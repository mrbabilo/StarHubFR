import Foundation

/// `gmcm-options.json` de la sonde (D4-T7) : les options que chaque mod
/// déclare à Generic Mod Config Menu en jeu, avec la copie de son
/// `config.json` prise au même instant (sonde ≥ 0.4.11).
///
/// Une capture plus ancienne n'a pas de copie : elle ne rend rien, parce que
/// le rapprochement option → clé ne se vérifie que sur la copie. Contre le
/// fichier actuel, une valeur éditée depuis la capture passerait pour un
/// rapprochement faux.
public struct GmcmCapture: Sendable {
    struct RawOption: Decodable, Sendable {
        let kind: String
        let name: String?
        let tooltip: String?
        let valueType: String?
        let value: String?
        let min: String?
        let max: String?
        let interval: String?
        let choices: [String]?
        let choiceLabels: [String]?
        let accessPath: [String]?
        let closureStrings: [String]?
    }

    struct RawMod: Decodable, Sendable {
        let uniqueID: String
        let version: String?
        let configSnapshot: String?
        let options: [RawOption]
    }

    private struct RawCapture: Decodable {
        let capturedAt: String
        let language: String?
        let mods: [RawMod]
    }

    public let capturedAt: String
    /// La langue du jeu à la capture (`fr`) : celle des libellés GMCM.
    public let language: String?
    /// Minuscules → mod ; le premier gagne si SMAPI en listait deux.
    private let modsById: [String: RawMod]

    public static func decode(_ data: Data) -> GmcmCapture? {
        do {
            let raw = try ProbeJSON.decoder().decode(RawCapture.self, from: data)
            var byId: [String: RawMod] = [:]
            for mod in raw.mods where byId[mod.uniqueID.lowercased()] == nil {
                byId[mod.uniqueID.lowercased()] = mod
            }
            return GmcmCapture(capturedAt: raw.capturedAt, language: raw.language, modsById: byId)
        } catch {
            return nil
        }
    }

    private init(capturedAt: String, language: String?, modsById: [String: RawMod]) {
        self.capturedAt = capturedAt
        self.language = language
        self.modsById = modsById
    }

    /// Les options vérifiées du mod, ou `nil` : mod absent de la capture,
    /// capture sans copie, copie illisible, ou version installée différente
    /// de la version capturée — une mise à jour peut avoir déplacé une clé.
    public func options(forMod uniqueId: String, installedVersion: String) -> GmcmModOptions? {
        guard let mod = modsById[uniqueId.lowercased()],
              let captured = mod.version,
              NexusUpdateChecker.compare(captured, installedVersion) == .orderedSame,
              let snapshot = mod.configSnapshot,
              let tree = ConfigJSONTree.parse(snapshot) else { return nil }
        return GmcmModOptions(language: language, options: mod.options, snapshot: tree)
    }
}

/// Ce que GMCM dit des clés d'un mod, indexé par chemin complet de clé
/// (segments en minuscules). Construit une fois par ouverture de l'éditeur.
public struct GmcmModOptions: Equatable, Sendable {
    public struct Bounds: Hashable, Sendable {
        public let min: Double
        public let max: Double
        /// `nil` : pas absent ou invalide, curseur continu.
        public let step: Double?

        public init(min: Double, max: Double, step: Double?) {
            self.min = min
            self.max = max
            self.step = step
        }

        public func contains(_ value: Double) -> Bool { value >= min && value <= max }

        /// La valeur que le curseur écrit : ramenée sur la grille du pas
        /// depuis `min`, puis au nombre de décimales du pas (sans pas : 1 pour
        /// un entier, 2 décimales sinon), puis dans les bornes. Sans cet
        /// arrondi, un pas de 0,05 écrit `0.15000000000000002`.
        public func snapped(_ value: Double, integer: Bool) -> Double {
            let step = self.step ?? (integer ? 1 : nil)
            var result = Swift.min(Swift.max(value, min), max)
            if let step {
                result = min + ((result - min) / step).rounded() * step
            }
            let decimals = integer ? 0 : (step.map(Self.decimals(of:)) ?? 2)
            let scale = pow(10, Double(decimals))
            result = (result * scale).rounded() / scale
            return Swift.min(Swift.max(result, min), max)
        }

        /// Décimales du pas tel que `String` l'écrit : `0.05` → 2, `512.0` → 0.
        private static func decimals(of step: Double) -> Int {
            let text = String(step)
            guard !text.contains("e"), let dot = text.firstIndex(of: ".") else { return 10 }
            let fraction = text[text.index(after: dot)...]
            return fraction == "0" ? 0 : fraction.count
        }
    }

    public struct Entry: Equatable, Sendable {
        public let label: String?
        public let tooltip: String?
        public let bounds: Bounds?
        public let choices: [String]?
        /// Valeur en minuscules → texte que GMCM affiche pour elle.
        public let choiceLabels: [String: String]
    }

    private struct Claim {
        let label: String?
        let tooltip: String?
        let bounds: Bounds?
        let choices: [String]?
        let choiceLabels: [String: String]
    }

    public let language: String?
    private let entries: [[String]: Entry]

    public var count: Int { entries.count }

    public func entry(for keyPath: [String]) -> Entry? {
        entries[keyPath.map { $0.lowercased() }]
    }

    init(language: String?, options: [GmcmCapture.RawOption], snapshot: ConfigJSONTree.Value) {
        self.language = language
        var order: [[String]] = []
        var claims: [[String]: [Claim]] = [:]
        for option in options where option.valueType != nil {
            guard let (path, leaf) = Self.uniqueLeaf(of: option, in: snapshot),
                  Self.agrees(leaf, option.value) else { continue }
            let key = path.map { $0.lowercased() }
            if claims[key] == nil { order.append(key) }
            let choice = Self.choices(of: option, leaf: leaf)
            claims[key, default: []].append(Claim(label: Self.nonEmpty(option.name),
                                                  tooltip: Self.nonEmpty(option.tooltip),
                                                  bounds: Self.bounds(of: option, leaf: leaf),
                                                  choices: choice?.values,
                                                  choiceLabels: choice?.labels ?? [:]))
        }
        var merged: [[String]: Entry] = [:]
        for key in order {
            guard let list = claims[key], let first = list.first else { continue }
            // Collision (doublons de page, 9 clés du parc) : le premier
            // libellé ; bornes et choix seulement s'ils concordent partout.
            let bounds = list.compactMap(\.bounds)
            let choices = list.compactMap(\.choices)
            let choiceOwner = list.first { $0.choices != nil }
            merged[key] = Entry(
                label: list.lazy.compactMap(\.label).first,
                tooltip: list.lazy.compactMap(\.tooltip).first,
                bounds: Set(bounds).count == 1 ? bounds.first : nil,
                choices: Set(choices).count == 1 ? choices.first : nil,
                choiceLabels: Set(choices).count == 1 ? (choiceOwner ?? first).choiceLabels : [:])
        }
        entries = merged
    }

    /// La feuille que l'option lit : une sous-suite contiguë de son
    /// `AccessPath`, à défaut une chaîne capturée par sa fermeture (clé de
    /// premier niveau). Exactement un candidat, sinon `nil`.
    private static func uniqueLeaf(of option: GmcmCapture.RawOption,
                                   in snapshot: ConfigJSONTree.Value) -> ([String], ConfigJSONTree.Value)? {
        var found: [[String]: ([String], ConfigJSONTree.Value)] = [:]
        let path = option.accessPath ?? []
        for start in path.indices {
            for end in start..<path.count {
                if let hit = leaf(at: Array(path[start...end]), in: snapshot) {
                    found[hit.0.map { $0.lowercased() }] = hit
                }
            }
        }
        if found.isEmpty {
            for text in option.closureStrings ?? [] {
                if let hit = leaf(at: [text], in: snapshot) { found[hit.0.map { $0.lowercased() }] = hit }
            }
        }
        guard found.count == 1 else { return nil }
        return found.values.first
    }

    /// La feuille au bout du chemin (clés sans la casse), avec le chemin à la
    /// casse du fichier. Un objet ou un tableau n'est pas une feuille.
    private static func leaf(at path: [String],
                             in value: ConfigJSONTree.Value) -> ([String], ConfigJSONTree.Value)? {
        var node = value
        var real: [String] = []
        for key in path {
            guard case .object(let object) = node,
                  let actual = object.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
                  let next = object.members[actual] else { return nil }
            real.append(actual)
            node = next
        }
        switch node {
        case .object, .array: return nil
        case .string, .number, .bool, .null: return (real, node)
        }
    }

    /// La valeur GMCM égale la valeur copiée : sinon le getter lit autre
    /// chose que la clé (inversion, transformation).
    private static func agrees(_ leaf: ConfigJSONTree.Value, _ gmcm: String?) -> Bool {
        guard let gmcm else { return false }
        switch leaf {
        case .bool(let flag):
            return gmcm.lowercased() == (flag ? "true" : "false")
        case .number(let literal):
            guard let file = Double(literal), let shown = Double(gmcm) else { return false }
            return abs(file - shown) <= 1e-6
        case .string(let text):
            return text.lowercased() == gmcm.lowercased()
        case .object, .array, .null:
            return false
        }
    }

    private static func bounds(of option: GmcmCapture.RawOption, leaf: ConfigJSONTree.Value) -> Bounds? {
        guard option.kind == "NumericModOption",
              case .number(let literal) = leaf, let value = Double(literal),
              let min = option.min.flatMap({ Double($0) }), let max = option.max.flatMap({ Double($0) }),
              min < max, value >= min, value <= max else { return nil }
        let step = option.interval.flatMap { Double($0) }.flatMap { $0 > 0 && $0 <= max - min ? $0 : nil }
        return Bounds(min: min, max: max, step: step)
    }

    private static func choices(of option: GmcmCapture.RawOption,
                                leaf: ConfigJSONTree.Value) -> (values: [String], labels: [String: String])? {
        guard option.kind == "ChoiceModOption", let values = option.choices, !values.isEmpty,
              let current = ConfigEditorModel.literalText(of: leaf),
              values.contains(where: { $0.lowercased() == current.lowercased() }) else { return nil }
        var labels: [String: String] = [:]
        if let texts = option.choiceLabels, texts.count == values.count {
            for (value, text) in zip(values, texts) where !text.isEmpty && text != value {
                labels[value.lowercased()] = text
            }
        }
        return (values, labels)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
