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
const gCa  = 2.0      # raised above the literature value (~0.4) so the Ca current is IDENTIFIABLE for symbolic recovery (Sec 6); the small physiological gCa is not uniquely recoverable from limit-cycle data
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

s_inf(V) = 1.0 / (1.0 + exp(-(V + 25.0) / 9.0))   # high-threshold Ca, half-activation ~ -25 mV, slope ~9 mV (Reuveni 1993)
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
# Real recordings are noisy AND temporally correlated. Following the paper (§3.5) we use an
# Ornstein–Uhlenbeck process instead of white noise:
#       xi_{k+1} = xi_k - theta * xi_k * dt + sigma * sqrt(dt) * N(0,1)   (theta=5, sigma=0.5)
# Each channel's OU process is normalised to unit std, then scaled by NOISE_LEVEL * std(channel)
# so every variable gets a comparable *relative*, *correlated* perturbation.

const NOISE_LEVEL = 0.02               # 2 % relative noise (small Ca current stays recoverable)
const OU_THETA    = 5.0                # OU mean-reversion rate (paper §3.5)
const OU_SIGMA    = 0.5                # OU volatility            (paper §3.5)

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

# Re-seed so the noise is reproducible even if this block is re-run on its own.
Random.seed!(RNG, 1111)
dt_noise   = step(tsteps)                          # ms between saved samples
ou         = ou_noise(RNG, size(data_clean, 1), size(data_clean, 2), dt_noise)
ou       ./= std(ou, dims = 2)                     # unit std per channel
data_noisy = data_clean .+ NOISE_LEVEL .* std(data_clean, dims = 2) .* ou

# --- Figure 1: ground-truth voltage + the noisy "measured" data --------------
fig1 = plot(tsteps, data_clean[1, :], lw = 2, color = "#185FA5",
            label = "V (truth)", xlabel = "t (ms)", ylabel = "V (mV)",
            title = "Advanced HH : true dynamics + noisy data", legend = :topright)
scatter!(fig1, tsteps, data_noisy[1, :], ms = 1.6, alpha = 0.4,
         label = "V (noisy data)", color = :red)

# --- Train / forecast split --------------------------------------------------
# We train on the first part of the trajectory and FORECAST the remainder, so
# the model is always asked to extrapolate into unseen time (Objective 1).
const T_TRAIN_END = 30.0
const train_idx   = findall(t -> t <= T_TRAIN_END, tsteps)   # indices used for training
tspan_train       = (0.0, T_TRAIN_END)
tsteps_train      = tsteps[train_idx]



# =============================================================================
#   Save Figures
# =============================================================================

# Set the explicit output directory using a raw string to handle Windows backslashes
output_dir = raw"D:\SciML\bootcamp\Research Project\HH-SciML-Project\figures"

# Create the directory if it doesn't already exist
mkpath(output_dir)

# Save the six single-variable figures
savefig(fig_V, joinpath(output_dir, "01_Membrane_Potential.png"))
savefig(fig_m, joinpath(output_dir, "02_Na_activation_m.png"))
savefig(fig_h, joinpath(output_dir, "03_Na_inactivation_h.png"))
savefig(fig_n, joinpath(output_dir, "04_K_activation_n.png"))
savefig(fig_p, joinpath(output_dir, "05_Persistent_Na_p.png"))
savefig(fig_s, joinpath(output_dir, "06_Calcium_s.png"))

# Save the stacked overview figure
savefig(fig_overview, joinpath(output_dir, "07_Stacked_Overview.png"))

# Save the ground-truth vs noisy data figure
savefig(fig1, joinpath(output_dir, "08_Noisy_Data_Comparison.png"))

println("All figures successfully saved to: ", output_dir)



# =============================================================================
#  SECTION 4 — Neural ODE  (Objective 1 / Action Item 3)
#  Replace the ENTIRE right-hand side with a neural network:  du/dt = NN(u).
# =============================================================================
#
#  V ranges over roughly [-80, +40] mV while the gates live in [0, 1].  Feeding
#  such different scales to a network hurts training, so we work in NORMALISED
#  coordinates  u_n = u ./ scale  (and de-normalise only for plotting).
# -----------------------------------------------------------------------------
const scale   = [100.0, 1.0, 1.0, 1.0, 1.0, 1.0]   # divide V by 100, leave gates as-is
norm_noisy    = data_noisy ./ scale                # only the noisy data feeds the loss
u0_n          = u0 ./ scale

# Network architecture follows the paper (§3.3):
#   * TIME t is an explicit input -> 7 inputs (6 states + t): lets the model learn
#     non-autonomous dynamics and improves extrapolation fidelity.
#   * 3-layer MLP, 64 hidden units, tanh activations.
#   * LayerNorm after each hidden layer for training stability.
nn_node = Lux.Chain(Lux.Dense(7, 64, tanh), Lux.LayerNorm((64,)),
                    Lux.Dense(64, 64, tanh), Lux.LayerNorm((64,)),
                    Lux.Dense(64, 6))
p_node0, st_node = Lux.setup(RNG, nn_node)
p_node0 = ComponentArray{Float64}(p_node0)         # Float64 for stiff-ODE accuracy

# Right-hand side in NORMALISED coordinates, written explicitly (instead of the NeuralODE
# wrapper) so we can pass t as an input AND control the solver + adjoint, exactly like the
# UDE in Section 5.  vcat(u, t) feeds the 6 states plus the current time to the network.
function node_rhs!(du, u, p, t)
    # Lux layers (esp. LayerNorm) expect a (features, batch) matrix, so feed the 7 inputs
    # as a 7x1 column and flatten the 6x1 result back to the length-6 derivative.
    du .= vec(nn_node(reshape(vcat(u, t), :, 1), p, st_node)[1])
    return nothing
end

# Train over the TRAINING window only.  Tsit5 here: a smoke test showed it gives a gradient
# identical to Rodas5P but is far cheaper, so 3000 iters stays tractable (the stiff Rodas5P
# adjoint was too heavy on this stack).  InterpolatingAdjoint(ReverseDiffVJP) gives stable
# gradients through sharp spikes (paper §5.2: backsolve adjoint collapses).  Tight tolerances
# match the ground truth.  Note: the paper warns Tsit5 *extrapolation* can let spikes fade.
prob_node = ODEProblem(node_rhs!, u0_n, tspan_train, p_node0)

predict_node(p) = Array(solve(prob_node, Tsit5(); p = p, saveat = tsteps_train,
                              abstol = 1e-8, reltol = 1e-8, verbose = false,
                              sensealg = InterpolatingAdjoint(autojacvec = ReverseDiffVJP(true))))

function loss_node(p)
    pred = predict_node(p)
    # Guard: if the solver bailed out early the sizes differ -> return a big *finite* penalty
    # (not Inf, which makes the BFGS line search assert isfinite(phi_c) and crash).
    size(pred, 2) == length(train_idx) || return 1.0e6
    return sum(abs2, norm_noisy[:, train_idx] .- pred)
end

losses_node = Float64[]
cb_node = function (state, l)
    push!(losses_node, l)
    length(losses_node) % 50 == 0 &&
        println("    [Neural ODE] iter $(length(losses_node))  loss = $(round(l, sigdigits = 4))")
    return false
end

println("[Section 4] Training the Neural ODE ...")
adtype     = Optimization.AutoZygote()
optf_node  = Optimization.OptimizationFunction((p, _) -> loss_node(p), adtype)
optprob_n  = Optimization.OptimizationProblem(optf_node, p_node0)

# Stage 1 — Adam at lr 1e-2 for up to 3000 iters (1e-3 was too slow once gCa=2.0 makes the
# dynamics harder — same speed-up we applied to the UDE).
res_node1  = Optimization.solve(optprob_n, OptimizationOptimisers.Adam(1e-2);
                                callback = cb_node, maxiters = 3000)
# Stage 2 — BFGS: second-order polishing.  Wrapped so a line search that wanders into an
# unstable-ODE region can't crash the whole run; on failure we keep the Adam result.
p_node = res_node1.u                                   # fall back to Adam result if BFGS fails
try
    optprob_n2 = Optimization.OptimizationProblem(optf_node, res_node1.u)
    res_node   = Optimization.solve(optprob_n2, OptimizationOptimJL.BFGS(initial_stepnorm = 0.01);
                                    callback = cb_node, maxiters = 300)
    p_node = res_node.u
catch err
    @warn "BFGS polish failed; keeping Adam result." exception = err
end

# --- Prediction on the training window AND forecast over the full span --------
# Plot against the solver's OWN grid (sol.t): a vanilla Neural ODE forecast can go unstable
# and stop early, so using sol.t keeps the x/y lengths matched and fig2 always saves.
sol_node_full = solve(ODEProblem(node_rhs!, u0_n, tspan, p_node), Tsit5();   # extend to 100 ms
                      saveat = tsteps, abstol = 1e-8, reltol = 1e-8, verbose = false)
t_pred    = sol_node_full.t
pred_node = Array(sol_node_full) .* scale                                    # de-normalise

# --- Visualise the forecast for ALL 6 states (the network predicts every derivative).
#     y-axes are CLIPPED to a physical band so the training-window fit and the divergence
#     onset are visible (the black-box NODE blows up to +-1e4 in forecast, which would
#     otherwise crush the truth into a flat line).  Legends sit OUTSIDE the axes so they
#     never cover the curves.  Truth solid vs Neural ODE dashed.
node_vars = [(1, "V (mV)", "Membrane potential",   (-90.0, 50.0), "fig2_neural_ode_voltage.png"),
             (2, "m",      "Na+ activation (m)",    (-0.5, 1.5),   "fig2_neural_ode_m.png"),
             (3, "h",      "Na+ inactivation (h)",  (-0.5, 1.5),   "fig2_neural_ode_h.png"),
             (4, "n",      "K+ activation (n)",     (-0.5, 1.5),   "fig2_neural_ode_n.png"),
             (5, "p",      "Persistent Na+ (p)",    (-0.5, 1.5),   "fig2_neural_ode_p.png"),
             (6, "s",      "Calcium (s)",           (-0.5, 1.5),   "fig2_neural_ode_s.png")]

for (i, ylab, ttl, yl, fname) in node_vars
    plt = plot(tsteps, data_clean[i, :], lw = 2, label = "truth",
               xlabel = "t (ms)", ylabel = ylab, title = "Neural ODE : $ttl",
               legend = :outertopright, ylims = yl)
    plot!(plt, t_pred, pred_node[i, :], lw = 2, ls = :dash, label = "Neural ODE")
    vline!(plt, [T_TRAIN_END], lw = 2, color = :gray, ls = :dot, label = "train | forecast")
    savefig(plt, joinpath(output_dir, fname))
end

# --- Stacked overview: every panel clipped to a physical range (V to -90..50 mV, gates to
#     -0.5..1.5) so all three rows are readable; the NODE forecast visibly dives out of range
#     just past the train|forecast line.  Legends outside the axes to avoid covering data.
ov_V   = plot(tsteps, data_clean[1, :], lw = 2, label = "V truth", ylabel = "V (mV)",
              legend = :outertopright, ylims = (-90.0, 50.0))
plot!(ov_V, t_pred, pred_node[1, :], lw = 2, ls = :dash, label = "V NODE")
ov_cls = plot(ylabel = "classical gates", ylims = (-0.5, 1.5), legend = :outertopright)
ov_adv = plot(xlabel = "t (ms)", ylabel = "advanced gates", ylims = (-0.5, 1.5), legend = :outertopright)
for (i, nm, c) in [(2, "m", "#D85A30"), (3, "h", "#0F6E56"), (4, "n", "#534AB7")]
    plot!(ov_cls, tsteps, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
    plot!(ov_cls, t_pred, pred_node[i, :], lw = 2, ls = :dash, color = c, label = "$nm NODE")
end
for (i, nm, c) in [(5, "p", "#BA7517"), (6, "s", "#993556")]
    plot!(ov_adv, tsteps, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
    plot!(ov_adv, t_pred, pred_node[i, :], lw = 2, ls = :dash, color = c, label = "$nm NODE")
end
for ov in (ov_V, ov_cls, ov_adv); vline!(ov, [T_TRAIN_END], lw = 1.5, color = :gray, ls = :dot, label = ""); end
fig_node_overview = plot(ov_V, ov_cls, ov_adv, layout = (3, 1), size = (900, 800), link = :x)
savefig(fig_node_overview, joinpath(output_dir, "fig2_neural_ode_overview.png"))

println("[Section 4] Neural ODE done  ->  7 figures (V/m/h/n/p/s + overview) in $(basename(output_dir))/")
# NOTE: a full 6-D spiking trajectory is genuinely hard for a black-box Neural
# ODE (stiff, sharp spikes). It captures the trend; the UDE below — which keeps
# the known physics — is expected to be far more accurate, which is exactly the
# scientific point of the roadmap.


# =============================================================================
#  SECTION 5 — Universal Differential Equation (Objective 2)
#  Keep ALL known physics, but REPLACE only the calcium current gCa s^2 (V-ECa)
#  with a neural network  U(V, s).  Retaining the physics should give far more
#  stable forecasts than the black-box Neural ODE of Section 4.
# =============================================================================
#
#  The calcium current is an AUTONOMOUS function of state -- it depends on the
#  voltage V and the calcium gate s only, NOT on time.  So the network takes
#  (V/100, s) as input.  We deliberately do NOT feed time t here (unlike the
#  black-box Neural ODE): the missing term is physical, and adding t would let it
#  overfit the time course and would corrupt the symbolic recovery in Section 6.
# -----------------------------------------------------------------------------
adtype = Optimization.AutoZygote()        # defined here so Section 5 can run after 0-3 alone

nn_ca = Lux.Chain(Lux.Dense(2, 16, tanh),
                  Lux.Dense(16, 16, tanh),
                  Lux.Dense(16, 1))
p_ca0, st_ca = Lux.setup(RNG, nn_ca)
p_ca0 = ComponentArray{Float64}(p_ca0)

# UDE right-hand side: identical to hh_advanced! except the Ca term is the network.
function hh_ude!(du, u, theta, t)
    V, m, h, n, p, s = u

    I_K   = gK   * n^4    * (V - EK)
    I_Na  = gNa  * m^3 * h * (V - ENa)
    I_L   = gL            * (V - EL)
    I_NaP = gNaP * p      * (V - ENa)
    I_Ca  = nn_ca([V / 100.0, s], theta, st_ca)[1][1]   # <-- unknown calcium current (V, s only)

    du[1] = (Iapp - I_K - I_Na - I_L - I_NaP - I_Ca) / Cm
    du[2] = alpha_m(V) * (1.0 - m) - beta_m(V) * m
    du[3] = alpha_h(V) * (1.0 - h) - beta_h(V) * h
    du[4] = alpha_n(V) * (1.0 - n) - beta_n(V) * n
    du[5] = alpha_p(V) * (1.0 - p) - beta_p(V) * p
    du[6] = alpha_s(V) * (1.0 - s) - beta_s(V) * s
    return nothing
end

prob_ude = ODEProblem(hh_ude!, u0, tspan_train, p_ca0)

# Reverse-mode adjoint -> spike-stable gradients.  verbose=false silences the transient
# instability warnings emitted while the calcium network is still untrained.
function predict_ude(theta)
    Array(solve(prob_ude, Tsit5(); p = theta, saveat = tsteps_train,
                abstol = 1e-8, reltol = 1e-8, verbose = false,
                sensealg = InterpolatingAdjoint(autojacvec = ReverseDiffVJP(true))))
end

function loss_ude(theta)
    pred = predict_ude(theta)
    size(pred, 2) == length(train_idx) || return 1.0e6   # finite penalty (Inf crashes BFGS line search)
    return sum(abs2, data_noisy[:, train_idx] .- pred)
end

losses_ude = Float64[]
cb_ude = function (state, l)
    push!(losses_ude, l)
    length(losses_ude) % 100 == 0 &&
        println("    [UDE] iter $(length(losses_ude))  loss = $(round(l, sigdigits = 4))")
    return false
end

println("[Section 5] Training the UDE (learning the calcium current) ...")
optf_ude   = Optimization.OptimizationFunction((p, _) -> loss_ude(p), adtype)
optprob_u  = Optimization.OptimizationProblem(optf_ude, p_ca0)

# Stage 1 — Adam warm-up (5000 iters, lr 1e-2; 1e-3 was too slow now that the stronger
# gCa=2.0 leaves a large Ca current for the untrained network to ramp up to).
res_ude1   = Optimization.solve(optprob_u, OptimizationOptimisers.Adam(1e-2);
                                callback = cb_ude, maxiters = 5000)
# Stage 2 — BFGS polish, wrapped so a bad line-search step can't crash the run.
p_ca = res_ude1.u                                      # fall back to Adam result if BFGS fails
try
    optprob_u2 = Optimization.OptimizationProblem(optf_ude, res_ude1.u)
    res_ude    = Optimization.solve(optprob_u2, OptimizationOptimJL.BFGS(initial_stepnorm = 0.01);
                                    callback = cb_ude, maxiters = 300)
    p_ca = res_ude.u
catch err
    @warn "UDE BFGS polish failed; keeping Adam result." exception = err
end

# --- UDE prediction + forecast over the full 100 ms (plot against sol.t for robustness) ---
sol_ude_full = solve(ODEProblem(hh_ude!, u0, tspan, p_ca), Tsit5();
                     saveat = tsteps, abstol = 1e-8, reltol = 1e-8, verbose = false)
t_ude    = sol_ude_full.t
pred_ude = Array(sol_ude_full)

# --- Visualise all 6 states (the UDE keeps the physics, so truth & prediction should overlap)
ude_vars = [(1, "V (mV)", "Membrane potential",   (-90.0, 50.0), "fig3_ude_voltage.png"),
            (2, "m",      "Na+ activation (m)",    (-0.5, 1.5),   "fig3_ude_m.png"),
            (3, "h",      "Na+ inactivation (h)",  (-0.5, 1.5),   "fig3_ude_h.png"),
            (4, "n",      "K+ activation (n)",     (-0.5, 1.5),   "fig3_ude_n.png"),
            (5, "p",      "Persistent Na+ (p)",    (-0.5, 1.5),   "fig3_ude_p.png"),
            (6, "s",      "Calcium (s)",           (-0.5, 1.5),   "fig3_ude_s.png")]

for (i, ylab, ttl, yl, fname) in ude_vars
    plt = plot(tsteps, data_clean[i, :], lw = 2, label = "truth",
               xlabel = "t (ms)", ylabel = ylab, title = "UDE : $ttl",
               legend = :outertopright, ylims = yl)
    plot!(plt, t_ude, pred_ude[i, :], lw = 2, ls = :dash, label = "UDE")
    vline!(plt, [T_TRAIN_END], lw = 2, color = :gray, ls = :dot, label = "train | forecast")
    savefig(plt, joinpath(output_dir, fname))
end

# --- Stacked overview, same style as Section 4 (clipped panels, outside legends).
ov_V   = plot(tsteps, data_clean[1, :], lw = 2, label = "V truth", ylabel = "V (mV)",
              legend = :outertopright, ylims = (-90.0, 50.0))
plot!(ov_V, t_ude, pred_ude[1, :], lw = 2, ls = :dash, label = "V UDE")
ov_cls = plot(ylabel = "classical gates", ylims = (-0.5, 1.5), legend = :outertopright)
ov_adv = plot(xlabel = "t (ms)", ylabel = "advanced gates", ylims = (-0.5, 1.5), legend = :outertopright)
for (i, nm, c) in [(2, "m", "#D85A30"), (3, "h", "#0F6E56"), (4, "n", "#534AB7")]
    plot!(ov_cls, tsteps, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
    plot!(ov_cls, t_ude, pred_ude[i, :], lw = 2, ls = :dash, color = c, label = "$nm UDE")
end
for (i, nm, c) in [(5, "p", "#BA7517"), (6, "s", "#993556")]
    plot!(ov_adv, tsteps, data_clean[i, :], lw = 2, color = c, label = "$nm truth")
    plot!(ov_adv, t_ude, pred_ude[i, :], lw = 2, ls = :dash, color = c, label = "$nm UDE")
end
for ov in (ov_V, ov_cls, ov_adv); vline!(ov, [T_TRAIN_END], lw = 1.5, color = :gray, ls = :dot, label = ""); end
fig_ude_overview = plot(ov_V, ov_cls, ov_adv, layout = (3, 1), size = (900, 800), link = :x)
savefig(fig_ude_overview, joinpath(output_dir, "fig3_ude_overview.png"))

println("[Section 5] UDE done  ->  7 figures (V/m/h/n/p/s + overview) in $(basename(output_dir))/")
