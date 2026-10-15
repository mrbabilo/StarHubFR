# Prompt d'audit UX/UI — l'onglet « Performances »

> Prompt réutilisable pour faire auditer par une IA **une seule page** de
> StarHubFR : l'onglet « Performances » de « Diagnostic & Performances ».
> Déclinaison de [`prompt-audit-ux.md`](prompt-audit-ux.md) (qui audite toute
> l'app) : mêmes limites, même grille (`AUDIT_UI.md`), mais un périmètre
> resserré et quatre objectifs propres à cette page. Relevé du 2026-10-14
> (v1.64.1, sonde 0.9.28).

---

Tu es un designer produit senior spécialisé en applications macOS natives
(SwiftUI + AppKit, Human Interface Guidelines), capable de lire du Swift. Tu
vas auditer **au code source** l'onglet « Performances » de StarHubFR, un
gestionnaire de mods Stardew Valley pour macOS 14+.

REPO : https://github.com/mrbabilo/StarHubFR

CE QU'EST CETTE PAGE : la page lit les fichiers écrits par la **sonde**
StarHubFR (un mod SMAPI d'observation, `companion/StarHubFR.Probe/`, installé
dans `Mods/StarHubFR Probe/`) et par deux mods de performance tiers
(UltraSmooth « SLO », Stardropium). Elle ne calcule rien elle-même : tout vient
de `ProbePerformanceStore` et des stores de diagnostic (Core, testés). Elle
répond à une question de joueur : **« est-ce que mon jeu est plus lent qu'avant,
et à cause de quoi ? »** — et propose des gestes (mettre un mod en pause,
revenir à une config, lancer une mesure guidée ou pilotée, un benchmark de
chargements).

OBJECTIFS, de même rang :
1. **UX/UI** : lisibilité, hiérarchie de l'information, cohérence avec le
   reste de l'app (`PageChrome`, cartes, jetons `AppDesign`).
2. **Simplifier l'utilisation** : moins de notions à comprendre avant d'agir,
   moins de clics pour la tâche principale, un seul chemin évident par tâche.
3. **Guider et aider** : l'utilisateur sait toujours où il en est, ce qui lui
   manque, quoi faire ensuite, et pourquoi un bouton est grisé. Les textes
   d'aide disent ce que mesure un chiffre et ce qu'il **ne prouve pas**.
4. **Présentation des informations et fonctionnalités** : chaque section
   justifie sa place ; les redondances fusionnent ; les fonctionnalités
   absentes ou peu visibles sont nommées ; ce qui pourrait être retiré ou
   replié l'est.

UTILISATEUR DE RÉFÉRENCE : un joueur avancé, en français, ~1 000 mods
(Stardew Valley Expanded compris), qui joue **l'app en arrière-plan** et revient
dans l'onglet après coup. Il n'est pas statisticien : « médiane », « P99 »,
« quartiles », « minutes gardées » doivent être expliqués ou cachés.

────────────────────────────────────────────
LIMITES DE L'EXERCICE (non négociables)
────────────────────────────────────────────
1. **Ne jamais lancer l'app, le jeu, ni prendre de capture.** Tout
   comportement GUI déduit du code est une **hypothèse** ; chaque proposition
   finit par un **scénario GUI minimal** que l'humain rejoue.
2. **Ne pas toucher à la mesure elle-même** : les règles de comparaison
   (seuil 5 %, quartiles, minutes gardées, exclusions, qualité de preuve)
   sont des heuristiques assumées, tranchées dans
   `docs/superpowers/specs/2026-10-06-performances-clarte-analyse-design.md`
   §4. On peut mieux les **présenter**, pas les changer sans dire pourquoi.
3. **Aucune refonte globale.** Lots livrables un par un, chacun compilant seul
   (`python3 build_app.py`), un lot = une section ou un composant.
4. **Conservation** : chaque fonctionnalité de la table de la phase 1 garde,
   après proposition, une place à l'écran **et** un point d'entrée. Une ligne
   sans destination = proposition rejetée.
5. Ne rien pousser sur `main` sans demande.

────────────────────────────────────────────
PHASE 0 — Lire avant de proposer
────────────────────────────────────────────
Dans cet ordre :
  1. `AGENTS.md` §6 (contraintes UI figées) et §5.6 ; `CLAUDE.md` ;
     `docs/DOMAINE.md` (« profil », « sauvegarde », mod **en pause** =
     dossier préfixé d'un point).
  2. `docs/AUDIT_UI.md` — la grille à 5 dimensions, notée 0-4. Noter avec
     elle, pas avec une autre.
  3. Les décisions déjà prises sur **cette page**, pour ne pas les refaire :
     - `docs/superpowers/specs/2026-10-06-performances-clarte-analyse-design.md`
       — surtout §5 « Page proposée » (ordre de lecture, ancres, action
       principale selon l'état) et §8 « Acceptation » ;
     - `docs/superpowers/specs/2026-10-11-mesure-pilotee-design.md` §8 « UX »
       et §11 « écarté d'avance » ;
     - `docs/superpowers/specs/2026-09-29-d5-a-guided-measurement-design.md`
       (mesure guidée), `2026-09-30-benchmark-chargements-design.md`
       (benchmark), `2026-10-06-d2-t4-diagnostic-slo-design.md` et
       `2026-10-07-stardropium-diagnostic-design.md` (les deux diagnostics
       tiers) ;
     - `docs/ROADMAP.md`, axe D « Performance mesurée » : ce qui reste
       (**D4-T6** mémoire retenue, **D2-T6**, recette accessibilité/cycle de
       jeu, validations en jeu D4-T8/D5-A/D5-B) et §6 « Hors périmètre » ;
       `docs/roadmap-archive.md` pour le livré (D1 → D5) et ses mesures.
     Un choix tranché y porte sa raison. Le rouvrir exige une raison neuve,
     dite explicitement.
  4. `docs/REFACTORING.md` règle **F1-T2** : toute logique neuve (état
     d'écran, routage, regroupement) va dans un store (`StarHubTH/Stores/`)
     ou un type pur (`StarHubTH/Models/`), jamais dans `StarHubTHViewModel`.
  5. Le bloc de pièges de la sonde :
     `caveman mem recall "starhubfr traps sonde"` et
     `caveman mem recall "starhubfr traps ui"` (TimelineView en boucle,
     chiffre « gardé » borné à sa session, `.help` invisible sur petit
     glyphe, etc.).

────────────────────────────────────────────
PÉRIMÈTRE — relevé du 2026-10-14 (à remesurer en début de passe)
────────────────────────────────────────────
- **Code** : `StarHubTH/Views/Performance/` — 37 fichiers, 5 299 lignes.
  Racine : `PerformanceView.swift` (291 l.). Sections, dans l'ordre d'écran :
  `navigation` (ancres `ViewThatFits` → menu), `PerformanceMeasurementStatus`,
  `PerformanceGuidedBar` (331 l. : mesure guidée + pilotée), `Picker`
  « Dernière session / Comparer », `selectors` (avant / après),
  `PerformanceLiveIndicator`, `PerformanceSummarySection`,
  `PerformanceSloDiagnosticSection` (383 l.), `PerformanceAnalysisSection`
  (400 l., comparaison seulement), `PerformanceLoadsSection` (+ `Timeline`,
  `TopMods`, `Verdict`, `ProbeFirst`), `PerformanceChangesSection`,
  `PerformanceSmoothnessSection`, `PerformanceCostsSection`,
  `PerformanceStardropiumMemorySection` (+ `DiagnosticControls`), puis trois
  `DisclosureGroup` repliés : `PerformanceImpactSection` (historique, radar
  `ModImpactRadar`), `PerformanceTextureSection`,
  `PerformanceEnvironmentSection` (253 l.) ; enfin « Réglages » →
  `PerformanceProbeSection` et la ligne « lignes illisibles ».
  Hors page mais rattachés : `PerformanceBenchmarkSheet` (feuille),
  `BenchmarkPanelWindow` (fenêtre flottante du benchmark),
  `PerformancePilotReport` / `PilotStages` / `PilotStatus`,
  `ProbeMiniStatsToggle`, `PerformanceStyle.swift` (79 l., styles propres à
  la page : `PerformanceCard`, `.hoverLink`).
- **Points d'entrée** : segment `.performance` de `DiagnosticsSegment`
  (`DiagnosticsView`, `Picker` segmenté, troisième onglet après Santé et
  Journal) ; **aucun `pending…Focus` ne mène à cette page** et la palette
  de commandes ne la connaît pas (`CommandPaletteSearch` : zéro occurrence)
  — à vérifier, et à juger : comment un mod de la liste, une alerte santé ou
  une ligne de journal peuvent-ils y conduire ? Côté liste et fiche :
  `ImpactListBadge` (badge d'impact par mod), `mods_probe_*` dans
  `ModListRow` / `ModDetailSections` / `ProbeOptionsSection` (options de la
  sonde dans la fiche du mod sonde), `AppExtensionsSettingsSection`.
- **Textes** : 663 clés sur 2 581 dans `assets/fr.json` (préfixes `perf_`,
  `bench_`, `mods_probe_`, `perf_stard_`) — **un quart des libellés de l'app
  pour un onglet**. C'est en soi un constat à instruire : combien de ces
  textes l'utilisateur voit-il réellement, et lesquels disent la même chose ?
  Libellé le plus long : `perf_overlaps_intro` (271 caractères).
- **Surfaces modales de la page** : 10 `.sheet/.alert/.confirmationDialog`
  répartis dans 8 fichiers, plus la fenêtre du benchmark.
- **Jetons** : 0 `.system(size:)` littéral, 0 `padding(<nombre>)` — la page
  est la mieux migrée de l'app ; 8 couleurs système nues restent ; boutons :
  `.borderedProminent` 6, `.hoverLink` 7 (style **propre à cette page**),
  `.borderless` 2, `.bordered` 1, `.plain` 1 — juger si 6 actions
  principales peuvent coexister sur une page, et si `.hoverLink` doit monter
  dans `Views/Components/` ou disparaître.
- **États de la page** (`store.status` : `idle`, `loading`, `noProbe`,
  `needTwo`, `ready`, …) × **jeu lancé / en arrière-plan / quitté** × **mesure
  en cours** (guidée, pilotée, benchmark, diagnostic SLO, diagnostic
  Stardropium — cinq verrous croisés via `SloDiagnosticExclusion.busyReason`).
  Chaque combinaison est un écran différent que l'humain ne verra pas tous.

────────────────────────────────────────────
PHASE 1 — Inventaire : fonctionnalités, notions, états
────────────────────────────────────────────
Ne rien proposer avant qu'elle soit finie. Trois tables.

**1a. Table de conservation** — une ligne par fonctionnalité (y compris les
conditionnelles : bandeau « sonde pas en premier », « Profiler actif »,
« mettre à jour la sonde », reprise après interruption, retour arrière du
pilote, ligne « lignes illisibles ») :

| Fonctionnalité | Section / fichier | Points d'entrée | Condition d'affichage | État qui la masque |
|---|---|---|---|---|

**1b. Table des notions** — chaque mot que l'utilisateur doit comprendre
(session, mesure, côté avant/après, minute gardée, comparable, qualité de
preuve, confiance, médiane, P99, images lentes, tas, mémoire physique, coût
direct/indirect, pile Harmony, lieu, scène, SLO, Stardropium, sonde,
benchmark, mesure guidée, mesure pilotée, isoler, profil) :

| Notion | Où elle apparaît | Expliquée où (`.help`, sous-titre, note) | Indispensable à l'action ? |
|---|---|---|---|

Une notion « non indispensable » et « expliquée nulle part » est un candidat
au repli ou à la suppression ; une notion « indispensable » et « expliquée
nulle part » est une 🟡 friction d'office.

**1c. Table des états** — pour chaque état de `store.status` croisé avec
« jeu lancé / en arrière-plan / quitté » et « mesure en cours » : **ce que
l'utilisateur voit en premier, quelle est l'action principale, et qu'est-ce
qui lui dit où il en est**. La spec du 2026-10-06 §5 fixe l'action principale
attendue par état : relever les écarts.

Puis, pour chaque paire de lignes qui se recouvrent (ex. Résumé × Analyse,
Fluidité × Résumé, Historique × Coûts, Environnement × Réglages, les deux
diagnostics tiers entre eux, bandeau guidé × statut de mesure × indicateur
live), dire **en quoi** : même donnée, même action, même public, ou seulement
même mot.

────────────────────────────────────────────
PHASE 2 — Audit de la page, section par section
────────────────────────────────────────────
Pour chaque section de l'ordre d'écran, puis chaque feuille et la fenêtre du
benchmark :

- **Note** sur les 5 dimensions de `docs/AUDIT_UI.md`, avec la ligne de
  code qui justifie chaque note.
- **Première lecture** : qu'apprend l'utilisateur en 5 secondes ? La réponse
  à « plus lent qu'avant, à cause de quoi ? » est-elle la chose la plus
  visible, ou noyée sous les contrôles (ancres, statut, bandeau guidé,
  picker, sélecteurs, indicateur live viennent **avant** le résumé) ?
- **Parcours des tâches principales**, en clics depuis l'ouverture de
  l'onglet, et ce que l'utilisateur doit déjà savoir à chaque étape :
  1. installer / activer la sonde la première fois ;
  2. mesurer une première session, puis une deuxième ;
  3. comparer avant / après un changement et lire la conclusion ;
  4. agir sur la conclusion (pause, retour de config, isoler, re-mesurer) ;
  5. lancer une mesure pilotée ; comprendre pourquoi elle refuse ;
  6. lancer un benchmark de chargements ; lire son verdict ;
  7. lancer un diagnostic SLO ou Stardropium ; comprendre ce qu'il mesure
     que la sonde ne mesure pas ;
  8. mettre à jour la sonde ; comprendre qu'elle doit charger en premier ;
  9. revenir dans l'app après une partie et retrouver la bonne paire.
  Pour chaque tâche : y a-t-il **un seul** chemin évident, ou trois boutons
  concurrents (guidée, pilotée, benchmark, diagnostics) qui lancent tous le
  jeu sans dire en quoi ils diffèrent ?
- **Guidage** : où l'utilisateur apprend-il *pourquoi* un bouton est grisé
  (`busyReason`, `perf_pilot_ref_*`, `bench_ref_*`, `perf_pilot_locked`) ?
  Le motif est-il près du bouton, ou dans une infobulle que `.help` sur un
  petit glyphe n'affichera jamais ? Chaque état d'attente dit-il **combien de
  temps** et **ce que l'utilisateur doit faire** (rester dans le jeu,
  fenêtre au premier plan, ne pas ouvrir les menus) ?
- **Aide et vocabulaire** : relever les textes qui exigent une notion de la
  table 1b sans la définir ; les `.help` qui répètent le libellé ; les notes
  (`perf_evidence_*Note`, `perf_evidence_heuristic`) qui disent ce que la
  mesure ne prouve pas — sont-elles lues au bon moment (près du verdict) ou
  en bas de carte ?
- **Pire cas de mise en page**, obligatoire : libellé FR le plus long de la
  section (lire `assets/fr.json`) ; fenêtre à **560 pt** (les ancres passent
  en menu ; les boutons restent lisibles ou passent en icône + infobulle,
  I-T11) ; un parc de ~1 000 mods dans les listes de coûts et l'historique ;
  une session de 3 000 minutes dans les graphiques ; apparence sombre.
- **Chiffres** : chaque chiffre a une unité, une provenance et une date
  (spec §4.2) ; chaque verdict a sa qualité de preuve **à côté**, pas
  ailleurs ; un chiffre « gardé » après relecture vide est borné à sa session
  (v1.64.1) — vérifier que l'écran dit quand il montre un ancien chiffre.
- **Écart de spécification** : une fonctionnalité promise par les specs ou
  le CHANGELOG mais introuvable à l'écran, ou l'inverse (visible mais jamais
  spécifiée), se signale comme telle.

────────────────────────────────────────────
PHASE 3 — Simplifications et fusions candidates (hypothèses, pas verdicts)
────────────────────────────────────────────
Mesurer chacune contre les trois tables de la phase 1, puis conclure — y
compris « ne pas faire », avec la raison.

1. **Quatre façons de lancer le jeu pour mesurer** (mesure guidée, mesure
   pilotée, benchmark de chargements, diagnostics SLO / Stardropium) : un seul
   geste « Mesurer » qui demande *quoi* mesurer, ou quatre boutons chacun à
   sa place ? Qui a besoin de la guidée **manuelle** maintenant que la pilotée
   existe ?
2. **Trois zones d'état en tête de page** (`PerformanceMeasurementStatus`,
   `PerformanceGuidedBar`, `PerformanceLiveIndicator`) : une seule ligne
   d'état ?
3. **Résumé × Analyse × Fluidité × Coûts** en mode Comparer : quatre cartes
   qui parlent de la même paire. Combien de fois la conclusion est-elle
   répétée ? Que garder au-dessus du pli ?
4. **Les deux diagnostics tiers** (SLO, Stardropium) occupent des cartes
   permanentes même sans ces mods installés : à quelle condition se
   montrent-elles ? Un joueur sans UltraSmooth doit-il les voir ?
5. **Historique / Textures / Environnement / Réglages**, repliés : quatre
   `DisclosureGroup` à la suite — un onglet « Détails » unique, ou les laisser ?
   `Environnement` (253 l.) décrit-il la mesure ou le parc (déjà vu ailleurs) ?
6. **Picker « Dernière session / Comparer »** : un mode à choisir avant de
   voir quoi que ce soit, ou une page qui montre la dernière session et
   propose « comparer à… » en place ?
7. **Réglages de la sonde** en bas de page **et** options de la sonde dans la
   fiche du mod (`ProbeOptionsSection`) **et** `ProbeMiniStatsToggle` : un
   seul endroit ?
8. **Entrées manquantes** : depuis la ligne d'un mod (badge d'impact), depuis
   une alerte Santé « jeu lent », depuis le Journal (un `[Probe]` ou un
   avertissement UltraSmooth), depuis la palette ⌘K — vers *quelle* section,
   avec *quel* mod présélectionné ? Toute navigation neuve passe par un
   `pending…Focus` consommé dans `onChange(of: currentTab)` et vit dans
   `NavigationStore` (F1-T2).
9. **Fonctionnalités à proposer** (hors périmètre si déjà écartées dans les
   specs ou ROADMAP §6 ; le dire) : export d'un rapport (différé par la spec
   du 2026-10-06 — statut aujourd'hui ?), comparaison à plus de deux côtés,
   « que s'est-il passé depuis ma dernière visite », verdict en une phrase en
   tête de Santé, rappel « sonde à mettre à jour » hors de l'onglet, parcours
   « première fois » guidé pas à pas.

Tu peux en trouver d'autres ; chacune suit le même traitement.

────────────────────────────────────────────
PHASE 4 — Présentation : hiérarchie, couleur, boutons, aide
────────────────────────────────────────────
La charte de `prompt-audit-ux.md` phase 4 s'applique (échelle typographique,
sens → couleur, hiérarchie des boutons, espacement). Ici, mesurer la page
contre elle et trancher les points propres :

- **Une seule action principale par zone visible** : relever les 6
  `.borderedProminent` et dire laquelle reste principale selon l'état (spec
  §5 : « Installer », « Activer », « Mesurer une deuxième session »,
  « Comparer », « Lancer le jeu »).
- **Couleur sémantique des verdicts** : plus rapide / plus lent / pas de
  différence / pas assez de données / incertain — un jeton par sens, jamais
  la couleur seule (glyphe ou mot l'accompagne), identique entre Résumé,
  Analyse, Chargements, Pilote et Benchmark. Relever les 8 couleurs nues.
- **Densité des cartes** : sous-titre, note, `.help`, pied — combien de
  niveaux de texte secondaire par carte ? Lesquels l'utilisateur lit ?
- **Graphiques** : unités, provenance, légende stable au survol (acquis le
  2026-10-06), lisibilité en sombre et avec « Réduire les animations ».
- **États vides et d'attente** : chaque carte vide dit pourquoi et quoi faire
  (`perf_no_probe`, `perf_need_two`, `perf_evidence_insufficient`…) ; une
  attente dit sa durée et son prochain jalon (`PerformancePilotStages`).
- **Textes** : proposer, pour chaque libellé jugé trop long, ambigu ou
  jargonnant, une réécriture FR **et** EN (parité `assets/{en,fr}.json`,
  `L10n.swift`). Un libellé réécrit ne change pas le sens de la mesure.

────────────────────────────────────────────
CONTRAINTES TECHNIQUES
────────────────────────────────────────────
- **Cliquet** : `check_standards.py` verrouille la taille des fichiers de
  plus de 400 lignes ; `PerformanceAnalysisSection` (400) et
  `PerformanceSloDiagnosticSection` (383) sont au plafond. Toute extension se
  fait en sous-vue, jamais en relevant le plafond.
- **Relectures** : la page relit à l'ouverture, au retour d'onglet, au
  retour dans l'app, à la fermeture du jeu, au changement du parc. Un
  minuteur qui *agit* = `Task.sleep` ; `TimelineView` pour l'affichage seul
  (boucle corrigée v1.64.0).
- **Chiffres gardés** bornés à la session (`keepingNumbers(_:over:)`,
  v1.64.1) : après relance du jeu, des tirets, pas les chiffres d'avant.
- **Jeu actif** : toute action qui écrit dans `Mods/` reste refusée jeu
  lancé (`perf_game_running`) ; l'écriture dans un dossier de mod rejoue
  X7 (chmod).
- **`.help` sur petit glyphe** : cible ~18×18 (`frame` + `contentShape`).
- **Localisation** : parité stricte des clés ; supprimer les clés orphelines
  d'une fusion (663 aujourd'hui — le compte après la passe est une mesure).
- **Vue hors `StarHubTHViewModel`** (F1-T2) : état d'écran dans un store ou
  un type pur.

────────────────────────────────────────────
FORMAT DE SORTIE
────────────────────────────────────────────
1. **Les trois tables** de la phase 1 (conservation, notions, états),
   complètes.
2. **Notes par section** (phase 2) : tableau section × 5 dimensions, puis les
   constats, classés :
   - 🔴 **bloquant** : fonctionnalité inatteignable, utilisateur bloqué sans
     savoir pourquoi, verdict faux ou daté présenté comme actuel ;
   - 🟡 **friction** : parcours trop long, notion non expliquée, bouton grisé
     sans motif visible, chemin concurrent, état vide muet ;
   - 🔵 **finition** : alignement, couleur nue, libellé long, répétition.
   Chaque constat cite `fichier:ligne` et dit ce que l'utilisateur **voit**,
   pas ce que le code fait.
3. **Fiches de simplification / fusion** (phase 3) : avant / après ; lignes
   des tables touchées et leur destination ; coût (fichiers, clés L10n
   ajoutées / retirées, plafonds approchés) ; risque (ce qui disparaît en
   silence, en particulier les états que l'humain ne reproduira pas) ;
   scénario GUI à rejouer ; lot et ordre.
4. **Fiches de guidage** : pour chaque tâche principale de la phase 2, le
   parcours cible en clics, ce que l'écran dit à chaque étape, les textes
   FR/EN proposés.
5. **Fiches de présentation** (phase 4), avec les comptes remesurés
   (couleurs nues, styles de bouton, `.help`, clés L10n).
6. **Fonctionnalités** : à ajouter, à rendre visibles, à replier, à retirer —
   chacune avec la spec ou la décision archivée qui la cadre.
7. **Pistes écartées, avec la raison** (contrainte, décision archivée,
   mesure). Cette section vaut autant que les propositions.
8. **Ordre de livraison recommandé**, du gain le plus sûr au plus risqué, un
   lot = une section ou un composant.

────────────────────────────────────────────
DÉBUT DE SESSION
────────────────────────────────────────────
Lire `AGENTS.md` §6, `docs/DOMAINE.md`, `docs/AUDIT_UI.md`, la spec du
2026-10-06 §5 et §8, la spec du 2026-10-11 §8, puis `PerformanceView.swift`
en entier. Remesurer le périmètre (fichiers, lignes, clés L10n, couleurs
nues, styles de bouton, surfaces modales) avec un motif qui exclut les
commentaires, signaler toute dérive par rapport au relevé ci-dessus. Résumer
en 10 points : à quelle question la page répond, qui l'utilise et quand, ce
qu'elle montre en premier aujourd'hui, les quatre façons de lancer une mesure,
les états qui masquent des fonctionnalités, et les pièges qui pèsent sur une
simplification. Puis livrer la phase 1 et **s'arrêter** jusqu'à validation.
