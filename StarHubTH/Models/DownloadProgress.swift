import Foundation

/// Le débit d'un téléchargement, lissé sur une courte fenêtre.
///
/// Ni instantané ni cumulé, et les deux écarts comptent :
/// - **instantané** (deux notifications consécutives), le chiffre saute d'un
///   facteur dix entre deux paquets, et l'estimation de temps avec lui ;
/// - **cumulé depuis le début**, il met des dizaines de secondes à refléter une
///   connexion qui vient de s'effondrer — c'est justement le moment où
///   l'utilisateur regarde.
///
/// L'horloge est fournie par l'appelant : sans quoi rien de tout ceci ne serait
/// testable autrement qu'en dormant.
struct DownloadRateEstimator: Equatable, Sendable {
    /// Un relevé : le nombre total d'octets reçus à cet instant.
    private struct Sample: Equatable, Sendable {
        let time: Date
        let bytes: Int64
    }

    /// La durée sur laquelle le débit est moyenné.
    let window: TimeInterval
    /// L'écart minimal entre le plus ancien et le plus récent relevé sous
    /// lequel on ne dit rien. Un débit calculé sur 30 ms n'est pas une mesure,
    /// c'est un artefact — et il produirait une estimation de temps qui danse
    /// dès la première seconde.
    let minimumSpan: TimeInterval

    private var samples: [Sample] = []

    init(window: TimeInterval = 3, minimumSpan: TimeInterval = 0.5) {
        self.window = window
        self.minimumSpan = minimumSpan
    }

    /// Enregistre le total d'octets reçus à cet instant.
    mutating func record(totalBytes: Int64, at time: Date) {
        samples.append(Sample(time: time, bytes: totalBytes))
        // La fenêtre est bornée par le temps, pas par le nombre de relevés :
        // `URLSession` en émet des centaines par seconde sur une connexion
        // rapide, et une poignée sur une connexion lente.
        let cutoff = time.addingTimeInterval(-window)
        guard let firstInside = samples.firstIndex(where: { $0.time >= cutoff }) else { return }
        // Deux relevés dans la fenêtre suffisent à mesurer : tout ce qui
        // précède est jeté, sans quoi la fenêtre réelle déborderait et un
        // effondrement de débit resterait masqué par le régime d'avant.
        //
        // En dessous, on garde le dernier relevé antérieur : c'est le cas d'un
        // téléchargement si lent que les notifications se raréfient — sans ce
        // repli, il ne resterait qu'un point et le débit disparaîtrait
        // précisément au moment où il ralentit.
        let keepFrom = samples.count - firstInside >= 2 ? firstInside : max(0, firstInside - 1)
        if keepFrom > 0 { samples.removeFirst(keepFrom) }
    }

    /// Le débit en octets par seconde, ou `nil` tant qu'il n'y a rien de
    /// mesurable : un seul relevé, un intervalle trop court, ou une horloge qui
    /// n'a pas avancé.
    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }
        let delta = last.bytes - first.bytes
        // Un delta négatif n'a pas de sens pour un total cumulé ; le refuser
        // plutôt que d'afficher un débit négatif.
        guard delta >= 0 else { return nil }
        return Double(delta) / span
    }

    /// Repart de zéro — un nouveau téléchargement, ou une reprise.
    mutating func reset() { samples.removeAll(keepingCapacity: true) }
}

/// Où en est le téléchargement en cours.
///
/// **La taille totale est facultative, et ce n'est pas un cas rare.** Le CDN de
/// Nexus ne l'annonce pas toujours (`expectedContentLength` vaut alors `-1`).
/// Sans elle : pas de pourcentage, pas de barre, pas de temps restant — le
/// volume reçu et le débit, qui sont vrais. Afficher une barre à 0 % ou un
/// « ∞ » serait pire que de ne rien montrer.
struct DownloadProgress: Equatable, Sendable {
    /// Ce que le téléchargement rapporte de lui-même.
    let bytesReceived: Int64
    /// `nil` quand le serveur ne l'annonce pas.
    let totalBytes: Int64?
    /// `nil` tant que le débit n'est pas mesurable (voir `DownloadRateEstimator`).
    let bytesPerSecond: Double?
    /// L'identifiant Nexus du mod, pour nommer ce qui se télécharge.
    let nexusModId: Int?

    init(bytesReceived: Int64, totalBytes: Int64?, bytesPerSecond: Double?,
         nexusModId: Int? = nil) {
        self.bytesReceived = bytesReceived
        // Un total nul ou négatif n'est pas une taille : `URLSession` rend
        // `-1` quand il l'ignore, et le laisser passer donnerait une division
        // par zéro déguisée en pourcentage.
        self.totalBytes = (totalBytes ?? 0) > 0 ? totalBytes : nil
        self.bytesPerSecond = (bytesPerSecond ?? 0) > 0 ? bytesPerSecond : nil
        self.nexusModId = nexusModId
    }

    /// La part reçue, entre 0 et 1. `nil` sans taille totale annoncée.
    ///
    /// Bornée à 1 : un serveur qui annonce une taille et en envoie davantage
    /// existe (réponse recompressée, en-tête menteur), et une barre remplie à
    /// 110 % déborderait de son cadre.
    var fractionCompleted: Double? {
        guard let totalBytes else { return nil }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }

    /// Le pourcentage entier à afficher. Même prudence que la couverture de
    /// traduction : « 100 » n'est rendu qu'une fois tout reçu — un
    /// téléchargement annoncé fini qui continue est le pire des affichages.
    var displayPercent: Int? {
        guard let fraction = fractionCompleted else { return nil }
        guard let totalBytes, bytesReceived < totalBytes else { return 100 }
        return max(0, min(99, Int(fraction * 100)))
    }

    /// Le temps restant, en secondes. `nil` sans taille totale **ou** sans
    /// débit mesurable : les deux sont nécessaires, et aucun ne se devine.
    var estimatedTimeRemaining: TimeInterval? {
        guard let totalBytes, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        let remaining = totalBytes - bytesReceived
        guard remaining > 0 else { return 0 }
        return Double(remaining) / bytesPerSecond
    }
}
