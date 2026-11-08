# Hide Home Feed - Build Plan

Design: [./design/hide-home-feed.md](./design/hide-home-feed.md) · Tracker: [./todo.md](./todo.md) ·
Rules: [../.opencode/rules/hide-home-feed.md](../.opencode/rules/hide-home-feed.md) ·
Runbook: [../RUNBOOK.md](../RUNBOOK.md)

5 steps in 3 stages. Each step is a slice that runs, with a check that proves it.

This is a map. Steps get reordered, merged, split or skipped as the build teaches us
things - each change is one line in the **Changes** log at the bottom.

There is no migration stage: nothing is moved, replaced or retargeted. The patch adds
options inside the existing *Hide navigation buttons* patch; no existing test, script or
manifest is invalidated (the repo has no Reddit patch tests). The design note's
Verification table is the only ladder the checks climb.

## Verification coverage

| Design row | Covered by |
|---|---|
| V1 build | S00 C1 |
| V2 patch of 2026.45.0 | S00 C2, re-run at S02/S03 device steps |
| V3 diff discipline | S00 C3, re-run at every step's commit |
| V4 setting OFF behaves stock | S02 device test |
| V5 start tab + drawer | S01 (drawer route, manually attached), S02 (cold start) |
| V6 subreddit → Back | S03 device run |
| V7 join shows in drawer | S03 device run |
| V8 coexists with other hides | S03 device run |
| V9 Back never reaches Home | S03 device run |
| V10 resume/REDIRECT_TO_HOME | S03 device run |
| V11 notification post → Back | S03 device run (needs a human finger if adb cannot tap the notification) |
| V12 sub deep link, cold | S03 device run |
| V13 root deep link | S03 device run |
| V14 toggles together | S03 device run |
| V15 rotation + recents | S03 device run |

**The device gate.** S01 onward need a phone. Each device step starts by polling
`adb devices` (Android SDK at `../android-sdk`, `platform-tools/adb`); when it is empty the
agent waits and says so. The app on the phone is disposable: the agent uninstalls
Play-Reddit and installs the patched APK freely (signature mismatch makes this
mandatory). The owner's only act is plugging the phone in with USB debugging on.

## Stage A - Baseline and the riskiest assumption

### S0. The fork builds and patches 2026.45.0, unmodified

**Goal:** a green harness and a known-good patch pipeline before any code exists, so S1
debugs the feature, never the toolchain.
**Read:** `docs/design/hide-home-feed.md`; the existing `HideNavigationButtonsPatch.kt` and its
extension, as context only.
**Do:**
1. Land the artefact set and harness (this step carries them): build plan, tracker, rules,
   `opencode.json`, runbook, review prompt, step/stage templates, checkpoint runner + lib.
2. Write `scripts/checks/S00.sh` from the Check lines, then
   `scripts/checkpoint.sh 0`, committing `evidence/S00.log` with everything.

**Check:**
- `./gradlew buildAndroid` succeeds and produces `patches/build/libs/patches-*.mpp` (V1)
- Morphe Desktop patches `~/Downloads/com.reddit.frontpage_2026.45.0-*.apkm` with
  `--result-file`; the patched output exists and the result file reports no failed patch (V2)
- `git diff --stat` base..HEAD limited to `patches/` and `extensions/` is empty (V3)

### S1. The drawer opens on command - the riskiest assumption

**Goal:** with *Hide Home feed* OFF by default, tapping Communities in the app opens the
subreddit drawer from the patched route - proving `pjb.a()` through the injected method
works, and settling which helper instance collects the event.
**Read:** the decompiled 2026.45.0 sources for `CommunitiesTabScreen.L3` region (design note,
Drawer opening); the extension patch; the navigation fingerprints file.
**Do:** add the setting (`Settings.java`, `strings.xml`, preference category), fingerprint 4
the structural way the design table specifies, add `StartTabScreenInterface` +
`patch_openCommunityDrawer()` following the existing `patch_getLabel` pattern, and wire
`onStartTabAttached` with a deliberately over-generous delay (ponytail: empirical value comes
from this step's device run). Install on the device, tap Communities, watch `logcat`.

**Check:**
- The build produces the bundle and the patch applies with no failed patch (V2 re-run)
- On the device, after tapping Communities manually, the drawer opens showing joined
  subreddits (~V5's surface half)
- The `pjb` event's collecting helper instance is identified at runtime by logging
- No drawer and no crash with the setting OFF on cold start (~V4)

**If it fails:** stop. The design fallback is *Communities* with **no drawer**: hooks 1-3
only, drop hook 4 and the added method, design note becomes v2. This is the one step where a
failure means rethink rather than fix and continue.

## Stage B - The mechanism, on the device

### S2. Every go-to-Home lands on Communities

**Goal:** cold start, deep link and app-resume all land on the Communities tab; the Home
tab disappears from the bar when the setting is ON, and nothing changes when OFF.
**Read:** the design note's Hooks table and "Why these sites"; the extension patch;
`Fingerprints.kt`.
**Do:** add `getStartTab` and its three fingerprints the structural way (hooks 1-3), switch
`Home(false)` to `Home(Settings.HIDE_HOME_FEED.get())`, and extend `hideNavigationTab` so the
start tab is never removed (failure mode 3). Install, cold start, exercise the sites.

**Check:**
- Setting ON, cold start: no Home tab, Communities screen, drawer opens (V5)
- Setting OFF, cold start: opens on Home as before, no drawer (V4)
- Highlighted-tab behaviour reported per failure mode 4 if the slot is not Communities
- The extension returns the original tab on failure (V2-style sanity: no crash on hook error)

### S3. The device gauntlet

**Goal:** every remaining row of the Verification table is exercised on the phone, and the
empirical `START_DRAWER_DELAY_MS` replaces the generous spike value (design: generous value
kept if it works robustly; otherwise a later lifecycle hook, ponytail removed).
**Read:** this plan's coverage table; the design note's Failure modes; the step summaries.
**Do:** scripted adb runs (`am start`, `uiautomator dump`, `screencap`, `logcat`) for V6-V15,
the delay tuning first, failures fixed inside this step unless they contradict the design.
Anything needing a human finger (V11 notification tap is the known case) is flagged in the
stage report rather than skipped.

**Check:**
- V6-V15 each reported pass/fail with evidence captured per run
- A tuned (or confirmed generous) delay value, with the reasoning in the log
- V9 failing = stop: a Back path to Home was found that the design says not to hook
- `scripts/checkpoint.sh 3` green

## Stage C - Wrap-up

### S4. Final gate and hand-off report

**Goal:** `scripts/checkpoint.sh all` green from cold, the review done, the owner's final
report written.
**Read:** the stage reports; the Changes log.
**Do:** run all checkpoints, sweep V3 one last time (diff limited to the six allowed
product files), fresh-context review (below), write the final summary to the owner.

**Check:**
- `scripts/checkpoint.sh all` exit 0 from a cold start
- Every design Verification row marked covered in this plan's table, or explicitly
  deferred with a reason
- The review prompt has been run and its findings file exists
- Diff discipline V3 confirmed at the last commit

## The review workflow

Review happens at the end of every stage, on by default, never blocking a step. The
implementer produces the range line; review runs with fresh context on a different model
session:

    Read and follow docs/REVIEW-PROMPT.md for <first sha>..<last sha>

If the owner is not available to paste it personally, a fresh-context agent session runs
the review prompt unattended and its findings land in `docs/reviews/<sha>.md`; the owner can
re-run it on the same range with a different model later. A "Must fix" goes back to the
implementer as the next session's first prompt.

## Done

- [ ] `scripts/checkpoint.sh all` green from a cold start
- [ ] Every row of the design note's Verification table is covered by a check
- [ ] What changed from the design, and why
- [ ] What production needs that this omits

## Changes

- 2026-11-08 - V3's check corrected: the diff base is the commit S0 started on
  (6450ea3a3), not `main` - the branch was created ahead of main, so a `main` merge-base
  diffed ten upstream fix commits and failed V3 with 156 phantom lines
- 2026-11-08 - S0 written and executed with the artefact+landing set; no product code
  touched, so V3's diff check is satisfied by an empty diff
