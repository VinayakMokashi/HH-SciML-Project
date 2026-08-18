# HANDOFF — Advanced Hodgkin–Huxley × SciML

> **Last updated 2026-08-18.** Restructured, not truncated. Sections 1–9 and 13–14 describe the
> CURRENT state; the earlier draft's thesis was overturned by our own control (§2) and the sections
> asserting it were rewritten rather than left to contradict the new ones. **Sections 10–12 preserve
> the project's history**: past mentor rulings, reproducibility notes, file schemas and the external
> code review. Do not delete those — several settled decisions are only explained nowhere else.
>
> **This file is SNAPSHOT-ONLY as of 2026-08-18.** It is gitignored so it never appears in the repo's
> file tree, but is committed as a deliberate snapshot and then removed again, so every version stays
> recoverable from history. Use `scripts/snapshot_handoff.ps1`, which makes both commits; a manual
> commit needs `git add -f`.
>
> **This is NOT a privacy mechanism.** The repo is PUBLIC and GitHub shows deleted files in their
> commit diffs, so every snapshot — including the mentor's quoted emails, the Overleaf link and the
> local paths below — is readable by anyone who opens the history. Out of the tree is not out of
> sight. **Do not put anything here you would not publish.** Unpublished results, candid assessments
> of collaborators, or credentials belong somewhere else entirely.
>
> Recover a past version: `git log --oneline --all -- HANDOFF.md`, then
> `git show <commit>:HANDOFF.md > HANDOFF.md`.

## 1. Goal
Apply Scientific ML to an **advanced Hodgkin–Huxley** neuron (classical HH + persistent-Na⁺ `I_NaP`
+ calcium `I_Ca`). Three objectives: **(1)** black-box Neural ODE for forecasting, **(2)** UDE that
keeps known physics and learns only the hidden calcium current, **(3)** symbolic recovery of that
learned current. Bootcamp/research project under Vizuara mentors (Prathamesh Dinesh Joshi);
deliverable is a NeurIPS-workshop-quality paper plus the public repo.

---

## 2. THE PAPER'S THESIS (changed 2026-08-06 — read this before touching anything)

The draft used to argue: *the calcium conductance is not identifiable from a single trajectory.*
**That is false and we proved it false ourselves.**

A direct two-parameter fit of `(gCa, ECa)` to the **same** single noisy trajectory — true structure
known, no network — recovers the conductance to **2.092 ± 0.130** against a true 2.0 (±6.2%).
Cross-validated three independent ways: profile-likelihood 95% CI **[1.625, 2.125]**, Gauss–Newton
relative SE **6.7%**, observed seed spread **6.2%**. χ²/point = **0.994**, i.e. the fit sits exactly
at the known noise floor.

The UDE + symbolic route on identical data gives **1.645 ± 0.672** (supervised trajectory) or
**1.596 ± 0.905** (convex hull). **All five** closure estimates fall outside the interval the data
support.

**So: the data determine the conductance; the flexible closure loses it.** Parametric
identifiability holds, functional identifiability fails — exactly the distinction in Loman, Browning
& Baker (arXiv 2606.30289), the paper Prathamesh asked us to add.

**Mandatory caveat that must travel with this claim:** a 2-parameter model given the true functional
form is EXPECTED to beat a 337-parameter closure given no form, and it also forecasts ~2× better
(0.123 vs 0.245 mV). The licensed inference is one-directional and sufficient: *because the data pin
the conductance, the closure's failure to pin it is not the data's fault.* Never write "two equally
good fits disagree".

---

## 3. Headline numbers (all 5 seeds unless noted; mean ± SD)

### Forecasting (forecast window, vs clean truth)
| model | V RMSE (mV) | rollout (ms) | note |
|---|---|---|---|
| Neural ODE, published (Adam 3000, **+ raw time input**) | span 229–9213 | 0.548 ± 0.655 | blows up |
| Neural ODE, parity budget (Adam 5000, + time) | span 275–11762 | 0.431 ± 0.446 | **budget explains nothing** |
| Neural ODE, parity budget, **autonomous** | median **16.88** | 19.53 ± 17.75 | **architecture explains everything** |
| UDE full-state | 0.245 ± 0.028 | 70 (capped, every seed) | |
| UDE voltage-only | 0.264 ± 0.118 | 70 (capped) | equivalent within noise |
| Parametric (gCa,ECa) fit | 0.123 ± 0.032 | — | |

- NODE autonomous per-seed V RMSE: 34.5 / 8.7 / 11.1 / **294.8** / 16.9 → **quote the median**, the
  mean (73.2 ± 124) is one bad seed. 4 of 5 seeds get the spike count exactly right.
- **Never** print mean ± SD for the two time-indexed NODE rows — guard G2 (`node-no-meanstd`).
  Spans only. The map entries exist but are marked DO NOT PRINT.

### Common-eval window (t > 50 ms, unseen for both conditions)
full **0.266 ± 0.037** vs voltage-only **0.289 ± 0.137** mV; I_Ca 1.251 ± 0.212 vs 1.382 ± 0.478.

### Symbolic recovery, gCa = 2.0
- Conductance form `s²(aV+b)` **supplied, not discovered**. R² vs true current **0.991 ± 0.005** on
  the supervised trajectory.
- â = **1.645 ± 0.672** (traj-train, THE HEADLINE) · 1.596 ± 0.905 (hull) · b̂ = −259.3 ± 59.5.
- **Domain-robust:** six domains give â means 1.36–1.65, SDs 0.50–0.90. The domains **overlap, they
  do not nest**.
- Conditioning correction: the near-collinearity argument applies to the **6-term SINDy library**
  (cond ~25k trajectory, ~14k hull), NOT the 2-term conductance form (102.4 vs 69.9, both benign).
- Sanity fit on the TRUE current still returns a = 2.0000, b = −240.00 exactly.

### gCa sweep, now 5 seeds at every point (forecast `ICa_rmse_norm`)
0.4 → **0.724 ± 0.318** · 1.0 → 0.312 ± 0.097 · 2.0 → 0.140 ± 0.025 · 4.0 → 0.093 ± 0.044
- **Only the 1.0→2.0 step clears 2 pooled SD** (2.4). 0.4→1.0 (1.8) and 2.0→4.0 (1.3) do not.
  Claim the END-TO-END trend, never an individual step.
- The old single-seed 1.179 at gCa=0.4 was the **worst of five**. "Normalised error exceeds one at
  the physiological value" is **NOT supported** — do not restore it.
- Raw I_Ca error is statistically **flat** across the sweep (1.19–1.48, all overlapping): the
  closure's absolute error barely moves, only the signal grows.
- Forecast V RMSE is flat across the sweep too (0.19–0.25).

### Aggressive retrain (Adam 20000 / BFGS 1000)
- Training loss **35.71 ± 1.81 → 29.66 ± 2.66 (−17%)** — recovered from saved params, not rerun.
  So the optimiser **succeeded** and the science got worse. That is the whole point; the old framing
  ("more optimisation did nothing") understates it.
- â 1.596 → 1.49; R² 0.984 → 0.845; forecast V RMSE 0.245 → ~0.76.
- Seed-1111 decoupling: forecast V RMSE ~unchanged (0.219→0.251) while R²_cond collapsed
  0.988→0.580. Same trajectory quality, different and no better closure.
- **gCa = 0.4 negative control (new, real):** hull â −0.372 → **−1.341**, R² 0.688 → **−0.331**
  (worse than predicting the current's own mean). On traj-train both budgets return ~0
  (−0.061 → +0.021) against a true +0.4 — report as "learns nothing", **NOT** as sign recovery.

---

## 4. Mentor review (2026-08) — ALL POINTS DISCHARGED

| # | Ask | Status |
|---|---|---|
| 1 | Parametric (gCa,ECa) fit + loss surface / profile likelihood / conditioning | ✅ `identifiability_parametric.jl` |
| 1b | Directly comparable training losses, before vs after retrain | ✅ `recover_training_losses.jl` (no retrain; validated rel-diff 0) |
| 2 | Soften "functional-form recovery" | ✅ form is SUPPLIED; banned phrasings recorded in claims.yaml |
| 3 | Revisit convex-hull evaluation | ✅ six domains; headline moved to supervised trajectory |
| 4 | Exact loss-normalisation formula + "propagation" not "reconstruction" | ✅ eq:loss; **no weights, V = 99.97% of the objective** |
| 5a | NODE comparable budget + better architecture | ✅ `node_parity.jl` — budget explains nothing, architecture everything |
| 5b | gCa sweep across all five seeds | ✅ `gca_sweep_5seed.jl` |
| 6 | 5 incomplete DOIs; add Loman/Browning/Baker; correct Beck; citation report | ✅ `paper/citations-audit.md`, `scripts/verify_references.py` |
| 7 | −65/−50, calcium row, gCa=0.4 source, noise, units, hyperlink boxes, Sreedath | ✅ all in main.tex |

**Beck et al.: he was right on two of three.** Their work DOES include calcium (665 Ca models in a
3,524-model database) and DOES discuss underdetermination substantively. Only "symbolic regression
is future work" survived. Corrected in Related Work.

**Citation bug his request caught:** we cited Optimization.jl's *version* DOI for v3.12.1, but
`Manifest.toml` says this project ran **v3.19.3**. Now the concept DOI + the real version.

**`Vizuara_Paper_HH.pdf` in the repo root is NOT a template** — it is the group's own prior paper
(Kainth, Joshi, R. Dandekar, R. Dandekar, Panat; arXiv 2511.11734, MSML 2025) on neural ODEs for
Hodgkin–Huxley. It was uncited; now cited. NOTE: arXiv spells the fifth author "Sreedat"; our byline
uses **"Sreedath"**, which Vinayak confirmed directly with Prathamesh on 2026-08-16 — **this is
settled, do not "fix" it back to match the arXiv record.** The bibliography entry keeps "Sreedat"
because a citation must reproduce the published record; only our own byline is corrected.

**"Paper banana" (image model) for figures: declined.** A generated figure is not traceable to the
CSVs and breaks Law I. The readability ask was met by regenerating from the real data instead.

---

## 5. Architecture (the engine is the source of truth)
```
src/hh_core.jl        model + data builders (closures; gCa/noise/window are ARGS, not consts).
                      COMMON_EVAL_START=50.0 + common_eval_indices().
src/metrics.jl        rmse / spike detection / rollout horizon / compute_metrics (tidy rows).
src/experiment.jl     run_experiment (UDE) + run_node_baseline (NODE) + figure savers + calcium
                      probe savers + param reload.  ALSO sets the global Plots font defaults.
experiments_runner.jl baselines×SEEDS + voltage-only×SEEDS + ablations -> CSVs + figures.
                      ALSO builds the fig7* ablation figures (NOT experiment.jl — see §9).
```
```
julia --project=. experiments_runner.jl              # full sweep (~26 trainings, 3-6 h)
HH_SMOKE=1  julia --project=. experiments_runner.jl  # fast pipeline check
HH_REPLOT=1 julia --project=. experiments_runner.jl  # rebuild CSVs+figures, no retrain
```

### Scripts added in the 2026-08 review round (all write to ISOLATED trees)
| script | output | note |
|---|---|---|
| `identifiability_parametric.jl` | `results/identifiability/` | `IDENT_PARTS=1,2,3,4` selects parts |
| `gca_sweep_5seed.jl` | `results/gca_sweep_5seed/` | only the missing cells (seeds 2222-5555) |
| `node_parity.jl` | `results/node_parity/` | `NODE_VARIANTS=autonomous\|timeinput`, `NODE_SEEDS=` |
| `recover_training_losses.jl` | `results/identifiability/` | no retrain; self-validating |
| `recover_voltage_only_commoneval.jl` | `results/identifiability/` | no retrain; self-validating |
| `retrain_gca2_20k.jl` | `results/retrain_gca2_20k/` | now takes `RETRAIN_GCA` / `RETRAIN_SEEDS` / `RETRAIN_OUT`, **defaults unchanged** |
| `figure_identifiability.jl` | `figures/fig13_*.png` | plotting only |
| `regen_fig2.jl` | `figures/fig2_*.png` | isolates the hang-prone NODE refit |
| `scripts/verify_references.py` | `paper/citations-audit.md` | Crossref + DataCite + arXiv |
| `scripts/summarize_gca_sweep.py` | `results/gca_sweep_5seed/gca_sweep_multiseed.csv` | dedupes |
| `scripts/summarize_node_parity.py` | `results/node_parity/node_parity_summary.csv` | dedupes |
| `scripts/symbolic_domain_comparison.py` | `results/identifiability/` | reproduces published hull fit to 1e-15 |
| `scripts/gca04_retrain_control.py` | `results/identifiability/` | imports the estimator from the above |

---

## 6. Key decisions & rationale
- **`gCa` / noise / `T_TRAIN_END` are NOT `const`** — closure factory args. A non-const global in the
  hot RHS forces dynamic dispatch and wrecks adjoint performance on Julia 1.6.7.
- **`gCa = 2.0`** is 5× the physiological value, which is now *derived in print*: Pospischil et al.
  (2008) IB cell runs the Reuveni L-current at 0.17 mS/cm² against gNa = 50 (ModelDB 123623,
  `demo_PY_IB.hoc:133,137`); rescaled to our squid gNa = 120 that ratio gives **0.408 ≈ 0.4**.
- **Train on noisy data, evaluate against the CLEAN trajectory.**
- **The loss has NO channel weights and NO normalisation** — raw units, so voltage carries
  **99.97%** of the expected full-state objective. This is why voltage-only ≈ full-state, and it is
  now stated in the paper rather than left as a mystery.
- **OU noise** θ=5, σ=0.5, level 0.02 = 2% of each channel's SD. At Δt≈0.196 ms the AR coefficient
  is 0.02, i.e. **effectively white** — the paper says so rather than claiming correlated noise.
- **Representative seed = 1111**, pre-registered, guardrail-checked as median-typical.

---

## 7. Files
- **Paper:** `paper/main.tex` · `paper/generated/metrics.{tex,json}` (**282 macros / 86 map
  entries**) · `paper/{claims,metrics_map}.yaml` · `paper/claim-guards.md` ·
  `paper/references.bib` (**38 entries**) · `paper/citations-audit.md` · `paper/figures/`.
- **The paper includes exactly 10 figures** (not the 42 in `figures/`): fig2, fig3, fig5, fig6,
  fig7b_commoneval, fig7c, fig9_before, fig11_before, fig11_after, fig13. `scripts/stage_figures.ps1`
  copies them into `paper/figures/` under disambiguated names; **fig13 must be copied manually**, it
  is not in that script's map yet.
- **Local only (gitignored):** `main.jl`, `Main_Clean.jl`, `Paper Writing Skills/`, `.claude/`,
  `__pycache__/`, and `HANDOFF.md` (snapshot-only — see the banner at the top).
- Repo: https://github.com/VinayakMokashi/HH-SciML-Project · Overleaf (PRIVATE, Claude gets 403):
  https://www.overleaf.com/project/68763f6fc5e21f10b0355123

---

## 8. Verification — run all of these after ANY edit
```
python "Paper Writing Skills/scripts/extract_metrics.py" --map paper/metrics_map.yaml --results-root results --out paper/generated/metrics.tex --json paper/generated/metrics.json --check
python "Paper Writing Skills/scripts/check_numbers.py" "paper/main.tex" --macros "paper/generated/metrics.tex"
python "Paper Writing Skills/scripts/check_claims.py" --claims "paper/claims.yaml" --tex "paper/main.tex" --metrics-tex "paper/generated/metrics.tex" --metrics-json "paper/generated/metrics.json" --figures-root "."
python "Paper Writing Skills/scripts/lint_prose.py" "paper/main.tex"
python scripts/verify_references.py
```
Current state: **check_numbers OK · check_claims 0 errors, 0 unsupported (31 claims: 4 retired,
27 supported) · lint_prose clean · 282/282 macros match disk · 38 refs, 36 verified, 0 unresolved.**

**⚠ The checkers verify traceability and ledger sync. They do NOT verify that a sentence agrees with
its evidence.** An adversarial audit of the rewrite (8 section auditors + independent adjudicators,
60 candidates) upheld **12** findings the checkers passed over — including the Introduction stating
the paper's thesis **backwards**. Re-run that audit after any thesis-level rewrite.

---

## 9. Gotchas
- **Julia 1.6.7**, pinned env. **Lux 0.5.14**: `LayerNorm` needs a matrix input.
- **`run_node_baseline` HANGS** on this stack. It is the LAST step of `HH_REPLOT=1`; summary figures
  are written before it, so **kill the job once figure mtimes stop advancing**. Use `regen_fig2.jl`
  to regenerate that one figure in isolation instead.
- **The fig7* ablation figures are built in `experiments_runner.jl`, NOT `src/experiment.jl`.** A
  font/margin change in experiment.jl does not reach them.
- **Font size and margin must move together.** A blanket 1.8× font bump clipped y-axis labels
  ("gate RMSE" → "ate RMSE"). Settled at ~1.3× (14/13/11/10) + left_margin 5→8 mm in experiment.jl
  and 8→16 mm with a 960×310n canvas in experiments_runner.jl.
- **Append-only CSVs contain smoke-test rows.** `metrics_gca_sweep.csv` and
  `metrics_node_parity.csv` — always dedupe keeping the **LAST** row per
  `(model,observed,gCa,noise_level,t_train_end,seed,window,metric)`. The summarize_* scripts do it.
- **Julia soft scope:** an accumulator assigned inside a top-level `for` never reaches the global.
  Wrap it in a function.
- Background Julia runs are **block-buffered**; use file mtimes as the progress signal.
- **Commits must have NO Claude co-author.** Vinayak is the committer.
- Plots emit benign `seriescolor does not match data indices` warnings on error-bar figures.
- **PowerShell 5.1 reads `.ps1` as ANSI unless the file has a BOM.** A single em-dash in a *comment*
  becomes mojibake and kills the PARSER, with the syntax error reported nowhere near the character.
  Keep `.ps1` files ASCII-only. (Cost us one debugging round on `snapshot_handoff.ps1`.)
- **`git commit` exits non-zero for "nothing to commit".** Never treat `$LASTEXITCODE` from it as a
  failure signal in a script; ask git what actually happened (`git rev-parse HEAD` before/after).
  Same script, same round.
- **Do not set `$ErrorActionPreference = "Stop"` in a script that shells out to git** on 5.1: this
  repo emits CRLF line-ending warnings on nearly every `add`, and they become terminating errors.

---

## 10. Project history (2026-06 → 2026-08)

Kept because the *why* behind settled decisions is not recoverable from the code, and because
several of these were mentor rulings that should not be silently reopened.

### Objective status
- **Objective 1 (Neural ODE):** done. Originally reported as "fits the training window then diverges
  in forecast". **That framing was corrected in 2026-08** — see §3; the divergence was an artifact of
  a raw time input, not a property of black-box models.
- **Objective 2 (UDE):** done, with multi-seed error bars and a fixed common evaluation window.
  - **Multi-seed:** NODE, UDE full-state and voltage-only over 5 seeds {1111,2222,3333,4444,5555}
    (`results/metrics_baseline_multiseed.csv`); `fig5`/`fig8` carry error bars. A
    representative-seed guardrail verifies 1111 is median-typical before its single-seed panels are
    used. Ablations stay single-seed at 1111 (mentor scope).
  - **Common evaluation window:** the training-window ablation is additionally scored on the fixed
    interval `t > 50 ms`, unseen for every training length {15,20,30,40,50}, so the comparison is
    apples-to-apples. Sanity check: at t_train=50 the common-eval value equals the forecast value.
- **Objective 3 (symbolic recovery):** done. `objective3_symbolic.jl` reads the saved calcium probes
  (no retraining). Method is self-contained — **not** DataDrivenSparse, which is why the early REPL
  attempt failed — mirroring the vetted Lotka–Volterra UDE+SINDy reference at
  `D:\SciML\bootcamp\Hands On Research Projects\Project 3\lotka_volterra_ude.jl` (relaxed LASSO /
  thresholded LSQ + OLS debiasing).

### Mentor loop
- **2026-07-07 — Prathamesh answered the three Objective-3 framing questions:**
  - **Q1 (headline):** lead with the **constrained conductance-form** recovery; present plain SINDy
    as the unconstrained discovery attempt. Its failure to sparsify is an identifiability
    observation **to report, not hide**.
  - **Q2 (identifiability sentence):** yes — state explicitly that the recovered coefficient reflects
    weak identifiability, and note the true-current sanity fit shows the regression is not at fault.
  - **Q3 (retrain):** greenlit **one bounded run** — retrain more aggressively, rerun the same
    symbolic pipeline. *"One clean additional run should be enough — do not expand into too many new
    experiments."* Scope decided: Adam + BFGS iteration bump only (multiple-shooting skipped, he did
    not ask for it); retrain all 5 gCa=2.0 `ude_full` seeds.
- **2026-07-24 — green light to draft.** *"We have enough evidence to make claims in the paper, so we
  are in good shape to start drafting it."* The evidence base was CLOSED from then until the 2026-08
  review reopened it with five specific asks.
- **2026-08 — the full review acted on. See §4.** Reply **sent to Prathamesh on 2026-08-18**
  covering all five majors, the citation work, the smaller corrections, and — leading the email —
  the reversal of the paper's thesis. Draft archived at `scratchpad/email_prathamesh.md`.
  **Awaiting his response**; the two questions put to him were whether the reversed thesis is the
  right story to lead with, and the venue.

### Commit chain
`cc4f80d` (train/forecast metrics, voltage-only, ablations) → `ee3b7f9` (multi-seed + common-eval +
calcium probes) → `38d7d4b` (Obj-2 figure legibility) → `2b5244c` (Objective 3 symbolic recovery) →
`c9614e0` (Obj-3 figure legibility) → `f3148b1` (aggressive retrain at gCa=2.0) → `96edf16` (paper
scaffold) → `310855c` (full prose draft) → **`a38745f` (2026-08-16, mentor review + thesis change)**.

---

## 11. Reproducibility & consistency notes

- **`HH_model.jl` (narrative, Sections 0–5)** seeds one shared `StableRNG(1111)` and draws noise →
  NODE init → UDE init sequentially; the engine gives each network a **fresh** `StableRNG(seed)`.
  Same model, architecture and hyperparameters, different random init ⇒ the narrative reproduces
  results **qualitatively only**. The engine + `results/metrics_all.csv` are authoritative for every
  reported number.
- **`metrics_all.csv` is a TIDY table** `(model, observed, gCa, noise_level, t_train_end, seed,
  window, metric, value)`. It contains multiple seed rows for the headline runs and
  `window="common_eval"` rows for the window-ablation runs and the baseline.
  `metrics_baseline.csv` (single-seed, REP_SEED), `metrics_baseline_multiseed.csv` (mean/std/n) and
  `ablation_{noise,window,gca}.csv` are wide views derived from it. NODE rows legitimately omit
  calcium (`ICa_*`) and carry `NaN` spike-time-error when diverged.
- **Filters on the tidy table MUST pin all of gCa / noise_level / t_train_end / seed** — the sweep is
  a star design, not a cross, so a loose filter silently pools ablation points into the baseline.
- Non-representative seeds carry `_seed<n>` in their tag already; `_calcium_id` avoids a double
  `_seed<n>_seed<n>` suffix on calcium filenames.

### Objective-3 inputs (pre-saved; no retraining needed)
- `results/calcium/probe_ude_full_seed{1111..5555}.csv` and `grid_ude_full_seed*.csv` (gCa=2.0,
  5 seeds), plus `probe_abl_gca_0.4_seed1111.csv` / `grid_abl_gca_0.4_seed1111.csv` (the gCa=0.4
  negative case). The 2026-08 sweep added the same pair for gCa ∈ {0.4,1.0,4.0} × seeds 2222–5555.
- Columns: `t,V,s,V_norm,ICa_true,ICa_nn` (probe, on-trajectory) and
  `V,s,V_norm,ICa_true,ICa_nn` (grid, 80×80 over the trajectory's bounding box).
- The learned closure is `Chain(Dense(2,16,tanh), Dense(16,16,tanh), Dense(16,1))` on inputs
  `[V/100, s]`; parameters in `results/params/ude_*.jld`, reload via `load_ude_params(tag, seed)`.

### Reference material (outside this repo)
- Mentor templates: `D:\SciML\bootcamp\Research Project\All Code\` — `Assignment_6.jl` (UDE),
  `UDE_Epidemiology.jl` (partial-observation loss, the pattern the voltage-only loss follows).
  `BlackholeDynamics.jl` imports DataDriven* but never uses them, so **no mentor SINDy example
  exists** — do not go looking for one again.
- Objective-3 reference: `D:\SciML\bootcamp\Hands On Research Projects\Project 3\lotka_volterra_ude.jl`.

### Figure inventory (`figures/`, 42 files; the paper uses 10 — see §7)
`01–08` dynamics + noise · `fig2_*` NODE · `fig3_*` UDE · `fig5` NODE-vs-UDE bars (±SD) ·
`fig6_*` voltage-only · `fig7`/`fig7b`/`fig7c` ablations · `fig7b_commoneval` fixed-window ablation ·
`fig8` full-vs-voltage (±SD) · `fig9–fig12` symbolic (baseline tree and retrain tree, colliding
basenames — staged with `_before`/`_after` suffixes meaning TRAINING BUDGET, not gCa) ·
`fig13` parametric identifiability.

---

## 12. External code-review cross-check (done 2026-07-01)

An earlier Claude.ai + Gemini web review of the training code was cross-checked against the engine.
**No bugs found** — almost every suggestion was already implemented: NN weights threaded through the
ODE `p` argument rather than globals; in-place RHS + `InterpolatingAdjoint(ReverseDiffVJP(true))`;
explicit `Float64` throughout; ternary rather than `ifelse` at the L'Hôpital singularity; gates never
clamped; voltage-only implemented.

- **Per-state loss weighting / state scaling** — raised as "V dominates the loss, gates ignored".
  Judged moot at the time because the gates are *physics-locked* to V by the known kinetics, so a
  V-dominated loss is arguably correct and is why voltage-only works.
  **2026-08 update: this reviewer was more right than we credited.** The domination is now
  quantified — voltage carries **99.97%** of the expected full-state objective — and it is stated in
  the paper as the explanation for the voltage-only equivalence. It is also exactly the imbalance
  that Kainth et al. (arXiv 2511.11734) correct with scale-aware residual normalisation. The
  observation was right; only the "so it doesn't matter" conclusion needed revising.
- **Warm-up / discard the first transient spike (~0–12 ms)** — minor. Including the transient in the
  0–30 ms training window did not hurt, and the brief off-limit-cycle excursion arguably *aids*
  identifiability.
- **The one genuinely open item:** multiple-shooting / curriculum training horizon. Still open, still
  never requested by the mentor. It would smooth the window-ablation non-monotonicity (which the
  paper explains as a fixed-iteration artifact) and harden some seeds.

---

## 13. NEXT STEPS

**Git state:** branch `main`, clean tree, sole-authored throughout. No SHA is pinned here on
purpose: this file is archived by a snapshot commit that is created *after* it is written, so any
SHA recorded inside it is permanently one commit stale. Run `git log --oneline -5` for the truth.
**Paper state:** all four checkers green, 0 unsupported claims, 282 macros, 38 refs verified,
Overleaf compile confirmed clean (fig13 layout, five-author byline, no figure overflow).
**Mentor:** full reply sent 2026-08-18; every point of his review is discharged (§4).

### Waiting on someone else
1. **Prathamesh's reply.** Two questions were put to him: whether the reversed thesis (§2) is the
   right story to lead with, and the venue. Do not restructure the argument until he answers - if he
   disagrees with the lead, the fix is presentational, not experimental.

### Blocking submission
2. **Read the rewritten Results + Discussion yourself.** The thesis changed and the checkers cannot
   tell you whether you agree with it. This is the one review no tool here can do.
3. **Check the Sim2Science CFP** (venue chosen 2026-08-18; ML4PS is no longer the target). Nothing in
   this repo records its page limit, format, or whether it is archival - and how much cutting is
   needed depends entirely on that.
4. **Cut to length once the limit is known.** If it is short-format, the two things that must survive
   are the parametric result (§2) and the NODE architecture attribution (§3). The window/noise
   ablations and the appendix are the natural first cuts.

### Should do before submission
5. **Hostile self-review (skill Phase 7).** The 17-objection table is in
   `Paper Writing Skills/references/review-and-rebuttal.md §3.1`. Several objections changed meaning
   when the thesis flipped - notably O3 ("you tuned gCa=2.0") and O4 ("it's just under-training"),
   both of which now have stronger answers than the table assumes.
6. **fig11 / fig12 still show the hull domain** while the text quotes the supervised trajectory.
   Captions say so, so it is honest, but regenerating them on `traj-train` would be cleaner. Cost:
   re-point `objective3_symbolic.jl`, which also writes `results/symbolic/*.csv` that many macros
   read - verify byte-identical output before trusting it (it was, on a plain re-run).
7. **`scripts/stage_figures.ps1` does not know about fig13.** Add it to the map so staging is one
   command instead of a command plus a manual copy.

### Routine
8. **Snapshot HANDOFF.md before each push:**
   `powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1 -Push`
   It is gitignored, so it is only archived when you do this deliberately.

### Deferred, with reasons
9. **Closure-ladder experiment** - a ladder of intermediate closures between 2 parameters and the
   full network, to find where identifiability is lost. Named in Limitations as the next experiment.
   Deliberately NOT run: a follow-up paper's worth of work, and the current contribution is complete
   without it.
10. **Multiple-trajectory positive control** - whether more trajectories restore identifiability
    *through the closure*. Also named in Limitations.
11. **Multiple-shooting / curriculum horizon** - would smooth the window-ablation non-monotonicity.
    Open since 2026-07; the mentor has never asked for it.

---

## 14. Next-session startup prompt

Copy everything between the fences into a fresh session.

```
We're continuing my Advanced Hodgkin-Huxley x SciML paper. Repo:
d:\SciML\bootcamp\Research Project\HH-SciML-Project    (branch: main)

THIS SESSION I WANT TO: <FILL IN>

--- STARTUP: read before doing anything ---
1. HANDOFF.md, in this order:
     Sec 2  - THE THESIS. It CHANGED in Aug 2026 and the change is counter-intuitive:
              the single trajectory DOES determine the calcium conductance (2.092 +/- 0.130
              against a true 2.0). The flexible neural closure is what loses it. Parametric
              identifiability holds; functional identifiability fails. Do not reintroduce
              "not identifiable from a single trajectory" anywhere.
     Sec 3  - current numbers, with the guards on which ones may be quoted and how.
     Sec 9  - gotchas. Several cost me hours; they are not optional reading.
     Sec 13 - next steps and current git/paper state.
     Sec 10-12 - project history, past mentor rulings, reproducibility notes. Consult
              before reopening any settled decision.
2. MEMORY.md and the memory files, especially:
     parametric-fit-shows-closure-induced-nonidentifiability
     mentor-review-weakened-three-claims
     paper-draft-and-layout
3. Skim paper/main.tex. The deliverable is paper/ (main.tex, generated/metrics.{tex,json},
   claims.yaml, metrics_map.yaml, references.bib, citations-audit.md, figures/).

--- HOW THIS PAPER IS BUILT ---
- Law I: every reported number is a \val macro from paper/generated/metrics.tex, traced
  through paper/metrics_map.yaml to a results CSV. Fixed INPUTS (constants, budgets,
  architecture) are preamble \newcommands with a source-file comment. A handful of
  literals carry a "% numok:" note ON THE SAME LINE - the checker is line-based.
- Law II: every claim lives in paper/claims.yaml with its scope, evidence and status.
  Anchor it in the prose with a "% claim: <id>" comment.
- Re-verify with the five commands in HANDOFF Sec 8. All five are currently green.
- *** The checkers verify traceability and ledger sync, NOT whether a sentence agrees
  with its evidence. *** An adversarial audit (8 section auditors + independent
  adjudicators) caught 12 real defects they had passed over, including the Introduction
  stating the thesis backwards. After any thesis-level edit, run that audit again.

--- GROUND RULES ---
- I am the committer. Commits have NO Claude co-author. Commit/push ONLY when I ask.
- NEVER commit: main.jl, Main_Clean.jl, "Paper Writing Skills/", .claude/, __pycache__/.
- HANDOFF.md is SNAPSHOT-ONLY: gitignored so it stays out of the repo listing, archived
  into history via scripts/snapshot_handoff.ps1 (run it before each push). It is NOT
  private - the repo is public and history is browsable. Do not put anything in it I
  would not publish.
- The evidence base is CLOSED unless I explicitly greenlight a run. Everything in the
  mentor's Aug 2026 review is already done.
- I compile on Overleaf (you get 403; local MiKTeX is broken). I paste errors back.
  Figures live in figures/, are staged into paper/figures/, and I upload them manually.
- Julia runs are long and block-buffered: use file mtimes as the progress signal, and
  know that run_node_baseline hangs (HANDOFF Sec 9).

--- WHERE THINGS STAND ---
Mentor's full review: discharged, reply sent 2026-08-18, awaiting his response on
(a) whether the reversed thesis is the right lead and (b) the venue.
Venue: Sim2Science. Its page limit is NOT recorded anywhere here - check the CFP before
planning any cut.
Paper: 0 unsupported claims, 282 macros, 38 references verified, compile clean.

Give me a short status read plus your recommended first step for the goal above,
and wait for my go before editing anything.
```

### If you only read one thing
The paper argues that a UDE can forecast a hidden ionic current beautifully and still
get its conductance wrong - and that this is caused by the flexible closure, not by a
shortage of data, because a two-parameter fit to the same trajectory recovers the
conductance to about six per cent. Every control in the paper exists to close off an
alternative explanation for that gap. If you find yourself weakening or hedging that
claim, check Sec 2 first: it is more strongly supported than it sounds.
