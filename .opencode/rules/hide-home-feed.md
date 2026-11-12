# Hide Home Feed - working rules

You implement this project from `docs/build-plan.md`. Keep moving. Stop only where this
file says to.

## Scope

- **All product work happens inside `morphe-patches/`.** `../reddit-decompiled/`,
  `../reddit-apk/` and `../tools/` are read-only.
- **Six product files and no others:** extensions `Settings.java`, `strings.xml` (base
  `values/`), `NavigationBarPreferenceCategory.java`, extension `HideNavigationButtonsPatch.java`;
  navigation package `Fingerprints.kt` and `HideNavigationButtonsPatch.kt`. Build-plan
  artefacts (docs/, .opencode/, scripts/, evidence/) are outside that list.
- `../reddit/shared/Constants.kt` is **not** in scope: it declares version compatibility
  for all 32 Reddit patches.
- Verify against 2026.45.0 only. No upstream PR goals this build.
- No new dependency. Build what the step asks for. No "also fixed", no refactoring outside it.
- Shell: macOS, zsh. `source ~/.zshrc` supplies `JAVA_HOME` (JDK 21) and `ANDROID_HOME`.
  adb is `../android-sdk/platform-tools/adb`.

## Git: every feature lives on its own branch

- **Never commit work on `main`.** It holds only verified, landed state.
- **Step work continues on the existing `feature/*` branch** - resuming is not a new
  start, so find the branch (`git branch --list 'feature/*'`, `git status`) before opening
  a new one. This build's branch is `feat/hide-home-feed`; new steps commit there.
- **Housekeeping is exempt.** Rule files, docs corrections, checkpoint contract fixes and
  rollback bookkeeping may land directly on `main` - small, self-contained, and visible
  in the log.
- **Landing needs both proofs checked.** The feature branch merges into `main`
  (`git merge --no-ff`) only when the step's checkpoint passes and the human has read the
  summary or asked for it. After the merge, delete the branch; anything kept around goes
  under `archive/...`.
- **Do not rewrite history** and do not push to `origin` unless the owner asks.

## How to work - the lazy senior developer

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the
code never written. Before writing any code, stop at the first rung that holds:

1. Does this need to be built at all?
2. Does it already exist in this codebase - the neighbouring fingerprints, the
   `patch_getLabel` pattern, the helper-method way an earlier patch got around an
   obfuscated class? Reuse it.
3. Does the standard library already do it? Is it one line? Make it one line.
4. Only then: write the minimum code that works.

The ladder runs after you understand the problem, not instead of it: read the step and the
code it touches, trace the real flow end to end, then climb.

- No abstractions, no boilerplate, no cleverness. Deletion over addition. Fewest files.
- Shortest working diff wins - but root cause, not symptom: a fix in the shared function
  beats one per call site, and the smallest change in the wrong place is a second bug.
- Mark a deliberate simplification with a known ceiling with a **ponytail** comment: what
  the ceiling is, and the upgrade path (e.g. the fixed drawer delay).
- Not lazy about: understanding the flow first (this build's one expensive mistake was an
  assumed screen - `MyCommunities` - that was never real), the structural way fingerprints
  match obfuscated code, error handling that keeps the app running, and the exactness the
  device run needs: the phone is never the spec's time constant, which is why the delay is
  measured not guessed.
- **Non-trivial logic leaves one runnable check behind** - the step's checkpoint is that
  check.

## The evidence rule

- Every step runs through `scripts/checkpoint.sh <N>`, never a bare rerun of the underlying
  commands, so the run is captured.
- Commit `evidence/S<N>.log` together with the step's code, summary and check.
- **Never edit an `evidence/` log.** It is captured output. If it is wrong, run the check
  again; a new log replaces it, a hand edit never hides what ran.
- **Never edit a frozen gate.** A check from an earlier step does not get reworded to fit
  today's code. If it is provably wrong, fix it in the open: one line in the plan's
  **Changes** log, starting `LOOSENED:` if it now proves less.

## Review workflow

At the end of every stage: run `scripts/checkpoint.sh all`, write the stage report
(`docs/stages/<stage>.md`), then run the review - a different model, fresh session, with:

    Read and follow docs/REVIEW-PROMPT.md for <first sha>..<last sha>

If the owner is unavailable, a fresh-context agent session runs `docs/REVIEW-PROMPT.md`
unattended; its findings go to `docs/reviews/<sha>.md`, every item on its **Must fix** list
becomes the next session's first prompt. Review never blocks a step mid-stage, and it is
never skipped for a stage with novel logic.

## Doing a step

1. Read the step, and the files it lists. Not the whole tree.
2. **Write the summary**: `docs/steps/S<N>.md` from `docs/steps/TEMPLATE.md` - what you
   are about to build, on one screen.
3. **Write the check**: `scripts/checks/S<N>.sh` from the step's **Check** lines,
   sourcing `lib.sh`. Run it - it should fail, because nothing is built yet.
4. Build the step. The simplest thing that satisfies the checks. No unit tests for glue;
   the arguments are obfuscated bytecode and a phone, the checkpoints and the device run
   are the tests.
5. Run `scripts/checkpoint.sh <N>`.
6. Pass → if what you built differs from the summary, rewrite the summary to match. Tick
   the box in `docs/todo.md` and commit the code, the summary, the check and
   `evidence/S<N>.log` together, with a semantic message that names the step.

- "do S<N>": all six, then stop. Do not wait after the summary.
- "do stage <X>": all six, then the next step in that stage.
- "plan S<N>": steps 1 and 2 only, then stop. The human wants to read it first.
- "change S<N>: ...": update the summary. If the step is already built, change the code to
  match, re-run the check, and commit.

## Device gate

A step that tests on the phone starts with `adb devices`; when it is empty, stop and say
"waiting for the phone", then end the session - the owner plugs it in and says go. Do not
hold the session open polling. The app's data on the phone is disposable; the agent
uninstalls and reinstalls Reddit freely.

## Step summaries

For a human who will not read the code. One screen, no code.

- **One sentence**: what works after this step that did not before.
- **A diagram**: a sequence diagram when the step is about components calling each other;
  a state or flow diagram when it is about states or branching; none when there is nothing
  to draw. Mermaid.
- **Three to six bullets**: what each part does, in plain words rather than function names.
- **Up to three choices** the human might want made differently. Only real ones.
- No snippets, no diffs, no signatures, no file lists, no edge cases. If it will not fit
  one screen, the step is too big - split it.

## Checks - yours to write and to keep right

- Every checkpoint has a `describe` block (Proves / How / Needs), and every check has a
  plain-English description and a "where to look". A human reads this output.
- **If a check is wrong, fix it.** Do not stop to ask. Add one line to the **Changes** log
  in `docs/build-plan.md`: what it checked before, what it checks now, why.
- **Never loosen a check silently.** If your change means the check proves less than it
  did, that line starts with "LOOSENED:". Fixing a check that was wrong is fine. Weakening
  one because the code does not pass it, and not saying so, is the one thing in this file
  that is never fine.
- Never edit an `evidence/` log. It is captured output.

## When to stop

- **A check has failed twice**, after two different fixes. Do not try a third approach.
- **The step marked as the riskiest assumption fails.** For S1 that is the drawer route:
  the fallback is *Communities* with no drawer, and the design note becomes v2.
- **Doing the step properly would contradict the design's load-bearing decision.**
- **The step needs something outside your scope.**
- **A device step finds no phone attached.** See Device gate.
- **A consult trigger fires.** See Consulting Claude.

When you stop, say in a few lines what you saw, what you tried, and what you would do next.
If another step in the stage does not depend on the blocked one, do that one and say so.

Anything short of those is not a reason to stop. If the plan or the design answers the
question, do not ask it.

## Consulting Claude (owner-triggered only)

Claude's usage is limited and reserved for decisions. Never run `claude`, or any other Claude
command, yourself. Write the consult file, stop, and tell the owner. Only the owner starts a
consult.

### Write a consult when

- a decision note or design change is needed, before writing its code
- a second fix attempt on the same problem has failed
- the next step depends on a claim about Reddit's behaviour that you could not check against
  the decompiled code or the phone
- a stop condition fired and the way forward is not obvious

Do not consult for build errors, fingerprint tuning, routine checks, or anything the design
already answers. Have only one consult open at a time.

### Before you write it

Do this work first. Claude should not have to gather what you can gather.

1. Try to disprove your own diagnosis, and record what you tried.
2. Mark every statement as OBSERVED or INFERRED. OBSERVED must cite a log line, screenshot,
   dump or `file:line`.
3. Confirm each piece of evidence came from the current build and shows the intended screen.
4. For each option, state what it breaks one step later.
5. Look for an option the current notes do not list.

### File

Write `docs/consults/NNN-short-name.md`, one page at most, with exactly these sections:

    # Consult NNN: <the question, in one sentence>

    Build: <commit> · Trigger: <which rule above>

    ## Question
    <the single decision needed>

    ## Observed
    <facts, each with its evidence path or file:line>

    ## Inferred
    <your theory, and what would prove it wrong>

    ## Tried
    <what you tried, and the result>

    ## Options
    <each option: what it does, its cost, what it breaks one step later>

    ## Recommendation
    <your pick and why>

    ## Files Claude should read
    <at most five paths, with line ranges where possible>

Commit the file, tell the owner its path, and stop work that depends on the answer. Continue
any independent work.

### After the answer

Claude's reply is `docs/consults/NNN-short-name-answer.md`. Follow it unless the evidence has
changed. If it has, write a new consult. Do not argue with the answer in code. Record the
outcome in the plan's Changes log.

A consult answer does not replace the stage-end review, and Claude's advice is a claim to be
tested on the device like any other.

## The plan is a map

- Reorder, merge or split steps when what you have learned makes the listed order wrong.
- Skip a step that has become pointless: mark it skipped in `docs/todo.md` with the reason.
- Each of those is one line in the **Changes** log. No other ceremony.
- You may not skip a row of the design note's **Verification** table. If one can no longer
  be checked, that is a stop. A row needing a human finger gets flagged in the stage
  report, not skipped.
- The human can change the plan at any time by saying so. Update it and log the line.

## End of a stage

1. `scripts/checkpoint.sh all`
2. Write `docs/stages/<stage>.md` from `docs/stages/TEMPLATE.md`.
3. Run the review workflow (this file, above).
4. Stop. The next stage starts on the owner's word, or on the review being clean.

## Never

- Rewrite history or force-push. A step that went wrong is fixed in a new commit.
- Push `feat/hide-home-feed` - stays local unless the owner says so.
- Edit `.opencode/rules/`, `opencode.json` or `RUNBOOK.md`. If one is wrong, say so.
- Hard-code a decompiled name (`f1`, `sps`, `pjb`, `re6`) into a fingerprint or a patch -
  match on structure, take names from the matched instruction.
- Log or commit secrets, keys, or the owner's personal data from the device.
