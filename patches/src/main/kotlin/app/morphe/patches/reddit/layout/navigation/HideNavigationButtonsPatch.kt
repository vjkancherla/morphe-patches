/*
 * Copyright 2026 Morphe.
 * https://github.com/MorpheApp/morphe-patches
 *
 * See the included NOTICE file for GPLv3 Section 7 terms that apply to this code.
 */

package app.morphe.patches.reddit.layout.navigation

import app.morphe.patcher.extensions.InstructionExtensions.addInstructions
import app.morphe.patcher.extensions.InstructionExtensions.addInstructionsWithLabels
import app.morphe.patcher.extensions.InstructionExtensions.getInstruction
import app.morphe.patcher.extensions.InstructionExtensions.replaceInstruction
import app.morphe.patcher.patch.PatchException
import app.morphe.patcher.patch.mutableClassDefBy
import app.morphe.patcher.patch.patch
import app.morphe.patcher.util.findFreeRegister
import app.morphe.patcher.util.proxy.mutableTypes.MutableMethod
import app.morphe.patcher.util.proxy.mutableTypes.MutableMethod.Companion.toMutable
import app.morphe.patcher.util.returnEarly
import app.morphe.patcher.util.smali.ExternalLabel
import app.morphe.patches.reddit.misc.settings.settingsPatch
import app.morphe.patches.reddit.misc.version.is_2026_25_0_or_greater
import app.morphe.patches.reddit.misc.version.versionCheckPatch
import app.morphe.patches.reddit.shared.Constants.COMPATIBILITY_REDDIT
import app.morphe.util.findInstructionIndicesReversedOrThrow
import app.morphe.util.setExtensionIsPatchIncluded
import com.android.tools.smali.dexlib2.AccessFlags
import com.android.tools.smali.dexlib2.Opcode
import com.android.tools.smali.dexlib2.builder.MutableMethodImplementation
import com.android.tools.smali.dexlib2.iface.instruction.FiveRegisterInstruction
import com.android.tools.smali.dexlib2.iface.instruction.OneRegisterInstruction
import com.android.tools.smali.dexlib2.iface.instruction.ReferenceInstruction
import com.android.tools.smali.dexlib2.iface.instruction.TwoRegisterInstruction
import com.android.tools.smali.dexlib2.iface.reference.FieldReference
import com.android.tools.smali.dexlib2.iface.reference.MethodReference
import com.android.tools.smali.dexlib2.iface.reference.TypeReference
import com.android.tools.smali.dexlib2.immutable.ImmutableMethod

private const val EXTENSION_CLASS =
    "Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch;"

private const val EXTENSION_HEADER_ITEM_INTERFACE =
    $$"Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch$NavigationButtonInterface;"

@Suppress("unused")
val hideNavigationButtonsPatch = patch(
    name = "Hide navigation buttons",
    description = "Adds options to hide buttons in the navigation bar."
) {
    compatibleWith(COMPATIBILITY_REDDIT)

    dependsOn(settingsPatch, versionCheckPatch)

    execute {
        // region legacy method
        if (!is_2026_25_0_or_greater) {
            val navigationButtonInnerMethod =
                BottomNavScreenResourceBuilderLegacyFingerprint.instructionMatches[0]
                    .methodReference

            mutableClassDefBy(navigationButtonInnerMethod.definingClass).apply {
                // Add interface and helper methods to allow extension code to call obfuscated methods.
                interfaces.add(EXTENSION_HEADER_ITEM_INTERFACE)
                // Add methods to access obfuscated navigation button fields.
                methods.add(
                    ImmutableMethod(
                        type,
                        "patch_getLabel",
                        listOf(),
                        "Ljava/lang/String;",
                        AccessFlags.PUBLIC.value or AccessFlags.FINAL.value,
                        null,
                        null,
                        MutableMethodImplementation(2),
                    ).toMutable().apply {
                        val labelField = fields.single { field ->
                            field.type == "Ljava/lang/String;"
                        }

                        addInstructions(
                            0,
                            """
                                iget-object v0, p0, $labelField
                                return-object v0
                            """
                        )
                    }
                )
            }

            BottomNavScreenResourceBuilderLegacyFingerprint.method.apply {
                findInstructionIndicesReversedOrThrow(ADD_METHOD_CALL).forEach { index ->
                    val instruction = getInstruction<FiveRegisterInstruction>(index)

                    val listRegister = instruction.registerC
                    val objectRegister = instruction.registerD

                    replaceInstruction(
                        index,
                        "invoke-static { v$listRegister, v$objectRegister }, " +
                                "$EXTENSION_CLASS->hideNavigationButtonsLegacy(Ljava/util/List;Ljava/lang/Object;)V"
                    )
                }
            }
        }

        // endregion

        // region modern method

        BottomNavScreenListBuilderFingerprint.let {
            it.method.apply {
                val enumIndex = it.instructionMatches.last().index
                val enumRegister = getInstruction<TwoRegisterInstruction>(enumIndex).registerA
                val freeRegister = findFreeRegister(enumIndex, enumRegister)
                val jumpInstructionIndex = it.instructionMatches[1].index
                val jumpInstruction = getInstruction(jumpInstructionIndex)

                addInstructionsWithLabels(
                    enumIndex + 1,
                    """
                        invoke-static { v$enumRegister }, $EXTENSION_CLASS->hideNavigationTab(Ljava/lang/Enum;)Z
                        move-result v$freeRegister
                        if-nez v$freeRegister, :jump
                    """,
                    ExternalLabel("jump", jumpInstruction)
                )
            }
        }

        // endregion

        // region hooks 1-4 (the v1 mechanism) and the feed guard

        // Feed guard: every feed is a ComposeScreen, so blocking the render method covers
        // every route - drawer rows, deep links and direct pushes. A fingerprint miss must
        // fail the patch; there is deliberately no catch here.
        listOf(
            ExploreFeedScreenFingerprint,
            HomePagerScreenFingerprint,
            PopularFeedScreenFingerprint,
            LatestFeedScreenFingerprint,
            NewsFeedScreenFingerprint,
        ).forEach { fingerprint ->
            fingerprint.method.apply {
                addInstructionsWithLabels(
                    0,
                    """
                        invoke-static {}, $EXTENSION_CLASS->hideFeedScreen()Z
                        move-result v0
                        if-eqz v0, :show
                        return-void
                        :show
                        nop
                    """
                )
                verifyInjectionAt(0, EXTENSION_CLASS, "hideFeedScreen")
            }
        }

        // Hook 1: the start-tab replacement. Injected at the entry of the screen's only
        // void method taking a single tab, so every installed first screen (cold start and
        // reused-activity deep links) lands on the start tab when the feature is ON.
        // Home(false) stays as it is: the Home button is never removed from the bar.
        BottomNavScreenSelectTabFingerprint.method.apply {
            addInstructions(
                0,
                """
                    invoke-static { p1 }, $EXTENSION_CLASS->getStartTab(Ljava/lang/Enum;)Ljava/lang/Enum;
                    move-result-object p1
                    check-cast p1, Lcom/reddit/launch/bottomnav/BottomNavTab;
                """
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "getStartTab")
        }

        // Hook 2: the initial-tab default. Injected just after the `sget-object` of the
        // fallback Home, so a plain cold start highlights (and made current) the start tab.
        // The register written by the sget is reused; it needs no new register.
        BottomNavScreenInitialTabFingerprint.let {
            it.method.apply {
                val sgetIndex = it.instructionMatches[0].index
                val tabRegister = getInstruction<OneRegisterInstruction>(sgetIndex).registerA
                addInstructions(
                    sgetIndex + 1,
                    """
                        invoke-static { v$tabRegister }, $EXTENSION_CLASS->getStartTab(Ljava/lang/Enum;)Ljava/lang/Enum;
                        move-result-object v$tabRegister
                        check-cast v$tabRegister, Lcom/reddit/launch/bottomnav/BottomNavTab;
                    """
                )
                verifyInjectionAt(sgetIndex + 1, EXTENSION_CLASS, "getStartTab")
            }
        }

        // Hook 3: the selection funnel. Injected at the presenter's entry, so every
        // programmatic tab selection (bar taps, REDIRECT_TO_HOME, deep links, onboarding)
        // lands on the start tab when the feature is ON. This is also the hook that makes
        // the bar's Home tap reach the start screen.
        BottomNavTabSelectionFingerprint.method.apply {
            addInstructions(
                0,
                """
                    invoke-static { p1 }, $EXTENSION_CLASS->getStartTab(Ljava/lang/Enum;)Ljava/lang/Enum;
                    move-result-object p1
                    check-cast p1, Lcom/reddit/launch/bottomnav/BottomNavTab;
                """
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "getStartTab")
        }

        // Hook 4: the Communities tab attaching is when the search page may be opened.
        // Injected at entry, not after the proxy call: this build reuses the View parameter
        // register for the achievements proxy before that call, so `p1` there is the proxy.
        // At entry `p1` is still the attached View the extension needs for a context.
        CommunitiesTabScreenDrawerProxyFingerprint.method.apply {
            addInstructions(
                0,
                "invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V"
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "onStartTabAttached")
        }

        // Hook 5: the guarded Home screen's attach. BottomNavScreen builds that screen
        // directly in a separate method, so no tab-selection site decides the first screen
        // on cold start - the landing is caught where the guarded screen itself attaches,
        // and passes its View to the same extension method as hook 4. Matched structurally
        // against its detach twin (same signature, dismisses and launches a coroutine), and
        // the uniqueness of the pair is asserted below.
        val attach = HomePagerScreenAttachFingerprint.matchOrNull()
            ?: throw PatchException("HomePagerScreen attach method not found")
        val detach = HomePagerScreenDetachFingerprint.matchOrNull()
            ?: throw PatchException("HomePagerScreen detach method not found")
        if (attach.originalMethod.name == detach.originalMethod.name) {
            throw PatchException("HomePagerScreen attach and detach fingerprints matched the same method")
        }
        var viewParamMethods = 0
        for (method in attach.originalClassDef.methods) {
            val accessFlags = method.accessFlags
            if ((accessFlags and AccessFlags.PUBLIC.value) != 0 &&
                (accessFlags and AccessFlags.FINAL.value) != 0 &&
                method.returnType == "V" &&
                method.parameterTypes.size == 1 &&
                method.parameterTypes[0] == "Landroid/view/View;"
            ) {
                viewParamMethods++
            }
        }
        if (viewParamMethods != 2) {
            throw PatchException(
                "HomePagerScreen has $viewParamMethods View-parameter void overrides, expected exactly 2"
            )
        }
        attach.method.apply {
            addInstructions(
                0,
                "invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V"
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "onStartTabAttached")
        }

        // Hook 6: the bottom bar's tap handler. The tapped tab is rewritten (with search
        // opened for Home taps) right after the bar item is read, before any comparison, so
        // the already-selected branch can no longer skip the selection funnel and land on
        // the bare blank Home page. The handler's own flow is never short-circuited, so the
        // start tab still attaches underneath.
        BottomNavTabTapHandlerFingerprint.method.apply {
            val igetIndex = BottomNavTabTapHandlerFingerprint.instructionMatches[0].index
            val tabRegister = getInstruction<TwoRegisterInstruction>(igetIndex).registerA
            addInstructions(
                igetIndex + 1,
                """
                    invoke-static { v$tabRegister }, $EXTENSION_CLASS->onBottomTabTapped(Ljava/lang/Enum;)Ljava/lang/Enum;
                    move-result-object v$tabRegister
                    check-cast v$tabRegister, Lcom/reddit/launch/bottomnav/BottomNavTab;
                """
            )
            verifyInjectionAt(igetIndex + 1, EXTENSION_CLASS, "onBottomTabTapped")
        }

        // The search zero state's Trending removal: trending shelves are dropped from
        // the shelf list in place as it enters the repository's publisher, which runs for
        // every request. The extension filters only when the query is empty, so the
        // pre-typing page alone is affected.
        // The publisher has 28 registers, so the parameter registers exceed the 4-bit
        // register list of `invoke-static` and the call goes through `/range` instead
        // (the inline smali compiler rejects the 4-bit form with "Invalid register: v25").
        SearchZeroStateFilterFingerprint.method.apply {
            addInstructions(
                0,
                "invoke-static/range { p1 .. p2 }, $EXTENSION_CLASS->filterSearchZeroState(Ljava/util/List;Ljava/lang/CharSequence;)V"
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "filterSearchZeroState")
        }

        // Credential-request suppression + tripwire: the credential chooser sheet is raised
        // by the system credential providers answering the app's own getCredentials asks.
        // The tripwire stacks proved both launch-time asks go through the datasource's
        // R8-moved body, and a fresh install did not stop the sheet, so the wedged state is
        // Google-side and the only durable product fix is to never ask. The ask is now
        // short-circuited at the datasource's entry with the flow's OWN no-credential
        // result - the same sealed wrapper the method's NoCredentialException branch builds
        // and returns - so callers receive an outcome they already handle. The three
        // references are read off the method's own instructions at patch time; the anchor is
        // androidx's NON-obfuscated NoCredentialException type-check. No obfuscated name is
        // hard-coded, and any missing piece fails the patch.
        CredentialsDataSourceLogTripwireFingerprint.method.apply {
            addInstructions(
                0,
                "invoke-static {}, $EXTENSION_CLASS->logCredentialRequest()V"
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "logCredentialRequest")

            val instructions = requireNotNull(implementation).instructions
            val anchorIndex = instructions.indexOfFirst { instruction ->
                instruction.opcode == Opcode.INSTANCE_OF &&
                    instruction is ReferenceInstruction &&
                    (instruction.reference as TypeReference).type ==
                        "Landroidx/credentials/exceptions/NoCredentialException;"
            }
            if (anchorIndex < 0) {
                throw PatchException(
                    "NoCredentialException type-check not found in $name - " +
                        "the no-credential result cannot be located structurally"
                )
            }
            val newWrapperInstruction = instructions.getOrNull(anchorIndex + 2)
            val singletonInstruction = instructions.getOrNull(anchorIndex + 3)
            val ctorInstruction = instructions.getOrNull(anchorIndex + 4)
            if (newWrapperInstruction?.opcode != Opcode.NEW_INSTANCE ||
                singletonInstruction?.opcode != Opcode.SGET_OBJECT ||
                ctorInstruction?.opcode != Opcode.INVOKE_DIRECT
            ) {
                throw PatchException(
                    "the no-credential result construction in $name does not have the expected " +
                        "shape (NEW_INSTANCE, SGET_OBJECT, INVOKE_DIRECT after the type-check)"
                )
            }
            val wrapperType =
                (newWrapperInstruction as ReferenceInstruction).reference as TypeReference
            val singletonField =
                (singletonInstruction as ReferenceInstruction).reference as FieldReference
            val wrapperCtor =
                (ctorInstruction as ReferenceInstruction).reference as MethodReference
            if (wrapperCtor.definingClass != wrapperType.type ||
                wrapperCtor.name != "<init>" ||
                wrapperCtor.parameterTypes != listOf("Ljava/lang/Object;")
            ) {
                throw PatchException(
                    "the constructor after the NoCredentialException branch does not build the " +
                        "wrapper (${wrapperCtor.definingClass}->${wrapperCtor.name})"
                )
            }

            val wrapperRegister = findFreeRegister(0)
            val singletonRegister = findFreeRegister(0, wrapperRegister)

            addInstructions(
                1,
                """
                    invoke-static {}, $EXTENSION_CLASS->logCredentialRequestSuppressed()V
                    new-instance v$wrapperRegister, $wrapperType
                    sget-object v$singletonRegister, $singletonField
                    invoke-direct { v$wrapperRegister, v$singletonRegister }, $wrapperCtor
                    return-object v$wrapperRegister
                """
            )
            verifyInjectionAt(1, EXTENSION_CLASS, "logCredentialRequestSuppressed")

            // Read-back of the short-circuit itself: every injected instruction must sit
            // exactly where it claims to, with the very references read off the method.
            val shortCircuit = listOf(
                2 to newWrapperInstruction,
                3 to singletonInstruction,
                4 to ctorInstruction,
            )
            for ((index, expected) in shortCircuit) {
                val found = getInstruction<ReferenceInstruction>(index)
                if (found.opcode != expected.opcode ||
                    found.reference.toString() != (expected as ReferenceInstruction).reference.toString()
                ) {
                    throw PatchException(
                        "short-circuit instruction $index of $name is not the copied reference"
                    )
                }
            }
            if (getInstruction(5).opcode != Opcode.RETURN_OBJECT) {
                throw PatchException("the short-circuit return is not at instruction index 5 of $name")
            }
        }
        AutoLoginResolveCredentialsLogTripwireFingerprint.method.apply {
            addInstructions(
                0,
                "invoke-static {}, $EXTENSION_CLASS->logCredentialRequest()V"
            )
            verifyInjectionAt(0, EXTENSION_CLASS, "logCredentialRequest")
        }

        // Keep guests out of the welcome/login flow (IntroductionActivity): on a fresh
        // install with no session, Reddit's forced-login gate returns true and routes every
        // cold start into the welcome screen - on both Hide-feeds states, and before any
        // home or feed logic runs, so the fork's own hooks never get a chance. The gate's
        // callers are the launch delegate and MainActivity, so forcing the gate itself
        // false is the single choke point; guests keep the app's home, where the start-tab
        // hooks land them on search. Verified on-device: with the gate active, BACK from
        // the welcome screen exits the app, so the settings flow was unreachable at all.
        ForceLoginGateFingerprint.method.returnEarly(false)

        // endregion

        setExtensionIsPatchIncluded(EXTENSION_CLASS)
    }
}

/**
 * Every hook call must sit exactly where a missed or mis-registered filter would silently
 * corrupt the flow - the feed guards and the entry hooks at instruction index 0 ("0000"),
 * the initial-tab hook immediately after its `sget-object`. This re-reads the instruction at
 * the claimed index and fails the patch instead of trusting the injection call above.
 */
private fun MutableMethod.verifyInjectionAt(
    index: Int,
    extensionClass: String,
    injectionPoint: String
) {
    val found = getInstruction<ReferenceInstruction>(index)
    if (found.opcode != Opcode.INVOKE_STATIC &&
        found.opcode != Opcode.INVOKE_STATIC_RANGE ||
        (found.reference as MethodReference).definingClass != extensionClass ||
        (found.reference as MethodReference).name != injectionPoint
    ) {
        throw PatchException("$injectionPoint call is not at instruction index $index of $name")
    }
}
