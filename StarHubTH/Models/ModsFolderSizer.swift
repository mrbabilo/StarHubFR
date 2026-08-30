import Foundation

/// Ce que pèsent les mods installés, dossier par dossier.
///
/// Mesuré sur le parc réel le 2026-08-24 : 863 dossiers, 103 893 fichiers,
/// **16,8 Go** — pour 23,8 Go libres sur le disque. Le chiffre n'est donc pas
/// décoratif, et les cinq plus gros postes du parc étaient des mods **en
/// pause** : d'où le sous-total `pausedBytes`, la moitié actionnable de la
/// mesure (un mod en pause occupe autant de place qu'un mod actif, sans rien
/// rendre en échange).
public struct ModsFolderSizes: Equatable, Sendable {
    /// Poids par entrée de premier niveau de `Mods/`, **sous son nom sur
    /// disque** — donc préfixé d'un point pour un mod en pause. C'est
    /// `ModItem.physicalFolderName` qui donne cette clé, jamais `folderName` :
    /// joindre sur le nom logique rendrait 0 octet pour tout mod en pause.
    public let byPhysicalFolder: [String: Int64]
    /// Somme des dossiers de premier niveau. Ce n'est **pas** tout à fait le
    /// même ensemble que la liste des mods : celle-ci ne retient que les
    /// dossiers portant un `manifest.json`, quand la mesure pèse tout dossier
    /// qui n'est ni un résidu système ni une quarantaine. C'est voulu — un
    /// dossier sans manifeste occupe la place comme un autre, et le pied de
    /// barre répond à « que pèse mon dossier `Mods/` ». Sur le parc réel
    /// l'écart vaut 60 Mo sur 16,84 Go : cinq dossiers d'outils déposés là.
    ///
    /// Un fichier isolé posé à la racine de `Mods/`, lui, n'est pas compté :
    /// la mesure est par dossier.
    public let totalBytes: Int64
    /// Part de `totalBytes` occupée par les mods en pause.
    public let pausedBytes: Int64
    /// Espace libre du volume **qui porte `Mods/`** — le jeu peut vivre sur un
    /// disque externe. `nil` quand le système ne le dit pas.
    public let availableBytes: Int64?
    public let measuredAt: Date

    public init(byPhysicalFolder: [String: Int64], totalBytes: Int64, pausedBytes: Int64,
                availableBytes: Int64?, measuredAt: Date) {
        self.byPhysicalFolder = byPhysicalFolder
        self.totalBytes = totalBytes
        self.pausedBytes = pausedBytes
        self.availableBytes = availableBytes
        self.measuredAt = measuredAt
    }

    /// Le poids d'un mod, `nil` s'il n'a pas été mesuré.
    ///
    /// Un composant de pack n'en a pas : son `physicalFolderName` porte un `/`
    /// (« Pack/Composant ») et ne peut donc pas être une clé de premier niveau.
    /// C'est voulu — afficher les 3,8 Go du pack sur chacun de ses composants
    /// compterait la même place autant de fois qu'il y a de composants.
    public func bytes(forPhysicalFolder folder: String) -> Int64? {
        byPhysicalFolder[folder]
    }

    /// Déplace la mesure d'un dossier qui vient d'être renommé dans `Mods/`.
    ///
    /// La bascule d'un mod **est** ce renommement (`Foo` ↔ `.Foo`) : le
    /// contenu ne change pas, le poids mesuré reste exact — seule sa clé
    /// bouge. Sans ce déplacement, la recherche sous le nouveau nom échoue
    /// et le poids disparaît jusqu'au prochain scan complet (vu à l'écran
    /// sur la fiche, H-T4b). Le sous-total `pausedBytes` suit le préfixe ;
    /// `totalBytes`, lui, ne bouge pas — renommer ne libère rien.
    public func renamingFolder(from oldKey: String, to newKey: String) -> ModsFolderSizes {
        guard let bytes = byPhysicalFolder[oldKey], oldKey != newKey else { return self }
        var byFolder = byPhysicalFolder
        byFolder.removeValue(forKey: oldKey)
        byFolder[newKey] = bytes
        var paused = pausedBytes
        let wasPaused = oldKey.hasPrefix(".")
        let isPaused = newKey.hasPrefix(".")
        if isPaused != wasPaused {
            paused += isPaused ? bytes : -bytes
        }
        return ModsFolderSizes(byPhysicalFolder: byFolder, totalBytes: totalBytes,
                               pausedBytes: paused, availableBytes: availableBytes,
                               measuredAt: measuredAt)
    }
}

public enum ModsFolderSizer {
    /// Parcourt `Mods/` et pèse chaque dossier de premier niveau.
    ///
    /// Rend `nil` quand le dossier n'existe pas : mieux vaut ne rien afficher
    /// qu'annoncer « 0 octet » à qui n'a pas encore désigné son jeu.
    ///
    /// Compter ~3 s sur un parc de 100 000 fichiers (cache chaud) : à appeler
    /// depuis une file de fond, jamais depuis le fil principal.
    public static func measure(modsFolder: URL, now: Date = Date()) -> ModsFolderSizes? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: modsFolder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let entries = try? fm.contentsOfDirectory(atPath: modsFolder.path)
        else { return nil }

        var byFolder: [String: Int64] = [:]
        var total: Int64 = 0
        var paused: Int64 = 0

        for entry in entries {
            // `.Spotlight-V100` et consorts sont des dossiers commençant par un
            // point : sans ce filtre, ils passeraient pour des mods en pause.
            //
            // Les deux mêmes exclusions que `scanMods()` — le résidu système et
            // la quarantaine d'une réparation. Un dossier `_Trash_*` naît
            // aujourd'hui à côté de `Mods/` et non dedans, mais le scanner
            // s'en protège quand même : trois classifications des entrées de
            // `Mods/` qui divergeraient d'un cas finiraient par se contredire.
            guard !OSJunk.isJunk(entry), !entry.hasPrefix(ModFolderRepairer.trashPrefix)
            else { continue }
            let url = modsFolder.appendingPathComponent(entry)
            var entryIsDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &entryIsDirectory),
                  entryIsDirectory.boolValue
            else { continue }

            let bytes = weigh(url)
            byFolder[entry] = bytes
            total += bytes
            if entry.hasPrefix(".") { paused += bytes }
        }

        return ModsFolderSizes(byPhysicalFolder: byFolder, totalBytes: total,
                               pausedBytes: paused,
                               availableBytes: availableBytes(on: modsFolder),
                               measuredAt: now)
    }

    /// Somme de la place **allouée** par les fichiers d'un dossier.
    ///
    /// Allouée et non logique : la question posée est « combien mes mods
    /// prennent-ils sur mon disque », pas « combien d'octets contiennent-ils ».
    /// L'écart mesuré sur le parc réel est mince (16,84 contre 16,59 Go) mais
    /// il va dans le sens de ce que le disque perd vraiment.
    ///
    /// ⚠️ `options: []` — **pas** `.skipsHiddenFiles`, contrairement au voisin
    /// `ModZipInstaller`. Un mod en pause est un dossier préfixé d'un point :
    /// l'option le sauterait en entier, et le parc réel a plus de 6 Go de mods
    /// en pause qui disparaîtraient de la mesure sans un chiffre pour le dire.
    ///
    /// Les résidus du système (`.DS_Store`, `._Foo`) ne sont pas écartés non
    /// plus : ces octets-là sont sur le disque comme les autres, et une
    /// cinquième copie de `OSJunk.isJunk` n'apporterait qu'une divergence de
    /// plus.
    private static func weigh(_ folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: [],
            // Un sous-dossier illisible ne doit pas interrompre la mesure du
            // reste : le parc est en 0555 par endroits.
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var bytes: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return bytes
    }

    /// Espace libre du volume qui porte ce dossier.
    ///
    /// `volumeAvailableCapacityForImportantUsage` et non `volumeAvailableCapacity` :
    /// macOS compte la place « purgeable » (instantanés, caches) qu'il rendra
    /// pour une écriture importante. C'est le chiffre que le Finder montre, et
    /// celui qui répond à « puis-je encore installer ce mod ».
    static func availableBytes(on folder: URL) -> Int64? {
        try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}
