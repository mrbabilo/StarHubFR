import SwiftUI

/// A1-T10 — la feuille de confirmation du nettoyage : les clés candidates,
/// l'avertissement backup, et un bouton destructif distinct d'« Annuler »
/// (défaut). Les clés viennent du scan en cache, filtrées sur les uids que
/// la section affiche — la liste montrée est celle de la section ; la
/// suppression, elle, recalcule sur le fichier au moment du geste
/// (`SaveCleanupStore`).
struct SaveCleanupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    /// La date qui a servi au scan de la section — même clé de cache.
    let modified: Date
    let mods: [ModItem]
    let uids: Set<String>
    let onCleaned: () -> Void

    @State private var store = SaveCleanupStore()
    @State private var candidats: [String: [String]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Saves.cleanupSheetTitle))
                .font(AppDesign.Font.headline)
                .lineLimit(2)
            Text(localization.L(L10n.Saves.cleanupSheetIntro))
                .font(AppDesign.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    ForEach(candidats.keys.sorted(), id: \.self) { uid in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uid)
                                .font(AppDesign.Font.monoCaption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ForEach(candidats[uid] ?? [], id: \.self) { clé in
                                Text(clé)
                                    .font(AppDesign.Font.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 280)

            footer
        }
        .padding(AppDesign.Spacing.lg)
        .frame(width: 460)
        .task { await chargerCandidats() }
        .interactiveDismissDisabled(store.phase == .enCours)
    }

    @ViewBuilder
    private var footer: some View {
        switch store.phase {
        case .idle:
            HStack {
                Spacer()
                Button(localization.L(L10n.Saves.cancel), role: .cancel) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                Button(localization.L(L10n.Saves.cleanupConfirm), role: .destructive) {
                    Task {
                        await store.nettoyer(save: save, mods: mods)
                        if case .terminé = store.phase { onCleaned() }
                    }
                }
            }
        case .enCours:
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.Saves.cleanupWorking))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        case .terminé(let supprimées, let laissées):
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text(String(format: localization.L(L10n.Saves.cleanupDone), supprimées))
                if laissées > 0 {
                    Text(String(format: localization.L(L10n.Saves.cleanupKept), laissées))
                        .font(AppDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
            closeRow
        case .échec(let raison):
            Text(texte(raison))
                .foregroundStyle(AppDesign.Color.error)
                .fixedSize(horizontal: false, vertical: true)
            closeRow
        }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button(localization.L(L10n.Saves.cleanupClose)) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func texte(_ raison: SaveCleanupStore.Raison) -> String {
        switch raison {
        case .backup: return localization.L(L10n.Saves.cleanupErrBackup)
        case .lecture: return localization.L(L10n.Saves.cleanupErrRead)
        case .écriture: return localization.L(L10n.Saves.cleanupErrWrite)
        case .aucuneClé: return localization.L(L10n.Saves.cleanupErrNone)
        }
    }

    /// Le scan est déjà en cache (la section vient de le lire) : pas de
    /// relecture des 37 Mo.
    private func chargerCandidats() async {
        guard let scan = await SaveFingerprintScanCache.shared.scan(
            folderName: save.folderName, modified: modified, url: save.fileURL)
        else { return }
        let prefixe = "smapi/mod-data/"
        var par: [String: [String]] = [:]
        for clé in scan.modDataKeys.keys where clé.hasPrefix(prefixe) {
            let uid = clé.dropFirst(prefixe.count).prefix { $0 != "/" }.lowercased()
            if uids.contains(uid) { par[uid, default: []].append(clé) }
        }
        candidats = par.mapValues { $0.sorted() }
    }
}
