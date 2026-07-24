import Testing
@testable import StarHubTHCore

struct ModTagTests {
    // Ported from upstream ModTagInferenceTests + additions.
    @Test func infersUITag() {
        #expect(ModItem.inferTag(name: "UI Info Suite", uniqueId: "cd.uiinfosuite", description: "Adds UI elements") == "UI")
    }
    @Test func infersFrameworkTag() {
        #expect(ModItem.inferTag(name: "Content Patcher", uniqueId: "Pathoschild.ContentPatcher", description: "Core framework") == "Framework")
    }
    @Test func infersFrameworkFromApiKeyword() {
        #expect(ModItem.inferTag(name: "Farm Type Manager", uniqueId: "esc.ftm", description: "API and framework for spawns") == "Framework")
    }
    @Test func infersTranslationTag() {
        #expect(ModItem.inferTag(name: "Thai Translation", uniqueId: "some.thai", description: "Language pack") == "Translation")
    }
    @Test func infersCosmeticTag() {
        #expect(ModItem.inferTag(name: "Cute Animals", uniqueId: "cute.animals", description: "Texture replacement") == "Cosmetic")
    }
    @Test func wholeWordMatchAvoidsFalsePositive() {
        // "fruit" contains "ui" but must NOT match the UI tag as a substring.
        #expect(ModItem.inferTag(name: "Fruit Trees", uniqueId: "a.fruit", description: "More crops to harvest") == "Gameplay")
    }
    @Test func fallsBackToOther() {
        #expect(ModItem.inferTag(name: "Zzz", uniqueId: "a.b", description: "qwerty") == "Other")
    }
    @Test func contentPatcherByUniqueIdPrefix() {
        #expect(ModItem.inferTag(name: "Some CP Pack", uniqueId: "Pathoschild.ContentPatcher.SomePack", description: "content patcher pack") == "Content Patcher")
    }

    // L10n mapping
    @Test func l10nKeyMapping() {
        #expect(L10n.ModTag.key(for: "Framework") == "mod_tag_framework")
        #expect(L10n.ModTag.key(for: "Content Patcher") == "mod_tag_content_patcher")
        #expect(L10n.ModTag.key(for: "UI") == "mod_tag_ui")
        #expect(L10n.ModTag.key(for: "anything else") == "mod_tag_other")
    }
}
