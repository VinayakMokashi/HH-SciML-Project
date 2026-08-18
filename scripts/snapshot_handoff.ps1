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
# Usage (from anywhere):
#     powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1
#     powershell -ExecutionPolicy Bypass -File scripts\snapshot_handoff.ps1 -Push
#
# IMPLEMENTATION NOTE — do not "tidy" these two things away:
#  * No `$ErrorActionPreference = "Stop"`. Under Windows PowerShell 5.1 that turns
#    ordinary git stderr chatter (the CRLF line-ending warnings this repo emits on
#    nearly every add) into terminating errors.
#  * Success is checked by asking git what actually happened, not by $LASTEXITCODE.
#    `git commit` exits non-zero for the perfectly normal "nothing to commit", so an
#    exit-code check reports a failure that did not occur — which is exactly how the
#    first version of this script broke.

param([switch]$Push)

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path "HANDOFF.md")) { Fail "HANDOFF.md not found in $root — nothing to snapshot." }

# Refuse to run with unrelated staged changes: this script makes two commits of its
# own, and sweeping up someone else's staged work into them would be a nasty surprise.
$staged = @(git diff --cached --name-only | Where-Object { $_ })
if ($staged.Count -gt 0) {
    Fail ("you have staged changes; commit or unstage them first. Staged: " + ($staged -join ", "))
}

$startHead = (git rev-parse HEAD).Trim()
$stamp     = Get-Date -Format "yyyy-MM-dd"

# -f is required: HANDOFF.md is gitignored on purpose, so only a deliberate add works.
git add -f HANDOFF.md | Out-Null
$pending = @(git diff --cached --name-only | Where-Object { $_ })
if ($pending.Count -eq 0) {
    Write-Host "HANDOFF.md is byte-identical to the last snapshot — nothing to do."
    exit 0
}

# --- commit 1: the snapshot -------------------------------------------------
git commit -q -m "chore: snapshot HANDOFF.md ($stamp)" | Out-Null
$afterAdd = (git rev-parse HEAD).Trim()
if ($afterAdd -eq $startHead) { Fail "snapshot commit did not happen (HEAD unchanged)." }
git cat-file -e "${afterAdd}:HANDOFF.md" 2>$null
if (-not $?) { Fail "snapshot commit exists but does not contain HANDOFF.md." }

# --- commit 2: take it back out --------------------------------------------
git rm --cached -q HANDOFF.md | Out-Null
git commit -q -m "chore: remove HANDOFF.md from tree (snapshot retained in history)" | Out-Null
$afterRm = (git rev-parse HEAD).Trim()
if ($afterRm -eq $afterAdd) { Fail "removal commit did not happen (HEAD unchanged)." }

# --- verify the invariant: in history, absent from the tree -----------------
git cat-file -e "${afterRm}:HANDOFF.md" 2>$null
if ($?) { Fail "HANDOFF.md is still present at HEAD — the removal commit did not work." }
if (-not (Test-Path "HANDOFF.md")) { Fail "HANDOFF.md was deleted from disk! Restore it: git show ${afterAdd}:HANDOFF.md > HANDOFF.md" }

Write-Host "Snapshotted HANDOFF.md ($stamp)." -ForegroundColor Green
Write-Host "  archived in : $afterAdd"
Write-Host "  absent from : HEAD ($afterRm)"
Write-Host "  on disk     : yes"
git log --oneline -2

if ($Push) {
    git push origin HEAD
    if ($LASTEXITCODE -ne 0) { Fail "push failed" }
    Write-Host "Pushed." -ForegroundColor Green
} else {
    Write-Host "Not pushed. Run 'git push origin main', or pass -Push next time."
}
