"""
distil_noise_weighted.py
=============================================================================
Distils the conductance out of BOTH arms of the noise-weighting experiment --
the unweighted-SSE-trained closures and the chi2-trained ones -- and tests
whether the objective actually changes the SPREAD of the recovered gCa.

WHY THIS EXISTS.  noise_weighted_ude.jl retrains the UDE under the noise-weighted
likelihood instead of the unweighted sum of squares, on the argument that the
matched-objective control already showed weighting alone takes a FIXED
two-parameter fit from ~20% relative spread to ~6%.  The forecast error that
script prints is NOT the answer -- the paper's whole point is that forecast error
stays good while recovery fails.  The answer is a_hat, and this computes it.

WHAT CHANGED 2026-09-09 (E1).  The n=5 pilot compared a fresh :chi2 arm against
the PUBLISHED :sse numbers.  That was legitimate only at the five published
seeds.  noise_weighted_ude.jl now runs BOTH arms at every seed in the isolated
tree, so this script distils both from the same place and the comparison is
paired by construction: within a seed the two arms share the noise draw AND the
network initialisation, and differ only in which residual was minimised.

THE PILOT WAS NOT SIGNIFICANT AND THAT IS WHY n WENT UP.  1.645 +- 0.672 against
2.018 +- 0.482 is a variance ratio of 1.94 on F(4,4), where ~6.4 is needed.  The
tests below are reported whatever they say; a null result kills the claim, which
is the point of running it.

THE ESTIMATOR IS IMPORTED, NOT REIMPLEMENTED.  fit_conductance / r2 /
cond_number / evaluate all come from scripts/symbolic_domain_comparison.py, the
script that produced the published number.  If the estimator ever changes, this
comparison changes with it and cannot silently drift.  (Its main() is guarded by
__name__, so importing runs nothing.)

AND THERE IS A SECOND SELF-TEST HERE, AT THE DISTILLATION LEVEL.  The Julia
harness proves it is the engine by reproducing one published forecast RMSE.  This
script proves the same thing one stage later: the fresh :sse arm at the five
published seeds must reproduce the published traj-train a_hat.  If it does not,
the :sse arm is not the published arm and the whole comparison is uninterpretable,
so the script EXITS NON-ZERO.

DOMAIN.  traj-train only: the supervised trajectory, t <= 30 ms.  That is the
domain the paper's headline a_hat uses, and mixing domains is this project's
most-documented failure mode -- the same closure gives -0.061 on the trajectory
and -0.372 on the hull at gCa=0.4.  We fit strictly where the model was
supervised, exactly as the published traj-train row does.

ISOLATION.  Reads results_noiseweighted/calcium/ and results/identifiability/
(published, read-only).  Writes results_noiseweighted/ only.  Nothing under
results/ is modified.

Run:  python scripts/distil_noise_weighted.py [results_dir]
"""

import csv
import importlib.util
import math
import re
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
PARAMETRIC = NW / "parametric_chi2_28seed.csv"
OUT = NW / "noise_weighted_recovery.csv"

# The direct two-parameter fit's relative spread, as PUBLISHED at n=5. Used only
# as a labelled fallback: dividing an n=28 numerator by it would be an unsound
# ratio, and unsound in the flattering direction.
PUBLISHED_PARAM_RELSD = 0.062

GCA_TRUE = 2.0
T_TRAIN_END = 30.0
ARMS = ("sse", "chi2")

# The five seeds whose SSE a_hat is published. Used ONLY as a self-test target.
PUBLISHED_SEEDS = (1111, 2222, 3333, 4444, 5555)
SELFTEST_RTOL = 1e-6

PROBE = re.compile(r"^probe_nw_(sse|chi2)_seed(\d+)\.csv$")


# --- statistics ---------------------------------------------------------------
# scipy is present in this environment; the fallbacks exist so a missing SciPy
# degrades the REPORT rather than killing a run that cost seven hours.
try:
    from scipy import stats as _st
except Exception:                                        # pragma: no cover
    _st = None


def f_test_variance(a, b):
    """One-sided F test: is var(a) > var(b)?  Returns (F, df1, df2, p)."""
    if len(a) < 2 or len(b) < 2:
        return (float("nan"),) * 4
    va, vb = statistics.variance(a), statistics.variance(b)
    if vb == 0:
        return (float("inf"), len(a) - 1, len(b) - 1, 0.0)
    F = va / vb
    d1, d2 = len(a) - 1, len(b) - 1
    p = float("nan") if _st is None else float(_st.f.sf(F, d1, d2))
    return F, d1, d2, p


def brown_forsythe(a, b):
    """Levene's test on deviations from the MEDIAN -- robust to the skew the
    a_hat distribution actually has, which the F test is not.  Two-sided."""
    if _st is None or len(a) < 2 or len(b) < 2:
        return float("nan"), float("nan")
    r = _st.levene(a, b, center="median")
    return float(r.statistic), float(r.pvalue)


def paired_error_test(pairs):
    """Within-seed comparison of |a_hat - true|.  The arms share the noise draw
    and the network init inside a seed, so this is a legitimate paired test and
    is far better powered than either variance test."""
    if _st is None or len(pairs) < 2:
        return float("nan"), float("nan"), float("nan")
    d_sse = [abs(s - GCA_TRUE) for s, _ in pairs]
    d_chi = [abs(c - GCA_TRUE) for _, c in pairs]
    try:
        r = _st.wilcoxon(d_sse, d_chi, alternative="greater")
    except ValueError:                                    # all differences zero
        return float("nan"), float("nan"), float("nan")
    med = statistics.median([x - y for x, y in zip(d_sse, d_chi)])
    return float(r.statistic), float(r.pvalue), med


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


# --- the work -----------------------------------------------------------------
def parametric_relsd(seeds):
    """Relative spread of the DIRECT two-parameter fit under the SAME chi2
    objective -- the denominator of the representation effect.

    Prefers the measured file, and only over the SAME seeds the closures used:
    a denominator computed on a different seed set is not a denominator, it is a
    second experiment. Falls back to the published n=5 constant, loudly.
    """
    if not PARAMETRIC.exists():
        return PUBLISHED_PARAM_RELSD, len(()), "PUBLISHED n=5 (measured file absent)"
    want = set(seeds)
    a = [float(r["a_hat"]) for r in sdc.read_csv(PARAMETRIC)
         if int(float(r["seed"])) in want]
    if len(a) < 2 or statistics.mean(a) == 0:
        return PUBLISHED_PARAM_RELSD, len(a), "PUBLISHED n=5 (measured file unusable)"
    return (statistics.stdev(a) / abs(statistics.mean(a)), len(a),
            f"measured over the same {len(a)} seeds")


def published_traj_train():
    """The published per-seed SSE a_hat on traj-train, for the self-test."""
    if not PUBLISHED_DOMAIN.exists():
        return {}
    return {int(float(r["seed"])): float(r["a_hat"])
            for r in sdc.read_csv(PUBLISHED_DOMAIN)
            if r.get("domain") == "traj-train"}


def distil(probe_path, seed):
    """a_hat and friends for one closure, on the supervised trajectory only."""
    d = sdc.read_csv(probe_path)
    t = sdc.col(d, "t")
    V = sdc.col(d, "V")
    s = sdc.col(d, "s")
    nn = sdc.col(d, "ICa_nn")
    tr = sdc.col(d, "ICa_true")
    k = [i for i in range(len(t)) if t[i] <= T_TRAIN_END]
    return sdc.evaluate([V[i] for i in k], [s[i] for i in k],
                        [nn[i] for i in k], [tr[i] for i in k],
                        "traj-train", seed)


def discover():
    """Seeds present for BOTH arms. Unpaired seeds are reported, never used --
    an arm that silently ran at more seeds than the other would bias exactly the
    variance comparison this script exists to make."""
    found = {arm: set() for arm in ARMS}
    for p in CAL.glob("probe_nw_*_seed*.csv"):
        m = PROBE.match(p.name)
        if m:
            found[m.group(1)].add(int(m.group(2)))
    paired = sorted(found["sse"] & found["chi2"])
    for arm in ARMS:
        odd = sorted(found[arm] - set(paired))
        if odd:
            print(f"  [note] {arm} arm has {len(odd)} unpaired seed(s), excluded: {odd}")
    return paired


def main():
    if not CAL.is_dir():
        sys.exit(f"no calcium probes at {CAL} -- run noise_weighted_ude.jl first")

    seeds = discover()
    if not seeds:
        sys.exit("no seed has probes for BOTH arms -- nothing paired to compare")

    pub = published_traj_train()
    rows, a = [], {arm: [] for arm in ARMS}
    pairs, drift = [], []

    for seed in seeds:
        rec = {}
        for arm in ARMS:
            r = distil(CAL / f"probe_nw_{arm}_seed{seed}.csv", seed)
            if r is None:
                print(f"  [skip] seed {seed} arm {arm}: too few supervised points")
                break
            r["objective"] = arm
            rec[arm] = r
        if len(rec) != len(ARMS):
            continue

        for arm in ARMS:
            row = dict(rec[arm])
            row["a_hat_published_sse"] = (pub.get(seed, float("nan"))
                                          if arm == "sse" else float("nan"))
            rows.append(row)
            a[arm].append(rec[arm]["a_hat"])

        pairs.append((rec["sse"]["a_hat"], rec["chi2"]["a_hat"]))

        if seed in PUBLISHED_SEEDS and seed in pub and pub[seed] != 0:
            drift.append((seed, abs(rec["sse"]["a_hat"] - pub[seed]) / abs(pub[seed])))

    if not rows:
        sys.exit("no closures distilled -- nothing to report")

    # --- SELF-TEST: the fresh SSE arm must BE the published arm ---------------
    print("\n=== SELF-TEST: fresh :sse arm vs the published traj-train a_hat ===")
    if not drift:
        print("  SKIPPED -- none of the published seeds is present in this tree.")
    else:
        for seed, rel in drift:
            print(f"  seed {seed:>6}: rel diff {rel:.3e}  (tol {SELFTEST_RTOL:.0e})")
        worst = max(rel for _, rel in drift)
        if worst > SELFTEST_RTOL:
            print("\n*** SELF-TEST FAILED. ***")
            print("The :sse arm re-run here does not reproduce the published a_hat, so it")
            print("is not the published arm and no difference against :chi2 can be")
            print("attributed to the objective. Fix the harness before reading anything")
            print("below as a result.")
            sys.exit(1)
        print(f"  PASS -- worst rel diff {worst:.3e}. The :sse arm is the published arm.")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0].keys())
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    # --- the table ------------------------------------------------------------
    print(f"\n=== a_hat on the supervised trajectory (t <= {T_TRAIN_END:g} ms), "
          f"true gCa = {GCA_TRUE} ===\n")
    print(f"  {'seed':>7}  {'SSE-trained':>12}  {'chi2-trained':>13}")
    for seed, (s_hat, c_hat) in zip(seeds, pairs):
        print(f"  {seed:>7}  {s_hat:>12.3f}  {c_hat:>13.3f}")

    n = len(pairs)
    print()
    for arm in ARMS:
        print(f"  {arm:>4}-trained closure : {ms(a[arm])}"
              f"   rel sd {relsd(a[arm]):.3f}   n={len(a[arm])}")

    # --- the tests ------------------------------------------------------------
    print("\n=== DOES THE OBJECTIVE CHANGE THE SPREAD? ===")
    F, d1, d2, p = f_test_variance(a["sse"], a["chi2"])
    print(f"  F test (var sse / var chi2)   F({d1},{d2}) = {F:.3f}   p = {p:.4f}"
          f"   {'SIGNIFICANT' if p < 0.05 else 'not significant'} at 0.05")
    W, pl = brown_forsythe(a["sse"], a["chi2"])
    print(f"  Brown-Forsythe (robust)       W = {W:.3f}   p = {pl:.4f}"
          f"   {'SIGNIFICANT' if pl < 0.05 else 'not significant'} at 0.05")
    T, pw, med = paired_error_test(pairs)
    print(f"  paired Wilcoxon on |a-2.0|    T = {T:.1f}   p = {pw:.4f}"
          f"   {'SIGNIFICANT' if pw < 0.05 else 'not significant'} at 0.05")
    print(f"     median within-seed reduction in |a_hat - 2.0|: {med:+.3f}")
    print("\n  The F test is the pre-registered one and it assumes normality the")
    print("  a_hat distribution may not have. Brown-Forsythe is the robust check on")
    print("  the same question. The paired test is the best-powered of the three")
    print("  because the arms share the noise draw and the init within a seed, but")
    print("  it tests ACCURACY, not scatter -- report which one is being quoted.")

    print("\n  Reference points:")
    print("    published headline a_hat  1.645 +- 0.672   (rel sd 0.409, n=5)")
    print("    pilot chi2 arm            2.018 +- 0.482   (rel sd 0.239, n=5)")
    print("    direct parametric fit     2.092 +- 0.130   (rel sd 0.062, n=5)")
    print("\n  READ IT THIS WAY: the question is whether the chi2-trained closure's")
    print("  SPREAD moves toward the parametric arm's. A shift in the mean alone is")
    print("  not the result -- the paper's claim is about scatter across seeds.")
    den, den_n, den_src = parametric_relsd(seeds)
    print("\n=== REPRESENTATION EFFECT, at a MATCHED objective ===")
    print(f"  direct two-parameter fit, chi2 : rel sd {den:.3f}   [{den_src}]")
    if den_n and den_n != len(seeds):
        print(f"  [warn] denominator covers {den_n} of the {len(seeds)} closure seeds")
    for arm, note in (("chi2", "matched objective -- THIS is the representation effect"),
                      ("sse", "objective NOT matched; representation + objective")):
        rs = relsd(a[arm])
        if not math.isnan(rs) and den:
            print(f"  {arm:>4}-trained closure scatters {rs / den:5.2f}x wider   ({note})")
    print(f"\n  Pilot values, both arms n=5: 3.84x (chi2) over a denominator of")
    print(f"  0.062 that was itself n=5. The denominator has now been re-measured")
    print(f"  at the same seeds as the numerator, which is what makes the ratio a")
    print(f"  ratio. Quote the chi2 row: it is the one with the objective held fixed.")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
