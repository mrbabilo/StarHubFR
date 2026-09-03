import Foundation

/// Agrège en une liste triée ce que l'app sait déjà de la santé du parc.
///
/// Pure et testée parce que le compte affiché en pied doit être **honnête** :
/// un compteur faux est pire qu'absent.
public enum HealthIssueResolver {

    public static func smapiIssues(_ diagnostics: SmapiDiagnostics?) -> [HealthIssue] {
        guard let d = diagnostics else { return [] }
        var issues: [HealthIssue] = []

        // `missingDeps` est un SOUS-ENSEMBLE de `failed`/`skipped` — le
        // parseur les y « promeut » (voir le commentaire sur
        // `missingDeps` dans SmapiLogDiagnostics.swift, et son `problemCount`
        // qui ne l'additionne pas séparément). Émettre une ligne par entrée
        // doublerait donc le compte affiché en pied de liste pour un même
        // mod. On enrichit à la place le détail de la ligne `failed`/
        // `skipped` d'origine, et on ne garde une ligne propre que pour le
        // cas défensif où le mod n'apparaît dans aucune des deux (ne devrait
        // jamais arriver côté parseur, mais l'info ne doit pas disparaître
        // si ça arrive quand même).
        let failedNames = Set(d.failed.map(\.name))
        let skippedNames = Set(d.skipped.map(\.name))

        for issue in d.failed {
            issues.append(HealthIssue(id: "smapi-failed-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name,
                                      detail: enrichedDetail(reason: issue.reason,
                                                             mod: issue.name,
                                                             missingDeps: d.missingDeps),
                                      actions: [.openMod(query: issue.name)]))
        }
        // Garde par SYMÉTRIE avec celle de `missingDeps` juste en dessous :
        // jamais vérifié sur un vrai journal (aucun n'en montre le cas), donc
        // posé par précaution plutôt qu'après coup. `skipped` porte le nom
        // SUIVI de sa version (« NEU Mod 1.0 ») alors que `failed` ne porte
        // que le nom du mod (« NEU Mod ») — un match exact entre les deux
        // ensembles de noms ne suffit pas, il faut reconnaître le suffixe de
        // version. Un `hasPrefix` NU sur-matcherait et supprimerait en
        // silence un mod `skipped` DIFFÉRENT dont le nom commence par celui
        // d'un mod `failed` (« Content Patcher » / « Content Patcher
        // Animations ») — un sous-comptage pire que le double-comptage visé
        // ici, parce que rien à l'écran ne signale la ligne manquante.
        // `isSameMod` ne retire donc que le DERNIER segment (la version) de
        // `skipped` avant de comparer.
        for issue in d.skipped where !failedNames.contains(where: {
            Self.isSameMod(failedName: $0, skippedName: issue.name)
        }) {
            issues.append(HealthIssue(id: "smapi-skipped-\(issue.name)",
                                      severity: .critical, source: .smapi,
                                      title: issue.name,
                                      detail: enrichedDetail(reason: issue.reason,
                                                             mod: issue.name,
                                                             missingDeps: d.missingDeps),
                                      // `issue.name` porte la version SUIVIE
                                      // du nom (« NEU Mod 1.0 ») — le titre la
                                      // garde (elle identifie la ligne), mais
                                      // `ModFocusResolver` ne fait ni préfixe
                                      // ni version : sans ce nettoyage, une
                                      // ligne skipped n'ouvrait JAMAIS sa
                                      // fiche (aucune fixture à la main
                                      // n'exerçait un nom versionné, d'où le
                                      // bogue passé inaperçu des tests).
                                      actions: [.openMod(query: Self.skippedModQuery(issue.name))]))
        }
        // Cas défensif seulement : un mod dont la dépendance manquante n'a
        // été promue dans aucune des deux listes ci-dessus.
        for dep in d.missingDeps where !failedNames.contains(dep.mod) && !skippedNames.contains(dep.mod) {
            issues.append(HealthIssue(id: "smapi-dep-\(dep.mod)-\(dep.missing)",
                                      severity: .critical, source: .smapi,
                                      title: dep.mod, detail: dep.missing,
                                      actions: [.openMod(query: dep.mod)]))
        }
        // Conflits externes et mods marqués « broken » par SMAPI : des
        // problèmes de chargement avérés au sens de `problemCount`
        // (SmapiLogDiagnostics.swift), donc au même titre que failed/skipped.
        // `externalConflicts` nomme un OUTIL (RivaTuner…), jamais un mod du
        // parc : `ModFocusResolver` n'y trouverait rien, la fiche n'a pas de
        // sens — le journal reste la seule trace utile.
        for name in d.externalConflicts {
            issues.append(HealthIssue(id: "smapi-conflict-\(name)",
                                      severity: .critical, source: .smapi,
                                      title: name, detail: nil,
                                      actions: [.openLogs(searchText: name)]))
        }
        for name in d.brokenMods {
            issues.append(HealthIssue(id: "smapi-broken-\(name)",
                                      severity: .critical, source: .smapi,
                                      title: name, detail: nil,
                                      actions: [.openMod(query: name)]))
        }
        for notice in d.benignNotices {
            issues.append(HealthIssue(id: "smapi-benign-\(notice.kind.rawValue)-\(notice.mod ?? "-")",
                                      severity: .info, source: .smapi,
                                      title: notice.mod ?? notice.kind.rawValue,
                                      // Sans mod, le titre était le rawValue de
                                      // l'enum — « galaxyAuth » affiché tel quel
                                      // au milieu d'une UI traduite (H-T6c,
                                      // constaté sur le journal de l'auteur).
                                      // La vue traduit la clé ; `title` reste le
                                      // repli.
                                      titleKey: notice.mod == nil ? notice.kind.l10nKey : nil,
                                      detail: notice.sample.isEmpty ? nil : notice.sample,
                                      // `notice.mod` est `nil` pour les notices
                                      // qui ne nomment aucun mod (Galaxy…) :
                                      // pas de fiche possible, on retombe sur
                                      // le journal — recherche sur l'exemple
                                      // brut si le parseur en a gardé un,
                                      // sinon sur le genre de notice lui-même.
                                      // Une information qui nomme un mod offre
                                      // les DEUX chemins : sa fiche dit ce
                                      // qu'est le mod, le journal ce qui s'est
                                      // passé. Sans mod, seul le journal
                                      // existe — pas de bouton mort à côté.
                                      actions: Self.benignActions(notice)))
        }
        return issues
    }

    public static func keybindIssues(_ report: KeybindScanner.KeybindReport?) -> [HealthIssue] {
        guard let report else { return [] }
        var issues: [HealthIssue] = []
        for collision in report.collisions {
            let modNames = collision.uses.map(\.modName).sorted()
            let mods = modNames.joined(separator: ", ")
            // `report.collisions` est indexé PAR combo : les deux mêmes mods
            // peuvent se disputer deux touches différentes (banal sur ~900
            // mods) — sans le combo dans l'id, ces deux lignes distinctes
            // partageraient la même identité (piège `ForEach`, CLAUDE.md).
            // `KeybindCombo.buttons` est déjà dédupliqué et trié
            // (`KeybindCombo.init?`), donc cette représentation est stable
            // entre deux résolutions.
            let comboKey = collision.combo.buttons.joined(separator: "+")
            issues.append(HealthIssue(id: "keybind-collision-\(comboKey)-\(mods)",
                                      severity: .warning, source: .keybind,
                                      title: mods, detail: nil,
                                      // Une collision oppose au moins deux
                                      // mods — un seul bouton ne peut désigner
                                      // qu'UN fautif : le premier par ordre
                                      // alphabétique, le même tri que `title`.
                                      actions: [.openMod(query: modNames.first ?? mods)]))
        }
        for conflict in report.gameConflicts {
            let modNames = conflict.uses.map(\.modName).sorted()
            let mods = modNames.joined(separator: ", ")
            issues.append(HealthIssue(id: "keybind-game-\(conflict.control.name)-\(mods)",
                                      severity: .warning, source: .keybind,
                                      title: mods, detail: conflict.control.name,
                                      actions: [.openMod(query: modNames.first ?? mods)]))
        }
        return issues
    }

    /// `ModConflictPair.first`/`.second` sont des `folderName` — pas des noms
    /// de mods. Les lignes voisines (raccourcis, SMAPI) affichent déjà des
    /// noms de mods : sans résolution, un conflit nommerait ses mods d'une
    /// troisième façon dans la même liste. `displayName` porte cette
    /// résolution — le ViewModel est seul à connaître `[ModItem]`, mais la
    /// RÈGLE (dossier → nom, repli sur le dossier si le mod est introuvable)
    /// reste ici, en un seul endroit, comme l'ancien `ModConflictSection.
    /// displayName(_:)` qu'elle remplace. Identité (`id`) construite sur les
    /// `folderName` bruts, jamais sur le nom résolu : elle doit rester stable
    /// même si un nom affiché change.
    public static func conflictIssues(_ conflicts: [ModConflictPair],
                                      displayName: (String) -> String = { $0 }) -> [HealthIssue] {
        conflicts.map { pair in
            HealthIssue(id: "conflict-\(pair.first)-\(pair.second)",
                        severity: .critical, source: .modConflict,
                        title: "\(displayName(pair.first)) · \(displayName(pair.second))",
                        detail: nil,
                        // Un conflit oppose deux mods ; `pair.first` en
                        // désigne un — c'est un `folderName`, ce qu'attend
                        // `ModFocusResolver` pour un conflit (voir la
                        // documentation de `Action.openMod`).
                        actions: [.openMod(query: pair.first)])
        }
    }

    /// Les dossiers réclamés par deux mods différents (X13).
    ///
    /// Sans cette ligne, la collision est **indétectable** : `ModItem.id` étant
    /// `folderName`, les deux mods partagent une identité `Identifiable` et un
    /// `ForEach` n'en rend qu'un — l'un disparaît de la liste sans que rien ne
    /// le dise, ni l'app, ni le jeu. On ne peut la découvrir qu'en comptant ses
    /// dossiers dans le Finder.
    ///
    /// `warning` et non `critical` : le jeu tourne — l'un des deux dossiers
    /// porte un point de tête, SMAPI ne charge que l'autre. Le dégât est dans
    /// l'app. Mais pas `info` non plus : ça cache un mod sans le dire.
    ///
    /// Le titre et le détail sont **injectés** : ce modèle vit dans Core, sans
    /// accès à la locale — même patron que `displayName` pour les conflits.
    /// L'unique action montre les deux dossiers dans le Finder ; voir
    /// `Action.revealInFinder` pour la raison qu'il n'y en a pas d'autre.
    public static func folderCollisionIssues(
        _ collisions: [ModFolderCollision.Collision],
        modsPath: String,
        title: (ModFolderCollision.Collision) -> String,
        detail: (ModFolderCollision.Collision) -> String) -> [HealthIssue] {
        collisions.map { collision in
            // Identité construite sur le dossier disputé, pas sur les noms
            // affichés : elle doit rester stable même si un manifeste change
            // de nom entre deux scans.
            HealthIssue(id: "folder-collision-\(collision.folderName)",
                        severity: .warning, source: .folderCollision,
                        title: title(collision), detail: detail(collision),
                        actions: collision.physicalFolderNames.isEmpty ? [] :
                            [.revealInFinder(paths: collision.physicalFolderNames.map {
                                (modsPath as NSString).appendingPathComponent($0)
                            })])
        }
    }

    /// Tri **stable** par gravité décroissante : à gravité égale, l'ordre de
    /// production (`smapiIssues` puis `keybindIssues` puis `conflictIssues`)
    /// est conservé, sinon les lignes sauteraient d'un rafraîchissement à
    /// l'autre. La clé secondaire `-offset` encode cette préservation
    /// explicitement — elle ne dépend pas de la stabilité, non garantie par
    /// la doc, de `Array.sorted`.
    public static func resolve(diagnostics: SmapiDiagnostics?,
                               keybindReport: KeybindScanner.KeybindReport?,
                               conflicts: [ModConflictPair],
                               folderCollisions: [HealthIssue] = [],
                               displayName: (String) -> String = { $0 }) -> [HealthIssue] {
        let all = smapiIssues(diagnostics)
            + keybindIssues(keybindReport)
            + conflictIssues(conflicts, displayName: displayName)
            + folderCollisions
        return all.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
    }

    /// `skippedIssue(fromLine:)` (SmapiLogDiagnostics.swift) construit son
    /// nom comme `<nom du mod> <version> because …` : tout avant le DERNIER
    /// espace est le nom, jamais plus. Retirer un préfixe suffirait à faire
    /// disparaître un mod dont le nom en contient un autre en entier
    /// (« Content Patcher Animations » contient « Content Patcher »).
    private static func isSameMod(failedName: String, skippedName: String) -> Bool {
        if failedName == skippedName { return true }
        guard let lastSpace = skippedName.lastIndex(of: " ") else { return false }
        return skippedName[skippedName.startIndex..<lastSpace] == failedName
    }

    /// Le nom NU d'un mod `skipped`, sans le suffixe de version que le
    /// parseur y accole (« NEU Mod 1.0 » → « NEU Mod ») — c'est ce nom que
    /// `ModFocusResolver.resolve` doit retrouver dans `[ModItem]`, qui ne
    /// connaît le mod que sous son nom nu. Même règle que `isSameMod`
    /// ci-dessus (le DERNIER segment est la version, jamais un préfixe), mais
    /// gardée : on ne retire ce segment que s'il commence par un chiffre,
    /// sinon un mod dont le nom se termine simplement par un mot
    /// (« Content Patcher Animations ») perdrait ce mot à tort.
    private static func skippedModQuery(_ name: String) -> String {
        guard let lastSpace = name.lastIndex(of: " ") else { return name }
        let suffix = name[name.index(after: lastSpace)...]
        guard let first = suffix.first, first.isNumber else { return name }
        return String(name[name.startIndex..<lastSpace])
    }

    /// Les chemins d'une notice bénigne : sa fiche quand elle nomme un mod,
    /// et TOUJOURS la ligne du journal — c'est là que le message brut se lit.
    private static func benignActions(_ notice: SmapiDiagnostics.BenignNotice) -> [HealthIssue.Action] {
        let searchable = logSearchText(fromSample: notice.sample)
        guard let mod = notice.mod else {
            // Sans mod, le repli sur le genre de notice tient : mieux vaut un
            // journal mal cadré qu'une ligne sans aucune issue.
            return [.openLogs(searchText: searchable ?? notice.kind.rawValue)]
        }
        // Avec un mod, ce repli n'a plus lieu d'être : le genre de notice
        // n'existe pas dans le journal, le bouton ouvrirait une recherche
        // vide À CÔTÉ d'un bouton qui, lui, mène quelque part.
        guard let searchable else { return [.openMod(query: mod)] }
        return [.openMod(query: mod), .openLogs(searchText: searchable)]
    }

    /// La recherche des Journaux pour une notice bénigne sans mod nommé.
    ///
    /// `notice.sample` vient de `SmapiLogDiagnostics.evidence(from:)`, qui
    /// tronque à 160 caractères et ajoute un « … » — un caractère ABSENT de
    /// la ligne réelle du journal. `LogsView` filtre par
    /// `message.contains(search)` : chercher le texte tronqué AVEC son
    /// ellipse ne matcherait jamais rien, un bouton qui ouvre un journal
    /// vide. Le retirer restaure un préfixe exact de la ligne d'origine.
    /// `nil` quand il ne reste rien à chercher : un exemple vide, ou réduit à
    /// sa seule ellipse de troncature. Rendre `""` posait un bouton qui vide
    /// simplement le filtre des Journaux au lieu d'y mener.
    private static func logSearchText(fromSample sample: String) -> String? {
        guard !sample.isEmpty else { return nil }
        guard sample.hasSuffix("…") else { return sample }
        let stripped = String(sample.dropLast()).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : stripped
    }

    /// Ajoute le nom de la dépendance manquante au détail, sauf s'il y
    /// figure déjà — le parseur reformule souvent la raison d'un `failed`
    /// pour l'y inclure (`"requires X (not installed)"`), et un ajout
    /// systématique répéterait alors la même information deux fois sur la
    /// même ligne.
    private static func enrichedDetail(reason: String, mod: String,
                                       missingDeps: [SmapiDiagnostics.MissingDep]) -> String {
        var detail = reason
        for dep in missingDeps where dep.mod == mod && !detail.contains(dep.missing) {
            detail += " (\(dep.missing))"
        }
        return detail
    }
}
