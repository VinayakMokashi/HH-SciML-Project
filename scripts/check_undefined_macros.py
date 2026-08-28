#!/usr/bin/env python3
r"""check_undefined_macros.py -- the TWELFTH checker.

WHY THIS EXISTS
---------------
Nothing else in the suite verifies that a command a manuscript USES is actually
DEFINED. On 2026-08-26 all eleven checkers were green on a document that would
not compile: neurips_2026.sty:407-411 defines \answerYes/\answerNo/\answerNA in
terms of \textcolor, and the .sty never loads a colour package -- the official
neurips_2026.tex supplies it. The result was ~40 "Undefined control sequence"
errors, every one of them pointing at checklist.tex, which was not the bug.
That cost a compile cycle, and compiles are expensive here: they happen on
Overleaf, by hand, and a session cannot run one.

It caught its own first real defect on 2026-08-28: the appendix built for the
Sim2Science restructure used \ProfileStep, which is defined in paper/main.tex
and was not carried into the 5-page cut's preamble. check_workshop_cut.py could
not see it -- that checker resolves \val macros and \cite keys only.

WHAT IT DOES
------------
Collects every \command in the live (non-comment) text of a manuscript and
subtracts, in order:
  * commands the file itself defines (\newcommand, \renewcommand, \def,
    \DeclareMathOperator, \newtheorem, \newenvironment);
  * commands defined by anything it \input's (generated/metrics.tex, checklist);
  * commands defined by the vendored .sty files sitting next to it;
  * a curated base-LaTeX-and-loaded-packages whitelist (BASE below).
Whatever survives is reported. It is a STATIC approximation, not a TeX parser:
treat a report as "look at this", not as proof. But every command it names is
one a human should be able to point at a definition for.

Usage:  python scripts/check_undefined_macros.py            # both manuscripts
        python scripts/check_undefined_macros.py <file.tex> # just one
Exit 1 if any manuscript has an unexplained command.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#  The two manuscripts, each with the directory its \input paths resolve against
#  and the .sty files that ship beside it.
TARGETS = [
    (os.path.join(ROOT, 'paper', 'main.tex'), os.path.join(ROOT, 'paper')),
    (os.path.join(ROOT, 'paper', 'sim2science', 'main.tex'),
     os.path.join(ROOT, 'paper', 'sim2science')),
]

#  Base LaTeX plus the packages these two preambles actually load: inputenc,
#  fontenc, xcolor, hyperref, url, booktabs, amsfonts, amsmath, amssymb,
#  nicefrac, microtype, graphicx, natbib, geometry, caption, subcaption, xspace.
#  Kept explicit rather than pulled from a TeX tree: there is no working local
#  LaTeX here (doctor.py reports the MiKTeX install broken), so a list that can
#  be read and argued with beats one that cannot be reproduced.
BASE = set("""
begin end documentclass usepackage input include includeonly newcommand
renewcommand providecommand def edef gdef xdef let newif newlength newcounter
setlength addtolength settowidth setcounter addtocounter stepcounter value
newsavebox savebox usebox sbox mbox hbox vbox fbox framebox makebox parbox
raisebox rule strut vphantom hphantom phantom smash
section subsection subsubsection paragraph subparagraph part chapter appendix
title author date maketitle thanks and abstract keywords
label ref pageref cite citep citet citealp citealt citeauthor citeyear
bibliography bibliographystyle bibitem newblock
textbf textit textrm textsf texttt textsc textnormal textsuperscript
textsubscript emph underline uline bf it rm sf tt sc em normalfont
tiny scriptsize footnotesize small normalsize large Large LARGE huge Huge
centering raggedright raggedleft flushleft flushright center
item itemize enumerate description list trivlist
footnote footnotemark footnotetext marginpar
caption captionsetup subcaption subfloat subfigure
includegraphics graphicspath DeclareGraphicsExtensions scalebox resizebox
rotatebox reflectbox
toprule midrule bottomrule cmidrule addlinespace morecmidrules specialrule
tabular tabularx array multicolumn multirow hline cline arraystretch tabcolsep
extrarowheight columnwidth linewidth textwidth textheight paperwidth
paperheight hsize vsize baselineskip baselinestretch parskip parindent
topsep partopsep itemsep parsep leftmargin rightmargin
frac dfrac tfrac nicefrac sqrt sum prod int oint lim limits nolimits
sup inf max min arg det dim exp ln log sin cos tan sinh cosh tanh
alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa
lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi
psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega
partial nabla infty forall exists neg emptyset varnothing
in notin ni subset supset subseteq supseteq cup cap setminus
leq geq neq approx equiv sim simeq cong propto ll gg
pm mp times div cdot cdots ldots vdots ddots dots
rightarrow leftarrow leftrightarrow Rightarrow Leftarrow Leftrightarrow
to gets mapsto longrightarrow
left right big Big bigg Bigg bigl bigr Bigl Bigr biggl biggr
langle rangle lvert rvert lVert rVert vert Vert mid
mathbb mathcal mathrm mathbf mathit mathsf mathtt mathfrak mathnormal
boldsymbol bm operatorname DeclareMathOperator text intertext
begingroup endgroup bgroup egroup relax expandafter noexpand csname endcsname
protect ensuremath ifdefined ifx else fi ifnum ifdim ifcase or
newenvironment renewenvironment newtheorem theoremstyle
equation eqref align aligned alignat gather multline split cases matrix
pmatrix bmatrix vmatrix Vmatrix array notag nonumber tag substack
quad qquad hspace vspace hfill vfill hskip vskip kern
smallskip medskip bigskip newline linebreak pagebreak newpage clearpage
cleardoublepage nopagebreak samepage sloppy fussy
url href hyperref hypersetup nolinkurl urlstyle autoref
textcolor color colorbox fcolorbox definecolor pagecolor normalcolor
today thepage thesection thefigure thetable thechapter theequation
figure table thebibliography enumi enumii labelenumi labelitemi
verb verbatim texttildelow textasciitilde textbackslash textunderscore
slash discretionary hyphenation mbox unskip ignorespaces
S P copyright dag ddag pounds ss ae AE oe OE aa AA o O l L
LaTeX TeX LaTeXe
GenericError PackageError PackageWarning ClassWarning message typeout
DeclareOption ProcessOptions ExecuteOptions CurrentOption
makeatletter makeatother AtBeginDocument AtEndDocument
if fi ifthenelse newpage suppressfloats floatpagefraction
topfraction bottomfraction textfraction dblfloatpagefraction
abovecaptionskip belowcaptionskip
star dagger ddagger circ bullet ast bigcirc square blacksquare
overline underline widehat widetilde hat tilde bar vec dot ddot acute grave
check breve mathring
colon semicolon comma period space
providecommand xspace
le ge ne leqslant geqslant lesssim gtrsim prec succ preceq succeq
land lor implies iff because therefore ldotp cdotp
""".split())

#  tikz/pgf, loaded by paper/main.tex only (the schematic in Sec. 2). Kept in
#  its own set so the cut, which does NOT load tikz, is not silently excused
#  for using a tikz command it has no package for.
TIKZ = set("""
usetikzlibrary tikz tikzpicture draw node path fill filldraw shade shadedraw
clip useasboundingbox coordinate pic matrix foreach pgfmathsetmacro
pgfmathparse tikzset tikzstyle arrow arrows anchor midway above below
""".split())


def strip_comments(text):
    r"""Drop TeX comments. A % is a comment unless escaped as \%."""
    out = []
    for line in text.split('\n'):
        i, n = 0, len(line)
        while i < n:
            if line[i] == '\\' and i + 1 < n:
                i += 2
                continue
            if line[i] == '%':
                break
            i += 1
        out.append(line[:i])
    return '\n'.join(out)


DEF_RX = re.compile(
    r'\\(?:newcommand|renewcommand|providecommand|DeclareRobustCommand)\s*\*?\s*'
    r'\{?\\([A-Za-z@]+)\}?'
    r'|\\(?:def|edef|gdef|xdef)\s*\\([A-Za-z@]+)'
    r'|\\(?:DeclareMathOperator|newtheorem|newenvironment|newlength|newcounter|'
    r'newif|newsavebox|newtoks)\s*\*?\s*\{?\\?([A-Za-z@]+)\}?')

USE_RX = re.compile(r'\\([A-Za-z]+)')
INPUT_RX = re.compile(r'\\(?:input|include)\s*\{([^}]+)\}')


def definitions(text):
    got = set()
    for m in DEF_RX.finditer(text):
        for g in m.groups():
            if g:
                got.add(g)
                # \newif\ifX also defines \Xtrue and \Xfalse
                if g.startswith('if'):
                    got.add(g[2:] + 'true')
                    got.add(g[2:] + 'false')
    return got


def read(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return fh.read()


def check(tex_path, base_dir):
    rel = os.path.relpath(tex_path, ROOT)
    if not os.path.exists(tex_path):
        print('-- skip %s (does not exist)' % rel)
        return []

    body = strip_comments(read(tex_path))
    defined = set(BASE) | definitions(body)
    #  Only excuse tikz commands in a document that actually loads tikz.
    if re.search(r'\\usepackage(?:\[[^\]]*\])?\{[^}]*\btikz\b[^}]*\}', body):
        defined |= TIKZ

    # Everything the document \input's. The 5-page cut says
    # \input{generated/metrics}, which resolves against paper/ in the SOURCE
    # tree and against the bundle root once make_sim2science_bundle.py has
    # copied generated/ next to main.tex -- so search both, nearest first.
    search = [base_dir, os.path.join(ROOT, 'paper'), ROOT]
    inputs = []
    for m in INPUT_RX.finditer(body):
        name = m.group(1).strip()
        for root in search:
            hit = None
            for cand in (name, name + '.tex'):
                p = os.path.join(root, cand)
                if os.path.exists(p):
                    hit = p
                    break
            if hit:
                inputs.append(hit)
                break
    for p in inputs:
        sub = strip_comments(read(p))
        defined |= definitions(sub)
        body += '\n' + sub          # the inputs' own USES count too

    # every .sty / .cls sitting beside the manuscript
    styles = [os.path.join(base_dir, f) for f in sorted(os.listdir(base_dir))
              if f.endswith(('.sty', '.cls'))]
    for p in styles:
        defined |= definitions(read(p))

    used = set(USE_RX.findall(body))
    unknown = sorted(used - defined)

    print('-- %s' % rel)
    print('   %d distinct command(s) used; %d definition(s) in scope '
          '(%d input, %d style file(s))'
          % (len(used), len(defined), len(inputs), len(styles)))
    if inputs:
        print('   inputs : %s' % ', '.join(os.path.basename(p) for p in inputs))
    if styles:
        print('   styles : %s' % ', '.join(os.path.basename(p) for p in styles))

    for name in unknown:
        # point at the first live use, so the report is actionable
        line = 0
        for i, ln in enumerate(strip_comments(read(tex_path)).split('\n'), 1):
            if re.search(r'\\%s(?![A-Za-z])' % re.escape(name), ln):
                line = i
                break
        where = '%s:%d' % (rel, line) if line else rel
        print('   UNDEFINED  \\%-28s first used at %s' % (name, where))
    return unknown


def main():
    argv = sys.argv[1:]
    if argv:
        targets = [(os.path.abspath(p), os.path.dirname(os.path.abspath(p)))
                   for p in argv]
    else:
        targets = TARGETS

    total = 0
    for tex, base in targets:
        total += len(check(tex, base))
        print('')

    if total:
        print('FAIL: %d command(s) used with no definition in scope.' % total)
        print('      Either the macro is missing from this preamble (the usual')
        print('      cause -- it exists in the other manuscript), or it belongs')
        print('      to a package the preamble does not load, or it is base')
        print('      LaTeX this checker does not know about. In the last case,')
        print('      add it to BASE with a note, do not delete the check.')
        return 1
    print('OK: every command used resolves to a definition in scope.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
