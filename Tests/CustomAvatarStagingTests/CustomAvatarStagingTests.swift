import Foundation
import Testing
@testable import StarHubTHCore

/// La règle de destination d'un avatar de sauvegarde. Elle n'avait aucun test :
/// elle vivait en ligne dans `selectCustomAvatar`, entre l'ouverture du panneau
/// système et la copie.
@Suite struct CustomAvatarStagingTests {

    private let avatars = URL(fileURLWithPath: "/data/StarHubFR/Avatars", isDirectory: true)

    private func plan(_ folderName: String, _ source: String,
                      occupied: Set<String> = []) -> CustomAvatarStaging.Plan {
        CustomAvatarStaging.plan(forSave: folderName,
                                 source: URL(fileURLWithPath: source),
                                 in: avatars,
                                 fileExists: { occupied.contains($0.lastPathComponent) })
    }

    /// Le nom composé est `<sauvegarde>_<fichier>`. Cette forme est **lue
    /// ailleurs** : `SaveHeroPortrait.resolvedImagePath` récupère un avatar dont
    /// le chemin absolu a été périmé en cherchant le fichier de même nom. La
    /// changer ici casserait la récupération là-bas.
    @Test func composeLeNomDepuisLaSauvegardeEtLeFichier() {
        let p = plan("Ferme_444827372", "/Users/x/Desktop/photo.png")
        #expect(p.destination.lastPathComponent == "Ferme_444827372_photo.png")
        #expect(p.destination.deletingLastPathComponent().path == avatars.path)
    }

    /// Le chemin d'origine peut pointer n'importe où — bureau, volume externe,
    /// photothèque. Rien de ce chemin ne doit transparaître dans le dossier de
    /// données : seul le dernier composant est repris.
    @Test func neRetientQueLeDernierComposantDeLaSource() {
        let p = plan("Ferme", "/Volumes/Photos privées/2026/été/avatar.jpeg")
        #expect(p.destination.lastPathComponent == "Ferme_avatar.jpeg")
        #expect(!p.destination.path.contains("Photos privées"))
        #expect(!p.destination.path.contains("été"))
    }

    /// Place libre : rien à retirer avant la copie.
    @Test func placeLibreNeRemplaceRien() {
        #expect(plan("Ferme", "/x/photo.png").replacesExisting == false)
    }

    /// **Le défaut que cette extraction corrige.** Deux images différentes
    /// peuvent porter le même nom de fichier (`photo.png` dans deux dossiers).
    /// La destination composée est alors identique, et `copyItem` refuse
    /// d'écrire sur un fichier existant — mesuré : `NSFileWriteFileExists`
    /// (516), l'ancienne image reste en place. Le joueur voyait son avatar ne
    /// pas changer, sans un mot à l'écran : seule une ligne de journal le
    /// disait. Le plan nomme donc le remplacement au lieu de le subir.
    @Test func placeOccupeeSeSignaleAuLieuDEchouer() {
        let p = plan("Ferme", "/autre/dossier/photo.png",
                     occupied: ["Ferme_photo.png"])
        #expect(p.replacesExisting == true)
        #expect(p.destination.lastPathComponent == "Ferme_photo.png")
    }

    /// L'occupation se juge sur **cette** destination, pas sur le dossier.
    /// Un avatar posé pour une autre sauvegarde ne doit rien déclencher —
    /// `folderName` est l'identité d'une sauvegarde, deux d'entre elles ne
    /// peuvent pas se disputer un nom.
    @Test func lAvatarDuneAutreSauvegardeNeComptePas() {
        let p = plan("Ferme", "/x/photo.png", occupied: ["Verger_photo.png"])
        #expect(p.replacesExisting == false)
    }
}
