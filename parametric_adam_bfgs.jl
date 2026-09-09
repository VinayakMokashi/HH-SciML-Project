# =============================================================================
#  parametric_adam_bfgs.jl   --   E2: ISOLATE THE OPTIMISER
# =============================================================================
#  THE GAP THIS CLOSES.  E1 measured, at a MATCHED objective, that the neural
#  closure's recovered gCa scatters 4.69x wider than a direct two-parameter fit
#  (rel sd 0.314 against 0.067, n=28, both descending the noise-weighted chi2).
#  That number is still not clean, because two things differ between the arms:
#
#      arm          representation      optimiser
#      closure      337 net weights     single-start Adam(1e-2) + BFGS
#      parametric   2 parameters        3-start Nelder-Mead
#
#  So "4.69x" is representation AND optimiser, and the paper can only say the
#  optimiser share is "at most" the whole of it. This script fits the SAME two
#  parameters on the SAME data under the SAME chi2 objective with the CLOSURE'S
#  optimiser and the closure's budget, so the two shares separate:
#
#      spread(2 params, Adam+BFGS) / spread(2 params, Nelder-Mead)  = optimiser
#      spread(closure,  Adam+BFGS) / spread(2 params, Adam+BFGS)    = representation
#
#  THE HONEST CAVEAT, and it must be stated wherever this is quoted: Nelder-Mead
#  will not run on 337 parameters, so this isolates the optimiser only at the
#  two-parameter end. It does not prove the same optimiser share applies at 337.
#
#  ---------------------------------------------------------------------------
#  PARAMETER SCALING IS A REAL CONFOUND HERE AND IT IS HANDLED EXPLICITLY.
#  Adam takes a step of fixed SIZE, so what it does depends on the scale of the
#  coordinate it steps along. The closure's 337 weights are O(1). The parametric
#  coordinates are not: gCa ~ 2 but ECa ~ 120. At lr = 1e-2 Adam needs ~12000
#  steps to traverse ECa once, so a raw-scale run would measure a step-size
#  mismatch and report it as an optimiser effect.
#
#  So the fit is done in a NORMALISED coordinate, theta = [gCa, ECa/ECA_SCALE],
#  with ECA_SCALE = 100 -- both coordinates O(1), matching the scale Adam faces
#  in the closure. This is house convention already: the closure's own network
#  is fed V/100 (src/experiment.jl, Vn = Vt ./ 100.0).
#
#  THE SCALE IS CLOSED OVER, NOT CARRIED IN theta. Putting it in the parameter
#  vector would hand Adam a third coordinate to update, over-parameterising a
#  two-parameter fit and changing the very geometry this script is measuring.
#  theta is two-dimensional, exactly as the Nelder-Mead arm's is.
#
#  AND THE RAW-SCALE RUN IS DONE TOO, as a sensitivity. PA_SCALES controls it.
#  Reporting both shows the scale dependence instead of hiding it -- if the two
#  disagree, the honest headline is that Adam's optimiser share is not
#  scale-free, which is itself worth knowing.
#
#  ---------------------------------------------------------------------------
#  STARTS. The closure gets ONE start (its network init); the parametric arm's
#  published recipe takes the best of three. Both are reported: every start is
#  fitted and written out, so the summary can quote best-of-3 (comparable to the
#  Nelder-Mead recipe) or the per-start spread (comparable to the closure's
#  single start). Mixing them would confound the optimiser with the multi-start.
#
#  SELF-TEST, AND IT GATES EVERYTHING.  The published objective is not
#  differentiable -- make_hh_calcium_params hard-types ::Float64 and eval_all
#  wraps a try/catch -- so the chi2 here is a MIRROR, and a mirror must prove it
#  is the original. At the published Nelder-Mead optimum for every published
#  seed, and in BOTH coordinate scalings, this script's chi2 must equal
#  identifiability_parametric.jl's eval_all(...)[3] to within SELFTEST_RTOL. If
#  it does not, the loss being descended is not the loss the other arms descend
#  and no comparison across them means anything, so the script EXITS NON-ZERO
#  before fitting.
#
#  ---------------------------------------------------------------------------
#  THE SENSITIVITY ALGORITHM IS NOT THE OPTIMISER, AND IT IS SUBSTITUTED.
#  src/experiment.jl:75 configures InterpolatingAdjoint(ReverseDiffVJP(true)) --
#  the right choice for the closure's 337 parameters, and the wrong tool for two,
#  where it pays for a full backward ODE solve to get a gradient forward mode
#  gets almost free. Measured here: 0.083 s/grad reverse against 0.006 s/grad
#  forward, a 13x difference that turned a ~38 h grid into a ~3 h one.
#
#  The gradient is the SAME MATHEMATICAL OBJECT either way, so this changes the
#  cost of the experiment and not the experiment -- PROVIDED the two agree, and
#  agreement is not assumed. The self-test below recomputes the chi2 gradient
#  under BOTH and fails the run if they differ by more than GRAD_RTOL. Measured
#  agreement at the benchmark point was 9.4e-08, which is the numerical noise
#  floor for abstol/reltol 1e-8. PA_SENSEALG=adjoint reverts to the closure's own
#  setting if that is ever wanted.
#
#  What is emphatically NOT substituted: the optimiser, its learning rate, its
#  iteration budget, the objective, the starts, or the data. Those are the
#  experiment.
#
#  ISOLATION. Writes results_noiseweighted/parametric_adam_bfgs.csv ONLY.
#  identifiability_parametric.jl is included with IDENT_PARTS=0, which matches no
#  part, so it defines the machinery and runs and writes nothing. HH_RESULTS_DIR
#  is set BEFORE the includes so src/experiment.jl's mkpath lands in the isolated
#  tree. NOTHING under results/ is modified.
#
#  RESUMABLE. A (seed, scaling, start) cell already in the CSV is skipped and
#  carried forward; the CSV is rewritten after every fit. PA_FORCE=1 disables it.
#
#  Run:  julia --project=. parametric_adam_bfgs.jl
#        PA_NSEEDS=1 julia --project=. parametric_adam_bfgs.jl     # quick check
# =============================================================================

const ROOT = @__DIR__

# MUST precede the includes: src/experiment.jl mkpaths these at include time.
ENV["HH_RESULTS_DIR"] = get(ENV, "PA_RESULTS_DIR", joinpath(ROOT, "results_noiseweighted"))
ENV["HH_FIG_DIR"]     = get(ENV, "PA_FIG_DIR",     joinpath(ROOT, "figures_noiseweighted"))
delete!(ENV, "HH_SMOKE")

ENV["IDENT_PARTS"] = "0"                 # matches no part: defines, runs nothing
include(joinpath(ROOT, "identifiability_parametric.jl"))   # brings in src/hh_core.jl
include(joinpath(ROOT, "src", "metrics.jl"))               # experiment.jl needs it first
include(joinpath(ROOT, "src", "experiment.jl"))            # train_two_stage, ADJOINT

using Printf, Statistics, Zygote

const GCA_TRUE  = 2.0
const ECA_SCALE = 100.0
const PA_NSEEDS = parse(Int, get(ENV, "PA_NSEEDS", "28"))
const PA_SEEDS  = [1111 * k for k in 1:PA_NSEEDS]     # identical rule to NW_SEEDS
const PA_SCALES = [("normalised", ECA_SCALE), ("raw", 1.0)]
const PA_FORCE  = get(ENV, "PA_FORCE", "0") == "1"

# The closure's budget, verbatim (run_experiment / noise_weighted_ude.jl).
const PA_ADAM_LR = 1e-2
const PA_ADAM    = parse(Int, get(ENV, "PA_ADAM", "5000"))
const PA_BFGS    = parse(Int, get(ENV, "PA_BFGS", "300"))

#  Forward-mode by default (2 parameters); "adjoint" restores the closure's own
#  reverse-mode setting. Whichever is chosen is verified against ADJOINT below.
const PA_SENSEALG = get(ENV, "PA_SENSEALG", "forward") == "adjoint" ?
                    ADJOINT : ForwardSensitivity()
const GRAD_RTOL   = 1e-5

const OUT_CSV   = joinpath(ENV["HH_RESULTS_DIR"], "parametric_adam_bfgs.csv")
const PUBLISHED = joinpath(OUT_DIR, "parametric_matched_objective.csv")
const SELFTEST_RTOL = 1e-9

# -----------------------------------------------------------------------------
#  The differentiable mirror of make_hh_calcium_params (identifiability_parametric.jl:63-78).
#  Two changes and no others: the parameters arrive through the ODE's own `p`
#  argument instead of being closed over, and nothing is hard-typed, so dual and
#  tracked numbers pass through. Every current term is character-identical.
#  `scale` is closed over, so theta stays two-dimensional.
# -----------------------------------------------------------------------------
function make_hh_calcium_ad(scale)
    return function (du, u, theta, _t)
        V, m, h, n, p, s = u
        gCa_p = theta[1]
        ECa_p = theta[2] * scale
        I_K   = gK   * n^4     * (V - EK)
        I_Na  = gNa  * m^3 * h * (V - ENa)
        I_L   = gL             * (V - EL)
        I_NaP = gNaP * p       * (V - ENa)
        I_Ca  = gCa_p * s^2    * (V - ECa_p)
        du[1] = (Iapp - I_K - I_Na - I_L - I_NaP - I_Ca) / Cm
        du[2] = alpha_m(V) * (1.0 - m) - beta_m(V) * m
        du[3] = alpha_h(V) * (1.0 - h) - beta_h(V) * h
        du[4] = alpha_n(V) * (1.0 - n) - beta_n(V) * n
        du[5] = alpha_p(V) * (1.0 - p) - beta_p(V) * p
        du[6] = alpha_s(V) * (1.0 - s) - beta_s(V) * s
        return nothing
    end
end

# The chi2 branch of make_objective (identifiability_parametric.jl:117), as a
# differentiable function of theta = [gCa, ECa/scale].
function make_chi2_ad(s, scale, theta0)
    prob   = ODEProblem(make_hh_calcium_ad(scale), s.u0, s.split.tspan_train, theta0)
    idx    = s.split.train_idx
    ntrain = length(idx)
    target = s.data_noisy[:, idx]
    sig    = s.sigma
    return function (theta)
        pred = Array(solve(prob, Tsit5(); p = theta, saveat = s.split.tsteps_train,
                           abstol = 1e-8, reltol = 1e-8, verbose = false,
                           sensealg = PA_SENSEALG))
        size(pred, 2) == ntrain || return 1.0e12
        return sum(abs2, (target .- pred) ./ sig)
    end
end

# =============================================================================
#  SELF-TEST — the mirrored chi2 must BE the published chi2.
# =============================================================================
function run_selftest()
    println("\n=== SELF-TEST: mirrored chi2 vs identifiability_parametric.jl's eval_all ===")
    isfile(PUBLISHED) || (println("*** cannot run: $PUBLISHED missing ***"); return false)
    pub = DataFrame(CSV.File(PUBLISHED))
    pub = pub[(pub.gCa_true .== GCA_TRUE) .& (pub.objective .== "chi2"), :]
    nrow(pub) == 0 && (println("*** cannot run: no published chi2 rows ***"); return false)

    worst = 0.0
    for r in eachrow(pub)
        s = setup(GCA_TRUE, r.seed)
        theirs = s.eval_all(r.gCa_hat, r.ECa_hat)[3]
        # BOTH scalings are checked, so the scale factor is verified rather than
        # assumed harmless: a wrong scale changes the ODE, not just the coordinates.
        for (nm, sc) in PA_SCALES
            th = [r.gCa_hat, r.ECa_hat / sc]
            mine = make_chi2_ad(s, sc, th)(th)
            d = abs(mine - theirs) / abs(theirs)
            @printf("  seed %6d  %-11s  mine %.10f  published %.10f  rel %.3e\n",
                    r.seed, nm, mine, theirs, d)
            d > worst && (worst = d)
        end
    end
    if !(worst <= SELFTEST_RTOL)
        @printf("\n*** SELF-TEST FAILED (worst rel diff %.3e > %.0e). ***\n", worst, SELFTEST_RTOL)
        println("The differentiable chi2 is not the published chi2, so a spread fitted")
        println("under it cannot be set beside the Nelder-Mead spread. Not fitting.")
        return false
    end
    @printf("  PASS -- worst rel diff %.3e. The mirror is the published objective.\n", worst)
    return true
end

# The value check above proves the LOSS is the published loss. It says nothing
# about the GRADIENT, which is what Adam actually descends -- so the substituted
# sensealg is checked separately, against the closure's own ADJOINT, at a point
# OFF the optimum where the gradient is large and informative. A gradient check
# at the optimum would pass on two near-zero vectors and prove nothing.
function run_grad_selftest()
    println("\n=== SELF-TEST: substituted sensealg vs the closure's ADJOINT ===")
    PA_SENSEALG === ADJOINT && (println("  SKIPPED -- PA_SENSEALG=adjoint, nothing substituted."); return true)
    s  = setup(GCA_TRUE, PA_SEEDS[1])
    th = [1.5, 0.9]                     # deliberately off the optimum
    mk(sa) = theta -> begin
        prob = ODEProblem(make_hh_calcium_ad(ECA_SCALE), s.u0, s.split.tspan_train, theta)
        pred = Array(solve(prob, Tsit5(); p = theta, saveat = s.split.tsteps_train,
                           abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = sa))
        sum(abs2, (s.data_noisy[:, s.split.train_idx] .- pred) ./ s.sigma)
    end
    g_ref = Zygote.gradient(mk(ADJOINT), th)[1]
    g_new = Zygote.gradient(mk(PA_SENSEALG), th)[1]
    rel = maximum(abs.(g_new .- g_ref) ./ max.(abs.(g_ref), eps()))
    @printf("  adjoint   [% .8e, % .8e]\n  substituted [% .8e, % .8e]\n  max rel diff %.3e (tol %.0e)\n",
            g_ref[1], g_ref[2], g_new[1], g_new[2], rel, GRAD_RTOL)
    if !(rel <= GRAD_RTOL)
        println("\n*** SELF-TEST FAILED. ***")
        println("The substituted sensealg computes a different gradient, so it would")
        println("change the experiment rather than only its cost. Not fitting.")
        return false
    end
    println("  PASS -- same gradient, cheaper. The substitution is safe.")
    return true
end

run_selftest() || exit(1)
run_grad_selftest() || exit(1)

# =============================================================================
#  FIT — every seed, every scaling, every start.
# =============================================================================
function load_cache()
    c = Dict{Tuple{Int,String,Int},NamedTuple}()
    (PA_FORCE || !isfile(OUT_CSV)) && return c
    try
        for r in CSV.File(OUT_CSV)
            c[(Int(r.seed), String(r.scaling), Int(r.start_idx))] =
                (; seed = Int(r.seed), scaling = String(r.scaling),
                   start_idx = Int(r.start_idx), gCa0 = Float64(r.gCa0), ECa0 = Float64(r.ECa0),
                   gCa_hat = Float64(r.gCa_hat), ECa_hat = Float64(r.ECa_hat),
                   chi2 = Float64(r.chi2), bfgs_ok = Bool(r.bfgs_ok))
        end
        @printf("resume: read %d cached fits\n", length(c))
    catch err
        @warn "resume: unreadable CSV; refitting everything." exception = err
        empty!(c)
    end
    return c
end

const CACHE = load_cache()
const ROWS  = NamedTuple[]
record!(r) = (push!(ROWS, r); CSV.write(OUT_CSV, DataFrame(ROWS)))

function fit_all()
    for seed in PA_SEEDS
        s = setup(GCA_TRUE, seed)
        for (nm, sc) in PA_SCALES, (i, x0) in enumerate(STARTS)
            key = (seed, nm, i)
            if haskey(CACHE, key)
                @printf("[skip] seed %6d %-11s start %d\n", seed, nm, i)
                record!(CACHE[key]); continue
            end
            theta0 = [x0[1], x0[2] / sc]
            tr = train_two_stage(make_chi2_ad(s, sc, theta0), theta0;
                                 adam_lr = PA_ADAM_LR, adam_iters = PA_ADAM,
                                 bfgs_iters = PA_BFGS, label = "param[$nm]")
            gCa_hat, ECa_hat = tr.p[1], tr.p[2] * sc
            @printf("  seed %6d %-11s start %d -> gCa %8.4f  ECa %9.4f  chi2 %12.4f\n",
                    seed, nm, i, gCa_hat, ECa_hat, tr.final_loss)
            record!((; seed, scaling = nm, start_idx = i, gCa0 = x0[1], ECa0 = x0[2],
                       gCa_hat, ECa_hat, chi2 = tr.final_loss, bfgs_ok = tr.bfgs_ok))
        end
    end
end

fit_all()

# =============================================================================
#  SUMMARY
# =============================================================================
df = DataFrame(ROWS)
println("\n=== gCa under Adam+BFGS, two parameters, chi2 objective ===")

function report(label, v)
    length(v) < 2 && return
    @printf("  %-34s n=%2d  %.3f +- %.3f   rel sd %.3f\n",
            label, length(v), mean(v), std(v), std(v) / abs(mean(v)))
end

function summarise(df)
    for (nm, _) in PA_SCALES
        d = df[df.scaling .== nm, :]
        nrow(d) == 0 && continue
        # best-of-3 by chi2 within a seed: the Nelder-Mead recipe's own rule.
        best = Float64[]
        for sd in unique(d.seed)
            g = d[d.seed .== sd, :]
            push!(best, g[argmin(g.chi2), :].gCa_hat)
        end
        report("$nm, best-of-$(length(STARTS))", best)
        for i in 1:length(STARTS)
            report("$nm, start $i alone", d[d.start_idx .== i, :].gCa_hat)
        end
    end
end
summarise(df)

println("""
READ IT THIS WAY. Compare the best-of-3 row against the Nelder-Mead arm's
rel sd 0.067 (results_noiseweighted/parametric_chi2_28seed.csv, same 28 seeds,
same objective, same starts): that ratio is the OPTIMISER's share. Then divide
the closure's 0.314 by THIS row to get the representation share. Quote the
normalised row; the raw row is the scale sensitivity, not the result. And state
the caveat: Nelder-Mead cannot run on 337 parameters, so this isolates the
optimiser at the two-parameter end only.
""")
println("wrote $OUT_CSV")
