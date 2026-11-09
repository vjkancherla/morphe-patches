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
