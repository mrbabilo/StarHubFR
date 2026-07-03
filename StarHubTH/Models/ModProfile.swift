import Foundation

struct ModProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var enabledModIds: [String] // Array of uniqueIds
}
