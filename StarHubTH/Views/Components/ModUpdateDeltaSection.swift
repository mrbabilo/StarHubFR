import SwiftUI

/// C2-T4 §7.2 — ce que la dernière mise à jour du mod a changé à ses clés :
/// compteurs, listes dépliables paginées, et les deux boutons qui conduisent
/// aux outils (éditeur de config, diff de traduction cadré sur les
/// manquantes). Se rend vide quand le mod n'a pas de delta — c'est l'état
/// ordinaire, pas un problème.
struct ModUpdateDeltaSection: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    /// Ouvre l'éditeur de config sur ce mod. La fiche vit déjà sur l'onglet
    /// Mods : poser `pendingConfigFocus` ne servirait à rien — ce canal n'est
    /// consommé que par un CHANGEMENT d'onglet (MainView.onChange). La fiche
    /// passe donc le geste direct.
    let onOpenConfig: () -> Void
    /// Ouvre l'onglet traduction de la fiche, le diff cadré sur les
    /// manquantes (`pendingTranslationDiffFilter` est posé par le parent
    /// avant le changement d'onglet interne).
    let onOpenTranslation: () -> Void

    @State private var shownAdded = 50
    @State private var shownRemoved = 50
    @State private var showReportConfigConfirm = false
    @State private var showReportTranslationConfirm = false
    /// Le retour du dernier report (« Report effectué : N clés » ou
    /// « Rien à reporter »), affiché sous les boutons jusqu'au suivant.
    @State private var reportMessage: String?

    var body: some View {
        if let delta = vm.updateKeyDelta(for: mod) {
            StandardSection(title: vm.L(L10n.Mods.updateDeltaTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(delta.date, style: .date)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(counters(delta).joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .textSelection(.enabled)
                    renamedSubsection(delta)
                    lists(delta)
                    buttons(delta)
                }
                .confirmationDialog(vm.L(L10n.Mods.updateDeltaRenamedTitle),
                                    isPresented: $showReportConfigConfirm,
                                    titleVisibility: .visible) {
                    Button(vm.L(L10n.Mods.updateDeltaRenamedReportConfig)) {
                        doReport { vm.applyRenameReportConfig(proposedPairs(for: delta).config, to: mod) }
                    }
                }
                .confirmationDialog(vm.L(L10n.Mods.updateDeltaRenamedTitle),
                                    isPresented: $showReportTranslationConfirm,
                                    titleVisibility: .visible) {
                    Button(vm.L(L10n.Mods.updateDeltaRenamedReportTranslation)) {
                        doReport { vm.applyRenameReportTranslation(proposedPairs(for: delta).translation, to: mod) }
                    }
                }
            }
        }
    }

    // MARK: - Clés renommées (C2-T4 §8)

    /// Les paires proposées, montrées AVANT action : celles par valeur sont
    /// sûres (point plein), celles par nom sont une heuristique à vérifier
    /// à l'œil (point creux).
    private func proposedPairs(for delta: ModUpdateKeyDelta) -> (translation: [RenamePair], config: [RenamePair]) {
        vm.renamePairs(for: delta)
    }

    @ViewBuilder
    private func renamedSubsection(_ delta: ModUpdateKeyDelta) -> some View {
        let proposed = proposedPairs(for: delta)
        if !proposed.translation.isEmpty || !proposed.config.isEmpty {
            // Les paires par valeur sont le signal sûr ; le reste vient de
            // l'heuristique de nom — le point creux dit « vérifiez ». La
            // config n'a pas de signal par valeur (ses valeurs sont des
            // réglages, pas des textes) : TOUTES ses paires sont
            // heuristiques, donc creuses.
            let safeTranslation = Set(KeyRenameMatcher.pairsByValue(
                old: delta.translation.removedKeys,
                new: delta.translation.addedUntranslated))
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.L(L10n.Mods.updateDeltaRenamedTitle))
                    .font(.system(size: 12, weight: .semibold))
                Text(vm.L(L10n.Mods.updateDeltaRenamedExplain))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ForEach(proposed.config, id: \.oldKey) { pair in
                    pairRow(pair, safe: false)
                }
                ForEach(proposed.translation, id: \.oldKey) { pair in
                    pairRow(pair, safe: safeTranslation.contains(pair))
                }
                HStack(spacing: 12) {
                    if !proposed.config.isEmpty {
                        Button(vm.L(L10n.Mods.updateDeltaRenamedReportConfig)) {
                            showReportConfigConfirm = true
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .pointingHandCursor()
                    }
                    if !proposed.translation.isEmpty {
                        Button(vm.L(L10n.Mods.updateDeltaRenamedReportTranslation)) {
                            showReportTranslationConfirm = true
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .pointingHandCursor()
                    }
                }
                if let message = reportMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 8)
        }
    }

    private func pairRow(_ pair: RenamePair, safe: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: safe ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundColor(safe ? .green : .secondary)
            Text(pair.oldKey)
                .font(.system(size: 11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(pair.newKey)
                .font(.system(size: 11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .textSelection(.enabled)
    }

    private func doReport(_ action: () -> KeyRenameReportOutcome) {
        switch action() {
        case .applied(let count):
            reportMessage = String(format: vm.L(L10n.Mods.updateDeltaRenamedDone), count)
        case .cancelled:
            // « Rien à reporter » ferait conclure que les paires étaient
            // fantaisistes ; le vrai état est « annulé pour sécurité ».
            reportMessage = vm.L(L10n.Mods.updateDeltaRenamedCancelled)
        case .nothingLeft:
            reportMessage = vm.L(L10n.Mods.updateDeltaRenamedNoneLeft)
        }
    }

    // MARK: - Compteurs

    /// Les compteurs non nuls, dans l'ordre de lecture : config d'abord,
    /// traduction ensuite, renommages en suffixe.
    private func counters(_ delta: ModUpdateKeyDelta) -> [String] {
        var parts: [String] = []
        if let added = delta.config?.added.count, added > 0 {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaConfigAdded), added))
        }
        if let removed = delta.config?.removed.count, removed > 0 {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaConfigRemoved), removed))
        }
        if !delta.translation.addedUntranslated.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationTodo),
                                delta.translation.addedUntranslated.count))
        }
        if !delta.translation.addedAuthorTranslated.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationAuthor),
                                delta.translation.addedAuthorTranslated.count))
        }
        if !delta.translation.removedKeys.isEmpty {
            parts.append(String(format: vm.L(L10n.Mods.updateDeltaTranslationOrphan),
                                delta.translation.removedKeys.count))
        }
        return parts
    }

    // MARK: - Listes

    private func lists(_ delta: ModUpdateKeyDelta) -> some View {
        let added = (Array(delta.translation.addedUntranslated.keys)
            + Array(delta.translation.addedAuthorTranslated.keys)).sorted()
        let removed = delta.translation.removedKeys.keys.sorted()
        return VStack(alignment: .leading, spacing: 6) {
            if !added.isEmpty {
                DisclosureGroup("\(vm.L(L10n.Mods.updateDeltaListAdded)) (\(added.count))") {
                    keyList(added, shown: shownAdded, more: {
                        shownAdded += 50
                    })
                }
            }
            if !removed.isEmpty {
                DisclosureGroup("\(vm.L(L10n.Mods.updateDeltaListRemoved)) (\(removed.count))") {
                    keyList(removed, shown: shownRemoved, more: {
                        shownRemoved += 50
                    })
                }
            }
        }
    }

    /// Les clés, paginées (`LazyVStack` pour les longues listes — une `List`
    /// beach-ballait à 2 000 lignes ; ici une clé par ligne, jamais par
    /// index — l'identité est la donnée stable elle-même).
    private func keyList(_ keys: [String], shown: Int, more: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(keys.prefix(shown), id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11).monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if shown < keys.count {
                Button("\(keys.count - shown)…") {
                    more()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .pointingHandCursor()
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Boutons

    @ViewBuilder
    private func buttons(_ delta: ModUpdateKeyDelta) -> some View {
        HStack(spacing: 12) {
            if delta.config?.added.isEmpty == false {
                Button(vm.L(L10n.Mods.updateDeltaOpenConfig)) {
                    onOpenConfig()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .pointingHandCursor()
            }
            if delta.translation.addedUntranslated.isEmpty == false {
                Button(vm.L(L10n.Mods.updateDeltaOpenTranslation)) {
                    onOpenTranslation()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .pointingHandCursor()
            }
        }
    }
}
