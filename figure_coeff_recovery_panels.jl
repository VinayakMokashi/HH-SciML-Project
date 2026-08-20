# =============================================================================
#  figure_coeff_recovery_panels.jl
#     -> figures/fig11_coeff_recovery_before.png   (Fig 6b in the paper)
#     -> figures/fig11_coeff_recovery_after.png    (Fig 8b, appendix)
# =============================================================================
#  Two problems with the panels these replace:
#
#  1. They were BYTE-DISTINGUISHABLE but VISUALLY IDENTICAL. Both carried the
#     same in-figure title, "Recovered calcium parameters vs truth (gCa=2.0,
#     5 seeds)", so a reader flipping between Fig 6b and Fig 8b had no way to
#     tell which was the baseline and which was the aggressive retrain -- the
#     one comparison those two panels exist to support. Each now names its
#     training budget and its fitting domain in its own supertitle.
#
#  2. Their fonts were never bumped in the legibility pass, and they print at
#     roughly half a text width, so a 1500 px canvas is squeezed into ~3.4 in.
#     Sizes here are set for that reduction, not for the canvas.
#
#  Also: both figures now share y-limits, computed across BOTH runs. The paper
#  asks the reader to compare them directly ("worse and noisier than before the
#  retrain"); on independently scaled axes that comparison is not visual.
#
#  PLOTTING ONLY -- nothing is refit. The conductance-form coefficients are read
#  from the metrics CSVs the two objective-3 runs already wrote. The ensemble
#  reversal potential is -mean(b)/mean(a): fitting s^2(aV+b) to the ensemble-mean
#  network output is a linear least-squares problem, so the fit of the mean IS
#  the mean of the fits (this identity is what the original run printed as
#  "ensemble", and it reproduces 162.5 / 171.3 mV exactly).
#
#  Run:  julia --project=. figure_coeff_recovery_panels.jl
# =============================================================================

const ROOT = @__DIR__

using CSV, DataFrames, Statistics, Printf
using Plots, Measures
gr()

const BEFORE_CSV = joinpath(ROOT, "results", "symbolic", "symbolic_recovery_metrics.csv")
const AFTER_CSV  = joinpath(ROOT, "results", "retrain_gca2_20k", "symbolic",
                            "symbolic_recovery_metrics.csv")
const FIG_DIR    = joinpath(ROOT, "figures")
const PAPER_DIR  = joinpath(ROOT, "paper", "figures")
mkpath(FIG_DIR)

const A_TRUE, B_TRUE, EREV_TRUE = 2.0, -240.0, 120.0

# Fonts sized for the print reduction, not the canvas (see header note 2).
#
# The arithmetic that governs this: a font of size f on a canvas W px wide,
# placed at a fraction p of a 6.5 in text width, prints at f * p * 6.5 * 72 / W
# pt. The old pairing (f = 17, W = 1500, p ~ 0.54) gives 2.9 pt against 10 pt
# body text -- the "sized for the reduction" note above was written before that
# was measured, and it was not nearly enough. Both figures are now placed at FULL
# text width, and W = 1950 puts them at 300 DPI there, so f = 28 prints at 6.7 pt.
# Margins are scaled with the fonts: raising one without the other clips the
# y-axis labels, which has bitten this project before.
const CANVAS_W = 1950
const FS = (titlefontsize = 30, guidefontsize = 29, tickfontsize = 28)

"Per-seed mean/SD of the conductance-form coefficients at the main setting."
function coeffs(csv)
    d = CSV.read(csv, DataFrame)
    d = d[isapprox.(Float64.(d.gCa), A_TRUE), :]          # drop the gCa=0.4 control row
    a, b = Float64.(d.a_hat), Float64.(d.b_hat)
    return (; a_m = mean(a), a_s = std(a), b_m = mean(b), b_s = std(b),
              erev = -mean(b) / mean(a), n = nrow(d))
end

bef, aft = coeffs(BEFORE_CSV), coeffs(AFTER_CSV)
bef.n == aft.n || error("seed counts differ: $(bef.n) vs $(aft.n)")

# Shared limits so the two figures can be compared by eye.
const A_TOP    = max(A_TRUE, bef.a_m + bef.a_s, aft.a_m + aft.a_s) * 1.18
const B_BOT    = min(B_TRUE, bef.b_m - bef.b_s, aft.b_m - aft.b_s) * 1.15
const EREV_TOP = max(EREV_TRUE, bef.erev, aft.erev) * 1.18

function panel_set(c, supertitle, outfile)
    common = (; legend = false, bar_width = 0.6, left_margin = 27mm,
                bottom_margin = 13mm, top_margin = 5mm, right_margin = 12mm, FS...)

    # Panel titles are kept to the symbol alone. At these font sizes the old
    # parenthetical ("per-seed mean±std") ran into the neighbouring panel's
    # title; what the bars and whiskers are is stated once in the caption.
    p1 = bar(["true", "recovered"], [A_TRUE, c.a_m]; yerror = [0.0, c.a_s],
             color = [:gray, :seagreen], ylims = (0, A_TOP),
             title = "a = gCa", ylabel = "conductance", common...)

    p2 = bar(["true", "recovered"], [B_TRUE, c.b_m]; yerror = [0.0, c.b_s],
             color = [:gray, :seagreen], ylims = (B_BOT, 15),
             title = "b = -gCa*ECa", ylabel = "coefficient", common...)

    p3 = bar(["true", "recovered"], [EREV_TRUE, c.erev];
             color = [:gray, :steelblue], ylims = (0, EREV_TOP),
             title = "Erev = -b/a",
             ylabel = "reversal potential (mV)", common...)

    # plot_titlevspan must be widened by hand: the default band is sized for a
    # one-line supertitle and a two-line one lands on the subplot titles.
    fig = plot(p1, p2, p3; layout = (1, 3), size = (CANVAS_W, 900),
               plot_title = supertitle, plot_titlefontsize = 32,
               plot_titlevspan = 0.17)
    out = joinpath(FIG_DIR, outfile)
    savefig(fig, out)
    cp(out, joinpath(PAPER_DIR, outfile); force = true)   # stage for the manuscript
    return out
end

# The optimiser is BFGS, not L-BFGS: src/experiment.jl calls
# OptimizationOptimJL.BFGS(initial_stepnorm = 0.01), and `grep -rn LBFGS
# --include=*.jl .` returns nothing. These two supertitles said "L-BFGS" while
# the manuscript was corrected around them, which is exactly how a figure ends
# up contradicting its own paper. Do not put it back.
o1 = panel_set(bef,
    "Recovered calcium parameters vs truth — hull domain, gCa=2.0, $(bef.n) seeds\n" *
    "baseline training (Adam 5000 / BFGS 300)",
    "fig11_coeff_recovery_before.png")

o2 = panel_set(aft,
    "Recovered calcium parameters vs truth — hull domain, gCa=2.0, $(aft.n) seeds\n" *
    "aggressive retrain (Adam 20000 / BFGS 1000)",
    "fig11_coeff_recovery_after.png")

@printf("\nwrote %s\n      %s\n", o1, o2)
@printf("  baseline : a = %.3f +/- %.3f   b = %.1f +/- %.1f   Erev = %.1f mV\n",
        bef.a_m, bef.a_s, bef.b_m, bef.b_s, bef.erev)
@printf("  retrain  : a = %.3f +/- %.3f   b = %.1f +/- %.1f   Erev = %.1f mV\n",
        aft.a_m, aft.a_s, aft.b_m, aft.b_s, aft.erev)
@printf("  shared limits: a (0, %.2f)  b (%.1f, 15)  Erev (0, %.1f)\n",
        A_TOP, B_BOT, EREV_TOP)
println("  paper macros to match: \\valSymbolicAHatMeanStd = 1.60 +/- 0.90 , " *
        "\\valRetrainAHatMeanStd = 1.49 +/- 1.48")
