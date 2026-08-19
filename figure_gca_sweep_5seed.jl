# =============================================================================
#  figure_gca_sweep_5seed.jl  ->  figures/fig7c_ablation_gca_5seed.png
# =============================================================================
#  The conductance sweep is the quantitative backbone of the identifiability
#  argument, and since 2026-08 it is run over all five seeds at every point. The
#  figure the paper cited was still the ORIGINAL single-seed panel, whose caption
#  had to apologise for itself ("each point here is a single seed with no error
#  bar, and the 5-seed version in the text supersedes this panel"). A figure that
#  contradicts the sentence pointing at it is worse than no figure.
#
#  Three panels, chosen to carry the MECHANISM rather than to enumerate metrics:
#    (a) forecast voltage error -- flat. Predictive accuracy on the observed
#        channel is unaffected by how much calcium there is to recover.
#    (b) RAW calcium error -- also flat, and this is the point. The closure's
#        absolute error barely moves across the sweep.
#    (c) NORMALISED calcium error -- falls eightfold, because the denominator (the
#        true current's own variation) is the only thing that grew.
#  Read together, (b) and (c) say the sweep is not making the closure better; it
#  is making the target bigger. The single-seed panel could not show this.
#
#  Note the gate-RMSE panel of the old figure is dropped: the sweep summary does
#  not carry that metric (scripts/summarize_gca_sweep.py emits ICa_rmse,
#  ICa_rmse_norm, V_rmse and rollout only), and the raw/normalised pair earns the
#  space better.
#
#  NOTHING is retrained. Plotting only.
#  Run:  julia --project=. figure_gca_sweep_5seed.jl
# =============================================================================

const ROOT = @__DIR__

using CSV, DataFrames, Statistics, Printf
using Plots, Measures
gr()

const SWEEP   = joinpath(ROOT, "results", "gca_sweep_5seed", "gca_sweep_multiseed.csv")
const FIG_DIR = joinpath(ROOT, "figures")
mkpath(FIG_DIR)

# Fonts are relative to the canvas; this prints at ~0.72\textwidth, so keep them
# generous (see the sizing note in figure_identifiability.jl).
const FS = (titlefontsize = 16, guidefontsize = 15, tickfontsize = 13,
            legendfontsize = 12)

df = CSV.read(SWEEP, DataFrame)

function series(metric)
    d = sort(df[df.metric .== metric, :], :gCa)
    isempty(d) && error("metric '$metric' is not in $SWEEP")
    return Float64.(d.gCa), Float64.(d.mean), Float64.(d.sd)
end

xg, vmean, vsd = series("V_rmse")
_,  rmean, rsd = series("ICa_rmse")
_,  nmean, nsd = series("ICa_rmse_norm")

# Categorical x so the four settings are evenly spaced rather than crowding at
# the low end; xg supplies the labels.
xi = collect(1.0:length(xg))
common = (; xlabel = "g(Ca)  (mS/cm²)", legend = false, marker = :circle,
            markersize = 6, lw = 2, xticks = (xi, string.(xg)),
            xlims = (0.6, length(xg) + 0.4), left_margin = 17mm,
            bottom_margin = 6mm, FS...)

p1 = plot(xi, vmean; yerror = vsd, color = :dodgerblue,
          ylabel = "V RMSE (mV)",
          title = "(a)  forecast voltage error: flat across the sweep", common...)

p2 = plot(xi, rmean; yerror = rsd, color = :seagreen,
          ylabel = "I(Ca) RMSE\n(μA/cm²)",
          title = "(b)  raw calcium error: also flat", common...)

p3 = plot(xi, nmean; yerror = nsd, color = :darkorange,
          ylabel = "I(Ca) RMSE / std\n(normalised)",
          title = "(c)  normalised calcium error: falls eightfold", common...)
# An explicit two-point segment rather than hline!, which trips GR on a subplot
# that already carries y-error bars.
plot!(p3, [0.6, length(xg) + 0.4], [1.0, 1.0]; color = :black, ls = :dash,
      lw = 1.5, label = "", marker = :none)

fig = plot(p1, p2, p3; layout = (3, 1), size = (960, 950), top_margin = 4mm)
out = joinpath(FIG_DIR, "fig7c_ablation_gca_5seed.png")
savefig(fig, out)

@printf("\nwrote %s\n", out)
println("  normalised calcium error (mean +/- sd, n = 5 at every point):")
for i in eachindex(xg)
    @printf("    gCa=%.1f : %.3f +/- %.3f\n", xg[i], nmean[i], nsd[i])
end
println("\n  adjacent-step separation (|gap| / pooled sd):")
for i in 1:length(xg)-1
    pooled = sqrt((nsd[i]^2 + nsd[i+1]^2) / 2)
    gap = abs(nmean[i] - nmean[i+1])
    @printf("    %.1f -> %.1f : %.2f  %s\n", xg[i], xg[i+1], gap / pooled,
            gap > 2 * pooled ? "SEPARATED" : "within noise")
end
@printf("\n  raw ICa error spans %.2f-%.2f with SDs %.2f-%.2f (intervals overlap)\n",
        minimum(rmean), maximum(rmean), minimum(rsd), maximum(rsd))
