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

    /// `folderName` du mod hôte → les **greffes** posées dessus.
    ///
    /// Plusieurs par mod, contrairement à la traduction : un même mod reçoit
    /// volontiers plusieurs lots de sacs `ItemBags`, et rien ne les fait se
    /// recouvrir puisqu'ils déposent des fichiers différents.
    ///
    /// Le type est celui des traductions, à dessein : il porte exactement ce
    /// qu'il faut — l'hôte, la fiche Nexus quand on la connaît, les fichiers
    /// déposés et ceux qu'ils ont recouverts. Son nom parle de traduction par
    /// héritage, pas par nature.
    public private(set) var addonsByHost: [String: [InstalledTranslation]]

    public init(byHost: [String: InstalledTranslation] = [:],
                addonsByHost: [String: [InstalledTranslation]] = [:]) {
        self.byHost = byHost
        self.addonsByHost = addonsByHost
    }

    /// **Relit l'ancien format.** Les registres écrits avant que les greffes
    /// existent ne portent que `byHost` ; exiger `addonsByHost` ferait échouer
    /// tout le décodage, et l'utilisateur perdrait le seul moyen de retirer les
    /// traductions déjà posées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byHost = try container.decode([String: InstalledTranslation].self, forKey: .byHost)
        addonsByHost = try container.decodeIfPresent(
            [String: [InstalledTranslation]].self, forKey: .addonsByHost) ?? [:]
    }

    public func translation(forHost host: String) -> InstalledTranslation? {
        byHost[host]
    }

    /// Les greffes posées sur ce mod, de la plus récente à la plus ancienne.
    public func addons(forHost host: String) -> [InstalledTranslation] {
        (addonsByHost[host] ?? []).sorted { $0.installedAt > $1.installedAt }
    }

    /// Enregistre une greffe, en **remplaçant** celle qui porte la même
    /// identité.
    ///
    /// L'identité est l'identifiant Nexus quand il est connu, le nom sinon :
    /// redéposer le même lot de sacs doit mettre à jour la ligne, pas en créer
    /// une seconde qui prétendrait qu'il est installé deux fois.
    public mutating func recordAddon(_ addon: InstalledTranslation) {
        var existing = addonsByHost[addon.hostFolderName] ?? []
        existing.removeAll { Self.sameAddon($0, addon) }
        existing.append(addon)
        addonsByHost[addon.hostFolderName] = existing
    }

    /// Oublie une greffe, et rend ce qu'on savait d'elle.
    @discardableResult
    public mutating func forgetAddon(_ addon: InstalledTranslation) -> InstalledTranslation? {
        guard var existing = addonsByHost[addon.hostFolderName],
              let index = existing.firstIndex(where: { Self.sameAddon($0, addon) })
        else { return nil }
        let removed = existing.remove(at: index)
        // Une clé qui ne porte plus rien s'en va : sinon le registre garderait
        // la trace d'hôtes sans greffe, et « ce mod a des greffes » deviendrait
        // faux sans que rien ne le dise.
        addonsByHost[addon.hostFolderName] = existing.isEmpty ? nil : existing
        return removed
    }

    /// Deux greffes sont la même quand elles désignent la même chose : leur
    /// identifiant Nexus s'il est connu des deux côtés, leur nom sinon.
    /// Deux greffes sont la même quand elles désignent la même chose.
    ///
    /// L'identifiant Nexus d'abord, quand les deux le portent. À défaut, celui
    /// que porte **le nom du fichier téléchargé** : 14 des 15 archives du jeu
    /// d'épreuve en ont un, et c'est le seul repère qui survive à un changement
    /// de version. Le nom en dernier, comparé par préfixe.
    ///
    /// **L'égalité stricte des noms ne convenait pas** : redéposer une version
    /// plus récente change le nom du fichier — `Utility Bags-37381-1-0-0-…`
    /// devient `Utility Bags-37381-1-1-0-…` — et l'ancienne greffe n'aurait pas
    /// été reconnue. Ses fichiers seraient restés sur le disque, une seconde
    /// ligne se serait ajoutée, et la sauvegarde de la nouvelle aurait pris les
    /// fichiers de l'ancienne pour ceux du mod.
    static func sameAddon(_ lhs: InstalledTranslation, _ rhs: InstalledTranslation) -> Bool {
        if lhs.nexusModId > 0, rhs.nexusModId > 0 { return lhs.nexusModId == rhs.nexusModId }
        let leftIds = NexusModSearch.nexusIdCandidates(inFileName: lhs.nexusName)
        let rightIds = NexusModSearch.nexusIdCandidates(inFileName: rhs.nexusName)
        if !leftIds.isDisjoint(with: rightIds) { return true }
        return NexusModSearch.namesMatch(lhs.nexusName, rhs.nexusName)
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
