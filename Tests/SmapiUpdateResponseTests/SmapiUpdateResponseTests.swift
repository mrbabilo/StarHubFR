import Testing
import Foundation
@testable import StarHubTHCore

/// Les charges utiles de ces tests sont des réponses **réelles** de
/// smapi.io, relevées le 2026-08-12 sur le parc de 960 mods. Les inventer
/// aurait masqué ce qui compte : `metadata` est presque vide pour les mods que
/// la base ne connaît pas, et les erreurs sont des phrases anglaises libres.
struct SmapiUpdateResponseTests {

    @Test func aSuggestedUpdateIsRead() throws {
        let json = """
        [{"id":"selph.ExtraMachineConfig",
          "suggestedUpdate":{"version":"1.18.0",
                             "url":"https://www.nexusmods.com/stardewvalley/mods/22256"},
          "metadata":{"id":["selph.ExtraMachineConfig"],"name":"Extra Machine Configs",
                      "nexusID":22256,
                      "main":{"version":"1.18.0","url":"https://x"},
                      "compatibilityStatus":"Ok"},
          "errors":[]}]
        """
        let mods = try SmapiUpdateResponse.decode(Data(json.utf8))
        #expect(mods.count == 1)
        #expect(mods[0].suggestedUpdate?.version == "1.18.0")
        #expect(mods[0].metadata?.nexusID == 22256)
        #expect(mods[0].metadata?.compatibilityStatus == "Ok")
    }

    @Test func aModWithNoUpdateHasNoSuggestion() throws {
        let json = """
        [{"id":"a","metadata":{"id":[]},"errors":[]}]
        """
        let mods = try SmapiUpdateResponse.decode(Data(json.utf8))
        #expect(mods[0].suggestedUpdate == nil)
    }

    @Test func anAlmostEmptyMetadataStillDecodes() throws {
        // Cas réel et fréquent : smapi.io ne connaît pas le mod, `metadata`
        // ne porte qu'un tableau `id` vide. Exiger `name` ou `nexusID`
        // ferait échouer le décodage du lot entier.
        let json = """
        [{"id":"Owljoy.ShopSearch","metadata":{"id":[]},"errors":[]}]
        """
        let mods = try SmapiUpdateResponse.decode(Data(json.utf8))
        #expect(mods[0].metadata?.name == nil)
        #expect(mods[0].metadata?.nexusID == nil)
    }

    @Test func aMissingMetadataKeyDecodes() throws {
        let mods = try SmapiUpdateResponse.decode(Data("""
        [{"id":"a"}]
        """.utf8))
        #expect(mods[0].metadata == nil)
        #expect(mods[0].errors.isEmpty)
    }

    @Test func malformedJsonThrowsRatherThanReturningNothing() {
        // Rendre `[]` ferait passer une panne de décodage pour « aucun mod à
        // jour » — exactement le silence qu'on cherche à supprimer.
        #expect(throws: (any Error).self) {
            try SmapiUpdateResponse.decode(Data("pas du json".utf8))
        }
    }

    // MARK: familles d'erreurs

    @Test func anInvalidNexusIdIsClassified() {
        #expect(SmapiUpdateResponse.blocker(for:
            "The value 'ceruleandeep.ja.personaleffects' isn't a valid Nexus mod ID, must be an integer ID.")
            == .malformedNexusId)
    }

    @Test func aMissingNexusPageIsClassified() {
        #expect(SmapiUpdateResponse.blocker(for: "Found no Nexus mod with this ID.")
            == .sourceNotFound)
    }

    @Test func aSourceWithoutValidVersionsIsClassified() {
        #expect(SmapiUpdateResponse.blocker(for:
            "The CurseForge mod with ID '1234' has no valid versions.") == .noValidVersion)
        #expect(SmapiUpdateResponse.blocker(for:
            "The Nexus mod with ID '5678' has no valid versions.") == .noValidVersion)
    }

    @Test func aMalformedUpdateKeyIsClassified() {
        #expect(SmapiUpdateResponse.blocker(for:
            "The update key 'Nexus' isn't in a valid format. It should contain the site key and mod ID like 'Nexus:541'.")
            == .malformedUpdateKey)
    }

    @Test func aMissingGitHubOrModDropIsClassified() {
        #expect(SmapiUpdateResponse.blocker(for: "Found no GitHub release for this ID.")
            == .sourceNotFound)
        #expect(SmapiUpdateResponse.blocker(for: "Found no ModDrop mod with this ID.")
            == .sourceNotFound)
    }

    @Test func anUnrecognisedErrorFallsBackToOther() {
        // La famille inconnue ne doit pas être avalée : elle reste affichable
        // avec son texte d'origine.
        #expect(SmapiUpdateResponse.blocker(for: "Quelque chose d'inédit") == .other)
    }

    @Test func blockerLabelKeysAreDistinctAndWired() {
        // La fenêtre des mises à jour affiche le motif de chaque mod
        // invérifiable. Deux familles qui se reflèteraient feraient taire une
        // distinction que smapi.io a prise la peine de marquer — et un mappage
        // vers une clé sans libellé dans les deux langues casserait la
        // parité au build.
        let keys: [SmapiUpdateResponse.Blocker: String] = [
            .malformedNexusId: L10n.Updates.blockerMalformedNexusId,
            .sourceNotFound: L10n.Updates.blockerSourceNotFound,
            .noValidVersion: L10n.Updates.blockerNoValidVersion,
            .malformedUpdateKey: L10n.Updates.blockerMalformedUpdateKey,
            .other: L10n.Updates.blockerOther,
        ]
        for (blocker, key) in keys {
            #expect(blocker.labelKey == key)
        }
        #expect(Set(keys.values).count == keys.count)
    }

    // MARK: - L'entrée qui vide son lot

    /// smapi.io répond `200` et une **liste vide** quand une seule entrée du
    /// lot lui déplaît. Mesuré le 2026-08-27 sur le parc réel :
    /// `Wesley.ArtisanQualityInOut` déclare `Version: "%ProjectVersion%"` — un
    /// jeton MSBuild non substitué — et les 149 autres mods du lot repartent
    /// sans verdict. Le client re-découpe désormais le lot et remonte l'entrée
    /// fautive sous ce motif, qui n'est **pas** une phrase de smapi.io.
    @Test func leMotifFabriqueParLAppSeClasseSousSonPropreNom() {
        #expect(SmapiUpdateResponse.blocker(for: SmapiUpdateResponse.rejectedEntryError)
                == .rejectedEntry)
    }

    @Test func ceMotifNeCollisionnePasAvecLesPhrasesDeSmapi() {
        // Le préfixe `starhub:` le met hors de portée des phrases anglaises
        // libres du serveur — et le classement le teste avant elles.
        #expect(SmapiUpdateResponse.rejectedEntryError.hasPrefix("starhub:"))
        for phrase in ["The Nexus mod with ID '50165' has no valid versions.",
                       "Found no Nexus mod with this ID.",
                       "The value '???' isn't a valid Nexus mod ID, must be an integer ID.",
                       "The update key 'Nexus:' isn't in a valid format."] {
            #expect(SmapiUpdateResponse.blocker(for: phrase) != .rejectedEntry)
        }
    }

    @Test func uneEntreeFabriqueeSeComporteCommeUneReponse() {
        // Elle doit traverser le pipeline comme les autres : un mod sans
        // réponse n'apparaît nulle part, c'est tout le défaut.
        let mod = SmapiUpdateResponse.Mod(
            id: "Wesley.ArtisanQualityInOut",
            errors: [SmapiUpdateResponse.rejectedEntryError])
        #expect(mod.suggestedUpdate == nil)
        #expect(mod.metadata == nil)
        #expect(mod.errors.count == 1)
        #expect(SmapiUpdateResponse.blocker(for: mod.errors[0]) == .rejectedEntry)
    }
}
