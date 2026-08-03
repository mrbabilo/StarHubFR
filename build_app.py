#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import sys

APP_NAME = "StarHubFR"
APP_DIR = f"{APP_NAME}.app"
CONTENTS_DIR = os.path.join(APP_DIR, "Contents")
MACOS_DIR = os.path.join(CONTENTS_DIR, "MacOS")
RESOURCES_DIR = os.path.join(CONTENTS_DIR, "Resources")
SUPPORTED_LOCALES = {
    "en": "Centralized English Localization Strings",
    "fr": "Centralized French Localization Strings",
}

def strings_escape(value: str) -> str:
    return (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )

def generate_localizable_strings() -> None:
    locale_data: dict[str, dict[str, str]] = {}
    for locale in SUPPORTED_LOCALES:
        json_path = os.path.join("assets", f"{locale}.json")
        with open(json_path, "r", encoding="utf-8") as file:
            locale_data[locale] = json.load(file)

    key_sets: dict[str, set[str]] = {locale: set(values.keys()) for locale, values in locale_data.items()}
    reference_locale = "en"
    reference_keys: set[str] = key_sets[reference_locale]
    for locale, keys in key_sets.items():
        missing: list[str] = sorted(reference_keys - keys)
        extra: list[str] = sorted(keys - reference_keys)
        if missing or extra:
            if missing:
                print(f"[ERROR] {locale}.json is missing keys: {', '.join(missing)}")
            if extra:
                print(f"[ERROR] {locale}.json has extra keys: {', '.join(extra)}")
            raise SystemExit(1)

    for locale, values in locale_data.items():
        lproj_dir = os.path.join("assets", f"{locale}.lproj")
        os.makedirs(lproj_dir, exist_ok=True)
        strings_path = os.path.join(lproj_dir, "Localizable.strings")
        with open(strings_path, "w", encoding="utf-8") as file:
            file.write(f"/* {SUPPORTED_LOCALES[locale]} */\n")
            lines = [
                f'"{strings_escape(key)}" = "{strings_escape(value)}";\n'
                for key, value in values.items()
            ]
            file.writelines(lines)
        print(f"[INFO] Generated {strings_path}")

def gather_swift_files() -> list[str]:
    """Return every .swift file compiled into the app (whole StarHubTH/ tree)."""
    swift_files: list[str] = []
    for root, _, files in os.walk("StarHubTH"):
        for file in files:
            if file.endswith(".swift"):
                swift_files.append(os.path.join(root, file))
    return sorted(swift_files)

def build_swiftc_command(swift_files: list[str], app_executable: str, module_cache_dir: str) -> list[str]:
    """The exact swiftc invocation used to compile the app (single module)."""
    # Pin an explicit deployment target (macOS 14, matching Package.swift and
    # Info.plist's LSMinimumSystemVersion). Without `-target` swiftc derives it
    # from the SDK, which on the macOS 26 / Tahoe toolchain fails with
    # "unable to load standard library for target 'arm64-apple-macosx26.0'".
    # Detect the host arch so Intel machines aren't broken by a hard-coded arm64.
    arch = platform.machine()  # arm64 (Apple Silicon) or x86_64 (Intel)
    return ["swiftc"] + swift_files + [
        "-target", f"{arch}-apple-macosx14.0",
        "-o", app_executable,
        "-parse-as-library",
        "-module-cache-path", module_cache_dir,
    ]

def write_compile_commands(swift_files: list[str], app_executable: str, module_cache_dir: str) -> None:
    """Write a compile database so SourceKit-LSP indexes ALL files (Core + UI).

    The app is one swiftc-compiled module, so every file's entry carries the
    full whole-module command. Regenerated on each build; keep out of git.
    """
    repo_root = os.path.abspath(".")
    arguments: list[str] = build_swiftc_command(swift_files, app_executable, module_cache_dir)
    entries: list[dict[str, str | list[str]]] = [
        {
            "directory": repo_root,
            "file": os.path.abspath(swift_file),
            "arguments": arguments,
        }
        for swift_file in swift_files
    ]
    with open("compile_commands.json", "w", encoding="utf-8") as file:
        json.dump(entries, file, indent=2)
    print(f"[INFO] Wrote compile_commands.json ({len(entries)} files) for SourceKit-LSP")

def generate_compile_commands_only():
    """Regenerate compile_commands.json without a full app build."""
    swift_files = gather_swift_files()
    if not swift_files:
        print("[ERROR] No Swift source files (.swift) found.")
        sys.exit(1)
    app_executable = os.path.join(MACOS_DIR, APP_NAME)
    module_cache_dir = os.path.join(".build", "module-cache")
    write_compile_commands(swift_files, app_executable, module_cache_dir)

def create_app_bundle():
    print(f"[INFO] Starting build process for {APP_DIR}...")
    generate_localizable_strings()
    
    # 1. Clean old build
    if os.path.exists(APP_DIR):
        shutil.rmtree(APP_DIR)
        
    # 2. Create directories
    os.makedirs(MACOS_DIR, exist_ok=True)
    os.makedirs(RESOURCES_DIR, exist_ok=True)
    
    # 3. Copy Info.plist and Generate Custom Assets
    shutil.copy2("Info.plist", os.path.join(CONTENTS_DIR, "Info.plist"))
    
    print("[INFO] Using existing Custom Stardew UI Assets...")
    
    custom_ui_dir = "assets/custom_ui"
    if os.path.exists(custom_ui_dir):
        for img in os.listdir(custom_ui_dir):
            if img.endswith(".png"):
                shutil.copy2(os.path.join(custom_ui_dir, img), os.path.join(RESOURCES_DIR, img))
        print("[INFO] Copied Custom UI Assets to App Resources")
        
    app_icon_path = "assets/AppIcon.icns"
    if os.path.exists(app_icon_path):
        shutil.copy2(app_icon_path, os.path.join(RESOURCES_DIR, "AppIcon.icns"))
        print("[INFO] Copied AppIcon.icns to App Resources")

    # Cover artwork used as the launch overlay background (see MainView's
    # launchBackgroundImage). Bundled so the overlay can find it at runtime
    # via Bundle.main.resourceURL without depending on the source tree.
    cover_path = "assets/nexus_cover_final.png"
    if os.path.exists(cover_path):
        shutil.copy2(cover_path, os.path.join(RESOURCES_DIR, "nexus_cover_final.png"))
        print("[INFO] Copied nexus_cover_final.png to App Resources")

    changelog_path = "CHANGELOG.md"
    if os.path.exists(changelog_path):
        shutil.copy2(changelog_path, os.path.join(RESOURCES_DIR, "CHANGELOG.md"))
        print("[INFO] Copied CHANGELOG.md to App Resources")

    for lang in ["en.lproj", "fr.lproj"]:
        lproj_src = os.path.join("assets", lang)
        if os.path.exists(lproj_src):
            lproj_dest = os.path.join(RESOURCES_DIR, lang)
            os.makedirs(lproj_dest, exist_ok=True)
            shutil.copy2(os.path.join(lproj_src, "Localizable.strings"), os.path.join(lproj_dest, "Localizable.strings"))
            print(f"[INFO] Copied {lang} to App Resources")
        
    # 4. Compile Swift App
    app_executable = os.path.join(MACOS_DIR, APP_NAME)
    module_cache_dir = os.path.join(".build", "module-cache")
    os.makedirs(module_cache_dir, exist_ok=True)
    
    # Find all Swift files recursively under StarHubTH
    swift_files = gather_swift_files()
    if not swift_files:
        print("[ERROR] No Swift source files (.swift) found.")
        sys.exit(1)

    # Keep the LSP compile database in sync with what we actually compile
    write_compile_commands(swift_files, app_executable, module_cache_dir)

    print(f"[INFO] Compiling Swift code ({len(swift_files)} files)...")
    swiftc_cmd = build_swiftc_command(swift_files, app_executable, module_cache_dir)

    # Run compiler. `xcrun` resolves the active Xcode toolchain and exports the
    # SDKROOT/DEVELOPER_DIR that the swiftc driver needs to locate the standard
    # library. Invoking `swiftc` directly fails with "unable to load standard
    # library for target ..." on a clean shell where the toolchain env is unset.
    result = subprocess.run(["xcrun"] + swiftc_cmd, check=False)
    if result.returncode != 0:
        print("[ERROR] Swift compilation failed.")
        sys.exit(1)
        
    # 5. Ad-hoc codesign to make it run locally without Gatekeeper blocking
    print("[INFO] Signing application (Codesign)...")
    codesign_cmd = ["codesign", "-s", "-", "-f", APP_DIR]
    codesign_result = subprocess.run(codesign_cmd, check=False)
    if codesign_result.returncode != 0:
        print("[ERROR] Codesign failed.")
        sys.exit(1)

    # 6. Ratchet on the Swift conventions. Runs after a successful compile so a
    # genuine compile error is never buried under convention noise. It only
    # fails on an *increase* against the committed baseline — see
    # check_standards.py for why it's a ratchet and not a gate.
    if "--skip-standards" not in sys.argv and os.path.exists("check_standards.py"):
        print("[INFO] Checking Swift conventions (ratchet)...")
        standards = subprocess.run([sys.executable, "check_standards.py"], check=False)
        if standards.returncode != 0:
            print("[ERROR] Build stopped: new convention violations. "
                  "Rerun with --skip-standards to build anyway.")
            sys.exit(1)

    print(f"[SUCCESS] Successfully built {APP_DIR}")
    print("[INFO] Run 'open StarHubFR.app' to launch the application.")

if __name__ == "__main__":
    if "--gen-compile-commands" in sys.argv:
        # Refresh the SourceKit-LSP index without a full app build.
        generate_compile_commands_only()
    else:
        create_app_bundle()
