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

    private static let installTint = Color.pink
    private static let configTint = AppDesign.Color.accent

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
                    "\(report.backups.count) · \(SharedFormatters.bytes(report.backupBytes))", dot: Self.installTint)
                row(localization.L(L10n.Maintenance.configBackups),
                    "\(report.configBackupCount) · \(SharedFormatters.bytes(report.configBackupBytes))", dot: Self.configTint)
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
            WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
                ForEach([1, 3, 5], id: \.self) { keep in
                    let freed = report.freedBytes(keepPerMod: keep)
                    Button {
                        let plan = MaintenanceInventory.plan(keepPerMod: keep,
                                                             entries: report.backups,
                                                             protections: report.protections)
                        onPurge(keep, plan.doomed.count, plan.freedBytes)
                    } label: {
                        Text(String(format: localization.L(L10n.Maintenance.keepPerMod),
                                    keep, SharedFormatters.bytes(freed)))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(freed <= 0)
                }
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

    private func row(_ label: String, _ value: String, dot: Color?) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Circle()
                .fill(dot ?? .clear)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
