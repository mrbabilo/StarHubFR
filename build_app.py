#!/usr/bin/env python3
from __future__ import annotations

import json
import re
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

    # Toute constante de `L10n.swift` doit exister dans les assets. La parité
    # ci-dessus ne dit rien de ce cas : une clé déclarée en Swift mais absente
    # des JSON compile, se copie dans le bundle, et **s'affiche telle quelle à
    # l'écran** — `localizedString(for:)` rend la clé quand la table ne la
    # porte pas. C'est un défaut que seul un œil sur l'écran attrapait.
    #
    # Les lignes de commentaires `// …` sont strippées avant le regex pour la
    # même raison que `check_standards.py` le fait : écrire *sur* une violation
    # (ex. un commentaire qui ressemblerait à une déclaration) ne doit pas en
    # être une — sinon la doc du fichier casserait le build.
    l10n_path = os.path.join("StarHubTH", "L10n.swift")
    with open(l10n_path, "r", encoding="utf-8") as f:
        l10n_source = "\n".join(
            line for line in f.read().splitlines()
            if not line.lstrip().startswith("//")
        )
    declared = re.findall(r'static let \w+\s*=\s*"([^"]+)"', l10n_source)
    undeclared = sorted({key for key in declared if key not in reference_keys})
    if undeclared:
        print(f"[ERROR] L10n.swift declares keys absent from assets/{reference_locale}.json: "
              f"{', '.join(undeclared)}")
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
    """Compilation whole-module — chemin de repli (`--whole-module`) et base de
    la table `compile_commands.json` servie à SourceKit-LSP.

    Ce n'est plus le chemin par défaut depuis F2-T2 : voir `build_incremental`.

    Whole-module: one swiftc invocation produces the executable. There is no
    object file the driver can reuse on the next build — `-incremental` only
    helps in `swift build`'s per-file `-c` + link workflow, not here. So the
    real build-time wins live in steps *around* swiftc: skipping the
    `compile_commands.json` rewrite when the file list is stable, and skipping
    `check_standards.py` when no source has changed since the last run. See
    `write_compile_commands` and the `STANDARDS_FRESH` cache for those.
    """
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

OBJECTS_DIR = os.path.join(".build", "objects")
OUTPUT_FILE_MAP = os.path.join(".build", "output-file-map.json")
MODULE_NAME = APP_NAME


def object_stem(swift_file: str) -> str:
    """Nom d'objet unique et stable pour un chemin source.

    `Models/X.swift` et `Views/X.swift` coexistent dans l'arbre : aplatir sur
    le seul nom de fichier les ferait s'écraser l'un l'autre, et le build
    produirait un binaire amputé sans rien signaler.
    """
    return os.path.splitext(swift_file)[0].replace(os.sep, "_")


def write_output_file_map(swift_files: list[str]) -> None:
    """Table des sorties par fichier, exigée par le mode incrémental.

    L'entrée `""` porte les dépendances au niveau module ; sans elle, swiftc
    refuse `-incremental`. Les `.swiftdeps` sont ce qui lui permet de savoir
    quels fichiers retoucher quand une déclaration change.
    """
    os.makedirs(OBJECTS_DIR, exist_ok=True)
    entries: dict[str, dict[str, str]] = {
        "": {"swift-dependencies": os.path.join(OBJECTS_DIR, "master.swiftdeps")}
    }
    for swift_file in swift_files:
        stem = os.path.join(OBJECTS_DIR, object_stem(swift_file))
        entries[os.path.abspath(swift_file)] = {
            "object": f"{stem}.o",
            "swift-dependencies": f"{stem}.swiftdeps",
            "dependencies": f"{stem}.d",
        }
    with open(OUTPUT_FILE_MAP, "w", encoding="utf-8") as file:
        json.dump(entries, file, indent=2)


def build_incremental(swift_files: list[str], app_executable: str,
                      module_cache_dir: str) -> bool:
    """Compile en objets par fichier puis lie — le mode incrémental de swiftc.

    Le chemin par défaut (`build_swiftc_command`) compile les 211 fichiers en
    **whole-module** : un seul binaire produit d'un coup, rien à réutiliser au
    build suivant, d'où l'égalité froid/chaud mesurée en F2-T1. Ici swiftc
    émet un `.o` par fichier et tient ses propres `.swiftdeps`, donc une
    modification isolée ne recompile que ce qu'elle touche.

    Défaut depuis le 2026-09-02, après lancement réel de l'app produite par ce
    chemin — l'équivalence des symboles (70 791 des deux côtés) ne prouve pas
    qu'un binaire démarre, seul un lancement le fait. `--whole-module` rend
    l'ancien chemin, comme filet et comme référence de mesure.
    """
    arch = platform.machine()
    target = f"{arch}-apple-macosx14.0"
    # ⚠️ Les chemins passés à swiftc doivent être **littéralement** les clés
    # du fichier de sortie : il compare les chaînes, pas les fichiers. Avec des
    # clés absolues et des arguments relatifs, il ne trouve aucune entrée,
    # désactive l'incrémental (« has no swiftDeps file ») et écrit ses objets
    # dans le répertoire courant — 214 `.o` et 214 `.swiftdeps` semés à la
    # racine du dépôt, sans le moindre code d'erreur.
    write_output_file_map(swift_files)

    compile_cmd = ["swiftc", "-c", "-incremental", "-enable-batch-mode",
                   "-output-file-map", OUTPUT_FILE_MAP,
                   "-module-name", MODULE_NAME,
                   "-target", target,
                   "-parse-as-library",
                   "-module-cache-path", module_cache_dir,
                   "-j", str(os.cpu_count() or 4)] + [os.path.abspath(f) for f in swift_files]
    print(f"[INFO] Compiling incrementally ({len(swift_files)} files)...")
    if subprocess.run(["xcrun"] + compile_cmd, check=False).returncode != 0:
        print("[ERROR] Incremental compilation failed.")
        return False

    objects = [os.path.join(OBJECTS_DIR, object_stem(f) + ".o") for f in swift_files]
    missing = [o for o in objects if not os.path.exists(o)]
    if missing:
        # Lier une liste amputée produirait un exécutable qui manque des
        # symboles sans que l'édition de liens le dise toujours.
        print(f"[ERROR] {len(missing)} object file(s) missing, e.g. {missing[0]}")
        return False

    print("[INFO] Linking...")
    link_cmd = ["swiftc", "-o", app_executable, "-target", target] + objects
    if subprocess.run(["xcrun"] + link_cmd, check=False).returncode != 0:
        print("[ERROR] Link failed.")
        return False
    return True


def write_compile_commands(swift_files: list[str], app_executable: str, module_cache_dir: str) -> None:
    """Write a compile database so SourceKit-LSP indexes ALL files (Core + UI).

    The app is one swiftc-compiled module, so every file's entry carries the
    full whole-module command. Regenerated on each build; keep out of git.

    Skips the write when the set of files (sorted + absolute) is unchanged
    since the previous build — regenerating a multi-thousand-line JSON for
    211 entries costs ~200ms plus a SourceKit-LSP re-index trigger.
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
    fingerprint = json.dumps(
        [(e["file"], e["directory"]) for e in entries], sort_keys=True
    )
    cache_path = ".build/compile_commands.fingerprint"
    try:
        with open(cache_path, "r", encoding="utf-8") as f:
            if f.read() == fingerprint:
                # Same files, same args → LSP already knows. Skip the write
                # *and* skip the noisy "Wrote" log on quiet builds.
                return
    except FileNotFoundError:
        pass

    with open("compile_commands.json", "w", encoding="utf-8") as file:
        json.dump(entries, file, indent=2)
    os.makedirs(".build", exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        f.write(fingerprint)
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

    # Compilation incrémentale par défaut depuis le 2026-09-02 (F2-T2) :
    # 141,7 s → 2,4 s pour une modification isolée, 30,1 s au pire. Le
    # basculement n'a eu lieu qu'après lancement réel de l'app produite par ce
    # chemin — l'équivalence des symboles ne prouve pas qu'un binaire démarre.
    #
    # `--whole-module` garde l'ancien chemin accessible : c'est le filet si
    # l'incrémental venait à produire un binaire douteux, et la référence
    # contre laquelle re-mesurer.
    if "--whole-module" not in sys.argv:
        if not build_incremental(swift_files, app_executable, module_cache_dir):
            sys.exit(1)
    else:
        print(f"[INFO] Compiling Swift code ({len(swift_files)} files)...")
        swiftc_cmd = build_swiftc_command(swift_files, app_executable, module_cache_dir)

        # Run compiler. `xcrun` resolves the active Xcode toolchain and exports
        # the SDKROOT/DEVELOPER_DIR that the swiftc driver needs to locate the
        # standard library. Invoking `swiftc` directly fails with "unable to
        # load standard library for target ..." on a clean shell where the
        # toolchain env is unset.
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
