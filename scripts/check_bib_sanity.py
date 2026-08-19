#!/usr/bin/env python3
"""check_bib_sanity.py -- catch bibliography defects that only surface on Overleaf.

WHY THIS EXISTS
    Three separate bibliography failures have now reached a compiled build, and
    none of the other six checkers can see any of them, because none of them
    parses a .bib file:

      1. A STRAY AT-SIGN IN A COMMENT. "%" is a LaTeX convention with no meaning
         to BibTeX. BibTeX ignores text between entries but still scans it for
         "@", so an at-sign inside a "comment" opens a bogus entry and the parse
         dies with "I was expecting a `{' or a `('". This happened on 2026-08-19
         in a comment that was itself explaining the entry types -- writing
         "@misc" and "@software" in prose was enough to break the build.

      2. A CITE KEY WITH NO ENTRY. Renders as "?" in the PDF and is trivially
         missed, because BibTeX reports it as a warning among dozens.

      3. A DUPLICATE KEY. BibTeX silently keeps one of them.

    All three are cheap to detect statically. CHECK 2 in particular is the
    static form of the "?-in-the-PDF" diagnosis that has cost this project two
    upload cycles: it answers the question before the upload, not after.

USAGE
    python scripts/check_bib_sanity.py                  # defaults below
    python scripts/check_bib_sanity.py --bib X --tex Y
    python scripts/check_bib_sanity.py --selftest
Exit status is 1 if anything is flagged, so it can gate a build.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_BIB = REPO / "paper" / "references.bib"
DEFAULT_TEX = REPO / "paper" / "main.tex"

# \cite, \citep, \citet, \citealp, \citeyear, ... optionally with [..][..]
CITE_RE = re.compile(r"\\[a-zA-Z]*cite[a-zA-Z]*\s*(?:\[[^\]]*\]\s*){0,2}\{([^}]*)\}")
ENTRY_RE = re.compile(r"@([A-Za-z]+)\s*[{(]\s*([^,\s]+)\s*,")


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def scan_at_signs(text: str):
    """Every '@' outside an entry body must begin a well-formed entry header."""
    problems = []
    i, n, depth = 0, len(text), 0
    while i < n:
        c = text[i]
        if depth == 0:
            if c == "@":
                m = ENTRY_RE.match(text, i)
                if m:
                    depth = 1          # entered an entry; its braces are counted below
                    i = m.end()
                    continue
                # Not a real entry header. Show the line so it is obvious which
                # prose sentence did it.
                ln = line_of(text, i)
                snippet = text.splitlines()[ln - 1].strip()
                problems.append((ln, snippet))
            i += 1
        else:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
    return problems


def parse_entries(text: str):
    """Return [(line, type, key)] for every entry header."""
    return [(line_of(text, m.start()), m.group(1).lower(), m.group(2))
            for m in ENTRY_RE.finditer(text)]


def run(bib_path: Path, tex_path: Path, quiet: bool = False) -> int:
    bib = bib_path.read_text(encoding="utf-8", errors="replace")
    flagged = 0

    def say(*a):
        if not quiet:
            print(*a)

    # --- CHECK 1: stray at-signs ------------------------------------------
    strays = scan_at_signs(bib)
    if strays:
        flagged += len(strays)
        say("STRAY AT-SIGN outside an entry -- BibTeX will fail to parse:")
        for ln, snippet in strays:
            say(f"  {bib_path.name}:{ln}: {snippet[:100]}")
        say("  fix: remove the '@'. A .bib comment is not protected by '%'.")
        say("")

    # --- CHECK 2: duplicate keys ------------------------------------------
    entries = parse_entries(bib)
    seen: dict[str, int] = {}
    dups = []
    for ln, _typ, key in entries:
        if key in seen:
            dups.append((ln, key, seen[key]))
        else:
            seen[key] = ln
    if dups:
        flagged += len(dups)
        say("DUPLICATE KEY -- BibTeX silently keeps only one:")
        for ln, key, first in dups:
            say(f"  {bib_path.name}:{ln}: '{key}' already defined at line {first}")
        say("")

    # --- CHECK 3: cited but not defined (this is the '?' in the PDF) -------
    missing = []
    if tex_path.exists():
        tex = tex_path.read_text(encoding="utf-8", errors="replace")
        for m in CITE_RE.finditer(tex):
            for key in (k.strip() for k in m.group(1).split(",")):
                if key and key not in seen:
                    missing.append((line_of(tex, m.start()), key))
    if missing:
        flagged += len(missing)
        say("CITED BUT NOT IN THE .bib -- renders as '?' in the PDF:")
        for ln, key in sorted(set(missing)):
            say(f"  {tex_path.name}:{ln}: {key}")
        say("")

    say(f"-- check_bib_sanity: {len(entries)} entries, {len(seen)} unique keys, "
        f"{flagged} problem(s)")
    if flagged == 0:
        say("OK: no stray at-signs, no duplicate keys, every cite key resolves.")
    return 1 if flagged else 0


def selftest() -> int:
    """The three defects this exists to catch, plus a clean control."""
    good = """@article{a2020, author = {X}, title = {T}, year = {2020} }
% a plain comment, no at-sign, is fine
@software{b2021, author = {Y}, title = {U}, version = {1.0} }
"""
    assert scan_at_signs(good) == [], "clean file must not flag"
    assert len(parse_entries(good)) == 2

    bad = good + "% retyping these as @misc would silence it\n"
    assert len(scan_at_signs(bad)) == 1, "at-sign in a comment must flag"

    # an at-sign inside an entry's braces is legitimate (e.g. an email address)
    inside = "@misc{c, author = {Z}, note = {mail me at x@y.z} }\n"
    assert scan_at_signs(inside) == [], "at-sign inside a field must not flag"

    dup = good + "@article{a2020, author = {W}, title = {V}, year = {2021} }\n"
    ents = parse_entries(dup)
    keys = [k for _, _, k in ents]
    assert keys.count("a2020") == 2, "duplicate must be visible to the checker"

    print("selftest OK: stray at-sign, in-field at-sign, and duplicate all behave")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bib", type=Path, default=DEFAULT_BIB)
    ap.add_argument("--tex", type=Path, default=DEFAULT_TEX)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.bib.exists():
        print(f"no such file: {args.bib}", file=sys.stderr)
        return 2
    return run(args.bib, args.tex, args.quiet)


if __name__ == "__main__":
    raise SystemExit(main())
