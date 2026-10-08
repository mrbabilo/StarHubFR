import Foundation

/// R5 — l'état actif/en pause d'avant un geste de masse, pour y revenir.
///
/// Le reste du retour en arrière existe déjà, chacun avec son mécanisme :
/// historique par mod (A1-T11), backups d'installation, corbeille, backups de
/// config, journal de reprise de profil (R2). Manquait seulement l'état des
/// dossiers avant un « Tout activer », une bascule de sélection ou un profil
/// appliqué — quelques Ko, là où copier les dossiers coûterait des dizaines de
/// Go.
///
/// Granularité : les dossiers **de tête** (un pack se renomme en entier),
/// par nom logique. Les dossiers en pause sont gardés aussi : au retour, un mod
/// installé depuis — inconnu de l'instantané — garde son état actuel au lieu
/// d'être mis en pause.
public struct ActivationSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Gesture: String, Codable, Sendable {
        case bulkEnable, bulkDisable, profile, restore
    }

    public let id: UUID
    public let takenAt: Date
    /// Le geste **qui a suivi** l'instantané : c'est lui que le retour défait.
    public let gesture: Gesture
    /// Nom du profil appliqué, nombre de mods visés… ce que la ligne affiche.
    public let detail: String?
    public let enabledFolders: [String]
    public let pausedFolders: [String]
    /// Le profil actif au moment de l'instantané. Revenir sous un autre
    /// profil ferait adopter cet état par ce dernier (`syncActiveProfileIds`) :
    /// le retour quitte alors le profil plutôt que de réécrire son contenu.
    public let activeProfileId: UUID?
    public var pinned: Bool

    public init(id: UUID = UUID(), takenAt: Date, gesture: Gesture, detail: String?,
                enabledFolders: [String], pausedFolders: [String],
                activeProfileId: UUID?, pinned: Bool = false) {
        self.id = id
        self.takenAt = takenAt
        self.gesture = gesture
        self.detail = detail
        self.enabledFolders = enabledFolders
        self.pausedFolders = pausedFolders
        self.activeProfileId = activeProfileId
        self.pinned = pinned
    }

    /// L'état des dossiers de tête, triés : deux instantanés du même état
    /// sont égaux quel que soit l'ordre du scan.
    public static func capture(gesture: Gesture, detail: String?, mods: [ModItem],
                               activeProfileId: UUID?, now: Date) -> ActivationSnapshot {
        ActivationSnapshot(takenAt: now, gesture: gesture, detail: detail,
                           enabledFolders: mods.filter(\.isEnabled).map(\.folderName).sorted(),
                           pausedFolders: mods.filter { !$0.isEnabled }.map(\.folderName).sorted(),
                           activeProfileId: activeProfileId)
    }

    func hasSameState(as other: ActivationSnapshot) -> Bool {
        enabledFolders == other.enabledFolders && pausedFolders == other.pausedFolders
    }
}

/// Les instantanés, du plus récent au plus ancien. Un retour ne réécrit rien :
/// il pose son propre instantané, et se défait donc comme le reste.
public struct ActivationHistory: Codable, Equatable, Sendable {
    public private(set) var snapshots: [ActivationSnapshot] = []

    /// Au-delà, un instantané non épinglé part. Épingler le garde.
    public static let retention: TimeInterval = 30 * 86_400
    /// Borne en nombre, pour une journée de bascules en série.
    public static let maxUnpinned = 50

    public init() {}

    /// Ajoute en tête, sauf si l'état est celui du plus récent : un geste qui
    /// n'a rien changé n'a rien à défaire.
    public mutating func record(_ snapshot: ActivationSnapshot, now: Date) {
        if let newest = snapshots.first, newest.hasSameState(as: snapshot) { return }
        snapshots.insert(snapshot, at: 0)
        prune(now: now)
    }

    public mutating func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[index].pinned = pinned
    }

    mutating func prune(now: Date) {
        var unpinned = 0
        snapshots = snapshots.filter { snapshot in
            if snapshot.pinned { return true }
            guard now.timeIntervalSince(snapshot.takenAt) <= Self.retention,
                  unpinned < Self.maxUnpinned else { return false }
            unpinned += 1
            return true
        }
    }
}

/// Les renommages qui ramènent `Mods/` à un instantané.
enum ActivationRestore {

    /// Par **dossier**, pas par `UniqueID` comme un profil : les mods sans
    /// identifiant (111 sur le parc) reviennent aussi. Un dossier inconnu de
    /// l'instantané ne bouge pas, et les mods de SMAPI ne sont jamais mis en
    /// pause (A1-T12). Les mises en pause d'abord, comme `ProfileApplyPlan` :
    /// elles libèrent un nom de dossier avant qu'un autre ne le réclame.
    ///
    /// - Parameter installed: les mods de **tête** du dernier scan.
    static func moves(to snapshot: ActivationSnapshot,
                      installed: [ModItem]) -> [ProfileApplyPlan.Move] {
        let enabled = Set(snapshot.enabledFolders)
        let paused = Set(snapshot.pausedFolders)
        let toDisable = installed.filter {
            $0.isEnabled && paused.contains($0.folderName) && !$0.isSmapiBundled
        }
        let toEnable = installed.filter { !$0.isEnabled && enabled.contains($0.folderName) }
        return toDisable.map { mod in
            ProfileApplyPlan.Move(folderName: mod.folderName, modName: mod.name,
                                  uniqueId: mod.uniqueId, source: mod.physicalFolderName,
                                  destination: "." + mod.folderName, direction: .disable)
        } + toEnable.map { mod in
            ProfileApplyPlan.Move(folderName: mod.folderName, modName: mod.name,
                                  uniqueId: mod.uniqueId, source: mod.physicalFolderName,
                                  destination: mod.folderName, direction: .enable)
        }
    }
}
