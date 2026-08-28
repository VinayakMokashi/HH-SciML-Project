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
4. **COMPILE FIRST AND CHECK WHERE THE REFERENCES HEAD LANDS.** The restructure adds roughly
   four model lines against about twelve that were free, so it should still fit — but that is
   a model, not a measurement, and nobody has compiled it. If References has slipped off
   page 5, turn the first dial in the LENGTH DIAL block at the top of
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

**One thing I did not do.** The in-image titles on two older figures still read "state
reconstruction" where the code and the text now say "state propagation". Regenerating them
means retraining, and I was not willing to do that this close to the deadline for a wording
fix. Neither of those figures is in the workshop paper — I picked panels for the Stage-1
figure that never carried the wrong word — so nothing we are submitting is affected. It is on
the list for the archival version.

Vinayak
