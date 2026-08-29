import SwiftUI

/// Le rapport de raccourcis, en section de l'onglet Alertes système
/// (spec §8). MVP lecture seule : aucun lien vers l'éditeur — le
/// changement d'onglet remet les états de détail à nil (piège connu).
///
/// Écarts au canevas du brief (mesure de la tâche 0) :
/// - Groupes repliés (`DisclosureGroup`) au lieu d'une liste plate : le parc
///   réactivé en entier rend jusqu'à 50 collisions, au-dessus du seuil de 40
///   posé par le brief lui-même. L'état d'ouverture vit dans un dictionnaire
///   plutôt qu'un `@State` scalaire : le rapport arrive de façon
///   asynchrone (`KeybindScanService.scan`), donc rien à initialiser depuis
///   lui à la création de la vue.
/// - Deux états de plus que le canevas (`noGameDir`, `noModsScanned`) : le
///   vert « aucun conflit » ne doit sortir que si quelque chose a
///   effectivement été scanné, sinon c'est un vert mensonger.
/// - `.onAppear` ne relance le scan que si aucun rapport n'est encore
///   publié : changer d'onglet détruit et recrée ce `@StateObject`, sans
///   cette garde les ~545 `config.json` du parc seraient relus à chaque
///   retour sur l'onglet.
struct KeybindReportSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    @StateObject private var service = KeybindScanService()

    /// Sous ce compte, un groupe s'ouvre par défaut ; au-dessus, il reste
    /// replié (décision de la tâche 0 : le parc réactivé dépasse le seuil
    /// de 40 collisions posé par le brief).
    private static let autoExpandThreshold = 10

    @State private var expanded: [String: Bool] = [:]
    private func expansion(_ key: String, defaultOpen: Bool) -> Binding<Bool> {
        Binding(get: { expanded[key] ?? defaultOpen }, set: { expanded[key] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            header
            if vm.gameDir.isEmpty {
                statusRow(icon: "exclamationmark.triangle.fill", color: .yellow,
                          text: vm.L(L10n.Keybinds.noGameDir))
            } else if service.isScanning {
                HStack(spacing: AppDesign.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(vm.L(L10n.Keybinds.scanning))
                        .foregroundColor(.secondary)
                }
            } else if let report = service.report {
                content(report)
            }
        }
        .padding(AppDesign.Spacing.lg)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .onAppear {
            // Garde : sans elle, revenir sur l'onglet Alertes système relit
            // tout le parc à chaque fois (le @StateObject est recréé).
            guard service.report == nil else { return }
            service.scan(mods: vm.mods, gameDir: vm.gameDir)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
            Text(vm.L(L10n.Keybinds.title)).font(.system(size: 14, weight: .bold))
            Spacer()
            Button(action: { service.scan(mods: vm.mods, gameDir: vm.gameDir) }) {
                Label(vm.L(L10n.Keybinds.rescan), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppDesign.Spacing.md)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHandCursor()
            .disabled(service.isScanning || vm.gameDir.isEmpty)
        }
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).foregroundColor(.secondary)
        }
    }

    // Le type du rapport est imbriqué dans le scanner (constat de T3) :
    // nom qualifié obligatoire hors de Core.
    @ViewBuilder private func content(_ report: KeybindScanner.KeybindReport) -> some View {
        if report.scannedMods == 0 {
            // Rapport présent mais rien à en tirer : aucun mod actif ne
            // porte de config.json. Distinct du vert « aucun conflit » —
            // là, on n'a rien scanné du tout.
            statusRow(icon: "info.circle", color: .secondary,
                      text: vm.L(L10n.Keybinds.noModsScanned))
        } else {
            Text(String(format: vm.L(L10n.Keybinds.counters),
                        report.scannedMods, report.keybindCount))
                .font(.system(size: 12)).foregroundColor(.secondary)
            if report.collisions.isEmpty && report.gameConflicts.isEmpty {
                statusRow(icon: "checkmark.circle.fill", color: .green,
                          text: vm.L(L10n.Keybinds.empty))
            } else {
                if !report.collisions.isEmpty {
                    collisionsGroup(report.collisions)
                }
                if !report.gameConflicts.isEmpty {
                    gameConflictsGroup(report.gameConflicts)
                }
            }
        }
        if !report.unrecognized.isEmpty {
            unrecognizedGroup(report.unrecognized)
        }
        if report.pausedIgnored > 0 {
            Text(String(format: vm.L(L10n.Keybinds.pausedNote), report.pausedIgnored))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func collisionsGroup(_ collisions: [KeybindScanner.KeybindCollision]) -> some View {
        DisclosureGroup(isExpanded: expansion("collisions",
                                               defaultOpen: collisions.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(collisions, id: \.combo) { collision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collision.combo.display).font(.system(size: 13, weight: .medium))
                        ForEach(collision.uses, id: \.self) { use in
                            Text("· \(use.modName) (\(use.keyPath.joined(separator: ".")))")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(String(format: vm.L(L10n.Keybinds.collisionsHeader), collisions.count))
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func gameConflictsGroup(_ conflicts: [KeybindScanner.GameControlConflict]) -> some View {
        DisclosureGroup(isExpanded: expansion("game",
                                               defaultOpen: conflicts.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(vm.L(L10n.Keybinds.gameCaveat))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(conflicts, id: \.control.name) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.control.name).font(.system(size: 13, weight: .medium))
                        ForEach(conflict.uses, id: \.self) { use in
                            Text("· \(use.modName) (\(use.keyPath.joined(separator: ".")))")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(String(format: vm.L(L10n.Keybinds.gameHeader), conflicts.count))
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func unrecognizedGroup(_ items: [KeybindScanner.UnrecognizedKeybind]) -> some View {
        DisclosureGroup(isExpanded: expansion("unrecognized",
                                               defaultOpen: items.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(items, id: \.self) { u in
                    Text("· \(u.modName) · \(u.keyPath.joined(separator: ".")) = \(u.raw)")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(String(format: vm.L(L10n.Keybinds.unrecognizedHeader), items.count))
                .font(.system(size: 13, weight: .semibold))
        }
    }
}
