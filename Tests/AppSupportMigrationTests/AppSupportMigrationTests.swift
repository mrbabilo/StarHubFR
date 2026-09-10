import Testing
import Foundation
@testable import StarHubTHCore

struct AppSupportMigrationTests {
    /// **Le chemin destructeur.** `installed_translations.json` stocke des
    /// chemins **absolus** vers les sauvegardes de dépôt. Déplacer le dossier
    /// sans les réécrire ferait supprimer le fichier déposé au lieu de rendre
    /// l'original — `ManifestlessInstaller.uninstall` supprime quand la
    /// sauvegarde est introuvable.
    @Test func absolutePathsAreRewritten() throws {
        let old = "/Users/x/Library/Application Support/StarHubTH"
        let new = "/Users/x/Library/Application Support/StarHubFR"
        let json = Data("""
        {"byHost":{},"addonsByHost":{"ItemBags":[{"hostFolderName":"ItemBags",
        "nexusModId":48157,"nexusName":"Config","version":"1","installedAt":1,
        "files":["bagconfig.json"],
        "replacedFiles":{"bagconfig.json":"\(old)/TranslationBackups/ItemBags/a/bagconfig.json"}}]}}
        """.utf8)
        let rewritten = try #require(AppSupportMigration.rewrite(json, from: old, to: new))
        let text = String(decoding: rewritten, as: UTF8.self)
        #expect(text.contains("\(new)/TranslationBackups"))
        #expect(!text.contains("Support/StarHubTH/"))
    }

    /// Un JSON sans aucun chemin de l'ancien dossier n'est pas réécrit : rendre
    /// `nil` évite de réécrire 617 Ko pour rien.
    @Test func aFileWithNothingToRewriteIsLeftAlone() {
        let json = Data(#"{"byHost":{},"addonsByHost":{}}"#.utf8)
        #expect(AppSupportMigration.rewrite(json, from: "/a/StarHubTH", to: "/a/StarHubFR") == nil)
        #expect(!AppSupportMigration.needsRewrite(json, oldRoot: "/a/StarHubTH"))
    }

    /// **Ne réécrire que la racine.** Un mod nommé « StarHubTH » dans le dossier
    /// `Mods/` ne doit pas voir son chemin changer.
    @Test func onlyTheRootIsRewritten() throws {
        let old = "/Users/x/Library/Application Support/StarHubTH"
        let json = Data("""
        {"a":"\(old)/TranslationBackups/x","b":"/Applications/Game/Mods/StarHubTH/y"}
        """.utf8)
        let text = String(decoding: try #require(
            AppSupportMigration.rewrite(json, from: old, to: "/Users/x/Library/Application Support/StarHubFR")),
            as: UTF8.self)
        #expect(text.contains("/Applications/Game/Mods/StarHubTH/y"))
    }

    /// **La fixture vient du vrai producteur, pas de ma main.**
    ///
    /// Les trois index que la migration réécrit — `installed_translations.json`
    /// et son `.bak`, `install_metadata.json`, `metadata.json` — sont écrits
    /// par un `JSONEncoder` **nu**, qui échappe les slashes : le disque porte
    /// `…\/StarHubTH\/…`, pas `…/StarHubTH/…`. Toutes les autres fixtures de
    /// ce fichier sont écrites à la main avec des slashes nus, et c'est ce qui
    /// a laissé passer le défaut : `rewrite` ne trouvait rien, rendait `nil`
    /// en silence, et le dossier partait avec ses chemins périmés — le
    /// scénario destructeur exact que cette réécriture existe pour empêcher.
    ///
    /// Mesuré le 2026-09-10 sur le parc : 150 slashes du registre réel, tous
    /// échappés ; 220 `backupPath` de `install_metadata.json`, tous échappés.
    @Test func pathsEscapedByJSONEncoderAreRewrittenToo() throws {
        struct Index: Codable { let backupPath: String }
        let old = "/Users/x/Library/Application Support/StarHubTH"
        let new = "/Users/x/Library/Application Support/StarHubFR"
        let data = try JSONEncoder()
            .encode(Index(backupPath: "\(old)/Backups/ModInstalls/backups/a"))

        // Le producteur échappe bien : sans cela l'épreuve ne prouverait rien.
        #expect(String(decoding: data, as: UTF8.self).contains("\\/"))
        #expect(AppSupportMigration.needsRewrite(data, oldRoot: old))

        let rewritten = try #require(AppSupportMigration.rewrite(data, from: old, to: new))
        // Le résultat reste du JSON décodable, et pointe vers le nouveau dossier.
        let back = try JSONDecoder().decode(Index.self, from: rewritten)
        #expect(back.backupPath == "\(new)/Backups/ModInstalls/backups/a")
    }

    /// Un JSON illisible n'est pas réécrit à l'aveugle : mieux vaut ne rien
    /// faire que produire un fichier corrompu.
    @Test func unreadableDataIsRefused() {
        let bytes = Data([0xFF, 0xFE, 0x00])
        #expect(AppSupportMigration.rewrite(bytes, from: "/a", to: "/b") == nil)
    }

    // MARK: - Le déplacement réel

    private func makeLegacy(_ fm: FileManager) throws -> (root: URL, old: URL, new: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let old = root.appendingPathComponent("StarHubTH")
        let new = root.appendingPathComponent("StarHubFR")
        try fm.createDirectory(at: old.appendingPathComponent("TranslationBackups/ItemBags/a"),
                               withIntermediateDirectories: true)
        try Data("sauvegarde".utf8)
            .write(to: old.appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json"))
        try Data("""
        {"byHost":{},"addonsByHost":{"ItemBags":[{"hostFolderName":"ItemBags",
        "nexusModId":48157,"nexusName":"C","version":"1","installedAt":1,
        "files":["bagconfig.json"],"replacedFiles":{"bagconfig.json":
        "\(old.path)/TranslationBackups/ItemBags/a/bagconfig.json"}}]}}
        """.utf8).write(to: old.appendingPathComponent("installed_translations.json"))
        return (root, old, new)
    }

    /// Le cas nominal : le dossier passe, et le chemin stocké **suit**.
    @Test func theFolderMovesAndTheStoredPathFollows() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(!fm.fileExists(atPath: g.old.path))
        let moved = g.new.appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json")
        #expect(fm.fileExists(atPath: moved.path))
        let text = try String(contentsOf: g.new.appendingPathComponent("installed_translations.json"),
                              encoding: .utf8)
        #expect(text.contains(g.new.path))
        #expect(!text.contains(g.old.path))
    }

    /// **Rien à migrer n'est pas un échec.** Une installation neuve n'a pas
    /// d'ancien dossier ; la migration doit passer sans bruit.
    @Test func nothingToMigrateSucceedsQuietly() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        #expect(AppSupport.migrate(from: root.appendingPathComponent("StarHubTH"),
                                   to: root.appendingPathComponent("StarHubFR"),
                                   fileManager: fm))
    }

    /// **Ce qui est déjà arrivé n'est jamais écrasé** — l'utilisateur a lancé
    /// une version migrée, puis une ancienne qui a réécrit dans l'ancien
    /// dossier. La donnée en place est la plus récente.
    @Test func anythingAlreadyMovedIsNeverOverwritten() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        try fm.createDirectory(at: g.new, withIntermediateDirectories: true)
        try Data("récent".utf8).write(to: g.new.appendingPathComponent("installed_translations.json"))

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(try String(contentsOf: g.new.appendingPathComponent("installed_translations.json"),
                           encoding: .utf8) == "récent")
        // Le reste a bien suivi, lui.
        #expect(fm.fileExists(atPath: g.new
            .appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json").path))
    }

    /// **La migration est reprenable.** Un échec en cours de route ne doit pas
    /// figer un état à moitié migré : un second passage finit le travail.
    @Test func aSecondPassFinishesTheJob() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        // Premier passage partiel simulé : le registre est déjà arrivé.
        try fm.createDirectory(at: g.new, withIntermediateDirectories: true)
        try fm.moveItem(at: g.old.appendingPathComponent("installed_translations.json"),
                        to: g.new.appendingPathComponent("installed_translations.json"))

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(fm.fileExists(atPath: g.new
            .appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json").path))
        #expect(!fm.fileExists(atPath: g.old.path))
    }

    /// **La réécriture d'abord, le déplacement ensuite.** Un dossier déplacé
    /// dont le JSON n'aurait pas été réécrit détruirait des fichiers au premier
    /// retrait de greffe : la migration doit échouer sans avoir rien bougé.
    @Test func aFailedRewriteLeavesTheFolderWhereItWas() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: g.old.path)
            try? fm.removeItem(at: g.root)
        }
        // Registre illisible en écriture : la réécriture ne peut pas aboutir.
        let registry = g.old.appendingPathComponent("installed_translations.json")
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: registry.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: g.old.path)

        #expect(!AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(fm.fileExists(atPath: g.old.path))
        #expect(!fm.fileExists(atPath: g.new.path))
    }

    /// **Le `.bak` compte autant que le principal** (constat de revue).
    /// `InstalledTranslationStore` écrit les deux et **promeut le `.bak`**
    /// quand le principal est corrompu : laissé aux chemins périmés, il ferait
    /// *supprimer* les fichiers d'origine du parc au premier retrait de greffe.
    /// C'est l'assertion dont dépend le chemin destructeur.
    @Test func theRegistryBackupIsRewrittenToo() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        // Le `.bak` que `save` écrit à chaque enregistrement, mêmes octets.
        let registry = g.old.appendingPathComponent("installed_translations.json")
        let backup = g.old.appendingPathComponent("installed_translations.json.bak")
        try fm.copyItem(at: registry, to: backup)

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))

        for name in ["installed_translations.json", "installed_translations.json.bak"] {
            let landed = g.new.appendingPathComponent(name)
            #expect(fm.fileExists(atPath: landed.path))
            let text = try String(contentsOf: landed, encoding: .utf8)
            #expect(text.contains(g.new.path))
            #expect(!text.contains(g.old.path))
        }
    }

    /// La reprise est par fichier, pas par paire : un premier passage
    /// interrompu qui n'a posé que le principal doit finir le `.bak` — et ne
    /// pas réécrire celui qui est déjà arrivé, plus récent par construction.
    @Test func aBackupLeftBehindIsFinishedOnTheNextPass() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        let backup = g.old.appendingPathComponent("installed_translations.json.bak")
        try fm.copyItem(at: g.old.appendingPathComponent("installed_translations.json"),
                        to: backup)
        // Passage partiel : le principal est déjà arrivé, avec son contenu à jour.
        try fm.createDirectory(at: g.new, withIntermediateDirectories: true)
        try Data("déjà à jour".utf8)
            .write(to: g.new.appendingPathComponent("installed_translations.json"))

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))

        // Le principal en place n'a pas été touché…
        #expect(try String(contentsOf: g.new.appendingPathComponent("installed_translations.json"),
                           encoding: .utf8) == "déjà à jour")
        // …et le `.bak` a suivi, réécrit.
        let landedBackup = g.new.appendingPathComponent("installed_translations.json.bak")
        let text = try String(contentsOf: landedBackup, encoding: .utf8)
        #expect(text.contains(g.new.path))
        #expect(!text.contains(g.old.path))
    }

    // MARK: - Réparer une installation déjà migrée

    /// **Le cas du parc de référence.** La réécriture d'origine était aveugle
    /// aux slashes échappés : les installations migrées avant le correctif
    /// portent un registre qui pointe encore vers l'ancien dossier, alors que
    /// les sauvegardes, elles, ont bien suivi. Mesuré le 2026-09-10 : **six
    /// greffes actives** dans cet état, et retirer l'une d'elles aurait
    /// supprimé le fichier de l'utilisateur au lieu de le rendre.
    ///
    /// La réparation ne peut pas passer par `migrate` : l'ancien dossier peut
    /// avoir disparu, et le registre de destination existe déjà — les deux
    /// gardes du déplacement l'écartent.
    @Test func anAlreadyMigratedRegistryIsRepaired() throws {
        struct Entry: Codable { let replacedFiles: [String: String] }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let old = root.appendingPathComponent("StarHubTH")
        let new = root.appendingPathComponent("StarHubFR")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: new, withIntermediateDirectories: true)

        // Écrit par le vrai producteur : slashes échappés.
        let stale = try JSONEncoder().encode(
            Entry(replacedFiles: ["i18n/fr.json": "\(old.path)/TranslationBackups/X/a/fr.json"]))
        let registry = new.appendingPathComponent("installed_translations.json")
        try stale.write(to: registry)
        try stale.write(to: new.appendingPathComponent("installed_translations.json.bak"))

        // Aucun ancien dossier : la réparation ne dépend pas de sa présence.
        #expect(!fm.fileExists(atPath: old.path))
        #expect(AppSupport.repairStalePaths(in: new, legacyRoot: old, fileManager: fm) == 2)

        let back = try JSONDecoder().decode(Entry.self, from: try Data(contentsOf: registry))
        #expect(back.replacedFiles["i18n/fr.json"]
                == "\(new.path)/TranslationBackups/X/a/fr.json")

        // Idempotente : un second passage n'a plus rien à faire.
        #expect(AppSupport.repairStalePaths(in: new, legacyRoot: old, fileManager: fm) == 0)
    }

    // MARK: - X105 : `Backups/` suit, avec son index (2026-09-10)

    /// **1,2 Go de points de restauration, et 220 chemins absolus qui doivent
    /// suivre.** L'index vit dans un sous-dossier (`Backups/ModInstalls/`) :
    /// l'épreuve porte autant sur le fait qu'il soit *trouvé* là que sur le
    /// déplacement lui-même — un index nommé mais jamais atteint se réécrirait
    /// silencieusement à zéro, et la sauvegarde deviendrait introuvable au
    /// premier restaurer.
    @Test func backupsMoveWithTheirIndexRewritten() throws {
        struct Entry: Codable { let backupPath: String }
        struct Index: Codable { let backups: [Entry] }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let old = root.appendingPathComponent("StarHubTH")
        let new = root.appendingPathComponent("StarHubFR")
        defer { try? fm.removeItem(at: root) }

        // Une sauvegarde réelle : le dossier archivé, et l'index qui le désigne
        // par chemin **absolu**, écrit par le vrai producteur (slashes échappés).
        let archived = old.appendingPathComponent("Backups/ModInstalls/backups/2026_X/[CP] Mod")
        try fm.createDirectory(at: archived, withIntermediateDirectories: true)
        try Data("mod".utf8).write(to: archived.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(Index(backups: [Entry(backupPath: archived.path)]))
            .write(to: old.appendingPathComponent("Backups/ModInstalls/install_metadata.json"))

        #expect(AppSupport.migrate(from: old, to: new, fileManager: fm))

        // L'ancien dossier s'en va **entièrement** : plus rien ne reste derrière.
        #expect(!fm.fileExists(atPath: old.path))
        // L'archive a suivi…
        let landed = new.appendingPathComponent("Backups/ModInstalls/backups/2026_X/[CP] Mod/manifest.json")
        #expect(fm.fileExists(atPath: landed.path))
        // …et l'index la désigne là où elle est vraiment.
        let index = try JSONDecoder().decode(
            Index.self,
            from: try Data(contentsOf: new.appendingPathComponent("Backups/ModInstalls/install_metadata.json")))
        let target = try #require(index.backups.first).backupPath
        #expect(target.hasPrefix(new.path))
        #expect(fm.fileExists(atPath: target))
    }

    /// Un index **sans** chemin absolu — le cas de `ModConfigs/metadata.json`,
    /// 6 sauvegardes et aucun chemin sur le parc — traverse intact.
    @Test func anIndexWithoutPathsIsNotDisturbed() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let old = root.appendingPathComponent("StarHubTH")
        let new = root.appendingPathComponent("StarHubFR")
        defer { try? fm.removeItem(at: root) }
        let dir = old.appendingPathComponent("Backups/ModConfigs")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let untouched = Data(#"{"backups":[{"folderName":"X","items":[]}]}"#.utf8)
        try untouched.write(to: dir.appendingPathComponent("metadata.json"))

        #expect(AppSupport.migrate(from: old, to: new, fileManager: fm))
        #expect(try Data(contentsOf: new.appendingPathComponent("Backups/ModConfigs/metadata.json"))
                == untouched)
    }

    /// **Le garde qui manquait.** `AppSupport.directory` est un `static let` à
    /// effet de bord : le lire migre. Cette suite en a fait la démonstration le
    /// 2026-09-10 en déplaçant 1,2 Go de sauvegardes réelles, simplement parce
    /// qu'un test construisait `ModInstallBackupManager.shared`.
    ///
    /// L'épreuve porte sur le mécanisme lui-même : si elle échoue un jour,
    /// c'est que la suite s'est remise à pouvoir toucher les données de
    /// l'utilisateur.
    @Test func theTestProcessNeverTriggersARealMigration() {
        #expect(!AppSupport.isHostedByTheApp)
        // Le chemin reste rendu — seuls les effets de bord sont retenus.
        #expect(AppSupport.directory?.lastPathComponent == "StarHubFR")
    }
}
