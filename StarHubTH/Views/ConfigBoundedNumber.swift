import SwiftUI

/// D4-T7 — le curseur d'une option dont le mod déclare les bornes à GMCM, à
/// gauche du champ chiffré existant. Hors bornes (valeur tapée à la main),
/// ou sans bornes, le champ seul : un curseur ne montre pas une valeur qu'il
/// n'atteint pas. Le curseur écrit seulement quand on le déplace, et
/// toujours une valeur arrondie (`Bounds.snapped`).
struct ConfigBoundedNumber<Field: View>: View {
    let bounds: GmcmModOptions.Bounds?
    let isInteger: Bool
    let value: Binding<Double>
    @ViewBuilder let field: () -> Field

    var body: some View {
        HStack(spacing: 8) {
            if let bounds, bounds.contains(value.wrappedValue) {
                Slider(value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = bounds.snapped($0, integer: isInteger) }
                ), in: bounds.min...bounds.max)
                .controlSize(.small)
                .frame(minWidth: 60, maxWidth: 140)
            }
            field()
        }
    }
}
