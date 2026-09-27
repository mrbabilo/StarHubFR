#!/usr/bin/env python3
"""Génère les fixtures de UpdateTriageTests (A1-T11) depuis le parc réel.

Trois cas, tous mesurés le 2026-09-27 :

- wildroot : mise à jour 1.4.1 → 1.4.2 de Wildroot Chronicles (Nexus 48079).
  Dossier installé = la sauvegarde « avant mise à jour » de la 1.4.1 ;
  archive neuve = le manifeste Nexus du fichier 184199 (1.4.2, principal).
- fotp : réinstallation de FOTP 3.4.19 (Nexus 50402) sur le dossier actuel.
- itembags : réinstallation d'ItemBags 3.1.0 (Nexus 5382), page sans aucun
  manifeste au format récent ; archive neuve = les chemins du manifeste
  ancien de 3.1.0, avec les empreintes du dossier (réinstallation).

Les empreintes sont tronquées à 16 caractères hexadécimaux : le tri ne fait
que les comparer, et la fixture reste petite. Aucun octet d'asset n'est
copié. Les manifestes Nexus sont publics.

Les chemins de versions Nexus restent **relatifs à l'archive**
(`Cropgenics/…`) : c'est l'association de racine qui doit les ramener au
dossier du mod.

Usage : python3 make_triage_fixtures.py [dossier de sortie] [dossier de cache]
"""
import hashlib, json, os, subprocess, sys, time, urllib.parse

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "Fixtures")
CACHE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.expanduser("~/Library/Caches"), "StarHubFR-triage-fixtures")
MODS = "/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS/Mods"
SUPPORT = os.path.expanduser("~/Library/Application Support/StarHubFR")
UA = "StarHubTH/1.50.0 (+https://github.com/AppleBoiy/StarHubTH)"
JUNK = {".DS_Store", "Thumbs.db", "ehthumbs.db", "Icon\r"}


def short(sha):
    return sha.lower()[:16]


def curl(url, out):
    for _ in range(3):
        r = subprocess.run(["curl", "-s", "-m", "30", "-A", UA, "-o", out, "-w", "%{http_code}", url],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if r.stdout != "000":
            return r.stdout
        time.sleep(2)
    return "000"


def mod_files(mod_id):
    path = os.path.join(CACHE, f"modfiles-{mod_id}.json")
    if not os.path.exists(path):
        body = json.dumps({"query": "{ modFiles(modId: %d, gameId: 1303) "
                                    "{ fileId version uri category name date } }" % mod_id})
        subprocess.run(["curl", "-s", "-m", "30", "-A", UA, "https://api.nexusmods.com/v2/graphql",
                        "-H", "Content-Type: application/json", "-d", body, "-o", path],
                       check=True, stdin=subprocess.DEVNULL)
    return json.load(open(path))["data"]["modFiles"]


def recent_manifest(uri):
    path = os.path.join(CACHE, "m-" + uri.replace("/", "_") + ".json")
    if not os.path.exists(path):
        code = curl("https://mod-file-manifests.nexusmods.com/" + uri, path)
        if code != "200":
            os.remove(path)
            return None
    return json.load(open(path))


def legacy_paths(mod_id, uri):
    path = os.path.join(CACHE, f"legacy-{mod_id}-" + uri.replace("/", "_") + ".json")
    if not os.path.exists(path):
        url = ("https://file-metadata.nexusmods.com/file/nexus-files-s3-meta/1303/%d/%s.json"
               % (mod_id, urllib.parse.quote(uri)))
        if curl(url, path) != "200":
            sys.exit(f"manifeste ancien introuvable : {uri}")
    out = []

    def walk(node):
        if node.get("type") == "file":
            out.append(node["path"])
        for child in node.get("children", []):
            walk(child)
    walk(json.load(open(path)))
    return out


def folder(root):
    out = {}
    for dirpath, dirs, files in os.walk(root):
        for name in files:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            if any(part in JUNK or part.startswith("._") for part in rel.split("/")):
                continue
            out[rel] = short(hashlib.sha256(open(full, "rb").read()).hexdigest())
    return out


def backup(folder_name, version):
    meta = json.load(open(os.path.join(SUPPORT, "Backups/ModInstalls/install_metadata.json")))
    items = meta if isinstance(meta, list) else meta.get("backups", list(meta.values()))
    hit = [b for b in items if b.get("originalFolderName") == folder_name
           and b.get("modMetadata", {}).get("version") == version][0]
    files = folder(hit["backupPath"])
    if "manifest.json" not in files:
        files = {k.split("/", 1)[1]: v for k, v in files.items() if "/" in k}
    return files


def recent_versions(mod_id):
    versions = []
    for f in sorted(mod_files(mod_id), key=lambda f: f["fileId"]):
        if "/" not in f["uri"]:
            continue
        manifest = recent_manifest(f["uri"])
        if manifest is None:
            continue
        files = {e["file_path"].replace("\\", "/"): short(e["file_hashes"]["SHA256"])
                 for e in manifest.get("files", [])}
        versions.append({"fileId": f["fileId"], "version": f["version"],
                         "category": f["category"], "files": files})
    return versions


def mapped(files, root):
    return {p[len(root):]: h for p, h in files.items() if p.startswith(root)}


def relevant(versions, keys):
    """Ne garde d'une version que ses `manifest.json` et les fichiers dont un
    suffixe de chemin existe dans le dossier ou l'archive neuve : les autres ne
    changent aucune décision du tri, et la fixture passe de 1 Mo à ~0,3 Mo."""
    lowered = {k.lower() for k in keys}
    out = []
    for v in versions:
        files = {}
        for p, h in v["files"].items():
            parts = p.split("/")
            suffixes = {"/".join(parts[i:]).lower() for i in range(len(parts))}
            if parts[-1].lower() == "manifest.json" or suffixes & lowered:
                files[p] = h
        out.append(dict(v, files=files))
    return out


def case(name, installed_version, installed, new_archive, versions):
    versions = relevant(versions, set(installed) | set(new_archive))
    return {"name": name, "installedVersion": installed_version,
            "installed": dict(sorted(installed.items())),
            "newArchive": dict(sorted(new_archive.items())),
            "versions": versions}


os.makedirs(CACHE, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

wildroot_versions = recent_versions(48079)
main_142 = next(v for v in wildroot_versions if v["fileId"] == 184199)
wildroot = case("wildroot", "1.4.1", backup("Cropgenics", "1.4.1"),
                mapped(main_142["files"], "Cropgenics/"),
                [v for v in wildroot_versions if v["fileId"] != 184199])

fotp_versions = recent_versions(50402)
fotp_installed = folder(os.path.join(MODS, "FOTP"))
main_3419 = max((v for v in fotp_versions if v["version"] == "3.4.19"),
                key=lambda v: sum(fotp_installed.get(p[5:]) == h for p, h in v["files"].items()
                                  if p.startswith("FOTP/")))
fotp = case("fotp", "3.4.19", fotp_installed, mapped(main_3419["files"], "FOTP/"), fotp_versions)

itembags_installed = folder(os.path.join(MODS, ".ItemBags"))
legacy_310 = next(f for f in mod_files(5382) if f["version"] == "3.1.0" and f["category"] == "MAIN")
shipped = [p[len("ItemBags/"):] for p in legacy_paths(5382, legacy_310["uri"])
           if p.startswith("ItemBags/")]
itembags = case("itembags", "3.1.0", itembags_installed,
                {p: itembags_installed[p] for p in shipped if p in itembags_installed},
                recent_versions(5382))

for c in (wildroot, fotp, itembags):
    with open(os.path.join(OUT, f"triage-{c['name']}.json"), "w", encoding="utf-8") as handle:
        json.dump(c, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"{c['name']}: {len(c['installed'])} installés, {len(c['newArchive'])} dans l'archive "
          f"neuve, {len(c['versions'])} versions au format récent")

sample = recent_manifest(main_142["uri"] if "uri" in main_142 else
                         next(f["uri"] for f in mod_files(48079) if f["fileId"] == 184199))
sample["files"] = sample["files"][:3]
with open(os.path.join(OUT, "manifest-recent-sample.json"), "w", encoding="utf-8") as handle:
    json.dump(sample, handle, ensure_ascii=False, indent=1)
print("manifest-recent-sample.json : 3 fichiers")
