import Foundation
import Testing
@testable import StarHubTHCore

/// Le nom **logique** de dossier d'un mod à installer est déjà pris par un mod
/// d'**autre** UniqueID — le cas réel qui a déclenché le chantier : deux
/// `[CP] Sounds of the Valley`, l'auteur ayant changé l'identifiant entre
/// versions (`Juanpa98ar.SotV` en 3.1.0 active, `Juanpa98ar.Source.SotV` en
/// 4.0.0 en pause). L'installateur ne voyait que l'identifiant : le nouveau
/// partait en pause en silence et — `ModItem.id` étant le nom logique — les
/// deux mods partageaient l'identité `Identifiable`, un seul rendu à l'écran.
///
/// Décision de l'auteur (2026-09-13) : **signal + choix dans l'aperçu**,
/// jamais d'écrasement automatique d'un mod d'uniqueId différent.
///
/// Les deux types de conflit ne fusionnent jamais : identifiant identique →
/// `.folderExists` seul (l'occupant du nom EST l'existant) ; le nom ne
/// redétecte jamais ce cas.
///
/// La détection est appelée par la fonction **pure** extraite
/// (`ModZipInstaller.detectConflicts`) : aucun fichier, aucun zip — la pureté
/// est le but, le harnais tmp UUID des suites voisines ne sert qu'aux tests
/// qui touchent le disque.
@Suite struct LogicalFolderNameCollisionTests {

    private func modItem(folderName: String, uniqueId: String,
                         version: String = "1.0.0",
                         isEnabled: Bool = false) -> ModItem {
        ModItem(uniqueId: uniqueId, name: folderName,
                folderName: folderName, version: version,
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: isEnabled, dependencies: [], children: nil, isGroup: false)
    }

    // MARK: - Le finder logique (`Array<ModItem>.mod(withLogicalFolderName:)`)

    /// Test 1 — le point de pause est décapité des deux côtés.
    @Test func logicalNameStripsThePauseDot() {
        let sounds = modItem(folderName: "[CP] Sounds of the Valley",
                             uniqueId: "Juanpa98ar.SotV", version: "3.1.0",
                             isEnabled: false)
        #expect(sounds.physicalFolderName == ".[CP] Sounds of the Valley")
        let mods = [sounds]

        // Le mod en pause vit à `.[CP] Sounds of the Valley` sur le disque ;
        // son nom **logique** reste le sien.
        #expect(mods.mod(withLogicalFolderName: "[CP] Sounds of the Valley")?.id
                == "[CP] Sounds of the Valley")

        // Une entrée portant le point de tête (construction directe, comme le
        // nom brut d'une archive) est trouvée par son nom logique.
        let dotted = [modItem(folderName: ".[CP] X", uniqueId: "some.dotted",
                              isEnabled: true)]
        #expect(dotted.mod(withLogicalFolderName: "[CP] X")?.id == ".[CP] X")

        #expect(mods.mod(withLogicalFolderName: "Absent") == nil)
    }

    /// Test 2 — la comparaison est insensible à la casse : APFS n'en distingue
    /// pas, `[CP] X` et `[cp] x` sont le même dossier.
    @Test func logicalNameIsCaseInsensitive() {
        let mods = [modItem(folderName: "[CP] Sounds of the Valley",
                            uniqueId: "Juanpa98ar.SotV")]
        #expect(mods.mod(withLogicalFolderName: "[cp] sounds of the valley")?.id
                == "[CP] Sounds of the Valley")
    }

    // MARK: - La détection (`ModZipInstaller.detectConflicts`)

    /// Test 3 — identifiant absent des installés, nom logique occupé par un
    /// mod d'autre identifiant : un conflit `.nameTakenByOtherMod`,
    /// `existingVersion` = la version de l'**occupant**, les trois
    /// résolutions offertes.
    @Test func aDifferentUniqueIdOnATakenNameDetectsNameTaken() throws {
        let occupant = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0")
        let incoming = parsedManifest(uniqueId: "Juanpa98ar.Source.SotV",
                                      name: "[CP] Sounds of the Valley",
                                      version: "4.0.0")

        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "[CP] Sounds of the Valley",
            manifest: incoming, in: [occupant])

        // L'identifiant du nouveau n'a trouvé personne : pas d'existing.
        #expect(detection.existing == nil)
        #expect(detection.conflicts.count == 1)
        let conflict = try #require(detection.conflicts.first)
        #expect(conflict.conflictType == .nameTakenByOtherMod)
        // La version affichée est celle de l'occupant — c'est lui qu'on
        // remplacerait.
        #expect(conflict.existingVersion == "3.1.0")
        #expect(conflict.newVersion == "4.0.0")
        #expect(Set(conflict.resolutionOptions)
                == Set([.overwriteWithBackup, .rename, .skip]))
    }

    /// Test 4 — le cas voisin qui ne doit **pas** fusionner : identifiant
    /// identique → exactement un conflit `.folderExists`, jamais de conflit
    /// de nom (l'occupant du nom EST l'existant).
    @Test func sameUniqueIdStillDetectsFolderExistsOnly() throws {
        let existing = modItem(folderName: "[CP] Sounds of the Valley",
                               uniqueId: "Juanpa98ar.SotV", version: "3.1.0")
        let incoming = parsedManifest(uniqueId: "Juanpa98ar.SotV",
                                      name: "[CP] Sounds of the Valley",
                                      version: "4.0.0")

        let detection = ModZipInstaller.detectConflicts(
            forFolderName: "[CP] Sounds of the Valley",
            manifest: incoming, in: [existing])

        #expect(detection.existing?.id == existing.id)
        #expect(detection.conflicts.count == 1,
                "les deux types de conflit ne fusionnent jamais")
        let conflict = try #require(detection.conflicts.first)
        #expect(conflict.conflictType == .folderExists)
        #expect(conflict.existingVersion == "3.1.0")
    }

    /// Test 5 — le défaut **par type** : une mise à jour d'identifiant écrase
    /// (le geste demandé, comportement historique inchangé) ; un nom pris par
    /// un autre mod se décale — jamais d'écrasement d'un autre mod sans choix
    /// explicite.
    @Test func defaultResolutionDependsOnConflictType() {
        #expect(ConflictResolution.default(for: .folderExists) == .overwriteWithBackup)
        #expect(ConflictResolution.default(for: .nameTakenByOtherMod) == .rename)
    }
}
