# Hide Home Feed - Build Plan

Design: [./design/hide-home-feed-v2.md](./design/hide-home-feed-v2.md) (current) ·
v1: [./design/hide-home-feed.md](./design/hide-home-feed.md) (Hooks 1-3 and build facts still apply) ·
Tracker: [./todo.md](./todo.md) ·
Rules: [../.opencode/rules/hide-home-feed.md](../.opencode/rules/hide-home-feed.md) ·
Runbook: [../RUNBOOK.md](../RUNBOOK.md)

5 steps in 3 stages. Each step is a slice that runs, with a check that proves it.

v2 changed the requirement: the app stays logged out, opens on Reddit's search page, and
must never show a feed. No-feed is the top priority; a blank page is acceptable. The owner's
2026-11-09 amendment keeps the Home button in the bar, leading to the empty start screen.

This is a map. Steps get reordered, merged, split or skipped as the build teaches us
things - each change is one line in the **Changes** log at the bottom.

There is no migration stage: nothing is moved, replaced or retargeted. The patch adds
options inside the existing *Hide navigation buttons* patch; no existing test, script or
manifest is invalidated (the repo has no Reddit patch tests). The design note's
Verification table is the only ladder the checks climb.

## Verification coverage

Rows marked (v2) are the v2 note's redefinitions; all other rows are v1's, still standing.

| Design row | Covered by |
|---|---|
| V1 build | S00 C1 |
| V2 patch of 2026.45.0 | S00 C2, re-run at S01/S02/S03 |
| V3 diff discipline | S00 C3, re-run at every step's commit |
| V4 setting OFF behaves stock | S02 device test |
| V5 (v2, amended 2026-11-09) setting ON, cold start: search page, no feed, Home button present, no login | S01 (cold start via hook 1), S02 (re-run) |
| V6 (v2) subreddit from results as a guest; Back returns to search | S03 device run |
| V7 (v2) Back from search: empty tab, search button, Back exits | S01 (empty tab after Back), S03 (search button and exit) |
| V8 coexists with other hides | S03 device run |
| V9 Back never reaches Home | S03 device run |
| V10 resume/REDIRECT_TO_HOME | S03 device run |
| V11 notification post → Back | S03 device run (needs a human finger if adb cannot tap the notification) |
| V12 (v2) sub deep link, cold: subreddit stays on top, no search over it | S03 device run |
| V13 root deep link | S03 device run |
| V14 toggles together | S03 device run |
| V15 rotation + recents | S03 device run |
| V16 (v2) each route shows no feed | S01 (all five guards present), S03 (root, Popular, Communities re-tap, drawer rows, REDIRECT_TO_HOME) |
| V17 (v2) setting OFF renders Home/Discover/Popular normally | S02 device test |

**The device gate.** S01 onward need a phone. Each device step starts by polling
`adb devices` (Android SDK at `../android-sdk`, `platform-tools/adb`); when it is empty the
agent waits and says so. The app on the phone is disposable: the agent uninstalls
Play-Reddit and installs the patched APK freely (signature mismatch makes this
mandatory). The owner's acts are plugging the phone in with USB debugging on, keeping the
lock screen unlocked while a device step runs, and (as a guest) turning *Hide feeds* on; no
account or login is used.

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

### S1. No feed renders, and cold start lands on search

**Goal:** with *Hide feeds* ON, the drawer route is gone, all five feed screens are guarded
at their render method, and a cold start lands on Reddit's search page (hook 1, decision
`../decisions/S01-communities-tab.md`: Option A, Home button stays). No feed can render on
any route, and the app still works as a guest with no login.
**Read:** the v2 note's Feed guard and Landing on search sections (and its 2026-11-09
amendment); the five screen classes; the extension patch; the navigation fingerprints file.
**Do:** remove the v1 drawer route (`StartTabScreenInterface`, `START_DRAWER_DELAY_MS`,
`TabScreenClickHandlerProviderFingerprint`, and the `patch_openCommunityDrawer` block). Add
five structural fingerprints for the feed render methods (public final, void, `(L, I)`,
filtered by the v2 compose key where the signature is not unique - `HomePagerScreen` has
four). Inject the guard at index 0 of each. Add hook 1: `getStartTab` and its fingerprint
(public final void on `BottomNavScreen`, single `BottomNavTab` parameter) injected at index
0 of the matched method; `Home(false)` stays as it is and `hideNavigationTab` keeps the
start tab from being hidden. Change hook 4 to pass its `View` and open
`https://www.reddit.com/search` once per process through an `ACTION_VIEW` intent restricted
to the app's package. Keep the setting key; change the base-`values` title to *Hide feeds*.
A fingerprint miss on any guard must fail the patch.

**Check:**
- The build produces the bundle and the patch applies with no failed patch (V2 re-run)
- With the toggle ON, a cold start opens the search page as a guest: no login prompt, no
  feed markers (V5). The app in the foreground is Reddit before this is asserted
- Back from search shows the Communities tab with its top bar over an empty page - no
  Discover feed - and does not crash; its search button opens search again
- Home is still in the bottom bar (owner amendment); no Home tap is tested yet
- No `getStartTab failure`, no `onStartTabAttached failure` and no `FATAL EXCEPTION` in logcat
- Hooks 2-3 are **not** in this step; tapping Home and the rest of V16 wait for S2/S3

**If it fails:** stop and report. The v2 note forbids a login, so a guest-mode toggle or
search failure is a design problem, not something to work around.

## Stage B - The mechanism, on the device

### S2. Cold start stays on search; tapping Home reaches the empty start screen

**Goal:** with the toggle ON, cold start lands on Reddit's search page, tapping the bar's
Home button reaches the empty Communities start screen, and every internal go-to-Home lands
on Communities (hooks 1-3; hook 1 landed in S1). With it OFF, Home, Discover and Popular
render normally.
**Read:** v1's Hooks table and "Why these sites" (still authoritative); the extension patch;
`Fingerprints.kt`; the v2 amendment (the Home button stays in the bar).
**Do:** add hooks 2-3 (`initial_tab` default read, presenter selection funnel) structurally
per v1's Hooks table. `Home(false)` stays as it is, so the bar keeps its Home button; the
bar's Home tap reaches the new start screen through hook 3 (owner amendment). Install, cold
start, exercise the sites. The search launch stays once-per-process and guest-only.

**Check:**
- Setting ON, cold start: search page shows, Home feed blank, Home button present, no login
  prompt (V5 re-run; no feed at any moment)
- Setting ON, tapping the bar's Home tab: the empty Communities start screen with its search
  button, no feed (V16's Home route)
- Setting OFF, cold start: Home, Discover and Popular all render normally (V4, V17)
- Highlighted-tab behaviour reported per failure mode 4 if the slot is not Communities
- The extension returns the original tab on failure (V2-style sanity: no crash on hook error)

### S3. The device gauntlet

**Goal:** every remaining row of v2's Verification table is exercised on the phone.
**Read:** this plan's coverage table; v2's Verification rows; the step summaries.
**Do:** scripted adb runs (`am start`, `uiautomator dump`, `screencap`, `logcat`) for the
standing v1 rows plus v2's V5, V6, V7, V12, V16 and V17. V16 is the requirement: root,
Popular, tapping the bar's Home tab, a Communities re-tap, the drawer's Discover/Popular/Latest
rows and the `REDIRECT_TO_HOME` resume must each show no feed. Anything needing a human finger
(V11's notification tap, and the owner's eyes on the search zero state) is flagged in the stage
report rather than skipped.

**Check:**
- Every row in the coverage table reported pass/fail with evidence per run
- V16: no feed visible on any of its routes
- V17: with the setting OFF, Home, Discover and Popular render normally
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

- 2026-11-09 - S01's device check rewritten as a cold-start check (no tap on a Communities
  tab): it starts the resolved launcher activity with a force-stop, confirms Reddit is the
  focused app before any assertion (a dump of the launcher is a harness error, never a
  result), asserts the search page with no login prompt and no feed markers, then Back to the
  empty start screen under the Communities top bar, then that top bar's search button. The
  old marker (`hideFeedScreen`) would have kept the pre-hook-1 build installed; the marker is
  now `getStartTab`. Nothing proves less: the tap-Communities route the old check asserted was
  impossible on this phone, and cold start covers V5 directly. Home taps stay out of S1
  (Reddit still selects Home until hooks 2-3 land).
- 2026-11-09 - The "guards at instruction 0000" claim is now machine-checked instead of
  reviewed by eye: after injecting, the patch re-reads instruction index 0 of each guarded
  render method (and hook 1's method) and fails the patch if the hook call is not there. The
  claim moved from the decision note's hand-listed "proved on the machine" into every
  checkpoint run's result-file check.
- 2026-11-09 - S01 stalled at the owner-defined stop condition: cold start with hook 1 does
  not attach the Communities screen. Temporary debug logging (since removed) proved hook 1
  fires and returns `Communities`, but the tab's attach never runs, so the search launch
  never fires and the screen renders chrome-less blank. The standalone search link opens the
  search page as a guest (its zero state shows a Trending list - owner's eyes, screenshot in
  `evidence/S01-search-zero-state.png`). Reported to the owner; S2/S3 not started.
- 2026-11-08 - The S1/Communities-tab question is resolved: `docs/decisions/S01-communities-tab.md`
  Option A with one amendment. Hook 1 (`getStartTab`) moves into S1, and the Home button stays
  in the bar (hiding it left no way back on a phone without a Communities slot - the slot is
  server-controlled and may return). The v2 note's decision item 2, its V5 row and its S1
  redefinition are amended accordingly, as are this plan's S1/S2 steps and S01's checks.
- 2026-11-08 - The S1/Communities-tab question and its options are written up for the owner
  in `docs/decisions/S01-communities-tab.md`. Recommended: move hook 1 into S1.
- 2026-11-08 - S1's device check hit a design problem, not a code problem: on this phone
  the bottom bar has four tabs (`Home`, `Create`, `Inbox`, `You`); the Communities slot is
  empty (`jn90.a` returns null, v1 failure mode 4). There is no Communities tab to tap, and
  its attach is what launches search, so S1 as redefined cannot pass before hook 1 lands in
  S2. Awaiting the owner's decision: reorder hook 1 into S1, or redefine S1.
- 2026-11-08 - S01's app launch corrected: `monkey` intermittently left the launcher in
  front, so the device checks failed for a harness reason. It now starts the resolved
  launcher activity and polls for the focused window. Not a loosening.
- 2026-11-08 - S1's code, summary and check landed, but the device half is blocked: the
  phone's keyguard is secure and showing, and adb cannot clear it. `scripts/checkpoint.sh 1`
  stops at the new unlock gate after the build/patch checks pass. The todo box stays
  unchecked; nothing after the gate is device-verified yet.
- 2026-11-08 - Requirement change adopted from `design/hide-home-feed-v2.md`: guest mode
  only, land on Reddit's search page, never render a feed. The design pointer, coverage
  map and S1-S3 goals now follow v2. S1's drawer route is removed before device testing and
  replaced by five render-method guards plus the once-per-process search launch. v2
  replaces v1's V5, V6, V7 and V12 and adds V16 and V17; the other rows stand.
- 2026-11-08 - Hook 4 is injected at the start of the Communities tab's attach method, not
  after the achievements-proxy call as the v2 snippet shows. In 2026.45.0 that method
  reuses the `View` parameter register for the proxy before the snippet's point, so passing
  `p1` there would pass the proxy, not the view. At entry `p1` is still the attached view the
  extension needs for a context. Verified in the shipped dex: the call is 0000 with `v1`
  (the view) before `invoke-super`.
- 2026-11-08 - LOOSENED: S1 no longer checks the drawer opening or the joined-subreddit
  list (v1's V5 surface half and V7). The owner has ruled out the account that list
  needed, so v2 replaces them with V5 (search landing, no feed) and V7 (Back to an empty
  tab). Nothing else covers the old drawer behaviour; it is out of scope by design.
- 2026-11-08 - Build paused at S1's owner gate: the requirement changed to
  *"do not log in at all"*, which removes the drawer's data source (the joined list is
  account-bound). Crossroads recorded in `HANDOVER.md`; design direction awaits advice.
  No S1 device gate was closed.
- 2026-11-08 - S0/S1 checkpoint constants moved to `scripts/checks/env.sh` - the machine
  paths were duplicated per checkpoint and would have diverged on the next edit
- 2026-11-08 - V3's check corrected: the diff base is the commit S0 started on
  (6450ea3a3), not `main` - the branch was created ahead of main, so a `main` merge-base
  diffed ten upstream fix commits and failed V3 with 156 phantom lines
- 2026-11-08 - S0 written and executed with the artefact+landing set; no product code
  touched, so V3's diff check is satisfied by an empty diff
