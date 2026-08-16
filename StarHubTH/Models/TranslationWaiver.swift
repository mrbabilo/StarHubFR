import Foundation

/// L'accord du traducteur pour passer outre une divergence de marques.
///
/// Il existe des cas légitimes : une phrase française neutre n'a que faire d'un
/// `${him^her^them}$`, et une phrase plus courte peut se passer d'un `^`.
/// Refuser sans issue rendrait ces chaînes définitivement intraduisibles — chez
/// nous plus qu'ailleurs, puisque l'édition est en place et qu'y enregistrer,
/// c'est publier.
///
/// Mais l'accord ne vaut **que pour le couple source/cible sur lequel il a été
/// donné**. Un accord qui survivrait à une modification serait pire que pas
/// d'accord : il laisserait passer une vraie erreur au nom d'une décision prise
/// pour une autre phrase. Sa péremption est automatique — `TranslationBaseline`
/// retenant déjà source et cible, il suffit qu'elles ne correspondent plus.
public enum TranslationWaiver {

    /// L'accord vaut-il encore pour ce couple ?
    public static func isAccepted(_ entry: TranslationBaseline.Entry?,
                                  source: String, target: String) -> Bool {
        guard let entry, entry.tokenMismatchAccepted else { return false }
        return entry.source == source && entry.target == target
    }

    /// L'entrée à écrire quand le traducteur passe outre.
    public static func accepting(source: String, target: String) -> TranslationBaseline.Entry {
        TranslationBaseline.Entry(source: source, target: target, tokenMismatchAccepted: true)
    }
}
