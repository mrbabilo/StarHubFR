import SwiftUI

/// A1-T11 — le journal local du mod dans sa fiche : chaque installation, mise
/// à jour, ajout et nettoyage, du plus récent au plus ancien. Lu hors du fil
/// principal (jusqu'à ~0,7 Mo par entrée sur les plus gros mods du parc).
struct ModHistorySection: View {
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    @State private var history: ModHistory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.L(L10n.ModHistory.title))
                .font(AppDesign.Font.footnote(.semibold))
            if let history {
                if history.entries.isEmpty {
                    Text(localization.L(L10n.ModHistory.empty))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(history.entries.reversed().enumerated()), id: \.offset) { _, entry in
                        ModHistoryEntryRow(localization: localization, entry: entry)
                    }
                }
            }
        }
        .task(id: mod.uniqueId) {
            let uniqueId = mod.uniqueId
            history = await Task.detached(priority: .utility) {
                ModHistoryFile.history(uniqueId: uniqueId, directory: ModHistoryFile.defaultDirectory())
            }.value
        }
    }
}

private struct ModHistoryEntryRow: View {
    @ObservedObject var localization: LocalizationStore
    let entry: ModHistory.Entry

    private static let shownFiles = 50

    private var kind: String {
        switch entry.kind {
        case .install: return localization.L(L10n.ModHistory.kindInstall)
        case .update: return localization.L(L10n.ModHistory.kindUpdate)
        case .addition: return localization.L(L10n.ModHistory.kindAddition)
        case .cleanup: return localization.L(L10n.ModHistory.kindCleanup)
        }
    }

    /// `1.4.1 → 1.4.2`, ou la seule version connue.
    private var versions: String? {
        switch (entry.fromVersion, entry.toVersion) {
        case let (from?, to?) where from != to: return "\(from) → \(to)"
        case let (_, to?): return to
        case let (from?, nil): return from
        case (nil, nil): return nil
        }
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if let report = entry.report, !report.isSilent {
                    UpdateTriageRows(localization: localization, report: report)
                }
                ForEach(entry.files.prefix(Self.shownFiles), id: \.path) { file in
                    Text(file.path)
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if entry.files.count > Self.shownFiles {
                    Text(String(format: localization.L(L10n.UpdateTriage.moreFiles),
                                entry.files.count - Self.shownFiles))
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)
        } label: {
            // Deux lignes plutôt qu'une : lisible à 560 pt (consigne du
            // 2026-09-25), la version et la source ne poussent pas la date.
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                        .font(AppDesign.Font.footnote)
                    Text(kind)
                        .font(AppDesign.Font.footnote(.semibold))
                    if let versions {
                        Text(versions)
                            .font(AppDesign.Font.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack(spacing: 6) {
                    Text(String(format: localization.L(L10n.ModHistory.fileCount), entry.files.count))
                    if let fileId = entry.nexusFileId {
                        Text(String(format: localization.L(L10n.ModHistory.nexusFile), fileId))
                    } else if let source = entry.source {
                        Text(source).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}
