import Foundation

/// L'avancement du balayage de `Mods/`, publié par le ViewModel à l'écran de
/// lancement. Anciennement imbriqué dans le ViewModel : le type vit avec le
/// scanner qui le produit (REFACTORING §6, domaine Scan, tranche 1).
///
/// `phase` — non nil quand la boucle par mod est **finie** et qu'une phase
/// nommée tourne encore (journal SMAPI, registre, doublons). Le compteur
/// reste alors affiché — à `total/total`, ce qu'il n'atteignait jamais —
/// mais la barre suit `launchProgress` au lieu du ratio, sans quoi elle
/// resterait immobile pendant toute la phase.
struct ScanProgress: Equatable {
    let done: Int
    let total: Int
    let currentName: String
    var phase: String? = nil
}

/// Le balayage de `Mods/` — énumération haut niveau, lecture des manifestes
/// et groupement des packs (REFACTORING §6, domaine Scan, tranche 1 : la
/// logique pure, pas l'orchestration).
///
/// Ce qui **n'est pas** ici et reste à l'appelant : la réparation préalable
/// (`ModFolderRepairer`, déjà en Core), le journal SMAPI, la synchronisation
/// du registre d'install, la détection des doublons et la publication de la
/// liste — tout ce qui touche d'autres domaines ou l'état publié.
///
/// « Ce qui n'est pas à moi arrive en paramètre » (§3) : la date d'install
/// (`installedModDate`, adossée au registre), le libellé « Préparation… »
/// déjà localisé, la destination des progrès (`onProgress` — l'appelant
/// repasse sur le fil principal) et du journal (`log`, pré-lié au niveau
/// warning) arrivent par l'appel.
///
/// Threading — contrat hérité du ViewModel : `scan()` est appelé depuis les
/// files de fond de `refresh()`/`performInitialLoad`/application de profil,
/// et **deux balayages peuvent tourner en concurrence**. Le cache de
/// manifestes est l'état de l'instance, verrouillé — c'est exactement la
/// course qui a produit un `EXC_BAD_ACCESS` en juillet 2026 sur le
/// subscript d'un dictionnaire sans verrou. La classe (et non une struct)
/// est ce qui rend le partage d'instance sûr : une copie vaudrait deux
/// caches, et le verrou ne les unirait pas.
final class ModScanner {

    struct Outcome {
        /// Les mods balayés, **dans l'ordre de balayage** — le tri alphabétique
        /// (`alphabeticalListOrder`) reste la décision de la publication.
        let mods: [ModItem]
        /// « Rien vu » n'est pas « rien installé » (X71) : faux quand `Mods/`
        /// est introuvable ou illisible. Les purges de fin de passe (registre,
        /// ancres) se suspendent sur cette valeur.
        let modsFolderWasReadable: Bool
        /// Le compte complet d'entrées, pour les phases qui suivent la boucle
        /// (`topEntries` n'existe plus là-bas).
        let scannedEntries: (done: Int, total: Int)
    }

    /// Cache de décodage indexé par mtime : évite de relire et re-parser
    /// chaque `manifest.json` à un rescan qui ne suit qu'une bascule (qui ne
    /// déplace qu'un dossier). Un rescan à rien devient ~N `stat()` et zéro
    /// décodage JSON. Vit à travers les scans sur l'instance.
    private var manifestCache: [String: (mtime: Date, manifest: [String: Any])] = [:]
    private let manifestCacheLock = NSLock()

    func scan(gameDir: String,
              installedModDate: (String) -> Date?,
              onProgress: (ScanProgress) -> Void,
              log: (String) -> Void) -> Outcome {
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        // Permanent safety net: if a legacy `Mods_disabled/` folder still
        // exists (recréé par un autre outil, ou un retardataire qui passe
        // d'une version pré-migration directement à la version actuelle),
        // the mods it holds are now invisible to the app and would otherwise
        // silently vanish from the list. Surface a single warning so the
        // user knows to reinstall them via drag-and-drop. Survives the N+1
        // removal of the one-shot migration method (plan step 17).
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        if fm.fileExists(atPath: disabledModsPath) {
            // Source unique OSJunk.isJunk (files + folders + AppleDouble). La liste
            // inline précédente omettait Icon\r, .Spotlight-V100 et .Trashes → un
            // Mods_disabled/ ne contenant que ces résidus déclenchait un faux
            // warning « still contains mods » (divergence de copie).
            let hasNonJunk = (try? fm.contentsOfDirectory(atPath: disabledModsPath))?
                .contains { entry in !OSJunk.isJunk(entry) } ?? false
            if hasNonJunk {
                log("Mods_disabled/ still contains mods — they are now invisible to StarHubTH. Reinstall them via drag-and-drop to make them appear under Mods/.")
            }
        }

        var scannedMods: [ModItem] = []

        // Manifest decode cache hit-test helper. Returns the cached JSON when
        // the on-disk mtime matches the cached entry's mtime, nil otherwise
        // (cache miss, file changed, or unreadable). The actual decode + cache
        // fill happens inline in parseModFolder below. Reads the cache under
        // `manifestCacheLock` because two concurrent `scanMods()` runs (refresh
        // + initial load, or a profile activation racing a manual refresh)
        // would otherwise race on the dictionary's storage.
        func cachedManifest(at manifestPath: String) -> [String: Any]? {
            guard let attrs = try? fm.attributesOfItem(atPath: manifestPath),
                  let mtime = attrs[.modificationDate] as? Date else {
                return nil
            }
            manifestCacheLock.lock()
            let cached = manifestCache[manifestPath]
            manifestCacheLock.unlock()
            guard let cached, cached.mtime == mtime else {
                return nil
            }
            return cached.manifest
        }

        // Helper to parse a folder containing manifest.json
        func parseModFolder(at path: String, relativePath: String, isEnabled: Bool) -> ModItem? {
            let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestPath) else { return nil }

            // Logical on-disk leaf name, with the disabled dot-prefix stripped.
            // For a top-level disabled mod the physical folder is `Mods/.X`, so
            // `lastPathComponent` yields `.X`. `folderName` is the logical key
            // (registry, profiles, activation timestamps, backups) and must
            // NEVER carry the dot — otherwise `physicalFolderName` (= "." +
            // folderName) would compute `..X`, and every on-disk access
            // (toggle, open-in-Finder, config editor) would miss the folder.
            // This is exactly the bug that left disabled mods un-toggleable and
            // un-openable. `relativePath` is already computed against the
            // physical root, so nested/pack mods never carry the prefix and
            // need no stripping.
            let physicalLeaf = (path as NSString).lastPathComponent
            let logicalLeaf = physicalLeaf.hasPrefix(".") ? String(physicalLeaf.dropFirst()) : physicalLeaf

            // Resolve the folder name used as the registry key — mirrors the
            // logic that sets `folderName` on the ModItem below.
            let resolvedFolderName = relativePath.isEmpty
                ? logicalLeaf
                : relativePath

            // Install date: prefer the persistent registry (records the actual
            // installation timestamp on this machine), which is far more
            // reliable than the on-disk folder mtime — `copyItem` preserves the
            // archive's packaging date, and backup/restore operations can shift
            // it too. Fall back to the folder mtime only for mods installed
            // before the registry existed.
            let installedFileDate: Date? = installedModDate(resolvedFolderName)
                ?? {
                    if let attrs = try? fm.attributesOfItem(atPath: path) {
                        return attrs[.modificationDate] as? Date
                    }
                    return nil
                }()
            let hasConfigFile = fm.fileExists(atPath: (path as NSString).appendingPathComponent("config.json"))
            // Les langues que le mod livre, pour la fiche et le filtre FR.
            //
            // Ne lisait que `<mod>/i18n`, par nom de fichier. Deux angles morts,
            // mesurés sur le parc : un content pack range son `i18n` sous
            // `[CP] Nom/` (121 dossiers sur 550 sont à deux niveaux, un à
            // quatre), et une locale peut être un **sous-dossier** dont les
            // fichiers portent d'autres noms (`i18n/fr/gui.json`). Résultat :
            // 90 mods mal détectés, dont **81 dont le français était
            // invisible**. La règle vit désormais en Core avec ses tests.
            let languages = I18nLocaleResolver.languageCodes(
                inModDirectory: URL(fileURLWithPath: path))

            // `name` is overridden from the manifest below when a `Name` field
            // exists, but fall back to the logical (dot-stripped) leaf so a
            // disabled mod missing a `Name` field displays as `X`, not `.X`.
            var name = logicalLeaf
            var uniqueId = ""
            var version = "Unknown"
            var author = "Unknown"
            var description = ""
            var nexusUrl = ""
            var nexusModId = ""
            var updateKeys: [String] = []
            var dependencies: [ModDependency] = []

            // Les deux branches ci-dessous — manifeste venu du cache chaud,
            // manifeste relu sur le disque — lisaient les mêmes huit champs,
            // chacune de son côté. Elles ont déjà divergé sur `Version` : un
            // même mod rendait deux chaînes différentes selon la branche
            // empruntée. La lecture vit désormais dans `ManifestFields` (Core,
            // testé) ; ce qui reste ici est le **repli**, qui lui est propre —
            // un champ absent laisse la valeur par défaut posée juste au-dessus,
            // dont le nom du dossier logique quand le manifeste ne se nomme pas.
            func apply(_ fields: ManifestFields) {
                if let read = fields.name { name = read }
                if let read = fields.uniqueId { uniqueId = read }
                if let read = fields.version { version = read }
                if let read = fields.author { author = read }
                if let read = fields.description { description = read }
                dependencies = fields.dependencies
                updateKeys = fields.updateKeys
                if let nexus = fields.nexus {
                    nexusModId = nexus.id
                    nexusUrl = nexus.url
                }
            }

            // mtime-keyed decode cache: avoids re-reading and re-parsing every
            // manifest.json on a rescan that follows a toggle (which moved only
            // one folder). The cache lives across scans on the scanner, so a
            // no-op rescan becomes ~N stat() calls and zero JSON decodes.
            if let cached = cachedManifest(at: manifestPath) {
                apply(ManifestFields(manifest: cached))
            } else if let rawData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                      let rawString = String(data: rawData, encoding: .utf8) {
                do {
                    // `decodeInstalled` : la tolérance JSON5 pleine, parce que
                    // le scan lit un mod que SMAPI a déjà chargé — il n'a rien
                    // à juger. L'expression régulière qui retirait ici les
                    // commentaires bloc est partie avec : JSON5 les gère, et
                    // elle amputait une valeur de chaîne en contenant.
                    let json = try ManifestJSON.decodeInstalled(rawString)
                    apply(ManifestFields(manifest: json))

                    // Fill the cache so the next scan of an unchanged manifest
                    // is a cheap mtime compare + dict reuse. Storing the raw
                    // decoded JSON (not a narrowed subset) keeps the cache usable
                    // for any future field added to the scan without rework.
                    // Write under the lock — concurrent scans would otherwise race
                    // on the dictionary subscript setter (EXC_BAD_ACCESS).
                    if let mtime = (try? fm.attributesOfItem(atPath: manifestPath))?[.modificationDate] as? Date {
                        manifestCacheLock.lock()
                        manifestCache[manifestPath] = (mtime: mtime, manifest: json)
                        manifestCacheLock.unlock()
                    }
                } catch {
                    // Manifest mal formé : on garde les valeurs par défaut
                    // (nom = dossier logique) mais on le signale pour que
                    // l'utilisateur comprenne pourquoi les métadonnées
                    // sont vides plutôt que de voir un mod "Unknown".
                    log("Manifest invalide pour \(relativePath.isEmpty ? logicalLeaf : relativePath): \(error.localizedDescription)")
                }
            }

            return ModItem(
                uniqueId: uniqueId,
                name: name,
                folderName: relativePath.isEmpty ? logicalLeaf : relativePath,
                version: version,
                author: author,
                description: description,
                nexusUrl: nexusUrl,
                nexusModId: nexusModId,
                updateKeys: updateKeys,
                isEnabled: isEnabled,
                dependencies: dependencies,
                installedFileDate: installedFileDate,
                hasConfigFile: hasConfigFile,
                languages: languages
            )
        }

        // Scan a single top-level entry (physicalRoot) for manifest.json files
        // and group them. `physicalRoot` is the on-disk folder name — which
        // for a disabled mod starts with `.` (e.g. `Mods/.CJBCheats`). The
        // `relativePath` passed to parseModFolder is computed relative to
        // `physicalRoot` so the dot prefix never leaks into `folderName`
        // (the registry/profile key) or into the pack grouping key.
        func scanEntryForMods(at physicalRoot: String, topLevelLogicalFolder: String, isEnabled: Bool) {
            let url = URL(fileURLWithPath: physicalRoot)
            var foundMods: [ModItem] = []

            // Sub-scan with `.skipsHiddenFiles` so nested junk (.DS_Store,
            // .git/, ._Foo) stays hidden — the dot-prefix classification of
            // *top-level* entries is handled by the caller, not here.
            // includingPropertiesForKeys: [] — we only filter by filename
            // ("manifest.json"), so prefetching isDirectory per file is pure
            // overhead on a tree with tens of thousands of files.
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == "manifest.json" {
                        let modFolderURL = fileURL.deletingLastPathComponent()
                        // Chemin relatif canonique : on résout les symlinks des
                        // deux côtés (l'énumérateur macOS rapporte /private/var/…
                        // même si la racine était /var/…) puis on ne retire le
                        // préfixe racine qu'une fois. Un replacingOccurrences(of:
                        // url.path) l'amputait à nouveau si la racine réapparaissait
                        // plus loin dans le sous-chemin — jumeau du bug M6 dans
                        // ModFolderRepairer.collectUniqueIds.
                        let resolvedMod = modFolderURL.resolvingSymlinksInPath().path
                        let resolvedRoot = url.resolvingSymlinksInPath().path
                        let rootStd = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
                        let relFromTop = (resolvedMod.hasPrefix(rootStd)
                            ? String(resolvedMod.dropFirst(rootStd.count))
                            : "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let fullRelPath = relFromTop.isEmpty ? topLevelLogicalFolder : "\(topLevelLogicalFolder)/\(relFromTop)"
                        if let mod = parseModFolder(at: modFolderURL.path, relativePath: fullRelPath, isEnabled: isEnabled) {
                            foundMods.append(mod)
                        }
                    }
                }
            }

            if foundMods.isEmpty {
                return
            } else if foundMods.count == 1 && foundMods[0].folderName == topLevelLogicalFolder {
                scannedMods.append(foundMods[0])
            } else {
                let groupMod = ModItem(
                    uniqueId: "",
                    name: topLevelLogicalFolder,
                    folderName: topLevelLogicalFolder,
                    version: "",
                    author: "Group",
                    description: "\(foundMods.count) mods",
                    nexusUrl: "",
                    nexusModId: "",
                    isEnabled: isEnabled,
                    dependencies: [],
                    children: foundMods,
                    isGroup: true,
                    languages: Set(foundMods.flatMap { $0.languages }).sorted()
                )
                scannedMods.append(groupMod)
            }
        }

        // Top-level enumeration of Mods/ WITHOUT `.skipsHiddenFiles` so the
        // dot-prefixed disabled entries (`.X`) are visible. Each entry is
        // classified exactly the same way `ModFolderRepairer.repairFolder`
        // classifies top-level entries, so the scanner and the repairer agree
        // on what counts as OS junk vs. a disabled mod.
        var modsFolderWasReadable = false
        var scannedEntries = (done: 0, total: 0)
        if fm.fileExists(atPath: modsPath),
           let topEntries = try? fm.contentsOfDirectory(atPath: modsPath) {
            modsFolderWasReadable = true
            let scanTotal = topEntries.count
            var scanDone = 0
            var lastProgressPublish: CFAbsoluteTime = 0
            for entry in topEntries {
                scanDone += 1
                if OSJunk.isJunk(entry) { continue }
                // Skip trash folders created by a prior repair run — the mods
                // quarantined inside are not active and must not appear in the
                // list nor in duplicate detection.
                if entry.hasPrefix(ModFolderRepairer.trashPrefix) { continue }

                // Dot prefix = disabled mod; strip it for the logical name.
                // Anything else = enabled mod (including the rare legitimate
                // dotted folder a user might have placed — treated as enabled
                // since SMAPI wouldn't load it anyway, but we don't break it).
                let isEnabled = !entry.hasPrefix(".")
                let topLevelLogicalFolder = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry
                let physicalRoot = (modsPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: physicalRoot, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                // Throttled progress publish (~12/s) so the launch overlay can
                // show "Analyse de <mod>… (done/total)" instead of a frozen
                // bar. Cheap relative to the per-folder scan that follows.
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressPublish > 0.08 {
                    lastProgressPublish = now
                    let d = scanDone, t = scanTotal
                    let nm = topLevelLogicalFolder
                    onProgress(ScanProgress(done: d, total: t, currentName: nm))
                }

                scanEntryForMods(at: physicalRoot, topLevelLogicalFolder: topLevelLogicalFolder, isEnabled: isEnabled)
            }
            scannedEntries = (done: scanDone, total: scanTotal)
        }

        return Outcome(mods: scannedMods,
                       modsFolderWasReadable: modsFolderWasReadable,
                       scannedEntries: scannedEntries)
    }
}
