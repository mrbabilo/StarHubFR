import SwiftUI
import AppKit

// MARK: - Color Tokens (ValleyOS)
extension Color {
    static let vBg          = Color.black.opacity(0.0)      // transparent (show blurred bg)
    static let vGlass       = Color.white.opacity(0.08)
    static let vGlassBorder = Color.white.opacity(0.14)
    static let vGlassHover  = Color.white.opacity(0.12)
    static let vSidebar     = Color.black.opacity(0.28)
    static let vAccent      = Color(red: 0.3, green: 0.82, blue: 0.42)   // Stardew Green
    static let vAccentDark  = Color(red: 0.18, green: 0.60, blue: 0.28)
    static let vText        = Color.white
    static let vMuted       = Color.white.opacity(0.55)
    static let vSubtle      = Color.white.opacity(0.35)
    static let vRed         = Color(red: 1.0, green: 0.38, blue: 0.35)
}

// MARK: - macOS Visual Effect (blur/vibrancy)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Glass Card Modifier (Squircle)
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur(material: .sidebar, blendingMode: .withinWindow)
                    Color.vGlass
                }
                .cornerRadius(cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.vGlassBorder, lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    // Legacy compat
    func stardewPanel(title: String? = nil) -> some View { self.glassCard() }
    func appPanel(title: String? = nil) -> some View { self.glassCard() }
}

// MARK: - iOS-style Toggle
struct ValleyToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { configuration.isOn.toggle() } }) {
            RoundedRectangle(cornerRadius: 14)
                .fill(configuration.isOn ? Color.vAccent : Color.white.opacity(0.2))
                .frame(width: 44, height: 26)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .offset(x: configuration.isOn ? 9 : -9)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Pill Button Modifier
struct PillButton: ViewModifier {
    var style: PillStyle = .primary
    @State private var isHovered = false
    @State private var isPressed = false

    enum PillStyle { case primary, secondary, ghost, danger }

    var bg: Color {
        switch style {
        case .primary:   return isHovered ? Color.vAccent : Color.vAccent.opacity(0.9)
        case .secondary: return isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12)
        case .ghost:     return isHovered ? Color.white.opacity(0.1) : Color.clear
        case .danger:    return isHovered ? Color.vRed : Color.vRed.opacity(0.15)
        }
    }

    var fg: Color {
        switch style {
        case .primary:   return .black
        case .secondary: return .vText
        case .ghost:     return .vAccent
        case .danger:    return isHovered ? .white : .vRed
        }
    }

    func body(content: Content) -> some View {
        content
            .foregroundColor(fg)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(bg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(style == .ghost ? Color.vAccent.opacity(0.3) : Color.clear, lineWidth: 1))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
            .onHover { isHovered = $0 }
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { isPressed = $0 }, perform: {})
            .pointingHandCursor()
    }
}

extension View {
    func pillButton(style: PillButton.PillStyle = .primary) -> some View {
        modifier(PillButton(style: style))
    }

    // Legacy compat
    func stardewButton(style _: Any? = nil, isSelected _: Bool = false) -> some View {
        modifier(PillButton(style: .secondary))
    }
    func appButton(style: AppButtonStyle = .secondary) -> some View {
        switch style {
        case .primary: return AnyView(modifier(PillButton(style: .primary)))
        case .danger:  return AnyView(modifier(PillButton(style: .danger)))
        default:       return AnyView(modifier(PillButton(style: .secondary)))
        }
    }
}

enum AppButtonStyle { case primary, secondary, danger, ghost }
