# UltraSmooth 2.4.17 et Radiance 2.3.2 — deltas (2026-10-14)

**Conseil : garder UltraSmooth en pause pour les mesures, et désactiver
`EnableLocationSpatialIndexEngine` avant de le réactiver pour jouer.** La 2.4.17
ajoute quatre cibles Harmony, dont un index spatial **actif par défaut** qui
remplace `GameLocation.getObjectAtTile` sans reproduire le contrat du jeu (les
meubles disparaissent de la réponse). Le correctif « double temps des machines »
annoncé par le changelog ne concernait pas ce parc. Radiance 2.3.2 n'ajoute
aucune cible.

## Périmètre et preuves

Comparaison ILSpy des DLL locales : UltraSmooth 2.4.16 (sauvegarde d'installation
`2026-10-13_011645_F4AFC9AC-…`) contre 2.4.17 installée dans `Mods/.UltraSmooth` ;
Radiance 2.3.1 (`2026-10-11_123141_A29338D3-…`) contre 2.3.2 dans
`Mods/.SDV-Radiance`. Code du jeu relu dans `Stardew Valley.dll` du parc
(`GameLocation.getObjectAt`, `CraftingRecipe.ItemMatchesForCrafting`). Changelogs
Nexus lus par `check_sources.py --fetch-changelogs` ; le code décompilé prime.

| Binaire | SHA-256 |
|---|---|
| UltraSmooth 2.4.16 | `2f6f30e0650dfaf27e5445152914b1b72a78b3d3506c8d80f292bcba09b96682` |
| UltraSmooth 2.4.17 | `e6d8043c90f665fa144538e1ad0fa2a95567be45eaa6f2a468b6c86453ae0f36` |
| Radiance 2.3.1 | `0e6ac911df98c7bb626d21f73c804ff4cf1706b0a66a44d568c03b4a87344517` |
| Radiance 2.3.2 | `1b8a5c67a9f1c94032ff20607b2dccbf53ba26445ddcae5fdbe0db4309ddc765` |

Audit statique ciblé : aucun lancement de jeu, aucune sauvegarde ni configuration
modifiée.

## UltraSmooth 2.4.17

UltraSmooth passe de 33 866 à 35 661 lignes décompilées : 11 fichiers changés, 2
nouveaux (`LocationSpatialIndexEngine`, `IUltraSmoothApi`). Cibles Harmony : 127
avant, 131 après. Les quatre nouvelles :

| Cible | Module | Défaut | Effet |
|---|---|---|---|
| `GameLocation.getObjectAtTile` | `LocationSpatialIndexEngine` (préfixe) | **actif** | réponse servie par un index, code du jeu sauté |
| `Object.performObjectDropInAction` | `ItemQueryBitmaskEngine` (préfixe) | suit `EnableItemQueryBitmaskEngine` | refus rapide **en mode sonde seulement** (`probe: true`) |
| `CraftingRecipe.ItemMatchesForCrafting` | `ItemQueryBitmaskEngine` (préfixe) | suit `EnableItemQueryBitmaskEngine` | correspondance d'ingrédient réécrite |
| `LetterViewerMenu.receiveLeftClick` | (correctif clic du calendrier) | — | changelog : pages de lettre tournées par erreur |

Aucune ne recoupe Stardropium 0.2.9 ni StardewOptimizer 3.0.3 :
`getObjectAtTile` n'apparaît dans aucune autre DLL décompilée. Le catalogue des
recouvrements n'a pas à bouger.

### 🟡 L'index spatial répond autrement que le jeu

`GameLocation.getObjectAt` (code du jeu) regarde **d'abord les meubles** (boîte
englobante), puis `objects` à la case, et respecte `ignorePassables` des deux
côtés. L'index d'UltraSmooth ne contient que `location.Objects`. Le préfixe :

- sur une case indexée, rend l'objet, même si un meuble la couvre ou s'il est
  franchissable avec `ignorePassables: true` ;
- sur une case non indexée, rend **`null` dès que la location a au moins un
  objet**, au lieu du meuble qui s'y trouve ;
- ne voit un objet posé qu'au `ObjectListChanged` de SMAPI, émis une fois par
  tick : un mod qui pose un objet puis l'interroge dans le même tick reçoit `null`.

L'écart est démontré par lecture des deux codes, pas observé en jeu. Il touche
tout appelant de `getObjectAtTile` à l'intérieur (maison, cabanes, intérieurs de
SVE) : mods de rangement, d'automatisation, de placement. Le module est actif par
défaut, et absent du `config.json` du parc, écrit par la 2.4.16 : SMAPI applique
donc la valeur par défaut `true`.

### Correctif « double temps des machines » : sans effet ici

`MachineDeadlinePatches` retranchait les minutes deux fois : le jeu décrémentait
`minutesUntilReady`, puis l'ombre du module retranchait encore et réécrivait la
valeur. La 2.4.17 recale l'échéance sur la valeur du jeu. Ce code vit sous
`EnableExperimentalFeatures` et `EnableMachineTimingWheel`, tous deux à `false`
par défaut et dans le `config.json` du parc : aucune sauvegarde du parc n'a pu
être touchée.

### Pistes écartées, avec la mesure

- **Ingrédients d'artisanat (`ItemMatchesForCrafting_Prefix`).** Le préfixe
  accepte `item.ItemId == item_id` sans regarder le type, et compare sans tenir
  compte de la casse. Le jeu compare l'id qualifié résolu par
  `ItemRegistry.GetDataOrErrorItem`. Un objet d'un autre type qui partagerait
  l'`ItemId` d'un ingrédient compterait (et serait consommé). Non classé : aucune
  paire réelle en collision n'est relevée. Pour conclure, chercher dans
  `Data/Furniture` et `Data/BigCraftables` un id numérique égal à un ingrédient
  de recette.
- **Refus rapide de dépôt dans une machine.** Il ne joue qu'en `probe: true` :
  le dépôt réel (`probe: false`) passe par le code du jeu. Un index périmé après
  une édition conditionnelle de `Data/Machines` ne fausserait que les surbrillances
  et les sondes d'autres mods, jamais la consommation. Non démontré.

## Radiance 2.3.2

Radiance gagne 228 lignes : 4 fichiers changés, aucune cible Harmony ajoutée ni
retirée. Le seul changement de logique visible dans `HarmonyPatcher` retire la
garde `AnotherModOwnsWeatherDraw` du dessin de la pluie. C'est le correctif
Fluttery Flakes du changelog : la pluie de Radiance revient, la neige reste à
Fluttery Flakes. Les autres correctifs (eau sur Android, glace des rivières,
lave des mines) touchent le rendu et les tables de cases, sans recouvrement.
