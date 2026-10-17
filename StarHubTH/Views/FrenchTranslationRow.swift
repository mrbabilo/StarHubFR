import SwiftUI

// Sortis de `FrenchTranslationsView` (R3, 2026-10-16) : la page gagne un
// second segment, « À finir ».

/// Un groupe repliable ; son état vit ici, pas dans la page, pour que chaque
/// section garde le sien.
struct FrenchTranslationSection<Content: View>: View {
    let title: String
    let style: (color: Color, icon: String)
    let startsOpen: Bool
    /// Vrai quand la légende de l'anneau désigne cette section : elle s'ouvre.
    let reveal: Bool
    @ViewBuilder let content: () -> Content
    @State private var isOpen: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isOpen ?? startsOpen }, set: { isOpen = $0 })) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) { content() }
                .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Label {
                Text(title).font(AppDesign.Font.body(.semibold))
            } icon: {
                Image(systemName: style.icon).foregroundStyle(style.color)
            }
        }
        .onChange(of: reveal) { _, now in
            if now { withMotion { isOpen = true } }
        }
    }
}

/// Un mod et ce que Nexus propose pour lui.
struct FrenchTranslationRow: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    let candidate: FrenchTranslationSweep.Candidate
    let status: FrenchTranslationSweep.Status
    let entry: FrenchTranslationSweep.Entry?
    let openMod: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AppDesign.Spacing.sm) {
                Text(candidate.name).font(AppDesign.Font.body(.medium)).lineLimit(1)
                if !candidate.isActive {
                    Text(localization.L(L10n.FrTranslations.paused))
                        .font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                }
                if viewModel.translationHub.isBusy(mod.folderName) { ProgressView().controlSize(.small) }
                Spacer()
                Button(localization.L(L10n.FrTranslations.openMod), action: openMod)
                    .buttonStyle(.borderless).controlSize(.small).pointingHandCursor().focusRing(cornerRadius: 4)
            }
            switch status {
            case .available(let hits):
                // Le plus sûr d'abord : confirmée, liée, puis par nom.
                ForEach(hits.sorted { rank($0) < rank($1) }) {
                    hitLine($0, action: L10n.FrTranslations.install, dismissable: confidence($0) != .confirmed)
                }
            case .updateAvailable(let newer):
                hitLine(newer, action: L10n.FrTranslations.update, dismissable: false)
            case .installed, .installedUnverified, .failed, .nothingFound, .notSearched:
                EmptyView()
            }
        }
        .cardSurface(padding: AppDesign.Spacing.sm)
    }

    private func confidence(_ hit: NexusModSearch.Hit) -> FrenchTranslationSweep.Confidence {
        entry?.confidence(of: hit, hostName: candidate.name) ?? .nameOnly
    }

    private func rank(_ hit: NexusModSearch.Hit) -> Int {
        switch confidence(hit) {
        case .confirmed: return 0
        case .linkedOnly: return 1
        case .nameOnly: return 2
        }
    }

    /// La marque d'un résultat qui demande à être vérifié ; rien quand le lien
    /// et le titre concordent.
    @ViewBuilder private func caution(_ hit: NexusModSearch.Hit) -> some View {
        switch confidence(hit) {
        case .confirmed:
            EmptyView()
        case .linkedOnly:
            Text(localization.L(L10n.FrTranslations.linkedOnly))
                .font(AppDesign.Font.iconXS).foregroundColor(AppDesign.Color.warning)
                .help(localization.L(L10n.FrTranslations.linkedOnlyHelp))
        case .nameOnly:
            Text(localization.L(L10n.FrTranslations.byName))
                .font(AppDesign.Font.iconXS).foregroundColor(AppDesign.Color.warning)
                .help(localization.L(L10n.FrTranslations.byNameHelp))
        }
    }

    /// `dismissable` : un résultat à vérifier (par le nom, ou lié sans que
    /// le titre nomme le mod) peut s'écarter (P5-4) ; une traduction confirmée
    /// ou la mise à jour d'une traduction posée, non.
    private func hitLine(_ hit: NexusModSearch.Hit, action: String, dismissable: Bool) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(hit.name).font(AppDesign.Font.footnote(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    caution(hit)
                }
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(AppDesign.Font.iconXS).foregroundColor(.secondary)
            }
            Spacer()
            // R7 — même garde que la fiche : sans Premium, lien direct refusé,
            // le bouton Nexus à côté relaie (avant : actif, puis modale d'erreur).
            let premiumOnly = viewModel.nexusDirectDownloadUnavailable
            Button(localization.L(action)) { viewModel.installTranslation(hit, into: mod) }
                .buttonStyle(.bordered).controlSize(.small).focusRing(cornerRadius: 5)
                .disabled(viewModel.translationHub.isBusy(mod.folderName) || premiumOnly)
                .help(premiumOnly ? localization.L(L10n.Mods.premiumOnlyHint) : "")
                .pointingHandCursor()
            Button {
                if let url = URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(AppDesign.Font.footnote)
            }
            .buttonStyle(.bordered).controlSize(.small).pointingHandCursor().focusRing(cornerRadius: 5)
            if dismissable {
                Button {
                    if !viewModel.translationSweep.dismiss(hit, for: candidate) {
                        viewModel.log("Traductions FR : l'écart de « \(hit.name) » n'a pas pu s'écrire", level: .warning)
                    }
                } label: {
                    // Cible portée à 18×18 : sur un glyphe nu, l'infobulle ne
                    // s'affiche jamais.
                    Image(systemName: "hand.thumbsdown")
                        .frame(width: 18, height: 18).contentShape(.rect)
                }
                .buttonStyle(.borderless).pointingHandCursor().focusRing(cornerRadius: 4)
                .help(localization.L(L10n.FrTranslations.notThisOne))
                .accessibilityLabel(localization.L(L10n.FrTranslations.notThisOne))
            }
        }
        .padding(.leading, AppDesign.Spacing.md)
    }
}

/// P5-4 — les résultats écartés, en bas de la page, chacun rétablissable.
/// Replié : la liste sert à rattraper un clic, pas à être lue.
struct DismissedTranslationHits: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let dismissals = viewModel.translationSweep.verdicts.dismissals
        if !dismissals.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text(localization.L(L10n.FrTranslations.dismissedExplanation))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(dismissals) { dismissal in
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Text(String(format: localization.L(L10n.FrTranslations.dismissedRow),
                                        dismissal.hitName, dismissal.modName))
                                .font(AppDesign.Font.footnote).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button(localization.L(L10n.FrTranslations.dismissedRestore)) {
                                if !viewModel.translationSweep.restore(dismissal) {
                                    viewModel.log("Traductions FR : le rétablissement de « \(dismissal.hitName) » "
                                                  + "n'a pas pu s'écrire", level: .warning)
                                }
                            }
                            .buttonStyle(.borderless).focusRing(cornerRadius: 4).controlSize(.small).pointingHandCursor()
                        }
                    }
                }
                .padding(.top, AppDesign.Spacing.xs)
            } label: {
                Label(String(format: localization.L(L10n.FrTranslations.dismissedTitle), Int64(dismissals.count)),
                      systemImage: "hand.thumbsdown")
                    .font(AppDesign.Font.body(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}
