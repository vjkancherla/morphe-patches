/*
 * Copyright 2026 Morphe.
 * https://github.com/MorpheApp/morphe-patches
 *
 * See the included NOTICE file for GPLv3 Section 7 terms that apply to this code.
 */

package app.morphe.extension.reddit.patches;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import app.morphe.extension.reddit.settings.Settings;
import app.morphe.extension.shared.Logger;
import app.morphe.extension.shared.ResourceUtils;

@SuppressWarnings("unused")
public final class HideNavigationButtonsPatch {
    /**
     * Interface to use obfuscated methods.
     */
    public interface NavigationButtonInterface {
        // Methods are added during patching.
        String patch_getLabel();
    }

    public interface StartTabScreenInterface {
        // Method is added during patching.
        void patch_openCommunityDrawer();
    }

    // Ponytail: a fixed timer on a slow device may fire before Reddit's drawer event
    // collector is alive, silently dropping the open; if S2's cold-start run shows a
    // generous value does not hold, the upgrade path is a later lifecycle hook.
    private static final long START_DRAWER_DELAY_MS = 1500L;

    private static boolean startDrawerRequested;

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

        NavigationButton button = labelToButton.get(tab.name());
        return button != null && button.shouldHide;
    }

    /**
     * Injection point.
     */
    public static void onStartTabAttached(Object screen) {
        if (!Settings.HIDE_HOME_FEED.get() || startDrawerRequested) {
            return;
        }
        startDrawerRequested = true;

        // The event the tab's menu button emits has no replay, so the call is delayed
        // once, until Reddit's drawer event collector is alive. Any failure keeps the
        // app working exactly as unpatched - the user is one swipe from the drawer.
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                ((StartTabScreenInterface) screen).patch_openCommunityDrawer();
            } catch (Exception ex) {
                Logger.printException(() -> "onStartTabAttached failure", ex);
            }
        }, START_DRAWER_DELAY_MS);
    }

    private enum NavigationButton {
        Answers(Settings.HIDE_ANSWERS_BUTTON.get()),
        Chat(Settings.HIDE_CHAT_BUTTON.get()),
        Communities(Settings.HIDE_DISCOVER_BUTTON.get()),
        Games(Settings.HIDE_GAMES_BUTTON.get()),
        Home(false),
        Inbox(false),
        MyCommunities(Settings.HIDE_DISCOVER_BUTTON.get()),
        Post(Settings.HIDE_CREATE_BUTTON.get()),
        Profile(false),
        UnifiedInbox(false);

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
