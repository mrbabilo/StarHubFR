import Testing
import Foundation
@testable import StarHubTHCore

/// La lecture des champs d'un `manifest.json` était écrite **trois fois** :
/// deux fois dans le scan (branche « cache chaud » et branche « lecture
/// disque » de `parseModFolder`) et une fois dans `ModManifest.init?(dict:)`.
/// Le commentaire laissé sur la version disait déjà ce que coûte cette
/// divergence — « le même mod pouvait rendre deux versions différentes selon
/// que son manifeste venait du cache ou du disque ».
///
/// ⚠️ Ce lecteur rend les champs **bruts**. Les replis (`"Unknown"`, le nom du
/// dossier quand `Name` manque) appartiennent à l'appelant : le scan retombe
/// sur le nom **logique du dossier**, que rien en Core ne connaît. Rendre ici
/// un `""` ou un `"Unknown"` remplacerait ce nom en silence.
struct ManifestFieldsTests {

    // MARK: - Lecture brute

    @Test func everyFieldIsReadRegardlessOfKeyCase() {
        let fields = ManifestFields(manifest: [
            "name": "Chores",
            "uniqueid": "xzqute.ChoreTrail",
            "AUTHOR": "xzqute",
            "Description": "Des corvées",
            "version": "1.2.3"
        ])
        #expect(fields.name == "Chores")
        #expect(fields.uniqueId == "xzqute.ChoreTrail")
        #expect(fields.author == "xzqute")
        #expect(fields.description == "Des corvées")
        #expect(fields.version == "1.2.3")
    }

    @Test func anAbsentFieldStaysNilSoTheCallerKeepsItsOwnFallback() {
        // Le scan affiche le nom du dossier logique quand `Name` manque — 111
        // mods du parc n'ont pas même d'`UniqueID`. Un défaut posé ici les
        // afficherait sans nom.
        let fields = ManifestFields(manifest: [:])
        #expect(fields.name == nil)
        #expect(fields.uniqueId == nil)
        #expect(fields.author == nil)
        #expect(fields.description == nil)
        #expect(fields.version == nil)
    }

    @Test func anEmptyNameIsNotAnAbsentName() {
        // `ModManifest.init?(dict:)` refuse un manifeste sans `Name` mais
        // accepte `""`. Confondre les deux ici déplacerait sa garde.
        let fields = ManifestFields(manifest: ["Name": "", "UniqueID": ""])
        #expect(fields.name == "")
        #expect(fields.uniqueId == "")
    }

    @Test func aFieldOfTheWrongTypeReadsAsAbsent() {
        let fields = ManifestFields(manifest: ["Name": 42, "UpdateKeys": "Nexus:191"])
        #expect(fields.name == nil)
        #expect(fields.updateKeys.isEmpty)
    }

    // MARK: - Les champs qui délèguent

    @Test func theVersionGoesThroughTheSharedReader() {
        // Forme objet : c'est la forme sur laquelle une lecture écrite à la
        // main divergeait.
        let fields = ManifestFields(manifest: [
            "Version": ["MajorVersion": 1, "MinorVersion": 2, "PatchVersion": 3]
        ])
        #expect(fields.version == "1.2.3")
    }

    @Test func dependenciesGoThroughTheSharedParser() {
        // `ContentPackFor` est la façon dont la plupart des content packs
        // déclarent leur seule exigence.
        let fields = ManifestFields(manifest: [
            "ContentPackFor": ["UniqueID": "Pathoschild.ContentPatcher"]
        ])
        #expect(fields.dependencies.map(\.uniqueId) == ["Pathoschild.ContentPatcher"])
    }

    @Test func theNexusIdGoesThroughTheSharedHelper() {
        // Espaces et suffixe `@variante` : la tolérance vient de
        // `ModManifest.parseNexusId`, elle n'est pas réécrite ici.
        let fields = ManifestFields(manifest: ["UpdateKeys": ["Nexus: 23169@SwimItems "]])
        #expect(fields.nexus?.id == "23169")
        #expect(fields.nexus?.url == "https://www.nexusmods.com/stardewvalley/mods/23169")
    }

    @Test func noUpdateKeyMeansNoNexusLinkRatherThanAnEmptyId() {
        let fields = ManifestFields(manifest: ["UpdateKeys": ["GitHub:foo/bar"]])
        #expect(fields.nexus == nil)
        #expect(fields.updateKeys == ["GitHub:foo/bar"])
    }

    // MARK: - Le seul champ qui porte une politique

    @Test func aBlankCautionMessageAnnouncesNothing() {
        // Extension Stardrop : un message d'espaces n'alerte pas plus qu'un
        // champ absent.
        #expect(ManifestFields(manifest: ["UpdateCautionMessage": "   "]).updateCautionMessage == nil)
        #expect(ManifestFields(manifest: [:]).updateCautionMessage == nil)
        #expect(ManifestFields(manifest: ["UpdateCautionMessage": "Casse les sauvegardes"])
                    .updateCautionMessage == "Casse les sauvegardes")
    }
}
