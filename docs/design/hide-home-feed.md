# Hide Home Feed - Design Note (v1)

Date: 2026-11-07
Scope: One new toggle in the existing Reddit `Hide navigation buttons` patch, on the
fork of `MorpheApp/morphe-patches`, branch `feat/hide-home-feed`. For personal use first;
an upstream PR is optional and out of scope here. Verified against Reddit 2026.45.0 only.

Context read:
- `patches/.../reddit/layout/navigation/HideNavigationButtonsPatch.kt` and `Fingerprints.kt` -
  the modern hook, and the pattern for adding an interface and helper method to an obfuscated class
- `extensions/reddit/.../patches/HideNavigationButtonsPatch.java` - `Home(false)` is hard-coded;
  the `NavigationButton` enum drives hiding
- `extensions/reddit/.../settings/Settings.java`, `.../categories/NavigationBarPreferenceCategory.java`,
  `patches/src/main/resources/addresources/values/reddit/strings.xml` - where a nav setting is declared
- `patches/.../reddit/shared/Constants.kt` - the patch targets 2026.45.0, .44.0, .43.0, .40.0 and older
- Decompiled Reddit 2026.45.0, read in `reddit-decompiled/sources/` and, for `e5()` and `re6`,
  as raw jadx fallback output. All Reddit class references below come from these
- Stated intent: "open the app → see a list of chosen subreddits (e.g. r/vibecoding, r/opencode,
  r/nfl, r/soccer) → tap one to read it." Adding more means tapping **Join**. No custom list UI.

## Decision

Add *Navigation bar → Hide Home feed*. When ON, the Home tab leaves the bar, every internal
"go to Home" lands on the `Communities` tab instead, and on the first attach of that tab in
each process the app opens Reddit's own left drawer, which holds the joined-subreddit list.
When OFF, the app behaves as it does today.

Owner confirmed the drawer auto-open, 2026-11-08.

## Why the drawer is the landing surface (load-bearing)

Everything hangs off this finding: **no bottom tab shows the joined subreddits.**

- `Communities` builds `CommunitiesTabScreen`, whose content is `explore_feed`
  (`ExploreFeedScreen`, the Discover feed).
- `MyCommunities` builds the same `CommunitiesTabScreen` (factory `re6`, case 8). It has no bar
  button in `jn90.a()`, and the screen's `E1()` reports `Communities`.
- The joined list is the `COMMUNITIES` section of `CommunityDrawerScreen`, in the drawer
  (`HeaderItem.COMMUNITIES`, `ObserveSubredditsUseCase`). The drawer also has Favorites, Moderating,
  Recently Visited, Resources, Games and About.

An earlier draft assumed `MyCommunities` was the joined list. It is not, so anything still
describing that is wrong.

Alternative considered - land on the `Communities` tab with no drawer. It is one hook smaller
and has no timing risk, but the first thing you see is a recommendation feed, which is the
thing this feature exists to avoid. It wins if the drawer hook proves unreliable (see S1 risk).

Alternative considered - `CommunityDrawerScreen` as the tab's content. It has a public no-arg
constructor and would make Back return to the list. It loses because it does not implement the
tab interface `uf6`, nothing shows it works outside the drawer, and it would still show the
non-subreddit rows. It wins if Back-to-list matters more than risk, and only after a spike.

## Shape

```
Settings.HIDE_HOME_FEED
        |
        v
Extension: HideNavigationButtonsPatch.java
  hideNavigationTab(tab)     removes Home from the bar, never removes Communities
  getStartTab(tab)           Home -> Communities, anything else unchanged
  onStartTabAttached(screen) once per process, schedules the drawer opening
        ^
        | invoke-static, injected by HideNavigationButtonsPatch.kt
        |
Reddit (obfuscated names, 2026.45.0)
  Hook 0 (exists)  BottomNavScreen list builder     hideNavigationTab
  Hook 1           BottomNavScreen.I5(tab), entry   getStartTab   first screen on the stack
  Hook 2           BottomNavScreen.e5(), after Home default  getStartTab   highlighted tab
  Hook 3           presenter c.T(tab, z), entry     getStartTab   every programmatic selection
  Hook 4           CommunitiesTabScreen.L3(view)    onStartTabAttached
  Added method     CommunitiesTabScreen.patch_openCommunityDrawer()   pjb.a()
```

## Core mechanism

### Setting

- `Settings.java`, with the other `HIDE_*` settings, keeping alphabetical order:
  `public static final BooleanSetting HIDE_HOME_FEED = new BooleanSetting("morphe_hide_home_feed", FALSE, true);`
- `strings.xml`, base `values/` only (Crowdin handles translations), next to
  `morphe_hide_games_button_title`:
  `<string name="morphe_hide_home_feed_title">Hide Home feed</string>`
- `NavigationBarPreferenceCategory.java`: a `BooleanSettingPreference` for it, first in `addPreferences`.

### Extension

In `HideNavigationButtonsPatch.java`. Logger is `app.morphe.extension.shared.Logger`.

- `Home(false)` becomes `Home(Settings.HIDE_HOME_FEED.get())`.
- In `hideNavigationTab`, after the null check: if the setting is ON and the tab name is the start
  tab, return false. This covers `Hide Discover or Communities button` being ON as well.

```java
private static final String START_TAB_NAME = "Communities";

public interface StartTabScreenInterface {
    void patch_openCommunityDrawer(); // Added during patching.
}

private static boolean startDrawerRequested;

/** Injection point. Replaces Home with the start tab. Any failure returns original. */
@SuppressWarnings({"unchecked", "rawtypes"})
public static Enum<?> getStartTab(@Nullable Enum<?> original) {
    try {
        if (original == null || !Settings.HIDE_HOME_FEED.get() || !"Home".equals(original.name())) {
            return original;
        }
        return Enum.valueOf((Class) original.getDeclaringClass(), START_TAB_NAME);
    } catch (Exception ex) {
        Logger.printException(() -> "getStartTab failure", ex);
        return original;
    }
}

/** Injection point. Opens the drawer once per process, after the event collector is alive. */
public static void onStartTabAttached(Object screen) {
    if (!Settings.HIDE_HOME_FEED.get() || startDrawerRequested) return;
    startDrawerRequested = true;
    new Handler(Looper.getMainLooper()).postDelayed(() -> {
        try {
            ((StartTabScreenInterface) screen).patch_openCommunityDrawer();
        } catch (Exception ex) {
            Logger.printException(() -> "onStartTabAttached failure", ex);
        }
    }, START_DRAWER_DELAY_MS);
}
```

`START_DRAWER_DELAY_MS` is found empirically in S1. Use `original.getDeclaringClass()`, never a
hard-coded Reddit class.

### Hooks

Match on structure, not obfuscated method names. Add them inside `// region modern method`, after
the `BottomNavScreenListBuilderFingerprint` block. Register numbers below come from decompiled
output; confirm them from the matched instruction.

| Hook | Fingerprint | Injection |
|---|---|---|
| 1 | `BottomNavScreen`, public final, returns void, single `BottomNavTab` parameter. It is the only such method in the class | Index 0, on the parameter |
| 2 | `BottomNavScreen`, string `com.reddit.arg.initial_tab`, filter `sget-object BottomNavTab;->Home` | Right after the `sget-object` |
| 3 | No `definingClass` (the presenter's name is unstable), returns void, parameters `BottomNavTab`, `Z`, filter `sget-object BottomNavTab;->Inbox`. Check it is unique; `N5` has the same signature but no `Inbox` read | Index 0, on the parameter |
| 4 | `CommunitiesTabScreen`, returns void, single `View` parameter, string `achievementsNotificationsProxy`, filter on the proxy call taking the screen. `W3` looks the same but calls the no-arg variant | After the proxy call |

Injection for hooks 1 to 3, where `vX` is the tab register:

```smali
invoke-static { vX }, Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch;->getStartTab(Ljava/lang/Enum;)Ljava/lang/Enum;
move-result-object vX
check-cast vX, Lcom/reddit/launch/bottomnav/BottomNavTab;
```

Added method: add `StartTabScreenInterface` to `CommunitiesTabScreen` and add
`patch_openCommunityDrawer()`, following the existing `patch_getLabel` pattern. Its body reads the
lazy `pjb` provider field, calls `get()`, casts to `pjb` and calls `pjb.a()`.

`CommunitiesTabScreen` has three fields of the same type (`f1`, `g1`, `h1`), so find the right one
structurally: in `com.reddit.communitiestab.compose.a`, it is the `iget-object` of a
`CommunitiesTabScreen` field nearest the string `communityNavIconClickHandler`. Take `pjb` from
the `check-cast` that follows. Never hard-code `f1`, `sps` or `pjb`.

### Why these sites

| Reddit code | What it does with Home | Treatment |
|---|---|---|
| `re6` lambda (case 4) → `I5(Home)` | Installs the first screen | Hook 1 |
| `MainActivity.k0` line 1453 → `I5(Home)` | Reused-activity deep link backstack | Hook 1 |
| `e5()` default → `df0` → `voo` → presenter `i.a` → `g2` | Sets the highlighted tab | Hook 2. jadx's Java shows this local as unused; the bytecode shows it is used |
| `legacyactivity/observer/a.java` lines 116, 121 → `z1(Home)` → `c.T` | `REDIRECT_TO_HOME` on app resume | Hook 3 |
| `dp00` line 165 → `z1(Home)` → `c.T` | Onboarding exit | Hook 3 |
| `HomeDeepLinker` → `c.Q(Home)` → `c.T` | Deep link to Home | Hook 3 |
| `J5`, `a.java` 131 and 185, `h.java` 28 and 79, `jn90`, `lf6`, `ln90`, `b.java` 94, `HomePagerScreen.E1`, refresh badge | Comparisons, tables, identity | **Do not hook.** Replacing Home here breaks other logic |

`c.T` is the selection funnel: `z1`, `Q` and `onSetCurrentTab` all reach it. The other `N5`
callers are the Inbox shortcut and the tap handler in `bottomnav/a.java`, and Home cannot be tapped
when hidden. `h.java:28` lists `Communities` as a root tab, which supports using it as the start.

### Drawer opening

The tab's own menu button works by calling `pjb.a()`. That emits on a flow, helper
`screens/drawer/helper/b` collects it (`ho3` case 2), and `b.y(activity)` opens the drawer if its
screen is the top screen. Reusing this keeps Reddit's own checks and analytics.

- **The event is dropped if nobody is collecting.** `pjb` has no replay, which is why the call is
  delayed instead of made directly from `L3`.
- **Deep links are mostly safe by construction.** `b.y()` does nothing unless the helper's screen
  is on top, and hook 4 only runs when the tab attaches.

## Failure modes handled

1. A hook's extension call throws: `getStartTab` returns the original tab and the app behaves as
   unpatched. The user sees Home and a logged exception.
2. The drawer opening fails or misses its timing: the user sees the Discover feed, and the list is
   one swipe away. Nothing crashes.
3. `Hide Discover or Communities button` is also ON: the start tab stays in the bar.
4. The server gives the Communities slot to Games or Answers, or empties it (`jn90.a`): the screen
   still opens, because the factory builds it from the enum, but no tab is highlighted.

**Not handled:**

- **`CommunityAccessRequestViewModel` line 353** pushes `HomePagerScreen` directly, so that flow
  shows the Home feed. It is a rare moderation flow, and hooking `HomePagerScreen` construction
  would be far more invasive.
- **Incognito:** `b.y()` shows a "blocked" sheet instead of the drawer, so an incognito cold start
  would show it. The extension cannot read the session state. Acceptable for a personal build, and
  worth fixing before any upstream PR.
- **Cold start by deep link, then tapping Communities:** the drawer opens once at that first attach.
  Harmless, so left as is.
- **Back from a subreddit** lands on the Discover feed with the drawer closed, not on the list.
- **Other versions:** the fingerprints are only verified on 2026.45.0. On another version a miss
  could fail the whole `Hide navigation buttons` patch. See Open questions.
- **Tablet side navigation** (`BottomNavTabListUseCaseParams.SIDE_NAV`) has not been looked at.

## Verification

V1 to V3 can run unattended. V4 onward need a phone: no device was attached when this was written
(`adb devices` was empty), so those rows belong to the owner, and an agent without a device must
stop at them rather than skip them.

| # | Check |
|---|---|
| V1 | `./gradlew buildAndroid` succeeds with no new warnings and produces `patches/build/libs/patches-*.mpp` |
| V2 | Patching the 2026.45.0 `.apkm` with Morphe Desktop succeeds, with *Hide navigation buttons* and *Settings* applied and no failed patch in the result file |
| V3 | `git diff --stat` against the base, limited to `patches/` and `extensions/`, shows only the six files listed under Files allowed. Build-plan artefacts elsewhere don't count |
| V4 | Setting OFF, cold start: opens on Home, Home tab visible, no drawer |
| V5 | Setting ON, restart: no Home tab, the start tab opens its screen, drawer open showing joined subreddits. Which slot occupies the Communities position is server-controlled; a non-Communities or empty slot means no highlighted tab (failure mode 4). Owner confirmed 2026-11-08 to verify the wording at test time |
| V6 | Tap a subreddit in the drawer: its feed opens. Back lands on the Communities tab with no crash |
| V7 | Join a new subreddit, reopen the drawer: it is listed |
| V8 | *Hide Discover or Communities button* also ON, restart: Communities is still shown and is still the start |
| V9 | Switch tabs and press Back repeatedly: the Home feed never appears; the app exits or stays on the start tab |
| V10 | Leave the app in the background past the resume timeout, or until `REDIRECT_TO_HOME` fires, and return: no Home feed |
| V11 | Open a post from a notification, press Back: no crash, no Home feed |
| V12 | Open a `reddit.com/r/<sub>` link from another app, cold: the subreddit opens with no drawer over it |
| V13 | Open a `https://www.reddit.com/` link from another app: no Home feed, no crash |
| V14 | Chat, Games and other nav toggles ON together with this one: all hidden, no crash |
| V15 | Rotate the screen, then kill from recents and reopen: still no Home feed, and rotation does not reopen the drawer |

**The ones that matter:** V5 is the feature. V10 is the leak that is easiest to miss, because a
normal test session never triggers it. V4 is the promise to everyone who leaves the setting off.

If V9 fails, stop and report. A Back path to Home was not found in the source, but the nav stack
was not traced exhaustively, and a second design decision would be needed.

## Build facts

- **Editable:** `morphe-patches/` only. **Read-only:** `../reddit-decompiled/sources/`,
  `../reddit-apk/`, `../tools/`.
- **Product files allowed (exactly six):** `Settings.java`, `strings.xml` (base `values/`),
  `NavigationBarPreferenceCategory.java` and extension `HideNavigationButtonsPatch.java`;
  navigation-package `Fingerprints.kt` and `HideNavigationButtonsPatch.kt`.
- **Shell:** macOS, zsh. `source ~/.zshrc` supplies `JAVA_HOME` (JDK 21) and `ANDROID_HOME`.
- **Build:** `./gradlew buildAndroid`.
- **Patch:** `java -jar ../tools/morphe-desktop-2.1.1-all.jar patch` with `--patches`, `--out` and
  `--result-file`. The input is `~/Downloads/com.reddit.frontpage_2026.45.0-*.apkm`. `--validate`
  and `--install` also exist. Check `patch --help` for full usage.
- **Commits:** semantic messages, e.g. `feat(Reddit): Add "Hide Home feed" option`.
- **Device testing (owner confirmed 2026-11-08):** the owner attaches a physical phone by USB
  during the build; the agent gates on `adb devices` and waits when it is empty. The phone runs a
  disposable Reddit data state: the Play install is uninstalled and replaced by the patched APK
  freely. The patched APK has a different signature, so the uninstall is required. Device checks
  (V4-V15) are automated as far as adb allows; anything needing a human finger is flagged in the
  stage report. Incognito caveat accepted as designed.
- **Tests:** the repo has patch tests under `patches/src/test/` for Music and YouTube, none for Reddit.
- **Non-goals:** a new patch, a setting to choose the start tab, a custom list screen or stored
  subreddit list, the legacy nav path (Reddit below 2026.25.0), edits to translated `strings.xml`,
  and refactoring anything not named here.

## Roads not taken

- **`MyCommunities` as the start tab** (the first spec): the strongest case was that the name implies
  the joined list. It lost because it builds the Discover screen and has no bar button. It would win if
  a future Reddit version gives it its own screen.
- **Hooking the `re6` lambda directly** (the first discovery report's A2): it is the literal site of
  `I5(Home)`. It lost because `re6` is an unstable synthetic name, and the `I5` entry also covers
  `MainActivity.k0`.
- **Opening `DrawerLayout` from the extension:** no patch to the screen class would be needed. It lost
  because the androidx method names are obfuscated (`drawerLayout.n(...)`) and it would skip Reddit's
  own checks in `b.y()`.

## Open questions

- [x] ~~Confirm the landing behaviour~~ Resolved 2026-11-08: drawer auto-open, this note stands
      as v1.
- [ ] What does the owner's bar show between Home and Inbox? A slot other than Communities means no
      highlighted tab in V5, which is accepted above but worth knowing before testing. (owner) —
      owner asked to leave it unknown until the device run; V5's wording is now server-dependent.
- [x] ~~Should 2026.44.0, .43.0 and .40.0 stay supported?~~ Resolved 2026-11-08: 2026.45.0 only as
      the **testing** scope. `Constants.kt` is untouched — `COMPATIBILITY_REDDIT` is shared by all
      32 Reddit patches, so the advertised version list for other patches does not change. No
      upstream PR is in scope.
- [ ] Which helper instance receives the `pjb` event on this tab? `y13` line 85 constructs the helper
      and the tab's own button proves the route exists, but it was not traced end to end. S1 settles it. (implementer)
- [ ] `START_DRAWER_DELAY_MS`: a fixed delay is fragile on slow devices. Keep it if S1 shows a generous
      value works; otherwise prefer a later lifecycle hook. (implementer)

## Effort

About a day for the implementing agent, plus an hour of owner time on a phone. The setting and
extension logic are small. **The drawer opening is the riskiest assumption and belongs early**: it
needs a device, its timing can only be found by running it, and if it fails the design falls back
to `Communities` with no drawer. Hook 3's fingerprint is the most likely to need a second attempt,
since it cannot name its class.
