import Foundation

/// Les onglets de la fiche, **nommés** : le parcours « traduis ce mod »
/// (`pendingTranslationFocus`) pointait un index entier — chaque
/// réordonnancement d'onglets le recassait en silence.
///
/// Vit en Core (P8-2) : le store de navigation porte `pendingDetailTab`, et
/// Core ne peut pas référencer un type de vue.
public enum DetailTab: Hashable {
    case description, changelog, dependencies, state, translation
}
