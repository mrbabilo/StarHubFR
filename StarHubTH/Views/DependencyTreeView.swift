import SwiftUI

/// Transitive dependency tree for the detail pane's Dependencies tab. Replaces
/// SP2's flat uniqueId list: resolved names, three-state status, per-node
/// actions, click-through. Rebuilds from `vm.dependencyTree(for:)`, which reads
/// `@Published mods` — so an "Enable" action re-resolves automatically.
struct DependencyTreeView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    var body: some View {
        let nodes = vm.dependencyTree(for: mod)
        // A5-T6 — ce que le manifeste tait compte aussi comme dépendance.
        let hidden = vm.hiddenCodeIndex.undeclaredLinks(for: mod, installed: vm.scanStore.mods)
        if nodes.isEmpty && hidden.isEmpty {
            ContentUnavailableView(localization.L(L10n.VM.noDependenciesFound), systemImage: "shippingbox")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(nodes) { node in
                    DependencyNodeTree(node: node, vm: vm, localization: localization)
                }
                if !hidden.isEmpty {
                    HiddenCodeDependenciesSection(viewModel: vm, localization: localization, links: hidden)
                        .padding(.top, nodes.isEmpty ? 0 : 8)
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
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DependencyRowView(node: node, vm: vm, localization: localization)
            if !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children) { child in
                        DependencyNodeTree(node: child, vm: vm, localization: localization)
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
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// La dépendance dont l'activation attend une confirmation : smapi.io la
    /// signale cassée. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?
    /// Même rôle, source différente : un conflit déclaré ou observé dans le
    /// journal avec un mod déjà actif (tâche 9). Voir `ConflictActivationGate`.
    @State private var pendingConflict: ConflictActivation?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(AppDesign.Font.body)
            VStack(alignment: .leading, spacing: 2) {
                if let resolved = node.resolved {
                    Text(resolved.name).font(AppDesign.Font.body(.medium))
                    Text(resolved.author).font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                } else {
                    Text(node.uniqueId)
                        .font(AppDesign.Font.monoCaption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(node.isRequired ? localization.L(L10n.Profiles.required) : localization.L(L10n.Profiles.optional))
                        .font(AppDesign.Font.iconXXS(.bold))
                        .foregroundColor(node.isRequired ? .orange : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((node.isRequired ? Color.orange : Color.secondary).opacity(0.15))
                        .cornerRadius(3)
                    Text(statusText).font(AppDesign.Font.iconXS).foregroundColor(.secondary)
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
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
    }

    private var iconName: String {
        switch node.status {
        case .active: return "checkmark.circle.fill"
        case .disabled: return "pause.circle.fill"
        case .missing: return node.isRequired ? AppDesign.Status.error.symbol : AppDesign.Status.unknown.symbol
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
        case .active: return localization.L(L10n.Mods.depActive)
        case .disabled: return localization.L(L10n.Mods.depDisabled)
        case .missing: return localization.L(L10n.Mods.depMissing)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch node.status {
        case .disabled(let depMod):
            Button(localization.L(L10n.Mods.depEnable)) {
                // Même porte qu'ailleurs : activer un mod signalé cassé se
                // confirme. Une dépendance cassée est justement le cas où
                // l'utilisateur a le plus besoin de le savoir avant de cliquer.
                if vm.activationWarning(for: depMod) != nil {
                    pendingActivation = depMod
                } else if let other = vm.conflictWarning(for: depMod) {
                    pendingConflict = ConflictActivation(mod: depMod, other: other)
                } else {
                    vm.toggleMod(depMod)
                }
            }
                .buttonStyle(.bordered).controlSize(.small).pointingHandCursor()
        case .active:
            let link = node.resolved.map { vm.nexusLink(for: $0) } ?? ""
            if !link.isEmpty {
                Button(localization.L(L10n.Mods.nexusOpenPage)) {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderless).controlSize(.small)
                .foregroundColor(.accentColor).pointingHandCursor()
            }
        case .missing:
            let modName = node.uniqueId.smapiModName
            let author = node.uniqueId.smapiAuthor
            // A1-T1 — la page Nexus exacte quand le dump Pathoschild la
            // connaît : pas de recherche à deviner. La recherche reste le
            // dernier recours (mod hors dump).
            let entry = vm.dependencyDirectory.entry(for: node.uniqueId)
            Menu {
                if let nexusId = entry?.nexusId {
                    Button {
                        NSWorkspace.shared.open(MissingDependencies.filesPage(nexusId: nexusId))
                    } label: {
                        Label(localization.L(L10n.Mods.depsSheetOpenPage), systemImage: "safari")
                    }
                }
                Button {
                    openNexusSearch(for: modName)
                } label: {
                    Label(String(format: localization.L(L10n.Mods.searchNexusByModName), modName),
                          systemImage: "magnifyingglass")
                }
                if !author.isEmpty {
                    Button {
                        openNexusAuthorSearch(for: author)
                    } label: {
                        Label(String(format: localization.L(L10n.Mods.searchNexusByAuthor), author),
                              systemImage: "person")
                    }
                }
            } label: {
                Text(entry?.name ?? localization.L(L10n.Mods.depSearch))
                    .underline(entry != nil)
            }
            .buttonStyle(.borderless).controlSize(.small)
            .foregroundColor(.accentColor).pointingHandCursor()
        }
    }

    /// Ouvre la recherche Nexus Mods pour un terme donné (dépendance manquante).
    private func openNexusSearch(for searchTerm: String) {
        NexusWebLinks.openSearch(for: searchTerm)
    }

    /// Ouvre la liste des mods d'un auteur sur Nexus Mods.
    private func openNexusAuthorSearch(for author: String) {
        NexusWebLinks.openAuthorSearch(for: author)
    }
}

/// Makes a row tappable → opens the dependency's own detail pane, but only when
/// the dependency is installed (a missing dep has no pane to show).
private struct NodeTapModifier: ViewModifier {
    let mod: ModItem?
    var vm: StarHubTHViewModel
    func body(content: Content) -> some View {
        if let mod {
            content.onTapGesture { vm.navigationStore.setViewingModDetail(mod) }.pointingHandCursor()
        } else {
            content
        }
    }
}
