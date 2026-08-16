# =============================================================================
#  recover_voltage_only_commoneval.jl
# =============================================================================
#  Discharges the ledger tombstone `voltage-only-common-eval-matches-full`.
#
#  The claim -- that voltage-only and full-state observation agree on the SHARED
#  common-evaluation window t > 50 ms -- had no evidence, because
#  experiments_runner.jl calls run_experiment for the voltage-only family WITHOUT
#  `common_eval_start` (line 98-103), so results/metrics_all.csv contains zero
#  `window=common_eval` rows for observed=voltage.
#
#  It does not need a retrain. The trained weights were saved
#  (results/params/ude_voltage_only*.jld), so the missing rows can be produced by
#  reloading each network, re-solving the full 100 ms span, and scoring on the
#  common-eval indices -- exactly what compute_metrics would have emitted had the
#  kwarg been passed. Same solver, same tolerances, same metric code.
#
#  Both families are recomputed, not just the voltage-only one, so the comparison
#  is like-for-like and so the full-state numbers can be checked against the rows
#  already in metrics_all.csv (printed as a self-test: they must match).
#
#  ISOLATION: writes results/identifiability/voltage_only_commoneval.csv.
#  results/metrics_all.csv is NOT touched -- appending there would change the
#  inputs of already-published \val macros.
#
#  Run:  julia --project=. recover_voltage_only_commoneval.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV, Statistics, Printf

const OUT_DIR = joinpath(ROOT, "results", "identifiability")
mkpath(OUT_DIR)

const G_CA, NOISE_LEVEL, T_TRAIN_END = 2.0, 0.02, 30.0
const SEEDS = [1111, 2222, 3333, 4444, 5555]
const REP_SEED = 1111

# tag convention from experiments_runner.jl: the representative seed keeps the
# bare tag, other seeds carry a _seed<n> suffix.
tag_for(family, seed) = seed == REP_SEED ? family : "$(family)_seed$(seed)"

function score_run(family, seed)
    data_clean = gen_clean_data(G_CA).data_clean
    data_noisy = gen_noisy_data(data_clean, NOISE_LEVEL; seed = seed)
    split      = make_split(T_TRAIN_END)
    u0         = steady_state_u0()

    tag = tag_for(family, seed)
    path = joinpath(PARAMS_DIR, "ude_$(tag).jld")
    isfile(path) || (@warn "missing params, skipping" path; return nothing)

    nn_ca, p_ca, st_ca = load_ude_params(tag, seed)
    rhs  = make_hh_ude(nn_ca, st_ca)
    pred = solve_aligned(rhs, u0, p_ca)

    Vt, st_ = data_clean[1, :], data_clean[6, :]
    ICa_true = G_CA .* st_ .^ 2 .* (Vt .- ECa)
    ICa_nn   = [nn_ca([Vt[i] / 100.0, st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]

    rows = compute_metrics(; model = "UDE",
                             observed = family == "ude_full" ? "full" : "voltage",
                             gCa = G_CA, noise_level = NOISE_LEVEL,
                             t_train_end = T_TRAIN_END, seed = seed,
                             t = TSTEPS, truth = data_clean, pred = pred,
                             train_idx = split.train_idx,
                             forecast_idx = split.forecast_idx,
                             truth_noisy = data_noisy,
                             ICa_true = ICa_true, ICa_nn = ICa_nn,
                             common_idx = common_eval_indices(COMMON_EVAL_START))
    return rows
end

println("\n=== Recovering common-eval metrics from saved parameters (no retraining) ===")
all_rows = NamedTuple[]
for family in ("ude_full", "voltage_only"), seed in SEEDS
    r = score_run(family, seed)
    r === nothing && continue
    append!(all_rows, r)
    @printf("  %-13s seed %d : %d metric rows\n", family, seed, length(r))
end

df = DataFrame(all_rows)
CSV.write(joinpath(OUT_DIR, "voltage_only_commoneval.csv"), df)

# ---------------------------------------------------------------------------
#  Self-test: the FORECAST-window numbers we just recomputed must reproduce the
#  rows already in metrics_all.csv. If they do not, the reload path is wrong and
#  the common-eval numbers cannot be trusted either.
# ---------------------------------------------------------------------------
published = CSV.read(joinpath(RESULTS_DIR, "metrics_all.csv"), DataFrame)
# Wrapped in a function: a bare top-level `for` gets Julia's soft scope, so an
# accumulator assigned inside it never reaches the global.
function worst_disagreement(df, published)
    worst = 0.0
    for r in eachrow(df)
        r.window == "forecast" || continue
        m = published[(published.model .== "UDE") .& (published.observed .== r.observed) .&
                      (published.gCa .== G_CA) .& (published.noise_level .== NOISE_LEVEL) .&
                      (published.t_train_end .== T_TRAIN_END) .& (published.seed .== r.seed) .&
                      (published.window .== "forecast") .& (published.metric .== r.metric), :]
        nrow(m) == 1 || continue
        a, b = Float64(r.value), Float64(m.value[1])
        (isfinite(a) && isfinite(b) && b != 0) || continue
        worst = max(worst, abs(a - b) / abs(b))
    end
    return worst
end
worst = worst_disagreement(df, published)
@printf("\n  self-test: worst relative disagreement with metrics_all.csv = %.3e  %s\n",
        worst, worst < 1e-8 ? "(reload path validated)" : "(WARNING - investigate)")

# --- the actual comparison -------------------------------------------------
println("\n=== Common-eval window (t > $(COMMON_EVAL_START) ms), mean +/- SD over $(length(SEEDS)) seeds ===")
for metric in ("V_rmse", "gate_rmse_mean", "ICa_rmse")
    print(rpad("  $metric", 20))
    for obs in ("full", "voltage")
        v = Float64.(df[(df.window .== "common_eval") .& (df.metric .== metric) .&
                        (df.observed .== obs), :value])
        v = filter(isfinite, v)
        isempty(v) && (print(rpad("$obs: --", 30)); continue)
        print(rpad(@sprintf("%s: %.4f +/- %.4f", obs, mean(v), std(v)), 30))
    end
    println()
end
println("\nwrote ", joinpath(OUT_DIR, "voltage_only_commoneval.csv"))
