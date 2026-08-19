# =============================================================================
#  make_overleaf_zip.ps1  ->  overleaf_upload.zip
# =============================================================================
#  Assembles exactly what Overleaf needs, with the directory structure the
#  document's relative paths assume. Run it, then drag the zip into Overleaf.
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
#  WHAT IS DELIBERATELY NOT INCLUDED:
#    - arxiv.sty. main.tex has \usepackage{arxiv}; arxiv.sty is NOT a CTAN
#      package and is NOT in this repo, so TeX Live/Overleaf cannot supply it.
#      It already exists in the live Overleaf project -- that is the only reason
#      the paper has ever compiled there. NEVER delete it, and if you ever start
#      a NEW project, copy it in first or the build dies on line 3.
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

$tex = Join-Path $paper "main.tex"
if (-not (Test-Path $tex)) { throw "main.tex not found at $tex" }

# --- build the source -> entry-name plan ------------------------------------
$plan = New-Object System.Collections.ArrayList
function Add-Item2Plan($src, $entry) {
    [void]$plan.Add([PSCustomObject]@{ Src = $src; Entry = $entry })
}

Add-Item2Plan $tex                                    "main.tex"
Add-Item2Plan (Join-Path $paper "references.bib")     "references.bib"
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

Write-Host ""
Write-Host ("wrote " + $zip)
Write-Host ("  main.tex + references.bib + generated/metrics.{tex,json} + " +
            $names.Count + " figures, verified " + $plan.Count + " entries")
foreach ($p in $plan) { Write-Host ("    " + $p.Entry) }
Write-Host ""
Write-Host "Upload: open the Overleaf project -> Upload -> select this zip -> overwrite when asked."
Write-Host "arxiv.sty is NOT in the zip and must stay in the project. Do not delete it."
