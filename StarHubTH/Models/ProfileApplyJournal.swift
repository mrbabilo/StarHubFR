import Foundation

/// Un crash au milieu d'une application de profil, rendu détectable au
/// lancement suivant.
///
/// La présence du fichier signifie une seule chose : la boucle de renommage
/// d'`applyProfileToFilesystem` est morte en route (crash, force-quit). Les
/// échecs de déplacement ordinaires — dossier tenu ouvert, collision — vivent
/// dans `incompletelyAppliedProfileIds` et son alerte, pas ici : eux, la
/// boucle les a vus passer.
///
/// `moves` sert au diagnostic (et au futur R5, qui en fera un retour
/// arrière) ; la reprise ne les **rejoue** pas — elle recalcule un plan sur
/// le parc relu, le plan étant idempotent (R6).
struct ProfileApplyJournal: Codable, Equatable {
    /// Le profil qu'on appliquait. Survit à la suppression du profil.
    let profileId: UUID
    /// Le nom au moment de l'application — l'alerte doit savoir parler même
    /// si le profil n'existe plus.
    let profileName: String
    let startedAt: Date
    let moves: [ProfileApplyPlan.Move]

    init(profileId: UUID, profileName: String, startedAt: Date,
                moves: [ProfileApplyPlan.Move]) {
        self.profileId = profileId
        self.profileName = profileName
        self.startedAt = startedAt
        self.moves = moves
    }
}

enum ProfileApplyJournalStore {
    /// Même dossier que le reste de l'état de récupération (voir
    /// `BisectionSnapshotStore`), mais il arrive en **paramètre** : aucun
    /// point d'entrée n'a de valeur par défaut, donc rien ne peut retomber sur
    /// le vrai Application Support d'un joueur par oubli, et deux tests
    /// concurrents ne peuvent plus se voler leur redirection. La production
    /// passe explicitement `AppSupport.directory`.
    ///
    /// Pas de création de dossier ici : `save` garantit le chemin au moment
    /// d'écrire (et signale son échec). `nil` reste toléré en silence — sans
    /// dossier de support, l'app ne peut rien persister de toute façon.
    private static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("profile_apply_journal.json")
    }

    /// Écriture atomique (`.atomic` = tmp + rename) : un fichier déchiré se
    /// lira « corrompu ⇒ absent », et un journal absent au moment d'un crash
    /// pendant l'écriture signifie que la boucle n'avait pas commencé — les
    /// deux lectures sont correctes.
    ///
    /// Retourne l'erreur d'écriture s'il y en a une, pour que l'appelant la
    /// dise à l'utilisateur plutôt que de l'avaler en `print` : sans
    /// filet de récupération après crash, la prochaine reprise ne pourra pas
    /// se déclencher et l'app continuera comme si de rien n'était.
    @discardableResult
    static func save(_ journal: ProfileApplyJournal, in directory: URL?) -> Error? {
        guard let directory else { return nil }
        let url = fileURL(in: directory)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(journal)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }

    /// Corrompu ⇒ nil : un journal illisible ne doit jamais paralyser le
    /// lancement. La forme `do/catch` plutôt que `try?` rend le contrat
    /// lisible : chaque échec **est** « absent », pas un accident avalé.
    static func load(from directory: URL?) -> ProfileApplyJournal? {
        guard let directory else { return nil }
        let url = fileURL(in: directory)
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return nil }
        do { return try JSONDecoder().decode(ProfileApplyJournal.self, from: data) } catch { return nil }
    }

    static func clear(in directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }
}
