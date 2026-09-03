import Testing
import Foundation
@testable import StarHubTHCore

/// X12 — la liste des mods que « Je l'ai déjà » a fait taire.
///
/// Le geste est un aller sans retour tant qu'il n'est ni montré ni annulable :
/// sur l'installation de l'auteur, **34 mods** affirment une version que leur
/// dossier ne porte pas, et plusieurs ont l'air d'un clic malheureux —
/// `Florian.TacticalEchoMines` affirmé en 1.3.0 quand le disque déclare 0.1.0.
/// C'est ce rapprochement-là, pas le numéro affirmé seul, qui rend l'erreur
/// visible.
struct AffirmedUpdatesTests {

    private func anchor(_ uid: String, _ version: String,
                        _ origin: ModVersionAnchor.Origin = .userAffirmed) -> ModVersionAnchor {
        ModVersionAnchor(uniqueId: uid, anchoredVersion: version, origin: origin,
                         anchoredAt: Date())
    }

    private func mod(_ uid: String, _ name: String, _ version: String)
        -> AffirmedUpdates.InstalledMod {
        .init(uniqueId: uid, name: name, version: version)
    }

    @Test func onlyUserAffirmedAnchorsAreListed() {
        // Une ancre d'installation ou de constat disque n'est pas un geste de
        // l'utilisateur : rien à lui rendre, rien à annuler.
        let rows = AffirmedUpdates.rows(
            anchors: ["a": anchor("a", "2.0.0"),
                      "b": anchor("b", "2.0.0", .install),
                      "c": anchor("c", "2.0.0", .diskObserved)],
            installed: [mod("a", "Alpha", "1.0.0"), mod("b", "Beta", "1.0.0"),
                        mod("c", "Gamma", "1.0.0")])
        #expect(rows.map(\.uniqueId) == ["a"])
    }

    @Test func anAnchorWithoutItsModIsDropped() {
        // `pruneAnchors` fait ce ménage au scan, mais la liste ne doit pas
        // dépendre de son passage : afficher un mod désinstallé proposerait de
        // réafficher une ligne qui ne peut plus exister.
        let rows = AffirmedUpdates.rows(anchors: ["ghost": anchor("ghost", "2.0.0")],
                                        installed: [])
        #expect(rows.isEmpty)
    }

    @Test func theDiskVersionTravelsWithTheAffirmedOne() {
        // Le cas réel : affirmé « 4 », disque en 1.0.4.
        let rows = AffirmedUpdates.rows(anchors: ["a": anchor("a", "4")],
                                        installed: [mod("a", "Pathfinder Valley", "1.0.4")])
        #expect(rows.first?.affirmedVersion == "4")
        #expect(rows.first?.manifestVersion == "1.0.4")
        #expect(rows.first?.disagreesWithDisk == true)
    }

    @Test func anAffirmationTheDiskHasSinceCaughtUpWithDoesNotShout() {
        // Le manifest a rejoint la version affirmée : l'ancre ne masque plus
        // rien. La ligne reste listée — le geste a bien eu lieu — mais sans
        // l'écart qui signale l'erreur.
        let rows = AffirmedUpdates.rows(anchors: ["a": anchor("a", "1.0.4")],
                                        installed: [mod("a", "Alpha", "1.0.4")])
        #expect(rows.count == 1)
        #expect(rows.first?.disagreesWithDisk == false)
    }

    @Test func rowsAreSortedByNameThenIdentifier() {
        // Deux mods peuvent porter le même nom : sans second critère, l'ordre
        // dépendrait du parcours du dictionnaire et sauterait d'un rendu à
        // l'autre.
        let rows = AffirmedUpdates.rows(
            anchors: ["z": anchor("z", "2"), "a": anchor("a", "2"), "m": anchor("m", "2")],
            installed: [mod("z", "alpha", "1.0"), mod("a", "Beta", "1.0"),
                        mod("m", "alpha", "1.0")])
        #expect(rows.map(\.uniqueId) == ["m", "z", "a"])
    }

    @Test func aModWithoutAUniqueIdCannotBeAffirmed() {
        // Le magasin est indexé par `UniqueID` : sans identifiant, aucune ancre
        // ne peut désigner ce mod, et le croisement ne doit pas l'inventer.
        let rows = AffirmedUpdates.rows(anchors: ["": anchor("", "2")],
                                        installed: [mod("", "Sans identité", "1.0")])
        #expect(rows.isEmpty)
    }
}
