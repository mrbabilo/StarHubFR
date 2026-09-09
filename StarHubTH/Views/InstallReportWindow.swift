import SwiftUI

/// Les identifiants de scène de l'app. Chacun est employé à trois endroits
/// au moins — déclaration, ouverture, fermeture — et une faute de frappe y
/// échoue **en silence** : `openWindow`/`dismissWindow` sur un identifiant
/// inconnu ne font rien. Même raison d'être que `UDKey`.
enum AppWindowID {
    static let main = "main"
    static let installReport = "installReport"
}

/// La fenêtre de bilan post-installation — redimensionnable, là où l'écran
/// de succès interne de la feuille vivait. Les données sont l'`InstallReport`
/// figé par le ViewModel : un rafraîchissement du parc pendant la lecture ne
/// fait rien bouger à l'écran. Réouverture idempotente : `openWindow` sur une
/// fenêtre déjà ouverte l'amène au premier plan et le contenu se remplace.
struct InstallReportWindow: View {
    @ObservedObject var vm: StarHubTHViewModel
    /// `dismissWindow`, pas `dismiss` : sur une racine de scène, `dismiss`
    /// n'est pas garanti de viser la fenêtre, et il échouerait sans bruit —
    /// exactement le défaut qu'on corrige ici. `dismissWindow(id:)` nomme
    /// sa cible.
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let report = vm.pendingInstallReport {
                ReportContent(vm: vm, report: report)
            } else {
                // Fenêtre ouverte sans bilan (fermeture en cours) : ne rien
                // montrer plutôt qu'un état fantôme.
                Text("")
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        // Vider le bilan ne fermait PAS la fenêtre : « Terminé » laissait une
        // fenêtre blanche à refermer à la main, et « Archive suivante » la
        // laissait flotter derrière la feuille rouverte. Un seul point de
        // fermeture, pour les deux boutons.
        .onChange(of: vm.pendingInstallReport) { _, report in
            if report == nil { dismissWindow(id: AppWindowID.installReport) }
        }
        // Fermeture au bouton rouge, bilan encore posé : le lot est abandonné,
        // le reste de la file part avec lui. Les deux boutons, eux, passent
        // par `onChange` ci-dessus avec un report déjà nil — ils n'arrivent
        // jamais ici avec du travail en attente.
        .onDisappear {
            if vm.pendingInstallReport != nil { vm.abandonInstallReport() }
        }
    }
}

private struct ReportContent: View {
    @ObservedObject var vm: StarHubTHViewModel
    let report: InstallReport

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Identité par position assumée ICI seulement : la liste
                    // est figée (InstallReport immuable), jamais mutée en
                    // place — deux mods peuvent porter le même nom
                    // d'affichage, `id: \.self` avertirait sur des doublons.
                    ForEach(Array(report.installedNames.enumerated()),
                            id: \.offset) { _, name in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                            Text(name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                    if !report.deltas.isEmpty {
                        Divider()
                        ForEach(report.deltas, id: \.folderName) { delta in
                            DeltaRow(vm: vm, delta: delta)
                        }
                    }
                }
                .padding(AppDesignCore.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
    }

    private var summary: InstallReportSummary { InstallReportSummary.of(report.deltas) }

    private var summaryParts: [String] {
        var parts: [String] = []
        if summary.modsUpdated > 0 {
            parts.append(String(format: vm.L(L10n.InstallReport.summaryMods), summary.modsUpdated))
        }
        if summary.translationTodo > 0 {
            parts.append(String(format: vm.L(L10n.InstallReport.summaryTranslation), summary.translationTodo))
        }
        if summary.configChanges > 0 {
            parts.append(String(format: vm.L(L10n.InstallReport.summaryConfig), summary.configChanges))
        }
        if summary.renamesSuggested > 0 {
            parts.append(String(format: vm.L(L10n.InstallReport.summaryRenames), summary.renamesSuggested))
        }
        return parts
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
                Text(vm.L(summary.modsUpdated > 0
                          ? L10n.InstallReport.titleUpdate
                          : L10n.InstallReport.titleInstall))
                    .font(.system(size: 18, weight: .semibold))
            }
            if !summaryParts.isEmpty {
                Text(summaryParts.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if report.remainingInQueue > 0 {
                Button(String(format: vm.L(L10n.InstallReport.nextArchive),
                              report.remainingInQueue)) {
                    // L'archive suivante repart dans la feuille — par le
                    // canal SANS discard : fichier original de l'utilisateur.
                    vm.queueNextDropArchive()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(vm.L(L10n.InstallReport.done)) {
                    vm.dismissInstallReport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(AppDesignCore.Spacing.lg)
    }
}

/// La ligne de delta C2-T4 — même logique que l'ancien `updateDeltaRow` de
/// la feuille (compteurs non nuls joints par « · »), sans refermer quoi que
/// ce soit : la fenêtre de bilan reste ouverte.
private struct DeltaRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let delta: ModUpdateKeyDelta

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text((delta.folderName as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(vm.L(L10n.Mods.updateDeltaOpenDetail)) {
                vm.openReportDetail(for: delta.folderName)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
    }

    private var parts: [String] {
        var parts: [String] = []
        if let added = delta.config?.added.count, added > 0 {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaConfigAdded), added))
        }
        if let removed = delta.config?.removed.count, removed > 0 {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaConfigRemoved), removed))
        }
        if !delta.translation.addedUntranslated.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationTodo),
                                delta.translation.addedUntranslated.count))
        }
        if !delta.translation.addedAuthorTranslated.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationAuthor),
                                delta.translation.addedAuthorTranslated.count))
        }
        if !delta.translation.removedKeys.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationOrphan),
                                delta.translation.removedKeys.count))
        }
        let renamed = KeyRenameMatcher.pairsByValue(old: delta.translation.removedKeys,
                                                    new: delta.translation.addedUntranslated)
        if !renamed.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaRenamedSuffix), renamed.count))
        }
        return parts
    }
}
