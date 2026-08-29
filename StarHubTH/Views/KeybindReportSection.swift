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
///   effectivement été scanné **et** entièrement compris (voir `content`
///   plus bas — un lot avec des raccourcis non reconnus n'est pas un lot
///   sans conflit), sinon c'est un vert mensonger.
/// - Le service vit sur `StarHubTHViewModel.keybindScanService` (même
///   patron que `smapiInstaller`), pas dans un `@StateObject` de cette vue :
///   `SystemAlertsView` vit dans une chaîne if/else if de `MainView`, pas
///   dans un `Group` à identité stable, donc revenir sur l'onglet la
///   détruirait et la recréerait à chaque fois — un `@StateObject` posé ici
///   repartirait toujours de zéro (ronde de revue 1, constat 1). Le rapport
///   publié survit ainsi au changement d'onglet.
/// - `.onAppear` appelle `KeybindScanService.scanIfNeeded`, pas `scan`
///   directement : le service compare une signature du parc courant à
///   celle de son dernier scan lancé, et ne relance que si elle diffère —
///   sinon un rapport calculé une fois resterait affiché pour toujours,
///   périmé dès qu'un mod change d'état entre deux visites de l'onglet
///   (ronde de revue 2, constat 3). Le bouton « Relancer l'analyse » reste
///   inconditionnel, lui : voir `header`.
struct KeybindReportSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var service: KeybindScanService

    init(vm: StarHubTHViewModel) {
        self.vm = vm
        self.service = vm.keybindScanService
    }

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
            // Le rapport publié survit au changement d'onglet (le service
            // vit sur le ViewModel), mais un rapport qui ne bougerait plus
            // jamais après le tout premier scan serait périmé dès qu'un mod
            // change d'état ailleurs dans l'app : `scanIfNeeded` compare une
            // signature du parc courant à celle du dernier scan lancé, et
            // ne relance que si elle diffère (ronde de revue 2, constat 3).
            // Le bouton « Relancer l'analyse » reste inconditionnel : voir
            // `header`.
            service.scanIfNeeded(mods: vm.mods, gameDir: vm.gameDir)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
            Text(vm.L(L10n.Keybinds.title))
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: AppDesign.Spacing.sm)
            Button(action: { service.scan(mods: vm.mods, gameDir: vm.gameDir) }) {
                Label(vm.L(L10n.Keybinds.rescan), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, AppDesign.Spacing.md)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHandCursor()
            .disabled(service.isScanning || vm.gameDir.isEmpty)
            .layoutPriority(1)
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
            // Le vert n'affirme l'absence de conflit que si le lot a aussi
            // été entièrement compris : des raccourcis non reconnus sont
            // eux aussi un signal, pas un simple à-côté du vert (ronde de
            // revue 1, constat 2).
            if report.collisions.isEmpty && report.gameConflicts.isEmpty && report.unrecognized.isEmpty {
                statusRow(icon: "checkmark.circle.fill", color: .green,
                          text: vm.L(L10n.Keybinds.empty))
            } else {
                if !report.collisions.isEmpty {
                    collisionsGroup(report.collisions)
                }
                if !report.gameConflicts.isEmpty {
                    // La réserve reste visible même groupe replié : c'est
                    // elle qui évite la fausse alerte chez qui a remappé
                    // ses touches (ronde de revue 1, constat 3).
                    Text(vm.L(L10n.Keybinds.gameCaveat))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    gameConflictsGroup(report.gameConflicts)
                }
                if !report.unrecognized.isEmpty {
                    unrecognizedGroup(report.unrecognized)
                }
            }
        }
        if report.pausedIgnored > 0 {
            Text(String(format: vm.L(L10n.Keybinds.pausedNote), report.pausedIgnored))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        if !report.catalogModsIgnored.isEmpty {
            // Défaut 1 (tâche 6) : une exclusion muette est un mensonge par
            // omission — ModShortcutReferenceHub pesait 12 des 29
            // collisions et 9 des 20 conflits jeu avant cette règle.
            //
            // Ronde de correction 1 : la chaîne parle du champ (« documentation
            // de raccourcis »), pas du mod — un mod dont une forme de chemin
            // est écartée peut très bien garder une vraie collision ailleurs
            // (le cas réel : `K` entre le Hub et Swim, affiché juste au-dessus
            // dans le groupe des collisions). Le compte est posé **avant** les
            // noms : `.truncationMode(.middle)` peut couper les noms si la
            // liste est longue, mais jamais le nombre en tête de phrase — le
            // plancher d'information que le brief demandait survit donc à la
            // troncature.
            Text(String(format: vm.L(L10n.Keybinds.catalogNote),
                        report.catalogModsIgnored.count,
                        report.catalogModsIgnored.joined(separator: ", ")))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    /// Défaut 2 (tâche 6) : un mod qui lie la même touche dans deux
    /// réglages différents produit deux `ModUse` distincts côté données
    /// (légitime — les `keyPath` diffèrent, la déduplication par
    /// `(modID, keyPath)` est correcte), mais l'écran ne doit le montrer
    /// qu'une fois par ligne, chemins réunis, sinon ça se lit comme un
    /// doublon d'affichage. Le critère de collision lui-même ne change
    /// pas : il reste `Set(uses.map(\.modID)).count >= 2`. Le regroupement
    /// lui-même (`groupedUses`) est une logique pure : elle vit dans
    /// `KeybindScanner`, sous `swift test` — cette vue ne fait que
    /// formater le résultat.
    private func groupedUseLine(_ use: KeybindScanner.GroupedUse) -> some View {
        Text("· \(use.modName) (\(use.keyPaths.map { $0.joined(separator: ".") }.joined(separator: ", ")))")
            .font(.system(size: 12)).foregroundColor(.secondary)
            .lineLimit(1).truncationMode(.middle)
    }

    private func collisionsGroup(_ collisions: [KeybindScanner.KeybindCollision]) -> some View {
        DisclosureGroup(isExpanded: expansion("collisions",
                                               defaultOpen: collisions.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(collisions, id: \.combo) { collision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collision.combo.display).font(.system(size: 13, weight: .medium))
                        ForEach(KeybindScanner.groupedUses(collision.uses)) { use in
                            groupedUseLine(use)
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
                ForEach(conflicts, id: \.control.name) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        // La touche en cause d'abord — c'est elle qui est
                        // actionnable ; le nom de champ C# ensuite, en
                        // second plan (ronde de revue 1, constat 4). Les 27
                        // noms de contrôles restent non traduits : chantier
                        // à part, porté ailleurs.
                        //
                        // Séparateur " / ", pas " + " : `control.buttons`
                        // liste des touches *alternatives* pour un même
                        // contrôle (ex. actionButton = X ou clic droit), pas
                        // une combinaison à presser ensemble — alors que
                        // " + " signifie déjà « ensemble » quarante pixels
                        // plus haut dans le groupe des collisions
                        // (`KeybindCombo.display`). Le scan n'a matché
                        // qu'une seule de ces touches, mais laquelle n'est
                        // pas portée par `GameControlConflict` (ronde de
                        // revue 2, constat 1).
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Text(conflict.control.buttons.joined(separator: " / "))
                                .font(.system(size: 13, weight: .medium))
                            Text(conflict.control.name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        ForEach(KeybindScanner.groupedUses(conflict.uses)) { use in
                            groupedUseLine(use)
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
