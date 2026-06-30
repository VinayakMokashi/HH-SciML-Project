# =============================================================================
#  experiments_runner.jl  —  end-to-end experiment sweep
# =============================================================================
#  Produces the mentor-requested quantitative evidence (Objective 3 excluded):
#    * baseline metrics for the Neural ODE and the full-state UDE
#    * a voltage-only UDE (only V observed; gates hidden but physics-evolved)
#    * one-axis ablations over noise level, training-window length, and gCa
#
#  Everything is SAVED: all metric values to results/*.csv, all plots to
#  figures/*.png.  Nothing is left console-only or display-only.  A final
#  assert_outputs() fails loudly if any expected artifact is missing.
#
#  RUN:
#    julia --project=. experiments_runner.jl              # full (~2-3 h)
#    HH_SMOKE=1 julia --project=. experiments_runner.jl   # fast pipeline check
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV, Plots, Statistics, Measures
gr()

const SMOKE  = get(ENV, "HH_SMOKE",  "0") == "1"
const REPLOT = get(ENV, "HH_REPLOT", "0") == "1"   # regenerate CSVs+figures only, no retraining

# Iteration budgets + sweep grids (reduced under SMOKE for a quick dry run).
const UDE_ADAM,  UDE_BFGS  = SMOKE ? (60, 5)  : (5000, 300)
const NODE_ADAM, NODE_BFGS = SMOKE ? (40, 3)  : (3000, 300)
const NOISE_EXTRA  = SMOKE ? [0.0, 0.05]        : [0.0, 0.01, 0.05, 0.10]
const WINDOW_EXTRA = SMOKE ? [20.0, 40.0]       : [15.0, 20.0, 40.0, 50.0]
const GCA_EXTRA    = SMOKE ? [0.4, 4.0]         : [0.4, 1.0, 4.0]

# Shared baseline (the center point of every ablation axis).
const B_GCA, B_NOISE, B_TWIN, B_SEED = 2.0, 0.02, 30.0, 1111

# Guard each run so one failure never aborts the whole sweep.
function safe_run(f, label)
    try
        return f()
    catch err
        @warn "RUN FAILED: $label — continuing." exception = (err, catch_backtrace())
        return nothing
    end
end

# Training/sweep — skipped under HH_REPLOT=1, which only rebuilds the derived
# CSVs and summary figures from an existing results/metrics_all.csv (no retrain).
if !REPLOT
isfile(METRICS_CSV) && rm(METRICS_CSV)   # fresh master table each full run

# =============================================================================
#  1. Baselines  (NODE + full-state UDE)
# =============================================================================
println("\n########## BASELINES ##########")
safe_run("NODE baseline") do
    r = run_node_baseline(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                            seed = B_SEED, adam_iters = NODE_ADAM, bfgs_iters = NODE_BFGS,
                            make_figs = true, prefix = "fig2_neural_ode")
    append_metrics!(r.metrics)
end
base = safe_run("UDE full baseline") do
    r = run_experiment(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                         observed = :full, seed = B_SEED,
                         adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS,
                         make_figs = true, tag = "ude_full", fig_prefix = "fig3_ude")
    append_metrics!(r.metrics); r
end

# =============================================================================
#  2. Voltage-only UDE  (Workstream 2)
# =============================================================================
println("\n########## VOLTAGE-ONLY UDE ##########")
safe_run("voltage-only UDE") do
    r = run_experiment(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                         observed = :voltage, seed = B_SEED,
                         adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS,
                         make_figs = true, tag = "voltage_only", fig_prefix = "fig6_voltage_only")
    append_metrics!(r.metrics)
end

# =============================================================================
#  3. Ablations  (one axis at a time; baseline is the shared center point)
# =============================================================================
println("\n########## ABLATIONS ##########")
for nl in NOISE_EXTRA
    safe_run("ablation noise=$nl") do
        r = run_experiment(; gCa = B_GCA, noise_level = nl, t_train_end = B_TWIN,
                             observed = :full, seed = B_SEED,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS, tag = "abl_noise_$(nl)")
        append_metrics!(r.metrics)
    end
end
for tw in WINDOW_EXTRA
    safe_run("ablation t_train=$tw") do
        r = run_experiment(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = tw,
                             observed = :full, seed = B_SEED,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS, tag = "abl_window_$(tw)")
        append_metrics!(r.metrics)
    end
end
for g in GCA_EXTRA
    safe_run("ablation gCa=$g") do
        r = run_experiment(; gCa = g, noise_level = B_NOISE, t_train_end = B_TWIN,
                             observed = :full, seed = B_SEED,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS, tag = "abl_gca_$(g)")
        append_metrics!(r.metrics)
    end
end

end  # if !REPLOT

# =============================================================================
#  4. Derived CSVs + summary figures  (read the master table back)
# =============================================================================
println("\n########## SUMMARISING ##########")
df = CSV.read(METRICS_CSV, DataFrame)

# scalar lookup against the tidy master table
function scalar(df; kw...)
    mask = trues(nrow(df))
    for (k, v) in kw
        mask .&= (df[!, k] .== v)
    end
    sub = df[mask, :]
    return nrow(sub) == 0 ? NaN : Float64(sub.value[1])
end

# (xs, ys) for a swept axis (UDE, full, fixed other two params)
function axis_series(df, axiscol, metric; window = "forecast",
                     gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    mask = (df.model .== "UDE") .& (df.observed .== "full") .&
           (df.window .== window) .& (df.metric .== metric)
    fixed = Dict(:gCa => gCa, :noise_level => noise_level, :t_train_end => t_train_end)
    delete!(fixed, axiscol)
    for (k, v) in fixed; mask .&= (df[!, k] .== v); end
    sub   = df[mask, :]
    order = sortperm(Float64.(sub[!, axiscol]))
    return Float64.(sub[order, axiscol]), Float64.(sub.value[order])
end

# --- metrics_baseline.csv (wide: NODE & UDE rows × window_metric cols) -------
let
    p = (df.observed .== "full") .& (df.gCa .== B_GCA) .&
        (df.noise_level .== B_NOISE) .& (df.t_train_end .== B_TWIN) .&
        ((df.model .== "NODE") .| (df.model .== "UDE"))
    sub = df[p, :]
    sub.key = string.(sub.window, "_", sub.metric)
    wide = unstack(sub, :model, :key, :value)
    CSV.write(joinpath(RESULTS_DIR, "metrics_baseline.csv"), wide)
end

# --- ablation_*.csv (wide: swept value × window_metric cols) -----------------
function write_ablation_csv(df, axiscol, fname; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    mask = (df.model .== "UDE") .& (df.observed .== "full")
    fixed = Dict(:gCa => gCa, :noise_level => noise_level, :t_train_end => t_train_end)
    delete!(fixed, axiscol)
    for (k, v) in fixed; mask .&= (df[!, k] .== v); end
    sub = df[mask, :]
    sub.key = string.(sub.window, "_", sub.metric)
    wide = unstack(sub, axiscol, :key, :value)
    sort!(wide, axiscol)
    CSV.write(joinpath(RESULTS_DIR, fname), wide)
end
write_ablation_csv(df, :noise_level, "ablation_noise.csv")
write_ablation_csv(df, :t_train_end, "ablation_window.csv")
write_ablation_csv(df, :gCa,         "ablation_gca.csv")

# log-scale bar with the numeric value printed atop each bar (so magnitudes are
# unambiguous despite the huge NODE-vs-UDE dynamic range).  Numeric x + padded
# xlims keep edge labels from clipping; labels hug each bar top (valign=:bottom)
# and the top headroom (×25) leaves room for the tallest label.
function logbar(labels, vals, ttl, ylab, colors)
    n = length(vals); v = max.(vals, 1e-4)
    fin = filter(isfinite, v)                       # a missing run -> NaN; don't let it poison ylims
    lo  = isempty(fin) ? 1e-4 : minimum(fin)
    hi  = isempty(fin) ? 1.0  : maximum(fin)
    p = bar(1:n, v; legend=false, ylabel=ylab, yscale=:log10, title=ttl, color=colors,
            xticks=(1:n, labels), xlims=(0.3, n+0.7), ylims=(lo*0.35, hi*25),
            bar_width=0.62, left_margin=9mm, bottom_margin=7mm, right_margin=6mm)
    for (x, raw) in enumerate(vals)
        isfinite(raw) || continue                   # skip labels for missing values
        annotate!(p, x, max(raw, 1e-4)*1.35, text(string(round(raw, sigdigits=3)), 8, :center, :bottom))
    end
    return p
end

# --- fig5: train-vs-forecast RMSE bars, NODE vs UDE (log y + value labels) ----
let
    labels = ["NODE\ntrain", "NODE\nforecast", "UDE\ntrain", "UDE\nforecast"]
    cols   = [:steelblue, :steelblue, :seagreen, :seagreen]
    pull(model, w, m) = scalar(df; model=model, observed="full", window=w, metric=m,
                              gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN)
    vrmse = [pull("NODE","train","V_rmse"), pull("NODE","forecast","V_rmse"),
             pull("UDE","train","V_rmse"),  pull("UDE","forecast","V_rmse")]
    grmse = [pull("NODE","train","gate_rmse_mean"), pull("NODE","forecast","gate_rmse_mean"),
             pull("UDE","train","gate_rmse_mean"),  pull("UDE","forecast","gate_rmse_mean")]
    p1 = logbar(labels, vrmse, "Voltage RMSE vs clean truth", "V RMSE (mV, log scale)", cols)
    p2 = logbar(labels, grmse, "Gating-variable RMSE",        "gate RMSE (log scale)",  cols)
    savefig(plot(p1, p2, layout=(1,2), size=(1050,470)),
            joinpath(FIG_DIR, "fig5_metrics_bar_train_vs_forecast.png"))
end

# --- fig7*: ablation curves (forecast window) --------------------------------
# Each metric gets its OWN panel (own y-scale) so the small gate-RMSE is never
# crushed against the larger V-RMSE, and no legend is needed (title + y-label
# describe each single-series panel). x-ticks sit exactly on the sampled values.
function ablation_fig(axiscol, xlab, fname; extra_metric = nothing, extra_lab = "", xt = :auto)
    xv, vr = axis_series(df, axiscol, "V_rmse")
    _,  gr = axis_series(df, axiscol, "gate_rmse_mean")
    _,  rh = axis_series(df, axiscol, "rollout_horizon_ms")
    common = (; xlabel=xlab, legend=false, marker=:circle, lw=2,
                left_margin=8mm, bottom_margin=5mm, xticks=xt)
    p1 = plot(xv, vr; ylabel="forecast V RMSE (mV)", title="Voltage forecast error",
              color=:dodgerblue, common...)
    p2 = plot(xv, gr; ylabel="forecast gate RMSE", title="Gating-variable forecast error",
              color=:seagreen, common...)
    p3 = plot(xv, rh; ylabel="rollout horizon (ms)", title="Forecast validity (rollout, capped at 70 ms)",
              color=:purple, ylims=(0, 75), common...)
    panels = Any[p1, p2, p3]
    if extra_metric !== nothing
        _, ev = axis_series(df, axiscol, extra_metric)
        p4 = plot(xv, ev; ylabel=extra_lab, title="Calcium-current identifiability (lower = better)",
                  color=:darkorange, common...)
        push!(panels, p4)
    end
    savefig(plot(panels..., layout=(length(panels), 1), size=(840, 290 * length(panels))),
            joinpath(FIG_DIR, fname))
end
ablation_fig(:noise_level, "noise level (relative)", "fig7_ablation_noise.png";
             xt=([0.0,0.01,0.02,0.05,0.10], ["0","0.01","0.02","0.05","0.10"]))
ablation_fig(:t_train_end, "training-window length (ms)", "fig7b_ablation_window.png";
             xt=([15,20,30,40,50], ["15","20","30","40","50"]))
ablation_fig(:gCa, "gCa (calcium strength)", "fig7c_ablation_gca.png";
             extra_metric="ICa_rmse_norm", extra_lab="I(Ca) RMSE / std (normalised)",
             xt=([0.4,1.0,2.0,4.0], ["0.4","1.0","2.0","4.0"]))

# --- fig8: full vs voltage-only, forecast metrics ----------------------------
let
    getm(obs, m) = scalar(df; model="UDE", observed=obs, window="forecast", metric=m,
                          gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN)
    specs = [("V_rmse",         "Voltage error",   "forecast V RMSE (mV)"),
             ("gate_rmse_mean", "Gating error",    "forecast gate RMSE (dimensionless)"),
             ("ICa_rmse",       "Calcium current", "forecast I(Ca) RMSE (μA/cm²)")]
    panels = []
    for (m, ttl, ylab) in specs
        vals    = [getm("full", m), getm("voltage", m)]
        heights = [isfinite(v) ? max(v, 0.0) : 0.0 for v in vals]   # missing run -> 0 bar, not NaN
        fin     = filter(isfinite, vals)
        top     = (isempty(fin) ? 1.0 : maximum(fin)) * 1.3
        push!(panels, bar(["full", "voltage-only"], heights; legend=false,
                          title=ttl, ylabel=ylab, color=[:seagreen, :darkorange],
                          ylims=(0, top), left_margin=9mm, bottom_margin=8mm))
    end
    savefig(plot(panels..., layout=(1,3), size=(1180,460)),
            joinpath(FIG_DIR, "fig8_full_vs_voltage_metrics_bar.png"))
end

# --- dynamics figures 01-08 (always; improved labels + headroom) -------------
save_dynamics_figs(; gCa=B_GCA, noise_level=B_NOISE, seed=B_SEED)

# In REPLOT mode the per-run trajectory/parity figures weren't produced by a
# training pass, so rebuild them: UDE figs from saved params, NODE via a re-fit
# (deterministic seed -> identical result, no params snapshot exists for it).
if REPLOT
    regenerate_ude_figs("ude_full", "fig3_ude";
                        gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN, seed=B_SEED)
    regenerate_ude_figs("voltage_only", "fig6_voltage_only";
                        gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN, seed=B_SEED)
    run_node_baseline(; gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN, seed=B_SEED,
                        adam_iters=NODE_ADAM, bfgs_iters=NODE_BFGS, make_figs=true,
                        prefix="fig2_neural_ode")
end

# =============================================================================
#  5. assert_outputs — fail loudly if any expected artifact is missing
# =============================================================================
function assert_outputs()
    csvs = ["metrics_all.csv", "metrics_baseline.csv",
            "ablation_noise.csv", "ablation_window.csv", "ablation_gca.csv"]
    figs = ["01_Membrane_Potential.png","02_Na_activation_m.png","03_Na_inactivation_h.png",
            "04_K_activation_n.png","05_Persistent_Na_p.png","06_Calcium_s.png",
            "07_Stacked_Overview.png","08_Noisy_Data_Comparison.png"]
    for suf in ["voltage","m","h","n","p","s","overview"]
        push!(figs, "fig2_neural_ode_$(suf).png")
        push!(figs, "fig3_ude_$(suf).png")
        push!(figs, "fig6_voltage_only_$(suf).png")
    end
    append!(figs, ["fig3_ude_calcium_parity.png", "fig6_voltage_only_calcium_parity.png",
                   "fig5_metrics_bar_train_vs_forecast.png",
                   "fig7_ablation_noise.png", "fig7b_ablation_window.png", "fig7c_ablation_gca.png",
                   "fig8_full_vs_voltage_metrics_bar.png"])
    missing = String[]
    for c in csvs; isfile(joinpath(RESULTS_DIR, c)) || push!(missing, "results/$c"); end
    for f in figs; isfile(joinpath(FIG_DIR, f))     || push!(missing, "figures/$f"); end
    if isempty(missing)
        println("\n✓ assert_outputs: all ", length(csvs), " CSVs and ", length(figs), " figures present.")
    else
        println("\n✗ assert_outputs: MISSING ", length(missing), " artifact(s):")
        foreach(m -> println("    - ", m), missing)
        error("assert_outputs failed: $(length(missing)) missing artifact(s).")
    end
end
assert_outputs()

# --- headline summary to console ---------------------------------------------
println("\n========== HEADLINE (forecast window, vs clean truth) ==========")
for (model, obs) in (("NODE","full"), ("UDE","full"), ("UDE","voltage"))
    v  = scalar(df; model=model, observed=obs, window="forecast", metric="V_rmse",         gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN)
    g  = scalar(df; model=model, observed=obs, window="forecast", metric="gate_rmse_mean", gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN)
    rh = scalar(df; model=model, observed=obs, window="forecast", metric="rollout_horizon_ms", gCa=B_GCA, noise_level=B_NOISE, t_train_end=B_TWIN)
    println(rpad("$model/$obs", 14), "  V_rmse=", rpad(round(v, sigdigits=4), 10),
            "gate_rmse=", rpad(round(g, sigdigits=4), 10), "rollout=", round(rh, sigdigits=4), " ms")
end
println("\n", SMOKE ? "[SMOKE run complete]" : "[FULL run complete]", "  metrics -> results/  figures -> figures/")
