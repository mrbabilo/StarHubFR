import Foundation

/// La règle de traversal des dossiers de mods, **copiée du code SMAPI**
/// (`SMAPI.Toolkit/Framework/ModScanning/ModScanner.cs`, lu le 2026-10-02) —
/// l'oracle exigé par la case A1-T4 : « que fait SMAPI d'un manifeste sous
/// `examples/` », tranché dans ses sources, pas dans un schéma.
///
/// La règle : un dossier est un **dossier de recherche** (on descend dedans)
/// seulement s'il contient au moins un sous-dossier et **aucun fichier
/// pertinent**. Sinon il est lu comme **un** mod — manifeste local, point —
/// et ses sous-dossiers ne sont jamais scannés. Conséquence mesurée sur le
/// parc (simulation d'activation de tous les mods en pause, 2026-10-02) :
/// **15 entrées** que notre ancien balayage listait et que SMAPI ne
/// chargerait pas — exemples, gabarits, assets nichés sous un vrai mod
/// (`BushBloomMod/examples/`, `MakeLove/ContentPackTemplate/`,
/// `ValleyBonds/…/assets/…`) — et **zéro** mod que SMAPI verrait et nous
/// pas. Lister ces entrées mentait sur ce qui tourne.
///
/// Deux précisions du code SMAPI reproduites ici :
/// - `IgnoreFileExtensions` : README, images, archives… ne comptent pas
///   comme fichiers pertinents (un parent réduit à un `README.md` reste un
///   dossier de recherche). L'entrée `".tar.gz"` de leur table est morte —
///   `Path.GetExtension` ne rend jamais `".tar.gz"` — et le comportement
///   réel (un `.gz` compte comme pertinent) est conservé.
/// - le manifeste lui-même **compte** comme fichier pertinent (extension
///   `.json`, hors liste) : un dossier à manifeste n'est donc jamais un
///   dossier de recherche — SMAPI le lit comme un mod et ignore ce qui est
///   en dessous.
enum ModFolderTraversal {

    /// Extensions sans poids dans la décision (copie de `IgnoreFileExtensions`).
    static let ignoredExtensions: Set<String> = [
        "doc", "docx", "md", "rtf", "txt",
        "bmp", "gif", "ico", "jpeg", "jpg", "png", "psd", "tif", "xcf",
        "rar", "zip", "7z", "tar",
        "backup", "bak", "old",
        "url", "lnk",
    ]

    /// Noms d'outils sans poids (copie de `IgnoreFilesystemNames`, hors
    /// entrées à point et AppleDouble déjà couverts par `OSJunk`/`skipsHiddenFiles`).
    static let irrelevantNames: Set<String> = [
        "__folder_managed_by_vortex", "desktop.ini", "thumbs.db", "mcs",
    ]

    static func isIrrelevant(_ name: String) -> Bool {
        OSJunk.isJunk(name) || irrelevantNames.contains(name.lowercased())
    }

    /// Les manifestes que SMAPI lirait sous `root`, dans l'ordre de visite.
    /// Vide quand SMAPI n'en lirait aucun. Les entrées à point (mods en
    /// pause, `.git`, AppleDouble) ne sont pas suivies, comme pour l'énumérateur.
    static func manifestURLs(under root: URL,
                             fileManager: FileManager = .default) -> [URL] {
        var out: [URL] = []
        collect(folder: root, into: &out, fileManager: fileManager)
        return out
    }

    private static func collect(folder: URL, into out: inout [URL],
                                fileManager: FileManager) {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        } catch {
            entries = [] // dossier illisible : rien à traverser
        }
        var subfolders: [URL] = []
        var relevantFileCount = 0
        var manifestURL: URL?
        for entry in entries {
            let name = entry.lastPathComponent
            if isIrrelevant(name) { continue }
            let isDirectory: Bool
            do {
                isDirectory = try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                isDirectory = false
            }
            if isDirectory {
                subfolders.append(entry)
                continue
            }
            if name.lowercased() == "manifest.json" { manifestURL = entry }
            if !ignoredExtensions.contains(entry.pathExtension.lowercased()) {
                relevantFileCount += 1
            }
        }
        if !subfolders.isEmpty && relevantFileCount == 0 {
            // Dossier de recherche : on descend, le manifeste local n'est pas lu.
            for sub in subfolders {
                collect(folder: sub, into: &out, fileManager: fileManager)
            }
        } else if let manifestURL {
            // Un mod : le manifeste local, et rien en dessous.
            out.append(manifestURL)
        }
        // Ni dossier de recherche ni mod : SMAPI ne charge rien ici.
    }
}
