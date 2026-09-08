# =============================================================================
#  noise_weighted_ude.jl
# =============================================================================
#  Asks the one question the matched-objective control raised and did not answer:
#  IF THE UDE DESCENDED THE NOISE-WEIGHTED LIKELIHOOD INSTEAD OF THE UNWEIGHTED
#  SUM OF SQUARES, WOULD THE CONDUCTANCE COME BACK?
#
#  THE EVIDENCE THAT MOTIVATES IT.  results/identifiability/
#  parametric_matched_objective_summary.csv, gCa = 2.0 rows.  At a FIXED
#  two-parameter representation, holding data, starts and optimiser constant and
#  changing only which residual is minimised:
#
#      objective   recovered gCa      rel_sd     recovered ECa (true 120)
#      sse_full    2.478 +- 0.489     0.1974     87.8 +- 36.0
#      sse_v       2.479 +- 0.489     0.1974     87.7 +- 36.0
#      chi2        2.092 +- 0.130     0.0621     111.9 +- 12.0
#
#  Two things follow.  First, sse_full and sse_v agree to three decimals, so the
#  damage is NOT the voltage domination the paper spends a paragraph on -- it is
#  the MISSING NOISE WEIGHTING.  Second, weighting alone takes the spread from
#  ~20% to ~6% at fixed representation.
#
#  And make_ude_loss (src/experiment.jl:173-188) descends the unweighted one.
#
#  WHAT THIS DOES.  Mirrors run_experiment (src/experiment.jl) exactly -- same
#  data, same split, same network init, same solver, same adjoint, same two-stage
#  Adam+BFGS schedule and budget -- and changes EXACTLY ONE THING: the reduction
#  applied to the residual.
#
#      :sse    sum(abs2, r)              the published objective, byte-for-byte
#      :chi2   sum(abs2, r ./ sigma)     sigma = noise_level .* std(clean, dims=2)
#
#  sigma is built the same way identifiability_parametric.jl:167 builds it, which
#  is the same way gen_noisy_data actually draws the noise.  So :chi2 here is the
#  same statistic the parametric arm already reports, applied to the closure.
#
#  EITHER OUTCOME IS A RESULT, WHICH IS WHY THIS IS WORTH ONE HOUR OF COMPUTE:
#    * if recovery returns, the paper stops being "flexible closures lose
#      identifiability" (a caution) and becomes "they lose it under the standard
#      loss, and this is the change that recovers it" (a prescription);
#    * if it does not, the objective effect demonstrably fails to transfer to the
#      flexible representation, which STRENGTHENS the representation attribution
#      rather than weakening it.
#
#  SELF-TEST, AND IT GATES EVERYTHING.  This script re-implements run_experiment
#  rather than calling it, so it must prove it is the same harness.  The :sse arm
#  at seed 1111 must reproduce the published per-seed forecast V RMSE
#      results/metrics_all.csv -> UDE, full, gCa 2.0, noise 0.02, t_train 30.0,
#      seed 1111, forecast, V_rmse = 0.2191970340109573
#  to within SELFTEST_RTOL.  If it does not, this harness is not the engine and
#  the :chi2 numbers mean nothing, so the script EXITS NON-ZERO before running
#  the treatment arm.  Same discipline as parametric_matched_objective.jl.
#
#  ISOLATION.  HH_RESULTS_DIR / HH_FIG_DIR are set BEFORE the includes, so
#  RESULTS_DIR, FIG_DIR, PARAMS_DIR and CALCIUM_DIR (all `const`, evaluated at
#  include time) point at results_noiseweighted/ and figures_noiseweighted/.
#  NOTHING under results/ or figures/ is read for writing or overwritten, so no
#  published macro can move.  The probe and grid CSVs land in
#  results_noiseweighted/calcium/ with the same filenames the distillation
#  scripts expect, so scripts/symbolic_domain_comparison.py can be pointed at
#  that tree unchanged to get a_hat on the supervised trajectory.
#
#  COMPUTE BUDGET (the co-author asked for this to be tight):
#      1 self-test run (:sse, seed 1111)          ~11 min
#      5 treatment runs (:chi2, all five seeds)   ~55 min
#      ------------------------------------------------
#      6 runs total                               ~1.1 h on the recorded CPU box
#  The :sse arm is NOT re-run at the other four seeds -- those numbers are already
#  published and re-deriving them would buy nothing.
#
#  Run:  julia --project=. noise_weighted_ude.jl
# =============================================================================

const ROOT = @__DIR__

# MUST precede the includes: RESULTS_DIR/FIG_DIR are consts read at include time.
ENV["HH_RESULTS_DIR"] = get(ENV, "NW_RESULTS_DIR", joinpath(ROOT, "results_noiseweighted"))
ENV["HH_FIG_DIR"]     = get(ENV, "NW_FIG_DIR",     joinpath(ROOT, "figures_noiseweighted"))
delete!(ENV, "HH_SMOKE")   # never let a stray smoke flag shrink the budgets here

include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using Printf, Statistics, DataFrames, CSV

# --- the settings the published baseline uses --------------------------------
const NW_GCA        = 2.0
const NW_NOISE      = 0.02
const NW_TWIN       = 30.0
const NW_SEEDS      = [1111, 2222, 3333, 4444, 5555]
#  NW_ADAM / NW_BFGS default to the published budget. NW_SMOKE=1 shrinks them to
#  exercise the plumbing in ~1 min per run -- it is a PIPELINE CHECK ONLY and its
#  numbers are meaningless, so it also disables the self-test comparison (which
#  would fail by construction at a reduced budget) and tags its output loudly.
const NW_SMOKE      = get(ENV, "NW_SMOKE", "0") == "1"
const NW_ADAM       = NW_SMOKE ? 30 : 5000
const NW_BFGS       = NW_SMOKE ? 5   : 300

# Self-test target: results/metrics_all.csv, UDE/full/2.0/0.02/30.0/1111/forecast/V_rmse
const SELFTEST_TARGET = 0.2191970340109573
const SELFTEST_RTOL   = 1e-6

# --- the one thing that varies ------------------------------------------------
#  Mirrors make_ude_loss(src/experiment.jl:173-188). The :sse branches are the
#  published expressions unchanged; the :chi2 branches divide the residual by the
#  known per-channel noise SD before squaring, exactly as
#  identifiability_parametric.jl:117 does for the parametric arm.
function make_ude_loss_weighted(observed::Symbol, objective::Symbol, predict,
                                data_noisy, train_idx, sigma)
    ntrain = length(train_idx)
    if observed == :voltage
        sig_v = sigma[1:1, :]
        return function (p)
            pred = predict(p)
            size(pred, 2) == ntrain || return 1.0e6
            r = data_noisy[1:1, train_idx] .- pred[1:1, :]
            return objective === :chi2 ? sum(abs2, r ./ sig_v) : sum(abs2, r)
        end
    else
        return function (p)
            pred = predict(p)
            size(pred, 2) == ntrain || return 1.0e6
            r = data_noisy[:, train_idx] .- pred
            return objective === :chi2 ? sum(abs2, r ./ sigma) : sum(abs2, r)
        end
    end
end

# --- run_experiment, mirrored, with the loss swapped -------------------------
#  Every line below that is not the loss is lifted from run_experiment
#  (src/experiment.jl:383-432) so the two harnesses cannot drift.
function run_weighted(; gCa = NW_GCA, noise_level = NW_NOISE, t_train_end = NW_TWIN,
                        observed = :full, seed = 1111, objective = :chi2,
                        adam_iters = NW_ADAM, bfgs_iters = NW_BFGS, tag = "")
    @printf("[run_weighted] objective=%s observed=%s seed=%d tag=%s\n",
            objective, observed, seed, tag)
    data_clean = gen_clean_data(gCa).data_clean
    data_noisy = gen_noisy_data(data_clean, noise_level; seed = seed)
    split      = make_split(t_train_end)
    u0         = steady_state_u0()

    # Known per-channel noise SD, as gen_noisy_data constructs it.
    sigma = noise_level .* std(data_clean, dims = 2)

    nn_ca, p_ca0, st_ca = make_ca_network(seed)
    rhs  = make_hh_ude(nn_ca, st_ca)
    prob = ODEProblem(rhs, u0, split.tspan_train, p_ca0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))

    loss_fn = make_ude_loss_weighted(observed, objective, predict,
                                     data_noisy, split.train_idx, sigma)

    tr   = train_two_stage(loss_fn, p_ca0; adam_lr = 1e-2, adam_iters = adam_iters,
                           bfgs_iters = bfgs_iters, label = "UDE[$objective]")
    p_ca = tr.p

    pred_full = solve_aligned(rhs, u0, p_ca)

    Vt = data_clean[1, :]; st_ = data_clean[6, :]; Vn = Vt ./ 100.0
    ICa_nn   = [nn_ca([Vn[i], st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]
    ICa_true = gCa .* st_ .^ 2 .* (Vt .- ECa)

    metrics = compute_metrics(; model = "UDE", observed = observed, gCa = gCa,
                                noise_level = noise_level, t_train_end = t_train_end,
                                seed = seed, t = TSTEPS, truth = data_clean,
                                pred = pred_full, train_idx = split.train_idx,
                                forecast_idx = split.forecast_idx,
                                truth_noisy = data_noisy, ICa_true = ICa_true,
                                ICa_nn = ICa_nn, common_idx = nothing)

    # Same artifacts run_experiment writes, into the ISOLATED tree.
    snapshot_params(tag, p_ca)
    save_calcium_probe(tag, seed, TSTEPS, Vt, st_, Vn, ICa_true, ICa_nn)
    save_calcium_grid_probe(nn_ca, p_ca, st_ca, gCa, tag, seed, Vt, st_)

    return (; seed, objective, observed, final_loss = tr.final_loss,
              bfgs_ok = tr.bfgs_ok, metrics)
end

# compute_metrics returns a Vector{NamedTuple} of tidy rows carrying `window`,
# `metric` and `value` (src/metrics.jl:117). Pull exactly one out, and insist on
# exactly one -- a silent first-match pick is how the wrong number gets reported.
function pick(metrics, window::String, metric::String)
    hits = filter(r -> r.window == window && r.metric == metric, metrics)
    length(hits) == 1 ||
        error("pick: expected exactly 1 row for $window/$metric, got $(length(hits))")
    return hits[1].value
end

# =============================================================================
#  1. SELF-TEST — prove this harness IS the engine before trusting anything.
# =============================================================================
println("\n=== SELF-TEST: :sse arm, seed 1111, must reproduce the published run ===")
st_run = run_weighted(; seed = 1111, objective = :sse, tag = "nw_selftest_sse")
st_val = pick(st_run.metrics, "forecast", "V_rmse")
st_rel = abs(st_val - SELFTEST_TARGET) / SELFTEST_TARGET
@printf("  published : %.16f\n  this run  : %.16f\n  rel diff  : %.3e (tol %.0e)\n",
        SELFTEST_TARGET, st_val, st_rel, SELFTEST_RTOL)

if NW_SMOKE
    println("  SKIPPED -- NW_SMOKE=1 runs a reduced budget, so this comparison")
    println("  would fail by construction. THESE NUMBERS ARE MEANINGLESS.")
elseif !(st_rel <= SELFTEST_RTOL)
    println("\n*** SELF-TEST FAILED. ***")
    println("This harness does not reproduce run_experiment, so any :chi2 number it")
    println("produces would be uninterpretable -- a difference could be the objective")
    println("or could be the harness, and nothing here could tell them apart.")
    println("NOT running the treatment arm. Fix the mirror first.")
    exit(1)
else
    println("  PASS -- the mirror is the engine. Proceeding.")
end
println()

# =============================================================================
#  2. TREATMENT — the noise-weighted objective, all five seeds.
# =============================================================================
println("=== TREATMENT: :chi2 arm, five seeds ===")
rows = NamedTuple[]

push!(rows, (; objective = "sse", seed = 1111, arm = "selftest",
               final_loss = st_run.final_loss, bfgs_ok = st_run.bfgs_ok,
               forecast_V_rmse = st_val,
               forecast_ICa_rmse = pick(st_run.metrics, "forecast", "ICa_rmse"),
               train_V_rmse = pick(st_run.metrics, "train", "V_rmse")))

for s in NW_SEEDS
    r = run_weighted(; seed = s, objective = :chi2, tag = "nw_chi2_seed$(s)")
    push!(rows, (; objective = "chi2", seed = s, arm = "treatment",
                   final_loss = r.final_loss, bfgs_ok = r.bfgs_ok,
                   forecast_V_rmse = pick(r.metrics, "forecast", "V_rmse"),
                   forecast_ICa_rmse = pick(r.metrics, "forecast", "ICa_rmse"),
                   train_V_rmse = pick(r.metrics, "train", "V_rmse")))
end

df  = DataFrame(rows)
out = joinpath(ENV["HH_RESULTS_DIR"], "noise_weighted_summary.csv")
CSV.write(out, df)

println("\n=== SUMMARY ===")
show(stdout, df; allrows = true, allcols = true)
println("\n\nwrote $out")

chi = df[df.objective .== "chi2", :]
@printf("\nchi2 arm, n=%d: forecast V RMSE %.4f +- %.4f mV   (published sse arm: 0.2452 +- 0.0284)\n",
        nrow(chi), mean(chi.forecast_V_rmse), std(chi.forecast_V_rmse))
println("""
NOTE: forecast error is NOT the headline for this experiment. The question is
whether the distilled conductance comes back. Next step, no retraining needed:
point the traj-train distillation at results_noiseweighted/calcium/ and compare
a_hat against the published 1.645 +- 0.672.
""")
