#!/usr/bin/env python3
"""Extrait les choix de config que les mods C# déclarent via leurs types.

MCM (in-game) voit les valeurs autorisées et min/max parce que les mods les
déclarent à l'API GMCM/MCM au lancement. Hors jeu, la même information se
lit **statiquement** dans la DLL : une clé de config dont la propriété
porte un type enum **de l'assembly lui-même** est un choix à valeurs figées
(`PlacementRule` → Strict/Loose/Anarchy). Les enums externes (SButton) sont
exclus naturellement : ce sont des touches, pas des choix (C4-T10 les
traite déjà), et les booléens/nombres ont leurs propres contrôles.

Sortie : assets/gmcm-options.json — { "<uniqueId>": { "<clé>": [valeurs] } }.
Rejouer après installation/retrait de mods : python3 tools/gmcm_options.py
(dépendance : dnfile — venv conseillé, voir docs/SOURCES.md).
"""
import json
import os
import re
import sys

from dnfile import dnPE

MODS_DIR_DEFAULT = "/Applications/Stardew Valley.app/Contents/MacOS/Mods"
OUTPUT_DEFAULT = "assets/gmcm-options.json"


def lenient_json(path):
    """config.json et manifest.json sont parfois JSON5 (commentaires,
    virgules traînantes) — même tolérance que l'app."""
    text = open(path, encoding="utf-8-sig", errors="replace").read()
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return json.loads(text)


def read_compressed_uint(data, pos):
    """Entier compressé ECMA-335 (§II.23.2)."""
    b0 = data[pos]
    if b0 & 0x80 == 0:
        return b0, pos + 1
    if b0 & 0xC0 == 0x80:
        return ((b0 & 0x3F) << 8) | data[pos + 1], pos + 2
    return ((b0 & 0x1F) << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3], pos + 4


def sig_element_type_and_token(blob):
    """[0]=0x28 (PropertySig|HASTHIS), [1]=paramCount, puis le type. Rend
    (element_type, coded_index_token) pour les VALUETYPE/CLASS, sinon
    (element_type, None)."""
    if len(blob) < 3 or blob[0] & 0x0F != 0x08:
        return None, None
    pos = 2
    et = blob[pos]
    pos += 1
    if et in (0x11, 0x12):  # VALUETYPE / CLASS
        token, _ = read_compressed_uint(blob, pos)
        return et, token
    return et, None


def literal_fields(typedef):
    """Les valeurs d'un enum : ses champs **littéraux** (constantes), avec
    le marqueur `value__` présent. Sans ce double filtre, toute classe à
    champs entre dans le lot (`<Auto>k__BackingField`…) — relevé sur
    FontSettings/Kinematics lors du premier passage."""
    names = []
    has_value_marker = False
    for f in typedef.FieldList:
        row = f.row
        n = row.Name.value if hasattr(row.Name, "value") else str(row.Name)
        if n == "value__":
            has_value_marker = True
            continue
        flags = row.Flags
        if getattr(flags, "fdLiteral", False):
            names.append(n)
    return names if has_value_marker else []


def extract(dll_path):
    """{clé de config: [valeurs]} pour les propriétés enum internes."""
    pe = dnPE(dll_path)
    mdt = pe.net.mdtables
    typedefs = mdt.TypeDef.rows

    def typedef_by_rid(rid):
        if 1 <= rid <= len(typedefs):
            return typedefs[rid - 1]
        return None

    enums = {}
    for t in typedefs:
        fl = literal_fields(t)
        if fl:
            enums[id(t)] = fl

    out = {}
    for pm in mdt.PropertyMap.rows:
        for pr in pm.PropertyList:
            row = pr.row
            name = row.Name.value if hasattr(row.Name, "value") else str(row.Name)
            blob = row.Type.value if hasattr(row.Type, "value") else bytes(row.Type)
            if hasattr(blob, "__bytes__"):
                blob = bytes(blob)
            et, token = sig_element_type_and_token(blob)
            if et != 0x11 or token is None:  # VALUETYPE uniquement
                continue
            # index codé TypeDefOrRef : 2 bits bas = table (0 = TypeDef).
            rid, tag = token >> 2, token & 0x3
            if tag != 0:
                continue  # TypeRef (ex. SButton) : externe, pas un choix.
            typedef = typedef_by_rid(rid)
            if typedef is None:
                continue
            values = enums.get(id(typedef))
            if values and len(values) >= 2:
                out[name] = values
    return out


def main():
    mods_dir = sys.argv[1] if len(sys.argv) > 1 else MODS_DIR_DEFAULT
    output = sys.argv[2] if len(sys.argv) > 2 else OUTPUT_DEFAULT
    dataset = {}
    scanned = 0
    for entry in sorted(os.listdir(mods_dir)):
        mod = os.path.join(mods_dir, entry)
        if not os.path.isdir(mod):
            continue
        manifest = os.path.join(mod, "manifest.json")
        dlls = [f for f in os.listdir(mod) if f.endswith(".dll")]
        if not os.path.isfile(manifest) or not dlls:
            continue
        try:
            uid = lenient_json(manifest).get("UniqueID", "")
        except Exception:
            continue
        if not uid:
            continue
        merged = {}
        for dll in dlls:
            try:
                merged.update(extract(os.path.join(mod, dll)))
            except Exception as e:
                print(f"[WARN] {entry}/{dll} : {e}", file=sys.stderr)
        if merged:
            dataset[uid] = merged
            scanned += 1
    with open(output, "w", encoding="utf-8") as f:
        json.dump(dataset, f, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"[INFO] {scanned} mods à choix d'enum → {output}")


if __name__ == "__main__":
    main()
