import SwiftUI

/// La palette ⌘K — une superposition, pas une feuille ni une fenêtre.
///
/// **Elle ne route jamais elle-même** : la sélection passe par le ViewModel,
/// et MainView applique. Un saut vers une fiche posé avant le changement
/// d'onglet serait effacé par la remise à zéro des états de détail (B3-T4).
///
/// **Elle n'écrit jamais dans `Mods/`.** Ses trois gestes (N-08, décision de
/// l'auteur qui revient sur I-T2) sont ceux du menu : vérifier les mises à
/// jour, ouvrir la feuille d'installation, lancer le jeu. Une action ne sort
/// que sur un début de titre, et ne passe devant que mieux appariée que tout
/// le reste (`CommandPaletteSearch.displayed`) : une frappe courte ouvre un
/// mod, pas un geste.
struct CommandPaletteView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool
    @Environment(\.openWindow) private var openWindow

    /// Le parc converti **une seule fois**, à l'ouverture.
    ///
    /// ⚠️ En propriété calculée, il serait reconstruit à chaque accès — et
    /// `body` y touche plusieurs fois par rendu. Soit tout le parc remappé par
    /// ligne affichée, à chaque frappe. Le parc ne bouge pas pendant que la
    /// palette est ouverte ; s'il bouge quand même, le cas est déjà traité :
    /// un mod disparu résout à `nil` et rien ne s'ouvre.
    @State private var entries: [CommandPaletteEntry] = []

    private func buildEntries() -> [CommandPaletteEntry] {
        var out: [CommandPaletteEntry] = SidebarOrder.all.map { entry in
            let shortTitle = entry.shortLabelKey.map { localization.L($0) }
            return CommandPaletteEntry.forDestination(
                entry,
                title: localization.L(entry.labelKey),
                shortTitle: shortTitle
            )
        }
        // L'onglet Performances n'est pas une destination de la barre
        // latérale : une entrée à part (lot D de l'audit Performances).
        out.append(CommandPaletteEntry(id: "dest:\(SidebarDestination.logs.rawValue)#performance",
                                       kind: .destination,
                                       title: localization.L(L10n.Logs.segmentPerformance),
                                       subtitle: localization.L(L10n.Logs.logs),
                                       icon: "gauge.with.dots.needle.67percent"))
        // L'aide intégrée : une fenêtre, pas une destination.
        out.append(CommandPaletteEntry(id: "dest:help", kind: .destination,
                                       title: localization.L(L10n.Help.title),
                                       subtitle: nil, icon: "questionmark.circle"))
        out += vm.scanStore.mods.flattenedMods.map(CommandPaletteEntry.forMod)
        out += vm.modProfiles.map {
            CommandPaletteEntry.forProfile(
                name: $0.name, id: $0.id,
                subtitle: localization.L($0.id == vm.activeProfileId ? L10n.Profiles.active
                                                                     : L10n.Palette.profileHint))
        }
        out += vm.saves.map {
            CommandPaletteEntry.forSave(playerName: $0.playerName, farmName: $0.farmName,
                                        folderName: $0.folderName)
        }
        // N-08 — les gestes du menu, leur raccourci en sous-titre.
        out += [("check", localization.L(L10n.Updates.nexusCheckButton), "⇧⌘U", "arrow.triangle.2.circlepath"),
                ("install", localization.L(L10n.ModInstall.installButton) + "…", "⌘O", "square.and.arrow.down"),
                ("launch", localization.L(L10n.Main.launchGame), "⌘R", "play.fill")].map { id, title, keys, icon in
            CommandPaletteEntry(id: "action:\(id)", kind: .action,
                                title: title, subtitle: keys, icon: icon)
        }
        return out
    }

    /// L'ordre **affiché**, regroupé par nature, et le seul que `selection`
    /// indexe (`CommandPaletteSearch.displayed`, testé).
    private var displayed: [CommandPaletteEntry] {
        CommandPaletteSearch.displayed(query, in: entries)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Le voile : cliquer à côté ferme, comme partout ailleurs.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .frame(width: 560)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 24)
                .padding(.top, 90)
        }
        .onAppear { entries = buildEntries(); fieldFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            field
            if !displayed.isEmpty {
                Divider()
                list
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                emptyState
            }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(localization.L(L10n.Palette.placeholder), text: $query)
                .textFieldStyle(.plain)
                .font(AppDesign.Font.headline)
                .focused($fieldFocused)
                .onSubmit { activate() }
                // N-12 — ⌘↩ active un profil ; ↩ seul n'en ouvre que l'aperçu.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    activate(applyingProfile: true)
                    return .handled
                }
                // ⚠️ Les gestionnaires sont posés **sur le champ**, pas sur le
                // ZStack : le champ a le focus (c'est tout l'intérêt de
                // `fieldFocused`), et une flèche tapée dedans y déplace le
                // curseur au lieu de remonter la hiérarchie. Rendre
                // `.handled` intercepte avant ce comportement par défaut.
                .onKeyPress(.upArrow) {
                    selection = max(0, selection - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    // `count - 1` vaut −1 sur une liste vide : borner à 0
                    // sinon `selection` part en négatif. `activate()` s'en
                    // garde déjà, mais un état absurde finit toujours par
                    // ressortir ailleurs.
                    selection = max(0, min(displayed.count - 1, selection + 1))
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Le libellé de section d'une nature — les quatre clés `palette_section_*`.
    private func sectionTitle(_ kind: CommandPaletteEntry.Kind) -> String {
        switch kind {
        case .destination: return localization.L(L10n.Palette.sectionDestinations)
        case .mod:         return localization.L(L10n.Palette.sectionMods)
        case .profile:     return localization.L(L10n.Palette.sectionProfiles)
        case .save:        return localization.L(L10n.Palette.sectionSaves)
        case .action:      return localization.L(L10n.Palette.sectionActions)
        }
    }

    private var list: some View {
        // Une seule dérivation par rendu : `displayed` reclasse tout le parc,
        // et `body` la lirait sinon une fois par ligne.
        let rows = displayed
        // ⚠️ `ScrollViewReader` n'est pas un ornement : sans lui, ↑/↓
        // déplacent bien la sélection mais la liste ne bouge pas, et la ligne
        // choisie sort du cadre dès la sixième — on pilote une surbrillance
        // qu'on ne voit plus. Relevé à l'écran par l'auteur le 2026-09-10 ;
        // aucun test d'ici ne l'atteint.
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Identité par `id` composé, jamais par position : l'@State
                    // d'une ligne fuirait vers sa voisine à chaque frappe.
                    //
                    // `rows` est plate — c'est elle que ↑/↓ parcourent et que
                    // `selection` indexe — mais **regroupée par nature** : sans
                    // ce regroupement, `rank` renvoie les natures entrelacées
                    // et les en-têtes doublonneraient.
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, e in
                        if i == 0 || rows[i - 1].kind != e.kind {
                            Text(sectionTitle(e.kind))
                                .font(AppDesign.Font.footnote(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, i == 0 ? 8 : 12)
                                .padding(.bottom, 2)
                        }
                        CommandPaletteRow(entry: e, isSelected: i == selection)
                            .contentShape(.rect)
                            // Cible explicite de `scrollTo` : ne pas compter
                            // sur l'identité que `ForEach` pose seule.
                            .id(e.id)
                            .onTapGesture { selection = i; activate() }
                    }
                }
            }
            .frame(maxHeight: 380)
            // Nouvelle requête : les résultats changent entièrement, on
            // remonte. `onChange(of: selection)` ne suffit pas — si la
            // sélection était déjà à 0, il ne se déclenche pas, et la liste
            // resterait là où la molette l'avait laissée.
            .onChange(of: query) { _, _ in
                guard let first = rows.first else { return }
                proxy.scrollTo(first.id, anchor: .top)
            }
            .onChange(of: selection) { _, i in
                guard rows.indices.contains(i) else { return }
                // `.center` plutôt que `.top` : la ligne suivante et la
                // précédente restent visibles, on garde le contexte. Pas
                // d'animation — une frappe maintenue en empilerait une par
                // pression et la liste traînerait derrière le doigt.
                proxy.scrollTo(rows[i].id, anchor: .center)
            }
        }
    }

    /// L'état vide **dit pourquoi** il est vide — règle posée par H-T7.
    private var emptyState: some View {
        Text(String(format: localization.L(L10n.Palette.noResults), query))
            .font(AppDesign.Font.body)
            .foregroundColor(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func close() {
        isPresented = false
        query = ""
        selection = 0
    }

    /// Ouvre la sélection courante. Chaque nature passe par le ViewModel.
    private func activate(applyingProfile: Bool = false) {
        let rows = displayed
        guard rows.indices.contains(selection) else {
            close()
            return
        }
        let e = rows[selection]
        let navigation = vm.navigationStore
        switch e.kind {
        case .destination:
            // L'id est "dest:" + rawValue — on remonte à la destination.
            let raw = String(e.id.dropFirst("dest:".count))
            if raw == "help" {
                navigation.pendingHelpSection = nil
                openWindow(id: AppWindowID.help)
            } else if raw.hasSuffix("#performance") {
                navigation.openPerformance()
            } else if let d = SidebarDestination(rawValue: raw) { navigation.requestTab(d) }
        case .mod:
            // Le canal B3-T4 déjà en place. Un mod disparu entre l'ouverture
            // et ↩ résout à nil : rien ne s'ouvre, plutôt qu'une fiche
            // fantôme — et la palette se ferme quand même.
            vm.openReportDetail(for: String(e.id.dropFirst("mod:".count)), door: .palette)
        case .profile:
            // N-12 (décision de l'auteur, revient sur I-T5) : ↩ ouvre l'aperçu,
            // rien ne bouge ; ⌘↩ active, par le chemin du bouton « Activer »
            // (gardes jeu lancé, reprise R2, alerte d'empreintes A1-T9).
            guard let id = UUID(uuidString: String(e.id.dropFirst("profile:".count))) else { break }
            if applyingProfile, id != vm.activeProfileId {
                vm.applyProfile(id: id)
            } else {
                navigation.openProfilePreview(id)
            }
        case .save:
            // N-08 (revient sur I-T2) : la page de la partie, sur Détails.
            navigation.requestSave(folderName: String(e.id.dropFirst("save:".count)))
        case .action:
            // Les chemins du menu, gardes comprises (vérification déjà en
            // cours, dossier du jeu absent, benchmark).
            switch e.id {
            case "action:check":   vm.checkNexusUpdates()
            case "action:install": navigation.requestInstall()
            default:               _ = vm.launchGame()
            }
        }
        close()
    }
}

/// Une ligne de résultat. Sortie de la vue principale pour ne pas saturer le
/// type-checker — un `body` trop dense compile en minutes ici.
private struct CommandPaletteRow: View {
    let entry: CommandPaletteEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .frame(width: 18)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(AppDesign.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let s = entry.subtitle {
                    Text(s)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
