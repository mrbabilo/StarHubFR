import Foundation

/// Une traduction communautaire posée sur un mod installé.
///
/// Rien d'autre ne la retient : une traduction n'est pas un mod. Elle n'a ni
/// dossier ni manifeste à elle — ce sont des fichiers déposés **dans** le mod
/// qu'elle traduit —, donc le registre des mods, qui ne connaît que des
/// dossiers de premier niveau, l'ignore complètement. Sans cette trace, on ne
/// peut ni savoir qu'une version plus récente existe, ni défaire ce qui a été
/// écrit.
public struct InstalledTranslation: Codable, Equatable, Sendable {
    /// Le mod traduit, par son `folderName` **logique** — celui qui survit à
    /// une mise en pause, comme partout ailleurs dans l'app.
    public let hostFolderName: String
    /// La traduction sur Nexus.
    public let nexusModId: Int
    /// Son titre au moment de l'installation, pour pouvoir la nommer même si
    /// elle disparaît de Nexus ensuite.
    public let nexusName: String
    public let version: String
    /// Date Nexus de la version installée. **C'est elle qui dit si une mise à
    /// jour existe**, pas le numéro de version : les traducteurs ne
    /// l'incrémentent pas tous, et beaucoup reprennent celui du mod d'origine.
    public let updatedAt: Date?
    public let installedAt: Date
    /// Ce que la traduction a déposé, en chemins relatifs au dossier du mod
    /// hôte (`i18n/fr.json`, `assets/…`). Sans cette liste, désinstaller
    /// reviendrait à deviner.
    public let files: [String]
    /// Les fichiers qui existaient **avant** et qu'il a fallu recouvrir, avec
    /// l'endroit où ils ont été mis à l'abri.
    ///
    /// Un mod livré avec son propre `i18n/fr.json`, recouvert par une
    /// traduction communautaire, se retrouverait sans français du tout si la
    /// désinstallation se contentait d'effacer.
    public let replacedFiles: [String: String]

    public init(hostFolderName: String, nexusModId: Int, nexusName: String,
                version: String, updatedAt: Date?, installedAt: Date,
                files: [String], replacedFiles: [String: String] = [:]) {
        self.hostFolderName = hostFolderName
        self.nexusModId = nexusModId
        self.nexusName = nexusName
        self.version = version
        self.updatedAt = updatedAt
        self.installedAt = installedAt
        self.files = files
        self.replacedFiles = replacedFiles
    }
}

/// Ce que l'app retient des traductions posées sur ses mods.
///
/// Type pur : la persistance vit ailleurs, comme pour `ModErrorHistory`.
public struct InstalledTranslationRegistry: Codable, Equatable, Sendable {
    /// `folderName` du mod hôte → la traduction qui y est posée.
    ///
    /// Une seule par mod : en poser deux reviendrait à ce que la seconde
    /// recouvre la première, et on ne saurait plus quoi rendre en désinstallant.
    public private(set) var byHost: [String: InstalledTranslation]

    public init(byHost: [String: InstalledTranslation] = [:]) {
        self.byHost = byHost
    }

    public func translation(forHost host: String) -> InstalledTranslation? {
        byHost[host]
    }

    /// Enregistre une traduction, en remplaçant celle qu'on avait pour ce mod.
    public mutating func record(_ translation: InstalledTranslation) {
        byHost[translation.hostFolderName] = translation
    }

    /// Oublie la traduction d'un mod et rend ce qu'on savait d'elle — c'est
    /// cette valeur qui dit quels fichiers retirer et lesquels remettre.
    @discardableResult
    public mutating func forget(host: String) -> InstalledTranslation? {
        byHost.removeValue(forKey: host)
    }

    /// Une traduction plus récente que celle en place ?
    ///
    /// Sur les **dates Nexus**, jamais sur les numéros de version : mesuré sur
    /// des traductions réelles, beaucoup reprennent le numéro du mod traduit ou
    /// ne bougent pas d'une version à l'autre. Une date absente d'un côté ou de
    /// l'autre ne conclut à rien — mieux vaut ne rien annoncer qu'annoncer à
    /// tort.
    public static func isNewer(_ candidate: Date?, than installed: Date?) -> Bool {
        guard let candidate, let installed else { return false }
        return candidate > installed
    }
}
