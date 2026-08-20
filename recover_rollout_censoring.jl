# =============================================================================
#  recover_rollout_censoring.jl
# =============================================================================
#  Re-measures the rollout horizon for the training-window ablation after the
#  censoring fix in src/metrics.jl.
#
#  THE DEFECT.  rollout_horizon() returned `cap_ms` (70.0) whenever the forecast
#  never left the tube, with no check on how much trajectory remained. On the
#  common-evaluation window the first scored sample is at t = 50.098 ms and the
#  trace ends at 100 ms, so only 49.902 ms of data exists -- yet every run
#  reported 70.0. results/ablation_window.csv therefore carries 70.0 in
#  `common_eval_rollout_horizon_ms` for all five windows, and the panel of
#  fig7b_commoneval_ablation_window.png that plots it is a flat line at a value
#  40% longer than the window it was measured in. The forecast window is affected
#  too, but only cosmetically: it starts at 30.137 ms, so its true ceiling is
#  69.863 ms rather than 70.0.
#
#  WHY NO RETRAIN.  The bug is in the metric, not in the model. The trained
#  weights for all five window settings were saved
#  (results/params/ude_abl_window_{15,20,40,50}.0.jld, and ude_ude_full.jld for
#  the 30 ms baseline), so the horizon can be re-measured by reloading each
#  network, re-solving the same 100 ms span with the same solver and tolerances,
#  and calling the CORRECTED rollout_horizon -- exactly what compute_metrics
#  would have emitted had the clamp been there. This is the same pattern as
#  recover_training_losses.jl and recover_voltage_only_commoneval.jl.
#
#  SELF-TEST.  Every OTHER metric this reload produces must reproduce the value
#  already in results/ablation_window.csv. Only rollout_horizon_ms is expected to
#  move. If anything else disagrees, the reload path is wrong and the new horizon
#  numbers cannot be trusted either -- the script says so and exits non-zero.
#
#  ISOLATION: writes results/identifiability/rollout_censoring.csv.
#  results/metrics_all.csv and results/ablation_window.csv are NOT touched;
#  appending there would change the inputs of already-published \val macros.
#
#  Run:  julia --project=. recover_rollout_censoring.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV, Statistics, Printf

const OUT_DIR = joinpath(ROOT, "results", "identifiability")
mkpath(OUT_DIR)

const G_CA, NOISE_LEVEL = 2.0, 0.02
const REP_SEED = 1111
const B_TWIN = 30.0

# experiments_runner.jl writes the 30 ms point as the baseline run, not as an
# ablation, so it carries the bare "ude_full" tag; the other four are tagged by
# their window length (write_ablation_csv pins seed = B_SEED on every axis, so
# every point here is the one representative seed).
const WINDOWS = [(15.0, "abl_window_15.0"),
                 (20.0, "abl_window_20.0"),
                 (30.0, "ude_full"),
                 (40.0, "abl_window_40.0"),
                 (50.0, "abl_window_50.0")]

function score_window(t_train_end, tag)
    data_clean = gen_clean_data(G_CA).data_clean
    data_noisy = gen_noisy_data(data_clean, NOISE_LEVEL; seed = REP_SEED)
    split      = make_split(t_train_end)
    u0         = steady_state_u0()

    path = joinpath(PARAMS_DIR, "ude_$(tag).jld")
    isfile(path) || (@warn "missing params, skipping" path; return nothing)

    nn_ca, p_ca, st_ca = load_ude_params(tag, REP_SEED)
    rhs  = make_hh_ude(nn_ca, st_ca)
    pred = solve_aligned(rhs, u0, p_ca)

    Vt, st_  = data_clean[1, :], data_clean[6, :]
    ICa_true = G_CA .* st_ .^ 2 .* (Vt .- ECa)
    ICa_nn   = [nn_ca([Vt[i] / 100.0, st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]

    rows = compute_metrics(; model = "UDE", observed = "full",
                             gCa = G_CA, noise_level = NOISE_LEVEL,
                             t_train_end = t_train_end, seed = REP_SEED,
                             t = TSTEPS, truth = data_clean, pred = pred,
                             train_idx = split.train_idx,
                             forecast_idx = split.forecast_idx,
                             truth_noisy = data_noisy,
                             ICa_true = ICa_true, ICa_nn = ICa_nn,
                             common_idx = common_eval_indices(COMMON_EVAL_START))
    return rows
end

println("\n=== Re-measuring rollout censoring from saved parameters (no retraining) ===")
println("(only rollout_horizon_ms should move; everything else is a self-test)\n")

all_rows = NamedTuple[]
for (twin, tag) in WINDOWS
    r = score_window(twin, tag)
    r === nothing && continue
    append!(all_rows, r)
    @printf("  t_train_end %5.1f  tag %-18s : %d metric rows\n", twin, tag, length(r))
end

df = DataFrame(all_rows)
CSV.write(joinpath(OUT_DIR, "rollout_censoring.csv"), df)

# ---------------------------------------------------------------------------
#  Report the horizons, and self-test everything else against ablation_window.csv
# ---------------------------------------------------------------------------
published = CSV.read(joinpath(RESULTS_DIR, "ablation_window.csv"), DataFrame)

function horizon_table(df)
    out = NamedTuple[]
    for w in sort(unique(df.t_train_end))
        f = df[(df.t_train_end .== w) .& (df.window .== "forecast") .&
               (df.metric .== "rollout_horizon_ms"), :]
        c = df[(df.t_train_end .== w) .& (df.window .== "common_eval") .&
               (df.metric .== "rollout_horizon_ms"), :]
        push!(out, (; t_train_end = w,
                      forecast = nrow(f) == 1 ? f.value[1] : NaN,
                      common_eval = nrow(c) == 1 ? c.value[1] : NaN))
    end
    return out
end

println("\n  rollout horizon (ms), corrected:")
println("    t_train_end   forecast   common_eval      (was 70.0 / 70.0)")
for r in horizon_table(df)
    @printf("    %8.1f    %8.3f   %8.3f\n", r.t_train_end, r.forecast, r.common_eval)
end

# Wrapped in a function: a bare top-level `for` gets Julia's soft scope, so an
# accumulator assigned inside it never reaches the global.
function worst_disagreement(df, published)
    worst, worst_lbl, n = 0.0, "", 0
    for r in eachrow(df)
        r.metric == "rollout_horizon_ms" && continue      # the one we changed
        col = Symbol(string(r.window, "_", r.metric))
        hasproperty(published, col) || continue
        m = published[published.t_train_end .== r.t_train_end, :]
        nrow(m) == 1 || continue
        a, b = Float64(r.value), Float64(m[1, col])
        (isfinite(a) && isfinite(b) && b != 0) || continue
        n += 1
        d = abs(a - b) / abs(b)
        if d > worst
            worst, worst_lbl = d, "$(col) @ t_train_end=$(r.t_train_end)"
        end
    end
    return worst, worst_lbl, n
end

worst, lbl, n = worst_disagreement(df, published)
@printf("\n  self-test: %d non-horizon metrics compared with ablation_window.csv\n", n)
@printf("             worst relative disagreement %.3e  (%s)\n", worst, lbl)

if worst > 1e-8
    println("\n  FAIL: the reload path does not reproduce the published numbers.")
    println("        The corrected horizons above cannot be trusted. Do not use them.")
    exit(1)
end
println("             OK -- the reload reproduces every other metric exactly, so the")
println("             horizon change is the metric fix and nothing else.")
println("\nwrote ", joinpath(OUT_DIR, "rollout_censoring.csv"))
