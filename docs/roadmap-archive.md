# Archive de la roadmap — ce qui a été livré

Ce fichier porte les **items terminés** de [`ROADMAP.md`](ROADMAP.md), avec leur
récit intact : ce qui était cassé, ce qui a été mesuré, sur quoi, et ce qui a été
écarté au passage. Il a été séparé de la roadmap le 2026-09-04 parce que ces
items en occupaient **plus des deux tiers** — la question « que reste-t-il à
faire ? » s'y lisait à une ligne contre quatre.

**À quoi ça sert.** Les mesures sont ici, et elles coûtent cher à refaire : le
nombre de manifestes qui déclarent un `ContentPackFor`, ce que smapi.io rend
sans `apiVersion`, combien de dossiers du parc portent un point de tête. Avant
de re-mesurer quoi que ce soit sur le parc, chercher ici.

**Ce que ce n'est pas.** Ce ne sont **pas des consignes** : ce sont des faits
datés, vrais au moment où ils ont été écrits. Le code a bougé depuis. Une règle
qu'il faut encore respecter aujourd'hui n'a rien à faire dans une archive — elle
vit dans les *Traps* de `CLAUDE.md`, dans `AGENTS.md` §4, ou dans l'en-tête du
type concerné.

**Comment y chercher.** Les identifiants (`X18`, `C4-T5`, `B3-T5`…) sont cités
tels quels dans le code et dans les messages de commit : `grep -n "X18"` ici
répond. L'ordre et les titres de section sont ceux de la roadmap.

---
## 3 bis. Veille — ce qui a été instruit puis écarté, avec la mesure

> Les sources externes qui bougent sont relevées par `check_sources.py`. Quand un
> mouvement est instruit et qu'il **ne donne rien**, la conclusion vit ici : sans ça,
> la session suivante relit le même journal des modifications et refait le même travail.
> Un écart écarté sans mesure ne compte pas — c'est le constat de
> `audit-fix-commits-by-message-not-title` (16 correctifs amont sur 20 avaient été
> jugés sur leur titre, deux valaient instruction).

### 2026-09-14 — Stardrop v1.10.0 → v1.10.2, et SMAPI `79f9bbb` → `f090df0`

**Retenu** : la liste noire SMAPI devient **A2-T7**, les manifestes imbriqués **A1-T4**,
et le message d'échec du gate L10n **F8**. Le reste est instruit et clos ci-dessous.

| Ce que le concurrent a corrigé | Chez nous | La mesure |
| --- | --- | --- |
| **Perte des notes et des configs au renommage d'un profil** (`b3d0f8df`) — leur renommage reconstruisait le profil depuis ses seuls mods activés | **Sans objet, par conception** | `renameProfile(id:newName:)` fait `mutateProfile(with: id) { $0.name = newName }` : une mutation **en place** sur un `UUID`. `ModProfile` porte `id: UUID` **distinct du nom** ; notes (`modNotes`) et métadonnées (`modMetadata`) ne sont jamais reconstruites. Leur modèle identifiait un profil par son fichier `<nom>.json` |
| **Caractères spéciaux dans un nom de profil** (`f20ebda0`) — nom de fichier non assaini, **et** collision de deux noms qui ne diffèrent que par des caractères remplacés | **Sans objet, par conception** | `ProfileConfigStore.fileURL(profileId: UUID)` écrit dans `<UUID>.json`. Le nom de profil n'entre dans **aucun** chemin : il n'y a ni caractère à remplacer, ni collision de fichiers à départager |
| **Second parcours du disque pour trouver les `config.json`** (`0ea2dbdf`) | **Nous ne l'avons pas** | `ModScanner.swift:168` fait un `fm.fileExists(atPath: …/config.json)` — un contrôle direct sur un chemin connu, pas une ré-énumération du dossier. *(La **seconde** moitié de leur diff, elle, a donné A1-T4 : voir la ROADMAP.)* |
| **Une traduction entière perdue en silence** (`8205d0ea`) — une virgule manquante dans `pl.json`, et le polonais disparaissait sans un mot | **Le gate attrape** | Prouvé **par sabotage** le 2026-09-14 : virgule retirée dans `assets/fr.json` → `build_app.py` **exit 1**, avant toute compilation. Reste un défaut d'ergonomie, sorti en **F8** : le message ne nomme pas le fichier |
| **Les langues découvertes depuis les fichiers i18n** (`15332a39`), au lieu d'une énumération figée de 15 langues | **Sans objet** | L'UI est **bilingue par conception** (`en`, `fr`), et `build_app.py` impose la **parité des clés** entre les deux — il n'y a pas d'énumération à tenir en accord avec des fichiers |
| **Bouton « retirer l'association `nxm://` »** (`dde6bbbd`) | **Ne se transpose pas** | Leur correctif est du **registre Windows** (`Software\Classes`, `UserChoice`). Sur macOS l'association est **déclarative** — `CFBundleURLSchemes` dans `Info.plist` — il n'y a aucune entrée à nettoyer, et pas d'API propre pour « rendre la main » à un autre gestionnaire. Le besoin reste réel ; la solution de l'amont n'y répond pas |

**Non instruit, et pourquoi** : `i18n-translator` v2.0.3 → v2.1.0 ne porte que deux
commits, tous deux des tests d'acceptation de sa propre release — rien sur les jetons
protégés ni sur les garanties d'écriture, les deux seules choses pour lesquelles nous
suivons ce dépôt. Les versions de mods qui ont bougé (`radiance` 1.7.7 → **2.0.0**,
`ultrasmooth` 2.1.7 → 2.2.5, `modern-config-menu` 2.1.0 → 2.1.2) sont des **publications
relevées via smapi.io**, pas des mises à jour du parc local ; aucun parseur n'existe
encore côté StarHubFR pour les formats de `radiance`, donc sa majeure ne casse rien
aujourd'hui — elle sera à relire quand D2 reprendra.

## 3 ter. Audit de deux archives du parc de test — 2026-09-14

> Demandé sur deux fichiers de `mods tests/`. Statique uniquement : **rien n'a été
> lancé** — ni l'application, ni son serveur — conformément à la règle du dépôt et
> parce qu'un binaire non notarisé ne s'exécute pas pour voir. Les deux sont
> désormais suivis par `check_sources.py` (`mod/save-launcher`, `mod/event-studio`).

### Stardew Valley Event Studio — Nexus 51824, `xzqute.StardewEventStudio`

**Rien à signaler.** Archive conventionnelle de 6 fichiers : `manifest.json`
(`EntryDll`, `MinimumApiVersion 4.5.0`, `UpdateKeys: ["Nexus:51824"]`), deux DLL,
`assets/`, `i18n/default.json`. Les deux DLL ne portent **aucune** référence à
`System.Net`, `Process`, `Assembly.Load` ni `Reflection.Emit` — relevé sur les
chaînes ASCII **et** UTF-16 (les chaînes .NET vivent dans le tas `#US` en UTF-16LE ;
un `strings` nu ne les voit pas, et `strings` de macOS n'a pas de `-e`). Les seules
correspondances du filtre sont `ItemRegistry` et `CommandRegistry`, deux API du jeu.
Absent de la liste noire SMAPI.

⚠️ **Une version plus récente existe** : l'archive est en `1.0.0-beta`, smapi.io
annonce `1.0.0-beta.1`.

### Stardew Save Launcher — Nexus 52041

**Ce n'est pas un mod.** C'est une **application macOS** de 113 Mo (707 fichiers,
archive non compressée) qui embarque un runtime .NET et un serveur ASP.NET Core,
accompagnée d'un **mod compagnon** de 17 Ko — `Codex.StardewSaveLauncher.Companion`,
seul `manifest.json` de toute l'archive, enfoui dans
`Stardew Save Launcher.app/Contents/Resources/CompanionMod/`.

Ce qui a été mesuré, et ce que ça vaut :

| Relevé | Lecture |
| --- | --- |
| Signature **ad-hoc**, `TeamIdentifier` non défini, bundle `local.stardew-save-launcher` | Ni signée par un développeur identifié, ni notarisée : Gatekeeper la refusera, et l'ouvrir demande un contournement explicite. C'est le fait à connaître **avant** de la lancer |
| Le serveur écoute sur **`http://127.0.0.1:5177`** | **Loopback seul**, pas `0.0.0.0` : rien n'est exposé au réseau local. C'est le bon choix, et c'est le point rassurant du lot |
| **Onze routes** `/api/…` — dont `/api/play/{profileId}`, `/api/profiles/{profileId}/rename`, `/api/plan/…` — servies en `MapGet`, `MapPost` et `MapDelete` | Aucune trace de jeton, d'en-tête d'autorisation ni de CORS dans les deux DLL applicatives. Tant que l'application tourne, **tout processus local** peut piloter ces routes. Ce n'est pas une porte dérobée — c'est l'absence de défense en profondeur habituelle des outils locaux — mais ça se sait avant de la laisser tourner en fond |
| `StardewSaveLauncher.Core.dll` invoque `/usr/bin/open` et `/bin/chmod`, et connaît `/Applications/Stardew Valley.app` | Cohérent avec sa fonction : lancer le jeu et rendre exécutable ce qui doit l'être. Aucun téléchargement, aucune URL distante |
| Le mod compagnon ne porte **aucune** URL, aucun client HTTP, aucun socket | Le dialogue entre l'app et le mod ne passe **pas** par le serveur : il passe par deux variables d'environnement (`STARDEW_SAVE_LAUNCHER_REQUEST`, `STARDEW_SAVE_LAUNCHER_LANGUAGE`) et un `launch-request.json` que le mod lit au démarrage **puis supprime**. Mécanisme sobre et lisible |
| Absent de la liste noire SMAPI | Comme l'autre |

**Conclusion** : aucun comportement malveillant. Deux réserves à porter à
l'utilisateur — le binaire n'est pas notarisé, et son serveur local n'authentifie
personne.

### Ce que la sauvegarde sait des mods — mesures du 2026-09-14, devenues A1-T6

Cherché parce que le `Core.dll` du launcher manipule `SaveModIds` et `CommonModIds`.
Relevé sur `Zofia_443716371` (37 Mo) et ses deux générations antérieures, sans
lancer le jeu — les trois fichiers suffisaient à trancher la question qui compte.

| Mesure | Valeur |
| --- | ---: |
| Clés `<key><string>` dans la sauvegarde | 8 984 |
| Préfixes distincts en forme `Auteur.Mod` | 748 |
| Préfixes résolvant vers un mod **installé** | **32** (4 509 entrées) |
| Dont des mods **en pause** | 3 — `larvuk.AdvancedFruitTreeFramework` (1 648), `NCarigon.BushBloomMod` (154), `Spiderbuttons.Agromancy` (115) |

**La question qui décidait de la sévérité — et sa réponse.** « Perd-on ces données
quand le mod n'est plus là ? » **Non.** `Kedi.VPP.WasRainingHere` porte **817 entrées
sans aucun mod installé qui corresponde**, et le compte est **stable sur trois
générations** de la même sauvegarde : 805 (26/07) → 817 (27/07) → 817 (14/09). Les
**56** préfixes présents dans la plus ancienne et absents de la plus récente sont
**tous** des clés à expiration — `_memory_oneweek`, `_memory_twoweeks`,
`_memory_eightweeks` — et **62** du même genre sont apparues en sens inverse. Ce
n'est pas une purge, c'est la durée de vie que les mods donnent eux-mêmes à leurs
clés. ⚠️ Cela vaut pour le **`modData`** ; le sort des **objets** définis par un mod
absent n'a pas été mesuré.

**Ce que le relevé ne dit PAS.** Les 695 préfixes non résolus ne sont pas 695 mods
manquants : la résolution s'arrête à deux segments, si bien que
`Kedi.VPP.WasRainingHere` (clé de `Kedi.VPP`) et `Cropgenics.GroveForestNode.Health`
/ `.Variant` / `.Master` (sous-clés d'un même propriétaire) comptent chacun pour un
« mod absent ». La règle de normalisation est **à mesurer avant d'être codée**.

### Ce que l'audit a trouvé sur **notre** application — devenu A1-T5

`detectZipStructure` ne relève qu'un seul dossier à manifeste dans cette archive,
et rien au-dessus n'en porte : la règle « un manifeste sous un autre manifeste est
une dépendance embarquée » ne mord donc pas, et la structure est classée
`.singleMod("Stardew Save Launcher.app/Contents/Resources/CompanionMod")`.
StarHubFR installerait le compagnon **seul** et écarterait l'application de 113 Mo
**sans un mot** — or le compagnon est inerte sans elle, puisqu'il attend une
variable d'environnement qu'elle seule pose. Voir la ROADMAP.

## 3 quater. Décompilation de ModernConfigMenu 2.1.2 — 2026-09-14

Demandée sur l'archive `ModernConfigMenu 2.1.2 49437 …`. Désassemblage IL par
`ikdasm` (77 411 lignes ; `monodis` échoue sur une assertion `get.c:913`).

**Le changelog a d'abord été déclaré illisible — à tort.** `curl` avec un
`User-Agent` de navigateur et `WebFetch` prennent bien un **403**, et l'API v1
exige la clé du Trousseau ; mais la page `?tab=logs` ouverte dans un vrai
navigateur **est parfaitement lisible, sans compte**. L'auteur l'a relevé, et les
**33 changelogs** en ont été extraits dans la foulée. Deux erreurs de méthode se
cumulaient : le DOM lu **avant la fin du chargement** (contenu en AJAX — un
`wait_for` sur le numéro de version suffit), puis lu via `body.innerText`, **qui
ne rend rien d'un conteneur masqué** alors que les `<h3>Version …</h3>` étaient
présents. ⚠️ **La leçon** : « la page est vide » se prouve sur le DOM, jamais sur
`innerText`, et jamais avant d'avoir attendu. Le suivi `changelog_reviewed` de
`check_sources.py`, né de ce constat, reste justifié — un **script** ne peut
toujours pas lire ces pages — mais pour la bonne raison.

**Ce que l'IL a donné à la place :**

| Relevé | Portée |
| --- | --- |
| `ModDateTracker.HistoryFilePath = "data/mod_history.json"` — **toujours présent en 2.1.2** | Le risque documenté en 2.1.0 n'a pas disparu |
| `DateCache` (UniqueID → DateTime), `HistoryCache` (UniqueID → `ModHistoryEntry`), `RecentWindow`, `PopulateModDates(helper, monitor, mods)` lisant `RegisteredMod.InstallDate` | MCM mémorise la **date d'installation de chaque mod** pour signaler les récents — un état qui ne se reconstruit pas |
| `GenericModConfigMenuCompat`, `IGenericModConfigMenuApi`, `GmcmRedirectPatch` | La compatibilité GMCM est explicite : la convention `config.<clé>.name` que lit notre éditeur **survit** au changement de front. C'est la raison pour laquelle ce mod est suivi |
| Aucune référence réseau hors de son propre dossier | Rien à signaler |

### Ce que la décompilation a trouvé sur **notre** application — devenu A1-T7

`ModConfigFiles.preservable` est une liste blanche de **18 noms** (`config.json` +
17 fichiers de langue) ; `snapshotUserConfigs` ne préserve qu'eux, et la mise à
jour écrase tout le reste.

🔴 **Table invalidée le 2026-09-14 — ne pas citer** (démenti plus bas, et §8.4 de
la ROADMAP). Conservée telle quelle pour mémoire du piège de mesure :

| ~~Mesure sur le parc (1 112 dossiers à manifeste)~~ | ~~Valeur~~ |
| --- | ---: |
| ~~Fichiers écrits **après** l'installation (mtime > manifeste + 1 h)~~ | ~~4 077~~ |
| ~~Déjà préservés (`config.json` 538, `fr.json` 348…) ou étrangers (`__folder_managed_by_vortex` 495)~~ | ~~1 525~~ |
| ~~**Net — détruits par une mise à jour**~~ | ~~**2 552, sur 256 mods**~~ |

Le classement des noms qui en sortait (`<sauvegarde>_SaveData.save`,
`companion.json` 67, `companion.png` 44, les configs horodatées d'`AccordSettings`)
désigne de vrais fichiers écrits par les mods — c'est le **total** qui était faux,
pas l'existence du problème.

⚠️ **Une mesure naïve donnait 275 « mods à données »** en comptant tout `data/*.json` :
faux — les `Mail.json`, `Dialogue.json`, `Objects.json` des Content Packs sont
**livrés**, pas écrits.

🔴 **Et le correctif d'alors — la mtime relative au manifeste — est faux aussi
(constaté le 2026-09-14, cadrage §8.4 de la ROADMAP).** Un zip restitue les dates
de travail de l'auteur : `.[CP] DSHi Food Retexture` porte un manifeste du
2025-06-15 et des assets étalés du 2025-01 au 2025-10, tous livrés. Les trois
premiers « détruits » du classement sont `content.json` (111), `assets/` (1 159)
et `Portraits/` (96) — du contenu livré. **Les chiffres 4 077 et 2 552 / 256 mods
ci-dessus ne valent rien** ; ils sont conservés pour mémoire du piège, pas comme
mesure. Quatrième instance du même travers.

✅ **Ce qui tient à la place** : un fichier dont le nom porte l'identifiant d'une
**sauvegarde réelle** n'a pu être écrit que sur cette machine, par le mod —
**100 fichiers sur 52 mods**, tous de la progression de jeu (`FarmTypeManager`,
40 packs `[FTM] *`, `BetterCrafting/savedata/seenrecipes/`,
`AnimalHusbandryMod/data/farmers/`). C'est un **plancher** certain, pas un total.

## 3 quinquies. Le design de l'éditeur de config de MCM — audit, 2026-09-14

Demandé après la décompilation (§3 quater) : « intégrer le design de l'éditeur de
config à notre appli ». L'IL de 2.1.2 porte leurs contrôles — `ColorPicker` (265
occurrences), `Slider` (309), `KeybindOverviewModal` (462), `ControlPoolManager`
(57) — plus `Core.Visibility` (réglages conditionnels),
`Binding.PropertyBinding` (application immédiate), `GroupedSectionCard`,
`CardSettingRow`, `MinimalSectionHeaderRow`.

**Une seule idée survit à la mesure du parc : le contrôle de raccourci** →
**C4-T10**. Les trois autres sont refusées ci-dessous, chiffres à l'appui, pour
qu'on ne les réinstruise pas.

### ⛔️ Ne pas porter : l'infobulle à la place de la description permanente

C'est le refus le plus important du lot, parce que leur propre historique dit
pourquoi. MCM a fait l'aller **et** le retour :

| Version | Ce que le changelog dit (verbatim) |
| --- | --- |
| **1.7.8** | « **Tooltip De-Cluttering**: Removed permanent description labels from inside cards to eliminate visual clutter; descriptions are now shown cleanly on hover tooltip popups as per game standards. » |
| **2.1.1** | « Textbox & Child Control Tooltip **Dead Zone** Elimination (`FindHoveredTooltip`) » et « **Hierarchical Parent-Chain Tooltip Inheritance** […] walk up from the deepest hovered leaf control » |

Retirer les descriptions a créé des zones mortes au survol, qu'il a fallu réparer
une version plus tard par une résolution d'infobulle parent par parent. L'IL de
2.1.2 porte encore cette machinerie : `FindHoveredTooltip`,
`SearchTreeForTooltip`, `DrawThemedTooltip`, 40 `TooltipGetter`.

Nous affichons la description **en permanence**
(`StarHubTH/Views/ModConfigEditorView.swift:713`), et ce choix est déjà adossé à
une mesure du parc inscrite dans le code : **1 926 rangées** en portent une,
**66 caractères de médiane**, 172 au 90ᵉ centile, 554 au pire ; **158 dépassent
deux lignes, une seule dépasse cinq**. Le désordre qu'ils ont voulu fuir n'existe
pas chez nous. ⚠️ Et sur macOS, `.help()` exige ~2 s de survol immobile : la piste
infobulle nous coûterait leurs zones mortes **plus** ce délai.

### ⛔️ Ne pas porter : le sélecteur de couleur

Compté sur les `config.json` du parc : **4 valeurs de couleur réelles** —
`.AccordSettings: CustomAccentColor = #DA8930`, et trois dans `.ChoreTrail`.
⚠️ Un premier comptage en annonçait 13 : le motif à six chiffres hexadécimaux
attrapait `100000` et `500000`. Exiger le `#` ramène à 4. Un contrôle pour quatre
valeurs sur tout le parc ne se justifie pas.

### ⛔️ Ne pas porter : le curseur (slider)

Un curseur a besoin d'une échelle, et nous n'en avons pas :
`ContentPackConfigSchema` porte `AllowValues`, `Default`, `AllowBlank`,
`AllowMultiple` — **aucune borne** `min`/`max`. Le curseur n'aurait rien à
graduer. Le champ numérique actuel garde son pas de 0,5 et son
`decimalFormatter` (sans lequel 0,5 s'affichait 0 — 758 options du parc
touchées).

## 4. Correctifs identifiés — à traiter en premier

- [x] **R2** ✅ *(livré le 2026-09-06)* — **Écriture atomique + apply guard pour
      `applyProfileToFilesystem`.** Le constat de la passe du 2026-09-04 disait
      « aucun instantané au niveau profil » ; la relecture du code en a dit plus :
      `incompletelyAppliedProfileIds` était un `private var` en mémoire, et le
      premier `syncActiveProfileIds()` après un crash — n'importe quelle bascule
      manuelle — **écrivait l'état disque partiel dans le profil**, l'accident
      maquillé en décision. Mesure du défaut : sur un parc de ~966 mods, une boucle
      de renommage interrompue au tiers laisse ~300 dossiers du mauvais côté, et
      le profil actif les réclame comme voulus au premier sync.
      ▸ **Livré** : garde jeu refus net aux quatre entrées applicatives
      (`applyProfile`, `updateProfile`, `addModToProfile`, `importFavorites` —
      la bissection passe à côté, elle gère l'état du jeu elle-même) ;
      `ProfileApplyJournal` (Core, patron `BisectionSnapshotStore`, écriture
      `.atomic`, corrompu ⇒ absent) écrit avant la boucle, effacé dans le
      completion ; adoption et capture bloquées tant qu'il vit ; dialogue de
      reprise au lancement (présenté après la révélation de la fenêtre, jamais
      pendant le splash) — « Reprendre » rejoue les déplacements **et** la
      restauration des configs (le completion que le crash a avalé la portait ;
      la capture, elle, avait déjà couru), « Garder l'état actuel » adopte
      explicitement. Quitter ou activer un autre profil tranche implicitement,
      avec journal. Correctif adjacent : la restauration qui saute jeu ouvert
      pose enfin le marqueur desync.
      ▸ **Écarté** : le « backup timestamped » du pattern RimManager (copie de
      dossiers — dizaines de Go sur le parc ; l'état pré-apply est le plan
      inverse, quelques Ko, déjà dans le journal pour R5), la « validation
      post-write » (redondante avec la capture d'échec par déplacement et le
      rescane systématique), la garde sur la bascule unitaire (autre ampleur,
      item séparé si demandé). 5 tests Core neufs, 2 325 verts.

- [x] **R2bis** ✅ *(livré le 2026-09-07)* — **Jamais deux instances du jeu au
      lancement.** Complément à R2, trouvé en le vérifiant : les quatre entrées
      applicatives refusaient jeu ouvert, mais le bouton de lancement lui-même
      pouvait repartir une seconde instance — `isGameRunning()` ne voit pas le
      processus pendant les quelques secondes avant son apparition dans
      `NSWorkspace.runningApplications`, et un double-clic passe librement dans
      cette fenêtre aveugle. Deux instances, c'est deux processus sur les mêmes
      fichiers de sauvegarde.
      ▸ **Livré** : refus net et alerte si le jeu tourne déjà ; `GameLaunchGate`
      (Core, 5 tests) ferme la porte 10 s après un lancement admis — la fenêtre
      part du **premier** essai admis, un refus ne la rallonge pas ; la porte se
      rouvre dès que le jeu devient visible (`isGameRunning()` appelle
      `noticeGameRunning()`) pour ne pas retarder un relancement légitime après
      un crash immédiat. 2 330 tests verts.

- [x] **R3** ✅ *(livré le 2026-09-07)* — **Snooze d'updates Nexus.** Le UX
      gap mesuré : ignorer une mise à jour = l'avoir en permanence sous les
      yeux — le seul geste « pas maintenant » était de fermer l'onglet.
      ▸ **Livré** : menu « Mettre en veille » sur chaque ligne Nexus, trois
      échéances — une semaine (horloge), jusqu'à la prochaine version du mod
      (la version Nexus au moment du geste est mémorisée ; une version
      **différente** réveille), jusqu'à la prochaine version de Stardew (la
      version locale du jeu, lue du journal SMAPI ; son changement réveille).
      `ModUpdateSnoozer` (Core, 11 tests) : identité par **UniqueID** (jamais
      l'id Nexus — 58 partagés sur le parc — ni le nom de dossier — un
      renommage ne doit pas réveiller un snooze), persistance UserDefaults
      (JSON, corruption ⇒ démarrage vide), expiration paresseuse évaluée et
      purgée à la lecture. La partition actifs/en-veille se juge **après** la
      consolidation par pack — jamais sur le cache plat, où une passe Nexus
      partielle doit continuer de fusionner. Le badge sidebar ne compte plus
      les veilles ; l'inventaire n'est jamais masqué (la pastille update y
      reste). Une section repliée sous la liste montre les veilles avec leur
      échéance et un bouton « Réactiver » — snoozer ne ressemble jamais à
      perdre une information. Absence de version lue (`nil`, 429, mod hors
      réponse) : le snooze tient — on ne réveille pas sur une absence
      d'information, seulement sur un changement. Cliquet : `vm.L`/`vm`/deux
      `print` Warning assumés par `--update` (patron des vues et des stores
      Core) ; les `try?` refondus en `do/catch` et `snoozedUpdates` en
      `private(set)` plutôt qu'assumés. 11 tests Core neufs, 2 341 verts.

- [x] **X1** ❌ *(non reproduit — pas de bug)* — Le copier/coller fonctionne dans le champ
      NexusID comme ailleurs dans l'app (vérifié par l'utilisateur, 2026-07-30). Le menu
      Édition est bien présent. Rien à corriger.
- [x] **X2** ✅ *(corrigé, en attente de release)* — **Le rendu des descriptions casse sur du BBCode réel.** Diagnostic mené
      sur **SVE** (Nexus 3753, 23 Ko de description) en rejouant `DescriptionBlockParser`
      à l'identique : **six défauts distincts**, tous reproduits.
      ▸ **a. Spoilers imbriqués → `[/spoiler]` affiché en clair.** SVE imbrique
      `[spoiler]` dans `[spoiler]` (4 fois) ; le motif apparie un ouvrant avec le
      **premier** fermant, le fermant externe reste orphelin dans le texte.
      ▸ **b. Images dans un spoiler jamais rendues (5 sur 22).** Le spoiler est consommé
      d'un seul bloc : les `[img]` qu'il contient restent du texte brut, on lit le
      balisage au lieu de voir l'image.
      ▸ **c. `**` orphelins à l'écran** (`Immersive Farm 2 Remastered**`,
      `[Twitter**](…)`). `balancedText` ne retire les délimiteurs que si leur nombre est
      **impair** ; un découpage de bloc qui en laisse un nombre pair mais mal placé passe
      au travers et s'affiche littéralement.
      ▸ **d. `](url)` affiché.** SVE contient des `[url=X][/url]` au libellé vide,
      convertis en `[](X)` — un lien Markdown sans libellé, que le rendu laisse voir.
      ▸ **e. Toute la page en gras.** `[size=…]` devient `**gras**` sans regarder la
      valeur, or SVE utilise `size=3` **187 fois** comme taille de *corps de texte*
      (contre 16 `size=4` de titres) : 100 % du texte en gras, titres indiscernables.
      ▸ **f. Perte de contenu sur `[CP]`.** La règle « supprimer toute balise restante »
      efface `[CP]`, qui n'est pas du BBCode mais le **nom réel des dossiers** de SVE
      (`[CP] Stardew Valley Expanded`) : les instructions d'installation deviennent
      fausses. *Le plus grave — les autres dégradent la forme, celui-ci l'information.*
      ▸ **Conclusion** : `a` et `b` sont des défauts de **structure** (imbrication, bloc
      dans bloc) qu'une chaîne de `replacingOccurrences` ne peut pas traiter. Le correctif
      juste est un **petit tokeniseur récursif**, pas une regex de plus.
      `DescriptionBlockTests` existe déjà en Core : le chantier est testable. · **M**
      ▸ **Fait** : tokeniseur récursif (6 défauts a→f corrigés) **plus** un rendu typé — titres
      (typo AppDesign 20/16/14, garde-fou <80 char), listes (puces/numérotées), code (verbatim,
      défilement horizontal), citations, centrage (conteneur récursif), couleur d'auteur
      (contraste-corrigée AA) et vrai souligné. Vérifié sur les **51 descriptions en cache** :
      266 spans couleur rendus, 0 balise ou marqueur qui fuit.
- [x] **X4** ✅ *(corrigé, en attente de release)* — 🔴 **Toute archive créée sous Windows est refusée à l'installation.**
      **Cause racine confirmée** (reproduite sur `mods tests/RestAndRecover 49031 1.6.1 …zip`) :
      l'archive utilise des **antislashs** comme séparateurs de chemin. `/usr/bin/unzip`
      les convertit correctement — les 15 fichiers sont extraits, l'arborescence est
      juste — mais émet `warning: … appears to use backslashes as path separators` et
      **sort avec le code 1**. Or `ModZipInstaller.swift:410` exige `terminationStatus == 0`
      et lève `extractionFailed` sur une extraction réussie.
      ▸ **Correctif** : accepter 0 **et 1** (convention Info-ZIP : 0 = normal, 1 =
      avertissements, ≥ 2 = vraie erreur), puis valider sur le contenu extrait plutôt que
      sur le code de sortie. Même traitement à prévoir côté RAR.
      ▸ **Portée réelle** : ce n'est pas un cas isolé — la majorité des mods Nexus sont
      empaquetés sous Windows. · **S** · **priorité maximale**
- [x] **X5** ✅ *(corrigé, en attente de release)* — 🔴 **RAR non pris en charge dans le flux de mise à jour.**
      `NexusDownloader.swift:130` nomme *tout* téléchargement `UUID().uuidString + ".zip"`,
      quel que soit le format réel du fichier Nexus. `extractArchive` dispatchant sur
      l'extension, un `.rar` téléchargé part chez `/usr/bin/unzip` et échoue.
      ▸ **Correctif** : dériver l'extension du nom de fichier réel — il est déjà connu,
      `getModFiles` le renvoie avant le téléchargement — ou à défaut du chemin de l'URL
      CDN. Le glisser-déposer, lui, accepte bien les deux formats
      (`ModInstallView.swift:217`) : c'est le chemin *téléchargement* qui est en retard. · **S**
- [x] **X6** ✅ *(corrigé, en attente de release)* — **Tout le parcours d'installation parle de « zip » alors qu'il accepte
      aussi le RAR.** Ce n'est pas un libellé isolé : **8 clés sur 9** mentionnent le seul
      format zip, `mod_install_empty_hint` étant la seule à annoncer les deux. Le popup
      « Installer un mod » (`mod_install_drop_zone`) est simplement le plus visible.
      ▸ **Clés à reformuler** (`assets/{en,fr}.json`, parité obligatoire) :
      `mod_install_drop_zone` (529), `mod_install_analyzing` (531),
      `mod_install_dep_in_pack` (540), `mod_install_no_mods` (547),
      `mod_install_invalid_structure` (560), `mod_install_oversized` (561),
      `mod_install_too_many_mods` (562), `mod_install_corrupted` (563).
      ▸ **Principe** : parler d'**archive** plutôt que de « fichier zip » dans les messages
      d'erreur et d'analyse, et n'énumérer « .zip ou .rar » que là où l'utilisateur doit
      savoir quoi déposer. Ne **pas** toucher aux clés qui décrivent de vraies opérations
      zip (`settings_hint_compress_*`, `vm_unzip_error`, `smapi_payload_not_found`).
      ▸ **Bonus L10n** : `InstallError.rarToolMissing` (`ModZipInstaller.swift:778`) renvoie
      une phrase **codée en dur en anglais**, non localisée — à faire passer par `L10n`. · **S**
- [x] **X7** ✅ *(corrigé, en attente de release)* — 🔴 **La mise à jour d'un mod échoue si ses
      dossiers sont en lecture seule.** `unzip`/`unrar` restituent les bits de permissions stockés
      dans l'archive ; certains mods livrent leurs dossiers en `0o555` (lecture seule). Or supprimer
      le contenu d'un dossier exige l'écriture *sur ce dossier*, donc la suppression récursive
      échouait sur une arborescence que l'app venait d'écrire elle-même (« vous ne disposez pas de
      l'autorisation nécessaire »), sans issue depuis l'UI. Reproduit et vérifié sur **Tilly - NPC**
      (38008) : 174 entrées, tous ses dossiers en `0o555`, message d'erreur reproduit à l'identique.
      ▸ **Correctif** : normaliser les droits à l'extraction (`grantOwnerWriteAccess`) et retenter
      la suppression après réparation pour les dossiers installés avant le correctif
      (`removeItemGrantingWriteAccess`, site `ModZipInstaller.swift:714`). · **S**
- [x] **X8** 📝 *(spécifié le 2026-08-31, à livrer)* — **Le MAIN pris pour référence sur
      `files.json` peut être obsolète.** `NexusDownloadAPI.pickPrimaryFile(_:)`
      (`Models/NexusDownloadAPI.swift:58`) prend `list.files.first` — c'est-à-dire le
      premier renvoyé par l'API, sans garantie d'ordre temporel. Pour un mod à plusieurs
      fichiers MAIN (cas réel : auteur qui publie v1.0.0, v1.5.0, v2.0.0), la version
      retenue peut être une version passée. Le cache `ModUpdate.latestVersion` la
      propage ensuite jusqu'à la prochaine vérification réussie.
      *Livré le 2026-08-31 : `pickLatestMainFile` (filtre MAIN puis
      `max(uploaded_timestamp ?? 0)`, repli toutes catégories) branché dans
      `fetchModInfo` ; 5 tests, RED comportemental prouvé contre un stub avant
      l'implémentation. **Constat frère traité le même jour, à sa demande** :
      `resolveFileId` passe à `pickLatestMainFileId` — les téléchargements à
      `fileId: nil` (install direct `downloadModFromNexus` VM:5157,
      `installTranslation` VM:5953) prennent eux aussi le MAIN le plus récent
      (2 tests).*
      *Sonde live du parc le même jour (810 mods avec `files.json` exploitable,
      0 erreur d'API) : **33 mods à plusieurs MAIN** (29×2, 3×3, 1×4) —
      **tous** voyaient l'ancien picker se tromper, dont **19 avec un numéro
      de version différent** (Content Patcher 1915 comparé à 2.8.1 au lieu de
      2.9.1 ; le mod 2072 avait 1 233 jours d'écart ; le 50802 présentait
      v1 pour v5). Aucun mod sans timestamp : le tri a toujours de quoi
      s'appuyer. Deux « plus récents » sont des betas (2072, 8616) — l'auteur
      les a publiées en dernier, le picker suit.*
      ▸ **Cause** : aucun tri par `uploaded_timestamp` côté client ; l'ordre de
      l'API n'est pas contractualisé.
      ▸ **Correctif** : étendre `NexusModFile` avec `uploaded_timestamp`, ajouter
      `pickLatestMainFile(_:)` (filtre `categoryId == 1`, puis `max(uploaded_timestamp)`,
      avec repli sur l'ensemble si aucun MAIN), brancher dans
      `NexusUpdateChecker.fetchModInfo:608`. Cinq tests unitaires, ~55 min.
      ▸ **Référence retenue** (rejetée comme code à importer, conservée comme
      inspiration conceptuelle) : `jathych/Stardew-Valley-Mod-Updater/check_mods.py:81-93`.
      ▸ **Audit complet** : [`docs/spec-nexus-files-picker.md`](spec-nexus-files-picker.md).
      ▸ **Origine** : veille concurrentielle 2026-08-31. · **S** · *à traiter avant
      B2-T5 (dates affichées) — même surface, risque de pollution du cache identique.*
- [x] **X9** ✅ *(livré le 2026-08-31)* — **Le check compare le
      manifeste installé au libellé Nexus posé par l'auteur — deux
      vocabulaires différents.** Cas réel : ModCollectionAlbum (50802) —
      l'auteur a monté les libellés **1→5 en deux jours** (16–18 août, noms de
      zips sans version), en-tête du mod `version: "1"`, et le manifeste
      *dans* l'archive est resté **1.2.0** (constaté à l'installation par
      l'utilisateur). Résultat : « mise à jour vers 5 » **fantôme**, reproposée
      après chaque installation puisque le manifeste ne change pas — invisible
      chez SMAPI, qui compare manifeste à manifeste.
      ▸ **Correctif** (piste (a), raffinée en **égalité de fileId**) : quand
      l'app a téléchargé elle-même le fichier, l'ancre d'installation
      `ModVersionAnchor.nexusFacts` — champ présent depuis le lot C mais
      jamais renseigné — reçoit enfin l'identifiant et la date du fichier posé
      (remontés par `NexusDownloader.resolveFile` → `NexusDownloadOutcome`).
      La reprise Nexus (`NexusFallbackCheck.rows`) juge alors par le fichier :
      MAIN le plus récent == celui qu'on tient ⇒ rien à proposer, quel que
      soit le libellé ; MAIN **différent et plus récent** ⇒ ligne, même à
      libellé égal (re-publication à numéro constant — chaque fichier
      re-publié reçoit un nouvel id, l'égalité suffit, pas d'horloge) ; MAIN
      différent mais **pas plus récent** (l'auteur a retiré le nôtre) ⇒
      abstention. Sans faits (install manuelle), sans `files.json`, ou pour
      une autre page : la règle aux libellés d'avant. La piste (b) seule
      (ancrer le libellé auto) aurait réintroduit le défaut que les ancres
      remplacent ; la (c) existait déjà (« Je l'ai déjà »).
      ▸ **Périmètre v1** : la ligne fantôme 50802 transitait par la reprise
      Nexus (preuve : son `uploadedTime` renseigné — la voie smapi.io le
      laisse à `nil`), c'est elle qui est corrigée ; les liens `nxm://` et les
      installs multi-dossiers (packs) restent sans faits, et la voie smapi.io
      principale reste au libellé — elle lit l'en-tête de page et se tait
      déjà sur ce cas. `NexusArchiveName` n'y suffisait pas : le nom du zip de
      50802 ne porte aucune version. · **M**
      ▸ **Contraste sain** : les 4 autres lignes du check du 2026-08-31
      vérifiées réelles sur `files.json` (DaLion Core 2.2.5, Farmer's
      Notebook 3.8, Walk of Life 1.5.0-Beta3 — trois posées dans la journée —
      et Mastery Extended 2.3.0).
- [x] **X3** ✅ *(corrigé le 2026-07-30 par `8f0a81e`, sans être mentionné)* — **Bouton
      « Activer » de la page dépendances sans effet.** La piste consignée était la bonne :
      quand la dépendance est l'**enfant d'un pack**, `mod.folderName` désigne le dossier
      de l'enfant, absent de la liste de premier niveau. `performToggle` partait alors de
      ce dossier introuvable, et sa boucle de renommage sortait par `continue` — aucun
      déplacement, aucun message. Le commit a introduit `seedFolder`, qui remonte au pack
      propriétaire via `getTopLevelFolder(for: mod.uniqueId)`. Le message du commit ne
      parlant que du rendu BBCode, le correctif est passé inaperçu et n'a pas de ligne au
      CHANGELOG. Vérifié en conditions réelles par l'auteur le 2026-08-01 : les trois
      boutons de la page (Activer, Page Nexus, Rechercher) répondent.
- [x] **X10** ✅ *(corrigé le 2026-09-03 par `83328af` et `715c964`)* — 🔴 **L'accord en
      genre était traité comme une marque intouchable.** `${fermier^fermière}$` sélectionne
      un texte selon le genre du personnage joué : seules ses **bornes** sont des marques,
      son contenu est du texte affiché. Le découpage voilait le tout, avec deux
      conséquences mesurées sur le parc — la pré-traduction par lot enveloppait 45 052
      caractères (1 713 blocs de prose, 59 fichiers, 40 mods) dans une balise « à ignorer »
      et rendait la phrase anglaise telle quelle ; et le contrôle de marques comparait ces
      blocs au nombre, alors que le français en **ajoute** là où l'anglais reste neutre
      (211 sélecteurs côté source, 1 528 côté français). **1 092 des 4 331 lignes**
      signalées « marque perdue » étaient des traductions justes, refusées par
      `saveTranslation`, rejetées par le moteur DeepL et écartées par l'import de lot.
      **Oracle** : la localisation française du jeu (`Content/Characters/Dialogue/*.fr-FR.xnb`)
      traduit l'intérieur dans 10 cas sur 10, et fait passer un sélecteur à trois
      (`Abigail/summer_Tue4`). La levée s'arrête aux bornes et à leur `^` : l'exempter plus
      largement masquait 135 vraies pertes.
- [x] **X11** ✅ *(corrigé le 2026-09-03 par `a22d936`)* — 🔴 **Une version affirmée
      illisible vidait un lot de 150 mods.** « Je l'ai déjà » enregistre le numéro
      **affiché**, souvent l'étiquette libre d'une page Nexus (« 5 », « 1.01 »,
      « 1.0.4.1 »). Envoyée telle quelle à smapi.io comme `installedVersion`, elle fait
      rendre **HTTP 200 et une liste vide** pour tout le lot — sans erreur ni message.
      Le re-découpage de `SmapiUpdateClient` rattrape une entrée fautive isolée, mais
      son budget est de 32 requêtes pour toute la vérification : les 15 ancres de
      l'installation de l'auteur l'épuisent d'emblée. Rejoué avec son algorithme :
      **471 mods rendus sur 1 073**, **4 mises à jour visibles sur 7** (trois perdues
      avec leur lot), 40 requêtes au lieu de 8, et 2 entrées fautives nommées sur 15.
      Le champ est désormais
      traduit vers la grammaire que le serveur sait lire, relevée requête par requête
      contre l'API réelle ; vérifié de bout en bout, 1 073 réponses sur 1 073.
- [x] **X12** ✅ *(livré le 2026-09-03 par `b9653dc`)* — **« Je l'ai déjà » était un
      aller sans retour, et invisible.** Un clic, sans confirmation, éteint la ligne de
      mise à jour d'un mod **pour toujours** : rien à l'écran ne dit quels mods sont
      dans cet état, et `ModVersionAnchorStore.remove(uniqueId:)` — la fonction qui
      défait le geste — **n'a aucun appelant**. La seule sortie est de désinstaller le
      mod (`pruneAnchors` nettoie alors l'ancre). Sur l'installation de l'auteur, **34
      mods** sont éteints, dont plusieurs ont l'air accidentels : `Florian.TacticalEchoMines`
      affirmé en 1.3.0 quand le disque porte 0.1.0, `Cargvis.PathfinderValley` affirmé
      « 4 » pour un disque en 1.0.4.
      **Livré** : bloc repliable sur la page Mises à jour, **hors de la chaîne des
      états** — c'est quand la page annonce « tous à jour » que ces mods doivent se
      voir. Chaque ligne porte le numéro affirmé **et** celui du manifest, l'écart en
      orange, plus un bouton *Réafficher* qui câble enfin le `remove`. Une explication
      en tête du bloc dit ce que le geste a fait et ce que le bouton défait.
      `AffirmedUpdates` est en Core, testé.
      Écart assumé : *Réafficher* ne relance pas la vérification — le cache ne porte
      plus la ligne, et huit lots réseau sur un clic isolé seraient disproportionnés.
      La ligne revient à la prochaine passe, ce que dit le libellé d'aide. · **S**
- [x] **X13** ✅ *(livré le 2026-09-03 par `ed455ba`)* — **Rien ne disait qu'un dossier
      était disputé par deux mods.** `ModItem.folderName` est logique (le point de tête
      d'un mod en pause en est retiré) : `X` actif et `.X` en pause portent donc la même
      clé, et rien ne garantit que ce soit le même mod. Mesuré sur le parc : **1 075
      dossiers pour 1 074 noms logiques** — `[CP] Seaside Sounds` (witchtopia, actif) et
      son homonyme en pause (Liana) sont deux mods de deux auteurs.
      Le dégât irréversible est corrigé (`33bf00e` : la bascule refuse de déplacer le
      dossier d'autrui). **Reste ce que la collision fait en silence** : `ModItem.id`
      **est** `folderName`, donc les deux mods partagent une identité `Identifiable` et
      un `ForEach` n'en rend qu'un — l'un des deux est invisible dans la liste ; et
      identifiant Nexus, catégorie, favori, note, config de profil et poids sont
      partagés.
      **Livré** : une ligne d'avertissement sur l'écran Alertes système, alimentée par
      `ModFolderCollision.collisions`, qui nomme le dossier disputé et les deux
      identités. Son unique action **montre les deux dossiers dans le Finder,
      sélectionnés ensemble** — « Voir la fiche » prendrait le nom logique, c'est-à-dire
      la clé ambiguë elle-même, et ouvrirait l'un des deux au hasard. `warning` et non
      `critical` : le jeu tourne, l'un des deux porte un point de tête.
      ⚠️ **Ne pas « corriger » en changeant `ModItem.id`** : ce champ est la clé de tous
      les magasins persistés, ce serait une migration. · **S**
- [x] **X14** ✅ *(corrigé le 2026-09-03 par `078b692`)* — 🔴 **Deux sauvegardes
      différentes rendaient la même empreinte, et l'une était supprimée.**
      `FolderDigest` calculait le chemin relatif d'un fichier par un test de préfixe
      contre la racine **telle que donnée**, alors que `FileManager.enumerator` rend des
      chemins **résolus** : sur une racine passant par `/var` (lien vers `/private/var`),
      le préfixe échouait pour *tous* les fichiers et le repli ne gardait que le
      `lastPathComponent`. Deux arbres ne différant que par **quel** sous-dossier porte
      chaque fichier de même nom étaient donc jugés identiques — et l'empreinte décide
      de supprimer une sauvegarde jugée redondante.
      Résolu par `realpath(3)`, **pas** `resolvingSymlinksInPath()` : mesuré sur
      `temporaryDirectory`, celle-ci laisse `/var` non résolu et n'aurait rien changé
      (voir Traps, symlink `/var/folders`). · **S**
- [x] **X15** ✅ *(corrigé le 2026-09-03 par `800509e`)* — **Un champ composé de balises
      auto-fermées se lisait comme un scalaire — et l'écriture détruisait sa structure.**
      `SavePlayerFields.forEachDirectChild` vidait le nom en attente quand une sous-balise
      **s'ouvrait**, jamais quand elle était **auto-fermée** : la profondeur n'ayant pas
      bougé, un enfant de `<player>` composé de seules balises `<x/>` redevenait éligible
      à sa propre fermeture et entrait dans la table avec son markup entier pour valeur.
      `replacingDirectChild` acceptait alors d'écraser le composé par un scalaire, dans
      la sauvegarde écrite.
      **Mesuré sur la sauvegarde réelle `Zofia_443716371`** : 5 enfants directs de
      `<player>` sont composés uniquement d'auto-fermés — `shieldSlot`
      (`<Item xsi:nil="true" />`), `adventureBar` (16 sous-balises),
      `lastGotPrizeFromGil`, `lastDesertFestivalFishingQuest`,
      `SpaceCore_PersonalCurrencies`. Les champs consommés aujourd'hui (`gender`,
      `health`, `hair`…) sont tous scalaires : aucun changement sur les lectures
      existantes. · **S**
- [x] **X16** ✅ *(corrigé le 2026-09-03 par `c007ff3`)* — **Un `403` de lien expiré
      accusait la clé API.** Tout `403` de Nexus — sur `download_link.json` interrogé
      avec une clé `nxm://` comme sur le CDN du transfert — était rendu `authFailed`
      (« vérifiez votre clé API dans les Réglages »). Une clé `nxm` ne sert qu'une fois
      et se périme vite : le message envoyait réparer ce qui n'était pas cassé.
      Le même statut couvre trois pannes selon l'appel : `Forbidden403Meaning`
      (`premiumRequired` / `expiredLink` / `authProblem`) remplace le booléen
      `treatForbiddenAsPremium`, et le mapping statut → erreur est passé pur dans
      `NexusDownloadAPI.statusError` (cœur testable). · **S**
- [x] **X17** ✅ *(corrigé le 2026-09-03 par `7d4dfee`)* — **Déposer un contenu reconnu
      dans un hôte en 0555 échouait sans recours.** `DroppedContentRecognizer.install`
      écrivait par `createDirectory`/`removeItem`/`copyItem` nus, sans passer par
      `RecoveredFileWriter` — seul chemin de dépôt du dépôt à ne pas le faire, alors que
      `ManifestlessInstaller` le fait systématiquement. `unzip` restitue les modes des
      archives : un hôte revenu de mise à jour avec ses dossiers en 0555 refusait le
      dépôt (`EACCES`), panneau d'erreur sans issue.
      Mesuré : le mécanisme est vivant (`.[CP] Toothless Pet` porte 6 dossiers en 0555),
      mais l'hôte de l'unique règle actuelle (`ItemBags`) est inscriptible — défaut
      latent, pas ouvert. L'écriture est désormais enroulée dans
      `RecoveredFileWriter.withWriteAccess` (droits rendus tels quels, remontée bornée à
      l'hôte), et `destination(for:)` passe par `physicalFolderName`. · **S**
- [x] **X18** ✅ *(corrigé le 2026-09-03 par `f078244`)* — 🔴 **Le framework qu'exige un
      content pack manquait à ses dépendances, à l'installation.**
      `ModManifest.init(dict:)` lisait `Dependencies` par une boucle à lui, sans
      `ContentPackFor` — or c'est ainsi que la plupart des mods de contenu déclarent
      leur seule exigence — et sans déduplication, quand `ModDependencyParser` (le
      lecteur du scan des mods installés) fait les deux.
      Mesuré sur le parc (1 085 manifests) : **625 déclarent un `ContentPackFor`**,
      dont 254 sans aucune autre dépendance — annoncés « aucune dépendance » alors
      qu'ils ne font rien sans leur framework — et 340 avec une liste amputée de
      celui-ci ; les 31 restants le déclarent deux fois, et seule la déduplication
      les concerne (483 des 625 visent Content Patcher). Plus **8 manifests déclarant deux fois la
      même dépendance** : 13 lignes en double, et des `id` dupliqués au `ForEach`.
      Une seule lecture désormais, celle du parseur. · **S**
- [x] **X19** ✅ *(corrigé le 2026-09-03 par `013d5c5`)* — **Une dépendance installée
      dans un pack était annoncée manquante.** La feuille d'installation cherchait
      chaque dépendance parmi les seules lignes de premier niveau : un pack n'en occupe
      qu'une, ses composants vivant dans `children` — et ce sont eux que les autres
      mods réclament.
      Mesuré sur les 1 988 déclarations du parc : 1 012 trouvées, **296 désignant un
      composant de pack** (109 identifiants distincts — `FlashShifter.SVE-FTM`,
      `Rafseazz.RSVCC`, `ichortower.HatMouseLacey.Core`…) affichées en rouge avec une
      recherche Nexus proposée pour un mod déjà là, 13 désignant la racine d'un pack
      (hors d'atteinte : un en-tête de pack ne porte pas d'identifiant), 667 vraiment
      absentes. `ModZipInstaller.findExistingMod` cherchait déjà correctement : sa
      règle est devenue `Array<ModItem>.mod(withUniqueId:)`, testée, et ses trois
      appelants la partagent. · **S**
- [x] **X20** ✅ *(corrigé le 2026-09-03 par `bb0674b`)* — 🔴 **L'ancrage d'après-
      installation visait un dossier qui n'existe pas, pour un composant de pack.**
      `ModInstallView.installedFolderPaths` refaisait le calcul de destination de
      `ModZipInstaller.install` — troisième copie de cette règle — et divergeait deux
      fois : elle cherchait le mod déjà installé dans les seules lignes de premier
      niveau (jamais un composant de pack : **239 des 1 095 mods du parc**, 21 %), et
      reprenait le nom de dossier de l'archive au lieu de celui du mod installé.
      Les trois consommateurs de ces chemins (`recordNexusModId`,
      `anchorInstalledMods`, `reconcileManifestVersion`) lisent un `manifest.json` au
      chemin donné et **s'abstiennent en silence** s'il n'y a rien : mettre à jour un
      composant depuis `nxm://` ou le téléchargement intégré ne posait donc aucune
      ancre — la mise à jour restait annoncée après installation, et l'identifiant
      Nexus, connu à ce seul instant, était perdu.
      `install` rend désormais les chemins **réellement écrits**, chacun portant
      l'`id` de sa sélection ; la copie de la vue a disparu.
      ⚠️ **Le cas `.rename` reste écarté de l'ancrage** — c'était le comportement
      d'avant, pour une raison que le commentaire d'origine ne disait pas : une
      installation renommée laisse l'original en place, deux dossiers portent alors
      le même `UniqueID`, et une ancre est unique par identifiant. La première
      version du correctif (`bb0674b`) l'avait changé sans le mesurer ;
      `4196b12` rétablit l'abstention, cette fois sciemment. · **S**
- [x] **X21** ✅ *(corrigé le 2026-09-03)* — **L'app rendait la sauvegarde sans la
      marque d'octets que le jeu y met.** Stardew écrit ses fichiers en UTF-8 **avec**
      marque (`EF BB BF`) : mesuré, les 38 fichiers produits par le jeu sur le disque
      de l'auteur en portent une, et les seuls sans sont **trois copies réécrites par
      cette app** — 37 492 144 octets contre 37 492 147, à l'octet près.
      `String(contentsOf:encoding:)` la consomme au décodage,
      `write(to:atomically:encoding:)` ne la remet pas. Les **trois** chemins
      d'écriture étaient touchés : `updateSave`, `updateInventory`
      (`XMLDocument.xmlData`) et `modifyInternalSaveNames` — ce dernier servant la
      duplication et le branchement depuis une sauvegarde, sur le fichier **et** son
      `SaveGameInfo`.
      .NET lit l'UTF-8 sans marque : rien n'était cassé, et c'est pourquoi personne
      ne l'avait vu. Rendue symétriquement — un fichier qui n'en portait pas n'en
      gagne pas. · **S**
- [x] **X22** ✅ *(corrigé le 2026-09-03)* — **La restauration d'un composant de pack
      fabriquait un pack jumeau.** Un composant n'a pas d'état propre :
      `physicalFolderName` vaut `(isEnabled ? "" : ".") + folderName`, le scan classe
      la seule entrée de premier niveau et fait hériter cet état à chaque composant,
      et son sous-parcours passe `.skipsHiddenFiles`. Mesuré sur le parc : **869
      dossiers pointés au premier niveau, aucun composant pointé au second**.
      `restoreBackup` rendait pourtant un composant absent dans `.MonPack/Composant`,
      créant `.MonPack` à côté du `MonPack` actif — deux dossiers de même nom logique,
      ce que sa propre documentation interdit, et un mod restauré invisible du jeu
      comme de l'app. Sur les 38 noms de composants sauvegardés, 37 ont leur dossier
      en place (le cas déjà correct) ; le 38e, `Parchment/[CP] Parchment Example
      Pack`, est exactement celui-là. La destination suit désormais l'état du **pack
      sur le disque** ; sans pack, retour en pause comme avant. · **S**
- [x] **X23** ✅ *(corrigé le 2026-09-03)* — **Supprimer une sauvegarde de composant
      laissait son dossier horodaté vide.** `deleteBackup` et `cleanupOldBackups`
      prenaient le **parent** de `backupPath` ; pour `<horodaté>/Pack/Composant`, ce
      parent n'est que la coquille du pack. Mesuré sur le magasin réel : **1 262
      dossiers pour 922 entrées d'index**, soit 340 coquilles orphelines — dont **321
      vides**, la signature exacte de ce défaut (les 19 autres viennent des marches
      arrière traitées en X24) ; **373 des 922 entrées** en auraient produit une de
      plus. Le
      dossier est maintenant identifié par sa **position** (premier composant sous
      `backups/`, suffixe de nommage vérifié), avec repli sur l'ancien calcul pour une
      entrée qui ne s'y trouverait pas. Le suffixe UUID garantit qu'un dossier
      horodaté n'abrite qu'une sauvegarde : y remonter ne peut emporter la voisine.
      · **S**
- [x] **X24** ✅ *(corrigé le 2026-09-03)* — **Le ménage automatique ne réparait pas
      les droits avant de supprimer.** `deleteBackup` passe par
      `removeItemGrantingWriteAccess` — une sauvegarde hérite des permissions du mod
      copié, et le parc en compte en lecture seule ; `cleanupOldBackups` faisait la
      même suppression avec un `removeItem` nu. Copie amputée de la même règle :
      l'échec laissait (à raison) l'entrée d'index, donc ces sauvegardes revenaient à
      chaque passage sans jamais être reprises. **2 sauvegardes** du magasin réel sont
      dans ce cas. Deux autres sites partageaient le manque — les marches arrière de
      `createBackup` et de `registerSetAsideFolderAsBackup`, qui suppriment un dossier
      que `copyItem`/`moveItem` vient de remplir **depuis un dossier de mod**, donc
      avec ses modes. C'est l'origine des **19 coquilles non vides** du magasin, que
      X23 n'explique pas : nom plat (jamais un pack), quatre fois le même mod le même
      jour — la signature de tentatives répétées dont la marche arrière n'a rien pu
      effacer. · **S**
- [x] **X25** ✅ *(livré le 2026-09-04)* — **340 dossiers de sauvegarde orphelins
      restaient sur le disque**, séquelle de X23 (321) et de X24 (19) : vides ou ne
      portant qu'un dossier vide, ~0 octet, invisibles dans l'app. Un ménage
      automatique fondé sur « non référencé par l'index » était **dangereux tel
      quel** : `loadIndex()` rend un index **vide** dès que le fichier est illisible
      ou mal décodé — et ce magasin porte les traces d'écritures difficiles (un
      `install_metadata.json.sb-*` traîne à côté). Tout le parc passerait alors pour
      orphelin. Il inverserait aussi la règle que ce fichier énonce lui-même :
      *une suppression ne se décide jamais sur une absence.* Gain ≈ 0 octet.
      ▸ **Étendu le 2026-09-04, même famille** : les préférences portaient **35
      entrées mortes** — 19 horodatages d'activation et 16 identifiants Nexus pour
      des dossiers disparus, mesurés au moment de X55. Depuis X55 plus aucune ne
      s'ajoute (les deux chemins de `deleteMod` purgent, y compris celui du dossier
      déjà disparu, où l'utilisateur a **explicitement** demandé la suppression —
      c'est ce consentement qui manque à un balayage).
      ▸ **Livré par l'écran « Entretien »** (`MaintenanceView`, `MaintenanceInventory`
      en Core — 22 tests) : un inventaire mesuré sur le disque (923 sauvegardes
      d'installation, 1,80 Go ; garder 1 par mod libérerait 723 Mo ; **1**
      sauvegarde protégée, seule copie d'un fichier d'un mod désinstallé), trois
      crans de purge sous confirmation nominative (corbeille, pas suppression ;
      les protégées ne partent jamais), et le nettoyage explicite des orphelins et
      clés mortes — un bouton qui dit ce qu'il retire et attend un clic, jamais
      une passe au lancement. L'inventaire nomme les sessions par la même règle
      que la suppression (`backupDirectory(of:)`, rendu public pour l'occasion) :
      décrire et retirer ne peuvent pas diverger sur le nom d'un dossier.
      ▸ **Revue du 2026-09-04, suite à la livraison** : la revue de code a
      soulevé deux remarques. La première corrigée par `0b1ee17`
      (`@discardableResult` sur `recoverProtectedFile` : le `Bool` rendu
      était ignoré par l'écran alors que `recoverFile` porte déjà
      l'échec à l'utilisateur via un modal — la marque fait taire le
      warning proprement, comme `purgeInstallBackups` et
      `purgeProtectedBackup`). La seconde — accès concurrent à
      `ModInstallBackupManager.shared` depuis le `DispatchQueue.global`
      — était un faux positif : `backupsDirPath` est un `let` du
      manager et `backupDirectory(of:)` est une fonction pure sur
      l'`URL` stockée ; `loadBackups()` est de toute façon snapshotté
      avant l'`async` (signature de `readMaintenanceReport`). Pas de
      suivi, pas de fix. Règle pure (`MaintenanceInventory`, 22 tests)
      et code effectful du VM inchangés par ailleurs.
- [x] **X26** ✅ *(corrigé le 2026-09-04)* — **Le balayage des résidus posait deux
      questions au disque par entrée avant de regarder le nom.**
      `sweepJunkInsideMods` tourne à chaque scan de lancement (`includeRepair`
      vaut `true` par défaut) et parcourt tout l'arbre de `Mods/` : **93 784
      entrées** sur le parc de référence, dont **aucune** ne porte un nom de
      résidu. Chacune passait par `resourceValues` (lien symbolique) puis un
      `fileExists(atPath:isDirectory:)` — mesuré à **1,09 s** de `lstat` seuls.
      Les quatre gardes sont des `continue` conjoints : leur ordre est libre, et
      le test de nom, seul à ne pas toucher au disque, passe devant. Comportement
      inchangé, y compris `Icon\r` (dont `lastPathComponent` préserve le retour
      chariot — fixé par un test). · **S**
- [x] **X27** ✅ *(corrigé le 2026-09-04)* — **La garde du premier niveau du
      réparateur n'énumérait que les résidus *fichiers*.** `OSJunk.folders`
      contient `.Spotlight-V100` et `.Trashes`, pointés tous les deux : la
      condition `OSJunk.files.contains(entry) || hasPrefix("._")` les laissait
      donc passer pour des mods en pause, jamais mis en quarantaine. C'est
      littéralement l'amputation qui a fait naître `OSJunk` (voir son en-tête) —
      la copie avait survécu à la consolidation des données. Aucun exemplaire sur
      le parc : **défaut latent**, corrigé par cohérence, sans effet visible
      aujourd'hui. Remplacé par `OSJunk.isJunk`. · **S**
- [x] **X30** ✅ *(corrigé le 2026-09-04)* — 🔴 **Une réponse refusée par
      l'installateur SMAPI figeait l'app en avalant la mémoire.**
      `runOfficialInstaller` écrit ses quatre réponses puis ferme l'entrée
      standard, et lisait la sortie par `readDataToEndOfFile()`. **Vérifié en
      exécutant le vrai binaire 4.5.2** (téléchargé, lancé hors du jeu) : une
      réponse refusée le fait reboucler sur sa question à une entrée close —
      **119 827 838 octets en 20 s**, ~6 Mo/s, tous accumulés en mémoire, barre à
      80 %, sortie impossible sans tuer l'app. Lecture désormais bornée par
      `SmapiInstallerLimits` (1 Mo, 10 min), puis coupure : SIGTERM, attente
      **sans lecture** (une horloge consultée entre deux lectures bloquantes
      n'avance jamais tant que l'enfant parle — la première version du correctif
      rejouait ainsi la panne), `SIGKILL` après une seconde, et vidange une fois
      l'écrivain mort. Mesuré : SIGTERM tue l'installateur en plein flot en
      0,02 s. Message dédié qui pointe le chemin du jeu. `lastMeaningfulLine` déplacée en Core au passage : elle
      porte **tout** ce que l'utilisateur apprend d'un échec et n'était couverte
      par aucun test. ⚠️ Reste hors de portée : un installateur qui se tairait en
      restant bloqué — la lecture d'un tube ne rend la main qu'aux octets ou à sa
      fermeture. Non mesuré, inchangé. · **M**
- [x] **X33** ✅ *(corrigé le 2026-09-04)* — 🔴 **Le filet de la récupération de
      fichiers bloquait la récupération d'un mod en pause.** `recoverFile` prend un
      instantané de config avant d'écrire, par
      `createBackup(gameDir:mods:[mod])` — dont le défaut `onlyEnabled: true`
      filtre le mod nommément désigné. Pour un mod en pause : `.noEnabledMods`
      levée, capturée par le `catch` de `recoverFile`, modale « aucun mod actif à
      sauvegarder », **et le fichier jamais réécrit**. Mesuré : **527 des 593
      `config.json` du parc** sont dans un dossier en pause. `onlyEnabled: false`
      — le filtre n'avait rien à trancher sur une liste d'un seul mod choisi. · **S**
- [x] **X34** ✅ *(corrigé le 2026-09-04)* — 🔴 **La restauration d'une config
      écrivait au nom logique, la sauvegarde lisait le nom physique.** C4-T5 avait
      appris `createBackup` à lire `physicalFolderName` (point compris) ;
      `restoreBackup` est resté sur `folderName`. Pour un mod en pause, la
      configuration atterrissait dans un `Mods/Nom` **fabriqué** par
      `createDirectory(withIntermediateDirectories:)` à côté du `Mods/.Nom` réel :
      dossier sans manifeste, invisible du scan comme du jeu, configuration jamais
      restaurée — sous un message « sauvegarde restaurée ». Résolution physique
      partagée avec X22 (le point ne vit que sur l'entrée de tête, `.Pack/Composant`),
      et un mod absent est **sauté et journalisé** au lieu d'être fabriqué. L'écriture
      passe par `RecoveredFileWriter.write` : une seule règle pour « écrire un fichier
      dans un mod installé », droits compris (un `i18n/` en lecture seule existe sur
      le parc). · **M**
- [x] **X35** ✅ *(corrigé le 2026-09-04)* — **Le filet d'avant restauration ne
      couvrait pas ce qu'il écrasait.** `restoreBackup` prenait son instantané avec
      `onlyEnabled: true`, et `ModConfigBackupsView` lui passait `vm.enabledMods` :
      un mod en pause restauré était donc écrasé **sans aucune copie de secours**,
      silencieusement (l'appel est en `try?`). Les deux moitiés corrigées ; et
      l'instantané se limite aux mods réellement restaurés, ce qui lui évite un
      parcours complet de `Mods/` (93 784 entrées) pour des mods qu'on ne touche
      pas. · **S**
- [x] **X36** ✅ *(corrigé le 2026-09-04)* — **Un fichier impossible à écrire
      abandonnait toute la restauration de configs.** La documentation de
      `restoreBackup` promet qu'un fichier manquant est sauté sans interrompre le
      reste ; la promesse ne valait que pour les fichiers **absents**. Un fichier
      présent mais impossible à écrire (verrouillé `uchg`, propriétaire différent)
      faisait remonter l'erreur et abandonnait tous les `selectedItems` suivants.
      Antérieur à X34 — l'ancien `copyItem` levait pareil. Chaque fichier est
      maintenant tenté pour lui-même, échec journalisé. Cliquet `print_calls`
      20 → 21, même justification. · **S**
- [x] **X37** ✅ *(corrigé le 2026-09-04)* — **Une restauration de configs annonçait
      « restaurée » même quand elle avait tout sauté.** Les trois cas ignorés (source absente, mod plus installé,
      fichier non écrit) ne sont que journalisés : l'écran dit « Sauvegarde
      restaurée » sans distinguer 12 fichiers écrits de 0. Modèle à suivre :
      `ModInstallRestoreReport` (X22), qui rend ce qui a été écrit et où. `restoreBackup`
      rend désormais un `ModConfigRestoreReport` — fichiers écrits, mods restaurés,
      mods entièrement sautés, fichiers sautés — et l'écran n'annonce « restaurée
      avec succès » que sur un rapport `isComplete` ; sinon il nomme ce qui manque,
      et le journal passe en avertissement. `@discardableResult` : la valeur est un
      **ajout**, les dix appelants existants (dont les tests de la bascule en pause)
      gardent le comportement d'avant — c'est la réponse au « ce que les appelants
      tiennent pour acquis ». Cinq tests, dont quatre **vérifiés par mutation** :
      un rapport qui tait ses sauts les fait tomber. · **S**
- [x] **X42** ✅ *(corrigé le 2026-09-04)* — **Trois lectures divergentes du champ
      `Version` d'un manifeste**, alors que `ManifestVersionReader` a été écrit pour
      qu'il n'y en ait qu'une (son en-tête le dit). Pire : les deux chemins de
      `parseModFolder` divergeaient entre eux — le « cache chaud » passait par le
      lecteur commun (L. 2746), le « cache froid » relisait le champ à la main
      quarante lignes plus bas, si bien que le même mod pouvait rendre deux versions
      selon l'état du cache. `ModManifest.init(dict:)` portait la troisième copie.
      Divergences réelles sur les trois formes que SMAPI accepte : partie de version
      en chaîne (`"MajorVersion": "2"` → 1.0.0 par échec du `as? Int`), chaîne
      entourée d'espaces (gardée telle quelle), chaîne blanche (affichée, donc un
      « v » suivi de rien). **Aucun des 1 095 manifestes du parc ne les porte
      aujourd'hui** (mesuré) — le seul mod à version-objet, *LovedLabels*, n'a que
      des entiers : **défaut latent**, corrigé par cohérence, six tests le
      verrouillent. · **S**
- [x] **X44** ✅ *(corrigé le 2026-09-04)* — **Quel mod on trouve quand deux
      dossiers déclarent le même `UniqueID` dépendait de l'ordre du dossier
      `Mods/`.** `Array<ModItem>.mod(withUniqueId:)` promet en toutes lettres « un
      mod de premier niveau d'abord, puis les composants », mais faisait **une seule
      passe** : pour chaque entrée, elle-même puis ses composants. Un pack placé
      avant le mod autonome rendait donc le composant — et l'ordre vient de
      `contentsOfDirectory`, qui n'en garantit aucun. Cas réel du parc :
      `schulz.SexyCombatIdols` est installé deux fois, en mod de tête
      `.SexyCombatIdols` (v1.1.1) et en composant `.SexyCombatIdolsNEW/…` (v1.2.0).
      C'est ce mod que `findExistingMod` écrase et sauvegarde à la réinstallation, et
      celui dont les écrans de dépendances montrent la version. **Le test censé
      verrouiller la règle passait quel que soit le code** : il donnait au mod de
      tête la première place du tableau. Deux passes désormais, et deux tests —
      l'ordre inverse, et un composant seul à porter l'identifiant. · **S**
- [x] **X46** ✅ *(corrigé le 2026-09-04)* — **Une vérification amputée était
      enregistrée comme un passage réussi du parc entier.** `SmapiUpdateClient.fetch`
      envoie les mods par lots de 150 — **huit** pour le parc de référence — et
      s'arrête au premier lot en échec (`break`) : les suivants ne partent jamais.
      Elle rendait pourtant `.success(collected)`, indistinguable d'une passe
      complète, et le ViewModel y appelait `recordSuccessfulCheck()` — l'horodatage
      que `UpdateCheckPolicy` lit pour **couper la vérification automatique pendant
      12 h**. Un 503 au troisième lot laissait donc jusqu'à **795 mods** jamais
      interrogés, sans une ligne au journal et sans nouvelle tentative avant le
      lendemain. Ce qui n'était **pas** cassé, et qui a été vérifié : les lignes de
      mise à jour et les verdicts de compatibilité sont bien **fusionnés** et non
      remplacés (`unanswered`, et la boucle sur les seuls `mods` répondus) — le trap
      « une passe partielle fusionne avec le cache » est respecté ; et les mods sans
      réponse partent en reprise Nexus, donc ils ne sont pas muets — mais aux dépens
      du **quota Nexus**, là où smapi.io est gratuit et sans quota. `fetch` rend
      désormais un `Outcome` qui porte `batchesCompleted`/`batchesTotal` ; le TTL
      n'est posé que sur une passe complète, et l'incomplétude est journalisée.
      `SmapiUpdateClient.swift` est entré dans `Package.swift` à cette occasion — il
      n'avait aucune dépendance hors Core — et quatre tests l'éprouvent par un
      `URLProtocol` simulé. · **S**
- [x] **X48** ✅ *(corrigé le 2026-09-04)* — **Une branche du lancement pouvait
      laisser l'app sans aucune fenêtre.** `applicationWillFinishLaunching` pose un
      observateur qui masque la fenêtre principale **à chaque fois** qu'elle devient
      visible ; seul `LaunchSplashController.finish()` le détache et la révèle. Or
      le `.onAppear` de `MainView` a deux branches : si `isLaunching` est vrai il
      lève le splash (et le `.onChange` appellera `finish()`), sinon il ne faisait
      que délivrer les liens `nxm://` en attente — sans `finish()`, et le `.onChange`
      ne se déclenchera jamais puisque la valeur ne change plus. Fenêtre masquée à
      vie, et `applicationShouldTerminateAfterLastWindowClosed` à `false` empêche
      l'app de se refermer. **Inatteignable aujourd'hui** : `isLaunching` ne retombe
      qu'après un `DispatchQueue.global` puis un `asyncAfter(0.15)`, bien après ce
      `.onAppear` — la branche tenait donc à un délai de 150 ms. `finish()` est
      idempotent et documenté sûr avant tout `show()` : l'appeler là coûte une ligne
      et retire la dépendance au timing. · **S**
- [x] **X50** ✅ *(fait le 2026-09-04)* — **Tranche des fichiers racine de
      `StarHubTH/` terminée** : 26 fichiers, dont les neuf derniers
      (`ModInstallBackup`, `ModConfigBackup`, `AppDesignCore`, `NexusCategory`,
      `UDKey`, `SaveFarmerPalette`, `SaveFarmNameResolver`, `DictionaryExtensions`,
      `L10nResolver`) balayés par les Traps de `CLAUDE.md` — **aucun défaut**. Seule
      correction : deux commentaires annonçaient encore `"th"` parmi les langues
      d'interface, retirée depuis (`assets/` ne porte que `en.json` et `fr.json`) ;
      le hub de traduction traite toujours les mods thaï, ce sont deux notions
      distinctes. **Trois pistes mesurées et écartées**, à ne pas rouvrir :
      (a) `caseInsensitiveValue` rend une valeur **arbitraire** quand deux clés ne
      diffèrent que par la casse — `Dictionary.first(where:)` n'a pas d'ordre, et
      Swift sème son hachage à chaque lancement — mais **0 des 1 086 manifestes**
      du parc a de telles clés ;
      (b) le scan des raccourcis lit les `config.json` en UTF-8 strict, or les 11
      fichiers à marque d'octets du parc vivent tous dans des sous-dossiers que ce
      scan ne regarde pas ;
      (c) les deux `formattedDate` construisent un `DateFormatter` par accès, mais
      la liste des sauvegardes est **groupée par mod** dans un `LazyVStack` — pas
      922 lignes. Le seuil `whichFarm >= 8` de `SaveFarmNameResolver` est correct :
      SDV 1.6 compte bien huit fermes vanilla, Meadowlands incluse. · **S**
- [x] **X51** ✅ *(corrigé le 2026-09-04 par `b063085`)* — 🔴 **« Tout activer »
      supprimait définitivement le mod qui portait le même nom de dossier.**
      `toggleAllMods` écartait le dossier trouvé à destination sous `.stale_<uuid>`
      puis le supprimait, sans vérifier à qui il appartenait.
      `ModFolderCollision.isStaleDuplicate` existe depuis le 2026-09-03 pour
      exactement ça et le dit dans son en-tête, mais seul `performToggle`
      l'appelait. Mesuré sur le parc le jour même : `[CP] Seaside Sounds`
      (`witchtopia.SeasideSounds` 1.0.0, 360 Ko, actif) et `.[CP] Seaside Sounds`
      (`Liana.SeasideSounds` 1.1.0, 3,2 Mo, en pause) sont deux mods de deux
      auteurs — un clic effaçait l'un des deux, sans corbeille ni journal. Le refus
      est jeté et non sauté, pour qu'il entre dans `failures` et soit nommé au
      bilan. `applyProfileToFilesystem` n'a pas la garde non plus mais ne détruit
      rien : son `moveItem` échoue et est rapporté. · **S**
- [x] **X52** ✅ *(corrigé le 2026-09-04 par `48b1489`)* — **La vérification des
      mises à jour se déclarait terminée pendant la reprise Nexus.** Le
      relâchement de `isCheckingNexusUpdates` en fin de `group.notify` — placement
      délibéré, commenté comme empêchant un re-déclenchement — écrasait le `true`
      que `recheckBlockedViaNexus` venait de poser, la reprise démarrant *dans*
      `applySmapiResults`, appelé depuis ce même bloc. Bouton « Vérifier » de
      retour et second passage possible par-dessus, sur le quota Nexus.
      `nexusFallbackInFlight` porte l'état, baissé en tête de
      `finishNexusFallback` pour couvrir ses deux sorties. · **S**
- [x] **X53** ✅ *(corrigé le 2026-09-04 par `48b1489`)* — **Le hub thaï cherchait
      sous le nom logique.** `Mods/<folderName>/i18n/th.json` au lieu de
      `physicalFolderName` (AGENTS.md §4.1). Mesuré : **22 des 30 `i18n/th.json`**
      du parc sont sous un dossier de tête en pause, donc annoncés « non
      installés » et rétrogradés par le tri. · **S**
- [x] **X56** ✅ *(corrigé le 2026-09-04)* — **Le filet de compatibilité était
      muet sur les mods dont il ne connaît que la mise à jour non officielle.**
      `PathoschildCompatibilityList.Entry` lisait `id`, `status`, `brokeIn`,
      `summary`, `nexusID` ; le dump (4 720 entrées) porte aussi
      `unofficialUpdate` (67), `abandonedReason` (277) et `warnings` (24).
      **Le constat d'origine visait les trois champs ; la mesure a montré que
      seul le premier valait quelque chose, et pas pour la raison écrite ici.**
      ▸ **Ce que la mesure a trouvé.** Des 67 entrées à `unofficialUpdate`,
      **63 n'ont aucun `status`** et 62 aucun `summary` — les 67 ont un
      `brokeIn`. Le verdict se construisant à partir du seul `status`, ces 63
      entrées ne produisaient **rien** : le filet se taisait exactement là où
      smapi.io, sondé le même jour sur les mêmes identifiants, répond
      `Unofficial` + « broken, use unofficial version ». Sur le parc, quatre
      mods invisibles dès que smapi.io se tait : Bus Locations, Mod Update Menu
      et les deux moitiés de SAAT.
      ▸ **Livré.** Un `unofficialUpdate` sans statut vaut `unofficial` — la
      règle que la liste amont applique elle-même. Un statut déjà posé n'est
      **jamais** écrasé (4 des 67 en portent un, dont un `abandoned` : le
      rétrograder en « une mise à jour existe » perdrait plus que l'inférence
      ne gagne), un statut inconnu reste `nil`, et le seul `brokeIn` n'invente
      pas de verdict. Aucune phrase n'est fabriquée pour les 62 sans résumé :
      le libellé du statut et `brokeIn` sont déjà rendus localisés, et le lien
      porte le **numéro de version** pour libellé, ce qu'il faut installer.
      L'unique entrée à résumé sans statut (`Lajna.24hClock`) cite déjà l'URL
      de sa mise à jour — pas de troisième bouton, l'UI n'en montre que deux.
      Rejoué sur le dump réel : **+63 verdicts au dump, +4 sur le parc, zéro
      verdict modifié**. Aucun écran neuf, aucune clé L10n.
      ▸ **Ce qui a été mesuré puis écarté.** `abandonedReason` accompagne
      **toujours** un statut `abandoned` (277/277) déjà rendu, et zéro mod du
      parc en porte : rien à gagner qu'une phrase non traduite. La jointure,
      elle, est **close** : jouée à la manière de SMAPI (découpage des `id` en
      liste, insensible à la casse) elle gagne 32 appariements et **aucun**
      champ neuf — la mesure de 2026-09-03 vaut aussi pour ces trois-là. · **S**
- [x] **X55** ✅ *(corrigé le 2026-09-04)* — **Le ménage à la suppression d'un mod
      était partiel.** `deleteMod` purgeait les favoris, l'historique d'erreurs, la
      référence de traduction et la couverture FR, mais laissait quatre magasins
      indexés sur le même nom de dossier — `profileManagedConfigMods`,
      `modActivationTimestamps`, `nexusCustomModIds`, `nexusCustomCategories` — plus
      la présence du mod dans « Je l'ai » de la vitrine (`recentNexusInstalls`,
      indexé sur l'identifiant Nexus).
      ▸ **Mesuré sur les préférences réelles le 2026-09-04** : **35 entrées
      fantômes** — 19 horodatages d'activation et 16 identifiants Nexus pour des
      dossiers qui n'existent plus (`[CP] ArchaeologySkill`, `Swim`,
      `MoreSecretNotes/PEEM`…). `favoriteMods` était propre : sa purge, elle,
      existait déjà.
      ▸ **Politique tranchée : on efface tout.** Ce qu'on supprime disparaît, et une
      réinstallation repart d'une page blanche. L'alternative — garder ce qui décrit
      le mod (identifiant Nexus, catégorie) et n'effacer que ce qui suit le dossier —
      laissait deux traces que rien ne nettoie jamais, pour épargner une ressaisie
      rare.
      ▸ `ModRemovalPurge` (Core, 9 tests) porte la règle : un pack emporte ses
      composants (leur `folderName` est le chemin relatif sous lui) **sans toucher au
      voisin dont le nom commence pareil** — supprimer `Pack` laisse `PackDeLuxe`.
      Le nom comparé est le **logique** : `.Pack` n'est pas ramassé au passage, ce
      serait l'entrée d'un autre mod. Chaque magasin n'est réécrit que s'il a changé.
      ▸ **Le retrait de `recentNexusInstalls` est sans risque** malgré les 58
      identifiants Nexus partagés du parc : `installedNexusIds()` en fait l'union
      avec les mods réellement installés, donc celui qui reste se voit par l'autre
      moitié.
      ▸ **Les deux chemins de `deleteMod` purgent**, y compris celui où le dossier a
      déjà disparu hors de l'app (Finder, mise à jour ratée) : c'était le producteur
      de traces mortes, puisqu'il ne touchait aucun magasin. Ce n'est pas le balayage
      que X25 interdit — là-bas une absence déciderait seule d'une suppression, ici
      l'utilisateur vient de demander la suppression de ce mod nommément.
      ▸ **Non fait, et volontairement** : les 35 fantômes déjà en place restent. Les
      balayer demanderait de décider qu'un dossier absent est un dossier supprimé —
      c'est très exactement ce que **X25** interdit, et un dossier `Mods/` non scanné
      ou un jeu déplacé effacerait des réglages vivants. À traiter comme un ménage
      explicite, jamais comme un automatisme. · **S**
- [x] **X57** ✅ *(corrigé le 2026-09-04)* — **La bascule en masse agissait sur
      le parc entier, depuis une liste filtrée.** Le bouton « Tout activer /
      Tout désactiver » vit dans `ModListView` — qui a une recherche, des
      catégories et une pagination à 15 — mais `toggleAllMods` parcourait
      `mods` en entier, **949 dossiers de tête** : filtrer sur « Content
      Patcher » puis cliquer « Tout désactiver » désactivait le parc. La règle
      de Stardrop (`c630c11`, 2026-09-01) est appliquée : *« what the user is
      looking at is what they act on »*. Le prédicat de cadrage (cinq filtres,
      tri, scope) a déménagé de la vue vers le ViewModel —
      `mods(matching:)` + `scopedMods(from:scope:)` — et liste comme bascule
      dérivent de la même source, évaluée sur `modList.filters` au moment du
      clic. La pagination n'entre pas dans la règle : artefact d'affichage, la
      bascule agit sur tout le résultat filtré, pas sur la page visible. Le
      menu grise ses entrées selon le cadrage courant (une entrée disponible
      dit ce qui bougerait), et le dialogue de confirmation annonce le compte
      exact. La garde de collision de **X51** est intacte — un refus sur les
      mods cadrés se lit là où il se noyait dans un bilan de huit cents
      déplacements. · **M**
- [x] **X58** ✅ *(livré le 2026-09-05)* — **`warnings` méritait un filtre de
      plateforme, pas un rejet.** Le champ existait sur 24 des 4 720 entrées du
      dump Pathoschild et l'app le jetait entièrement : télémétrie non divulguée
      et non annoncée sur la page du mod, plantages au chargement d'une
      sauvegarde, archive à la structure fausse qu'il faut dézipper deux fois,
      incompatibilité multijoueur — rien de tout ça n'était dit nulle part.
      ▸ **Pourquoi on ne pouvait pas simplement l'afficher** : **17 des 24 ne
      parlent que d'Android**. Les remonter tels quels ferait contredire la
      source primaire — smapi.io déclare `Ok` les deux mods du parc concernés.
      `ModPlatformWarnings` tranche : on n'écarte que sur un signe **positif**
      qu'il s'agit d'ailleurs, et la mention de notre plateforme **annule**
      l'écart (« Broken on Android and macOS » est gardé). Le corpus se répartit
      exactement comme la mesure d'août l'annonçait — 17 + 1 renvoi vers un autre
      magasin de téléchargement écartés, **6 gardés** — et un test épingle ce
      compte : s'il bouge, c'est la règle ou le dump qui a changé.
      ▸ **Le piège de la sous-chaîne** : « ios » vit dans « ratios » et
      « kiosk », « mac » et « pc » sont tout aussi courts. Un faux positif du
      côté « plateforme étrangère » **masque** un avertissement réel : la
      recherche se fait en mots entiers, avec le test qui le prouve.
      ▸ **Où ça se dit** : une ligne de l'écran d'alertes, en gravité `info` —
      la seule que `actionableCount` ne compte pas, donc la pastille de la barre
      latérale ne s'allume jamais pour ça. Le détail nomme sa source et dit que
      le mod n'est pas déclaré cassé, sans quoi la ligne se lirait comme un
      verdict. Le balisage Markdown passe par `ModCompatibility.parseSummary`,
      déjà écrit pour le champ voisin du même dump — pas de seconde règle.
      ▸ ⚠️ **Zéro ligne sur le parc de référence**, et c'est le résultat correct :
      les deux mods concernés (`Automatic Gates`, `Bigger Backpack`, tous deux en
      pause) portent l'un « Broken on Android », l'autre « use Nexus, ModDrop is
      NOT updated ». Une ligne apparaîtrait en installant l'un des six —
      `Dissolver Enhanced` (télémétrie) ou `Entoarox Utilities` (plantages au
      chargement) par exemple.
      ▸ Lecture du dump **quel que soit son âge** : un avertissement d'il y a
      trois jours reste vrai, et le lier au TTL de 6 h ferait disparaître ces
      lignes 18 heures par jour. **18 tests neufs** (2 215 → 2 233). · **S**
- [x] **X72** ✅ *(corrigé le 2026-09-05, tranché par l'auteur)* — **Le
      renommage offert à un composant de pack en collision était mort par
      construction.** Les revendications de collision sont bâties sur
      `flattenedMods`, où les composants figurent sous la forme
      `Pack/Composant` ; `folderCollisionIssues` offrait `.renameFolder`
      sans condition. Mais la feuille cherche ses prétendants dans `vm.mods`
      (entrées de tête seulement) : zéro prétendant pour un nom de composant
      → « le nom est vide » à l'ouverture, bouton désactivé pour toujours —
      et `validate` refuserait de toute façon le `/` de la saisie.
      ▸ **Tranché avant de coder, comme l'exigeait le constat** : supprimer
      l'action pour les noms contenant `/`, plutôt que construire un
      renommage de composants — qui exigerait d'abord de débloquer le cas
      latent X28 (composant en pause dans un pack actif, que
      `physicalFolderName` ne sait pas exprimer) pour ne pas bâtir un chemin
      qui casse sur lui. Zéro occurrence sur le parc ; la ligne de collision
      et la révélation Finder restent. La frontière est la barre oblique du
      nom disputé, pas une garde dérivée du refus de saisie. **1 test
      neuf** (2 297 → 2 298). · **S**
- [x] **X32** ✅ *(corrigé le 2026-09-06)* — **L'installateur SMAPI accepte
      `--install` / `--uninstall` / `--game-path`.** L'app répondait à l'aveugle
      à une séquence de questions dont l'ordre était supposé stable — quatre
      réponses d'un coup sur stdin (`1` couleurs, `2` chemin personnalisé, le
      chemin, l'action) — c'est ce qui rendait X30 possible.
      ▸ **Le constat disait « impossible depuis un agent » : démenti par
      l'expérience.** Une installation de contrôle a été montée en /tmp —
      dossier factice avec `Stardew Valley` (lanceur exécutable),
      `Stardew Valley.dll`, `.deps.json`, `.runtimeconfig.json`, composition
      découverte par les messages d'erreur de l'installateur lui-même (« That
      directory doesn't contain a Stardew Valley executable », puis
      `FileNotFoundException` sur `.deps.json`) — et le vrai binaire 4.5.2
      téléchargé de sa release GitHub y a été lancé, comme X30 l'avait fait
      avant. ⚠️ Leçon d'exécution : un binaire .NET **ignore SIGPIPE** —
      `| head -c` ne le tue pas, il faut un kill -TERM temporisé explicite
      (l'incident a coûté 1,4 Go de flot sur la première mesure).
      ▸ **Mesuré sur le vrai binaire** : `--install --game-path P` → « Just
      one question first » (le jeu de couleurs, notre `1`), « That's all I
      need! I'll install SMAPI now. », « SMAPI is installed! », exit 0, même
      attelage posé qu'en mode interactif (`Mods/`, `smapi-internal/`,
      `StardewModdingAPI*`, mods groupés). `--uninstall --game-path P` →
      « SMAPI is removed! », `Mods/` conservé. `--install --uninstall` →
      refus propre immédiat. Dossier sans jeu → « Failed finding your game
      path. » et **sortie** — plus de rebouclage de question, l'amorce de X30
      ne peut même plus s'armer par un mauvais chemin. Exit code **0 même en
      échec** : le critère de réussite (message + preuves disque) reste le
      bon.
      ▸ **Le contrat vit en Core** (`SmapiInstallerInvocation` + 
      `SmapiInstallerAction`) : arguments de drapeaux, chemin brut sans
      quoting (`Process.arguments` n'est pas un shell — l'espace de « Stardew
      Valley.app » passe tel quel, épinglé par test), réponse couleurs. La
      garde de lecture bornée de X30 est conservée telle quelle.
      ▸ **Constat neuf ouvert en échange : X77** — l'installation de contrôle
      a montré qu'une installation **propre** ne pose pas
      `StardewValley-original`, que `getInstalledVersion` et la garde
      d'uninstall exigent : une installation propre est indétectable par
      l'app. Voir la roadmap.
      **4 tests neufs** (2 310 → 2 314). Deux gates verts. · **M**
- [x] **X29** ✅ *(corrigé le 2026-09-06)* — **La détection de doublons sur
      disque n'a aucun appelant en production.** Le ViewModel passe
      `detectDuplicates: false` et utilise la version en mémoire — la version
      disque gardait donc sa propre lecture de manifeste (regex de
      commentaires bloc + `.json5Allowed`), quatrième copie d'une règle
      consolidée dans `ManifestJSON.decode`.
      ▸ **Le tranchage qu'exigeait le constat, par la mesure** : « unifier
      serait un changement de comportement sur un chemin sans appelant » —
      la parité des deux lectures a été **mesurée sur le parc réel avant de
      décider** (harnais compilant le vrai `ManifestJSON.swift` + la
      réplique exacte de la lecture maison, exécuté sur les manifestes du
      dossier de jeu) : **1 101 manifestes, 1 101 identiques, 0
      divergents**, dont 4 muets des deux côtés. Unifier n'est plus un
      changement de comportement hypothétique : c'est un no-op mesuré.
      ▸ **La fonction et son défaut `true` restent** : `repairIfNeeded` est
      un type autonome par design, ses appelants standalone (et les tests)
      gardent la détection complète. Seule la copie de lecture part —
      remplacée par `ManifestJSON.decode`, la même grammaire que le scan,
      l'installation et la sauvegarde. Une grammaire commune n'est pas un
      détail : un manifeste JSON5 exotique que seule une voie décoderait
      serait invisible du scan mais compté par la détection — exactement
      la divergence silencieuse que le constat refusait de créer à moitié.
      ▸ **La divergence théorique, épinglée par test** : la regex maison
      strippait `/* … */` **aveugle au contexte des chaînes** — un
      identifiant contenant le marqueur était amputé (« a/*keep*/b » lu
      « ab »). Zéro manifeste du parc ne porte le cas ; le test rouge-vert
      épingle le mécanisme désormais conforme au scan. **1 test neuf**
      (2 309 → 2 310). Deux gates verts. · **S**
- [x] **X45** ✅ *(corrigé le 2026-09-06)* — **Le dépliage des packs a
      encore dix copies manuelles.** `flattenedMods` affirmait dans son
      propre en-tête avoir remplacé les 22 réécritures de 2026-08-01 ; il
      en restait dix, revérifiées une à une avant d'agir (les lignes du
      constat avaient dérivé, et une copie du décompte vivait sur deux
      lignes dans `FavoriteResolution`) : trois sur un tableau complet
      (VM — registre d'install, ancres de profil éphémère de bissection,
      cibles de config gérée), sept sur un mod isolé (VM ×2,
      `BisectionRunner` ×2, `ModFolderRepairer`, `ModGridCardValues`,
      `FavoriteResolution`).
      ▸ **L'API manquante, pas juste les appels** : la forme à un seul mod
      n'était couverte par rien — `ModItem.components` naît : un pack rend
      ses composants, un mod autonome se représente lui-même. Et
      `flattenedMods` devient `flatMap(\.components)` : la brique et sa
      version tableau ne peuvent plus diverger.
      ▸ **Une onzième, non comptée par le constat** :
      `DroppedContentRecognizer.allMods(in:)` réécrivait `flattenedMods`
      entière en forme `guard` — même brique, retirée au passage (un seul
      appelant).
      ▸ **Resté tel quel, à dessein** : VM L.5497 (`children?.first ??
      mod`) prend le *premier* enfant, pas tous — sémantique différente,
      pas une copie de dépliage.
      ▸ Refactor pur, rien à l'écran — pas d'entrée CHANGELOG.
      **5 tests neufs** (2 304 → 2 309) : les quatre cas de `components`,
      dont le groupe sans `children` que chaque copie protégeait par son
      `?? []`, et la parité avec `flattenedMods`. Deux gates verts. · **S**
- [x] **X43** ✅ *(corrigé le 2026-09-06)* — **Le dialogue de conflit de
      configuration est mort dans sa totalité.**
      `ConflictType.configFilesConflict` et `.dependencyMissing` n'avaient
      **aucun site de construction** ; `ConfigResolution` (`keepExisting`,
      `useNew`, `merge`) n'était jamais posé — `InstallSelection
      .configResolution` valait `nil` à tous les sites de l'UI, qui se
      contentait de le recopier, et `ModZipInstaller` ne le lisait nulle
      part ; `ConflictResolution.keepExisting`/`.useNew` étaient traités
      dans un `switch` mais jamais construits.
      ▸ **Résidu d'une bascule de conception** : demander à l'utilisateur
      ce qu'il veut faire de son `config.json` a été remplacé par la
      préservation automatique (`snapshotUserConfigs` dans
      `ModZipInstaller`), qui est le bon comportement et fonctionne. Le
      retrait, fait d'un bloc comme l'exigeait le constat, emporte les
      deux cas morts de `ConflictType`, les deux cas morts de
      `ConflictResolution` (le `else` voisin du switch faisait déjà la
      même chose), l'`enum ConfigResolution` entier et le champ
      `InstallSelection.configResolution` : 4 sites d'`InstallPreview`,
      17 sites de tests.
      ▸ **Rien ne change à l'écran** — le dialogue n'a jamais été affiché ;
      pas d'entrée CHANGELOG. Ce qui reste vivant : `folderExists` et
      `overwriteWithBackup`/`.rename`/`.skip` (le dialogue de collision
      réel), l'affichage des dépendances manquantes d'`InstallPreview`
      (vit ailleurs), et le `keepExisting` de `SmapiUpdateRequest` — un
      autre type, vivant lui.
      **2 304 tests inchangés et verts** (retrait de code mort). · **S**
- [x] **X28** ✅ *(corrigé le 2026-09-06)* — **Un `__MACOSX` niché dans un
      mod perd ses fichiers mais garde son dossier.** Le balayage profond ne
      déplaçait que des fichiers (`if isDir { continue }`) et la passe de
      premier niveau ne traite `OSJunk.folders` qu'à la profondeur 1 : un
      `__MACOSX` à l'intérieur d'un dossier de mod voyait ses fichiers mis
      en quarantaine un par un, et la coquille restait indéfiniment.
      ▸ **Le geste du premier niveau, sans sa limite de profondeur** : le
      dossier de résidu niché part **en bloc** — son contenu est du résidu
      par construction, le balayer fichier par fichier ne laisse qu'une
      coquille. `enumerator.skipDescendants()` empêche d'énumérer les
      entrées d'un dossier déjà déplacé. Un dossier de résidu à la
      **racine** de `Mods/` n'est pas traité deux fois : la passe profonde
      tourne avant celle de premier niveau, qui ne revoit pas un dossier
      déjà parti.
      ▸ **La coquille déjà vidée par les versions précédentes part elle
      aussi** : leurs balayages emportaient les fichiers, jamais le
      dossier — c'était la trace visible du défaut chez qui l'a déjà
      rencontré (testé).
      ▸ **Le voisin qui ne doit pas partir ne part pas** : un lien
      symbolique nommé `__MACOSX` ne déplace pas ce qu'il désigne — la
      règle du balayage fichiers vaut pour les dossiers (testé).
      ▸ **Zéro exemplaire sur le parc de référence** — latent, comme le
      disait le constat ; la gâchette est une extraction dont le
      `__MACOSX` atterrit à l'intérieur du dossier du mod.
      **3 tests neufs** (2 301 → 2 304). · **S**
- [x] **X47** ✅ *(corrigé le 2026-09-05)* — **Un lot smapi.io en échec ne
      sacrifie plus les lots suivants.** Le `break` du premier lot fautif
      renonçait aux lots restants, que rien n'incriminait : sur les huit lots
      du parc de référence, un 503 ponctuel au troisième livrait **795 mods**
      à la reprise Nexus (quota compté) là où smapi.io les aurait couverts
      gratuitement. Le choix d'origine protégeait d'une rafale contre une API
      publique gratuite — la nouvelle politique garde la protection et rend
      les lots : **continuer** au suivant, puis **une** seconde chance au
      fautif en fin de passe, après un retrait de 5 s. Une seule : réessayer
      indéfiniment cognerait ce que le code s'interdit déjà de paralléliser.
      ▸ **Ce qui ne relève pas** : une erreur de **décodage** est
      déterministe — les mêmes octets reviendraient —, aucune seconde chance
      pour elle ; un lot **abandonné** par budget de re-découpage épuisé
      (X64) non plus, le budget est consommé. Les lots sains partent quand
      même après un abandon : un budget épuisé condamne le découpage, pas un
      lot d'une requête qui peut très bien revenir.
      ▸ **`Outcome` dit la cause** : un compte de lots n'explique pas
      pourquoi une passe est amputée. `Outcome.failure` porte la **première**
      défaillance de la passe — choix déterministe, le journal de l'appelant
      n'y verrait sinon que l'ordre d'un dictionnaire.
      ▸ Le retrait vit derrière `retryPause` (5 s en production, 0 dans les
      tests) ; son `Task.sleep` est en do/catch, pas en `try?` — une
      annulation dit que la seconde chance n'a pas d'auditoire, l'avaler et
      retenter quand même serait pire que le silence (leçon X69, le cliquet
      a confirmé). **3 tests neufs** (2 298 → 2 301). · **S**
- [x] **X76** ✅ *(corrigé le 2026-09-05)* — **Un index qu'on n'a pas lu ne
      rend pas orphelines les sauvegardes qu'il référence.**
      `loadIndex` rendait un index vide pour trois états distincts — premier
      lancement, fichier absent, fichier corrompu — et `readMaintenanceReport`
      calculait les orphelins par différence `onDisk − referenced` : index
      corrompu ⇒ `referenced` vide ⇒ **les 203 sessions réelles du parc
      passaient pour des dossiers que l'index ignore**, exactement la famille
      que le bouton « nettoyer » (X25) existe à corbeiller. Un clic les y
      envoyait toutes ; la corbeille était le seul filet.
      ▸ **Pourquoi la garde ne pouvait pas être heuristique** : les 340
      orphelins légitimes de X25 existent **avec un index intact** qui
      référence les vraies sauvegardes. Distinguer « index vide de corruption »
      de « index sain, orphelins réels » ne peut pas se faire sur les lots —
      seul l'**état de lecture** tranche.
      ▸ **La règle** : `loadBackupsWithIndexState()` rend un `BackupsRead`
      qui dit si un index a été décodé — absent et corrompu sont les deux
      faces du même « non » (un index supprimé sous des sauvegardes présentes
      est le même danger) ; `orphanSessions(indexWasReadable:)` ne rend
      rien sans lecture, et le journal dit la différence entre « rien à
      nettoyer » et « je n'ai rien pu lire » — la leçon de X70, appliquée au
      troisième lot de l'écran. **5 tests neufs** (2 292 → 2 297). · **S**
- [x] **X75** ✅ *(corrigé le 2026-09-05)* — **Le `i18n/fr.json` d'un mod ne
      doit pas être reclamé parce qu'un *autre* mod a sa traduction au même
      chemin.** `installedTranslationRelativePaths()` aplatissait les chemins
      de **tous** les hôtes du registre en un seul ensemble, et `walkBackup`
      appariait chaque fichier de chaque sauvegarde par suffixe contre lui.
      L'hôte de la sauvegarde — `originalFolderName`, connu avant la
      traversée — était ignoré.
      ▸ **Mesuré sur le parc** : 4 hôtes portent `i18n/fr.json` dans le
      registre, donc **59 fichiers d'auteur** sur les 203 sauvegardes
      étaient étiquetés « traduction posée par l'app ». Aucun ne l'était.
      ▸ **La chaîne de conséquence quand elle s'arme** : un fichier
      `.translation` d'un mod désinstallé compte comme manquant
      (`installedState` rend `presentFiles == nil` → tout manque) → la
      sauvegarde devient `.soleCopy` → protégée, impurgeable, affichée
      « seule copie », proposée à la récupération. **Zéro aujourd'hui** (les
      trois mods Zebrus de la mesure du 04-09 ont été réinstallés depuis —
      vérifié), donc latent, même classe que X28 — mais sa gâchette est un
      simple `keepPerMod` au-dessus du nombre de sauvegardes.
      ▸ **La règle de suffixe ne peut pas distinguer les hôtes** — c'est
      vérifié par le test qui a échoué : la première fixture exigeait
      l'impossible d'elle. Le correctif vit donc dans le **bornage** :
      l'appariement se fait contre les seuls chemins de l'hôte de la
      sauvegarde, la règle de classification est extraite dans Core
      (`MaintenanceInventory.classifyUserFile`). **8 tests neufs**. · **S**
- [x] **X74** ✅ *(corrigé le 2026-09-05)* — **Une préférence posée sur un pack
      passait pour morte.** `buildMaintenanceReport` bâtissait son
      `installedFolders` sur `mods.flattenedMods`, qui **remplace** un pack par
      ses composants : l'en-tête n'y figure pas. Toute clé portant le nom d'un
      pack installé était donc jugée orpheline par
      `MaintenanceInventory.stalePreferenceKeys`, montrée comme telle, et
      effacée au clic sur « nettoyer ».
      ▸ **Ce n'est pas un cas tordu, c'est le geste recommandé.** La fiche d'un
      pack offre le champ « identifiant Nexus » et le sélecteur de catégorie —
      ni l'un ni l'autre n'est conditionné à `!isGroup`, vérifié dans
      `ModDetailView` — et c'est le **seul** endroit sensé pour eux : un
      composant n'a pas de page Nexus, 20 des 55 mods introuvables par leur nom
      en sont. La bascule horodate elle aussi la ligne de tête
      (`mods.first(where:)` porte les entrées de tête).
      ▸ **Et la règle de préfixe aggravait la perte** : le rapport juge chaque
      clé isolément, mais `cleanStaleMaintenanceEntries` purge par
      `ModRemovalPurge`, qui emporte `Pack` **et** tout `Pack/…`. Les
      préférences des composants partaient donc sans avoir jamais été montrées.
      ▸ **Mesuré sur le parc : 0 occurrence aujourd'hui** — 521 clés relevées
      dans les quatre magasins (437 horodatages, 169 identifiants Nexus, 10
      configs suivies par profil), aucune ne désigne un des 115 en-têtes de
      packs. Le défaut est donc latent ; sa gâchette est un clic sur une action
      ordinaire.
      ▸ **La règle vit dans Core** (`preferenceKeyableFolders`, sur `[ModItem]`)
      plutôt qu'au ViewModel, avec la distinction écrite : `flattenedMods`
      répond à « quelles **identités** sont installées » — bon pour un
      `UniqueID`, faux pour une préférence, qui se pose sur la **ligne**.
      **4 tests neufs** (2 280 → 2 284), dont un qui épingle l'écart avec
      l'ancienne règle : les trois premiers étaient passés du premier coup, donc
      ne prouvaient rien.
      ▸ Même famille que X70 : l'écran d'entretien juge mort ce qu'il n'a pas
      regardé. · **S**
- [x] **X73** ✅ *(corrigé le 2026-09-05)* — **« Nom (A→Z) » ne triait pas
      comme les six autres tris de la liste.** `mods(matching:)` compte sept
      cas de tri. Six comparent les noms par
      `localizedCaseInsensitiveCompare` — la règle de macOS — et « Nom (Z→A) »
      aussi. Le septième, `.name`, ne comparait rien : il rendait `false` et
      s'en remettait à l'ordre posé au balayage par `alphabeticalListOrder`,
      qui était `lowercased() <`, c'est-à-dire l'ordre des **scalaires
      Unicode**.
      ▸ **Mesuré sur le parc, avec le vrai comparateur compilé** (pas une
      approximation : la première, en Python, disait « 0 divergence » et était
      fausse) : **190 des 951 noms** changent de place entre les deux règles,
      et **553 paires** s'inversent. Conséquence directe : « A→Z » n'était pas
      l'inverse de « Z→A ».
      ▸ **Ce que ça donnait à l'écran** : `*SorryLabCore*` et `6480's Giant
      Crops` passaient avant tout le bloc `[…]` — `*` vaut U+002A et `[`
      U+005B — quand macOS les range après. `[CP] 6480's Storage Variety`
      arrivait avant `[CP] [DDF] Garry` pour la même raison. Et l'apostrophe
      séparait deux mods du même auteur : `Nyapu's Portraits` loin de
      `Nyapu-Style More Haley Events` (`'` U+0027 précède `-` U+002D).
      ▸ **Deux corrections, une cause.** (a) `alphabeticalListOrder`
      (`ModItem.swift`) adopte le comparateur des six autres — un seul endroit,
      dans Core, déjà couvert par `ModListOrderTests`. (b) `.name` ne trie plus
      du tout : il rendait `false` pour tout, ce qui ne redonnait l'ordre
      d'entrée **que si** `sorted(by:)` était stable — la bibliothèque standard
      ne le garantit pas. Le commentaire l'affirmait pourtant : c'est le
      corollaire de X67, une propriété de sûreté affirmée est un endroit à
      vérifier. L'invariant réel est écrit à sa place (le balayage pose
      l'ordre, la bascule en masse est un `map` qui le préserve).
      ▸ **Gratuit, et même moins cher** : le tri à blanc coûtait une passe sur
      949 mods à chaque rendu, donc à chaque frappe dans la recherche.
      Mesuré : 2,28 ms par tri à blanc, 0,01 ms sans tri ; le tri localisé
      complet aurait coûté 3,33 ms par rendu, d'où le choix de corriger l'ordre
      **à la source** plutôt que de trier à chaque cadrage.
      ▸ Même famille que X63–X71 : le chemin voisin qui n'applique pas la règle
      de ses six jumeaux. **4 tests neufs** (2 277 → 2 280), tous d'attentes
      **mesurées** — la première version en portait deux, devinées, toutes deux
      fausses. · **S**
- [x] **X71** ✅ *(corrigé le 2026-09-05)* — **Un `Mods/` illisible effaçait la
      mémoire des installations.** `scanMods` ne garde que `gameDir.isEmpty`.
      Le parcours de tête est `if fm.fileExists(atPath: modsPath), let
      topEntries = try? fm.contentsOfDirectory(...)` : quand il échoue,
      `scannedMods` reste vide et l'exécution **continue** jusqu'à
      `syncInstalledModRegistry(scannedMods:)`, appelé sans condition. Deux
      purges s'y appliquent alors à un lot vide — `registry.filter {
      seenFolders.contains($0.key) }` vide le registre d'install, et
      `anchorStore.pruneAnchors(keeping:)` retire toutes les ancres de version.
      ▸ **Mesuré sur le parc** : **1 097 entrées de registre + 251 ancres**.
      ▸ **La copie de secours ne rattrape rien** — vérifié dans le code :
      `persistInstalledModRegistry` écrit le **même blob** sur la clé principale
      et sur la clé de secours, à la même écriture. Le filet couvre un blob
      corrompu (`loadInstalledModRegistryFromDisk` promeut la secours si la
      principale ne décode pas), pas un effacement logique : les deux copies
      partent ensemble, dès la première passe.
      ▸ **Aucun clic requis, contrairement à X70** : le déclencheur est
      `HomeView.swift:254` — `.onAppear { vm.refresh() }`. Ouvrir l'app suffit,
      revenir à l'Accueil aussi. Il n'y a ni minuterie ni observateur de focus.
      Causes plausibles d'un `Mods/` illisible : volume externe débranché
      (`gameDir` pointe alors dans le vide), dossier de jeu déplacé, droits
      refusés. Non mesuré — le correctif ne s'appuie sur aucune d'elles.
      ▸ **Le correctif porte un fait, pas un test de vacuité** : `scanMods`
      capture `modsFolderWasReadable` à l'endroit même où la distinction existe,
      et le passe jusqu'aux deux purges. Un `Mods/` **lu et vide** purge
      normalement : c'est une désinstallation réelle. Ce qui a été vu
      s'enregistre dans les deux cas — seule la purge est suspendue, pas le
      reste de la passe (bookkeeping des versions, lot de grâce).
      ▸ Même famille que X63–X70 : le magasin voisin qui n'applique pas la règle
      de son jumeau. X70 l'avait posée pour les préférences d'entretien, dans le
      même vocabulaire (« on n'a rien vu » ≠ « il n'y a rien ») ; elle n'avait
      pas été appliquée au registre d'install ni aux ancres.
      **3 tests neufs** (2 274 → 2 277), dont le cas voisin qui doit continuer
      de purger. Le journal dit la différence
      ([[warn-when-a-feature-shows-nothing]]). · **S**
- [x] **X70** ✅ *(corrigé le 2026-09-05)* — **Un parc qu'on ne voit pas n'est
      pas un parc vide.** `MaintenanceInventory.stalePreferenceKeys` juge chaque
      clé sur son absence de `installedFolders`. Ce lot vide ne veut pas dire
      « aucun mod installé » : il veut dire « on n'a rien lu » — dossier de jeu
      introuvable ou déplacé, disque externe débranché, balayage pas terminé
      quand l'écran s'ouvre. Toutes les clés passaient alors pour mortes, et le
      bouton « nettoyer » les effaçait.
      ▸ **Mesuré sur le parc** : **616 entrées** partaient — 437 dates
      d'activation, 169 identifiants Nexus saisis à la main, 10 mods à
      configuration suivie par profil. Les identifiants Nexus ne se retrouvent
      qu'à la main, un par un.
      ▸ **La règle existait déjà à côté**, dans le même fichier, pour les
      sessions orphelines : « une suppression ne se décide pas sur une absence
      constatée toute seule ». Elle n'avait pas été appliquée aux clés.
      Même famille que X63–X69 : le chemin voisin qui n'applique pas la règle de
      son jumeau.
      ▸ **Le reste de l'écran échoue déjà du bon côté** — vérifié : un
      `modsRoot` illisible rend chaque sauvegarde `.soleCopy`, donc *protégée*,
      donc non supprimable. Seules les clés penchaient dans le mauvais sens.
      ▸ **Prix assumé** : un parc réellement vide ne nettoie plus ses clés. Le
      prix de l'inverse est la perte de données de tous les autres.
      **2 tests neufs** (2 272 → 2 274), dont le cas voisin — un seul mod vu
      suffit à rendre le jugement. Et le journal dit la différence entre « tout
      est propre » et « je n'ai rien pu lire »
      ([[warn-when-a-feature-shows-nothing]]). · **S**
- [x] **X69** ✅ *(corrigé le 2026-09-05)* — **Supprimer un mod laissait le
      registre des traductions derrière lui.** Trouvé en relisant le **delta du
      ViewModel** — 1 386 lignes ajoutées sur 31 commits depuis que sa tranche
      avait été déclarée complète.
      ▸ **La comparaison qui l'a montré** : les trois chemins qui touchent aux
      magasins indexés par nom de dossier. Le **renommage** (X60) en migre
      douze, dont `installedTranslations` ; la **suppression** (`forgetStores`,
      X55) en purge cinq ; le **ménage** de l'écran Entretien (X25) en balaie
      quatre. `installedTranslations` est le seul que le renommage migre et que
      ni la suppression ni le ménage ne touchent.
      ▸ **Un orphelin réel sur le parc** : une greffe posée sur
      `[CP] Make Gunther Real`, mod absent du disque (vérifié : aucun dossier de
      ce nom, ni à plat ni niché — seul `.GunthersGuide` s'en approche). L'entrée
      affirme qu'une traduction est installée sur un mod qui n'existe plus.
      ▸ **Le défaut a deux étages**, et n'en corriger qu'un n'aurait rien changé :
      `rename(host:to:)` couvre **trois** dictionnaires (`byHost`,
      `addonsByHost`, `declaredTranslations`), quand `forget(host:)` n'en vide
      qu'**un**. L'orphelin du parc vit dans `addonsByHost` — câbler
      `forget(host:)` à la suppression ne l'aurait pas atteint. D'où
      `forgetEverything(host:)`, contrepartie symétrique du renommage, **4 tests
      neufs** (2 268 → 2 272). `forget(host:)` reste tel quel : le retrait d'une
      traduction rend délibérément l'entrée pour savoir quoi remettre, et une
      greffe sur le même mod n'a pas à partir avec.
      ▸ **Les originaux mis à l'abri partent avec l'entrée.** Les valeurs de
      `replacedFiles` en sont les seuls pointeurs, et **rien ne balaie
      `TranslationBackups/`** — `readMaintenanceReport` ne parcourt que les
      sauvegardes d'installation. Les oublier sans les retirer aurait échangé
      une entrée fausse contre des octets que plus personne ne désigne. Seuls
      les chemins **sous la racine des sauvegardes** sont retirés : un chemin
      venu d'ailleurs ne s'efface pas sur la foi d'un registre. Mesuré : les 5
      dossiers de `TranslationBackups/` (544 Ko) ont tous leur mod encore
      installé — zéro orphelin de fichiers aujourd'hui.
      ▸ 📌 **Suite possible, non faite** : `TranslationBackups/` n'a aucun
      balayeur, et `cleanStaleMaintenanceEntries` ne connaît que les quatre
      préférences de X25. L'y ajouter demande d'étendre le rapport, producteur
      distinct — à traiter à part.
      ▸ 📌 **Cliquet non relevé** : le premier jet posait un `try?` sur le
      retrait des originaux (`try_optional` +1). Corrigé plutôt qu'assumé — les
      échecs sont comptés et journalisés **en une ligne**, ce qui est aussi la
      seule occasion de savoir que des octets sont restés. · **S**
- [x] **X68** ✅ *(corrigé le 2026-09-05)* — **La correction de contraste des
      descriptions partait à l'envers en thème sombre.** `MarkdownText.render`
      résolvait `NSColor.windowBackgroundColor` par `usingColorSpace(.sRGB)`
      pour donner un fond à `ContrastChecker.adjusted`. C'est une couleur
      **dynamique** : elle se résout contre `NSAppearance.currentDrawing()`,
      posée seulement pendant un dessin. Or `render` est appelé depuis l'`init`
      de la vue — aucun contexte de dessin, aucune garantie sur l'apparence
      ambiante.
      ▸ **Mesuré en compilant le cas, pas déduit** (2026-09-05) : sans
      apparence posée, `windowBackgroundColor` rend du **blanc** (luminance
      1,0000) ; sous `.darkAqua`, du gris 0,118 (luminance 0,0130). Le seuil de
      `adjusted` étant à 0,2, la première réponse fait **assombrir** le texte et
      la seconde l'**éclaircir** : la décision s'inverse entièrement. Se
      tromper, c'est écrire du texte sombre sur fond sombre — exactement ce que
      la correction de contraste existe pour empêcher.
      ▸ **Le correctif** : `performAsCurrentDrawingAppearance` sur
      `NSApp.effectiveAppearance` (l'apparence réelle de l'app, bascule de
      thème comprise), avec repli sur `NSAppearance.currentDrawing()`. Vérifié
      en exécutant le code corrigé : il suit désormais l'apparence dans les deux
      sens. Sans effet quand l'ambiante était déjà la bonne, décisif sinon.
      ▸ Corollaire tombé au passage : la valeur était figée à l'`init` et donc
      jamais recalculée à une bascule de thème. SwiftUI réinitialise la vue au
      changement de `colorScheme`, ce qui rejoue `render` — le repli sur
      `NSApp.effectiveAppearance` suffit donc, sans toucher à la mise en cache
      (un `body` qui recalculerait ce parsing coûterait cher, cf. les pièges de
      perf de `CLAUDE.md`).
      ▸ **Faux positifs écartés dans le même fichier**, à ne pas rouvrir :
      `ContrastChecker.color(named:)` semblait court-circuiter la correction
      pour les couleurs nommées (`[color=red]`) — il n'en est rien,
      `DescriptionBlockParser.resolveColorHex` les normalise en `#rrggbb` et
      elles repassent par `adjusted`. Et `adjusted` n'essaie qu'**une**
      direction avant de rendre `nil` : c'est conservateur, pas faux — l'appelant
      retombe sur la couleur par défaut. · **S**
- [x] **X67** ✅ *(corrigé le 2026-09-05)* — **Deux chemins Nexus voyaient un
      `429` sans armer la porte de limitation partagée.** `NexusUpdateChecker`
      tient un `NexusRateLimitGate` commun à tous les appels ; son propre
      helper, `noteRateLimitIfThrottled`, relève le quota, analyse `Retry-After`
      et arme la porte — et sa documentation dit pourquoi : « une réponse qui
      échappe au relevé est un 429 non vu, qui aggrave le bannissement au lieu
      de l'attendre ». Elle se limitait à « tous les `dataTask` **de ce
      fichier** ».
      ▸ **Le commentaire faux est le vrai point de départ.**
      `NexusSearchClient.send` portait déjà, mot pour mot, « un 429 freine tout
      le monde plutôt que la seule recherche ». C'était faux : il n'appelait que
      `noteQuota`, qui relève sans armer. Un commentaire qui affirme une
      propriété de sûreté absente est ce qui empêche le lecteur suivant d'aller
      vérifier.
      ▸ **`NexusDownloader.noteQuotaAndStatusError`** faisait pareil, et c'est
      le cas le plus net : `statusError` **reconnaît** le 429 (`.rateLimited`)
      sans que rien ne freine la suite, sur la **même API v1** que
      `fetchModInfo`, qui arme, elle. Aucune incertitude, et c'est le geste le
      plus cher en quota. Trois sites de téléchargement y convergent.
      ▸ **`retryAfter: 60` en dur** dans `send` : le délai annoncé par le
      serveur était jeté. Un 429 disant « attends 300 » valait 60 s d'attente,
      donc un nouveau 429.
      ▸ ❓ **Ce qu'on n'a pas fait, faute de mesure** : la porte armée ne
      **bloque pas** une requête GraphQL v2 au départ, là où `fetchModInfo` s'y
      refuse. Le coût d'une erreur n'est pas symétrique — armer depuis v2 risque
      un contrôle de mises à jour retardé, bloquer v2 depuis v1 couperait la
      vitrine Découverte jusqu'à quinze minutes — et la prémisse n'est pas
      établie : **un `429` sur v1 refuse-t-il aussi v2 sur la même clé ?**
      La mesure demande la clé de l'auteur et consomme du quota ; `docs/SOURCES.md`
      §2.4 note d'ailleurs qu'aucune sonde n'existe pour v2.
      ▸ ⚠️ **Sans test**, comme X65 et X66. **Cause commune, nommée ici** : ces
      clients codent en dur `URLSession.shared` et des singletons, donc aucun
      test ne peut atteindre le câblage. `SmapiUpdateClient` a pris un
      `init(session:)` et en a tiré cinq tests — c'est le précédent à suivre si
      on veut rendre cette grappe testable. · **S**
- [x] **X66** ✅ *(corrigé le 2026-09-05)* — **Le rapport de raccourcis restait
      sur l'état d'avant une écriture de `config.json`.** Il se lit
      exclusivement dans ces fichiers, et la signature de
      `KeybindScanService.scanIfNeeded` ne couvre que `folderName`/`isEnabled` :
      une écriture qui ne touche pas au parc lui est invisible.
      ▸ **Quatre chemins écrivent un `config.json`, un seul rescannait.** La
      fermeture de l'éditeur de configuration le faisait — et son commentaire
      expliquait précisément pourquoi. Les trois autres l'ignoraient : la
      restauration d'une sauvegarde de configurations
      (`ModConfigBackupsView.performRestore`), la bascule de profil
      (`restoreProfileConfigs`, qui réécrit chaque mod marqué) et la
      récupération d'un fichier perdu (`recoverFile`, partagé avec la reprise
      d'une sauvegarde protégée). Le cas le plus net : l'utilisateur corrige un
      conflit, restaure une sauvegarde, et l'écran lui montre encore les
      conflits d'avant.
      ▸ Le cas du profil n'est pas couvert par le rescan que déclenche déjà un
      changement de parc : **deux profils peuvent n'avoir que leurs
      configurations de différent**, aucun dossier ne bouge alors.
      ▸ **La règle en un seul exemplaire** :
      `StarHubTHViewModel.rescanKeybindsAfterConfigWrite()`, dont le `didSet` de
      l'éditeur n'est plus qu'un appelant parmi quatre. Même forme que X61, X65.
      ▸ **Défaut trouvé en relecture du correctif** : `scan` refusait
      silencieusement une demande arrivée pendant un scan (`guard !isScanning`),
      ce qui reperdait le rescan à chaque fois qu'une écriture tombait pendant
      une lecture. Le rejeu garde **l'état demandé** (`pendingRescan`) et non un
      drapeau : rejouer avec les arguments du scan en cours relirait le disque
      mais sur la liste de candidats d'avant, et poserait
      `lastScannedSignature` pour un parc jamais lu — `scanIfNeeded` se croirait
      alors à jour. C'est exactement le cas de la bascule de profil, qui bouge le
      parc *puis* réécrit des configs.
      ▸ ⚠️ **Sans test**, comme X65 : `KeybindScanService` est `@MainActor` et
      hors du périmètre de `Package.swift`. **Vérification manuelle en une
      minute** : restaurer une sauvegarde de configurations, puis regarder la
      pastille de raccourcis de la barre latérale sans passer par l'onglet.
      ▸ 📌 **Cliquet** : `abbreviation_vm` +1 ici. Sur la journée, la base a été
      relevée quatre fois (X63 +2/+1, X65 +1, X66 +1) — chaque ligne reprenait
      l'idiome de sa voisine, mais le cliquet ne fait que se desserrer. À
      resserrer lors d'une passe dédiée plutôt qu'au fil des correctifs. · **S**
- [x] **X65** ✅ *(corrigé le 2026-09-05)* — **Le filet de sécurité du splash
      révélait la fenêtre sans délivrer les liens `nxm://` en attente.** Un clic
      « Mod Manager Download » sur Nexus lance l'app à froid ; le lien est mis en
      file jusqu'à ce que la fenêtre principale soit à l'écran (sans quoi la
      feuille d'installation s'ouvre sur une fenêtre absente et ne peut plus être
      refermée — piège documenté sur `AppDelegate.isReady`).
      ▸ **Trois chemins révèlent la fenêtre** : la fin de chargement ordinaire
      (`onChange(of: vm.isLaunching)`), un lancement déjà terminé quand la vue
      paraît, et le **filet des 30 secondes** de `hideMainWindow()`. Les deux
      premiers appelaient `deliverPendingURLs()` à la main ; le troisième
      appelle `finish()` directement et l'oubliait. Un chargement qui n'aboutit
      jamais — la prémisse même du filet — rendait donc la fenêtre puis ne
      téléchargeait rien, en silence.
      ▸ Même forme que **X64** : une branche sœur qui ne fait pas ce que font
      ses voisines. La règle vit maintenant en un seul exemplaire,
      `LaunchSplashController.onReveal`, appelée dans `finish()` juste après
      `showMainWindow()` — **avant** le `guard let panel`, sans quoi un
      lancement assez rapide pour finir avant `show()` (panneau nil) aurait
      recréé une quatrième asymétrie. Les deux appels explicites sont retirés.
      ▸ ⚠️ **Sans test** : `AppDelegate` et `LaunchSplashController` sont du
      AppKit, hors du périmètre de `Package.swift` — balayage par les Traps,
      comme le protocole le prescrit pour ces fichiers. Extraire la file
      (`pendingURLs` / `isReady` / `onURL`) vers Core reste possible, mais elle
      n'était pas en cause : ses invariants tiennent sur tous les chemins, c'est
      le **câblage** qui manquait. Cliquet `our_shared_singletons` relevé (+1,
      la ligne reprend le patron des quatre autres du même fichier).
      ▸ ❓ **Question pour l'auteur, tranchée le 2026-09-05 sur l'app lancée** :
      `applicationShouldTerminateAfterLastWindowClosed → false` existe pour le
      splash, mais vaut pour toute la vie de l'app. Fermer la fenêtre
      principale (Cmd+W) après le lancement laisse-t-il une app sans fenêtre
      qu'un clic sur le Dock ne rouvre pas ? **Non — mesuré par l'auteur** :
      Cmd+W est inopérant durant le splash (voulu : on ne referme pas un
      lancement en cours), ferme la fenêtre lancée, et **le clic Dock la fait
      revenir** — la scène `Window` SwiftUI se réinstancie. C'est le patron
      macOS standard des applis à fenêtre unique (App Store, Réglages
      Système) ; rien à corriger, la question est close sans correctif.
- [x] **X64** ✅ *(corrigé le 2026-09-05)* — **Un budget de re-découpage épuisé
      se faisait passer pour une passe complète.** smapi.io ne rejette jamais :
      il rend `200` et une liste vide quand une seule entrée du lot lui déplaît.
      `SmapiUpdateClient.collect` re-découpe alors le lot pour isoler la
      coupable, avec un budget de **32 requêtes pour toute la vérification**.
      Ce budget épuisé, la fonction rendait `([], budget)` — un tableau vide, en
      silence — et la boucle de `fetch` comptait malgré tout le lot comme
      terminé.
      ▸ **Mesuré par le test avant correction** : 300 mods demandés, **13
      verdicts rendus**, `batchesCompleted: 2 / 2`, `isComplete: true`. Le
      `NexusUpdateChecker.recordSuccessfulCheck()` de l'appelant posait donc son
      horodatage, ce qui coupe la vérification automatique **douze heures**
      (`UpdateCheckPolicy`) pour 287 mods jamais interrogés.
      ▸ C'est le défaut que `batchesCompleted` avait été créé pour empêcher
      (X47 et la passe partielle), rentré par la porte de derrière. L'asymétrie
      était visible dans le fichier : la branche « seule dans son lot » avait
      délibérément choisi de remonter `rejectedEntryError` plutôt que de se
      taire ; la branche voisine se taisait.
      ▸ **La correction** : un troisième membre `abandoned` au tuple privé de
      `collect`, remonté à `fetch`, qui garde ce qui a été isolé puis sort sans
      compter le lot. Aucune signature publique touchée, et le chemin d'honnêteté
      existant fait le reste — l'appelant journalise déjà « passe incomplète » et
      ne pose pas l'horodatage.
      ▸ **Déclenchabilité** : les trois champs connus pour vider un lot sont
      filtrés avant l'envoi (`isExpressibleVersion` depuis X62,
      `sanitizedGameVersion`, `apiVersion` figée). Le filet reste pour le
      manifeste tiers qu'on ne contrôle pas — ce que sa propre documentation
      dit. **1 test neuf** (2 267 → 2 268). · **S**
- [x] **X63** ✅ *(corrigé le 2026-09-05)* — **Installer un mod neuf effaçait
      le mod qui portait déjà son nom de dossier.** `install` ne reconnaît un mod
      installé qu'à son `UniqueID` (`findExistingMod`). Sans correspondance, il
      posait la copie à `Mods/.<nom de l'archive>` — et si ce chemin était pris,
      l'occupant partait au rollback dans le dossier temporaire puis était
      **supprimé** dès la copie réussie. Aucune sauvegarde : elle ne vit que dans
      la branche `.overwriteWithBackup`, conditionnée au même `UniqueID`. Aucun
      message non plus.
      ▸ **Le cas est réel** : les deux `[CP] Seaside Sounds` du parc (X60)
      montrent qu'un même nom logique porté par deux `UniqueID` distincts arrive ;
      il suffit que l'un soit en pause — donc à `Mods/.X`, exactement là où
      atterrit un mod neuf — pour que l'installation du second le détruise.
      Prouvé par test avant correction, pas déduit.
      ▸ **La règle** : à destination occupée, on lit le `manifest.json` du
      dossier. Même `UniqueID` (comparaison insensible à la casse) → c'est notre
      propre mod, l'écraser est le geste demandé. Autre identifiant, ou **aucun
      identifiant lisible** → on se décale sur un nom horodaté. La polarité
      compte : une **racine de pack** ne porte pas de manifeste (ce sont ses
      composants qui en portent), et lire l'absence de propriétaire comme une
      permission d'effacer aurait détruit les packs — pire que le défaut corrigé.
      ▸ C'est le **nouveau** qui bouge, jamais l'installé : `ModItem.id` est le
      nom de dossier, et déplacer l'installé casserait toutes les clés
      persistées. Le décalage ne porte que sur la dernière composante, un
      composant de pack reste donc dans son pack.
      ▸ **Tombé au passage** : deux composants d'une même archive partageant un
      nom de feuille (deux parents différents, donc pas de `commonParent`)
      s'écrasaient l'un l'autre — le second arrive quand le premier est déjà
      écrit, la même règle les sépare. **5 tests neufs** (2 263 → 2 267), dont le
      cas voisin qui ne doit *pas* bouger : réinstaller le même mod écrase bien
      son propre dossier. Le déplacement remonte à l'utilisateur par
      `InstalledModPath.displacedFrom` et une ligne de journal. · **S**
- [x] **X60** ✅ *(livré le 2026-09-05)* — **Deux mods se disputaient un nom de
      dossier ; on les sépare pour de bon.** `X` actif et `.X` en pause sont deux
      mods distincts — cas réel du parc : les deux `[CP] Seaside Sounds`, de
      witchtopia et de Liana. Un profil qui réclame celui en pause et pas l'autre
      demande un **échange** de noms : les deux déplacements se refusent l'un
      l'autre, et aucun ordre ne les débloque — c'est un cycle à deux, trouvé le
      2026-09-04 par la propriété d'idempotence de **R6** (86 parcs engendrés sur
      200 en portent un). Le 2026-09-04, le refus a d'abord été rendu *explicite*
      (`renameModFolder` partagé par les trois chemins de bascule nomme le mod
      qui occupe le dossier).
      ▸ **Ce que la roadmap prescrivait, et pourquoi on ne l'a pas fait.** Le
      nom temporaire dénoue le cycle et rien d'autre : `ModItem.id` **est** le
      nom de dossier, et sur le parc **4 magasins persistés** tenaient la seule
      clé `[CP] Seaside Sounds` pour les deux mods —
      `installedModRegistry`, son backup, `modActivationTimestamps`,
      `nexusCustomModIds`. Un échange de dossiers rendrait le profil
      « appliqué » sans rien changer à ça : l'identifiant Nexus saisi pour l'un
      continuerait de servir pour l'autre. Le choix de l'auteur : **renommer, et
      migrer les clés** — la case verte contre la cause.
      ▸ **Le geste.** Une action « Renommer ce dossier » sur la ligne de
      collision de l'écran d'alertes système. La feuille fait **choisir lequel**
      des deux renommer (nom, auteur, identifiant, état du dossier) : sans ça
      l'utilisateur renommerait celui que la liste des mods lui montre —
      c'est-à-dire, justement, celui qu'elle a retenu arbitrairement. Le disque
      bouge d'abord ; si le `moveItem` échoue, aucun magasin n'a bougé.
      ▸ **Les douze surfaces** indexées par nom de dossier suivent : favoris,
      configs pilotées par profil, horodatages d'activation, identifiants et
      catégories Nexus personnalisés, registre installé, historique d'erreurs,
      les deux jeux de sauvegardes (config et installation), la référence de
      traduction, les configs retenues par chaque profil, les traductions
      posées. Plus deux caches (le poids, indexé sur le nom **physique** — donc
      les deux formes, pointée et non pointée — et la couverture FR).
      ▸ **La distinction qui décide de tout : préférence ou affirmation.** Une
      clé partagée n'est pas *déplacée* — le mod resté en place perdrait ce
      qu'elle portait pour avoir laissé son voisin se renommer. Mais elle n'est
      pas non plus copiée aveuglément : un favori est une **préférence**, les
      deux la gardent ; l'identifiant Nexus saisi à la main et la ligne de
      registre sont des **affirmations sur un mod**, et rien ne dit lequel des
      deux prétendants elles décrivaient. Les copier enverrait le mod renommé
      chercher ses mises à jour sur la page d'un autre — et « je l'ai déjà »
      (**X62**) s'ancrerait sur cette version-là. `SharedKeyPolicy` tranche par
      magasin : `.copy` pour les préférences, `.leaveBehind` pour les deux
      autres — comme pour les deux jeux de sauvegardes, config et installation :
      ces fichiers-là portent ce que l'utilisateur a écrit à la main, et les
      emporter priverait de sa propre config le mod resté en place. Ce que le
      mod renommé perd ainsi, il le réapprend de son manifeste au scan suivant.
      La feuille le dit à l'écran, sinon l'utilisateur chercherait ensuite
      l'identifiant qu'il avait saisi.
      ▸ **Les refus** (`ModFolderRename.Verdict`) : nom vide, point de tête —
      c'est la marque d'un mod en pause, pas un caractère de nom —, `/` et `:`,
      nom déjà pris. La comparaison est **insensible à la casse** : le disque
      macOS l'est, et `Seaside` renommé `SEASIDE` ne libérerait rien.
      ▸ **Et le préfixe de composant** : une clé `Pack/Composant` suit son pack,
      `PackDeLuxe` non — la frontière est la barre oblique, pas la sous-chaîne.
      ▸ Un bandeau prévient si le jeu tourne **et** que le mod choisi est actif ;
      renommer un dossier en pause pendant une partie ne risque rien, SMAPI ne
      l'a pas chargé. Avertir, jamais interdire — la doctrine du dépôt.
      ▸ **30 tests neufs** (2 233 → 2 263), dont les 17 de `ModFolderRename` et
      les deux qui pinglaient l'ancienne action unique de la ligne de collision,
      réécrits. · **S**
      ▸ **Relu le 2026-09-05, deux pistes vérifiées et mortes** — à ne pas
      rejouer. (a) `ForEach(claimants, id: \.uniqueId)` avec deux identifiants
      **vides** rejouerait le piège d'identité de `CLAUDE.md` ; il est
      **inatteignable** : `ModFolderCollision.collisions` écarte les
      identifiants vides et exige au moins deux identités **distinctes**, donc
      la feuille ne s'ouvre jamais sur cet état. (b) `stillClaimed` compare par
      `uniqueId` et rendrait `false` pour deux prétendants de même identifiant —
      les clés seraient alors *déplacées* au lieu d'être partagées, et le jumeau
      resté en place perdrait favori, horodatage et ligne de registre. Même
      raison : cet état n'ouvre pas la feuille. Et deux entrées de tête ne
      peuvent pas dépasser deux prétendants, un par nom physique. Ce qui reste
      ouvert de cette relecture est **X72** (composant de pack), en ROADMAP §4.
- [x] **X62** ✅ *(corrigé le 2026-09-04, signalé par l'auteur)* — **« Je l'ai
      déjà » ne tenait pas sur une étiquette Nexus libre.** Le geste posait bien
      son ancre, et la ligne revenait quand même à chaque vérification.
      ▸ **Mesuré avant de toucher au code** : les **15** lignes du cache de mises
      à jour étaient **toutes** des mods affirmés, et la version affirmée y
      égalait la version proposée. Corrélation parfaite avec une seule
      propriété : **15/15** des lignes revenues portent une version affirmée que
      smapi.io ne sait pas lire (`3`, `5`, `6`, `1.01`…), quand **22/23** des
      affirmations silencieuses en portent une lisible. La casse, elle,
      correspondait partout — ce n'était pas `F6-T4`.
      ▸ **La cause** : `SmapiUpdateRequest.sentVersion` substitue la version du
      manifeste quand l'ancre n'est pas exprimable — à raison, une seule de ces
      étiquettes vide un lot de 150 mods. Mais le ViewModel passait ensuite
      **ce qui avait été envoyé** à `NexusFallbackCheck.Blocked`, alors que la
      reprise Nexus compare à l'**étiquette de la page**, qui parle exactement ce
      vocabulaire-là. Elle comparait donc « 1.1.5 » à « 3 » et rendait la ligne.
      Le commentaire du code affirmait l'inverse (« prend l'ancre au retour, pas
      ce qu'on a envoyé ») : l'intention était juste, le câblage non.
      ▸ **Le second demi-tour** : une ligne que smapi.io ne « répond » pas est
      conservée d'une passe à l'autre — un mod sans réponse n'est pas un mod à
      jour — mais elle n'était jamais reconfrontée à l'ancre. Une ligne posée
      *avant* l'affirmation survivait donc à toutes les passes suivantes, et
      corriger la seule recréation n'aurait rien montré à l'écran.
      `AffirmedUpdates.isStillDue` la reconfronte.
      ▸ **Un risque mesuré et écarté** : faire entrer l'ancre dans la comparaison
      la fait aussi entrer dans `isAmbiguous`, qui écarte une page dont les mods
      ne s'accordent pas sur leur version — un voisin de page légitime pouvait
      donc devenir muet. Sur le parc, **3 affirmations sur 38** partagent leur
      page avec un mod non affirmé, et les trois portent une ancre **exprimable**
      : leur valeur comparée est inchangée. Zéro cas aujourd'hui ; à revoir si
      une affirmation inexprimable rejoint une page partagée.
      ▸ **12 tests neufs** (2 203 → 2 215), dont un qui prouve que le cas
      discrimine — la même page, comparée au manifeste, **rend** la ligne — et un
      qui épingle la frontière dangereuse de `isStillDue` : une version installée
      **vide** (le dernier recours de `sentVersion`) laisse la ligne due. Ne rien
      savoir n'est pas être à jour. · **S**
- [x] **X61** ✅ *(corrigé le 2026-09-04)* — **Deux copies de la même
      précaution avaient divergé, et la troisième manquait.** Quand une bascule
      trouve un dossier à la destination, la règle est de l'écarter s'il s'agit
      d'un résidu du mod qu'on bascule, et de refuser si c'est le dossier d'un
      **autre** mod (`ModFolderCollision`). Trois chemins renomment des dossiers ;
      la règle vivait en deux exemplaires, et ils ne disaient pas la même chose.
      ▸ **La divergence** : la bascule unitaire écarte le résidu sous un nom
      **préfixé d'un point** — sans lui, SMAPI continue de charger un dossier qui
      déclare le même `UniqueID` que celui qui vient de prendre sa place. La
      bascule en masse écartait sous `X.stale_<uuid>`, sans point. Le résidu n'est
      supprimé qu'après un renommage réussi : si cette suppression échoue, ou si
      l'app s'arrête entre les deux, le parc garde un dossier chargé en double.
      ▸ **Le manque** : l'application d'un profil n'appelait pas la règle du tout.
      Elle ne perdait rien (`moveItem` échoue au lieu d'écraser), mais elle ne
      savait ni récupérer son propre résidu, ni dire à qui appartenait le dossier
      qui la bloquait — voir **X60**. ⚠️ *Récupérer* veut dire **supprimer** :
      une suppression apparaît donc sur un chemin qui n'en faisait aucune. Elle
      est bornée par `isStaleDuplicate` — le dossier écarté doit déclarer
      l'identifiant du mod qu'on déplace (ou n'avoir aucun manifeste lisible) —
      et le retour arrière remet le dossier en place si le renommage échoue.
      C'est la doctrine que les deux autres chemins appliquaient déjà.
      ▸ Un seul `renameModFolder` sert désormais les trois, et le nom du dossier
      écarté est une règle de Core testée (`ModFolderCollision.asideName`,
      4 tests). Le plan d'application porte l'`UniqueID` de chaque déplacement,
      sans quoi l'arbitrage était impossible depuis ce chemin. · **S**
- [x] **X49** ✅ *(corrigé le 2026-09-04)* — **Deux recherches Nexus lancées coup
      sur coup pouvaient revenir dans le désordre.** `searchDiscovery(name:)`
      écrasait `discoverySearch` sans vérifier que le terme demandé était encore
      celui qu'on attendait ; le voisin immédiat, `loadMoreDiscoverySearch`,
      portait pourtant une garde. Le jeton d'époque manquant est extrait en Core
      (`RequestEpoch`, 6 tests) et posé aux trois endroits qui en avaient besoin.
      ▸ **Ce que le câblage a montré, et que l'item ne disait pas** : le désordre
      n'était pas le pire cas. Vider le champ ou quitter les résultats mettait
      `discoverySearch` à `nil` **sans périmer la requête en vol** — une réponse
      arrivée une seconde plus tard faisait revenir la liste que l'utilisateur
      venait de fermer. Même chose sur la fiche d'un mod : `loadDiscoveryDetail`
      n'a aucune garde, et la feuille se ferme puis se rouvre sur un autre mod
      bien plus vite qu'une requête ne revient — le corps du premier mod
      s'affichait alors sous le titre du second, l'en-tête venant de la ligne
      cliquée et le corps de `discoveryDetail`. Les deux sont couverts par le
      même jeton.
      ▸ **La pagination prolonge, elle ne remplace pas** : `loadMoreDiscoverySearch`
      porte le jeton *courant* (`currentToken`) au lieu d'en ouvrir un — demander
      la suite ne doit pas invalider la recherche qu'elle continue. Sa garde
      d'origine (même terme, même compte chargé) reste : elle protège d'autre
      chose, une liste qui a grandi entre-temps.
      ▸ L'item disait le correctif « non testable ici ». Il l'est devenu en
      sortant la règle du ViewModel : ce qui n'était pas testable, c'était son
      emplacement. · **S**
- [x] **X31** ✅ *(corrigé le 2026-09-04)* — **Le marqueur de version SMAPI
      mentait indéfiniment.** `getInstalledVersion` rendait le contenu de
      `smapi-internal/.starhubth-installed-version` dès qu'il était lisible, et
      ce fichier n'est écrit que par cette app. Une mise à jour de SMAPI passée
      par son propre installateur ne le réécrit pas : l'app affichait
      éternellement l'ancienne version, et le repli — la première ligne de
      `SMAPI-latest.txt` — n'était jamais consulté.
      ▸ **La règle retenue** : lire les deux sources, les départager par leur
      **date d'écriture**, croire la plus récente. Un journal plus récent que le
      marqueur veut dire qu'une partie a tourné depuis notre installation, et il
      nomme la version réellement *chargée*. Un marqueur plus récent veut dire
      qu'on vient d'installer sans que le jeu ait été relancé. Extrait en Core
      (`SmapiVersionEvidence`), 13 tests.
      ▸ **Ce que la mesure a corrigé dans l'item** : l'app ne « propose » aucune
      mise à jour de SMAPI — rien dans le code ne compare la version installée à
      une release. Ce qui était faux, c'est ce qui est **affiché**, aux trois
      endroits qui le montrent (accueil, réglages, pastille du bandeau d'état).
      ▸ **Deux pistes écartées, mesurées** : dater l'installation par
      `StardewModdingAPI.dll` ne marche pas — sa date est celle du **build** de
      la release (2026-03-14 pour 4.5.2), pas de la copie ; et le dossier
      `smapi-internal` est retouché par SMAPI en cours de partie (27/07 contre un
      marqueur du 23/07), donc sa date ne signale pas une réinstallation.
      ▸ **Ce qui reste ouvert, assumé** : SMAPI installé ailleurs *puis* jeu
      jamais relancé — les deux sources parlent d'avant. La fenêtre se referme au
      premier lancement, celui-là même pour lequel on met SMAPI à jour.
      ▸ **Ce qui rend la règle valide**, et qui a été vérifié plutôt que supposé :
      SMAPI **réécrit** `SMAPI-latest.txt` à chaque lancement — une seule
      bannière dans un fichier de 489 Ko, session du 01/09 de 17:39 à 17:44. La
      date du fichier appartient donc bien à la session que sa première ligne
      nomme. S'il s'accumulait, on apparierait une version ancienne à une date
      fraîche, et la règle préférerait le vieux journal à un marqueur juste.
      ▸ Cliquet `try_optional` relevé de 1 (301 → 302) : la lecture de date passe
      par `try?`, comme les 13 autres lectures d'attributs du dépôt. · **S**
- [x] **X54** ✅ *(corrigé le 2026-09-04)* — **Le journal annonçait « profil
      créé » sur un simple ajout.** `vm_profile_created` était journalisé en
      quatre endroits ; deux ne créaient rien. Ajouter un mod à un profil — le
      geste de réparation d'une dépendance que le profil laissait de côté —
      écrivait « Profil « Solo » créé (312 mods) », et importer les favoris
      aussi. Sur une journée de réglages, le journal donnait à lire une série de
      créations de profils qui n'avaient jamais eu lieu.
      ▸ Deux clés neuves, en parité `en`/`fr` : `vm_profile_mod_added` nomme le
      mod entré (son identifiant à défaut — une dépendance réclamée par un
      profil importé peut ne pas être installée) et `vm_profile_favorites_imported`
      dit **combien** de favoris sont entrés, ce que le compte final du profil ne
      disait pas. `createProfile` et `duplicateProfile` gardent la clé d'origine :
      dupliquer crée bien un profil. · **S**
- [x] **R6** ✅ *(livré le 2026-09-04)* — **Property-test « idempotent » sur
      `applyProfileToFilesystem`.** La règle qui décide *qui bouge, qui reste et
      dans quel ordre* vivait à l'intérieur de la méthode, mêlée au
      `DispatchQueue`, aux renommages et au rescane — donc hors de portée de
      `swift test`. Elle est extraite dans `ProfileApplyPlan` (Core) : la
      méthode du ViewModel exécute désormais un plan au lieu de le recalculer,
      une seule source pour la liste des dossiers à renommer.
      ▸ **Le verdict, mesuré** : l'application **est** idempotente. Sur 200 parcs
      engendrés (générateur déterministe, packs, mods sans identifiant, noms de
      dossier volontairement peu nombreux pour forcer les collisions), la
      seconde passe ne redemande **que** les déplacements que le disque a
      refusés au premier tour, et la troisième ne bouge plus rien. L'hypothèse
      de l'item — « des cas où un double-apply renomme deux fois (X→.X→X) » —
      est infirmée : rien n'oscille.
      ▸ **Ce que la propriété a trouvé à la place** : 86 des 200 parcs portent au
      moins un déplacement impossible, tous de la même forme — l'échange de nom
      entre `X` actif et `.X` en pause. Ouvert en **X60**.
      ▸ **Ce que les mutants ont dit** : la garde « mod sans identifiant » et
      l'ordre des déplacements sont bien tenus par un test chacun. Le mutant qui
      construit la destination depuis le nom **physique** survit — il est
      équivalent : seuls des mods actifs entrent dans la liste des mises en
      pause, où nom physique et nom logique coïncident. Sur l'ordre, ce qui est
      **mesuré** : l'échanger ne change le résultat d'aucun des 200 parcs
      engendrés, et tous les conflits observés y sont des échanges à deux, qu'un
      ordonnancement ne débloque pas. Un test le tient tout de même
      (`modsAreSetAsideBeforeOthersAreBroughtBack`) : l'ordre reste celui que la
      méthode a toujours eu. · **S**
- [x] **X59** ✅ *(constat faux, clos le 2026-09-04 — aucun code changé)* —
      **« Changer de profil jette la liste de ses échecs. »** Faux. Le constat
      avait été ouvert en lisant le paramètre `completion` de
      `applyProfileToFilesystem` : trois appels sur quatre l'ignorent, et le
      changement de profil reçoit ses échecs sous `_`. Mais ce paramètre ne porte
      qu'un **compte**, à l'usage de la bissection ; le signal à l'utilisateur,
      lui, part de l'intérieur de la méthode. Vérifié ligne à ligne :
      `profileApplyMessage` compose un texte qui **nomme** les mods restés du
      mauvais côté (huit au plus, puis `(+N)`), distingue l'échec total de
      l'échec partiel, y ajoute les mods du profil absents du disque, et
      `showModal` le pose dans `alertMessage` / `showAlert`. `MainView` porte le
      `.alert(isPresented: $vm.showAlert)` en permanence, quel que soit l'onglet :
      l'alerte s'affiche donc sur le geste, pas dans les journaux. Le profil est
      en outre marqué `incompletelyAppliedProfileIds`, ce qui transforme un
      re-clic en reprise des déplacements manquants. Rien à corriger.
      ▸ **Ce que ça enseigne** : la vérification qui a ouvert X59 s'était arrêtée
      à la signature. Un constat « l'utilisateur n'est pas prévenu » n'est acquis
      qu'après avoir suivi le chemin **jusqu'à la vue qui présente**. · **S**
- [x] **B1-T1** ✅ *(livré le 2026-08-01)* — Boutons **Activer/Désactiver** et
      **Supprimer** sur la fiche mod (parité avec la liste, mêmes confirmations).
      Absents pour un composant de pack, comme dans la liste. La fiche se referme
      à la suppression. · **S**
- [x] **B1-T2** ✅ *(livré le 2026-08-01)* — Tri, filtres, catégorie, page **et
      recherche** portés par `ModListFilters` dans le ViewModel. La remise à la page 1
      est portée par le type, ce qui a supprimé cinq `.onChange` que la vue devait
      tenir à jour à la main. **La position de défilement n'est pas conservée** : la
      pagination (15 par page) rend le scroll intra-page court, et la restaurer
      demanderait un `ScrollViewReader` — à rouvrir si le besoin se fait sentir. · **S**

## 5. Roadmap par chantier

### Bissection guidée — **Axe A** · livrée en **v1.11.0**


#### A4 — Recherche dichotomique du mod fautif

- [x] **A4-T1** — Modèle de session de bissection (Core, testable) : ensemble de départ,
      partition en deux, verdict utilisateur (« ça plante encore » / « ça ne plante plus »),
      sous-ensemble suivant, arrêt sur candidat unique. Journal des essais. · **M**
- [x] **A4-T2** — Application d'une étape : activer/désactiver la moitié courante en
      réutilisant la machinerie de profils, avec **instantané de l'état initial** et
      restauration intégrale en un clic à la sortie (y compris en cas d'abandon). · **M** ·
      risque : c'est la tâche qui manipule le plus de fichiers → sortie de secours obligatoire.
- [x] **A4-T3** — UI de session dans l'onglet Diagnostic : étape *n* sur ~log₂(N),
      liste des mods de l'essai courant, boutons de verdict, bouton « tout restaurer ». · **M**
- [x] **A4-T4** — Respect des dépendances : ne jamais désactiver un framework dont un mod
      actif de l'essai dépend (sinon les faux positifs rendent la bissection inutile). · **M**
- [x] **A4-T5** — Conclusion : l'écran final **nomme le mod trouvé**, le laisse en pause
      (tous les autres sont réactivés) et offre « tout remettre comme avant ». · **S**
- [x] **A4-T6** — Actions sur le mod trouvé : page Nexus, fiche du mod (où vit son
      historique d'erreurs), et « garder ce mod en pause » — qui referme la recherche
      sans réactiver le coupable, geste qui n'existait pas. Les mods que le journal
      accuse s'ouvrent de la même façon. A sorti la résolution du saut vers un mod dans
      `ModFocusResolver` (Core, testé) : elle ignorait les packs. · **S**

## 5. Roadmap par chantier

### Hub de traduction FR, phase 1 : *diagnostic* — **Axe C** · livrée en **v1.13.0**, sauf **C2-T4**


#### C1 — Couverture de traduction par mod

- [x] **C1-T1** — Calculer, pour chaque mod, la couverture i18n : clés de
      `i18n/default.json` (ou `en.json`) présentes/absentes dans `i18n/fr.json`, plus les
      clés orphelines côté FR. Modèle Core testable, aucune UI. · **M**
      **Livré** (v1.13.0, sous la pastille de C1-T2) : `TranslationCoverage`
      et ses états absent/vide distincts, mesurés en arrière-plan après le scan.
- [x] **C1-T2** — Badge de couverture dans la liste des mods, branché sur le filtre
      `FrenchTranslationScope` existant. **Livré** (`c6d4fec`, `beda7ed`) : pastille
      dans le vocabulaire de `VersionBadge`, chiffres à chasse fixe, trois états dont
      « pas encore mesuré ». · **S**
- [x] **C1-T3** — Section « Traduction » sur la fiche mod : compteur, date du dernier
      `fr.json`, lien vers l'éditeur. · **M**
      **Livré** (v1.13.0) : compteur « X clés traduites sur Y », barre de
      progression, absentes et vides listées séparément — et la limite « le cache
      ne contient qu'un entier », levée avec.
      - **Barre de progression**, à sa place ici et non dans la liste : la ligne de
        liste porte déjà globe, langues et deux dates, alors que la fiche a l'espace.
        La barre donne la comparaison instantanée, le nombre la précision — deux
        rôles, deux éléments (cf. [`audit-nana-ux.md`](audit-nana-ux.md) §2).
      - **Dire ce qui manque, pas seulement combien.** C'est ce que la liste ne peut
        pas faire : les clés absentes, et surtout les **vides**, qui cassent
        l'affichage en jeu au lieu de retomber sur l'anglais. 26 mods du parc en
        portent.
      - ⚠️ **Le cache ne contient qu'un entier.** `frenchCoverageByMod` stocke
        `displayPercent` ; afficher « 142 clés sur 197 » suppose d'y ranger la
        `Coverage` complète. Limite introduite en C1-T2, à lever ici.
- [x] **C1-T7** — Isoler les mods **partiellement traduits** : sur le parc, 392 sont
      complets et **31 ne le sont qu'en partie**. **Livré** (`6755f22`) en quatrième
      cadrage du filtre de traduction, et non en carte d'accueil comme envisagé
      d'après `stardew-i18n-translator` — leur page d'accueil ne sert qu'à la
      traduction, la nôtre a d'autres devoirs, et c'est dans la liste que le travail
      se fait. · **S**
- [x] **C1-T4** — ~~Test structurel « mod de traduction pure »~~ → **requalifié et livré
      autrement** (`46ce633`), après mesure sur le parc.
      - Le symptôme visé — un pack de traduction vers une autre langue affiché à
        « 0 % FR » — **ne peut plus se produire** depuis C1-T2 : sans français, aucune
        pastille ne s'affiche. Et le cas lui-même est à **zéro mod** sur le parc, sous
        un critère strict (contenu limité à `i18n/` + `manifest.json`).
      - La mesure a en revanche montré un défaut voisin **huit fois plus gros** : le
        filtre « à traduire » rendait 397 mods dont **310 sans le moindre `i18n`**.
        Un mod qui n'expose aucun texte n'est pas « sans traduction française », il est
        hors sujet. Le filtre exige désormais que le mod soit traduisible, et rend 87
        mods dont 48 vraiment à traduire.
      - L'heuristique de nom (`ModItem.swift:99`) reste en place : elle sert au **tag**
        de catégorie, pas à la couverture, et rien ne la met en défaut aujourd'hui.
- [x] **C1-T5** — Signaler qu'un `fr.json` disparu **existe encore dans une sauvegarde**.
      Mesuré le 2026-08-01 sur le parc réel : 92 mods ont un `default.json` sans `fr.json`,
      et **16 d'entre eux en ont un** dans `Backups/{ModInstalls,ModConfigs}`. Cas vérifié :
      `BetterInventory` avait `i18n/fr.json` (1348 o) dans la sauvegarde du 25/07, le dossier
      installé n'a plus que `default.json` — la mise à jour du mod a effacé la traduction,
      les auteurs ne redistribuant pas toujours les contributions communautaires. Phase 1 se
      limite à **le dire** (lecture seule) ; la récupération est **B4-T4**. · **M**
      **Livré** (v1.13.0) : la fiche nomme la sauvegarde et sa date.
- [x] **C1-T6** — Décoder les `i18n/*.json` comme le fait SMAPI, dont le comportement a été
      mesuré sur la DLL du jeu : `File.ReadAllText` honore la marque d'ordre des octets — un
      `ru.json` du parc est en UTF-16 LE et se charge **parfaitement** — puis se rabat sur
      UTF-8 en remplaçant les octets invalides par U+FFFD, sans erreur : trois `es.json` en
      jeu 8 bits hérité se chargent donc **avec les accents corrompus**. Reproduire les deux,
      et signaler le second comme une anomalie du mod plutôt que comme un échec de lecture.
      Sans quoi 4 fichiers réels restent illisibles chez nous — cf. l'en-tête de
      `I18nLenientParser.swift`. · **S**
      **Livré** (v1.13.1) : `I18nFileDecoder` honore la marque d'ordre, remplace
      les octets invalides, et `hasReplacedBytes` distingue l'anomalie du mod de
      l'échec de lecture.
- [x] **C1-T8** — Un mod dont la seule traduction est `fr-FR.json` (variante régionale)
      s'affiche « traduit en français » dans le filtre et la pastille de couverture, mais
      sa couverture mesurée est **0 %** et il ne sera jamais signalé obsolète par la
      fraîcheur : `languageCodes(inModDirectory:)` replie les variantes régionales sur leur
      langue de base, `I18nLocaleResolver.files(in:locale:)` non. Affecte déjà l'écran de
      couverture livré en v1.13.0 ; trouvé pendant ce plan, non corrigé. · **S**
      **Livré** (v1.13.1) : une variante régionale seule ne compte plus pour sa
      langue de base, et `unloadableLocaleFiles` nomme chaque fichier que le jeu
      n'ouvrira jamais, avec le nom qu'il devrait porter.

#### C2 — Vue diff EN/FR

- [x] **C2-T1** — Vue côte à côte : clé, valeur EN, valeur FR, état (traduite / manquante /
      identique à l'EN / obsolète). · **M** **Livré** (`8538c17`).
- [x] **C2-T2** — Détection d'obsolescence : une valeur FR est suspecte si la valeur EN a
      changé depuis la dernière écriture du `fr.json` (empreinte stockée à côté du backup
      de config existant). · **M** · risque : heuristique, à présenter comme telle.
      **Livré** (`7f92dac`, `d8b9ee3`, `b5180ec`, `31a34ff`, `e75e6ea`, `d5deef5`,
      `8467e4a`) autrement que prévu : l'empreinte seule ne dirait rien avant des
      mois (mesuré : 32 clés
      changées sur 35 mods comparables, 3 traductions réellement périmées dans un
      seul mod). Deux signaux à la place — la date du fichier, disponible au
      premier lancement sur 21 dossiers `i18n` répartis sur 18 mods, et une
      référence par clé qui s'adopte à la première ouverture du diff, reprise
      d'`imported_baselines` de `stardew-i18n-translator`.
- [x] **C2-T3** — Recherche et filtre par état. **Livré** avec la vue diff
      (`8538c17`) : un cadrage par état dont le libellé porte le compte, les états
      absents du mod n'étant pas proposés, plus une recherche sur la clé, l'anglais
      et le français, et une échappatoire quand elle ne rend rien. · **S**
- [x] **C2-T5** — Regrouper les lignes du diff par **section de commentaire** du
      fichier. Répond au besoin de « voir les dialogues par personnage » — mais par
      la structure que l'auteur a écrite, la seule fiable : déduire le locuteur des
      clés ne marche pas (mesuré, cf. [`audit-nana-ux.md`](audit-nana-ux.md) §9).
      **167 des 450** fichiers français du parc portent de tels commentaires, 3290
      sections, souvent déjà traduites. Obstacle : la passe 1 du parseur les
      supprime — il faudra les conserver comme marqueurs de position. Ne les
      afficher que dans l'ordre naturel : un tri les rendrait mensongers. · **M**
      **Livré** : regroupement (`01c3dc9`), puis en-têtes mis en évidence, repliage
      et table des matières.

## 5. Roadmap par chantier

### Hub de traduction FR, phase 2 : *édition & assistance* — **Axe C** · livrée par morceaux (**v1.15.0** → **v1.17.0**)


#### C3 — Éditeur `fr.json` assisté

- [x] **C3-T1** — Édition en place depuis la vue diff (écriture atomique, backup
      systématique via `ModConfigBackupManager`). · **M** · risque : écriture destructive
      → aucun enregistrement sans backup préalable.
      **Livré** (v1.15.0) : l'onglet Traduction est devenu un éditeur — édition
      côte à côte, `fr.json` créé au premier enregistrement, `.bak` avant chaque
      écriture, marqueurs du jeu protégés au passage.
- [x] **C3-T3** — Pré-traduction assistée. **Deux voies, l'une n'exclut pas l'autre** :
      API distante (DeepL/Claude/Google, clé au trousseau) ou **endpoint local compatible
      OpenAI** (Ollama/LM Studio — ni coût, ni fuite de données, précédent établi par la
      référence ci-dessus). Opt-in explicite, diff obligatoire avant écriture. · **M**
      **Livré** le 2026-08-19/20 (P2b, `[Unreleased]`) — **la voie locale seule** :
      Ollama et LM Studio sondés en loopback, par clé et par lot arrêtable, sans
      proxy ni redirection suivie. Le panneau conseille en plus un modèle adapté à
      la mémoire de la machine, ou en retient un déjà installé plutôt que de faire
      télécharger plusieurs gigaoctets.
      **Deux écarts assumés par rapport à l'énoncé.** *Le diff avant écriture* n'est
      obligatoire que sur la voie **par clé** : la proposition remplit un brouillon
      qu'un « Enregistrer » explicite valide. Le **lot** écrit directement — mais
      jamais sur une valeur française existante (il ne traite que l'absent et le
      vide), avec `.bak`, et chaque valeur écrite porte le drapeau **« À relire »**
      avec son filtre. C'est ce drapeau qui remplace le diff sur cette voie ; sans
      lui, une valeur machine se présenterait comme relue.
      *La voie distante* n'est pas livrée : spec écrite le 2026-08-20
      (`docs/superpowers/specs/2026-08-20-secours-traduction-en-ligne-design.md`),
      voir **C3-T7**.
- [x] **C3-T4** — Glossaire de termes du jeu pour la cohérence (noms de PNJ, objets,
      saisons), amorcé depuis les traductions officielles. · **M**
      **Livré** le 2026-08-19 (P2b, `[Unreleased]`) : 1 126 termes lus **dans les
      `.xnb` du jeu installé** — objets, artisanat, armes, outils, vêtements, PNJ,
      lieux, saisons — et imposés au modèle, avec pastilles cliquables dans
      l'éditeur. A demandé d'écrire un décodeur LZX et un lecteur XNB complets
      (translittérés de `lzxd`), validés **octet par octet** contre StardewXnbHack :
      360 dictionnaires réels, 360 identiques.
      Écart assumé : la gate de qualité exige `en != fr`, donc les noms propres
      identiques dans les deux langues (« Abigail ») **sortent** du glossaire —
      voulu, un nom identique n'a pas besoin d'être imposé.
      **Vérifié sur le jeu réel le 2026-09-03** (audit tranche E) : les 9 tables sont
      présentes et appariées, et **aucune description ne fuit** dans le glossaire —
      les 85 valeurs retenues portées par une clé qui n'est pas un `_Name` ont été
      relues une à une, toutes de vrais noms d'objet. Ne pas refaire cette mesure.
      **Son appariement, lui, était lent** : `matchEntries` cherchait les 1 126 termes
      dans chaque valeur (9,04 ms), désormais indexés par premier mot (`dc052a6`) —
      voir le constat joint à **F3** pour ce qui reste.
- [x] **C3-T6** — `I18nLenientParser` garde la **première** occurrence d'une clé JSON
      dupliquée ; le jeu (Newtonsoft) garde la **dernière**. Trouvé pendant C2-T5, mesuré
      sur le parc : 7 mods sur 512 concernés (ex. `[CP] Tea`, `spring_23` défini deux fois
      sous deux sections). Sans dommage tant que l'écran ne fait qu'**afficher** (C2) —
      mais C3 écrira des fichiers depuis ce même diff, et un traducteur traduirait alors
      le mauvais texte anglais. **Le comportement de référence doit être établi en
      exécutant la DLL Newtonsoft du jeu, jamais en lisant une spécification JSON**
      (cf. `docs/DOMAINE.md`). Consigné aujourd'hui uniquement dans des commentaires de
      code (`I18nOutline`, `TranslationCoverage`), nulle part ailleurs dans cette
      roadmap avant cette entrée. · **S** · risque : correctif mécanique une fois la
      référence connue, mais un écart de comportement mal vérifié contaminerait toutes
      les écritures de C3.
      **Livré** le 2026-08-18 (`bc9a9f9`), dans le sens inverse de l'énoncé : la
      référence établie sur la DLL dit **dernière valeur, à la position de la
      première occurrence** — c'est elle que le parseur applique désormais, plutôt
      que de « garder la première ». Chiffres recalés sur le parc du jour :
      58 fichiers i18n sur 2487, dont 39 aux valeurs divergentes.
      **Remesuré le 2026-09-03** (audit tranche E, 2 749 fichiers lisibles) :
      60 fichiers portent 139 clés dupliquées, dont **17 changent de section** entre la
      première et la dernière occurrence et 21 de rang. L'écart qui subsiste est
      documenté et assumé — la valeur affichée vient de la dernière occurrence, la
      section et la position de la première, faute de quoi `diffGroups` couperait en
      deux le bloc qui entoure la rangée (`cd54f05`, qui corrige au passage trois
      commentaires qui justifiaient la règle par une raison fausse).
- [x] **C3-T7** — **Secours de traduction en ligne (DeepL)** : quand l'IA locale
      échoue — serveur injoignable, ou refus faute de marques dures après retry —,
      la clé part chez DeepL, et seulement alors. Accord explicite par case à
      cocher, décochée par défaut ; clé au trousseau ; quota lu sur `/v2/usage`
      plutôt que codé en dur. · **M** · risque : un moteur générique ignore les
      marques du jeu — la protection passe par `tag_handling: xml` + `ignore_tags`,
      et c'est là qu'est le vrai travail, pas dans l'appel HTTP.
      Spec validée le 2026-08-20 :
      `docs/superpowers/specs/2026-08-20-secours-traduction-en-ligne-design.md`.
      Google Traduction écarté (pas d'API gratuite officielle ; les points d'entrée
      non documentés violent les conditions d'utilisation), LibreTranslate écarté
      (pas d'équivalent d'`ignore_tags`).
      **Livré** le 2026-08-21 (`9ec6030`…`d542608`), **sorti en v1.17.0** et
      validé à l'écran le même jour, sur une vraie clé gratuite.
      **Un défaut a survécu à toute la suite stubée** : `ignore_tags` partait en
      chaîne là où l'API JSON attend un tableau, et le service refusait *chaque*
      traduction (`HTTP 400`). Rien ne l'a vu — ni les tests, ni la relecture —
      parce qu'un stub accepte n'importe quel corps ; c'est le compteur de
      caractères du compte, resté à zéro, qui l'a dit. D'où `DeepLLiveTests`,
      un oracle sur le vrai service (`DEEPL_API_KEY=…:fx ./run_tests.sh`), sur
      le modèle de l'oracle XNB.
      Deux écarts assumés par rapport à la spec, tous deux constatés en écrivant
      le code :
      1. **Le secours peut être le seul moteur.** La spec le décrivait comme un
         recours après échec local ; sur une machine qui ne fait pas tourner de
         modèle — celle de l'auteur — il n'y a pas d'échec local, il n'y a pas de
         local du tout. La case, la phrase de confidentialité et le
         récapitulatif de lot ont chacun leur variante pour ce cas, plutôt que
         d'annoncer un secours à qui n'a rien à secourir.
      2. **Le 429 a son propre état**, distinct du quota épuisé : la spec les
         voulait « la même coupure », et c'est bien la même — mais rien n'a été
         consommé, et l'annoncer comme un quota enverrait l'utilisateur chercher
         un problème qui n'existe pas.
- [x] **C3-T8** — **Traduire une sélection de la source**. Une valeur entière
      n'est pas toujours ce qu'on veut traduire : il manque un mot, une
      tournure, et le reste est déjà écrit. La sélection de l'anglais part
      seule — clic droit ou bouton —, la phrase entière servant de contexte non
      traduit. · **S**
      **Livré** le 2026-08-21 (`ab964c1`…`e786dfa`), sorti en v1.17.0, validé à
      l'écran. Trois décisions inscrites dans le code : le résultat est une
      pastille qu'on clique pour l'insérer (macOS 14 ne dit pas où est le
      curseur d'un `TextEditor`, « insérer au curseur » aurait dégénéré en
      « ajouter à la fin ») ; une sélection qui emporte une marque du jeu est
      refusée, les marques nommées ; cette voie passe par le service en ligne
      **seul**, le prompt local étant bâti pour une valeur entière.
      Le panneau anglais est devenu un pont AppKit : SwiftUI rend un texte
      sélectionnable mais ne dit pas ce qui l'est avant macOS 15.

#### C4 — Éditeur de config lisible

- [x] **C4-T4** — `§audit-config-menus` — **Lire le `ConfigSchema` de `content.json`**
      (Content Patcher) : type, valeur par défaut, valeurs admises, section, description.
      C'est un **schéma complet, déjà sur le disque**, sans décompilation ni heuristique —
      et il donne d'un coup la liste déroulante à la place du champ libre, le regroupement
      par section, l'infobulle, et le repérage des valeurs modifiées par rapport au défaut.
      **Mesuré sur le parc** : côté **actifs**, 30 content packs, **20 publient un
      `ConfigSchema`**, **1041 tokens**, et **100 % des clés de leur `config.json` sont
      décrites** (c'est Content Patcher qui génère le fichier depuis le schéma) ; parc
      entier, 256 packs de plus et 5335 tokens, même couverture.
      Champs par fréquence : `Default` 6372, `AllowValues` 5053, **`Section` 4831**,
      `Description` 3378, `AllowBlank` 871, `AllowMultiple` 408, `Name` 173.
      ⚠️ **Tolérances mesurées, pas supposées** : `Allow Multiple` avec une espace (40),
      `section` en minuscules (35), `description` (1), et deux coquilles uniques
      (`HostowValues`, `HostowBlank`). Lecture **insensible à la casse et à l'espace**,
      champ inconnu ignoré sans bruit. **14 `content.json` restent illisibles** même en
      JSON5 : le repli est l'éditeur brut, jamais une erreur. · **M**
      ✅ **Socle livré le 2026-08-28** — `Models/ContentPackConfigSchema.swift` (Core),
      9 tests, bâti sur `ConfigJSONTree` plutôt que sur un cinquième analyseur JSON.
      **Confronté au parc, pas seulement aux fixtures** : 591 `content.json` parcourus,
      **276 schémas et 6376 tokens — les mêmes comptes que le relevé Python**. Les
      quatre écarts sont ceux que les tolérances rattrapent, et le vérifient :
      `Section` 4866 contre 4831 (+35 `section` en minuscules), `AllowMultiple` 448
      contre 408 (+40 `Allow Multiple` avec espace), `Description` +1, et `AllowValues`
      5047 contre 5053 (−6 champs ne contenant que des virgules, écartés à raison).
      L'API **distingue les trois issues** — `unreadable`, `noSchema`, `options` — parce
      qu'elles se ressemblent toutes les trois à l'écran (aucune option à montrer) mais
      qu'**une seule mérite d'être signalée** : sur 591 `content.json`, **276 ont un
      schéma, 301 n'en ont pas, 14 sont illisibles** (compté en Swift, pas déduit du
      relevé Python — l'arbre a sa propre tolérance). Les confondre afficherait des clés
      brutes sans explication aux 14, et un avertissement injustifié aux 301.
      ✅ **Branché sur l'écran le 2026-08-28** — `ConfigEditorModel.groups(of:describedBy:)`
      (Core, 15 tests de plus). Ce que l'utilisateur voit change : **414 sections** à la
      place de la liste à plat, **1759 descriptions** sous les libellés (2 lignes au
      plus), **954 listes déroulantes**, et une pastille « modifié » avec retour au
      défaut sur **161 réglages**. Un bandeau pour les **5** packs au `content.json`
      illisible ; rien pour les 246 mods C#, qui gardent l'arborescence de leur JSON.
      **Trois refus délibérés, tous mesurés** : pas de menu pour les **2801** clés qui
      n'admettent que `true`/`false` (l'interrupteur reste), pas de menu pour les **22**
      à choix multiple (leur valeur est une liste à virgules), et une valeur absente de
      la liste que son propre schéma admet (**8** clés) est gardée, mise en tête du menu
      et signalée — jamais remplacée.
      **Confronté au parc** : 462 fichiers fusionnés, **11 891 feuilles → 11 891
      rangées, 0 perdue**, 0 retour au défaut inécrivable. C'est cette confrontation —
      pas les tests — qui a trouvé le dernier défaut : quand la valeur du fichier ne
      diffère de celle du schéma que par la **casse** (`spring` contre `Spring`, 3 clés),
      rendre l'orthographe du schéma faisait réécrire le fichier au premier passage dans
      le menu. C'est celle du fichier qui est retenue.
      ▸ **Ce que la vérification à l'écran a trouvé, et que les tests ne pouvaient pas
      voir** (2026-08-28) : les `Name` et `Description` d'un schéma **ne sont pas
      toujours du texte**. Content Patcher y accepte le jeton
      `{{i18n: config.Appearance.Name}}`, résolu à l'exécution contre le `i18n/` du pack.
      L'écran les affichait bruts — **moins lisible que la clé** qu'il montrait avant le
      branchement. 9 packs, 285 jetons, dont le cas de démonstration lui-même.
      **Et la mesure a rapporté dix fois plus que le correctif** : Content Patcher cherche
      aussi `config.<clé>.name` **sans jeton**, par convention — 1888 des 2061 clés des
      116 packs à table y trouvent un libellé, contre 173 `Name` explicites sur tout le
      parc. `Models/ContentPackI18n.swift`, 10 tests, table lue par `I18nLenientParser`.
      Sur les 462 fichiers : **148 → 1889 libellés** autres que la clé, 1926 descriptions,
      268 sections traduites sur 414, **0 jeton brut à l'écran**.
      ▸ **Quatre retours d'écran corrigés dans la foulée** : l'onglet **visuel** par défaut
      (`MainView` ouvrait sur le JSON brut), les deux points d'entrée renommés
      « Réglages du mod » puisque c'est ce qu'ils ouvrent, une **colonne de contrôles
      alignée** — interrupteurs, listes et incrémenteurs tombaient à trois abscisses
      différentes, la place du bouton de retour au défaut étant désormais toujours
      réservée —, et la **description d'un réglage entière** au lieu de tronquée à
      deux lignes : 158 des 1926 du parc dépassent deux lignes, une seule cinq.
      ⚠️ **Leçon à retenir** : la confrontation au parc comptait 1759 descriptions sans
      jamais regarder **ce qu'elles contenaient**. Compter n'est pas lire.
- [x] **C4-T5** — `§audit-config-menus` — **Sortir l'éditeur de `JSONSerialization`.**
      Défaut indépendant des menus de config, trouvé en instruisant C4-T3, et le plus
      coûteux des trois : `ModConfigEditorView` lit et réécrit le `config.json` avec
      `JSONSerialization` alors que **`ConfigJSONTree` existe dans Core, testé, et
      préserve l'ordre des clés** (livré par B3-T5). Trois conséquences mesurables —
      l'éditeur **refuse** tout `config.json` en JSON5 (commentaire, virgule traînante)
      et affiche « JSON invalide » ; il liste les options **par ordre alphabétique**
      (`dict.keys.sorted()`) au lieu de l'ordre voulu par l'auteur ; et il réécrit le
      fichier avec `.prettyPrinted`, dont **l'ordre des clés est celui du dictionnaire**,
      pas celui du fichier. Il dépose en outre un `.bak` à côté du fichier au lieu de
      passer par `ModConfigBackupManager`. · **M**
      **Les quatre points, repérés** — `ModConfigEditorView.swift` : validation et
      lecture par `JSONSerialization` (`:242`, `:252`, `:295`), tri alphabétique à
      l'affichage (`:295`, `dict.keys.sorted()`), réécriture `.prettyPrinted` dont
      l'ordre est celui du dictionnaire (`:349`, d'où le rattrapage `\\/` → `/` juste
      après), et sauvegarde en `.bak` voisin (`:359`) au lieu de
      `ModConfigBackupManager`. `ConfigJSONTree.parse` / `.write` couvrent déjà les
      trois premiers besoins ; c'est un remplacement, pas une écriture.
      **Cas de démonstration, sur son parc** : `[CP] More Upgrades`, actif, **87 clés
      que l'auteur a réparties en 15 sections avec 75 descriptions** — l'écran les
      affiche aujourd'hui à plat et par ordre alphabétique, ce qui met
      `BigSilo_BuildCost` à côté de `BigSilo` et très loin de `SuperBarn`.
      ⚠️ **À passer avant le reskin de cet écran par l'axe H** : re-styler une liste
      triée alphabétiquement et incapable d'ouvrir un JSON5 fige le défaut sous une
      nouvelle peau.
      ⚠️ **Vérification humaine obligatoire** : c'est du code de vue, hors de portée de
      `swift test` ; le seul gate automatique est la compilation, et tout l'enjeu est un
      comportement d'écran. Ne pas livrer sur « ça compile ».
      ✅ **Livré le 2026-08-28, et vérifié à l'écran par lui le même jour** — la
      vérification humaine que cette tâche exigeait est faite ; le comportement d'écran
      (ordre des options, champ décimal, bouton de restauration) est confirmé.
      La logique est sortie de l'écran vers
      `Models/ConfigEditorModel.swift` (Core, 24 tests) plutôt que réécrite dans la vue :
      c'est le seul filet automatique possible ici. `ModConfigBackupManager` gagne
      `onlyEnabled:` et `mostRecentBackedUpFile` (5 tests). 1598 tests, gate `EXIT=0`.
      **Confronté au parc, pas aux seules fixtures** : les **462** `config.json` de
      premier niveau sont lus, **0 fichier** dont l'ordre affiché diffère de l'ordre du
      fichier, et les **11 891 options** rejouées **une par une** sur l'arbre d'origine —
      l'opération réelle d'une édition — rendent **un arbre identique dans tous les cas**
      (0 chemin perdu, 0 littéral réécrit, 0 valeur changée).
      *(La première version de ce relevé ne prouvait rien : elle comparait la sortie de
      `ConfigJSONTree.write` à ce que `write` vérifie déjà lui-même avant de rendre.)*
      **Répartition des 11 891 options** : 5834 interrupteurs, 2718 textes, 2581 entiers,
      **758 décimaux** — ces derniers s'affichaient `0` au lieu de `0,5`, un
      `NumberFormatter` nu n'ayant aucune décimale. Défaut antérieur à T5, corrigé ici.
      ⚠️ **Deux des quatre points sont des durcissements, pas des correctifs de son
      vécu** — mesuré avant d'écrire : **0** `config.json` de premier niveau du parc est
      en JSON5, et **0** dossier n'est en lecture seule (rien à faire côté X7 ici). Le
      gain chiffré est ailleurs : **363 des 462** fichiers ont un ordre d'auteur
      différent de l'alphabet.
      ▸ **Ce que la migration a révélé et qui n'était pas au repérage** : l'éditeur
      s'ouvre aussi sur un mod **en pause**, et c'est le cas **majoritaire** — **379 des
      462** mods à `config.json` sont en pause. `createBackup` filtrait `isEnabled` et
      aurait levé `noEnabledMods` huit fois sur dix, laissant l'enregistrement sans
      filet ; d'où `onlyEnabled:`, et la lecture par `physicalFolderName`.
      ▸ **Un changement de comportement à valider à l'écran** : « Restaurer la
      configuration » **charge** la sauvegarde dans l'éditeur au lieu d'écraser le
      fichier sur-le-champ — c'est « Enregistrer » qui écrit, après avoir mis la version
      actuelle à l'abri. Les `config.json.bak` déjà déposés restent lisibles en second
      recours.
      ▸ **Ce que T5 seul ne donne pas** : sur `[CP] More Upgrades`, l'écran montre 87
      clés **en ordre d'auteur mais toujours à plat**. Les 15 sections et les 75
      descriptions viennent du `ConfigSchema` — c'est **C4-T4**, dont le socle est livré
      et le branchement reste à faire.
      ▸ **Tranché le 2026-08-28 : une sauvegarde par mod et par jour.** Chaque
      « Enregistrer » en déposait une, et le ménage automatique ne supprime qu'au-delà de
      30 jours — dix réglages modifiés dans l'après-midi mettaient dix lignes d'un seul
      mod devant les sauvegardes complètes. C'est la **première du jour** qui reste,
      jamais remplacée : elle porte l'état avec lequel le jeu a tourné avant qu'on y
      touche, quand l'écraser à chaque enregistrement laisserait une mauvaise
      modification manger le filet en deux saves — le défaut du `.bak` roulant qu'on
      vient justement de retirer. Une sauvegarde générale du même jour compte aussi :
      elle contient le fichier, donc elle protège. `backupFromToday`, 3 tests.
      ▸ **Angle mort connu, hors parc** : `physicalFolderName` préfixe le point au
      **chemin entier** (`.Pack/Composant`), donc un *composant* de pack mis en pause
      serait cherché au mauvais endroit — par l'éditeur comme par la sauvegarde, qui
      restent au moins cohérents. Zéro cas sur le parc (un seul dossier pointé imbriqué,
      et c'est un `.config`).
- [x] **C4-T6** ✅ *(corrigé le 2026-09-04)* — **Dire quand le fichier va être réécrit
      sous nos pieds** — et refuser de l'écraser en aveugle.
      Un mod C# rappelle `WriteConfig` quand il veut (UltraSmooth : 4 sites — migration,
      profil, commandes ; MCM : 5 ; et la vue « raccourcis » de GMCM en réécrit N d'un
      coup). L'éditeur lisait `config.json` à l'ouverture et le **remplaçait en bloc** à
      l'enregistrement, sans jamais relire : une session de jeu ouverte à côté suffisait
      à faire disparaître ce que le mod venait d'écrire.
      ▸ **Le filet ne rattrapait pas ce cas.** `backUpCurrentConfig` ne garde qu'une
      sauvegarde par mod et par jour, et c'est la **première** (règle voulue). Éditer à
      10 h, laisser le mod réécrire à 14 h, éditer à 15 h : la seule copie du jour est
      celle d'avant 10 h, et l'état de 14 h n'existe plus nulle part. Le contrôle à
      l'enregistrement n'est donc pas un supplément de prudence — c'est ce qui protège
      cet état-là.
      ▸ **Livré.** `ModConfigWriteGuard` (Core, 10 tests) compare le texte chargé, le
      texte relu juste avant d'écrire et le texte à écrire : `proceed` quand le disque
      n'a pas bougé, quand le fichier a disparu, ou quand il porte déjà au caractère
      près ce qu'on allait écrire ; `externallyChanged` sinon ; **`unverifiable` quand
      la relecture échoue** — une lecture ratée n'est pas un consentement (le piège de
      X25 en miniature). Les deux derniers ouvrent une alerte qui dit ce qui est en jeu,
      « Enregistrer quand même » à un clic. Comparaison sur le texte entier : un simple
      reformatage compte pour une réécriture, et rien ne compare ligne à ligne (`\r\n`
      est un seul `Character`).
      ▸ Bandeau « jeu en cours » dans les deux onglets de l'éditeur, évalué **dans** le
      `body` (l'idiome de `SavesView`) pour qu'un jeu lancé après l'ouverture le fasse
      apparaître — et conditionné à `mod.isEnabled` : un mod en pause n'est pas chargé
      par SMAPI et ne peut rien réécrire, or **379 des 462 mods à `config.json`** du parc
      sont en pause. 6 clés L10n en/fr.
      ▸ **Prévisualisation de normalisation : écartée, mesurée.** La piste gratuite —
      lire les bornes dans la prose des infobulles — ne couvre rien : sur les **5 476
      clés `config.*`** du parc, **24 clés dans 8 mods** portent une borne numérique
      explicite (`(1-20)`, `(0 to 100)`), soit 0,4 %, et un motif plus large ramène
      surtout des faux positifs (« Monster Range Detection »). Surtout, elle rate le mod
      qui motivait la tâche : les **24 clamps de SLO vivent dans `Normalize()`**, aucun
      en prose. Une table curative codée en dur périmerait au prochain
      `OptimizationProfileVersion`. → **C4-T8**. · **S**
- [x] **C4-T2** — Champs de raccourcis clavier : validation des noms `SButton`, détection
      des collisions entre mods. · **M**
      `§audit-config-menus` : la tâche est confirmée par l'existence de
      `Overlays.KeybindOverlay` / `KeybindEdit` dans GMCM — c'est la référence
      d'ergonomie à regarder, pas un code à porter (aucune donnée n'en sort).
      ✅ **Livré le 2026-08-29, sur son parc réel** (92 mods actifs) :
      **141 liaisons lues, 18 collisions, 11 conflits jeu** — chiffres
      d'écran après la règle du catalogue, pas ceux de la mesure Python de
      la tâche 0. Le rapport vit dans les Alertes système (groupes repliés
      au-delà de 10, « Relancer l'analyse » inconditionnel), les mêmes
      lignes sur la fiche du mod, un bouton « Réglages du mod » par ligne
      citée, et la pastille Alertes système compte collisions et conflits
      jeu — jamais les « non reconnus », valeurs illisibles plutôt que
      problèmes avérés. La logique est en Core (`SButtonTable` figée du
      relevé IL, `KeybindParser`, `KeybindScanner`) : **1656 → 1692
      tests** sur le plan. Depuis la ronde finale de revue, enregistrer une
      config depuis l'éditeur relance le scan — le rapport ne reste plus
      sur l'état d'avant la correction.
      ▸ **Sémantique exact-combo** : une collision, ce sont des mods qui
      partagent **la même combinaison exacte** (`LeftControl + F8`), pas
      des combinaisons qui se chevauchent — un modificateur seul partagé
      n'alarme personne (contre-exemple MCM, non-régression testée).
      ▸ **Règle du catalogue (R4)** : plus de **8** combinaisons distinctes
      sous une même forme de chemin **dans un même mod** ⇒ documentation,
      pas des liaisons — écartée du scan, et le mod écarté reste nommé à
      l'écran. Marge mesurée : 42 combinaisons distinctes pour le catalogue
      réel (`ModShortcutReferenceHub`), 2 au maximum légitime observé.
      ⚠️ **Angles morts restants** : les chevauchements sous-ensemble ne
      sont pas détectés (A = `K`, B = `K`+Shift co-déclenchent sur le
      geste long — spec §12, consigné) ; composants de pack et mods en
      pause héritent de l'angle mort `physicalFolderName` de C4-T5 (zéro
      cas mesuré) ; les 27 noms de contrôles du jeu restent en anglais
      (champs C# bruts, chantier à part) ; un `config.json` illisible
      compte silencieusement comme scanné-vide (un cas réel, en pause).
- [x] **C4-T3** — ✅ **Spike mené le 2026-08-28. Verdict : non-go sur les menus de
      config — et une meilleure source trouvée à côté.** `§audit-config-menus`, détail
      dans [`audit-config-menus.md`](audit-config-menus.md). Décompilation IL (`ikdasm`)
      des deux DLL, archives fournies par l'auteur.
      ▸ **GMCM 1.16.0 n'écrit rien** : aucun `File::Write*`, aucun `JsonConvert` dans
      31 325 lignes d'IL. Il n'écrit pas même le `config.json` — son
      `Register(manifest, reset, save)` reçoit une **fermeture** que le mod exécute
      lui-même. `Name` et `Tooltip` sont des `Func<string>` évalués au rendu : il n'y a
      rien de statique à lire.
      ▸ **Modern Config Menu 1.7.4 écrit un fichier**, `config_exports/<UniqueID>.json`,
      mais c'est un `Dictionary<string,string>` **libellé affiché → valeur** : des
      *valeurs*, pas un schéma. Ni type, ni bornes, ni valeurs admises, ni clé de
      `config.json`.
      ⚠️ **Corrigé le 2026-08-28** : le spike avait conclu de la seule classe
      `GenericModConfigMenuCompat` que MCM n'accédait pas aux données de GMCM. **Il y
      accède** — par un chemin `[MCM GMCM-Import]` qui **réfléchit dans la mémoire vive**
      de GMCM (`GenericModConfigMenu.Mod` → `instance` → `ConfigManager` → `configs`).
      C'est ce qui lui permet d'annoncer que tous les mods GMCM sont stylés
      automatiquement. **Sans conséquence sur le verdict** : ce chemin n'écrit rien
      (0 `WriteJsonFile`), et il ne marche que **dans le processus du jeu**.
      ▸ **La décompilation des DLL de chaque mod reste écartée**, comme prévu : rien dans
      ce spike ne la réhabilite.
      ▸ **Ce que le spike a rapporté** : la vraie source est ailleurs — le `ConfigSchema`
      de Content Patcher, sur le disque et complet → **C4-T4**, désormais devant C4-T1.

## 5. Roadmap par chantier

### Profils, favoris & backups exploitables — **Axe B** · **B4 livré en v1.18.0**, B3 aux trois quarts


#### B3 — Profils

- [x] **B3-T1** — Choix à la création : profil **vide** (défaut demandé) ou instantané des
      mods actifs. · **S** · *validé à l'écran le 2026-08-24 : la touche Entrée crée bien
      un profil vide. Annoncé au CHANGELOG (§Changed). La décision qui n'allait pas
      de soi : un profil vide ne peut pas devenir actif à sa création — `syncActiveProfileIds`
      réécrit le profil actif depuis le disque à chaque scan, et l'aurait rempli des mods en
      cours dans la foulée. `ProfileFactory` (Core) porte les deux règles, testées.*
- [x] **B3-T2** — Favoris de mods, avec « importer les favoris dans ce profil ». *Livré :
      étoile sur chaque ligne de premier niveau et sur la fiche, pastille de cadrage dans la
      barre d'outils, entrée « Importer les favoris » au menu ⋯ d'un profil.
      **L'asymétrie des clés est le cœur de la tâche** : un favori se marque sur une ligne,
      donc se désigne par son `folderName` **logique** (qui survit à une mise en pause),
      quand un profil ne connaît que des `UniqueID` — et entre les deux, les packs, dossiers
      de premier niveau sans identifiant à eux. `FavoriteResolution` (Core, 12 tests) porte
      cette traduction : un pack apporte tous ses composants, la déduplication ignore la
      casse comme `addModToProfile`, et les favoris intraduisibles (désinstallés, ou sans
      identifiant au manifeste) sont **nommés** au lieu d'être écartés en silence comme le
      fait `applyEnabledFolders`. L'import est **une seule mutation** : boucler sur
      `addModToProfile` aurait réappliqué le profil au disque à chaque mod. Sur le profil
      actif il demande confirmation, puisqu'il active les mods immédiatement.* · **M**
- [x] **B3-T3** — Duplication d'un profil. · **S** · *`ProfileFactory.duplicate`, la copie
      porte son propre identifiant et n'est pas activée.*
- [x] **B3-T4** — Diagnostic de profil au changement : mods manquants, dépendances non
      satisfaites, couverture FR (réutilise **C1-T1**). · **M** · *partiel (2026-08-24) :
      les **mods manquants** sont livrés — `ProfileDiagnostics` (Core, 14 tests), pastille
      sur la ligne du profil, écran nommant chaque mod, restauration depuis une sauvegarde
      et téléchargement Nexus quand l'identifiant est connu. Le profil retient désormais
      nom et identifiant Nexus de ses mods (`ProfileModMetadata`) : c'est la seule source
      qui couvre, mesuré sur le parc réel — sur les 16 mods manquants de ses deux profils,
      2 ont une sauvegarde, 1 un identifiant Nexus en cache, 2 sont livrés avec SMAPI.
      Pastilles validées à l'écran le 2026-08-24. Les **dépendances non satisfaites**
      ont suivi le même jour : `ProfileDiagnostics.dependencyGaps` réutilise
      `ModDependencyStatus` en lui passant l'état **futur** du parc (celui qu'aura le
      profil une fois appliqué), plutôt qu'une seconde règle qui en aurait divergé ;
      la dépendance installée mais laissée hors du profil s'y ajoute d'un clic. Mesuré
      avant d'écrire : ses trois profils sont **complets** (344, 628 et 73 dépendances
      requises, aucune insatisfaite) — l'écran ne montrera rien sur eux, et c'est le
      résultat attendu. Le cas visé est le profil **vide** qu'on remplit mod par mod
      depuis B3-T1, où l'on oublie un cadre.
      **Complété le 2026-08-27** par la **couverture FR du profil**. Deux
      décisions ont façonné la tâche.
      **Un store séparé.** `frenchCoverageByMod` ne contient que les mods qui
      livrent déjà du français, et son absence d'entrée *est* le troisième état
      de la pastille de la liste (« pas encore mesuré », C1-T2). Or les mods qui
      font tout l'intérêt de cet écran sont ceux qui ont un `default.json` et
      aucun `fr.json` — 23, 50 et 21 sur ses trois profils. Les y verser aurait
      fait surgir autant de pastilles « 0 % » dans une liste déjà livrée.
      **Une porte à soi.** L'écran de diagnostic ne s'ouvrait que par la
      pastille orange, laquelle n'existe qu'en cas de défaut : sur « TEST »
      (aucun mod manquant, aucune dépendance en souffrance) il était
      inatteignable, alors que c'est le profil le moins traduit. La pastille
      « FR 94 % · 23 à traduire » est donc cliquable et ouvre le même écran.
      L'agrégation porte sur les **clés**, pas sur une moyenne de pourcentages
      (`East Scarp: NPCs` pèse 11 021 clés à lui seul), et `ownDirectoriesOnly`
      empêche un mod imbriqué d'être compté deux fois — 6 cas sur le parc, dont
      3 avec un `i18n`. Mesuré avec le code livré : **94,4 %, 86,3 % et 93,8 %**
      des clés. Chaque rangée ouvre l'onglet Traduction du mod : sans geste, la
      section n'aurait fait que constater.*
- [x] **B3-T5** — **Configurations par profil** : un même mod peut avoir des `config.json`
      différents selon le profil (ex. CJB Cheats configuré en solo, désactivé en multi).
      Capture/restauration au changement de profil avec **merge JSON non-destructif**
      (`JsonTools.Merge` côté Stardop) pour ne pas écraser les réglages existants. Opt-in,
      aucun swap sans backup préalable (réutilise `ModConfigBackupManager`). · **L** ·
      *§audit-stardrop · le chantier le plus volumineux issu de l'audit.*
      **Instruit le 2026-08-27** — design dans
      `docs/superpowers/specs/2026-08-27-configs-par-profil-design.md` (dossier
      gitignoré : la spec vit en local). Quatre choses que la mesure du parc a
      tranchées, et qui changent la forme de la tâche :
      - **La population existe** : 3 profils (COMPLET 329, OK 529, TEST 125), et
        **169 mods portant un `config.json` sont actifs à la fois dans COMPLET et
        OK**, 51 dans les trois. Sur 1015 dossiers de mods, 547 portent un config
        — mais **92 seulement parmi les 125 actifs**, l'écart étant les mods en
        pause qui n'ont jamais tourné : le `config.json` est **généré, pas livré**,
        et « le fichier n'existe pas encore » est un cas normal.
      - **SMAPI réécrit tous les configs à chaque lancement** (90 sur 92 au même
        horodatage à la minute près). La fidélité textuelle parfaite est donc
        inutile — mais **l'ordre des clés ne doit jamais être trié** : SMAPI écrit
        dans l'ordre des champs de la classe C# (1 fichier sur 79 est en ordre
        alphabétique), et `JSONSerialization` rend un dictionnaire **non ordonné**.
        L'aller-retour par `JSONSerialization` est interdit sur un config — ce que
        fait pourtant `ModConfigEditorView.swift:349` aujourd'hui.
      - **Deux chemins de perte fermés dans le design.** La capture ne doit avoir
        lieu que sur une transition réelle A→B : à la **reprise d'une application
        incomplète**, le disque porte déjà les réglages du profil *entrant*, et les
        capturer au crédit du sortant écraserait son config dans le geste censé
        rattraper l'erreur. Et le point d'accroche est **`applyProfile`**, jamais
        `applyProfileToFilesystem` — que la **bissection** emprunte avec un profil
        éphémère et `activeProfileId` à `nil`, des dizaines de fois d'affilée.
      - **Le merge n'est plus le premier morceau.** Mémoriser le config en **texte
        brut** préserve l'ordre gratuitement et avale les 2 configs illisibles du
        parc sans parseur ; le parseur JSON ordonné, seul vrai morceau neuf, arrive
        **après** que la fonctionnalité marche. Livrable dès l'étape 3 sur 7.
      Limite assumée : l'app **ne peut pas dire quels mods marquer** — aucun
      historique par profil, et les 4 sauvegardes de configs existantes ne portent
      aucune attribution de profil. Outil tourné vers l'avant.
      **Étapes 1 à 4 livrées le 2026-08-27** : magasin, capture/restauration,
      fiche et icône.
      **Étapes 5 à 7, livrées le 2026-08-27 sauf une** : parseur JSON à l'ordre
      des clés préservé (`ConfigJSONTree`) et son écrivain au format SMAPI, la
      fonction de fusion (`ConfigJSONMerge`, disque par-dessus mémorisé), la
      comparaison clé à clé (`ConfigJSONDiff`) et son écran « Comparer avec… »,
      les orphelins nommés sur la fiche du profil, et la fusion accrochée à la
      restauration. Le préalable a été vérifié en jeu le 2026-08-27 : SMAPI
      recomble bien une clé retirée d'un `config.json`, l'affirmation de la
      spec §5.3 tient. B3-T5 est complet, **validé à l'écran le 2026-08-27**
      (fusion à la restauration et choix du profil successeur à la
      suppression).
- [x] **B3-T7** — Supprimer un profil laisse son magasin de configs derrière lui.
      `deleteProfile` (`StarHubTHViewModel.swift:7002`) retire le profil des préférences
      sans toucher à `Application Support/StarHubTH/ProfileConfigs/<uuid>.json` : le
      fichier n'est plus jamais lu — aucune surface ne le nomme, `profileConfigSummary`
      ne parcourt que les profils existants — et n'est jamais effacé. · **S**
      *Constaté le 2026-08-27 sur le parc réel : le dossier porte deux magasins, dont un
      (`D44530B0…`, 3,1 Ko, 5 configs, écrit à 16:39:53) qui n'appartient à aucun des
      trois profils. Effacer un magasin est un chemin de suppression neuf, donc à
      instruire — l'alternative honnête étant de le laisser et de le dire quelque part.*
      **Livré le 2026-08-27.** Arbitrage de l'auteur : effacer, et balayer les
      magasins déjà orphelins au démarrage. La décision se prend au dialogue de
      suppression, qui nomme le nombre de configs perdus — seulement s'il y en
      a. La logique est pure et en Core (`orphanFileNames`, 4 tests) : une
      liste de profils **vide** ne rend jamais d'orphelin (des préférences
      illisibles donnent exactement cette liste, et le balayage viderait le
      dossier), seuls les noms `<UUID>.json` sont candidats, et la comparaison
      ignore la casse — le nom vient du disque, pas de `UUID.uuidString`.
      Un effacement qui échoue ne remonte nulle part, à dessein : le profil
      ayant disparu, le fichier est devenu orphelin et le balayage suivant le
      reprend.
- [x] **B3-T6** — Notes libres par mod, persistées au profil (annotations contextuelles :
      « désactivé en multi car désync », « à mettre à jour »). · **S** · *§audit-stardrop*
      **Livré le 2026-08-27.** Deux arbitrages de l'auteur en séance : la note
      appartient au **profil actif** (elle documente l'usage du mod dans ce
      profil — sans profil actif, la section reste visible et l'explique au
      lieu de disparaître) ; et elle se **signale dans la liste** (icône près
      du nom, note en infobulle), car on note justement pour s'en souvenir en
      parcourant la liste — sans indicateur, la note ne se retrouverait qu'en
      ouvrant les fiches une à une.
      `ModProfile.modNotes` (Core, 4 tests) suit l'**identité** du mod
      (`UniqueID`), pas son dossier : la note survit à une mise en pause.
      Décodeur tolérant au patron de `modMetadata` — les profils enregistrés
      avant les notes se relisent sans rien perdre, test dédié. Une note vidée
      est **retirée**, jamais rangée vide. L'en-tête d'un pack ne porte pas de
      note (pas d'identité, **F4**) ; ses composants se notent eux-mêmes.
      Sauvegarde à la perte du focus, au patron du draft Nexus — la vue est
      recréée par mod (`.id(mod.folderName)`), un brouillon ne peut pas fuir
      sur le mod voisin.
      *Corrigé dans la foulée du premier retour réel (2026-08-27)* : deux
      défauts. **L'infobulle ne venait jamais** — la cause n'était pas le
      tooltip mais sa cible : un glyph de 10 pt est plus petit que le curseur
      immobile qu'exige macOS (~2 s entièrement dans la zone), et le
      mécanisme, lui, marche dans cette liste (`authorLabel` pose un `.help`
      passif sur un `Text` de la même ligne depuis des versions). Zone de hit
      portée à 18×18 (`contentShape`), dessin inchangé. **Vider la note puis
      cliquer un autre mod ne vidait rien** — cliquer un autre mod remplace
      la vue (`.id`) avant que la perte de focus ne tire, et le vidage n'était
      jamais committé ; la fiche commette désormais aussi à `onDisappear`,
      idempotent avec le blur.*

#### B4 — Page de backups

- [x] **B4-T1** — Regroupement par mod puis par version, tri (dernier backup, A→Z, Z→A),
      recherche. · **M** · *livré le 2026-08-22 (`7c9efce`), sorti en **v1.18.0** — `Models/BackupBrowser.swift`.*
- [x] **B4-T2** — Retour utilisateur explicite après restauration (ce qui a été écrit, où). · **S** ·
      *validé à l'écran le 2026-08-24.*
      *`ModInstallRestoreReport` (Core, testé) : mod, version, nombre de fichiers, chemin
      lisible, actif ou en pause, versions remplacées et conservées. La page l'affiche avec
      « Afficher dans le Finder » ; la même phrase part au journal.*
- [x] **B4-T3** — Garantir qu'une restauration met à jour le registre : version, écrasement
      du dossier existant, recréation s'il a disparu. · **M** · *validé à l'écran le
      2026-08-24 — l'alerte du compte rendu s'affiche bien après la confirmation.* *les tests de
      caractérisation ont trouvé le défaut : restaurer un mod **actif** copiait la
      sauvegarde dans `Mods/.Nom` sans toucher à `Mods/Nom`. Deux dossiers pour un même
      `folderName` — la clé du registre, des profils et des sauvegardes — et le mod
      restauré invisible du jeu. La restauration remplace désormais le mod où il se
      trouve, actif ou en pause, et ne repart en pause que s'il n'est plus installé.
      Le rafraîchissement du registre lui-même reste appelé depuis la vue
      (`vm.refresh()`), hors de portée des tests Core. La clause « version » a
      découvert un second défaut : `ModVersionAnchorRules.afterDiskChange` refuse
      de faire **descendre** une ancre — une version qui change sans rejoindre la
      cible passe pour une mise à jour inachevée. Un retour arrière laissait donc
      l'ancre sur la version remplacée, et `SmapiUpdateRequest` envoyait celle-ci
      à smapi.io : le mod rétrogradé était annoncé « à jour ». La restauration
      pose désormais une ancre `.install`, comme toute installation menée par
      l'app.*
- [x] **B4-T4** — **Récupérer un fichier isolé depuis une sauvegarde**, sans restaurer le mod
      entier : `i18n/fr.json` et `config.json`. Une mise à jour de mod écrase le dossier et
      emporte ce que l'auteur ne redistribue pas — traduction communautaire, réglages.
      Mesuré le 2026-08-01 sur le parc réel (951 mods installés, 74 présents en sauvegarde) :
      **16 `fr.json`** et **1 `config.json`** absents mais retrouvables ; 10 `config.json` de
      plus divergent de leur sauvegarde.
      Trois exigences, la deuxième étant celle qui coûte :
      1. **Détection** — croiser les dossiers de mods de `Backups/{ModInstalls,ModConfigs}`
         avec le parc installé ; modèle Core testable (cf. `ModInstallBackupManager`,
         `ModConfigBackupManager`, qui ne savent aujourd'hui restaurer qu'en tout-ou-rien).
      2. **Ne pas confondre divergence et perte** — pour `config.json`, un fichier différent
         de la sauvegarde est le cas *normal* : l'utilisateur a réglé le mod depuis. Ne
         proposer la récupération que sur un fichier **absent**, ou revenu aux valeurs par
         défaut alors que la sauvegarde en portait de personnalisées, ce qui suppose une
         comparaison clé à clé et non octet à octet. Un faux positif ici écrase des réglages
         voulus : la faute est plus grave que l'oubli. ⚠️ « Revenu aux valeurs par défaut »
         n'est pas directement observable — SMAPI les régénère depuis le code du mod, pas
         depuis un fichier de référence. Les deux seuls signaux sûrs sont donc « absent » et
         « la sauvegarde porte des clés que l'installé n'a plus ».
      3. **Écriture explicite** — aperçu du contenu avant écrasement, action par fichier et
         par mod, jamais en lot silencieux. · **L**
      ✅ **Livré le 2026-08-24.** `FileRecoveryRules` porte la règle des deux signaux sûrs,
      `RecoverableFileScanner` croise les sauvegardes d'installation avec le parc (entrées
      injectées, 13 tests). L'écran s'ouvre depuis la page des sauvegardes : aperçu du
      contenu, récupération fichier par fichier, et sauvegarde préalable de ce qui est en
      place. Remesuré le jour même : **10 `i18n/fr.json`** absents de l'installé et présents
      en sauvegarde, **0 `config.json`** absent, **1** dont la sauvegarde porte 2 clés que
      l'installé n'a plus. *Reste possible plus tard : les sauvegardes de configs
      (`Backups/ModConfigs`) comme seconde source — 3 lots seulement sur le parc, contre 145
      dossiers côté installations.*
      ✅ **Complété le 2026-08-24 à la demande de l'auteur** : récupération **clé à clé**
      d'une traduction (`TranslationRecoveryDiff`, 10 tests) — une mise à jour rend le
      fichier à l'anglais, le traducteur en refait une partie, et remplacer le fichier
      entier lui coûterait ce qu'il vient d'écrire. Seules les clés que l'installé n'a
      plus sont réinjectées, par `TranslationDocument` qui conserve l'ordre et la forme.
      L'écran montre le diff complet : clés seulement en sauvegarde (récupérables), clés
      ajoutées depuis, valeurs divergentes côte à côte. Les traductions qui **diffèrent**
      sans rien avoir perdu sont listées pour comparaison seule — trois cas sur le parc
      (92 valeurs changées, 27 et 39 clés ajoutées) — là où un `config.json` divergent
      reste, lui, délibérément absent : c'est le cas normal.*

#### B2 — Ergonomie transverse

- [x] **B2-T1** — ETA et débit pendant les téléchargements Nexus, et **panneau de downloads
      observable** : statut par téléchargement, %, vitesse, annulation, retry (inspiration :
      `DownloadPanel` de Stardop). Aujourd'hui StarHubFR ne fait que du
      `URLSession.downloadTask` fire-and-forget, sans progression live. · **M** · *§audit-stardrop*
      **Livré le 2026-08-27, sans le panneau — et c'est le point.** L'app
      **sérialise** les téléchargements à dessein (`rejectNexusDownloadIfBusy`) :
      deux en vol se disputeraient `pendingDownloadedZip`. Un panneau de
      transferts concurrents n'aurait donc rien à lister. Ce qui manquait
      n'était pas une liste mais **un téléchargement rendu observable** :
      pourcentage, volume, débit, temps restant et **annulation**, en pied de
      barre latérale — un lien `nxm://` peut arriver du navigateur quel que
      soit l'onglet ouvert — et repris sur la ligne des mises à jour.
      **Le risque était le passage au délégué.** `URLSession.downloadTask(with:
      completionHandler:)` garantissait une complétion unique, et tout en
      dépend : `isDownloadingFromNexus` n'est remis à `false` que là, et sans
      cela le bouton reste condamné pour la session. Le délégué, lui, sépare
      cela en `didFinishDownloadingTo` **puis** `didCompleteWithError(nil)`, qui
      se produisent tous deux sur un téléchargement normal. `NexusFileDownload`
      porte donc la garantie lui-même — un drapeau relevé sous verrou par le
      premier qui parle — et **toutes** les sorties y passent, échecs d'API
      compris. Trois autres pièges traités : le fichier temporaire est supprimé
      au retour de `didFinishDownloadingTo` (déplacement synchrone) ; la
      session retient fortement son délégué jusqu'à `finishTasksAndInvalidate` ;
      et `didWriteData` tire des centaines de fois par seconde, d'où un rapport
      limité à dix par seconde — la faute qui avait rendu la vue des journaux
      inutilisable. Annuler n'est **pas** une erreur : `NSURLErrorCancelled`
      devient `.cancelled`, que les trois appelants taisent au lieu d'ouvrir une
      alerte sur un geste volontaire. Le débit est lissé sur trois secondes
      (`DownloadRateEstimator`, Core, 8 tests) : instantané il sauterait d'un
      facteur dix, cumulé il masquerait un effondrement de connexion. Et
      **sans taille annoncée** — `expectedContentLength` vaut `-1` plus souvent
      qu'on ne croit sur un CDN — ni barre, ni pourcentage, ni ETA : seulement
      le volume et le débit, qui sont vrais.*
- [x] **B2-T2** — Poids par mod, total de `Mods/`, espace disque restant (en pied de barre
      latérale). *Livré : `Models/ModsFolderSizer.swift` pèse chaque dossier de premier
      niveau (place **allouée**), la mesure tourne en fond après chaque `scanMods()`, une
      passe à la fois. Deux pièges écartés : la jointure se fait sur le nom **physique**
      (`physicalFolderName`), sans quoi tout mod en pause afficherait 0 octet ; et le
      parcours n'utilise pas `.skipsHiddenFiles`, qui sauterait ces mêmes dossiers. Mesuré
      sur le parc réel : 863 dossiers, 103 893 fichiers, 16,84 Go — **dont 12,71 Go de mods
      en pause (746 sur 863)** — pour 24,9 Go libres, en 5,6 s. D'où le sous-total « en
      pause » et la place restante en orange sous le seuil.* · **M**
- [x] **B2-T3** — Boutons de rafraîchissement sur la quarantaine et les alertes système ;
      sur la fiche mod, rafraîchissement **automatique** dès qu'un NexusID est saisi. · **S**
      *Livré le 2026-08-26. Quarantaine : « Relancer l'analyse » rejoue `refresh()` —
      le rafraîchissement manuel établi (accueil, installations), seul chemin qui
      relance la réparation dont la page publie le rapport — inactif pendant le scan
      (`scanProgress`). Alertes système : « Revérifier le journal » appelle un neuf
      `refreshSmapiLog()`, qui relit **le seul journal SMAPI** sur un thread
      d'arrière-plan — la page ne montre que ce que dit le journal, rescaner 863
      dossiers pour relire un fichier serait un contresens ; bouton présent dans
      l'état vert aussi, car un journal silencieux avant une installation ne dit
      rien d'après. La part « fiche mod » était déjà couverte : la saisie manuelle
      recharge (`commitDraft` → `loadModDetail` + `fetchMetadata`), et l'adoption
      d'un candidat A3-T1 fait de même depuis le correctif du jour — sans
      `loadModDetail`, la description restait celle du manifeste local jusqu'à la
      prochaine navigation, le défaut même que documente `commitDraft`. Au passage :
      l'état vide des alertes disait « Tous les mods sont à jour » — la clé des
      mises à jour Nexus, mésusée ; clé propre « Aucune alerte système », et la
      clé morte retirée des trois endroits.*
      *Corrigé dans la foulée du premier retour réel (2026-08-26) : les deux
      pages étaient **conditionnelles** dans la barre latérale — Quarantaine
      n'apparaissait que si le dernier rapport avait mis quelque chose en
      quarantaine, les Alertes que si des erreurs existaient. Les boutons de
      relance vivaient donc sur des pages **inaccessibles dans le cas commun**
      (parc sain, journal sans erreur) : la vérification était justement ce
      qu'on ne pouvait pas faire. Les deux entrées sont désormais permanentes,
      au patron de « Mises à jour » voisin (toujours visible, pastille masquée
      à zéro — `SidebarBadgeItem` le fait déjà), et la quarantaine sans rapport
      affiche le même message que le rapport vide plutôt qu'un blanc.*
- [x] **B2-T4** — Guidage quand `unrar`/`unar`/`7z` manque. *Socle déjà en place* : l'accueil
      affiche l'état d'installation de `unar` avec la commande Homebrew
      (`home_tool_unar_*`). Ce qui manque : au **moment de l'échec**, un message actionnable
      avec commande copiable — aujourd'hui une phrase anglaise codée en dur (cf. **X6**). · **S**
      *Audit du 2026-08-25 : **la phrase anglaise codée en dur n'existe plus.** X6 a
      livré le message localisé, et il s'affiche bien au moment de l'échec
      (`installErrorMessage` → `rarToolMissing`), commande Homebrew incluse. Ne reste
      que **copiable** : aucun `NSPasteboard` dans la feuille d'installation. La
      tâche a fondu à un bouton.*
      **Livré le 2026-08-26.** `InstallError.copyableCommand` (Core, 2 tests) porte
      la commande — celle-là même que le message d'erreur et l'accueil recommandent
      (`unar`, pas `unrar`) — et l'alerte de la feuille d'installation offre
      « Copier la commande » quand l'erreur en porte une, jamais sinon. Le message
      et la commande se posent ensemble par un helper unique (`showFailure`) : la
      feuille ne remet jamais son erreur à zéro, et une commande héritée d'une
      erreur précédente se serait affichée sur la suivante.
- [x] **B2-T5** — ~~Reprendre l'affichage des dates d'un mod~~ → **requalifié en
      ajout, puis livré.** · **S**
      *Revérifié le 2026-08-25 : **ce n'était pas un défaut d'affichage**. L'app ne capte
      qu'une seule date Nexus — `updated_timestamp` → `NexusModExtra.uploadedTime` — et
      les trois endroits qui la montrent la nomment juste : « MàJ » dans la liste
      (`ModListView.swift:1305`), « Dernière mise à jour » sur la fiche
      (`ModDetailView.swift:326`), la date du fichier dans le bandeau
      (`MainView.swift:794`). La date d'installation à côté vient du `manifest.json`,
      étiquetée « Installé ». `created_timestamp` n'est simplement **jamais demandé**.
      Restait donc un ajout — montrer l'âge d'un mod —, pas une correction.*
      **Requalifié en séance le 2026-08-27**, sur deux arbitrages de l'auteur :
      ce qu'il veut apprendre n'est pas la date de création (anecdotique) mais
      **l'âge depuis la dernière mise à jour** — le signal « ce mod dort » — et
      cet âge n'apparaît qu'**à partir d'un an révolu**, une mise à jour récente
      se lisant fraîche d'elle-même. `LastUpdateAge` (Core, 3 tests) porte le
      seuil ; le texte vient de `RelativeDateTimeFormatter` (rendu vérifié :
      « il y a 5 ans », « 5 years ago »), donc aucune clé L10n à tenir et la
      localisation suit le système. Affiché sur la **fiche seule**, à côté de la
      date : la liste porte déjà quatre badges par ligne, et le bandeau des
      mises à jour est redondant par construction — une ligne qui s'y trouve
      décrit un fichier *plus récent* que l'installé. `created_timestamp`
      reste non demandé, par décision.*
- [x] **B2-T6** — Quota Nexus quotidien visible (header `x-rl-daily-remaining`). *Livré :
      les six en-têtes `x-rl-*` sont relevés sur **toute** réponse Nexus — succès comme 429,
      car c'est le refus qui porte le « 0 restant » — par un `NexusQuota` pur
      (`Models/NexusQuota.swift`), persisté et affiché dans les réglages avec l'heure de
      remise à zéro. Une réponse sans ces en-têtes (la patte CDN d'un téléchargement) n'est
      pas une mesure à zéro : elle laisse la précédente intacte. L'app n'interrogeant plus
      l'API Nexus qu'à la demande, l'état « jamais mesuré » est explicite.* · **S** ·
      *§audit-stardrop*
- [x] **B2-T10** — Re-vérifier par Nexus les mods que smapi.io n'a pas pu juger. La
      détection des mises à jour est intégralement déléguée à smapi.io ; quand celui-ci
      répond une erreur (`Blocker` : page introuvable, aucune version exploitable…), le mod
      reste sans verdict de **toute** source. · **M**
      *Preuve levée le 2026-08-27 : Powered Automation (50165) installé en 1.0.0, Nexus
      publie 1.025, smapi.io répond « has no valid versions » — les versions exotiques du
      mod (`1`, `1.01`, `1.02`, `1.025`), créé le 17 août, n'ont jamais été indexées. La
      fenêtre disait « tous à jour » (115 blockers mesurés sur le parc, tacitement
      confondus avec des mods à jour). C'est le 3,5 % de désaccord smapi.io/Nexus mesuré
      à l'intégration.*
      **Livré le 2026-08-27.** `NexusFallbackCheck` (Core, 15 tests) décide qui reprendre ;
      la reprise part en série derrière la vérification manuelle, une page à la fois.
      **La règle prévue ici était fausse, et la mesure l'a montrée.** Reprendre « les mods
      en erreur qui déclarent une `UpdateKeys: Nexus:…` » ramasse exactement ce qu'il faut
      écarter et laisse de côté un tiers de ce qu'il faut prendre. Relevé du jour sur le
      parc — **1 010 `UniqueID`, 122 mods bloqués** :
      - **51 sont repris**, sur 41 pages. La plupart tiennent leur identifiant de leur
        manifeste ; **20** de `metadata.nexusID`, que smapi.io rend *même pour les mods
        qu'elle ne sait pas juger* : ceux-là ne déclarent aucune clé Nexus et la règle
        prévue les aurait tous manqués, **dont Stardew Valley Expanded**, actif, dont la
        clé vaut littéralement `Nexus:???` ;
      - **18 doivent être écartés** : leur clé Nexus a bien été consultée, seule celle de
        CurseForge, GitHub ou ModDrop a échoué (« The CurseForge mod with ID '868705' has
        no valid versions »). La règle prévue les aurait tous repris — 18 requêtes pour
        rejouer un verdict déjà rendu ;
      - **51 n'ont aucun identifiant Nexus** (`Nexus:???`, `Nexus:`, `Nexus:null`) : rien
        à interroger.
      Le critère retenu est donc « smapi.io n'a pas rendu de verdict **Nexus** » : soit le
      mod ne déclare pas de clé Nexus exploitable (Nexus n'a jamais été consulté, et
      `metadata.nexusID` en fournit une), soit c'est cette clé-là qui a échoué.
      **Deux garde-fous que la mesure a rendus nécessaires :**
      - *une page revendiquée par des versions différentes ne juge personne*. `Nexus:50165`
        est déclaré par Powered Automation (1.0.0) **et** par Automate (2.6.1), dont le
        manifeste porte une clé fausse ; `Nexus:38134` par deux mods en 10.0.0 et 7.0.0.
        Sans cette règle, la page proposerait un jour à Automate une mise à jour dont le
        bouton installerait un autre mod. À versions égales il n'y a pas d'ambiguïté : les
        sept composants des *Forgotten Caverns* et les quatre modules de *Starblue UI* sont
        bien la même publication — d'où **51 mods pour 41 pages**, donc 41 requêtes ;
      - *un `-unofficial` n'est pas remplacé par l'officiel de même numéro*. Par la lettre
        du semver « 1.1.3 » l'emporte sur « 1.1.3-unofficial.1-p1xel8ted » ; chez SMAPI
        cette forme désigne un correctif **postérieur**, et la proposer conseillerait une
        régression (`ZeroMeters.SAAT.Mod`, parc réel).
      `isNewer` a été éprouvé sur les formes réelles du lot avant d'écrire la moindre
      requête — c'est justement parce que leurs versions sont exotiques que smapi.io les
      refuse : `1.025` > `1.02` > `1.01`, `1.0` = `1.0.0`, `v1.5` = `1.5.0`. Aucun faux
      positif.
      Sans clé d'API la reprise ne fait rien et ne signale rien ; un 429 l'arrête sur place
      et ce qui a abouti reste acquis ; le journal rend un décompte honnête (pages
      interrogées / trouvées / confirmées à jour / échecs).
      **Vérifié à l'écran le 2026-08-27 à 22:06**, sur son parc entier (1 016 mods, plus
      aucun lot perdu) : 123 invérifiables, **52 mods repris sur 42 pages, 10 mises à jour
      trouvées, 42 confirmés à jour, 0 échec** — quand smapi.io seule n'en trouvait que
      **3**. La reprise rapporte donc plus du triple de ce que la source principale voit.
      *(Les comptes détaillés ci-dessus viennent du relevé d'atelier sur 1 010 `UniqueID` ;
      l'écart de un tient aux six entrées que ma mesure ne voyait pas.)*
      *Stardrop ne résout pas ce problème* — il décode `ModEntry.Errors[]` et **ne le lit
      nulle part**, et son `HasUpdateKeys()`/`HasValidVersion()` retire silencieusement de
      la requête smapi.io tout mod dont une clé est vide ou la version inanalysable. Ses
      tickets #134 (« Some Mods that SMAPI has an update for, Stardrop does not ») et #121
      sont ouverts depuis 2023, et son historique ne porte aucun commit sur le sujet.
- [x] **B2-T9** — Trier la liste des mods par poids. *Livré : chaque ligne porte sa taille
      (teintée au-delà de 100 Mo — 22 dossiers du parc réel, qui portent 87 % des 16,8 Go),
      un tri « Poids » les remonte en tête, et la barre d'outils annonce ce que pèse le
      cadrage courant. **Le filtre par seuil n'a pas été construit, délibérément** : cadrer
      sur « en pause » et trier par poids répond déjà à « qu'est-ce que je peux récupérer »
      — 12,71 Go sur le parc réel, lus directement dans la barre d'outils — et une pastille
      de plus alourdirait une barre qui en porte déjà cinq. Ne pas le rebâtir sans un
      besoin qui ne se satisfasse pas du couple existant.* · **S**
- [x] **B2-T8** — Cesser d'émettre quand le quota est à zéro. `NexusRateLimitGate` replafonne
      son back-off à 15 min (`maxBackoff`) : sur un quota journalier épuisé, l'app retente
      donc une requête tous les quarts d'heure pour rien, jusqu'à la remise à zéro. Depuis
      B2-T6 l'instant exact de remise à zéro est connu — la porte peut s'y aligner au lieu
      de deviner. · **S**
      *Mesuré le 2026-08-25 sur le compte de référence : **20 000/jour et 2 000/heure**,
      dont 19 969 et 1 999 restants. C'est donc la fenêtre **horaire** qui est atteignable,
      pas la journalière — l'app n'appelant plus l'API qu'à la demande, il faudrait
      2 000 fiches de mods ouvertes en une heure. Le correctif garde son sens, son urgence
      non. Au passage : ce compte est **non premium** et annonce pourtant 20 000/jour —
      le plafond ne dit rien du type de compte.*
      ▸ **Livré le 2026-08-28** : `NexusRateLimitGate.note(retryAfter:quota:)` — une fenêtre
      mesurée à zéro **avec** sa remise à zéro arme la porte jusqu'à cette échéance, plafond
      dérogé (c'est lui qui faisait réessayer pour rien) ; sans échéance, ou avec du quota
      restant, le comportement ne change pas. `noteQuota` rend désormais la mesure, et les
      deux sites 429 (`noteRateLimitIfThrottled`, `fetchModInfo`) la passent à la porte.
      6 tests.*
- [x] **B2-T7** — `UpdateCautionMessage` : si un manifest installé expose ce champ
      (extension SMAPI tolérée, absente = pas d'alerte), alerter l'utilisateur **avant**
      d'écraser la version existante (breaking change annoncé par l'auteur). · **S** ·
      *§audit-stardrop*
      *Mesuré le 2026-08-25 : **0 mod sur 863** expose ce champ dans le parc de référence.
      La fonctionnalité ne montrerait rien aujourd'hui ; elle ne vaudra que pour un mod
      installé plus tard qui l'annonce. À garder, pas à prioriser.*
      ▸ **Livré le 2026-08-28 — et la sémantique ci-dessus était inversée.** Le champ n'est
      pas une extension SMAPI (0 résultat dans les sources `Pathoschild/SMAPI`) mais une
      extension **Stardrop**, et il vit dans le manifest de **l'archive** — de la version
      publiée — pas dans celui du mod installé : c'est l'auteur de la *nouvelle* version qui
      annonce la casse. Vérifié dans les sources (`Floogen/Stardrop`, `MainWindow.axaml.cs`
      ≈ l. 2907 : manifests de l'archive filtrés sur `HasModInstalled(UniqueID)`, comparaison
      `OrdinalIgnoreCase`). Livraison : `ModManifest.updateCautionMessage` (lu sans casse,
      blanc → rien), `UpdateCaution.warnings` dans `ZipModInfo.swift` (9 tests, Core), et une
      **bannière orange en tête de la préview d'installation** — bannière, pas dialogue :
      la préview demande déjà confirmation, un second blocage ne ferait que répéter la
      question. La mesure tient : la bannière ne vivra que par un mod à venir.*
      ▸ **Vérifié à l'écran le 2026-08-28** : la bannière s'affiche, et le message de
      l'auteur y paraît **tel qu'il l'a écrit — en anglais, en pratique**. C'est voulu,
      et Stardrop l'affiche brut aussi : c'est un texte de sécurité, le traduire
      automatiquement (l'IA locale saurait) risquerait d'en déformer précisément le
      sens. Seul l'habillage est localisé — titre « À lire avant la mise à jour » ;
      `vm.L` ne peut d'ailleurs pas retomber sur l'anglais, sa chute est la clé brute.
- [x] **B1-T4** — **Réunir les problèmes dans l'onglet qui porte ce nom.** *Livré le
      2026-08-25, à sa demande. Le cadrage « Problèmes » ne connaissait qu'une chose —
      un mod **actif** dont une dépendance requise manque ou dort — quand la pastille
      d'anomalie en couvrait trois. Un mod pouvait donc porter une pastille et manquer
      à l'onglet censé les réunir, alors que le commentaire du code affirmait
      l'inverse. Les deux suivent désormais la même règle ; **mesuré avant de les
      réunir** : sur les versions installées du parc, cela n'ajoute qu'**une erreur et
      cinq avertissements** (9 dossiers seulement ont un historique).
      Deux signaux rejoignent `ModAnomaly` :
      - **le verdict smapi.io** (A2-T2) ;
      - **les mods installés plusieurs fois** — mesuré : **7 identifiants sur 14
        dossiers**, dont **trois avec leurs deux copies actives** (le mod Swim, à plat
        et dans son dossier de téléchargement). SMAPI en charge une et ignore l'autre.
        L'index est bâti **une fois par scan**, dans le parcours qui aplatit déjà les
        identifiants — c'est le seul endroit où l'information existe encore, `states`
        et `byId` en écrasant un sur deux. Les dossiers sont **nommés**, pas comptés :
        « installé 2 fois » ne dit pas lequel supprimer parmi 863.

      **L'état actif gradue, il ne filtre pas.** L'ancienne règle exigeait
      `mod.isEnabled` ; les sept mods signalés du parc étant tous en pause, ils
      n'auraient jamais paru. Un mod cassé activé, ou deux copies actives : erreur.
      Sinon avertissement — listé quand même, un dossier à supprimer restant un
      dossier à supprimer.* · **S**
- [x] **B1-T3** — Pastilles d'anomalie dans la liste des mods. *Livré : une pastille orange
      près du nom réunit les trois signaux — erreurs et avertissements des journaux SMAPI,
      dépendance requise absente ou en pause, manifeste sans identifiant (SMAPI ne chargera
      pas ce mod ; il apparaît bien dans la liste, avec `uniqueId` vide).
      **Les compteurs ne portent que sur la version installée**, comme la fiche du mod :
      mesuré avant d'écrire, un mod du parc totalisait 76 erreurs dont **une seule** sur sa
      version courante, et trois autres n'avaient d'historique que sur une version remplacée
      depuis. La règle de dépendance est celle du cadrage « Problèmes »
      (`vm.hasDependencyIssue`, remontée de la vue au ViewModel), pas une seconde.
      `ModAnomalyReport` (Core, 12 tests) agrège un pack sur son en-tête tout en laissant à
      chaque composant la sienne — contrairement au poids, une erreur s'attribue.
      **Empreinte sur le parc réel : 6 mods sur 863**, dont un seul en erreur.* · **M**

## 5. Roadmap par chantier

### Fiabilité du registre & compatibilité — **Axe A** · à faire


#### A1 — Registre robuste

- [x] **A1-T3** — **Installer une archive sans `manifest.json`** : traduction d'un mod déjà
      installé, ou fichiers greffés dans un mod existant (bagages `ItemBags`…). Aujourd'hui
      l'installateur ne classe une archive que par sa structure (`ZipStructure` :
      `singleMod` / `multiMod` / `flatRoot` / `unrecognized`) et cherche des
      `manifest.json` : les sept archives du jeu d'épreuve tombent donc en
      `invalidStructure`, « aucun mod trouvé ». Il faut reconnaître l'archive par son
      **contenu**, désigner le dossier de destination, et écrire **dans** un mod existant —
      donc sauvegarde préalable obligatoire (`ModInstallBackupManager`) et passage par
      `RecoveredFileWriter.withWriteAccess`, le parc étant en `0555` par endroits.
      · **M/L** · *à instruire avant d'engager*

      **Quatre formes, toutes présentes dans `mods tests/`** — ce dossier est le jeu
      d'épreuve, pas un exemple. ⚠️ Il est **gitignoré** : il vit sur la machine de
      l'auteur et n'est pas dans le dépôt. Les noms d'archives ci-dessous suffisent à le
      reconstituer depuis Nexus :
      1. *Traduction, dossier cible nommé* — `FishingLogbook/i18n/fr.json`,
         `The Queen of Sauce's Cookbook - Recipe Tracker/i18n/fr.json`. La destination est
         dans l'archive : le cas facile.
      2. *Traduction, dossier suffixé* — `MakeGuntherRealFR/*.json` (des dialogues, pas un
         `i18n/`). Le dossier cible est vraisemblablement `MakeGuntherReal` : le « FR »
         appartient au nom de la traduction, pas à celui du mod. **Ne jamais décapiter un
         suffixe sans confirmation** — c'est le genre d'heuristique qui écrase le mauvais
         dossier.
      3. *Greffe, chemin cible nommé* — `ItemBags/assets/Modded Bags/*.json`.
      4. *Greffe, fichiers nus à la racine* — `Sword and Sorcery Bags`, `Utility Bags`,
         `Cloth And Colors Bag` : des `.json` à plat, **rien dans l'archive ne dit où les
         déposer**. La prise est dans le contenu : ces fichiers portent `BagId` / `BagName`
         (et parfois `ModUniqueId`, absent du cas 3 — ne pas s'y fier seul), ce qui les
         range dans `ItemBags/assets/Modded Bags/`.

      **Ce que la tâche doit livrer, au-delà de la copie** : dire quel mod sera modifié
      **avant** d'écrire, refuser proprement quand le mod cible n'est pas installé (et le
      nommer), et laisser une trace récupérable — une greffe est invisible dans le registre,
      qui ne connaît que des dossiers de premier niveau. **Sauvegarder chaque fichier
      écrasé** : sans ça, désinstaller une traduction laisserait le mod sans le `fr.json`
      que son auteur livrait (voir **A3-T3**).

#### A2 — Compatibilité SMAPI via l'API smapi.io

- [x] **A2-T1** — Client de l'API `smapi.io/api/v3.0/mods` : POST `ModSearchData`
      (UniqueID + version installée + update keys + version SMAPI + version du jeu) pour
      chaque mod à version valide. Réponse typée par mod : `SuggestedUpdate`,
      `CompatibilityStatus` (`Ok`/`Broken`/`Abandoned`/`Obsolete`/`Unofficial`/`Workaround`),
      `Unofficial` (URL de mise à jour non officielle), `Main`/`CustomUrl`. DTO portables
      depuis Stardop (`ModSearchEntry`, `ModEntry`, `ModEntryMetadata`).
      **Filtres obligatoires** (validés par le spike) : ne soumettre que les mods
      `HasValidVersion && HasUpdateKeys` (comme Stardop) et **normaliser les `UpdateKeys`**
      (strip espaces : `"Nexus: 20290"` → `"Nexus:20290"`, sinon le mod est invisible). · **M**
      *Livré, constaté à l'audit du 2026-08-25 : la case était restée décochée.
      `SmapiUpdateClient` (réseau seul) + `SmapiUpdateRequest` (candidats, filtres,
      normalisation des clés, version du jeu assainie) + `SmapiUpdateResponse`
      (décodage, classement des erreurs), tous trois testés ; `checkNexusUpdates`
      les branche avec une progression par lot. **Les lots font 150, pas 10** :
      mesuré sûr sur un parc de 960 mods en 7 lots, ce qui périme la prescription
      de throttle d'A2-T4. L'affichage du statut a suivi le même jour (**A2-T2**).*
- [x] **A2-T2** — Afficher le statut, `brokeIn` et le **lien de mise à jour non officielle /
      mod de remplacement** sur la fiche mod et dans la carte de santé. · **M**
      *Livré le 2026-08-25, sous une forme que la mesure a dictée. **Interrogé
      smapi.io avec les 840 mods interrogeables du parc avant d'écrire une ligne** :
      552 sans aucun statut (66 %), 281 `Ok`, 5 `Unofficial`, 2 `Workaround`, et
      aucun `Broken`/`Abandoned`/`Obsolete`. Les sept signalés portent tous un
      `brokeIn` et **aucun `suggestedUpdate`** — invisibles pour la liste des
      mises à jour —, et **les sept étaient déjà en pause** : l'utilisateur les
      avait diagnostiqués seul. D'où la forme retenue, les deux à la fois :
      - **passive** — bandeau sur la fiche du mod, bloc dans la carte de santé.
        Le bloc annonce **les deux chiffres** : montrer les sept sans dire les
        552 inconnus laisserait croire le reste vérifié sain ;
      - **au moment qui décide** — une confirmation avant d'**activer** un mod
        signalé (liste, fiche, arbre de dépendances) et avant d'en **installer**
        un. Jamais avant une mise en pause, qui est le bon geste ; et
        l'application d'un profil n'en déclenche aucune, elle passe par
        `toggleMod`.

      Deux trouvailles ont façonné le code : **`brokeIn` était dans la réponse et
      n'était pas décodé**, et **l'action vit dans `compatibilitySummary`, pas
      dans `unofficial`** — ce dernier n'est rempli que 2 fois sur 7, et son URL
      pointe vers `smapi.io` lui-même. Les liens utiles sont des liens Markdown
      dans la phrase, mêlés à des `<small>` : d'où `ModCompatibility`
      (Core, testé sur les sept phrases réelles) qui les en sort.

      **La réserve sur `compare(_:_:)` est caduque** : depuis le passage à
      smapi.io, ce n'est plus lui qui décide d'une mise à jour — il ne sert plus
      qu'à la consolidation par pack et au tri de la liste. Le classement d'une
      version `-unofficial` avant l'officielle n'a plus d'effet visible.
      ⚠️ *(constat conservé pour mémoire, désamorcé — voir ci-dessus)* **2026-08-01** : `NexusUpdateChecker.compare(_:_:)`
      classe `1.0.0-unofficial.3-auteur` **avant** `1.0.0`, parce que le semver rétrograde
      toute version portant un tag de pré-version. Or la communauté Stardew publie ces
      correctifs **après** la version qu'ils réparent, et ils la remplacent. Conséquence :
      une mise à jour non officielle ne peut pas être présentée comme plus récente.
      Figé par un test (`Tests/VersionCompareTests`) qui documente le comportement actuel.
      La correction appartient à cette tâche, pas au comparateur seul : `compare` sert
      aussi au tri de la liste et à la détection des mises à jour, et la changer sans
      distinguer les deux usages déplacerait le problème.
- [x] **A2-T3** — Fallback sur `Pathoschild/SmapiCompatibilityList` (`mods.jsonc`,
      jointure sur `UniqueID`) quand smapi.io est injoignable, et bandeau signalant la
      fraîcheur de la source effectivement utilisée (live vs cache statique). · **M**
      *Livré le 2026-08-31. `PathoschildCompatibilityList` (Core) : récupère
      `data/mods.jsonc` (URL canonique Pathoschild, sans clé ni quota), strip les
      commentaires JSONC de façon *string-aware* (un `//` dans une URL de résumé
      ne fait plus disparaître la ligne), joint sur `UniqueID` et rend des
      `ModCompatibility` — même type que smapi.io, mêmes verdicts
      (`broken`/`abandoned`/`obsolete`/`workaround`/`unofficial`). Le dump est mis
      en cache disque (Application Support, TTL 6 h, aligné A2-T4) ; un échec
      réseau utilise le cache, même périmé. Le filet ne s'exécute **que** quand
      smapi.io échoue — il n'est pas un crawler parallèle. La carte de santé
      porte un badge « Source : … » qui dit si ce qui s'affiche vient de smapi.io
      (vert), du dump Pathoschild (orange) ou du cache disque (gris), avec la date
      du dump le cas échéant. Verdicts Pathoschild **secondaires** : ils ne
      écrasent jamais un verdict smapi.io déjà présent ; ils ne remplissent que
      les `UniqueID` sans verdict. 13 tests, dont le strip JSONC (commentaires
      ligne/bloc, URL préservée, `\"` non-fermant).*

      ⚠️ *Audit du 2026-09-01 — la première livraison ne couvrait que le pire cas
      (smapi.io HS). Le cas vécu (smapi.io répond **partiellement** : 478/1080
      sur le parc mesuré) n'était pas armé, et le cache `pathoschild_mods.jsonc`
      n'était jamais posé sur un parc où smapi.io ne plante pas. Conséquence :
      tous les mods que smapi.io omet **silencieusement** (entrée rendue avec
      `metadata: nil, errors: []`) restaient sans verdict — donc sans reprise
      Nexus, donc invisibles à Mod Updates. Cas vécu : UltraSmooth / 50971, et
      ~515 mods du parc.*

      *Élargi le 2026-09-01. (1) `PathoschildCompatibilityList.Entry` expose le
      champ `nexus` du JSONC (était ignoré) ; (2) `PathoschildNexusIndex` (Core)
      construit un index `UniqueID → nexusID` offline depuis le cache disque ;
      (3) `checkNexusUpdates` déclenche `PathoschildCompatibilityList.fetch`
      systématiquement, synchronisé avec smapi.io par un `DispatchGroup` (le
      cache est posé avant `applySmapiResults` ne le lise) ; (4)
      `applySmapiResults` pousse un `Blocked` pour tout mod envoyé mais sans
      réponse smapi.io — `metadataNexusId` vient de l'override manuel (champ
      « Nexus Mod ID » de la fiche détail) en priorité, du dump Pathoschild en
      repli. Le préfixe `nexus:` ajouté au `errors` du `Blocked` fait passer
      `NexusFallbackCheck.needsNexusVerdict` (le filtre historique cherchait
      déjà « nexus » pour les erreurs Nexus, le nouveau cas l'écrit dans le
      même vocabulaire). Mesure sur le parc : 26 → 515 mods repris, 2 → 15 MAJ
      détectées par vérification. 3 tests ajoutés dans `NexusFallbackCheckTests`
      (mod absent résolu par Pathoschild, mod absent avec override manuel, mod
      absent sans identifiant Nexus — sanity check), 5 dans une nouvelle suite
      `PathoschildNexusIndexTests` (cache absent, mod connu, identifiant CSV,
      identifiant non positif, décodeur `nexus`). Le verdict Pathoschild
      reste **secondaire** quand il passe (règle A2-T3 inchangée) ; la
      nouveauté est qu'il passe **aussi** quand le verdict smapi.io est
      simplement absent — pas seulement quand il contredit.*
- [x] **A2-T4** — **Cache persistant + update check incrémental** (découlant du spike) :
      persister la dernière réponse par mod (équivalent `Versions.json`), avec un **vrai
      TTL 6–24 h** (Stardop appelle à chaque boot = son bug — le rate-limit l'interdit ici) ;
      interroger par **petits lots (~10) avec throttle** (5–8 s), jamais toute la modlist
      d'un coup ; servir l'affichage boot depuis le cache, rafraîchir en arrière-plan. · **M** ·
      *risque : sans cette tâche, A2 casse la modlist au boot — à poser en même temps que T1.*
      ⚠️ *Audit du 2026-08-25 — **la moitié est livrée et l'autre moitié a changé de
      sens.** Livré : l'affichage au lancement est servi par le cache
      (`cachedUpdates`), et A2-T1 n'a pas cassé la modlist au boot. Périmé : les
      « petits lots (~10) avec throttle 5–8 s » — le code envoie des lots de **150**,
      mesurés sûrs sur 960 mods, et la crainte du spike ne s'est pas vérifiée.
      **Reste vraiment à faire** : le TTL. `checkNexusUpdates()` part à chaque
      lancement et réinterroge le parc entier, sans se demander si la réponse
      précédente vaut encore.*
      *Livré le 2026-08-31. Le « reste vraiment à faire » de l'audit — le TTL — est
      fermé : `UpdateCheckPolicy` (Core, pur) décide si le passage automatique part
      (jamais effectué, ou dernier succès ≥ TTL) ; l'horloge `nexusUpdatesLastCheckedAt`
      (UserDefaults) n'est remontée que par un passage **ayant répondu** — un échec
      n'écrit rien, le lancement suivant réessaie. TTL retenu : **12 h** (dans la
      fourchette 6–24 h du cadrage) ; un passage encore frais sert le cache tel quel.
      La garde ne porte que le passage automatique du lancement — le bouton
      « Vérifier » de la page Mises à jour passe toujours outre. 3 tests : jamais
      vérifié / frais / périmé, frontière exacte posée sur le TTL.*

- [x] **A2-T6** — **Pages Nexus supprimées ou momentanément indisponibles, dites
      à l'écran.** ✅ *(livré le 2026-09-14 — `bd8ef8ab`, `4878b34f`, `1f26df02`,
      `500c86aa`)*. Cas fondateur : mod
      [32260](https://www.nexusmods.com/stardewvalley/mods/32260) — caché le
      23 juin 2026 par son auteur, installé sur le parc en deux packs partageant
      l'id (`Azathii.ForgottenWoods`, `Azathii.ForgottenWoods.FTM`), en 1.5.0.
      **Mesures à ne pas refaire** :
      • smapi.io rend la **même** erreur « Found no Nexus mod with this ID. »
      pour une page cachée, une page supprimée et un identifiant jamais existé
      (trois sondes réelles). L'erreur était déjà parsée en `.sourceNotFound`
      (`SmapiUpdateResponse.blocker`, fragment « found no ») et déjà affichée au
      volet « invérifiables » ; c'est une **erreur dans une entrée présente**,
      jamais une absence — le piège 429/503 des passes partielles ne s'applique
      pas à ce verdict ;
      • page cachée côté web = HTTP 200, `og:title = "Mod unavailable"`, bandeau
      « Hidden mod » avec date, auteur et raison libre. ⚠️ **Le cache des
      lecteurs web ment sur l'état** : sans `no-cache`, 32260 a montré trois mois
      sa page d'avant le masquage — toute sonde d'état passe en `no_cache` ;
      • **l'API v1 départage** : pour 32260 *caché*, v1 répond **200 — version
      1.5.0** (jamais publique). La reprise a donc *réglé* le cas fondateur en
      « à jour (1.5.0 = 1.5.0) », la copie du parc venant de cette release
      retirée.
      **Livré** : la reprise nomme désormais les statuts au journal
      (`http_<code>`) et marque l'état par mod — `NexusPageState` (`.removed`
      pour un 404, tous les mods de la page ; `.unavailable` pour un 200 après
      « found no », seuls les porteurs, même règle du premier-erreur que les
      invérifiables), projection **remplacée** à chaque reprise — une page
      redevenue visible doit voir son état mourir, pas fusionner — et élaguée
      au parc installé, persistée côté `ModUpdateStore` (**F1-T2 respecté en
      cours de route : le cliquet a refusé l'état neuf dans le ViewModel**).
      Écran : badge capsule à côté du nom en ligne (popover au clic), badge sur
      la carte de grille, bandeau rouge/orange sur la fiche, et `hasIssues`
      intègre l'état — le filtre « Problèmes » les ramène. Reste ouvert, **au
      contact** : une `[MAJ]` suggérée sur une page cachée serait
      intéléchargeable ; un vrai 404 n'a pas encore été observé sur le parc —
      le journal le nommera quand il viendra.

#### A3 — Métadonnées Nexus

- [x] **A3-T5** — **Ce qui est posé se voit, se suit et ne se propose plus.** *Livré le
      2026-08-26, à sa demande, après que la recherche a été éprouvée.
      Quatre demandes, une même racine : le registre ne retenait que les traductions,
      et rien de ce qui était en place n'était distingué de ce qui restait à trouver.
      - **Le registre porte les greffes**, plusieurs par mod — la traduction reste
        unique. L'ancien format se relit (test dédié) : un échec de décodage aurait
        fait perdre le seul moyen de retirer les traductions déjà posées.
      - **Deux formes d'« installé »**, mesurées : un supplément peut être un mod à
        part entière (2 des 10 de Cornucopia, 1 des 12 de Ridgeside) ou une greffe
        sans manifeste. La première se reconnaît à son identifiant Nexus, la seconde
        au registre.
      - **Le rattachement Nexus n'est pas manuel.** Sur un compte gratuit tout
        s'installe à la main, donc sans identifiant — et sans identifiant aucune mise
        à jour ne peut être vue : le suivi livré en A3-T3 ne pouvait **jamais** se
        déclencher. Le nom du fichier téléchargé porte l'identifiant dans **14 cas sur
        15**, et le titre le confirme ; deux signaux indépendants qui concordent, ou
        rien. Quatre tests encadrent l'abstention.
      - **La date retenue est celle du dépôt**, jamais celle du résultat : la seconde
        déclarerait la ligne à jour par construction.
      ⚠️ *Relecture : huit défauts, dont **deux régressions** — la moitié « déjà
      installé » de la partition était jetée, et elle porte à la fois le résultat qui
      annonce la mise à jour et celui vers lequel rattacher. La pastille de mise à
      jour, qui fonctionnait, ne pouvait plus s'afficher.* · **M**
- [x] **A3-T1** — Recherche automatique des `NexusID` manquants (correspondance nom +
      auteur, proposition validée par l'utilisateur, jamais d'écriture aveugle). · **M** ·
      risque : quota d'API Nexus, faux positifs. *La recherche par nom qu'elle suppose
      n'existe pas en API v1 : elle dépend d'**A3-T2** (GraphQL v2), vérifié le 2026-08-25.*

      **Première moitié livrée le 2026-08-26 — et elle ne cherche rien.** Mesuré avant
      d'écrire : **148 mods du parc n'ont aucune clé Nexus dans leur manifeste**, et
      **30 d'entre eux sont identifiés par smapi.io**, dont la réponse porte déjà
      `metadata.nexusID`. L'app le recevait à chaque vérification et le jetait — sauf
      sur les lignes de mise à jour, où il ne sert qu'au bouton de téléchargement.
      La source est fiable là où elle répond : **dix de ces trente avaient été saisis
      à la main par l'utilisateur, et les dix concordent exactement**. Restaient
      **20 identifiants gratuits perdus**, désormais retenus (`NexusIdLearning`, Core,
      11 tests). La règle d'écriture n'est pas dupliquée : c'est celle de
      `NexusInstallIdRecording` — le manifeste fait foi, une saisie manuelle ne se fait
      jamais écraser, rien n'est réécrit à l'identique.

      **Ce qui reste — et c'est là qu'est le risque.** 118 mods restent inconnus de
      smapi.io, dont **35 déjà renseignés à la main** : la recherche floue vise donc
      **83 mods**, pas 148. Deux mesures pour la cadrer : le quota n'est pas le
      problème (20 000/jour, 2 000/heure — cf. B2-T8), les faux positifs le sont. Le
      seul signal disponible est le nom, et il est traître sur ce parc : **148
      manifestes sur 995 portent un préfixe `[CP]`** qui n'appartient pas au titre
      Nexus. Une ligne qui suit le mauvais mod est pire qu'une ligne qui ne suit rien
      — d'où la validation par l'utilisateur, jamais d'écriture aveugle.

      **Seconde moitié livrée le 2026-08-26 — mesurée avant d'être écrite.** La
      requête GraphQL v2 a été réellement exécutée sur les 83 mods : **55 ne rendent
      rien** (mod retiré, renommé, jamais publié — dont **20 composants de pack**
      dont le nom n'a jamais été un titre Nexus), **23 rendent des candidats dont
      61 % sont des traductions** (45 sur 74 : le titre d'une traduction commence
      par celui du mod, la comparaison par préfixe les attrape toutes). Trois règles
      en sortent, dans `NexusModSearch.identityCandidates` (Core, 10 tests) :

      - le tag `Translation` écarte toutes les traductions — seul moyen, et il les
        écarte toutes : **18 mods n'ont plus qu'un candidat** (contre 14 sans le
        filtre) et les cinq listes restantes deviennent lisibles ;
      - **l'auteur confirme, il ne trie pas** : sur ces 18, le pseudo Nexus
        concorde 12 fois, parfois à une variante près (`skeleton` / `Skeleton0w0`),
        et parfois pas alors que c'est le même mod (`Owljoy` / `OwlandJoy`) — en
        faire un filtre perdrait des candidats justes, il n'ordonne que l'affichage
        (préfixe, plancher quatre caractères, multi-auteurs essayés un à un) ;
      - **rien n'est écrit d'autorité** : la fiche du mod propose, l'utilisateur
        désigne (« C'est celui-ci »), et l'adoption passe par le même chemin qu'une
        saisie manuelle (`setCustomNexusModId`) — deux des 18 candidats uniques
        mesurés portaient un auteur sans rapport.

      « Aucun résultat » reste la réponse la plus fréquente — deux mods sur trois —
      et elle est écrite en toutes lettres, sans quoi le bouton passerait pour
      cassé ; le composant d'un pack est orienté vers la fiche du pack, qui est là
      où son nom a une chance d'exister.
- [x] **A3-T2** — **Client de recherche Nexus (GraphQL v2)** — le socle qui manquait à tout
      l'axe A3. *Faisabilité vérifiée le 2026-08-25, sur le compte réel* : l'API **v1 n'a
      aucune recherche texte** (`/mods/search.json` → **422**) et `latest_updated.json` ne
      rend que **10 entrées** couvrant une heure — inexploitable pour un balayage. En
      revanche `POST https://api.nexusmods.com/v2/graphql` répond, s'introspecte et cherche
      par nom. Requête qui marche :
      `mods(filter:{ name:{value:"…",op:WILDCARD}, gameId:{value:"1303",op:EQUALS} }){ totalCount nodes{ modId name uploader{name} modCategory{name} } }`.
      · **M** · *non documentée officiellement : la traiter comme une dépendance qui peut
      casser, et prévoir la dégradation propre.*

      **Quatre pièges relevés à la mesure, tous coûteux à redécouvrir :**
      1. **`gameId` numérique obligatoire** (1303 pour Stardew, lu sur
         `/v1/games/stardewvalley.json`) — `gameDomainName` seul rend `totalCount: 0` sans
         erreur, et filtrer par `modId` sans `gameId` échoue explicitement.
      2. **L'index ne connaît pas les accents.** « Français » → **0 résultat**, « Francais »
         → **184**. Toute requête doit être dépliée en variantes non accentuées.
      3. **`op: WILDCARD` est la seule opération de nom** ; `MATCHES` est refusé par le
         schéma.
      4. Le champ `first` n'est **pas** accepté sur `mods` : c'est `count` / `offset`, et le
         tri passe par `sort:{updatedAt:{direction:DESC}}`.

      *Livré (`NexusModSearch`, Core, 27 tests + `NexusSearchClient`). Deux ajouts que la
      mesure a imposés : **GraphQL rend 200 avec un tableau `errors`** — le prendre pour un
      résultat vide changerait une panne de schéma en « rien trouvé » —, et **l'API v2 ne
      renvoie aucun en-tête `x-rl-*`**, donc l'affichage de quota (B2-T6) ne dit rien des
      recherches.*
- [x] **A3-T3** — **Trouver les traductions françaises des mods installés**, la plus récente
      pour chacun, et proposer l'installation (qui relève d'**A1-T3** : ces archives n'ont
      pas de manifeste). · **M** · *dépend d'A3-T2*
      - Volumes mesurés sur Stardew : « Francais » **184** mods, « French » **68**,
        « Traduction » **51** — « FR » en rend **1 559** et n'est donc pas un mot-clé mais
        du bruit. La recherche part du **nom du mod installé**, pas du mot-clé de langue :
        c'est ce qui distingue « la traduction de *ce* mod » de « les traductions ».
      - Le rapprochement est le vrai risque, pas la requête : un nom de traduction ressemble
        au nom du mod sans lui être égal (« Parchment - Fishing Log - Francais » pour le mod
        « Parchment »). **Proposition validée par l'utilisateur, jamais d'installation
        aveugle** — même règle qu'A3-T1.
      - Croiser avec ce que l'app sait déjà : un mod dont `i18n/fr.json` est présent et à
        jour n'a rien à chercher (voir la couverture FR, **C1-T1**).
      - **Suivre les mises à jour, et pouvoir désinstaller.** Une traduction installée doit
        être retenue — quel mod elle traduit, quel `modId` Nexus, quelle version, quels
        fichiers elle a déposés — sinon ni l'une ni l'autre n'est possible : une traduction
        est invisible du registre des mods, qui ne connaît que des dossiers de premier
        niveau. D'où `InstalledTranslationRegistry`. Deux conséquences qui ne vont pas de
        soi :
        1. *Suivre* = comparer la date Nexus de la version installée à la plus récente
           trouvée, **pas** les numéros de version : les traducteurs ne les incrémentent pas
           tous, et beaucoup reprennent celui du mod d'origine.
        2. *Supprimer* = retirer les fichiers déposés **et rendre ce qu'ils ont écrasé**.
           Un mod livré avec son propre `i18n/fr.json`, recouvert par une traduction
           communautaire, se retrouverait sans français du tout si la désinstallation se
           contentait d'effacer. La sauvegarde de l'écrasé est donc une obligation de
           l'installation (**A1-T3**), pas une option.
      - *Livré : section « Traduction française » sur la fiche du mod — chercher, installer,
        voir qu'une version plus récente existe, retirer. **Le tri se fait sur le tag Nexus
        `French`, pas sur la catégorie** : Stardew n'a aucune catégorie « Traduction » et ses
        traductions se répartissent sur treize catégories, quand 77 traductions sur 80
        portent le tag. Le titre ne sert que de filet pour les trois autres.
        `InstalledTranslationRegistry` + `InstalledTranslationStore` retiennent ce qui est
        posé ; sans eux, ni suivi ni retrait. Réserve : le téléchargement intégré demande un
        compte **Nexus Premium** — sur un compte gratuit, `/download_link.json` rend un 403,
        et c'est le bouton « Nexus » (onglet `?tab=files`) qui prend le relais.*
- [x] **A3-T4** — **Trouver les suppléments d'un mod installé** : greffes d'assets et
      modificateurs (bagages `ItemBags`, packs de recettes…). Même socle qu'A3-T3, autre
      requête — le nom du mod installé apparaît dans le **titre du supplément**
      (« ItemBags for All Cornucopia », « Sword and Sorcery Bags »). Six mods portent
      « ItemBags » dans leur nom sur Stardew ; le gisement est ailleurs, dans les titres qui
      citent le mod cible sans nommer l'hôte. · **M** · *dépend d'A3-T2 ; installation par
      **A1-T3**, désormais livrée : déposer un supplément à la main fonctionne, et l'app
      demande le mod cible quand elle ne sait pas. **Ne reste que la découverte** — chercher
      les suppléments d'un mod installé sans quitter l'app.*
      ⚠️ *Étendre `DroppedContentRecognizer` à d'autres hôtes qu'ItemBags a été **cherché et
      écarté** le 2026-08-25 : sur le parc, les quatre candidats sont soit des content packs
      avec manifeste, soit des dossiers attendus (thèmes BetterCrafting), soit des patchs
      Content Patcher dont la seule signature serait `Changes` — la clé de tout
      `content.json`, qui enverrait n'importe quel pack au mauvais endroit. A1-T3 rend la
      table inutile : une archive inconnue demande son hôte au lieu d'être devinée.*

      *Livré le 2026-08-26. Section « Suppléments et correctifs » sur la fiche du mod :
      chercher, lire, ouvrir la page Nexus. **Aucun bouton d'installation** — le dépôt
      d'une archive sans manifeste (A1-T3) s'en charge, et un compte gratuit ne peut de
      toute façon pas télécharger par l'API.
      **Ce que la section dit d'elle-même, parce que la mesure l'impose** : Nexus n'a
      aucune notion de « supplément ». La recherche répond à la seule question
      possible — quels mods citent celui-ci dans leur titre — et une phrase le dit à
      l'écran plutôt que de laisser croire à une certitude. Deux garde-fous mesurés :
      - les traductions sont écartées par leur **tag** `Translation`, seul signal qui
        les sépare (8 des 26 premiers résultats sur « Sword and Sorcery ») ;
      - la liste est plafonnée **et le total annoncé** : « Wildflour's Atelier Goods »
        rend 3 candidats sur 12, « Content Patcher » en compte **428**. Une poignée
        affichée sans ce chiffre passerait pour la réponse entière.
      Le mod hôte est écarté par son identifiant Nexus **et par son titre** : 111 mods
      du parc n'en déclarent aucun, et sans ce second filet le mod figurait en tête de
      ses propres suppléments — défaut vu en simulant la recherche sur le parc réel
      avant toute exécution de l'app.
      `NexusModSearch.decode` rend désormais une **page** (résultats + `totalCount`) :
      le total était demandé à l'API depuis le début et jeté au décodage.*

      ✅ **Cinquième forme ajoutée le 2026-08-26**, sur un cas qu'il a rencontré :
      `bagconfig.json` seul dans son archive (Nexus 48157, un remplacement de
      configuration pour `ItemBags`). Ni la structure ni les clés JSON ne le situaient.
      La règle est le **nom du fichier confronté à ce que les mods portent à leur
      racine**, et elle ne tient que par l'unicité — mesuré : 76 des 91 noms de
      fichiers JSON de premier niveau n'ont qu'un propriétaire, mais `config.json`
      en a 544 et `content.json` 522. Un seul propriétaire donne un plan, plusieurs
      font demander, `manifest.json` ne compte jamais.

      ✅ **Faisabilité mesurée sur l'API réelle le 2026-08-25.** Deux inconnues levées :
      1. *Trouver* — `op: WILDCARD` est bien une recherche **par sous-chaîne**, pas par
         préfixe : chercher « Wildflour » rend « Item Bags for Wildflour's Atelier Goods »,
         chercher « Cornucopia » rend « Whipped Cream for Cornucopia Artisan Machines ».
         Le nom du mod installé suffit donc comme requête, sans traitement.
      2. *Trier* — **c'est là qu'est le travail, pas dans la recherche.** Les résultats sont
         noyés de traductions : sur « Sword and Sorcery », les 8 premiers sur 26 sont des
         traductions (JP, CN, HU, PT-BR, ID, RU…). Le champ `tags { name }` **existe sur
         chaque nœud** et tranche net : sur douze résultats « Wildflour », les six
         traductions portent toutes le tag `Translation`, et les deux vrais suppléments
         (« Item Bags for… », « Domed Pots compatibility for… ») n'en portent aucun.
         La règle est donc : chercher par le nom du mod, **écarter le tag `Translation`**,
         écarter le mod hôte lui-même par son `modId`. Reste à porter `tags` dans
         `NexusModSearch.Hit`, qui ne le lit pas encore.*
- [x] **A3-T6** — **Déclarer une traduction que l'app n'a pas posée.** L'app sait
      rattacher une ligne **déjà au registre** — menu « Rattacher à Nexus », plus le
      rattachement muet d'**A3-T5** quand une recherche a tourné. Ce qui manque, c'est
      tout ce qui a été posé **hors de l'app** : ces traductions-là n'ont aucune ligne,
      donc rien à rattacher.

      **Mesuré sur le parc le 2026-08-29.** 488 mods portent un `i18n/fr.json` ; **313**
      l'ont vu naître sur cette machine plus de 24 h après le mod lui-même, et **310 de
      ces 313 étaient inconnues du registre** — qui n'en comptait que 7 lignes, dont 4
      greffes. Deux signaux indépendants concordent (`mtime` côté auteur en donne 357,
      `birthtime` local 313) et le seul cas connu-vrai, `UIInfoSuite2Alt`, tombe bien
      dans le lot. L'éditeur du hub ne gonfle pas le chiffre : il n'a touché que **3**
      mods. Ce qu'elles coûtent : ni provenance, ni retrait, ni suivi de version — et
      **129 des 313 échappent même à la couverture** du hub, faute d'`UniqueID`
      lisible ; 14 des 184 suivies sont incomplètes (`[CP] Mineral Town` 3968/4369).

      Le geste : sur la fiche, une ligne « traduction présente, origine inconnue », et
      un bouton pour la déclarer — recherche Nexus, ou saisie de l'identifiant. **Rien
      ne s'inscrit d'office** : `birthtime` ment sur un dossier copié ou restauré, et
      une provenance devinée dans un registre qui sert justement à ne pas deviner vaut
      moins que pas de provenance du tout. · **M**
      *Livré le 2026-08-31. Nouveau type `DeclaredTranslation` (Core) — strict
      nécessaire à l'identité et au suivi (modId, nom, version, dates), **pas** de
      liste de fichiers déposés ni de fichiers recouverts : on ne sait pas ce que
      l'utilisateur a posé, et prétendre le savoir pour défaire quelque chose qu'on
      n'a pas écrit serait le défaut exact qu'on vient de citer. Champ
      `declaredTranslations: [String: DeclaredTranslation]` ajouté à
      `InstalledTranslationRegistry` avec **décodage rétro-compatible** : les
      registres écrits avant A3-T6 (sans le champ) restent lisibles. Une
      déclaration coexiste avec une installation existante, et `undeclare` ne
      touche pas le disque. UI : bannière « traduction présente, origine inconnue »
      sur la fiche quand `i18n/fr.json` est sur disque **et** qu'aucune ligne
      (installée ni déclarée) n'existe, avec deux sorties : recherche Nexus ou
      déclaration manuelle (sheet). 6 tests sur le registre, dont le back-compat
      et la coexistence install + déclaration.*
      *Réserve : 310 gestes. C'est pourquoi les deux chemins automatiques comptent —
      la lecture du nom de fichier au dépôt (`NexusArchiveName`, livrée le 2026-08-29,
      9 noms lus sur 13 étiquetés) couvre les poses futures, `confirmedNexusId` couvre
      celles pour lesquelles une recherche a tourné. A3-T6 est le filet du reste.*

#### A5 — Incompatibilités entre mods

- [x] **A5-T1** ✅ *(livré le 2026-08-29)* — **Lire les conflits que Content Patcher journalise.** Il écrit la
      phrase exacte quand deux packs se disputent un asset exclusif ; `SmapiLogParser`
      lit déjà le journal. Zéro faux positif — c'est Content Patcher qui a raison, pas
      une déduction — et ça couvre tous les conflits, pas seulement les `Load`.
      Limite à dire à l'écran : **ça constate, ça ne prévient pas** ; il faut avoir
      joué avec les deux mods actifs. · **S**
- [x] **A5-T2** ✅ *(livré le 2026-08-30, vérifié à l'écran)* — **Signaler soi-même une incompatibilité, ou en écarter une.** La
      prévention que le journal ne donne pas. Magasin de verdicts sur des paires **non
      ordonnées**, clé `folderName` logique (111 mods du parc n'ont pas d'`UniqueID`,
      et le nom logique survit à la mise en pause), chaque verdict portant
      `déclarée` ou `écartée`, une note et une date. Persisté comme le registre des
      traductions. Alimente le rapport **et** l'avertissement à l'activation, greffé
      sur `vm.activationWarning(for:)` — le crochet qui existe déjà pour les mods que
      smapi.io signale cassés. Un verdict orphelin (mod désinstallé) se dit, ne se
      jette pas. · **M**
- [x] **A5-T3** ✅ *(livré le 2026-08-29, vérifié à l'écran)* — **Le paragraphe de compatibilité de l'auteur, sur la fiche.** 15 %
      des mods en écrivent un ; l'app cache déjà les descriptions et sait rendre le
      BBCode. **Aucune extraction de paires** : on remonte la phrase, l'utilisateur
      juge. C'est le seul usage honnête d'un signal à 20 % de précision, et il capte
      aussi les mentions « catégorie » qu'une extraction jetterait. · **S**

## 5. Roadmap par chantier

### Découverte de nouveaux mods — **Axe G** · livré en **v1.25.0**

- [x] **G-T1** — Spike de validation API : mods triés (endossements, mise à
      jour, création), filtre par tag `French`, champ endossements, requête de
      fiche. Introspection du schéma d'abord ; si elle est désactivée, sondage
      à la main comme le 2026-08-25. Passe par l'utilisateur — la clé du
      Trousseau est inaccessible aux agents. Repli si tri/filtre infaisable :
      v1 = recherche + croisement parc, tendances reportées. · **S**
- [x] **G-T2** — Onglet « Découvrir » : trois sections (une requête chacune,
      cache 24 h, rafraîchissement manuel seul), recherche par nom en vitrine,
      badge « installé » + filtre « masquer installés » **avec compte affiché**
      (sur 966 mods installés, les tendances seront largement filtrées — le
      filtre ne doit pas masquer qu'il a filtré), fiche éclair + « Ouvrir sur
      Nexus » (`nxm://` existant ramène le fichier dans l'app). · **M**
- [x] **G-T3** — Install direct depuis la fiche : pipeline des mises à jour
      appliqué à un mod non installé. API réservée **Premium** — 403 mesuré
      sur compte gratuit (**A3-T3**) ; site + `nxm://` reste la voie gratuite
      en toutes versions. · **M**

## 5. Roadmap par chantier

### Cohérence UI : un seul langage pour toute l'app — **Axe H** · à faire

- [x] **H-T1** — **Châssis** : tokens manquants (`Grid`, `Metrics`, `Shadow`,
      `Icon`), extraction vers `Views/Components/` des 6 composants de
      `DiscoverView` (`ModCard`, `StateCard`, `ErrorBanner`, `StatStrip`,
      `HeroHeader`, `SectionHeader`) et de `CategoryBadge` — défini dans
      `ModListView.swift`, déjà consommé par les deux vues —, Découvrir bascule dessus
      **sans changement visuel** (l'extraction sans bascule créerait des copies
      divergentes), bibliothèque `/design` créée (Foundations + Components),
      `UX_UI_Specifications.md` retiré avec bandeau de renvoi. · **M**
- [x] **H-T2** — **Navigation** : un seul style d'item de sidebar, badge
      capsule sur l'item (motif Mail) — fin de la zone de statut séparée ;
      4 groupes : Bibliothèque / Parties / Santé & secours / Application.
      Aucune destination supprimée ni enterrée, identifiants d'onglet
      inchangés (pas de migration d'état). · **S**
- [x] **H-T3** — **Accueil tableau de bord** : bande des 4 compteurs
      cliquables (mises à jour, alertes SMAPI, quarantaine, parc — un zéro
      affiché est une information), carte de lancement (mode + profil + dossier
      suivis d'un coup d'œil), parc et socle en version constat ; identité et
      réglages déménagent (version, crédits, dossier, SMAPI détaillé →
      Réglages ; « Installer SMAPI » reste sur l'accueil quand SMAPI manque). · **M**
- [x] **H-T4** — **Mods, pilote du reskin** : toolbar unifiée au motif
      Découvrir (un seul geste par intention), rangée à hauteur réservée avec
      état codé glyph + couleur + barre d'accent (jamais la couleur seule),
      grille optionnelle réutilisant `ModCard` via un adaptateur de valeurs
      (un `ModItem` n'a ni endossements ni catégorie Nexus servis), fiche
      `HeroHeader` + `StatStrip` où l'action praticable est la proéminente. · **L**
- [x] **H-T5** — **Lot Parties** : profils en cartes à chiffres clés (jamais
      un formulaire nu), sauvegardes au même motif. · **M**
      ✅ (livré le 2026-08-31)
- [x] **H-T5b** — **Hero de sauvegarde illustré**. ✅ (livré le 2026-08-31)
- [x] **H-T5d** — **Lecture d'une sauvegarde : la queue au lieu du fichier
      entier.** ✅ (livré le 2026-09-02)
      Mesuré sur les 6 fichiers de save du disque (2 à 39 Mo) : les scalaires de
      niveau `<SaveGame>` — `whichFarm`, `goldenWalnuts`, `whichModFarm` — sont
      écrits **après** les grandes collections et vivent dans le dernier 1,2 %
      du fichier (98,8 % au pire). Les chercher sur le fichier entier coûtait
      ~313 ms chacun.
      `SaveGameFields.trailingScope` restreint la recherche au dernier
      vingtième (plancher 1 Mo, quatre fois la marge du pire cas), avec une
      **ancre** : si la queue ne porte pas `<whichFarm>`, on n'a pas la bonne
      zone et l'appelant repart du fichier entier — le résultat ne peut donc
      pas être pire qu'avant. À l'inverse, une balise absente d'une queue qui
      porte l'ancre est absente de `<SaveGame>`, puisqu'elle en serait la
      voisine.
      La date (`yearForSaveGame`/`seasonForSaveGame`/`dayOfMonthForSaveGame`)
      est un champ du **fermier** — enfant direct de `<player>` sur les 10
      fichiers mesurés : elle sort de la passe unique de `SavePlayerFields` au
      lieu de trois balayages de plus. Ferme au passage la même faute que pour
      le sexe : un monstre de quête imbriqué portait sa propre date.
      **Mesure : 1028 ms → 228 ms** sur la save de 37 Mo ; 1191 → 287 ms sur
      l'ensemble des parties listées (×4,2).
      ⚠️ Ne pas « optimiser » l'ancre par un pré-filtre `range(of:)` : mesuré,
      il est plus lent que la regex (1108 ms contre 353 sur 37 Mo), `.literal`
      aussi (391 ms), et `utf8.firstRange(of:)` est catastrophique (15,7 s).
      **Mémoïsation livrée avec.** `fetchSaves()` reparsait chaque dossier à
      chaque rafraîchissement, dossiers de secours compris ; la lecture est
      désormais mémorisée par chemin. L'empreinte croise **date et taille** —
      la date seule ne suffit pas (`restoreBackup` recopie avec `copyItem`,
      qui la préserve), la taille seule non plus (500 → 600). Le trou restant
      est fermé par une invalidation explicite en tête de chaque chemin
      d'écriture ; un test le prouve (sans elle, restaurer une sauvegarde
      laissait la fiche sur le contenu d'avant).
      ⚠️ Cache et invalidation sont **globaux** : correct en production, mais
      la suite de tests qui les exerce doit être `.serialized`, sinon un test
      qui invalide efface l'entrée qu'un autre vient de poser.
      ⚠️ Ne pas comparer deux `Date` qui ont fait un aller-retour par
      `setAttributes` : elles s'impriment identiques, leur écart mesure 0,0 et
      `==` est pourtant faux. Le code de production compare deux lectures de
      la même source, où l'égalité stricte est correcte.
- [x] **H-T6** — **Lot Santé & secours** : alertes système, quarantaine,
      backups ×2 — gravité toujours glyph + couleur, rapports en tableaux
      lisibles. · **M**
      ✅ (livré le 2026-09-02)


---

## Avertissement de lecture d'origine et table de réconciliation (2026-07-30)

Les deux blocs ci-dessous ouvraient la roadmap jusqu'au 2026-09-04. Ils décrivent
l'état du projet en **v1.10.0** — le §1 annonce une v1.10.1 à couper et parle de
correctifs « en attente de release », la table appariait la liste de souhaits de
l'auteur aux tâches d'alors. **Plusieurs de ses états sont faux aujourd'hui** :
les configurations par profil y sont « à faire » alors que B3-T5 est livré, le
ViewModel y fait 8 389 lignes contre ~9 470 depuis. À lire comme la photographie
datée qu'ils sont, jamais comme un état courant.

## 1. Avertissement de lecture

Le document de veille propose une roadmap `v0.2 → v0.4` et décrit StarHubFR à partir du
README et de suppositions (« état probable », « sans accès au code »). Deux conséquences :

1. **Le versionnage du document est caduc.** Le projet est à **v1.10.0**, avec 22 releases.
   La présente roadmap repart de **v1.11.0**.
2. **Son « Axe 1 — Santé & registre des mods », présenté comme le chantier prioritaire,
   est largement livré** (v1.9.x–v1.10.0 : parseur de diagnostics SMAPI, carte de santé,
   repliement du bruit, groupement par mod, historique d'erreurs par version de mod).

**Poids respectif des sources** :

| Partie | Fiabilité | Usage ici |
| :-- | :-- | :-- |
| Liste de souhaits de l'auteur (2026-07-30) | **Autorité** | Définit le périmètre |
| §« Grandes familles de fonctionnalités » du doc de veille | Haute (c'est la même liste, reformulée) | Périmètre |
| Reste du doc de veille (comparaisons Stardrop/SVMM, « fonctionnalités actuelles ») | Moyenne — devine souvent faux sur le dépôt | Inspirations, risques, positionnement |

> ⚠️ **Deux demandes de la liste sont pleinement livrées** (backups `config.json`/`fr.json`,
> et le socle de reconnaissance des mods de traduction). La liste **précède v1.7** : leur
> réapparition n'est donc **pas** le signe d'une régression, mais d'une liste non tenue à
> jour. **Deux exceptions**, vérifiées et confirmées comme encore ouvertes :
>
> - **les dates affichées** — le champ `updated_timestamp` existe côté code, mais champ
>   présent ≠ affichage juste, et l'anomalie est re-signalée → **B2-T5** ;
> - **le RAR** — livré sur le glisser-déposer (v1.7.1) mais **absent du chemin de mise à
>   jour**, qui forçait l'extension `.zip` sur tout téléchargement → **corrigé en séance**
>   (**X5**).
>
> ✅ S'y est ajouté un **défaut bloquant découvert en séance** : les archives empaquetées
> sous Windows (antislashs) étaient refusées alors que leur extraction réussissait —
> **corrigé** (**X4**), avec les libellés du parcours d'installation (**X6**). Ces trois
> correctifs attendent une **v1.10.1**.

La conclusion de fond du doc de veille reste juste, mais pour des raisons différentes de
celles qu'il avance : **l'axe diagnostic étant livré, l'outillage de traduction FR est le
seul chantier structurant encore entièrement intact** — et le seul qui justifie StarHubFR
comme produit distinct de StarHubTH et de Stardrop.

---


## 3. Table de réconciliation

Marquage : **Fait** = preuve dans le code ou le CHANGELOG. **Partiel** = socle présent,
promesse non tenue. **À faire** = rien dans le code. Les lignes **§new** viennent de la
liste du 2026-07-30 et n'existaient pas dans le document de veille.
Les lignes **§ajout** sont des demandes formulées **après** cette liste ; leur date est
portée dans la colonne de droite.

| Source | Demande | État | Preuve / renvoi |
| :-- | :-- | :-- | :-- |
| **§new** | Désactivation/activation **dichotomique** pour isoler un mod défectueux | **Fait ✅** | `Models/BisectionSession.swift` (Core, testé) + `BisectionRunner` + `Views/Components/BisectionCard.swift` |
| **§new** | Mutualiser les diagnostics/mesures de perf entre utilisateurs (cf. `circinus.sh`) | **À faire** | Aucun backend → **D2** (décision produit, non chiffrée) |
| **§new** | Refactoriser le God module | **À faire** | `StarHubTHViewModel.swift` = **8389 lignes** (mesuré le 2026-08-28 ; 4278 au relevé initial, +96 %) → **F1** |
| **§new** | Vérifier optimisation (vitesse, mémoire) et sécurité du code | **À faire** | → **F2** |
| **§new** | Copier/coller du NexusID impossible | **Non reproduit** | Fonctionne ; le menu Édition est présent → **X1** clos |
| **§new** | BBCode/Markdown non rendu dans la description | **Corrigé ✅** | 6 défauts reproduits sur SVE (3753) puis corrigés (tokeniseur récursif) ; rendu typé ajouté (titres/listes/code/citations/centrage/couleur/souligné), vérifié sur 51 descriptions → **X2** |
| **§new** | Rafraîchissement automatique dès qu'on renseigne l'identifiant Nexus | **Fait** | Livré le 2026-08-26 → **B2-T3** (saisie manuelle et adoption d'un candidat) |
| **§new** | `smapi.io/json` comme analyseur de référence pour les JSON Stardew | *(précision)* | Affine la définition de « manifest valide » → **A1-T2** |
| **§new** | `stardew-i18n-translator` comme référence de pipeline i18n | *(précision)* | Affine **C3** — voir la réserve de licence en §5 |
| §1 | Refonte du log SMAPI façon *Log Doctor* | **Fait** | `Models/SmapiLogDiagnostics.swift`, `Views/Components/SmapiHealthCard.swift`, v1.9.x–1.10.0 |
| §1 | Optimiser l'affichage des ~2000 lignes | **Fait** | `LazyVStack` + repliement par famille (`Models/LogNoise.swift`), v1.10.0 |
| §1 | Signaler les mods incompatibles (`smapi.io/mods`) | **Fait** | L'API live est branchée (**A2-T1**) et son verdict s'affiche — fiche, carte de santé, et confirmation avant activation ou installation (**A2-T2**) |
| **§ajout** | Signaler les incompatibilités **entre mods** | **Partiel** | Demandé le 2026-08-29. Autre axe que la ligne ci-dessus, qui ne couvre que mod ↔ SMAPI. Mesuré après décompilation de Content Patcher : **3** paires certaines, toutes dormantes ; le journal de CP et le signalement utilisateur passent devant → **A5** (T1–T3 livrés le 2026-08-29/30 ; restent T4/T5) |
| **§ajout** | Déclarer une traduction posée hors de l'app | **Fait** (2026-08-31) | Demandé le 2026-08-29. Mesuré : 310 des 313 traductions posées à la main étaient inconnues du registre → **A3-T6** |
| §1 | Activer automatiquement les dépendances | **Partiel** | `DependencyTreeView.swift:124` : bouton **Activer** par nœud. Manque l'action groupée → **A1-T1** |
| §1 | Détecter un `manifest.json` corrompu, proposer une réinstallation | **Partiel** | `ModFolderRepairer.swift` répare des structures de dossiers, pas des manifests invalides → **A1-T2** |
| §1 | Mise en évidence des problèmes dans la liste des mods | **Fait** | Pastille d'anomalie près du nom (**B1-T3**, pas encore publié) |
| §2 | Dates Nexus (création / mise à jour) | **Fait, pour ce qui est capté** | Revérifié le 2026-08-25 : la seule date captée (`updated_timestamp`) est nommée juste aux trois endroits qui la montrent. `created_timestamp` n'est jamais demandé — par décision. L'âge de la dernière MàJ s'affiche sur la fiche à partir d'un an révolu (**B2-T5** livré, 2026-08-27) |
| §2 | ETA pendant le téléchargement | **Fait** | Pourcentage, volume, débit, temps restant et annulation, en pied de barre latérale (**B2-T1**, 2026-08-27) |
| §2 | Poids du mod, taille de `Mods/`, espace disque restant | **Fait** | Pied de barre latérale + fiche mod (**B2-T2**, pas encore publié) |
| §2 | Splashscreen en fenêtre dédiée | **Fait** | `Views/LaunchSplashWindow.swift`, v1.10.0 |
| §2 | Boutons **Activer** / **Supprimer** sur la fiche mod | **Livré** (2026-08-01) | `ModDetailView.actionRow` → **B1-T1** |
| §2 | Le retour depuis la fiche conserve tri / filtres / scroll | **Partiel** (2026-08-01) | `ModListFilters` porté par le ViewModel ; **le scroll ne l'est pas, et c'est assumé** (pagination à 15) → **B1-T2** |
| §2 | Vérifier le bouton d'activation de la page dépendances | **Fait** | Corrigé le 2026-07-30 par `8f0a81e` (`seedFolder` remonte au pack) → **X3** |
| §2 | Boutons de rafraîchissement (quarantaine, alertes système) | **Fait** | Livré le 2026-08-26 → **B2-T3** |
| §3 | Reconnaître les mods de traduction (i18n seul) | **Partiel** | `ModItem.languages`, filtre `FrenchTranslationScope` et heuristique de nom (`ModItem.swift:99`) — **C1-T4 requalifiée et livrée** (`46ce633`) : le cas visé est à zéro mod sur le parc |
| **§new** | Installer une archive sans manifeste (traduction d'un mod, greffe type `ItemBags`) | **Fait** | Livré le 2026-08-25 (**A1-T3**, pas encore publié) ; jeu d'épreuve dans `mods tests/` |
| **§new** | Chercher sur Nexus les traductions FR et les suppléments des mods installés | **Fait** | Traductions (**A3-T2/T3**) et suppléments (**A3-T4**) livrés le 2026-08-25/26 |
| **§new** | Liste des mods : ordre alphabétique unique, packs mêlés | **Fait** (2026-08-26) | Retour utilisateur ; le tri plaçait les packs en tête — `ModItem.alphabeticalListOrder` (Core, 3 tests) |
| §3 | Nouveau profil créé **vide** | **Fait** (2026-08-24) | L'alerte propose les deux voies, « vide » en premier ; `ProfileFactory` (Core, testé) → **B3-T1** |
| §3 | Favoris de mods + import dans un profil | **Fait** | Étoile, cadrage, import nommant les intraduisibles (**B3-T2**, pas encore publié) |
| §3 | Duplication d'un profil | **Fait** (2026-08-24) | `duplicateProfile(id:)`, depuis le menu ⋯ de la ligne → **B3-T3** |
| §3 | Recherche automatique des NexusID manquants | **Fait** | Livré le 2026-08-26 (**A3-T1**) : smapi.io d'abord (20 identifiants gratuits), recherche par nom pour le reste — traductions écartées, auteur en indice, adoption sur clic |
| §4 | Backups : feedback après restauration, tri, regroupement, recherche | **Fait** (2026-08-23) | Regroupement, tri et recherche → **B4-T1** ; compte rendu de restauration (ce qui a été écrit, où, ce qu'est devenue la version remplacée) → **B4-T2** |
| §4 | Un mod restauré met à jour le registre | **Corrigé ✅** (2026-08-23) | Vérifié : la restauration d'un mod **actif** en déposait une seconde copie en pause à côté, deux dossiers pour un `folderName` — la clé du registre. Elle remplace désormais le mod là où il est → **B4-T3** |
| §4 | Sauvegarde / restauration de `config.json` et `fr.json` | **Fait** | `ModConfigBackupManager.swift` + `Extensions/ModConfigFiles.swift` |
| §5 | Éditeur de config exploitant les clés de traduction | **Fait** (v1.26.0) | **C4-T4** livré : sections, descriptions et listes déroulantes tirées du `ConfigSchema` du pack, libellés lus dans son i18n — 1889 réglages du parc y gagnent un nom lisible. Reste **C4-T1** (i18n des mods C#, 39 % côté actifs) |
| §5 | Intégrer *Modern Config Menu* / GMCM (49382, 49437) | **Instruit, écarté ✅** | Spike du 2026-08-28 (**C4-T3**) : ni l'un ni l'autre n'écrit de schéma hors du jeu. La source utilisable est le `ConfigSchema` de Content Patcher → **C4-T4**. Voir `audit-config-menus.md` |
| §5 | Aide à la configuration des raccourcis clavier | **Fait** (2026-08-29) | **C4-T2** livré : validation `SButton`, collisions inter-mods et conflits jeu — 141 liaisons, 18 collisions, 11 conflits jeu mesurés sur le parc. Angles morts restants → **C4-T7** |
| §6 | Éditeur `fr.json` avec diagnostic des clés | **À faire** | → **C2**, **C3** |
| §6 | Chaînes anglaises non traduites hors i18n (`events.json`, `dialogues.json`…) | **À faire** | → **C3-T2** |
| §6 | Pré-traduction (DeepL / Claude / Google) | **Fait** | Trois voies livrées : **locale** (Ollama / LM Studio, glossaire du jeu imposé) → **C3-T3** ; **par son propre chat** (lot `.json` exporté puis réimporté) → **C3-T5** ; **distante par API** (DeepL, marques protégées, quota lu) → **C3-T7**. Google et LibreTranslate écartés, voir la spec |
| §6 | Une mise à jour de mod signale les conflits de config/traduction | **À faire** | → **C2-T4** |
| §7 | Packs de mods et de configs distribuables | **À faire** | → **E1** |
| §8 | Éditeur de sauvegardes enrichi | **Partiel** | `SaveManager.swift` : argent, stats de base, duplication → **E3** (arbitrage) |
| §8 | Profiler / analyse FPS à l'activation d'un mod | **Reformulé** | Aucune mesure maison possible ; parsing du log Profiler → **D1** |
| §9 | Support des archives **RAR** | **Fait ✅** | Glisser-déposer depuis v1.7.1 ; chemin téléchargement/mise à jour réparé en séance (**X5**) ; commande copiable au moment de l'échec (**B2-T4**, 2026-08-26) |
| **§new** | Une archive de mod légitime est refusée à l'installation | **Corrigé ✅** | Cause racine : `unzip` sort en code 1 (avertissement) sur les archives à antislashs, refusé par un `terminationStatus == 0`. Corrigé en séance → **X4** |
| **§new** | La mise à jour d'un mod échoue si ses dossiers sont en lecture seule | **Corrigé ✅** | Cause racine : `unzip`/`unrar` restituent les modes de l'archive (dossiers en `0o555`) ; la suppression récursive exige l'écriture *sur* chaque dossier. Corrigé en séance, vérifié sur *Tilly - NPC* (38008) → **X7** |
| §9 | Doc utilisateur, screenshots, publication Nexus, Sentinel | **À faire** | → **E2** |
| *Thaï* | « Centre de traduction thaï incohérent dans un fork FR » | **Neutralisé, à finir** | `MainView.swift:13` : `showThaiTranslationHub = false` sans réglage pour l'activer → UI morte. Reste l'architecture → **C5** |

Lignes ci-dessous issues de l'**audit Stardop (2026-07-31)** — veille concurrentielle, *pas*
de la liste de l'auteur. Analyse complète et exclusions motivées : `docs/audit-stardrop.md`.

| Source | Demande | État | Preuve / renvoi |
| :-- | :-- | :-- | :-- |
| *audit* | Compatibilité mods via l'**API live `smapi.io`** (plutôt que le dump statique `mods.jsonc`) | **Fait** | Plus riche : statut + mise à jour suggérée + URL unofficial. Repositionne **A2** |
| *audit* | **Configs par profil** (un même mod, plusieurs `config.json`) | **À faire** | Manquante ; merge JSON non-destructif → **B3-T5** |
| *audit* | Notes libres par mod | **Fait** | Note par mod rangée au profil actif, signalée dans la liste (**B3-T6**, v1.21.0) |
| *audit* | Quota Nexus quotidien visible | **Fait** | Relevé sur toute réponse, affiché dans les réglages (**B2-T6**, v1.19.0) |
| *audit* | `UpdateCautionMessage` (alerte auteur avant mise à jour) | **Fait** (v1.26.0) | **B2-T7** : bannière dans la préview d'installation, message rendu tel que l'auteur l'a écrit. Aucun mod du parc ne l'expose encore |
| *audit* | Panneau de downloads observable (%, vitesse, annulation) | **Fait autrement** | Un seul téléchargement à la fois, par conception : un panneau de transferts concurrents n'aurait rien à lister. Le transfert en cours est rendu observable et annulable (**B2-T1**) |

**Bilan au 2026-08-24 (v1.18.0 publiée)** — les **7 bugs** de la liste initiale sont
corrigés, y compris le bloquant. Sur les 45 demandes : la **bissection** (axe A4) est
sortie en v1.11.0, le **hub de traduction FR** (axe C) en v1.13.0 → v1.17.0, et l'**axe
B** en **v1.18.0** — page des sauvegardes navigable, restauration qui dit ce qu'elle
écrit, récupération d'un fichier isolé puis clé à clé, diagnostic de profil, profil vide
par défaut, duplication. Restent essentiellement
**B2** (ergonomie transverse : quota Nexus, tailles, ETA de téléchargement), **B3-T2/T5/T6**
(favoris, configs par profil, notes), **B4-T4** (récupérer un fichier isolé d'une
sauvegarde), **A1/A2/A3** (registre, compatibilité smapi.io, NexusID automatiques) et la
queue de C (C2-T4, C3-T2, C4, C5). L'axe diagnostic de log est derrière nous.

> Ce paragraphe se refait à la main : le compte de tâches n'a de valeur que s'il est
> juste, et il ne l'était plus. Se fier aux cases à cocher du §5, pas à un total figé.

---

---

## Archivage du 2026-09-23 — remise à niveau

Tout ce qui suit était resté en place dans `ROADMAP.md` après livraison — 17 items jamais archivés, et 3 déjà archivés dont la copie traînait encore (C4-T1/T7/T8) et un dont le récit vivait déjà ici en §4 (R2). Corps déplacés verbatim ; les identifiants sont indexés au §11 de la roadmap.


### 4. Correctifs identifiés (suite)


- [x] **X111** ✅ *(livré le 2026-09-24)* — **Après « Effacer », le journal de l'app rognait la tête du bloc SMAPI.**
      `LogBudget.appending` écrêtait par la tête du tableau, avec un commentaire
      affirmant que « toutes les entrées concernées sont de l'app ». Le bloc
      SMAPI vit dans le même tableau et occupe toute la place que l'app laisse.
      Tant que des entrées de l'app précèdent, la tête est l'une d'elles ; après
      « Effacer » (`clearApp`), il n'y en a plus, et chaque ligne de l'app
      jetait la première ligne SMAPI — le diagnostic de démarrage (« Skipped
      mods ») d'abord, jusqu'à la relecture suivante. La carte de santé, qui lit
      le fichier entier, n'était pas touchée.
      ▸ **Trouvé** par la comparaison des corps déplacés vers `Stores/` (audit
      du VM, fin de tranche 4) : le défaut précède l'extraction (`ef807448`),
      qui l'a transporté fidèlement.
      ▸ **Mesuré le 2026-09-24** : `SMAPI-latest.txt` du parc à 11 374 lignes
      pour un plafond de 2 000 — le bloc SMAPI remplit toujours son budget.
      ▸ **Livré** : l'entrée de l'app la plus ancienne part d'abord ; sans
      elle, le bloc SMAPI rend une place par `trimPreservingSignal` (bruit
      `TRACE` d'abord). Test rouge avant, épingle du cas nominal à côté.

- [x] **X110** ✅ *(livré le 2026-09-24)* — **La corbeille ne pouvait pas purger un mod livré en lecture seule.**
      `ModTrash.purgeEntry` et `ModTrash.purgeAll` effaçaient par
      `fm.removeItem` nu. Un mod dont l'archive fixe ses dossiers en 0555
      garde ces droits une fois en corbeille : le déplacement y réussit (seul
      le parent doit être inscriptible), l'effacement échoue en `Code=513`.
      « Vider la corbeille » s'arrêtait au premier événement touché. C'est le
      piège que l'installateur a déjà réglé (X7,
      `ModZipInstaller.removeItemGrantingWriteAccess`) : la corbeille était un
      nouveau chemin d'écriture qui ne l'appliquait pas.
      ▸ **Mesuré sur le parc le 2026-09-24** : un seul mod sur 994,
      `.[CP] Toothless Pet` (dossier, `assets/` et `i18n/` en `r-xr-xr-x`). La
      mémoire « 0555 partout » était périmée.
      ▸ **Livré** : les deux purges passent par
      `removeItemGrantingWriteAccess` (tenter, puis ouvrir les droits et
      retenter). Deux tests, rouges en `Code=513` avant le correctif.

- [x] **X109** ✅ *(livré le 2026-09-24)* — **« Tout activer / Tout désactiver » pouvait vider le profil actif quand `Mods/` était devenu illisible.**
      `toggleAllMods` adopte l'état du disque (`syncActiveProfileIds`) après son
      rescan, sans condition. Or `scanMods` publie sa liste même quand il n'a
      pas pu lire `Mods/` : une liste vide. L'adoption écrivait alors
      `enabledModIds = []` et effaçait `modMetadata` du profil actif. Seul le
      journal R2 la bloquait. Même famille que X70 et X71 : une donnée vide qui
      voulait dire « rien lu » prise pour « rien activé ». Le registre était
      protégé (X71), l'adoption du profil non.
      ▸ **Pourquoi c'est réel ici** : le parc vit sur un disque externe
      (`/Volumes/BABILOGAMES`). Disque éjecté ou endormi app ouverte, liste
      encore affichée, clic sur « Tout désactiver » : tous les déplacements
      échouent, le rescan lit vide, le profil perd sa liste — et la fenêtre
      d'échec s'affiche après. Scénario tracé dans le code, pas joué : il
      aurait effacé le profil actif.
      ▸ **Livré** : `ScanStore` retient si le scan qui a posé `mods` a pu lire
      `Mods/` (faux aussi quand le dossier de jeu n'est pas renseigné) ; la
      décision d'adopter sort en Core, `ProfileRecovery.adoptDiskState`, qui
      refuse une lecture illisible après le journal R2. Cinq tests, le refus
      prouvé par sabotage.

- [x] **X108** ✅ *(livré le 2026-09-24)* — **Une mise en veille « jusqu'à la prochaine version de Stardew » se réveillait à la première lecture du journal SMAPI.**
      Le menu propose ce mode même quand la version du jeu est inconnue (aucun
      journal lu : installation neuve, journal illisible). Le snooze gardait
      alors `gameVersionAtSnooze = nil`, et la lecture suivante comparait
      `"1.6.15" != nil` : réveil immédiat, jeu inchangé — l'inverse de la règle
      écrite dans l'en-tête de `ModUpdateSnoozer` (« on ne réveille pas sur une
      absence, seulement sur un changement »). Prouvé par un test rouge.
      ▸ **Livré** : la première version lue devient la référence manquante,
      persistée, et seule une version suivante réveille. Le mode « jusqu'à la
      prochaine version du mod » n'est pas concerné : `latestVersion` n'est
      jamais `nil`.
      ▸ **Au passage, deux silences d'écriture du report de clés renommées
      (C2-T4)** : l'enregistrement du delta après report (`try?`) et la
      sauvegarde de `config.json` avant report (`_ = try?`) se journalisent
      désormais, comme le chemin de l'installation et l'éditeur. La sauvegarde
      « une par mod et par jour » devient une seule fonction,
      `ModConfigBackupManager.backUpConfigOncePerDay`, partagée par l'éditeur
      et le report — les deux copies avaient divergé (l'une journalisait,
      l'autre avalait ; l'une appliquait la rétention, l'autre non).

- [x] **X107** ✅ *(livré le 2026-09-24)* — **Un favori dont le dossier a quitté le disque hors de l'app restait pour toujours.**
      `forgetStores` était la purge commune à la suppression, mais les favoris,
      la marque « à écarter », l'historique d'erreurs, la référence de
      traduction et la couverture FR ne partaient que dans la **branche de
      succès** de `deleteMod`. La branche « dossier déjà absent » — le mod a
      quitté le disque par le Finder ou une réorganisation — appelait
      `forgetStores` seule. Et l'écran Entretien (X25) ne jugeait que quatre
      magasins : les favoris et la marque « à écarter » (arrivée le 2026-09-07,
      après X55) n'y figuraient pas, si bien que rien ne pouvait retirer
      l'orphelin. Même famille que X69 : le chemin voisin qui n'applique pas la
      règle.
      ▸ **Mesuré sur les préférences réelles le 2026-09-24** : `favoriteMods`
      porte 46 clés dont **une orpheline**, `[CP] Stardew Valley Expanded` —
      SVE vit depuis le 2026-09-22 dans le pack `Stardew Valley Expanded/`. Le
      badge Favoris affichait 46 pour 45 lignes, et SVE n'était plus en favori.
      Les autres magasins sont propres (registre 1 148, horodatages 543,
      `nexusCustomModIds` 204, `blacklistedMods` 11 : zéro orpheline, un
      composant de pack en pause compté présent — le point vit sur l'en-tête).
      ▸ **Livré** : les cinq purges entrent dans `forgetStores`, que les deux
      branches partagent ; `ModRemovalPurge` y emporte aussi les composants d'un
      pack supprimé (l'ancien `remove(folderName)` n'ôtait que l'en-tête). La
      liste des clés jugées par l'Entretien passe en Core,
      `MaintenanceInventory.folderKeyedPreferenceKeys`, six magasins, et
      `cleanStaleMaintenanceEntries` purge les deux ensembles. Deux tests,
      rougis par sabotage (retirer les favoris de la liste).
      ▸ **Écarté** : la cause de la réorganisation de SVE. La branche
      `.overwriteWithBackup` de l'installateur réinstalle au `folderName`
      existant — elle ne peut pas avoir déplacé SVE dans un pack. Le correctif
      couvre toute disparition hors de l'app, quelle qu'en soit la cause.

- [x] **X106** ✅ *(livré le 2026-09-13)* — **Un `NSLock` est pris et rendu dans un contexte asynchrone.**
      `SmapiUpdateClient.swift:110` et `:112` — le compilateur le dit déjà
      (`instance method 'lock' is unavailable from asynchronous contexts`), et
      c'est l'un des **13 avertissements que le code porte aujourd'hui**, qu'un
      build incrémental ne réémet pas (relevé P5 du 2026-09-11,
      `docs/REFACTORING.md` §9). Un verrou tenu à travers une suspension
      immobilise un thread du pool coopératif, qui en compte autant que de
      cœurs : c'est la seule des quatre trouvailles du relevé qui soit un risque
      **d'exécution** et non une branche morte. Remplacer par un verrouillage
      porté par un acteur, ou borner la section critique en dehors de tout
      `await`. ⚠️ Mesurer d'abord s'il y a réellement un `await` **dans** la
      section : le diagnostic vise le contexte, pas la portée du verrou.
      **Le verdict de la mesure** : la crainte ne s'est **pas** réalisée —
      aucune des deux sections critiques ne contenait d'`await`. La première
      vivait dans `fetch`, fonction synchrone ; la seconde (`lock / inFlight =
      nil / unlock`) est une ligne droite **après** le `await task.value` qui
      précède la prise du verrou. Aucun thread du pool coopératif n'a jamais
      été immobilisé. Le danger réel était ailleurs : le SDK précise *this is
      an error in the Swift 6 language mode* — la migration Swift 6 aurait
      cassé le build. **Livré** : les deux sections bornées dans des helpers
      **synchrones** (`engage(makeTask:)` d'un tenant, l'atomicité du
      check-and-set X87 préservée au même verrou ; `clearInFlight()`),
      2 diagnostics → 0. Le mécanisme X87, jusque-là sans **aucun** test (le
      filet existant ne couvrait ni la sérialisation ni le nettoyage), est
      épinglé par `anOverlappingCallWaitsItsTurnAndTheSlotIsReturned` — épingle
      à sémaphore, prouvé rouge par deux sabotages (branche « passe en vol »
      morte → les passes s'entremêlent ; créneau jamais rendu → la complétion
      du second appel ne part jamais). ⚠️ Appris au passage : un appel
      chevauchant ne récupère pas le verdict de la passe en vol — il en
      déclenche une **seconde**, sérialisée, après elle (mesuré : 2 + 2
      requêtes, retraits X47 compris). Comportement livré, laissé tel quel ;
      un court-circuit vers le verdict existant serait une décision propre.
      *(Trois autres trouvailles du même relevé, sans risque d'exécution —
      `NexusArchiveStore.swift:117` un `??` à membre gauche non optionnel donc
      une branche morte, `StarHubTHViewModel.swift:2909` un `seedFolder` calculé
      jamais utilisé, `StarHubTHApp.swift:105` un `bootstrapDefaults` inféré
      `Void` — **corrigées le même jour**, avec trois avertissements de plus
      repérés au même build : un `mutateIfChanged` dont le `Bool` était ignoré
      sans le dire, deux `index` de garde jamais lus, exprimés en
      `contains(where:)`. Le `Void` explicite de `bootstrapDefaults` est
      **porteur d'ordre** : la propriété est déclarée avant le `@AppStorage` de
      l'App, qui lit `UserDefaults` à son initialisation — déplacer
      l'appel dans `init()` inverserait la reprise pour ce lecteur.)*
      **La classe concurrency — traitée le même jour (2026-09-13).** ⚠️ Le
      relevé annonçait 6 diagnostics ; la re-mesure sans drapeau en rendait
      **7** — le refactor avait lui-même introduit 4 brèches de conformance
      `Sendable` en Core (types publics : jamais d'implicite). Les sept
      éteints, chacun à son verdict : conformités explicites
      (`ModInstallBackup` + 2, `NexusModSearch.Page`) ; `FileManager` créé
      **dans** la closure (patron de la boucle sœur) ; `nonisolated(unsafe)`
      borné au store pour le relais de progression Nexus ; boîte `weak`
      `@unchecked Sendable` pour la bascule en masse — 🚩 une capture-liste
      `[weak x]` **défait** la liaison `nonisolated(unsafe)`, prouvé au gate.
      Passe sans drapeau : **7 → 0** ; gate + 3 152 tests verts. ✅ Vérifié à
      l'écran par l'auteur le 2026-09-13. **La phase P5
      reste fermée** : 453 diagnostics stricts — 202 bloquants Swift 6 — au
      jalon du chantier (467 au 2026-09-11) ; **L1 close le 2026-09-13 :
      427 / 184 bloquants** (quinze globales éteintes sur seize,
      `SaveNotesStore.shared` reportée à la tranche des stores) ; **L2 close
      le même jour : 237 / 85 bloquants** — `@MainActor` sur le ViewModel,
      102 bloquants tombés (prévision ~95), le VM (13) sort du top 2 de la
      dette au profit de `SmapiInstaller` (25) et `SmapiUpdateClient` (22) :
      c'est ce qui cadre L4. ✅ **Vérifié à l'écran par l'auteur le
      2026-09-13** (liste des mods, bascule d'un mod, application d'un
      profil, ouverture d'une sauvegarde, recalcul de couverture de
      traduction, glisser-déposer en échec, recherche Nexus) — **L2 est
      close**. **L3 close le même jour : 216 / 83 bloquants** — les deux
      boucles disque (bascule en masse, application de profil) exécutent
      en Core via `ModFolderBulkMove` (canal `AsyncStream`, exécution
      testée pour la première fois) ; baisse de compteur modeste (−2
      bloquants), le gain est la testabilité et le rescan rendu au fond.
      ✅ **Vérifié à l'écran par l'auteur le 2026-09-13/14** (bascule en
      masse filtrée, application de profil, profil avec mod manquant,
      bissection profil) — ce rejeu a révélé le doublon SotV et déclenché
      le chantier « collision de nom logique à l'installation » (signal +
      choix dans l'aperçu, vérifié le 2026-09-14). **L3 est close.** La fin
      de jeu structurée (exécuteurs Core + `AsyncStream`) est faite.
      **L4 close le 2026-09-14 : 121 / 28 bloquants** — les trois clients
      réseau/process traités en trois familles (`SmapiInstaller` façade
      `@MainActor` 25 → 0 ; types traversants de `SmapiUpdateClient`
      `Sendable` 22 → 0, X87 prouvé intact par le diff ; les deux
      complétions de `NexusUpdateChecker` `@Sendable` 8 → 0, ses huit hops
      inchangés). **55 bloquants tombés, exactement les 55 ciblés** — ⚠️ le
      critère « 60 » de la spec était périmé, il datait d'avant L3. Deux
      découvertes consignées : une passe stricte **tuée sous-compte en
      silence** (12 fichiers couverts sur 17 ; le compte intermédiaire de T2
      était faux de 3), et un type **public** (`NexusInstallFacts`) casse
      l'inférence `Sendable` d'un type interne à un maillon de distance.
      ✅ **Vérifié à l'écran par l'auteur le 2026-09-14** (installation SMAPI
      réelle → désinstallation → réinstallation) — **L4 est close**. La
      vérification a échoué du premier coup et a livré un défaut **antérieur
      à la tranche** : l'installateur lancé sans `PATH` ne trouvait plus
      `chmod` et s'arrêtait le jeu à moitié installé (cassé depuis le
      2026-09-07). Corrigé, plus les libellés de désinstallation et la
      persistance de la sortie de l'installateur. Reste la sortie d'acteur de `scanMods` (tranche
      d'isolation). **L5 close le 2026-09-14 : le Core compile en
      `swiftLanguageMode(.v6)`** — 101 / 20 bloquants, et surtout un cliquet
      tenu par le compilateur sur la moitié testée du dépôt. ⚠️ La bascule a
      rougi la CI au premier essai : elle compile en **Xcode 16.4 (Swift
      6.0)**, la machine de développement en 6.3.3, et la première est plus
      stricte. Défaite sur `main`, reprise en PR, validée par la CI avant
      fusion (#6). Reste **L6** : l'app en mode Swift 6 (VM 12,
      `NexusSearchClient` 2, `ModInstallView` 2, quatre vues à 1).
      **L6 close le 2026-09-14 : 6 / 0 bloquants** — le compte du chantier
      tombe à zéro (453 / 202 à l'ouverture). ⚠️ **L'app n'est pas pour
      autant en mode Swift 6** : le drapeau a été posé puis retiré, car
      l'app compile sans erreur et **meurt au lancement** — le mode 6
      contrôle l'isolation *à l'exécution*, et `scanMods` /
      `syncInstalledModRegistry` / `reloadSaves` sont déclarées `@MainActor`
      mais exécutées sur une file de fond depuis L2. La **tranche
      d'isolation** devient donc le prérequis du mode 6 côté app, et non un
      raffinement : c'est ce qui reste de P5. Détail, pile et sondes :
      `REFACTORING.md` §9.
      **Cadrage mesuré le 2026-09-14** (première étape livrée : `log`,
      `publishLaunchPhase` et `publishLaunchPhaseProgress` sont `nonisolated`,
      leur corps l'était déjà). Marquer `scanMods`,
      `syncInstalledModRegistry`, `reloadSaves` et
      `migrateDisabledModsToDotPrefix` `nonisolated` rend **16 erreurs** que
      le compilateur nomme : 5 `log` (faites), 4 lectures de `gameDir`, 7
      appels isolés (`installedModDate`, `publishLaunchPhase` ×3,
      `parseSMAPILog`, `measureModsFolderSize`). ⚠️ **Le verrou est
      structurel** : une méthode `nonisolated` ne peut lire *aucune*
      propriété stockée du ViewModel — ni `gameDir`, ni `environment`, ni les
      magasins. Il faut donc trancher magasin par magasin ce qui est lisible
      hors acteur.

      ⚠️ **Le relevé des magasins était faux, et son ordre avec lui.** Il
      annonçait « `ModScanner` (20 `var`) — le seul à examiner vraiment » :
      c'était un `grep` nu, qui comptait les variables **locales** de
      `scan()`. Recompté le 2026-09-14 en ancrant sur l'indentation des
      propriétés stockées, l'ordre s'inverse — les trois premiers sont le
      **même cas trivial**, une seule mutable sous un seul verrou, et le
      quatrième n'appartient pas à la famille :

      | Magasin | Propriétés stockées **mutables** | Verdict |
      | --- | ---: | --- |
      | `ModVersionAnchorStore` | **0** | `let` partout |
      | `InstalledModRegistryStore` | 1 (`cache`) | 3 accès, tous sous `lock` |
      | `ModScanner` | 1 (`manifestCache`) | 2 accès, tous sous son verrou |
      | `ScanStore` | 5 `@Observable` + 2 sous `sizeLock` | **état publié, lu par les vues** |

      Les **trois premiers sont traversants depuis le 2026-09-14**, l'audit
      écrit à chaque déclaration. ⚠️ La conformité *vérifiée* a été tentée
      d'abord et **refusée par le compilateur** : `UserDefaults` n'est pas
      `Sendable` — c'est la seule raison de l'`@unchecked` sur les deux
      magasins qui en portent un, pas une promesse sur leur état.
      **`ScanStore` reste `@MainActor` et n'est pas à rendre traversant** :
      ce n'est pas un cas plus dur du même geste, c'est de l'état d'interface
      observé par les vues. L'ouvrir serait la mauvaise réponse — c'est
      `scanMods` qui doit cesser de le toucher hors acteur, pas lui qui doit
      s'ouvrir. `GameEnvironmentStore`, isolé en L5, est le dernier cas à
      part : son `gameDir` est persisté à chaque écriture, donc lisible hors
      acteur par les préférences.

      **Étape 2 livrée le 2026-09-14 — et le coût mesuré valait la moitié de
      l'annonce.** Les quatre méthodes marquées `nonisolated`, le compilateur
      nomme **7** erreurs, pas 16 : les conformités ci-dessus en avaient
      éteint la moitié d'un coup, parce qu'**un `let` de type `Sendable` sur
      un acteur est implicitement lisible hors de lui**. Mieux :
      `reloadSaves`, `syncInstalledModRegistry` et
      `migrateDisabledModsToDotPrefix` n'en produisaient **aucune** — elles
      étaient déjà prêtes. Les sept vivaient toutes dans `scanMods`.

      Elles se sont réglées en trois gestes :

      - **`gameDir` arrive en paramètre** (4 des 7), résolu par l'appelant sur
        l'acteur — dix sites d'appel, chacun le lisant avant son saut. C'est la
        décision que L5 avait déjà prise pour `fallbackFarmerName`. ⚠️ La
        variante « le lire hors acteur depuis les préférences », que le cadrage
        proposait, a été **écartée sur preuve** : `restoreGameDir` écrit un
        chemin détecté *avant* que son `didSet` ne le persiste, et une lecture
        qui croise cette fenêtre rend l'ancien chemin.
      - **`parseSMAPILog`, `computeSmapiDiagnostics`, `installedModDate`
        passent `nonisolated`** — les deux premières promettaient déjà « safe
        off-main » dans leur propre documentation ; la signature le dit enfin.
      - **`measureModsFolderSize` reste `@MainActor`**, atteinte par un saut
        `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` — le
        patron du dépôt, et celui que L5 a prouvé préférable à
        `Task { @MainActor in }` (deux tests de magasin et un du client
        smapi.io rougissent sur le second, qui n'entre pas dans le FIFO de la
        file principale). ⚠️ Son invariant a été vérifié plutôt que supposé :
        `beginSizeMeasure` est un test-and-set **sous `sizeLock`**, donc
        atomique d'où qu'on l'appelle. Le saut ne l'affaiblit pas, il
        sérialise deux demandes rivales.

      Relevé en passant, **corrigé le même jour** : la restauration depuis la
      corbeille était le seul site qui balaie **sur le fil principal** — ~960
      mods y gelaient l'interface le temps de la passe. Le saut par la file
      globale, inatteignable tant que le site appelait une méthode faussement
      `@MainActor`, est devenu mécanique après la tranche : `gameDir` résolu
      sur le main, balayage sur la file `userInitiated`, comme les autres.

      **Passe stricte de clôture** : 57 / 8 après le basculement, **49 / 0**
      après extinction des huit — la passe de départ (6 / 0) était un faux
      vert, le compilateur ne regardant pas les franchissements d'un corps
      qui se déclarait sur l'acteur en tournant au fond. Les 43 avertissements
      restants sont du bruit préexistant que le drapeau voit maintenant sur ce
      chemin ; **zéro bloquant Swift 6**.

      **La phase P5 est close le 2026-09-14** : le drapeau `-swift-version 6`
      est reposé sur l'app (`8e2729cf`) et **tient** — lancement vérifié par
      l'auteur à l'écran, CI verte (Xcode 16.4, plus stricte que la machine).
      Bilan du chantier, jalon d'ouverture → clôture : **453 avertissements /
      202 bloquants → 49 / 0**, Core et app en mode Swift 6, le cliquet tenu
      par le compilateur sur la moitié testée et désormais par le runtime sur
      l'autre. Ce que la fin de jeu a coûté et appris : le faux vert des 6/0
      (un compilateur fait confiance à une étiquette, un runtime pas), le
      grep nu qui surenchérit (20 `var` = des locales), et trois filets (gate,
      tests, CI) muets sur un crash que seul un lancement observé voyait.


- [x] **X105** — ✅ **livré le 2026-09-10.** `Backups/` vit sous `StarHubFR/`,
      et l'ancien dossier disparaît entièrement à la migration. Ses **220
      chemins absolus** (champ `backupPath`, seul champ absolu des deux index —
      énumération faite champ par champ, pas devinée) sont repointés **avant**
      le déplacement, qui est un rename sur le même volume et non une copie des
      1,2 Go. Le gain n'est pas la cohabitation — l'amont n'a jamais écrit là :
      c'est que les données de l'app tiennent désormais en **un seul endroit**.
      Chiffres du plan de 2026-08-26 (1 468 sauvegardes, 1 309 chemins, 617 Ko)
      périmés d'un facteur 6 ; compter ces chemins sans échapper les slashes
      rend 0 (défaut corrigé en `01ef900`).


#### Fiabilité du registre & compatibilité — Axe A (suite)

- [x] **A1-T10** — ✅ **Livré le 2026-09-24.** **Le nettoyage guidé d'une sauvegarde : écrit, jamais
      automatique.** *(même audit, 2026-09-23 ; **livrée** le 2026-09-24 :
      une seule catégorie — les clés `smapi/mod-data` des mods disparus, la
      liste exacte de la section de la fiche (règle partagée
      `SaveAbsentMods.absentKeyCounts`, `legacy-migrated` compris) ; bouton
      « Nettoyer… », feuille clé par clé, backup vérifié non vide, écriture
      atomique BOM préservé, item atypique laissé et compté (8bb01778..ab0539ec).
      Locations et arbres hors périmètre : attribution heuristique — spec
      `docs/superpowers/specs/2026-09-23-save-cleanup-design.md`.)* Ce que
      SaveSaver fait au chargement (reconstruire un `ErrorItem` en objet vanilla,
      élaguer une location disparue, convertir un arbre cassé) deviendrait ici un
      geste explicite : **opt-in par catégorie, diff affiché avant écriture,
      backup vérifié non vide avant, écriture atomique `.tmp` → move** — la
      discipline du mod est correcte et rejoint les nôtres
      (`ModConfigWriteGuard`, snapshot `beforeUpdate`).
      ⚠️ **Jamais** l'auto-conversion au chargement (son défaut : vraie par
      défaut, et son seuil `Error` est large), ni le cas fourre-tout « type
      inconnu → `Object` vide » (destructif sur un faux positif).
      ⚠️ **Chaque catégorie de nettoyage s'instruit séparément** : la grammaire
      d'écriture d'un save n'est pas mesurée chez nous, et
      `stardew-save-editor` (SOURCES §3) reste la référence du domaine. · **L**

- [x] **A1-T9** — ✅ **Livré le 2026-09-23.** **L'audit de sauvegarde en lecture : la taxonomie SaveSaver sans
      son bistouri.** *(même audit, 2026-09-23 ; **livrée** le 2026-09-23 :
      familles arbres + locations dans les empreintes (ed78b150), absents
      nommés par clés à uid exact sur la fiche (753cf0a2, cache de scan
      partagé entre sections — lecture+scan de 37 Mo mesurés à ~10 s).)*
      SaveSaver (Nexus 52709,
      décompilé) montre ce qu'une sauvegarde peut porter de cassé : items
      `ErrorItem`, locations de mods disparus, bâtiments inconnus, arbres
      sauvages/fruitiers de mods, types C# non résolus. Tout se détecte **hors
      jeu, en lecture seule** — `SaveManager` parse déjà le XML, et l'app connaît
      l'état du parc (actif / en pause / absent), ce que SaveSaver ignore : lui ne
      peut dire « type inconnu », nous pouvons dire « type du mod X, en pause ».
      **Un écran de diagnostic doit conduire** : chaque ligne porte le mod
      responsable et sa fiche, ou l'option de nettoyage (**A1-T10**).
      ⚠️ **Ne pas porter les listes vanilla codées en dur du mod** (77 locations,
      21 bâtiments, ids d'arbres — divergeront des mises à jour du jeu) : la
      vérité est dans le contenu du jeu et du parc, lue comme lui la lit
      (`DataLoader` côté jeu, manifestes et DLL côté app).
      ⚠️ Son seuil `IsErrorItem` (`DisplayName.Contains("Error")`) est un faux
      positif ambulant — un item légitime au nom traduit contenant « Error »
      serait converti en pierre chez lui ; ne pas l'imiter. **Le harnais de
      test existe pourtant chez lui** : `savesaver_infect` injecte huit faux
      items C# cassés dans une sauvegarde pour provoquer et rejouer le scénario
      — le moyen de tester cet item sans attendre un vrai accident, la fixture
      étant produite par un vrai producteur, jamais à la main.
      ▸ **Hérité d'A1-T6 (livré sans eux)** : (1) ✅ les mods **absents** du
      parc — section « Mods disparus de la médiathèque » sur la fiche
      (753cf0a2, 2026-09-23) ;
      (2) ✅ le même avertissement **à l'activation d'un profil** — livré
      (tranche 1, 2026-09-23 ; avec deux correctifs d'A1-T8 : « Annuler »
      reprenait la bascule, et un pack n'était jamais chiffré) ; ✅ la
      **bascule en masse** (« Tout désactiver ») aussi, tranche 2a.
      ▸ **Mesuré le 2026-09-23 (Zofia + TestOK, 1 127 ids) — le cadrage change :**
      - *La taxonomie SaveSaver ne trouve rien* : 0 type `xsi` de mod (109
        types, tous vanilla) ; les 2 « Error Item » sont le placeholder
        `RANDOM_CLUMPS` d'ItemExtensions, **actif**. Un écran bâti sur elle
        resterait vide.
      - *La règle de préfixes est réfutée* : les ~200 orphelins sont presque
        tous des mods **installés** dont l'espace de noms n'est pas l'UniqueID
        (`Kedi.VPP.*` = KediDili.VanillaPlusProfessions, `moonslime.Wizardry.*`
        = WizardrySkill, `FashionSense.*`, `Casa.*`/`Evento.*` = Defense
        Division en pause, 34 locations). `Lumisteria.MtVapius`, le cas
        « absent » de l'audit, est **installé**.
      - *L'attribution par contenu* (json/dll/tmx, UTF-8 + UTF-16) coûte 66 s
        sur 531 Mo et laisse 48 chaînes ambiguës et 75 introuvables sur 206.
      - *Les absents sûrs viennent des clés à uid exact* : `smapi/mod-data/<uid>`
        et `<uid>/<clé>` (A1-T9 tranche 0, corrigé : le scanner refusait le `/`,
        64 mods en pause au lieu de 43 sur Zofia) — `aloofllama.giftdiscovery`,
        `thalethegreat.walletautopetter`, `foxisadev.bqr`, `BiggerAutoGrabber`…
      - *Deux familles non lues* : arbres (`treeType`, 518 sapins SVE) et
        locations (298 `Custom_*` jamais vues ; les namespacées tombent dans
        « objets » par le repli `<name>`).
      **Option retenue (a)** : familles arbres + locations, absents nommés par
      les clés à uid exact, **aucune attribution heuristique**. · **M**

- [x] **A1-T6** — ✅ **Livré le 2026-09-23.** **Une sauvegarde sait quels mods l'ont écrite — on ne le lui demande
      jamais.** *(trouvé le 2026-09-14 en cherchant ce que `Stardew Save Launcher` a
      d'exploitable : son `Core.dll` manipule `SaveModIds` et `CommonModIds`. Mesures
      dans [`roadmap-archive.md`](roadmap-archive.md) §3 ter.)*
      Le fichier de sauvegarde porte les `modData` que chaque mod y a écrits, et leurs
      clés sont préfixées de l'`UniqueID` du propriétaire — la clé d'identité du parc.
      **Mesuré sur `Zofia_443716371` (37 Mo)** : 8 984 clés, **748 préfixes distincts**,
      dont **32 résolvent vers un mod installé**. Trois d'entre eux sont **en pause** :
      `larvuk.AdvancedFruitTreeFramework` (**1 648 entrées**), `NCarigon.BushBloomMod`
      (154) et `Spiderbuttons.Agromancy` (115).
      **Ce que l'écran dirait** : « cette sauvegarde porte du contenu de 3 mods que tu as
      mis en pause » — au moment d'activer un profil, ou sur la fiche de la sauvegarde.
      Aucun autre gestionnaire ne le fait, et StarHubFR a déjà les deux moitiés : le
      lecteur de sauvegardes et le registre des mods.
      ⚠️ **Sévérité mesurée, pas supposée : ce n'est PAS une perte de données.** Les
      `modData` d'un mod absent **survivent** — `Kedi.VPP.WasRainingHere` porte 817
      entrées sans aucun mod installé qui corresponde, et le compte est **stable sur
      trois générations** de la même sauvegarde (805 → 817 → 817). Les 56 préfixes
      disparus entre la plus ancienne et la plus récente sont des clés **à expiration**
      (`_memory_oneweek`, `_memory_eightweeks`), pas une purge. Le texte doit donc dire
      « du contenu dort », jamais « tu vas perdre ». *(Ce qu'il advient des **objets**
      définis par un mod absent — pas de leur `modData` — n'est pas mesuré ici.)*
      ⚠️ **La règle de normalisation reste à mesurer, et c'est le vrai travail.** Les
      695 préfixes non résolus ne sont **pas** 695 mods manquants : `Kedi.VPP.WasRainingHere`
      est une clé de `Kedi.VPP`, et `Cropgenics.GroveForestNode.Health` / `.Variant` /
      `.Master` sont des sous-clés d'un même propriétaire. Le relevé ci-dessus s'arrête à
      deux segments ; la vraie règle se mesure sur le parc avant d'être codée — c'est le
      constat de `spec-rules-need-measuring`, où la règle écrite était fausse **dans les
      deux sens**. · **M**
      ✅ **Ce qui a été fait.** `SavePausedFootprints` (Core, 7 tests, un
      sabotage par mécanisme) croise le scan d'**A1-T8** avec l'état du parc :
      la résolution reçoit **tous** les UniqueIDs puis filtre les mods en pause
      (sinon l'empreinte d'un mod actif `A.B_C` retomberait sur un `A.B` en
      pause) ; un id aussi porté par une copie active ne dort pas ; deux copies
      en pause font une rangée ; un id vide n'attribue rien ; un composant de
      pack en pause est rapporté sous son dossier. `SavePausedFootprintStore`
      scanne hors fil principal, garde le scan en cache par dossier et date,
      refait la résolution à chaque bascule, et n'affiche que la réponse à la
      dernière demande. La section « Mods en pause dans cette sauvegarde » de
      la fiche conduit chaque rangée à la fiche du mod (onglet État).
      📏 **Mesuré sur Zofia avec le vrai parc** (1 146 mods, 855 en pause,
      1 141 ids) : **43 mods en pause** rapportés, Alchemistry en tête
      (815 objets, 42 clés), Dayswork 1 bâtiment ; scan 1,7 s + résolution
      0,36 s contre le parc entier (build release), hors fil principal.
      ▸ **Hors périmètre, délibérément** : les mods **absents** du parc et
      l'avertissement à l'activation d'un profil — reportés, vivants, dans
      **A1-T9** (ROADMAP).


- [x] **A1-T8** — ✅ **Livré le 2026-09-23.** **Avertir à la bascule : mettre en
      pause un mod ne met pas en pause ses empreintes dans les sauvegardes.**
      *(né de l'audit [Keybind Radar & SaveSaver](audit-keybind-radar-savesaver.md) ;
      complète **A1-T6** et répond à sa question laissée ouverte — ce qu'il advient
      des **objets** définis par un mod absent, pas de leur `modData` — par la
      mesure.)* Mesuré sur `Zofia_443716371` : **757 objets**
      `Morghoula.AlchemistryCP_*` et un bâtiment `Bindicle.Dayswork_Office` pour
      des mods **en pause**, ~133 nœuds `Lumisteria.MtVapius_*` pour un mod
      **absent** ; 457 identifiants namespacés distincts au total. Les empreintes
      ont tenu au seul croisement des identifiants namespacés contre les
      manifestes du parc — `DotNetMetadata` (C4-T11) n'a pas été nécessaire.
      ⚠️ **Sévérité instruite avant d'écrire le texte** : aucun crash observé —
      les empreintes sont des objets/ressources référencés par id, pas des types
      C# (0 `xsi:type` de mod sur les deux saves actives). Le cas crashant de
      SaveSaver (types C# orphelins) est réel dans la nature mais non observé ici.
      L'avertissement suit la sévérité mesurée, pas le pire cas — « voilà ce qui
      restera », jamais « tu vas perdre » (même discipline que **A1-T6**).
      ✅ **Ce qui a été fait.** `SaveFingerprintScanner` (Core, XMLParser
      événementiel) compte les empreintes par porteur — objets (`name`/`itemId`
      dédupliqués à la fermeture de l'élément : un objet porté par les deux champs
      compte une fois ; 1 922 `itemId` namespacés pour 1 648 `name` sur Zofia),
      bâtiments (`buildingType`), clés `modData` (`key`>`string`) ; les références
      des listes de butin (`<string>` isolés, 667 sur Zofia) ne comptent pas.
      `SaveFingerprintResolution` croise avec les UniqueIDs du parc — identique,
      préfixe `_`/`.`, clé de jeu `<fonction>_<uid>` (règle **générique** : la
      fonction est un mot de lettres avant le premier underscore — 138 clés
      mesurées, `firstVisit_` 63, `eventSeen_` 39… — jamais une liste codée en
      dur qui divergerait des mises à jour du jeu), forme SMAPI
      `smapi/mod-data/<uid>/` (43 clés). Le préfixe le plus long gagne (`A.B_C`
      avant `A.B`) ; une empreinte orpheline n'attribue rien — zéro ambiguïté
      mesurée sur 1 125 UniqueIDs et deux saves.
      ✅ **Le geste** : `performToggle` intercepte toute bascule vers pause
      (pack compris — les UniqueIDs de tout le plan), scanne les saves hors fil
      principal via `SaveFingerprintPauseStore` (extrait, règle F1-T2) et suspend
      le geste derrière une alerte racine chiffrée par save quand le rapport
      n'est pas vide — « Mettre en pause n'efface pas ce que X a laissé dans vos
      sauvegardes : Zofia : 757 objets ». Rapport vide → bascule immédiate, sans
      confirmation pour rien. `isToggling` reste posé pendant scan et suspension :
      la file de bascule n'enchaîne pas, le spinner de la rangée reste visible.
      19 tests Core, mécanismes prouvés par sabotage.
      ▸ **Ce que A1-T8 ne fait PAS, et c'est délibéré** : la **bascule en masse**
      (`toggleAllMods`) traverse `ModFolderBulkMove`, pas `performToggle` — elle
      reste muette, comme la **désinstallation** ; l'audit **A1-T9** rendra le
      chiffre visible hors du geste.


- [x] **A1-T7** — ✅ **Livré le 2026-09-15** *(option A ; l'option C s'est trouvée
      déjà en place)*. **Mettre à jour un mod perdait ses données — et la liste des
      rescapés tenait en 18 noms.** *(trouvé le 2026-09-14 en décompilant
      `ModernConfigMenu` 2.1.2 ; mesures dans
      [`roadmap-archive.md`](roadmap-archive.md) §3 quater.)*
      `ModConfigFiles.preservable` est une **liste blanche de noms de fichiers** :
      `config.json` et les 17 fichiers de langue. `snapshotUserConfigs` ne préserve
      qu'eux. **Tout le reste est écrasé** par la copie neuve.
      ✅ **Le filet existe, et il est entier** : avant l'effacement,
      `ModInstallBackupManager.createBackup(for:gameDir:reason: .beforeUpdate)` copie
      le **dossier complet** (`copyItem`, `:235`), et doit réussir sous peine
      d'abandon de l'installation. Rétention : tout ≤ 30 jours, puis une par mois.
      Le défaut n'est donc **pas** une destruction — c'est que ces fichiers ne sont
      **jamais remis** dans le mod mis à jour, et que **rien ne le dit** : le joueur
      retrouve un mod amnésique et devrait deviner d'aller fouiller une sauvegarde.
      **Mesuré sur le parc** : **100 fichiers, sur 52 mods**, portent dans leur nom
      l'identifiant d'une **sauvegarde réelle** — ils n'ont donc pu être écrits que
      sur cette machine, par le mod. Ce sont des `<sauvegarde>_SaveData.save` et
      apparentés (`FarmTypeManager` et ses 40 packs `[FTM] *`,
      `BetterCrafting/savedata/seenrecipes/`, `AnimalHusbandryMod/data/farmers/`) :
      de la **progression par partie**. Les perdre, c'est perdre le jeu lié à ce mod
      pour cette sauvegarde. C'est un **plancher** — il ne voit pas ce qui ne se nomme
      pas d'après une partie.
      ⚠️ **Une version antérieure de cet item annonçait « 2 552 fichiers sur 256
      mods »** : ce chiffre venait d'un critère de mtime relative au manifeste, et il
      est **faux** — un zip restitue les dates de travail de l'auteur. Détail du
      démenti en **§8.4**. Viennent ensuite
      `companion.json` (67) et `companion.png` (44), et le cas fondateur
      `data/mod_history.json` — que MCM écrit **toujours** en 2.1.2 (vérifié dans l'IL :
      `ModDateTracker.HistoryFilePath`), et qui porte la date d'installation de chaque
      mod pour signaler les récents.
      ⚠️ **Le CLAUDE.md ne nomme que `config.json` et `fr.json`** : le piège est donc
      plus large que ce que le dépôt en dit.
      ⚠️ **Le remède n'est PAS « préserver tout fichier écrit après l'installation ».**
      Ce garde trop large garderait à vie les fichiers qu'un mod renomme ou abandonne
      d'une version à l'autre — et c'est exactement le défaut qu'`isAuthorLanguageFile`
      a dû corriger après coup, quand la préservation figeait l'anglais de l'auteur à
      chaque mise à jour. La règle se **mesure** avant de se coder : ce qui distingue
      une donnée d'utilisateur d'un fichier livré n'est ni le nom, ni l'extension, ni
      la seule mtime. Deux pistes à éprouver — un fichier **absent de l'archive neuve**
      est par construction une donnée locale ; et `content.json` (111 occurrences) est
      le contre-exemple utile, puisqu'il est livré **et** modifiable.
      ⚠️ Et quoi qu'il arrive, **le dire** : un fichier écarté de la préservation doit
      apparaître au bilan d'installation, jamais disparaître en silence.
      ✅ **Ce qui a été fait** : `PreservedModData` (Core) porte la règle et ses deux
      moitiés (mise à l'abri, remise en place) ; `ModZipInstaller` compare les deux
      arbres juste avant l'effacement, là où l'ancien dossier et l'archive neuve
      existent tous les deux. La restauration d'un extra **ne lance pas** — rater un
      fichier de données périmé ne doit pas faire avorter une mise à jour réussie,
      le dossier entier étant déjà en sauvegarde ; celle des 18 noms lance toujours.
      Les préservations sont journalisées, les échecs en `warning` et **nommés**.
      19 tests, huit mécanismes prouvés par sabotage.
      ✅ **Le bilan le dit aussi** (2026-09-15) : `PreservedDataOutcome` entre dans
      `InstallReport`, `InstallReportSummary` gagne `dataRestored`/`dataFailed` (deux
      compteurs distincts — l'échec n'est pas un sous-cas de la réussite), et
      `InstallReportWindow` rend une section « Données de mod conservées » **avant**
      les deltas : ce qui touche aux parties sauvegardées passe avant les réglages.
      Un résultat muet ne prend pas de ligne. Les échecs **nomment les fichiers**
      (six au plus, le compte restant exact). L'en-tête s'enroule désormais au lieu
      de se tronquer — le pire cas FR fait ~1 100 px pour 520 de large, et les
      fragments de fin étaient précisément les nouveaux. · **livré**
      📐 **Cadrage écrit le 2026-09-14 : §8.4** — la règle proposée (*absent de
      l'archive neuve ⇒ donnée locale*), pourquoi elle ne rejoue pas le défaut
      d'`isAuthorLanguageFile`, le point dur prouvé (`FarmTypeManager/data/` mêle
      `default.json` livré et `*_SaveData.save` écrits) et trois options chiffrées.
      **En attente d'arbitrage.** · **M**



- [x] **A2-T7** — ✅ **Livré le 2026-09-15.** **Avertir quand un mod installé est sur la liste noire SMAPI.**
      *(source relevée le 2026-09-14 : SMAPI a bougé pour la première fois depuis le
      2026-07-01, et les huit commits ne portent ni le format du journal, ni le schéma de
      manifeste, ni l'installateur — ils alimentent `SMAPI.blacklist.json`.)*
      C'est la liste des mods **malveillants** bloqués par défaut, **distincte** de
      `metadata.json`/`mods.jsonc` qui portent les incompatibilités : ses messages disent
      « downloads malicious code from a remote server and runs it on your computer », et
      plusieurs entrées sont des **reuploads piégés de mods légitimes** — le cas que
      l'utilisateur ne peut pas distinguer à l'œil sur Nexus.
      **Mesures faites** : la ressource est servie publiquement
      (`https://smapi.io/SMAPI.blacklist.json`, HTTP 200, 5 029 octets), elle est du
      **JSONC** comme `mods.jsonc` — commentaires bloc **et** ligne, `ManifestJSON.decode`
      sait déjà les retirer — et elle est clée sur l'**`UniqueID`** du manifeste, la clé
      d'identité du parc. **9 entrées croisées contre les 1 112 manifestes du parc de
      référence : aucune correspondance**, le parc est sain.
      **Ce que ça ajoute vraiment** : SMAPI bloque déjà ces mods, mais **au lancement du
      jeu**, et il l'écrit dans un journal qui n'existe qu'après. StarHubFR peut le dire
      **avant**, au scan, sans lancer le jeu — c'est exactement ce que fait déjà
      `PathoschildCompatibilityList` pour la compatibilité, donc le patron est en place
      (dump public, cache hors-ligne, croisement par `UniqueID`).
      ⚠️ **Ce n'est pas un badge de plus.** Un mod malveillant ne se range pas à côté de
      « mise à jour disponible » : la destination doit être décidée (alerte système en
      tête, ou un état propre sur la fiche), et le texte doit dire quoi faire — le message
      de SMAPI demande de supprimer le mod **et** de lancer une analyse antivirus.
      ⚠️ **Ne jamais supprimer d'office** : le verdict vient d'une source externe, et
      `UniqueID` est déclaratif — un mod peut usurper celui d'un autre. On avertit.
      ✅ **Ce qui a été fait** : `SmapiBlacklist` (Core) lit le JSONC, croise le parc et
      monte les lignes ; `HealthIssue.Source.malicious` en `critical` (donc en tête de
      l'écran d'alertes, prouvé par test contre une ligne `info`) ; deux actions, la
      fiche puis « Montrer dans le Finder », **aucune suppression** ; bandeau rouge
      `MaliciousModBanner` au-dessus de tout sur la fiche. Source déclarée
      (`smapi/blacklist`) et documentée en `SOURCES.md` §2.2 bis.
      **Trois décisions** qui le séparent de la liste de compatibilité : le croisement
      **ignore la casse** (SMAPI aussi — sinon un reupload changeant une majuscule
      passerait pour sain) ; un document illisible rend `nil`, **jamais** une liste
      vide ; le `LooseFileBlacklist` est traité, le **nom** servant de grille de tri et
      seule l'**empreinte** condamnant.
      ⚠️ **Invisible sur un parc sain** — 0 correspondance sur 1 112 manifestes au
      2026-09-15. Pour le voir agir : renommer l'`UniqueID` d'un mod de test en
      `BritishW.ChaosWhispers` et relancer l'app. · **livré**



#### Hub de traduction FR — Axe C (suite)

- [x] **C5-T2** — ✅ **Livré le 2026-09-23.** Aligner README/CHANGELOG (la mention
      du hub thaï quitte le discours produit). Constat : les deux README ne le
      présentaient déjà plus ; restait l'attribution à l'amont (gardée : crédit
      légitime) et le CHANGELOG, dont les entrées historiques ne se réécrivent
      pas. Fait : les 5 bannières, chargées depuis le dépôt
      `stardew-thai-translations` d'AppleBoiy (MIT), vivent dans
      `assets/banners/` — plus de dépendance au dépôt thaï, et `build_app.py`
      ne les embarque pas ; la ligne du changelog intégré dit « deux dernières
      versions » ; A1-T6/T8 entrent dans les deux README.


- [x] **C2-T4** — Après mise à jour d'un mod, signaler les clés de config **et** de
      traduction ajoutées ou disparues (s'appuie sur les références par clé adoptées
      en C2-T2 — l'empreinte prévue n'a pas été retenue, cf. C2-T2). · **M**
      *(Livrée le 2026-09-08 : capture du delta dans la branche `.overwriteWithBackup`
      de l'installeur (`UpdateKeySnapshot`/`ModUpdateKeyDelta.compare`, seul instant où
      ancien et neuf coexistent), persistance par `UniqueID`, ligne à l'écran de succès,
      section « Dernière mise à jour » sur la fiche avec réconciliation des renommages
      (`KeyRenameMatcher` par valeur ou similarité, report via `RenameReport` — jamais
      d'écrasement d'un existant). Correctif embarqué : l'anglais du mod
      (`i18n/default.json`/`en.json`) ne se fige plus à la mise à jour. Commits
      `ac7e8e8`→`0200b38`.)*



- [x] **C4-T9** — **Un mod dont le métier est de remapper les touches n'est pas en
      conflit avec le jeu.** *(relevé le 2026-09-14 dans le changelog de
      ModernConfigMenu 2.1.1, qui a ajouté `IsVanillaControlRemapMod()` pour la même
      raison — et qui nomme en exemple un mod **actif sur notre parc**.)*
      `KeybindScanner` classe en `gameConflicts` tout raccourci de mod qui retombe sur
      un contrôle du jeu. Pour un mod de remap, c'est **sa fonction** : le signaler est
      un faux positif, et il gonfle le seul chiffre que l'écran donne (`problemCount`).
      **Mesuré** : `Global Config Settings Rewrite` est **installé et actif** — c'est
      exactement le mod que leur changelog cite.
      ⚠️ **Ce que nous faisons déjà mieux, vérifié, et qu'il ne faut pas « corriger »** :
      leurs deux autres correctifs de la même version ne nous concernent pas.
      `KeybindCombo` est `Hashable` sur `Array(Set(buttons)).sorted()` — la
      **combinaison entière normalisée**, là où ils regroupaient sur `Buttons[0]` et
      voyaient `Shift+F` entrer en conflit avec `Shift+J`. Et `SButtonTable` distingue
      déjà `LeftShift`/`RightShift`/`LeftControl`/`RightControl`/`LeftAlt` (codes
      160-165), la différenciation qu'ils ont dû ajouter.
      ⚠️ **La reconnaissance d'un mod de remap est le vrai sujet, et elle se mesure** :
      leur `IsVanillaControlRemapMod()` repose sur une liste de mods connus. Une
      heuristique sur le nom écarterait des mods légitimes (trois candidats trouvés au
      mot « remap » sur le parc, **deux sont des cartes**). Trancher sur données avant
      de coder. · **S**
      **Livré** le 2026-09-15, tranché sur données (sonde sur le parc réel,
      grammaire réelle, puis sonde supprimée) : 16 lignes de conflit jeu sur
      12 mods, dont **un seul faux positif** — GCSR (`ShiftToolbar` sur
      toolbarSwap). Reconnaissance retenue : liste d'UniqueID
      (`vanillaRemapModIds`, comparaison sans la casse, comme SMAPI), le
      même choix que MCM — la liste démarre de notre mesure.
      **Source MCM relue le jour même** (décompilation `ikdasm` de la DLL
      2.1.2 installée) : leur « liste de mods connus » n'en est pas une —
      `IsVanillaControlRemapMod` teste trois **sous-chaînes** sans la casse
      (`GlobalConfigSettings` dans l'UniqueID, `Global Config Settings` dans
      le nom, `GameControls` dans l'UniqueID). Passées sur le parc, ces
      motifs n'attrapent que GCSR : équivalent à notre liste, et notre liste
      ne peut pas écarter un mod légitime par accident — l'exact opposé de
      l'heuristique que la roadmap refusait. L'exclusion ne touche que les **conflits
      jeu** : les collisions mod-mod du remap restent (Tab partagé GCSR +
      Chests Anywhere est un vrai double consommateur), le compte de
      liaisons aussi, et la note du rapport nomme le mod écarté
      (`remapModsIgnored`, miroir de la note catalogue).



- [x] **C4-T10** — **L'éditeur de config rend les raccourcis en champ texte libre,
      alors que le scanner sait déjà les reconnaître.** *(relevé le 2026-09-14 en
      auditant le design de ModernConfigMenu — §3 quinquies de l'archive ; leur
      `KeybindOverviewModal` est la seule de leurs idées que le parc justifie.)*
      **Le fait d'architecture** : `KeybindScanner.report`
      (`StarHubTH/Models/KeybindScanner.swift:336`) et `ConfigEditorModel.groups`
      (`StarHubTH/Models/ConfigEditorModel.swift:284`) parcourent **le même**
      `ConfigEditorModel.leaves(of: tree)`. Le scanner classe chaque feuille par
      `classify(leaf:)` ; l'éditeur, sur la feuille identique, en fait un `.text`.
      Il n'y a pas de plomberie à construire : la classification existe déjà, et
      elle prend exactement le type que l'éditeur tient en main.
      **Le point d'insertion est nommé** : `ConfigEditorModel.row(for:describedBy:
      orLabeledBy:)` (`:300`) tient la `Leaf` entière et **surcharge déjà le
      contrôle une fois** — pour `choiceControl(for:option:)`. Une branche keybind
      s'y pose de la même forme. ⚠️ Ce qui n'est pas gratuit, en revanche :
      `KeybindScanner` dépend de `ConfigEditorModel.Leaf`, donc appeler `classify`
      depuis `ConfigEditorModel` referme un cycle au niveau des types. Sans
      conséquence dans un module unique, mais à trancher volontairement — la
      grammaire aurait peut-être sa place dans `KeybindGrammar.swift`.
      **Mesuré sur le parc** (port fidèle de `KeybindParser` + `classify` ; 614
      `config.json`, 16 552 feuilles, 15 fichiers illisibles) : **466 feuilles sont
      des raccourcis, réparties sur 146 mods** — 348 par indice de nom
      (`key|bind|shortcut`) et **118 par combinaison distinctive sans indice**
      (`.Automate: Controls.ToggleOverlay`, `Stillbloom: MultiSelectModifier`).
      **Les 466 sont des chaînes, donc toutes rendues en `.text`** ; seules 3 vivent
      dans un pack à `content.json` où un schéma pourrait déjà en faire une liste.
      Zéro `unrecognized` sur tout le parc.
      ⚠️ **Un comptage antérieur disait 315** : il approximait en Python la seule
      branche à indice de nom et manquait les 118 autres. Mesurer avec la grammaire
      réelle, jamais avec une regex de substitution.
      ⚠️ **L'aller-retour d'écriture est le piège** : le contrôle doit réécrire
      l'orthographe que le mod attend, pas une forme canonique. Le parc porte
      `'D0'`, `'None'`, `'LeftShift'`, `'Up'` — normaliser `D0` en `0` écrirait
      autre chose que ce que l'auteur a posé. Le précédent est déjà dans le modèle :
      `Control.toggle(Bool, asString:)` mémorise si `true` était un booléen ou la
      chaîne `"true"`, et `ConfigEditorModel.value(of:)` le restitue. Un `.keybind`
      doit porter la même mémoire.
      ⚠️ **Ne pas suivre `classify` seule pour décider d'afficher le contrôle** : la
      règle R4 du scanner (`KeybindScanner.swift:277`) existe parce que
      `ModShortcutReferenceHub` **documente** les raccourcis des autres — chaque
      feuille de son catalogue passe `classify`, et aucune n'est liée à quoi que ce
      soit. Un sélecteur de touche posé dessus serait un faux positif visible.
      **Sans casser l'existant** : le contrôle naît dans `ConfigEditorModel.Control`
      (type Core, donc testable), et l'écriture continue de passer par
      `ModConfigWriteGuard`. · **M**
      **Livré** le 2026-09-15 : `Control.keybind(raw:combo:)` porte l'orthographe
      d'origine (`'D0'`, `'leftshift'`) et la restitue telle quelle tant qu'on
      n'a pas touché — prouvé par sabotage, la forme canonique d'un `D0` étant
      justement `D0` (le premier test ne voyait rien). La règle R4 devient
      partagée (`KeybindScanner.catalogShapes`), le schéma garde la priorité,
      les listes à plusieurs combinaisons restent en champ texte, et une valeur
      numérique garde son champ chiffré. Le cycle de types éditeur↔scanner est
      assumé et documenté (module unique). Capture : `ModKeybindField` — Échap
      annule, un modificateur seul n'engage rien (son `keyDown` précède celui
      de la touche modifiée), et les touches hors table `MacKeyCodeMap` sont
      avalées sans rien casser.
      **Corrigé à l'écran le jour même** : une capture posant un caractère
      unique (`A`, `O`) ou vide (`None`) repassait la règle R2 du scanner au
      re-rendu — le contrôle redevenait un champ texte sous les yeux de
      l'utilisateur (un chiffre, distinctif, passait ; pas une lettre).
      `groups(of:…, stickyKeybinds:)` : la session mémorise les rangées
      capturées et la re-classification les respecte ; l'intention explicite
      bat aussi l'heuristique du catalogue. À la réouverture, la grammaire
      re-tranche (une valeur `A` non hintée y reste un champ texte).
      **AZERTY, affiché le jour même** : les `SButton` nomment des
      **positions physiques US** (wiki Stardew, FNA#121) — presser la touche
      A d'un AZERTY enregistre `Q`, et c'est bien cette touche que le mod
      écoutera ; écrire le keycap lierait la mauvaise touche. Affichage
      retenu après retour de l'auteur (« l'utilisateur ne doit pas être
      désorienté ») : **ta touche d'abord, le nom enregistré ensuite, en
      discret** — « a · Q » — traduit depuis la disposition clavier
      **courante** par `UCKeyTranslate` (`MacKeyLayout`), donc vrai aussi à
      la réouverture, pas seulement juste après la capture. Silencieux quand
      la gravure coïncide (QWERTY) ou n'apprend rien (`D1` contre `1`,
      touches sans gravure). L'info-bulle dit la convention : minuscule = ta
      touche, majuscule = le nom du fichier.
      **L'annotation « lié à » livrée le jour même** (reproduction de
      l'affichage de conflits de leur `KeybindOverviewModal` — décompilé) :
      sous une rangée raccourci, « Conflit avec {mod} ({réglage}) » ou
      « un contrôle du jeu ({contrôle}) ». Leur logique — signatures
      canoniques, première collision trouvée, conflit jeu prioritaire —
      existe déjà chez nous en plus riche : l'annotation lit le rapport
      (`KeybindScanner.annotation`), hérite des exclusions catalogue (R4)
      et remap (C4-T9), et distingue manette.



- [x] **C4-T11** — **Les listes déroulantes que les DLL C# déclarent par
      leurs types.** *(relevé le 2026-09-15 par l'auteur : Stillbloom
      « Placement rule » — Strict/Loose/Anarchy — rendu en champ texte
      alors que MCM, en jeu, connaît les valeurs et les bornes.)*
      **Livré** le 2026-09-15, en deux temps. Le relevé d'abord
      (`tools/gmcm_options.py` → `assets/gmcm-options.json`), corrigé le
      jour même : le filtre de pertinence — une propriété n'est un choix
      que si sa clé existe dans le config.json du mod — est passé de 122
      mods/588 champs (dont les enums internes des libs embarquées, cas
      AccordSettings) à **33 mods/63 champs**, 33/33 cohérents avec les
      valeurs réelles des configs. Puis **la lecture live dans l'app**
      (question de l'auteur : « que se passe-t-il pour un nouveau mod ou
      si une mise à jour ajoute des options ? ») : `DotNetMetadata` +
      `DotNetAssemblyOptions` relisent les tables à l'ouverture de
      l'éditeur, cache par empreinte de DLL, nouveaux mods et mises à
      jour couverts sans release ; le tool devient l'oracle (122 comparés
      sur le parc, 0 écart) et le dataset figé le filet. Variance du
      format mesurée avant écriture (455 DLL), fixture produite par le
      vrai producteur (`dotnet build`) avec les pièges du format, chaque
      garde prouvé par sabotage — deux ne s'observaient que par tests
      directs. Restes notés en SOURCES.md §6 bis : les listes en
      littéraux d'API (`SetAllowedValues`), les **min/max** des nombres,
      la convention tooltip « Valeur = description » (2 champs sur 226
      mods — précise, sans couverture).

- [x] **C4-T12** — ✅ **Livré le 2026-09-24.** **Le signal de conflit pendant la capture, pas seulement
      après.** *(**livrée** le 2026-09-24 : l'annotation « lié à » cherche dans
      toutes les liaisons actives (`KeybindReport.activeUses`), plus seulement
      dans les collisions — une touche fraîchement capturée qui ne recoupe
      qu'une liaison d'un autre mod est nommée dès la pression ; l'éditeur
      relisait déjà la valeur capturée. Même mod exclu, comme le rapport ;
      l'effacement existait déjà (`[×]`). Idée gardée de l'audit [Keybind Radar & SaveSaver](audit-keybind-radar-savesaver.md)
      §1, 2026-09-23 : l'overlay « This key is already in use » de Keybind Radar
      s'affiche pendant la saisie, pas après coup — l'annotation « lié à »
      livrée ci-dessus ne parle qu'à la relecture.)* Sous `ModKeybindField`,
      pendant une capture, si le combo pressé correspond à une autre liaison,
      signal immédiat sous le champ ; le rapport `KeybindScanner` et ses
      signatures canoniques existent déjà, l'annotation reste le bilan après
      coup.
      ⚠️ **Comparer sur les signatures canoniques, pas sur les touches
      pressées** : la capture est clavier (`MacKeyCodeMap`), mais le parc va
      porter des `MouseX1`/`MouseX2` (MCM 2.1.3, SOURCES §6) et des boutons
      manette — dire s'il y a conflit est une question de sémantique de
      signature, pas de ressemblance de jeton.
      ⚠️ **L'affordance d'effacement peut voyager avec** (MCM 2.1.6, journal
      lu le 2026-09-23) : leur bouton `[×]` et « clic droit / ⌫ pour vider »
      pendant l'écoute — notre capture a Échap (annule) mais aucun chemin
      explicite vers « None ».
      ⚠️ **Keybind Radar 1.0.1 (lu le 2026-09-24) étend son signal en direct
      aux liaisons manette** : le besoin couvre donc aussi les boutons de
      manette, ce qui confirme la comparaison par signature canonique. · **S**

- [x] **C4-T14** — ✅ **Livré le 2026-09-24.** **Les libellés par valeur
      d'une liste déroulante.** *(trouvé le 2026-09-24 en décompilant
      Radiance 2.2.0 — SOURCES §5.)* Chaque entrée d'un menu de l'éditeur de
      config montre le libellé que le mod publie, la valeur écrite restant
      celle du fichier. Deux conventions : `config.<clé>.values.<valeur>`
      (Content Patcher, reprise par les mods Pathoschild) lue par
      `ContentPackI18n` dans `ConfigSchemaOption.valueLabels`, et
      `config.<clé>.<valeur>` (mods C#) gardée par `ConfigLabelResolver`
      dans `Labels.values`. La rangée (`Row.choiceLabels`) ne cherche que
      les entrées du menu : un suffixe qui n'est pas une valeur admise ne
      s'affiche jamais, et une valeur homonyme d'un suffixe connu (`Title`)
      reste brute.
      📏 **La règle mesurée avant d'être codée.** La mesure grossière
      (20 mods C#, 37 champs) visait le mauvais chemin : côté C#, seuls
      **5 champs sur 3 mods** (Chests Anywhere `Range`, MH Event List ×3,
      Radiance `SheetUpscaleStyle`) ont une tige égale à la clé **et** des
      suffixes égaux aux valeurs de l'enum — 14 valeurs, 0 faux. Le gros du
      gain est côté packs CP, que la mesure initiale excluait : **617 des
      1227 listes** du parc portent la convention `.values.` (1861 valeurs
      sur 1875), **59 packs** en français.
      **Restes mesurés, non traités.** Rapprochement par ensemble de
      valeurs (tige libre, p. ex. Radiance `camera.mode` ↔ `CameraMode`) :
      6 champs de plus, 2 ambigus (`shadows.model`/`water.model` ↔ deux
      enums `{Classic, Modern}`) — il toucherait au plafond structurel du
      resolver. Les listes en littéraux d'API (`SetAllowedValues` :
      StardewDashboard, TreeAndBush, AutomateToolSwap… ~12 valeurs) n'ont
      pas de menu (SOURCES §6 bis). Les mods Pathoschild écrivent des
      tiges et valeurs en kebab-case (`skip-to.values.title-menu` pour
      `SkipTo = Title`) : hors d'atteinte sans règle propre. · **S**



#### Expérience utilisateur : navigation & accessibilité — Axe I (suite)


- [x] **I-T1** ✅ *(partie raccourcis livrée le 2026-09-09)* — **⌘1…⌘9** mènent
      aux neuf premières destinations visibles, et un **menu « Aller »** les
      affiche : les raccourcis deviennent découvrables et macOS les gère
      nativement. `SidebarOrder` (Core, 15 destinations, 11 tests) est la
      source unique que lisent la barre latérale, le menu et la palette —
      la barre a cessé d'écrire ses 14 entrées à la main.
      ⚠️ **Le second membre de I-T1 reste ouvert** : la navigation au focus
      des 14 écrans (entrer/sortir des fiches, des feuilles, de la liste).
      Elle traverse toute l'app, vaut **L**, et demande une **mesure d'abord** :
      quels écrans piègent réellement le clavier aujourd'hui. La deviner écran
      par écran ferait un lot qui ne se termine pas. → repris en **I-T6**.


- [x] **I-T2** ✅ *(livré le 2026-09-09)* — **Palette ⌘K** : mods, profils,
      sauvegardes et pages, recherche tolérante (sous-séquence, accents
      ignorés) et classée de façon déterministe (`CommandPaletteSearch`, Core,
      18 tests). Mesurée à **4,5 ms** par frappe sur 1 000 entrées et 0,7 ms à
      l'ouverture, sous le seuil des 16 ms — aucune indexation nécessaire.
      **Écart assumé avec l'intitulé d'origine** : la palette **navigue
      seulement**. Les actions qui écrivent (installer, mettre à jour,
      restaurer) en sont exclues — tranché avec l'auteur : une frappe rapide
      ne doit pas pouvoir écrire dans `Mods/`. Et elle conduit à l'**onglet**
      des profils et des sauvegardes, pas à l'élément précis : aucun canal
      n'existe pour ça, et en ajouter deux pour un besoin non mesuré est ce
      que ce dépôt regrette ailleurs.


#### Axe F — Dette technique (suite)


- [x] **F3** — **Latence de frappe dans la recherche de la liste des mods.** Rapportée par
      l'auteur le 2026-08-01 : un délai perceptible entre deux lettres, sur sa modlist
      réelle (822 dossiers de premier niveau, 918 manifests).
      ▸ **Livrée le 2026-09-12** (`fd6f0d08`, vérifiée à l'écran par l'auteur le jour
      même) — le délai ne venait ni du filtrage ni de la conversion `@Observable` :
      l'A/B des trois témoins a tranché « défaut préexistant » (gênant sur les trois),
      puis la capture Instruments a nommé `ModItem.inferTag` **relancé par frappe**
      (deux passes pleines de la base + les badges de lignes, ~150 regexes par mod,
      sans mémoïsation — ~0,7 s de fil principal bloqué par lettre). Le tag se calcule
      maintenant **une fois à l'init** de `ModItem` et `inferredTagKey` lit la valeur
      stockée ; la règle du pack (tag du composant de tête) est préservée et prouvée
      par test. Arbitrage révisé par l'auteur le jour même : correctif immédiat pour
      la mémoïsation seule. **Les constats accumulés ci-dessous (`healthIssues`, le
      lot de traduction à 3,2 s) restent ouverts dans le seau de la passe groupée** —
      la case fermée ne les emporte pas.
      **Déjà mesuré, et écarté — ne pas y revenir** :
  - le filtrage (`filteredMods`) coûte **~2 à 5 ms par frappe** à cette échelle ;
  - le tri **0,04 ms**, y compris le cas `.name` dont la closure renvoie toujours `false` ;
  - un index de recherche pré-minusculé (au lieu de `localizedCaseInsensitiveContains`)
        ferait gagner ~2 ms : sans rapport avec l'ordre de grandeur perçu.
      **Piste restante** : le **rendu**, pas le calcul — chaque frappe reconstruit les 15
      lignes de la page avec leurs images, badges, interrupteurs et boutons. Noter qu'un
      debounce de 200 ms a été retiré en 1.7.0 *parce qu'il aggravait* le lag perçu ; le
      remettre suppose un réglage différent, pas un retour en arrière.
      **⚠️ Le terrain a changé le 2026-09-11** — à lire avant de rouvrir cette
      tâche. La « piste restante » ci-dessus (le **rendu**) est exactement ce que
      le chantier A du refactor a touché : le VM et trois stores sont passés
      `@Observable`, donc une vue ne se réinvalide plus que sur les propriétés
      qu'elle **lit**, là où chaque `@Published` publiait à toute la fenêtre.
      Deux conséquences pour la passe : le gain attendu n'a **pas** été mesuré
      (c'est ce qui reste dû), et l'A/B a désormais **deux** témoins — le bundle
      v1.11.1 pour la question régression/préexistant, et le tag
      `pre-refactor-observable` (`e1bb12f`) pour l'effet de la conversion seule.
      Les mesurer ensemble évite de confondre les deux réponses.
      → `docs/refactoring-vider-le-viewmodel.md` §5 bis et §9.
      **Non tranché : régression ou défaut préexistant.** `bundles/StarHubFR_v1.11.1.zip`
      est la version d'avant B1-T2 et sert de témoin pour un A/B — première étape de la
      passe, avant d'écrire quoi que ce soit : les deux réponses mènent à des travaux
      opposés.
      ▸ **Témoins produits (2026-09-12)** — les trois zips de l'A/B sont dans
      `bundles/`, chacun bâti par le gate de son commit (exit 0) :
      `StarHubFR_v1.11.1.zip` (tag `v1.11.1`, `8a48b518` — identité pré-F5
      `com.appleboiy.StarHubTH`), `StarHubFR_pre-refactor-observable.zip`
      (`e1bb12f`) et `StarHubFR_post-refactor-46fe7bf6.zip` (tête actuelle).
      Les deux derniers partagent identité (`com.mrbabilo.StarHubFR`) et numéro
      (1.43.1) : ne pas les départager à l'À propos, mais au dossier d'où chacun
      est lancé. Recette : extraire chaque zip dans son propre dossier, quitter
      complètement (Cmd+Q) entre deux builds, taper la même requête lettre à
      lettre sur le parc réel, noter la sensation par build, consigner le verdict
      ici puis fermer ou instruire la case. ⚠️ v1.11.1 relit le domaine d'avant
      F5 : premier lancement = re-scan et recréation de l'ancien dossier
      AppSupport (supprimé par X105) — test en lecture seule, aucune écriture
      (installation, bascule, backup) depuis ce build.
      ▸ **Verdict de l'A/B (2026-09-12, auteur)** — **gênant sur les trois** :
      les builds essayés furent v1.41.1 (le zip déjà présent, identité pré-F5 —
      le v1.11.1 rebâti n'a pas servi), `pre-refactor-observable` et la tête
      actuelle ; trois binaires distincts vérifiés au md5, tous laguent pareil. La
      question est tranchée : **défaut préexistant**, aucune régression à ouvrir —
      et le gain de la conversion `@Observable` sur la frappe est nul (le risque
      « gain de réactivité nul » du cadrage §7 s'est réalisé). La piste restante
      est le **rendu**, et elle vaut pour deux UI — v1.11.1 est d'avant la refonte
      d'août — : chercher ce que les deux reconstructions de page partagent par
      frappe. Instruction avant d'écrire quoi que ce soit : une capture
      Instruments pendant la frappe (`xctrace`, template `SwiftUI`), pour nommer
      où va le temps au lieu de le déduire du code. La case reste dans le seau de
      la passe groupée (arbitrage du 2026-08-01).
      ▸ **Capture Instruments analysée (2026-09-12)** — trace `SwiftUI` 45 s sur
      le témoin v1.41.1 pendant la frappe : 23 gels du fil principal — un Severe
      Hang de 2,3 s, quinze de 0,5 à 1,0 s — soit **~0,7 s de fil principal
      bloqué par lettre** (17,6 s de fil occupé sur la fenêtre, contre 1,5 s pour
      tout le démarrage). Attribution : **27 % du temps occupé (4,7 s) dans
      `ModItem.inferTag`/`inferredTagKey`** — la chaîne
      `Regex.firstMatch → Processor.atSimpleBoundary → matchesWord` du moteur
      Unicode. Mécanisme : chaque frappe relance `inferredTagBuckets` et
      `uncategorizedCount` (`ModListView`) sur toute la base, chacun appelle
      `inferredTagKey` **par mod**, et `inferTag` enchaîne ~150 regexes
      `\bmot\b` sur `name + uniqueId + description` **sans mémoïsation** — les
      badges `InferredTagBadge` repassent une troisième fois sur les lignes
      visibles. La mesure « filtrage 2–5 ms » de cette case ne voyait pas ce
      chemin : il vit dans la couche vue, pas dans `filteredMods`. Le même code
      est vérifié présent à la tête (mêmes fonctions, mêmes appels). Remède
      candidat : le tag d'un mod ne dépend pas du texte cherché — le mémoïser
      (calcul à l'init de `ModItem`, pure logique Core, testable) fait tomber la
      répétition par frappe ; il restera le rendu proprement dit des 15 lignes.
      **Constat accumulé (audit du 2026-09-02), à joindre à la passe groupée** — autre
      sujet, même seau : `healthIssues` (`StarHubTHViewModel.swift:379`, `@MainActor`
      computed) est recalculé à chaque accès — aplatissement des ~966 mods, `Set`,
      résolution complète — et lu plusieurs fois par rendu (`systemAlertCount`,
      `activeConflictCount`, écran d'alertes, accueil). Chaque tick de `scanProgress`
      (publié **par mod** pendant un scan — ⚠️ **périmé** : throttlé à ~12/s et
      publié sur main depuis `87de592`, voir tranche perf & concurrence de F2) fait réévaluer les corps observateurs : ~un
      recalcul complet par mod scanné, soit ~966 par passe. Coût unitaire faible
      (microsecondes), mais c'est le patron exact qui a beach-ballé les journaux (voir
      Traps, `List` → `LazyVStack`). **Mesurer avant d'agir** ; une mémoïsation sur
      signature d'entrées (`mods`, verdicts de conflits, conflits Content Patcher,
      diagnostics SMAPI) garderait la source unique intacte.
      **Second constat accumulé (audit `Models/` du 2026-09-03), même seau** :
      `exportTranslationLot` et `importTranslationLot` restent `@MainActor` sans tâche
      détachée ni progression. L'appariement du glossaire, qui coûtait 149 s, est corrigé
      (`dc052a6`) ; il reste **3,2 s de fil principal nu** sur le plus gros mod à traduire
      du parc (16 482 clés sans français), l'import autant puisqu'il reconstruit le même
      lot. Une barre de progression suppose de sortir le calcul du fil principal : même
      geste que le reste du seau, à faire d'un bloc.
      **Constat accumulé (audit du 2026-09-03), à joindre à la passe groupée** —
      `exportTranslationLot` et `importTranslationLot`
      (`StarHubTHViewModel.swift`) sont `@MainActor` et appellent
      `TranslationLot.build` **sans tâche détachée ni progression**. L'appariement
      du glossaire, lui, est corrigé (index par premier mot, 9,04 ms → 0,195 ms par
      valeur, `dc052a6`) : le gel du pire mod du parc — 16 482 clés sans français —
      tombe de **149 s à 3,2 s**. Ces 3,2 s restants sont du fil principal nu, sans
      un mot à l'écran. Le correctif tient en une `Task.detached` plus un état de
      progression ; il n'a pas été fait au fil de l'eau, conformément à l'arbitrage
      ci-dessous.
      **Arbitrage de l'auteur (2026-08-01) : traiter dans une passe de performance
      groupée, en fin de projet** — pas au fil de l'eau. Ne pas rouvrir isolément ; y
      joindre les autres constats de perf accumulés d'ici là. · **M**


- [x] **F5-T1** — ✅ **livré le 2026-09-10** (commits `8724fb9`..`4deb794`).
      Les données de fichiers vivent sous `~/Library/Application Support/StarHubFR/`
      derrière l'accesseur unique `AppSupport` — quatorze sites branchés, sept
      stores de plus que les six prévus par le plan. Migration **reprenable**
      (entrée par entrée, ce qui est déjà arrivé n'est jamais écrasé),
      déclenchée par un `static let` : aucun point de lancement n'est assez
      tôt, le ViewModel lit deux stores dans ses initialisateurs de
      propriétés. `Backups/` reste derrière, délibérément. Validée sur
      machine : dossier déplacé au premier accès, `StarHubTH/` ne garde que
      `Backups/`, le registre ne porte plus aucun chemin absolu.


- [x] **F5-T2** — ✅ **livré le 2026-09-10** (`8c54ba6`, `07ca257`, `5c5ea4e`).
      Identifiant `com.mrbabilo.StarHubFR` — et le `CFBundleURLName` du schéma
      `nxm`, qui ne change pas lui-même. Les 45 clés possédées (re-mesurées sur
      le domaine réel du 2026-09-10 : le plan en comptait 31, neuf sont nées
      depuis) sont recopiées au premier lancement, **jamais écrasées** ; le
      Trousseau passe au nouveau service avec lecture de secours unique sur
      l'ancien, qui reste en place pour l'application d'origine. Vérification
      machine restante : `defaults read com.mrbabilo.StarHubFR gameDir`, la clé
      Nexus reconnue, et un « Mod Manager Download » Nexus qui ouvre StarHubFR.


- [x] **F7** ✅ *(livré le 2026-09-09)* — **L'onglet courant était une chaîne, et
      rien ne garantissait qu'elle désigne une page.** `currentTab` était un
      `String`, et la répartition du contenu de `MainView` une **chaîne de
      `if / else if` sur des littéraux** — pas un `switch`. Une faute de frappe
      ne cassait pas la compilation : elle rendait une **page blanche, en
      silence**. Le dépôt avait pourtant déjà tranché l'inverse ailleurs, avec
      le `switch` exhaustif de `sectionView` (`SettingsSectionOrder`, H-T7).
      **Livré** : `SidebarDestination` (Core, 15 cas, `rawValue` reprenant les
      anciennes chaînes) ; `MainView` switche exhaustivement pour la
      répartition **et** pour le titre de fenêtre, sans `default:` ;
      `HomeAttention.Kind.tab` — deuxième endroit qui écrivait ces
      identifiants à la main, en Core — est typé lui aussi.
      **Le garde-fou est vérifié, pas supposé** : une 16ᵉ destination ajoutée
      sans page fait échouer le build (`error: switch must be exhaustive`).
      10 fichiers, 2 500 tests verts, un compteur du cliquet en baisse.
      **Relevé pendant la relecture critique de I-T1/I-T2, puis fait *avant*
      le lot** : la spec y crée `SidebarOrder`, une table Core de ces mêmes
      identifiants alimentant trois nouveaux écrivains (⌘1…⌘9, palette,
      menus) — la garder en `String` aurait écrit les identifiants une
      deuxième fois et *augmenté* la surface de page blanche.


#### 10.3 Veille RimManager (suite)


#### Cohérence UI : un seul langage — Axe H (les cinq derniers corps)


- [x] **H-T5e** — ✅ **Livré et vérifié à l'écran le 2026-09-09.** **Vignette illustrée pour une ferme de mod.**
      Depuis que `SaveFarmType` reconnaît une ferme de mod (`whichFarm = -1`,
      cas `FrontierFarm`), sa vignette sort de la plage 0-7 des illustrations
      et affiche un glyphe `house.fill` sur fond neutre. C'est honnête — on
      n'a pas l'illustration — mais à côté des sept tuiles illustrées, la case
      se lit comme « celle qui manque ».
      Une neuvième image générique « ferme personnalisée », découpée au même
      format que les autres (190×200, `assets/custom_ui/farm_glyph_mod.png`),
      la ferait rentrer dans le rang. `SaveFarmGlyph` la chargerait avant de
      retomber sur le SF Symbol, qui reste le filet.
      Vérifié à l'écran le 2026-09-02 : le repli actuel est acceptable, ce
      n'est pas un défaut à corriger en urgence. · **XS**
      ✅ **L'auteur a fourni l'illustration le 2026-09-09** (« Ferme
      frontière »), et elle est en place. **Traitement mesuré, pas estimé** :
      la source faisait 1254×1254 avec un cartouche titré ; un profil de
      luminance ligne par ligne a situé la bordure crème à 20 px et le début du
      cartouche à y≈1108 — les sept vignettes du dépôt n'ont ni cadre ni titre.
      Recadrée sur l'illustration seule au ratio 190:200, décalée de 40 px vers
      la gauche pour garder la ferme entière (elle occupe x≈80…570 ; un
      centrage strict l'aurait collée au bord), puis rendue en 190×200 —
      **le format exact des sept autres, vérifié par `sips`**.
      `SaveFarmGlyph.resourceName(_:)` route tout `whichFarm` hors 0-7 vers
      `farm_glyph_mod`. Le SF Symbol **reste** le filet si la resource manque
      du bundle : le repli n'est pas supprimé, il recule d'un cran.
      > **À vérifier à l'écran (H-T5e)** — 1. Écran Sauvegardes, une partie sur
      > ferme de mod (le parc en a une : `FrontierFarm`) : la vignette illustrée
      > remplace le glyphe, et se lit comme les sept autres à 80×56.
      > 2. Les huit fermes vanilla n'ont **pas** changé d'image — la bascule ne
      > vaut que hors 0-7. 3. Le cadrage tient à la taille d'affichage réelle :
      > la ferme reste lisible, elle n'est pas coupée par le remplissage
      > couvrant (`aspectRatio(.fill)` rogne les bords longs).
      >
      > ✅ **Les trois points sont passés** (vérification de l'auteur,
      > 2026-09-09) : le cadrage tient à 80×56 malgré le remplissage couvrant,
      > et les huit fermes vanilla sont inchangées.



- [x] **H-T5c** — ⛔️ **Abandonné le 2026-09-09** *(décision de l'auteur, §8.3 — la case est cochée parce que l'item est clos, pas parce qu'il est fait ; même convention que `X59` et `C4-T8`)*. **Portrait du fermier fidèle à la sauvegarde.** L'avatar du hero
      est aujourd'hui une illustration fixe par sexe ; `<hair>`, `<hairstyleColor>`
      et `<skin>` sont lues et correctes mais ne pilotent aucun pixel. Recomposer
      la tête (base + calques coiffure/peau) plutôt que teinter un crop.
      ~~Prérequis : des calques séparés, que l'affiche du jeu ne fournit pas.~~ · ~~**M**~~
      ⚠️ **Le prérequis est faux — réfuté le 2026-09-09.** Il est vrai de
      l'*affiche* et faux du **jeu installé** :
      `Stardew Valley.app/Contents/Resources/Content/Characters/Farmer/` porte
      les calques séparés, lus octet par octet et non déduits du nom —
      `farmer_base.xnb` et `farmer_girl_base.xnb` (18 Ko, drapeau `0x81` :
      **compressés LZX**), `hairstyles.xnb` (11 Ko) et `hairstyles2.xnb`
      (6,7 Ko, LZX aussi), `skinColors.xnb` (**non compressé** — son
      `Microsoft.Xna.Framework.Content.Texture2DReader` se lit en clair dans
      l'en-tête), plus `accessories`, `hats`, `shirts`, `pants`. Et la
      décompression LZX **existe déjà** dans le dépôt (`LzxdDecoder`,
      `LzxdBitstream`, `LzxdWindow`, `LzxdTree`, plus
      `XnbStringDictionaryReader.decompressLZX`).
      **Ce qui manque vraiment**, et que le prérequis aurait dû nommer : un
      lecteur de **`Texture2D`** — le travail XNB du dépôt lit des
      *dictionnaires de chaînes*, jamais des pixels (format de surface,
      dimensions, niveaux de mip, données RGBA) ; la correspondance entre
      l'index `<hair>` d'une sauvegarde et sa région dans
      `hairstyles`/`hairstyles2` ; et les règles de composition (ordre des
      calques, teinte de `<hairstyleColor>`, palette de `skinColors`).
      **Jamais tenté** : `git log -S` ne rend rien sur `farmer_base`,
      `Texture2D` ni `hairstyles`.
      ⛔️ **Abandonné le 2026-09-09, par décision de l'auteur** *(§8.3 —
      l'item est fermé, pas déplacé)*. Ce qui suit dit pourquoi, et ce que la
      réfutation ci-dessus vaut si la question revient un jour.
      **Ce n'est pas un lot de l'axe H.**
      La spec §9 pose « **aucune fonctionnalité nouvelle** : la refonte
      déplace, renomme et restyle ». Un lecteur de textures, un index de
      sprites et un compositeur de calques sont une **capacité neuve** — le
      plus gros morceau de code neuf jamais proposé dans cet axe, et la taille
      **M** était estimée en supposant les calques absents. L'auteur a tranché
      l'abandon : l'avatar garde son illustration fixe par sexe. **Ne pas
      rouvrir sans décision explicite** — et si la question revient, partir de
      la mesure ci-dessus plutôt que du prérequis, qui était faux.


- [x] **H-T7** — ✅ **Livré le 2026-09-09, en deux lots.** **Lots Journaux & Réglages** : reskin léger des journaux
      (la perf est déjà faite), Réglages absorbe les déménagés de l'accueil
      en sections unifiées. Deux releases — phases 5 et 6 de la spec. · **S**
      ▸ **Cadré et mesuré le 2026-09-09** — plan
      `docs/superpowers/plans/2026-09-09-lots-journaux-reglages-h-t7.md` (local,
      gitignoré) ; les faits qui engagent sont ici :
      **Ligne de base** — `LogsView` (706 l.) : **26** tailles de police
      littérales, zéro token, zéro composant partagé. `SettingsView` (977 l.) :
      **53** littérales, zéro token, `StandardSection` ×13. Cible du critère
      §10 n°1 : **0** des deux côtés.
      **Le système n'a aucun token monospace** — et le dépôt en porte déjà deux
      formes divergentes (`design: .monospaced` dans `BisectionCard`,
      `.monospaced()` dans `ModUpdateDeltaSection`). Le châssis H-T1 les avait
      extraits de `DiscoverView`, qui n'affiche aucun texte monospacé ; les
      journaux le sont par nature.
      ⚠️ **Ce qui est testable et ce qui ne l'est pas** : `Package.swift` ne
      compile de tout le système de design que `AppDesignCore.swift` (l.129).
      **`AppDesign.Font`/`Color` vit hors SPM** — une *taille* (`CGFloat`) se
      teste, une *police* SwiftUI ne se teste pas dans ce dépôt. Un test qui
      importerait `StarHubTHCore` pour lire `AppDesign.Font.…` ne compilerait
      pas. Choix ancien et délibéré (cf. `.kilo/plans/…ux-ui-spec…`, décision
      D1) — ne pas le « corriger » en chemin.
      **Défaut d'accessibilité trouvé au cadrage** : `LogsView` porte 6
      `.help()` et **aucune** cible élargie. Les quatre boutons-glyphes de sa
      barre d'outils (défilement auto, copier, grouper, recharger) sont des
      `Image` nues d'environ 13 pt, sous le seuil où macOS peut tenir un survol
      de 2 s immobile : **ces infobulles ne s'affichent jamais**, alors qu'elles
      sont la seule explication de quatre boutons sans libellé. Corrigé dans le
      lot (cible 18×18 + `contentShape`), règle d'accessibilité §7 point 1.
      ✅ **Lot Journaux (phase 5) livré et vérifié à l'écran le 2026-09-09.**
      `LogsView` tombe de
      **26 tailles de police littérales à ZÉRO** — le critère §10 n°1 est
      atteint pour cette vue. Deux tokens monospace neufs
      (`AppDesign.Font.monoFootnote`/`.monoCaption`, dérivés des tokens
      proportionnels), espacements et rayons rangés sur les paliers du système,
      couleurs de gravité passées en sémantique. L'état vide passe à
      `StateCard` et **distingue deux vides** qui ne se lèvent pas pareil :
      filtré (glyphe de filtre + bouton qui remet source, niveau et recherche à
      zéro) ou réellement vide (message seul, sans bouton inerte) — critère §10
      n°4. Les quatre infobulles de la barre d'outils sont **réparées** (cible
      13 pt → 18×18 + `contentShape`). Cliquet relevé de +1 sur
      `vm_dot_L_calls` et `abbreviation_vm` — le `vm.L` du libellé neuf.
      *Écarts assumés, à ne pas « corriger » :* la largeur 58 de la colonne
      d'horodatage (c'est un alignement, pas un espacement) et le diamètre 6 pt
      des points de gravité (plus petit il disparaît, plus gros il déborde).
      > **À vérifier à l'écran (lot Journaux)** — 1. Onglet Journaux sur un
      > vrai journal SMAPI (~120 000 lignes) : le défilement reste fluide, les
      > cartes de santé et de bissection gardent leur place. 2. Taper une
      > recherche qui ne rend rien : le glyphe change, la phrase parle de
      > filtres, le bouton « Effacer les filtres » ramène la liste. 3. Source
      > StarHubFR sans aucun filtre et sans journaux : « Aucun journal pour
      > cette session » revient, **sans** bouton. 4. **Fenêtre à sa largeur
      > minimale, en français** : les pastilles de niveau (Tout/INFO/WARN/
      > ERROR/TRACE avec leur compte) ne se chevauchent pas — c'est la seule
      > zone où la tokenisation a resserré des espacements (10 → 8, 5 → 4).
      > 5. Grouper par mod : les points rouge/orange restent visibles à côté du
      > nom. 6. **Survoler deux secondes chacun des quatre boutons-glyphes de
      > la barre d'outils** : l'infobulle sort — avant ce lot, aucune ne
      > sortait.
      >
      > ✅ **Les six points sont passés** (vérification de l'auteur, 2026-09-09).
      > Le point 4 en particulier — les pastilles de niveau en français à la
      > largeur minimale — était le seul risque de mise en page du lot : la
      > tokenisation y resserrait deux espacements. Il tient. La même
      > tokenisation peut donc être répétée sur les 53 sites de `SettingsView`
      > sans reposer la question.

      ✅ **Lot Réglages (phase 6) livré et vérifié à l'écran le 2026-09-09.**
      `SettingsView` tombe de
      **53 tailles littérales à ZÉRO** : les deux vues du lot sont à zéro, le
      critère §10 n°1 est atteint sur tout le périmètre de H-T7. Onze sections
      de premier niveau — et non treize : **le glossaire et le secours en ligne
      sont imbriqués dans « Traduction assistée »** (`LocalAISettingsSection`),
      les hisser aurait demandé d'éclater cette vue, refonte que §9 exclut.
      Elles se lisent en quatre groupes titrés (Jeu, Mods & contenu, Données &
      stockage, À propos), dont l'ordre vient d'un type Core sous test
      (`SettingsSectionOrder`, 7 tests) : le groupe Jeu suit **l'ordre des
      gestes** — dossier, puis SMAPI, puis lancement — et les réglages de
      développeur quittent le milieu de l'écran pour le groupe Données.
      *Garde-fous du déplacement :* le `switch` de `sectionView` est exhaustif
      (jamais de `default:`, qui rendrait une perte silencieuse), le compte de
      `StandardSection` reste à 13, et le mapping cas → propriété a été relu un
      à un — c'est le seul contrôle qui attrape un **branchement croisé**, que
      ni le `switch` ni le compte ne voient. Cliquet relevé de +1 (le `vm.L`
      des titres de groupe). Bénéfice de côté : un `body` de 380 lignes découpé
      en onze propriétés nommées, exactement le genre qui sature le
      type-checker.
      > **À vérifier à l'écran (lot Réglages)** — 1. Les onze sections sont
      > toutes là, aucune perdue au déplacement : **4** sous Jeu, **3** sous
      > Mods & contenu, **3** sous Données & stockage, **1** sous À propos.
      > 2. **En français, fenêtre à sa largeur minimale** : les quatre titres
      > de groupe ne se tronquent pas — « Données & stockage » est le plus
      > long. 3. Sans clé Nexus enregistrée : le champ sécurisé et le bouton
      > « Enregistrer » sont là, le flash vert sort à l'enregistrement.
      > 4. Avec une clé : les points masqués sont monospacés et alignés.
      > 5. « Traduction assistée » contient toujours le glossaire **et** le
      > secours en ligne — ils n'ont pas été hissés au premier niveau, et
      > n'apparaissent nulle part en double.
      >
      > ✅ **Les cinq points sont passés** (vérification de l'auteur,
      > 2026-09-09). Aucune section perdue au déplacement des onze blocs, et
      > les quatre titres tiennent en français à la largeur minimale.

      **H-T7 est clos.** Les deux vues du lot sont à zéro taille littérale, les
      deux lots sont vérifiés à l'écran. L'axe H garde **quatre** items ouverts
      — H-T5c, H-T5e, H-T8, H-T9.

      **Ce qui n'est PAS dans ce lot, et attend H-T9** : le dépôt porte **538**
      tailles littérales au total — `ModDetailView` 106, `MainView` 57,
      `BisectionCard` 36, `SmapiHealthCard` 35, `QuarantineView` 19. Les lots
      qui ont touché ces fichiers (H-T2/T3, H-T4b, H-T6) n'en avaient scopé
      qu'une partie : ce n'est pas un manquement de leur part, c'est
      l'inventaire que le closage doit reprendre. **Ne pas rouvrir ces lots
      depuis H-T7.** S'y ajoutent, depuis H-T8, les **17** littérales de
      `ThaiTranslationHubView`, écarté parce que `C5-T1` doit le refondre.


- [x] **H-T8** — ✅ **Livré et vérifié à l'écran le 2026-09-09.** **Hub de traduction** : reskin de continuité seulement —
      monde à part, déjà structuré. · **M**
      ▸ **Cadré et mesuré le 2026-09-09.**
      **Périmètre : cinq vues, 74 tailles littérales, 1 970 lignes** —
      `TranslationDiffView` (1 021 l., 37), `TranslationEditorView` (494 l., 13),
      `TranslationRecoveryDiffView` (190 l., 12), `TranslationBatchView`
      (164 l., 8), `TranslationSectionIndexView` (101 l., 4). Ce sont bien les
      « Éditeur, diffs, lots » que la spec §6 nomme pour ce lot ; les deux
      dernières sont ouvertes **depuis** `TranslationDiffView` (l.213 et l.313),
      aucune n'est orpheline.
      ⚠️ **`ThaiTranslationHubView` (283 l., 17 littérales) est EXCLU, et c'est
      délibéré.** Ce n'est pas l'éditeur FR mais le catalogue de traductions
      thaï de l'amont — et surtout **`C5-T1` est encore ouvert** (vérifié : la
      case l.346, et aucun commit ne touche `showThaiTranslationHub`), qui doit
      rendre cette vue générique et exposer une vue FR par défaut. La
      reskinner maintenant serait du travail que C5-T1 jetterait. **Ses 17
      littérales rejoignent donc l'inventaire H-T9**, pour que cet écran ne
      sorte pas de l'axe H sans que personne s'en aperçoive.
      **Deux tokens manquent encore**, et le lot les ajoute : le monospace
      n'existe qu'en 11 et 12 (posés par H-T7) alors que le hub en emploie 7 à
      **10 pt** et 1 à **9 pt** — des clés techniques, plus petites qu'une ligne
      de journal. `size: 8` (un glyphe décoratif annotant une clé) monte à 9,
      le plus petit palier : **changement visible d'1 pt**, à vérifier à
      l'écran.
      **Accessibilité §7 point 1** : le relevé automatique donnait
      `TranslationEditorView` à 6 `.help()` pour zéro cible élargie — le motif
      de `LogsView` avant H-T7. **La lecture du code l'a réfuté, et c'est le
      constat le plus utile du lot.** Les trois glyphes de l'éditeur
      (baguette, chevrons) sont des boutons **système bordés**, pas `.plain` :
      macOS leur donne déjà une zone de contrôle bien plus large que le glyphe.
      Les trois de `TranslationDiffView` portent **glyphe *et* libellé** dans un
      `HStack` — la cible fait la largeur du texte. Le défaut de `LogsView`
      venait des boutons `.plain` à `Image` nue, forme **absente** du hub.
      Un compteur `help()` sans `contentShape` en face n'est donc pas un
      défaut : c'est un signal à instruire, six faux positifs sur six ici.
      **États vides §10 n°4 : déjà tenus, rien à corriger.** Le vide filtré de
      `TranslationDiffView` porte son échappatoire depuis toujours
      (`diffClearFilters`, l.586 — « sans elle, un filtre trop étroit est une
      impasse dont on ne voit pas la sortie »). Les autres sont des états
      **sans issue** — ce mod n'a aucune clé, rien à comparer — auxquels il n'y
      a rien à proposer ; ou bien leur champ de recherche est à vingt points
      au-dessus (`TranslationSectionIndexView`).
      ✅ **Bilan : le lot se réduit à la tokenisation, et c'est le résultat
      juste.** La spec annonçait « reskin de continuité seulement » : le hub,
      écrit plus tard que les journaux, tenait déjà les deux critères de fond.
      Aucun correctif inventé pour justifier le lot.
      > **À vérifier à l'écran (H-T8)** — 1. Fiche d'un mod traduit → onglet
      > diff : les clés i18n restent monospacées et alignées en colonne, les
      > compteurs des filtres gardent leurs chiffres alignés d'une ligne à
      > l'autre (`.monospacedDigit()` préservé sur trois d'entre eux).
      > 2. **Le seul écart visible du lot** : dans la liste du diff, le petit
      > glyphe de loupe qui annote une clé passe de 8 à 9 pt — vérifier qu'il
      > reste aligné sur la ligne de base de la clé qu'il annote (son
      > commentaire d'origine dit que c'est son enjeu). 3. Éditeur d'une clé :
      > baguette de pré-traduction et chevrons précédent/suivant restent
      > cliquables et leurs infobulles sortent. 4. Lot de traduction et index
      > des sections ouverts depuis le diff : rien n'a changé de taille au
      > point de tronquer. 5. Un mod sans aucune clé à traduire, puis un filtre
      > qui ne rend rien : le premier affiche son constat, le second garde son
      > lien « effacer les filtres ».
      >
      > ✅ **Les cinq points sont passés** (vérification de l'auteur,
      > 2026-09-09), le glyphe monté de 8 à 9 pt compris : il reste aligné sur
      > la ligne de base de la clé qu'il annote.


- [x] **H-T9** — ✅ **Livré le 2026-09-09 — l'axe H est clos.** **Closage** :
      audit de fidélité (Découvrir visuellement identique à la v1.25.0 malgré
      les évolutions du système), bibliothèque `/design` complétée (Screens),
      nettoyage des vestiges. · **S**
      **1. Audit de fidélité : ZÉRO écart** — critère §10 n°6 atteint. Méthode,
      faute de pouvoir comparer à l'œil : résoudre chaque token en sa valeur
      numérique et comparer les multisets de valeurs de style (polices,
      espacements, rayons, marges, hauteurs) entre `v1.25.0` et aujourd'hui.
      Résultat : **29 valeurs distinctes des deux côtés, aucune disparue,
      aucune apparue**. Et **aucune valeur de token n'a bougé** depuis
      v1.25.0 : le diff de `AppDesignCore.swift` et `AppDesignUI.swift` ne
      porte que des ajouts, pas une seule ligne supprimée.
      ⚠️ **Le chemin vaut d'être retenu : 21 écarts → 8 → 5 → 0, et les 21
      étaient tous faux.** Chaque réduction est venue d'un **élargissement du
      périmètre**, jamais d'un correctif. La vitrine de v1.25.0 tenait dans un
      seul fichier ; aujourd'hui son style vit aussi dans `ModCard`,
      `HeroHeader`, `SectionHeader`, `StatStrip`, `StateCard`, `NeutralBadge`,
      `ErrorBanner` et `CategoryBadge`. Comparer fichier à fichier montrait des
      disparitions fantômes. Deux pièges en particulier : `NeutralBadge` est
      l'ancien `badge(_:)` privé de `DiscoverView` (son en-tête dit lui-même
      pourquoi ses marges 6 et 2 **restent littérales** — les tokens voisins
      valent 4 et 8, les substituer aurait changé l'apparence), et
      `CategoryBadge` existait **déjà** en v1.25.0, dans `ModListView` : ses
      valeurs paraissaient « nouvelles » parce qu'elles n'étaient pas dans le
      fichier comparé. **Un compte n'est pas une lecture** — trois fois de
      suite ici.
      **2. Bibliothèque `/design` complétée** : quatrième artboard
      `Screens.dc.html` (`canvas.json` n'en déclarait que trois — Foundations,
      Components, Cards). Il montre ce que les autres ne montrent pas : le
      **patron de page de liste** (en-tête fixe / défilement / pied fixe), les
      journaux avec leur repli de familles et leurs comptes par source, les
      deux états vides qui ne se lèvent pas pareil, et les quatre groupes des
      Réglages. Il dit aussi ce qu'il ne montre pas, et pourquoi.
      **3. Vestiges retirés** : `green_button.png`, `wood_button.png`,
      `wood_panel.png` — hérités du commit initial (`8b068b2`, 2026-07-03),
      **jamais chargés par une ligne de ce fork** (`git log -S` muet sur les
      trois), et pourtant copiés dans le bundle à chaque build. Leur seule
      autre trace est une déclaration de ressource dans le `.pbxproj` de
      l'amont, pas un usage.
      ▸ **Ce que H-T9 ne fait PAS, et c'est délibéré** : les **555** tailles de
      police littérales du reste du dépôt (538 relevées en H-T7 + 17 de
      `ThaiTranslationHubView` en H-T8) restent en place. Le critère §10 n°1 ne
      porte que sur « les vues migrées », et les remettre à zéro sur quarante
      fichiers serait un chantier plus gros que tout l'axe H réuni. **C'est un
      relevé daté pour un futur axe, pas une dette à éteindre ici.**

