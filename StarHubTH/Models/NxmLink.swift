import Foundation

/// Parsed representation of a Nexus `nxm://` deep link, produced when the user
/// clicks "Mod Manager Download" on the website. The `key`/`expires` pair is
/// what unlocks `download_link.json` for NON-premium accounts; premium links
/// may omit them. Format:
/// nxm://<gameDomain>/mods/<modId>/files/<fileId>?key=…&expires=…&user_id=…
struct NxmLink: Equatable {
    let gameDomain: String
    let modId: Int
    let fileId: Int
    let key: String?
    let expires: Int?
    let userId: Int?

    static func parse(_ url: URL) -> NxmLink? {
        guard url.scheme?.lowercased() == "nxm" else { return nil }
        // host = gameDomain; path = /mods/<modId>/files/<fileId>
        guard let gameDomain = url.host, !gameDomain.isEmpty else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "mods", parts[2] == "files",
              let modId = Int(parts[1]), let fileId = Int(parts[3]) else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return NxmLink(
            gameDomain: gameDomain,
            modId: modId,
            fileId: fileId,
            key: value("key"),
            expires: value("expires").flatMap(Int.init),
            userId: value("user_id").flatMap(Int.init)
        )
    }
}
