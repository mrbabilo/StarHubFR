import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ZZProbe {
    @Test func absents() throws {
        let game = "/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS"
        let mods = ModScanner().scan(gameDir: game, installedModDate: { _ in nil },
                                     onProgress: { _ in }, log: { _ in }).mods
        let parc = Set(mods.allUniqueIds.map { $0.lowercased() })
        print("PROBE parc", mods.count, "ids", parc.count)
        for save in ["Zofia_443716371", "TestOK_444827372"] {
            let url = URL(fileURLWithPath: NSHomeDirectory()
                + "/.config/StardewValley/Saves/\(save)/\(save)")
            let t0 = Date()
            let data = try Data(contentsOf: url)
            let t1 = Date()
            let scan = try #require(SaveFingerprintScanner.scan(data))
            print("PROBE \(save) lecture", Date().timeIntervalSince(t0),
                  "scan", Date().timeIntervalSince(t1),
                  "Mo", data.count / 1_000_000)
            let uids = Set(scan.modDataKeys.keys.compactMap { key -> String? in
                guard key.hasPrefix("smapi/mod-data/") else { return nil }
                return key.dropFirst(15).split(separator: "/").first.map { $0.lowercased() }
            })
            print("PROBE \(save) absents:", uids.subtracting(parc).sorted())
        }
    }
}
