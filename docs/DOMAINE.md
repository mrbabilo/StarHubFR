# StarHubFR — Connaissances métier

À lire avant de toucher à l'installation de mods, à SMAPI, à Nexus, aux profils,
aux sauvegardes ou aux fichiers de traduction. C'est ce que ni `CLAUDE.md`
(conventions), ni `REFACTORING.md` (architecture), ni `ROADMAP.md` (feuille de
route) ne disent : **ce que l'application manipule réellement, et à quoi
ressemblent les systèmes extérieurs qu'elle enveloppe.**

Transposé de `docs/DOMAIN_CONTEXT.md` de l'upstream (AppleBoiy/StarHubTH), mais
**chaque affirmation a été vérifiée contre notre code** — plusieurs de leurs
paragraphes sont faux ici, et sont signalés comme tels plus bas. Ne pas lire leur
version en pensant qu'elle nous décrit.

## 1. Ce qu'est StarHubFR

Le positionnement fait foi dans [`ROADMAP.md` §2](ROADMAP.md) :

> gestionnaire de mods macOS **francophone**, qui prend au sérieux trois choses :
> la santé de la modlist, la traduction FR, et la lisibilité de ce qui est installé.

Deux conséquences structurantes :

- **Un seul jeu.** `Mods/`, `manifest.json`, SMAPI et le domaine Stardew Valley de
  Nexus sont des hypothèses codées en dur, délibérément. Pas de couche
  d'abstraction par jeu, pas de système de greffons. Une demande du genre
  « généraliser à d'autres jeux » est une sortie de périmètre, à signaler plutôt
  qu'à construire.
- **UI bilingue en/fr seulement.** `assets/en.json` et `assets/fr.json` sont la
  source de vérité, à parité de clés obligatoire (le build échoue sinon).
  *Le thaï comme langue d'interface a été retiré* — mais la fonctionnalité
  « catalogue de traductions thaï » subsiste (`ThaiTranslationTable.swift`),
  neutralisée derrière `showThaiTranslationHub`, faux par défaut
  ([MainView.swift:13](../StarHubTH/Views/MainView.swift#L13)).

## 2. Les quatre mots qui se confondent

C'est la première source d'erreur du domaine. Aucun de ces termes n'est
interchangeable, et **notre vocabulaire diverge de celui de l'upstream**.

| Terme | Chez nous | Piège |
| --- | --- | --- |
| **pack** | un **dossier de premier niveau contenant plusieurs mods** — un même téléchargement livre un framework et ses packs de contenu. `ModItem.isGroup` + `children`. | Chez l'upstream, `ModPack` désigne tout autre chose : un ensemble exportable, calqué sur les *Collections* Nexus. **Nous n'avons pas cela** — aucun `ModPack.swift`, aucune collection. Leur doc induirait en erreur. |
| **profil** | un jeu nommé d'identifiants de mods activés, purement local, pour basculer d'une configuration à l'autre. `ModProfile.swift`. | Aucun partage, aucune métadonnée Nexus, aucun format d'export. |
| **sauvegarde de partie** | les parties de Stardew Valley, sous `~/.config/StardewValley/Saves/`. `SaveManager.swift`, `SaveTree.swift`. | « sauvegarde » tout court est ambigu — préciser. |
| **sauvegarde d'application** | ce que StarHubFR archive lui-même, sous `~/Library/Application Support/StarHubTH/Backups/{ModInstalls,ModConfigs}`. | Deux dossiers distincts : le mod entier avant réinstallation, et les seuls fichiers de configuration. |

## 3. SMAPI

SMAPI est le chargeur de mods tiers dont dépend la quasi-totalité des mods. Il
remplace l'exécutable du jeu. L'application l'installe, le surveille et lit ses
journaux ; **elle ne réimplémente rien de sa logique de chargement.**

- **Installation** — [`SmapiInstaller.swift`](../StarHubTH/SmapiInstaller.swift).
  L'installeur officiel est lancé sous le capot ; l'exécutable d'origine est
  conservé sous le nom `StardewValley-original` dans le dossier du jeu. **Sa
  présence est littéralement la façon dont l'application détecte « SMAPI est
  installé ».**
- **La détection de version est un contournement assumé, pas de la complexité
  gratuite.** SMAPI ne laisse derrière lui aucun artefact fiable disant sa
  version. L'application écrit donc son propre marqueur,
  `smapi-internal/.starhubth-installed-version`, juste après une installation
  réussie ([SmapiInstaller.swift:11](../StarHubTH/SmapiInstaller.swift#L11)), et
  ne se rabat sur l'analyse du journal que pour les installations qu'elle n'a pas
  faites. **Ne pas « simplifier » en supposant que SMAPI publie sa version
  quelque part** — cela a été vérifié, il ne le fait pas.
- **Identité d'un mod** — chaque dossier sous `Mods/` porte un `manifest.json`
  avec un `UniqueID` (`Pathoschild.ContentPatcher`) dont SMAPI se sert pour
  résoudre les dépendances. Il ne faut le confondre ni avec l'identifiant de la
  page Nexus, ni avec le nom du dossier. Les comparaisons d'identifiants se font
  **sans égard à la casse** : SMAPI fait de même, et deux auteurs écrivent
  rarement le même identifiant pareil.
- **Ce que le chargeur tolère est bien plus large que ce que documente son
  schéma.** SMAPI lit les `manifest.json` et les `i18n/*.json` avec Newtonsoft en
  réglages par défaut : commentaires, virgules en trop, clés non quotées,
  guillemets simples, retours à la ligne bruts dans une valeur. Toute affirmation
  du type « le jeu refusera ce fichier » doit être **mesurée** en exécutant sa
  propre `Newtonsoft.Json.dll`, jamais déduite d'un schéma.

### Mettre un mod en pause — nous divergeons de l'upstream

**Un mod en pause est un dossier préfixé par un point, resté dans `Mods/`**
(`Mods/.NomDuMod`), parce que SMAPI ignore les dossiers pointés. L'upstream
déplace le dossier vers `Mods_disabled/` ; nous avons migré vers le préfixe et
gardons une migration idempotente depuis l'ancien schéma
([StarHubTHViewModel.swift:535](../StarHubTH/StarHubTHViewModel.swift#L535)).

La conséquence à connaître : **tout dossier pointé est candidat à « mod en
pause »**, y compris les résidus du système. C'est ce qui a fait afficher un
`.Spotlight-V100` comme un mod désactivé. La liste de référence est
[`OSJunk.swift`](../StarHubTH/Models/OSJunk.swift) — une seule, justement pour
que ce défaut ne revienne pas par duplication.

## 4. Nexus Mods

- **API REST v1** (`https://api.nexusmods.com/v1`) — informations de mod, listes
  de fichiers, liens de téléchargement. Clé personnelle par utilisateur, envoyée
  en en-tête, **stockée dans le trousseau macOS — jamais dans `UserDefaults`**
  ([NexusUpdateChecker.swift:9](../StarHubTH/NexusUpdateChecker.swift#L9)). Pas
  d'OAuth. `Models/NexusDownloadAPI.swift`, `Models/NexusRequestBuilder.swift`,
  `Models/NexusDownloader.swift`.
- **GraphQL v2 : nous ne l'utilisons pas.** L'upstream s'en sert pour les
  *Collections* ; nous n'avons pas cette fonctionnalité. Leur paragraphe ne nous
  décrit pas.
- **Protocole `nxm://`** — l'application enregistre le schéma d'URL, si bien que
  « télécharger avec un gestionnaire » depuis le site Nexus la réveille.
  `Models/NxmLink.swift` analyse l'URL. Elle arrive par `application(_:open:)`
  au niveau AppKit, **pas** par le `.onOpenURL` de SwiftUI, et les URL reçues
  avant que la vue n'ait câblé son gestionnaire — cas du démarrage à froid
  déclenché par un clic — sont mises en attente puis rejouées
  ([StarHubTHApp.swift:9](../StarHubTH/StarHubTHApp.swift#L9)).
- **Limites de débit et clé révoquée sont de vrais modes de panne visibles par
  l'utilisateur**, pas des cas théoriques.
- **La liste de compatibilité SMAPI n'est pas branchée.** Les mods cassés sont
  aujourd'hui déduits des avertissements du journal SMAPI local, sans base
  externe — c'est l'objet de **A2** dans la roadmap.

## 5. Fichiers de traduction (i18n)

Le différenciateur du produit, et le sujet le plus piégeux.

- Un mod traduit porte `i18n/default.json` (l'anglais de référence) et un fichier
  par langue, `i18n/fr.json`. Sans `default.json`, une couverture n'a pas de
  dénominateur.
- **Les auteurs les écrivent à la main**, par centaines : commentaires de
  section, virgules en trop, fins de ligne Windows (CRLF, majoritaires),
  encodages hérités. Un lecteur JSON strict en refuse près de 40 % sur une
  modlist réelle. D'où [`I18nLenientParser.swift`](../StarHubTH/Models/I18nLenientParser.swift),
  dont l'en-tête porte les mesures et les limites connues — **le lire avant d'y
  toucher.**
- Un pack de traduction **vers une autre langue** (`i18n/th.json`, `zh.json`) n'a
  pas de `fr.json` : il s'afficherait à 0 % de couverture FR alors qu'il est
  complet pour ce qu'il est.
- Une mise à jour de mod écrase le dossier et **emporte la traduction
  communautaire** que l'auteur ne redistribue pas. C'est mesurable : 16 `fr.json`
  du parc de référence n'existent plus que dans une sauvegarde (**B4-T4**).

## 6. Sauvegardes de partie

[`SaveManager.swift`](../StarHubTH/SaveManager.swift) lit et écrit le format de
Stardew Valley **directement**. C'est du XML, sans API exposée par le jeu : le
lecteur fait de l'extraction ciblée par balise (`extractTag`,
`extractSpouseFromPlayer`) plutôt qu'un modèle objet complet — **délibérément**,
puisqu'un schéma complet devrait suivre chaque champ que le jeu ajoute à chaque
mise à jour, alors que l'application n'en exploite qu'une poignée. L'édition fait
la même chirurgie ciblée sur les mêmes bornes de balises, pour la même raison.

## 7. Où regarder, par tâche

| Vous travaillez sur… | Commencer par |
| --- | --- |
| scan des mods, mise en pause, packs | `StarHubTHViewModel.swift` (`scanMods`), `ModItem.swift`, `Models/OSJunk.swift` |
| manifestes, dépendances | `Models/ManifestJSON.swift`, `Models/ModDependencyParser.swift`, `Models/ModDependencyStatus.swift`, `Models/DependencyTree.swift` |
| installation depuis une archive | `ModZipInstaller.swift`, `Models/ZipModInfo.swift`, `ModFolderRepairer.swift` |
| téléchargements et mises à jour Nexus | `Models/NexusDownload*.swift`, `NexusUpdateChecker.swift`, `Models/NexusUpdateConsolidation.swift` |
| SMAPI : installation, version | `SmapiInstaller.swift` |
| journaux et diagnostic SMAPI | `Models/SmapiLogParser.swift`, `Models/SmapiLogDiagnostics.swift`, `Models/LogNoise.swift`, `Models/ModErrorHistory*.swift` |
| recherche du mod fautif (bissection) | `BisectionRunner.swift`, `Models/Bisection*.swift` |
| profils | `Models/ModProfile.swift` |
| sauvegardes de partie | `SaveManager.swift`, `Models/SaveTree.swift` |
| sauvegardes applicatives | `ModInstallBackupManager.swift`, `ModConfigBackupManager.swift` |
| traduction FR | `Models/I18nLenientParser.swift` |
| chaînes d'interface | `L10n.swift` + `assets/{en,fr}.json` → skill `localization` |

## 8. Ce que ce document ne dit pas

L'architecture, le découpage en couches et l'ordre des extractions sont dans
[`REFACTORING.md`](REFACTORING.md) — source de vérité unique pour la migration en
cours. Les fonctionnalités à venir sont dans [`ROADMAP.md`](ROADMAP.md). Les
procédures de build, de test et de release sont dans `CLAUDE.md` et les skills.
Ce document ne porte que le **métier**.
