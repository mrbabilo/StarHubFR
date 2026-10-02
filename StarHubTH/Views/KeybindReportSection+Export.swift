import SwiftUI
import AppKit

extension KeybindReportSection {
    /// C4-T13 — le rapport en Markdown daté, là où l'utilisateur le veut :
    /// panneau d'enregistrement, écriture atomique, échec au journal.
    func exportReport(_ report: KeybindScanner.KeybindReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "starhubfr-raccourcis-\(DateFormatter.posixStamp()).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = KeybindReportExport.markdown(report: report, generatedAt: Date())
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            vm.log("Rapport de raccourcis exporté : \(url.lastPathComponent)", level: .info)
        } catch {
            vm.log("Export du rapport impossible : \(error.localizedDescription)", level: .warning)
        }
    }
}
