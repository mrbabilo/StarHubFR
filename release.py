#!/usr/bin/env python3
import os
import shutil
import subprocess
import plistlib

APP_NAME = "StarHubTH"
APP_DIR = f"{APP_NAME}.app"
BUNDLES_DIR = "bundles"

def get_version():
    plist_path = "Info.plist"
    if os.path.exists(plist_path):
        with open(plist_path, 'rb') as f:
            plist = plistlib.load(f)
            return plist.get("CFBundleShortVersionString", "1.0.0")
    return "1.0.0"

def create_release():
    print("🚀 เริ่มขั้นตอนการสร้าง Release...")
    
    # 1. Build the app using existing build_app.py
    print("1️⃣ กำลัง Build แอปพลิเคชัน...")
    result = subprocess.run(["python3", "build_app.py"])
    if result.returncode != 0:
        print("❌ การ Build ล้มเหลว กรุณาตรวจสอบข้อผิดพลาดด้านบน")
        return
        
    if not os.path.exists(APP_DIR):
        print(f"❌ ไม่พบโฟลเดอร์ {APP_DIR} หลังจากการ Build")
        return
        
    # 2. Get version
    version = get_version()
    print(f"2️⃣ เวอร์ชันปัจจุบัน: v{version}")
    
    # 3. Create bundles directory
    os.makedirs(BUNDLES_DIR, exist_ok=True)
    
    # 4. Zip the app
    zip_name = f"{APP_NAME}_v{version}"
    zip_path = os.path.join(BUNDLES_DIR, f"{zip_name}.zip")
    
    # Remove old zip if exists
    if os.path.exists(zip_path):
        os.remove(zip_path)
        
    print(f"3️⃣ กำลังบีบอัดไฟล์ไปที่ {zip_path}...")
    
    # We use ditto on macOS to preserve resource forks and codesignatures properly
    subprocess.run(["ditto", "-c", "-k", "--keepParent", APP_DIR, zip_path])
    
    print("✅ สร้างไฟล์ Release สำเร็จแล้ว!")
    print(f"📁 คุณสามารถนำไฟล์ {zip_path} ไปอัปโหลดบน GitHub Releases ได้เลยครับ")

if __name__ == "__main__":
    create_release()
