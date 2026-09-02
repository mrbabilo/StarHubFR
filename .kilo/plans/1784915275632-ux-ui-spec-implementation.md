# Plan d'implémentation — Spécification UX/UI StarHubFR (v2.0)

**Source :** `docs/UX_UI_Specifications.md` (spec v2.0, 1307 lignes)
**Base :** commit `a3937f6` (release 1.6.0)
**Découpage :** 5 phases → 5 PRs indépendantes, chacune déployable.

---

## Décisions de design arbitrées (corrigent la spec)

La spec v2.0 contient 3 inexactitudes techniques détectées par audit du code.
Le plan ci-dessous les corrige — **l'implémenteur suit ce plan, pas la spec
littérale** sur ces points.

| # | Spec dit | Réalité code | Décision retenue |
|---|----------|--------------|------------------|
| D1 | Tokens `AppDesign` (Font/Color/Spacing) dans `StarHubTH/Design/` | `StarHubTH/Design/` n'est pas dans le target SPM `StarHubTHCore` → non testable | **Split** : `Spacing`/`Radius`/`Opacity` (CGFloat/Double purs) → `StarHubTHCore`. `Font`/`Color` (SwiftUI) → app `StarHubTH/Design/` |
| D2 | 3 langues en/fr/th, éditer `.strings` | Seulement `assets/en.json` + `assets/fr.json`. `build_app.py` génère les `.strings`. Pas de th.json | **en + fr uniquement**. Nouvelles clés dans les 2 `.json`, jamais éditer les `.strings` générés |
| D3 | `MockStarHubTHViewModel: StarHubTHViewModel` pour tester l'UI | `StarHubTHViewModel` (145 Ko) hors SPM → non mockable | **Pas de mock ViewModel**. Composants UI validés visuellement. Tests SPM = tokens + ContrastChecker + InstallationError uniquement |
| D4 | `InstallationError` dans `StarHubTH/Models/` | Dossier app, non testable SPM | **Dans `StarHubTHCore`** (dépend de Foundation + L10n déjà présents) |

---

## Contraintes d'exécution (non-négociables)

1. **Zéro breaking change visuel** sur la migration tokens (diff = 0 pixel).
2. **Toute chaîne utilisateur** via `L10n.*` → clé ajoutée dans `en.json` **et** `fr.json` avant utilisation, sinon `build_app.py` casse.
3. **Pas de dépendance externe** ajoutée à `Package.swift`.
4. **macOS 14+** : APIs natives uniquement (`LazyVStack`, `.task(id:)`, `AsyncImage`).
5. Chaque commit compile (`swift build` côté SPM + build app via `build_app.py`).
6. Convention de clé JSON : `section_action_snake_case` (ex: `mods_open_details`).

---

## Phase 1 — Foundation (Design Tokens)

**Objectif :** créer les tokens, migrer les composants principaux sans diff visuel.

### Tâches ordonnées

1. **Créer `StarHubTH/AppDesignCore.swift`** (dans `StarHubTHCore`, donc à ajouter à `Package.swift` sources) :
   - `enum AppDesignCore` avec `Spacing` (CGFloat), `Radius` (CGFloat), `Opacity` (Double).
   - Valeurs EXACTES de la spec §3.1 : `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32` / `sm=6, md=8, section=10, lg=12` / `subtle=0.05, light=0.1, medium=0.15, strong=0.25, disabled=0.5, secondary=0.8`.
2. **Ajouter** `"AppDesignCore.swift"` au tableau `sources:` du target `StarHubTHCore` dans `Package.swift`.
3. **Créer `StarHubTH/Design/AppDesignUI.swift`** (côté app, import SwiftUI) :
   - `enum AppDesign` (sans le suffixe Core) qui `import` et réexporte `AppDesignCore.Spacing/Radius/Opacity`.
   - Ajoute `enum Font` et `enum Color` (cf. spec §3.1, valeurs déduites du grep : `iconXS=10, footnote=11, caption=12, body=13, rowTitle=14, headline=16, viewTitle=20`).
4. **Migrer `SharedComponents.swift`** (4 composants) : remplacer littéraux par `AppDesign.*`. Diff visuel attendu : **0**.
5. **Migrer `MainView.swift`** : `SidebarSectionHeader` (ligne 400) + `SidebarNavItem` (ligne 414). Ajouter le paramètre `icon` optionnel à `SidebarSectionHeader`. Mettre à jour les 3 sites d'appel (lignes ~155, ~199, ~224) avec icônes `gamecontroller`, `gearshape`, `globe.asia.australia`.
6. **Migrer `ModListView.swift`** : remplacer littéraux (~50 occurrences) par tokens.
7. **Créer `Tests/DesignSystemTests/`** + ajouter target dans `Package.swift` :
   - `DesignTokensTests.swift` : assert valeurs exactes (cf. spec §9.3).
   - `TokenMigrationTests.swift` : assert tokens ∈ valeurs historiquement utilisées.
8. **Vérifier** : `swift test --filter DesignSystemTests` passe. Build app via `build_app.py`. Diff visuel manuel (clair + sombre) sur Home, Mods, Saves.

### Critères de validation Phase 1
- [ ] `swift build` OK
- [ ] `swift test --filter DesignSystemTests` OK
- [ ] `python3 build_app.py` génère l'app sans erreur locales
- [ ] Captures d'écran avant/après identiques sur 3 vues principales
- [ ] 0 littéral `.system(size:` restant dans SharedComponents/MainView/ModListView

---

## Phase 2 — Correctifs UX ciblés

**Objectif :** corriger les 5 gaps de friction utilisateur (spec §5).

### Tâches ordonnées

1. **Clés L10n à ajouter** (dans `L10n.swift` + `en.json` + `fr.json`) :
   - `mods_open_details` / `mods_open_details_hint` (corrige le bug `ModListRow.swift:1067`)
   - `mod_install_empty_title` / `mod_install_empty_hint`
   - Vérifier d'abord que `mod_install_*` n'existent pas déjà (grep montre `mod_install_dep_required_missing` etc. — ne pas dupliquer).
2. **Créer `StarHubTH/Views/Components/`** (nouveau dossier).
3. **Créer `SystemStatusFooter.swift`** (spec §4.3) : lit `vm.mods`, `vm.outOfDateMods`, `vm.nexusUpdates`, `vm.smapiErrors`. Intégrer dans `MainView.swift` avant le `Spacer()` final (~ligne 248).
4. **Créer `EmptyStateDropZone.swift`** (spec §5.1) : intégrer dans la branche `if vm.mods.isEmpty` de `ModListView.swift` (~ligne 355).
5. **Dépendances manquantes cliquables** (spec §5.2) : modifier le bloc `missingDeps` de `ModListRow.swift` (~ligne 983) — chaque dépendance devient un `Button` ouvrant la recherche Nexus.
6. **Spinner toggle** (spec §5.3) : ajouter `@Published var pendingToggleFolder: String?` au ViewModel. Modifier le bloc toggle de `ModListRow.swift` (~ligne 1091) pour afficher un `ProgressView` quand `pendingToggleFolder == mod.folderName`.
7. **Corriger le bug tooltip** : `ModListRow.swift:1067` `L10n.Mods.viewOnNexus` → `L10n.Mods.openDetails` (nouvelle clé du point 1).
8. **Créer `InstallationError.swift` dans `StarHubTHCore`** (spec §5.4, mais emplacement corrigé par décision D4). Dépend de `L10n` (déjà dans le target). **Note** : `InstallationError.errorDescription` doit récupérer la langue courante — vérifier comment `L10n` accède à la langue sans ViewModel (probablement via `UserDefaults.standard.string(forKey:"currentLanguage")` + fallback "en"). Si `L10n` ne permet pas l'accès statique, créer un helper `AppLocale.current()` dans `StarHubTHCore`.
9. **Migrer `ModInstallView.swift`** (~ligne 79) pour utiliser `InstallationError` typé au lieu d'un `String` brut.
10. **Vérifier** : build + `build_app.py` (parité locales) + tests visuels manuels sur chaque gap.

### Critères de validation Phase 2
- [ ] `swift build` OK + `build_app.py` OK (parité en/fr respectée)
- [ ] `swift test` OK (InstallationError testable si tests ajoutés)
- [ ] 5 gaps testés manuellement : drop zone vide, dépendance cliquable ouvre Nexus, spinner apparaît pendant toggle, tooltip info.circle corrigé, message d'erreur d'installation typé
- [ ] `SystemStatusFooter` visible en bas de sidebar sans casser le layout

---

## Phase 3 — Accessibilité

**Objectif :** ajouter les labels VoiceOver + corriger les contrastes (spec §6).

### Tâches ordonnées

1. **Audit complet** : `grep -rn "accessibility" StarHubTH/Views/` doit toujours retourner 0 au départ. Lister tous les boutons icône-only.
2. **`ModListRow.swift`** : ajouter `.accessibilityElement(children: .combine)` + `.accessibilityLabel/Value/Hint` sur le HStack racine (spec §6.2.1).
3. **Boutons icône-only** : pattern systématique `.accessibilityLabel(...)` + `.accessibilityHint(...)` (spec §6.2.2). Prioriser ModListRow, MainView sidebar, SavesView toolbar.
4. **Toggles** : `.accessibilityLabel` + `.accessibilityValue` (spec §6.2.3).
5. **Créer `StarHubTHCore/ContrastChecker.swift`** (dans SPM pour testabilité) : implémentation réelle de `ratio()` + `relativeLuminance()` (spec §6.3, code fourni).
6. **Ajouter `"ContrastChecker.swift"`** aux sources `StarHubTHCore` dans `Package.swift`.
7. **Créer `Tests/DesignSystemTests/ContrastCheckerTests.swift`** : tests `blackOnWhite` (ratio 21), `secondaryOnWindow` (doit passer AA).
8. **Mesurer les paires critiques** (manuel via `ContrastChecker` ou Accessibility Inspector) : `.secondary`/`.windowBg`, `.error`/fond error 0.1, `.accent`/blanc. Documenter les résultats dans le PR.
9. **Vérifier** : `swift test --filter ContrastChecker` OK. Session VoiceOver manuelle sur parcours mod toggle + install.

### Critères de validation Phase 3
- [ ] `grep -rn "accessibilityLabel" StarHubTH/Views/ \| wc -l` ≥ 15 (était 0)
- [ ] `swift test --filter ContrastCheckerTests` OK
- [ ] Session VoiceOver : ModListRow annonce "nom, auteur, version, activé/désactivé"
- [ ] Tous les boutons icône-only ont un `accessibilityLabel`
- [ ] Rapport de contraste des 3 paires critiques documenté

---

## Phase 4 — Performance

**Objectif :** fluidité avec 100+ mods (spec §8).

### Tâches ordonnées

1. **Debounce recherche** (`ModListView.swift`) : ajouter `@State private var debouncedSearchText`. Remplacer `searchText` par `debouncedSearchText` dans `filteredMods`. Ajouter `.task(id: searchText)` avec sleep 200ms (spec §8.1).
2. **`LazyVStack` migration** (`ModListView.swift` ~ligne 292) : remplacer `VStack` par `LazyVStack`. **Attention** : `LazyVStack` change subtilement le comportement des `onAppear` des rows — vérifier que `pendingToggleFolder` et la pagination fonctionnent toujours.
3. **Créer `StarHubTH/Design/CachedAsyncImage.swift`** (côté app, SwiftUI) : wrapper `AsyncImage` avec `URLCache` partagé (spec §8.3).
4. **Migrer** les `AsyncImage` de `ModDetailView.swift` (~ligne 66) et les avatars vers `CachedAsyncImage`.
5. **Profiler** : avec 100+ mods (générer un jeu de test ou utiliser install réelle), mesurer avant/après via Instruments (Time Profiler sur le scroll + recherche).
6. **Vérifier** : aucun lag perceptible au scroll, recherche réagit après ≤200ms, images ne se re-téléchargent pas à la réouverture.

### Critères de validation Phase 4
- [ ] `swift build` OK
- [ ] Profiling Instruments : temps de premier rendu réduit (quantifier)
- [ ] Recherche debounced : pas de filtrage pendant la frappe, déclenchement à 200ms après arrêt
- [ ] Réouverture d'un ModDetail : image instantanée (cache)
- [ ] Pagination + LazyVStack cohabitent sans bug visuel

---

## Phase 5 — Internationalisation (clôture)

**Objectif :** finaliser toutes les nouvelles clés L10n et garantir la parité.

### Tâches ordonnées

1. **Inventaire exhaustif** : collecter toutes les nouvelles clés introduites en Phases 1-4 (Phase 2 en a déjà ~6). Vérifier qu'aucune chaîne littérale n'a fuité : `grep -rn 'Text("' StarHubTH/Views/ | grep -v 'verbatim:' | grep -v 'L10n\.'`.
2. **Pour chaque clé manquante** : ajouter dans `L10n.swift` (section appropriée) + `assets/en.json` + `assets/fr.json`. Convention : `section_action_snake_case`.
3. **Lancer `build_app.py`** : doit générer `assets/{en,fr}.lproj/Localizable.strings` sans erreur de parité.
4. **Vérification finale** : `python3 build_app.py` exit 0. `swift build` OK. `swift test` OK.
5. **Relecture FR** : s'assurer que les traductions françaises sont naturelles (pas du franglais).

### Critères de validation Phase 5
- [ ] `python3 build_app.py` exit 0 (parité en/fr respectée)
- [ ] `grep -rn 'Text("' StarHubTH/Views/ | grep -v 'verbatim:' | grep -v 'L10n\.'` retourne 0 ligne
- [ ] `swift build` + `swift test` OK
- [ ] Toutes les nouvelles chaînes ont une traduction FR cohérente

---

## Risques transverses et mitigations

| Risque | Phase(s) | Mitigation |
|--------|----------|------------|
| Régression visuelle migration tokens | 1 | Tests `TokenMigrationTests` + diff manuel. Si doute, garder l'ancien valeur dans un commit séparé pour A/B |
| Nouvelle clé L10n oublie une langue | 2, 5 | `build_app.py` casse le build (filet auto) — ne jamais commit sans l'avoir lancé |
| `LazyVStack` casse pagination/onAppear | 4 | Tester avec 50+ mods avant merge. Revert possible car isolé à ModListView |
| `pendingToggleFolder` race condition | 2 | Suivre le pattern optimiste existant `localIsOn` — ne pas inventer de nouvelle mécanique |
| `InstallationError` ne peut pas accéder à la langue sans VM | 2 | Décision D4 : créer `AppLocale.current()` helper dans StarHubTHCore si `L10n` ne suffit pas. Trancher au moment du codage |
| `SidebarSectionHeader` param `icon` breaking | 1 | Paramètre optionnel avec défaut `""` → compat arrière garantie |

---

## Commandes de validation globales (à lancer après chaque phase)

```bash
# Build SPM (couches logiques + tests)
swift build

# Tests SPM
swift test

# Build app complet (compile Views + génère .strings + valide parité locales)
python3 build_app.py

# Compter les littéraux ad-hoc restants (objectif global : -70%)
grep -rn "\.system(size:" StarHubTH/Views/ | wc -l

# Détecter les chaînes littérales interdites
grep -rn 'Text("' StarHubTH/Views/ | grep -v 'verbatim:' | grep -v 'L10n\.'
```

---

## Fichiers créés (récapitulatif final)

| Fichier | Côté | Phase | Testable SPM |
|---------|------|-------|--------------|
| `StarHubTH/AppDesignCore.swift` | SPM (`StarHubTHCore`) | 1 | ✅ |
| `StarHubTH/Design/AppDesignUI.swift` | App | 1 | ❌ (visuel) |
| `StarHubTH/ContrastChecker.swift` | SPM (`StarHubTHCore`) | 3 | ✅ |
| `StarHubTH/InstallationError.swift` | SPM (`StarHubTHCore`) | 2 | ✅ |
| `StarHubTH/Views/Components/SystemStatusFooter.swift` | App | 2 | ❌ (visuel) |
| `StarHubTH/Views/Components/EmptyStateDropZone.swift` | App | 2 | ❌ (visuel) |
| `StarHubTH/Design/CachedAsyncImage.swift` | App | 4 | ❌ (visuel) |
| `Tests/DesignSystemTests/DesignTokensTests.swift` | SPM | 1 | — |
| `Tests/DesignSystemTests/TokenMigrationTests.swift` | SPM | 1 | — |
| `Tests/DesignSystemTests/ContrastCheckerTests.swift` | SPM | 3 | — |

## Fichiers modifiés (principaux)

| Fichier | Phases |
|---------|--------|
| `Package.swift` (ajout sources + target test) | 1, 2, 3 |
| `StarHubTH/L10n.swift` | 2, 5 |
| `assets/en.json`, `assets/fr.json` | 2, 5 |
| `StarHubTH/Views/SharedComponents.swift` | 1 |
| `StarHubTH/Views/MainView.swift` | 1, 2 |
| `StarHubTH/Views/ModListView.swift` | 1, 2, 4 |
| `StarHubTH/Views/ModDetailView.swift` | 1, 4 |
| `StarHubTH/StarHubTHViewModel.swift` | 2 |
| `StarHubTH/Views/ModInstallView.swift` | 2 |

---

## Questions ouvertes (à trancher pendant l'implémentation, non-bloquantes)

1. **Phase 2, point 8** : `L10n` permet-il l'accès statique à la langue courante sans ViewModel ? Si non, créer `AppLocale.current()`. À vérifier au moment du codage de `InstallationError`.
2. **Phase 4** : le jeu de test "100+ mods" — générer des dossiers factices dans `Mods_disabled/` pour le profiling, ou utiliser une install réelle ? Préférer la génération scriptée pour la reproductibilité.
3. **Phase 5** : certaines clés `mod_install_*` existent déjà (ex: `mod_install_dep_required_missing`). L'implémenteur doit vérifier au cas par cas pour ne pas dupliquer.
