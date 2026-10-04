import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// E2-T1 — l'export du rapport de la liste de mods, dans l'en-tête de
/// l'onglet « Santé » (slot `trailing` du `PageHeader`) : toujours à
/// l'écran, là où la section de bas de page était repoussée sous le pli par
/// la carte Santé pleine hauteur (retour d'écran du 2026-10-04). Un bouton
/// menu : les libellés FR complets ne tiennent pas dans un en-tête.
/// Markdown compact au presse-papiers (à coller dans un fil de discussion),
/// HTML complet au panneau d'enregistrement (à archiver ou joindre).
///
/// Toutes les données sont déjà en mémoire au ViewModel — la même anomalie que
/// la liste (`vm.anomaly`), la couverture FR connue, les surcharges d'identifiant
/// Nexus ; aucun accès réseau, aucune lecture de plus. Le calcul est synchrone
/// au clic, comme l'export du rapport de raccourcis : ~un millier de lignes
/// d'opérations dictionnaires, et le panneau modal bloque de toute façon.
struct ModlistReportMenu: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    private func collectEntries() -> [ModlistReport.Entry] {
        ModlistReport.collect(
            mods: vm.mods,
            history: vm.modErrorHistory,
            dependencyIssue: { vm.hasDependencyIssue($0) },
            duplicates: vm.scanStore.duplicateIndex,
            compatibility: vm.compatibilityStatuses,
            coverage: vm.frenchCoverageByMod,
            nexusId: { vm.nexusCustomModIds[$0.folderName] })
    }

    var body: some View {
        Menu {
            Button(localization.L(L10n.Logs.modlistReportCopy), action: copyReport)
            Button(localization.L(L10n.Logs.modlistReportSave), action: saveReport)
        } label: {
            Label(localization.L(L10n.Logs.modlistReportMenu),
                  systemImage: "doc.text")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
    }

    private func copyReport() {
        let text = ModlistReport.compact(entries: collectEntries(), generatedAt: Date())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        vm.log("Rapport de la liste de mods copié (\(vm.mods.count) mods).", level: .info)
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "starhubfr-modlist-\(DateFormatter.posixStamp()).html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = ModlistReport.html(entries: collectEntries(), generatedAt: Date())
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            vm.log("Rapport de la liste de mods exporté : \(url.lastPathComponent)", level: .info)
        } catch {
            vm.log("Export du rapport impossible : \(error.localizedDescription)", level: .warning)
        }
    }
}
