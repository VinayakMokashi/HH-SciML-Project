#!/usr/bin/env python3
"""
check_tex_sanity.py -- catch LaTeX source defects that COMPILE CLEANLY but are wrong.

The four macro/claim checkers in `Paper Writing Skills/scripts/` verify traceability
and ledger sync. They cannot see either of the defects below, and neither can
`pdflatex -halt-on-error`, because both produce valid TeX. Both shipped into a
compiled PDF during the August 2026 revision round; this script exists so they
cannot ship again.

CHECK 1 -- control characters (severity: bug)
    A literal 0x0B byte appeared where "\\v" was intended, because a shell heredoc
    collapsed "\\\\v" to "\\v" and Python then read that as a vertical tab. The
    result: "$\\valSymbolicAHatMeanStd$" became "$<VT>alSymbolicAHatMeanStd$",
    which LaTeX happily typeset as math italics -- so the caption printed the raw
    letters "alSymbolicAHatMeanStd" instead of the number, with no error anywhere.

CHECK 2 -- a comment marker mid-line (severity: bug)
    Everything after an unescaped "%" is a comment. A "% numok:" or "% claim:"
    appended in the middle of a line silently deletes the rest of that line. This
    happened once and left a sentence beginning in mid-air in the PDF. The test is
    deliberately narrow rather than general: a real annotation ends at its source
    reference, so we flag only a "numok"/"claim" note with four or more further
    words AFTER a filename. That is the exact shape of the one that shipped, and it
    does not fire on the many legitimate annotations in the preamble.

Exit status 1 if anything is found, so it can join the verification pipeline.

Usage:
    python scripts/check_tex_sanity.py                 # defaults to paper/
    python scripts/check_tex_sanity.py paper/main.tex ...
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = [ROOT / "paper" / "main.tex",
           ROOT / "paper" / "generated" / "metrics.tex",
           ROOT / "paper" / "references.bib"]

# Tab (0x09), LF (0x0A) and CR (0x0D) are legitimate; everything else below 0x20 is not.
BAD_BYTES = set(range(0x00, 0x09)) | {0x0B, 0x0C} | set(range(0x0E, 0x20))

# The signature of the real defect, kept deliberately NARROW so it does not cry wolf
# on the many legitimate annotations in the preamble. A genuine "% numok:" / "% claim:"
# note ends at its source reference; if four or more further words follow a filename,
# a sentence was almost certainly swallowed. That is exactly the shape of the one that
# shipped:  "% numok: b 22.9% vs a 56.7% ..., results/....csv These are five different
# closures that happen to fit"
SWALLOWED = re.compile(
    r"(?:numok|claim)\s*:.*?\.(?:csv|jl|tex|png|yaml|bib)\b"      # note + its source ref
    r"(?:\s+\S+){4,}",                                            # ... then more words
    re.IGNORECASE)


def check_control_bytes(path):
    data = path.read_bytes()
    out = []
    for off, b in enumerate(data):
        if b in BAD_BYTES:
            line = data[:off].count(b"\n") + 1
            ctx = data[max(0, off - 40):off + 40].decode("utf-8", "replace")
            ctx = ctx.replace(chr(b), "<0x%02X>" % b).replace("\n", " ")
            out.append((line, "control byte 0x%02X" % b, ctx.strip()))
    return out


def check_midline_comments(path):
    if path.suffix != ".tex":
        return []
    out = []
    for i, raw in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        # find the first unescaped %
        pos = None
        for m in re.finditer(r"%", raw):
            if m.start() == 0 or raw[m.start() - 1] != "\\":
                pos = m.start()
                break
        if pos is None:
            continue
        before, after = raw[:pos], raw[pos + 1:].strip()
        # only interesting if real content precedes the comment on the same line
        if not re.search(r"[A-Za-z]{3,}", before):
            continue
        if SWALLOWED.search(after):
            out.append((i, "prose swallowed by a mid-line comment", after[:100]))
    return out


def main():
    paths = [Path(a) for a in sys.argv[1:]] or DEFAULT
    findings = []
    for p in paths:
        if not p.exists():
            print("missing: %s" % p)
            continue
        for line, kind, ctx in check_control_bytes(p) + check_midline_comments(p):
            findings.append((p, line, kind, ctx))

    for p, line, kind, ctx in sorted(findings, key=lambda f: (str(f[0]), f[1])):
        try:
            rel = p.relative_to(ROOT)
        except ValueError:
            rel = p
        print("%s:%d: %s\n    %s" % (rel, line, kind, ctx))

    print()
    if findings:
        print("FAIL: %d finding(s). Both classes compile cleanly -- fix before shipping." % len(findings))
        print("  control byte  -> replace with the characters that were intended")
        print("  mid-line %%    -> move the comment to its own line, or to the true end of the line")
        return 1
    print("OK: no control characters, no prose lost behind a mid-line comment.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
