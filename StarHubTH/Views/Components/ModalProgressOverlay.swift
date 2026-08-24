import SwiftUI

/// Le voile de progression des opérations qui remuent des dossiers de mods en
/// masse : bascule de tout le parc, application d'un profil.
///
/// Il est **bloquant** à dessein — pendant que `Mods/` est en cours de
/// réécriture, tout autre geste de l'utilisateur porterait sur un état qui
/// n'existe déjà plus.
///
/// Partagé plutôt que recopié : c'est le même voile pour la bascule en masse et
/// pour les profils, et deux copies finissent par diverger.
struct ModalProgressOverlay: View {
    /// Ce qui est en cours, en clair — « Application du profil… ».
    let label: String
    let done: Int
    let total: Int

    var body: some View {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        ZStack {
            Color.black.opacity(AppDesign.Opacity.strong)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: fraction, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 280)
                    .animation(.easeInOut(duration: 0.2), value: fraction)
                HStack(spacing: 6) {
                    Text(label)
                        .font(AppDesign.Font.caption(.medium))
                    Text("\(done)/\(total)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.lg))
            .shadow(color: .black.opacity(AppDesign.Opacity.medium), radius: 12, y: 4)
        }
        .transition(.opacity)
    }
}
