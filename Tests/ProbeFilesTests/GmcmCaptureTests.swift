import Testing
import Foundation
@testable import StarHubTHCore

struct GmcmCaptureTests {
    private func capture() throws -> GmcmCapture {
        try #require(GmcmCapture.decode(try Fixture.data("gmcm-options.json")))
    }

    private func options(_ uid: String, _ version: String) throws -> GmcmModOptions {
        try #require(try capture().options(forMod: uid, installedVersion: version))
    }

    /// Capture d'un seul mod, `Test.Mod` 1.0.0, pour les cas que le parc ne
    /// contient pas. `options` : objets JSON au format de la sonde.
    private func synthetic(_ options: [[String: Any]], snapshot: String?,
                           version: String = "1.0.0") throws -> GmcmCapture {
        var mod: [String: Any] = ["UniqueID": "Test.Mod", "Name": "Test", "Version": version,
                                  "Options": options]
        mod["ConfigSnapshot"] = snapshot ?? NSNull()
        let json: [String: Any] = ["CapturedAt": "2026-09-27T01:34:37.0734180+02:00",
                                   "GmcmVersion": "1.16.0", "Language": "fr", "Mods": [mod]]
        return try #require(GmcmCapture.decode(try JSONSerialization.data(withJSONObject: json)))
    }

    private func option(_ kind: String = "SimpleModOption", name: String = "Label",
                        value: String?, path: [String], closure: [String] = [],
                        min: String? = nil, max: String? = nil, interval: String? = nil,
                        choices: [String]? = nil, choiceLabels: [String]? = nil) -> [String: Any] {
        ["Kind": kind, "Name": name, "Tooltip": NSNull(), "ValueType": "String",
         "Value": value ?? NSNull(), "Min": min ?? NSNull(), "Max": max ?? NSNull(),
         "Interval": interval ?? NSNull(), "Choices": choices ?? NSNull(),
         "ChoiceLabels": choiceLabels ?? NSNull(), "AccessPath": path, "ClosureStrings": closure]
    }

    @Test func decodesTheRealCapture() throws {
        let capture = try capture()
        #expect(capture.language == "fr")
        #expect(capture.capturedAt == "2026-09-27T01:34:37.0734180+02:00")
    }

    /// Clés retenues par mod, relevées sur le parc le 2026-09-27 (même règle
    /// rejouée en Python) : le rapprochement Swift doit tomber juste partout.
    @Test func entriesPerModMatchTheParc() throws {
        let expected: [(String, String, Int)] = [
            ("palmhacker13.UltraSmooth", "2.3.8", 60), ("Digus.MailServicesMod", "1.6.2", 14),
            ("Nullnnow.MS-Books", "2.0.6", 57), ("Owenynk.InteractionBubbles", "1.0.3", 18),
            ("leclair.bettercrafting", "2.18.0", 42), ("ThaleTheGreat.WalletTools", "3.3.1", 29),
            ("KCC.SnS", "2.3.10", 31), ("Pathoschild.CentralStation", "1.7.0", 2),
            ("Exonika.TheMuseumPays", "1.5.8", 1),
        ]
        for (uid, version, count) in expected {
            #expect(try options(uid, version).count == count, "\(uid)")
        }
    }

    @Test func ultraSmoothBoundsAndChoices() throws {
        let us = try options("palmhacker13.UltraSmooth", "2.3.8")
        #expect(us.entry(for: ["TimeSliceBudgetMs"])?.bounds == .init(min: 0.1, max: 5, step: 0.1))
        #expect(us.entry(for: ["TextCacheCapacity"])?.bounds == .init(min: 512, max: 16384, step: 512))
        #expect(us.entry(for: ["FpsMode"])?.choices == ["Standard", "Enhanced60", "MonitorHz", "Unlimited"])
        #expect(us.entry(for: ["FpsMode"])?.label == "Fréquence d'actualisation (Mode FPS)")
        #expect(us.entry(for: ["fpsmode"]) == us.entry(for: ["FpsMode"]))
    }

    /// « Activer » dans GMCM, `Disable…` dans le fichier : valeurs opposées,
    /// l'option est écartée — son libellé dirait le contraire de la clé.
    @Test func anInvertedOptionIsRejected() throws {
        let mail = try options("Digus.MailServicesMod", "1.6.2")
        #expect(mail.entry(for: ["DisableGiftService"]) == nil)
        #expect(mail.entry(for: ["EnableRecoveryService"])?.label == "Recovery Service")
    }

    /// 1900 dans le fichier, 36 dans GMCM (bornes 36–155) : transformée.
    @Test func aTransformedOptionIsRejected() throws {
        let books = try options("Nullnnow.MS-Books", "2.0.6")
        #expect(books.entry(for: ["IslandStartTime"]) == nil)
        #expect(books.entry(for: ["PigChance"])?.bounds == .init(min: 0, max: 1, step: 0.1))
    }

    @Test func keysFoundByPathByClosureAndNested() throws {
        #expect(try options("Pathoschild.CentralStation", "1.7.0")
                    .entry(for: ["RequirePamBus"])?.label == "Exiger le bus de Pam")
        #expect(try options("Exonika.TheMuseumPays", "1.5.8")
                    .entry(for: ["Reward Amount"])?.label == "Quantité de récompense")
        #expect(try options("leclair.bettercrafting", "2.18.0")
                    .entry(for: ["AddToBehaviors", "UseTool", "Quantity"])?.bounds == .init(min: 1, max: 999, step: nil))
    }

    /// `both` dans le fichier, `Both` dans GMCM.
    @Test func choicesMatchWithoutCase() throws {
        #expect(try options("KCC.SnS", "2.3.10").entry(for: ["ShieldThrowMethod"])?.choices
                == ["Weapon Special", "Both", "Keybind"])
    }

    /// Deux libellés pour une clé : celui de la première option.
    @Test func collisionsKeepTheFirstLabel() throws {
        #expect(try options("ThaleTheGreat.WalletTools", "3.3.1")
                    .entry(for: ["PlayToolSwapSound"])?.label == "Son de Changement d'Outillage")
    }

    @Test func collisionsDropDisagreeingBounds() throws {
        let same = try synthetic([
            option("NumericModOption", name: "A", value: "5", path: ["Volume"], min: "0", max: "10"),
            option("NumericModOption", name: "B", value: "5", path: ["Volume"], min: "0", max: "10"),
        ], snapshot: #"{"Volume": 5}"#)
        #expect(try #require(same.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
                    .entry(for: ["Volume"])?.bounds == .init(min: 0, max: 10, step: nil))
        let differ = try synthetic([
            option("NumericModOption", name: "A", value: "5", path: ["Volume"], min: "0", max: "10"),
            option("NumericModOption", name: "B", value: "5", path: ["Volume"], min: "0", max: "20"),
        ], snapshot: #"{"Volume": 5}"#)
        let differing = try #require(differ.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        let entry = try #require(differing.entry(for: ["Volume"]))
        #expect(entry.bounds == nil)
        #expect(entry.label == "A")
    }

    /// « How chatty is the valley » : un curseur qui pilote 6 clés.
    @Test func anAmbiguousOptionIsRejected() throws {
        let capture = try synthetic([
            option(value: "true", path: ["Section", "Enabled", "Other", "Enabled"]),
        ], snapshot: #"{"Enabled": true, "Other": {"Enabled": true}}"#)
        #expect(try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0")).count == 0)
    }

    @Test func invalidBoundsGiveNoSlider() throws {
        let capture = try synthetic([
            option("NumericModOption", name: "Inverted", value: "5", path: ["A"], min: "10", max: "0"),
            option("NumericModOption", name: "ZeroStep", value: "5", path: ["B"], min: "0", max: "10", interval: "0"),
            option("NumericModOption", name: "HugeStep", value: "5", path: ["C"], min: "0", max: "10", interval: "20"),
            option("NumericModOption", name: "Outside", value: "50", path: ["D"], min: "0", max: "10"),
            option("NumericModOption", name: "Text", value: "5", path: ["E"], min: "0", max: "10"),
        ], snapshot: #"{"A": 5, "B": 5, "C": 5, "D": 50, "E": "5"}"#)
        let options = try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        #expect(options.entry(for: ["A"])?.bounds == nil)
        #expect(options.entry(for: ["A"])?.label == "Inverted")
        #expect(options.entry(for: ["B"])?.bounds == .init(min: 0, max: 10, step: nil))
        #expect(options.entry(for: ["C"])?.bounds == .init(min: 0, max: 10, step: nil))
        #expect(options.entry(for: ["D"])?.bounds == nil)
        #expect(options.entry(for: ["E"])?.bounds == nil)
    }

    @Test func choiceLabelsFollowTheirValues() throws {
        let capture = try synthetic([
            option("ChoiceModOption", value: "both", path: ["Mode"],
                   choices: ["both", "keybind"], choiceLabels: ["Both", "keybind"]),
            option("ChoiceModOption", value: "x", path: ["Short"],
                   choices: ["x", "y"], choiceLabels: ["X"]),
            option("ChoiceModOption", value: "z", path: ["Outside"], choices: ["x", "y"]),
        ], snapshot: #"{"Mode": "both", "Short": "x", "Outside": "z"}"#)
        let options = try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        // Un libellé identique à la valeur n'apporte rien.
        #expect(options.entry(for: ["Mode"])?.choiceLabels == ["both": "Both"])
        // Longueurs différentes : libellés ignorés, choix gardés.
        #expect(options.entry(for: ["Short"])?.choiceLabels == [:])
        #expect(options.entry(for: ["Short"])?.choices == ["x", "y"])
        // Valeur hors liste : pas de choix.
        #expect(options.entry(for: ["Outside"])?.choices == nil)
    }

    /// Le fichier actuel du parc (sonde ≤ 0.4.10) : ni copie ni version.
    @Test func anOldCaptureGivesNothing() throws {
        let json = #"{"CapturedAt": "2026-09-26T20:34:25.7329420+02:00", "GmcmVersion": "1.16.0", "Mods": [{"UniqueID": "Test.Mod", "Name": "Test", "Options": []}]}"#
        let capture = try #require(GmcmCapture.decode(Data(json.utf8)))
        #expect(capture.language == nil)
        #expect(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0") == nil)
        let noSnapshot = try synthetic([], snapshot: nil)
        #expect(noSnapshot.options(forMod: "Test.Mod", installedVersion: "1.0.0") == nil)
    }

    /// Mise à jour depuis la capture : le mod entier est ignoré. `1.0` et
    /// `1.0.0` sont la même version.
    @Test func anotherInstalledVersionGivesNothing() throws {
        let capture = try synthetic([option(value: "true", path: ["A"])], snapshot: #"{"A": true}"#)
        #expect(capture.options(forMod: "Test.Mod", installedVersion: "1.1.0") == nil)
        #expect(capture.options(forMod: "test.mod", installedVersion: "1.0") != nil)
        #expect(capture.options(forMod: "Other.Mod", installedVersion: "1.0.0") == nil)
    }

    @Test func anUnreadableCaptureIsNil() {
        #expect(GmcmCapture.decode(Data("{".utf8)) == nil)
        #expect(GmcmCapture.decode(Data()) == nil)
    }
}
