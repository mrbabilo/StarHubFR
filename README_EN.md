> [!IMPORTANT]
> This fork adds French language support and a French-touch UX/UI. See the [French README](README.md).

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
*   **Mod Manager**: Enable or disable mods effortlessly through a beautiful app interface — no manual file moving required.
*   **Drag & Drop Mod Installer**: Drag a `.zip` file directly into the app to install one or more mods. Automatic structure detection (single-mod, multi-mod pack), integrity validation (anti-zip-bomb, < 500 MB), conflict preview and missing dependency suggestions.
*   **Mod Profiles**: Group mods into multiple profiles and switch between them instantly with a single click.
*   **Thai Translation Hub**: A dedicated hub listing all Thai translation mods — browse, check status, download, and track updates in one place.
*   **Nexus Mods Update Checker**: Manually check for mod updates via the Nexus Mods API. API key securely stored in macOS Keychain, update detection even at identical version (upload date comparison).
*   **Mod Backups**:
    *   *Install backup*: Automatic backup before overwriting a mod, with hybrid retention (5 most recent + ≤30 days + 1 per month beyond).
    *   *Config backup*: Backup and restore `config.json`/`fr.json` files for enabled mods.
*   **Mod Config Editor**: Edit a mod's `config.json` directly in the app, via a hierarchical visual editor (searchable tree of typed settings) or a raw JSON editor with line numbers and live validation. Reset and restore-from-local-backup buttons included.
*   **Advanced Mod List**: Category filtering, pagination (15 mods/page with direct page jump), uncategorized mod filter, "With Config" filter (configurable mods only), sorting by name (A-Z/Z-A), author, version or activation order, and description image support. A gear icon on each configurable mod opens the config editor directly.
*   **Save Manager**:
    *   View details of all save files (money, in-game time, season, farm layout)
    *   Duplicate or delete save files
    *   Edit money and basic character stats
*   **Developer Logs**: Monitor SMAPI output in real time directly within the app.
*   **In-App Changelog Viewer**: Browse the version history (`CHANGELOG.md`) directly from the app's sidebar.
*   **Bilingual Support**: Switch the app language instantly between French and English.
*   **Native macOS UI**: A clean, intuitive interface designed to feel right at home on macOS.

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
2. **Install**: Unzip the file and drag `StarHubTH.app` into your Applications folder, then double-click to launch.
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
open StarHubTH.app
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
