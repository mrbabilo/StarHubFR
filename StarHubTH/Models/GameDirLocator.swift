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
}
