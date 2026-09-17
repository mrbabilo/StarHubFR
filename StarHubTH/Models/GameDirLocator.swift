import Foundation

/// Où est installé le jeu, et où vit l'avatar du compte Steam. Le VM portait
/// ces deux lectures en ligne (`detectDefaultGameDir`, et le bloc avatar de
/// `fetchSteamUser`) sans aucun test.
///
/// `home`, `gogRoot` et le `FileManager` arrivent en paramètres : c'est ce
/// qui rend les deux lectures testables — le domicile et `/Applications`
/// réels sont des états de la machine, pas des entrées de test.
public enum GameDirLocator {

    /// Steam d'abord, GOG ensuite, `""` quand rien n'existe (l'appelant
    /// affiche alors son écran « choisir un dossier »).
    ///
    /// Le chemin rendu est **résolu** des symlinks (`/tmp` → `/private/tmp`,
    /// `Application Support` variable selon l'OS — AGENTS §4.9) : avant
    /// `fileExists` ET avant tout usage ultérieur, pour que les comparaisons
    /// avec `physicalRoot` (cf. §J scanMods) restent cohérentes.
    public static func detectDefault(home: String,
                                     gogRoot: String = "/Applications",
                                     fm: FileManager = .default) -> String {
        let resolve: (String) -> String = { ($0 as NSString).resolvingSymlinksInPath }
        let steamPath = resolve("\(home)/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS")
        if fm.fileExists(atPath: steamPath) {
            return steamPath
        }

        let gogPath = resolve("\(gogRoot)/Stardew Valley.app/Contents/MacOS")
        if fm.fileExists(atPath: gogPath) {
            return gogPath
        }

        return ""
    }

    /// `avatarcache/<steamID>.png`, sinon `.jpg`, sinon `nil`. Un `steamID`
    /// vide ne cherche rien.
    public static func avatarPath(steamID: String, home: String, fm: FileManager = .default) -> String? {
        guard !steamID.isEmpty else { return nil }
        let cache = "\(home)/Library/Application Support/Steam/config/avatarcache"
        let png = "\(cache)/\(steamID).png"
        if fm.fileExists(atPath: png) {
            return png
        }
        let jpg = "\(cache)/\(steamID).jpg"
        if fm.fileExists(atPath: jpg) {
            return jpg
        }
        return nil
    }

    /// Ramène un chemin **choisi par l'utilisateur** au dossier que le reste
    /// de l'application appelle `gameDir` — `Contents/MacOS`, jamais le
    /// bundle ni `Mods/`. Tous les sites du dépôt dérivent `Mods` de là
    /// (`(gameDir as NSString).appendingPathComponent("Mods")`) : la
    /// sémantique ne bouge pas, c'est la descente manuelle jusqu'à
    /// `Contents/MacOS` qu'on supprime.
    ///
    /// Les quatre formes qu'on voit réellement, dans cet ordre :
    /// `…/Contents/MacOS` (déjà bon) ; `Stardew Valley.app` ou le dossier
    /// Steam `Stardew Valley/` (→ `Contents/MacOS` dessous) ; `…/Contents`
    /// (→ `MacOS`) ; `…/Contents/MacOS/Mods` (→ le parent).
    ///
    /// **Ne refuse rien** : un chemin qui ne ressemble à aucune de ces formes
    /// est rendu tel quel. L'écran d'accueil dit déjà « SMAPI non installé »
    /// et les alertes système parlent d'un dossier vide — un garde ici
    /// perdrait plus que le cas qu'il attrape (installations exotiques,
    /// copies portables).
    ///
    /// Le chemin rendu est **résolu** des symlinks, comme celui de
    /// `detectDefault` : les deux nourrissent les mêmes comparaisons avec
    /// `physicalRoot` dans `scanMods` (AGENTS §4.9).
    public static func normalize(pickedPath: String, fm: FileManager = .default) -> String {
        let resolved = (pickedPath as NSString).resolvingSymlinksInPath
        let path = resolved as NSString

        // Déjà `…/Contents/MacOS` : rien à faire, et surtout ne pas aller
        // chercher un `Contents/MacOS/Contents/MacOS` fantôme.
        if path.lastPathComponent == "MacOS",
           (path.deletingLastPathComponent as NSString).lastPathComponent == "Contents" {
            return resolved
        }

        // Un bundle `.app`, ou le dossier Steam `Stardew Valley/` : même
        // forme, même descente.
        let inside = path.appendingPathComponent("Contents/MacOS")
        if isDirectory(inside, fm: fm) {
            return inside
        }

        // L'utilisateur s'est arrêté à `Contents`.
        if path.lastPathComponent == "Contents" {
            let macOS = path.appendingPathComponent("MacOS")
            if isDirectory(macOS, fm: fm) {
                return macOS
            }
        }

        // Il a désigné le dossier des mods lui-même — le cas le plus probable
        // quand on demande « où sont mes mods ».
        if path.lastPathComponent == "Mods" {
            return path.deletingLastPathComponent
        }

        return resolved
    }

    /// Est-ce que ce dossier est bien l'intérieur d'une installation de
    /// Stardew Valley ? La question se pose parce qu'on **écrit** ensuite
    /// dedans (`ensureModsFolder`) : créer un `Mods/` dans le premier dossier
    /// venu est un dégât, pas un service.
    ///
    /// Le cas réel qui l'a rendue nécessaire (2026-09-17) : un dossier qui
    /// **contient** les jeux (`/Volumes/…/JEUX EN COURS`, douze `.app`) avait
    /// été enregistré comme `gameDir` faute de pouvoir cliquer le bundle. Il
    /// ne porte aucun de ces marqueurs ; le vrai dossier du jeu en porte cinq.
    ///
    /// Les marqueurs sont mesurés sur une installation réelle, pas devinés.
    /// Deux exclusions délibérées : `Content/` vit sous `Contents/Resources/`,
    /// pas à côté de l'exécutable ; et **`Mods/` n'est pas un marqueur** —
    /// c'est nous qui le créons (ici et dans `ModZipInstaller`). Un marqueur
    /// que notre propre code fabrique rendrait le garde inopérant au second
    /// passage : le dossier refusé une fois serait accepté la fois suivante.
    ///
    /// Un seul suffit. Une installation neuve n'a pas encore `smapi-internal/`,
    /// mais elle a toujours son exécutable.
    public static func isGameFolder(_ path: String, fm: FileManager = .default) -> Bool {
        let markers = ["Stardew Valley", "StardewValley", "StardewModdingAPI",
                       "smapi-internal"]
        return markers.contains { fm.fileExists(atPath: (path as NSString).appendingPathComponent($0)) }
    }

    /// Ce qui a mal tourné en choisissant un dossier. Le store le rend, le
    /// ViewModel le traduit : Core ne connaît ni `L10n` ni le bundle (§3).
    public enum SelectionProblem: Sendable, Equatable {
        /// Le dossier a été enregistré, mais rien n'y ressemble au jeu — et
        /// donc aucun `Mods/` n'y a été créé.
        case notAGameFolder
        /// Le dossier est bien celui du jeu, mais `Mods/` n'a pas pu être créé.
        case modsFolderUnavailable
    }

    /// Le dossier `Mods` sous un `gameDir`, créé s'il manque. Rend le chemin ;
    /// **lève** si la création échoue — un bundle en lecture seule ou un
    /// `/Applications` sans droits doit se voir, pas se deviner à un scan qui
    /// rend zéro mod.
    @discardableResult
    public static func ensureModsFolder(gameDir: String, fm: FileManager = .default) throws -> String {
        let mods = (gameDir as NSString).appendingPathComponent("Mods")
        if isDirectory(mods, fm: fm) {
            return mods
        }
        try fm.createDirectory(atPath: mods, withIntermediateDirectories: true)
        return mods
    }

    private static func isDirectory(_ path: String, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

}
