# =============================================================================
#  src/metrics.jl  —  Quantitative evaluation (Workstream 1)
# =============================================================================
#  All metrics are scored against the CLEAN trajectory `data_clean` (honest
#  model error), never the noisy training target.  Train window = t<=t_train_end,
#  forecast window = t>t_train_end, always reported separately.
#
#  `compute_metrics` returns a TIDY (long) vector of rows
#       (model, observed, gCa, noise_level, t_train_end, seed, window, metric, value)
#  so every run from every experiment appends uniformly to one master CSV.
# =============================================================================

using Statistics

# --- Basic errors ------------------------------------------------------------
rmse(a, b) = sqrt(mean(abs2, vec(a) .- vec(b)))

# Drop non-finite pairs first (the black-box Neural ODE forecast blows up to
# ±1e4 / NaN; we still want a meaningful RMSE on the finite part).
function rmse_safe(a, b)
    d    = vec(a) .- vec(b)
    good = isfinite.(d)
    any(good) || return Inf
    return sqrt(mean(abs2, d[good]))
end

# --- Spike detection (peak finding on V) ------------------------------------
#  A sample is a spike peak if it is a local maximum, finite, and above
#  `vthresh` (rest is -65 mV, spikes overshoot well above 0).  Peaks closer than
#  `min_dist_ms` are merged (refractory) — keep the taller one.
function detect_spikes(V, t; vthresh = 0.0, min_dist_ms = 2.0)
    peaks_t = Float64[]
    peaks_v = Float64[]
    for i in 2:length(V)-1
        vi = V[i]
        (isfinite(vi) && isfinite(V[i-1]) && isfinite(V[i+1])) || continue
        if vi > vthresh && vi > V[i-1] && vi >= V[i+1]
            ti = t[i]
            if !isempty(peaks_t) && (ti - peaks_t[end]) < min_dist_ms
                if vi > peaks_v[end]            # within refractory: keep taller
                    peaks_t[end] = ti
                    peaks_v[end] = vi
                end
            else
                push!(peaks_t, ti)
                push!(peaks_v, vi)
            end
        end
    end
    return peaks_t
end

# --- Spike-time error (greedy nearest match within tolerance) ----------------
function spike_time_error(t_pred, t_true; match_tol_ms = 2.0)
    n_true = length(t_true)
    n_pred = length(t_pred)
    used   = falses(n_pred)
    devs   = Float64[]
    for tt in t_true
        best_j, best_d = 0, Inf
        for j in 1:n_pred
            used[j] && continue
            d = abs(t_pred[j] - tt)
            d < best_d && (best_d = d; best_j = j)
        end
        if best_j != 0 && best_d <= match_tol_ms
            used[best_j] = true
            push!(devs, best_d)
        end
    end
    return (; mean_abs_dev_ms = isempty(devs) ? NaN : mean(devs),
              count_diff = n_pred - n_true,
              n_matched  = length(devs),
              n_true, n_pred)
end

# --- Rollout horizon ---------------------------------------------------------
#  Elapsed time from `t_start` until |Vpred - Vtrue| first exceeds `thresh_mv`
#  and STAYS above it for at least `sustained_ms` (single-sample blips ignored).
#  Non-finite error counts as a breach.
#
#  RIGHT-CENSORING.  A run that never breaches is censored, and it is censored at
#  whichever comes first: the `cap_ms` ceiling, or the end of the trajectory we
#  actually have.  The second bound used to be missing, and it mattered: on the
#  common-evaluation window `t_start` is ~50.1 ms with the trace ending at 100 ms,
#  so only ~49.9 ms of data exists, yet every such run reported the full 70 ms cap
#  -- a horizon 40% longer than the window it was measured in.  `avail` below is
#  that second bound.  Both exits are clamped to it, so the returned value is
#  always a duration the data could actually support, and a value equal to
#  `min(cap_ms, avail)` still means "never breached" (report it as ">=", per the
#  censoring guard).
function rollout_horizon(Vp, Vt, t; thresh_mv = 10.0, t_start = 30.0,
                         sustained_ms = 1.0, cap_ms = 70.0)
    idx = findall(ti -> ti >= t_start, t)
    isempty(idx) && return 0.0
    avail = max(0.0, t[end] - t_start)
    ceil_ms = min(cap_ms, avail)
    dt   = length(t) > 1 ? (t[end] - t[1]) / (length(t) - 1) : 1.0
    nsus = max(1, round(Int, sustained_ms / dt))
    run  = 0
    for i in idx
        err = abs(Vp[i] - Vt[i])
        if !isfinite(err) || err > thresh_mv
            run += 1
            if run >= nsus
                t_breach = t[i - (nsus - 1)]
                return min(ceil_ms, max(0.0, t_breach - t_start))
            end
        else
            run = 0
        end
    end
    return ceil_ms
end

# --- helper: build one tidy row ---------------------------------------------
_row(id, window, metric, value) =
    (; id..., window = String(window), metric = String(metric), value = Float64(value))

# --- compute_metrics ---------------------------------------------------------
#  truth/pred are 6 x N aligned to `t` (pred NaN-padded past any early stop).
#  Optional: truth_noisy (secondary vs-noisy V RMSE), ICa_true/ICa_nn (calcium
#  recovery), and the spike/rollout knobs.
#  `common_idx` (optional): a fixed evaluation window (indices into `t`), scored
#  in addition to train/forecast and tagged window="common_eval".  Used by the
#  training-window ablation so every training length is judged on ONE shared
#  forecast interval.  Purely additive — the tidy schema is unchanged; runs that
#  omit it simply produce no common_eval rows.
function compute_metrics(; model, observed, gCa, noise_level, t_train_end, seed,
                           t, truth, pred, train_idx, forecast_idx,
                           truth_noisy = nothing, ICa_true = nothing, ICa_nn = nothing,
                           common_idx = nothing,
                           vthresh = 0.0, min_dist_ms = 2.0, match_tol_ms = 2.0,
                           rollout_thresh_mv = 10.0, rollout_sustained_ms = 1.0,
                           rollout_cap_ms = 70.0)
    id = (; model = String(model), observed = String(observed),
            gCa, noise_level, t_train_end, seed)
    gate_names = ("m", "h", "n", "p", "s")
    rows = NamedTuple[]

    windows = Any[(:train, train_idx), (:forecast, forecast_idx)]
    common_idx !== nothing && push!(windows, (:common_eval, common_idx))
    for (wname, widx) in windows
        isempty(widx) && continue
        # voltage + per-gate RMSE vs clean truth
        push!(rows, _row(id, wname, "V_rmse", rmse_safe(truth[1, widx], pred[1, widx])))
        gate_rmses = Float64[]
        for (gi, gn) in enumerate(gate_names)
            r = rmse_safe(truth[gi+1, widx], pred[gi+1, widx])
            push!(gate_rmses, r)
            push!(rows, _row(id, wname, "$(gn)_rmse", r))
        end
        push!(rows, _row(id, wname, "gate_rmse_mean", mean(gate_rmses)))

        # secondary: V RMSE vs the noisy target (the noise floor), for transparency
        if truth_noisy !== nothing
            push!(rows, _row(id, wname, "V_rmse_vs_noisy",
                             rmse_safe(truth_noisy[1, widx], pred[1, widx])))
        end

        # calcium-current recovery (the UDE's learned term vs the true current)
        if ICa_true !== nothing && ICa_nn !== nothing
            r = rmse_safe(ICa_true[widx], ICa_nn[widx])
            push!(rows, _row(id, wname, "ICa_rmse", r))
            sd = std(filter(isfinite, ICa_true[widx]))
            push!(rows, _row(id, wname, "ICa_rmse_norm", sd > 0 ? r / sd : NaN))
        end
    end

    # forecast-only spike + rollout metrics
    if !isempty(forecast_idx)
        sp_true = detect_spikes(truth[1, forecast_idx], t[forecast_idx];
                                vthresh = vthresh, min_dist_ms = min_dist_ms)
        sp_pred = detect_spikes(pred[1, forecast_idx],  t[forecast_idx];
                                vthresh = vthresh, min_dist_ms = min_dist_ms)
        se = spike_time_error(sp_pred, sp_true; match_tol_ms = match_tol_ms)
        push!(rows, _row(id, :forecast, "spike_mean_abs_dev_ms", se.mean_abs_dev_ms))
        push!(rows, _row(id, :forecast, "spike_count_diff", se.count_diff))

        t_start = t[forecast_idx[1]]
        rh = rollout_horizon(pred[1, :], truth[1, :], t;
                             thresh_mv = rollout_thresh_mv, t_start = t_start,
                             sustained_ms = rollout_sustained_ms, cap_ms = rollout_cap_ms)
        push!(rows, _row(id, :forecast, "rollout_horizon_ms", rh))
    end

    # same spike + rollout metrics over the fixed common evaluation window, so the
    # training-window ablation can compare them on one shared interval.
    if common_idx !== nothing && !isempty(common_idx)
        sp_true = detect_spikes(truth[1, common_idx], t[common_idx];
                                vthresh = vthresh, min_dist_ms = min_dist_ms)
        sp_pred = detect_spikes(pred[1, common_idx],  t[common_idx];
                                vthresh = vthresh, min_dist_ms = min_dist_ms)
        se = spike_time_error(sp_pred, sp_true; match_tol_ms = match_tol_ms)
        push!(rows, _row(id, :common_eval, "spike_mean_abs_dev_ms", se.mean_abs_dev_ms))
        push!(rows, _row(id, :common_eval, "spike_count_diff", se.count_diff))

        t_start = t[common_idx[1]]
        rh = rollout_horizon(pred[1, :], truth[1, :], t;
                             thresh_mv = rollout_thresh_mv, t_start = t_start,
                             sustained_ms = rollout_sustained_ms, cap_ms = rollout_cap_ms)
        push!(rows, _row(id, :common_eval, "rollout_horizon_ms", rh))
    end

    return rows
end
