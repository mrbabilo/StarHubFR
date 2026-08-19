import SwiftUI

/// Le dialogue de pré-traduction par lot (tâche 14 du plan P2b, spec §7).
///
/// Trois temps : le récapitulatif avant lancement — on sait ce qui va être
/// traduit, avec quel modèle, et que chaque résultat sera marqué « À
/// relire » —, la progression avec l'arrêt coopératif, puis le rapport.
/// Fermer en cours de route ne perd rien : chaque résultat est persisté dès
/// qu'il arrive, avant tout le reste (spec §8.4).
struct TranslationBatchView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    let locale: String
    /// Les rangées à jour au moment de l'ouverture : le lot ne traite que
    /// ce qui reste (absent ou vide), jamais une valeur française existante.
    let rows: [TranslationCoverage.DiffRow]
    /// Appelée à la fermeture : le diff se rouvre cadré sur « À relire ».
    let onClose: () -> Void

    @State private var started = false

    private var eligible: [TranslationCoverage.DiffRow] {
        TranslationBatchPlanner.eligibleRows(rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !started {
                recap
            } else if let report = vm.batchReport {
                reportView(report)
            } else if let progress = vm.batchProgress {
                progressView(progress)
            } else {
                // Le lot vient d'être lancé : l'état n'est pas encore posé.
                ProgressView().controlSize(.small)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 180)
    }

    // MARK: - Avant lancement

    private var recap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: vm.L(L10n.Mods.translationBatchRecap),
                        Int64(eligible.count),
                        UserDefaults.standard.string(forKey: UDKey.localAIModel) ?? ""))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(vm.L(L10n.Mods.translationBatchCancel)) { onClose() }
                Button(vm.L(L10n.Mods.translationBatchButton)) {
                    started = true
                    vm.startBatch(mod: mod, locale: locale, rows: rows)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(eligible.isEmpty)
            }
        }
    }

    // MARK: - En cours

    private func progressView(_ progress: StarHubTHViewModel.BatchProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
            Text(String(format: vm.L(L10n.Mods.translationBatchProgress),
                        Int64(progress.done), Int64(progress.total)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button(vm.L(L10n.Mods.translationBatchCancel)) { vm.cancelBatch() }
            }
        }
    }

    // MARK: - Rapport

    private func reportView(_ report: StarHubTHViewModel.BatchReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: vm.L(L10n.Mods.translationBatchReport),
                        Int64(report.translated), Int64(report.refusedRowIDs.count),
                        Int64(report.errors)))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if report.softGlossaryIgnored > 0 {
                Text(String(format: vm.L(L10n.Mods.translationBatchSoftIgnored),
                            Int64(report.softGlossaryIgnored)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !report.refusedRowIDs.isEmpty {
                // Les clés refusées pour marques manquantes : c'est la liste
                // de ce qu'il reste à faire à la main, le rapport ne la
                // résume pas en un chiffre.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.refusedRowIDs.prefix(20), id: \.self) { id in
                        Text(id).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if report.refusedRowIDs.count > 20 {
                        Text("…").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button(vm.L(L10n.Mods.translationBatchClose)) { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
