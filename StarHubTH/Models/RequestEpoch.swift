import Foundation

/// Le jeton qui dit si une réponse asynchrone est encore attendue.
///
/// Le motif que ça résout : une vue lance une requête, l'utilisateur en lance
/// une seconde avant que la première ne revienne, et rien ne garantit l'ordre
/// de retour. Sans jeton, la réponse la plus lente écrit par-dessus la plus
/// récente — l'écran affiche alors le résultat d'une question qui n'est plus
/// posée. Le cas mesuré : deux recherches Nexus rapprochées (X49), et une
/// réponse qui ressuscitait des résultats que l'utilisateur venait de fermer.
///
/// À tenir sur le **fil principal**, comme l'état publié qu'il protège : c'est
/// une `struct`, deux appels concurrents à `open()` se marcheraient dessus.
public struct RequestEpoch: Equatable, Sendable {
    /// Le jeton de la demande en cours. Part à 1 au premier `open()` : la
    /// valeur initiale n'est distribuée à personne, donc rien ne peut la
    /// présenter comme courante.
    private var current: Int = 0

    public init() {}

    /// Ouvre une demande et rend son jeton. Toute réponse portant un jeton
    /// antérieur est périmée à partir de là.
    public mutating func open() -> Int {
        current &+= 1
        return current
    }

    /// Périme tout ce qui est en vol sans rien ouvrir — l'utilisateur a quitté
    /// l'écran, ou vidé le champ.
    public mutating func abandonAll() {
        current &+= 1
    }

    /// Le jeton de la demande en cours, sans en ouvrir de nouvelle : ce qu'une
    /// pagination doit porter pour prolonger la demande au lieu de la
    /// remplacer.
    public var currentToken: Int { current }

    /// Cette réponse est-elle encore celle qu'on attend ?
    public func isCurrent(_ token: Int) -> Bool { token == current }
}
