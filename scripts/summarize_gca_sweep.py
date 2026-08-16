#!/usr/bin/env python3
"""
summarize_gca_sweep.py -- assemble the five-seed conductance sweep.

Mentor request (Prathamesh, 2026-08), point 5: the gCa sweep was single-seed and
must not be presented as a quantitative identifiability boundary until it is
repeated across all five seeds.

The sweep is assembled from two sources, because only the missing cells were
re-run:

  * gCa = 2.0  -- all five seeds already existed as the headline `ude_full`
                  baseline runs, in results/metrics_all.csv.
  * gCa in {0.4, 1.0, 4.0}
               -- seed 1111 already existed as the published single-seed
                  ablation (tag abl_gca_*), also in results/metrics_all.csv;
                  seeds 2222-5555 come from results/gca_sweep_5seed/.

IMPORTANT (deduplication): metrics_gca_sweep.csv is append-only and contains
rows from the pipeline smoke test that ran before the real sweep.  Smoke rows
are indistinguishable from real ones in the tidy schema -- same columns, no
iteration count -- so we keep the LAST row for each
(model, observed, gCa, noise_level, t_train_end, seed, window, metric) key.  The
real run always writes after the smoke run, so last-wins is correct.

Usage:  python scripts/summarize_gca_sweep.py
"""

import csv
import statistics as st
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALL_CSV = ROOT / "results" / "metrics_all.csv"
SWEEP_CSV = ROOT / "results" / "gca_sweep_5seed" / "metrics_gca_sweep.csv"
OUT_CSV = ROOT / "results" / "gca_sweep_5seed" / "gca_sweep_multiseed.csv"

KEY = ("model", "observed", "gCa", "noise_level", "t_train_end", "seed",
       "window", "metric")

B_NOISE, B_TWIN = 0.02, 30.0
GCAS = [0.4, 1.0, 2.0, 4.0]
SEEDS = [1111, 2222, 3333, 4444, 5555]
METRICS = ["ICa_rmse_norm", "ICa_rmse", "V_rmse", "rollout_horizon_ms"]


def load(path):
    if not path.exists():
        return []
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def dedupe_last(rows):
    """Keep the last row per identity key (smoke rows are written first)."""
    d = OrderedDict()
    for r in rows:
        d[tuple(r[k] for k in KEY)] = r
    return list(d.values())


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    raw_all = load(ALL_CSV)
    raw_sweep = load(SWEEP_CSV)
    sweep = dedupe_last(raw_sweep)
    print(f"metrics_all.csv        : {len(raw_all)} rows")
    print(f"metrics_gca_sweep.csv  : {len(raw_sweep)} rows -> {len(sweep)} after dedupe-by-last")

    # index: (gCa, seed, metric) -> value, forecast window, UDE full-state,
    # baseline noise and training window only.
    table = {}
    provenance = {}

    def ingest(rows, tag):
        for r in rows:
            if r["model"] != "UDE" or r["observed"] != "full":
                continue
            if r["window"] != "forecast":
                continue
            if num(r["noise_level"]) != B_NOISE or num(r["t_train_end"]) != B_TWIN:
                continue
            g, s, m, v = num(r["gCa"]), int(float(r["seed"])), r["metric"], num(r["value"])
            if g is None or m not in METRICS:
                continue
            if not any(abs(g - t) < 1e-9 for t in GCAS) or s not in SEEDS:
                continue
            g = [t for t in GCAS if abs(g - t) < 1e-9][0]
            table[(g, s, m)] = v
            provenance[(g, s)] = tag

    # metrics_all first, then the new sweep (new cells only; no overlap expected)
    ingest(raw_all, "published")
    ingest(sweep, "new-sweep")

    out_rows = []
    print(f"\n{'gCa':>5} {'metric':<20} {'n':>2}  {'mean':>10} {'sd':>9}  per-seed")
    print("-" * 96)
    for m in METRICS:
        for g in GCAS:
            vals = [(s, table[(g, s, m)]) for s in SEEDS if (g, s, m) in table]
            if not vals:
                continue
            v = [x for _, x in vals]
            mean = st.mean(v)
            sd = st.stdev(v) if len(v) > 1 else float("nan")
            per = " ".join(f"{x:.4g}" for x in v)
            print(f"{g:>5} {m:<20} {len(v):>2}  {mean:>10.4f} {sd:>9.4f}  {per}")
            out_rows.append({
                "gCa": g, "metric": m, "n": len(v), "mean": mean, "sd": sd,
                "min": min(v), "max": max(v),
                "seeds": ";".join(str(s) for s, _ in vals),
                "values": ";".join(f"{x:.10g}" for _, x in vals),
                "sources": ";".join(sorted({provenance[(g, s)] for s, _ in vals})),
            })
        print()

    with open(OUT_CSV, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        w.writerows(out_rows)
    print(f"wrote {OUT_CSV}")

    # The load-bearing question: with error bars, which steps of the sweep are
    # actually separated?
    print("\nSeparation of adjacent gCa steps on ICa_rmse_norm "
          "(gap vs pooled SD; |gap| > 2 pooled SD is a clear separation):")
    key = "ICa_rmse_norm"
    for a, b in zip(GCAS, GCAS[1:]):
        ra = next((r for r in out_rows if r["metric"] == key and r["gCa"] == a), None)
        rb = next((r for r in out_rows if r["metric"] == key and r["gCa"] == b), None)
        if not ra or not rb:
            continue
        gap = ra["mean"] - rb["mean"]
        pooled = ((ra["sd"] ** 2 + rb["sd"] ** 2) / 2) ** 0.5
        verdict = "SEPARATED" if abs(gap) > 2 * pooled else "within noise"
        print(f"  {a} -> {b}: gap {gap:+.4f}, pooled SD {pooled:.4f}, "
              f"ratio {abs(gap)/pooled:5.1f}  {verdict}")


if __name__ == "__main__":
    main()
