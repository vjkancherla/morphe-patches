# Hide Home Feed - Design Note (v2: no feeds, land on Search, no login)

Date: 2026-11-08
Supersedes: `hide-home-feed.md` (v1), for the landing surface only. v1 stays as the record, and
its Hooks 1-3, "Why these sites" table, failure modes 1, 3 and 4, and build facts still apply
unless changed below. Verified against Reddit 2026.45.0 only.

Stated intent (owner, 2026-11-08): "I do not want to login to reddit", "when I open, I see the
search page and not the feed page and I will search for the subreddit I want to use", and
"I do not want to see the feed at all, this is critical."

## Decision

*Navigation bar → Hide Home feed*, when ON:

1. **No feed screen ever renders.** Reddit's five feed screens draw nothing. This is the
   guarantee, and it does not depend on navigation or timing.
2. The Home tab leaves the bar, and every internal "go to Home" lands on the `Communities` tab
   (v1 hooks 1-3, unchanged). That tab now shows only Reddit's top bar over an empty page.
3. On the first attach of that tab in each process, the app opens Reddit's own search page.

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
`MainActivity` with status ok. The phone was locked, so the screen it reached was **not seen**.
S1 below settles that.

## What changes from the S1 spike code

Remove, all of it reachable only from the drawer route:

- `StartTabScreenInterface` and `START_DRAWER_DELAY_MS` in the extension.
- `TabScreenClickHandlerProviderFingerprint` in `Fingerprints.kt`.
- In `HideNavigationButtonsPatch.kt`: the `interfaces.add(EXTENSION_START_TAB_SCREEN_INTERFACE)`
  block, the `communityNavIconClickHandler` lookup and the added `patch_openCommunityDrawer` method.

Keep `CommunitiesTabScreenDrawerProxyFingerprint`, the setting and the toggle. Hook 4 stays at the
same site but passes the view, so the extension has an Activity context:

```smali
invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V
```

Extension, replacing the current `onStartTabAttached`:

```java
private static final String SEARCH_PAGE_URL = "https://www.reddit.com/search";

private static boolean startSearchRequested;

/** Injection point. Opens Reddit's search page once per process. */
public static void onStartTabAttached(View view) {
    if (!Settings.HIDE_HOME_FEED.get() || startSearchRequested) return;
    // Set before firing. The link re-enters MainActivity, which can re-attach this tab.
    startSearchRequested = true;
    view.post(() -> {
        try {
            Context context = view.getContext();
            context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SEARCH_PAGE_URL))
                    .setPackage(context.getPackageName()));
        } catch (Exception ex) {
            Logger.printException(() -> "onStartTabAttached failure", ex);
        }
    });
}
```

The once-per-process flag is what prevents a loop. Do not remove it.

Product files remain the six allowed in v1, with the guards added to the navigation
`Fingerprints.kt` and `HideNavigationButtonsPatch.kt`. `Home(false)` still becomes
`Home(Settings.HIDE_HOME_FEED.get())`, and `hideNavigationTab` still protects the start tab. Change
the base-`values` title to `Hide feeds`, since the toggle now covers all five. Keep the setting key.

## Behaviour to expect

- Open app: search page. Search, tap a community, read. Back returns to search (Reddit's own stack).
- Back from search: the `Communities` tab with its top bar and an empty page. Its search button
  returns to search. Back again exits.
- If the search link fails: the same empty page and a logged exception. Nothing crashes, no feed.
- Guest mode: reading only. No join, vote or comment.

## Not handled

- **Subreddit pages are feeds by design.** They are what the owner opens. Typing `all` or `popular`
  into search as a subreddit name may reach an unguarded listing; it needs a deliberate search.
- **Search page zero state:** Reddit may show trending or suggested items before typing
  (`RedditDynamicTypeaheadAndZeroStateRepository`). Not seen yet. If it looks like a feed, that is
  an S1 failure and needs its own guard.
- **Other versions:** the guards are verified on 2026.45.0 only, and a miss fails the patch.
- **Cold start by external link, then Back to the tab:** the search page opens once at that attach.
  Harmless if it happens after the link's screen. If it covers the linked screen, that is a V12
  failure and needs a guard.

## Verification

Replaces v1's V5, V6, V7 and V12 and the S1 check, and adds V16 and V17. All other V rows stand.
Device runs need the owner to keep the phone unlocked: it has a lock screen that adb cannot clear.

| # | Check |
|---|---|
| V5 | Setting ON, cold start: search page shows, no Home tab, no login prompt, no feed at any moment |
| V6 | Type a subreddit name, open it from the results: its feed loads as a guest. Back returns to search |
| V7 | Back from search: top bar over an empty page, no crash. Its search button opens search. Back again exits or stays |
| V12 | Open a `reddit.com/r/<sub>` link from another app, cold: the subreddit stays on top, no search page over it |
| V16 | Setting ON, each route shows no feed: `https://www.reddit.com/`, `/r/popular`, the `Communities` tab re-tapped, the drawer's Discover, Popular and Latest rows, app resumed after the `REDIRECT_TO_HOME` timeout |
| V17 | Setting OFF: Home, Discover and Popular all render normally |

**The ones that matter:** V16 is the requirement. V17 is the promise to anyone who leaves it off.

**S1 redefined:** remove `signed_in_gate` from `scripts/checks/S01.sh`. S1 now proves, with the toggle on
and all five guards in place: tapping `Communities` opens the search page, Back shows the empty
tab with no Discover feed, and no crash. Hooks 1-3 land in S2 as planned, so V5's cold start and
the rest of V16 are proved there. Log the change in the plan's Changes log, with `LOOSENED:`
if any check proves less.

## Roads not taken

- **Covering the feed with search only (earlier draft of this note):** Back from search exposed
  Discover. Rejected by the owner as critical.
- **Hiding the view at attach:** depends on timing, can flash, and covers only the routes hooked.
- **Search as the tab's content:** `TypeaheadResultsScreen` does not implement the tab interface
  `uf6`, so it would need the same spike v1 declined for the drawer.
- **Stored whitelist in a dialog:** works without login, but the owner prefers searching each time.
- **Drawer (v1), anonymous account:** both need a login, which the owner has ruled out.

## Open questions

- [ ] Does the query-less link show the search page, for a guest, with community suggestions? (S1)
- [ ] Does the search page show feed-like content before typing? (S1, owner's eyes)
- [ ] Does the keyboard open automatically? Cosmetic. (S1)
- [ ] Does an early return from the render method leave any screen in a bad state, for example a
      spinner or a crash on tab re-select? (S1)
- [ ] Is Morphe settings reachable from the avatar menu as a guest, to turn the toggle on? (S1)
- [ ] Does `view.post` fire early enough on cold start, or does the link race Reddit's startup? (S1)
