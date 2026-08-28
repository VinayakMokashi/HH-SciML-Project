# =============================================================================
#  regen_fig3_fig6.jl  ->  figures/fig3_ude_*.png, figures/fig6_voltage_only_*.png
# =============================================================================
#  Companion to regen_fig2.jl, and the CHEAP half of decision D1.
#
#  WHY THIS IS SAFE, and why it is not a training run.
#  regenerate_ude_figs (src/experiment.jl:313-326) LOADS the saved parameter
#  snapshot (results/params/ude_<tag>.jld) and does a forward solve. There is no
#  optimiser, no RNG draw that affects the result, and no fit. Given the same
#  .jld it is deterministic, so the curves are identical to the published ones;
#  what changes is the in-image TITLE of the stacked overview, which the code now
#  emits as "state propagation" (src/experiment.jl:224) while the committed PNGs
#  still read "state reconstruction" -- decision D1.
#
#  WHAT IT WRITES, all of it under figures/ and results/calcium/:
#    figures/<prefix>_{voltage,m,h,n,p,s}.png   per-variable panels
#    figures/<prefix>_overview.png              the stacked 3-panel composite
#                                               (THE ONE D1 IS ABOUT)
#    figures/<prefix>_calcium_parity.png
#    results/calcium/probe_<tag>_seed<seed>.csv
#    results/calcium/grid_<tag>_seed<seed>.csv
#
#  NO RESULTS CSV THAT FEEDS A REPORTED NUMBER IS TOUCHED. The two calcium files
#  it rewrites are inputs to the symbolic stage, not sources for
#  paper/metrics_map.yaml -- checked against the map's file list, which names
#  only metrics_*.csv, ablation_*.csv, identifiability/*, symbolic/*,
#  gca_sweep_5seed/* and node_parity/*. Re-run extract_metrics.py --check after
#  this anyway; that is what proves it.
#
#  NOTE the per-variable panels have ALWAYS been titled
#  "<stem> : truth vs <model>" (src/experiment.jl:213-221) and never carried the
#  "state reconstruction" wording. fig3_ude_voltage.png is used by the 5-page
#  workshop paper, so if this run changes it, compare the two before accepting.
#
#  Baseline constants below are B_GCA/B_NOISE/B_TWIN/B_SEED from
#  experiments_runner.jl:49,57 and the call is the REPLOT-mode call at
#  experiments_runner.jl:371-374, reproduced so a hang costs these figures only.
#
#  Run:  julia --project=. regen_fig3_fig6.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

const B_GCA, B_NOISE, B_TWIN, B_SEED = 2.0, 0.02, 30.0, 1111

println("Regenerating fig3 (full-state UDE) from saved params -- no training")
regenerate_ude_figs("ude_full", "fig3_ude";
                    gCa = B_GCA, noise_level = B_NOISE,
                    t_train_end = B_TWIN, seed = B_SEED)
println("  wrote figures/fig3_ude_overview.png and its panels")

println("Regenerating fig6 (voltage-only UDE) from saved params -- no training")
regenerate_ude_figs("voltage_only", "fig6_voltage_only";
                    gCa = B_GCA, noise_level = B_NOISE,
                    t_train_end = B_TWIN, seed = B_SEED)
println("  wrote figures/fig6_voltage_only_overview.png and its panels")

println("done.")
