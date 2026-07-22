# Filtre "Sans catégorie" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "No Category" entry to the existing category filter menu in `ModListView` so the user can scope the mod list to mods (standalone or whole packs) with no category assigned.

**Architecture:** Replace the `selectedCategory: NexusCategory?` state in `ModListView` with a 3-case `CategoryScope` enum (`.all` / `.category(NexusCategory)` / `.uncategorized`), so "no filter", "one category selected", and "uncategorized selected" are mutually exclusive by construction. Filtering, the menu's item list, the button label, and the disabled/hint condition all switch on this enum.

**Tech Stack:** Swift 5 / SwiftUI (macOS 14+ target), no automated test target in this repo — verification is `python3 build_app.py` (compiles + regenerates `.strings` + enforces en/th key parity) plus manual exercise of the built app.

## Global Constraints

- `en.json` and `th.json` must contain exactly the same keys — the build validates this parity (see `docs/superpowers/specs/2026-07-19-uncategorized-mod-filter-design.md`).
- Deployment target is macOS 14.0 — don't use APIs newer than that.
- Follow the existing code style in `ModListView.swift`: doc comments only where the *why* is non-obvious, `vm.L(...)` for all user-facing strings.

---

### Task 1: Localization key for "No Category"

**Files:**
- Modify: `assets/en.json:83`
- Modify: `assets/th.json:83`
- Modify: `StarHubTH/L10n.swift:149`

**Interfaces:**
- Produces: `L10n.Mods.categoryFilterUncategorized` (String constant, value `"mods_category_filter_uncategorized"`) — consumed by Task 2's menu item and button label.

- [ ] **Step 1: Add the English string**

In `assets/en.json`, the category-filter block currently reads (lines 82-86):

```json
  "mods_category_filter": "Category",
  "mods_category_filter_all": "All Categories",
  "mods_category_filter_clear": "Clear category filter",
  "mods_category_filter_empty_hint": "Assign categories to mods (via the info button) or run a Nexus Mods update check to populate them.",
  "mods_category_filter_hint": "Filter mods by Nexus category",
```

Insert a new line directly after `mods_category_filter_all`:

```json
  "mods_category_filter": "Category",
  "mods_category_filter_all": "All Categories",
  "mods_category_filter_uncategorized": "No Category",
  "mods_category_filter_clear": "Clear category filter",
  "mods_category_filter_empty_hint": "Assign categories to mods (via the info button) or run a Nexus Mods update check to populate them.",
  "mods_category_filter_hint": "Filter mods by Nexus category",
```

- [ ] **Step 2: Add the Thai string**

In `assets/th.json`, the equivalent block (lines 82-86):

```json
  "mods_category_filter": "หมวดหมู่",
  "mods_category_filter_all": "หมวดหมู่ทั้งหมด",
  "mods_category_filter_clear": "ล้างตัวกรองหมวดหมู่",
  "mods_category_filter_empty_hint": "กำหนดหมวดหมู่ให้ส่วนเสริมได้ผ่านปุ่มข้อมูล หรือเรียกตรวจอัปเดต Nexus Mods เพื่อโหลดหมวดหมู่อัตโนมัติ",
  "mods_category_filter_hint": "กรองส่วนเสริมตามหมวดหมู่ Nexus",
```

Insert a new line directly after `mods_category_filter_all`:

```json
  "mods_category_filter": "หมวดหมู่",
  "mods_category_filter_all": "หมวดหมู่ทั้งหมด",
  "mods_category_filter_uncategorized": "ไม่มีหมวดหมู่",
  "mods_category_filter_clear": "ล้างตัวกรองหมวดหมู่",
  "mods_category_filter_empty_hint": "กำหนดหมวดหมู่ให้ส่วนเสริมได้ผ่านปุ่มข้อมูล หรือเรียกตรวจอัปเดต Nexus Mods เพื่อโหลดหมวดหมู่อัตโนมัติ",
  "mods_category_filter_hint": "กรองส่วนเสริมตามหมวดหมู่ Nexus",
```

- [ ] **Step 3: Add the L10n constant**

In `StarHubTH/L10n.swift`, the `Mods` enum currently declares (lines 148-152):

```swift
        static let categoryFilter           = "mods_category_filter"
        static let categoryFilterAll        = "mods_category_filter_all"
        static let categoryFilterClear      = "mods_category_filter_clear"
        static let categoryFilterHint       = "mods_category_filter_hint"
        static let categoryFilterEmptyHint  = "mods_category_filter_empty_hint"
```

Add the new constant directly after `categoryFilterAll`:

```swift
        static let categoryFilter           = "mods_category_filter"
        static let categoryFilterAll        = "mods_category_filter_all"
        static let categoryFilterUncategorized = "mods_category_filter_uncategorized"
        static let categoryFilterClear      = "mods_category_filter_clear"
        static let categoryFilterHint       = "mods_category_filter_hint"
        static let categoryFilterEmptyHint  = "mods_category_filter_empty_hint"
```

- [ ] **Step 4: Build to confirm the new key is valid and parity holds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` — no key-parity error, no Swift compile error (the new constant is unused so far, which is fine).

- [ ] **Step 5: Commit**

```bash
git add assets/en.json assets/th.json StarHubTH/L10n.swift
git commit -m "Add localization key for uncategorized mod filter"
```

---

### Task 2: CategoryScope enum, filtering logic, and menu UI

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift:3-7` (enum block), `:13-19` (state), `:28-39` (`filteredMods`), `:100-121` (near `availableCategories`), `:170-183` (disabled/hint), `:361-420` (`categoryPicker`)

**Interfaces:**
- Consumes: `L10n.Mods.categoryFilterUncategorized` from Task 1.
- Produces: `CategoryScope` enum (`.all` / `.category(NexusCategory)` / `.uncategorized`) — this is the type of `selectedCategory` used throughout `ModListView`. `uncategorizedCount: Int` computed property.

- [ ] **Step 1: Add the `CategoryScope` enum**

In `StarHubTH/Views/ModListView.swift`, the file currently opens with (lines 1-7):

```swift
import SwiftUI

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
}
```

Add the new enum directly after `ModFilter`:

```swift
import SwiftUI

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
}

/// Scope for the category-filter menu: show everything, scope to one Nexus
/// category, or scope to mods with no category assigned. A single enum
/// (rather than `NexusCategory?` plus a separate boolean) keeps these three
/// states mutually exclusive by construction.
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case uncategorized
}
```

- [ ] **Step 2: Change the `selectedCategory` state to use `CategoryScope`**

The current declaration (lines 13-16):

```swift
    /// Selected Nexus category, or `nil` to show every category. Only mods
    /// whose category was fetched during the last Nexus check are affected;
    /// mods without a known category disappear when a scope is chosen.
    @State private var selectedCategory: NexusCategory? = nil
```

Replace with:

```swift
    /// Category-filter scope: show everything, scope to one Nexus category,
    /// or scope to mods with no category assigned. `.category` only affects
    /// mods whose category was fetched during the last Nexus check or set
    /// manually; `.uncategorized` is the counterpart for the rest.
    @State private var selectedCategory: CategoryScope = .all
```

- [ ] **Step 3: Update `filteredMods` to switch on `CategoryScope`**

The current implementation (lines 28-39):

```swift
    var filteredMods: [ModItem] {
        vm.mods.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.uniqueId.localizedCaseInsensitiveContains(searchText) }
            .filter { mod in
                guard let cat = selectedCategory else { return true }
                // Groups match if any child matches; individual mods match if
                // their cached category id equals the selected one.
                if mod.isGroup, let children = mod.children {
                    return children.contains { vm.category(for: $0)?.id == cat.id }
                }
                return vm.category(for: mod)?.id == cat.id
            }
    }
```

Replace with:

```swift
    var filteredMods: [ModItem] {
        vm.mods.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.uniqueId.localizedCaseInsensitiveContains(searchText) }
            .filter { mod in
                switch selectedCategory {
                case .all:
                    return true
                case .category(let cat):
                    // Groups match if any child matches; individual mods match if
                    // their cached category id equals the selected one.
                    if mod.isGroup, let children = mod.children {
                        return children.contains { vm.category(for: $0)?.id == cat.id }
                    }
                    return vm.category(for: mod)?.id == cat.id
                case .uncategorized:
                    // Groups match only if every child lacks a category; a pack
                    // with at least one categorized child isn't "uncategorized".
                    if mod.isGroup, let children = mod.children {
                        return !children.isEmpty && children.allSatisfy { vm.category(for: $0) == nil }
                    }
                    return vm.category(for: mod) == nil
                }
            }
    }
```

- [ ] **Step 4: Add the `uncategorizedCount` computed property**

In `StarHubTH/Views/ModListView.swift`, find the `availableCategories` property (lines 100-121, ending with its closing brace `}` right before `scopeCounts`). Insert the new property directly after it, before `scopeCounts`:

```swift
    /// Count of top-level mods (standalone mods + whole packs) with no
    /// category assigned, matching the group semantics used by the
    /// `.uncategorized` filter case above (a pack only counts if *every*
    /// child lacks a category). Drives the "No Category (N)" menu entry and
    /// its visibility.
    private var uncategorizedCount: Int {
        vm.mods.filter { mod in
            if mod.isGroup, let children = mod.children {
                return !children.isEmpty && children.allSatisfy { vm.category(for: $0) == nil }
            }
            return vm.category(for: mod) == nil
        }.count
    }
```

- [ ] **Step 5: Update the disabled/hint condition around the picker**

The current block (lines 170-183):

```swift
                        categoryPicker
                            .disabled(availableCategories.isEmpty)
                            .help(availableCategories.isEmpty
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))
                    }
                    if availableCategories.isEmpty {
                        Text(vm.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
```

Replace with:

```swift
                        categoryPicker
                            .disabled(availableCategories.isEmpty && uncategorizedCount == 0)
                            .help(availableCategories.isEmpty && uncategorizedCount == 0
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))
                    }
                    if availableCategories.isEmpty && uncategorizedCount == 0 {
                        Text(vm.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
```

- [ ] **Step 6: Update `categoryPicker` — menu items and button label**

The current implementation (lines 361-420):

```swift
    private var categoryPicker: some View {
        Menu {
            Button {
                selectedCategory = nil
            } label: {
                Label(vm.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            Divider()
            ForEach(availableCategories, id: \.category.id) { entry in
                Button {
                    selectedCategory = entry.category
                } label: {
                    // SwiftUI Menus render Button labels as plain text — an
                    // HStack would only show its first child. Concatenating
                    // Text views (or building a single string) keeps both the
                    // icon and the category name visible in the row.
                    Text(categoryBadgeEmoji(entry.category) + " " + entry.category.localizedName(vm.L) + "   (\(entry.count))")
                }
            }
            if selectedCategory != nil {
                Divider()
                Button(role: .destructive) {
                    selectedCategory = nil
                } label: {
                    Label(vm.L(L10n.Mods.categoryFilterClear), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let cat = selectedCategory {
                    Circle()
                        .fill(cat.color)
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(vm.L))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                    Text(vm.L(L10n.Mods.categoryFilter))
                        .font(.system(size: 12, weight: .medium))
                }
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
```

Replace with:

```swift
    private var categoryPicker: some View {
        Menu {
            Button {
                selectedCategory = .all
            } label: {
                Label(vm.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            if uncategorizedCount > 0 {
                Button {
                    selectedCategory = .uncategorized
                } label: {
                    Label("\(vm.L(L10n.Mods.categoryFilterUncategorized))   (\(uncategorizedCount))", systemImage: "circle.dashed")
                }
            }
            Divider()
            ForEach(availableCategories, id: \.category.id) { entry in
                Button {
                    selectedCategory = .category(entry.category)
                } label: {
                    // SwiftUI Menus render Button labels as plain text — an
                    // HStack would only show its first child. Concatenating
                    // Text views (or building a single string) keeps both the
                    // icon and the category name visible in the row.
                    Text(categoryBadgeEmoji(entry.category) + " " + entry.category.localizedName(vm.L) + "   (\(entry.count))")
                }
            }
            if selectedCategory != .all {
                Divider()
                Button(role: .destructive) {
                    selectedCategory = .all
                } label: {
                    Label(vm.L(L10n.Mods.categoryFilterClear), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                switch selectedCategory {
                case .all:
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                    Text(vm.L(L10n.Mods.categoryFilter))
                        .font(.system(size: 12, weight: .medium))
                case .category(let cat):
                    Circle()
                        .fill(cat.color)
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(vm.L))
                        .font(.system(size: 12, weight: .medium))
                case .uncategorized:
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.Mods.categoryFilterUncategorized))
                        .font(.system(size: 12, weight: .medium))
                }
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
```

- [ ] **Step 7: Build to confirm it compiles**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` — no Swift compile errors (in particular, no leftover reference to `selectedCategory` as `NexusCategory?` anywhere in the file).

Run: `grep -n "selectedCategory" StarHubTH/Views/ModListView.swift`
Expected: every usage is one of `.all`, `.category(...)`, `.uncategorized`, or the `switch`/`if selectedCategory != .all` forms added above — no `nil` or `entry.category` (bare) assignments left over.

- [ ] **Step 8: Manual verification in the running app**

Run: `open StarHubTH.app`

1. Open the Mods tab. Click the category filter button.
2. If any mod lacks a category, confirm a "No Category (N)" entry appears between "All Categories" and the divider before the Nexus category list; `N` should equal the number of rows (standalone mods + whole packs) that appear when selected.
3. Select "No Category" — confirm the list shows only standalone mods with no category badge, and only packs where *no* child has a category badge (a pack with a mix of categorized/uncategorized children should NOT appear).
4. Confirm the filter button now shows a dashed-circle icon + "No Category" label, and the "Clear category filter" item appears in the menu.
5. Click "Clear category filter" — confirm it resets to "All Categories" and the full list returns.
6. If every installed mod currently has a category, confirm the "No Category" entry is absent from the menu and the picker isn't incorrectly disabled (it should still be enabled because real categories exist).

- [ ] **Step 9: Commit**

```bash
git add StarHubTH/Views/ModListView.swift
git commit -m "Add 'No Category' filter to the mod list category menu"
```
