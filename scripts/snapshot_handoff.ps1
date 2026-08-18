# scripts/snapshot_handoff.ps1 — archive HANDOFF.md into git history without
# leaving it in the repo's file tree.
#
# WHY THIS EXISTS
# HANDOFF.md is the session-to-session continuity file. It is gitignored so it does
# not show up in the repo listing, but a wholesale rewrite once destroyed several of
# its sections with no copy to restore from. So: snapshot it deliberately, then take
# it back out, leaving the content in history and the working tree clean.
#
# It makes TWO commits:
#   1. "chore: snapshot HANDOFF.md (<date>)"  — adds the file
#   2. "chore: remove HANDOFF.md from tree"   — removes it again
# so HEAD never carries it, while commit 1 preserves it forever.
#
# *** THIS IS NOT A PRIVACY MECHANISM. ***
# The repository is PUBLIC. Every snapshot is readable by anyone who browses the
# commit history — GitHub shows deleted files in their commit diffs. Keeping the file
# out of the working tree hides it from a casual glance at the file list and from
# nothing else. If something genuinely must not be seen, it does not belong in this
# file at all.
#
# Recover the latest snapshot with:
#     git log --oneline --all -- HANDOFF.md
#     git show <commit>:HANDOFF.md > HANDOFF.md
#
# Usage (from the repo root):
#     powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1
#     powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1 -Push

param([switch]$Push)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path "HANDOFF.md")) {
    Write-Error "HANDOFF.md not found in $root — nothing to snapshot."
}

# Refuse to run with unrelated staged changes: this script makes two commits of its
# own, and sweeping up someone else's staged work into them would be a nasty surprise.
$staged = git diff --cached --name-only
if ($staged) {
    Write-Error ("Refusing to run: you have staged changes.`n" +
                 "Commit or unstage them first, then re-run.`n" +
                 "Staged: " + ($staged -join ", "))
}

$stamp = Get-Date -Format "yyyy-MM-dd"

# -f is required: HANDOFF.md is gitignored on purpose, so only a deliberate add works.
git add -f HANDOFF.md
if ($LASTEXITCODE -ne 0) { Write-Error "git add failed" }

# Nothing to do if the content is identical to the last snapshot.
$pending = git diff --cached --name-only
if (-not $pending) {
    Write-Output "HANDOFF.md is unchanged since the last snapshot — nothing committed."
    exit 0
}

git commit -q -m "chore: snapshot HANDOFF.md ($stamp)"
if ($LASTEXITCODE -ne 0) { Write-Error "snapshot commit failed" }

git rm --cached -q HANDOFF.md
if ($LASTEXITCODE -ne 0) { Write-Error "git rm --cached failed" }

git commit -q -m "chore: remove HANDOFF.md from tree (snapshot retained in history)"
if ($LASTEXITCODE -ne 0) { Write-Error "removal commit failed" }

Write-Output "Snapshotted HANDOFF.md ($stamp): archived in history, absent from the tree."
git log --oneline -2

if ($Push) {
    git push origin HEAD
    if ($LASTEXITCODE -ne 0) { Write-Error "push failed" }
    Write-Output "Pushed."
} else {
    Write-Output "Not pushed. Run 'git push origin main' when ready, or pass -Push."
}
