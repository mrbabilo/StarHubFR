import SwiftUI

/// Transitive dependency tree for the detail pane's Dependencies tab. Replaces
/// SP2's flat uniqueId list: resolved names, three-state status, per-node
/// actions, click-through. Rebuilds from `vm.dependencyTree(for:)`, which reads
/// `@Published mods` — so an "Enable" action re-resolves automatically.
struct DependencyTreeView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    var body: some View {
        let nodes = vm.dependencyTree(for: mod)
        if nodes.isEmpty {
            ContentUnavailableView(vm.L(L10n.VM.noDependenciesFound), systemImage: "shippingbox")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(nodes) { node in
                    DependencyNodeTree(node: node, vm: vm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One node plus its children, indented under a thin leading guide rail. The
/// recursion (a view containing itself) is what gives arbitrary depth without
/// per-node `├─`/`└─` glyph bookkeeping.
struct DependencyNodeTree: View {
    let node: DependencyNode
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DependencyRowView(node: node, vm: vm)
            if !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children) { child in
                        DependencyNodeTree(node: child, vm: vm)
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                        .padding(.leading, 6)
                }
            }
        }
    }
}

/// A single dependency row: status icon + resolved name/author (or monospaced
/// uniqueId when missing), required/optional badge, status text, and a
/// status-specific action. Tapping an installed row opens that mod's own detail
/// pane (SP2 navigation).
struct DependencyRowView: View {
    let node: DependencyNode
    @ObservedObject var vm: StarHubTHViewModel
    /// La dépendance dont l'activation attend une confirmation : smapi.io la
    /// signale cassée. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                if let resolved = node.resolved {
                    Text(resolved.name).font(.system(size: 13, weight: .medium))
                    Text(resolved.author).font(.system(size: 10)).foregroundColor(.secondary)
                } else {
                    Text(node.uniqueId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(node.isRequired ? vm.L(L10n.Profiles.required) : vm.L(L10n.Profiles.optional))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(node.isRequired ? .orange : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((node.isRequired ? Color.orange : Color.secondary).opacity(0.15))
                        .cornerRadius(3)
                    Text(statusText).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(iconColor.opacity(0.25), lineWidth: 1))
        .contentShape(Rectangle())
        .modifier(NodeTapModifier(mod: node.resolved, vm: vm))
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
    }

    private var iconName: String {
        switch node.status {
        case .active: return "checkmark.circle.fill"
        case .disabled: return "pause.circle.fill"
        case .missing: return node.isRequired ? "xmark.circle.fill" : "questionmark.circle"
        }
    }
    private var iconColor: Color {
        switch node.status {
        case .active: return .green
        case .disabled: return .yellow
        case .missing: return node.isRequired ? .red : .gray
        }
    }
    private var statusText: String {
        switch node.status {
        case .active: return vm.L(L10n.Mods.depActive)
        case .disabled: return vm.L(L10n.Mods.depDisabled)
        case .missing: return vm.L(L10n.Mods.depMissing)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch node.status {
        case .disabled(let depMod):
            Button(vm.L(L10n.Mods.depEnable)) {
                // Même porte qu'ailleurs : activer un mod signalé cassé se
                // confirme. Une dépendance cassée est justement le cas où
                // l'utilisateur a le plus besoin de le savoir avant de cliquer.
                if vm.activationWarning(for: depMod) != nil {
                    pendingActivation = depMod
                } else {
                    vm.toggleMod(depMod)
                }
            }
                .buttonStyle(.bordered).controlSize(.small).pointingHandCursor()
        case .active:
            let link = node.resolved.map { vm.nexusLink(for: $0) } ?? ""
            if !link.isEmpty {
                Button(vm.L(L10n.Mods.nexusOpenPage)) {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderless).controlSize(.small)
                .foregroundColor(.accentColor).pointingHandCursor()
            }
        case .missing:
            let modName = node.uniqueId.smapiModName
            let author = node.uniqueId.smapiAuthor
            Menu {
                Button {
                    openNexusSearch(for: modName)
                } label: {
                    Label(String(format: vm.L(L10n.Mods.searchNexusByModName), modName),
                          systemImage: "magnifyingglass")
                }
                if !author.isEmpty {
                    Button {
                        openNexusAuthorSearch(for: author)
                    } label: {
                        Label(String(format: vm.L(L10n.Mods.searchNexusByAuthor), author),
                              systemImage: "person")
                    }
                }
            } label: {
                Text(vm.L(L10n.Mods.depSearch))
            }
            .buttonStyle(.borderless).controlSize(.small)
            .foregroundColor(.accentColor).pointingHandCursor()
        }
    }

    /// Ouvre la recherche Nexus Mods pour un terme donné (dépendance manquante).
    private func openNexusSearch(for searchTerm: String) {
        let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        if let url = URL(string: "https://www.nexusmods.com/stardewvalley/search/?gsearch=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ouvre la liste des mods d'un auteur sur Nexus Mods. Le filtre `?author=`
    /// est plus précis qu'une recherche plein texte pour retrouver tous les
    /// mods d'un même auteur.
    private func openNexusAuthorSearch(for author: String) {
        let encoded = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
        if let url = URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?author=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Makes a row tappable → opens the dependency's own detail pane, but only when
/// the dependency is installed (a missing dep has no pane to show).
private struct NodeTapModifier: ViewModifier {
    let mod: ModItem?
    @ObservedObject var vm: StarHubTHViewModel
    func body(content: Content) -> some View {
        if let mod {
            content.onTapGesture { vm.viewingModDetail = mod }.pointingHandCursor()
        } else {
            content
        }
    }
}
