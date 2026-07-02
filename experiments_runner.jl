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

# Seeds for the multi-seed headline runs (mentor request: report mean±std over
# several random inits).  Only the three headline runs — NODE baseline, UDE
# full-state, voltage-only — are repeated; the ablations stay single-seed at
# B_SEED.  REP_SEED supplies the single-seed trajectory/parity panels; it is the
# pre-registered baseline seed (chosen before the spread was known), guarded
# post-hoc against being an outlier (see the representative-seed guardrail below).
const SEEDS    = SMOKE ? [1111, 2222] : [1111, 2222, 3333, 4444, 5555]
const REP_SEED = B_SEED

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
#  1. Baselines  (NODE + full-state UDE)  — repeated over SEEDS
# =============================================================================
#  Only REP_SEED writes the trajectory/parity figures (the panels are per-run
#  visuals); every seed appends its metrics.  REP_SEED keeps the canonical param
#  tags ("ude_full"/"voltage_only") so the HH_REPLOT regeneration path is
#  unchanged; other seeds get seed-suffixed tags so all snapshots persist.
println("\n########## BASELINES (multi-seed) ##########")
for sd in SEEDS
    isrep = (sd == REP_SEED)
    safe_run("NODE baseline seed=$sd") do
        r = run_node_baseline(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                                seed = sd, adam_iters = NODE_ADAM, bfgs_iters = NODE_BFGS,
                                make_figs = isrep, prefix = "fig2_neural_ode")
        append_metrics!(r.metrics)
    end
    safe_run("UDE full baseline seed=$sd") do
        r = run_experiment(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                             observed = :full, seed = sd,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS,
                             make_figs = isrep,
                             tag = isrep ? "ude_full" : "ude_full_seed$(sd)",
                             fig_prefix = "fig3_ude",
                             common_eval_start = COMMON_EVAL_START)
        append_metrics!(r.metrics)
    end
end

# =============================================================================
#  2. Voltage-only UDE  (Workstream 2)  — repeated over SEEDS
# =============================================================================
println("\n########## VOLTAGE-ONLY UDE (multi-seed) ##########")
for sd in SEEDS
    isrep = (sd == REP_SEED)
    safe_run("voltage-only UDE seed=$sd") do
        r = run_experiment(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                             observed = :voltage, seed = sd,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS,
                             make_figs = isrep,
                             tag = isrep ? "voltage_only" : "voltage_only_seed$(sd)",
                             fig_prefix = "fig6_voltage_only")
        append_metrics!(r.metrics)
    end
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
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS, tag = "abl_window_$(tw)",
                             common_eval_start = COMMON_EVAL_START)
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

# (xs, ys) for a swept axis (UDE, full, single ablation seed, fixed other params).
# The seed filter matters now that the baseline (t_train_end=30) is run over
# multiple seeds — without it the t_train_end axis would pick up 5 duplicate
# points at 30 ms.  Ablations are single-seed at B_SEED.
function axis_series(df, axiscol, metric; window = "forecast",
                     gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    mask = (df.model .== "UDE") .& (df.observed .== "full") .& (df.seed .== B_SEED) .&
           (df.window .== window) .& (df.metric .== metric)
    fixed = Dict(:gCa => gCa, :noise_level => noise_level, :t_train_end => t_train_end)
    delete!(fixed, axiscol)
    for (k, v) in fixed; mask .&= (df[!, k] .== v); end
    sub   = df[mask, :]
    order = sortperm(Float64.(sub[!, axiscol]))
    return Float64.(sub[order, axiscol]), Float64.(sub.value[order])
end

# --- metrics_baseline.csv (wide: NODE & UDE rows × window_metric cols) -------
# Single-seed (REP_SEED) view — unchanged in form/content from before the
# multi-seed work.  The mean±std across seeds lives in metrics_baseline_multiseed.csv.
let
    p = (df.observed .== "full") .& (df.seed .== REP_SEED) .& (df.gCa .== B_GCA) .&
        (df.noise_level .== B_NOISE) .& (df.t_train_end .== B_TWIN) .&
        ((df.model .== "NODE") .| (df.model .== "UDE"))
    sub = df[p, :]
    sub.key = string.(sub.window, "_", sub.metric)
    wide = unstack(sub, :model, :key, :value)
    CSV.write(joinpath(RESULTS_DIR, "metrics_baseline.csv"), wide)
end

# --- metrics_baseline_multiseed.csv (mean±std over SEEDS) --------------------
# The mentor-requested aggregate: for each headline (model, observed) at the
# baseline setting, mean/std/n across the seeds for every window×metric.
# `agg` is also reused by fig5/fig8 and the headline console summary.
function agg(dframe; model, observed, window, metric,
             gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    mask = (dframe.model .== model) .& (dframe.observed .== observed) .&
           (dframe.window .== window) .& (dframe.metric .== metric) .&
           (dframe.gCa .== gCa) .& (dframe.noise_level .== noise_level) .&
           (dframe.t_train_end .== t_train_end)
    vals = filter(isfinite, Float64.(dframe.value[mask]))
    n = length(vals)
    return (; mean = n == 0 ? NaN : Statistics.mean(vals),
              std  = n <= 1 ? 0.0 : Statistics.std(vals), n = n)
end
let
    combos  = [("NODE", "full"), ("UDE", "full"), ("UDE", "voltage")]
    windows = ["train", "forecast"]
    mets    = ["V_rmse", "gate_rmse_mean", "V_rmse_vs_noisy", "rollout_horizon_ms",
               "ICa_rmse", "ICa_rmse_norm", "spike_mean_abs_dev_ms"]
    rows = NamedTuple[]
    for (mdl, obs) in combos, w in windows, mt in mets
        a = agg(df; model = mdl, observed = obs, window = w, metric = mt)
        a.n == 0 && continue
        push!(rows, (; model = mdl, observed = obs, window = w, metric = mt,
                       mean = a.mean, std = a.std, n_seeds = a.n))
    end
    CSV.write(joinpath(RESULTS_DIR, "metrics_baseline_multiseed.csv"), DataFrame(rows))
end

# --- ablation_*.csv (wide: swept value × window_metric cols) -----------------
function write_ablation_csv(df, axiscol, fname; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    mask = (df.model .== "UDE") .& (df.observed .== "full") .& (df.seed .== B_SEED)
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

# log bar with mean±std whiskers across seeds.  On a log axis a symmetric std can
# push the lower whisker to <=0, so the lower arm is clamped just above the bar
# floor; the printed number is the mean.
function logbar_err(labels, means, errs, ttl, ylab, colors)
    n = length(means); v = max.(means, 1e-4)
    lower = [isfinite(e) ? min(e, v[i]*0.999) : 0.0 for (i, e) in enumerate(errs)]
    upper = [isfinite(e) ? e : 0.0 for e in errs]
    caps  = [v[i] + upper[i] for i in 1:n]                 # top of each error whisker
    fin   = filter(isfinite, v)
    lo    = isempty(fin) ? 1e-4 : minimum(fin)
    hi    = maximum(filter(isfinite, caps); init = 1.0)    # frame includes the whiskers
    p = bar(1:n, v; legend=false, ylabel=ylab, yscale=:log10, title=ttl, color=colors,
            xticks=(1:n, labels), xlims=(0.3, n+0.7), ylims=(lo*0.30, hi*6),
            bar_width=0.62, yerror=(lower, upper), left_margin=9mm, bottom_margin=7mm, right_margin=6mm)
    # place each value label just ABOVE its whisker cap so the two never overlap
    for x in 1:n
        isfinite(means[x]) || continue
        annotate!(p, x, caps[x]*1.35, text(string(round(means[x], sigdigits=3)), 7, :center, :bottom))
    end
    return p
end

# --- fig5: train-vs-forecast RMSE bars, NODE vs UDE (log y, mean±std over seeds)
let
    labels = ["NODE\ntrain", "NODE\nforecast", "UDE\ntrain", "UDE\nforecast"]
    cols   = [:steelblue, :steelblue, :seagreen, :seagreen]
    specs  = [("NODE","train"), ("NODE","forecast"), ("UDE","train"), ("UDE","forecast")]
    grab(m) = [agg(df; model=md, observed="full", window=w, metric=m) for (md, w) in specs]
    va = grab("V_rmse"); ga = grab("gate_rmse_mean")
    ns = length(SEEDS)
    p1 = logbar_err(labels, [x.mean for x in va], [x.std for x in va],
                    "Voltage RMSE vs clean truth (mean±std, $ns seeds)", "V RMSE (mV, log scale)", cols)
    p2 = logbar_err(labels, [x.mean for x in ga], [x.std for x in ga],
                    "Gating-variable RMSE (mean±std, $ns seeds)", "gate RMSE (log scale)", cols)
    savefig(plot(p1, p2, layout=(1,2), size=(1050,470)),
            joinpath(FIG_DIR, "fig5_metrics_bar_train_vs_forecast.png"))
end

# --- fig7*: ablation curves (forecast window) --------------------------------
# Each metric gets its OWN panel (own y-scale) so the small gate-RMSE is never
# crushed against the larger V-RMSE, and no legend is needed (title + y-label
# describe each single-series panel). x-ticks sit exactly on the sampled values.
function ablation_fig(axiscol, xlab, fname; extra_metric = nothing, extra_lab = "", xt = :auto,
                      window = "forecast")
    wl = window == "common_eval" ? "common-eval, t>$(Int(COMMON_EVAL_START)) ms" : window
    xv, vr = axis_series(df, axiscol, "V_rmse";         window = window)
    _,  gr = axis_series(df, axiscol, "gate_rmse_mean"; window = window)
    _,  rh = axis_series(df, axiscol, "rollout_horizon_ms"; window = window)
    common = (; xlabel=xlab, legend=false, marker=:circle, lw=2,
                left_margin=8mm, bottom_margin=5mm, xticks=xt)
    # ylabels stay short; the evaluation window is named in each panel title instead
    # (a "$wl ..." ylabel is long enough to clip off the top of the panel).
    p1 = plot(xv, vr; ylabel="V RMSE (mV)", title="Voltage error ($wl)",
              color=:dodgerblue, common...)
    p2 = plot(xv, gr; ylabel="gate RMSE", title="Gating-variable error ($wl)",
              color=:seagreen, common...)
    p3 = plot(xv, rh; ylabel="rollout horizon (ms)", title="Forecast validity ($wl, cap 70 ms)",
              color=:purple, ylims=(0, 75), common...)
    panels = Any[p1, p2, p3]
    if extra_metric !== nothing
        _, ev = axis_series(df, axiscol, extra_metric; window = window)
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
# common-eval version: every training length scored on the SAME (50,100] ms
# interval, so the comparison is not confounded by a shifting forecast window.
ablation_fig(:t_train_end, "training-window length (ms)", "fig7b_commoneval_ablation_window.png";
             window="common_eval",
             xt=([15,20,30,40,50], ["15","20","30","40","50"]))
ablation_fig(:gCa, "gCa (calcium strength)", "fig7c_ablation_gca.png";
             extra_metric="ICa_rmse_norm", extra_lab="I(Ca) RMSE / std (normalised)",
             xt=([0.4,1.0,2.0,4.0], ["0.4","1.0","2.0","4.0"]))

# --- fig8: full vs voltage-only, forecast metrics (mean±std over seeds) -------
let
    ns = length(SEEDS)
    specs = [("V_rmse",         "Voltage error",   "forecast V RMSE (mV)"),
             ("gate_rmse_mean", "Gating error",    "forecast gate RMSE (dimensionless)"),
             ("ICa_rmse",       "Calcium current", "forecast I(Ca) RMSE (μA/cm²)")]
    panels = []
    for (m, ttl, ylab) in specs
        af = agg(df; model="UDE", observed="full",    window="forecast", metric=m)
        av = agg(df; model="UDE", observed="voltage", window="forecast", metric=m)
        means = [isfinite(af.mean) ? max(af.mean, 0.0) : 0.0,
                 isfinite(av.mean) ? max(av.mean, 0.0) : 0.0]
        errs  = [isfinite(af.std) ? af.std : 0.0, isfinite(av.std) ? av.std : 0.0]
        top   = maximum(means .+ errs) * 1.3
        top   = top > 0 ? top : 1.0
        push!(panels, bar(["full", "voltage-only"], means; legend=false,
                          title=ttl, ylabel=ylab, titlefontsize=10,
                          color=[:seagreen, :darkorange], yerror=errs,
                          ylims=(0, top), left_margin=9mm, right_margin=5mm, bottom_margin=8mm))
    end
    savefig(plot(panels..., layout=(1,3), size=(1220,470),
                 plot_title="Forecast error: full vs voltage-only (mean±std, $ns seeds)",
                 plot_titlefontsize=12),
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
    csvs = ["metrics_all.csv", "metrics_baseline.csv", "metrics_baseline_multiseed.csv",
            "ablation_noise.csv", "ablation_window.csv", "ablation_gca.csv",
            joinpath("calcium", "probe_ude_full_seed$(REP_SEED).csv"),
            joinpath("calcium", "grid_ude_full_seed$(REP_SEED).csv")]
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
                   "fig7_ablation_noise.png", "fig7b_ablation_window.png",
                   "fig7b_commoneval_ablation_window.png", "fig7c_ablation_gca.png",
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

# =============================================================================
#  6. Representative-seed guardrail
# =============================================================================
#  REP_SEED supplies the single-seed trajectory/parity panels.  Confirm it is a
#  TYPICAL run — not a lucky/unlucky outlier — by checking its headline metric
#  (UDE/full forecast V RMSE) against the across-seed median/IQR.  If REP_SEED
#  falls outside the IQR, print the exact command to regenerate the panels from
#  the median-closest seed's saved params (no retraining).
let
    mask = (df.model .== "UDE") .& (df.observed .== "full") .& (df.window .== "forecast") .&
           (df.metric .== "V_rmse") .& (df.gCa .== B_GCA) .& (df.noise_level .== B_NOISE) .&
           (df.t_train_end .== B_TWIN)
    sub = df[mask, :]
    println("\n========== representative-seed guardrail (UDE/full forecast V RMSE) ==========")
    if nrow(sub) == 0
        println("  no UDE/full forecast rows found — skipping guardrail.")
    else
        seeds = Int.(sub.seed); vals = Float64.(sub.value)
        med   = Statistics.median(vals)
        best  = seeds[argmin(abs.(vals .- med))]           # median-closest seed
        println("  per-seed: ", join(["$(s)=$(round(v, sigdigits=4))" for (s, v) in zip(seeds, vals)], "  "))
        println("  median = ", round(med, sigdigits=4), " mV ; median-closest seed = ", best)
        repi = findfirst(==(REP_SEED), seeds)
        if repi === nothing
            println("  ⚠ REP_SEED ($REP_SEED) not among the run seeds — cannot assess representativeness.")
        elseif best == REP_SEED
            println("  ✓ REP_SEED ($REP_SEED) IS the median-closest seed — panels are representative.")
        else
            rep_val = vals[repi]
            q1, q3  = Statistics.quantile(vals, 0.25), Statistics.quantile(vals, 0.75)
            if q1 <= rep_val <= q3
                println("  ✓ REP_SEED ($REP_SEED)=", round(rep_val, sigdigits=4),
                        " within IQR [", round(q1, sigdigits=4), ", ", round(q3, sigdigits=4),
                        "] — acceptable as representative.")
            else
                println("  ⚠ REP_SEED ($REP_SEED)=", round(rep_val, sigdigits=4),
                        " OUTSIDE IQR [", round(q1, sigdigits=4), ", ", round(q3, sigdigits=4), "].")
                println("    Regenerate representative panels from median-closest seed $best (no retrain):")
                println("    HH_REPLOT-style: regenerate_ude_figs(\"ude_full_seed$(best)\", \"fig3_ude\"; " *
                        "gCa=$B_GCA, noise_level=$B_NOISE, t_train_end=$B_TWIN, seed=$best)")
            end
        end
    end
    println("==============================================================================")
end

# --- headline summary to console (mean±std over SEEDS) -----------------------
println("\n========== HEADLINE (forecast window, vs clean truth; mean±std over $(length(SEEDS)) seeds) ==========")
for (model, obs) in (("NODE","full"), ("UDE","full"), ("UDE","voltage"))
    v  = agg(df; model=model, observed=obs, window="forecast", metric="V_rmse")
    g  = agg(df; model=model, observed=obs, window="forecast", metric="gate_rmse_mean")
    rh = agg(df; model=model, observed=obs, window="forecast", metric="rollout_horizon_ms")
    fmt(a) = "$(round(a.mean, sigdigits=4))±$(round(a.std, sigdigits=2))"
    println(rpad("$model/$obs", 14), "  V_rmse=", rpad(fmt(v), 20),
            "gate_rmse=", rpad(fmt(g), 20), "rollout=", fmt(rh), " ms")
end
println("\n", SMOKE ? "[SMOKE run complete]" : "[FULL run complete]", "  metrics -> results/  figures -> figures/")
