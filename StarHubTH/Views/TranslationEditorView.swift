import SwiftUI

/// L'éditeur d'une clé : l'anglais en lecture seule, le français éditable.
///
/// Les deux zones sous le champ ont une **hauteur fixe**. Une zone qui
/// apparaît selon le contenu ferait sauter le champ de saisie d'une clé à
/// l'autre — insupportable quand on en enchaîne des centaines.
struct TranslationEditorView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    let locale: String
    let row: TranslationCoverage.DiffRow
    let onSaved: () -> Void
    @Binding var isPresented: Bool

    @State private var draft: String = ""
    @State private var blocked: [TranslationTokenCheck.Mismatch] = []
    /// Le diagnostic d'un `.failed` : composant introuvable, `default.json`
    /// illisible, écriture refusée par le disque. Contrairement à `blocked`,
    /// **rien ici ne se remet à zéro quand `draft` change** — ce ne sont pas
    /// des désaccords sur le texte mais des pannes structurelles, qui
    /// resurgiraient identiques à la prochaine tentative. Effacer l'avis au
    /// premier caractère retapé donnerait l'illusion qu'un problème de
    /// dossier ou de disque s'est réglé tout seul ; il ne se réarme qu'au
    /// prochain appel de `save()`, jamais avant.
    @State private var failureMessage: String?

    /// Dédoublonnées et triées : la même marque répétée trois fois ne donne
    /// qu'une pastille, et l'ordre ne doit pas sauter d'une ouverture à l'autre.
    private var sourceTokens: [String] {
        Array(Set(TranslationTokenCheck.extract(row.english))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            if let component = row.component {
                Text(component)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }

            Text(vm.L(L10n.Mods.translationEditorSource))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(row.english)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)

            Text(vm.L(L10n.Mods.translationEditorTarget))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1))

            tokenChips.frame(height: 46, alignment: .topLeading)
            // 90pt, pas 36 : dimensionné sur le pire cas réaliste, pas la
            // moyenne. Voir le calcul au-dessus de `statusNotice`.
            statusNotice.frame(height: 90, alignment: .topLeading)

            HStack {
                Button(vm.L(L10n.Mods.translationEditorKeepEnglish)) { draft = row.english }
                Spacer()
                Button(vm.L(L10n.Mods.translationEditorCancel)) { isPresented = false }
                // N'apparaît **qu'après** un refus : offert d'emblée, il
                // inviterait à contourner la vérification avant même de l'avoir
                // lue. N'a de sens que pour un blocage de tokens — un `.failed`
                // n'a rien à « forcer », le problème n'est pas dans le texte.
                if !blocked.isEmpty {
                    Button(vm.L(L10n.Mods.translationEditorSaveAnyway)) { save(acceptingMismatch: true) }
                }
                Button(vm.L(L10n.Mods.translationEditorSave)) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 540)
        .onAppear { draft = row.french }
        // Retoucher la phrase remet le refus de tokens à zéro : l'accord porte
        // sur un couple source/cible précis, et la cible vient de changer.
        // `failureMessage` n'est volontairement pas concerné, voir sa
        // déclaration ci-dessus.
        .onChange(of: draft) { _, _ in blocked = [] }
    }

    /// Les marques du jeu présentes dans la source, cliquables : les retaper à
    /// la main est la première cause de mod cassé.
    @ViewBuilder private var tokenChips: some View {
        if sourceTokens.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.L(L10n.Mods.translationEditorTokens))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(sourceTokens, id: \.self) { token in
                        Button { draft += token } label: {
                            Text(token)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    /// Ce que `save()` a refusé, quelle qu'en soit la raison — jamais les
    /// deux en même temps, `save()` ne pose que l'un des deux `@State`.
    ///
    /// Deux causes de refus, une seule zone : un blocage de tokens (le texte
    /// pose problème, on peut le corriger ou passer outre) et un échec
    /// structurel (rien à voir avec ce qui a été tapé). Les mélanger dans le
    /// même texte aurait fait perdre au traducteur la marque manquante sous
    /// un message générique — ou l'inverse, fait chercher une divergence de
    /// tokens dans une simple panne d'écriture disque.
    ///
    /// **Hauteur de la zone (90pt) : dimensionnée sur le pire cas, pas la
    /// moyenne.** Les messages de `.failed` embarquent des chemins absolus —
    /// `StarHubTHViewModel.saveTranslation` en construit un jusqu'à ~315
    /// caractères sur un vrai chemin d'installation Steam et un nom de mod
    /// verbeux (« …est en layout B — créer un fichier à la racine
    /// casserait… »). À ~80 caractères par ligne sur les 520pt de large
    /// utiles du panneau (largeur du sheet 560, moins 2×20 de marge, à 10pt),
    /// ça fait jusqu'à 5 lignes ≈ 65pt, plus l'intitulé (14pt) et
    /// l'espacement (3pt) : 82pt. Le blocage de tokens, avec sa marque
    /// manquante sur 3 lignes (42pt) et son indice sur 2 lignes (26pt),
    /// atteint 71pt. 90pt couvre les deux avec une marge. Ni le message
    /// d'échec ni l'indice n'ont de `lineLimit` : un texte plus long que
    /// prévu déborde du cadre plutôt que d'être coupé — jamais invisible,
    /// jamais tronqué, toujours sélectionnable.
    @ViewBuilder private var statusNotice: some View {
        if let failureMessage {
            VStack(alignment: .leading, spacing: 3) {
                // Seule cette ligne est localisée : c'est l'unique constat que
                // le traducteur ne peut pas se permettre de manquer, quelle
                // que soit sa langue d'UI.
                Text(vm.L(L10n.Mods.translationEditorFailed))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red.opacity(0.85))
                // Le diagnostic, verbatim : c'est exactement la phrase posée
                // dans le journal (`log(...)` côté ViewModel), donc greppable
                // en cas de rapport de bug — mais seulement s'il reste
                // entier et copiable. Ni `lineLimit` (il embarque des
                // chemins absolus, potentiellement longs) ni troncature :
                // `.textSelection` porte sur le texte complet, jamais sur un
                // « … » qui aurait avalé la moitié d'un chemin.
                Text(failureMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        } else if !blocked.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                // Nommer les marques manquantes plutôt qu'en donner le
                // nombre : le traducteur doit pouvoir juger si l'absence est
                // voulue — une phrase française neutre n'a que faire d'un
                // sélecteur de genre. `lineLimit(3)` plutôt que 2 : au-delà
                // de quatre ou cinq marques distinctes, deux lignes ne
                // suffisent déjà plus.
                Text(String(format: vm.L(L10n.Mods.translationEditorBlocked), Int64(blocked.count))
                     + "  " + blocked.map(\.token).joined(separator: "  "))
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                    .lineLimit(3)
                // Pas de `lineLimit` : c'est l'information la plus
                // importante de tout l'écran — c'est elle qui explique le
                // bouton juste en dessous — et à 155 caractères en français
                // elle ne tient déjà pas sur une ligne.
                Text(vm.L(L10n.Mods.translationEditorMismatchHint))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        } else {
            EmptyView()
        }
    }

    private func save(acceptingMismatch: Bool = false) {
        // Effacé avant l'appel, pas dans `onChange(of: draft)` : un ancien
        // échec ne doit pas rester affiché après un nouveau succès, mais ne
        // doit pas non plus disparaître avant qu'on sache si la nouvelle
        // tentative a réussi.
        failureMessage = nil
        switch vm.saveTranslation(mod: mod, locale: locale, row: row, value: draft,
                                  acceptingTokenMismatch: acceptingMismatch) {
        case .saved:
            blocked = []
            onSaved()
            isPresented = false
        case .blocked(let mismatches):
            blocked = mismatches
        case .failed(let message):
            blocked = []
            failureMessage = message
        }
    }
}
