import SwiftUI

/// L'état de la sonde en tête de l'onglet : une ligne quand elle est à jour,
/// la carte « Sonde » quand une action est due (installer, réactiver, mettre
/// à jour). La bannière « sonde chargée en premier » remonte ici tant qu'elle
/// attend une réponse ; sinon elle vit dans « Sonde et réglages » en bas de
/// page (lot A, S6). Les états de mesure vivent dans `PerformanceStatusLine`.
struct PerformanceMeasurementStatus: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    /// Déplie et montre « Sonde et réglages » en bas de page.
    var openSettings: () -> Void
    @AppStorage(UDKey.probeLoadEarlyConsent) private var loadEarlyConsent: Bool?

    private var bundledProbeVersion: String? {
        ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL).flatMap(ProbeBundle.version(ofFolder:))
    }

    /// Sonde active, à jour, et le dernier lancement l'a chargée après
    /// d'autres mods sans que l'utilisateur ait répondu : la bannière prend la
    /// tête de page, et la carte du bas ne la répète pas.
    static func hoistsLoadOrderBanner(_ viewModel: StarHubTHViewModel, _ store: ProbePerformanceStore,
                                      consent: Bool?) -> Bool {
        guard consent == nil, store.lastLaunch?.probeLoadsFirst == false else { return false }
        let probe = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        guard case .enabled(_, let version) = probe else { return false }
        if case .outdated = GuidedProtocol.readiness(probeVersion: version, isEnabled: true) { return false }
        guard GuidedProtocol.supportsPilot(version) else { return false }
        let bundled = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL).flatMap(ProbeBundle.version(ofFolder:))
        if case .update = ProbeBundle.action(bundled: bundled, presence: probe) { return false }
        return true
    }

    var body: some View {
        let probe = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            switch probe {
            case .absent, .paused:
                PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
            case .enabled(_, let version):
                HStack(spacing: AppDesign.Spacing.sm) {
                    Label(String(format: localization.L(L10n.Performance.probeEnabled), version), systemImage: "waveform.path")
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    Button(localization.L(L10n.Performance.probeSettingsLink), action: openSettings)
                        .buttonStyle(.hoverLink).focusRing(cornerRadius: 4).font(AppDesign.Font.footnote)
                    Spacer()
                    ProbeMiniStatsToggle(viewModel: viewModel, localization: localization, presence: probe)
                }
                if case .outdated = GuidedProtocol.readiness(probeVersion: version, isEnabled: true) {
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                } else if !GuidedProtocol.supportsPilot(version) {
                    // Guidage possible, pilotage non : sans ce mot, le bouton
                    // « Mesure pilotée » resterait caché sans explication.
                    Text(String(format: localization.L(L10n.PerformancePilot.needsProbeUpdate),
                                GuidedProtocol.pilotMinimumVersion.map(String.init).joined(separator: ".")))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                } else if case .update = ProbeBundle.action(bundled: bundledProbeVersion, presence: probe) {
                    // L'app embarque une sonde plus récente : sans cette carte,
                    // la mise à jour ne se proposait que dans le volet replié
                    // « Réglages » (0.9.26 jamais déployée, 2026-10-13).
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                } else if Self.hoistsLoadOrderBanner(viewModel, store, consent: loadEarlyConsent) {
                    PerformanceLoadsProbeFirst(viewModel: viewModel, localization: localization, store: store,
                                               consent: $loadEarlyConsent)
                }
            }
        }
    }
}
