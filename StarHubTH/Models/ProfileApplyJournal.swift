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
    /// `BisectionSnapshotStore`). `internal` et mutable uniquement pour les
    /// tests, qui le redirigent vers un dossier temporaire.
    static var storageDirectory: URL? = defaultDirectory()

    private static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL? {
        storageDirectory?.appendingPathComponent("profile_apply_journal.json")
    }

    /// Écriture atomique (`.atomic` = tmp + rename) : un fichier déchiré se
    /// lira « corrompu ⇒ absent », et un journal absent au moment d'un crash
    /// pendant l'écriture signifie que la boucle n'avait pas commencé — les
    /// deux lectures sont correctes.
    static func save(_ journal: ProfileApplyJournal) {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(journal)
            try data.write(to: url, options: .atomic)
        } catch {
            // L'unique filet de récupération après crash : si l'écriture
            // échoue, la reprise sera impossible au prochain démarrage. Le
            // signaler plutôt que de l'avaler silencieusement.
            print("Warning: profile apply journal write failed at \(url.path): \(error)")
        }
    }

    /// Corrompu ⇒ nil : un journal illisible ne doit jamais paralyser le
    /// lancement.
    static func load() -> ProfileApplyJournal? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProfileApplyJournal.self, from: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
