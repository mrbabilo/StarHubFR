> [!IMPORTANT]
> This fork adds French language support and a French-touch UX/UI. See the [French README](README.md).
>
> Original project: [StarHubTH](https://github.com/AppleBoiy/StarHubTH) by **AppleBoiy** — which offers a **Thai** version.

<p align="center">
  <img src="assets/nexus_banner_final.png" alt="StarHubFR Banner">
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0288D1?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://www.python.org"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python"></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="https://github.com/mrbabilo/StarHubFR/releases/latest"><img src="https://img.shields.io/github/v/release/mrbabilo/StarHubFR?label=Version&color=2ea44f" alt="Version"></a>
  <a href="https://www.stardewvalley.net"><img src="https://img.shields.io/badge/Stardew%20Valley-1.6-5BA04E" alt="Stardew Valley 1.6"></a>
  <a href="https://smapi.io"><img src="https://img.shields.io/badge/SMAPI-4.x-6A5ACD" alt="SMAPI 4.x"></a>
  <a href="#"><img src="https://img.shields.io/badge/Languages-FR%20%7C%20EN-0055A4" alt="Languages FR and EN"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License"></a>
  <a href="https://github.com/mrbabilo/StarHubFR/actions/workflows/ci.yml"><img src="https://github.com/mrbabilo/StarHubFR/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

**StarHubFR is a native macOS mod manager for Stardew Valley, in French and English.**
Install, organise and troubleshoot your mods without opening Finder or a terminal, even with several hundred mods.

The **[user guide](GUIDE.md)** (in French) covers living alongside other mod managers, the `X` / `.X` convention for paused mods, and removing the app cleanly.

## Why StarHubFR

*   🇫🇷 **French throughout** — interface, errors and diagnostics, with an instant switch to English.
*   🩺 **It tells you what's wrong** — it reads the SMAPI log for you and says what to do, in plain words.
*   ✍️ **Translate mods inside the app** — a key-by-key editor writes the `fr.json` without breaking the game's markers.
*   🍎 **Truly native** — Swift and SwiftUI, no web layer, usable with VoiceOver.
*   🧩 **Built for large collections** — designed and tested on installs of several hundred mods (SVE and friends).
*   🧭 **Find new mods without leaving the app** — trending, recently updated and a French selection, checked against what you already have.

<p align="center">
  <img src="assets/banners/features_banner.png" alt="Key Features" width="300">
</p>

### 🩺 SMAPI diagnostics

When the game crashes or a mod refuses to load, StarHubFR turns the SMAPI log into a readable diagnosis.

*   **Advice, not jargon** — "install this dependency", "this mod is installed twice", "this mod doesn't support your game version".
*   **Health at a glance** — SMAPI and game versions, mods loaded, skipped or failed with their reason, missing dependencies.
*   **Mods to watch** — those that change the game's code or your saves, those that log the most errors, with what it means for you.
*   **False alarms set aside** — GOG Galaxy, an optional integration missing, an absent companion mod: the message is quoted, a button jumps to its lines, and the mod is no longer blamed for nothing.
*   **A log you can read** — repetitive lines folded, grouping by mod (worst first), a badge when the log predates your session.
*   **Errors tracked version by version** — a mod's page tells you whether its new version behaves worse than the previous one.
*   **Every shortcut and its conflicts** — each key of your active mods, searchable by mod, setting or key; when capturing a key, the config editor says if another mod already uses it.
*   **Conflicts predicted before you play** — two mods loading the same asset exclusively are flagged, and enabling them (one at a time, in bulk or through a profile) warns you and names the asset.
*   **Find the faulty mod** — when nothing points to a culprit, the app pauses your mods by halves and asks one question per step. About ten tries are enough; everything comes back in one click.

### ⏱️ Performance

The StarHubFR probe, a small SMAPI mod installed at your request, measures the game while you play. The *Performance* tab compares two moments and tells you what changed.

*   **Load times** — game launch and save loading, compared with the previous state of your collection, with the heaviest mods.
*   **Automatic benchmark** — the app runs several launches on its own, alternating both states, then puts your collection back as it was.
*   **Smoothness and memory** — frame time, stutters, process memory and per-mod textures, minute by minute, with what separates two sessions (mods, versions, settings, scene).
*   **No verdict by chance** — a difference only counts beyond the noise measured between your own sessions; otherwise it stays grey.
*   **Guided, reversible diagnostics** — for Stardew Loading Optimizer and Stardropium, the app installs them if needed, turns measurements on for one play session, then restores settings and mods, even after an interruption.
*   **"Environment" card** — the settings Stardew Loading Optimizer actually applied, configurable mods, and the weight and conflicts of each Content Patcher pack.

### 📦 Installing and organising

*   **Drag and drop an archive** (`.zip`, `.7z`, `.rar`) — structure detected (single mod or pack), format recognised from its bytes, safety limits (500 MB archive, 2 GB unpacked), conflicts and missing dependencies announced.
*   **Content for another mod lands in the right place** — a file meant for a framework (an *ItemBags* bag, say) goes into its host mod, with the path shown and any existing file backed up first.
*   **Enable without moving files** — one mod, a selection (click, ⌘, ⇧, ⌘A, then Space) or all at once. Mods shipped with SMAPI stay enabled.
*   **Profiles** — several sets of mods, one click to switch.
*   **A list that sorts** — categories inferred from the manifest, filters (configurable, "set aside", uncategorised…), sorting by name, author, endorsements or oldest update; All, Enabled, Paused, **Problems** and **Updates** scopes.
*   **Nexus endorsements** — each mod's thumb shows its endorsement count and endorses in one click.
*   **"Set aside" mark** — take a mod out of circulation without uninstalling it: greyed out, gathered by a filter, importable into a profile.

### 🔄 Updates and downloads

*   **Checks with no account**, through [smapi.io](https://smapi.io/), from the manifests. A "Stop" button interrupts the check at any time.
*   **If smapi.io goes down** — the app says so and offers to check directly on Nexus: a keyless sort only rechecks the pages that changed, a few dozen requests instead of several thousand.
*   **Mods without a verdict, explained** — the ones neither smapi.io nor Nexus could judge, each with its reason (no Nexus ID, page hidden or removed…). A Nexus ID you entered by hand replaces a broken manifest key.
*   **Each mod says it has an update** — an "↑ version" badge on its row and a banner on its page. Matching uses the manifest ID, never the Nexus ID.
*   **"I already have it"** — for authors who publish without bumping their manifest version: the row records the version you actually have, then goes away.
*   **Download in the app** — directly with a Premium account, or through the `nxm://` link with a free one. The API key stays in the macOS Keychain.
*   **What an update changes** — config options added or removed, new text to translate, author translations dropped; renamed keys are carried over, never overwritten. The preview also warns when active mods read the internal code of the mod being replaced.

### 🧭 Discover

*   **Three Nexus showcases** — trending, recently updated and a French selection, cached for 24 h.
*   **What you already have shows** — an "Installed" badge and a filter to hide them, with the number hidden.
*   **Categories and search** — 26 categories filtered server-side, name search with the real total.
*   **Quick sheet** — description, version, endorsements, then **Install** (Premium) or **Open on Nexus**.
*   **Never silent** — no key, quota reached or network down, each state says what's happening and offers the action that fixes it.

### 📖 Mod page

*   **Six tabs** — Overview, Health, Dependencies, Translation, History, Manage.
*   **Compatibility first** — smapi.io's verdict and what the author says about it, in one card.
*   **Health** — a verdict and eight checks (SMAPI blocklist, loading, smapi.io, log, incompatibilities, shortcuts, duplicates, Nexus page), with "not checked" when data is missing.
*   **Dependencies** — the full tree with status and actions, plus the mods whose internal code this one reads without declaring them.
*   **Description and changelog** rendered as native text (bold, lists, links, images, spoilers).
*   **Nexus ID and category** editable in place.

### 🌐 French translation

Each mod page has a **Translation** tab that shows the real state of its French and doubles as an editor.

*   **English on the left, French on the right**, key by key; a mod without a `fr.json` gets one on the first save.
*   **A local AI drafts the French** — a model running on your Mac (Ollama, LM Studio), key by key or in batches, marked "To review". Nothing leaves the machine.
*   **The glossary comes from the game** — over a thousand item, character and place names, read from your install and imposed on the model.
*   **The game's markers are protected** — shown in colour, inserted in one click; a save that drops one is refused.
*   **The real completion rate** — 100 % only when every key is done; empty, missing and outdated keys listed separately.
*   **"French Translations" page** — translations published on Nexus for your mods, and updates to the ones you have.
*   **Teamwork** — export a ZIP batch for a translator, merge it back key by key.
*   **Focus mode** — banners and sidebar hidden (Esc to leave).

### ⚙️ Configuration and backups

*   **Config editor** — a searchable tree of typed settings, or raw JSON validated live; dropdowns show the mod's own labels, translated.
*   **Mod backups** — before every overwrite, plus your `config.json` and `fr.json`, and the files an update took away.
*   **Saves** — details, copy, deletion, and editing money or character stats.
*   **What your mods leave in your saves** — counted before pausing a mod; "Clean…" removes data from mods that are gone, after a backup.

### 🎮 Everyday use

*   **A home page that gets to the point** — the counters that matter and **Launch Game**, vanilla or through SMAPI.
*   **Live logs** — SMAPI and StarHubFR output, filterable by source and level.
*   **The mods the app relies on** — listed in Settings, with their role, state and install link.
*   **Accessible and readable** — VoiceOver, and buttons that turn into icons when the window is narrow.

<p align="center">
  <img src="assets/banners/screenshots_banner.png" alt="Screenshots" width="300">
</p>

|   |   |
| :---: | :---: |
| <img src="screenshots/1.jpg" width="400"> | <img src="screenshots/2.jpg" width="400"> |
| <img src="screenshots/3.jpg" width="400"> | <img src="screenshots/4.jpg" width="400"> |
| <img src="screenshots/5.jpg" width="400"> | <img src="screenshots/6.jpg" width="400"> |
| <img src="screenshots/7.jpg" width="400"> | <img src="screenshots/8.jpg" width="400"> |
| <img src="screenshots/9.jpg" width="400"> | <img src="screenshots/10.jpg" width="400"> |
| <img src="screenshots/11.jpg" width="400"> | <img src="screenshots/12.jpg" width="400"> |
| <img src="screenshots/13.jpg" width="400"> | <img src="screenshots/14.jpg" width="400"> |
| <img src="screenshots/15.jpg" width="400"> | <img src="screenshots/16.jpg" width="400"> |
| <img src="screenshots/17.jpg" width="400"> | <img src="screenshots/18.jpg" width="400"> |
| <img src="screenshots/19.jpg" width="400"> | <img src="screenshots/20.jpg" width="400"> |
| <img src="screenshots/21.jpg" width="400"> | <img src="screenshots/22.jpg" width="400"> |
| <img src="screenshots/23.jpg" width="400"> | <img src="screenshots/24.jpg" width="400"> |
| <img src="screenshots/25.jpg" width="400"> | <img src="screenshots/26.jpg" width="400"> |
| <img src="screenshots/27.jpg" width="400"> | <img src="screenshots/28.jpg" width="400"> |
| <img src="screenshots/29.jpg" width="400"> | <img src="screenshots/30.jpg" width="400"> |
| <img src="screenshots/31.jpg" width="400"> |  |

<p align="center">
  <img src="assets/banners/install_banner.png" alt="Installation" width="300">
</p>

### Requirements

*   macOS 14 (Sonoma) or later.
*   Stardew Valley installed on macOS (Steam or GOG).
*   [SMAPI](https://smapi.io/) to play with mods; the app can install it.

### Install

1. Download the latest version from the [Releases](../../releases) page.
2. Unzip it and drag `StarHubFR.app` into Applications.
3. On first launch macOS may block the app, which isn't notarised: open **System Settings › Privacy & Security**, then **Open Anyway**.
4. The app looks for the game folder; if it isn't found, point to it (for example `/Applications/Stardew Valley.app/Contents/MacOS`).

To move to a new version, quit the app completely (⌘Q) before replacing the bundle.

<p align="center">
  <img src="assets/banners/developers_banner.png" alt="For Developers" width="300">
</p>

The app is written in **Swift** and **SwiftUI**. You need macOS 14 and Xcode 16 (the version the CI uses).

```bash
python3 build_app.py   # compiles, checks conventions and produces StarHubFR.app
open StarHubFR.app
./run_tests.sh         # core tests (Swift Testing)
python3 release.py     # release archive in bundles/
```

There is no Xcode project: `build_app.py` compiles every source, and `Package.swift` only describes the tested core.

<p align="center">
  <img src="assets/banners/credits_banner.png" alt="Credits & License" width="300">
</p>

StarHubFR is released under the [MIT License](LICENSE): fork it, change it, improve it. It derives from [StarHubTH](https://github.com/AppleBoiy/StarHubTH) by **AppleBoiy**, who offers a **Thai** version.

### Acknowledgements

StarHubFR builds on the work of many projects. The full list — APIs queried, files read, code reused, and the state of each — is kept up to date in [`docs/SOURCES.md`](docs/SOURCES.md).

**SMAPI and diagnostics**

*   [**SMAPI**](https://github.com/pathoschild/SMAPI), [**Content Patcher**](https://github.com/Pathoschild/StardewMods/tree/develop/ContentPatcher), [**StardewXnbHack**](https://github.com/Pathoschild/StardewXnbHack) and the [**compatibility list**](https://github.com/Pathoschild/SmapiCompatibilityList) by **Pathoschild** (MIT) — log and manifest formats checked against the sources, load-time measuring points, pack config schema, reading the game's files, offline verdicts. The built-in installer downloads SMAPI's releases.
*   [**smapi.io**](https://smapi.io/) — the update API that answers for Nexus, CurseForge, ModDrop and GitHub with no key or account, its [log parser](https://smapi.io/log/) and its [blocklist](https://smapi.io/SMAPI.blacklist.json).
*   [**SMAPILogDoctor.py**](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py) by **ZeroXPatch** — the idea of a log diagnosis written for players.

**Nexus Mods**

*   [**Nexus Mods**](https://www.nexusmods.com/stardewvalley) — API v1 for mod pages and downloads, GraphQL API v2 (undocumented, mapped by introspection) for discovery, search and keyless sorting. Thank you for keeping it open.
*   [**Nexus Mods App**](https://nexus-mods.github.io/NexusMods.App/developers/), [**node-nexus-api**](https://github.com/Nexus-Mods/node-nexus-api) and [**Vortex**](https://github.com/Nexus-Mods/Vortex) — the `nxm://` protocol, response shapes, mod manager conventions.

**Translation**

*   [**lzxd**](https://codeberg.org/Lonami/lzxd) by **Lonami** (MIT / Apache-2.0) — ported to Swift to read the game's official translations; [**libmspack**](https://github.com/kyz/libmspack) by **Stuart Caie** (LGPL-2.1) as a reference, with no code reused.
*   [**stardew-i18n-translator**](https://github.com/Nana1873/stardew-i18n-translator) by **Nana1873** (GPL-3.0) — the design model for our editor, down to marker protection. No code reused.
*   [**Transtar**](https://github.com/wanniwa/transtar) by **wanniwa**, [**Internationalization**](https://www.nexusmods.com/stardewvalley/mods/21317) by **bcmpinc** and [**ModTRANS**](https://www.nexusmods.com/stardewvalley/mods/53388) — other approaches to translating mods, studied for ours.
*   [**Ollama**](https://ollama.com) (MIT) and [**LM Studio**](https://lmstudio.ai) — the local AI servers the app detects, without bundling them; [**Qwen2.5**](https://ollama.com/library/qwen2.5) by the **Qwen team** (Apache-2.0), the recommended model; [**DeepL**](https://www.deepl.com/pro-api), an optional fallback with your own key.

**Configuration and saves**

*   [**Generic Mod Config Menu**](https://www.nexusmods.com/stardewvalley/mods/5098) by **spacechase0** and [**Modern Config Menu**](https://www.nexusmods.com/stardewvalley/mods/49437) by **palmhacker13** — what mods declare about their settings, and the probe's in-game menu.
*   [**stardew-save-editor**](https://github.com/colecrouter/stardew-save-editor) by **colecrouter** — the reference for reading and editing saves.
*   **Newtonsoft.Json** (MIT), as shipped with the game and run under Mono — the oracle for what SMAPI really accepts as JSON.

**Performance**

*   [**Profiler**](https://github.com/SinZ163/StardewMods/tree/main/Profiler) by **SinZ** (MIT) — frame timers and garbage-collector pause reading reused by the probe; its viewer [Stardew Utilities](https://stardew.361zn.is) guided how we read load times.
*   [**FastLoads**](https://www.nexusmods.com/stardewvalley/mods/19454) by **spajus**, [**Stardew Loading Optimizer**](https://www.nexusmods.com/stardewvalley/mods/50153) by **neoiw**, [**Stardropium**](https://www.nexusmods.com/stardewvalley/mods/52803) by **Arshia1381**, [**UltraSmooth**](https://www.nexusmods.com/stardewvalley/mods/50971) by **palmhacker13** and [**SDV-Radiance**](https://www.nexusmods.com/stardewvalley/mods/49397) by **PHUICMT** — decompiled and studied to learn what they change in the game, and so what our measurements must see.

**Tools**

*   [**ILSpy**](https://github.com/icsharpcode/ILSpy) (MIT) — decompiling mods to audit their changes.
*   [**dnfile**](https://github.com/malwarefrank/dnfile) (MIT) — the Python oracle for our .NET metadata reader.
*   [**7-Zip**](https://www.7-zip.org), [**The Unarchiver**](https://theunarchiver.com) (`unar`) and **unrar** — used, when installed, to open `.7z` and `.rar` archives.

**Inspiration**

*   [**Stardrop**](https://github.com/Floogen/Stardrop) by **Floogen** and its macOS port [**Stardrop – Native MacOS**](https://www.nexusmods.com/stardewvalley/mods/53356) by **kautsaralbaa** — live update checks, notes, per-profile configs.
*   [**JuniGrid**](https://www.nexusmods.com/stardewvalley/mods/53227) by **MLD210** and [**StarModsManager**](https://github.com/Arborsm/StarModsManager) by **Arborsm** — other managers, read for their ideas as much as their pitfalls.
*   [**Keybind Radar**](https://www.nexusmods.com/stardewvalley/mods/52710) by **Wooa** and [**SaveSaver**](https://www.nexusmods.com/stardewvalley/mods/52709) by **Sky** — they shaped the conflict signal at key capture and guided save cleanup.
