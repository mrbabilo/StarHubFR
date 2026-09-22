# Audit — Keybind Radar & SaveSaver *(2026-09-23)*

Deux mods SMAPI parus la veille (2026-09-22), signalés comme sources à suivre,
décompilés et audités pour décider quoi en intégrer. **Aucun code de l'un ou
l'autre ne tourne chez nous ; ce document porte les conclusions.**

| | Keybind Radar | SaveSaver |
|---|---|---|
| **Nexus** | [52710](https://www.nexusmods.com/stardewvalley/mods/52710) | [52709](https://www.nexusmods.com/stardewvalley/mods/52709) |
| **Identité** | `wooa.KeybindRadar` · v1.0.0 · Wooa | `Sky.SaveSaver` · v1 · Sky |
| **Dépendances** | GMCM **optionnel** | aucune (Harmony, Ionic.Zlib embarqués) |
| **UpdateKeys** | `Nexus:52710` | **aucune** — ni SMAPI ni smapi.io ne savent qu'une mise à jour existe |
| **DLL** | 40 Ko, 2 155 lignes décompilées | 42 Ko, 2 584 lignes |
| **Axe recouvert** | C4 (raccourcis & conflits) | sauvegardes & backups |

*Méthode* : DLL prises dans le dossier du jeu (les deux mods y sont **en
pause**, `.KeybindRadar/` et `.SaveSaver/`), décompilées en C# par
`ilspycmd` 10.1.1 — qui exige `DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/10.0.401/libexec`
sinon « You must install .NET » alors que le SDK est bien là (piège d'apphost,
à retenir pour toute décompilation future). Toutes les affirmations ci-dessous
viennent des sources décompilées, pas des pages Nexus.

---

## 1. Keybind Radar — un radar de raccourcis en jeu

### Ce qu'il fait

1. **Scanner** (`KeybindScanner.Scan`, à chaque ouverture du radar) : trouve le
   dossier `Mods/` en remontant depuis son propre dossier, énumère **tous** les
   `manifest.json`, ne garde que les mods **chargés** (`ModRegistry.IsLoaded` —
   les mods en pause sont exclus, donc pas de doublon `X`/`.X`), lit leur
   `config.json` (JSON lenient : commentaires + virgules traînantes), plus les
   touches vanilla de déplacement (lues en live dans `Game1.options`) et sa
   propre touche d'ouverture.
2. **Détection par indice de nom** : une feuille du config est un raccourci si
   le dernier ou avant-dernier segment de son chemin contient `key`, `hotkey`,
   `button`, `shortcut`, `bind`, `control`, `modifier`, `toggle` ou `delete` ;
   les champs `tip/tooltip/description/desc/hint/help` sont exclus, les
   littéraux booléens aussi. Tableaux de chaînes acceptés, split sur « , ».
3. **Libellés par fuzzy-match i18n** : charge l'i18n du mod (default + locale),
   tokenise noms de champs et **clés** i18n, match par Levenshtein ≤ 1 (tokens
   ≥ 4 caractères) avec score type Jaccard ≥ 0,4, et affiche la **valeur** i18n
   (≤ 30 caractères, sans `{{`, sans retour à la ligne). Une approximation de
   notre convention `config.<clé>.name` qui marche aussi sur les mods hors
   convention — au prix de faux positifs possibles.
4. **Conflits** : group by (appareil, combo normalisé) où la normalisation
   coupe sur `+`, trie les parties alphabet case-insensitive et retire les
   espaces ; conflit si > 1 entrées distinctes dans le groupe. **Pas de match
   partiel** : `LeftShift+A` et `A` ne conflit pas (sous-détection assumée).
   Deux actions du même mod sur la même touche comptent comme conflit.
5. **UI en jeu** (`RadarMenu`, IClickableMenu maison) : recherche, filtres
   **All / Conflicts / Unassigned**, bascule **PC / Manette** (split des
   bindings via `Keybind.TryParse` + `TryGetController`), tri par colonne,
   résumé « total / conflits / non-assignés », et par ligne un bouton **Open**
   qui appelle `Gmcm.OpenModMenu(manifest)` — le saut à la page GMCM du mod —
   avec retour automatique au radar et **re-scan** (les modifications sont
   reflétées).
6. **Overlay de conflit live** : pendant une capture de touche dans GMCM
   (propriété `IsBindingKey` lue **par réflexion**), si le combo pressé
   correspond exactement à une autre entrée du radar, toast 3 s « This key is
   already in use: {combo} — Used by: {mod - action} » + son d'annulation.

### Limites vues dans le code

- L'heuristique de nom **rate les raccourcis sans indice** — mesure faite chez
  nous (ROADMAP axe C4) : sur le parc, **118 des 466 feuilles-raccourcis n'ont
  aucun indice de nom** (`Stillbloom: MultiSelectModifier`,
  `.Automate: Controls.ToggleOverlay`). Leur radar ne les verrait pas.
- Ne voit que ce qui est **écrit dans config.json** : les raccourcis d'un mod
  jamais lancé (GMCM n'a rien encore écrit) sont absents, de même que les
  touches hors config. Notre lecture des DLL (C4-T11) et le registre GMCM en
  jeu (MCM `KeybindOverviewModal`) sont des sources plus vraies.
- `IsGmcmOptionsMenu` teste le nom de type `SpecificModConfigMenu` **et le
  namespace `GenericModConfigMenu`** — c'est le GMCM de spacechase0. Avec
  **Modern Config Menu** (palmhacker13, le front installé sur le parc), le
  namespace ne matche pas : la restauration du radar après saut et l'overlay
  live sont vraisemblablement **morts**. Analyse statique, non vérifiée à
  l'écran — mais le même code reflète aussi `Cancel` et `IsBindingKey` par
  réflexion, fragile dans tous les cas.
- La détection des appareils sépare bien PC/manette, mais un combo mixte
  (`LeftControl + LeftStick`) part du côté de sa première partie manette.

### Verdict face à notre axe C4

Keybind Radar est une **version en jeu, plus faible, de ce que l'app fait déjà
hors jeu** : notre `KeybindScanner` (règle R2 par combinaison distinctive + R4
catalogue), l'annotation « lié à » (signatures canoniques, conflit jeu
prioritaire, distinction manette, exclusions remap C4-T9) et
`KeybindReportSection` couvrent tout ce que son radar affiche, sur des sources
plus vraies. Les deux idées qui restent intéressantes sont **déjà les restes C4
notés en ROADMAP** : filtres tous/liés/conflits, recherche, saut-au-réglage et
export — un mod tout neuf qui ne fait que ça est un signal de demande. La
troisième, propre à son code : l'**avertissement au moment de la capture**
(notre annotation « lié à » est calculée après coup dans le rapport ; un signal
immédiat sous le champ pendant la capture serait l'équivalent de son overlay —
idée à garder, priorité basse).

**À ne pas porter** : l'heuristique nom-only (inférieure à la nôtre), le
fuzzy-match i18n (notre convention exacte est meilleure ; le fuzzy ne rattrape
que les mods hors convention — revenir dessus si un cas réel apparaît), la
réflexion sur les menus GMCM.

---

## 2. SaveSaver — la réparation de sauvegardes au chargement

### Ce qu'il fait

1. **Patch Harmony sur `SaveGame.TryReadSaveFile`** : à chaque chargement de
   sauvegarde, lit le XML (supporte zlib si le premier octet vaut `0x78`),
   énumère tous les attributs `xsi:type`, et **valide chaque type** contre : les
   types XSD primitifs, les types de **toutes les assemblies chargées** (jeu +
   mods, indexées au fil de l'eau), `Type.GetType`, puis des listes vanilla
   codées en dur (77 locations, 21 bâtiments, arbres, ids de fruits).
2. **Sanitation typée par contexte** pour un type non résolu :
   - slot d'équipement (chapeau, bottes, anneaux, shirt/pants) → retiré ;
   - `Item` → **reconstruit** en objet vanilla (pierre `(O)390` par défaut,
     configurable), stack et qualité préservés ;
   - `GameLocation` inconnue → **élaguée** (joueur replacé en FarmHouse s'il
     s'y trouvait) ; bâtiment → retiré ; culture → retirée ;
   - arbre sauvage inconnu → chêne/érable/pin adulte selon le nom ; fruitier
     inconnu → pommier `628` ;
   - tout autre élément → `xsi:type="Object"` et enfants vidés.
3. Les `ErrorItem` existants (`(O)ErrorItem`, nom contenant « Error Item »,
   **ou DisplayName contenant « Error »**) sont convertis à la volée si
   `AutoConvertErrorItemsOnLoad` (vrai **par défaut**).
4. Si le XML nettoyé désérialise, la sauvegarde charge (sinon repli sur le
   loader vanilla) et un **menu de rapport** (`CorruptionReportMenu`) propose :
   « Clean & Backup Save » (écriture permanente : backup vérifié non vide
   d'abord, écriture `.tmp` + `File.Move` atomique, **abandon** si le backup
   est vide) ou « Keep Temporary » (session seulement). Backups dans
   `Mods/SaveSaver/Backups`, 3 max par sauvegarde, pruning par date.
5. Au `SaveLoaded` : joueur warpé en FarmHouse si sa location est nulle,
   conversion auto des ErrorItems et des arbres cassés (HUD), rapport si
   nécessaire. Six commandes console (`savesaver_scan/clean/purge_errors/
   convert_errors/convert_trees` et `savesaver_infect`, qui **injecte** 8 faux
   items C# cassés pour tester — l'outil de test qui manque au dépôt upstream).

### Limites et risques vus dans le code

- `IsErrorItem` juge sur `DisplayName.Contains("Error")` : un item légitime
  dont le nom traduit contient « Error » serait **converti en pierre
  automatiquement**, par défaut, sans rien demander.
- La validité des types dépend des **assemblies chargées au moment du scan** —
  un mod chargé plus tard rendrait « valides » des types d'abord condamnés.
  L'ordre de chargement fait foi, pas l'état du parc.
- Les listes vanilla codées en dur (locations, bâtiments, arbres) divergeront
  des mises à jour du jeu ; le repli `DataLoader.*` ne compense que si
  `Game1.content` est prêt.
- Le cas fourre-tout (type inconnu hors item/location/bâtiment/culture/arbre)
  réécrit l'élément en `Object` vide — destructif sur un faux positif.
- **Ses backups vivent dans son propre dossier de mod** : c'est la classe
  « mod qui garde des données runtime dans son dossier » documentée en §6 de
  SOURCES.md (le cas `mod_history.json` de MCM) — sauf qu'ici la donnée n'est
  **pas régénérable** (des sauvegardes). Notre mise à jour
  `.overwriteWithBackup` supprime le dossier avant réextraction ; le snapshot
  `beforeUpdate` le conserve, mais c'est un incident en attente. Classé à
  surveiller, même note que MCM.
- Sans `UpdateKeys`, personne — SMAPI, smapi.io, notre vérificateur — ne peut
  lui trouver de mise à jour.

### Verdict — et la mesure qui compte

**Les saves maison sont propres sur l'axe C#** : Zofia (34 071 attributs
`xsi:type`) et TestOK (14 723) ne portent **aucun** type de mod orphelin, **0
ErrorItem**. Le crash au chargement que SaveSaver guérit ne nous menace pas
aujourd'hui.

Mais la passe suivante a trouvé ce que sa taxonomie **ne voit pas** : les
empreintes de mods **par identifiant nommé**. 457 noms namespacés distincts
dans Zofia, dont :

- **`Lumisteria.MtVapius` : ~133 nœuds dans le save, et le mod est ABSENT du
  parc** — le scénario exact de SaveSaver, déjà réalisé chez nous (sans crash :
  ce sont des ressources référencées par id, pas des types C#) ;
- **`Morghoula.Alchemistry` : 757 objets**, `Dayswork` : 1 bâtiment,
  `FruitTreesReforged` : des fruits — les trois mods sont **en pause**. Notre
  bascule par préfixe point produit donc des saves qui référencent des mods
  inactifs, exactement comme une désinstallation, **sans aucun
  avertissement**.

C'est l'angle qui nous appartient : SaveSaver répare au chargement, dans le
jeu ; **nous pouvons prévenir avant**, à la bascule et à la désinstallation, et
**auditer hors jeu**. Notre advantage décisif : nous connaissons le parc (mods
actifs, en pause, absents) et savons lire les DLL (`DotNetMetadata`, C4-T11)
pour dire « ce type appartient au mod X » au lieu de « type inconnu ».

**À prendre** (candidats roadmap, dans cet ordre) :
1. **Avertissement pause/désinstallation → impact saves** : croiser les
   empreintes du mod (types C# via `DotNetMetadata`, ids namespacés via
   manifest + contenu) avec les saves de l'utilisateur ; avertir à la bascule,
   chiffré (« 757 objets dans Zofia référencent ce mod »). Lecture seule.
2. **Audit de sauvegarde en lecture** : taxonomie SaveSaver (items ErrorItem,
   locations de mods disparus, bâtiments, arbres cassés) dans la vue
   Sauvegardes, avec pour chaque ligne le mod responsable et son état
   (actif/en pause/absent) — « un écran de diagnostic doit conduire » : la
   destination est la fiche du mod ou l'option de nettoyage guidé.
3. **Nettoyage guidé** (écriture, plus tard) : jamais d'auto-remplacement
   sans opt-in explicite, backup avant, diff affiché — la discipline que
   SaveSaver a correcte (backup vérifié, écriture atomique) et que notre
   `ModConfigWriteGuard` / `beforeUpdate` généralisent.

**À ne pas porter** : `DisplayName.Contains("Error")`, les listes vanilla
codées en dur (on lira le jeu et le parc), l'auto-conversion par défaut, les
backups dans le dossier du mod, la réécriture fourre-tout en `Object` vide.

---

## 3. Suites

- Sondes posées dans `check_sources.py` (`mod/keybind-radar`,
  `mod/savesaver` — cette dernière restera muette chez smapi.io tant que le
  mod ne déclare pas d'`UpdateKeys`, état relevé, pas alerte).
- Carte des sources : `docs/SOURCES.md` §5.
- Les restes C4 (filtres, recherche, saut, export) gardent leur case ROADMAP ;
  le signal de demande est renforcé par Keybind Radar.
- Les candidats d'intégration ci-dessus ne sont **pas** inscrits en ROADMAP :
  décision à prendre à la lecture de cet audit, mesures de parc disponibles
  dans le §2 pour calibrer.
