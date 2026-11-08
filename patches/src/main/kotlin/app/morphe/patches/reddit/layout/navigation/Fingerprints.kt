/*
 * Copyright 2026 Morphe.
 * https://github.com/MorpheApp/morphe-patches
 *
 * See the included NOTICE file for GPLv3 Section 7 terms that apply to this code.
 */

package app.morphe.patches.reddit.layout.navigation

import app.morphe.patcher.Fingerprint
import app.morphe.patcher.fieldAccess
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
 * The lambda that wires the tab's nav-icon click (`com.reddit.communitiestab.compose.a`
 * in 2026.45.0) without its obfuscated name: among the screen's fields it reads the one
 * holding the drawer's event provider. The string only occurs inside this lambda's
 * method, and the field it null-checks is the provider; the cast to the provider's type
 * follows the `get()` call right after the field read.
 *
 * Obfuscated names are resolved from the matched instructions - never written here.
 */
internal object TabScreenClickHandlerProviderFingerprint : Fingerprint(
    strings = listOf("communityNavIconClickHandler"),
    filters = listOf(
        fieldAccess(
            opcode = Opcode.IGET_OBJECT,
            definingClass = "Lcom/reddit/communitiestab/compose/CommunitiesTabScreen;"
        )
    )
)
