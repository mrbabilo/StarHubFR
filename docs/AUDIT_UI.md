# Grille d'audit UI — macOS

Une grille pour noter l'état de l'interface **au code source**, sans lancer
l'app : cinq dimensions, chacune notée 0-4. Elle sert à situer un écran avant
de le retoucher, et à dire ce qu'on a regardé quand on affirme qu'il va bien.

## Provenance et écart assumé

Reprise de `skill/reference/audit.native.md` du projet
[Impeccable](https://github.com/pbakaus/impeccable) (pbakaus), qui fournit un
audit natif au code source pour SwiftUI/UIKit/Compose. **Rien n'est installé :
seule la grille est reprise, et elle est retargetée.**

Impeccable déclare quatre plateformes — `web`, `ios`, `android`, `adaptive`.
macOS n'en fait pas partie, et ça se voit dans ses critères : cibles tactiles de
44 pt, Dynamic Type, encoche et Dynamic Island, retour par balayage de bord,
barres d'onglets. Sur une app de bureau à barre latérale, fenêtres
redimensionnables, survol et clavier, ces critères notent les mauvaises choses.
Chaque dimension ci-dessous remplace donc le critère iOS par son équivalent
desktop, et cite le piège du dépôt qui l'a rendu concret quand il y en a un.

Son autre moitié — les 61 règles déterministes, sans clé API — ne s'applique
pas : elles scannent `.tsx` `.jsx` `.html` `.svelte` `.vue` `.js` `.css` `.ts`,
et aucun `.swift`. Sur les 48 fichiers de `Views/`, elles ne lisent pas une
ligne. Ne pas espérer de relevé automatique de ce côté.

---

## 1. Accessibilité (VoiceOver, clavier)

**Chercher :**

- Contrôles sans libellé d'accessibilité, sans trait, sans annonce d'état.
- **Parcours au clavier** — un écran de bureau se traverse à la tabulation.
  Contrôle inatteignable, ordre illogique, focus perdu au changement de vue.
  ⚠️ Un `onChange(of: focusState)` seul meurt si la vue est remplacée par
  `.id(...)` : doubler d'un `onDisappear` idempotent.
- **Raccourcis liés deux fois** (menu + local) : le menu gagne, et le local ne
  se déclenche jamais — ⌘K s'ouvrait sans pouvoir se refermer.
- **Échap** ferme bien les feuilles ; ne pas conclure le contraire d'un relevé
  statique. Une absence de mécanisme se relève, un comportement se constate.
- Taille de police : le texte suit-il le réglage système, ou est-il figé ?
  Les `.system(size:)` littéraux ne suivent pas.
- **Cibles de survol** : `.help()` sur un glyphe de 10 pt ne s'affiche jamais —
  macOS exige ~2 s de survol immobile entièrement dans la zone. Porter la cible
  à ~18×18 (`frame` + `contentShape(.rect)`) **avant** le `.help`.
- Contraste du texte dans les deux apparences, claire et sombre.

**0** = inutilisable au lecteur d'écran · **1** = lacunes majeures (contrôles
sans libellé, rien ne suit la taille système) · **2** = partiel (libellés
présents, ordre ou mise à l'échelle cassés) · **3** = bon, lacunes mineures ·
**4** = libellé, ordonné, à l'échelle, survol atteignable.

## 2. Performance

**Chercher :**

- **Listes non virtualisées** — le piège le plus cher du dépôt : ~2 000 lignes
  de journal dans une `List` ont beach-ballé 8–10 s ; `LazyVStack` a corrigé.
- **Propriétés calculées qui re-parcourent** : plusieurs propriétés balayant la
  même collection à chaque rendu. Une seule passe construit la vue.
- **`body` trop dense** : sature le type-checker (compilation en minutes,
  diagnostics absurdes). Découper en sous-vues.
- **Travail synchrone sur le fil principal** dans un chemin de défilement ou de
  geste. Toute mutation `@Published` reste sur le principal, mais le calcul qui
  la précède ne doit pas y être.
- **Travail au lancement avant la première image** — le splash est une fenêtre
  séparée, pas une excuse pour charger sous elle.
- Images pleine taille décodées pour des vignettes, sans cache.

**0** = saccadé partout · **1** = problèmes majeurs (liste non virtualisée,
lancement lent) · **2** = partiel · **3** = bon · **4** = lancement rapide,
défilement fluide.

## 3. Apparence et thème

**Chercher :**

- **Couleurs en dur** au lieu des tokens (`AppDesign.Color`, `AppDesignCore`)
  ou des couleurs sémantiques système. ⚠️ Le piège n'est pas le littéral en
  soi — c'est le littéral **quand un token porte déjà ce sens**. Deux verts
  pour « activé » se voient côte à côte ; un voile noir ou un liseré blanc sur
  vignette n'ont, eux, pas de token et n'en demandent pas.
- **Apparence sombre** : variantes manquantes, contraste faible, inversion
  hâtive. Éprouver sur les deux thèmes, pas sur celui qu'on utilise.
- Matériaux hors plateforme : un flou fait main là où un matériau système est
  attendu.
- **Libellés français** : le FR est plus long que l'EN. Vérifier la largeur sur
  le libellé le plus long, pas sur le plus court — trois retours sur un seul
  alignement.

**0** = tout en dur · **1** = tokens minimaux · **2** = partiel (tokens
présents, appliqués inégalement) · **3** = bon · **4** = sémantique partout, les
deux apparences de plein droit.

> **État connu au 2026-09-09** : l'axe H a migré les vues de son périmètre et
> s'est clos sur un audit de fidélité à zéro écart. Le reliquat du reste du
> dépôt (couleurs littérales, 555 tailles littérales) est **un relevé daté pour
> un futur axe, pas une dette à éteindre** — décision de l'auteur, commit
> `13c5caf`. Ne pas la rouvrir sans qu'il le demande.
>
> ⚠️ La méthode de cet audit — comparer les multisets de valeurs de style entre
> deux versions — ne peut pas voir un littéral **présent des deux côtés**. Un
> token contourné de longue date y passe pour « aucun écart ». C'est ainsi que
> trois usages du vert système ont survécu là où `AppDesign.Color.installed`
> disait déjà le même état (corrigé le 2026-09-10).

## 4. Conformité à la plateforme (CRITIQUE)

**Chercher :**

- **Contrôles de forme web** : boutons dessinés à la main, bascules maison,
  affordances qui n'existent qu'au survol.
- **Cycle de vie des fenêtres** — deux pièges qui ont cassé l'app : `orderOut`
  sur la fenêtre principale vaut « dernière fenêtre fermée » (exiger
  `applicationShouldTerminateAfterLastWindowClosed → false`), et masquer depuis
  `.onAppear` est trop tard (intercepter dans
  `applicationWillFinishLaunching`).
- **macOS ne remplace pas une app ouverte** lors d'un `open` : une release
  locale ne prend effet qu'après Cmd+Q.
- **Redimensionnement** : la fenêtre est libre. Un `frame` fixe et un
  `lineLimit` absent se voient aux extrêmes, pas au milieu.
- **Jeu d'icônes** : SF Symbols, sans mélange.
- **Patron des pages de liste** : `VStack(spacing: 0)` — en-tête fixe,
  `Divider`, `ScrollView`, pied fixe. Pas un `ScrollView` unique qui ferait tout
  défiler ensemble.
- **Barre latérale** : pas de barre de recherche ; « Mod Updates » reste visible
  en permanence, badge caché à zéro.

**0** = étranger à la plateforme · **4** = indiscernable d'une app native.

## 5. Identité visuelle

**Chercher :**

- Un écran de diagnostic qui **constate sans conduire** : dix revues vertes et
  « pas grande utilité » à l'écran. Chaque ligne doit avoir une destination
  exacte, pas un onglet.
- Une fonctionnalité qui **ne montre rien** sur les données réelles de
  l'utilisateur — livrer avec le scénario minimal qui la fait apparaître.
- Espacements et rayons cohérents entre écrans de même famille.
- Densité : une page de liste et une fiche ne se lisent pas au même rythme.

**0** = générique · **4** = un parti pris tenu partout.

---

## Ce que la grille ne tranche pas

**Aucune de ces notes ne remplace un regard à l'écran.** Le relevé statique a
déjà conclu faux deux fois en une soirée dans ce dépôt. Les agents valident par
succès de build ; la vérification GUI est déléguée à l'humain — c'est une règle
du projet, pas une précaution.

Utiliser la grille pour **désigner ce qu'il faut aller regarder**, jamais pour
affirmer que l'écran va bien.
