import Foundation

/// Plan de raccourcis (spec 2026-10-15 §3) : `conflictsOnly` ne déplace que
/// les perdants des collisions clavier avérées ; `fullLayout` range en plus
/// chaque réglage d'un mod classé qui n'est pas sur une touche de sa famille.
public enum KeybindPlanMode: Sendable { case conflictsOnly, fullLayout }

/// Une alternative clavier d'un réglage que le plan propose de réécrire.
/// `from` est la combinaison **analysée** (`KeybindCombo` trie et dédoublonne
/// ses boutons : `LeftShift + H` devient `["H", "LeftShift"]`) — pas le texte
/// du fichier : l'écriture retrouve l'alternative par égalité de combinaison
/// analysée, jamais par comparaison de texte. `to` est la combinaison proposée.
/// Un réglage peut porter plusieurs déplacements, un par alternative perdante
/// (`"H, J"` battu sur les deux) : l'identité inclut donc `from`.
public struct PlannedMove: Equatable, Sendable, Identifiable {
    public enum Reason: Equatable, Sendable { case conflictLoser(against: String), familyPlacement }
    public let modID: String
    public let modName: String
    public let keyPath: [String]
    public let from: KeybindCombo
    public let to: KeybindCombo
    public let family: KeybindFamily
    public let reason: Reason
    public var id: String { modID + "/" + keyPath.joined(separator: ".") + "#" + from.display }
}

/// Un réglage que le plan aurait déplacé mais qu'il laisse en place, avec sa
/// raison : un « non déplacé » est un résultat normal, jamais un échec.
public struct UnmovableSetting: Equatable, Sendable, Identifiable {
    public enum Reason: Equatable, Sendable {
        case noFamily, authorBlock, remapMod, heldModifier, inert,
             contextResolved, familyFull, singleButtonFieldFull
    }
    public let modID: String
    public let modName: String
    public let keyPath: [String]
    public let reason: Reason
    public var id: String { modID + "/" + keyPath.joined(separator: ".") }
}

public struct KeybindPlan: Equatable, Sendable {
    public let mode: KeybindPlanMode
    public let moves: [PlannedMove]
    public let unmovable: [UnmovableSetting]
}

/// Le solveur, pur : un rapport et des familles en entrée, un plan en sortie.
/// Tout est parcouru en ordre trié — deux appels sur le même rapport rendent
/// le même plan, au bouton près.
public enum KeybindPlanner {

    /// Pool de placement : lettres, chiffres de la rangée, touches F —
    /// visibles sur toute disposition (la ponctuation, dont l'invisibilité
    /// dépend de `MacKeyLayout`, est évitée par construction).
    static let letters = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
    static let digits = (0...9).map { "D\($0)" }
    static let functionKeys = (1...12).map { "F\($0)" }
    /// Ordre du repli en corde (spec §3.3).
    static let chordModifiers = ["LeftControl", "LeftShift", "LeftAlt"]

    static func keys(of family: KeybindFamily) -> [String] {
        switch family {
        case .action: letters
        case .info: digits
        case .rare: functionKeys
        }
    }

    /// `families` : folderName → famille (corrections du magasin par-dessus
    /// les déductions — la fusion est faite par l'appelant).
    /// `chordCapable` : les ids de réglage (`modID + "/" + keyPath.joined(separator: "."`)
    /// dont la valeur porte déjà une corde ou une liste — seuls eux
    /// acceptent un repli `modificateur + touche`.
    public static func plan(report: KeybindScanner.KeybindReport,
                            families: [String: KeybindFamily],
                            mode: KeybindPlanMode,
                            chordCapable: Set<String>) -> KeybindPlan {
        let blocks = authorBlockKeys(report.settings)
        let collisionParties = Set(report.collisions.flatMap(\.uses).map {
            KeybindScanner.settingKey($0.modID, $0.keyPath)
        })
        var pool = Pool(gameButtons: Set(report.gameControls.flatMap(\.buttons)),
                        activeUses: report.activeUses)
        var moves: [PlannedMove] = []
        var unmovable: [UnmovableSetting] = []
        // Deux alternatives d'un réglage refusées pour la même raison : une
        // seule ligne, le réglage est le même.
        func note(_ entry: UnmovableSetting) {
            if !unmovable.contains(entry) { unmovable.append(entry) }
        }
        for candidate in candidates(report: report, families: families, mode: mode) {
            let family = families[candidate.modID]
            if let reason = exclusion(of: candidate, family: family, report: report,
                                      blocks: blocks, collisionParties: collisionParties) {
                note(candidate.unmovable(reason))
                continue
            }
            guard let family else { continue }   // couvert par `exclusion` (.noFamily)
            switch pool.place(candidate, family: family,
                              chordCapable: chordCapable.contains(candidate.planID)) {
            case .success(let to):
                // `to == from` : corde de famille déjà en place, rien de mieux.
                guard to != candidate.from else { continue }
                moves.append(PlannedMove(modID: candidate.modID, modName: candidate.modName,
                                         keyPath: candidate.keyPath, from: candidate.from, to: to,
                                         family: family, reason: candidate.reason))
            case .failure(let refusal):
                note(candidate.unmovable(refusal.reason))
            }
        }
        return KeybindPlan(mode: mode,
                           moves: moves.sorted {
                               precedes(($0.modID, $0.keyPath), ($1.modID, $1.keyPath))
                                   || (($0.modID, $0.keyPath) == ($1.modID, $1.keyPath) && $0.from < $1.from)
                           },
                           unmovable: unmovable.sorted { precedes(($0.modID, $0.keyPath), ($1.modID, $1.keyPath)) })
    }

    // MARK: - Candidats

    /// Une alternative d'un réglage que le plan voudrait déplacer, avant la
    /// règle 1.
    struct Candidate {
        let modID: String
        let modName: String
        let keyPath: [String]
        let from: KeybindCombo
        let reason: PlannedMove.Reason
        var settingKey: String { KeybindScanner.settingKey(modID, keyPath) }
        var planID: String { modID + "/" + keyPath.joined(separator: ".") }
        var alternativeKey: String { settingKey + "#" + from.display }
        func unmovable(_ reason: UnmovableSetting.Reason) -> UnmovableSetting {
            UnmovableSetting(modID: modID, modName: modName, keyPath: keyPath, reason: reason)
        }
    }

    /// Les réglages qu'on déplacerait, **avant** exclusions : c'est cet ordre
    /// qui borne `unmovable` aux seuls réglages qui auraient bougé — un mod de
    /// remap sans conflit n'a rien à y faire. Une **alternative** n'y entre
    /// qu'une fois ; un réglage `"H, J"` battu sur les deux y entre deux fois
    /// (sinon le conflit sur J resterait, muet, hors plan et hors refus).
    static func candidates(report: KeybindScanner.KeybindReport,
                           families: [String: KeybindFamily],
                           mode: KeybindPlanMode) -> [Candidate] {
        var seen = Set<String>()
        var out: [Candidate] = []
        func add(_ candidate: Candidate) {
            guard seen.insert(candidate.alternativeKey).inserted else { return }
            out.append(candidate)
        }
        // Règle 2 : action > info > rare > sans famille ; à égalité, le
        // `modID` le plus petit garde. Un mod ne se conflitte pas lui-même :
        // ses autres usages dans le seau du gardien ne perdent pas.
        for collision in report.collisions.sorted(by: { $0.combo < $1.combo }) {
            let ranked = collision.uses.sorted {
                (rank(families[$0.modID]), $1.modID) > (rank(families[$1.modID]), $0.modID)
            }
            guard let keeper = ranked.first else { continue }
            for use in ranked where use.modID != keeper.modID {
                add(Candidate(modID: use.modID, modName: use.modName, keyPath: use.keyPath,
                              from: collision.combo, reason: .conflictLoser(against: keeper.modName)))
            }
        }
        guard mode == .fullLayout else { return sortedForPlacement(out) }
        // Rangement complet : chaque alternative clavier d'un mod classé qui
        // n'est pas une touche simple de sa famille.
        // Mod sans famille : hors champ (jamais déplacé, rien à signaler).
        for setting in report.settings.sorted(by: { precedes(($0.modID, $0.keyPath), ($1.modID, $1.keyPath)) }) {
            guard let family = families[setting.modID] else { continue }
            let familyKeys = keys(of: family)
            for from in setting.combos
            where isKeyboard(from) && !(from.buttons.count == 1 && familyKeys.contains(from.buttons[0])) {
                add(Candidate(modID: setting.modID, modName: setting.modName, keyPath: setting.keyPath,
                              from: from, reason: .familyPlacement))
            }
        }
        return sortedForPlacement(out)
    }

    /// Ordre de placement — celui qui départage deux réglages visant la même
    /// initiale : `modID`, chemin, puis alternative.
    static func sortedForPlacement(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted {
            precedes(($0.modID, $0.keyPath), ($1.modID, $1.keyPath))
                || (($0.modID, $0.keyPath) == ($1.modID, $1.keyPath) && $0.from < $1.from)
        }
    }

    /// Clavier au sens du rangement : ni manette ni souris. Une liaison
    /// souris (`MouseX1`) est un choix délibéré du joueur ; le rangement
    /// complet ne la ramène pas sur une lettre. En collision, elle reste un
    /// perdant ordinaire (`from` = la combinaison en collision).
    static func isKeyboard(_ combo: KeybindCombo) -> Bool {
        !combo.isEmpty && !combo.isGamepad && !combo.buttons.contains { $0.hasPrefix("Mouse") }
    }

    static func rank(_ family: KeybindFamily?) -> Int {
        switch family {
        case .action: 3
        case .info: 2
        case .rare: 1
        case nil: 0
        }
    }

    // MARK: - Règle 1

    /// La raison de ne pas déplacer, dans l'ordre de la règle 1 ; `nil` =
    /// mobile.
    static func exclusion(of candidate: Candidate, family: KeybindFamily?,
                          report: KeybindScanner.KeybindReport,
                          blocks: Set<String>, collisionParties: Set<String>) -> UnmovableSetting.Reason? {
        let key = candidate.settingKey
        if report.remapModIDs.contains(candidate.modID) { return .remapMod }
        // Tenu : déclaré (`heldSettings`), détecté (Ctrl/Maj/Alt seuls sous
        // un nom de modificateur), ou réglage qui n'agit qu'en maintenant
        // une autre touche (`settingChords`) — sa combinaison porte alors
        // une touche qui n'est pas dans le fichier : `from` ne serait pas
        // ce que le champ contient.
        if report.heldSettings.contains(key) || report.settingChords[key] != nil
            || KeybindScanner.isHeldModifier(candidate.from, keyPath: candidate.keyPath, declared: false) {
            return .heldModifier
        }
        if report.inertSettings.contains(key) { return .inert }
        // Contexte relevé hors collision avérée : le conflit a été levé, ou
        // le réglage n'écoute que son menu/mode — le rangement n'y touche pas.
        if report.settingContexts[key] != nil, !collisionParties.contains(key) { return .contextResolved }
        if blocks.contains(key) { return .authorBlock }
        if family == nil { return .noFamily }
        return nil
    }

    /// Blocs d'auteur : ≥ 3 réglages d'un même mod dont les noms ne
    /// diffèrent que par leurs nombres (`AbilityBar1Slot1…8`). Les segments
    /// d'index de tableau (`Keys.[0]`) sont ignorés : une liste de trois
    /// touches est **un** réglage, pas un bloc — on compte les noms
    /// distincts.
    static func authorBlockKeys(_ settings: [KeybindScanner.SettingBinding]) -> Set<String> {
        var groups: [String: (names: Set<String>, keys: [String])] = [:]
        for setting in settings {
            let name = settingName(setting.keyPath).joined(separator: ".")
            guard name.contains(where: \.isNumber) else { continue }
            let stem = name.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            let group = setting.modID + "\u{1F}" + stem
            groups[group, default: ([], [])].names.insert(name)
            groups[group, default: ([], [])].keys.append(KeybindScanner.settingKey(setting.modID, setting.keyPath))
        }
        return Set(groups.values.filter { $0.names.count >= 3 }.flatMap(\.keys))
    }

    /// Le chemin sans ses index de tableau (`["Keys", "[0]"]` → `["Keys"]`).
    static func settingName(_ keyPath: [String]) -> [String] {
        keyPath.filter { !($0.hasPrefix("[") && $0.hasSuffix("]")) }
    }

    static func precedes(_ a: (String, [String]), _ b: (String, [String])) -> Bool {
        if a.0 != b.0 { return a.0 < b.0 }
        return a.1.lexicographicallyPrecedes(b.1)
    }
}

// MARK: - Placement

extension KeybindPlanner {

    /// Le refus de placement, porté par `Result` (`UnmovableSetting.Reason`
    /// n'est pas une `Error`).
    struct Refusal: Error { let reason: UnmovableSetting.Reason }

    /// Les touches encore libres pendant la construction du plan (spec §3.4) :
    /// ni contrôle du jeu, ni touche simple tenue par un autre réglage actif,
    /// ni combinaison déjà proposée plus tôt dans ce plan — ni l'alternative
    /// qu'on quitte, ni une autre alternative du même réglage (« H, K » battu
    /// sur H ne doit pas devenir « K, K » : une suppression déguisée).
    struct Pool {
        let gameButtons: Set<String>
        let activeUses: [KeybindCombo: [KeybindScanner.ModUse]]
        var planned = Set<KeybindCombo>()

        /// Libre : jamais `from` lui-même, rien de déjà proposé, et aucun
        /// usage actif — les autres alternatives du réglage comprises.
        func isFree(_ combo: KeybindCombo, for candidate: KeybindPlanner.Candidate) -> Bool {
            combo != candidate.from && !planned.contains(combo) && (activeUses[combo] ?? []).isEmpty
        }

        /// Touche simple de la famille d'abord (mnémonique pour les lettres,
        /// ordre croissant pour chiffres et F) ; famille pleine → corde,
        /// seulement pour un champ qui en porte déjà une ou une liste — un
        /// champ `SButton` simple refuserait la corde et le mod retomberait
        /// en silence sur son défaut.
        mutating func place(_ candidate: KeybindPlanner.Candidate, family: KeybindFamily,
                            chordCapable: Bool) -> Result<KeybindCombo, Refusal> {
            let order = KeybindPlanner.preferredKeys(for: candidate, family: family)
                .filter { !gameButtons.contains($0) }
            for key in order {
                guard let combo = KeybindCombo(buttons: [key]), isFree(combo, for: candidate) else { continue }
                planned.insert(combo)
                return .success(combo)
            }
            guard chordCapable else { return .failure(Refusal(reason: .singleButtonFieldFull)) }
            // Rangement complet : une corde de famille déjà en place est le
            // mieux qu'une famille pleine puisse offrir — la changer contre
            // une autre corde serait du remue-ménage. `from` rendu = rien à faire.
            if candidate.reason == .familyPlacement, KeybindPlanner.isFamilyChord(candidate.from, family) {
                return .success(candidate.from)
            }
            // La corde se pose sur une touche de famille même tenue seule par
            // un autre mod : seule la combinaison exacte doit être libre.
            for modifier in KeybindPlanner.chordModifiers {
                for key in order {
                    guard let combo = KeybindCombo(buttons: [modifier, key]),
                          isFree(combo, for: candidate) else { continue }
                    planned.insert(combo)
                    return .success(combo)
                }
            }
            return .failure(Refusal(reason: .familyFull))
        }
    }

    /// `modificateur de corde + touche de la famille`.
    static func isFamilyChord(_ combo: KeybindCombo, _ family: KeybindFamily) -> Bool {
        combo.buttons.count == 2
            && combo.buttons.contains(where: chordModifiers.contains)
            && combo.buttons.contains(where: keys(of: family).contains)
    }

    /// Les touches de la famille dans l'ordre d'essai. Lettres : initiale
    /// du nom du **mod** d'abord (la moitié des réglages du parc s'appellent
    /// `Open…` — l'initiale du réglage donnerait O partout), puis celle du
    /// réglage, puis les autres lettres des deux noms, puis l'alphabet.
    /// Chiffres et F : ordre croissant.
    static func preferredKeys(for candidate: Candidate, family: KeybindFamily) -> [String] {
        let familyKeys = keys(of: family)
        guard family == .action else { return familyKeys }
        let modLetters = asciiLetters(candidate.modName)
        let settingLetters = asciiLetters(settingName(candidate.keyPath).last ?? "")
        let mnemonic = Array(modLetters.prefix(1)) + Array(settingLetters.prefix(1))
            + modLetters + settingLetters
        var seen = Set<String>()
        return (mnemonic + familyKeys).filter { familyKeys.contains($0) && seen.insert($0).inserted }
    }

    /// Les lettres A–Z d'un nom, en majuscules, dans l'ordre (accents et
    /// chiffres ignorés : ils ne nomment aucune touche de lettre).
    static func asciiLetters(_ name: String) -> [String] {
        name.uppercased().unicodeScalars
            .filter { $0.value >= 65 && $0.value <= 90 }
            .map { String($0) }
    }
}
