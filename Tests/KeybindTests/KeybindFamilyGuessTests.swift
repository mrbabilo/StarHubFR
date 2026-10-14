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
}
