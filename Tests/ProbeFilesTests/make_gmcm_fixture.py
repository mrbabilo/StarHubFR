#!/usr/bin/env python3
"""Extrait Fixtures/gmcm-options.json (D4-T7) de la vraie capture de la sonde.

Liste FERMÉE de mods : les copies de config.json finissent dans un dépôt
public. Une copie dont une clé ressemble à un secret est refusée.

Tant que la sonde v0.4.11 n'a pas tourné, la capture n'a ni ConfigSnapshot,
ni Version, ni Language : ils sont reconstitués depuis le disque (config.json
et manifest.json actuels), et seulement pour des mods dont le config.json
date d'avant la capture. Dès qu'une capture v0.4.11 existe, ses champs sont
repris tels quels — relancer ce script après la session, puis ajuster les
comptes attendus de GmcmCaptureTests s'ils bougent.

Usage : python3 make_gmcm_fixture.py [dossier Mods] [dossier de sortie]
"""
import datetime, json, os, re, sys

MODS = sys.argv[1] if len(sys.argv) > 1 else \
    "/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS/Mods"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "Fixtures")
EXPORT = os.path.expanduser(
    "~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe/gmcm-options.json")
KEEP = ["palmhacker13.UltraSmooth", "Digus.MailServicesMod", "Nullnnow.MS-Books",
        "Owenynk.InteractionBubbles", "leclair.bettercrafting", "ThaleTheGreat.WalletTools",
        "KCC.SnS", "Pathoschild.CentralStation", "Exonika.TheMuseumPays"]
SECRET = re.compile(r"api.?key|token|password|webhook", re.I)


def lenient(text):
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    text = re.sub(r"(?m)^\s*//.*$", "", text)
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", text))


def keys(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from keys(value)


folders = {}
for root, dirs, files in os.walk(MODS):
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    if "manifest.json" in files:
        try:
            manifest = lenient(open(os.path.join(root, "manifest.json"), encoding="utf-8-sig").read())
            folders.setdefault(manifest.get("UniqueID", "").lower(), (root, manifest))
        except Exception:
            pass

export = json.load(open(EXPORT, encoding="utf-8-sig"))
stamp = export["CapturedAt"]
captured = datetime.datetime.fromisoformat(stamp[:26] + stamp[-6:]).timestamp()
mods = []
for mod in export["Mods"]:
    if mod["UniqueID"] not in KEEP:
        continue
    if "ConfigSnapshot" not in mod:
        root, manifest = folders[mod["UniqueID"].lower()]
        path = os.path.join(root, "config.json")
        if os.path.getmtime(path) > captured:
            sys.exit(f"{mod['UniqueID']} : config.json réécrit après la capture, copie non reconstituable")
        mod["ConfigSnapshot"] = open(path, encoding="utf-8-sig").read()
        mod["Version"] = manifest["Version"]
        for option in mod["Options"]:
            option.setdefault("ChoiceLabels", None)
    if mod["ConfigSnapshot"] is not None:
        secret = [k for k in keys(lenient(mod["ConfigSnapshot"])) if SECRET.search(k)]
        if secret:
            sys.exit(f"{mod['UniqueID']} : clé qui ressemble à un secret ({secret[0]}), fixture refusée")
    mods.append(mod)

missing = set(KEEP) - {m["UniqueID"] for m in mods}
if missing:
    sys.exit(f"absents de la capture : {sorted(missing)}")
export["Mods"] = mods
export.setdefault("Language", "fr")
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "gmcm-options.json"), "w", encoding="utf-8") as handle:
    json.dump(export, handle, ensure_ascii=False, indent=2)
print(f"{len(mods)} mods, {sum(len(m['Options']) for m in mods)} options → {OUT}/gmcm-options.json")
