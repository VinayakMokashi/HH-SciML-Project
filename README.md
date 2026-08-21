# Identifiability Limits of UDEs in a Hodgkin-Huxley Neuron

Code, trained-network parameter snapshots, and every results table behind the paper
*"When Can Scientific Machine Learning Recover a Hidden Ionic Current? Identifiability
Limits of Universal Differential Equations in a Hodgkin-Huxley Neuron"* (`paper/main.tex`).

**What the work shows.** A UDE that replaces the calcium current of a six-state
Hodgkin-Huxley model with a neural closure forecasts held-out voltage accurately and
reproduces the shape of the hidden current, but does **not** recover its conductance.
The reason is not a shortage of data: a direct two-parameter fit of `(gCa, ECa)` to the
*same* single noisy trajectory recovers `gCa` to about six per cent. Parametric
identifiability holds; functional identifiability fails. The data confine the conductance
to a short, bounded stretch of the `gCa`-`ECa` trade-off, and the estimates read off the
closure scatter well beyond it. The two arms also differ in objective and optimiser, not
only in representation: a matched-objective control attributes a roughly threefold
inflation to the objective alone, and because it holds the optimiser fixed it bounds the
representation's own contribution at about a further factor of two rather than measuring
it.

---

## Licence

A two-part split, because code and evidence want different terms:

| What | Licence | File |
|---|---|---|
| **Software** — `src/`, the root `*.jl` entry points, `scripts/`, and our own LaTeX under `paper/` | MIT | [`LICENSE`](LICENSE) |
| **Evidence** — `results/` (every metric CSV and every `.jld` trained-parameter snapshot) and `figures/` (including the staged copies in `paper/figures/`) | CC BY 4.0 | [`LICENSE-DATA`](LICENSE-DATA) |

MIT because it is the shortest thing that works and it matches the Julia and SciML
ecosystem this builds on; CC BY 4.0 because the evidence is what a reader would want to
reuse, and attribution is the only condition worth attaching to it.

**Two files are covered by neither, and are not ours to relicense:**

- `paper/arxiv.sty` — vendored from [kourgeorge/arxiv-style](https://github.com/kourgeorge/arxiv-style)
  under its own MIT copyright; the provenance stamp is in the file header.
- `Vizuara_Paper_HH.pdf` — a third-party publication (Kainth et al., MSML 2025), kept here
  only as a reading reference. All rights remain with its authors and publisher.

Keep this section, `LICENSE`/`LICENSE-DATA`, and the paper's Data and Code Availability
section in sync: a licence change is a three-place edit.

---

## Requirements

| Component | Version | Used for |
|---|---|---|
| Julia | 1.6.7 (pinned; `Manifest.toml` is resolved against it) | every `*.jl` entry point |
| Python | 3.x, standard library only (no numpy/pandas needed) | `scripts/*.py` |
| Windows PowerShell | 5.1 | `scripts/*.ps1` (figure staging, Overleaf bundle) |
| LaTeX | any TeX Live / Overleaf with `natbib`, `hyperref`, `subcaption`, `tikz` | `paper/main.tex` |

The Julia environment is pinned. `Lux` is at 0.5.14, where `LayerNorm` requires a matrix
input; do not update the manifest without re-running the pipeline.

## Setup

```
git clone <this repository>
cd HH-SciML-Project
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

Python helpers need no environment:

```
python scripts/summarize_node_parity.py
```

Run every command **from the repository root**. All scripts resolve their paths against
their own file location, but the PowerShell helpers assume the root as the working
directory.

---

## `HH_SMOKE=1` is isolated, but read this before using it

`HH_SMOKE=1` is a *pipeline* check: tiny iteration budgets and reduced grids, so it
exercises every code path in minutes and produces numbers that mean nothing.

**Its output is isolated.** `src/experiment.jl` redirects the whole output tree under
smoke, so a smoke run writes to `results_smoke/` and `figures_smoke/` and cannot touch the
published `results/` and `figures/`. This was not always true: before 2026-08-20 the paths
were unconditional, and a smoke run truncated `results/metrics_all.csv` from 696 rows to
321 and modified 63 other tracked files. If you are on an older checkout, assume the
destructive behaviour.

Two things the isolation does *not* cover:

- `gca_sweep_5seed.jl` and `node_parity.jl` write **append-only** CSVs. Their summarize
  scripts dedupe keeping the **last** row per key, so a stray row appended last silently
  wins. Re-run the matching `scripts/summarize_*.py` after any partial run.
- `retrain_gca2_20k.jl` has its own switch, `RETRAIN_OUT`, which is what the `gCa = 0.4`
  negative control uses to write to a separate tree.

Whatever you run, check `git status` afterwards. Nothing under `results/` should change
unless you meant it to.

---

## Ordered entry points

Step 1 comes first; every other step names what it depends on. Wall-clock figures are for
the full (non-smoke) configuration.

| # | Command | Writes | Depends on | Cost |
|---|---|---|---|---|
| 1 | `julia --project=. experiments_runner.jl` | `results/metrics_all.csv`, `results/metrics_baseline{,_multiseed}.csv`, `results/ablation_*.csv`, `results/calcium/*.csv`, `results/params/*.jld`, `figures/fig2*,fig3*,fig5,fig6*,fig7*,fig8*,07_*,08_*` | - | ~26 trainings, 3-6 h |
| 2 | `julia --project=. objective3_symbolic.jl` | `results/symbolic/{symbolic_recovery_metrics.csv,sindy_coefficients.csv,learned_calcium_equation.txt}`, `figures/fig9..fig12*` | step 1 (`results/calcium/` probe and grid CSVs) | minutes |
| 3 | `julia --project=. retrain_gca2_20k.jl` | `results/retrain_gca2_20k/{metrics_retrain.csv,calcium/,params/}` | step 1 | ~4x step 1's per-run cost, 5 seeds |
| 4 | `julia --project=. objective3_symbolic_retrain.jl` | `results/retrain_gca2_20k/{symbolic/,figures/}` | step 3 | minutes |
| 5 | `julia --project=. identifiability_parametric.jl` | `results/identifiability/{parametric_fit.csv,loss_surface_gca*.csv,profile_{gca,eca}_gca*.csv,conditioning.csv}` | - (uses the true model, not the trained networks) | ~1 h |
| 6 | `NODE_VARIANTS=autonomous julia --project=. node_parity.jl` then `NODE_VARIANTS=timeinput julia --project=. node_parity.jl` then `python scripts/summarize_node_parity.py` | `results/node_parity/{metrics_node_parity.csv,run_log_*.csv,node_parity_summary.csv}` | - | ~10x a UDE training per run; split across processes on purpose |
| 7 | `julia --project=. gca_sweep_5seed.jl` then `python scripts/summarize_gca_sweep.py` | `results/gca_sweep_5seed/{metrics_gca_sweep.csv,run_log.csv,gca_sweep_multiseed.csv}` | step 1 (fills only the seeds step 1 did not run) | hours |
| 8 | `julia --project=. recover_training_losses.jl` | `results/identifiability/training_losses_before_after.csv` | steps 1 and 3 (reads saved parameters; no retraining) | minutes |
| 9 | `julia --project=. recover_voltage_only_commoneval.jl` | `results/identifiability/voltage_only_commoneval.csv` | step 1 (no retraining) | minutes |
| 10 | `python scripts/symbolic_domain_comparison.py` | `results/identifiability/symbolic_domain_comparison.csv` | step 1 (`results/calcium/probe_*.csv`) | seconds |
| 11 | `RETRAIN_GCA=0.4 RETRAIN_SEEDS=1111 RETRAIN_OUT=retrain_gca04_20k julia --project=. retrain_gca2_20k.jl` then `python scripts/gca04_retrain_control.py` | `results/retrain_gca04_20k/`, `results/identifiability/gca04_retrain_control.csv` | step 1 | one long training |

### Plotting-only steps (nothing is refit)

| Command | Produces | Reads |
|---|---|---|
| `julia --project=. figure_identifiability.jl` | `figures/fig13_parametric_identifiability.png` | `results/identifiability/{loss_surface_gca2.0.csv,profile_gca_gca2.0.csv,parametric_fit.csv,symbolic_domain_comparison.csv}` |
| `julia --project=. figure_gca_sweep_5seed.jl` | `figures/fig7c_ablation_gca_5seed.png` | `results/gca_sweep_5seed/gca_sweep_multiseed.csv` |
| `julia --project=. figure_coeff_recovery_panels.jl` | `figures/fig11_coeff_recovery_{before,after}.png` **and stages both into `paper/figures/` itself** | `results/symbolic/symbolic_recovery_metrics.csv`, `results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv` |
| `julia --project=. regen_fig2.jl` | `figures/fig2_neural_ode_overview.png` alone | retrains the one published-configuration neural ODE; use when the `HH_REPLOT` pipeline hangs on its last step |

### Paper build

```
powershell -ExecutionPolicy Bypass -File scripts\stage_figures.ps1
powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1
python scripts/check_tex_sanity.py
python scripts/check_bib_sanity.py
python scripts/verify_references.py      # network: Crossref, DataCite, arXiv
```

`stage_figures.ps1` copies the paper's images into the single directory
`paper/figures/` under disambiguated names, because the baseline and the
aggressive-retrain trees both contain `fig9..fig12` under identical basenames and they
tell opposite stories. The `_before` / `_after` suffix means **training budget**
(5000/300 vs 20000/1000), not `gCa`, noise, or window. The two
`fig11_coeff_recovery_*` panels are deliberately *not* in its map: their generator
stages them. After copying, the script re-reads `main.tex` and fails if any
`\includegraphics` target is missing.

---

## Environment switches

| Variable | Read by | Effect |
|---|---|---|
| `HH_SMOKE=1` | `experiments_runner.jl`, `gca_sweep_5seed.jl`, `node_parity.jl`, `identifiability_parametric.jl`, `retrain_gca2_20k.jl` | tiny iteration budgets and reduced grids for a fast pipeline check. **Destructive: writes over the published `results/` and `figures/`. See the warning above.** |
| `HH_REPLOT=1` | `experiments_runner.jl` | skip all training; rebuild the derived CSVs and summary figures from the existing `results/metrics_all.csv`. Its last step (`run_node_baseline`) is a known hang on this stack; every other figure is written before it, so kill the job once figure mtimes stop advancing and use `regen_fig2.jl` for that one panel. |
| `IDENT_PARTS=1,2,3,4` | `identifiability_parametric.jl` | select which parts run: 1 parametric fit, 2 loss surface, 3 profile likelihoods, 4 conditioning. Default all four. |
| `NODE_VARIANTS=autonomous,timeinput` | `node_parity.jl` | which neural-ODE variants to train. Each value set writes its own `run_log_<variants>.csv`, so two variant-restricted processes can run concurrently without clobbering the log. Default both. |
| `NODE_SEEDS=1111,2222,3333,4444,5555` | `node_parity.jl` | seed list. Default all five. Overridden to a single seed under `HH_SMOKE`. |
| `RETRAIN_GCA=2.0` | `retrain_gca2_20k.jl` | true `gCa` for the aggressive retrain. Default `2.0` reproduces the published run. When it is not `2.0`, the script skips the baseline `gCa=0.4` probe copy, which previously made a negative control look like a successful replication. |
| `RETRAIN_SEEDS=1111,...` | `retrain_gca2_20k.jl` | seed list. Default all five. |
| `RETRAIN_OUT=retrain_gca2_20k` | `retrain_gca2_20k.jl` | output subdirectory under `results/`. The only isolation switch in the repository. |

On PowerShell, set these as `$env:HH_SMOKE = "1"` before the command; the inline
`VAR=value cmd` form is a bash-ism and is a parse error in PowerShell.

---

## Where each paper table and figure comes from

Paper item numbers are the numbers as printed in `paper/main.tex`. Every number in the
paper is a `\val...` macro defined in `paper/generated/metrics.tex` and traced to a cell
of a committed CSV by `paper/metrics_map.yaml`; the mapping below is that file, grouped
by where the values surface.

### Tables

| Paper item | Produced by | Results file(s) it reads |
|---|---|---|
| Table 1 - model constants and provenance | none; literal constants | `src/hh_core.jl`, mirrored once each as `\newcommand`s in the `main.tex` preamble with a source-line comment. No CSV. |
| Table 2 - forecast performance | `experiments_runner.jl`; `node_parity.jl` + `scripts/summarize_node_parity.py` | `results/metrics_baseline_multiseed.csv` (UDE rows), `results/node_parity/node_parity_summary.csv` (all three neural-ODE rows) |
| Table 3 - direct parametric estimation | `identifiability_parametric.jl`; `objective3_symbolic.jl`; `scripts/symbolic_domain_comparison.py`; `scripts/gca04_retrain_control.py` | `results/identifiability/parametric_fit.csv`, `results/identifiability/conditioning.csv`, `results/identifiability/symbolic_domain_comparison.csv`, `results/identifiability/gca04_retrain_control.csv`, `results/symbolic/symbolic_recovery_metrics.csv` |
| Table 4 - aggressive-retrain control | `objective3_symbolic.jl` (before); `retrain_gca2_20k.jl` + `objective3_symbolic_retrain.jl` (after); `recover_training_losses.jl`; `experiments_runner.jl` | `results/symbolic/symbolic_recovery_metrics.csv`, `results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv`, `results/retrain_gca2_20k/metrics_retrain.csv`, `results/identifiability/training_losses_before_after.csv`, `results/metrics_baseline_multiseed.csv` |

### Figures

`main.tex` sets `\graphicspath{{figures/}}` and is compiled from inside `paper/`, so every
name below is resolved against `paper/figures/` after staging.

| Paper item | Staged filename | Produced by | Results file(s) it reads |
|---|---|---|---|
| Figure 1 - schematic | none (inline TikZ in `main.tex`) | - | - |
| Figure 2a - neural ODE overview | `fig2_neural_ode_overview.png` | `experiments_runner.jl` (or `regen_fig2.jl` alone) | trained in place; metrics to `results/metrics_all.csv` |
| Figure 2b - UDE overview | `fig3_ude_overview.png` | `experiments_runner.jl` | as above |
| Figure 3 - train vs forecast bars | `fig5_metrics_bar_train_vs_forecast.png` | `experiments_runner.jl` | `results/metrics_all.csv` |
| Figure 4 - voltage-only overview | `fig6_voltage_only_overview.png` | `experiments_runner.jl` | trained in place |
| Figure 5 - conductance sweep, five seeds | `fig7c_ablation_gca_5seed.png` | `figure_gca_sweep_5seed.jl` | `results/gca_sweep_5seed/gca_sweep_multiseed.csv` |
| Figure 6a - symbolic parity (baseline budget) | `fig9_symbolic_parity_before.png` (staged from `figures/fig9_calcium_symbolic_parity.png`) | `objective3_symbolic.jl` | `results/calcium/` probe and grid CSVs |
| Figure 6b - coefficient recovery, hull domain, baseline budget | `fig11_coeff_recovery_before.png` | `figure_coeff_recovery_panels.jl` (stages itself) | `results/symbolic/symbolic_recovery_metrics.csv` |
| Figure 7 - parametric identifiability, three panels | `fig13_parametric_identifiability.png` | `figure_identifiability.jl` | `results/identifiability/{loss_surface_gca2.0.csv,profile_gca_gca2.0.csv,parametric_fit.csv,symbolic_domain_comparison.csv}` |
| Figure 8a - window ablation on the shared window | `fig7b_commoneval_ablation_window.png` | `experiments_runner.jl` | `results/metrics_all.csv` |
| Figure 8b - coefficient recovery, hull domain, aggressive budget | `fig11_coeff_recovery_after.png` | `figure_coeff_recovery_panels.jl` (stages itself) | `results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv` |
| Noise ablation, appendix | `fig7_ablation_noise.png` | `experiments_runner.jl` | `results/ablation_noise.csv` |

`figures/` holds roughly forty-five images; the paper prints the eleven above.
Figure numbering in this table follows an earlier layout; several subfigure pairs
were later split into standalone figures, so treat the descriptions rather than
the numbers as authoritative.
`fig10` and `fig12` are produced by the symbolic pipeline but are not printed.

**Domain caution.** Figures 6b and 8b are fitted on the **convex hull** of the closure's
input domain, and say so in the panel supertitle and in the caption. Every conductance
estimate quoted in the paper's prose is on the **supervised trajectory** instead. The two
domains give different numbers; do not swap one for the other when reading a CSV.

---

## Repository layout

```
src/hh_core.jl                model and data builders; gCa, noise level and window are
                              closure arguments, not consts (a non-const global in the
                              hot right-hand side wrecks adjoint performance on 1.6.7)
src/metrics.jl                RMSE, spike detection, rollout horizon, tidy metric rows
src/experiment.jl             run_experiment (UDE), run_node_baseline (NODE), figure and
                              calcium-probe savers, parameter reload
experiments_runner.jl         the sweep; also builds the fig7* ablation figures
objective3_symbolic*.jl       SINDy distillation of the trained closure
identifiability_parametric.jl direct (gCa, ECa) fit, loss surface, profiles, conditioning
node_parity.jl                neural-ODE controls at the UDE's budget
gca_sweep_5seed.jl            fills the missing seeds of the conductance sweep
retrain_gca2_20k.jl           aggressive-budget retrain into an isolated tree
recover_*.jl                  post-hoc measurements from saved parameters; no retraining
figure_*.jl                   plotting only
scripts/*.py                  summarizers, domain comparison, LaTeX and BibTeX checkers
scripts/*.ps1                 figure staging and the Overleaf bundle
results/                      committed quantitative evidence: metric CSVs and the .jld
                              trained-network snapshots the paper's numbers come from
figures/                      all generated figures
paper/                        main.tex, references.bib, generated/metrics.tex,
                              metrics_map.yaml, claims.yaml, claim-guards.md,
                              citations-audit.md, arxiv.sty (vendored), figures/
```

## Provenance chain

Three ledgers keep the paper honest, and all three are committed here:

- `paper/metrics_map.yaml` maps every reported number to a cell of a CSV under `results/`.
- `paper/generated/metrics.tex` is the extracted macro file the paper `\input`s. **Do not
  edit it by hand.**
- `paper/claims.yaml` is the claim ledger; each claim is anchored in the prose as a
  `claim` comment and carries a scope, its evidence, and a status.

**Not included:** the extraction and checking tooling (`extract_metrics.py`,
`check_numbers.py`, `check_claims.py`, `lint_prose.py`) lives in a separate private
repository. `paper/generated/metrics.tex` and `metrics.json` are committed, so the paper
compiles and every number remains traceable to a CSV by reading `metrics_map.yaml`; but
re-running the automated traceability check requires that tooling. The checkers that
*are* here (`scripts/check_tex_sanity.py`, `scripts/check_bib_sanity.py`,
`scripts/verify_references.py`) can be run by anyone.

## Known issues

- `run_node_baseline` can hang on this stack; it is the last step of `HH_REPLOT=1`. Kill
  the job once figure mtimes stop advancing and use `regen_fig2.jl`.
- `metrics_gca_sweep.csv` and `metrics_node_parity.csv` are append-only and may contain
  superseded rows. Always dedupe keeping the last row per
  `(model, observed, gCa, noise_level, t_train_end, seed, window, metric)`; the
  `summarize_*` scripts do this.
- Background Julia runs are block-buffered; use file mtimes as the progress signal.
- Plots emits benign `seriescolor does not match data indices` warnings on error-bar
  figures.
- Keep `.ps1` files ASCII-only. PowerShell 5.1 reads a `.ps1` as ANSI unless it has a BOM,
  and a single non-ASCII character in a comment kills the parser with an error reported
  nowhere near it.

## Citing

> **[TODO - AUTHOR]** Add the citation for the paper and, once the archived snapshot
> exists, its DOI. Keep this block in sync with the paper's Data and Code Availability
> section.
