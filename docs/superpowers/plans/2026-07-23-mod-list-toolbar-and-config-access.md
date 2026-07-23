# Mod List Toolbar Rework + Config Access Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the mods list toolbar (move/rename the Install button, extend sorting, add a "with configuration" filter) and add a per-row gear icon into the existing mod config editor, matching upstream's discoverability.

**Architecture:** All UI changes live in `StarHubTH/Views/ModListView.swift`. A new `ModItem.hasConfigFile: Bool` field (computed once during `StarHubTHViewModel.scanMods()`) backs both the new filter and the new row icon — no per-render filesystem checks. Version sorting reuses the existing `NexusUpdateChecker.compare(_:_:)` semver comparator.

**Tech Stack:** Swift 5.9, SwiftUI. See the design doc for the full rationale: `docs/superpowers/specs/2026-07-23-mod-list-toolbar-and-config-access-design.md`.

## Global Constraints

- **Build gate split**: `ModItem.swift` and `L10n.swift` are part of the `StarHubTHCore` SPM target (`Package.swift`) — `swift build` and `swift test` validate them, and existing tests in `Tests/ModConfigBackupManagerTests` and `Tests/ModInstallBackupManagerTests` construct `ModItem(...)` directly, so the new field's default value must keep those call sites compiling unchanged. `StarHubTHViewModel.swift` and `Views/ModListView.swift` are **not** in that target — only `python3 build_app.py` (raw `swiftc` over the whole app) validates changes to them. Every task below states its actual gate.
- **Localization**: only `en` and `th` locales exist (`assets/en.json`, `assets/th.json`, matching keys in `L10n.swift`). No `fr.json`. Never hand-edit `assets/*.lproj/Localizable.strings` — `python3 build_app.py` regenerates them from the two JSON files and aborts on key mismatch.
- **Reuse, don't duplicate**: version comparison reuses `NexusUpdateChecker.compare(_:_:) -> ComparisonResult` (`StarHubTH/NexusUpdateChecker.swift:688`) — no new comparison logic. The row's gear icon reuses the existing `L10n.Settings.configCodeEditor` key (already used for the context-menu "Code Editor" entry) rather than a new key.
- **Pack semantics**: a pack (`mod.isGroup == true`) is never itself "configurable" (its own folder has no `config.json`) — the "with configuration" filter uses `matchesSelfOrAnyChild(mod) { $0.hasConfigFile }` (existing helper, already used for search/issues) so a pack still appears in the filtered list if any child qualifies. The per-row gear icon is unrelated to this aggregation — it only ever looks at the row's own `mod.hasConfigFile`, guarded by `!mod.isGroup`.
- Commit after each task (established convention in this repository).

---

### Task 1: Data model — `ModItem.hasConfigFile` + all new localization keys

**Files:**
- Modify: `StarHubTH/ModItem.swift`
- Modify: `StarHubTH/StarHubTHViewModel.swift:479-571` (inside `scanMods()`)
- Modify: `StarHubTH/L10n.swift`
- Modify: `assets/en.json`
- Modify: `assets/th.json`

**Interfaces:**
- Produces: `ModItem.hasConfigFile: Bool` (default `false` in the initializer, so the two existing test-helper call sites in `Tests/ModConfigBackupManagerTests` and `Tests/ModInstallBackupManagerTests` keep compiling unchanged). Produces 6 new `L10n` keys consumed by Tasks 2–4: `L10n.Mods.sortNameDescending`, `.sortAuthor`, `.sortVersion`, `.configFilterLabel`, plus a changed value (not a new key) for the existing `L10n.Mods.sortName` and `L10n.ModInstall.installButton`.

This task's build gate is **both** `swift build` (for `ModItem.swift`/`L10n.swift`, part of the SPM target) **and** `python3 build_app.py` (for the `scanMods()` change in `StarHubTHViewModel.swift`, which is not in the SPM target).

- [ ] **Step 1: Add the field to `ModItem`**

In `StarHubTH/ModItem.swift`, find:
```swift
    public var installedFileDate: Date? = nil

    public init(
```
Replace with:
```swift
    public var installedFileDate: Date? = nil
    /// Whether the mod's own folder contains a `config.json`, captured at
    /// scan time. `false` for group headers (a pack's own folder never has
    /// one — only its children might) and for anything constructed without
    /// passing it explicitly (e.g. existing test helpers). Backs both the
    /// "with configuration" list filter and the per-row config-editor icon
    /// in `ModListView`.
    public let hasConfigFile: Bool

    public init(
```

- [ ] **Step 2: Thread it through the initializer**

In the same file, find:
```swift
        isGroup: Bool = false,
        installedFileDate: Date? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.version = version
        self.author = author
        self.description = description
        self.nexusUrl = nexusUrl
        self.nexusModId = nexusModId
        self.isEnabled = isEnabled
        self.dependencies = dependencies
        self.children = children
        self.isGroup = isGroup
        self.installedFileDate = installedFileDate
    }
```
Replace with:
```swift
        isGroup: Bool = false,
        installedFileDate: Date? = nil,
        hasConfigFile: Bool = false
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.version = version
        self.author = author
        self.description = description
        self.nexusUrl = nexusUrl
        self.nexusModId = nexusModId
        self.isEnabled = isEnabled
        self.dependencies = dependencies
        self.children = children
        self.isGroup = isGroup
        self.installedFileDate = installedFileDate
        self.hasConfigFile = hasConfigFile
    }
```

- [ ] **Step 3: Compute it during `scanMods()` and pass it to the real constructor**

In `StarHubTH/StarHubTHViewModel.swift`, find:
```swift
            let installedFileDate: Date? = {
                if let attrs = try? fm.attributesOfItem(atPath: path) {
                    return attrs[.modificationDate] as? Date
                }
                return nil
            }()

            var name = (path as NSString).lastPathComponent
```
Replace with:
```swift
            let installedFileDate: Date? = {
                if let attrs = try? fm.attributesOfItem(atPath: path) {
                    return attrs[.modificationDate] as? Date
                }
                return nil
            }()
            let hasConfigFile = fm.fileExists(atPath: (path as NSString).appendingPathComponent("config.json"))

            var name = (path as NSString).lastPathComponent
```

Then find:
```swift
                isEnabled: isEnabled,
                dependencies: dependencies,
                installedFileDate: installedFileDate
            )
        }
        
        // Helper to recursively scan folders for manifest.json and group them
```
Replace with:
```swift
                isEnabled: isEnabled,
                dependencies: dependencies,
                installedFileDate: installedFileDate,
                hasConfigFile: hasConfigFile
            )
        }
        
        // Helper to recursively scan folders for manifest.json and group them
```

- [ ] **Step 4: Add the new `L10n.Mods` keys and update the existing `sortName` value**

In `StarHubTH/L10n.swift`, find:
```swift
        static let sortName             = "mods_sort_name"
        static let sortActivationOrder  = "mods_sort_activation_order"
        static let sortInstallDate      = "mods_sort_install_date"
        // Nexus category filter
```
Replace with:
```swift
        static let sortName             = "mods_sort_name"
        static let sortNameDescending   = "mods_sort_name_descending"
        static let sortActivationOrder  = "mods_sort_activation_order"
        static let sortInstallDate      = "mods_sort_install_date"
        static let sortAuthor           = "mods_sort_author"
        static let sortVersion          = "mods_sort_version"
        static let configFilterLabel    = "mods_config_filter_label"
        // Nexus category filter
```

- [ ] **Step 5: Add the English strings and update the existing one**

In `assets/en.json`, find:
```json
  "mods_sort_install_date": "Install Date",
```
Replace with:
```json
  "mods_sort_install_date": "Install Date",
  "mods_sort_author": "Author",
  "mods_sort_version": "Version",
  "mods_config_filter_label": "With Config",
```
Then find:
```json
  "mods_sort_name": "Name",
```
Replace with:
```json
  "mods_sort_name": "Name (A-Z)",
```
Then add the new descending-name key — find:
```json
  "mods_sort_name": "Name (A-Z)",
```
Replace with:
```json
  "mods_sort_name": "Name (A-Z)",
  "mods_sort_name_descending": "Name (Z-A)",
```
Finally, find:
```json
  "mod_install_button": "Install",
```
Replace with:
```json
  "mod_install_button": "Install mods",
```

- [ ] **Step 6: Add the Thai strings and update the existing one**

In `assets/th.json`, find:
```json
  "mods_sort_install_date": "วันที่ติดตั้ง",
```
Replace with:
```json
  "mods_sort_install_date": "วันที่ติดตั้ง",
  "mods_sort_author": "ผู้สร้าง",
  "mods_sort_version": "เวอร์ชัน",
  "mods_config_filter_label": "มีการตั้งค่า",
```
Then find:
```json
  "mods_sort_name": "ชื่อ",
```
Replace with:
```json
  "mods_sort_name": "ชื่อ (ก-ฮ)",
  "mods_sort_name_descending": "ชื่อ (ฮ-ก)",
```
Finally, find:
```json
  "mod_install_button": "ติดตั้ง",
```
Replace with:
```json
  "mod_install_button": "ติดตั้งม็อด",
```

- [ ] **Step 7: Build and verify**

Run: `python3 build_app.py`
Expected: succeeds, no `[ERROR]` from the localization parity check (both JSON files must end up with exactly the same 6 new keys), no `swiftc` errors.

Run: `swift build`
Expected: `Build complete!` — confirms `ModItem.swift`/`L10n.swift` compile and the SPM target (which includes the two test targets that construct `ModItem`) still builds.

Run: `swift test`
Expected: attempts to run — if this environment shows `error: no such module 'Testing'`, that is a pre-existing, unrelated environment limitation (confirmed earlier in this project's history), not a regression from this change; note it in the report but do not treat it as a failure. If `Testing` *is* available, all existing tests must still pass (the new field has a default, so no existing test's `ModItem(...)` call should need changes).

- [ ] **Step 8: Commit**

```bash
git add StarHubTH/ModItem.swift StarHubTH/StarHubTHViewModel.swift StarHubTH/L10n.swift assets/en.json assets/th.json assets/en.lproj/Localizable.strings assets/th.lproj/Localizable.strings
git commit -m "feat: add ModItem.hasConfigFile and localization keys for mod list toolbar rework"
```

---

### Task 2: Extended sort (Z-A, Author, Version) + fixed sort-button icon

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift`

**Interfaces:**
- Consumes: `ModItem.author`, `.version` (already existed); `NexusUpdateChecker.compare(_:_:) -> ComparisonResult`; `L10n.Mods.sortNameDescending`, `.sortAuthor`, `.sortVersion` (Task 1).
- Produces: `ModSortOrder` gains cases `.nameDescending`, `.author`, `.version`, consumed by nothing outside this file.

This task's build gate is **`python3 build_app.py`** — `ModListView.swift` is not part of the SPM target.

- [ ] **Step 1: Extend the sort-order enum**

Find:
```swift
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, activationOrder, installDate
    var id: String { rawValue }
}
```
Replace with:
```swift
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, nameDescending, activationOrder, installDate, author, version
    var id: String { rawValue }
}
```

- [ ] **Step 2: Add the new sorting rules**

Find:
```swift
                case .installDate:
                    let lhsDate = effectiveInstallDate(for: lhs)
                    let rhsDate = effectiveInstallDate(for: rhs)
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
            }
    }
```
Replace with:
```swift
                case .installDate:
                    let lhsDate = effectiveInstallDate(for: lhs)
                    let rhsDate = effectiveInstallDate(for: rhs)
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                case .nameDescending:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                case .author:
                    let authorOrder = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
                    if authorOrder != .orderedSame { return authorOrder == .orderedAscending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .version:
                    let versionOrder = NexusUpdateChecker.compare(lhs.version, rhs.version)
                    if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }
```

- [ ] **Step 3: Fix the sort button's own icon and add the new menu entries**

Find:
```swift
    private var sortPicker: some View {
        Menu {
            Button {
                selectedSort = .name
            } label: {
                Label(vm.L(L10n.Mods.sortName), systemImage: "textformat")
            }
            Button {
                selectedSort = .activationOrder
            } label: {
                Label(vm.L(L10n.Mods.sortActivationOrder), systemImage: "clock.arrow.circlepath")
            }
            Button {
                selectedSort = .installDate
            } label: {
                Label(vm.L(L10n.Mods.sortInstallDate), systemImage: "calendar.badge.clock")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sortIcon)
                    .font(.system(size: 11))
                Text(sortLabel)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
```
Replace with:
```swift
    private var sortPicker: some View {
        Menu {
            Button {
                selectedSort = .name
            } label: {
                Label(vm.L(L10n.Mods.sortName), systemImage: "textformat")
            }
            Button {
                selectedSort = .nameDescending
            } label: {
                Label(vm.L(L10n.Mods.sortNameDescending), systemImage: "textformat.size.larger")
            }
            Button {
                selectedSort = .activationOrder
            } label: {
                Label(vm.L(L10n.Mods.sortActivationOrder), systemImage: "clock.arrow.circlepath")
            }
            Button {
                selectedSort = .installDate
            } label: {
                Label(vm.L(L10n.Mods.sortInstallDate), systemImage: "calendar.badge.clock")
            }
            Button {
                selectedSort = .author
            } label: {
                Label(vm.L(L10n.Mods.sortAuthor), systemImage: "person")
            }
            Button {
                selectedSort = .version
            } label: {
                Label(vm.L(L10n.Mods.sortVersion), systemImage: "number")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(sortLabel)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
```

- [ ] **Step 4: Remove the now-unused `sortIcon` and extend `sortLabel`**

Find:
```swift
    private var sortIcon: String {
        switch selectedSort {
        case .name: return "textformat"
        case .activationOrder: return "clock.arrow.circlepath"
        case .installDate: return "calendar.badge.clock"
        }
    }

    private var sortLabel: String {
        switch selectedSort {
        case .name: return vm.L(L10n.Mods.sortName)
        case .activationOrder: return vm.L(L10n.Mods.sortActivationOrder)
        case .installDate: return vm.L(L10n.Mods.sortInstallDate)
        }
    }
```
Replace with:
```swift
    private var sortLabel: String {
        switch selectedSort {
        case .name: return vm.L(L10n.Mods.sortName)
        case .nameDescending: return vm.L(L10n.Mods.sortNameDescending)
        case .activationOrder: return vm.L(L10n.Mods.sortActivationOrder)
        case .installDate: return vm.L(L10n.Mods.sortInstallDate)
        case .author: return vm.L(L10n.Mods.sortAuthor)
        case .version: return vm.L(L10n.Mods.sortVersion)
        }
    }
```
(`sortIcon` is deleted outright — the button's icon is now the fixed `"arrow.up.arrow.down"` inlined in Step 3, so the per-case computed icon has no remaining caller.)

- [ ] **Step 5: Build and verify**

Run: `python3 build_app.py`
Expected: builds successfully. If `sortIcon` is referenced anywhere else, `swiftc` will report an error naming that call site — re-check Step 4 didn't miss a caller (none should exist; it was only ever used in Step 3's original block, already replaced).

Manual check: launch the app, open the sort menu on the Mods page, confirm 6 entries appear in this order — Name, Name (Z-A), Activation Order, Install Date, Author, Version — and that picking each one actually reorders the list, with the button's icon staying the fixed sort glyph regardless of selection.

- [ ] **Step 6: Commit**

```bash
git add StarHubTH/Views/ModListView.swift
git commit -m "feat: add Z-A/author/version mod sort options, fix sort button icon"
```

---

### Task 3: "With configuration" filter

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift`

**Interfaces:**
- Consumes: `ModItem.hasConfigFile` (Task 1), `matchesSelfOrAnyChild(_:_:)` (existing helper, `ModListView.swift:56`), `L10n.Mods.configFilterLabel` (Task 1).
- Produces: `@State private var configOnlyFilter: Bool`, consumed only within this file.

This task's build gate is **`python3 build_app.py`**.

- [ ] **Step 1: Add the filter state**

Find:
```swift
    @State private var selectedSort: ModSortOrder = .name
```
Replace with:
```swift
    @State private var selectedSort: ModSortOrder = .name
    /// Scopes the list to mods (or packs with at least one qualifying child)
    /// that have a `config.json`. Combines with the category/scope filters —
    /// AND semantics, same as every other filter in `filteredMods`.
    @State private var configOnlyFilter: Bool = false
```

- [ ] **Step 2: Add the filter predicate**

Find:
```swift
            .filter { mod in
                switch selectedCategory {
                case .all:
                    return true
                case .category(let cat):
                    // `vm.category(for:)` already resolves a group to its
                    // dominant child category, so this agrees with the badge
                    // shown on the group's own row by construction.
                    return vm.category(for: mod)?.id == cat.id
                case .uncategorized:
                    // Same reasoning: `vm.category(for:)` returns nil for a
                    // group exactly when none of its children have a known
                    // category, matching what its badge (absence) shows.
                    return vm.category(for: mod) == nil
                }
            }
            .sorted { lhs, rhs in
```
Replace with:
```swift
            .filter { mod in
                switch selectedCategory {
                case .all:
                    return true
                case .category(let cat):
                    // `vm.category(for:)` already resolves a group to its
                    // dominant child category, so this agrees with the badge
                    // shown on the group's own row by construction.
                    return vm.category(for: mod)?.id == cat.id
                case .uncategorized:
                    // Same reasoning: `vm.category(for:)` returns nil for a
                    // group exactly when none of its children have a known
                    // category, matching what its badge (absence) shows.
                    return vm.category(for: mod) == nil
                }
            }
            .filter { mod in
                !configOnlyFilter || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
            }
            .sorted { lhs, rhs in
```

- [ ] **Step 3: Add the toggle button**

Find:
```swift
    // MARK: - Category picker
```
Replace with:
```swift
    // MARK: - Config-only filter toggle

    /// Toggle button scoping the list to mods with a `config.json` (see
    /// `configOnlyFilter`). Same visual family as `sortPicker`/
    /// `categoryPicker` (rounded chip, same padding/font), but a plain
    /// toggle rather than a menu — there's only one on/off state, not a
    /// set of choices.
    private var configFilterToggle: some View {
        Button {
            configOnlyFilter.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                Text(vm.L(L10n.Mods.configFilterLabel))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(configOnlyFilter ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configOnlyFilter ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(configOnlyFilter ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(vm.L(L10n.Mods.configFilterLabel))
    }

    // MARK: - Category picker
```

- [ ] **Step 4: Wire it into the filter row**

Find:
```swift
                        Spacer()

                        sortPicker

                        // Category filter (Menu picker). Populated from every
```
Replace with:
```swift
                        Spacer()

                        sortPicker

                        configFilterToggle

                        // Category filter (Menu picker). Populated from every
```

- [ ] **Step 5: Build and verify**

Run: `python3 build_app.py`
Expected: builds successfully.

Manual check: launch the app, click the new "With Config" toggle on the Mods page — the list should narrow to mods (and packs with at least one configurable child) that have a `config.json`; click again to clear it. Combine with a category filter to confirm they narrow together (AND, not OR).

- [ ] **Step 6: Commit**

```bash
git add StarHubTH/Views/ModListView.swift
git commit -m "feat: add \"with configuration\" filter to mod list"
```

---

### Task 4: Move/rename Install button + per-row config-editor gear icon

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift`

**Interfaces:**
- Consumes: `L10n.ModInstall.installButton` (value changed in Task 1, key unchanged), `L10n.Settings.configCodeEditor` (existing key, reused — not new), `vm.editingModConfig` (existing `StarHubTHViewModel` property), `ModItem.hasConfigFile` (Task 1), `ModItem.isGroup` (existing).

This task's build gate is **`python3 build_app.py`**.

- [ ] **Step 1: Remove the Install button from its own row**

Find:
```swift
                // ── Install Button ─────────────────────────────────────────
                HStack {
                    Button {
                        showInstallSheet = true
                    } label: {
                        Label(vm.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                .padding(.bottom, 8)

                // ── Scope filter ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("", selection: $selectedFilter) {
```
Replace with:
```swift
                // ── Scope filter ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("", selection: $selectedFilter) {
```

- [ ] **Step 2: Add it to the right of the filter row**

Find:
```swift
                        categoryPicker(categories: categories, uncatCount: uncatCount)
                            .disabled(categories.isEmpty && uncatCount == 0)
                            .help(categories.isEmpty && uncatCount == 0
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))
                    }
                    if categories.isEmpty && uncatCount == 0 {
```
Replace with:
```swift
                        categoryPicker(categories: categories, uncatCount: uncatCount)
                            .disabled(categories.isEmpty && uncatCount == 0)
                            .help(categories.isEmpty && uncatCount == 0
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))

                        Button {
                            showInstallSheet = true
                        } label: {
                            Label(vm.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if categories.isEmpty && uncatCount == 0 {
```

- [ ] **Step 3: Add the gear icon to the mod row**

Find:
```swift
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openFolder))
                .pointingHandCursor()

                // Direct "open on Nexus" button — visible whenever the mod has
```
Replace with:
```swift
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openFolder))
                .pointingHandCursor()

                // Direct config-editor access, mirroring upstream's
                // discoverability: visible only for a standalone mod (never
                // a pack header, which has no config.json of its own) that
                // actually has a config.json. The right-click "Code Editor"
                // context-menu entry stays as an additional entry point.
                if !mod.isGroup && mod.hasConfigFile {
                    Button {
                        vm.editingModConfig = mod
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Settings.configCodeEditor))
                    .pointingHandCursor()
                }

                // Direct "open on Nexus" button — visible whenever the mod has
```

- [ ] **Step 4: Build and verify**

Run: `python3 build_app.py`
Expected: builds successfully.

Manual check: launch the app, confirm "Install mods" appears at the right end of the filter row (not in its own row above it anymore) and still opens the install sheet. Confirm a mod with a `config.json` shows a gear icon on its row (between the folder icon and the Nexus/info icons) that opens the config editor, and that a mod without one does not show the icon. Confirm the right-click "Code Editor" entry still works independently.

- [ ] **Step 5: Commit**

```bash
git add StarHubTH/Views/ModListView.swift
git commit -m "feat: move/rename Install button, add per-row config-editor gear icon"
```

