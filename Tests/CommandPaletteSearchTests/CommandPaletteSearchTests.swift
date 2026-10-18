import Testing
import Foundation
@testable import StarHubTHCore

@Suite("Classement de la palette de commandes")
struct CommandPaletteSearchTests {

    private func mod(_ title: String, _ subtitle: String? = nil) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "mod:\(title)", kind: .mod, title: title,
                            subtitle: subtitle, icon: "puzzlepiece.extension.fill")
    }
    private func page(_ title: String) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "dest:\(title)", kind: .destination, title: title,
                            subtitle: nil, icon: "house.fill")
    }

    @Test func lExactPasseAvantLePrefixe() {
        let r = CommandPaletteSearch.rank("auto", in: [mod("Automate"), mod("Auto")])
        #expect(r.first?.title == "Auto")
    }

    @Test func lePrefixePasseAvantLeContenu() {
        let r = CommandPaletteSearch.rank("patch", in: [mod("Content Patcher"),
                                                        mod("Patcher Tools")])
        #expect(r.first?.title == "Patcher Tools")
    }

    @Test func leContenuPasseAvantLaSousSequence() {
        let r = CommandPaletteSearch.rank("cp", in: [mod("Content Patcher"),
                                                      mod("CPU Monitor")])
        #expect(r.first?.title == "CPU Monitor")
    }

    /// L'exemple de la spec : « cp » doit trouver « Content Patcher ».
    @Test func laSousSequenceTrouveLesInitiales() {
        let r = CommandPaletteSearch.rank("cp", in: [mod("Content Patcher")])
        #expect(r.map(\.title) == ["Content Patcher"])
    }

    /// ⚠️ Tracé à la main avant d'écrire le test : pour « pathoschild »,
    /// « Pathfinder » ne correspond par **rien** — pas même en sous-séquence,
    /// il n'y a pas de `o` après `path`. La requête est donc « path », où
    /// « Pathfinder » gagne par préfixe et « Automate » ne rentre que par son
    /// sous-titre.
    @Test func leSousTitreEstLaDerniereChance() {
        let r = CommandPaletteSearch.rank("path",
                                          in: [mod("Automate", "Pathoschild"),
                                               mod("Pathfinder")])
        #expect(r.map(\.title) == ["Pathfinder", "Automate"])
    }

    /// Et le sous-titre rattrape bien ce que le titre ne dit pas.
    @Test func leSousTitreSeulSuffitAEtreTrouve() {
        let r = CommandPaletteSearch.rank("pathoschild",
                                          in: [mod("Automate", "Pathoschild"),
                                               mod("Pathfinder")])
        #expect(r.map(\.title) == ["Automate"])
    }

    /// Le pliage sert les libellés FR de destinations et les noms libres —
    /// le parc de mods, lui, n'a aucun diacritique (mesuré, spec §6.3).
    @Test func lesAccentsSontIgnores() {
        let r = CommandPaletteSearch.rank("reglages", in: [page("Réglages")])
        #expect(r.map(\.title) == ["Réglages"])
    }

    @Test func lAccentDansLaRequeteTrouveAussi() {
        let r = CommandPaletteSearch.rank("Réglages", in: [page("Reglages")])
        #expect(r.count == 1)
    }

    @Test func laCasseEstIndifferente() {
        #expect(CommandPaletteSearch.rank("AUTOMATE", in: [mod("Automate")]).count == 1)
    }

    @Test func aEgaliteLaPagePasseDevantLeMod() {
        let r = CommandPaletteSearch.rank("journal", in: [mod("Journal"), page("Journal")])
        #expect(r.first?.kind == .destination)
    }

    @Test func aEgaliteLeTitreLePlusCourtGagne() {
        let r = CommandPaletteSearch.rank("auto", in: [mod("Automate Deluxe"),
                                                        mod("Automate")])
        #expect(r.first?.title == "Automate")
    }

    @Test func leClassementEstDeterministe() {
        let entries = [mod("Alpha"), mod("Beta"), mod("Gamma"), page("Alpha")]
        let a = CommandPaletteSearch.rank("a", in: entries).map(\.id)
        let b = CommandPaletteSearch.rank("a", in: entries).map(\.id)
        #expect(a == b)
    }

    /// Faire tomber 966 mods dans une palette vide la rendrait illisible.
    @Test func requeteVideRendLesSeulesDestinations() {
        let r = CommandPaletteSearch.rank("", in: [mod("Automate"), page("Accueil")])
        #expect(r.map(\.kind) == [.destination])
    }

    @Test func requeteBlancheCompteCommeVide() {
        let r = CommandPaletteSearch.rank("   ", in: [mod("Automate"), page("Accueil")])
        #expect(r.map(\.kind) == [.destination])
    }

    @Test func laLimiteEstRespectee() {
        let many = (0..<50).map { mod("Automate \($0)") }
        #expect(CommandPaletteSearch.rank("automate", in: many, limit: 20).count == 20)
    }

    @Test func uneRequetePlusLongueQueToutNeRendRien() {
        let r = CommandPaletteSearch.rank("xxxxxxxxxxxxxxxxxxxx", in: [mod("Auto")])
        #expect(r.isEmpty)
    }

    @Test func fabriqueDepuisUneDestination() {
        let entry = SidebarOrder.all.first { $0.destination == .mods }
        #expect(entry != nil)
        guard let entry else { return }
        let e = CommandPaletteEntry.forDestination(entry, title: "Gestion des mods")
        #expect(e.kind == .destination)
        #expect(e.title == "Gestion des mods")
        #expect(e.id == "dest:Mods")
        #expect(e.icon == "puzzlepiece.extension.fill")
    }

    /// N-10 : le titre complet reste affiché, mais la forme courte de la
    /// barre doit aussi retrouver la destination sans devenir un sous-titre.
    @Test func uneDestinationSeChercheAussiParSonLibelleCourt() {
        let entry = SidebarOrder.all.first { $0.destination == .updates }
        #expect(entry != nil)
        guard let entry else { return }
        let e = CommandPaletteEntry.forDestination(
            entry, title: "Mise à jour des mods", shortTitle: "Mises à jour")

        #expect(CommandPaletteSearch.rank("Mises à jour", in: [e]).map(\.title)
                == ["Mise à jour des mods"])
        #expect(e.subtitle == nil)
    }

    @Test func fabriqueDepuisUnProfilEtUneSauvegarde() {
        let id = UUID()
        let p = CommandPaletteEntry.forProfile(name: "Ferme d'été", id: id)
        #expect(p.kind == .profile)
        #expect(p.id == "profile:\(id.uuidString)")
        // Deux homonymes restent deux entrées distinctes (I-T5).
        #expect(CommandPaletteEntry.forProfile(name: "Ferme d'été", id: UUID()).id != p.id)

        let s = CommandPaletteEntry.forSave(playerName: "David", farmName: "Rivedoux",
                                            folderName: "David_123")
        #expect(s.kind == .save)
        #expect(s.title == "David")
        #expect(s.subtitle == "Rivedoux")
        // N-08 : ↩ ouvre la partie désignée par son dossier — deux parties
        // homonymes (une copie) restent distinctes.
        #expect(s.id == "save:David_123")
    }

    // MARK: - N-08 : les actions

    private func action(_ title: String) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "action:\(title)", kind: .action, title: title,
                            subtitle: nil, icon: "bolt")
    }

    /// Une action ne sort que sur un début de titre : « mise » ne doit pas
    /// trouver « Vérifier les mises à jour » par le milieu.
    @Test func uneActionNeSortQueSurUnDebutDeTitre() {
        let entries = [action("Vérifier les mises à jour")]
        #expect(CommandPaletteSearch.displayed("verif", in: entries).count == 1)
        #expect(CommandPaletteSearch.displayed("mise", in: entries).isEmpty)
        #expect(CommandPaletteSearch.displayed("vmaj", in: entries).isEmpty)
    }

    /// « ver » : « Vertical Toolbar » correspond aussi bien que l'action —
    /// ↩ doit ouvrir le mod, pas lancer une vérification.
    @Test func aCorrespondanceEgaleLeModPasseDevantLAction() {
        let r = CommandPaletteSearch.displayed(
            "ver", in: [action("Vérifier les mises à jour"), mod("Vertical Toolbar")])
        #expect(r.map(\.title) == ["Vertical Toolbar", "Vérifier les mises à jour"])
    }

    /// « lancer » : l'action correspond par le début, « Balancer » seulement
    /// par le milieu — l'action passe en tête.
    @Test func uneActionMieuxApparieePasseEnTete() {
        let r = CommandPaletteSearch.displayed(
            "lancer", in: [mod("Balancer"), action("Lancer le jeu")])
        #expect(r.first?.title == "Lancer le jeu")
    }

    /// Requête vide : les pages seules, comme avant — pas d'action.
    @Test func requeteVideNeMontreNiModNiAction() {
        let r = CommandPaletteSearch.displayed("", in: [page("Accueil"), action("Lancer le jeu"),
                                                        mod("Automate")])
        #expect(r.map(\.title) == ["Accueil"])
    }

    /// L'affichage regroupe par nature sans doublonner les en-têtes : un mod
    /// mieux apparié qu'une page sort quand même dans le groupe des mods.
    @Test func lAffichageRegroupeParNature() {
        let r = CommandPaletteSearch.displayed(
            "re", in: [mod("Reflections"), page("Réglages"), mod("Better Rendering")])
        #expect(r.map(\.kind) == [.destination, .mod, .mod])
    }
}
