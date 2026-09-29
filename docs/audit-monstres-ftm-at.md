# Audit — les monstres du monde entier, FTM et Alternative Textures *(2026-09-29)*

Découvert en mesurant UltraSmooth ([`audit-ultrasmooth-2.4.0.md`](audit-ultrasmooth-2.4.0.md)) :
`Monster.update` appelé **4,7 à 4,9 millions de fois par minute** (~1 500
monstres par mise à jour) sur la session du 2026-09-29 19:50, où que soit le
joueur (Ferme, Plage, Ville), et **en hausse dans la session** (1,9 M → 4,9 M en
4 minutes ; ~1,2 M les sessions du 26/09).

## 1. Le jeu met à jour les monstres de tous les lieux

`Game1.UpdateLocations` parcourt **tous** les lieux (`Utility.ForEachLocation`)
et appelle `GameLocation.updateEvenIfFarmerIsntHere`, qui appelle
`updateCharacters` : chaque PNJ et chaque monstre de chaque lieu est mis à
jour à chaque tick, joueur présent ou non (décompilé, Stardew 1.6.15).

## 2. Qui les fait naître : Farm Type Manager

15 packs FTM actifs font naître des monstres ; plafond quotidien cumulé
**17 992**, dont **Stardew Valley Expanded 14 542** (246 zones : Highlands
3 889, Crimson Badlands 3 165, Highlands Cavern 1 778, Forbidden Maze 1 115…),
beaucoup sous condition de saison ou de météo. FTM les fait apparaître à des
heures échelonnées (`SpawnTiming`), d'où la hausse dans la journée. Le
`config.json` de FTM sur le parc : **`MonsterLimitPerLocation: 50`** — ~30 lieux
à 50 monstres donnent les ~1 500 mesurés.

## 3. Alternative Textures 8.1.1 : un coût par monstre et par mise à jour

- `MonsterPatch.MonsterPostfix` (constructeur de `Monster`) marque **chaque**
  monstre (`AssignDefaultModData` quand aucune texture n'existe) —
  `UseRandomTexturesWhenPlacingMonster` n'est pas consulté.
- `MonsterPatch.UpdatePostfix` tourne alors sur chaque mise à jour de chaque
  monstre : recherches de chaînes, lectures du `modData` (`NetDictionary`),
  `GetSpecificTextureModel`… puis, sans texture, **`Sprite.loadedTexture =
  string.Empty`**. Or `AnimatedSprite.Texture` appelle `loadTexture()`, qui
  recharge par `contentManager.Load<Texture2D>` dès que `loadedTexture` diffère
  du nom de texture, puis `UpdateSourceRect()` : un rechargement par monstre et
  par mise à jour, compté dans la mise à jour du jeu, pas dans le suffixe.
- Mesuré (patches armés, 5 minutes, Ferme) : le suffixe seul coûte **5,2 ms
  par image** (58 ms/s, 4,69 M appels/min).
- Sur le parc, **un seul pack actif** l'utilise : `[AT] Vanilla Forage Crops
  and Bushes` (cultures et buissons) ; aucun pack de textures de monstres.

À signaler à l'auteur (PeacefulEnd) : ne marquer un monstre que si une
texture existe, et ne pas remettre `loadedTexture` à vide à chaque mise à jour.

## 4. Leviers (réversibles), à mesurer par paire guidée

1. **Mettre Alternative Textures en pause** (et son composant `[AT]` de VFCB) :
   −5,2 ms par image mesurés, plus les rechargements de texture.
2. **FTM `MonsterLimitPerLocation` 50 → 15** : ~1 500 → ~450 monstres mis à
   jour ; moins de monstres dans les zones dangereuses (SVE Highlands…).
3. **UltraSmooth en pause** : voir son audit (56 FPS contre 18).

## 5. Mesuré (paire guidée 20:42 → 21:40, Ferme, deux côtés `stable`)

UltraSmooth en pause des deux côtés ; appliqués entre les deux : Alternative
Textures en pause (A) et FTM `MonsterLimitPerLocation` 50 → 15 (B). Heures de
jeu comparables (7 h 30–13 h contre 8 h–13 h 30).

| | Avant | Après | Écart |
|---|---|---|---|
| Mise à jour (`Update` p50) | 11,0 ms | 9,4 ms | −15 % |
| Dessin (`OuterDraw` p50) | 4,8 ms | 3,9 ms | −19 % |
| Travail par image (update + draw) | 13,9 ms | 12,4 ms | −11 % |
| `Present` | 1,4 ms | 0,6 ms | |
| FPS moyens | 55,9 | 58,0 | plafonné à 60 |
| Tas | ~4 000 Mo | ~3 925 Mo | −75 Mo |

Le jeu étant plafonné par la synchro, le gain est de la **marge** : 2,8 → 4,3 ms
libres par image de 16,7 ms. A et B appliqués ensemble : leur part respective
n'est pas séparée.
