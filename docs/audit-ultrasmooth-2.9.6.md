# UltraSmooth 2.9.6, Radiance 2.5.1, PureBinarySave 2.0.8 et Modern Config Menu 2.5.2 — décompilés du parc *(2026-11-26)*

Le relevé du 2026-11-26 avait laissé quatre deltas « à décompiler depuis le
parc ». Le parc les porte déjà : UltraSmooth **2.9.6** (en pause),
PureBinarySave **2.0.8**, Modern Config Menu **2.5.2** (actifs) et Radiance
**2.5.1** (en pause). Les quatre DLL ont été décompilées (ilspycmd 10.1.1)
depuis le parc et comparées aux décompilations gardées (UltraSmooth 2.9.2,
PureBinarySave 2.0.6, Modern Config Menu 2.3.4, Radiance 2.4.9). Copies et
sorties brutes dans `~/Outils/analyses/{ultrasmooth-2.9.6,purebinarysave-2.0.8,
modernconfigmenu-2.5.2,radiance-2.5.1}/`. Rien exécuté.

## Catalogue A5-T7 — aucune paire ne bouge

Relevé des cibles nommées (`typeof(...)` + nom de méthode, et noms en chaîne
pour `AccessTools`) : **396 cibles des deux côtés pour UltraSmooth**, **108
pour Radiance**, ensembles **identiques** entre l'ancienne et la nouvelle
version ; nombre d'appels `Patch(` inchangé (225 et 37). Les cibles hors
lecture littérale du catalogue (balayage `Monster.update`, traversée
SpaceCore, itérateur de sauvegarde, setters TMXTile, index de Farm Type
Manager, `MachineGroup.Automate`, sous-classes de `Critter`) sont toutes
encore présentes dans le code.

Ce qui change chez UltraSmooth 2.9.6 ne touche aucune cible commune :

- **conditions Content Patcher** (« plus fidèles aux cas limites ») : la clé
  de cache des requêtes est réécrite (même contenu : requête, lieu, joueur,
  objets visés, clés ignorées) et l'optimiseur des préconditions étendues
  relit désormais son interrupteur `EnableExpandedPreconditionsOptimizer`
  (vrai par défaut) à chaque appel au lieu d'un drapeau figé au démarrage ;
- **préchauffe SpaceCore** déplacée en tâche de fond, au menu de chargement
  seulement (jamais pendant une sauvegarde ni monde chargé) ;
- **fondus** : le multiplicateur de fondu rapide est neutralisé tant qu'un
  menu ou un dialogue est ouvert pendant un fondu entrant ;
- **Clear Monocle** rejoint Clear Glasses et SpriteMaster dans la liste des
  mods devant lesquels le pipeline d'images s'efface.

`us_trace` : aucune ligne de format modifiée — le parseur D2 du 2026-11-18
reste juste.

**Verdict** : les 21 méthodes UltraSmooth × Stardropium, 15 UltraSmooth ×
Radiance et 5 Radiance × Stardropium tiennent ; `PerformanceOverlap.swift`
passe à UltraSmooth **2.9.6** et Radiance **2.5.1**, sans changement de
méthode.

## Radiance 2.5.1 — la ligne d'à-coup pour D2

La 2.5.0 écrit au journal SMAPI une ligne par à-coup, **au niveau TRACE**
(fichier journal seulement, pas la console) :

- **seuil** : 50 ms par défaut, 66,7 ms (quatre images à 60 Hz) sur le
  chemin de l'économiseur d'énergie ;
- **filtres** : rien pendant les 180 premières images après l'arrivée sur
  une carte, rien hors du jeu proprement dit (menus, transitions) ;
- **débit** : une ligne au plus toutes les 10 s ; les à-coups tus entre-temps
  sont comptés et annoncés sur la ligne suivante ;
- **forme** : `Stutter: a <N> ms frame in <lieu> at <H>:<MM>. Radiance <x.x> ms
  (<module> <x.x>, …), the game and other mods <y.y> ms, garbage collection
  gen0 +a gen1 +b gen2 +c, <K> KB allocated (<n> more since the last line).`
  — la parenthèse des modules (trois au plus, ceux ≥ 0,5 ms, du plus lourd
  au plus léger), le segment GC (seulement si une collecte a eu lieu depuis
  le dernier à-coup) et le compteur de lignes tues sont **facultatifs** ;
  l'heure de jeu est écrite sans zéro initial pour l'heure (`6:00`,
  `13:40`). Le lieu est le nom unique de la carte, `?` à défaut.

Pour le parseur D2, quand le chantier rouvrira : reconnaître `Stutter: a `
en tête, lire la durée, le lieu, la part de Radiance et le reste ; tolérer
l'absence de chacun des trois segments facultatifs. La part « the game and
other mods » est une soustraction (durée moins Radiance), pas une mesure.

Le reste du delta 2.5.x : menu F6 refait, aurore, étoiles filantes et pluie
de météores de printemps (commande `radiance_shower`), préréglage
« Low spec » et économiseur de batterie au premier lancement sur téléphone,
fenêtres et particules plus détaillées dans `radiance_report`.

## PureBinarySave 2.0.8 — deux clés, garde X138 intacte

- **`MobileCompatibilityMode`** (2.0.7, faux par défaut ; aussi détecté
  seul sur Android et émulateurs) coupe le préchargement de l'écran titre,
  le balayage des parties au démarrage et les fondus réservés au bureau ;
  le `config.json` du parc la porte déjà ;
- **`NotifyOnXmlMirrorComplete`** (2.0.8, faux par défaut) affiche un
  message HUD quand la copie XML de fond est écrite ; absente du
  `config.json` du parc tant que le jeu n'a pas tourné en 2.0.8 (SMAPI
  l'ajoutera au prochain lancement).

La garde `.bin.sync` et le chemin AutoHeal vérifiés le 2026-11-18 ne sont
**pas touchés** par le delta : le scénario X138 reste traité en amont.

### Format des fichiers `.bin`, relevé sur le parc le 2026-11-27

Lecture seule, partie `TEST_453239247` (fichiers du 2026-11-20 ; la version du
mod qui les a écrits n'est pas connue). Préalable à B6-T2.

- **`<partie>.bin` et `SaveGameInfo.bin`** : en-tête de 28 octets, tous
  les entiers en petit-boutiste :

  | Décalage | Taille | Champ |
  |---|---|---|
  | 0 | 4 | signature `PPBS` (uint32 0x53425050) |
  | 4 | 2 | version du format (uint16), 1 ; refusé au-delà |
  | 6 | 2 | drapeaux (uint16), 0 partout ; écrit à 0 par la 2.0.8 |
  | 8 | 4 | taille du XML décompressé (int32) |
  | 12 | 4 | taille du flux Brotli (int32) |
  | 16 | 4 | Adler-32 du XML décompressé (uint32) |
  | 20 | 8 | date d'écriture, ticks .NET UTC (int64, centaines de ns depuis l'an 1) |

  Le reste est du Brotli : décompressé, il est identique octet pour octet au
  XML voisin (`cmp`), marque d'octets comprise. Vérifié le 2026-11-27 sur les
  deux fichiers de la partie : l'Adler-32 de l'en-tête égale celui du XML
  voisin, la date tombe à moins d'1 ms de la date de modification du `.bin`.
  À la lecture, le mod refuse le fichier si la signature, la version, la
  taille décompressée ou l'Adler-32 ne concordent pas, puis essaie le
  `.bin.bak` (partie plus ancienne).
- **`<fichier>.bin.sync`** : 16 octets — date de modification du XML voisin
  (ticks .NET UTC, int64), puis sa taille (int64). Les deux à zéro marquent
  un XML encore à écrire (copie XML différée). Fichier écrit par
  renommage d'un `.sync.tmp`.
- **Garde au chargement** (hors mode « disque pur ») : si la date du XML
  s'écarte de plus de 2 s de celle du `.bin.sync`, ou si sa taille diffère,
  et que le XML est bien formé, le mod efface le `.bin`, son `.bin.sync` et
  les caches `*.assets.bin` / `*.maps.bin`, puis charge le XML et refait le
  binaire. Un XML absent, de moins de 500 octets ou mal formé est au
  contraire **reconstruit depuis le `.bin`** (AutoHeal) : une édition ratée
  du XML est alors écrasée par l'ancienne partie.
- **`<partie>.official_fr.assets.bin`** (en-tête `CABP`) et
  **`<partie>.official_fr.maps.bin`** (`CMBP`) : caches de contenu traduit, pas
  la partie. À conserver dans un backup ou une restauration, jamais à éditer.

Conséquence pour B6-T2 : une partie dont le XML est complet s'édite par le
XML seul, la garde fait le reste. Le `.bin` n'est à écrire que si le XML
manque ou n'est qu'un bouchon (mode « disque pur », copie XML différée) :
en-tête ci-dessus avec un Adler-32 et une date neufs, Brotli du XML, puis un
`.bin.sync` à la date et à la taille du XML écrit. Lu dans la 2.0.8
(`~/Outils/analyses/purebinarysave-2.0.8/`, lecture statique) ; à
revérifier à chaque version du mod.

## Modern Config Menu 2.5.2 — traduction française en retard

API publique (`ModConfigMenuApi`) inchangée : la lecture des menus par la
sonde n'est pas concernée. Une seule clé de configuration nouvelle,
`VirtualKeyboardSize` (moyen par défaut), pour le clavier virtuel de
rebind ; deux fenêtres neuves (clavier virtuel de rebind, rendu des surfaces).

**Constat pour le parc** : `i18n/default.json` porte **223 clés**, le
`fr.json` posé le 2026-09-18 en porte **180** — **43 manquent** (clavier
virtuel, navigation tactile, moteur de défilement, plein écran, décalage du
bouton titre, police vanilla). Même retard chez **UltraSmooth 2.9.6** :
**351 clés `config.*`** (le corpus de l'éditeur en comptait 115 à la 2.1.3)
contre **230** dans son `fr.json`, soit **127 manquantes**. Le hub de
traduction de l'app doit les montrer comme traductions incomplètes ; c'est à
vérifier à l'écran, pas un défaut supposé.
