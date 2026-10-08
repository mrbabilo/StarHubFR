import Foundation

/// La mécanique de la passe de couverture française : **qui** mesurer, et
/// **comment** faire entrer un lot de mesures dans l'état publié.
///
/// Ce ne sont pas les lectures de fichiers — celles-là vivent dans
/// `TranslationCoverage`, déjà en Core et testé. Ce sont les deux décisions qui
/// les encadrent, et qui n'avaient aucun test alors qu'elles commandent ce que
/// la pastille de la liste montre : la passe complète coûte ~13 s de lecture
/// disque sur le parc de référence (424 mods, 159 503 clés), et `mods` est
/// republié à chaque mise en pause, chaque rafraîchissement, chaque activation
/// de profil. Se tromper de lot, c'est refaire ces 13 s pour rien — ou ne
/// jamais mesurer un mod.
///
/// Extrait le 2026-09-10 (point 3 du §5 de `docs/REFACTORING.md`). Le
/// `Task.detached` et les lectures restent au ViewModel : ce qui est ici est
/// **pur**, et se teste sans toucher au disque.
enum FrenchCoveragePass {

    /// Un mod à mesurer.
    ///
    /// Les deux noms sont là et doivent y rester. Le dossier à ouvrir est le
    /// **physique** — un mod en pause vit dans `.X` — tandis que la clé de
    /// l'état publié est le nom **logique**, celui qu'emploient tous les
    /// magasins persistés. Les confondre ferait soit chercher dans le vide,
    /// soit reperdre la mesure à chaque bascule.
    struct Target: Equatable {
        /// La clé de l'état publié (`ModItem.folderName`).
        let key: String
        /// Le nom du dossier sur le disque (`ModItem.physicalFolderName`).
        let physicalFolder: String
    }

    /// Les mods qu'il reste à mesurer, dans l'ordre de la liste.
    ///
    /// Deux règles, et elles ne se recouvrent pas :
    ///
    /// - **Incrémental** : un mod dont la couverture est déjà connue n'est pas
    ///   remesuré. Mettre un mod en pause déplace son dossier sans toucher à
    ///   ses fichiers de traduction — le résultat reste valable.
    ///   `invalidateFrenchCoverage(for:)` sert aux cas où le contenu change.
    /// - **Français seulement** : seuls les mods que le scan dit traduits en
    ///   français sont mesurés. C'est ce qui rend la passe abordable, et c'est
    ///   pourquoi cette détection devait être juste d'abord.
    ///
    /// ⚠️ Cette seconde règle **diffère volontairement** de celle des profils
    /// (`ProfileCoveragePass`, qui prend aussi les mods à `default.json` sans
    /// français). Les unifier ferait surgir une pastille « 0 % » sur les mods
    /// non traduits de la liste — voir la documentation de
    /// `profileTranslationSummaries`.
    ///
    /// - Parameter known: les dossiers déjà mesurés, par nom **logique**.
    static func targets(in mods: [ModItem], known: Set<String>) -> [Target] {
        mods.filter { !known.contains($0.folderName) && $0.languages.contains("fr") }
            .map { Target(key: $0.folderName, physicalFolder: $0.physicalFolderName) }
    }

    /// Le nombre de mesures accumulées avant publication.
    ///
    /// Publier par paquets : un envoi par mod ferait redessiner la liste des
    /// centaines de fois pour rien.
    static let batchSize = 25

    /// L'état que la passe alimente : la couverture connue, et les mods dont
    /// l'anglais est plus récent que le français.
    struct State: Equatable {
        var coverage: [String: TranslationCoverage.Coverage]
        var stale: Set<String>
        /// F6-T1 — le tampon de la dernière mesure posée (ou de la dernière
        /// invalidation) de chaque mod : une mesure plus ancienne n'y entre plus.
        fileprivate(set) var stamps: [String: Int] = [:]
        private(set) var clock = 0

        init(coverage: [String: TranslationCoverage.Coverage] = [:],
             stale: Set<String> = []) {
            self.coverage = coverage
            self.stale = stale
        }

        /// Le tampon d'une mesure qui commence — passe complète ou re-mesure
        /// ciblée. Pris **avant** de lire les fichiers.
        mutating func tick() -> Int {
            clock += 1
            return clock
        }

        /// Oublie un mod dont les fichiers ont pu changer ; un lot lu avant
        /// l'oubli ne le ressuscite pas avec les chiffres d'avant.
        mutating func invalidate(_ key: String) {
            coverage.removeValue(forKey: key)
            stale.remove(key)
            stamps[key] = tick()
        }
    }

    /// Fait entrer un lot de mesures dans l'état.
    ///
    /// - Parameter batch: les couvertures mesurées, par nom logique.
    /// - Parameter stale: ceux du lot dont l'anglais est plus récent.
    /// - Parameter stamp: le tampon (`State.tick()`) pris au début de la
    ///   mesure qui a produit ce lot.
    /// - Returns: le nouvel état, ou `nil` quand rien ne s'applique — lot vide,
    ///   ou entièrement plus ancien que ce qui est posé.
    ///
    /// **F6-T1.** Le `cancel()` d'un recalcul n'interrompt pas une fusion déjà
    /// engagée, et une re-mesure ciblée (traduction enregistrée) ou une
    /// invalidation (mise à jour du mod) peut passer entre la lecture d'un lot
    /// et sa fusion. La garde est **par mod** : seules les entrées plus
    /// anciennes que la dernière posée tombent, le reste du lot s'applique —
    /// une garde par passe jetterait des mesures que rien n'a remplacées.
    static func merging(_ batch: [String: TranslationCoverage.Coverage],
                        stale: Set<String>,
                        into current: State,
                        stamp: Int) -> State? {
        let isFresh = { (key: String) in stamp >= current.stamps[key, default: .min] }
        let fresh = batch.filter { isFresh($0.key) }
        let freshStale = stale.filter(isFresh)
        guard !fresh.isEmpty || !freshStale.isEmpty else { return nil }
        var next = current
        next.coverage.merge(fresh) { _, new in new }
        // Un mod du lot qui n'y est plus signalé a cessé d'être suspect — le
        // retirer d'abord laisse `formUnion` ne faire grandir l'ensemble que de
        // ce que ce lot confirme. Réel depuis la re-mesure ciblée.
        next.stale.subtract(fresh.keys)
        next.stale.formUnion(freshStale)
        for key in Set(fresh.keys).union(freshStale) { next.stamps[key] = stamp }
        return next
    }
}

/// Le même travail, mais pour la page des profils — **et ses règles ne sont pas
/// les mêmes**.
///
/// La différence tient en une ligne et elle est délibérée : un mod qui livre un
/// `default.json` et **aucun** `fr.json` compte ici, alors qu'il est écarté de
/// la passe de la liste. Ce sont même ceux-là qui font tout l'intérêt de cet
/// écran — 8, 28 et 15 sur les trois profils de référence. Les verser dans le
/// magasin commun ferait surgir une pastille « 0 % » sur autant de lignes de la
/// liste des mods, où l'absence d'entrée veut dire « pas encore mesuré ».
///
/// Le grain diffère aussi : la pastille de la liste mesure un dossier de premier
/// niveau entier, quand un profil raisonne par composant — d'où l'indexation par
/// `UniqueID` et non par nom de dossier.
enum ProfileCoveragePass {

    /// Un mod à mesurer pour les profils.
    struct Target: Equatable {
        /// L'`UniqueID` en minuscules — la clé du magasin de couverture des
        /// profils.
        let id: String
        /// Le nom du dossier sur le disque (`.X` pour un mod en pause).
        let physicalFolder: String
    }

    /// Ce qu'il reste à mesurer pour couvrir tous les profils.
    ///
    /// Quatre règles, toutes nécessaires :
    ///
    /// - **Une seule fois par mod**, même s'il apparaît dans dix profils : la
    ///   mesure porte sur le mod, pas sur son appartenance.
    /// - **Incrémental** : ce qui est déjà mesuré n'est pas rouvert.
    /// - **Installé** : un profil peut nommer un mod absent du disque — il n'y a
    ///   rien à y lire.
    /// - **Livrant une source** : `languages` porte `en` dès qu'un
    ///   `default.json` existe. Sur le parc, plus de la moitié des mods n'ont
    ///   aucun dossier `i18n` ; les ouvrir serait le gros du coût pour rien.
    ///
    /// - Parameter known: les `UniqueID` déjà mesurés, en minuscules.
    /// - Returns: les cibles dans l'ordre des profils, puis des mods qu'ils
    ///   nomment — l'ordre de la mesure, donc celui où les résumés se
    ///   complètent.
    static func targets(profiles: [ModProfile], installed: [ModItem],
                        known: Set<String>) -> [Target] {
        // `uniquingKeysWith: first` : deux mods peuvent porter le même
        // `UniqueID` — `X` actif et `.X` en pause sont deux dossiers distincts,
        // cas réel sur le parc. Le premier vu l'emporte, comme partout ailleurs.
        let byId = Dictionary(installed.map { ($0.uniqueId.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })
        var targets: [Target] = []
        var queued = Set<String>()
        for profile in profiles {
            for uniqueId in profile.enabledModIds {
                let key = uniqueId.lowercased()
                guard !key.isEmpty, !known.contains(key),
                      queued.insert(key).inserted, let mod = byId[key],
                      mod.languages.contains("en") || mod.languages.contains("fr")
                else { continue }
                targets.append(Target(id: key, physicalFolder: mod.physicalFolderName))
            }
        }
        return targets
    }
}
