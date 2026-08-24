import Foundation

/// Ce qu'un profil contient à sa création.
enum ProfileSeed {
    /// Aucun mod — le profil se remplit ensuite, mod par mod. C'est le choix
    /// que l'auteur demande par défaut : créer un profil pour *préparer* une
    /// autre configuration, pas pour figer celle en cours.
    case empty
    /// Les mods actuellement actifs, tels quels.
    case currentlyEnabledMods
}

/// La création d'un profil, hors du ViewModel pour être vérifiable.
///
/// Le choix « vide ou instantané » entraîne une seconde décision qui n'a rien
/// d'évident — le profil doit-il devenir actif ? — et c'est celle qui casse
/// silencieusement si on la prend au mauvais endroit.
enum ProfileFactory {
    /// - Returns: le profil, et s'il peut devenir actif immédiatement.
    ///
    ///   Un instantané le peut : son contenu est exactement l'état du disque,
    ///   aucun dossier n'a besoin d'être déplacé. Un profil **vide** ne le peut
    ///   pas : le profil actif est réécrit depuis le disque à chaque scan
    ///   (`syncActiveProfileIds`), si bien qu'un profil vide marqué actif se
    ///   retrouverait rempli des mods en cours au scan suivant. L'utilisateur
    ///   l'active quand il le décide — et met alors ses mods en pause en
    ///   connaissance de cause.
    static func make(name: String,
                     seed: ProfileSeed,
                     enabledUniqueIds: [String]) -> (profile: ModProfile, activate: Bool) {
        switch seed {
        case .empty:
            return (ModProfile(name: name, enabledModIds: []), false)
        case .currentlyEnabledMods:
            return (ModProfile(name: name, enabledModIds: enabledUniqueIds), true)
        }
    }

    /// Copie un profil sous un nouveau nom.
    ///
    /// La copie porte son **propre identifiant** : `ModProfile` s'identifie par
    /// `id`, et deux profils qui le partageraient seraient renommés, supprimés
    /// ou activés d'un seul geste. Les homonymes, eux, sont sans conséquence —
    /// rien dans le code ne joint deux profils sur leur nom.
    ///
    /// - Parameter nameFormat: le gabarit localisé du nom de la copie, avec un
    ///   `%@` pour le nom d'origine.
    static func duplicate(_ profile: ModProfile, nameFormat: String) -> ModProfile {
        ModProfile(name: String(format: nameFormat, profile.name),
                   enabledModIds: profile.enabledModIds)
    }
}
