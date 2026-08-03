#!/usr/bin/env python3
"""Cliquet anti-régression sur les conventions Swift du projet.

Ce n'est **pas** une barrière de qualité : le code viole massivement ces
conventions aujourd'hui — 1361 `vm`, 761 appels à `L(_:)`, 174 `try?`, 117
`DispatchQueue` — et une barrière serait rouge dès le premier jour, donc
désactivée dans la semaine (lancer `--report` pour l'état courant). C'est un
cliquet : chaque compteur est comparé à une base de référence commitée, et seule
une **augmentation** échoue. Le refactor fait baisser les compteurs ; la base
est resserrée d'autant, et ne peut plus remonter.

    python3 check_standards.py            # vérifie (utilisé par build_app.py)
    python3 check_standards.py --update   # resserre la base après une baisse
    python3 check_standards.py --report    # affiche les compteurs sans verdict

Faire baisser un compteur est le travail ; le faire monter demande un
`--update` explicite, visible dans le diff — pas un contournement silencieux.

Les règles viennent de `docs/SWIFT_STANDARDS.md` de l'upstream, elles-mêmes une
compression des Swift API Design Guidelines. Voir `docs/REFACTORING.md` pour ce
qu'on en retient et ce qu'on écarte.
"""
from __future__ import annotations

import json
import os
import re
import sys
from typing import Callable, Iterator

SOURCE_DIR = "StarHubTH"
BASELINE_PATH = ".standards-baseline.json"

# Ces `.shared` sont ceux d'Apple, pas les nôtres : les compter mêlerait une
# dette qu'on peut rembourser à une convention de framework qu'on ne changera
# pas. Ils ont leur propre compteur, informatif.
FRAMEWORK_SINGLETONS = {
    "NSWorkspace", "URLSession", "FileManager", "NSAppleEventManager",
    "UserDefaults", "NotificationCenter", "NSApplication", "NSPasteboard",
    "ProcessInfo", "Bundle",
}


def strip_comments(source: str) -> str:
    """Retire les commentaires de ligne, pour qu'écrire *sur* une violation
    n'en soit pas une. Les blocs `/* */` ne sont pas traités : ils sont rares
    ici, et le cliquet ne demande pas l'exactitude — il demande d'être
    déterministe."""
    out: list[str] = []
    for line in source.splitlines():
        if line.lstrip().startswith("//"):
            continue
        out.append(line)
    return "\n".join(out)


def swift_sources() -> Iterator[str]:
    for root, _dirs, files in os.walk(SOURCE_DIR):
        for name in sorted(files):
            if name.endswith(".swift"):
                yield os.path.join(root, name)


def count_shared(text: str) -> tuple[int, int]:
    """Sépare nos singletons de ceux des frameworks."""
    ours: int = 0
    framework: int = 0
    for owner in re.findall(r"\b([A-Z]\w*)\.shared\b", text):
        if owner in FRAMEWORK_SINGLETONS:
            framework += 1
        else:
            ours += 1
    return ours, framework


RULES: dict[str, Callable[[str], int]] = {
    # §1.4 — abréviations : `vm` est l'abréviation la plus répandue du dépôt.
    "abbreviation_vm": lambda t: len(re.findall(r"\bvm\b", t)),
    # §1.4 — `L(_:)`, une méthode d'une lettre sur le chemin le plus fréquenté.
    # ⚠️ Ce compteur ne voit **que** les appels nus `L(...)`. La forme dominante
    # dans les vues est `vm.L(...)`, exclue ici parce que la négation `(?<![\w.])`
    # sert d'abord à écarter `URL(`, `HTML(`, `XMLL(`… Ne pas lire ce nombre
    # comme « le nombre de sites d'appel de L » : il en sous-estime le total d'un
    # ordre de grandeur. Comme cliquet il reste valable — il est déterministe et
    # ne peut pas monter en silence.
    "bare_L_calls": lambda t: len(re.findall(r"(?<![\w.])L\(", t)),
    # La forme réelle des vues, comptée à part pour que le total soit lisible.
    "vm_dot_L_calls": lambda t: len(re.findall(r"\bvm\.L\(", t)),
    # §1.1 — pas de préfixe `get` sur un accesseur.
    "get_prefixed_funcs": lambda t: len(re.findall(r"\bfunc get[A-Z]", t)),
    # §2.2 — une classe non `final` qui n'est pas conçue pour l'héritage.
    "non_final_classes": lambda t: len(
        [m for m in re.findall(r"^[ \t]*(.*?)\bclass\s+[A-Z]", t, re.M)
         if "final" not in m and "extension" not in m]
    ),
    # §7.1 — `try?` avale la cause de l'échec.
    "try_optional": lambda t: len(re.findall(r"\btry\?", t)),
    # §7.3 — `print` est invisible dans une app livrée.
    "print_calls": lambda t: len(re.findall(r"(?<![\w.])print\(", t)),
    # §8 — une propriété publiée que toute vue peut muter n'a pas de propriétaire.
    "published_without_private_set": lambda t: (
        len(re.findall(r"@Published\b", t))
        - len(re.findall(r"@Published\s+private\(set\)", t))
    ),
    # §6.1 — `DispatchQueue` là où `async`/`await` suffirait.
    "dispatch_queue": lambda t: len(re.findall(r"\bDispatchQueue\b", t)),
    # §4.1 — nos propres singletons atteints depuis un site d'appel.
    "our_shared_singletons": lambda t: count_shared(t)[0],
}

# Compté et affiché, jamais bloquant : ce sont les singletons d'Apple.
INFORMATIONAL: dict[str, Callable[[str], int]] = {
    "framework_shared": lambda t: count_shared(t)[1],
}


def measure() -> tuple[dict[str, int], dict[str, int]]:
    text = "\n".join(strip_comments(open(p, encoding="utf-8").read())
                     for p in swift_sources())
    counts = {name: rule(text) for name, rule in RULES.items()}
    info = {name: rule(text) for name, rule in INFORMATIONAL.items()}
    return counts, info


def load_baseline() -> dict[str, int] | None:
    if not os.path.exists(BASELINE_PATH):
        return None
    with open(BASELINE_PATH, encoding="utf-8") as f:
        loaded: dict[str, int] = json.load(f)
    return loaded


def save_baseline(counts: dict[str, int]) -> None:
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(counts, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = set(sys.argv[1:])
    counts, info = measure()

    if "--report" in args:
        width = max(len(k) for k in list(counts) + list(info))
        for name, value in sorted(counts.items()):
            print(f"  {name:<{width}}  {value}")
        for name, value in sorted(info.items()):
            print(f"  {name:<{width}}  {value}  (informatif)")
        return 0

    if "--update" in args:
        save_baseline(counts)
        print(f"[INFO] Base de référence écrite dans {BASELINE_PATH}.")
        return 0

    baseline = load_baseline()
    if baseline is None:
        print(f"[ERROR] {BASELINE_PATH} absent — lancer `--update` une fois pour l'établir.")
        return 1

    regressions: list[tuple[str, int, int]] = []
    improvements: list[tuple[str, int, int]] = []
    unknown: list[str] = []
    for name, value in sorted(counts.items()):
        if name not in baseline:
            unknown.append(name)
        elif value > baseline[name]:
            regressions.append((name, baseline[name], value))
        elif value < baseline[name]:
            improvements.append((name, baseline[name], value))

    for name in unknown:
        print(f"[ERROR] Règle « {name} » absente de la base — lancer `--update`.")

    for name, was, now in regressions:
        print(f"[ERROR] {name} : {was} → {now} (+{now - was}) — nouvelle violation.")

    for name, was, now in improvements:
        print(f"[INFO]  {name} : {was} → {now} (−{was - now}) — resserrer avec `--update`.")

    if regressions or unknown:
        print("[ERROR] Le cliquet des conventions a reculé. Corriger, ou "
              "`python3 check_standards.py --update` si l'ajout est délibéré.")
        return 1

    print("[SUCCESS] Conventions : aucune violation nouvelle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
