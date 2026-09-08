"""
distil_noise_weighted.py
=============================================================================
Distils the conductance out of the noise-weighted (chi2-trained) closures and
sets it beside the published, unweighted-SSE-trained result.

WHY THIS EXISTS.  noise_weighted_ude.jl retrains the UDE under the noise-weighted
likelihood instead of the unweighted sum of squares, on the argument that the
matched-objective control already showed weighting alone takes a FIXED
two-parameter fit from ~20% relative spread to ~6%.  The forecast error that
script prints is NOT the answer -- the paper's whole point is that forecast error
stays good while recovery fails.  The answer is a_hat, and this computes it.

THE ESTIMATOR IS IMPORTED, NOT REIMPLEMENTED.  fit_conductance / r2 /
cond_number / evaluate all come from scripts/symbolic_domain_comparison.py, the
script that produced the published number.  If the estimator ever changes, this
comparison changes with it and cannot silently drift.  (Its main() is guarded by
__name__, so importing runs nothing.)

DOMAIN.  traj-train only: the supervised trajectory, t <= 30 ms.  That is the
domain the paper's headline a_hat uses, and mixing domains is this project's
most-documented failure mode -- the same closure gives -0.061 on the trajectory
and -0.372 on the hull at gCa=0.4.  We fit strictly where the model was
supervised, exactly as the published traj-train row does.

ISOLATION.  Reads results_noiseweighted/calcium/ and results/identifiability/
(published, read-only).  Writes results_noiseweighted/ only.  Nothing under
results/ is modified.

Run:  python scripts/distil_noise_weighted.py
"""

import csv
import importlib.util
import math
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# --- import the published estimator, without running its main() --------------
_spec = importlib.util.spec_from_file_location(
    "sdc", ROOT / "scripts" / "symbolic_domain_comparison.py"
)
sdc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sdc)

NW = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results_noiseweighted"
CAL = NW / "calcium"
PUBLISHED_DOMAIN = ROOT / "results" / "identifiability" / "symbolic_domain_comparison.csv"
OUT = NW / "noise_weighted_recovery.csv"

SEEDS = [1111, 2222, 3333, 4444, 5555]
GCA_TRUE = 2.0
T_TRAIN_END = 30.0


def published_traj_train():
    """The published per-seed a_hat on traj-train, for a paired comparison."""
    if not PUBLISHED_DOMAIN.exists():
        return {}
    out = {}
    for r in sdc.read_csv(PUBLISHED_DOMAIN):
        if r.get("domain") == "traj-train":
            out[int(float(r["seed"]))] = float(r["a_hat"])
    return out


def main():
    if not CAL.is_dir():
        sys.exit(f"no calcium probes at {CAL} -- run noise_weighted_ude.jl first")

    pub = published_traj_train()
    rows = []
    for seed in SEEDS:
        probe = CAL / f"probe_nw_chi2_seed{seed}.csv"
        if not probe.exists():
            print(f"  [skip] seed {seed}: {probe.name} not found")
            continue
        d = sdc.read_csv(probe)
        t = sdc.col(d, "t")
        V = sdc.col(d, "V")
        s = sdc.col(d, "s")
        nn = sdc.col(d, "ICa_nn")
        tr = sdc.col(d, "ICa_true")
        k = [i for i in range(len(t)) if t[i] <= T_TRAIN_END]
        rec = sdc.evaluate([V[i] for i in k], [s[i] for i in k],
                           [nn[i] for i in k], [tr[i] for i in k],
                           "traj-train", seed)
        if rec is None:
            print(f"  [skip] seed {seed}: too few supervised points")
            continue
        rec["objective"] = "chi2"
        rec["a_hat_published_sse"] = pub.get(seed, float("nan"))
        rows.append(rec)

    if not rows:
        sys.exit("no closures distilled -- nothing to report")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    a_new = [r["a_hat"] for r in rows if not math.isnan(r["a_hat"])]
    a_pub = [r["a_hat_published_sse"] for r in rows
             if not math.isnan(r["a_hat_published_sse"])]

    def ms(v):
        if not v:
            return "n/a"
        if len(v) < 2:
            return f"{v[0]:.3f} (n=1)"
        return f"{statistics.mean(v):.3f} +- {statistics.stdev(v):.3f}"

    def relsd(v):
        if len(v) < 2 or statistics.mean(v) == 0:
            return float("nan")
        return statistics.stdev(v) / abs(statistics.mean(v))

    print("\n=== a_hat on the supervised trajectory (t <= 30 ms), true gCa = 2.0 ===\n")
    print(f"  {'seed':>6}  {'chi2-trained':>14}  {'published (SSE)':>17}")
    for r in rows:
        p = r["a_hat_published_sse"]
        ps = "n/a" if math.isnan(p) else f"{p:.3f}"
        print(f"  {r['seed']:>6}  {r['a_hat']:>14.3f}  {ps:>17}")

    print(f"\n  chi2-trained closure : {ms(a_new)}"
          f"   rel sd {relsd(a_new):.3f}" if len(a_new) > 1 else f"\n  chi2 : {ms(a_new)}")
    if a_pub:
        print(f"  published SSE arm    : {ms(a_pub)}"
              f"   rel sd {relsd(a_pub):.3f}" if len(a_pub) > 1 else "")

    print("\n  Reference points:")
    print("    published headline a_hat  1.645 +- 0.672   (rel sd 0.409)")
    print("    direct parametric fit     2.092 +- 0.130   (rel sd 0.062)")
    print("\n  READ IT THIS WAY: the question is whether the chi2-trained closure's")
    print("  SPREAD moves toward the parametric arm's. A shift in the mean alone is")
    print("  not the result -- the paper's claim is about scatter across seeds.")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
