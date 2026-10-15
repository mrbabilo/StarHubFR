import Testing
@testable import StarHubTHCore

struct KeybindPlanWriterTests {
    private func combo(_ buttons: String...) -> KeybindCombo { KeybindCombo(buttons: buttons)! }

    @Test func replacesOnlyTheKeyboardAlternative() throws {
        let original = "{\n  \"NextCategory\": \"Down, RightTrigger\",\n  \"Other\": 1\n}"
        let text = try KeybindPlanWriter.rewrittenText(original: original, keyPath: ["NextCategory"],
                                                       from: combo("Down"), to: combo("D3")).get()
        #expect(text.contains("\"D3, RightTrigger\""))
        #expect(text.contains("\"Other\": 1"))
    }
    @Test func replacesAChordAlternativeWhateverItsSpacing() throws {
        let original = "{ \"Open\": \"LeftControl +Q, RightTrigger\" }"
        let text = try KeybindPlanWriter.rewrittenText(original: original, keyPath: ["Open"],
                                                       from: combo("LeftControl", "Q"), to: combo("O")).get()
        #expect(text.contains("\"O, RightTrigger\""))
    }
    @Test func crlfFileSurvives() throws {
        let original = "{\r\n  \"Key\": \"H\",\r\n  \"Volume\": 50\r\n}"
        let text = try KeybindPlanWriter.rewrittenText(original: original, keyPath: ["Key"],
                                                       from: combo("H"), to: combo("K")).get()
        #expect(ConfigJSONTree.parse(text) != nil)
        #expect(text.contains("\"K\""))
        #expect(text.contains("50"))
    }
    @Test func missingAlternativeFailsLoudly() {
        let original = "{ \"Key\": \"J\" }"
        let result = KeybindPlanWriter.rewrittenText(original: original, keyPath: ["Key"],
                                                     from: combo("H"), to: combo("K"))
        #expect(result == .failure(.alternativeMissing))
    }
    @Test func deeperPathWorks() throws {
        let original = "{ \"Controls\": { \"ToggleLookup\": \"F1\" } }"
        let text = try KeybindPlanWriter.rewrittenText(original: original,
                                                       keyPath: ["Controls", "ToggleLookup"],
                                                       from: combo("F1"), to: combo("L")).get()
        #expect(text.contains("\"L\""))
    }
    @Test func unparsableFileFails() {
        #expect(KeybindPlanWriter.rewrittenText(original: "pas du json", keyPath: ["K"],
                                                from: combo("H"), to: combo("K")) == .failure(.unreadable))
    }
    @Test func nonStringValueIsUnsupported() {
        let result = KeybindPlanWriter.rewrittenText(original: "{ \"Key\": 112 }", keyPath: ["Key"],
                                                     from: combo("F1"), to: combo("K"))
        #expect(result == .failure(.unsupportedValue))
    }
    @Test func missingPathFails() {
        let result = KeybindPlanWriter.rewrittenText(original: "{ \"A\": \"H\" }", keyPath: ["B"],
                                                     from: combo("H"), to: combo("K"))
        #expect(result == .failure(.pathMissing))
    }
    @Test func matchingGoesThroughTheScannerGrammar() throws {
        let original = "{ \"Open\": \"leftcontrol+q, RightTrigger\" }"
        let text = try KeybindPlanWriter.rewrittenText(original: original, keyPath: ["Open"],
                                                       from: combo("LeftControl", "Q"), to: combo("O")).get()
        #expect(text.contains("\"O, RightTrigger\""))
    }
    @Test func arraySegmentWorks() throws {
        let original = "{ \"Keys\": [\"H\", \"J\"] }"
        let text = try KeybindPlanWriter.rewrittenText(original: original, keyPath: ["Keys", "[1]"],
                                                       from: combo("J"), to: combo("K")).get()
        #expect(text.contains("\"K\""))
        #expect(text.contains("\"H\""))
    }
}
