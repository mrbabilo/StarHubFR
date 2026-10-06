# D2-T4 — Session diagnostique SLO réversible

Date : 2026-10-06. Relecture critique : 2026-10-07. Statut : design approuvé.

## 1. Objectif

Depuis l’onglet Performances, le joueur lance une session enrichie qui active
temporairement les diagnostics de Stardew Loading Optimizer (SLO) et la sonde
StarHubFR. Au retour, StarHubFR restaure exactement l’état initial, rapproche le
journal SLO des fichiers de la sonde et affiche une analyse claire : chargement,
caches, transitions, mémoire, fluidité et limites de la conclusion.

Le parcours doit aussi fonctionner quand SLO est absent : StarHubFR propose son
installation par le pipeline Nexus existant, sans lancer le jeu automatiquement.

Succès produit : un joueur peut obtenir les constats relevés pendant la session
réelle du 2026-10-06 sans lire `SMAPI-latest.txt`, sans laisser les diagnostics
actifs et sans confondre durée imbriquée, corrélation et cause.

## 2. Principes

- Le geste est explicite, temporaire et récupérable après fermeture inattendue de
  StarHubFR.
- Seules deux clés SLO sont écrites : `EnableDetailedDiagnostics=true` et
  `EnablePerformanceMeasurement=true`.
- `contentPatcherPerPatchProbe=True` est un état effectif publié dans
  `[OPTIMIZER CONFIG]`, pas une clé du `config.json` actuel. StarHubFR le vérifie
  au retour ; il ne crée pas de clé inventée.
- Les autres options SLO et les valeurs inconnues restent sémantiquement intactes
  pendant la préparation. Le JSON diagnostique peut normaliser sa mise en forme ;
  la restauration remet les octets originaux.
- Aucun mod de performance n’est désactivé automatiquement.
- Les durées de diagnostics natifs SLO peuvent être imbriquées. StarHubFR ne les
  additionne jamais pour fabriquer un total.
- Une seule session décrit ce qui a été observé ; elle ne prouve pas qu’une
  option ou un mod cause l’écart.

## 3. États et parcours

### 3.1 Disponibilité

Un modèle pur résout SLO par UniqueID `neoiw.StardewLoadingOptimizer` dans les
mods scannés, y compris les enfants de groupes. Les états affichables sont :

1. **SLO absent** — expliquer le besoin et proposer l’installation.
2. **Téléchargement ou installation en cours** — reprendre état global Nexus,
   y compris archive téléchargée dont la feuille d’installation est ouverte ;
   aucun second téléchargement.
3. **SLO installé en pause** — proposer « Activer SLO et lancer le diagnostic ».
4. **SLO actif, configuration compatible** — proposer le lancement.
5. **SLO incompatible** — version antérieure à 1.0.0, racine JSON non objet,
   fichier illisible ou valeur existante des deux clés de type autre que booléen ;
   proposer mise à jour ou correction, ne rien écrire.
6. **Jeu actif ou autre opération exclusive active** — action désactivée avec
   motif concret.
7. **Profil de lancement Vanilla** — demander de sélectionner SMAPI avant de
   préparer quoi que ce soit ; un diagnostic SLO ne peut pas exister en Vanilla.

La sonde StarHubFR reste une précondition. Son installation/mise à jour utilise
le bundle existant : une version plus ancienne que celle embarquée doit être mise
à jour ; une version égale ou plus récente est acceptée. Si elle est installée en
pause, le parcours peut l’activer pour la session puis restaurer son état initial.
Si elle manque ou doit être mise à jour, la carte propose le parcours
`ProbeBundle` existant ; aucun lancement n’est enchaîné automatiquement.

### 3.2 SLO absent

La page Nexus SLO est l’identifiant **50153**. Cet identifiant et le UniqueID
vivent dans un type de contrat unique, pas dans la vue.

- Si `nexusDirectDownloadUnavailable == false`, « Installer SLO » appelle
  le pipeline Nexus avec `nexusId: 50153` et UniqueID attendu
  `neoiw.StardewLoadingOptimizer`. Progression, annulation, file, validation de
  l’archive et feuille d’installation restent celles du pipeline commun.
- Sinon, « Ouvrir la page Nexus » ouvre la page des fichiers construite par le
  helper existant après avoir enregistré la même attente d’UniqueID. Un lien
  `nxm://` revient dans le pipeline StarHubFR et bénéficie de cette validation.
- L’installation conserve la règle générale : nouveau mod désactivé par défaut.
- Après confirmation de l’installation, le scan des mods fait évoluer la carte.
  Aucun lancement n’est enchaîné automatiquement.
- Archive annulée, invalide ou portant un autre UniqueID : état absent conservé,
  message du pipeline affiché, aucune session diagnostique créée.

### 3.3 Préparation

Une feuille présente avant écriture :

- SLO sera activé s’il est en pause ;
- la sonde sera activée si elle est en pause ;
- si SLO ou la sonde appartient à un dossier groupé en pause, les autres mods de
  cette racine seront aussi activés par le renommage et leurs noms sont listés ;
- les deux clés diagnostiques passeront à `true` pour cette session ;
- le volume du journal et le léger surcoût attendus ;
- la restauration automatique prévue après fermeture du jeu.

Après confirmation seulement, StarHubFR :

1. refuse si le profil choisi est Vanilla, si le jeu est actif ou si benchmark,
   bissection, profil ou mouvement de mods occupe déjà le parc ;
2. résout les racines logiques, leurs chemins physiques initiaux et les chemins
   qu’elles auront une fois actives ;
3. lit `config.json` à son chemin initial et conserve ses octets exacts, ou note
   son absence ;
4. décode un objet JSON — jamais `.allowFragments` — avec tolérance JSON5 déjà
   utilisée par le projet ; un fichier absent devient un objet diagnostique
   minimal pour SLO >= 1.0.0 ;
5. construit les octets diagnostiques et leur empreinte, puis persiste le plan
   complet de récupération avant le premier changement disque ;
6. active les racines SLO et/ou sonde par renommage même-parent si nécessaire et
   vérifie leur état réel après callback ;
7. ouvre les droits propriétaire du dossier SLO, écrit atomiquement au chemin
   actif, puis relit et vérifie l’empreinte ;
8. lance le jeu par `launchGame(honoringCloseAfterLaunch: false)` et surveille
   son apparition puis sa fermeture.

Si une étape échoue, les étapes déjà appliquées sont restaurées. Le jeu ne part
que lorsque plan, configuration et états de mods concordent avec la préparation.

## 4. Transaction et récupération

### 4.1 Instantané persistant

Un fichier sous Application Support/StarHubFR contient : identifiant UUID,
date de préparation et de demande de lancement, racine `Mods` résolue, chemins
logiques et physiques initiaux/actifs des racines, chemins initial/actif de
`config.json`, état initial
SLO/sonde, état initial du fichier (`absent` ou octets), octets diagnostiques et
leurs empreintes acceptées (écriture StarHubFR, puis éventuelle normalisation SLO
attestée au lancement), état « jeu déjà vu », offset ou identité du journal avant
lancement et derniers identifiants de session connus de la sonde. Cette copie
locale sert uniquement à la récupération ; son contenu n’est jamais ajouté aux
journaux.

Écriture de l’instantané : fichier temporaire puis remplacement atomique. Un seul
plan existe. Un plan présent rend benchmark, bissection et autre diagnostic
indisponibles jusqu’à restauration ou résolution.

### 4.2 Fin normale

`GameExit.publisher` signale la fermeture. Le suivi par sondage applique le même
délai de stabilisation de trois secondes avant lecture ; les deux chemins
convergent vers une seule finalisation idempotente :

1. relire journal et fichiers sonde ;
2. construire puis publier le rapport même si certaines sources manquent ;
3. tant que la racine SLO est active, restaurer `config.json` à son **chemin
   actif** seulement si son contenu correspond à une empreinte diagnostique
   acceptée ;
4. restaurer ensuite états SLO/sonde par leurs racines, seulement s’ils
   correspondent encore à l’état temporaire attendu ;
5. effacer plan uniquement après restauration complète ;
6. rescanner parc et recharger Performances.

Le rapport dérivé est enregistré localement avant effacement du plan afin que la
carte « dernier rapport » survive à un redémarrage. Ce reçu contient résultats,
limites, identifiant/date de session et empreintes des sources, jamais journal
brut ni contenu de configuration. Un échec d’enregistrement ne retarde pas la
restauration du parc.

### 4.3 Modification concurrente et reprise

Si `config.json` a changé pendant jeu, StarHubFR ne l’écrase pas. Le plan reste
visible en état « configuration modifiée » avec deux actions : ouvrir dossier ou
restaurer explicitement la copie initiale après confirmation. Même règle si un
état de mod ne correspond plus à l’état temporaire attendu.

Après demande de lancement, une surveillance reprend le patron à deux temps du
benchmark : processus vu puis disparu = fin ; processus jamais vu pendant 90 s =
lancement échoué et restauration. Elle n’arrête jamais le jeu et n’impose pas de
durée maximale à une partie.

Au démarrage de StarHubFR ou à son retour au premier plan :

- jeu encore actif : garder plan et afficher « diagnostic en cours » ;
- aucune demande de lancement persistée : reprendre le rollback pré-lancement ;
- jeu pas encore vu et demande vieille de moins de 90 s : attendre et surveiller,
  car Steam/SMAPI peut encore démarrer ;
- jeu déjà vu puis fermé, ou jamais vu après 90 s : analyser ce qui existe puis
  restaurer automatiquement si état temporaire intact ;
- état divergent : garder plan et demander résolution ;
- racine `Mods` indisponible, racine attendue absente ou formes active et pointée
  présentes ensemble : garder plan sans conclure que le fichier était absent ;
- plan illisible : ne rien modifier, afficher erreur récupérable et emplacement.

Une restauration répétée est idempotente. Fichier initialement absent : le
fichier diagnostique est retiré seulement s’il est toujours identique à celui
écrit par StarHubFR ou à la normalisation SLO attestée. Lors de l’analyse, une
nouvelle empreinte n’est acceptée que si elle correspond aux octets réellement
lus, que les deux clés restent booléennes et vraies, que l’inventaire de la
session les attribue à SLO et que la dernière ligne effective du journal confirme
les diagnostics. Toute modification ultérieure reste un conflit.

Chaque racine est jugée séparément : état temporaire = à restaurer, état initial
= déjà restauré, autre état = conflit. Si une reprise trouve la racine SLO déjà
repointée, elle vérifie l’original au chemin initial au lieu d’interpréter le
chemin actif disparu comme un fichier supprimé. Cette règle couvre crash après
activation, après écriture, après restauration config et après renommage.

## 5. Corrélation de session

Le rapport doit porter sur lancement produit par ce plan :

- journal SLO : lire uniquement le `SMAPI-latest.txt` du lancement postérieur à
  la préparation et les lignes après borne enregistrée ;
- sonde : sélectionner nouvelle session d’inventaire postérieure à préparation,
  qui contient `mrbabilo.StarHubFR.Probe` et SLO ; une empreinte `config.json`
  de SLO égale à l’écriture diagnostique est la preuve forte. Une empreinte
  différente n’est admise que comme normalisation attestée selon §4.3 ; puis lire
  `loads.jsonl`, `timings.jsonl` et `mod-costs.jsonl` par même identifiant
  `Session` ;
- accepter rapport SLO partiel si session sonde absente ou interrompue, avec
  limite explicite ;
- refuser mélange avec session antérieure, même si elle est dernière dans un
  fichier ;
- conserver date, version SLO, version sonde et couverture dans rapport.

Le parseur travaille hors MainActor. Une génération de relecture empêche un ancien
résultat d’écraser une session plus récente.

## 6. Rapport diagnostique

`SloDiagnosticReport` est un modèle pur et `Sendable`. Il expose données et
interprétations séparément.

### 6.1 Configuration effective

Parser dernière ligne `[OPTIMIZER CONFIG]` de la tranche de journal. Le helper
historique `SloOptimizerConfig.parse(log:)` prend aujourd’hui la première ligne :
le nouveau parseur doit parcourir à rebours ou fournir `parseLatest`, sans lui
attribuer implicitement cette sémantique. Vérifier : diagnostics
détaillés, mesure performance et sonde Content Patcher effectifs. Afficher option
attendue mais absente ou désactivée ; ne pas supposer que l’écriture a été honorée.

### 6.2 Chargement

- Temps lancement et sauvegarde depuis la sonde, avec phases.
- Plus grand temps direct mesuré par mod et couverture des coûts.
- `[CONTENT PATCHER HOTSPOTS]` et `[NATIVE SUMMARY]` comme scopes imbriqués.
- « Principale attente observée » peut nommer un scope dominant, jamais « cause ».
- Les durées imbriquées apparaissent dans détail et ne sont pas sommées.
- Comparaison historique seulement via règles `ProbeLoadComparison` existantes.

### 6.3 Caches et préparation

- Carte : fichiers, taille, succès, échecs, corruptions, temps observé.
- Images : capacité, occupation, succès, échecs, évictions, admissions refusées,
  décodages initiaux et préparation arrière-plan.
- Préchargement : état, fichiers prévus/lus, octets et achèvement.
- Tuiles différées : appels reportés, sources en attente/réchauffées, échecs.
- SpaceCore : fast-path, replis, échecs, initialisation parallèle.

« Utilisé » exige au moins un succès. « Cache presque plein » exige occupation
>= 90 % de limite. « Échec » exige compteur d’échec non nul. Temps passé dans un
cache n’est jamais présenté comme temps économisé sans mesure témoin. Les lignes
`SNAPSHOT` sont cumulatives : garder la dernière valide de chaque famille, jamais
additionner plusieurs instantanés. Pour prélecture, garder état le plus récent et
son achèvement ; pour événements warp, agréger chaque événement une seule fois.

### 6.4 Transitions et jeu

- `[FAST WARP COMPLETE]` : nombre, médiane, minimum, maximum et destinations.
- `[FAST WARP ABORT]`/`EXCLUDED` : nombre et raison, présentés comme repli de
  sécurité lorsque journal le dit.
- Fluidité stable issue des minutes valides de la sonde, séparée des minutes de
  chargement et de transition. Une transition appartient à la fenêtre
  `(At - WallSeconds, At]` qui contient un `WarpRequest`, `FAST WARP COMPLETE`,
  `ABORT` ou `EXCLUDED` ; passage de minuit géré à partir de la date de session.
  Si cette corrélation temporelle échoue, ne pas prétendre exclure les
  transitions et afficher la limite.
- Coût propre SLO issu de `mod-costs.jsonl` : ms/s, maximum, allocations et
  couverture Harmony. `PatchesMeasured=false` limite attribution.
- Mises à jour lentes en état Ready : nombre et maximum, sans les confondre avec
  blocages du chargement.

### 6.5 Mémoire et limites

- Pic Working Set comparé à `workingSetSoftLimit` ; « proche » à >= 90 %,
  « dépassée » à >= 100 %.
- Mémoire réservée et gérée restent des métriques distinctes.
- Cache image saturé n’est pas automatiquement pression mémoire.
- Limites listées : session unique, source manquante, diagnostic incomplet,
  Harmony non mesuré, durée courte, absence de comparaison témoin, fermeture
  avant fin et scopes imbriqués.

## 7. Interface

Une carte « Diagnostic SLO » se place directement sous résumé/analyse, donc avant
les détails. Elle reste visible dans tous les états : installation, préparation,
session en cours, restauration bloquée ou dernier rapport.

Rapport terminé :

1. verdict court et daté ;
2. quatre lignes : chargement, transitions, caches, fluidité/mémoire ;
3. limites visibles sans déplier ;
4. graphiques seulement quand ils clarifient au moins deux valeurs : barres
   classées des attentes de chargement (jamais empilées), points des transitions
   avec médiane, chronologies séparées fluidité et mémoire ;
5. barres de capacité pour caches avec valeur et limite textuelles ;
6. détails repliables par source ;
7. action « Refaire le diagnostic ».

Chaque graphique garde une ligne de détail de hauteur fixe sous son tracé : le
survol ou clic la remplit sans déplacer contenu suivant. Les mêmes détails sont
accessibles au clavier/VoiceOver, axes portent unité en clair, absence ou valeur
unique reste texte. Aucune animation quand Réduire les animations est actif.

Les textes privilégient secondes, millisecondes, Mo/Go, succès/échecs et noms de
mods. Termes internes (`scope-exclusive`, phase native, hit) sont traduits ou
réservés aux détails. Chaque bouton utilise `AdaptiveLabels`, aide et libellé
lisible à 560 pt. Animations limitées à 150 ms et respectent Réduire les animations.

## 8. Architecture

- `Models/SloDiagnosticContract.swift` : UniqueID, Nexus ID, clés et disponibilité.
- `Models/SloDiagnosticTransaction.swift` : instantané, préparation, décision de
  restauration, sérialisation persistante et opérations pures testables.
- `Models/SloDiagnosticReport.swift` : parseurs de lignes, agrégats et limites.
- `Stores/SloDiagnosticSessionStore.swift` : orchestration `@MainActor @Observable`,
  I/O et calcul hors MainActor, génération/annulation.
- `Views/Performance/PerformanceSloDiagnosticSection.swift` : états, feuille,
  rapport et gestes ; aucun calcul statistique.
- `PerformanceView` possède ou reçoit store, recharge avec autres sources et
  écoute fermeture du jeu.

La fonctionnalité neuve ne rejoint pas `StarHubTHViewModel`. La vue appelle ses
gestes existants pour téléchargement Nexus, lancement, scan et renommage de mods.

L’instantané sert aussi de verrou durable. `BenchmarkRunner`, `BisectionRunner`
et `ProbePerformanceStore.prepare` refusent de démarrer tant qu’il existe ; le
store SLO refuse symétriquement leurs états actifs ou plans persistants. Les
gestes manuels sur mods restent possibles, mais deviennent divergence visible et
ne sont jamais écrasés à la restauration.

## 9. Erreurs et cas limites

- SLO absent, en pause, groupé, dupliqué ou version incompatible.
- Sonde absente, en pause, plus ancienne que le bundle ou bundle indisponible.
- `config.json` absent, illisible, scalaire, commentaires/trailing commas ou
  clés de type invalide.
- Jeu lancé entre affichage feuille et confirmation.
- Échec écriture plan, droits dossier, écriture/relecture configuration,
  activation mod ou lancement.
- Profil Vanilla, processus jamais apparu et redémarrage pendant délai Steam.
- Crash entre deux étapes de préparation/restauration, avant demande de lancement.
- Volume du jeu démonté, racine supprimée ou collision `X`/`.X` pendant reprise.
- StarHubFR fermé avant apparition du processus jeu.
- Jeu jamais apparu, crashé, encore actif lors reprise ou fermé sans notification.
- Configuration et dossiers modifiés par utilisateur pendant session.
- Journal tronqué/rotaté, ancienne session seule, ligne SLO nouvelle ou partielle.
- Compteurs non finis, négatifs, limites nulles et aucune transition.
- Téléchargement Nexus indisponible, annulé, en file ou archive inattendue.

Chaque cas aboutit à état explicite. Aucun ne produit restauration aveugle, zéro
inventé ou rapport attribué à mauvaise session.

## 10. Tests et validation

Tests Swift Testing, données synthétiques anonymisées :

- disponibilité et route installation directe/page Nexus ;
- modification exclusive des deux clés, JSON racine obligatoire et conservation
  des clés inconnues ;
- restauration exacte, fichier initialement absent, divergence et idempotence ;
- récupération après redémarrage dans états jeu actif/fermé/divergent ;
- corrélation stricte session/journal, inventaire sonde, SHA exact et voie de
  normalisation SLO attestée ;
- chemins initial/actif lorsque racine pointée est renommée, ordre restauration
  config avant dossiers et groupe activant des mods frères ;
- profil Vanilla, processus jamais vu, redémarrage avant/après délai de 90 s ;
- parsing configuration, caches, préchargement, tuiles, SpaceCore, hotspots,
  warps, avertissements et mémoire ;
- médiane transitions, seuils 90/100 %, valeurs invalides et scopes non additionnés ;
- rapport partiel et limites ;
- persistance du dernier rapport sans journal ni configuration bruts ;
- exclusion mutuelle SLO/benchmark/bissection/mesure guidée, dans les deux sens ;
- cycle store par dépendances injectées, génération obsolète ignorée ;
- parité `en.json`/`fr.json`.

Validation dépôt : `python3 build_app.py`, `./run_tests.sh`,
`python3 check_standards.py --report` et `python3 check_sources.py --offline` si
un contrat externe est ajouté ou modifié. Vérification GUI déléguée au joueur :
SLO absent, installation, lancement, retour, rapport, restauration et largeur
560 pt. Agent ne lance jamais application et ne prend jamais capture.

## 11. Hors périmètre

- Installer ou désactiver automatiquement d’autres mods de performance.
- Modifier limites de cache ou profil SLO.
- Promettre gain sans essai témoin.
- Automatiser un A/B SLO activé/désactivé ; benchmark existant reste distinct.
- Envoyer journal, configuration ou télémétrie hors machine.
- Dépendre d’un nouveau service ou d’une bibliothèque tierce.
