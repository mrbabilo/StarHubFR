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
    print(f"📦 เริ่มสร้าง {APP_DIR}...")
    
    # 1. Clean old build
    if os.path.exists(APP_DIR):
        shutil.rmtree(APP_DIR)
        
    # 2. Create directories
    os.makedirs(MACOS_DIR, exist_ok=True)
    os.makedirs(RESOURCES_DIR, exist_ok=True)
    
    # 3. Copy Info.plist and Generate Custom Assets
    shutil.copy2("Info.plist", os.path.join(CONTENTS_DIR, "Info.plist"))
    
    print("⏳ Generating Custom Stardew UI Assets...")
    subprocess.run(["python3", "generate_custom_assets.py"])
    
    custom_ui_dir = "assets/custom_ui"
    if os.path.exists(custom_ui_dir):
        for img in os.listdir(custom_ui_dir):
            if img.endswith(".png"):
                shutil.copy2(os.path.join(custom_ui_dir, img), os.path.join(RESOURCES_DIR, img))
        print("✅ Copied Custom UI Assets to App Resources")
        
    app_icon_path = "assets/AppIcon.icns"
    if os.path.exists(app_icon_path):
        shutil.copy2(app_icon_path, os.path.join(RESOURCES_DIR, "AppIcon.icns"))
        print("✅ Copied AppIcon.icns to App Resources")
        
    # 4. Compile Swift App
    app_executable = os.path.join(MACOS_DIR, APP_NAME)
    
    # Find all Swift files recursively under StarHubTH
    swift_files = []
    for root, dirs, files in os.walk("StarHubTH"):
        for file in files:
            if file.endswith(".swift"):
                swift_files.append(os.path.join(root, file))
                
    if not swift_files:
        print("❌ ไม่พบไฟล์โค้ด Swift (.swift)")
        return
        
    print(f"🛠️ กำลังคอมไพล์โค้ด Swift ({len(swift_files)} ไฟล์)...")
    swiftc_cmd = ["swiftc"] + swift_files + ["-o", app_executable, "-parse-as-library"]
    
    # Run compiler
    result = subprocess.run(swiftc_cmd)
    if result.returncode != 0:
        print("❌ เกิดข้อผิดพลาดในการคอมไพล์ Swift")
        return
        
    # 5. Ad-hoc codesign to make it run locally without Gatekeeper blocking
    print("🔐 กำลังเซ็นชื่อ (Codesign) แอปพลิเคชัน...")
    codesign_cmd = ["codesign", "-s", "-", "-f", APP_DIR]
    subprocess.run(codesign_cmd)
    
    print(f"✅ สร้าง {APP_DIR} สำเร็จแล้ว!")
    print("✨ ลองรันคำสั่ง open StarHubTH.app เพื่อเปิดใช้งานโปรแกรมได้เลยครับ")

if __name__ == "__main__":
    create_app_bundle()
