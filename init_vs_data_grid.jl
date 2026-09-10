# =============================================================================
#  init_vs_data_grid.jl   --   E3: DECOUPLE INITIALISATION FROM THE DATA DRAW
# =============================================================================
#  THE CAVEAT THIS RETIRES.  Every spread this project reports -- the published
#  1.645 +- 0.672, E1's 1.543 +- 1.237 (SSE) and 1.925 +- 0.605 (chi2) -- is a
#  spread across SEEDS, and a seed sets two independent things at once:
#
#      make_ca_network(seed)   StableRNG(seed) -> the network initialisation
#                              (src/experiment.jl:146-150)
#      gen_noisy_data(...; seed = seed)  a FRESH StableRNG(seed) -> the noise draw
#                              (src/hh_core.jl:164)
#
#  run_ude hands the same integer to both, so the two streams are already
#  independent and merely share a label. Nothing in the repository has ever
#  varied them separately, which is why the Limitations text can only call the
#  reported number a JOINT init-and-data spread. It has never been decomposed.
#
#  WHAT THIS DOES.  Crosses them: every initialisation seed against every data
#  seed, on both objectives. The published/E1 runs are the DIAGONAL of that grid.
#
#      a_hat[i, d]  for i in INIT_SEEDS, d in DATA_SEEDS, arm in {sse, chi2}
#
#  and a two-way random-effects decomposition then splits the variance into an
#  initialisation component, a data component and a residual (the interaction,
#  which a one-observation-per-cell design cannot separate from noise).
#
#  WHY IT MATTERS MORE AFTER E1, NOT LESS.  E1 found the SSE arm's relative
#  spread is 0.802 at n=28, not the 0.408 the published five seeds suggested,
#  with three seeds recovering a NEGATIVE conductance. A spread that large is
#  worth attributing. If it is mostly the data draw, the closure is at the mercy
#  of one noise realisation and more data is the answer. If it is mostly the
#  initialisation, the closure is finding different optima on identical data and
#  the answer is averaging or a better-conditioned representation. Those are
#  different papers, and right now the evidence cannot tell them apart.
#
#  THE DESIGN IS THE PUBLISHED SEEDS, CROSSED. INIT_SEEDS and DATA_SEEDS are both
#  1111*k for k = 1..GRID -- the same arithmetic rule as NW_SEEDS, and its first
#  five entries are the published five. So the diagonal of this grid IS the
#  published experiment, which is what makes the self-test below possible.
#
#  SELF-TEST, IN TWO STAGES, AND THE FIRST ONE GATES.
#    stage 1, before anything else: the (sse, i=1111, d=1111) cell must reproduce
#      the published forecast V RMSE 0.2191970340109573 bit-for-bit. Eight
#      minutes, and it proves this harness is still run_experiment.
#    stage 2, at the end: EVERY diagonal cell must reproduce the corresponding
#      E1 run in results_noiseweighted/noise_weighted_summary.csv. A diagonal
#      cell and an E1 run are the same computation under two different names, so
#      any difference means the crossing was implemented wrongly -- the likeliest
#      bug in the whole script, and one no value-check on a single cell catches.
#      Exits non-zero on mismatch.
#
#  ISOLATION.  HH_RESULTS_DIR / HH_FIG_DIR are set BEFORE the includes, so this
#  writes to results_initdata/ only. results/ and results_noiseweighted/ are read
#  but never written. E3_SMOKE=1 diverts to results_e3_smoke/ so a reduced-budget
#  run can never land on real output under a matching filename.
#
#  RESUMABLE. A (arm, init, data) cell whose probe AND summary row both exist is
#  skipped and carried forward. The CSV is rewritten after every run. The loop is
#  CELL-major over the diagonal first, then the off-diagonal, so a killed job
#  leaves the self-testable part complete. E3_FORCE=1 disables skipping.
#
#  COMPUTE.  GRID=5 -> 2 arms x 25 cells = 50 runs x ~8 min ~= 6.7 h unattended.
#
#  Run:  julia --project=. init_vs_data_grid.jl
#        E3_SMOKE=1 julia --project=. init_vs_data_grid.jl     # plumbing only
# =============================================================================

const ROOT = @__DIR__

const _E3_SMOKE = get(ENV, "E3_SMOKE", "0") == "1"
ENV["HH_RESULTS_DIR"] = get(ENV, "E3_RESULTS_DIR",
    joinpath(ROOT, _E3_SMOKE ? "results_e3_smoke" : "results_initdata"))
ENV["HH_FIG_DIR"] = get(ENV, "E3_FIG_DIR",
    joinpath(ROOT, _E3_SMOKE ? "figures_e3_smoke" : "figures_initdata"))
delete!(ENV, "HH_SMOKE")

include(joinpath(ROOT, "src", "hh_core.jl"))
include(joinpath(ROOT, "src", "metrics.jl"))
include(joinpath(ROOT, "src", "experiment.jl"))

using Printf, Statistics, DataFrames, CSV

const E3_GCA   = 2.0
const E3_NOISE = 0.02
const E3_TWIN  = 30.0
const E3_GRID  = parse(Int, get(ENV, "E3_GRID", _E3_SMOKE ? "2" : "5"))
const INIT_SEEDS = [1111 * k for k in 1:E3_GRID]
const DATA_SEEDS = [1111 * k for k in 1:E3_GRID]
const E3_ARMS  = [:sse, :chi2]
const E3_FORCE = get(ENV, "E3_FORCE", "0") == "1"
const E3_ADAM  = _E3_SMOKE ? 30 : 5000
const E3_BFGS  = _E3_SMOKE ? 5  : 300

const SELFTEST_TARGET = 0.2191970340109573
const SELFTEST_RTOL   = 1e-6
const E1_SUMMARY = joinpath(ROOT, "results_noiseweighted", "noise_weighted_summary.csv")
const OUT_CSV    = joinpath(ENV["HH_RESULTS_DIR"], "init_vs_data_summary.csv")

e3_tag(arm, i, d) = "e3_$(arm)_i$(i)_d$(d)"
# Derived from the engine's own _calcium_id (src/experiment.jl:274), not from a
# restatement of its rule: it appends "_seed<n>" unless the tag already ends in
# one, and a hand-copied version of that rule is exactly the kind of drift that
# has bitten this repo before.
e3_probe(arm, i, d) =
    joinpath(ENV["HH_RESULTS_DIR"], "calcium",
             "probe_$(_calcium_id(e3_tag(arm, i, d), d)).csv")

# The loss, mirrored from noise_weighted_ude.jl, which mirrors make_ude_loss
# (src/experiment.jl:173-188). Identical there; repeated here so E3 does not
# depend on E1's script staying loaded.
function make_loss(objective::Symbol, predict, data_noisy, train_idx, sigma)
    ntrain = length(train_idx)
    return function (p)
        pred = predict(p)
        size(pred, 2) == ntrain || return 1.0e6
        r = data_noisy[:, train_idx] .- pred
        return objective === :chi2 ? sum(abs2, r ./ sigma) : sum(abs2, r)
    end
end

# -----------------------------------------------------------------------------
#  run_experiment, mirrored, with the ONE change this experiment exists to make:
#  the initialisation seed and the data seed are separate arguments. Setting them
#  equal reproduces run_experiment exactly, which is what the diagonal self-test
#  checks. Everything else is lifted from src/experiment.jl:383-432.
# -----------------------------------------------------------------------------
function run_cell(; init_seed, data_seed, objective, gCa = E3_GCA,
                    noise_level = E3_NOISE, t_train_end = E3_TWIN)
    tag = e3_tag(objective, init_seed, data_seed)
    @printf("[run_cell] %s  init=%d data=%d objective=%s\n",
            tag, init_seed, data_seed, objective)
    data_clean = gen_clean_data(gCa).data_clean
    data_noisy = gen_noisy_data(data_clean, noise_level; seed = data_seed)   # <- data
    split      = make_split(t_train_end)
    u0         = steady_state_u0()
    sigma      = noise_level .* std(data_clean, dims = 2)

    nn_ca, p_ca0, st_ca = make_ca_network(init_seed)                          # <- init
    rhs  = make_hh_ude(nn_ca, st_ca)
    prob = ODEProblem(rhs, u0, split.tspan_train, p_ca0)
    predict(p) = Array(solve(prob, Tsit5(); p = p, saveat = split.tsteps_train,
                             abstol = 1e-8, reltol = 1e-8, verbose = false, sensealg = ADJOINT))

    tr = train_two_stage(make_loss(objective, predict, data_noisy, split.train_idx, sigma),
                         p_ca0; adam_lr = 1e-2, adam_iters = E3_ADAM,
                         bfgs_iters = E3_BFGS, label = "UDE[$objective]")
    p_ca = tr.p
    pred_full = solve_aligned(rhs, u0, p_ca)

    Vt = data_clean[1, :]; st_ = data_clean[6, :]; Vn = Vt ./ 100.0
    ICa_nn   = [nn_ca([Vn[i], st_[i]], p_ca, st_ca)[1][1] for i in eachindex(Vt)]
    ICa_true = gCa .* st_ .^ 2 .* (Vt .- ECa)

    metrics = compute_metrics(; model = "UDE", observed = :full, gCa = gCa,
                                noise_level = noise_level, t_train_end = t_train_end,
                                seed = data_seed, t = TSTEPS, truth = data_clean,
                                pred = pred_full, train_idx = split.train_idx,
                                forecast_idx = split.forecast_idx,
                                truth_noisy = data_noisy, ICa_true = ICa_true,
                                ICa_nn = ICa_nn, common_idx = nothing)

    snapshot_params(tag, p_ca)
    save_calcium_probe(tag, data_seed, TSTEPS, Vt, st_, Vn, ICa_true, ICa_nn)
    save_calcium_grid_probe(nn_ca, p_ca, st_ca, gCa, tag, data_seed, Vt, st_)
    return (; tr, metrics)
end

function pick(metrics, window::String, metric::String)
    hits = filter(r -> r.window == window && r.metric == metric, metrics)
    length(hits) == 1 ||
        error("pick: expected exactly 1 row for $window/$metric, got $(length(hits))")
    return hits[1].value
end

row_of(arm, i, d, r) =
    (; objective = String(Symbol(arm)), init_seed = i, data_seed = d,
       on_diagonal = (i == d), final_loss = r.tr.final_loss, bfgs_ok = r.tr.bfgs_ok,
       forecast_V_rmse = pick(r.metrics, "forecast", "V_rmse"),
       forecast_ICa_rmse = pick(r.metrics, "forecast", "ICa_rmse"),
       train_V_rmse = pick(r.metrics, "train", "V_rmse"))

# =============================================================================
#  STAGE 1 SELF-TEST — prove this harness is still the engine. Eight minutes.
# =============================================================================
println("\n=== SELF-TEST 1: (sse, init=1111, data=1111) must reproduce the published run ===")
st = run_cell(; init_seed = 1111, data_seed = 1111, objective = :sse)
st_val = pick(st.metrics, "forecast", "V_rmse")
st_rel = abs(st_val - SELFTEST_TARGET) / SELFTEST_TARGET
@printf("  published : %.16f\n  this run  : %.16f\n  rel diff  : %.3e (tol %.0e)\n",
        SELFTEST_TARGET, st_val, st_rel, SELFTEST_RTOL)
if _E3_SMOKE
    println("  SKIPPED -- E3_SMOKE=1 is a reduced budget. THESE NUMBERS ARE MEANINGLESS.")
elseif !(st_rel <= SELFTEST_RTOL)
    println("\n*** SELF-TEST FAILED. Setting init_seed == data_seed must reproduce")
    println("run_experiment exactly; it does not, so the crossing is not a crossing")
    println("of the published experiment. NOT running the grid.")
    exit(1)
else
    println("  PASS -- the diagonal is the published experiment. Proceeding.")
end

# =============================================================================
#  THE GRID — diagonal first, so a killed job leaves the self-testable part done.
# =============================================================================
cached = Dict{Tuple{String,Int,Int},NamedTuple}()
if !E3_FORCE && isfile(OUT_CSV)
    try
        for r in CSV.File(OUT_CSV)
            cached[(String(r.objective), Int(r.init_seed), Int(r.data_seed))] =
                (; objective = String(r.objective), init_seed = Int(r.init_seed),
                   data_seed = Int(r.data_seed), on_diagonal = Bool(r.on_diagonal),
                   final_loss = Float64(r.final_loss), bfgs_ok = Bool(r.bfgs_ok),
                   forecast_V_rmse = Float64(r.forecast_V_rmse),
                   forecast_ICa_rmse = Float64(r.forecast_ICa_rmse),
                   train_V_rmse = Float64(r.train_V_rmse))
        end
        @printf("resume: read %d cached cells\n", length(cached))
    catch err
        @warn "resume: unreadable CSV; running every cell." exception = err
        empty!(cached)
    end
end
delete!(cached, ("sse", 1111, 1111))    # just re-run as the gate; keep the fresh one

const ROWS = NamedTuple[]
record!(r) = (push!(ROWS, r); CSV.write(OUT_CSV, DataFrame(ROWS)))

record!(row_of(:sse, 1111, 1111, st))

function run_grid()
    cells = [(arm, i, d) for arm in E3_ARMS for i in INIT_SEEDS for d in DATA_SEEDS]
    sort!(cells; by = c -> (c[2] != c[3], String(Symbol(c[1])), c[2], c[3]))  # diagonal first
    for (arm, i, d) in cells
        key = (String(Symbol(arm)), i, d)
        (arm === :sse && i == 1111 && d == 1111) && continue      # the gate, recorded
        if haskey(cached, key) && isfile(e3_probe(arm, i, d))
            @printf("[skip] %s i=%d d=%d\n", arm, i, d)
            record!(cached[key]); continue
        end
        record!(row_of(arm, i, d, run_cell(; init_seed = i, data_seed = d, objective = arm)))
    end
end
run_grid()

# =============================================================================
#  STAGE 2 SELF-TEST — every diagonal cell must equal its E1 run.
# =============================================================================
println("\n=== SELF-TEST 2: the diagonal vs E1's noise_weighted_summary.csv ===")
df = DataFrame(ROWS)
if _E3_SMOKE
    println("  SKIPPED -- smoke budget.")
elseif !isfile(E1_SUMMARY)
    println("  SKIPPED -- $E1_SUMMARY not found.")
else
    e1 = DataFrame(CSV.File(E1_SUMMARY))
    # WRAPPED IN A FUNCTION DELIBERATELY. Accumulators assigned inside a
    # top-level `for` are new locals under Julia's soft scope, so `n += 1` reads
    # an undefined local and throws. HANDOFF section 9 names this; it still bit
    # here, in the same session in which it was fixed once already.
    function compare_diagonal(df, e1)
        worst, worst_lbl, n = 0.0, "(none compared)", 0
        for r in eachrow(df[df.on_diagonal, :])
            m = e1[(e1.objective .== r.objective) .& (e1.seed .== r.init_seed), :]
            nrow(m) == 1 || continue
            d = abs(r.forecast_V_rmse - m[1, :forecast_V_rmse]) / abs(m[1, :forecast_V_rmse])
            @printf("  %-4s seed %6d  rel diff %.3e\n", r.objective, r.init_seed, d)
            n += 1
            if d > worst
                worst, worst_lbl = d, "$(r.objective) seed $(r.init_seed)"
            end
        end
        return worst, worst_lbl, n
    end
    worst, worst_lbl, n = compare_diagonal(df, e1)
    if n == 0
        println("  *** no diagonal cell matched an E1 row -- cannot verify. ***"); exit(1)
    elseif !(worst <= SELFTEST_RTOL)
        @printf("\n*** SELF-TEST 2 FAILED: worst %.3e at %s. ***\n", worst, worst_lbl)
        println("A diagonal cell and an E1 run are the same computation under two names.")
        println("They differ, so the crossing is implemented wrongly and the off-diagonal")
        println("cells cannot be trusted.")
        exit(1)
    else
        @printf("  PASS -- %d diagonal cells, worst rel diff %.3e.\n", n, worst)
    end
end

@printf("\n%d cells: %d sse, %d chi2  (%d on the diagonal)\n", nrow(df),
        sum(df.objective .== "sse"), sum(df.objective .== "chi2"), sum(df.on_diagonal))
println("wrote $OUT_CSV")
println("""
Forecast error is not the point here. Next, no retraining needed:
    python scripts/distil_init_vs_data.py
""")
