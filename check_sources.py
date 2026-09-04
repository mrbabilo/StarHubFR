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
     "role": "l'idée du diagnostic de journal SMAPI présenté au joueur",
     "used_by": "SmapiDiagnostics.swift (crédité dans CHANGELOG.md)"},

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
    args = ap.parse_args()

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
        save_baseline(merged)
        say(f"{C.GRN}[OK]{C.END} Référence mise à jour "
            f"({len(observed)} source(s) relevée(s), "
            f"{len(unreachable)} conservée(s) telle(s) quelle(s)).")
        return 0

    drift = 0
    for key in sorted(observed):
        changes = diff(baseline.get(key), observed[key])
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

    if drift:
        say(f"{C.YEL}[ÉCART]{C.END} {drift} source(s) ont bougé depuis la référence.")
        say("        Regarder ce qui a changé, décider, puis `--update` pour l'assumer.")
        return 1

    say(f"{C.GRN}[OK]{C.END} Aucune source n'a bougé "
        f"({len(observed)} relevée(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
