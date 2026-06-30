# =============================================================================
#  src/hh_core.jl  —  Advanced Hodgkin–Huxley model + data builders
# =============================================================================
#  Side-effect-free core shared by the narrative script and the experiment
#  engine (src/experiment.jl).  Defining this file runs NOTHING expensive: it
#  only declares constants, kinetics, and *builder* functions.  Nothing is
#  solved, trained, or plotted at include time.
#
#  The three quantities the ablations sweep — gCa, the noise level, and the
#  training-window length — are NOT constants here.  They are passed as
#  arguments to the builders below.  In particular `make_hh_advanced(gCa)`
#  returns a CLOSURE that captures gCa as a local, so the ODE right-hand side
#  never reads a mutable global (a non-const global in the hot RHS would force
#  dynamic dispatch and wreck adjoint performance on Julia 1.6.7).  Do NOT
#  "simplify" this back into a reassignable global.
#
#  UNITS (standard squid-axon convention, resting potential ~ -65 mV)
#        V : mV     t : ms     C : uF/cm^2     g : mS/cm^2     I : uA/cm^2     E : mV
# =============================================================================

using DifferentialEquations
using Statistics
using StableRNGs
using Random

# -----------------------------------------------------------------------------
#  Fixed biophysical constants (literature-grounded; never swept).
#  gCa is deliberately ABSENT here — it is a builder argument.
# -----------------------------------------------------------------------------
const Cm   = 1.0      # membrane capacitance
const gNa  = 120.0    # max sodium conductance
const gK   = 36.0     # max potassium conductance
const gL   = 0.3      # leak conductance
const ENa  = 50.0     # sodium reversal potential
const EK   = -77.0    # potassium reversal potential
const EL   = -54.4    # leak reversal potential

const gNaP = 0.5      # max persistent-sodium conductance (Golomb–Amitai 1997 range)
const ECa  = 120.0    # calcium reversal potential
const Iapp = 10.0     # uA/cm^2 : drives repetitive spiking

# -----------------------------------------------------------------------------
#  Gating kinetics (verbatim from the narrative model).  alpha_m / alpha_n carry
#  a removable 0/0 singularity; we return the analytic L'Hopital limit there.
# -----------------------------------------------------------------------------
function alpha_m(V)
    a = V + 40.0
    return abs(a) < 1e-6 ? 1.0 : 0.1 * a / (1.0 - exp(-a / 10.0))
end
beta_m(V) = 4.0 * exp(-(V + 65.0) / 18.0)

alpha_h(V) = 0.07 * exp(-(V + 65.0) / 20.0)
beta_h(V)  = 1.0 / (exp(-(V + 35.0) / 10.0) + 1.0)

function alpha_n(V)
    a = V + 55.0
    return abs(a) < 1e-6 ? 0.1 : 0.01 * a / (1.0 - exp(-a / 10.0))
end
beta_n(V) = 0.125 * exp(-(V + 65.0) / 80.0)

p_inf(V) = 1.0 / (1.0 + exp(-(V + 50.0) / 6.0))   # persistent-Na, V½ ~ -50 mV (Magistretti–Alonso 1999)
const tau_p = 1.0
alpha_p(V) = p_inf(V) / tau_p
beta_p(V)  = (1.0 - p_inf(V)) / tau_p

s_inf(V) = 1.0 / (1.0 + exp(-(V + 25.0) / 9.0))   # high-threshold Ca, V½ ~ -25 mV slope ~9 (Reuveni 1993)
const tau_s = 5.0
alpha_s(V) = s_inf(V) / tau_s
beta_s(V)  = (1.0 - s_inf(V)) / tau_s

# -----------------------------------------------------------------------------
#  Time grid + normalisation scale (fixed across all experiments).
# -----------------------------------------------------------------------------
const TSPAN_FULL = (0.0, 100.0)
const DATASIZE   = 512
const TSTEPS     = range(TSPAN_FULL[1], TSPAN_FULL[2]; length = DATASIZE)
const SCALE      = [100.0, 1.0, 1.0, 1.0, 1.0, 1.0]   # divide V by 100 (Neural ODE)

# OU noise process parameters (paper §3.5; never swept — only the level is).
const OU_THETA = 5.0
const OU_SIGMA = 0.5

# -----------------------------------------------------------------------------
#  Rest-state initial condition: V0 + gates at their voltage-clamped steady states.
# -----------------------------------------------------------------------------
const V0 = -65.0
xinf(a, b) = a / (a + b)
steady_state_u0() = [V0,
                     xinf(alpha_m(V0), beta_m(V0)),
                     xinf(alpha_h(V0), beta_h(V0)),
                     xinf(alpha_n(V0), beta_n(V0)),
                     xinf(alpha_p(V0), beta_p(V0)),
                     xinf(alpha_s(V0), beta_s(V0))]

# -----------------------------------------------------------------------------
#  make_hh_advanced(gCa) -> closure (du,u,p,t).
#  Identical dynamics to the narrative `hh_advanced!`, but gCa is captured as a
#  local so the RHS reads no mutable global.  State u = [V, m, h, n, p, s].
# -----------------------------------------------------------------------------
function make_hh_advanced(gCa::Float64)
    return function (du, u, _params, _t)
        V, m, h, n, p, s = u

        I_K   = gK   * n^4    * (V - EK)
        I_Na  = gNa  * m^3 * h * (V - ENa)
        I_L   = gL            * (V - EL)
        I_NaP = gNaP * p      * (V - ENa)
        I_Ca  = gCa  * s^2    * (V - ECa)

        du[1] = (Iapp - I_K - I_Na - I_L - I_NaP - I_Ca) / Cm
        du[2] = alpha_m(V) * (1.0 - m) - beta_m(V) * m
        du[3] = alpha_h(V) * (1.0 - h) - beta_h(V) * h
        du[4] = alpha_n(V) * (1.0 - n) - beta_n(V) * n
        du[5] = alpha_p(V) * (1.0 - p) - beta_p(V) * p
        du[6] = alpha_s(V) * (1.0 - s) - beta_s(V) * s
        return nothing
    end
end

# -----------------------------------------------------------------------------
#  gen_clean_data(gCa) -> (; data_clean, tsteps)
#  Solve the TRUE advanced-HH model exactly over the full 100 ms window.
# -----------------------------------------------------------------------------
function gen_clean_data(gCa::Float64)
    prob = ODEProblem(make_hh_advanced(gCa), steady_state_u0(), TSPAN_FULL)
    sol  = solve(prob, Tsit5(); saveat = TSTEPS, abstol = 1e-8, reltol = 1e-8)
    return (; data_clean = Array(sol), tsteps = TSTEPS)
end

# -----------------------------------------------------------------------------
#  ou_noise: one Ornstein–Uhlenbeck path per channel (paper §3.5).
#       xi_{k+1} = xi_k - theta*xi_k*dt + sigma*sqrt(dt)*N(0,1)
# -----------------------------------------------------------------------------
function ou_noise(rng, nrows, ncols, dt; theta = OU_THETA, sigma = OU_SIGMA)
    xi = zeros(nrows, ncols)
    for i in 1:nrows
        x = 0.0
        for k in 1:ncols
            x += -theta * x * dt + sigma * sqrt(dt) * randn(rng)
            xi[i, k] = x
        end
    end
    return xi
end

# -----------------------------------------------------------------------------
#  gen_noisy_data(data_clean, noise_level; seed) -> Matrix
#  Add per-channel, unit-std-normalised OU noise scaled to `noise_level` of each
#  channel's std.  Deterministic in `seed` (fresh StableRNG): seed=1111,
#  noise_level=0.02 reproduces the narrative Section-3 `data_noisy` exactly.
# -----------------------------------------------------------------------------
function gen_noisy_data(data_clean::AbstractMatrix, noise_level::Float64; seed::Int = 1111)
    rng = StableRNG(seed)
    dt  = step(TSTEPS)
    ou  = ou_noise(rng, size(data_clean, 1), size(data_clean, 2), dt)
    ou ./= std(ou, dims = 2)                       # unit std per channel
    return data_clean .+ noise_level .* std(data_clean, dims = 2) .* ou
end

# -----------------------------------------------------------------------------
#  make_split(t_train_end) -> (; train_idx, forecast_idx, tspan_train, tsteps_train)
#  Indices into TSTEPS for the training window (t <= t_train_end) and the
#  forecasting window (t > t_train_end).
# -----------------------------------------------------------------------------
function make_split(t_train_end::Float64)
    train_idx    = findall(t -> t <= t_train_end, TSTEPS)
    forecast_idx = findall(t -> t  > t_train_end, TSTEPS)
    return (; train_idx,
              forecast_idx,
              tspan_train  = (0.0, t_train_end),
              tsteps_train = TSTEPS[train_idx])
end
