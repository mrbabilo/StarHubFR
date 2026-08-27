import Foundation
import Testing
@testable import StarHubTHCore

/// B3-T6 — notes libres par mod, persistées au profil. La note suit
/// l'**identité** du mod (`UniqueID`), pas son dossier : elle doit survivre à
/// une mise en pause et suivre le mod dans le profil. Une note vidée est
/// retirée plutôt que rangée vide — sinon chaque mod jamais noté laisse une
/// clé morte dans le JSON du profil, pour toujours.
@Suite struct ProfileNotesTests {

    @Test("Une note s'écrit, se relit, et survit à un aller-retour JSON")
    func writeReadRoundTrip() throws {
        var profile = ModProfile(name: "Multi", enabledModIds: [])
        profile.setNote("désactivé en multi car désync", forModId: "Pathoschild.SVE")

        #expect(profile.note(forModId: "Pathoschild.SVE") == "désactivé en multi car désync")
        #expect(profile.note(forModId: "autre.mod") == nil)

        let decoded = try JSONDecoder().decode(
            [ModProfile].self,
            from: JSONEncoder().encode([profile]))
        #expect(decoded.first?.note(forModId: "Pathoschild.SVE")
                == "désactivé en multi car désync")
    }

    @Test("Une note vidée disparaît du profil, clé comprise")
    func emptiedNoteIsRemoved() {
        var profile = ModProfile(name: "Solo", enabledModIds: [])
        profile.setNote("à mettre à jour", forModId: "SomeMod")

        profile.setNote("", forModId: "SomeMod")
        #expect(profile.note(forModId: "SomeMod") == nil)
        #expect(profile.modNotes["SomeMod"] == nil)

        profile.setNote("retirée à la main", forModId: "SomeMod")
        profile.setNote(nil, forModId: "SomeMod")
        #expect(profile.modNotes["SomeMod"] == nil)
    }

    @Test("Un identifiant vide ne note rien — les packs n'ont pas d'identité")
    func emptyIdWritesNothing() {
        var profile = ModProfile(name: "Solo", enabledModIds: [])
        profile.setNote("note d'un pack ?", forModId: "")
        #expect(profile.modNotes.isEmpty)
        #expect(profile.note(forModId: "") == nil)
    }

    @Test("Un profil enregistré avant les notes se décode sans en perdre une")
    func decodesLegacyProfileWithoutField() throws {
        // Le format d'avant B3-T6 : pas de `modNotes`. Un décodage strict
        // ferait disparaître le profil entier au premier lancement — le
        // patron que `modMetadata` a déjà dû suivre (cf. ModProfile.swift).
        let legacy = """
        [{
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "Ancien",
          "enabledModIds": ["SomeMod"]
        }]
        """
        let decoded = try JSONDecoder().decode([ModProfile].self,
                                               from: Data(legacy.utf8))
        #expect(decoded.count == 1)
        #expect(decoded.first?.modNotes.isEmpty == true)
    }
}
