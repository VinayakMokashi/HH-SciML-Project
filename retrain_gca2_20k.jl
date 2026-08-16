# =============================================================================
#  retrain_gca2_20k.jl  —  bounded aggressive re-train of the gCa=2.0 UDE
# =============================================================================
#  Mentor-greenlit "one clean additional run" (reply 2026-07-07): retrain the
#  gCa=2.0 full-state UDE more aggressively (more Adam/BFGS iters), regenerate
#  the calcium probes, then rerun the EXACT symbolic pipeline to see whether the
#  conductance coefficients move toward a=2.0 / b=-240 and whether plain SINDy
#  sparsifies.  Scope this session: iteration bump ONLY (no multiple-shooting).
#
#  ISOLATION GUARANTEE — this script writes NOTHING under the canonical
#  results/calcium, results/params, results/symbolic, figures/, or
#  results/metrics_all.csv.  Every artifact lands under:
#        results/retrain_gca2_20k/{calcium,params}/  +  metrics_retrain.csv
#  The existing results are the untouched "before" snapshot.  It reuses the
#  engine's training primitives (via include) but redirects all output through
#  this file's own inline writers, so no engine save-fn hits the canonical dirs.
#
#  Retrains all 5 headline seeds {1111..5555} at gCa=2.0 (keeps Objective 3's
#  per-seed mean±std + pooled ensemble reproducible).  Voltage-only, NODE, the
#  other ablations, and the gCa=0.4 negative control are NOT retrained.  The
#  gCa=0.4 probe is copied into the run's calcium dir so the redirected Obj-3
#  finds its negative case in one place.
#
#  Run:
#    julia --project=. retrain_gca2_20k.jl                 # full aggressive run
#    RETRAIN_SMOKE=1 julia --project=. retrain_gca2_20k.jl # fast pipeline check
# =============================================================================

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))   # brings ADJOINT + all primitives

using DataFrames, CSV
import JLD

const SMOKE = get(ENV, "RETRAIN_SMOKE", "0") == "1"

# Aggressive budget (current baseline was Adam 5000 / BFGS 300).
const ADAM_ITERS = SMOKE ? 60 : 20_000
const BFGS_ITERS = SMOKE ? 5  : 1_000
# All 5 headline seeds in both modes (smoke just uses tiny iters) so the
# redirected Objective-3, which expects all 5, has every probe to read.
const RETRAIN_SEEDS = haskey(ENV, "RETRAIN_SEEDS") ?
    parse.(Int, split(ENV["RETRAIN_SEEDS"], ",")) : [1111, 2222, 3333, 4444, 5555]

# Baseline setting (unchanged from the canonical headline run).
#
# The three env overrides below all DEFAULT to the published configuration, so
# running this file with no environment set reproduces the original gCa=2.0 run
# byte for byte. They exist so the same code can run the physiological negative
# control at the aggressive budget:
#
#   RETRAIN_GCA=0.4 RETRAIN_SEEDS=1111 RETRAIN_OUT=retrain_gca04_20k \
#       julia --project=. retrain_gca2_20k.jl
#
# That control was previously missing, and its absence was actively dangerous:
# the old run COPIED the baseline gCa=0.4 probe into its own tree (see the copy
# step at the bottom), so the "after" negative-control row was byte-identical to
# the "before" one and read like a successful replication when nothing had been
# rerun. The copy is now skipped whenever gCa != 2.0.
const G_CA        = parse(Float64, get(ENV, "RETRAIN_GCA", "2.0"))
const NOISE_LEVEL = 0.02
const T_TRAIN_END = 30.0

# --- Isolated output tree ----------------------------------------------------
const OUT_DIR      = joinpath(ROOT, "results", get(ENV, "RETRAIN_OUT", "retrain_gca2_20k"))
const OUT_CALCIUM  = joinpath(OUT_DIR, "calcium")
const OUT_PARAMS   = joinpath(OUT_DIR, "params")
for d in (OUT_DIR, OUT_CALCIUM, OUT_PARAMS); mkpath(d); end

# --- Inline writers (redirected copies of the engine's savers) ---------------
# On-trajectory probe: same schema as src/experiment.jl save_calcium_probe.
function write_probe(seed, t, V, s, Vnorm, ICa_true, ICa_nn)
    df = DataFrame(t = collect(t), V = collect(V), s = collect(s), V_norm = collect(Vnorm),
                   ICa_true = collect(ICa_true), ICa_nn = collect(ICa_nn))
    CSV.write(joinpath(OUT_CALCIUM, "probe_ude_full_seed$(seed).csv"), df)
end

# Off-trajectory (V,s) grid over the trajectory's bounding box (80×80), same
# schema/logic as src/experiment.jl save_calcium_grid_probe.
function write_grid(nn, p_ca, st_ca, gCa, seed, Vtraj, straj; nV = 80, ns = 80)
    Vgrid = range(minimum(Vtraj), maximum(Vtraj); length = nV)
    sgrid = range(minimum(straj), maximum(straj); length = ns)
    rows = NamedTuple[]
    for Vv in Vgrid, sv in sgrid
        inn   = nn([Vv / 100.0, sv], p_ca, st_ca)[1][1]
        itrue = gCa * sv^2 * (Vv - ECa)
        push!(rows, (; V = Vv, s = sv, V_norm = Vv / 100.0, ICa_true = itrue, ICa_nn = inn))
    end
    CSV.write(joinpath(OUT_CALCIUM, "grid_ude_full_seed$(seed).csv"), DataFrame(rows))
end

# --- One seed: train + probe (core of run_experiment, output redirected) -----
function retrain_seed(seed)
    println("\n[retrain] seed=$seed  gCa=$G_CA  Adam=$ADAM_ITERS  BFGS=$BFGS_ITERS")
    data_clean = gen_clean_data(G_CA).data_clean
    data_noisy = gen_noisy_data(data_clean, NOISE_LEVEL; seed = seed)
    split      = make_split(T_TRAIN_END)
    u0         = steady_state_u0()

    nn_ca, p_ca0, st_ca = make_ca_network(seed)
    rhs  = make_hh_ude(nn_ca, st_ca)
    prob = ODEProblem(rhs, u0, split.tspan_train, p_ca0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))
    loss_fn = make_ude_loss(:full, predict, data_noisy, split.train_idx)

    tr   = train_two_stage(loss_fn, p_ca0; adam_lr = 1e-2,
                           adam_iters = ADAM_ITERS, bfgs_iters = BFGS_ITERS, label = "UDE-s$seed")
    p_ca = tr.p

    pred_full = solve_aligned(rhs, u0, p_ca)

    # probe the learned calcium current along the TRUE trajectory
    Vt = data_clean[1, :]; st_ = data_clean[6, :]; Vn = Vt ./ 100.0
    ICa_nn   = [nn_ca([Vn[i], st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]
    ICa_true = G_CA .* st_ .^ 2 .* (Vt .- ECa)

    write_probe(seed, TSTEPS, Vt, st_, Vn, ICa_true, ICa_nn)
    write_grid(nn_ca, p_ca, st_ca, G_CA, seed, Vt, st_)
    JLD.save(joinpath(OUT_PARAMS, "ude_ude_full_seed$(seed).jld"), "p_ca", Vector(p_ca))

    ti = split.train_idx; fi = split.forecast_idx
    return (; seed,
              final_loss     = tr.final_loss, bfgs_ok = tr.bfgs_ok,
              train_V_rmse   = rmse_safe(data_clean[1, ti], pred_full[1, ti]),
              forecast_V_rmse= rmse_safe(data_clean[1, fi], pred_full[1, fi]),
              train_ICa_rmse = rmse_safe(ICa_true[ti], ICa_nn[ti]),
              forecast_ICa_rmse = rmse_safe(ICa_true[fi], ICa_nn[fi]))
end

# =============================================================================
#  Run
# =============================================================================
println("="^76)
println(" gCa=$G_CA aggressive re-train (Adam $ADAM_ITERS / BFGS $BFGS_ITERS)  ",
        SMOKE ? "[SMOKE]" : "[FULL]")
println(" output tree: ", OUT_DIR, "  (canonical results/ + figures/ untouched)")
println("="^76)

summary = NamedTuple[]
for sd in RETRAIN_SEEDS
    try
        push!(summary, retrain_seed(sd))
    catch err
        @warn "retrain seed=$sd FAILED — continuing." exception = (err, catch_backtrace())
    end
end

# Copy the (unchanged) gCa=0.4 negative-case probe/grid into this run's calcium
# dir so the redirected Objective-3 reads its negative control from one place.
#
# ONLY when this run is the gCa=2.0 one. If we are ourselves retraining at
# gCa=0.4 the copy would overwrite the freshly trained probe with the baseline's
# and silently turn a real control into a duplicate of the thing it controls --
# which is exactly the trap the original version of this script laid.
if G_CA == 2.0
    for f in ("probe_abl_gca_0.4_seed1111.csv", "grid_abl_gca_0.4_seed1111.csv")
        src = joinpath(ROOT, "results", "calcium", f)
        dst = joinpath(OUT_CALCIUM, f)
        isfile(src) ? cp(src, dst; force = true) :
            @warn "negative-case file missing (Obj-3 neg case will fail): $src"
    end
else
    println("\n[note] gCa=$G_CA run: NOT copying the baseline gCa=0.4 probe. ",
            "This run's own probes are the negative control.")
end

# --- metrics_retrain.csv (this run only; canonical metrics_all.csv untouched) --
CSV.write(joinpath(OUT_DIR, "metrics_retrain.csv"), DataFrame(summary))

println("\n========== retrain summary (forecast vs clean truth) ==========")
for r in summary
    println("  seed $(r.seed): forecast V_rmse=$(round(r.forecast_V_rmse, sigdigits=4)) mV  ",
            "forecast ICa_rmse=$(round(r.forecast_ICa_rmse, sigdigits=4))  ",
            "train V_rmse=$(round(r.train_V_rmse, sigdigits=4))  bfgs_ok=$(r.bfgs_ok)")
end
println("\n[retrain complete]  probes -> $OUT_CALCIUM   metrics -> $(joinpath(OUT_DIR, "metrics_retrain.csv"))")
println("Next: julia --project=. objective3_symbolic_retrain.jl")
