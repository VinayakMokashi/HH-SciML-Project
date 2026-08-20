# =============================================================================
#  parametric_matched_objective.jl
# =============================================================================
#  Closes the objective confound that the 2026-08 referee round exposed.
#
#  THE PROBLEM.  The paper sets a parametric (gCa, ECa) fit beside the estimate
#  distilled from the neural closure and reads the difference in spread as a
#  property of the REPRESENTATION. But the two arms never minimised the same
#  thing. The UDE descends an unweighted, native-units sum of squares
#  (make_ude_loss, src/experiment.jl) which is 99.97% voltage by construction;
#  the parametric reference descends the noise-weighted chi-square
#  (identifiability_parametric.jl, fit_params selects eval_all(...)[3]), in which
#  all six channels count comparably. Representation, objective and optimiser all
#  changed at once, and nothing in the repository separated them. Until now the
#  paper could only DISCLOSE that; a referee could still say the comparison was
#  never controlled.
#
#  WHAT THIS DOES.  Re-runs the SAME multi-start Nelder-Mead, on the SAME data,
#  from the SAME three starting points, over the SAME two free parameters -- and
#  changes exactly one thing: which reduction of the residual it minimises.
#
#      sse_full  (index 1)  the full-state UDE's own objective, byte-for-byte
#      sse_v     (index 2)  the voltage-only UDE's objective
#      chi2      (index 3)  the weighted likelihood the paper already reports
#
#  With representation held fixed at two parameters and the true functional form,
#  any spread difference across these three rows is the OBJECTIVE alone. That is
#  the control the comparison was missing.
#
#  NO TRAINING. No network, no adjoint. Every evaluation is one forward solve of
#  the known six-state model over the training window, exactly as in Part 1.
#
#  SELF-TEST. The chi2 row must reproduce results/identifiability/parametric_fit.csv
#  to machine precision -- same harness, same starts, same objective index. If it
#  does not, this script is not running the comparison it claims to and the other
#  two rows mean nothing. It exits non-zero in that case.
#
#  ISOLATION: writes results/identifiability/parametric_matched_objective.csv.
#  parametric_fit.csv is NOT touched -- it backs published macros.
#
#  Run:  julia --project=. parametric_matched_objective.jl
# =============================================================================

const ROOT = @__DIR__

# Load the Part-1 machinery without running any of its parts. PARTS is built from
# IDENT_PARTS, so a value no part matches gives us the functions and constants
# (setup, make_objective, STARTS, forecast_rmse, SEEDS, GCA_FIT, OUT_DIR, ECa)
# with no side effects and no CSV writes.
ENV["IDENT_PARTS"] = "0"
include(joinpath(ROOT, "identifiability_parametric.jl"))

using Printf

# The three reductions make_objective returns, in its own order.
const OBJECTIVES = [(1, "sse_full", "unweighted SSE, all six channels (the full-state UDE's own loss)"),
                    (2, "sse_v",    "unweighted SSE, voltage row only (the voltage-only UDE's loss)"),
                    (3, "chi2",     "noise-weighted chi-square (the paper's reference; a likelihood)")]

# fit_params hard-codes index 3. This is that function with the index as an
# argument and nothing else changed -- same STARTS, same optimiser, same options,
# same non-finite guard.
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

println("\n=== Matched-objective parametric fits (no training) ===")
println("Same data, same two free parameters, same true form, same starts.")
println("The ONLY thing that varies down the rows is the objective.\n")

rows = NamedTuple[]
for gCa_true in GCA_FIT, seed in SEEDS, (idx, name, _) in OBJECTIVES
    s   = setup(gCa_true, seed)
    fit = fit_params_on(s.eval_all, idx)
    all3 = s.eval_all(fit.gCa, fit.ECa)
    fV  = forecast_rmse(fit.gCa, fit.ECa, s.data_clean, s.split.forecast_idx, s.u0)
    push!(rows, (; gCa_true, seed, objective = name,
                   gCa_hat = fit.gCa, ECa_hat = fit.ECa,
                   a_hat = fit.gCa, b_hat = -fit.gCa * fit.ECa,
                   objective_value = fit.fmin,
                   sse_full = all3[1], sse_v = all3[2], chi2 = all3[3],
                   forecast_V_rmse = fV))
end
df = DataFrame(rows)
CSV.write(joinpath(OUT_DIR, "parametric_matched_objective.csv"), df)

# -----------------------------------------------------------------------------
#  Summary: relative spread of gCa_hat across seeds, per objective per setting.
# -----------------------------------------------------------------------------
println("gCa_true  objective   gCa_hat (mean +/- SD)      rel.SD     ECa_hat (mean +/- SD)")
function summarise(df)
    out = NamedTuple[]
    for g in sort(unique(df.gCa_true)), (_, name, _) in OBJECTIVES
        d = df[(df.gCa_true .== g) .& (df.objective .== name), :]
        nrow(d) >= 2 || continue
        gm, gs = mean(d.gCa_hat), std(d.gCa_hat)
        em, es = mean(d.ECa_hat), std(d.ECa_hat)
        push!(out, (; gCa_true = g, objective = name, g_mean = gm, g_sd = gs,
                      rel_sd = gs / abs(gm), e_mean = em, e_sd = es, n = nrow(d)))
        @printf("  %.1f    %-9s   %7.3f +/- %-7.3f  %6.1f%%    %8.2f +/- %.2f\n",
                g, name, gm, gs, 100 * gs / abs(gm), em, es)
    end
    return out
end
summ = DataFrame(summarise(df))
CSV.write(joinpath(OUT_DIR, "parametric_matched_objective_summary.csv"), summ)

# -----------------------------------------------------------------------------
#  SELF-TEST against the published chi-square fit.
# -----------------------------------------------------------------------------
pub = CSV.read(joinpath(OUT_DIR, "parametric_fit.csv"), DataFrame)

function worst_vs_published(df, pub)
    worst, lbl, n = 0.0, "", 0
    for r in eachrow(df)
        r.objective == "chi2" || continue
        m = pub[(pub.gCa_true .== r.gCa_true) .& (pub.seed .== r.seed), :]
        nrow(m) == 1 || continue
        for f in (:gCa_hat, :ECa_hat, :chi2)
            a, b = Float64(getproperty(r, f)), Float64(m[1, f])
            (isfinite(a) && isfinite(b) && b != 0) || continue
            n += 1
            d = abs(a - b) / abs(b)
            if d > worst
                worst, lbl = d, "$(f) @ gCa=$(r.gCa_true) seed=$(r.seed)"
            end
        end
    end
    return worst, lbl, n
end

worst, lbl, ncmp = worst_vs_published(df, pub)
@printf("\n  self-test: %d chi2-row values compared with parametric_fit.csv\n", ncmp)
@printf("             worst relative disagreement %.3e  (%s)\n", worst, lbl)
if worst > 1e-6
    println("\n  FAIL: the chi2 row does not reproduce the published fit, so this is not")
    println("        the same harness and the matched-objective rows cannot be trusted.")
    exit(1)
end
println("             OK -- identical harness; the only variable across rows is the objective.")

@printf("\nwrote %s\n", joinpath(OUT_DIR, "parametric_matched_objective.csv"))
@printf("      %s\n", joinpath(OUT_DIR, "parametric_matched_objective_summary.csv"))
