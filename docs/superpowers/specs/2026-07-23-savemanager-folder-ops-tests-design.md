# Automated Tests for SaveManager (Folder Operations) — Design

## Goal

Extend the test pattern established by the `ModConfigBackupManager` pilot
and its `ModInstallBackupManager` extension to `SaveManager` — specifically
its **folder-operation** surface (backup/restore/delete/duplicate/branch a
save), the first of two planned sub-projects for this manager. The second
sub-project (a separate future spec) covers `SaveManager`'s XML
content-editing surface (`fetchSaves`/`parseSaveFile`, `updateSave`,
`fetchInventory`/`updateInventory`) — a different risk profile (wrong tag
replaced vs. lost/corrupted folder) that doesn't belong in the same review.

## Why split SaveManager into two sub-projects

`SaveManager.swift` (802 lines) is substantially larger than the two
managers already covered (14 + 15 tests) and its ~15 public methods split
cleanly into two families with different failure modes:

- **Folder operations** (this spec): `backupSave`, `deleteSave`,
  `duplicateSave`, `branchFromBackup`, `listBackups`, `restoreBackup`,
  `deleteBackup`, and the shared private helper `cloneSaveFolder`. These
  copy/move/trash whole save folders — the same class of risk as the two
  managers already covered.
- **XML content editing** (future spec): `fetchSaves`/`parseSaveFile`
  (regex-based tag extraction), `updateSave` (regex-based tag replacement,
  including the divorce/friendship-cleanup logic), `fetchInventory`/
  `updateInventory` (XML document manipulation via `XMLDocument`). Needs
  realistic save-file XML fixtures and a different testing approach
  (content-correctness assertions rather than file-existence/backup-count
  assertions).

## No dependency-injection changes needed (unlike the prior two managers)

Every method in this spec's scope operates on `URL`s supplied via its
parameters (`SaveGameInfo.fileURL`, `SaveBackup.folderPath`) — **none of
them read `SaveManager`'s `self.savesDir`** (only `fetchSaves()`, out of
scope here, does). This means tests can construct their own
`SaveGameInfo`/`SaveBackup` values pointing at a temp directory and call
`SaveManager.shared`'s real methods directly — no injectable-directory
initializer is needed for this sub-project, unlike the pilot and its
extension.

## A bug found during exploration, approved for a fix + regression test

`backupSave`'s destination folder name
(`folderPath.appendingPathExtension("backup_\(timestamp)")`, second-
granularity only, no uniqueness suffix) can collide if two backups are
created within the same wall-clock second — the second `copyItem` would
fail (destination already exists) and `backupSave` would silently return
`false`. Since `updateSave` (out of scope here, but calls `backupSave`
first) depends on this succeeding, a same-second collision would silently
block a save edit too. The user approved fixing this as part of this work
(same bug class already fixed this session in the other two managers).

The fix must also touch `listBackups`, which parses the backup folder
name to recover its timestamp via a **strict** `"yyyyMMdd_HHmmss"`
`DateFormatter` — appending a uniqueness suffix after the timestamp would
make that parse fail (silently falling back to `Date()`, i.e. every
backup would display as if created "now"). Fix: `listBackups` reads only
the first 15 characters of the string after the prefix (the fixed-width
timestamp), ignoring anything appended after it.

The identical bug also exists in `restoreBackup`'s own internal
pre-restore backup path (`preRestoreBackupPath`, same naming scheme, same
missing suffix) — fixed identically for consistency, since a
`restoreBackup` call racing a `backupSave`/another `restoreBackup` within
the same second has the same collision risk.

## Global Constraints

- No change to `build_app.py`'s build output or behavior.
- No change to `SaveManager`'s production behavior beyond the approved
  bug fix (naming uniqueness + the parsing fix it requires).
- Tests must never touch the real `~/.config/StardewValley/Saves`
  directory.
- Test framework: Swift Testing.

**Known, accepted limitation:** `deleteSave`/`deleteBackup` call
`FileManager.trashItem(at:resultingItemURL: nil)` — production code
already discards the trashed item's actual destination, so a test has no
way to locate and remove it afterward without changing that method's
signature (out of scope: the only approved production change is the
naming-uniqueness fix). Tests for these two methods will therefore leave
their tiny fixture folder in the real macOS Trash after each run — small,
inert, user-recoverable-or-emptyable debris, not the real Saves
directory or any user data. This is disclosed here rather than promising
a cleanup mechanism the current API can't support.

---

## Architecture

Same `Package.swift`, extended further:

```text
StarHubTH/
├── SaveManager.swift          (existing — visibility changes + the
│                                 uniqueness-suffix bug fix)
├── Models/
│   └── InventoryItem.swift    (existing — visibility only; referenced by
│                                 SaveManager's fetchInventory/updateInventory
│                                 signatures even though this spec doesn't
│                                 test those methods, so the type must still
│                                 resolve for the file to compile)
└── ... (everything else, untouched)

Tests/
├── ModConfigBackupManagerTests/   (existing, untouched)
├── ModInstallBackupManagerTests/  (existing, untouched)
└── SaveManagerTests/              (NEW)
    └── SaveManagerTests.swift
```

`Package.swift`'s `StarHubTHCore` target gains
`"SaveManager.swift"` and `"Models/InventoryItem.swift"` in its
`sources:` list (note the `Models/` subdirectory prefix — `build_app.py`
walks recursively so this wasn't visible as a distinct concern before,
but SPM's `sources:` paths are relative to the target's `path:` and must
include the subdirectory). A new `.testTarget` block for
`SaveManagerTests` is added alongside the existing two.

### Visibility changes

- `SaveManager`: the class, `static let shared`, and every method this
  spec tests (`backupSave`, `deleteSave`, `duplicateSave`,
  `branchFromBackup`, `listBackups`, `restoreBackup`, `deleteBackup`) →
  `public`. `init()` itself → `public` (no parameter changes — no DI
  needed, as established above). Everything else (`cloneSaveFolder`,
  `modifyInternalSaveNames`, the regex/tag helpers, `regexCache`) stays
  `private`/internal, unchanged.
- `SaveGameInfo`: `public` struct + explicit `public init(...)` (18
  stored properties — Swift's implicit memberwise init is only ever
  internal regardless of the struct's own access level, same lesson as
  `ModItem` in the pilot). Its computed properties (`farmTypeName`,
  `farmIcon`, `seasonName`) do NOT need to be public — this spec's tests
  don't touch them (they belong to the XML-content sub-project, since
  `seasonName` reads `L10n.Saves.*`, which would otherwise pull `L10n.swift`
  into this target for no benefit here).
- `SaveBackup`: `public` struct + explicit `public init(folderPath:timestamp:saveFolder:)`.
- `InventoryItem` (`Models/InventoryItem.swift`): stays fully internal —
  it's referenced only in `fetchInventory`/`updateInventory`'s
  signatures, which stay `private`... actually they're already `internal`
  (not `private`) in the source today. Since this spec's tests never call
  those two methods, `InventoryItem` doesn't need `public` — only its
  presence in the compiled module matters (same reasoning as `ModManifest`
  in the previous extension).

### The bug fix

`backupSave`, current:
```swift
let timestamp = formatter.string(from: Date())
let folderPath = info.fileURL.deletingLastPathComponent()
let backupPath = folderPath.appendingPathExtension("backup_\(timestamp)")
```
becomes:
```swift
let timestamp = formatter.string(from: Date())
let folderPath = info.fileURL.deletingLastPathComponent()
// A UUID suffix guarantees each backup gets its own folder even when
// several are created within the same second — without it, the second
// copyItem below fails (destination exists) and backupSave silently
// returns false.
let backupPath = folderPath.appendingPathExtension("backup_\(timestamp)_\(UUID().uuidString)")
```

`restoreBackup`'s `preRestoreBackupPath`, current:
```swift
let preRestoreBackupPath = saveFolder
    .deletingLastPathComponent()
    .appendingPathComponent("\(saveFolder.lastPathComponent).backup_\(timestamp)")
```
becomes:
```swift
let preRestoreBackupPath = saveFolder
    .deletingLastPathComponent()
    .appendingPathComponent("\(saveFolder.lastPathComponent).backup_\(timestamp)_\(UUID().uuidString)")
```

`listBackups`, current:
```swift
let tsString = String(name.dropFirst(prefix.count))
let formatter = DateFormatter()
formatter.dateFormat = "yyyyMMdd_HHmmss"
let date = formatter.date(from: tsString) ?? Date()
```
becomes:
```swift
// Only the fixed-width "yyyyMMdd_HHmmss" (15 characters) is the actual
// timestamp — anything appended after it (the uniqueness suffix) must be
// ignored rather than fed into the strict formatter, which would
// otherwise fail to parse and silently fall back to `Date()`.
let tsString = String(name.dropFirst(prefix.count).prefix(15))
let formatter = DateFormatter()
formatter.dateFormat = "yyyyMMdd_HHmmss"
let date = formatter.date(from: tsString) ?? Date()
```

## Test helpers

- `makeTestSave(folderName:fileURL:playerName:farmName:...) -> SaveGameInfo`
  — sensible defaults for all 18 fields except `folderName`/`fileURL`
  (always required, since every test needs to control where the fake
  save file lives).
- `writeTestSaveFile(at url: URL, content: String)` — writes a minimal
  save-file fixture. This spec's tests don't need realistic Stardew XML
  content (they never parse it) — a short placeholder string is enough
  to prove copy/move fidelity.
- `TestEnvironment` — a temp root containing `Saves/<SaveName>/<SaveName>`
  (mirroring the real on-disk shape: a save's XML file shares its
  folder's name), with `cleanup()`. Note: `cleanup()` cannot remove
  anything `deleteSave`/`deleteBackup` already trashed (moved out of the
  temp root into the real Trash) — see the accepted limitation above; it
  only removes what's still under `root` at the end of a test.

## Test list

1. `backupSave` — creates a sibling `.backup_<timestamp>_<uuid>` folder
   with matching content.
2. `backupSave` — two backups created back-to-back get distinct folder
   names (regression test for the fix).
3. `listBackups` — correctly parses the new (fixed) naming format and
   returns backups sorted newest-first.
4. `restoreBackup` — successful restore: current state is backed up
   first, then the target backup's content replaces the live save.
5. `restoreBackup` — **rollback on copy-into-place failure**: lock the
   backup's source folder read-only (`chmod 0o000`, same technique
   verified working in the previous plan) so the final `copyItem` fails
   after the live folder has already been moved aside; assert the live
   folder is restored to its pre-restore content rather than left
   missing.
6. `deleteSave` — the save folder is gone from its original location
   afterward (trashed, not just deleted-in-place — verified by asserting
   absence at the original path, since the actual Trash destination
   isn't recoverable from the current API; see the accepted limitation
   above).
7. `deleteBackup` — same verification pattern for a backup folder.
8. `duplicateSave` — clones the save folder with a `_copy` suffix,
   renames the internal save file, and patches the name/farmName XML
   fields.
9. `duplicateSave` — calling it twice on the same save produces
   `_copy` then `_copy_2` (collision-avoidance in `cloneSaveFolder`).
10. `branchFromBackup` — clones from a backup folder with a `_branch`
    suffix, same internal patching as `duplicateSave`.

## Out of scope for this spec

- `fetchSaves`/`parseSaveFile`, `updateSave`, `fetchInventory`/
  `updateInventory` (future, separate spec — SaveManager's XML-editing
  surface).
- `ModZipInstaller` tests (future, separate spec — the last of the 3
  managers originally identified).
- Fixing the Minor items the pilot's and this extension's final reviews
  deferred as fast-follows (unrelated to `SaveManager`).
