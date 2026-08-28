import SwiftUI

/// L'en-tête d'une section : son titre, un **compte honnête** de ce qui est
/// montré sur ce qui a été reçu (spec refonte §2, P2), et un seul bouton pour
/// deux gestes — déplier ce qui est déjà là, et demander la suite (P3).
///
/// `moreTitle` à `nil` retire le bouton : il n'y a plus rien à montrer.
struct SectionHeader: View {
    let title: String
    let countText: String
    let moreTitle: String?
    let moreDisabled: Bool
    let more: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text(countText)
                .font(.caption).foregroundStyle(.secondary)
            if let moreTitle {
                Button(moreTitle, action: more)
                    .buttonStyle(.link)
                    .disabled(moreDisabled)
            }
        }
    }
}
