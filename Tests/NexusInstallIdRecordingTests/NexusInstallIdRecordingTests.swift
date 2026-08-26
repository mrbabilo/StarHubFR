import Testing
import Foundation
@testable import StarHubTHCore

/// Quand un mod arrive par Nexus (lien `nxm://` ou téléchargement intégré),
/// l'app connaît son identifiant. Elle s'en servait puis le jetait : un mod
/// dont l'auteur a oublié `UpdateKeys` devenait alors définitivement invisible
/// aux vérifications de mises à jour, sans le moindre signal. Sur un parc réel
/// de 966 mods, 111 étaient dans ce cas.
///
/// Ces tests verrouillent la décision « faut-il retenir cet identifiant ? ».
/// Elle doit être avare : le manifeste fait foi (c'est ce que SMAPI lit), et
/// une saisie manuelle ne se fait pas écraser par une installation.
struct NexusInstallIdRecordingTests {

    @Test func anIdIsRecordedWhenTheManifestDeclaresNone() {
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: nil,
            existingOverride: nil
        )
        #expect(recorded == "49133")
    }

    @Test func anIdIsRecordedWhenUpdateKeysHoldNoNexusEntry() {
        // Cas réel : beaucoup de mods ne déclarent que GitHub ou ModDrop.
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49953,
            manifestUpdateKeys: ["GitHub:author/repo", "ModDrop:1234"],
            existingOverride: nil
        )
        #expect(recorded == "49953")
    }

    @Test func theManifestWinsOverTheDownloadedId() {
        // Le manifeste est ce que SMAPI lui-même lit. Enregistrer un override
        // ici créerait une divergence silencieuse entre l'app et le jeu.
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: ["Nexus:2400"],
            existingOverride: nil
        )
        #expect(recorded == nil)
    }

    @Test func aVariantSuffixStillCountsAsADeclaredId() {
        // `Nexus:23169@SwimItems` : les packs multi-mods partagent un id.
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: ["Nexus:23169@SwimItems"],
            existingOverride: nil
        )
        #expect(recorded == nil)
    }

    @Test func aManualOverrideIsNeverClobbered() {
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: nil,
            existingOverride: "12345"
        )
        #expect(recorded == nil)
    }

    @Test func aBlankOverrideIsNotAnOverride() {
        // Un champ vidé puis laissé tel quel ne doit pas bloquer l'apprentissage.
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: nil,
            existingOverride: "   "
        )
        #expect(recorded == "49133")
    }

    @Test func aNonPositiveIdIsRefused() {
        // Un `nxm://` malformé ou un champ non renseigné ne doit rien écrire :
        // l'app interrogerait ensuite une page qui n'existe pas.
        for bogus in [0, -1] {
            let recorded = NexusInstallIdRecording.idToRecord(
                sourceModId: bogus,
                manifestUpdateKeys: nil,
                existingOverride: nil
            )
            #expect(recorded == nil, "id \(bogus) ne doit rien enregistrer")
        }
    }

    @Test func aMalformedNexusKeyDoesNotCountAsDeclared() {
        // `Nexus:` sans chiffre, ou un id à zéro : `parseNexusId` les rejette,
        // donc le mod n'est PAS interrogeable et l'identifiant téléchargé est
        // la seule chose exploitable.
        let recorded = NexusInstallIdRecording.idToRecord(
            sourceModId: 49133,
            manifestUpdateKeys: ["Nexus:", "Nexus:0"],
            existingOverride: nil
        )
        #expect(recorded == "49133")
    }
}
