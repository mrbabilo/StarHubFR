# Contribuer à StarHubFR

*[English version below](#contributing-to-starhubfr).*

Merci de votre intérêt pour StarHubFR, gestionnaire de mods Stardew Valley natif pour macOS. Ce guide dit comment signaler un problème, proposer une idée et faire accepter un changement de code.

## Signaler, proposer, demander

Ouvrez une [issue](../../issues/new/choose) et choisissez le modèle qui correspond :

- **Bug de l'app** — un écran, un bouton ou une donnée qui ne va pas.
- **SMAPI ou installation de mod** — une archive qui ne s'installe pas, un jeu qui ne démarre plus.
- **Mod non détecté** — un mod absent de la liste, ou avec un mauvais nom, une mauvaise version.
- **Idée** — une fonction qui manque.
- **Question** — tout le reste.

Cherchez d'abord dans les [issues existantes](../../issues?q=is%3Aissue) : un doublon fait perdre du temps à tout le monde.

**Une faille de sécurité ne s'ouvre jamais en issue publique** : voir [SECURITY.md](SECURITY.md).

## Traductions

Deux choses distinctes portent ce nom :

- **L'interface de l'app** (anglais et français) vit dans `assets/en.json` et `assets/fr.json`. Une correction de libellé est une contribution bienvenue : même clé dans les deux fichiers, français avec tous ses accents.
- **Les traductions de mods** ne sont pas hébergées ici. L'onglet Traduction de l'app écrit le `fr.json` d'un mod sur votre Mac ; pour partager une traduction, publiez-la sur Nexus Mods avec l'accord de l'auteur du mod.

## Préparer l'environnement

- macOS 14 ou ultérieur.
- **Xcode 16.4** complet, la version de la CI. Les seuls Command Line Tools ne suffisent pas.
- Python 3, appelé `python3`.

Si `xcode-select -p` pointe sur `/Library/Developer/CommandLineTools`, la compilation échoue sur `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`, répété sur chaque `@State`. Ce n'est pas une erreur de code. Préfixez la commande :

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 build_app.py
```

## Compiler et tester

```bash
python3 build_app.py; echo "exit=$?"   # compile toute l'app, vérifie les conventions, produit StarHubFR.app
./run_tests.sh                         # tests du cœur (Swift Testing)
./run_tests.sh --filter Keybind        # une seule famille de tests
```

- Il n'y a pas de projet Xcode. `build_app.py` compile toutes les sources de `StarHubTH/` ; c'est le vrai contrôle d'un changement.
- `Package.swift` ne décrit que le **cœur** testable (modèles, magasins, analyseurs). Les vues et le ViewModel ne s'y compilent pas, donc ne se testent pas.
- Lisez le code de sortie de `build_app.py` directement : `python3 build_app.py | tail` rend celui de `tail`, vert même en cas d'échec.

## Règles du code

- **Une logique pure va dans le cœur** (`StarHubTH/Models/`, déclarée dans `Package.swift`), avec ses tests. Un état partagé va dans son propre magasin (`StarHubTH/Stores/`). Rien de neuf n'entre dans `StarHubTHViewModel`.
- **Cliquet des conventions** : `check_standards.py`, lancé par `build_app.py`, échoue si un compteur augmente — fichier de plus de 400 lignes (taille verrouillée fichier par fichier), abréviation `vm`, nouveau `DispatchQueue`, nouveau singleton `.shared`. `python3 check_standards.py --report` donne l'état.
- **Localisation** : chaque libellé existe dans `assets/en.json` et `assets/fr.json`, avec la même clé, référencé via `L10n.swift`. Le build échoue si les deux fichiers divergent.
- **Vocabulaire métier** : lisez [`docs/DOMAINE.md`](docs/DOMAINE.md) avant de toucher aux mods, profils, sauvegardes ou traductions. Un mod en pause est un dossier préfixé d'un point (`Mods/.X`), jamais un dossier déplacé.
- **Les tests n'écrivent jamais dans le vrai dossier de l'app** (`~/Library/Application Support/StarHubFR/`) : un magasin testé reçoit un dossier temporaire.
- Pas de nouvelle dépendance externe sans en discuter d'abord dans une issue.
- **Le guide utilisateur fait partie de l'app** : la fenêtre d'aide affiche `GUIDE.md` et `GUIDE_EN.md`. Un écran qui change de libellé ou de geste change les deux guides ; chaque section garde son marqueur `<!-- help: id -->`, sinon le build échoue.

La carte du code — couches, flux, données sur disque, outillage — est dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Les pièges techniques connus (SwiftUI, processus, concurrence, analyse des manifestes) sont consignés dans [`AGENTS.md`](AGENTS.md), section 4.

## Proposer une pull request

1. Pour un changement important, ouvrez d'abord une issue : on se met d'accord avant que vous écriviez le code.
2. Forkez, puis créez une branche depuis `main`.
3. Un commit par changement logique, au format `type(portée): description` — par exemple `fix(raccourcis): …`, `feat(performances): …`, `docs(readme): …`. Français ou anglais.
4. Ajoutez une ligne au `CHANGELOG.md`, sous `## [Unreleased]`, en français : ce qui change pour l'utilisateur, en moins de 300 caractères.
5. Joignez une capture d'écran si l'interface change, en français et à la largeur minimale de la fenêtre si possible.
6. La CI (Xcode 16.4) doit être verte. Elle compile le cœur, lance les tests et vérifie les conventions, mais ne compile pas l'app entière : `python3 build_app.py` en local reste indispensable.

Si un assistant IA a écrit un commit, terminez son message par un trailer `Co-Authored-By:` qui nomme le modèle réellement utilisé.

## Comportement

Soyez bienveillant et patient : les personnes qui ouvrent une issue ont des niveaux techniques très variés. Une critique porte sur le code, jamais sur la personne.

---

# Contributing to StarHubFR

Thanks for your interest in StarHubFR, a native macOS mod manager for Stardew Valley. The French section above is the reference; this is a summary.

## Report, suggest, ask

Open an [issue](../../issues/new/choose) and pick a template: **App bug**, **SMAPI or mod install**, **Mod not detected**, **Feature idea** or **Question**. Search [existing issues](../../issues?q=is%3Aissue) first. **Never report a security flaw in a public issue**: see [SECURITY.md](SECURITY.md).

## Translations

- **The app's interface** lives in `assets/en.json` and `assets/fr.json`. Wording fixes are welcome: same key in both files.
- **Mod translations** are not hosted here. The app's Translation tab writes a mod's `fr.json` on your Mac; to share one, publish it on Nexus Mods with the mod author's consent.

## Set up, build, test

You need macOS 14+, full **Xcode 16.4** (the CI version; Command Line Tools alone are not enough) and `python3`.

```bash
python3 build_app.py; echo "exit=$?"   # builds the whole app, checks conventions
./run_tests.sh                         # core tests (Swift Testing)
```

If the build fails on `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`, the active toolchain is the Command Line Tools: prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. There is no Xcode project; `Package.swift` only covers the testable core.

## Code rules

- Pure logic goes into the core (`StarHubTH/Models/`, listed in `Package.swift`) with tests; shared state gets its own store (`StarHubTH/Stores/`). Nothing new goes into `StarHubTHViewModel`.
- `check_standards.py` fails when a counter grows: files over 400 lines (locked per file), the `vm` abbreviation, new `DispatchQueue`, new `.shared` singletons.
- Every UI string exists in both `assets/en.json` and `assets/fr.json` under the same key; the build fails otherwise.
- Read [`docs/DOMAINE.md`](docs/DOMAINE.md) before touching mods, profiles, saves or translations. A paused mod is a dot-prefixed folder (`Mods/.X`).
- Tests never write to the real `~/Library/Application Support/StarHubFR/`.
- The code map (layers, flows, on-disk data, tooling) is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), in French; known pitfalls are in [`AGENTS.md`](AGENTS.md), section 4.
- The user guide is part of the app: the help window shows `GUIDE.md` and `GUIDE_EN.md`. A screen whose labels or gestures change updates both guides; each section keeps its `<!-- help: id -->` marker or the build fails.

## Pull requests

Discuss large changes in an issue first. Branch from `main`, one commit per logical change (`type(scope): description`), add a line under `## [Unreleased]` in `CHANGELOG.md` (in French, user-facing), attach a screenshot for UI changes, and make sure CI is green. CI builds the core, runs the tests and checks conventions, but does not build the whole app: run `python3 build_app.py` locally. If an AI assistant wrote a commit, end it with a `Co-Authored-By:` trailer naming the model actually used.
