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

S'y ajoute un compteur **par fichier** (clés `file:<chemin>`) pour chaque
fichier au-dessus du seuil. Voir le commentaire de `FILE_PREFIX` : les deux
agrégats se compensent entre fichiers, celui-ci ne se compense pas.
"""
from __future__ import annotations

import hashlib
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


# ─── Le lot `@Observable` (chantier A, 2026-09-11) ───────────────────────────
# Trois compteurs remplacent `published_without_private_set` : le mot-clé
# `@Published` a disparu des quatre classes du lot, et compter un mot-clé
# absent mesure 0 par construction — le cliquet applaudirait la disparition de
# la règle qu'il protège (cadrage §5).
LOT_FILES = (
    "StarHubTH/StarHubTHViewModel.swift",
    "StarHubTH/Stores/GameEnvironmentStore.swift",
    "StarHubTH/Stores/NexusMetadataStore.swift",
    "StarHubTH/Stores/SavesStore.swift",
    "StarHubTH/Stores/LogStore.swift",
    "StarHubTH/Stores/SmapiHealthStore.swift",
    "StarHubTH/Stores/ErrorHistoryStore.swift",
    "StarHubTH/Stores/DiscoveryStore.swift",
    "StarHubTH/Stores/MaintenanceStore.swift",
    "StarHubTH/SaveManager.swift",
)
# Les instances Combine que le VM peut lire dans un corps calculé — le défaut
# du cas 4 (un `@Observable` lisant un `ObservableObject` perd le suivi en
# silence). `localization` en est VOLONTAIREMENT absente : les lectures
# `localization.L(...)` des libellés sont légitimes (le store est observé par
# les vues elles-mêmes), et les compter verrouillerait un faux défaut.
COMBINE_INSTANCES = ("keybindScanService", "smapiInstaller", "bisection", "modList")

# ⚠️ Le reste de la ligne est analysé, pas filtré par le motif : une stockée
# peut n'avoir **ni** `=` **ni** `{` (`var x: T?`, dont la valeur par défaut
# est `nil`). Le premier jet exigeait l'un des deux et manquait ces
# propriétés-là — trouvé par la vérification à la main exigée avant de poser
# la base, sur `keybindReport`.
_VAR_DECL = re.compile(
    r"^\s*(?:@\w+\s+)*((?:private\(set\) )?)"
    r"(?:private |public |fileprivate )?var (\w+)\b(.*)$")


def class_members_with_lines(path: str) -> list[tuple[str, bool, bool, int]]:
    """Les `var` de la classe principale : (nom, est_stockée, private_set, ligne).

    Profondeur de classe 1, types imbriqués exclus, commentaires strippés.
    « Stockée » = déclarée avec `=`, ou avec une accolade qui porte des
    observateurs (`didSet`/`willSet`) — dix propriétés du ViewModel sont dans
    ce cas. Trois décomptes à la main ont raté cette distinction (21, 25, 34) :
    le parseur est la seule mesure qui fasse foi, et il a été vérifié contre
    une lecture du fichier avant que la base ne soit posée.
    """
    lines = strip_comments(read_source(path)).splitlines()
    out: list[tuple[str, bool, bool, int]] = []
    depth = 0
    inside = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if not inside:
            if re.match(r"^\s*(?:@\w+\s+)*(?:final )?class \w+", line):
                inside = True
                depth = line.count("{") - line.count("}")
            i += 1
            continue
        if depth == 1 and re.match(
                r"^\s*(?:@\w+\s+)*(?:final )?(?:private |public )?"
                r"(?:struct|enum|class|extension)\s", line):
            d = line.count("{") - line.count("}")
            i += 1
            while d > 0 and i < len(lines):
                d += lines[i].count("{") - lines[i].count("}")
                i += 1
            continue
        m = _VAR_DECL.match(line) if depth == 1 else None
        if m:
            pset, name, rest = bool(m.group(1)), m.group(2), m.group(3).rstrip()
            # Ce qui décide est l'ordre de `=` et `{` — un corps peut tenir sur
            # la même ligne (`var x: Int { healthIssues.count }`), et une
            # stockée peut s'initialiser par une closure (`var x = { … }()`).
            eq, brace = rest.find("="), rest.find("{")
            if eq != -1 and (brace == -1 or eq < brace):
                stored = True                      # `var x = …` / `var x: T = …`
            elif brace != -1:                      # corps : calculée, sauf
                lookahead = " ".join(lines[i:i + 3])   # observateurs
                stored = bool(re.search(r"\b(didSet|willSet)\b", lookahead))
            else:
                stored = True                      # `var x: T?` — défaut nil
            out.append((name, stored, pset, i + 1))
        depth += line.count("{") - line.count("}")
        i += 1
    return out


def _computed_bodies(path: str) -> list[tuple[int, str]]:
    """Le corps de chaque propriété calculée, délimité par ses accolades.

    ⚠️ Deux défauts ont vécu ici le 2026-09-11, tous deux rendant **0** — ce
    qui ressemblait à un succès. Les éviter en modifiant cette fonction :

    1. Les lignes viennent de la source **strippée**, comme celles que rend
       `class_members_with_lines`. Découper la source brute avec ces
       numéros-là décalait chaque fenêtre de la hauteur des commentaires
       (3 949 lignes sur le ViewModel) : le relevé ne décrivait plus aucune
       propriété. Garder les deux fonctions sur la même source.
    2. La fenêtre s'arrêtait au `var` suivant, donc elle avalait les `func`
       intercalées. `scopingInputs` héritait ainsi de `toggleAllMods` et de
       son `modList.filters` — un faux positif, mais surtout un **masque** :
       une vraie façade ajoutée dans la même fenêtre n'aurait rien incrémenté,
       le compteur valant déjà 1 pour ce corps. D'où le comptage d'accolades,
       qui donne le corps exact."""
    lines = strip_comments(read_source(path)).splitlines()
    bodies = []
    for _name, stored, _p, ln in class_members_with_lines(path):
        if stored:
            continue
        depth, body, started = 0, [], False
        for line in lines[ln - 1:]:
            body.append(line)
            depth += line.count("{") - line.count("}")
            if line.count("{"):
                started = True
            if started and depth <= 0:
                break
        bodies.append((ln, "\n".join(body)))
    return bodies


def _rule_vm_stored_state(_: str) -> int:
    return sum(1 for _n, stored, _p, _l in
               class_members_with_lines("StarHubTH/StarHubTHViewModel.swift")
               if stored)


def _rule_vm_facades_to_combine(_: str) -> int:
    path = "StarHubTH/StarHubTHViewModel.swift"
    return sum(any(re.search(rf"\b{inst}\.\w+", body) for inst in COMBINE_INSTANCES)
               for _ln, body in _computed_bodies(path))


def _rule_observable_without_private_set(_: str) -> int:
    return sum(1 for path in LOT_FILES
               for _n, stored, pset, _l in class_members_with_lines(path)
               if stored and not pset)


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
    # §8 — un état que toute vue peut muter n'a pas de propriétaire. Porte la
    # règle de `published_without_private_set`, retirée avec le mot-clé
    # `@Published` que le lot `@Observable` a fait disparaître : le compteur
    # d'origine mesurerait désormais 0 par construction.
    "observable_stored_without_private_set": _rule_observable_without_private_set,
    # La phase « vider le ViewModel » (docs/refactoring-vider-le-viewmodel.md)
    # se mesure ici : l'état stocké du VM ne peut que baisser. Une façade de
    # lecture — autorisée depuis que le suivi la traverse — ne le fait pas
    # monter.
    "viewmodel_stored_state": _rule_vm_stored_state,
    # Le seul angle mort silencieux du chantier : une façade du VM qui délègue
    # à un objet resté en Combine perd le suivi sans erreur ni plantage. Doit
    # rester à 0. ⚠️ **Pas** « zéro ObservableObject » : cinq subsistent
    # volontairement (cadrage §3).
    # ⚠️ Portée réelle, mesurée le 2026-09-11 — ce 0 ne dit pas « aucune façade
    # n'existe », il dit « aucune propriété calculée du VM n'en est une » :
    #  • la règle ne balaie que des **propriétés calculées** (30, corps exact
    #    par comptage d'accolades). Une *méthode* façade échapperait au relevé.
    #    Six corps de fonction citent une de ces instances (`installSmapi`,
    #    `toggleAllMods`…) : tous des **verbes**, et le cas 4 ne mord que sur
    #    une lecture rendue par un `body`.
    #  • `localization` est hors de COMBINE_INSTANCES exprès : les 45 vues qui
    #    traduisent le reçoivent en `@ObservedObject` et l'observent donc
    #    directement (cas 1). Aucune ne passe par le VM — `vm_dot_L_calls` = 0.
    # Refaire ces deux mesures avant de conclure quoi que ce soit d'un 0 futur.
    # Le 0 lui-même est vérifié par sabotage : ajouter une propriété calculée
    # lisant `modList.filters` fait monter le compteur à 1.
    "viewmodel_facades_to_combine": _rule_vm_facades_to_combine,
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

# § le même défaut, un cran plus loin : **les deux agrégats se compensent entre
# fichiers**. Mesuré le 2026-09-11 sur ce dépôt — 120 lignes ajoutées au
# ViewModel et 120 retirées de `ModListView` sortent en `[SUCCESS]`, code 0,
# sans un mot. La marge silencieuse ainsi disponible valait **~16 000 lignes**
# (25 804 d'excès total, dont 9 812 au seul ViewModel) : tout ce que les autres
# fichiers peuvent encore perdre, le God module peut le prendre. Et ce n'est pas
# un cas d'école — P8 (découpage des vues) va justement faire fondre
# `ModListView` de ~1 950 lignes d'excès.
#
# D'où un compteur **par fichier** pour chacun de ceux qui dépassent : la
# compensation devient impossible, et la baseline nomme dans le diff le fichier
# qui a grossi, au lieu d'un total où personne ne le retrouve. C'est ce que
# `docs/REFACTORING.md` §1 réclamait — « y inscrire le nombre de lignes du
# ViewModel est le seul mécanisme qui rende F1-T2 opposable ».
#
# Le bruit ajouté est quasi nul : sans compensation, faire grossir un fichier
# faisait **déjà** monter `oversized_excess_lines` et échouer le cliquet. Ces
# clés ne mordent donc que là où l'agrégat se laissait berner.
#
# Un fichier qui repasse sous le seuil perd sa clé : c'est voulu, il sort du
# périmètre de la règle et `oversized_files` enregistre le gain.
FILE_PREFIX = "file:"


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
                cached_rules, cached_newest, cached_sizes_json = f.read().split("\n", 2)
            cached_sizes: dict[str, int] = json.loads(cached_sizes_json)
            if (cached_rules == ruleset_fingerprint()
                    and cached_newest == current_newest
                    and cached_sizes == current_sizes):
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
                #
                # Les clés `file:` sont exclues de cette comparaison : elles
                # dérivent des **sources**, pas du jeu de règles, et l'empreinte
                # ci-dessus couvre déjà tout changement de source. Les y inclure
                # rendrait le cache inutilisable dès qu'un fichier franchit le
                # seuil — l'empreinte a alors déjà invalidé l'entrée.
                cached_rule_keys = {k for k in cached_counts
                                    if not k.startswith(FILE_PREFIX)}
                if (cached_rule_keys == set(RULES) | set(FILE_RULES)
                        and set(cached_info) == set(INFORMATIONAL)):
                    return cached_counts, cached_info
        except (OSError, ValueError):
            pass  # missing cache, malformed cache → fall through to full measure

    text = "\n".join(strip_comments(read_source(p)) for p in swift_sources())
    counts = {name: rule(text) for name, rule in RULES.items()}
    line_counts = file_line_counts()
    counts.update({name: rule(line_counts) for name, rule in FILE_RULES.items()})
    counts.update({FILE_PREFIX + path: n for path, n in line_counts.items()
                   if n > LINE_LIMIT})
    info = {name: rule(text) for name, rule in INFORMATIONAL.items()}

    # Persist the verdict for next time. Errors here are non-fatal — a failed
    # cache write just means the next run re-measures.
    try:
        current_newest, current_sizes = source_fingerprint()
        with open(cache_path, "w", encoding="utf-8") as f:
            f.write(f"{ruleset_fingerprint()}\n{current_newest}\n"
                    f"{json.dumps(current_sizes, sort_keys=True)}")
        with open(counts_path, "w", encoding="utf-8") as f:
            json.dump(counts, f, sort_keys=True)
        with open(info_path, "w", encoding="utf-8") as f:
            json.dump(info, f, sort_keys=True)
    except OSError:
        pass

    return counts, info


def ruleset_fingerprint() -> str:
    """Empreinte du script lui-même, jointe au cache.

    L'empreinte des sources ne couvre que le Swift : modifier le jeu de règles
    sans toucher une ligne de Swift rendait un verdict caché d'où la règle
    neuve était absente — `build_app.py` passe justement par ce chemin. Le
    garde précédent comparait les *noms* des règles, ce qui ne voit ni un corps
    de règle réécrit, ni une clé dérivée des sources comme `file:`. Hacher le
    fichier voit les deux, pour une lecture de 400 lignes.
    """
    try:
        with open(__file__, "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()
    except OSError:
        return "unknown"  # cache alors toujours invalide : sûr, pas silencieux


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
        # Les clés `file:` sont tenues hors de ce listing : elles sont une par
        # fichier en dépassement (37 au 2026-09-11), elles noieraient les dix
        # compteurs de conventions — et la section ci-dessous les rend déjà,
        # triées et avec leur écart au seuil.
        rules_only = {k: v for k, v in counts.items()
                      if not k.startswith(FILE_PREFIX)}
        width = max(len(k) for k in list(rules_only) + list(info))
        for name, value in sorted(rules_only.items()):
            print(f"  {name:<{width}}  {value}")
        for name, value in sorted(info.items()):
            print(f"  {name:<{width}}  {value}  (informatif)")
        # Un compte de fichiers trop gros ne dit pas *lesquels*, et c'est la
        # seule chose dont le refactor a besoin pour choisir sa prochaine
        # cible. Les nommer ici évite de refaire un `wc -l | sort` à la main.
        oversized = sorted(((n, p) for p, n in file_line_counts().items()
                            if n > LINE_LIMIT), reverse=True)
        if oversized:
            # L'écart à la **base** compte autant que l'écart au seuil : c'est
            # lui qui dit si le fichier a bougé depuis le dernier verrou.
            baseline = load_baseline() or {}
            print(f"\n  Les plus gros fichiers (> {LINE_LIMIT} lignes) :")
            for count, path in oversized[:10]:
                was = baseline.get(FILE_PREFIX + path)
                drift = "" if was is None or was == count else f"  [{count - was:+d} / base]"
                print(f"    {count:>6}  (+{count - LINE_LIMIT})  {path}{drift}")
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

    # Un fichier verrouillé qui n'est plus mesuré est repassé sous le seuil,
    # a été découpé, renommé ou supprimé — le gain que ce cliquet cherche. Il
    # ne se voit nulle part ailleurs : `main()` n'itère que sur les compteurs
    # relevés, donc la clé resterait dans la base sans que rien ne le dise.
    # ⚠️ Le message ne dit **pas** « repasse sous le seuil » : d'ici, les trois
    # causes sont indiscernables, et P8 (découpage des vues) renomme et déplace
    # des fichiers par construction. Affirmer la mauvaise des trois ferait
    # consigner une mesure fausse dans `docs/REFACTORING.md`.
    for name in sorted(baseline):
        if name.startswith(FILE_PREFIX) and name not in counts:
            print(f"[INFO]  {name[len(FILE_PREFIX):]} : plus mesuré — repassé "
                  f"sous {LINE_LIMIT} lignes, renommé ou supprimé. "
                  f"Resserrer avec `--update`.")

    for name in unknown:
        if name.startswith(FILE_PREFIX):
            path = name[len(FILE_PREFIX):]
            # Indiscernable d'ici : un fichier neuf au-dessus du seuil, ou une
            # base pas encore à jour. Le message ne tranche donc pas — il dit
            # ce qui est mesuré, et `--update` assume dans le diff.
            print(f"[ERROR] {path} : {counts[name]} lignes, au-dessus de "
                  f"{LINE_LIMIT} et absent de la base — `--update` pour l'assumer.")
        else:
            print(f"[ERROR] Règle « {name} » absente de la base — lancer `--update`.")

    for name, was, now in regressions:
        if name.startswith(FILE_PREFIX):
            path = name[len(FILE_PREFIX):]
            print(f"[ERROR] {path} : {was} → {now} (+{now - was} lignes) — "
                  f"un fichier déjà trop gros grossit encore.")
        else:
            print(f"[ERROR] {name} : {was} → {now} (+{now - was}) — nouvelle violation.")

    for name, was, now in improvements:
        if name.startswith(FILE_PREFIX):
            path = name[len(FILE_PREFIX):]
            print(f"[INFO]  {path} : {was} → {now} (−{was - now} lignes) — "
                  f"resserrer avec `--update`.")
        else:
            print(f"[INFO]  {name} : {was} → {now} (−{was - now}) — resserrer avec `--update`.")

    if regressions or unknown:
        print("[ERROR] Le cliquet des conventions a reculé. Corriger, ou "
              "`python3 check_standards.py --update` si l'ajout est délibéré.")
        return 1

    print("[SUCCESS] Conventions : aucune violation nouvelle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
