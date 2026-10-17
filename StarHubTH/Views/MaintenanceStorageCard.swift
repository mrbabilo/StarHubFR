import SwiftUI

/// La carte de tête de l'Entretien : ce que StarHubFR occupe, sa répartition,
/// et les trois crans de purge — le chiffre qu'on vient voir et le geste qui
/// le réduit, ensemble (audit UX 2026-10-02).
///
/// Le gain annoncé vient de `report.freedBytes` — le même chemin que la
/// purge : un chiffre qui divergerait de ce qui part serait un mensonge.
struct MaintenanceStorageCard: View {
    let report: MaintenanceInventory.Report
    @ObservedObject var localization: LocalizationStore
    /// Cran choisi : combien garder par mod, entrées condamnées, poids libéré.
    let onPurge: (_ keepPerMod: Int, _ doomed: Int, _ freedBytes: Int64) -> Void
    /// R1 — la légende mène au segment de Sauvegardes qu'elle chiffre.
    var openBackups: (BackupsSegment) -> Void = { _ in }

    /// Parts d'un même total (C2b) : le rose se lisait comme une erreur, les
    /// violets `Chart.part*` ne se lisaient pas ici (vu à l'écran). L'accent,
    /// en deux intensités.
    private static let installTint = AppDesign.Color.accent
    private static let configTint = AppDesign.Color.accent.opacity(0.4)

    /// Le cran choisi (E11) ; replié sur le premier qui libère quelque chose.
    @State private var keep = 1

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            HStack(alignment: .center, spacing: AppDesign.Spacing.md) {
                IconTile(icon: "internaldrive", tint: AppDesign.Color.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(localization.L(L10n.Maintenance.total))
                        .font(AppDesign.Font.caption(.semibold))
                        .foregroundStyle(.secondary)
                    Text(SharedFormatters.bytes(report.totalBytes))
                        .font(.system(size: AppDesign.Font.scaled(28), weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            if report.backupBytes + report.configBackupBytes > 0 { bar }
            VStack(alignment: .leading, spacing: 3) {
                row(localization.L(L10n.Maintenance.installBackups),
                    "\(report.backups.count) · \(SharedFormatters.bytes(report.backupBytes))", dot: Self.installTint, open: .install)
                row(localization.L(L10n.Maintenance.configBackups),
                    "\(report.configBackupCount) · \(SharedFormatters.bytes(report.configBackupBytes))", dot: Self.configTint, open: .config)
                if !report.orphanSessions.isEmpty {
                    row(localization.L(L10n.Maintenance.orphanSessions), String(report.orphanSessions.count), dot: nil)
                }
                if !report.stalePreferenceKeys.isEmpty {
                    row(localization.L(L10n.Maintenance.staleKeys), String(report.stalePreferenceKeys.count), dot: nil)
                }
            }
            .font(AppDesign.Font.caption)
            .foregroundColor(.secondary)

            Divider()

            Text(localization.L(L10n.Maintenance.freeSpaceTitle))
                .font(AppDesign.Font.body(.semibold))
            // R1 — la règle automatique, dite comme dans Sauvegardes, puis ce
            // que le geste manuel ajoute.
            Text(BackupRetentionSummary.automatic(localized: localization.L) + " "
                 + localization.L(L10n.Maintenance.retentionManual))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // E11 — un seul geste de corbeille : choisir le cran, puis un
            // bouton. Un cran qui ne libère rien n'est pas proposé.
            let crans = [1, 3, 5].filter { report.freedBytes(keepPerMod: $0) > 0 }
            if let chosen = crans.contains(keep) ? keep : crans.first {
                WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
                    Picker(localization.L(L10n.Maintenance.keepPicker), selection: Binding(get: { chosen }, set: { keep = $0 })) {
                        ForEach(crans, id: \.self) { cran in
                            Text(String(format: localization.L(L10n.Maintenance.keepPerMod),
                                        cran, SharedFormatters.bytes(report.freedBytes(keepPerMod: cran)))).tag(cran)
                        }
                    }
                    .labelsHidden().fixedSize().controlSize(.small)
                    Button(String(format: localization.L(L10n.Maintenance.trashChosen),
                                  SharedFormatters.bytes(report.freedBytes(keepPerMod: chosen)))) {
                        let plan = MaintenanceInventory.plan(keepPerMod: chosen, entries: report.backups,
                                                             protections: report.protections)
                        onPurge(chosen, plan.doomed.count, plan.freedBytes)
                    }
                    .buttonStyle(.bordered).focusRing(cornerRadius: 5)
                    .controlSize(.small)
                }
            } else {
                StateCard(icon: "checkmark.circle", text: localization.L(L10n.Maintenance.nothingToFree),
                          actionTitle: nil) {}
            }
            Text(localization.L(L10n.Maintenance.trashHint))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Installations et configurations, en proportion du total. Décorative :
    /// les lignes dessous portent les chiffres.
    private var bar: some View {
        let total = max(report.backupBytes + report.configBackupBytes, 1)
        return GeometryReader { proxy in
            // L'écart ne sépare que deux segments présents : sinon il déborde.
            HStack(spacing: report.backupBytes > 0 && report.configBackupBytes > 0 ? 2 : 0) {
                Self.installTint
                    .frame(width: proxy.size.width * CGFloat(report.backupBytes) / CGFloat(total))
                Self.configTint
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, dot: Color?, open segment: BackupsSegment? = nil) -> some View {
        let line = HStack(spacing: AppDesign.Spacing.xs) {
            Circle()
                .fill(dot ?? .clear)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
            if segment != nil { Image(systemName: "chevron.right").font(AppDesign.Font.iconXS) }
        }
        if let segment {
            Button { openBackups(segment) } label: { line.contentShape(Rectangle()) }
                .buttonStyle(.plain).focusRing(cornerRadius: 4)
                .pointingHandCursor()
        } else {
            line
        }
    }
}
