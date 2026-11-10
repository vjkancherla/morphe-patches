# HANDOVER - Hide Home Feed, full speed to delivery

Written 2026-11-10 late, at the owner's word: **reviews are deferred; push to delivery**.
The next session starts at "First actions, in order". This document replaces the
2026-11-09 handover entirely; the artefacts it points to carry the history.

## Owner calls still open (the only blocking ones)

1. **V20 - the search zero-state filter's ONE attempt failed on device.** With *Hide feeds*
   ON, the pre-typing search page still shows **Trending** (trending searches),
   **Trending Communities**, a **Trending shelf card** ("Chelsea FC", "Pawan Kalyan
   Announces Divorce") alongside the recent searches ("Recent", history rows) - no crash,
   recent searches intact, but the sections are NOT removed. Evidence:
   `evidence/S03.log` (check [20]) and `evidence/S03-search-zero-state-after.png`.
   The hook site is the repository's terminal publisher
   `a(List, String, TypeaheadQueryMode)` of `com/reddit/typeahead/data/f` - verified
   matched and injected (read-back verify passes), so the injection is exactly where it
   claims to be, and the data-side filter simply never sees models whose `toString()`
   starts with `SearchTypeaheadList(`/`SearchTrendingQuery(`/`SearchTypeaheadSuggestion(`
   **or** sees a different list than the page renders. Per the owner's brief: stop and
   report; **no second site may be improvised.** Options for the owner: (a) accept the
   Trending sections as shipped (the row stays red with a reason), (b) reopen design for
   a sanctioned approach, (c) drop V20 from scope. Nothing may proceed on V20 without
   this call.
2. **`.opencode/rules/hide-home-feed.md`** still carries an uncommitted earlier-session
   edit ("Consulting Claude", +70 lines) - not this work; commit or discard at the owner's
   word. It is also where the stage-end rule says to write stage reports from a
   `docs/stages/TEMPLATE.md` that was just deleted (owner's instruction;
   `docs/REVIEW-PROMPT.md` governs review now) - the rules file needs that one line
   struck BY THE OWNER.
3. **Reviews deferred** (owner, 2026-11-10): the stage-A report exists
   (`docs/stages/A.md`, review line filled in) but no review has run. Delivery proceeds
   without it unless the owner says otherwise.

## Exact state

- Branch `feat/hide-home-feed`, local only, never pushed. HEAD `3597d9da0`.
- The patch pipeline **proves green end to end**: `./gradlew buildAndroid` produces
  `patches/build/libs/patches-2.1.0.mpp`; morphe-desktop applies **all 29 patches** with
  `failedPatches: []` (`build/ckpt/result.json`); every hook's read-back verify
  (`verifyInjectionAt`) passes. Fixed this session: the zero-state fingerprint's
  impossible `returnType = "Ljava/lang/Object;"` pin (full class-name declarations compare
  as EQUALS; the return type is now unpinned because the `(List, String,
  TypeaheadQueryMode)` parameter signature is unique in the class), and the publisher's
  28-register parameter space (`invoke-static/range { p1 .. p2 }` - the 4-bit
  `invoke-static` register list caps at v15).
- Six allowed product files + docs, all committed: hooks 1-6, feed guards, the zero-state
  filter, the *Hide Inbox button* toggle (key `morphe_hide_inbox_button`, default off),
  with the extension shared-launch helper (~1 s debounce, once per process, WeakReference
  tap context, failures logged, never a crash).
- Device runs (phone `5e7ec3a8`): S0 green 8/8; **S1 green 18/18**
  (`evidence/S01.log` - S01 rewritten to the owner's spec: cold start opens search by
  itself; Back out of it no feed/no crash; three Home taps each open search and the bare
  blank Home page never appears; the Communities menu reaches Morphe; guest r/soccer
  round-trip; logcat clean). **S2 green 13/13** (`evidence/S02.log` - the OFF setting is
  stock; ON landing stands; toggle round-trips).
- **S3 NOT green** (`evidence/S03.log`, script `scripts/checks/S03.sh`): 18 of 21 checks
  pass; the failing three: **V7** (a ColorOS post-install sheet - "Installed / Version
  2026.45.0 / 160 MB / Close" - parks over the front window after `install -r` and blocks
  the flow; the `dismiss_overlays` helper taps Close but the sheet was still up when V7
  dumped: the tap is not landing or the sheet reappears; needs a tap-then-verify-gone
  loop with a BACK fallback), **V14** (the composite-toggle check failed because the
  state chain still contained the search page where the bar dump was expected - a
  navigation gap around `close_search_with_back` +
  `wait_for_ui` after `leave_settings` - needs a state
  re-establishing cold start before the Create-removal assertion), **V20** (above, owner
  call). V12 (cold external r/<sub> link) PASSES; V9 (Back never reaches the Home feed)
  PASSES; V19 (Inbox toggle round-trip on device) PASSES.
- S03 also: V15 rotation - passed; V16 route coverage - passed with the variant recorded
  (the Communities bar slot is absent on this phone: server state; the re-tap route is
  recorded as not exercisable).

## What remains for delivery

- Fix S03's V7 and V14 (harness, no product code) and re-run `scripts/checkpoint.sh 3`
  until those are green. V20's known-true failure stays recorded as-is pending the owner's
  call above - do not re-attempt it, do not loosen it, do not remove it.
- Then Stage C per the plan: `scripts/checkpoint.sh all` from a cold start, every
  Verification row covered-or-deferred, the final gate's Diff discipline, and the S4
  hand-off items in `docs/build-plan.md` ("Final gate and hand-off report").
- `docs/steps/S03.md` and the stage-B report (`docs/stages/B.md`) are the remaining
  artefacts once S3 settles; stage reports follow no template now (see owner call 2, the
  rules file's stray line) - plain report plus the filled-in REVIEW-PROMPT range line.

## First actions, in order

1. Fix `dismiss_overlays` in `scripts/checks/S03.sh` (V7): after tapping Close, re-dump,
   require the sheet's texts gone; if still up, press BACK, re-dump, and require Reddit in
   front (the harness error rule still applies - a dump of anything not Reddit is an
   error, never a result).
2. Fix V14 in the same file: after `leave_settings`, do a full `cold_start` and establish
   the search-page state with `wait_for_ui 'Search Reddit'` before asserting anything; the
   Create-removal assertion happens on the bar dump after `close_search_with_back`, and
   its `dump` must come from that state chain, never a stale variable.
3. `scripts/checkpoint.sh 3` - expect everything green except V20 (unchanged until the
   owner calls it).
4. Write `docs/steps/S03.md` + `docs/stages/B.md` with the honest checks table (18 green,
   V20 red pending decision).
5. Then S4's final gate. Do NOT run `scripts/checkpoint.sh all` while V20 blocks 3 - it
   fails and that is correct until the owner decides. First pencil the "covered / deferred
   with reason" table for the plan's Done row: every Verification row of
   `docs/design/hide-home-feed-v2.md` accounted for, V20 deferred with the owner's
   decision recorded once given.
6. Commit every step's evidence log with its work; keep the rules-file question for the
   owner; keep the branch un-pushed.

## Facts not to re-derive

- Toolchain: `source ~/.zshrc` gives JDK 21 + ANDROID_HOME; project root only for
  checkpoint invocations; patch command
  `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch -p patches/build/libs/patches-2.1.0.mpp -o build/ckpt/patched.apk -r build/ckpt/result.json <the 2026.45.0 .apkm>`; adb at `../android-sdk/platform-tools/adb`; the ColorOS install sheet is
  polled+tapped by each check's `confirm_install_sheet`; gate on `dumpsys window policy`
  `mIsShowing=false`.
- Device truths (2026-11-10): backing out of the cold-start search lands the blank guarded
  `HomePagerScreen` - NO Communities top bar (bar labels only, 30+ s); the top bar arrives
  through a Home-tap flow (hook 6 -> search -> Back). The top bar and its menu lag several
  seconds - checks poll (`wait_for_ui`), never fixed sleeps. The stock OFF home shows its
  own chrome: search pill (`Search Reddit`), `Log in`, hamburger (`Open community menu`),
  and NO a11y vote/share labels - "renders normally" is judged by screencap pixel
  diversity (`content_pixel_score`: blank ~hundreds, feed ~thousands). The stock home's
  hamburger menu holds: Popular, Morphe, About, Reddit Rules, User agreement,
  Acknowledgements - NO Discover row (variant recorded in S02/S03).
- uiautomator mechanics: every node has a `text` attr (often empty) BEFORE
  `content-desc` - a first-attr matcher hides content-desc-only labels; both attrs are
  scanned per node (`node_center` in S01/S02/S03). The Morphe switches read truthfully on
  their `checked` attr, and each toggles via its row's checkable node (row band =
  title node's y-range).
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
looping; Morphe settings unreachable; a guard fingerprint miss. For V20: no second site,
no re-attempt outside the owner's call. Nothing is loosened without marking `LOOSENED:`
in the plan's Changes log.

## Where the artefacts live

- Plan + Changes log `docs/build-plan.md`; design `docs/design/hide-home-feed-v2.md`
  (third amendment included); decision note `docs/decisions/S01-communities-tab.md`;
  tracker `docs/todo.md`; step summaries `docs/steps/S01.md`, `S02.md`;
  stage report `docs/stages/A.md` (REVIEW-PROMPT range line filled in; no stage template
  any more - `docs/REVIEW-PROMPT.md` governs review whenever the owner revives it).
- Checks: `scripts/checks/S0{0,1,2,3}.sh` + `scripts/checks/lib.sh`/`env.sh`;
  evidence `evidence/S00.log`, `S01.log`, `S02.log`, `S03.log`,
  `S03-search-zero-state-after.png` (never edited).
- The patch result each build: `build/ckpt/result.json` (regenerated per run).
- Working rules: `.opencode/rules/hide-home-feed.md` (owner's pending edit, see above);
  runbook for the human: `RUNBOOK.md`.

## Rules that still bind

Guest mode only; never hard-code obfuscated names; a guard fingerprint miss must fail
patching; do not guard `CommunitiesTabScreen` or the search page itself (the filter is
data-side); keep the once-per-process flag on the attach launch; only the six allowed
product files; never edit an evidence log; `LOOSENED:` on any check that proves less; do
not push the branch; `.opencode/rules/` is never edited by the implementer.
