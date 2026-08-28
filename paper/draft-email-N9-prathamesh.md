# N20 — draft reply to Prathamesh after mentor review 2

Status: DRAFT, not sent. Rewritten 2026-08-28 after his two review emails (HANDOFF §4n),
then reconciled against the executed work later the same day: N13-N17 are now DONE, so every
claim below has been checked against the file rather than against the plan.

*(Filename is historical -- it began as the N9 cold-send draft. The content is N20.)*

**This replaces the earlier N9 draft entirely.** That one sent the 5-page draft cold and
warned him about three things he would otherwise discover. He has now read it and replied,
so the cold-send framing is dead, and two of its three warnings are obsolete: the
"supplementary carries the forecast plot" defence no longer exists (there is no supplementary
upload), and the table-caption point he has independently confirmed.

**Send this when N13–N17 are done, with the revised PDF attached — ONE pdf now, not two.**

**Before sending:**
1. The revised `main.pdf` must be attached and must already contain the Stage-1 figure and
   the appendix. Do not send this promising work that is not in the file.
2. The compute paragraph states the per-run number as *measured from file timestamps*. Keep
   that framing — it is the honest version and it is what makes the claim defensible.
3. If Raj's ID arrives before you send, delete ask 1.
4. **The length question is CLOSED and must not be re-litigated by eye.** Measured on the
   2026-08-28 compile: the body ends at the foot of page 5 and the References head sits at
   the TOP of page 6, which is the target state (the CFP excludes references, checklist and
   appendix from the five pages). Every round-11 and round-12 fix landed in the appendix,
   the checklist or this email — **lines 1-770 of `paper/sim2science/main.tex`, which is the
   preamble, the abstract and all of Secs 1-5, are byte-for-byte the version that was
   measured on 28 Aug.** Verified with `diff`, not by eye. **Recompile
   anyway before attaching, and confirm the References head still opens page 6.** If it has
   moved, turn the first dial in the LENGTH DIAL block at the top of
   `paper/sim2science/main.tex` before sending, not after.

---

**Subject:** Sim2Science revisions done — and I need Raj's OpenReview ID

Hi Prathamesh,

Thank you — that was exactly the review I needed. I have worked through all of it and the
revised draft is attached. Two things I need from you first, then what changed.

**What I need**

1. **Raj's OpenReview profile ID**, or the email his profile uses. I am adding him as a
   co-author. Yours resolves correctly on the form. OpenReview refuses any author without a
   profile, so this is the one outstanding thing that would stop me pressing Submit.
2. **Something you should know before I nominate you**, because it was not visible when you
   offered: the CFP says **each nominated reviewer is assigned two other submissions to
   review**. You volunteered before that number was on the table, so tell me if it changes
   anything and I will nominate myself instead.

**On the deadline:** the CFP has moved it to **2 September, 23:59 AoE**. The OpenReview form
still showed 30 August when I last looked, so I am working to the earlier date until the form
catches up.

**What changed**

You were right about the supplementary — I checked the form and there is a single PDF field
and nothing else. The appendix now lives inside the main paper. One piece of good news: the
CFP puts **no page limit on the appendix**, only on the five-page body, so I was not fighting
for room. I kept it tight regardless, as you suggested.

**The Stage-1 figure is in**, and it is the first figure in the Results section. You were
right that a reader never saw prediction succeed before being shown interpretation fail,
which is a real gap in a paper called *Predict, then interpret*. It is two panels on shared
axes and the same seed: the black-box neural ODE against the truth on the left, the UDE
against the truth on the right. I also took the second lever you offered and **shrank the old
Figure 1** rather than dropping anything, so the identifiability figure is still there, just
smaller, and no control had to go.

I took your softer wording for the main claim, close to verbatim. It is better than mine — it
says what the experiments actually establish and stops short of the broader statement, which
is the right place to stop given we varied one closure and two distillation methods. **I kept
the parametric-versus-functional identifiability vocabulary** you asked for last time, but
moved it: your phrasing is now what the paper *asserts*, and the Loman framing is what
*explains* the finding a sentence later. Both manuscripts say it the same way — I have a
consistency check that fails the build if one of them drifts, which is how I found that the
old wording appeared in five places and not one.

The checklist has moved to sit after the references and before the appendix; the CFP confirms
that placement explicitly, so thank you for catching it.

On the footer: I checked the CFP, and it specifies exactly the two lines we already have —
`\usepackage[dblblindworkshop]{neurips_2026}` and `\workshoptitle{Sim2Science}`. The
"Submitted to 40th Conference…" line is the template's own submission-mode behaviour and
switches to the workshop name at camera-ready. I looked at forcing it earlier, and the option
that does so also turns off double-blind and prints the real byline, so I left it alone.

**On compute**, since you asked for it specifically. We never instrumented wall-clock, and I
would rather not invent a total. What I can give honestly is the hardware — CPU only, no GPU,
16 GB — and a per-run cost measured from the timestamps on the saved parameter files. The
conductance sweep wrote twelve of those back to back, and the gaps between them put a single
UDE training at about eleven minutes; the appendix states the run count the design implies so
a reader can multiply. **Checklist Q8 has gone from No to Yes** on the strength of that, and I
walked all sixteen answers again rather than only the three you named — Q4 and Q5 were still
pointing at a supplementary that will not exist, and two others were pointing at the wrong
section. Tell me if you would rather Q8 said something else.

Since then I have run two more audit passes over the checklist and the appendix, because the
checklist is the one file none of my automated checks can read and it ships inside the PDF.
They turned up nine more things and I have fixed all of them: the checklist was citing an
"Eq. 1" that no longer exists (a length pass had inlined that equation), and three separate
answers described the methods without mentioning the parametric fit, which is the paper's
main counter-experiment. The rest were appendix cross-references that pointed at the right
label but the wrong content — a caption sending the reader to Table 1 for a number Table 1
does not carry, and the compute appendix naming one neural-ODE run where the design has
three. **None of it touched the five-page body**, so the length is exactly where you last
saw it. I mention it not to alarm you but so you know what has moved since your review.

**The "state reconstruction" figure titles are fixed.** Two of the overview composites still
printed that in-image title where the code and the text now say "state propagation". It
turned out not to need a retrain: the UDE figures reload the saved parameter snapshot and do
a forward solve, and the one neural-ODE figure that did retrain came back byte-identical
panel for panel. The regenerated versions are what is attached, and no results file behind
any reported number was touched.

Vinayak
