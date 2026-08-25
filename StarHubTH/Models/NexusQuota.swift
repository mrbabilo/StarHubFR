import Foundation

/// Ce qu'il reste de quota Nexus, tel que l'API le déclare à chaque réponse.
///
/// Nexus renvoie six en-têtes `x-rl-*` sur **toute** réponse de son API — succès
/// comme 429 —, et l'app les jetait jusqu'ici. Les relever ne coûte aucune
/// requête : c'est de la donnée déjà reçue.
///
/// Type pur (les en-têtes et l'instant sont injectés) pour être testable sans
/// réseau ; `NexusUpdateChecker` en garde la dernière valeur et la persiste.
///
/// ⚠️ L'absence d'en-tête n'est **pas** un quota à zéro : la patte CDN d'un
/// téléchargement ne porte aucun `x-rl-*`. `init?` rend `nil` dans ce cas,
/// pour qu'une réponse muette n'écrase jamais une bonne mesure.
public struct NexusQuota: Codable, Equatable, Sendable {
    /// Une fenêtre de comptage (horaire ou journalière).
    public struct Window: Codable, Equatable, Sendable {
        /// Plafond annoncé. Optionnel : le reste seul suffit à afficher
        /// quelque chose.
        ///
        /// ⚠️ **Il ne dit rien du type de compte.** Mesuré le 2026-08-25 sur le
        /// compte de référence, que `NexusAccountValidator` déclare
        /// `isPremium: false` : 20 000/jour et 2 000/heure. Déduire « premium »
        /// d'un plafond élevé est l'erreur qui a déjà été commise une fois —
        /// seul `/users/validate.json` répond à cette question.
        public let limit: Int?
        /// Ce qu'il reste d'appels dans la fenêtre.
        public let remaining: Int
        /// Instant de remise à zéro, quand l'API le donne.
        public let reset: Date?

        public init(limit: Int?, remaining: Int, reset: Date?) {
            self.limit = limit
            self.remaining = remaining
            self.reset = reset
        }
    }

    public let hourly: Window?
    public let daily: Window?
    /// Instant de la réponse qui a fourni ces chiffres.
    public let measuredAt: Date

    public init(hourly: Window?, daily: Window?, measuredAt: Date) {
        self.hourly = hourly
        self.daily = daily
        self.measuredAt = measuredAt
    }

    /// Relève les six en-têtes d'une réponse. Rend `nil` si aucune des deux
    /// fenêtres n'annonce de reste : il n'y a alors rien à retenir, et surtout
    /// rien qui doive remplacer une mesure précédente.
    ///
    /// - Parameter headers: les en-têtes de la réponse ; les clés sont
    ///   comparées sans tenir compte de la casse (`allHeaderFields` est un
    ///   dictionnaire ordinaire, lui, sensible à la casse).
    public init?(headers: [String: String], now: Date = Date()) {
        var lower: [String: String] = [:]
        for (key, value) in headers { lower[key.lowercased()] = value }

        func window(_ prefix: String) -> Window? {
            guard let remaining = Self.parseInt(lower["x-rl-\(prefix)-remaining"]) else { return nil }
            return Window(limit: Self.parseInt(lower["x-rl-\(prefix)-limit"]),
                          remaining: remaining,
                          reset: Self.parseDate(lower["x-rl-\(prefix)-reset"]))
        }

        let hourly = window("hourly")
        let daily = window("daily")
        guard hourly != nil || daily != nil else { return nil }
        self.init(hourly: hourly, daily: daily, measuredAt: now)
    }

    /// La fenêtre journalière **si elle vaut encore**, `nil` si elle s'est
    /// remise à zéro depuis la mesure : « 2 appels restants » mesurés hier
    /// ment après minuit, mieux vaut ne rien affirmer.
    public func dailyIfCurrent(now: Date = Date()) -> Window? {
        Self.ifCurrent(daily, measuredAt: measuredAt, span: 24 * 3600, now: now)
    }

    /// La fenêtre horaire si elle vaut encore. **Elle périme la première, et
    /// seule** : l'app n'appelle l'API Nexus qu'à la demande, une heure sans
    /// consulter de fiche de mod est l'état normal de ce réglage. Périmer le
    /// compte journalier avec elle masquerait un chiffre encore exact jusqu'à
    /// minuit — soit, en pratique, presque tout le temps.
    public func hourlyIfCurrent(now: Date = Date()) -> Window? {
        Self.ifCurrent(hourly, measuredAt: measuredAt, span: 3600, now: now)
    }

    /// `true` quand plus aucun chiffre ne veut dire quoi que ce soit.
    public func isStale(now: Date = Date()) -> Bool {
        dailyIfCurrent(now: now) == nil && hourlyIfCurrent(now: now) == nil
    }

    /// Sans instant de remise à zéro (en-tête absent ou illisible), on retombe
    /// sur la durée nominale de la fenêtre depuis la mesure.
    private static func ifCurrent(_ window: Window?, measuredAt: Date,
                                  span: TimeInterval, now: Date) -> Window? {
        guard let window else { return nil }
        if let reset = window.reset { return now >= reset ? nil : window }
        return now >= measuredAt.addingTimeInterval(span) ? nil : window
    }

    private static func parseInt(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Nexus date ses remises à zéro en `2026-08-24 19:00:00 +0000` (vérifié
    /// sur une réponse réelle), mais ses propres documents ont montré de l'ISO
    /// 8601 par le passé : les deux sont acceptés, et une date illisible laisse
    /// simplement le champ vide plutôt que de faire tomber toute la mesure.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let date = formatter.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }
}
