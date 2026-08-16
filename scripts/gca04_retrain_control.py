#!/usr/bin/env python3
"""
gca04_retrain_control.py -- does the physiological failure survive a 4x budget?

Discharges the ledger tombstone `retrain-negative-control-replicates`.

Background. The aggressive-retrain control was run only at gCa=2.0. Its script
then COPIED the baseline gCa=0.4 probe into its own output tree so the symbolic
stage could find a negative control in one place. The consequence was a trap: the
gCa=0.4 row of the "after" results was byte-identical to the "before" row, so a
before/after table showed matching numbers in the control row and read exactly
like a successful replication, when in fact nothing had been rerun.

`retrain_gca2_20k.jl` now takes RETRAIN_GCA / RETRAIN_SEEDS / RETRAIN_OUT (all
defaulting to the published configuration) and skips that copy when gCa != 2.0.
The genuine gCa=0.4 run at Adam 20000 / BFGS 1000 lives in
results/retrain_gca04_20k/. This script applies the SAME conductance-form
estimator to before and after and reports whether the wrong-sign failure holds.

Estimator and domains are imported from symbolic_domain_comparison.py so this is
provably the same fit, not a re-implementation of it.

Usage:  python scripts/gca04_retrain_control.py
"""

import csv
import importlib.util
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Import the sibling module by path (scripts/ is not a package).
_spec = importlib.util.spec_from_file_location(
    "sdc", ROOT / "scripts" / "symbolic_domain_comparison.py")
sdc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sdc)

GCA_TRUE = 0.4
ECA_TRUE = 120.0
T_TRAIN_END = 30.0
OUT = ROOT / "results" / "identifiability" / "gca04_retrain_control.csv"

CASES = [
    ("before", ROOT / "results" / "calcium" / "probe_abl_gca_0.4_seed1111.csv",
               ROOT / "results" / "calcium" / "grid_abl_gca_0.4_seed1111.csv"),
    ("after",  ROOT / "results" / "retrain_gca04_20k" / "calcium" / "probe_ude_full_seed1111.csv",
               ROOT / "results" / "retrain_gca04_20k" / "calcium" / "grid_ude_full_seed1111.csv"),
]


def analyse(label, probe_path, grid_path):
    traj = sdc.read_csv(probe_path)
    grid = sdc.read_csv(grid_path)
    tV, ts = sdc.col(traj, "V"), sdc.col(traj, "s")
    tnn, ttr = sdc.col(traj, "ICa_nn"), sdc.col(traj, "ICa_true")
    tt = sdc.col(traj, "t")
    gV, gs = sdc.col(grid, "V"), sdc.col(grid, "s")
    gnn, gtr = sdc.col(grid, "ICa_nn"), sdc.col(grid, "ICa_true")

    rows = []

    hull = sdc.convex_hull(list(zip(tV, ts)))
    keep = [i for i in range(len(gV)) if sdc.in_hull((gV[i], gs[i]), hull)]
    r = sdc.evaluate([gV[i] for i in keep], [gs[i] for i in keep],
                     [gnn[i] for i in keep], [gtr[i] for i in keep], "hull", 1111)
    r["case"] = label
    rows.append(r)

    k = [i for i in range(len(tt)) if tt[i] <= T_TRAIN_END]
    r = sdc.evaluate([tV[i] for i in k], [ts[i] for i in k],
                     [tnn[i] for i in k], [ttr[i] for i in k], "traj-train", 1111)
    r["case"] = label
    rows.append(r)
    return rows


def main():
    for _, p, g in CASES:
        if not p.exists() or not g.exists():
            raise SystemExit(f"missing input: {p if not p.exists() else g}")

    out = []
    for label, p, g in CASES:
        out.extend(analyse(label, p, g))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    fields = ["case", "domain", "seed", "n", "a_hat", "b_hat", "Erev",
              "r2_vs_true_on_domain", "r2_vs_nn_on_domain", "cond",
              "a_sanity_true_current", "b_sanity_true_current"]
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(out)

    print(f"Aggressive-retrain negative control at gCa = {GCA_TRUE} "
          f"(true a = {GCA_TRUE}, true b = {-GCA_TRUE * ECA_TRUE})\n")
    print(f"{'case':<8} {'domain':<12} {'n':>5} {'a_hat':>9} {'b_hat':>10} "
          f"{'R2 vs true':>11}  sign")
    print("-" * 66)
    for r in out:
        sign = "CORRECT (+)" if r["a_hat"] > 0 else "WRONG (-)"
        print(f"{r['case']:<8} {r['domain']:<12} {r['n']:>5} {r['a_hat']:>9.4f} "
              f"{r['b_hat']:>10.2f} {r['r2_vs_true_on_domain']:>11.4f}  {sign}")

    # The load-bearing question: does the sign failure replicate?
    print()
    for dom in ("hull", "traj-train"):
        b = next(r for r in out if r["case"] == "before" and r["domain"] == dom)
        a = next(r for r in out if r["case"] == "after" and r["domain"] == dom)
        same = (b["a_hat"] < 0) == (a["a_hat"] < 0)
        print(f"  {dom:<12}: a_hat {b['a_hat']:+.4f} -> {a['a_hat']:+.4f}   "
              f"sign {'REPLICATES' if same else 'CHANGES'}"
              f"{'' if same else '  <-- report this, it weakens the control'}")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
