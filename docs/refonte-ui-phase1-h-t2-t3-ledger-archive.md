# Archive du ledger SDD — refonte-ui-phase1-h-t2-t3-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-28-refonte-ui-phase1-h-t2-h-t3/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-28-refonte-ui-phase1-h-t2-h-t3.md`.

2026-08-28-refonte-ui-phase1-h-t2-h-t3.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-28-refonte-ui-phase1-h-t2-h-t3.md

Spec : docs/superpowers/specs/2026-08-28-refonte-ui-design.md (lisible, autorité).
Branche : `main`, par convention du dépôt (CLAUDE.md) et consentement explicite
de l'utilisateur cette session. Pas de worktree.

## Scan de pré-vol

### Paires de tâches partageant un fichier ou une interface

| A → B | Produit / consommé | Constat |
|---|---|---|
| T1 → T4 | `HomeAttention.counters(…)`, `HomeLaunchState.resolve(…)` | Cohérent. T4 consomme exactement ce que T1 déclare produire. |
| T2 → T4 | icônes et teintes des compteurs | **CONFLIT** — T4 disait « réutilisant les icônes et teintes de la tâche 2 », or le retrait d'`iconColor` (relecture critique, F2) supprime les teintes d'icône ; et `.library` n'est pas un item badgé, donc sans `badgeColor`. → tranché, voir Ruling 1. |
| T2 → T5 | clés `main_group_*` ajoutées / clés orphelines retirées | Cohérent. T2 dit explicitement de ne pas supprimer les anciennes clés ; T5 fait la passe. |
| T2 ↔ T4 | tous deux modifient `MainView.swift` | Pas de conflit : régions disjointes (T2 le corps de la barre latérale, T4 la seule ligne 270). Dispatch séquentiel. |
| T3 → T4 | `SettingsView` accueille ce que `HomeView` retirera | Cohérent, et c'est l'invariant du plan : T3 **précède** T4. T3 ne modifie pas `HomeView`. |
| T1 → T2 | identifiants d'onglet | Cohérent : `Kind.tab` code les mêmes 4 identifiants que la barre latérale. |

### Cohérence interne de chaque tâche

| Tâche | Constat |
|---|---|
| T1 | Tests et code s'accordent : ordre des compteurs, `Kind.tab`, priorité du dossier de jeu. Cible de test ajoutée à `Package.swift` avant l'étape RED — sans quoi l'échec ne prouverait rien. |
| T2 | Canevas cohérent après F2 : `SidebarItem` ne déclare plus `iconColor`, les 13 appels ne le passent plus, la signature « Produces » est à jour. Accolades du canevas équilibrées. |
| T3 | Fichiers créés/touchés cohérents (SettingsView seul). L'étape de vérification exige deux appelants — ce qui suppose `HomeView` intact : cohérent. |
| T4 | `HomeView` n'a pas de `currentTab` — **relevé et corrigé** dans le plan (F1) avec l'`init` complet et le site d'appel. Sans cela le canevas ne compilait pas. |
| T5 | Vérifie ce que T2 et T4 ont laissé. `main_alerts_nav_a11y` explicitement conservée. |

### Ce que le plan mandate et qu'une revue pourrait prendre pour un défaut

| Point | Ruling |
|---|---|
| T3 duplique des blocs de `HomeView` dans `SettingsView` | Ruling 2 ci-dessous. |

## Rulings

Ruling 1 — **Couture T2→T4 sur les glyphes et teintes.** Le plan porte
désormais une table explicite : glyphe = le symbole de l'item de barre
latérale, teinte = sa `badgeColor`, et `.secondary` pour `.library` qui n'est
pas un item badgé. Justification : `tint(for:)` n'est lu que lorsque
`level == .attention`, et le parc ne lève jamais l'attention (test de T1) — la
valeur rend le `switch` total sans prétendre à une couleur qui s'afficherait.
*Coût si faux* : une teinte inutilisée à corriger d'une ligne.

Ruling 2 — **La duplication de T3 est voulue et transitoire.** Entre le commit
de T3 et celui de T4, `SettingsView` et `HomeView` montrent le même dossier du
jeu, la même gestion SMAPI et les mêmes extensions cœur. Une revue de tâche
signalera légitimement « duplication ». Elle est le prix de l'invariant du
plan : aucun commit ne laisse une capacité injoignable, et l'ordre inverse
transformerait `selectGameDir` en code mort sans qu'aucun gate ne le voie.
T4 supprime le doublon. *Coût si faux* : un commit intermédiaire redondant
dans l'historique.

## Progression

Task 1: complete (commits 71155a8..6efe2ea, review clean)
Task 1: ⚠️ résolu par le contrôleur — le brief annonçait « +10 tests », son code
  en contient 9. Aucun défaut : la ligne de base après T1 est **1656**, c'est
  elle que les tâches suivantes doivent citer. L'implémenteur a suivi le brief
  plutôt que de rembourrer, ce qui était le bon choix.
Task 1: minor (deferred): aucun test ne croise `gameDirIsEmpty: true` avec
  `profileIsVanilla: true` — la priorité du dossier est correcte par lecture
  (retour dur avant la branche vanilla) mais un réordonnancement passerait.
Task 1: minor (deferred): `Counter.tab` est un renvoi d'une ligne vers
  `kind.tab` — la destination est dérivable de deux façons.

Task 2: Ruling 3 — **le cliquet monte de +1/+1, et il doit monter.** La spec §4.2
  impose **quatre** groupes de navigation ; il y en avait trois. Le quatrième
  en-tête appelle `vm.L(…)` comme les trois autres : `abbreviation_vm`
  2214→2215, `vm_dot_L_calls` 1173→1174. Vérifié moi-même : 3
  `SidebarSectionHeader(title: vm.L(…))` avant, 4 après — aucune duplication à
  retirer, la hausse est le coût exact d'une destination de plus.
  CLAUDE.md prévoit ce cas : « Un ajout délibéré demande un `--update`
  explicite, visible dans le diff. » → autorisé, `.standards-baseline.json`
  dans le commit.
  *Coût si faux* : une ligne de baseline relevée à tort, que `--report` montre
  et qu'un `--update` inverse.

Task 2: complete (commits 6efe2ea..d232131, review clean, gate EXIT=0)
Task 2: minor (deferred): les trois items autrefois badgés gagnent un **survol**
  (l'ancien SidebarBadgeItem n'avait pas d'`.onHover`) — visible, non annoncé
  dans la note de vérification. → à ajouter au scénario de T5.
Task 2: minor (deferred): ils gagnent aussi le trait d'accessibilité
  `.isSelected`, qu'ils n'avaient pas. Amélioration, mais nouveau comportement
  VoiceOver. → même scénario.

Task 3: Ruling 4 — **`SettingsView` n'a pas de `smapiInstaller`, il doit
  l'acquérir comme `HomeView`.** Vérifié : `SettingsView` ne déclare que `vm` et
  des `@AppStorage` ; lire `vm.smapiInstaller` dans le corps ne créerait aucune
  observation, et la barre de progression resterait figée pendant toute
  l'installation. Solution imposée : recopier le motif de `HomeView` —
  `@ObservedObject var smapiInstaller: SmapiInstaller` plus un
  `init(vm:)` qui fait `self.smapiInstaller = vm.smapiInstaller`. La signature
  d'appel reste `SettingsView(vm: vm)` : **`MainView` n'est pas touché**.
  *Coût si faux* : une propriété observée de trop, sans effet visible.

Task 3: Ruling 5 — **T3 passe son propre gate**, contrairement au budget du plan
  (qui groupait T3+T4). Raison : le ruling 4 introduit un `init` personnalisé et
  ~100 lignes de vue recopiées ; si ça ne compile pas, le gate de T4 accuserait
  deux tâches à la fois. Dix minutes achètent l'isolement du défaut.
  *Coût si faux* : dix minutes de build.

Task 3: Ruling 6 — **pas de `--update` sur la hausse de +38/+18.** Elle vient de
  la duplication délibérée de ~100 lignes de vue dans un second fichier
  (ruling 2), et elle est **transitoire** : T4 retire ces mêmes lignes de
  `HomeView`. Relever la baseline maintenant la laisserait desserrée pour
  toujours, alors qu'elle va redescendre d'elle-même.
  Conséquence : le commit de T3 reste avec un gate « compile et signature
  verts, cliquet rouge par construction », et **le gate de T4 doit être vert
  avec la baseline inchangée** (`abbreviation_vm` ≤ 2215, `vm_dot_L_calls`
  ≤ 1174). C'est un critère d'acceptation plus fort que celui du plan : il
  prouve que T4 a bien retiré ce que T3 a dupliqué.
  *Coût si faux* : si T4 échoue, le cliquet reste rouge jusqu'à sa correction.

Task 3: note — l'implémenteur a dû envelopper les nouvelles sections dans un
  `Group { }` : le `VStack` du corps avait déjà 8 enfants et `ViewBuilder`
  plafonne à 10. Défaut visible seulement au build, sans effet de mise en page.

Task 3: complete (commits d232131..7849832, review clean ; gate = compile et
  signature verts, cliquet rouge par construction — ruling 6)
Task 3: minor (deferred): le `Group { }` et son commentaire explicatif devront
  disparaître avec les blocs en T4, pas rester en commentaire orphelin.

Task 4: Ruling 8 — **le « 0 littéral » de l'étape 4 compte 1, et c'est bon
  signe.** Le reste est `.font(.system(size: AppDesign.Icon.md))` — un token,
  posé tel quel par le canevas du brief lui-même (le critère grep du brief
  contredit son propre canevas). C'est le motif canonique du châssis H-T1 :
  `StateCard.swift:18` et `HeroHeader.swift:50` l'utilisent. Le critère réel
  (ROADMAP : « zéro valeur de style hors tokens ») est satisfait : il y avait
  8 littéraux avant, 0 après.
  *Coût si faux* : un grep trop large qui refuse le motif de tout le châssis.

Task 4: reprise après interruption de session — étapes 1–4 vérifiées dans
  l'arbre par le contrôleur : bande des 4 compteurs (étape 1), carte de
  lancement et états empêchés (étape 2), sections « dossier du jeu » et
  « gestion SMAPI » retirées, extensions cœur en lecture seule — glyphes
  d'état sans bouton (étape 3), capacités toutes joignables + littéraux à 0
  (étape 4, ruling 8). Aucune référence orpheline aux blocs supprimés, site
  d'appel unique `MainView.swift:218` à jour. Étape 5 (gate) lancée.

Task 4: Ruling 9 — **le critère additionnel du ruling 6 est révoqué, la
  baseline est relevée.** Le gate de T4 est resté rouge (+35/+15) alors que
  T4 avait fait son travail (mesuré : Δ −3/−3 sur HomeView, MainView et
  SettingsView inchangés). La prémisse du ruling 6 — « T4 retire ces mêmes
  lignes » — est fausse sur deux points vérifiés dans le code :
  1. T3 a posé **quatre** sections aux Réglages ; T4 n'en retire que deux
     (`gameFolder`, `smapiManager`). `appInfo` et `coreExtensions` restent à
     l'accueil en **constat** (spec : « le parc et le socle restent en version
     constat ») pendant que les **commandes** vivent aux Réglages — double
     présence voulue, chaque exemplaire coûtant ses `vm`.
  2. La bande des compteurs et la carte de lancement sont une fonctionnalité
     nouvelle : leur coût en `vm` est intrinsèque.
  Tordre le code pour masquer des `vm` légitimes serait jouer contre la
  métrique. CLAUDE.md : « Un ajout délibéré demande un `--update` explicite,
  visible dans le diff. » → baseline 2215→2250 / 1174→1189, fichier dans le
  commit de T4 (précédent : ruling 3). Compilation et signature avaient déjà
  passé dans le même arbre ; le cliquet revérifié vert après relevé (EXIT=0).
  *Coût si faux* : une baseline desserrée de +35/+15 que le prochain chantier
  de vues devra défricher — le ruling 6 gardait raison de traquer ça.

Task 4: complete (commit à venir, review contrôleur = étapes 1–4 du brief
  vérifiées à la main + gate G3 : compile/signature/cliquet verts)

Task 5: complete — 4 clés retirées (main_game_management, main_system,
  main_online, home_version_string) de L10n.swift et des deux locales, aucune
  référence survivante ; main_alerts_nav_a11y conservée (SidebarItem).
  ROADMAP : H-T2/H-T3 cochées, constat + scénario à l'écran posés.
  Gates : swift test 1656 verts (EXIT=0) ; build_app.py EXIT=0 (parité clés
  validée par le build) ; check_standards --report stable à 2250/1189.

PLAN COMPLETE — phase 1 (H-T2 + H-T3) livrée en 5 tâches, commits
  71155a8…(T5). Reste au plan de chantier H : T4 (Mods, · L) → T9. La
  vérification à l'écran (8 points, dans la ROADMAP) conditionne l'ouverture
  de H-T4 — elle revient à l'utilisateur.

Clôture : vérification à l'écran passée par l'utilisateur le 2026-08-28
  (8/8, rien à signaler) — consignée dans la ROADMAP. Phase 1 fermée
  bout en bout : plan, code, gates, écran. H-T4 débloqué.
