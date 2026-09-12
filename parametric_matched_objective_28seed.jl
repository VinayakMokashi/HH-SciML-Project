# =============================================================================
#  parametric_matched_objective_28seed.jl
# =============================================================================
#  FIXES A DENOMINATOR, AND THAT IS THE WHOLE JOB.
#
#  THE PROBLEM IT SOLVES.  The noise-weighting experiment reports how much wider
#  the neural closure scatters than a direct two-parameter fit under the SAME
#  objective -- the "representation effect".  The pilot put that at 3.84x with
#  both arms at n=5.  E1 then took the closure arms to n=28, and the closure's
#  numerator moved a long way: the SSE arm's relative spread went 0.408 -> 0.802
#  when the extra 23 seeds arrived.  The five published seeds were a benign draw.
#
#  So the denominator cannot stay at n=5.  Quoting an n=28 numerator over an n=5
#  denominator would be exactly the kind of unsound ratio this project's audit
#  rounds keep catching, and it would be unsound in the flattering direction:
#  if the parametric arm's spread also grows with n, the representation effect
#  is SMALLER than the ratio would claim.
#
#  WHAT THIS DOES.  Re-runs parametric_matched_objective.jl's chi2 row -- the
#  noise-weighted likelihood, the same objective the :chi2 closures descend -- at
#  gCa = 2.0 across the SAME 28 seeds E1 used.  Same setup(), same eval_all, same
#  three starts, same multi-start Nelder-Mead, same options.  Nothing about the
#  fit changes; only the seed list is longer.
#
#  NO TRAINING.  No network, no adjoint.  Every evaluation is one forward solve
#  of the known six-state model over the training window.
#
#  SELF-TEST, AND IT GATES THE RESULT.  At the five published seeds this must
#  reproduce results/identifiability/parametric_matched_objective.csv (gCa_true
#  2.0, objective chi2) to within SELFTEST_RTOL.  If it does not, this is not the
#  published estimator and its 28-seed spread cannot be set beside the published
#  one, so the script EXITS NON-ZERO.  Same discipline as noise_weighted_ude.jl.
#
#  EXTENDED 2026-09-12: PM_OBJECTIVE selects the objective (chi2 | sse_full |
#  sse_v), default chi2, so the E2 denominator above is reproduced unchanged.
#  PM_OBJECTIVE=sse_full supplies the one cell the n=28 decomposition was
#  missing: the direct fit under the closure's OWN unweighted objective. Without
#  it the paper's "at most a further twofold" bound could only be argued, not
#  tested -- and that bound rested on the objective's effect transferring
#  unchanged from two parameters to the closure, which E1 showed it does not.
#
#  ISOLATION.  Writes results_noiseweighted/parametric_<objective>_28seed.csv ONLY.
#  identifiability_parametric.jl is included with IDENT_PARTS=0, which matches no
#  part, so including it defines the machinery and runs nothing and writes
#  nothing.  NOTHING under results/ is modified -- those files back published
#  macros.
#
#  Run:  julia --project=. parametric_matched_objective_28seed.jl
# =============================================================================

const ROOT = @__DIR__

# IDENT_PARTS=0 matches no part: we get setup, STARTS, forecast_rmse, OUT_DIR and
# ECa with no side effects and no CSV writes. Same trick parametric_matched_objective.jl uses.
ENV["IDENT_PARTS"] = "0"
include(joinpath(ROOT, "identifiability_parametric.jl"))

using Printf, Statistics

const GCA_TRUE   = 2.0
const PM_OBJECTIVE = get(ENV, "PM_OBJECTIVE", "chi2")
#  make_objective returns (sse_full, sse_v, chi2) in that order.
const OBJ_INDEX = Dict("sse_full" => 1, "sse_v" => 2, "chi2" => 3)[PM_OBJECTIVE]
const NSEEDS     = parse(Int, get(ENV, "PM_NSEEDS", "28"))
const PM_SEEDS   = [1111 * k for k in 1:NSEEDS]   # identical rule to NW_SEEDS
const OUT_CSV    = joinpath(ROOT, "results_noiseweighted", "parametric_$(PM_OBJECTIVE)_28seed.csv")
const PUBLISHED  = joinpath(OUT_DIR, "parametric_matched_objective.csv")
const SELFTEST_RTOL = 1e-6

# fit_params with the objective index as an argument. Lifted verbatim from
# parametric_matched_objective.jl:64-78 -- same STARTS, same optimiser, same
# options, same non-finite guard -- so the two cannot drift.
function fit_params_on(eval_all, idx::Int)
    obj(x) = begin
        v = eval_all(x[1], x[2])[idx]
        isfinite(v) ? v : 1.0e12
    end
    best_x, best_f = [NaN, NaN], Inf
    for x0 in STARTS
        res = OPTIM.optimize(obj, copy(x0), OPTIM.NelderMead(),
                             OPTIM.Options(iterations = 2000, g_tol = 1e-10))
        if OPTIM.minimum(res) < best_f
            best_f = OPTIM.minimum(res)
            best_x = OPTIM.minimizer(res)
        end
    end
    return (; gCa = best_x[1], ECa = best_x[2], fmin = best_f)
end

@printf("\n=== Parametric %s fit, gCa = %.1f, %d seeds ===\n", PM_OBJECTIVE, GCA_TRUE, length(PM_SEEDS))
println("Same estimator as the published n=5 row; only the seed list is longer.\n")

rows = NamedTuple[]
for seed in PM_SEEDS
    s   = setup(GCA_TRUE, seed)
    fit = fit_params_on(s.eval_all, OBJ_INDEX)
    fV  = forecast_rmse(fit.gCa, fit.ECa, s.data_clean, s.split.forecast_idx, s.u0)
    push!(rows, (; gCa_true = GCA_TRUE, seed, objective = PM_OBJECTIVE,
                   gCa_hat = fit.gCa, ECa_hat = fit.ECa,
                   a_hat = fit.gCa, b_hat = -fit.gCa * fit.ECa,
                   objective_value = fit.fmin, forecast_V_rmse = fV))
    @printf("  seed %6d   gCa_hat %8.4f   ECa_hat %9.4f\n", seed, fit.gCa, fit.ECa)
end
df = DataFrame(rows)

# =============================================================================
#  SELF-TEST — the five published seeds must come back unchanged.
# =============================================================================
println("\n=== SELF-TEST: the five published seeds vs parametric_matched_objective.csv ===")
if !isfile(PUBLISHED)
    println("*** SELF-TEST CANNOT RUN: $PUBLISHED is missing. ***")
    exit(1)
end
pub = DataFrame(CSV.File(PUBLISHED))
pub = pub[(pub.gCa_true .== GCA_TRUE) .& (pub.objective .== PM_OBJECTIVE), :]

# WRAPPED IN A FUNCTION DELIBERATELY. An accumulator assigned inside a top-level
# `for` is a new local under Julia's soft scope and never reaches the global, so
# the comparison silently reads 0.0 and the self-test passes no matter what.
# This bit on the first run of this script; HANDOFF section 9 has it as a named gotcha.
function selftest_worst(df, pub)
    worst, worst_lbl = 0.0, "(no matching seed)"
    for r in eachrow(pub)
        m = df[df.seed .== r.seed, :]
        nrow(m) == 1 || continue
        for f in (:gCa_hat, :ECa_hat)
            d = abs(m[1, f] - r[f]) / max(abs(r[f]), eps())
            @printf("  seed %6d  %-8s rel diff %.3e\n", r.seed, f, d)
            if d > worst
                worst, worst_lbl = d, "$(f) @ seed $(r.seed)"
            end
        end
    end
    return worst, worst_lbl
end

# An empty overlap would leave worst at 0.0 and pass vacuously. Refuse that.
nrow(pub) == 0 && (println("*** SELF-TEST CANNOT RUN: no published chi2 rows at gCa=$(GCA_TRUE). ***"); exit(1))
worst, worst_lbl = selftest_worst(df, pub)

if !(worst <= SELFTEST_RTOL)
    println("\n*** SELF-TEST FAILED (worst $worst at $worst_lbl). ***")
    println("This is not the published estimator, so its 28-seed spread cannot be")
    println("set beside the published n=5 one. NOT writing the CSV.")
    exit(1)
end
@printf("  PASS -- worst rel diff %.3e. Same estimator, longer seed list.\n", worst)

mkpath(dirname(OUT_CSV))
CSV.write(OUT_CSV, df)

# =============================================================================
#  SUMMARY
# =============================================================================
a = df.a_hat
pub5 = pub.a_hat
@printf("\n=== gCa recovered by the DIRECT two-parameter fit, %s objective ===\n", PM_OBJECTIVE)
@printf("  published n=%d : %.3f +- %.3f   rel sd %.3f\n",
        length(pub5), mean(pub5), std(pub5), std(pub5) / abs(mean(pub5)))
@printf("  this run  n=%d : %.3f +- %.3f   rel sd %.3f\n",
        length(a), mean(a), std(a), std(a) / abs(mean(a)))
println("""
This rel sd is the DENOMINATOR of the representation effect. Feed it to
scripts/distil_noise_weighted.py, which reads this CSV when it is present and
falls back to the published n=5 value (loudly) when it is not.
""")
println("wrote $OUT_CSV")
