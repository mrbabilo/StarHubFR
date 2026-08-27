# Audit — Vortex, Nexus Mods App, StarModsManager

> **Objet** : établir ce qui, chez les trois autres gestionnaires de mods Stardew
> Valley, mérite d'être intégré à StarHubFR — et ce que leurs bugs nous
> apprennent.
> **Date** : 2026-08-27. Sources clonées et lues :
> `Nexus-Mods/Vortex` (Electron/TypeScript), `Nexus-Mods/NexusMods.App`
> (C#/Avalonia, successeur annoncé de Vortex), `Arborsm/StarModsManager`
> (C#/Avalonia, spécifique Stardew).
> Les chemins sont relatifs à la racine de chaque dépôt. Les décisions portées
> en `ROADMAP.md` portent la marque `§audit-gestionnaires`.
> Complète `docs/audit-stardrop.md`, qui couvre le quatrième concurrent.

## 1. La trouvaille transversale : personne ne lit `errors[]`

L'API `smapi.io/api/v3.0/mods` renvoie, par mod, un tableau `errors[]` qui dit
**pourquoi** elle n'a pas pu juger ce mod. Sur le parc de référence, 122 mods sur
1 010 en portent un.

| Gestionnaire | `errors[]` | Constat |
| --- | --- | --- |
| **Stardrop** | `Models/SMAPI/Web/ModEntry.cs:17` | déclaré, **lu nulle part** |
| **Vortex** | `types.ts:95` | déclaré, **lu nulle part** |
| **NexusMods.App** | — | le champ n'est même pas exposé |
| **StarModsManager** | — | n'interroge pas smapi.io |

**Aucun des quatre ne dit à l'utilisateur qu'un mod n'a de verdict d'aucune
source.** C'est ce que fait B2-T10 depuis aujourd'hui, et cet audit le
transforme d'intuition en fait documenté : ce n'est pas un oubli local, c'est un
angle mort de tout l'écosystème.

## 2. NexusMods.App

### 2.1 Ils n'utilisent presque pas smapi.io

`src/NexusMods.Games.StardewValley/WebAPI/SMAPIWebApi.cs:52-58` :

```csharp
new ModSearchEntryModel(id: id, installedVersion: null, updateKeys: null, isBroken: false)
```

`installedVersion: null` **et** `updateKeys: null`. C'est exactement le piège
consigné dans la carte `smapi-io-update-api` : sans ces champs, l'API répond
mais ne suggère **aucune** mise à jour. Et de fait, ils n'extraient de la réponse
que `UniqueId`, `Name` et `NexusModsLink` (`:88-100`) — pas une version.

Ce n'est pas un défaut chez eux : étant Nexus, leurs mises à jour passent par
leur propre API. Mais cela règle une question de positionnement — **le client
officiel de Nexus ne tire pas de smapi.io les verdicts multi-sources
(Nexus + GitHub + CurseForge + ModDrop) que nous en tirons.**

### 2.2 À intégrer : la base de compatibilité **locale** de SMAPI

`src/NexusMods.Games.StardewValley/Emitters/SMAPIModDatabaseCompatibilityDiagnosticEmitter.cs:23-35`.

SMAPI livre sa propre base de correctifs dans `smapi-internal/metadata.json` —
**44 Ko déjà sur le disque de l'utilisateur**, aucune requête réseau. Leur
argument pour préférer le fichier local au distant (`smapi.io/SMAPI.metadata.json`)
est juste : ces verdicts ne valent que pour la version de SMAPI installée.

**Mesuré sur le parc de référence** (188 entrées dans la base, SMAPI 4.5.2) :

| | |
| --- | --- |
| mods du parc présents dans la base | **15** sur 1 010 |
| réellement concernés (version installée dans la clause) | **1**, en pause |
| **qui seraient signalés à tort sans lire la clause de version** | **14** |

⚠️ **Le piège est dans la clause, pas dans la donnée.** Les entrées sont bornées
par version — `"~1.13.11 | Status": "AssumeBroken"` signifie « cassé jusqu'à
1.13.11 inclus ». **Stardew Valley Expanded est dans cette base**, actif, avec
une clause qui s'arrête à 1.13.11 quand la version installée est 1.15.11. Une
intégration naïve l'afficherait « cassé », comme Swim, JsonAssets, StardewHack
et SkipIntro.

**Verdict** : source gratuite et hors ligne, mais **rendement d'un mod en pause**
sur ce parc. À porter comme complément d'un signal existant, jamais comme
fonctionnalité autonome — et jamais sans la comparaison de bornes. Sa vraie
valeur est ailleurs : la base porte un **motif technique** que smapi.io ne donne
pas (« Harmony patches fail at runtime », « causes a save crash on certain
dates »), utile le jour où un mod est effectivement signalé.

### 2.3 Leurs 14 diagnostics, mesurés chez nous

`src/NexusMods.Games.StardewValley/Diagnostics.cs`. Trois que nous n'avons pas —
tous à rendement **nul** sur le parc de référence :

| Diagnostic | Champ | Mesure |
| --- | --- | --- |
| mod exigeant un SMAPI plus récent | `MinimumApiVersion` *(jamais lu par notre app)* | **0** sur 648 déclarations |
| mod exigeant un jeu plus récent | `MinimumGameVersion` | **0** sur 60 |
| dépendance installée mais trop ancienne | `Dependencies[].MinimumVersion` | **0** |

Le zéro s'explique : SMAPI 4.5.2 et le jeu sont à jour. Ce sont des diagnostics
**préventifs**, qui ne parlent que le jour où SMAPI prend du retard sur un mod
fraîchement installé. Même famille que B2-T7 (`UpdateCautionMessage`, 0 mod) :
à garder, pas à prioriser — et désormais chiffrés.

### 2.4 Écarté

| Sujet | Raison |
| --- | --- |
| `StardewValleyLoadoutSynchronizer`, `Abstractions.Loadouts`, GC | Repose entièrement sur un **déploiement depuis un dossier de transit** par liens. StarHubFR manipule `Mods/` en place et met en pause par préfixe point. Rien ne transfère. |
| `Games.FOMOD`, `AdvancedInstaller` | Installateurs interactifs multi-jeux, sans usage Stardew. |

## 3. Vortex

Seule l'extension `extensions/games/game-stardewvalley/` est pertinente ; le
cœur de Vortex repose sur le même déploiement par transit que NexusMods.App.

### 3.1 Bug — le TTL hebdomadaire vaut 2 h 48

`src/common.ts:63-64` :

```ts
/** SMAPI compatibility query interval (once per week). */
export const SMAPI_QUERY_FREQUENCY: number = 1000 * 60 * 24 * 7;
```

`1000 × 60 × 24 × 7 = 10 080 000 ms`, soit **2 h 48** — le facteur des
minutes vers les heures manque. Une semaine vaudrait `1000 × 60 × 60 × 24 × 7`.
Le commentaire dit explicitement l'intention ; le calcul ne la tient pas.
Vortex réinterroge donc smapi.io **une soixantaine de fois plus souvent** que
prévu.

**Ce que ça nous apprend** : une constante de durée composée mérite d'être
écrite dans une unité qui se relit (`7 * .day`), et un commentaire qui affirme
une durée n'est pas une preuve. À vérifier chez nous sur les mêmes patrons.

### 3.2 Une requête par mod, et une requête incomplète

`src/compatibility/updateConflictInfo.ts:55-65, 78` — `updateConflictInfo` prend
**un seul `modId`** et appelle `smapi.findByNames(query)` pour lui. Sur un parc
de mille mods, cela fait mille requêtes HTTP là où nous en faisons sept lots de
150.

Le corps envoyé (`src/smapi/proxy.ts:115-119`) ne porte que `mods`,
`includeExtendedMetadata` et `apiVersion` : **ni `gameVersion` ni `platform`**.
La compatibilité ne peut donc pas être jugée pour la version de jeu réelle. Et
`SMAPI_IO_API_VERSION` est figé à `"3.0.0"` (`src/common.ts:67`) quand SMAPI en
est à 4.5.

Ces deux défauts se composent avec le précédent : TTL soixante fois trop court
× une requête par mod.

*Vérifié et **non** bogué* : le choix du statut le plus grave
(`compatibilityPrio`, `:66-79`) est correct — `compatibilityOptions` range
`broken` en tête et le tri croissant prend bien le pire.

### 3.3 Pas d'installation de SMAPI sur macOS

`src/installers/smapi/install.macos.test.ts` — le test verrouille le message du
bouchon : `"SMAPI automatic installation on macOS is not implemented yet"`, et
vérifie qu'aucune archive n'est décompressée. Windows et Linux sont implémentés.

Notre `SmapiInstaller.swift` le fait sur macOS. **Écart en notre faveur, sur la
seule plateforme qui nous concerne.**

Leurs fixtures (`src/installers/smapi/fixtures/archiveListings.ts`) confirment la
structure de l'archive SMAPI que nous traitons déjà : archive principale →
`internal/<plateforme>/install.dat`, elle-même une archive.

### 3.4 Le « mod de configuration » — déjà couvert, et mieux

`src/configMod/README.md`. Vortex crée un mod synthétique par profil,
`Stardew Valley Configuration (<Profile Name>)`, pour que les `config.json`
générés au premier lancement survivent à une mise à jour ou une désinstallation.

Nous couvrons déjà ce besoin par un chemin plus simple :
`ModZipInstaller.swift:1164` photographie `config.json` **et tous les
`i18n/*.json`** avant une réinstallation, et les restaure ensuite. Les fichiers
de langue ne sont pas mentionnés côté Vortex — or ce sont eux que le hub de
traduction FR produit.

*À retenir tout de même* : leurs garde-fous de `src/configMod/policy.ts` —
ne jamais absorber un fichier de `smapi-internal/`, refuser d'attribuer
d'office les fichiers d'un mod « racine ». Nos chemins d'écriture méritent la
même liste explicite.

## 4. StarModsManager

Le plus proche de notre axe C : c'est une **implémentation livrée** de la
traduction de mods Stardew par modèle de langue, Ollama en local et OpenAI en
ligne (`src/StarModsManager/Trans/`, 4 fichiers, 262 lignes). **Windows
seulement**, macOS annoncé comme « prévu ».

### 4.1 Ce qui converge avec notre spec

- **Deux implémentations derrière une interface** (`ITranslator.cs:11-19`) :
  `OllamaTrans` et `OpenAITrans`, avec `NeedApi` pour distinguer le local du
  distant. C'est notre `LocalLLMClient` / `DeepLClient`.
- **Vérification des jetons après traduction** (`Translator.cs:68`) :
  `IsMismatchedTokens`, avec un `?? true` prudent — l'indéterminé est traité
  comme une incohérence. C'est notre `TranslationTokenCheck`.
- **L'ordre des clés est restauré depuis `default.json`**
  (`Translator.cs:70-73`, `combined.Sort(defaultLang)`) : le dictionnaire perd
  l'ordre, ils le remettent depuis le fichier source. Même invariant que notre
  `OrderedJSONWriter`, atteint autrement.

### 4.2 Bug — la traduction s'écrit sans filet, et l'annulation la tronque

`Translator.cs:76` :

```csharp
await File.WriteAllTextAsync(savePath, content, token);
```

Écriture **directe** sur le fichier de l'utilisateur, **et le jeton
d'annulation est passé à l'écriture elle-même**. Annuler pendant l'écriture — le
bouton existe, la traduction dure des minutes — laisse un `fr.json` tronqué à la
place du fichier précédent. Des heures de traduction pour un fichier illisible.

Notre `TranslationFileStore.swift:43-48` écrit dans un `.tmp` puis
`replaceItemAt` : l'ancien fichier survit à tout échec. **C'est la garantie qui
justifie la contrainte, et voici le contre-exemple réel qui la motive.**

### 4.3 Bug — une tabulation dans une valeur est remplacée en silence

`ITranslator.cs:36-37` :

```csharp
var formedJson = json.Replace("\t", " ");
return JsonSerializer.Deserialize(formedJson, Default.DictionaryStringString) ?? [];
```

Le remplacement vise les tabulations brutes qui traînent dans des JSON malformés
— illégales dans une chaîne JSON, et les fichiers de mods en contiennent. Mais
il est **global** : une tabulation à l'intérieur d'une valeur de texte est
remplacée par une espace, donc **le texte du mod est altéré avant même d'être
traduit**, sans que rien ne le dise.

Notre `I18nLenientParser` tolère ces fichiers en lecture sans réécrire leur
contenu. Point à ne pas régresser.

### 4.4 Deux détails d'implémentation

- `TranslationContext.UnescapeUnicodeChinese` (`ITranslator.cs:44-53`) : ils
  dés-échappent à la main les `\uXXXX` de la plage CJK, parce que l'encodeur
  .NET échappe tout le non-ASCII. **Nous n'avons pas ce contournement à faire** :
  `OrderedJSONWriter.escape` (`:83-104`) n'échappe que les caractères de contrôle
  C0 et laisse accents, emoji et CJK littéraux — et échappe correctement la
  tabulation en `\t` au lieu de la remplacer.
- `Translator.cs:13-15` : le constructeur du singleton lance `Task.Run(Test)`,
  c'est-à-dire un **appel réseau au traducteur** au premier accès à
  `Translator.Instance`, dont le résultat écrit `IsAvailable` sans
  synchronisation. Course de données, et effet de bord dans un constructeur.

## 5. Synthèse — ce qui vaut d'être intégré

| # | Trouvaille | Source | Poids | Statut proposé |
| --- | --- | --- | --- | --- |
| 1 | Base locale `smapi-internal/metadata.json` — motifs techniques, hors ligne, **avec comparaison de bornes obligatoire** | NexusMods.App | **S** | candidat ROADMAP, faible priorité (1 mod concerné) |
| 2 | `MinimumApiVersion` / `MinimumGameVersion` non lus par notre app | NexusMods.App | **S** | candidat préventif (0 mod aujourd'hui) |
| 3 | Dépendance installée mais sous sa `MinimumVersion` | NexusMods.App | **S** | candidat préventif (0 mod aujourd'hui) |
| 4 | Liste explicite de garde-fous d'écriture (`policy.ts`) | Vortex | **S** | à reprendre comme revue, pas comme code |
| 5 | Constantes de durée relisibles + audit de nos TTL | Vortex (bug) | **XS** | vérification interne |

### Écarté, avec la raison

| Sujet | Source | Raison |
| --- | --- | --- |
| Loadouts, synchronizers, ramasse-miettes | NexusMods.App | Reposent sur un déploiement depuis un dossier de transit. Nous éditons `Mods/` en place. |
| Mod de configuration synthétique | Vortex | Besoin déjà couvert par `ModZipInstaller`, qui préserve en plus les `i18n/*.json`. |
| Installateur SMAPI | Vortex | Non implémenté sur macOS chez eux ; le nôtre l'est. |
| Requête smapi.io par mod, TTL, `apiVersion` figé | Vortex | Inférieurs à notre voie groupée. À ne pas imiter. |
| `errors[]` ignoré | les quatre | C'est précisément B2-T10. |
| Écriture non atomique, `Replace("\t", " ")` | StarModsManager | Contre-exemples : nos garanties d'écriture existent pour ça. |
| Chemins et empaquetage | StarModsManager | Windows seulement, AOT. |

### Ce que l'audit confirme de notre position

- **Sur la détection de mises à jour**, nous sommes seuls à exploiter smapi.io
  pour ce qu'elle sait : verdicts multi-sources, motifs d'échec, et reprise par
  Nexus des mods qu'elle refuse de juger.
- **Sur la traduction**, notre spec est au-dessus de la seule implémentation
  livrée sur deux points qui coûtent des données à l'utilisateur : écriture
  atomique et non-altération du texte source.
- **Sur macOS**, ni Vortex ni StarModsManager n'installent SMAPI ; l'un ne
  tourne pas du tout sur la plateforme.
