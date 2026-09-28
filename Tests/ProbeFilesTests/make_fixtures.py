#!/usr/bin/env python3
"""Extrait les fixtures de ProbeFilesTests des vrais fichiers de la sonde.

Rejouable : `python3 Tests/ProbeFilesTests/make_fixtures.py [dossier_sonde] [sortie] [--harmony-map]`.
Rien n'est écrit à la main : les lignes et les méthodes viennent telles quelles
des fichiers produits par companion/StarHubFR.Probe ; seuls les tableaux `Mods`
de mod-costs.jsonl sont réduits (une ligne réelle pèse ~44 Ko).
"""
import json, os, sys

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
SRC = ARGS[0] if ARGS else os.path.expanduser(
    "~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe")
OUT = ARGS[1] if len(ARGS) > 1 else os.path.join(os.path.dirname(__file__), "Fixtures")
os.makedirs(OUT, exist_ok=True)

PERF = {"palmhacker13.ultrasmooth", "arshia1381.stardropium", "phuicmt.sdvradiance",
        "sinz.speedysolutions", "neoiw.stardewloadingoptimizer"}
PERF_ASM = {"UltraSmooth", "Stardropium", "SDV-Radiance", "SinZational Speedy Solutions",
            "StardewLoadingOptimizer"}
EXTRA_OWNERS = {"Cropgenics.cjb-compat", "MiniMonoModHotfix", "mrbabilo.StarHubFR.Probe.PatchCosts"}
TIMING_SESSIONS = ("2026-09-26T01:38", "2026-09-26T01:53", "2026-09-26T20:30",
                   "2026-09-28T18:56", "2026-09-28T19:21")
COST_SESSIONS = ("2026-09-26T02:33", "2026-09-26T20:30", "2026-09-28T18:56")
INVENTORY_SESSIONS = ("2026-09-28T18:56", "2026-09-28T19:21")
COST_MODS = PERF | {"pathoschild.contentpatcher", "mrbabilo.starhubfr.probe"}

# Carte : méthodes touchant un mod de performance, plus quelques propriétaires secondaires.
m = json.load(open(os.path.join(SRC, "harmony-map.json"), encoding="utf-8"))
kept = [me for me in m["Methods"]
        if me["DeclaringAssembly"] in PERF_ASM
        or any(p["Owner"].lower() in PERF or p["Owner"] in EXTRA_OWNERS for p in me["Patches"])]
m["Methods"] = kept
# La carte des patchs est figée au 2026-09-26 : les mods de performance ont
# quitté le parc depuis, une carte régénérée n'aurait plus aucun chevauchement
# à tester. `--harmony-map` la réécrit exprès.
if "--harmony-map" in sys.argv:
    json.dump(m, open(os.path.join(OUT, "harmony-map.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

def pick(name, sessions, shrink=None):
    lines = [l.rstrip("\n") for l in open(os.path.join(SRC, name), encoding="utf-8")]
    keep = [l for l in lines if json.loads(l)["Session"].startswith(sessions)]
    if shrink:
        keep = [shrink(l) for l in keep]
    truncated = keep[-1][: len(keep[-1]) // 2]   # une ligne réelle coupée net
    open(os.path.join(OUT, name), "w", encoding="utf-8").write("\n".join(keep + [truncated]) + "\n")
    return keep

def shrink_costs(line):
    r = json.loads(line)
    r["Mods"] = [dict(x, Events=x["Events"][:3]) for x in r["Mods"] if x["Mod"].lower() in COST_MODS]
    return json.dumps(r, ensure_ascii=False, separators=(",", ":"))

t = pick("timings.jsonl", TIMING_SESSIONS)
c = pick("mod-costs.jsonl", COST_SESSIONS, shrink_costs)
pick("inventory.jsonl", INVENTORY_SESSIONS)

# Ce que les tests attendent : à comparer aux valeurs écrites dans le plan.
def short(s):
    s = s.split("(")[0]
    if ".." in s:
        head, tail = s.split("..", 1)
        return head.split(".")[-1] + ".." + tail
    return ".".join(s.split(".")[-2:])
owners = lambda me: {p["Owner"].lower() for p in me["Patches"]}
def shared(a, b): return sorted({short(me["Method"]) for me in kept if a in owners(me) and b in owners(me)})
def code(a, asm): return sorted({short(me["Method"]) for me in kept if me["DeclaringAssembly"] == asm and a in owners(me)})
print("mods", len(m["Mods"]), "methods", len(kept), "stage", m["Stage"], "capturedAt", m["CapturedAt"])
print("SD x US", shared("arshia1381.stardropium", "palmhacker13.ultrasmooth"))
print("SLO x US", shared("neoiw.stardewloadingoptimizer", "palmhacker13.ultrasmooth"))
print("SLO x SD", shared("neoiw.stardewloadingoptimizer", "arshia1381.stardropium"))
print("SLO -> SinZ", code("neoiw.stardewloadingoptimizer", "SinZational Speedy Solutions"))
print("SD -> SinZ", code("arshia1381.stardropium", "SinZational Speedy Solutions"))
print("SinZ patches", sorted({short(me["Method"]) for me in kept if "sinz.speedysolutions" in owners(me)}))
vers = {x["UniqueID"]: x["Version"] for x in m["Mods"]}
print("versions", {k: vers.get(k) for k in ["palmhacker13.UltraSmooth", "Arshia1381.Stardropium", "neoiw.StardewLoadingOptimizer", "SinZ.SpeedySolutions", "phuicmt.SDVRadiance"]})
print("timings lines", len(t), "costs lines", len(c))
