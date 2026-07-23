---
name: build-app
description: Use when building or verifying a Swift change in StarHubFR — knows the split build gate (build_app.py vs swift build), the broken `swift test`, and how to verify logic without the GUI.
---

# Builder & vérifier StarHubFR

Le build est scindé. **Choisir le bon gate selon le fichier touché.**

## 1. Quel système couvre mon fichier ?

- **Core** (dans `Package.swift`) : `ModItem`, `ModConfigBackup(Manager)`,
  `ModInstallBackup(Manager)`, `SaveManager`, `DictionaryExtensions`, `ZipModInfo`,
  `Models/InventoryItem`, `L10n`. → validables par `swift build` / `./run_tests.sh`.
- **Tout le reste** (UI `Views/*`, `StarHubTHViewModel`, `SmapiInstaller`,
  `NexusUpdateChecker`, …) : compilé **uniquement** par `build_app.py`.

## 2. Builder

```bash
python3 build_app.py            # build réel de l'app (swiftc sur tous les .swift)
                                # régénère aussi compile_commands.json
python3 build_app.py --gen-compile-commands   # rafraîchir l'index LSP seul
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build   # Core seul
```

`python` n'est pas dans le PATH → toujours `python3`. Un build réussi = `[SUCCESS]`.

## 3. Tester

```bash
./run_tests.sh    # swift test (Core) avec DEVELOPER_DIR sur Xcode
```

Si `error: no such module 'Testing'` → **limite d'environnement** (Swift Testing
exige Xcode complet, pas seulement les Command Line Tools), **pas une régression**.
Ne pas traiter cet échec comme un bug de code.

### Vérifier de la logique que `swift test` ne peut pas atteindre

Compiler un harnais Swift autonome dans le scratchpad qui `import` directement le(s)
fichier(s) de production réels (les copier, pas des mocks) + un `main.swift` pilote,
puis exécuter le binaire. **Attention** : un binaire `swiftc` ad-hoc non signé ne
peut **pas** faire de réseau dans le sandbox (timeout) — ce n'est pas un bug du code.

## 4. Règle absolue

**Ne jamais lancer l'app ni prendre de capture d'écran depuis un agent/sous-agent.**
La vérification GUI est déléguée à l'humain ; les agents valident par build réussi.
