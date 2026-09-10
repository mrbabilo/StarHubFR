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

Deux compteurs (`oversized_files`, `oversized_excess_lines`) portent sur la
**taille des fichiers** et non sur un motif dans le texte : ils viennent du
`check_file_length` de l'upstream, la seule de leurs six règles qui nous
manquait — et celle qui aurait crié pendant les 41 jours où le ViewModel a
triplé. Repris avec un écart assumé : leur version ne compte que les fichiers
en dépassement, ce qui ne bouge pas quand un fichier déjà trop gros grossit
encore. Voir le commentaire de `FILE_RULES`.
"""
from __future__ import annotations

import json
import os
import re
import sys
from typing import Callable, Iterator

SOURCE_DIR = "StarHubTH"
BASELINE_PATH = ".standards-baseline.json"
# § convention de taille de fichier — le seuil de l'upstream, repris tel quel.
# Leur plus gros fichier après refactor fait 392 lignes : le seuil est tenable,
# ce n'est pas une cible théorique.
LINE_LIMIT = 400
# Per-file mtime sum, used to skip the 211-file scan when nothing has changed
# since the last run. Lives next to the baseline so a `rm .standards-*` cleans
# both. Recomputed every time the hash drifts.
SOURCE_FRESHNESS_PATH = ".standards-source-freshness"

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


_LINE_COUNTS: dict[str, int] | None = None


def read_source(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def file_line_counts() -> dict[str, int]:
    """Lignes **brutes** par fichier — commentaires compris, contrairement à
    tous les autres compteurs.

    Délibéré : les règles de `RULES` cherchent des violations, et écrire *sur*
    une violation n'en est pas une, d'où `strip_comments`. Ici la question est
    « ce fichier est-il maniable ? », et 3 000 lignes de commentaires se
    parcourent, se scrollent et saturent le type-checker exactement comme
    3 000 lignes de code. C'est aussi le compte que rend `wc -l`, donc celui
    qu'on vérifie à la main sans se demander quelle convention s'applique.

    Mémoïsé pour le processus courant : `--report` relit le détail des gros
    fichiers après `measure()` — sans mémo, la seconde passe repayait le
    parcours des ~211 fichiers que la première venait de faire (revue du
    2026-09-10). Un processus ne voit qu'un état du disque ; le gâchis
    inter-processus, lui, reste couvert par le cache d'empreinte.
    """
    global _LINE_COUNTS
    if _LINE_COUNTS is None:
        counts = {}
        for p in swift_sources():
            with open(p, encoding="utf-8") as handle:
                counts[p] = sum(1 for _ in handle)
        _LINE_COUNTS = counts
    return _LINE_COUNTS


# § convention de taille de fichier. Deux compteurs, parce qu'un seul laisse
# passer la moitié du défaut :
#
#   - `oversized_files` seul ne bouge pas quand un fichier déjà trop gros
#     grossit encore. C'est exactement ce qui est arrivé au ViewModel — 4 296
#     → 11 902 lignes en 41 jours **sans jamais changer de catégorie**. Un
#     cliquet aveugle à ça n'aurait rien empêché.
#   - `oversized_excess_lines` seul ne distingue pas un fichier neuf à 401
#     lignes (+1) d'un dépassement anodin ; et il est le seul à récompenser
#     un découpage, puisqu'il tombe dès qu'un fichier repasse sous le seuil.
#
# Ensemble : le premier interdit d'ouvrir un nouveau fourre-tout, le second
# interdit d'engraisser ceux qui existent.
FILE_RULES: dict[str, Callable[[dict[str, int]], int]] = {
    "oversized_files": lambda c: sum(1 for n in c.values() if n > LINE_LIMIT),
    "oversized_excess_lines": lambda c: sum(
        n - LINE_LIMIT for n in c.values() if n > LINE_LIMIT
    ),
}


def measure(force: bool = False) -> tuple[dict[str, int], dict[str, int]]:
    """Run every ratchet rule over the source tree.

    Cached by an aggregate source-tree fingerprint (newest mtime + per-file
    size). Saves the full ~211-file regex sweep on quiet builds where the user
    touched only assets, Info.plist or Xcode project files. `force=True`
    bypasses the cache (used by `--update` / `--report`).
    """
    cache_path = SOURCE_FRESHNESS_PATH
    counts_path = SOURCE_FRESHNESS_PATH + ".counts"
    info_path = SOURCE_FRESHNESS_PATH + ".info"
    if not force:
        try:
            current_newest, current_sizes = source_fingerprint()
            with open(cache_path, encoding="utf-8") as f:
                cached_newest, cached_sizes_json = f.read().split("\n", 1)
            cached_sizes: dict[str, int] = json.loads(cached_sizes_json)
            if cached_newest == current_newest and cached_sizes == current_sizes:
                # Same source since the last run → same counts and same
                # informationals. Re-read both from the cache instead of
                # re-sweeping 211 files.
                with open(counts_path, encoding="utf-8") as f:
                    cached_counts: dict[str, int] = json.loads(f.read())
                with open(info_path, encoding="utf-8") as f:
                    cached_info: dict[str, int] = json.loads(f.read())
                # ⚠️ L'empreinte ne couvre que les **sources**, pas le jeu de
                # règles. Ajouter une règle sans toucher au Swift rendait donc
                # un relevé d'où elle était absente : `main()` n'itère que sur
                # les clés reçues, la règle neuve n'était ni vérifiée ni
                # signalée comme inconnue — elle sautait en silence, et
                # `build_app.py` passe justement par ce chemin. Comparer les
                # clés attendues referme ça sans fichier supplémentaire.
                if (set(cached_counts) == set(RULES) | set(FILE_RULES)
                        and set(cached_info) == set(INFORMATIONAL)):
                    return cached_counts, cached_info
        except (OSError, ValueError):
            pass  # missing cache, malformed cache → fall through to full measure

    text = "\n".join(strip_comments(read_source(p)) for p in swift_sources())
    counts = {name: rule(text) for name, rule in RULES.items()}
    line_counts = file_line_counts()
    counts.update({name: rule(line_counts) for name, rule in FILE_RULES.items()})
    info = {name: rule(text) for name, rule in INFORMATIONAL.items()}

    # Persist the verdict for next time. Errors here are non-fatal — a failed
    # cache write just means the next run re-measures.
    try:
        current_newest, current_sizes = source_fingerprint()
        with open(cache_path, "w", encoding="utf-8") as f:
            f.write(f"{current_newest}\n{json.dumps(current_sizes, sort_keys=True)}")
        with open(counts_path, "w", encoding="utf-8") as f:
            json.dump(counts, f, sort_keys=True)
        with open(info_path, "w", encoding="utf-8") as f:
            json.dump(info, f, sort_keys=True)
    except OSError:
        pass

    return counts, info


def source_fingerprint() -> tuple[str, dict[str, int]]:
    """Aggregate (newest_mtime, per-file size) over the Swift source tree.

    Cheap: one `os.stat` per file, no reads. Drift between two builds means
    at least one file changed (mtime) or one file was rewritten with the same
    mtime but different content (size) — both invalidate the cache.
    """
    newest: float = 0.0
    sizes: dict[str, int] = {}
    for path in swift_sources():
        st = os.stat(path)
        newest = max(newest, st.st_mtime)
        sizes[path] = st.st_size
    return str(newest), sizes


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
    # `--report` and `--update` want live numbers (the user is asking "what's
    # the state right now?"). The default mode (used by `build_app.py`)
    # benefits from the cache: a no-op build shouldn't re-run 10 regex sweeps.
    force = bool({"--report", "--update"} & args)
    counts, info = measure(force=force)

    if "--report" in args:
        width = max(len(k) for k in list(counts) + list(info))
        for name, value in sorted(counts.items()):
            print(f"  {name:<{width}}  {value}")
        for name, value in sorted(info.items()):
            print(f"  {name:<{width}}  {value}  (informatif)")
        # Un compte de fichiers trop gros ne dit pas *lesquels*, et c'est la
        # seule chose dont le refactor a besoin pour choisir sa prochaine
        # cible. Les nommer ici évite de refaire un `wc -l | sort` à la main.
        oversized = sorted(((n, p) for p, n in file_line_counts().items()
                            if n > LINE_LIMIT), reverse=True)
        if oversized:
            print(f"\n  Les plus gros fichiers (> {LINE_LIMIT} lignes) :")
            for count, path in oversized[:10]:
                print(f"    {count:>6}  (+{count - LINE_LIMIT})  {path}")
            if len(oversized) > 10:
                print(f"    … et {len(oversized) - 10} autres")
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
