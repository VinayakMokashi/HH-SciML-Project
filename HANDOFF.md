# HANDOFF — Advanced Hodgkin–Huxley × SciML

> ## START HERE, 2026-08-26 (evening)
> **§4l is the live section. Read it first.** The framing question is CLOSED — option (C),
> an audit of the two-stage predict-then-interpret recipe — and §4l records why option (A)
> was drafted in full and then abandoned. Do not reopen N0 without reading it.
>
> **The 5-page paper is drafted, compiled, and fits inside five pages.** All ELEVEN checkers
> are green on both manuscripts and `sim2science_upload/` is built and anonymity-verified.
> **Only N9 and N10 remain, and neither is analysis:** send the draft to Prathamesh, then
> nominate him and submit.
>
> **§4k — the mentor's video — is HISTORY now, not a to-do list.** It is still worth reading
> for context, but **two of its premises are wrong** and §4l says which and why.
>
> **Deadline: 30 Aug 17:29 IST (= 29 Aug 23:59 AoE).**
>
> Note the §4x sections run NEWEST FIRST: 4l (the N0 decision) → 4k (mentor video) → 4j
> (figure audit) → 4i (prose audit) → 4h (venue) → 4g…4b. §4–4g are chronological history.
> The 5-page draft was **deleted on purpose** on 2026-08-26 and is being rewritten from
> scratch; recover the old one with `git show bfc8768:paper/sim2science/main.tex`.

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

> **STOP. As of 2026-08-26 the FRAMING below is contested and the decision is open — see
> §4k.** The mentor is against building the whole paper around the reverse claim, on
> positional grounds (it reads as Vizuara house style), and says that if we keep it, the
> title and the entire flow must change. He explicitly left the call to Vinayak.
>
> **NOTHING IN THIS SECTION IS RETRACTED. Every number and every inference below still
> stands and is still verified.** What is open is whether this is the paper's organising
> claim or one of its sections. Do not edit this section in response to §4k; read both.

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

## 4e. Final line-by-line audit (2026-08-21)

18 auditors: 8 prose regions covering all 2092 lines, 4 tables cell-by-cell against their
CSVs, and 6 figure agents that VIEWED each of the 11 printed images. 133 candidates, each
handed to a separate agent told to refute it. **27 confirmed, 38 refuted, 68 unverified**
(their verifiers died on a session limit -- see below). All 27 confirmed are FIXED.

**Three were blockers, and all three were the same species: a sentence contradicting the
paper's own Results.**
1. `main.tex:623` said that at the physiological conductance the calcium current is "too
   small to be recoverable at all" -- the retired DATA-side thesis, in a section that
   predates the parametric result. The direct fit recovers it there. Now attributed to the
   closure, with a forward reference.
2. `main.tex:308` claimed all five parametric estimates sit inside the tolerated stretch and
   all five closure estimates outside. Both halves false: 2 of 5 parametric fall outside,
   1 of 5 closure falls inside. It also restored the grid-artifact phrasing
   `figure_identifiability.jl` explicitly warns against. The Fig 13 caption carried the same
   overstatement eight lines above its own correct hedge.
3. The gCa=0.4 retrain paragraph quoted hull-only numbers with no "hull" -- the DOMAIN RULE
   again, a fifth time. The two domains differ ~6x there.

**The provenance-pointer drift bit a second time, and it was self-inflicted.** Adding a
4-line comment above `gNaP` in `src/hh_core.jl` invalidated 41 pointers across four files.
`check_provenance_refs.py` did NOT catch it: the shifted pointers still landed on non-blank,
non-`end` lines. **The checker only catches out-of-range and obviously-wrong targets; it
cannot tell that a pointer now names the wrong real line.** After ANY insertion into a `.jl`
file, rebase the pointers by the insertion size and spot-check by content.

Other confirmed and fixed: the canary was one commit stale (it guards nothing if left on an
old macro -- repoint it whenever you add macros); Table 2's voltage-only row printed the
FULL-STATE rollout macro; the sloppy and stiff directions were described the wrong way round;
Table 3's caption had the spread widening down the column when it widens up; the hull was
described as built from the training trajectory when it uses the full span; a cross-reference
pointed at the section that says the opposite; the abstract said training used 100 ms; an
unsupported causal clause explained the 15 ms collapse; the OU caption said sigma sets the
shape when sigma cancels outright; Table 1's caption claimed the omitted inactivation gate is
what makes the target two scalars; Figures 2 and 5 were cited only from inside other figures'
captions. Every figure and table is now cited from body prose (checked mechanically).

**68 candidates were never adjudicated** because the verifier agents hit a session limit.
They are NOT known defects -- the confirmed-to-refuted ratio on the adjudicated set was about
27:38, so most would likely fall. But they were never checked. The full list is in the
workflow transcript at
`.claude/projects/.../subagents/workflows/wf_ca2459c3-25f/triage.json` (key `unver`).
**Re-run that adjudication before submission** if you want the audit to be complete; the ones
worth checking first are the Discussion/Limitations/Conclusion items, since that region's
verifiers were the ones that died.

## 4f. Round 2: the 68 unadjudicated candidates (2026-08-21)

The first pass left 68 candidates unadjudicated because its verifier agents hit a session
limit. Those 68 were re-adjudicated against the CURRENT files. **The hit rate was much higher
than round 1: 50 STILL REAL, 14 refuted, 4 already fixed** -- against round 1's 27:38. They
were concentrated in Discussion, Limitations, Conclusion and Related Work, the regions whose
verifiers died first. **Do not treat an incomplete audit as a clean one.**

**FIXED THIS ROUND: the blocker and all ten majors.**

The blocker was an integrity problem, not a wording one. Related Work said the prior Kainth
work "independently corroborates" our black-box result. `references.bib:402` already records
that it is "prior work by four of this paper's five authors" -- so the paper claimed
independent corroboration from its own authors, and the surrounding paragraph is written in
the third person throughout, so nothing told the reader. Now discloses the overlap and drops
"independently".

The ten majors, briefly: Related Work called voltage "the only observable" (the headline
condition scores all six channels); it described our experiment as "recovering gating dynamics
from voltage alone", which Sec 5.2 explicitly disclaims; Table 4's caption conflated the hull
FIT domain with the evaluation domain for the R-squared row; the Fig 7b caption said the 40/50
ms rise does not clear seed noise when it is 4.7-6.5 sigma; a clause attributed the NODE
failure to "buying a tighter fit by clock index", contradicted by the recorded training
errors; the SINDy floor "keeps five of the six terms" does not follow from the estimator's
construction; the Conclusion listed the chain of controls without the measured objective
confound; and the README's figure table was missing the noise ablation while the paper claims
it maps every figure.

Also fixed: the Conclusion claimed the forecast is dependable "even when only voltage is
observed" (the guard forbids that reading -- voltage already dominates the objective);
Limitations called the gap "an order-of-magnitude contrast" without the decomposition; "roughly
half of the gap on a log scale" overstated the representation's ~39% share; and the anonymity
TODO still listed the acknowledgement that was removed.

**39 MINOR/NIT findings remain open and are listed in `paper/audit-2026-08-21-round2.json`
(status STILL_REAL).** None is a correctness blocker; they are things like a caption calling a
three-panel figure "the panel", a superlative the negative control beats, a rug that resolves
four ticks for five estimates, and several figure-caption/panel mismatches in fig13 and fig6.
Two are worth doing before submission because they touch numbers a reader checks: Appendix B's
rollout-horizon definition still omits the availability bound the metric now applies, and
`\LossDropPct` is a measured result hard-coded as a literal inside the block declared "model
INPUTS, not results".

## 4g. Round 5, and the ninth checker (2026-08-21)

**Round 5 was a full top-to-bottom audit**: 17 areas over all 2166 lines, 4 tables
cell-by-cell, 11 figures viewed, every candidate routed to a separate agent told to refute
it. **71 candidates, 28 confirmed.**

### The number that matters

| round | scope | confirmed | per area |
|---|---|---|---|
| 1+2 | full | 77 | ~4.3 |
| 3 | clearing minors | 39 | -- |
| 4 | 6 areas | 10 | 1.7 |
| 5 | 17 areas | 28 | **1.6** |

**The rate flattened. It did not converge.** Rounds 4 and 5 find defects at the same
per-area rate, so a sixth identical audit would find roughly 25 more. Repeating the loop is
no longer the right move; that is what the ninth checker is for.

### Why it flattened, and the round-5 blocker that proves it

By rounds 4-5 almost nothing found was an error of fact. They were **consistency debt**: the
paper asserts the same dozen things in three to six places each, a correction lands in one
or two, and the next audit finds the survivors. **Each fix seeds the next round's findings.**

The blocker is the archetype, and it was mine. Round 4 established that the matched-objective
control never isolates the optimiser -- it swaps the objective but keeps multi-start
Nelder-Mead -- so the residual twofold BOUNDS the representation rather than measuring it. I
wrote the rule into `claims.yaml` ("Say 'at most', never 'is'") and then applied it to
**Limitations alone**. The abstract still said the representation's own contribution *is* a
factor of about two, and split the gap 50/50 where the Results say two-fifths. One site fixed
out of five, in the most-read sentence in the paper. All six sites now agree.

Also fixed in round 5: Methods asserted the hull grid IS the network's genuine interpolation
region (Results retract that); the retrain paragraph claimed a flat direction "observed
directly" from one seed; `claims.yaml` still asserted the exact seed-noise sentence the Fig 7b
caption had been corrected away from a round earlier; Appendix B said the BFGS flag reaches
two run families when it reaches five; a bare `0.38` had no numok; two unit omissions. Plus
two README drifts no paper audit could see -- it still documented `HH_SMOKE` as destructive
when the code has isolated it to `results_smoke/` since 2026-08-20, and still carried the
"same trade-off direction" claim removed from the paper for lacking support in the body.

### The ninth checker: `scripts/check_consistency.py`

Built to kill that class mechanically instead of paying an audit round for it.
`paper/consistency.yaml` declares one group per repeated claim:

| field | meaning |
|---|---|
| `probe` | regex that finds the sites (omit to check `forbid` only) |
| `require` | every probed site must ALSO match this |
| `forbid` | no line may match this, ever |
| `forbid_unless` | exempts a denial ("the claim is *not that* ...") |
| `only_if` | site qualifier -- separates a claim from a mere pointer |
| `window` | lines of context a `require` may be satisfied from |
| `min_sites` | **fails if the probe matches too few** -- catches a probe gone stale |

Eleven groups today: the representation-share bound, the retired thesis, full-BFGS, five
gates, the interpolated profile interval, the four-of-five count, the DOMAIN RULE, no
equally-good-fits, rollout censoring, form-is-supplied, and single-seed ablations.

**Regression-tested:** re-injecting the round-5 abstract wording makes it FAIL on both lines;
reverting makes it pass. It also found a genuinely stale `[1.63, 2.13]` in `claims.yaml` on
its first run.

`consistency-ok` on a line exempts it -- for guard notes that deliberately quote a forbidden
phrase to warn against it. Use sparingly; each escape is a line no longer protected.

**THE WORKFLOW THAT MATTERS: when you change a claim, update `consistency.yaml` FIRST, then
let the checker name every site you still have to touch.** That is the whole point, and it is
the discipline that would have prevented the round-5 blocker.

## 4k. MENTOR VIDEO REVIEW, 2026-08-26. THE THESIS IS REOPENED. READ THIS FIRST.

Prathamesh replied to the corrected full draft with a ~16-minute video. Vinayak supplied
the transcript. **This is the most consequential input since the thesis reversal itself**,
and the next session must start here, not from §2.

> ## THESE ARE SUGGESTIONS, NOT REQUIREMENTS. (Vinayak, 2026-08-26)
> Everything in this section is a co-author's advice on a paper where **Vinayak is sole
> first author and corresponding author**, and Prathamesh said four separate times that the
> call is his: *"I leave decision up to you. It's your decision. Your paper, it's your work,
> it's your decision."* His judgement is worth a great deal and none of it should be
> discarded lightly — but it is input to a decision, not a checklist to execute.
>
> **The only BINDING constraints are the CFP's** (5 pages, official template, double-blind,
> checklist, reciprocal reviewer, 30 Aug 17:29 IST). See the BINDING/ADVICE split at the top
> of §13. **They already conflict once:** he asks for table captions below the table, the
> NeurIPS template puts them above, and the template wins. Read every item below as "worth
> doing unless we have a reason", not as "must".

> **COMPLETENESS: this section is exhaustive, not a summary.** The transcript was walked
> timestamp by timestamp and every distinct point extracted — 64 of them, from 00:00 to
> 16:07 — then each was checked mechanically against this file. All 64 are recorded here or
> in §13's N/A series. **You do not need the transcript to act; this section is sufficient.**
> The first pass of this section missed eleven, so if you add material to it later, re-walk
> the transcript rather than trusting a read-through: the easy ones to lose are the asides
> that cut against his main argument (11:54) and the one-clause content requirements (08:35).

### 1. THE HEADLINE: he is against the reverse claim as the WHOLE story

Verbatim: *"we should not go with this reverse claim. And if we are supposed to go ahead,
we should change the title and entire overall flow, even if the results are failing."*

**His reasoning is positional, not scientific.** Vizuara recently published a paper on
"SciML in the wild, why it hurts", and before that one presenting an application domain as
a stress test showing where SciML fails. His worry: *"it might sound like Vizuara's work
that comes as somewhere related to same thing ... and it tries to take the just different
domain for stress testing that particular claim."* A pure negative-result paper from this
group reads as house style rather than as this project's own finding.

**He explicitly does NOT overrule.** *"even if that was the only inference that we could
get, that is fine. We would have go ahead because ... your work is individual work. It has
nothing to do with what other candidates are doing at Vizuara and ... the results are
results."* And: *"revolving entire paper as a negative result for your case, I am not in
that favor, but I leave decision up to you. It's your decision. Your paper, it's your work."*

**What he proposes instead:** make HH + neural ODE + UDE the spine, and carry the symbolic
failure as **one part** rather than the thesis. *"We can mention that for the symbolic
recovery, it didn't recover, but that should not be the entire story."* He notes the
forecasting plots are strong and the error bars are good, so there is a positive result to
lead with.

**His one technical argument, and the honest reply to it.** He suggests the symbolic
failure may be method-specific: *"different algorithm might work. Like if you use SINDy and
[a neural] network, or there are newer methods now in SciML for symbolic recovery."*
> Partly answerable from what we already have, partly not — **do not wave this away, and do
> not accept it whole.** The paper already contains the sanity fit: run the SAME estimator
> on the TRUE calcium current and it returns a = 2.0000, b = -240.00 exactly. So the
> regression is exonerated and the scatter originates upstream, in the closure. BUT we have
> never run a *different* symbolic method on the *learned closure*, so "another algorithm
> extracts a better coefficient from this same closure" is untested. The defensible scope is
> "this closure, distilled this way, does not yield the conductance" — which is narrower than
> "functional identifiability fails", and the paper currently reaches for the wider claim in
> places.

**A POINT THAT CUTS THE OTHER WAY, AND HE SAID IT HIMSELF.** At 11:54 he notes:
*"NeurIPS workshop accept a preliminary negative result."* **So the venue is not the
objection.** A negative-result paper is publishable at Sim2Science on its merits; his
concern is purely about how it positions *this group's* output. That matters for N0 —
option (A) is not a venue risk, it is a positioning trade-off. Weigh it as one.

He also asks for precision rather than breadth if we do report the failure: *"we can make
exact claim if some of the identification is not working"* — i.e. name exactly which part
did not identify, rather than generalising to identifiability as a whole. That is the same
narrowing the box above arrives at from the evidence side.

**THIS IS A DECISION FOR VINAYAK AND IT IS NOT MADE.** Both options are live:
- **(A) Keep the reversal as the thesis.** Then, per his instruction, the title AND the
  entire flow change. §2 stays as-is.
- **(B) Rebalance.** HH/NODE/UDE forecasting is the spine; identifiability and the symbolic
  failure become a substantial section, not the frame. Retitle. §2's thesis text stays TRUE
  but stops being the paper's organising claim.
Nothing in §2 is retracted by this — **the science is unchanged**. What is contested is the
framing. Do not "fix" §2's numbers in response to this section.

### 2. Sim2Science logistics — CONFIRMED and TIGHTENED

| | |
|---|---|
| Deadline | 29 Aug 23:59 **AoE** = **30 Aug 17:29 IST**. He said "30 August, 5.30 PM IST" and that conversion is **correct** (AoE = UTC-12). |
| Length | 5 pages, official NeurIPS template only |
| Blinding | double-blind: no names, no affiliations |
| **Repo link** | **"Even the GitHub repository link, please avoid it as of now."** Harder than the CFP wording. T5 is not merely deferred, it is forbidden for this submission. |
| Checklist | must be filled WITH justifications. On code: say it is reproducible from the details given, and that **the full codebase is released upon acceptance**. |
| Reciprocal reviewer | **Nominate Prathamesh.** He volunteered and will send his ID. He is a co-author; **Vinayak remains sole first author and corresponding author** — he stated this unprompted, so authorship order is settled. He notes the role means **reviewing two papers** ("I'll review the two papers, that is for sure, with the proper guidelines"), so it is a real commitment he has accepted, not a formality. |

### 3. Writing feedback — applies to BOTH papers, urgently to the 5-page

**Structure**
- **Abstract: 14-15 lines MAX, few numbers.** Order: problem statement (start from HH) ->
  traditional approaches -> what SciML/we did -> results, qualitative then quantitative ->
  close. The current abstract is "very, very long".
- **Introduction: exactly 4 paragraphs**, the last being contributions; 3 covering
  introduction and related work. Minimum 20 citations overall (we have 38, fine).
- **Contributions: one headline + TWO LINES.** Not a bullet list, not a results summary,
  not many numbers. His reason is a reader's: *"I need to understand why should I read the
  paper ... If this is so long, I'll better read the entire paper."*
- **Related work: 2 paragraphs max.** Do not state results in Related Work or Introduction.
- **Discussion + Conclusion = ONE section. Limitations + Future Work = ONE. Two paragraphs
  max each.** Current version reads "like an essay".
- **Methods order:** dataset -> preprocessing -> neural ODE -> UDE -> symbolic.
- **ADD A DATA-GENERATION SUBSECTION.** *"Data generation you should definitely add."* We
  have all of it (the true model, the OU noise at 2% of each channel's SD, 512 samples over
  100 ms, the clean-vs-noisy split) but it is currently scattered through Methods rather
  than standing as its own step.
- **KEEP the training details.** *"this training matrix, these details are very important
  for us."* The budgets, optimiser, tolerances and metric definitions stay — they are not
  what to cut for length.
- **Cite the source of the equations.** *"you should cite a relevant paper that has this
  equations. If we are adding something from our side, make sure to give reasons for that.
  And make sure that we have the proper notations. Mathematically, it's correct."* Three
  separate requirements: (i) a citation for the HH/I_NaP/I_Ca equations as printed, (ii) an
  explicit justification wherever we deviated or added, (iii) a notation check. Note the
  round-7 audit already flagged a live notation collision as a *refuted* candidate worth
  revisiting here: Table 1's caption writes the source model's calcium gate product as
  $m^2h$ while $m$ and $h$ are already bound to the sodium gates.
- For NeurIPS, **stop explaining UDEs and SINDy from first principles** — cite and give one
  or two lines. (He was explicit that the long explanatory version is a *strength* for arXiv
  or a journal and will earn citations there. It is only wrong for a 5-page workshop paper.)
- **Appendix is allowed but 4-5 pages, not 20, and must not be a dumping ground** to make
  the main body fit. *"to shift everything in appendix is not a good idea."* To shorten it
  he suggests **reducing the figure sizes** rather than cutting content.

**AI-tells he flagged by name — this is the sharpest and most actionable part**
- The **title** "looks like a very AI generated one".
- Subheadings like **"known physics versus hidden current"**.
- Sentences like **"the identifiability vocabulary we use comes from a parallel line of
  work"** and **"we should say plainly what our protocol does not do"**.
- His warning is reputational, not stylistic: *"If such things are caught ... they might
  question, okay, is everything done by agent."* He suggests feeding a human writing-style
  guide to Claude and asks plainly: *"just make sure it doesn't sound too AI-generated"* and
  *"we should not over-exaggerate"*.

**Figures and tables**
- He asks for **table captions BELOW the table**, with the table at the top of the page.
  Ours are above.
  > **WE ARE NOT DOING THIS FOR THE 5-PAGE PAPER, and the reason is not stubbornness.**
  > The official NeurIPS 2026 template's own sample table is `\caption` *then*
  > `\begin{tabular}` (`neurips_2026.tex:342,345`) — captions ABOVE for tables, below for
  > figures. The CFP warns that submissions not using the required template may be
  > desk-rejected, so template convention beats a style preference here. Our tables already
  > match it: **no change**. For the archival paper it is a free choice, and caption-above
  > is the dominant convention there too. See P7 in §13. **This is the one place his advice
  > and a binding requirement collide — worth mentioning to him rather than silently
  > ignoring.**
- **Bold the best value in every metric column**, direction-aware (highest where higher is
  better, lowest where lower is better).
- **Legends must say what blue and green are** (Fig. 3's bars).
- Ablation figure titles should be plain: *"ablation: calcium, training window, noise"* —
  the current descriptive title is another AI-tell in his reading.
- **In the 5-page paper, show only ONE ablation case, not all three.** *"in NeurIPS, we
  cannot add this, so you can just give one case."* Choose deliberately; the conductance
  sweep is the only one with five seeds at every point, and it is the one that carries the
  mechanism.
- The 5-page paper must carry **the NODE/UDE forecast plot AND one symbolic-recovery graph**.
- **Fig. 1 schematic: he recommends paperbanana** (clone from GitHub, drive with a Gemini API
  key; it has a methodology-diagram category). Current one is *"too white ... just a
  flowchart diagram"*.
  > **This is NOT the request that was declined in §4.** That refusal was about generating
  > DATA figures, which would break Law I because they carry no CSV provenance. A methodology
  > schematic has no CSV to be traceable to, so Law I is not the objection. The remaining
  > objection is accuracy — a generated diagram can silently misdescribe the pipeline — and
  > that is checkable by looking at it. Reconsider on the merits; do not cite the old refusal.

**Praise, recorded because it calibrates how much to change:** *"a very good work overall"*;
the plots are *"very good quality and error bars are there"*; *"These are very, very good
figures"*; keywords good; references *"checked pretty well"*; appendix *"nice"*; *"you are
very good at writing the paper and you understand the depth of research"*. He thinks the
full paper is strong for arXiv or a journal and *"will get a lot of citations"*. **The
archival paper does not need rewriting — it needs the caption/AI-tell pass and a shorter
Discussion.**

**He praised the METHOD, not just the output, and that is worth keeping.** He opened by
singling out the previous email's handling of the citations — *"references unresolved,
unfabricated, two flagged"* — and the disclosure of citing our own group's work. He also
endorsed the working style explicitly: *"You are using the agentic pipeline along with your
knowledge. You are not completely dependent on autonomous pipeline, but you are taking
benefit of both."* Read that alongside his warning at 05:20 — *"Do not completely depend on
agent to write everything"* — and the AI-tell section above: the objection is to unowned
prose, not to the tooling. **The citation-audit and checker apparatus is validated; keep it.**

**A third publication route is on the table.** *"if you wish, not the arXiv preprint, then
you can aim for a journal submission, if any."* So the archival paper has three possible
destinations, not two: arXiv preprint, a journal, or both. Not a decision for this week,
but it affects how much polish the P-series deserves on the archival paper.

### 4. AMBIGUOUS — resolved by reading, not by asking (Vinayak's call, 2026-08-26)

At 12:39, mid-way through the figures: *"You definitely think of which trade-off bound you
wanted to add."* Vinayak's instruction is to infer it from the state of the paper rather
than block on a reply. **The adopted reading, with its reasoning, so a later session can
overturn it if he says otherwise:**

The sentence sits between *"These are very, very good figures"* and *"you'll have to very
smartly think of what to include in the 5-page paper"*. So it is about **figure selection
for the 5-page paper**, not about adding a new analysis. Exactly one figure in the paper
shows both a trade-off and a bound: **Fig. 7 (`fig13_parametric_identifiability.png`)** —
panel (a) is the $g_{Ca}$–$E_{Ca}$ loss-surface valley, which *is* the trade-off, and panel
(b) is the profile likelihood with the 95% interval, which *is* the bound.

> **ADOPTED: he means Fig. 7, and is asking which of its three panels earns space in five
> pages.** Act on that. Panel (c) is the one that carries the four-of-five closure
> comparison, so it is the panel that does argumentative work rather than method exposition.

**The alternative, recorded so it is not lost:** the representation-share upper bound
(objective ~3.2x, representation at most ~2.1x). Less likely — that is a number in prose,
not a figure, and he was scrolling figures when he said it. **Confidence: moderate, not
high. Unconfirmed.** If a reply to him is being written for another reason, add the
question; do not send one just for this.

### 5. His plan
Focus this week on Sim2Science. Send him the **5-page draft** to finalise. He will send a
second round of feedback on the big paper afterwards. He also suggested feeding this
transcript to Claude for further suggestions — which is what produced this section.

## 4l. N0 IS DECIDED (option C), AND THE 5-PAGE PAPER IS DRAFTED (2026-08-26)

**Vinayak's decisions, in the order he made them:**
- **N0 = (C), after (A) was drafted in full and then reconsidered.** The paper AUDITS the
  two-stage predict-then-interpret recipe: stage one (fit a UDE) earns its reputation,
  stage two (read the coefficient off the closure) does not, and a chain of controls says
  why. §2 stands unchanged and **the science is identical to (A)** — same numbers, same
  controls, same guards. Only the organising claim moved.
- **Claim scope = narrowed EVERYWHERE, both manuscripts.** "Functional identifiability
  fails" is now bound to *this closure under these distillations* at every site.

> ### WHY (A) WAS ABANDONED, AND IT IS THE MOST REUSABLE LESSON HERE
> Neither reason was visible when the option was chosen; both surfaced only by going and
> **reading the archival manuscript instead of trusting §2's summary of it**.
> 1. **`paper/main.tex` is ALREADY built as (C).** Its title is a question — *"When Can
>    Scientific Machine Learning Recover a Hidden Ionic Current?"*. Its Intro §1.2 says *"we
>    run the whole predict-then-interpret pipeline against ground truth we control."* Its six
>    contributions put the two POSITIVE results first and the failure third. Its Conclusion
>    opens positive and only then turns. **§2 records the THESIS as the reversal, and that is
>    true — but the paper is SHAPED as an audit.** Option (A) would have made the workshop
>    paper more aggressively framed than the manuscript the mentor read and praised, which is
>    exactly the objection he raised.
> 2. **The supplementary IS that manuscript.** `make_sim2science_bundle.py` generates
>    `supplementary.tex` by anonymising `main.tex`. Under (A) a reviewer would have opened a
>    declarative reversal-titled workshop paper and found a question-titled recipe-audit
>    paper attached to it — two frames inside one submission.
>
> **Cost of the switch: about three hours.** Title, abstract, the contributions paragraph,
> two subsection headings, one Discussion sentence. No figure, table, number or guard moved,
> because the science did not move. **If a framing decision ever comes up again, check what
> the archival paper actually does before deciding, not what §2 says it argues.**

### Two premises in §4k were WRONG, and the paper is the authority

1. **"We never ran a different symbolic method on the learned closure" is false.** We ran
   **two**: the constrained two-term fit on the supplied form, and the **unconstrained
   six-term sparse regression** (`main.tex:1396-1408`), which never sparsifies and fits the
   physical $Vs^2$ term with the WRONG SIGN at the representative seed. Both fail,
   differently. The mentor's objection is far more answerable than §4k assumed — but two
   methods is still not all methods, so the narrowing stands.
2. **§3's "6-term SINDy library cond ~25k trajectory, ~14k hull" is CONTRADICTED by the
   paper.** `main.tex:1379` says plainly: *"We did not measure the conditioning of the
   six-term polynomial library on either domain, so we assert nothing about it."* **Do not
   use those numbers.** They are not macros and nothing on disk backs them.
3. §3 also over-reads the sanity fit. `main.tex:1380-1394` is more careful: `a = 2.0000` is
   **exact by construction** (the analytic current lies in the estimator's two-column span),
   so it is a wiring check, not a test the fit could have failed. The pre-emption is built on
   that weaker, correct reading.

### The narrowing, and the checker that now enforces it
New `consistency.yaml` group **`functional-identifiability-names-its-scope`** (16 groups
now, 65 sites). It named all six drifted sites on its first run and every one was fixed:
`main.tex` abstract / contributions / Discussion, `README.md`, and two in `claims.yaml`.
A new `claims.yaml` scope block records the distillation as the unvaried axis.

> **A REAL BUG IN THE CHECKER'S CONTRACT, found writing that group.** `check_consistency.py`
> joins the context with `' '.join()`, so a qualifier straddling a line break inside an
> `\item` block arrives as **`"for this   closure"` — three spaces** — and a single-space
> literal in `require` silently never matches. **Write `require` alternations with `\s+`,
> never a literal space.** Several existing groups still use literal spaces in multi-word
> `require` branches (`symbolic-form-is-supplied`'s "given the conductance form", "assumed
> form"). They pass today; they are one rewrap away from a false FAIL. Not changed, because
> changing a passing group's regex changes what it protects.

### A live citation defect, caught by re-running the reference verifier
`norden2025structural` (arXiv 2502.04131) was **retitled on arXiv**. Our bib carried the v1
title; DataCite and arXiv now both return *"Structure is information: structural
identifiability mappings for machine learning with partially observed dynamical systems"*
(overlap 0.71, under the 75 % gate). Fixed in `references.bib`. Back to 36 verified / 2
review. **`verify_references.py` is not a formality — re-run it before every submission;
live records change under a stable DOI.**

### The 5-page paper
`paper/sim2science/main.tex` exists again, drafted from scratch. Preamble recovered from
`bfc8768` so `check_workshop_cut.py` re-armed cleanly on the first run.
- **Title (N1):** *"Predict, then interpret: how far a UDE gets on a hidden ionic current"*.
  Names the recipe, hints the finding without asserting it, and is deliberately NOT the
  archival title, which the mentor called AI-generated.
- **Structure:** intro 4 paragraphs with related work folded into the first three (his
  "3 covering introduction and related work" reading, which is the only one that fits five
  pages); contributions one headline + two lines; methods data-generation → preprocessing →
  NODE → UDE → symbolic with the training details KEPT; results run stage one → stage two →
  controls; discussion+conclusion one section, limitations+future work one, two paragraphs
  each.
- **Exhibits: ONE figure (fig13) and ONE table**, and this was settled against a REAL
  compile, not an estimate. **His forecast-plot and one-ablation asks are unmet**; both are
  carried as prose. **Tell him this; do not let him discover it.** The arithmetic, so it is
  not re-litigated: the body had ~0.15 page of headroom, fig5 costs ~0.29 page even at
  0.66\textwidth, and cropping it to the single voltage panel makes it *squarer and
  therefore taller* per unit width, not smaller. Keeping it would have meant deleting the
  retrain control or the sweep control — a bad trade, since Table 1 already states the
  forecast numbers **and** gives the repaired autonomous baseline that fig5 does not plot.
  **Settled against a SECOND compile:** after the (C) trims the References head lands
  ~75–80 % down page 5, leaving ~12–15 free lines against fig5's ~16. One to four lines
  short — and a `[t]` float can migrate to page 3 or 4 and cost *more* than its own height by
  leaving a ragged page bottom, so the shortfall is not the whole risk. **The forecast bars
  are not lost:** the supplementary IS the archival manuscript and already prints fig5, fig6
  and fig7c (verified, 11 figures in `supplementary.tex`), and the Supplementary paragraph
  now says so. The **LENGTH DIAL** in the preamble records the arithmetic and the gauge.
- **P1 (AI-tells):** em-dash rate cut from 4.1 to **1.6 per 1k words**, LLM-tell-word density
  0.0, `lint_prose` verdict clean on both manuscripts.
- **checklist.tex: all 16 answers filled with justifications**, instruction block deleted as
  the template itself instructs, `\input{checklist}` added AFTER the bibliography. Code
  answer is **No** with the honest reason (URL/DOI withheld for anonymity; reproducible from
  Sec. 2 + supplementary; full codebase released on acceptance). LLM-usage answer is **NA**:
  no LLM in the methodology, assistance confined to drafting and consistency checking.

> ### THE PAGE COUNT IS AN ESTIMATE AND IT IS THE ONE OPEN RISK.
> Claude gets 403 on Overleaf, so **nobody has compiled this.** The estimate is computed from
> the template's real geometry (`neurips_2026.sty`: textheight 9in, textwidth 5.5in, 10pt on
> 11pt ⇒ 58.9 lines/page) rather than from the old cut's own unverified word guess:
> **≈ 5.4 pages, with roughly ±0.4 of model error** (the sensitivity is words-per-line, taken
> as 13). It may already fit; it may need one dial turn. **Measure it first, then turn the
> dial — do not cut prose blind.**

### FIRST COMPILE, and the one thing no checker could see
The first Overleaf compile failed with ~40 `Undefined control sequence` errors, every one
pointing at `checklist.tex`. **The checklist was not the bug.** `neurips_2026.sty:407-411`
defines `\answerYes/\answerNo/\answerNA/\answerTODO` in terms of **`\textcolor`**, and the
`.sty` never loads a colour package — the official `neurips_2026.tex` supplies it, and our
preamble was written from the old cut, which never `\input` the checklist and so never
needed it. **Fixed: `\usepackage{xcolor}` before `hyperref`**, with a DO-NOT-REMOVE comment
naming the reason. Also fixed the 0.64 pt overfull `\hbox` on Table 1 (`\tabcolsep` 6 → 4.5 pt).

> **THE GAP THIS EXPOSES, and it is structural.** Eleven checkers were green on a document
> that would not compile. **Nothing in the suite verifies that a command used is defined** —
> `check_workshop_cut.py` resolves `\val` macros and `\cite` keys only, and `check_tex_sanity.py`
> looks for control bytes and swallowed prose. The failure mode is specific and will recur:
> a macro defined in a vendored `.sty` that depends on a package the `.sty` does not load.
> A static scan (collect every `\command`, subtract the `.sty`'s definitions, the preamble,
> `metrics.tex` and a LaTeX/package whitelist) now returns only `\slash` and `\tabcolsep`,
> both base LaTeX. **Worth promoting into a twelfth checker before the next venue.**

**Two BibTeX warnings in that log are EXPECTED and must not be "fixed":** `pal2023lux` and
`dixit2023optimization` (`entry type ... isn't style-file defined`). §8 explains why —
`unsrtnat.bst` has no `software` type, and retyping them `@misc` would break
`verify_references.py:256`, which keys on `type == "software"` to enforce a `version` field.

### Round 8 — the end-to-end audit of the option-C cut (2026-08-26, evening)
The cut had **never** been audited: written in one pass, rewritten twice, then hit with ~20
surgical trims. §4i predicts exactly this profile — *"every finding was an error introduced in
the writing"* — and that is what came out. Read end to end, plus mechanical cross-checks
(dangling refs, claim anchors, macro overlap, shared-macro bodies, guard spot-checks, prose
numbers in both manuscripts, README). **Six confirmed, all mine, all fixed.**

| # | sev | finding |
|---|---|---|
| 1 | **MAJOR** | **The "not the same kind of quantity" qualification was missing.** The cut compares the parametric spread against the closure spread in the abstract, the contributions, §3.2 *and* Table 1, but never said the two are different kinds of estimand. `main.tex:1917-1923` spends four sentences on it and says *"we would rather state that than let a reader discover it"*. Classic round-6 archetype: a qualification lost in compression while the claim it qualifies gets **more** prominent. Fixed by two sentences in §3.2. |
| 2 | MINOR | `"the same $\chi^2$ surface the profile traces"` — **forward reference**; the profile likelihood is not introduced until two sentences later. Created when the three-routes sentence was compressed. Reworded. |
| 3 | MINOR | Discussion asserted *"$R^2$ ... is above $0.99$"*. That is a **universal read off a five-seed mean** of 0.991 ± 0.005, and the archival paper never makes the claim — so the derived artifact was stating something its source does not. Replaced with the macro; one `numok` exemption retired with it. |
| 4 | MINOR | **$b$ was never defined.** The cut prints $s^2(aV+b)$ and defined only $a$. Straight P5 (notation) miss. Restored *"and $-b/a$ the reversal potential"*. |
| 5 | MINOR | Limitations read *"no statistical test is run anywhere, **so** every comparison is an equivalence-within-noise statement"* — a causal `so` that does not follow, left behind when the $n=5$ reason and the *"not an ordering"* clause were trimmed. Restored to the archival wording. |
| 6 | MINOR | The gate-propagation sentence asserted `physics-prior-reconstructs-unobserved-gates` with **no claim anchor**. Added (free — comments do not typeset). |

**One candidate was CHECKED AND REJECTED, and the reason generalises.** The memory note says the
objective at the true parameters is **39.64**; both manuscripts print **39.33 ± 1.26**. Not a
discrepancy: 39.64 is the objective at the *true parameters*, 39.33 at the *maximum-likelihood
fit of the true structure*, which scores slightly better because it absorbs the noise
realisation. **39.33 is the stricter reference and both training losses are below either.**
Do not "reconcile" them. (§4i: a confirmed-looking finding does not make its fix correct.)

**Also cleared, so nobody re-opens them:** the three macros used in the cut but not the archival
paper (`valParamFitSseFullTwo`, `valTrainLossBefore/After`) are **byte-identical aliases**
generated from the same map entries, so the cut states no number its source does not; and
`sglblindworkshop` appears only inside the DO-NOT-USE comment, never in a `\usepackage`.

**Net effect on length: −3 model lines.** The References head should move from ~85 % to ~80 %
of page 5, so the fixes cost nothing.

### Verification state
**All ELEVEN commands green**, both manuscripts: 322/322 macros, 0 flagged numbers in either,
0 claim errors, `lint_prose` clean ×2, 36/38 refs verified, tex_sanity clean, bib_sanity
clean, provenance clean, consistency 65 sites / 16 groups, workshop_cut 22 shared macros /
31 `\val` / 32 cite keys. `sim2science_upload/` rebuilt and the anonymiser accepted it.
**Anonymity spot-checked by hand beyond the script:** the only author-name hits in
`references.bib` are in `kainth2025pinodesr`, which the cut does **not** cite, so BibTeX
never prints it; the `.sty` hits are third-party provenance URLs in comments.

## 4m. Round 9 — the CROSS-MANUSCRIPT audit (2026-08-26, night). THE AXIS NOBODY
## HAD RUN, AND IT WAS THE PRODUCTIVE ONE.

Rounds 1-8 audited each manuscript against *itself*. **Nobody had ever asked whether the
5-page cut agrees with `paper/main.tex`**, which is the one question that matters for a
DERIVED artifact. 8 finders (Table 1 cell-by-cell, fig13 viewed, cross-paper numbers,
dropped qualifications, claim scope, guards, the archival's 2026-08-26 deltas, a fresh
prose read), every candidate routed to a separate neutral verifier, MAJORs to two verifiers
with different lenses. **56 agents, 37 candidates, 17 distinct defects after dedup.**

> **A 32-of-37 survival rate is the round-7 smell running the other way.** §4j's lesson was
> that 0/15 means the refuters were primed. 32/37 means the *finders* may be. Both MAJORs
> and every contested call were hand-checked against the CSVs before being believed, and
> that is what caught the one fabricated number below.

**FOUR MAJORS, all in the cut, all fixed.**

| # | site | defect |
|---|---|---|
| 1 | `sim2science/main.tex:355` | **Table 1's first row named the wrong experiment.** Labelled `Neural ODE, as published` while printing `\valNodeParityTime*` — the PARITY-budget run. `node_parity_summary.csv` is explicit: `published_time` = 229--9213 / 0.55±0.65, `parity_time` = 275--11762 / 0.43±0.45. The archival keeps them as two rows disambiguated by a budget column **the cut does not have**, so the label carried the whole burden and named the wrong run. Knock-on: "Table 1 gives both" was false — the budget control was nowhere in the cut. Fixed by restoring the published row, so the cut now mirrors the archival's three-row ladder. |
| 2 | `sim2science/main.tex:484` | **"lower than the loss at the true parameters."** 39.33 is the objective at the *maximum-likelihood fit of the true structure*; `claims.yaml` says the objective at the true parameters "is in no committed CSV at all -- do not quote one". **Round 8 checked the §3.3 site, found it correct, and never checked the sibling.** The single most-repeated failure mode in this project, caught one round later. |
| 3 | `sim2science/main.tex:329` | **The voltage-only gate result had lost the true-initial-condition qualification.** The archival states it FOUR times (`:356`, `:784-785`, `:1143`, `:1168`); the cut stated it nowhere. `claims.yaml` calls omitting it "the easiest way to lose this claim in review", and the cut is what reviewers read. |
| 4 | `sim2science/main.tex:232` | **`iravanian2020` was called symbolic.** It is *"...Using a Domain-Specific **Recurrent Neural Network**"*, and `main.tex:469` says so. The cut invented a symbolic precedent its own source denies, inside the sentence about the second stage. |

**Ten MINORs / NITs fixed**, the reusable ones being: the retrain paragraph put the
**trajectory** forecast under "On the hull" (the DOMAIN RULE breaking *backwards* — the
archival spends a whole Table 4 caption sentence preventing exactly that); "an error of about
six per cent" where 6.2 % is the relative *spread* and the error is 4.6 %; "the representative
seed" never defined in the cut while the sentence says it is the *lowest of the five*
(pre-registration is the whole defence and it was missing); the Table 1 caption dropping the
caveat `claims.yaml` marks MANDATORY ("deliberately unequal ... licenses only the
one-directional reading") while *adding* a bolding leaderboard the archival uses in no table.

**Two archival fixes.** `main.tex:1901` claimed *"no better algorithm exists for that basis"* —
vacuous under one reading (OLS is the least-squares optimum by construction, so the "so" does
no work) and false under the other, in the one paragraph whose job is to BOUND the claim; the
cut already omitted it, so deleting it made them agree. And the 2026-08-26 narrowing had landed
at **two sites out of four**.

> ### THE NEW GROUP, AND WHY `require` BEING AN **OR** IS ONLY A FLOOR
> `functional-identifiability-names-its-scope` passes on `this closure` **alone**, because its
> `require` is an alternation. `claims.yaml` binds BOTH halves ("FOR THIS CLOSURE UNDER THESE
> DISTILLATIONS"). So the checker was green while the Discussion and the contributions bullet
> carried half the qualification. New group **`identifiability-narrowing-names-the-distillation`**
> (17 groups, 71 sites) pins the second half. **It was ADDED, not merged into the sibling** —
> §4l's warning stands: changing a passing group's regex changes what it protects. On its first
> run it named all three drifted sites, including one in the cut nobody had flagged by hand.

> ### A VERIFIER FABRICATED A NUMBER, AND ONLY A DISK CHECK CAUGHT IT.
> One verifier "refuted" the archival clause by reporting it had re-run an $E_{Ca}$-constrained
> fit giving **2.012 ± 0.068**. No results CSV carries the closure's per-point output, so that
> fit cannot be reproduced from this repo at all. **The number is unsourced; do not use it.**
> The finding did not depend on it. What IS on disk and makes the same point: the implied
> reversal potential $-\hat b/\hat a$ on the supervised trajectory runs **66.6 to 231.0 mV**
> against a true 120 (`symbolic_domain_comparison.csv`, traj-train rows). **When a subagent
> reports a computed result, check the input exists before believing the output.**

### The length arithmetic, and it is the open risk
Measured, not guessed: body words **2624 -> 2743 (+119)** ≈ +9.2 typeset lines at the LENGTH
DIAL's 13 words/line, **+1** for the third neural-ODE row, **−3.9** from turning the dial
(fig13 `0.85 -> 0.70\textwidth`, dial step 1, which is P8's "reduce figure sizes rather than
cut content"). **NET ≈ +6.3 typeset lines** against the ~12--15 free the last compile left.
It should still fit; the margin is now thinner than it was. **Re-measure where the References
head lands.** If it reaches page 6, the next dial turns in order are: fig13 to 0.62 (~2 more
lines), then drop the third neural-ODE row again and reword "gives both" to cite the
supplementary (~1 line). **Do NOT pay for it with the retrain or sweep control.**

### A gap in the suite, adjacent to the missing twelfth checker
**`check_claims.py` has never been run against the 5-page cut** — §8's command line passes
`--tex paper/main.tex` only. So the cut's `% claim:` anchors are verified by *nothing*, which is
why two unanchored assertions survived to round 9. Fixing this is a one-flag change and belongs
with `check_undefined_macros.py`.

**Verification state after round 9: all ELEVEN green on both manuscripts** — 322/322 macros,
0 flagged numbers ×2, 0 claim errors, `lint_prose` clean ×2 (no new flags; READ.CV improved
0.64 -> 0.70), 36/38 refs, tex/bib/provenance clean, **consistency 71 sites / 17 groups**,
workshop_cut 22 shared macros / **34** `\val` / 32 cite keys. `sim2science_upload/` rebuilt and
the anonymiser accepted it; hand-checked again (the only author-name hits are in
`kainth2025pinodesr`, which the cut does not cite, and the archival's self-identifying clause is
neutralised in `supplementary.tex:465` — **D4 restores it for camera-ready**).

## 4n. MENTOR REVIEW 2 (2026-08-28). THE SUPPLEMENTARY SLOT DOES NOT EXIST.
## READ THIS BEFORE ANYTHING ELSE — IT INVALIDATES THE FIGURE TRADE.

Prathamesh reviewed the compiled 5-page draft and answered the N9 questions, in two emails.
**He is happy with the paper** — *"good Sim2Science story and a good fit for the workshop"*,
*"the paper is now well-balanced rather than just a stress test"* — and asks for **one more
iteration** before submission. Most of it is ordinary revision. One item is not.

> ### THE ONE THAT CHANGES THE PLAN: THERE IS NO SEPARATE SUPPLEMENTARY UPLOAD.
> *"Since Sim2Science does not provide a separate supplementary upload, everything has to go
> into the appendix."* … *"I submitted a paper to Sim2Science today and there is no separate
> option for supplementary material but you check once. The appendix must be included within
> the main paper itself."*
>
> **VERIFY THIS ON THE ACTUAL SUBMISSION FORM BEFORE RESTRUCTURING** — he says "check once",
> and everything below is downstream of it. But plan for it being true.
>
> **What it invalidates, in blast-radius order:**
> 1. **N4's whole trade (§4l) is dead.** The forecast plot and the ablation were "in the
>    supplementary, *available* not *guaranteed seen*". With no supplementary slot they are
>    simply **ABSENT**. The arithmetic that justified one body figure assumed a second PDF
>    existed. It does not.
> 2. **`paper/sim2science/main.tex:536-544`, the `\paragraph{Data, code and supplementary
>    material.}`, becomes FALSE.** It promises the supplementary carries eight specific
>    things (parameter table, metric definitions, forecast and voltage-only overviews, all
>    three ablations, the SINDy attempt, the six-domain check, the \gcaPhys{} negative
>    control, seed counts). None of that ships unless it goes in an appendix.
> 3. **`checklist.tex:64` (Q4) and `:84` (Q5) become FALSE** — both cite "the supplementary"
>    as where the reproducibility detail lives. Those are the only two live checklist sites;
>    the other `supplement` hits are template boilerplate, not our text.
> 4. **The F-series premise shifts.** "The supplementary IS the archival manuscript" was the
>    freeze rationale. The submitted artifact is now **ONE pdf**. F2–F6 still apply, to that
>    one file.
> 5. **§4l's SECOND argument for option (C) is moot** — the "two frames inside one
>    submission" worry assumed the archival shipped as the supplement. **N0 IS STILL
>    DECIDED.** Argument #1 (the archival is *already built* as (C)) is untouched and was
>    always the stronger of the two. **Do not reopen N0 on the strength of this.**

### His six asks, with what each one costs

| # | ask | his words | cost / hazard |
|---|---|---|---|
| **1** | **Add a Stage-1 figure. "Highly important."** | *"A reader never actually sees the success of Stage 1 … one figure showing the NODE prediction, the UDE prediction, and the ground truth voltage/current trajectory … The current Figure 1 can then become the second figure or be simplified."* | He describes **trajectories**, not the bar chart. See the hazard box below — this is the item with a live trap in it. |
| **2** | **Soften the headline claim** | replace *"What fails is the functional identifiability of this closure"* with *"What fails is the practical recovery of the physical coefficient from this flexible closure under the tested objectives and distillation procedures."* | A CLAIM CHANGE → `consistency.yaml` FIRST, then let the checker name every site. Tension noted below. |
| **3** | **Appendix, 4–5 pages, concise** | *"one table with complete training hyperparameters, reproducibility details, hardware/compute information, parameter tables, any remaining ablation details … without making the submission unnecessarily long."* | Most of it ports from the archival's App A + App B. **Compute/hardware is NEW and only Vinayak knows it.** |
| **4** | **Checklist placement** | *"Sim2Science states that checklist should be added after references and before the appendix."* | Today `\input{checklist}` is after the bibliography and there is no appendix. New order: body → references → **checklist** → appendix. |
| **5** | **Footer** | *"still says 'Submitted to 40th Conference…' Since this is a workshop submission, setting the workshop title through `\workshoptitle{Sim2Science}` … Check the guidelines on the website."* | **He is mistaken about the mechanism, and the obvious fix is a trap.** See the box. |
| **6** | **Checklist consistency + compute** | *"ensure the checklist is fully consistent with the manuscript … Add the missing compute details (CPU/GPU, runtime, memory). If details were not logged or cannot be mentioned, we can state that positively."* | Q8 currently answers **No**. Either measure, or restate positively. Q4/Q5 must lose "the supplementary". |

> ### HAZARD ON THE FIGURE ASK — D1 GOES FROM DEFERRED TO ACUTE.
> **`fig2` and `fig3` still print "state reconstruction" as their in-image title** (decision
> D1, §4j). In the archival that is survivable because only fig5's caption denies the word
> and *does* carry an apology clause. **The 5-page cut has no apology clause anywhere.** So
> promoting either panel into the 5-page body ships a figure whose printed title contradicts
> the paper's own "propagation, not reconstruction" sentence at `sim2science/main.tex:88-89`.
> Three ways out, in order of preference:
>   (a) **regenerate fig2/fig3 from the corrected code** — closes D1 properly, but README
>       calls this a TRAINING run, so it needs Vinayak's greenlight and could contradict
>       Table 2 if it fails to reproduce;
>   (b) carry the apology clause into the 5-page caption (free, honest, slightly awkward);
>   (c) use **fig5** (the train-vs-forecast bar chart) instead — it has no in-image title
>       problem, but it is **not what he asked for**: it shows magnitudes, not trajectories.
>
> **WHERE THE SPACE COMES FROM, and this is the insight that makes the ask affordable.** The
> body had ~zero headroom after round 9. **The appendix is the new lever**: Methods detail
> can move out of the body and into App B, freeing body lines for the figure. That is a
> better trade than any on the old LENGTH DIAL, and it did not exist before this email.
> **Still do not pay for the figure by deleting the retrain control or the sweep control.**

> ### HAZARD ON THE FOOTER ASK — DO NOT PASS `final` TO GET IT.
> `\workshoptitle{Sim2Science}` **is already set** (`sim2science/main.tex:91`). The footer is
> the template's *correct submission-mode behaviour*, not a missing setting:
> `neurips_2026.sty:111` builds `\@trackname` as "… Workshop: \@workshoptitle." but
> `:416-425` uses `\@trackname` **only when `\if@neuripsfinal` is true**; otherwise it prints
> the generic "Submitted to 40th Conference … Do not distribute."
> **`\DeclareOption{final}` at `:49-51` sets `\@neuripsfinaltrue` AND `\@anonymousfalse`.**
> Passing `final` to make the footer name the workshop would **turn off double-blind
> anonymity and print the real byline.** That is a desk-reject, not a formatting tweak.
> **Check the Sim2Science site for what they actually require. If they do want the
> workshop-named footer at submission, find another route and re-verify anonymity after.**

> ### TENSION IN THE SOFTENING ASK — DO NOT DELETE THE VOCABULARY.
> In review 1 (§4k) he **asked for** the Loman/Browning/Baker parametric-vs-functional
> vocabulary, and §4l built two `consistency.yaml` groups on the phrase
> `functional(ly)?[- ]identifiab\w*` — `functional-identifiability-names-its-scope` and
> `identifiability-narrowing-names-the-distillation`, whose probes would go dead if the
> phrase disappeared (both carry `min_sites`, so they would FAIL loudly rather than silently
> — that is the design working). His ask is to soften **the headline sentence**, not to
> retire the frame. Keep the vocabulary where it explains the finding; use his wording where
> the paper *asserts* the failure. **His phrasing is narrower than ours, which is the right
> direction for a frozen artifact (F2).**

### The N9 answers — N10 is unblocked, and one decision is yours alone
- **Reviewer ID: `~Prathamesh_Dinesh_Joshi1`** (or search the full name and pick from the
  dropdown; Vizuara shows under his affiliation). *"The author line details will be imported
  automatically once you enter the ID."*
- **THE AUTHOR LIST IS VINAYAK'S CALL AND HIS ALONE.** On whether to add Raj Dandekar, Rajat
  Dandekar and Sreedath Panat: *"I leave that decision entirely up to you. Due to past
  experience, we have a strict policy not to influence this choice, so the decision is
  yours."* **Decide before submitting — the CFP allows no authors to be added after review
  opens.** Do not let a session make this call for him, and do not let it drift.
- **Table captions: confirmed ABOVE.** *"I checked as well, and NeurIPS guidelines state that
  table captions should be placed at the top."* P7 settled, no change.
- He does **not** want the full archival shipped as a supplement even if a slot existed:
  *"submitting a full-length paper draft as a supplement is generally not a good practice."*

### THE COMPILED-PDF PASS (2026-08-26, late). THE LAST UNCOVERED AXIS, AND IT PAID.

Vinayak compiled all three artifacts and pasted them back. **This is the axis §4i named as
the remaining risk and no session had ever been able to run**, because Claude gets 403 on
Overleaf. Three findings, all in the rendered output, none visible to any checker.

1. **The 5-page cut FITS.** References head lands on **page 5, line 184**, with the body
   ending at 183. The round-9 arithmetic (net ≈ +6 typeset lines against ~12–15 free) held.
   Table 1's six rows do not overflow `\textwidth` at `\tabcolsep` 4.5 pt, and fig13 is
   legible at `0.70\textwidth`. **Both blind changes survived contact with the typesetter.**
2. **A defect I introduced, caught only in print.** The A4 abstract edit read *"distil the
   closure back into the conductance form $s^2(aV+b)$, **and separately by** unconstrained
   sparse regression"* — a coordination mixing "into X" with "by Y". Rewritten to
   *"distil the closure back into closed form **twice**: once constrained to the conductance
   form $s^2(aV+b)$, and once by unconstrained sparse regression over a six-term library."*
   **A fix that passes eleven checkers can still read badly. Only the PDF shows that.**
3. **MAJOR, and it was in the SUBMITTED supplementary.** It printed
   `TODO-REPOSITORY-URL` twice and `TODO-COMMIT-SHA` / `TODO-ARCHIVE-DOI` once, raw, to
   reviewers — while the 5-page paper says *"the repository URL, snapshot DOI and commit are
   withheld here for anonymity"* and checklist Q5 says *"both are withheld"*. **One
   submission, three artifacts, two of them contradicting the third.**

> **THE FIX WENT IN THE BUNDLER, AND THE REASONING GENERALISES.**
> `paper/main.tex` is RIGHT to hold those placeholders — T5–T7 substitute them at
> publication. What was wrong is that the anonymiser did not neutralise them on the way out.
> `make_sim2science_bundle.py` now does, as step **3b**, mirroring the author-overlap clause:
> two `assert`-guarded blocks, plus a final sweep that FAILS the build if `TODO-` survives on
> any line that typesets (comments may keep it). So the archival keeps its placeholders, the
> submitted supplementary says what the other two artifacts say, and a future reword of the
> archival wording breaks the build loudly instead of shipping a placeholder.
> **Never hand-edit `sim2science_upload/` — it is build output. Fix the bundler.**

**Also fixed this pass:** `checklist.tex` Q7 said *"Two quantities are deliberately not
reported"* as mean ± SD. There are **three** — the censored horizons, the two time-indexed
spans, and the autonomous row's **median**, which the round-9 table caption newly explains.
Found because **`checklist.tex` is verified by nothing** (see §8).

**Net effect of the whole PDF pass: 3 fixes, one of them MAJOR in the submitted supplementary.
The 5-page `main.tex` did not change** — `sim2science_upload/main.tex` is byte-identical to
`paper/sim2science/main.tex`, so **only `supplementary.tex` needs recompiling.**

## 4j. Round 7 — the figure-and-table audit (2026-08-22). ONE REAL DEFECT, AND THE
## WORKFLOW REFUTED IT.

30 agents: one per printed figure (each told to **VIEW the image**), one per table
(cell-by-cell against `generated/metrics.tex` and the CSVs), each candidate routed to a
refuter. **15 candidates, and the workflow returned 0 confirmed.**

**Do not trust that zero. I spot-checked it by hand and found the workflow wrong.**

The refuter prompt said "default to refuted unless the evidence is unambiguous" AND named
two guards (G14's deliberate missing error bar, and the NODE rollout horizons legitimately
staying mean ± SD) as things that "refute a lot of plausible-looking findings". That is
priming, and it is my error in writing the prompt. A 15/15 refutation rate is a smell, not
a clean bill of health.

### The defect the refuter got wrong

`figures/fig6_voltage_only_overview.png` prints, as its in-image title,

> **UDE : state propagation (truth vs UDE)** ← what it says NOW in code
> **UDE : state reconstruction (truth vs UDE)** ← what the COMMITTED PNG still says

and the caption at `main.tex:1187` spends a clause denying exactly that word: *"it is
\emph{propagation} from the true initial state under known gate equations rather than
reconstruction of the gates from voltage."* **This is mentor review point 4** — he asked
for "propagation" not "reconstruction" — regressed in a place no checker and no prose audit
can see, because it is pixels.

`src/experiment.jl:224` is the single source: it titles EVERY overview figure that way, so
fig2, fig3 and fig6 all carry it. Only fig6's caption actively contradicts it, which is why
it is acute there.

**What was done, and what was NOT.**
- `src/experiment.jl:224` now reads `state propagation`. One string, **same line count**,
  so no provenance pointers moved (verified).
- The fig6 caption now discloses that the printed title still reads "state reconstruction"
  and that the caption corrects it. That makes today's draft honest with no run.
- **THE COMMITTED PNGs STILL SAY "state reconstruction".** The code and the images now
  disagree, deliberately and temporarily.

> **OPEN DECISION, and it is the best remaining reason to touch the pipeline.**
> Regenerating fig2/fig3/fig6 from the corrected code would remove the caption apology and
> close mentor point 4 properly. README calls fig6 "trained in place", so this is a
> TRAINING RUN, not a replot — the evidence base is closed without your greenlight, and a
> run that failed to reproduce the published trajectory would contradict Table 2. Not done.
> If you do it: re-verify the figures byte-wise against their captions afterwards, and
> delete the apology clause from the fig6 caption in the same pass.

### What the audit got RIGHT

I checked the two most suspicious refutations by hand and the refuters were correct:
- **fig5** prints `3950.0` with an error bar for the time-indexed NODE forecast, which
  looks like a G2 violation. It is not: the caption at `main.tex:1114-1118` explicitly says
  that bar "summarises a blown-up solve and its error bar is not a dispersion estimate".
  Anticipated and disclosed.
- **fig13(a)** resolving only four markers for five parametric fits is already stated in the
  caption ("Two of the five estimates coincide to within a marker width").

### The lesson worth keeping
**Write refuter prompts neutral.** "Default to refuted" plus a list of things that commonly
refute findings produces a rubber stamp. Round 6's refuters killed 25 of 31 candidates and
that felt right; round 7's killed 15 of 15 and one of them was real. **When a refutation
pass returns zero, hand-check the two or three most substantive kills before believing it.**

## 4i. Round 6 — the final pre-submission audit (2026-08-22). THE RATE FINALLY FELL.

41 agents: 7 area auditors over all 2,174 lines of `main.tex` and 3 over the 5-page cut,
every candidate routed to a separate agent told to **refute** it. **31 candidates, 6
confirmed.**

| round | scope | areas | confirmed | per area |
|---|---|---|---|---|
| 1+2 | full | 18 | 77 | ~4.3 |
| 4 | 6 areas | 6 | 10 | 1.7 |
| 5 | 17 areas | 17 | 28 | **1.6** |
| **6** | **full + the cut** | **10** | **6** | **0.6** |

**Round 5's warning was that the rate had flattened at ~1.6 and a sixth audit would find
~25 more. It found 6.** Per 1,000 lines of `main.tex`, round 5 confirmed 12.9 defects and
round 6 confirmed 0.92; the survival rate also fell, 39% to 10%, so the finders proposed
less AND less of it held. The ninth checker plausibly earned its keep: the consistency-debt
class that dominated rounds 4-5 produced **zero** findings this round.

> **DO NOT READ THAT AS "an order of magnitude cleaner". The comparison is not
> like-for-like, and two of the differences are real coverage gaps.**
> 1. **Round 5 VIEWED all 11 figures and checked 4 tables cell-by-cell against their
>    CSVs. Round 6 did NEITHER.** That ground is uncovered, and it is historically
>    productive: two figures once shipped contradicting their own text (§10).
> 2. Round 6 was given an explicit DO-NOT-REPORT list excluding the 39 known open
>    minor/nits. Round 5 had no such exclusion, so part of the gap is definitional.
> 3. Round 6 used 7 areas of ~310 lines against round 5's 17 of ~127 — fewer eyes per line.
> 4. Round 6 finders were capped at 4 findings and told to prefer few and certain.
>
> **A seventh PROSE audit of `main.tex` is not a good use of time.** The figure-and-table
> gap named here was closed the same day — see §4j, which found one real defect (the fig6
> title) that every prose round and every checker had missed. **Both audit axes have now
> been run. Neither is worth repeating; the remaining risk is in the COMPILED PDF and in
> the delivery, which is where every recent failure has actually come from.**

### Full paper — 2 confirmed, both fixed

1. **MAJOR, and it was a live footgun, not a wording bug.** `README.md:203` said Figure 8a
   is produced by `experiments_runner.jl` from `results/metrics_all.csv`. It is not:
   the printed panel is 1950x1500, the canvas of `figure_commoneval_window.jl`, which reads
   the corrected `results/identifiability/rollout_censoring.csv`. **Both scripts write the
   same filename**, and the runner's version plots the pre-censoring 70.0 constant — the
   exact value the Fig. 8a caption says the panel is *not* plotted at. So following the
   documented pipeline silently overwrites the good panel with one that contradicts its own
   caption. Same species as the `stage_figures.ps1` footgun in §9, different mechanism.
   `main.tex` was left alone (its sentence becomes true once the README conforms); fixed in
   `README.md` — the figure row, a new entry-point step 12 for `recover_rollout_censoring.jl`,
   a plotting-only row for `figure_commoneval_window.jl`, a blockquote warning, and the
   `HH_REPLOT=1` row.
   > **STILL ARMED AT THE CODE LEVEL, and it is your call.** `experiments_runner.jl:331`
   > still writes `fig7b_commoneval_ablation_window.png`. Renaming its output to
   > `..._precensoring.png` (and dropping the row from `stage_figures.ps1:40`) would make
   > the collision impossible. Not done: it changes a committed pipeline script, and the
   > evidence base is closed without your greenlight. Documentation alone leaves it armed.

2. **MINOR.** The Fig. 9 noise caption said "no adjacent difference here can be judged
   against a spread", while the sibling Fig. 8a caption at line 2131 does exactly that
   judging ("several times the five-seed spread at the centre point"). Reworded.

### The 5-page cut — 4 confirmed, all four mine, all fixed
The cut had **never** been audited, and it was written in one pass. Every finding was an
error introduced in the writing, which is the expected profile for new prose:
- **MAJOR:** "Three *independent* routes agree on the precision." They are not independent —
  the asymptotic SE is the Gauss–Newton approximation to the *same* $\chi^2$ surface the
  profile traces. `main.tex:1482-1487` says so explicitly and avoids the word; the cut
  asserted it. Now matches.
- **MAJOR:** the Fig. 1 caption said the grid-point reading "would overstate" the interval
  width. **Backwards** — the grid bracket is 0.500 wide against the interpolated 0.541, so
  it *understates*, which is why it wrongly pushed seed 3333 outside. `main.tex:1578` makes
  no directional claim; the cut now matches it. (Note: §4b above says the grid reading
  "inflated the interval". **That wording in this file is itself wrong** — same error.)
- **MAJOR:** the Supplementary paragraph promised "per-seed tables". The supplementary is
  the anonymised `main.tex`, whose four tables are all mean ± SD. Now promises seed counts
  and spreads, which is what it actually carries.
- **MINOR:** the preamble named `scripts/check_shared_macros.py` as the enforcer of the
  two-preamble invariant. That script does not exist — the enforcer is
  `scripts/check_workshop_cut.py`. Repointed.

### One proposed fix was REJECTED, and the reason generalises
The verifier's remedy for the noise caption was to calibrate the noise steps against the
five-seed spread at the centre point, mirroring the window caption. **That is wrong here.**
`main.tex:1223` already warns that where the spread varies along an axis, "each point must
be judged against its own spread rather than the centre point's" — and on the *noise* axis
the noise level is the very quantity that sets the spread, so the centre point's spread is
not transferable. The caption now says that instead. **A confirmed finding does not make
its proposed fix correct; verify the remedy separately.**

## 4h. The venue is settled, and it reshaped the deliverable (2026-08-21, evening)

**T2 is DONE and it was the consequential one.** Sim2Science is a **NeurIPS 2026
workshop** (Paris, 12 or 13 Dec). https://www.sim2science.com/cfp.html — verified twice,
independently, because the answers change the artifact:

| | |
|---|---|
| **Deadline** | **29 August 2026, 23:59 AoE** |
| **Length** | **5 pages excluding references.** Unlimited supplementary/appendix, but "reviewers are not obligated to read it" |
| **Format** | official NeurIPS 2026 template, `\usepackage[dblblindworkshop]{neurips_2026}` + `\workshoptitle{Sim2Science}`. **"Submissions not using the required template may be desk-rejected."** |
| **Review** | **DOUBLE-BLIND.** No author names/affiliations, no self-identifying references |
| **Archival** | **Non-archival.** No proceedings, so the full paper stays eligible for an archival venue afterwards |
| **Also required** | one author nominated as **reciprocal reviewer** at submission; `checklist.tex` filled (does not count toward the limit) |

**Non-archival is the load-bearing fact:** submitting here does not burn the paper. The
full manuscript remains the archival version and `paper/main.tex` was NOT cut down.

### What was built
`paper/sim2science/main.tex` — a **derived** 5-page double-blind cut. 2,395 body words,
one figure (fig13), no tables. It states nothing `main.tex` does not, uses only `\val`
macros, and carries every guard: the domain rule, the interpolated interval, four-of-five,
censored rollout, form-is-supplied, representation-as-a-bound, spans-not-mean-SD for the
time-indexed NODE rows.

**Two guards were added because two manuscripts is exactly the consistency debt §4g is
about.**
- `paper/consistency.yaml` now lists `paper/sim2science/main.tex` in **all groups** (15 then, 16 since the 2026-08-26 scope group), so
  every shared invariant is enforced across both files (58 sites, up from 24).
- `scripts/check_workshop_cut.py` (**tenth checker**) covers what consistency.yaml cannot:
  shared fixed-input macros must have **identical bodies** in both preambles, every `\val`
  must resolve, every `\cite` must resolve, every figure must exist under its exact name.

### The supplementary is GENERATED, not written
`scripts/make_sim2science_bundle.py` builds `sim2science_upload/` and produces
`supplementary.tex` by **anonymising `paper/main.tex` at build time** — byline stripped,
`pdfauthor` blanked, identifying comments removed, and the Related Work self-identifying
clause neutralised. One source of truth; the transform is auditable and in one place.

**It refuses to write anything if a single identifying string survives, if a figure is
missing, or if either document still has a non-empty `\author`.** That guard is not
decorative: on its first run it caught a camera-ready comment *I had just written into the
cut's preamble* that named the byline. An un-anonymised upload is a desk-reject and cannot
be undone.

> **The clause at `main.tex:477` is a genuine conflict, and the transform takes a side.**
> Round 2 added "though that work shares four of this paper's five authors" because
> claiming *independent* corroboration from your own authors is an integrity problem.
> Under double-blind that disclosure breaks anonymity. The transform keeps the hedge
> ("rather than lean on it as independent") and drops only the reason.
> **RESTORE THE FULL DISCLOSURE IN THE CAMERA-READY — it is not optional there.**

### Open, and yours
- **`paper/sim2science/neurips_2026.sty` and `checklist.tex` are vendored third-party
  files** (NeurIPS). `LICENSE` carves out `paper/arxiv.sty` and `Vizuara_Paper_HH.pdf` by
  name; these two are not in that list yet. Same class of decision, not made unilaterally.
- **Nobody has compiled either document.** The 5-page claim is a word-count estimate
  (2,395 words + abstract + one figure), not a measured page count.

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
python scripts/check_consistency.py
python scripts/check_workshop_cut.py
python "Paper Writing Skills/scripts/check_numbers.py" "paper/sim2science/main.tex" --macros "paper/generated/metrics.tex"
```
> **2026-08-26: the two formerly dormant checkers are LIVE again.** `paper/sim2science/main.tex`
> exists (the option-C redraft), so `check_workshop_cut.py` and
> `make_sim2science_bundle.py` both do real work. Nothing is skipped any more.

Current state (2026-08-26, after the option-C conversion): **all ELEVEN green —
extract_metrics 322/322 macros match disk · check_numbers OK on both manuscripts (0 flagged)
· check_claims 0 errors, 11 warnings · lint_prose clean on both · verify_references 38 refs,
36 verified, 2 review · tex_sanity clean on both · bib_sanity clean · check_provenance_refs
clean (12 expected WARNs) · check_consistency 65 sites across 16 groups agree ·
check_workshop_cut 22 shared macros / 31 `\val` / 32 cite keys all resolve.**
`sim2science_upload/` rebuilt. No duplicate `\newcommand` in either manuscript. `doctor.py`
reports 3 FAILs; those are the broken local MiKTeX and are expected — compilation is
Overleaf-only.

> **SUPERSEDED 2026-08-26 (round 9). CURRENT STATE: all ELEVEN green on both manuscripts —
> 322/322 macros · check_numbers OK ×2 · check_claims 0 errors / 11 warnings · lint_prose
> clean ×2 (no new flags; READ.CV improved 0.64 → 0.70) · verify_references 36/38 ·
> tex_sanity · bib_sanity · provenance (12 expected WARNs) · consistency
> **71 sites / 17 groups** · workshop_cut 22 shared macros / **34** `\val` / 32 cite keys.**

> ### THREE THINGS THIS SUITE DOES NOT CHECK. All three cost something real.
>
> **1. Nothing verifies that a command USED is actually DEFINED** (the missing twelfth
> checker — the `xcolor` story below). Still open.
>
> **2. `check_claims.py` has NEVER been run against the 5-page cut.** The command below
> passes `--tex paper/main.tex` only, so **no checker has ever read the cut's `% claim:`
> anchors**. That is why two unanchored assertions survived to round 9. Fixing it is one
> flag. Note `claims.yaml` `section:` ids are the archival outline, so expect warnings, not
> errors, on first run against the cut.
>
> **3. `paper/sim2science/checklist.tex` is verified by NOTHING** — not `check_numbers`
> (which never sees it), not `check_claims`, not `lint_prose` — and it ships **inside the
> submitted PDF**. Round 9 read it by hand and found Q7 undercounting the non-mean±SD
> quantities (two, should be three). A checklist answer that contradicts the paper is an
> administrative risk, not a scientific one, which is exactly why nobody looks.

> ### A TWELFTH CHECKER IS MISSING, AND IT COST A COMPILE CYCLE.
> **Nothing in this suite verifies that a command USED is actually DEFINED.** All eleven were
> green on a document that would not compile: `neurips_2026.sty:407-411` defines
> `\answerYes/\answerNo/\answerNA` via **`\textcolor`**, and the `.sty` never loads a colour
> package — the official `neurips_2026.tex` supplies it. Our preamble came from the old cut,
> which never `\input` the checklist and so never needed `xcolor`. Result: ~40
> `Undefined control sequence` errors all pointing at `checklist.tex`, which was not the bug.
> **Fixed by `\usepackage{xcolor}` before `hyperref`**, with a DO-NOT-REMOVE comment.
> The general failure mode — *a macro from a vendored `.sty` that depends on a package the
> `.sty` does not load* — will recur at the next venue with the next template. The stopgap is
> a static scan: collect every `\command` in the manuscript, subtract what the `.sty` defines,
> what the preamble defines, `generated/metrics.tex`, and a LaTeX/package whitelist. Run
> against the cut it leaves only `\slash` and `\tabcolsep`, both base LaTeX. **Promote it to
> `scripts/check_undefined_macros.py` before the next submission.**

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
**Paper state (2026-08-26, evening):** all **ELEVEN** checkers green on BOTH manuscripts,
0 unsupported claims, 322 macros, 38 refs (36 verified, 2 expected review). Seven adversarial
audit rounds; the last two are §4i and §4j. The 5-page cut exists again under option (C),
compiles, and fits — see §4l.

**The full paper HAS been compiled and read** (2026-08-26, Vinayak). That gate — open since
2026-08-19 and the one every previous handoff led with — is CLOSED. The rebuild/upload
procedure and its traps still live in §7; use them for any future build.

**Mentor:** replied 2026-08-26 **with a video**, not text. See **§4k**, which is now the
most important section in this file. It reopens the framing question and supplies a long
list of concrete writing fixes.

### Do this first
**N0 IS DECIDED — see §4l. Option (C): the paper audits the two-stage recipe.** Option (A)
was drafted in full first and then abandoned for two reasons that only appear if you read
`paper/main.tex` rather than §2's summary of it — §4l has both. The claim scope was narrowed
in BOTH manuscripts in the same session, and the 5-page paper is drafted with all eleven
checkers green. **§4k is history, not a to-do list; §4l is the live section.**

> ### THE SCIENCE IS DONE. THE STRUCTURE IS NOT — §4n REOPENED IT (2026-08-28).
> **The evidence base is closed and stays closed.** Nine audit rounds, all eleven checkers
> green, all three artifacts compiled and read in print. Nothing below asks for a new number.
>
> **DO NOT RUN A TENTH AUDIT ROUND on what already exists.** Not because auditing is
> exhausted but because the *axes* are: prose in `main.tex` (rounds 1–6) · figures and
> tables (rounds 5, 7) · the cut internally (rounds 6, 8, 9) · cross-manuscript agreement
> (round 9) · the compiled PDFs · `checklist.tex`. **DO re-audit whatever mentor review 2
> changes** — new prose is new risk, and §4i's profile for fresh writing is "every finding
> was an error introduced in the writing".
>
> **WHAT IS OPEN IS THE SHAPE OF THE SUBMISSION, and it is open because of one fact:
> there is no separate supplementary upload (§4n).** The 5-page paper has to grow an
> appendix, gain a Stage-1 figure, soften its headline claim, move its checklist, and stop
> promising a supplement that will not ship.

> ### VERIFY THIS FIRST. EVERYTHING ELSE IS DOWNSTREAM OF IT.
> Open the actual submission form at `NeurIPS.cc/2026/Workshop/Sim2Sci` and check whether a
> **supplementary-material upload** exists. Prathamesh submitted his own paper there on
> 2026-08-28 and reports it does not — but he said *"you check once"*, and the entire
> restructure below is conditional on his being right.
> **If there IS a slot:** the old plan survives largely intact; re-read §4l's trade before
> changing anything, and note he still advises against shipping the full archival as a
> supplement.
> **If there is NOT:** work N11–N17 below in order.

> ### WHAT GETS SUBMITTED, AND WHERE IT LIVES. Get this wrong and the paper is desk-rejected.
> **After the restructure this is ONE pdf, not two.**
>
> | upload | compile this | source to EDIT |
> |---|---|---|
> | `main.pdf` — body ≤ 5 pp + references + checklist + appendix | `sim2science_upload/main.tex` | `paper/sim2science/main.tex` (+ `checklist.tex`) |
>
> **EDIT the SOURCE. UPLOAD the bundle.** `sim2science_upload/` is build output, destroyed on
> every `make_sim2science_bundle.py` run — a hand-edit there is lost silently.
> **NEVER upload a PDF built from `paper/main.tex` itself:** it carries the real byline,
> affiliations and emails, and would break double-blind.
> `supplementary.tex` keeps being generated — it is still the anonymised archival and still
> the place the two manuscripts are checked against each other — but **it is no longer a
> submitted artifact**. Do not delete the bundler path; it is how §4n item 2's content gets
> ported into the appendix, and it is the archival's own anonymisation route for A10.

### Waiting on someone else
**NOTHING IS BLOCKED ON HIM ANY MORE (2026-08-28).** Both items arrived; see §4n.
1. ~~Prathamesh's reviewer ID.~~ **RECEIVED: `~Prathamesh_Dinesh_Joshi1`.** N10 unblocked.
2. ~~His feedback on the 5-page draft.~~ **RECEIVED, two emails, §4n.** He wants **one more
   iteration**, then we submit.
3. Still outstanding: his second round on the **archival** paper (A11), which he sends after
   Sim2Science. Not on the critical path.

> **ONE THING ONLY VINAYAK CAN DECIDE, AND IT IS IRREVERSIBLE.** Whether Raj Dandekar, Rajat
> Dandekar and Sreedath Panat go on the author line. Prathamesh: *"I leave that decision
> entirely up to you. Due to past experience, we have a strict policy not to influence this
> choice."* **Every author must be listed at submission; none can be added after review
> opens.** No session should decide this, infer it, or let it slide to the deadline.

### VINAYAK'S TODO LIST

Nothing below is blocked on analysis; every item is a decision or an errand. They are
ordered so that each one's prerequisite comes before it.

**REVISED 2026-08-21 evening, after the CFP landed (§4h). T2 is done and it invalidated
half of what was below.** The deadline is **29 Aug 23:59 AoE.** The ordering now runs off
the submission, not off the archival paper.

**REVISED AGAIN 2026-08-26, after the mentor's video (§4k).** B1/B2 are DONE — the full
paper has been compiled and read. The 5-page cut has been **DELETED** and is being redrafted
from scratch. D2 is **SKIPPED** by Vinayak's decision.

> ## THE CRITICAL PATH, 2026-08-26
> **Deadline: 30 Aug 17:29 IST (= 29 Aug 23:59 AoE). Four days.**
> **Step 0 is a DECISION, not a task: the framing question in §4k. Everything about the
> 5-page paper — its title, abstract, contributions and section order — depends on which
> way it goes, so it cannot be deferred and then written around.**

### FIRST: what is BINDING and what is ADVICE

Corrected 2026-08-26 after Vinayak pushed back, and the distinction is load-bearing because
one of the two lists contradicts the other.

| | |
|---|---|
| **BINDING** | The Sim2Science CFP: 5 pages excluding references, the official NeurIPS 2026 template, double-blind, the filled checklist, a nominated reciprocal reviewer, 30 Aug 17:29 IST. Miss one and the paper is desk-rejected. |
| **ADVICE** | Everything in the mentor's video (§4k). He is a co-author and his judgement is worth a lot, and he said four times that the call is Vinayak's. **These are suggestions to weigh, not a checklist to execute.** |

> **THEY ALREADY CONFLICT ONCE, so do not treat the video as spec.** He asks for table
> captions *below* the table. **The official NeurIPS template puts them ABOVE** — its own
> sample table is `\caption` then `\begin{tabular}` (`neurips_2026.tex:342,345`), and figure
> captions go below. Our tables are already caption-above. **For the 5-page paper the
> correct action is therefore NO CHANGE**, and following his suggestion would move us away
> from the required template. For the archival paper it is a free choice; caption-above is
> the dominant convention there too.

### P-series: presentation rules that apply to BOTH manuscripts

**Listed once, on purpose.** Writing these into the N-series and the A-series separately is
precisely the consistency debt that five audit rounds were spent paying down — two copies
drift, and the next audit finds the survivors. Both series below point here instead.

| # | Rule | Source | Notes |
|---|---|---|---|
| P1 | **AI-tell pass.** Kill the named offenders and their siblings: the title, "known physics versus hidden current", "the identifiability vocabulary ... parallel line of work", "we should say plainly what our protocol does not do". | advice, strongly held | His concern is reputational — a reviewer concluding the work was agent-written. The most valuable item on this list. |
| P2 | **Bold the best value in each metric column**, direction-aware. | advice | |
| P3 | **Legends must name the colours** (Fig. 3's blue/green bars). | advice | A genuine legibility defect, not taste. |
| P4 | **Plain ablation figure titles**: "ablation: calcium, training window, noise". | advice | |
| P5 | **Cite the source paper for the equations as printed; justify anything we added; notation pass.** | advice | Includes Table 1's caption writing the calcium gate product as $m^2h$ while $m,h$ are already the sodium gates. |
| P6 | **Shorten Discussion/Conclusion/Limitations.** Discussion+Conclusion one section, Limitations+Future Work one, <=2 paragraphs each. | advice | Far more urgent at 5 pages. |
| P7 | **Table captions: keep them ABOVE.** | **template beats advice** | See the conflict box. No change for either paper unless you decide otherwise for the archival one. |
| P8 | **Reduce figure sizes** to shorten an appendix, rather than cutting content. | advice | |
| P9 | Reconsider **paperbanana** for the Fig. 1 schematic. | advice | §4k explains why the §4 refusal does not apply to a non-data diagram. Applies to whichever paper carries a schematic — at 5 pages it may not survive at all. |

### N-series: the Sim2Science 5-page paper (drafting from scratch)

**Also do P1-P9 here.** P1, P5 and P6 matter most in 5 pages; P7 means leaving the captions
where they are.

| # | Do this | Waits on | Notes |
|---|---|---|---|
| **N0** | ~~DECIDE THE FRAMING.~~ **DONE 2026-08-26: option (C)** -- the paper audits the two-stage predict-then-interpret recipe. (A) was drafted in full first, then abandoned; **§4l has both reasons and they are the reusable part.** | -- | Do NOT reopen without reading §4l. |
| **N1** | ~~Retitle.~~ **DONE.** *"Predict, then interpret: how far a UDE gets on a hidden ionic current."* | -- | Deliberately not the archival title, which he called AI-generated. |
| N2 | ~~Draft the 5 pages.~~ **DONE.** `paper/sim2science/main.tex` exists; preamble recovered from `bfc8768` so `check_workshop_cut.py` re-armed cleanly. | -- | Related work is folded into the intro's first three paragraphs -- his "3 covering introduction and related work" reading, the only one that fits five pages. |
| N3 | ~~Contributions: one headline + two lines.~~ **DONE.** | -- | Headline is the audit, not the reversal. |
| ~~N4~~ | **SUPERSEDED 2026-08-28 by §4n.** The trade below assumed a supplementary upload that does not exist, so "the supplementary prints them" is no longer a defence. **See N13.** ~~Figures.~~ ~~Main body carries **one figure (fig13) and one table**.~~ His forecast-plot and one-ablation asks are unmet; both are prose. | -- | Arithmetic in §4l, settled against TWO real compiles. The supplementary prints fig5/fig6/fig7c and the Supplementary paragraph now names them -- but the CFP says **reviewers are not obligated to read it**, so the figure is *available*, not *guaranteed seen*. Say it that way to him. |
| N4b | ~~Data-generation subsection + keep training details.~~ **DONE.** | -- | Methods runs data generation -> preprocessing -> NODE -> UDE -> symbolic. |
| N5 | ~~Do P1-P9.~~ **DONE for the 5-page paper.** P1: em-dash rate 4.1 -> **1.6 per 1k words**, LLM-tell density 0.0, `lint_prose` clean. P7: captions stay above. | -- | **P1-P9 are still OPEN for the archival paper** -- that is A-series work after the deadline. |
| N6 | ~~Fill `checklist.tex`.~~ **DONE.** All 16 answered with justifications, instruction block deleted as the template itself instructs, `\input{checklist}` placed AFTER the bibliography. | -- | Code answer is **No** with the honest reason (URL/DOI withheld for anonymity; reproducible from Sec. 2 + supplementary; codebase released on acceptance). LLM answer is **NA**: no LLM in the methodology. |
| N7 | ~~No repo URL, names or affiliations.~~ **DONE and verified by hand, not only by the bundler.** | -- | The only author-name hits in `references.bib` are inside `kainth2025pinodesr`, which the cut does **not** cite, so BibTeX never prints it. The `.sty` hits are third-party provenance URLs in comments. |
| N8 | ~~Bundle, compile, measure.~~ **DONE, and now CLOSED.** Compile 1 failed on the missing `xcolor` (§8). Compile 2 put the References head ~75-80 % down page 5. **Compile 3 (2026-08-26, post round 9) is the one that counts: xcolor fix confirmed, ~40 checklist errors gone, References head on page 5 at line 184 with the body ending at 183.** All three artifacts read in print. | -- | **The gauge is where the References head lands, not a page total.** Page 5 = fits. **One recompile outstanding: `supplementary.tex` ONLY**, after the bundler's `TODO-` fix. |
| **N9** | **SEND the 5-page draft to Prathamesh.** **DRAFTED 2026-08-26 at `paper/draft-email-N9-prathamesh.md` — not sent.** Read it before sending; it has a three-item pre-send check at the top. | recompile of `supplementary.tex` -- **THEN DO THIS** | Tells him the three things rather than letting him find them: (i) the framing went to **(C)**, which is what his own full-paper draft already does; (ii) the forecast plot and the ablation are in the **supplementary**, not the body, and the CFP says reviewers are not obliged to read it, so they are *available*, not *guaranteed seen* -- **this is an ask of his we did not meet, and the draft says so plainly**; (iii) **table captions stay ABOVE** because the template requires it -- the one place his advice and a binding requirement collide. It also **asks for the reviewer ID up front** (it blocks submission) and asks him to confirm his author line. |
| **N10** | **Nominate Prathamesh as reciprocal reviewer** — ID **`~Prathamesh_Dinesh_Joshi1`** (or search the full name, pick from the dropdown; his author line imports automatically) — and submit at `NeurIPS.cc/2026/Workshop/Sim2Sci`. | N11–N17 | All authors listed at submission; none can be added after review opens. Upload BOTH PDFs: `main.pdf` (5 pages) and `supplementary.pdf`. **The CFP wording: "at submission time, authors nominate one author of the paper -- someone with sufficient relevant expertise and publications -- to serve as the paper's reciprocal reviewer."** |

### N11-N17: mentor review 2 (2026-08-28). Work these IN ORDER — each unblocks the next.

**Read §4n first.** Every row below assumes there is no supplementary upload slot; N11 is
the check that establishes that. **Nothing here needs a new experiment.**

| # | Do this | Notes / hazards |
|---|---|---|
| **N11** | **VERIFY on the submission form whether a supplementary upload exists.** | Gates everything. He says no and says "check once". If a slot DOES exist, re-read §4l before changing anything — but he still advises against shipping the full archival as a supplement. |
| **N12** | **DECIDE THE AUTHOR LIST.** Raj / Rajat / Sreedath in or out. | **Vinayak's alone**, he was explicit. Irreversible at submission. Do this early, not at the deadline. |
| **N13** | **Add the Stage-1 figure.** NODE vs UDE vs ground truth. He calls it *"highly important"* and it is the one substantive content ask. **He also offers a second space lever, which the first pass missed:** *"The current Figure 1 can then become the second figure **or be simplified**."* So fig13 may be demoted, shrunk further, or reduced to fewer panels — it does not have to survive at full size. | **D1 becomes acute** — fig2/fig3 print "state reconstruction". Three routes in §4n's hazard box; (a) regenerate needs a GREENLIGHT because README calls it a training run. Space comes from moving Methods detail into the appendix, **not** from deleting the retrain or sweep control. |
| **N14** | **Build the appendix, 4–5 pp.** Hyperparameter table, reproducibility, **compute/hardware**, parameter table, remaining ablation details. | **He gave explicit permission to CUT, and the 4–5 page cap makes that load-bearing:** *"It is perfectly fine to omit some details from the longer draft; in fact, submitting a full-length paper draft as a supplement is generally not a good practice."* Do not try to cram the whole archival in. Ports from the archival's App A + App B and Table 1 — they are the right content at roughly the right length. **Compute/hardware is genuinely new and only Vinayak knows it** (see N16). |
| **N15** | **Kill every "supplementary" promise.** `sim2science/main.tex:536-544` (the whole `\paragraph{Data, code and supplementary material.}`) and `checklist.tex:64` (Q4) and `:84` (Q5). | **AND KEEP THE RELEASE-ON-ACCEPTANCE WORDING CONSISTENT while you rewrite it** — his words: *"If the repository will only be released after acceptance, make sure the wording in the paper and checklist says that consistently."* The paper paragraph and checklist Q5/Q13 are one pair; changing one half is how they drift. Those are the only FOUR live sites; the other `supplement` hits in checklist.tex are template boilerplate. Repoint them at the appendix, or delete the promise. |
| **N16** | **Checklist: move it, fix Q8, and re-check ALL SIXTEEN answers.** New order body → references → **checklist** → appendix. Q8 (compute) currently answers **No**. His ask is broader than three questions: *"Please ensure the checklist is fully consistent with the manuscript."* **Specific hazard the restructure creates:** the checklist carries four `Sec.~N` cross-references (Sec. 1, 2, 3, 5) written against the CURRENT section numbering. Adding an appendix and moving content between body and appendix can invalidate every one of them, and **no checker will catch it** (§8). Walk all sixteen. | He is fine either way: *"If details were not logged or cannot be mentioned, we can state that positively."* **ASK VINAYAK for CPU/GPU, RAM and rough runtime** — nobody else can supply them. Then make Q4/Q5/Q8 agree with the restructured paper. Remember `checklist.tex` is verified by NO checker (§8). |
| **N17** | **Soften the headline claim** to his wording: *"the practical recovery of the physical coefficient from this flexible closure under the tested objectives and distillation procedures."* | **CLAIM CHANGE → `consistency.yaml` FIRST**, then let `check_consistency.py` name every site in both manuscripts. **Do NOT delete the functional-identifiability vocabulary** — he asked for it in review 1 and two groups probe on it (§4n's tension box). Soften where the paper *asserts*; keep the frame where it *explains*. |
| **N18** | **Check the footer question on the Sim2Science site.** | `\workshoptitle{Sim2Science}` is already set. **Do NOT pass `final` to make the footer name the workshop — `neurips_2026.sty:49-51` sets `\@anonymousfalse` and would print the real byline.** §4n's footer box has the full mechanism. |
| **N19** | **Re-audit ONLY what N13–N17 changed**, then re-run all eleven checkers and rebuild the bundle. | New prose is new risk; §4i's profile for fresh writing is "every finding was an error introduced in the writing". Do not re-audit the untouched body. |
| **N20** | **Send the revised draft back to Prathamesh.** *"Let me know once you make these changes."* | He expects one more look before submission. `paper/draft-email-N9-prathamesh.md` is the previous note and shows the house style. |

### A-series: the archival paper (after the workshop deadline)
He does **not** want this rewritten — it is strong for arXiv or a journal. It needs a
finishing pass, not surgery.

| # | Do this | Notes |
|---|---|---|
**A1-A9 were REMOVED on 2026-08-26 — they are now P1-P9 and apply to BOTH papers.** They
were mis-filed as archival-only, which would have meant doing the same nine things twice and
letting the two copies drift. Only what follows is genuinely archival-only.

| # | Do this | Notes |
|---|---|---|
| A10 | Decide the destination: **arXiv preprint, a journal, or both**. | He raised the journal route unprompted. Affects how much polish P1-P9 deserve here. |
| A11 | Second round of mentor feedback on the big paper. | He will send it after Sim2Science. |
| A12 | Restore anything the 5-page paper had to drop for anonymity or length. | The author-overlap disclosure (D4) is the one that is *mandatory* to restore, not optional. |

### Still open, unchanged
- **D1** regenerate fig2/fig3/fig6 from the corrected "state propagation" title (a training
  run — needs a greenlight; would let the fig6 caption apology be deleted).
- **~~D2~~ SKIPPED by Vinayak, 2026-08-26.** `experiments_runner.jl` keeps writing
  `fig7b_commoneval_ablation_window.png`. The README warning in the plotting-only section is
  now the only defence — **it must not be deleted.**
- **D3** add `neurips_2026.sty` + `checklist.tex` to the `LICENSE` third-party carve-out.
- **D4** the author-overlap disclosure: dropped for anonymity, **restore for camera-ready**.
- **T4-T8** fresh repo, repo URL, Zenodo DOI, commit SHA, README citation block — all after
  the workshop deadline, and T5 is *forbidden* in the workshop submission (see §4k).
- 39 MINOR/NIT findings in `paper/audit-2026-08-21-round2.json`. None is a blocker.

> **The S1-S5 table that stood here is SUPERSEDED and was removed on 2026-08-26.** It was
> written against the old 5-page cut, which no longer exists. Use the N-series above. T1
> is done (B1/B2); T4-T8 are folded into "Still open, unchanged".

**Law I still applies to T5–T7.** A URL, a DOI and a commit SHA all contain digits, and
`check_numbers.py` is line-based. After substituting, append a `% numok:` at the TRUE END of
every line that then carries a digit — mid-line, it silently deletes the rest of the line.
(This paragraph appeared twice, near-identically, until 2026-08-26. Deduplicated.)

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


### F-series: FREEZING THE SUBMITTED ARTIFACT (added 2026-08-26, and it is not optional)

**The problem, in one sentence.** At submission the two manuscripts cannot disagree — the
supplementary IS the archival paper, generated by anonymising `main.tex` at build time — but
`paper/sim2science/main.tex` stays an **editable file in a repo whose archival paper will keep
moving** (journal revision, A11's second mentor round, P1–P9). The submitted PDF will not move
with it.

> **THE FAILURE MODE, and it is this project's oldest archetype wearing a new hat.**
> A journal referee forces a claim narrowing in the archival paper. `check_consistency` fails
> on **both** files, correctly. A future session "fixes" it by editing
> `paper/sim2science/main.tex` to match. The checker goes green — and the repo now asserts
> that the workshop paper said something it did not. The sibling that was not fixed is a PDF
> that **cannot** be fixed. Narrowing is the direction revisions travel, so this is the likely
> case, not the exotic one.

| # | Do this | When |
|---|---|---|
| ~~**F1**~~ | ~~Check whether Sim2Science makes OpenReview submissions publicly visible.~~ **ANSWERED 2026-08-26 from the CFP** (`sim2science.com/cfp.html`), and it raises the stakes rather than lowering them: *"Rejected or withdrawn submissions are not made public"* but *"accepted submissions will be linked on the workshop webpage."* Also confirmed there: *"Sim2Science is non-archival — there are no formal proceedings, so accepted work remains eligible for submission to archival venues afterwards."* **So: accepted ⇒ the 5-page paper becomes a publicly linked, citable record and F2–F6 are load-bearing. Rejected ⇒ the whole problem evaporates.** | ~~before N10~~ **DONE** |
| **F2** | **Keep the 5-page paper at the NARROWEST version of every claim.** Already done once — "this closure under these distillations". This is the real protection: the frozen artifact must never be the one holding the wider claim, because then a later narrowing strands it. Apply this rule to any edit before submission. | ongoing |
| **F3** | **Tag the submitted commit**: `git tag -a sim2science-submitted -m "exact state submitted to Sim2Science <date>"` then `git push origin sim2science-submitted`. Do it on the commit whose bundle produced the uploaded PDFs, not a later one. | **at N10** |
| **F4** | **Mark the file frozen.** After submission add a banner at the top of `paper/sim2science/main.tex`: this is a RECORD of a submitted artifact; editing it does not change what was submitted; the only legitimate edit is the camera-ready. Repeat it here in §13. | at N10 |
| **F5** | **When `check_consistency` later fails across the two files, the DEFAULT is to change the archival paper, not the cut** — or to accept the divergence and document it, never to silently edit the frozen cut. If the cut must change, that is a camera-ready decision, and F3's tag is the diff baseline. | after N10 |
| **F6** | **The camera-ready is the ONLY re-sync point.** If Sim2Science accepts and the archival paper has narrowed by then, the camera-ready adopts the narrowing (and D4's author-overlap disclosure is restored at the same time). If it rejects, the whole problem evaporates — the 5-page paper becomes a draft with no standing. | on acceptance |

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

Rewritten 2026-08-28 (seventh time), after **mentor review 2** (§4n). The previous prompt
said the papers were finished and only delivery remained. **That is no longer true**: there
is no supplementary upload slot, so the 5-page paper has to grow an appendix and absorb what
the supplement was carrying. Copy everything between the fences into a fresh session.

```
We're continuing my Advanced Hodgkin-Huxley x SciML paper. Repo:
d:\SciML\bootcamp\Research Project\HH-SciML-Project   (branch main, pushed, clean)

READ HANDOFF.md FIRST, in this order:
  Sec 4n  - MENTOR REVIEW 2. THE LIVE SECTION. There is no supplementary upload
            slot, which kills the figure trade the paper was built around. It
            also has three HAZARD BOXES (the fig2/fig3 title, the `final`
            option, the claim-softening tension). Read all three.
  Sec 13  - the to-do list. N11-N20 are this session's work, in order.
  Sec 4l  - why N0 is option (C) and must not be reopened.
  Sec 8   - the eleven checkers and the THREE things they do not check.
  Sec 9   - gotchas, non-optional.
  Sec 3   - current numbers AND the boxed DOMAIN RULE.

--- STATE ---
- DEADLINE: Sim2Science @ NeurIPS 2026, 30 Aug 17:29 IST (= 29 Aug 23:59 AoE).
- THE SCIENCE IS DONE AND THE EVIDENCE BASE IS CLOSED. Nine audit rounds, all
  ELEVEN checkers green, all three artifacts compiled and read in print.
  NOTHING below needs a new experiment. Do not propose one.
- Prathamesh (co-author, the mentor) reviewed the compiled draft and is HAPPY
  with it - "good Sim2Science story", "well-balanced rather than just a stress
  test". He wants ONE more iteration, then we submit. His reviewer ID is in.
- Framing (N0) is CLOSED: option (C). Sec 4n notes that one of the two original
  reasons for (C) is now moot - do NOT reopen it on that basis; the other reason
  was always the stronger one.
- I compile on Overleaf; you get 403. You can NEVER measure a page count. Ask me
  and I will paste the PDF back. The gauge is where the References head lands.

--- DO THIS FIRST, IT GATES EVERYTHING ---
N11. Check the actual submission form at NeurIPS.cc/2026/Workshop/Sim2Sci for
     whether a SUPPLEMENTARY-MATERIAL upload exists. Prathamesh submitted his
     own paper there on 28 Aug and reports it does not, but said "you check
     once". Every task below assumes he is right. If a slot DOES exist, stop and
     re-read Sec 4l before changing anything.

--- THEN, IN ORDER (Sec 13 has the full rows) ---
N12. AUTHOR LIST DECISION - MINE ALONE. Whether Raj Dandekar, Rajat Dandekar and
     Sreedath Panat go on the byline. Prathamesh explicitly refuses to influence
     it. Irreversible: no author can be added after review opens. ASK ME EARLY;
     do not decide it for me and do not let it drift to the deadline.
N13. Add the Stage-1 figure (NODE vs UDE vs ground truth). He calls this
     "highly important" - a reader never sees stage one succeed. HAZARD: fig2 and
     fig3 still print "state reconstruction" in-image (decision D1) and the
     5-page cut has no apology clause. Regenerating is a TRAINING run and needs
     my greenlight. Space comes from moving Methods detail into the new appendix,
     NOT from deleting the retrain control or the sweep control.
N14. Build the appendix, 4-5 pages: hyperparameter table, reproducibility,
     compute/hardware, parameter table, remaining ablation details. Most of it
     ports from the archival's Appendix A + B and its Table 1.
N15. Kill every "supplementary" promise - it will not ship. FOUR live sites:
     paper/sim2science/main.tex:536-544 (the whole Data-and-code paragraph) and
     checklist.tex:64 (Q4) and :84 (Q5). The other `supplement` hits in
     checklist.tex are template boilerplate, not our text.
N16. Checklist: move it to body -> references -> CHECKLIST -> appendix, and fix
     Q8 (compute), which currently answers No. ASK ME for CPU/GPU, RAM and rough
     runtime - nobody else can supply them. He is fine with stating positively
     that something was not logged. Remember checklist.tex is verified by NO
     checker.
N17. Soften the headline claim to his wording: "the practical recovery of the
     physical coefficient from this flexible closure under the tested objectives
     and distillation procedures". THIS IS A CLAIM CHANGE: update
     paper/consistency.yaml FIRST, then run python scripts/check_consistency.py
     and let it name EVERY site in BOTH manuscripts. Do NOT delete the
     functional-identifiability vocabulary - he asked for it in review 1 and two
     consistency groups probe on it.
N18. Check the Sim2Science site on the footer. DO NOT pass `final` to make the
     footer name the workshop: neurips_2026.sty:49-51 sets \@anonymousfalse and
     would print the real byline. \workshoptitle{Sim2Science} is already set.
N19. Re-audit ONLY what N13-N17 changed, re-run all eleven checkers, rebuild the
     bundle. Do not re-audit the untouched body - Sec 13 has the axis ledger.
N20. Send the revised draft back to Prathamesh; he expects one more look.
     paper/draft-email-N9-prathamesh.md is the previous note and the house style.
N10. Then nominate him (ID: ~Prathamesh_Dinesh_Joshi1) and submit.
F3.  git tag -a sim2science-submitted on the commit whose bundle produced the
     UPLOADED pdf (not a later one), then push the tag.
F4.  Add the FROZEN banner to paper/sim2science/main.tex. See the F-series.

--- WHAT WE SUBMIT (get this wrong = desk reject) ---
  ONE pdf now, not two: body <= 5 pages + references + checklist + appendix.
  Compile sim2science_upload/main.tex; the SOURCE to edit is
  paper/sim2science/main.tex (+ paper/sim2science/checklist.tex).
  sim2science_upload/ is BUILD OUTPUT, destroyed by every
  make_sim2science_bundle.py run - a hand-edit there is lost silently.
  NEVER upload a pdf built from paper/main.tex itself: it carries the real
  byline, affiliations and emails.
  supplementary.tex keeps being GENERATED (it is the anonymised archival and the
  cross-check target) but is no longer submitted. Do not delete that path.

--- AFTER THE DEADLINE ---
  A11 Prathamesh's second round on the ARCHIVAL paper.
  P1-P9 presentation pass on the archival - P1 first (AI-tells, the title he
      called AI-generated, and the \shorttitle at main.tex:194 which states the
      negative result flatly while the title asks a question; the abstract's
      closing sentence is the same accent). BOTH are known and deliberately
      deferred - do not "discover" them.
  A10 archival destination: arXiv, a journal, or both.
  A12 restore what the cut dropped. D4 (author-overlap disclosure) is MANDATORY.
  D3  add neurips_2026.sty + checklist.tex to the LICENSE carve-out.
  T4-T8 fresh repo (COPY files into a new git init, never clone - the old history
      carries a private Overleaf URL and verbatim mentor quotes), repo URL,
      Zenodo DOI, commit SHA, README citation block. Law I applies: a URL, a DOI
      and a SHA all carry digits, so each needs a "% numok:" at the TRUE END of
      its line. These also replace the TODO- placeholders paper/main.tex still
      (correctly) holds.
  THREE CHECKER GAPS, all specced in Sec 8:
      (a) scripts/check_undefined_macros.py - nothing verifies a command USED is
          DEFINED. Eleven checkers passed a document that would not compile.
      (b) check_claims.py has NEVER run against the 5-page cut (one flag).
      (c) checklist.tex is verified by NOTHING and ships inside the pdf.
  D1  regenerate fig2/fig3/fig6 from the corrected "state propagation" title.
      TRAINING run, needs my greenlight. N13 may force this earlier.
  39 MINOR/NIT findings in paper/audit-2026-08-21-round2.json. None is a blocker.

--- DEFERRED WITH REASONS (do not start without asking me) ---
  closure-ladder experiment; multiple-trajectory positive control;
  multiple-shooting / curriculum horizon. All follow-up-paper scope.

--- HOW THIS PAPER IS BUILT ---
- Law I: every reported number is a \val macro from paper/generated/metrics.tex,
  traced via paper/metrics_map.yaml to a results CSV. Fixed INPUTS are preamble
  \newcommands with a source comment. Literals need "% numok:" at the TRUE END
  of the line, with a space before the %.
- Law II: every claim lives in paper/claims.yaml, anchored as "% claim: <id>".
  The `scope` fields are where over-claiming dies; read them before judging any
  claim.
- The supplementary/archival anonymisation is GENERATED by
  scripts/make_sim2science_bundle.py, which REFUSES to write if any identifying
  string or TODO- placeholder survives. Never hand-maintain a second copy; fix
  the BUNDLER.
- The two preambles share fixed-input macros; check_workshop_cut.py FAILS if any
  shared macro has a different body. Keep them byte-identical.
- When you change a claim: update paper/consistency.yaml FIRST, then run
  check_consistency.py and let it name EVERY site in BOTH manuscripts. Fixing the
  site I point at and not its siblings is this project's single most common
  failure mode. A group whose `require` is an OR is a FLOOR, not a ceiling.

--- HARD-WON GOTCHAS ---
- NEVER write LaTeX or regex through a shell heredoc, and never through
  `python -c` either. Backslashes get eaten. Write the script or patch to disk
  with the Write tool, then run it.
- consistency.yaml `require` regexes must use \s+ between words, never a literal
  space: the checker joins context with ' '.join().
- A "% numok:" or "% claim:" comment placed MID-LINE silently deletes the rest
  of that line. Put them at the TRUE end.
- Editing ANY .jl file shifts provenance pointers. Keep the LINE COUNT identical
  and re-run check_provenance_refs.py.
- The code says "state propagation"; the committed PNGs still say "state
  reconstruction". Deliberate and temporary - Sec 4j, decision D1. Only fig5's
  caption in the archival discloses it, because only that caption denies the
  word. N13 may make this acute.
- Two BibTeX warnings are EXPECTED and must not be "fixed": pal2023lux and
  dixit2023optimization. Sec 8 explains why.
- A subagent CAN fabricate a computed result. Round 9 had one report a fit it
  could not have run (no CSV holds the closure's per-point output). Check the
  INPUT exists before believing the output.

--- GROUND RULES ---
- I am the committer. NO Claude co-author. Commit/push only when I ask.
- NEVER commit: main.jl, Main_Clean.jl, "Paper Writing Skills/", .claude/,
  __pycache__/, overleaf_upload/, overleaf_upload.zip, sim2science_upload/.
- HANDOFF.md is gitignored and snapshot-only; archive with
  scripts\snapshot_handoff.ps1 -Push before pushing.
```
