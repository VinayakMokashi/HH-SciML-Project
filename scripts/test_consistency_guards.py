"""
test_consistency_guards.py
=============================================================================
Proves that the consistency guards added in the 2026-09 experiment round can
actually FAIL. A guard that cannot fail is decoration, and this repo has shipped
guards that passed for the wrong reason.

WHY THIS EXISTS.  check_consistency.py reports "OK" whenever nothing forbidden is
present -- which is also what it reports if a guard's regex is broken and can
never match. The only way to know a guard protects anything is to inject the
exact defect it exists to catch and watch it fire. This script does that for:

  representation-share-is-measured-not-bounded   (added 2026-09-12)
      stops the n=5 "at most a further twofold" bound, and the "objective is the
      larger share" reading, from re-entering the archival or the README. Both
      are FALSE at n=28 (see paper/main.tex Sec. 4.8).
  optimiser-share-is-two-parameter-only          (added 2026-09-11)
      stops the E2 optimiser result escaping to another section without its
      two-parameter scope.

THE LESSON BEHIND THE CASE DESIGN.  `require` is satisfied from a +/-3 line window
(check_consistency.py, `window`). The first version of the optimiser test deleted
the qualifier NEXT TO the claim and "passed" -- because the paragraph heading two
lines away still satisfied the window. The real failure mode is a claim ESCAPING
to a distant section unqualified, which is how this repo's older bound was
breached (abstract said "is", Limitations said "at most"). So every injection
here lands in the Discussion, or in the README, far from the qualified text.

SAFETY.  It rewrites paper/main.tex and README.md in place, so it restores both
from byte copies in a `finally`, and verifies the restored tree passes. NEVER run
two copies at once: they race on the same files.

Run:  python scripts/test_consistency_guards.py      (exit 0 = every guard fires)
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "paper" / "main.tex"
README = ROOT / "README.md"

DISC = "\\section{Discussion}\n\\label{sec:discussion}\n"

CASES = [
    # --- representation-share-is-measured-not-bounded ---
    (MAIN, "old bound re-enters the Discussion",
     DISC, DISC + "\nAt most a further twofold is attributable to the representation.\n"),
    (MAIN, "old 'larger share' wording re-enters",
     DISC, DISC + "\nThe larger share of the gap on a log scale is the objective.\n"),
    (MAIN, "old bound, line-wrapped mid-phrase",
     DISC, DISC + "\nThe remainder\nbounds the representation's own contribution.\n"),
    (README, "old bound re-enters the README",
     "it is not the cause.",
     "it is not the cause. At most a further twofold is the representation's."),
    # --- optimiser-share-is-two-parameter-only ---
    (MAIN, "optimiser claim escapes to the Discussion unqualified",
     DISC, DISC + "\nThe optimiser contributes nothing to the observed spread.\n"),
    (MAIN, "forbidden optimiser phrasing injected",
     "With the optimiser contributing",
     "The optimiser is ruled out. With the optimiser contributing"),
]


def run():
    p = subprocess.run([sys.executable, "scripts/check_consistency.py"],
                       cwd=ROOT, capture_output=True, text=True)
    lines = (p.stdout + p.stderr).strip().splitlines()
    return p.returncode, (lines[-1] if lines else "")


def main():
    tmp = Path(tempfile.mkdtemp(prefix="guardtest_"))
    backups = {p: tmp / p.name for p in (MAIN, README)}
    for p, b in backups.items():
        shutil.copy(p, b)
    orig = {p: p.read_text(encoding="utf-8") for p in (MAIN, README)}

    rc0, last0 = run()
    if rc0 != 0:
        print(f"*** the UNTOUCHED tree already fails check_consistency: {last0}")
        print("    Fix that first; a guard test on a failing tree proves nothing.")
        return 1

    ok = True
    try:
        for path, name, old, new in CASES:
            n = orig[path].count(old)
            if n != 1:
                print(f"  TEST INVALID        {name}: anchor matched {n}x in {path.name}"
                      " -- update this script's anchor, the prose moved")
                ok = False
                continue
            path.write_text(orig[path].replace(old, new), encoding="utf-8")
            rc, last = run()
            path.write_text(orig[path], encoding="utf-8")
            print(f"  {'OK (fired)' if rc else 'GUARD DID NOT FIRE':<19} {name}"
                  + ("" if rc else f"  -- {last[:60]}"))
            ok = ok and rc != 0
    finally:
        for p, b in backups.items():
            shutil.copy(b, p)
        shutil.rmtree(tmp, ignore_errors=True)

    rc, _ = run()
    print(f"  {'OK (clean)' if rc == 0 else 'RESTORE FAILED':<19} restored tree")
    ok = ok and rc == 0
    print("\nVERDICT:", "PASS -- every guard fires" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
