#!/usr/bin/env python3
"""Contrôle les sources externes dont StarHubFR dépend.

Le pendant de `check_standards.py` pour ce qui vit **hors** du dépôt : les API
qu'on interroge, les dumps qu'on télécharge, les projets dont on a repris du
code ou des idées. Même patron — un relevé comparé à `.sources-baseline.json`,
un `--update` explicite pour assumer un changement, visible dans le diff.

La différence avec le cliquet des conventions : ici, un écart n'est pas une
faute. C'est un **signal**. Une nouvelle version de SMAPI n'est pas un bug ;
c'est une chose à aller regarder. Le script dit ce qui a bougé, pas ce qui est
cassé.

Trois familles de sondes :

- `repo`      — dépôt GitHub : dernière release et date du dernier commit.
- `http`      — une URL qu'on télécharge vraiment : code HTTP et taille.
- `contract`  — une vérification de comportement, pas de version : le champ
                qu'on envoie est-il toujours accepté, la réponse a-t-elle
                toujours les clés qu'on décode. C'est la seule famille qui
                attrape une rupture **silencieuse**, celle qui rend HTTP 200 et
                une liste vide.

Usage :
    python3 check_sources.py              # relève et compare (sortie 1 si écart)
    python3 check_sources.py --report     # relève et affiche, sans juger
    python3 check_sources.py --update     # assume l'état courant comme référence
    python3 check_sources.py --only smapi # ne sonde que les clés contenant « smapi »
    python3 check_sources.py --offline    # n'exécute que les contrôles locaux

Codes de sortie :
    0  rien n'a bougé (ou --report / --update)
    1  au moins une source a changé
    2  le script lui-même n'a pas pu faire son travail (référence illisible)

Les sources injoignables sont **signalées, pas comptées comme un écart** : une
panne de réseau ne doit pas se lire comme « SMAPI a sorti une version ».
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
BASELINE = os.path.join(ROOT, ".sources-baseline.json")
TIMEOUT = 30
UA = "StarHubFR-source-check/1.0 (+https://github.com/mrbabilo/StarHubFR)"


# ── Sortie ────────────────────────────────────────────────────────────────────

class C:
    """Couleurs ANSI, neutralisées hors terminal."""
    on = sys.stdout.isatty()
    RED = "\033[91m" if on else ""
    YEL = "\033[93m" if on else ""
    GRN = "\033[92m" if on else ""
    DIM = "\033[2m" if on else ""
    BOLD = "\033[1m" if on else ""
    END = "\033[0m" if on else ""


def say(msg=""):
    print(msg)


# ── Accès réseau ──────────────────────────────────────────────────────────────

def _gh(path):
    """Interroge l'API GitHub, par `gh` si disponible (quota authentifié, 5 000/h)
    et par urllib sinon (60/h, partagé par IP — vite épuisé)."""
    if shutil.which("gh"):
        try:
            out = subprocess.run(["gh", "api", path],
                                 capture_output=True, text=True, timeout=TIMEOUT,
                                 stdin=subprocess.DEVNULL)
            if out.returncode == 0:
                return json.loads(out.stdout)
            # `gh` répond proprement sur un 404 : c'est une réponse, pas une panne.
            if "Not Found" in (out.stderr or ""):
                return None
        except Exception:
            pass
    req = urllib.request.Request("https://api.github.com" + path,
                                 headers={"User-Agent": UA,
                                          "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.load(r)


def _get(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.status, r.read()


def _post_json(url, body):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"User-Agent": UA, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, None


# ── Sondes « dépôt » ──────────────────────────────────────────────────────────

def probe_repo(spec):
    """Dernière release et dernier commit d'un dépôt GitHub.

    Les deux, et pas seulement la release : une liste de compatibilité ou un
    dépôt de traductions n'en publie jamais, et son activité ne se lit que dans
    les commits. À l'inverse, un dépôt qui publie des releases bouge tout le
    temps sur `develop` sans que ça nous concerne.
    """
    repo = spec["repo"]
    meta = _gh(f"/repos/{repo}")
    state = {"pushed_at": meta.get("pushed_at"),
             "archived": bool(meta.get("archived")),
             "default_branch": meta.get("default_branch")}
    rel = None
    try:
        rel = _gh(f"/repos/{repo}/releases/latest")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
    if rel:
        state["release"] = rel.get("tag_name")
        state["released_at"] = rel.get("published_at")
    if spec.get("track_commit", True):
        commits = _gh(f"/repos/{repo}/commits?per_page=1")
        if commits:
            state["last_commit"] = commits[0]["sha"][:7]
            state["last_commit_at"] = commits[0]["commit"]["committer"]["date"]
    return state


# ── Sondes « http » ───────────────────────────────────────────────────────────

def probe_http(spec):
    """Une URL qu'on télécharge pour de vrai.

    On relève le **code et la taille**, pas une empreinte du contenu : le dump
    de compatibilité change plusieurs fois par semaine, une empreinte crierait
    en permanence. La taille attrape ce qui compte — une URL qui devient un 404
    de 14 octets, ou un fichier qui fond de moitié.

    Un code d'erreur HTTP est un **état relevé**, pas une panne de sonde. Sans
    ça, le `401` que Nexus rend légitimement à une requête sans clé se serait
    lu « injoignable » — et un vrai `404`, le jour où l'hôte change de forme,
    aurait été indistinguable de ce 401 attendu.
    """
    try:
        status, body = _get(spec["url"])
    except urllib.error.HTTPError as e:
        body = e.read() or b""
        status = e.code
    state = {"http": status, "bytes": len(body)}
    if spec.get("expect_bytes_at_least") and len(body) < spec["expect_bytes_at_least"]:
        state["alerte"] = (f"corps de {len(body)} octets, moins que le plancher "
                           f"de {spec['expect_bytes_at_least']} — l'URL a peut-être bougé")
    return state


# ── Sondes « mod » — version d'un mod du jeu, via l'oracle smapi.io ──────────

def probe_smapi_mod(spec):
    """La dernière version d'un mod Nexus, **sans clé**.

    Les pages Nexus refusent les clients non-navigateurs (403 Cloudflare,
    mesuré sur urllib et curl le 2026-09-04) et l'API v1 exige la clé du
    Trousseau — hors de question de la faire lire à un script de relevé.
    On passe donc par smapi.io, déjà le contrat réseau n° 1 de l'app, avec
    la grammaire exacte de `SmapiUpdateRequest` : une entrée
    `{id, updateKeys, installedVersion}`, **lot d'un** (un `installedVersion`
    illisible vide le lot entier — voir docs/SOURCES.md §2.1), version
    ancienne par construction pour forcer la suggestion. La réponse porte
    `metadata.main.version` : c'est l'oracle de version gratuit.

    Une réponse vide n'est pas une panne : la base smapi.io couvre les mods
    avec un décalage, un mod tout neuf peut y être absent — état relevé,
    pas alerte.
    """
    body = {
        "apiVersion": "4.1.10",   # figée, voir probe_smapi_contract
        "gameVersion": "1.6.15",
        "platform": "Mac",        # sensible à la casse : « mac » vide le lot
        "includeExtendedMetadata": True,
        "mods": [{"id": spec["uniqueId"],
                  "updateKeys": [f"Nexus:{spec['nexusId']}"],
                  "installedVersion": "0.0.1"}],
    }
    status, data = _post_json("https://smapi.io/api/v3.0/mods", body)
    if status != 200 or not data:
        return {"version": None,
                "note": f"réponse {status}{' vide' if status == 200 else ''} — couverture smapi.io en décalage ?"}
    meta = (data[0].get("metadata") or {})
    return {
        "version": (meta.get("main") or {}).get("version"),
        "name": meta.get("name"),
        "gitHubRepo": meta.get("gitHubRepo"),
    }


# ── Sondes « contrat » ────────────────────────────────────────────────────────

SMAPI_ENDPOINT = "https://smapi.io/api/v3.0/mods"
SMAPI_SAMPLE = [
    {"id": "Pathoschild.ContentPatcher", "updateKeys": ["Nexus:1915"],
     "installedVersion": "2.0.0"},
    {"id": "spacechase0.GenericModConfigMenu", "updateKeys": ["Nexus:5098"],
     "installedVersion": "1.11.0"},
]


def _smapi_body(**over):
    body = {"mods": SMAPI_SAMPLE, "includeExtendedMetadata": True,
            "gameVersion": "1.6.15", "platform": "Mac", "apiVersion": "4.1.10"}
    body.update(over)
    return body


def probe_smapi_contract(spec):
    """Ce que smapi.io fait de notre requête — pas sa version.

    Trois choses, et chacune a déjà cassé une fois :

    1. la requête nominale rend-elle encore des suggestions ? Un HTTP 200 avec
       une liste vide est le mode de panne maison de ce service : ni erreur, ni
       message, juste zéro mise à jour pour tout le parc ;
    2. `platform` reste-t-il sensible à la casse ? Mesuré le 2026-09-04 :
       « Mac » répond, « macOS » rend une liste vide. Le jour où le serveur
       accepte les deux, ce contrôle le dira — et le jour où il refuse
       « Mac », il criera avant que l'utilisateur ne le découvre ;
    3. la réponse porte-t-elle toujours les clés qu'on décode ?
    """
    state = {}

    status, data = _post_json(SMAPI_ENDPOINT, _smapi_body())
    state["http"] = status
    if not isinstance(data, list):
        state["alerte"] = "réponse non conforme (liste attendue)"
        return state
    state["mods_rendus"] = len(data)
    state["suggestions"] = sum(1 for m in data if (m.get("suggestedUpdate") or {}).get("version"))
    if state["suggestions"] == 0:
        state["alerte"] = ("zéro suggestion sur un échantillon volontairement "
                           "périmé — le lot silencieusement vide est de retour")

    # Le piège de la casse de `platform`.
    _, alt = _post_json(SMAPI_ENDPOINT, _smapi_body(platform="macOS"))
    state["platform_macOS_rend"] = len(alt) if isinstance(alt, list) else None

    if data:
        state["cles_racine"] = sorted(data[0].keys())
        state["cles_metadata"] = sorted((data[0].get("metadata") or {}).keys())
    return state


def probe_pathoschild_fields(spec):
    """Les champs du dump de compatibilité, et leur fréquence.

    On décode `status`, `brokeIn` et `summary`. Le dump en porte d'autres —
    `unofficialUpdate`, `warnings`, `abandonedReason` — qu'on n'exploite pas
    encore : les compter ici, c'est savoir ce qu'on laisse sur la table, et
    voir tout de suite le jour où l'un de ceux qu'on lit disparaît.
    """
    status, body = _get(spec["url"])
    raw = body.decode("utf-8", "replace")
    mods = json.loads(_strip_jsonc(raw))["mods"]
    interesting = ("status", "brokeIn", "summary", "unofficialUpdate",
                   "warnings", "abandonedReason", "nexus", "id")
    counts = {k: sum(1 for m in mods if m.get(k) is not None) for k in interesting}
    return {"http": status, "mods": len(mods), "champs": counts}


def probe_smapi_blacklist(spec):
    """La liste des mods **malveillants** bloqués par SMAPI (A2-T7).

    On relève le compte des deux sections et les clés de chaque entrée : une
    entrée neuve est un mod piégé de plus, et un changement de clés casserait
    silencieusement le croisement. Distincte de `mods.jsonc`, qui porte les
    incompatibilités — celle-ci parle de code hostile.
    """
    status, body = _get(spec["url"])
    doc = json.loads(_strip_jsonc(body.decode("utf-8", "replace")))
    entries = doc.get("Blacklist", [])
    loose = doc.get("LooseFileBlacklist", [])
    keys = sorted({k for e in entries for k in e})
    return {"http": status,
            "mods_bloques": len(entries),
            "fichiers_pieges": len(loose),
            "champs_entree": keys,
            "noms_surveilles": sorted(e.get("Name", "") for e in loose)}


def _strip_jsonc(raw):
    """Retire commentaires et virgules traînantes, **sans toucher aux chaînes**.

    Un `//` vit dans presque toutes les URL du dump : une regex naïve couperait
    au milieu de `https://…` et rendrait le fichier illisible.
    """
    out, in_str, esc, i = [], False, False, 0
    while i < len(raw):
        c = raw[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(raw) and raw[i + 1] == "/":
            while i < len(raw) and raw[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < len(raw) and raw[i + 1] == "*":
            j = raw.find("*/", i + 2)
            i = j + 2 if j >= 0 else len(raw)
            continue
        out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


# ── Sondes locales ────────────────────────────────────────────────────────────

def probe_pinned_constants(spec):
    """Les versions **codées en dur** dans les sources, relevées sur le disque.

    Elles ne changent que par un commit, mais c'est justement le point : les
    comparer à ce que les sources externes annoncent est la seule façon de voir
    qu'une constante a pris du retard. Aucune n'est fautive par nature —
    `apiVersion` est délibérément figée, et mesurée comme sans effet.
    """
    def grep1(path, pattern):
        try:
            text = open(os.path.join(ROOT, path), encoding="utf-8").read()
        except OSError:
            return None
        m = re.search(pattern, text)
        return m.group(1) if m else None

    return {
        "smapi_apiVersion": grep1("StarHubTH/Models/SmapiUpdateRequest.swift",
                                  r'apiVersion\s*=\s*"([^"]+)"'),
        "smapi_defaultGameVersion": grep1("StarHubTH/Models/SmapiUpdateRequest.swift",
                                          r'defaultGameVersion\s*=\s*"([^"]+)"'),
        "nexus_apiBase": grep1("StarHubTH/Models/NexusRequestBuilder.swift",
                               r'apiBase\s*=\s*"([^"]+)"'),
        "smapi_endpoint": grep1("StarHubTH/SmapiUpdateClient.swift",
                                r'endpoint\s*=\s*URL\(string:\s*"([^"]+)"'),
        "pathoschild_dumpURL": grep1("StarHubTH/Models/PathoschildCompatibilityList.swift",
                                     r'"(https://raw\.githubusercontent\.com/[^"]+)"'),
    }


# ── Le registre ───────────────────────────────────────────────────────────────
#
# L'ordre est celui de `docs/SOURCES.md` : ce que l'app appelle en marche,
# puis ce dont elle a repris du code, puis ce qu'elle observe.

SOURCES = [
    # — Contrats réseau vivants —
    {"key": "smapi.io/contrat", "kind": "contract", "probe": probe_smapi_contract,
     "role": "API de mise à jour : le verdict de tous les mods du parc",
     "used_by": "StarHubTH/SmapiUpdateClient.swift"},

    {"key": "pathoschild/dump", "kind": "contract", "probe": probe_pathoschild_fields,
     "url": "https://raw.githubusercontent.com/Pathoschild/SmapiCompatibilityList"
            "/develop/data/mods.jsonc",
     "role": "filet hors-ligne des verdicts de compatibilité",
     "used_by": "StarHubTH/Models/PathoschildCompatibilityList.swift"},

    {"key": "smapi/blacklist", "kind": "contract", "probe": probe_smapi_blacklist,
     "url": "https://smapi.io/SMAPI.blacklist.json",
     "role": "la liste des mods MALVEILLANTS que SMAPI refuse de charger — "
             "distincte de mods.jsonc (incompatibilités) : ici les messages "
             "parlent de code hostile, et plusieurs entrées sont des reuploads "
             "piégés de mods légitimes",
     "used_by": "StarHubTH/Models/SmapiBlacklist.swift",
     "note": "un écart ici n'est pas une régression mais une nouvelle menace : "
             "une entrée de plus veut dire un mod piégé de plus, à croiser au parc"},

    {"key": "nexus/api-v1", "kind": "http",
     "url": "https://api.nexusmods.com/v1/games/stardewvalley.json",
     "role": "API Nexus v1 — mods, fichiers, quota, compte",
     "used_by": "StarHubTH/Models/NexusRequestBuilder.swift",
     "note": "sans clé, un 401 est la bonne réponse : on vérifie que l'hôte "
             "répond et n'a pas été retiré, pas qu'il nous laisse entrer"},

    # — Dépôts dont on suit les versions —
    {"key": "SMAPI", "kind": "repo", "repo": "Pathoschild/SMAPI",
     "role": "le format du journal, le schéma de manifeste, l'installateur téléchargé",
     "used_by": "SmapiInstaller.swift, SmapiLogParser.swift, SmapiDiagnostics.swift"},

    {"key": "compat-list", "kind": "repo", "repo": "Pathoschild/SmapiCompatibilityList",
     "role": "le dépôt derrière le dump ci-dessus",
     "used_by": "PathoschildCompatibilityList.swift"},

    {"key": "amont/StarHubTH", "kind": "repo", "repo": "AppleBoiy/StarHubTH",
     "role": "le projet dont StarHubFR est le fork",
     "used_by": "tout le dépôt (base commune : e38c4eb)"},

    {"key": "thai-translations", "kind": "repo", "repo": "AppleBoiy/stardew-thai-translations",
     "role": "catalogue et archives du hub de traduction thaï",
     "used_by": "StarHubTHViewModel.fetchThaiTranslations / installThaiTranslation"},

    {"key": "fork/StarHubFR", "kind": "repo", "repo": "mrbabilo/StarHubFR",
     "role": "le dépôt du fork — sa page releases alimente la détection "
             "de mise à jour de l'app (jamais l'upstream : ses releases "
             "ne sont pas les nôtres)",
     "used_by": "StarHubTHViewModel.checkForAppRelease / Models/AppReleaseCheck.swift"},

    {"key": "Stardrop", "kind": "repo", "repo": "Floogen/Stardrop",
     "role": "gestionnaire concurrent (C#/Avalonia) — audité pour ses idées",
     "used_by": "docs/audit-stardrop.md"},

    {"key": "i18n-translator", "kind": "repo", "repo": "Nana1873/stardew-i18n-translator",
     "role": "référence du hub de traduction : jetons protégés, garanties d'écriture",
     "used_by": "docs/ (spec du hub FR), TranslationTokenCheck, TranslationDocument"},

    {"key": "save-editor", "kind": "repo", "repo": "colecrouter/stardew-save-editor",
     "role": "référence de l'édition de sauvegardes",
     "used_by": "SaveManager.swift"},

    {"key": "XnbHack", "kind": "repo", "repo": "Pathoschild/StardewXnbHack",
     "role": "référence du dépaquetage `.xnb` (glossaire du jeu)",
     "used_by": "XnbStringDictionaryReader.swift"},

    {"key": "log-doctor", "kind": "repo", "repo": "ZeroXPatch/Projects-for-Nexus-Mod",
     "role": "l'idée du diagnostic de journal SMAPI présenté au joueur ; "
             "héberge aussi la source de FasterMenuLoad",
     "used_by": "SmapiDiagnostics.swift (crédité dans CHANGELOG.md)"},

    {"key": "gmcm-source", "kind": "repo", "repo": "spacechase0/StardewValleyMods",
     "role": "source de Generic Mod Config Menu — l'origine de la convention "
             "config.<clé>.name/.tooltip que notre éditeur de config lit "
             "dans les i18n",
     "used_by": "ModConfigSchema (libellés), docs/SOURCES.md §6"},

    # — Mods du jeu observés (docs/SOURCES.md §6, audit-mods-config-perf.md) —
    {"key": "mod/gmcm", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 5098, "uniqueId": "spacechase0.GenericModConfigMenu",
     "role": "l'origine de la convention config.* lue par notre éditeur",
     "used_by": "ModConfigSchema (libellés), docs/audit-mods-config-perf.md"},

    {"key": "mod/modern-config-menu", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 49437, "uniqueId": "palmhacker13.ModernConfigMenu",
     "role": "front alternatif à la même API — la convention survit au changement de front",
     "used_by": "docs/audit-mods-config-perf.md"},

    {"key": "mod/ultrasmooth", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 50971, "uniqueId": "palmhacker13.UltraSmooth",
     "role": "corpus de test de l'éditeur (115 clés config.*) ; perf : "
             "us_analyze est un profil de soi, l'outil profond est la "
             "boîte noire us_trace (60 s) — rien chez les autres mods",
     "used_by": "docs/audit-mods-config-perf.md, docs/audit-perf-analyzers.md"},

    {"key": "mod/faster-menu-load", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 41564, "uniqueId": "ZeroXPatch.FasterMenuLoad",
     "role": "mod de perf ZeroXPatch — sa source vit dans le monorepo déjà suivi (log-doctor)",
     "used_by": "docs/audit-mods-config-perf.md"},

    {"key": "mod/loading-optimizer", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 50153, "uniqueId": "neoiw.StardewLoadingOptimizer",
     "role": "orchestrateur perf ; journalise [OPTIMIZER CONFIG], ligne à parser (chantier D2)",
     "used_by": "docs/audit-mods-config-perf.md"},

    {"key": "mod/speedy-solutions", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 37301, "uniqueId": "SinZ.SpeedySolutions",
     "role": "mod de perf de chargement (cache d'images, TBin) ; membre de deux "
             "paires du catalogue des recouvrements (A5-T7) — une version neuve "
             "peut rendre la ligne fausse, la redécompiler",
     "used_by": "StarHubTH/Models/PerformanceOverlap.swift"},

    {"key": "mod/profiler", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 12135, "uniqueId": "SinZ.Profiler",
     "role": "la télémétrie que le chantier D1 parse ([BigLoop]) ; installé mais en pause sur le parc",
     "used_by": "chantier D1 (ROADMAP), docs/SOURCES.md §6"},

    {"key": "profiler-source", "kind": "repo", "repo": "SinZ163/StardewMods",
     "role": "source du mod Profiler — le format de journal que D1-T2 doit parser",
     "used_by": "chantier D1 (ROADMAP)"},

    {"key": "mod/radiance", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 49397, "uniqueId": "phuicmt.SDVRadiance",
     "role": "suite graphique lourde ; diagnostic FrameCost (14 parties "
             "CPU+GPU, ours / not ours, arrival+N) — radiance_report "
             "écrit dans ~/Documents/Radiance-Dumps/",
     "used_by": "docs/SOURCES.md §6, docs/audit-perf-analyzers.md"},

    {"key": "mod/save-launcher", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 52041, "uniqueId": "Codex.StardewSaveLauncher.Companion",
     "role": "le cas limite de l'installateur : une archive de 113 Mo dont le "
             "SEUL manifeste vit quatre niveaux sous un .app (Contents/Resources/"
             "CompanionMod). `detectZipStructure` y répond `.singleMod` et pose "
             "le companion seul — l'application, qui est le produit, est écartée "
             "sans un mot. Le mod est inerte sans elle : il lit la variable "
             "STARDEW_SAVE_LAUNCHER_REQUEST qu'elle seule pose. Audité le "
             "2026-09-14 : serveur ASP.NET sur 127.0.0.1:5177, onze routes /api "
             "sans authentification, signature ad-hoc sans TeamIdentifier",
     "used_by": "docs/roadmap-archive.md §3 ter (audit), A1-T4"},

    {"key": "mod/event-studio", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 51824, "uniqueId": "xzqute.StardewEventStudio",
     "role": "éditeur d'évènements en jeu, suivi pour son i18n/default.json de "
             "41 992 octets — le plus gros corpus de clés d'un seul mod du parc "
             "de test, et donc le cas de charge de l'éditeur de traduction. "
             "Audité le 2026-09-14 : aucune référence réseau, process ou "
             "réflexion dans ses deux DLL",
     "used_by": "docs/roadmap-archive.md §3 ter (audit)"},

    {"key": "mod/keybind-radar", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 52710, "uniqueId": "wooa.KeybindRadar",
     "role": "radar de raccourcis en jeu (conflits, non-assignés, saut GMCM) — "
             "recouvre l'axe C4 ; décompilé le 2026-09-23, notre KeybindScanner "
             "est plus riche (118 raccourcis sans indice de nom que son "
             "heuristique rate)",
     "used_by": "docs/audit-keybind-radar-savesaver.md, docs/SOURCES.md §5"},

    {"key": "mod/savesaver", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 52709, "uniqueId": "Sky.SaveSaver",
     "role": "sanitation de sauvegardes au chargement (types orphelins, "
             "ErrorItems) ; décompilé le 2026-09-23. SANS UpdateKeys dans son "
             "manifeste — smapi.io peut rester muet en permanence, état relevé, "
             "pas alerte ; ses Backups vivent dans son dossier de mod "
             "(classe « données runtime » du §6, non régénérables)",
     "used_by": "docs/audit-keybind-radar-savesaver.md, docs/SOURCES.md §5"},

    {"key": "mod/stardropium", "kind": "smapi-mod", "probe": probe_smapi_mod,
     "nexusId": 52803, "uniqueId": "Arshia1381.Stardropium",
     "role": "mod de performances (37 modules en 0.1.3, dont 15 patchent des types "
             "internes d'autres mods) ; paru et audité le 2026-09-25, delta "
             "0.1.3 puis 0.1.4-beta audités le 2026-09-26, actif sur le parc "
             "à côté d'UltraSmooth. UpdateKeys Nexus + GitHub depuis 0.1.4 ; "
             "9 méthodes patchées en commun avec UltraSmooth 2.3.7 "
             "(catalogue A5-T7)",
     "used_by": "docs/audit-stardropium.md, docs/SOURCES.md §5"},

    {"key": "mod/stardropium-src", "kind": "repo", "repo": "ArshiaS1381/StardropiumMod",
     "role": "sources de Stardropium — un module retiré le jour même de la "
             "parution (suppression de mises à jour de Content Patcher) : "
             "suivre les commits, pas seulement la version",
     "used_by": "docs/audit-stardropium.md"},

    # — Local —
    {"key": "constantes-figées", "kind": "local", "probe": probe_pinned_constants,
     "role": "les versions et URL codées en dur dans les sources",
     "used_by": "—"},
]

# Sources sans sonde automatique, listées pour mémoire par `--report`.
# Les sonder demanderait une clé (donc du quota de l'utilisateur) ou un service
# qui ne tourne pas forcément.
UNPROBED = [
    ("DeepL", "api.deepl.com et api-free.deepl.com, chemins /v2/translate et "
              "/v2/usage — une sonde consommerait le quota de la clé",
     "StarHubTH/Models/DeepLClient.swift"),
    ("IA locale", "Ollama / LM Studio sur le loopback, contrat OpenAI "
                  "`POST {base}/v1/chat/completions` — ne tourne pas toujours",
     "StarHubTH/Models/LocalLLMClient.swift"),
    ("Nexus GraphQL v2", "api.nexusmods.com/v2/graphql — la recherche ; "
                         "exige un jeton",
     "StarHubTH/NexusSearchClient.swift"),
    ("Steam", "steam://run/413150 et les fichiers locaux du client Steam "
              "(nom et avatar)",
     "StarHubTHViewModel.launchGame / fetchSteamUser"),
    ("lzxd", "codeberg.org/Lonami/lzxd — le décodeur LZX dont l'algorithme a "
             "été porté. Le dépôt a **quitté GitHub** le 2026-02-09 ; "
             "Codeberg n'a pas d'API publique stable à sonder",
     "LzxdDecoder.swift, LzxdWindow.swift, LzxdTree.swift, LzxdBitstream.swift"),
]


# ── Comparaison ───────────────────────────────────────────────────────────────

def flatten(prefix, value, out):
    """Aplatit un relevé en chemins → valeur, pour dire *quoi* a bougé plutôt
    que « cette source a changé »."""
    if isinstance(value, dict):
        for k in sorted(value):
            flatten(f"{prefix}.{k}" if prefix else k, value[k], out)
    elif isinstance(value, list):
        out[prefix] = json.dumps(value, ensure_ascii=False, sort_keys=True)
    else:
        out[prefix] = value
    return out


def diff(old, new):
    a, b = flatten("", old or {}, {}), flatten("", new or {}, {})
    changes = []
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            changes.append((k, a.get(k), b.get(k)))
    return changes


# ── Suivi des changelogs ──────────────────────────────────────────────────────

# La clé que porte une source dans la référence pour dire jusqu'où son journal
# des modifications a été **lu par un humain ou un agent**, pas par le script.
CHANGELOG_FIELD = "changelog_reviewed"


def changelog_reminders(baseline, observed):
    """Les sources dont la version a dépassé le dernier changelog instruit.

    **Pourquoi ce n'est pas une sonde.** Les changelogs Nexus ne sont lisibles
    par aucun script : `urllib` et `curl` prennent un 403 Cloudflare (mesuré le
    2026-09-04, re-mesuré le 2026-09-14), la page `?tab=logs` ouverte dans un
    vrai navigateur ne rend qu'un squelette — son contenu arrive en AJAX et
    l'ancien endpoint `Core/Libs/Common/Widgets/ModChangeLogs` a disparu avec le
    passage à Next.js — et l'API v1 `/mods/{id}/changelogs.json` exige la clé du
    Trousseau, qu'un script de relevé n'a pas à lire.

    **Pourquoi pas GitHub non plus.** Mesuré le 2026-09-14 sur les trois seules
    sources `smapi-mod` qui déclarent un dépôt : `spacechase0/StardewValleyMods`,
    `SinZ163/StardewMods` et `ZeroXPatch/Projects-for-Nexus-Mod` n'ont **aucune
    release**, et sur les 100 tags du premier, **aucun** ne nomme GMCM. Un étage
    « notes de release » ne rendrait donc rien pour aucune d'elles — seulement
    du bruit.

    Ce qui reste est le seul geste honnête : **se souvenir de ce qui a été lu**.
    Le script compare la version relevée au dernier changelog instruit et le
    **rappelle** — il ne l'échoue pas. Un changelog non lu n'est ni un écart de
    source (sortie 1) ni une panne du script (sortie 2) : c'est une dette de
    lecture.
    """
    out = []
    for key, state in sorted(observed.items()):
        version = (state or {}).get("version")
        if not version:
            continue
        seen = (baseline.get(key) or {}).get(CHANGELOG_FIELD)
        if seen != version:
            out.append((key, version, seen))
    return out


NEXUS_GRAPHQL = "https://api.nexusmods.com/v2/graphql"


def fetch_changelog(mod_id):
    """Les changelogs d'un mod Nexus, par l'API v2 GraphQL, **sans clé**.

    **Pourquoi l'API et pas la page.** La page `?tab=logs` est publique et
    parfaitement lisible **dans un navigateur** — vérifié le 2026-09-14, 33
    versions extraites de MCM. Mais aucun client de script ne l'atteint :
    `urllib` et `curl` prennent un **403** (Cloudflare filtre sur l'empreinte
    TLS, que des en-têtes ne déguisent pas).

    **Pourquoi la v2 et plus la v1.** La v1 (`changelogs.json`) exige la clé
    du Trousseau. La v2 rend le même contenu sans clé — mesuré le 2026-09-25
    sur cinq mods (F9) : `modFiles` donne, **par fichier**, sa version, sa date
    et `changelogText`. Rendu ici au format de la v1, `{version: [lignes]}`,
    du plus ancien au plus récent ; un fichier sans journal ne crée pas
    d'entrée — un mod qui n'en publie aucun rend `{}`.
    """
    query = ("{ modFiles(modId: %d, gameId: 1303) "
             "{ version date changelogText } }" % int(mod_id))
    try:
        status, data = _post_json(NEXUS_GRAPHQL, {"query": query})
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"
    if status != 200 or not isinstance(data, dict):
        return None, f"HTTP {status}"
    if data.get("errors"):
        return None, "; ".join(str(e.get("message", e)) for e in data["errors"])
    files = (data.get("data") or {}).get("modFiles")
    if files is None:
        return None, "réponse sans modFiles"
    # Même règle que `NexusModDetailV2.mergeChangelogs` (A3-T7) : un journal
    # identique sur plusieurs fichiers d'une version compte une fois, un
    # journal différent ajoute ses lignes neuves — jamais de dédoublonnage à
    # l'intérieur d'un fichier (SVE répète « . » comme séparateur).
    logs = {}
    for f in sorted(files, key=lambda f: f.get("date") or 0):
        lines = f.get("changelogText") or []
        version = f.get("version")
        if not lines or not version:
            continue
        if version not in logs:
            logs[version] = list(lines)
        elif lines != logs[version]:
            logs[version].extend(line for line in lines if line not in logs[version])
    return logs, None


def load_baseline():
    if not os.path.exists(BASELINE):
        return {}
    try:
        with open(BASELINE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        say(f"{C.RED}[ERREUR]{C.END} `{os.path.basename(BASELINE)}` illisible : {e}")
        say("         Le corriger, ou le régénérer par `--update` en connaissance de cause.")
        sys.exit(2)


def save_baseline(data):
    with open(BASELINE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


# ── Programme ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="Relève l'état des sources externes de StarHubFR.")
    ap.add_argument("--update", action="store_true",
                    help="assume l'état courant comme nouvelle référence")
    ap.add_argument("--report", action="store_true",
                    help="affiche le relevé sans juger (sortie 0)")
    ap.add_argument("--only", metavar="MOTIF",
                    help="ne sonde que les sources dont la clé contient MOTIF")
    ap.add_argument("--offline", action="store_true",
                    help="n'exécute que les contrôles qui ne sortent pas de la machine")
    ap.add_argument("--fetch-changelogs", action="store_true",
                    help="récupère et affiche les changelogs des sources dont la "
                         "version a dépassé le dernier journal instruit (API Nexus v2, "
                         "sans clé). N'inscrit RIEN : c'est à la lecture de décider, "
                         "puis --changelog-reviewed")
    ap.add_argument("--changelog-reviewed", metavar="CLÉ=VERSION", action="append",
                    help="note qu'on a LU le journal des modifications d'une source "
                         "jusqu'à cette version (ex. mod/modern-config-menu=2.1.2). "
                         "Volontairement séparé de --update : celui-ci assume un "
                         "changement de version, il ne peut pas prétendre qu'on a lu "
                         "un changelog")
    args = ap.parse_args()

    if args.changelog_reviewed:
        base = load_baseline()
        for pair in args.changelog_reviewed:
            if "=" not in pair:
                say(f"{C.RED}[ERREUR]{C.END} attendu CLÉ=VERSION, reçu « {pair} »")
                return 2
            key, version = pair.split("=", 1)
            if key not in base:
                say(f"{C.RED}[ERREUR]{C.END} source inconnue : « {key} »")
                return 2
            base[key][CHANGELOG_FIELD] = version
            say(f"{C.GRN}[OK]{C.END} {key} — changelog instruit jusqu'à {C.BOLD}{version}{C.END}")
        save_baseline(base)
        return 0

    baseline = load_baseline()
    observed, unreachable = {}, []

    selected = [s for s in SOURCES
                if (not args.only or args.only.lower() in s["key"].lower())
                and (not args.offline or s["kind"] == "local")]
    if not selected:
        say(f"{C.YEL}Aucune source ne correspond au filtre.{C.END}")
        return 0

    say(f"{C.BOLD}Sources externes — relevé{C.END}")
    say("")
    for spec in selected:
        key = spec["key"]
        try:
            if spec["kind"] == "repo":
                state = probe_repo(spec)
            elif spec["kind"] == "http":
                state = probe_http(spec)
            else:
                state = spec["probe"](spec)
            observed[key] = state
            say(f"  {C.DIM}·{C.END} {key:22s} {C.DIM}{spec['role']}{C.END}")
        except Exception as e:
            unreachable.append((key, f"{type(e).__name__}: {e}"))
            say(f"  {C.YEL}?{C.END} {key:22s} {C.DIM}injoignable{C.END}")

    say("")

    if args.update:
        # Une source injoignable garde sa référence : l'écraser par du vide
        # ferait passer la panne pour un état, et le prochain retour du service
        # pour un changement.
        merged = dict(baseline)
        merged.update(observed)
        # ⚠️ Le suivi de changelog **survit** à `--update`, il n'est jamais posé
        # par lui. Sans ça, le réflexe « la version a bougé → --update »
        # estampillerait « changelog lu » sur un changelog que personne n'a
        # ouvert, et le rappel ne repartirait plus jamais. Seul
        # `--changelog-reviewed` écrit ce champ.
        for key, previous in baseline.items():
            if isinstance(previous, dict) and CHANGELOG_FIELD in previous:
                merged.setdefault(key, {})
                if isinstance(merged[key], dict):
                    merged[key][CHANGELOG_FIELD] = previous[CHANGELOG_FIELD]
        save_baseline(merged)
        say(f"{C.GRN}[OK]{C.END} Référence mise à jour "
            f"({len(observed)} source(s) relevée(s), "
            f"{len(unreachable)} conservée(s) telle(s) quelle(s)).")
        return 0

    drift = 0
    for key in sorted(observed):
        # Le suivi de changelog n'est pas un état de la source : c'est une note
        # que nous prenons sur elle. Le laisser dans la comparaison ferait
        # compter « quelqu'un a lu le changelog » comme un écart — mesuré, et
        # c'est ce qui rendait le script rouge après un `--changelog-reviewed`.
        previous = baseline.get(key)
        if isinstance(previous, dict):
            previous = {k: v for k, v in previous.items() if k != CHANGELOG_FIELD}
        changes = diff(previous, observed[key])
        if not changes:
            continue
        drift += 1
        known = key in baseline
        head = "NOUVELLE SOURCE" if not known else "A CHANGÉ"
        say(f"{C.YEL}[{head}]{C.END} {C.BOLD}{key}{C.END}")
        for path, was, now in changes:
            if known:
                say(f"    {path} : {C.DIM}{was}{C.END} → {C.BOLD}{now}{C.END}")
            else:
                say(f"    {path} = {now}")
        say("")

    for key, why in unreachable:
        say(f"{C.YEL}[INJOIGNABLE]{C.END} {key} — {why}")
    if unreachable:
        say(f"{C.DIM}    Une source injoignable n'est pas un écart : elle est "
            f"reportée, pas comptée.{C.END}")
        say("")

    if args.report:
        say(f"{C.BOLD}Relevé complet{C.END}")
        say(json.dumps(observed, ensure_ascii=False, indent=2, sort_keys=True))
        say("")
        say(f"{C.BOLD}Sources suivies à la main (pas de sonde){C.END}")
        for name, why, used in UNPROBED:
            say(f"  · {name} — {why}")
            say(f"    {C.DIM}{used}{C.END}")
        return 0

    pending = changelog_reminders(baseline, observed)

    if args.fetch_changelogs:
        if not pending:
            say(f"{C.GRN}[OK]{C.END} Aucun changelog en retard.")
            return 0
        by_key = {spec["key"]: spec for spec in SOURCES}
        missing = 0
        for skey, version, seen in pending:
            mod_id = (by_key.get(skey) or {}).get("nexusId")
            if not mod_id:
                continue
            logs, err = fetch_changelog(mod_id)
            say(f"{C.BOLD}{skey}{C.END} — Nexus {mod_id}, version {version}")
            if err:
                say(f"    {C.YEL}injoignable — {err}{C.END}")
                missing += 1
                say("")
                continue
            # Les versions postérieures au dernier journal instruit, celles
            # qu'on n'a pas lues. Sans repère, tout le journal est neuf.
            fresh = [v for v in logs if not seen or v != seen]
            if seen and seen in logs:
                order = list(logs)
                fresh = order[order.index(seen) + 1:] if seen in order else fresh
            if not logs:
                # État légitime : l'auteur n'a jamais publié de journal. Le
                # dire, plutôt que de laisser une ligne muette qu'on lirait
                # comme une panne.
                say(f"    {C.DIM}aucun changelog publié pour ce mod{C.END}")
                say("")
                continue
            for v in (fresh or list(logs))[-6:]:
                say(f"  {C.BOLD}{v}{C.END}")
                for line in logs.get(v, []):
                    # L'API rend le texte tel qu'il est saisi sur Nexus, donc
                    # avec ses entités HTML : sans ça, `Span<int>` s'affiche
                    # `Span&lt;int&gt;` et `A & B` devient `A &amp; B`.
                    say(f"    · {html.unescape(line)}")
            say("")
        say(f"{C.DIM}Rien n'a été inscrit. Après lecture : "
            f"--changelog-reviewed clé=version{C.END}")
        return 2 if missing else 0

    if pending:
        say(f"{C.DIM}[CHANGELOG]{C.END} {len(pending)} source(s) dont le journal des "
            f"modifications n'a pas été lu pour la version courante :")
        for key, version, seen in pending:
            depuis = f"lu jusqu'à {seen}" if seen else "jamais lu"
            say(f"    {key} — version {C.BOLD}{version}{C.END} ({depuis})")
        say(f"{C.DIM}    Rappel, pas un écart : `--fetch-changelogs` les affiche "
            f"(API Nexus v2, sans clé). Les lire, puis "
            f"`--changelog-reviewed clé=version`.{C.END}")
        say("")

    if drift:
        say(f"{C.YEL}[ÉCART]{C.END} {drift} source(s) ont bougé depuis la référence.")
        say("        Regarder ce qui a changé, décider, puis `--update` pour l'assumer.")
        return 1

    say(f"{C.GRN}[OK]{C.END} Aucune source n'a bougé "
        f"({len(observed)} relevée(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
