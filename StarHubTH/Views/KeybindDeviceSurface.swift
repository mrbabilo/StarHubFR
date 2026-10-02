import SwiftUI

/// La souris et la manette de la vue clavier du rapport de raccourcis
/// (`KeybindKeyboardGroup`) : un corps dessiné et des zones cliquables aux
/// noms `SButton` de SMAPI (disposition Xbox pour la manette).
struct KeybindDeviceSurface: View {
    enum Design { case mouse, gamepad }

    let title: String
    let design: Design
    let index: [String: [KeybindScanner.SettingBinding]]
    @ObservedObject var localization: LocalizationStore
    let openConfig: (String, [String]) -> Void

    private struct Spot { let name: String; let label: String; let rect: CGRect; let round: Bool }

    private var canvas: CGSize { design == .mouse ? CGSize(width: 150, height: 210) : CGSize(width: 320, height: 200) }

    private var spots: [Spot] {
        switch design {
        case .mouse:
            return [
                Spot(name: "MouseLeft", label: "G", rect: CGRect(x: 18, y: 10, width: 54, height: 78), round: false),
                Spot(name: "MouseRight", label: "D", rect: CGRect(x: 78, y: 10, width: 54, height: 78), round: false),
                Spot(name: "MouseMiddle", label: "", rect: CGRect(x: 66, y: 24, width: 18, height: 36), round: true),
                Spot(name: "MouseX2", label: "X2", rect: CGRect(x: 2, y: 96, width: 14, height: 26), round: false),
                Spot(name: "MouseX1", label: "X1", rect: CGRect(x: 2, y: 128, width: 14, height: 26), round: false),
            ]
        case .gamepad:
            return [
                Spot(name: "LeftTrigger", label: "LT", rect: CGRect(x: 42, y: 0, width: 56, height: 18), round: false),
                Spot(name: "RightTrigger", label: "RT", rect: CGRect(x: 222, y: 0, width: 56, height: 18), round: false),
                Spot(name: "LeftShoulder", label: "LB", rect: CGRect(x: 36, y: 22, width: 68, height: 16), round: false),
                Spot(name: "RightShoulder", label: "RB", rect: CGRect(x: 216, y: 22, width: 68, height: 16), round: false),
                Spot(name: "LeftStick", label: "L3", rect: CGRect(x: 66, y: 70, width: 38, height: 38), round: true),
                Spot(name: "RightStick", label: "R3", rect: CGRect(x: 182, y: 118, width: 36, height: 36), round: true),
                Spot(name: "DPadUp", label: "▲", rect: CGRect(x: 112, y: 106, width: 18, height: 18), round: false),
                Spot(name: "DPadDown", label: "▼", rect: CGRect(x: 112, y: 142, width: 18, height: 18), round: false),
                Spot(name: "DPadLeft", label: "◀", rect: CGRect(x: 94, y: 124, width: 18, height: 18), round: false),
                Spot(name: "DPadRight", label: "▶", rect: CGRect(x: 130, y: 124, width: 18, height: 18), round: false),
                Spot(name: "ControllerBack", label: "⧉", rect: CGRect(x: 134, y: 78, width: 18, height: 12), round: true),
                Spot(name: "ControllerStart", label: "≡", rect: CGRect(x: 168, y: 78, width: 18, height: 12), round: true),
                Spot(name: "BigButton", label: "", rect: CGRect(x: 150, y: 52, width: 20, height: 20), round: true),
                Spot(name: "ControllerY", label: "Y", rect: CGRect(x: 226, y: 58, width: 22, height: 22), round: true),
                Spot(name: "ControllerX", label: "X", rect: CGRect(x: 204, y: 80, width: 22, height: 22), round: true),
                Spot(name: "ControllerB", label: "B", rect: CGRect(x: 248, y: 80, width: 22, height: 22), round: true),
                Spot(name: "ControllerA", label: "A", rect: CGRect(x: 226, y: 102, width: 22, height: 22), round: true),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(title).font(AppDesign.Font.caption(.semibold))
            ZStack(alignment: .topLeading) {
                body(of: design).fill(Color.secondary.opacity(0.12))
                body(of: design).stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                ForEach(spots, id: \.name) { spot in
                    KeybindSurfaceButton(name: spot.name, index: index, localization: localization,
                                  openConfig: openConfig,
                                  shape: spot.round ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 5))) {
                        Text(spot.label).font(.system(size: 9, weight: .semibold))
                            .frame(width: spot.rect.width, height: spot.rect.height)
                    }
                    .frame(width: spot.rect.width, height: spot.rect.height)
                    .offset(x: spot.rect.minX, y: spot.rect.minY)
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        }
        .fixedSize()
    }

    private func body(of design: Design) -> Path {
        switch design {
        case .mouse:
            return Path(roundedRect: CGRect(x: 14, y: 6, width: 122, height: 200), cornerRadius: 60)
        case .gamepad:
            var p = Path()
            p.move(to: CGPoint(x: 88, y: 44))
            p.addLine(to: CGPoint(x: 232, y: 44))
            p.addCurve(to: CGPoint(x: 312, y: 150), control1: CGPoint(x: 276, y: 44), control2: CGPoint(x: 304, y: 90))
            p.addCurve(to: CGPoint(x: 276, y: 196), control1: CGPoint(x: 318, y: 190), control2: CGPoint(x: 296, y: 202))
            p.addCurve(to: CGPoint(x: 228, y: 160), control1: CGPoint(x: 256, y: 190), control2: CGPoint(x: 244, y: 168))
            p.addLine(to: CGPoint(x: 92, y: 160))
            p.addCurve(to: CGPoint(x: 44, y: 196), control1: CGPoint(x: 76, y: 168), control2: CGPoint(x: 64, y: 190))
            p.addCurve(to: CGPoint(x: 8, y: 150), control1: CGPoint(x: 24, y: 202), control2: CGPoint(x: 2, y: 190))
            p.addCurve(to: CGPoint(x: 88, y: 44), control1: CGPoint(x: 16, y: 90), control2: CGPoint(x: 44, y: 44))
            p.closeSubpath()
            return p
        }
    }
}

