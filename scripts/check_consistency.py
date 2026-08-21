#!/usr/bin/env python3
"""check_consistency.py -- the ninth checker: repeated claims must agree.

WHY THIS EXISTS
---------------
Five audit rounds found 154 defects in this manuscript. By rounds 4 and 5 almost
none were errors of fact; they were CONSISTENCY DEBT. The paper asserts the same
dozen things in three to six places each. A correction lands in one or two of
them and the rest keep the old wording, so the next audit finds the survivors --
which is why the defect rate flattened at ~1.6 per audit area instead of falling
to zero. Each fix was seeding the next round's findings.

The round-5 blocker is the archetype: round 4 established that the
matched-objective control never isolates the optimiser (so the residual twofold
BOUNDS the representation rather than measuring it), wrote "say 'at most', never
'is'" into claims.yaml, and then applied it to Limitations alone. The abstract
still said "is". One site fixed out of five, in the most-read sentence.

No other checker can see this. check_numbers verifies that each number is
traceable; check_claims verifies the ledger is anchored; neither compares two
sentences to each other. This does.

WHAT IT CHECKS
--------------
paper/consistency.yaml declares one group per repeated claim:

    probe      regex that finds the sites (omit to check `forbid` only)
    require    every probed site must also match this, else FAIL
    forbid     no line in the listed files may match this, ever
    window     lines of context a `require` may be satisfied from (default 3)
    min_sites  fail if `probe` matches fewer sites than this -- catches a probe
               that has silently stopped matching after a rewrite
    files      which files the group applies to

LaTeX comment text is stripped before matching (honouring \\%), so a rule cannot
be satisfied or tripped by a comment. The one exception is `% numok:` /
`% claim:` markers, which are kept, because some rules are about them.

Usage:  python scripts/check_consistency.py [--verbose]
Exit 1 on any FAIL.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, 'paper', 'consistency.yaml')

#  Put this marker on a line that deliberately QUOTES a forbidden phrase in order
#  to warn against it -- guard notes in claims.yaml, "do not restore this" code
#  comments, and this file's own docstring all need it. Use it sparingly: every
#  escape is a line the checker stops protecting.
ESCAPE = 'consistency-ok'


def strip_tex_comments(text, path):
    """Blank out LaTeX comment text, keeping numok/claim markers and line count."""
    if not path.endswith('.tex'):
        return text
    out = []
    for line in text.split('\n'):
        i, cut = 0, None
        while i < len(line):
            if line[i] == '%' and (i == 0 or line[i - 1] != '\\'):
                cut = i
                break
            i += 1
        if cut is None:
            out.append(line)
        else:
            tail = line[cut:]
            keep = tail if ('numok:' in tail or 'claim:' in tail) else ''
            out.append(line[:cut] + keep)
    return '\n'.join(out)


def load_groups(path):
    """Minimal YAML reader for the shapes this file uses. No dependency."""
    groups, cur, key, buf = [], None, None, None

    def flush():
        nonlocal key, buf
        if key is not None and buf is not None:
            cur[key] = ' '.join(buf.split())
        key, buf = None, None

    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line.startswith('groups:'):
            continue
        m = re.match(r'^  - id:\s*(.+)$', line)
        if m:
            flush()
            cur = {'id': m.group(1).strip()}
            groups.append(cur)
            continue
        if cur is None:
            continue
        m = re.match(r'^    ([a-z_]+):\s*(.*)$', line)
        if m:
            flush()
            k, v = m.group(1), m.group(2).strip()
            if v in ('>-', '|', '>'):
                key, buf = k, ''
            elif v.startswith('[') and v.endswith(']'):
                cur[k] = [x.strip().strip('"\'') for x in v[1:-1].split(',') if x.strip()]
            elif v == 'null':
                cur[k] = None
            else:
                # scalars are written quoted in the spec so that regex
                # metacharacters survive; the quotes are not part of the value
                if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
                    v = v[1:-1]
                v = v.split('#')[0].strip() if re.match(r'^\d+\s*#', v) else v
                cur[k] = int(v) if v.isdigit() else v
            continue
        if key is not None and line.startswith('      '):
            buf = (buf + ' ' + line.strip()).strip()
    flush()
    return groups


def compile_rx(pat):
    """Compile a spec regex.

    The spec writes long alternations across several YAML lines for readability;
    the loader joins them with single spaces, which would otherwise leave a stray
    space after every '|' and stop the branch matching. Squeeze whitespace only
    at the alternation and group boundaries, never inside a phrase -- the phrases
    contain meaningful spaces.
    """
    if pat is None:
        return None
    pat = re.sub(r'\|\s+', '|', pat)
    pat = re.sub(r'\(\s+', '(', pat)
    pat = re.sub(r'\s+\)', ')', pat)
    return re.compile(pat, re.IGNORECASE)


def main():
    verbose = '--verbose' in sys.argv
    if not os.path.exists(SPEC):
        print('MISSING %s' % SPEC)
        return 1
    groups = load_groups(SPEC)

    cache = {}

    def lines_of(rel):
        if rel not in cache:
            p = os.path.join(ROOT, rel)
            if not os.path.exists(p):
                cache[rel] = None
            else:
                txt = open(p, encoding='utf-8', errors='replace').read()
                cache[rel] = strip_tex_comments(txt, rel).split('\n')
        return cache[rel]

    fails, checked = [], 0
    print('-- check_consistency: %d repeated-claim group(s)' % len(groups))

    for g in groups:
        gid = g['id']
        files = g.get('files') or ['paper/main.tex']
        probe = compile_rx(g.get('probe'))
        require = compile_rx(g.get('require'))
        forbid = compile_rx(g.get('forbid'))
        unless = compile_rx(g.get('forbid_unless'))
        only_if = compile_rx(g.get('only_if'))
        window = int(g.get('window', 3))
        min_sites = int(g.get('min_sites', 0))
        sites = 0

        for rel in files:
            L = lines_of(rel)
            if L is None:
                continue

            if forbid is not None:
                for i, line in enumerate(L, 1):
                    if ESCAPE in line:
                        continue          # deliberate meta-reference, see ESCAPE
                    if not forbid.search(line):
                        continue
                    # A forbidden phrase is fine when the paper is DENYING it
                    # ("the claim is not that two equally good fits disagree").
                    # The denial usually sits on the previous wrapped line, so
                    # look at a small window, not just the hit line.
                    if unless is not None:
                        lo = max(0, i - 3)
                        if unless.search(' '.join(L[lo:i + 1])):
                            continue
                    fails.append((gid, rel, i, 'FORBIDDEN phrase present',
                                  line.strip()[:110]))

            if probe is not None:
                # Claims routinely span two or three wrapped lines, so probe over
                # a joined sliding window rather than line by line. Matching line
                # by line was silently finding nothing, which is exactly the kind
                # of dead check this file exists to prevent -- hence min_sites.
                span = 3
                hit_at = set()
                for i in range(len(L)):
                    joined = ' '.join(L[i:i + span])
                    if not probe.search(joined):
                        continue
                    if ESCAPE in joined:
                        continue
                    # `only_if` separates a CLAIM site from a mere pointer.
                    # "the training-window ablation is in Fig. 8" asserts nothing
                    # and needs no qualifier; "the ablation gives X mV" does. The
                    # usual discriminator is that a claim quotes a macro.
                    if only_if is not None and not only_if.search(joined):
                        continue
                    # attribute the hit to the first line of the window, and do
                    # not double-count overlapping windows over one sentence
                    if any(abs(i - h) < span for h in hit_at):
                        continue
                    hit_at.add(i)
                    sites += 1
                    checked += 1
                    if require is None:
                        continue
                    lo, hi = max(0, i - window), min(len(L), i + span + window)
                    ctx = ' '.join(L[lo:hi])
                    if not require.search(ctx):
                        fails.append((gid, rel, i + 1,
                                      'site does not satisfy require',
                                      L[i].strip()[:110]))
                    elif verbose:
                        print('   ok  %s:%d  %s' % (rel, i + 1, gid))

        if probe is not None and sites < min_sites:
            fails.append((gid, files[0], 0,
                          'probe matched %d site(s), expected at least %d -- the '
                          'claim moved or the probe went stale' % (sites, min_sites),
                          ''))

    for gid, rel, ln, why, txt in fails:
        where = '%s:%d' % (rel, ln) if ln else rel
        print('FAIL [%s] %s' % (gid, where))
        print('     %s' % why)
        if txt:
            print('     %s' % txt)

    print()
    if fails:
        print('%d inconsistency/ies. A claim stated in several places has drifted in '
              'at least one of them.' % len(fails))
        print('Fix EVERY site, not the one the checker names first -- that is the '
              'failure mode this checker exists to catch.')
        return 1
    print('OK: %d probed site(s) across %d group(s) agree; no forbidden phrasing.'
          % (checked, len(groups)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
