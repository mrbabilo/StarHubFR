import Testing
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

    @Test func fabriqueDepuisUnProfilEtUneSauvegarde() {
        let p = CommandPaletteEntry.forProfile(name: "Ferme d'été")
        #expect(p.kind == .profile)
        #expect(p.id == "profile:Ferme d'été")

        let s = CommandPaletteEntry.forSave(playerName: "David", farmName: "Rivedoux")
        #expect(s.kind == .save)
        #expect(s.title == "David")
        #expect(s.subtitle == "Rivedoux")
    }
}
