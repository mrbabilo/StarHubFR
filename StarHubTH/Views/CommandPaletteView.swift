import SwiftUI

/// La palette ⌘K — une superposition, pas une feuille ni une fenêtre.
///
/// **Elle ne route jamais elle-même** : la sélection passe par le ViewModel,
/// et MainView applique. Un saut vers une fiche posé avant le changement
/// d'onglet serait effacé par la remise à zéro des états de détail (B3-T4).
///
/// **Elle n'écrit jamais** : naviguer seulement. Une frappe rapide ne doit pas
/// pouvoir toucher à `Mods/`.
struct CommandPaletteView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var isPresented: Bool
    @AppStorage("showThaiTranslationHub") private var showThaiTranslationHub = false

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    /// Le parc converti **une seule fois**, à l'ouverture.
    ///
    /// ⚠️ En propriété calculée, il serait reconstruit à chaque accès — et
    /// `body` y touche plusieurs fois par rendu. Soit tout le parc remappé par
    /// ligne affichée, à chaque frappe. Le parc ne bouge pas pendant que la
    /// palette est ouverte ; s'il bouge quand même, le cas est déjà traité :
    /// un mod disparu résout à `nil` et rien ne s'ouvre.
    @State private var entries: [CommandPaletteEntry] = []

    private func buildEntries() -> [CommandPaletteEntry] {
        var out: [CommandPaletteEntry] = SidebarOrder
            .visible(showThaiHub: showThaiTranslationHub)
            .map { CommandPaletteEntry.forDestination($0, title: localization.L($0.labelKey)) }
        out += vm.scanStore.mods.flattenedMods.map(CommandPaletteEntry.forMod)
        out += vm.modProfiles.map { CommandPaletteEntry.forProfile(name: $0.name) }
        out += vm.saves.map {
            CommandPaletteEntry.forSave(playerName: $0.playerName,
                                        farmName: $0.farmName)
        }
        return out
    }

    private var results: [CommandPaletteEntry] {
        CommandPaletteSearch.rank(query, in: entries)
    }

    /// L'ordre **affiché**, et le seul que `selection` indexe.
    ///
    /// ⚠️ `rank` trie par force de correspondance d'abord : une destination
    /// faiblement appariée sort après des mods bien appariés, et une nature
    /// peut réapparaître plus bas. Grouper à l'affichage sans regrouper ici
    /// ferait **doublonner les en-têtes**. On regroupe donc par nature en
    /// gardant l'ordre du classement à l'intérieur de chaque groupe — `sorted`
    /// n'étant pas stable en Swift, on trie sur la paire (nature, rang).
    private var displayed: [CommandPaletteEntry] {
        results.enumerated()
            .sorted { a, b in
                a.element.kind != b.element.kind
                    ? a.element.kind < b.element.kind
                    : a.offset < b.offset
            }
            .map(\.element)
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
                .font(.system(size: 16))
                .focused($fieldFocused)
                .onSubmit { activate() }
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
                                .font(.system(size: 11, weight: .semibold))
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
            .font(.system(size: 13))
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
    private func activate() {
        let rows = displayed
        guard rows.indices.contains(selection) else {
            close()
            return
        }
        let e = rows[selection]
        switch e.kind {
        case .destination:
            // L'id est "dest:" + rawValue — on remonte à la destination.
            let raw = String(e.id.dropFirst("dest:".count))
            if let d = SidebarDestination(rawValue: raw) { vm.requestTab(d) }
        case .mod:
            // Le canal B3-T4 déjà en place. Un mod disparu entre l'ouverture
            // et ↩ résout à nil : rien ne s'ouvre, plutôt qu'une fiche
            // fantôme — et la palette se ferme quand même.
            vm.openReportDetail(for: String(e.id.dropFirst("mod:".count)))
        case .profile:
            // Pas de canal « ce profil » : on conduit à l'onglet, décision de
            // spec §7. Ajouter deux canaux pour un besoin non mesuré est ce
            // que ce dépôt regrette ailleurs.
            vm.requestTab(.profiles)
        case .save:
            vm.requestTab(.saves)
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
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let s = entry.subtitle {
                    Text(s)
                        .font(.system(size: 11))
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
