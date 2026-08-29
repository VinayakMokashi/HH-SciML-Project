# N21 — reply to Prathamesh after mentor review 3 (the video, 2026-08-29)

**This supersedes `draft-email-N9-prathamesh.md`**, which was the reply to review 2. He has
since seen that draft and reviewed it on video, so that file is history — do not send it.

**Before sending:**
1. Rebuild and recompile: `python scripts/make_sim2science_bundle.py`, then compile
   `sim2science_upload/main.tex` on Overleaf. Attach THAT pdf. Anything built before
   2026-08-29 night is superseded.
2. **Look at the compiled first page.** Confirm the citation boxes are gone and the footnote
   reads "Submitted to the Sim2Science workshop at the 40th Conference…". The email claims
   both; do not claim them without seeing them.
3. Confirm the References head still opens page 6. The body only got shorter, but this is the
   first round that touched it. **The email deliberately does NOT claim the page count** —
   no compiled PDF exists in the repo, so it is not ours to assert yet.
4. If you would rather just submit, cut the last paragraph. Everything else stands.

**Written deliberately plain: no headers, no bullets, one dash in the whole note.** A reply
defending a de-AI-ing pass cannot itself be laid out as a status report. Do not "tidy" it into
sections before sending.

---

**Subject:** Sim2Science — your changes are in, and one I didn't make

Hi Prathamesh,

Thank you, that was a useful review, and the language point was the right one to push on.

The link boxes are gone. They were coming from hyperref: the full paper sets `hidelinks`, the
workshop version never got it, which is why you saw borders in one and not the other. The links
still work, the boxes just don't draw.

The footnote names the workshop now. The template does build "Workshop: Sim2Science", but it
only prints it in camera-ready mode, and the option that forces it also switches off
double-blind and prints our real names. So I overrode that one line in our own preamble and
left the style file untouched, since the template warns that tweaking it can be grounds for
desk rejection.

The checklist is a third shorter, 1016 words down to 648, and the compute answer went from 153
words to 38. You were right that it read as machine-written. Checking afterwards, the NeurIPS
template itself asks for a short one or two sentence justification, so the long version was
outside its own guidance, not just yours. The Data and code paragraph is shorter too. It now
says we withhold the code for anonymity and release everything on acceptance, MIT for the
software and CC BY 4.0 for the results, which is what checklist Q5 and Q13 say.

On the language: "recipe" is gone from the workshop paper, and so are the three sentences
opening with "Nor". You were right that the repetition was the giveaway, and right that the
second one was hard to parse. I could not defend it either when I went back to it. Both still
stand in the full paper and I will do the same pass there after the deadline.

On dashes, the checklist is down to none and the body runs about one per thousand words. I left
the few that genuinely interrupt a sentence rather than chase the count to zero.

The bigger change came out of going back to my own writing notes. The paper never once said
what we expected and did not get — every "we" in it was procedural, we ran, we fit, we
measured. It now says the expectation in three places: that we expected to use the black-box
baseline as published and it needed repairing first; that we expected the usual reading to
hold, that one short trajectory cannot pin the conductance; and that we expected four times the
budget to tighten the estimate, and it loosened it. The last one is the retrain control, and
saying it that way is just closer to what happened.

Beyond those three I reworked prose through the body, splitting the long balanced sentences and
dropping the flourishes. Every edit came out the same length or shorter, so the body actually
shrank. The paragraphs you read in Sections 1 and 3 will look different; none of them changed
meaning.

One I did not do. You said the checklist guidelines could go, but the template says in bold to
keep the questions, the answers and the guidelines. It is the same collision we had over table
captions last time, so I made the same call: the template wins, the guidelines stay, and I cut
the justifications instead, which is where the length actually was.

On Raj, thank you, that solves it. I had been hunting for a profile ID string and there was no
need for one.

The deadline is 2 September, 23:59 AoE, which is 17:29 our time on the 3rd. If you can get to
it by the 1st I will fold in whatever you find; otherwise I will submit and we can take the
rest into the archival version.

Vinayak
