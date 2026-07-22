import SwiftUI

// MARK: - Standard Section
struct StandardSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content
    
    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background(Color.clear)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            
            if let footerText = footer, !footerText.isEmpty {
                Text(LocalizedStringKey(footerText))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .tint(.accentColor)
            }
        }
    }
}

// MARK: - Standard Row
struct StandardRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let showDivider: Bool
    
    init(title: LocalizedStringKey, detail: LocalizedStringKey, showDivider: Bool = true) {
        self.title = title
        self.detail = detail
        self.showDivider = showDivider
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            if showDivider {
                Divider()
            }
        }
    }
}

// MARK: - Info Popover Button
struct InfoPopoverButton: View {
    let text: String
    var color: Color = .secondary
    @State private var showPopover = false
    
    var body: some View {
        Button(action: {
            showPopover.toggle()
        }) {
            Image(systemName: "info.circle")
                .foregroundColor(color)
                .font(.system(size: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .padding()
                .frame(width: 200)
        }
    }
}
