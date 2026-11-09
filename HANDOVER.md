# HANDOVER - Hide Home Feed, latest status

Written 2026-11-09 (after the hooks 2-3 device round). The build is stopped on the owner's
stop rule, with **two explicit decisions pending** (below). A reviewer only needs this file
plus the artefacts it points to.

## Settled design (v2, amended 2026-11-09)

`docs/design/hide-home-feed-v2.md`. When *Navigation bar → Hide feeds* is ON:

1. **No feed screen ever renders** (the five feed screens are guarded at their render
   method - discover, home, popular, latest, news). This is the guarantee and it held
   through every device run.
2. The **Home button stays in the bar** (owner amendment to v2: hiding it left no way back
   on a phone whose bar has no Communities slot) and leads to the empty start screen: every
   internal go-to-Home lands on the Communities tab (hooks 1-3).
3. On that tab's first attach per process, the app opens Reddit's own search page
   (`https://www.reddit.com/search`, ACTION_VIEW, own package, once-per-process flag).

Guest mode only; no login. The Communities bar slot is server-controlled and may be absent,
so every device check must pass with or without a Communities tab.

Decision note `docs/decisions/S01-communities-tab.md` is **RESOLVED**: Option A (hook 1
moved into S1 as a cold-start check) with the Home-stays amendment.

## Where we are (exact state)

- Branch `feat/hide-home-feed`, never pushed. Newer commits, oldest first:
  - `c27fc50f5` adopt the v2 no-feed, search-landing design
  - `2047f3387` five feed guards + hook 4 (view-passing search launch), S1 checks
  - `cc4da9217` S01 app-launch fix (resolved launcher activity) + S1 device-block record
  - `e6866df28` the missing-Communities-tab decision note (now resolved)
  - `5485c366e` **hook 1** (start-tab replacement) + S01 rewritten as cold-start check
  - `231b6aaf9` **hooks 2-3** (`initial_tab` default, selection funnel)
- Read-back verification is part of the patch now: after every injection the patch re-reads
  the claimed instruction index and fails the patch if the hook call is not there (5 feed
  guards at index 0, hook 1 at index 0, hook 2 right after its sget-object, hook 3 at index
  0). A fingerprint miss also fails the patch. Both are recorded by S01's result-file check.
- `scripts/checkpoint.sh 0` is green any time. `checkpoint.sh 1` fails honestly at the
  cold-start check (the stop condition below); `checkpoint.sh 2/3` do not exist yet.
- The phone currently has the hooks-2-3 build installed with *Hide feeds* ON (guest).

## What is proved on the phone (all fresh, repeated)

- With the toggle ON, **no feed ever renders**: cold start shows a blank page with no feed
  markers, the app stays alive, logcat shows no patch failure and no crash - across every
  run, including the unpatched-path states. The no-feed guarantee holds everywhere tried.
- The bar shows `Home Create Inbox You` (the Communities slot was server-emptied on every
  observed boot; on the first boot after a fresh install, once, it showed `Communities`).
- Morphe settings are reachable **as a guest** through the left drawer's *Morphe* entry,
  and *Hide feeds* was switched ON as a guest (the old open question is answered).
- Tapping the bar's **Home** button (hook 3's funnel) attaches the Communities screen and
  **opens the search page once per process** - the whole hooks 3+4+search-link pipeline
  works. The search page, as a guest, shows no login prompt and no vote/comment markers,
  and the keyboard opens by itself. Screenshot: `evidence/S01-search-zero-state.png`.
- Pressing Back from that search page returns to the same blank state (no crash).

## The stop condition (second fix attempt used)

**Cold start does not land on search.** `getStartTab` fires and returns `Communities`
(proved with temporary logs, removed since), and with hooks 2-3 in, the selected tab is
Communities too - but the redirected Communities screen **never attaches** (`L3`, hook 4,
never runs on cold start), so the search never opens by itself and the screen stays a
chrome-less blank page. Diagnosis from reverse-reading (not a fix attempt): `BottomNavScreen`'s
stack change listener (`bottomnav/b.java`) derives the highlighted tab from whichever screen
the stack shows, and the initial visible screen is not picked by hook 1's `I5` push - the
selection funnel the bar taps use is what attaches tab screens, which is why the Home tap
works and the cold-start install does not. v1's "I5 installs the first screen" does not
hold for the render path. No workaround attempted, per the owner's stop rule.

**Net user experience on this build:** open app → blank, feed-free page → one tap on the
bar's Home → search page → the app is fully usable, feed-free, guest.

## Decisions pending (owner)

1. **Cold-start landing.**
   - **A. Accept the one-tap landing (recommended).** Cold start blank is acceptable under
     v2's own priority ("a blank page is always an acceptable outcome"); search is one tap
     away. S2's checks then assert this flow with `LOOSENED:` on V5's auto-opening search.
   - **B. One more tracing pass** at the true cold-start selection site - a new fingerprint,
     fresh design work. This would be a third fix attempt on the same check (the rules allow
     it only as deliberate new design work, not as a third patch improvisation).
2. **A Search button in the bottom bar** (owner asked 2026-11-09: "the bottom bar has
   Home+Create+Inbox+You - I will never use Create and Inbox - add search there?").
   Options offered: (1) hide Create/Inbox, keep search one tap away via Home- no new UI;
   (2) re-point Create or Inbox's click to the search intent, icon stays Reddit's
   (misleading icon); (3) a true Search slot with Reddit's search icon/label - fresh design
   work and a device probe of the bar composable. Option 3 may make decision 1-B moot.
3. **The search zero state needs eyes**: the guest search page shows a *Trending* list
   before typing (trending searches + trending communities). Feed-like or acceptable?
   Screenshot in `evidence/S01-search-zero-state.png`.

## Grounded facts (do not re-derive)

- **Toolchain:** `./gradlew buildAndroid` → `patches/build/libs/patches-2.1.0.mpp`;
  `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch -p <bundle> -o <out> -r
  <result.json> $HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch...apkm`.
- **Device:** adb at `../android-sdk/platform-tools/adb` (not on PATH), serial `5e7ec3a8`;
  a secure keyguard adb cannot clear - gate on `dumpsys window policy` `mIsShowing=false`
  and keep the owner's phone awake; ColorOS install confirmation sheet is polled and tapped
  by `install_fresh`. A reinstall of the patched build over itself keeps data and settings
  (same signature); a fresh install wipes the toggle - the guest-toggle route above makes
  re-enabling scriptable.
- **uiautomator on this build:** the bar labels come through as text (`Home`, `Create`,
  `Inbox`, `You`); the search page shows as `Search Reddit` (its own hint text and a Back
  node). The chrome-less blank state shows only the bar labels.
- **Patch powders:** match structurally; `re6`/`jn90`/`hv2` are obfuscated build IDs used
  above only for reading the decompiled sources in `../reddit-decompiled/sources/` (raw
  jadx; never hard-coded into the patch).
- **Marking:** the installed build is identified by the `getStartTab` marker string in its
  dexes (S01's `installed_patched`). Any future build without a new marker string looks
  identical to the installed one and will be silently kept by `install -r` checks.

## Where the artefacts live

- Design: `docs/design/hide-home-feed-v2.md` (amended; v1 `hide-home-feed.md` stays as the
  hooks/why-sites record), decision: `docs/decisions/S01-communities-tab.md`.
- Plan + Changes log: `docs/build-plan.md`; tracker `docs/todo.md` (S0 ticked; S1 open);
  step summary `docs/steps/S01.md` (rewritten for the cold-start check).
- Checks: `scripts/checks/S0{0,1}.sh`; evidence `evidence/S00.log`, `evidence/S01.log`
  (the fresh failed run - checkpoint output, never edited) and the zero-state screenshot.
- Working rules: `.opencode/rules/hide-home-feed.md`; review workflow `docs/REVIEW-PROMPT.md`
  (runs at stage end, different model; no stage report yet because S1 is not green).
- Runbook for the human: `RUNBOOK.md`.

## Rules that still bind

Guest mode only; never hard-code obfuscated names; a guard fingerprint miss must fail
patching; do not guard `CommunitiesTabScreen`; keep the once-per-process flag on the search
launch; only the six allowed product files (`Settings.java`, base `strings.xml`,
`NavigationBarPreferenceCategory.java`, extension `HideNavigationButtonsPatch.java`,
navigation `Fingerprints.kt` and `HideNavigationButtonsPatch.kt`); never edit an evidence
log; `LOOSENED:` on any check that proves less; stop and report (no workarounds) on the
five stop conditions in the owner's brief (locked phone, broken search link, feed-like
search zero state, visible feed anywhere, cold start not attaching the Communities screen).
