# HANDOVER - Hide Home Feed, parked at the crossroads

Written 2026-11-08 / 2026-11-09 night. The build is stopped on purpose. A stronger model
is asked to advise on a requirement change; this is everything it needs, in one file.

## The crossroads

**The settled design (docs/design/hide-home-feed.md, v1):** add *Navigation bar → Hide
Home feed*. When ON, the Home tab disappears, every internal go-to-Home lands on the
Communities tab, and on that tab's first attach the app opens Reddit's own community
drawer, which lists the **joined subreddits**. That list is the point: the app opens
straight onto the subreddits the owner reads. An anonymous account is the only way that
list exists - it is server-side data; Reddit's guest mode has no subscriptions, no
favorites, no "your communities" anywhere (verified: no bottom tab shows joined lists,
which is why the design routes through the drawer).

**The new requirement (owner, 2026-11-08):** *"I do not want to login to reddit."* The
drawer's data source disappears under that requirement. The owner confirmed they know
this reverses the original spec.

**What was offered at that moment, and where it stands:**

| Option | What it means | Cost | Status |
|---|---|---|---|
| Anonymous throwaway account | The settled design works as-is; the owner's real account is never touched. Signup is ~5 min, email optional. | Zero new scope. | Rejected - the owner said they do not want to log in at all. |
| Stored whitelist + custom surface | A subreddit list kept in Morphe settings (comma-separated; UI components exist), rendered as a tappable in-app list that needs no account. The drawer route, hooks 1-3 semantics and the design note's landing decision all get re-examined. | Real scope: the design note's own text says its drawer-screen-as-tab alternative "wins only after a spike"; a custom list inside Reddit's composables from an extension without Reddit's classpath is the hard part. Roughly a day+ and unknowns. The plan's Stage structure changes: S1's device gate stays closed, S2+ get redrawn. | **The crossroads. Awaiting design advice.** |
| Hybrid | Anonymous account now (S1 unblocks today), whitelist as a separate v2 design that can replace the drawer later without invalidating what lands. | Small. | Not chosen; keep on the table. |

Questions the stronger model should answer first: whether a no-login whitelist is
realistically buildable from *within the extension* (loading subreddits needs either a
fake account session, guest mode with manual r/<sub> opens, or a custom Surface inside
Reddit's navstack), and what the smallest honest version of that list looks like.

## Where we are (exact state)

- Branch `feat/hide-home-feed`, never pushed. Two commits landed:
  - `101422f0d` - S0: artefacts + harness + green baseline gate (6/6 checks).
  - `8cea1dedb` - rules file gained the git-branch discipline section.
- One commit about to be made at pause: the full S1 spike code (see below) + `HANDOVER.md`.
- S0 checkpoint is green re-runnable any time: `scripts/checkpoint.sh 0`.
- S1 checkpoint is green up to the owner gate and parked deliberately: `scripts/checkpoint.sh 1`
  stops honestly at "app signed in and set up" (check [5]) - that is by design, not a bug.

### What S1 built and proved (compiles, patches, ships)

Six files, all within the design's allowed list:
- `Settings.java`: `HIDE_HOME_FEED` added (default off).
- `strings.xml` (base values only): its title.
- `NavigationBarPreferenceCategory.java`: the toggle, first in the category.
- Extension `HideNavigationButtonsPatch.java`: `StartTabScreenInterface` +
  `onStartTabAttached` (once-per-process, delayed drawer call, failures logged, app keeps
  working unpatched). Delay is a deliberate 1500 ms ponytail pending a real device tune.
- Navigation `Fingerprints.kt`: two structural fingerprints - the tab-attach proxy call
  (discriminates `L3` from `W3` via the one-arg proxy call) and the nav-icon handler
  lambda (string `communityNavIconClickHandler` + an iget of a screen field).
- Navigation `HideNavigationButtonsPatch.kt`: hook 4 injection after the proxy call, plus
  the added `patch_openCommunityDrawer()` method - provider field, provider type and the
  drawer call are all resolved from matched instructions at patch time; nothing obfuscated
  is hard-coded.

Proved on the machine: build green; Morphe Desktop patches 2026.45.0 with **29/29 applied,
zero failed**; `patch_openCommunityDrawer` verified inside the shipped dexes (classes15 +
classes17) and inside the APK installed on the test phone.

Proved on the device (OnePlus 13, CPH2649, Android 16): the patched build cold-starts
clean (no crash, no patch exceptions in logcat), and the install-confirm friction was
automated (see device facts). The app is at its logged-out home screen (guest-start patch
forces guest browsing on cold start; the "Log in" text is the guest-mode entry, not a
blocked state).

### What S1 has NOT proved (the parked half)

That tapping Communities opens the subreddit drawer through the injected route - the
riskiest assumption the whole design hangs on. It cannot be proved without an account
(the drawer's joined section is account data). If the crossroads resolves to the
whitelist design, this check gets redefined; if it resolves to any-account, sign in on
the phone once and `scripts/checkpoint.sh 1` finishes the step as written.

## Grounded facts the next session needs (do not re-derive)

- **Toolchain:** `./gradlew buildAndroid` → `patches/build/libs/patches-2.1.0.mpp`;
  `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch -p <bundle> -o <out> -r <result.json>
  ~/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch...apkm`. Result file is clean
  JSON (`success` / `failedPatches` / `appliedPatches`). The Settings patch is nameless and
  arrives as a dependency of "Hide navigation buttons".
- **Device:** adb at `../android-sdk/platform-tools/adb` (not on PATH). Serial `5e7ec3a8`.
  OnePlus 13 locks its screen in under a minute - wake (`input keyevent KEYCODE_WAKEUP`)
  + swipe-up, or UI dumps return lock-screen content. ColorOS shows an on-device
  **install confirmation sheet** for every `adb install` ("Continue installation"); S1's
  `install_fresh` already polls and taps it. Installing patched Reddit wipes the app's
  data (accepted disposable state).
- **Patch powders:** fingerprints here hatch structurally (strings + field/call filters) -
  names like `f1`/`sps`/`pjb`/`re6` are obfuscated and must come from matched instructions.
  One useful detail: `pjb.a()` emits Unit on a `MutableSharedFlow` with `DROP_OLDEST` and
  **no replay** - the reason the drawer call is delayed.
- **Check rule:** every step runs through `scripts/checkpoint.sh <N>`, evidence log is
  committed with the step and never edited, and a check that proves less must be logged
  with `LOOSENED:` in the plan's Changes log (all in `.opencode/rules/hide-home-feed.md`).

## Where the artefacts live

- Design + decision + why: `docs/design/hide-home-feed.md` (v1; read the Verification
  table and "Roads not taken" for the terminal context - especially the
  drawer-screen-as-tab alternative that the whitelist direction would revisit).
- The plan + live Changes log: `docs/build-plan.md` (with the coverage map of the
  design's V1-V15 verification rows).
- Tracker: `docs/todo.md`. Step summary written before code: `docs/steps/S01.md`.
- Working rules (the implementing agent obeys these): `.opencode/rules/hide-home-feed.md`,
  loaded via `opencode.json`. Review workflow: `docs/REVIEW-PROMPT.md`, run at stage end
  with a different model.
- Runbook for the human: `RUNBOOK.md`.

## Files changing under any crossroads outcome

If the whitelist direction wins: design note v2 first, then the plan's Stage structure
redrawn; the S1 spike's injection machinery and the setting string stay reusable; hooks
1-3 (start-tab replacement) survive in any design that opens subreddits instead of Home.
If the whitelist needs a custom rendered list, the drawer route and hook 4 may be dropped
entirely with their checkpoints fenced off rather than deleted.
