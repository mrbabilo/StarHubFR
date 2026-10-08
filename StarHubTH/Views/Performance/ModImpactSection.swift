import SwiftUI

/// D5-C — la classe d'impact : icône colorée + mot en encre normale, jamais
/// la couleur seule (vert et orange sous 3:1 sur fond clair, `dataviz`).
struct ModImpactBadge: View {
    @ObservedObject var localization: LocalizationStore
    let impactClass: ModImpactClass?
    let score: Double?
    /// Note d'une autre version que l'installée (spec §3.3) : en gris.
    var dimmed = false

    /// La charte d'une classe — icône, couleur, clé du libellé — en un seul
    /// endroit : la pastille de liste (`ImpactListBadge`) la réutilise, et
    /// deux copies de ce switch divergeraient à la première retouche.
    /// L'élevé est un **rond plein**, pas un triangle : le triangle est la
    /// signalétique des problèmes (anomalies de la liste, avertissements du
    /// journal) et un coût de performance mesuré n'est pas une panne.
    static func visuals(for impactClass: ModImpactClass) -> (icon: String, color: Color, key: String) {
        switch impactClass {
        case .high: ("circle.fill", AppDesign.Color.error, L10n.Performance.impactClassHigh)
        case .medium: ("minus.circle.fill", AppDesign.Color.warning, L10n.Performance.impactClassMedium)
        case .low: ("checkmark.circle.fill", AppDesign.Color.success, L10n.Performance.impactClassLow)
        }
    }

    /// Le nom localisé d'un axe, partagé par le radar de la fiche et la
    /// pastille de liste — une seule copie du switch, pour la même raison.
    static func axisLabel(_ axis: ModImpactAxis, localization: LocalizationStore) -> String {
        switch axis {
        case .fps: localization.L(L10n.Performance.impactAxisFps)
        case .spikes: localization.L(L10n.Performance.impactAxisSpikes)
        case .launch: localization.L(L10n.Performance.impactAxisLaunch)
        case .save: localization.L(L10n.Performance.impactAxisSave)
        case .alloc: localization.L(L10n.Performance.impactAxisAlloc)
        }
    }

    var body: some View {
        if let impactClass, let score {
            let visuals = Self.visuals(for: impactClass)
            Label {
                Text("\(localization.L(visuals.key)) · \(String(format: localization.L(L10n.Performance.impactScore), ModImpactFormat.score(score)))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: visuals.icon).foregroundStyle(dimmed ? Color.secondary : visuals.color)
            }
            .font(AppDesign.Font.footnote(.semibold))
            .foregroundStyle(dimmed ? .secondary : .primary)
        }
    }
}

/// Les libellés localisés de l'impact ; les nombres viennent de
/// `ModImpactFormat` (Core, testé), dans la langue de l'interface.
extension ModImpactFormat {
    /// « v1.2 », ou « version inconnue » (segment sans inventaire) — le « v »
    /// ne vit pas dans les gabarits, sinon « vversion inconnue ».
    static func version(_ version: String?, localization: LocalizationStore) -> String {
        version.map { "v" + $0 } ?? localization.L(L10n.Performance.impactVersionUnknown)
    }

    /// « ↓ 8 depuis v1.1 (plus léger) », « Inchangée depuis v1.1 » — la fiche
    /// et le libellé VoiceOver de la flèche du classement.
    static func evolutionText(_ delta: Double, previous: String?, localization: LocalizationStore) -> String {
        let since = version(previous, localization: localization)
        switch evolution(delta) {
        case .stable: return String(format: localization.L(L10n.Performance.impactEvolutionStable), since)
        case .gain: return String(format: localization.L(L10n.Performance.impactEvolutionGain), score(abs(delta)), since)
        case .loss: return String(format: localization.L(L10n.Performance.impactEvolutionLoss), score(abs(delta)), since)
        }
    }

    static func evolutionIcon(_ delta: Double) -> (name: String, color: Color) {
        switch evolution(delta) {
        case .stable: ("equal", .secondary)
        case .gain: ("arrow.down.right", AppDesign.Color.success)
        case .loss: ("arrow.up.right", AppDesign.Color.warning)
        }
    }
}

/// D5-C — la section « Impact sur les performances » de la fiche (onglet
/// État). Ne calcule rien : tout vient de `ModImpactStore` (Core, testé).
struct ModImpactSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    private var store: ModImpactStore { viewModel.modImpactStore }
    private var language: String { localization.currentLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.impactTitle)).font(AppDesign.Font.headline(.semibold))
            content
        }
        // Première lecture seulement : la fermeture du jeu relit pour tous
        // (`GameExitRefresh`), une fiche ouverte ne relit plus 18 Mo.
        .task {
            if store.status == .idle {
                await store.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(), gameDir: viewModel.gameDir)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .noProbe:
            StateCard(icon: "gauge.with.dots.needle.0percent", text: localization.L(L10n.Performance.impactEmptyProbe), actionTitle: nil) {}
        case .unreadableHistory:
            StateCard(icon: AppDesign.Status.warning.symbol, text: localization.L(L10n.Performance.impactUnreadable), actionTitle: nil) {}
        case .ready:
            if let entry = store.entry(for: mod), let shown = entry.shown {
                measured(entry, shown)
            } else if store.entry(for: mod)?.isNegligible == true {
                StateCard(icon: "leaf", text: localization.L(L10n.Performance.impactNegligible), actionTitle: nil) {}
            } else {
                StateCard(icon: "hourglass", text: localization.L(L10n.Performance.impactEmptyMod), actionTitle: nil) {}
            }
        }
    }

    @ViewBuilder
    private func measured(_ entry: ModImpactEntry, _ shown: ModImpactVersionStats) -> some View {
        if !entry.isEnabled { note(localization.L(L10n.Performance.impactPaused)) }
        if entry.current == nil {
            note(String(format: localization.L(L10n.Performance.impactNotMeasuredVersion),
                        ModImpactFormat.version(entry.installedVersion, localization: localization),
                        ModImpactFormat.version(shown.version, localization: localization)))
        }
        if shown.isNegligible {
            StateCard(icon: "leaf", text: localization.L(L10n.Performance.impactNegligible), actionTitle: nil) {}
        } else {
            SplitRow(spacing: AppDesign.Spacing.lg) {
                ModImpactRadar(shares: shown.shares, size: 200, label: axisLabel,
                               detail: { axisDetail($0, shown) })
            } trailing: {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    ModImpactBadge(localization: localization, impactClass: shown.impactClass, score: shown.score,
                                   dimmed: entry.current == nil)
                    if isPartial(shown) { note(localization.L(L10n.Performance.impactPartial)) }
                    if let gain = gainText(shown) {
                        Text(gain).font(AppDesign.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                    blockersText
                    evolution(entry)
                }
            }
        }
        versions(entry)
        footer(shown)
    }

    // MARK: — Morceaux

    private func note(_ text: String) -> some View {
        PerformanceFormatting.note(text)
    }

    private func axisLabel(_ axis: ModImpactAxis) -> String {
        ModImpactBadge.axisLabel(axis, localization: localization)
    }

    private func axisDetail(_ axis: ModImpactAxis, _ stats: ModImpactVersionStats) -> String {
        guard let share = stats.shares[axis] else {
            return String(format: localization.L(L10n.Performance.impactUnmeasuredAxis), axisLabel(axis))
        }
        let n = axis == .launch ? stats.launchSources : axis == .save ? stats.saveSources : stats.inGameSources
        return String(format: localization.L(L10n.Performance.impactAxisDetail), axisLabel(axis),
                      ModImpactFormat.percent(share, language: language), n)
    }

    /// « partielle » : un axe manque à ce mod alors qu'un autre mod l'a.
    private func isPartial(_ stats: ModImpactVersionStats) -> Bool {
        let measuredSomewhere = Set(store.entries.compactMap(\.shown).flatMap { $0.shares.keys })
        return measuredSomewhere.contains { stats.shares[$0] == nil }
    }

    private func gainText(_ s: ModImpactVersionStats) -> String? {
        var parts: [String] = []
        if let frame = s.msPerFrame {
            let ms = ModImpactFormat.number(frame, digits: 2, language: language)
            parts.append(s.frameWorkShare.map {
                String(format: localization.L(L10n.Performance.impactGainFrame), ms, ModImpactFormat.percent($0, language: language))
            } ?? String(format: localization.L(L10n.Performance.impactGainFrameOnly), ms))
        }
        if let ms = s.launchMs {
            parts.append(String(format: localization.L(L10n.Performance.impactGainLaunch), ModImpactFormat.duration(ms, language: language)))
        }
        if let ms = s.saveMs {
            parts.append(String(format: localization.L(L10n.Performance.impactGainSave), ModImpactFormat.duration(ms, language: language)))
        }
        if let mb = s.allocMBPerMinute {
            parts.append(String(format: localization.L(L10n.Performance.impactGainAlloc), ModImpactFormat.number(mb, language: language)))
        }
        return parts.isEmpty ? nil : String(format: localization.L(L10n.Performance.impactGain), parts.joined(separator: " · "))
    }

    @ViewBuilder
    private var blockersText: some View {
        let blockers = ProbePerformanceActions.pauseBlockers(modId: mod.uniqueId, in: viewModel.mods)
        if !blockers.dependents.isEmpty {
            note(blockers.dependents.count == 1 ? localization.L(L10n.Performance.impactDependentsOne)
                 : String(format: localization.L(L10n.Performance.impactDependents), blockers.dependents.count))
                .help(blockers.dependents.joined(separator: ", "))
        }
        if !blockers.siblings.isEmpty {
            note(String(format: localization.L(L10n.Performance.impactSiblings), blockers.siblings.joined(separator: ", ")))
        }
    }

    /// Flèche colorée, texte en encre normale (`dataviz` : le vert et
    /// l'orange ne portent jamais de texte).
    @ViewBuilder
    private func evolution(_ entry: ModImpactEntry) -> some View {
        if let delta = entry.evolution, let previousVersion = entry.previousVersion {
            let icon = ModImpactFormat.evolutionIcon(delta)
            Label {
                Text(ModImpactFormat.evolutionText(delta, previous: previousVersion.version, localization: localization))
            } icon: {
                Image(systemName: icon.name).foregroundStyle(icon.color)
            }
            .font(AppDesign.Font.footnote(.semibold))
        } else if entry.comparableVersionCount > 1 {
            note(localization.L(L10n.Performance.impactEvolutionFew))
        }
    }

    @ViewBuilder
    private func versions(_ entry: ModImpactEntry) -> some View {
        if entry.versions.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.versions, id: \.version) { v in
                    Text(String(format: localization.L(L10n.Performance.impactVersionRow),
                                ModImpactFormat.version(v.version, localization: localization),
                                v.isNegligible ? "—" : String(format: localization.L(L10n.Performance.impactScore),
                                                              ModImpactFormat.score(v.score)),
                                v.sourceCount, ModImpactFormat.date(v.first) ?? "", ModImpactFormat.date(v.last) ?? ""))
                        .font(AppDesign.Font.footnote).monospacedDigit()
                        .foregroundStyle(v == entry.current ? .primary : .secondary)
                }
            }
        }
    }

    private func footer(_ shown: ModImpactVersionStats) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            note(localization.L(L10n.Performance.impactRelative))
            if shown.inGameSources > 0, shown.patchedSources < shown.inGameSources {
                note(String(format: localization.L(L10n.Performance.impactPatches), shown.patchedSources, shown.inGameSources))
            }
            note(String(format: localization.L(L10n.Performance.impactSources),
                        ModImpactFormat.date(store.lastInGame) ?? localization.L(L10n.Performance.impactNever),
                        ModImpactFormat.date(store.lastLaunch) ?? localization.L(L10n.Performance.impactNever),
                        ModImpactFormat.date(store.lastSave) ?? localization.L(L10n.Performance.impactNever)))
        }
    }
}
