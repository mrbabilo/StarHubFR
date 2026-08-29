import SwiftUI

/// La section « Conflits entre mods », dans l'onglet Alertes système, juste
/// après `KeybindReportSection` (spec A5-T2, tâche 8).
///
/// Trois sources bien distinctes, jamais mélangées :
/// - `vm.contentPatcherConflicts` : ce que Content Patcher a **constaté** en
///   rejouant, lu dans le journal SMAPI de la dernière partie — un fait
///   passé, pas l'état du parc aujourd'hui.
/// - `vm.modConflictVerdicts.declared` : ce que l'utilisateur a **déclaré**
///   lui-même, sans que rien ne l'ait détecté.
/// - `vm.modConflictVerdicts.dismissed` : ce que l'utilisateur a **écarté**
///   d'un précédent constat — retiré des deux listes ci-dessus, jamais
///   effacé du disque (voir `ModConflictVerdicts.orphans`).
///
/// Écarts au canevas du brief (mesurés en écrivant cette vue) :
/// - **Aucun `.onAppear`** : contrairement à `KeybindReportSection`, qui
///   déclenche son propre scan, `contentPatcherConflicts` est déjà publiée
///   par les deux chemins de lecture du journal (`refreshSmapiLog` et le
///   scan ordinaire). Un scan ici serait un second chemin qui doublonnerait
///   le travail sans rien ajouter.
/// - **`vm.mods.flattenedMods`, pas `vm.mods`** : un content pack est un
///   enfant de son pack parent (`ModItem.children`), pas une entrée de
///   premier niveau — comparer directement contre `vm.mods` manquerait tout
///   pack, et c'est justement le terrain de Content Patcher. Même repli que
///   `resolveModFolder(forLoggedName:)` dans le ViewModel.
/// - **Correspondance « paire écartée » pour `withinOnePack`** : le brief
///   demande de retirer les paires écartées des points 2 **à 4**, y compris
///   donc les conflits « un seul pack ». `ModConflictPair` accepte deux noms
///   identiques (`first == second`), ce qui donne une clé stable pour ce
///   cas d'auto-conflit — sans ce repli, un conflit `withinOnePack` écarté
///   une fois reviendrait à chaque relecture du journal.
/// - **Un conflit `betweenPacks` à plus de deux packs (`Multiple content
///   packs…`) n'est jamais filtré par les verdicts, dans les deux sens** :
///   `pair(_:)` rend `nil` pour ce cas — `ModConflictPair` ne modélise
///   qu'une paire de deux, et choisir laquelle des C(n,2) paires internes
///   représenterait le groupe serait une décision de modélisation que rien
///   n'impose ici. Concrètement : un tel conflit ne peut **ni** être écarté
///   **ni** revenir après l'avoir été — `liveConflicts` ne le retire jamais
///   de la liste affichée. Si la tâche 9 lui donne un bouton « Écarter »
///   quand même, un clic dessus produira un verdict que ce fichier ne sait
///   pas lire : le repli « N écarté(s) » compterait sans que la ligne
///   correspondante ne disparaisse jamais — une contradiction visible, pas
///   un simple oubli. Cas rare en pratique — jamais rencontré sur le parc
///   de 966 mods qui a servi de repère à cet axe.
/// - **`%lld` plutôt que le `%d` du canevas brief** pour les deux compteurs
///   (`conflicts_dismissed_count`, `conflicts_orphans`) : convention du
///   dépôt déjà posée par `KeybindReportSection` (`keybinds_collisions_header`
///   et consorts) — `Int` est 64 bits sur cette plateforme, `%d` attend un
///   `Int32` et rendrait un nombre au hasard.
/// - **Noms d'affichage résolus via `vm.mods.flattenedMods`** partout,
///   y compris pour les paires déclarées par l'utilisateur : `ModConflictPair`
///   ne porte que des `folderName`, illisibles tels quels dans une liste
///   destinée à l'utilisateur. Un nom non résolu (mod désinstallé, ou nom
///   d'affichage que Content Patcher a mal découpé) reste affiché tel quel —
///   jamais tu, même imparfait.
/// - **Le vert « aucun conflit » ne couvre que les points 2 à 4** (les
///   éléments qui appellent une action ou une lecture) : le compteur des
///   paires écartées et la ligne des verdicts orphelins restent des
///   post-scripta inconditionnels, montrés même sous le vert. Voir aussi
///   « Ronde de correction 1 » plus bas : le test de vacuité lui-même a dû
///   changer une fois cette idée poussée jusqu'au bout.
/// - **Un état de plus que le canevas** (`conflicts_no_log`), sur le même
///   principe que les deux états ajoutés par `KeybindReportSection`
///   (`noGameDir`, `noModsScanned`) : le vert « aucun conflit dans le
///   journal » ne doit sortir que si un journal a effectivement été lu.
///   `vm.smapiLogDate == nil` distingue les deux cas — ce n'est pas une
///   simple absence de conflit, c'est une absence de lecture, et les
///   confondre serait le vert mensonger que le canevas demande justement
///   de refuser (brief, point 7 : « surtout pas un silence »). Les paires
///   déclarées restent visibles dans les deux cas : elles ne dépendent pas
///   du journal.
///
/// **Ronde de correction 1** (relecture du 2026-08-30) — deux constats
/// « Important », les deux sur le même thème : une affirmation qui ne
/// tenait plus une fois un cas limite poussé au bout.
/// - **Constat 1, le vert mensonger était encore possible.** Le test de
///   vacuité portait sur les listes **après** filtrage des paires écartées
///   (`betweenPacksConflicts`/`withinOnePackConflicts`/`declaredPairs`), pas
///   sur `vm.contentPatcherConflicts` brut. Scénario réel : le journal
///   rapporte deux conflits, l'utilisateur les écarte tous les deux (tâche
///   9), les trois listes filtrées se vident, `smapiLogDate` existe toujours
///   — et l'ancien code affichait « Aucun conflit dans le journal de la
///   dernière partie » à côté de « 2 écarté(s) » juste en dessous. La phrase
///   affirme un fait sur le journal, et ce fait était faux : le journal en
///   contenait deux. La défense initiale (« même patron que
///   `pausedIgnored`/`catalogModsIgnored` ») ne tenait pas : ces compteurs-là
///   comptent des entrées **jamais scannées**, donc leur vert reste vrai ;
///   une paire écartée est un conflit **détecté puis masqué par choix**, pas
///   la même garantie. Correctif : le vert n'affirme plus rien sauf si
///   **rien n'a été filtré**, c'est-à-dire si `vm.contentPatcherConflicts`
///   (non filtré) est vide — sinon une ligne neutre dédiée
///   (`conflicts_all_dismissed`) dit ce qui est vrai : tout ce que le
///   journal rapportait a été écarté. Voir `content`.
/// - **Constat 2, « Les deux sont actifs » était faux au pluriel.** Un
///   conflit `betweenPacks` peut citer trois packs ou plus (forme
///   « Multiple content packs » que `ContentPatcherConflicts.parse` gère).
///   L'ancien `bothActive(_:)` testait correctement **tous** les noms, mais
///   le badge affichait littéralement « Les deux sont actifs » même à
///   quatre. Correctif : `activeBadgeLabel(for:)` choisit entre
///   `conflicts_both_active` (exactement deux packs) et le nouveau
///   `conflicts_all_active` (trois ou plus).
/// - **Mineur, au passage** : le glyphe d'en-tête était figé sur
///   `exclamationmark.triangle.fill` orange, y compris quand le corps
///   affichait le vert. `KeybindReportSection.header` garde un glyphe
///   neutre (`keyboard`, couleur par défaut) et réserve la couleur
///   sémantique à la ligne de statut du corps — repris ici avec
///   `arrow.triangle.merge`.
///
/// **Tâche 9** — les boutons « Écarter » : un par ligne, jamais sur un
/// `betweenPacks` à 3 packs ou plus (`pair(_:)` y rend `nil`, voir le
/// paragraphe qui suit). `pair(_:)` délègue désormais à
/// `vm.conflictPair(for:)` — la fiche d'un mod (« Signaler »/« Écarter ») et
/// `vm.conflictWarning(for:)` en ont besoin aussi, une seule correspondance
/// partagée plutôt que trois copies qui auraient fini par diverger.
struct ModConflictSection: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            header
            content
        }
        .padding(AppDesign.Spacing.lg)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
    }

    private var header: some View {
        HStack {
            // Glyphe neutre, couleur par défaut : la couleur sémantique
            // (vert/orange/gris) vit sur la ligne de statut du corps, pas
            // ici — même patron que `KeybindReportSection.header`, dont le
            // glyphe `keyboard` ne préjuge pas non plus du contenu
            // (ronde de correction 1, mineur).
            Image(systemName: "arrow.triangle.merge")
            Text(vm.L(L10n.Conflicts.title))
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: AppDesign.Spacing.sm)
            // Le journal décrit la dernière partie jouée, pas l'état actuel
            // du parc : le dire est une exigence, pas une politesse (brief,
            // point 1). Absent tant qu'aucun journal n'a jamais été lu.
            if let date = vm.smapiLogDate {
                Text(String(format: vm.L(L10n.Conflicts.observedAt),
                            DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Données dérivées

    /// Les mods installés aujourd'hui, packs dépliés — c'est contre cette
    /// liste, jamais contre le journal, que « les deux actifs » se juge.
    private var installedMods: [ModItem] {
        vm.mods.flattenedMods
    }

    private func displayName(_ folderName: String) -> String {
        installedMods.first(where: { $0.folderName == folderName })?.name ?? folderName
    }

    /// Les `folderName` d'un conflit, résolus une fois pour toutes.
    private func folders(_ conflict: LoadConflict) -> [String] {
        vm.conflictFolderNames(conflict)
    }

    /// La paire canonique d'un conflit, quand elle est représentable. `nil`
    /// pour un `betweenPacks` à plus de deux packs (voir le commentaire de
    /// tête) : ce conflit n'est alors jamais filtré par un verdict.
    ///
    /// Déléguée au ViewModel (tâche 9, `vm.conflictPair(for:)`) : la fiche
    /// d'un mod (« Signaler »/« Écarter ») et `conflictWarning(for:)` en ont
    /// besoin aussi — une seule correspondance conflit ↔ paire, pas une
    /// copie par écran qui aurait fini par diverger.
    private func pair(_ conflict: LoadConflict) -> ModConflictPair? {
        vm.conflictPair(for: conflict)
    }

    private var dismissedPairs: Set<ModConflictPair> {
        Set(vm.modConflictVerdicts.dismissed)
    }

    /// Les conflits du journal, paires écartées retirées (brief : « les
    /// paires écartées sont retirées des points 2 à 4 »).
    private func liveConflicts(kind: LoadConflict.Kind) -> [LoadConflict] {
        vm.contentPatcherConflicts.filter { conflict in
            guard conflict.kind == kind else { return false }
            if let p = pair(conflict), dismissedPairs.contains(p) { return false }
            return true
        }
    }

    private var betweenPacksConflicts: [LoadConflict] { liveConflicts(kind: .betweenPacks) }
    private var withinOnePackConflicts: [LoadConflict] { liveConflicts(kind: .withinOnePack) }
    private var declaredPairs: [ModConflictPair] { vm.modConflictVerdicts.declared }

    /// Le libellé du badge « actifs », ou `nil` si au moins un pack cité
    /// n'est pas installé et activé aujourd'hui. Deux libellés distincts
    /// (ronde de correction 1, constat 2) : un `betweenPacks` peut citer
    /// trois packs ou plus (forme « Multiple content packs » que
    /// `ContentPatcherConflicts.parse` gère) — « Les deux sont actifs »
    /// serait faux par construction au-delà de deux.
    private func activeBadgeLabel(for conflict: LoadConflict) -> String? {
        let names = folders(conflict)
        guard !names.isEmpty else { return nil }
        let enabledFolders = Set(installedMods.filter(\.isEnabled).map(\.folderName))
        guard Set(names).isSubset(of: enabledFolders) else { return nil }
        return names.count == 2 ? vm.L(L10n.Conflicts.bothActive) : vm.L(L10n.Conflicts.allActive)
    }

    // MARK: - Corps

    @ViewBuilder private var content: some View {
        // Le vert ne couvre que ce qui appelle une lecture ou une action —
        // les post-scripta (écartés, orphelins) restent en dehors de ce
        // test, voir le commentaire de tête. Et le vert lui-même ne sort
        // que si un journal a réellement été lu : `smapiLogDate` et
        // `contentPatcherConflicts` sont remis à `nil`/`[]` ensemble quand
        // le fichier journal est absent (`parseSMAPILog`, StarHubTHViewModel
        // ~2972) — sans cette distinction, une installation qui n'a jamais
        // lancé le jeu via SMAPI lirait « aucun conflit », un vert mensonger
        // puisque rien n'a été regardé pour cet axe.
        //
        // Ronde de correction 1, constat 1 : le vert doit aussi rester vrai
        // une fois des paires écartées. `betweenPacksConflicts`/
        // `withinOnePackConflicts` sont déjà filtrées par verdict — les
        // trouver vides ne dit donc pas « le journal n'a rien rapporté »,
        // seulement « rien de non-écarté ne reste ». D'où le test sur
        // `vm.contentPatcherConflicts`, **non filtré** : s'il est vide, le
        // journal était réellement silencieux (vert légitime) ; s'il ne
        // l'est pas, tout ce qu'il contenait a été écarté par choix — un
        // fait différent, avec son propre libellé neutre.
        if betweenPacksConflicts.isEmpty && withinOnePackConflicts.isEmpty && declaredPairs.isEmpty {
            if vm.smapiLogDate == nil {
                statusRow(icon: "info.circle", color: .secondary,
                          text: vm.L(L10n.Conflicts.noLogRead))
            } else if vm.contentPatcherConflicts.isEmpty {
                statusRow(icon: "checkmark.circle.fill", color: .green,
                          text: vm.L(L10n.Conflicts.noneObserved))
            } else {
                statusRow(icon: "info.circle", color: .secondary,
                          text: vm.L(L10n.Conflicts.allDismissed))
            }
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                ForEach(betweenPacksConflicts, id: \.self) { conflict in
                    betweenPacksRow(conflict)
                }
                ForEach(withinOnePackConflicts, id: \.self) { conflict in
                    withinOnePackRow(conflict)
                }
                ForEach(declaredPairs, id: \.self) { p in
                    declaredRow(p)
                }
            }
        }

        // Post-scripta inconditionnels : voir le commentaire de tête.
        if !vm.modConflictVerdicts.dismissed.isEmpty {
            Text(String(format: vm.L(L10n.Conflicts.dismissedCount),
                        vm.modConflictVerdicts.dismissed.count))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        let orphanPairs = vm.modConflictVerdicts.orphans(among: installedMods.map(\.folderName))
        if !orphanPairs.isEmpty {
            Text(String(format: vm.L(L10n.Conflicts.orphans), orphanPairs.count))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).foregroundColor(.secondary)
        }
    }

    /// Le bouton « Écarter » d'une ligne de conflit (tâche 9). Jamais posé
    /// sur un `betweenPacks` à plus de deux packs : `pair` y est `nil` — un
    /// clic écrirait un verdict que ce fichier ne sait pas lire (la
    /// contradiction que le commentaire de tête met en garde).
    private func dismissButton(for pair: ModConflictPair) -> some View {
        Button(vm.L(L10n.Conflicts.dismissButton)) {
            vm.dismissConflict(pair)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .pointingHandCursor()
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, AppDesign.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(4)
    }

    private func betweenPacksRow(_ conflict: LoadConflict) -> some View {
        let names = folders(conflict).map(displayName)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Text("· \(names.joined(separator: " × "))")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                if let label = activeBadgeLabel(for: conflict) {
                    badge(label)
                }
                Spacer(minLength: AppDesign.Spacing.sm)
                // `nil` pour un `betweenPacks` à 3 packs ou plus : pas de
                // bouton, voir le commentaire de tête de `pair(_:)`.
                if let p = pair(conflict) {
                    dismissButton(for: p)
                }
            }
            Text(String(format: vm.L(L10n.Conflicts.asset), conflict.asset))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            // La TRACE « Affected patches » de Content Patcher : quel patch
            // de chaque mod réclame l'asset. Absente quand la TRACE a été
            // jetée par le cap mémoire du journal ou n'a jamais été écrite
            // (`withinOnePack` n'en émet pas) — vide veut dire inconnu, la
            // ligne s'abstient plutôt que d'inventer.
            if !conflict.affectedPatches.isEmpty {
                Text(String(format: vm.L(L10n.Conflicts.affectedPatches),
                            conflict.affectedPatches.joined(separator: ", ")))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func withinOnePackRow(_ conflict: LoadConflict) -> some View {
        let name = displayName(folders(conflict).first ?? "")
        return HStack(spacing: AppDesign.Spacing.xs) {
            Text(String(format: vm.L(L10n.Conflicts.withinOne), name))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: AppDesign.Spacing.sm)
            if let p = pair(conflict) {
                dismissButton(for: p)
            }
        }
    }

    private func declaredRow(_ pair: ModConflictPair) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text("· \(displayName(pair.first)) × \(displayName(pair.second))")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            badge(vm.L(L10n.Conflicts.declaredByYou))
            Spacer(minLength: AppDesign.Spacing.sm)
            dismissButton(for: pair)
        }
    }
}
