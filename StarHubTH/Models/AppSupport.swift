import Foundation

/// Le répertoire de données de l'application, et lui seul.
///
/// **Un seul endroit qui le construit.** Il en existait d'abord six, chacun
/// répétant `appendingPathComponent("StarHubTH")` — c'est la forme exacte que
/// ce dépôt a déjà payée : des copies qui divergent, et un renommage qui en
/// oublie une. Re-compté le 2026-09-10, ils sont quatorze (sept stores de plus
/// depuis le plan) : la tâche 4 les branche tous ici.
///
/// `Backups/` n'en fait délibérément pas partie : voir
/// `ModInstallBackupManager`.
public enum AppSupport {
    /// Le nom du dossier. `StarHubFR` et non `StarHubTH` : l'application
    /// d'origine, dont ce dépôt est un fork, écrit encore dans le second
    /// (`StarHubTH_debug.log` et `Avatars/`, vérifié sur son dépôt le
    /// 2026-08-26). Les deux installées côte à côte se marcheraient dessus.
    static let folderName = "StarHubFR"
    static let legacyFolderName = "StarHubTH"

    /// Le répertoire, créé s'il manque. `nil` quand le système ne rend aucun
    /// dossier de support — cas où l'app ne peut de toute façon rien persister.
    public static let directory: URL? = resolve()

    /// Le dossier des avatars de sauvegarde. Un seul endroit le construit :
    /// le ViewModel y copie l'image choisie, `SaveHeroPortrait` l'y retrouve
    /// quand le chemin absolu stocké dans `SaveNotes_v2` a été périmé par un
    /// déplacement du dossier de données.
    public static var avatarsDirectory: URL? {
        directory?.appendingPathComponent("Avatars", isDirectory: true)
    }

    private static func resolve() -> URL? {
        // **La reprise des préférences part d'ici, et c'est le point du
        // dispositif.** Elle est aussi déclenchée depuis `StarHubTHApp`, mais
        // cet ordre-là serait une affirmation statique ; celui-ci se prouve —
        // le premier initialisateur stocké du ViewModel qui touche quoi que ce
        // soit passe par `directory`, donc par ici. Idempotente : le second
        // appel ne coûte rien. Voir `DefaultsMigration.runOnce`.
        _ = DefaultsMigration.runOnce
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let target = base.appendingPathComponent(folderName, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        // **Ici et pas au lancement.** `StarHubTHApp` construit son ViewModel
        // dans un initialiseur de propriété, qui s'exécute avant le corps de
        // `init()` — et ce ViewModel lit deux stores dès sa construction. Aucun
        // point d'entrée de l'app n'est donc assez tôt. Un `static let` l'est :
        // Swift garantit qu'il ne s'évalue qu'une fois, à la première lecture.
        _ = migrate(from: legacy, to: target, fileManager: .default)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        // **Hors du garde de `migrate`, et c'est le point.** Une installation
        // migrée avant le correctif des slashes échappés a son ancien dossier
        // déjà vidé et sa destination déjà peuplée : les deux gardes du
        // déplacement l'écartent, et son index continuerait de mentir.
        repairStalePaths(in: target, legacyRoot: legacy, fileManager: .default)
        return target
    }

    /// Les index qui portent des chemins **absolus** : tout déplacement du
    /// dossier doit les repointer, et le `.bak` compte autant que le principal
    /// — `InstalledTranslationStore` le promeut quand le principal est corrompu.
    static let pathBearingIndexes = ["installed_translations.json",
                                     "installed_translations.json.bak"]

    /// Repointe les chemins d'une installation **déjà migrée** dont les index
    /// sont restés à l'ancienne racine.
    ///
    /// La réécriture d'origine était aveugle aux slashes échappés que produit
    /// un `JSONEncoder` nu : elle ne trouvait rien, rendait `nil`, et le
    /// dossier partait avec ses chemins périmés. Les sauvegardes, elles, ont
    /// bien suivi — seul l'index ment. Mesuré sur le parc le 2026-09-10 :
    /// **six greffes actives** dans cet état ; en retirer une aurait supprimé
    /// le fichier de l'utilisateur au lieu de le rendre
    /// (`ManifestlessInstaller.uninstall` supprime quand la sauvegarde est
    /// introuvable).
    ///
    /// Séparée de `migrate`, et pas un cas particulier de celle-ci : ses deux
    /// gardes — ancien dossier présent, destination encore vide — écartent
    /// précisément l'installation à réparer.
    ///
    /// - Returns: combien de fichiers ont été repointés. Idempotente : 0 dès
    ///   que plus rien ne pointe vers l'ancienne racine.
    @discardableResult
    static func repairStalePaths(in target: URL, legacyRoot: URL,
                                 fileManager fm: FileManager) -> Int {
        var repaired = 0
        for name in pathBearingIndexes {
            let url = target.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let rewritten = AppSupportMigration.rewrite(data,
                                                              from: legacyRoot.path,
                                                              to: target.path)
            else { continue }
            // Un échec d'écriture n'est pas fatal : l'index reste tel quel et
            // le prochain lancement retentera. Rien n'est perdu entre-temps —
            // les sauvegardes, elles, sont bien à leur nouvelle place.
            guard (try? rewritten.write(to: url, options: .atomic)) != nil else { continue }
            repaired += 1
        }
        return repaired
    }

    /// Déplace les données de l'ancien dossier vers le nouveau, **après** avoir
    /// repointé les chemins absolus qu'elles contiennent.
    ///
    /// - Returns: `false` quand la migration a été tentée et a échoué. Rien à
    ///   migrer rend `true` : ce n'est pas un échec.
    ///
    /// **L'ordre n'est pas négociable.** La réécriture d'abord, dans l'ancien
    /// dossier, sur une copie de travail ; le déplacement seulement si elle a
    /// abouti. Un dossier déplacé dont le registre pointerait encore vers
    /// l'ancien chemin ferait *supprimer* les fichiers d'origine du parc au
    /// premier retrait de greffe — `ManifestlessInstaller.uninstall` supprime
    /// quand la sauvegarde est introuvable.
    ///
    /// `Backups/` reste dans l'ancien dossier : son index porte 1 309 chemins
    /// absolus, et l'application d'origine n'y écrit jamais.
    @discardableResult
    static func migrate(from legacy: URL, to target: URL, fileManager fm: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: legacy.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return true }
        // **Le `.bak` compte autant que le principal.** `InstalledTranslationStore`
        // écrit les deux à chaque enregistrement et promeut le `.bak` quand le
        // principal est corrompu : un `.bak` laissé aux chemins périmés ferait
        // *supprimer* les fichiers d'origine du parc au premier retrait de
        // greffe, exactement le défaut que cette réécriture existe pour éviter.
        for name in pathBearingIndexes {
            let source = legacy.appendingPathComponent(name)
            let destination = target.appendingPathComponent(name)
            // La réécriture d'abord, et seulement si ce fichier-là va bouger :
            // une destination qui en a déjà un porte des données plus récentes.
            guard !fm.fileExists(atPath: destination.path),
                  let data = try? Data(contentsOf: source),
                  let rewritten = AppSupportMigration.rewrite(data,
                                                              from: legacy.path,
                                                              to: target.path)
            else { continue }
            do {
                try rewritten.write(to: source, options: .atomic)
            } catch {
                // Rien n'a bougé : le dossier est intact, et un prochain
                // lancement retentera.
                return false
            }
        }

        // **Toujours entrée par entrée, jamais le dossier entier.** `Backups/`
        // doit rester derrière, et surtout : un déplacement en bloc qui échoue
        // au milieu laisserait un état à moitié migré qu'aucun second passage
        // ne saurait reprendre. Entrée par entrée, en sautant ce qui est déjà
        // arrivé, la migration est **reprenable** — elle peut échouer, être
        // relancée, et finir le travail.
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: legacy.path) {
                // `Backups/` reste, délibérément (1 309 chemins absolus).
                guard name != "Backups" else { continue }
                let destination = target.appendingPathComponent(name)
                // Déjà arrivé : ne pas écraser. Ce qui est en place est plus
                // récent que ce qui attend encore dans l'ancien dossier.
                guard !fm.fileExists(atPath: destination.path) else { continue }
                try fm.moveItem(at: legacy.appendingPathComponent(name), to: destination)
            }
            // Un ancien dossier vidé de tout s'en va ; s'il garde `Backups/`,
            // il reste, et c'est voulu.
            if let rest = try? fm.contentsOfDirectory(atPath: legacy.path), rest.isEmpty {
                try? fm.removeItem(at: legacy)
            }
        } catch {
            return false
        }
        return true
    }
}
