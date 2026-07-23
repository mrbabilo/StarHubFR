import Foundation

extension Dictionary where Key == String {
    func caseInsensitiveValue(forKey key: String) -> Value? {
        if let value = self[key] { return value }
        let lowerKey = key.lowercased()
        if let match = self.first(where: { $0.key.lowercased() == lowerKey }) {
            return match.value
        }
        return nil
    }
}
