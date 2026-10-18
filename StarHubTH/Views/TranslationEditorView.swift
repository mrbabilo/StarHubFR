import SwiftUI

/// L'éditeur d'une clé : l'anglais en lecture seule, le français éditable.
///
/// Les deux zones sous le champ ont une **hauteur fixe**. Une zone qui
/// apparaît selon le contenu ferait sauter le champ de saisie d'une clé à
/// l'autre — insupportable quand on en enchaîne des centaines.
struct TranslationEditorView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    let locale: String
    let row: TranslationCoverage.DiffRow
    /// Les voisines de `row` dans l'ordre **affiché** — filtre compris. `nil`
    /// aux deux bouts de la liste.
    let previous: TranslationCoverage.DiffRow?
    let next: TranslationCoverage.DiffRow?
    /// Remplace la ligne éditée par sa voisine, sans refermer la feuille.
    let onNavigate: (TranslationCoverage.DiffRow) -> Void
    let onSaved: () -> Void
    @Binding var isPresented: Bool

    @State private var draft: String = ""
    @State private var blocked: [TranslationTokenCheck.Mismatch] = []
    /// Le verrou du bouton « Pré-traduire » pendant l'appel à l'IA locale.
    @State private var isPreTranslating = false
    /// Les termes du jeu matchés dans la source anglaise — calculés par ligne,
    /// pas à chaque frappe : le matching parcourt tout le glossaire.
    @State private var glossaryMatches: [GlossaryEntry] = []
    /// Le diagnostic d'un `.failed` : composant introuvable, `default.json`
    /// illisible, écriture refusée par le disque. Contrairement à `blocked`,
    /// **rien ici ne se remet à zéro quand `draft` change** — ce ne sont pas
    /// des désaccords sur le texte mais des pannes structurelles, qui
    /// resurgiraient identiques à la prochaine tentative. Effacer l'avis au
    /// premier caractère retapé donnerait l'illusion qu'un problème de
    /// dossier ou de disque s'est réglé tout seul ; il ne se réarme qu'au
    /// prochain appel de `save()`, jamais avant.
    @State private var failureMessage: TranslationEditorNotice?
    /// La ligne qu'on voulait rejoindre quand un refus de marques a interrompu
    /// la navigation. Sans elle, « Enregistrer quand même » refermait la
    /// feuille et l'intention se perdait en silence : il fallait rouvrir et
    /// refaire le geste.
    @State private var pendingNavigation: TranslationCoverage.DiffRow?
    /// Ce qui est sélectionné dans le panneau anglais, remonté par le pont
    /// AppKit — SwiftUI ne sait pas le dire avant macOS 15.
    @State private var sourceSelection = ""
    /// La traduction du fragment, en attente d'un clic. Elle ne s'écrit pas
    /// toute seule dans le brouillon : c'est une proposition sur un morceau,
    /// le traducteur décide où elle va.
    @State private var fragmentProposal: String?
    @State private var isTranslatingFragment = false

    /// Dédoublonnées et triées : la même marque répétée trois fois ne donne
    /// qu'une pastille, et l'ordre ne doit pas sauter d'une ouverture à l'autre.
    ///
    /// ⚠️ Ces pastilles montrent **toutes** les marques de la source, y compris
    /// les bornes `${` / `}$` d'un sélecteur de genre et le `^` qui les sépare.
    /// Le contrôle d'écriture, lui, ne compare pas ces trois-là : le français
    /// en ajoute légitimement (voir `TranslationTokenCheck.comparedTokens`).
    /// L'affichage promet donc un cran de plus que ce qui bloque — c'est voulu,
    /// une borne perdue reste une erreur à voir. Ne pas « aligner » le contrôle
    /// sur les pastilles.
    private var sourceTokens: [String] {
        Array(Set(TranslationTokenCheck.extract(row.english))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(row.key)
                .font(AppDesign.Font.monoCaption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            if let component = row.component {
                Text(component)
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(AppDesign.Color.dimmedSecondary(AppDesign.Opacity.secondary))
            }

            Text(localization.L(L10n.Mods.translationEditorSource))
                .font(AppDesign.Font.footnote(.semibold))
                .foregroundColor(.secondary)
            // Le pont AppKit remplace un `Text` sélectionnable : c'est la
            // sélection **lue** qui manquait, pas la sélection elle-même.
            SelectableTextView(
                text: row.english,
                selection: $sourceSelection,
                actionTitle: localization.L(L10n.Mods.translationEditorTranslateSelectionMenu),
                action: { Task { await translateSelection() } })
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(Color.primary.opacity(AppDesign.Opacity.subtle))
                .cornerRadius(AppDesign.Radius.sm)

            selectionRow.frame(minHeight: 24, alignment: .leading)

            Text(localization.L(L10n.Mods.translationEditorTarget))
                .font(AppDesign.Font.footnote(.semibold))
                .foregroundColor(.secondary)
            TextEditor(text: $draft)
                .font(AppDesign.Font.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.primary.opacity(AppDesign.Opacity.medium), lineWidth: 1))

            tokenChips.frame(minHeight: 46, alignment: .topLeading)
            // Réserve minimale : la feuille ne danse pas quand une rangée
            // apparaît, mais peut grandir si les termes doivent se replier.
            glossaryChips.frame(minHeight: 24, alignment: .topLeading)
            // 90pt minimum, pas plafond : le texte à 130 % reste entier.
            statusNotice.frame(minHeight: 90, alignment: .topLeading)

            footer
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 560, minHeight: 580)
        .onAppear {
            draft = row.french
            glossaryMatches = viewModel.glossaryMatches(for: row.english, language: locale)
        }
        // `.sheet(item:)` peut réutiliser cette vue en changeant seulement
        // `row` : `onAppear` ne se redéclencherait pas, et le brouillon de la
        // ligne précédente s'écrirait dans la suivante. On réarme donc sur
        // l'identité de la ligne, pas sur l'apparition de la vue.
        .onChange(of: row.id) { _, _ in
            draft = row.french
            blocked = []
            failureMessage = nil
            pendingNavigation = nil
            glossaryMatches = viewModel.glossaryMatches(for: row.english, language: locale)
        }
        // Retoucher la phrase remet le refus de tokens à zéro : l'accord porte
        // sur un couple source/cible précis, et la cible vient de changer.
        // `failureMessage` n'est volontairement pas concerné, voir sa
        // déclaration ci-dessus.
        .onChange(of: draft) { _, _ in blocked = [] }
    }

    /// Navigation à gauche, validation à droite. À la largeur minimale, le
    /// second groupe passe sous le premier au lieu de comprimer ses libellés.
    private var footer: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) {
            // Pré-traduire remplit seulement le brouillon : Enregistrer reste
            // le seul chemin d'écriture.
            Button {
                Task { await preTranslate() }
            } label: {
                if isPreTranslating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                }
            }
            .disabled(isPreTranslating)
            .help(isPreTranslating
                  ? localization.L(L10n.Mods.translationEditorPretranslating)
                  : localization.L(L10n.Mods.translationEditorPretranslate))
            .accessibilityLabel(localization.L(L10n.Mods.translationEditorPretranslate))

            Button { navigate(to: previous) } label: { Image(systemName: "chevron.left") }
                .disabled(previous == nil)
                .help(localization.L(L10n.Mods.translationEditorPrevious))
                .accessibilityLabel(localization.L(L10n.Mods.translationEditorPrevious))

            Button { navigate(to: next) } label: { Image(systemName: "chevron.right") }
                .disabled(next == nil)
                .help(localization.L(L10n.Mods.translationEditorNext))
                .accessibilityLabel(localization.L(L10n.Mods.translationEditorNext))

            Button(localization.L(L10n.Mods.translationEditorKeepEnglish)) { draft = row.english }
        } trailing: {
            Button(localization.L(L10n.Mods.translationEditorCancel)) { isPresented = false }
            // Proposé seulement après un refus de marques : un échec d'écriture
            // structurel n'a rien à forcer.
            if !blocked.isEmpty {
                Button(localization.L(L10n.Mods.translationEditorSaveAnyway)) {
                    save(acceptingMismatch: true)
                }
            }
            Button(localization.L(L10n.Mods.translationEditorSave)) { save() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Les marques du jeu présentes dans la source, cliquables : les retaper à
    /// la main est la première cause de mod cassé.
    @ViewBuilder private var tokenChips: some View {
        if sourceTokens.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text(localization.L(L10n.Mods.translationEditorTokens))
                    .font(AppDesign.Font.iconXS(.semibold))
                    .foregroundColor(.secondary)
                WrapHStack(spacing: 6, lineSpacing: AppDesign.Spacing.xs) {
                    ForEach(sourceTokens, id: \.self) { token in
                        Button { draft += token } label: {
                            Text(token)
                                .font(AppDesign.Font.monoFootnote)
                                .padding(.horizontal, AppDesign.Spacing.sm)
                                .padding(.vertical, AppDesign.Spacing.xs)
                                .background(Color.accentColor.opacity(AppDesign.Opacity.light))
                                .cornerRadius(AppDesign.Radius.sm)
                        }
                        .buttonStyle(.plain).focusRing(cornerRadius: AppDesign.Radius.sm)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    /// Le geste de la sélection et son résultat sur la **même** rangée, sous
    /// la source : l'action près de ce sur quoi elle porte, et une hauteur qui
    /// ne bouge pas selon qu'une pastille est là ou non.
    @ViewBuilder private var selectionRow: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) {
            Button(localization.L(L10n.Mods.translationEditorTranslateSelection)) {
                Task { await translateSelection() }
            }
            .controlSize(.small)
            .disabled(sourceSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || isTranslatingFragment)
            if isTranslatingFragment {
                ProgressView().controlSize(.small)
            }
        } trailing: {
            if let proposal = fragmentProposal, !isTranslatingFragment {
                // Même mécanique que les chips de glossaire : cliquer insère.
                Button { draft += proposal } label: {
                    Text(proposal)
                        .font(AppDesign.Font.footnote)
                        .lineLimit(1)
                        .padding(.horizontal, AppDesign.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(AppDesign.Opacity.medium))
                        .cornerRadius(AppDesign.Radius.sm)
                }
                .buttonStyle(.plain).focusRing(cornerRadius: AppDesign.Radius.sm)
                .pointingHandCursor()
                .help(proposal)
            }
        }
    }

    /// Traduit ce qui est sélectionné dans la source, la phrase entière en
    /// contexte. Les refus réutilisent `failureMessage` : ce sont des pannes
    /// ou des règles, pas un désaccord sur le texte tapé.
    private func translateSelection() async {
        isTranslatingFragment = true
        defer { isTranslatingFragment = false }
        fragmentProposal = nil
        switch await viewModel.translateFragment(sourceSelection, inside: row.english) {
        case .proposal(let text):
            fragmentProposal = text
        case .refusedMarkers(let markers):
            failureMessage = .init(text: String(format: localization.L(L10n.Mods.translationEditorSelectionMarkers),
                                                markers.joined(separator: ", ")))
        case .noFallback:
            failureMessage = localization.notice(.noFallback)
        case .nothingSelected:
            break
        case .fallbackStopped(let stop):
            failureMessage = localization.notice(.stopped(stop))
        case .failed:
            failureMessage = .init(text: localization.L(L10n.Mods.translationEditorPretranslateFailed))
        }
    }

    /// Les termes du jeu matchés dans la source, en `EN → FR` monospace :
    /// cliquer insère la forme française, la même mécanique que les chips de
    /// marques — l'IA locale impose ces mêmes termes dans son prompt, ce sont
    /// les mêmes matchs (`viewModel.glossaryMatches`).
    @ViewBuilder private var glossaryChips: some View {
        if glossaryMatches.isEmpty {
            EmptyView()
        } else {
            WrapHStack(spacing: 6, lineSpacing: AppDesign.Spacing.xs) {
                ForEach(glossaryMatches, id: \.en) { entry in
                    Button { draft += entry.fr } label: {
                        Text("\(entry.en) → \(entry.fr)")
                            .font(AppDesign.Font.monoFootnote)
                            .padding(.horizontal, AppDesign.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(AppDesign.Opacity.light))
                            .cornerRadius(AppDesign.Radius.sm)
                    }
                    .buttonStyle(.plain).focusRing(cornerRadius: AppDesign.Radius.sm)
                    .pointingHandCursor()
                    .help("\(localization.L(L10n.Mods.translationEditorGlossary)) : \(entry.en) → \(entry.fr)")
                }
            }
            .help(localization.L(L10n.Mods.translationEditorGlossary))
        }
    }

    /// Demande une proposition à l'IA locale et la verse dans le brouillon.
    /// L'échec réutilise `failureMessage` — c'est une panne structurelle
    /// (serveur injoignable, non configuré), pas un désaccord sur le texte :
    /// retaper la phrase n'y changera rien, et l'avis ne doit pas s'effacer
    /// au premier caractère, pour la même raison que celui de `save()`.
    private func preTranslate() async {
        // Rien à demander sans IA réglée : la panne serait annoncée comme un
        // serveur muet, alors qu'il n'y a pas de serveur. Le lot cache son
        // bouton dans ce cas (spec §7) ; ici il reste, mais il dit où aller.
        guard viewModel.isTranslationAssistAvailable else {
            failureMessage = localization.notice(.noEngine)
            return
        }
        isPreTranslating = true
        defer { isPreTranslating = false }
        switch await viewModel.preTranslate(mod: mod, locale: locale, row: row) {
        case .proposal(let proposal):
            draft = proposal
        case .fallbackStopped(let stop):
            // Nommer la cause : sur ce chemin on reclique, et un message
            // générique ferait retenter une clé que le service ne rendra pas.
            failureMessage = localization.notice(.stopped(stop))
        case .failed:
            failureMessage = .init(text: localization.L(L10n.Mods.translationEditorPretranslateFailed))
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
    /// **Hauteur minimale de la zone (90pt) : dimensionnée sur le pire cas,
    /// sans plafonner les textes agrandis.** Les messages de `.failed`
    /// embarquent des chemins absolus —
    /// `StarHubTHViewModel.saveTranslation` en construit un jusqu'à ~315
    /// caractères sur un vrai chemin d'installation Steam et un nom de mod
    /// verbeux (« …est en layout B — créer un fichier à la racine
    /// casserait… »). À ~80 caractères par ligne sur les 520pt de large
    /// utiles du panneau (largeur du sheet 560, moins 2×20 de marge, à 10pt),
    /// ça fait jusqu'à 5 lignes ≈ 65pt, plus l'intitulé (14pt) et
    /// l'espacement (3pt) : 82pt. Le blocage de tokens, ses écarts et ceux
    /// à vérifier sur 3 lignes (42pt) et son indice sur 2 lignes (26pt),
    /// atteint 71pt. 90pt couvre les deux avec une marge. Ni le message
    /// d'échec, ni le blocage, ni l'indice n'ont de `lineLimit` : un texte plus long que
    /// prévu déborde du cadre plutôt que d'être coupé — jamais invisible,
    /// jamais tronqué, toujours sélectionnable.
    @ViewBuilder private var statusNotice: some View {
        if let failureMessage {
            VStack(alignment: .leading, spacing: 3) {
                // Seule cette ligne est localisée : c'est l'unique constat que
                // le traducteur ne peut pas se permettre de manquer, quelle
                // que soit sa langue d'UI.
                Text(localization.L(L10n.Mods.translationEditorFailed))
                    .font(AppDesign.Font.footnote(.semibold))
                    .foregroundColor(.red.opacity(0.85))
                // Le diagnostic, verbatim : c'est exactement la phrase posée
                // dans le journal (`log(...)` côté ViewModel), donc greppable
                // en cas de rapport de bug — mais seulement s'il reste
                // entier et copiable. Ni `lineLimit` (il embarque des
                // chemins absolus, potentiellement longs) ni troncature :
                // `.textSelection` porte sur le texte complet, jamais sur un
                // « … » qui aurait avalé la moitié d'un chemin.
                Text(failureMessage.text)
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                if let section = failureMessage.settings {
                    // N-11. Ouvrir les Réglages ferme la feuille : grisé si un brouillon s'y perdrait.
                    SettingsLinkButton(section: section, title: localization.L(L10n.TranslationAssist.openSettings),
                                       navigation: viewModel.navigationStore) { isPresented = false }
                        .disabled(draft != row.french)
                        .help(draft != row.french ? localization.L(L10n.TranslationAssist.saveFirst) : "")
                }
            }
        } else if !blocked.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                // Nommer chaque marque et son sens (manquante, en trop)
                // plutôt qu'en donner le nombre, puis ce qui n'est qu'à
                // vérifier : la contrepartie d'une faute (le `$h` perdu sous
                // un `#$h` ajouté) est souvent un simple avertissement. Pas
                // de `lineLimit` : un libellé coupé cacherait une marque.
                Text(TranslationMismatchText.blocked(blocked, english: row.english, draft: draft, localization))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.red.opacity(0.85))
                // Pas de `lineLimit` : c'est l'information la plus
                // importante de tout l'écran — c'est elle qui explique le
                // bouton juste en dessous — et à 155 caractères en français
                // elle ne tient déjà pas sur une ligne.
                Text(localization.L(L10n.Mods.translationEditorMismatchHint))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }
        } else {
            TranslationWarningNote(english: row.english, draft: draft, localization: localization)
        }
    }

    /// Passe à une voisine — **en enregistrant d'abord** si le texte a changé.
    ///
    /// Naviguer en abandonnant une modification perdrait le travail sans le
    /// dire, ce qui est le pire résultat possible ici. Et si l'enregistrement
    /// est refusé — marque du jeu manquante, ou panne — on ne bouge pas : le
    /// motif s'affiche sur la ligne qu'il concerne, pas sur la suivante.
    private func navigate(to target: TranslationCoverage.DiffRow?) {
        guard let target else { return }
        if draft != row.french {
            failureMessage = nil
            switch viewModel.saveTranslation(mod: mod, locale: locale, row: row, value: draft) {
            case .saved:
                blocked = []
                onSaved()
            case .blocked(let mismatches):
                blocked = mismatches
                // On retient où l'on allait : accepter la divergence doit
                // reprendre le voyage, pas le clore.
                pendingNavigation = target
                return
            case .failed(let message):
                blocked = []
                failureMessage = .init(text: message)
                // Même raison que pour un refus de marques, et surtout : sans
                // cette ligne, `.failed` était la seule branche à ne rien dire
                // de l'intention. Elle laissait donc en place celle d'un aller
                // précédent — demander la suivante, échouer, puis demander la
                // précédente et échouer encore faisait repartir vers la
                // *suivante* au premier enregistrement réussi, à l'opposé du
                // dernier geste.
                pendingNavigation = target
                return
            }
        }
        pendingNavigation = nil
        onNavigate(target)
    }

    private func save(acceptingMismatch: Bool = false) {
        // Rien n'a changé : fermer sans écrire. Sans cette garde, cliquer
        // Enregistrer sur une ligne `.empty` sans y toucher (`draft` et
        // `row.french` valent tous deux `""`) supprimait la clé du fichier —
        // un effet de bord sur un clic qui n'a l'air de rien faire, et qui
        // change pourtant le comportement en jeu (retour au repli anglais).
        guard draft != row.french else {
            isPresented = false
            return
        }

        // Effacé avant l'appel, pas dans `onChange(of: draft)` : un ancien
        // échec ne doit pas rester affiché après un nouveau succès, mais ne
        // doit pas non plus disparaître avant qu'on sache si la nouvelle
        // tentative a réussi.
        failureMessage = nil
        switch viewModel.saveTranslation(mod: mod, locale: locale, row: row, value: draft,
                                  acceptingTokenMismatch: acceptingMismatch) {
        case .saved:
            blocked = []
            onSaved()
            // Reprendre le voyage interrompu par le refus, plutôt que de
            // refermer sur une intention avortée.
            if let target = pendingNavigation {
                pendingNavigation = nil
                onNavigate(target)
            } else {
                isPresented = false
            }
        case .blocked(let mismatches):
            blocked = mismatches
        case .failed(let message):
            blocked = []
            failureMessage = .init(text: message)
        }
    }
}
