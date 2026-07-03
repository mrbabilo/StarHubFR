#!/usr/bin/env python3
import os
import shutil
import glob
import subprocess
import plistlib

APP_NAME = "StarHubTH"
APP_DIR = f"{APP_NAME}.app"
CONTENTS_DIR = os.path.join(APP_DIR, "Contents")
MACOS_DIR = os.path.join(CONTENTS_DIR, "MacOS")
RESOURCES_DIR = os.path.join(CONTENTS_DIR, "Resources")

def create_app_bundle():
    print(f"[INFO] Starting build process for {APP_DIR}...")
    
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
        
    for lang in ["en.lproj", "th.lproj", "ja.lproj"]:
        lproj_src = os.path.join("assets", lang)
        if os.path.exists(lproj_src):
            lproj_dest = os.path.join(RESOURCES_DIR, lang)
            os.makedirs(lproj_dest, exist_ok=True)
            shutil.copy2(os.path.join(lproj_src, "Localizable.strings"), os.path.join(lproj_dest, "Localizable.strings"))
            print(f"[INFO] Copied {lang} to App Resources")
        
    # 4. Compile Swift App
    app_executable = os.path.join(MACOS_DIR, APP_NAME)
    
    # Find all Swift files recursively under StarHubTH
    swift_files = []
    for root, dirs, files in os.walk("StarHubTH"):
        for file in files:
            if file.endswith(".swift"):
                swift_files.append(os.path.join(root, file))
                
    if not swift_files:
        print("[ERROR] No Swift source files (.swift) found.")
        return
        
    print(f"[INFO] Compiling Swift code ({len(swift_files)} files)...")
    swiftc_cmd = ["swiftc"] + swift_files + ["-o", app_executable, "-parse-as-library"]
    
    # Run compiler
    result = subprocess.run(swiftc_cmd)
    if result.returncode != 0:
        print("[ERROR] Swift compilation failed.")
        return
        
    # 5. Ad-hoc codesign to make it run locally without Gatekeeper blocking
    print("[INFO] Signing application (Codesign)...")
    codesign_cmd = ["codesign", "-s", "-", "-f", APP_DIR]
    subprocess.run(codesign_cmd)
    
    print(f"[SUCCESS] Successfully built {APP_DIR}")
    print("[INFO] Run 'open StarHubTH.app' to launch the application.")

if __name__ == "__main__":
    create_app_bundle()
