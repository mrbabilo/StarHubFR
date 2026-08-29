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
///   packs…`) n'est pas filtré par les verdicts** : `ModConflictPair` ne
///   modélise qu'une paire de deux. Étendre le filtre à toutes les paires
///   internes d'un groupe de 3+ aurait supposé une sémantique que le
///   magasin des verdicts ne porte pas (task 9, qui écrit les verdicts,
///   n'a pas non plus ce cas). Cas rare en pratique — jamais rencontré sur
///   le parc de 966 mods qui a servi de repère à cet axe.
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
///   post-scripta inconditionnels, montrés même sous le vert — même patron
///   que `pausedIgnored`/`catalogModsIgnored` sous le vert de
///   `KeybindReportSection`. Sans ça, un utilisateur qui a écarté 3 paires
///   verrait soit un vert qui tait ce fait, soit jamais de vert du tout.
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
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
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
    private func pair(_ conflict: LoadConflict) -> ModConflictPair? {
        let names = folders(conflict)
        switch conflict.kind {
        case .withinOnePack:
            guard let only = names.first else { return nil }
            return ModConflictPair(only, only)
        case .betweenPacks:
            guard names.count == 2 else { return nil }
            return ModConflictPair(names[0], names[1])
        }
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

    private func bothActive(_ conflict: LoadConflict) -> Bool {
        let names = folders(conflict)
        guard !names.isEmpty else { return false }
        let enabledFolders = Set(installedMods.filter(\.isEnabled).map(\.folderName))
        return Set(names).isSubset(of: enabledFolders)
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
        if betweenPacksConflicts.isEmpty && withinOnePackConflicts.isEmpty && declaredPairs.isEmpty {
            if vm.smapiLogDate == nil {
                statusRow(icon: "info.circle", color: .secondary,
                          text: vm.L(L10n.Conflicts.noLogRead))
            } else {
                statusRow(icon: "checkmark.circle.fill", color: .green,
                          text: vm.L(L10n.Conflicts.noneObserved))
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
                if bothActive(conflict) {
                    badge(vm.L(L10n.Conflicts.bothActive))
                }
            }
            Text(String(format: vm.L(L10n.Conflicts.asset), conflict.asset))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func withinOnePackRow(_ conflict: LoadConflict) -> some View {
        let name = displayName(folders(conflict).first ?? "")
        return Text(String(format: vm.L(L10n.Conflicts.withinOne), name))
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1).truncationMode(.middle)
    }

    private func declaredRow(_ pair: ModConflictPair) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text("· \(displayName(pair.first)) × \(displayName(pair.second))")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            badge(vm.L(L10n.Conflicts.declaredByYou))
        }
    }
}
