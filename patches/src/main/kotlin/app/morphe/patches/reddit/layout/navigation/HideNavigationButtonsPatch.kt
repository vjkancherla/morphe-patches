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
import app.morphe.patcher.patch.mutableClassDefBy
import app.morphe.patcher.patch.patch
import app.morphe.patcher.util.findFreeRegister
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
import com.android.tools.smali.dexlib2.iface.reference.FieldReference
import com.android.tools.smali.dexlib2.iface.reference.MethodReference
import com.android.tools.smali.dexlib2.iface.reference.StringReference
import com.android.tools.smali.dexlib2.iface.reference.TypeReference
import com.android.tools.smali.dexlib2.immutable.ImmutableMethod

private const val EXTENSION_CLASS =
    "Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch;"

private const val EXTENSION_HEADER_ITEM_INTERFACE =
    $$"Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch$NavigationButtonInterface;"

private const val EXTENSION_START_TAB_SCREEN_INTERFACE =
    $$"Lapp/morphe/extension/reddit/patches/HideNavigationButtonsPatch$StartTabScreenInterface;"

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

        // Hook 4: the Communities tab attaching is when the drawer request may be raised.
        CommunitiesTabScreenDrawerProxyFingerprint.let {
            it.method.apply {
                addInstructions(
                    it.instructionMatches.last().index + 1,
                    "invoke-static { p0 }, $EXTENSION_CLASS->onStartTabAttached(Ljava/lang/Object;)V"
                )
            }
        }

        // Added method: the tab screen learns to open its own subreddit drawer, through
        // the same provider its menu button uses. All obfuscated members are resolved
        // from matched instructions - nothing obfuscated is hard-coded.
        mutableClassDefBy("Lcom/reddit/communitiestab/compose/CommunitiesTabScreen;").apply {
            interfaces.add(EXTENSION_START_TAB_SCREEN_INTERFACE)

            val wireMethod = TabScreenClickHandlerProviderFingerprint.method
            val wireInstructions = wireMethod.implementation!!.instructions.toList()
            val constIndex = wireInstructions.indexOfFirst { instruction ->
                instruction.opcode == Opcode.CONST_STRING &&
                    ((instruction as ReferenceInstruction).reference as StringReference).string == "communityNavIconClickHandler"
            }
            if (constIndex < 0) {
                throw IllegalArgumentException("communityNavIconClickHandler not found")
            }
            val fieldAccessorIndices = TabScreenClickHandlerProviderFingerprint
                .instructionMatches.map { it.index }
            val igetIndex = fieldAccessorIndices.minBy { index ->
                kotlin.math.abs(index - constIndex)
            }
            val providerField = (wireInstructions[igetIndex] as ReferenceInstruction)
                .reference as FieldReference

            if (providerField.definingClass != "Lcom/reddit/communitiestab/compose/CommunitiesTabScreen;") {
                throw IllegalArgumentException(
                    "Nearest field not on the Communities tab screen: $providerField"
                )
            }

            var providerType: String? = null
            var invokeKind: String? = null
            var getReference: MethodReference? = null
            for (instruction in wireInstructions.subList(igetIndex + 1, wireInstructions.size)) {
                when (instruction.opcode) {
                    Opcode.CHECK_CAST ->
                        providerType = ((instruction as ReferenceInstruction).reference as TypeReference).type
                    Opcode.INVOKE_INTERFACE, Opcode.INVOKE_VIRTUAL ->
                        if (getReference == null) {
                            val reference = (instruction as ReferenceInstruction).reference as MethodReference
                            if (reference.definingClass != "Lkotlin/jvm/internal/Intrinsics;" &&
                                reference.returnType == "Ljava/lang/Object;"
                            ) {
                                getReference = reference
                                invokeKind = when (instruction.opcode) {
                                    Opcode.INVOKE_INTERFACE -> "interface"
                                    else -> "virtual"
                                }
                            }
                        }
                    else -> Unit
                }
                if (providerType != null && getReference != null) break
            }
            if (providerType == null || invokeKind == null || getReference == null) {
                throw IllegalArgumentException(
                    "The provider's get() call and its type cast were not found after the field access"
                )
            }

            methods.add(
                ImmutableMethod(
                    type,
                    "patch_openCommunityDrawer",
                    listOf(),
                    "V",
                    AccessFlags.PUBLIC.value or AccessFlags.FINAL.value,
                    null,
                    null,
                    MutableMethodImplementation(2),
                ).toMutable().apply {
                    addInstructions(
                        0,
                        """
                            iget-object v0, p0, ${providerField.definingClass}->${providerField.name}:${providerField.type}
                            invoke-$invokeKind { v0 }, ${getReference.definingClass}->${getReference.name}()Ljava/lang/Object;
                            move-result-object v0
                            check-cast v0, $providerType
                            invoke-virtual { v0 }, $providerType->a()V
                            return-void
                        """
                    )
                }
            )
        }

        // endregion

        setExtensionIsPatchIncluded(EXTENSION_CLASS)
    }
}
