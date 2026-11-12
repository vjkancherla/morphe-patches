# Project Handbook - Hide Feeds for Reddit

A single consolidated reference for the Morphe Patches fork that adds a **Hide feeds**
mode to Reddit on Android. It gathers the goal, the design, the current state, every
command, and the open issues. The authoritative detail still lives in the linked docs;
this file is the map and the status sheet.

Last updated: **2026-11-12** (delivery closed: S04 final gate PASS 8/8, sign-in sheet fixed, branch pushed to `origin`).
Verified against **Reddit 2026.45.0** only.

---

## 1. What this project is

A personal fork of [Morphe Patches](https://github.com/MorpheApp/morphe-patches) with one
added feature: a **Hide feeds** switch for Reddit that makes the app usable without ever
rendering a feed.

The owner's stated intent:

- "I do not want to log in to Reddit."
- "When I open, I see the search page and not the feed page, and I will search for the
  subreddit I want to use."
- "I do not want to see the feed at all, this is critical."

How that became requirements:

| Requirement | How it is met |
|---|---|
| Never render a feed | Five feed screens are guarded at their render method |
| No login | Guest mode throughout; the featured build includes *Start as guest* |
| Open on search | The guarded Home screen's attach opens Reddit's own search link |
| Home button still works | Every Home tap opens search and lands on the empty Communities screen |
| Reach Morphe settings | The Communities top bar's menu stays reachable |
| Trending search sections gone | A data-side filter (attempted; see V20) |

The priority rule from the design note: **if goals conflict, no-feed wins. A blank page is
always acceptable. A visible feed never is.**

---

## 2. Status at a glance

| Area | State (2026-11-12) |
|---|---|
| Build (`./gradlew buildAndroid`) | **Green** - produces `patches/build/libs/patches-2.1.0.mpp` |
| Patch of 2026.45.0 | **Green** - all 29 patches apply, `failedPatches: []`, every hook read-back verified |
| S0 - toolchain baseline | **6/6 green** (`evidence/S00.log`) |
| S1 - cold start, guards, Home taps | **18/18 green** (`evidence/S01.log`) |
| S2 - OFF is stock, ON lands search | **13/13 green** (`evidence/S02.log`) |
| S3 - device gauntlet | **20/21** - V20 the only red (accepted as shipped); V11 is outside the 21 (manual) |
| S4 - final gate | **PASS 8/8** (`scripts/checks/S04.sh`, `evidence/S04.log`); raw `checkpoint.sh all` stays FAIL on V20 by design |
| Sign-in sheet ("credential storm") | **Fixed** 2026-11-12 by hooks 7-8 (section 4.6); 20/20 cold starts clean |
| Stage reviews | **Deferred** by the owner on 2026-11-10 |
| Branch | `feat/hide-home-feed`, pushed to `origin` (the owner's fork) on 2026-11-12 |

Stage-C hand-off report: `docs/stages/C.md`.

---

## 3. What the app does when it is working

With **Morphe -> Navigation bar -> Hide feeds** ON, as a guest:

1. **Cold start** - Reddit's search page opens by itself, keyboard up, no login prompt,
   no feed. This is hook 5.
2. **Back from that first search** - the first Back closes the keyboard, the second leaves
   the search page. The guarded blank Home page stays; the Communities top bar is *not*
   attached on this path (measured on the phone).
3. **Tap the bar's Home from anywhere** - search opens *every time* (hook 6). After Back,
   the Communities top bar is over the empty screen. The bare blank Home page is no longer
   reachable through taps.
4. **Communities menu** - the top bar's menu reaches the **Morphe** entry, which is the
   only way to Morphe settings on this phone.
5. **Subreddits** - a searched subreddit opens and works as a guest; Back returns to search.
   Subreddit pages are feeds by design, and are exempt from the no-feed rule because they
   are what the owner deliberately opens.
6. **Hide Inbox button** (optional, default off) - hides both `Inbox` and `UnifiedInbox`
   from the bottom bar.
7. **Search zero state** - the *Trending* and *Trending Communities* sections were meant to
   be removed. The one permitted attempt failed on device; the owner accepted the sections
   as shipped (see V20).

With the switch OFF, the app behaves as stock Reddit.

---

## 4. How it works

### 4.1 The guarantee - five render guards

Every feed in 2026.45.0 is a `ComposeScreen` whose render method has the same shape.
Blocking that method covers every route, including ones navigation hooks cannot see: the
drawer's Discover/Popular/Latest rows, deep links, and direct pushes.

| Screen | Class | Guard |
|---|---|---|
| Discover | `com/reddit/communitiestab/explore/ExploreFeedScreen` | `hideFeedScreen()` at render entry |
| Home | `com/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen` | same |
| Popular | `com/reddit/feeds/popular/impl/ui/PopularFeedScreen` | same |
| Latest | `com/reddit/feeds/latest/impl/ui/LatestFeedScreen` | same |
| News | `com/reddit/feeds/news/impl/NewsFeedScreen` | same |

The guarded method is matched structurally (public final, returns void, parameters
`(L, I)`) because its name is obfuscated. The extension method is one line: return the
`HIDE_HOME_FEED` setting. A fingerprint miss **fails the patch** - a build that cannot
guard a feed never ships.

`CommunitiesTabScreen` itself is deliberately **not** guarded: its top bar holds the
search button, drawer button and avatar menu, which are the way back to search and to
Morphe settings.

### 4.2 Navigation hooks 1-6

| Hook | Site | What it does |
|---|---|---|
| 1 | `getStartTab` (start-tab request) | Requests Communities instead of Home |
| 2 | `initial_tab` default read | A plain cold start with no tab extra installs Communities |
| 3 | Presenter selection funnel | Any programmatic/repeated Home selection becomes Communities |
| 4 | Communities tab's attach | Calls `onStartTabAttached(view)`; opens search once per process |
| 5 | Guarded Home screen's attach | Same extension method as hook 4; this is what makes the **cold start** land on search |
| 6 | Bottom-bar tap handler | Rewrites a Home tap to Communities and opens search **on every tap** |

Hooks 1-3 keep internal "go to Home" requests off the feed. Hook 5 exists because
`BottomNavScreen` builds `HomePagerScreen` directly, so tab selection cannot decide the
first visible screen. Hook 6 exists because the tap handler's "already selected" branch
could otherwise skip the funnel and show the bare blank Home page.

All three launch sites go through **one shared helper**:

- `WeakReference<Context>` stored by the attach hooks, read by the tap path.
- ~1 s debounce (`SystemClock.elapsedRealtime`) so a cold-start attach and an immediate
  tap do not double-launch.
- A once-per-process flag, set before the intent is fired, prevents loops.
- Every failure is logged and never crashes the app; the tap handler still returns the
  mapped tab.

Search is opened with `https://www.reddit.com/search` as an `ACTION_VIEW` intent restricted
to the app's own package. Reddit's own routing then shows `TypeaheadResultsScreen` - no
Reddit class names are hard-coded in the extension.

### 4.3 Search zero state (V20)

The pre-typing search page shows *Trending* (trending searches) and *Trending Communities*
shelves. The intended hook is the terminal publisher
`a(List, String, TypeaheadQueryMode)` of `com/reddit/typeahead/data/f`.
`filterSearchZeroState` runs only when the query is empty, drops a shelf only if at least
one of its rows is a `SearchTrendingQuery` or `SearchTypeaheadSuggestion`, and leaves
recent-search shelves untouched. It reads the shelf's list field by reflection, so no
obfuscated field name is used.

The hook is verified matched and injected, but the device still showed the Trending
sections. Per the owner's brief the attempt stopped; there is **no second site**, no
re-attempt, and nothing was loosened. The owner later accepted the sections as shipped
(option a).

### 4.4 Settings

| Setting | Key | Label | Default |
|---|---|---|---|
| Hide feeds | `morphe_hide_home_feed` | Hide feeds | OFF |
| Hide Inbox button | `morphe_hide_inbox_button` | Hide Inbox button | OFF |
| Existing nav hides | unchanged | Hide Create / Discover / Games / Answers / Chat | unchanged |

The two switches live under **Morphe -> Navigation bar**. The label changed from hiding
only Home to **Hide feeds** because it now covers five feed screens. The setting key did
not change, so an existing toggle survives an `install -r`.

### 4.5 Product files (the hard scope limit)

Only these six product files may change:

1. `extensions/reddit/src/main/java/app/morphe/extension/reddit/settings/Settings.java`
2. `patches/src/main/resources/addresources/values/reddit/strings.xml` (base `values/`)
3. `extensions/reddit/src/main/java/app/morphe/extension/reddit/settings/preference/categories/NavigationBarPreferenceCategory.java`
4. `extensions/reddit/src/main/java/app/morphe/extension/reddit/patches/HideNavigationButtonsPatch.java`
5. `patches/src/main/kotlin/app/morphe/patches/reddit/layout/navigation/Fingerprints.kt`
6. `patches/src/main/kotlin/app/morphe/patches/reddit/layout/navigation/HideNavigationButtonsPatch.kt`

Docs, `.opencode/`, `scripts/`, and `evidence/` are build artefacts, outside that list.
`../reddit/shared/Constants.kt` is **not** in scope (it declares version compatibility for
all Reddit patches).

### 4.6 Sign-in suppression - hooks 7-8 (added 2026-11-12)

On 2026-11-12 Reddit 2026.45.0 began showing Google's "Sign-in options / Unlock" sheet
about 5 s after every launch, even on a fresh install of the unchanged build. The likely
trigger is Reddit's server config turning on forced login for logged-out users. Two hooks
remove it; neither hard-codes an obfuscated name.

| Hook | Site | What it does |
|---|---|---|
| 7 | Credentials datasource (`RedditCredentialsDataSource`, R8-moved body) | Returns the flow's own NoCredentialException result at entry, so Reddit never calls Credential Manager. References are copied at patch time from the method's own bytecode, anchored on `androidx/credentials/exceptions/NoCredentialException`. Logs `MorpheCred: credential request suppressed` |
| 8 | Forced-login gate (`RedditForceLoginGate`) | Returns false, so a guest cold start never routes to `IntroductionActivity` (the welcome / sign-up screen) |

A log-only tripwire (`MorpheCred: credential request`) stays at the datasource entry.
Both hooks live in the six product files. Recovery after a reinstall:
`docs/REINSTALL-REDDIT.md`. Note: Android backup restores Reddit's settings on reinstall,
so a "fresh" install may come up with the toggles already ON.

---

## 5. Where everything lives

Workspace root: `~/Downloads/Devops-Projects/morphe-reddit/`

```
morphe-reddit/
├── morphe-patches/          the git repo (fork of MorpheApp/morphe-patches)
│   ├── patches/             patch bundle sources -> patches-2.1.0.mpp
│   ├── extensions/          runtime extension code injected into the APK
│   ├── scripts/             checkpoint runner + device checks
│   ├── evidence/            captured checkpoint logs and screenshots
│   ├── docs/                plan, design, steps, stages, this handbook
│   ├── build/ckpt/          patched.apk + result.json (gitignored)
│   └── HANDOVER.md          the last committed session handover
├── android-sdk/             Android command-line SDK (~2 GB)
│   └── platform-tools/adb
├── reddit-apk/              unpacked 2026.45.0 .apkm (base.apk + splits)
├── reddit-decompiled/       jadx output for recon (several GB)
├── tools/
│   ├── morphe-desktop-2.1.1-all.jar
│   ├── jadx/
│   └── morphe-data/
└── CLEANUP.md               which workspace folders are disposable
```

The original `.apkm` lives at
`~/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm`.

**Git remotes:** `origin` is `https://github.com/vjkancherla/morphe-patches.git`,
`upstream` is MorpheApp. The feature branch is **local only** - a fresh clone of `origin`
does not contain this work.

### Key documents

| Document | Purpose |
|---|---|
| `HANDOVER.md` | Last session handover: owner calls, exact state, next actions |
| `docs/build-plan.md` | Steps S0-S4, coverage map, **Changes** log |
| `docs/design/hide-home-feed-v2.md` | Current design note and Verification table |
| `docs/design/hide-home-feed.md` | v1 design; hooks 1-3 and build facts still apply |
| `docs/todo.md` | Tracker |
| `docs/steps/S01.md`, `S02.md` | Plain-English step summaries |
| `docs/stages/A.md` | Stage A report |
| `docs/decisions/S01-communities-tab.md` | The Communities-slot decision |
| `.opencode/rules/hide-home-feed.md` | Working rules for the implementing agent |
| `RUNBOOK.md` | The human's runbook for driving the agent |
| `docs/REINSTALL-REDDIT.md` | **How to put the app back on the phone after deleting it** |

---

## 6. Build, patch, install

All commands run from `morphe-patches/`. `source ~/.zshrc` supplies JDK 21 and
`ANDROID_HOME`; the checkpoint scripts also have explicit defaults.

### 6.1 Build the patch bundle

```bash
source ~/.zshrc
cd ~/Downloads/Devops-Projects/morphe-reddit/morphe-patches
./gradlew buildAndroid
```

Output: `patches/build/libs/patches-2.1.0.mpp`.

### 6.2 Patch the Reddit 2026.45.0 APKM

```bash
APKM="$HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm"

java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
  -p patches/build/libs/patches-2.1.0.mpp \
  -o build/ckpt/patched.apk \
  -r build/ckpt/result.json \
  "$APKM"
```

Output: `build/ckpt/patched.apk` (about 160 MB) and `build/ckpt/result.json`.

A good result reads:

```json
{"success": true, "packageName": "com.reddit.frontpage", "packageVersion": "2026.45.0",
 "appliedPatches": [ ... 29 entries including "Hide navigation buttons" ... ],
 "failedPatches": [], "stepResults": [{"step":"PATCHING","success":true},
 {"step":"REBUILDING","success":true},{"step":"SIGNING","success":true}]}
```

The patch is **all-or-nothing useful**: if a fingerprint misses, `failedPatches` is not
empty and the build must not be installed.

### 6.3 Install on the phone

USB debugging on, phone unlocked, trusted for this Mac:

```bash
../android-sdk/platform-tools/adb devices
../android-sdk/platform-tools/adb install -r build/ckpt/patched.apk
```

- A phone that still has the **patched** build: `install -r` keeps data and the toggle.
- A phone with **Play Store Reddit**: signatures differ, so uninstall first:
  `adb uninstall com.reddit.frontpage`, then install. This also wipes app data, so the
  Hide feeds toggle must be turned on again.
- ColorOS may show an install confirmation ("Continue installation") and an
  "Installed / Version ... / Close" sheet. Accept/close them on the device.

### 6.4 Turn the feature on

The guards and hooks are inert when the toggle is off - the app behaves as stock Reddit.
After every fresh install:

1. Open Reddit (the *Start as guest* patch skips the login wall).
2. Open the hamburger / community menu -> **Morphe**.
3. **Navigation bar** -> **Hide feeds** -> ON.
4. Optional: **Hide Inbox button** -> ON.
5. Cold start the app: the search page should open by itself.

---

## 7. Testing on the phone

Everything runs through the checkpoint runner so output is captured:

```bash
scripts/checkpoint.sh 0          # toolchain
scripts/checkpoint.sh 1          # cold start, guards, Home taps
scripts/checkpoint.sh 2          # OFF stock, ON landing
scripts/checkpoint.sh 3          # device gauntlet
scripts/checkpoint.sh all        # every checkpoint
scripts/checkpoint.sh 3 --explain  # list checks without running
```

Each run writes `evidence/S<N>.log`. **Evidence logs are never edited** - a re-run replaces
the log, a hand edit is forbidden.

### Device gate

- `adb devices` must show the phone; otherwise the run stops and says
  "waiting for the phone".
- The phone must be **unlocked**; its keyguard cannot be cleared by adb.
- The app on the phone is disposable: the checks uninstall/reinstall freely.
- The guest state and the toggle are kept across `install -r`.
- Checks poll (`wait_for_ui`, `ui_text_retried`) rather than sleep on a fixed clock because
  the top bar and its menu attach with a multi-second lag.
- A uiautomator dump of anything that is not Reddit is a **harness error**, never a result.
- The Communities bar slot is server-controlled; checks pass with or without it.

`scripts/checks/env.sh` holds the shared paths (`APKM`, `BUNDLE`, `OUT_DIR`, `PACKAGE`).
`scripts/checks/lib.sh` implements the `describe / check / require / finish` vocabulary.

---

## 8. Verification status

From the design note's table, with the latest observed result:

| Row | What it proves | Status |
|---|---|---|
| V1 | Build produces the bundle | **Green** (S0, re-run each device check) |
| V2 | Patch of 2026.45.0 succeeds | **Green** (S0, re-run each device check) |
| V3 | Diff discipline (product tree) | **Green** at S0 base; six product files changed by design |
| V4 | Setting OFF behaves stock | **Green** (S02) |
| V5 | ON cold start: search by itself, no feed, Home present, no login | **Green** (S01, re-run S02) |
| V6 | Subreddit from results as guest; Back returns to search | **Green** (S01) |
| V7 | Back from search: no feed/no crash; top-bar search button works | **Green** (S03; harness waits for the top bar's late attach) |
| V8 | Coexists with other hides | **Green** (S03) |
| V9 | Back never reaches Home | **Green** (S03) |
| V10 | Resume / `REDIRECT_TO_HOME` | **Green** (S03, resume variant) |
| V11 | Notification post -> Back | **Manual - signed off n/a** (owner, 2026-11-12: Reddit notifications are off on the phone) |
| V12 | Cold external r/<sub> link stays on top | **Green** (S03) |
| V13 | Root deep link shows no feed | **Green** (S03) |
| V14 | Toggles together keep a usable bar | **Green** (S03) |
| V15 | Rotation + recents | **Green** (S03) |
| V16 | Every route shows no feed, with/without Communities tab | **Green**, variant recorded: this phone has no Communities slot |
| V17 | OFF renders Home/Discover/Popular normally | **Green** (S02) |
| V18 | Every Home tap opens search; blank Home never appears | **Green** (S01) |
| V19 | Hide Inbox drives Inbox + UnifiedInbox | **Green** (S03) |
| V20 | Search zero state has no Trending; recent searches stay | **Red - accepted as shipped** (owner, 2026-11-10, option a) |

**The ones that matter:** V16 is the requirement. V17 is the promise to anyone who leaves
the switch off. V18 is the behavioural core of the Home-tap design.

---

## 9. Decision timeline (condensed)

| Date | Decision |
|---|---|
| 2026-11-08 | Original drawer-based design abandoned; v2 design: no login, guest, land on search, never render a feed |
| 2026-11-08 | v2 adopts five render guards; drawer route removed; guest-only confirmed |
| 2026-11-08 | Communities-slot problem recorded; hook 1 moved into S1; Home button stays in the bar |
| 2026-11-09 | **Third amendment:** hook 5 (cold-start attach opens search), hook 6 (every Home tap opens search), shared debounced launch, Hide Inbox toggle, remove search Trending shelves |
| 2026-11-09 | Zero-state hook moved from `hydrateRecentSkeletonItems` to the terminal publisher; the inline smali compiler cannot compile the five-parameter hydrate shape |
| 2026-11-10 | Zero-state fingerprint's impossible `returnType` pin removed; `invoke-static/range` used for the 28-register publisher |
| 2026-11-10 | S1 green 18/18; S2 green 13/13 |
| 2026-11-10 | V20's one device attempt failed; owner chose **option (a): accept as shipped**; row stays red with the reason |
| 2026-11-10 | Reviews deferred; push to delivery |
| 2026-11-12 | S00 V3 redefined: product diff confined to the six allowed files |
| 2026-11-12 | Sign-in sheet on every launch; hook 7 (datasource suppression) and hook 8 (forced-login gate false) added, owner-approved |
| 2026-11-12 | S04 final gate PASS 8/8 with V20 as the one accepted exception; V11 signed off n/a; branch pushed to `origin` |

The full log is the **Changes** section of `docs/build-plan.md`.

---

## 10. Open issues and owner calls

### 10.1 V7 harness failure - resolved

- Fixed in the harness on 2026-11-12: the top bar attaches up to 30+ s late; S03 now
  polls 15 s with a 45 s fallback. V7 is green. No product code was involved.

### 10.2 V20 - accepted as shipped

- The filter is injected at the verified terminal publisher; the page still showed
  Trending.
- Owner accepted the sections on 2026-11-10 (option a). No second site, no re-attempt.
- The row stays red in the coverage table, with the reason recorded. It is the only red
  row going into the final gate.

### 10.3 Working tree

- Everything is committed. `.opencode/rules/hide-home-feed.md` still tells the agent to
  write stage reports from the deleted `docs/stages/TEMPLATE.md`; that one line needs the
  owner's word to strike.

### 10.4 Reviews deferred

- Stage A report exists (`docs/stages/A.md`), review line filled in, no review has run.
- Delivery proceeds without it unless the owner says otherwise.
- `docs/REVIEW-PROMPT.md` governs review whenever it is revived.

### 10.5 Branch

- `feat/hide-home-feed` was pushed to `origin` (the owner's fork,
  `vjkancherla/morphe-patches`) on 2026-11-12. Never push to `upstream`.

### 10.6 V11 - manual, signed off n/a

- The notification-post flow cannot be driven by adb on this phone. S04 reports it as its
  own manual line and never counts it as an automated pass.
- Signed off n/a on 2026-11-12 (`scripts/checks/S04-v11-signoff.txt`): Reddit
  notifications are turned off on the phone. If they are turned back on, test it by hand:
  tap a Reddit notification, press Back, expect the search page.

### 10.7 The Communities bar slot

- Server-controlled and absent on this phone. Every check must pass with or without it.
- The empty-screen menu and the Home-tap flow are what make Morphe settings reachable.

---

## 11. Delivery - closed 2026-11-12

All steps are done: V7 fixed in the harness, S03 20/21 with V20 accepted, sign-in sheet
fixed (hooks 7-8), S04 final gate PASS 8/8, hand-off report `docs/stages/C.md`, branch
pushed to `origin`.

If Reddit changes again: rebuild and patch (section 6), run `scripts/checkpoint.sh all`,
then `scripts/checks/S04.sh`. The raw `all` verdict stays FAIL on V20; S04 is the only
place that exception applies.

---

## 12. Rules that still bind

- Guest mode only; no account, no login.
- Never hard-code obfuscated names (`f1`, `sps`, `pjb`, `re6`, ...) in a fingerprint or
  patch; match on structure and take names from the matched instruction.
- A guard or hook fingerprint miss must **fail the patch**.
- Never edit an `evidence/` log; re-run the check instead.
- Never loosen a check silently. If a change proves less, the plan's Changes line starts
  `LOOSENED:`.
- Only the six product files; docs/.opencode/scripts/evidence are outside that list.
- Keep the once-per-process flag on the attach launch; it prevents a search loop.
- Do not push the branch; do not rewrite history.
- `.opencode/rules/` is not edited by the implementer.
- The product diff for this feature is exactly the six files above.

---

## 13. Facts not to re-derive

- Toolchain: `source ~/.zshrc` gives JDK 21 (`/opt/homebrew/opt/openjdk@21`) and
  `ANDROID_HOME`; adb is `../android-sdk/platform-tools/adb`.
- Project root matters: checkpoints run from `morphe-patches/` only.
- Patch command is the `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch ...` form
  in section 6.2.
- ColorOS gates installs behind a confirmation sheet, then parks an "Installed" sheet over
  the front window. Both must be dismissed before reading UI.
- The install sheet can reappear *after* the install-time dismissal window; re-check
  before each state read.
- uiautomator nodes carry an empty `text` attribute **before** `content-desc`; a
  first-attribute matcher hides content-desc-only labels. Scan both per node.
- Morphe switches read truthfully on their `checked` attribute.
- The top bar and its menu attach with a several-second lag; poll, do not sleep once.
- The cold-start search's Back path does **not** attach the Communities top bar; the top
  bar arrives through the Home-tap flow.
- The stock OFF home shows: search pill (`Search Reddit`), `Log in`, hamburger
  (`Open community menu`). The stock home menu holds Popular, Morphe, About, Reddit Rules,
  User agreement, Acknowledgements - no Discover row.
- "Renders normally" for stock guest screens is judged by screencap pixel diversity
  (`content_pixel_score`): blank is hundreds, a feed is thousands. This build's guest
  screens carry no vote/share a11y labels.
- Inline smali compiler traps (both reproduced):
  1. It emits **nothing** for a five-parameter method shape
     `(List, FilterValues, Z, List, ContinuationImpl)`.
  2. Multiline `addInstructions` near its edge silently drops lines. Single-line inserts
     with void extension methods are the proven shape.
- Parameter registers above v15 need `invoke-static/range` (the 4-bit `invoke-static`
  register list caps at v15).
- `verifyInjectionAt` (read-back of instruction 0) is what catches residual injection
  failures; it accepts both `invoke-static` and `invoke-static/range`.
- Bytecode dumper, if needed: `/var/folders/t5/d576h93s1mj1kkt4ykx7hg5r0000gn/T/opencode/bcdump/`
  (`bc.sh` runs `Dump <dexdir> <class-descriptor> [method-substring]`; dexes already
  extracted).

---

## 14. Stop conditions (still binding)

- Phone locked or not attached.
- A login prompt appears.
- Any feed visible under the ON toggle (deliberately opened subreddit pages are exempt).
- Search launching twice, or looping.
- Morphe settings unreachable.
- A guard fingerprint miss.
- A check fails twice after two different fixes.
- For V20: no second site, no re-attempt outside the owner's call.

---

## Appendix A - Artifact index

| Artifact | Path |
|---|---|
| Patch bundle | `patches/build/libs/patches-2.1.0.mpp` |
| Patched APK | `build/ckpt/patched.apk` (gitignored) |
| Patch result | `build/ckpt/result.json` (regenerated per run) |
| Evidence logs | `evidence/S00.log` ... `evidence/S03.log` |
| Zero-state before/after screenshots | `evidence/S01-search-zero-state.png`, `evidence/S03-search-zero-state-after.png` |
| Checks | `scripts/checks/S0{0,1,2,3}.sh` + `lib.sh` / `env.sh` |
| Runner | `scripts/checkpoint.sh` |
| Reinstall guide | `docs/REINSTALL-REDDIT.md` |

## Appendix B - One-screen command card

```bash
source ~/.zshrc
cd ~/Downloads/Devops-Projects/morphe-reddit/morphe-patches

# Build
./gradlew buildAndroid

# Patch
java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
  -p patches/build/libs/patches-2.1.0.mpp \
  -o build/ckpt/patched.apk \
  -r build/ckpt/result.json \
  "$HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm"

# Install (uninstall first only if Play Store Reddit is installed)
../android-sdk/platform-tools/adb install -r build/ckpt/patched.apk

# Test
scripts/checkpoint.sh 3
```
