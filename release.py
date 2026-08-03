#!/usr/bin/env python3
import os
import subprocess
import plistlib

APP_NAME = "StarHubFR"
APP_DIR = f"{APP_NAME}.app"
BUNDLES_DIR = "bundles"

PLIST_PATH = "Info.plist"

def get_version():
    if os.path.exists(PLIST_PATH):
        with open(PLIST_PATH, 'rb') as f:
            plist = plistlib.load(f)
            return plist.get("CFBundleShortVersionString", "1.1.0")
    return "1.1.0"

def bump_build_number():
    """Incrémente CFBundleVersion, le compteur de build.

    Deux numéros, deux rôles : CFBundleShortVersionString est la version que
    l'utilisateur lit et que le CHANGELOG date ; CFBundleVersion est le compteur
    monotone que macOS, Gatekeeper et un futur mécanisme de mise à jour
    comparent. Il doit avancer à chaque bundle qui sort, y compris deux bundles
    de la même version affichée.

    Il était tenu à la main jusqu'ici (4, 5, … 9) — ce qui finit toujours par
    sauter un tour. L'incrément a lieu avant le build, sinon le bundle produit
    embarquerait encore l'ancienne valeur.
    """
    if not os.path.exists(PLIST_PATH):
        print(f"[ERROR] {PLIST_PATH} introuvable — impossible d'incrémenter le numéro de build.")
        return None

    with open(PLIST_PATH, 'rb') as f:
        plist = plistlib.load(f)

    raw = plist.get("CFBundleVersion")
    if raw is None:
        print("[ERROR] CFBundleVersion absent d'Info.plist.")
        return None
    if not str(raw).isdigit():
        # Un compteur non entier ne se compare pas : mieux vaut s'arrêter que
        # produire un bundle dont la version se compare mal.
        print(f"[ERROR] CFBundleVersion vaut {raw!r} : ce doit être un entier simple.")
        return None

    previous = int(raw)
    plist["CFBundleVersion"] = str(previous + 1)
    with open(PLIST_PATH, 'wb') as f:
        plistlib.dump(plist, f)

    print(f"[INFO] Numéro de build : {previous} → {previous + 1} (Info.plist modifié, à commiter).")
    return previous + 1

def create_release():
    print("[INFO] Starting release process...")

    # 0. Bump the build counter before building, so the bundle carries it.
    if bump_build_number() is None:
        print("[ERROR] Release interrompue.")
        return

    # 1. Build the app using existing build_app.py
    print("[INFO] Building application...")
    result = subprocess.run(["python3", "build_app.py"])
    if result.returncode != 0:
        print("[ERROR] Application build failed. Check the errors above.")
        return
        
    if not os.path.exists(APP_DIR):
        print(f"[ERROR] Output folder {APP_DIR} not found after build.")
        return
        
    # 2. Get version
    version = get_version()
    print(f"[INFO] Current version: v{version}")
    
    # 3. Create bundles directory
    os.makedirs(BUNDLES_DIR, exist_ok=True)
    
    # 4. Zip the app
    zip_name = f"{APP_NAME}_v{version}"
    zip_path = os.path.join(BUNDLES_DIR, f"{zip_name}.zip")
    
    # Remove old zip if exists
    if os.path.exists(zip_path):
        os.remove(zip_path)
        
    print(f"[INFO] Archiving bundle to {zip_path}...")
    
    # We use ditto on macOS to preserve resource forks and codesignatures properly
    result = subprocess.run(["ditto", "-c", "-k", "--keepParent", APP_DIR, zip_path])
    if result.returncode != 0:
        print("[ERROR] ditto failed to create the zip archive.")
        return

    print("[SUCCESS] Release bundle created successfully.")
    print(f"[INFO] The bundle is ready at {zip_path}.")
    print("-" * 40)
    
    upload = input("[PROMPT] Do you want to upload this release to GitHub? (y/n): ")
    if upload.lower() in ['y', 'yes']:
        print("[INFO] Uploading release...")
        tag = f"v{version}"
        cmd = [
            "gh", "release", "create", tag, zip_path,
            "--title", f"Release {tag}",
            "--notes", f"Automated release for StarHubFR {tag}."
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            print(f"[SUCCESS] Uploaded {tag} successfully.")
            print(res.stdout.strip())
        else:
            print(f"[ERROR] Upload failed:\n{res.stderr.strip()}")
    else:
        print("[INFO] Skipping upload.")

if __name__ == "__main__":
    create_release()
