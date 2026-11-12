/*
 * Copyright 2026 Morphe.
 * https://github.com/MorpheApp/morphe-patches
 *
 * See the included NOTICE file for GPLv3 Section 7 terms that apply to this code.
 */

package app.morphe.patches.reddit.layout.navigation

import app.morphe.patcher.Fingerprint
import app.morphe.patcher.fieldAccess
import app.morphe.patcher.literal
import app.morphe.patcher.methodCall
import app.morphe.patcher.newInstance
import com.android.tools.smali.dexlib2.AccessFlags
import com.android.tools.smali.dexlib2.Opcode
import com.android.tools.smali.dexlib2.iface.reference.MethodReference

internal val ADD_METHOD_CALL = methodCall(
    opcode = Opcode.INVOKE_INTERFACE,
    smali = "Ljava/util/List;->add(Ljava/lang/Object;)Z"
)

internal object BottomNavScreenListBuilderFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/launch/bottomnav/BottomNavScreen;",
    returnType = "L",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    filters = listOf(
        newInstance("Ljava/util/ArrayList;"),
        methodCall(
            opcode = Opcode.INVOKE_INTERFACE,
            smali = "Ljava/util/Iterator;->hasNext()Z"
        ),
        fieldAccess(
            opcode = Opcode.IGET_OBJECT,
            type = "Lcom/reddit/launch/bottomnav/BottomNavTab;"
        )
    )
)

internal object BottomNavScreenResourceBuilderLegacyFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/launch/bottomnav/BottomNavScreen;",
    returnType = "L",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    filters = listOf(
        methodCall(
            opcode = Opcode.INVOKE_DIRECT,
            parameters = listOf("Ljava/lang/String;", "L")
        ),
        ADD_METHOD_CALL
    ),
    strings = listOf("answersFeatures")
)

/**
 * The Communities tab's attach (`L3` in 2026.45.0) without its obfuscated name: the only
 * void method of the screen taking a View that hands the screen itself to the achievements
 * proxy. The visually identical variant (`W3` in 2026.45.0) calls the proxy with no
 * arguments, so this filter alone separates them.
 *
 * Never hard-code the class' obfuscated members; index registers come from the matched
 * call, and the extension always receives the screen as the method's own this-register.
 */
internal object CommunitiesTabScreenDrawerProxyFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/communitiestab/compose/CommunitiesTabScreen;",
    returnType = "V",
    parameters = listOf("Landroid/view/View;"),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    filters = listOf(
        methodCall(
            opcode = Opcode.INVOKE_VIRTUAL,
            parameters = listOf("Lcom/reddit/screen/ComposeScreen;")
        )
    ),
    strings = listOf("achievementsNotificationsProxy")
)

/**
 * Hook 1: the start-tab replacement (`I5` in 2026.45.0). Public final, returns void, and the
 * only method of `BottomNavScreen` taking a single `BottomNavTab` parameter. It installs the
 * first screen on the stack, so injecting at its entry redirects every internal "go to Home"
 * except the initial_tab default (hook 2) and the programmatic selections (hook 3).
 */
internal object BottomNavScreenSelectTabFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/launch/bottomnav/BottomNavScreen;",
    returnType = "V",
    parameters = listOf("Lcom/reddit/launch/bottomnav/BottomNavTab;"),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL)
)

/**
 * Hook 2: the initial-tab default (`e5` in 2026.45.0). The screen's initialization reads the
 * `com.reddit.arg.initial_tab` extra and falls back to the `Home` enum constant when the
 * extra is absent, which is every plain cold start. Matched by that string (the only method
 * of the class holding it) and the `sget-object` of the fallback.
 */
internal object BottomNavScreenInitialTabFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/launch/bottomnav/BottomNavScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    strings = listOf("com.reddit.arg.initial_tab"),
    filters = listOf(
        fieldAccess(
            opcode = Opcode.SGET_OBJECT,
            definingClass = "Lcom/reddit/launch/bottomnav/BottomNavTab;",
            name = "Home"
        )
    )
)

/**
 * Hook 3: the selection funnel (the presenter's `T` in 2026.45.0). The presenter's class
 * name is unstable, so no definingClass: the only public final void method taking a tab and
 * a boolean that reads the `Inbox` enum constant. `BottomNavScreen.N5` has the same
 * signature but never reads it; `Q` reads `Profile`.
 */
internal object BottomNavTabSelectionFingerprint : Fingerprint(
    returnType = "V",
    parameters = listOf("Lcom/reddit/launch/bottomnav/BottomNavTab;", "Z"),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    filters = listOf(
        fieldAccess(
            opcode = Opcode.SGET_OBJECT,
            definingClass = "Lcom/reddit/launch/bottomnav/BottomNavTab;",
            name = "Inbox"
        )
    )
)

/**
 * Hook 5: the guarded Home screen's attach (the `L3` override in 2026.45.0). The only
 * public final void method of the screen taking one `View` that calls its super twin first,
 * makes exactly one further part call and returns - two registers, four instructions. Its
 * detach twin ([HomePagerScreenDetachFingerprint] below) has the same signature but
 * dismisses the banner sheet and launches the on-detach coroutine, so it is five registers
 * and double-digit instructions; the size difference separates them without any obfuscated
 * name.
 */
internal object HomePagerScreenAttachFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen;",
    returnType = "V",
    parameters = listOf("Landroid/view/View;"),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    custom = { _, _ -> true }
)

/**
 * Hook 5's detach twin, matched only to prove the pair of View-parameter overrides is
 * complete and no third one lies in between (the patch asserts exactly two exist and that
 * they are distinct methods).
 */
internal object HomePagerScreenDetachFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen;",
    returnType = "V",
    parameters = listOf("Landroid/view/View;"),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    strings = listOf("feedTransitionBehaviorProvider")
)

/**
 * Hook 6: the bottom bar's tap handler. A synthetic `kotlin.jvm.functions.Function0`
 * implementation in the `com.reddit.launch.bottomnav` package whose `invoke()` reads the
 * tapped tab off the bar item into the register every later comparison uses - including the
 * already-selected branch that previously let repeated Home taps skip the selection funnel.
 * Matched by its two property-name strings (both unique to it app-wide) and the single
 * `iget-object` of a `BottomNavTab`-typed field.
 */
internal object BottomNavTabTapHandlerFingerprint : Fingerprint(
    returnType = "Ljava/lang/Object;",
    parameters = listOf(),
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    strings = listOf("loggedOutBottomSheetScreenFactory", "feedRefreshPolicy"),
    filters = listOf(
        fieldAccess(
            opcode = Opcode.IGET_OBJECT,
            type = "Lcom/reddit/launch/bottomnav/BottomNavTab;"
        )
    )
)

/**
 * The five feed screens (2026.45.0). Their class names are not obfuscated; the render
 * method is (`V2` in this build). Each is matched structurally as the public final void
 * method taking a Compose state and an int, and pinned by the compose key literal the v2
 * note records. `HomePagerScreen` has four methods with that signature, so the literal is
 * required there; every literal occurs exactly once in its class.
 */
internal object ExploreFeedScreenFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/communitiestab/explore/ExploreFeedScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf("L", "I"),
    filters = listOf(literal(888459659))
)

internal object HomePagerScreenFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feedslegacy/switcher/impl/homepager/compose/HomePagerScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf("L", "I"),
    filters = listOf(literal(-1198908911))
)

internal object PopularFeedScreenFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feeds/popular/impl/ui/PopularFeedScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf("L", "I"),
    filters = listOf(literal(2024162344))
)

internal object LatestFeedScreenFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feeds/latest/impl/ui/LatestFeedScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf("L", "I"),
    filters = listOf(literal(-1095661192))
)

internal object NewsFeedScreenFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/feeds/news/impl/NewsFeedScreen;",
    returnType = "V",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf("L", "I"),
    filters = listOf(literal(1045476250))
)

/**
 * The search zero state's terminal publisher (the repository's curate-and-publish method in
 * 2026.45.0, class `com/reddit/typeahead/data/f` - the class name is not obfuscated, the
 * method's is). Every zero-state request ends here - the cached branch of the global
 * zero-state request and the empty-query branch of the network fetch - with the finished
 * shelf list as its first parameter and the query string as its second; its output is both
 * the published state flow and the returned response, so dropping the Trending shelves at
 * its entry removes the *Trending* and *Trending Communities* sections from the page while
 * recent-search shelves stay. Typed queries also pass through it, but the extension filters
 * only when the query is empty, so typed suggestions are untouched.
 *
 * Matched purely by the signature (public final, `(List, String, TypeaheadQueryMode)` -
 * the only method of the class with it); the obfuscated method name is never hard-coded.
 * The concrete return type is NOT pinned: a full class-name return type declaration compares
 * as EQUALS and the method's real return is an obfuscated wrapper class (it would have to be
 * hard-coded, which this codebase never does) - omitting it reduces the candidates to the
 * methods of the class matching the parameter signature, which is unique.
 * Verified against APK bytecode, since the hydrate method the shelves also pass through
 * fails to decompile - and that shape (List, FilterValues, boolean, List,
 * ContinuationImpl) cannot be injected into at all: the patcher's inline smali compiler
 * emits nothing for it (reproduced against the compiler, 2026-11-09).
 */
internal object SearchZeroStateFilterFingerprint : Fingerprint(
    definingClass = "Lcom/reddit/typeahead/data/f;",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf(
        "Ljava/util/List;",
        "Ljava/lang/String;",
        "Lcom/reddit/search/domain/model/TypeaheadQueryMode;"
    )
)

/**
 * The credentials datasource's R8-moved coroutine body (the
 * `RedditCredentialsDataSource` fetch in 2026.45.0; the class and the method are both
 * obfuscated, so neither is hard-coded). Pinned structurally instead: the suspend-lambda
 * dispatch shape (public final, `(Activity, List, Z, ContinuationImpl) -> Object`) plus
 * the three datasource-unique log/tag strings, which the bytecode carries verbatim.
 * Verified unique against the 2026.45.0 APK (exactly one method in the whole app matches).
 *
 * This method is what every sign-in-questions flow asks the system credential providers
 * with. The hook on it is LOG ONLY: it records who asks for credentials, so if the
 * credential chooser sheet ever returns, its stack names the requesting path.
 */
internal object CredentialsDataSourceLogTripwireFingerprint : Fingerprint(
    returnType = "Ljava/lang/Object;",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf(
        "Landroid/app/Activity;",
        "Ljava/util/List;",
        "Z",
        "Lkotlin/coroutines/jvm/internal/ContinuationImpl;"
    ),
    strings = listOf(
        "credentials_manager_data_source",
        "androidx.credentials.BUNDLE_KEY_ALLOWED_USER_IDS",
        "android.credentials.TYPE_PASSWORD_CREDENTIAL"
    )
)

/**
 * The auto-login use case's resolve method (`RedditAutoLoginUseCase` in 2026.45.0; the
 * class and the method are both obfuscated, so neither is hard-coded). Pinned
 * structurally: the suspend-lambda dispatch shape (public final,
 * `(String, ?, Z, Z, String, ?, ContinuationImpl) -> Object`) plus its four
 * error-source tag strings, which the bytecode carries verbatim. Verified unique against
 * the 2026.45.0 APK (exactly one method in the whole app matches).
 *
 * This runs at every app launch (auto-login / saved-account restore) and asks the
 * credential providers to resolve saved accounts. LOG ONLY: same tripwire purpose as
 * the datasource hook above.
 */
internal object AutoLoginResolveCredentialsLogTripwireFingerprint : Fingerprint(
    returnType = "Ljava/lang/Object;",
    accessFlags = listOf(AccessFlags.PUBLIC, AccessFlags.FINAL),
    parameters = listOf(
        "Ljava/lang/String;",
        "L",
        "Z",
        "Z",
        "Ljava/lang/String;",
        "L",
        "Lkotlin/coroutines/jvm/internal/ContinuationImpl;"
    ),
    strings = listOf(
        "AutoLogin",
        "invalid_account_data",
        "username_retrieval_error",
        "username_unavailable"
    )
)
