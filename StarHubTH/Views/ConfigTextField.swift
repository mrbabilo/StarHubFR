import SwiftUI

/// Un champ texte de l'éditeur de config. Un secret (`ConfigSecretField` :
/// clé d'API, jeton, mot de passe) passe en champ masqué, comme la clé Nexus
/// des Réglages ; l'onglet JSON brut le montre encore, à la demande.
struct ConfigTextField: View {
    let isSecret: Bool
    @Binding var text: String

    var body: some View {
        Group {
            if isSecret {
                SecureField("", text: $text).textContentType(.password)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }
}
