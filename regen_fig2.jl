# =============================================================================
#  regen_fig2.jl  ->  figures/fig2_neural_ode_overview.png
# =============================================================================
#  fig2 is the only figure the paper includes that HH_REPLOT=1 does not reliably
#  refresh: it is produced by run_node_baseline, which is the LAST step of the
#  replot pipeline and is the documented hang risk (HANDOFF sec 9). In the
#  2026-08 readability pass the replot wrote every other summary figure and then
#  hung there, leaving fig2 with the old, smaller fonts while its neighbours had
#  the new ones.
#
#  This runs that one step on its own, so a hang costs one figure and not a whole
#  pipeline, and so it can be retried without redoing anything else.
#
#  It reproduces the PUBLISHED configuration exactly -- Adam 3000 / BFGS 300 with
#  the raw time input -- because that is what the figure is captioned as showing
#  (the neural ODE as originally configured, whose failure mode the paper
#  discusses before replacing it with the repaired autonomous baseline). Do NOT
#  "improve" it to the parity architecture: the panel would then no longer match
#  its caption, and the repaired baseline is reported in Table 1 instead.
#
#  The run is deterministic in the seed, so the curves are identical to the
#  published ones; only the font sizes change. No CSV is written.
#
#  Run:  julia --project=. regen_fig2.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

const B_GCA, B_NOISE, B_TWIN, REP_SEED = 2.0, 0.02, 30.0, 1111
const NODE_ADAM, NODE_BFGS = 3000, 300      # experiments_runner.jl:43, published

println("Regenerating fig2 (published NODE config: Adam $NODE_ADAM / BFGS $NODE_BFGS, +time input)")
r = run_node_baseline(; gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN,
                        seed = REP_SEED, adam_iters = NODE_ADAM, bfgs_iters = NODE_BFGS,
                        make_figs = true, prefix = "fig2_neural_ode")
println("done. final_loss = ", r.final_loss, "  bfgs_ok = ", r.bfgs_ok)
println("wrote figures/fig2_neural_ode_overview.png")
