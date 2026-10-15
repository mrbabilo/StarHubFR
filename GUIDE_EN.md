# User guide — StarHubFR

*[Version française](GUIDE.md).*

How to use it day to day, and what to do when something goes wrong. For the full list of what the app can do, see the [README](README_EN.md). Labels below are those of the app in English.

**Contents**

1. [First launch](#1-first-launch)
2. [Installing mods](#2-installing-mods)
3. [Enabling and pausing: the `X` / `.X` convention](#3-enabling-and-pausing-the-x--x-convention)
4. [Profiles and groups](#4-profiles-and-groups)
5. [Updates](#5-updates)
6. [When the game crashes or a mod won't load](#6-when-the-game-crashes-or-a-mod-wont-load)
7. [Conflicting keyboard shortcuts](#7-conflicting-keyboard-shortcuts)
8. [Measuring performance](#8-measuring-performance)
9. [Translating a mod into French](#9-translating-a-mod-into-french)
10. [Getting back what was replaced or deleted](#10-getting-back-what-was-replaced-or-deleted)
11. [Alongside other mod managers](#11-alongside-other-mod-managers)
12. [Uninstalling StarHubFR cleanly](#12-uninstalling-starhubfr-cleanly)

---

<!-- help: first-launch -->
## 1. First launch

1. Download the latest version from the [Releases](../../releases) page, unzip it and drag `StarHubFR.app` into **Applications**.
2. The app is not notarized: on first launch, macOS may block it. Open **System Settings › Privacy & Security**, then **Open Anyway**.
3. The app looks for Stardew Valley. If it can't find it, point it to **the game application itself**; the `Mods/` folder is found from there.
4. If SMAPI is not installed, the app offers to install it. Without SMAPI, the game loads no mods.

**The Nexus API key is optional.** Without it, the app already checks for updates (through smapi.io) and browses Discover. With it (**Settings › API Key**), it downloads and installs from Nexus, and you can endorse a mod in one click. The key stays in the macOS Keychain.

To move to a new version of the app, quit it completely (⌘Q) before replacing `StarHubFR.app`.

<!-- help: install -->
## 2. Installing mods

**From an archive.** Drop a `.zip`, `.7z` or `.rar` on the drop zone of **Mod Management**. The app recognises a single mod or a pack, reports missing dependencies and conflicts, then installs.

**From Nexus.** With a Premium account, the **Install** button downloads directly. With a free account, the Nexus page opens: click **Mod Manager Download** and the app picks up the archive.

Good to know:

- **A new mod arrives paused.** Enable it in the list when you're ready. Updating an enabled mod keeps it enabled.
- **Your settings are kept.** An archive never overwrites the `config.json` or `fr.json` of a mod that is already installed.
- **The old version is backed up** before it is replaced (see [section 10](#10-getting-back-what-was-replaced-or-deleted)).
- **A file meant for another mod** (a bag for *ItemBags*, for example) is placed inside its host mod, and the app shows you where.

<!-- help: pause -->
## 3. Enabling and pausing: the `X` / `.X` convention

Pausing a mod renames its folder with a **leading dot**: `Mods/ColorfulVolume` becomes `Mods/.ColorfulVolume`. SMAPI does not load dot folders. Nothing is moved or deleted.

- **One mod, a selection, or all of them.** Click a row's switch; select several rows (click, ⌘-click, ⇧-click, ⌘A) then press Space; or use **Enable All** on the filtered list.
- **Finder hides these folders** (⇧⌘. shows them). A mod that has "vanished" from the game but still takes up space is almost always a paused mod.
- **Don't delete them by hand**: the dot folders in `Mods/` are your paused mods, not hidden files to clean up.
- **The mods shipped with SMAPI** (ConsoleCommands, SaveBackup) stay enabled, and neither they nor the StarHubFR probe can be deleted from the app: it tells you if you try.
- **Before you pause a mod that writes into your saves**, the app measures what it left there. **Game Saves › Clean up…** removes the data of mods that are gone, after copying the save.

<!-- help: profiles -->
## 4. Profiles and groups

A **profile** describes a **state**: which mods are enabled. A **group** describes an **arrangement**: how the list is organised. The two work together.

**Mod Profiles.** Create an empty profile, or copy the mods that are currently enabled. Switching profiles enables and pauses mods in one go. Each profile can keep its own mod settings (**Per-profile configuration**): when you switch profiles, you get that profile's `config.json` files back.

**Groups.** In **Mod Management**, "Group by" your groups or by category. A group folds, enables or pauses in one gesture; "Put in group" places a row or a selection into a group.

**"Set aside" mark.** For a mod you want out of circulation without uninstalling it: it stays greyed out and gathered under its own filter.

<!-- help: updates -->
## 5. Updates

**Mod Updates** checks your whole collection without an account or a key, through smapi.io. Each mod concerned carries a "↑ version" badge in the list.

- **Before installing**, the preview tells you what the new version changes: config options added or removed, texts to translate, enabled mods that read its internal code.
- **"I already have it"**: for a mod whose author publishes without changing the version in its manifest. The row records the version actually installed and disappears.
- **Mods without a verdict** are listed with their reason (no identifier, hidden page…). A Nexus ID typed by hand repairs a broken key.
- **If smapi.io doesn't answer**, the app says so and offers to check Nexus directly.

<!-- help: troubleshooting -->
## 6. When the game crashes or a mod won't load

1. Launch the game through SMAPI, reproduce the problem, then open **Diagnostics & Performance › Health**. The app reads the SMAPI log and tells you what to do, in plain words: a dependency to install, a duplicated mod, a mod that doesn't support your game version.
2. **Log** shows the lines themselves, grouped by mod, the most troublesome first.
3. If nothing points to a culprit, the **Find the mod causing the problem** card pauses your mods by halves and asks you one question per relaunch. About ten tries are enough; everything goes back as it was in one click.
4. **System Alerts** gathers what needs your attention across your whole collection, in three tabs: **Alerts** (missing dependencies, duplicates, folders to repair), **Keyboard shortcuts** and **Mod conflicts** (two mods replacing the same content).

To ask for help, upload `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt` to [smapi.io/log](https://smapi.io/log) and share the link you get.

<!-- help: shortcuts -->
## 7. Conflicting keyboard shortcuts

**System Alerts › Keyboard shortcuts** lists every key used by your enabled mods, searchable by mod, setting or key. Two mods on the same key trigger together.

**"Propose a plan"** works out a solution:

- **Conflicts only**: only the mod that gives way changes key.
- **Arrange all by family**: letters for action mods, digits for everyday information, F keys for what you rarely use.

Uncheck a row to keep a key; correct the family of a mod that was guessed wrong, and the app remembers it. **Apply** first backs up the `config.json` files involved, then changes only the shortcut concerned; the summary says what moved and what remains. **Undo the plan** puts the files back, as long as no other backup has been made since.

Close the game before applying: a mod reads its configuration at launch. After a profile switch that creates conflicts, an alert on **Mod Profiles** leads straight to the plan.

<!-- help: performance -->
## 8. Measuring performance

**Diagnostics & Performance › Performance** answers "is this mod slowing my game down?".

1. **Install the StarHubFR probe**, a small SMAPI mod shipped with the app. It doesn't use the network and changes nothing else; it measures loading, smoothness and memory while you play.
2. **Play normally**: the tab compares two moments and tells you what changed (mods, versions, settings).
3. For a clear answer about one specific change, **Measure** starts a guided measurement: the probe drives the game before and after, and the app gives you the comparison. You keep the change or go back to how things were, even after an interruption.

A difference is shown as a gain or a loss only beyond the noise measured between your own sessions; below that, it stays grey. To stop the probe, pause it like any other mod.

<!-- help: translate -->
## 9. Translating a mod into French

Open a mod's page, **Translation** tab.

- **English on the left, French on the right**, key by key. A mod without a `fr.json` gets one on the first save.
- **The game's markers** (player names, line breaks, colours…) are shown in colour and inserted in one click. A save that loses one is refused: the game would display broken text.
- **Draft by a local AI**: with [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai) on your Mac, the app suggests a translation marked "To review". Nothing leaves your machine. The glossary of the game's official names is imposed on the model.
- **French translations** lists the translations already published on Nexus for your mods: often, installing one is all it takes.

A translation written in the app lives in the mod's folder. Updating the mod doesn't overwrite it; the update preview tells you which keys need revisiting.

<!-- help: recover -->
## 10. Getting back what was replaced or deleted

- **An update replaced a mod and you want the old version** — **Mod Backups** › Restore (the mod comes back paused).
- **A `config.json` was rewritten** (config editor, shortcut plan) — **Mod Backups** › Configuration Backups.
- **You moved mods to the trash from the app** — **Maintenance** › Restore, or **Restore all** for a batch.
- **An unreadable or stray folder disappeared from `Mods/`** — **Quarantine**: scans set aside what was in the way, nothing is deleted.
- **A save** — **Game Saves**: a copy is made before each change.

All of this lives in `~/Library/Application Support/StarHubFR/`.

<!-- help: other-managers -->
## 11. Alongside other mod managers

StarHubFR, Vortex, Stardrop and the Nexus Mods App read **the same** `Mods/` folder of the game.

- **Only one tool should pause mods at a time.** StarHubFR's pause is a dot folder; Vortex and Stardrop ignore it or do things differently. If you switch tools, put the mods in the state you want with **only one** of them.
- **A mod installed by StarHubFR is an ordinary folder.** Other tools see it as if it had been placed there by hand.
- **The game always starts through SMAPI**: a mod runs the same whichever tool installed it.

<!-- help: uninstall -->
## 12. Uninstalling StarHubFR cleanly

Paused mods live in dot folders inside `Mods/`. If you remove the app without bringing them back, the game won't load them any more and they will seem lost.

1. In **Mod Management**, choose the **All** scope, then **Enable All**; or delete yourself the paused mods you no longer want.
2. Check that the **Disabled** scope is empty.
3. Pause or delete the `Mods/StarHubFR Probe` folder if you installed the probe. Pausing it from the app also removes it from SMAPI's early-load list.
4. Quit StarHubFR and move `StarHubFR.app` to the trash. The `Mods/` folder is then an ordinary SMAPI folder.

To also erase the app's data (profiles, mod backups, history, translations in progress):

- delete `~/Library/Application Support/StarHubFR/`;
- delete `~/Library/Preferences/com.mrbabilo.StarHubFR.plist`;
- in **Keychain Access**, delete the `com.mrbabilo.StarHubFR` items (Nexus key, DeepL key).

The `Backups/` folder holds the old versions of your mods: have a look before deleting it.
