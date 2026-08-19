# =============================================================================
#  make_overleaf_zip.ps1  ->  overleaf_upload/  AND  overleaf_upload.zip
# =============================================================================
#  Assembles exactly what Overleaf needs, with the directory structure the
#  document's relative paths assume. TWO artifacts, because Overleaf treats them
#  completely differently and only one of them fits the usual case:
#
#    overleaf_upload/      <- DRAG THIS into an EXISTING project's file tree.
#                             Open the folder, select all four items (main.tex,
#                             references.bib, figures, generated) and drag them
#                             onto the file tree. Overleaf merges the folders and
#                             asks before overwriting. Keeps the project URL and
#                             its collaborators.
#
#    overleaf_upload.zip   <- ONLY for New Project -> Upload Project, which
#                             creates a BRAND NEW project by extracting it.
#                             *** Uploading this zip INTO an existing project
#                             does NOT extract it. *** Overleaf stores it as a
#                             binary file and nothing compiles. That is a real
#                             thing that happened; hence the folder above.
#
#  WHY A SCRIPT AND NOT "just zip the paper folder":
#
#    paper/main.tex resolves three paths RELATIVE TO THE COMPILE ROOT:
#        \input{generated/metrics}     -> generated/metrics.tex
#        \graphicspath{{figures/}}     -> figures/*.png
#        \bibliography{references}     -> references.bib
#    Zipping the FOLDER puts everything one level down (paper/main.tex,
#    paper/figures/...). Overleaf then compiles paper/main.tex from the project
#    root and every one of those three paths misses. The contents must sit at
#    the ZIP ROOT, which is what this script builds.
#
#  arxiv.sty IS INCLUDED (since 2026-08-19). main.tex has \usepackage{arxiv},
#  and arxiv.sty is not a CTAN package, so neither Overleaf nor a local TeX Live
#  can supply it. It was previously assumed to live in the Overleaf project; it
#  did not, and its absence was what broke the first upload. It is now vendored
#  at paper/arxiv.sty and shipped in every bundle, so the upload is
#  self-contained and a brand-new project compiles without a manual step.
#
#  WHAT IS DELIBERATELY NOT INCLUDED:
#    - claims.yaml, claim-guards.md, metrics_map.yaml, citations-audit.md.
#      These are the audit trail, not build inputs; Overleaf ignores them.
#    - Unreferenced figures. Only the images main.tex actually includes are
#      copied, read live out of the .tex, so this cannot drift.
#
#  TWO WINDOWS TRAPS THIS SCRIPT EXISTS TO AVOID (both were hit while writing it):
#    1. ZipFile.CreateFromDirectory stores WINDOWS separators on .NET Framework
#       ("figures\fig2.png"). The ZIP format mandates "/", and the Linux unzip
#       Overleaf runs reads a backslash as an ordinary filename character -- so
#       the archive extracts as flat files literally named "figures\fig2.png",
#       no figures/ directory appears, and every \includegraphics misses.
#       Entries are therefore written by hand, and verified before hand-over.
#    2. Deriving entry names by string-slicing a staging path is unsafe:
#       $env:TEMP is often the 8.3 short form ("VINAYA~1") while FullName
#       returns the long form, so the offsets disagree and names come out
#       truncated ("1d1200/main.tex"). There is no staging directory now; every
#       entry name is stated literally below.
#
#  ASCII ONLY: PowerShell 5.1 reads a .ps1 as ANSI unless it has a BOM, and one
#  non-ASCII character in a COMMENT kills the parser (see HANDOFF Sec 9).
#
#  Usage:  powershell -ExecutionPolicy Bypass -File scripts\make_overleaf_zip.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$repo  = Split-Path -Parent $PSScriptRoot
$paper = Join-Path $repo "paper"
$zip   = Join-Path $repo "overleaf_upload.zip"
$dir   = Join-Path $repo "overleaf_upload"

$tex = Join-Path $paper "main.tex"
if (-not (Test-Path $tex)) { throw "main.tex not found at $tex" }

# --- build the source -> entry-name plan ------------------------------------
$plan = New-Object System.Collections.ArrayList
function Add-Item2Plan($src, $entry) {
    [void]$plan.Add([PSCustomObject]@{ Src = $src; Entry = $entry })
}

Add-Item2Plan $tex                                    "main.tex"
Add-Item2Plan (Join-Path $paper "references.bib")     "references.bib"
Add-Item2Plan (Join-Path $paper "arxiv.sty")          "arxiv.sty"
Add-Item2Plan (Join-Path $paper "generated\metrics.tex")  "generated/metrics.tex"
Add-Item2Plan (Join-Path $paper "generated\metrics.json") "generated/metrics.json"

# figures: exactly those main.tex includes, read out of the source itself
$content = Get-Content $tex -Raw
$names = [regex]::Matches($content, '\\includegraphics\[[^\]]*\]\{([^}]*)\}') |
         ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($n in $names) {
    Add-Item2Plan (Join-Path $paper (Join-Path "figures" $n)) ("figures/" + $n)
}

$missing = @($plan | Where-Object { -not (Test-Path $_.Src) })
if ($missing.Count -gt 0) {
    throw ("referenced by main.tex but missing on disk: " +
           (($missing | ForEach-Object { $_.Entry }) -join ", "))
}

# --- write the archive ------------------------------------------------------
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, "Create")
try {
    foreach ($p in $plan) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $p.Src, $p.Entry) | Out-Null
    }
} finally {
    $archive.Dispose()
}

# --- verify rather than trust ------------------------------------------------
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $got = @($check.Entries | ForEach-Object { $_.FullName })
    $bad = @($got | Where-Object { $_ -like "*\*" })
    if ($bad.Count -gt 0) { throw ("zip entry contains a backslash: " + $bad[0]) }
    $want = @($plan | ForEach-Object { $_.Entry })
    $diff = @(Compare-Object $want $got)
    if ($diff.Count -gt 0) { throw "zip contents do not match the plan" }
} finally {
    $check.Dispose()
}

# --- write the drag-ready folder -------------------------------------------
#  Same plan, laid out on disk. This is the artifact for the normal case: an
#  existing project that already has arxiv.sty and collaborators on it.
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir -Force | Out-Null
foreach ($p in $plan) {
    $target = Join-Path $dir ($p.Entry -replace "/", "\")
    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item $p.Src $target -Force
}
$staged = @(Get-ChildItem $dir -Recurse -File).Count
if ($staged -ne $plan.Count) {
    throw ("staged $staged files but planned " + $plan.Count)
}

Write-Host ""
Write-Host ("wrote " + $dir + "\   (" + $plan.Count + " files, verified)")
Write-Host ("wrote " + $zip)
Write-Host ("  main.tex + references.bib + generated/metrics.{tex,json} + " +
            $names.Count + " figures")
foreach ($p in $plan) { Write-Host ("    " + $p.Entry) }
Write-Host ""
Write-Host "TO UPDATE THE EXISTING PROJECT (normal case, keeps the URL and collaborators):"
Write-Host "  open overleaf_upload\ , select ALL 5 items (main.tex, references.bib, arxiv.sty,"
Write-Host "  figures, generated) and DRAG them onto the Overleaf file tree. Overwrite when asked."
Write-Host ""
Write-Host "The .zip is ONLY for New Project -> Upload Project, which makes a NEW project."
Write-Host "Uploading the zip INTO an existing project does not extract it -- it just sits there."
Write-Host "arxiv.sty is now vendored at paper/arxiv.sty and IS included, so the bundle is"
Write-Host "self-contained: a brand-new Overleaf project will compile from it unaided."
