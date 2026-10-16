import SwiftUI

/// Une version sauvegardée d'un `config.json` contre le fichier actuel, avant
/// de la restaurer (`ConfigBackupComparison`). Lecture seule.
struct ConfigBackupCompareSheet: View {
    @ObservedObject var localization: LocalizationStore
    let version: ConfigBackupBrowser.Version
    /// Le `config.json` actuel du mod ; `nil` s'il n'est plus installé.
    let currentURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: ConfigBackupComparison.Outcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: localization.L(L10n.ModConfigBackups.compareTitle),
                            version.item.modDisplayName, version.backup.formattedDate))
                    .font(AppDesign.Font.headline(.semibold))
                Text(localization.L(L10n.ModConfigBackups.compareNote))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            switch outcome {
            case nil: centered(Text("")).overlay(ProgressView())
            case .missing: centered(Text(localization.L(L10n.ModConfigBackups.compareMissing)))
            case .unparseable: centered(Text(localization.L(L10n.ModConfigBackups.compareUnparseable)))
            case .identical: centered(Text(localization.L(L10n.ModConfigBackups.compareIdentical)))
            case .differs(let diffs):
                ConfigDiffList(localization: localization, diffs: diffs,
                               nameA: localization.L(L10n.ModConfigBackups.sideBackup),
                               nameB: localization.L(L10n.ModConfigBackups.sideCurrent))
            }
            Divider()
            HStack {
                Spacer()
                Button(localization.L(L10n.Main.ok)) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 540)
        // Lu hors du fil principal : l'index des sauvegardes et deux fichiers.
        .task {
            let folder = version.item.modFolderName, id = version.backup.id, current = currentURL
            outcome = await Task.detached(priority: .userInitiated) {
                let backupURL = ModConfigBackupManager.shared.backedUpFiles(named: "config.json", forMod: folder)
                    .first { $0.backup.id == id }?.url
                return ConfigBackupComparison.compare(backup: Self.text(backupURL), current: Self.text(current))
            }.value
        }
    }

    private static func text(_ url: URL?) -> String? {
        guard let url else { return nil }
        do { return try String(contentsOf: url, encoding: .utf8) } catch { return nil }
    }

    private func centered(_ text: Text) -> some View {
        VStack {
            Spacer()
            text.font(AppDesign.Font.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
