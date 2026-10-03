import Foundation

/// D4-T3 — la sonde StarHubFR **embarquée dans l'app** (`build_app.py` la
/// copie dans `Resources/Probe/StarHubFR Probe`), installée comme un mod
/// visible et pausable, mise à jour avec l'app, jamais sans l'accord de
/// l'utilisateur : la carte « Sonde » propose, il confirme.
///
/// L'installation ne remplace que ce que l'app livre (DLL, manifeste,
/// i18n, licence) : `config.json` et tout fichier posé à côté restent.
public enum ProbeBundle {

    public static let folderName = "StarHubFR Probe"

    public enum Action: Equatable, Sendable {
        /// L'app n'embarque pas de sonde (build sans `dotnet` ni jeu).
        case unavailable
        case install(version: String)
        case update(from: String, to: String)
        case upToDate(version: String)
        /// Installée plus récente que celle de l'app : ne rien proposer.
        case newerInstalled(installed: String, bundled: String)
    }

    /// Le dossier embarqué dans l'app, s'il porte un manifeste.
    public static func bundledFolder(resourcesURL: URL?) -> URL? {
        guard let folder = resourcesURL?.appendingPathComponent("Probe/\(folderName)", isDirectory: true),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path)
        else { return nil }
        return folder
    }

    /// La version du manifeste d'un dossier de sonde.
    public static func version(ofFolder folder: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("manifest.json").path),
              let text = String(data: data, encoding: .utf8),
              let manifest = I18nLenientParser.lenientObject(text) else { return nil }
        return manifest["Version"] as? String
    }

    public static func action(bundled: String?, presence: ModPresence) -> Action {
        guard let bundled else { return .unavailable }
        switch presence {
        case .absent:
            return .install(version: bundled)
        case .paused(_, let installed), .enabled(_, let installed):
            if installed == bundled { return .upToDate(version: installed) }
            if ProbeLoadRecords.version(installed, atLeast: components(bundled)) {
                return .newerInstalled(installed: installed, bundled: bundled)
            }
            return .update(from: installed, to: bundled)
        }
    }

    /// Où écrire. Absente : `Mods/StarHubFR Probe`. Installée : le dossier
    /// **réel** — logique, en pause (`.X`), ou composant d'un pack en pause
    /// (`.Tête/Reste`, le point vit sur l'entrée de tête) ; `nil` si aucun
    /// n'existe, plutôt que fabriquer un dossier sans manifeste.
    public static func target(modsRoot: URL, presence: ModPresence) -> URL? {
        guard let logical = presence.folderName else { return modsRoot.appendingPathComponent(folderName) }
        var candidates = [logical, "." + logical]
        let parts = logical.split(separator: "/", maxSplits: 1)
        if parts.count == 2 { candidates.append(".\(parts[0])/\(parts[1])") }
        return candidates.map { modsRoot.appendingPathComponent($0, isDirectory: true) }.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Copie le dossier embarqué dans `target` (créé s'il manque) : chaque
    /// élément livré remplace son homonyme, le reste du dossier est gardé.
    /// Un dossier de mod en 0555 (cas réel du parc) est d'abord ouvert en
    /// écriture.
    public static func install(from source: URL, into target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        ModZipInstaller.grantOwnerWriteAccess(in: target)
        for name in try fm.contentsOfDirectory(atPath: source.path) where !name.hasPrefix(".") {
            let destination = target.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) {
                try ModZipInstaller.removeItemGrantingWriteAccess(atPath: destination.path)
            }
            try fm.copyItem(at: source.appendingPathComponent(name), to: destination)
        }
    }

    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
