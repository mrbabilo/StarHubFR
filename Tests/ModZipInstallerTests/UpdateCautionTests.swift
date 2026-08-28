import Foundation
import Testing
@testable import StarHubTHCore

/// B2-T7 : `UpdateCautionMessage` est une extension **Stardrop** du manifest
/// (ignorée par SMAPI, aucun mod du parc de référence ne l'expose aujourd'hui).
/// L'auteur l'écrit dans le manifest de la version **qu'il publie** : elle ne
/// concerne que la mise à jour d'un mod **déjà installé**, et doit s'afficher
/// avant que la nouvelle version n'écrase l'ancienne. Sémantique vérifiée dans
/// les sources Stardrop (`Floogen/Stardrop`, `MainWindow.axaml.cs` : les
/// manifests de l'archive, filtrés sur `HasModInstalled(UniqueID)`).
@Suite struct UpdateCautionTests {

    // MARK: - Lecture du champ (ModManifest)

    private func manifest(dict extra: [String: Any]) -> ModManifest? {
        var dict: [String: Any] = ["Name": "Test Mod", "UniqueID": "test.mod"]
        for (key, value) in extra { dict[key] = value }
        return ModManifest(dict: dict)
    }

    @Test("Le champ UpdateCautionMessage est lu tel quel")
    func readsTheCautionMessage() {
        let m = manifest(dict: ["UpdateCautionMessage": "This update breaks saves!"])
        #expect(m?.updateCautionMessage == "This update breaks saves!")
    }

    /// Newtonsoft, chez Stardrop, fait correspondre les propriétés sans tenir
    /// compte de la casse : un manifest en minuscules doit marcher pareil.
    @Test("Le champ est lu sans tenir compte de sa casse")
    func readsTheFieldCaseInsensitively() {
        let m = manifest(dict: ["updatecautionmessage": "Casse différente"])
        #expect(m?.updateCautionMessage == "Casse différente")
    }

    @Test("Un manifest sans le champ n'alerte pas")
    func absentFieldIsNil() {
        #expect(manifest(dict: [:])?.updateCautionMessage == nil)
    }

    @Test("Un message vide ou d'espaces n'alerte pas")
    func blankMessageIsNil() {
        #expect(manifest(dict: ["UpdateCautionMessage": ""])?.updateCautionMessage == nil)
        #expect(manifest(dict: ["UpdateCautionMessage": "   "])?.updateCautionMessage == nil)
    }

    // MARK: - Filtrage sur les mods installés (UpdateCaution.warnings)

    private func detectedMod(uniqueId: String, name: String,
                             caution: String?) -> DetectedMod {
        var dict: [String: Any] = ["Name": name, "UniqueID": uniqueId]
        if let caution { dict["UpdateCautionMessage"] = caution }
        let m = ModManifest(dict: dict)!
        return DetectedMod(folderName: name, relativePath: name, manifest: m,
                           hasConfigFiles: false, dependencies: [],
                           dependencyDetails: [], existingVersion: nil)
    }

    @Test("Un mod installé dont l'archive porte un message alerte, avec son nom")
    func installedModWithCautionWarns() {
        let warnings = UpdateCaution.warnings(
            in: [detectedMod(uniqueId: "test.mod", name: "Test Mod",
                             caution: "Backup your saves first")],
            installedUniqueIds: ["test.mod"])
        #expect(warnings == [.init(modName: "Test Mod", message: "Backup your saves first")])
    }

    /// Stardrop compare les `UniqueID` en `OrdinalIgnoreCase` : un auteur peut
    /// changer la casse entre deux versions.
    @Test("L'identité du mod se compare sans casse")
    func identityIsCaseInsensitive() {
        let warnings = UpdateCaution.warnings(
            in: [detectedMod(uniqueId: "Test.Mod", name: "Test Mod", caution: "Attention")],
            installedUniqueIds: ["test.mod"])
        #expect(warnings.count == 1)
    }

    @Test("Un mod nouveau, jamais installé, n'alerte pas")
    func freshInstallNeverWarns() {
        let warnings = UpdateCaution.warnings(
            in: [detectedMod(uniqueId: "brand.new", name: "Brand New", caution: "Attention")],
            installedUniqueIds: ["test.mod"])
        #expect(warnings.isEmpty)
    }

    @Test("Un mod installé sans message dans l'archive n'alerte pas")
    func installedModWithoutCautionStaysSilent() {
        let warnings = UpdateCaution.warnings(
            in: [detectedMod(uniqueId: "test.mod", name: "Test Mod", caution: nil)],
            installedUniqueIds: ["test.mod"])
        #expect(warnings.isEmpty)
    }

    @Test("Un pack alerte pour chacun de ses mods concernés, dans l'ordre de l'archive")
    func aPackWarnsForEachConcernedModInOrder() {
        let warnings = UpdateCaution.warnings(
            in: [
                detectedMod(uniqueId: "first.mod", name: "First", caution: "Un"),
                detectedMod(uniqueId: "other.mod", name: "Other", caution: nil),
                detectedMod(uniqueId: "second.mod", name: "Second", caution: "Deux"),
            ],
            installedUniqueIds: ["second.mod", "first.mod", "unrelated"])
        #expect(warnings.map(\.modName) == ["First", "Second"])
        #expect(warnings.map(\.message) == ["Un", "Deux"])
    }
}
