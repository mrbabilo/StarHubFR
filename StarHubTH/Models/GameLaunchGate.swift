import Foundation

/// Le délai anti double-lancement du jeu (R2bis).
///
/// Seconde couche du garde « jamais deux instances du jeu » : la première —
/// `isGameRunning()` — interroge `NSWorkspace.runningApplications`, mais le
/// processus lancé n'y apparaît pas avant quelques secondes. Pendant cette
/// fenêtre aveugle, un double-clic sur le bouton de lancement partirait une
/// seconde instance. Ce garde ponte la fenêtre : un lancement admis ferme la
/// porte pour `cooldown` secondes, indépendamment de ce que le système voit.
///
/// Une fois le jeu visible, c'est `isGameRunning()` qui protège : le VM
/// appelle alors `noticeGameRunning()` pour rouvrir la porte — sinon un crash
/// immédiat suivi d'un relancement légitime attendrait le délai complet pour
/// rien.
struct GameLaunchGate {
    /// Largeur de la fenêtre aveugle. Dix secondes couvrent l'apparition du
    /// processus dans `NSWorkspace` (quelques secondes mesurées) avec marge,
    /// sans transformer un vrai échec de lancement en attente interminable.
    static let cooldown: TimeInterval = 10

    /// Horodatage du dernier lancement **admis** — pas du dernier clic : un
    /// refus ne rallonge pas la fenêtre.
    private var lastAdmittedAt: Date?

    /// Admet le lancement, ou le refuse s'il tombe dans la fenêtre d'un
    /// lancement précédent. Seul un `true` déplace l'horodatage.
    mutating func admit(now: Date = Date()) -> Bool {
        if let last = lastAdmittedAt, now.timeIntervalSince(last) < Self.cooldown {
            return false
        }
        lastAdmittedAt = now
        return true
    }

    /// Le jeu est devenu visible dans `NSWorkspace` : le garde système prend
    /// le relais, la porte se rouvre immédiatement.
    mutating func noticeGameRunning() {
        lastAdmittedAt = nil
    }
}
