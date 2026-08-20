# Draft email to Prathamesh, to send with the corrected PDF

Status: DRAFT, not sent. Written 2026-08-21. Attach the compiled PDF built from the
current source (see HANDOFF, T1 — read it yourself first).

Two things to check before sending:
- The three corrections below are the ones that change what he was previously told.
  Do not soften them; the third one lowers a headline he was given.
- If you have decided on Sim2Science by the time you send this, say so in the last
  paragraph instead of asking.

---

**Subject:** Updated HH × SciML draft — three corrections to what I sent on 18 Aug

Hi Prathamesh,

Attached is the current draft. Every point from your August review is addressed, and I
have re-checked each one against the repository rather than assuming it survived the
rewrites since.

Since my last email the paper has been through an adversarial audit and a round of
corrections, and **three things I told you have changed**. I want to flag them
explicitly rather than let you find them in the PDF.

**1. The profile-likelihood interval moved, and one count with it.**
I quoted [1.63, 2.13]. That was the outermost points of the scan grid that fell under
the χ² threshold, and the grid step is 0.0625 — coarse enough to matter. Interpolating
the threshold crossings gives **[1.6065, 2.1477]**, which an independent Wald interval
corroborates at [1.6049, 2.1492]. As a result, "all five closure estimates fall outside
the interval" is now **four of five**: seed 3333, at 1.6069, sits just inside the
resolved interval. The figure and the text now agree on this, and the plotting script
computes the interval the same way rather than reading grid bounds.

I should also have said at the time that the interval belongs to the representative seed
alone, and that this seed's estimate is the lowest of the five. For the ensemble the
right number to quote is 2.092 ± 0.130.

**2. The parametric-vs-closure gap is smaller than I claimed, because the two arms were
not minimising the same thing.**
This is the substantive one. I presented the gap between the parametric fit (about 6%
relative spread) and the closure (about 41%) as an effect of the *representation*. But
the parametric fit minimises a noise-weighted χ², while the UDE minimises an unweighted
sum of squares that is 99.97% voltage by construction. Objective, optimiser and
representation were all changing at once.

I have now run the control: the same two-parameter fit, same data, same true functional
form, same starting points, same solver — changing only which residual is minimised. Under
the UDE's own objective it gives **2.48 ± 0.49**, a spread of about 20% rather than 6%.

So the decomposition is roughly **3.2× objective and 2.1× representation**, not a single
sixfold representation effect. The paper now claims about twofold for the representation
and says so wherever the two arms are compared. The direction of the conclusion is
unchanged and the one-directional inference still holds — the data do pin the conductance,
so the closure's scatter cannot be blamed on the data — but the magnitude I gave you was
too generous to my own argument.

**3. The aggressive-retrain control now has a reference point, and it reads as
over-fitting.**
The training loss falls from 35.71 ± 1.81 to 29.66 ± 2.66. What was missing was anything
to compare that against. Evaluating the same objective at the maximum-likelihood
two-parameter fit of the true structure gives **39.33 ± 1.26** — both UDE losses are
*below* what the correct physics achieves on the same noisy data. And inside the training
window, error against the clean trajectory rises from 0.148 ± 0.045 to 0.243 ± 0.054 mV
while the objective falls. So the extra optimisation is fitting the noise realisation
rather than travelling along a harmless flat direction. I have stated plainly that there
is no validation split or early-stopping criterion anywhere in the protocol.

**Smaller corrections in the same pass**, none of which change a conclusion: the schematic
said the model was solved over the full 100 ms window when training uses 30 ms; the text
said "six gate ODEs" where there are five; ten references to "L-BFGS" were wrong (the code
runs full BFGS); a claim about the closure's agreement with the conductance form was
supported by the wrong column (agreement with the true current rather than with the
closure — the right one is now reported, 0.985 ± 0.009 on the supervised trajectory and
0.936 ± 0.075 on the hull); the rollout horizon was reporting a 70 ms cap inside a 49.9 ms
window; and several citations were carrying attributions the cited papers do not support,
including the g_Ca–E_Ca trade-off, which I had credited to Walch & Eisenberg — their result
is a conductance × gating combination under voltage clamp, which is a different statement.

Everything reported is traceable to a committed CSV, and the code and data are now
licensed (MIT for the software, CC BY 4.0 for the results and figures).

Two things I would still value your view on:

- **Is the reversed thesis the right thing to lead with?** Parametric identifiability holds
  while functional identifiability fails — the data determine the conductance and the
  flexible closure loses it. It is counter-intuitive, and I would rather hear now than from
  a reviewer if you think it should be framed differently.
- **Venue.** I am looking at Sim2Science and have not yet checked its page limit or whether
  it is double-blind. If you have a stronger suggestion I am open to it.

Thanks again for the review — the parametric fit you asked for turned out to be the thing
the whole argument now rests on.

Best,
Vinayak
