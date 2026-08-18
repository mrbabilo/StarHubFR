# CLAUDE.md — StarHubFR

Conventions partagées pour ce dépôt. Les *procédures* détaillées vivent dans les
skills (`.claude/skills/`) ; ce fichier ne fait qu'y pointer.

## Projet

- **StarHubFR** — gestionnaire de mods Stardew Valley pour macOS (SwiftUI, macOS 14+).
- Fork de **StarHubTH** (AppleBoiy). Le dossier source s'appelle encore `StarHubTH/`,
  mais le bundle produit est désormais `StarHubFR.app` (exécutable `StarHubFR`).
  Seul l'identifiant de bundle reste `com.appleboiy.StarHubTH` (Keychain/préférences).
- UI **bilingue** : anglais (`en`), français (`fr`). *(Le thaï comme langue d'UI a
  été retiré ; la fonctionnalité « Thai Translation Hub » — mods de traduction —
  reste, elle.)*

**Avant de toucher aux mods, à SMAPI, à Nexus, aux profils, aux sauvegardes ou aux
fichiers de traduction : lire `docs/DOMAINE.md`.** Il porte ce que le code ne dit
pas — notamment que « pack », « profil » et « sauvegarde » désignent ici autre
chose que chez l'upstream, et qu'un mod en pause est un dossier **préfixé par un
point** dans `Mods/`, pas un dossier déplacé.

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
- **`check_standards.py`** — cliquet sur les conventions Swift, lancé par
  `build_app.py` après une compilation réussie. Il n'échoue que si un compteur
  **augmente** par rapport à `.standards-baseline.json` : le code viole
  massivement ces règles aujourd'hui, une barrière serait rouge dès le premier
  jour. Faire baisser un compteur puis `--update` pour resserrer ; `--report`
  pour voir l'état. Un ajout délibéré demande un `--update` explicite, visible
  dans le diff. `--skip-standards` débloque un build ponctuel.

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

Terminer les messages de commit par un trailer nommant le **modèle qui a
réellement écrit le commit** — jamais un nom figé :

- Claude : `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
  (ou `Claude Sonnet 5`, `Claude Haiku 4.5`… selon le modèle actif).
- GLM : `Co-Authored-By: GLM 5.3 <noreply@z.ai>`.

⚠️ Le dépôt est travaillé avec **plusieurs modèles**, dont GLM via `glm.sh`
(qui route Claude Code vers l'API z.ai : le modèle *actif* est alors GLM, quel
que soit l'alias `sonnet`/`opus` affiché). Vérifier quel modèle tourne avant de
signer.

L'historique antérieur au 2026-07-30 porte `Claude Sonnet 5` sur 167 commits,
y compris ceux d'autres modèles : ne pas s'y fier comme source de vérité.
