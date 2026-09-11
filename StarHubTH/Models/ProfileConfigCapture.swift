import Foundation

/// Quand **ne pas** mémoriser les `config.json` d'un profil, et comment
/// compter ce qu'une passe a changé.
///
/// Les trois abstentions partagent une même règle : **laisser le trou visible
/// plutôt que maquiller une donnée fausse**. Chacune couvre un état où le
/// disque ne porte pas ce que le profil croit y avoir — capturer y
/// attribuerait au profil le contenu d'un autre, dans le geste même censé
/// préserver ses réglages.
enum ProfileConfigCapture {

    /// Pourquoi la capture n'a pas lieu. Chaque cas porte de quoi le dire à
    /// l'utilisateur ; l'appelant résout la clé de localisation.
    enum Abstention: Equatable, Sendable {
        /// Le jeu tourne : il réécrit les `config.json` sous nos pieds.
        case gameRunning
        /// Une bascule antérieure, faite jeu ouvert, a laissé ce profil actif
        /// sans que son disque en porte les réglages — il tient encore ceux
        /// d'un autre profil.
        case desynced(profileName: String)
        /// R2 : l'application de ce profil s'est arrêtée en chemin, et son
        /// disque tient un état dont rien ne dit pour quel profil il est fait.
        case interruptedApply(profileName: String)
    }

    /// - Parameter journal: l'application interrompue non résolue. Son
    ///   `profileName` **fait foi** pour nommer l'abstention : il survit au
    ///   renommage comme à la suppression du profil.
    static func abstention(capturing profileId: UUID,
                           profiles: [ModProfile],
                           gameRunning: Bool,
                           desyncedProfileId: UUID?,
                           journal: ProfileApplyJournal?) -> Abstention? {
        // Le jeu d'abord : c'est la cause que l'utilisateur peut traiter tout
        // de suite, et elle rend les deux autres sans objet.
        if gameRunning { return .gameRunning }
        if desyncedProfileId == profileId {
            let name = profiles.first { $0.id == profileId }?.name ?? ""
            return .desynced(profileName: name)
        }
        if let journal, journal.profileId == profileId {
            return .interruptedApply(profileName: journal.profileName)
        }
        return nil
    }

    /// Combien d'entrées cette passe a réellement touchées — ajoutées,
    /// retirées, ou dont le texte a changé.
    ///
    /// **Pas le total du magasin** : « 12 configs mémorisés » quand un seul a
    /// bougé donnerait une fausse idée de ce que la bascule vient de faire.
    /// Une date de capture rafraîchie sans changement de texte ne compte pas
    /// — `ProfileConfigStore.captured` ne la rafraîchit d'ailleurs pas.
    static func touchedCount(before: [String: ProfileConfigEntry],
                             after: [String: ProfileConfigEntry]) -> Int {
        Set(after.keys).symmetricDifference(before.keys).count
            + after.filter { before[$0.key] != nil && before[$0.key]?.text != $0.value.text }.count
    }
}
