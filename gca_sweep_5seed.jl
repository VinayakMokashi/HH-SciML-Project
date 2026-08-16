# =============================================================================
#  gca_sweep_5seed.jl
# =============================================================================
#  Mentor request (Prathamesh, 2026-08), point 5: "The conductance sweep should
#  also be repeated across all five seeds before it is presented as the
#  quantitative identifiability boundary."
#
#  The published sweep is single-seed at 1111 for gCa in {0.4, 1.0, 4.0} and
#  five-seed only at the headline gCa=2.0.  This script fills in the missing
#  cells: seeds {2222,3333,4444,5555} x gCa in {0.4,1.0,4.0} = 12 trainings.
#  Nothing already on disk is recomputed or overwritten.
#
#  ISOLATION: metric rows go to results/gca_sweep_5seed/metrics_gca_sweep.csv.
#  They are deliberately NOT appended to results/metrics_all.csv, because the
#  paper's \val macros are extracted from that file and adding seeds would
#  silently change published single-seed numbers.  Parameter snapshots and
#  calcium probes DO land in the canonical results/params and results/calcium,
#  but only under new seed-suffixed filenames (purely additive).
#
#  Run:  julia --project=. gca_sweep_5seed.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV

const OUT_DIR = joinpath(ROOT, "results", "gca_sweep_5seed")
mkpath(OUT_DIR)
const SWEEP_CSV = joinpath(OUT_DIR, "metrics_gca_sweep.csv")
const RUNLOG    = joinpath(OUT_DIR, "run_log.csv")

const SMOKE = get(ENV, "HH_SMOKE", "0") == "1"

# Budgets identical to the published runs (experiments_runner.jl lines 30-31).
const UDE_ADAM, UDE_BFGS = SMOKE ? (60, 5) : (5000, 300)

# Baseline protocol, unchanged.
const B_NOISE, B_TWIN = 0.02, 30.0

# The missing cells only: seed 1111 already exists for these gCa values, and
# gCa=2.0 already has all five seeds (the ude_full baseline runs).
const GCA_VALUES = SMOKE ? [0.4] : [0.4, 1.0, 4.0]
const NEW_SEEDS  = SMOKE ? [2222] : [2222, 3333, 4444, 5555]

function append_rows!(rows, path)
    isempty(rows) && return
    df = DataFrame(rows)
    CSV.write(path, df; append = isfile(path), writeheader = !isfile(path))
end

println("\n########## gCa SWEEP — FILLING IN SEEDS 2222..5555 ##########")
println("  $(length(GCA_VALUES)) gCa values x $(length(NEW_SEEDS)) seeds = ",
        length(GCA_VALUES) * length(NEW_SEEDS), " trainings")

log_rows = NamedTuple[]
for g in GCA_VALUES, sd in NEW_SEEDS
    label = "gCa=$g seed=$sd"
    println("\n----- $label -----")
    try
        r = run_experiment(; gCa = g, noise_level = B_NOISE, t_train_end = B_TWIN,
                             observed = :full, seed = sd,
                             adam_iters = UDE_ADAM, bfgs_iters = UDE_BFGS,
                             make_figs = false,
                             tag = "abl_gca_$(g)_seed$(sd)")
        append_rows!(r.metrics, SWEEP_CSV)
        # final_loss is captured here so this sweep can report training loss
        # alongside recovery quality (the baseline runs never recorded it).
        push!(log_rows, (; gCa = g, seed = sd, final_loss = r.final_loss,
                           bfgs_ok = r.bfgs_ok, status = "ok"))
        println("  [ok] $label  final_loss=$(r.final_loss)  bfgs_ok=$(r.bfgs_ok)")
    catch err
        @warn "RUN FAILED: $label — continuing." exception = (err, catch_backtrace())
        push!(log_rows, (; gCa = g, seed = sd, final_loss = NaN,
                           bfgs_ok = false, status = "failed"))
    end
    CSV.write(RUNLOG, DataFrame(log_rows))
end

println("\nDONE. Metrics -> $SWEEP_CSV")
