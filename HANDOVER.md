# HANDOVER - Hide Home Feed, full speed to delivery

## Session close 2026-11-12 - the credential storm, found and fixed

The **credential storm** (a Google credential-chooser sheet parking over every Reddit
launch) was root-caused and fixed this session. Nothing in the product code had changed;
tripwire stacks pinned both launch-time credential asks to `RedditCredentialsDataSource`'s
R8-moved body (found structurally), and a fresh install STILL fired the sheet - the wedged
state is Google-side, keyed to the package identity and this fork's signing key (the
owner's separately signed 2026.40.0 phone build never stormed). Fixes, both committed:

- **4a** (25f758fb1): the datasource returns the flow's own no-credential result at
  entry - references read off the method's own bytecode, no obfuscated names; log
  tripwires (`MorpheCred`) stay. Hook 7 was reverted first (it hard-coded R8 field `a`).
- **4b** (f61021043, owner-approved: the fork has no sign-in surface): Reddit's
  forced-login gate returns false, so a fresh install no longer cold-starts into the
  welcome/login flow (`IntroductionActivity`) - which had made the settings flow
  unreachable on both Hide-feeds states.
- Verified: 20/20 scripted cold starts land on search, no sheet, no welcome screen;
  raw `checkpoint.sh all` = S00 6/6, S01 18/18, S02 13/13, S03 20/21 (V20 red-accepted,
  same signature); **S04 final gate PASS 8/8** (evidence/S04.log) - the only place the
  V20 exception applies; raw verdict stays FAIL by design.
- **V11 is manual** (not one of S03's 21 checks): sign-off place is
  `scripts/checks/S04-v11-signoff.txt` - PENDING the owner's sign-off.
- Reinstalling: follow `docs/REINSTALL-REDDIT.md`. Two device truths recorded there and
  below: **Android backup restores Reddit's settings on reinstall** (a fresh install came
  up with the toggles ON before any tap), and the signing key matters to Google's
  per-app credential state.

Rewritten 2026-11-10 late-night, session close at the owner's word. The owner took the
open V20 call this session (**option (a), accept as shipped**), the V7/V14 harness fixes
landed and proved green on device, and the session was cut during the final clean run's
V19. The next session starts at "First actions, in order". This document replaces the
earlier 2026-11-10 handover entirely.

## Owner calls still open (the only blocking ones)

1. **`.opencode/rules/hide-home-feed.md`** still carries an uncommitted earlier-session
   edit ("Consulting Claude", +70 lines) - not this work; commit or discard at the owner's
   word. It is also where the stage-end rule says to write stage reports from a
   `docs/stages/TEMPLATE.md` that was deleted (owner's instruction;
   `docs/REVIEW-PROMPT.md` governs review now) - the rules file needs that one line
   struck BY THE OWNER. Still unresolved.
2. **Reviews deferred** (owner, 2026-11-10): the stage-A report exists
   (`docs/stages/A.md`, review line filled in) but no review has run. Delivery proceeds
   without it unless the owner says otherwise. Still unresolved.

RESOLVED this session: **V20 - the owner accepted it as shipped (option a).** The
zero-state filter's ONE permitted device attempt failed (the pre-typing search page still
renders Trending / Trending Communities / the trending shelf; evidence
`evidence/S03.log` and `evidence/S03-search-zero-state-after.png`). The hook site is the
repository's terminal publisher, verified matched, injected and read-back verified. The
decision is recorded in `docs/build-plan.md` (Changes log entry + the V20 row of the
coverage table). The row stays red with the reason; **no second site, no re-attempt,
nothing loosened**; V20 is the only red row going into the final gate's
covered/deferred table.

## Exact state

- Branch `feat/hide-home-feed`, local only, never pushed.
- The patch pipeline **proves green end to end**: `./gradlew buildAndroid` produces
  `patches/build/libs/patches-2.1.0.mpp`; morphe-desktop applies **all 29 patches** with
  `failedPatches: []`; every hook's read-back verify passes. Unchanged this session.
- **S3 is now 20/21**: V7 and V14 are FIXED (green on device this session); V19 passed in
  every full run; V20 is red BY OWNER DECISION (above), recorded, correct, untouchable.
- Harness fixes landed in `scripts/checks/S03.sh` (no product code touched):
  - `dismiss_overlays`: tap Close -> re-dump -> require the sheet's texts gone; if still
    up, press BACK -> re-dump -> require gone; then **require Reddit in front** (the BACK
    fallback can exit the app - observed); loud failure with the front window and dump if
    it survives 3 rounds. `cold_start` propagates the failure.
  - New `bring_reddit_front` helper (resume without force-stop); `cold_start` reuses it.
  - `top_bar_search_button`: dismisses the sheet at point of use - the ColorOS app-details
    sheet pops up BETWEEN the entry check and V7 (observed twice), after every
    install-time dismissal window - and requires Reddit in front before reading state.
  - **V7 tap fix**: this build's top bar carries the search pill as
    `content-desc="search on Reddit"` and there is NO plain `Search` node - the old
    `tap_node "Search"` silently matched nothing and never tapped. It now taps
    "search on Reddit" (with "Search" as fallback) and fails loudly if neither exists.
    Verified live on the device: tapping the pill opens the search page.
  - **V14 fix**: after the toggle + `leave_settings`, the state chain is re-established -
    `cold_start`, then `wait_for_ui 'Search Reddit' 20` (polled, not assumed), explicit
    failure if `close_search_with_back` fails, and the Create-removal assertion reads only
    the bar dump of that live chain, never a stale variable. Green in every run since.
  - `open_morphe_entry` fails fast when the search page will not close.
- Run history this session (evidence/S03.log holds the LAST one only - the runner
  overwrites): run 1 = 18/21 (V7, V14, V20); runs 2-4 = only V7 + V20 red, each with a
  different V7 shape (sheet over the bar; launcher in front; silent no-tap) - which is
  what drove the three fixes above; **run 5 = checks 1-18 ALL GREEN** (V7 green, V14
  green) and the owner cut the session during V19, so the log has no finish verdict.
- Phone note: the cut left the phone mid-V19 (the *Hide Inbox* switch may be ON and the
  app wherever V19 left it). Harmless: every S03 run reinstalls the fresh build and its
  toggles converge (`set_morphe_toggle` flips until the desired state reads true).
- S0 8/8, S1 18/18, S2 13/13 all remain green (`evidence/S00.log`, `S01.log`, `S02.log`).

## What remains for delivery

DELIVERED 2026-11-12: the clean runs exist, the final gate is written and green
(`scripts/checkpoint.sh 4` -> S04 PASS 8/8, evidence/S04.log; raw `all` = S00 6/6,
S01 18/18, S02 13/13, S03 20/21 with V20 red-accepted; the stage-C hand-off report is
`docs/stages/C.md`). What remains is the owner's V11 sign-off
(`scripts/checks/S04-v11-signoff.txt`), the still-deferred stage reviews, and the
owner-owned housekeeping below.

Superseded context (pre-delivery, kept for the record):

- ONE clean full re-run: `scripts/checkpoint.sh 3` - expect everything green except V20
  (red by owner decision, unchanged, do not loosen, do not remove). Its complete
  evidence log with the PASS-verdict-minus-V20 is what the stage report cites.
- Then Stage C per the plan: `scripts/checkpoint.sh all` from a cold start (now that 3
  settles green-except-V20, decide with the owner how `all` should treat the one
  red-accepted row - it fails and that is correct), every Verification row
  covered-or-deferred, the final gate's Diff discipline, and the S4 hand-off items in
  `docs/build-plan.md` ("Final gate and hand-off report").
- `docs/steps/S03.md` and the stage-B report (`docs/stages/B.md`) are the remaining
  artefacts once S3's clean run exists; stage reports follow no template now - plain
  report plus the filled-in REVIEW-PROMPT range line. The honest checks table: 20 green,
  V20 red with the owner's (a) decision recorded.
- Pencil the "covered / deferred with reason" table for the plan's Done row: every
  Verification row of `docs/design/hide-home-feed-v2.md` accounted for, V20 deferred with
  the owner's decision already recorded.

## First actions, in order

1. `scripts/checkpoint.sh 3` from the project root (`source ~/.zshrc` first for JDK 21 +
   ANDROID_HOME; phone attached and UNLOCKED - adb cannot clear the keyguard). Expect
   checks 1-21 green except [20] V20.
2. Write `docs/steps/S03.md` + `docs/stages/B.md` with the honest table (20 green, V20
   red-accepted) and note V11 (human finger) as flagged-not-skipped, as the log does.
3. Commit the clean evidence log with those artefacts; keep the branch un-pushed.
4. Then the final gate: the covered/deferred table, then `scripts/checkpoint.sh all`
   subject to the owner's word on the red-accepted V20 row.

## Facts not to re-derive

- **Android backup restores Reddit's settings on reinstall (measured 2026-11-12):** a
  fresh install of `com.reddit.frontpage` came up with the Morphe toggles already ON
  before anything was tapped - Android's device backup/restore carried the old install's
  `com.reddit.frontpage_preferences` (the Morphe extension's prefs live there) across the
  uninstall. Defaults are FALSE (`Settings.java`), so an ON state without a tap is the
  restore, not the defaults. Never conclude a toggle state from "it's a fresh install" -
  read the switch or verify behaviorally.

- Toolchain: `source ~/.zshrc` gives JDK 21 + ANDROID_HOME; project root only for
  checkpoint invocations; patch command
  `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch -p patches/build/libs/patches-2.1.0.mpp -o build/ckpt/patched.apk -r build/ckpt/result.json <the 2026.45.0 .apkm>`; adb at `../android-sdk/platform-tools/adb`; the ColorOS install sheet is
  polled+tapped by each check's `confirm_install_sheet`; gate on `dumpsys window policy`
  `mIsShowing=false`. Session cleanup for wrap-ups: `./gradlew --stop` +
  `../android-sdk/platform-tools/adb kill-server` (done at this session's close).
- Device truths (2026-11-10): backing out of the cold-start search lands the blank guarded
  `HomePagerScreen` - NO Communities top bar (bar labels only, 30+ s); the top bar arrives
  through a Home-tap flow (hook 6 -> search -> Back). The top bar and its menu lag several
  seconds - checks poll (`wait_for_ui`), never fixed sleeps. The top bar's search control
  is `content-desc="search on Reddit"`; there is no plain `Search` node on this build, so
  any tap that targets `"Search"` silently taps nothing - `node_center` returns empty on
  no match and callers must fail loudly, not skip. The stock OFF home shows its own
  chrome: search pill (`Search Reddit`), `Log in`, hamburger (`Open community menu`), and
  NO a11y vote/share labels - "renders normally" is judged by screencap pixel diversity
  (`content_pixel_score`: blank ~hundreds, feed ~thousands). The stock home's hamburger
  menu holds: Popular, Morphe, About, Reddit Rules, User agreement, Acknowledgements - NO
  Discover row (variant recorded in S02/S03).
- ColorOS sheet behaviour (all observed this session): the app-details sheet
  ("Installed / Version 2026.45.0 / 160 MB / Close") can pop up seconds AFTER the install
  completes - i.e., between checks - not only during `install -r`; tapping Close may not
  land and the BACK fallback can exit Reddit to the launcher instead of the sheet; hence
  tap-verify-gone -> BACK-verify-gone -> require-Reddit-in-front (resume via
  `bring_reddit_front` if the launcher won), all in `dismiss_overlays` plus a point-of-use
  call in `top_bar_search_button`.
- uiautomator mechanics: every node has a `text` attr (often empty) BEFORE
  `content-desc` - a first-attr matcher hides content-desc-only labels; both attrs are
  scanned per node (`node_center` in S01/S02/S03). The Morphe switches read truthfully on
  their `checked` attr, and each toggles via its row's checkable node (row band =
  title node's y-range). The harness `check` keeps only the LAST 10 lines of a failed
  check's output - long expected/found blocks get truncated from the top; when writing
  failure messages, put the dump lines LAST if they matter least.
- The inline smali compiler traps (both reproduced): it emits NOTHING for the 5-parameter
  hydrate shape `(List, FilterValues, Z, List, ContinuationImpl)`; multiline
  `addInstructions` on compilers near their edge silently drops lines - single-line
  inserts with void extension methods are the proven shape, and `verifyInjectionAt`
  (read-back) is what catches the residual cases. Parameter registers above v15 need
  `invoke-static/range`.
- Bytecode dumper if needed: `/var/folders/t5/d576h93s1mj1kkt4ykx7hg5r0000gn/T/opencode/bcdump/`
  (`bc.sh` runs `Dump <dexdir> <class-descriptor> [method-substring]`; dexes already
  extracted).

## Stop conditions (still binding)

Phone locked or not attached; a login prompt; any feed visible under the ON toggle
(subreddit pages the check opens deliberately are exempt); search launching twice or
looping; Morphe settings unreachable; a guard fingerprint miss. For V20: the owner's (a)
decision is recorded - the row stays red, no second site, no re-attempt, nothing loosened.
Nothing is loosened without marking `LOOSENED:` in the plan's Changes log.

## Where the artefacts live

- Plan + Changes log `docs/build-plan.md` (V20 decision recorded this session: Changes
  entry + the V20 coverage row); design `docs/design/hide-home-feed-v2.md` (third
  amendment included); decision note `docs/decisions/S01-communities-tab.md`;
  tracker `docs/todo.md`; step summaries `docs/steps/S01.md`, `S02.md`;
  stage report `docs/stages/A.md` (REVIEW-PROMPT range line filled in; no stage template
  any more - `docs/REVIEW-PROMPT.md` governs review whenever the owner revives it).
- Checks: `scripts/checks/S0{0,1,2,3}.sh` + `scripts/checks/lib.sh`/`env.sh`;
  evidence `evidence/S00.log`, `S01.log`, `S02.log`, `S03.log` (currently the ABORTED
  run 5 partial - replaced by the next clean run; never hand-edited),
  `S03-search-zero-state-after.png`.
- The patch result each build: `build/ckpt/result.json` (regenerated per run).
- Working rules: `.opencode/rules/hide-home-feed.md` (owner's pending edit, see above);
  runbook for the human: `RUNBOOK.md`.

## Rules that still bind

Guest mode only; never hard-code obfuscated names; a guard fingerprint miss must fail
patching; do not guard `CommunitiesTabScreen` or the search page itself (the filter is
data-side); keep the once-per-process flag on the attach launch; only the six allowed
product files; never edit an evidence log; `LOOSENED:` on any check that proves less; do
not push the branch; `.opencode/rules/` is never edited by the implementer.
