# Claim guards — the HH SciML paper

Every number in `results/` that is *tempting* and *wrong* is listed here, once, with the honest
replacement already written. This file exists because the HH project's evidence base is closed
(no new experiments) and its most quotable numbers are its most misleading ones: a saturated
censored metric, a diverged integration with error bars, and an "ensemble" estimator that is
algebraically the mean it is being compared against. A drafter reading `HANDOFF.md` §3/§3b and
transcribing its table would ship at least six unsupportable claims.

**How this file is used.** In **Claims**, every entry in `claims.yaml` whose evidence touches a
trapped number carries `guard: <guard-id>` pointing at a section below; a claim that cannot be
phrased to satisfy its guard gets `status: overreaching` and does not enter the paper. In
**Verify**, `check_claims.py` fails the build on any `status: overreaching` claim and surfaces the
guard id so the reviewer sees the honest rewrite next to the offending sentence. Guard ids are
kebab-case, stable, and referenced by id only — never by number (`G7` is a reading aid; the id is
the contract).

> **Id-sync invariant.** The `Guard id:` of every section below is the id `claims.yaml` references in
> its `guard:` field. `claims.yaml` is the machine-parsed side of this link, so **it owns the ids and
> this file follows**. Two directions of breakage, both silent until `check_claims.py` runs:
> a guard here that no claim references is fine (guards G7–G9, G11, G14, G15, G17, G18 forbid
> sentences rather than qualify claims); a `guard:` in `claims.yaml` with **no section here** is a
> dangling ref and a bug. Checked with:
>
> ```bash
> python -c "import re,yaml; \
> g={c['guard'] for c in yaml.safe_load(open('claims.yaml',encoding='utf-8'))['claims'] if c.get('guard')}; \
> m=set(re.findall(r'\*\*Guard id:\*\* \`([a-z0-9-]+)\`', open('claim-guards.md',encoding='utf-8').read())); \
> print('dangling (FAIL):', g-m or 'none'); print('unreferenced (ok):', sorted(m-g))"
> ```

**Every value below was re-verified against the real CSVs** [verified, 2026-07-16] by direct
recomputation, not copied from a brief. Where a guard is not in the contract §9 enumeration it is
marked as such.

**Use as a pre-submission checklist:** grep the `.tex` for each guard's forbidden pattern (given
per guard) before building. All clean ⇒ the trapped numbers are safe.

---

### G1: The rollout horizon is censored, not measured

**Tempting claim.** `HANDOFF.md` §3 table: `UDE full-state (Obj 2) | ... | rollout 70 ms (max)`,
and the multiseed CSV's literal `rollout_horizon_ms = 70.0 ± 0.0`. A drafter writes: *"the UDE
forecasts accurately for 70 ± 0 ms."*

**Why it is wrong.** `70.0` is the constant `cap_ms` in `rollout_horizon` (`src/metrics.jl:81-82`).
The function returns `cap_ms` when `|Vpred − Vtrue|` **never** breaches 10 mV for ≥1 ms — i.e. `70.0`
is the sentinel for *"never failed"*, not a duration that was observed. And `70 = 100 − 30` is the
**entire remaining trajectory** past `t_train_end=30`: there is no data after t=100, so the metric
*cannot* return more than 70 here. All 5 seeds × both observation settings return exactly `70.0`
(verified: 10/10 rows). The metric is saturated and non-discriminating — `± 0.0` is a std over five
copies of a constant, and reads as spurious precision (zero uncertainty on the paper's best number).
Second hazard: the cap is a hard `70.0` while the *available* span is `100 − t_start`. Every
`common_eval` scoring has `t_start = 50`, so only 50 ms exist — yet a non-breaching run still reports
`70.0`, **a horizon longer than the window it was measured in**.

**The evidence.** `results/metrics_baseline_multiseed.csv`, filter `window==forecast ∧
metric==rollout_horizon_ms`: UDE/full `mean=70.0, std=0.0, n_seeds=5`; UDE/voltage `mean=70.0,
std=0.0, n_seeds=5`. Per-seed from `results/metrics_all.csv` filter `model==UDE ∧ window==forecast ∧
metric==rollout_horizon_ms ∧ @base`: `70.0, 70.0, 70.0, 70.0, 70.0` for both `observed` values.
Cap constant: `src/metrics.jl:81` (`cap_ms = 70.0`, `thresh_mv = 10.0`, `sustained_ms = 1.0`).

**Honest rewrite.**
> The UDE never leaves the 10 mV error tube: across all five seeds the rollout horizon saturates the
> 70 ms measurement cap (the full extent of the simulated trajectory past the training window), so we
> report it as ≥70 ms. The metric is right-censored at the horizon of the data and cannot distinguish
> among seeds or between observation settings.

Emit via `emit: ge` with `censored_at: 70.0` (contract §6) → renders `\ge 70`. Never emit `mean_std`
for this metric.

**Grep before submit:** `70 \pm 0`, `70.0 \pm`, `70 ms` not preceded by `\ge`/"at least"/"cap".

**Guard id:** `rollout-is-censored`

---

### G2: The NODE's forecast RMSE is a divergence, not a measurement with error bars

**Tempting claim.** `HANDOFF.md` §3 table, verbatim:
`| Neural ODE (Obj 1) | 3951 ± 3561 (diverges) | 22.4 ± 23 | 0.55 ± 0.65 ms |`.
A drafter transcribes: *"the Neural ODE achieves a forecast V RMSE of 3951 ± 3561 mV."*

**Why it is wrong.** Three compounding defects.

1. **The distribution is not a distribution.** Per-seed: `4122.7, 229.1, 1134.0, 5056.6, 9213.4` mV —
   a **40.2× spread** (max/min, verified). A mean±std summarises a location and a scale; here neither
   exists. The std (3561) is 90% of the mean and the sample is manifestly non-normal. Writing `±`
   asserts a symmetric error model that the data refutes.
2. **The numbers are the finite residue of a blown-up solve.** `rmse_safe` (`src/metrics.jl:20-25`)
   drops non-finite pairs and averages over survivors only, by design ("the black-box Neural ODE
   forecast blows up to ±1e4 / NaN; we still want a meaningful RMSE on the finite part"). There is no
   `n_finite` column, so **the denominator is unreported and varies by seed**. `3951` is an average
   over an unknown subset of an integration that failed.
3. **The magnitude is physically meaningless.** A membrane potential RMSE of 10³–10⁴ mV on a model
   whose true V spans ≈[−80, 40] mV is not "large error", it is "the ODE left the manifold". Quoting
   it as a metric invites a reviewer to ask why you tuned a baseline to 4000 mV.

The honest measurement is the rollout horizon, which is bounded and interpretable: NODE
`0.5479 ± 0.6549` ms, per-seed `0.783, 0.0, 0.391, 1.566, 0.0`. With `dt ≈ 0.1957` ms, the NODE
leaves the tube within **one to eight samples**, and **two of five seeds report exactly `0.0` — they
breach at the very first forecast sample.** That is the result.

**The evidence.** `results/metrics_baseline_multiseed.csv` filter `model==NODE ∧ observed==full ∧
window==forecast`: `V_rmse mean=3951.178018885416 std=3561.340803031814 n_seeds=5`;
`rollout_horizon_ms mean=0.5479452054794521 std=0.6549197859366547 n_seeds=5`;
`gate_rmse_mean mean=22.422765 std=23.426121 n_seeds=5` (same defect — std ≈ mean).
Per-seed from `results/metrics_all.csv` filter `model==NODE ∧ window==forecast ∧ metric==V_rmse ∧
@base` (all 5 verified above). `rmse_safe`: `src/metrics.jl:20-25`.

**Honest rewrite.**
> The Neural ODE fits the training window but its forecast diverges: the integrated trajectory leaves
> the ±10 mV error tube after 0.55 ± 0.65 ms (per-seed 0.0–1.57 ms; two of five seeds breach at the
> first forecast sample), after which the solution blows up to O(10²–10⁴) mV across seeds. We report
> the rollout horizon rather than a forecast RMSE: post-divergence RMSE is computed over only the
> finite samples of a failed solve and is not a meaningful error scale.

If a reviewer demands a magnitude, give the **range across seeds** (`10²–10⁴ mV`), never a mean±std.

**Grep before submit:** `3951`, `3561`, `22.4`, `± 23`.

**Guard id:** `node-no-meanstd`  *(id fixed by contract §6 `claims.yaml` schema example)*

---

### G3: The "ensemble" coefficient is the per-seed mean, not a second estimate

**Tempting claim.** `HANDOFF.md` §3b: *"Ensemble coefficients: **a = gCa ≈ 1.60** (true 2.0 …), **b ≈
−259**"*, alongside `results/symbolic/learned_calcium_equation.txt` lines 6-7 which print
`per-seed a = 1.596 +/- 0.905` and `ensemble a = gCa ~ 1.596` as if they were two results. A drafter
writes: *"the per-seed and pooled ensemble fits agree closely (a = 1.596 vs 1.596), confirming the
estimate is stable."*

**Why it is wrong.** They agree to six decimal places because **they are the same number by
algebra**, and "agreement" between a quantity and itself is not evidence. The mechanism:
`data_clean` depends only on `gCa` (`gen_clean_data(gCa)`, `src/hh_core.jl`), so all 5 seeds at
gCa=2.0 share **one clean trajectory**, hence **one convex hull**, hence **one hull-masked grid**,
hence **one design matrix** `Φ = [V·s², s²]`. The pooled fit stacks that identical `Φ` five times
against five different targets `yᵢ`:

```
β_ens = (Φ_stacked' Φ_stacked)^{-1} Φ_stacked' y_stacked
      = (5·Φ'Φ)^{-1} · Φ'(Σᵢ yᵢ)
      = mean_i (Φ'Φ)^{-1} Φ' yᵢ  =  mean_i(βᵢ)
```

Pooling stacked copies of one design **is** averaging. Presenting both lines double-counts a single
estimator and manufactures a false corroboration — precisely the kind of thing a hostile reviewer
enjoys finding.

**What is genuinely different is `Erev`**, and only `Erev`, because `−b/a` is a **nonlinear ratio**:
ratio-of-means ≠ mean-of-ratios. Verified: `mean_i(−bᵢ/aᵢ) = 222.94` mV versus
`−mean(b)/mean(a) = 162.53` mV — a 60 mV gap between the two ways of averaging. The code's comment
(`objective3_symbolic.jl:197-198`, "the per-seed ratio −b/a is noisy when a is small, so we report
the pooled value") states the *correct* and *only* justification. Frame it as a coefficient-ratio
convention, not an ensemble fit.

**The evidence.** `results/symbolic/symbolic_recovery_metrics.csv`, filter `gCa==2.0` (5 rows):
`mean(a_hat) = 1.595550`, `mean(b_hat) = -259.332393`. Ensemble (not in any CSV; parsed from
`results/symbolic/learned_calcium_equation.txt` line 7, and independently recomputed from the pooled
hull-masked grid probes): `a_ens = 1.595550`, `b_ens = -259.3324` — identical to 6 dp.
Fit code: `objective3_symbolic.jl:199-202`. Same identity holds in the retrain tree
(`1.494710` both ways).

**Honest rewrite.**
> Because the clean trajectory depends only on gCa, all five seeds share one convex hull and one
> design matrix, so the pooled fit is algebraically identical to the per-seed mean of the
> coefficients (a = 1.5956 either way). We therefore report per-seed coefficients with their spread,
> and use the pooled fit only for the reversal potential, where −b/a is a nonlinear ratio and the
> per-seed ratios are unstable when a is small (mean of per-seed ratios: 222.9 mV; ratio of mean
> coefficients: 162.5 mV).

Report **one** estimator for `a` and `b`. Never place per-seed and ensemble side by side as
agreeing evidence.

**Grep before submit:** `ensemble`, `pooled` near `a =` / `b =`; any sentence containing both
`1.596` and `1.60` as separate quantities.

**Guard id:** `ensemble-is-not-independent`

---

### G4: R²_ens = 0.997 is uninformative and must not headline recovery quality

**Tempting claim.** `HANDOFF.md` §3b: *"the learned calcium current is recovered as the conductance
form `I_Ca = s²(aV + b)`, matching the true current at **R² = 0.997 (ensemble)** / 0.984 ± 0.015
(per-seed)."* A drafter leads with `R² = 0.997`.

**Why it is wrong.** `R2_ens` is `r2(pooled symbolic fit, pooled **true** current)` evaluated on the
shared hull grid (`objective3_symbolic.jl:202`). Because every seed shares that geometry, the
statistic mostly scores *"can the form s²(aV+b) fit gCa·s²(V−ECa) on this domain?"* — which it can,
essentially by construction, since the truth is exactly in the model class. It is close to a
tautology dressed as a fit quality.

**The proof that it measures nothing:** the aggressive retrain made per-seed recovery **collapse**
from `r2_cond_true = 0.983586 ± 0.014494` to `0.845475 ± 0.160284` — a catastrophic, 10×-noisier
degradation — while `R2_ens` moved from `0.997333` to `0.997341`, i.e. **in the fifth decimal
place**. A statistic that cannot detect that collapse cannot certify the recovery.

Compounding it: `R2_ens` and per-seed `r2_cond_true` are **measured on different domains** —
`r2_cond_true` on the 512-point trajectory, `R2_ens` on the pooled hull grid — so the
`learned_calcium_equation.txt` line `R2(symbolic vs true I_Ca) = 0.9836 +/- 0.0145 (per-seed) ;
0.9973 (ensemble)` compares apples to oranges. The ensemble figure is **not** "the per-seed number,
improved by pooling."

*(Note: `recon/codebase.md` §7.7 flagged the two `0.9973` values as possibly identical and asked for
a recheck. Resolved: they differ at the 5th decimal — `0.997333` vs `0.997341` — which strengthens
rather than weakens this guard. [verified])*

**The evidence.** Per-seed, `results/symbolic/symbolic_recovery_metrics.csv` filter `gCa==2.0`,
column `r2_cond_true`: `0.983586 ± 0.014494` (n=5). Retrain,
`results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv` same filter: `0.845475 ± 0.160284`.
`R2_ens` before/after: `0.997333` → `0.997341` (`learned_calcium_equation.txt` line 8 in each tree).

**Honest rewrite.**
> Against the true current the constrained fit attains R² = 0.984 ± 0.014 across seeds. We do not
> report the pooled R² (0.9973): it is computed on the hull grid shared by all seeds and against a
> target that lies exactly in the fitted model class, and it is insensitive to the estimator's actual
> quality — it moves only in its fifth decimal (0.997333 → 0.997341) while the per-seed R² collapses
> to 0.845 ± 0.160 under the retrain control of §[retrain].

**Grep before submit:** `0.997`, `0.9973`, `R^2 = 0.997`, `R² (ensemble)`.

**Guard id:** `r2-ens-is-uninformative`

---

### G5: a = 1.60 ± 0.90 against a true 2.0 is not a recovery

**Tempting claim.** `HANDOFF.md` §3b: *"the learned calcium current **is recovered** as the
conductance form … **a = gCa ≈ 1.60** (true 2.0 — voltage-gain *underestimated* …), **b ≈ −259**
(true −240, **~8%**), **Erev = −b/a ≈ 162 mV** (true 120)."* A drafter writes: *"we recover the
calcium conductance to within 20% and the reversal potential to within 35%."*

**Why it is wrong.** "Recovered … underestimated by 20%" describes a **biased but precise**
estimator. This estimator is neither — it is **unbiased-ish and useless**:

| quantity | estimate | true | error | spread |
|---|---|---|---|---|
| `a` (=gCa) | `1.595550` | 2.0 | −20% | **std 0.904569 = 56.7% of the mean**; per-seed `0.673 → 3.095` (**4.6×**) |
| `b` (=−gCa·ECa) | `-259.332393` | −240.0 | +8% | std `59.501608` = **23% of the mean** |
| `Erev` (=−b/a) | `162.5348` (pooled) | 120.0 | **+35%** | per-seed `51.4 → 467.6` mV (**9.1×**) |

Quoting `b` as "~8%" while suppressing its ±23% spread is the specific move to avoid: the point
estimate lands near the truth **by accident of averaging**, and the per-seed values do not. One seed
(4444) puts `a = 0.673`, another (2222) puts `a = 3.095` — a factor of 4.6 apart, straddling the
truth. That is not a measurement of gCa; it is five different closures that fit the same voltage.

**The control that makes this a finding rather than a bug.** The `[sanity]` fit
(`objective3_symbolic.jl:208-209`) applies the *identical* estimator, on the *identical*
hull-restricted domain, to the **analytic true current**, and returns `a = 2.0000, b = -240.00`
**exactly**. So the hull mask, the design matrix, and the regression are all exonerated: the spread
lives in the **network**. Cite the sanity fit every single time you attribute the gap to
identifiability — without it, "our recovery is noisy" reads as "our pipeline is broken."

**The evidence.** `results/symbolic/symbolic_recovery_metrics.csv`, filter `gCa==2.0` (5 rows):

| seed | `a_hat` | `b_hat` | `Erev` | `r2_cond_true` |
|---|---|---|---|---|
| 1111 | 1.200887 | −289.467640 | 241.044912 | 0.988146 |
| 2222 | 3.094842 | −158.987957 | 51.371913 | 0.963875 |
| 3333 | 1.474806 | −264.896010 | 179.614101 | 0.996589 |
| 4444 | 0.673056 | −314.721906 | 467.601437 | 0.973269 |
| 5555 | 1.534158 | −268.588453 | 175.072168 | 0.996053 |

Aggregates (ddof=1): `a 1.595550 ± 0.904569`; `b −259.332393 ± 59.501608`; `r2_cond_true
0.983586 ± 0.014494`. Sanity fit: `objective3_symbolic.jl:208-209`, console `a=2.0000 b=-240.00`.
Negative control, filter `gCa==0.4` (1 row): `a_hat = -0.371980` (true +0.4 — **wrong sign**),
`b_hat = -89.225507` (true −48.0), `Erev = -239.866501` (true +120), `r2_cond_true = 0.780647`,
`r2_sindy_true = -0.358705` (**negative R²** — worse than predicting the mean).

**Honest rewrite.**
> The learned closure recovers the **functional form** of the calcium current: constrained to
> s²(aV+b) it matches the true current with R² = 0.984 ± 0.014 across seeds. Its **coefficients are
> not recovered**. The conductance a = 1.60 ± 0.90 (true 2.0) has a standard deviation of 57% of its
> mean and spans 0.67–3.09 across seeds — a factor of 4.6 — and the reversal potential −b/a = 162.5 mV
> (true 120.0) is off by 35%, with per-seed values from 51 to 468 mV. Fitting the *true* current with
> the same estimator on the same domain returns a = 2.0000, b = −240.00 exactly, so the spread is a
> property of the trained network, not of the regression. The calcium conductance is not identifiable
> from this single trajectory.

Never write "recovered", "estimated", or "within X%" of `a`, `b`, or `Erev`. The permitted verbs are
**order-correct**, **not identifiable**, **spans**.

**Grep before submit:** `recover` within 2 lines of `a =`; `1.60`/`1.596` without a neighbouring
`0.90`/`± 0.9`; `162` without `120` and a spread; `8\%`.

**Guard id:** `a-hat-not-a-recovery`

---

### G6: Full-state vs voltage-only is an equivalence, not a ranking

**Tempting claim.** `HANDOFF.md` §3: *"Voltage-only = comparable mean, **~4× higher variance**
(V-RMSE std 0.118 vs 0.028)."* And the unwary version: *"voltage-only observation is slightly worse
than full-state."*

**Why it is wrong — two separate errors.**

1. **The means are not distinguishable.** V_rmse `0.245239 ± 0.028376` vs `0.263551 ± 0.117602`:
   Δ = 0.018 against a pooled std ≈ 0.085, **n = 5**. ICa_rmse `1.189072 ± 0.208293` vs
   `1.309227 ± 0.446775`: Δ = 0.120 against pooled std ≈ 0.35. ICa_rmse_norm `0.140341 ± 0.024584`
   vs `0.154522 ± 0.052731`. **No statistical test was run anywhere in the codebase**, and n=5 would
   support almost nothing if one were. "Slightly worse" asserts an ordering the data does not carry.
2. **The "~4× higher variance" is itself unsupported.** It is a **ratio of two sample standard
   deviations with 4 degrees of freedom each**. The sampling distribution of such a ratio is
   enormously wide — an F(4,4) variance ratio needs roughly a 6× point estimate before it clears a
   two-sided 95% threshold. `0.118/0.028 ≈ 4.2` is a plausible draw from equal variances. Do not
   report a variance ratio from n=5 as a finding.

The equivalence framing is also **the stronger and more interesting result**: the physics prior
reconstructs five gate trajectories that were never in the loss (`make_ude_loss` selects row 1 only,
`src/experiment.jl:157-172`). Ranking the two settings throws that away to assert something you
cannot defend.

**The evidence.** `results/metrics_baseline_multiseed.csv`, filter `model==UDE ∧ window==forecast`:

| observed | `V_rmse` | `gate_rmse_mean` | `ICa_rmse` | `ICa_rmse_norm` | n |
|---|---|---|---|---|---|
| full | 0.245239 ± 0.028376 | 0.000952 ± 0.000170 | 1.189072 ± 0.208293 | 0.140341 ± 0.024584 | 5 |
| voltage | 0.263551 ± 0.117602 | 0.001060 ± 0.000434 | 1.309227 ± 0.446775 | 0.154522 ± 0.052731 | 5 |

**Honest rewrite.**
> Restricting the loss to the voltage trace alone matches full-state observation to within seed
> noise: forecast V RMSE 0.264 ± 0.118 mV versus 0.245 ± 0.028 mV, and forecast I_Ca RMSE
> 1.31 ± 0.45 versus 1.19 ± 0.21 µA/cm² (n = 5 seeds; no significance test is possible at this sample
> size and none is claimed). The five gate trajectories are never in the objective yet are
> reconstructed to a mean RMSE of 1.1 × 10⁻³, because the known kinetics propagate them from the
> voltage fit — the physics prior, not the data, supplies the hidden states.

If you must mention the wider voltage-only spread, phrase it as observation, not finding: *"the
voltage-only setting is visibly more variable across seeds, though n = 5 does not support a
quantitative variance ratio."*

**Grep before submit:** `slightly worse`, `4×`, `4x higher variance`, `outperform`, `better than`
near `voltage-only`.

**Guard id:** `voltage-only-no-superiority`

---

### G7: There is no common-eval comparison of full vs voltage-only

**Tempting claim.** *"On the shared evaluation window (t > 50 ms), full-state and voltage-only UDEs
achieve …"* — a natural sentence to write, since the paper has both a common-eval protocol and a
full-vs-voltage comparison.

**Why it is wrong.** The rows do not exist. `common_eval_start` is passed **only** by the UDE
full-state baseline and the window ablation (`experiments_runner.jl:110-115` calls `run_experiment`
for the voltage-only runs **without** it; likewise the noise ablation at 114-116 and the gCa ablation
at 131-133, and the NODE baseline never gets it). Verified: grouping every `window=='common_eval'`
row in `metrics_all.csv` by `(model, observed)` returns exactly **one** group — `UDE/full`, 117 rows.
`NODE` and `UDE/voltage` have **zero**. The comparison is unavailable from this evidence base, and
the base is closed (mentor: no further experiments).

**The evidence.** `results/metrics_all.csv`, filter `window=='common_eval'` → 117 rows, all
`model==UDE ∧ observed=='full'` (= 9 `(t_train_end, seed)` cells × 13 metrics: `t_train_end ∈
{15,20,30,40,50}` at seed 1111, plus `t_train_end=30` at all 5 seeds).
Code: `experiments_runner.jl:110-115`; `common_eval_indices`, `src/hh_core.jl:85`.

**Honest rewrite.** Say nothing. If a reviewer asks, the Limitations sentence is:
> The shared evaluation window was instrumented only for the full-state UDE and the training-window
> ablation; the full-versus-voltage-only comparison is therefore reported on the forecast window
> (t > 30 ms), which is identical for both settings and so is not confounded by a window shift.

**Grep before submit:** `common` within 3 lines of `voltage-only`.

**Guard id:** `no-commoneval-voltage`

---

### G8: common_eval columns in the noise and gCa ablations are unusable

**Tempting claim.** *"Scored on the shared window, calcium recovery degrades from … across the gCa
sweep"* — reading `common_eval_ICa_rmse_norm` out of `ablation_gca.csv` because the column is there.

**Why it is wrong.** The column exists but is populated on **exactly one row** — the shared baseline
centre point, which the ablation inherits from the full-state baseline run (the only run in those
families that was given a `common_eval_start`). Verified: `ablation_noise.csv` → **1 of 5** rows have
any `common_eval_*` populated (the `noise_level=0.02` row); `ablation_gca.csv` → **1 of 4** (the
`gCa=2.0` row). A one-point series is not a series. Anything read from those columns is the baseline
restated under an ablation label.

Only **`ablation_window.csv`** carries a real common-eval series (all 5 rows populated) — that is the
family that was instrumented for it.

**The evidence.** `results/ablation_noise.csv`: 10 `common_eval_*` columns empty on the
`noise_level ∈ {0.0, 0.01, 0.05, 0.1}` rows. `results/ablation_gca.csv`: same, empty on
`gCa ∈ {0.4, 1.0, 4.0}`. Writer: `write_ablation_csv`, `experiments_runner.jl:218-231`.

**Honest rewrite.** Use the **forecast** window for the noise and gCa ablations and say so — it is
legitimate there, because neither axis shifts the training window, so the forecast interval
(t > 30 ms) is identical across every point on both axes and the comparison is unconfounded:
> The noise and conductance ablations are scored on the forecast window (t > 30 ms), which is common
> to every point on those axes because neither sweep alters the training window. The shared
> late-window protocol (t > 50 ms) is required only for the training-window ablation, where the
> forecast interval would otherwise move with the training length.

**Grep before submit:** `common_eval` near `noise` or `gCa`.

**Guard id:** `commoneval-ablation-unusable`

---

### G9: At t_train_end = 50 the common-eval "check" is an identity

**Tempting claim.** `HANDOFF.md` §3, verbatim: *"Sanity check: at t_train=50 the common-eval value
equals the forecast value (both are (50,100]) — **verified**."* A drafter promotes this: *"we
validate the common-evaluation protocol by confirming that at t_train = 50 ms it reproduces the
forecast metrics."*

**Why it is wrong.** It is true, and it is **true by construction**, so it validates nothing. It
could not have come out any other way. `common_eval_indices` selects `findall(t -> t > 50.0, TSTEPS)`
(`src/hh_core.jl:85-86`); `make_split(50.0)` sets `forecast_idx = findall(t -> t > 50.0, TSTEPS)`
(`src/experiment.jl`). **The same index set.** The two column families are then computed from
identical predictions on identical indices, so they are byte-identical — verified: at the
`t_train_end==50.0` row, **every** `common_eval_*` column equals its `forecast_*` twin exactly
(`common_eval_V_rmse == forecast_V_rmse == 0.417721`, and so on for all 13 metrics).

A "check" whose outcome is entailed by the code is a tautology. Presenting it as a passed test is
worse than omitting it: a reviewer who reads `hh_core.jl:85` sees that you tested `x == x` and
reported it as evidence. That damages the credibility of the protocol it was meant to support.

**The evidence.** `results/ablation_window.csv`, row `t_train_end == 50.0`: all 10 `common_eval_*`
RMSE columns and all 3 `common_eval_` spike/rollout columns equal their `forecast_*` counterparts
(verified programmatically: identity holds for every pair). Contrast the other rows, where they
legitimately differ (`t_train_end=30`: `forecast_V_rmse = 0.219197` vs
`common_eval_V_rmse = 0.236084`).

**Honest rewrite.** Present it as a *consistency invariant of the implementation*, in Methods or an
appendix — never as a result:
> By construction the shared window (t > 50 ms) coincides with the forecast window at the longest
> training length, so the two metric families are identical at t_train = 50 ms; the two protocols
> diverge only for shorter training windows, which is exactly where the comparison is needed.

**Grep before submit:** `sanity check` near `50`; `validat` near `common`.

**Guard id:** `commoneval-equals-forecast-at-50`

---

### G10: The retrain's gCa = 0.4 row is a copied file, not an "after"

**Tempting claim.** *"After aggressive retraining, the gCa = 0.4 negative control still fails
(a = −0.37, wrong sign; R² = 0.781), confirming that the failure at the physiological conductance is
not a training artifact."* The row is sitting in
`results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv`, so it looks like an after-result.

**Why it is wrong.** `retrain_gca2_20k.jl` retrains **only the 5 gCa=2.0 full-state seeds** (header
scope, lines 19-23). The gCa=0.4 negative control was **not retrained** — its probe files are
`cp(..., force=true)`-copied from the canonical tree into the retrain tree (`retrain_gca2_20k.jl:136-143`)
so that the redirected Objective-3 script finds its control in one place. The symbolic pipeline then
re-fits the **same copied probe** and reproduces the **same numbers**. Verified: the two `gCa==0.4`
rows are **identical across every one of the 14 columns** (`DataFrame.equals` → `True`).

Reporting it as an "after" claims a replication that did not happen, in the one table whose entire
rhetorical purpose is a before/after contrast. This is the most dangerous guard in the file: the
error is invisible in the CSV and fatal in review.

**The evidence.** `results/symbolic/symbolic_recovery_metrics.csv` `gCa==0.4` row and
`results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv` `gCa==0.4` row: byte-identical
(`a_hat = -0.371980`, `b_hat = -89.225507`, `Erev = -239.866501`, `r2_cond_true = 0.780647`,
`r2_sindy_true = -0.358705`). Copy: `retrain_gca2_20k.jl:136-143`. Scope: same file, header 19-23.

**Honest rewrite.** Exclude the row from every before/after table and state the scope:
> The retraining control covers the five gCa = 2.0 full-state seeds. The gCa = 0.4 negative control,
> the voltage-only setting, the Neural ODE, and the remaining ablations were not retrained; the
> gCa = 0.4 entry in the retrain output tree is the original probe re-analysed, not an independent
> replication, and we do not report it as an after-condition.

**Grep before submit:** `0.4` inside any retrain/before-after table; `-0.372`/`-0.37` near
`retrain`.

**Guard id:** `retrain-gca-point-four-is-copied`

---

### G11: fig7b is confounded — use fig7b_commoneval for any cross-window comparison

*(Not in the contract §9 enumeration, which merges the fig7b confound into the window artifact of G12.
Split out because the two are independent defects with different fixes: G11 is cured by citing the
commoneval figure, G12 is not cured by anything and must be disclosed in the caption. Grounded in
`recon/results.md` §9.5 / §10.)*

**Tempting claim.** Any sentence citing `figures/fig7b_ablation_window.png` to compare training
lengths — e.g. *"forecast V RMSE degrades as the training window lengthens (fig7b)."*

**Why it is wrong.** `fig7b_ablation_window.png` scores each training length on **its own** forecast
window: `forecast_idx = t > t_train_end` (`make_split`). So the `t_train=15` point is scored on
(15, 100], the `t_train=50` point on (50, 100] — **different intervals, different numbers of points,
different dynamical content**. Every cross-window difference in that figure mixes the model's
accuracy with the window's difficulty. The confound is structural, not a nuance.

`figures/fig7b_commoneval_ablation_window.png` (written `experiments_runner.jl:326-328` with
`window="common_eval"`) scores all five on the shared t > 50 ms interval. That is the only
apples-to-apples version, and it is the one the mentor asked for.

Both files exist, differ by 12 characters in the filename, and look nearly identical. Getting this
wrong is a `\includegraphics` typo with a scientific consequence.

**The evidence.** Confounded: `experiments_runner.jl:322-323` → `fig7b_ablation_window.png`,
`window="forecast"` (default). Correct: `experiments_runner.jl:326-328` →
`fig7b_commoneval_ablation_window.png`, `window="common_eval"`. Rationale in code:
`src/hh_core.jl:81-84` ("the forecast window otherwise shifts with the training window, so its
metrics are not directly comparable across runs"). The two series differ materially — e.g. at
`t_train=15`, `forecast_V_rmse = 1.261599` vs `common_eval_V_rmse = 1.558603`.

**Honest rewrite.** Cite only `fig7b_commoneval_ablation_window.png` in the training-window analysis
and pin the reason to the caption:
> All training lengths are scored on the same unseen interval (t > 50 ms), which is forecast for
> every window in the sweep; the per-run forecast window shifts with training length and is therefore
> not comparable across this axis.

`fig7b_ablation_window.png` belongs in the appendix or nowhere. If it ships, its caption must state
that each point is scored on a different interval.

**Grep before submit:** `fig7b_ablation_window` (must appear zero times in the main text).

**Guard id:** `fig7b-confounded`

---

### G12: The 40→50 ms non-monotonicity is an optimization artifact, not a finding

**Tempting claim.** `HANDOFF.md` §3: *"15 ms → **1.56 mV** (too short), 20 ms → 0.23, 30 ms → 0.24,
40 ms → 0.37, 50 ms → 0.42. Supports needing a *sufficiently long* window."* An unwary drafter reads
the last three points and writes the opposite: *"performance degrades with longer training windows,
suggesting the model overfits the extended window"* — or, worse, *"there is an optimal training
window near 20–30 ms."*

**Why it is wrong.** **Every window trains for the same fixed budget** — Adam 5000 / BFGS 300
(`experiments_runner.jl:42`) — regardless of how many data points it must fit. At `t_train_end=15`
the loss covers ~77 points; at 50 ms, ~256. The longer windows are therefore **under-optimised**, not
intrinsically harder. The upward trend at 40→50 ms measures the **iteration budget**, not the
dynamics. This is a standing project finding (memory: `window-ablation-nonmonotonicity-is-artifact`).
Note `fig7b_commoneval` fixes the *shifting-window* confound (G11) but **not** this one — they are
independent defects and both must be disclosed.

**And most of the axis is inside seed noise anyway.** The seed spread at the shared centre point
(`t_train=30`) is `± 0.028` mV (G6). Against that yardstick:

| gap | Δ | verdict |
|---|---|---|
| 15 → 20 | 1.333 | **real** (≈ 47× the seed std) |
| 20 → 30 | 0.011 | inside seed noise |
| 30 → 40 | 0.131 | ~4.6× seed std — marginal, single seed, and confounded by the budget |
| 40 → 50 | 0.051 | ~1.8× seed std — **not interpretable** |

Only the `t_train=15` collapse (`1.558603`, ≈ **6.6×** the 20 ms value) clears seed noise decisively.
That is the one claim this axis supports.

**The evidence.** `results/ablation_window.csv`, column `common_eval_V_rmse` (all 5 rows populated,
all scored on t > 50 ms), single seed 1111:

| `t_train_end` | 15 | 20 | 30 | 40 | 50 |
|---|---|---|---|---|---|
| `common_eval_V_rmse` | 1.558603 | 0.225237 | 0.236084 | 0.367170 | 0.417721 |
| `common_eval_ICa_rmse_norm` | 0.229141 | 0.246919 | 0.114604 | 0.250005 | 0.110871 |

(`common_eval_ICa_rmse_norm` is **not even monotone in sign** — 0.229 → 0.247 → 0.115 → 0.250 → 0.111.
It supports no trend at all; do not plot a trend line through it.) Budget:
`experiments_runner.jl:42`. Seed spread reference: `metrics_baseline_multiseed.csv`, UDE/full
forecast `V_rmse std = 0.028376`.

**Honest rewrite.**
> Training on only the first 15 ms fails: scored on the shared window the forecast V RMSE is 1.56 mV,
> roughly seven times the value at any longer window — the 15 ms window ends inside the initial
> transient and never observes a full limit cycle. Beyond 20 ms the axis is flat to within seed noise
> (0.23–0.42 mV against a seed spread of ±0.03 at the centre point, single seed per point). The mild
> upward drift at 40–50 ms is **not** evidence that longer windows are harder: every window receives
> the same fixed budget (Adam 5000 / BFGS 300) irrespective of the number of data points in its loss,
> so the longer windows are under-optimised. We report the axis as "a sufficiently long window is
> required, and 20 ms suffices," and draw no conclusion from its non-monotonicity.

The caption **must** carry the artifact statement or the figure argues the opposite of the truth.

**Grep before submit:** `optimal window`, `degrad` near `window`, `overfit` near `window`, any trend
claim citing 40 or 50 ms.

**Guard id:** `window-nonmonotonicity-is-artifact`

---

### G13: Every ablation is n = 1; most gaps are inside seed noise

**Tempting claim.** *"Calcium identifiability improves monotonically with conductance
(1.18 → 0.33 → 0.11 → 0.068), demonstrating a clean dose–response relationship."* Or any ablation
sentence that does not say "single seed".

**Why it is wrong.** `axis_series` and `write_ablation_csv` both pin `df.seed .== B_SEED`
(`experiments_runner.jl:162-172`, `206-216`) — **necessarily**, or the `t_train_end` axis would pick
up 5 duplicate points at 30 ms from the multi-seed baseline. Consequence: **every point on every
ablation axis is one run at seed 1111, with no error bar.** The grid is a star design (one axis at a
time about a shared centre), not a crossed factorial; only `seed` is crossed, and only at the centre.

The centre point's seed spread is the only available yardstick. Applying it to the gCa axis
(seed spread of `ICa_rmse_norm` at gCa=2.0 = `± 0.024584`, n=5):

| gap | Δ | vs seed std | verdict |
|---|---|---|---|
| 0.4 → 1.0 | 0.847 | 34× | **safely real** |
| 1.0 → 2.0 | 0.220 | 9× | **real** |
| 2.0 → 4.0 | **0.045** | **1.8×** | **near seed noise — do not interpret** |

So the axis supports "identifiability collapses at low conductance", and **not** "identifiability
keeps improving above gCa = 2.0". The `0.112 vs 0.068` step is the same size as the noise on a single
point. By the same yardstick on the window axis, only `t_train=15` clears (G12). Across all three
ablations, exactly **two** gaps are safely real: `gCa 0.4→1.0` and `t_train=15`.

**The evidence.** `results/ablation_gca.csv`, column `forecast_ICa_rmse_norm`, seed 1111 only:

| `gCa` | 0.4 | 1.0 | 2.0 | 4.0 |
|---|---|---|---|---|
| value | 1.179159 | 0.332549 | 0.112292 | 0.067725 |

Seed spread at the centre: `metrics_baseline_multiseed.csv`, `model==UDE ∧ observed==full ∧
window==forecast ∧ metric==ICa_rmse_norm` → `0.140341 ± 0.024584`, n=5. (Note the centre-point
values differ legitimately: `0.112292` is seed 1111 alone; `0.140341` is the 5-seed mean.)
Seed pinning: `experiments_runner.jl:159-172`.

**Honest rewrite.**
> All ablations are single runs at the pre-registered baseline seed (1111); the sweeps carry no error
> bars, and we calibrate them against the five-seed spread at the shared centre point
> (ICa_rmse_norm = 0.140 ± 0.025). On that basis the collapse at gCa = 0.4 (1.18, i.e. the closure's
> error exceeds the calcium current's own standard deviation — the network has learned nothing about
> it) and the drop to gCa = 1.0 (0.33) are far outside seed noise, while the difference between
> gCa = 2.0 and gCa = 4.0 (0.11 vs 0.07) is comparable to it and we draw no conclusion from it.

`ICa_rmse_norm > 1` is the sharpest sentence in the paper — the error exceeds the signal's own
variation (`ICa_rmse / std(ICa_true)`, `src/metrics.jl:151-153`). Spend it on gCa = 0.4 and nowhere
else.

**Grep before submit:** `monotonic`, `dose`, `trend` near an ablation; `0.068`/`0.0677` presented as
an improvement.

**AMENDED 2026-08 (five-seed sweep).** The gCa sweep is now run at n=5 at every point, so
for that one ablation the "single seed" wording is retired -- but the guard tightens rather
than relaxes. With spreads available, the adjacent steps can be tested, and two of the three
fail: `0.4->1.0` separates by 1.8 pooled SD and `2.0->4.0` by 1.3, against 2.4 for
`1.0->2.0`. So the ban on reading `gCa 2.0->4.0` as a step is no longer a precaution about
sample size; it is a measured negative result. Claim the end-to-end 0.4-vs-4.0 trend (~8x,
far outside noise) and nothing finer. The remaining ablations are still n=1 and must still
say so.

**Guard id:** `ablations-are-n1`

---

### G14: fig11 mixes two estimators and panel 3 has no error bar

**Tempting claim.** The figure as it stands: three bars, true vs recovered, for `a`, `b`, `Erev` —
read by any reviewer as one estimator with consistent uncertainty. Caption drafted as *"Recovered
coefficients versus ground truth (mean ± std over 5 seeds)."*

**Why it is wrong.** That caption is **false for panel 3**. Panels 1-2 (`a`, `b`) plot per-seed
mean ± std; panel 3 (`Erev`) plots the **pooled point estimate** with **no `yerror` argument passed**
(`objective3_symbolic.jl:309-312`). The missing whisker therefore reads as **zero uncertainty on the
single most-wrong number in the paper** — `Erev = 162.5` mV against a true 120.0, off by 35%.

The per-seed `Erev` values are `241.0, 51.4, 179.6, 467.6, 175.1` mV — a **9.1× spread** bracketing
the truth from both sides. The honest picture is the opposite of a confident bar. Panel 3 genuinely
*cannot* carry a per-seed error bar (the ratio −b/a blows up as a → 0, which is exactly what seed
2222's `a = 3.09` and seed 4444's `a = 0.67` do to it — code comment 197-198), and per G3 the pooled
value is the only stable summary. That is a legitimate estimator choice and an **illegitimate silent
one**. Note also that per G3 panels 1-2 and the pooled fit are the *same* estimator for `a` and `b`
— the figure does not show two methods agreeing.

**The evidence.** `figures/fig11_calcium_coeff_recovery.png`, written `objective3_symbolic.jl:298-317`;
panel 3 at lines 309-312 passes no `yerror`. Per-seed `Erev` from
`results/symbolic/symbolic_recovery_metrics.csv` filter `gCa==2.0`: `241.044912, 51.371913,
179.614101, 467.601437, 175.072168` (min 51.4, max 467.6, ratio 9.10). Pooled
`Erev_ens = 162.5348`; mean of per-seed ratios = `222.9409`.

**Honest rewrite (the caption, which is the deliverable here).**
> **Figure 11.** Recovered versus true coefficients of the constrained calcium closure
> I_Ca = s²(aV + b) at gCa = 2.0. **Panels (a, b):** per-seed mean ± s.d. over 5 seeds. **Panel (c):**
> the reversal potential −b/a computed from the mean coefficients, shown **without an error bar
> because it is a pooled point estimate, not a per-seed mean** — the per-seed ratios span 51–468 mV
> (a factor of 9) and are unstable when a is small, so their mean (222.9 mV) is not a usable summary.
> The absence of a whisker in panel (c) indicates an estimator that admits no per-seed spread, **not**
> a precise estimate: at 162.5 mV against a true 120.0 mV this is the least accurate recovered
> quantity in the study.

Either ship that caption or split panel 3 into its own figure. Do not ship the three-panel figure
with a mean±std caption.

**Grep before submit:** `mean $\pm$ std` in the fig11 caption; `Erev` without a spread or a
"pooled" qualifier.

**Guard id:** `fig11-mixed-estimators`

---

### G15: "All other constants literature-grounded" is false as written

**Tempting claim.** `HANDOFF.md` §5, verbatim: *"**`gCa = 2.0`** (above the literature ~0.4) —
justified by the identifiability ablation above, not convenience. **All other constants
literature-grounded** (`ECa=120`, `gNaP=0.5` Golomb–Amitai 1997, **classical HH set**, `p_inf` V½ −50
Magistretti–Alonso 1999, `s_inf` V½ −25 slope 9 Reuveni 1993)."* This sentence, transcribed into a
parameter table with a citation column, fabricates citations.

**Why it is wrong.** **Exactly three literature citations exist in the entire codebase.** "Classical
HH set" is doing enormous unearned work in that sentence — the classical block carries **no inline
citation anywhere in the code**. The standing project rule (memory:
`param-values-must-be-literature-grounded`) is that parameter values come from published refs, never
picked for convenience — so the parameter table must **close this from outside the code**, or state
plainly which values are conventional-but-uncited. It cannot inherit a citation the source never made.

| Constant | Value | Citation status in code |
|---|---|---|
| `gNaP` | 0.5 | **Golomb–Amitai 1997** (range) — `src/hh_core.jl:47` |
| `p_inf` V½ / slope | −50 / 6 | **Magistretti–Alonso 1999** — `src/hh_core.jl:88` |
| `s_inf` V½ / slope | −25 / 9 | **Reuveni 1993** — `src/hh_core.jl:93` |
| `ECa` | 120.0 | **Reuveni 1993**, but *only* via a comment in `objective3_symbolic.jl:44-45`; **no citation in `hh_core.jl`** |
| `Cm` | 1.0 | **none** |
| `gNa` | 120.0 | **none** |
| `gK` | 36.0 | **none** |
| `gL` | 0.3 | **none** |
| `ENa` | 50.0 | **none** |
| `EK` | −77.0 | **none** |
| `EL` | −54.4 | **none** |
| `Iapp` | 10.0 | **none** |
| `tau_p` | 1.0 | **none** |
| `tau_s` | 5.0 | **none** |
| `OU_THETA` | 5.0 | **none** — comment points at "paper §3.5", i.e. at the paper being written (circular) |
| `OU_SIGMA` | 0.5 | **none** — same |

The classical block is *implicitly* Hodgkin–Huxley 1952 squid axon and the values are the standard
textbook set, but **the code never says so** and the paper must not pretend the attribution came from
the code. `Iapp`, `tau_p`, `tau_s` and the OU parameters are genuinely uncited modelling choices.
The `OU_THETA`/`OU_SIGMA` comments are the worst case: they cite **this paper's own §3.5**, which
does not exist yet — a citation loop that must be broken by stating them as chosen values.

**Required action, not just phrasing.** Two of these need real bibliography work (see
`references.bib` / the Bibliography phase), and it is outside what the code can settle:
1. **Cite the classical block to a real source** — Hodgkin & Huxley 1952 for the squid parameter set.
   The key is **`hodgkin1952`** [verified — `recon/relatedwork.md` supplies the entry: *J. Physiol.*
   **117**(4):500–544, doi `10.1113/jphysiol.1952.sp004764`]. `recon/relatedwork.md` also prescribes the
   provenance paragraph this table serves: HH 1952 → Pospischil et al. 2008 (`pospischil2008`) as the
   modern minimal-model template → per-current provenance (Reuveni 1993, Golomb–Amitai 1997,
   Magistretti–Alonso 1999).
   **VERIFY before submission:** the brief supplies the *paper*, not a page/table locator for these
   specific values (`Cm=1.0, gNa=120.0, gK=36.0, gL=0.3, ENa=50.0, EK=-77.0, EL=-54.4`). Note the code's
   values are the **textbook resting-potential-shifted convention**, not HH 1952's original
   depolarization-positive values (HH 1952 Table 3 uses `E_Na≈-115, E_K≈+12` mV relative to rest, sign
   convention inverted). Cite `hodgkin1952` for the *model and the conductances*; do **not** claim the
   reversal potentials are transcribed from it. If no locator is confirmed, the honest phrasing is
   "the standard squid-axon parameter set [hodgkin1952], in the modern sign convention" — which is a
   real attribution, not a fabricated one.
2. **Declare the rest as choices.** `Iapp = 10.0` is chosen to drive repetitive spiking (the code
   comment says exactly this: `uA/cm^2 : drives repetitive spiking`); `tau_p`, `tau_s`, and the OU
   parameters are modelling choices with no source. Say so.

**Honest rewrite (the parameter table's footnote).**
> Sodium and potassium kinetics and the passive parameters (Cm, gNa, gK, gL, ENa, EK, EL) use the
> standard squid-axon values \citep{hodgkin1952}, in the modern resting-potential-referenced sign
> convention. The persistent-sodium conductance gNaP = 0.5 mS/cm² is taken
> from the range in Golomb & Amitai (1997); the persistent-sodium half-activation (−50 mV) from
> Magistretti & Alonso (1999); the high-threshold calcium half-activation and slope (−25 mV, 9 mV)
> and the calcium reversal potential ECa = 120 mV from Reuveni et al. (1993). The remaining values
> are modelling choices, not measurements: the drive Iapp = 10 µA/cm² is set to elicit repetitive
> spiking; the gate time constants tau_p = 1 ms and tau_s = 5 ms and the Ornstein–Uhlenbeck noise
> parameters (θ = 5, σ = 0.5, renormalised to unit variance per channel so that noise_level alone sets
> the amplitude) are chosen, and we state them for reproducibility rather than attributing them to a
> source. The calcium conductance gCa = 2.0 mS/cm² is deliberately set above the physiological range
> (~0.4) as the controlled variable of the identifiability experiment of §[gca-ablation], not for
> convenience.

That last clause is doing real work: `gCa = 2.0` is the first thing a neuroscientist reviewer will
challenge, and the gCa ablation (G13) is the answer. Make the table point at it.

**Grep before submit:** any citation key attached to `Cm`, `gNa`, `gK`, `gL`, `ENa`, `EK`, `EL`,
`Iapp`, `tau_p`, `tau_s`, `theta`, `sigma`; the phrase `literature-grounded`.

**Guard id:** `uncited-constants`

---

### G16: Every identifiability claim is "from this trajectory" — and that belongs in the abstract

**Tempting claim.** The paper's own headline, unqualified: *"the calcium conductance is not
identifiable"* — or the title-level version, *"Identifiability Limits of Universal Differential
Equations in a Hodgkin–Huxley Neuron."* A reviewer reads that as a claim about UDEs and HH neurons.

**Why it is wrong.** The entire evidence base is **one trajectory**: one drive (`Iapp = 10.0`,
constant), one initial condition (`steady_state_u0()` at V0 = −65 mV), one 100 ms window, one 512-point
grid, one noise realisation per seed. There is **no second protocol** — no current-clamp step family,
no varied IC, no longer recording, no perturbation. The seeds redraw the network init *and* the noise
path jointly (`run_experiment`: `gen_noisy_data(..., seed=seed)` and `make_ca_network(seed)` take the
same argument), so they do not even give independent trajectories — they give one trajectory with five
noise realisations. As stated, the unqualified claim is **unsupportable and trivially attackable**:
"did you try a different stimulus?" ends the discussion, because the answer is no and the evidence
base is closed.

Qualified, the claim is **strong, defensible, and interesting** — and the qualifier costs four words.
A negative result with a precisely drawn boundary is a contribution; the same result with a boundary
drawn past the data is a rejection. The controls make the qualified version genuinely hard to attack:

- **The gCa sweep** (G13): the failure is a smooth function of how much the hidden current moves
  the observable voltage. Over five seeds the normalised calcium error runs from
  `0.093 ± 0.044` at `gCa = 4.0` to `0.724 ± 0.318` at the literature value `0.4` — it
  **approaches** the true current's own variation, with a spread that reaches it. Say *approaches
  unity and give the spread*; **do not write that it exceeds one** — claims.yaml forbids that
  phrasing and the five-seed mean does not support it (the `1.179` this bullet used to lean on is
  one realisation, BLOCK 3 of metrics_map.yaml). That is an information argument, not an anecdote.
- **The aggressive retrain**: 4× the iterations (Adam 20k/BFGS 1k vs 5k/300) made **every quantity
  worse and noisier** — `a` 1.5956 ± 0.9046 → 1.4947 ± 1.4843 (std +64%, moving *away* from 2.0);
  `r2_cond_true` 0.9836 ± 0.0145 → 0.8455 ± 0.1603; forecast V RMSE 0.2452 ± 0.0284 → 0.7556 ± 0.4114.
  And **`bfgs_ok == true` for all 5 seeds with `final_loss = 29.66 ± 2.66`** (tight): the optimiser
  converged. It converged to **different closures that fit the same voltage equally well**. That is
  the textbook non-identifiability signature, and it forecloses "you just under-trained it".
- **The sanity fit** (G5): `a = 2.0000, b = −240.00` exactly on the true current. Forecloses "your
  regression is broken."

Three controls, three foreclosed rebuttals. The scope qualifier is what lets you spend them.

**The evidence.** Single trajectory: `TSPAN_FULL = (0.0, 100.0)`, `DATASIZE = 512`,
`Iapp = 10.0`, `V0 = -65.0`, `steady_state_u0()` — `src/hh_core.jl:39-40, 74-76, 103-105`;
`gen_clean_data(gCa)` is the only data generator. Seed coupling: `src/experiment.jl` (`run_experiment`,
`run_node_baseline`). Retrain: `results/retrain_gca2_20k/metrics_retrain.csv` — all 5 rows
`bfgs_ok = True`, `final_loss` per-seed `29.212284, 26.260637, 31.822533, 32.795931, 28.208120`
(mean 29.6599 ± 2.6634), `forecast_V_rmse` mean 0.755622 ± 0.411361. Symbolic before/after:
`results/symbolic/symbolic_recovery_metrics.csv` vs
`results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv`, filter `gCa==2.0`.

**AMENDED 2026-08-19 — THE QUALIFIER CHANGED. READ THIS BEFORE COPYING ANYTHING BELOW.**
This guard's *requirement* stands: the claim needs an explicit scope or it overreaches. But the
scope it used to prescribe — "from a single 100 ms trajectory" — was **falsified by our own
control** and is marked `status: retired` in claims.yaml (`single-trajectory-is-the-binding-
limitation`). One trajectory is *sufficient*: a direct two-parameter fit to that same trajectory
recovers the conductance to about six per cent. The binding limit is the **closure**, not the data.
Any draft that says "not identifiable from a single trajectory" is reintroducing a dead claim.

**Honest rewrite (abstract-grade — this exact qualifier goes in the abstract, not only Limitations).**
> …the UDE reproduces the voltage trace and recovers the functional form of the hidden calcium
> current, but **not its coefficients: read out through the neural closure**, the calcium conductance
> is not identifiable (a = 1.60 ± 0.90 against a true 2.0). The limit is the closure and not the
> data: a two-parameter fit to the *same* trajectory recovers the conductance to about six per cent
> (2.092 ± 0.130; profile-likelihood 95% interval [1.6065, 2.1477] on the representative seed). Two
> further controls foreclose the optimiser and the regression: quadrupling the training budget makes
> every recovered quantity worse and noisier while the loss converges (BFGS succeeds on all seeds,
> final loss 29.7 ± 2.7) — different closures fit the same voltage equally well — and fitting the
> *true* current with the same estimator on the same domain returns the exact coefficients.

Every claim of non-identifiability in the paper carries `scope:` in `claims.yaml` reading
`"single trajectory, Iapp=10.0 constant, one IC, 100 ms, 512 samples, n=5 seeds (init+noise jointly)"`
and the matching qualifier in prose. Also: describe the seed spread as **"over seeds, each seed
redrawing both the network initialisation and the noise realisation"** — never as "over random
inits" (the runner's own comment at `experiments_runner.jl:53-54` says "several random inits" and is
inaccurate; the two variance sources are inseparable in these runs).

**Grep before submit:** `not identifiable` / `non-identifiab` without `single trajectory` within
2 lines; `random inits`.

**Guard id:** `single-trajectory-scope`

---

### G17: The NODE's spike-timing accuracy is an average over 2 seeds, not 5

*(Not in the contract §9 enumeration — added because it is the same failure class as G2 and it
flatters the baseline, which is the direction that costs you a reviewer.)*

**Tempting claim.** A NODE-vs-UDE table row: *"spike timing error: NODE 1.27 ± 0.42 ms, UDE
0.00 ± 0.00 ms"* — read straight off `metrics_baseline_multiseed.csv`, where every other NODE row has
`n_seeds = 5`.

**Why it is wrong.** That row has **`n_seeds = 2`**. `spike_time_error` returns `NaN` when no
predicted spike matches any true spike within the 2 ms tolerance, and `agg()` does
`filter(isfinite, ...)` before averaging (`experiments_runner.jl:197`), so **the seeds that failed
completely are silently deleted from both the mean and the count**. Verified per-seed:
`NaN, 0.978474, NaN, 1.565558, NaN` — **three of five seeds produced no matchable spike at all**, and
the "1.27 ms" is the average of the two that did.

So the number reports the NODE's timing accuracy *conditional on it having produced a recognisable
spike*, which it failed to do 60% of the time. Printing it beside the UDE's `0.000000 ± 0.000000
(n=5)` without stating n=2 materially flatters a baseline that diverged within one sample (G2) — and
the `n_seeds` column is sitting right there in the CSV to convict you.

**The evidence.** `results/metrics_baseline_multiseed.csv`:
`NODE,full,forecast,spike_mean_abs_dev_ms,1.272016,0.415131,**2**` — the only NODE row with
`n_seeds ≠ 5`. Per-seed, `results/metrics_all.csv` filter `model==NODE ∧ window==forecast ∧
metric==spike_mean_abs_dev_ms ∧ @base`: seeds 1111/3333/5555 = `NaN`; 2222 = `0.978474`;
4444 = `1.565558`. Matching: `src/metrics.jl` `spike_time_error`, `match_tol_ms = 2.0`, greedy
nearest-unused. Aggregation: `experiments_runner.jl:197`.

**Honest rewrite.** Preferred: **drop the metric for the NODE** and say why.
> Spike-timing error is undefined for the Neural ODE: three of five seeds produce no spike matchable
> to a true spike within the 2 ms tolerance, and the metric is reported over the remaining two
> (1.27 ± 0.42 ms, n = 2). We omit it from the comparison — a timing error conditional on having
> produced a spike is not comparable to the UDE's exact spike recovery (0.00 ± 0.00 ms, n = 5).

If it must be tabled, **print `n` in the cell**: `1.27 ± 0.42 (n=2 of 5)`. Any table containing this
metric needs an `n` column, because this row's `n` differs from every other row's.

**Grep before submit:** `1.27`, `spike` in any NODE row lacking an `n=2` annotation.

**Guard id:** `node-spike-n2`

---

### G18: The SINDy fit's R² is a goodness-of-fit, not an equation recovery

*(Not in the contract §9 enumeration — added because `claims.yaml` claim `sindy-does-not-sparsify`
references this guard id, and because it is the last place in the paper where a high R² can be
mistaken for a recovered equation.)*

**Tempting claim.** `results/symbolic/symbolic_recovery_metrics.csv` column `r2_sindy_true` reads
`0.955782 ± 0.059157` at gCa=2.0 — higher than several quantities the paper *does* report. A drafter
writes: *"unconstrained sparse regression independently recovers the calcium current (R² = 0.96),
corroborating the constrained fit."*

**Why it is wrong.** Nothing was sparsified and no equation was recovered.

1. **The sparsity is zero.** `n_sindy_terms = 6` at **every one of the 6 configs** (verified: all 5
   gCa=2.0 seeds and the gCa=0.4 control). The library is `{1, V, s, V*s, s², V*s²}` — six terms, six
   retained. The truth `2·V·s² − 240·s²` is **exactly representable in that library with two terms**.
   A sparse-regression method that returns the full library on a target that is exactly two-sparse in
   it has failed at the one thing it exists to do. Reporting its R² as a success inverts the result.
2. **The coefficients are not merely noisy — one is sign-wrong at 40% of seeds.** `V*s²` (true
   **+2.0**) is fitted as `−1.469, +4.783, +1.275, +5.124, −7.963` — **2 of 5 seeds negative**, span
   −7.96 → +5.12. `s²` (true **−240.0**) is fitted as `−406.9, −93.2, −247.7, −37.7, −949.1` — a
   **25×** span. The physical structure is smeared across the correlated low-order terms (`1, V, s,
   V*s`), which is exactly why R² survives: on the hull-masked grid the six columns are strongly
   collinear, so a wrong decomposition still interpolates the target. **High R² here measures the
   library's expressiveness, not the estimator's correctness** — the same defect as `R2_ens` (G4),
   one level further out.
3. **The negative control proves the statistic is not a recovery metric.** At gCa=0.4,
   `r2_sindy_true = −0.358705` — a **negative R²**, worse than predicting the mean, while
   `n_sindy_terms` is still 6 and `r2_sindy_nn = 0.243003`. The fit tracks the *network*, not the
   truth.

The retrain confirms the direction: `r2_sindy_true` fell `0.955782 ± 0.059157` → `0.712049 ± 0.259264`,
and the **physical `s²` term was driven to exactly `0.0` for seeds 3333/4444** (`n_sindy_terms = 5`) —
the extra optimisation deleted the one term the truth actually needs.

**The evidence.** `results/symbolic/symbolic_recovery_metrics.csv`, filter `gCa==2.0`:
`r2_sindy_true = 0.955782 ± 0.059157`, `n_sindy_terms = 6,6,6,6,6`. Filter `gCa==0.4`:
`r2_sindy_true = -0.358705`, `n_sindy_terms = 6`. Coefficients:
`results/symbolic/sindy_coefficients.csv`, rows `V*s^2` and `s^2` (values above; columns are runs,
rows are terms). Retrain: `results/retrain_gca2_20k/symbolic/symbolic_recovery_metrics.csv`
(`n_sindy_terms = 6,6,5,5,6`) and its `sindy_coefficients.csv` (`s^2 == 0.0` at seeds 3333/4444).
Library: `EXPONENTS`, `objective3_symbolic.jl:56`.

**Honest rewrite.**
> Unconstrained sparse regression over the library {1, V, s, Vs, s², Vs²} — which contains the true
> current exactly, as `2Vs² − 240s²` — recovers no sparse equation: all six terms are retained at
> every seed, the `Vs²` coefficient (true +2.0) ranges from −7.96 to +5.12 and takes the wrong sign
> at two of five seeds, and the `s²` coefficient (true −240) spans a factor of 25. The fit
> nevertheless tracks the true current (R² = 0.96 ± 0.06), because the library's columns are
> collinear on the sampled domain: a wrong decomposition interpolates as well as the right one. We
> therefore report the SINDy fit as a **negative** result about sparse recovery, not as corroborating
> evidence, and use the *constrained* fit (G4, G5) for all coefficient statements.

Never present the SINDy R² beside the constrained fit's R² as two agreeing recoveries — as with G3,
that manufactures corroboration out of one estimator's goodness-of-fit.

**Grep before submit:** `0.96` / `0.956` near `SINDy`; `sparse` near `recover`; `corroborat`.

**Guard id:** `sindy-r2-is-not-identifiability`

---

## Pre-submission checklist

Run in the **Verify** phase, before the build. Each line is one grep over the `.tex` body.

| # | Guard id | Passes when |
|---|---|---|
| G1 | `rollout-is-censored` | every `70` is `\ge 70` / "at least 70 ms (capped)"; no `70 \pm 0` |
| G2 | `node-no-meanstd` | `3951`, `3561`, `22.4` absent; NODE reported via rollout + divergence range |
| G3 | `ensemble-is-not-independent` | `a`/`b` reported once; "ensemble" appears only for `Erev`, with the ratio rationale |
| G4 | `r2-ens-is-uninformative` | `0.997` absent; recovery quality quoted as `r2_cond_true = 0.984 ± 0.014` |
| G5 | `a-hat-not-a-recovery` | no "recover"/"within X%" for `a`/`b`/`Erev`; `1.60` always carries `± 0.90`; sanity fit cited |
| G6 | `voltage-only-no-superiority` | no "worse"/"better"/"4×"; equivalence-within-seed-noise phrasing; n=5 stated |
| G7 | `no-commoneval-voltage` | no common-eval sentence mentions voltage-only or NODE |
| G8 | `commoneval-ablation-unusable` | noise/gCa ablations cite the forecast window only |
| G9 | `commoneval-equals-forecast-at-50` | the t=50 identity is never called a check/validation |
| G10 | `retrain-gca-point-four-is-copied` | no `gCa=0.4` row in any before/after table; retrain scope stated |
| G11 | `fig7b-confounded` | `fig7b_ablation_window` absent from the main text |
| G12 | `window-nonmonotonicity-is-artifact` | the artifact sentence is in the caption; no trend claim past 20 ms |
| G13 | `ablations-are-n1` | the gCa sweep is n=5 and says so; every OTHER ablation says "single seed"; still no claim on `gCa 2.0→4.0` |
| G14 | `fig11-mixed-estimators` | fig11 caption names panel 3 as a pooled point estimate |
| G15 | `uncited-constants` | no fabricated citation keys; the "modelling choices" footnote is present |
| G16 | `single-trajectory-scope` | the scope qualifier is **in the abstract**; no "random inits" |
| G17 | `node-spike-n2` | metric dropped for NODE, or annotated `(n=2 of 5)` |
| G18 | `sindy-r2-is-not-identifiability` | SINDy framed as a negative sparsity result; its R² never beside the constrained fit's |

**The three numbers that must never appear unqualified anywhere:** `70` (G1), `3951` (G2),
`0.997` (G4).

**The one sentence that must appear in the abstract:** the single-trajectory scope qualifier (G16).

## Cross-references

- Guard mechanics, macro provenance, and the `emit: ge` / `censored_at` spec:
  [references/evidence-discipline.md](../../references/evidence-discipline.md)
- The claim ledger these ids are referenced from: [claims.yaml](claims.yaml)
- Extraction filters for every number quoted above: [metrics_map.yaml](metrics_map.yaml)
- Figure-level consequences of G11 and G14: [figure-plan.md](figure-plan.md)
- Negative-result framing (G16's rhetoric): [references/writing-craft.md](../../references/writing-craft.md)
- Hostile self-review, which is where these guards are exercised:
  [references/review-and-rebuttal.md](../../references/review-and-rebuttal.md)
