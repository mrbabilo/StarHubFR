import Foundation

/// P5-5a / P5-5b (audit UX 2026-10-16) — une archive déposée, sur la fenêtre
/// ou sur l'icône du Dock, prend le même chemin : même garde, même file
/// (`pendingDropQueue`), même feuille d'installation. Rien ne s'installe sans
/// la feuille.
extension StarHubTHViewModel {
    /// La raison de refuser un dépôt maintenant, ou `nil`.
    var archiveDropRefusal: ArchiveDropRefusal? {
        ArchiveDropRefusal.first(
            installOpen: pendingDropPresentation != nil || navigationStore.showsInstallSheet,
            downloadBusy: NexusDownloadFlow.isBusy(isDownloading: isDownloadingFromNexus,
                                                   hasPendingZip: pendingDownloadedZip != nil),
            profileApplying: isApplyingProfile,
            operations: modSetOperations)
    }

    /// Ouvre la feuille sur la première archive, ou rend le refus. Un lot
    /// sans rien d'ouvrable montre le premier fichier : la feuille dit pourquoi.
    @discardableResult
    func presentDroppedArchives(_ urls: [URL]) -> ArchiveDropRefusal? {
        if let refusal = archiveDropRefusal { return refusal }
        guard !urls.isEmpty else { return nil }
        let (archives, rejected) = ModZipInstaller.partitionDroppedFiles(urls)
        dropQueuePush(archives.isEmpty ? Array(rejected.prefix(1)) : archives)
        queueNextDropArchive()
        return nil
    }
}

extension StarHubTHViewModel {
    /// P5-5b — le Dock n'a pas de bandeau de survol : un refus se dit en
    /// message (« une installation est en cours… »), jamais en silence.
    func openDockArchives(_ urls: [URL], localization: LocalizationStore) {
        if let refusal = presentDroppedArchives(urls) { showModal(message: refusal.message(localization)) }
    }
}

extension ArchiveDropRefusal {
    func message(_ localization: LocalizationStore) -> String {
        switch self {
        case .installOpen: localization.L(L10n.ArchiveDrop.refusedInstallOpen)
        case .downloadBusy: localization.L(L10n.ArchiveDrop.refusedDownload)
        case .profileApplying: localization.L(L10n.ArchiveDrop.refusedProfile)
        case .operationRunning(let operation):
            String(format: localization.L(L10n.ArchiveDrop.refusedOperation), localization.name(of: operation))
        }
    }
}
