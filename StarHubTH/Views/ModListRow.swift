import SwiftUI

// Lignes, groupes et badges de la liste de mods (P8, geste B, 2026-09-14),
// sortis de `ModListView`. `anomalyReasons` est internal (lue par la vue
// principale) ; les badges restent `private`, ils ne servent qu'ici.
// MARK: - Section Group
struct ModSectionGroup: View {
    let title: String
    let mods: [ModItem]
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState

    var body: some View {
        StandardSection(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.element.id) { idx, mod in
                    if mod.isGroup, let children = mod.children {
                        ModGroupRow(mod: mod, children: children, vm: vm, localization: localization, listState: listState)
                    } else {
                        ModListRow(mod: mod, vm: vm, localization: localization, listState: listState,
                                   isChild: false, isGroupHeader: false, isExpanded: .constant(false))
                    }
                    
                    if idx < mods.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                            .frame(height: 1)
                            .padding(.leading, 48)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, -8)
        }
    }
}

// MARK: - Mod Group Row
struct ModGroupRow: View {
    let mod: ModItem
    let children: [ModItem]
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ModListRow(mod: mod, vm: vm, localization: localization, listState: listState,
                       isChild: false, isGroupHeader: true, isExpanded: $isExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { cIdx, child in
                        ModListRow(mod: child, vm: vm, localization: localization, listState: listState,
                                   isChild: true, isGroupHeader: false, isExpanded: .constant(false))
                        if cIdx < children.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                                .frame(height: 1)
                                .padding(.leading, 64)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Row
struct ModListRow: View {
    let mod: ModItem
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Porté pour les gestes qui touchent au cadrage de la liste — par
    /// exemple, lever le filtre « à écarter » quand le dernier mod marqué
    /// est démarqué, plutôt que de laisser l'utilisateur devant une liste
    /// vide sans explication.
    @ObservedObject var listState: ModListState
    @State private var isHovered = false
    var isChild: Bool = false
    var isGroupHeader: Bool = false
    @Binding var isExpanded: Bool
    @State private var localIsOn: Bool?
    /// Debounce du toggle : annule un toggle en attente si l'utilisateur
    /// rebascule avant le délai — sinon un double-clic laissait les deux timers
    /// tirer et le 1er clic gagnait (l'utilisateur finit sur OFF, le mod s'active).
    @State private var pendingToggle: DispatchWorkItem?
    /// Drives the confirmation dialog before deleting this row's mod.
    @State private var showDeleteConfirm = false
    /// L'infobulle demande deux secondes de curseur immobile, et ne se lit
    /// pas au clavier : la note et l'anomalie s'ouvrent aussi **au clic**,
    /// dans un popover qui les montre en entier.
    @State private var showingNote = false
    @State private var showingAnomaly = false
    @State private var showingNexusPage = false
    /// Le mod dont l'activation attend une confirmation : smapi.io le signale
    /// cassé. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?
    /// Même rôle, source différente : un conflit déclaré ou observé dans le
    /// journal avec un mod déjà actif (tâche 9). Voir `ConflictActivationGate`.
    @State private var pendingConflict: ConflictActivation?

    private var modRowA11yLabel: String {
        String(
            format: localization.L(L10n.Mods.rowA11yLabel),
            mod.name,
            mod.author,
            String(format: localization.L(L10n.Mods.versionPrefix), mod.version)
        )
    }

    /// The effective enabled state, honoring the optimistic `localIsOn` value
    /// so the visual styling reacts instantly when the toggle is flipped
    /// (before `vm.scanStore.mods` catches up).
    private var effectiveEnabled: Bool { localIsOn ?? mod.isEnabled }

    /// Compact metadata strip shown under the category/author/version line:
    /// languages (FR highlighted), last-update date, install date. Returns nil
    /// when nothing is known so no empty row is rendered. Uses relative dates
    /// (short form) to keep the line scannable; full dates live in the detail
    /// pane.
    /// Les largeurs des colonnes, à un seul endroit.
    ///
    /// **Fixes, et non minimales.** Un `minWidth` laisse la colonne grandir
    /// avec son contenu : l'auteur, mesuré de 1 à 99 caractères sur le parc
    /// réel, décalait donc le numéro de version d'une ligne à l'autre — c'est
    /// justement ce qu'un alignement doit empêcher. Une valeur absente garde
    /// sa place pour la même raison : ce qui suit ne doit pas remonter.
    ///
    /// Sans risque pour le nom du mod : il occupe sa propre ligne au-dessus, et
    /// ne partage la largeur avec aucune de ces colonnes. Total des deux
    /// bandes : 340 et 470 points environ, sous la largeur d'une fenêtre même
    /// étroite.
    enum Column {
        static let category: CGFloat = 110
        static let author: CGFloat = 150
        static let version: CGFloat = 80

        /// « FR 100 % » en français, espace insécable compris : huit signes,
        /// pas quatre.
        static let french: CGFloat = 66
        static let updated: CGFloat = 110
        static let installed: CGFloat = 105
        static let weight: CGFloat = 82
        static let languages: CGFloat = 120
    }

    /// L'auteur, dans un créneau borné.
    ///
    /// Le parc réel va de 1 à **99 caractères** (« Brandon Marquis Markail
    /// Green (Space Baby), 1.6 update by Nikki864, GMCM menu by MickeyMik »),
    /// avec une médiane à 9 : sans borne, un seul auteur bavard poussait la
    /// version et tout ce qui suit hors de leur colonne pour cette ligne-là.
    ///
    /// Troncature au **milieu** et non à la fin : ces noms à rallonge disent
    /// « X, repris par Y », et couper la fin masquerait justement qui maintient
    /// le mod aujourd'hui. L'infobulle porte la valeur entière.
    ///
    /// Vide plutôt que « Unknown » — le littéral que porte un manifeste sans
    /// auteur, déjà écarté de la même façon sur la fiche du mod.
    @ViewBuilder
    private var authorLabel: some View {
        let author = mod.isGroup ? vm.displayAuthor(for: mod) : mod.author
        if !author.isEmpty, author != "Unknown" {
            Text(author)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(author)
        } else {
            // Un créneau tenu vide : la colonne suivante doit rester en place.
            Color.clear.frame(height: 1)
        }
    }

    /// Une valeur de la bande, précédée de son icône.
    private func metaValue(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(AppDesign.Font.iconXXS)
            Text(text).lineLimit(1)
        }
    }

    /// Bande compacte sous la ligne catégorie/auteur/version : couverture
    /// française, dates, poids, puis les langues.
    ///
    /// Des créneaux de largeur **minimale**, pour que les mêmes valeurs se
    /// retrouvent à la même abscisse d'une ligne à l'autre : sur 863 mods,
    /// comparer deux poids ou deux dates demandait jusqu'ici de les chercher.
    /// `minWidth` et non `width` — la colonne s'aligne quand la place est là et
    /// reflue quand la fenêtre se resserre, plutôt que de rogner le nom du mod
    /// au-dessus.
    ///
    /// Chaque valeur garde son créneau même absente : sans quoi ce qui la suit
    /// remonte d'un cran et la colonne se défait — la moitié du parc n'ayant
    /// aucune langue déclarée (445 dossiers sur 863), une ligne sur deux
    /// décalait tout ce qui venait après. Les puces « • » qui séparaient les
    /// champs n'ont plus lieu d'être : des colonnes n'ont pas de séparateurs.
    private var rowMetadataLine: AnyView? {
        let updated = vm.nexusLastUpdated(for: mod)
        // La date **effective** : un en-tête de pack n'a pas de
        // `manifest.json`, donc pas de date propre — il hérite de la plus
        // récente de ses composants (`ModItem.effectiveInstallDate`). Lue
        // brute, la colonne restait vide sur toutes les lignes de pack.
        let installed = mod.effectiveInstallDate
        let langs = mod.languages
        // `mod` vient de `vm.scanStore.mods`, donc de la même analyse que la mesure : sa
        // clé physique désigne le dossier tel qu'il était sur le disque quand
        // le poids a été relevé. Un composant de pack n'en a pas — c'est
        // l'en-tête du pack qui porte le poids du dossier entier.
        let size = vm.sizeOnDisk(of: mod)
        // Les attributs comptent aussi : un mod qui n'a qu'une note doit
        // montrer sa bande, sinon la note disparaîtrait avec elle.
        let hasAttribute = vm.anomaly(for: mod) != nil
            || vm.modNote(for: mod) != nil
            || vm.isProfileConfigManaged(mod)
        guard updated != nil || installed != nil || !langs.isEmpty || size != nil || hasAttribute else {
            return nil
        }
        return AnyView(
            HStack(spacing: 10) {
                updatedSlot(updated)
                installedSlot(installed)
                weightSlot(size)
                languagesLabel(langs)
                frenchSlot(langs: langs)
                noteSlot
                profileConfigSlot
            }
        )
    }

    /// La largeur d'un créneau d'attribut : la cible de 18 pt qu'exige une
    /// infobulle vivante sur macOS, plus l'air qui la sépare de sa voisine.
    private static let attributeSlot: CGFloat = 22

    /// Le texte du popover d'état de page : le composant porteur d'abord
    /// quand le badge d'un pack vient d'un de ses enfants, puis la phrase
    /// d'état.
    private var nexusPagePopoverText: String {
        guard let page = vm.nexusPageState(for: mod) else { return "" }
        var lines: [String] = []
        if mod.isGroup, page.component.uniqueId != mod.uniqueId {
            lines.append(String(format: localization.L(L10n.Mods.compatInPack),
                                page.component.name))
        }
        lines.append(localization.L(page.state == .removed
            ? L10n.Mods.nexusPageRemovedHint : L10n.Mods.nexusPageUnavailableHint))
        return lines.joined(separator: "\n")
    }

    /// La note du mod, même traitement — et le clic la donne en entier : une
    /// note de plusieurs lignes ne tient pas dans une infobulle.
    @ViewBuilder
    private var noteSlot: some View {
        Group {
            if let note = vm.modNote(for: mod) {
                Button { showingNote = true } label: {
                    Image(systemName: "note.text")
                        .font(AppDesign.Font.iconXS)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(note)
                .popover(isPresented: $showingNote, arrowEdge: .bottom) {
                    attributePopover(title: localization.L(L10n.Mods.noteTitle),
                                     systemImage: "note.text",
                                     text: note)
                }
            }
        }
        .frame(width: Self.attributeSlot, alignment: .leading)
    }

    /// Le mod garde un `config.json` par profil. Elle suit ses deux voisines
    /// dans la bande : restée près du nom, elle y serait seule de son espèce.
    ///
    /// L'engrenage, pas des curseurs : `slider.horizontal.3` à 10 pt se lit
    /// comme des lignes de texte — à côté de la note, un utilisateur y a vu
    /// une note vide et a cliqué. L'engrenage est le glyphe « config » de
    /// l'app (le bouton d'édition de la rangée en porte un), et un état sans
    /// geste n'usurpe pas l'allure d'un bouton.
    @ViewBuilder
    private var profileConfigSlot: some View {
        Group {
            if vm.isProfileConfigManaged(mod) {
                Image(systemName: "gearshape")
                    .font(AppDesign.Font.iconXS)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
                    .help(localization.L(L10n.Mods.profileConfigBadge))
            }
        }
        .frame(width: Self.attributeSlot, alignment: .leading)
    }

    /// Ce qu'un clic sur un attribut montre : le texte en entier, borné en
    /// largeur pour qu'une note longue s'enroule au lieu de fuir hors écran.
    private func attributePopover(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(AppDesign.Font.caption(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(AppDesign.Font.footnote)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppDesign.Spacing.md)
        .frame(width: 320, alignment: .leading)
    }

    /// La couverture française **ferme** la bande, juste après les codes de
    /// langue dont elle précise l'un des membres : les deux se lisent ensemble,
    /// et le bout de ligne en fait un point d'arrivée du regard plutôt qu'un
    /// préambule à franchir avant les dates.
    @ViewBuilder
    private func frenchSlot(langs: [String]) -> some View {
        Group {
            if langs.contains("fr") {
                FrenchCoverageBadge(
                    percent: vm.frenchCoverage(for: mod),
                    // Un code de langue, pas une phrase : il ne se traduit pas,
                    // exactement comme la liste des langues à côté.
                    unmeasuredLabel: "FR",
                    percentFormat: localization.L(L10n.Mods.frCoveragePercent)
                )
            }
        }
        .frame(width: ModListRow.Column.french, alignment: .leading)
    }

    @ViewBuilder
    private func updatedSlot(_ updated: Date?) -> some View {
        Group {
            if let updated {
                metaValue("clock.arrow.circlepath",
                          updated.formatted(.relative(presentation: .named)))
            }
        }
        .frame(width: ModListRow.Column.updated, alignment: .leading)
    }

    @ViewBuilder
    private func installedSlot(_ installed: Date?) -> some View {
        Group {
            if let installed {
                metaValue("tray.and.arrow.down",
                          installed.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .frame(width: ModListRow.Column.installed, alignment: .leading)
    }

    @ViewBuilder
    private func weightSlot(_ size: Int64?) -> some View {
        Group {
            if let size { ModWeightLabel(bytes: size) }
        }
        .frame(width: ModListRow.Column.weight, alignment: .leading)
    }

    /// Jusqu'à 76 caractères de codes sur le parc réel : borné à ce que la
    /// place permet, avec la liste entière à l'infobulle.
    @ViewBuilder
    private func languagesLabel(_ langs: [String]) -> some View {
        let codes = langs.map { $0.uppercased() }.joined(separator: " ")
        Group {
            if !langs.isEmpty {
                metaValue("globe", codes)
                    .truncationMode(.tail)
                    .help(codes)
            }
        }
        .frame(width: ModListRow.Column.languages, alignment: .leading)
    }

    /// L'étoile de favori, sur les lignes de **premier niveau** seulement.
    ///
    /// Un composant de pack n'en porte pas : il ne s'active pas seul — c'est le
    /// pack qu'on met en pause, qu'on installe et qu'on met dans un profil. Le
    /// marquer séparément laisserait croire l'inverse.
    ///
    /// Toujours visible, pleine ou vide, plutôt qu'au survol : une étoile qui
    /// n'apparaît qu'au passage de la souris ne se découvre pas, et on ne peut
    /// pas lire d'un coup d'œil ce qui est marqué.
    @ViewBuilder
    private var favoriteStar: some View {
        let on = vm.isFavorite(mod)
        Button {
            vm.toggleFavorite(mod)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(AppDesign.Font.footnote)
                .foregroundColor(on ? .yellow : .secondary.opacity(isHovered ? 0.6 : 0.25))
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .help(localization.L(on ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd))
        .accessibilityLabel(localization.L(on ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd))
    }

    var body: some View {
        HStack(spacing: 0) {

            // Status accent bar — instant at-a-glance enabled/disabled
            // reading. Green for enabled, muted for disabled. Wider for
            // top-level rows, slimmer for pack children.
            RoundedRectangle(cornerRadius: 2)
                .fill(effectiveEnabled
                      ? AppDesign.Color.installed
                      : Color.secondary.opacity(AppDesign.Opacity.strong))
                .frame(width: isChild ? 2.5 : 3.5)

            HStack(spacing: AppDesign.Spacing.md) {
            
            // Chevron space (ensures perfect alignment for all top-level items)
            if !isChild {
                ZStack {
                    if isGroupHeader {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(AppDesign.Font.iconXS(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 14, alignment: .center)

                favoriteStar
                    // Largeur fixe : sans elle, l'étoile mesure ce que son
                    // glyph veut, et l'indentation des composants ci-dessous
                    // ne pouvait pas s'y accorder.
                    .frame(width: 16, alignment: .center)

                // Les glyphes d'état « à écarter » et « en pause » vivent ici,
                // pas dans la VStack grisée : à 0.55 d'opacité, le grisé
                // mangerait la redondance que ces glyphes sont censés porter
                // (P6 : couleur + barre d'accent + glyph). Trois indicateurs
                // côte à côte, à pleine opacité, d'un coup d'œil lisibles.
                // Mêmes 16 pt que l'étoile : l'alignement vertical reste
                // stable d'une ligne à l'autre.
                if !isChild && vm.isBlacklisted(mod) {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .center)
                } else if !effectiveEnabled && !isChild {
                    // Pas de `pause.circle` plein + × : un mod blacklisté ET
                    // en pause reste surtout blacklisté, et superposer deux
                    // glyphes côte à côte se lirait comme une 3e colonne
                    // d'actions. On garde la même largeur réservée pour la
                    // stabilité de l'alignement.
                    Image(systemName: "pause.circle")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .center)
                } else if !isChild {
                    // Réserve la place même quand aucun des deux états n'est
                    // posé : sans cette largeur invisible, un mod actif non
                    // blacklisté apparaîtrait plus à gauche qu'un mod
                    // blacklisté, et les colonnes de métadonnées se
                    // décaleraient.
                    Color.clear.frame(width: 16, height: 1)
                }
            } else {
                // L'indentation d'un composant se **calcule** sur ce qui la
                // précède chez son pack — chevron (14) + espace (12) + étoile
                // (16) + espace (12) + état (16) — plus un cran. Le 32
                // forfaitaire d'avant tombait en deçà : le nom d'un composant
                // commençait à *gauche* de celui de son pack, et toute sa
                // bande de métadonnées avec.
                Spacer().frame(width: 14 + AppDesign.Spacing.md + 16 + AppDesign.Spacing.md + 16 + AppDesign.Spacing.md)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Les deux badges d'alerte ouvrent la rangée du nom (au
                    // choix de l'auteur) : l'état de la page Nexus (A2-T6)
                    // puis l'anomalie. En tête du HStack, leur abscisse reste
                    // stable d'une ligne à l'autre — c'est la leçon du
                    // déplacement de l'anomalie vers la bande de
                    // métadonnées, retournée : ces badges ont vocation à
                    // alerter avant la fiche, et c'est ici qu'on les cherche.
                    if let page = vm.nexusPageState(for: mod) {
                        Button { showingNexusPage = true } label: {
                            NexusPageBadge(state: page.state, L: localization.L)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHandCursor()
                        .popover(isPresented: $showingNexusPage, arrowEdge: .bottom) {
                            attributePopover(
                                title: localization.L(page.state == .removed
                                    ? L10n.Mods.nexusPageRemoved : L10n.Mods.nexusPageUnavailable),
                                systemImage: page.state == .removed
                                    ? "xmark.circle.fill" : "eye.slash.fill",
                                text: nexusPagePopoverText)
                        }
                    }
                    if let anomaly = vm.anomaly(for: mod) {
                        Button { showingAnomaly = true } label: {
                            AnomalyBadge(anomaly: anomaly, vm: vm)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHandCursor()
                        .popover(isPresented: $showingAnomaly, arrowEdge: .bottom) {
                            attributePopover(title: localization.L(L10n.Mods.filterIssues),
                                             systemImage: "exclamationmark.triangle.fill",
                                             text: anomalyReasons(anomaly, vm: vm))
                        }
                    }
                    if let pending = PendingModUpdates.current(vm).pending(for: mod) { PendingUpdateBadge(pending: pending,
                        help: String(format: localization.L(L10n.Updates.availableVersion), pending.availableVersion)) }
                    Text(mod.name)
                        .font(AppDesign.Font.body(.medium))
                        .foregroundColor(effectiveEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    // Les glyphes d'état « à écarter » et « en pause » sont dans
                    // le HStack d'actions à gauche (à côté de l'étoile), pas
                    // dans la zone grisée : à 0.55 d'opacité, le grisé
                    // mange la redondance que ces glyphes sont censés porter
                    // (P6 : couleur + barre d'accent + glyph, jamais la
                    // couleur seule). Reste ici ce qui parle du **nom** :
                    // son état, et ses alertes.
                }
                
                if mod.name != mod.folderName {
                    Text(mod.folderName)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
                
                // Une seule forme pour les deux cas : un en-tête de pack rend
                // les mêmes champs, agrégés de ses composants. Deux `HStack`
                // jumeaux les auraient fait diverger dès la première retouche —
                // et un pack mal aligné au milieu de la liste se voit.
                HStack(spacing: 8) {
                    // Category badge — only for mods whose category was
                    // fetched from Nexus or manually pinned. Otherwise
                    // fall back to the offline-inferred type tag.
                    Group {
                        if let cat = vm.category(for: mod) {
                            CategoryBadge(category: cat, L: localization.L)
                        } else {
                            InferredTagBadge(label: localization.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod))))
                        }
                    }
                    .frame(width: ModListRow.Column.category, alignment: .leading)

                    authorLabel
                        .frame(width: ModListRow.Column.author, alignment: .leading)

                    VersionBadge(version: mod.isGroup ? vm.displayVersion(for: mod) : mod.version)
                        .frame(width: ModListRow.Column.version, alignment: .leading)

                    if mod.isGroup {
                        // Le nombre de composants ferme la ligne : il varie, et
                        // plus rien ne le suit dont il pourrait décaler la place.
                        Text(mod.description)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                // Compact metadata strip: languages + dates. Only shown when
                // at least one value is known, to avoid an empty row.
                if let metaLine = rowMetadataLine {
                    metaLine
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                let missingDeps = vm.getMissingDependencies(for: mod)
                let disabledDeps = vm.getDisabledDependencies(for: mod)
                if !missingDeps.isEmpty || !disabledDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !missingDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                // Chaque dépendance manquante est cliquable :
                                // ouvre la recherche Nexus Mods pour ce nom.
                                Text("\(localization.L(L10n.Mods.missingDependenciesPrefix)) ")
                                    .foregroundColor(.secondary)
                                ForEach(Array(missingDeps.enumerated()), id: \.offset) { idx, depId in
                                    HStack(spacing: 2) {
                                        if idx > 0 { Text(",") }
                                        let modName = depId.smapiModName
                                        let author = depId.smapiAuthor
                                        // Au clic, propose deux recherches Nexus :
                                        // par nom du mod (défaut) ou par auteur.
                                        Menu {
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
                                            Text(modName)
                                                .underline()
                                                .pointingHandCursor()
                                        }
                                        .menuStyle(.button)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .foregroundColor(.red)
                        }
                        if !disabledDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                Text(String(format: localization.L(L10n.Mods.disabledRequiredDeps), disabledDeps.joined(separator: ", ")))
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    .font(AppDesign.Font.footnote)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.2), lineWidth: 0.5)
                    )
                    .padding(.top, 2)
                }
            }
            // Grisé du contenu « info » quand le mod est marqué « à écarter ».
            // On ne touche ni la barre d'accent (l'état enabled/disabled doit
            // rester lisible), ni les boutons d'action (les gestes doivent
            // rester cliquables — y compris le bouton × qui lève la marque).
            .opacity((!isChild && vm.isBlacklisted(mod)) ? 0.55 : 1.0)

            Spacer()

            // Actions (always visible)
            HStack(spacing: AppDesign.Spacing.md) {
                // Bouton « à écarter » — premier niveau seulement, comme
                // l'étoile de favori. La marque se pose ici parce que c'est
                // l'écran de décision : marquer le sort d'un mod.
                if !isChild {
                    let blacklisted = vm.isBlacklisted(mod)
                    Button {
                        vm.toggleBlacklist(mod)
                        // Lever le filtre « à écarter » s'il ne montre plus
                        // rien : sans ça, l'utilisateur voit une liste vide
                        // sans comprendre pourquoi — la pastille dit
                        // « À écarter » (au lieu du compte, qui est 0), mais
                        // la liste reste filtrée et vide.
                        if vm.blacklistedMods.isEmpty {
                            listState.filters.blacklistedOnly = false
                        }
                    } label: {
                        Image(systemName: blacklisted ? "xmark.circle.fill" : "xmark.circle")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(blacklisted ? .secondary : .secondary.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(localization.L(blacklisted ? L10n.Mods.blacklistRemove : L10n.Mods.blacklistAdd))
                    .accessibilityLabel(localization.L(blacklisted ? L10n.Mods.blacklistRemove : L10n.Mods.blacklistAdd))
                    .pointingHandCursor()
                }

                Button {
                    let url = URL(fileURLWithPath: vm.gameDir)
                        .appendingPathComponent("Mods")
                        .appendingPathComponent(mod.physicalFolderName)
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "folder")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(localization.L(L10n.Mods.openFolder))
                .accessibilityLabel(localization.L(L10n.Mods.openFolder))
                .accessibilityHint(localization.L(L10n.Mods.openFolderA11yHint))
                .pointingHandCursor()

                // Direct config-editor access, mirroring upstream's
                // discoverability: visible only for a standalone mod (never
                // a pack header, which has no config.json of its own) that
                // actually has a config.json. The right-click "Code Editor"
                // context-menu entry stays as an additional entry point.
                if !mod.isGroup && mod.hasConfigFile {
                    Button {
                        vm.navigationStore.setEditingModConfig(mod)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(localization.L(L10n.Settings.configModSettings))
                    .accessibilityLabel(localization.L(L10n.Settings.configModSettings))
                    .accessibilityHint(localization.L(L10n.Settings.configModSettingsA11yHint))
                    .pointingHandCursor()
                }

                // Direct "open on Nexus" button — visible whenever the mod has
                // an effective Nexus id (manifest-declared or user-assigned).
                let link = vm.nexusLink(for: mod)
                if !link.isEmpty {
                    Button {
                        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "safari")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(localization.L(L10n.Mods.viewOnNexus))
                    .accessibilityLabel(localization.L(L10n.Mods.viewOnNexus))
                    .accessibilityHint(localization.L(L10n.Mods.viewOnNexusA11yHint))
                    .pointingHandCursor()
                }

                // Info button — always visible so the user can edit the mod's
                // category / Nexus link even when it has no dependencies or
                // pre-existing Nexus URL.
                Button {
                    vm.navigationStore.setViewingModDetail(mod)
                } label: {
                    Image(systemName: "info.circle")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(localization.L(L10n.Mods.openDetails))
                .accessibilityLabel(localization.L(L10n.Mods.openDetails))
                .accessibilityHint(localization.L(L10n.Mods.openDetailsHint))
                .pointingHandCursor()

                // Delete button — permanently removes the mod (or pack) from
                // disk. Hidden for child rows inside a pack, since the pack
                // header carries the delete action for all children. A
                // confirmation dialog fires before the actual deletion.
                // While the deletion is in flight (folder removal + rescan),
                // a spinner replaces the trash icon on this row.
                if !isChild {
                    if vm.pendingDeleteFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .help(localization.L(L10n.Mods.deleteMod))
                    } else {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(AppDesign.Font.rowTitle)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(vm.pendingDeleteFolder != nil)
                        .help(localization.L(L10n.Mods.deleteMod))
                        .accessibilityLabel(localization.L(L10n.Mods.deleteMod))
                        .accessibilityHint(localization.L(L10n.Mods.deleteModA11yHint))
                        .pointingHandCursor()
                    }
                }
            }
            .padding(.trailing, 8)


            // macOS Native Switch Toggle
            if !isChild {
                HStack(spacing: AppDesign.Spacing.xs) {
                    // Spinner pendant l'opération de toggle (rename du
                    // dossier dans Mods/ entre X et .X). Disparaît dès
                    // que pendingToggleFolder est remis à nil par le VM.
                    if vm.pendingToggleFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                    Toggle("", isOn: Binding(
                        get: { localIsOn ?? mod.isEnabled },
                        set: { newValue in
                            localIsOn = newValue
                            // Annule un toggle en attente : sans cela, un
                            // double-clic laissait deux timers tirer et le 1er
                            // clic gagnait au lieu du dernier.
                            pendingToggle?.cancel()
                            let work = DispatchWorkItem {
                                if newValue != mod.isEnabled {
                                    // Activer un mod que smapi.io signale cassé
                                    // demande une confirmation ; le mettre en
                                    // pause, jamais. La bascule optimiste est
                                    // rendue tout de suite : l'interrupteur ne
                                    // doit pas rester sur « actif » pendant que
                                    // l'alerte attend une réponse.
                                    if vm.activationWarning(for: mod) != nil {
                                        localIsOn = nil
                                        pendingActivation = mod
                                        return
                                    }
                                    // Même porte, source différente : un conflit
                                    // déclaré ou observé dans le journal avec un
                                    // mod déjà actif (tâche 9).
                                    if let other = vm.conflictWarning(for: mod) {
                                        localIsOn = nil
                                        pendingConflict = ConflictActivation(mod: mod, other: other)
                                        return
                                    }
                                    // Keep the optimistic value until toggleMod's completion
                                    // confirms vm.scanStore.mods has actually caught up — clearing it
                                    // eagerly here races the background scanMods() and made
                                    // the switch visibly snap back to its old position.
                                    vm.toggleMod(mod) {
                                        localIsOn = nil
                                    }
                                } else {
                                    localIsOn = nil
                                }
                            }
                            pendingToggle = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                        }
                    ))
                        .toggleStyle(SwitchToggleStyle(tint: AppDesign.Color.installed))
                        .controlSize(.small)
                        // Annuler un toggle en attente quand la rangée disparaît
                        // (virtualisation, navigation) : sinon le debounce 300 ms
                        // tirait pour un mod désaffiché.
                        .onDisappear { pendingToggle?.cancel() }
                        .labelsHidden()
                        .accessibilityLabel(String(format: localization.L(L10n.Mods.toggleA11yLabel), mod.name))
                        .accessibilityHint(localization.L(L10n.Mods.toggleA11yHint))
                        .accessibilityValue(mod.isEnabled ? localization.L(L10n.Mods.enabled) : localization.L(L10n.Mods.disabled))
                }
            } else {
                Toggle("", isOn: .constant(false))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .controlSize(.small)
                    .labelsHidden()
                    .opacity(0)
            }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            // Dim the content (not the toggle/accent bar) for disabled mods to
            // create visual hierarchy — active mods draw the eye first.
            .opacity(effectiveEnabled ? 1.0 : 0.72)
        }
        .background(
            // Hover: accent-tinted fill for a clearer "interactive" feel.
            isHovered ? Color.accentColor.opacity(0.06) : Color.clear
        )
        .background(
            vm.selectedModID == mod.folderName
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(6)
        .overlay(
            // Subtle accent border on hover — polished focus ring.
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .stroke(isHovered ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: effectiveEnabled)
        .onHover { isHovered = $0 }
        // Accessibility : VoiceOver annonce le mod comme un élément unifié
        // avec son nom, auteur, version et état (activé/désactivé).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modRowA11yLabel)
        .accessibilityValue(mod.isEnabled ? localization.L(L10n.Mods.enabled) : localization.L(L10n.Mods.disabled))
        .accessibilityHint(localization.L(L10n.Mods.openDetailsHint))
        .contextMenu {
            Button(localization.L(L10n.Mods.openInFinder)) {
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent("Mods")
                    .appendingPathComponent(mod.physicalFolderName)
                NSWorkspace.shared.open(url)
            }
            Button(localization.L(L10n.Settings.configModSettings)) {
                vm.navigationStore.setEditingModConfig(mod)
            }
            let effectiveLink = vm.nexusLink(for: mod)
            if !effectiveLink.isEmpty {
                Button(localization.L(L10n.Mods.viewDetailsOnNexus)) {
                    if let url = URL(string: effectiveLink) { NSWorkspace.shared.open(url) }
                }
            }
            if !isChild {
                Divider()
                Button(localization.L(L10n.Mods.deleteMod), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog(
            String(format: localization.L(L10n.Mods.deleteConfirmTitle), mod.name),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(localization.L(L10n.Mods.deleteMod), role: .destructive) {
                vm.deleteMod(mod)
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { }
        } message: {
             Text(mod.isGroup
                 ? localization.L(L10n.Mods.deleteConfirmPack)
                 : localization.L(L10n.Mods.deleteConfirmMessage))
        }
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
    }

    /// Ouvre la recherche Nexus Mods pour une dépendance manquante.
    /// Le terme de recherche utilise le nom lisible (ex. "Content Patcher"
    /// plutôt que l'identifiant unique "Pathoschild.ContentPatcher") pour
    /// exploiter l'indexation par nom de Nexus.
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

/// Neutral badge shown in place of `CategoryBadge` when a mod has no Nexus
/// category: displays its offline-inferred type tag (see `ModItem.inferTag`)
/// instead, so uncategorized mods still carry some at-a-glance grouping info.
private struct InferredTagBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .lineLimit(1)
            .font(AppDesign.Font.iconXS(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(AppDesign.Opacity.medium))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }
}

/// Pastille de couverture française, dans le vocabulaire de `VersionBadge` :
/// une unité compacte et scannable plutôt qu'un mot noyé dans la ligne grise.
///
/// **Le nombre porte l'information, la couleur la renforce** — jamais
/// l'inverse. Un badge dont le sens tiendrait au seul vert contre orange serait
/// illisible pour un daltonien et invisible en balayage rapide ; c'est le taux
/// écrit qui se compare d'une ligne à l'autre.
///
/// Trois états, parce qu'il y en a trois : mesuré et complet, mesuré et
/// partiel, et **pas encore mesuré** — le calcul se fait en tâche de fond après
/// le scan. Ce dernier état se lit en gris et sans nombre : annoncer un taux
/// qu'on ignore serait pire que de ne rien annoncer.
private struct FrenchCoverageBadge: View {
    /// `nil` tant que la mesure n'a pas abouti.
    let percent: Int?
    let unmeasuredLabel: String
    let percentFormat: String

    private var tint: Color {
        guard let percent else { return .secondary }
        return percent >= 100 ? AppDesign.Color.success : .orange
    }

    var body: some View {
        Text(percent.map { String(format: percentFormat, $0) } ?? unmeasuredLabel)
            // Chiffres à chasse fixe : dans une liste, « 8 % » et « 72 % »
            // doivent s'aligner verticalement pour se comparer d'un coup d'œil,
            // sinon chaque pastille danse d'une ligne à l'autre.
            .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
            // Sur une seule ligne, quoi qu'il arrive : dans une colonne de
            // largeur fixe, « FR 100 % » se repliait et poussait le « % » sous
            // le reste. `fixedSize` prime sur la contrainte de la colonne.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(AppDesign.Opacity.medium))
            )
            .overlay(
                // Un liseré porte le contour que l'aplat à 15 % ne donne pas —
                // sans lui la pastille se dissout sur un fond clair.
                Capsule().stroke(tint.opacity(AppDesign.Opacity.strong), lineWidth: 0.5)
            )
    }
}

/// Compact monospaced pill for a mod's version number. Replaces the bare
/// `Text("v\(version)")` so the version reads as a distinct, scannable unit
/// rather than blending into the metadata row's bullet-separated text.
private struct VersionBadge: View {
    let version: String
    var body: some View {
        Text("v\(version)")
            .font(AppDesign.Font.iconXS(.medium).monospaced())
            // Le parc réel monte à 28 signes (« 0.6.3-unofficial-mushymato.1 »,
            // « %ProjectVersion% ») : sans garde, la capsule se repliait sur
            // deux lignes et faisait enfler la rangée. Coupée au milieu, le
            // numéro majeur et le suffixe restent tous deux lisibles.
            .lineLimit(1)
            .truncationMode(.middle)
            .help(version)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
    }
}


/// Le poids d'un mod dans sa ligne de liste.
///
/// Affiché sur **toutes** les lignes, mais teinté au-delà de 100 Mo. Le parc
/// réel explique les deux décisions : sa médiane est de 213 Ko et 650 dossiers
/// sur 863 pèsent moins d'un mégaoctet — un chiffre neutre partout serait du
/// bruit — tandis que **22 dossiers portent 87 % des 16,8 Go**. La teinte les
/// désigne sans qu'il faille lire 863 lignes, et reste assez rare pour valoir
/// signal.
private struct ModWeightLabel: View {
    let bytes: Int64

    /// 22 mods du parc réel passent ce seuil, et ils portent 87 % du poids.
    /// Plus bas (50 Mo : 31 mods) la teinte se banalise, plus haut (300 Mo :
    /// 11 mods) elle laisse de côté des dossiers qui pèsent encore lourd.
    private static let heavyThreshold: Int64 = 100_000_000

    private var isHeavy: Bool { bytes >= Self.heavyThreshold }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "internaldrive")
                .font(AppDesign.Font.iconXXS)
            // Chiffres à chasse fixe, comme la pastille de couverture : d'une
            // ligne à l'autre les tailles doivent s'aligner pour se comparer.
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(AppDesign.Font.iconXS(isHeavy ? .semibold : .regular).monospacedDigit())
        }
        .foregroundColor(isHeavy ? .orange : .secondary)
    }
}


// MARK: - Pastille d'anomalie (B1-T3)

/// Ce qui empêche un mod de bien tourner, sur sa ligne.
///
/// Trois signaux sous une seule pastille : erreurs et avertissements relevés
/// dans les journaux SMAPI **pour la version installée**, dépendance requise
/// absente ou en pause, manifeste sans identifiant. Le détail passe par
/// l'infobulle — la ligne porte déjà beaucoup.
///
/// Six mods sur 863 en portent une sur le parc réel : c'est attendu, une
/// pastille qui s'allumerait souvent ne dirait plus rien.
private struct AnomalyBadge: View {
    let anomaly: ModAnomaly
    var vm: StarHubTHViewModel

    private var tint: Color { anomaly.severity == .error ? .orange : .yellow }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppDesign.Font.iconXS)
            if anomaly.badgeCount > 0 {
                Text("\(anomaly.badgeCount)")
                    .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
            }
        }
        .foregroundColor(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(tint.opacity(AppDesign.Opacity.medium)))
        // La capsule mesurait ~13 pt de haut : trop court pour que macOS
        // accepte de garder son curseur « tout à l'intérieur » les ~2 s
        // qu'exige une infobulle — le timer se réinitialisait et l'aide ne
        // venait jamais. Même correction que la note et la config voisines :
        // une cible d'au moins 18×18, et une forme qui la porte.
        .frame(minWidth: 18, minHeight: 18)
        .contentShape(.rect)
        .help(reasons)
        .accessibilityLabel(reasons)
    }

    private var reasons: String { anomalyReasons(anomaly, vm: vm) }
}

/// Toutes les raisons d'une anomalie, une par ligne : un mod peut cumuler une
/// dépendance manquante et des erreurs, et n'en montrer qu'une enverrait sur
/// une fausse piste.
///
/// Une fonction et non une propriété de la pastille : la rangée en a besoin
/// pour son popover, et fabriquer une pastille jetable pour lire son texte
/// aurait été un détour.
/// `@MainActor` (L2) : la fonction lit l'état du VM — lui-même isolé sur
/// l'acteur principal — et n'a que trois appelants, tous dans des vues.
@MainActor
func anomalyReasons(_ anomaly: ModAnomaly, vm: StarHubTHViewModel) -> String {
    var lines: [String] = []
    if anomaly.isUnloadable { lines.append(vm.localization.L(L10n.Mods.anomalyUnloadable)) }
    if anomaly.hasDependencyIssue { lines.append(vm.localization.L(L10n.Mods.anomalyDependency)) }
    if let duplicate = anomaly.duplicate {
        // Les dossiers **nommés** : un compte seul laisserait chercher
        // lequel supprimer parmi 863.
        lines.append(String(format: vm.localization.L(duplicate.isActive
                                         ? L10n.Mods.anomalyDuplicateActive
                                         : L10n.Mods.anomalyDuplicateDormant),
                            duplicate.copies,
                            duplicate.folders.joined(separator: ", ")))
    }
    if let status = anomaly.compatibility {
        lines.append(String(format: vm.localization.L(L10n.Mods.anomalyCompat),
                            CompatibilityWarning.label(status, vm.localization)))
    }
    if anomaly.errorCount > 0 {
        lines.append(String(format: vm.localization.L(L10n.Mods.anomalyErrors), anomaly.errorCount))
    }
    if anomaly.warningCount > 0 {
        lines.append(String(format: vm.localization.L(L10n.Mods.anomalyWarnings), anomaly.warningCount))
    }
    return lines.joined(separator: "\n")
}
