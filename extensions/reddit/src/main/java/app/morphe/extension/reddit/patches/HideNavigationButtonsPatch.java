/*
 * Copyright 2026 Morphe.
 * https://github.com/MorpheApp/morphe-patches
 *
 * See the included NOTICE file for GPLv3 Section 7 terms that apply to this code.
 */

package app.morphe.extension.reddit.patches;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.SystemClock;
import android.view.View;

import androidx.annotation.Nullable;

import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.lang.ref.WeakReference;

import java.util.Iterator;

import app.morphe.extension.reddit.settings.Settings;
import app.morphe.extension.shared.Logger;
import app.morphe.extension.shared.ResourceUtils;

import kotlin.Unit;

@SuppressWarnings("unused")
public final class HideNavigationButtonsPatch {
    /**
     * Interface to use obfuscated methods.
     */
    public interface NavigationButtonInterface {
        // Methods are added during patching.
        String patch_getLabel();
    }

    private static final String SEARCH_PAGE_URL = "https://www.reddit.com/search";
    private static final String START_TAB_NAME = "Communities";
    private static final String HOME_TAB_NAME = "Home";
    private static final long SEARCH_LAUNCH_DEBOUNCE_MS = 1000;

    private static final String SEARCH_SHELF_PREFIX = "SearchTypeaheadList(";
    private static final String[] SEARCH_TRENDING_ROW_PREFIXES = {
            "SearchTrendingQuery(", "SearchTypeaheadSuggestion("
    };

    private static boolean searchLaunched;
    private static long lastSearchLaunchAtMs;
    private static WeakReference<Context> attachedContext = new WeakReference<>(null);

    private static final Map<String, NavigationButtonLegacy> labelToButtonLegacy = new HashMap<>();
    private static final Map<String, NavigationButton> labelToButton = new HashMap<>();

    static {
        for (NavigationButtonLegacy button : NavigationButtonLegacy.values()) {
            labelToButtonLegacy.put(button.label, button);
        }

        for (NavigationButton button : NavigationButton.values()) {
            labelToButton.put(button.name(), button);
        }
    }

    /**
     * @return If this patch was included during patching.
     */
    public static boolean isPatchIncluded() {
        return false;  // Modified during patching.
    }

    /**
     * Injection point.
     */
    public static void hideNavigationButtonsLegacy(List<Object> list, Object object) {
        if (list == null) {
            return;
        }

        if (object instanceof NavigationButtonInterface button) {
            String label = button.patch_getLabel();
            if (label != null) {
                NavigationButtonLegacy buttonEnum = labelToButtonLegacy.get(label);
                if (buttonEnum != null && buttonEnum.shouldHide) {
                    return;
                }
            }
        }

        list.add(object);
    }

    /**
     * Injection point.
     */
    public static boolean hideNavigationTab(@Nullable Enum<?> tab) {
        if (tab == null) {
            return false;
        }

        // The start tab holds the landing surface (search opens from its attach), so it is
        // never hidden from the bar - not even by the "Hide Discover or Communities button"
        // option, which maps to the same tab.
        if (Settings.HIDE_HOME_FEED.get() && START_TAB_NAME.equals(tab.name())) {
            return false;
        }

        NavigationButton button = labelToButton.get(tab.name());
        return button != null && button.shouldHide;
    }

    /**
     * Injection point. Replaces Home with the start tab. Any failure returns original.
     */
    @SuppressWarnings({"unchecked", "rawtypes"})
    public static Enum<?> getStartTab(@Nullable Enum<?> original) {
        try {
            if (original == null || !Settings.HIDE_HOME_FEED.get() || !HOME_TAB_NAME.equals(original.name())) {
                return original;
            }
            return Enum.valueOf((Class) original.getDeclaringClass(), START_TAB_NAME);
        } catch (Exception ex) {
            Logger.printException(() -> "getStartTab failure", ex);
            return original;
        }
    }

    /**
     * Injection point. Rewrites the bottom bar's tapped tab and opens search for Home taps.
     * Any failure returns the original tab.
     */
    @SuppressWarnings({"unchecked", "rawtypes"})
    public static Enum<?> onBottomTabTapped(@Nullable Enum<?> tapped) {
        try {
            if (tapped == null || !Settings.HIDE_HOME_FEED.get() || !HOME_TAB_NAME.equals(tapped.name())) {
                return tapped;
            }
            Context context = attachedContext.get();
            if (context != null) {
                // Every Home tap opens search, and also sets the once-per-process flag
                // so the attach hooks cannot open a second search over this one.
                searchLaunched = true;
                openSearchPage(context);
            }
            // Do not short-circuit the caller: the tap handler keeps running, the start
            // tab attaches underneath, and its top bar (with Morphe settings) stays
            // reachable.
            return Enum.valueOf((Class) tapped.getDeclaringClass(), START_TAB_NAME);
        } catch (Exception ex) {
            Logger.printException(() -> "onBottomTabTapped failure", ex);
            return tapped;
        }
    }

    /**
     * Injection point. True blocks a feed screen from rendering.
     */
    public static boolean hideFeedScreen() {
        return Settings.HIDE_HOME_FEED.get();
    }

    /**
     * Injection point (hooks 4 and 5). Opens Reddit's search page on the first attach of
     * the start tab or of the guarded Home screen, once per process.
     */
    public static void onStartTabAttached(View view) {
        if (!Settings.HIDE_HOME_FEED.get()) {
            return;
        }
        // Serves the tap path (hook 6), which has no View of its own.
        attachedContext.clear();
        attachedContext = new WeakReference<>(view.getContext());
        if (searchLaunched) {
            return;
        }
        // Set before firing. The link re-enters MainActivity, which can re-attach tabs.
        searchLaunched = true;
        view.post(() -> openSearchPage(view.getContext()));
    }

    /**
     * One shared search launch: debounced, failures logged, never crashing.
     */
    private static void openSearchPage(@Nullable Context context) {
        try {
            long now = SystemClock.elapsedRealtime();
            if (now - lastSearchLaunchAtMs < SEARCH_LAUNCH_DEBOUNCE_MS) {
                return;
            }
            // Stamped before the attempt: for the debounce window it does not matter
            // whether this launch succeeded.
            lastSearchLaunchAtMs = now;
            context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SEARCH_PAGE_URL))
                    .setPackage(context.getPackageName()));
        } catch (Exception ex) {
            Logger.printException(() -> "openSearchPage failure", ex);
        }
    }

    /**
     * Injection point. Removes the Trending sections (trending searches and trending
     * communities) from the search page's pre-typing state, dropping their shelves from
     * the list in place. Runs for every typeahead publish, so the query decides: only an
     * empty query (the zero state) is filtered. Recent-search shelves stay. Failures
     * leave the list untouched.
     */
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

    /**
     * Injection point (hook 7). Ends the welcome flow's onInitialize coroutine at its
     * entry with the canonical completed-coroutine value, so its launch-time credential
     * query never runs: the system credential providers answer the query with a chooser
     * sheet that parks over the app on every cold start, and this fork has no sign-in
     * surface at all. Not gated on the toggle - the query is the app asking for sign-in
     * options, which this fork never offers.
     */
    public static Object skipWelcomeCredentialQuery() {
        Logger.printDebug(() -> "Welcome credential query skipped");
        return Unit.a;
    }

    private static boolean isTrendingShelf(@Nullable Object shelf) {        if (shelf == null) {
            return false;
        }
        // The models are domain data: their toString() starts with the GraphQL model name,
        // which is not an obfuscated symbol (the same class of string the shelf rows use).
        if (!shelf.toString().startsWith(SEARCH_SHELF_PREFIX)) {
            return false;
        }
        List<?> rows = listFieldOf(shelf);
        if (rows == null || rows.isEmpty()) {
            return false;   // an unrecognised shelf is never dropped
        }
        for (Object row : rows) {
            if (row == null) {
                continue;
            }
            String rowName = row.toString();
            for (String prefix : SEARCH_TRENDING_ROW_PREFIXES) {
                if (rowName.startsWith(prefix)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * The shelf's row list lives in its only list-typed field, which has an obfuscated
     * name. Reading it by declared type keeps any obfuscated name out of this code.
     */
    @Nullable
    private static List<?> listFieldOf(Object shelf) {
        for (Field field : shelf.getClass().getDeclaredFields()) {
            if (field.getType() == List.class) {
                field.setAccessible(true);
                try {
                    return (List<?>) field.get(shelf);
                } catch (IllegalAccessException ex) {
                    return null;
                }
            }
        }
        return null;
    }

    private enum NavigationButton {
        Answers(Settings.HIDE_ANSWERS_BUTTON.get()),
        Chat(Settings.HIDE_CHAT_BUTTON.get()),
        Communities(Settings.HIDE_DISCOVER_BUTTON.get()),
        Games(Settings.HIDE_GAMES_BUTTON.get()),
        Home(false),
        Inbox(Settings.HIDE_INBOX_BUTTON.get()),
        MyCommunities(Settings.HIDE_DISCOVER_BUTTON.get()),
        Post(Settings.HIDE_CREATE_BUTTON.get()),
        Profile(false),
        UnifiedInbox(Settings.HIDE_INBOX_BUTTON.get());

        final boolean shouldHide;

        NavigationButton(boolean shouldHide) {
            this.shouldHide = shouldHide;
        }
    }

    private enum NavigationButtonLegacy {
        ANSWERS(Settings.HIDE_ANSWERS_BUTTON.get(), "answers_label"),
        CHAT(Settings.HIDE_CHAT_BUTTON.get(), "label_chat"),
        CREATE(Settings.HIDE_CREATE_BUTTON.get(), "action_create"),
        DISCOVER(Settings.HIDE_DISCOVER_BUTTON.get(), "communities_label"),
        GAMES(Settings.HIDE_GAMES_BUTTON.get(), "label_games");

        final boolean shouldHide;
        final String label;

        NavigationButtonLegacy(boolean shouldHide, String resourceName) {
            this.shouldHide = shouldHide;
            this.label = ResourceUtils.getStringIdentifier(resourceName) == 0
                    ? "dummy_bogus_legacy_label" // Some legacy strings are missing with 2026.26.0+
                    : ResourceUtils.getString(resourceName);
        }
    }
}
