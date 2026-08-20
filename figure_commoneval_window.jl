# =============================================================================
#  figure_commoneval_window.jl  --  PLOTTING ONLY, refits nothing.
# =============================================================================
#  Rebuilds figures/fig7b_commoneval_ablation_window.png (the paper's Fig. 8a).
#
#  WHY IT IS NOT BUILT BY experiments_runner.jl ANY MORE.
#  Two independent reasons, and both are why this file exists:
#
#  1. CENSORING.  The runner's ablation_fig() reads results/ablation_window.csv,
#     whose common_eval_rollout_horizon_ms column says 70.0 for all five windows.
#     That is the cap constant, not a measurement: the common-eval window starts
#     at 50.098 ms and the trace ends at 100 ms, so only 49.902 ms exists to be
#     measured.  src/metrics.jl now clamps the horizon to the data actually
#     available, and recover_rollout_censoring.jl re-measured all five windows
#     from the saved parameters (no retraining).  This script reads THAT file.
#     Its self-test compared 150 other metrics against ablation_window.csv and
#     found a worst relative disagreement of exactly 0, so the only thing that
#     differs between the two sources is the metric we deliberately fixed.
#
#  2. LEGIBILITY.  A font of size f on a canvas W px wide prints at
#     f * (placement fraction) * 6.5in * 72 / W pt.  The panel used to sit in a
#     0.49\textwidth subfigure at W = 960, so the runner's ~13 pt defaults printed
#     at about 3 pt against 10 pt body text.  Half width cannot be rescued by
#     fonts alone: three stacked panels there need f ~ 30, and at that size the
#     titles run off the canvas and the y-tick labels collide (the same trap the
#     project hit once before -- font size and margin have to move together).
#     So the figure is now placed at FULL \textwidth and sized for it: W = 1950
#     gives 300 DPI across 6.5 in, and 30 pt ticks print at ~7.2 pt.
#     If you re-place it narrower, rescale the fonts by the same factor.
#
#  Run:  julia --project=. figure_commoneval_window.jl
# =============================================================================

const ROOT = @__DIR__
using CSV, DataFrames, Plots, Measures, Printf

const IDENT   = joinpath(ROOT, "results", "identifiability")
const FIG_DIR = joinpath(ROOT, "figures")
const SRC     = joinpath(IDENT, "rollout_censoring.csv")
const OUT     = joinpath(FIG_DIR, "fig7b_commoneval_ablation_window.png")

const COMMON_EVAL_START = 50.0

# Printed-size budget for a FULL \textwidth placement on a 1950 px canvas:
# pt_printed = f * 6.5 * 72 / 1950 = f * 0.24.  Ticks at 30 -> 7.2 pt, and
# 1950 px across 6.5 in is 300 DPI.
const CANVAS_W = 1950
const PLACEMENT = 1.0                     # fraction of \textwidth in main.tex
const FS = (titlefontsize = 34, guidefontsize = 32, tickfontsize = 30,
            legendfontsize = 26)

isfile(SRC) || error("missing $SRC -- run recover_rollout_censoring.jl first")
df = CSV.read(SRC, DataFrame)

series(metric; window = "common_eval") = begin
    d = df[(df.window .== window) .& (df.metric .== metric), :]
    sort!(d, :t_train_end)
    (Float64.(d.t_train_end), Float64.(d.value))
end

xv, vr = series("V_rmse")
_,  gr = series("gate_rmse_mean")
_,  rh = series("rollout_horizon_ms")

# Every common-eval horizon is censored at the same bound (the window is fixed at
# t > 50 ms regardless of how long training ran), so name that bound in the title
# rather than the 70 ms cap, which this window can never reach.
censor = maximum(rh)

# Titles stay short: the evaluation window is stated once in the caption, so
# repeating "common-eval, t>50 ms" in all three overflows the panel at these
# font sizes without adding anything.
common = (; xlabel = "training-window length (ms)", legend = false,
            marker = :circle, ms = 9, lw = 3.5,
            left_margin = 26mm, bottom_margin = 11mm,
            right_margin = 10mm, top_margin = 4mm,
            xticks = Int.(xv), FS...)

p1 = plot(xv, vr; ylabel = "V RMSE (mV)", title = "Voltage error",
          color = :dodgerblue, common...)
p2 = plot(xv, gr; ylabel = "gate RMSE", title = "Gating-variable error",
          color = :seagreen, yticks = 0:0.002:0.008, common...)
p3 = plot(xv, rh; ylabel = "rollout horizon (ms)",
          title = @sprintf("Forecast validity (censored at %.1f ms)", censor),
          color = :purple, ylims = (0, censor * 1.45), yticks = 0:25:75, common...)

savefig(plot(p1, p2, p3; layout = (3, 1), size = (CANVAS_W, 1500)), OUT)

@printf("\nwrote %s\n", OUT)
@printf("  source            : %s\n", SRC)
@printf("  horizon, all five : %s ms\n", join(map(x -> @sprintf("%.3f", x), rh), ", "))
@printf("  censoring bound   : %.3f ms  (was plotted as the 70.0 ms cap)\n", censor)
@printf("  V RMSE            : %s\n", join(map(x -> @sprintf("%.3f", x), vr), ", "))
@printf("  ticks print at    : %.1f pt at %.2f x textwidth (%.0f DPI)\n",
        FS.tickfontsize * PLACEMENT * 6.5 * 72 / CANVAS_W,
        PLACEMENT, CANVAS_W / (PLACEMENT * 6.5))
