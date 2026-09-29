import SwiftUI

/// « Ce qui a changé » (spec « Différences d'inventaire ») : mods ajoutés,
/// retirés, mis à jour, réglages modifiés (diff clé par clé quand les deux
/// contenus sont rangés), la sonde à part. Sans inventaire : le dire, jamais
/// « aucun changement ».
struct PerformanceChangesSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let report: ProbePerformanceReport
    let configsDirectory: URL

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.sectionChanges)).font(AppDesign.Font.headline(.semibold))
            if crossedAChange {
                Text(localization.L(L10n.Performance.crossedChange))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            if let diff = report.diff {
                if diff.probeChanged {
                    Text(localization.L(L10n.Performance.probeChanged))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                }
                if diff.changes.isEmpty {
                    Text(localization.L(L10n.Performance.noChange)).foregroundColor(.secondary)
                } else {
                    ForEach(diff.changes, id: \.modId) { change in row(change) }
                }
            } else {
                Text(localization.L(L10n.Performance.inventoryMissing)).foregroundColor(.secondary)
            }
        }
    }

    /// Une des deux mesures traversait une coupure (spec « Mesure propre »).
    private var crossedAChange: Bool {
        [report.before.kind, report.after.kind].contains {
            if case .measurement(_, let crossed) = $0 { return crossed != nil }
            return false
        }
    }

    @ViewBuilder
    private func row(_ change: ProbeModChange) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SplitRow {
                Text(name(change.modId))
                    .lineLimit(1).truncationMode(.middle)
                    .help(change.modId)
            } trailing: {
                Text(kindLabel(change.kind)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            if case .configChanged(let old, let new) = change.kind,
               let keys = ProbeInventoryDiffRule.configDiff(modId: change.modId, oldSha: old, newSha: new,
                                                            configsDirectory: configsDirectory) {
                ForEach(keys) { key in
                    Text(String(format: localization.L(L10n.Performance.changeConfigKey),
                                key.path, key.valueA ?? "—", key.valueB ?? "—"))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func kindLabel(_ kind: ProbeModChange.Kind) -> String {
        switch kind {
        case .added: return localization.L(L10n.Performance.changeAdded)
        case .removed: return localization.L(L10n.Performance.changeRemoved)
        case .versionChanged(let from, let to, _):
            return String(format: localization.L(L10n.Performance.changeVersion), from, to)
        case .configChanged: return localization.L(L10n.Performance.changeConfig)
        }
    }

    /// Le nom du manifeste quand le mod est installé, sinon l'identifiant.
    private func name(_ modId: String) -> String {
        viewModel.scanStore.mods.flattenedMods
            .first { $0.uniqueId.caseInsensitiveCompare(modId) == .orderedSame }?.name ?? modId
    }
}
