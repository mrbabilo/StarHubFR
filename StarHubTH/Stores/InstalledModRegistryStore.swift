import Foundation

/// Le registre des mods installés : quelle version de chaque dossier a été vue
/// sur disque, et **quand** on l'y a constatée.
///
/// Ce que la date du dossier ne dit pas — `copyItem` conserve la date
/// d'empaquetage de l'archive — ce registre le dit : l'instant réel de
/// l'installation sur cette machine. Le vérificateur de mises à jour s'en sert
/// pour la détection à version égale : une mise en ligne Nexus postérieure à la
/// date du registre signale une copie périmée.
///
/// Extrait du ViewModel le 2026-09-10 (point 1 du §5 de `docs/REFACTORING.md`).
/// La règle de rapprochement vivait déjà en Core (`InstalledModRegistry.sync`,
/// testée) ; c'est la **persistance** qui restait au ViewModel, avec ses trois
/// mécanismes de sûreté que rien ne vérifiait — clé de secours doublant chaque
/// écriture, restauration sur corruption, reconstruction depuis le disque.
///
/// ⚠️ **Le secours n'est pas une copie « avant écriture ».** `persist` écrit les
/// **mêmes octets neufs** sur les deux clés dans la foulée : le secours ne porte
/// donc jamais la génération précédente, et ne permet aucun retour en arrière.
/// Ce qu'il couvre est plus étroit — une clé devenue illisible pendant que
/// l'autre reste lisible. Mesuré sur une installation réelle le 2026-09-10 :
/// `installedModRegistry` et `installedModRegistryBackup` font tous deux
/// exactement 90 902 octets.
///
/// `UserDefaults` entre par l'initialiseur, comme dans `ModVersionAnchorStore`
/// et `ModUpdateSnoozer` : c'est ce qui permet aux tests d'écrire dans un
/// domaine jetable au lieu des préférences réelles de l'utilisateur.
///
/// **L'initialiseur ne lit rien**, et le chargement reste paresseux. Au
/// lancement, `ModVersionAnchorStore.migrateAwayFromNexusVersion()` réécrit le
/// JSON brut du registre avant que le cache ne soit chauffé — mais un cache pris
/// trop tôt ne perdrait rien : `InstalledModRecord` ne porte plus `nexusVersion`,
/// donc les deux JSON se décodent en cartes **identiques champ pour champ**.
/// L'ordre qui compte vraiment est plus étroit : la migration doit passer **avant**
/// que la liste de grâce ne soit posée puis consommée, sous peine de ré-estampiller
/// des dates d'installation qu'aucune autre source ne reconstitue. C'est ce que
/// l'ordre des trois appels au lancement garantit déjà.
final class InstalledModRegistryStore {

    /// Ce que la synchronisation a constaté, rendu à l'appelant plutôt que
    /// journalisé ici : le store ne connaît ni le journal de l'app ni sa
    /// localisation. C'est le patron « ce qui n'est pas à moi arrive (ou
    /// repart) en paramètre » (§3 de `docs/REFACTORING.md`).
    struct SyncReport: Equatable {
        /// Nombre d'entrées reconstruites depuis le disque après la purge de
        /// migration. Zéro quand la migration avait déjà eu lieu.
        let rebuiltFromDisk: Int
        /// Nombre de dossiers dont la date d'installation a été préservée
        /// malgré un changement de version — celui-ci venant d'un changement
        /// de lecture, pas du disque.
        let gracePreserved: Int
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cache: [String: InstalledModRecord]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Lecture

    /// Le registre, chargé une seule fois par session puis mémoïsé.
    ///
    /// Le chemin froid décode depuis `UserDefaults` avec la chaîne de secours ;
    /// les appels suivants lisent le cache (ni décodage JSON, ni I/O), rafraîchi
    /// par toute écriture. Sûr entre fils via `lock`.
    func all() -> [String: InstalledModRecord] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded = loadFromDisk()
        cache = loaded
        return loaded
    }

    /// La date d'installation enregistrée pour un dossier, ou `nil` si le mod
    /// n'a jamais été enregistré (installé avant que cette fonctionnalité
    /// n'existe, par exemple).
    func installedDate(for folderName: String) -> Date? {
        all()[folderName]?.installedAt
    }

    /// Chauffe le cache. Appelé une fois au lancement pour que le seul décodage
    /// JSON de la session soit explicite et compté dans le coût de démarrage,
    /// plutôt que d'arriver par surprise au premier accès.
    func warmCache() {
        _ = all()
    }

    // MARK: - Écriture

    /// Lecture–modification–écriture atomique.
    ///
    /// C'est le **seul** chemin d'écriture. Un `replaceAll` a existé à côté,
    /// sans jamais trouver d'appelant de production : remplacer tout le registre
    /// se dit `mutate { $0 = … }`, et une seconde porte n'aurait servi qu'à
    /// diverger de celle-ci.
    ///
    /// La séquence « lire le cache → muter → réécrire le cache » se fait sous un
    /// seul verrou, pour qu'un second scan concurrent ne puisse pas charger la
    /// même version, muter, et écraser nos changements (audit 2026-08-05 : faux
    /// « mise à jour disponible » perpétuel quand l'entrée `nexusVersion` était
    /// perdue dans la course).
    ///
    /// **La persistance est dedans, et doit y rester.** Elle a longtemps suivi
    /// le `unlock`, au motif que `UserDefaults.set` serait lent — motif jamais
    /// mesuré. Il l'est depuis le 2026-09-10 : sur un registre de la taille du
    /// parc de référence (961 entrées, 95 Ko), encoder puis écrire les deux clés
    /// coûte **3,4 ms en médiane, 6,8 ms au pire**, dont 2,6 ms d'encodage.
    /// C'est une poignée d'appels par scan, pas un chemin de rendu.
    ///
    /// Ce que l'ancienne forme coûtait, elle, était une incohérence : deux
    /// `mutate` concurrents pouvaient muter dans un ordre et persister dans
    /// l'autre — le cache tenant le dernier état, `UserDefaults` l'avant-dernier.
    /// Le registre survivant au lancement suivant n'était alors plus celui que
    /// la session avait constaté, et les dossiers perdus repassaient pour
    /// « installés aujourd'hui ». Le verrou rend l'écriture aussi ordonnée que
    /// la mutation, sans mécanisme neuf ni état à vérifier.
    ///
    /// Le corps rend une valeur, qui ressort d'ici : c'est ce qui a supprimé la
    /// boîte à un élément dont le ViewModel se servait pour faire échapper un
    /// booléen d'une closure `inout` (déviation consignée au §6).
    ///
    /// ⚠️ **Le corps s'exécute sous le verrou, et `NSLock` n'est pas récursif :
    /// il ne doit appeler aucune autre méthode de ce store** — `all()`,
    /// `installedDate(for:)` et `mutate` lui-même bloqueraient sans plantage ni
    /// journal. Ce qu'il lui faut du registre, il le reçoit en `inout`.
    @discardableResult
    func mutate<T>(_ body: (inout [String: InstalledModRecord]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        var map = cache ?? loadFromDisk()
        let result = body(&map)
        cache = map
        persist(map)
        return result
    }

    /// La même lecture-modification-écriture, mais le corps **dit** s'il a
    /// bougé : sur `false`, rien n'est mis en cache ni persisté. Le code que
    /// cette variante remplace ne sauvait que quand `ModFolderRename.migrate`
    /// rendait `true` — le `mutate` inconditionnel réécrivait ~91 Ko sur les
    /// deux clés pour chaque renommage sans entrée de registre (revue du
    /// 2026-09-10).
    func mutateIfChanged(_ body: (inout [String: InstalledModRecord]) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var map = cache ?? loadFromDisk()
        guard body(&map) else { return false }
        cache = map
        persist(map)
        return true
    }

    // MARK: - Dossiers en grâce

    /// Les dossiers dont un changement de version ne doit **pas** ré-estampiller
    /// la date d'installation : leur version change parce que la *lecture* a
    /// changé (la migration a retiré `nexusVersion` du registre), pas le disque.
    ///
    /// Posés une fois par la migration, consommés puis effacés par la
    /// synchronisation suivante. Un dossier absent de cette passe est de toute
    /// façon purgé du registre : une passe suffit.
    func installDateGrace() -> Set<String> {
        Set(defaults.stringArray(forKey: UDKey.installDateGrace) ?? [])
    }

    func setInstallDateGrace(_ folders: [String]) {
        defaults.set(folders, forKey: UDKey.installDateGrace)
    }

    // MARK: - Synchronisation avec le disque

    /// Rapproche le registre de ce qu'un scan a vu, et déplace les ancres de
    /// version que des installations hors de l'app ont rendues fausses.
    ///
    /// Appelée à la fin de chaque `scanMods()`, de sorte qu'un mod arrivé par
    /// **n'importe quel** moyen — installateur de l'app, glisser-déposer, copie
    /// manuelle dans `Mods/` — soit suivi.
    ///
    /// - Parameter scannedMods: ce que le scan a vu ; les packs sont dépliés ici.
    /// - Parameter modsFolderWasReadable: faux quand le scan n'a **pas pu lire**
    ///   `Mods/`. Les deux purges de cette passe — le registre lui-même et les
    ///   ancres de version — sont alors suspendues : elles répondent à « ce
    ///   dossier a disparu », question à laquelle un lot qu'on n'a pas pu lire
    ///   ne répond pas. L'enregistrement, lui, continue.
    /// - Parameter anchorStore: le magasin des affirmations. Il arrive en
    ///   paramètre parce qu'il ne nous appartient pas.
    /// - Parameter suggestedVersions: la version que smapi.io suggère, par
    ///   `UniqueID` — la cible que le manifest doit rejoindre pour qu'on tienne
    ///   l'installation pour accomplie. Sans suggestion connue, la règle compare
    ///   à la version du manifest, donc l'atteint d'office.
    /// - Parameter now: l'instant de la passe, pour tout le lot. Injecté : les
    ///   trois quarts des règles portent sur l'horodatage, et une horloge
    ///   paramétrable est ce qui les rend vérifiables.
    /// - Returns: ce qu'il y a à dire à l'utilisateur, à charge pour l'appelant
    ///   de le journaliser.
    func sync(scannedMods: [ModItem],
              modsFolderWasReadable: Bool,
              anchorStore: ModVersionAnchorStore,
              suggestedVersions: [String: String],
              now: Date = Date()) -> SyncReport {
        // Déplier les packs pour que leurs composants soient suivis aussi.
        let allMods = scannedMods.flattenedMods

        // Migration unique : effacer tout registre antérieur, bâti sur des dates
        // de dossier non fiables.
        //
        // Le drapeau est posé **après** `mutate`, donc après que le registre
        // purgé a été écrit. Il a longtemps été posé dans le corps, avec un
        // commentaire affirmant l'inverse de ce qui se passait : le corps
        // s'exécute avant `persist`, si bien que le drapeau atteignait le disque
        // le premier. Un plantage entre les deux laissait alors `true` sur un
        // registre non purgé — et la migration ne rejouait plus jamais. Dans cet
        // ordre-ci, le même plantage laisse le drapeau à `false` et la purge
        // rejoue au scan suivant, ce qui ne coûte que des dates réestampillées.
        let migrationDone = defaults.bool(forKey: UDKey.registryMigrationV2Done)

        let seen = allMods.map {
            InstalledModRegistry.Seen(folder: $0.folderName, version: $0.version)
        }
        let graceFolders = installDateGrace()

        // La version que le registre portait AVANT cette passe. C'est le seul
        // endroit où l'app voit l'ancienne et la nouvelle version d'un dossier
        // côte à côte, donc le seul d'où l'on puisse constater qu'une
        // installation a eu lieu hors de l'app. À lire avant la mutation.
        let previousVersions = all().mapValues(\.version)

        let rebuiltFromDisk = mutate { registry -> Int in
            if !migrationDone { registry = [:] }
            let (synced, _) = InstalledModRegistry.sync(registry: registry,
                                                        seen: seen,
                                                        now: now,
                                                        installDateGrace: graceFolders,
                                                        pruneMissing: modsFolderWasReadable)
            registry = synced
            return migrationDone ? 0 : registry.count
        }
        if !migrationDone {
            defaults.set(true, forKey: UDKey.registryMigrationV2Done)
        }

        anchorModsUpdatedOnDisk(allMods,
                                previousVersions: previousVersions,
                                excluding: graceFolders,
                                anchorStore: anchorStore,
                                suggestedVersions: suggestedVersions,
                                now: now)

        if !graceFolders.isEmpty {
            defaults.removeObject(forKey: UDKey.installDateGrace)
        }

        // Un mod supprimé ne doit pas laisser son affirmation derrière lui :
        // réinstallé plus tard, il hériterait d'une version qu'il n'a pas.
        // Même réserve que pour le registre : un `Mods/` illisible n'atteste
        // aucune suppression, et purger là-dessus retire les 251 ancres du parc.
        if modsFolderWasReadable {
            anchorStore.pruneAnchors(keeping: Set(allMods.map(\.uniqueId).filter { !$0.isEmpty }))
        }

        return SyncReport(rebuiltFromDisk: rebuiltFromDisk,
                          gracePreserved: graceFolders.count)
    }

    /// Constate sur disque les mises à jour que l'app n'a pas menées, et déplace
    /// l'ancre en conséquence.
    ///
    /// Sans cet appel, `ModVersionAnchorRules.afterDiskChange` n'avait aucun
    /// appelant et l'origine `.diskObserved` ne se produisait jamais : un mod
    /// ancré à la version X, puis mis à jour à la main (glisser-déposer, copie),
    /// continuait d'annoncer X comme version installée. smapi.io répondait
    /// « mise à jour disponible » indéfiniment — le défaut d'origine en miroir,
    /// une fausse mise à jour affirmée au lieu d'une vraie effacée.
    ///
    /// - Parameter excluding: les dossiers en grâce. Leur version « change »
    ///   parce que la lecture a changé, pas le disque : les ancrer ici
    ///   affirmerait une installation qui n'a pas eu lieu.
    func anchorModsUpdatedOnDisk(_ allMods: [ModItem],
                                 previousVersions: [String: String],
                                 excluding graceFolders: Set<String>,
                                 anchorStore: ModVersionAnchorStore,
                                 suggestedVersions: [String: String],
                                 now: Date) {
        for mod in allMods where !mod.uniqueId.isEmpty && !graceFolders.contains(mod.folderName) {
            guard let previous = previousVersions[mod.folderName] else { continue }
            guard let anchor = ModVersionAnchorRules.afterDiskChange(
                existing: anchorStore.anchor(for: mod.uniqueId),
                uniqueId: mod.uniqueId,
                previousManifestVersion: previous,
                currentManifestVersion: mod.version,
                suggestedVersion: suggestedVersions[mod.uniqueId] ?? mod.version,
                now: now) else { continue }
            anchorStore.put(anchor)
        }
    }

    // MARK: - Persistance

    /// Charge depuis `UserDefaults`, avec repli automatique :
    ///
    /// 1. **Clé principale** — la décoder. Si elle est valide, la rendre.
    /// 2. **Clé de secours** — si la principale est absente ou corrompue,
    ///    essayer le secours. En cas de succès, le promouvoir en principale et
    ///    signaler la récupération.
    /// 3. **Ni l'une ni l'autre** — rendre `[:]`. Le registre sera entièrement
    ///    reconstruit depuis le disque par `sync` au prochain scan.
    ///
    /// Les blobs corrompus (principal comme secours) sont purgés pour qu'ils ne
    /// bloquent pas les écritures suivantes.
    ///
    /// Appelée sous verrou par `all()` et `mutate`, mais ne le prend pas
    /// elle-même : elle ne touche qu'à `defaults`, jamais au cache.
    private func loadFromDisk() -> [String: InstalledModRecord] {
        // 1. La principale.
        if let primary = defaults.data(forKey: UDKey.installedModRegistry),
           let decoded = try? JSONDecoder().decode([String: InstalledModRecord].self, from: primary) {
            return decoded
        }

        // Principale absente ou corrompue — la purger.
        if defaults.data(forKey: UDKey.installedModRegistry) != nil {
            defaults.removeObject(forKey: UDKey.installedModRegistry)
        }

        // 2. Le secours.
        if let backup = defaults.data(forKey: UDKey.installedModRegistryBackup),
           let decoded = try? JSONDecoder().decode([String: InstalledModRecord].self, from: backup) {
            // Le promouvoir en principale : les chargements suivants sont
            // rapides, et la principale corrompue est remplacée.
            if let data = try? JSONEncoder().encode(decoded) {
                defaults.set(data, forKey: UDKey.installedModRegistry)
            }
            NSLog("[StarHubFR] Install registry restored from backup (%d entries).",
                  decoded.count)
            return decoded
        }

        // Secours absent ou corrompu lui aussi — le purger également.
        if defaults.data(forKey: UDKey.installedModRegistryBackup) != nil {
            defaults.removeObject(forKey: UDKey.installedModRegistryBackup)
            NSLog("[StarHubFR] Install registry and backup both corrupt/unavailable — rebuilding from disk.")
        }

        // 3. Aucune des deux n'est utilisable — vide ; reconstruit au prochain scan.
        return [:]
    }

    /// Écrit le **même** blob sur la clé principale et sur celle de secours.
    ///
    /// Ce que cela couvre, exactement : une clé rendue illisible alors que
    /// l'autre reste lisible — `loadFromDisk` bascule alors sur la seconde. Ce
    /// que cela ne couvre **pas** : revenir à l'état d'avant, puisque les deux
    /// clés reçoivent la même génération neuve ; ni une donnée fausse mais bien
    /// formée, qui sera fidèlement doublée.
    ///
    /// Appelée **sous le verrou** par `mutate` — voir son commentaire pour la
    /// mesure qui a réglé la question.
    private func persist(_ map: [String: InstalledModRecord]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: UDKey.installedModRegistry)
        defaults.set(data, forKey: UDKey.installedModRegistryBackup)
    }
}
