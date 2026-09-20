# N22 — the post-submission experiment round (E1, E2, E3) and what it does to the paper

**Supersedes nothing. `draft-email-N21-prathamesh.md` was the pre-submission reply and is
history; this is the first note to him since the paper went in on 30 Aug.**

**WHEN TO SEND: between 23 and 28 Sep 2026.** Not before — his two reciprocal Sim2Science
reviews are due 23 Sep and he should not be reading this while writing those. Not after the
29 Sep notification either, and that is the part that matters: **if the paper is accepted, the
camera-ready must fix two claims these results contradict, the body has ZERO margin, and we do
not even know how long the camera-ready window is** (it is not in the CFP notes we kept — see
T21). A co-author meeting three new experiments for the first time inside that window is the
risk this email exists to remove.

**Before sending:**
1. **Re-read it against the artifact.** This project's own lesson: a draft written before the
   work and reconciled once is stale the next time the work moves. Every number below is in
   `results_noiseweighted/paper_macros_e1e3.csv`; check them against it, not against memory.
2. **Do not attach a PDF.** Nobody here can compile (Overleaf 403s), so we cannot claim a page
   count or show him a rendered §4.8. Point him at the source and the HANDOFF box instead.
3. If he has already sent his internal tool's feedback by the time you send this, drop the
   last paragraph's request for it.
4. Plain prose on purpose: no headers, no bullet lists, one indented number block. A note
   telling a co-author that a submitted claim is wrong should not arrive laid out as a status
   report.

---

Hi Prathamesh,

Quick but important update on the experiments, and I want to lead with the part that affects
the submitted paper rather than bury it.

We ran the seed count up on the noise-weighting experiment and then two follow-ups, and the
decomposition in our submitted paper does not survive the larger sample. The paper says the
objective is the larger share of the gap between the parametric fit and the closure, and that
the representation accounts for at most a further factor of two. At 28 seeds the two causes
are comparable and that bound is exceeded. The direction helps us — the representation, which
is the paper's thesis, comes out as a bigger effect, not a smaller one — so this is not a
retraction of anything. But two sentences in the submission are now wrong, and I would rather
you heard it from me in September than from a reviewer.

What we did, and all three self-test against the published numbers before they are allowed to
report anything. First, both arms of the noise-weighting comparison at 28 paired seeds instead
of five. Second, the same two-parameter fit refitted with the closure's own optimiser, to take
the optimiser out of the comparison. Third, a crossed grid that separates the network
initialisation from the noise draw, which the paper has always had to report jointly.

    recovered gCa, 28 seeds, true value 2.0
      closure, unweighted loss     1.543 +- 1.237     rel. spread 0.802   (0.408 at five seeds)
      closure, noise-weighted      1.925 +- 0.605     rel. spread 0.314
      direct fit, noise-weighted   1.966 +- 0.132     rel. spread 0.067
      direct fit, unweighted       1.970 +- 0.523     rel. spread 0.265

Three things came out of that. The five seeds we published were a kind draw: the closure's
spread nearly doubles with more seeds, and three of the 28 recover a negative conductance,
which is not a wide estimate but an impossible one. Training against the noise-weighted
likelihood instead of the unweighted sum of squares genuinely recovers the conductance
(F(27,27) = 4.18, p = 0.0002) and costs nothing in forecasting. And with all four combinations
of estimator and objective measured on the same seeds, the objective inflates the direct fit
3.95-fold but the closure only 2.55-fold, so the arithmetic split we used no longer holds; the
representation ends up owning between 45 and 62 per cent of the gap depending on which effect
you remove first.

The crossed grid is the one I find most interesting. The initialisation contributes nothing
measurable (p = 0.75) — the closure is not finding different optima on the same data, it is at
the mercy of which noise realisation it was handed. And the noise-weighted objective helps
almost entirely by removing the interaction between initialisation and data draw, 0.209 down
to 0.031, rather than by making the closure less sensitive to the data. That is a mechanism,
not just an effect.

I have already written this into the archival as a new results section and corrected the
decomposition wherever the old split appeared, including the abstract. The submitted paper is
untouched and I have not gone near it. All our checks are green.

What I would value from you, whenever you have time and certainly not before your reviews are
done: whether you agree the framing should shift — the honest reading now is that the loss you
choose creates an interaction between initialisation and noise, the likelihood removes it, and
what remains is representation — and whether you think these results belong in a camera-ready
if we are accepted, given there is no space in the five pages without cutting something else.
If your internal tool's feedback is ready, this would be a good moment for it, since it should
shape which experiment we run next.

Thanks,
Vinayak
