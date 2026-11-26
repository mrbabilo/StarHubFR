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
