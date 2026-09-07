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
///
/// Si le jeu **n'est jamais devenu visible** (crash au lancement, refus de
/// Gatekeeper, dossier de jeu invalide), la porte se rouvre **quand même** à
/// la fin de la fenêtre aveugle — `admit()` n'a pas besoin qu'on lui dise
/// quoi que ce soit, le temps écoulé suffit. C'est pour cela que le cooldown
/// reste court : il borne la gêne d'un lancement avorté, pas l'absence du
/// jeu.
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
    ///
    /// La porte se rouvre d'elle-même une fois `cooldown` écoulée : un jeu
    /// qui a crashé avant d'apparaître dans `NSWorkspace` n'avertira jamais
    /// `noticeGameRunning()`, et un refus au-delà de la fenêtre serait
    /// silencieux — l'utilisateur verrait « Lancement récent refusé » sans
    /// cause connue.
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
