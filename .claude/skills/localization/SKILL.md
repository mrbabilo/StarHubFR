---
name: localization
description: Use when adding, renaming, or editing a user-facing string in StarHubFR — keeps the en/th/fr JSON files at key parity and wired through L10n.swift.
---

# Localisation StarHubFR (en / th / fr)

## Source de vérité

`assets/en.json`, `assets/th.json`, `assets/fr.json` — un dictionnaire plat
`clé → texte`. `assets/*.lproj/Localizable.strings` sont **générés** par
`build_app.py` (ne pas les éditer à la main).

## Ajouter / modifier une chaîne

1. Ajouter la **même clé** dans **les trois** fichiers `assets/{en,th,fr}.json`
   avec la traduction adaptée. `en` est la locale de référence.
2. Référencer la clé côté Swift via `L10n.swift` (voir les entrées existantes pour
   le motif exact).
3. Builder : `python3 build_app.py`. Il **valide la parité des clés** — toute clé
   manquante ou en trop dans une locale fait échouer le build avec
   `[ERROR] <locale>.json is missing/has extra keys`. Corriger jusqu'au `[SUCCESS]`.

## Règles

- Français : orthographe complète, accents et diacritiques obligatoires.
- Ne jamais laisser une locale à la traîne : les trois JSON doivent avoir
  exactement le même jeu de clés.
- Sauvegarder les fichiers de langue avant refonte massive (le repo backupe déjà
  tous les fichiers de langue des mods, pas seulement `fr.json`).
