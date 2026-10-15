import Foundation
import Observation

/// Archive un dossier (`Mods/` ou les parties) en `.zip` là où l'utilisateur
/// l'a choisi, avec avancement, annulation et nettoyage (règle F1-T2 : hors
/// VM). Remplace `zipToDesktop`, qui lançait un `zip` muet sur le Bureau.
///
/// Rien ne reste derrière une annulation ou un échec : le temporaire de `zip`
/// vit dans un dossier caché propre à l'archive, supprimé à la fin quoi qu'il
/// arrive — un `zip` tué laisse son temporaire (constaté le 2026-10-15).
@MainActor
@Observable
public final class FolderArchiveStore {

    public enum Kind: String, Sendable { case mods, saves }

    public enum Phase: Equatable, Sendable {
        case idle
        case running(progress: FolderArchive.Progress?, startedAt: Date)
        case finished(archive: URL, bytes: Int64, seconds: Double)
        case failed(message: String)
        case cancelled
    }

    public private(set) var phase: Phase = .idle

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private let defaults: UserDefaults
    private let zipURL: URL
    /// En dessous, une archive mesure surtout le lancement de `zip` : son
    /// débit fausserait l'estimation de la suivante.
    private let minimumLearningBytes: Int64
    private var run: ZipRun?

    public init(defaults: UserDefaults = .standard,
                zipURL: URL = URL(fileURLWithPath: "/usr/bin/zip"),
                minimumLearningBytes: Int64 = 100_000_000) {
        self.defaults = defaults
        self.zipURL = zipURL
        self.minimumLearningBytes = minimumLearningBytes
    }

    /// Débit de la dernière grosse archive, le défaut sinon.
    public var bytesPerSecond: Double {
        let stored = defaults.double(forKey: Key.bytesPerSecond)
        return stored > 0 ? stored : FolderArchive.defaultBytesPerSecond
    }

    /// Dernier dossier où une archive de ce genre a abouti.
    public func lastDestination(for kind: Kind) -> URL? {
        defaults.string(forKey: Key.destination(kind)).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public func start(kind: Kind, source: URL, destinationFolder: URL,
                      archiveName: String, sourceBytes: Int64) {
        guard !isRunning else { return }
        let startedAt = Date()
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            phase = .failed(message: source.path)
            return
        }
        guard !FolderArchive.destination(destinationFolder, isInside: source) else {
            phase = .failed(message: destinationFolder.path)
            return
        }
        let archive = Self.unusedURL(in: destinationFolder, name: archiveName)
        let temporary = destinationFolder
            .appendingPathComponent(".starhubfr-archive-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        } catch {
            phase = .failed(message: error.localizedDescription)
            return
        }

        let zipRun = ZipRun(executable: zipURL, source: source,
                            arguments: FolderArchive.zipArguments(archive: archive, temporaryFolder: temporary))
        run = zipRun
        phase = .running(progress: nil, startedAt: startedAt)

        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = zipRun.execute { progress in
                Task { @MainActor in self?.publish(progress, startedAt: startedAt) }
            }
            await self?.finish(outcome, kind: kind, archive: archive, temporary: temporary,
                               destinationFolder: destinationFolder, sourceBytes: sourceBytes,
                               startedAt: startedAt)
        }
    }

    /// Arrête `zip` ; le nettoyage suit dans `finish`.
    public func cancel() {
        run?.cancel()
    }

    /// Revient à l'état initial une fois le résultat lu.
    public func reset() {
        guard !isRunning else { return }
        phase = .idle
    }

    private func publish(_ progress: FolderArchive.Progress, startedAt: Date) {
        guard case .running(_, let current) = phase, current == startedAt else { return }
        phase = .running(progress: progress, startedAt: startedAt)
    }

    private func finish(_ outcome: ZipRun.Outcome, kind: Kind, archive: URL, temporary: URL,
                        destinationFolder: URL, sourceBytes: Int64, startedAt: Date) {
        run = nil
        Self.remove(temporary)
        let seconds = Date().timeIntervalSince(startedAt)
        switch outcome {
        case .succeeded:
            defaults.set(destinationFolder.path, forKey: Key.destination(kind))
            if sourceBytes >= minimumLearningBytes, seconds > 0 {
                defaults.set(Double(sourceBytes) / seconds, forKey: Key.bytesPerSecond)
            }
            phase = .finished(archive: archive, bytes: Self.size(of: archive), seconds: seconds)
        case .cancelled:
            Self.remove(archive)
            phase = .cancelled
        case .failed(let message):
            Self.remove(archive)
            phase = .failed(message: message)
        }
    }

    // MARK: - Fichiers

    /// Le nom demandé, ou `nom-2.zip`, `nom-3.zip`… : `zip` *mettrait à jour*
    /// une archive existante au lieu d'en écrire une neuve.
    private static func unusedURL(in folder: URL, name: String) -> URL {
        let first = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base)-\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            // Rien à faire de plus : le dossier caché reste, sans gêner la suite.
        }
    }

    private static func size(of url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return 0
        }
    }

    private enum Key {
        static let bytesPerSecond = "folderArchive.bytesPerSecond"
        static func destination(_ kind: Kind) -> String { "folderArchive.destination.\(kind.rawValue)" }
    }
}

/// Un `zip` en cours. `@unchecked Sendable` : `Process` ne l'est pas, mais
/// tout accès partagé (lancement, annulation) passe sous `lock`.
final class ZipRun: @unchecked Sendable {

    enum Outcome: Sendable, Equatable {
        case succeeded
        case cancelled
        case failed(String)
    }

    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    init(executable: URL, source: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = source
        process.standardInput = FileHandle.nullDevice
        // Hériter l'environnement, puis surcharger : `LC_NUMERIC=C` garde le
        // point décimal de `1.7M` quelle que soit la langue du Mac.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_NUMERIC"] = "C"
        process.environment = environment
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if started, process.isRunning { process.terminate() }
    }

    /// Lance `zip` et lit sa sortie jusqu'au bout, **avant** d'attendre sa
    /// fin : un tube plein (64 Ko) bloquerait l'enfant et le parent.
    /// Bloquant — à appeler hors du fil principal.
    func execute(onProgress: @escaping @Sendable (FolderArchive.Progress) -> Void) -> Outcome {
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        lock.lock()
        if cancelled { lock.unlock(); return .cancelled }
        do {
            try process.run()
        } catch {
            lock.unlock()
            return .failed(error.localizedDescription)
        }
        started = true
        lock.unlock()

        // L'erreur se lit en parallèle : elle aussi peut remplir son tube.
        let errorBuffer = ErrorBuffer()
        let errorHandle = errors.fileHandleForReading
        let errorRead = DispatchSemaphore(value: 0)
        Thread {
            errorBuffer.data = errorHandle.readDataToEndOfFile()
            errorRead.signal()
        }.start()

        var lastPublished = Date.distantPast
        var pending = Data()
        let handle = output.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                // Le nom de fichier peut ne pas être de l'UTF-8 valide : seul le
                // préfixe numérique compte, d'où le décodage tolérant.
                let line = String(decoding: lineData, as: UTF8.self)
                guard let progress = FolderArchive.progress(fromLine: line) else { continue }
                let now = Date()
                if now.timeIntervalSince(lastPublished) >= 0.25 {
                    lastPublished = now
                    onProgress(progress)
                }
            }
        }
        process.waitUntilExit()
        errorRead.wait()

        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { return .cancelled }
        if process.terminationStatus == 0 { return .succeeded }
        let message = String(decoding: errorBuffer.data, as: UTF8.self)
            .split(separator: "\n").last.map(String.init) ?? "zip \(process.terminationStatus)"
        return .failed(message)
    }

    /// Tampon de la sortie d'erreur, rempli par son fil de lecture.
    private final class ErrorBuffer: @unchecked Sendable {
        var data = Data()
    }
}
