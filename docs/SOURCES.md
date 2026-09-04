# Sources externes de StarHubFR

> **Objet** — recenser tout ce dont l'app dépend hors de ce dépôt : les API
> qu'elle interroge en marche, les dumps qu'elle télécharge, les projets dont
> du code ou des idées ont été reprises. Et dire, pour chacune, **où elle est
> utilisée** et **comment vérifier qu'elle a bougé**.
>
> Relevé initial : **2026-09-04**. Toutes les valeurs chiffrées de ce document
> sont mesurées ce jour-là, pas estimées.
>
> ⚠️ Ce fichier est la **carte**. L'état courant, lui, se relève par
> `python3 check_sources.py` (référence dans `.sources-baseline.json`) — ne pas
> recopier de versions ici, elles pourriraient. Ce document porte les *rôles*
> et le *raisonnement*, le script porte les *valeurs*.

---

## 1. Comment vérifier

```bash
python3 check_sources.py            # relève et compare (sortie 1 s'il y a un écart)
python3 check_sources.py --report   # relève et affiche tout, sans juger
python3 check_sources.py --offline  # seulement les contrôles locaux
python3 check_sources.py --update   # assume l'état courant comme référence
```

Même patron que `check_standards.py` / `.standards-baseline.json` : un relevé,
une référence, un `--update` explicite visible dans le diff. Une différence
majeure de sens : **un écart n'est pas une faute**. Une nouvelle version de
SMAPI n'est pas un bug, c'est une chose à aller regarder.

Les sources injoignables sont reportées séparément et **ne comptent pas comme
un écart** : une panne de réseau ne doit pas se lire comme « SMAPI a sorti une
version ». Et `--update` conserve la référence d'une source injoignable au lieu
de l'écraser par du vide.

**Le script a été éprouvé par mutation** (2026-09-04) : nouvelle version de
SMAPI, retournement du piège `platform`, disparition d'un champ du dump,
modification d'une constante dans le code, référence corrompue — les cinq sont
attrapés, avec les bons codes de sortie (1 pour un écart, 2 pour une référence
illisible). `--update --only X` ne perd pas les autres clés. Ce dépôt a payé
assez cher des scripts qui rendaient `exit 0` sur un échec pour que ça se
vérifie plutôt que ça se suppose.

---

## 2. Contrats réseau vivants

Ce que l'app appelle pendant qu'elle tourne. Une rupture ici casse une
fonctionnalité chez l'utilisateur, souvent **en silence**.

### 2.1 smapi.io — API de mise à jour

| | |
|---|---|
| **Point d'entrée** | `POST https://smapi.io/api/v3.0/mods` |
| **Rôle** | le verdict de mise à jour **et** de compatibilité de tout le parc |
| **Code** | `StarHubTH/SmapiUpdateClient.swift`, `Models/SmapiUpdateRequest.swift`, `Models/SmapiUpdateResponse.swift` |
| **Clé requise** | non — gratuit, sans quota. C'est la voie principale ; Nexus n'est le filet que pour ce que smapi.io ne tranche pas |

**Son mode de panne est le silence.** Le service rend `HTTP 200` et une **liste
vide** quand un champ ne lui plaît pas. Quatre champs en sont capables, et les
trois premiers sont documentés dans `SmapiUpdateRequest.swift` :

1. `apiVersion` absent → aucune suggestion ;
2. `gameVersion` malformé (`"1.6.15."`, `"x.y.z"`) → lot entier vide ;
3. `installedVersion` inanalysable sur **une seule** entrée → les 150 du lot
   disparaissent ;
4. **`platform` sensible à la casse** — `"Mac"` répond, `"macOS"` et `"MacOS"`
   rendent une liste vide. Mesuré le 2026-09-04, et **jusque-là non
   documenté**. Le code envoie bien `"Mac"` ; c'est une mine, pas un défaut. Le
   contrôle de `check_sources.py` la surveille dans les deux sens.

Deux constantes figées, délibérément :

- `apiVersion = "4.1.10"` alors que SMAPI en est à 4.5.2. **Ce n'est pas du
  retard** : re-mesuré le 2026-09-04, `1.0.0`, `4.1.10` et `4.5.2` rendent les
  mêmes suggestions aux mêmes mods. La version installée, elle, est absente
  quand SMAPI a été posé hors de l'app.
- `defaultGameVersion = "1.6.15"` — conforme au jeu réellement installé
  (`SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356`).

Le chemin de version de l'URL n'est pas discriminant : `v2.0`, `v3.0` et `v4.0`
répondent tous à l'identique.

### 2.2 Pathoschild / SmapiCompatibilityList — le dump de compatibilité

| | |
|---|---|
| **URL** | `https://raw.githubusercontent.com/Pathoschild/SmapiCompatibilityList/develop/data/mods.jsonc` |
| **Rôle** | filet hors-ligne des verdicts, quand smapi.io est muet |
| **Code** | `StarHubTH/Models/PathoschildCompatibilityList.swift` |
| **Branche** | `develop` est la branche **par défaut** ; `main` n'existe pas (un lien vers `main` rend un 404 de 14 octets) |

⚠️ C'est du **JSONC** : commentaires de ligne et virgules traînantes. Et les
`//` abondent à l'intérieur des chaînes (chaque URL en porte) — une regex naïve
coupe au milieu d'un `https://` et rend le fichier illisible. Le décodeur Swift
et le `_strip_jsonc` du script traitent tous deux les chaînes à part.

**Ce qu'on n'exploite pas encore**, mesuré sur le dump (4 720 mods) puis croisé
avec le parc réel (1 090 identifiants, 292 connus du dump) :

| Champ | Dans le dump | Sur le parc | Décodé ? |
|---|---:|---:|---|
| `status` | 534 | 2 | ✅ |
| `brokeIn` | 1 109 | 8 | ✅ |
| `summary` | 334 | — | ✅ |
| `unofficialUpdate` | 67 | **5** | ❌ |
| `warnings` | 24 | **2** | ❌ |
| `abandonedReason` | 277 | 0 | ❌ |

Les cinq `unofficialUpdate` du parc sont des correctifs communautaires
installables (Bus Locations, Informant, SAAT ×2, Mod Update Menu) — voir X56.

### 2.3 Nexus Mods — API v1 (REST)

| | |
|---|---|
| **Base** | `https://api.nexusmods.com/v1` |
| **Rôle** | fiche mod, fichiers, changelogs, quota, compte, téléchargement premium |
| **Code** | **un seul constructeur**, `Models/NexusRequestBuilder.makeRequest(path:apiKey:)`. Deux jeux d'en-têtes feraient voir deux clients distincts à Nexus |
| **Clé** | requise, dans le Trousseau (`KeychainSecret`) |
| **État** | v1 toujours servie, aucune date de retrait annoncée. Un `401` sans clé est la bonne réponse — c'est ce que le script relève |

v1 **ne sait pas chercher** : la recherche passe par GraphQL (§2.4).

### 2.4 Nexus Mods — API v2 (GraphQL)

| | |
|---|---|
| **Point d'entrée** | `https://api.nexusmods.com/v2/graphql` |
| **Rôle** | la recherche de mods, la vitrine Découverte |
| **Code** | `StarHubTH/NexusSearchClient.swift` |
| **À savoir** | le filtre est un tag `French`, pas une catégorie. `ModsFilter` porte 27 champs, dont `categoryName` et `languageName` |
| **Sonde** | aucune — exige un jeton |

### 2.5 DeepL — traduction de secours

| | |
|---|---|
| **Base** | `https://api-free.deepl.com` (plan gratuit) ou `https://api.deepl.com` |
| **Chemins** | `/v2/translate`, `/v2/usage` |
| **Code** | `Models/DeepLClient.swift`, `Models/DeepLDesktop.swift` |
| **Clé** | Trousseau, et le secours n'envoie rien sans **accord explicite** en plus de la clé |
| **Sonde** | aucune, volontairement — elle consommerait le quota de la clé |

### 2.6 IA locale — Ollama / LM Studio

| | |
|---|---|
| **Contrat** | `POST {base}/v1/chat/completions`, compatible OpenAI |
| **Bases admises** | loopback uniquement (`localhost:11434`, `127.0.0.1:1234`…), validé par `LocalLLMEndpoint.validate` |
| **Code** | `Models/LocalLLMClient.swift`, `Models/LocalLLMEndpoint.swift`, `Models/OllamaCapabilities.swift` |
| **Sur cette machine** | Ollama **0.33.3**, un modèle : `qwen2.5:7b` |
| **Sonde** | aucune — le service ne tourne pas toujours |

### 2.7 GitHub — releases

Deux usages, sans clé :

- `api.github.com/repos/Pathoschild/SMAPI/releases/latest` — l'installateur
  SMAPI (`SmapiInstaller.swift`) télécharge l'archive de la dernière release.
- `api.github.com/repos/AppleBoiy/stardew-thai-translations/releases?per_page=100`
  et `raw.githubusercontent.com/.../main/README.md` — le catalogue et les
  archives du hub thaï (`StarHubTHViewModel`).

⚠️ Sans jeton, l'API GitHub plafonne à **60 requêtes/heure par IP**. Le script
passe par `gh` quand il est présent (5 000/h).

### 2.8 Steam

`steam://run/413150` pour lancer le jeu, et les fichiers locaux du client Steam
pour le nom et l'avatar du joueur. Pas d'API, pas de sonde.

---

## 3. Code et algorithmes repris

Ce qui n'est pas appelé en marche, mais dont du code vit chez nous. **Le crédit
est permanent, en tête de chaque fichier concerné.**

| Source | Licence | Ce qui a été repris | Où |
|---|---|---|---|
| [**lzxd** 0.2.6/0.2.7](https://codeberg.org/Lonami/lzxd) — Lonami | MIT **ou** Apache-2.0 | **translittération** Swift du décodeur LZX (train de bits, arbres canoniques, fenêtre) | `LzxdDecoder`, `LzxdWindow`, `LzxdTree`, `LzxdBitstream` |
| [**libmspack**](https://github.com/kyz/libmspack) — Stuart Caie | LGPL-2.1 | référence de lecture du format LZX (jamais de code copié) | idem |
| [**StardewXnbHack**](https://github.com/Pathoschild/StardewXnbHack) — Pathoschild | MIT | structure des `.xnb` du jeu | `XnbStringDictionaryReader` |
| [**SMAPI**](https://github.com/pathoschild/SMAPI) — Pathoschild | MIT | format du journal, schéma de manifeste, leniance JSON | `SmapiLogParser`, `SmapiDiagnostics`, `ManifestJSON` |
| **Newtonsoft.Json** (via la DLL du jeu) | MIT | **oracle exécuté**, pas lu : la vraie leniance JSON de SMAPI, mesurée en faisant tourner la DLL sous mono | `I18nLenientParser`, `ConfigJSONTree` |
| [**SMAPILogDoctor.py**](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod) — ZeroXPatch | — | **l'idée** d'un diagnostic de journal SMAPI présenté au joueur | `SmapiDiagnostics` |
| [smapi.io/log](https://smapi.io/log/) | — | le découpage de référence du journal | `SmapiLogParser` |
| [**stardew-i18n-translator**](https://github.com/Nana1873/stardew-i18n-translator) — Nana1873 | — | jetons protégés (3 formes composées reprises), 6 garanties d'écriture | `TranslationTokenCheck`, `TranslationDocument` |
| [**stardew-save-editor**](https://github.com/colecrouter/stardew-save-editor) — colecrouter | — | référence de l'édition de sauvegardes | `SaveManager` |
| **Content Patcher** — `ConfigSchema` | — | le schéma des options de config d'un mod ; les libellés, eux, vivent dans le i18n du pack (`config.<clé>.name`) | `ConfigJSONTree`, `ModConfigSchema` |

⚠️ Le dépôt GitHub de **lzxd** est **archivé** (dernier commit :
« Migrate off GitHub », 2026-02-09) ; la suite est sur **Codeberg**. Les deux
hôtes répondent encore, les crédits en tête des fichiers Swift restent donc
valides — mais c'est Codeberg qu'il faut consulter pour toute divergence future.
Codeberg n'a pas d'API publique stable : cette source se suit **à la main**.

---

## 4. StarHubTH — l'amont

| | |
|---|---|
| **Dépôt** | `AppleBoiy/StarHubTH` |
| **Base commune** | `e38c4eb` (« Update CHANGELOG for version 1.0.9 ») |
| **État** | **figé depuis le 2026-07-27**, non archivé, 0 étoile |
| **Divergence** | **204 commits** présents chez l'amont et absents de chez nous, tous entre le 2026-07-23 et le 2026-07-27, dont **28 `fix:`** |

L'amont a bifurqué vers une **autre application** : réécriture en Swift 6 strict
(`LogStore`, `AppLauncher`, `FilePicker`, `ModInstaller`, `URLDispatcher`),
outillage XCUITest de capture d'écran, publication automatique sur Nexus. Notre
fork a gardé le monolithe et a évolué ailleurs. « Intégrer » l'amont veut donc
dire reprendre des **idées et des correctifs**, jamais des commits.

**Deux correctifs amont vérifiés le 2026-09-04**, les seuls qui touchent des
sous-systèmes que nous avons toujours :

- `6306958` *SmapiLogParser silently found zero updates against real SMAPI logs*
  — une ligne vide juste après « You can update N mods: » terminait le bloc.
  **Déjà intégré chez nous**, et `SmapiLogParser.swift:148-154` crédite le
  commit amont.
- `f488efe` *BBCode list parsing for `[list=1]`, `[list=a]`, `[li]`, headings*
  — **dépassé** : notre `DescriptionBlockParser` gère `[list…]` avec attributs,
  `[*]`, `[li]`, les titres par `[size]`/`[heading]` et l'imbrication, avec un
  vrai type `.list(items:ordered:)` là où l'amont produisait du texte à tirets.

Voir aussi la mémoire `audit-fix-commits-by-message-not-title` : **16 des
20 correctifs amont examinés avaient été écartés sur leur seul titre**, dont
deux qui valaient instruction. Ne pas trier ces 204 commits sur leur libellé.

---

## 5. Concurrents observés

| Projet | Nature | Ce qu'on en a tiré |
|---|---|---|
| [**Stardrop**](https://github.com/Floogen/Stardrop) — Floogen | C# / Avalonia, 269 ★, **très actif** | `docs/audit-stardrop.md` (2026-07-31) : smapi.io en direct plutôt que le dump, configs par profil, notes, `UpdateCautionMessage`. **Ne pas porter** SimpleObscure ni les jonctions de dossiers |
| [**Nexus Mods App**](https://nexus-mods.github.io/NexusMods.App/developers/) | officiel, Rust/C# | documentation du protocole `nxm://` et des collections |
| [node-nexus-api](https://github.com/Nexus-Mods/node-nexus-api) | client officiel Node | forme des réponses de l'API v1 |
| Divers (RWELabs, thimadera, Zamiell, awesomestardew…) | — | inventaire de l'écosystème, cités dans `docs/audit-gestionnaires.md` |

### Ce que Stardrop a livré depuis notre audit

Notre audit date du **2026-07-31** ; Stardrop a poussé jusqu'au **2026-09-01**
et sorti `v1.10.0-beta.2`. Les changements qui touchent nos zones :

1. **`Enable / Disable All Mods` n'agit plus que sur les mods visibles dans la
   grille** (2026-09-01, `c630c11`). Leur règle : *« Bulk actions run through
   this so that what the user is looking at is what they act on »* — filtre de
   source, recherche, filtres actif/inactif et mods masqués, sous une règle
   unique, évaluée sur l'état courant et non relue de la vue. Chez nous,
   repris le **2026-09-04** (X57) : la règle de cadrage vit dans le
   ViewModel, et la liste comme la bascule en dérivent.
2. **Enregistrement du protocole NXM durci** (2026-08-31). Nous avons aussi un
   gestionnaire `nxm://` ; à comparer.
3. **Notifications de mise à jour qui n'arrivaient qu'après redémarrage**
   (2026-08-31) — corrigé chez eux ; symptôme voisin de notre X52.
4. **Ignorer une version, de façon réversible et visible** (2026-08-28). Nous
   avons l'équivalent — « Je l'ai déjà » (X12) avec `revealAffirmedUpdate` pour
   revenir en arrière : rien à reprendre, mais bon à savoir aligné.
5. **« Collection Installed Mods Path »** (2026-08-31) — les collections Nexus,
   que nous ne gérons pas du tout.

---

## 6. Mods du jeu observés — la convention `config.*`

Références du domaine, pas des dépendances : aucun code de ces mods ne vit
chez nous. Elles sont là parce que notre **éditeur de config** lit une
convention dont ces mods sont l'origine et le corpus — étudiés le
**2026-09-04** depuis les archives de `mods tests/` (gitignoré), pas depuis
les pages Nexus. L'audit approfondi (décompilation comprise) vit dans
`docs/audit-mods-config-perf.md`.

**La convention.** Un mod SMAPI configurable enregistre ses options auprès
d'un menu générique (l'API `IGenericModConfigMenuApi`) et résout
**lui-même** ses libellés dans son i18n, selon les clés nées des exemples
GMCM : `config.<clé>.name` / `.tooltip`, et par extension
`config.<clé>.choice.<valeur>`, `config.<clé>.button`,
`config.section.<id>.title` / `.desc`, `config.category`. Notre éditeur lit
ces clés **statiquement**, jeu éteint — voir la mémoire
`mod-config-schema-sources`.

Mesuré dans les DLL (scan UTF-16) : `ModernConfigMenu.dll` porte « Generic
Mod Config Menu detected » et « not installed; nothing to import » — c'est
un front alternatif qui **importe les enregistrements GMCM** — et zéro clé
`config.*` en propre ; `UltraSmooth.dll`, elle, compose ses clés
elle-même (« Modern Config Menu detected. Registering… »). La convention
vit dans les i18n des mods, pas dans les menus : c'est pourquoi une lecture
statique peut exister, et pourquoi elle survit aux remplacements de front.

| Mod | Identité | Ce qu'on en tire |
|---|---|---|
| [**Generic Mod Config Menu**](https://www.nexusmods.com/stardewvalley/mods/5098) — spacechase0, 1.16.0 | `spacechase0.GenericModConfigMenu` · Nexus 5098 · [source](https://github.com/spacechase0/StardewValleyMods) (monorepo, **surveillé**) | **l'origine de la convention `config.*`** que notre éditeur lit pour ses libellés |
| [**Modern Config Menu**](https://www.nexusmods.com/stardewvalley/mods/49437) — palmhacker13, 1.7.8 | `palmhacker13.ModernConfigMenu` · Nexus 49437 | la preuve que la convention survit à un changement de front : même i18n, autre UI |
| [**UltraSmooth**](https://www.nexusmods.com/stardewvalley/mods/50971) — palmhacker13, 2.1.3 | `palmhacker13.UltraSmooth` · Nexus 50971 · dépend de MCM | **le corpus de test de l'éditeur** : 115 clés `config.*` (41 `.name`, 41 `.tooltip`, 11 `.button`, 16 de section, 4 `.choice`) plus une clé maison `.gmcmGuide` ; porte aussi un `i18n/th.json` (hub thaï) |
| [**Faster Menu Load**](https://www.nexusmods.com/stardewvalley/mods/41564) — ZeroXPatch, 1.5.0 | `ZeroXPatch.FasterMenuLoad` · Nexus 41564 | même auteur que le SMAPILogDoctor crédité §3 ; une des 13 dépendances du SLO ; **seul des cinq non installé** sur le parc |
| [**Stardew Loading Optimizer**](https://www.nexusmods.com/stardewvalley/mods/50153) — neoiw, 1.0.0 (source : 0.5.0-rc.18) | `neoiw.StardewLoadingOptimizer` · Nexus 50153 | orchestrateur de 13 mods de performance ; son téléchargement « Source Code » est un **exemple complet d'intégration GMCM côté mod** (`GenericModConfigMenuIntegration.cs`) |
| [**Profiler**](https://www.nexusmods.com/stardewvalley/mods/12135) — SinZ, 2.0.0 | `SinZ.Profiler` · Nexus 12135 · [source](https://github.com/SinZ163/StardewMods/tree/main/Profiler) (monorepo SinZ163, **surveillé**) | **la télémétrie que le chantier D1 parse** : `[BigLoop] In total, it took {0:N}ms handling …` (chaîne mesurée dans la DLL). Ses packs de contenu étendent le profilage **par déclaration** (`{Type: "Duration", TargetType, TargetMethod}`). **Installé sur le parc mais en pause** (`.Profiler/`) — sa détection doit regarder les mods en pause, pas seulement les actifs. Le zip 2.0.0 de `mods tests/` embarque le `Profiler.pdb` : les symboles de débogage sont là si le format de log doit être vérifié plus finement |

Deux constats de lecture, mesurés :

- **Le manifeste du SLO contredit son README** : les 13 dépendances y sont
  toutes **requises** (`IsOptional` absent de chacune), alors que le README
  présente Content Patcher, SpaceCore et GMCM comme « optional integrations,
  not required dependencies ». SMAPI applique le manifeste — c'est lui qui
  fait foi sur le disque.
- Cinq des six sont **installés sur le parc** (tous sauf Faster Menu Load ;
  Profiler y est **en pause**) : leurs mises à jour relèvent donc du
  vérificateur de l'app. Les six **versions** sont néanmoins surveillées par
  `check_sources.py` (sonde `smapi-mod`) : les pages Nexus renvoient **403**
  aux clients non-navigateurs (Cloudflare, mesuré sur urllib et curl le
  2026-09-04) et l'API v1 exigerait la clé du Trousseau — l'oracle est
  smapi.io, avec la grammaire exacte de `SmapiUpdateRequest` (lot d'un,
  `platform: "Mac"`). Les sources **code** suivent leurs monorepos GitHub :
  GMCM (spacechase0), FasterMenuLoad (ZeroXPatch, entrée `log-doctor`) et
  Profiler (SinZ163, entrée `profiler-source`).

---

## 7. Pistes d'intégration ouvertes

Consignées en `docs/ROADMAP.md` §4, avec leur mesure :

- **X56** — les champs `unofficialUpdate`, `warnings` et `abandonedReason` du
  dump Pathoschild ne sont pas décodés. Sur le parc : 5, 2 et 0 mods
  respectivement. Les cinq premiers sont des correctifs communautaires
  installables pour des mods que rien ne signale aujourd'hui.
- ~~**X57** — la bascule en masse agit sur le parc entier alors que son
  bouton vit dans une liste filtrée et paginée.~~ **Corrigé le 2026-09-04** :
  la règle de cadrage vit dans le ViewModel (`mods(matching:)` +
  `scopedMods(from:scope:)`), liste et bascule en dérivent — voir ROADMAP §4.
Fait dans la même passe : le piège `platform` est désormais documenté dans
`SmapiUpdateRequest.swift`, à côté des trois autres champs capables de vider un
lot en silence, et surveillé par `check_sources.py`.

---

## 8. Mesures à ne pas refaire

Relevées le 2026-09-04, sur le parc réel
(`/Applications/Stardew Valley.app/Contents/MacOS/Mods`) :

- **1 096 manifestes**, 1 090 `UniqueID` distincts, **0 illisible**.
- **142 manifestes portent un BOM UTF-8**, tous lus correctement — le piège
  documenté dans `CLAUDE.md` disait l'inverse et était faux (voir son entrée
  corrigée).
- **0 manifeste hors UTF-8.**
- 949 dossiers de tête : **79 actifs, 870 en pause**.
- **1 collision `X` / `.X`** : `[CP] Seaside Sounds` — deux mods, deux auteurs.
- **30 `i18n/th.json`**, dont **22 sous un dossier en pause**.
- Dump Pathoschild : **941 484 octets**, 4 720 mods.
- smapi.io : `apiVersion` sans effet sur le résultat, `platform` sensible à la
  casse, `v2.0`/`v3.0`/`v4.0` équivalents.
