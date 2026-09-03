import Foundation

/// Ce qu'il faut faire d'une archive **sans `manifest.json`**.
///
/// Ce n'est pas un mod : c'est une traduction, ou des fichiers à greffer dans
/// un mod déjà installé (bagages `ItemBags`, packs de recettes…). L'installateur
/// ordinaire les refuse toutes — il classe par structure et cherche des
/// manifestes —, alors qu'elles sont parfaitement légitimes.
///
/// Cinq formes, relevées sur des archives réelles. Elles ne se distinguent
/// **pas** par leur structure mais par ce que leur contenu permet de déduire :
///
/// 1. Un dossier racine qui porte le nom d'un mod installé
///    (`FishingLogbook/i18n/fr.json`) — la destination est écrite dans
///    l'archive.
/// 2. Un dossier racine dont le nom **ressemble** à un mod installé sans lui
///    être égal (`MakeGuntherRealFR/` quand le mod s'appelle
///    `[CP] Make Gunther Real`). Mesuré : ni l'égalité ni le simple retrait
///    d'un suffixe de langue ne suffisent. **Ce cas se tranche en demandant**,
///    jamais en devinant : se tromper ici écrit dans le mauvais mod.
/// 3. Un dossier racine nommé, chemin complet
///    (`ItemBags/assets/Modded Bags/*.json`).
/// 4. Des chemins **déjà relatifs à la racine du mod** (`i18n/fr.json`) : rien
///    dans l'archive ne nomme le mod, c'est le geste qui le désigne — la fiche
///    sur laquelle on la dépose.
///
/// 5. Un fichier **nu** qui porte le nom d'un fichier déjà présent à la racine
///    d'un mod installé (`bagconfig.json` pour `ItemBags`) : un remplacement de
///    configuration, genre entier sur Nexus. C'est le **nom** qui désigne
///    l'hôte, et il ne vaut que s'il ne désigne qu'un seul mod.
///
/// Une sixième forme n'est pas traitée ici : des fichiers **nus** à la racine
/// (`Cloth and Colors Bag.json`), que seul leur contenu situe. Elle appartient à
/// `DroppedContentRecognizer`, qui désigne l'hôte par son `UniqueID` SMAPI — la
/// bonne clé — là où ce classificateur ne connaît que des noms de dossier.
public enum ManifestlessArchive {
    public enum Kind: Equatable, Sendable {
        /// Des fichiers de langue, à poser dans le mod traduit.
        case translation
        /// Des fichiers ajoutés à un mod existant.
        case addon
    }

    /// Un fichier de l'archive et sa place dans le mod hôte.
    public struct Entry: Equatable, Sendable {
        /// Chemin dans l'archive.
        public let source: String
        /// Chemin **relatif au dossier du mod hôte**.
        public let destination: String

        public init(source: String, destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Le mod à modifier, par son `folderName` **logique**. C'est
        /// l'appelant qui en tire le nom physique — un mod en pause vit dans un
        /// dossier préfixé d'un point, et le parc réel en compte 746 sur 863.
        public let hostFolderName: String
        public let kind: Kind
        public let entries: [Entry]

        public init(hostFolderName: String, kind: Kind, entries: [Entry]) {
            self.hostFolderName = hostFolderName
            self.kind = kind
            self.entries = entries
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// La destination est certaine.
        case plan(Plan)
        /// L'archive est reconnue, mais le mod hôte reste à désigner. Les
        /// candidats sont proposés du plus ressemblant au moins ressemblant.
        case needsHost(candidates: [String], kind: Kind, entries: [Entry])
        /// Rien ne permet de conclure. Mieux vaut refuser que déposer au hasard.
        case unrecognised
    }

    /// Les dossiers qu'un mod porte **à l'intérieur** de lui.
    ///
    /// Une archive dont tous les dossiers de tête en sont ne nomme aucun mod :
    /// ses chemins sont déjà relatifs à la racine de celui qui la recevra.
    /// Retirer `i18n` comme s'il s'agissait du nom d'un mod poserait le
    /// `fr.json` à la racine du dossier, où SMAPI ne le lira jamais.
    /// `content` en est volontairement absent : c'est le nom du dossier du
    /// **jeu**, et une archive de remplacement XNB qui en porterait un se
    /// verrait déposée dans un mod. Aucun cas relevé n'en demande.
    private static let modContentDirectories: Set<String> = ["i18n", "assets"]

    /// - Parameters:
    ///   - paths: les chemins que porte l'archive, dossiers exclus.
    ///   - installedFolderNames: les `folderName` **logiques** des mods de
    ///     premier niveau installés.
    /// - Parameter rootFileOwners: pour chaque nom de fichier présent **à la
    ///   racine** d'un mod installé, les mods qui le portent. C'est ce qui
    ///   permet de reconnaître un remplacement de configuration.
    public static func classify(paths: [String],
                                installedFolderNames: [String],
                                rootFileOwners: [String: [String]] = [:]) -> Outcome {
        let files = paths.filter { !$0.hasSuffix("/") && !$0.isEmpty }
        guard !files.isEmpty else { return .unrecognised }

        // ── Un fichier nu qui porte le nom d'un fichier déjà là : le cas 5.
        // Testé **avant** la racine unique, ces archives n'ayant pas de dossier.
        if let outcome = replacementOutcome(for: files, owners: rootFileOwners) {
            return outcome
        }

        // ── Des chemins déjà relatifs à la racine du mod : le cas 4. Testé
        // **avant** la racine unique, sinon une archive faite du seul dossier
        // `i18n/` se ferait décapiter de ce qui la rend lisible par le jeu.
        if let entries = modRootRelativeEntries(of: files, installed: installedFolderNames) {
            return .needsHost(candidates: [], kind: kind(of: entries), entries: entries)
        }

        // ── Un dossier racine unique : le cas 1, 2 ou 3.
        if let root = singleRoot(of: files) {
            // Le mod visé est peut-être plus bas que le premier emballage :
            // la traduction française de UI Info Suite 2 Alternative répète
            // son propre nom deux fois avant `UIInfoSuite2Alt/i18n/fr.json`.
            // C'est toujours le cas 1 — la destination est écrite dans
            // l'archive —, simplement plus profond.
            if let known = firstInstalledLevel(of: files, installed: installedFolderNames) {
                let entries = strip(prefix: known, from: files)
                if !entries.isEmpty {
                    let name = known.components(separatedBy: "/").last ?? known
                    return .plan(Plan(hostFolderName: name, kind: kind(of: entries),
                                      entries: entries))
                }
            }
            var prefix = root
            var entries = strip(prefix: prefix, from: files)
            guard !entries.isEmpty else { return .unrecognised }

            // **Un dossier de présentation qui en emballe un autre** — variante
            // du cas 2. Relevé sur une archive réelle,
            // `Nyapu Style Lilybrook/[CP] Lilybrook/Assets/…` : la racine ne
            // désigne rien, mais le niveau en dessous vise bien un mod installé.
            // Sans cette descente, l'archive partait en « à désigner » avec des
            // candidats tirés du mauvais nom.
            if !installedFolderNames.contains(prefix),
               let inner = singleRoot(of: entries.map(\.destination)),
               !modContentDirectories.contains(inner.lowercased()),
               !strip(prefix: inner, from: entries.map(\.destination)).isEmpty {
                let deeper = prefix + "/" + inner
                let deeperEntries = strip(prefix: deeper, from: files)
                // On ne descend que si le nom du dessous vaut mieux que celui du
                // dessus : soit il désigne un mod installé, soit il ressemble à
                // davantage de mods que la racine n'en évoquait.
                let innerMatches = installedFolderNames.contains(inner)
                    || !candidates(for: inner, among: installedFolderNames).isEmpty
                if innerMatches, !deeperEntries.isEmpty {
                    prefix = inner
                    entries = deeperEntries
                }
            }

            if installedFolderNames.contains(prefix) {
                return .plan(Plan(hostFolderName: prefix, kind: kind(of: entries),
                                  entries: entries))
            }
            // Le nom ne désigne aucun mod installé : proposer, ne pas deviner.
            return .needsHost(candidates: candidates(for: prefix, among: installedFolderNames),
                              kind: kind(of: entries), entries: entries)
        }

        return .unrecognised
    }

    /// Les noms qu'un fichier nu ne doit **jamais** faire reconnaître.
    ///
    /// `manifest.json` d'abord : une archive qui en porte un n'est pas sans
    /// manifeste, et ce classificateur ne tournerait pas. Le nommer quand même
    /// ferme la porte à l'archive qui n'en contiendrait qu'un, orpheline.
    private static let neverAReplacement: Set<String> = ["manifest.json"]

    /// Un remplacement de fichier : l'archive ne porte que des fichiers nus, et
    /// leur nom désigne un fichier déjà présent à la racine d'un mod.
    ///
    /// **Mesuré sur le parc le 2026-08-26** : 76 des 91 noms de fichiers JSON
    /// de premier niveau n'appartiennent qu'à **un seul** mod — `bagconfig.json`
    /// et `modded_items.json` en sont. Mais `config.json` est porté par **544**
    /// mods et `content.json` par **522** : sur ceux-là, deviner écrirait dans
    /// le mauvais dossier une fois sur cinq cents. D'où la règle : un seul
    /// propriétaire donne un plan, plusieurs font demander, aucun ne conclut
    /// rien.
    private static func replacementOutcome(for files: [String],
                                           owners: [String: [String]]) -> Outcome? {
        guard !owners.isEmpty, files.allSatisfy({ !$0.contains("/") }) else { return nil }
        var hosts: Set<String> = []
        var candidates: [String] = []
        for file in files {
            let key = file.lowercased()
            guard !neverAReplacement.contains(key),
                  let owning = owners[key], !owning.isEmpty else { return nil }
            hosts.formUnion(owning)
            candidates.append(contentsOf: owning)
        }
        // Tous les fichiers doivent viser le **même** mod : une archive qui
        // remplacerait des fichiers de deux mods à la fois n'a pas de sens, et
        // la déposer dans l'un écraserait au hasard.
        let entries = files.map { Entry(source: $0, destination: $0) }
        if hosts.count == 1, let host = hosts.first {
            return .plan(Plan(hostFolderName: host, kind: .addon, entries: entries))
        }
        // Plusieurs mods portent ce nom : proposer, ne pas deviner.
        return .needsHost(candidates: Array(Set(candidates)).sorted(),
                          kind: .addon, entries: entries)
    }

    /// Une archive faite des seuls dossiers qu'un mod porte en lui, laissée
    /// telle quelle : chaque fichier garde son chemin, c'est déjà sa place.
    /// `nil` quand ce n'en est pas une.
    private static func modRootRelativeEntries(of files: [String],
                                               installed: [String]) -> [Entry]? {
        let heads = Set(files.compactMap { path -> String? in
            guard let slash = path.firstIndex(of: "/") else { return nil }
            return String(path[path.startIndex..<slash]).lowercased()
        })
        // Chaque fichier doit être dans l'un de ces dossiers : un fichier posé
        // à côté ne serait relatif à rien.
        guard !heads.isEmpty, heads.isSubset(of: modContentDirectories),
              files.allSatisfy({ $0.contains("/") })
        else { return nil }
        // Un mod installé qui porterait l'un de ces noms garde la main : son
        // nom écrit dans l'archive dit alors où déposer, ce qui vaut mieux que
        // de laisser l'hôte à désigner.
        let names = Set(installed.map { $0.lowercased() })
        guard heads.isDisjoint(with: names) else { return nil }
        return files.map { Entry(source: $0, destination: $0) }
    }

    /// Ce qu'une archive dépose : des fichiers de langue, ou autre chose.
    private static func kind(of entries: [Entry]) -> Kind {
        entries.allSatisfy { $0.destination.lowercased().hasPrefix("i18n/") }
            ? .translation : .addon
    }

    /// Le chemin complet du premier dossier **emboîté** qui porte le nom d'un
    /// mod installé, `nil` si la chaîne n'en rencontre aucun.
    ///
    /// Une archive n'emballe pas toujours son mod une seule fois : celle de la
    /// traduction FR de UI Info Suite 2 Alternative le fait deux fois, du même
    /// nom, avant `UIInfoSuite2Alt/`. Descendre d'un seul cran laissait le mod
    /// cible **hors** des candidats proposés — il ne partageait avec
    /// l'emballage que des numéros de version.
    ///
    /// La descente s'arrête au premier niveau reconnu, jamais au plus profond :
    /// `ItemBags/assets/…` doit donner `ItemBags`. Et elle ne franchit jamais
    /// un dossier qu'un mod porte en lui — `i18n` n'emballe rien, c'est déjà
    /// la place du fichier.
    private static func firstInstalledLevel(of files: [String],
                                            installed: [String]) -> String? {
        var remaining = files
        var walked = ""
        while let root = singleRoot(of: remaining) {
            guard !modContentDirectories.contains(root.lowercased()) else { return nil }
            let entries = strip(prefix: root, from: remaining)
            guard !entries.isEmpty else { return nil }
            walked = walked.isEmpty ? root : walked + "/" + root
            if installed.contains(root) { return walked }
            remaining = entries.map(\.destination)
        }
        return nil
    }

    /// Retire un préfixe de dossier des chemins, en laissant tomber ce qui
    /// n'en garderait rien.
    private static func strip(prefix: String, from files: [String]) -> [Entry] {
        files.compactMap { path in
            guard path.hasPrefix(prefix + "/") else { return nil }
            let relative = String(path.dropFirst(prefix.count + 1))
            return relative.isEmpty ? nil : Entry(source: path, destination: relative)
        }
    }

    /// Le dossier racine commun à tous les fichiers, `nil` s'il n'y en a pas un
    /// seul — une archive à plat, ou qui porte plusieurs dossiers, ne dit pas
    /// où elle va.
    private static func singleRoot(of files: [String]) -> String? {
        let roots = Set(files.compactMap { path -> String? in
            guard let slash = path.firstIndex(of: "/") else { return nil }
            return String(path[path.startIndex..<slash])
        })
        // Tous les fichiers doivent être dans ce dossier : un fichier laissé à
        // la racine à côté d'un dossier est une archive qu'on ne comprend pas.
        guard roots.count == 1, let root = roots.first,
              files.allSatisfy({ $0.hasPrefix(root + "/") })
        else { return nil }
        return root
    }

    /// Ce qui ne dit rien de l'identité d'un mod : marqueurs de langue et
    /// préfixes de convention. `[CP]` désigne un pack Content Patcher, pas un
    /// mod en particulier, et le `FR` d'une traduction désigne la traduction,
    /// pas le mod traduit.
    private static let noiseWords: Set<String> = [
        "fr", "fra", "vf", "francais", "francaise", "french", "traduction",
        "cp", "smapi", "mod", "the", "a", "de", "du", "la", "le",
    ]

    /// Les mods installés dont le nom ressemble le plus à celui du dossier.
    ///
    /// **Par mots communs, pas par sous-chaîne.** Le parc réel oppose
    /// `MakeGuntherRealFR` à `[CP] Make Gunther Real` : ni l'un ne contient
    /// l'autre, puisque le premier porte un suffixe et le second un préfixe.
    /// Découpés en mots — la casse chameau compte comme une césure — il leur
    /// reste « make », « gunther » et « real » en partage.
    ///
    /// Les candidats sont **proposés**, jamais choisis : écrire dans le mauvais
    /// mod ne se rattrape pas.
    static func candidates(for folder: String, among installed: [String],
                           limit: Int = 8) -> [String] {
        let needle = significantWords(folder)
        guard !needle.isEmpty else { return [] }
        return installed
            .map { name -> (name: String, shared: Int, gap: Int) in
                let words = significantWords(name)
                return (name, words.intersection(needle).count,
                        abs(compact(name).count - compact(folder).count))
            }
            .filter { $0.shared > 0 }
            // Le plus de mots en partage d'abord ; à égalité, le nom dont la
            // longueur est la plus proche — entre `Parchment` et `[CP] Parchment
            // Example Pack` pour un `ParchmentFR`, le premier gagne.
            .sorted { ($0.shared, -$0.gap) > ($1.shared, -$1.gap) }
            .prefix(limit)
            .map(\.name)
    }

    /// Les mots porteurs d'identité d'un nom : sans accents ni casse, coupés
    /// sur la ponctuation **et** sur la casse chameau (`MakeGuntherReal` donne
    /// trois mots), débarrassés de ce qui ne distingue rien.
    ///
    /// **Une suite de majuscules se coupe avant le mot qu'elle précède** :
    /// `UIInfoSuite2Alt` rend `ui`, `info`, `suite2`, `alt`. Sans cette
    /// césure, l'archive de traduction réelle
    /// `UI Info Suite 2 Alternative FR` ne partageait **aucun** mot avec le
    /// dossier `UIInfoSuite2Alt` du parc : l'hôte était absent des candidats
    /// et la feuille en proposait quatre autres, tous faux. Mesuré sur les 947
    /// mods installés le 2026-09-03 — en simulant, pour chacun, une archive
    /// nommée comme lui espaces retirés : l'hôte est retrouvé 933 fois contre
    /// 930 avant, et figure 928 fois dans les quatre candidats affichés contre
    /// 925. Aucun cas perdu, et le cas réel passe d'absent au premier rang.
    ///
    /// Une suite de majuscules **seule** reste entière (`SVE`) : la césure
    /// n'a lieu que si une minuscule suit, c'est-à-dire si un mot commence.
    static func significantWords(_ name: String) -> Set<String> {
        var words: [String] = []
        var current = ""
        let characters = Array(name)
        for (index, character) in characters.enumerated() {
            if character.isUppercase, !current.isEmpty {
                let previousIsLower = current.last?.isUppercase == false
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // `UIInfo` : le `I` clôt le sigle, le `nfo` ouvre un mot.
                let opensAWord = current.last?.isUppercase == true && next?.isLowercase == true
                if previousIsLower || opensAWord {
                    words.append(current)
                    current = ""
                }
            }
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        let folded = words.map {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive],
                       locale: Locale(identifier: "en_US_POSIX"))
        }
        return Set(folded.filter { !$0.isEmpty && !noiseWords.contains($0) })
    }

    /// Réduit un nom à ses lettres et chiffres, sans accents ni casse.
    static func compact(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }
}
