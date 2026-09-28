#!/usr/bin/env python3
"""Contrôle des fichiers d'inventaire de la sonde StarHubFR (D4-T4, v0.4.12).

Vérifie, pour la dernière session qui a une ligne `launch` :
- la ligne `launch` : mods non vides, chaque empreinte non nulle a son contenu
  dans configs/, et ce contenu porte bien cette empreinte ;
- les lignes `configChanged` : `ChangedAt` <= `At`, contenus présents ;
- les lignes de timings.jsonl de la session : `MenuTicks` entier,
  0 <= MenuTicks <= Tick.Count ;
- chaque fichier de configs/ porte l'empreinte de son nom (pas de contenu
  tronqué sous un nom d'empreinte).

Imprime la distribution de MenuTicks / Tick.Count (minutes en partie), qui
calibre le seuil du plan 3. Sortie 0 si tout tient, 1 sinon.
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime

DEFAULT_DIR = os.path.expanduser("~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe")


def sha256(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def read_jsonl(path):
    rows, bad = [], 0
    if not os.path.exists(path):
        return rows, bad
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1
    return rows, bad


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default=DEFAULT_DIR)
    args = parser.parse_args()
    problems = []

    inventory, bad = read_jsonl(os.path.join(args.dir, "inventory.jsonl"))
    if bad:
        problems.append(f"inventory.jsonl : {bad} ligne(s) illisible(s)")
    launches = [r for r in inventory if r.get("Kind") == "launch"]
    if not launches:
        print("ÉCHEC : aucune ligne `launch` dans inventory.jsonl (sonde < 0.4.12 ?)")
        return 1
    launch = launches[-1]
    session = launch.get("Session")
    configs_dir = os.path.join(args.dir, "configs")

    mods = launch.get("Mods") or []
    if not mods:
        problems.append("launch : liste de mods vide")
    with_config = [m for m in mods if m.get("Config")]
    for mod in with_config:
        path = os.path.join(configs_dir, mod["Config"] + ".json")
        if not os.path.exists(path):
            problems.append(f"launch : contenu absent pour {mod.get('Id')} ({mod['Config'][:12]}…)")

    changes = [r for r in inventory if r.get("Kind") == "configChanged" and r.get("Session") == session]
    per_mod = {}
    for change in changes:
        for mod_id in (change.get("Configs") or {}):
            per_mod[mod_id] = per_mod.get(mod_id, 0) + 1
    for change in changes:
        at, changed_at = change.get("At"), change.get("ChangedAt")
        if not changed_at or changed_at > at:
            problems.append(f"configChanged à {at} : ChangedAt absent ou postérieur ({changed_at})")
        for mod_id, sha in (change.get("Configs") or {}).items():
            if sha and not os.path.exists(os.path.join(configs_dir, sha + ".json")):
                problems.append(f"configChanged : contenu absent pour {mod_id}")

    if os.path.isdir(configs_dir):
        for name in os.listdir(configs_dir):
            if not name.endswith(".json"):
                continue
            if sha256(os.path.join(configs_dir, name)) != name[:-5]:
                problems.append(f"configs/{name} : le contenu ne porte pas l'empreinte de son nom")

    timings, bad_t = read_jsonl(os.path.join(args.dir, "timings.jsonl"))
    minutes = [r for r in timings if r.get("Session") == session]
    ratios = []
    for minute in minutes:
        menu = minute.get("MenuTicks")
        ticks = (minute.get("Tick") or {}).get("Count")
        if not isinstance(menu, int):
            problems.append(f"timings {minute.get('At')} : MenuTicks absent ou non entier")
            continue
        if ticks is not None and not (0 <= menu <= ticks):
            problems.append(f"timings {minute.get('At')} : MenuTicks {menu} hors de [0, {ticks}]")
        if minute.get("Location") and ticks:
            ratios.append(menu / ticks)

    print(f"Session {session} : {len(mods)} mods, {len(with_config)} config.json, "
          f"{len(changes)} changement(s) de réglage, {len(minutes)} minute(s).")
    if per_mod:
        # Un mod qui change à chaque minute range un état dans sa config :
        # ses « changements » ne sont pas des réglages (plan 3, réglages volatils).
        print("Changements de réglage par mod : "
              + ", ".join(f"{m} ×{n}" for m, n in sorted(per_mod.items(), key=lambda kv: -kv[1])))
    if ratios:
        ratios.sort()
        def q(p):
            return ratios[min(len(ratios) - 1, int(p * len(ratios)))]
        print("MenuTicks / Tick.Count, minutes en partie : "
              f"min {ratios[0]:.2f} · Q1 {q(0.25):.2f} · médiane {q(0.5):.2f} · Q3 {q(0.75):.2f} · max {ratios[-1]:.2f} "
              f"· > 0,5 : {sum(r > 0.5 for r in ratios)}/{len(ratios)}")
    if problems:
        print(f"ÉCHEC : {len(problems)} manquement(s)")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
