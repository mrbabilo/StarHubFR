import SwiftUI

/// Le dernier rapport de réparation : quarantaine, doublons, et les dossiers
/// sans manifeste (« à voir », jamais déplacés) — une carte par section, que
/// les tuiles de `RepairReportSummary` atteignent par leur `id`.
/// Extraite du `body` de QuarantineView le 2026-09-10 : l'ajout de la
/// section a fait franchir au body le seuil de saturation du type-checker
/// (piège CLAUDE.md).
struct RepairReportCard: View {
    let report: ModFolderRepairer.Report
    @ObservedObject var localization: LocalizationStore
    let gameDir: String

    private struct DuplicateRow: Identifiable {
        let id: String
        let duplicate: ModFolderRepairer.Duplicate
    }

    private func duplicateRows(from duplicates: [ModFolderRepairer.Duplicate]) -> [DuplicateRow] {
        Array(duplicates.prefix(20).enumerated()).map { offset, dup in
            DuplicateRow(id: "\(offset)-\(dup.uniqueId)-\(dup.enabledFolder)-\(dup.disabledFolder)", duplicate: dup)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
            if report.quarantined.isEmpty && report.duplicates.isEmpty && report.reviewItems.isEmpty {
                Text(localization.L(L10n.Quarantine.noQuarantine))
                    .font(AppDesign.Font.body)
                    .foregroundColor(AppDesign.Color.secondary)
            }
            if !report.quarantined.isEmpty { quarantinedCard }
            if !report.duplicates.isEmpty { duplicatesCard }
            if !report.reviewItems.isEmpty { reviewCard }
        }
    }

    private var quarantinedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(format: localization.L(L10n.Quarantine.itemsQuarantined), Int64(report.quarantined.count)),
                systemImage: "tray.and.arrow.down.fill"
            )
            .font(AppDesign.Font.body)
            // Constat, pas panne : les éléments listés ici sont déjà
            // déplacés en lieu sûr. `.purple` distinguait visuellement
            // ce bloc du bloc doublons (`.orange`) qui, lui, réclame une
            // action ; `secondary` garde cette distinction sans réutiliser
            // `warning` (= `.orange`, cf. AppDesignUI) qui ferait « jurer »
            // les deux blocs en un seul signal.
            .foregroundColor(AppDesign.Color.secondary)

            // Identité par la valeur seule : `relativePath` est un chemin
            // disque réel, unique par construction dans un même rapport
            // (repairFolder + sweepJunkInsideMods ne peuvent pas produire
            // deux Item pour le même fichier physique — cf. rapport de
            // tâche). `id: \.offset` ferait fuiter l'@State d'une ligne
            // vers une autre au prochain scan (piège CLAUDE.md §SwiftUI).
            ForEach(Array(report.quarantined.prefix(20).enumerated()), id: \.element.relativePath) { _, item in
                HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
                    Image(systemName: "archivebox.fill")
                        // Pas de `.opacity(0.7)` supplémentaire ici :
                        // `secondary` est déjà une couleur hiérarchique
                        // atténuée (~0.5 alpha) — la multiplier aurait
                        // rendu ce glyphe de 10pt quasi invisible.
                        .foregroundColor(AppDesign.Color.secondary)
                        .font(AppDesign.Font.iconXS)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.relativePath)
                            .font(AppDesign.Font.monoCaption)
                            .foregroundColor(AppDesign.Color.primary)
                        Text(item.reason)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(AppDesign.Color.secondary)
                    }
                }
            }
            if report.quarantined.count > 20 {
                Text(String(format: localization.L(L10n.Quarantine.andNMore), Int64(report.quarantined.count - 20)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id(RepairReportSection.quarantined)
    }

    private var duplicatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(format: localization.L(L10n.Quarantine.duplicatesFound), Int64(report.duplicates.count)),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(AppDesign.Font.body)
            // Vrai avertissement, à la différence du bloc quarantine
            // ci-dessus : un doublon d'UniqueID n'est pas auto-résolu,
            // il attend une décision de l'utilisateur.
            .foregroundColor(AppDesign.Color.warning)

            // `Duplicate` n'est pas garanti unique par la valeur : un
            // pack livrant deux manifest.json sous le même UniqueID et
            // le même dossier désactivé produit deux `Duplicate`
            // identiques (uniqueId + enabledFolder + disabledFolder).
            // Contrairement à `quarantined` (chemin disque réel, donc
            // unique), la valeur seule collisionnerait ici — d'où le
            // rang ajouté au contenu (`DuplicateRow`), jamais le rang
            // seul (id: \.offset fuiterait l'@State au prochain scan).
            ForEach(duplicateRows(from: report.duplicates)) { row in
                HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(AppDesign.Color.warning.opacity(0.7))
                        .font(AppDesign.Font.iconXS)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.duplicate.uniqueId)
                            .font(AppDesign.Font.monoCaption)
                            .foregroundColor(AppDesign.Color.primary)
                        Text("\(row.duplicate.enabledFolder)  ⇄  \(row.duplicate.disabledFolder)")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(AppDesign.Color.secondary)
                    }
                }
            }
            if report.duplicates.count > 20 {
                Text(String(format: localization.L(L10n.Quarantine.andNMore), Int64(report.duplicates.count - 20)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id(RepairReportSection.duplicates)
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Constat, pas intervention : ces dossiers n'ont
            // PAS été déplacés — la section les montre pour
            // ce qu'ils sont, l'action reste à l'utilisateur.
            Label(
                localization.L(L10n.Quarantine.reviewTitle),
                systemImage: "folder.badge.questionmark"
            )
            .font(AppDesign.Font.body(.semibold))
            .foregroundColor(AppDesign.Color.primary)

            Text(localization.L(L10n.Quarantine.reviewNote))
                .font(AppDesign.Font.footnote)
                .foregroundColor(AppDesign.Color.secondary)

            ForEach(report.reviewItems, id: \.relativePath) { item in
                HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
                    Image(systemName: "folder")
                        .foregroundColor(AppDesign.Color.secondary)
                        .font(AppDesign.Font.iconXS)
                        .padding(.top, 2)
                    Text(item.relativePath)
                        .font(AppDesign.Font.monoCaption)
                        .foregroundColor(AppDesign.Color.primary)
                    Spacer()
                    Button(localization.L(L10n.ModInstall.revealInFinder)) {
                        let full = URL(fileURLWithPath: gameDir)
                            .appendingPathComponent("Mods")
                            .appendingPathComponent(item.relativePath)
                        NSWorkspace.shared.activateFileViewerSelecting([full])
                    }
                    .buttonStyle(.link)
                    .font(AppDesign.Font.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id(RepairReportSection.review)
    }
}

/// Les trois sections du rapport, cibles de défilement des tuiles.
enum RepairReportSection: Hashable { case quarantined, duplicates, review }

/// Trois chiffres en tête du rapport — mis à l'écart, doublons, à voir —
/// chacun menant à sa carte. Un compte nul reste affiché, éteint : « rien
/// en quarantaine » est une information.
struct RepairReportSummary: View {
    let report: ModFolderRepairer.Report
    @ObservedObject var localization: LocalizationStore
    let onSelect: (RepairReportSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Quarantine.lastRepair))
                .font(AppDesign.Font.caption(.semibold))
                .foregroundStyle(.secondary)
            WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
                tile(.quarantined, icon: "tray.and.arrow.down.fill", label: L10n.Quarantine.tileQuarantined,
                     count: report.quarantined.count, tint: AppDesign.Color.accent)
                tile(.duplicates, icon: "doc.on.doc.fill", label: L10n.Quarantine.tileDuplicates,
                     count: report.duplicates.count, tint: AppDesign.Color.warning)
                tile(.review, icon: "folder.badge.questionmark", label: L10n.Quarantine.tileReview,
                     count: report.reviewItems.count, tint: AppDesign.Color.info)
            }
        }
    }

    private func tile(_ section: RepairReportSection, icon: String, label: String,
                      count: Int, tint: Color) -> some View {
        MetricTile(icon: icon, value: count, label: localization.L(label), tint: tint,
                   help: count > 0 ? localization.L(L10n.Quarantine.tileHint) : nil) {
            onSelect(section)
        }
        .disabled(count == 0)
    }
}
