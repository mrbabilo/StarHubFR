#!/usr/bin/env python3
"""D5-B tâche 0 : spans de lancement et de chargement lus dans des journaux SMAPI.

Usage : python3 companion/StarHubFR.Probe/tools/load_spans.py journal1.txt journal2.txt …
Lignes repères (SMAPI 4.5.2, jeu 1.6.15, vérifiées le 2026-09-29) :
  lancement  : première ligne horodatée  →  "Type 'help' for help"
  chargement : "set to 'loadingMode (6)'" →  "Context: loaded save '"
Résolution : la seconde (horodatage du journal).
"""
import re, statistics, sys

STAMP = re.compile(r"^\[(\d\d):(\d\d):(\d\d) ")


def seconds(line):
    m = STAMP.match(line)
    return int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3]) if m else None


def spans(path):
    first = help_ = load_start = loaded = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            t = seconds(line)
            if t is None:
                continue
            if first is None:
                first = t
            if help_ is None and "Type 'help' for help" in line:
                help_ = t
            if load_start is None and "set to 'loadingMode (6)'" in line:
                load_start = t
            if loaded is None and load_start is not None and "Context: loaded save '" in line:
                loaded = t

    def d(a, b):
        if a is None or b is None:
            return None
        return (b - a) % 86400  # passage de minuit

    return d(first, help_), d(load_start, loaded)


rows = [(p, *spans(p)) for p in sys.argv[1:]]
for p, launch, load in rows:
    print(f"{p}\tlancement {launch} s\tchargement {load} s")
for i, name in ((1, "lancement"), (2, "chargement")):
    values = [r[i] for r in rows if r[i] is not None]
    if len(values) >= 2:
        med = statistics.median(values)
        spread = (max(values) - min(values)) / med * 100
        print(f"{name}: médiane {med} s, écart max {spread:.1f} %")
