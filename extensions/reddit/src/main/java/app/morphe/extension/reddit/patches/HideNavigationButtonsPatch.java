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
import android.view.View;

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

    private static final String SEARCH_PAGE_URL = "https://www.reddit.com/search";
    private static final String START_TAB_NAME = "Communities";

    private static boolean startSearchRequested;

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
            if (original == null || !Settings.HIDE_HOME_FEED.get() || !"Home".equals(original.name())) {
                return original;
            }
            return Enum.valueOf((Class) original.getDeclaringClass(), START_TAB_NAME);
        } catch (Exception ex) {
            Logger.printException(() -> "getStartTab failure", ex);
            return original;
        }
    }

    /**
     * Injection point. True blocks a feed screen from rendering.
     */
    public static boolean hideFeedScreen() {
        return Settings.HIDE_HOME_FEED.get();
    }

    /**
     * Injection point. Opens Reddit's search page once per process.
     */
    public static void onStartTabAttached(View view) {
        if (!Settings.HIDE_HOME_FEED.get() || startSearchRequested) {
            return;
        }
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
