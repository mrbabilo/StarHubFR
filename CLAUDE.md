# CLAUDE.md — StarHubFR

Conventions partagées du dépôt. *Procédures* détaillées → skills (`.claude/skills/`) ; ce fichier pointe seulement.

## Projet

- **StarHubFR** — gestionnaire mods Stardew Valley macOS (SwiftUI, macOS 14+).
  Fork de **StarHubTH** (AppleBoiy) : dossier source encore `StarHubTH/`, bundle `StarHubFR.app`, identifiant `com.mrbabilo.StarHubFR` (app d'origine installable à côté — domaines préférences + Trousseau séparés ; ancien `com.appleboiy.StarHubTH` lu **en secours** via `KeychainSecret.legacyService` et `DefaultsMigration`).
- Depuis X105, **toutes** données sous `~/Library/Application Support/StarHubFR/` (`Backups/` compris) — ancien dossier supprimé entièrement à migration.
- UI **bilingue** : anglais (`en`), français (`fr`). Thaï UI retiré, « Thai Translation Hub » aussi (C5-T1, 2026-09-24) : sa place sidebar → page « Traductions FR ».

**Avant toucher mods, SMAPI, Nexus, profils, sauvegardes ou fichiers traduction : lire `docs/DOMAINE.md`.** Mod en pause = dossier **préfixé par point** dans `Mods/`, pas dossier déplacé.

## Sources à consulter — au-delà de ce fichier

Ordre d'utilité (chaque doc porte ce que code ne dit pas) :

- **`AGENTS.md`** — conventions + pièges consolidés (§4 surtout). Complémentaire, pas redondant.
- **`docs/DOMAINE.md`** — vocabulaire métier (« pack », « profil », « sauvegarde » ≠ sens upstream).
- **`docs/ROADMAP.md`** — ce qui **reste** à faire. ⚠️ Cases en retard sur code livré : vérifier `git log` avant tâche « à faire ». Identifiant absent roadmap = livré : chercher dans `docs/roadmap-archive.md` (mesures à ne pas refaire).
- **`docs/SOURCES.md`** — carte hors-dépôt : API interrogées, dumps, code repris. Obligatoire avant client réseau (Nexus, smapi.io, DeepL, IA locale) ou parseur format externe. Valeurs relevées par `check_sources.py`.
- **`docs/REFACTORING.md`** — plan refacto ViewModel. Règle F1-T2 : **fonctionnalité neuve n'entre plus dans `StarHubTHViewModel`** — naît dans propre type (stores dans `StarHubTH/Stores/`, types purs dans `StarHubTH/Models/`). État en retard : vérifier `git log`.
- **`.kilo/plans/`** — archives ère Kilo : **raisonnement** derrière choix en place. Lire pour « pourquoi », jamais comme consigne (cases sans valeur, partie livrée autrement). Reste de `.kilo/` ignoré.
- **`docs/superpowers/`** — specs + plans récents, gitignorés (absents d'un clone frais).

## Build & test — LIRE avant de valider un changement

Build **scindé en deux systèmes** ; vérifier lequel couvre fichier touché.

- **Build réel app : `python3 build_app.py`** — `swiftc` sur *tous* `.swift` sous `StarHubTH/` (un module). **Vrai gate** pour UI, ViewModel, `SmapiInstaller`, `NexusUpdateChecker`, etc. Compilation incrémentale depuis F2-T2 ; `--whole-module` = ancien chemin, filet si binaire douteux.
  `python` **pas** dans PATH → toujours `python3`.
- **`swift build`** valide seulement sous-ensemble Core du `Package.swift` (`ModItem`, managers backup, `SaveManager`, `L10n`, …) + tests.
- **Tests : `./run_tests.sh`** (lance `swift test` avec `DEVELOPER_DIR` sur Xcode). `no such module 'Testing'` = Command Line Tools actifs, **limite environnement, pas régression** — skill `build-app` pour vérif logique si `swift test` inaccessible.
- **`compile_commands.json`** (racine, généré, gitignoré) alimente SourceKit-LSP sur *tous* fichiers ; régénéré à chaque build, seul : `python3 build_app.py --gen-compile-commands`.
- **`check_standards.py`** — cliquet lancé par `build_app.py` post-compilation : échoue seulement si compteur **augmente** vs `.standards-baseline.json` (tailles fichiers **verrouillées par fichier**). Baisser compteur puis `--update` pour resserrer ; `--report` pour état ; `--skip-standards` débloque build ponctuel.
- **`check_sources.py`** — pendant du cliquet pour hors-dépôt (API appelées, dumps téléchargés, code repris), comparé à `.sources-baseline.json`. Écart **pas** faute : chose à regarder. → carte dans `docs/SOURCES.md`.

**Jamais lancer app ni capture depuis agent/sous-agent.** Vérif GUI déléguée à humain ; agents valident par succès build.

## Localisation

`assets/{en,fr}.json` = **source de vérité**. `build_app.py` valide **parité clés** entre les deux (build en erreur sinon) + génère `assets/*.lproj/Localizable.strings`. Clés référencées via `L10n.swift`.
→ Procédure complète : skill `localization`.

## Changelog & release

`CHANGELOG.md` suit **Keep a Changelog** ; incrémenté chaque release via `release.py`. → skill `release`.

## Traps — rappel par sujet (cavemem)

Pièges techniques détaillés, **chers à retrouver**, vivent dans cavemem (conventions larges : `AGENTS.md` §4 ; raisonnement ancien : `.kilo/plans/`). **Rappeler bloc AVANT toucher domaine**, pas après accident :

- SwiftUI / AppKit → `caveman mem recall "starhubfr traps swiftui"`
- Process, Pipe, système de fichiers → `caveman mem recall "starhubfr traps process"`
- Concurrence, caches, threads → `caveman mem recall "starhubfr traps concurrence"`
- Manifestes, i18n, Nexus, smapi.io, parsing → `caveman mem recall "starhubfr traps parsing"`
- Build, release, tests, cliquets → `caveman mem recall "starhubfr traps build"`
- UI, listes, sidebar, toggles de mods → `caveman mem recall "starhubfr traps ui"`

Sur hit, sortie = forme compacte ; `caveman mem recover <handle>` rend original octet pour octet.

## Git

Travailler sur `main`. **Pousser seulement si utilisateur demande.** **Fetch + rebase avant push** : autres sessions poussent aussi sur `main`, CI GitHub juge chaque push.

Terminer messages commit par trailer nommant **modèle ayant réellement écrit commit** — jamais nom figé :

- Claude : `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
  (ou `Claude Sonnet 5`, `Claude Haiku 4.5`… selon modèle actif).
- GLM : `Co-Authored-By: GLM 5.3 <noreply@z.ai>`.

⚠️ Dépôt travaillé par **plusieurs modèles**, dont GLM via `glm.sh` (route Claude Code vers API z.ai : modèle *actif* = GLM, quel que soit alias `sonnet`/`opus` affiché). Vérifier modèle actif avant signer.

Historique avant 2026-07-30 porte `Claude Sonnet 5` sur 167 commits, y compris ceux d'autres modèles : pas source de vérité.