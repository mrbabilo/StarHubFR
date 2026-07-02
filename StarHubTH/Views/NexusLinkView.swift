import SwiftUI

// Subview representing the interactive Nexus Link with hover state color adjustments
struct NexusLinkView: View {
    let urlString: String
    let isSelected: Bool
    let activeColor: Color
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text("Nexus")
                .font(.system(size: 11))
                .foregroundColor(isHovered ? (isSelected ? Color.white.opacity(0.7) : activeColor.opacity(0.7)) : (isSelected ? Color.white : activeColor))
                .underline(isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .onHover { hover in
            isHovered = hover
        }
    }
}
