import Foundation

/// I-T21 lot 1 — la corbeille d'une sélection multiple : délégations seules
/// (F1-T2), la règle vit dans `ModTrashSelection`.
extension StarHubTHViewModel {
    /// Déplacer le dossier d'un mod chargé laisse SMAPI pointer dans le vide
    /// jusqu'au lancement suivant ; unitaire et groupé refusent de la même voix.
    func refuseTrashWhileGameRuns() -> Bool {
        guard isGameRunning() else { return false }
        showModal(message: localization.L(L10n.Mods.trashGameRunning))
        return true
    }

    /// Un seul événement de corbeille pour tout le lot (« Tout restaurer »
    /// le rend en bloc). Vrai si au moins un mod est parti : un refus garde la
    /// sélection de l'appelant.
    @discardableResult
    func trashMods(_ mods: [ModItem]) -> Bool {
        let plan = ModTrashSelection.plan(selected: mods, all: self.mods)
        guard !plan.trashable.isEmpty else { return false }
        if refuseDuringBenchmark() || refuseTrashWhileGameRuns() { return false }
        guard !gameDir.isEmpty else {
            showModal(message: localization.L(L10n.Settings.gameDirNotSet))
            return false
        }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let items = plan.trashable.map {
            ModTrash.Item(physical: $0.physicalFolderName,
                          logicalLeaf: ($0.folderName as NSString).lastPathComponent)
        }
        let result = ModTrash.trash(modsPath: modsPath, trashRoot: ModTrash.root(gameDir: gameDir),
                                    stamp: ModTrash.makeStamp(), items: items)
        let moved = Set(result.moved)
        // Une ligne par mod parti, comme le geste unitaire, puis le compte.
        for mod in plan.trashable where moved.contains(mod.physicalFolderName) {
            forgetStores(of: mod)
            log(String(format: localization.L(L10n.Mods.deletedLog), mod.name))
        }
        if !moved.isEmpty { log(localization.plural(L10n.Mods.trashSelectionLog, moved.count)) }
        let failed = ModTrashSelection.failures(plan.trashable, failed: result.failed)
        if !failed.isEmpty {
            let message = String(format: localization.L(L10n.Mods.trashSelectionFailed),
                                 "\n" + failed.joined(separator: "\n"))
            log(message, level: .error)
            showModal(message: message)
        }
        // Un seul rescan pour le lot, hors du fil principal (convention du
        // cliquet : pas de `DispatchQueue` neuve).
        Task { [weak self] in
            await self?.rescanInBackground()
            self?.syncActiveProfileIds()
        }
        return !moved.isEmpty
    }
}
