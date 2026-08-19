# scripts/stage_figures.ps1 - copy every figure the paper references into ONE
# directory (paper/figures) under a disambiguated name, so \graphicspath has a
# single entry and the colliding fig9..fig12 basenames (baseline vs retrain tree,
# which tell OPPOSITE stories) cannot silently resolve to the wrong file.
#
# _before / _after suffix == TRAINING BUDGET (Adam 5000/BFGS 300 vs 20000/1000),
# NOT gCa/noise/window. Run from the repo root; Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File scripts\stage_figures.ps1
#
# ASCII ONLY. PowerShell 5.1 reads a .ps1 as ANSI unless it has a BOM, and this
# file has none: the em-dash that used to sit in line 1 decoded to a smart quote
# and was a live parser hazard (see HANDOFF Sec 9). Do not paste one back in.
$r   = "d:\SciML\bootcamp\Research Project\HH-SciML-Project"
$dst = "$r\paper\figures"
New-Item -ItemType Directory -Force $dst | Out-Null

$map = [ordered]@{
  # --- colliding basenames -> disambiguated by training budget ---
  "figures\fig9_calcium_symbolic_parity.png"                               = "fig9_symbolic_parity_before.png"
  "figures\fig10_calcium_symbolic_timeseries.png"                          = "fig10_symbolic_timeseries_before.png"
  "figures\fig12_calcium_identifiability.png"                              = "fig12_identifiability_before.png"
  "results\retrain_gca2_20k\figures\fig9_calcium_symbolic_parity.png"      = "fig9_symbolic_parity_after.png"
  "results\retrain_gca2_20k\figures\fig10_calcium_symbolic_timeseries.png" = "fig10_symbolic_timeseries_after.png"
  "results\retrain_gca2_20k\figures\fig12_calcium_identifiability.png"     = "fig12_identifiability_after.png"
  # --- non-colliding, copied under their own names ---
  "figures\fig2_neural_ode_overview.png"                                   = "fig2_neural_ode_overview.png"
  "figures\fig3_ude_overview.png"                                          = "fig3_ude_overview.png"
  "figures\fig3_ude_calcium_parity.png"                                    = "fig3_ude_calcium_parity.png"
  "figures\fig5_metrics_bar_train_vs_forecast.png"                         = "fig5_metrics_bar_train_vs_forecast.png"
  "figures\fig6_voltage_only_overview.png"                                 = "fig6_voltage_only_overview.png"
  "figures\fig6_voltage_only_calcium_parity.png"                           = "fig6_voltage_only_calcium_parity.png"
  "figures\fig7b_commoneval_ablation_window.png"                           = "fig7b_commoneval_ablation_window.png"
  "figures\fig7c_ablation_gca.png"                                         = "fig7c_ablation_gca.png"
  "figures\fig7c_ablation_gca_5seed.png"                                   = "fig7c_ablation_gca_5seed.png"
  "figures\fig8_full_vs_voltage_metrics_bar.png"                           = "fig8_full_vs_voltage_metrics_bar.png"
  "figures\fig13_parametric_identifiability.png"                           = "fig13_parametric_identifiability.png"
  "figures\07_Stacked_Overview.png"                                        = "07_Stacked_Overview.png"
  "figures\08_Noisy_Data_Comparison.png"                                   = "08_Noisy_Data_Comparison.png"
}

# =============================================================================
#  DELIBERATELY NOT IN THE MAP: fig11_coeff_recovery_before.png / _after.png
# =============================================================================
#  They used to be here, mapped from figures\fig11_calcium_coeff_recovery.png and
#  its retrain-tree twin. Those two sources are now SUPERSEDED, and re-adding
#  either row silently reverts the paper's Fig 6b and Fig 8b to panels that:
#    - carry identical in-figure titles, so the reader cannot tell the baseline
#      from the aggressive retrain (the one comparison the pair exists for), and
#    - are drawn on independently scaled axes, which makes the appendix caption's
#      "on the same axes as Fig 6b" claim FALSE.
#  figure_coeff_recovery_panels.jl regenerates both from the metrics CSVs and
#  stages them into paper/figures itself. Regenerate with:
#      julia --project=. figure_coeff_recovery_panels.jl
#  Verified 2026-08-19: the superseded sources differ from the staged panels
#  (md5 9a1eca32.. vs b816e8d8.., 78ae3131.. vs 43ebdf7a..), so this is a real
#  overwrite, not a no-op.
# =============================================================================

$seen = @{}
foreach ($k in $map.Keys) {
  $v = $map[$k]
  if ($seen.ContainsKey($v)) { throw "destination collision: $v <- $k and $($seen[$v])" }
  $seen[$v] = $k
  if (-not (Test-Path "$r\$k")) { throw "missing source: $r\$k" }
  Copy-Item "$r\$k" "$dst\$v" -Force
}
Write-Output "staged $($map.Count) figures -> $dst"

# --- self-check: every image main.tex includes must now be present ----------
#  This is what would have caught the fig11 regression above, and the missing
#  fig13, without anyone having to remember either.
$tex = "$r\paper\main.tex"
if (Test-Path $tex) {
  $content = Get-Content $tex -Raw
  $needed = [regex]::Matches($content, '\\includegraphics\[[^\]]*\]\{([^}]*)\}') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
  $absent = @($needed | Where-Object { -not (Test-Path (Join-Path $dst $_)) })
  if ($absent.Count -gt 0) {
    throw ("main.tex includes figures that are NOT in $dst after staging: " +
           ($absent -join ", ") + " -- add them to the map, or regenerate them.")
  }
  $unstaged = @($needed | Where-Object { -not $seen.ContainsKey($_) })
  Write-Output "self-check OK: all $($needed.Count) figures main.tex includes are present"
  if ($unstaged.Count -gt 0) {
    Write-Output ("  note: staged by their own generator, not by this script: " +
                  ($unstaged -join ", "))
  }
}
