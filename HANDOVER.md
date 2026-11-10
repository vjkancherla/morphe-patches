# HANDOVER - Hide Home Feed, latest status

Written 2026-11-09 late evening, mid-implementation of the owner's three decisions. The next
session must start at **"First actions tomorrow"** below. A reviewer needs this file plus the
artefacts it points to.

## Owner decisions (third amendment) - all three taken and in the tree

1. **Cold start opens search by itself** (one-tap landing rejected) - implemented as **hook 5**.
2. **The bar's Home button opens search on every tap; Create/Inbox hideable** - implemented as
   **hook 6** plus a new *Hide Inbox button* setting (key `morphe_hide_inbox_button`, default
   off, drives both `Inbox` and `UnifiedInbox`, placed after the Create toggle).
3. **Remove the Trending / Trending Communities sections from the search page before typing** -
   implemented as the zero-state filter; **not yet device-proven** (needs the S03 A/B dump).

The design note `docs/design/hide-home-feed-v2.md` has the full *Third amendment* sections
(hooks 5-6, shared launch, the search zero state, V18-V20 rows); build-plan S1-S3 and todo are
rewritten to match; the Changes log has the three new entries. The `LOOSENED:` plan for V5 is
withdrawn - auto-open is restored, S01 must prove it.

## Where we are (exact state)

- Branch `feat/hide-home-feed`, never pushed. **Nothing committed this session.** The working
  tree (all on top of `53d20059e`) has: docs (build-plan, design note, todo), the six allowed
  product files (`Settings.java`, base strings.xml,
  `NavigationBarPreferenceCategory.java`, extension `HideNavigationButtonsPatch.java`,
  navigation `Fingerprints.kt` / `HideNavigationButtonsPatch.kt`), and **one pre-existing
  uncommitted edit of `.opencode/rules/hide-home-feed.md`** (a "Consulting Claude" section,
  +70 lines) that came from an earlier session - it is not part of this work; raise it with
  the owner before committing it.
- `./gradlew buildAndroid` is green and produced the bundle with all new code.
- **The last morphe-desktop patch run was aborted mid-run** (the owner stopped it) - so the
  *fresh bundle has NOT yet been proven to patch*. First thing tomorrow: run the patch again
  and check the result file (command at the bottom).
- Hooks so far in the patch: feed guards (committed), hooks 1-3 (committed), hook 4 (this
  session: unchanged site, now with a read-back verify), hook 5 (new), hook 6 (new) and the
  zero-state filter (new). Every injection has a `verifyInjectionAt` read-back that fails the
  patch if the call is not exactly where claimed.
- Device: phone `5e7ec3a8` attached and unlocked earlier today; it still runs the hooks-2-3
  build with *Hide feeds* ON (guest). `install -r` keeps data and the toggle.

## What the hooks are (one line each, so tomorrow does not re-derive)

- **Hook 5**: injected at index 0 of `HomePagerScreen`'s attach override (the blank cold-start
  page is the guarded HomePagerScreen; `BottomNavScreen` builds it directly, so no
  tab-selection site can decide the first screen). It passes the View to hook 4's extension
  method `onStartTabAttached(View)`.
- **Hook 6**: injected right after the tap-handler's bar-item read (instruction index 5 of
  `Lcom/reddit/launch/bottomnav/a;->invoke`, an `iget-object` of field type
  `BottomNavTab`) - replaces the register with `onBottomTabTapped`, which (feature ON, tab
  Home) launches search and returns `Communities`; the handler continues normally, so the
  start tab still attaches underneath and its top bar (Morphe settings) stays reachable.
- **Search launch**: one shared `openSearchPage(Context)`; ~1 s shared debounce
  (`SystemClock.elapsedRealtime`, stamped before the attempt); attach hooks fire once per
  process through `searchLaunched` and store the View's context in a `WeakReference` for the
  tap path; a tap that launches sets the flag too; every failure logged, never a crash.
- **Zero-state filter**: `filterSearchZeroState(List, CharSequence)` removes, in place,
  shelves whose rows are trending; it is injected at the repository's terminal publisher and
  filters **only when the query is empty** (typed queries keep their suggestions).

## Key findings of today (do not re-derive)

- **The inline smali compiler emits NOTHING for a 5-param `(List, FilterValues, Z, List,
  ContinuationImpl)` method** - the zero state hydrate method. Reproduced directly against
  `InlineSmaliCompiler.Companion.compile` (jars in the temp recipe below); one- and
  three-parameter methods compile fine. This is why the filter lives on the repository's
  terminal publisher `a(List, String, TypeaheadQueryMode)` (three clean parameters): the same
  flow ends there, and the query check confines it to the zero state. Do not move the hook
  back to the hydrate method.
- **HomePagerScreen attach (`L3` in 2026.45.0)** vs its detach twin (`W3`): both public final
  void, one `View`, call super first. Attach is 2 registers / 4 instructions; detach is
  5 registers / 26 (dismiss + coroutine). `HomePagerScreenAttachFingerprint` matches by that
  shape (`custom`); `HomePagerScreenDetachFingerprint` pins the twin by the string
  `feedTransitionBehaviorProvider`; the patch asserts exactly 2 View-param void overrides
  exist and that the two fingerprints hit different methods.
- **Hook 6's handler**: synthetic `Function0` in `com.reddit.launch.bottomnav` (class `a`),
  `invoke()` contains the strings `loggedOutBottomSheetScreenFactory` and
  `feedRefreshPolicy` (unique to it); the tab read is `iget-object v3, v4,
  Lwf6;->a:Lcom/reddit/launch/bottomnav/BottomNavTab;` at instruction index 5; the
  already-selected branch (`N5(tab, true)`) and the funnel (`c.T(tab, false)` = hook 3) both
  come later, which is why rewriting before the comparisons fixes repeated Home taps.
- **Trending data model** (from the zero-state network parse `a.e`, read from bytecode):
  a section shelf is `SearchTypeaheadList(id=, children=...)` (`vzf0`); the *Trending*
  searches rows are `SearchTrendingQuery(` (`bzf0`); the *Trending Communities* rows are
  expected to be `SearchTypeaheadSuggestion(` (`v6g0`); recent rows are
  `SearchRecentSkeletonQuery(` (`yjf0`) before and `SearchRecentQuery(` (`ojf0`) after
  hydration. These are GraphQL/telemetry model names that appear in the classes' own
  `toString()` - they are domain strings, not obfuscated symbols. The shelf's children list
  is read at runtime by reflecting the shelf object's list-typed field (no obfuscated field
  name needed); an unrecognised shelf is never dropped.
- **Zero-state flow**: `handleGlobalZeroStateRequestOrdered` (`d`, cache list
  `w8r0.f` + timestamp `w8r0.g`) -> on miss `fetchFromNetworkAndCache` (`b`) with an empty
  query -> `hydrateRecentSkeletonItems` (`e`) fills recent skeletons from local history ->
  the terminal publisher publishes `mv10` to the state flow and returns `q5k0(lve0(...))`.
  **This flow is from bytecode reading; the extension's row-prefix filter is the one attempt
  allowed** - if the device A/B dump still shows the sections (or loses recent searches),
  stop and report what was found; do not improvise a second site.
- **Bytecode dumper** (may be gone by tomorrow; rebuild if needed): a small dexlib2 program in
  `/var/folders/t5/d576h93s1mj1kkt4ykx7hg5r0000gn/T/opencode/bcdump/` (`Dump.java`, `bc.sh`,
  dexes already extracted from the .apkm's base.apk). Recipe: extract `classes*.dex` from the
  `.apkm`'s `base.apk`, compile `Dump.java` with `smali-dexlib2-4220ae75f7.jar` +
  `smali-util` + `smali` from the Gradle cache (`com.github.MorpheApp.smali/...4220ae75f7`),
  run `Dump <dexdir> <class descriptor> [method-substring]`.
- A **fresh `install -r` over the hooks-2-3 build keeps data and the toggle**, so the S01
  rewrite must always install the freshly patched build (no marker-based skip) - the stale-
  build fix dropped from the owner's brief; not yet written into `scripts/checks/S01.sh`.

## First actions tomorrow, in order

1. Rerun the aborted patch and confirm the result file is clean (the bundle is current):
   `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch -p patches/build/libs/patches-2.1.0.mpp -o build/ckpt/patched.apk -r build/ckpt/result.json $HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm`
   then check `build/ckpt/result.json`: success true, `failedPatches` empty, and
   *Hide navigation buttons* applied. Also confirm with a fresh `./gradlew buildAndroid`
   first (the tree is uncommitted; nothing should have drifted).
2. Commit the tree (docs + the six product files) as one step commit - but NOT the
   `.opencode/rules` edit (owner's call). Suggested message: `feat(Reddit): Add hooks 5-6,
   Hide Inbox toggle and the search zero-state filter (S1, third amendment)`.
3. Rewrite `scripts/checks/S01.sh` to the owner's spec: always `install -r` the fresh build;
   launcher-dump-is-a-harness-error rule stays; assert, with the toggle ON as a guest:
   cold start opens search by itself (no login, no feed); Back until keyboard closed and the
   search page is gone - no feed, no crash; Home tap opens search, Back shows the Communities
   top bar; three or more Home taps (closing search between) each open search and the bare
   blank Home page never appears; the Communities menu reaches the Morphe entry; search a
   subreddit, open it, Back returns to search; logcat clean. Drop the old
   `installed_patched`/toggle-gate path. Remove any `LOOSENED:` plan for V5 wording from the
   plan's Changes log (the auto-open is restored).
4. `scripts/checkpoint.sh 1` until green; commit the evidence log with the step.
5. Write `scripts/checks/S02.sh` and `S03.sh`: S02 - hooks 2-3 device run (cold start, Home
   route, setting OFF) as its step check; S03 - every remaining V row incl. V12 (cold
   external `r/<sub>` link stays on top, no search over it) and all V16 routes **with and
   without a Communities tab** (add/remove the tab is a server state - exercise what is
   reachable and record which variant ran). Hooks 2-3 are committed but S2 is not done until
   its check exists and passes.
6. Trending last: reproduce the owner's pre-typing state facts on the phone, take the before
   dump of the empty search page, install the filter build, take the after dump. Sections
   gone + recent searches kept = V20 green; anything else = stop and report (one attempt
   only, per the owner's brief).

## Facts still to reproduce on the phone (owner's message today; not yet in evidence/)

- The cold-start blank page is the guarded HomePagerScreen (already established by tracing
  and by the phone facts; hook 5's attach-side approach must now prove itself on device).
- From search, the first Back closes the keyboard; the second Back shows the Communities top
  bar (`Open community menu`, `search on Reddit`) - the handover's old "same blank state"
  was wrong for this flow.
- Repeated Home taps landing the bare blank Home page (via the already-selected branch) -
  hook 6 must prove they cannot any more.
- A left swipe on the bare blank Home page opens no drawer; Morphe settings are reached
  through the Communities top bar's menu - S01/S03 must keep that reachable.
- Guest search "soccer" -> open r/soccer -> Back returns to search (worked yesterday).

## Stop conditions (owner's brief today, all still binding)

Phone locked or not attached; a login prompt; any feed visible at any moment (subreddit
pages the owner opens excepted); search launching twice or looping; Morphe settings
unreachable; cold start still not landing on search after hook 5. For the trending attempt:
if the one site fails the A/B dump, stop and report - no second site.

## Grounded facts (from the previous handover, unchanged)

- **Toolchain:** `./gradlew buildAndroid` -> `patches/build/libs/patches-2.1.0.mpp`; the
  patch command is in "First actions" above. `source ~/.zshrc` gives JDK 21 + ANDROID_HOME;
  adb at `../android-sdk/platform-tools/adb` (not on PATH), serial `5e7ec3a8`; gate on
  `dumpsys window policy` `mIsShowing=false`; the ColorOS install sheet is polled and tapped
  by the check's `confirm_install_sheet`.
- **uiautomator on this build:** bar labels come through as text (`Home`, `Create`, `Inbox`,
  `You`); the search page shows as `Search Reddit`; the chrome-less blank state shows only
  bar labels. A dump of anything that is not Reddit is a harness error.
- **Patch powders:** match structurally; the obfuscated build IDs (`re6`/`jn90`/`hv2`) are
  only for reading `../reddit-decompiled/sources/` - never hard-coded.
- **Tooling quirk worth remembering:** multiline `addInstructions` quietly dropped its first
  line on the 5-param hydrate method - do not trust multiline inserts on methods where the
  inline compiler is near its edge; `verifyInjectionAt` (read-back) is what caught it, and
  single-line injections with a void extension method are the proven shape (hook 4/5).

## Where the artefacts live

- Design: `docs/design/hide-home-feed-v2.md` (third amendment included); decision note
  `docs/decisions/S01-communities-tab.md`; plan + Changes log `docs/build-plan.md`; tracker
  `docs/todo.md`; step summaries `docs/steps/`; stage reports `docs/stages/`.
- Checks: `scripts/checks/S0{0,1}.sh` (S01 still the OLD one - rewrite it before running);
  evidence `evidence/S00.log`, `evidence/S01.log`, `evidence/S01-search-zero-state.png`
  (never edited).
- Working rules: `.opencode/rules/hide-home-feed.md`; review workflow `docs/REVIEW-PROMPT.md`
  (runs at stage end; no stage report yet - S1 is not green).
- Runbook for the human: `RUNBOOK.md`.

## Rules that still bind

Guest mode only; never hard-code obfuscated names; a guard fingerprint miss must fail
patching; do not guard `CommunitiesTabScreen` (and do not guard the search page itself - the
filter is data-side); keep the once-per-process flag on the attach launch; only the six
allowed product files; never edit an evidence log; `LOOSENED:` on any check that proves less;
do not push the branch; `.opencode/rules/` is never edited by the implementer.
