import SwiftUI

/// A1-T11 — ce qu'un tri a fait des fichiers d'un mod, ligne par catégorie
/// non vide. Partagé par le bilan d'installation et le journal de la fiche.
struct UpdateTriageRows: View {
    @ObservedObject var localization: LocalizationStore
    let report: UpdateTriageReport

    /// Au-delà de six noms la liste cesse d'informer (même borne que le bilan
    /// A1-T7) ; le compte, lui, reste exact.
    private static let shown = 6

    private struct Line: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let text: String
        let paths: [String]
    }

    private var lines: [Line] {
        var out: [Line] = []
        func add(_ key: String, _ icon: String, _ color: Color, _ paths: [String]) {
            guard !paths.isEmpty else { return }
            out.append(Line(id: key, icon: icon, color: color,
                            text: String(format: localization.L(key), paths.count), paths: paths))
        }
        add(L10n.UpdateTriage.ghosts, "trash", .secondary, report.removedGhosts)
        add(L10n.UpdateTriage.retouches, "paintbrush", .green, report.keptRetouches)
        add(L10n.UpdateTriage.authorChanged, "exclamationmark.circle", .orange, report.retouchesAuthorChanged)
        add(L10n.UpdateTriage.content, "exclamationmark.triangle.fill", .orange, report.contentRetouches)
        add(L10n.UpdateTriage.structural, "arrow.triangle.2.circlepath", .orange, report.replacedStructural)
        add(L10n.UpdateTriage.unverified, "questionmark.circle", .orange, report.replacedUnverified)
        add(L10n.UpdateTriage.unverifiedTranslations, "character.bubble", .secondary,
            report.keptUnverifiedTranslations)
        add(L10n.UpdateTriage.deposits, "tray.and.arrow.down", .secondary, report.keptDeposits)
        add(L10n.UpdateTriage.nowShips, "arrow.left.arrow.right", .orange, report.authorNowShips)
        add(L10n.UpdateTriage.deletions, "minus.circle", .secondary, report.respectedDeletions)
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if report.nexusIncomplete {
                row(icon: "wifi.exclamationmark", color: .orange,
                    text: localization.L(L10n.UpdateTriage.nexusIncomplete), paths: [])
            }
            ForEach(lines) { line in
                row(icon: line.icon, color: line.color, text: line.text, paths: line.paths)
            }
        }
    }

    private func row(icon: String, color: Color, text: String, paths: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(AppDesign.Font.footnote)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(AppDesign.Font.caption)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(paths.prefix(Self.shown).enumerated()), id: \.offset) { _, path in
                    Text(path)
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if paths.count > Self.shown {
                    Text(String(format: localization.L(L10n.UpdateTriage.moreFiles), paths.count - Self.shown))
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
