import Testing
import Foundation
@testable import StarHubTHCore

/// N-04 — « À régler » et « Récemment installés » sous les tuiles de l'Accueil.
@Suite("Accueil : à régler et récemment installés")
struct HomeAgendaTests {

    private func issue(_ id: String, _ severity: HealthIssue.Severity,
                       _ actions: [HealthIssue.Action] = []) -> HealthIssue {
        HealthIssue(id: id, severity: severity, source: .smapi, title: id,
                    detail: nil, actions: actions)
    }

    private func mod(_ name: String, installed: Date?, children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: name, name: name, folderName: name, version: "1.0", author: "",
                description: "", nexusUrl: "", nexusModId: "", isEnabled: true,
                dependencies: [], children: children, isGroup: children != nil,
                installedFileDate: installed)
    }

    // MARK: - À régler

    /// Rien d'actionnable : la section dit qu'il n'y a rien (« un 0 se lit »).
    @Test func sansProblemeLaListeEstVide() {
        let agenda = HomeAgenda.toFix([issue("note", .info)])
        #expect(agenda.rows.isEmpty)
        #expect(agenda.remaining == 0)
    }

    /// Critique d'abord, l'ordre des Alertes gardé dans chaque gravité ;
    /// les notices `.info` n'y figurent pas (comme la pastille).
    @Test func lesCritiquesPassentDevantDansLOrdreDesAlertes() {
        let agenda = HomeAgenda.toFix([issue("w1", .warning), issue("i1", .info),
                                       issue("c1", .critical), issue("w2", .warning),
                                       issue("c2", .critical)])
        #expect(agenda.rows.map(\.id) == ["c1", "c2", "w1", "w2"])
    }

    /// Cinq lignes au plus ; le reste se compte, pour le lien vers les Alertes.
    @Test func cinqLignesAuPlusEtLeResteCompte() {
        let issues = (1...8).map { issue("w\($0)", .warning) }
        let agenda = HomeAgenda.toFix(issues)
        #expect(agenda.rows.count == 5)
        #expect(agenda.remaining == 3)
    }

    /// Une ligne mène à une **destination**, jamais à une écriture : renommer,
    /// réparer ou réinstaller restent aux Alertes, où leur feuille vit.
    @Test func laLigneMeneAuPremierCheminDeNavigation() {
        let rename = issue("r", .warning, [.renameFolder(folderName: "X"),
                                           .openModDependencies(query: "X")])
        #expect(HomeAgenda.destination(of: rename) == .openModDependencies(query: "X"))
        let writeOnly = issue("w", .warning, [.repairManifest(folderName: "X")])
        #expect(HomeAgenda.destination(of: writeOnly) == nil)
    }

    // MARK: - Récemment installés

    /// Le plus récent d'abord, cinq au plus, les mods sans date écartés ; un
    /// pack compte pour une ligne, à la date de son composant le plus récent.
    @Test func lesPlusRecentsDAbordUnPackPourUneLigne() {
        let d = { (s: Double) in Date(timeIntervalSince1970: s) }
        let pack = mod("Pack", installed: nil,
                       children: [mod("A", installed: d(50)), mod("B", installed: d(900))])
        let mods = [mod("Old", installed: d(10)), mod("NoDate", installed: nil), pack,
                    mod("M1", installed: d(500)), mod("M2", installed: d(600)),
                    mod("M3", installed: d(700)), mod("M4", installed: d(800))]
        let recent = HomeAgenda.recentlyInstalled(mods)
        #expect(recent.map(\.name) == ["Pack", "M4", "M3", "M2", "M1"])
    }
}
