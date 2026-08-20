# HANDOFF — Advanced Hodgkin–Huxley × SciML

> **Last updated 2026-08-19 (evening: upload round).** Restructured, not truncated. Sections 1–9 and 13–14 describe the
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

**Re-audited 2026-08-20** after the referee round rewrote large parts of the paper: all
seven still hold. Checked item by item, not assumed. Two are now *better* than when he
saw them (the citation-audit VERIFIED line names its tolerances instead of overclaiming;
the loss-normalisation disclosure now also names the objective/optimiser difference
between the two arms). Nothing regressed. The Sreedath byline and the deliberate
"Sreedat" bibliography spelling both survived the round.

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

## 4b. Referee-report round (2026-08-20) — 81 findings worked

An eight-reviewer adversarial audit of the manuscript, the pipeline and the public repo produced
81 findings (4 blockers, 19 major, 39 minor, 19 nits). Every one was **re-verified against the repo
before acting** — 71 confirmed, 5 partial, 3 refuted. 165 patches were applied, then an independent
6-auditor / 56-verifier adversarial pass over the resulting diff found 26 further real defects,
which were also fixed.

**What actually changed in the science.**
- **The objective/optimiser confound is now disclosed** (§4.4). The UDE minimises an *unweighted*
  native-units SSE by Adam+BFGS; the parametric arm minimises *noise-weighted* chi-square by
  multi-start Nelder-Mead. The old §4.4 said "two of the three quantities need a weighted
  objective", which implied the headline 2.092 came from the raw SSE — `fit_params`
  (`identifiability_parametric.jl`) minimises chi-square for **all three**, so the paper had
  misdescribed its own method. Representation, objective and optimiser co-vary; nothing here
  separates their contributions, and the paper now says so. The one-directional inference of §2
  survives untouched.
- **The retrain control now has a noise floor, from committed data.** New macro
  `ParamFitSseFullTwo` = **39.33 +/- 1.26**: the `sse_full` column of `parametric_fit.csv`, i.e.
  the UDE's own objective evaluated at the maximum-likelihood (gCa, ECa) of the TRUE structure.
  Both UDE losses (35.71 before, 29.66 after) are *below* it. A model that scores better than the
  correct physics on the data the physics generated is fitting the noise realisation. **No run was
  needed** — the column was already in the CSV. (The referee report proposed evaluating at the true
  parameters, which has no CSV; this is the same argument from committed evidence, and slightly
  more conservative.)
- **The profile interval was a grid artifact.** The scan step is 0.0625, and quoting the outermost
  grid points under the threshold inflated the interval to [1.625, 2.125]. Interpolating the
  Delta-chi2 = 3.8415 crossings gives **[1.6065, 2.1477]**, which the independent Wald interval
  corroborates at [1.6049, 2.1492]. Seed 3333's closure estimate (1.60693) is **inside** it, so
  "every one of the five falls outside" is now "four clearly outside; the fifth on the lower edge".
  This changed the abstract, and `figure_identifiability.jl` was fixed to interpolate too — it now
  independently reproduces both the interval and the 4-of-5 count.
- **`r2_vs_nn_on_domain` is now reported.** The sentence "the closure is well approximated by the
  conductance form" had been supported by `r2_vs_true_on_domain` (agreement with the TRUE current).
  The column the sentence needs was in the same CSV and appeared nowhere in the paper.
- **Six citation misattributions corrected**, incl. dropping `walch2016` from the gCa-ECa trade-off
  (its Thm 3.1 is a conductance x gating combination under *voltage clamp*, with E assumed known).
- **False statements fixed**: "all six gate ODEs" (there are five), Fig 1's "Solve [0,100] ms"
  (training solves [0,30]), "L-BFGS" x10 (the code runs full BFGS).

**Figures.** `fig13` panel (c) had its legend box sitting on the seed-2222 diamond at 2.816 — the
point that defines the upper end of the span its own caption quotes. Fixed (headroom + transparent
legend) and re-rendered; all five closure diamonds are now visible. `fig7_ablation_noise.png` is
now printed in Appendix C (the noise sweep was run, committed and figured but never mentioned).

**Bulk application is dangerous — budget for the cleanup.** Applying 165 patches by script caused
collateral damage that *every checker passed*: 9 duplicate `\newcommand` definitions (a hard LaTeX
error that would have broken the Overleaf build), a duplicated *Data and Code Availability*
section, a duplicated table row in Table 4, three duplicated prose paragraphs, a duplicated
PowerShell hashtable key (`stage_figures.ps1` would have thrown), a duplicated `[compat]` block,
and a mangled sentence fragment in Limitations that would have shipped as visible garbage. The
lesson: **after any bulk apply, scan for repeated blocks and duplicate `\newcommand` names before
trusting the checkers.**

**Not done — these are yours (see §13).** LICENCE and the repo URL / Zenodo DOI (placeholders are
in the paper and the README, deliberately, and marked TODO); whether Sim2Science is double-blind,
which decides whether the repo URL and the author block may appear at all; the git-history question
(`HANDOFF.md` snapshots, `Vizuara_Paper_HH.pdf`); `M9` (the rollout horizon returns the 70 ms cap
inside a 49.9 ms window — fixing it edits `src/metrics.jl` and regenerates a committed CSV, so it
needs your greenlight); `M6` (six figures print at ~3 pt); and `gNaP = 0.5`, which needs the
Golomb & Amitai primary source you may have institutional access to.

## 4c. Metric fix + figure legibility round (2026-08-20, greenlit)

### The rollout horizon was measuring past the end of the data (referee M9)

`rollout_horizon` returned `cap_ms` (70.0) whenever the forecast never left the
tube, **with no check on how much trajectory remained**. On the common-evaluation
window the first scored sample is at 50.098 ms and the trace ends at 100 ms, so only
49.902 ms exists to be measured -- a horizon 40% longer than the window it was
measured in, plotted as a flat line in the paper's Fig. 8a. The forecast window was
affected too but only cosmetically (its ceiling is 69.863, not 70.0).

**Fixed in `src/metrics.jl`**: the horizon is now clamped to `min(cap_ms, t[end] - t_start)`
at both exits. A value equal to that bound still means "never breached" -- report it
with `>=`, per the censoring guard.

**No retrain was needed, and none was done.** The bug was in the metric, not the model,
and the weights for all five window settings were saved. `recover_rollout_censoring.jl`
(new, same idiom as the other `recover_*.jl` scripts) reloads each network, re-solves the
same span with the same solver and tolerances, and re-measures with the corrected
function into `results/identifiability/rollout_censoring.csv`. **Its self-test compared
150 other metrics against `ablation_window.csv` and found a worst relative disagreement
of exactly 0**, so the only thing that moved is the metric we deliberately fixed.
`results/metrics_all.csv` and `results/ablation_window.csv` were NOT touched -- appending
there would change the inputs of already-published macros.

Corrected horizons (ms), forecast / common-eval, against 70.0 / 70.0 before:

| t_train_end | forecast | common-eval |
|---|---|---|
| 15 | 70.000 | 49.902 |
| 20 | 70.000 | 49.902 |
| 30 | 69.863 | 49.902 |
| 40 | 59.883 | 49.902 |
| 50 | 49.902 | 49.902 |

The forecast column is the more interesting one: it was flat at 70 only because the
metric ignored the available data. It actually tracks the window that remains. The
scientific conclusion is unchanged (the UDE never breaches anywhere), but it is now
stated as censoring rather than as a measured duration.

### Figure legibility (referee M6)

The governing arithmetic, worth writing down because it was got wrong twice:

> a font of size `f` on a canvas `W` px wide, placed at a fraction `p` of the 6.5 in
> text width, prints at **`f * p * 6.5 * 72 / W`** pt, and the figure resolves at
> **`W / (p * 6.5)`** DPI.

Six figures printed at roughly 3 pt against 10 pt body text. **Half width cannot be
rescued by fonts alone**: three stacked panels at `p = 0.49` need `f ~ 30`, and at that
size titles run off the canvas and y-tick labels collide (tried it; the first attempt
was unreadable in a new way). The fix is to widen the placement AND size the canvas for
it.

| figure | before | now | how |
|---|---|---|---|
| `fig7b_commoneval_ablation_window` | 960 px @ 0.49, ~3 pt, 301 DPI | 1950 px @ 1.0, 7.2 pt, 300 DPI | new `figure_commoneval_window.jl` (plotting only, reads the corrected CSV) |
| `fig11_coeff_recovery_before/after` | 1500 px @ 0.54/0.62, ~2.9 pt | 1950 px @ 1.0, 6.7 pt, 300 DPI | `figure_coeff_recovery_panels.jl` fonts + margins |
| `fig9_symbolic_parity_before` | 600 px @ 0.44, ~3.8 pt, 210 DPI | 1250 px @ 0.62, 7.0 pt, 310 DPI | `objective3_symbolic.jl` |
| `fig2_neural_ode_overview` | 950 px @ 0.49, ~3.0 pt | 950 px @ 1.0, ~5.4 pt, 146 DPI | LaTeX placement only -- **see below** |
| `fig3_ude_overview` | as above | as above | LaTeX placement only |

**Re-running `objective3_symbolic.jl` is safe** -- confirmed again this round: all three
of its CSVs came back byte-identical (md5) after the font change. Snapshot the md5s
before and check them after; do not skip that.

**`fig2` cannot be re-rendered without retraining.** `results/params/` holds only
`ude_*.jld`; no neural-ODE weights were ever saved, so `regen_fig2.jl` *retrains* the
NODE. Since fig2 and fig3 are a matched pair shown on the same axes, re-rendering fig3
alone would make them visually inconsistent. Both were therefore widened in LaTeX only.
They are the one remaining legibility compromise: readable (~5.4 pt) but 146 DPI. Fixing
them properly needs a NODE retrain, which is a decision, not a chore.

**Figure layout changed** as a consequence -- four subfigure pairs became eight
standalone figures (`fig:parity` and `fig:symbolic`; `fig:node-vs-ude` and
`fig:ude-overview`; `fig:appendix` and `fig:appendix-retrain`). Every `(a)`/`(b)`
sub-reference in the prose was repointed. **This makes the paper longer** -- check it
against the venue's page limit before submission.

### gNaP = 0.5 (referee M8) -- resolved as a labelling fix, not a citation

Golomb & Amitai 1997 is closed access with no repository copy, so the printed value
still has not been checked. What was wrong was that the repo stated it at three
different strengths: Table 1 cited it outright, the prose called it a "conductance
range", and the code comment said "range". All four sites (Table 1, the two prose sites,
`src/hh_core.jl`) now agree on the weakest defensible claim: **it is our choice**, of the
same order as that model family once rescaled to our sodium conductance, and Appendix A
says so and says nothing depends on it (it is a ground-truth constant supplied
identically to the data, the closure and the parametric fit, so it cancels from every
comparison). If you later get the primary source and the value checks out, the honest
upgrade is to restore the citation in all four places at once.

### Fig 13(b) legend -- fixed by deletion, and here is why

The legend drew the dashed threshold with a key that read solid and the dotted truth
line with a key that read dashed. This is **not** a styling bug to chase: a legend key is
only a few tens of pixels long, too short to render a dash or dot pattern faithfully at
these line widths, so *any* key for those two lines will misdescribe them. Both labels
were dropped and the caption now names both lines. The same limitation still applies to
the `y = x` key in fig9 -- left alone there because it is the only black line in the
panel, so the key cannot be confused for another series.

## 4d. The objective confound is now MEASURED, not disclosed (2026-08-20, greenlit)

`parametric_matched_objective.jl` (new) closes the biggest remaining referee attack surface.
It repeats the **identical** two-parameter fit -- same data, same true functional form, same
two free parameters, same three Nelder-Mead starts, same solver and tolerances -- and changes
exactly one thing: which reduction of the residual it minimises. No training, no network.

| gCa | weighted chi-square | unweighted SSE (the UDE's own) |
|---|---|---|
| 0.4 | 0.438 +/- 0.065 (14.9%) | 0.634 +/- 0.236 (37.3%) |
| 1.0 | 1.043 +/- 0.084 (8.1%) | 1.245 +/- 0.329 (26.4%) |
| **2.0** | **2.092 +/- 0.130 (6.2%)** | **2.478 +/- 0.489 (19.7%)** |
| 4.0 | 4.105 +/- 0.120 (2.9%) | 4.553 +/- 0.588 (12.9%) |

**Self-test: the chi-square row reproduces `parametric_fit.csv` with worst relative
disagreement exactly 0 over 60 comparisons**, so the harness is identical and the objective is
provably the only variable. The script exits non-zero if that ever stops holding.

**The licensed decomposition, at gCa = 2.0:** objective ~3.2x (6.2 -> 19.7%), representation
~2.1x (19.7 -> 40.9%). **Quote the twofold figure for the representation. Never the sixfold
ratio** -- that is the two compounded, and it is what the paper used to imply was pure
representation. Macro `ParamFitGcaHatTwoSseFull`; the claim ledger entry for
`closure-induced-nonidentifiability` carries the decomposition and forbids the old phrasing.

Two things fall out for free. `sse_v` agrees with `sse_full` to three decimals at every
setting, which independently corroborates `LossShareV` (99.97% voltage) from a completely
different direction. And the effect is monotone in gCa in both columns, so it is not an
artefact of the headline setting.

**What changed in the prose:** Sec 4.4 now says the control was RUN rather than that nothing
separates the contributions; the Results passage states the decomposition; the abstract and the
contributions bullet both quote the twofold figure. The one-directional inference is untouched
and is still the load-bearing part of the argument.

### Licences chosen (2026-08-20)

**MIT for the software, CC BY 4.0 for the evidence.** Both files exist
(`LICENSE`, `LICENSE-DATA`), so the abstract's release sentence is no longer empty --
until they existed, default copyright applied and nothing in the public repo was
legally reusable. MIT because it is the shortest thing that works and matches the
Julia/SciML ecosystem; CC BY 4.0 because the evidence is what a reader would reuse and
attribution is the only condition worth attaching.

Two files are carved out in `LICENSE` and named in the paper, because they are not ours
to relicense: `paper/arxiv.sty` (vendored, upstream MIT, provenance stamped in its
header) and `Vizuara_Paper_HH.pdf` (third-party publication, all rights reserved).

**A licence change is a THREE-place edit:** `LICENSE`/`LICENSE-DATA`, `README.md`, and
the Data and Code Availability sentence in `main.tex`. The comment block above that
sentence says so.

Law I note: "4.0" carries digits, so the sentence needed a `% numok:` naming
`LICENSE-DATA`. Any DOI or commit SHA substituted later will need the same treatment,
appended at the TRUE END of the line.

### Also decided this round

- **fig2 / fig3 stay at 146 DPI. Do not retrain the NODE for them.** They are readable
  (~5.4 pt after the widening; they were ~3.0 pt). The only way to raise their resolution is
  `regen_fig2.jl`, which *retrains* the neural ODE -- no NODE weights were ever saved, only
  `ude_*.jld`. That is a training run on the documented hang-prone path, and if it did not
  reproduce the published trajectory bit-for-bit the figure would contradict Table 2, which is
  a worse defect than low DPI. The legibility problem is fixed; the DPI note is cosmetic.
- **No separate follow-up to the mentor** about the superseded [1.63, 2.13] interval. Vinayak
  sends him the corrected draft directly instead.
- **Venue questions deferred** until the draft is final -- but three of them gate other work.
  See NEXT STEPS.

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

### Uploading to Overleaf — the procedure, and why the obvious ones fail
```
powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1
```
That writes **two** artifacts, and picking the wrong one wastes a cycle:

| artifact | use it for | what happens otherwise |
|---|---|---|
| `overleaf_upload/` | **the normal case.** Open it, select all four items (`main.tex`, `references.bib`, `figures`, `generated`) and **drag them onto the existing project's file tree**. Overleaf merges the folders and asks before overwriting. | — |
| `overleaf_upload.zip` | **only** `New Project → Upload Project`, which extracts it into a **brand-new** project | Uploading it *into* an existing project **does not extract it**. It sits in the file tree as a binary blob and nothing compiles. Confirmed 2026-08-19. |

Prefer the folder. A new project gets a new URL, loses the collaborators and comments, and
**has no `arxiv.sty`** — so it cannot compile until that file is copied in by hand.

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
- **`arxiv.sty` is VENDORED at `paper/arxiv.sty`** (2026-08-19) and ships in both artifacts, so
  the bundle is self-contained and a brand-new Overleaf project compiles from it unaided.
  It is not a CTAN package — no package manager will ever install it and Overleaf cannot supply
  it — so `\usepackage{arxiv}` fails on line 3 of `main.tex` without a local copy. This was NOT
  a hypothetical: the belief that the live Overleaf project already contained it was simply
  **wrong**, and `LaTeX Error: File 'arxiv.sty' not found` is what the first successful upload
  produced. Provenance, licence (MIT) and the body md5 are stamped in the file's own header;
  re-fetch from the URL there rather than hand-patching it.
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
python scripts/check_bib_sanity.py
python scripts/check_provenance_refs.py
```
Current state (2026-08-20): **all eight green — extract_metrics 316/316 macros match disk · check_numbers OK (163 numbers, 0 flagged, 49 numok exemptions) · check_claims 0 errors, 0 unsupported (32 claims: 4 retired, 28 supported; the 10 duplicate-anchor warnings are legal) · lint_prose clean · verify_references 38 refs, 36 verified, 2 review, 0 unresolved · tex_sanity clean · bib_sanity clean (38 entries, 38 unique keys) · check_provenance_refs 158 pointers, 0 past end of file.** `doctor.py` reports 3 FAILs; those are the broken local MiKTeX and are expected — compilation is Overleaf-only.

`check_bib_sanity.py` (added 2026-08-19) is the seventh, and it exists for the same reason as the
sixth: a defect nothing else could see reached a build. **`%` is not a comment character in a
`.bib` file.** BibTeX ignores text between entries but still scans it for at-signs, so writing a
type name with one in a "comment" opens a bogus entry and the parse dies with ``I was expecting
a `{' or a `('``. A comment explaining the entry types did exactly that. The checker also does
**statically** what has twice been diagnosed only after an upload: it reports every `\cite` key
with no matching entry, which is what a `?` in the PDF means. Run it before every upload.
It caught a second at-sign in its own warning text on its first run — `--selftest` covers the
three cases (stray at-sign, legitimate at-sign inside a field, duplicate key).

`check_provenance_refs.py` (added 2026-08-20) is the **eighth**, and it exists because the same
defect has now shipped twice. Law I asks every fixed INPUT and every ledger note to name the source
line it came from, and those pointers are plain text that nothing keeps honest: any edit that
inserts lines above a cited line silently invalidates every pointer below it. The Aug-2026 round
found seven pointers into `src/experiment.jl` drifted by +16 and fixed them; the **next** round
inserted the `HH_SMOKE` isolation block into the same file and drifted **63** pointers again, this
time by +28 (and `experiments_runner.jl` by +12). A stale pointer is worse than a missing one - it
lands the reader on real code and looks authoritative. The checker FAILs on a pointer past end of
file and WARNs when a cited line is blank or a bare `end` (usually drift; legitimate when it is the
closing line of a cited range). **Run it after any edit that adds or removes lines in a `.jl` file.**
Prefer citing a stable anchor - a function name, a LaTeX label - over a line number.

**`check_claims.py` MUST be run with `--figures-root .`** (repo root). With any other root its
basename fallback silently resolves `results/retrain_gca2_20k/figures/fig11_*.png` to the
*baseline's* file of the same name — the collision is documented at the top of `claims.yaml`.

**Two BibTeX warnings are EXPECTED and must not be "fixed":** `entry type for "pal2023lux"`
and `"dixit2023optimization" isn't style-file defined`. `unsrtnat.bst` has no `software` type,
so BibTeX formats both with its default type, `misc` — which is already what they render as, and
the pinned version reaches print through `note`. Retyping them `@misc` would silence the warning
with byte-identical output, but `scripts/verify_references.py:256` keys on `type == "software"`
to enforce that software records carry a `version`. The reasoning is written into
`references.bib` above the entries.

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
- **A `%` in a `.bib` file protects nothing.** It is a LaTeX convention; BibTeX has no comment
  syntax and scans between-entry text for at-signs, so one inside a "comment" starts a bogus
  entry and the whole bibliography fails to parse. Never write an entry type with its at-sign in
  `references.bib` prose. `scripts/check_bib_sanity.py` fails the build on it.
- **A stale uploaded `generated/metrics.tex` fails in TWO different ways, and the second one is
  what you will actually see.** Both mean the same thing: Overleaf kept the metrics file it already
  had, so every macro added since the last upload is undefined. It is never a source bug.
  1. *Blank values in the PDF*, compile otherwise clean. This is the older symptom.
  2. **`Undefined control sequence`, once per USE, pointing at the PROSE.** This is what happened
     on 2026-08-20: 18 errors across 9 sections, none of which named the missing file. Errors
     inside a `\caption` are all reported at the caption's closing brace, so a line that contains
     no macro at all gets blamed - `main.tex:2039` was `spread.}`.
  **Diagnose in one step:** take the erroring line numbers, look up which `\val` macros they use,
  and check those against `git diff` of `paper/generated/metrics.tex`. If they are all new, the
  upload was partial. There is now a **canary guard** in `main.tex` right after
  `\input{generated/metrics}` that turns this into one legible error naming the fix; keep it
  pointed at a recently-added macro, and `scripts/check_tex_sanity.py` fails if it names a macro
  that does not exist.
  **The fix is always the same: drag ALL FIVE items across, not just `main.tex`.** A `?` in place
  of a citation is the same class of problem in `references.bib`.
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
  the reversal of the paper's thesis.
  **Awaiting his response**; the two questions put to him were whether the reversed thesis is the
  right story to lead with, and the venue.

  > **WARNING about the draft paths this section used to give.** They were
  > `scratchpad/email_prathamesh*.md`, which is **not in the repo** - it is the assistant's
  > per-session temp directory, and it is gone the moment the session ends. Both drafts were
  > recovered on 2026-08-19 only because that session was still alive. **Never record a decision
  > or a deliverable as "it's in scratchpad".** Either put it in this file or paste it into the
  > mail client immediately. The authoritative copy of the sent email is Vinayak's Sent folder;
  > it is deliberately NOT archived here, because this file is published through git history
  > and a personal message to a collaborator is not ours to publish. The audit below records
  > everything about it that a future session actually needs.

  **THE SENT EMAIL RE-AUDITED, 2026-08-19.** Every number in it still matches the repo - no
  experiment has been re-run since, and `extract_metrics --check` still reports 286/286 macros
  matching disk. Checked individually and all confirmed: `gCa = 2.092 +/- 0.130` (+/-6.2%),
  chi2/pt `0.994`, GN relative SE `6.7%`, UDE+symbolic `1.645 +/- 0.672`, losses
  `35.71 +/- 1.81 -> 29.66 +/- 2.66` (17% reduction), the sweep `0.724/0.312/0.140/0.093` with
  only `1.0->2.0` clearing 2 pooled SD, NODE `0.548 -> 0.431 -> 19.53` and `0.245` vs median
  `16.9`, `99.97%`, hull-vs-domain range `1.36-1.65`, 38 refs / 36 verified / 2 flagged.
  It also already contains the correct retraction of the "normalised error exceeds one at the
  physiological value" claim, which the 2026-08-19 round then purged from the guard files too.

  **THREE THINGS IN IT ARE NOW BEHIND THE PAPER** (updated 2026-08-20; it was one).
  Vinayak decided on 2026-08-20 NOT to send a correction email and to send the corrected
  draft instead - so these are the points to name in the covering note, not a separate
  erratum.

  1. **The interval itself moved.** The email quotes `[1.63, 2.13]`. That was the outermost
     GRID POINTS under the threshold on an 0.0625-step scan. Interpolating the crossings
     gives `[1.6065, 2.1477]` (the independent Wald interval agrees at `[1.6049, 2.1492]`).
  2. **"All five fall outside" is now FALSE.** It was true against the coarse bracket -
     traj-train values `1.241, 2.816, 1.607, 1.318, 1.242` all sit outside `[1.63, 2.13]`.
     Against the resolved interval, seed 3333 at `1.6069` is INSIDE, by `0.0004`. The paper
     now says "four of the five fall clearly outside; the fifth sits on its lower edge".
  3. **The headline ratio is decomposed and the representation's share is SMALLER.** The
     email presents the parametric-vs-closure gap as a representation effect. It is not
     purely that: `parametric_matched_objective.jl` now measures the same fit under the
     closure's own objective and gets `2.478 +/- 0.489` (19.7%) against `2.092 +/- 0.130`
     (6.2%). Objective ~3.2x, representation ~2.1x. **The mentor was told a sixfold
     representation effect; the paper now claims about twofold.** This is the one that
     changes what he was told, not just how precisely.

  Also still true and still worth saying: the interval belongs to the **representative seed
  alone**, and that seed's estimate is the LOWEST of the five, so three of the other
  parametric seeds sit above its upper edge. Quote the pooled `2.092 +/- 0.130` for the
  ensemble. The direction of every conclusion he was given is unchanged; the magnitudes and
  one count are not.

  **A follow-up is owed, and the gap has widened.** The PDF built at the time of the email came
  from a STALE Overleaf upload: 47 blank values, two `?` citations, a missing Kainth paragraph,
  and a sentence starting mid-air. Since then the paper has ALSO gained the round-3 text fixes,
  a replaced Fig 5, relabelled Figs 6b/8b and a re-fitted Table 2. If he was sent or pointed at
  that build, he is now several rounds behind: send the corrected PDF.

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

### The upload round (2026-08-19, evening) - four failures, none of them the paper
Getting a compiled PDF took four attempts. Every failure was in the *delivery*, and each is now
either automated away or guarded, so none should recur:
1. **Zip uploaded into the project, never extracted.** Overleaf only extracts a zip via
   `New Project -> Upload Project`; uploading one *into* a project stores it as a binary file.
   Fix: the bundler now also emits a drag-ready `overleaf_upload/` folder (§7).
2. **`arxiv.sty` not found.** The standing assumption that the live project contained it was
   simply **wrong**. Fix: vendored at `paper/arxiv.sty`, MIT, provenance stamped in its header,
   shipped in every bundle. The build now has no external file dependency.
3. **BibTeX parse death**, self-inflicted, from a comment added the commit before: `%` protects
   nothing in a `.bib`, and the at-signs in `@misc`/`@software` written as prose opened bogus
   entries. Fix: `scripts/check_bib_sanity.py`, which also statically finds unresolved `\cite`
   keys - the `?`-in-the-PDF diagnosis, moved to before the upload instead of after.
4. **Table 2 overfull by 24.4pt.** Fix: `\small` + `tabcolsep 5pt`, scoped to that table.

The lesson worth keeping: **the checkers verify the paper, not the delivery.** Six green checkers
sat alongside a bundle that could not compile. Anything on the path from repo to PDF needs its
own guard, which is why the bundler and the staging script now both self-verify.

### Commit chain
`cc4f80d` (train/forecast metrics, voltage-only, ablations) → `ee3b7f9` (multi-seed + common-eval +
calcium probes) → `38d7d4b` (Obj-2 figure legibility) → `2b5244c` (Objective 3 symbolic recovery) →
`c9614e0` (Obj-3 figure legibility) → `f3148b1` (aggressive retrain at gCa=2.0) → `96edf16` (paper
scaffold) → `310855c` (full prose draft) → `a38745f` (2026-08-16, mentor review + thesis change) →
`8eede75` (comment-swallowed prose + domain-number alignment) → `94e2fd8` (control-byte repair +
tex-sanity guard) → `12b1b3c` (five-seed Fig 5, relabelled Figs 6b/8b, staging-script repair,
Overleaf bundler) → `ca68f47` (drag-ready folder) → `2ab55bb` (vendored `arxiv.sty`) →
**`fb1a7db`** (BibTeX repair + `check_bib_sanity.py` + Table 2 width). Snapshot/remove HANDOFF
pairs are interleaved throughout; ignore them when reading the chain. No SHA here is the tip:
run `git log --oneline -8`.

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
0. **Rebuild, upload, and READ THE COMPILED PDF.** This is still open and it is still the
   gate everything else waits behind: nobody has read a PDF of the current source, and the
   source has changed enormously since the last build.
   `powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1`, then open
   `overleaf_upload\`, select **all five items** (`main.tex`, `references.bib`, `arxiv.sty`,
   `figures`, `generated`) and **drag them onto the existing project's file tree**; overwrite;
   Recompile. **Do not upload the .zip into the project** — it does not extract. Full
   procedure and every trap in the Files section.

   The bundle is built and verified byte-identical to `paper/` (16 files, 11 figures).
   Check, specifically:
   - **Length.** The figure layout changed: four subfigure pairs became eight standalone
     figures, several now full-width. The paper got longer. Read the page count first,
     against the venue limit.
   - no blank values anywhere (a blank = stale `generated/metrics.tex`);
   - no `?` citations (`check_bib_sanity.py` says there should be none);
   - the five `TODO-` placeholders in Data and Code Availability are still placeholders —
     they are deliberate, but they must not reach a submission;
   - Table 2 sits inside the margins.
   Expected and NOT to be "fixed": two BibTeX `entry type ... isn't style-file defined`
   warnings, several `Underfull \vbox` messages, one `Underfull \hbox` in `output.bbl`.


### Waiting on someone else
1. **Prathamesh's reply.** Two questions were put to him: whether the reversed thesis (§2) is the
   right story to lead with, and the venue. Do not restructure the argument until he answers - if he
   disagrees with the lead, the fix is presentational, not experimental.

### VINAYAK'S TODO LIST — owned by him, deferred deliberately (as of 2026-08-21)

Nothing below is blocked on analysis; every item is a decision or an errand. They are
ordered so that each one's prerequisite comes before it.

| # | Do this | Waits on | Notes |
|---|---|---|---|
| T1 | **Read the compiled PDF.** Drag **all five** items from `overleaf_upload/` onto the Overleaf file tree: `main.tex`, `references.bib`, `arxiv.sty`, `figures`, `generated`. | nothing | Dragging fewer is what caused the 2026-08-20 build failure. A canary in `main.tex` now catches it with one legible error. |
| T2 | **Check the Sim2Science CFP**: page limit, format, archival status, and **double-blind or not**. | nothing | Double-blind is the consequential one — see T4 and the note below. |
| T3 | **Cut to length** once the limit is known. | T2 | If short-format, what must survive is the parametric result and the NODE architecture attribution; the window/noise ablations and the appendix are the first cuts. The 2026-08-20 figure round made the paper longer. |
| T4 | **Create the fresh repo** (item 13 below): copy files into a new `git init`, never clone. | T2 | If the venue is double-blind, the repo cannot be linked from the paper at all until after acceptance. |
| T5 | Fill **`TODO-REPOSITORY-URL`** (`main.tex:248` and in Data and Code Availability). | T2, T4 | |
| T6 | Fill **`TODO-ARCHIVE-DOI`**: tag a release, deposit to Zenodo, paste the DOI. | T4 | |
| T7 | Fill **`TODO-COMMIT-SHA`** — **LAST**, after the source is frozen. | T5, T6 | It must be the commit the reported numbers actually came from. |
| T8 | Fill the `[TODO - AUTHOR]` citation block at **`README.md:283`**. | T6 | Needs the DOI. |

**Law I applies to T5–T7.** A URL, a DOI and a commit SHA all contain digits, and
`check_numbers.py` is line-based. After substituting, append a `% numok:` at the TRUE END
of every line that then carries a digit — mid-line, it silently deletes the rest of the
line.

**Settled 2026-08-21, do not reopen without reason:**
- **Copyright holder** stays "Vinayak Mokashi and the HH-SciML-Project authors" in
  `LICENSE`/`LICENSE-DATA`. It does not appear in the paper, so there is nothing to decide
  there.
- **The Acknowledgements section was removed.** Prathamesh is a co-author, so thanking him
  for reviewing duplicates his authorship, and a double-blind venue would require its
  removal anyway. It is in git history if the venue turns out to be single-blind and you
  want it back.
- **fig2 / fig3 stay at 146 DPI.** Readable; raising it needs a NODE retrain that could
  contradict Table 2.
- **No correction email to the mentor.** The corrected draft goes to him directly.


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

8. ~~Get `arxiv.sty` into the repo.~~ **DONE 2026-08-19**, and it turned out to be load-bearing
   rather than tidy-up: the Overleaf project did **not** contain the file, so the first upload
   failed with `File 'arxiv.sty' not found`. Fetched from `kourgeorge/arxiv-style` (MIT),
   stamped with source/date/licence/md5, committed at `paper/arxiv.sty`, and added to the
   bundler. The build now has **no** external file dependency.

### Routine
9. **Snapshot HANDOFF.md before each push:**
   `powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1 -Push`
   It is gitignored, so it is only archived when you do this deliberately.

### Decided, not yet done
13. **Publish from a BRAND-NEW repository** (decided 2026-08-20). Rather than rewrite this
    repo's history, the finished paper gets a fresh repo and this one is kept as-is.
    **The trap: `git clone` carries the old history. Build it by COPYING FILES into a fresh
    `git init`, and do not copy `.git/`.**
    Must come across, because the numbers trace to it: `results/` (all CSVs and the `.jld`
    parameter snapshots), `paper/`, `figures/`, `src/`, the root `.jl` entry points,
    `scripts/`, `Project.toml`, `Manifest.toml`, `README.md`, and a `LICENSE`.
    Must NOT: `main.jl`, `Main_Clean.jl`, `Paper Writing Skills/`, `.claude/`,
    `__pycache__/`, `overleaf_upload/`, `overleaf_upload.zip`, `HANDOFF.md`, and
    `Vizuara_Paper_HH.pdf` (4.8 MB third-party PDF, redistributed with no licence).
    Why: 24 commits here touch `HANDOFF.md`, which carries a private Overleaf project URL,
    unpublished venue strategy and verbatim mentor quotes. (The often-repeated "colleague's
    email" worry is a non-issue: `sreedath@vizuara.com` is a byline email in the paper.)

### Deferred, with reasons
10. **Closure-ladder experiment** - a ladder of intermediate closures between 2 parameters and the
   full network, to find where identifiability is lost. Named in Limitations as the next experiment.
   Deliberately NOT run: a follow-up paper's worth of work, and the current contribution is complete
   without it.
11. **Multiple-trajectory positive control** - whether more trajectories restore identifiability
    *through the closure*. Also named in Limitations.
12. **Multiple-shooting / curriculum horizon** - would smooth the window-ablation non-monotonicity.
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
              "not identifiable from a single trajectory" - claims.yaml marks it retired.
     Sec 3  - current numbers, AND the boxed DOMAIN RULE. Read that box carefully: four
              separate defects in Aug 2026 came from breaking it.
     Sec 7  - the Overleaf upload procedure and its table of traps. Non-obvious and it
              cost four failed attempts on 2026-08-19.
     Sec 9  - gotchas. Non-optional; several cost hours.
     Sec 13 - next steps. Item 0 is "read the compiled PDF" and is probably still open.
     Sec 10-12 - project history, past mentor rulings, the three external review passes,
              the upload round, reproducibility notes, file schemas. Consult before
              reopening any settled decision.
2. MEMORY.md and the memory files, especially:
     parametric-fit-shows-closure-induced-nonidentifiability
     mentor-review-weakened-three-claims
     paper-draft-and-layout
3. Skim paper/main.tex. Deliverable is paper/ (main.tex, arxiv.sty, references.bib,
   generated/metrics.{tex,json}, claims.yaml, claim-guards.md, metrics_map.yaml,
   citations-audit.md, figures/).

--- HOW THIS PAPER IS BUILT ---
- Law I: every reported number is a \val macro from paper/generated/metrics.tex, traced via
  paper/metrics_map.yaml to a results CSV. Fixed INPUTS are preamble \newcommands with a
  source comment. A few literals carry "% numok:" ON THE SAME LINE - the checker is line-based.
- Law II: every claim lives in paper/claims.yaml with scope, evidence and status, anchored in
  the prose as "% claim: <id>".
- Verify with the SEVEN commands in HANDOFF Sec 8. All seven are currently green:
  286/286 macros match disk, 147 numbers 0 flagged, 0 claim errors, prose clean,
  38 refs (36 verified, 2 benign), tex-sanity clean, bib-sanity clean.
  check_claims MUST get --figures-root . or it mis-resolves colliding basenames.

--- WHAT THE CHECKERS CANNOT SEE (each learned the hard way) ---
- They do NOT check whether a sentence agrees with its evidence. An adversarial audit caught
  12 defects they passed over, including the Introduction stating the thesis BACKWARDS.
- They do NOT look at a figure. Two shipped that contradicted their own text: the sweep figure
  was single-seed while the sentence citing it claimed five, and the before/after retrain
  panels were visually identical. LOOK at every figure after regenerating any of them.
- They do NOT check the DELIVERY. Six green checkers once sat alongside a bundle that could
  not compile at all. Everything between the repo and the PDF needs its own guard.
- A blank value in a compiled PDF means the uploaded generated/metrics.tex is STALE, not that
  the source is broken. A "?" citation means references.bib is stale - and check_bib_sanity.py
  now finds that one statically, before the upload.

--- GROUND RULES ---
- I am the committer. NO Claude co-author. Commit/push ONLY when I ask.
- NEVER commit: main.jl, Main_Clean.jl, "Paper Writing Skills/", .claude/, __pycache__/,
  overleaf_upload/, overleaf_upload.zip.
- HANDOFF.md is SNAPSHOT-ONLY: gitignored, archived into history via
  scripts/snapshot_handoff.ps1 (run before each push). It is NOT private - the repo is public
  and history is browsable. Do not put anything in it I would not publish.
- NEVER write LaTeX through a shell heredoc. Backslashes get eaten in transit and the result
  is valid TeX that typesets garbage. Use a patch file written directly to disk.
- Never write an at-sign in a .bib comment: "%" means nothing to BibTeX and it will try to
  parse the line as an entry.
- Evidence base is CLOSED unless I greenlight a run. The mentor's Aug 2026 review is fully done.
- I compile on Overleaf (you get 403) and paste errors back. Build my upload with
  scripts/make_overleaf_zip.ps1 and tell me to DRAG the overleaf_upload/ folder contents onto
  the file tree. Never tell me to upload the .zip into the existing project - it never extracts.
- Julia runs are long and block-buffered: use file mtimes as the progress signal, and
  run_node_baseline hangs (Sec 9).
- Do not record anything important as "it's in scratchpad" - that directory dies with the
  session. It belongs in HANDOFF.md or in my inbox.

--- WHERE THINGS STAND ---
Mentor: full reply sent 2026-08-18. Every number in it still matches the repo (re-audited
2026-08-19), but THREE things in it are now behind the paper - see the email record in the
project-history section for the exact wording. In short: the profile interval moved from
[1.63, 2.13] to [1.6065, 2.1477] (the old one was the coarse grid bracket); "all five closure
estimates fall outside it" is now four of five; and the parametric-vs-closure gap is no longer
presented as a pure representation effect - the objective accounts for ~3.2x of it and the
representation for ~2.1x, so HE WAS TOLD SIXFOLD AND THE PAPER NOW SAYS ABOUT TWOFOLD.
Decision 2026-08-20: NO separate correction email. Vinayak sends the corrected draft directly
and names these in the covering note. Every conclusion's DIRECTION is unchanged.
Still awaiting his answer on the thesis lead and the venue.
Venue: Sim2Science. Page limit, format, archival status and DOUBLE-BLIND status are all still
unchecked - deliberately deferred until the draft is final. Double-blind is the consequential
one: it decides whether the repo URL, the author block and the acknowledgement may appear.
The paper is well past 4 pages and the figure round made it longer.
Open decision that is MINE, not yours: the Kainth reference reproduces arXiv's author string
"Sreedat Panat", probably a typo for Sreedath Panat. It is deliberate (metadata fidelity) and
documented; a reviewer suggested correcting it, and note the sent email already told Prathamesh
"Sreedath's name" was fixed - so this looks inconsistent from outside. Ask me; do not change it
silently.
Nobody has yet read a compiled PDF of the current source.

Give me a short status read plus your recommended first step for the goal above, and wait for
my go before editing anything.
```

### If you only read one thing
The paper argues that a UDE can forecast a hidden ionic current beautifully and still get its
conductance wrong - and that this is caused by the flexible closure, not by a shortage of data,
because a two-parameter fit to the same trajectory recovers the conductance to about six per cent.
Every control exists to close off an alternative explanation for that gap. If you find yourself
hedging that claim, read Sec 2 first: it is better supported than it sounds.
