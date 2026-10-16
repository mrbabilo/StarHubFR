import Foundation
import Testing
@testable import StarHubTHCore

/// R9 — le geste proposé pour une dépendance requise non satisfaite.
@Suite struct DependencyFixTests {

    private func mod(_ id: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id + (enabled ? "" : "-paused"), version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test("En pause : l'activer, casse ignorée")
    func pausedIsActivated() {
        let paused = mod("Nature.RITS", enabled: false)
        #expect(DependencyFix.action(for: "nature.rits", installed: [paused], nexusId: 1, directDownload: true)
                == .activate(paused))
    }

    @Test("Une copie active suffit : rien à faire")
    func activeCopyWins() {
        let installed = [mod("A.B", enabled: false), mod("A.B", enabled: true)]
        #expect(DependencyFix.action(for: "A.B", installed: installed, nexusId: 1, directDownload: true) == nil)
    }

    @Test("Manquante : installer, la page sans Premium, sinon chercher")
    func missingCases() {
        #expect(DependencyFix.action(for: "X.Y", installed: [], nexusId: 42, directDownload: true) == .install(nexusId: 42))
        #expect(DependencyFix.action(for: "X.Y", installed: [], nexusId: 42, directDownload: false) == .openPage(nexusId: 42))
        #expect(DependencyFix.action(for: "X.Y", installed: [], nexusId: nil, directDownload: true) == .search)
    }
}
