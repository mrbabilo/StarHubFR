import Testing
import Foundation
@testable import StarHubTHCore

/// smapi.io répond déjà `metadata.nexusID` pour chaque mod qu'elle connaît, et
/// l'app le jetait partout sauf sur les lignes de mise à jour — où il ne sert
/// qu'au bouton de téléchargement. Un mod dont l'auteur a oublié `UpdateKeys`
/// restait donc sans page Nexus, sans suivi de version et sans recherche de
/// traduction, alors que la réponse portait son identifiant.
///
/// Mesuré sur le parc réel (2026-08-26) : **148 mods sans clé Nexus dans leur
/// manifeste, dont 30 que smapi.io identifie**. Dix de ces trente avaient déjà
/// été renseignés à la main par l'utilisateur — et **les dix concordent
/// exactement** avec ce que smapi.io répond. Restent **20 identifiants gratuits
/// aujourd'hui perdus**.
///
/// Ces tests verrouillent la décision « quel dossier apprend quoi ». Elle
/// délègue la règle d'écriture à `NexusInstallIdRecording`, la même que pour une
/// installation venue de Nexus : le manifeste fait foi, une saisie manuelle ne
/// se fait jamais écraser.
struct NexusIdLearningTests {

    private func folder(_ name: String,
                        _ uniqueId: String,
                        keys: [String] = []) -> NexusIdLearning.Folder {
        NexusIdLearning.Folder(folderName: name, uniqueId: uniqueId, updateKeys: keys)
    }

    @Test func anIdIsLearnedWhenTheManifestDeclaresNone() {
        // Cas réel : Animated Portrait Framework, mesuré sur le parc.
        let plan = NexusIdLearning.plan(
            knownIds: ["tyr4ntx.AnimatedPortraitFramework": 43364],
            folders: [folder("AnimatedPortraitFramework", "tyr4ntx.AnimatedPortraitFramework")],
            existingOverrides: [:]
        )
        #expect(plan == ["AnimatedPortraitFramework": "43364"])
    }

    @Test func theManifestWinsOverSmapi() {
        // Le manifeste est ce que SMAPI lui-même lit : un override qui le
        // double créerait une divergence silencieuse entre l'app et le jeu.
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("A", "a.b", keys: ["Nexus:2400"])],
            existingOverrides: [:]
        )
        #expect(plan.isEmpty)
    }

    @Test func aManualEntryIsNeverClobbered() {
        // Les dix saisies manuelles du parc concordaient toutes ; la onzième
        // pourrait ne pas concorder, et c'est son choix qui doit tenir.
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("A", "a.b")],
            existingOverrides: ["A": "12345"]
        )
        #expect(plan.isEmpty)
    }

    @Test func anIdenticalOverrideIsNotRewritten() {
        // Rien à écrire quand la valeur est déjà celle-là : sans ça, chaque
        // vérification de mises à jour réécrirait les préférences pour rien.
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("A", "a.b")],
            existingOverrides: ["A": "43364"]
        )
        #expect(plan.isEmpty)
    }

    @Test func aPackHeaderLearnsNothing() {
        // Un en-tête de pack porte `uniqueId: ""` : il n'a pas de verdict à lui
        // et ne doit pas hériter de celui d'un enfant.
        let plan = NexusIdLearning.plan(
            knownIds: ["": 43364, "a.b": 43364],
            folders: [folder("Pack", ""), folder("Pack/Enfant", "a.b")],
            existingOverrides: [:]
        )
        #expect(plan == ["Pack/Enfant": "43364"])
    }

    @Test func bothCopiesOfAModInstalledTwiceLearnTheSameId() {
        // Mesuré : 7 identifiants du parc sont portés par deux dossiers. Les
        // deux pointent la même page Nexus — les deux doivent l'apprendre,
        // sans quoi la copie oubliée reste invisible aux vérifications.
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("Swim", "a.b"), folder("Downloads/Swim", "a.b")],
            existingOverrides: [:]
        )
        #expect(plan == ["Swim": "43364", "Downloads/Swim": "43364"])
    }

    @Test func aModAbsentFromTheResponseLearnsNothing() {
        // Un lot en échec laisse des mods sans réponse : ne rien savoir n'est
        // pas savoir que le mod n'a pas de page.
        let plan = NexusIdLearning.plan(
            knownIds: [:],
            folders: [folder("A", "a.b")],
            existingOverrides: [:]
        )
        #expect(plan.isEmpty)
    }

    @Test func aNonPositiveIdIsRefused() {
        // `metadata.nexusID` est optionnel côté serveur ; un 0 ne mènerait
        // qu'à un 404 à chaque vérification.
        for bogus in [0, -1] {
            let plan = NexusIdLearning.plan(
                knownIds: ["a.b": bogus],
                folders: [folder("A", "a.b")],
                existingOverrides: [:]
            )
            #expect(plan.isEmpty, "id \(bogus) ne doit rien apprendre")
        }
    }

    @Test func aBlankOverrideDoesNotBlockLearning() {
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("A", "a.b")],
            existingOverrides: ["A": "   "]
        )
        #expect(plan == ["A": "43364"])
    }

    @Test func aFolderWithoutAUniqueIdLearnsNothing() {
        // Un manifeste sans `UniqueID` : SMAPI ne chargera pas ce mod, et rien
        // ne permet de le joindre à un verdict.
        let plan = NexusIdLearning.plan(
            knownIds: ["a.b": 43364],
            folders: [folder("A", "")],
            existingOverrides: [:]
        )
        #expect(plan.isEmpty)
    }

    @Test func twoFoldersOfDifferentModsSharingAPageBothLearnIt() {
        // Mesuré : East Scarp expose deux `UniqueID` distincts pour la même
        // page Nexus (5787). Ce n'est pas une collision, c'est un mod livré en
        // plusieurs composants.
        let plan = NexusIdLearning.plan(
            knownIds: ["ES.BarberShop": 5787, "atravita.EastScarp": 5787],
            folders: [folder("EastScarp/Barber", "ES.BarberShop"),
                      folder("EastScarp/CSharp", "atravita.EastScarp")],
            existingOverrides: [:]
        )
        #expect(plan == ["EastScarp/Barber": "5787", "EastScarp/CSharp": "5787"])
    }
}
