# CLAUDE.md — StarHubFR

Conventions partagées pour ce dépôt. Les *procédures* détaillées vivent dans les
skills (`.claude/skills/`) ; ce fichier ne fait qu'y pointer.

## Projet

- **StarHubFR** — gestionnaire de mods Stardew Valley pour macOS (SwiftUI, macOS 14+).
- Fork de **StarHubTH** (AppleBoiy). Le dossier source s'appelle encore `StarHubTH/`
  et le bundle produit `StarHubTH.app` ; seul le nom affiché est « StarHubFR ».
- UI **bilingue** : anglais (`en`), français (`fr`). *(Le thaï comme langue d'UI a
  été retiré ; la fonctionnalité « Thai Translation Hub » — mods de traduction —
  reste, elle.)*

## Build & test — LIRE avant de valider un changement

Le build est **scindé en deux systèmes** ; vérifier lequel couvre le fichier touché.

- **Build réel de l'app** : `python3 build_app.py` — `swiftc` brut sur *tous* les
  `.swift` sous `StarHubTH/` (un seul module). C'est le **vrai gate** pour tout ce
  qui touche l'UI, le ViewModel, `SmapiInstaller`, `NexusUpdateChecker`, etc.
  `python` n'est **pas** dans le PATH → toujours `python3`.
- **`swift build`** ne valide que le sous-ensemble Core du `Package.swift`
  (`ModItem`, les managers de backup, `SaveManager`, `L10n`, …) + ses tests.
- **Tests** : `./run_tests.sh` (lance `swift test` avec `DEVELOPER_DIR` sur Xcode).
  Peut échouer avec `no such module 'Testing'` si seuls les Command Line Tools sont
  actifs — c'est une **limite d'environnement, pas une régression**. Voir le skill
  `build-app` pour la vérification de logique quand `swift test` est inaccessible.
- **`compile_commands.json`** (racine, généré, gitignoré) alimente SourceKit-LSP
  pour l'autocomplétion sur *tous* les fichiers. Régénéré à chaque build ;
  rafraîchir seul avec `python3 build_app.py --gen-compile-commands`.

**Ne jamais lancer l'app ni prendre de capture depuis un agent/sous-agent.** La
vérification GUI est déléguée à l'humain ; les agents valident par succès de build.

## Localisation

`assets/{en,fr}.json` sont la **source de vérité**. `build_app.py` valide la
**parité des clés** entre les deux (build en erreur sinon) et génère les
`assets/*.lproj/Localizable.strings`. Les clés sont référencées via `L10n.swift`.
→ Procédure complète : skill `localization`.

## Changelog & release

`CHANGELOG.md` suit le format **Keep a Changelog** ; incrémenté à chaque release
via `release.py`. → skill `release`.

## Git

Travailler sur `main`. **Pousser uniquement quand l'utilisateur le demande.**
Terminer les messages de commit par :
`Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
