import Foundation

/// L'état de la fiche de mod (REFACTORING §6, domaine Détail de mod) :
/// ce que la vue rend pendant la séquence cache → réseau. Les transitions
/// sont pures et testées (`ModDetailStateTests`) ; le câblage — `didSet`
/// d'ouverture, garde anti-course à l'application, sauvegarde du cache —
/// reste au ViewModel.
struct ModDetailState {
    let modId: Int
    var description: [DescriptionBlock]
    var changelog: [DescriptionBlock]
    /// Servi du cache ou du repli local : le frais arrive derrière.
    var isStale: Bool
    /// Un fetch réseau est en vol — seulement si un identifiant Nexus existe.
    var isLoading: Bool

    /// État initial : le cache s'il existe (affiché instantané, marqué
    /// stale pendant le rafraîchissement), sinon la description locale du
    /// manifeste, changelog vide. `modId <= 0` = pas d'identifiant Nexus :
    /// aucun réseau en vol, le spinner ne tourne pas pour un fetch qui
    /// n'aura jamais lieu.
    static func initial(modId: Int, cached: ModDetailRaw?, localDescription: String) -> ModDetailState {
        if modId > 0, let cached {
            return ModDetailState(modId: modId,
                description: DescriptionBlockParser.parse(cached.description),
                changelog: DescriptionBlockParser.parse(cached.changelog),
                isStale: true, isLoading: true)
        }
        return ModDetailState(modId: modId,
            description: DescriptionBlockParser.parse(localDescription),
            changelog: [], isStale: true, isLoading: modId > 0)
    }

    /// Rafraîchissement réseau réussi : frais, terminé.
    static func refreshed(modId: Int, raw: ModDetailRaw) -> ModDetailState {
        ModDetailState(modId: modId,
            description: DescriptionBlockParser.parse(raw.description),
            changelog: DescriptionBlockParser.parse(raw.changelog),
            isStale: false, isLoading: false)
    }

    /// Ferme le spinner — mais seulement si la fiche affichée est bien
    /// celle du mod visé : une réponse tardive pour un autre mod ne doit
    /// pas y toucher.
    mutating func stopLoading(ifShowing modId: Int) {
        guard self.modId == modId else { return }
        isLoading = false
    }
}
