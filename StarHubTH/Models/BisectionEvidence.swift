import Foundation

/// Croisement des relevés d'une recherche guidée : ce que le journal a imputé,
/// à quelle fréquence, et **ce qui doit être actif pour que l'erreur
/// apparaisse**. Type pur, sans interface ni entrée-sortie.
public enum BisectionEvidence {
    /// Un relevé d'étape : dossiers actifs, mods incriminés avec un extrait de
    /// leur erreur, et si la panne était encore là.
    public typealias Step = (enabled: Set<String>, blamed: [String: String], stillBroken: Bool)

    public struct LogSuspect: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        /// Étapes où ce mod était incriminé **et** la panne présente.
        public let whenBroken: Int
        /// Étapes où il était incriminé alors que tout allait bien.
        public let whenFine: Int
        /// Nombre total d'étapes en échec, pour situer `whenBroken`.
        public let brokenSteps: Int
        /// Un extrait de l'erreur relevée. Un compte seul ne dit pas *quoi*
        /// s'est mal passé, et c'est cela que l'utilisateur cherche.
        public let sample: String?
        /// Mods présents à **toutes** les étapes où ce mod s'est plaint, et
        /// absents de toutes celles où il tournait sans rien dire. Répond à la
        /// question « qu'est-ce qui fait que l'erreur cesse ? ».
        public let appearsOnlyWith: [String]
        public init(name: String, whenBroken: Int, whenFine: Int, brokenSteps: Int,
                    sample: String?, appearsOnlyWith: [String]) {
            self.name = name; self.whenBroken = whenBroken; self.whenFine = whenFine
            self.brokenSteps = brokenSteps; self.sample = sample
            self.appearsOnlyWith = appearsOnlyWith
        }
    }

    /// Croise les relevés : fréquence d'incrimination, extrait de l'erreur, et
    /// surtout **ce qui doit être actif pour que l'erreur apparaisse**.
    ///
    /// Compter, ne pas intersecter : exiger qu'un mod soit incriminé à *toutes*
    /// les étapes en échec éliminait le cas recherché, une erreur intermittente
    /// n'apparaissant qu'à certaines.
    public static func analyse(_ log: [Step],
                               resolve: (String) -> String?) -> [LogSuspect] {
        let brokenSteps = log.filter(\.stillBroken).count
        var names = Set<String>()
        for step in log { names.formUnion(step.blamed.keys) }

        return names.compactMap { name -> LogSuspect? in
            let complained = log.filter { $0.blamed[name] != nil }
            guard !complained.isEmpty else { return nil }
            let whenBroken = complained.filter(\.stillBroken).count
            guard whenBroken > 0 else { return nil }

            // Étapes où ce mod tournait sans rien dire : c'est leur comparaison
            // avec les précédentes qui désigne le déclencheur.
            let ownFolder = resolve(name)
            let quiet = log.filter { step in
                step.blamed[name] == nil
                    && ownFolder.map { step.enabled.contains($0) } ?? false
            }
            var trigger: [String] = []
            if !quiet.isEmpty, let first = complained.first {
                var always = complained.dropFirst().reduce(first.enabled) { $0.intersection($1.enabled) }
                for q in quiet { always.subtract(q.enabled) }
                if let own = ownFolder { always.remove(own) }
                trigger = always.sorted()
            }

            return LogSuspect(name: name,
                              whenBroken: whenBroken,
                              whenFine: complained.count - whenBroken,
                              brokenSteps: brokenSteps,
                              sample: complained.compactMap { $0.blamed[name] }.first,
                              appearsOnlyWith: trigger)
        }
        .sorted { ($0.whenBroken, -$0.whenFine, $0.name) > ($1.whenBroken, -$1.whenFine, $1.name) }
    }
}
