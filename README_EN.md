<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="Key Features" width="300">
</p>

*   **Easy Game Launch**: Launch Stardew Valley in either Vanilla mode or through SMAPI for modded play.
*   **Mod Manager**: Enable or disable mods effortlessly through a beautiful app interface — no manual file moving required.
*   **Mod Profiles**: Group mods into multiple profiles and switch between them instantly with a single click.
*   **Thai Translation Hub**: A dedicated hub listing all Thai translation mods — browse, check status, download, and track updates in one place.
*   **Save Manager**:
    *   View details of all save files (money, in-game time, season, farm layout)
    *   Duplicate or delete save files
    *   Edit money and basic character stats
*   **Developer Logs**: Monitor SMAPI output in real time directly within the app.
*   **Bilingual Support**: Switch the app language instantly between English and Thai (ภาษาไทย).
*   **Native macOS UI**: A clean, intuitive interface designed to feel right at home on macOS.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/screenshots_banner.png" alt="Screenshots" width="300">
</p>

| Home / Profile | Settings |
| :---: | :---: |
| <img src="screenshots/profile_en.png" width="400"> | <img src="screenshots/settings_en.png" width="400"> |

| Save Manager | Save Editor |
| :---: | :---: |
| <img src="screenshots/save_en.png" width="400"> | <img src="screenshots/save_edit_en.png" width="400"> |

| Mod Manager | Mod Profiles |
| :---: | :---: |
| <img src="screenshots/mods_en.png" width="400"> | <img src="screenshots/mod_profile_en.png" width="400"> |

| Thai Translation Hub |
| :---: |
| <img src="screenshots/th_translation_hub.png" width="400"> |

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="Installation" width="300">
</p>

1. **Download**: Grab the latest release from the [Releases](../../releases) page.
2. **Install**: Unzip the file and drag `StarHubTH.app` into your Applications folder, then double-click to launch.
3. **Set Game Folder**: On first launch, the app will attempt to auto-detect your Steam game folder. If not found, you can manually select the game directory (e.g. `/Applications/Stardew Valley.app/Contents/MacOS`).
4. **You're ready!**: Manage your mods or saves, then hit **"Launch Game"** from the left sidebar.

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
