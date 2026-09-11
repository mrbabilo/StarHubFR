import Foundation

/// La comptabilité d'un lot de pré-traduction : ce que chaque ligne ajoute au
/// bilan, et quand la boucle doit s'arrêter.
///
/// Extrait de `runBatch` (ViewModel), où six compteurs, la coupure du service
/// de secours et une sortie de boucle nommée étaient enchevêtrés avec le
/// réseau et l'écriture disque — donc invérifiables. Le type ne connaît ni
/// l'un ni l'autre : l'appelant traduit, écrit, puis **soumet ce qui s'est
/// passé** et reçoit ce qu'il doit faire ensuite (patron `NexusResume`).
public struct TranslationBatchRun {

    /// Où en est le lot — `nil` côté appelant quand aucun lot ne tourne.
    public struct Progress: Equatable, Sendable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    /// Le bilan du lot : les traduites, les clés refusées pour marques
    /// manquantes (**nommées**, l'écran propose de les reprendre à la main),
    /// les erreurs, et les termes du glossaire que le moteur n'a pas repris —
    /// un signalement doux, jamais bloquant.
    public struct Report: Equatable, Sendable {
        public let translated: Int
        public let refusedRowIDs: [String]
        public let errors: Int
        public let softGlossaryIgnored: Int
        /// Combien de ces traductions viennent du secours en ligne — la
        /// provenance doit être visible, jamais devinée.
        public let translatedByFallback: Int
        /// Le secours s'est arrêté en cours de lot, et pourquoi.
        public let fallbackStop: FallbackStop?

        /// Ce qui a coupé le secours en ligne au milieu d'un lot. Trois
        /// causes, trois phrases : un quota épuisé se règle chez DeepL, un
        /// rythme refusé se règle en attendant, une clé refusée se change
        /// dans les réglages.
        public enum FallbackStop: Equatable, Sendable {
            case quotaExhausted
            case rateLimited
            case unauthorized
        }

        public init(translated: Int, refusedRowIDs: [String], errors: Int,
                    softGlossaryIgnored: Int, translatedByFallback: Int,
                    fallbackStop: FallbackStop?) {
            self.translated = translated
            self.refusedRowIDs = refusedRowIDs
            self.errors = errors
            self.softGlossaryIgnored = softGlossaryIgnored
            self.translatedByFallback = translatedByFallback
            self.fallbackStop = fallbackStop
        }
    }

    /// Ce que l'appelant doit faire après avoir soumis une ligne.
    public struct Step: Equatable, Sendable {
        /// Couper le secours en ligne pour le reste du lot : marteler un
        /// service qui a déjà dit non ne le fera pas céder, et une clé
        /// refusée le sera autant à la clé suivante.
        public let dropsFallback: Bool
        /// Sortir de la boucle : plus rien ne peut traduire. Continuer
        /// collectionnerait une erreur par clé restante, là où le bilan a
        /// déjà dit ce qui s'est passé et ce qu'il reste à faire.
        public let stopsLoop: Bool
    }

    private let hasLocalEngine: Bool
    private var translated = 0
    private var refused: [String] = []
    private var errors = 0
    private var softIgnored = 0
    private var translatedByFallback = 0
    private var fallbackStop: Report.FallbackStop?

    /// - Parameter hasLocalEngine: vrai quand une IA locale est réglée. C'est
    ///   elle qui décide si le lot survit à la coupure du secours en ligne.
    public init(hasLocalEngine: Bool) {
        self.hasLocalEngine = hasLocalEngine
    }

    /// Soumet le sort d'une ligne.
    ///
    /// - Parameters:
    ///   - writeSucceeded: le fichier a bien reçu la traduction. Une
    ///     proposition non écrite est une erreur, et ne nourrit aucun autre
    ///     compteur — le signalement du glossaire porte sur ce qui est *sur
    ///     le disque*, pas sur ce que le moteur a dit.
    ///   - cancelled: le lot a été annulé. `data(for:)` honore l'annulation,
    ///     donc la requête en vol échoue **par notre fait** : la compter
    ///     rapporterait une erreur fantôme à chaque arrêt demandé.
    @discardableResult
    public mutating func record(rowID: String,
                                outcome: TranslationEngine.Outcome,
                                glossaryMatches: [GlossaryEntry],
                                writeSucceeded: Bool,
                                cancelled: Bool) -> Step {
        switch outcome {
        case .translated(let proposal, let by):
            guard writeSucceeded else {
                errors += 1
                return Step(dropsFallback: false, stopsLoop: false)
            }
            translated += 1
            if by == .fallback { translatedByFallback += 1 }
            softIgnored += glossaryMatches.filter { !proposal.contains($0.fr) }.count

        case .refusedTokens:
            refused.append(rowID)

        case .endpointError:
            if !cancelled { errors += 1 }

        case .quotaExhausted, .fallbackRateLimited, .fallbackUnauthorized:
            switch outcome {
            case .quotaExhausted: fallbackStop = .quotaExhausted
            case .fallbackRateLimited: fallbackStop = .rateLimited
            case .fallbackUnauthorized: fallbackStop = .unauthorized
            // Inatteignable : le `case` extérieur ne laisse passer que les
            // trois ci-dessus. Nommé plutôt que replié sur un `default`, qui
            // annoncerait un jour une clé refusée pour un cas ajouté
            // ailleurs — mauvais message, mauvais remède.
            case .translated, .refusedTokens, .endpointError: break
            }
            errors += 1
            return Step(dropsFallback: true, stopsLoop: !hasLocalEngine)
        }
        return Step(dropsFallback: false, stopsLoop: false)
    }

    public var report: Report {
        Report(translated: translated, refusedRowIDs: refused, errors: errors,
               softGlossaryIgnored: softIgnored,
               translatedByFallback: translatedByFallback,
               fallbackStop: fallbackStop)
    }

    /// La ligne de journal du lot. Le journal de l'app n'est pas localisé :
    /// le texte EST la décision.
    public func summary(mod: String) -> String {
        "Lot \(mod) : \(translated) traduites (dont \(translatedByFallback) "
            + "par le secours en ligne), \(refused.count) refusées (marques manquantes), "
            + "\(errors) erreurs, \(softIgnored) termes glossaire ignorés"
            + (fallbackStop.map { ", secours coupé : \($0)" } ?? "")
    }
}
