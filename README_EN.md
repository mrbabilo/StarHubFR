> [!IMPORTANT]
> This fork adds French language support and a French-touch UX/UI. See the [French README](README.md).
>
> Original project: [StarHubTH](https://github.com/AppleBoiy/StarHubTH) by **AppleBoiy** — which offers a **Thai** version.

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0288D1?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://www.python.org"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python"></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="Key Features" width="300">
</p>

*   **Easy Game Launch**: Launch Stardew Valley in either Vanilla mode or through SMAPI for modded play.
*   **Mod Manager**: Enable or disable mods effortlessly through a beautiful app interface — no manual file moving required. Enable or disable **every mod at once** (progress bar, lossless moves) and **delete** a mod or pack from disk after confirmation.
*   **Drag & Drop Mod Installer**: Drag a `.zip`, `.7z` or `.rar` file directly into the app to install one or more mods. Automatic structure detection (single-mod, multi-mod pack), integrity validation (500 MB archive cap, 2 GB zip-bomb guard across all three formats, format detected from the file signature rather than its extension), conflict preview and missing dependency suggestions.
*   **Content installs inside its host mod**: Some Nexus downloads are content for a framework, not standalone mods — an *ItemBags* bag, say — and carry no `manifest.json`. The app recognises them and offers to put the file where it belongs, showing the exact path first, backing up any existing file; a paused host mod is handled, and a backup that fails cancels the install rather than overwriting.
*   **Mod Profiles**: Group mods into multiple profiles and switch between them instantly with a single click.
*   **Mod Updates & Downloads**: Check for mod updates via [smapi.io](https://smapi.io/) — no API key and no Nexus account needed: the check reads what each mod's manifest declares, and a mod it couldn't reach stays flagged instead of passing for up to date. An **"I already have it"** button covers authors who ship a new version without bumping their manifest's version: the row records the version you actually have, then drops. Then **download right in the app** — a *Premium update* button (Premium account required; the API key, stored in the macOS Keychain, only serves downloads) or *Nexus update* via the free `nxm://` link. After installing, the `manifest.json` is auto-reconciled so the mod stops showing a phantom "update available".
*   **Rich Mod Detail Pane**: A dedicated pane shows the mod's **full description** (BBCode/HTML rendered as native text — bold, lists, links, native-size images, collapsible spoilers), its complete **changelog**, and a **transitive dependency tree** (enabled/disabled/missing status, Enable/Nexus/Search actions, click-through between mods). Category and Nexus-id editing live in the pane.
*   **French Translation Tab**: A Translation tab on each mod's page shows the real state of its French — and it is an editor, not just a report. Click any line to open it side by side — English on the left, read-only; your French on the right — and step to the next key, or back to the previous one, without returning to the list. A mod with no French file yet gets one on the first save, and the tab opens on mods with no French at all, not only where work has begun. Every key appears with its English and its status (translated, to translate, empty, same as English, orphan), each filter carrying its count. Marks the game reads but must not be translated (Content Patcher tokens, dialogue separators, portrait commands) show in monospace and colour in both columns — and in the editor they insert with a click rather than a retype; a save that drops one is refused, naming what is missing, with a way through when the omission is deliberate, since a gender-neutral French sentence has no use for a gender switch. Sections an author wrote become collapsible headings with what's left in them, and a list jumps straight to one. A pill gives the real completion rate — green when complete, amber when not, and only 100 % when every key is done. An absent key (falls back to English) is told apart from an empty one (shows nothing at all), listed separately, empty first; an outdated translation is flagged with its date gap and a "To review" filter; and where a StarHubFR backup still holds a translation lost to an update, the mod's page says so with its date. Files are read the way their authors write them — comments, trailing commas, unquoted keys, CRLF, legacy UTF-16/UTF-32/8-bit encodings — what the game loads, we read.
*   **Mod Backups**:
    *   *Install backup*: Automatic backup before overwriting a mod, with hybrid retention (5 most recent + ≤30 days + 1 per month beyond).
    *   *Config backup*: Backup and restore `config.json`/`fr.json` files for enabled mods.
*   **Mod Config Editor**: Edit a mod's `config.json` directly in the app, via a hierarchical visual editor (searchable tree of typed settings) or a raw JSON editor with line numbers and live validation. Reset and restore-from-local-backup buttons included.
*   **AI-Assisted Translation**: A model running on your own Mac fills the draft — one key at a time, or a batch you can stop and resume. Suggestions arrive marked *Needs review*, with a filter to find them, and go through the same marker check as anything you type. Nothing leaves the machine: only a loopback address is accepted, with no proxy and no redirect followed. A glossary built from your installed game — over a thousand item, tool, character, location and season names — is imposed on the model, so a suggestion reads *Minerai d'iridium* rather than an invented synonym, and the matching terms show as chips in the editor. Since a fresh Ollama has no model and the right name is not guessable, Settings reads this Mac's memory, names a model that fits and the one command to run — or points at a suitable model you already have.
*   **Advanced Mod List**: Automatic classification by **type** (UI, Framework, Content Patcher, Translation, NPC, Audio, Map…) inferred from the manifest, also used as an offline fallback for the category filter. Category filtering, pagination (15 mods/page with direct page jump), uncategorized mod filter, "With Config" filter (configurable mods only), sorting by name (A-Z/Z-A), author, version or activation order. A gear icon on each configurable mod opens the config editor directly.
*   **Save Manager**:
    *   View details of all save files (money, in-game time, season, farm layout)
    *   Duplicate or delete save files
    *   Edit money and basic character stats
*   **Developer Logs**: Monitor SMAPI output in real time directly within the app. Filter by source (StarHubFR/SMAPI) and by level with counts, search, and copy lines that keep their origin and the mod they came from.
*   **SMAPI Diagnostics**: A health card at the top of the logs turns `SMAPI-latest.txt` into a readable diagnosis — SMAPI and game versions, loaded mods and content packs, skipped or failed mods **with the reason**, missing dependencies, mods that change game code or your saves, and the mods logging the most errors. It leads with **"What you can do"**: actionable advice in plain language instead of jargon. An **"Errors you can ignore"** section recognizes common false alarms (GOG Galaxy sign-in, an unavailable optional integration, a missing companion mod, a mod failing to read its own data), names the mod involved, quotes the original message, and offers a button that jumps straight to its lines in the log — and they no longer count against the mod. A badge flags a stale log, and a button reveals it in Finder. Repetitive lines fold into one expandable row, entries can be grouped per mod (most problematic first), and each mod keeps a per-version history of the errors it logged, shown on its detail page — so you can tell whether a new version behaves worse than the one before.
*   **In-App Changelog Viewer**: Browse the version history (`CHANGELOG.md`) directly from the app's sidebar.
*   **Bilingual Support**: Switch the app language instantly between French and English.
*   **Native macOS UI**: A clean, intuitive interface designed to feel right at home on macOS.
*   **VoiceOver Accessibility**: Full screen-reader navigation across the mod list, action buttons, sidebar, and the empty-state install zone.
*   **System Status Footer**: Persistent at-a-glance counts for active mods, pending updates, and SMAPI errors in the sidebar.
*   **Empty-State Drop Zone**: When no mods are installed, a large visual drag-and-drop prompt replaces plain text.
*   **Cached Mod Images**: Mod detail-pane banners are now cached for faster repeat display.
*   **Improved Mod Search**: Missing-dependency links now open Nexus with a human-readable search term (e.g. "Content Patcher" instead of "Pathoschild.ContentPatcher").

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/screenshots_banner.png" alt="Screenshots" width="300">
</p>

|   |   |
| :---: | :---: |
| <img src="screenshots/1.png" width="400"> | <img src="screenshots/2.png" width="400"> |
| <img src="screenshots/3.png" width="400"> | <img src="screenshots/4.png" width="400"> |
| <img src="screenshots/5.png" width="400"> | <img src="screenshots/6.png" width="400"> |
| <img src="screenshots/7.png" width="400"> | <img src="screenshots/8.png" width="400"> |
| <img src="screenshots/9.png" width="400"> | <img src="screenshots/10.png" width="400"> |
| <img src="screenshots/11.png" width="400"> | <img src="screenshots/12.png" width="400"> |

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="Installation" width="300">
</p>

### Minimum Requirements
*   **Operating System**: macOS 14.0 (Sonoma) or later
*   **Stardew Valley**: the game installed on macOS (Steam or GOG version)
*   **Optional**: [SMAPI](https://smapi.io/) for playing with mods

### Installation Steps
1. **Download**: Grab the latest release from the [Releases](../../releases) page.
2. **Install**: Unzip the file and drag `StarHubFR.app` into your Applications folder, then double-click to launch.
3. **Set Game Folder**: On first launch, the app will attempt to auto-detect your Steam game folder. If not found, you can manually select the game directory (e.g. `/Applications/Stardew Valley.app/Contents/MacOS`).
4. **You're ready!**: Manage your mods or saves, then hit **"Launch Game"** on the Home page.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/developers_banner.png" alt="For Developers" width="300">
</p>

This app is built with **Swift** and **SwiftUI** as a native macOS application.

### Requirements
*   macOS 14.0 (Sonoma) or later
*   Xcode 15.0 or later (for compiling from source)

### Running the Project
You can open the project in Xcode or compile via Terminal using the build script:
```bash
python3 build_app.py
open StarHubFR.app
```

### Building a Release
To package the app into a `.zip` for distribution:
```bash
python3 release.py
```
Release files will be saved in the `bundles/` folder.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/credits_banner.png" alt="Credits & License" width="300">
</p>

This project is released under the [MIT License](LICENSE). Feel free to fork, modify, and build upon it.
Original project: [StarHubTH](https://github.com/AppleBoiy/StarHubTH) by **AppleBoiy** — which offers a **Thai** version.

### Acknowledgements

StarHubFR's **SMAPI diagnostics** owe a lot to the following work:

*   [**SMAPILogDoctor.py**](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py) by **ZeroXPatch** — the idea of a player-facing SMAPI log doctor (skipped mods with their reason, missing dependencies, risk categories, suggested fixes) was the starting point for our parser.
*   [**smapi.io/log**](https://smapi.io/log/) — SMAPI's official log parser, our reference for what's worth extracting from a log.
*   [**SMAPI**](https://github.com/pathoschild/SMAPI) by **Pathoschild** — the exact log format (warning-group sections, levels, headers) was verified directly against the sources, notably `LogManager.cs`.

StarHubFR's **assisted translation** (game-term glossary, AI pre-translation) owes a lot to the following work:

*   [**lzxd**](https://github.com/Lonami/lzxd) by **Lonami** (MIT / Apache-2.0) — our LZX decoder, which reads the game's official localization files straight from your install, is a Swift transliteration of this implementation.
*   [**stardew-i18n-translator**](https://github.com/Nana1873/stardew-i18n-translator) by **Nana1873** (GPL-3.0) — a Windows mod-translation app whose workflow served as the design reference for ours. No code is taken from it: the licenses rule that out.
*   [**StardewXnbHack**](https://github.com/Pathoschild/StardewXnbHack) by **Pathoschild** (MIT) — used as the oracle that validates our game-file reader, byte for byte.
*   [**Ollama**](https://ollama.com) (MIT) — the local AI server the app detects, points you to, and sends to — the only recipient of anything it sends. StarHubFR neither installs nor bundles it: it runs on your machine, under your control.
*   [**LM Studio**](https://lmstudio.ai) — detected alongside Ollama when it exposes its OpenAI-compatible API (free, proprietary).
*   [**Qwen2.5**](https://ollama.com/library/qwen2.5) by the **Qwen team** (Apache-2.0) — the family the app suggests by default: multilingual, regular sizes, and above all **no reasoning** — a model that deliberates before answering burns its token budget and returns a truncated translation. The choice stays yours: the Model field takes anything your server serves.
