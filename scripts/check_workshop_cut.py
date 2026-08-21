#!/usr/bin/env python3
r"""check_workshop_cut.py -- the tenth checker: the derived 5-page cut must not drift.

WHY THIS EXISTS
---------------
paper/sim2science/main.tex is a DERIVED artifact: the 5-page double-blind cut of
paper/main.tex required by the Sim2Science @ NeurIPS 2026 CFP (5 pages excluding
references, unlimited supplementary). Two manuscripts asserting the same dozen
things is precisely the consistency debt that five audit rounds were spent
paying down -- so the cut needs its own mechanical guard, not good intentions.

paper/consistency.yaml already covers the SHARED CLAIMS across both files (it
lists sim2science/main.tex in the relevant groups). This checker covers the four
things consistency.yaml cannot see:

  1. FIXED-INPUT MACROS MUST AGREE. The cut carries its own copy of the
     fixed-input preamble rather than \input-ing a shared file, because
     refactoring the audited manuscript's preamble to serve a derived artifact
     was judged the wrong risk. The cost of that decision is two definitions of
     \Ttrain, \Rcap, \NparamUde and friends. This fails if any macro defined in
     BOTH files has a different body -- which is the whole reason the copy is
     safe.

  2. EVERY \val MACRO MUST RESOLVE. A \val macro that generated/metrics.tex does
     not define is an "Undefined control sequence" reported once per USE,
     pointing at the prose and never at the cause. That has cost this project
     two debugging rounds already (HANDOFF Sec 9).

  3. EVERY \cite KEY MUST RESOLVE. An unresolved key is a "?" in the compiled
     PDF, diagnosed twice only after an upload. Same argument as
     check_bib_sanity.py, applied to the cut.

  4. EVERY \includegraphics TARGET MUST EXIST in paper/figures/, under the exact
     name and case. Overleaf is Linux and case-sensitive; Windows is not.

Usage:  python scripts/check_workshop_cut.py
Exit 1 on any FAIL.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, 'paper', 'main.tex')
CUT = os.path.join(ROOT, 'paper', 'sim2science', 'main.tex')
METRICS = os.path.join(ROOT, 'paper', 'generated', 'metrics.tex')
BIB = os.path.join(ROOT, 'paper', 'references.bib')
FIGDIR = os.path.join(ROOT, 'paper', 'figures')

#  A macro whose two definitions are ALLOWED to differ, with the reason. Keep
#  this list empty if you can; every entry is a divergence nobody is watching.
ALLOWED_DIVERGENCE = {}

NEWCMD = re.compile(r'\\newcommand\{\\([A-Za-z]+)\}\{(.*?)\}\s*(?:%.*)?$')


def read(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def strip_comments(text):
    """Blank out LaTeX comment text, honouring \\% and preserving line count."""
    out = []
    for line in text.split('\n'):
        buf, i = [], 0
        while i < len(line):
            ch = line[i]
            if ch == '\\' and i + 1 < len(line):
                buf.append(line[i:i + 2])
                i += 2
                continue
            if ch == '%':
                break
            buf.append(ch)
            i += 1
        out.append(''.join(buf))
    return '\n'.join(out)


def newcommands(text):
    """Map macro name -> body, for single-line \newcommand definitions."""
    found = {}
    for line in text.split('\n'):
        line = line.rstrip()
        # several \newcommand on one line (the model-constant rows do this)
        for m in re.finditer(r'\\newcommand\{\\([A-Za-z]+)\}\{([^{}]*)\}', line):
            found[m.group(1)] = m.group(2)
    return found


def main():
    for p in (FULL, CUT, METRICS, BIB):
        if not os.path.exists(p):
            print('FAIL missing required file: %s' % os.path.relpath(p, ROOT))
            return 1

    cut_raw = read(CUT)
    cut = strip_comments(cut_raw)
    full = strip_comments(read(FULL))
    fails = []

    # ---- 1. shared fixed-input macros must have identical bodies -----------
    a, b = newcommands(full), newcommands(cut)
    shared = sorted(set(a) & set(b))
    for name in shared:
        if name in ALLOWED_DIVERGENCE:
            continue
        if a[name] != b[name]:
            fails.append('macro \\%s differs: main.tex has {%s}, the cut has {%s}'
                         % (name, a[name], b[name]))

    # ---- 2. every \val macro used in the cut must be defined ---------------
    defined = set(newcommands(read(METRICS)))
    used = set(re.findall(r'\\(val[A-Za-z]+)', cut))
    for name in sorted(used - defined):
        fails.append('\\%s is used in the cut but generated/metrics.tex does not '
                     'define it (this compiles as "Undefined control sequence")'
                     % name)

    # ---- 3. every \cite key must resolve ----------------------------------
    bibkeys = set(re.findall(r'^@[A-Za-z]+\{([^,]+),', read(BIB), re.M))
    cited = set()
    for m in re.finditer(r'\\cite[a-zA-Z]*\s*(?:\[[^\]]*\])*\{([^}]*)\}', cut):
        for k in m.group(1).split(','):
            if k.strip():
                cited.add(k.strip())
    for k in sorted(cited - bibkeys):
        fails.append('\\cite{%s} has no entry in references.bib (prints as "?")' % k)

    # ---- 4. every figure must exist, exact name and case ------------------
    have = set(os.listdir(FIGDIR)) if os.path.isdir(FIGDIR) else set()
    for m in re.finditer(r'\\includegraphics(?:\[[^\]]*\])?\{([^}]*)\}', cut):
        target = m.group(1)
        if target not in have:
            fails.append('figure %s is not in paper/figures/ under that exact '
                         'name (Overleaf is case-sensitive)' % target)

    print('-- check_workshop_cut: %d shared macro(s), %d \\val macro(s), '
          '%d cite key(s)' % (len(shared), len(used), len(cited)))
    if fails:
        for f in fails:
            print('FAIL %s' % f)
        print('\n%d problem(s) in the derived 5-page cut.' % len(fails))
        return 1
    print('OK: shared macros agree, every \\val and \\cite resolves, '
          'every figure is staged.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
