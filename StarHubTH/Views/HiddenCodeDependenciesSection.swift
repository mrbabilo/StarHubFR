import SwiftUI

/// A5-T6 — sous l'arbre des dépendances : les mods dont celui-ci cherche
/// les types internes par leur nom **sans les déclarer**. Une ligne par mod
/// visé ; les noms de type se déplient, sélectionnables (ce sont eux qu'on
/// cherche dans un changelog ou un rapport de bug).
struct HiddenCodeDependenciesSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let links: [HiddenCodeDependencies.Link]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.L(L10n.HiddenCode.title), systemImage: "doc.text.magnifyingglass")
                .font(AppDesign.Font.rowTitle(.semibold))
            Text(localization.L(L10n.HiddenCode.explain))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(links, id: \.self) { link in
                HiddenCodeLinkRow(viewModel: viewModel, localization: localization, link: link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HiddenCodeLinkRow: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let link: HiddenCodeDependencies.Link
    @State private var expanded = false

    var body: some View {
        let target = viewModel.scanStore.mods.mod(withUniqueId: link.target)
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(link.typeNames, id: \.self) { name in
                    Text(name)
                        .font(AppDesign.Font.monoCaption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                if let target {
                    Button(target.name) { viewModel.navigationStore.setViewingModDetail(target) }
                        .buttonStyle(.link)
                        .font(AppDesign.Font.body(.medium))
                        .help(link.target)
                } else {
                    Text(link.target).font(AppDesign.Font.monoCaption)
                }
                Text(String(format: localization.L(L10n.HiddenCode.types), link.typeNames.count))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }
}
