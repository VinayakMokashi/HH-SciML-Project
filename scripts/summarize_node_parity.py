#!/usr/bin/env python3
"""
summarize_node_parity.py -- the neural ODE baseline at a matched budget.

Mentor request (Prathamesh, 2026-08), point 5: "The neural ODE baseline should
receive a comparable optimisation budget and a better-justified architecture.
The current raw-time input and smaller Adam budget make the general 'impossible
versus routine' comparison difficult to defend."

Two objections are bundled there, so `node_parity.jl` separates them. Reading
the three rows in order attributes the published failure:

  published   Adam 3000, inputs = 6 states + raw t   (results/metrics_all.csv)
  timeinput   Adam 5000, inputs = 6 states + raw t   -> isolates the BUDGET
  autonomous  Adam 5000, inputs = 6 states only      -> isolates the ARCHITECTURE

The autonomous variant is the defensible one: the true system is autonomous
(a constant I_app drives it), so a right-hand side that reads the clock is more
expressive than the physics requires and can fit the training window by time
index instead of learning a vector field.

DEDUPLICATION: metrics_node_parity.csv is append-only and contains rows from the
pipeline smoke test that ran first. Smoke rows are indistinguishable in the tidy
schema, so we keep the LAST row per identity key.

Usage:  python scripts/summarize_node_parity.py
"""

import csv
import math
import statistics as st
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALL_CSV = ROOT / "results" / "metrics_all.csv"
PARITY_CSV = ROOT / "results" / "node_parity" / "metrics_node_parity.csv"
OUT_CSV = ROOT / "results" / "node_parity" / "node_parity_summary.csv"

KEY = ("model", "observed", "gCa", "noise_level", "t_train_end", "seed",
       "window", "metric")
B_GCA, B_NOISE, B_TWIN = 2.0, 0.02, 30.0
METRICS = ["V_rmse", "rollout_horizon_ms", "gate_rmse_mean", "spike_count_diff"]

# (display label, source file, model name in the tidy table, short key).
# The short key is what metrics_map.yaml filters on: the display labels contain
# parentheses and runs of spaces and make brittle YAML filters.
ROWS = [
    ("NODE published (Adam 3000, +time)", ALL_CSV, "NODE", "published_time"),
    ("NODE parity   (Adam 5000, +time)", PARITY_CSV, "NODE_time_parity", "parity_time"),
    ("NODE parity   (Adam 5000, autonomous)", PARITY_CSV, "NODE_auto_parity", "parity_auto"),
    ("UDE full-state (Adam 5000)", ALL_CSV, "UDE", "ude_full"),
]


def load(path):
    if not path.exists():
        return []
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def dedupe_last(rows):
    d = OrderedDict()
    for r in rows:
        d[tuple(r[k] for k in KEY)] = r
    return list(d.values())


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def collect(rows, model, metric):
    """Per-seed values for one model/metric at the baseline condition."""
    out = {}
    for r in rows:
        if r["model"] != model or r["window"] != "forecast" or r["metric"] != metric:
            continue
        if model == "UDE" and r["observed"] != "full":
            continue
        if (num(r["gCa"]) != B_GCA or num(r["noise_level"]) != B_NOISE
                or num(r["t_train_end"]) != B_TWIN):
            continue
        v = num(r["value"])
        if v is not None and math.isfinite(v):
            out[int(float(r["seed"]))] = v
    return out


def fmt(vals):
    if not vals:
        return "--", ""
    v = list(vals.values())
    if len(v) == 1:
        return f"{v[0]:.4g}", f"n=1 (seed {list(vals)[0]})"
    return f"{st.mean(v):.4g} +/- {st.stdev(v):.3g}", f"n={len(v)}"


def main():
    raw_all = load(ALL_CSV)
    raw_par = load(PARITY_CSV)
    par = dedupe_last(raw_par)
    print(f"metrics_node_parity.csv: {len(raw_par)} rows -> {len(par)} after dedupe-by-last\n")

    cache = {}
    out_rows = []
    for label, path, model, key in ROWS:
        src = raw_all if path == ALL_CSV else par
        for m in METRICS:
            cache[(label, m)] = collect(src, model, m)

    hdr = f"{'model':<40}"
    for m in METRICS:
        hdr += f"{m:>26}"
    print(hdr)
    print("-" * len(hdr))
    for label, _, _, key in ROWS:
        line = f"{label:<40}"
        for m in METRICS:
            s, _ = fmt(cache[(label, m)])
            line += f"{s:>26}"
        print(line)
        for m in METRICS:
            vals = cache[(label, m)]
            if vals:
                v = list(vals.values())
                out_rows.append({
                    "key": key, "model": label, "metric": m, "n": len(v),
                    "mean": st.mean(v),
                    "sd": st.stdev(v) if len(v) > 1 else float("nan"),
                    "median": st.median(v),
                    "min": min(v), "max": max(v),
                    "seeds": ";".join(str(k) for k in sorted(vals)),
                    "values": ";".join(f"{vals[k]:.10g}" for k in sorted(vals)),
                })

    print("\nseed coverage:")
    for label, _, _, _k in ROWS:
        vals = cache[(label, "V_rmse")]
        print(f"  {label:<40} seeds {sorted(vals) if vals else '(none)'}")

    with open(OUT_CSV, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        w.writerows(out_rows)
    print(f"\nwrote {OUT_CSV}")

    # Attribution, on the seeds the two parity variants actually share.
    ti = cache[("NODE parity   (Adam 5000, +time)", "rollout_horizon_ms")]
    au = cache[("NODE parity   (Adam 5000, autonomous)", "rollout_horizon_ms")]
    pub = cache[("NODE published (Adam 3000, +time)", "rollout_horizon_ms")]
    shared = sorted(set(ti) & set(au))
    print("\nAttribution (rollout horizon, ms -- higher is better):")
    if pub:
        print(f"  published  (3000, +time)  : {st.mean(list(pub.values())):.3f}  n={len(pub)}")
    if ti:
        print(f"  parity     (5000, +time)  : {st.mean(list(ti.values())):.3f}  n={len(ti)}"
              "   <- budget effect vs published")
    if shared:
        print(f"  parity     (5000, autonom): "
              f"{st.mean([au[s] for s in shared]):.3f}  n={len(shared)}"
              "   <- architecture effect vs the row above")
        print(f"  (compared on shared seeds {shared}; "
              f"+time on those seeds = {st.mean([ti[s] for s in shared]):.3f})")


if __name__ == "__main__":
    main()
