#!/usr/bin/env python3
"""Extrait pour ModImpactSampleTests une session réelle d'au moins 5 minutes
comparables (2026-09-29 19:50, la seule avec des patches mesurés).

Rejouable : `python3 Tests/ProbeFilesTests/make_impact_fixture.py [dossier_sonde]`.
Rien n'est écrit à la main : lignes réelles, seuls les tableaux `Mods` de
mod-costs.jsonl sont réduits aux mods de MODS (une ligne réelle pèse ~44 Ko)
et leurs `Events` vidés.
"""
import json, os, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe")
OUT = os.path.join(os.path.dirname(__file__), "Fixtures")
SESSION = "2026-09-29T19:50"
MODS = {"pathoschild.contentpatcher", "cropgenics", "spacechase0.spacecore",
        "esca.farmtypemanager", "hedgehogtechnologies.autoforager", "mrbabilo.starhubfr.probe"}

def pick(name, out, shrink=None):
    keep = []
    for line in open(os.path.join(SRC, name), encoding="utf-8"):
        line = line.rstrip("\n")
        if line and json.loads(line).get("Session", "").startswith(SESSION):
            keep.append(shrink(line) if shrink else line)
    open(os.path.join(OUT, out), "w", encoding="utf-8").write("\n".join(keep) + "\n")
    return len(keep)

def shrink_costs(line):
    r = json.loads(line)
    r["Mods"] = [dict(m, Events=[]) for m in r["Mods"] if m["Mod"].lower() in MODS]
    return json.dumps(r, ensure_ascii=False, separators=(",", ":"))

print("timings", pick("timings.jsonl", "impact-timings.jsonl"))
print("costs", pick("mod-costs.jsonl", "impact-mod-costs.jsonl", shrink_costs))
print("inventory", pick("inventory.jsonl", "impact-inventory.jsonl"))
