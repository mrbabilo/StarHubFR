---
name: release
description: Use when cutting a StarHubFR release — bumping CHANGELOG (Keep a Changelog) and running release.py.
---

# Release StarHubFR

## 1. CHANGELOG

`CHANGELOG.md` suit **Keep a Changelog**. Avant de tagguer :

- Déplacer les entrées de `## [Unreleased]` vers une nouvelle section versionnée
  `## [X.Y.Z] - YYYY-MM-DD`.
- Regrouper sous `Added` / `Changed` / `Fixed` / `Removed`.
- Préserver l'historique pré-fork (1.0.0 → 1.0.9) déjà présent.
- Le `CHANGELOG.md` est copié dans le bundle par `build_app.py` (visible dans l'app).

## 2. Builder puis publier

```bash
python3 build_app.py     # produit StarHubTH.app signé ad-hoc
python3 release.py       # empaquetage / publication du release
```

Lire `release.py` avant de le lancer pour confirmer ce qu'il fait (zip, version,
destination). **Ne pousser / publier que sur demande explicite de l'utilisateur.**
