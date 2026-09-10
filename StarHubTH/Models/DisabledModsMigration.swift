import Foundation

/// La migration one-shot `Mods_disabled/` → préfixe point dans `Mods/`
/// (REFACTORING §6, domaine Scan). Un ancien dossier `Mods_disabled/` rendait
/// ses mods invisibles : ils vivent désormais dans `Mods/` sous `.X`, la
/// convention de pause du dépôt. Le drapeau `UDKey.disabledModsMigratedToDotPrefix`
/// fait qu'on ne passe ici qu'une fois — sauf si le dossier est illisible,
/// auquel cas on **ne** le pose **pas** et le prochain lancement réessaie.
///
/// « Ce qui n'est pas à moi arrive en paramètre » (§3) : les préférences, le
/// gestionnaire de fichiers et le journal (pré-lié aux niveaux de l'app)
/// arrivent par l'appel — la fonction est contrôlable en test de bout en bout.
enum DisabledModsMigration {

    static func runIfNeeded(gameDir: String,
                            defaults: UserDefaults = .standard,
                            fm: FileManager = .default,
                            log: (String, LogLevel) -> Void) {
        guard !gameDir.isEmpty else { return }
        if defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix) { return }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")

        // Fast path: no legacy folder → nothing to do.
        guard fm.fileExists(atPath: disabledPath) else {
            defaults.set(true, forKey: UDKey.disabledModsMigratedToDotPrefix)
            return
        }

        // Ensure Mods/ exists so moves below always have a destination.
        try? fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true)


        guard let entries = try? fm.contentsOfDirectory(atPath: disabledPath) else {
            // Can't even read the folder — leave it and let the scanMods
            // warning surface it. Don't set the flag so we retry next launch.
            log("Migration: could not read Mods_disabled/ — skipping (will retry next launch).", .warning)
            return
        }

        var failed = 0
        var moved = 0
        for entry in entries {
            if OSJunk.isJunk(entry) { continue }

            let src = (disabledPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: src, isDirectory: &isDir)
            // Only migrate directories — a stray file at the root of
            // Mods_disabled/ is left in place (and surfaced by the warning).
            guard isDir.boolValue else { continue }

            let dotName = "." + entry
            let dst = (modsPath as NSString).appendingPathComponent(dotName)
            let finalDst: String
            if fm.fileExists(atPath: dst) {
                // Collision: a `.X` already exists in Mods/ (e.g. from a
                // crashed prior run, or a manual copy). Preserve the data by
                // moving under a unique suffix rather than overwriting.
                let uuid8 = String(UUID().uuidString.prefix(8))
                finalDst = "\(dst)_\(uuid8)"
                log("Migration: collision — Mods/.\(entry) already exists, moved Mods_disabled/\(entry) → Mods/.\(entry)_\(uuid8).", .warning)
            } else {
                finalDst = dst
            }

            do {
                try fm.moveItem(atPath: src, toPath: finalDst)
                moved += 1
            } catch {
                failed += 1
                log("Migration: failed to move Mods_disabled/\(entry) → \(finalDst): \(error.localizedDescription)", .error)
            }
        }

        // Remove Mods_disabled/ entirely if it's now empty or only holds junk.
        let remaining = (try? fm.contentsOfDirectory(atPath: disabledPath)) ?? []
        let onlyJunk = remaining.allSatisfy(OSJunk.isJunk)
        if onlyJunk {
            do {
                try fm.removeItem(atPath: disabledPath)
            } catch {
                // Non-fatal — the permanent warning will re-surface it.
                log("Migration: could not remove empty Mods_disabled/: \(error.localizedDescription)", .warning)
            }
        } else {
            log("Migration: Mods_disabled/ still contains \(remaining.count) non-junk entries (failed moves or stray files) — left in place; see the Mods_disabled warning.", .warning)
        }

        log("Migration: moved \(moved) disabled mod(s) to Mods/.X, \(failed) failure(s).", failed > 0 ? .warning : .info)
        defaults.set(true, forKey: UDKey.disabledModsMigratedToDotPrefix)
    }
}
