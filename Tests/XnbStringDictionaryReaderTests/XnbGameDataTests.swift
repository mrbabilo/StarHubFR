import Foundation
import Testing
@testable import StarHubTHCore

/// Les schémas `Data/Objects` et `Data/BigCraftables` contre les fichiers
/// réels du jeu installé : chaque entrée lue, fichier consommé jusqu'au
/// dernier octet. `STARDEW_CONTENT_DIR` = dossier `Content` du jeu ;
/// sans elle, le test est sauté (CI). Aucune donnée du jeu dans le dépôt.
struct XnbGameDataTests {
    static let content = ProcessInfo.processInfo.environment["STARDEW_CONTENT_DIR"]
        .map { URL(fileURLWithPath: $0) }

    static func entries(_ name: String, _ schema: XnbSchema) throws -> [String: [String: XnbValue]] {
        guard let content else { preconditionFailure("garanti par .enabled") }
        let data = try Data(contentsOf: content.appendingPathComponent("Data/\(name).xnb"))
        guard case .dictionary(let pairs) = try XnbTypedReader.read(data, root: schema) else {
            Issue.record("racine de \(name) : pas un dictionnaire")
            return [:]
        }
        var entries: [String: [String: XnbValue]] = [:]
        for pair in pairs {
            guard case .string(let key) = pair.key, case .object(let fields) = pair.value else {
                Issue.record("entrée de \(name) mal formée : \(pair.key)")
                continue
            }
            entries[key] = fields
        }
        #expect(entries.count == pairs.count, "clés en double dans \(name)")
        return entries
    }

    /// Un nom de membre en double écraserait en silence la valeur lue avant.
    @Test func schemaMemberNamesAreUnique() {
        func check(_ schema: XnbSchema) {
            switch schema {
            case .object(let name, let members):
                let names = members.map(\.0)
                #expect(Set(names).count == names.count, "membre en double dans \(name)")
                members.forEach { check($0.1) }
            case .list(let element), .nullable(let element): check(element)
            case .dictionary(let key, let value): check(key); check(value)
            case .string, .int, .bool, .float, .double, .enumInt: break
            }
        }
        check(.objects)
        check(.bigCraftables)
    }

    @Test(.enabled(if: content != nil, "STARDEW_CONTENT_DIR absent — dossier Content du jeu"))
    func everyObjectOfTheInstalledGameIsRead() throws {
        let objects = try Self.entries("Objects", .objects)
        #expect(objects.count == 807, "mesuré sur le jeu 1.6.15")
        #expect(objects["24"]?["Name"] == .string("Parsnip"))
        #expect(objects["24"]?["DisplayName"] == .string("[LocalizedText Strings\\Objects:Parsnip_Name]"))

        let bigCraftables = try Self.entries("BigCraftables", .bigCraftables)
        #expect(bigCraftables.count == 182, "mesuré sur le jeu 1.6.15")
        #expect(bigCraftables["130"]?["Name"] == .string("Chest"))
    }
}
