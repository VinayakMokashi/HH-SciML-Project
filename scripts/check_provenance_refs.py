#!/usr/bin/env python3
"""check_provenance_refs.py -- validate every "file.ext:LINE" provenance pointer.

WHY THIS EXISTS
---------------
Law I asks every fixed INPUT and every ledger note to name the source line it came
from. Those pointers are plain text, so nothing keeps them honest: any edit that
inserts lines above a cited line silently invalidates every pointer below it.

That has now happened twice. The 2026-08 round found seven pointers into
src/experiment.jl drifted by +16 and fixed them; the very next round inserted the
HH_SMOKE output-isolation block into the same file and drifted every pointer again,
this time by +28. A pointer that is merely *stale* is worse than one that is
missing, because a reader who follows it lands on real code and believes it.

WHAT IT CHECKS
--------------
For every "<path>:<line>" or "<path>:<line>-<line>" or "<path>:<a>,<b>" it finds:
  FAIL  the file does not exist
  FAIL  the line number is past the end of the file
  WARN  the cited line is blank or is a bare delimiter ("end", "}", ")")
        -- almost always the signature of drift rather than an intentional target

It cannot tell a pointer that is in range but points at the wrong thing. For that
the report prints the cited line so a human can scan the list; grep-able output is
the point. Prefer citing a stable anchor (a function name, a LaTeX label) over a
line number wherever the surrounding text allows it.

Usage:  python scripts/check_provenance_refs.py [--quiet]
Exit code 1 if any FAIL.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Files whose text carries provenance pointers.
SCAN = [
    'paper/main.tex',
    'paper/metrics_map.yaml',
    'paper/claims.yaml',
    'paper/claim-guards.md',
    'Project.toml',
    'node_parity.jl',
    'experiments_runner.jl',
    'HH_model.jl',
    'src/experiment.jl',
    'src/hh_core.jl',
    'src/metrics.jl',
    'identifiability_parametric.jl',
    'objective3_symbolic.jl',
    'retrain_gca2_20k.jl',
    'recover_training_losses.jl',
    'figure_identifiability.jl',
]

# <path><:line>[-line][,line]...  path must end in a known source extension.
REF = re.compile(
    r'\b((?:[\w./\\-]+/)?[\w.-]+\.(?:jl|py|tex|yaml|toml|ps1|csv))'
    r':(\d+(?:\s*[-,]\s*\d+)*)\b'
)

BARE = {'end', '}', ')', '{', 'end)', '];', ']', '"""'}


def numbers(spec):
    out = []
    for part in re.split(r'[-,]', spec):
        part = part.strip()
        if part.isdigit():
            out.append(int(part))
    return out


def main():
    quiet = '--quiet' in sys.argv
    cache = {}
    fails, warns, total = [], [], 0

    for rel in SCAN:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        for lineno, text in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
            for m in REF.finditer(text):
                target, spec = m.group(1), m.group(2)
                # ignore self-referential "line 12" style inside URLs
                if '://' in text[:m.start()][-8:]:
                    continue
                tpath = os.path.join(ROOT, target.replace('\\', '/'))
                total += 1
                if not os.path.exists(tpath) and '/' not in target:
                    # bare basename: the repo keeps its modules under src/
                    alt = os.path.join(ROOT, 'src', target)
                    if os.path.exists(alt):
                        tpath = alt
                if not os.path.exists(tpath):
                    # only complain about paths that look repo-local
                    if '/' in target or target.endswith(('.jl', '.ps1')):
                        fails.append((rel, lineno, target, spec, 'target file not found'))
                    continue
                if tpath not in cache:
                    cache[tpath] = open(tpath, encoding='utf-8', errors='replace').read().split('\n')
                lines = cache[tpath]
                for n in numbers(spec):
                    if n < 1 or n > len(lines):
                        fails.append((rel, lineno, target, str(n),
                                      'line %d past end of file (%d lines)' % (n, len(lines))))
                        continue
                    body = lines[n - 1].strip()
                    if body == '' or body in BARE:
                        warns.append((rel, lineno, target, str(n),
                                      'cited line is %r' % (body or '<blank>')))

    print('-- check_provenance_refs: %d pointer(s) in %d file(s)' % (total, len(SCAN)))
    for rel, ln, tgt, spec, why in fails:
        print('FAIL %s:%d -> %s:%s  %s' % (rel, ln, tgt, spec, why))
    if not quiet:
        for rel, ln, tgt, spec, why in warns:
            print('WARN %s:%d -> %s:%s  %s' % (rel, ln, tgt, spec, why))

    if fails:
        print('\n%d broken pointer(s). A stale pointer is worse than none: it lands the '
              'reader on real code and looks authoritative.' % len(fails))
        return 1
    print('OK: no pointer past end of file.%s'
          % ('' if quiet else '  %d warning(s) -- read them, they usually mean drift.' % len(warns)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
