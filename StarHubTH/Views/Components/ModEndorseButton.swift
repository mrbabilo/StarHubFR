import SwiftUI

/// A3-T8 — le geste « approuver sur Nexus », partagé par la fiche, la ligne
/// de la liste et le menu contextuel de la carte : même identifiant, même
/// version envoyée, mêmes refus.
@MainActor
enum ModEndorsement {
    /// L'identifiant Nexus du mod, si une clé permet d'agir dessus.
    static func actionableId(_ mod: ModItem, viewModel: StarHubTHViewModel) -> Int? {
        guard viewModel.hasNexusApiKey, let id = Int(viewModel.resolvedNexusModId(for: mod)), id > 0 else { return nil }
        return id
    }

    static func isEndorsed(_ mod: ModItem, viewModel: StarHubTHViewModel) -> Bool {
        guard let id = Int(viewModel.resolvedNexusModId(for: mod)) else { return false }
        return viewModel.endorsementStore.statuses[id] == .endorsed
    }

    /// Approuve ou retire. `reportRefusal` : la liste n'a pas de place pour
    /// le refus, il part en fenêtre ; la fiche l'affiche sous sa barre.
    static func toggle(_ mod: ModItem, viewModel: StarHubTHViewModel, localization: LocalizationStore,
                       reportRefusal: Bool) {
        guard let id = actionableId(mod, viewModel: viewModel) else { return }
        let version = mod.version.isEmpty ? (mod.components.first?.version ?? "") : mod.version
        Task {
            await viewModel.endorsementStore.toggle(modId: id, version: version) { viewModel.log($0) }
            if reportRefusal, let refusal = viewModel.endorsementStore.failures[id] {
                viewModel.showModal(message: message(refusal, localization: localization))
            }
        }
    }

    static func message(_ refusal: NexusEndorsement.Outcome, localization: LocalizationStore) -> String {
        switch refusal {
        case .isOwnMod: return localization.L(L10n.Mods.endorseOwnMod)
        case .tooSoonAfterDownload: return localization.L(L10n.Mods.endorseTooSoon)
        case .notDownloaded: return localization.L(L10n.Mods.endorseNotDownloaded)
        case .unknown(let code, let message):
            return String(format: localization.L(L10n.Mods.endorseUnknown), Int64(code), message ?? "—")
        case .endorsed, .abstained: return ""
        }
    }
}

/// Le pouce de la ligne : le nombre d'approbations Nexus, plein quand tu as
/// approuvé ; un clic approuve ou retire si une clé est posée, sinon il ne
/// fait qu'afficher.
struct ModEndorseButton: View {
    let mod: ModItem
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let count = viewModel.nexusEndorsementCount(for: mod)
        let endorsed = ModEndorsement.isEndorsed(mod, viewModel: viewModel)
        let actionable = ModEndorsement.actionableId(mod, viewModel: viewModel)
        if count != nil || actionable != nil {
            Button {
                ModEndorsement.toggle(mod, viewModel: viewModel, localization: localization, reportRefusal: true)
            } label: {
                Label(count.map { "\($0)" } ?? "—", systemImage: endorsed ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(AppDesign.Font.footnote.monospacedDigit())
                    .foregroundColor(endorsed ? AppDesign.Color.info : .secondary)
                    .lineLimit(1)
                    .frame(minHeight: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(actionable == nil || actionable.map { viewModel.endorsementStore.inFlight.contains($0) } == true)
            .help(helpText(count: count, endorsed: endorsed, actionable: actionable != nil))
            .accessibilityLabel(helpText(count: count, endorsed: endorsed, actionable: actionable != nil))
        }
    }

    private func helpText(count: Int?, endorsed: Bool, actionable: Bool) -> String {
        let total = count.map { String(format: localization.L(L10n.Mods.endorsementsCount), Int64($0)) } ?? ""
        guard actionable else { return total }
        let gesture = localization.L(endorsed ? L10n.Mods.endorseWithdraw : L10n.Mods.endorseAdd)
        return total.isEmpty ? gesture : "\(total) · \(gesture)"
    }
}
