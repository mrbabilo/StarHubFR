import Testing
@testable import StarHubTHCore

struct KeybindFamilyGuessTests {
    @Test func ownModeContextForcesRare() {
        #expect(KeybindFamilyGuess.guess(modName: "Stillbloom", settingNames: ["GrabKey"],
                                         nexusCategory: nil, hasOwnModeContext: true) == .rare)
    }
    @Test func infoKeywordsWin() {
        #expect(KeybindFamilyGuess.guess(modName: "UIInfoSuite2Alt",
                                         settingNames: ["OpenCalendarKeybind", "OpenQiSpecialOrdersBoardKeybind"],
                                         nexusCategory: nil, hasOwnModeContext: false) == .info)
    }
    @Test func actionKeywordsWin() {
        #expect(KeybindFamilyGuess.guess(modName: "Swim", settingNames: ["DiveKey"],
                                         nexusCategory: nil, hasOwnModeContext: false) == .action)
    }
    @Test func rareKeywordsWin() {
        #expect(KeybindFamilyGuess.guess(modName: "PerformanceHud", settingNames: ["ToggleOverlayKey"],
                                         nexusCategory: nil, hasOwnModeContext: false) == .rare)
    }
    @Test func unknownStaysNil() {
        #expect(KeybindFamilyGuess.guess(modName: "BetterItemStacks", settingNames: ["SplitModifier"],
                                         nexusCategory: nil, hasOwnModeContext: false) == nil)
    }
    @Test func nexusCategoryBreaksSilence() {
        #expect(KeybindFamilyGuess.guess(modName: "SomethingNeutral", settingNames: ["MainKey"],
                                         nexusCategory: "User Interface", hasOwnModeContext: false) == .info)
    }

    @Test func substringInsideWordDoesNotMatchRoll() {
        #expect(KeybindFamilyGuess.guess(modName: "OrbToggleController", settingNames: ["OrbToggleKey", "OrbToggleController"],
                                         nexusCategory: nil, hasOwnModeContext: false) == nil)
    }
    @Test func substringInsideWordDoesNotMatchEatNorUse() {
        #expect(KeybindFamilyGuess.guess(modName: "WeatherMouseTweaks", settingNames: ["CreateKey"],
                                         nexusCategory: nil, hasOwnModeContext: false) == nil)
    }
    @Test func substringInsideWordDoesNotMatchDashStorePlace() {
        #expect(KeybindFamilyGuess.guess(modName: "DashboardRestore", settingNames: ["ReplaceKey"],
                                         nexusCategory: nil, hasOwnModeContext: false) == nil)
    }
    @Test func tieBreakPrefersRare() {
        #expect(KeybindFamilyGuess.guess(modName: "DebugMenu", settingNames: [],
                                         nexusCategory: nil, hasOwnModeContext: false) == .rare)
    }
    @Test func matchingIsCaseInsensitive() {
        #expect(KeybindFamilyGuess.guess(modName: "SWIM", settingNames: ["Dive_Key"],
                                         nexusCategory: nil, hasOwnModeContext: false) == .action)
    }
    @Test func nexusGameplayMechanicsGivesAction() {
        #expect(KeybindFamilyGuess.guess(modName: "SomethingNeutral", settingNames: ["MainKey"],
                                         nexusCategory: "Gameplay Mechanics", hasOwnModeContext: false) == .action)
    }
    @Test func keywordsBeatNexusCategory() {
        #expect(KeybindFamilyGuess.guess(modName: "Swim", settingNames: ["DiveKey"],
                                         nexusCategory: "User Interface", hasOwnModeContext: false) == .action)
    }
    @Test func shortKeywordAcceptsTrailingS() {
        #expect(KeybindFamilyGuess.guess(modName: "FarmMaps", settingNames: [],
                                         nexusCategory: nil, hasOwnModeContext: false) == .info)
    }
    @Test func longKeywordMatchesAsPrefix() {
        #expect(KeybindFamilyGuess.guess(modName: "CropEncyclopedia", settingNames: [],
                                         nexusCategory: nil, hasOwnModeContext: false) == .info)
    }
}
