# Tri par ordre d'activation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sort mode to the mods list that orders mods by when each was last activated (most recent first), alongside the existing alphabetical order.

**Architecture:** `StarHubTHViewModel` records a `Date` per `folderName` every time a mod (or pack, moved as a single folder) transitions from disabled to enabled — in `toggleMod()` and `applyProfileToFilesystem()` — persisted in UserDefaults like the existing `nexusCustomCategories`/`nexusCustomModIds` maps. `ModListView` gets a new sort-mode menu next to the existing category filter; choosing "Activation order" sorts `filteredMods` by that map (missing entries sort last, tie-broken by name).

**Tech Stack:** Swift 5 / SwiftUI (macOS 14+ target). No automated test target in this repo — verification is `python3 build_app.py` plus manual exercise of the built app.

## Global Constraints

- Deployment target is macOS 14.0.
- Follow the existing code style: doc comments only where the *why* is non-obvious, `vm.L(...)` for all user-facing strings.
- `en.json` and `th.json` must contain exactly the same keys — the build validates this parity.
- The timestamp is keyed by `ModItem.folderName` and only ever written on a disabled→enabled transition — never on disable. This applies uniformly to standalone mods and packs, since both are moved as a single folder (confirmed in the spec).

---

### Task 1: Record and persist per-mod activation timestamps

**Files:**
- Modify: `StarHubTH/StarHubTHViewModel.swift` (multiple locations — see steps)

**Interfaces:**
- Produces: `StarHubTHViewModel.modActivationTimestamps: [String: Date]` (published, keyed by `folderName`) — consumed by Task 2's sort.

- [ ] **Step 1: Add the published property**

Find:

```swift
    @Published var nexusCustomModIds: [String: String] = [:]
```

Replace with:

```swift
    @Published var nexusCustomModIds: [String: String] = [:]

    /// `{ folderName: lastActivatedDate }` — stamped every time a mod (or a
    /// whole pack, which moves as a single folder) transitions from
    /// disabled to enabled, in `toggleMod()` and
    /// `applyProfileToFilesystem()`. Never touched on disable — it records
    /// the *last activation*, not the last state change. Drives the
    /// "Activation order" sort in the mods list. Persisted in UserDefaults.
    @Published var modActivationTimestamps: [String: Date] = [:]
```

- [ ] **Step 2: Seed it at init**

Find:

```swift
        self.nexusCustomModIds = Self.loadCustomModIds()
```

Replace with:

```swift
        self.nexusCustomModIds = Self.loadCustomModIds()
        self.modActivationTimestamps = Self.loadModActivationTimestamps()
```

- [ ] **Step 3: Add the persistence helpers**

Find:

```swift
    private static func saveCustomModIds(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: customModIdsKey)
    }
```

Replace with:

```swift
    private static func saveCustomModIds(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: customModIdsKey)
    }

    private static let modActivationTimestampsKey = "modActivationTimestamps"

    private static func loadModActivationTimestamps() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: modActivationTimestampsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private static func saveModActivationTimestamps(_ map: [String: Date]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: modActivationTimestampsKey)
    }
```

- [ ] **Step 4: Stamp activations in `toggleMod()`**

Find:

```swift
        for folderName in foldersToToggle {
            guard let m = self.mods.first(where: { $0.folderName == folderName }) else { continue }
            if m.isEnabled == targetState { continue }
            
            let srcPath = ((m.isEnabled ? modsPath : disabledModsPath) as NSString).appendingPathComponent(m.folderName)
            let destFolder = m.isEnabled ? disabledModsPath : modsPath
            let destPath = ((destFolder as NSString).appendingPathComponent(m.folderName) as String)
            
            do {
                let destParent = (destPath as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: destParent) {
                    try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
                }
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.moveItem(atPath: srcPath, toPath: destPath)
                anyMoved = true
            } catch {
                print("Failed to toggle \(m.name): \(error.localizedDescription)")
            }
        }
        
        if anyMoved {
```

Replace with:

```swift
        for folderName in foldersToToggle {
            guard let m = self.mods.first(where: { $0.folderName == folderName }) else { continue }
            if m.isEnabled == targetState { continue }
            
            let srcPath = ((m.isEnabled ? modsPath : disabledModsPath) as NSString).appendingPathComponent(m.folderName)
            let destFolder = m.isEnabled ? disabledModsPath : modsPath
            let destPath = ((destFolder as NSString).appendingPathComponent(m.folderName) as String)
            
            do {
                let destParent = (destPath as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: destParent) {
                    try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
                }
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.moveItem(atPath: srcPath, toPath: destPath)
                anyMoved = true
                if targetState {
                    self.modActivationTimestamps[folderName] = Date()
                }
            } catch {
                print("Failed to toggle \(m.name): \(error.localizedDescription)")
            }
        }

        if anyMoved {
            if targetState {
                Self.saveModActivationTimestamps(self.modActivationTimestamps)
            }
```

- [ ] **Step 5: Stamp activations in `applyProfileToFilesystem()`**

Find:

```swift
        // Enable mods in profile
        for mod in mods.filter({ !$0.isEnabled }) {
            if isCoveredByProfile(mod) {
                let src = (disabledModsPath as NSString).appendingPathComponent(mod.folderName)
                let dst = (modsPath as NSString).appendingPathComponent(mod.folderName)
                try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true, attributes: nil)
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.scanMods()
            DispatchQueue.main.async {
                self.syncActiveProfileIds()
            }
        }
```

Replace with:

```swift
        // Enable mods in profile
        var anyEnabled = false
        for mod in mods.filter({ !$0.isEnabled }) {
            if isCoveredByProfile(mod) {
                let src = (disabledModsPath as NSString).appendingPathComponent(mod.folderName)
                let dst = (modsPath as NSString).appendingPathComponent(mod.folderName)
                try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true, attributes: nil)
                try? fm.moveItem(atPath: src, toPath: dst)
                self.modActivationTimestamps[mod.folderName] = Date()
                anyEnabled = true
            }
        }
        if anyEnabled {
            Self.saveModActivationTimestamps(self.modActivationTimestamps)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.scanMods()
            DispatchQueue.main.async {
                self.syncActiveProfileIds()
            }
        }
```

- [ ] **Step 6: Build to confirm it compiles**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

---

### Task 2: Sort selector in the mods list

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift` (state, `filteredMods`, new menu, `body` wiring)
- Modify: `StarHubTH/L10n.swift`, `assets/en.json`, `assets/th.json` (new sort-menu strings)

**Interfaces:**
- Consumes: `vm.modActivationTimestamps: [String: Date]` from Task 1.
- Produces: `ModSortOrder` enum (`.name` / `.activationOrder`) — local to `ModListView`, not consumed elsewhere.

- [ ] **Step 1: Add the localization keys**

In `assets/en.json`, find (alphabetically near the existing category-filter keys):

```json
  "mods_category_filter": "Category",
```

Insert three new keys directly before it (alphabetically `mods_category_filter` < `mods_sort_*`, but exact position doesn't matter for JSON — insert here to keep sort-related keys grouped with the other menu keys just above):

```json
  "mods_sort_by": "Sort",
  "mods_sort_name": "Name",
  "mods_sort_activation_order": "Activation Order",
  "mods_category_filter": "Category",
```

In `assets/th.json`, find:

```json
  "mods_category_filter": "หมวดหมู่",
```

Insert:

```json
  "mods_sort_by": "เรียงตาม",
  "mods_sort_name": "ชื่อ",
  "mods_sort_activation_order": "ลำดับการเปิดใช้งาน",
  "mods_category_filter": "หมวดหมู่",
```

In `StarHubTH/L10n.swift`, find:

```swift
        // Nexus category filter
        static let categoryFilter           = "mods_category_filter"
```

Replace with:

```swift
        static let sortBy               = "mods_sort_by"
        static let sortName             = "mods_sort_name"
        static let sortActivationOrder  = "mods_sort_activation_order"
        // Nexus category filter
        static let categoryFilter           = "mods_category_filter"
```

- [ ] **Step 2: Build to confirm the new keys are valid and parity holds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` — no key-parity error (the new keys are unused so far, which is fine).

- [ ] **Step 3: Add `ModSortOrder` and the `selectedSort` state**

In `StarHubTH/Views/ModListView.swift`, find:

```swift
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case uncategorized
}
```

Replace with:

```swift
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case uncategorized
}

/// Sort order for the mods list. `.name` matches `vm.mods`'s existing
/// alphabetical order (so no extra sort is needed for it); `.activationOrder`
/// sorts by `vm.modActivationTimestamps`, most recent first.
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, activationOrder
    var id: String { rawValue }
}
```

Find:

```swift
    @State private var selectedCategory: CategoryScope = .all
```

Replace with:

```swift
    @State private var selectedCategory: CategoryScope = .all
    @State private var selectedSort: ModSortOrder = .name
```

- [ ] **Step 4: Apply the sort in `filteredMods`**

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
    }
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
            .sorted { lhs, rhs in
                switch selectedSort {
                case .name:
                    // `vm.mods` is already alphabetical (see `scanMods()`),
                    // and `.sorted` is stable, so this is a no-op ordering
                    // pass — kept as an explicit case so the switch stays
                    // exhaustive and self-documenting.
                    return false
                case .activationOrder:
                    let lhsDate = vm.modActivationTimestamps[lhs.folderName]
                    let rhsDate = vm.modActivationTimestamps[rhs.folderName]
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

- [ ] **Step 5: Add the sort menu**

`categoryPicker` exists as a private property in *two* different structs in
this file (`ModListView`'s list-wide filter, and `ModDetailsPopover`'s
per-mod editor) — target the `ModListView` one, identified by the doc
comment directly above it. Find:

```swift
    // MARK: - Category picker

    /// Dropdown listing every category present in the installed mods list.
    /// Selecting one scopes the list to that category; selecting "All" clears
    /// it. Each row shows the category color + localized name + mod count.
    private var categoryPicker: some View {
```

Insert a new `sortPicker` property directly before it:

```swift
    /// Dropdown choosing how the mods list is ordered. `.name` mirrors the
    /// list's default (already-alphabetical) order; `.activationOrder`
    /// sorts by `vm.modActivationTimestamps` (see `filteredMods`).
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
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedSort == .activationOrder ? "clock.arrow.circlepath" : "textformat")
                    .font(.system(size: 11))
                Text(selectedSort == .activationOrder ? vm.L(L10n.Mods.sortActivationOrder) : vm.L(L10n.Mods.sortName))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var categoryPicker: some View {
```

- [ ] **Step 6: Wire `sortPicker` into the toolbar row**

Find:

```swift
                        Spacer()

                        // Category filter (Menu picker). Populated from every
                        // mod's effective category (manual override or API).
                        categoryPicker
                            .disabled(availableCategories.isEmpty && uncategorizedCount == 0)
                            .help(availableCategories.isEmpty && uncategorizedCount == 0
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))
                    }
```

Replace with:

```swift
                        Spacer()

                        sortPicker

                        // Category filter (Menu picker). Populated from every
                        // mod's effective category (manual override or API).
                        categoryPicker
                            .disabled(availableCategories.isEmpty && uncategorizedCount == 0)
                            .help(availableCategories.isEmpty && uncategorizedCount == 0
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))
                    }
```

- [ ] **Step 7: Build to confirm it compiles**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 8: Manual verification in the running app**

Run: `open StarHubTH.app`

1. Open the Mods tab. Confirm a new "Name" / "Activation Order" menu appears next to the category filter, defaulting to "Name" with the current alphabetical order unchanged.
2. Enable a mod that was previously disabled. Switch the sort menu to "Activation Order" — confirm that mod now appears at (or near) the top.
3. Enable a whole pack (not an individual mod inside it) — confirm the pack itself moves to the top in Activation Order, and that this doesn't affect the pack's children's own order when expanded.
4. Confirm mods never toggled through the app (or installed before this feature) appear after every mod with a recorded activation, sorted alphabetically among themselves.
5. Switch back to "Name" — confirm the list returns to the original alphabetical order.
6. Confirm the sort choice persists across search text changes, category filter changes, and scope changes (All/Enabled/Disabled/Issues) — it should only change when the user picks a different option from the new menu.
