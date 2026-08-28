# Audit — Generic Mod Config Menu, Modern Config Menu, et le schéma de Content Patcher

> **Objet** : décider si StarHubFR peut lire, **hors du jeu**, la description des
> options de configuration d'un mod — types, valeurs admises, libellés, sections.
> C'est le spike **C4-T3**, avec décision go/no-go.
> **Date** : 2026-08-28. **Méthode** : décompilation IL (`ikdasm`) des deux DLL,
> archives fournies par l'auteur dans `mods tests/` ; puis mesure sur le parc réel
> (`/Applications/Stardew Valley.app/Contents/MacOS/Mods`, 1017 mods).
> Les décisions portées en `ROADMAP.md` portent la marque `§audit-config-menus`.
> Pendant de [`audit-gestionnaires.md`](audit-gestionnaires.md) et
> [`audit-stardrop.md`](audit-stardrop.md), qui couvrent les gestionnaires ; celui-ci
> ne parle que de **configuration de mods**.

---

## 1. La réponse en une ligne

**Les menus de config n'écrivent aucun schéma. Content Patcher, si.**

La question posée par C4-T3 — « les mods 49382 et 49437 écrivent-ils quelque chose
de lisible hors du jeu ? » — a deux réponses opposées selon le type de mod, et c'est
la distinction qui manquait à la roadmap :

| Type de mod | Où vit la description des options | Lisible hors jeu |
| :-- | :-- | :-- |
| **Mod SMAPI en C#** | En mémoire, enregistrée à `GameLaunched` via l'API de GMCM | **Non** |
| **Content pack (Content Patcher)** | `content.json` → champ `ConfigSchema` | **Oui, entièrement** |

---

## 2. Generic Mod Config Menu 1.16.0 — rien sur le disque

`spacechase0.GenericModConfigMenu`, `MinimumApiVersion` 4.1, DLL de 177 Ko.

**Zéro écriture.** La recherche d'appels `System.IO.File::Write*`,
`System.IO.Directory::Create*` et `JsonConvert::*` dans les 31 325 lignes d'IL ne
rend **rien**. GMCM ne persiste ni schéma, ni valeurs, ni cache.

**Il n'écrit même pas le `config.json`.** Sa méthode d'enregistrement est :

```
Register(IManifest mod, System.Action reset, System.Action save, bool titleScreenOnly)
```

`save` est une **fermeture fournie par le mod** ; GMCM l'appelle et c'est le mod qui
écrit, par `helper.WriteConfig()`. GMCM ne connaît pas le fichier.

**Le modèle d'option** (`Framework.ModOption.BaseModOption`) :

| Champ | Type | Conséquence pour nous |
| :-- | :-- | :-- |
| `FieldId` | `string` | **Identifiant choisi par l'auteur du mod**, sans lien avec la clé du `config.json` |
| `Name` | `Func<string>` | Une **fermeture**, évaluée au rendu — rien à lire statiquement |
| `Tooltip` | `Func<string>` | Idem |
| `IsTitleScreenOnly` | `bool` | |
| `Owner` | `ModConfig` | |

Dérivés : `SimpleModOption\`1`, `NumericModOption\`1`, `ChoiceModOption\`1`,
`ComplexModOption`, `ImageModOption`, `PageLinkModOption`, `ParagraphModOption`,
`ReadOnlyModOption`, `SectionTitleModOption`, `SectionSubHeaderModOption`.
Plus `Overlays.KeybindOverlay` / `KeybindEdit` pour la saisie de raccourcis.

**`FieldId` explique un chiffre qui nous manquait.** Sur les ~13 000 clés `config.*`
trouvées dans les `i18n/` du parc, **6 172 ne retombent sur aucune clé du
`config.json` du même mod** — par exemple `config.lltk-difficulty.name` dans un mod
dont le `config.json` commence par `AbilityBar1Slot1`. Ce ne sont pas des erreurs
d'auteur : ce sont des identifiants d'option GMCM, et **rien sur le disque ne les
relie à une clé de configuration**. Toute tentative d'étiquetage par les `i18n/`
seuls hérite de ce plafond.

---

## 3. Modern Config Menu 1.7.4 — un export, mais de valeurs

`palmhacker13.ModernConfigMenu`, `MinimumApiVersion` 4.0.0, 19,5 Mo (il embarque
FontStashSharp, StbImageSharp, Cyotek.BitmapFont — sa propre pile de rendu).

**Son modèle en mémoire est plus riche que celui de GMCM** — `SettingBase` porte
`Name`, `Tooltip`, `Section`, `Page`, `ParentSettingId` (options conditionnelles),
`IndentLevel`, `IsEnabled`, `IsVisible`, `IsLive` (application immédiate),
`IsHostOnly`, `IsPinned`, `CachedDisabledReason`, `CachedValidationError` ;
`SliderSetting` porte `Min`/`Max`, `DropdownSetting` porte `Choices`.

**Il écrit un fichier, et c'est le seul du lot** :

```
Helper.Data.WriteJsonFile<Dictionary<string,string>>(
    Path.Combine("config_exports", <UniqueID> + ".json"), …)
```

⚠️ **Mais c'est un export de *valeurs*, pas de schéma.** Le dictionnaire associe
`SettingBase.Name` — le **libellé affiché**, donc localisé — à la valeur courante
rendue en chaîne (couleur en `#RRGGBB`, liste de raccourcis, texte). Ni type, ni
bornes, ni valeurs admises, ni clé de `config.json`. Un chemin d'**import**
symétrique existe (« No export file found at … »), ce qui en fait une fonction de
sauvegarde/transfert de réglages, pas une source de description.

**`GenericModConfigMenuCompat` n'est pas le pont** — mais un pont existe ailleurs.
Cette classe-là appelle bien `Register(ModManifest, …)`, `AddParagraph`,
`AddKeybindList` avec **son propre** manifeste : c'est MCM qui s'inscrit dans GMCM
pour y exposer son raccourci.

⚠️ **Correction du 2026-08-28** (relecture de la DLL **installée**, 1.7.3, à partir
de la page Nexus qui annonce « All GMCM-registered mods are automatically
styled ») : le premier passage avait conclu de cette seule classe que MCM n'accédait
pas aux données de GMCM. **C'est faux.** Son IL porte un chemin
`[MCM GMCM-Import]` qui **réfléchit dans la mémoire vive de GMCM** :

```
type « GenericModConfigMenu.Mod »
  → champ « instance » / « Instance »
  → champ « ConfigManager » / « configManager »
  → champ « configs » / « Configs », casté en IDictionary
```

puis reconstruit chaque enregistrement dans son propre `ModConfigRegistry` /
`RegisteredMod`. Les messages d'échec sont explicites (« ConfigManager field not
found », « configs dictionary cast to IDict… », « Skip entry '…' »).

**Ce que cette correction ne change pas** : l'import ne fait **aucune écriture** —
0 `WriteJsonFile`, 0 `File::Write` sur tout le chemin. Il marche parce que MCM
s'exécute **dans le processus du jeu**, à côté de GMCM, après que les mods s'y sont
enregistrés. Hors du jeu, il n'y a toujours rien à lire : le verdict de non-go tient,
et la seule source hors-jeu reste le `ConfigSchema` de Content Patcher.

---

## 4. Content Patcher — le schéma que personne n'était allé chercher

Un content pack déclare ses options dans `content.json`, champ **`ConfigSchema`** :

```json
"ConfigSchema": {
  "EnableJohn": { "AllowValues": "true, false", "Default": true }
}
```

Content Patcher génère ensuite le `config.json` correspondant au lancement.
**C'est un schéma complet, sur le disque, sans décompilation ni heuristique.**

### Mesuré sur le parc (2026-08-28)

| | content packs | dont `ConfigSchema` | tokens | clés de `config.json` décrites |
| :-- | --: | --: | --: | --: |
| **Actifs** | 30 | **20** | 1 041 | **100 %** |
| En pause | 561 | 256 | 5 335 | **100 %** |

La couverture est **totale** — c'est attendu, puisque c'est Content Patcher qui
génère le `config.json` à partir du schéma. Là où l'étiquetage par `i18n/` plafonne
à 39 % des clés côté mods actifs, celui-ci ne rate rien.

### Les champs réellement rencontrés, par fréquence

| Champ | Occurrences | Ce qu'il donne |
| :-- | --: | :-- |
| `Default` | 6 372 | La valeur par défaut → bouton « réinitialiser », et le repérage des valeurs modifiées |
| `AllowValues` | 5 053 | Les valeurs admises → **liste déroulante au lieu d'un champ libre**, et validation |
| `Section` | 4 831 | **Le regroupement** — absent de la doc de référence, présent partout |
| `Description` | 3 378 | L'infobulle, en clair |
| `AllowBlank` | 871 | Le vide est-il permis |
| `AllowMultiple` | 408 | Valeurs multiples séparées par virgule |
| `Name` | 173 | Libellé explicite, sinon le nom du token |

⚠️ **Variantes à tolérer, mesurées, pas supposées** : `Allow Multiple` avec une
espace (40), `section` en minuscules (35), `description` (1), et deux coquilles
uniques — `HostowValues`, `HostowBlank` — vraisemblablement un remplacement
« All » → « Host » qui a débordé. Le lecteur doit être **insensible à la casse et
tolérant à l'espace**, et ignorer sans bruit ce qu'il ne reconnaît pas.
**14 `content.json` sont illisibles** même avec un analyseur JSON5 : le repli doit
être l'éditeur brut, jamais une erreur.

---

## 5. Ce que vaut l'autre voie : les libellés par `i18n/`

Pour les mods **C#**, la seule source hors jeu reste le dossier `i18n/`, où
l'auteur publie des clés `config.<tige>.name` / `.description` / `.tooltip`.
Règle de rattachement mesurée : comparer la **tige** (clé i18n privée de son
préfixe `config.` et de son suffixe `name|description|tooltip|desc|label|title`)
à la clé du `config.json`, insensible à la casse.

| | mods candidats | clés de config | étiquetées | au moins une | toutes |
| :-- | --: | --: | --: | --: | --: |
| **Actifs** | 47 | 782 | **304 (39 %)** | 25 | 13 |
| Tout le parc | 258 | 6 118 | 4 468 (73 %) | 192 | 140 |

C'est utile mais partiel, et le plafond est structurel (§2, `FieldId`).
*(L'écart 39 % / 73 % n'est pas expliqué — 47 mods actifs, échantillon trop petit
pour en tirer une règle.)*

---

## 6. Les commentaires du `config.json` ne portent rien

Le plan C4 supposait qu'on pourrait **inférer** types et valeurs admises depuis les
commentaires du `config.json`. Mesure définitive, commentaires détectés **hors
chaîne** (un `//` dans une URL ne compte pas) : sur les **547 `config.json` voisins
d'un `manifest.json`** — les vrais fichiers de configuration de mod — **zéro** porte
un commentaire. **L'inférence par commentaires n'a aucune matière.**

*(Une recherche plus large trouve 569 fichiers nommés `config.json` dans l'arbre,
dont 2 commentés — mais ces deux-là vivent dans un dossier `i18n/` : ce sont des
fichiers de traduction qui partagent le nom, pas des configurations. Le premier
relevé de la journée annonçait « 4 » parce qu'il comptait des `//` situés à
l'intérieur de chaînes.)*

Conséquence de second ordre : préserver les commentaires à l'écriture **ne protège
rien** sur ce parc. Ce qui reste à protéger, c'est l'**ordre des clés** — et
`ConfigJSONTree` sait déjà le faire (§7, #6).

❓ **Question ouverte, non tranchée** : SMAPI réécrit-il le `config.json` à chaque
lancement (ce qui effacerait commentaires et ordre des clés de toute façon), ou
seulement quand une clé manque ? Test discriminant, pas encore fait : relever la
date de modification de ces 4 fichiers et vérifier s'ils survivent à un lancement.
Ne pas construire d'argument sur cette hypothèse avant de l'avoir mesurée.

---

## 7. Synthèse — ce qui entre dans la roadmap

| # | Trouvaille | Source | Poids | Sort |
| :-- | :-- | :-- | :-- | :-- |
| 1 | Lire `ConfigSchema` de `content.json` : type, défaut, valeurs admises, section, description | Content Patcher | **M** | **La voie principale** — 20 packs actifs, 100 % de couverture |
| 2 | Étiquetage par `i18n/` pour les mods C# | GMCM (par défaut) | **M** | Voie secondaire, plafond 39 % côté actifs |
| 3 | Regroupement par section, au lieu d'une liste alphabétique | CP `Section` + MCM `Section`/`Page` | **S** | À faire avec #1 |
| 4 | Détection de collision de raccourcis | GMCM `KeybindOverlay` | **M** | Confirme **C4-T2** ; référence d'ergonomie |
| 5 | Export/import des valeurs de config en fichier portable | MCM `config_exports/` | — | **Écarté** : nos profils et `ModConfigBackupManager` couvrent mieux (par profil, avec restauration clé à clé) |

### Écarté, avec la raison

| Sujet | Source | Raison |
| :-- | :-- | :-- |
| Lire un export de schéma GMCM | GMCM | Il n'en existe pas — rien n'est écrit sur le disque |
| Décompiler les DLL des mods pour retrouver les appels d'enregistrement | — | Coûteux, fragile, à recasser à chaque mise à jour de mod. C'est la voie que **C4-T3** rejetait d'avance, et rien ici ne la réhabilite |
| `ParentSettingId`, `IsHostOnly`, `IsLive` | MCM | Modèle riche, mais **aucune source hors jeu** pour un mod quelconque : on ne saurait pas les renseigner |
| Inférence depuis les commentaires du `config.json` | plan C4, tâche 6 | 4 fichiers sur 547, aucun ne porte de borne ni de choix |
