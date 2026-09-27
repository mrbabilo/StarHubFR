import SwiftUI

// A1-T11 — ce que l'installation fait du tri par provenance, du journal local
// et des originaux de traduction. Sorti de `ModInstallView.swift`, dont la
// taille est verrouillée par le cliquet : `performInstall` n'y gagne que trois
// appels.
extension ModInstallView {
    /// Le fournisseur du tri, construit sur le fil principal avant l'envoi en
    /// file de fond : le registre des traductions et les identifiants Nexus
    /// saisis à la main y sont figés.
    func makeTriageProvider(archive: URL?) -> UpdateTriageProvider {
        UpdateTriageSession.provider(translations: vm.installedTranslations,
                                     customNexusIds: vm.nexusCustomModIds,
                                     archive: archive)
    }

    /// Sur le fil principal, après l'installation : les échecs du journal et du
    /// rebasage sont dits (jamais bloquants — l'installation a réussi), les
    /// originaux de traduction que l'auteur ne livre plus sortent du registre,
    /// qui est réécrit.
    func finishTriage(historyFailures: [String],
                      rebase: (dropped: [String: Set<String>], failed: [String])) {
        for uniqueId in historyFailures {
            vm.log(String(format: localization.L(L10n.ModHistory.writeFailed), uniqueId), level: .warning)
        }
        if !rebase.failed.isEmpty {
            vm.log(String(format: localization.L(L10n.ModHistory.originalsFailed),
                          rebase.failed.joined(separator: ", ")), level: .warning)
        }
        guard !rebase.dropped.isEmpty else { return }
        vm.translationHub.mutateInstalled { registry in
            for (host, relatives) in rebase.dropped {
                registry.forgetReplacedOriginals(relatives, host: host)
            }
        }
        if !InstalledTranslationStore.save(vm.installedTranslations) {
            vm.log(localization.L(L10n.ModHistory.registryNotSaved), level: .warning)
        }
    }
}
