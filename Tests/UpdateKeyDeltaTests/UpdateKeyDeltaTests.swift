import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct UpdateKeyDeltaTests {

    private func snapshot(config: String? = nil,
                          english: [String: [String: String]] = [:],
                          french: [String: [String: String]] = [:]) -> UpdateKeySnapshot {
        let configValues = config?.split(separator: ",").reduce(into: [String: String]()) {
            let parts = $1.split(separator: "=", maxSplits: 1)
            $0[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
        }
        return UpdateKeySnapshot(config: configValues, english: english, french: french)
    }

    @Test func configAddedAndRemoved() throws {
        let old = snapshot(config: "Keep,Removed", english: [:])
        let new = snapshot(config: "Keep,Added", english: [:])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Mod")
        #expect(Set((delta?.config?.added ?? [:]).keys) == ["Added"])
        #expect(Set((delta?.config?.removed ?? [:]).keys) == ["Removed"])
    }

    @Test func configNilWhenArchiveShipsNone() throws {
        let old = snapshot(config: "Keep", english: [:])
        let new = snapshot(config: nil, english: [:])   // archive sans config.json
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Mod")
        #expect(delta?.config == nil, "le versant config se tait, il ne dit pas « 0 »")
    }

    @Test func translationVentilatesAuthorTranslated() throws {
        // Le neuf ajoute deux clés : l'une traduite par l'auteur (fr.json neuf),
        // l'autre non. L'utilisateur ne traduit aucune des deux.
        let old = snapshot(english: ["": ["gone": "Old"]], french: ["": ["gone": "Parti"]])
        let new = snapshot(english: ["": ["gone": "Old", "byAuthor": "Text", "toDo": "Todo"]],
                           french: ["": ["byAuthor": "Traduit par l'auteur"]])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Mod")
        #expect(Set((delta?.translation.addedAuthorTranslated ?? [:]).keys) == ["byAuthor"])
        #expect(Set((delta?.translation.addedUntranslated ?? [:]).keys) == ["toDo"])
        #expect(delta?.translation.removedKeys.isEmpty == true, "gone n'a pas disparu")
    }

    @Test func nestedComponentKeysAreQualifiedByPath() throws {
        // Composant imbriqué : la qualification porte le chemin relatif
        // entier — « Kid/GrandKid/clé », pas seulement le dernier segment.
        let old = snapshot(english: [:], french: [:])
        let new = snapshot(english: ["Kid/GrandKid": ["fresh": "Text"]], french: [:])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Mod")
        #expect(delta?.translation.addedUntranslated["Kid/GrandKid/fresh"] == "Text")
    }

    @Test func removedEnglishKeepsOldValue() throws {
        let old = snapshot(english: ["": ["gone": "Le vieux texte"]], french: [:])
        let new = snapshot(english: ["": [:]], french: [:])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Mod")
        #expect(delta?.translation.removedKeys["gone"] == "Le vieux texte")
    }

    @Test func sameKeyInTwoComponentsStaysDistinct() throws {
        let old = snapshot(english: ["": ["k": "A"], "Kid": ["k": "B"]], french: [:])
        let new = snapshot(english: ["": ["k": "A", "k2": "C"], "Kid": ["k": "B"]], french: [:])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Pack")
        // La clé qualifiée porte le composant : "k2" nu, mais jamais fusionné
        // avec un "Kid/k".
        #expect(Set((delta?.translation.addedUntranslated ?? [:]).keys) == ["k2"])
    }

    @Test func emptyDeltaReturnsNil() throws {
        let old = snapshot(config: "A", english: ["": ["k": "v"]], french: ["": ["k": "fr"]])
        let new = snapshot(config: "A", english: ["": ["k": "v"]], french: ["": ["k": "fr"]])
        #expect(ModUpdateKeyDelta.compare(old: old, new: new,
                                          uniqueId: "a.b", folderName: "Mod") == nil)
    }

    @Test func packKeysAreQualified() throws {
        let old = snapshot(english: [:], french: [:])
        let new = snapshot(english: ["Kid": ["k": "v"]], french: [:])
        let delta = ModUpdateKeyDelta.compare(old: old, new: new,
                                              uniqueId: "a.b", folderName: "Pack")
        #expect(Set((delta?.translation.addedUntranslated ?? [:]).keys) == ["Kid/k"])
    }
}
