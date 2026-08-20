# =============================================================================
#  recover_training_losses.jl
# =============================================================================
#  Mentor request (Prathamesh, 2026-08), point 1, final sentence: "The original
#  and retrained runs should also report directly comparable training losses."
#
#  Table 2 of the draft currently says "not recorded" for the before-retrain
#  training loss, because run_experiment returned final_loss but the sweep runner
#  only persisted the tidy metric rows, which have no loss column.  The trained
#  parameters were saved, though, so the loss does not need a retrain to recover:
#  we rebuild the EXACT training objective and evaluate it at the saved weights.
#
#  Both sides are evaluated with the same construction the trainer used --
#  make_ude_loss(:full, ...) over the same noisy data, same training indices,
#  same solver and tolerances (src/experiment.jl:157-172, mirrored by
#  retrain_gca2_20k.jl:88-92) -- so before and after are directly comparable.
#
#  As a self-check the script also recomputes the AFTER loss and compares it with
#  the value retrain_gca2_20k.jl recorded at the time.  Those two should agree to
#  solver tolerance; if they do not, the recomputation is not trustworthy and the
#  discrepancy is reported rather than hidden.
#
#  No training happens here.  Ten forward solves.
#
#  Run:  julia --project=. recover_training_losses.jl
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using DataFrames, CSV, Statistics, Printf
import JLD

const OUT_DIR = joinpath(ROOT, "results", "identifiability")
mkpath(OUT_DIR)
const RETRAIN_PARAMS = joinpath(ROOT, "results", "retrain_gca2_20k", "params")
const RETRAIN_METRICS = joinpath(ROOT, "results", "retrain_gca2_20k", "metrics_retrain.csv")

const G_CA, NOISE_LEVEL, T_TRAIN_END = 2.0, 0.02, 30.0
const SEEDS = [1111, 2222, 3333, 4444, 5555]
const REP_SEED = 1111

# Rebuild the exact training objective for one seed and return a closure that
# scores any parameter vector.
function loss_for_seed(seed)
    data_clean = gen_clean_data(G_CA).data_clean
    data_noisy = gen_noisy_data(data_clean, NOISE_LEVEL; seed = seed)
    split      = make_split(T_TRAIN_END)
    u0         = steady_state_u0()

    nn_ca, p_template, st_ca = make_ca_network(seed)
    rhs  = make_hh_ude(nn_ca, st_ca)
    prob = ODEProblem(rhs, u0, split.tspan_train, p_template)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false))
    loss_fn = make_ude_loss(:full, predict, data_noisy, split.train_idx)
    return (; loss_fn, p_template)
end

# Load a saved flat parameter vector into the ComponentArray template.
function load_into(p_template, path)
    isfile(path) || return nothing
    flat = JLD.load(path, "p_ca")
    p = copy(p_template)
    p .= flat
    return p
end

recorded = Dict{Int,Float64}()
if isfile(RETRAIN_METRICS)
    for r in CSV.File(RETRAIN_METRICS)
        recorded[Int(r.seed)] = Float64(r.final_loss)
    end
end

println("\n=== Recovering full-state training losses from saved parameters ===")
println("(objective: unweighted sum of squares over 6 states x 154 training samples)\n")

rows = NamedTuple[]
for seed in SEEDS
    ctx = loss_for_seed(seed)

    tag = seed == REP_SEED ? "ude_full" : "ude_full_seed$(seed)"
    p_before = load_into(ctx.p_template, joinpath(PARAMS_DIR, "ude_$(tag).jld"))
    p_after  = load_into(ctx.p_template, joinpath(RETRAIN_PARAMS, "ude_ude_full_seed$(seed).jld"))

    l_before = p_before === nothing ? NaN : ctx.loss_fn(p_before)
    l_after  = p_after  === nothing ? NaN : ctx.loss_fn(p_after)
    l_rec    = get(recorded, seed, NaN)
    # Relative disagreement between our recomputation and the recorded value.
    drift = (isnan(l_after) || isnan(l_rec)) ? NaN : abs(l_after - l_rec) / l_rec

    push!(rows, (; seed,
                   final_loss_before = l_before,
                   final_loss_after_recomputed = l_after,
                   final_loss_after_recorded = l_rec,
                   after_recompute_rel_diff = drift))
    @printf("  seed %d :  before = %10.4f   after = %10.4f  (recorded %10.4f, rel diff %.2e)\n",
            seed, l_before, l_after, l_rec, drift)
end

df = DataFrame(rows)
CSV.write(joinpath(OUT_DIR, "training_losses_before_after.csv"), df)

b = collect(skipmissing(df.final_loss_before)); b = b[.!isnan.(b)]
a = collect(skipmissing(df.final_loss_after_recomputed)); a = a[.!isnan.(a)]
d = collect(skipmissing(df.after_recompute_rel_diff)); d = d[.!isnan.(d)]

println()
@printf("  BEFORE (Adam 5000 / BFGS 300) : %.4f +/- %.4f  (n=%d)\n", mean(b), std(b), length(b))
@printf("  AFTER  (Adam 20000 / BFGS 1000): %.4f +/- %.4f  (n=%d)\n", mean(a), std(a), length(a))
@printf("  loss reduction: %.2f %% of the before value\n", 100 * (mean(b) - mean(a)) / mean(b))
if !isempty(d)
    @printf("  max |recomputed - recorded| / recorded = %.3e  %s\n", maximum(d),
            maximum(d) < 1e-6 ? "(recomputation validated)" : "(WARNING: disagreement)")
end
println("\nwrote ", joinpath(OUT_DIR, "training_losses_before_after.csv"))
