# =============================================================================
#  node_parity.jl
# =============================================================================
#  Mentor request (Prathamesh, 2026-08), point 5: "The neural ODE baseline should
#  receive a comparable optimisation budget and a better-justified architecture.
#  The current raw-time input and smaller Adam budget make the general
#  'impossible versus routine' comparison difficult to defend."
#
#  Two objections are bundled there, so this script separates them into two
#  variants, both trained at the UDE's OWN budget (Adam 5000 / BFGS 300 instead
#  of 3000 / 300), over the same five seeds:
#
#    "autonomous" — the defensible architecture.  Inputs are the six normalised
#                   states ONLY.  The true system is autonomous (a constant
#                   I_app drives it), so a right-hand side that reads the clock
#                   is strictly more expressive than the physics requires and
#                   can memorise the training window by time index rather than
#                   learning a vector field.  This is the honest baseline.
#
#    "timeinput"  — the published architecture (six states + raw t), retrained
#                   at the parity budget.  Holding the architecture fixed and
#                   changing only the budget isolates how much of the published
#                   NODE failure was the smaller Adam allocation.
#
#  Together the two variants answer "was it the budget or the architecture?"
#  rather than confounding them.  Everything else (width, depth, LayerNorm,
#  normalised coordinates, solver, tolerances, adjoint, loss, data, seeds) is
#  identical to run_node_baseline.
#
#  ISOLATION: everything lands under results/node_parity/.  Nothing in the
#  canonical results/ or figures/ trees is read-modified-written, and no rows are
#  appended to results/metrics_all.csv (the paper's \val macros come from there).
#
#  Run:  julia --project=. node_parity.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV

const OUT_DIR = joinpath(ROOT, "results", "node_parity")
mkpath(OUT_DIR)
const PARITY_CSV = joinpath(OUT_DIR, "metrics_node_parity.csv")
# The run log is per-process (named after the variant selection) so two
# concurrent variant-restricted processes never clobber each other's log.  The
# metrics CSV is append-only and safe to share.
const RUNLOG = joinpath(OUT_DIR,
    "run_log_" * replace(get(ENV, "NODE_VARIANTS", "all"), "," => "-") * ".csv")

const SMOKE = get(ENV, "HH_SMOKE", "0") == "1"

# Parity budget = the UDE's budget (experiments_runner.jl line 30), not the
# NODE's published 3000/300.
const ADAM_PARITY, BFGS_PARITY = SMOKE ? (40, 3) : (5000, 300)

const B_GCA, B_NOISE, B_TWIN = 2.0, 0.02, 30.0
const SEEDS = SMOKE ? [1111] :
    haskey(ENV, "NODE_SEEDS") ? parse.(Int, split(ENV["NODE_SEEDS"], ",")) :
    [1111, 2222, 3333, 4444, 5555]

# A NODE training at the parity budget costs roughly ten times a UDE training, so
# the two variants are split across processes rather than run back to back:
#   NODE_VARIANTS=autonomous julia --project=. node_parity.jl
#   NODE_VARIANTS=timeinput  julia --project=. node_parity.jl
# Runs are deterministic in the seed, so a variant repeated by accident produces
# identical rows and the analysis dedupes by (model, seed, window, metric).
const VARIANTS = let v = get(ENV, "NODE_VARIANTS", "autonomous,timeinput")
    sel = split(v, ",")
    [x for x in (false, true) if (x ? "timeinput" : "autonomous") in sel]
end

# -----------------------------------------------------------------------------
#  One NODE training.  `use_time` selects the variant; everything else matches
#  run_node_baseline exactly (src/experiment.jl:438-477).
# -----------------------------------------------------------------------------
function run_node_variant(; seed, use_time::Bool, adam_iters, bfgs_iters,
                            gCa = B_GCA, noise_level = B_NOISE, t_train_end = B_TWIN)
    data_clean = gen_clean_data(gCa).data_clean
    data_noisy = gen_noisy_data(data_clean, noise_level; seed = seed)
    split      = make_split(t_train_end)
    norm_noisy = data_noisy ./ SCALE
    u0n        = steady_state_u0() ./ SCALE

    nin = use_time ? 7 : 6
    nn  = Lux.Chain(Lux.Dense(nin, 64, tanh), Lux.LayerNorm((64,)),
                    Lux.Dense(64, 64, tanh), Lux.LayerNorm((64,)), Lux.Dense(64, 6))
    p0, stn = Lux.setup(StableRNG(seed), nn)
    p0      = ComponentArray{Float64}(p0)

    # Lux 0.5.14 LayerNorm needs a matrix input — reshape to a column, vec the output.
    rhs = if use_time
        function (du, u, p, t)
            du .= vec(nn(reshape(vcat(u, t), :, 1), p, stn)[1]); return nothing
        end
    else
        function (du, u, p, _t)
            du .= vec(nn(reshape(u, :, 1), p, stn)[1]); return nothing
        end
    end

    prob = ODEProblem(rhs, u0n, split.tspan_train, p0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))
    ntrain = length(split.train_idx)
    loss_fn(p) = (pred = predict(p); size(pred, 2) == ntrain ?
                  sum(abs2, norm_noisy[:, split.train_idx] .- pred) : 1.0e6)

    label = use_time ? "NODE-t" : "NODE-auto"
    tr = train_two_stage(loss_fn, p0; adam_lr = 1e-2, adam_iters = adam_iters,
                         bfgs_iters = bfgs_iters, label = label)

    pred_full = solve_aligned(rhs, u0n, tr.p) .* SCALE   # de-normalise

    # model name carries the variant so the two are distinguishable in the tidy CSV.
    metrics = compute_metrics(; model = use_time ? "NODE_time_parity" : "NODE_auto_parity",
                                observed = "full", gCa = gCa, noise_level = noise_level,
                                t_train_end = t_train_end, seed = seed,
                                t = TSTEPS, truth = data_clean, pred = pred_full,
                                train_idx = split.train_idx, forecast_idx = split.forecast_idx,
                                truth_noisy = data_noisy)

    nparam = length(p0)
    return (; metrics, final_loss = tr.final_loss, bfgs_ok = tr.bfgs_ok, nparam)
end

function append_rows!(rows, path)
    isempty(rows) && return
    df = DataFrame(rows)
    CSV.write(path, df; append = isfile(path), writeheader = !isfile(path))
end

println("\n########## NODE PARITY RUNS (Adam $ADAM_PARITY / BFGS $BFGS_PARITY) ##########")

log_rows = NamedTuple[]
# Autonomous variant FIRST: it is the primary answer to the mentor's objection,
# so a partial run still delivers the result that matters.
for use_time in VARIANTS, sd in SEEDS
    variant = use_time ? "timeinput" : "autonomous"
    println("\n----- NODE variant=$variant seed=$sd -----")
    try
        r = run_node_variant(; seed = sd, use_time = use_time,
                               adam_iters = ADAM_PARITY, bfgs_iters = BFGS_PARITY)
        append_rows!(r.metrics, PARITY_CSV)
        push!(log_rows, (; variant, seed = sd, adam_iters = ADAM_PARITY,
                           bfgs_iters = BFGS_PARITY, nparam = r.nparam,
                           final_loss = r.final_loss, bfgs_ok = r.bfgs_ok, status = "ok"))
        println("  [ok] $variant seed=$sd  final_loss=$(r.final_loss)")
    catch err
        @warn "RUN FAILED: NODE $variant seed=$sd — continuing." exception = (err, catch_backtrace())
        push!(log_rows, (; variant, seed = sd, adam_iters = ADAM_PARITY,
                           bfgs_iters = BFGS_PARITY, nparam = -1,
                           final_loss = NaN, bfgs_ok = false, status = "failed"))
    end
    CSV.write(RUNLOG, DataFrame(log_rows))
end

println("\nDONE. Metrics -> $PARITY_CSV")
