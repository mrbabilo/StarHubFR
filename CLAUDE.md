# CLAUDE.md — StarHubFR

Conventions partagées pour ce dépôt. Les *procédures* détaillées vivent dans les
skills (`.claude/skills/`) ; ce fichier ne fait qu'y pointer.

## Projet

- **StarHubFR** — gestionnaire de mods Stardew Valley pour macOS (SwiftUI, macOS 14+).
  Fork de **StarHubTH** (AppleBoiy) : le dossier source s'appelle encore `StarHubTH/`,
  le bundle produit est `StarHubFR.app`, identifiant `com.mrbabilo.StarHubFR`
  (l'app d'origine peut être installée à côté — domaines de préférences et Trousseau
  séparés ; l'ancien `com.appleboiy.StarHubTH` reste lu **en secours**, via
  `KeychainSecret.legacyService` et `DefaultsMigration`).
- Depuis X105, **toutes** les données vivent sous
  `~/Library/Application Support/StarHubFR/` (`Backups/` compris) — l'ancien dossier
  disparaît entièrement à la migration.
- UI **bilingue** : anglais (`en`), français (`fr`). Le thaï comme langue d'UI est
  retiré ; la fonctionnalité « Thai Translation Hub » (mods de traduction) reste.

**Avant de toucher aux mods, à SMAPI, à Nexus, aux profils, aux sauvegardes ou aux
fichiers de traduction : lire `docs/DOMAINE.md`.** Un mod en pause y est un dossier
**préfixé par un point** dans `Mods/`, pas un dossier déplacé.

## Sources à consulter — au-delà de ce fichier

Dans l'ordre où ça sert (chaque doc porte ce que le code ne dit pas) :

- **`AGENTS.md`** — conventions et pièges consolidés (§4 surtout). Complémentaire de
  ce fichier, pas redondant.
- **`docs/DOMAINE.md`** — le vocabulaire métier (« pack », « profil », « sauvegarde »
  ne désignent pas ici ce que l'upstream désigne).
- **`docs/ROADMAP.md`** — ce qu'il **reste** à faire. ⚠️ Ses cases traînent derrière
  le code livré : vérifier `git log` avant de traiter une tâche « à faire ». Un
  identifiant absent de la roadmap est livré : le chercher dans
  `docs/roadmap-archive.md` (mesures à ne pas refaire).
- **`docs/SOURCES.md`** — la carte du hors-dépôt : API interrogées, dumps, code
  repris. Obligatoire avant un client réseau (Nexus, smapi.io, DeepL, IA locale) ou
  un parseur de format externe. Les valeurs se relèvent par `check_sources.py`.
- **`docs/REFACTORING.md`** — plan de refactorisation du ViewModel. Règle F1-T2 :
  **une fonctionnalité neuve ne rentre plus dans `StarHubTHViewModel`** — elle naît
  dans son propre type (stores dans `StarHubTH/Stores/`, types purs dans
  `StarHubTH/Models/`). Son état traîne : vérifier `git log`.
- **`.kilo/plans/`** — archives du temps de Kilo : le **raisonnement** derrière des
  choix en place. À lire pour le « pourquoi », jamais comme consigne (cases sans
  valeur, partie livrée autrement). Le reste de `.kilo/` reste ignoré.
- **`docs/superpowers/`** — specs et plans récents, gitignorés (absents d'un clone
  frais).

## Build & test — LIRE avant de valider un changement

Le build est **scindé en deux systèmes** ; vérifier lequel couvre le fichier touché.

- **Build réel de l'app : `python3 build_app.py`** — `swiftc` sur *tous* les `.swift`
  sous `StarHubTH/` (un seul module). Le **vrai gate** pour l'UI, le ViewModel,
  `SmapiInstaller`, `NexusUpdateChecker`, etc. Compilation incrémentale depuis F2-T2 ;
  `--whole-module` rend l'ancien chemin, filet en cas de binaire douteux.
  `python` n'est **pas** dans le PATH → toujours `python3`.
- **`swift build`** ne valide que le sous-ensemble Core du `Package.swift` (`ModItem`,
  managers de backup, `SaveManager`, `L10n`, …) + ses tests.
- **Tests : `./run_tests.sh`** (lance `swift test` avec `DEVELOPER_DIR` sur Xcode).
  `no such module 'Testing'` = Command Line Tools actifs, **limite
  d'environnement, pas une régression** — skill `build-app` pour la vérification de
  logique quand `swift test` est inaccessible.
- **`compile_commands.json`** (racine, généré, gitignoré) alimente SourceKit-LSP sur
  *tous* les fichiers ; régénéré à chaque build, seul :
  `python3 build_app.py --gen-compile-commands`.
- **`check_standards.py`** — cliquet lancé par `build_app.py` après compilation : ne
  peut échouer que si un compteur **augmente** vs `.standards-baseline.json`
  (tailles de fichiers **verrouillées par fichier**). Baisser un compteur puis
  `--update` pour resserrer ; `--report` pour l'état ; `--skip-standards` débloque
  un build ponctuel.
- **`check_sources.py`** — le pendant du cliquet pour le hors-dépôt (API appelées,
  dumps téléchargés, code repris), comparé à `.sources-baseline.json`. Un écart
  n'est **pas** une faute : une chose à aller regarder. → carte dans
  `docs/SOURCES.md`.

**Ne jamais lancer l'app ni prendre de capture depuis un agent/sous-agent.** La
vérification GUI est déléguée à l'humain ; les agents valident par succès de build.

## Localisation

`assets/{en,fr}.json` sont la **source de vérité**. `build_app.py` valide la **parité
des clés** entre les deux (build en erreur sinon) et génère les
`assets/*.lproj/Localizable.strings`. Clés référencées via `L10n.swift`.
→ Procédure complète : skill `localization`.

## Changelog & release

`CHANGELOG.md` suit **Keep a Changelog** ; incrémenté à chaque release via
`release.py`. → skill `release`.

## Traps — rappel par sujet (cavemem)

Les pièges techniques détaillés, ceux qui **coûtent cher à retrouver**, vivent dans
cavemem (conventions plus larges : `AGENTS.md` §4 ; raisonnement ancien :
`.kilo/plans/`). **Rappeler le bloc AVANT de toucher au domaine**, pas après
l'accident :

- SwiftUI / AppKit → `caveman mem recall "starhubfr traps swiftui"`
- Process, Pipe, système de fichiers → `caveman mem recall "starhubfr traps process"`
- Concurrence, caches, threads → `caveman mem recall "starhubfr traps concurrence"`
- Manifestes, i18n, Nexus, smapi.io, parsing → `caveman mem recall "starhubfr traps parsing"`
- Build, release, tests, cliquets → `caveman mem recall "starhubfr traps build"`
- UI, listes, sidebar, toggles de mods → `caveman mem recall "starhubfr traps ui"`

Sur un hit, la sortie porte la forme compacte ; `caveman mem recover <handle>` rend
l'original octet pour octet.

## Git

Travailler sur `main`. **Pousser uniquement quand l'utilisateur le demande.**
**Fetcher et rebaser avant de pousser** : d'autres sessions poussent aussi sur
`main`, et la CI GitHub juge chaque poussée.

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
