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
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// `dismissWindow`, pas `dismiss` : sur une racine de scène, `dismiss`
    /// n'est pas garanti de viser la fenêtre, et il échouerait sans bruit —
    /// exactement le défaut qu'on corrige ici. `dismissWindow(id:)` nomme
    /// sa cible.
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let report = vm.pendingInstallReport {
                ReportContent(vm: vm, localization: localization, report: report)
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
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
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
                                .font(AppDesign.Font.footnote(.bold))
                                .foregroundColor(.green)
                            Text(name)
                                .font(AppDesign.Font.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                    // A1-T7 — avant les deltas : ce qui touche aux parties
                    // sauvegardées passe avant ce qui touche aux réglages.
                    if !report.preserved.isEmpty {
                        Divider()
                        Text(localization.L(L10n.InstallReport.dataSection))
                            .font(AppDesign.Font.body(.semibold))
                        ForEach(Array(report.preserved.enumerated()),
                                id: \.offset) { _, outcome in
                            PreservedRow(localization: localization, outcome: outcome)
                        }
                    }
                    if !report.deltas.isEmpty {
                        Divider()
                        ForEach(report.deltas, id: \.folderName) { delta in
                            DeltaRow(vm: vm, localization: localization, delta: delta)
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

    private var summary: InstallReportSummary {
        InstallReportSummary.of(report.deltas, preserved: report.preserved)
    }

    private var summaryParts: [String] {
        var parts: [String] = []
        if summary.modsUpdated > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryMods), summary.modsUpdated))
        }
        if summary.translationTodo > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryTranslation), summary.translationTodo))
        }
        if summary.configChanges > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryConfig), summary.configChanges))
        }
        if summary.renamesSuggested > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryRenames), summary.renamesSuggested))
        }
        // A1-T7 — les données du mod que la mise à jour a rendues. Les échecs
        // ont leur propre part : ce sont les seuls qui appellent un geste.
        if summary.dataRestored > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryDataRestored),
                                summary.dataRestored))
        }
        if summary.dataFailed > 0 {
            parts.append(String(format: localization.L(L10n.InstallReport.summaryDataFailed),
                                summary.dataFailed))
        }
        return parts
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: AppDesign.Font.scaled(28)))
                    .foregroundColor(.green)
                Text(localization.L(summary.modsUpdated > 0
                          ? L10n.InstallReport.titleUpdate
                          : L10n.InstallReport.titleInstall))
                    .font(.system(size: AppDesign.Font.scaled(18), weight: .semibold))
            }
            if !summaryParts.isEmpty {
                Text(summaryParts.joined(separator: " · "))
                    .font(AppDesign.Font.body)
                    .foregroundColor(.secondary)
                    // Le pire cas FR fait ~1 100 px pour une fenêtre large de
                    // 520 : sans ceci la ligne se tronque, et ce sont les
                    // fragments de fin — les données du mod, A1-T7 — qui
                    // disparaissent en premier. Elle s'enroule désormais.
                    .fixedSize(horizontal: false, vertical: true)
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
                Button(String(format: localization.L(L10n.InstallReport.nextArchive),
                              report.remainingInQueue)) {
                    // L'archive suivante repart dans la feuille — par le
                    // canal SANS discard : fichier original de l'utilisateur.
                    vm.queueNextDropArchive()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(localization.L(L10n.InstallReport.done)) {
                    vm.dismissInstallReport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction) // I-T5 : Entrée conclut le bilan
                .controlSize(.large)
            }
        }
        .padding(AppDesignCore.Spacing.lg)
    }
}

/// La ligne de delta C2-T4 — même logique que l'ancien `updateDeltaRow` de
/// la feuille (compteurs non nuls joints par « · »), sans refermer quoi que
/// ce soit : la fenêtre de bilan reste ouverte.
/// A1-T7 — ce qu'une mise à jour a rendu à **un** mod.
///
/// Deux lignes possibles et indépendantes : ce qui est revenu (une bonne
/// nouvelle, discrète) et ce qui n'a pas pu revenir (une consigne, appuyée).
/// La seconde **nomme les fichiers** — sans eux l'utilisateur ne sait pas quoi
/// aller chercher dans la sauvegarde d'installation.
private struct PreservedRow: View {
    @ObservedObject var localization: LocalizationStore
    let outcome: PreservedDataOutcome

    /// Au-delà de six noms la liste cesse d'informer et pousse le reste du
    /// bilan hors de l'écran ; le compte, lui, reste exact sur la ligne.
    private var shownFailures: ArraySlice<String> { outcome.failed.prefix(6) }
    private var shownPaths: ArraySlice<String> { outcome.paths.prefix(6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if outcome.restored > 0 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: localization.L(L10n.InstallReport.dataRestoredRow),
                                    outcome.modFolder, outcome.restored))
                            .font(AppDesign.Font.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        // A1-T7 (suite) — nommer ce qui a été remis, pas
                        // seulement le compter.
                        ForEach(Array(shownPaths.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(AppDesign.Font.monoFootnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
            }
            if outcome.skipped > 0 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.orange)
                    Text(String(format: localization.L(L10n.InstallReport.dataSkippedRow),
                                outcome.modFolder, outcome.skipped))
                        .font(AppDesign.Font.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            if !outcome.failed.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: localization.L(L10n.InstallReport.dataFailedRow),
                                    outcome.modFolder, outcome.failed.count))
                            .font(AppDesign.Font.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(shownFailures.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(AppDesign.Font.monoFootnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct DeltaRow: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let delta: ModUpdateKeyDelta

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text((delta.folderName as NSString).lastPathComponent)
                    .font(AppDesign.Font.body(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(parts.joined(separator: " · "))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(localization.L(L10n.Mods.updateDeltaOpenDetail)) {
                vm.openReportDetail(for: delta.folderName)
            }
            .buttonStyle(.link)
            .font(AppDesign.Font.caption)
        }
    }

    private var parts: [String] {
        var parts: [String] = []
        if let added = delta.config?.added.count, added > 0 {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaConfigAdded), added))
        }
        if let removed = delta.config?.removed.count, removed > 0 {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaConfigRemoved), removed))
        }
        if !delta.translation.addedUntranslated.isEmpty {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaTranslationTodo),
                                delta.translation.addedUntranslated.count))
        }
        if !delta.translation.addedAuthorTranslated.isEmpty {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaTranslationAuthor),
                                delta.translation.addedAuthorTranslated.count))
        }
        if !delta.translation.removedKeys.isEmpty {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaTranslationOrphan),
                                delta.translation.removedKeys.count))
        }
        let renamed = KeyRenameMatcher.pairsByValue(old: delta.translation.removedKeys,
                                                    new: delta.translation.addedUntranslated)
        if !renamed.isEmpty {
            parts.append(String(format: localization.L(L10n.Mods.updateDeltaRenamedSuffix), renamed.count))
        }
        return parts
    }
}
