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
import com.android.tools.smali.dexlib2.iface.instruction.ReferenceInstruction
import com.android.tools.smali.dexlib2.iface.instruction.TwoRegisterInstruction
import com.android.tools.smali.dexlib2.iface.reference.MethodReference
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
                verifyInjectionAtEntry(EXTENSION_CLASS, "hideFeedScreen")
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
            verifyInjectionAtEntry(EXTENSION_CLASS, "getStartTab")
        }

        // Hook 4: the Communities tab attaching is when the search page may be opened.
        // Injected at entry, not after the proxy call: this build reuses the View parameter
        // register for the achievements proxy before that call, so `p1` there is the proxy.
        // At entry `p1` is still the attached View the extension needs for a context.
        CommunitiesTabScreenDrawerProxyFingerprint.method.addInstructions(
            0,
            "invoke-static { p1 }, $EXTENSION_CLASS->onStartTabAttached(Landroid/view/View;)V"
        )

        // endregion

        setExtensionIsPatchIncluded(EXTENSION_CLASS)
    }
}

/**
 * The design (and the S01 evidence trail) insists the hook call is at instruction index 0,
 * ahead of everything the method originally ran - "at instruction 0000". A misplaced hook
 * is not an acceptable state to ship, so this fails the patch instead of trusting the
 * injection call above.
 */
private fun MutableMethod.verifyInjectionAtEntry(extensionClass: String, injectionPoint: String) {
    val first = getInstruction<ReferenceInstruction>(0)
    if (first.opcode != Opcode.INVOKE_STATIC ||
        (first.reference as MethodReference).definingClass != extensionClass ||
        (first.reference as MethodReference).name != injectionPoint
    ) {
        throw PatchException("$injectionPoint call is not at instruction index 0 of $name")
    }
}
