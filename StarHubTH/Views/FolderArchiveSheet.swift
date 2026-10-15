import AppKit
import SwiftUI

/// Ce qu'une feuille d'archive doit savoir de sa source, préparé par le
/// bouton qui l'ouvre.
struct FolderArchiveRequest: Identifiable {
    let kind: FolderArchiveStore.Kind
    let source: URL
    let filePrefix: String
    /// « 966 mods, dont 809 en pause » — déjà traduit.
    let summary: String
    /// Le poids déjà mesuré au scan, `nil` s'il faut le mesurer.
    let knownBytes: Int64?

    var id: String { kind.rawValue }

    /// Tout `Mods/`, mods en pause compris : un mod en pause est un dossier
    /// `.X` dans `Mods/`, et `zip -r .` l'emporte comme les autres.
    @MainActor
    static func mods(from viewModel: StarHubTHViewModel, _ localization: LocalizationStore) -> FolderArchiveRequest? {
        guard !viewModel.gameDir.isEmpty else { return nil }
        let mods = viewModel.mods
        let paused = mods.filter { !$0.isEnabled }.count
        return FolderArchiveRequest(
            kind: .mods,
            source: URL(fileURLWithPath: viewModel.gameDir).appendingPathComponent("Mods", isDirectory: true),
            filePrefix: "StardewMods",
            summary: String(format: localization.L(L10n.Archive.modsSummary), Int64(mods.count), Int64(paused)),
            knownBytes: viewModel.modsFolderSizes?.totalBytes)
    }

    static func saves(_ localization: LocalizationStore) -> FolderArchiveRequest {
        let source = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/StardewValley/Saves", isDirectory: true)
        let count = visibleFolderCount(in: source)
        return FolderArchiveRequest(
            kind: .saves, source: source, filePrefix: "StardewSaves",
            summary: String(format: localization.L(L10n.Archive.savesSummary), Int64(count)),
            knownBytes: nil)
    }

    /// Dossiers visibles directement sous `folder` — une partie par dossier.
    private static func visibleFolderCount(in folder: URL) -> Int {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { !$0.hasPrefix(".") }.count
        } catch {
            return 0
        }
    }
}

/// Feuille « Sauvegarder… » : ce qui part, où, si la place suffit, combien de
/// temps — puis l'avancement, l'annulation, le résultat.
struct FolderArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var localization: LocalizationStore
    let request: FolderArchiveRequest

    @State private var store = FolderArchiveStore()
    @State private var destination: URL?
    @State private var sourceBytes: Int64?
    @State private var available: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(request.kind == .mods ? L10n.Archive.modsTitle : L10n.Archive.savesTitle))
                .font(AppDesign.Font.headline)
                .fixedSize(horizontal: false, vertical: true)
            switch store.phase {
            case .idle: plan
            case .running(let progress, let startedAt): running(progress, startedAt: startedAt)
            case .finished(let archive, let bytes, let seconds): finished(archive, bytes: bytes, seconds: seconds)
            case .failed(let message): ended(localization.L(L10n.Archive.failed) + "\n" + message, color: AppDesign.Color.error)
            case .cancelled: ended(localization.L(L10n.Archive.cancelled), color: .secondary)
            }
        }
        .padding(AppDesign.Spacing.lg)
        .frame(width: 460)
        .interactiveDismissDisabled(store.isRunning)
        .task { await prepare() }
    }

    // MARK: - Avant de lancer

    @ViewBuilder
    private var plan: some View {
        let enough = sourceBytes.map { FolderArchive.hasEnoughSpace(sourceBytes: $0, available: available) } ?? false
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            row("shippingbox", request.summary + " · " + bytesText(sourceBytes))
            HStack(alignment: .firstTextBaseline) {
                row("folder", destination?.path ?? "—")
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: AppDesign.Spacing.sm)
                Button(localization.L(L10n.Archive.choose)) { chooseDestination() }
            }
            if let sourceBytes {
                spaceRow(sourceBytes: sourceBytes, enough: enough)
                row("clock", String(format: localization.L(L10n.Archive.estimate),
                                    durationText(FolderArchive.estimatedSeconds(
                                        bytes: sourceBytes, bytesPerSecond: store.bytesPerSecond))))
            }
        }
        .font(AppDesign.Font.caption)
        HStack {
            Spacer()
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(localization.L(L10n.Archive.start)) { start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!enough || destination == nil)
        }
    }

    @ViewBuilder
    private func spaceRow(sourceBytes: Int64, enough: Bool) -> some View {
        let needed = FolderArchive.requiredBytes(sourceBytes: sourceBytes)
        if enough {
            row("internaldrive", String(format: localization.L(L10n.Archive.spaceOK),
                                        bytesText(available), bytesText(needed)))
        } else {
            row("exclamationmark.triangle.fill", String(format: localization.L(L10n.Archive.spaceShort),
                                                        bytesText(needed), bytesText(available)))
                .foregroundStyle(AppDesign.Color.error)
        }
    }

    // MARK: - Pendant

    @ViewBuilder
    private func running(_ progress: FolderArchive.Progress?, startedAt: Date) -> some View {
        ProgressView(value: progress?.fraction ?? 0)
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            Text(statusText(progress, elapsed: context.date.timeIntervalSince(startedAt)))
                .font(AppDesign.Font.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button(localization.L(L10n.Archive.stop), role: .cancel) { store.cancel() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func statusText(_ progress: FolderArchive.Progress?, elapsed: Double) -> String {
        guard let progress else { return localization.L(L10n.Archive.starting) }
        let remaining = FolderArchive.remainingSeconds(progress: progress, elapsed: elapsed)
        return String(format: localization.L(L10n.Archive.progress),
                      Int64(progress.entriesDone), Int64(progress.entriesTotal),
                      bytesText(progress.bytesDone), bytesText(progress.bytesTotal),
                      remaining.map(durationText) ?? "—")
    }

    // MARK: - Après

    @ViewBuilder
    private func finished(_ archive: URL, bytes: Int64, seconds: Double) -> some View {
        Label(String(format: localization.L(L10n.Archive.done), bytesText(bytes), durationText(seconds)),
              systemImage: "checkmark.circle.fill")
            .foregroundStyle(AppDesign.Color.success)
            .fixedSize(horizontal: false, vertical: true)
        Text(archive.path)
            .font(AppDesign.Font.monoCaption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button(localization.L(L10n.Archive.reveal)) {
                NSWorkspace.shared.activateFileViewerSelecting([archive])
            }
            Button(localization.L(L10n.Saves.cleanupClose)) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func ended(_ message: String, color: Color) -> some View {
        Text(message)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button(localization.L(L10n.Saves.cleanupClose)) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func prepare() async {
        let kind = request.kind
        let fallback = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        let chosen = store.lastDestination(for: kind)
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? fallback
        destination = chosen
        available = ModsFolderSizer.availableBytes(on: chosen)
        if let known = request.knownBytes {
            sourceBytes = known
            return
        }
        let source = request.source
        // ~3 s sur un parc de 100 000 fichiers : hors du fil principal.
        sourceBytes = await Task.detached(priority: .userInitiated) {
            ModsFolderSizer.measure(modsFolder: source)?.totalBytes ?? 0
        }.value
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        panel.prompt = localization.L(L10n.Archive.choose)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
        available = ModsFolderSizer.availableBytes(on: url)
    }

    private func start() {
        guard let destination, let sourceBytes else { return }
        store.start(kind: request.kind, source: request.source, destinationFolder: destination,
                    archiveName: FolderArchive.archiveName(prefix: request.filePrefix, date: Date()),
                    sourceBytes: sourceBytes)
    }

    // MARK: - Mise en forme

    private func row(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bytesText(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = Int64((seconds / 60).rounded(.up))
        if seconds < 60 { return localization.L(L10n.Archive.underAMinute) }
        if minutes < 60 { return String(format: localization.L(L10n.Archive.minutes), minutes) }
        return String(format: localization.L(L10n.Archive.hoursMinutes), minutes / 60, minutes % 60)
    }
}

extension L10n {
    enum Archive {
        static let modsTitle    = "archive_mods_title"
        static let savesTitle   = "archive_saves_title"
        static let modsSummary  = "archive_mods_summary"
        static let savesSummary = "archive_saves_summary"
        static let choose       = "archive_choose"
        static let spaceOK      = "archive_space_ok"
        static let spaceShort   = "archive_space_short"
        static let estimate     = "archive_estimate"
        static let start        = "archive_start"
        static let stop         = "archive_stop"
        static let starting     = "archive_starting"
        static let progress     = "archive_progress"
        static let done         = "archive_done"
        static let reveal       = "archive_reveal"
        static let failed       = "archive_failed"
        static let cancelled    = "archive_cancelled"
        static let underAMinute = "archive_under_a_minute"
        static let minutes      = "archive_minutes"
        static let hoursMinutes = "archive_hours_minutes"
    }
}
