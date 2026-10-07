import Foundation

public enum SloDiagnosticPresentationKind: Equatable, Sendable {
    case missing, downloading, awaitingInstall, paused, ready, incompatible
    case probeRequired, blocked, preparing, waitingForGame, running, restoring
    case recovery, failed, report
}

public enum SloDiagnosticPresentationAction: Equatable, Sendable {
    case download(nexusId: Int, uniqueId: String)
    case openPage(URL, nexusId: Int, uniqueId: String)
    case installProbe(ProbeBundle.Action)
    case confirm(SloDiagnosticPreparation)
    case retry
    case restore
}

public struct SloDiagnosticPresentation: Equatable, Sendable {
    public let kind: SloDiagnosticPresentationKind
    public let action: SloDiagnosticPresentationAction?

    public static func make(state: SloDiagnosticSessionStore.State,
                            directDownloadUnavailable: Bool,
                            nexusActivity: SloDiagnosticNexusActivity = .idle)
        -> SloDiagnosticPresentation {
        if case .downloading(let id) = nexusActivity, id == SloDiagnosticContract.nexusId {
            return .init(kind: .downloading, action: nil)
        }
        if case .awaitingInstall(let id) = nexusActivity, id == SloDiagnosticContract.nexusId {
            return .init(kind: .awaitingInstall, action: nil)
        }
        switch state {
        case .idle: return .init(kind: .blocked, action: .retry)
        case .unavailable(let readiness):
            return unavailable(readiness, directDownloadUnavailable: directDownloadUnavailable)
        case .ready(let preparation):
            let paused = !preparation.slo.isEnabled || !preparation.probeWasEnabled
            return .init(kind: paused ? .paused : .ready, action: .confirm(preparation))
        case .preparing: return .init(kind: .preparing, action: nil)
        case .waitingForGame: return .init(kind: .waitingForGame, action: nil)
        case .running: return .init(kind: .running, action: nil)
        case .restoring: return .init(kind: .restoring, action: nil)
        case .recoveryBlocked: return .init(kind: .recovery, action: .restore)
        case .failed: return .init(kind: .failed, action: .retry)
        case .report: return .init(kind: .report, action: .retry)
        }
    }

    private static func unavailable(_ readiness: SloDiagnosticReadiness,
                                    directDownloadUnavailable: Bool)
        -> SloDiagnosticPresentation {
        switch readiness {
        case .sloAbsent:
            let route = SloDiagnosticContract.installRoute(
                directDownloadUnavailable: directDownloadUnavailable)
            switch route {
            case .directDownload(let id):
                return .init(kind: .missing,
                             action: .download(nexusId: id,
                                               uniqueId: SloDiagnosticContract.uniqueId))
            case .webPage(let url):
                return .init(kind: .missing,
                             action: .openPage(url, nexusId: SloDiagnosticContract.nexusId,
                                               uniqueId: SloDiagnosticContract.uniqueId))
            }
        case .sloDownloading: return .init(kind: .downloading, action: nil)
        case .sloPaused:
            return .init(kind: .paused, action: .retry)
        case .ready(let installation):
            return .init(kind: installation.isEnabled ? .ready : .paused, action: .retry)
        case .incompatible: return .init(kind: .incompatible, action: nil)
        case .ambiguous, .blocked: return .init(kind: .blocked, action: .retry)
        case .probeInstallRequired(let action):
            return .init(kind: .probeRequired,
                         action: action == .unavailable ? nil : .installProbe(action))
        case .probePaused: return .init(kind: .paused, action: .retry)
        }
    }
}
