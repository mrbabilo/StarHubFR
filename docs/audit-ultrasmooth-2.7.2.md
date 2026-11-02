# UltraSmooth 2.7.2 et PureBinarySave 1.0.7 (2026-11-02)

**Conseil : laisser PureBinarySave en pause sur ce parc.** Sans SpaceCore, il
n'a pas réécrit son `.bin` au coucher : chaque chargement ramène la partie au jour de sa
migration, et sa commande de retrait écrase le XML à jour par cet état ancien.
Avec ou sans SpaceCore, tant qu'un `.bin`
existe dans le dossier d'une partie, le jeu le charge à la place du XML. Or
StarHubFR lit et modifie le XML. Une partie modifiée dans l'app pendant que le
mod est actif perd ces modifications au chargement suivant, sans un mot (X138).

**UltraSmooth peut repartir, mais la sonde ne mesure plus juste le changement
d'heure quand il est actif** : son étalement des gestionnaires `TimeChanged`
contourne le point d'accroche de la sonde (X139). Les conseils des audits
précédents tiennent : `EnableSpaceCorePrewarm` reste à `false` (c'est le cas sur
le parc), et `EnableLocationSpatialIndexEngine` est à couper.

Le catalogue des recouvrements (A5-T7) a été remesuré : deux méthodes
d'éclairage rejoignent la paire Radiance × UltraSmooth, une la paire Radiance ×
Stardropium. PureBinarySave n'entre dans aucune paire.

## Périmètre et preuves

Décompilation ILSpy (`ilspycmd`, dossiers d'analyse hors dépôt, rien exécuté)
des DLL du parc, toutes en pause sauf Speedy Solutions :

| Binaire | Origine | SHA-256 |
|---|---|---|
| PureBinarySave 1.0.7 | `Mods/.PureBinarySave` | `ecbb9340528f538353a1f3a690a78231815a735d21f0581f8dffef71cf9015aa` |
| PureBinarySave 1.0.6 | sauvegarde d'installation du 2026-11-01 | — (comparaison seulement) |
| UltraSmooth 2.7.2 | `Mods/.UltraSmooth` | `32fe632427edecccb77fd8e34152998c8fef0285ced6a97587642716ca0eb7c3` |
| UltraSmooth 2.7.0 | sauvegarde d'installation du 2026-11-01 | — (comparaison seulement) |
| Radiance 2.4.5, Stardropium 0.3.0, StardewOptimizer 3.0.3, Loading Optimizer 1.0.0, Speedy Solutions 1.1.0 | parc | pour le catalogue |

**La 2.6.2 du dernier audit n'est plus nulle part.** Ce qu'UltraSmooth a changé
entre 2.6.2 et 2.7.0 est donc lu dans son état final, pas en diff ; le diff
2.7.0 → 2.7.2 n'ajoute que sept cibles d'interface (menus de configuration,
cadran de l'argent, notifications, tutoriel, curseur à la manette).

Le relevé des cibles Harmony a été fait par un script de lecture des appels
(`typeof`, types tenus dans une variable, `TypeByName`, machines à états trouvées
par leur nom), puis chaque méthode commune a été relue à son site
`harmony.Patch`, avec sa garde et sa valeur par défaut des deux côtés. Les
balayages dynamiques (personnages, critters, monstres) ont été relus à la main.

## PureBinarySave 1.0.7

### Ce que le mod écrit dans le dossier d'une partie

- `<partie>.bin` : le XML que le sérialiseur du jeu produit, **compressé en
  Brotli** derrière un en-tête de 28 octets avec une somme de contrôle. Ce n'est
  pas un autre format de données, c'est la même partie compressée. (Le relevé des
  sources du même jour parlait de MessagePack : MessagePack sert au cache
  d'assets, pas à la partie.)
- `SaveGameInfo.bin`, le résumé du fermier pour le menu de chargement.
- `<partie>.bin.bak` (copie gardée par le remplacement atomique), `.bin.tmp`
  pendant l'écriture.
- `<partie>.<langue>.assets.bin` : un instantané des données de jeu déjà
  modifiées par Content Patcher, pour accélérer le chargement suivant.
- `<partie>.cpcache.bin` si le cache Content Patcher est allumé (éteint par
  défaut).

L'écriture du `.bin` est atomique (fichier temporaire, somme de contrôle, puis
remplacement). Aucun réseau, aucun processus, aucun chargement de code.

### Au coucher, le XML devient un talon

Avec la recopie différée, active par défaut et sur le parc, le fichier XML
principal ne reçoit **pas** la partie au coucher : il reçoit un talon de deux
lignes (un commentaire et un élément racine `PureBinarySave`). La partie part dans
le `.bin`. Le `SaveGameInfo` XML, lui, est écrit normalement.

Le vrai XML est recopié depuis le `.bin` au début de la journée suivante, après
6 secondes, en tâche de fond. La recopie attend tant qu'UltraSmooth signale une
forte charge, et elle est forcée au retour à l'écran titre et à la sortie normale
du jeu. **Un arrêt brutal entre le coucher et la recopie laisse le talon sur le
disque** ; le mod le répare au lancement suivant, s'il est toujours actif.

### Au chargement, le `.bin` passe toujours d'abord

Si `<partie>.bin` existe, le jeu le charge. Aucune date n'est comparée avec le XML.
Le XML ne sert qu'en repli : pas de `.bin`, `.bin` illisible, ou mode de
comparaison XML activé.

Au lancement, le mod reconstruit le XML depuis le `.bin` quand le XML manque,
pèse moins de 500 octets, n'a pas `SaveGame` pour racine, est illisible, ou est
plus ancien que le `.bin` de plus de 3 secondes. Un XML **plus récent** que le
`.bin` n'est jamais regardé.

### Sans SpaceCore, le `.bin` n'est jamais réécrit : la partie revient au jour de la migration

Signalé le 2026-11-02 (« recharge toujours la sauvegarde du jour 1 sur Mac »),
reconstitué à partir des relevés de la sonde et du code, sans rien lancer.

**Ce que montrent les relevés du 1er novembre.** Six sessions avec
PureBinarySave actif, de 20:32 à 21:04, toutes sur un profil réduit **sans
SpaceCore** (25 à 35 mods ; SpaceCore ne réapparaît que le 2 novembre). Les
chargements de `TEST_453239247` donnent trois fois « spring 1 Y1 » alors que le
XML grossit entre deux chargements (5 876 113 puis 6 296 423 octets) ; ceux de
`BENCH_450485299` restent sur « spring 4 Y1 » malgré deux couchers. Sur ces
sessions, la sonde compte cinq sauvegardes et n'enregistre **aucun** passage dans
les deux préfixes qui écrivent le `.bin` au coucher. C'est un indice fort, pas une
preuve : la sonde ne compte pas une méthode de patch que le JIT a intégrée à
l'appelant (c'est pourquoi `Prefix_reloadMap` manque alors que `Postfix_reloadMap`
est compté). Mais ces deux préfixes contiennent un bloc `try/catch`, que le JIT
n'intègre pas. **Ce qui est établi**, c'est que le `.bin` n'a pas été réécrit au
coucher : les chargements restent au jour de la migration alors que le XML
avance.

**Le mécanisme, vu dans le code.**

1. Au premier chargement d'une partie sans `.bin`, le mod la « migre » : il
   copie le XML tel quel dans un `.bin` (l'historique d'erreurs de l'app garde
   les deux messages de succès, pour `TEST_453239247` et `BENCH_450485299`).
2. Au coucher, le `.bin` n'est réécrit que par l'un de deux préfixes : celui posé
   sur le proxy de sérialisation de SpaceCore, si SpaceCore est là ; sinon celui
   posé sur `SaveSerializer.Serialize` du jeu. Or cette méthode est
   **générique** (`Serialize<T>`) : le mod patche son instanciation pour
   `SaveGame`. Pourquoi ce préfixe ne réécrit rien n'est pas établi. Trois causes
   restent possibles : le patch n'a pas été posé, une exception a été avalée par
   le `catch` qui l'entoure, ou il est posé mais jamais appelé. La plus probable
   est la dernière, une déduction : pour un type référence, le CLR exécute un code
   partagé entre toutes les instanciations, que le détour posé sur
   l'instanciation ne voit pas.
3. Le jeu écrit donc un XML vanilla complet à chaque coucher, et le `.bin` reste
   celui de la migration.
4. Au chargement suivant, le `.bin` existe : il est lu, sans comparaison de date.
   La réparation automatique ne regarde que le cas inverse (`.bin` plus récent).
   La partie revient au jour de la migration — jour 1 pour une ferme neuve.
5. **La commande de retrait aggrave la perte.** Elle reconstruit le XML depuis
   le `.bin` avant de supprimer les `.bin` : elle écrase le XML à jour par l'état
   de la migration. Le relevé le montre : à 21:14, mod retiré, `TEST_453239247`
   se recharge encore en « spring 1 Y1 ».

**Condition observée : sans SpaceCore, sur Mac Apple Silicon.** Le rôle du Mac
n'est pas testé. Aucune branche du mod ne dépend de la plateforme, mais le
détour des méthodes par Harmony diffère selon le processeur. Avec SpaceCore, le
préfixe passe par un proxy non générique ; ce chemin n'a pas été observé, faute
de session réunissant les deux mods. **Installer SpaceCore n'est donc pas un
remède vérifié.**

### Ce que cela fait à StarHubFR

Vérifié dans les deux codes, rien exécuté :

- **Les modifications de l'app sont perdues (X138).** L'éditeur de partie
  (`updateSave` : argent, noms, santé, énergie, monnaies, conjoint), l'éditeur
  d'inventaire, le retrait des mods absents et le renommage d'une copie écrivent
  dans le XML. Avec un `.bin` présent, le chargement suivant les ignore, puis la
  sauvegarde suivante les écrase. L'utilisateur ne voit aucune erreur.
- **Le cas le plus grave ne passe pas par l'app.** Mettre PureBinarySave en
  pause, jouer quelques jours en vanilla, puis le réactiver : le `.bin` périmé
  est chargé à la place du XML à jour. Les journées jouées entre-temps
  disparaissent. StarHubFR met les mods en pause : c'est par lui que ce chemin
  s'ouvre le plus souvent.
- **Copie et benchmark.** `cloneSaveFolder` (copie d'une partie, branche depuis
  une sauvegarde, copie de benchmark) renomme le XML mais pas le `.bin`. La copie
  se charge donc depuis son XML, ce qui est juste, sauf si la copie a été faite
  pendant la fenêtre du talon. Le benchmark mesure alors le chargement XML, pas
  celui du `.bin`.
- **Lecture.** Pendant la fenêtre du talon, tout ce qui lit le XML principal
  voit un document presque vide : la page Parties (`parseSaveFile` lit ce
  fichier, pas `SaveGameInfo`) affiche un fermier « Unknown » sans argent ni
  date, et l'empreinte de la partie (`SaveFingerprint`) ne trouve aucun mod.
- **Corrigé en partie le 2026-11-02 (X138).** Après une écriture complète de
  l'app, les `.bin` de la partie partent à la Corbeille et le mod les recrée
  depuis le XML. Les éditeurs et la copie refusent une partie dont le XML n'est
  qu'un talon ou est plus ancien que le `.bin` de plus de 3 s. Une alerte
  critique signale PureBinarySave actif sans SpaceCore actif. Reste ouvert : la
  réactivation après des jours sans le mod, et la lecture pendant la fenêtre du
  talon.
- **Sauvegardes et restaurations : saines.** Elles copient le dossier entier,
  `.bin` compris, et une restauration remplace tout le dossier.
- **Poids.** Le cache d'assets vit dans le dossier de la partie : il entre dans
  chaque sauvegarde de partie faite par l'app. Sa taille n'a pas été mesurée,
  aucune partie du parc n'en a encore.

### Le compactage

Actif par défaut, avant chaque sauvegarde : il retire les chaînes vides des
listes de courrier, d'évènements vus, de réponses de dialogue et de musiques
entendues, les commandes spéciales nulles et les débris qui n'ont plus de
morceaux. Rien d'autre. Bénin.

### 1.0.6 → 1.0.7

Le cache d'assets est refait (la moitié du diff), le chargement paresseux des
feuilles de tuiles revient, et la recopie XML **réinsère enfin les données
SpaceCore** qu'elle perdait : jusqu'à la 1.0.6, le XML recopié n'était pas
fidèle au `.bin` pour les mods qui passent par SpaceCore.

## UltraSmooth 2.7.2

### Le changement d'heure contourne SMAPI (X139)

`EnableTimeChangedPacing` (actif par défaut ; actif sur le parc, budget de 1 ms)
pose un préfixe sur la levée générique des évènements de SMAPI. Pour
`TimeChanged`, il appelle lui-même chaque gestionnaire des mods, le chronomètre,
et met en file ceux qui dépassent le budget ou qu'il a déjà jugés lourds. La file
se vide pendant sa propre mise à jour par image. Le corps d'origine de SMAPI ne
tourne plus pour cet évènement.

La sonde StarHubFR transpile précisément ce corps (`ModCosts`, accroche
`ManagedEvent<T>.Raise`). Avec UltraSmooth actif, elle ne voit donc plus le coût
`TimeChanged` d'aucun mod, et le travail différé tombe dans le temps de la mise à
jour d'UltraSmooth : **UltraSmooth paraîtra payer ce que les autres mods
coûtent toutes les dix minutes de jeu**. C'est une déduction tirée des deux
codes ; aucune mesure ne l'a encore montrée.

Le module existait déjà en 2.7.0 ; aucun audit précédent ne l'avait relevé.

**Posé le 2026-11-02 (X139)** : la paire sonde × UltraSmooth est une
incompatibilité connue de l'app, qui conseille d'éteindre l'option pendant les
mesures. La déduction reste à confirmer par une capture.

### Le journal SMAPI réécrit (X140)

`EnableSmapiOptimizer` (actif par défaut et sur le parc) remplace l'écriture du
fichier `SMAPI-latest.txt` :

- chaque ligne part dans une file, écrite par un fil en arrière-plan toutes les
  100 ms au plus ; seules les lignes qui contiennent « Fatal » ou « Crash » sont
  écrites tout de suite. Un arrêt brutal peut perdre la fin du journal ;
- **au-delà de cinq lignes identiques consécutives**, les suivantes sont
  remplacées par une ligne de résumé, sans horodatage ni niveau, qui commence
  par `[UltraSmooth SMAPI Optimizer] Suppressed N duplicate log lines:` et cite
  la ligne répétée, coupée à 80 caractères.

Cette ligne commence par un crochet, comme un en-tête SMAPI : `SmapiLogParser`
en faisait une entrée à part, de niveau trace, datée « UltraSmooth » et imputée
à un mod « Optimizer ». Une erreur répétée à chaque image ne comptait donc que
cinq fois par série dans les diagnostics de l'app. **Corrigé (X140)** : le
lecteur reconnaît le résumé et rend à la dernière entrée ses N répétitions,
seulement quand la citation désigne bien cette entrée.

Le même module fait aussi sauter certaines images à la mise à jour des
surveillances de fichiers de SMAPI quand le moteur de cadence est actif.

### Le reste

- **Nettoyage mémoire au coucher** (`EnableSafeWindowCleanup`) : deux GC complets
  forcés, l'un bloquant, avant et après la sauvegarde, puis une demande de
  restitution de mémoire au système (sur Mac, `malloc_zone_pressure_relief`). Ce
  coût tombe dans le fondu du coucher, donc dans ce que la sonde mesure à cet
  instant.
- **Éclairage** : `LightMapOptimizer` patche la lueur des lampes et celle des
  fenêtres même quand Radiance est présent. Il dit lui céder l'éclairage, mais
  ses deux préfixes restent posés, gardés à l'exécution par `EnableLightCulling`.
- **Sauvegarde** : l'agrandissement du tampon (`BatchSerializationOptimizer`) et
  l'index de Farm Type Manager sont toujours là ; la traversée SpaceCore aussi.
- **Surfaces** : toujours un seul fichier écrit (le rapport `us_trace`) et la
  config ; ni réseau, ni processus, ni chargement de code. Des appels système
  Windows et Linux restent derrière leur garde de plateforme.

## Catalogue des recouvrements (A5-T7)

| Paire | Avant | Après | Changement |
|---|---|---|---|
| Stardropium × UltraSmooth | 20 (+1 conditionnelle) | 20 (+1) | toutes encore patchées des deux côtés |
| Radiance × UltraSmooth | 13 | **15** | `LightSource.Draw`, `GameLocation.drawLightGlows` (neuves chez Radiance en 2.4.x) |
| StardewOptimizer × UltraSmooth | 8 (+1) | 8 (+1) | inchangée |
| Radiance × Stardropium | 4 | **5** | `LightSource.Draw` |
| Les paires sans UltraSmooth ni Radiance | — | — | mods inchangés sur le parc |

**PureBinarySave n'entre dans aucune paire** :

- avec Stardropium, une seule méthode commune (`GameLocation.reloadMap`) ; leurs
  deux itérateurs ne sont pas les mêmes (chargement contre sauvegarde) ;
- avec Loading Optimizer, une seule par défaut (`Game1.loadForNewGame`) ; les six
  autres (lecture de la partie, chargement des lieux, invalidation du cache,
  feuilles de tuiles…) sont dans sa sonde de durées, derrière
  `EnableDetailedDiagnostics`, éteint par défaut ;
- avec UltraSmooth, aucune : la traversée SpaceCore qu'UltraSmooth patche,
  PureBinarySave l'appelle sans la patcher. Les deux mods travaillent pourtant sur
  le même chemin d'écriture, par des méthodes différentes, et se parlent par une
  API.

## Limites

- Rien n'a été lancé. Le contournement de la sonde et le comptage des erreurs
  du journal sont déduits du code, pas observés.
- La taille du cache d'assets de PureBinarySave n'est pas connue : aucune partie
  du parc n'en a.
- UltraSmooth 2.6.2 → 2.7.0 n'est pas comparé, faute de DLL.
