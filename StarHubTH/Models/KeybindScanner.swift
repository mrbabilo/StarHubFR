import Foundation

/// Les contrôles du jeu et leurs boutons **par défaut**, figés du relevé IL
/// du constructeur `StardewValley.Options` (tâche 0, step 3). Ce ne sont pas
/// les contrôles réels de l'utilisateur — la réserve est affichée à l'écran.
public enum GameControlDefaults {
    public struct GameControl: Equatable, Sendable {
        public let name: String
        public let buttons: [String]
        public init(name: String, buttons: [String]) { self.name = name; self.buttons = buttons }
    }
    /// ── coller le relevé de la tâche 0 (step 3) : un `GameControl` par
    /// champ `InputButton[]` du constructeur d'`Options`, tous. ──
    public static let controls: [GameControl] = [
        GameControl(name: "moveUpButton", buttons: ["W"]),
        GameControl(name: "moveDownButton", buttons: ["S"]),
        GameControl(name: "moveLeftButton", buttons: ["A"]),
        GameControl(name: "moveRightButton", buttons: ["D"]),
        GameControl(name: "actionButton", buttons: ["X", "MouseRight"]),
        GameControl(name: "cancelButton", buttons: ["V"]),
        GameControl(name: "useToolButton", buttons: ["C", "MouseLeft"]),
        GameControl(name: "menuButton", buttons: ["E", "Escape"]),
        GameControl(name: "runButton", buttons: ["LeftShift"]),
        GameControl(name: "chatButton", buttons: ["T", "OemQuestion"]),
        GameControl(name: "mapButton", buttons: ["M"]),
        GameControl(name: "journalButton", buttons: ["F"]),
        GameControl(name: "inventorySlot1", buttons: ["D1"]),
        GameControl(name: "inventorySlot2", buttons: ["D2"]),
        GameControl(name: "inventorySlot3", buttons: ["D3"]),
        GameControl(name: "inventorySlot4", buttons: ["D4"]),
        GameControl(name: "inventorySlot5", buttons: ["D5"]),
        GameControl(name: "inventorySlot6", buttons: ["D6"]),
        GameControl(name: "inventorySlot7", buttons: ["D7"]),
        GameControl(name: "inventorySlot8", buttons: ["D8"]),
        GameControl(name: "inventorySlot9", buttons: ["D9"]),
        GameControl(name: "inventorySlot10", buttons: ["D0"]),
        GameControl(name: "inventorySlot11", buttons: ["OemMinus"]),
        GameControl(name: "inventorySlot12", buttons: ["OemPlus"]),
        GameControl(name: "toolbarSwap", buttons: ["Tab"]),
        GameControl(name: "emoteButton", buttons: ["Y"]),
    ]
}

public enum KeybindScanner {

    public struct ModScan: Sendable {
        public let id: String
        public let name: String
        public let isActive: Bool
        public let tree: ConfigJSONTree.Value
        public init(id: String, name: String, isActive: Bool, tree: ConfigJSONTree.Value) {
            self.id = id; self.name = name; self.isActive = isActive; self.tree = tree
        }
    }

    public enum Decision: Equatable, Sendable {
        case keybind([KeybindCombo])
        case unrecognized(raw: String)
        case notKeybind
    }

    public struct ModUse: Hashable, Sendable {
        public let modID: String
        public let modName: String
        public let keyPath: [String]
        /// C4-T7 — l'état du mod au moment du scan. Les liaisons d'un mod
        /// en pause ne tirent pas au jeu : leurs collisions sont **latentes**
        /// (elles n'apparaîtraient qu'à la réactivation) et ne comptent pas
        /// dans les problèmes avérés. Défaut `true` : les sites qui parlent
        /// du cas actif n'ont pas à le répéter.
        public let isActive: Bool

        public init(modID: String, modName: String, keyPath: [String], isActive: Bool = true) {
            self.modID = modID; self.modName = modName
            self.keyPath = keyPath; self.isActive = isActive
        }
    }

    /// Défaut 2 (tâche 6) : un mod qui lie la même touche dans deux réglages
    /// différents produit deux `ModUse` distincts côté données — légitime,
    /// les `keyPath` diffèrent — mais l'écran ne doit le montrer qu'une fois
    /// par ligne, ses chemins réunis. Le regroupement est une logique pure,
    /// elle vit ici pour rester sous `swift test`, pas dans la vue.
    public struct GroupedUse: Identifiable, Equatable, Sendable {
        public let modID: String
        public let modName: String
        public let keyPaths: [[String]]
        /// C4-T7 — pour que la vue puisse marquer « (en pause) » dans les
        /// collisions latentes : un mod a un seul état, l'identité tient.
        public let isActive: Bool
        public var id: String { modID }
    }

    /// Fusionne les usages d'un même `modID` en une entrée, ses `keyPath`
    /// réunis dans l'ordre de première rencontre. Deux mods distincts
    /// restent deux entrées, dans l'ordre où `uses` les présente (déjà
    /// alphabétique par nom depuis `report`).
    public static func groupedUses(_ uses: [ModUse]) -> [GroupedUse] {
        var order: [String] = []
        var namesByID: [String: String] = [:]
        var pathsByID: [String: [[String]]] = [:]
        var activeByID: [String: Bool] = [:]
        for use in uses {
            if pathsByID[use.modID] == nil {
                order.append(use.modID)
                pathsByID[use.modID] = []
            }
            pathsByID[use.modID]?.append(use.keyPath)
            namesByID[use.modID] = use.modName
            activeByID[use.modID] = use.isActive
        }
        return order.map { id in
            GroupedUse(modID: id, modName: namesByID[id] ?? "",
                       keyPaths: pathsByID[id] ?? [],
                       isActive: activeByID[id] ?? true)
        }
    }
    public struct KeybindCollision: Equatable, Sendable {
        public let combo: KeybindCombo
        public let uses: [ModUse]
    }
    /// C4-T7 — le co-déclenchement au geste long (spec §12) : tenir la
    /// combinaison longue fait aussi tirer la courte qu'elle contient. `A`
    /// est le sous-ensemble strict, `B` la combinaison qui le contient ;
    /// `uses` réunit les liaisons des deux. Deux combinaisons d'un **même**
    /// mod n'y entrent jamais (règle §3 : un mod ne se conflitte pas
    /// lui-même) — il faut au moins deux mods dans l'union.
    public struct SubsetOverlap: Hashable, Sendable {
        public let subset: KeybindCombo
        public let superset: KeybindCombo
        public let uses: [ModUse]
    }
    public struct GameControlConflict: Equatable, Sendable {
        public let control: GameControlDefaults.GameControl
        public let uses: [ModUse]
    }
    public struct UnrecognizedKeybind: Hashable, Sendable {
        public let modID: String, modName: String, keyPath: [String], raw: String
    }
    /// Tâche 9 — ce qu'un mod précis subit d'un rapport déjà calculé :
    /// les mêmes lignes que le rapport global, **moins lui-même**. La
    /// sélection est une logique pure, elle vit ici pour rester sous
    /// `swift test` — la fiche qui l'affiche n'a aucune couverture.
    public struct ModKeybindConflicts: Equatable, Sendable {
        /// Collisions où ce mod est partie prenante ; `uses` ne retient
        /// que les **autres** mods — la fiche parle de CE mod, il ne se
        /// cite pas dans sa propre liste.
        public let collisions: [KeybindCollision]
        /// Conflits avec un contrôle par défaut du jeu qui le touchent ;
        /// `uses` réduit pareillement aux autres.
        public let gameConflicts: [GameControlConflict]
        public var isEmpty: Bool { collisions.isEmpty && gameConflicts.isEmpty }
    }
    public struct KeybindReport: Equatable, Sendable {
        /// Collisions **clavier** avérées (mods actifs). Les collisions
        /// manette sont à part depuis C4-T7 — catégorie visible.
        public var collisions: [KeybindCollision]
        /// C4-T7 — collisions sur au moins un bouton manette. Réelles et
        /// avérées, mais pas de la même famille : celui qui n'a pas de
        /// manette branchée n'y est pas sujet.
        public var gamepadCollisions: [KeybindCollision]
        /// C4-T7 — co-déclenchements au geste long (sous-ensemble strict),
        /// entre mods actifs. Signalés, mais **pas** des problèmes avérés
        /// au sens du badge : un sous-ensemble se supporte souvent des
        /// années sans que personne ne le remarque — la spec §12 disait de
        /// les signaler « si la mesure montre qu'ils pèsent », ils sont donc
        /// visibles sans peser sur le vert.
        public var subsetOverlaps: [SubsetOverlap]
        /// C4-T7 — les collisions qui n'existeraient **que si** les mods en
        /// pause étaient actifs : au moins un mod en pause, pas deux mods
        /// actifs (celle-là est déjà dans `collisions` ou
        /// `gamepadCollisions`). `uses` porte tout le monde, l'état de chacun
        /// lisible sur `ModUse.isActive`.
        public var latentCollisions: [KeybindCollision]
        public var gameConflicts: [GameControlConflict]
        public var unrecognized: [UnrecognizedKeybind]
        public var scannedMods: Int
        /// Les feuilles qui **lient** au moins une combinaison. Une feuille à
        /// `None` n'en est pas une : elle n'entre dans aucun index — ni
        /// collision, ni conflit jeu — et l'annoncer comme un raccourci
        /// gonflait le seul chiffre que l'écran donne. Mesuré sur le parc :
        /// 18 des 76 feuilles comptées ne liaient rien (CJBCheatsMenu en a 5,
        /// UIInfoSuite2Alt 7), soit 76 annoncés pour 58 liaisons.
        public var keybindCount: Int
        public var pausedIgnored: Int
        /// R4 : noms des mods dont au moins une forme de chemin a été
        /// écartée comme catalogue (§ `catalogThreshold`). Une exclusion
        /// muette est un mensonge par omission — la vue doit pouvoir le
        /// dire.
        public var catalogModsIgnored: [String]

        /// Problèmes avérés : collisions clavier et manette entre mods actifs
        /// plus conflits avec un contrôle du jeu. Les « non reconnus » n'y
        /// entrent pas — ce sont des valeurs illisibles, pas des problèmes
        /// avérés (tâche 7, pour la pastille de la barre latérale et de
        /// l'accueil) ; les co-déclenchements et les collisions latentes non
        /// plus, délibérément (C4-T7).
        public var problemCount: Int {
            collisions.count + gamepadCollisions.count + gameConflicts.count
        }

        /// Tâche 9 — « ce que ce modID subit » : les collisions et
        /// conflits jeu où le mod apparaît, ses propres usages retirés de
        /// chaque liste. Un mod étranger à tout conflit rend `isEmpty` ;
        /// un mod absent du rapport (jamais scanné) pareil — les deux cas
        /// se valent pour la fiche, qui reste muette.
        public func conflicts(affecting modID: String) -> ModKeybindConflicts {
            let allCollisions = collisions + gamepadCollisions
            return ModKeybindConflicts(
                collisions: allCollisions
                    .filter { $0.uses.contains { $0.modID == modID } }
                    .map { KeybindCollision(combo: $0.combo,
                                            uses: $0.uses.filter { $0.modID != modID }) },
                gameConflicts: gameConflicts
                    .filter { $0.uses.contains { $0.modID == modID } }
                    .map { GameControlConflict(control: $0.control,
                                               uses: $0.uses.filter { $0.modID != modID }) })
        }
    }

    /// R1/R2/R3 — la règle gelée par la mesure (spec §6 + son constat) :
    /// sans indice de nom, une origine numérique (entier JSON, chaîne
    /// numérique, liste numérique — le cas CollectionsMod mesuré) n'est
    /// jamais un raccourci ; un champ nommé illisible n'entre dans
    /// `unrecognized` qu'avec un jeton reconnaissable.
    public static func classify(leaf: ConfigEditorModel.Leaf) -> Decision {
        let hinted = leaf.keyPath.joined(separator: ".").range(
            of: "key|bind|shortcut", options: [.regularExpression, .caseInsensitive]) != nil
        let parsed = KeybindParser.parse(leaf.value)
        if hinted {
            if let combos = parsed { return .keybind(combos) }
            return hasRecognizableToken(leaf.value)
                ? .unrecognized(raw: literal(of: leaf.value)) : .notKeybind
        }
        guard let combos = parsed, !isNumericOrigin(leaf.value),
              combos.contains(where: \.isDistinctive) else { return .notKeybind }
        return .keybind(combos)
    }

    /// Origine numérique (règle gelée) : entier JSON, chaîne numérique,
    /// ou liste dont tous les éléments le sont.
    static func isNumericOrigin(_ value: ConfigJSONTree.Value) -> Bool {
        switch value {
        case .number: return true
        case .string(let s):
            return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        case .array(let items):
            guard !items.isEmpty else { return true }
            return items.allSatisfy { isNumericOrigin($0) }
        default: return false
        }
    }

    /// Au moins un jeton reconnaissable : nom `SButton` (casse-insensible)
    /// ou modificateur nu — les typos que le `TryParse` de SMAPI rejette.
    static func hasRecognizableToken(_ value: ConfigJSONTree.Value) -> Bool {
        let texts: [String]
        switch value {
        case .string(let s): texts = [s]
        case .array(let items):
            texts = items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        default: return false
        }
        return texts.contains { text in
            text.split(whereSeparator: { "+, ".contains($0) }).contains { token in
                SButtonTable.canonicalName(for: String(token)) != nil
                    || ["shift", "ctrl", "alt"].contains(token.lowercased())
            }
        }
    }

    static func literal(of value: ConfigJSONTree.Value) -> String {
        if case .string(let s) = value { return s }
        if case .number(let lit) = value { return lit }
        return "?"
    }

    /// R4 — le catalogue (constat utilisateur, tâche 6, mesuré sur
    /// `ModShortcutReferenceHub`, ZeroXPatch) : ce mod *documente* les
    /// raccourcis des autres, il n'en lie aucun. Rien ne distingue son
    /// tableau `Shortcuts` d'un vrai raccourci à `classify(leaf:)` — le
    /// chemin porte « key » et « shortcut », chaque lettre parse — donc la
    /// règle ne peut pas vivre dans `classify`, feuille par feuille : il
    /// faut voir combien de combos *distincts* une même forme de chemin
    /// porte, à l'intérieur d'un même mod.
    ///
    /// Mesure sur les 92 mods actifs du parc réel (142 formes) : le maximum
    /// légitime observé est 2 (une alternative dans un seul champ, ex.
    /// `"A, MouseLeft"`) ; le catalogue est à 42. Seuil retenu : 8 — 4× le
    /// maximum légitime, 5× sous le catalogue. Aucun `UniqueID` en dur.
    static let catalogThreshold = 8

    /// La forme d'un `keyPath` : chaque indice de tableau réduit à `[]`
    /// (`["Shortcuts", "[7]", "KeyCombo"]` → `"Shortcuts.[].KeyCombo"`).
    static func pathShape(_ keyPath: [String]) -> String {
        keyPath.map { segment in
            segment.range(of: #"^\[\d+\]$"#, options: .regularExpression) != nil ? "[]" : segment
        }.joined(separator: ".")
    }

    public static func report(mods: [ModScan]) -> KeybindReport {
        var index: [KeybindCombo: [ModUse]] = [:]          // mods actifs
        var pausedIndex: [KeybindCombo: [ModUse]] = [:]    // mods en pause (C4-T7)
        var gameIndex: [String: [ModUse]] = [:]      // nom de contrôle → usages
        var unrecognized: [UnrecognizedKeybind] = []
        var keybindCount = 0
        var pausedIgnored = 0
        // Ronde de correction 1 : un `(id, name)` par mod écarté, jamais un
        // `Set<String>` de noms — ce parc a de vrais homonymes (Swim
        // installé deux fois) ; dédupliquer sur le nom effacerait un des
        // deux mods du constat alors qu'ils sont deux dossiers distincts.
        var catalogMods: [(id: String, name: String)] = []
        // Un même littéral peut rendre deux fois la même combinaison
        // (« F8, F8 ») : le même usage n'entre qu'une fois dans son seau,
        // sinon la vue reçoit deux lignes de même identité.
        func add(_ use: ModUse, to bucket: inout [ModUse]) {
            guard !bucket.contains(use) else { return }
            bucket.append(use)
        }

        // C4-T7 — la classification (et la règle du catalogue R4) court pour
        // TOUS les mods, actifs et en pause : une quarantaine de liaisons d'un
        // mod en pause écarté comme catalogue ne doit pas revenir en
        // collisions latentes.
        for mod in mods {
            // Passe 1 : classer les feuilles du mod, sans encore les indexer
            // — la règle du catalogue (R4) a besoin de voir le mod entier
            // avant de savoir quelles feuilles compteront.
            var keybindLeaves: [(keyPath: [String], combos: [KeybindCombo])] = []
            // Rangées à part, pas encore dans le seau global `unrecognized` :
            // une feuille qui ne parse pas sous une forme qui se révèle être
            // un catalogue (passe 2) n'a pas plus sa place dans « non
            // reconnus » qu'une feuille qui parse — le mod entier, sous cette
            // forme, est déjà déclaré écarté (ronde de correction 1).
            var unrecognizedLeaves: [(keyPath: [String], raw: String)] = []
            for leaf in ConfigEditorModel.leaves(of: mod.tree) {
                switch classify(leaf: leaf) {
                case .keybind(let combos):
                    keybindLeaves.append((leaf.keyPath, combos))
                case .unrecognized(let raw):
                    unrecognizedLeaves.append((leaf.keyPath, raw))
                case .notKeybind:
                    break
                }
            }

            // Passe 2 : par forme de chemin, compter les combos distincts —
            // au-delà du seuil, la forme est un catalogue (R4), elle ne
            // produit aucune liaison. Compté par mod, jamais cumulé entre
            // mods : deux mods qui déclarent chacun peu de touches sous une
            // forme de même nom ne s'additionnent pas.
            var combosByShape: [String: Set<KeybindCombo>] = [:]
            for (keyPath, combos) in keybindLeaves {
                let shape = pathShape(keyPath)
                for combo in combos where !combo.isEmpty {
                    combosByShape[shape, default: []].insert(combo)
                }
            }
            let catalogShapes = Set(
                combosByShape.filter { $0.value.count > catalogThreshold }.map(\.key))
            if !catalogShapes.isEmpty {
                catalogMods.append((mod.id, mod.name))
            }

            for (keyPath, combos) in keybindLeaves {
                guard !catalogShapes.contains(pathShape(keyPath)) else { continue }
                // Compté **si ça lie** : voir le doc de `keybindCount`. La
                // boucle qui suit saute déjà les combinaisons vides, ce
                // compteur était la seule ligne à les prendre pour des
                // raccourcis. Les mods en pause ne gonflent pas ce chiffre —
                // ils ne lient pas au jeu.
                if mod.isActive, combos.contains(where: { !$0.isEmpty }) { keybindCount += 1 }
                for combo in combos where !combo.isEmpty {
                    let use = ModUse(modID: mod.id, modName: mod.name, keyPath: keyPath,
                                     isActive: mod.isActive)
                    if mod.isActive {
                        add(use, to: &index[combo, default: []])
                        // Conflit jeu : combinaison à bouton unique uniquement.
                        if combo.buttons.count == 1, let button = combo.buttons.first {
                            for control in GameControlDefaults.controls
                            where control.buttons.contains(button) {
                                add(use, to: &gameIndex[control.name, default: []])
                            }
                        }
                    } else {
                        add(use, to: &pausedIndex[combo, default: []])
                    }
                }
            }

            for (keyPath, raw) in unrecognizedLeaves {
                guard !catalogShapes.contains(pathShape(keyPath)) else { continue }
                // Les illisibles d'un mod en pause restent hors du rapport :
                // l'écran parle de l'état qui tire au jeu.
                guard mod.isActive else { continue }
                unrecognized.append(.init(modID: mod.id, modName: mod.name,
                                          keyPath: keyPath, raw: raw))
            }
            if !mod.isActive { pausedIgnored += 1 }
        }

        func bucketCollisions(of buckets: [KeybindCombo: [ModUse]]) -> [KeybindCollision] {
            buckets
                .filter { Set($0.value.map(\.modID)).count >= 2 }
                // Départage par `modID` (ronde finale) : le sort de Swift n'est
                // pas garanti stable, et ce parc a de vrais homonymes (Swim
                // installé deux fois) — le nom seul ne définit pas un ordre
                // total, deux rapports du même lot pouvaient différer.
                .map { KeybindCollision(combo: $0.key, uses: $0.value.sorted { ($0.modName, $0.modID) < ($1.modName, $1.modID) }) }
                .sorted { $0.combo < $1.combo }
        }

        let allCollisions = bucketCollisions(of: index)
        // C4-T7 — la famille manette a sa catégorie : `LeftStick` partagé par
        // deux frameworks ValleyBonds (mesuré le 2026-09-04) n'est pas une
        // collision clavier.
        let gamepadCollisions = allCollisions.filter { $0.combo.isGamepad }
        let collisions = allCollisions.filter { !$0.combo.isGamepad }

        // C4-T7 — le latent : le seau complet (actifs + pause) minus les
        // seaux déjà avérés. Il faut au moins un mod en pause, au moins deux
        // mods distincts, et pas deux mods actifs — ce dernier cas est déjà
        // compté ci-dessus.
        var latentBuckets: [KeybindCombo: [ModUse]] = [:]
        for (combo, uses) in index {
            guard Set(uses.map(\.modID)).count < 2 else { continue }
            if let paused = pausedIndex[combo] {
                latentBuckets[combo] = uses + paused
            }
        }
        for (combo, paused) in pausedIndex
        where Set(paused.map(\.modID)).count >= 2 {
            latentBuckets[combo] = (latentBuckets[combo] ?? []) + paused
        }
        let latentCollisions = bucketCollisions(of: latentBuckets)

        // C4-T7 — les co-déclenchements (sous-ensembles stricts) entre mods
        // actifs, jamais au sein d'un même mod (§3). Le lot est petit
        // (58 liaisons mesurées sur le parc réel, quelques dizaines de
        // combos) : le produit cartésien est à l'aise.
        var subsetOverlaps: [SubsetOverlap] = []
        let activeCombos = index.keys.filter { !$0.isEmpty }.sorted()
        for (aPosition, a) in activeCombos.enumerated() {
            for b in activeCombos[aPosition...] where a.isStrictSubset(of: b) {
                let uses = (index[a] ?? []) + (index[b] ?? [])
                guard Set(uses.map(\.modID)).count >= 2 else { continue }
                subsetOverlaps.append(SubsetOverlap(subset: a, superset: b,
                                                    uses: uses.sorted { ($0.modName, $0.modID) < ($1.modName, $1.modID) }))
            }
        }

        let gameConflicts = gameIndex
            .map { name, uses in
                GameControlConflict(
                    control: GameControlDefaults.controls.first { $0.name == name }!,
                    uses: uses.sorted { ($0.modName, $0.modID) < ($1.modName, $1.modID) })
            }
            .sorted { $0.control.name < $1.control.name }
        unrecognized.sort { ($0.modName, $0.keyPath.joined()) < ($1.modName, $1.keyPath.joined()) }

        let catalogModsIgnored = catalogMods
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            .map(\.name)

        return KeybindReport(collisions: collisions,
                             gamepadCollisions: gamepadCollisions,
                             subsetOverlaps: subsetOverlaps.sorted {
                                 ($0.subset, $0.superset) < ($1.subset, $1.superset)
                             },
                             latentCollisions: latentCollisions,
                             gameConflicts: gameConflicts,
                             unrecognized: unrecognized,
                             scannedMods: mods.filter(\.isActive).count,
                             keybindCount: keybindCount, pausedIgnored: pausedIgnored,
                             catalogModsIgnored: catalogModsIgnored)
    }
}
