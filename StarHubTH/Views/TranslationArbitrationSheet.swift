import SwiftUI

/// C3-T5 — la feuille de fusion d'un lot reçu d'un autre humain.
///
/// Elle montre, mod par mod, ce que le lot propose : les traductions
/// nouvelles (écrites d'un coup), les divergences avec ce qui est déjà en
/// place (à arbitrer — d'un coup, puis ligne par ligne), et ce qui ne dit
/// rien (identique, non rempli, écarté). L'écriture passe par la closure du
/// parent — le chemin éprouvé de `saveTranslation` — **après** re-lecture des
/// rangées : une divergence dont l'anglais a bougé pendant la feuille
/// ouverte est abandonnée et nommée, jamais écrite sur l'ancien anglais.
struct TranslationArbitrationSheet: View {
    let store: TranslationLotMergeStore
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Re-lecture des rangées d'un mod au moment d'écrire.
    let freshRows: (ModItem) async -> [TranslationCoverage.DiffRow]
    /// Appelé avec le total écrit : le parent recharge ses rangées — et ne
    /// cadre sur « À relire » que si quelque chose a effectivement été écrit.
    let onWrote: (Int) -> Void
    let onClose: () -> Void

    @State private var result: String?
    @State private var writing = false

    private var totalWritable: Int { store.reviews.reduce(0) { $0 + $1.writableCount } }
    private var totalDivergent: Int { store.reviews.reduce(0) { $0 + $1.divergenceCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                Text(result)
                    .font(AppDesign.Font.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(localization.L(L10n.Mods.translationBatchClose)) { onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(localization.L(L10n.Mods.translationLotMergeTitle))
                    .font(.system(size: AppDesign.Font.scaled(15), weight: .semibold))
                summary
                List {
                    ForEach(store.reviews) { review in
                        ModSection(review: review, store: store, localization: localization)
                    }
                    refusalsSection
                }
                .listStyle(.inset)
                HStack {
                    Spacer()
                    Button(localization.L(L10n.Mods.translationBatchCancel)) { onClose() }
                        .keyboardShortcut(.cancelAction)
                    Button(String(format: localization.L(L10n.Mods.translationLotMergeWrite),
                                  Int64(totalWritable))) {
                        write()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(writing || totalWritable == 0)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
    }

    @ViewBuilder
    private var summary: some View {
        let counts = store.reviews.reduce((0, 0, 0, 0)) { acc, review in
            let d = review.review.proposals
            func count(_ disposition: TranslationLotMerge.Disposition) -> Int {
                d.filter { $0.disposition == disposition }.count
            }
            return (acc.0 + count(.writeNow), acc.1 + count(.divergent),
                    acc.2 + count(.identical), acc.3 + count(.unfilled))
        }
        HStack(spacing: 12) {
            Label(String(format: localization.L(L10n.Mods.translationLotMergeWriteNow),
                         Int64(counts.0)), systemImage: "plus.circle")
            Label(String(format: localization.L(L10n.Mods.translationLotMergeDivergent),
                         Int64(counts.1)), systemImage: "arrow.left.arrow.right")
            Label(String(format: localization.L(L10n.Mods.translationLotMergeIdentical),
                         Int64(counts.2)), systemImage: "equal.circle")
            Label(String(format: localization.L(L10n.Mods.translationLotMergeUnfilled),
                         Int64(counts.3)), systemImage: "minus.circle")
        }
        .font(AppDesign.Font.caption)
        .foregroundColor(.secondary)
        .help(localization.L(L10n.Mods.translationLotMergeLegend))
    }

    @ViewBuilder
    private var refusalsSection: some View {
        let all = store.refusals.sorted(by: { $0.key < $1.key })
        if !all.isEmpty || !store.unknownFolders.isEmpty {
            Section(localization.L(L10n.Mods.translationLotMergeRefused)) {
                ForEach(all, id: \.key) { entry in
                    Text("\(entry.key) — \(refusalMessage(entry.value))")
                        .font(AppDesign.Font.monoIconXS)
                        .foregroundColor(.secondary)
                }
                ForEach(store.unknownFolders, id: \.self) { folder in
                    Text("\(folder) — "
                         + String(format: localization.L(L10n.Mods.translationLotUnknownMod),
                                  folder))
                        .font(AppDesign.Font.monoIconXS)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func write() {
        writing = true
        Task {
            var written = 0
            var dropped = 0
            var failures = 0
            for review in store.reviews where review.writableCount > 0 {
                let rows = await freshRows(review.mod)
                let outcome = store.apply(modID: review.mod.folderName, freshRows: rows) {
                    mod, row, value in
                    viewModel.saveTranslation(mod: mod, locale: "fr", row: row, value: value,
                                       clearingReviewFlag: false)
                }
                written += outcome.written
                dropped += outcome.dropped.count
                failures += outcome.failures
            }
            viewModel.log("Lot fusionné : \(written) écrites, \(dropped) abandonnées "
                   + "(l'anglais a bougé), \(failures) en échec", level: .info)
            result = String(format: localization.L(L10n.Mods.translationLotMergeResult),
                            Int64(written), Int64(dropped), Int64(failures))
            if written > 0 { onWrote(written) }
            writing = false
        }
    }

    private func refusalMessage(_ refusal: TranslationLotMerge.FileRefusal) -> String {
        switch refusal {
        case .staleLot: return localization.L(L10n.Mods.translationLotStale)
        case .wrongMod: return localization.L(L10n.Mods.translationLotWrongMod)
        case .unreadable, .wrongLanguage, .unsupportedFormat:
            return localization.L(L10n.Mods.translationLotUnreadable)
        }
    }
}

/// Le bloc d'un mod : comptes, penchants d'un coup, puis la liste des
/// divergences — l'anglais en référence, le français en place face à la
/// valeur reçue.
private struct ModSection: View {
    let review: TranslationLotMergeStore.ModReview
    let store: TranslationLotMergeStore
    @ObservedObject var localization: LocalizationStore

    private var divergent: [TranslationLotMerge.Proposal] {
        review.review.proposals.filter { $0.disposition == .divergent }
    }

    var body: some View {
        Section(review.mod.name) {
            counts
            if !divergent.isEmpty {
                HStack(spacing: 8) {
                    Button(localization.L(L10n.Mods.translationLotMergeMine)) {
                        store.leanAll(review.id, incoming: false)
                    }
                    Button(localization.L(L10n.Mods.translationLotMergeTheirs)) {
                        store.leanAll(review.id, incoming: true)
                    }
                    Spacer()
                }
                .font(AppDesign.Font.caption)
                ForEach(divergent, id: \.self) { proposal in
                    DivergenceRow(review: review, proposal: proposal,
                                  store: store, localization: localization)
                }
            }
            if !review.review.rejections.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(review.review.rejections.prefix(20).enumerated()),
                            id: \.offset) { _, rejection in
                        Text(rejectionLabel(rejection))
                            .font(AppDesign.Font.monoIconXS)
                            .foregroundColor(.secondary)
                    }
                    if review.review.rejections.count > 20 {
                        Text("…").font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var counts: some View {
        HStack(spacing: 12) {
            Text(String(format: localization.L(L10n.Mods.translationLotMergeWriteNow),
                        Int64(countOf(.writeNow))))
            Text(String(format: localization.L(L10n.Mods.translationLotMergeDivergent),
                        Int64(countOf(.divergent))))
            if countOf(.identical) > 0 {
                Text(String(format: localization.L(L10n.Mods.translationLotMergeIdentical),
                            Int64(countOf(.identical))))
            }
            if countOf(.unfilled) > 0 {
                Text(String(format: localization.L(L10n.Mods.translationLotMergeUnfilled),
                            Int64(countOf(.unfilled))))
            }
        }
        .font(AppDesign.Font.caption)
        .foregroundColor(.secondary)
    }

    private func countOf(_ disposition: TranslationLotMerge.Disposition) -> Int {
        review.review.proposals.filter { $0.disposition == disposition }.count
    }

    private func rejectionLabel(_ rejection: TranslationLotImport.Rejection) -> String {
        let key = rejection.component.map { "\($0)/\(rejection.key)" } ?? rejection.key
        return "\(key) — \(reasonLabel(rejection.reason))"
    }

    private func reasonLabel(_ reason: TranslationLotImport.Rejection.Reason) -> String {
        switch reason {
        case .missingHardMarkers(let markers):
            return String(format: localization.L(L10n.Mods.translationLotReasonMissingMarkers),
                          markers.joined(separator: ", "))
        case .extraHardMarkers(let markers):
            return String(format: localization.L(L10n.Mods.translationLotReasonExtraMarkers),
                          markers.joined(separator: ", "))
        case .unknownKey:
            return localization.L(L10n.Mods.translationLotReasonUnknownKey)
        case .sourceAltered:
            return localization.L(L10n.Mods.translationLotReasonSourceAltered)
        }
    }
}

/// Une divergence : la décision en tête, les deux français côte à côte
/// dessous — celui en place et celui reçu — sous l'anglais de référence.
private struct DivergenceRow: View {
    let review: TranslationLotMergeStore.ModReview
    let proposal: TranslationLotMerge.Proposal
    let store: TranslationLotMergeStore
    @ObservedObject var localization: LocalizationStore

    private var identity: String { review.identity(of: proposal) }
    private var decision: Bool? { review.takeIncoming[identity] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Picker("", selection: Binding(
                    get: { decision },
                    set: { store.lean(review.id, identity: identity, incoming: $0) })) {
                    Text(localization.L(L10n.Mods.translationLotMergeUndecided))
                        .tag(Bool?.none)
                    Text(localization.L(L10n.Mods.translationLotMergeMineShort))
                        .tag(Bool?.some(false))
                    Text(localization.L(L10n.Mods.translationLotMergeTheirsShort))
                        .tag(Bool?.some(true))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.key)
                        .font(AppDesign.Font.monoIconXS)
                        .foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(proposal.source)
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    HStack(alignment: .top, spacing: 10) {
                        Text(proposal.currentFrench)
                            .font(AppDesign.Font.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                        Text(proposal.incoming)
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                    }
                }
            }
            Divider()
        }
        .help("\(localization.L(L10n.Mods.translationLotMergeMineShort)) : \(proposal.currentFrench) · "
              + "\(localization.L(L10n.Mods.translationLotMergeTheirsShort)) : \(proposal.incoming)")
    }
}
