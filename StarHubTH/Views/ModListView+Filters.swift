import SwiftUI

// Le panneau de filtres de `ModListView` — P8, geste A (cadrage
// 2026-09-14) : même type, extension dans un second fichier, aucune
// réécriture. Les membres lus ici mais posés dans le fichier principal
// (`filters`, `listState`, `pageSize`…) y sont `internal` : `private`
// est file-scopé pour les extensions.
extension ModListView {

    @ViewBuilder
    /// Un tri du menu. L'icône **ne se remplace pas** par une coche quand le
    /// tri est actif : le bouton du menu affiche déjà le libellé du tri en
    /// cours (`sortLabel`), donc la coche ne disait rien de plus — elle
    /// effaçait juste l'icône, et l'entrée par défaut (« Nom (A-Z) ») en
    /// paraissait dépourvue.
    private func sortItem(_ order: ModSortOrder, label: String, icon: String) -> some View {
        Button {
            listState.filters.sort = order
        } label: {
            Label(localization.L(label), systemImage: icon)
        }
    }

    /// Une option du menu traduction, avec son compte dans la vue active.
    ///
    /// Le compte, et rien d'autre : l'entrée ne s'éteint pas à zéro. « À
    /// revoir » et « Partiellement traduits » se lisent dans des mesures qui
    /// se font en tâche de fond — au lancement elles valent zéro pour un
    /// moment, et une entrée grisée aurait dit « il n'y en a pas » là où il
    /// fallait lire « pas encore compté ».
    private func translationItem(_ scope: FrenchTranslationScope,
                                 label: String,
                                 icon: String,
                                 count: Int) -> some View {
        Button {
            listState.filters.frenchTranslation = scope
        } label: {
            Label("\(localization.L(label)) (\(count))", systemImage: icon)
        }
    }

    var sortPicker: some View {
        Menu {
            // `arrow.up`/`arrow.down` et non la paire
            // `arrow.up.arrow.down`/`arrow.down.arrow.up` : la seconde
            // **n'existe pas** sur macOS 26 (vérifié par
            // `NSImage(systemSymbolName:)`), et un symbole absent ne dessine
            // rien — l'entrée paraissait sans icône.
            sortItem(.name, label: L10n.Mods.sortName, icon: "arrow.up")
            sortItem(.nameDescending, label: L10n.Mods.sortNameDescending, icon: "arrow.down")
            sortItem(.activationOrder, label: L10n.Mods.sortActivationOrder, icon: "clock.arrow.circlepath")
            sortItem(.installDate, label: L10n.Mods.sortInstallDate, icon: "calendar")
            sortItem(.author, label: L10n.Mods.sortAuthor, icon: "person.fill")
            sortItem(.version, label: L10n.Mods.sortVersion, icon: "tag")
            sortItem(.size, label: L10n.Mods.sortSize, icon: "internaldrive")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(AppDesign.Font.footnote)
                Text(sortLabel)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var sortLabel: String {
        switch filters.sort {
        case .name: return localization.L(L10n.Mods.sortName)
        case .nameDescending: return localization.L(L10n.Mods.sortNameDescending)
        case .activationOrder: return localization.L(L10n.Mods.sortActivationOrder)
        case .installDate: return localization.L(L10n.Mods.sortInstallDate)
        case .author: return localization.L(L10n.Mods.sortAuthor)
        case .version: return localization.L(L10n.Mods.sortVersion)
        case .size: return localization.L(L10n.Mods.sortSize)
        }
    }

    // MARK: - Config-only filter toggle

    /// Toggle button scoping the list to mods with a `config.json` (see
    /// `filters.configOnly`). Same visual family as `sortPicker`/
    /// `categoryPicker` (rounded chip, same padding/font), but a plain
    /// toggle rather than a menu — there's only one on/off state, not a
    /// set of choices.
    var configFilterToggle: some View {
        Button {
            listState.filters.configOnly.toggle()
        } label: {
            // Le glyph seul : le libellé vit à l'infobulle. La cible reste
            // large (10/5 de marge autour d'un glyph de 11 pt), bien au-delà
            // du 18×18 qu'exige une infobulle vivante.
            Image(systemName: "gearshape")
                .font(AppDesign.Font.footnote)
                .foregroundColor(filters.configOnly ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                        .fill(filters.configOnly ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                        .stroke(filters.configOnly ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(localization.L(L10n.Mods.configFilterLabel))
        // Sans texte visible, l'infobulle ne suffit pas : VoiceOver n'a plus
        // que ce libellé.
        .accessibilityLabel(localization.L(L10n.Mods.configFilterLabel))
    }

    // MARK: - Favourites filter toggle (B3-T2)

    /// Cadre la liste sur les mods marqués d'une étoile. Même famille visuelle
    /// que `configFilterToggle`.
    ///
    /// Une pastille de plus dans une barre qui en portait déjà cinq, et c'est
    /// justifié ici alors que le poids s'en est passé (B2-T9) : le poids se
    /// cadrait par « en pause » + tri, les favoris n'ont aucun équivalent. Sans
    /// ce cadrage, un jeu de favoris se perdrait dans 36 pages de liste.
    ///
    /// Quand rien n'est marqué, la pastille dit **où** marquer plutôt que de
    /// mener à une liste vide.
    var favoritesFilterToggle: some View {
        let active = filters.favoritesOnly
        let empty = vm.favoriteMods.isEmpty
        return Button {
            listState.filters.favoritesOnly.toggle()
        } label: {
            // Le libellé passe à l'infobulle ; le **compte** reste, lui : il
            // ne se lit nulle part ailleurs dans la barre.
            //
            // Sauf quand rien n'est marqué : la pastille est alors *désactivée*,
            // et l'infobulle d'un contrôle désactivé ne se montre pas toujours
            // sur macOS. Réduite à une étoile grise, elle ne dirait plus rien —
            // elle garde donc son libellé dans ce seul état, celui où elle a
            // justement quelque chose à expliquer.
            HStack(spacing: 4) {
                Image(systemName: active ? "star.fill" : "star")
                    .font(AppDesign.Font.footnote)
                if empty {
                    Text(localization.L(L10n.Mods.filterFavorites))
                        .font(AppDesign.Font.caption(.medium))
                } else {
                    Text("\(vm.favoriteMods.count)")
                        .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(active ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(active ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(active ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(empty && !active)
        .help(localization.L(empty ? L10n.Mods.filterFavoritesEmptyHint : L10n.Mods.filterFavoritesHint))
        .accessibilityLabel(localization.L(L10n.Mods.filterFavorites))
        // Le compte est à l'écran : sans cette valeur, VoiceOver le perdrait
        // avec le libellé.
        .accessibilityValue(empty ? "" : "\(vm.favoriteMods.count)")
    }

    // MARK: - Blacklisted filter toggle

    /// Cadre la liste sur les mods marqués « à écarter ». Même famille visuelle
    /// que `favoritesFilterToggle` — `.circle` plein quand actif, vide sinon,
    /// compteur tant qu'il y a quelque chose à compter, libellé quand il n'y
    /// a rien à expliquer d'autre que le geste.
    ///
    /// Le filtre est **positif** : par défaut tout le monde passe, et c'est
    /// l'activer qui réduit la liste aux seuls marqués. Un grisé de la liste
    /// générale reste donc découvrable sans ce filtre — c'est la même
    /// logique que les favoris, retournée.
    var blacklistedFilterToggle: some View {
        let active = filters.blacklistedOnly
        let empty = vm.blacklistedMods.isEmpty
        return Button {
            listState.filters.blacklistedOnly.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "xmark.circle.fill" : "xmark.circle")
                    .font(AppDesign.Font.footnote)
                if empty {
                    Text(localization.L(L10n.Mods.filterBlacklisted))
                        .font(AppDesign.Font.caption(.medium))
                } else {
                    Text("\(vm.blacklistedMods.count)")
                        .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(active ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(active ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(active ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(empty && !active)
        .help(localization.L(empty ? L10n.Mods.filterBlacklistedEmptyHint : L10n.Mods.filterBlacklistedHint))
        .accessibilityLabel(localization.L(L10n.Mods.filterBlacklisted))
        .accessibilityValue(empty ? "" : "\(vm.blacklistedMods.count)")
    }

    // MARK: - French-translation filter picker

    /// Three-state menu scoping the list to mods that ship (or don't ship) an
    /// `i18n/fr.json` translation file. Same chip visual family as the
    /// config-only toggle and the category picker.
    /// Combien de mods la vue active contient pour chaque état de traduction.
    /// Les options qui n'y mènent nulle part se **désactivent** — elles ne
    /// disparaissent pas : un menu dont les entrées vont et viennent ne se
    /// mémorise pas.
    func frenchTranslationCounts(from base: [ModItem]) -> [FrenchTranslationScope: Int] {
        var counts: [FrenchTranslationScope: Int] = [:]
        for scope in [FrenchTranslationScope.available, .partial, .missing, .stale] {
            counts[scope] = base.filter { vm.matchesTranslation($0, scope) }.count
        }
        return counts
    }

    func frenchTranslationPicker(counts: [FrenchTranslationScope: Int]) -> some View {
        let isActive = filters.frenchTranslation != .off
        let label: String = {
            switch filters.frenchTranslation {
            case .off:       return localization.L(L10n.Mods.frTranslationFilterLabel)
            case .available: return localization.L(L10n.Mods.frTranslationAvailable)
            case .partial:   return localization.L(L10n.Mods.frTranslationPartial)
            case .missing:   return localization.L(L10n.Mods.frTranslationMissing)
            case .stale:     return localization.L(L10n.Mods.frTranslationStale)
            }
        }()
        let icon: String = {
            switch filters.frenchTranslation {
            case .off:       return "character.bubble"
            case .available: return "checkmark.bubble"
            case .partial:   return "ellipsis.bubble"
            // Le symbole `xmark` sur bulle n'existe pas sur macOS 26
            // (mesuré) : l'entrée « À traduire » n'affichait rien.
            case .missing:   return "exclamationmark.bubble"
            case .stale:     return "clock.badge.exclamationmark"
            }
        }()
        return Menu {
            Button {
                listState.filters.frenchTranslation = .off
            } label: {
                Label(localization.L(L10n.Mods.frTranslationFilterLabel), systemImage: "character.bubble")
            }
            translationItem(.available, label: L10n.Mods.frTranslationAvailable,
                            icon: "checkmark.bubble", count: counts[.available] ?? 0)
            translationItem(.partial, label: L10n.Mods.frTranslationPartial,
                            icon: "ellipsis.bubble", count: counts[.partial] ?? 0)
            translationItem(.missing, label: L10n.Mods.frTranslationMissing,
                            icon: "exclamationmark.bubble", count: counts[.missing] ?? 0)
            translationItem(.stale, label: L10n.Mods.frTranslationStale,
                            icon: "clock.badge.exclamationmark", count: counts[.stale] ?? 0)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppDesign.Font.footnote)
                Text(label)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(isActive ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(isActive ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(localization.L(L10n.Mods.frTranslationFilterLabel))
    }

    // MARK: - Category picker

    /// Dropdown listing every category present in the installed mods list.
    /// Selecting one scopes the list to that category; selecting "All" clears
    /// it. Each row shows the category color + localized name + mod count.
    func categoryPicker(categories: [(category: NexusCategory, count: Int)], uncatCount: Int, tagBuckets: [(tag: String, label: String, count: Int)]) -> some View {
        Menu {
            Button {
                listState.filters.category = .all
            } label: {
                Label(localization.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            if uncatCount > 0 {
                Button {
                    listState.filters.category = .uncategorized
                } label: {
                    Label("\(localization.L(L10n.Mods.categoryFilterUncategorized))   (\(uncatCount))", systemImage: "circle.dashed")
                }
            }
            if !categories.isEmpty {
                Divider()
            }
            ForEach(categories, id: \.category.id) { entry in
                Button {
                    listState.filters.category = .category(entry.category)
                } label: {
                    // SwiftUI Menus render Button labels as plain text — an
                    // HStack would only show its first child. Concatenating
                    // Text views (or building a single string) keeps both the
                    // icon and the category name visible in the row.
                    Text(entry.category.emoji + " " + entry.category.localizedName(localization.L) + "   (\(entry.count))")
                }
            }
            // Offline fallback: mods with no Nexus category, grouped by their
            // inferred type tag instead of a single "uncategorized" bucket.
            if !tagBuckets.isEmpty {
                Divider()
                ForEach(tagBuckets, id: \.tag) { bucket in
                    Button {
                        listState.filters.category = .inferredTag(bucket.tag)
                    } label: {
                        Text("\(bucket.label)   (\(bucket.count))")
                    }
                }
            }
            if filters.category != .all {
                Divider()
                Button(role: .destructive) {
                    listState.filters.category = .all
                } label: {
                    Label(localization.L(L10n.Mods.categoryFilterClear), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                switch filters.category {
                case .all:
                    Image(systemName: "tag")
                        .font(AppDesign.Font.footnote)
                    Text(localization.L(L10n.Mods.categoryFilter))
                        .font(AppDesign.Font.caption(.medium))
                case .category(let cat):
                    Circle()
                        .fill(Color(cat.color))
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(localization.L))
                        .font(AppDesign.Font.caption(.medium))
                case .inferredTag(let tag):
                    Image(systemName: "tag.circle")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(localization.L(L10n.ModTag.key(for: tag)))
                        .font(AppDesign.Font.caption(.medium))
                case .uncategorized:
                    Image(systemName: "circle.dashed")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(localization.L(L10n.Mods.categoryFilterUncategorized))
                        .font(AppDesign.Font.caption(.medium))
                }
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

}
