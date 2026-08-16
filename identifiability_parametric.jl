# =============================================================================
#  identifiability_parametric.jl
# =============================================================================
#  Mentor request (Prathamesh, 2026-08): the paper demonstrates unstable /
#  practically non-identifiable recovery of the calcium current from one noisy
#  trajectory, but does not yet MEASURE it.  This script supplies the direct
#  parametric evidence:
#
#    (1) a direct two-parameter fit of (gCa, ECa) to the SAME single noisy
#        trajectory, with the true structure known and no neural network,
#    (2) a 2-D loss surface over (gCa, ECa),
#    (3) profile likelihoods for gCa and for ECa with chi-square thresholds,
#    (4) a conditioning analysis (FIM / Hessian eigenvalues at the optimum) in
#        both (gCa,ECa) and the (a,b) coordinates the symbolic stage estimates.
#
#  This is NOT a UDE run: no network, no adjoint, no training.  Every evaluation
#  is one forward solve of the known six-state model over the training window,
#  so the whole script is minutes, not hours.
#
#  ISOLATION: everything is written under results/identifiability/.  The
#  canonical results/ and figures/ trees are never touched (same convention as
#  results/retrain_gca2_20k/).
#
#  Run:  julia --project=. identifiability_parametric.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))

using DataFrames, CSV, Statistics, LinearAlgebra, Printf
using OptimizationOptimJL
const OPTIM = OptimizationOptimJL.Optim

const OUT_DIR = joinpath(ROOT, "results", "identifiability")
mkpath(OUT_DIR)

# Baseline protocol — identical to the headline UDE runs (experiments_runner.jl).
const B_NOISE = 0.02
const B_TWIN  = 30.0
const SEEDS   = [1111, 2222, 3333, 4444, 5555]
const REP_SEED = 1111

# gCa settings to analyse.  The full sweep gets the cheap per-seed fit; the two
# ends of the story (physiological vs. the headline setting) get the expensive
# surface + profile treatment.
const GCA_FIT     = [0.4, 1.0, 2.0, 4.0]
const GCA_PROFILE = [0.4, 2.0]

const SMOKE = get(ENV, "HH_SMOKE", "0") == "1"

# Each of the four parts is self-contained (they share only the setup helpers),
# so any subset can be re-run alone:  IDENT_PARTS=4 julia --project=. <this file>
const PARTS = Set(parse.(Int, split(get(ENV, "IDENT_PARTS", "1,2,3,4"), ",")))

# -----------------------------------------------------------------------------
#  Parametric model: the TRUE right-hand side with (gCa, ECa) as free arguments.
#
#  src/hh_core.jl's make_hh_advanced captures gCa but reads ECa from a const
#  global.  Here BOTH calcium parameters are closure-captured locals, so this is
#  the same physics with the two quantities the recovery task is meant to return
#  turned into estimands.  Everything else is byte-identical to hh_core.
# -----------------------------------------------------------------------------
function make_hh_calcium_params(gCa_p::Float64, ECa_p::Float64)
    return function (du, u, _params, _t)
        V, m, h, n, p, s = u
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

# -----------------------------------------------------------------------------
#  One evaluation = one forward solve over the TRAINING window only, from the
#  true initial condition, on the same saveat grid the UDE was fitted on.
#  Returns three reductions of the same residual matrix:
#
#    sse_full : sum(abs2, .) over all six raw channels.  This is BYTE-FOR-BYTE
#               the objective the full-state UDE minimises (src/experiment.jl
#               line 141) — unweighted, unnormalised, raw units.
#    sse_v    : the same sum over the voltage row alone (the voltage-only UDE
#               objective, src/experiment.jl line 135).
#    chi2     : the properly weighted statistic, sum_(i,t) r_it^2 / sigma_i^2,
#               with sigma_i the KNOWN per-channel noise standard deviation
#               (noise_level * std of that channel's clean signal — exactly how
#               gen_noisy_data builds it).  Only this one is a log-likelihood,
#               so only this one carries a chi-square threshold.
#
#  Reporting all three is the point: the objective the UDE actually descends is
#  not the statistical likelihood, and the reader should be able to see both.
# -----------------------------------------------------------------------------
function make_objective(data_noisy, sigma, train_idx, tsteps_train, tspan_train, u0)
    Vrow = 1
    function eval_all(gCa_p::Float64, ECa_p::Float64)
        local pred
        try
            prob = ODEProblem(make_hh_calcium_params(gCa_p, ECa_p), u0, tspan_train)
            sol  = solve(prob, Tsit5(); saveat = tsteps_train,
                         abstol = 1e-8, reltol = 1e-8, verbose = false)
            pred = Array(sol)
            size(pred, 2) == length(train_idx) || return (Inf, Inf, Inf)
            all(isfinite, pred) || return (Inf, Inf, Inf)
        catch
            return (Inf, Inf, Inf)
        end
        r        = data_noisy[:, train_idx] .- pred
        sse_full = sum(abs2, r)
        sse_v    = sum(abs2, r[Vrow:Vrow, :])
        chi2     = sum(abs2, r ./ sigma)
        return (sse_full, sse_v, chi2)
    end
    return eval_all
end

# Fit by multi-start Nelder-Mead on the chi-square.  Start points deliberately
# EXCLUDE the truth so a good estimate is earned, not assumed.
const STARTS = [[1.0, 60.0], [0.5, 200.0], [3.0, 80.0]]

function fit_params(eval_all)
    obj(x) = begin
        v = eval_all(x[1], x[2])[3]
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
    return (; gCa = best_x[1], ECa = best_x[2], chi2 = best_f)
end

# Forecast quality of a fitted parameter pair, so the parametric fit can be put
# on the same axis as the UDE's forecast V RMSE.
function forecast_rmse(gCa_p, ECa_p, data_clean, forecast_idx, u0)
    prob = ODEProblem(make_hh_calcium_params(gCa_p, ECa_p), u0, TSPAN_FULL)
    sol  = solve(prob, Tsit5(); saveat = TSTEPS, abstol = 1e-8, reltol = 1e-8,
                 verbose = false)
    pred = Array(sol)
    size(pred, 2) == DATASIZE || return NaN
    d = pred[1, forecast_idx] .- data_clean[1, forecast_idx]
    good = isfinite.(d)
    any(good) || return NaN
    return sqrt(mean(abs2, d[good]))
end

# -----------------------------------------------------------------------------
#  Setup helper: build the exact data the UDE saw for one (gCa_true, seed).
# -----------------------------------------------------------------------------
function setup(gCa_true, seed)
    data_clean = gen_clean_data(gCa_true).data_clean
    data_noisy = gen_noisy_data(data_clean, B_NOISE; seed = seed)
    split      = make_split(B_TWIN)
    u0         = steady_state_u0()
    # Known per-channel noise SD, as constructed by gen_noisy_data.
    sigma      = B_NOISE .* std(data_clean, dims = 2)
    eval_all   = make_objective(data_noisy, sigma, split.train_idx,
                                split.tsteps_train, split.tspan_train, u0)
    return (; data_clean, data_noisy, split, u0, sigma, eval_all)
end

# =============================================================================
#  PART 1 — direct parametric fit, every gCa setting x every seed
# =============================================================================
if 1 in PARTS
println("\n=== PART 1: direct (gCa, ECa) fits ===")
fit_rows = NamedTuple[]
for gCa_true in GCA_FIT, seed in SEEDS
    s   = setup(gCa_true, seed)
    fit = fit_params(s.eval_all)
    # Conductance-form coordinates, directly comparable to the symbolic a_hat/b_hat.
    a_hat = fit.gCa
    b_hat = -fit.gCa * fit.ECa
    fV    = forecast_rmse(fit.gCa, fit.ECa, s.data_clean, s.split.forecast_idx, s.u0)
    ndata = 6 * length(s.split.train_idx)
    push!(fit_rows, (; gCa_true, seed,
                       gCa_hat = fit.gCa, ECa_hat = fit.ECa,
                       a_hat, b_hat,
                       a_true = gCa_true, b_true = -gCa_true * ECa,
                       chi2 = fit.chi2, chi2_per_point = fit.chi2 / ndata,
                       sse_full = s.eval_all(fit.gCa, fit.ECa)[1],
                       sse_v    = s.eval_all(fit.gCa, fit.ECa)[2],
                       forecast_V_rmse = fV))
    @printf("  gCa_true=%.1f seed=%d ->  gCa_hat=%8.4f  ECa_hat=%9.3f  fV=%.4f\n",
            gCa_true, seed, fit.gCa, fit.ECa, fV)
end
CSV.write(joinpath(OUT_DIR, "parametric_fit.csv"), DataFrame(fit_rows))
end  # PART 1

# =============================================================================
#  PART 2 — 2-D loss surface over (gCa, ECa)
# =============================================================================
if 2 in PARTS
println("\n=== PART 2: loss surfaces ===")
const NG = SMOKE ? 11 : 101
const GCA_GRID = range(0.0, 5.0;   length = NG)
const ECA_GRID = range(0.0, 300.0; length = NG)

for gCa_true in GCA_PROFILE
    s = setup(gCa_true, REP_SEED)
    rows = NamedTuple[]
    for g in GCA_GRID, e in ECA_GRID
        sf, sv, c2 = s.eval_all(g, e)
        push!(rows, (; gCa_true, seed = REP_SEED, gCa = g, ECa = e,
                       sse_full = sf, sse_v = sv, chi2 = c2))
    end
    CSV.write(joinpath(OUT_DIR, "loss_surface_gca$(gCa_true).csv"), DataFrame(rows))
    println("  surface gCa_true=$gCa_true : $(length(rows)) points")
end
end  # PART 2

# =============================================================================
#  PART 3 — profile likelihoods
# -----------------------------------------------------------------------------
#  Profile for gCa: fix gCa on a grid, RE-OPTIMISE ECa, record the minimum.
#  Profile for ECa: the mirror image.  The 95% pointwise confidence interval is
#  the set where the profile stays within chi2_min + 3.841 (one degree of
#  freedom).  This is the standard practical-identifiability diagnostic of
#  Raue et al. (2009), which the paper already cites.
# =============================================================================
if 3 in PARTS
println("\n=== PART 3: profile likelihoods ===")
const CHI2_95_1DF = 3.841458820694124   # quantile(Chisq(1), 0.95)
const NP = SMOKE ? 9 : 81

function profile_over(eval_all, fixed_grid, free_lo, free_hi, free_start; fix_first::Bool)
    rows = NamedTuple[]
    for xf in fixed_grid
        obj(y) = begin
            v = fix_first ? eval_all(xf, y[1])[3] : eval_all(y[1], xf)[3]
            isfinite(v) ? v : 1.0e12
        end
        # Coarse scan then local polish: the free axis can be almost flat, where
        # a bare local method would stop wherever it started.
        best_y, best_f = free_start, Inf
        for y in range(free_lo, free_hi; length = 61)
            f = obj([y])
            if f < best_f; best_f = f; best_y = y; end
        end
        res = OPTIM.optimize(obj, [best_y], OPTIM.NelderMead(),
                             OPTIM.Options(iterations = 800))
        if OPTIM.minimum(res) < best_f
            best_f = OPTIM.minimum(res)
            best_y = OPTIM.minimizer(res)[1]
        end
        push!(rows, (; fixed = xf, free_hat = best_y, chi2 = best_f))
    end
    return rows
end

for gCa_true in GCA_PROFILE
    s = setup(gCa_true, REP_SEED)

    pg = profile_over(s.eval_all, range(0.0, 5.0; length = NP),
                      0.0, 300.0, 120.0; fix_first = true)
    df_g = DataFrame(pg); rename!(df_g, :fixed => :gCa, :free_hat => :ECa_hat)
    df_g[!, :gCa_true]   = fill(gCa_true, nrow(df_g))
    df_g[!, :delta_chi2] = df_g.chi2 .- minimum(df_g.chi2)
    df_g[!, :within_95]  = df_g.delta_chi2 .<= CHI2_95_1DF
    CSV.write(joinpath(OUT_DIR, "profile_gca_gca$(gCa_true).csv"), df_g)

    pe = profile_over(s.eval_all, range(0.0, 300.0; length = NP),
                      -1.0, 6.0, 2.0; fix_first = false)
    df_e = DataFrame(pe); rename!(df_e, :fixed => :ECa, :free_hat => :gCa_hat)
    df_e[!, :gCa_true]   = fill(gCa_true, nrow(df_e))
    df_e[!, :delta_chi2] = df_e.chi2 .- minimum(df_e.chi2)
    df_e[!, :within_95]  = df_e.delta_chi2 .<= CHI2_95_1DF
    CSV.write(joinpath(OUT_DIR, "profile_eca_gca$(gCa_true).csv"), df_e)

    ing = df_g.gCa[df_g.within_95]; ine = df_e.ECa[df_e.within_95]
    @printf("  gCa_true=%.1f : gCa 95%% CI = [%.3f, %.3f] | ECa 95%% CI = [%.1f, %.1f]\n",
            gCa_true, minimum(ing), maximum(ing), minimum(ine), maximum(ine))
end
end  # PART 3

# =============================================================================
#  PART 4 — conditioning at the optimum
# -----------------------------------------------------------------------------
#  For a Gaussian likelihood the natural conditioning object is the Fisher
#  information matrix.  We build it from FIRST-order sensitivities (the
#  Gauss-Newton form)
#
#      F_ij = sum_(k,t) (1/sigma_k^2) * dpred_kt/dtheta_i * dpred_kt/dtheta_j
#
#  rather than from a finite-difference Hessian of the chi-square.  That choice
#  is deliberate and load-bearing.  This is a spiking model: a small parameter
#  change shifts spike PHASE, so the chi-square rises by ~10^6 within a fraction
#  of a percent of the optimum and its second differences are dominated by that
#  hyper-curvature at any usable step size.  (We checked: a central-difference
#  Hessian returns two nearly equal eigenvalues of order 10^9 and an implied
#  relative standard error of 3e-5, which is contradicted by both the profile
#  likelihood and the observed seed-to-seed spread.)  First differences are
#  stable at small steps and give the standard asymptotic covariance inv(F).
#
#  SCALING: the two parameters carry incommensurate units and very different
#  magnitudes (gCa ~ 2 mS/cm^2 vs ECa ~ 120 mV), so a raw-unit information matrix
#  is dominated by whichever parameter happens to be numerically small and its
#  "sloppy" eigenvector falls on a coordinate axis as a units artifact.  The
#  scale-free object is the information in LOG parameters, which measures
#  sensitivity to FRACTIONAL change: F_log = diag(theta) * F * diag(theta).
#  That is what we report; the raw-unit condition number is kept alongside it.
#
#  The eigenvector of the smallest eigenvalue is the direction in which the data
#  are least informative — the "identifiable combination" picture of Walch &
#  Eisenberg (2016).  We also express the information in the (a,b) coordinates
#  the symbolic stage actually estimates, where I_Ca = s^2(aV + b), a = gCa and
#  b = -gCa*ECa, via the Jacobian of (gCa,ECa) with respect to (a,b):
#      gCa = a, ECa = -b/a  =>  d(gCa)/da = 1, d(gCa)/db = 0,
#                               d(ECa)/da = -ECa/gCa, d(ECa)/db = -1/gCa.
# =============================================================================
if 4 in PARTS
println("
=== PART 4: conditioning ===")

# Predicted training-window trajectory at (gCa, ECa), or `nothing` on failure.
function predict_traj(gCa_p, ECa_p, tsteps_train, tspan_train, u0, ntrain)
    try
        prob = ODEProblem(make_hh_calcium_params(gCa_p, ECa_p), u0, tspan_train)
        sol  = solve(prob, Tsit5(); saveat = tsteps_train,
                     abstol = 1e-10, reltol = 1e-10, verbose = false)
        arr = Array(sol)
        size(arr, 2) == ntrain || return nothing
        all(isfinite, arr) || return nothing
        return arr
    catch
        return nothing
    end
end

cond_rows = NamedTuple[]
for gCa_true in GCA_PROFILE, seed in SEEDS
    s   = setup(gCa_true, seed)
    fit = fit_params(s.eval_all)
    g0, e0 = fit.gCa, fit.ECa
    ntrain = length(s.split.train_idx)
    pt(x, y) = predict_traj(x, y, s.split.tsteps_train, s.split.tspan_train, s.u0, ntrain)

    # Central first differences at a small RELATIVE step.  1e-6 is far inside the
    # quadratic region yet far above the 1e-10 solver tolerance.
    rstep = 1e-6
    dg = rstep * abs(g0); de = rstep * abs(e0)
    Pgp, Pgm = pt(g0 + dg, e0), pt(g0 - dg, e0)
    Pep, Pem = pt(g0, e0 + de), pt(g0, e0 - de)
    if Pgp === nothing || Pgm === nothing || Pep === nothing || Pem === nothing
        @warn "sensitivity solve failed; skipping" gCa_true seed
        continue
    end
    Sg = (Pgp .- Pgm) ./ (2dg)          # dpred/dgCa   (6 x ntrain)
    Se = (Pep .- Pem) ./ (2de)          # dpred/dECa

    W = 1.0 ./ (s.sigma .^ 2)           # per-channel inverse variance (6 x 1)
    Fgg = sum(W .* Sg .* Sg)
    Fee = sum(W .* Se .* Se)
    Fge = sum(W .* Sg .* Se)
    F   = [Fgg Fge; Fge Fee]
    lam_raw = sort(eigen(Symmetric(F)).values; rev = true)

    # --- primary: log-parameter (fractional) information ------------------
    S     = [g0 0.0; 0.0 e0]
    F_log = S * F * S
    evl   = eigen(Symmetric(F_log))
    ord   = sortperm(evl.values; rev = true)
    lam   = evl.values[ord]; vec_ = evl.vectors[:, ord]

    # Asymptotic RELATIVE standard errors: inv(F_log) is already a covariance in
    # fractional units, so a diagonal square root is a relative SD.
    rse_g, rse_e, corr_ge = NaN, NaN, NaN
    try
        C = inv(F_log)
        rse_g = sqrt(max(C[1, 1], 0.0))
        rse_e = sqrt(max(C[2, 2], 0.0))
        corr_ge = C[1, 2] / sqrt(max(C[1, 1] * C[2, 2], eps()))
    catch
    end

    # --- same information in the (a,b) coordinates the symbolic stage fits --
    J    = g0 == 0.0 ? [1.0 0.0; 0.0 0.0] : [1.0 0.0; (-e0 / g0) (-1.0 / g0)]
    F_ab = J' * F * J
    a0, b0 = g0, -g0 * e0
    Sab  = [a0 0.0; 0.0 b0]
    lam2 = sort(eigen(Symmetric(Sab * F_ab * Sab)).values; rev = true)

    push!(cond_rows, (; gCa_true, seed, gCa_hat = g0, ECa_hat = e0,
                        eig_stiff = lam[1], eig_sloppy = lam[2],
                        cond_number = lam[1] / max(lam[2], eps()),
                        sloppy_dir_gCa = vec_[1, 2], sloppy_dir_ECa = vec_[2, 2],
                        stiff_dir_gCa  = vec_[1, 1], stiff_dir_ECa  = vec_[2, 1],
                        rel_se_gCa = rse_g, rel_se_ECa = rse_e, corr_gCa_ECa = corr_ge,
                        eig_stiff_ab = lam2[1], eig_sloppy_ab = lam2[2],
                        cond_number_ab = lam2[1] / max(lam2[2], eps()),
                        cond_number_rawunits = lam_raw[1] / max(lam_raw[2], eps())))
    @printf("  gCa_true=%.1f seed=%d : cond(log)=%.4g  sloppy=(%+.3f,%+.3f)  relSE gCa=%.4f ECa=%.4f  corr=%+.3f
",
            gCa_true, seed, lam[1] / max(lam[2], eps()),
            vec_[1, 2], vec_[2, 2], rse_g, rse_e, corr_ge)
end
CSV.write(joinpath(OUT_DIR, "conditioning.csv"), DataFrame(cond_rows))
end  # PART 4

println("\nDONE. Artifacts in $(OUT_DIR)")
