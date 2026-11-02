import Foundation

/// « Signaler un bug » : le formulaire `.github/ISSUE_TEMPLATE/bug_app.yml`
/// du dépôt, ouvert dans le navigateur. GitHub préremplit un champ du
/// formulaire par son `id` passé en paramètre ; seuls les champs texte s'y
/// prêtent (pas la liste du processeur, d'où sa place à côté de macOS).
///
/// Rien d'autre ne part dans l'adresse : ni journaux ni chemins, qui portent
/// le nom de l'utilisateur. Il relit et envoie lui-même le formulaire.
public enum BugReportLink {
    static let newIssue = "https://github.com/mrbabilo/StarHubFR/issues/new"

    public static func url(appVersion: String, build: String?,
                           macOS: OperatingSystemVersion, appleSilicon: Bool) -> URL {
        let version = "v\(appVersion)" + (build.map { " (build \($0))" } ?? "")
        let patch = macOS.patchVersion > 0 ? ".\(macOS.patchVersion)" : ""
        let system = "macOS \(macOS.majorVersion).\(macOS.minorVersion)\(patch) · "
            + (appleSilicon ? "Apple Silicon" : "Intel")
        var components = URLComponents(string: newIssue)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_app.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "starhubfr-version", value: version),
            URLQueryItem(name: "macos-version", value: system),
        ]
        return components.url!
    }

    /// Le lien pour l'app qui tourne.
    public static var current: URL {
        let info = Bundle.main.infoDictionary
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        return url(appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                   build: info?["CFBundleVersion"] as? String,
                   macOS: ProcessInfo.processInfo.operatingSystemVersion,
                   appleSilicon: appleSilicon)
    }
}
