import SwiftUI

/// Le rapport de raccourcis, en section de l'onglet Alertes système
/// (spec §8). Chaque ligne de mod cité mène à son éditeur de configuration
/// (`configButton`) : signaler un conflit sans permettre d'y remédier
/// laissait l'utilisateur retrouver le mod à la main dans la liste.
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
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var service: KeybindScanService
    /// La bascule d'onglet fait partie du geste « ouvrir la config » : le
    /// bouton d'une ligne vit sur les Alertes système, l'éditeur sur Mods.
    @Binding var currentTab: SidebarDestination

    init(vm: StarHubTHViewModel, localization: LocalizationStore, currentTab: Binding<SidebarDestination>) {
        self.localization = localization
        self.vm = vm
        self.service = vm.keybindScanService
        self._currentTab = currentTab
    }

    /// Sous ce compte, un groupe s'ouvre par défaut ; au-dessus, il reste
    /// replié (décision de la tâche 0 : le parc réactivé dépasse le seuil
    /// de 40 collisions posé par le brief).
    private static let autoExpandThreshold = 10

    @State private var expanded: [String: Bool] = [:]
    private func expansion(_ key: String, defaultOpen: Bool) -> Binding<Bool> {
        Binding(get: { expanded[key] ?? defaultOpen }, set: { expanded[key] = $0 })
    }

    /// Refonte du 2026-10-02 : des cartes par rôle, dans l'ordre de la
    /// gravité — le verdict, ce qui est cassé, l'outil (clavier),
    /// l'inventaire, puis ce que l'analyse a écarté. Le `ScrollViewReader`
    /// vit ici : le `ScrollView` qui défile est celui de `SystemAlertsView`,
    /// et une tuile ouvre son groupe puis y défile.
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    header
                    if vm.gameDir.isEmpty {
                        statusRow(icon: "exclamationmark.triangle.fill", color: AppDesign.Color.warning,
                                  text: localization.L(L10n.Keybinds.noGameDir))
                    } else if service.isScanning {
                        HStack(spacing: AppDesign.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text(localization.L(L10n.Keybinds.scanning))
                                .foregroundColor(.secondary)
                        }
                    } else if let report = service.report {
                        summary(report, proxy: proxy)
                    }
                }
                .cardSurface(padding: AppDesign.Spacing.lg)
                if !vm.gameDir.isEmpty, !service.isScanning, let report = service.report {
                    sections(report)
                }
            }
        }
        .onAppear {
            // Le rapport publié survit au changement d'onglet (le service
            // vit sur le ViewModel), mais un rapport qui ne bougerait plus
            // jamais après le tout premier scan serait périmé dès qu'un mod
            // change d'état ailleurs dans l'app : `scanIfNeeded` compare une
            // signature du parc courant à celle du dernier scan lancé, et
            // ne relance que si elle diffère (ronde de revue 2, constat 3).
            // Le bouton « Relancer l'analyse » reste inconditionnel : voir
            // `header`.
            service.scanIfNeeded(mods: vm.scanStore.mods, gameDir: vm.gameDir)
        }
    }

    /// Le titre est celui de l'onglet des Alertes système : la section ne
    /// le répète pas, elle garde son action.
    private var header: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Spacer(minLength: AppDesign.Spacing.sm)
            Button(action: { if let report = service.report { exportReport(report) } }) {
                Label(localization.L(L10n.Keybinds.export), systemImage: "square.and.arrow.up")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
            .disabled(service.report == nil)
            .help(localization.L(L10n.Keybinds.exportHint))
            Button(action: { service.scan(mods: vm.scanStore.mods, gameDir: vm.gameDir) }) {
                Label(localization.L(L10n.Keybinds.rescan), systemImage: "arrow.clockwise")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
    /// Le verdict : compteurs, puis le vert — qui n'affirme l'absence de
    /// conflit que si le lot a été entièrement compris (aucun non reconnu,
    /// aucun co-déclenchement : ronde de revue 1, constat 2) — ou les
    /// tuiles, qui mènent chacune à leur groupe.
    @ViewBuilder private func summary(_ report: KeybindScanner.KeybindReport,
                                      proxy: ScrollViewProxy) -> some View {
        if report.scannedMods == 0 {
            // Rien d'analysé : distinct du vert « aucun conflit ».
            statusRow(icon: "info.circle", color: .secondary,
                      text: localization.L(L10n.Keybinds.noModsScanned))
        } else {
            Text(String(format: localization.L(L10n.Keybinds.counters),
                        report.scannedMods, report.keybindCount))
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
            if report.problemCount == 0 && report.unrecognized.isEmpty
                && report.subsetOverlaps.isEmpty {
                statusRow(icon: "checkmark.circle.fill", color: AppDesign.Color.success,
                          text: localization.L(L10n.Keybinds.empty))
            } else {
                KeybindSummaryTiles(report: report, L: localization.L) { key in
                    expanded[key] = true
                    withAnimation(Motion.animation(.easeInOut(duration: 0.25))) {
                        proxy.scrollTo(key, anchor: .top)
                    }
                }
            }
        }
    }

    /// Les sections sous le verdict, par gravité : cassé (collisions),
    /// à faire (jeu, non reconnus), information (co-déclenchements,
    /// latentes — hors de la branche « problèmes » exprès : elles
    /// s'affichent même quand tout est vert), puis l'outil et l'inventaire.
    @ViewBuilder private func sections(_ report: KeybindScanner.KeybindReport) -> some View {
        let problems = !report.collisions.isEmpty || !report.gamepadCollisions.isEmpty
            || !report.gameConflicts.isEmpty || !report.unrecognized.isEmpty
            || !report.subsetOverlaps.isEmpty || !report.latentCollisions.isEmpty
        if report.scannedMods > 0, problems {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                if !report.collisions.isEmpty {
                    collisionsGroup(report.collisions, key: "collisions",
                                    header: L10n.Keybinds.collisionsHeader).id("collisions")
                }
                if !report.gamepadCollisions.isEmpty {
                    // C4-T7 — pas une collision clavier ; sans effet si le jeu a coupé la manette.
                    collisionsGroup(report.gamepadCollisions, key: "gamepad",
                                    header: report.gamepadOff ? L10n.Keybinds.gamepadOffHeader
                                        : L10n.Keybinds.gamepadHeader).id("gamepad")
                }
                if !report.gameConflicts.isEmpty {
                    // La réserve reste visible même groupe replié : c'est
                    // elle qui évite la fausse alerte chez qui a remappé
                    // ses touches (ronde de revue 1, constat 3).
                    Text(localization.L(report.gameControlsSource.caveatKey))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    gameConflictsGroup(report.gameConflicts).id("game")
                }
                if !report.unrecognized.isEmpty {
                    unrecognizedGroup(report.unrecognized).id("unrecognized")
                }
                if !report.subsetOverlaps.isEmpty {
                    subsetOverlapsGroup(report.subsetOverlaps)
                }
                if !report.latentCollisions.isEmpty {
                    latentCollisionsGroup(report.latentCollisions)
                }
            }
            .cardSurface(padding: AppDesign.Spacing.lg)
        }
        if !report.settings.isEmpty {
            KeybindKeyboardGroup(localization: localization, settings: report.settings,
                                 isExpanded: expansion("keyboard", defaultOpen: true),
                                 openConfig: { openConfig($0, $1) })
                .cardSurface(padding: AppDesign.Spacing.lg)
            // C4-T13 — l'inventaire, replié par défaut : ce n'est pas un
            // signal.
            KeybindOverviewGroup(localization: localization, bindings: report.settings,
                                 isExpanded: expansion("overview", defaultOpen: false),
                                 openConfig: { openConfig($0, $1) })
                .cardSurface(padding: AppDesign.Spacing.lg)
        }
        // Une exclusion muette est un mensonge par omission : les notes
        // restent visibles, regroupées en pied, compte avant les noms.
        KeybindExclusionNotes(report: report, localization: localization)
    }

    /// L'en-tête d'un groupe : glyphe de gravité, couleur du sens, titre.
    private func groupLabel(_ format: String, _ count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon).foregroundColor(tint)
            Text(String(format: localization.L(format), count))
                .font(AppDesign.Font.body(.semibold))
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
        HStack(spacing: AppDesign.Spacing.xs) {
            // C4-T7 — dans les collisions latentes, le lecteur doit voir qui
            // est en pause : c'est LUI qu'il faut activer pour que le conflit
            // naisse.
            Text("· \(use.modName)\(use.isActive ? "" : " (\(localization.L(L10n.Keybinds.pausedSuffix)))") (\(use.keyPaths.map { $0.joined(separator: ".") }.joined(separator: ", ")))")
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            configButton(modID: use.modID, keyPath: use.keyPaths.first)
        }
    }

    /// Voir `KeybindConfigButton` : partagé avec la vue « tous les
    /// raccourcis » (C4-T13). La keyPath de la ligne vise le réglage précis
    /// dans l'éditeur (scroll + surlignage) ; `nil` sur les lignes qui en
    /// réunissent plusieurs — l'éditeur s'ouvre en haut, comme avant.
    private func configButton(modID: String, keyPath: [String]? = nil) -> some View {
        KeybindConfigButton(localization: localization) { openConfig(modID, keyPath) }
    }

    /// Le geste « ouvrir la config » d'une ligne. La demande doit traverser
    /// le changement d'onglet, qui remet `editingModConfig` à nil (piège
    /// documenté dans `MainView`) : elle passe par
    /// `navigationStore.pendingConfigFocus`, consommé dans le `onChange`
    /// **après** la remise à zéro — même patron que `pendingTranslationFocus`.
    private func openConfig(_ modID: String, _ keyPath: [String]?) {
        if vm.openModConfig(forFolder: modID, keyPath: keyPath) {
            currentTab = .mods
        }
    }

    private func collisionsGroup(_ collisions: [KeybindScanner.KeybindCollision],
                                 key: String, header: String) -> some View {
        DisclosureGroup(isExpanded: expansion(key,
                                               defaultOpen: collisions.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(collisions, id: \.combo) { collision in
                    VStack(alignment: .leading, spacing: 2) {
                        KeybindKeyChip(text: collision.combo.display)
                        ForEach(KeybindScanner.groupedUses(collision.uses)) { use in
                            groupedUseLine(use)
                        }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            groupLabel(header, collisions.count, icon: KeybindConflictStyle.glyph,
                       tint: KeybindConflictStyle.color(.mods))
        }
    }

    /// C4-T7 — le co-déclenchement au geste long : « F8 » part aussi quand
    /// « LeftControl + F8 » est tenu. L'aide tient lieu d'explication ; les
    /// deux combinaisons sont posées sur une ligne, le plus court en premier.
    private func subsetOverlapsGroup(_ overlaps: [KeybindScanner.SubsetOverlap]) -> some View {
        DisclosureGroup(isExpanded: expansion("subsets",
                                               defaultOpen: overlaps.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.Keybinds.subsetsHint))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                ForEach(overlaps, id: \.self) { overlap in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AppDesign.Spacing.xs) {
                            KeybindKeyChip(text: overlap.subset.display)
                            Text("⊂").foregroundColor(.secondary)
                            KeybindKeyChip(text: overlap.superset.display)
                        }
                        ForEach(KeybindScanner.groupedUses(overlap.uses)) { use in
                            groupedUseLine(use)
                        }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            groupLabel(L10n.Keybinds.subsetsHeader, overlaps.count, icon: "info.circle",
                       tint: AppDesign.Color.info)
        }
    }

    /// C4-T7 — l'angle mort du toggling : rien ne s'affiche ici qui soit
    /// déjà un conflit avéré, et rien de ce qui est affiché ne tire au jeu
    /// aujourd'hui. Chaque ligne dit qui est en pause.
    private func latentCollisionsGroup(_ collisions: [KeybindScanner.KeybindCollision]) -> some View {
        DisclosureGroup(isExpanded: expansion("latent",
                                               defaultOpen: collisions.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(collisions, id: \.combo) { collision in
                    VStack(alignment: .leading, spacing: 2) {
                        KeybindKeyChip(text: collision.combo.display)
                        ForEach(KeybindScanner.groupedUses(collision.uses)) { use in
                            groupedUseLine(use)
                        }
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            groupLabel(L10n.Keybinds.latentHeader, collisions.count, icon: "pause.circle",
                       tint: .secondary)
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
                                .font(AppDesign.Font.body(.medium))
                            Text(conflict.control.name)
                                .font(AppDesign.Font.footnote)
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
            groupLabel(L10n.Keybinds.gameHeader, conflicts.count, icon: KeybindConflictStyle.glyph,
                       tint: KeybindConflictStyle.color(.game))
        }
    }

    private func unrecognizedGroup(_ items: [KeybindScanner.UnrecognizedKeybind]) -> some View {
        DisclosureGroup(isExpanded: expansion("unrecognized",
                                               defaultOpen: items.count <= Self.autoExpandThreshold)) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(items, id: \.self) { u in
                    HStack(spacing: AppDesign.Spacing.xs) {
                        Text("· \(u.modName) · \(u.keyPath.joined(separator: ".")) = \(u.raw)")
                            .font(AppDesign.Font.caption).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        configButton(modID: u.modID)
                    }
                }
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            groupLabel(L10n.Keybinds.unrecognizedHeader, items.count, icon: "questionmark.circle",
                       tint: AppDesign.Color.warning)
        }
    }
}
