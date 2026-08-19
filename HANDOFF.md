# HANDOFF — Advanced Hodgkin–Huxley × SciML

> **Last updated 2026-08-19.** Restructured, not truncated. Sections 1–9 and 13–14 describe the
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
- At gCa=0.4 the closure gives **-0.372 on the hull** (wrong sign) and **-0.061 on the supervised
  trajectory** (indistinguishable from zero) against a true +0.4. Neither is usable; they differ by
  a factor of six, so ALWAYS say which domain a number came from.

> **THE DOMAIN RULE - every recent error came from breaking it.**
> The text quotes the **supervised trajectory** for every conductance estimate. The **hull** appears
> only where it must: the two symbolic figure panels (fig9/fig11 were produced on it) and the
> retrain before/after pair (the retrained closures were distilled on it, so before/after has to
> match). **Wherever a hull number appears, the sentence or caption must say so.** Four separate
> defects in Aug 2026 - "sixty per cent" instead of forty, an unlabelled -0.372 in two places, and
> a Table 3 column still on the hull - were all this rule drifting. Check with:
> `grep -n "valSymbolicAHatNegControl\|valSymbolicAHatMeanStd" paper/main.tex` and confirm every
> hit has "hull" within a few lines or in its caption.

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
uses **"Sreedath"** and the email **sreedath@vizuara.com**, both confirmed with Prathamesh on
2026-08-16. (The email had been corrected on Overleaf but not in this source until 2026-08-18, so
an upload would have silently reverted it - check the byline survives any re-upload.) The name was
confirmed directly with Prathamesh on 2026-08-16 — **this is
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
| `figure_gca_sweep_5seed.jl` | `figures/fig7c_ablation_gca_5seed.png` | plotting only; the paper's Fig 5 |
| `figure_coeff_recovery_panels.jl` | `figures/fig11_coeff_recovery_{before,after}.png` | plotting only; also stages into `paper/figures/` |
| `scripts/check_tex_sanity.py` | (console) | control bytes + prose lost behind a mid-line `%` |
| `scripts/make_overleaf_zip.ps1` | `overleaf_upload.zip` | **the only correct way to build the Overleaf upload — see §7** |

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
- **Paper:** `paper/main.tex` · `paper/generated/metrics.{tex,json}` (**286 macros / 89 map
  entries**) · `paper/{claims,metrics_map}.yaml` · `paper/claim-guards.md` ·
  `paper/references.bib` (**38 entries**) · `paper/citations-audit.md` · `paper/figures/`.
- **The paper includes exactly 10 figures** (not the 45 in `figures/`): fig2, fig3, fig5, fig6,
  fig7b_commoneval, **fig7c_ablation_gca_5seed**, fig9_before, fig11_coeff_recovery_before,
  fig11_coeff_recovery_after, fig13. `scripts/stage_figures.ps1` stages 19 of them into
  `paper/figures/` under disambiguated names, and **as of 2026-08-19 it self-checks**: after
  copying it re-reads `main.tex` and throws if any `\includegraphics` target is missing from
  `paper/figures/`. fig13 and the five-seed sweep are in its map now, so staging is one command
  with no manual copy. The two `fig11_coeff_recovery_*` panels are **deliberately not in that
  map** — `figure_coeff_recovery_panels.jl` stages them itself (see the gotcha in §9).
  Do not hand-maintain this list: `scripts/make_overleaf_zip.ps1` derives it live from the
  `\includegraphics` calls in `main.tex` and refuses to build if one is missing.
- **Local only (gitignored):** `main.jl`, `Main_Clean.jl`, `Paper Writing Skills/`, `.claude/`,
  `__pycache__/`, and `HANDOFF.md` (snapshot-only — see the banner at the top).
- Repo: https://github.com/VinayakMokashi/HH-SciML-Project · Overleaf (PRIVATE, Claude gets 403):
  https://www.overleaf.com/project/68763f6fc5e21f10b0355123

### Uploading to Overleaf — the procedure, and why the obvious one fails
```
powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1
```
then in Overleaf: **Upload → pick `overleaf_upload.zip` → overwrite when asked → Recompile.**

**Do NOT zip the `paper` folder itself, and do NOT drag the folder in.** `main.tex` resolves
three paths against the *compile root*:

| line | path | needs |
|---|---|---|
| `\input{generated/metrics}` | `generated/metrics.tex` | `generated/` at the root |
| `\graphicspath{{figures/}}` | `figures/*.png` | `figures/` at the root |
| `\bibliography{references}` | `references.bib` | at the root |

Nesting the folder puts all three one level down (`paper/generated/...`) and every one of them
misses. The zip therefore carries the **contents** of `paper/` at its root. Three further traps,
all of which were hit and are now defended in the script:
- **`arxiv.sty` is not in this repo and never will be.** It is not a CTAN package, so Overleaf
  cannot supply it; it exists only inside the live Overleaf project, which is the sole reason the
  paper has ever compiled there. It is deliberately excluded from the zip so an overwrite cannot
  clobber it. **Never delete it**, and if a NEW project is ever started, copy it in first or the
  build dies on line 3.
- **Overleaf is Linux and case-sensitive.** Windows will happily resolve `Fig5.png` against
  `fig5.png`; Overleaf will not. The script matches names exactly.
- **`ZipFile.CreateFromDirectory` writes Windows separators** (`figures\fig2.png`). Linux unzip
  reads the backslash as a filename character, so nothing lands in `figures/` and every image
  breaks. The script writes entries by hand and verifies there is no backslash before handing the
  archive over.

The zip is gitignored — it is derived, everything in it is already tracked under `paper/`.
`claims.yaml`, `claim-guards.md`, `metrics_map.yaml` and `citations-audit.md` are **not**
uploaded: they are the audit trail, not build inputs.

---

## 8. Verification — run all of these after ANY edit
```
python "Paper Writing Skills/scripts/extract_metrics.py" --map paper/metrics_map.yaml --results-root results --out paper/generated/metrics.tex --json paper/generated/metrics.json --check
python "Paper Writing Skills/scripts/check_numbers.py" "paper/main.tex" --macros "paper/generated/metrics.tex"
python "Paper Writing Skills/scripts/check_claims.py" --claims "paper/claims.yaml" --tex "paper/main.tex" --metrics-tex "paper/generated/metrics.tex" --metrics-json "paper/generated/metrics.json" --figures-root "."
python "Paper Writing Skills/scripts/lint_prose.py" "paper/main.tex"
python scripts/verify_references.py
python scripts/check_tex_sanity.py
```
Current state (2026-08-19): **all six green — check_numbers OK (147 numbers, 0 flagged) ·
check_claims 0 errors, 0 unsupported (31 claims: 4 retired, 27 supported; the 10 duplicate-anchor
warnings are legal) · lint_prose clean · 286/286 macros match disk · 38 refs, 36 verified,
2 review, 0 unresolved · tex_sanity clean.** `doctor.py` reports 3 FAILs; those are the broken
local MiKTeX and are expected — compilation is Overleaf-only.

**`check_claims.py` MUST be run with `--figures-root .`** (repo root). With any other root its
basename fallback silently resolves `results/retrain_gca2_20k/figures/fig11_*.png` to the
*baseline's* file of the same name — the collision is documented at the top of `claims.yaml`.

`check_tex_sanity.py` (added 2026-08-19) exists because two defects reached a compiled PDF that
**nothing else could see** — not the other five, not `pdflatex -halt-on-error`, because both are
valid TeX:
1. a stray **control byte** where a macro name should be. A shell heredoc collapsed `\\v` to `\v`,
   Python read that as a vertical tab, and `$\valSymbolicAHatMeanStd$` became
   `$<VT>alSymbolicAHatMeanStd$` — which typeset as the raw italic letters "alSymbolicAHatMeanStd"
   in the Table 3 caption, silently, where a number belonged;
2. **prose swallowed by a mid-line `%`**, which left a sentence starting in mid-air.
**Never write LaTeX through a shell heredoc.** Every one of those was a backslash eaten in transit.
Use a patch file written directly to disk, and re-run this checker afterwards.

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
- **A regenerated figure can be silently reverted by `scripts/stage_figures.ps1`.** It copies
  `figures/* -> paper/figures/*` through a hand-written map, so if a figure is regenerated by a
  NEW script that writes a NEW name, the old map row still points at the superseded source and
  overwrites the good panel on the next staging run. This was live for the two
  `fig11_coeff_recovery_*` panels on 2026-08-19: the map still pointed at
  `fig11_calcium_coeff_recovery.png`, whose md5 differs, so running the documented staging
  command would have restored the unlabelled, independently-scaled panels and falsified the
  appendix caption's "on the same axes" claim. Fixed by removing those two rows and adding a
  self-check to the script. **When a figure gets a new generator, check the staging map.**
- **Font size and margin must move together.** A blanket 1.8× font bump clipped y-axis labels
  ("gate RMSE" → "ate RMSE"). Settled at ~1.3× (14/13/11/10) + left_margin 5→8 mm in experiment.jl
  and 8→16 mm with a 960×310n canvas in experiments_runner.jl.
- **A `% numok:` or `% claim:` comment placed MID-LINE silently deletes the rest of that line.**
  This shipped once: a numok appended after "...conductance's half." swallowed the clause that
  followed it, and the compiled PDF carried a sentence starting in mid-air. **No checker catches
  this** - `check_numbers` reads the comment as a valid exemption. Put such comments on their own
  line, or at the true end of a line. Detect with:
  `grep -n "% numok:" paper/main.tex` and read what follows each marker.
- **Overleaf silently renders an undefined `\val...` macro as NOTHING** and keeps compiling. If the
  PDF has blanks where numbers should be, the uploaded `generated/metrics.tex` is stale - it is not
  a source bug. Diagnose by checking whether the blanks are all macros added since the last upload.
  Re-upload `main.tex`, `references.bib` AND `generated/metrics.{tex,json}` together; a `?` in place
  of a citation is the same problem in `references.bib`.
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
  **A short follow-up is owed (2026-08-18).** The email's science is still accurate - nothing we
  changed afterwards altered a reported number - but the PDF built at that time was compiled from a
  STALE Overleaf upload: 47 blank values, two `?` citations, a missing Kainth paragraph, and one
  sentence starting mid-air from the comment bug. If he was sent or pointed at that build, send the
  corrected one. Draft: `scratchpad/email_prathamesh_followup.md`.

### External review passes (2026-08-19) — three rounds, all discharged
The compiled draft was put through a *separate* Claude session three times. It read the PDF and the
repo cold, with no memory of how anything got there, and that is exactly why it worked: every
defect it found had been invisible from inside the work. Worth repeating before submission.

- **Round 1 — the stale-build signature.** 47 blank values and two `?` citations in the PDF. Not a
  source bug at all: the Overleaf upload was stale. Diagnosis rule now in §9. Also caught a missing
  Kainth paragraph (the group's own prior paper, uncited).
- **Round 2 — the control byte.** `$\valSymbolicAHatMeanStd$` had become `$<VT>alSymbolic...$`: a
  shell heredoc collapsed `\\v` to `\v`, Python read it as a vertical tab, and the Table 3 caption
  typeset the raw italic letters `alSymbolicAHatMeanStd` where a number belonged. Valid TeX, so no
  checker could see it. Produced `scripts/check_tex_sanity.py` and the rule **never write LaTeX
  through a shell heredoc**. Also caught prose swallowed by a mid-line `%`.
- **Round 3 — figures contradicting their own text.** Seven text fixes (sweep qualification,
  profile-CI attribution to the representative seed, a missing "per cent", the Euler-Maruyama
  parenthetical, Appendix B budgets + `\ArchNodeAuto`, Table 4 caption scope), then two figure
  defects fixed the same day:
  1. **Fig 5 was still the single-seed panel** while the sentence citing it announced the five-seed
     sweep, and its caption had to apologise for itself. Replaced via `figure_gca_sweep_5seed.jl`
     with a three-panel figure that carries the *mechanism*: forecast voltage error flat, **raw**
     calcium error flat, **normalised** error down eightfold — i.e. raising gCa does not improve the
     closure, it enlarges the target. The single-seed panel could not show that.
  2. **Fig 6b and Fig 8b were visually identical** — same in-figure title — though they are the
     before/after of the retrain, the one comparison they exist to support. Both regenerated by
     `figure_coeff_recovery_panels.jl` naming their domain and budget, on **shared y-limits** so the
     "worse and noisier" claim is visible rather than asserted (the conductance whisker now reaches
     zero after the retrain). Plotting only, from the saved metrics CSVs: 162.5 / 171.3 mV and both
     `\val` macros reproduce exactly. Guard G14 still honoured — panel 3 carries no error bar.

  The ledger was re-pointed at the figures the paper now prints, two stale `n=1` sweep scopes were
  corrected, and **guard G13 was amended**: with five seeds the adjacent steps became *testable*, so
  the ban on reading the gCa 2.0→4.0 step stopped being a precaution about sample size and became a
  measured negative result (1.3 pooled SD, against 2.4 for 1.0→2.0). The guard got stricter.

### Commit chain
`cc4f80d` (train/forecast metrics, voltage-only, ablations) → `ee3b7f9` (multi-seed + common-eval +
calcium probes) → `38d7d4b` (Obj-2 figure legibility) → `2b5244c` (Objective 3 symbolic recovery) →
`c9614e0` (Obj-3 figure legibility) → `f3148b1` (aggressive retrain at gCa=2.0) → `96edf16` (paper
scaffold) → `310855c` (full prose draft) → `a38745f` (2026-08-16, mentor review + thesis change) →
`8eede75` (comment-swallowed prose + domain-number alignment) → `94e2fd8` (control-byte repair +
tex-sanity guard) → **the 2026-08-19 figure round**. Snapshot/remove HANDOFF pairs are interleaved
throughout; ignore them when reading the chain.

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

### Figure inventory (`figures/`, 45 files; the paper uses 10 — see §7)
`01–08` dynamics + noise · `fig2_*` NODE · `fig3_*` UDE · `fig5` NODE-vs-UDE bars (±SD) ·
`fig6_*` voltage-only · `fig7`/`fig7b`/`fig7c` ablations · `fig7b_commoneval` fixed-window ablation ·
`fig8` full-vs-voltage (±SD) · `fig9–fig12` symbolic (baseline tree and retrain tree, colliding
basenames — staged with `_before`/`_after` suffixes meaning TRAINING BUDGET, not gCa) ·
`fig13` parametric identifiability · `fig7c_ablation_gca_5seed` the five-seed sweep that
SUPERSEDES `fig7c_ablation_gca` in the paper · `fig11_coeff_recovery_{before,after}` the relabelled
coefficient panels, written straight into `figures/` AND `paper/figures/` by
`figure_coeff_recovery_panels.jl` (these two names are unique repo-wide, unlike the `fig9-fig12`
basenames, so they cannot be mis-resolved).

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

**Git state:** branch `main`, sole-authored throughout. Neither a SHA nor a "clean tree" claim is
recorded here on purpose: this file is archived by a snapshot commit created *after* it is
written, so any such statement is stale before it is read. **Run `git status --porcelain` and
`git log --oneline -5` for the truth** — and if `status` is non-empty, note that `git add -u`
stages tracked files ONLY, so new figures and new scripts must be added by path or they are
silently left behind.
**Paper state:** all six checkers green, 0 unsupported claims, 286 macros, 38 refs verified.
**The current source has NOT been compiled yet** — the last confirmed-clean Overleaf build predates
the round-3 text fixes and the two figure replacements. Uploading and reading the PDF is step 0.
**Mentor:** full reply sent 2026-08-18; every point of his review is discharged (§4).

### Do this first
0. **Rebuild the upload bundle and recompile on Overleaf:**
   `powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1`, then Upload →
   `overleaf_upload.zip` → overwrite → Recompile. Full procedure and the four traps are in §7.
   This replaces the old "re-upload four files by hand" step, which was the source of the stale
   build (47 blanks, two `?` citations). **Then read the PDF**, checking specifically: Fig 5 is the
   three-panel five-seed sweep, Figs 6b and 8b now carry different titles, no blank values, no `?`
   citations. Then send the short follow-up to Prathamesh if he has the old build.

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
   As of 2026-08-19 the two fig11 panels **say so in the figure itself** ("hull domain" in the
   supertitle) as well as in the captions, so the honesty gap is closed and this is now optional
   polish, not a defect. fig12 is not printed in the paper. Regenerating on `traj-train` would
   still be cleaner. Cost: re-point `objective3_symbolic.jl`, which also writes
   `results/symbolic/*.csv` that many macros read - verify byte-identical output before trusting
   it (it was, on a plain re-run).
7. ~~`scripts/stage_figures.ps1` does not know about fig13.~~ **DONE 2026-08-19.** fig13 and
   `fig7c_ablation_gca_5seed.png` are in the map, the two stale `fig11_*` rows that would have
   reverted the new panels are removed, the file is ASCII-only again (its line-1 em-dash was a
   latent PS 5.1 parser hazard), and the script now verifies every `\includegraphics` target is
   present before it exits.

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

Copy everything between the fences into a fresh session and fill in one line.

```
We're continuing my Advanced Hodgkin-Huxley x SciML paper. Repo:
d:\SciML\bootcamp\Research Project\HH-SciML-Project    (branch: main)

THIS SESSION I WANT TO: <FILL IN>

--- STARTUP: read before doing anything ---
1. HANDOFF.md, in this order:
     Sec 2  - THE THESIS. It CHANGED in Aug 2026 and it is counter-intuitive: the single
              trajectory DOES determine the calcium conductance (2.092 +/- 0.130 against a
              true 2.0). The flexible neural closure is what loses it. Parametric
              identifiability holds; functional identifiability fails. Never reintroduce
              "not identifiable from a single trajectory".
     Sec 3  - current numbers, AND the boxed DOMAIN RULE. Read that box carefully: four
              separate defects in Aug 2026 came from breaking it.
     Sec 9  - gotchas. Non-optional; several cost hours.
     Sec 13 - next steps. Item 0 is an Overleaf rebuild+recompile that is probably outstanding.
     Sec 7  - the Overleaf upload procedure. Use scripts/make_overleaf_zip.ps1; do NOT zip or
              drag the paper folder itself, it breaks all three relative paths.
     Sec 10-12 - project history, past mentor rulings, reproducibility notes, file schemas.
              Consult before reopening any settled decision.
2. MEMORY.md and the memory files, especially:
     parametric-fit-shows-closure-induced-nonidentifiability
     mentor-review-weakened-three-claims
     paper-draft-and-layout
3. Skim paper/main.tex. Deliverable is paper/ (main.tex, generated/metrics.{tex,json},
   claims.yaml, metrics_map.yaml, references.bib, citations-audit.md, figures/).

--- HOW THIS PAPER IS BUILT ---
- Law I: every reported number is a \val macro from paper/generated/metrics.tex, traced via
  paper/metrics_map.yaml to a results CSV. Fixed INPUTS are preamble \newcommands with a
  source comment. A few literals carry "% numok:" ON THE SAME LINE - the checker is line-based.
- Law II: every claim lives in paper/claims.yaml with scope, evidence and status, anchored in
  the prose as "% claim: <id>".
- Verify with the six commands in HANDOFF Sec 8. All six are currently green:
  286/286 macros, 0 untraceable numbers, 0 errors, 0 unsupported claims, 38 refs verified,
  tex-sanity clean. check_claims MUST get --figures-root . or it mis-resolves colliding basenames.

--- WHAT THE CHECKERS CANNOT SEE (learned the hard way) ---
- They do NOT check whether a sentence agrees with its evidence. An adversarial audit caught
  12 defects they passed over, including the Introduction stating the thesis BACKWARDS.
- They do NOT catch a "%" comment placed mid-line, which silently deletes the rest of that
  line. One shipped: a sentence began in mid-air in the compiled PDF.
- A blank value in a compiled PDF means the uploaded generated/metrics.tex is STALE, not that
  the source is broken. A "?" citation means references.bib is stale. Rebuild the whole bundle
  with scripts/make_overleaf_zip.ps1 rather than re-uploading files one at a time.
- They do NOT look at a figure. Two shipped that contradicted their own text: the sweep figure
  was single-seed while the sentence citing it claimed five, and the before/after retrain panels
  were visually identical. LOOK at every figure the paper includes after regenerating any of them.
So: after any thesis-level edit, re-run the adversarial audit AND read the compiled PDF.

--- GROUND RULES ---
- I am the committer. NO Claude co-author. Commit/push ONLY when I ask.
- NEVER commit: main.jl, Main_Clean.jl, "Paper Writing Skills/", .claude/, __pycache__/.
- HANDOFF.md is SNAPSHOT-ONLY: gitignored, archived into history via
  scripts/snapshot_handoff.ps1 (run before each push). It is NOT private - the repo is public
  and history is browsable. Do not put anything in it I would not publish.
- Evidence base is CLOSED unless I greenlight a run. The mentor's Aug 2026 review is fully done.
- I compile on Overleaf (you get 403) and paste errors back. Build my upload with
  scripts/make_overleaf_zip.ps1 - never ask me to re-upload files one at a time.
- Julia runs are long and block-buffered: use file mtimes as the progress signal, and
  run_node_baseline hangs (Sec 9).

--- WHERE THINGS STAND ---
Mentor: full reply sent 2026-08-18; a short follow-up about the faulty build may still be owed
(scratchpad draft, HANDOFF Sec 10). Awaiting his answer on the thesis lead and the venue.
Venue: Sim2Science. Its page limit is NOT recorded anywhere here - check the CFP before
planning any cut; the paper is well past 4 pages.
Open decision that is MINE, not yours: the Kainth reference reproduces arXiv's author string
"Sreedat Panat", which is probably a typo for Sreedath Panat. It is deliberate (metadata
fidelity) and documented; a reviewer suggested correcting it. Ask me, do not change it silently.
The current source has NOT been compiled since the 2026-08-19 figure round.

Give me a short status read plus your recommended first step for the goal above, and wait for
my go before editing anything.
```

### If you only read one thing
The paper argues that a UDE can forecast a hidden ionic current beautifully and still get its
conductance wrong - and that this is caused by the flexible closure, not by a shortage of data,
because a two-parameter fit to the same trajectory recovers the conductance to about six per cent.
Every control exists to close off an alternative explanation for that gap. If you find yourself
hedging that claim, read Sec 2 first: it is better supported than it sounds.
