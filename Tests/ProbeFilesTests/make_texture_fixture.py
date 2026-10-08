#!/usr/bin/env python3
"""Extrait pour ModImpactTextureTests une session réelle avec les textures
relevées (2026-10-07 11:06, sonde 0.9.21, `MeasureTextures` allumé).

Rejouable : `python3 Tests/ProbeFilesTests/make_texture_fixture.py [dossier_sonde]`.
Lignes réelles ; seuls les tableaux `Mods` de mod-costs.jsonl sont réduits aux
mods de MODS, `Events` vidés. L'inventaire existe en deux exemplaires : le
réel (0.9.21, attribution d'avant `OnBehalfOf` et par éditeur, que l'app
doit écarter) et le même avec la seule version de la sonde montée à 0.9.24 — aucune session réelle
de cette version n'existait quand la fixture a été écrite.
"""
import json, os, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe")
OUT = os.path.join(os.path.dirname(__file__), "Fixtures")
SESSION = "2026-10-07T11:06"
MODS = {"pathoschild.contentpatcher", "cropgenics", "spacechase0.spacecore",
        "becks723.fontsettings", "mrbabilo.starhubfr.probe"}

def lines(name):
    for line in open(os.path.join(SRC, name), encoding="utf-8"):
        line = line.rstrip("\n")
        if line and json.loads(line).get("Session", "").startswith(SESSION):
            yield line

def write(out, rows):
    open(os.path.join(OUT, out), "w", encoding="utf-8").write("\n".join(rows) + "\n")
    print(out, len(rows))

def shrink_costs(line):
    r = json.loads(line)
    r["Mods"] = [dict(m, Events=[]) for m in r["Mods"] if m["Mod"].lower() in MODS]
    return json.dumps(r, ensure_ascii=False, separators=(",", ":"))

def bump_probe(line):
    return re.sub(r'("Id":"mrbabilo\.StarHubFR\.Probe","Version":")[^"]*"', r'\g<1>0.9.24"', line)

write("texture-timings.jsonl", list(lines("timings.jsonl")))
write("texture-mod-costs.jsonl", [shrink_costs(l) for l in lines("mod-costs.jsonl")])
inventory = list(lines("inventory.jsonl"))
write("texture-inventory-real.jsonl", inventory)
bumped = [bump_probe(l) for l in inventory]
assert bumped != inventory, "version de la sonde introuvable dans l'inventaire"
write("texture-inventory-0.9.24.jsonl", bumped)
