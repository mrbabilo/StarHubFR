# UltraSmooth 2.8.4 (2026-11-11)

Delta depuis l'[audit 2.7.2](audit-ultrasmooth-2.7.2.md) et le relevé 2.7.6
(journal lu de 2.7.9 à 2.8.4). **UltraSmooth 2.8.4 et PureBinarySave 1.0.10 sont
actifs sur le parc** ; Stardropium 0.3.0 et Radiance 2.4.7 sont en pause.

**Une paire du catalogue change.** Avec Stardropium, `GameLocation.timeUpdate`
n'est plus une méthode conditionnelle : jusqu'en 2.7.6, UltraSmooth ne la
patchait que derrière `EnableExperimentalFeatures`. En 2.8.4, son
`ClockTickOptimizer`, posé sans autre garde qu'`EnableMod`, y ajoute un préfixe.
Ce préfixe saute entièrement les lieux sans animaux ni bâtiments, et diffère les
autres quand l'étalement est actif. Stardropium y pose le sien par défaut
(`EnableTenMinuteOptimization`). Deux règles d'omission s'appliquent donc au même
passage de 10 minutes, comme pour `passTimeForObjects`. La paire passe de 20 à
**21 méthodes partagées** et n'a plus de méthode conditionnelle.

**Un recouvrement neuf, hors catalogue : `GameContentHelper.InvalidateCache`.**
Le module d'optimisation de Content Patcher d'UltraSmooth (`EnableContentPatcherOptimizer`,
vrai par défaut) pose un préfixe sur la méthode de SMAPI qui invalide des assets
par prédicat. PureBinarySave en pose un sur la même méthode
(`EnableCpBatching`, vrai par défaut, relu dans la 1.0.10 du parc), et Loading
Optimizer aussi, mais seulement avec `EnableDetailedDiagnostics`, faux par
défaut. Aucun de ces préfixes n'annule l'appel : chacun **réécrit le prédicat**.
UltraSmooth, pendant le passage d'heure de Content Patcher seulement, ne laisse
invalider que les assets de la vue courante ; PureBinarySave saute ce que son
regroupeur juge redondant une fois son instantané d'assets restauré. Les deux
filtres se composent : un asset n'est invalidé que si les deux l'acceptent. Rien
ne plante, mais un asset qui devait changer à l'heure peut garder son ancienne
version. C'est **une** méthode commune entre UltraSmooth et PureBinarySave
(aucune en 2.7.6) : sous le seuil du catalogue, PureBinarySave reste hors des
paires. À regarder si des textures ou des cartes « oublient » de changer en
cours de journée avec les deux mods actifs.

**Les erreurs rattrapées par UltraSmooth sortent du journal visible.** Le
« rate-limited error logging » annoncé en 2.8.0 est
`UltraSmoothLogger.ErrorOnce` : 44 appels en 2.8.4, aucun en 2.7.6. Il écrit
**une fois par clé et par session** (la mémoire n'est jamais vidée), au niveau
**TRACE**, sous la forme `<clé> failed (logged once): <type>: <message>`. Une
exception qu'UltraSmooth rattrape sur ces sites n'est donc plus une ligne ERROR :
les Alertes, l'historique d'erreurs par mod et `topErrorMods` ne la voient plus,
et `LogBudget` sacrifie le TRACE en premier quand le journal dépasse son
plafond. Une baisse du compte d'erreurs d'UltraSmooth sur le parc ne prouve donc
pas qu'il va mieux. Une partie de ces sites sont neufs (le durcissement de
« 35 points » de la 2.8.0) : sans eux, l'exception aurait remonté jusqu'à
Harmony ou SMAPI. Recherche à faire si l'on veut que l'app lise ces lignes :
filtrer `failed (logged once)` dans le TRACE d'UltraSmooth.

**Les conseils de l'audit 2.7.2 tiennent.** `EnableSpaceCorePrewarm` n'a pas
d'initialisateur et reste à `false` ; `EnableLocationSpatialIndexEngine` est à
`true` par défaut depuis au moins 2.7.6, le conseil de le couper tient.
**Nouveau : `EnableLocationTimeSlicing` passe à `true` par défaut** (il existait
en 2.7.6, sans initialisateur, donc éteint). C'est le moteur
qui étale sur plusieurs images la mise à jour des lieux hors écran (le « pic de
6h10 » du journal 2.7.9) : `ClockTickOptimizer` diffère `timeUpdate` et
`performTenMinuteUpdate` des lieux hors vue, et UltraSmooth patche désormais
`Game1.UpdateGameClock` et `Game1.Update`. *Déduit, non mesuré* : la sonde, qui
attribue déjà au compte d'UltraSmooth les gestionnaires `TimeChanged` qu'il
déclenche (X139), verra aussi le coût des lieux glisser hors du passage de
l'heure, vers les images suivantes. Une mesure guidée avec UltraSmooth actif
décrit UltraSmooth plus que le parc.

**Le parseur des résumés reste bon (X140).** Le littéral `Suppressed N
duplicate log lines` (citation tronquée à 80) est identique en 2.8.4.

## Cibles Harmony neuves et retirées

- Horloge et boucle : `Game1.UpdateGameClock`, `Game1.Update`.
- Co-op : `Multiplayer.UpdateEarly`, `Multiplayer.UpdateLate`,
  `Farmer.UpdateIfOtherPlayer`.
- Content Patcher : le module, déjà présent en 2.7.6 (`OnAssetRequested`,
  `GetContexts`), s'étend à `PatchManager.UpdateContext`,
  `ScreenManager.OnTimeChanged`, `EditImagePatch.LoadSourceImage` (types
  internes résolus par leur nom) et, chez SMAPI, à
  `GameContentHelper.InvalidateCache` (ci-dessus).
- Jeu : `GameLocation.timeUpdate` passe dans `ClockTickOptimizer` (ci-dessus).
- Retirée : `Game1.didPlayerJustRightClick` (le correctif d'entrée de la 2.7.6).
  `FlyingCompanion.Update` reste patchée, par `DeclaredMethod`.

Aucun des cinq autres mods du catalogue, ni PureBinarySave, ne patche les cibles
d'horloge, de co-op ou internes à Content Patcher.

## Le catalogue des recouvrements (A5-T7)

Les 43 méthodes que le catalogue attribue à UltraSmooth dans ses trois paires
(Stardropium, Radiance, StardewOptimizer) ont été recherchées une à une dans les
deux versions, typées par `typeof` comme par `TypeByName`, balayages dynamiques
compris : toutes sont encore patchées en 2.8.4. Le seul changement est
`timeUpdate` (ci-dessus). Radiance 2.4.7, re-décompilée pour l'occasion, a les
mêmes cibles que la 2.4.5 : ses correctifs 2.4.6/2.4.7 vivent dans ses shaders.

| Paire | 2.7.6 (partagées + conditionnelles) | 2.8.4 |
|---|---|---|
| Stardropium × UltraSmooth | 20 + 1 (`timeUpdate`) | **21 + 0** |
| Radiance × UltraSmooth | 15 | 15 |
| StardewOptimizer × UltraSmooth | 8 + 1 | 8 + 1 |
| PureBinarySave × UltraSmooth (hors catalogue) | 0 | 1 (`InvalidateCache`) |

`PerformanceOverlap.swift` suit : `timeUpdate` rejoint les méthodes partagées,
`measuredVersion` passe à 2.8.4 (UltraSmooth) et 2.4.7 (Radiance).

## Périmètre et preuves

Décompilation ILSpy (`ilspycmd` 10.1.1, dossiers d'analyse hors dépôt, rien
exécuté) des DLL du parc :

| Binaire | Origine | SHA-256 |
|---|---|---|
| UltraSmooth 2.8.4 | `Mods/UltraSmooth` (actif) | `b074abd0d4c78f1b3769117514e44e7200f8ff8c3290e62f37626f8cb8394fa1` |
| PureBinarySave 1.0.10 | `Mods/PureBinarySave` (actif) | `4742c8d9de5e0c1f05c8dbda4f9f31c1a8cb4d497f2ccf26cf236710ef97ba2a` |
| Radiance 2.4.7 | `Mods/.SDV-Radiance` (en pause) | dossier `radiance-2.4.7` |
| UltraSmooth 2.7.6 | analyse du 2026-11-05 | comparaison |
| Stardropium 0.3.0, StardewOptimizer 3.0.3, Speedy Solutions 1.1.0, Loading Optimizer 1.0.0 | analyses du disque, mêmes versions que le parc | pour le catalogue |

Méthode : relevé des cibles par motif (`AccessTools.Method`, `GetMethod`,
attributs `HarmonyPatch`), puis recherche nominative de chaque méthode du
catalogue, et lecture des sites neufs avec leur garde et le défaut de leur
option, des deux côtés. Un premier passage par motif seul ne voyait pas les
méthodes typées par `TypeByName` ni les balayages dynamiques, et avait conclu à
tort que le catalogue ne bougeait pas.

## Ce qui reste à faire

- Une partie réelle avec 2.8.4, puis relire le TRACE : combien de lignes
  `failed (logged once)` sur ce parc, et sur quelles clés.
- Décider si l'app doit lire ces lignes TRACE d'UltraSmooth pour ne pas sous-compter
  ses erreurs (Alertes, historique par mod).
