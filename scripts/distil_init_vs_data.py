"""
distil_init_vs_data.py
=============================================================================
Distils the conductance out of the crossed init x data grid and decomposes the
seed-to-seed spread into an INITIALISATION component and a DATA component.

WHY THIS EXISTS.  Every gCa spread this project reports is a spread across
SEEDS, and a seed sets two independent things: the network initialisation
(make_ca_network -> StableRNG(seed)) and the noise draw (gen_noisy_data -> a
fresh StableRNG(seed)).  run_ude passes the same integer to both, so the
reported number is a JOINT init-and-data spread that has never been split.
init_vs_data_grid.jl crosses them; this reads the result.

E1 MADE THIS MORE URGENT, NOT LESS.  The SSE arm's relative spread is 0.802 at
n=28, not the 0.408 the published five seeds suggested, and three of 28 seeds
recover a NEGATIVE conductance.  A failure that large deserves an address.  If
it is the data draw, the closure is hostage to one noise realisation.  If it is
the initialisation, the closure finds different optima on identical data.  The
remedies differ.

THE ESTIMATOR IS IMPORTED, NOT REIMPLEMENTED -- fit_conductance / evaluate come
from scripts/symbolic_domain_comparison.py, the script that produced the
published number, exactly as scripts/distil_noise_weighted.py does.

DOMAIN.  traj-train only (t <= 30 ms), the domain the paper's headline a_hat
uses.  Mixing domains is this project's most-documented failure mode.

THE DECOMPOSITION.  A two-way crossed random-effects model with one observation
per cell:

    a[i,d] = mu + alpha_i + beta_d + eps[i,d]

    MS_init  = D * sum_i (mean_i - grand)^2 / (I-1)
    MS_data  = I * sum_d (mean_d - grand)^2 / (D-1)
    MS_resid = (SS_total - SS_init - SS_data) / ((I-1)(D-1))

    var_init = (MS_init - MS_resid) / D
    var_data = (MS_data - MS_resid) / I
    var_resid = MS_resid

WHAT THE RESIDUAL IS, AND WHY IT IS NOT "NOISE".  With one run per cell the
interaction is confounded with everything else, so var_resid holds BOTH the
genuine init x data interaction AND any run-to-run irreproducibility.  Training
here is deterministic given (init, data), so there is no run-to-run term: the
residual IS the interaction.  Report it as such -- a large residual means init
and data matter jointly, not that the estimate is noisy.

A NEGATIVE VARIANCE COMPONENT IS A REAL POSSIBILITY, not an error.  The
method-of-moments estimator can go below zero when the true component is near
zero; it is reported as estimated and floored at zero only for the percentage
split, with the raw value shown alongside.

SELF-TEST.  The diagonal cells must reproduce E1's per-seed a_hat from
results_noiseweighted/noise_weighted_recovery.csv.  A diagonal cell and an E1
run are the same computation under two names, so a mismatch means the crossing
is wrong and the off-diagonal cells mean nothing.  Exits non-zero.

ISOLATION.  Reads results_initdata/ and results_noiseweighted/ (read-only).
Writes results_initdata/ only.  Nothing under results/ is touched.

Run:  python scripts/distil_init_vs_data.py [results_dir]
"""

import csv
import importlib.util
import math
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location(
    "sdc", ROOT / "scripts" / "symbolic_domain_comparison.py"
)
sdc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sdc)

E3 = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results_initdata"
CAL = E3 / "calcium"
E1_RECOVERY = ROOT / "results_noiseweighted" / "noise_weighted_recovery.csv"
OUT = E3 / "init_vs_data_recovery.csv"

GCA_TRUE = 2.0
T_TRAIN_END = 30.0
ARMS = ("sse", "chi2")
SELFTEST_RTOL = 1e-6

# The trailing "_seed<n>" is appended by _calcium_id (src/experiment.jl:274)
# because the E3 tag does not already end in one. Optional here so the pattern
# holds whether or not that ever changes.
PROBE = re.compile(r"^probe_e3_(sse|chi2)_i(\d+)_d(\d+)(?:_seed\d+)?\.csv$")


def distil(path, seed):
    d = sdc.read_csv(path)
    t, V = sdc.col(d, "t"), sdc.col(d, "V")
    s, nn = sdc.col(d, "s"), sdc.col(d, "ICa_nn")
    tr = sdc.col(d, "ICa_true")
    k = [i for i in range(len(t)) if t[i] <= T_TRAIN_END]
    return sdc.evaluate([V[i] for i in k], [s[i] for i in k],
                        [nn[i] for i in k], [tr[i] for i in k], "traj-train", seed)


def decompose(cell, inits, datas):
    """Two-way crossed random-effects components. `cell` maps (i,d) -> a_hat."""
    I, D = len(inits), len(datas)
    vals = [cell[(i, d)] for i in inits for d in datas]
    grand = statistics.mean(vals)
    row_m = {i: statistics.mean([cell[(i, d)] for d in datas]) for i in inits}
    col_m = {d: statistics.mean([cell[(i, d)] for i in inits]) for d in datas}

    ss_total = sum((v - grand) ** 2 for v in vals)
    ss_init = D * sum((row_m[i] - grand) ** 2 for i in inits)
    ss_data = I * sum((col_m[d] - grand) ** 2 for d in datas)
    ss_resid = ss_total - ss_init - ss_data

    ms_init = ss_init / (I - 1)
    ms_data = ss_data / (D - 1)
    ms_resid = ss_resid / ((I - 1) * (D - 1))

    return {
        "grand": grand, "I": I, "D": D,
        "var_init": (ms_init - ms_resid) / D,
        "var_data": (ms_data - ms_resid) / I,
        "var_resid": ms_resid,
        "ms_init": ms_init, "ms_data": ms_data, "ms_resid": ms_resid,
        "F_init": ms_init / ms_resid if ms_resid > 0 else float("nan"),
        "F_data": ms_data / ms_resid if ms_resid > 0 else float("nan"),
        "df1": I - 1, "df2": (I - 1) * (D - 1),
        "total_var_across_cells": statistics.variance(vals),
        "diagonal": [cell[(i, i)] for i in inits if (i, i) in cell],
    }


try:
    from scipy import stats as _st
except Exception:                                          # pragma: no cover
    _st = None


def pval(F, d1, d2):
    if _st is None or not math.isfinite(F) or F <= 0:
        return float("nan")
    return float(_st.f.sf(F, d1, d2))


def main():
    if not CAL.is_dir():
        sys.exit(f"no probes at {CAL} -- run init_vs_data_grid.jl first")

    found = {}
    for p in CAL.glob("probe_e3_*.csv"):
        m = PROBE.match(p.name)
        if m:
            found[(m.group(1), int(m.group(2)), int(m.group(3)))] = p
    if not found:
        sys.exit(f"no probe matched the expected pattern in {CAL}")

    rows, cells = [], {arm: {} for arm in ARMS}
    for (arm, i, d), p in sorted(found.items()):
        r = distil(p, d)
        if r is None:
            print(f"  [skip] {arm} i={i} d={d}: too few supervised points")
            continue
        r.update({"objective": arm, "init_seed": i, "data_seed": d,
                  "on_diagonal": i == d})
        rows.append(r)
        cells[arm][(i, d)] = r["a_hat"]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    # --- SELF-TEST: the diagonal must be E1 ----------------------------------
    print("\n=== SELF-TEST: diagonal cells vs E1's per-seed a_hat ===")
    if not E1_RECOVERY.exists():
        print(f"  SKIPPED -- {E1_RECOVERY} not found.")
    else:
        e1 = {(r["objective"], int(float(r["seed"]))): float(r["a_hat"])
              for r in sdc.read_csv(E1_RECOVERY)}
        worst, n = 0.0, 0
        for arm in ARMS:
            for (i, d), v in sorted(cells[arm].items()):
                if i != d or (arm, i) not in e1:
                    continue
                ref = e1[(arm, i)]
                rel = abs(v - ref) / max(abs(ref), 1e-12)
                print(f"  {arm:>4} seed {i:>6}: {v:8.4f} vs E1 {ref:8.4f}   rel {rel:.3e}")
                worst = max(worst, rel); n += 1
        if n == 0:
            sys.exit("  *** no diagonal cell matched an E1 row -- cannot verify. ***")
        if worst > SELFTEST_RTOL:
            print("\n*** SELF-TEST FAILED. ***")
            print("A diagonal cell and an E1 run are the same computation under two")
            print("names. They differ, so the crossing is wrong and nothing off the")
            print("diagonal can be trusted.")
            sys.exit(1)
        print(f"  PASS -- {n} diagonal cells, worst rel diff {worst:.3e}.")

    # --- the grids and the decomposition -------------------------------------
    for arm in ARMS:
        c = cells[arm]
        if not c:
            continue
        inits = sorted({i for i, _ in c})
        datas = sorted({d for _, d in c})
        if not all((i, d) in c for i in inits for d in datas):
            print(f"\n[{arm}] grid incomplete ({len(c)} of {len(inits)*len(datas)} cells)"
                  f" -- decomposition needs a full grid, skipping it.")
            continue

        print(f"\n=== {arm.upper()} arm: a_hat[init, data], true gCa = {GCA_TRUE} ===")
        print("        data ->  " + "".join(f"{d:>9}" for d in datas) + "     row mean")
        for i in inits:
            r = [c[(i, d)] for d in datas]
            marks = "".join(f"{c[(i,d)]:>9.3f}" for d in datas)
            print(f"  init {i:>6}: {marks}   {statistics.mean(r):>9.3f}")
        print("  col mean :  " +
              "".join(f"{statistics.mean([c[(i,d)] for i in inits]):>9.3f}" for d in datas))

        r = decompose(c, inits, datas)
        diag = r["diagonal"]
        print(f"\n  --- variance decomposition ({r['I']}x{r['D']} crossed, 1 run/cell) ---")
        tot = max(r["var_init"], 0) + max(r["var_data"], 0) + max(r["var_resid"], 0)
        for name, key in (("initialisation", "var_init"), ("data draw", "var_data"),
                          ("interaction", "var_resid")):
            v = r[key]
            pct = (max(v, 0) / tot * 100) if tot > 0 else float("nan")
            note = "  (negative estimate -> component is ~0)" if v < 0 else ""
            print(f"    {name:<15} var {v:>10.5f}   sd {math.sqrt(max(v,0)):>7.4f}"
                  f"   {pct:5.1f}%{note}")
        print(f"    {'TOTAL (cells)':<15} var {r['total_var_across_cells']:>10.5f}"
              f"   sd {math.sqrt(r['total_var_across_cells']):>7.4f}")
        print(f"\n    F_init = {r['F_init']:.3f} on F({r['df1']},{r['df2']})"
              f"   p = {pval(r['F_init'], r['df1'], r['df2']):.4f}")
        print(f"    F_data = {r['F_data']:.3f} on F({r['df1']},{r['df2']})"
              f"   p = {pval(r['F_data'], r['df1'], r['df2']):.4f}")

        if len(diag) > 1:
            dm, ds = statistics.mean(diag), statistics.stdev(diag)
            allv = [c[(i, d)] for i in inits for d in datas]
            am, asd = statistics.mean(allv), statistics.stdev(allv)
            print(f"\n    diagonal only (what the paper measures): "
                  f"{dm:.3f} +- {ds:.3f}   rel sd {ds/abs(dm):.3f}   n={len(diag)}")
            print(f"    the full crossed grid:                   "
                  f"{am:.3f} +- {asd:.3f}   rel sd {asd/abs(am):.3f}   n={len(allv)}")

    print("\n  HOW TO READ IT. The interaction term is not noise: training is")
    print("  deterministic given (init, data), so a large residual means the two")
    print("  factors matter JOINTLY -- a given initialisation is good or bad")
    print("  depending on which noise draw it meets. That is a stronger statement")
    print("  than either main effect and it is the one to check first.")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
