import Foundation

/// Coupe l'étalement d'UltraSmooth le temps d'une mesure de la sonde, puis le
/// rétablit (relevé des sources du 2026-11-11, `docs/audit-ultrasmooth-2.8.4.md`).
///
/// UltraSmooth déclenche lui-même les gestionnaires `TimeChanged`
/// (`EnableTimeChangedPacing`, X139) et étale la mise à jour des lieux hors
/// écran (`EnableLocationTimeSlicing`, active par défaut depuis 2.8.x) : la
/// sonde met alors leur coût au compte d'UltraSmooth, ou sur les images
/// suivantes. Pendant une mesure guidée, pilotée ou un benchmark, l'app met les
/// deux options à `false`, et remet le fichier d'origine à la sortie du jeu.
///
/// Trois refus, décidés par l'auteur le 2026-11-11 :
/// - **options expérimentales actives** : UltraSmooth rallume les deux options à
///   chaque chargement, l'écriture ne tiendrait pas — rien n'est touché, la
///   mesure part avec l'avertissement ;
/// - **schéma ancien** (`ConfigSchemaVersion` < 3) : sa migration les rallume au
///   premier chargement de la 2.8.x — même chose ;
/// - à la remise, **un fichier modifié pendant la mesure** n'est pas écrasé :
///   on le dit.
///
/// L'unique état est l'instantané sur disque : il survit à un plantage, et sa
/// présence au lancement de l'app suffit à rétablir. Les contenus ne sont
/// jamais journalisés.
public enum UltraSmoothMeasureSetting {
    public static let uniqueId = "palmhacker13.UltraSmooth"
    static let keys = ["EnableTimeChangedPacing", "EnableLocationTimeSlicing"]
    static let experimentalKey = "EnableExperimentalFeatures"
    static let schemaKey = "ConfigSchemaVersion"
    /// La version de schéma à partir de laquelle UltraSmooth ne rallume plus
    /// ces options au chargement (migrations `< 2` et `< 3` de la 2.8.4).
    static let minimumSchema = 3

    // MARK: - Règle (pure)

    public enum Refusal: Equatable, Sendable {
        case experimental, oldSchema, unreadable
    }

    public enum Plan: Equatable, Sendable {
        /// Les deux options sont déjà coupées.
        case alreadyOff
        case write(String)
        case refused(Refusal)
    }

    /// Le texte à écrire : chaque option à `true` (ou absente — défaut `true`)
    /// passe à `false` ; le reste du fichier est laissé tel quel, à l'octet.
    public static func plan(configText: String) -> Plan {
        guard let parsed = object(configText) else { return .refused(.unreadable) }
        if bool(parsed, experimentalKey) == true { return .refused(.experimental) }
        guard let schema = int(parsed, schemaKey), schema >= minimumSchema else { return .refused(.oldSchema) }
        var text = configText
        var changed = false
        for key in keys where bool(parsed, key) != false {
            guard let next = settingFalse(text, key: key) else { return .refused(.unreadable) }
            text = next
            changed = true
        }
        guard changed else { return .alreadyOff }
        // Le texte écrit doit se relire, avec les deux options coupées et rien
        // d'autre de changé — sinon on n'écrit pas.
        guard let written = object(text), keys.allSatisfy({ bool(written, $0) == false }),
              NSDictionary(dictionary: without(keys, written)).isEqual(to: without(keys, parsed))
        else { return .refused(.unreadable) }
        return .write(text)
    }

    public enum RestorePlan: Equatable, Sendable {
        /// Le fichier est celui qu'on a écrit : remettre l'original.
        case restore
        /// Déjà revenu à l'original (remis à la main, ou jamais écrit).
        case alreadyOriginal
        /// Modifié pendant la mesure : ne rien écraser, le dire.
        case changedMeanwhile
    }

    /// Jugé sur le **contenu**, pas sur les octets : SMAPI relit et réécrit
    /// `config.json` à chaque lancement (`ModHelper.ReadConfig` appelle
    /// `WriteConfig`, « create file or fill in missing fields » ; UltraSmooth
    /// le lit dans `Entry`). Commentaires retirés, clés remises dans l'ordre de
    /// la classe, champs manquants ajoutés : rien de cela n'est une
    /// modification du joueur. Comparés aux octets, ces fichiers passaient pour
    /// « modifiés pendant la mesure », et les deux options restaient coupées.
    public static func restorePlan(current: String?, snapshot: Snapshot) -> RestorePlan {
        if current == snapshot.writtenText { return .restore }
        if current == snapshot.originalText { return .alreadyOriginal }
        guard let current, let found = object(current) else { return .changedMeanwhile }
        if let written = object(snapshot.writtenText), carries(found, written) { return .restore }
        // Original sans l'une des clés (défaut `true`) : la retrouver coupée
        // n'est pas « revenu à l'original ».
        if let original = object(snapshot.originalText), carries(found, original),
           keys.allSatisfy({ bool(original, $0) == false || bool(found, $0) != false }) {
            return .alreadyOriginal
        }
        return .changedMeanwhile
    }

    /// `found` porte-t-il chaque valeur que `expected` déclare ? Clés sans la
    /// casse, comme Newtonsoft ; un champ **en plus** (rempli par SMAPI, ou
    /// ajouté par une version neuve du mod) ne compte pas.
    static func carries(_ found: [String: Any], _ expected: [String: Any]) -> Bool {
        expected.allSatisfy { entry in
            guard let actual = value(found, entry.key) else { return false }
            return (actual as AnyObject).isEqual(entry.value as AnyObject)
        }
    }

    // MARK: - Instantané

    public struct Snapshot: Codable, Equatable, Sendable {
        public let configPath: String
        public let originalText: String
        public let writtenText: String
        /// Dernier lancement de mesure : la remise attend une sortie du jeu
        /// **postérieure** (une série relance vite après une sortie).
        public var lastAppliedAt: Date
    }

    static func snapshotURL(in directory: URL?) -> URL? {
        directory?.appendingPathComponent("ultrasmooth-measure.json")
    }

    static func loadSnapshot(_ url: URL?) -> Snapshot? {
        guard let url, let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(Snapshot.self, from: data) } catch { return nil }
    }

    static func saveSnapshot(_ snapshot: Snapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func removeSnapshot(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) } catch { return }
    }

    // MARK: - Avant une mesure

    public enum ApplyOutcome: Equatable, Sendable {
        /// Sonde ou UltraSmooth absent ou en pause : rien à régler.
        case notNeeded
        case alreadyOff
        case applied
        case refused(Refusal)
        case failed(String)
    }

    /// À appeler juste avant de lancer le jeu pour une mesure. Ne bloque jamais
    /// la mesure : l'appelant dit le refus ou l'échec, puis lance.
    public static func beforeMeasure(mods: [ModItem], gameDir: String, backups: ModConfigBackupManager,
                                     stateDirectory: URL? = AppSupport.directory, now: Date = Date()) -> ApplyOutcome {
        let flat = mods.flattenedMods
        guard flat.contains(where: { $0.isStarHubProbe && $0.isEnabled }),
              let mod = flat.first(where: { $0.isEnabled && $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame }),
              let target = ProbePerformanceActions.configURL(of: mod, gameDir: gameDir),
              let snapshotURL = snapshotURL(in: stateDirectory)
        else { return .notNeeded }
        let current = read(target)
        // Une mesure précédente de la série a déjà réglé ce fichier (que SMAPI
        // a pu réécrire depuis) : ne rien réécrire, seulement dater ce
        // lancement — sinon la sortie suivante tenterait une remise à tort.
        if var snapshot = loadSnapshot(snapshotURL), snapshot.configPath == target.path,
           restorePlan(current: current, snapshot: snapshot) == .restore {
            snapshot.lastAppliedAt = now
            do { try saveSnapshot(snapshot, to: snapshotURL) } catch { return .failed(error.localizedDescription) }
            return .applied
        }
        guard let current else { return .refused(.unreadable) }
        switch plan(configText: current) {
        case .alreadyOff: return .alreadyOff
        case .refused(let refusal): return .refused(refusal)
        case .write(let text):
            do {
                _ = try backups.backUpConfigOncePerDay(for: mod, gameDir: gameDir)
                // L'instantané avant l'écriture : un plantage entre les deux
                // laisse un instantané dont la remise dira « déjà d'origine ».
                try saveSnapshot(Snapshot(configPath: target.path, originalText: current,
                                          writtenText: text, lastAppliedAt: now), to: snapshotURL)
                ModZipInstaller.grantOwnerWriteAccess(in: target.deletingLastPathComponent())
                try text.write(to: target, atomically: true, encoding: .utf8)
            } catch {
                return .failed(error.localizedDescription)
            }
            return .applied
        }
    }

    // MARK: - Après la mesure

    public enum RestoreOutcome: Equatable, Sendable {
        case nothingPending
        /// Jeu encore lancé, ou mesure relancée depuis la sortie : plus tard.
        case notYet
        case restored
        case alreadyOriginal
        case changedMeanwhile
        case failed(String)
    }

    /// À la sortie du jeu (et au lancement de l'app). `exitedAt` : quand le jeu
    /// a été vu fermé ; `nil` au lancement de l'app (aucune mesure en vol).
    public static func afterMeasure(gameRunning: Bool, exitedAt: Date?,
                                    stateDirectory: URL? = AppSupport.directory) -> RestoreOutcome {
        guard let snapshotURL = snapshotURL(in: stateDirectory),
              let snapshot = loadSnapshot(snapshotURL) else { return .nothingPending }
        if gameRunning { return .notYet }
        if let exitedAt, snapshot.lastAppliedAt > exitedAt { return .notYet }
        let target = URL(fileURLWithPath: snapshot.configPath)
        switch restorePlan(current: read(target), snapshot: snapshot) {
        case .alreadyOriginal:
            removeSnapshot(snapshotURL)
            return .alreadyOriginal
        case .changedMeanwhile:
            removeSnapshot(snapshotURL)
            return .changedMeanwhile
        case .restore:
            do {
                ModZipInstaller.grantOwnerWriteAccess(in: target.deletingLastPathComponent())
                try snapshot.originalText.write(to: target, atomically: true, encoding: .utf8)
            } catch {
                // L'instantané reste : la prochaine sortie ou le prochain
                // lancement réessaiera.
                return .failed(error.localizedDescription)
            }
            removeSnapshot(snapshotURL)
            return .restored
        }
    }

    // MARK: - Lecture tolérante

    static func read(_ url: URL) -> String? {
        FileManager.default.contents(atPath: url.path).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Clé sans la casse : Newtonsoft relit `enabletimechangedpacing` comme la
    /// bonne propriété.
    private static func value(_ object: [String: Any], _ key: String) -> Any? {
        object.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func bool(_ object: [String: Any], _ key: String) -> Bool? {
        guard let number = value(object, key) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func int(_ object: [String: Any], _ key: String) -> Int? {
        (value(object, key) as? NSNumber)?.intValue
    }

    private static func without(_ keys: [String], _ object: [String: Any]) -> [String: Any] {
        object.filter { entry in !keys.contains { $0.caseInsensitiveCompare(entry.key) == .orderedSame } }
    }

    /// Remplace `"Clé": true` par `"Clé": false`, ou ajoute la clé en tête de
    /// l'objet si elle manque. `nil` si le texte ne s'y prête pas.
    static func settingFalse(_ text: String, key: String) -> String? {
        let pattern = "(\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*)true\\b"
        let regex: NSRegularExpression
        do { regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) } catch { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let hits = regex.numberOfMatches(in: text, range: range)
        if hits == 1 {
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1false")
        }
        guard hits == 0, let parsed = object(text), value(parsed, key) == nil,
              let brace = text.firstIndex(of: "{") else { return nil }
        let after = text.index(after: brace)
        let separator = text[after...].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("}") ? "" : ","
        return text.replacingCharacters(in: after..<after, with: "\n  \"\(key)\": false\(separator)")
    }
}
