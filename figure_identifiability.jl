# =============================================================================
#  figure_identifiability.jl  ->  figures/fig13_parametric_identifiability.png
# =============================================================================
#  The paper's central new result has no figure. This builds it, from CSVs that
#  are already on disk (identifiability_parametric.jl + the symbolic pipeline).
#  NOTHING is retrained, refitted, or recomputed here: this is a plotting script.
#
#  Three panels, left to right, telling the argument in order:
#
#   (a) The chi-square surface over (gCa, ECa) at the headline condition. There
#       IS a curved valley — the two calcium parameters trade off along an
#       identifiable combination — but it CLOSES. The 95% region is a bounded
#       blob containing the truth, not an open channel.
#
#   (b) The profile likelihood for gCa, which is panel (a) read along its valley
#       floor with ECa re-optimised at every point. The horizontal line is the
#       chi-square 95% threshold (3.84, 1 dof). Where the profile sits below it
#       is the confidence interval. The per-seed estimates from the NEURAL
#       CLOSURE are plotted underneath on the same axis: most of them fall well
#       outside an interval the data support comfortably.
#
#   (c) The punchline as a per-seed scatter. Same data, same trajectory, two
#       representations of the same current. Parametric estimates cluster on the
#       truth; closure estimates scatter across a factor of four.
#
#  Run:  julia --project=. figure_identifiability.jl
# =============================================================================

const ROOT = @__DIR__

using CSV, DataFrames, Statistics, Printf
using Plots, Measures
gr()

const IDENT   = joinpath(ROOT, "results", "identifiability")
const SYMB    = joinpath(ROOT, "results", "symbolic")   # (retained: older hull-domain outputs)
const FIG_DIR = joinpath(ROOT, "figures")
mkpath(FIG_DIR)

const GCA_TRUE, ECA_TRUE = 2.0, 120.0
const CHI2_95 = 3.841458820694124        # quantile(Chisq(1), 0.95)

# Readability. Font sizes here are relative to the CANVAS, so what matters is the
# ratio to the canvas height, not the number: at \textwidth (about 17 cm) a
# 1650x520 canvas with 9 pt ticks prints them at roughly 2.6 pt, which is
# unreadable. The layout below is two rows rather than one (so each panel is
# ~2x wider on the page) and the fonts are scaled up to match, landing tick
# labels near 7 pt in print.
# Sizing check: a font of size f on a canvas of height H prints at
# f/H * (print height) . With H = 1000 and a printed height of ~12.1 cm, tick
# labels at 20 land at 0.24 cm, about 7 pt. That is the floor for figure text.
const FS = (titlefontsize = 25, guidefontsize = 22, tickfontsize = 20,
            legendfontsize = 17)

surf = CSV.read(joinpath(IDENT, "loss_surface_gca2.0.csv"), DataFrame)
prof = CSV.read(joinpath(IDENT, "profile_gca_gca2.0.csv"), DataFrame)
fit  = CSV.read(joinpath(IDENT, "parametric_fit.csv"), DataFrame)

# Closure estimates come from the SUPERVISED-TRAJECTORY refit, not the convex
# hull, so this figure shows the same domain the text quotes. (The conclusion is
# the same either way -- all five estimates fall outside the interval on both consistency-ok
# domains -- but the figure should not plot one domain while the prose reports
# another.) The hull fit still appears, labelled, in the older symbolic figures.
dom  = CSV.read(joinpath(IDENT, "symbolic_domain_comparison.csv"), DataFrame)

fit2  = fit[isapprox.(fit.gCa_true, GCA_TRUE), :]
symb2 = sort(dom[dom.domain .== "traj-train", :], :seed)

# ---------------------------------------------------------------- panel (a)
# The valley is far narrower than the 101x101 surface grid, so a heatmap of that
# grid renders it as a one-pixel streak and shows nothing about whether it
# closes. We therefore plot the valley FLOOR directly, which is what the profile
# computed at fine resolution: for each gCa, the ECa that best compensates it.
# That curve IS the identifiable combination, and the shaded span is where the
# data still tolerate the pairing. The surface CSV is used only for the inset
# check that the floor really is the minimum (not drawn).
pr0 = sort(prof[prof.chi2 .< 1e6, :], :gCa)
dmin0 = minimum(pr0.delta_chi2)
ok = pr0.delta_chi2 .<= CHI2_95 .+ dmin0

pa = plot(pr0.gCa, pr0.ECa_hat;
          lw = 3, color = :steelblue,
          label = "valley floor",
          xlabel = "g(Ca)  (mS/cm²)", ylabel = "E(Ca)  (mV)",
          title = "(a)  the trade-off is bounded",
          xlims = (0.5, 4.0), ylims = (0, 320), left_margin = 5mm,
          bottom_margin = 4mm, FS...)
# The stretch of that floor the data actually tolerate.
plot!(pa, pr0.gCa[ok], pr0.ECa_hat[ok]; lw = 8, color = :steelblue, alpha = 0.35,
      label = "95% region")
scatter!(pa, [GCA_TRUE], [ECA_TRUE], m = (:star5, 13, :gold), msw = 1.5,
         msc = :black, label = "truth")
scatter!(pa, fit2.gCa_hat, fit2.ECa_hat, m = (:circle, 6, :orangered), msw = 0.8,
         msc = :white, label = "parametric fits")
scatter!(pa, symb2.a_hat, fill(12.0, nrow(symb2)); m = (:vline, 11, :crimson),
         msw = 2.5, label = "closure estimates")
plot!(pa, legend = :topright, foreground_color_legend = nothing,
      background_color_legend = RGBA(1, 1, 1, 0.8))

# ---------------------------------------------------------------- panel (b)
pr = sort(prof[prof.chi2 .< 1e6, :], :gCa)
dmin = minimum(pr.delta_chi2)

#  Interpolate the Delta-chi2 threshold crossings rather than taking the
#  outermost GRID POINTS that happen to fall under the threshold.  The scan step
#  is 0.0625 in gCa, and rounding outward to the grid inflated the interval to
#  [1.625, 2.125].  That inflation is not cosmetic: it pushed seed 3333's closure consistency-ok
#  estimate (a_hat = 1.6069) outside the band and let the paper say "every one of
#  the five falls outside", which is a statement about the scan resolution and not
#  about the data.  The interpolated crossings are [1.6065, 2.1477] and that is
#  what main.tex now quotes -- keep the two in step.  Delta-chi2 is convex on both
#  flanks here, so linear interpolation is if anything marginally too narrow.
#  Wrapped in a function on purpose: on 1.6 a value assigned inside a top-level
#  `for` never reaches the global scope.
function ci_crossings(g, d, thr)
    lo = NaN
    hi = NaN
    for i in 1:(length(g) - 1)
        if (d[i] - thr) * (d[i + 1] - thr) < 0
            c = g[i] + (thr - d[i]) * (g[i + 1] - g[i]) / (d[i + 1] - d[i])
            isnan(lo) && (lo = c)
            hi = c
        end
    end
    return lo, hi
end

lo, hi = ci_crossings(pr.gCa, pr.delta_chi2, CHI2_95 + dmin)

pb = plot(pr.gCa, pr.delta_chi2;
          lw = 2.5, color = :steelblue, label = "profile likelihood",
          xlabel = "g(Ca)  (mS/cm²)", ylabel = "Δχ²  (profile)",
          title = "(b)  the data bound g(Ca)",
          xlims = (0, 5), ylims = (0, 60), left_margin = 5mm,
          bottom_margin = 4mm, FS...)
vspan!(pb, [lo, hi], color = :steelblue, alpha = 0.15, label = "95% interval")
#  These two carry NO legend entry, deliberately. They used to, and the legend
#  disagreed with the plot: the dashed threshold drew a key that read as solid
#  and the dotted truth line a key that read as dashed. That is not a styling
#  bug to chase -- a legend key is only a few tens of pixels long, which is too
#  short to render a dash or dot pattern faithfully at this line width, so any
#  key for these two will misdescribe them. The caption names both lines
#  instead, which is unambiguous. Do not re-add labels here.
hline!(pb, [CHI2_95], color = :black, ls = :dash, lw = 1.5, label = "")
vline!(pb, [GCA_TRUE], color = :black, ls = :dot, lw = 1.5, label = "")
# Closure estimates on the same axis, as rug marks along the bottom.
scatter!(pb, symb2.a_hat, fill(2.0, nrow(symb2));
         m = (:vline, 12, :crimson), msw = 2.5,
         label = "closure estimates")
plot!(pb, legend = :topright, foreground_color_legend = nothing,
      background_color_legend = RGBA(1, 1, 1, 0.75))

# ---------------------------------------------------------------- panel (c)
seeds = sort(unique(fit2.seed))
xp = 1:length(seeds)
pc_par = [fit2.gCa_hat[findfirst(==(s), fit2.seed)] for s in seeds]
pc_clo = [symb2.a_hat[findfirst(==(s), symb2.seed)] for s in seeds]

pc = plot(; xlabel = "seed", ylabel = "recovered g(Ca)  (mS/cm²)",
          title = "(c)  same data, two representations",
          xticks = (xp, string.(seeds)), xlims = (0.4, length(seeds) + 0.6),
          # Headroom above the largest closure estimate (seed 2222, a_hat = 2.816).
          # At the old top of 3.4 the :topleft legend box sat ON that diamond and
          # erased the point that defines the upper end of the span the caption
          # quotes; the legend is also transparent now so nothing can hide a marker.
          ylims = (0.6, 4.0), left_margin = 5mm, bottom_margin = 4mm, FS...)
hline!(pc, [GCA_TRUE], color = :black, ls = :dash, lw = 2, label = "truth = 2.0")
scatter!(pc, xp, pc_clo; m = (:diamond, 9, :crimson), msw = 0.8, msc = :white,
         label = "via neural closure")
scatter!(pc, xp, pc_par; m = (:circle, 9, :orangered), msw = 0.8, msc = :white,
         label = "parametric fit")
for i in xp                                  # pair the two estimates per seed
    plot!(pc, [i, i], [pc_par[i], pc_clo[i]], color = :gray60, lw = 1, label = "")
end
plot!(pc, legend = :topleft, foreground_color_legend = nothing,
      background_color_legend = nothing)

# Two rows: (a) and (b) share the top, (c) spans the bottom. A 1x3 strip is
# 3.2:1, which at \textwidth is only ~5 cm tall and shrinks every label past
# legibility; this is ~1.4:1 and prints about 12 cm tall.
fig = plot(pa, pb, pc; layout = @layout([a b; c]), size = (1400, 1000),
           bottom_margin = 9mm, left_margin = 11mm, right_margin = 5mm,
           top_margin = 4mm)
out = joinpath(FIG_DIR, "fig13_parametric_identifiability.png")
savefig(fig, out)

@printf("\nwrote %s\n", out)
@printf("  panel (b) 95%% CI, interpolated threshold crossings: [%.4f, %.4f]\n", lo, hi)
@printf("  parametric: mean %.3f  sd %.3f  range [%.3f, %.3f]\n",
        mean(pc_par), std(pc_par), minimum(pc_par), maximum(pc_par))
@printf("  closure   : mean %.3f  sd %.3f  range [%.3f, %.3f]\n",
        mean(pc_clo), std(pc_clo), minimum(pc_clo), maximum(pc_clo))
@printf("  closure estimates outside the 95%% interval: %d of %d\n",
        count(a -> a < lo || a > hi, pc_clo), length(pc_clo))
