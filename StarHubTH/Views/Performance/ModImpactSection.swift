import SwiftUI

/// D5-C — la classe d'impact : icône colorée + mot en encre normale, jamais
/// la couleur seule (vert et orange sous 3:1 sur fond clair, `dataviz`).
struct ModImpactBadge: View {
    @ObservedObject var localization: LocalizationStore
    let impactClass: ModImpactClass?
    let score: Double?

    var body: some View {
        if let impactClass, let score {
            let (icon, color, key): (String, Color, String) = switch impactClass {
            case .high: ("exclamationmark.triangle.fill", AppDesign.Color.error, L10n.Performance.impactClassHigh)
            case .medium: ("minus.circle.fill", AppDesign.Color.warning, L10n.Performance.impactClassMedium)
            case .low: ("checkmark.circle.fill", AppDesign.Color.success, L10n.Performance.impactClassLow)
            }
            Label {
                Text("\(localization.L(key)) · \(String(format: localization.L(L10n.Performance.impactScore), ModImpactFormat.score(score)))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            .font(AppDesign.Font.footnote(.semibold))
        }
    }
}

/// Formats partagés par la fiche et la carte (virgule décimale en français :
/// patron `PerformanceLoadsSection.duration`).
enum ModImpactFormat {
    static func score(_ value: Double) -> String { String(Int(value.rounded())) }
    static func number(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
    static func percent(_ share: Double) -> String {
        share < 0.01 ? "\(number(share * 100, digits: 2)) %" : "\(number(share * 100)) %"
    }
    /// « v1.2 », ou « version inconnue » (segment sans inventaire) — le « v »
    /// ne vit pas dans les gabarits, sinon « vversion inconnue ».
    static func version(_ version: String?, localization: LocalizationStore) -> String {
        version.map { "v" + $0 } ?? localization.L(L10n.Performance.impactVersionUnknown)
    }
    static func date(_ date: Date?) -> String? {
        date.map { $0.formatted(.dateTime.day().month(.twoDigits)) }
    }
}

/// D5-C — la section « Impact sur les performances » de la fiche (onglet
/// État). Ne calcule rien : tout vient de `ModImpactStore` (Core, testé).
struct ModImpactSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    private var store: ModImpactStore { viewModel.modImpactStore }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.impactTitle)).font(AppDesign.Font.headline(.semibold))
            content
        }
        .task { await store.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(), gameDir: viewModel.gameDir) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .noProbe:
            StateCard(icon: "gauge.with.dots.needle.0percent", text: localization.L(L10n.Performance.impactEmptyProbe), actionTitle: nil) {}
        case .unreadableHistory:
            StateCard(icon: "exclamationmark.triangle", text: localization.L(L10n.Performance.impactUnreadable), actionTitle: nil) {}
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
                    ModImpactBadge(localization: localization, impactClass: shown.impactClass, score: shown.score)
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
        Text(text).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func axisLabel(_ axis: ModImpactAxis) -> String {
        switch axis {
        case .fps: localization.L(L10n.Performance.impactAxisFps)
        case .spikes: localization.L(L10n.Performance.impactAxisSpikes)
        case .launch: localization.L(L10n.Performance.impactAxisLaunch)
        case .save: localization.L(L10n.Performance.impactAxisSave)
        case .alloc: localization.L(L10n.Performance.impactAxisAlloc)
        }
    }

    private func axisDetail(_ axis: ModImpactAxis, _ stats: ModImpactVersionStats) -> String {
        guard let share = stats.shares[axis] else {
            return String(format: localization.L(L10n.Performance.impactUnmeasuredAxis), axisLabel(axis))
        }
        let n = axis == .launch || axis == .save ? stats.sourceCount - stats.inGameSources : stats.inGameSources
        return String(format: localization.L(L10n.Performance.impactAxisDetail), axisLabel(axis), ModImpactFormat.percent(share), n)
    }

    /// « partielle » : un axe manque à ce mod alors qu'un autre mod l'a.
    private func isPartial(_ stats: ModImpactVersionStats) -> Bool {
        let measuredSomewhere = Set(store.entries.compactMap(\.shown).flatMap { $0.shares.keys })
        return measuredSomewhere.contains { stats.shares[$0] == nil }
    }

    private func gainText(_ s: ModImpactVersionStats) -> String? {
        var parts: [String] = []
        if let frame = s.msPerFrame {
            parts.append(String(format: localization.L(L10n.Performance.impactGainFrame), ModImpactFormat.number(frame, digits: 2),
                                ModImpactFormat.percent(s.frameWorkShare ?? 0)))
        }
        if let ms = s.launchMs {
            parts.append(String(format: localization.L(L10n.Performance.impactGainLaunch), PerformanceLoadsSection.duration(ms)))
        }
        if let ms = s.saveMs {
            parts.append(String(format: localization.L(L10n.Performance.impactGainSave), PerformanceLoadsSection.duration(ms)))
        }
        if let mb = s.allocMBPerMinute {
            parts.append(String(format: localization.L(L10n.Performance.impactGainAlloc), ModImpactFormat.number(mb)))
        }
        return parts.isEmpty ? nil : String(format: localization.L(L10n.Performance.impactGain), parts.joined(separator: " · "))
    }

    @ViewBuilder
    private var blockersText: some View {
        let blockers = ProbePerformanceActions.pauseBlockers(modId: mod.uniqueId, in: viewModel.mods)
        if !blockers.dependents.isEmpty {
            note(String(format: localization.L(L10n.Performance.impactDependents), blockers.dependents.count))
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
            let previous = ModImpactFormat.version(previousVersion.version, localization: localization)
            let key = delta <= 0 ? L10n.Performance.impactEvolutionGain : L10n.Performance.impactEvolutionLoss
            Label {
                Text(String(format: localization.L(key), ModImpactFormat.score(abs(delta)), previous))
            } icon: {
                Image(systemName: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                    .foregroundStyle(delta <= 0 ? AppDesign.Color.success : AppDesign.Color.warning)
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
