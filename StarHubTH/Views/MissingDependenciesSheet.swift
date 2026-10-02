import SwiftUI

/// A1-T1 — le récapitulatif des dépendances requises absentes du disque,
/// avec l'action de chacune : téléchargement dans l'app (compte premium),
/// page Nexus à ouvrir (« Mod Manager Download », repris par `nxm://`),
/// recherche en dernier recours. SMAPI n'y entre pas : il a son installateur.
///
/// La feuille **est** la confirmation : chaque ligne se lance seule, ou tout
/// d'un geste — aucun effet avant l'ouverture.
struct MissingDependenciesSheet: View {
    let vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var isPresented: Bool

    private var plan: [MissingDependency] { vm.missingDependenciesPlan }

    private var hasDirectDownload: Bool { !vm.nexusDirectDownloadUnavailable }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "shippingbox.and.arrow.backward",
                       title: localization.L(L10n.Mods.depsSheetTitle),
                       subtitle: String(format: localization.L(L10n.Mods.depsSheetIntro),
                                        Int64(plan.count)))
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.md)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    ForEach(plan) { dep in
                        row(dep)
                        Divider()
                    }
                }
                .padding(AppDesign.Spacing.xl)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 380, idealHeight: 520)
    }

    private func row(_ dep: MissingDependency) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dep.name)
                    .font(AppDesign.Font.rowTitle(.medium))
                    .lineLimit(1)
                    .help(dep.uniqueIds.joined(separator: ", "))
                Text(String(format: localization.L(L10n.Mods.depsSheetRequiredBy),
                            dep.requiredBy.joined(separator: ", ")))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if dep.isSmapi {
                    Text(localization.L(L10n.Mods.depsSheetSmapi))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }
            Spacer()
            actionButton(dep)
        }
        .padding(.vertical, AppDesign.Spacing.xs)
    }

    @ViewBuilder
    private func actionButton(_ dep: MissingDependency) -> some View {
        if dep.isSmapi {
            EmptyView()
        } else if let nexusId = dep.nexusId, hasDirectDownload {
            Button {
                vm.downloadMissingDependency(dep)
                isPresented = false
            } label: {
                Label(localization.L(L10n.Mods.depsSheetInstall), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .pointingHandCursor()
        } else if let nexusId = dep.nexusId {
            Button {
                NSWorkspace.shared.open(MissingDependencies.filesPage(nexusId: nexusId))
            } label: {
                Label(localization.L(L10n.Mods.depsSheetOpenPage), systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        } else if let url = MissingDependencies.searchPage(for: dep.name) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(localization.L(L10n.Mods.depsSheetSearch), systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
    }

    private var hasOpenablePages: Bool {
        plan.contains { !$0.isSmapi && $0.nexusId != nil }
    }

    private var footer: some View {
        HStack {
            if !hasDirectDownload && hasOpenablePages {
                Text(localization.L(L10n.Mods.depsSheetFreeHint))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 380, alignment: .leading)
            }
            Spacer()
            if plan.contains(where: { !$0.isSmapi && $0.nexusId != nil && hasDirectDownload }) {
                Button {
                    vm.installAllMissingDependencies()
                    isPresented = false
                } label: {
                    Label(localization.L(L10n.Mods.depsSheetInstallAll), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
            }
            Button {
                isPresented = false
            } label: {
                Text(localization.L(L10n.Mods.depsSheetClose))
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .pointingHandCursor()
        }
        .padding(AppDesign.Spacing.xl)
    }
}
