import SwiftUI

// MARK: - Initials Avatar
/// Circular "initials" badge — was reimplemented as the same
/// `ZStack { Circle().fill(...); Text(...) }` at 5 separate call sites
/// (the account-menu profile indicator, out-of-date/update mod rows, and
/// both mod-profile avatars); this is the one shared implementation.
struct InitialsAvatar: View {
    let text: String
    var initialsCount: Int = 1
    var size: CGFloat
    var fillColor: Color = .accentColor
    var textColor: Color = .white
    var fontSize: CGFloat
    var fontWeight: Font.Weight = .bold
    /// Optional border ring, e.g. to separate a small badge from the
    /// image it's overlaid on.
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 2

    private var initials: String {
        String(text.prefix(initialsCount)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .overlay {
                    if let strokeColor {
                        Circle().stroke(strokeColor, lineWidth: strokeWidth)
                    }
                }
            Text(initials)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(textColor)
        }
        .frame(width: size, height: size)
    }
}

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
                Text(verbatim: title)
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
                Text(verbatim: footerText)
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
            Text(verbatim: text)
                .font(.system(size: 12))
                .padding()
                .frame(width: 200)
        }
    }
}
