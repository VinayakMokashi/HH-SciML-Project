# N20 — draft reply to Prathamesh after mentor review 2

Status: DRAFT, not sent. Rewritten 2026-08-28 after his two review emails (HANDOFF §4n).

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

**The Stage-1 figure is in.** You were right that a reader never saw prediction succeed
before being shown interpretation fail, which is a real gap in a paper called *Predict, then
interpret*. It now leads the results.

I took your softer wording for the main claim. It is better than mine — it says what the
experiments actually establish and stops short of the broader statement, which is the right
place to stop given we varied one closure and two distillation methods.

The checklist has moved to sit after the references and before the appendix; the CFP confirms
that placement explicitly, so thank you for catching it.

On the footer: I checked the CFP, and it specifies exactly the two lines we already have —
`\usepackage[dblblindworkshop]{neurips_2026}` and `\workshoptitle{Sim2Science}`. The
"Submitted to 40th Conference…" line is the template's own submission-mode behaviour and
switches to the workshop name at camera-ready. I looked at forcing it earlier, and the option
that does so also turns off double-blind and prints the real byline, so I left it alone.

**On compute**, since you asked for it specifically. We never instrumented wall-clock, and I
would rather not invent a total. What I can give honestly is the hardware — CPU only, no GPU,
16 GB — and a per-run cost measured from the timestamps on the saved parameter files, which
come out at about eleven minutes per UDE training run, plus the number of runs the design
implies. The checklist says it that way. Tell me if you would rather it said something else.

Vinayak
