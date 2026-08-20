# =============================================================================
#  objective3_symbolic.jl  —  Objective 3: symbolic recovery of the learned
#  calcium current from the trained UDE.
# -----------------------------------------------------------------------------
#  Reads the pre-saved calcium probes (results/calcium/*.csv) written by the
#  experiment engine — NO retraining.  The learned neural closure U(V,s) stands
#  in for I_Ca; we distill it back into an interpretable equation.
#
#  Two complementary recoveries, both fit on the grid probe RESTRICTED to the
#  convex hull of the training trajectory (network-INTERPOLATION region, with
#  genuine 2-D (V,s) spread — fitting on the trajectory alone fails because the
#  HH limit cycle is a near-collinear 1-D loop):
#
#    (A) Unconstrained SINDy — sparse regression (standardized STLSQ + OLS
#        debiasing) over a low-order polynomial library.  The "let the data pick
#        the terms" discovery step.
#    (B) Conductance-form recovery — posit the biophysical form
#        I_Ca = s^2 * (a*V + b)   (a gate-squared current with a linear driving
#        force).  The true current gCa*s^2*(V-ECa) is exactly this with a = gCa,
#        b = -gCa*ECa, so a recovers the calcium conductance and -b/a recovers
#        the calcium reversal potential ECa.
#
#  Main setting gCa = 2.0 (5 seeds -> mean +/- std).  Negative / identifiability
#  case gCa = 0.4 (physiological; the current is non-identifiable from this data,
#  so recovery is expected to fail).
#
#  Method self-contained (no DataDrivenSparse) — mirrors the vetted
#  Lotka-Volterra UDE+SINDy reference (relaxed LASSO / thresholded least squares
#  + OLS debiasing).
#
#  Run:  julia --project=. objective3_symbolic.jl
# =============================================================================

using CSV, DataFrames, LinearAlgebra, Statistics, Printf, Plots, Measures
gr()
isinteractive() || (ENV["GKSwstype"] = "100")

const ROOT        = @__DIR__
const CALCIUM_DIR = joinpath(ROOT, "results", "calcium")
const SYM_DIR     = joinpath(ROOT, "results", "symbolic")
const FIG_DIR     = joinpath(ROOT, "figures")
mkpath(SYM_DIR)

# Calcium reversal potential — matches src/hh_core.jl (literature-grounded,
# Reuveni 1993).  The TRUE current gCa*s^2*(V-ECa) = gCa*V*s^2 - gCa*ECa*s^2.
const ECA      = 120.0
const SEEDS    = [1111, 2222, 3333, 4444, 5555]
const REP_SEED = 1111
const TAU      = 0.05    # STLSQ relative threshold

# -----------------------------------------------------------------------------
#  Polynomial candidate library in (V, s) for the SINDy discovery step.
#  Conductance-motivated, low order (products of a gate power with {1, V}); the
#  true active terms V*s^2 and s^2 both live in it.
# -----------------------------------------------------------------------------
const EXPONENTS = [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)]   # 1, V, s, V*s, s^2, V*s^2

function monomial_name(ab)
    a, b = ab
    a == 0 && b == 0 && return "1"
    parts = String[]
    a == 1 && push!(parts, "V");   a >= 2 && push!(parts, "V^$a")
    b == 1 && push!(parts, "s");   b >= 2 && push!(parts, "s^$b")
    return join(parts, "*")
end
design_matrix(V, s) = reduce(hcat, [(V .^ a) .* (s .^ b) for (a, b) in EXPONENTS])
libindex(a, b)      = findfirst(==((a, b)), EXPONENTS)

# --- 2D convex hull (Andrew's monotone chain) + point-in-hull -----------------
function convex_hull(pts)
    P = sort(unique(pts))
    length(P) <= 2 && return P
    cross(o, a, b) = (a[1]-o[1])*(b[2]-o[2]) - (a[2]-o[2])*(b[1]-o[1])
    build(seq) = begin
        h = eltype(P)[]
        for p in seq
            while length(h) >= 2 && cross(h[end-1], h[end], p) <= 0; pop!(h); end
            push!(h, p)
        end
        h
    end
    lower = build(P); upper = build(reverse(P))
    return vcat(lower[1:end-1], upper[1:end-1])
end
function in_hull(pt, hull)
    n = length(hull)
    for i in 1:n
        a = hull[i]; b = hull[mod1(i + 1, n)]
        ((b[1]-a[1])*(pt[2]-a[2]) - (b[2]-a[2])*(pt[1]-a[1])) < -1e-9 && return false
    end
    return true
end

# --- SINDy (A): standardized STLSQ selection + OLS debiasing ------------------
function stlsq_select(Φ, y; τ = TAU, iters = 20)
    ξ = Φ \ y; keep = trues(length(ξ))
    for _ in 1:iters
        any(keep) || break
        newkeep = abs.(ξ) .>= τ * maximum(abs.(ξ[keep]))
        newkeep == keep && break
        keep = newkeep; ξ = zeros(length(ξ))
        any(keep) && (ξ[keep] = Φ[:, keep] \ y)
    end
    return findall(keep)
end
function sindy_recover(Φ, y; τ = TAU)
    M = size(Φ, 2); cidx = libindex(0, 0); ncols = [j for j in 1:M if j != cidx]
    Φn = Φ[:, ncols]; μ = vec(mean(Φn, dims=1)); σ = vec(std(Φn, dims=1)); σ[σ .== 0] .= 1.0
    sel = stlsq_select((Φn .- μ') ./ σ', y; τ = τ)
    active = sort(unique(vcat(cidx, ncols[sel])))
    β = zeros(M); β[active] = Φ[:, active] \ y
    return β, active
end

# --- Conductance form (B): I_Ca = s^2*(a*V + b) ------------------------------
fit_conductance(V, s, y) = hcat(V .* s .^ 2, s .^ 2) \ y      # -> [a, b]

rmse(a, b) = sqrt(mean(abs2, a .- b))
r2(pred, targ) = (ss = sum(abs2, targ .- mean(targ)); ss == 0 ? NaN : 1 - sum(abs2, targ .- pred) / ss)
format_expr(β) = join([@sprintf("%+.4g*%s", β[i], monomial_name(EXPONENTS[i]))
                       for i in eachindex(β) if β[i] != 0], "  ")

# -----------------------------------------------------------------------------
#  Per-configuration recovery.
# -----------------------------------------------------------------------------
load_grid(tag, seed) = CSV.read(joinpath(CALCIUM_DIR, "grid_$(tag)_seed$(seed).csv"), DataFrame)
load_traj(tag, seed) = CSV.read(joinpath(CALCIUM_DIR, "probe_$(tag)_seed$(seed).csv"), DataFrame)

function recover_config(tag, seed, gCa; τ = TAU)
    tr = load_traj(tag, seed)
    t = Float64.(tr.t); V = Float64.(tr.V); s = Float64.(tr.s)
    ICa_nn = Float64.(tr.ICa_nn); ICa_true = Float64.(tr.ICa_true)

    # fit domain = grid points inside the trajectory's (V,s) convex hull
    g = load_grid(tag, seed)
    Vg = Float64.(g.V); sg = Float64.(g.s)
    ICa_nn_g = Float64.(g.ICa_nn); ICa_true_g = Float64.(g.ICa_true)
    hull   = convex_hull([(V[i], s[i]) for i in eachindex(V)])
    inside = [in_hull((Vg[i], sg[i]), hull) for i in eachindex(Vg)]
    Vg, sg = Vg[inside], sg[inside]
    ICa_nn_g, ICa_true_g = ICa_nn_g[inside], ICa_true_g[inside]
    Φg = design_matrix(Vg, sg)

    # (A) unconstrained SINDy over the polynomial library
    β, active = sindy_recover(Φg, ICa_nn_g; τ = τ)
    ICa_sindy = design_matrix(V, s) * β

    # (B) conductance form  I_Ca = s^2*(a*V + b)
    a_hat, b_hat = fit_conductance(Vg, sg, ICa_nn_g)
    a_san, b_san = fit_conductance(Vg, sg, ICa_true_g)          # sanity: fit TRUE current
    ICa_cond = a_hat .* V .* s .^ 2 .+ b_hat .* s .^ 2

    return (; tag, seed, gCa, β, active, nactive = length(active),
              expr = format_expr(β), n_fit = length(Vg),
              Vg, sg, nn_g = ICa_nn_g, tru_g = ICa_true_g,   # masked grid, for pooling
              a_true = gCa, b_true = -gCa * ECA, Erev_true = ECA,
              a_hat, b_hat, Erev = -b_hat / a_hat, a_san, b_san,
              t, V, s, ICa_nn, ICa_true, ICa_sindy, ICa_cond,
              # conductance-form agreement (headline)
              r2_cond_true = r2(ICa_cond, ICa_true), r2_cond_nn = r2(ICa_cond, ICa_nn),
              rmse_cond_true = rmse(ICa_cond, ICa_true),
              # SINDy-form agreement
              r2_sindy_true = r2(ICa_sindy, ICa_true), r2_sindy_nn = r2(ICa_sindy, ICa_nn),
              # network vs true (context)
              rmse_nn_true = rmse(ICa_nn, ICa_true), r2_nn_true = r2(ICa_nn, ICa_true))
end

# =============================================================================
#  Run recovery
# =============================================================================
println("="^76)
println(" Objective 3 — symbolic recovery of the learned calcium current")
println("="^76)
println("True:  I_Ca = gCa*s^2*(V - ECa) = (+gCa)*V*s^2 + (-gCa*ECa)*s^2   (ECa=$ECA)\n")

res_main = [recover_config("ude_full", sd, 2.0) for sd in SEEDS]
res_neg  = recover_config("abl_gca_0.4", REP_SEED, 0.4)

agg(v) = (mean(v), std(v))

println("---- (A) unconstrained SINDy over the polynomial library, gCa=2.0 ----")
for r in res_main
    @printf("seed %d : %d terms | R2 vs true %.3f | I_Ca ~ %s\n",
            r.seed, r.nactive, r.r2_sindy_true, r.expr)
end
println("  -> the two physical terms s^2 and V*s^2 dominate, but the fit does not fully")
println("     sparsify: the network's small departures from the exact form leak into the")
println("     correlated low-order terms (an identifiability limit, not a code issue).")

println("\n---- (B) conductance-form recovery  I_Ca = s^2*(a*V + b),  gCa=2.0 ----")
for r in res_main
    @printf("seed %d : a=%.3f  b=%.1f  Erev=-b/a=%.1f mV | R2(vs true)=%.4f  R2(vs neural)=%.4f\n",
            r.seed, r.a_hat, r.b_hat, r.Erev, r.r2_cond_true, r.r2_cond_nn)
end
am, as = agg([r.a_hat for r in res_main]); bm, bs = agg([r.b_hat for r in res_main])
r2tm, r2ts = agg([r.r2_cond_true for r in res_main])
# ensemble estimate: pool all seeds' hull-grid data and fit once (stable Erev —
# the per-seed ratio -b/a is noisy when a is small, so we report the pooled value).
Vp = vcat([r.Vg for r in res_main]...); sp = vcat([r.sg for r in res_main]...)
nnp = vcat([r.nn_g for r in res_main]...); trup = vcat([r.tru_g for r in res_main]...)
a_ens, b_ens = fit_conductance(Vp, sp, nnp); Erev_ens = -b_ens / a_ens
r2_ens = r2(a_ens .* Vp .* sp .^ 2 .+ b_ens .* sp .^ 2, trup)
@printf("\n  per-seed mean +/- std:   a = %.3f +/- %.3f (true 2.0)   b = %.1f +/- %.1f (true -240)\n", am, as, bm, bs)
@printf("  ensemble (pooled) fit :  a = %.3f   b = %.1f   Erev = -b/a = %.1f mV   R2(vs true)=%.4f\n",
        a_ens, b_ens, Erev_ens, r2_ens)
@printf("    -> recovered  gCa ~ %.2f (true 2.0) ,  ECa ~ %.0f mV (true 120)\n", a_ens, Erev_ens)
@printf("    R2(symbolic vs true I_Ca), per-seed : %.4f +/- %.4f\n", r2tm, r2ts)
@printf("  [sanity] fitting the TRUE current on the same domain: a=%.4f b=%.2f (expect 2.0, -240)\n",
        res_main[1].a_san, res_main[1].b_san)

println("\n---- gCa = 0.4 (physiological; identifiability NEGATIVE case) ----")
@printf("  conductance : a=%.3f (true 0.40)  b=%.1f (true -48.0)  Erev=%.1f mV | R2(vs true)=%.4f\n",
        res_neg.a_hat, res_neg.b_hat, res_neg.Erev, res_neg.r2_cond_true)
@printf("  SINDy       : %d terms | R2 vs true %.3f | I_Ca ~ %s\n",
        res_neg.nactive, res_neg.r2_sindy_true, res_neg.expr)
println("  -> recovery fails: the calcium current is a negligible, non-identifiable")
println("     contribution at the physiological conductance.")

# =============================================================================
#  Persist results
# =============================================================================
open(joinpath(SYM_DIR, "learned_calcium_equation.txt"), "w") do io
    println(io, "Objective 3 — symbolic recovery of the learned calcium current")
    println(io, "True form: I_Ca = gCa*s^2*(V-ECa) = (+gCa)*V*s^2 + (-gCa*ECa)*s^2 ,  ECa=$ECA")
    println(io)
    println(io, "== gCa = 2.0 (main setting) ==")
    println(io, "Conductance-form recovery  I_Ca = s^2*(a*V + b):")
    println(io, @sprintf("  per-seed  a = %.3f +/- %.3f (true 2.000)   b = %.1f +/- %.1f (true -240.0)", am, as, bm, bs))
    println(io, @sprintf("  ensemble  a = gCa ~ %.3f   b ~ %.1f   Erev = -b/a ~ %.1f mV (true 120.0)", a_ens, b_ens, Erev_ens))
    println(io, @sprintf("  R2(symbolic vs true I_Ca) = %.4f +/- %.4f (per-seed) ; %.4f (ensemble)", r2tm, r2ts, r2_ens))
    println(io)
    println(io, "Representative seed $(REP_SEED):")
    println(io, @sprintf("  I_Ca ~ %+.3f*V*s^2  %+.1f*s^2", res_main[1].a_hat, res_main[1].b_hat))
    println(io, "  Unconstrained SINDy (6-term library): I_Ca ~ ", res_main[1].expr)
    println(io, @sprintf("  R2(SINDy vs true) = %.4f", res_main[1].r2_sindy_true))
    println(io)
    println(io, "== gCa = 0.4 (physiological; negative / non-identifiable case) ==")
    println(io, @sprintf("  conductance: a=%.3f (true 0.40) b=%.1f (true -48.0) Erev=%.1f mV",
                         res_neg.a_hat, res_neg.b_hat, res_neg.Erev))
    println(io, @sprintf("  R2(symbolic vs true I_Ca) = %.4f  -> recovery fails", res_neg.r2_cond_true))
end

open(joinpath(SYM_DIR, "symbolic_recovery_metrics.csv"), "w") do io
    println(io, "gCa,seed,a_hat,a_true,b_hat,b_true,Erev,Erev_true,",
                "r2_cond_true,r2_cond_nn,r2_sindy_true,r2_sindy_nn,rmse_nn_true,n_sindy_terms")
    for r in vcat(res_main, res_neg)
        println(io, join((r.gCa, r.seed, r.a_hat, r.a_true, r.b_hat, r.b_true, r.Erev, r.Erev_true,
                          r.r2_cond_true, r.r2_cond_nn, r.r2_sindy_true, r.r2_sindy_nn,
                          r.rmse_nn_true, r.nactive), ","))
    end
end

open(joinpath(SYM_DIR, "sindy_coefficients.csv"), "w") do io
    hdr = ["basis"; ["gca2.0_seed$(sd)" for sd in SEEDS]; "gca0.4_seed$(REP_SEED)"]
    println(io, join(hdr, ","))
    for i in eachindex(EXPONENTS)
        row = Any[monomial_name(EXPONENTS[i])]
        for r in res_main; push!(row, r.β[i]); end
        push!(row, res_neg.β[i])
        println(io, join(row, ","))
    end
end

# =============================================================================
#  Figures
# =============================================================================
r0 = res_main[1]

# --- fig9: parity — conductance & neural vs true (gCa=2.0, rep seed) ----------
let
    lo = minimum(vcat(r0.ICa_true, r0.ICa_cond, r0.ICa_nn))
    hi = maximum(vcat(r0.ICa_true, r0.ICa_cond, r0.ICa_nn))
    pad = 0.05 * (hi - lo); lims = (lo - pad, hi + pad)
    # Sized for print, not for the screen. This panel used the Plots default
    # 600x400 canvas and default ~11 pt fonts; placed at 0.44\textwidth that put
    # its axis text at roughly 3.8 pt against 10 pt body text, and 600 px across
    # 2.9 in is 210 DPI. A font f on a canvas W px wide, printed at a fraction p
    # of a 6.5 in text width, lands at f * p * 6.5 * 72 / W pt: at W = 1250 and
    # p = 0.62 that is f * 0.232, so 30 pt ticks print at 7.0 pt and the canvas
    # is 310 DPI. The parity plot keeps aspect_ratio = :equal, so the canvas is
    # square and the margins have to grow with the fonts.
    p = scatter(r0.ICa_true, r0.ICa_nn, ms = 5, alpha = 0.3, color = :darkorange,
                label = "neural U(V,s)", xlabel = "true I_Ca (μA/cm²)",
                ylabel = "recovered I_Ca (μA/cm²)", legend = :bottomright,
                title = "Calcium-current recovery, seed $(REP_SEED)",
                xlims = lims, ylims = lims, aspect_ratio = :equal,
                size = (1250, 1250), titlefontsize = 30, guidefontsize = 30,
                tickfontsize = 29, legendfontsize = 25,
                left_margin = 14mm, bottom_margin = 12mm,
                right_margin = 8mm, top_margin = 5mm)
    scatter!(p, r0.ICa_true, r0.ICa_cond, ms = 5, alpha = 0.5, color = :seagreen,
             label = "symbolic s²(aV+b)")
    plot!(p, [lims...], [lims...], color = :black, ls = :dash, lw = 3, label = "y = x")
    savefig(p, joinpath(FIG_DIR, "fig9_calcium_symbolic_parity.png"))
end

# --- fig10: I_Ca(t) along the trajectory — true / neural / symbolic ----------
let
    p = plot(r0.t, r0.ICa_true, lw = 2.5, color = :black, label = "true I_Ca",
             xlabel = "t (ms)", ylabel = "I_Ca (μA/cm²)", legend = :outertop, legendcolumns = 3,
             title = "Learned vs true calcium current (gCa=2.0)", titlefontsize = 11,
             size = (820, 420), left_margin = 4mm, bottom_margin = 4mm)
    plot!(p, r0.t, r0.ICa_nn,   lw = 2, ls = :dash, color = :darkorange, label = "neural U(V,s)")
    plot!(p, r0.t, r0.ICa_cond, lw = 2, ls = :dot,  color = :seagreen,   label = "symbolic s²(aV+b)")
    savefig(p, joinpath(FIG_DIR, "fig10_calcium_symbolic_timeseries.png"))
end

# --- fig11: coefficient recovery vs truth (gCa=2.0, mean±std over seeds) ------
let
    a_hats = [r.a_hat for r in res_main]; b_hats = [r.b_hat for r in res_main]
    am_, as_ = mean(a_hats), std(a_hats); bm_, bs_ = mean(b_hats), std(b_hats)
    p1 = bar(["true", "recovered"], [2.0, am_], legend = false, yerror = [0.0, as_],
             color = [:gray, :seagreen], title = "a = gCa  (per-seed mean±std)", ylabel = "conductance",
             ylims = (0, max(2.0, am_ + as_) * 1.18), bar_width = 0.6,
             left_margin = 7mm, bottom_margin = 5mm, top_margin = 3mm)
    p2 = bar(["true", "recovered"], [-240.0, bm_], legend = false, yerror = [0.0, bs_],
             color = [:gray, :seagreen], title = "b = -gCa*ECa  (per-seed mean±std)", ylabel = "coefficient",
             ylims = (min(-240.0, bm_ - bs_) * 1.15, 15), bar_width = 0.6,
             left_margin = 7mm, bottom_margin = 5mm, top_margin = 3mm)
    p3 = bar(["true", "recovered"], [120.0, Erev_ens], legend = false,
             color = [:gray, :steelblue], title = "Erev = -b/a  (ensemble)", ylabel = "reversal potential (mV)",
             ylims = (0, max(120.0, Erev_ens) * 1.18), bar_width = 0.6,
             left_margin = 7mm, bottom_margin = 5mm, top_margin = 3mm)
    savefig(plot(p1, p2, p3, layout = (1, 3), size = (1500, 560),
                 plot_title = "Recovered calcium parameters vs truth (gCa=2.0, 5 seeds)",
                 plot_titlefontsize = 13),
            joinpath(FIG_DIR, "fig11_calcium_coeff_recovery.png"))
end

# --- fig12: identifiability — gCa=2.0 (recoverable) vs gCa=0.4 (not) ----------
let
    common = (; xlabel = "t (ms)", ylabel = "I_Ca (μA/cm²)", legend = :outertop, legendcolumns = 2,
                left_margin = 4mm, bottom_margin = 4mm)
    pg = plot(r0.t, r0.ICa_true, lw = 2.5, color = :black, label = "true",
              title = @sprintf("gCa=2.0: recoverable (R²=%.3f)", r0.r2_cond_true); common...)
    plot!(pg, r0.t, r0.ICa_cond, lw = 2, ls = :dot, color = :seagreen, label = "symbolic")
    pb = plot(res_neg.t, res_neg.ICa_true, lw = 2.5, color = :black, label = "true",
              title = @sprintf("gCa=0.4: non-identifiable (R²=%.3f)", res_neg.r2_cond_true); common...)
    plot!(pb, res_neg.t, res_neg.ICa_cond, lw = 2, ls = :dot, color = :crimson, label = "symbolic")
    savefig(plot(pg, pb, layout = (1, 2), size = (1150, 500),
                 plot_title = "Symbolic recovery is meaningful only when the current is identifiable",
                 plot_titlefontsize = 11),
            joinpath(FIG_DIR, "fig12_calcium_identifiability.png"))
end

# =============================================================================
#  assert outputs
# =============================================================================
let
    want = [joinpath(SYM_DIR, f) for f in
            ("learned_calcium_equation.txt", "symbolic_recovery_metrics.csv", "sindy_coefficients.csv")]
    append!(want, [joinpath(FIG_DIR, f) for f in
            ("fig9_calcium_symbolic_parity.png", "fig10_calcium_symbolic_timeseries.png",
             "fig11_calcium_coeff_recovery.png", "fig12_calcium_identifiability.png")])
    miss = filter(f -> !isfile(f), want)
    isempty(miss) ? println("\n✓ all ", length(want), " Objective-3 artifacts written.") :
                    (println("\n✗ MISSING:"); foreach(m -> println("   - ", m), miss);
                     error("objective3: missing $(length(miss)) artifact(s)"))
end
println("\n[Objective 3 complete]  results -> results/symbolic/   figures -> figures/fig9-12")
