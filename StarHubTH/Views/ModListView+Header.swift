import SwiftUI

// L'en-tête fixe de `ModListView` : cadrage, recherche et actions, puis
// filtres et méta. Sorti du fichier principal (I-T11, 2026-09-25) quand
// chaque rangée a dû devenir adaptative.
//
// À la fenêtre minimale (560 pt de contenu, 512 une fois les marges ôtées),
// la rangée de filtres débordait des deux côtés et le libellé de poids se
// repliait une lettre par ligne, sur toute la hauteur de l'en-tête (constat
// à l'écran). Chaque rangée tient donc sur une ligne quand elle le peut, et
// se replie sur deux sinon — jamais tronquée (`AGENTS.md` §6).
extension ModListView {

    func listHeader(counts: (all: Int, enabled: Int, disabled: Int, issues: Int, updates: Int),
                    display: [ModItem],
                    categories: [(category: NexusCategory, count: Int)],
                    uncatCount: Int,
                    tagBuckets: [(tag: String, label: String, count: Int)],
                    translationCounts: [FrenchTranslationScope: Int]) -> some View {
        let noCategory = categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty
        return VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            // Rangée principale : cadrage (gauche) et action clé (droite), à
            // la même priorité visuelle, au-dessus des filtres secondaires.
            ViewThatFits(in: .horizontal) {
                HStack {
                    scopePicker(counts: counts)
                    searchField
                    Spacer()
                    listTools(display: display)
                }
                // Trop étroit : la recherche descend sur sa propre ligne, et
                // « Installer des mods » ne garde que son icône (infobulle).
                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    HStack {
                        scopePicker(counts: counts)
                        Spacer()
                        listTools(display: display)
                            .labelStyle(.iconOnly)
                    }
                    searchField
                }
            }

            // Rangée secondaire : filtres et tri, groupés en puces qui se
            // lisent comme une unité (« affiner la liste »). La méta (poids,
            // profil) passe dessous quand les deux ne tiennent pas ensemble.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    filterChips(categories: categories, uncatCount: uncatCount,
                                tagBuckets: tagBuckets, noCategory: noCategory,
                                translationCounts: translationCounts)
                    Spacer()
                    listMeta(display: display, noCategory: noCategory)
                }
                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    HStack(spacing: 6) {
                        filterChips(categories: categories, uncatCount: uncatCount,
                                    tagBuckets: tagBuckets, noCategory: noCategory,
                                    translationCounts: translationCounts)
                    }
                    HStack(spacing: 6) {
                        listMeta(display: display, noCategory: noCategory)
                    }
                }
            }
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.top, AppDesign.Spacing.xl)
        .padding(.bottom, AppDesign.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Libellés complets, ou icône et compte si la barre est trop étroite :
    /// jamais tronqués.
    private func scopePicker(counts: (all: Int, enabled: Int, disabled: Int, issues: Int, updates: Int)) -> some View {
        ViewThatFits(in: .horizontal) {
            ModScopePicker(scope: $listState.filters.scope, counts: counts,
                           localization: localization, compact: false)
            ModScopePicker(scope: $listState.filters.scope, counts: counts,
                           localization: localization, compact: true)
        }
    }

    /// La recherche vit ici, au motif des journaux (`LogsView.swift:182`) —
    /// la barre système `.searchable` disparaît : un geste, une place (P3).
    /// Filtrage à la frappe, comme `.searchable` le donnait ; le motif
    /// Découvrir est submit-only et l'aurait régressé.
    private var searchField: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(.secondary)
            TextField(localization.L(L10n.Mods.searchMods),
                      text: $listState.filters.search)
                .textFieldStyle(.plain)
                .searchFieldShortcut($searchFocused)
            if !listState.filters.search.isEmpty {
                Button {
                    listState.filters.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                // Cible 18×18 + contentShape : un glyphe nu de ~12 pt rend
                // `.help` muet (contrainte a11y du lot).
                .frame(width: 18, height: 18)
                .contentShape(.rect)
                .help(localization.L(L10n.Discovery.clearSearch))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, AppDesign.Spacing.xs)
        .background(Color.primary.opacity(AppDesign.Opacity.light))
        .cornerRadius(6)
        .frame(maxWidth: 220)
    }

    /// Disposition, bascule groupée et installation.
    @ViewBuilder
    private func listTools(display: [ModItem]) -> some View {
        // La grille optionnelle (H-T4) : liste dense par défaut, cartes
        // au-dessus. Choix persisté — une habitude de parcours, pas un état
        // de session.
        Picker(localization.L(L10n.Mods.layoutList), selection: $listLayout) {
            // `list.bullet` et non un glyph de disposition : à 32 pt de
            // demi-segment, tout ce qui dessine des quartiers devient
            // illisible.
            Image(systemName: "list.bullet")
                .tag(ModsListLayout.list)
            Image(systemName: "square.grid.2x2")
                .tag(ModsListLayout.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 64)
        .help(listLayout == .list
              ? localization.L(L10n.Mods.layoutList)
              : localization.L(L10n.Mods.layoutGrid))

        // Désactivé quand il n'y a rien à basculer, ou pendant une bascule
        // groupée déjà en cours.
        bulkToggleMenu(scoped: display)
            .disabled(vm.scanStore.mods.isEmpty || vm.bulkToggleProgress != nil)

        Button {
            showInstallSheet = true
        } label: {
            Label(localization.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
        }
        .buttonStyle(.borderedProminent)
        .help(localization.L(L10n.ModInstall.installButton))
    }

    @ViewBuilder
    private func filterChips(categories: [(category: NexusCategory, count: Int)],
                             uncatCount: Int,
                             tagBuckets: [(tag: String, label: String, count: Int)],
                             noCategory: Bool,
                             translationCounts: [FrenchTranslationScope: Int]) -> some View {
        sortPicker

        Divider()
            .frame(height: 16)

        configFilterToggle

        favoritesFilterToggle

        blacklistedFilterToggle

        Divider()
            .frame(height: 16)

        frenchTranslationPicker(counts: translationCounts)

        categoryPicker(categories: categories, uncatCount: uncatCount, tagBuckets: tagBuckets)
            .disabled(noCategory)
            .help(noCategory
                  ? localization.L(L10n.Mods.categoryFilterEmptyHint)
                  : localization.L(L10n.Mods.categoryFilterHint))
    }

    @ViewBuilder
    private func listMeta(display: [ModItem], noCategory: Bool) -> some View {
        scopeWeightLabel(for: display)
            .lineLimit(1)
            .fixedSize()

        if noCategory {
            Text(localization.L(L10n.Mods.categoryFilterEmptyHint))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
                .lineLimit(1)
                .help(localization.L(L10n.Mods.categoryFilterEmptyHint))
        }

        // Le profil appliqué — et le chemin vers la page qui le gère : c'est
        // là qu'on va quand on le lit ici.
        if let profile = vm.activeProfile {
            Button {
                currentTab = .profiles
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.crop.circle")
                        .font(AppDesign.Font.footnote)
                    Text(String(format: localization.L(L10n.Profiles.activeLabel), profile.name))
                        .font(AppDesign.Font.footnote(.medium))
                        .lineLimit(1)
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, AppDesign.Spacing.sm)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(localization.L(L10n.Profiles.title))
            .accessibilityLabel(String(format: localization.L(L10n.Profiles.activeLabel), profile.name))
            .accessibilityHint(localization.L(L10n.Profiles.title))
        }
    }
}
