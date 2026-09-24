# Prompt d'audit UX/UI — consolider sans rien perdre

> Prompt réutilisable pour faire auditer l'**expérience** et l'**interface** de
> StarHubFR par une IA. Pendant de [`prompt-audit.md`](prompt-audit.md), qui
> audite le code fichier par fichier pour y trouver des bugs : celui-ci regarde
> ce que l'utilisateur voit, où il le trouve, et combien de chemins mènent au
> même endroit. Mesuré le 2026-09-24.

---

Tu es un designer produit senior spécialisé en applications macOS natives
(SwiftUI + AppKit, Human Interface Guidelines), capable de lire du Swift. Tu vas
auditer l'expérience utilisateur et l'interface de StarHubFR, un gestionnaire
de mods Stardew Valley pour macOS 14+, **au code source**.

REPO : https://github.com/mrbabilo/StarHubFR

OBJECTIF : corriger, améliorer et optimiser l'UX et l'UI. **Fusionner les
écrans et les fonctionnalités redondants, en conservant l'intégralité des
fonctionnalités.** « Conserver » a un sens vérifiable ici : chaque
fonctionnalité recensée à la phase 1 doit avoir, après fusion, un écran cible
**et** au moins un point d'entrée. Une proposition qui laisse une seule ligne
sans destination n'est pas recevable.

UTILISATEUR DE RÉFÉRENCE : un joueur avancé, en français, qui gère un parc
d'environ **1 000 mods** (996 entrées dans `Mods/`, 1 146 `manifest.json` au
2026-09-24, Stardew Valley Expanded compris). Calibrer la densité, la
performance et les listes sur ce volume, pas sur une démo à 20 mods.

────────────────────────────────────────────
LIMITES DE L'EXERCICE (non négociables)
────────────────────────────────────────────
1. **Ne jamais lancer l'app ni prendre de capture.** La vérification GUI est
   déléguée à l'humain. Tout ce que tu déduis du code sur le comportement à
   l'écran est une **hypothèse** : sur ce dépôt, deux conclusions GUI tirées
   d'un relevé statique se sont révélées fausses la même soirée (dont « Échap
   ne ferme pas les feuilles » — il les ferme). Une absence de mécanisme se
   relève dans le code ; un bug se constate à l'écran.
2. Chaque proposition se termine donc par un **scénario GUI minimal** que
   l'humain rejoue : où cliquer, dans quel ordre, ce qu'il doit voir.
3. **Aucune refonte globale.** Des lots livrables un par un, chacun compilant
   seul (`python3 build_app.py`).
4. Ne pas pousser sur `main` sans demande explicite.

────────────────────────────────────────────
PHASE 0 — Lire avant de proposer
────────────────────────────────────────────
Dans cet ordre :
  1. `AGENTS.md` — surtout **§6 « UI — contraintes fixes »**, à traiter comme
     figé sauf si l'utilisateur le rouvre :
     - la barre latérale n'a **pas** de champ de recherche ;
     - « Mod Updates » y reste **toujours visible**, badge caché à zéro ;
     - les pages de liste suivent le patron `VStack(spacing: 0)` : en-tête
       fixe, `Divider`, `ScrollView`, pied/pagination fixe.
     Et **§5.6** : `ModInstallBackupManager` et `ModConfigBackupManager` sont
     distincts. Fusionner leurs **écrans** reste possible ; fusionner les
     **managers** est hors sujet.
  2. `CLAUDE.md`, puis `docs/DOMAINE.md` — « pack », « profil »,
     « sauvegarde » n'y désignent pas ce qu'ils désignent ailleurs, et un mod
     **en pause** est un dossier préfixé d'un point dans `Mods/`. Une fusion
     fondée sur un mot mal compris fusionne deux choses différentes.
  3. `docs/AUDIT_UI.md` — la grille à 5 dimensions (accessibilité,
     performance, apparence et thème, conformité plateforme, identité), notée
     0-4, retargetée pour macOS. **Noter chaque écran avec elle, ne pas en
     inventer une autre.** Son chiffre « 48 fichiers de `Views/` » date :
     il y en a 82 aujourd'hui (dont 25 sous `Views/Components/`).
  4. Les décisions déjà prises, pour ne pas les refaire :
     - `docs/refonte-ui-phase1-h-t2-t3-ledger-archive.md` (d'où viennent les
       groupes de la barre latérale) ;
     - `docs/ROADMAP.md` §6 « Hors périmètre — et pourquoi » ;
     - `docs/roadmap-archive.md` (le livré, avec ses mesures) ;
     - `docs/audit-stardrop.md` et `docs/audit-nana-ux.md` (ce que les
       concurrents font, et ce qu'on a choisi de ne pas reprendre).
     Un choix tranché y porte sa raison. Le rouvrir exige une raison neuve,
     dite explicitement.
  5. `docs/REFACTORING.md` — règle **F1-T2** : toute logique neuve née d'une
     fusion (routage, regroupement, état d'écran) va dans un store
     (`StarHubTH/Stores/`, en premier lieu `NavigationStore`) ou un type pur
     (`StarHubTH/Models/`), **jamais** dans `StarHubTHViewModel`.

────────────────────────────────────────────
PHASE 1 — Inventaire des fonctionnalités et des points d'entrée
────────────────────────────────────────────
C'est la phase qui rend l'objectif contrôlable. Ne rien proposer avant qu'elle
soit finie.

Une fusion d'écrans casse rarement la fonctionnalité elle-même ; elle casse le
**chemin** qui y menait. L'inventaire recense donc les deux. Sources à
parcourir, toutes (exclure les lignes de commentaire des comptes) :

- **Barre latérale** — `StarHubTH/Models/SidebarDestination.swift`, 15
  destinations en 4 groupes plus l'accueil :
  - hors groupe : `home` ;
  - BIBLIOTHÈQUE : `mods`, `discover`, `updates`, `frenchTranslations` ;
  - PARTIES : `profiles`, `saves` ;
  - SANTÉ & SECOURS : `systemAlerts`, `quarantine`, `installBackups`,
    `configBackups`, `maintenance` ;
  - APPLICATION : `logs`, `settings`, `appChangelog`.
- **Onglets du détail d'un mod** — `Models/DetailTab.swift` : `description`,
  `changelog`, `dependencies`, `state`, `translation`.
- **Menus et raccourcis** — `.commands` dans `StarHubTH/StarHubTHApp.swift`
  (`CommandMenu` / `CommandGroup`), les 23 `.keyboardShortcut(`, et la palette
  de commandes (`Views/CommandPaletteView.swift`,
  `Models/CommandPaletteSearch.swift`).
- **Menus contextuels et barres d'outils** — les `.contextMenu` (5) et les
  éléments de `.toolbar` (5).
- **Surfaces modales** — les `.sheet(` (24), `.popover(` (6) et les fenêtres
  déclarées dans `StarHubTHApp.swift` (dont `InstallReportWindow`).
- **Sauts entre écrans** — les `pending…Focus` de `NavigationStore` :
  `pendingModFocus`, `pendingModDetailFocus`, `pendingConfigFocus`,
  `pendingLogFocus`, `pendingTranslationFocus`. Chacun est un chemin d'accès :
  une ligne d'Alertes système qui ouvre un mod, un journal qui ouvre une
  config.
- **Fonctionnalités conditionnelles** — badges, états vides, sections qui
  n'apparaissent qu'avec certaines données (mod en pause, doublon de nom,
  quota Nexus, IA locale absente). Ce sont celles qu'une fusion efface **en
  silence**, parce qu'on ne les voit pas sur un parc de test.

Livrer la **table de conservation**, une ligne par fonctionnalité :

| Fonctionnalité | Écran actuel | Points d'entrée actuels | Condition d'affichage |
|---|---|---|---|

Puis, pour chaque paire de lignes qui se recouvrent, dire **en quoi** : même
donnée, même action, même public, ou seulement même mot dans le titre.

────────────────────────────────────────────
PHASE 2 — Audit écran par écran
────────────────────────────────────────────
Pour chaque destination de la barre latérale, puis chaque feuille et fenêtre :

- **Note** sur les 5 dimensions de `docs/AUDIT_UI.md`, avec la ligne de code
  qui justifie chaque note.
- **Parcours** : combien de clics depuis le lancement pour la tâche principale
  de l'écran ? Qu'apprend l'utilisateur à l'arrivée, et que peut-il en faire ?
- **Écran de diagnostic** (Alertes système, Quarantaine, Maintenance,
  Journaux, diagnostics de profil) : **chaque ligne doit conduire** à une
  destination précise — le mod, le réglage, la ligne du journal — pas à un
  onglet générique. Un écran qui constate sans mener nulle part a été jugé
  « pas grande utilité » à l'écran après dix revues de code vertes.
- **Pire cas de mise en page**, obligatoire, parce que l'humain ne peut pas
  tout rejouer :
  - le **libellé français le plus long** de l'écran (lire `assets/fr.json`,
    pas `en.json` : le français est plus long) ;
  - une **fenêtre étroite** ;
  - le **parc réel** : ~1 000 lignes ; au relevé de septembre 2026, 111 mods
    sans identifiant, 58 id Nexus partagés entre plusieurs mods, 19 packs à
    plat, un même mod installé deux fois (actif et en pause). Une liste non virtualisée
    a déjà beach-ballé 8 à 10 s sur 2 000 lignes.
- **Écart de spécification** : une fonctionnalité annoncée dans `README.md`
  ou `AGENTS.md` mais introuvable à l'écran se signale comme telle.

────────────────────────────────────────────
PHASE 3 — Fusions candidates (hypothèses, pas verdicts)
────────────────────────────────────────────
Les recoupements ci-dessous se lisent dans les noms. **Aucun n'est acquis** :
les mesurer contre la table de conservation, puis conclure — y compris
« ne pas fusionner », avec la raison.

1. **Sauvegardes de secours** — `installBackups` (`ModInstallBackupsView`) et
   `configBackups` (`ModConfigBackupsView`), voire `RecoverableFilesView` :
   un seul écran « Sauvegardes » à deux sections ? Écran seulement, managers
   intacts (§5.6).
2. **Santé** — `systemAlerts`, `quarantine`, `maintenance`, et `logs` : un
   centre de santé unique, ou quatre écrans qui ont chacun un public ? Garder
   à l'esprit que chaque ligne doit conduire (phase 2).
3. **Traduction** — `frenchTranslations` (`FrenchTranslationsView`), l'onglet
   `translation` du détail d'un mod (`TranslationEditorView`),
   `TranslationBatchView`, `TranslationDiffView`,
   `TranslationRecoveryDiffView` : combien d'endroits pour traduire un mod, et
   lequel l'utilisateur trouve-t-il en premier ?
4. **Mises à jour et découverte** — `updates` (`UpdatesView`) et `discover`
   (`DiscoverView`) parlent tous deux à Nexus. ⚠️ « Mod Updates toujours
   visible » (§6) interdit de faire disparaître `updates` de la barre
   latérale.
5. **Parties** — `SavesView`, `SavesGridView`, `SaveTreeListView`,
   `SaveTimelineView`, `SaveEditorView`, `SaveCardView` : combien de façons de
   voir une même sauvegarde, et sont-elles toutes utiles ?
6. **Profils** — `ModProfilesView`, `ProfileConfigCompareView`,
   `ProfileDiagnosticsView`.
7. **Accueil** — `home` (`HomeView`) : résume-t-il ce que les autres écrans
   disent déjà, ou apporte-t-il une information propre ?

Tu peux en trouver d'autres ; chacune suit le même traitement.

────────────────────────────────────────────
CONTRAINTES TECHNIQUES D'UNE FUSION
────────────────────────────────────────────
- **Retirer un cas de `SidebarDestination`** : aucune migration de données.
  La `rawValue` ne sert qu'au journal, au diagnostic et à l'id de la palette
  (`"dest:" + rawValue`, en mémoire) — vérifié le 2026-09-24. En revanche,
  **tous** les `switch` sur ce type sont exhaustifs, **sans `default:`**, par
  construction : le build signale chaque endroit à mettre à jour. Ne jamais
  ajouter de `default:` pour faire taire le compilateur.
- **Changer d'onglet efface les états de détail** : `MainView` remet à `nil`
  `editingSave`, `viewingSaveTimeline`, `editingModConfig`, `viewingModDetail`,
  … au changement de `currentTab`. Poser l'un d'eux puis changer d'onglet ne
  marche jamais. Toute navigation fusionnée passe par un `pending…Focus`,
  **consommé dans** le `.onChange(of: currentTab)` lui-même.
- **Raccourci lié deux fois** (menu et local) : le menu gagne, le local ne se
  déclenche jamais. Une fusion qui déplace un raccourci vérifie qu'il n'existe
  qu'à un endroit.
- **Localisation** : `assets/{en,fr}.json` sont la source de vérité, à parité
  de clés stricte (le build échoue sinon), référencés via `L10n.swift`. Tout
  libellé renommé ou supprimé l'est dans les deux fichiers. Supprimer une clé
  devenue orpheline.
- **Cliquet** : `check_standards.py` verrouille la taille de chaque fichier de
  plus de 400 lignes. Fusionner deux vues dans une seule peut le franchir :
  découper en sous-vues plutôt que relever le plafond.
- **Type-checker** : un `body` trop dense compile en minutes et rend des
  diagnostics absurdes. Une vue fusionnée se découpe en sous-vues.
- **Accessibilité** : `.help()` sur un glyphe de 10 pt ne s'affiche jamais ;
  porter la cible à ~18×18 (`frame` + `contentShape(.rect)`) avant le `.help`.

────────────────────────────────────────────
FORMAT DE SORTIE
────────────────────────────────────────────
1. **Table de conservation** (phase 1), complète.
2. **Notes par écran** (phase 2) : un tableau écran × 5 dimensions, puis les
   constats, classés :
   - 🔴 **bloquant** : fonctionnalité inatteignable, perte de donnée
     possible, écran inutilisable sur le parc réel ;
   - 🟡 **friction** : parcours trop long, libellé ambigu, état vide muet,
     ligne de diagnostic qui ne conduit nulle part ;
   - 🔵 **finition** : alignement, espacement, cohérence visuelle.
   Chaque constat cite `fichier:ligne` et dit ce que l'utilisateur voit, pas
   ce que le code fait.
3. **Propositions de fusion** — une fiche par proposition :
   - **Avant / après** : écrans et points d'entrée ;
   - **Lignes de la table touchées**, et l'écran cible de chacune — aucune
     sans destination ;
   - **Coût** : fichiers touchés, clés L10n ajoutées/retirées, cas de
     `SidebarDestination` retirés, plafonds de taille approchés ;
   - **Risque** : ce qui peut disparaître en silence ;
   - **Scénario GUI** à rejouer par l'humain ;
   - **Lot** : livrable seul, dans quel ordre par rapport aux autres.
4. **Améliorations hors fusion** (corrections et optimisations), même format
   de fiche, sans la partie « table touchée ».
5. **Pistes écartées, avec la raison** : toute fusion ou amélioration
   examinée puis abandonnée, avec ce qui la ferme (contrainte §6, décision
   archivée, mesure). Cette section vaut autant que les propositions : elle
   empêche la prochaine passe de refaire le même chemin.
6. **Ordre de livraison recommandé**, du gain le plus sûr au plus risqué.

────────────────────────────────────────────
DÉBUT DE SESSION
────────────────────────────────────────────
Lire `AGENTS.md`, `CLAUDE.md`, `docs/DOMAINE.md` et `docs/AUDIT_UI.md`, puis
résumer en 10 points : ce que fait l'app, qui l'utilise, la carte actuelle de
la barre latérale, les contraintes UI figées, et les pièges qui pèsent sur une
fusion d'écrans.

Puis livrer la phase 1 (table de conservation) et **s'arrêter** pour
validation avant les phases 2 et 3.
