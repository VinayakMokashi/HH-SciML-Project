# =============================================================================
#  src/experiment.jl  —  Parameterized experiment engine (Workstreams 2 & 3)
# =============================================================================
#  Depends on src/hh_core.jl and src/metrics.jl being included FIRST.
#
#  One entry point trains a UDE for any (gCa, noise_level, t_train_end, observed)
#  setting, scores it against the clean truth, and (optionally) saves figures and
#  a parameter snapshot.  `run_node_baseline` does the same for the black-box
#  Neural ODE.  Both turn the swept knobs into closure-captured locals — no
#  mutable globals in any ODE right-hand side.
# =============================================================================

using Lux, ComponentArrays
using Optimization, OptimizationOptimisers, OptimizationOptimJL
using SciMLSensitivity, Zygote
using DifferentialEquations
using StableRNGs
using Statistics
using DataFrames, CSV
using Plots
using Measures
import JLD
gr()

# --- Figure legibility (mentor request, 2026-08) -----------------------------
# Font sizes in Plots are relative to the CANVAS, so what reaches the page is
# fontsize/canvas_height x printed_height. These figures render ~820-900 px tall
# and are included at ~0.85\textwidth (~12 cm), so the old 11 pt defaults arrived
# at roughly 4.5 pt in print -- legible on screen, not on paper.
#
# The bump is deliberately MODEST (~1.3x, not the ~1.8x first tried). These are
# stacked multi-panel figures whose panels set their own left_margin, and at 1.8x
# the y-axis labels no longer fit it: "gate RMSE" rendered as "ate RMSE" and the
# normalised-calcium label collided with the panel above. Font size and margin
# have to move together, and the margins here are per-panel, so the ceiling is
# set by the tightest one. 1.3x clears them and still roughly doubles the printed
# text size relative to the original.
default(titlefontsize = 14, guidefontsize = 13, tickfontsize = 11,
        legendfontsize = 10, foreground_color_legend = nothing)

const PROJECT_DIR = dirname(@__DIR__)

# --- Output isolation: a dry run must not be able to touch released artifacts -
#  HH_SMOKE=1 cuts the iteration budgets, the ablation grids AND the seed list
#  (experiments_runner.jl:42-46,:45), so everything a smoke run produces is junk
#  next to the paper.  Until this change it wrote that junk straight into
#  results/ and figures/, and experiments_runner.jl:73 deletes METRICS_CSV
#  first: one accidental smoke run truncated the released results/metrics_all.csv
#  from 696 rows to 321 and rewrote 63 other tracked files.
#
#  Under HH_SMOKE the entire output tree moves to results_smoke/ + figures_smoke/.
#  This is the same isolation objective3_symbolic_retrain.jl:38-45 already applies
#  to its own run, and for the same stated reason: so that the canonical results/
#  and figures/ "are never overwritten".
#
#  HH_RESULTS_DIR / HH_FIG_DIR override either path explicitly; a relative value
#  is resolved against PROJECT_DIR.  With none of the three variables set the
#  paths are exactly the expressions they replaced, so a FULL run still writes
#  PROJECT_DIR/figures and PROJECT_DIR/results unchanged.
function _outdir(envvar::AbstractString, default::AbstractString)
    v = get(ENV, envvar, "")
    isempty(v) && return joinpath(PROJECT_DIR, default)
    return isabspath(v) ? v : joinpath(PROJECT_DIR, v)
end

const SMOKE_OUT   = get(ENV, "HH_SMOKE", "0") == "1"
const FIG_DIR     = _outdir("HH_FIG_DIR",     SMOKE_OUT ? "figures_smoke" : "figures")
const RESULTS_DIR = _outdir("HH_RESULTS_DIR", SMOKE_OUT ? "results_smoke" : "results")
const PARAMS_DIR  = joinpath(RESULTS_DIR, "params")
for d in (FIG_DIR, RESULTS_DIR, PARAMS_DIR); mkpath(d); end
if SMOKE_OUT
    @warn "HH_SMOKE=1 -- outputs isolated from the released tree." FIG_DIR RESULTS_DIR
end

const ADJOINT      = InterpolatingAdjoint(autojacvec = ReverseDiffVJP(true))
const METRICS_CSV  = joinpath(RESULTS_DIR, "metrics_all.csv")

# -----------------------------------------------------------------------------
#  Persistence: append tidy metric rows to the master CSV immediately after each
#  run (durable even if a later run crashes).  Uniform tidy schema -> safe append.
# -----------------------------------------------------------------------------
function append_metrics!(rows; path = METRICS_CSV)
    isempty(rows) && return path
    df = DataFrame(rows)
    CSV.write(path, df; append = isfile(path), writeheader = !isfile(path))
    return path
end

# -----------------------------------------------------------------------------
#  solve_aligned: integrate `rhs` over the full window and return a 6×DATASIZE
#  matrix aligned to TSTEPS.  If the solver bails early (or throws), the missing
#  tail is NaN-padded so downstream metrics/figures stay length-matched.
# -----------------------------------------------------------------------------
function solve_aligned(rhs, u0, p)
    full = fill(NaN, length(u0), DATASIZE)
    try
        sol = solve(ODEProblem(rhs, u0, TSPAN_FULL, p), Tsit5();
                    saveat = TSTEPS, abstol = 1e-8, reltol = 1e-8, verbose = false)
        arr = Array(sol)
        k   = min(size(arr, 2), DATASIZE)
        full[:, 1:k] .= arr[:, 1:k]
    catch err
        @warn "solve_aligned: full-span solve failed; returning NaN-padded prediction." exception = err
    end
    return full
end

# -----------------------------------------------------------------------------
#  Generic two-stage trainer (Adam warm-up -> BFGS polish in try/catch).
#  Returns the best parameters, the final loss, and whether BFGS succeeded.
# -----------------------------------------------------------------------------
function train_two_stage(loss_fn, p0; adam_lr = 1e-2, adam_iters = 5000,
                         bfgs_iters = 300, label = "train")
    adtype  = Optimization.AutoZygote()
    optf    = Optimization.OptimizationFunction((p, _) -> loss_fn(p), adtype)
    optprob = Optimization.OptimizationProblem(optf, p0)

    losses = Float64[]
    cb = function (state, l)
        push!(losses, l)
        length(losses) % 500 == 0 &&
            println("      [$label] iter $(length(losses))  loss = $(round(l, sigdigits = 4))")
        return false
    end

    res1    = Optimization.solve(optprob, OptimizationOptimisers.Adam(adam_lr);
                                 callback = cb, maxiters = adam_iters)
    p_final = res1.u
    bfgs_ok = false
    try
        optprob2 = Optimization.OptimizationProblem(optf, res1.u)
        res2     = Optimization.solve(optprob2,
                                      OptimizationOptimJL.BFGS(initial_stepnorm = 0.01);
                                      callback = cb, maxiters = bfgs_iters)
        p_final  = res2.u
        bfgs_ok  = true
    catch err
        @warn "[$label] BFGS polish failed; keeping Adam result." exception = err
    end
    return (; p = p_final, final_loss = isempty(losses) ? NaN : losses[end], bfgs_ok, losses)
end

# -----------------------------------------------------------------------------
#  Calcium network + UDE right-hand side (closure over the fresh network/state).
# -----------------------------------------------------------------------------
function make_ca_network(seed::Int)
    nn      = Lux.Chain(Lux.Dense(2, 16, tanh), Lux.Dense(16, 16, tanh), Lux.Dense(16, 1))
    p0, st  = Lux.setup(StableRNG(seed), nn)
    return nn, ComponentArray{Float64}(p0), st
end

# The UDE keeps ALL known physics; only I_Ca = gCa*s^2*(V-ECa) is replaced by the
# network (so gCa never appears here — it only shapes the TRUE data we fit to).
function make_hh_ude(nn_ca, st_ca)
    return function (du, u, theta, _t)
        V, m, h, n, p, s = u
        I_K   = gK   * n^4    * (V - EK)
        I_Na  = gNa  * m^3 * h * (V - ENa)
        I_L   = gL            * (V - EL)
        I_NaP = gNaP * p      * (V - ENa)
        I_Ca  = nn_ca([V / 100.0, s], theta, st_ca)[1][1]
        du[1] = (Iapp - I_K - I_Na - I_L - I_NaP - I_Ca) / Cm
        du[2] = alpha_m(V) * (1.0 - m) - beta_m(V) * m
        du[3] = alpha_h(V) * (1.0 - h) - beta_h(V) * h
        du[4] = alpha_n(V) * (1.0 - n) - beta_n(V) * n
        du[5] = alpha_p(V) * (1.0 - p) - beta_p(V) * p
        du[6] = alpha_s(V) * (1.0 - s) - beta_s(V) * s
        return nothing
    end
end

# Loss factory — the voltage-only switch is exactly one row selection.
function make_ude_loss(observed::Symbol, predict, data_noisy, train_idx)
    ntrain = length(train_idx)
    if observed == :voltage
        return function (p)
            pred = predict(p)
            size(pred, 2) == ntrain || return 1.0e6
            return sum(abs2, data_noisy[1:1, train_idx] .- pred[1:1, :])
        end
    else  # :full
        return function (p)
            pred = predict(p)
            size(pred, 2) == ntrain || return 1.0e6
            return sum(abs2, data_noisy[:, train_idx] .- pred)
        end
    end
end

# -----------------------------------------------------------------------------
#  Figure helpers (always savefig — never display-only).
# -----------------------------------------------------------------------------
# (row index, file suffix, y-axis label, descriptive title stem)
const _TRAJ_VARS = [(1, "voltage", "V (mV)",            "Membrane voltage"),
                    (2, "m", "m (dimensionless)",       "Na⁺ activation gate m"),
                    (3, "h", "h (dimensionless)",       "Na⁺ inactivation gate h"),
                    (4, "n", "n (dimensionless)",       "K⁺ activation gate n"),
                    (5, "p", "p (dimensionless)",       "Persistent-Na⁺ gate p"),
                    (6, "s", "s (dimensionless)",       "Calcium gate s")]

# Data-driven y-limits: frame the TRUTH range with padding so each variable fills
# its panel (fixes the squashed small-amplitude gates s/h/p).  A model whose
# forecast diverges (the black-box NODE) simply runs off-panel — which reads as
# "diverged" while keeping the in-range fit legible.
function _ylims_data(x; pad = 0.08)
    lo, hi = minimum(x), maximum(x)
    sp = hi - lo
    sp == 0 && (sp = max(abs(hi), 1.0))
    return (lo - pad * sp, hi + pad * sp)
end

function save_trajectory_figs(prefix, model_label, data_clean, pred, t_train_end)
    for (i, suffix, ylab, stem) in _TRAJ_VARS
        plt = plot(TSTEPS, data_clean[i, :], lw = 2, label = "truth",
                   xlabel = "t (ms)", ylabel = ylab, title = "$stem : truth vs $model_label",
                   legend = :outertopright, ylims = _ylims_data(data_clean[i, :]),
                   left_margin = 4mm, bottom_margin = 3mm)
        plot!(plt, TSTEPS, pred[i, :], lw = 2, ls = :dash, label = model_label)
        vline!(plt, [t_train_end], lw = 2, color = :gray, ls = :dot, label = "train | forecast")
        savefig(plt, joinpath(FIG_DIR, "$(prefix)_$(suffix).png"))
    end
    # stacked overview — per-group y-limits from the truth range
    ov_V = plot(TSTEPS, data_clean[1, :], lw = 2, label = "V truth", ylabel = "V (mV)",
                title = "$model_label : state reconstruction (truth vs $model_label)",
                legend = :outertopright, ylims = _ylims_data(data_clean[1, :]), left_margin = 8mm)
    plot!(ov_V, TSTEPS, pred[1, :], lw = 2, ls = :dash, label = "V $model_label")
    ov_cls = plot(ylabel = "classical gates m,h,n\n(dimensionless)", left_margin = 8mm,
                  ylims = _ylims_data(data_clean[2:4, :]), legend = :outertopright)
    ov_adv = plot(xlabel = "t (ms)", ylabel = "advanced gates p,s\n(dimensionless)", left_margin = 8mm,
                  ylims = _ylims_data(data_clean[5:6, :]), legend = :outertopright)
    for (i, nm, c) in [(2, "m", "#D85A30"), (3, "h", "#0F6E56"), (4, "n", "#534AB7")]
        plot!(ov_cls, TSTEPS, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
        plot!(ov_cls, TSTEPS, pred[i, :], lw = 2, ls = :dash, color = c, label = "$nm $model_label")
    end
    for (i, nm, c) in [(5, "p", "#BA7517"), (6, "s", "#993556")]
        plot!(ov_adv, TSTEPS, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
        plot!(ov_adv, TSTEPS, pred[i, :], lw = 2, ls = :dash, color = c, label = "$nm $model_label")
    end
    # label the train|forecast divider once (top panel) so the overview explains it
    vline!(ov_V, [t_train_end], lw = 1.5, color = :gray, ls = :dot, label = "train | forecast")
    vline!(ov_cls, [t_train_end], lw = 1.5, color = :gray, ls = :dot, label = "")
    vline!(ov_adv, [t_train_end], lw = 1.5, color = :gray, ls = :dot, label = "")
    fig = plot(ov_V, ov_cls, ov_adv, layout = (3, 1), size = (950, 820), link = :x)
    savefig(fig, joinpath(FIG_DIR, "$(prefix)_overview.png"))
    return nothing
end

function save_calcium_parity(prefix, ICa_true, ICa_nn)
    good = isfinite.(ICa_true) .& isfinite.(ICa_nn)
    r    = rmse_safe(ICa_true, ICa_nn)
    lo   = min(minimum(ICa_true[good]), minimum(ICa_nn[good]))
    hi   = max(maximum(ICa_true[good]), maximum(ICa_nn[good]))
    pad  = 0.05 * (hi - lo)
    lims = (lo - pad, hi + pad)
    plt = scatter(ICa_true, ICa_nn, ms = 2.5, alpha = 0.5, label = "per-timestep samples",
                  xlabel = "I(Ca) truth (μA/cm²)", ylabel = "I(Ca) network (μA/cm²)",
                  title = "Calcium-current parity   (RMSE = $(round(r, sigdigits = 3)) μA/cm²)",
                  legend = :bottomright, aspect_ratio = :equal, xlims = lims, ylims = lims,
                  left_margin = 4mm, bottom_margin = 3mm)
    plot!(plt, [lims...], [lims...], lw = 2, color = :black, ls = :dash, label = "ideal  y = x")
    savefig(plt, joinpath(FIG_DIR, "$(prefix)_calcium_parity.png"))
    return nothing
end

# --- Calcium-current probe savers (raw data for Objective 3 / SINDy) ----------
#  The learned calcium term is otherwise only turned into a figure + one RMSE.
#  These persist the underlying (input -> output) data so symbolic recovery needs
#  no retraining.  Files land under results/calcium/.
const CALCIUM_DIR = joinpath(RESULTS_DIR, "calcium")

# Build a unique run id for calcium filenames.  Non-representative seeds already
# carry "_seed<n>" in their tag; the representative seed's tag does not — so append
# the seed only when it isn't already there (avoids "..._seed3333_seed3333").
_calcium_id(tag, seed) = occursin(r"_seed\d+$", tag) ? tag : "$(tag)_seed$(seed)"

# On-trajectory samples: the learned I_Ca and the true I_Ca at every timestep,
# with the network inputs (V, s and the V/100 normalisation the net actually sees).
function save_calcium_probe(tag, seed, t, V, s, Vnorm, ICa_true, ICa_nn)
    isempty(tag) && return nothing
    mkpath(CALCIUM_DIR)
    df = DataFrame(t = collect(t), V = collect(V), s = collect(s), V_norm = collect(Vnorm),
                   ICa_true = collect(ICa_true), ICa_nn = collect(ICa_nn))
    CSV.write(joinpath(CALCIUM_DIR, "probe_$(_calcium_id(tag, seed)).csv"), df)
    return nothing
end

# Off-trajectory grid: the learned network sampled on a regular (V, s) grid over
# the observed domain, so symbolic regression is not confined to the on-trajectory
# manifold.  ICa_true here is the analytic gCa*s^2*(V-ECa) on the same grid.
function save_calcium_grid_probe(nn, p_ca, st_ca, gCa, tag, seed, Vtraj, straj; nV = 80, ns = 80)
    isempty(tag) && return nothing
    mkpath(CALCIUM_DIR)
    Vgrid = range(minimum(Vtraj), maximum(Vtraj); length = nV)
    sgrid = range(minimum(straj), maximum(straj); length = ns)
    rows = NamedTuple[]
    for Vv in Vgrid, sv in sgrid
        inn   = nn([Vv / 100.0, sv], p_ca, st_ca)[1][1]
        itrue = gCa * sv^2 * (Vv - ECa)
        push!(rows, (; V = Vv, s = sv, V_norm = Vv / 100.0, ICa_true = itrue, ICa_nn = inn))
    end
    CSV.write(joinpath(CALCIUM_DIR, "grid_$(_calcium_id(tag, seed)).csv"), DataFrame(rows))
    return nothing
end

# --- Regeneration helpers (rebuild figures from saved params — no retraining) -
function load_ude_params(tag, seed)
    nn, p_template, st = make_ca_network(seed)
    loaded = JLD.load(joinpath(PARAMS_DIR, "ude_$(tag).jld"), "p_ca")
    p = copy(p_template); p .= loaded            # same flat order as Vector(p_ca)
    return nn, p, st
end

function regenerate_ude_figs(tag, fig_prefix; gCa, noise_level, t_train_end, seed)
    data_clean   = gen_clean_data(gCa).data_clean
    nn, p_ca, st = load_ude_params(tag, seed)
    rhs  = make_hh_ude(nn, st)
    pred = solve_aligned(rhs, steady_state_u0(), p_ca)
    Vt = data_clean[1, :]; s = data_clean[6, :]; Vn = Vt ./ 100.0
    ICa_nn   = [nn([Vn[i], s[i]], p_ca, st)[1][1] for i in eachindex(Vt)]
    ICa_true = gCa .* s .^ 2 .* (Vt .- ECa)
    save_trajectory_figs(fig_prefix, "UDE", data_clean, pred, t_train_end)
    save_calcium_parity(fig_prefix, ICa_true, ICa_nn)
    save_calcium_probe(tag, seed, TSTEPS, Vt, s, Vn, ICa_true, ICa_nn)
    save_calcium_grid_probe(nn, p_ca, st, gCa, tag, seed, Vt, s)
    return nothing
end

# --- Dynamics figures 01–08 (regenerated from the engine, improved styling) ---
function save_dynamics_figs(; gCa = 2.0, noise_level = 0.02, seed = 1111)
    dc = gen_clean_data(gCa).data_clean
    dn = gen_noisy_data(dc, noise_level; seed = seed)
    specs = [(1, "01_Membrane_Potential",  "V (mV)",            "Membrane potential V(t) (advanced HH)", "#185FA5"),
             (2, "02_Na_activation_m",      "m (dimensionless)", "Na⁺ activation gate m",      "#D85A30"),
             (3, "03_Na_inactivation_h",    "h (dimensionless)", "Na⁺ inactivation gate h",    "#0F6E56"),
             (4, "04_K_activation_n",       "n (dimensionless)", "K⁺ activation gate n",       "#534AB7"),
             (5, "05_Persistent_Na_p",      "p (dimensionless)", "Persistent-Na⁺ gate p",      "#BA7517"),
             (6, "06_Calcium_s",            "s (dimensionless)", "Calcium gate s",             "#993556")]
    for (i, fname, ylab, ttl, col) in specs
        plt = plot(TSTEPS, dc[i, :], lw = 2, color = col, legend = false, xlabel = "t (ms)",
                   ylabel = ylab, title = ttl, ylims = _ylims_data(dc[i, :]),
                   left_margin = 4mm, bottom_margin = 3mm)
        savefig(plt, joinpath(FIG_DIR, "$(fname).png"))
    end
    # 07 stacked overview
    ov_V = plot(TSTEPS, dc[1, :], lw = 2, color = "#185FA5", label = "V", ylabel = "V (mV)",
                ylims = _ylims_data(dc[1, :]), legend = :outertopright, left_margin = 8mm)
    ov_cls = plot(ylabel = "classical gates m,h,n\n(dimensionless)", left_margin = 8mm,
                  ylims = _ylims_data(dc[2:4, :]), legend = :outertopright)
    for (i, nm, c) in [(2, "m", "#D85A30"), (3, "h", "#0F6E56"), (4, "n", "#534AB7")]
        plot!(ov_cls, TSTEPS, dc[i, :], lw = 2, color = c, label = nm)
    end
    ov_adv = plot(xlabel = "t (ms)", ylabel = "advanced gates p,s\n(dimensionless)", left_margin = 8mm,
                  ylims = _ylims_data(dc[5:6, :]), legend = :outertopright)
    for (i, nm, c) in [(5, "p", "#BA7517"), (6, "s", "#993556")]
        plot!(ov_adv, TSTEPS, dc[i, :], lw = 2, color = c, label = nm)
    end
    savefig(plot(ov_V, ov_cls, ov_adv, layout = (3, 1), size = (950, 820), link = :x),
            joinpath(FIG_DIR, "07_Stacked_Overview.png"))
    # 08 noisy data vs truth (voltage)
    f8 = plot(TSTEPS, dc[1, :], lw = 2, color = "#185FA5", label = "V (truth)",
              xlabel = "t (ms)", ylabel = "V (mV)", title = "Advanced HH : true dynamics + noisy data",
              legend = :outertopright, ylims = _ylims_data(dc[1, :]), left_margin = 4mm, bottom_margin = 3mm)
    scatter!(f8, TSTEPS, dn[1, :], ms = 1.8, alpha = 0.45, label = "V (noisy data)",
             color = :darkorange, markerstrokewidth = 0)
    savefig(f8, joinpath(FIG_DIR, "08_Noisy_Data_Comparison.png"))
    return nothing
end

function snapshot_params(tag, p_ca)
    isempty(tag) && return nothing
    try
        JLD.save(joinpath(PARAMS_DIR, "ude_$(tag).jld"), "p_ca", Vector(p_ca))
    catch err
        @warn "snapshot_params: could not write JLD snapshot." exception = err
    end
    return nothing
end

# -----------------------------------------------------------------------------
#  run_experiment — train + score one UDE setting.
# -----------------------------------------------------------------------------
function run_experiment(; gCa = 2.0, noise_level = 0.02, t_train_end = 30.0,
                          observed = :full, seed = 1111,
                          adam_iters = 5000, bfgs_iters = 300,
                          make_figs = false, tag = "", fig_prefix = "",
                          common_eval_start = nothing)
    println("[run_experiment] gCa=$gCa noise=$noise_level t_train=$t_train_end observed=$observed tag=$tag")
    data_clean = gen_clean_data(gCa).data_clean
    data_noisy = gen_noisy_data(data_clean, noise_level; seed = seed)
    split      = make_split(t_train_end)
    u0         = steady_state_u0()

    nn_ca, p_ca0, st_ca = make_ca_network(seed)
    rhs  = make_hh_ude(nn_ca, st_ca)
    prob = ODEProblem(rhs, u0, split.tspan_train, p_ca0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))
    loss_fn = make_ude_loss(observed, predict, data_noisy, split.train_idx)

    tr   = train_two_stage(loss_fn, p_ca0; adam_lr = 1e-2, adam_iters = adam_iters,
                           bfgs_iters = bfgs_iters, label = "UDE")
    p_ca = tr.p

    pred_full = solve_aligned(rhs, u0, p_ca)

    # probe the learned calcium current along the TRUE trajectory
    Vt = data_clean[1, :]; st_ = data_clean[6, :]; Vn = Vt ./ 100.0
    ICa_nn   = [nn_ca([Vn[i], st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]
    ICa_true = gCa .* st_ .^ 2 .* (Vt .- ECa)

    cidx = common_eval_start === nothing ? nothing : common_eval_indices(Float64(common_eval_start))
    metrics = compute_metrics(; model = "UDE", observed = observed, gCa = gCa,
                                noise_level = noise_level, t_train_end = t_train_end, seed = seed,
                                t = TSTEPS, truth = data_clean, pred = pred_full,
                                train_idx = split.train_idx, forecast_idx = split.forecast_idx,
                                truth_noisy = data_noisy, ICa_true = ICa_true, ICa_nn = ICa_nn,
                                common_idx = cidx)

    if make_figs
        prefix = !isempty(fig_prefix) ? fig_prefix :
                 (isempty(tag) ? "fig_ude" : "fig_$(tag)")
        save_trajectory_figs(prefix, "UDE", data_clean, pred_full, t_train_end)
        save_calcium_parity(prefix, ICa_true, ICa_nn)
    end
    snapshot_params(tag, p_ca)
    save_calcium_probe(tag, seed, TSTEPS, Vt, st_, Vn, ICa_true, ICa_nn)
    save_calcium_grid_probe(nn_ca, p_ca, st_ca, gCa, tag, seed, Vt, st_)

    return (; gCa, noise_level, t_train_end, observed, seed, p_ca,
              final_loss = tr.final_loss, bfgs_ok = tr.bfgs_ok,
              pred_full, ICa_true, ICa_nn, metrics, data_clean, data_noisy)
end

# -----------------------------------------------------------------------------
#  run_node_baseline — black-box Neural ODE (Objective 1) metrics, for the
#  headline NODE-vs-UDE comparison.  Normalised coords, time as an input.
# -----------------------------------------------------------------------------
function run_node_baseline(; gCa = 2.0, noise_level = 0.02, t_train_end = 30.0, seed = 1111,
                             adam_iters = 3000, bfgs_iters = 300, make_figs = true,
                             prefix = "fig2_neural_ode")
    println("[run_node_baseline] gCa=$gCa noise=$noise_level t_train=$t_train_end")
    data_clean = gen_clean_data(gCa).data_clean
    data_noisy = gen_noisy_data(data_clean, noise_level; seed = seed)
    split      = make_split(t_train_end)
    norm_noisy = data_noisy ./ SCALE
    u0n        = steady_state_u0() ./ SCALE

    nn      = Lux.Chain(Lux.Dense(7, 64, tanh), Lux.LayerNorm((64,)),
                        Lux.Dense(64, 64, tanh), Lux.LayerNorm((64,)), Lux.Dense(64, 6))
    p0, stn = Lux.setup(StableRNG(seed), nn)
    p0      = ComponentArray{Float64}(p0)
    rhs = function (du, u, p, t)
        du .= vec(nn(reshape(vcat(u, t), :, 1), p, stn)[1]); return nothing
    end
    prob = ODEProblem(rhs, u0n, split.tspan_train, p0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))
    ntrain = length(split.train_idx)
    loss_fn(p) = (pred = predict(p); size(pred, 2) == ntrain ?
                  sum(abs2, norm_noisy[:, split.train_idx] .- pred) : 1.0e6)

    tr     = train_two_stage(loss_fn, p0; adam_lr = 1e-2, adam_iters = adam_iters,
                             bfgs_iters = bfgs_iters, label = "NODE")
    p_node = tr.p

    pred_full = solve_aligned(rhs, u0n, p_node) .* SCALE     # de-normalise

    metrics = compute_metrics(; model = "NODE", observed = "full", gCa = gCa,
                                noise_level = noise_level, t_train_end = t_train_end, seed = seed,
                                t = TSTEPS, truth = data_clean, pred = pred_full,
                                train_idx = split.train_idx, forecast_idx = split.forecast_idx,
                                truth_noisy = data_noisy)

    make_figs && save_trajectory_figs(prefix, "Neural ODE", data_clean, pred_full, t_train_end)

    return (; p_node, final_loss = tr.final_loss, bfgs_ok = tr.bfgs_ok, pred_full, metrics)
end
