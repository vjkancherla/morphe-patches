# Runbook

The agent builds. I look at the end of each stage. Nothing sits between one step and the next.

## Build

    do stage <X>        every step in the stage, then a report, then it stops
    do S<N>             one step, then it stops
    plan S<N>           only the summary of what it would build, then it stops

Each step: it writes the summary and the check, builds, runs the check, ticks the box,
commits.

## The phone

Before "do S1" onward, plug the phone in with USB debugging on. When the agent needs it and
`adb devices` is empty it will stop and say "waiting for the phone" - plug it in and say
"go". The Reddit app on it is disposable: the agent uninstalls Play-Reddit and installs the
patched APK freely. Nothing on my real devices is touched.

## What changed, without reading code

`docs/steps/S<N>.md`, one screen per step: one sentence on what works now, a diagram, a
few plain bullets, and any choices I might want made differently. If I want one of those
choices changed: "change S<N>: <what>".

## When it stops early

It stops only if a check failed twice, the risky assumption failed (S1's fallback: stays on
Communities with no drawer), the step clashes with the design, it needs something outside
its scope, or no phone is attached. It says what it saw and what it would do. I answer, or
change the plan:

| I say | What happens |
|---|---|
| "the check is wrong: <why>" | It fixes the check and logs what it now proves |
| "skip S<N>" / "do S<N> first" / "merge S2 and S3" | It updates the plan and logs a line |
| "try <approach>" | It continues with that |
| "what will S<N> check?" | `scripts/checkpoint.sh <N> --explain` |

## End of a stage

1. Read `docs/stages/<X>.md` - one screen: links to the step summaries, which checks
   changed, what is mine to decide. **Checks that changed** is the section not to skip.
2. Review, different model, new session - paste the line at the bottom of the report:

       Read and follow docs/REVIEW-PROMPT.md for <first sha>..<last sha>

   If I am not around, the agent runs that same prompt in a fresh-context session itself
   and files it in `docs/reviews/`; I can re-run it on the range whenever I like.
3. If the review has a **Must fix** list - back to the implementing model, new session:

       Read docs/reviews/<sha>.md and fix the Must fix items. Nothing else.

4. Next stage.

The review is the only time anything other than the author reads the code. Skipping it is
my call; for the stages with the novel logic (S1, S2), don't.

## Worth noticing

- A check listed as LOOSENED with nothing else covering it
- A step summary I could not follow, or one with code in it - ask for it in plainer terms
- The same step stopping twice - that is a design problem, not a code problem
- A review that says it is fine in one line and names nothing it checked
