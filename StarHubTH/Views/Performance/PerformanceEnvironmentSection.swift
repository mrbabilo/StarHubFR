import SwiftUI

/// D2-T3 §5 — la carte « Environnement » : l'état statique qui explique les
/// mesures — config SLO résolue, mods configurables en jeu, poids des packs
/// Content Patcher. Toujours visible : elle ne dépend ni des sélecteurs
/// Avant/Après ni de la présence de la sonde.
struct PerformanceEnvironmentSection: View {
    @ObservedObject var localization: LocalizationStore
    var store: SessionEnvironmentStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            switch store.status {
            case .idle, .loading:
                // La carte garde sa hauteur de titre : jamais de saut de layout.
                header(dateText: nil)
                ProgressView().controlSize(.small)
            case .ready:
                if let report = store.report {
                    header(dateText: report.journalDate?
                        .formatted(date: .abbreviated, time: .shortened))
                    contents(report)
                } else {
                    header(dateText: nil)
                    Text(localization.L(L10n.Performance.envJournalMissing))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                }
            }
        }
    }

    private func header(dateText: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(L10n.Performance.envTitle))
                .font(AppDesign.Font.headline(.semibold))
            if let dateText {
                // Le journal reflète la session passée, le scan voit le disque
                // maintenant : la date dit laquelle des deux on lit (spec §7).
                Text(String(format: localization.L(L10n.Performance.envJournalDate), dateText))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func contents(_ report: SessionEnvironmentReport) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            sloSection(report.slo)
            menusSection(report.menus)
            packsSection(report)
        }
    }

    // MARK: - SLO

    @ViewBuilder
    private func sloSection(_ slo: SloOptimizerConfig?) -> some View {
        // Nom propre de mod : identique en/fr, pas de clé L10n.
        Text("Stardew Loading Optimizer").font(AppDesign.Font.headline(.semibold))
        if let slo {
            if let profile = slo.profile {
                Text(String(format: localization.L(L10n.Performance.envSloProfile), profile))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            // Tri stable : les optimisations connues d'abord, le reste alphabétique.
            let known = ["backgroundMapPreparation", "backgroundImagePreparation",
                         "fastWarp", "deferredTileSheets"]
            let names = slo.optimizations.keys.sorted {
                (known.firstIndex(of: $0) ?? known.count, $0)
                    < (known.firstIndex(of: $1) ?? known.count, $1)
            }
            ForEach(names, id: \.self) { name in
                optRow(name, slo.optimizations[name])
            }
            cacheLimits(slo.raw)
        } else {
            Text(localization.L(L10n.Performance.envSloAbsent))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
        }
    }

    /// Spec §5 : les limites de cache **repliées** — bruit technique, mais
    /// disponible (`imageCacheLimit=512 MB` vit en clair dans `raw`).
    @ViewBuilder
    private func cacheLimits(_ raw: [String: String]) -> some View {
        let limits = raw.filter { $0.key.localizedCaseInsensitiveContains("limit") }
            .sorted { $0.key < $1.key }
        if !limits.isEmpty {
            DisclosureGroup(localization.L(L10n.Performance.envSloCache)) {
                ForEach(limits, id: \.0) { key, value in
                    Text("\(key)=\(value)")
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                }
            }
            .font(AppDesign.Font.footnote)
        }
    }

    private func optRow(_ name: String, _ opt: SloOptimizerConfig.Optimization?) -> some View {
        let yes = localization.L(L10n.Performance.envYes)
        let no = localization.L(L10n.Performance.envNo)
        let line = String(format: localization.L(L10n.Performance.envSloOptRow),
                          name,
                          opt?.configured == nil ? "—" : (opt!.configured! ? yes : no),
                          opt?.effective == nil ? "—" : (opt!.effective! ? yes : no))
        return VStack(alignment: .leading, spacing: 1) {
            Text(line).font(AppDesign.Font.body)
            if let reason = opt?.reason, !reason.isEmpty {
                Text(reason).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Menus

    private func menusSection(_ menus: [ConfigMenuEntry]) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(localization.L(L10n.Performance.envMenusTitle))
                .font(AppDesign.Font.headline(.semibold))
            Text(String(format: localization.L(L10n.Performance.envMenusCount), Int64(menus.count)))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            ForEach(menus) { menu in
                HStack(spacing: AppDesign.Spacing.xs) {
                    Text(menu.name).font(AppDesign.Font.body)
                    if let id = menu.modId {
                        Text("(\(id))").font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: AppDesign.Spacing.xs)
                    flavorTag(menu.flavor)
                }
            }
            // Couverture partielle par nature (spec §2) : note permanente.
            Text(localization.L(L10n.Performance.envMenusPartial))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
        }
    }

    private func flavorTag(_ flavor: ConfigMenuEntry.Flavor) -> some View {
        let key = flavor == .mcm ? L10n.Performance.envFlavorMcm : L10n.Performance.envFlavorGmcm
        return Text(localization.L(key))
            .font(AppDesign.Font.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(AppDesign.Color.controlBg))
    }

    // MARK: - Packs CP

    private func packsSection(_ report: SessionEnvironmentReport) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(localization.L(L10n.Performance.envPacksTitle))
                .font(AppDesign.Font.headline(.semibold))
            if report.groups.isEmpty {
                // Le report != nil garantit un journal lu : ici c'est le disque
                // qui n'a aucun pack CP actif (tout en pause, ou gameDir absent)
                // — pas « pas de journal » (revue D2-T3, issue 1).
                Text(localization.L(L10n.Performance.envPacksNone))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            } else {
                Text(String(format: localization.L(L10n.Performance.envPacksTotal),
                            Int64(report.totalPatches), Int64(report.totalPacks)))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                let ranked = report.groups.sorted { $0.totalPatches > $1.totalPatches }
                ForEach(Array(ranked.prefix(8).enumerated()), id: \.offset) { _, group in
                    packRow(group, conflicted: isConflicted(group, report.conflicts))
                }
                if ranked.count > 8 {
                    Text(String(format: localization.L(L10n.Performance.envPacksRest),
                                Int64(ranked.count - 8)))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                }
                if !report.unreadablePacks.isEmpty {
                    Text(String(format: localization.L(L10n.Performance.envPacksIllisible),
                                report.unreadablePacks.joined(separator: ", ")))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func packRow(_ group: ContentPatcherPacks.Group, conflicted: Bool) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text(group.rootName).font(AppDesign.Font.body).lineLimit(1)
                .truncationMode(.middle)
            // Détail par pack quand la racine en porte plusieurs (SVE = [CP]+[FTM]).
            if group.packs.count > 1 {
                Text(group.packs.map { "\($0.packName): \($0.state == .ok ? String($0.patches) : "?")" }
                    .joined(separator: " · "))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: AppDesign.Spacing.xs)
            Text("\(group.totalPatches)")
                .font(AppDesign.Font.body.monospacedDigit()).foregroundColor(.secondary)
            if conflicted {
                badge(localization.L(L10n.Performance.envPacksConflicts))
            }
        }
    }

    /// Les conflits nomment les packs tels que CP les journalise (display
    /// name, ex. « [CP] Stardew Valley Expanded ») ; la carte nomme la racine
    /// (ex. « Stardew Valley Expanded »). Rapprochement **à sens unique** :
    /// le nom plié du pack contient le nom plié de la racine — jamais
    /// l'inverse, sinon un nom court (« Lone ») badge des packs sans rapport.
    private func isConflicted(_ group: ContentPatcherPacks.Group,
                              _ conflicts: [LoadConflict]) -> Bool {
        let root = group.rootName.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                          locale: nil)
        return conflicts.contains { conflict in
            conflict.packs.contains {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                    .contains(root)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(AppDesign.Font.caption).foregroundColor(AppDesign.Color.warning)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(AppDesign.Color.warning.opacity(AppDesign.Opacity.light)))
    }
}
