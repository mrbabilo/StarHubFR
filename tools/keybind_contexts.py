#!/usr/bin/env python3
"""keybind_contexts.py — relevé hors app des contextes d'écoute des mods.

Le dataset `assets/keybind-contexts.json` porte, par mod, **quand** il
écoute ses touches (menu propre, mode, touche d'activation). Ce savoir
vient de la lecture du C# décompilé de chaque DLL ; cet outil prépare ce
travail, il ne le remplace pas :

  1. il trouve les mods dont le `config.json` porte des réglages de
     touches (grammaire SButton heuristique) ;
  2. il décompile la DLL de chacun (ilspycmd, .NET) — cache par empreinte
     (chemin + mtime) pour ne payer qu'une fois ;
  3. il garde les clés que le C# déclare `SButton`/`KeybindList`/`Keys`
     (le type fait foi, la grammaire ne fait que préfiltrer), et relève
     chaque lecture (`.JustPressed()`, `e.Button == …`, `IsDown(…)`) avec
     les **gardes** du code au-dessus (`Context.IsWorldReady`,
     `activeClickableMenu`, mode propre…) ;
  4. il compare au dataset : mods non couverts, entrées périmées.

Limite : la preuve se rattache au **nom de feuille** de la clé ; des
réglages homonymes (`ShortcutKey` de chaque couche de Data Layers)
partagent les mêmes lectures.

Sortie : `report.md` (à lire, pour décider les règles candidates) et
`candidates.json` (machine). Rien n'écrit dans le dataset : une règle
n'entre qu'après vérification humaine dans le C# décompilé.

Usage :
  python3 tools/keybind_contexts.py scan --mods "/path/Mods" \
      --dataset assets/keybind-contexts.json --out /tmp/keybind-report
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ── Grammaire de touches (heuristique, côté outil seulement) ──────────────

STRONG_TOKEN = re.compile(
    r"^(?:D\d|F\d\d?|NumPad\d|Mouse(?:Left|Right|Middle|XButton\d)"
    r"|Left|Right|Oem[A-Za-z]+)$")
WEAK_TOKEN = re.compile(r"^[A-Z][A-Za-z0-9]*$")
PLAIN_NAMES = {
    "escape", "space", "tab", "enter", "backspace", "delete", "insert",
    "home", "end", "pageup", "pagedown", "up", "down", "left", "right",
    "none", "add", "subtract", "multiply", "divide", "decimal",
    "capslock", "leftshift", "rightshift", "leftcontrol", "rightcontrol",
    "leftalt", "rightalt", "leftwindows", "rightwindows",
}


def looks_like_keybind(value):
    """Un réglage candidat-touche : `None`, ou des jetons SButton."""
    if not isinstance(value, str) or not value.strip():
        return False
    tokens = [t.strip() for t in re.split(r"[+,]", value) if t.strip()]
    if not tokens:
        return False
    for token in tokens:
        low = token.lower()
        if low in PLAIN_NAMES or STRONG_TOKEN.match(token):
            continue
        if len(token) == 1 and token.isalpha():
            continue  # lettre (A-Z, la règle du libellé)
        if WEAK_TOKEN.match(token) and any(
                c.isdigit() or c.isupper() for c in token[1:]):
            continue  # composé improbable mais typé SButton
        return False
    return True


JSON_STRING = r'"(?:\\.|[^"\\])*"'
JSON_COMMENT = re.compile(JSON_STRING + r"|//[^\n]*|/\*[\s\S]*?\*/")
JSON_TRAILING_COMMA = re.compile(JSON_STRING + r"|,(?=\s*[}\]])")


def parse_json_lenient(text):
    """Manifestes et configs tolèrent commentaires et virgules finales
    (Newtonsoft). Le décapage saute les chaînes : un `//` naïf coupait
    `"https://smapi.io/schemas/manifest.json"` et perdait le mod."""
    try:
        return json.loads(text)
    except ValueError:
        keep_strings = lambda m: m.group(0) if m.group(0)[0] == '"' else ""
        stripped = JSON_COMMENT.sub(keep_strings, text)
        stripped = JSON_TRAILING_COMMA.sub(keep_strings, stripped)
        try:
            return json.loads(stripped)
        except ValueError:
            return None


def walk_leaves(node, path=()):
    if isinstance(node, dict):
        for key, child in node.items():
            yield from walk_leaves(child, path + (key,))
    else:
        yield path, node


# ── Découverte des mods ────────────────────────────────────────────────────

def find_mods(mods_root):
    """Dossiers à manifeste, jusqu'à 3 niveaux (packs chemisés compris).
    Rend des dicts : id, nom, dossier, dll, actif, clés de touches."""
    mods, unreadable = [], []
    for manifest_path in sorted(mods_root.rglob("manifest.json")):
        depth = len(manifest_path.relative_to(mods_root).parts)
        if depth > 4:  # manifest + 3 niveaux de dossiers
            continue
        manifest = parse_json_lenient(manifest_path.read_text(
            encoding="utf-8-sig", errors="replace"))
        if not isinstance(manifest, dict):
            unreadable.append(str(manifest_path.relative_to(mods_root)))
            continue
        folder = manifest_path.parent
        rel = folder.relative_to(mods_root)
        active = not any(part.startswith(".") for part in rel.parts)
        config = folder / "config.json"
        keys, string_leaves = [], []
        if config.exists():
            tree = parse_json_lenient(config.read_text(
                encoding="utf-8-sig", errors="replace"))
            if isinstance(tree, dict):
                for path, value in walk_leaves(tree):
                    if isinstance(value, str):
                        string_leaves.append(list(path))
                    if looks_like_keybind(value):
                        keys.append(list(path))
        # La DLL du mod est celle que SMAPI charge : `EntryDll`. Un pack de
        # contenu n'en a pas — personne ne lit ses « touches » comme touches.
        entry_dll = manifest.get("EntryDll")
        dll = folder / entry_dll if isinstance(entry_dll, str) else None
        mods.append({
            "id": str(manifest.get("UniqueID", "")),
            "name": str(manifest.get("Name", folder.name)),
            "folder": str(folder),
            "rel": str(rel),
            "dll": str(dll) if dll and dll.exists() else None,
            "contentPack": dll is None,
            "active": active,
            "keybindKeys": keys,  # préfiltre seulement
            "stringLeaves": string_leaves,
        })
    return mods, unreadable


# ── Décompilation (cache par chemin + mtime) ──────────────────────────────

KEY_TYPES = r"(?:KeybindList|SButton\??|Keys|Buttons)"
KEY_DECL_PATTERN = re.compile(rf"^\s*public\s+{KEY_TYPES}\s+(\w+)\b")
INPUT_CALLS = r"(?:IsDown|IsSuppressed|GetState|Suppress|IsPressed|IsKeyDown)"


def read_patterns(key):
    """Les formes sous lesquelles le C# décompilé lit une touche :
    `X.Key.JustPressed()` (KeybindList), `e.Button == X.Key` (SButton),
    `Input.IsDown(X.Key)`."""
    k = re.escape(key)
    return [
        ("méthode", re.compile(
            rf"\.{k}\.(?:JustPressed|IsDown|IsPressed|IsSuppressed"
            rf"|GetState)\(")),
        ("comparaison", re.compile(
            rf"(?:[=!]=\s*[\w.()]*\.{k}\b|\.{k}\s*[=!]=)")),
        ("appel", re.compile(rf"\b{INPUT_CALLS}\([^)]*\.{k}\b")),
    ]


def keybind_properties(cs_text):
    """Noms déclarés `public SButton|KeybindList|Keys X` : la vérité sur
    ce qui est une touche, là où la grammaire de config devine."""
    return {m.group(1) for line in cs_text.splitlines()
            if (m := KEY_DECL_PATTERN.match(line))}
DECL_PATTERN = re.compile(
    r"^\s*(?:public|private|protected|internal|static).*?\b\w+\s*\(")
GUARD_PATTERN = re.compile(
    r"\b(?:Context\.IsWorldReady|Context\.IsPlayerFree|Context\.IsMainPlayer"
    r"|activeClickableMenu|IsOverviewActive|editorMode|replay\.IsActive"
    r"|playingEvent|eventUp|Game1\.eventUp|IsStashAnywhereActive"
    r"|ModEnabled|paused|Suppress\w*)")


def decompile(dll, cache_dir, ilspycmd, dotnet_root):
    """C# décompilé, en cache. Sortie écrite **dans un fichier** (jamais
    un pipe : une DLL produit des mégaoctets)."""
    digest = hashlib.sha256(
        f"{dll}:{Path(dll).stat().st_mtime_ns}".encode()).hexdigest()[:20]
    cached = cache_dir / f"{digest}.cs"
    if cached.exists():
        return cached
    cache_dir.mkdir(parents=True, exist_ok=True)
    env = None
    if dotnet_root:
        env = dict(os.environ)  # hériter, puis surcharger
        env["DOTNET_ROOT"] = dotnet_root
    # Écrit à côté puis renommé : un délai dépassé ne laisse pas un .cs
    # tronqué que le passage suivant prendrait pour bon.
    partial = cached.with_suffix(".partial")
    try:
        with partial.open("wb") as out:
            result = subprocess.run(
                [ilspycmd, dll], stdout=out, stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL, env=env, timeout=180)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.decode(errors="replace")[:300])
        partial.replace(cached)
    finally:
        partial.unlink(missing_ok=True)
    return cached


def key_evidence(cs_text, key):
    """Pour une clé de config : chaque lecture comme touche, avec les
    gardes visibles **au-dessus** dans la même méthode (fenêtre bornée
    par la déclaration suivante). Approximation assumée : c'est de
    l'aide à la lecture, pas une analyse."""
    evidence = []
    lines = cs_text.splitlines()
    patterns = read_patterns(key)
    for i, line in enumerate(lines):
        if f".{key}" not in line or "AddKeybind" in line:
            continue
        match = next(((kind, m) for kind, pattern in patterns
                      if (m := pattern.search(line))), None)
        if not match:
            continue
        kind, found = match
        guards = []
        for back in range(i - 1, max(i - 40, -1), -1):
            above = lines[back]
            if DECL_PATTERN.match(above) and "=>" not in above:
                break
            if GUARD_PATTERN.search(above):
                guards.append(above.strip())
        evidence.append({
            "line": i + 1,
            "kind": kind,
            "read": found.group(0).strip(),
            "guards": list(reversed(guards[-6:])),
        })
    return evidence


# ── Rapports ───────────────────────────────────────────────────────────────

def build_report(mods, dataset_ids, cache_dir, ilspycmd, dotnet_root):
    candidates, failures = [], []
    # Packs de contenu exclus : sans DLL, leurs valeurs « None »/« Left »
    # ne sont pas des touches (options d'un ConfigSchema).
    with_keys = [m for m in mods if m["keybindKeys"] and not m["contentPack"]]
    covered = 0
    for mod in with_keys:
        uid = mod["id"]
        known = uid.lower() in dataset_ids
        if known:
            covered += 1
        entry = {"id": uid, "name": mod["name"], "rel": mod["rel"],
                 "active": mod["active"], "known": known, "keys": {}}
        if not mod["dll"]:
            entry["error"] = "EntryDll introuvable"
            failures.append(entry)
            candidates.append(entry)
            continue
        try:
            cs_file = decompile(mod["dll"], cache_dir, ilspycmd, dotnet_root)
        except Exception as error:  # noqa: BLE001 — relevé best-effort
            entry["error"] = str(error)
            failures.append(entry)
            candidates.append(entry)
            continue
        cs_text = cs_file.read_text(encoding="utf-8", errors="replace")
        typed = keybind_properties(cs_text)
        entry["untyped"] = [".".join(p) for p in mod["keybindKeys"]
                            if p[-1] not in typed]
        for path in mod["stringLeaves"]:
            key = path[-1]
            if key not in typed:
                continue
            entry["keys"][".".join(path)] = key_evidence(cs_text, key)
        candidates.append(entry)
    stale = sorted(dataset_ids - {m["id"].lower() for m in mods})
    return candidates, stale, failures, len(with_keys), covered


def write_reports(out_dir, candidates, stale, unreadable, total, covered):
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "candidates.json").write_text(
        json.dumps({"candidates": candidates, "staleDatasetEntries": stale,
                    "unreadableManifests": unreadable},
                   ensure_ascii=False, indent=2),
        encoding="utf-8")
    typed = sum(1 for e in candidates if e["keys"])
    lines = ["# Contextes d'écoute — relevé candidat", "",
             f"{total} mods passés au C# ; {typed} déclarent des touches "
             f"(SButton/KeybindList) ; {covered} déjà dans le dataset ; "
             f"{len(stale)} entrées périmées.", ""]
    if unreadable:
        lines += ["## Manifestes illisibles (mods absents du relevé)", ""]
        lines += [f"- {path}" for path in unreadable] + [""]
    if stale:
        lines += ["## Entrées périmées du dataset", ""]
        lines += [f"- {uid}" for uid in stale] + [""]
    for entry in candidates:
        flag = "connu" if entry["known"] else "**NON COUVERT**"
        state = "actif" if entry["active"] else "en pause"
        lines.append(f"## {entry['name']} — `{entry['id']}` ({state}, {flag})")
        lines.append("")
        if "error" in entry:
            lines += [f"⚠️ {entry['error']}", ""]
            continue
        if not entry["keys"]:
            lines += ["Aucun réglage typé touche dans la DLL — la grammaire "
                      "de config s'est trompée (vérifier à la main si le "
                      "dataset prétend le contraire).", ""]
            continue
        for key, hits in sorted(entry["keys"].items()):
            lines.append(f"### `{key}`")
            for hit in hits:
                lines.append(f"- l.{hit['line']} ({hit['kind']}) "
                             f"`{hit['read']}`")
                for guard in hit["guards"]:
                    lines.append(f"  - garde : `{guard}`")
            if not hits:
                lines.append("- typé touche, mais aucune lecture reconnue "
                             "(lu indirectement ? à lire)")
        lines.append("")
    (out_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["scan"])
    parser.add_argument("--mods", required=True, type=Path)
    parser.add_argument("--dataset", type=Path,
                        default=Path("assets/keybind-contexts.json"))
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--cache", type=Path,
                        default=Path(".keybind-decompile-cache"))
    parser.add_argument("--ilspycmd", default=str(
        Path.home() / ".dotnet/tools/ilspycmd"))
    parser.add_argument("--dotnet-root",
                        default="/opt/homebrew/Cellar/dotnet/10.0.401/libexec")
    args = parser.parse_args()

    if not args.mods.is_dir():
        sys.exit(f"dossier Mods introuvable : {args.mods}")
    dataset_ids = set()
    if args.dataset.exists():
        dataset_ids = {uid.lower() for uid in
                       json.loads(args.dataset.read_text())["mods"]}

    mods, unreadable = find_mods(args.mods)
    candidates, stale, failures, total, covered = build_report(
        mods, dataset_ids, args.cache, args.ilspycmd, args.dotnet_root)
    write_reports(args.out, candidates, stale, unreadable, total, covered)
    print(f"{len(mods)} mods, {total} à touches, {covered} couverts, "
          f"{len(stale)} périmés, {len(failures)} échecs de décompilation, "
          f"{len(unreadable)} manifestes illisibles.")
    print(f"rapport : {args.out/'report.md'}")


if __name__ == "__main__":
    main()
