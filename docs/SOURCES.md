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
python3 check_sources.py --fetch-changelogs  # va LIRE les journaux en retard (API v2, sans clé)
python3 check_sources.py --changelog-reviewed mod/x=1.2.3   # note qu'on a lu son journal
```

Même patron que `check_standards.py` / `.standards-baseline.json` : un relevé,
une référence, un `--update` explicite visible dans le diff. Une différence
majeure de sens : **un écart n'est pas une faute**. Une nouvelle version de
SMAPI n'est pas un bug, c'est une chose à aller regarder.

Les sources injoignables sont reportées séparément et **ne comptent pas comme
un écart** : une panne de réseau ne doit pas se lire comme « SMAPI a sorti une
version ». Et `--update` conserve la référence d'une source injoignable au lieu
de l'écraser par du vide.

### Les changelogs — pourquoi c'est une note, pas une sonde *(2026-09-14)*

Une version qui monte ne dit pas **ce qui a changé**, et c'est souvent le
changelog qui porte la conséquence pour notre code — le cas fondateur est MCM
2.1.0, dont le journal annonçait un `data/mod_history.json` écrit dans le dossier
du mod, que notre mise à jour supprime (devenu **A1-T7**).

**La page Nexus n'est pas lisible par un script** : `urllib` et `curl` — même
avec un `User-Agent` de navigateur — prennent un **403 Cloudflare**, et l'API v1
`/mods/{id}/changelogs.json` exige la clé du Trousseau. ⚠️ *Le paragraphe
concluait qu'aucun script ne lit un changelog Nexus ; faux depuis la mesure du
2026-09-25 : l'API v2 les rend sans clé (voir « La voie qui marche » ci-dessous).* L'ancien endpoint `Core/Libs/Common/Widgets/ModChangeLogs` a par
ailleurs disparu avec le passage de Nexus à Next.js.

> ⚠️ **Correction du 2026-09-14, le soir même** : une première version de ce
> paragraphe affirmait que la page `?tab=logs` « ne rend qu'un squelette » dans un
> vrai navigateur. **C'est faux**, et l'auteur l'a relevé. Elle est parfaitement
> lisible **sans compte** — les **33 changelogs** de MCM en ont été extraits. Deux
> erreurs de méthode se cumulaient : le DOM avait été lu **avant la fin du
> chargement** (le contenu arrive en AJAX ; un `wait_for` sur le numéro de version
> suffit), puis via `body.innerText`, **qui ne rend rien d'un conteneur masqué** —
> alors que les `<h3>Version …</h3>` étaient bien présents dans le document. Lire
> le DOM (`querySelectorAll('h3')`), jamais `innerText`, et attendre. Le suivi
> ci-dessous garde tout son sens — un agent lit la page, aucun script ne le peut —
> mais pour la bonne raison.

**GitHub ne sauve pas la mise non plus.** Sur les trois seules sources
`smapi-mod` qui déclarent un dépôt, `spacechase0/StardewValleyMods`,
`SinZ163/StardewMods` et `ZeroXPatch/Projects-for-Nexus-Mod` n'ont **aucune
release**, et sur les **100 tags** du premier, **aucun** ne nomme GMCM. Un étage
« notes de release » ne rendrait rien pour aucune d'elles.

**La voie qui marche : l'API v2, sans clé** *(F9, 2026-09-25)*.
`--fetch-changelogs` va chercher les journaux des sources en retard par
`POST https://api.nexusmods.com/v2/graphql` — `modFiles(modId, gameId: 1303)
{ version date changelogText }` — et les rend au format de l'ancienne v1,
`{version: [lignes]}`, du plus ancien au plus récent. Un journal identique
sur plusieurs fichiers d'une même version compte une fois, un journal
différent ajoute ses lignes neuves (règle d'A3-T7) ; un fichier sans journal
ne crée pas d'entrée.
Aucune clé, donc plus de Trousseau ni de `NEXUS_API_KEY` : la v1
(`changelogs.json`), qui les exigeait, et l'option `--use-keychain` sont
retirées. ⚠️ Un identifiant inconnu rend une liste **vide**, pas une erreur —
indiscernable d'un mod sans journal ; les identifiants viennent de nos propres
entrées, le cas ne se pose qu'à la saisie.

⚠️ **La commande n'inscrit rien.** Elle affiche ; c'est à la lecture de décider,
puis `--changelog-reviewed`. Poser le marqueur automatiquement rejouerait
exactement le piège de `--update` — dire « lu » d'un journal que personne n'a
ouvert.

Deux détails qui se voient à l'usage : le texte de l'API porte ses **entités
HTML** (sans `html.unescape`, `Span<int>` s'affiche `Span&lt;int&gt;`), et un mod
sans journal publié rend un objet vide — dit explicitement, plutôt qu'une ligne
muette qu'on lirait comme une panne.

Et l'on garde la mémoire de ce qu'on a lu : chaque source porte un
`changelog_reviewed` dans la référence ; le script compare la version relevée à
cette valeur et **rappelle** l'écart.

Trois propriétés, toutes vérifiées par sabotage le 2026-09-14 :

- le rappel **ne rend pas le script rouge** (sortie 0) — un changelog non lu
  n'est ni un écart de source ni une panne de script, et rougir en permanence
  tuerait le signal ;
- `--update` **ne peut pas** poser ce champ : il le recopie tel quel. C'était le
  vrai danger — le réflexe « la version a bougé → `--update` » aurait estampillé
  « changelog lu » sur un journal que personne n'a ouvert, et le rappel ne serait
  jamais reparti. Seul `--changelog-reviewed` l'écrit ;
- le champ est **exclu de la comparaison** : sans ça, prendre une note comptait
  comme un écart de la source (défaut trouvé par le test, pas par la relecture).

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

### 2.2 bis SMAPI — la liste noire des mods **malveillants**

| | |
|---|---|
| **URL** | `https://smapi.io/SMAPI.blacklist.json` |
| **Rôle** | les mods que SMAPI refuse de charger parce qu'ils sont piégés |
| **Code** | `StarHubTH/Models/SmapiBlacklist.swift` |
| **Relevé** | `smapi/blacklist` dans `check_sources.py` |

⚠️ **Ne pas confondre avec `mods.jsonc` (§2.2).** Celui-là porte les
*incompatibilités* ; celui-ci parle de **code hostile** — ses messages disent
« downloads malicious code from a remote server and runs it on your computer »,
et plusieurs entrées sont des **reuploads piégés de mods légitimes**, le cas
qu'un joueur ne distingue pas à l'œil sur Nexus.

Deux sections, relevées le 2026-09-15 (HTTP 200, 5 029 octets), re-relevées le
2026-09-23 :

| Section | Clé | Compte | Croisé au parc (1 112 manifestes) |
|---|---|---:|---|
| `Blacklist` | `Id` = `UniqueID` du manifeste | **16** *(9 le 2026-09-15)* | **0 correspondance** |
| `LooseFileBlacklist` | `Name` + `Hash` (MD5) | 1 | **0** — et aucun `.bat` du tout |

La hausse de septembre porte la liste à 16 : **10 entrées datées 2026-09**, dont
**4 d'un même auteur** (`StardewLabs.*`) — plus une campagne qu'un mod isolé,
toutes sur le même motif (« downloads malicious code from a remote server and
runs it on your computer »). Croisé au parc le 2026-09-23 : toujours
**0 correspondance**.

Trois décisions que ce document doit porter, parce qu'elles ne se déduisent pas
du code :

1. **Le croisement ignore la casse**, à l'inverse de §2.2 où la comparaison
   stricte a été mesurée sans effet. SMAPI compare les identifiants **sans** la
   casse : un reupload déclarant `opularenous.portablecommunitycenter` serait
   refusé par le jeu tout en passant pour sain chez nous. Une liste de sécurité
   doit être au moins aussi large que celle qu'elle relaie.
2. **Un document illisible rend `nil`, jamais une liste vide.** « Aucun mod
   malveillant » et « je n'ai pas su lire » ne sont pas la même chose, et les
   confondre afficherait un parc sain sur une ignorance. Même règle de cache
   qu'en §2.2 : on n'écrase le cache que par un corps qu'on sait décoder.
3. **Le `LooseFileBlacklist` est traité**, ce que sa forme rend abordable : le
   **nom** sert de grille de tri (un seul surveillé aujourd'hui), et seule
   l'**empreinte** condamne. Hacher le parc entier serait hors de question ;
   hacher les fichiers d'un nom donné ne coûte rien. Un fichier innocent qui
   porte le nom reste innocent.

⚠️ **Jamais de suppression automatique.** L'`UniqueID` est déclaratif — un mod
peut usurper celui d'un autre. On avertit, l'utilisateur agit.

⚠️ **Format en transition (SMAPI `d6f868e`, 2026-09-28).** SMAPI a retiré
`SMAPI.blacklist.json` de son dépôt : smapi.io le **génère** désormais à partir
d'une liste interne (`Pathoschild/StardewMalwareScanner.Data`,
`data/malware-blacklist.json`, branche `nightly` — dépôt **privé**, 404 pour
nous) par `MalwareBlacklistConverter`. Le document public garde ses deux
sections, mais la forme générée permet ce que notre décodeur ne lit pas :

- une entrée `Blacklist` **sans `Id`**, reconnue par la seule empreinte MD5 du
  DLL d'entrée (`EntryDllHash`) — SMAPI (`ModBlacklist.CheckMod`) la vérifie
  contre **tout** mod ; `SmapiBlacklist.decode` l'écarte en silence (garde
  `Id` non vide) ;
- une entrée `Id` + `EntryDllHash` : SMAPI exige **les deux** ; nous
  condamnerions sur l'`Id` seul (plus large, acceptable pour un avertissement) ;
- une entrée `LooseFileBlacklist` par **extension** seule (`".scr"`) ou nom
  seul : SMAPI teste chaque champ présent ; nous exigeons `Name` **et** `Hash`
  et l'écartons en silence.

Relevé le 2026-09-29 : la ressource servie est encore l'ancien JSONC commenté
(18 `Id`, aucun `EntryDllHash` ni `Extension`) — le convertisseur n'est pas
déployé. Aucun des 18 `Id` n'est au parc. **Lu depuis X116 (2026-09-29)** :
chaque champ est décodé et jugé selon les règles de SMAPI
(`SmapiBlacklistScan`) ; seules les entrées de fichier par empreinte seule
restent non vérifiées — comptées et dites au journal. Depuis X118, seuls
les mods changés depuis leur dernière vérification se relisent (registre
`smapi-blacklist-scan.json`, relecture complète si la liste change).

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
| **Rôle** | la recherche de mods, la vitrine Découverte, le repli de la fiche (A3-T7 : description + `modFiles.changelogText`, **seul appel parti sans clé**) |
| **Code** | `StarHubTH/NexusSearchClient.swift`, `Models/NexusModDetailV2.swift` (fiche) ; lien « requis par » et relecture par lots : `Models/NexusTranslationLinks.swift`, `FrenchTranslationLookup.swift` (C5-T1) |
| **À savoir** | le filtre est un tag `French`, pas une catégorie. `ModsFilter` porte 27 champs, dont `categoryName` et `languageName` |
| **Sans jeton** | **faux, ce que disait cette ligne** (mesuré le 2026-09-24) : introspection, `mods(filter:…)` et `modRequirements` répondent sans clé, à condition d'envoyer un `User-Agent` — sans lui, Cloudflare rend 403. L'app garde la clé (quota, cohérence avec v1), sauf pour la fiche (A3-T7) |
| **Traductions d'un mod** | `modRequirements { modsRequiringThisMod(count:, offset:) { totalCount nodes { modId modName notes } } }` : les fiches qui déclarent le mod comme prérequis — les traductions en font partie, **sans champ de langue** (la langue se lit dans `modName`). La section « Translations » de la page web (langue → fiche) **n'est pas exposée** par le schéma (38 champs de `Mod`, aucun). Mesuré sur le parc : 176 mods traduisibles sans `fr.json`, 94 avec un id Nexus (87 distincts) ; **10** ont une traduction FR requérante, **toutes justes** ; la recherche nom + tag `French` en rend 11 dont **4 fausses**, et ses 7 justes sont déjà dans les 10. SVE (3753) : 756 requérants, 3 des 5 traductions FR de la page y figurent. ⚠️ **Le lien ne dit pas « traduction de ce mod »** : relu par l'app (Swift, API réelle), SVE rend 8 traductions FR liées dont 4 traduisent un **autre** mod qui requiert SVE, et le tag `French` seul fait passer pour traductions des mods écrits en français (3 requérants de T's Core). Règle livrée : tags `French`+`Translation` ou titre, puis « confirmée » seulement si le titre nomme le mod — sur le parc, 9 traductions liées, 8 confirmées. Les **packs** (17 candidats) n'ont jamais d'id Nexus au manifeste de tête : pour eux, recherche par nom seule |
| **Sonde** | aucune |

### 2.4 bis Nexus Mods — manifestes de fichiers *(A1-T11, 2026-09-27)*

| | |
|---|---|
| **Liste** | `modFiles(modId:, gameId: 1303) { fileId version uri date }` (GraphQL v2, **sans clé**) |
| **Format récent** | `https://mod-file-manifests.nexusmods.com/<uri>` quand l'`uri` est en `xx/yy/zz/<uuid>` — chemins **et SHA-256** de chaque fichier, empreinte de l'archive et de sa version reconditionnée |
| **Format ancien** | `https://file-metadata.nexusmods.com/file/nexus-files-s3-meta/1303/<modId>/<uri encodée>.json` quand l'`uri` est le nom du fichier stocké — arbre de **chemins seuls**, tailles arrondies (`578.6 kB`, unité non prouvée). Très vieux fichiers : 404 HTML. Lu par l'app depuis A1-T11 plan 2, **seulement** pour « Nettoyer les anciens fichiers » (`includeLegacy`), jamais pendant une mise à jour ; mesure du 2026-09-28 : seule référence de la version installée pour 58 % des mods Nexus du parc (585 sur 1 004) |
| **Rôle** | la mise à jour reconnaît les fichiers qu'un auteur a retirés (identiques à une ancienne version) ; le nettoyage (plan 2) lit aussi l'ancien format |
| **Code** | `StarHubTH/Models/NexusFileManifestFetcher.swift`, `NexusFileManifest.swift`, `NexusRequestBuilder.makeManifestRequest` |
| **Relevé** | `nexus/manifestes-fichiers` dans `check_sources.py` |

Mesuré le 2026-09-27 :

- manifeste Wildroot 1.4.2 (fichier 184199) contre l'archive réelle : 289
  fichiers des deux côtés, **0 empreinte différente** ; l'empreinte de
  l'archive gardée dans `NexusArchives/` est celle du manifeste ;
- sur 60 mods du parc tirés au hasard (761 avec un id Nexus), **version
  installée** : 27 % au format récent, 67 % à l'ancien, 7 % introuvables en
  chaînes (`1.1` contre `1.1.0` — `NexusUpdateChecker.compare` les retrouve) ;
  42 pages sur 60 n'ont aucun fichier récent ;
- ⚠️ **User-Agent** : celui de Python par défaut reçoit 403, celui de l'app
  et de `check_sources.py` 200 ;
- ⚠️ l'`uri` ancienne porte espaces et parenthèses : **l'encoder**. Un `curl`
  non encodé échoue avant connexion (`000`) — pris un moment pour un blocage
  du CDN, c'était le script.

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
- `api.github.com/repos/mrbabilo/StarHubFR/releases/latest` — la détection de
  mise à jour de l'app elle-même (`StarHubTHViewModel.checkForAppRelease`,
  décision en `Models/AppReleaseCheck.swift`). **Le fork, jamais l'upstream** :
  interroger AppleBoiy/StarHubTH proposerait ses releases, pas les nôtres.
  `/releases/latest` exclut déjà drafts et prereleases côté GitHub ; le check
  est throttlé à 24 h.

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
| [**Profiler**](https://github.com/SinZ163/StardewMods/tree/main/Profiler) — SinZ | MIT | minuteurs de trame par postfix sur `DebugTimings.Start/Stop{Draw,Update}Timer`, pauses GC par `EventListener` du runtime .NET (`TimingMetrics.cs`, `GcEventListener.cs`) | `companion/StarHubFR.Probe/` (`FrameTimings.cs`, `GcPauses.cs`, licence dans `LICENSE-THIRD-PARTY.md`) |

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
| [**JuniGrid**](https://www.nexusmods.com/stardewvalley/mods/53227) — MLD210 ([source](https://github.com/MLD-yu/JuniGrid)) | C# + interface WebView2, Windows seul, EN/ZH ; dépôt créé le 2026-09-02, v1.2.4 sur Nexus le 2026-10-01, 3 ★, **très actif** | [`audit-junigrid.md`](audit-junigrid.md) (2026-10-01) : **OAuth Nexus exigé pour une app publique** (politique API), reprise des téléchargements, étiquette neutre pour un remplacement déjà fait. **Ne pas porter** la réécriture du `Version` des manifestes ni le « zip présent = installé » |
| [**Nexus Mods App**](https://nexus-mods.github.io/NexusMods.App/developers/) | officiel, Rust/C# | documentation du protocole `nxm://` et des collections |
| [node-nexus-api](https://github.com/Nexus-Mods/node-nexus-api) | client officiel Node | forme des réponses de l'API v1 |
| [**Keybind Radar**](https://www.nexusmods.com/stardewvalley/mods/52710) — Wooa | mod SMAPI en jeu (`wooa.KeybindRadar`), 2026-09-22 | radar de raccourcis & conflits — recouvre l'axe C4. Décompilé : [`audit-keybind-radar-savesaver.md`](audit-keybind-radar-savesaver.md) — notre `KeybindScanner` est plus riche (118 raccourcis sans indice de nom que son heuristique rate) |
| [**SaveSaver**](https://www.nexusmods.com/stardewvalley/mods/52709) — Sky | mod SMAPI en jeu (`Sky.SaveSaver`), 2026-09-22 | sanitation de sauvegardes au chargement (types orphelins, ErrorItems). Décompilé : même audit — ses backups vivent **dans son dossier de mod** (classe §6, et non régénérables) |
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
6. **v1.10.3** (2026-09-15, notes lues le 2026-09-23) : groupement de mods
   localisé, réparation de téléchargements de **collections** (caractères
   invalides) et de la colonne Enabled — UI de grille et collections ; rien à
   porter chez nous.

### JuniGrid — relevé du 2026-10-01

Lu depuis la description Nexus (API GraphQL v2, `legacyMods`, sans clé) et
les métadonnées du dépôt ; **code audité le même jour** :
[`audit-junigrid.md`](audit-junigrid.md). Ce qui touche nos axes :

| JuniGrid | Chez nous |
|---|---|
| Connexion Nexus par **OAuth** (application enregistrée) : aucune clé API à coller | clé API personnelle (`NexusAccountStore`). Piste ouverte, pas une dette : l'OAuth exige d'enregistrer l'app auprès de Nexus |
| Mise à jour jugée contre le **fichier installé** (file ID + version), pas le seul manifeste | aligné — manifestes de fichiers et triage (A1-T11, §2.4 bis) |
| Statut « plus maintenu » avec lien vers la **vraie** version de remplacement, silence si on l'a déjà | aligné — `unofficialUpdate` (X56) et `CompatibilityResolution` (le verdict smapi.io ignore la version installée) |
| Avis dédié pour une dépendance **installée mais désactivée** | aligné — `ModDependencyStatus`, `ModAnomaly` |
| Traductions en **surcouche** : chaque fichier remplacé sauvegardé, bascule et restauration fichier par fichier | voisin — hub FR en place avec fichier compagnon (C3) ; la restauration **par fichier** est à comparer avant tout portage |
| Installation de SMAPI depuis Nexus, **boîte de commandes** vers la console du jeu en cours | installateur SMAPI oui ; envoi de commandes console, non |
| Outils de portraits (packs saisonniers) | hors périmètre |

Embarque DepotDownloader (GPL v2), WebView2, XNA 4.0 redistribuable et le
runtime .NET : rien de cela ne nous concerne (macOS, pas de Steam en direct).

### Deux mods qui recouvrent nos axes — Keybind Radar et SaveSaver *(2026-09-23)*

Tous deux parus le 2026-09-22, tous deux **en pause sur le parc**, décompilés
et audités dans [`audit-keybind-radar-savesaver.md`](audit-keybind-radar-savesaver.md).
Ce qu'il faut en retenir ici, au-delà du verdict de l'audit :

- **SaveSaver ne déclare aucun `UpdateKeys`** : ni SMAPI, ni smapi.io, ni notre
  vérificateur ne sauront qu'une mise à jour existe. La sonde
  `mod/savesaver` restera muette — état relevé, pas alerte.
- **Ses backups de sauvegardes vivent dans son dossier de mod** — la classe
  « données runtime dans le dossier » du §6 (cas MCM), aggravée : une
  sauvegarde n'est pas régénérable. Notre `.overwriteWithBackup` détruirait le
  dossier à une mise à jour ; le snapshot `beforeUpdate` le conserve, à
  surveiller pareil.
- **L'empreinte des mods dans les saves ne passe pas seulement par des types
  C#** (ce que SaveSaver voit) : mesuré sur la sauvegarde maison Zofia,
  457 identifiants namespacés — ~133 nœuds `Lumisteria.MtVapius` dont le mod
  est **absent du parc**, 757 objets `Morghoula.Alchemistry` dont le mod est
  **en pause**. Notre bascule pause crée donc le scénario SaveSaver sans le
  dire ; l'idée d'intégration n° 1 de l'audit en découle.

### Trois deltas décompilés — Keybind Radar 1.0.1, UltraSmooth 2.3.6, Radiance 2.2.0 *(2026-09-24)*

Nouvelle DLL prise dans le dossier du jeu, ancienne dans le backup
d'installation de l'app (`Backups/ModInstalls/backups/<date>_install_backup/`),
les deux passées à `ilspycmd` et comparées. **Contrôle de sécurité** (réseau,
process, chargement de code, `DllImport`) : aucun motif nouveau dans les trois
deltas. Les motifs préexistants sont bénins : UltraSmooth règle le tampon des
sockets du multijoueur (`CoopSocketBufferSizeKb`) et interroge l'affichage
(`SDL2`, `user32` sous Windows).

- **Keybind Radar 1.0.1** — le signal en direct accepte désormais les boutons
  **manette** en plus du clavier (`IsLiveConflictButton` : `TryGetKeyboard` ou
  `TryGetController`) ; un modificateur seul n'alerte pas. La comparaison
  porte sur **toutes** les entrées du radar, pas les seules collisions,
  l'entrée en cours d'édition exclue, égalité exacte d'ensembles par
  alternative (`EntryUsesButtons`) — la même sémantique que C4-T12, à ceci
  près que les autres réglages du même mod comptent chez eux (écarté chez
  nous, 2026-09-24). Toujours accroché à GMCM par son namespace
  (`GenericModConfigMenu`) et seulement quand GMCM a été ouvert **depuis le
  radar** (`RadarToRestore`) : mort avec Modern Config Menu, comme en 1.0.0.
  Ajouts : bouton Refresh, `RefreshMod` après retour de GMCM, coupe-circuit
  sur erreurs répétées.
- **UltraSmooth 2.3.6** — le patch Harmony `Game1.DrawWorld` (« 5-Axis
  telemetry boundary » : dos, bâtiments, entités, devant, flush) n'est plus
  posé ; la ligne de journal correspondante disparaît. **Les cinq sections du
  rapport `us_trace` sont identiques** à la 2.3.5 : D2-T2 n'est pas touché.
  Clés `config.*` (194) et feuilles de `config.json` (66) inchangées.
- **Radiance 2.2.0** — +19 libellés `config.*`, dont des libellés **par
  valeur** de liste (`config.sheetupscalekernel.epx|mmpx|mmpxedgeguarded|xbr`)
  que notre `ConfigLabelResolver` ne lit pas (il ne connaît que
  `name|description|tooltip|…`) : la liste s'afficherait en jetons bruts. Le
  `config.json` du parc (282 feuilles) n'a pas encore été réécrit par la
  2.2.0 — les options neuves n'apparaîtront qu'après un lancement du jeu. Le
  rapport `radiance_report` gagne une ligne (« memory asked of the collector
  per frame, KB »), format autrement stable.

### Stardropium — un mod de performances qui patche les autres *(2026-09-25)*

Paru le 2026-09-25 (Nexus 52803, sources sur GitHub), **en pause sur le
parc**, audité dans [`audit-stardropium.md`](audit-stardropium.md). À retenir
ici :

- **Sans `UpdateKeys`**, comme SaveSaver : smapi.io le connaît quand on lui
  passe l'identifiant (0.1.1 relevé), SMAPI et notre vérificateur non.
- **Couplage de versions non déclaré** : 16 modules patchent des types
  internes d'autres mods par leur nom ; un type disparu éteint le module sans
  journal. Sonde `mod/stardropium-src` : suivre les **commits** — le premier
  correctif, le jour de la parution, a retiré un module entier.
- **7 méthodes patchées en commun avec UltraSmooth** (culling des
  `TerrainFeature`, `getTimeOfDayString`, `NPC.update`) et le même réglage
  du tampon réseau : premier cas mesuré de deux mods de performance actifs
  qui se recouvrent au niveau Harmony.
- **Il saute des écritures de Farm Type Manager** (`_SaveData.save` quand
  `SavedObjects` est vide, alors que le fichier porte aussi `LNOSCounter`) :
  l'état de la veille reste sur le disque.
- **Ligne de journal quotidienne** `[Morning Memory Optimizer (Background)]
  RAM: a MB -> b MB (Managed Heap: …)` : candidate pour D2.

### Relevé du 2026-09-25 — quatre mods, Stardrop

Les changelogs ci-dessous viennent de l'**API Nexus v2 sans clé** :
`modFiles(modId, gameId: 1303) { version date changelogText }` rend le
journal de chaque fichier. Le §1 disait qu'aucun script ne lit les
changelogs Nexus ; c'est faux pour la v2 (mesuré sur les quatre mods) —
`--fetch-changelogs` passe par elle depuis F9.

- **Modern Config Menu 2.1.7** — installé sur le parc, **décompilé et
  comparé** à la 2.1.6 du backup d'installation : 7 fichiers d'interface
  (bouton `[×]` dans la recherche, retour arrière des claviers virtuels).
  Aucune E/S, aucun réseau, aucune ligne de journal ajoutée ; `i18n/` et
  `data/` identiques.
- **UltraSmooth 2.3.7** — installé sur le parc, **décompilé et comparé** à
  la 2.3.6 du backup d'installation (2026-09-26). « Stripped out all tick
  stage profilers and telemetry logging » vise `EnableRenderTelemetry` et
  quelques clés de réglage retirées du `config.json`, **pas `us_trace`** :
  `LagTraceRecorder` est toujours là, même nom de fichier
  (`UltraSmooth_TraceReport_*.txt` dans le dossier du mod), mêmes sections.
  Un seul changement de format : la ligne `Game Time: … | Location: …` de
  chaque pic peut finir par ` | Menu: <menu>` et/ou ` | Weather: <météo>`. Le
  parseur de D2-T2 doit accepter ces suffixes optionnels. Aucune nouvelle E/S
  ni réseau. Nouveautés : `JitPrewarmer` et `SafeWindowMemoryManager` (actifs
  par défaut), et une section Experimental (`EnableExperimentalFeatures`,
  **désactivée par défaut**) qui ne pose ses patches qu'une fois activée :
  `GameLocation.passTimeForObjects`, `performTenMinuteUpdate`, `timeUpdate`,
  `Object.minutesElapsed`, `MinutesUntilReady`, `checkForAction`,
  `PathFindController.findPathForNPCSchedules` (à compter pour A5-T7). i18n :
  +36 clés `config.*` (194 → 230), et le `fr.json` de l'auteur (inchangé) en
  laisse maintenant 113 sans traduction, contre 77. Le `config.json` du parc
  ne sera réécrit qu'au prochain lancement du jeu.
- **Radiance 2.2.1** — changelog seul, pas encore installé : réglages neufs
  (herbe au vent, ombres aux pieds), traduction chinoise complétée ; rien qui
  touche nos lecteurs.
- **Event Studio 1.0.0-rc.1/rc.2** — changelog seul, en pause sur le parc :
  ses exports Content Patcher rangent désormais les évènements dans
  `events/<lieu>.json` appelés par `Include` — la forme que suit A5-T4.
- **Stardrop** — `pushed_at` a bougé sans code : dernier commit le
  2026-09-23 (v1.10.4 : dossier de collection créé au démarrage, traduction
  chinoise). Rien pour nous.

---

### Relevé du 2026-09-29 — six mods, SMAPI, la liste noire

Changelogs lus par `--fetch-changelogs` ; les quatre DLL fermées **décompilées
et comparées** à la version précédente du backup d'installation. Aucune
nouvelle surface réseau, process, chargement de code ni suppression de
fichier dans les cinq DLL (motif `HttpClient|Process.Start|Assembly.Load|
DllImport|File.Delete…` compté avant/après) ; seul ajout : Modern Config Menu
lit quatre variables d'environnement (`CINDERBOX`, `ANDROID_ROOT`,
`ANDROID_DATA`, `SteamDeck`) pour détecter la plateforme.

- **UltraSmooth 2.3.8 → 2.3.9** — 3 fichiers (`ProfilerEngine`,
  `HighFpsPacingEngine`, `DialoguePacingEngine`), 70 cibles Harmony avant et
  après. **Touche D4-T4** : en mode `Enhanced60` sur un écran ≤ 60 Hz, il passe
  le jeu en **pas variable** (`IsFixedTimeStep = false`) ; au-delà de 60 Hz il
  garde le pas fixe à 60. En pas variable, les ticks SMAPI suivent les trames :
  la conversion ms/s → ms par tick de `ProbeAnalysis` (÷ 60) n'est exacte
  qu'à 60 ticks/s — la cadence mesurée (`Tick.Count / WallSeconds`) serait
  juste (**X117**). Nouvelle ligne de journal : `UltraSmooth: 60 FPS Enhanced mode active
  on <Hz>Hz display (…)`. i18n inchangé (230 `config.*`, 113 sans `fr`).
- **UltraSmooth 2.3.9 → 2.4.0** *(2026-09-29)* — 5 fichiers (`HighFpsPacingEngine`,
  `DialoguePacingEngine`, `MinigamePacingEngine`, `ProjectileOptimizer`,
  `UiOverlaySmoother`) : le temps fixe de 16,6667 ms des mises à jour cadencées
  devient `GetPacedGameTime(time)`, actif seulement en pas variable. `ModConfig`
  inchangé ; surfaces réseau / processus / chargement de code / suppression
  identiques. Pourquoi il fait chuter les FPS du parc (spirale de rattrapage,
  ~15 ms ajoutées au dessin) et l'option « Profilateur » mal traduite :
  [`audit-ultrasmooth-2.4.0.md`](audit-ultrasmooth-2.4.0.md).
- **Modern Config Menu 2.1.8 → 2.2.1** — 13 fichiers d'interface, deux neufs
  (`VirtualKeyboardMode`, `ModernVirtualKeyboardModal`). Deux réglages neufs
  dans son `config.json` : `VirtualKeyboard` (Auto/Always/Never) et
  `FullscreenMode`. i18n 187 → 196 clés, 16 sans `fr`.
- **Modern Config Menu 2.2.1 → 2.2.4** *(2026-10-01, décompilé et diffé, 795 lignes)* —
  10 fichiers, aucun neuf ; aucune API réseau, processus, fichier ou
  chargement de code nouvelle. **Raccourcis** : le format écrit ne change pas
  (`KeybindList` de SMAPI), mais un modificateur n'est plus validé seul — MCM
  écrit désormais de vraies combinaisons (`LeftControl + R`), que
  `KeybindGrammar` lit déjà (tests `LeftControl + F8`/`+ H`). Retour arrière
  touche par touche (Retour/Suppr). Redirection GMCM en priorité 800
  (`OpenListMenu`/`OpenModMenu`). Réglage neuf `SeamlessTouchNavigation`
  (défaut `false`, tactile seulement). i18n de l'archive 196 → 198 clés.
- **Radiance 2.2.2 → 2.2.3** — 18 fichiers, trois neufs (`ArtReloads`,
  `BoundTargets`, `SettingsLog`). **Ligne de journal à parser (D2)** :
  `settings (<moment>): <N> changed from default: clé:valeur, …`, au niveau
  **Trace** (fichier journal seulement), au chargement d'une partie et à la
  fermeture de ses réglages — l'état de Radiance derrière un journal envoyé.
  i18n 1 105 → 1 109 (554 → 556 `config.*`), 133 sans `fr`.
- **Stardropium 0.1.4-beta → 0.1.5-Alpha-Hotfix1** — module
  `WaterTileOptimization` retiré (patch de `GameLocation.isWaterTile`), et le
  patch de l'interne Content Patcher `ContextualState.MergeFrom` supprimé
  (48 → 47 cibles). Ni l'un ni l'autre ne figure au catalogue A5-T7 : rien à
  corriger.
- **Stardropium 0.1.5-Alpha-Hotfix1 → 0.2.0-beta** *(2026-10-01)* — détail et
  verdict : [`audit-stardropium.md`](audit-stardropium.md) § 6. **Défaut sur le
  parc** : la réécriture de `GameLocation.passTimeForObjects` (active par
  défaut) n'appelle plus `minutesElapsed` sur un objet simple sans
  `heldObject` hors de 4 identifiants vanilla — le postfix de Sword and
  Sorcery qui fait expirer `DN.SnS_WallOfForce` ne tourne plus.
  Avant de réactiver : `EnableTenMinuteObjectPassTimeOptimization: false`.
- **Event Studio rc.3 → rc.4** — pas de backup de la rc.3 (installée hors
  app) : audit de la rc.4 seule, **aucune** occurrence du motif. Changelog :
  alignement des sprites HD dans l'éditeur.
- **UI Framework 1.8.0 → 1.8.1** — source ouverte, 6 commits : `MenuHost`
  libère ses menus quand un autre mod ouvre le sien par-dessus ; le manifeste
  porte enfin `UpdateKeys: ["Nexus:52945"]` (smapi.io et notre vérificateur
  le suivent désormais).
- **SMAPI `f090df0 → d6f868e`** — un commit : migration de la liste noire
  (voir §2.2 bis).

### Relevé du 2026-10-01 — trois mods, deux dépôts

Les trois DLL ont été décompilées et comparées à la version précédente du
backup d'installation. Aucune nouvelle surface réseau, processus, chargement
de code ni suppression de fichier (motif compté avant/après).

- **UltraSmooth 2.4.0 → 2.4.1** — 11 fichiers neufs, `Experimental.Pathfinding`
  retiré, 14 réglages neufs. **Défaut grave, actif par défaut** :
  `EnableParallelDayUpdate` lance `GameLocation.DayUpdate` sur plusieurs fils.
  Le corps propre de `Town`, `Forest`, `Beach`, `Farm`… s'exécute alors deux
  fois par nuit (la rénovation de Pam arrive deux fois plus vite,
  `VisitsUntilY1Guarantee` est décrémenté deux fois dans la sauvegarde).
  Jamais exécuté sur le parc : le mod est en pause. Avant de le réactiver :
  `"EnableParallelDayUpdate": false`. Catalogue A5-T7 : `LightSource.Draw`
  est une 13ᵉ méthode commune avec Stardropium. `findPathForNPCSchedules`
  dépend maintenant d'`EnableRouteCache`, plus d'`EnableExperimentalFeatures`.
  Détail, autres optimiseurs (préchauffage de saison hors du fil du jeu,
  hibernation d'Automate) : [`audit-ultrasmooth-2.4.1.md`](audit-ultrasmooth-2.4.1.md).
- **Modern Config Menu 2.2.4 → 2.2.5** — 9 fichiers, aucun neuf.
  Le bouton `[+]` écrit des raccourcis alternatifs séparés par une virgule
  (`F8, ControllerBack`) : `KeybindParser` les lit déjà (test `"F8, K"`).
  Réglage neuf `UseVanillaFont`. i18n 198 → 201 clés, 21 sans `fr`.
- **Keybind Radar 1.0.1 → 1.0.2** — sans changelog sur Nexus. Un fichier :
  le bouton d'ouverture de GMCM est grisé sur l'écran titre (clé i18n
  `gmcm.open.button.title-unavailable`).
- **i18n-translator `8322bac → 1f1a622`** — un commit : liste des modèles
  ChatGPT dans les réglages. Jetons protégés et garanties d'écriture
  inchangés.
- **UI Framework (source) `57b4888 → 432fb6a`** — `UIFrameworkDesigner`, un
  éditeur web de menus avec générateur de métadonnées : une future source du
  schéma `Bind`. Rien ne change dans le `Bind` de `StardewUIFramework/Data`.

### La visionneuse de Profiler — `stardew.361zn.is` *(2026-09-29)*

« Stardew Utilities », de SinZ (l'auteur de **Profiler**) : une application
React **entièrement locale**. On glisse un journal SMAPI sur la page, elle le
lit dans le navigateur (`File.stream()`), sans rien envoyer. Aucune API, aucun
paramètre d'URL pour lui passer un journal : **inexploitable comme service**
par l'app — au mieux un lien « ouvrir l'analyseur » et le journal montré dans
le Finder, à glisser à la main.

Ce que son code (`js/main.js`, relu le 2026-09-29) établit :
- elle garde les messages `ModName === "Profiler"`, niveau **TRACE**, qui
  commencent par `[RawLog] ` ; le reste de la ligne est un JSON :
  `OccuredAt`, `Metadata { Type: "Duration", ModId, EventType, Details,
  Duration, InnerDetails[] }` — `InnerDetails` porte les appels imbriqués,
  même forme, récursive. C'est la forme que **D1-T2** doit parser ;
- elle lit aussi le format JSON des journaux partagés par smapi.io (le
  fichier commence par `{"IsValid":true`) ;
- trois onglets : « Log Viewer », « Profiler Analysis (Column Chart) » (barres
  imbriquées sur l'axe du temps), « Log Graphs » annoncé, pas livré.

Pour nous : **pas une source de la mesure guidée** (sous-projet D5-A) —
Profiler et la sonde s'excluent dans une même session (incompatibilité connue,
`KnownIncompatibilities`), et la sonde mesure déjà le coût par mod et par
événement, sans le seuil de Profiler.

**Session Profiler seul du 2026-09-29 (22:49, sonde en pause, 140 mods +
146 packs)** — journal conservé sous
`~/Library/Application Support/StarHubFR/ProfilerLogs/SMAPI-profiler-seul-2026-09-29.txt`
(celui du 2026-09-26 cité par D1-T2 a disparu du disque). Ce qu'elle établit :
- Profiler **ne chronomètre pas l'`Entry`** des mods : son `Init` arrive à la
  fin de la phase « Launching mods » (22:49:31 → 22:49:53, 22 s d'`Entry`
  cumulés), qu'il ne voit donc pas. Cette phase ne se lit qu'en bloc, à la
  seconde, par les horodatages SMAPI ;
- il pose des jalons de phase en `INFO` : `[t ms][Fast|Slow] Game Launched`,
  `LoadStageChanged A -> B` (None → SaveParsed → … → Ready), `Save Loaded`,
  `Day Started`, `Warped` — `Fast` au début des gestionnaires, `Slow` après
  le dernier ;
- ses `[RawLog]` imbriquent, sous les événements SMAPI, des nœuds
  `ApplyLoad` / `ApplyEdit` attribués **au pack de contenu** (`ModId` du
  pack, pas `Pathoschild.ContentPatcher`) : 5 727 nœuds sur la session. Le
  coût par pack pendant un chargement est donc lisible ;
- chiffres (temps propre, enfants soustraits) : lancement 51,7 s de
  gestionnaires, dont **Content Patcher 30,8 s** (27,3 s sur son premier
  `UpdateTicked`, qui ne se ventile pas par pack) ; chargement de sauvegarde
  63,0 s, dont **AutoForager 10,6 s** (≈ 1,1 s à chaque `Content.AssetReady`,
  9 fois), SVE 7,4 s en `ApplyLoad`, FTM 3,0 s au `DayStarted`. Ce sont des
  **minorants** : `config.json` de Profiler ne journalise un appel de tête
  qu'à partir de 5 ms (`LoggerDurationOuterThreshold`) et un appel imbriqué
  qu'à partir de 0,1 ms (`LoggerDurationInnerThreshold`). En chargement, où
  les gros appels dominent, l'écart est faible ; en jeu, il est complet.

**Le code source de Profiler** (SinZ163/StardewMods relu le 2026-09-29 ;
installé : **2.0.0**, dépôt : 3.0-alpha5 du 2025-09-30) :

- **Instrumentation** : un transpileur Harmony sur
  `ManagedEvent<TimeChangedEventArgs>.Raise` (les deux surcharges) — et c'est
  tout. Comme le corps générique de `Raise` est **partagé par le JIT** entre
  toutes les instanciations (types référence), ce patch unique chronomètre
  **tous** les événements SMAPI : chaque gestionnaire est enveloppé
  `Stopwatch` au `Push`/`TryPop` de la pile de `ProfilerAPI`, `ModId` vient
  du `SourceMod` du délégué. Élégant et fragile : si SMAPI déplace ou
  spécialise `Raise`, toute la mesure disparaît en silence ;
- **Écriture** : au `Pop` d'un événement racine, ligne TRACE
  `[RawLog] {OccuredAt, Metadata}` si la durée ≥ 5 ms ; sinon rejetée. Les
  enfants s'accrochent au `InnerDetails` du parent s'ils durent ≥ 0,1 ms
  (le flag `important` des événements `Trace` force l'écriture). Racine
  rejetée = **toute sa descendance perdue** : un appel englobant court
  masque des enfants qu'il contient ;
- **Seuils de lecture** (`[BigLoop]` n'est qu'un résumé) :
  `EventThreshold` 10 ms → ligne DEBUG par gestionnaire ;
  `BigLoopThreshold` 100 ms → résumé `[BigLoop]` ;
  `LoggerDuration*Threshold` → ce qui entre dans les `[RawLog]`.
  La **2.0.0 installée n'a aucun garde-fou de désynchronisation** (la pile
  qui déraille corrompt le nesting en silence ; le drain d'erreur
  « desync » n'existe qu'à partir de 2.1-alpha3) ni de flush de fin de
  session (les `Push` restés ouverts à la sortie sont perdus) — la session
  du 2026-09-29 ne montre aucune trace de déraillement ;
- **La 3.0-alpha5 ajoute** `TimingMetrics` (postfixes sur
  `DebugTimings.Start/Stop{Draw,Update}Timer` → `[RawMetrics]`
  `DrawTime`/`UpdateTime` par trame, `ModId` « Stardew Valley ») et
  `GcEventListener` (`EventListener` .NET sur le mot-clé GC → pauses en
  `[RawWaterfall]`, `ModId` « $CLR ») — les deux fonctions dont la sonde
  s'est inspirée (§3) et qui motivent l'incompatibilité déclarée avec elle.
  Ne pas mettre à jour Profiler pour D5-B : la 2.0.0 suffit et n'entre pas
  en collision avec la sonde ;
- **Jalons de phase** (`PlayerLogger`, double abonnement priorité
  max/min → paires `INFO [t][Fast]` / `[t][Slow]`) : `Game Launched`,
  `LoadStageChanged A -> B`, `Save Loaded`, `Day Started`, `Warped A -> B`.
  La session du 2026-09-29, 140 mods + 146 packs :
  `Launching mods` 22 s (l'`Entry`, invisible de Profiler — son `Init`
  tombe à la toute fin) ; `Game Launched` 4,6 s de gestionnaires ;
  clic → `SaveParsed` **≈ 11 s** (clic à 22:51:12, `gameMode` passé à
  `loadingMode (6)` puis `getLoadEnumerator` ; les 87 s entre `Game Launched`
  et `SaveParsed` comptent le temps passé au menu) ;
  `SaveParsed → SaveAddedLocations` **41,5 s** (le plus gros bloc natif) ;
  `→ SaveLoadedLocations` 12,1 s (les `ApplyLoad` de Content Patcher) ;
  `Loaded → Ready` 3,0 s ; `Save Loaded` 152,7 s après le lancement des
  gestionnaires ; `Day Started` +10,4 s ; premier warp
  FarmHouse → Farm +18,6 s. Ces spans sont la cible de D5-B : les
  reproduire sans Profiler, avec la sonde et les horodatages SMAPI.

**Deux coutures qu'utilise la sonde 0.6.0 (D5-B)** *(2026-09-30)* :
- Content Patcher 2.9.1 : `PatchManager.ApplyLoad<T>`/`ApplyEdits<T>`
  enveloppent chaque patch dans `Profiler?.RecordSection(packId,
  "ApplyLoad"|"ApplyEdit", path)` ; le champ `private readonly
  ProfilerIntegration? Profiler` est null sans `SinZ.Profiler`. La sonde le
  pose pendant les chargements et répond à `RecordSection`. Si Content
  Patcher renomme ce champ ou cette méthode : `PackSeam: missing` dans
  `loads.jsonl`, dit à l'écran.
- SMAPI 4.5.2 : `GameContentManager.ApplyLoader<T>`/`ApplyEditors<T>`
  entourent chaque rappel `LoadFrom`/`Edit` d'un
  `HeuristicModsRunningCode.Push`/`TryPop`, comme `ManagedEvent.Raise`.
  Garde : `AssetHook`.
  La boucle d'`Entry` de `SCore.LoadMods` : **sonde 0.8.0** — postfix posés
  dans le **constructeur** du mod (créé pendant la boucle de chargement,
  avant toute la boucle de démarrage) sur `SCore.ReloadTranslations
  (IEnumerable<IModMetadata>)` (départ) et `ModMetadata.SetApi` (fin de
  `Entry` + `GetApi` de chaque mod). Porte du 2026-10-01 : 1 et 140 appels
  sur 140 mods de code. Le jeu fixe `TieredCompilation: false`
  (`StardewModdingAPI.runtimeconfig.json`) : une petite méthode intégrée
  avant la sonde ne tirerait jamais — d'où ces deux accroches, pas
  `ModRegistry.Add`. Garde : `EntryHook`. **Deux limites de l'étape 1** :
  (1) un mod qui démarre **avant** la sonde a un coût `entry` **inclusif** —
  `ModCosts` n'est pas encore armé, les gestionnaires d'autres mods qui
  tournent pendant son `Entry` (un `AssetRequested` de Content Patcher, par
  exemple) lui sont imputés ; **levée quand la sonde est chargée en premier**
  (consentement, étape 2). (2) Le démarrage de la sonde elle-même est compté
  dans `EntryLoopMs` mais n'a pas de ligne : la somme des `entry` + coûts
  attribués reste en dessous de la boucle d'au moins ce temps-là.
  **Sonde 0.9.0** : prefix/postfix sur `SCore.TryLoadMod` (durée directe,
  `__result == false` = échec nommé « Load (échec) ») ; position lue dans
  `ModRegistry.GetAll()` (ordre de chargement) → `ProbeLoadsFirst`.
  `smapi-internal/config.user.json` : `ModsToLoadEarly` fusionné par
  `JsonConvert.PopulateObject` ; identifiant listé mais absent → WARN SMAPI à
  chaque lancement (`SCore.cs:401`) — l'app le retire quand la sonde est en
  pause, et n'écrit jamais sans consentement (copie
  `config.user.json.starhubfr.bak`). Garde : `ModLoadHook`.
  **Corrigé en 0.6.2** : transpiler ces deux méthodes **génériques** n'a
  rien attribué (deux sessions, zéro rappel) — Harmony ne détourne que
  l'instanciation `<object>`, les appels réels passent par le corps
  partagé. La sonde postfixe désormais `SCore.RequestAssetOperations`
  (non générique) et enveloppe les délégués `GetData`/`ApplyEdit` des
  opérations neuves de chaque requête. Validé en jeu le 2026-09-30 :
  ≈ 8 600 rappels vus par session, aucun hors du fil du jeu.

**Benchmark automatique (sonde 0.7.0)** *(2026-09-30)* :
- `benchmark-plan.json` (`Version`, `RunId`, `SaveName`, `ExpiresAt`),
  écrit **et effacé** par l'app seule ; la sonde ignore un plan illisible,
  d'une autre version ou expiré (10 min) — un lancement manuel n'est jamais
  détourné. Lignes `loads.jsonl` marquées `BenchmarkRun`.
- Chargement : `SaveGame.Load(slot)` puis `Game1.exitActiveMenu()` = le
  corps de `LoadGameMenu.SaveFileSlot.Activate` (1.6.15 décompilé). Sortie :
  `Game1.quit = true`, lu par `Game1._update`.
- Piège : `_update` rend la main **avant** `if (quit) Exit()` et avant
  l'avance du chargement quand la fenêtre est inactive et
  `options.pauseWhenOutOfFocus` vrai (défaut). La sonde le réaffirme à
  faux à chaque tick sous plan ; rien n'est persisté (`SaveGame` écrit
  `default_options` depuis les options de la sauvegarde, et une affectation
  directe ne marque pas `optionsDirty`).
- Jeu 1.6.15 : `SaveGame.Load(string)` public static pose
  `Game1.currentLoader = getLoadEnumerator(filename)` — c'est `S0`.

### Deux mods de temps de chargement décompilés — FastLoads 1.0.3 et Loading Optimizer 1.0.0 *(2026-09-29)*

Contribution au chantier **D5-B** : ce que deux mods dédiés au temps de
chargement font au jeu, et ce qu'on en retient pour nos mesures.

**FastLoads** (spajus, 1.0.3, [Nexus 19454](https://www.nexusmods.com/stardewvalley/mods/19454)
· `spajus.fastloads` · [source](https://github.com/spajus/stardew-valley-fast-loads),
dernier commit 2023-12) : 242 lignes, trois patches Harmony sur `NPC`.
`populateRoutesFromLocationToLocationList` est hashé dans un `HashSet<long>`
au postfix ; `doesRoutesListContain` est **remplacé** par un test O(1) sur ce
hash (l'original scannait la liste complète avec une égalité profonde par
candidat) ; `exploreWarpPoints` est **remplacé** par une reprise qui
dédoublonne au fil de l'eau. Preuve historique que le chargement d'une partie
passait un temps considérable à recalculer les routes de PNJ — et l'étiquette
Nexus « Broken in Version 1.6 » avec le mot de l'auteur (« le problème semble
corrigé dans le jeu ») disent que **1.6 a corrigé ce coût**. Le jeu du parc est
en 1.6.15 : **à ne jamais installer** — ses deux remplacements complets de
méthodes privées divergeraient du jeu. Sa valeur pour nous : D5-B ne doit pas
chercher ce coût sur 1.6, et son option `DetectCollisions` documente le risque
d'un index par hash (une collision rend une route fausse en silence). Aucune
clé `config.*` (libellés GMCM bruts).

**Stardew Loading Optimizer** (neoiw, 1.0.0 — décompilé depuis le parc,
`.StardewLoadingOptimizer/`, où il est **en pause**) : ~20 600 lignes
décompilées, dix services. Sur 1.6.15 :
- `SaveFileSlot` ctor postfix : `ActivateDelay = 0` — supprime le délai
  artificiel du menu de chargement de sauvegarde (−2,17 s revendiqués par le
  README) ; la chaîne de `SaveGame.Load` reste au jeu ;
- `TMXFormat.Load(Stream)` prefix/postfix : cache disque **des maps
  compilées** (`map-cache-v2`), clé `Longueur + LastWriteTime` du `.tmx`
  source, et réparation `UpdateDisplaySize` après un hit ;
- `ModContentManager.LoadRawImageData` (méthode interne de SMAPI) : cache
  des **images décodées** (BGRA) avec budget mémoire (384 Mo par défaut),
  décodage sur thread d'arrière-plan, jointure runtime bornée à 500 ms ;
- prélecture de fichiers (`.tmx/.tbin/.png/.json`) en arrière-plan après
  `SaveLoaded`, 24 Mo/s plafonnée à 256 Mo — **cache OS**, le jeu n'est pas
  modifié ;
- tilesheets différées pendant `loadForNewGame`, réchauffées 3 s plus tard ;
- SpaceCore : initialisation des sérialiseurs **parallélisée** + fast-path qui
  **réécrit en IL** les appels `DeserializeProxy<T>` de SpaceCore quand le
  sidecar (`spacecore-serialization.json`) confirme « aucune donnée custom » —
  le patch le plus fragile du mod : il dépend des internes d'un mod mis à
  jour souvent, et touche la lecture des sauvegardes (même famille de risque
  que le préchauffage SpaceCore d'UltraSmooth qui figeait l'enregistrement
  des types) ;
- warps accélérés (`ScreenFade.UpdateFadeAlpha`, multiplicateur 6,5×) ;
- **son propre profilé de chargement** : `NativeTimingProbe` instrumente
  ~30 méthodes natives (`SaveGame.Load`, `TryReadSaveFile`,
  `loadDataToFarmer`, `loadDataToLocations`, `GameLocation.loadMap`,
  `resetForPlayerEntry`, `WarpPathfindingCache.PopulateCache`,
  `Map.LoadTileSheets`, portées de Content Patcher…) + `ExitDiagnostics`
  à la sortie. **Désactivés par défaut** (`EnableDetailedDiagnostics=false`,
  réglage du parc). D5-B peut les activer comme contre-point d'une session ;
  leur liste de phases est une carte des étapes de chargement qui recoupe
  les jalons de Profiler ;
- `PrepareToUninstall=true` : retire tous ses patches et arrête ses workers —
  la propreté de désinstallation que le chantier D2 demande ;
- journal : une ligne `[OPTIMIZER CONFIG]` exhaustive au lancement, puis des
  statuts `[MAP CACHE STATUS]`, `[IMAGE CACHE STATUS]`, `[PREFETCH STATUS]`,
  `[SAVE PREFETCH …]`, `[NATIVE PHASE]`… à parser (chantier D2).

Risques notés à la lecture : ses caches se réparent en silence
(`[MAP CACHE DISPLAY REPAIR]`, `[IMAGE CACHE PRESSURE]` — les mêmes
« pertes silencieuses contre on gagne quoi » que notre A1-T8/T9 traitent
côté app) ; le parc le garde **en pause** — les mesures D5-B décrivent le
parc sans lui.

### Les outils de profilage .NET hors jeu *(2026-09-29)*

Complément des mods profilés ci-dessus — ce que l'écosystème .NET/macOS
apporte, et ses pièges :

- **`dotnet-counters monitor`** (`--name "Stardew Valley"`) : taux
  d'allocation et GC en direct. Le complément du **D5-C** — `GcEventListener`
  de la sonde voit les pauses, pas les taux ;
- **`dotnet-trace collect`** : call stacks managés, convertibles en
  `speedscope` (`--format speedscope`). Profile `--profile gc-collect` pour
  savoir qui alloue ;
- **Piège du nom de processus** : sur macOS, ce n'est pas
  `StardewModdingAPI` mais **« Stardew Valley »** — le binaire secondaire
  est rattaché au bundle par LaunchServices (sonde du 2026-09-24) ;
- **Piège de contamination** : tout outil attaché (EventPipe, Instruments)
  ajoute une surcharge supérieure au seuil de 5 % du verdict — **jamais
  pendant une mesure guidée** D5-A/D5-B. Diagnostic et mesure comparative
  vivent dans des sessions séparées ;
- **Instruments** (Xcode) : le seul outil qui descend sous le .NET —
  Time Profiler / CPU Counters / Metal pour le moteur natif (cas
  UltraSmooth, goulot GPU) ; trames JIT CoreCLR mélangées, aucune
  attribution par mod ;
- **samply** : équivalent zéro-config pour **l'app StarHubFR elle-même**
  (Swift natif, symboles complets) ;
- **Tracy** : exige d'instrumenter le code source du jeu — impossible, jeu
  fermé. **dotTrace** : payant, aucun besoin propre.

### Outils de traduction de mods *(2026-09-24)*

Relevés à la demande de l'utilisateur, pour le hub FR :

- **Transtar** (`wanniwa/transtar`, Python, **GPL-3.0**, Windows seulement ;
  code lu au commit `a47562c` = 3.0.5, plus récent que la release 3.0.0 du
  2025-12-26 — source ouverte, rien à décompiler) — extrait tout le texte
  affiché d'un mod (`i18n`, Content Patcher, JA, MFM, STF, QF) dans un dossier
  `dict`, le fait traduire (Google, DeepL, LLM), puis régénère un paquet. Étudié
  le 2026-09-24 pour **C3-T2** ; relever les règles, **ne pas recopier le code**.
  - **Détection des fichiers** (`file_util.get_target_type`) : par nom —
    `content.json` = CP, dossiers préfixés `[JA]`/`[BL]`… Tout est ouvert en
    `utf-8` strict : les i18n UTF-16/32 du parc le feraient échouer.
  - **Parcours CP** (`CpHandler.handle`) : `Include` suivi récursivement,
    `Load` d'un `.json` lu comme des entrées, `EditData` (sauf `TargetField`,
    ignoré), jetons `{{Random:…}}` dépliés, `DynamicTokens` substitués dans les
    chemins, `{{Language}}`/`{{Target}}`/`{{TargetWithoutPath}}` résolus. Un
    changement sous `When: {Language: X}` avec X ≠ langue source est **sauté** —
    c'est ce qui évite de compter un fichier déjà traduit.
  - **La table cible → champs affichés** (`TargetAssetType` + `traverse_editdata_entries`),
    le vrai savoir : chaînes entières pour `Characters/Dialogue/*`, `Strings/*`,
    `Data/Mail`, `Data/ExtraDialogue`… ; `DisplayName`/`Description` pour
    `Objects`, `BigCraftables`, `Weapons`, `Shirts`, `Pants` ; `DisplayName`
    (+ `Name`) pour `Locations`, `FruitTrees`, `Buildings` ; `FarmAnimals` 5
    champs (`ShopDisplayName`, `BirthText`…) ; `Characters.DisplayName` et
    `FriendsAndFamily` ; `Shops` → `Owners[].ClosedMessage` et
    `Dialogues[].Dialogue` ; `WorldMap` → `Tooltips[].Text`, `MapAreas[].ScrollText` ;
    `SpecialOrders` → `Objectives[].Text` ; `PassiveFestivals` → `DisplayName`,
    `StartMessage` ; `Minecarts` → `Destinations[].DisplayName` ; films →
    `SpecialResponses.*.Text` ; CJB Cheats Menu, UnlockableBundles. Les anciens
    formats à barres obliques 1.5 ont leurs index (`ObjectInformation` 4-5,
    `Quests` 1-3 et 9, `Hats` 1 et 5, `Furniture` 7, `NPCDispositions` 11…).
  - **Événements** : une regex (`speak`, `splitSpeak`, `textAboveHead`,
    `message`, `question`, `quickQuestion`, `end dialogue`) n'extrait que le
    texte entre guillemets ; une valeur qui porte déjà `i18n` est sautée.
  - **Défauts relevés** : `action.lower == "EditMap".lower()` (méthode comparée
    à une chaîne) — la branche `EditMap` (`SetProperties.Default/Failure`)
    ne s'exécute **jamais** ; `CraftingRecipes` est classé mais `deal_str` n'a
    pas de branche pour lui (`crafting_recipes()` jamais appelée) — ses noms ne
    sont jamais extraits ; la signature de jetons `trait()` compte
    `${…}` comme un jeton comparé à l'identique — le sélecteur de genre, que le
    français réécrit légitimement (mémoire `gender-selector-is-not-a-token`),
    y serait une erreur. Notre `TranslationTokens` reconnaît `%mot` + chiffres
    de façon générique, là où `trait()` énumère 17 substitutions.
  - **Contrôles de réponse d'IA** (`check/AdvancedChecks.py`) : nombre de lignes
    conservé, jetons présents, réponse identique à l'original (similarité de
    Jaccard), reste de texte source — idées pour le lot IA du hub.
  - **Mesure sur le parc** (136 packs CP actifs, règles ci-dessus, `Include`
    et `Load` suivis, changements `When: Language` sautés) : **4 800** chaînes
    affichées écrites en dur hors `{{i18n}}`, dont **4 092 déjà en français**
    (East Scarp, entre autres, a reçu une traduction qui écrit dans ses
    assets), **233 en anglais** et 475 indécidables (noms courts). Les 233
    anglaises tiennent dans **11 packs**, dont **192** dans un seul
    (`[NPC] Lucy Artifact Store`). Leçon pour C3-T2 : « en dur » ne veut pas
    dire « en anglais » — il faut juger la langue du texte, ce que Transtar ne
    fait pas.
- **Internationalization** (Nexus 21317, v0.6, 2026-05-10) — éditeur i18n servi
  **dans le jeu** sur `localhost:8018`, mise à jour à chaud. Notre hub édite hors
  jeu ; rien à reprendre, sinon l'idée du rechargement à chaud — que SMAPI offre
  déjà par sa commande console `reload_i18n`.
- **AutoTranslator** (Nexus 35031, v2.0.2, 2025-09-09) — traduction IA des i18n
  depuis le jeu (OpenAI, DeepSeek, Anthropic, Gemini), mises à jour
  incrémentales. Recouvre le hub (DeepL, IA locale) ; rien de neuf, la structure
  `i18n/default/` est déjà lue par `I18nLocaleResolver`.
- **Developer Tool — i18n Translator** (Nexus 21920) — déjà relevé : mémoire
  `stardew-i18n-translator-reference`.

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
| [**Modern Config Menu**](https://www.nexusmods.com/stardewvalley/mods/49437) — palmhacker13, 2.1.0 | `palmhacker13.ModernConfigMenu` · Nexus 49437 | la preuve que la convention survit à un changement de front : même i18n, autre UI. Sa 2.1.0 (changelog lu le 2026-09-10) écrit `data/mod_history.json` **dans son propre dossier** ; or notre mise à jour (`.overwriteWithBackup`) supprime le dossier avant réextraction, snapshot limité à `config.json` + `i18n/*.json` — ce fichier meurt. Regénérable (le mod redécouvre au lancement suivant), et l'ancien dossier entier reste dans la sauvegarde `beforeUpdate` : aucun changement de code, mais la **classe** « mod qui garde des données runtime dans son dossier » est à surveiller — un mod dont la donnée ne serait pas regénérable perdrait sur toute mise à jour StarHubFR. Journaux lus jusqu'à **2.1.6** (2026-09-23) : sa **2.1.3 rend les boutons souris M4/M5/M3 bindables** dans tous les champs raccourcis — les configs du parc vont porter des `MouseX1`/`MouseX2`/`MouseMiddle`, jetons que notre `SButtonTable` porte déjà (KeybindGrammar.swift) ; la 2.1.4 importe en plus les enregistrements GMCM **retardés** (Automate), que notre lecture statique des DLL voit de toute façon sans besoin de règle |
| [**UltraSmooth**](https://www.nexusmods.com/stardewvalley/mods/50971) — palmhacker13, 2.1.3 | `palmhacker13.UltraSmooth` · Nexus 50971 · dépend de MCM · **installé sur le parc** | **le corpus de test de l'éditeur** : 115 clés `config.*` (41 `.name`, 41 `.tooltip`, 11 `.button`, 16 de section, 4 `.choice`) plus une clé maison `.gmcmGuide` ; porte aussi un `i18n/th.json` (hub thaï). Perf : `us_analyze` est un **profil de soi** (top 5 de ses propres moteurs) ; l'outil profond est la boîte noire **`us_trace`** (60 s, rapport au journal SMAPI **et** fichier dans le dossier du mod) — aucun patch Harmony chez les autres mods. Audité : [`audit-perf-analyzers.md`](audit-perf-analyzers.md) |
| [**Faster Menu Load**](https://www.nexusmods.com/stardewvalley/mods/41564) — ZeroXPatch, 1.5.0 | `ZeroXPatch.FasterMenuLoad` · Nexus 41564 | même auteur que le SMAPILogDoctor crédité §3 ; une des 13 dépendances du SLO ; **seul des cinq non installé** sur le parc |
| [**Stardew Loading Optimizer**](https://www.nexusmods.com/stardewvalley/mods/50153) — neoiw, 1.0.0 (source : 0.5.0-rc.18) | `neoiw.StardewLoadingOptimizer` · Nexus 50153 | orchestrateur de 13 mods de performance ; son téléchargement « Source Code » est un **exemple complet d'intégration GMCM côté mod** (`GenericModConfigMenuIntegration.cs`). Sa 1.0.0 **décompilée le 2026-09-29** (analyse complète §5) : les 13 dépendances sont désormais `IsRequired: false` — le constat « manifeste intégriste » ci-dessous ne vaut plus que pour la 0.5.x auditée ; **en pause sur le parc** |
| [**SinZational Speedy Solutions**](https://www.nexusmods.com/stardewvalley/mods/37301) — SinZ, 1.1.0 | `SinZ.SpeedySolutions` · Nexus 37301 · **installé sur le parc** | membre de deux paires du catalogue des recouvrements de perf (A5-T7, `PerformanceOverlap.swift`) : `ModContentManager.LoadRawImageData` avec Loading Optimizer et Stardropium, `TMXFormat.Load` avec Loading Optimizer ; Stardropium patche aussi son propre postfix **Cache disque** (`cache/`, 979 fichiers, 121 Mo le 2026-09-30, options TBin/image toutes actives) : relevé stable d'une session à l'autre (886 cartes demandées, 199 en mémoire, les 5 mêmes cartes SVE recalculées à chaque fois). Son préfixe `TMXFormat.Load` porte le chargement des cartes lui-même (12,6 s en S1→S2), pas un surcoût. Le mettre en pause ou vider `cache/` reconstruit 121 Mo à la session suivante : une comparaison D5-B qui l'enjambe voit sa dispersion gonfler, d'où le seuil mesuré par comparaison (option 4). |
| [**Profiler**](https://www.nexusmods.com/stardewvalley/mods/12135) — SinZ, 2.0.0 | `SinZ.Profiler` · Nexus 12135 · [source](https://github.com/SinZ163/StardewMods/tree/main/Profiler) (monorepo SinZ163, **surveillé**) | **la télémétrie que le chantier D1 parse** : `[BigLoop] In total, it took {0:N}ms handling …` (chaîne mesurée dans la DLL). Ses packs de contenu étendent le profilage **par déclaration** (`{Type: "Duration", TargetType, TargetMethod}`). **Installé sur le parc mais en pause** (`.Profiler/`) — sa détection doit regarder les mods en pause, pas seulement les actifs. **Déclaré incompatible avec la sonde StarHubFR** (2026-09-29, `KnownIncompatibilities`) : les deux posent les mêmes minuteurs, actifs ensemble chacun gonfle ce que l'autre mesure — alerte quand les deux sont actifs, écartable. Le zip 2.0.0 de `mods tests/` embarque le `Profiler.pdb` : les symboles de débogage sont là si le format de log doit être vérifié plus finement. **Code relu le 2026-09-29 (§5)** : mécanique du transpileur, seuils, ce que la 3.0-alpha5 ajoute (et qu'il ne faut pas installer) |
| [**SDV-Radiance**](https://www.nexusmods.com/stardewvalley/mods/49397) — phuicmt, 1.7.6 | `phuicmt.SDVRadiance` · Nexus 49397 · `GitHub:PHUICMT/SDV-Radiance` · dépendance GMCM optionnelle · **installé sur le parc** | suite graphique lourde (bloom, color grading, sun shafts, ombres directionnelles, reflets) ; son diagnostic perf est **`FrameCost`** : 14 parties de rendu mesurées CPU **et** GPU (requêtes timer OpenGL), 6 frames les plus longues découpées `ours / not ours` avec deltas GC et `arrival+N` ; **`radiance_report`** écrit `~/Documents/Radiance-Dumps/radiance-report.txt`. Aucune attribution aux autres mods — « not ours » reste un lot. Audité : [`audit-perf-analyzers.md`](audit-perf-analyzers.md). Nexus **2.3.x** (journal lu le 2026-09-23, le parc reste en 2.2.5) : vague de stabilité dont la **2.3.4** — son pré-warm des sérialiseurs SpaceCore **figeait l'initialisation avant l'enregistrement des types custom des mods**, crash de sauvegarde « type not expected » au coucher : exactement la classe de types C# orphelins des **A1-T8/T9**, provoquée par un mod du parc ; la 2.3.5 retire le LOD herbe expérimental et désactive sa télémétrie de rendu par défaut |

Deux constats de lecture, mesurés :

- **Le manifeste du SLO contredit son README** (constat du 2026-09-04, sur
  la 0.5.x) : les 13 dépendances y étaient toutes **requises** (`IsOptional`
  absent de chacune), alors que le README présente Content Patcher, SpaceCore
  et GMCM comme « optional integrations, not required dependencies ». **Sa
  1.0.0 a corrigé** : les 13 sont désormais `IsRequired: false` (manifeste
  décompilé le 2026-09-29). SMAPI applique le manifeste — c'est lui qui
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

**UI Framework** ([Nexus 52945](https://www.nexusmods.com/stardewvalley/mods/52945),
`6135.UIFramework`, 1.8.0, paru le 2026-09-26 ; sources
[6135/StardewValleyMods](https://github.com/6135/StardewValleyMods), GPL-3.0) —
suivi par `mod/ui-framework` et `ui-framework-source`. Bibliothèque de menus :
un pack Content Patcher y écrit en JSON une page de réglages complète dont les
champs se lient à un état (`"Bind": "config.volume"`). Si ces pages remplacent
l'enregistrement GMCM d'un pack, ses options échappent au relevé
`gmcm-options.json` de la sonde (D4-T7) comme à la convention `config.*` de
notre éditeur. Installé **en pause** sur le parc (avec deux exemples) : à
décompiler, et à mesurer sur un pack réel qui l'exige, avant d'en tirer une
règle.

### 6 bis — Les choix que les DLL déclarent par leurs types *(2026-09-15)*

Le lecteur vit désormais **dans l'app** : `DotNetMetadata` +
`DotNetAssemblyOptions` (Swift pur, Foundation seul) relisent les tables
de métadonnées des DLL du mod à l'ouverture de son éditeur — un mod
nouvellement installé ou mis à jour est couvert sans release, avec cache
par empreinte de DLL (`GmcmLiveOptionsStore`, `DllOptions/` dans le
dossier de données). **`tools/gmcm_options.py`** (venv : `dnfile`) devient
l'**oracle** : c'est lui qui a validé le lecteur Swift sur le parc
(122 mods comparés, 0 écart, sonde jetable supprimée) et reste le moyen
de rejouer la mesure. Son dataset `assets/gmcm-options.json` reste
embarqué comme filet quand aucune DLL ne se lit.

Variance du format **mesurée avant écriture** (455 DLL du parc) : 0 stream
non compressé `#-`, 26 DLL en index de heap 4 octets (les deux largeurs
sont réellement exercées), aucune table d'indirection non vide (détectée
et refusée). La fixture des tests est produite par **le vrai producteur**
(`dotnet build`) et porte les pièges du format : dernier TypeDef et
dernière entrée de PropertyMap (plages qui finissent au bout de la
table), enum d'un assembly référencé, struct à constantes sans `value__`,
backing fields non littéraux. Chaque garde a été prouvé par sabotage —
deux d'entre eux n'étaient observables que par des tests directs sur la
grammaire (le sabotage restait vert sur la fixture).

Pourquoi cette source : **MCM (in-game) connaît les valeurs autorisées et
les bornes min/max parce que les mods les déclarent à son API au
lancement** — hors jeu, la déclaration se lit dans les métadonnées, sans
décoder l'IL : la **`PropertySig`** de `Config.Placement` porte le type
(`Stillbloom.PlacementRule`, TypeDef **interne**), et les valeurs sont les
champs **littéraux** de l'enum. Les enums externes (`SButton`, TypeRef)
sont des touches, exclus naturellement — C4-T10 les traite déjà.

**Le filtre de pertinence** (relevé corrigé le jour même) : une propriété
n'entre dans les propositions que si **sa clé existe dans le config.json
du mod**. Sans lui, les enums internes des libs embarquées gonflaient le
dataset de types qui ne sont pas des réglages (AccordSettings : deux DLL,
`Status`/`Kind` absents de son config ; 122 mods/588 champs avant filtre,
**33 mods/63 champs après** — et 33/33 mods dont chaque valeur courante
tombe dans sa liste, vérifié sur le parc). Sans config.json — mod jamais
lancé — l'éditeur n'affiche de toute façon aucun réglage : le filtre suit
exactement ce que l'éditeur peut éditer.

**Reste à prendre** : les listes passées en littéraux à l'API GMCM
(`SetAllowedValues`) et les **bornes min/max** des `AddNumberOption` —
là, il faut décoder l'IL des méthodes d'enregistrement.

---

## 7. Pistes d'intégration ouvertes

Consignées en `docs/ROADMAP.md` §4 (les ouvertes) ou dans
`docs/roadmap-archive.md` (les livrées), avec leur mesure :

- ~~**X56** — les champs `unofficialUpdate`, `warnings` et `abandonedReason` du
  dump Pathoschild ne sont pas décodés.~~ **Corrigé le 2026-09-04** :
  `unofficialUpdate` est décodé et vaut le statut `unofficial` quand aucun statut
  n'est posé — 63 des 67 entrées qui le portent n'en ont pas, et le filet se
  taisait sur 4 mods du parc que smapi.io déclare `Unofficial`. `warnings` et
  `abandonedReason` mesurés puis écartés ; le filtre de plateforme qui manque au
  premier est ouvert en **X58**.
- ~~**X57** — la bascule en masse agit sur le parc entier alors que son
  bouton vit dans une liste filtrée et paginée.~~ **Corrigé le 2026-09-04** :
  la règle de cadrage vit dans le ViewModel (`mods(matching:)` +
  `scopedMods(from:scope:)`), liste et bascule en dérivent — voir l'archive.
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
