# Hide Home Feed - Design Note (v2: no feeds, land on Search, no login)

Date: 2026-11-08, amended 2026-11-09 (Home button stays), amended 2026-11-09 again (owner
decisions on cold start, Home taps, Inbox toggle and the trending sections - the *Third
amendment* sections below).
Supersedes: `hide-home-feed.md` (v1), for the landing surface only. v1 stays as the record, and
its Hooks 1-3, "Why these sites" table, failure modes 1, 3 and 4, and build facts still apply
unless changed below. Verified against Reddit 2026.45.0 only.

Stated intent (owner, 2026-11-08): "I do not want to login to reddit", "when I open, I see the
search page and not the feed page and I will search for the subreddit I want to use", and
"I do not want to see the feed at all, this is critical."

## Decision

*Navigation bar → Hide feeds*, when ON:

1. **No feed screen ever renders.** Reddit's five feed screens draw nothing. This is the
   guarantee, and it does not depend on navigation or timing.
2. **The Home button stays in the bar** (owner amendment, 2026-11-09, recording the
   `docs/decisions/S01-communities-tab.md` decision: Option A with one change) and opens
   Reddit's search page on **every** tap (third amendment). Its screen is the empty start
   screen: every internal "go to Home" lands on the `Communities` tab (v1 hooks 1-3), so
   tapping the bar's Home tab arrives there through hook 3, with hook 6 rewriting the tapped
   tab first. That tab shows only Reddit's top bar over an empty page, with its search
   button. Never hook the list builder into removing Home for this feature.
3. **The app opens Reddit's own search page by itself** (third amendment, not only on the
   start tab's attach): the guarded Home screen and the start tab both open it on their
   first attach per process (hooks 4-5), and every Home tap opens it again (hook 6).

The Communities bar slot is server-controlled: this phone hides it (`jn90.a` returns null,
v1 failure mode 4) and a future build may restore it, so every device check must pass with
or without a Communities tab. The feed guard, not navigation, is what keeps the app
feed-free.

The app runs in guest mode throughout. No drawer auto-open, no stored subreddit list, no account.
When OFF, the app behaves as it does today.

Requirement priority: if any two goals conflict, no-feed wins. A blank page is always an
acceptable outcome. A visible feed never is.

## Feed guard (the critical part)

Every feed in 2026.45.0 is a `ComposeScreen` whose render method has the same shape. Blocking the
render method covers every way of reaching the screen, including the ones navigation hooks cannot
see: the drawer's Discover, Popular and Latest rows, deep links, and direct pushes.

| Screen | Class | Compose key in the render method |
|---|---|---|
| Discover | `com/reddit/communitiestab/explore/ExploreFeedScreen` | `888459659` |
| Home | `com/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen` | `-1198908911` |
| Popular | `com/reddit/feeds/popular/impl/ui/PopularFeedScreen` | `2024162344` |
| Latest | `com/reddit/feeds/latest/impl/ui/LatestFeedScreen` | `-1095661192` |
| News | `com/reddit/feeds/news/impl/NewsFeedScreen` | `1045476250` |

These class names are not obfuscated. The render method is obfuscated (`V2` in this build), so
match it structurally: `definingClass` above, public final, returns void, parameters `(L, I)`.
Confirm it is unique in each class, and add the compose key literal as a filter if it is not.

Inject at index 0, before the method starts its Compose group, so the composer stays balanced:

```smali
invoke-static {}, $EXTENSION_CLASS->hideFeedScreen()Z
move-result v0
if-eqz v0, :show
return-void
:show
nop
```

```java
/** Injection point. True blocks a feed screen from rendering. */
public static boolean hideFeedScreen() {
    return Settings.HIDE_HOME_FEED.get();
}
```

`v0` is free at entry. Use `addInstructionsWithLabels`, as the existing hook code does. Do not
catch a fingerprint miss: a miss must fail patching, so a build that cannot guard a feed never ships.

Do not guard `CommunitiesTabScreen` itself. Its top bar holds the search button, the drawer button
and the avatar menu, which are the way back to search and to Morphe settings. Its body embeds
`ExploreFeedScreen(false)`, which the guard already blanks.

## Landing on search

`DeepLinkUtil.search(Context, Bundle)` handles the search link. With an empty `q` and no flair it
builds `TypeaheadResultsScreen.DeepLinker`, the search-box page. A query-less link reaches that
screen through Reddit's own routing, with no Reddit classes or obfuscated names in the extension.

The link: `https://www.reddit.com/search`, sent as an `ACTION_VIEW` intent restricted to the app's
own package.

Device status: on the patched build, `am start` with this link cold-started and resolved to
`MainActivity` with status ok. The search page opens as a guest with the keyboard up
(2026-11-09, on the phone).

## Third amendment (2026-11-09): why the cold start was blank, and the new hooks

**Established on the phone with the hooks-2-3 build:** the cold-start blank page *is* the
guarded `HomePagerScreen` (the guard holds; nothing renders). `BottomNavScreen` builds it
directly in a separate method, so hook 1's push (and the initial-tab default, hook 2) never
decide which screen is visible on cold start; the screen shows up regardless. Hook 1 therefore
stays as the *selected-tab* redirect (the bar highlight and REDIRECT_TO_HOME paths), but the
**cold-start landing must be caught at the screen's attach, not at tab selection.**

The three owner decisions of 2026-11-09, replacing the options in the handover:

1. **Cold start opens search by itself** (the one-tap landing is not accepted). This is hook 5.
2. **The bottom-bar Home button opens search on every tap.** Create and Inbox buttons may be
   hidden (a *Hide Inbox button* setting drives both `Inbox` and `UnifiedInbox`, next to the
   Create toggle). This is hook 6 plus the new setting.
3. **The search page's Trending sections are removed before typing** (see
   *Search zero state* below).

### Hook 5 - the guarded Home screen's attach

`HomePagerScreen` (class `com/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen`,
not obfuscated) has an attach override - the only public final void method taking one
`View` and calling its super twin first - which runs when the guarded Home screen comes to
the front, including on cold start. Its **detach twin has the same signature** and also calls
`dismiss()` on the banner sheet plus a coroutine launch, so it is five registers and
double-digit instructions; the attach is two registers and four instructions
(super call, one call chain, return). Match the attach structurally by method shape and that
size difference, confirm the match is unique in the class (exactly two View-parameter void
overrides exist, attach and detach), and pin the twin with its own fingerprint so a future
natural rename of either cannot silently pass.

```smali
invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V
```

Hook 5 passes the attached View to **the same extension method as hook 4**. Hook 4 stays at the
start tab's attach ( Communities tab screen, achievements-proxy method, unchanged). So both the
start tab and the guarded Home screen launch search on their first attach per process, which is
what makes the cold start land on search.

### Hook 6 - the bottom-bar tap handler

The bar's tap handler is a synthetic `kotlin.jvm.functions.Function0` implementation in the
`com.reddit.launch.bottomnav` package whose `invoke()` contains the two property-name strings
`loggedOutBottomSheetScreenFactory` and `feedRefreshPolicy` (both strings occur in no other
class). It reads the tapped tab off the bar item into the register used by every subsequent
comparison - including the "already selected" branch that previously let repeated Home taps
skip hook 3 and land on the bare blank Home page.

Inject **right after that read, before any comparison** and replace the register with the result
of a new extension method:

```smali
invoke-static { vX }, $EXTENSION_CLASS->onBottomTabTapped(Ljava/lang/Enum;)Ljava/lang/Enum;
move-result-object vX
check-cast vX, Lcom/reddit/launch/bottomnav/BottomNavTab;
```

```java
/** Injection point. Rewrites the tapped tab; may launch search for Home taps. */
public static Enum<?> onBottomTabTapped(@Nullable Enum<?> tapped) {
    try {
        if (tapped == null || !Settings.HIDE_HOME_FEED.get() || !"Home".equals(tapped.name())) {
            return tapped;  // any other tab, or the feature off: unchanged
        }
        launchSearch();  // every tap; also sets the once-per-process flag
        return Enum.valueOf((Class) tapped.getDeclaringClass(), START_TAB_NAME);  // Communities
    } catch (Exception ex) {
        Logger.printException(() -> "onBottomTabTapped failure", ex);
        return tapped;  // never crash a tap
    }
}
```

The replacement happens **before** all comparisons, so the handler then behaves exactly like a
Communities tap: `Communities` still attaches underneath through the selection funnel (hook 3),
keeping the top bar, its search button, the avatar menu and the drawer reachable - the owner
has measured that the Communities menu is the only way to Morphe settings now (a left swipe
on the blank page does *not* open a drawer). **The handler is never short-circuited:** the
extension only rewrites the register.

### One shared search launch

All three launch sites (hooks 4 and 5 per attach - once per process through the existing flag -
and hook 6 per tap) go through one private helper:

- The attach hooks store the View's `Context` in a `WeakReference` for the tap path; the tap
  path reads it, and if it is empty it skips the launch and still returns the mapped tab.
- A shared debounce of about one second (`SystemClock.elapsedRealtime`, stamped before the
  intent is fired) covers a cold-start attach and an immediate tap within one second, and home
  taps seconds apart.
- A Home tap that launches search also sets the once-per-process flag, so hook 4 cannot launch
  a second search over it.
- Every failure is logged (`Logger.printException`) and never crashes the app; the tap handler
  returns the mapped tab regardless, per failure-mode rule: a failing search is a blank page,
  never a feed and never a crash.

## What changes from the S1 spike code

Remove, all of it reachable only from the drawer route:

- `StartTabScreenInterface` and `START_DRAWER_DELAY_MS` in the extension.
- `TabScreenClickHandlerProviderFingerprint` in `Fingerprints.kt`.
- In `HideNavigationButtonsPatch.kt`: the `interfaces.add(EXTENSION_START_TAB_SCREEN_INTERFACE)`
  block, the `communityNavIconClickHandler` lookup and the added `patch_openCommunityDrawer` method.

Keep `CommunitiesTabScreenDrawerProxyFingerprint`, the setting and the toggle. Hook 4 stays at
the same site but passes the view, so the extension has an Activity context. Hook 5 uses the
same method at the guarded Home screen's attach:

```smali
invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V
```

Extension, replacing the current `onStartTabAttached` (both hooks call it):

```java
private static final String SEARCH_PAGE_URL = "https://www.reddit.com/search";
private static final long SEARCH_LAUNCH_DEBOUNCE_MS = 1000;

private static boolean searchLaunched;              // once per process
private static long lastSearchLaunchAtMs;           // shared debounce
private static WeakReference<Context> attachedContextRef;

/** Injection point (hooks 4 and 5). Opens search on the first attach per process. */
public static void onStartTabAttached(View view) {
    if (!Settings.HIDE_HOME_FEED.get()) return;
    attachedContextRef = new WeakReference<>(view.getContext());  // for the tap path
    if (searchLaunched) return;
    // Set before firing. The link re-enters MainActivity, which can re-attach this tab.
    searchLaunched = true;
    view.post(() -> openSearchPage(view.getContext()));
}

private static void openSearchPage(Context context) {
    long now = SystemClock.elapsedRealtime();
    if (now - lastSearchLaunchAtMs < SEARCH_LAUNCH_DEBOUNCE_MS) return;
    lastSearchLaunchAtMs = now;
    try {
        context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SEARCH_PAGE_URL))
                .setPackage(context.getPackageName()));
    } catch (Exception ex) {
        Logger.printException(() -> "openSearchPage failure", ex);
    }
}

/** Injection point (hook 6). Every Home tap launches search and lands on Communities. */
public static Enum<?> onBottomTabTapped(@Nullable Enum<?> tapped) {
    try {
        if (tapped == null || !Settings.HIDE_HOME_FEED.get() || !"Home".equals(tapped.name())) {
            return tapped;
        }
        Context context = attachedContextRef != null ? attachedContextRef.get() : null;
        if (context != null) {
            searchLaunched = true;   // the attach hooks must not launch a second search
            openSearchPage(context);
        }
        // Do not return early from the caller: the tab is rewritten and the handler keeps
        // executing, so Communities attaches underneath and its top bar stays reachable.
        return Enum.valueOf((Class) tapped.getDeclaringClass(), START_TAB_NAME);
    } catch (Exception ex) {
        Logger.printException(() -> "onBottomTabTapped failure", ex);
        return tapped;
    }
}
```

The once-per-process flag is what prevents a loop. Do not remove it.

Product files remain the six allowed in v1, with the guards, hooks 5-6 and the zero-state
filter added to the navigation `Fingerprints.kt` and `HideNavigationButtonsPatch.kt`. `Home(false)`
stays as it is: the Home button is never hidden (owner amendment, 2026-11-09). `hideNavigationTab`
still protects the start tab, so *Hide Discover or Communities button* cannot remove the landing
surface. Change the base-`values` title to `Hide feeds`, since the toggle now covers all five.
Keep the setting key.

A new **Hide Inbox button** setting (key `morphe_hide_inbox_button`, default off) drives both
the `Inbox` and `UnifiedInbox` bar entries, sitting next to the *Hide Create button* toggle.
Default off changes nothing for anyone who does not touch it.

## Search zero state: remove Trending before typing

The pre-typing search page shows two Reddit sections - *Trending* (trending searches) and
*Trending Communities* - which are feed-like and the owner has decided they go when the
setting is ON. Recent searches, if the guest has any, stay.

**Source of the sections:** `RedditDynamicTypeaheadAndZeroStateRepository`
(class `com/reddit/typeahead/data/f` - the class name is not obfuscated).
Its global zero-state method (`handleGlobalZeroStateRequestOrdered`) and the network fetch it
falls back to (`fetchFromNetworkAndCache`) failed to decompile, so both were read from the APK
bytecode instead (dexlib2 dump). The flow, from the bytecode:

1. `handleGlobalZeroStateRequestOrdered` serves the cached shelf list when fresh, otherwise
   calls `fetchFromNetworkAndCache` with an empty query;
2. with an empty query that method passes the network's shelf list to
   `hydrateRecentSkeletonItems`, which fills the *recent* skeletons from local history and
   returns the finished list;
3. the finished list is then published by the repository's terminal method together with the
   query - this is the single funnel through which every pre-typing shelf reaches the page.
   **Trending Communities is a shelf of the same list:** the network response's
   `SearchTypeaheadList` nodes (the shelf model, `children` included) carry both sections, the
   *Trending* searches as `SearchTrendingQuery` rows and the communities as
   `SearchTypeaheadSuggestion` rows; typed queries use the same funnel but never include
   trending shelves.

**The clean site is the repository's terminal publisher** (the curate-and-publish method of
`com/reddit/typeahead/data/f`): every zero-state branch ends there - the finished shelf list as
its first parameter and the query string as its second, and its output is both the published
state flow and the returned response - so dropping the trending shelves at its entry removes
the sections from the page while recent-search shelves are untouched. Typed queries pass
through it too, but the extension filters only when the query is empty, so typed suggestions
are untouched.

It was not the first plan: an earlier draft hooked `hydrateRecentSkeletonItems`' entry instead,
and that site cannot be hook-shaped at all - the method's parameter shape
(`(List, FilterValues, boolean, List, ContinuationImpl)`, five parameters) is beyond the
patcher's inline smali compiler, which emits NOTHING for it (reproduced directly against
`InlineSmaliCompiler.Companion.compile`, 2026-11-09; one- and three-parameter methods compile
fine, and multiline inserts on such methods quietly drop their first line).
The publisher takes three clean parameters and the same flow ends there. Do not move the hook
back to the hydrate method.

Two further findings while proving the patch (2026-11-10, both surfaced by the patch run):

1. The fingerprint initially pinned `returnType = "Ljava/lang/Object;"` - a full class-name
   type declaration compares as EQUALS, and the publisher's real return is an obfuscated
   wrapper class, so the never-matching fingerprint failed the patch. The concrete return type
   is deliberately NOT pinned (that would hard-code an obfuscated name); the parameter
   signature `(List, String, TypeaheadQueryMode)` is unique in the class and carries the
   match. The obfuscated method name is never hard-coded either.
2. The publisher has 28 registers, so its parameter registers exceed the 4-bit register list
   of `invoke-static` and the call goes through `/range` (the inline compiler rejects the
   4-bit form with `Invalid register: v25`):

```smali
invoke-static/range { p1 .. p2 }, $EXTENSION_CLASS->filterSearchZeroState(Ljava/util/List;Ljava/lang/CharSequence;)V
```

```java
private static final String SEARCH_SHELF_PREFIX = "SearchTypeaheadList(";
private static final String[] SEARCH_TRENDING_ROW_PREFIXES =
        {"SearchTrendingQuery(", "SearchTypeaheadSuggestion("};

/** Injection point. Removes the Trending sections from the search zero state. */
public static void filterSearchZeroState(@Nullable List<?> items, @Nullable CharSequence query) {
    try {
        if (items == null || items.isEmpty() || !Settings.HIDE_HOME_FEED.get()) {
            return;
        }
        if (query == null || query.length() != 0) {
            return;   // a typed query: its suggestions are not the zero state
        }
        Iterator<?> iterator = items.iterator();
        while (iterator.hasNext()) {
            Object item = iterator.next();
            if (item != null && isTrendingShelf(item)) {
                iterator.remove();   // the whole shelf, so no empty section header is left
            }
        }
    } catch (Throwable ex) {
        Logger.printException(() -> "filterSearchZeroState failure", ex);
    }
}
```

A shelf is identified at runtime by its data-model name (`SearchTypeaheadList`), and its rows by
the same convention (`SearchTrendingQuery`, `SearchTypeaheadSuggestion`) - these are server-side
GraphQL/telemetry names that appear in the models' own `toString()`, not obfuscated symbols, the
same class of string the existing *Hide Trending shelves* label matching uses. The shelf's
children are read through runtime reflection on the shelf object's list-typed field, so no
obfuscated field name is needed. A shelf is dropped only when the setting is ON and at least one
of its rows is a trending-search or community-suggestion row; a shelf with only recent rows (or
an unrecognised shape) is never dropped. If this one site does not survive the device dump - the
sections still showing, or recent searches lost - the attempt stops and reports; no second site
is improvised.

## Behaviour to expect

- Open app (cold start): the search page opens by itself, as a guest, keyboard up. No login
  prompt anywhere.
- Search, tap a community, read. Back returns to search (Reddit's own stack). From search, the
  first Back closes the keyboard; continuing Back then shows the *Communities top bar* (its
  menu holds Morphe settings). No feed ever shows.
- Tap the bar's Home: search opens **each time**, and the empty `Communities` screen (top bar
  over a blank page) is attached underneath, so its menu still reaches Morphe settings after
  Back. The bare blank Home page is no longer reachable through taps.
- Tapping the empty screen's Communities tab again reopens the same empty screen (no new
  search - that path is the start tab staying put, not a launch).
- Hide feeds' zero state: *Trending* and *Trending Communities* are gone; any recent searches
  the guest has still list.
- If the search link fails: the empty page and a logged exception. Nothing crashes, no feed.
- Guest mode: reading only. No join, vote or comment.

## Not handled

- **Subreddit pages are feeds by design.** They are what the owner opens. Typing `all` or `popular`
  into search as a subreddit name may reach an unguarded listing; it needs a deliberate search.
- **Trending anywhere else:** the removal covers the search page's pre-typing state only;
  trending feed units in typed results or elsewhere are separate Reddit surfaces.
- **Other versions:** the guards are verified on 2026.45.0 only, and a miss fails the patch.
- **Cold start by external link, then Back to the tab:** the search page opens once at that
  attach. Harmless if it happens after the link's screen. If it covers the linked screen, that
  is a V12 failure and needs a guard.
- **A left swipe on the bare blank Home page** opens no drawer (measured, 2026-11-09); the
  drawer is not relied on anywhere - Morphe settings are reached through the Communities top
  bar's menu.

## Verification

Replaced and extended by the third amendment: V5 restored to auto-open (no LOOSENED any more),
Home-tap rows, V18-V20 added for the hook-6 tap flow, the Inbox toggle and the trending
removal. All rows stand unless amended below. Device runs need the owner to keep the phone
unlocked: it has a lock screen that adb cannot clear.

| # | Check |
|---|---|
| V5 | Setting ON, cold start: **the search page opens by itself**, no feed at any moment, Home button present, no login prompt (auto-open restored by hook 5) |
| V6 | Type a subreddit name, open it from the results: its feed loads as a guest. Back returns to search |
| V7 | Back from search until it is gone: no feed, no crash; tapping the Communities top bar's search button opens search again |
| V12 | Open a `reddit.com/r/<sub>` link from another app, cold: the subreddit stays on top, no search page over it |
| V16 | Setting ON, each route shows no feed: `https://www.reddit.com/`, `/r/popular`, the Communities tab re-tapped, the drawer's Discover, Popular and Latest rows, app resumed after the `REDIRECT_TO_HOME` timeout. **All V16 routes are exercised with and without a Communities tab** |
| V17 | Setting OFF: Home, Discover and Popular all render normally |
| V18 | Tap Home, close search with Back, repeat three or more times: search opens every time, and the bare blank Home page *never* appears after a tap flow. After each Back the Communities top bar is present and its menu still reaches the Morphe entry |
| V19 | *Hide Inbox button* ON: both `Inbox` and `UnifiedInbox` bars disappear (the bar reads Home Create You); OFF leaves them |
| V20 | Setting ON, the search page before typing shows **no Trending or Trending Communities sections**; recent searches, if present, still list (before-and-after dump) |

**The ones that matter:** V16 is the requirement. V17 is the promise to anyone who leaves it off.
V18 is the third amendment's behavioral core.

**S1 redefined for the third amendment (2026-11-09):** with hooks 5-6 in, S1 proves the full
cold start (V5 restored, no LOOSENED), the Back flow to the Communities top bar, the Home-tap
flow (V18), the Morphe reachability through the Communities menu, and the guest search of a
subreddit with Back returning to search. The launcher-dump rule stays: a uiautomator dump of
anything that is not Reddit is a harness error, never a result. Checks install the freshly
patched build with `install -r` (data kept) - never a marker-based skip, so a check can never
pass against an older build.

## Roads not taken

- **Covering the feed with search only (earlier draft of this note):** Back from search exposed
  Discover. Rejected by the owner as critical.
- **Hiding the view at attach:** depends on timing, can flash, and covers only the routes hooked.
- **Search as the tab's content:** `TypeaheadResultsScreen` does not implement the tab interface
  `uf6`, so it would need the same spike v1 declined for the drawer.
- **Stored whitelist in a dialog:** works without login, but the owner prefers searching each time.
- **Drawer (v1), anonymous account:** both need a login, which the owner has ruled out.

## Open questions

- [x] ~~Does the query-less link show the search page, for a guest, with community
      suggestions?~~ Resolved 2026-11-09 on the phone: it opens (via an external `am start`;
      the hook-4 launch itself is unreachable until the Communities screen attaches, see the
      stop condition in `../decisions/S01-communities-tab.md`).
- [x] ~~Does the search page show feed-like content before typing?~~ Resolved 2026-11-09: the
      zero state shows *Trending* (trending searches) and *Trending Communities* sections; the
      owner decided they are removed when the setting is ON (see *Search zero state* above).
      Screenshot: `evidence/S01-search-zero-state.png`.
- [x] ~~Does the keyboard open automatically?~~ Yes (2026-11-09). Cosmetic.
- [ ] Does an early return from the render method leave any screen in a bad state, for example
      a spinner or a crash on tab re-select? (blocked until the screen attaches)
- [x] ~~Is Morphe settings reachable from the avatar menu as a guest, to turn the toggle on?~~
      Resolved 2026-11-09: as a guest, the left drawer has a *Morphe* entry that opens the
      Morphe settings.
- [x] ~~Why does the redirected `CommunitiesTabScreen` not attach on cold start?~~ Resolved
      2026-11-09 by the third amendment: the cold-start visible screen is the guarded
      `HomePagerScreen`, built directly by a separate `BottomNavScreen` method, so no
      tab-selection site decides it, and hook 1's push wiring does not reach the first screen.
      The owner chose to land the cold start at the *attach* of that screen (hook 5) rather
      than keep tracing selection sites; the Home-tap path stays on the funnel (hooks 3+6) and
      the start tab keeps its own attach hook (hook 4).
