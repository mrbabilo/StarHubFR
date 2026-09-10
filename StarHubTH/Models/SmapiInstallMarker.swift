import Foundation

/// Le seul marqueur fiable de la présence de SMAPI dans un dossier de jeu
/// (X77) : le dossier `smapi-internal/`, posé par **chaque** installation et
/// retiré par **chaque** désinstallation — mesuré le 2026-09-06 sur une
/// installation de contrôle du vrai binaire SMAPI 4.5.2.
///
/// `StardewValley-original` ne l'est pas : il n'apparaît qu'en **remplaçant**
/// une installation SMAPI antérieure. Une installation propre — jeu vierge —
/// ne le pose jamais, si bien que détecter SMAPI par lui faisait une
/// installation réussie passer pour absente au scan suivant : réinstallation
/// possible en boucle, désinstallation refusée. Les preuves de réussite de
/// `runOfficialInstaller` testaient déjà `smapi-internal` ; la détection et
/// les preuves partagent désormais la même définition, par construction.
///
/// ⚠️ Le lancement **vanilla** (`launchGame` dans le ViewModel) teste
/// `StardewValley-original` pour une autre raison : c'est le **binaire** qu'il
/// exécute. Ce test-là reste légitime — voir le commentaire de
/// `HomeLaunchState` sur la réconciliation à faire un jour.
public enum SmapiInstallMarker {

    /// Posé par chaque installation SMAPI, retiré par chaque désinstallation.
    public static let folderName = "smapi-internal"

    /// Le marqueur de **version** que `SmapiInstaller.install()` écrit à la
    /// fin d'une installation réussie — chemin relatif au dossier de jeu,
    /// source n°1 du lecteur `SmapiVersionEvidence.installedVersion`.
    /// Une seule définition : l'installateur qui l'écrit et le lecteur qui
    /// le lit doivent nommer le même fichier par construction.
    public static let installedVersionRelativePath =
        "\(folderName)/.starhubth-installed-version"

    public static func isPresent(gameDir: String, fm: FileManager = .default) -> Bool {
        let path = (gameDir as NSString).appendingPathComponent(folderName)
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
