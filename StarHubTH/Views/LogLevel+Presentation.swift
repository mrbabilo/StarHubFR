import SwiftUI

/// Comment une sévérité se montre. Séparé du modèle (`Models/LogEntry.swift`)
/// parce qu'un `Color` SwiftUI dans un type de données l'exclut du module Core,
/// et donc de tout test.
extension LogLevel {
    var color: Color {
        switch self {
        case .info:    return .primary
        case .warning: return .orange
        case .error:   return .red
        case .trace:   return .blue
        }
    }

    var icon: String {
        switch self {
        case .info:    return AppDesign.Status.info.symbol
        case .warning: return AppDesign.Status.warning.symbol
        case .error:   return AppDesign.Status.error.symbol
        case .trace:   return "terminal"
        }
    }
}
