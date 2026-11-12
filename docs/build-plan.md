# Hide Home Feed - Build Plan

Design: [./design/hide-home-feed-v2.md](./design/hide-home-feed-v2.md) (current) ·
v1: [./design/hide-home-feed.md](./design/hide-home-feed.md) (Hooks 1-3 and build facts still apply) ·
Tracker: [./todo.md](./todo.md) ·
Rules: [../.opencode/rules/hide-home-feed.md](../.opencode/rules/hide-home-feed.md) ·
Runbook: [../RUNBOOK.md](../RUNBOOK.md)

5 steps in 3 stages. Each step is a slice that runs, with a check that proves it.

v2 changed the requirement: the app stays logged out, opens on Reddit's search page, and
must never show a feed. No-feed is the top priority; a blank page is acceptable. The owner's
2026-11-09 amendments keep the Home button in the bar; the third amendment (2026-11-09,
owner decisions on the handover's pending items) makes the cold start open search by itself
via the guarded Home screen's attach (hook 5, because `BottomNavScreen` builds that screen
directly, so no tab-selection site lets the first screen change), makes every Home tap open
search through the bar-tap handler (hook 6), adds a *Hide Inbox button* toggle driving
`Inbox` and `UnifiedInbox`, and removes the search zero state's Trending sections.

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
| V5 (v3) setting ON, cold start: **search opens by itself** (hook 5), no feed, Home button present, no login | S01 (device), S02 (re-run) |
| V6 (v3) subreddit from results as a guest; Back returns to search | S01 device, S03 re-run |
| V7 (v3) Back from search: no feed, no crash; top-bar search button works | S01 (Back flow), S03 (search button and exit) |
| V8 coexists with other hides | S03 device run |
| V9 Back never reaches Home | S03 device run |
| V10 resume/REDIRECT_TO_HOME | S03 device run |
| V11 notification post → Back | S03 device run (needs a human finger if adb cannot tap the notification) |
| V12 (v3) sub deep link, cold: subreddit stays on top, no search over it | S03 device run |
| V13 root deep link | S03 device run |
| V14 toggles together | S03 device run |
| V15 rotation + recents | S03 device run |
| V16 (v3) each route shows no feed, **with and without a Communities tab** | S01 (all five guards present), S03 (root, Popular, Communities re-tap, drawer rows, REDIRECT_TO_HOME) |
| V17 (v3) setting OFF renders Home/Discover/Popular normally | S02 device test |
| V18 (v3) every Home tap opens search, bare blank Home never after a tap flow; Communities top bar and its Morphe menu stay reachable | S01 device |
| V19 (v3) Hide Inbox button toggle drives Inbox + UnifiedInbox | S03 device run |
| V20 (v3) search zero state has no Trending sections; recent searches stay | S03 device run (before-and-after dump) — the ONE attempt FAILED on device; owner accepted as shipped, 2026-11-10 (option a); row stays red with the reason |

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

### S1. No feed renders, cold start lands on search, every Home tap opens search

**Goal:** with *Hide feeds* ON, the drawer route is gone, all five feed screens are guarded
at their render method, a cold start lands on Reddit's search page by itself (hook 5 at the
guarded Home screen's attach - `BottomNavScreen` builds that screen directly, so tab
selection cannot decide the first screen; the owner's third-amendment decision), and every
tap on the bar's Home opens search and lands the empty Communities screen underneath (hook
6), keeping the Communities top bar and its Morphe-settings menu reachable. No feed can
render on any route, and the app still works as a guest with no login.
**Read:** the v2 note's Feed guard, Third amendment (hooks 5-6, shared launch), Search zero
state, and Verification sections; the five screen classes; the extension patch; the
navigation fingerprints file.
**Do:** hooks 1-4 as landed (the drawer-route removal from the v2 note; the five render
guards; hook 1 start-tab replacement; hook 2 initial-tab default; hook 3 selection funnel;
hook 4 the start tab's attach passing its View). Add hook 5: the guarded Home screen's
attach override (one View, calls super, tells itself apart from its detach twin
structurally, match unique), passing the View to hook 4's extension method. Add hook 6 at
the bar's tap handler (bottomnav Function0 carrying `loggedOutBottomSheetScreenFactory` and
`feedRefreshPolicy`): replace the tapped-tab register right after the bar-item read, before
any comparison, with `onBottomTabTapped`. Rewrite the extension's search launch as the one
shared debounced helper (WeakReference context, ~1 s debounce, failures logged, flag set so
attach hooks cannot double-launch; tap path returns the mapped tab when the context is
empty). Add the *Hide Inbox button* setting driving `Inbox` and `UnifiedInbox`, next to the
Create toggle. Device checks always install the freshly patched build with `install -r`
(data kept) - no marker-based skip. Search zero state trending removal is deliberately
**last** (after S1-S3 are green), so it cannot block them.
A fingerprint miss on any guard or hook must fail the patch.

**Check:**
- The build produces the bundle and the patch applies with no failed patch (V2 re-run)
- With the toggle ON, a cold start opens the search page by itself as a guest: no login
  prompt, no feed (V5)
- Back until the keyboard is closed and the search page is gone: no feed, no crash; the
  Communities top bar is present (V7's flow half)
- Tapping the bar's Home opens search; Back shows the Communities top bar, no feed (V18)
- Three or more Home taps, closing search between them: search opens each time, and the
  bare blank Home page never appears after the tap flow; the Communities menu still reaches
  the Morphe entry (V18)
- A subreddit search, open, Back returns to search (V6)
- Home is still in the bottom bar (owner amendment); no check requires a Communities bar slot
- No patch failure (`getStartTab`, `onStartTabAttached`, `onBottomTabTapped`,
  `openSearchPage`, `filterSearchZeroState`) and no `FATAL EXCEPTION` in logcat
- Search zero state's Trending removal and the Inbox toggle wait for S3 (V19, V20)

**If it fails:** stop and report. The v2 note forbids a login, so a guest-mode toggle or
search failure is a design problem, not something to work around.

## Stage B - The mechanism, on the device

### S2. Tapping Home stays on the empty start screen; the setting OFF behaves stock

**Goal:** with the toggle ON, hooks 1-3 keep every internal go-to-Home on the Communities
start screen even if a route re-selects Home without a tap (the tap path is hook 6, proved
in S1). With it OFF, Home, Discover and Popular render normally.
**Read:** v1's Hooks table and "Why these sites" (still authoritative); the extension patch;
`Fingerprints.kt`; the third amendment.
**Do:** hooks 2-3 (`initial_tab` default read, presenter selection funnel) structurally per
v1's Hooks table. `Home(false)` stays as it is. Install, cold start, exercise the sites.
The search launch stays once-per-process per attach and guest-only; Home taps open search
per hook 6.

**Check:**
- Setting ON, cold start: search page shows by itself, Home feed blank, Home button
  present, no login prompt (V5 re-run; no feed at any moment)
- Setting ON, tapping the bar's Home tab: search opens and the Communities screen sits
  underneath with its top bar over an empty page (V16's Home route)
- Setting OFF, cold start: Home, Discover and Popular all render normally (V4, V17)
- Highlighted-tab behaviour reported per failure mode 4 if the slot is not Communities
- The extension returns the original tab on failure (V2-style sanity: no crash on hook error)

### S3. The device gauntlet

**Goal:** every remaining row of v3's Verification table is exercised on the phone,
including V12 (a cold external r/<sub> link stays on top with no search page over it), all
V16 routes with and without a Communities tab, the Inbox toggle (V19) and the Trending
removal with its before-and-after dump (V20).
**Read:** this plan's coverage table; the v2 note's Verification rows; the step summaries.
**Do:** scripted adb runs (`am start`, `uiautomator dump`, `screencap`, `logcat`) for the
standing v1 rows plus v3's V5, V6, V7, V12, V16, V17, V18, V19 and V20. V16 is the
requirement: root, Popular, tapping the bar's Home tab, a Communities re-tap, the drawer's
Discover/Popular/Latest rows and the `REDIRECT_TO_HOME` resume must each show no feed -
each with and without a Communities tab. Anything needing a human finger (V11's
notification tap) is flagged in the stage report rather than skipped.

**Check:**
- Every row in the coverage table reported pass/fail with evidence per run
- V16: no feed visible on any of its routes, with and without a Communities tab
- V17: with the setting OFF, Home, Discover and Popular render normally
- V19: the Hide Inbox button toggle hides Inbox and UnifiedInbox, restores them when off
- V20: the search page before typing has no Trending or Trending Communities sections
  (before-and-after dumps), recent searches kept
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

- [ ] `scripts/checkpoint.sh all` green from a cold start - **superseded by the owner's
      final-gate decision (2026-11-11)**: S03 fails only on V20 (red-accepted), so the
      raw `all` verdict stays an honest FAIL; the gate (S04) asserts each checkpoint's
      recorded verdict instead - S04 encodes the decision, the raw run is shown in the
      final report
- [x] Every row of the design note's Verification table is covered by a check (or
      explicitly deferred below)
- [x] What changed from the design, and why (stage reports + the Changes log)
- [x] What production needs that this omits (the final hand-off report)

## Final gate - covered / deferred (2026-11-11)

Every design Verification row, accounted for at the final gate:

| Row | Status | Evidence and reason |
|---|---|---|
| V1 build | PASS | S00 C1 |
| V2 patch of 2026.45.0 | PASS | S00 C2, re-run green at every checkpoint (result.json, 29/29, no failed patches) |
| V3 diff discipline | PASS | S00 C3; re-swept at the final gate's last commit: only the six allowed product files, +606/-2 |
| V4 setting OFF stock | PASS | S02 (13/13) |
| V5 cold start opens search | PASS | S01 (18/18), S02 re-run |
| V6 subreddit from results, Back to search | PASS | S01 (guest r/soccer round-trip) |
| V7 Back flow + top-bar search button | PASS | S01 (Back flow), S03 [8] |
| V8 coexists with other hides | PASS | S03 [12] |
| V9 Back never reaches Home | PASS | S03 [9] (a failure would be a STOP) |
| V10 resume from background | PASS | S03 [13] (resume variant; the REDIRECT_TO_HOME timeout path needs a server-backed session - variant recorded in S03) |
| V11 notification post -> Back | DEFERRED | needs a human finger if adb cannot tap the notification; flagged in every S03 run, covered nowhere else |
| V12 cold sub deep link | PASS | S03 [10] |
| V13 root deep link | PASS | S03 [11] |
| V14 toggles together | PASS | S03 [18] |
| V15 rotation | PASS | S03 [14] (pixel-diversity score recorded) |
| V16 every route, no feed | PASS | S01 (all five guards) + S03 [15][16][17]; variant recorded: the Communities bar slot is absent on this phone (server state), so the with-tab re-tap route is not exercisable |
| V17 OFF renders normally | PASS | S02 (pixel-diversity judged; this build's guest screens carry no vote/share a11y labels) |
| V18 every Home tap opens search | PASS | S01 (hook 6 proved, blank Home never after a tap flow) |
| V19 Hide Inbox toggle | PASS | S03 [19] (hides both bar Inboxes, OFF restores) |
| V20 zero state, no Trending | DEFERRED | the ONE permitted attempt FAILED on device (Trending sections still render; hook verified matched/injected/read-back); **owner accepted as shipped, option (a), 2026-11-10** - recorded above and in the stage-B report |

## Changes

- 2026-11-11 - V3's S00 check redefined for the finished state: from "zero product diff"
  (S0's unmodified-baseline invariant, which the feature's landing necessarily breaks) to
  "the product diff is confined to the six allowed product files" - the discipline the
  plan has stated all along. LOOSENED in the strict sense (six named files vs zero);
  the reason: the zero-diff form was S0's temporary invariant and the six-file limit is
  the design's own rule; any seventh product file still fails the check.
- 2026-11-11 - S03's V7 top-bar wait extended: the bar's attach can lag 30+ s (measured
  device truth) and the fallback's 12 s poll raced it - the raw `checkpoint.sh all` run
  failed V7 once that way (it had passed the same code twice earlier today). The
  fallback's budget is now 45 s and the first reach polls 15 s instead of single-dumping.
  Not a loosening - a poll budget covering a measured lag.
- 2026-11-11 - The owner made the final-gate calls: **the gate encodes the decision** -
  since S03's sole red is V20 (red-accepted), the raw `scripts/checkpoint.sh all` verdict
  stays an honest FAIL and the S04 gate asserts each checkpoint's RECORDED verdict
  instead (S03 = 20/21 with V20 the single failing check by owner decision); the raw run
  is still shown in the final report. **Reviews stay deferred** (reaffirmed).
  LOOSENED: S4's review-prompt check ("the review prompt has been run and its findings
  file exists") no longer blocks the gate - it asserts that the owner's recorded
  deferral stands instead. Nothing else proves less: the covered/deferred table and the
  V3 re-sweep are new, harder checks.
- 2026-11-10 - The owner called V20: **option (a), accept as shipped.** The zero-state
  filter's ONE permitted device attempt failed (the pre-typing search page still renders
  Trending / Trending Communities / the trending shelf; `evidence/S03.log` check [20] and
  `evidence/S03-search-zero-state-after.png`). The hook site is the repository's terminal
  publisher, verified matched, injected and read-back verified, so the row stays red with
  this decision recorded - no second site, no re-attempt, nothing loosened. V20 is the
  only red row going into the final gate's covered/deferred table.
- 2026-11-10 - S2 is green on the phone (S02, 13/13): the OFF setting is stock (the switch
  is driven through Morphe settings and verified on the switch itself; the stock feed is
  judged by the screen's pixel diversity because this build's guest screens carry no vote/
  share a11y labels), the ON landing stands (cold start search, Home-tap flow to the top
  bar), and the toggle round-trips. `docs/steps/S02.md` and the stage-A report are in, and
  the independent review is due over the day's range. S03's script and evidence are
  committed with them: the gauntlet is green except V7 (a ColorOS install sheet blocks the
  flow - pending a dismissal fix), V14 (a navigation gap), and V20, whose one permitted
  attempt FAILED - the zero state still shows Trending sections, stop-and-report per the
  owner's brief, no second site.
- 2026-11-10 - S1 is green on the phone (S01 rewritten to the owner's spec, 18/18): cold
  start opens search by itself (hook 5 proved on device), Back out of it shows no feed and
  no crash, three Home taps in a row each open search and the bare blank Home page never
  appears (hook 6 proved), the Communities menu reaches the Morphe entry, guest search of
  r/soccer opens it and Back returns to search, logcat clean. One device finding folded
  back into the design note: backing out of the *cold-start* search does NOT attach the
  Communities top bar - the blank guarded `HomePagerScreen` stays (its attach never ran a
  tab selection); the top bar attaches through the Home-tap flow, which is where the check
  asserts it. Check mechanics learned on the way: `install -r` keeps the toggle, dumps are
  polled (the top bar and its menu lag >3 s), and uiautomator nodes carry an empty `text`
  attr before their `content-desc`, so a first-attr matcher hides content-desc-only labels.

- 2026-11-10 - The previously aborted patch run is re-run and **proves** the bundle: all 29
  patches apply, *Hide navigation buttons* among them, with every hook's read-back
  verification in place. Two blocks were found and cleared on the way: the zero-state
  fingerprint had pinned `returnType = "Ljava/lang/Object;"`, which compares as EQUALS against
  the publisher's real (obfuscated) return type and could never match - the return type is now
  deliberately unpinned, since the `(List, String, TypeaheadQueryMode)` parameter signature is
  unique in the class; and the publisher's 28 registers exceed the 4-bit register list of
  `invoke-static`, so the zero-state injection uses `invoke-static/range { p1 .. p2 }`
  (and `verifyInjectionAt` now accepts both opcodes). The zero-state hook stands on the
  repository's terminal publisher - the hydrate site is unusable, the inline smali compiler
  emits nothing for its five-parameter shape - and the design note's zero-state section is
  rewritten to match.
- 2026-11-09 - The owner took the handover's three
  pending decisions and the design note is amended a third time (the *Third amendment*):
  cold start opens search by itself via hook 5 (the guarded `HomePagerScreen`'s attach -
  the blank page is that screen, `BottomNavScreen` builds it directly, so no tab-selection
  site can decide the first screen; this is deliberate new design work, not a third fix on
  the old approach), every bottom-bar Home tap opens search via hook 6 (the bottomnav
  Function0 tap handler, rewritten before any comparison, so the already-selected branch
  can no longer skip the funnel and land the bare blank Home page), all launches share one
  debounced helper (~1 s, WeakReference context for the tap path, failures logged), a
  *Hide Inbox button* toggle drives `Inbox` and `UnifiedInbox`, and the search zero state's
  Trending sections are removed through the repository's zero-state hydrate funnel
  (`RedditDynamicTypeaheadAndZeroStateRepository`, read from APK bytecode where jadx
  failed). S01's check is rewritten for all of it, the coverage table gains V18-V20, and
  S03 must cover every remaining row incl. V12 and all V16 routes with and without a
  Communities tab. Hooks 2-3 stay as committed, now checked under S02's run.
- 2026-11-09 - Stale-build risk closed: device checks always install the freshly patched
  build with `install -r` (data, toggle and guest state kept), so no check can run against
  an older build; the `getStartTab` marker-based "already installed" skip is gone.
- 2026-11-09 - Device facts recorded from the owner's hooks-2-3 phone (not in evidence/):
  the cold-start blank page is the guarded `HomePagerScreen`; from search the first Back
  closes the keyboard and the second shows the Communities top bar (`Open community menu`,
  `search on Reddit`) - the handover's "same blank state" was wrong for this flow; repeated
  Home taps can land the bare blank Home page via the tap handler's already-selected branch,
  which skips hook 3; a left swipe on that page does not open the drawer, so the Communities
  top bar's menu (Morphe entry) is the settings route and must stay reachable; guest search
  of a subreddit, opening it and Back to search all work.
- 2026-11-09 - S2's hooks 2-3 (`initial_tab` default read, selection funnel) implemented the
  structural way, with the same index-0/after-sget read-back verification. The cold start
  still does not attach the Communities screen, but tapping the bar's Home button now reaches
  it through hook 3: the Communities screen attaches, the once-per-process search fires, and
  the app is usable. The funnel path (hooks 3+4, the search link) is proved on the phone; only
  the initial cold-start screen install does not attach. Ownership decision recorded in
  `docs/decisions/S01-communities-tab.md`: superseded by the third amendment (hook 5 opens
  search on the cold-start attach, so one-tap landing is moot).
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
