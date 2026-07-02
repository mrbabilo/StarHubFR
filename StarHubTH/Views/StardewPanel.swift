import SwiftUI

// Glass panel modifier — used internally by glassCard and legacy compat
struct AppPanelModifier: ViewModifier {
    var title: String?
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.vMuted)
                    .tracking(1.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            content
                .padding(title != nil ? [.horizontal, .bottom] : .all, 16)
        }
        .glassCard(cornerRadius: 14)
    }
}
