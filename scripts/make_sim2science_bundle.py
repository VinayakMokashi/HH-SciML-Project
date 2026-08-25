#!/usr/bin/env python3
r"""make_sim2science_bundle.py -- build the double-blind Sim2Science submission.

WHAT IT BUILDS
--------------
    sim2science_upload/
        main.tex            the 5-page cut  (paper/sim2science/main.tex, verbatim)
        supplementary.tex   the FULL paper, ANONYMISED at build time
        neurips_2026.sty    vendored NeurIPS 2026 style (the cut requires it)
        arxiv.sty           vendored arxiv style (the supplementary uses it)
        checklist.tex       the CFP's reproducibility checklist
        references.bib
        generated/metrics.tex
        figures/*.png       exactly the figures the two documents reference

WHY THE SUPPLEMENTARY IS GENERATED, NOT WRITTEN
-----------------------------------------------
The CFP allows unlimited supplementary material, so the most useful supplement is
the full manuscript itself -- every ablation, table and appendix, already audited.
But the full manuscript carries a byline, and Sim2Science is double-blind.

Keeping a hand-anonymised second copy of a 2100-line paper would be a third
artifact to keep in sync, and five audit rounds in this project were spent paying
down exactly that kind of duplication. So anonymisation is a BUILD-TIME
TRANSFORM over paper/main.tex, applied here, explicitly, in one place. There is
one source of truth and the transform is auditable.

THE SELF-CHECK IS THE POINT
---------------------------
A build that silently fails to anonymise is worse than no build: it is a
desk-reject, and it cannot be undone once uploaded. So this script FAILS rather
than writes if any identifying string survives into the output, if a figure is
missing, or if either document still has a non-empty \author block. It is the
delivery guard the checkers do not provide (HANDOFF Sec 8: "the checkers verify
the paper, not the delivery").

Usage:  python scripts/make_sim2science_bundle.py
Exit 1 on any failure; nothing is left half-written on failure.
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAPER = os.path.join(ROOT, 'paper')
CUTDIR = os.path.join(PAPER, 'sim2science')
OUT = os.path.join(ROOT, 'sim2science_upload')

#  Strings that must NOT survive into the built bundle's .tex files.
#  "Overleaf" is deliberately absent: it is a tool name in build comments, not an
#  identity. Cited authors are not listed either -- they reach the PDF through
#  \citet keys, never as literal source text, and citing prior work in the third
#  person is permitted under double-blind.
IDENTIFYING = [
    'Mokashi', 'mokashi',
    'Prathamesh', 'Prathmesh',
    'Dandekar',
    'Sreedath',
    'Panat',
    'Vizuara',
    'brown.edu',
    '@vizuara.com',
]

#  The one self-identifying SENTENCE in the manuscript. Round 2 of the audit
#  added this disclosure because claiming "independent corroboration" from your
#  own authors is an integrity problem. Under double-blind the disclosure itself
#  breaks anonymity, so the transform keeps the epistemic hedge (do not lean on
#  it as independent) and drops only the reason. RESTORE THE FULL DISCLOSURE IN
#  THE CAMERA-READY -- it is not optional there.
SELF_ID_CLAUSE = re.compile(
    r'---\s*though\s+that\s+work\s+shares\s+four\s+of\s+this\s+'
    r'paper\'s\s+five\s+authors,\s+so\s+we\s+note\s+the\s+agreement\s+'
    r'rather\s+than\s+lean\s+on\s+it\s+as\s+independent\s*---',
    re.S)
SELF_ID_REPLACEMENT = (
    '--- though we note the agreement rather than lean on it as\n'
    'independent ---')

IDENT_RX = re.compile('|'.join(re.escape(s) for s in IDENTIFYING))


def read(p):
    with open(p, encoding='utf-8') as fh:
        return fh.read()


def write(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


def anonymise(text):
    """Return (anonymised_text, notes). Raises AssertionError if a step no-ops."""
    notes = []

    # ---- 1. the \author block -> empty -----------------------------------
    lines = text.split('\n')
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == r'\author{':
            start = i
            break
    assert start is not None, r'could not find the \author{ block in main.tex'
    end = None
    for j in range(start + 1, len(lines)):
        if lines[j].strip() == '}':
            end = j
            break
    assert end is not None, r'could not find the end of the \author{ block'
    removed = end - start + 1
    lines[start:end + 1] = [
        '% ---- DOUBLE-BLIND: byline removed by scripts/make_sim2science_bundle.py.',
        '%      The real block is in paper/main.tex and must be restored verbatim',
        '%      for the camera-ready; one surname spelling and one address there',
        '%      are settled and deliberately differ from the arXiv record.',
        r'\author{}',
    ]
    notes.append('author block: %d lines -> anonymous' % removed)
    text = '\n'.join(lines)

    # ---- 2. pdfauthor metadata -------------------------------------------
    text, n = re.subn(r'pdfauthor=\{[^}]*\}', 'pdfauthor={Anonymous}', text)
    assert n >= 1, 'no pdfauthor= line found to anonymise'
    notes.append('pdfauthor: %d line(s)' % n)

    # ---- 3. the self-identifying clause in Related Work -------------------
    text, n = SELF_ID_CLAUSE.subn(SELF_ID_REPLACEMENT, text)
    assert n == 1, ('expected exactly 1 self-identifying clause, found %d -- '
                    'the sentence was reworded; update SELF_ID_CLAUSE' % n)
    notes.append('self-identifying clause: neutralised')

    # ---- 4. any COMMENT line that names a person or the affiliation -------
    out, ncomment = [], 0
    for ln in text.split('\n'):
        stripped = ln.lstrip()
        if stripped.startswith('%') and IDENT_RX.search(ln):
            out.append('% [identifying comment removed for double-blind review]')
            ncomment += 1
        else:
            out.append(ln)
    text = '\n'.join(out)
    notes.append('identifying comments: %d removed' % ncomment)

    # ---- 5. mark the document as the supplement ---------------------------
    text, n = re.subn(
        r'(\\maketitle)',
        r'\1\n\n\\begin{center}\\textsc{Supplementary material --- '
        r'Sim2Science @ NeurIPS 2026}\\end{center}',
        text, count=1)
    assert n == 1, r'no \maketitle found to mark as supplementary'
    notes.append('supplementary banner inserted')
    return text, notes


def figures_referenced(*texts):
    got = set()
    for t in texts:
        for m in re.finditer(r'\\includegraphics(?:\[[^\]]*\])?\{([^}]*)\}', t):
            got.add(m.group(1))
    return got


def main():
    cut_src = os.path.join(CUTDIR, 'main.tex')
    #  Dormant, not obsolete -- see the note in scripts/check_workshop_cut.py.
    #  The 5-page draft was deleted on 2026-08-26 to be rewritten from scratch
    #  against the mentor's video feedback. Everything else here (the anonymising
    #  transform, the identifying-string self-check, the figure staging) is still
    #  correct and will be needed again the moment the redraft exists.
    if not os.path.exists(cut_src):
        print('-- make_sim2science_bundle: nothing to build.')
        print('   paper/sim2science/main.tex does not exist (deleted 2026-08-26 for a')
        print('   redraft). Write the new 5-page paper there, then re-run this.')
        print('   The anonymising supplementary transform is unchanged and ready.')
        return 0

    for p in (cut_src,
              os.path.join(CUTDIR, 'neurips_2026.sty'),
              os.path.join(CUTDIR, 'checklist.tex'),
              os.path.join(PAPER, 'main.tex'),
              os.path.join(PAPER, 'arxiv.sty'),
              os.path.join(PAPER, 'references.bib'),
              os.path.join(PAPER, 'generated', 'metrics.tex')):
        if not os.path.exists(p):
            print('FAIL missing input: %s' % os.path.relpath(p, ROOT))
            return 1

    cut = read(cut_src)
    try:
        supp, notes = anonymise(read(os.path.join(PAPER, 'main.tex')))
    except AssertionError as exc:
        print('FAIL anonymisation step did not apply: %s' % exc)
        print('     Nothing was written. Fix the transform before rebuilding.')
        return 1

    # ---- verify BEFORE writing anything ----------------------------------
    fails = []
    for label, body in (('main.tex', cut), ('supplementary.tex', supp)):
        for m in IDENT_RX.finditer(body):
            line = body[:m.start()].count('\n') + 1
            fails.append('%s:%d still contains identifying string %r'
                         % (label, line, m.group(0)))
        for m in re.finditer(r'\\author\{([^}]*)\}', body):
            if m.group(1).strip():
                fails.append('%s has a non-empty \\author{} block' % label)

    figs = figures_referenced(cut, supp)
    figdir = os.path.join(PAPER, 'figures')
    have = set(os.listdir(figdir)) if os.path.isdir(figdir) else set()
    for f in sorted(figs):
        if f not in have:
            fails.append('figure %s missing from paper/figures/ '
                         '(exact name; Overleaf is case-sensitive)' % f)

    if fails:
        for f in fails:
            print('FAIL %s' % f)
        print('\n%d problem(s). NOTHING was written.' % len(fails))
        return 1

    # ---- write ------------------------------------------------------------
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    write(os.path.join(OUT, 'main.tex'), cut)
    write(os.path.join(OUT, 'supplementary.tex'), supp)
    for name, src in (('neurips_2026.sty', os.path.join(CUTDIR, 'neurips_2026.sty')),
                      ('checklist.tex', os.path.join(CUTDIR, 'checklist.tex')),
                      ('arxiv.sty', os.path.join(PAPER, 'arxiv.sty')),
                      ('references.bib', os.path.join(PAPER, 'references.bib'))):
        shutil.copy2(src, os.path.join(OUT, name))
    write(os.path.join(OUT, 'generated', 'metrics.tex'),
          read(os.path.join(PAPER, 'generated', 'metrics.tex')))
    os.makedirs(os.path.join(OUT, 'figures'))
    for f in sorted(figs):
        shutil.copy2(os.path.join(figdir, f), os.path.join(OUT, 'figures', f))

    for n in notes:
        print('  anonymise: %s' % n)
    print('\nwrote %s  (%d figures)' % (os.path.relpath(OUT, ROOT), len(figs)))
    print("""
UPLOAD: make a NEW Overleaf project and drag EVERY item in sim2science_upload/
onto its file tree -- main.tex, supplementary.tex, neurips_2026.sty, arxiv.sty,
checklist.tex, references.bib, generated/, figures/.  Compile main.tex for the
5-page submission and supplementary.tex for the supplement, then upload both
PDFs to OpenReview.

REMEMBER, none of which this script can do for you:
  - nominate one author as the reciprocal reviewer at submission time;
  - check the compiled main.pdf is <= 5 pages EXCLUDING references;
  - fill checklist.tex (it does not count toward the page limit).""")
    return 0


if __name__ == '__main__':
    sys.exit(main())
