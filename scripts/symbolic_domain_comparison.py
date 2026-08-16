#!/usr/bin/env python3
"""
symbolic_domain_comparison.py -- refit the conductance form on restricted domains.

Mentor request (Prathamesh, 2026-08), point 3: "Please revisit the convex-hull
evaluation. The training trajectory is nearly one-dimensional, and points inside
its two-dimensional convex hull were not necessarily visited or supervised. The
symbolic analysis should be restricted to the observed trajectory, a controlled
neighbourhood around it, or multiple trajectories that genuinely cover the
region."

The objection is sound. The published fit evaluates the trained closure on an
80x80 grid masked to the convex hull of the trajectory's (V,s) cloud. A limit
cycle is a closed loop, and the interior of a loop is not visited: the hull
interior is a region where the network was never supervised and its values there
are extrapolation dressed up as interpolation.

This script refits the SAME conductance form I_Ca = s^2(aV + b) on four nested
domains and reports how the recovered coefficients move:

  hull        -- the published domain (grid inside the trajectory's convex hull)
  tube-eps    -- grid points within eps of the trajectory in the network's own
                 input coordinates (V/100, s): a controlled neighbourhood
  traj-full   -- the observed trajectory only, all 100 ms
  traj-train  -- the observed trajectory over t <= 30 ms only, i.e. strictly the
                 points that were actually supervised

Column `cond` is the 2-norm condition number of the design matrix [V s^2, s^2].
It quantifies the original methodological finding: on the trajectory alone the
two regressors are nearly collinear, so the split into a and b is ill-posed even
though the fitted CURVE is fine.

Nothing is retrained. This reads only the calcium probes already on disk. The
`hull` column is a re-implementation of the Julia routine in
objective3_symbolic.jl (convex hull + `hcat(V.*s.^2, s.^2) \\ y`), and the script
checks it against the published per-seed a_hat values as a correctness test.

Usage:  python scripts/symbolic_domain_comparison.py
"""

import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAL = ROOT / "results" / "calcium"
PUBLISHED = ROOT / "results" / "symbolic" / "symbolic_recovery_metrics.csv"
OUT = ROOT / "results" / "identifiability" / "symbolic_domain_comparison.csv"

SEEDS = [1111, 2222, 3333, 4444, 5555]
GCA_TRUE = 2.0
ECA_TRUE = 120.0
T_TRAIN_END = 30.0
TUBE_EPS = [0.02, 0.05, 0.10]      # in (V/100, s) units


# ---------------------------------------------------------------- geometry
def convex_hull(points):
    """Andrew's monotone chain; mirrors convex_hull() in objective3_symbolic.jl."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def in_hull(pt, hull):
    """Inside-or-on test for a counter-clockwise hull; mirrors in_hull()."""
    n = len(hull)
    for i in range(n):
        a, b = hull[i], hull[(i + 1) % n]
        cr = (b[0] - a[0]) * (pt[1] - a[1]) - (b[1] - a[1]) * (pt[0] - a[0])
        if cr < -1e-12:
            return False
    return True


# ------------------------------------------------------------------ linalg
def fit_conductance(V, s, y):
    """OLS for y ~ a*(V s^2) + b*(s^2); the normal equations of a 2-column fit."""
    x1 = [V[i] * s[i] ** 2 for i in range(len(V))]
    x2 = [s[i] ** 2 for i in range(len(V))]
    s11 = sum(a * a for a in x1)
    s12 = sum(x1[i] * x2[i] for i in range(len(x1)))
    s22 = sum(a * a for a in x2)
    t1 = sum(x1[i] * y[i] for i in range(len(x1)))
    t2 = sum(x2[i] * y[i] for i in range(len(x2)))
    det = s11 * s22 - s12 * s12
    if abs(det) < 1e-300:
        return float("nan"), float("nan")
    return (s22 * t1 - s12 * t2) / det, (s11 * t2 - s12 * t1) / det


def cond_number(V, s):
    """2-norm condition number of [V s^2, s^2] via the 2x2 Gram matrix."""
    x1 = [V[i] * s[i] ** 2 for i in range(len(V))]
    x2 = [s[i] ** 2 for i in range(len(V))]
    a = sum(v * v for v in x1)
    b = sum(x1[i] * x2[i] for i in range(len(x1)))
    d = sum(v * v for v in x2)
    tr, det = a + d, a * d - b * b
    disc = max(tr * tr / 4 - det, 0.0)
    lo, hi = tr / 2 - math.sqrt(disc), tr / 2 + math.sqrt(disc)
    if lo <= 0:
        return float("inf")
    return math.sqrt(hi / lo)          # singular values are sqrt of Gram eigenvalues


def r2(pred, targ):
    m = sum(targ) / len(targ)
    ss = sum((t - m) ** 2 for t in targ)
    if ss == 0:
        return float("nan")
    return 1 - sum((targ[i] - pred[i]) ** 2 for i in range(len(targ))) / ss


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def col(rows, name):
    return [float(r[name]) for r in rows]


# -------------------------------------------------------------------- main
def evaluate(V, s, y_nn, y_true, label, seed):
    """Fit the conductance form on one domain and score it against truth there."""
    if len(V) < 3:
        return None
    a, b = fit_conductance(V, s, y_nn)
    a_s, b_s = fit_conductance(V, s, y_true)     # same estimator on the TRUE current
    pred = [a * V[i] * s[i] ** 2 + b * s[i] ** 2 for i in range(len(V))]
    return {
        "seed": seed, "domain": label, "n": len(V),
        "a_hat": a, "b_hat": b,
        "Erev": (-b / a) if a not in (0.0,) and not math.isnan(a) else float("nan"),
        "r2_vs_true_on_domain": r2(pred, y_true),
        "r2_vs_nn_on_domain": r2(pred, y_nn),
        "cond": cond_number(V, s),
        "a_sanity_true_current": a_s, "b_sanity_true_current": b_s,
    }


def main():
    published = {}
    if PUBLISHED.exists():
        for r in read_csv(PUBLISHED):
            if abs(float(r["gCa"]) - GCA_TRUE) < 1e-9:
                published[int(r["seed"])] = float(r["a_hat"])

    out = []
    for seed in SEEDS:
        traj = read_csv(CAL / f"probe_ude_full_seed{seed}.csv")
        grid = read_csv(CAL / f"grid_ude_full_seed{seed}.csv")

        tV, ts = col(traj, "V"), col(traj, "s")
        tnn, ttr = col(traj, "ICa_nn"), col(traj, "ICa_true")
        tt = col(traj, "t")
        gV, gs = col(grid, "V"), col(grid, "s")
        gnn, gtr = col(grid, "ICa_nn"), col(grid, "ICa_true")

        # (1) published domain: grid masked to the trajectory's convex hull
        hull = convex_hull(list(zip(tV, ts)))
        keep = [i for i in range(len(gV)) if in_hull((gV[i], gs[i]), hull)]
        out.append(evaluate([gV[i] for i in keep], [gs[i] for i in keep],
                            [gnn[i] for i in keep], [gtr[i] for i in keep],
                            "hull", seed))

        # (2) controlled neighbourhoods: grid points within eps of the trajectory,
        #     measured in the network's own input coordinates (V/100, s).
        tn = [(tV[i] / 100.0, ts[i]) for i in range(len(tV))]
        for eps in TUBE_EPS:
            keep = []
            for i in range(len(gV)):
                p = (gV[i] / 100.0, gs[i])
                for q in tn:
                    if (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 <= eps * eps:
                        keep.append(i)
                        break
            out.append(evaluate([gV[i] for i in keep], [gs[i] for i in keep],
                                [gnn[i] for i in keep], [gtr[i] for i in keep],
                                f"tube{eps:g}", seed))

        # (3) the observed trajectory itself
        out.append(evaluate(tV, ts, tnn, ttr, "traj-full", seed))

        # (4) strictly the supervised part of it
        k = [i for i in range(len(tt)) if tt[i] <= T_TRAIN_END]
        out.append(evaluate([tV[i] for i in k], [ts[i] for i in k],
                            [tnn[i] for i in k], [ttr[i] for i in k],
                            "traj-train", seed))

    out = [r for r in out if r]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    # correctness test: our `hull` column must reproduce the published a_hat
    print("Correctness check -- reimplemented `hull` fit vs published a_hat:")
    ok = True
    for r in out:
        if r["domain"] == "hull" and r["seed"] in published:
            d = abs(r["a_hat"] - published[r["seed"]])
            flag = "ok" if d < 1e-6 else "MISMATCH"
            if d >= 1e-6:
                ok = False
            print(f"  seed {r['seed']}: {r['a_hat']:.6f} vs {published[r['seed']]:.6f}  "
                  f"(diff {d:.2e}) {flag}")
    print("  => reimplementation validated\n" if ok else
          "  => WARNING: does not reproduce the published fit; treat with caution\n")

    order = ["hull"] + [f"tube{e:g}" for e in TUBE_EPS] + ["traj-full", "traj-train"]
    print(f"{'domain':<12} {'n':>6} {'cond':>10}   a_hat (true 2.0)            "
          f"b_hat (true -240)          R2 vs true")
    print("-" * 104)
    for dom in order:
        rs = [r for r in out if r["domain"] == dom]
        if not rs:
            continue
        a = [r["a_hat"] for r in rs]
        b = [r["b_hat"] for r in rs]
        rr = [r["r2_vs_true_on_domain"] for r in rs]
        n = sum(r["n"] for r in rs) // len(rs)
        cd = sum(r["cond"] for r in rs) / len(rs)

        def ms(v):
            m = sum(v) / len(v)
            sd = math.sqrt(sum((x - m) ** 2 for x in v) / (len(v) - 1)) if len(v) > 1 else 0.0
            return m, sd

        am, asd = ms(a)
        bm, bsd = ms(b)
        rm, _ = ms(rr)
        print(f"{dom:<12} {n:>6} {cd:>10.1f}   {am:7.3f} +/- {asd:6.3f} "
              f"[{min(a):6.2f},{max(a):6.2f}]   {bm:8.1f} +/- {bsd:6.1f}   {rm:8.4f}")

    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
