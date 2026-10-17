import Foundation
import Testing
@testable import StarHubTHCore

/// R9 — le geste proposé pour une dépendance requise non satisfaite.
@Suite struct DependencyFixTests {

    private func mod(_ id: String, folder: String? = nil, enabled: Bool,
                     requires: [String] = []) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: folder ?? id, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled,
                dependencies: requires.map { ModDependency(uniqueId: $0, isRequired: true) })
    }

    @Test("En pause : l'activer")
    func pausedIsActivated() {
        let paused = mod("Nature.RITS", enabled: false)
        #expect(DependencyFix.action(resolved: paused, nexusId: 1, directDownload: true) == .activate(paused))
    }

    @Test("Active : rien à faire")
    func activeNeedsNothing() {
        #expect(DependencyFix.action(resolved: mod("A.B", enabled: true), nexusId: 1, directDownload: true) == nil)
    }

    @Test("Manquante : installer, la page sans Premium, sinon chercher")
    func missingCases() {
        #expect(DependencyFix.action(resolved: nil, nexusId: 42, directDownload: true) == .install(nexusId: 42))
        #expect(DependencyFix.action(resolved: nil, nexusId: 42, directDownload: false) == .openPage(nexusId: 42))
        #expect(DependencyFix.action(resolved: nil, nexusId: nil, directDownload: true) == .search)
    }

    /// Id partagé par deux dossiers (58 au parc) : l'encart dit « désactivée »
    /// exactement quand le geste propose « Activer », sur le même mod.
    @Test("Id partagé : l'encart et le geste jugent la même copie", arguments: [true, false])
    func sharedIdAgreesWithBanner(lastEnabled: Bool) {
        let first = mod("Shared.Dep", folder: "SharedA", enabled: !lastEnabled)
        let last = mod("Shared.Dep", folder: "SharedB", enabled: lastEnabled)
        let dependent = mod("User.Mod", enabled: true, requires: ["shared.dep"])
        let index = DependencyIndex.build(from: [first, last, dependent])
        let flagged = !index.disabled(for: dependent).isEmpty
        let fix = DependencyFix.action(resolved: index.resolve("Shared.Dep")?.mod, nexusId: nil, directDownload: true)
        #expect(flagged == (fix != nil))
        if case .activate(let target) = fix { #expect(!target.isEnabled) }
    }
}
