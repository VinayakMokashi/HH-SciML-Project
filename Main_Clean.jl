#  UNITS (standard squid-axon convention, resting potential ~ -65 mV)
#        V  : mV          t : ms          C : uF/cm^2
#        g  : mS/cm^2     I : uA/cm^2     E : mV

# -----------------------------------------------------------------------------
#  SECTION 0 — Packages
# -----------------------------------------------------------------------------
using DifferentialEquations
using Lux, ComponentArrays
using DiffEqFlux
using Optimization
using OptimizationOptimisers
using OptimizationOptimJL
using SciMLSensitivity
using Zygote
using DataDrivenDiffEq, DataDrivenSparse
using ModelingToolkit: @variables
using LinearAlgebra, Statistics
using StableRNGs
using Random
using Plots

gr()                                     # GR plotting backend

# One RNG, fixed seed -> every run (data noise + NN init) is reproducible.
const RNG = StableRNG(1111)




# =============================================================================
#  SECTION 1 — Biophysical parameters & gating kinetics
# =============================================================================
#
#  Classical HH (PDF):
#     Cm dV/dt = I - gK n^4 (V-EK) - gNa m^3 h (V-ENa) - gL (V-EL)
#
#  Advanced HH (adds two currents):
#     I_NaP = gNaP p   (V - ENa)      (persistent sodium)
#     I_Ca  = gCa  s^2 (V - ECa)      (calcium)  
# -----------------------------------------------------------------------------

# --- Membrane capacitance, maximal conductances & reversal potentials --------
const Cm   = 1.0      # membrane capacitance
const gNa  = 120.0    # max sodium conductance              ENa below
const gK   = 36.0     # max potassium conductance           EK below
const gL   = 0.3      # leak conductance                    EL below
const ENa  = 50.0     # sodium reversal potential
const EK   = -77.0    # potassium reversal potential
const EL   = -54.4    # leak reversal potential

# --- Extra (advanced-model) currents -----------------------------------------
const gNaP = 0.5      # max persistent-sodium conductance
const gCa  = 1.0      # max calcium conductance
const ECa  = 120.0    # calcium reversal potential (Ca is far from rest -> strong driving force)

# --- Constant injected stimulus current --------------------------------------
const Iapp = 10.0     # uA/cm^2 : large enough to drive *repetitive* spiking

# -----------------------------------------------------------------------------
#  Voltage-dependent rate constants for the CLASSICAL gates m, h, n.
#
#  alpha_m and alpha_n contain a *removable* 0/0 singularity (at V = -40 and
#  V = -55 respectively, where numerator and denominator vanish together).
#  We return the analytic limit there (L'Hopital) so the integrator and the
#  automatic-differentiation pass never evaluate 0/0.
# -----------------------------------------------------------------------------
function alpha_m(V)
    a = V + 40.0
    return abs(a) < 1e-6 ? 1.0 : 0.1 * a / (1.0 - exp(-a / 10.0))   # limit -> 1.0
end
beta_m(V) = 4.0 * exp(-(V + 65.0) / 18.0)

alpha_h(V) = 0.07 * exp(-(V + 65.0) / 20.0)
beta_h(V)  = 1.0 / (exp(-(V + 35.0) / 10.0) + 1.0)

function alpha_n(V)
    a = V + 55.0
    return abs(a) < 1e-6 ? 0.1 : 0.01 * a / (1.0 - exp(-a / 10.0))  # limit -> 0.1
end
beta_n(V) = 0.125 * exp(-(V + 65.0) / 80.0)

# -----------------------------------------------------------------------------
#  Rate constants for the EXTRA gates p (persistent Na+) and s (Ca2+).
#
# We adopt the standard, well
#  behaved choice: a sigmoidal steady-state activation x_inf(V) together with a
#  (here constant) time constant tau_x, then convert to the alpha/beta form via
#       alpha = x_inf / tau ,     beta = (1 - x_inf) / tau
#  so that the gating ODE reduces to   dx/dt = (x_inf - x) / tau.
# -----------------------------------------------------------------------------
p_inf(V) = 1.0 / (1.0 + exp(-(V + 50.0) / 6.0))   # persistent-Na, half-activation ~ -50 mV
const tau_p = 1.0                                  # ms (fast)
alpha_p(V) = p_inf(V) / tau_p
beta_p(V)  = (1.0 - p_inf(V)) / tau_p

s_inf(V) = 1.0 / (1.0 + exp(-(V + 25.0) / 5.0))   # high-threshold Ca, half-activation ~ -25 mV
const tau_s = 5.0                                  # ms
alpha_s(V) = s_inf(V) / tau_s
beta_s(V)  = (1.0 - s_inf(V)) / tau_s





# =============================================================================
#  SECTION 2 — The advanced HH ODE  (Action Item 1: "implement & run the ODE")
#  State vector  u = [V, m, h, n, p, s]
# =============================================================================
function hh_advanced!(du, u, params, t)
    V, m, h, n, p, s = u

    # --- Ionic currents -------------------------------------------------------
    I_K   = gK   * n^4    * (V - EK)     # delayed-rectifier potassium
    I_Na  = gNa  * m^3 * h * (V - ENa)   # transient sodium
    I_L   = gL            * (V - EL)     # passive leak
    I_NaP = gNaP * p      * (V - ENa)    # persistent sodium  (advanced model)
    I_Ca  = gCa  * s^2    * (V - ECa)    # calcium            (advanced model) 

    # --- Membrane potential ---------------------------------------------------
    du[1] = (Iapp - I_K - I_Na - I_L - I_NaP - I_Ca) / Cm

    # --- Gating variables (first-order kinetics dx/dt = a(1-x) - b x) ---------
    du[2] = alpha_m(V) * (1.0 - m) - beta_m(V) * m
    du[3] = alpha_h(V) * (1.0 - h) - beta_h(V) * h
    du[4] = alpha_n(V) * (1.0 - n) - beta_n(V) * n
    du[5] = alpha_p(V) * (1.0 - p) - beta_p(V) * p
    du[6] = alpha_s(V) * (1.0 - s) - beta_s(V) * s
    return nothing
end

# --- Initial condition: rest potential, gates at their steady states ---------
const V0 = -65.0
xinf(a, b) = a / (a + b)               # steady state of a first-order gate
u0 = [V0,
      xinf(alpha_m(V0), beta_m(V0)),
      xinf(alpha_h(V0), beta_h(V0)),
      xinf(alpha_n(V0), beta_n(V0)),
      xinf(alpha_p(V0), beta_p(V0)),
      xinf(alpha_s(V0), beta_s(V0))]

# --- Time grid ---------------------------------------------------------------
const tspan    = (0.0, 100.0)                       # 100 ms window
const datasize = 512                               # number of saved samples
const tsteps   = range(tspan[1], tspan[2]; length = datasize)

# --- Solve the true model ----------------------------------------------------
println("[Section 2] Solving the advanced HH ODE ...")
prob_true  = ODEProblem(hh_advanced!, u0, tspan)
sol_true   = solve(prob_true, Tsit5(); saveat = tsteps, abstol = 1e-8, reltol = 1e-8)
data_clean = Array(sol_true)                       # 6 x datasize  (the ground truth)

# --- Unpack the ground-truth trajectory ------------------------------------
V = data_clean[1, :]
m = data_clean[2, :]
h = data_clean[3, :]
n = data_clean[4, :]
p = data_clean[5, :]
s = data_clean[6, :]

# === Six single-variable figures ===========================================
fig_V = plot(tsteps, V, lw = 2, color = "#185FA5", legend = false,
             xlabel = "t (ms)", ylabel = "V (mV)", title = "Membrane potential")

fig_m = plot(tsteps, m, lw = 2, color = "#D85A30", legend = false,
             xlabel = "t (ms)", ylabel = "m", ylims = (0, 1), title = "Na⁺ activation (m)")

fig_h = plot(tsteps, h, lw = 2, color = "#0F6E56", legend = false,
             xlabel = "t (ms)", ylabel = "h", ylims = (0, 1), title = "Na⁺ inactivation (h)")

fig_n = plot(tsteps, n, lw = 2, color = "#534AB7", legend = false,
             xlabel = "t (ms)", ylabel = "n", ylims = (0, 1), title = "K⁺ activation (n)")

fig_p = plot(tsteps, p, lw = 2, color = "#BA7517", legend = false,
             xlabel = "t (ms)", ylabel = "p", ylims = (0, 1), title = "Persistent Na⁺ (p)")

fig_s = plot(tsteps, s, lw = 2, color = "#993556", legend = false,
             xlabel = "t (ms)", ylabel = "s", ylims = (0, 1), title = "Calcium (s)")

# === Seventh figure: the stacked overview ==================================
ov_V = plot(tsteps, V, lw = 2, color = "#185FA5", label = "V", ylabel = "V (mV)")
hline!(ov_V, [0.0], lw = 0.7, ls = :dash, color = :gray, label = "")

ov_cls = plot(tsteps, m, lw = 2, color = "#D85A30", label = "m")
plot!(ov_cls, tsteps, h, lw = 2, color = "#0F6E56", label = "h")
plot!(ov_cls, tsteps, n, lw = 2, color = "#534AB7", label = "n")
plot!(ov_cls, ylabel = "classical", ylims = (0, 1), legend = :topright)

ov_adv = plot(tsteps, p, lw = 2, color = "#BA7517", label = "p")
plot!(ov_adv, tsteps, s, lw = 2, color = "#993556", label = "s")
plot!(ov_adv, xlabel = "t (ms)", ylabel = "advanced", ylims = (0, 1), legend = :topright)

fig_overview = plot(ov_V, ov_cls, ov_adv, layout = (3, 1), size = (900, 800), link = :x)

# --- Display all seven ------------------------------------------------------
display(fig_V); display(fig_m); display(fig_h)
display(fig_n); display(fig_p); display(fig_s)
display(fig_overview)




# =============================================================================
#  SECTION 3 — Generate noisy data  (Action Item 2: "add noise for realism")
# =============================================================================
# Real recordings are noisy. We add zero-mean Gaussian noise scaled, per state
# variable, by that variable's own standard deviation, so every channel gets a
# comparable *relative* perturbation.

const NOISE_LEVEL = 0.05               # 5 % relative noise

# Re-seed so the noise is reproducible even if this block is re-run on its own.
Random.seed!(RNG, 1111)
data_noisy = data_clean .+ NOISE_LEVEL .* std(data_clean, dims = 2) .* randn(RNG, size(data_clean))

# --- Figure 1: ground-truth voltage + the noisy "measured" data --------------
fig1 = plot(tsteps, data_clean[1, :], lw = 2, color = "#185FA5",
            label = "V (truth)", xlabel = "t (ms)", ylabel = "V (mV)",
            title = "Advanced HH : true dynamics + noisy data", legend = :topright)
scatter!(fig1, tsteps, data_noisy[1, :], ms = 1.6, alpha = 0.4,
         label = "V (noisy data)", color = :red)

# --- Train / forecast split --------------------------------------------------
# We train on the first part of the trajectory and FORECAST the remainder, so
# the model is always asked to extrapolate into unseen time (Objective 1).
const T_TRAIN_END = 45.0
const train_idx   = findall(t -> t <= T_TRAIN_END, tsteps)   # indices used for training
tspan_train       = (0.0, T_TRAIN_END)
tsteps_train      = tsteps[train_idx]



# =============================================================================
#   Save Figures
# =============================================================================

# println("[Section 4] Saving figures to disk...")

# # Set the explicit output directory using a raw string to handle Windows backslashes
# output_dir = raw"D:\SciML\bootcamp\Research Project\HH-SciML-Project\Figures_Section_0_to_2"

# # Create the directory if it doesn't already exist
# mkpath(output_dir)

# # Save the six single-variable figures
# savefig(fig_V, joinpath(output_dir, "01_Membrane_Potential.png"))
# savefig(fig_m, joinpath(output_dir, "02_Na_activation_m.png"))
# savefig(fig_h, joinpath(output_dir, "03_Na_inactivation_h.png"))
# savefig(fig_n, joinpath(output_dir, "04_K_activation_n.png"))
# savefig(fig_p, joinpath(output_dir, "05_Persistent_Na_p.png"))
# savefig(fig_s, joinpath(output_dir, "06_Calcium_s.png"))

# # Save the stacked overview figure
# savefig(fig_overview, joinpath(output_dir, "07_Stacked_Overview.png"))

# # Save the ground-truth vs noisy data figure
# savefig(fig1, joinpath(output_dir, "08_Noisy_Data_Comparison.png"))

# println("All figures successfully saved to: ", output_dir)




