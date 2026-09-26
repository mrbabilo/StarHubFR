#!/usr/bin/env python3
"""Mesure combien d'options de gmcm-options.json retrouvent leur clé dans le
vrai config.json du mod (D4-T7). Un AccessPath non vide ne prouve rien : en
v0.3.2, 4 203 options sur 4 209 en portaient un, 1 313 seulement menaient à
une clé réelle. Critère : un segment contigu du chemin, ou une chaîne capturée
par la fermeture (ClosureStrings, v0.4.2), désigne une feuille de config.json.

Usage : python3 check_gmcm_paths.py [chemin/vers/Mods]
"""
import collections, json, os, re, sys

MODS = sys.argv[1] if len(sys.argv) > 1 else \
    "/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS/Mods"
EXPORT = os.path.expanduser(
    "~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe/gmcm-options.json")


def load(path):
    text = open(path, encoding="utf-8-sig", errors="replace").read()
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    text = re.sub(r"(?m)^\s*//.*$", "", text)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def leaf(config, path):
    """La valeur au bout du chemin (clés insensibles à la casse), ou None."""
    node = config
    for key in path:
        if not isinstance(node, dict):
            return None
        match = [k for k in node if k.lower() == key.lower()]
        if not match:
            return None
        node = node[match[0]]
    return None if isinstance(node, (dict, list)) else ("leaf", node)


folders = collections.defaultdict(list)
for root, _, files in os.walk(MODS):
    if "manifest.json" in files and not os.path.basename(root).startswith("."):
        try:
            folders[load(os.path.join(root, "manifest.json")).get("UniqueID", "").lower()].append(root)
        except Exception:
            pass

stats, misses = collections.Counter(), collections.Counter()
for mod in json.load(open(EXPORT))["Mods"]:
    configs = [os.path.join(r, "config.json") for r in folders.get(mod["UniqueID"].lower(), [])
               if os.path.exists(os.path.join(r, "config.json"))]
    if not configs:
        stats["sans config.json"] += 1 * sum(1 for o in mod["Options"] if o.get("ValueType"))
        continue
    try:
        config = load(configs[0])
    except Exception:
        continue
    for option in mod["Options"]:
        if not option.get("ValueType"):
            continue
        path = option.get("AccessPath") or []
        by_path = any(leaf(config, path[s:e]) for s in range(len(path)) for e in range(s + 1, len(path) + 1))
        by_closure = any(leaf(config, [s]) for s in option.get("ClosureStrings") or [])
        if by_path:
            stats["par AccessPath"] += 1
        elif by_closure:
            stats["par ClosureStrings"] += 1
        else:
            stats["introuvable"] += 1
            misses[mod["UniqueID"]] += 1

print(dict(stats))
for uid, n in misses.most_common(15):
    print(f"  {n:4} {uid}")
