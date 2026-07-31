import Foundation
import SwiftUI

/// Pilote une recherche : traduit les décisions de `BisectionSession` en
/// déplacements de dossiers, lance le jeu, et attend le retour de l'utilisateur.
///
/// Toute la logique de recherche vit dans `BisectionSession` (Core, testée) ;
/// cette classe ne fait que la relier au disque et à l'interface.
@MainActor
final class BisectionRunner: ObservableObject {
    @Published private(set) var state: BisectionState?
    @Published private(set) var isApplying = false
    @Published private(set) var currentFolders: [String] = []
    @Published var interruptedSnapshot: BisectionSnapshot?

    private var session: BisectionSession?
    private var snapshot: BisectionSnapshot?

    /// Le runner vit aussi longtemps que le ViewModel (`lazy var bisection`),
    /// donc le cycle de vie est garanti : `unowned` évite un cycle de rétention
    /// sans risquer un accès après libération.
    private unowned let vm: StarHubTHViewModel

    /// `nonisolated` : l'init ne fait que stocker la référence au ViewModel, il
    /// n'accède à aucun état MainActor. Permet l'instanciation paresseuse depuis
    /// le ViewModel (`lazy var bisection`), lui-même non isolé.
    nonisolated init(vm: StarHubTHViewModel) { self.vm = vm }

    /// Au démarrage de l'app : une recherche laissée en plan ?
    func checkForInterruptedSession() {
        interruptedSnapshot = BisectionSnapshotStore.load()
    }

    func start() {
        let list = candidates(from: vm.mods, gameDir: vm.gameDir)
        guard !list.isEmpty else { state = .inconclusive; return }

        // L'instantané part sur le disque AVANT le premier déplacement.
        let snap = BisectionSnapshot(
            enabledFolders: vm.mods.filter(\.isEnabled).map(\.folderName),
            startedAt: Date()
        )
        BisectionSnapshotStore.save(snap)
        snapshot = snap

        let s = BisectionSession(candidates: list)
        session = s
        state = s.state
        apply(s.foldersToEnable) { [weak self] in self?.vm.launchGame() }
    }

    func answer(_ outcome: BisectionOutcome) {
        guard var s = session else { return }
        s.record(outcome)
        session = s
        state = s.state
        switch s.state {
        case .concluded, .inconclusive, .notReproducible:
            // Recherche finie : on remet tout comme avant, sauf le mod trouvé
            // (s'il y en a un), laissé en pause pour que l'utilisateur décide.
            let keepPaused = s.state.concludedFolder.map { [$0] } ?? []
            let restore = (snapshot?.enabledFolders ?? []).filter { !keepPaused.contains($0) }
            apply(restore) { BisectionSnapshotStore.clear(); self.snapshot = nil }
        default:
            apply(s.foldersToEnable) { [weak self] in self?.vm.launchGame() }
        }
    }

    func restoreAndStop() {
        let restore = snapshot?.enabledFolders ?? interruptedSnapshot?.enabledFolders ?? []
        apply(restore) {
            BisectionSnapshotStore.clear()
            self.snapshot = nil
            self.interruptedSnapshot = nil
            self.session = nil
            self.state = nil
        }
    }

    /// Applique un ensemble de dossiers actifs, puis enchaîne. `isApplying`
    /// borne l'UI : tant qu'il est vrai, la carte affiche « Je lance le jeu… »
    /// et ne propose pas de réponse — l'utilisateur ne peut pas anticiper la fin
    /// du rescane.
    private func apply(_ folders: [String], then next: @escaping () -> Void) {
        isApplying = true
        currentFolders = folders
        vm.applyEnabledFolders(folders) { [weak self] in
            self?.isApplying = false
            next()
        }
    }

    /// Candidats = dossiers de premier niveau actifs contenant du code.
    /// Un pack compte pour un, puisqu'il bascule d'un bloc.
    private func candidates(from mods: [ModItem], gameDir: String) -> [BisectionCandidate] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        return mods.compactMap { mod -> BisectionCandidate? in
            guard mod.isEnabled else { return nil }
            let folder = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
            guard Self.containsCode(at: folder) else { return nil }
            let children = mod.isGroup ? (mod.children ?? []) : [mod]
            return BisectionCandidate(
                folderName: mod.folderName,
                uniqueIds: children.map(\.uniqueId).filter { !$0.isEmpty },
                requires: children.flatMap(\.dependencies).filter(\.isRequired).map(\.uniqueId)
            )
        }
    }

    /// Un dossier « contient du code » s'il embarque un `.dll` : un pack de
    /// contenu ne s'exécute pas, il est lu par Content Patcher.
    private static func containsCode(at path: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return false }
        for case let file as String in enumerator where file.lowercased().hasSuffix(".dll") {
            return true
        }
        return false
    }
}

private extension BisectionState {
    var concludedFolder: String? {
        if case .concluded(let folder) = self { return folder }
        return nil
    }
}
