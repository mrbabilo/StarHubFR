# Config Editor + App Changelog (from upstream StarHubTH) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the mod config editor (hierarchical + raw JSON), the code editor, and the in-app changelog viewer from upstream `AppleBoiy/StarHubTH` into this fork, adapted to the fork's existing conventions.

**Architecture:** Three new SwiftUI view files extracted verbatim (or near-verbatim) from `upstream/main`, wired into the existing `StarHubTHViewModel`/`MainView`/`ModListView` navigation pattern. No upstream Nexus code, no upstream backup/restore-by-zip code — the fork's own equivalents (`NexusUpdateChecker`, `ModConfigBackupManager`/`ModConfigBackupsView`, `zipToDesktop`) already cover those needs more safely. See `.kilo/plans/1784807396660-starhubfr-vs-starhubth-analysis.md` for the full comparative analysis this plan implements.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (Cocoa) — this repository is not an Xcode project; the shipped app is compiled by `python build_app.py` via raw `swiftc`. A separate `Package.swift` defines an SPM library target `StarHubTHCore` used only for Swift Testing coverage of pure-logic files (see Global Constraints).

## Global Constraints

- **Build system split**: `python build_app.py` compiles the *entire* app (`StarHubTH/*.swift` + `StarHubTH/Views/*.swift`) via raw `swiftc` — this is the only command that validates changes to `StarHubTHViewModel.swift`, any `Views/*.swift` file, or `SmapiInstaller.swift`. `swift build` / `swift test` only compile the `StarHubTHCore` SPM target defined in `Package.swift` (currently: `ModItem.swift`, `ModConfigBackup.swift`, `ModConfigBackupManager.swift`, `DictionaryExtensions.swift`, `ZipModInfo.swift`, `ModInstallBackup.swift`, `ModInstallBackupManager.swift`, `SaveManager.swift`, `Models/InventoryItem.swift`, `L10n.swift`) plus its three test targets. Every task below states which of these two builds is its actual gate — do not report a task done on `swift build` alone if it touches a file outside that list.
- **Two locales only**: `SUPPORTED_LOCALES` in `build_app.py` is `{"en", "th"}`. There is no `fr.json` and none is to be added by this plan. New localization keys go in `L10n.swift`, `assets/en.json`, and `assets/th.json` only.
- **Never hand-edit `assets/*.lproj/Localizable.strings`**: `python build_app.py` regenerates both files from `assets/en.json`/`assets/th.json` on every run (`generate_localizable_strings()` in `build_app.py`), and aborts the whole build with `[ERROR] <locale>.json is missing keys: ...` / `has extra keys: ...` if `en.json` and `th.json` don't have exactly the same key set. Editing `.lproj` files directly would be silently overwritten and does not participate in the parity check.
- **Do not port upstream's `vm.backupMod(mod:)` / `vm.restoreModZip(mod:)`.** Upstream's `ModConfigEditorView` calls these two ViewModel methods (NSSavePanel-driven whole-mod-folder zip export / NSOpenPanel-driven raw `unzip -o` restore, unvalidated). The fork already covers this need two ways that are both safer and more consistent with its own conventions: `ModConfigBackupManager` + `ModConfigBackupsView` (versioned, selective, reachable from the "ConfigBackups" tab) for structured config backups, and the existing `zipToDesktop(sourceDir:filePrefix:successKey:errorKey:)` + `backupAllMods()` pattern in `StarHubTHViewModel.swift:1966` for whole-folder zip export. Task 2 below drops the corresponding upstream menu items instead of porting them. If you find yourself about to add `func backupMod` or `func restoreModZip` to `StarHubTHViewModel.swift`, stop — that is out of scope for this plan.
- **Do not add a Nexus API key store.** `NexusUpdateChecker.swift` already stores it in the macOS Keychain. No task here touches Nexus code, and none should introduce a second, `UserDefaults`-based key store.
- Commit after each task (established convention in this repository — see recent commits `a807445`, `c89b500`, `1d37be2`).

---

### Task 1: Localization keys for the config editor and changelog view

**Files:**
- Modify: `StarHubTH/L10n.swift`
- Modify: `assets/en.json`
- Modify: `assets/th.json`

**Interfaces:**
- Produces: the following static string constants, consumed by Task 2's copied view files —
  - `L10n.Main.appChangelog` → `"main_app_changelog"`
  - `L10n.Settings.configVisualEditor` → `"config_visual_editor"`
  - `L10n.Settings.configCodeEditor` → `"config_code_editor"`
  - `L10n.Settings.configNoSettingsFound` → `"config_no_settings_found"`
  - `L10n.Settings.configNoSettingsFoundFor` → `"config_no_settings_found_for"`
  - `L10n.Settings.configRawJson` → `"config_raw_json"`
  - `L10n.Settings.configReset` → `"config_reset"`
  - `L10n.Settings.configRestoreConfig` → `"config_restore_config"`
  - `L10n.Settings.configSaved` → `"config_saved"`
  - `L10n.Settings.configSearchPlaceholder` → `"config_search_placeholder"`
  - `L10n.Settings.configInvalidJson` → `"config_invalid_json"`
  - Already exist, do **not** re-add: `L10n.Saves.saveChanges` (`"saves_save_changes"`), `L10n.Settings.settings` (`"settings_settings"`), `L10n.Settings.gameDirNotSet` (`"settings_game_dir_not_set"`).

- [ ] **Step 1: Add the `Main` key**

In `StarHubTH/L10n.swift`, find:
```swift
        static let playerFallback       = "main_player_fallback"
    }
```
Replace with:
```swift
        static let playerFallback       = "main_player_fallback"
        static let appChangelog         = "main_app_changelog"
    }
```

- [ ] **Step 2: Add the ten `Settings` keys**

In the same file, find the last line of `enum Settings` (immediately before its closing `}`):
```swift
        static let nexusKeyPlaceholder  = "settings_nexus_api_key_placeholder"
    }
```
Replace with:
```swift
        static let nexusKeyPlaceholder  = "settings_nexus_api_key_placeholder"
        static let configVisualEditor      = "config_visual_editor"
        static let configCodeEditor        = "config_code_editor"
        static let configNoSettingsFound   = "config_no_settings_found"
        static let configNoSettingsFoundFor = "config_no_settings_found_for"
        static let configRawJson           = "config_raw_json"
        static let configReset             = "config_reset"
        static let configRestoreConfig     = "config_restore_config"
        static let configSaved             = "config_saved"
        static let configSearchPlaceholder = "config_search_placeholder"
        static let configInvalidJson       = "config_invalid_json"
    }
```

- [ ] **Step 3: Add the English strings**

In `assets/en.json`, the file is a flat, single-level JSON object. Find its last entry (currently):
```json
  "mod_config_backups_nothing_to_back_up": "None of the enabled mods have config files to back up."
}
```
Replace with:
```json
  "mod_config_backups_nothing_to_back_up": "None of the enabled mods have config files to back up.",
  "main_app_changelog": "App Changelog",
  "config_visual_editor": "Visual Editor",
  "config_code_editor": "Code Editor",
  "config_no_settings_found": "No configurable settings found.",
  "config_no_settings_found_for": "No settings found for \"%@\"",
  "config_raw_json": "Raw JSON",
  "config_reset": "Reset",
  "config_restore_config": "Restore Config",
  "config_saved": "Config saved successfully",
  "config_search_placeholder": "Search settings...",
  "config_invalid_json": "Invalid JSON format"
}
```

- [ ] **Step 4: Add the Thai strings**

In `assets/th.json`, add the same 11 keys with these values (find the file's closing `}` and insert before it, adding a trailing comma to what was previously the last line, exactly as in Step 3):
```json
  "main_app_changelog": "บันทึกการเปลี่ยนแปลง",
  "config_visual_editor": "ตัวแก้ไขภาพ",
  "config_code_editor": "ตัวแก้ไขโค้ด",
  "config_no_settings_found": "ไม่พบการตั้งค่าที่ปรับแต่งได้",
  "config_no_settings_found_for": "ไม่พบการตั้งค่าสำหรับ \"%@\"",
  "config_raw_json": "ไฟล์ JSON ต้นฉบับ",
  "config_reset": "คืนค่าเริ่มต้น",
  "config_restore_config": "ย้อนคืนการตั้งค่า",
  "config_saved": "บันทึกการตั้งค่าเรียบร้อยแล้ว",
  "config_search_placeholder": "ค้นหาการตั้งค่า...",
  "config_invalid_json": "รูปแบบ JSON ไม่ถูกต้อง"
}
```

- [ ] **Step 5: Verify parity and regenerate `.lproj` files**

Run: `python build_app.py`
Expected: build proceeds past `generate_localizable_strings()` without any `[ERROR] ... missing keys` / `has extra keys` line (that step runs first and calls `raise SystemExit(1)` on mismatch). This also rewrites `assets/en.lproj/Localizable.strings` and `assets/th.lproj/Localizable.strings` — expect them to show as modified in `git status`; that is correct, they are generated files tracked in git.

- [ ] **Step 6: Confirm the SPM package still builds**

Run: `swift build`
Expected: `Build complete!` (this target includes `L10n.swift`; confirms Step 1–2 introduced no syntax error).

- [ ] **Step 7: Commit**

```bash
git add StarHubTH/L10n.swift assets/en.json assets/th.json assets/en.lproj/Localizable.strings assets/th.lproj/Localizable.strings
git commit -m "feat: add localization keys for upstream config editor and changelog view"
```

---

### Task 2: Add ModConfigEditorView, CodeEditorView, AppChangelogView + editingModConfig

**Files:**
- Create: `StarHubTH/Views/CodeEditorView.swift`
- Create: `StarHubTH/Views/AppChangelogView.swift`
- Create: `StarHubTH/Views/ModConfigEditorView.swift`
- Modify: `StarHubTH/StarHubTHViewModel.swift:204` (insertion point below)

**Interfaces:**
- Consumes: the 11 `L10n` keys from Task 1; `ModItem.name` / `.folderName` / `.isEnabled` (already defined in `StarHubTH/ModItem.swift`); `StarHubTHViewModel.gameDir: String`, `.L(_:) -> String`, `.showModal(message:)` (all already defined); `StandardSection<Content>` from `StarHubTH/Views/SharedComponents.swift:43` (signature: `init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content)`, already matches upstream's usage verbatim).
- Produces: `@Published var editingModConfig: ModItem? = nil` on `StarHubTHViewModel`, consumed by Task 3. `struct ModConfigEditorView: View { init(vm: StarHubTHViewModel, mod: ModItem) }`. `struct AppChangelogView: View { init(vm: StarHubTHViewModel) }`.

This task's build gate is **`python build_app.py`**, not `swift build` — none of these three files are part of the `StarHubTHCore` SPM target.

- [ ] **Step 1: Add `editingModConfig` to the ViewModel**

In `StarHubTH/StarHubTHViewModel.swift`, find:
```swift
    @Published var viewingThaiMod: ThaiTranslationMod? = nil
```
Replace with:
```swift
    @Published var viewingThaiMod: ThaiTranslationMod? = nil
    @Published var editingModConfig: ModItem? = nil
```

- [ ] **Step 2: Extract `CodeEditorView.swift` verbatim**

This file has zero dependencies on anything in this fork's ViewModel (confirmed: no `vm.` references at all beyond what SwiftUI itself needs) — copy upstream's final version as-is.

Run: `git show upstream/main:StarHubTH/Views/CodeEditorView.swift > StarHubTH/Views/CodeEditorView.swift`
Expected: command succeeds silently, file created (124 lines).

- [ ] **Step 3: Extract `AppChangelogView.swift` verbatim**

This file only calls `vm.L(L10n.Main.appChangelog)`, which Task 1 added — copy as-is.

Run: `git show upstream/main:StarHubTH/Views/AppChangelogView.swift > StarHubTH/Views/AppChangelogView.swift`
Expected: command succeeds silently, file created (94 lines). It reads `CHANGELOG.md` via `Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")` — Task 3 adds the `build_app.py` change that puts that file in the bundle; until then this view will show "CHANGELOG.md not found in app bundle." at runtime, which is expected and not a bug in this task.

- [ ] **Step 4: Extract `ModConfigEditorView.swift`, then remove the upstream backup/restore-by-zip menu items**

Run: `git show upstream/main:StarHubTH/Views/ModConfigEditorView.swift > StarHubTH/Views/ModConfigEditorView.swift`
Expected: command succeeds silently, file created (524 lines).

Per the Global Constraints section, this file must **not** call `vm.backupMod`/`vm.restoreModZip` — those methods do not exist in this fork's ViewModel and must not be added (the fork's `ModConfigBackupManager`/`ModConfigBackupsView` and `backupAllMods()` already cover this). Edit the file: find
```swift
                Menu {
                    Button(action: { vm.backupMod(mod: mod) }) {
                        Label(vm.L(L10n.Settings.configBackupMod), systemImage: "arrow.down.doc")
                    }
                    Button(action: { vm.restoreModZip(mod: mod) }) {
                        Label(vm.L(L10n.Settings.configRestoreMod), systemImage: "arrow.up.doc")
                    }
                    Divider()
                    Button(action: { restoreConfigBackup() }) {
                        Label(vm.L(L10n.Settings.configRestoreConfig), systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Label(vm.L(L10n.Settings.configBackupAndRestore), systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderedButton)
```
Replace with:
```swift
                Button(action: { restoreConfigBackup() }) {
                    Label(vm.L(L10n.Settings.configRestoreConfig), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
```
(`restoreConfigBackup()` is a private method further down in the same file — it restores from a local `config.json.bak` or an explicitly-picked `.json` file, has no dependency on `vm.backupMod`/`vm.restoreModZip`, and is unaffected by this edit — leave it as extracted.)

- [ ] **Step 5: Build the whole app**

Run: `python build_app.py`
Expected: compiles successfully through the `swiftc` step (look for the app bundle being produced at `StarHubTH.app`; no `error:` lines from `swiftc`). If it fails, the error will point at one of the three new files or at `StarHubTHViewModel.swift:205` — re-check Steps 1–4 for a typo before proceeding.

- [ ] **Step 6: Confirm the SPM package is unaffected**

Run: `swift build && swift test`
Expected: `Build complete!` and all existing tests still pass (this task does not touch any file in the `StarHubTHCore` target, so this is a regression check, not new coverage).

- [ ] **Step 7: Commit**

```bash
git add StarHubTH/Views/CodeEditorView.swift StarHubTH/Views/AppChangelogView.swift StarHubTH/Views/ModConfigEditorView.swift StarHubTH/StarHubTHViewModel.swift
git commit -m "feat: add mod config editor, code editor, and changelog views from upstream"
```

---

### Task 3: Wire up navigation — ModListView entry point, MainView routing, CHANGELOG.md bundling

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift` (context menu, ~line 904)
- Modify: `StarHubTH/Views/MainView.swift` (title logic, sidebar, content switch, back-navigation)
- Modify: `build_app.py` (~line 84)

**Interfaces:**
- Consumes: `vm.editingModConfig` (Task 2), `ModConfigEditorView(vm:mod:)` / `AppChangelogView(vm:)` (Task 2), `SidebarNavItem` / `SidebarSectionHeader` (already defined in `MainView.swift`).

This task's build gate is **`python build_app.py`**.

- [ ] **Step 1: Add "Edit Config" to the mod row's context menu**

In `StarHubTH/Views/ModListView.swift`, find:
```swift
        .contextMenu {
            Button(vm.L(L10n.Mods.openInFinder)) {
                let baseFolder = mod.isEnabled ? "Mods" : "Mods_disabled"
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent(baseFolder)
                    .appendingPathComponent(mod.folderName)
                NSWorkspace.shared.open(url)
            }
            let effectiveLink = vm.nexusLink(for: mod)
```
Replace with:
```swift
        .contextMenu {
            Button(vm.L(L10n.Mods.openInFinder)) {
                let baseFolder = mod.isEnabled ? "Mods" : "Mods_disabled"
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent(baseFolder)
                    .appendingPathComponent(mod.folderName)
                NSWorkspace.shared.open(url)
            }
            Button(vm.L(L10n.Settings.configCodeEditor)) {
                vm.editingModConfig = mod
            }
            let effectiveLink = vm.nexusLink(for: mod)
```
(Reusing `L10n.Settings.configCodeEditor` — "Code Editor" / "ตัวแก้ไขโค้ด" — as the menu item label; it already exists from Task 1 and reads naturally as a menu action here. Do not add a new key for this.)

- [ ] **Step 2: Show the config editor in place of the mods list when `editingModConfig` is set**

In `StarHubTH/Views/MainView.swift`, find:
```swift
                if currentTab == "Mods" {
                    ModListView(vm: vm)
                } else if currentTab == "ConfigBackups" {
```
Replace with:
```swift
                if currentTab == "Mods" {
                    if let mod = vm.editingModConfig {
                        ModConfigEditorView(vm: vm, mod: mod)
                    } else {
                        ModListView(vm: vm)
                    }
                } else if currentTab == "ConfigBackups" {
```

- [ ] **Step 3: Add the AppChangelog tab's content**

In the same file, find:
```swift
                } else if currentTab == "Logs" {
                    LogsView(vm: vm)
                } else {
                    HomeView(vm: vm)
                }
```
Replace with:
```swift
                } else if currentTab == "Logs" {
                    LogsView(vm: vm)
                } else if currentTab == "AppChangelog" {
                    AppChangelogView(vm: vm)
                } else {
                    HomeView(vm: vm)
                }
```

- [ ] **Step 4: Add the sidebar entry**

In the same file, find:
```swift
                // System & Settings Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.system))
                    
                    if matchesSearch(vm.L(L10n.Settings.settings)) {
                        SidebarNavItem(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            label: vm.L(L10n.Settings.settings),
                            tab: "Settings",
                            currentTab: $currentTab
                        )
                    }
                }
```
Replace with:
```swift
                // System & Settings Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.system))
                    
                    if matchesSearch(vm.L(L10n.Settings.settings)) {
                        SidebarNavItem(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            label: vm.L(L10n.Settings.settings),
                            tab: "Settings",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.Main.appChangelog)) {
                        SidebarNavItem(
                            icon: "doc.text.fill",
                            iconColor: .indigo,
                            label: vm.L(L10n.Main.appChangelog),
                            tab: "AppChangelog",
                            currentTab: $currentTab
                        )
                    }
                }
```

- [ ] **Step 5: Add the navigation title**

In the same file, find:
```swift
        if currentTab == "Settings" { return vm.L(L10n.Settings.settings) }
        if currentTab == "Logs" { return vm.L(L10n.Logs.logs) }
        return vm.L(L10n.Main.home)
```
Replace with:
```swift
        if currentTab == "Mods" && vm.editingModConfig != nil { return vm.editingModConfig!.name }
        if currentTab == "Settings" { return vm.L(L10n.Settings.settings) }
        if currentTab == "Logs" { return vm.L(L10n.Logs.logs) }
        if currentTab == "AppChangelog" { return vm.L(L10n.Main.appChangelog) }
        return vm.L(L10n.Main.home)
```

- [ ] **Step 6: Clear `editingModConfig` on tab change**

In the same file, find:
```swift
            .onChange(of: currentTab) {
                vm.editingSave = nil
                vm.viewingThaiMod = nil
                vm.viewingSaveTimeline = nil
```
Replace with:
```swift
            .onChange(of: currentTab) {
                vm.editingSave = nil
                vm.viewingThaiMod = nil
                vm.viewingSaveTimeline = nil
                vm.editingModConfig = nil
```

- [ ] **Step 7: Wire the back button**

In the same file, find:
```swift
                        Button(action: {
                            if vm.editingSave != nil {
                                vm.editingSave = nil
                            } else if vm.viewingThaiMod != nil {
                                vm.viewingThaiMod = nil
                            } else if vm.viewingSaveTimeline != nil {
                                vm.viewingSaveTimeline = nil
                            } else if tabHistory.count > 1 {
                                isNavigatingBackOrForward = true
                                let current = tabHistory.removeLast()
                                forwardHistory.append(current)
                                currentTab = tabHistory.last ?? "Home"
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(vm.editingSave == nil && vm.viewingThaiMod == nil && vm.viewingSaveTimeline == nil && tabHistory.count <= 1)
```
Replace with:
```swift
                        Button(action: {
                            if vm.editingSave != nil {
                                vm.editingSave = nil
                            } else if vm.viewingThaiMod != nil {
                                vm.viewingThaiMod = nil
                            } else if vm.viewingSaveTimeline != nil {
                                vm.viewingSaveTimeline = nil
                            } else if vm.editingModConfig != nil {
                                vm.editingModConfig = nil
                            } else if tabHistory.count > 1 {
                                isNavigatingBackOrForward = true
                                let current = tabHistory.removeLast()
                                forwardHistory.append(current)
                                currentTab = tabHistory.last ?? "Home"
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(vm.editingSave == nil && vm.viewingThaiMod == nil && vm.viewingSaveTimeline == nil && vm.editingModConfig == nil && tabHistory.count <= 1)
```

- [ ] **Step 8: Bundle CHANGELOG.md into the app**

In `build_app.py`, find:
```python
        shutil.copy2(app_icon_path, os.path.join(RESOURCES_DIR, "AppIcon.icns"))
        print("[INFO] Copied AppIcon.icns to App Resources")
        
    for lang in ["en.lproj", "th.lproj"]:
```
Replace with:
```python
        shutil.copy2(app_icon_path, os.path.join(RESOURCES_DIR, "AppIcon.icns"))
        print("[INFO] Copied AppIcon.icns to App Resources")

    changelog_path = "CHANGELOG.md"
    if os.path.exists(changelog_path):
        shutil.copy2(changelog_path, os.path.join(RESOURCES_DIR, "CHANGELOG.md"))
        print("[INFO] Copied CHANGELOG.md to App Resources")

    for lang in ["en.lproj", "th.lproj"]:
```

- [ ] **Step 9: Build and smoke-test**

Run: `python build_app.py`
Expected: builds successfully; console shows `[INFO] Copied CHANGELOG.md to App Resources`.

Run: `open StarHubTH.app`
Manual check (this repo's existing convention for UI changes — see CLAUDE.md-equivalent guidance to test the golden path in a browser/app before reporting done):
- [ ] Navigate to "Mods", right-click any mod row → "Code Editor" appears in the context menu and clicking it opens `ModConfigEditorView` in place of the mods list, showing the mod's name in the navigation title.
- [ ] The back chevron returns to the mods list.
- [ ] In the sidebar, a new "App Changelog" entry appears under System & Settings; clicking it shows the content of this repo's `CHANGELOG.md`, not "CHANGELOG.md not found in app bundle."
- [ ] Existing pagination, category filters, and the "ConfigBackups" tab still work unchanged.

- [ ] **Step 10: Commit**

```bash
git add StarHubTH/Views/ModListView.swift StarHubTH/Views/MainView.swift build_app.py
git commit -m "feat: wire up mod config editor entry point and app changelog navigation"
```

---

### Task 4: Port upstream's per-file rollback into SmapiInstaller.install()

**Files:**
- Modify: `StarHubTH/SmapiInstaller.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–3; independent of the rest of this plan.
- Produces: no new public interface — `install(gameDir:completion:)`'s signature is unchanged, only its internal failure-recovery behavior is strengthened.

This task's build gate is **`python build_app.py`** (`SmapiInstaller.swift` is not part of the SPM target). There is no automated test coverage for this file in this repository (it performs live network downloads and mutates the real game directory) — validation is manual, per Step 4.

**Context**: the fork's `install()` already backs up the single `StardewValley` launcher binary to `StardewValley-original` before overwriting it (this backup is *permanent* — `uninstall()` and `SmapiInstaller.getInstalledVersion(gameDir:)` both depend on it existing after a successful install, so it must **not** be touched by this task). What the fork's rollback is missing, and upstream's has: if the payload-copy loop fails partway through (e.g. disk full on file 5 of 10), only the launcher binary gets restored on failure — the other files the loop already overwrote in `gameDir` (e.g. `smapi-internal` contents) stay overwritten. Upstream tracks every copied item and restores each one individually. This task ports that mechanism into the fork's version, on top of the fork's existing upfront validations (HTTP status, unzip exit code, empty-payload check) which upstream lacks and which this task must not remove.

- [ ] **Step 1: Add per-item rollback tracking**

In `StarHubTH/SmapiInstaller.swift`, find:
```swift
            let fm = FileManager.default
            let targetGameBin = (gameDir as NSString).appendingPathComponent("StardewValley")
            let backupGameBin = (gameDir as NSString).appendingPathComponent("StardewValley-original")
            // Set once we start overwriting files in `gameDir` itself, so the
            // catch block below only attempts a rollback for failures that
            // happen after the game's own launcher was actually touched —
            // not for a download/extract failure that never got that far.
            var gameFilesModified = false
```
Replace with:
```swift
            let fm = FileManager.default
            let targetGameBin = (gameDir as NSString).appendingPathComponent("StardewValley")
            let backupGameBin = (gameDir as NSString).appendingPathComponent("StardewValley-original")
            // Set once we start overwriting files in `gameDir` itself, so the
            // catch block below only attempts a rollback for failures that
            // happen after the game's own launcher was actually touched —
            // not for a download/extract failure that never got that far.
            var gameFilesModified = false
            // Every payload item this run has copied into `gameDir`, in copy
            // order — lets a failure partway through the loop below undo
            // exactly what this run changed (not just the launcher binary).
            // Declared here (not inside the `do` block) because `do`-scoped
            // locals aren't visible to the matching `catch`.
            var installedItems: [String] = []
            // Transient per-run staging for items this run overwrites, so
            // they can be moved back on failure. Distinct from
            // `backupGameBin`, which is a *permanent* record `uninstall()`
            // and `getInstalledVersion(gameDir:)` rely on — this directory
            // is always removed at the end of this run, success or failure.
            let rollbackStagingDir = URL(fileURLWithPath: tempDir).appendingPathComponent("smapi_install_rollback")
```

- [ ] **Step 2: Create the staging directory before the copy loop, and stage-then-copy each item**

Find:
```swift
                // From here on we're overwriting files inside `gameDir`; if
                // anything below throws, the catch block restores the
                // original launcher from `backupGameBin` rather than leaving
                // the game in a half-installed, unplayable state.
                gameFilesModified = true

                for item in payloadItems {
                    if item.hasPrefix(".") { continue }
                    let srcItem = (sourcePayload as NSString).appendingPathComponent(item)
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    if fm.fileExists(atPath: destItem) { try fm.removeItem(atPath: destItem) }
                    try fm.copyItem(atPath: srcItem, toPath: destItem)
                }
```
Replace with:
```swift
                // From here on we're overwriting files inside `gameDir`; if
                // anything below throws, the catch block restores the
                // original launcher from `backupGameBin` rather than leaving
                // the game in a half-installed, unplayable state.
                gameFilesModified = true

                if fm.fileExists(atPath: rollbackStagingDir.path) {
                    try? fm.removeItem(at: rollbackStagingDir)
                }
                try fm.createDirectory(at: rollbackStagingDir, withIntermediateDirectories: true, attributes: nil)

                for item in payloadItems {
                    if item.hasPrefix(".") { continue }
                    let srcItem = (sourcePayload as NSString).appendingPathComponent(item)
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    if fm.fileExists(atPath: destItem) {
                        let stagedItem = rollbackStagingDir.appendingPathComponent(item).path
                        try fm.moveItem(atPath: destItem, toPath: stagedItem)
                    }
                    try fm.copyItem(atPath: srcItem, toPath: destItem)
                    installedItems.append(item)
                }
```

- [ ] **Step 3: Clean up the staging directory on success, and roll back per-item on failure**

Find:
```swift
                try? fm.removeItem(at: zipDest)
                try? fm.removeItem(at: extractDir)
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, L10n.Smapi.installSuccess, nil)
                }
                
            } catch {
                let installErrorMessage = error.localizedDescription
                // If we'd already started overwriting the game's own files
                // when this failed, try to put the original launcher back
                // rather than leaving the game unplayable.
                if gameFilesModified && fm.fileExists(atPath: backupGameBin) {
```
Replace with:
```swift
                try? fm.removeItem(at: rollbackStagingDir)
                try? fm.removeItem(at: zipDest)
                try? fm.removeItem(at: extractDir)
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isInstalling = false
                    completion(true, L10n.Smapi.installSuccess, nil)
                }
                
            } catch {
                let installErrorMessage = error.localizedDescription

                // Undo every payload item this run already copied in, restoring
                // whatever was staged aside for it (or just removing it if the
                // item didn't exist before this run), so a failure partway
                // through the copy loop doesn't leave a mix of old and new files.
                for item in installedItems.reversed() {
                    let destItem = (gameDir as NSString).appendingPathComponent(item)
                    let stagedItem = rollbackStagingDir.appendingPathComponent(item).path
                    try? fm.removeItem(atPath: destItem)
                    if fm.fileExists(atPath: stagedItem) {
                        try? fm.moveItem(atPath: stagedItem, toPath: destItem)
                    }
                }
                try? fm.removeItem(at: rollbackStagingDir)

                // If we'd already started overwriting the game's own files
                // when this failed, try to put the original launcher back
                // rather than leaving the game unplayable.
                if gameFilesModified && fm.fileExists(atPath: backupGameBin) {
```

- [ ] **Step 4: Build and manually validate**

Run: `python build_app.py`
Expected: builds successfully, no `error:` from `swiftc` in `SmapiInstaller.swift`.

Manual validation (no automated coverage exists for this file — see task header):
- [ ] Run a real SMAPI install via the app against a test Stardew Valley install; confirm it still succeeds end-to-end and `StardewValley-original` is created exactly as before.
- [ ] Run uninstall afterward; confirm it still works (this task does not touch `uninstall()`).
- [ ] If possible, simulate a mid-loop failure (e.g. temporarily revoke write permission on one file inside `gameDir` before installing) and confirm no payload file is left half-overwritten — everything present before the run is exactly restored.

- [ ] **Step 5: Commit**

```bash
git add StarHubTH/SmapiInstaller.swift
git commit -m "fix: roll back every overwritten file on a failed SMAPI install, not just the launcher"
```
