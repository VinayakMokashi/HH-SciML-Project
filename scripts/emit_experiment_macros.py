"""
emit_experiment_macros.py
=============================================================================
Computes every DERIVED quantity the E1/E2/E3 write-up quotes and writes them to
one tidy CSV, so `paper/metrics_map.yaml` can map each macro to a single cell
instead of doing arithmetic it cannot do.

WHY A SEPARATE FILE RATHER THAN MORE MAP ENTRIES.  extract_metrics.py can take a
mean, an SD or a single cell. It cannot take a ratio of two SDs, an F statistic,
a variance component, or a count of seeds satisfying a predicate -- and those are
most of what these three experiments produced. Computing them in the map is not
possible; computing them in prose would put unsourced numbers in the paper, which
is exactly what check_numbers.py exists to prevent. So they are computed ONCE,
here, from the committed per-seed evidence, and written as data.

ISOLATION.  Reads results_noiseweighted/ and results_initdata/ (both committed
evidence).  Writes ONE file: results_noiseweighted/paper_macros_e1e3.csv.
NOTHING under results/ is read for writing or touched -- those files back the
published macros and the frozen workshop submission.

SELF-TEST.  Every quantity that also appears in a committed distillation output
is recomputed here and checked against it. If this script and the distillation
scripts ever disagree, the numbers in the paper would silently depend on which
one ran last, so a mismatch EXITS NON-ZERO. The check covers the headline
per-arm means/SDs and the variance components.

Run:  python scripts/emit_experiment_macros.py
"""

import csv
import math
import statistics
import sys
from pathlib import Path

from scipy import stats

ROOT = Path(__file__).resolve().parent.parent
NW = ROOT / "results_noiseweighted"
E3 = ROOT / "results_initdata"
OUT = NW / "paper_macros_e1e3.csv"

GCA_TRUE = 2.0
PUBLISHED_SEEDS = (1111, 2222, 3333, 4444, 5555)


def rd(p):
    with open(p, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def relsd(v):
    return statistics.stdev(v) / abs(statistics.mean(v))


rows = []


def put(quantity, value, note):
    rows.append({"quantity": quantity, "value": value, "note": note})


# =============================================================================
#  E1 — the noise-weighting effect at n=28
# =============================================================================
rec = rd(NW / "noise_weighted_recovery.csv")
a = {arm: [float(r["a_hat"]) for r in rec if r["objective"] == arm]
     for arm in ("sse", "chi2")}
by_seed = {arm: {int(float(r["seed"])): float(r["a_hat"])
                 for r in rec if r["objective"] == arm} for arm in ("sse", "chi2")}
seeds = sorted(by_seed["sse"])

put("E1N", len(a["sse"]), "seeds per arm in the noise-weighting experiment")
for arm, tag in (("sse", "Sse"), ("chi2", "Chi")):
    put(f"E1{tag}AhatMean", round(statistics.mean(a[arm]), 3), f"{arm} arm a_hat mean, n=28")
    put(f"E1{tag}AhatStd", round(statistics.stdev(a[arm]), 3), f"{arm} arm a_hat sd, n=28")
    put(f"E1{tag}RelSd", round(relsd(a[arm]), 3), f"{arm} arm a_hat relative sd, n=28")
    put(f"E1{tag}Neg", sum(1 for x in a[arm] if x < 0),
        f"{arm} arm seeds recovering a NEGATIVE conductance")
    put(f"E1{tag}Within", sum(1 for x in a[arm] if abs(x - GCA_TRUE) / GCA_TRUE <= 0.25),
        f"{arm} arm seeds within 25% of the true gCa")

F = statistics.variance(a["sse"]) / statistics.variance(a["chi2"])
d1 = d2 = len(a["sse"]) - 1
put("E1F", round(F, 3), "variance ratio sse/chi2")
put("E1Fdf", d1, "degrees of freedom, each arm")
put("E1Fp", float(f"{stats.f.sf(F, d1, d2):.4f}"), "one-sided F test p-value")
lev = stats.levene(a["sse"], a["chi2"], center="median")
put("E1LeveneP", float(f"{lev.pvalue:.3f}"), "Brown-Forsythe p-value (robust)")
w = stats.wilcoxon([abs(by_seed["sse"][s] - GCA_TRUE) for s in seeds],
                   [abs(by_seed["chi2"][s] - GCA_TRUE) for s in seeds],
                   alternative="greater")
put("E1WilcoxonP", float(f"{w.pvalue:.3f}"), "paired Wilcoxon on |a_hat-2|, sse worse")

# the published five, to show they were a benign draw
pub5 = [by_seed["sse"][s] for s in PUBLISHED_SEEDS]
put("E1SsePubFiveRelSd", round(relsd(pub5), 3), "sse relative sd over the five PUBLISHED seeds")

# forecast, paired
sm = rd(NW / "noise_weighted_summary.csv")
f = {arm: {int(float(r["seed"])): float(r["forecast_V_rmse"])
           for r in sm if r["objective"] == arm} for arm in ("sse", "chi2")}
for arm, tag in (("sse", "Sse"), ("chi2", "Chi")):
    v = [f[arm][s] for s in seeds]
    put(f"E1{tag}FcastMean", round(statistics.mean(v), 3), f"{arm} forecast V RMSE mean (mV)")
    put(f"E1{tag}FcastStd", round(statistics.stdev(v), 3), f"{arm} forecast V RMSE sd (mV)")
wf = stats.wilcoxon([f["sse"][s] for s in seeds], [f["chi2"][s] for s in seeds],
                    alternative="greater")
put("E1FcastP", float(f"{wf.pvalue:.4f}"), "paired Wilcoxon, sse forecast worse than chi2")
put("E1FcastBetter", sum(1 for s in seeds if f["chi2"][s] < f["sse"][s]),
    "seeds where chi2 forecasts better than sse")

# =============================================================================
#  E2 — the optimiser, isolated at two parameters
# =============================================================================
nm = [float(r["a_hat"]) for r in rd(NW / "parametric_chi2_28seed.csv")]
ab_rows = rd(NW / "parametric_adam_bfgs.csv")
ab = [float(r["gCa_hat"]) for r in ab_rows
      if r["scaling"] == "normalised" and int(float(r["start_idx"])) == 1]

put("E2ParamN", len(nm), "seeds in the direct two-parameter fit")
put("E2NmMean", round(statistics.mean(nm), 3), "Nelder-Mead gCa mean, n=28")
put("E2NmStd", round(statistics.stdev(nm), 3), "Nelder-Mead gCa sd, n=28")
put("E2NmRelSd", round(relsd(nm), 3), "Nelder-Mead relative sd -- the DENOMINATOR")
put("E2AbRelSd", round(relsd(ab), 3), "Adam+BFGS relative sd at two parameters")
put("E2OptRatio", round(relsd(ab) / relsd(nm), 4), "OPTIMISER share at two parameters")
put("E2ReprRatio", round(relsd(a["chi2"]) / relsd(nm), 2),
    "REPRESENTATION share: chi2 closure over the direct fit, matched objective")
put("E2SseOverParam", round(relsd(a["sse"]) / relsd(nm), 2),
    "sse closure over the direct fit (objective NOT matched)")
worst = max(abs(float(r["gCa_hat"]) - nmv) / abs(nmv)
            for r in ab_rows
            for nmv in [next(float(x["a_hat"]) for x in rd(NW / "parametric_chi2_28seed.csv")
                             if int(float(x["seed"])) == int(float(r["seed"])))])
put("E2WorstCell", float(f"{worst:.1e}"), "worst relative gCa difference over all 168 cells")
put("E2Cells", len(ab_rows), "total Adam+BFGS fits")

# ---- the missing cell: the direct fit under the closure's OWN objective, n=28 ----
# parametric_matched_objective_28seed.jl with PM_OBJECTIVE=sse_full.
import math as _m
sse_nm = [float(r["a_hat"]) for r in rd(NW / "parametric_sse_full_28seed.csv")]
put("E2SseNmMean", round(statistics.mean(sse_nm), 3), "direct fit under the UNWEIGHTED SSE, gCa mean, n=28")
put("E2SseNmStd", round(statistics.stdev(sse_nm), 3), "direct fit under the unweighted SSE, gCa sd, n=28")
put("E2SseNmRelSd", round(relsd(sse_nm), 3), "direct fit under the unweighted SSE, relative sd, n=28")

r_cs, r_cc = relsd(a["sse"]), relsd(a["chi2"])     # closure, SSE / chi2
r_ds, r_dc = relsd(sse_nm), relsd(nm)              # direct,  SSE / chi2
total      = r_cs / r_dc
obj_fit    = r_ds / r_dc     # objective effect, measured on the direct fit
obj_clo    = r_cs / r_cc     # objective effect, measured on the closure
rep_sse    = r_cs / r_ds     # representation effect under the SSE objective
rep_chi    = r_cc / r_dc     # representation effect under the chi2 objective

# The identity that makes the two orderings a decomposition at all.
for lhs, rhs, nm_ in ((obj_fit * rep_sse, total, "fit-first"),
                      (obj_clo * rep_chi, total, "closure-first")):
    if abs(lhs - rhs) / rhs > 1e-12:
        print(f"*** SELF-TEST FAILED: {nm_} ordering does not multiply to the total. ***")
        sys.exit(1)

put("DecTotal",     round(total, 2),   "closure SSE over direct chi2: the full gap, n=28 (n=5: 6.57)")
put("DecObjAtFit",  round(obj_fit, 2), "objective effect on the DIRECT fit, n=28 (n=5: 3.2)")
put("DecObjAtClo",  round(obj_clo, 2), "objective effect on the CLOSURE, n=28")
put("DecRepAtSse",  round(rep_sse, 2), "representation effect under the SSE objective, n=28 (n=5: 2.07, the old 'twofold')")
put("DecRepAtChi",  round(rep_chi, 2), "representation effect under the chi2 objective, n=28")
lo, hi = sorted((_m.log(rep_sse) / _m.log(total), _m.log(rep_chi) / _m.log(total)))
put("DecRepLogShareLo", round(lo * 100), "representation's share of the gap on a log scale, lower ordering (%) (n=5: 39, 'two-fifths')")
put("DecRepLogShareHi", round(hi * 100), "representation's share of the gap on a log scale, upper ordering (%)")

# =============================================================================
#  E3 — the variance decomposition
# =============================================================================
e3 = rd(E3 / "init_vs_data_recovery.csv")
for arm, tag in (("sse", "Sse"), ("chi2", "Chi")):
    cell = {(int(float(r["init_seed"])), int(float(r["data_seed"]))): float(r["a_hat"])
            for r in e3 if r["objective"] == arm}
    inits = sorted({i for i, _ in cell})
    datas = sorted({d for _, d in cell})
    I, D = len(inits), len(datas)
    vals = [cell[(i, d)] for i in inits for d in datas]
    grand = statistics.mean(vals)
    ss_tot = sum((v - grand) ** 2 for v in vals)
    ss_i = D * sum((statistics.mean([cell[(i, d)] for d in datas]) - grand) ** 2 for i in inits)
    ss_d = I * sum((statistics.mean([cell[(i, d)] for i in inits]) - grand) ** 2 for d in datas)
    ms_i, ms_d = ss_i / (I - 1), ss_d / (D - 1)
    ms_r = (ss_tot - ss_i - ss_d) / ((I - 1) * (D - 1))
    v_i, v_d = (ms_i - ms_r) / D, (ms_d - ms_r) / I
    tot = max(v_i, 0) + max(v_d, 0) + max(ms_r, 0)
    put(f"E3{tag}VarInit", round(v_i, 3), f"{arm}: initialisation variance component")
    put(f"E3{tag}VarData", round(v_d, 3), f"{arm}: data-draw variance component")
    put(f"E3{tag}VarInter", round(ms_r, 3), f"{arm}: interaction variance component")
    put(f"E3{tag}PctData", round(max(v_d, 0) / tot * 100), f"{arm}: data share of variance (%)")
    put(f"E3{tag}PctInter", round(max(ms_r, 0) / tot * 100), f"{arm}: interaction share (%)")
    put(f"E3{tag}FInit", round(ms_i / ms_r, 3), f"{arm}: F for initialisation")
    put(f"E3{tag}FInitP", float(f"{stats.f.sf(ms_i/ms_r, I-1, (I-1)*(D-1)):.3f}"),
        f"{arm}: p for initialisation")
    put(f"E3{tag}FData", round(ms_d / ms_r, 2), f"{arm}: F for the data draw")
    # A p-value is never zero. Anything below the printing resolution is emitted
    # as the BOUND 0.0001 and must be quoted in prose as "p < ...", never "p =".
    _pd = stats.f.sf(ms_d / ms_r, I - 1, (I - 1) * (D - 1))
    put(f"E3{tag}FDataP", max(float(f"{_pd:.4f}"), 0.0001),
        f"{arm}: p for the data draw"
        + (" -- BOUND: true value is smaller, quote as 'p <'" if _pd < 0.0001 else ""))
    put(f"E3{tag}Df", (I - 1) * (D - 1), f"{arm}: residual degrees of freedom")
put("E3Grid", I, "levels per factor in the crossed grid")
put("E3Cells", len(e3), "total cells across both arms")

# =============================================================================
#  SELF-TEST — must agree with the committed distillation outputs.
# =============================================================================
def get(q):
    return next(r["value"] for r in rows if r["quantity"] == q)


EXPECT = {  # values printed by the distillation scripts and quoted in the commits
    "E1SseAhatMean": 1.543, "E1SseAhatStd": 1.237, "E1SseRelSd": 0.802,
    "E1ChiAhatMean": 1.925, "E1ChiAhatStd": 0.605, "E1ChiRelSd": 0.314,
    "E1F": 4.177, "E1Fp": 0.0002,
    "E2NmRelSd": 0.067, "E2OptRatio": 1.0,
    "E3SseVarData": 0.286, "E3SseVarInter": 0.209,
    "E3ChiVarData": 0.25, "E3ChiVarInter": 0.031,
}
bad = [(q, get(q), v) for q, v in EXPECT.items() if abs(float(get(q)) - v) > 5e-3]
if bad:
    print("*** SELF-TEST FAILED: this script disagrees with the distillation output. ***")
    for q, got, want in bad:
        print(f"    {q}: this script {got}, distillation {want}")
    print("The paper's numbers would then depend on which script ran last.")
    sys.exit(1)
print(f"SELF-TEST PASS -- {len(EXPECT)} quantities agree with the distillation output.")

OUT.parent.mkdir(parents=True, exist_ok=True)
with open(OUT, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=["quantity", "value", "note"])
    w.writeheader()
    w.writerows(rows)
print(f"wrote {OUT}  ({len(rows)} quantities)")
