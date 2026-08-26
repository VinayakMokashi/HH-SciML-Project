# N9 — draft email to Prathamesh, sending the 5-page Sim2Science draft

Status: DRAFT, not sent. Written 2026-08-26 after round 9 and the compiled-PDF pass.

**Attach both PDFs**, compiled from `sim2science_upload/`:
- `main.pdf` — the 5-page submission (anonymous)
- `supplementary.pdf` — the anonymised archival manuscript (29 pp)

**Before sending, check three things:**
1. `supplementary.tex` has been recompiled since the bundler's `TODO-` fix. The old PDF
   printed `TODO-REPOSITORY-URL` to reviewers.
2. The three things in the middle section are the ones he would otherwise *find* — two of
   them are asks of his that we did not meet. Do not soften them.
3. The deadline is real and close. The reviewer-ID ask is the one that blocks submission,
   so it is first, not last.

---

**Subject:** Sim2Science draft attached — and I need your OpenReview ID before Sat 30 Aug

Hi Prathamesh,

Both PDFs are attached: the 5-page submission and the supplementary, which is the full
manuscript anonymised. The workshop deadline is **Saturday 30 August, 17:29 IST**
(29 Aug 23:59 AoE), so I have put what I need from you at the top.

**What I need from you, ideally by Thursday 28th**

1. **Your OpenReview reviewer ID or the email your OpenReview profile uses.** The CFP
   requires us to nominate one author as the paper's reciprocal reviewer at submission
   time, and you volunteered in your video. I cannot submit without it.
2. **Confirm your author line exactly as it should appear** — I currently have
   *Prathamesh Dinesh Joshi, Vizuara AI Labs, Prathmesh@vizuara.com*, which is what you
   confirmed earlier. Worth one look, because **every author must be listed at submission
   and nobody can be added after review opens.**
3. **Any changes you want in the 5-page paper.** Anything structural needs to reach me by
   Thursday; a wording fix can land Friday. If you are happy with it as it stands, just
   say so and I will submit.

**Three things I would rather tell you than let you find**

**The framing went to option (C): the paper audits the two-stage predict-then-interpret
recipe** rather than leading with the negative result. Stage one earns its reputation,
stage two does not, and a chain of controls says why. I got there by going back and
reading your full-paper draft properly — it is *already* built that way, question title,
positives first in the contributions, a conclusion that opens positive and only then
turns. Leading the workshop paper with the reversal would have made it more aggressively
framed than the manuscript it is derived from, which is the objection you raised. The
science is identical either way: same numbers, same controls, same guards.

**The forecast plot and the ablation figure are in the supplementary, not the body, and I
could not make them fit.** This is the ask of yours I did not meet, and I want to be
straight about the cost. The body carries one figure and one table. Restoring the forecast
bars would have meant deleting either the retrain control or the conductance sweep — the
two controls that answer "you under-trained" and "you tuned g_Ca = 2.0" — and I judged
those worth more under review than the plot. The supplementary does print them, but **the
CFP says reviewers are not obliged to read it**, so they are *available*, not *guaranteed
seen*. If you disagree with that trade, tell me and I will make the swap.

**Table captions stay above the tables.** This is the one place your advice collides with a
binding requirement rather than a preference: the official NeurIPS template puts table
captions above and figure captions below, and its own sample table does exactly that.
Moving them would take us away from the required template, so I left them.

**What has changed since your video, briefly**

Retitled to *"Predict, then interpret: how far a UDE gets on a hidden ionic current"* —
deliberately not the archival title you flagged as AI-generated. The AI-tell pass is done
on the 5-page paper: em-dash rate down from 4.1 to 1.6 per thousand words. Discussion and
Conclusion are now one section and Limitations and Future Work another, two paragraphs
each, as you asked. The identifiability claim is narrowed everywhere to *this closure under
these distillations* rather than stated in general — your "we can make an exact claim if
some of the identification is not working" point, applied at every site in both papers.

The presentation pass on the **archival** paper is still open; I am holding it until after
the deadline so it does not eat the submission window. Your second round of feedback on
that one can come whenever suits you.

Thanks — and thank you for offering to review. That is the piece I genuinely cannot do
without.

Vinayak
