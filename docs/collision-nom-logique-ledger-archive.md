# Archive du chantier — collision de nom logique à l'installation

*Copié du ledger SDD le 2026-09-14 à la clôture du chantier (source git-ignorée
`.superpowers/sdd/2026-09-13-collision-nom-logique-installation/progress.md`,
désormais supprimable). Plan :
`docs/superpowers/plans/2026-09-13-collision-nom-logique-installation.md`
(local, gitignoré). Déclencheur : le doublon SotV — deux versions du même mod
sous un même nom logique, installées en silence, une seule carte à l'écran.
Décision de l'auteur : signal + choix dans l'aperçu, jamais d'écrasement
automatique d'un mod d'uniqueId différent.

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-13-collision-nom-logique-installation.md

Spec: pas de spec formelle — demande explicite de l'auteur (2026-09-13) :
« le doublon aurait dû être signalé, ou écraser la 3.1.0 » ; décision tranchée
par AskUserQuestion : **signal + choix dans l'aperçu**, jamais d'écrasement
automatique d'un mod d'uniqueId différent. (lues : plan, spec §L3 pour
contexte, code d'installation et d'aperçu)
Base: b8e5eff9 (main, L1-L3 poussées jusqu'à 52e6b1d0, CI verte)
Héritage rulings : R2 (--update visible), R9 (un seul implémenteur), R10
(jamais d'amend), R11 (subagents de cette session), R12/attribution
`GLM 5.3 <noreply@z.ai>` (forme CLAUDE.md).

## Pre-flight scan — paires de tâches partageant un fichier ou une interface

| Tâches | Ce qui est partagé | Trouvé |
| --- | --- | --- |
| T1 × T2 | `ModZipInstaller.swift` (détection :454 vs installation :1069) + l'interface du conflit | T1 produit, T2 consomme — séquentiel ; même fichier → pas de parallélisme revue/N+1 (Ruling 8 hérité) |
| T1 × InstallPreview | défaut de résolution (2 sites : :353, :394) | les DEUX sites doivent passer à `default(for:)` — en rater un = défaut d'aperçu asymétrique |
| T2 × tests existants | harnais InstallFolderCollisionTests / PreserveUserConfigsTests | patrons à imiter, pas à modifier |

## Pre-flight scan — auto-cohérence de chaque tâche

| Tâche | Vérifié | Trouvé |
| --- | --- | --- |
| T1 | exclusivité des deux conflits | uniqueId identique → `folderExists` seul (l'occupant EST l'existant) ; le nom ne redétecte jamais — par construction |
| T1 | défaut par type | `.folderExists` → overwrite (verbatim), `.nameTakenByOtherMod` → rename (jamais d'écrasement sans choix) |
| T1 | comparaison du nom | case-insensitive (APFS), point de pause décapité des deux côtés |
| T2 | l'occupant comme existing effectif | le chemin :1090-1147 tourne tel quel (backup, purge, key delta, configs) ; :1161 « actif si l'occupant l'était » marche tel quel |
| T2 | occupant introuvable au disque | patron :1123-1125 (.modNotFound toléré) |
| écran | scénario réel Sounds of the Valley | rejoué par l'auteur après fusion |

## Détails hérités du diagnostic (pour le relecteur)

Cas réel : `[CP] Sounds of the Valley` v3.1.0 `Juanpa98ar.SotV` actif +
`.[CP] Sounds of the Valley` v4.0.0 `Juanpa98ar.Source.SotV` pause — même
nom logique, même Nexus 14881, uniqueIds différents. L'installateur n'a vu
que l'uniqueId → nouveau mod → pause silencieuse (:1166).

## Journal d'exécution

BASE T1: b8e5eff9
T1: DONE — commit 3bf56498 (11 fichiers, +264/−21 : finder ModItem, types
  ZipModInfo, détection ModZipInstaller, InstallPreview ×2 sites, L10n
  en/fr + .strings, tests 128 lignes). 5 tests rouges puis verts — 3174/318
  suites ; sabotages ciblés prouvés (casse → test 2 seul ; overwrite pour le
  nouveau type → test 5 seul). Gate EXIT=0, R2 assumé visible (ModZipInstaller
  1463→1501, InstallPreview 691→706, L10n 1680→1683). Détection extraite en
  fonction pure `ModZipInstaller.detectConflicts`. Parité L10n 1464.
  Deux notes assumées : `DetectedMod.existingVersion` reste nil pour le nom
  pris (T2 résoudra via la résolution explicite) ; la ligne « Installée →
  Nouvelle » de ConflictRow s'affiche aussi pour le nouveau type (passe
  écran Task 3 si utile).
Revue dispatchée : paquet review-b8e5eff9..3bf56498.diff (34 Ko) — pureté
  de detectConflicts, exclusion structurelle des deux types, les deux sites
  InstallPreview, la traversée packs du finder vs son voisin, le champ
  existingVersion nil non lu par erreur.
T1: revue — cœur ✅ (5 tests exacts, interface verbatim, exclusion
  structurelle vraie et verrouillée par le t4, L10n vérifiée à l'octet y
  compris NBSP, finder miroir exact de son voisin, existingVersion nil lu
  en if let par le seul lecteur) MAIS qualité **à corriger** :
  **IMPORTANT** — l'armement `.rename` fuit dans la comptabilité post-install
  (`ModInstallView.swift:934-936`) : `renamedIds` exclut ces mods de
  installedFolderPaths → pour une install Nexus, recordNexusModId/
  anchorInstalledMods/reconcileManifestVersion sautés — le mod à peine posé
  peut réapparaître dans Mod Updates. Avant T1 ils portaient nil et étaient
  inclus. Le scénario-cible même du chantier.
  Mineurs deferred : décapitage côté requête non épinglé (une ligne t1) ;
  redondance ConflictRow (passe écran) ; dérive de ligne du rapport.
T1: fix round 1/5 — implémenteur original repris. Exigence : l'abstention
  porte sur « copie de même uniqueId reste en place », pas sur la valeur
  brute `.rename` ; comportement pré-T1 pour les mods du nouveau type
  (inclus dans la comptabilité) ; test rouge d'abord épinnant les deux
  polarités (nom pris .rename source Nexus → comptabilité passée ;
  .folderExists .rename → exclue comme avant) ; commit NEUF.
T1: fix round 1/5 livré — commit 0b99c41f (4 fichiers, +131/−25). Le
  critère d'abstention est « une copie du même UniqueID reste en place »
  (`DetectedMod.existingVersion`, posé par detectConflicts) ; la règle a
  quitté ModInstallView pour `ModZipInstaller.accountingPaths`, statique
  pure et testée ; nom pris par autre mod en `.rename` source Nexus →
  recordNexusModId/ancre/reconcile repassent ; conflit d'identifiant
  renommé et déplacement X63 restent exclus (voisins épinglés). Rouge
  comportemental d'abord (nouveau type : paths → []), voisins verts sur la
  même exécution ; 3177 verts, gate EXIT=0. Cliquet R2 : ModZipInstaller
  1501→1536, ModInstallView 1112→1099 (resserré), visible au diff.
  Mineurs non traités, deferred.
Re-revue scopée dispatchée : paquet review-3bf56498..0b99c41f.diff (15 Ko)
  — le prédicat existingVersion, accountingPaths pure, les 3 consommateurs,
  le chemin banal et le .overwriteWithBackup inchangés, baseline cohérente.
T1: re-revue — **ADDRESSED, fix approuvé, aucune nouvelle casse**. Le
  prédicat est le bon (existingVersion exclusif à la branche .folderExists,
  nil dans les deux autres) ; les trois polarités épinglées par tests purs
  VÉRIFIÉS verts à l'exécution (8/8) ; règle unique en un seul endroit
  (accountingPaths:111), les 3 consommateurs consomment tous le nouvel
  appel, grep renamedIds = zéro occurrence ; fixture « même identifiant »
  fidèle au réel (l'horodatage .rename vit déjà dans finalDestFolderName
  :1222, donc displacedFrom == nil — l'exclusion historique tient par le
  seul prédicat) ; baseline arithmétiquement cohérente.
  ⚠️ Observation hors périmètre reportée à T2 : la résolution `.skip` d'un
  conflit nom-pris n'est pas honorée à l'écriture — la branche skip vit
  derrière `if let existing = existingMod` (:1163-1166) qui est nil pour ce
  type. C'est LE câblage installation-résolution de T2.
T1: complete (commits b8e5eff9..0b99c41f, fix round 1/5 : 1 addressed,
  0 open — review close, 3 minors deferred)
BASE T2: 0b99c41f
T2: DONE_WITH_CONCERNS — commit 92fcb0a9 (3 fichiers, +264/−5 dont 232 de
  tests ; R2 assumé : ModZipInstaller 1536→1563). Les 4 tests rouges puis
  verts, 12/12 suite collision, 2 sabotages rougissent le test 1 (backup
  absente, état actif) ; gate EXIT=0. ⚠️ Le mystère crash résolu : la
  suite complète n'a jamais été 100 % verte à cause de DEUX tests tiers
  temporels (SmapiUpdateClient:97 stub timeout sous charge ;
  DeepLClientTests:473 timing) — non-régression prouvée (DeepL isolé
  échoue sur l'ancêtre chargé, PASSE sur main avec le commit, 0,640 s
  machine calme) ; 3181 tests, 1 seule issue hors périmètre au meilleur
  run. Signal à l'auteur : ces deux tests tiers flasquent sous charge sur
  cette machine.
Revue dispatchée : paquet review-0b99c41f..92fcb0a9.diff (25 Ko) — skip
  honoré ?, overwrite sur l'occupant (backup/removal/configs/actif),
  rename inchangé, accountingPaths intacte, l'argument de non-régression
  des échecs tiers.
T2: revue — conformité ✅, qualité **approuvée**, 0 critique / 0 important /
  4 mineurs. Le relecteur a RELANCÉ lui-même la suite collision sur HEAD :
  12/12 verts. Le rouge authentique (/tmp/t2-red.log) documente le bug
  pré-T2 (skip qui installait quand même, décalé horodaté). Câblage minimal
  et fidèle (+27 nettes, une seule variable effectiveExisting, zéro
  réordonnancement). Les deux échecs tiers lus et exemptés : force-unwrap de
  harnais SmapiUpdateClient (box.value! après timeout 20 s) et seuil
  temporel pur DeepL (200×10 vagues) — aucun lien avec le diff, signature
  d'instabilité (échecs différents sur deux runs du même arbre, contrôle
  calme 0,640 s).
T2: minor (deferred): contradiction interne du BRIEF (Step 3.4 vs Produces
  sur .skip) — défaut du plan ; corriger le brief pour l'archive.
T2: minor (deferred): pas de test dédié occupant-absent-du-disque sur la
  branche nom-pris (partage de branche avec .folderExists qui le couvre) ;
  dix lignes si un jour la branche est retouchée.
T2: minor (deferred): occupant = composant de pack (folderName imbriqué) non
  couvert par test sur le chemin nom-pris — mécanique héritée telle quelle
  de la branche identifiant.
T2: minor (deferred): nit de citation du rapport (+33/−3 vs +27 nettes).
T2: complete (commits 0b99c41f..92fcb0a9, review clean, 4 minors deferred)
Revue finale L3-collision dispatchée : paquet review-b8e5eff9..92fcb0a9.diff
  (3 commits de code) — mission = la somme (flux complet détection →
  résolution → installation), tri des mineurs (T1 : 3 + T2 : 4), l'écran
  due à l'auteur.

## REVUE FINALE COLLISION — 2026-09-14 00:12 — NON PRÊTE (1 Critique + 1 Important, racine unique)

La somme a trouvé ce que les revues locales ne pouvaient pas voir :
**le `.rename` du nom pris délègue sa distinction à `nonCollidingDestination`
— un mécanisme de CHEMIN disque — alors que le contrat « renommer » de
l'app est un nom LOGIQUE distinct.**
- **C1 (Critique)** : sur occupant ACTIF (rejeu SotV propre), le chemin
  pointé `.[CP] SotV` est libre → le nouveau s'y pose → `ModItem.id`
  identique à l'occupant → **un seul rendu à l'écran**, sans log — le
  défaut cible de la branche, reproduit par la résolution PAR DÉFAUT.
- **I1 (Important)** : les tests de comptabilité du fix round T1 façonnent
  à la main `InstalledModPath(displacedFrom: nil)` — forme que le
  producteur réel ne génère que si l'occupant est actif ; pour occupant en
  pause, `accountingPaths` exclut → pas d'ancre → le mod réapparaît dans
  Mod Updates. Et `aDisplacedWriteIsStillExcludedFromAccounting` épingle le
  même scénario comme devant être exclu — les deux tests purs se
  contredisent, l'arbitre étant le champ que le producteur pose. (La règle
  du dépôt : « faire générer la fixture par le producteur ».)

Le reste de la somme est vérifié et bon : overwrite correct sur les deux
états d'occupant (octets de l'occupant en backup, configs, actif préservé),
skip honoré partout, exclusion structurelle par construction, couture
aperçu→installation dégrade toujours en sécurité (existingMods relu,
résolution nil ne peut jamais armer un écrasement), double-install
cohérente, composant de pack sain.

**Fix wave dispatchée** (fix subagent unique, findings complets) :
- C1 : le `.rename` du nom pris pose `finalDestFolderName =
  folderName_timestamp` — symétrique de la branche `.folderExists`
  (:1248-1249) — un nom LOGIQUE distinct au lieu d'un chemin disque ;
  conséquences attendues : les deux rendus à l'écran, comptabilité passée
  sur les deux variantes d'occupant.
- I1 : les tests de comptabilité ré-ancrés par le **`install()` réel**
  (harnais InstallerTestEnv), plus de fixture façonnée à la main ; le test
  T2 `renameResolutionKeepsBothAliveUnderDistinctNames` mis à jour (il
  affirmait le décalage nonCollidingDestination).
- Rouge d'abord (reproducteur C1 : nom logique posé identique à l'occupant
  → rouge), sabotage, gate + suite complète (les 2 tiers flasquants hors
  périmètre, relance isolée si besoin), commit NEUF.
Tri des mineurs confirmé : rien « avant diffusion » hors ce fix ; « tranche
suivante » : décapitage côté requête, doc orphelin est déjà clos, la
redondance ConflictRow pliera dans la reprise du flux ; « jamais » : le
reste.

## FIX WAVE REVUE FINALE — livrée — 2026-09-14 00:37

Commit `5d188257` (3 fichiers, +252/−71, baseline 1563→1583 visible, GLM
5.3 signé). Rouge d'abord — reproducteur C1 : `newLeaf ==
"[CP] Sounds of the Valley"` = identité de l'occupant — puis vert 14/14
suite collision, gate EXIT=0, **suite complète 3183/318 suites, 0 échec**,
sabotage de l'horodatage rougit le reproducteur exactement.
- Fix C1 : fanion `renamesForNameTaken` dans le bloc nom-pris, la branche
  d'écriture pose `"\(folderName)_\(timestampStamp)"` symétrique de la
  branche d'identifiant ; `nonCollidingDestination` conservé pour
  l'horodaté physiquement pris ; comptabilité `displacedFrom == nil` dans
  les deux états d'occupant.
- Fix I1 : les deux tests de comptabilité ré-ancrés sur le `install()`
  réel (actif compté — déjà vert ; pause comptée — ROUGE pré-fix, le creux
  d'origine prouvé ; X63 exclu via producteur) ;
  `renameResolutionKeepsBothAliveUnderDistinctNames` réépinglé sur le nom
  logique.
Inquiétudes assumées : cas limite même-seconde (horodaté pris → décalage →
exclu, même borne que la branche d'identifiant) ; la ligne de log « dossier
pris » ne se déclenche plus sur rename nominal (annoncé par le nom +
l'aperçu) ; vérification écran SotV à l'humain.
Re-revue scopée dispatchée : paquet review-92fcb0a9..5d188257.diff (32 Ko).
Re-revue fix wave — **C1 et I1 ADDRESSED, fix approuvé, aucune nouvelle
  casse bloquante**. Le fanion est posé dans la bonne branche et sans
  concurrence possible (renamesForNameTaken n'existe que sous
  existingMod == nil, résolutions exclusives) ; les deux rendus prouvés par
  le reproducteur réel (fait affirmé, pas un compte) ; les deux tests de
  comptabilité passent par install() réel, le cas « pause comptée » était
  ROUGE pré-fix (creux d'origine prouvé) ; la fixture pure restante
  (same-unique-id) est légitime (existingVersion est le critère réel) ;
  même-seconde = borne préexistante partagée avec la branche d'identifiant ;
  la ligne X63 muette sur rename nominal est information strictement accrue.
  Suite exécutée par le relecteur sur HEAD : 14/14 vert, arbre intact.

## CLÔTURE CHANTIER COLLISION — 2026-09-14 00:42

Côté code : **complet et approuvé** (3 commits de code + fix wave :
3bf56498, 0b99c41f, 92fcb0a9, 5d188257 — non poussés, push sur demande).
Restent, hors agents :
1. **La vérification à l'écran par l'auteur** (Task 3 du plan) — rejouer le
   scénario SotV : réinstaller l'une des deux versions, l'aperçu propose le
   dialogue du nom pris, chaque résolution produit l'état attendu ; la
   grille/liste ne perd plus la vue d'un mod. C'est LE verdict final.
2. **Le push** sur demande.
3. **L'archive du ledger** dans docs/ + suppression du workspace (patron
   L1-L2), à la demande.

Rulings du chantier (cumul) : héritage R2/R5/R9/R10/R11/R12 ; décision
auteur « signal + choix dans l'aperçu, jamais d'écrasement automatique » ;
défaut par type (rename pour nom pris) ; abstention comptable sur le fait
métier (existingVersion), pas la valeur brute ; rename du nom pris = nom
logique horodaté (pas chemin) ; tests de comptabilité par le producteur
réel ; tri des mineurs par la revue finale (2 « tranche suivante » :
décapitage côté requête, occupant composant de pack ; « jamais » : le
reste).
