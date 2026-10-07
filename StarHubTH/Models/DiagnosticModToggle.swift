import Foundation

/// Diagnostic-only atomic rename. Never chains dependencies outside the snapshot.
public enum DiagnosticModToggle {
    public static func enabled(root: String, modsRoot: URL) -> Bool? {
        guard valid(root) else { return nil }
        let fm = FileManager.default
        var activeIsDirectory: ObjCBool = false
        var pausedIsDirectory: ObjCBool = false
        let active = fm.fileExists(atPath: modsRoot.appendingPathComponent(root).path, isDirectory: &activeIsDirectory)
        let paused = fm.fileExists(atPath: modsRoot.appendingPathComponent("." + root).path, isDirectory: &pausedIsDirectory)
        if active && !paused && activeIsDirectory.boolValue { return true }
        if paused && !active && pausedIsDirectory.boolValue { return false }
        return nil
    }

    public static func setEnabled(_ enabled: Bool, root: String, modsRoot: URL) -> Bool {
        guard let current = self.enabled(root: root, modsRoot: modsRoot) else { return false }
        if current == enabled { return true }
        let source = modsRoot.appendingPathComponent(current ? root : "." + root)
        let destination = modsRoot.appendingPathComponent(enabled ? root : "." + root)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return self.enabled(root: root, modsRoot: modsRoot) == enabled
        } catch { return false }
    }

    private static func valid(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
    }
}
