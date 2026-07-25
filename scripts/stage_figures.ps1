# scripts/stage_figures.ps1 — copy every figure the paper references into ONE
# directory (paper/figures) under a disambiguated name, so \graphicspath has a
# single entry and the colliding fig9..fig12 basenames (baseline vs retrain tree,
# which tell OPPOSITE stories) cannot silently resolve to the wrong file.
#
# _before / _after suffix == TRAINING BUDGET (Adam 5000/BFGS 300 vs 20000/1000),
# NOT gCa/noise/window. Run from the repo root; Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File scripts\stage_figures.ps1
$r   = "d:\SciML\bootcamp\Research Project\HH-SciML-Project"
$dst = "$r\paper\figures"
New-Item -ItemType Directory -Force $dst | Out-Null

$map = [ordered]@{
  # --- colliding basenames -> disambiguated by training budget ---
  "figures\fig9_calcium_symbolic_parity.png"                               = "fig9_symbolic_parity_before.png"
  "figures\fig10_calcium_symbolic_timeseries.png"                          = "fig10_symbolic_timeseries_before.png"
  "figures\fig11_calcium_coeff_recovery.png"                               = "fig11_coeff_recovery_before.png"
  "figures\fig12_calcium_identifiability.png"                              = "fig12_identifiability_before.png"
  "results\retrain_gca2_20k\figures\fig9_calcium_symbolic_parity.png"      = "fig9_symbolic_parity_after.png"
  "results\retrain_gca2_20k\figures\fig10_calcium_symbolic_timeseries.png" = "fig10_symbolic_timeseries_after.png"
  "results\retrain_gca2_20k\figures\fig11_calcium_coeff_recovery.png"      = "fig11_coeff_recovery_after.png"
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
  "figures\fig8_full_vs_voltage_metrics_bar.png"                           = "fig8_full_vs_voltage_metrics_bar.png"
  "figures\07_Stacked_Overview.png"                                        = "07_Stacked_Overview.png"
  "figures\08_Noisy_Data_Comparison.png"                                   = "08_Noisy_Data_Comparison.png"
}

$seen = @{}
foreach ($k in $map.Keys) {
  $v = $map[$k]
  if ($seen.ContainsKey($v)) { throw "destination collision: $v <- $k and $($seen[$v])" }
  $seen[$v] = $k
  if (-not (Test-Path "$r\$k")) { throw "missing source: $r\$k" }
  Copy-Item "$r\$k" "$dst\$v" -Force
}
Write-Output "staged $($map.Count) figures -> $dst"
