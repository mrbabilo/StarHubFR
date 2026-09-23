import Foundation

/// A1-T7 — ce qu'une mise à jour doit remettre dans le mod, au-delà des 18 noms
/// de `ModConfigFiles.preservable`.
///
/// **La règle : un fichier absent de l'archive neuve est une donnée locale.**
/// Le mod l'a écrit en jouant (`<sauvegarde>_SaveData.save` de FarmTypeManager,
/// `savedata/seenrecipes/` de BetterCrafting, `data/farmers/` d'AnimalHusbandry),
/// ou l'utilisateur l'a posé là. Mesuré sur le parc : **100 fichiers sur 52 mods**
/// portent dans leur nom l'identifiant d'une sauvegarde réelle — ils n'ont donc pu
/// être écrits que sur cette machine. Cadrage complet en `ROADMAP.md` §8.4.
///
/// **Pourquoi cette règle ne rejoue pas le défaut d'`isAuthorLanguageFile`.**
/// Ce défaut-là (B4-T4 puis C2-T4) préservait un fichier *que la version neuve
/// livrait aussi*, et figeait ainsi l'anglais de l'auteur à chaque mise à jour.
/// Ici l'asymétrie l'interdit par construction : **si le fichier est dans
/// l'archive neuve, il n'est jamais préservé**. C'est la justification de la
/// règle, plus solide qu'un comptage d'échantillons.
///
/// **Ce qu'elle ne sait pas faire** : distinguer une donnée d'utilisateur d'un
/// fichier que l'auteur a retiré entre deux versions. Aucune règle de nom, de
/// dossier ou d'extension ne le peut — c'est prouvé sur le parc :
/// `FarmTypeManager/data/` contient `default.json` (livré par le mod) **à côté**
/// de `essai_448486987_SaveData.save` (écrit en jouant). Seule l'archive les
/// sépare. Le risque résiduel est donc *borné*, pas supprimé : un tel fichier
/// survit à la mise à jour, et le bilan d'installation le dit.
enum PreservedModData {

    /// Le réglage « remettre les données après une mise à jour » tranche le
    /// sort des extras : remis dans le mod (défaut) ou laissés dans la
    /// sauvegarde d'installation. La clé absente vaut **true** — le
    /// comportement livré d'A1-T7 — et jamais le `false` du `bool(forKey:)` nu.
    static func shouldRestore(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: UDKey.restoreModDataOnUpdate) == nil
            ? true
            : defaults.bool(forKey: UDKey.restoreModDataOnUpdate)
    }

    /// Les chemins relatifs du mod installé que l'archive neuve ne livre pas.
    ///
    /// - Parameters:
    ///   - installed: chemins relatifs au dossier du mod installé.
    ///   - shippedByArchive: chemins relatifs à la racine du mod **dans
    ///     l'archive neuve déjà extraite**.
    ///   - alreadyHandled: ce que `snapshotUserConfigs` gouverne déjà (la liste
    ///     blanche des 18 noms, **avant** son filtre `isAuthorLanguageFile`).
    ///     Ces chemins sortent d'ici quoi qu'il arrive : leur sort est décidé
    ///     là-bas, y compris l'exclusion délibérée d'`i18n/en.json`. Les
    ///     reprendre ici la contredirait en silence.
    ///
    /// L'ordre d'entrée est conservé — le bilan lit cette liste telle quelle.
    static func extraPaths(installed: [String],
                           shippedByArchive: [String],
                           alreadyHandled: [String]) -> [String] {
        let shipped = Set(shippedByArchive.map(normalized))
        let handled = Set(alreadyHandled.map(normalized))
        var seen = Set<String>()
        return installed.filter { path in
            let key = normalized(path)
            guard !key.isEmpty, !shipped.contains(key), !handled.contains(key) else { return false }
            // Les résidus du système ne sont pas des données : les recopier
            // ferait revivre un `.DS_Store` que l'utilisateur vient d'effacer.
            //
            // ⚠️ Le test se fait sur le chemin **d'origine**, pas sur `key` :
            // `OSJunk` compare des noms exacts (`.DS_Store`, `__MACOSX`), et
            // les chercher dans la forme minuscule ne trouvait que le préfixe
            // `._`. Le premier jet le faisait — trois résidus sur quatre
            // passaient, et seul un test les a montrés.
            let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            guard !components.contains(where: { OSJunk.isJunk(String($0)) }) else { return false }
            return seen.insert(key).inserted
        }
    }

    /// Forme de comparaison d'un chemin relatif.
    ///
    /// Minuscules **à dessein** : le système de fichiers de macOS est
    /// insensible à la casse par défaut, donc `Assets/Foo.png` dans l'archive
    /// et `assets/foo.png` sur le disque sont **le même fichier**. Les tenir
    /// pour distincts préserverait un fichier que la copie neuve va écraser de
    /// toute façon — et l'archive gagnerait quand même, en laissant croire au
    /// bilan qu'on a sauvé quelque chose.
    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    /// Met les extras à l'abri avant que le dossier du mod ne soit effacé.
    ///
    /// Rend un dictionnaire chemin relatif → fichier temporaire, de la même
    /// forme que `snapshotUserConfigs`. Un fichier qu'on n'arrive pas à copier
    /// est simplement absent du résultat : la sauvegarde d'installation
    /// (`ModInstallBackupManager`, dossier entier) en garde une copie, donc
    /// échouer ici ne perd rien de définitif.
    static func snapshot(_ relativePaths: [String],
                         from modFolder: URL,
                         using fm: FileManager) -> [String: URL] {
        var out: [String: URL] = [:]
        for relative in relativePaths {
            let source = modFolder.appendingPathComponent(relative)
            // Nom à plat : le chemin relatif est la clé, le fichier temporaire
            // n'est qu'un entrepôt.
            let flat = relative.replacingOccurrences(of: "/", with: "__")
            let tmp = fm.temporaryDirectory
                .appendingPathComponent("starhubfr_extra_\(UUID().uuidString)_\(flat)")
            do {
                try fm.copyItem(at: source, to: tmp)
                out[relative] = tmp
            } catch {
                try? fm.removeItem(at: tmp)
            }
        }
        return out
    }

    /// Remet les extras dans la copie fraîchement installée.
    ///
    /// ⚠️ **Ne lance jamais**, à la différence de `restoreUserConfigs`. La
    /// distinction est délibérée : les 18 noms de la liste blanche sont des
    /// réglages que l'utilisateur a écrits à la main, et rater leur
    /// restauration doit arrêter l'installation. Un extra, lui, peut être un
    /// fichier périmé qu'une nouvelle arborescence rend impossible à reposer
    /// (un chemin devenu dossier, par exemple) — faire avorter pour cela une
    /// mise à jour par ailleurs réussie coûterait plus que ça ne protège,
    /// **d'autant que le dossier entier est déjà en sauvegarde**. Les échecs
    /// se comptent et remontent au bilan ; ils ne disparaissent pas.
    ///
    /// Les entrées restaurées sortent du dictionnaire, pour que le ménage de
    /// l'appelant ne balaie que les restes réels.
    static func restore(_ snapshots: inout [String: URL],
                        into destFolder: URL,
                        using fm: FileManager) -> (restored: Int, restoredPaths: [String], failed: [String]) {
        var restored = 0
        var restoredPaths: [String] = []
        var failed: [String] = []
        for relative in snapshots.keys.sorted() {
            guard let tmp = snapshots[relative] else { continue }
            let target = destFolder.appendingPathComponent(relative)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // La copie neuve ne livre pas ce fichier (c'est la définition
                // d'un extra), mais un dossier homonyme peut occuper la place.
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: tmp, to: target)
                restored += 1
                restoredPaths.append(relative)
                snapshots.removeValue(forKey: relative)
            } catch {
                failed.append(relative)
            }
        }
        return (restored, restoredPaths, failed)
    }

    /// Ce qu'il faut dire à l'utilisateur d'une préservation, mod par mod.
    ///
    /// Rend des couples (message, estUnÉchec). Une préservation réussie se
    /// mentionne — le joueur doit savoir que ses parties ont suivi la mise à
    /// jour ; un échec se signale plus fort, parce que c'est précisément le cas
    /// où un fichier dort désormais dans la seule sauvegarde d'installation.
    /// Rien n'est rendu quand il n'y a rien à dire : une mise à jour ordinaire
    /// ne doit pas bavarder.
    static func messages(restored: Int, failed: [String],
                         restoredPaths: [String] = [], skipped: Int = 0,
                         modFolder: String)
        -> [(text: String, isFailure: Bool)] {
        var out: [(String, Bool)] = []
        if restored > 0 {
            let names = restoredPaths.prefix(5).joined(separator: ", ")
            let extra = restoredPaths.count > 5
                ? " (+\(restoredPaths.count - 5) autres)" : ""
            let liste = names.isEmpty ? "" : " : " + names + extra
            out.append(("\(modFolder) : \(restored) fichier(s) de données du mod "
                        + "remis en place après la mise à jour\(liste)", false))
        }
        if skipped > 0 {
            // Réglage « ne pas remettre » : les données dorment dans la
            // sauvegarde d'installation — l'utilisateur doit savoir où.
            out.append(("\(modFolder) : \(skipped) fichier(s) de données non remis "
                        + "par choix du réglage — ils restent dans la sauvegarde "
                        + "d'installation du mod", true))
        }
        if !failed.isEmpty {
            // Les noms, pas seulement le compte : sans eux l'utilisateur ne
            // sait pas quoi aller rechercher dans la sauvegarde.
            let names = failed.prefix(5).joined(separator: ", ")
            let extra = failed.count > 5 ? " (+\(failed.count - 5) autres)" : ""
            out.append(("\(modFolder) : \(failed.count) fichier(s) de données n'ont pas pu "
                        + "être remis — ils restent dans la sauvegarde d'installation : "
                        + names + extra, true))
        }
        return out
    }

    /// Les chemins relatifs de tous les fichiers ordinaires sous `root`.
    ///
    /// ⚠️ **`.skipsHiddenFiles` est volontairement absent.** Un mod écrit
    /// parfois ses données dans un dossier caché, et surtout : le dossier d'un
    /// mod en pause porte lui-même un point. Le tri des résidus système se fait
    /// dans `extraPaths`, par nom, pas par « caché ».
    ///
    /// Le chemin est résolu des deux côtés avant le découpage — sur macOS
    /// `/var/folders` est un lien vers `/private/var/folders`, et l'énumérateur
    /// rend des URL **résolues** même si la racine ne l'était pas (piège maison,
    /// `CLAUDE.md` §Système de fichiers).
    static func relativeFiles(under root: URL, using fm: FileManager) -> [String] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = fm.enumerator(at: root.resolvingSymlinksInPath(),
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: []) else { return [] }
        var out: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            // Bornage strict : `hasPrefix` nu confondrait « Mod » et « ModX »
            // (même garde que `ModConfigFiles.preservableFiles`).
            if path == base { continue }
            guard path.hasPrefix(base + "/") else { continue }
            out.append(String(path.dropFirst(base.count + 1)))
        }
        return out
    }
}
