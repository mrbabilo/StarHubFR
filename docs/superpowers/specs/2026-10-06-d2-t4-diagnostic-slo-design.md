# D2-T4 — Session diagnostique SLO réversible

Date : 2026-10-06. Statut : design approuvé.

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
2. **Téléchargement ou installation en cours** — reprendre état global Nexus ;
   aucun second téléchargement.
3. **SLO installé en pause** — proposer « Activer SLO et lancer le diagnostic ».
4. **SLO actif, configuration compatible** — proposer le lancement.
5. **SLO incompatible** — version antérieure à 1.0.0, racine JSON non objet,
   fichier illisible ou valeur existante des deux clés de type autre que booléen ;
   proposer mise à jour ou correction, ne rien écrire.
6. **Jeu actif ou autre opération exclusive active** — action désactivée avec
   motif concret.

La sonde StarHubFR reste une précondition. Son installation utilise le bundle
existant. Si elle est installée en pause, le parcours peut l’activer pour la
session puis restaurer son état initial.

### 3.2 SLO absent

La page Nexus SLO est l’identifiant **50153**. Cet identifiant et le UniqueID
vivent dans un type de contrat unique, pas dans la vue.

- Si `nexusDirectDownloadUnavailable == false`, « Installer SLO » appelle
  `downloadModFromNexus(nexusId: 50153)`. Progression, annulation, file et feuille
  d’installation restent celles du pipeline Nexus commun.
- Sinon, « Ouvrir la page Nexus » ouvre la page des fichiers construite par le
  helper existant. Un lien `nxm://` revient dans le pipeline StarHubFR.
- L’installation conserve la règle générale : nouveau mod désactivé par défaut.
- Après confirmation de l’installation, le scan des mods fait évoluer la carte.
  Aucun lancement n’est enchaîné automatiquement.
- Archive annulée, invalide ou portant un autre UniqueID : état absent conservé,
  message du pipeline affiché, aucune session diagnostique créée.

### 3.3 Préparation

Une feuille présente avant écriture :

- SLO sera activé s’il est en pause ;
- la sonde sera activée si elle est en pause ;
- les deux clés diagnostiques passeront à `true` pour cette session ;
- le volume du journal et le léger surcoût attendus ;
- la restauration automatique prévue après fermeture du jeu.

Après confirmation seulement, StarHubFR :

1. refuse si le jeu est actif ou si benchmark, bissection, profil ou mouvement de
   mods occupe déjà le parc ;
2. lit `config.json` et conserve ses octets exacts, ou note son absence ;
3. décode un objet JSON — jamais `.allowFragments` — avec tolérance JSON5 déjà
   utilisée par le projet ; un fichier absent devient un objet diagnostique
   minimal pour SLO >= 1.0.0 ;
4. remplace seulement les deux valeurs diagnostiques puis écrit atomiquement ;
5. conserve les octets diagnostiques écrits et leur empreinte ;
6. active SLO et/ou sonde par renommage même-parent si nécessaire ;
7. persiste le plan de récupération avant le premier changement disque ;
8. lance le jeu par `launchGame(honoringCloseAfterLaunch: false)`.

Si une étape échoue, les étapes déjà appliquées sont restaurées. Le jeu ne part
que lorsque plan, configuration et états de mods concordent avec la préparation.

## 4. Transaction et récupération

### 4.1 Instantané persistant

Un fichier sous Application Support/StarHubFR contient : identifiant UUID,
date de préparation, chemin logique du dossier SLO, état initial SLO/sonde,
état initial du fichier (`absent` ou octets), empreinte des octets diagnostiques,
offset ou identité du journal avant lancement et derniers identifiants de session
connus de la sonde. Il ne journalise jamais le contenu de la configuration.

Écriture de l’instantané : fichier temporaire puis remplacement atomique. Un seul
plan existe. Un plan présent rend benchmark, bissection et autre diagnostic
indisponibles jusqu’à restauration ou résolution.

### 4.2 Fin normale

`GameExit.publisher` signale la fermeture. Après son délai d’écriture existant :

1. relire journal et fichiers sonde ;
2. construire puis publier le rapport même si certaines sources manquent ;
3. restaurer `config.json` seulement si son contenu correspond aux octets
   diagnostiques écrits ;
4. restaurer états SLO/sonde seulement s’ils correspondent encore à l’état
   temporaire attendu ;
5. effacer plan uniquement après restauration complète ;
6. rescanner parc et recharger Performances.

Le rapport est dérivé des sources déjà persistantes ; aucun nouveau fichier de
télémétrie contenant leur contenu n’est créé.

### 4.3 Modification concurrente et reprise

Si `config.json` a changé pendant jeu, StarHubFR ne l’écrase pas. Le plan reste
visible en état « configuration modifiée » avec deux actions : ouvrir dossier ou
restaurer explicitement la copie initiale après confirmation. Même règle si un
état de mod ne correspond plus à l’état temporaire attendu.

Au démarrage de StarHubFR ou à son retour au premier plan :

- jeu encore actif : garder plan et afficher « diagnostic en cours » ;
- jeu fermé et état temporaire intact : restaurer automatiquement ;
- état divergent : garder plan et demander résolution ;
- plan illisible : ne rien modifier, afficher erreur récupérable et emplacement.

Une restauration répétée est idempotente. Fichier initialement absent : le
fichier diagnostique est retiré seulement s’il est toujours identique à celui
écrit par StarHubFR.

## 5. Corrélation de session

Le rapport doit porter sur lancement produit par ce plan :

- journal SLO : lire uniquement le `SMAPI-latest.txt` du lancement postérieur à
  la préparation et les lignes après borne enregistrée ;
- sonde : sélectionner nouvelle session d’inventaire postérieure à préparation,
  puis ses lignes `loads.jsonl`, `timings.jsonl` et `mod-costs.jsonl` par même
  identifiant `Session` ;
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

Parser dernière ligne `[OPTIMIZER CONFIG]` de la session. Vérifier : diagnostics
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
cache n’est jamais présenté comme temps économisé sans mesure témoin.

### 6.4 Transitions et jeu

- `[FAST WARP COMPLETE]` : nombre, médiane, minimum, maximum et destinations.
- `[FAST WARP ABORT]`/`EXCLUDED` : nombre et raison, présentés comme repli de
  sécurité lorsque journal le dit.
- Fluidité stable issue des minutes valides de la sonde, séparée des minutes de
  chargement et de transition.
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
4. détails repliables par source ;
5. action « Refaire le diagnostic ».

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

## 9. Erreurs et cas limites

- SLO absent, en pause, groupé, dupliqué ou version incompatible.
- Sonde absente, en pause ou trop ancienne.
- `config.json` absent, illisible, scalaire, commentaires/trailing commas ou
  clés de type invalide.
- Jeu lancé entre affichage feuille et confirmation.
- Échec écriture plan, écriture configuration, activation mod ou lancement.
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
- corrélation stricte session/journal ;
- parsing configuration, caches, préchargement, tuiles, SpaceCore, hotspots,
  warps, avertissements et mémoire ;
- médiane transitions, seuils 90/100 %, valeurs invalides et scopes non additionnés ;
- rapport partiel et limites ;
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
