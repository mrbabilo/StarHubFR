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
                // E7 — le geste utile d'abord, en évidence ; l'arbre complet suit.
                let toFix = DependencyTreeBuilder.toFix(nodes)
                if !toFix.isEmpty {
                    Text(localization.L(L10n.Mods.depsToFix))
                        .font(AppDesign.Font.caption(.semibold)).foregroundStyle(.secondary)
                    ForEach(toFix) { node in
                        DependencyRowView(node: node, vm: vm, localization: localization, prominent: true)
                    }
                    Divider().padding(.vertical, 4)
                }
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

    /// Le libellé de l'onglet : « Dépendances (1 · 1 à régler) ». Les racines
    /// rendues (fusionnées pour un pack) et les liens non déclarés (A5-T6).
    static func tabTitle(viewModel: StarHubTHViewModel, mod: ModItem, localization: LocalizationStore) -> String {
        let roots = viewModel.dependencyTree(for: mod)
        let total = roots.count + viewModel.hiddenCodeIndex.undeclaredLinks(for: mod, installed: viewModel.scanStore.mods).count
        let toFix = DependencyTreeBuilder.toFix(roots).count
        let count = toFix == 0 ? "\(total)" : "\(total) · " + localization.plural(L10n.Mods.depsToFixCount, toFix)
        return "\(localization.L(L10n.Profiles.dependencies)) (\(count))"
    }
}

/// One node plus its children, indented under a thin leading guide rail. The
/// recursion (a view containing itself) is what gives arbitrary depth without
/// per-node `├─`/`└─` glyph bookkeeping.
struct DependencyNodeTree: View {
    let node: DependencyNode
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// E7 — les sous-niveaux repliés par défaut : l'optionnelle d'une
    /// dépendance ne pèse plus autant que la requise du mod.
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DependencyRowView(node: node, vm: vm, localization: localization)
            if !node.children.isEmpty {
                Button { expanded.toggle() } label: {
                    Label(localization.plural(L10n.Mods.depsIndirect, node.children.count),
                          systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).focusRing(cornerRadius: 4)
                .padding(.leading, 18).pointingHandCursor()
            }
            if expanded, !node.children.isEmpty {
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
    /// E7 — dans « À régler » : le geste en bouton plein.
    var prominent = false
    /// La dépendance dont l'activation attend une confirmation : smapi.io la
    /// signale cassée. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?
    /// Même rôle, source différente : un conflit déclaré ou observé dans le
    /// journal avec un mod déjà actif (tâche 9). Voir `ConflictActivationGate`.
    @State private var pendingConflict: ConflictActivation?

    var body: some View {
        HStack(spacing: 10) {
            // E7 — la carte s'ouvre par un vrai bouton (clavier, VoiceOver),
            // les gestes restent à côté, hors de son libellé.
            if let mod = node.resolved {
                Button { vm.navigationStore.setViewingModDetail(mod) } label: {
                    identity.contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusRing(cornerRadius: 6)
                .pointingHandCursor()
            } else {
                identity
            }
            actionButton
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(iconColor.opacity(0.25), lineWidth: 1))
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
    }

    private var identity: some View {
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
                    // « Requis » reste neutre une fois satisfait (E7).
                    let alarming = node.isRequired && node.status != .active
                    Text(node.isRequired ? localization.L(L10n.Profiles.required) : localization.L(L10n.Profiles.optional))
                        .font(AppDesign.Font.iconXXS(.bold))
                        .foregroundColor(alarming ? .orange : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((alarming ? Color.orange : Color.secondary).opacity(0.15))
                        .cornerRadius(3)
                    Text(statusText).font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Les jetons d'état (E7) : le jaune était celui du favori.
        case .active: return AppDesign.Color.installed
        case .disabled: return AppDesign.Color.paused
        case .missing: return node.isRequired ? AppDesign.Color.error : .secondary
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
        case .disabled, .missing:
            // R9 — les gestes de l'encart de la liste : activer, installer,
            // ouvrir la page ou chercher, par les gardes de cette rangée.
            DependencyFixActions(viewModel: vm, localization: localization, uniqueId: node.uniqueId,
                                 pendingActivation: $pendingActivation, pendingConflict: $pendingConflict,
                                 prominent: prominent)
        case .active:
            let link = node.resolved.map { vm.nexusLink(for: $0) } ?? ""
            if !link.isEmpty {
                Button(localization.L(L10n.Mods.nexusOpenPage)) {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderless).focusRing(cornerRadius: 4).controlSize(.small)
                .foregroundColor(.accentColor).pointingHandCursor()
            }
        }
    }
}
