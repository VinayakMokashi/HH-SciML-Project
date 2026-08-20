#!/usr/bin/env python3
"""
verify_references.py -- machine-verify every entry in paper/references.bib.

Mentor request (Prathamesh, 2026-08): venues have begun banning authors over
fabricated or unverifiable citations, so every reference must be checked against
an authoritative record and the evidence kept alongside the paper.

For each bib entry this script resolves the DOI against Crossref (journal and
conference records) or DataCite (Zenodo software records), and resolves the
eprint id against the arXiv API, then compares the returned title, first-author
surname and year with what the .bib file claims.  It writes a markdown audit
table with a working link per entry.

The check is deliberately conservative: a MISMATCH is a prompt to look, not a
verdict.  Titles differ legitimately in punctuation, LaTeX braces and subtitle
handling, and Crossref author records are sometimes incomplete.

Usage (from the repo root):
    python scripts/verify_references.py
    python scripts/verify_references.py --bib paper/references.bib \
                                        --out paper/citations-audit.md
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

UA = "HH-SciML-reference-audit/1.0 (mailto:vinayak_mokashi@brown.edu)"
TIMEOUT = 30


# --------------------------------------------------------------------------
#  .bib parsing -- deliberately small: our file is hand-maintained, one entry
#  per @type{key, ...} block with `field = {...}` or `field = "..."` lines.
# --------------------------------------------------------------------------
def parse_bib(text):
    entries = []
    # Strip full-line comments so commented-out fields never look like data.
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith("%")]
    text = "\n".join(lines)

    for m in re.finditer(r"@(\w+)\s*\{\s*([^,]+),", text):
        etype, key = m.group(1).lower(), m.group(2).strip()
        # Walk braces from the entry's opening brace to find its extent.
        start = text.index("{", m.start())
        depth, i = 0, start
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[start + 1:i]

        fields = {}
        for fm in re.finditer(r"(\w+)\s*=\s*", body):
            fname = fm.group(1).lower()
            j = fm.end()
            if j >= len(body):
                continue
            if body[j] == "{":
                d, k = 0, j
                while k < len(body):
                    if body[k] == "{":
                        d += 1
                    elif body[k] == "}":
                        d -= 1
                        if d == 0:
                            break
                    k += 1
                val = body[j + 1:k]
            elif body[j] == '"':
                k = body.index('"', j + 1)
                val = body[j + 1:k]
            else:
                k = j
                while k < len(body) and body[k] not in ",\n":
                    k += 1
                val = body[j:k]
            fields[fname] = " ".join(val.split())
        entries.append({"type": etype, "key": key, "fields": fields})
    return entries


# --------------------------------------------------------------------------
#  normalisation + comparison
# --------------------------------------------------------------------------
def norm_title(s):
    if not s:
        return ""
    s = s.replace("--", "-")
    s = re.sub(r"\\[a-zA-Z]+", " ", s)          # LaTeX commands
    s = re.sub(r"[{}$\\]", "", s)                # braces, math, escapes
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(s.split())


def first_surname(author_field):
    """Surname of the first author from a BibTeX author string."""
    if not author_field:
        return ""
    first = author_field.split(" and ")[0].strip()
    first = re.sub(r"[{}\\]", "", first)
    if "," in first:                              # "Surname, Given"
        surname = first.split(",")[0]
    else:                                         # "Given Surname"
        surname = first.split()[-1] if first.split() else ""
    # Drop spaces too, so "de Silva" and "deSilva" compare equal.
    surname = re.sub(r"[^A-Za-z\-']", "", surname)
    return surname.lower().replace(" ", "")


def token_overlap(a, b):
    ta, tb = set(a.split()), set(b.split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / max(len(ta), len(tb))


# --------------------------------------------------------------------------
#  resolvers
# --------------------------------------------------------------------------
def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.load(r)


def lookup_crossref(doi):
    d = http_json("https://api.crossref.org/works/" + urllib.parse.quote(doi))["message"]
    authors = d.get("author") or []
    surname = ""
    for a in authors:
        if a.get("family"):
            surname = a["family"]
            break
    year = ""
    for kf in ("published-print", "published-online", "issued", "created"):
        if d.get(kf, {}).get("date-parts", [[None]])[0][0]:
            year = str(d[kf]["date-parts"][0][0])
            break
    return {
        "source": "Crossref",
        "title": (d.get("title") or [""])[0],
        "surname": surname,
        "year": year,
        "container": (d.get("container-title") or [""])[0],
        "type": d.get("type", ""),
    }


def lookup_datacite(doi):
    d = http_json("https://api.datacite.org/dois/" + urllib.parse.quote(doi))["data"]["attributes"]
    titles = d.get("titles") or [{}]
    creators = d.get("creators") or [{}]
    c0 = creators[0]
    surname = c0.get("familyName") or (c0.get("name", "").split(",")[0])
    return {
        "source": "DataCite",
        "title": titles[0].get("title", ""),
        "surname": surname or "",
        "year": str(d.get("publicationYear", "")),
        "container": d.get("publisher", "") if isinstance(d.get("publisher"), str)
                     else (d.get("publisher") or {}).get("name", ""),
        "type": (d.get("types") or {}).get("resourceTypeGeneral", ""),
    }


def lookup_arxiv(eprint):
    url = "http://export.arxiv.org/api/query?id_list=" + urllib.parse.quote(eprint)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        root = ET.fromstring(r.read())
    ns = {"a": "http://www.w3.org/2005/Atom"}
    entry = root.find("a:entry", ns)
    if entry is None:
        raise ValueError("no arXiv entry")
    title = " ".join((entry.findtext("a:title", "", ns) or "").split())
    if title.lower().startswith("error"):
        raise ValueError("arXiv reports: " + title)
    authors = entry.findall("a:author", ns)
    surname = ""
    if authors:
        nm = authors[0].findtext("a:name", "", ns) or ""
        surname = nm.split()[-1] if nm.split() else ""
    published = entry.findtext("a:published", "", ns) or ""
    return {
        "source": "arXiv",
        "title": title,
        "surname": surname,
        "year": published[:4],
        "container": "arXiv",
        "type": "preprint",
    }


# --------------------------------------------------------------------------
def audit_entry(e):
    f = e["fields"]
    doi = (f.get("doi") or "").strip()
    eprint = (f.get("eprint") or "").strip()
    bib_title = f.get("title", "")
    bib_surname = first_surname(f.get("author", ""))
    bib_year = (f.get("year") or "").strip()

    records, errors = [], []

    if doi:
        got = None
        for fn in (lookup_crossref, lookup_datacite):
            try:
                got = fn(doi)
                break
            except Exception as ex:  # try the other registry before giving up
                errors.append(f"{fn.__name__}: {type(ex).__name__}")
        if got:
            records.append(got)
    if eprint:
        try:
            records.append(lookup_arxiv(eprint))
        except Exception as ex:
            errors.append(f"arxiv: {type(ex).__name__}: {ex}")

    checks = []
    for rec in records:
        overlap = token_overlap(norm_title(bib_title), norm_title(rec["title"]))
        title_ok = overlap >= 0.75
        rec_surname = rec["surname"].lower().replace(" ", "")
        auth_ok = (not bib_surname or not rec_surname
                   or bib_surname == rec_surname
                   or bib_surname in rec_surname
                   or rec_surname in bib_surname)
        year_ok = (not bib_year or not rec["year"]
                   or abs(int(bib_year) - int(rec["year"])) <= 1)
        checks.append({"rec": rec, "title_ok": title_ok, "overlap": overlap,
                       "auth_ok": auth_ok, "year_ok": year_ok})

    # Metadata completeness is a SEPARATE axis from correctness: an entry can
    # resolve perfectly on arXiv and still be missing the published DOI, which
    # is what a reader chasing the citation actually needs.
    gaps = []
    if not doi:
        gaps.append("no DOI")
    if e["type"] == "software" and not f.get("version"):
        gaps.append("software entry has no version")
    for rec in records:
        if rec["source"] == "Crossref" and rec["type"] in ("journal-article",
                                                           "proceedings-article",
                                                           "book-chapter"):
            if (f.get("journal", "").lower().startswith("arxiv")
                    or "arxiv preprint" in f.get("journal", "").lower()):
                gaps.append("cited as a preprint but a published record exists")

    if not records:
        status = "UNRESOLVED"
    elif all(c["title_ok"] and c["auth_ok"] and c["year_ok"] for c in checks):
        status = "VERIFIED"
    else:
        status = "REVIEW"

    if doi:
        link = "https://doi.org/" + doi
    elif eprint:
        link = "https://arxiv.org/abs/" + eprint
    else:
        link = ""

    return {"entry": e, "doi": doi, "eprint": eprint, "link": link,
            "status": status, "checks": checks, "errors": errors, "gaps": gaps,
            "bib_title": bib_title, "bib_surname": bib_surname, "bib_year": bib_year}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bib", default="paper/references.bib")
    ap.add_argument("--out", default="paper/citations-audit.md")
    ap.add_argument("--tex", default="paper/main.tex",
                    help="checked so every entry is actually cited (and vice versa)")
    args = ap.parse_args()

    bib_path = Path(args.bib)
    entries = parse_bib(bib_path.read_text(encoding="utf-8"))
    print(f"parsed {len(entries)} entries from {bib_path}")

    cited = set()
    tex_path = Path(args.tex)
    if tex_path.exists():
        tex = tex_path.read_text(encoding="utf-8")
        for m in re.finditer(r"\\cite[a-zA-Z]*\**(?:\[[^\]]*\])*\{([^}]*)\}", tex):
            for k in m.group(1).split(","):
                cited.add(k.strip())

    results = []
    for i, e in enumerate(entries, 1):
        r = audit_entry(e)
        results.append(r)
        print(f"  [{i:2d}/{len(entries)}] {e['key']:<28} {r['status']}")
        time.sleep(0.4)          # be polite to the public APIs

    n_ver = sum(1 for r in results if r["status"] == "VERIFIED")
    n_rev = sum(1 for r in results if r["status"] == "REVIEW")
    n_unr = sum(1 for r in results if r["status"] == "UNRESOLVED")

    out = []
    out.append("# Citation audit\n")
    out.append(f"Automated verification of `{args.bib}`, "
               f"produced by `scripts/verify_references.py`.\n")
    out.append("Every entry's DOI is resolved against **Crossref** (articles and "
               "proceedings) or **DataCite** (Zenodo software records), and every "
               "`eprint` id against the **arXiv API**. The returned title, "
               "first-author surname and year are compared against what the "
               "`.bib` file claims. Re-run the script to reproduce this table.\n")
    out.append(f"- Entries: **{len(results)}** "
               f"(verified {n_ver}, needs review {n_rev}, unresolved {n_unr})\n")
    out.append("\nStatus meanings:\n")
    out.append("- **VERIFIED** — every resolved record agrees with the bib entry "
               "on title (at least 75% word overlap after normalisation), "
               "first-author surname (substring match in either direction) and "
               "year (within +/-1). Volume, issue and page numbers are NOT "
               "compared, and an empty surname or year in the .bib passes "
               "automatically.\n")
    out.append("- **REVIEW** — the record resolved but at least one field "
               "disagrees. Usually LaTeX braces or punctuation in the title; "
               "read the note and confirm by eye.\n")
    out.append("- **UNRESOLVED** — no DOI and no arXiv id to check against, or "
               "the registry had no record. These need a manual link.\n")
    n_gap = sum(1 for r in results if r["gaps"])
    out.append(f"- Entries with incomplete metadata: **{n_gap}**\n")
    out.append("\n| # | Key | Cited as (title) | Type | Identifier | Verified link "
               "| Registry | Status | Metadata | Notes |\n")
    out.append("|---|---|---|---|---|---|---|---|---|---|\n")

    for i, r in enumerate(results, 1):
        e = r["entry"]
        ident = r["doi"] or (("arXiv:" + r["eprint"]) if r["eprint"] else "—")
        link = f"[resolve]({r['link']})" if r["link"] else "—"
        registry = ", ".join(sorted({c["rec"]["source"] for c in r["checks"]})) or "—"
        notes = []
        for c in r["checks"]:
            src = c["rec"]["source"]
            if not c["title_ok"]:
                notes.append(f"{src} title differs (overlap {c['overlap']:.2f}): "
                             f"“{c['rec']['title'][:70]}”")
            if not c["auth_ok"]:
                notes.append(f"{src} first author “{c['rec']['surname']}” vs "
                             f"bib “{r['bib_surname']}”")
            if not c["year_ok"]:
                notes.append(f"{src} year {c['rec']['year']} vs bib {r['bib_year']}")
        if e["key"] not in cited and cited:
            notes.append("**not cited in main.tex**")
        if not r["doi"] and not r["eprint"]:
            notes.append("no DOI and no arXiv id in the entry")
        # A failed Crossref call is routine and uninteresting when another
        # registry resolved the entry: arXiv and Zenodo DOIs live in DataCite,
        # so Crossref returns 404 for them by design.  Only surface lookup
        # errors when nothing resolved at all.
        if r["errors"] and not r["checks"]:
            notes.append("lookup errors: " + "; ".join(r["errors"]))
        title = r["bib_title"].replace("|", "\\|")
        title = re.sub(r"\s+", " ", title)
        if len(title) > 80:
            title = title[:77] + "..."
        meta = "; ".join(sorted(set(r["gaps"]))) if r["gaps"] else "complete"
        out.append(f"| {i} | `{e['key']}` | {title} | {e['type']} | "
                   f"`{ident}` | {link} | {registry} | **{r['status']}** | "
                   f"{meta} | {'; '.join(notes) if notes else '—'} |\n")

    uncited = sorted(k for k in {e["key"] for e in entries} if cited and k not in cited)
    missing = sorted(k for k in cited if k not in {e["key"] for e in entries})
    out.append("\n## Cross-check against the manuscript\n\n")
    out.append(f"- Entries in the bib file: **{len(entries)}**\n")
    out.append(f"- Distinct keys cited in `{args.tex}`: **{len(cited)}**\n")
    out.append(f"- Bib entries never cited: {('`' + '`, `'.join(uncited) + '`') if uncited else '**none**'}\n")
    out.append(f"- Cited keys with no bib entry: {('`' + '`, `'.join(missing) + '`') if missing else '**none**'}\n")

    Path(args.out).write_text("".join(out), encoding="utf-8")
    print(f"\nwrote {args.out}: {n_ver} verified, {n_rev} review, {n_unr} unresolved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
