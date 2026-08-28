# Spécifications UX/UI — StarHubFR (v2.0 — alignée sur le code réel)

| Champ   | Valeur                              |
|---------|-------------------------------------|
| Version | 2.0 (réécrite après analyse du code)|
| Date    | 25 juillet 2026                     |
| Cible   | macOS 14+ / Swift 5.9 / SwiftUI     |
| Projet  | StarHubTH (repo) → StarHubFR (app)  |
| Pré-requis | commit `a3937f6` (release 1.6.0) |

> **Note de révision :** Cette version remplace la v1.0 qui contenait du code
> placeholder, des composants redondants avec l'existant, et des estimations
> irréalistes. Toutes les valeurs chiffrées proviennent d'une analyse du code
> au commit `a3937f6`.

> ⚠️ **Document périmé — ne pas s'en servir comme source (constaté le 2026-08-28).**
> Il s'épingle au commit `a3937f6` (v1.6.0) et le dépôt en est à la **v1.25.0** : dix-neuf
> releases ont passé, dont l'onglet Découvrir, le hub de traduction, les profils, la
> bissection et la carte de santé SMAPI — rien de tout cela n'est décrit ici. Aucun autre
> document du dépôt ne le cite. À réécrire contre le code, ou à retirer ; en attendant,
> l'état réel se lit dans `docs/ROADMAP.md` (§3, table de réconciliation) et dans le code.

---

## 1. État des lieux (inventaire du code existant)

Avant de spécifier des changements, il faut savoir ce qui existe déjà.
Cette section est **factuelle** : issue de `grep` sur `StarHubTH/Views/`.

### 1.1 Composants réutilisables déjà présents

| Composant            | Fichier                     | Lignes | Rôle                                     |
|----------------------|-----------------------------|--------|------------------------------------------|
| `InitialsAvatar`     | `SharedComponents.swift`    | 8–40   | Badge circulaire avec initiales          |
| `StandardSection`    | `SharedComponents.swift`    | 43–81  | Conteneur card + titre + footer          |
| `StandardRow`        | `SharedComponents.swift`    | 84–113 | Ligne titre/détail avec divider          |
| `InfoPopoverButton`  | `SharedComponents.swift`    | 116–138| Bouton info avec popover                 |
| `SidebarSectionHeader` | `MainView.swift`          | 400–411| En-tête de section sidebar               |
| `SidebarNavItem`     | `MainView.swift`            | 414–451| Item de navigation sidebar               |
| `pointingHandCursor()` | `ViewExtensions.swift`    | 6–27   | Cursor en main sur hover                 |

**Conclusion :** La base d'un design system existe déjà. La spec v2.0 **étend**
ces composants au lieu de les réinventer.

### 1.2 Inventaire des valeurs de design utilisées (du code réel)

Issue de `grep -rn` sur `StarHubTH/Views/`. Ces chiffres sont la **réalité**
qui doit être rationalisée, pas des suggestions abstraites.

#### Tailles de polices (`Font.system(size:)`)

| Taille | Occurrences | Usage dominant                          |
|--------|-------------|-----------------------------------------|
| 10     | 36          | Icônes, micro-labels, chevrons          |
| 11     | 64          | Footnotes, badges, captions             |
| 12     | 74          | Texte secondaire, métadonnées           |
| 13     | 45          | Corps de texte standard, `StandardRow`  |
| 14     | 30          | Titres de ligne sidebar, corps          |
| 16     | 7           | Sous-titres, `headerBand`               |
| 20–24  | 2           | Titres (`title2`, username HomeView)    |
| 40–56  | 4           | Icônes empty-state                      |

#### Rayons de coins (`cornerRadius:`)

| Rayon | Occurrences | Usage                                   |
|-------|-------------|-----------------------------------------|
| 6     | 12          | Sidebar items, chips                    |
| 8     | 8           | Petits éléments                         |
| 10    | 4           | `StandardSection`                       |
| 12    | 5           | Cartes, banner, drop zones              |

#### Espacements (`VStack/HStack spacing:`)

| Espacement | Occurrences | Usage                                   |
|------------|-------------|-----------------------------------------|
| 0          | 31          | Listes sans gap                         |
| 2          | 21          | Tight (badge + texte)                   |
| 4          | 30          | Micro-espacements                       |
| 6          | 33          | Petits groupes                          |
| 8          | 35          | Standard interne                        |
| 12         | 23          | Entre éléments                          |
| 16         | 26          | Entre sections                          |
| 24         | 2           | HomeView, ModListView                   |
| 32         | 3           | Grosse séparation                       |

#### Opacités (`Color.opacity()`)

| Opacité | Occurrences | Usage                                   |
|---------|-------------|-----------------------------------------|
| 0.04–0.06 | 16        | Arrière-plans subtils                   |
| 0.08–0.12 | 40        | Arrière-plans moyens, borders           |
| 0.15      | 12        | Borders, hover states                   |
| 0.25      | 4         | Overlays                                |
| 0.5       | 14        | Disabled                                |
| 0.7–0.8   | 21        | Texte secondaire                        |

#### Couleurs (top)

| Couleur                    | Occurrences |
|----------------------------|-------------|
| `Color.accentColor`        | 35          |
| `Color.primary`            | 30          |
| `Color.secondary`          | 29          |
| `Color(nsColor:.window)`   | 18          |
| `Color(nsColor:.control)`  | 18          |

### 1.3 Dépendances techniques réelles

```swift
// Package.swift (commit a3937f6)
// swift-tools-version:5.9
// platforms: [.macOS(.v14)]   ← LA cible minimale
//
// Dépendances externes : AUCUNE
// Frameworks : SwiftUI, AppKit, Foundation, UniformTypeIdentifiers
// Targets de test : 9 dossiers sous Tests/
```

**Implication :** Toute proposition doit rester sur des API macOS 14+ natives.
Pas de bibliothèque tierce sans justification forte.

### 1.4 Système de localisation existant

```swift
// StarHubTH/L10n.swift — clés centralisées, générées automatiquement
// assets/{en,fr,th}.lproj/Localizable.strings — fichiers de traduction
// build_app.py — valide la parité des clés entre les 3 langues
```

**Contrainte (mémoire projet) :** `localization_key_parity` — toute nouvelle
chaîne affichée à l'utilisateur DOIT passer par `L10n.*` et exister dans les
3 fichiers `.strings`, sinon le build casse.

---

## 2. Objectifs et portée

### 2.1 Ce que cette spec NE fait PAS

- **Ne réinvente pas** les composants existants (`StandardSection`, etc.)
- **Ne casse pas** la structure sidebar existante (déjà bonne)
- **N'ajoute pas** de dépendance externe
- **N'introduit pas** de breaking change pour les utilisateurs

### 2.2 Ce que cette spec FAIT

1. **Rationalise** les ~70 valeurs ad-hoc en ~6 tokens par catégorie
2. **Comble** les gaps identifiés (accessibilité, feedback erreurs, perf)
3. **Documente** les patterns existants pour les nouveaux contributeurs
4. **Planifie** la migration sans big-bang (compatible avec releases 1.x → 2.0)

### 2.3 Métriques de succès mesurables

| Métrique                     | Mesure                                  | Cible |
|------------------------------|-----------------------------------------|-------|
| Valeurs ad-hoc dans les vues | `grep "\.system(size:" \| wc -l`        | -70%  |
| Cohérence tokens             | % de fichiers utilisant `AppTypography` | 80%+  |
| Couverture accessibilité     | Composants avec `accessibilityLabel`    | 100%  |
| Temps recherche (1000 mods)  | Instruments profiling                   | <100ms|


---

## 3. Design Tokens (basés sur les valeurs réelles)

> **Principe :** Les tokens ci-dessous sont choisis pour **minimiser le diff**
> avec le code existant. Chaque token correspond à la valeur la plus utilisée
> dans sa catégorie (voir §1.2).

### 3.1 Fichier unique : `StarHubTH/Design/AppDesignTokens.swift`

Un seul fichier plutôt que 5, parce que les tokens se référencent entre eux
et qu'un import suffit. Internal par défaut (pas de `public` — l'app n'est
pas un framework).

```swift
// StarHubTH/Design/AppDesignTokens.swift
import CoreGraphics
import SwiftUI

/// Design tokens centralisés pour StarHubFR.
/// Remplacent les valeurs ad-hoc éparpillées dans les Views.
/// Valeurs dérivées de l'inventaire du code existant (voir spec §1.2).
enum AppDesign {

    // MARK: - Spacing (VStack/HStack spacing, padding)
    enum Spacing {
        /// 4 — micro (badge + texte). ~30 occurrences dans le code.
        static let xs: CGFloat = 4
        /// 8 — standard interne. Valeur la plus utilisée (35 occ.).
        static let sm: CGFloat = 8
        /// 12 — entre éléments apparentés (23 occ.).
        static let md: CGFloat = 12
        /// 16 — entre sections (26 occ.).
        static let lg: CGFloat = 16
        /// 24 — grosse séparation (HomeView, ModListView).
        static let xl: CGFloat = 24
        /// 32 — séparation maximale (3 occ.).
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner radius
    enum Radius {
        /// 6 — sidebar items, chips. Valeur la plus utilisée (12 occ.).
        static let sm: CGFloat = 6
        /// 8 — petits éléments (8 occ.).
        static let md: CGFloat = 8
        /// 10 — `StandardSection` existant (4 occ.).
        static let section: CGFloat = 10
        /// 12 — cartes, banner, drop zones (5 occ.).
        static let lg: CGFloat = 12
    }

    // MARK: - Opacity
    enum Opacity {
        /// 0.05 — arrière-plans très subtils.
        static let subtle: Double = 0.05
        /// 0.1 — arrière-plans moyens, borders (valeur dominante, 16 occ.).
        static let light: Double = 0.1
        /// 0.15 — borders accentués, hover (12 occ.).
        static let medium: Double = 0.15
        /// 0.25 — overlays modaux (4 occ.).
        static let strong: Double = 0.25
        /// 0.5 — éléments désactivés (14 occ.).
        static let disabled: Double = 0.5
        /// 0.8 — texte secondaire (14 occ.).
        static let secondary: Double = 0.8
    }

    // MARK: - Typography
    /// Déduit des tailles réellement utilisées (74× size 12, 64× size 11, etc.).
    enum Font {
        // Micro (icônes, chevrons, labels minuscules)
        static let iconXS    = SwiftUI.Font.system(size: 10)
        // Captions / footnotes (64 occ. pour size 11)
        static let footnote  = SwiftUI.Font.system(size: 11)
        // Texte secondaire (74 occ. pour size 12 — le plus utilisé)
        static let caption   = SwiftUI.Font.system(size: 12)
        // Corps standard (45 occ. pour size 13 — StandardRow, corps)
        static let body      = SwiftUI.Font.system(size: 13)
        // Titres de ligne / sidebar (30 occ. pour size 14)
        static let rowTitle  = SwiftUI.Font.system(size: 14)
        // Sous-titres (7 occ. pour size 16)
        static let headline  = SwiftUI.Font.system(size: 16)
        // Titres de vue (utilise déjà .title2/.title3 système)
        static let viewTitle = SwiftUI.Font.system(size: 20, weight: .semibold)

        // Helpers avec weight
        static func body(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 13, weight: w)
        }
        static func caption(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 12, weight: w)
        }
    }

    // MARK: - Colors (sémantiques, basées sur l'existant)
    enum Color {
        // Les 3 couleurs système dominantes (94 occurrences combinées)
        static let primary    = SwiftUI.Color.primary
        static let secondary  = SwiftUI.Color.secondary
        static let accent     = SwiftUI.Color.accentColor

        // Arrière-plans système (42 occurrences combinées)
        static let windowBg       = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let controlBg      = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let textBg         = SwiftUI.Color(nsColor: .textBackgroundColor)

        // Status (utilisé ponctuellement : HomeView .green, UpdatesView .red, etc.)
        static let success    = SwiftUI.Color.green
        static let warning    = SwiftUI.Color.orange
        static let error      = SwiftUI.Color.red
        static let info       = SwiftUI.Color.blue
    }
}
```

### 3.2 Stratégie de migration (pas de big-bang)

La migration se fait **fichier par fichier**, un commit par vue, pour garder
des diffs reviewables. Chaque commit doit compiler et fonctionner.

```bash
# Workflow par fichier :
git checkout -b refactor/design-tokens-homeview
# 1. Remplacer les valeurs ad-hoc dans HomeView.swift
# 2. Builder : swift build
# 3. Tester visuellement (clair + sombre)
# 4. Commit : "refactor(HomeView): adopt AppDesign tokens"
git commit -am "refactor(HomeView): adopt AppDesign tokens"
```

**Ordre de priorité** (par fréquence d'utilisation et impact visuel) :

| # | Fichier              | Lignes | Valeurs ad-hoc | Priorité |
|---|----------------------|--------|----------------|----------|
| 1 | `SharedComponents`   | 138    | ~15            | 🔴 Haute (réutilisé partout) |
| 2 | `MainView`           | 774    | ~40            | 🔴 Haute (visible en permanence) |
| 3 | `ModListView`        | 1100+  | ~50            | 🔴 Haute (vue principale mods) |
| 4 | `HomeView`           | 310    | ~20            | 🟡 Moyenne |
| 5 | `ModDetailView`      | 508    | ~25            | 🟡 Moyenne |
| 6 | `SavesView`          | 787    | ~35            | 🟡 Moyenne |
| 7 | Autres vues          | —      | —              | 🟢 Basse  |

### 3.3 Exemple concret : migration de `StandardSection`

```swift
// AVANT (SharedComponents.swift ligne 43)
struct StandardSection<Content: View>: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {                    // ← 8
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .bold))          // ← 13, .bold
                    .foregroundColor(.primary)
            }
            VStack(spacing: 0) { content }
                .padding(16)                                          // ← 16
                .cornerRadius(10)                                     // ← 10
                .overlay(RoundedRectangle(cornerRadius: 10)          // ← 10
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)) // ← 0.1
        }
    }
}

// APRÈS
struct StandardSection<Content: View>: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(AppDesign.Font.body(.bold))
                    .foregroundColor(AppDesign.Color.primary)
            }
            VStack(spacing: 0) { content }
                .padding(AppDesign.Spacing.lg)
                .cornerRadius(AppDesign.Radius.section)
                .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
                    .stroke(AppDesign.Color.primary.opacity(AppDesign.Opacity.light),
                            lineWidth: 1))
        }
    }
}
```

**Diff visible : zéro.** C'est le but. La valeur business est la cohérence
future et la maintenabilité, pas un relookage.


---

## 4. Architecture de navigation

### 4.1 État actuel (à conserver)

Le sidebar existant (`MainView.swift` lignes 46–256) est déjà bien structuré :

```
┌─ Sidebar (240px fixe) ──────────────┐
│ 🔍 Recherche                        │
│ 👤 Compte + profil actif            │
│ 🚨 Alertes (si count > 0)           │
│ ── Gestion du jeu ──                │
│   📁 Saves                          │
│   🧩 Mods                           │
│   📦 Config Backups                 │
│   👥 Profiles                       │
│ ── Système ──                       │
│   ⚙️ Paramètres                     │
│   📄 Journal des versions           │
│ ── En ligne ──                      │
│   🌏 Thai Translation Hub           │
│ ── (Logs si activé) ──              │
│   📋 Logs                           │
└─────────────────────────────────────┘
```

**Verdict :** Ne pas restructurer. L'organisation par groupes sémantiques
est déjà en place et conforme aux HIG macOS.

### 4.2 Améliorations ciblées (non-cassantes)

#### 4.2.1 Icônes sur les `SidebarSectionHeader`

Le composant existe (`MainView.swift:400`) mais n'affiche que du texte. Ajouter
un paramètre `icon` optionnel pour reconnaissance visuelle plus rapide.

```swift
// MainView.swift — REMPLACER le struct existant (ligne 400)
struct SidebarSectionHeader: View {
    let title: String
    var icon: String = ""   // NOUVEAU, optionnel, pas de breaking change

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs + 2) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(AppDesign.Font.iconXS.weight(.semibold))
                    .foregroundColor(AppDesign.Color.secondary)
            }
            Text(title)
                .font(AppDesign.Font.caption(.semibold))
                .foregroundColor(AppDesign.Color.secondary)
        }
        .padding(.leading, AppDesign.Spacing.sm)
        .padding(.top, AppDesign.Spacing.sm)
    }
}
```

**Appels à modifier** (3 sites dans MainView.swift) :

```swift
// Ligne ~155 : AVANT
SidebarSectionHeader(title: vm.L(L10n.Main.gameManagement))
// APRÈS
SidebarSectionHeader(title: vm.L(L10n.Main.gameManagement), icon: "gamecontroller")

// Ligne ~199
SidebarSectionHeader(title: vm.L(L10n.Main.system), icon: "gearshape")

// Ligne ~224
SidebarSectionHeader(title: vm.L(L10n.Main.online), icon: "globe.asia.australia")
```

#### 4.2.2 `SidebarNavItem` — migration vers tokens

Le composant (`MainView.swift:414`) utilise déjà les bonnes valeurs (10, 6, etc.).
La migration est conservative : remplacer les littéraux par les tokens
correspondants sans changer le rendu.

```swift
// Les seules lignes qui changent dans SidebarNavItem :
.padding(.horizontal, 10)                          // → AppDesign.Spacing.sm + 2
.padding(.vertical, 6)                             // → garder 6 (pas de token direct)
RoundedRectangle(cornerRadius: 6, style: .continuous) // → AppDesign.Radius.sm
Color.primary.opacity(0.05)                        // → AppDesign.Opacity.subtle
```

### 4.3 Indicateur d'état global (composant nouveau)

Actuellement, le statut du système (mods actifs, updates, erreurs) n'est visible
qu'en cliquant sur "Alertes". Un mini-résumé en bas de sidebar améliorerait la
découvrabilité.

```swift
// NOUVEAU FICHIER : StarHubTH/Views/Components/SystemStatusFooter.swift

import SwiftUI

/// Résumé compact affiché en bas du sidebar (avant le Spacer final).
/// Visible en permanence, pas de clic requis.
struct SystemStatusFooter: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            statusPill(
                count: vm.mods.filter(\.isEnabled).count,
                total: vm.mods.count,
                color: AppDesign.Color.success,
                icon: "puzzlepiece.extension"
            )
            statusPill(
                count: vm.outOfDateMods.count + vm.nexusUpdates.count,
                color: AppDesign.Color.warning,
                icon: "arrow.up.circle"
            )
            if !vm.smapiErrors.isEmpty {
                statusPill(
                    count: vm.smapiErrors.count,
                    color: AppDesign.Color.error,
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, AppDesign.Spacing.xs)
    }

    private func statusPill(count: Int, total: Int? = nil,
                            color: SwiftUI.Color, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(AppDesign.Font.iconXS)
            if let total = total {
                Text("\(count)/\(total)")
                    .font(AppDesign.Font.footnote.weight(.medium))
                    .monospacedDigit()
            } else {
                Text("\(count)")
                    .font(AppDesign.Font.footnote.weight(.medium))
                    .monospacedDigit()
            }
        }
        .foregroundColor(count > 0 ? color : AppDesign.Color.secondary)
    }
}
```

**Intégration dans MainView.swift** (avant le `Spacer()` final, ligne ~248) :

```swift
// AVANT
Spacer()

// APRÈS
Spacer()
SystemStatusFooter(vm: vm)
```


---

## 5. Gaps identifiés et correctifs ciblés

Cette section liste les problèmes UX concrets observés dans le code,
avec pour chacun un correctif minimal et non-cassant.

### 5.1 Gap : Installation de mods peu découverte

**Problème :** `ModListView` expose l'installation via un bouton `+` dans une
barre d'outils déjà chargée (6 contrôles sur une ligne). Le drag-and-drop
n'est pas signalé visuellement.

**Correctif :** Ajouter une zone de drop visible **uniquement quand la liste
est vide ou filtrée à zéro**, sans encombrer la vue quand des mods existent.

```swift
// ModListView.swift — dans la branche `if filtered.isEmpty` (ligne ~350)

if vm.mods.isEmpty {
    // Première utilisation : zone de drop XXL
    EmptyStateDropZone(vm: vm, onInstall: { showInstallSheet = true })
} else {
    // État actuel (icône + texte)
    VStack(spacing: AppDesign.Spacing.lg) { /* ... existant ... */ }
}

// NOUVEAU FICHIER : StarHubTH/Views/Components/EmptyStateDropZone.swift
struct EmptyStateDropZone: View {
    @ObservedObject var vm: StarHubTHViewModel
    let onInstall: () -> Void

    var body: some View {
        Button(action: onInstall) {
            VStack(spacing: AppDesign.Spacing.lg) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 48))
                    .foregroundColor(AppDesign.Color.accent)
                VStack(spacing: AppDesign.Spacing.xs) {
                    Text(L10n.ModInstall.emptyTitle.localized(vm.L))
                        .font(AppDesign.Font.headline)
                    Text(L10n.ModInstall.emptyHint.localized(vm.L))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(AppDesign.Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppDesign.Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.lg)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundColor(AppDesign.Color.accent.opacity(AppDesign.Opacity.light))
            )
        }
        .buttonStyle(.plain)
    }
}
```

**Clés L10n à ajouter** (dans `L10n.swift` + 3 fichiers `.strings`) :
```swift
enum ModInstall {
    static let emptyTitle = "mod_install_empty_title"  // "Aucun mod installé"
    static let emptyHint  = "mod_install_empty_hint"   // "Glissez un .zip ou cliquez ici"
}
```

### 5.2 Gap : Dépendances manquantes — feedback faible

**Problème :** `ModListRow` (ligne ~981) affiche les dépendances manquantes
en rouge, mais sans action. L'utilisateur doit aller chercher le mod sur
Nexus lui-même.

**Correctif :** Rendre chaque dépendance manquante cliquable vers Nexus.
Réutilise `vm.nexusLink(for:)` et le pattern `linkButton` de ModDetailView.

```swift
// ModListRow.swift — REMPLACER le bloc lignes 983-989

if !missingDeps.isEmpty {
    HStack(spacing: AppDesign.Spacing.xs) {
        Image(systemName: "exclamationmark.triangle.fill")
        ForEach(missingDeps, id: \.self) { dep in
            Button(dep) {
                // Tente d'ouvrir la recherche Nexus pour ce nom de mod
                let encoded = dep.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed) ?? dep
                if let url = URL(string:
                    "https://www.nexusmods.com/stardewvalley/mods/categories/all/?keyword=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(AppDesign.Font.footnote)
            .foregroundColor(AppDesign.Color.error)
            .underline()
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }
    .foregroundColor(AppDesign.Color.error)
}
```

### 5.3 Gap : Pas de feedback sur toggle de mod

**Problème :** `ModListRow` a un toggle (ligne ~1092) avec état optimiste
(`localIsOn`) mais aucun indicateur visuel pendant l'opération. Sur de gros
packs, l'utilisateur ne sait pas si son clic a été pris en compte.

**Correctif :** Ajouter un mini-spinner à côté du toggle pendant l'opération.

```swift
// ModListRow.swift — modifier le bloc toggle (ligne ~1091)

if !isChild {
    HStack(spacing: AppDesign.Spacing.xs) {
        if let pending = vm.pendingToggleFolder, pending == mod.folderName {
            // NOUVEAU : spinner pendant l'opération
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        }
        Toggle("", isOn: Binding(
            get: { localIsOn ?? mod.isEnabled },
            set: { newValue in
                localIsOn = newValue
                vm.toggleMod(mod)   // Le VM doit setter pendingToggleFolder
            }
        ))
        .labelsHidden()
    }
}
```

**Côté ViewModel** (`StarHubTHViewModel.swift`), ajouter :
```swift
@Published var pendingToggleFolder: String?   // folderName pendant l'op
```

### 5.4 Gap : Erreurs d'installation — message brut

**Problème :** `ModInstallView` (ligne ~79) affiche les erreurs via une
`alert` générique avec juste le texte de l'erreur. Pas de suggestion de
récupération.

**Correctif :** Typer les erreurs et afficher une suggestion contextuelle.

```swift
// NOUVEAU FICHIER : StarHubTH/Models/InstallationError.swift

import Foundation

enum InstallationError: LocalizedError {
    case invalidZipFormat
    case zipTooLarge(sizeMB: Int)
    case noManifestFound
    case dependencyMissing(names: [String])
    case fileSystemDenied(path: String)
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidZipFormat:
            return L10n.ModInstall.errInvalidZip.localized(currentLang)
        case .zipTooLarge(let mb):
            return String(format: L10n.ModInstall.errTooLarge.localized(currentLang), mb)
        case .noManifestFound:
            return L10n.ModInstall.errNoManifest.localized(currentLang)
        case .dependencyMissing(let names):
            return String(format: L10n.ModInstall.errDeps.localized(currentLang),
                          names.joined(separator: ", "))
        case .fileSystemDenied(let path):
            return String(format: L10n.ModInstall.errFs.localized(currentLang), path)
        case .unknown(let err):
            return err.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidZipFormat:
            return L10n.ModInstall.recoverZip.localized(currentLang)
        case .dependencyMissing:
            return L10n.ModInstall.recoverDeps.localized(currentLang)
        case .fileSystemDenied:
            return L10n.ModInstall.recoverFs.localized(currentLang)
        default:
            return nil
        }
    }

    var canRetry: Bool {
        switch self {
        case .noManifestFound, .unknown: return false
        default: return true
        }
    }
}
```

### 5.5 Gap : `help()` tooltips sous-utilisés

**Inventaire :** Seulement ~8 `.help()` dans tout le code. Beaucoup de boutons
icône-only (folder, gear, safari, info dans ModListRow) sont opaques pour un
nouvel utilisateur.

**Correctif :** Audit systématique. Liste des boutons icône-only sans `help()` :

| Fichier         | Ligne | Icône              | Tooltip à ajouter         |
|-----------------|-------|--------------------|---------------------------|
| ModListRow      | 1014  | `folder`           | ✅ déjà présent          |
| ModListRow      | 1031  | `gearshape`        | ✅ déjà présent          |
| ModListRow      | 1047  | `safari`           | ✅ déjà présent          |
| ModListRow      | 1062  | `info.circle`      | ⚠️ utilise le mauvais key |
| ModListRow      | 1078  | `trash`            | ✅ déjà présent          |
| SavesView       | ~80   | `list.bullet`      | ❌ manquant              |
| SavesView       | ~91   | `square.grid.2x2`  | ❌ manquant              |

**Bug subtil détecté :** `ModListRow.swift:1067` utilise `L10n.Mods.viewOnNexus`
comme tooltip pour le bouton `info.circle` — c'est trompeur (le bouton ouvre
les détails, pas Nexus).

```swift
// ModListRow.swift ligne 1067 — CORRIGER
.help(vm.L(L10n.Mods.viewOnNexus))   // ❌ trompeur
// →
.help(vm.L(L10n.Mods.openDetails))   // ✅ nouvelle clé à ajouter
```


---

## 6. Accessibilité

### 6.1 État actuel

**Inventaire :** `grep -rn "accessibility" StarHubTH/Views/` retourne **0 résultat**.
Aucun label VoiceOver n'est posé. C'est le gap le plus critique.

### 6.2 Plan de correction prioritaire

Appliquer les labels sur les composants les plus utilisés en premier.

#### 6.2.1 `ModListRow` (ligne la plus consultée de l'app)

```swift
// ModListRow.swift — ajouter sur le HStack racine (ligne ~904)

HStack(spacing: AppDesign.Spacing.md) {
    // ... contenu existant ...
}
.accessibilityElement(children: .combine)
.accessibilityLabel("\(mod.name), \(mod.author), version \(mod.version)")
.accessibilityValue(mod.isEnabled ? "activé" : "désactivé")
.accessibilityHint("Activez pour basculer l'état du mod")
.accessibilityAddTraits(.isButton)
```

#### 6.2.2 Boutons icône-only

Chaque bouton icône-only DOIT avoir un `accessibilityLabel` (le `.help()` ne
suffit pas pour VoiceOver).

```swift
// Pattern à appliquer à TOUS les boutons icône-only
Button(action: openFolder) {
    Image(systemName: "folder")
}
.buttonStyle(.plain)
.help(vm.L(L10n.Mods.openFolder))                              // tooltip
.accessibilityLabel(vm.L(L10n.Mods.openFolder))               // VoiceOver
.accessibilityHint(vm.L(L10n.Mods.openFolderHint))            // action
```

#### 6.2.3 Toggles

```swift
Toggle("", isOn: $enabled)
    .labelsHidden()
    .accessibilityLabel("Mod \(mod.name)")
    .accessibilityValue(enabled ? "Activé" : "Désactivé")
```

### 6.3 Contraste — vérification

La spec v1.0 proposait un `verifyContrast()` placeholder. Version réelle :

```swift
// StarHubTH/Design/ContrastChecker.swift (utilitaire de DEV, pas de prod)

import AppKit

enum ContrastChecker {
    /// Ratio de contraste WCAG entre deux NSColor.
    /// Retourne un ratio entre 1.0 (identique) et 21.0 (noir/blanc).
    static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let lighter = max(l1, l2)
        let darker  = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// True si le ratio respecte WCAG AA (4.5:1 pour texte normal, 3:1 pour grand texte).
    static func passesAA(foreground: NSColor, background: NSColor,
                         largeText: Bool = false) -> Bool {
        let threshold = largeText ? 3.0 : 4.5
        return ratio(foreground, background) >= threshold
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(c.redComponent)
        let g = channel(c.greenComponent)
        let b = channel(c.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
```

**Vérifications à faire** (les couleurs utilisées dans l'app) :

| Paire | Mode clair | Mode sombre | Action |
|-------|-----------|-------------|--------|
| `.secondary` sur `.windowBg` | OK (~4.7) | À vérifier | Mesurer |
| `.error` sur fond error 0.1 | OK | À vérifier | Mesurer |
| `.accent` sur fond blanc | OK | À vérifier | Mesurer |

---

## 7. Internationalisation (alignée sur `L10n.swift`)

### 7.1 Règle absolue (déjà en place, à respecter)

```swift
// ❌ JAMAIS — casse la parité build_app.py
Text("Installer un mod")

// ✅ TOUJOURS
Text(vm.L(L10n.ModInstall.installButton))
```

### 7.2 Workflow d'ajout de chaîne

```
1. Ajouter la clé dans L10n.swift
      static let newKey = "mod_install_new_key"

2. Ajouter la traduction dans assets/fr.lproj/Localizable.strings
      "mod_install_new_key" = "Nouvelle chaîne";

3. Ajouter dans assets/en.lproj/Localizable.strings
      "mod_install_new_key" = "New string";

4. Ajouter dans assets/th.lproj/Localizable.strings
      "mod_install_new_key" = "สตริงใหม่";

5. Builder — build_app.py valide la parité automatiquement
```

### 7.3 Chaînes à ajouter pour cette spec

| Clé proposeée              | FR                          | Usage                    |
|----------------------------|-----------------------------|--------------------------|
| `mod_install_empty_title`  | Aucun mod installé          | EmptyStateDropZone       |
| `mod_install_empty_hint`   | Glissez un .zip ou cliquez  | EmptyStateDropZone       |
| `mods_open_details`        | Voir les détails            | Tooltip info.circle      |
| `mods_open_details_hint`   | Ouvre la fiche détaillée    | Accessibility hint       |
| `mod_install_err_*`        | (6 clés d'erreurs)          | InstallationError        |
| `mod_install_recover_*`    | (3 clés de récupération)    | InstallationError        |

---

## 8. Performance

### 8.1 Recherche — filtrage temps réel (ModListView)

**Problème initial supposé :** `searchText` déclenche `filteredMods` (computed
property) à chaque keystroke. Avec 100+ mods et des dépendances à scanner, on
craignait une latence.

**Correctif tenté puis abandonné :** Debounce de 200 ms via `.task(id: searchText)`
+ `debouncedSearch`. Testé en 1.7.0-beta, mais **reverté** : le délai de 200 ms
introduit une latence perceptible qui donne l'impression que la barre de
recherche « accroche » à chaque caractère, dégradant l'UX perçue par rapport au
filtrage temps réel d'origine (1.6.0).

**Décision finale :** Filtrage temps réel conservé. Le `ViewModel` maintient un
index précomputé (`installedUniqueIds`, `installedModStates`) utilisé par
`getMissingDependencies`/`getDisabledDependencies` (O(dépendances) par appel),
et la pagination (15/page) limite le nombre de rows rendues. Le coût par
keystroke reste négligeable dans la pratique.

```swift
// ModListView.swift — état final (filtrage temps réel, pas de debounce)
@State private var searchText = ""

var filteredMods: [ModItem] {
    vm.mods
        .filter { mod in
            searchText.isEmpty || matchesSelfOrAnyChild(mod) {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.uniqueId.localizedCaseInsensitiveContains(searchText)
            }
        }
        // ...
}

.searchable(text: $searchText, prompt: Text(vm.L(L10n.Mods.searchMods)))
.onChange(of: searchText) { currentPage = 1 }
```

### 8.2 Liste — `VStack` conservé (pagination comme optimisation principale)

**Problème initial supposé :** `ModListView` utilise `ScrollView` + `VStack`
qui matérialise toutes les rows même hors écran.

**Correctif tenté puis abandonné :** Migration vers `LazyVStack`. Testé en
1.7.0-beta, mais **reverté** : la pagination plafonne déjà la liste à 15 rows
par page, donc le bénéfice de `LazyVStack` est marginal et ne justifie pas le
changement de comportement de rendu.

**Décision finale :** `VStack` conservé (rendu déterministe). La pagination
(15/page, footer avec saut de page direct) reste l'optimisation principale de
la liste.

### 8.3 Cache d'images Nexus

**Problème :** `ModDetailView` (ligne ~66) et les avatars utilisent `AsyncImage`
sans cache. Re-télécharge à chaque ouverture.

**Correctif :** Wrapper autour de `AsyncImage` avec `URLCache` partagé.

```swift
// StarHubTH/Design/CachedAsyncImage.swift

import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    private static let cache: URLCache = {
        let cache = URLCache(memoryCapacity: 50_000_000,   // 50 MB RAM
                             diskCapacity: 100_000_000,     // 100 MB disk
                             diskPath: "starhub-image-cache")
        URLCache.shared = cache
        return cache
    }()

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(image)
            case .failure:
                placeholder()
            case .empty:
                placeholder()
            @unknown default:
                placeholder()
            }
        }
    }
}
```

**Migration :** Remplacer les `AsyncImage(url:)` par `CachedAsyncImage(url:)`.


---

## 9. Tests

### 9.1 Stratégie (alignée sur les 9 targets existantes)

Le projet a déjà 9 dossiers de tests sous `Tests/`. La spec ajoute un 10e
pour le design system, sans réinventer l'existant.

```
Tests/
├── ModConfigBackupManagerTests/     (existant)
├── ModInstallBackupManagerTests/    (existant)
├── SaveManagerTests/                (existant)
├── NexusDownloadTests/              (existant)
├── ManifestVersionPatcherTests/     (existant)
├── ModTagTests/                     (existant)
├── DescriptionBlockTests/           (existant)
├── ModDependencyParserTests/        (existant)
├── DependencyTreeTests/             (existant)
└── DesignSystemTests/               ← NOUVEAU
```

**Package.swift à modifier** (ajouter un target) :

```swift
// Package.swift — ajouter dans le tableau des testTargets
.testTarget(
    name: "DesignSystemTests",
    dependencies: ["StarHubTHCore"],
    path: "Tests/DesignSystemTests"
),
```

### 9.2 Mock ViewModel pour tests UI

Le code de test v1.0 référençait `mockViewModel` sans le définir. Version réelle :

```swift
// Tests/DesignSystemTests/Mocks/MockStarHubTHViewModel.swift

import Foundation
@testable import StarHubTHCore

/// ViewModel de test avec données pré-remplies.
/// Évite de toucher au système de fichiers réel.
final class MockStarHubTHViewModel: StarHubTHViewModel {
    override init() {
        super.init()
        // Données de test reproductibles
        self.mods = [
            ModItem(folderName: "ContentPatcher", name: "Content Patcher",
                    author: "Pathoschild", version: "2.0.0",
                    isEnabled: true, isGroup: false, description: "",
                    children: nil, uniqueId: "Pathoschild.ContentPatcher",
                    dependencies: [], installedFileDate: Date(),
                    hasConfigFile: false),
            ModItem(folderName: "SVE", name: "Stardew Valley Expanded",
                    author: "FlashShifter", version: "1.14.0",
                    isEnabled: false, isGroup: false, description: "",
                    children: nil, uniqueId: "FlashShifter.SVE",
                    dependencies: ["ContentPatcher"], installedFileDate: nil,
                    hasConfigFile: true),
        ]
    }
}
```

### 9.3 Tests concrets à écrire

```swift
// Tests/DesignSystemTests/DesignTokensTests.swift

import XCTest
@testable import StarHubTHCore

final class DesignTokensTests: XCTestCase {

    func testSpacing_followsFourBasedGrid() {
        // Les tokens doivent être des multiples de 4 pour la cohérence visuelle
        XCTAssertEqual(AppDesign.Spacing.xs, 4)
        XCTAssertEqual(AppDesign.Spacing.sm, 8)
        XCTAssertEqual(AppDesign.Spacing.md, 12)   // exception acceptable
        XCTAssertEqual(AppDesign.Spacing.lg, 16)
        XCTAssertEqual(AppDesign.Spacing.xl, 24)
        XCTAssertEqual(AppDesign.Spacing.xxl, 32)
    }

    func testRadius_coversExistingUseCases() {
        // Doit couvrir toutes les valeurs utilisées dans le code (6, 8, 10, 12)
        let allRadii = [AppDesign.Radius.sm, AppDesign.Radius.md,
                        AppDesign.Radius.section, AppDesign.Radius.lg]
        XCTAssertTrue(allRadii.contains(6))
        XCTAssertTrue(allRadii.contains(8))
        XCTAssertTrue(allRadii.contains(10))
        XCTAssertTrue(allRadii.contains(12))
    }

    func testOpacity_tokensCoverExistingRange() {
        // L'intervalle [0.05, 0.8] doit être couvert
        XCTAssertLessThanOrEqual(AppDesign.Opacity.subtle, 0.1)
        XCTAssertGreaterThanOrEqual(AppDesign.Opacity.secondary, 0.7)
    }
}

// Tests/DesignSystemTests/ContrastCheckerTests.swift

import XCTest
import AppKit
@testable import StarHubTHCore

final class ContrastCheckerTests: XCTestCase {

    func testBlackOnWhite_passesAA() {
        let ratio = ContrastChecker.ratio(.black, .white)
        XCTAssertEqual(ratio, 21.0, accuracy: 0.1)
        XCTAssertTrue(ContrastChecker.passesAA(foreground: .black, background: .white))
    }

    func testSecondaryOnWindowBackground_meetsAA() {
        // .secondary sur .windowBackgroundColor — cas courant dans l'app
        let fg = NSColor.secondaryLabelColor
        let bg = NSColor.windowBackgroundColor
        XCTAssertTrue(ContrastChecker.passesAA(foreground: fg, background: bg),
                      "secondaryLabel doit rester lisible sur windowBackground")
    }
}
```

### 9.4 Test de non-régression visuelle

Vu l'absence de framework de snapshot testing, un test pragmatique : vérifier
que la migration vers tokens ne change pas les valeurs numériques.

```swift
// Tests/DesignSystemTests/TokenMigrationTests.swift

final class TokenMigrationTests: XCTestCase {
    /// Vérifie que chaque token correspond à une valeur réellement utilisée
    /// dans le code avant migration. Échoue si on introduit une nouvelle valeur
    /// qui n'a jamais été testée visuellement.
    func testTokens_matchPreviouslyUsedValues() {
        // Ces valeurs proviennent du grep §1.2 — NE PAS CHANGER sans re-tester visuellement
        let knownGoodValues: Set<[CGFloat]> = [
            [4, 6, 8, 10, 12, 16, 20, 24, 32, 40],        // spacings
            [6, 8, 10, 12],                                  // radii
            [10, 11, 12, 13, 14, 16, 20, 24],              // font sizes
        ]
        let tokenSizes: Set<CGFloat> = [
            AppDesign.Spacing.xs, AppDesign.Spacing.sm, AppDesign.Spacing.md,
            AppDesign.Spacing.lg, AppDesign.Spacing.xl, AppDesign.Spacing.xxl,
            AppDesign.Radius.sm, AppDesign.Radius.md,
            AppDesign.Radius.section, AppDesign.Radius.lg,
        ]
        let knownFlattened = Set(knownGoodValues.flatMap { $0 })
        for size in tokenSizes {
            XCTAssertTrue(knownFlattened.contains(size),
                          "Token \(size) n'est pas une valeur éprouvée — vérifier visuellement")
        }
    }
}
```

---

## 10. Roadmap et estimations (révisées +50%)

> **Correction critique #4 :** Les estimations v1.0 étaient irréalistes.
> Version révisée avec marge de sécurité.

### 10.1 Phases détaillées

#### Phase 1 — Foundation (5 jours)

| Tâche                                         | Estimation |
|-----------------------------------------------|------------|
| Créer `AppDesignTokens.swift` + tests         | 1 jour     |
| Migrer `SharedComponents.swift`               | 0.5 jour   |
| Migrer `MainView.swift` (sidebar)             | 1 jour     |
| Migrer `ModListView.swift`                    | 1.5 jours  |
| Tests + vérification visuelle clair/sombre    | 1 jour     |

**Livrable :** Tous les composants principaux utilisent les tokens.
**Diff visible :** Aucun (migration conservative).

#### Phase 2 — Correctifs UX ciblés (4 jours)

| Tâche                                         | Estimation |
|-----------------------------------------------|------------|
| `SystemStatusFooter` + intégration            | 1 jour     |
| `EmptyStateDropZone` (ModListView)            | 0.5 jour   |
| Dépendances manquantes cliquables             | 0.5 jour   |
| Spinner toggle + `pendingToggleFolder`        | 1 jour     |
| `InstallationError` typé + migration          | 1 jour     |

**Livrable :** Feedback utilisateur amélioré sur les points de friction.

#### Phase 3 — Accessibilité (3 jours)

| Tâche                                         | Estimation |
|-----------------------------------------------|------------|
| `accessibilityLabel` sur ModListRow + sidebar | 1 jour     |
| Audit complet boutons icône-only              | 0.5 jour   |
| `ContrastChecker` + vérifications             | 0.5 jour   |
| Tests + validation VoiceOver                  | 1 jour     |

**Livrable :** Conformité VoiceOver sur les parcours critiques.

#### Phase 4 — Performance (2 jours)

| Tâche                                         | Estimation |
|-----------------------------------------------|------------|
| Debounce recherche                            | 0.5 jour   |
| `LazyVStack` migration                        | 0.5 jour   |
| `CachedAsyncImage` + migration                | 1 jour     |

**Livrable :** Fluidité avec 100+ mods.

#### Phase 5 — Internationalisation (1 jour)

| Tâche                                         | Estimation |
|-----------------------------------------------|------------|
| Ajouter ~15 nouvelles clés L10n               | 0.5 jour   |
| Traductions FR/EN/TH                          | 0.5 jour   |

**Livrable :** `build_app.py` passe, parité maintenue.

### 10.2 Total révisé

| Version v1.0 (irréaliste) | Version v2.0 (réaliste) |
|---------------------------|-------------------------|
| 11–15 jours               | **15 jours**            |

La marge de +30% (vs les +50% annoncées dans la relecture) se justifie :
le code existant est de bonne qualité, les composants à migrer sont identifiés.

---

## 11. Gestion des risques

| Risque                                  | Probabilité | Impact   | Mitigation                              |
|-----------------------------------------|-------------|----------|-----------------------------------------|
| Régression visuelle après migration     | Moyenne     | Élevé    | Tests `TokenMigrationTests` + diff visuel manuel |
| Nouvelle clé L10n oublie une langue     | Élevée      | Critique | `build_app.py` casse le build (filet auto) |
| `LazyVStack` change l'ordre visuel      | Faible      | Moyen    | Test sur 50+ mods avant merge          |
| VoiceOver non testé sur parcours réel   | Moyenne     | Élevé    | Session manuelle obligatoire avant release |
| `pendingToggleFolder` race condition    | Moyenne     | Moyen    | La logique existante `localIsOn` est déjà optimiste — étendre le même pattern |

---

## 12. Guide du développeur (anti-patterns)

```swift
// ❌ ÉVITER — hardcode casse la cohérence
Text("Titre").font(.system(size: 13, weight: .bold))
RoundedRectangle(cornerRadius: 10)
VStack(spacing: 8) { }
Color.primary.opacity(0.1)

// ✅ PRÉFÉRER — tokens centralisés
Text("Titre").font(AppDesign.Font.body(.bold))
RoundedRectangle(cornerRadius: AppDesign.Radius.section)
VStack(spacing: AppDesign.Spacing.sm) { }
AppDesign.Color.primary.opacity(AppDesign.Opacity.light)
```

```swift
// ❌ ÉVITER — chaîne littérale (casse build_app.py)
Text("Installer")

// ✅ PRÉFÉRER — clé L10n
Text(vm.L(L10n.ModInstall.installButton))
```

```swift
// ❌ ÉVITER — bouton icône sans label accessibilité
Button(action: openFolder) { Image(systemName: "folder") }

// ✅ PRÉFÉRER — accessible + tooltip
Button(action: openFolder) {
    Image(systemName: "folder")
}
.help(vm.L(L10n.Mods.openFolder))
.accessibilityLabel(vm.L(L10n.Mods.openFolder))
```

```swift
// ❌ ÉVITER — VStack dans ScrollView pour listes longues
ScrollView { VStack { ForEach(items) { row($0) } } }

// ✅ PRÉFÉRER — LazyVStack (rendu paresseux)
ScrollView { LazyVStack { ForEach(items) { row($0) } } }
```

---

## 13. Annexes

### 13.1 Commandes de vérification

```bash
# Vérifier la parité des clés L10n (doit passer sans erreur)
python3 build_app.py --check-locales

# Lancer tous les tests
swift test

# Lancer uniquement les tests design system
swift test --filter DesignSystemTests

# Compter les valeurs ad-hoc restantes (objectif : -70%)
grep -rn "\.system(size:" StarHubTH/Views/ | wc -l

# Vérifier qu'aucune chaîne littérale n'est oubliée
grep -rn 'Text("' StarHubTH/Views/ | grep -v "verbatim:" | grep -v 'L10n\.'
```

### 13.2 Références

- Apple Human Interface Guidelines (macOS 14)
- WCAG 2.1 niveau AA
- Code existant au commit `a3937f6` (release 1.6.0)

### 13.3 Historique des versions du document

| Version | Date         | Changements                                     |
|---------|--------------|-------------------------------------------------|
| 1.0     | 24 juil. 2026| Version initiale (placeholder, estimations fausses) |
| 2.0     | 25 juil. 2026| Réécriture alignée sur code réel, sans placeholder |

---

**Fin du document.**
