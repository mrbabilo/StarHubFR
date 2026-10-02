import SwiftUI

/// Le rapport de raccourcis **sur le matériel** : un clavier de MacBook
/// (ISO ou ANSI selon le Mac), la souris et la manette, chaque touche
/// portant les réglages des mods actifs qui l'utilisent. Né de la maquette
/// validée le 2026-10-02.
///
/// Le nom d'une touche vient de la même règle que la capture
/// (`MacKeyCodeMap.capturedName`, caractère de la disposition active) : la
/// vue et l'éditeur ne peuvent pas diverger. Le conflit est celui du rapport
/// (`KeybindDevicePlacement.hasConflict`). Rien ne disparaît : un réglage
/// sans surface dessinée (`Delete`, `Home` sur un MacBook) va dans « Sans
/// touche dédiée ».
///
/// Clic sur une touche utilisée : un popover liste ses réglages, chacun avec
/// l'engrenage qui ouvre l'éditeur sur la clé (`openConfig`, C4-T13).
struct KeybindKeyboardGroup: View {
    @ObservedObject var localization: LocalizationStore
    let settings: [KeybindScanner.SettingBinding]
    @Binding var isExpanded: Bool
    let openConfig: (String, [String]) -> Void

    @AppStorage("keybindKeyboard.showMouse") private var showMouse = true
    @AppStorage("keybindKeyboard.showGamepad") private var showGamepad = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let index = KeybindDevicePlacement.index(settings)
            let keys = MacKeyboardGeometry.keys(MacKeyLayout.keyboardKind).map(DrawnKey.init)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                Text(localization.L(L10n.Keybinds.keyboardHint))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                KeyboardBoard(keys: keys, index: index, localization: localization,
                              openConfig: openConfig)
                HStack(spacing: AppDesign.Spacing.md) {
                    Toggle(localization.L(L10n.Keybinds.keyboardMouse), isOn: $showMouse)
                    Toggle(localization.L(L10n.Keybinds.keyboardGamepad), isOn: $showGamepad)
                }
                .toggleStyle(.checkbox)
                .font(AppDesign.Font.caption)
                // Côte à côte quand ils tiennent, l'un sous l'autre sinon
                // (fenêtre minimale de 560 pt).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppDesign.Spacing.lg) { devices(index) }
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.md) { devices(index) }
                }
                leftovers(index, keys: keys)
                Text(localization.L(L10n.Keybinds.keyboardModelNote))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(localization.L(L10n.Keybinds.keyboardHeader))
                .font(AppDesign.Font.body(.semibold))
        }
    }

    @ViewBuilder
    private func devices(_ index: [String: [KeybindScanner.SettingBinding]]) -> some View {
        if showMouse {
            KeybindDeviceSurface(title: localization.L(L10n.Keybinds.keyboardMouse), design: .mouse,
                          index: index, localization: localization, openConfig: openConfig)
        }
        if showGamepad {
            KeybindDeviceSurface(title: localization.L(L10n.Keybinds.keyboardGamepad), design: .gamepad,
                          index: index, localization: localization, openConfig: openConfig)
        }
    }

    /// Ce que ni le clavier, ni la souris, ni la manette ne portent : les
    /// touches atteintes avec fn, puis — en avertissement — celles qu'aucune
    /// touche de ce Mac ne produit.
    @ViewBuilder
    private func leftovers(_ index: [String: [KeybindScanner.SettingBinding]],
                           keys: [DrawnKey]) -> some View {
        let rest = KeybindDevicePlacement.leftovers(
            of: index, surfaces: KeybindDevicePlacement.surfaces(keyboard: keys.compactMap(\.name)))
        if !rest.viaFn.isEmpty {
            chips(localization.L(L10n.Keybinds.keyboardViaFn), names: rest.viaFn, index: index) {
                "\($0) (\(KeybindDevicePlacement.fnReachable[$0] ?? ""))"
            }
        }
        if !rest.unreachable.isEmpty {
            chips(localization.L(L10n.Keybinds.keyboardUnreachable), names: rest.unreachable,
                  index: index, warning: true) { $0 }
        }
    }

    private func chips(_ title: String, names: [String],
                       index: [String: [KeybindScanner.SettingBinding]],
                       warning: Bool = false, label: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            if warning {
                SwiftUI.Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(AppDesign.Font.caption(.semibold))
                    .foregroundColor(AppDesign.Color.warning)
            } else {
                Text(title).font(AppDesign.Font.caption(.semibold))
            }
            WrapHStack(spacing: 6, lineSpacing: 6) {
                ForEach(names, id: \.self) { name in
                    KeybindSurfaceButton(name: name, index: index, localization: localization,
                                         openConfig: openConfig) {
                        Text("\(label(name)) · \(index[name]?.count ?? 0)")
                            .font(AppDesign.Font.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Une touche dessinée

/// Une touche de la géométrie, nommée par la disposition active.
struct DrawnKey: Identifiable {
    let key: MacKeyboardGeometry.Key
    /// Le nom `SButton` que le jeu lit pour cette touche ; `nil` quand il ne
    /// la voit pas (`)` `^` `ù` en AZERTY) ou qu'elle n'en a pas (fn).
    let name: String?
    let legend: String
    let shifted: String?

    var id: String { key.id }

    init(_ key: MacKeyboardGeometry.Key) {
        self.key = key
        guard let code = key.keyCode else {
            name = nil; legend = key.label ?? ""; shifted = nil; return
        }
        let character = MacKeyLayout.character(for: code)
        name = MacKeyCodeMap.capturedName(keyCode: code, character: character)
        if let fixed = key.label {
            legend = fixed; shifted = nil
        } else {
            let main = (character ?? "").uppercased()
            legend = main
            let upper = MacKeyLayout.character(for: code, shift: true)
            // La légende du haut : seulement quand elle apprend quelque chose
            // (« 1 » au-dessus de « & »), pas la majuscule d'une lettre.
            if let upper, upper.uppercased() != main { shifted = upper } else { shifted = nil }
        }
    }
}

private struct KeyboardBoard: View {
    let keys: [DrawnKey]
    let index: [String: [KeybindScanner.SettingBinding]]
    @ObservedObject var localization: LocalizationStore
    let openConfig: (String, [String]) -> Void

    private let gap: CGFloat = 3

    var body: some View {
        let totalRows = MacKeyboardGeometry.rowHeights.reduce(0, +)
        GeometryReader { proxy in
            let unit = proxy.size.width / MacKeyboardGeometry.width
            ZStack(alignment: .topLeading) {
                ForEach(keys) { drawn in
                    keyView(drawn, unit: unit)
                }
            }
        }
        .aspectRatio(MacKeyboardGeometry.width / totalRows, contentMode: .fit)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
    }

    private func rowTop(_ row: Int) -> Double {
        MacKeyboardGeometry.rowHeights.prefix(row).reduce(0, +)
    }

    /// Haut et hauteur d'une touche, en unités, selon sa forme.
    private func span(_ key: MacKeyboardGeometry.Key) -> (top: Double, height: Double) {
        let rowH = MacKeyboardGeometry.rowHeights[key.row]
        let top = rowTop(key.row)
        switch key.shape {
        case .halfTop: return (top, rowH / 2)
        case .halfBottom: return (top + rowH / 2, rowH / 2)
        case .isoEnter: return (top, rowH + MacKeyboardGeometry.rowHeights[key.row + 1])
        case .normal: return (top, rowH)
        }
    }

    @ViewBuilder
    private func keyView(_ drawn: DrawnKey, unit: CGFloat) -> some View {
        let key = drawn.key
        let (top, height) = span(key)
        let width = CGFloat(key.width) * unit - gap
        let h = CGFloat(height) * unit - gap
        KeybindSurfaceButton(name: drawn.name, index: index, localization: localization,
                      openConfig: openConfig, shape: keyShape(key, width: width, height: h,
                                                              unit: unit)) {
            KeyCap(drawn: drawn, compact: unit < 40)
                .frame(width: width, height: h, alignment: .topLeading)
        }
        .frame(width: width, height: h)
        .offset(x: CGFloat(key.x) * unit + gap / 2, y: CGFloat(top) * unit + gap / 2)
    }

    private func keyShape(_ key: MacKeyboardGeometry.Key, width: CGFloat, height: CGFloat,
                          unit: CGFloat) -> AnyShape {
        if case .isoEnter(let notch) = key.shape {
            return AnyShape(IsoEnterShape(notchWidth: CGFloat(notch) * unit,
                                          notchHeight: CGFloat(MacKeyboardGeometry.rowHeights[key.row]) * unit))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// L'Entrée ISO : un L, encoche en bas à gauche.
private struct IsoEnterShape: Shape {
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + notchWidth, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + notchWidth, y: rect.minY + notchHeight))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notchHeight))
        p.closeSubpath()
        return p
    }
}

private struct KeyCap: View {
    let drawn: DrawnKey
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let glyph = drawn.key.glyph, glyph != "touchid" {
                Image(systemName: glyph).font(.system(size: compact ? 8 : 10))
            }
            if let shifted = drawn.shifted {
                Text(shifted).font(.system(size: compact ? 7 : 9)).foregroundStyle(.secondary)
            }
            if !drawn.legend.isEmpty {
                Text(drawn.legend)
                    .font(.system(size: drawn.key.label != nil ? (compact ? 7 : 8.5) : (compact ? 9 : 11),
                                  weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, compact ? 2 : 4)
        .padding(.vertical, compact ? 1 : 3)
    }
}

// MARK: - Une surface cliquable

/// Une touche, un bouton de souris ou de manette : coloré selon ses
/// réglages, popover au clic. Le conflit porte aussi un glyphe — jamais la
/// couleur seule (règle de l'axe H).
struct KeybindSurfaceButton<Content: View>: View {
    let name: String?
    let index: [String: [KeybindScanner.SettingBinding]]
    @ObservedObject var localization: LocalizationStore
    let openConfig: (String, [String]) -> Void
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 5))
    @ViewBuilder let label: () -> Content

    @State private var showing = false
    @State private var hovering = false

    private var bindings: [KeybindScanner.SettingBinding] { name.flatMap { index[$0] } ?? [] }
    private var kind: KeybindScanner.ConflictKind? { name.flatMap { KeybindDevicePlacement.conflict($0, in: index) } }
    private var conflict: Bool { kind != nil }

    var body: some View {
        let used = !bindings.isEmpty
        let tint = KeybindConflictStyle.color(kind)
        let fill: Color = used ? tint.opacity(0.16) : AppDesign.Color.controlBg
        let edge: Color = used ? tint : Color.secondary.opacity(0.35)
        let content = label()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Relief de capuchon : l'ombre de carte des jetons (I-T18).
            .background(shape.fill(fill)
                .shadow(color: .black.opacity(AppDesignCore.Shadow.card.opacity * 1.5),
                        radius: 0.5, y: 1))
            // Pointillés : une touche que le jeu ne lit pas.
            .overlay(shape.stroke(edge, style: StrokeStyle(lineWidth: used ? 1.5 : 0.75,
                                                           dash: name == nil ? [3, 2] : [])))
            .overlay(alignment: .bottomTrailing) {
                if used {
                    HStack(spacing: 1) {
                        if conflict { Image(systemName: KeybindConflictStyle.glyph) }
                        Text("\(bindings.count)")
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(tint)
                    .padding(2)
                }
            }
        if used {
            Button { showing = true } label: { content.contentShape(shape) }
                .buttonStyle(.plain)
                .pointingHandCursor()
                // Survol : la touche se soulève un peu — une seule animation,
                // qui respecte « réduire les animations » (`Motion`).
                .scaleEffect(hovering ? 1.06 : 1)
                .zIndex(hovering ? 1 : 0)
                .onHover { hovering = $0 }
                .animation(Motion.animation(.easeOut(duration: 0.12)), value: hovering)
                .accessibilityLabel(accessibility)
                .popover(isPresented: $showing, arrowEdge: .bottom) { popover }
        } else {
            content
                .opacity(name == nil ? 0.55 : 1)
                .help(name == nil ? localization.L(L10n.Keybinds.keyboardUnreadable) : "")
                .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        String(format: localization.L(L10n.Keybinds.keyboardA11y), name ?? "", Int64(bindings.count))
            + (conflict ? " — " + localization.L(L10n.Keybinds.keyboardConflict) : "")
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            HStack {
                Text(name ?? "").font(AppDesign.Font.body(.semibold))
                if conflict {
                    SwiftUI.Label(localization.L(L10n.Keybinds.keyboardConflict), systemImage: KeybindConflictStyle.glyph)
                        .font(AppDesign.Font.caption).foregroundColor(KeybindConflictStyle.color(kind))
                }
            }
            ForEach(bindings) { setting in
                HStack(spacing: AppDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(setting.modName).font(AppDesign.Font.caption(.medium))
                        Text(setting.keyPath.joined(separator: ".") + " = "
                             + setting.combos.map(\.display).joined(separator: ", "))
                            .font(AppDesign.Font.monoFootnote).foregroundColor(.secondary)
                    }
                    Spacer(minLength: AppDesign.Spacing.md)
                    if setting.hasConflict {
                        Image(systemName: KeybindConflictStyle.glyph)
                            .foregroundColor(KeybindConflictStyle.color(setting.conflict))
                            .accessibilityLabel(localization.L(L10n.Keybinds.keyboardConflict))
                    }
                    KeybindConfigButton(localization: localization) {
                        showing = false
                        openConfig(setting.modID, setting.keyPath)
                    }
                }
            }
        }
        .padding(AppDesign.Spacing.md)
        .frame(minWidth: 260, maxWidth: 420)
    }
}
