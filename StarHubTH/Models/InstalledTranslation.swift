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

/// Déclaration manuelle d'une traduction posée hors de l'app (A3-T6).
///
/// Le registre des `InstalledTranslation` est rempli quand l'app **pose** la
/// traduction — elle sait alors quels fichiers déposer et lesquels remettre.
/// Une traduction mise à la main avant que l'app n'existe, ou copiée d'un
/// autre profil, n'y figure pas : aucun install ne l'a écrite. Sans trace
/// nulle part, le suivi de version reste muet.
///
/// Cette structure porte le strict nécessaire pour le suivi et le retrait
/// « propre » depuis l'UI : l'identité Nexus (`modId`, `name`), la version
/// connue, et la date Nexus si elle a pu être relevée. **Pas de `files`,
/// pas de `replacedFiles`** : on ne sait pas ce que la traduction a
/// recouvert, et prétendre le savoir pour défaire quelque chose qu'on n'a
/// pas fait serait le défaut exact qu'on vient de citer (cf. le commentaire
/// de `replacedFiles` sur `InstalledTranslation`).
///
/// Conséquence pratique : un clic sur « Retirer la déclaration » sur une
/// **déclaration** n'efface rien du disque — il retire juste la ligne du
/// registre. C'est l'utilisateur qui a posé les fichiers, c'est lui qui les
/// enlèvera. L'UI le dit.
extension InstalledTranslation {
    /// La même traduction, rattachée à un autre dossier hôte. Le nom est
    /// inscrit **dans** la traduction : c'est lui que la désinstallation lit.
    func rehosted(to host: String) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: host, nexusModId: nexusModId,
                             nexusName: nexusName, version: version,
                             updatedAt: updatedAt, installedAt: installedAt,
                             files: files, replacedFiles: replacedFiles)
    }
}

public struct DeclaredTranslation: Codable, Equatable, Sendable {
    public let nexusModId: Int
    public let nexusName: String
    public let version: String?
    public let updatedAt: Date?
    public let declaredAt: Date

    public init(nexusModId: Int, nexusName: String, version: String?,
                updatedAt: Date?, declaredAt: Date) {
        self.nexusModId = nexusModId
        self.nexusName = nexusName
        self.version = version
        self.updatedAt = updatedAt
        self.declaredAt = declaredAt
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

    /// `folderName` du mod hôte → la **déclaration** d'une traduction posée à
    /// la main (A3-T6). Une par mod : comme `byHost`, deux déclarations sur le
    /// même mod signifieraient qu'on ne sait plus laquelle l'utilisateur a
    /// voulu dire. La déclaration ne remplace pas une `InstalledTranslation`
    /// existante — elle coexiste avec, jusqu'à ce que l'utilisateur fasse
    /// quelque chose.
    public private(set) var declaredTranslations: [String: DeclaredTranslation]

    public init(byHost: [String: InstalledTranslation] = [:],
                addonsByHost: [String: [InstalledTranslation]] = [:],
                declaredTranslations: [String: DeclaredTranslation] = [:]) {
        self.byHost = byHost
        self.addonsByHost = addonsByHost
        self.declaredTranslations = declaredTranslations
    }

    /// **Relit les anciens formats.** Les registres écrits avant les greffes
    /// ne portent que `byHost` ; ceux écrits avant A3-T6 ne portent ni greffes
    /// ni déclarations. Exiger les nouveaux champs ferait perdre la seule
    /// trace qu'on ait des fichiers déjà posés.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byHost = try container.decode([String: InstalledTranslation].self, forKey: .byHost)
        addonsByHost = try container.decodeIfPresent(
            [String: [InstalledTranslation]].self, forKey: .addonsByHost) ?? [:]
        declaredTranslations = try container.decodeIfPresent(
            [String: DeclaredTranslation].self, forKey: .declaredTranslations) ?? [:]
    }

    /// **Relit les noms des lignes restées sans identifiant.**
    ///
    /// Le dépôt à la main n'apprend l'identifiant depuis le nom de l'archive
    /// que depuis le 2026-08-29 : les lignes écrites avant portent un nom
    /// parfaitement lisible et un identifiant à 0, donc aucun suivi de mise à
    /// jour. Relevé sur le registre réel : 4 lignes sur 13, dont
    /// `MakeGuntherRealFR-34339-1-0-1748539543`.
    ///
    /// Trois règles, et rien d'autre :
    /// - une ligne **déjà identifiée** n'est jamais relue — son identifiant
    ///   vient de Nexus, le nom n'est qu'un nom ;
    /// - une version déjà connue est conservée : elle vient d'une lecture plus
    ///   sûre que celle du nom ;
    /// - la date retenue est celle du **dépôt**, comme au dépôt lui-même —
    ///   sans elle `isNewer` refuse de conclure, et l'identifiant appris ne
    ///   servirait à rien.
    ///
    /// Idempotent : appelé à chaque chargement, il ne trouve plus rien à
    /// apprendre au second passage.
    public func learningNexusIdsFromNames() -> InstalledTranslationRegistry {
        InstalledTranslationRegistry(
            byHost: byHost.mapValues(Self.learningId(in:)),
            addonsByHost: addonsByHost.mapValues { $0.map(Self.learningId(in:)) },
            declaredTranslations: declaredTranslations)
    }

    /// Une ligne, relue si — et seulement si — elle n'a pas d'identifiant et
    /// que son nom en porte un.
    private static func learningId(in entry: InstalledTranslation) -> InstalledTranslation {
        guard entry.nexusModId == 0,
              let origin = NexusArchiveName.parse(entry.nexusName)
        else { return entry }
        return InstalledTranslation(
            hostFolderName: entry.hostFolderName,
            nexusModId: origin.modId,
            nexusName: entry.nexusName,
            version: entry.version.isEmpty ? origin.version : entry.version,
            updatedAt: entry.updatedAt ?? entry.installedAt,
            installedAt: entry.installedAt,
            files: entry.files,
            replacedFiles: entry.replacedFiles)
    }

    /// Fait suivre un renommage du dossier hôte (X60).
    ///
    /// Trois tables désignent l'hôte par son nom de dossier — la traduction
    /// posée, les greffes, et la déclaration manuelle — et le nom est **aussi**
    /// inscrit dans chaque traduction, où la désinstallation le lit pour savoir
    /// dans quel dossier rendre les fichiers. Les quatre suivent ensemble.
    ///
    /// - Returns: `true` si le registre a changé.
    @discardableResult
    public mutating func rename(host old: String, to new: String) -> Bool {
        var changed = false
        if let posted = byHost.removeValue(forKey: old) {
            byHost[new] = posted.rehosted(to: new)
            changed = true
        }
        if let addons = addonsByHost.removeValue(forKey: old) {
            addonsByHost[new] = addons.map { $0.rehosted(to: new) }
            changed = true
        }
        if let declared = declaredTranslations.removeValue(forKey: old) {
            declaredTranslations[new] = declared
            changed = true
        }
        return changed
    }

    public func translation(forHost host: String) -> InstalledTranslation? {
        byHost[host]
    }

    /// La déclaration manuelle d'une traduction sur ce mod, ou `nil`. Une
    /// déclaration ne s'invente pas : elle n'existe que si l'utilisateur l'a
    /// posée. Cf. `hasUndeclaredFrenchTranslation` pour le cas inverse.
    public func declaredTranslation(forHost host: String) -> DeclaredTranslation? {
        declaredTranslations[host]
    }

    /// Une seule déclaration par hôte : en écrire une seconde remplace la
    /// précédente. C'est volontaire — l'utilisateur a peut-être trouvé le
    /// bon identifiant Nexus après coup, et garderait l'ancien comme une
    /// « proposition écartée » ne servirait qu'à afficher deux lignes
    /// concurrentes pour la même traduction.
    public mutating func declare(_ decl: DeclaredTranslation, forHost host: String) {
        declaredTranslations[host] = decl
    }

    /// Oublie une déclaration. Renvoie `true` quand il y avait effectivement
    /// quelque chose à oublier — utile pour le journal.
    @discardableResult
    public mutating func undeclare(forHost host: String) -> Bool {
        declaredTranslations.removeValue(forKey: host) != nil
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
