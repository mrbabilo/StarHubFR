# Roadmap StarHubFR

> **Sources** :
>
> 1. `docs/Recherche les meilleurs projets open-source pour S.md` (veille Perplexity : écosystème, comparaisons, risques) ;
> 2. **la liste de souhaits dictée par l'auteur du projet le 2026-07-30** — *source faisant autorité sur le périmètre*.
>
> **Réconciliée avec l'état réel du dépôt au 2026-07-30 (v1.10.0).**
> **Statut** : document de travail. Les identifiants de tâche (`C1-T2`, `B3-T1`…) sont
> stables et peuvent être cités dans les messages de commit et les futures sessions.

---

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

## 2. Positionnement retenu

> **StarHubFR = gestionnaire de mods macOS francophone, qui prend au sérieux
> trois choses : la santé de la modlist, la traduction FR, et la lisibilité
> de ce qui est installé.**

- **Axe A — Diagnostic, fiabilité & compatibilité** : bissection guidée, dépendances,
  manifests corrompus, liste de compatibilité SMAPI distante.
- **Axe C — Traduction FR** *(différenciateur)* : couverture i18n, diff EN/FR, édition
  assistée de `fr.json`, hub multilingue.
- **Axe B — Ergonomie mods, profils & backups** : rendre exploitable ce qui existe déjà.
- **Axe D — Performance** : exploitation du log du mod *Profiler*, puis mutualisation.
- **Axe E — Packs, distribution & pédagogie** : packaging, rapport de modlist, doc, Nexus.
- **Axe F — Dette technique** *(transverse)* : découpage du God module, audit perf/sécurité,
  réactivité de la liste des mods (**F3**).

**Règle de discipline reprise du document de veille** :
> *Chaque release ne sert qu'un seul axe principal, plus quelques correctifs gratuits.*

---

## 3. Table de réconciliation

Marquage : **Fait** = preuve dans le code ou le CHANGELOG. **Partiel** = socle présent,
promesse non tenue. **À faire** = rien dans le code. Les lignes **§new** viennent de la
liste du 2026-07-30 et n'existaient pas dans le document de veille.

| Source | Demande | État | Preuve / renvoi |
| :-- | :-- | :-- | :-- |
| **§new** | Désactivation/activation **dichotomique** pour isoler un mod défectueux | **Fait ✅** | `Models/BisectionSession.swift` (Core, testé) + `BisectionRunner` + `Views/Components/BisectionCard.swift` |
| **§new** | Mutualiser les diagnostics/mesures de perf entre utilisateurs (cf. `circinus.sh`) | **À faire** | Aucun backend → **D2** (décision produit, non chiffrée) |
| **§new** | Refactoriser le God module | **À faire** | `StarHubTHViewModel.swift` = **6485 lignes** (4278 au relevé initial, +52 %) → **F1** |
| **§new** | Vérifier optimisation (vitesse, mémoire) et sécurité du code | **À faire** | → **F2** |
| **§new** | Copier/coller du NexusID impossible | **Non reproduit** | Fonctionne ; le menu Édition est présent → **X1** clos |
| **§new** | BBCode/Markdown non rendu dans la description | **Corrigé ✅** | 6 défauts reproduits sur SVE (3753) puis corrigés (tokeniseur récursif) ; rendu typé ajouté (titres/listes/code/citations/centrage/couleur/souligné), vérifié sur 51 descriptions → **X2** |
| **§new** | Rafraîchissement automatique dès qu'on renseigne l'identifiant Nexus | **À faire** | → **B2-T3** |
| **§new** | `smapi.io/json` comme analyseur de référence pour les JSON Stardew | *(précision)* | Affine la définition de « manifest valide » → **A1-T2** |
| **§new** | `stardew-i18n-translator` comme référence de pipeline i18n | *(précision)* | Affine **C3** — voir la réserve de licence en §5 |
| §1 | Refonte du log SMAPI façon *Log Doctor* | **Fait** | `Models/SmapiLogDiagnostics.swift`, `Views/Components/SmapiHealthCard.swift`, v1.9.x–1.10.0 |
| §1 | Optimiser l'affichage des ~2000 lignes | **Fait** | `LazyVStack` + repliement par famille (`Models/LogNoise.swift`), v1.10.0 |
| §1 | Signaler les mods incompatibles (`smapi.io/mods`) | **Fait** | L'API live est branchée (**A2-T1**) et son verdict s'affiche — fiche, carte de santé, et confirmation avant activation ou installation (**A2-T2**) |
| §1 | Activer automatiquement les dépendances | **Partiel** | `DependencyTreeView.swift:124` : bouton **Activer** par nœud. Manque l'action groupée → **A1-T1** |
| §1 | Détecter un `manifest.json` corrompu, proposer une réinstallation | **Partiel** | `ModFolderRepairer.swift` répare des structures de dossiers, pas des manifests invalides → **A1-T2** |
| §1 | Mise en évidence des problèmes dans la liste des mods | **Fait** | Pastille d'anomalie près du nom (**B1-T3**, pas encore publié) |
| §2 | Dates Nexus (création / mise à jour) | **Fait, pour ce qui est capté** | Revérifié le 2026-08-25 : la seule date captée (`updated_timestamp`) est nommée juste aux trois endroits qui la montrent. `created_timestamp` n'est jamais demandé → **B2-T5** devient un ajout |
| §2 | ETA pendant le téléchargement | **À faire** | Rien dans `Models/NexusDownloader.swift` → **B2-T1** |
| §2 | Poids du mod, taille de `Mods/`, espace disque restant | **Fait** | Pied de barre latérale + fiche mod (**B2-T2**, pas encore publié) |
| §2 | Splashscreen en fenêtre dédiée | **Fait** | `Views/LaunchSplashWindow.swift`, v1.10.0 |
| §2 | Boutons **Activer** / **Supprimer** sur la fiche mod | **Livré** (2026-08-01) | `ModDetailView.actionRow` → **B1-T1** |
| §2 | Le retour depuis la fiche conserve tri / filtres / scroll | **Partiel** (2026-08-01) | `ModListFilters` porté par le ViewModel ; **le scroll ne l'est pas, et c'est assumé** (pagination à 15) → **B1-T2** |
| §2 | Vérifier le bouton d'activation de la page dépendances | **Fait** | Corrigé le 2026-07-30 par `8f0a81e` (`seedFolder` remonte au pack) → **X3** |
| §2 | Boutons de rafraîchissement (quarantaine, alertes système) | **À faire** | → **B2-T3** |
| §3 | Reconnaître les mods de traduction (i18n seul) | **Partiel** | `ModItem.languages`, filtre `FrenchTranslationScope` et heuristique de nom (`ModItem.swift:99`) — **C1-T4 requalifiée et livrée** (`46ce633`) : le cas visé est à zéro mod sur le parc |
| **§new** | Installer une archive sans manifeste (traduction d'un mod, greffe type `ItemBags`) | **Fait** | Livré le 2026-08-25 (**A1-T3**, pas encore publié) ; jeu d'épreuve dans `mods tests/` |
| **§new** | Chercher sur Nexus les traductions FR et les suppléments des mods installés | **Fait** | Traductions (**A3-T2/T3**) et suppléments (**A3-T4**) livrés le 2026-08-25/26 |
| §3 | Nouveau profil créé **vide** | **Fait** (2026-08-24) | L'alerte propose les deux voies, « vide » en premier ; `ProfileFactory` (Core, testé) → **B3-T1** |
| §3 | Favoris de mods + import dans un profil | **Fait** | Étoile, cadrage, import nommant les intraduisibles (**B3-T2**, pas encore publié) |
| §3 | Duplication d'un profil | **Fait** (2026-08-24) | `duplicateProfile(id:)`, depuis le menu ⋯ de la ligne → **B3-T3** |
| §3 | Recherche automatique des NexusID manquants | **À faire** | Saisie manuelle sur la fiche mod → **A3-T1** |
| §4 | Backups : feedback après restauration, tri, regroupement, recherche | **Fait** (2026-08-23) | Regroupement, tri et recherche → **B4-T1** ; compte rendu de restauration (ce qui a été écrit, où, ce qu'est devenue la version remplacée) → **B4-T2** |
| §4 | Un mod restauré met à jour le registre | **Corrigé ✅** (2026-08-23) | Vérifié : la restauration d'un mod **actif** en déposait une seconde copie en pause à côté, deux dossiers pour un `folderName` — la clé du registre. Elle remplace désormais le mod là où il est → **B4-T3** |
| §4 | Sauvegarde / restauration de `config.json` et `fr.json` | **Fait** | `ModConfigBackupManager.swift` + `Extensions/ModConfigFiles.swift` |
| §5 | Éditeur de config exploitant les clés de traduction | **À faire** | `ModConfigEditorView.swift` affiche les clés brutes → **C4-T1** |
| §5 | Intégrer *Modern Config Menu* / GMCM (49382, 49437) | **À instruire** | Réintégré au périmètre à la demande de l'auteur → **C4-T3** (spike) |
| §5 | Aide à la configuration des raccourcis clavier | **À faire** | → **C4-T2** |
| §6 | Éditeur `fr.json` avec diagnostic des clés | **À faire** | → **C2**, **C3** |
| §6 | Chaînes anglaises non traduites hors i18n (`events.json`, `dialogues.json`…) | **À faire** | → **C3-T2** |
| §6 | Pré-traduction (DeepL / Claude / Google) | **Fait** | Trois voies livrées : **locale** (Ollama / LM Studio, glossaire du jeu imposé) → **C3-T3** ; **par son propre chat** (lot `.json` exporté puis réimporté) → **C3-T5** ; **distante par API** (DeepL, marques protégées, quota lu) → **C3-T7**. Google et LibreTranslate écartés, voir la spec |
| §6 | Une mise à jour de mod signale les conflits de config/traduction | **À faire** | → **C2-T4** |
| §7 | Packs de mods et de configs distribuables | **À faire** | → **E1** |
| §8 | Éditeur de sauvegardes enrichi | **Partiel** | `SaveManager.swift` : argent, stats de base, duplication → **E3** (arbitrage) |
| §8 | Profiler / analyse FPS à l'activation d'un mod | **Reformulé** | Aucune mesure maison possible ; parsing du log Profiler → **D1** |
| §9 | Support des archives **RAR** | **Fait ✅** | Glisser-déposer depuis v1.7.1 ; chemin téléchargement/mise à jour réparé en séance (**X5**). Reste le guidage au moment de l'échec → **B2-T4** |
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
| *audit* | Notes libres par mod | **À faire** | → **B3-T6** |
| *audit* | Quota Nexus quotidien visible | **Fait** | Relevé sur toute réponse, affiché dans les réglages (**B2-T6**, pas encore publié) |
| *audit* | `UpdateCautionMessage` (alerte auteur avant mise à jour) | **À faire** | → **B2-T7** |
| *audit* | Panneau de downloads observable (%, vitesse, annulation) | **À faire** | Élargit **B2-T1** |

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

## 4. Correctifs identifiés — à traiter en premier

Ce ne sont pas des fonctionnalités : ce sont des choses cassées ou dégradées.

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

---

## 5. Roadmap par chantier

Effort : **S** ≈ une session · **M** ≈ 2–3 sessions · **L** ≈ chantier multi-sessions.

> **Les chantiers ne portent plus de numéro de version prévisionnel.** Ils en ont
> porté, et la réalité les a démentis trois fois : la v1.14.0 est partie sur
> l'ancrage des versions et non sur l'éditeur de traduction, la v1.15.0 sur
> l'éditeur et non sur les profils, la v1.16.0 sur le glossaire et l'IA locale et
> non sur le registre. Un numéro annoncé ici est une promesse que l'ordre des
> travaux ne tient pas — et une roadmap qui ment sur l'état réel ne vaut rien
> (§9). **Un titre ne porte un numéro que si cette version est sortie**, et le
> `CHANGELOG.md` reste le journal de ce qui est livré.

---

### Bissection guidée — **Axe A** · livrée en **v1.11.0**

> **Changement d'ordre assumé** : la version précédente de cette roadmap plaçait la
> traduction FR en v1.11. La bissection passe devant parce que l'auteur l'a placée en
> tête de sa liste, qu'elle s'appuie sur une mécanique déjà en place
> (`applyProfileToFilesystem`), et qu'à ~900 mods une bissection à la main coûte des
> heures par incident. Voir §7 pour l'arbitrage.

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

#### Embarqués

Les correctifs **X2** et **X3** du §4 (X1 clos sans suite ; X4/X5/X6 livrés en v1.10.1),
plus **B1-T1** et **B1-T2**.

> ✅ **X4, X5 et X6 sont corrigés** et consignés dans `[Unreleased]` — reste à couper la
> **v1.10.1** avec `release.py`. Build vert, 192 tests au vert (dont une régression
> ajoutée sur les codes de sortie d'extraction).

**Risques** : manipulation massive de dossiers ; un abandon en cours de session ne doit
jamais laisser la modlist dans un état intermédiaire.
⚠️ **Dépendance croisée avec F1** : A4-T2 s'appuie sur la machinerie de profils, qui vit
dans le VM de 4278 lignes que **F1-T1** désigne justement comme premier candidat à
l'extraction. Deux issues acceptables — soit l'état de session de bissection naît d'emblée
dans son propre type, soit **F1-T1** passe avant. À trancher au démarrage de la version,
pas à mi-parcours.
**Critère de succès** : identifier le mod responsable d'un plantage sur ~900 mods en une
dizaine d'essais guidés, et retrouver l'état initial exact à la fin.

---

### Hub de traduction FR, phase 1 : *diagnostic* — **Axe C** · livrée en **v1.13.0**, sauf **C2-T4**

Objectif : tenir la promesse du dépôt (« traduction en français ») **en lecture seule**,
sans risque d'écriture destructive.

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
- [ ] **C2-T4** — Après mise à jour d'un mod, signaler les clés de config **et** de
      traduction ajoutées ou disparues (s'appuie sur les références par clé adoptées
      en C2-T2 — l'empreinte prévue n'a pas été retenue, cf. C2-T2). · **M**

**Risques** : formats i18n hétérogènes (tous les mods n'ont pas de `default.json`) ; gros
mods (SVE ≈ milliers de clés) → calcul hors du thread principal.
**Critère de succès** : savoir en un coup d'œil quels mods installés sont traduits,
partiellement traduits ou pas du tout, sans ouvrir un seul fichier.

---

### Hub de traduction FR, phase 2 : *édition & assistance* — **Axe C** · livrée par morceaux (**v1.15.0** → **v1.17.0**)

C'est la version qui fait de StarHubFR autre chose qu'un Stardrop macOS.

> *Ce chantier est parti en trois : **P2a** l'éditeur (livré en v1.15.0), **P2b** le
> glossaire et l'IA locale (livré, dans `[Unreleased]`), **P2c** le lot JSON (livré,
> dans `[Unreleased]` ; l'export ZIP reste un livrable distinct, non planifié).
> Chaque tâche cochée porte sa version réelle.*

#### C3 — Éditeur `fr.json` assisté

> **Référence** : `Nana1873/stardew-i18n-translator` — app de bureau **Windows x64**
> (Rust + Tauri + React), qui lit `i18n/default.json`, écrit `i18n/<lang>.json`, produit
> des ZIP d'installation, et sait construire un glossaire depuis `Content/Strings/*.xnb`.
> Elle traduit via saisie manuelle, **points de terminaison locaux compatibles OpenAI
> (Ollama, LM Studio)** ou lots JSON externes.
> ⚠️ **Licence GPL-3.0+, incompatible avec le MIT de StarHubFR** : on s'inspire du
> *workflow*, on ne recopie pas le code. Bonne nouvelle stratégique : elle est
> **Windows uniquement** — la place est libre sur macOS.

- [x] **C3-T1** — Édition en place depuis la vue diff (écriture atomique, backup
      systématique via `ModConfigBackupManager`). · **M** · risque : écriture destructive
      → aucun enregistrement sans backup préalable.
      **Livré** (v1.15.0) : l'onglet Traduction est devenu un éditeur — édition
      côte à côte, `fr.json` créé au premier enregistrement, `.bak` avant chaque
      écriture, marqueurs du jeu protégés au passage.
- [ ] **C3-T2** — Scan élargi aux assets Content Patcher (`events.json`, `dialogues.json`,
      `content.json`) : repérer les chaînes affichées restées en anglais. · **L** ·
      risque : forte hétérogénéité des packs → livrer en « suggestions », jamais en verdict.
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
- [ ] **C3-T5** — **Partiel ✅** — Export/import d'un lot de travail (`.json`) pour
      traduire à plusieurs, puis fusion contrôlée. · **M**
      **Reste à livrer** : la fusion entre humains (deux traducteurs sur le même mod,
      arbitrage des divergences) et l'export ZIP. La case reste décochée pour cela ;
      l'usage « faire traduire le lot par son propre chat » est, lui, livré (ci-dessous).
      **Plan écrit** le 2026-08-20 (`docs/superpowers/plans/2026-08-20-lot-json-traduction.md`),
      pour l'**autre** usage du même mécanisme : faire traduire le lot par le chat
      que l'utilisateur a déjà — la troisième voie de la référence. C'est la seule
      voie qui ne dépende ni d'un serveur local, ni d'une clé, ni d'un quota, et
      elle a gagné en priorité le jour où l'IA locale s'est révélée impraticable
      sur une machine de milieu de gamme. La fusion entre humains reste hors du
      plan ; l'export ZIP aussi (livrable distinct).
      **Livré** le 2026-08-21 (`c66ef31`…`a162ffe`), validé à la main sur un mod
      réel : deux boutons dans l'onglet Traduction, consignes de traduction
      embarquées dans le fichier, jamais d'écrasement d'un français existant.
      Écart à la ligne `LotExchange` de la spec : l'empreinte SHA-256, livrée
      puis devenue morte au passage au jugement entrée par entrée (un chat
      rend un gros lot en plusieurs messages, et l'import du premier fait
      sortir ses clés de l'état courant), a été retirée du format avant toute
      livraison — le refus en bloc ne survit qu'au cas où aucune clé du
      fichier ne concerne l'état courant.
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

- [ ] **C4-T1** — *(voie sûre)* Étiqueter les champs de `config.json` avec les libellés
      `config.*` que le mod publie dans son `i18n/` (en FR si disponible), au lieu des clés
      brutes. Faisable sans dépendance externe. · **M** · *hypothèse à valider sur un
      échantillon de mods réels avant engagement.*
- [ ] **C4-T2** — Champs de raccourcis clavier : validation des noms `SButton`, détection
      des collisions entre mods. · **M**
- [ ] **C4-T3** — *(spike, 1 session, décision go/no-go)* **GMCM / Modern Config Menu.**
      Question à trancher : les mods **49382** et **49437** écrivent-ils quoi que ce soit
      de lisible hors du jeu (export de schéma, fichier JSON, API locale) ? Nexus renvoie
      HTTP 403 aux requêtes automatiques : à vérifier manuellement.
      ▸ Si **oui** → StarHubFR lit ce fichier : chantier ordinaire.
      ▸ Si **non** → il reste la décompilation des DLL (Mono.Cecil/ILSpy) pour retrouver
      les appels d'enregistrement GMCM : **coûteux, fragile, à recasser à chaque mise à
      jour de mod**. À n'ouvrir que si l'échantillon montre un vrai gain sur C4-T1. · **S**

#### C5 — Hub de traduction agnostique de la langue

- [ ] **C5-T1** — Rendre `ThaiTranslationHubView` générique (langue en paramètre) et
      exposer une vue **FR** par défaut ; supprimer le drapeau `showThaiTranslationHub` ou
      le transformer en sélecteur de langue. · **M**
- [ ] **C5-T2** — Aligner README/CHANGELOG (la mention du hub thaï quitte le discours
      produit). · **S**

**Risques** : c'est la version la plus exposée à la perte de données utilisateur (écriture
dans les fichiers des mods). Aucune écriture sans backup préalable ni diff affiché.
**Critère de succès** : traduire un mod moyen de bout en bout sans quitter StarHubFR, et
pouvoir revenir en arrière à tout moment.

---

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
- [~] **B3-T4** — Diagnostic de profil au changement : mods manquants, dépendances non
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
      **Reste à faire** : la couverture FR du profil (réutiliserait **C1-T1**).*
- [ ] **B3-T5** — **Configurations par profil** : un même mod peut avoir des `config.json`
      différents selon le profil (ex. CJB Cheats configuré en solo, désactivé en multi).
      Capture/restauration au changement de profil avec **merge JSON non-destructif**
      (`JsonTools.Merge` côté Stardop) pour ne pas écraser les réglages existants. Opt-in,
      aucun swap sans backup préalable (réutilise `ModConfigBackupManager`). · **L** ·
      *§audit-stardrop · le chantier le plus volumineux issu de l'audit ; à instruire avant
      engagement (écriture dans les configs des mods = surface de perte de données).*
- [ ] **B3-T6** — Notes libres par mod, persistées au profil (annotations contextuelles :
      « désactivé en multi car désync », « à mettre à jour »). · **S** · *§audit-stardrop*

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

- [ ] **B2-T1** — ETA et débit pendant les téléchargements Nexus, et **panneau de downloads
      observable** : statut par téléchargement, %, vitesse, annulation, retry (inspiration :
      `DownloadPanel` de Stardop). Aujourd'hui StarHubFR ne fait que du
      `URLSession.downloadTask` fire-and-forget, sans progression live. · **M** · *§audit-stardrop*
- [x] **B2-T2** — Poids par mod, total de `Mods/`, espace disque restant (en pied de barre
      latérale). *Livré : `Models/ModsFolderSizer.swift` pèse chaque dossier de premier
      niveau (place **allouée**), la mesure tourne en fond après chaque `scanMods()`, une
      passe à la fois. Deux pièges écartés : la jointure se fait sur le nom **physique**
      (`physicalFolderName`), sans quoi tout mod en pause afficherait 0 octet ; et le
      parcours n'utilise pas `.skipsHiddenFiles`, qui sauterait ces mêmes dossiers. Mesuré
      sur le parc réel : 863 dossiers, 103 893 fichiers, 16,84 Go — **dont 12,71 Go de mods
      en pause (746 sur 863)** — pour 24,9 Go libres, en 5,6 s. D'où le sous-total « en
      pause » et la place restante en orange sous le seuil.* · **M**
- [ ] **B2-T3** — Boutons de rafraîchissement sur la quarantaine et les alertes système ;
      sur la fiche mod, rafraîchissement **automatique** dès qu'un NexusID est saisi. · **S**
- [ ] **B2-T4** — Guidage quand `unrar`/`unar`/`7z` manque. *Socle déjà en place* : l'accueil
      affiche l'état d'installation de `unar` avec la commande Homebrew
      (`home_tool_unar_*`). Ce qui manque : au **moment de l'échec**, un message actionnable
      avec commande copiable — aujourd'hui une phrase anglaise codée en dur (cf. **X6**). · **S**
      *Audit du 2026-08-25 : **la phrase anglaise codée en dur n'existe plus.** X6 a
      livré le message localisé, et il s'affiche bien au moment de l'échec
      (`installErrorMessage` → `rarToolMissing`), commande Homebrew incluse. Ne reste
      que **copiable** : aucun `NSPasteboard` dans la feuille d'installation. La
      tâche a fondu à un bouton.*
- [ ] **B2-T5** — Reprendre l'affichage des dates d'un mod : distinguer explicitement
      *date de création Nexus* et *date de mise à jour*, et vérifier laquelle est montrée
      où (liste, fiche, bandeau de mise à jour). · **S**
      *Revérifié le 2026-08-25 : **ce n'est pas un défaut d'affichage**. L'app ne capte
      qu'une seule date Nexus — `updated_timestamp` → `NexusModExtra.uploadedTime` — et
      les trois endroits qui la montrent la nomment juste : « MàJ » dans la liste
      (`ModListView.swift:1305`), « Dernière mise à jour » sur la fiche
      (`ModDetailView.swift:326`), la date du fichier dans le bandeau
      (`MainView.swift:794`). La date d'installation à côté vient du `manifest.json`,
      étiquetée « Installé ». `created_timestamp` n'est simplement **jamais demandé**.
      Reste donc un ajout — montrer l'âge d'un mod —, pas une correction : le requalifier
      avant de le prendre.*
- [x] **B2-T6** — Quota Nexus quotidien visible (header `x-rl-daily-remaining`). *Livré :
      les six en-têtes `x-rl-*` sont relevés sur **toute** réponse Nexus — succès comme 429,
      car c'est le refus qui porte le « 0 restant » — par un `NexusQuota` pur
      (`Models/NexusQuota.swift`), persisté et affiché dans les réglages avec l'heure de
      remise à zéro. Une réponse sans ces en-têtes (la patte CDN d'un téléchargement) n'est
      pas une mesure à zéro : elle laisse la précédente intacte. L'app n'interrogeant plus
      l'API Nexus qu'à la demande, l'état « jamais mesuré » est explicite.* · **S** ·
      *§audit-stardrop*
- [x] **B2-T9** — Trier la liste des mods par poids. *Livré : chaque ligne porte sa taille
      (teintée au-delà de 100 Mo — 22 dossiers du parc réel, qui portent 87 % des 16,8 Go),
      un tri « Poids » les remonte en tête, et la barre d'outils annonce ce que pèse le
      cadrage courant. **Le filtre par seuil n'a pas été construit, délibérément** : cadrer
      sur « en pause » et trier par poids répond déjà à « qu'est-ce que je peux récupérer »
      — 12,71 Go sur le parc réel, lus directement dans la barre d'outils — et une pastille
      de plus alourdirait une barre qui en porte déjà cinq. Ne pas le rebâtir sans un
      besoin qui ne se satisfasse pas du couple existant.* · **S**
- [ ] **B2-T8** — Cesser d'émettre quand le quota est à zéro. `NexusRateLimitGate` replafonne
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
- [ ] **B2-T7** — `UpdateCautionMessage` : si un manifest installé expose ce champ
      (extension SMAPI tolérée, absente = pas d'alerte), alerter l'utilisateur **avant**
      d'écraser la version existante (breaking change annoncé par l'auteur). · **S** ·
      *§audit-stardrop*
      *Mesuré le 2026-08-25 : **0 mod sur 863** expose ce champ dans le parc de référence.
      La fonctionnalité ne montrerait rien aujourd'hui ; elle ne vaudra que pour un mod
      installé plus tard qui l'annonce. À garder, pas à prioriser.*
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

**Critère de succès** : un profil se crée, se duplique et s'applique sans surprise ; un
backup se retrouve en moins de dix secondes.

---

### Fiabilité du registre & compatibilité — **Axe A** · à faire

#### A1 — Registre robuste

- [ ] **A1-T1** — Action groupée « activer toutes les dépendances manquantes » : l'activation
      unitaire existe déjà par nœud (`DependencyTreeView.swift:124`, cf. **X3**) ; il manque
      la résolution transitive en un geste, avec récapitulatif avant application. · **M**
- [ ] **A1-T2** — Détecter un `manifest.json` illisible et proposer la réparation :
      restauration depuis backup, sinon réinstallation Nexus. La validation doit accepter
      ce que SMAPI accepte (JSON5 : commentaires, virgules traînantes) — `smapi.io/json`
      sert de référence de comportement, et les messages d'erreur doivent être aussi
      explicites que les siens. · **M**

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

> 🔄 **Repositionné après audit Stardop (2026-07-31 — voir `docs/audit-stardrop.md`)** :
> Stardop interroge l'API live `smapi.io/api/v3.0/mods` (`IncludeExtendedMetadata`) — la
> source que SMAPI utilise lui-même au démarrage. **Plus riche que le dump statique
> `mods.jsonc`** : elle remonte en plus la mise à jour *suggérée* et l'URL de mise à jour
> *non officielle*. `mods.jsonc` devient le **fallback hors-ligne**, plus la source primaire.

> 🧪 **Spike (2026-07-31, modlist réelle ~948 mods)** — la richesse est **confirmée**
> (`suggestedUpdate` + `metadata{name,nexusID,main,unofficial}`), mais le spike a révélé
> deux contraintes qui **cadrent l'implémentation** :
> - **🔴 Rate-limit agressif** : smapi.io répond `[]` **silencieusement** (jamais de 429)
>   au-delà de ~100 mods/min par IP. Un fetch complet au boot est **impraticable** sur une
>   grosse modlist. → cache persistant + update check **incrémental** obligatoires.
> - **✅ Pas de bug URLSession** (test croisé curl / `URLSession.shared` / session éphémère :
>   tous réagissent **identiquement** au rate-limit, avec le même body et les mêmes headers).
>   L'intuition initiale d'un bug spécifique URLSession était un artefact de tests en rafale
>   (URLSession testée en série, curl intercalé de pauses). → **implémentation Swift native
>   possible, pas de contournement `curl`**. La fenêtre de récupération du rate-limit est en
>   revanche **longue** (> 60 s après saturation), ce qui renforce la nécessité de **A2-T4**.

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
- [ ] **A2-T3** — Fallback sur `Pathoschild/SmapiCompatibilityList` (`mods.jsonc`,
      jointure sur `UniqueID`) quand smapi.io est injoignable, et bandeau signalant la
      fraîcheur de la source effectivement utilisée (live vs cache statique). · **M**
- [ ] **A2-T4** — **Cache persistant + update check incrémental** (découlant du spike) :
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

> ⚠️ **Réserve conservée** : `smapi.io/mods` annonce lui-même ne plus être mis à jour
> exhaustivement, et son avenir est incertain. À traiter comme **complément** au
> diagnostic de log, jamais comme source unique de vérité — d'où le fallback `mods.jsonc`.

#### A3 — Métadonnées Nexus

- [ ] **A3-T1** — Recherche automatique des `NexusID` manquants (correspondance nom +
      auteur, proposition validée par l'utilisateur, jamais d'écriture aveugle). · **M** ·
      risque : quota d'API Nexus, faux positifs. *La recherche par nom qu'elle suppose
      n'existe pas en API v1 : elle dépend d'**A3-T2** (GraphQL v2), vérifié le 2026-08-25.*

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

**Critère de succès** : passer de « ce mod a planté » à « ce mod est cassé depuis
SMAPI 3.0, voici son remplaçant ».

---

### Performance mesurée — **Axe D** · à faire

#### D1 — Exploitation du log du mod *Profiler* (Nexus 12135)

- [ ] **D1-T1** — Détecter la présence et l'activation de Profiler ; guidage (installer →
      jouer une session représentative → revenir). · **S**
- [ ] **D1-T2** — Parser les lignes `[Profiler] [BigLoop] … GameLoop.TimeChanged` : événement,
      durée totale, détail par mod. Modèle Core testable. · **M**
- [ ] **D1-T3** — Vue « Impact performances » dans l'onglet Diagnostic : classement des mods
      par temps moyen/max, jointure sur le registre. · **M**
- [ ] **D1-T4** — Badge d'impact (faible / moyen / élevé) dans la liste et sur la fiche mod,
      avec mention explicite que la mesure est **contextuelle** (dépend de la save, du
      profil, du moment in-game). · **S**
- [ ] **D1-T5** — Mesure avant/après à l'activation d'un nouveau mod : comparer deux sessions
      Profiler et attribuer le delta. · **M** · *c'est la version tenable de la demande
      « analyse FPS à l'activation de chaque mod » — voir §6.*

**Risques** : dépendance au format de sortie d'un mod tiers → parseur tolérant, échec
silencieux plutôt que faux chiffres.
**Critère de succès** : identifier en une session de jeu les trois mods les plus coûteux,
sans lire une ligne de log.

---

### Horizon 2.0 — Packs, distribution & pédagogie — **Axe E**

#### E1 — Packs

- [ ] **E1-T1** — Créer un pack distribuable (mods + versions + configs) et le réinstaller
      ailleurs ; création automatique d'un profil portant le nom du pack. · **L**
- [ ] **E1-T2** — Pack de configurations seules (sans les mods). · **M**

#### E2 — Distribution & documentation

- [ ] **E2-T1** — Rapport de modlist exportable (Markdown/HTML) : nom, version, source, état,
      couverture FR, anomalies — pensé pour le support et l'usage en cours. · **M**
- [ ] **E2-T2** — Documentation utilisateur : coexistence avec d'autres gestionnaires,
      convention `X` / `.X`, réactivation de tous les mods avant désinstallation. · **S**
- [ ] **E2-T3** — Captures d'écran, page Nexus, distribution hors App Store (signature,
      notarisation, ou **Sentinel** pour lever la quarantaine côté utilisateur). · **M**

#### E3 — Éditeur de sauvegardes *(à arbitrer avant engagement)*

- [ ] **E3-T1** — Décider du périmètre en s'inspirant de `colecrouter/stardew-save-editor`
      (inventaire, relations, recettes). Corruption de save = perte irréversible : n'ouvrir
      ce chantier qu'avec backup automatique et validation stricte. · **L**

**Le passage en 2.0.0** se justifie par le changement de nature du produit (StarHubFR
devient distribuable et partageable), pas par une rupture d'API.

---

### Horizon 2.x — Mutualisation communautaire — **Axe D2**

#### D2 — Diagnostics et mesures partagés entre utilisateurs (cf. `circinus.sh`)

**Volontairement non chiffré.** Ce n'est pas une tâche de développement mais une décision
produit. Trois verrous à lever *avant* d'écrire la moindre ligne :

1. **Infrastructure** — il faut un service serveur, donc un hébergement, une
   disponibilité, un coût récurrent et une maintenance. StarHubFR est aujourd'hui une app
   locale sans backend : c'est un changement de nature du projet.
2. **Données personnelles** — un log SMAPI contient des chemins de fichiers
   (donc le nom de session macOS), la liste complète des mods, parfois des noms de
   sauvegarde. Toute remontée impose anonymisation, consentement explicite, RGPD, et une
   politique de conservation.
3. **Modération et confiance** — des mesures agrégées non filtrées produisent des verdicts
   faux (« ce mod est lent ») fondés sur des configurations non comparables. Il faut un
   seuil de représentativité et une façon de contester.

- [ ] **D2-T1** — *(préalable)* Décider si StarHubFR devient un produit avec backend.
      Tant que la réponse n'est pas oui, les tâches ci-dessous n'existent pas.
- [ ] **D2-T2** — Étudier `circinus.sh` : quelles données remontent, sous quel consentement,
      quelle granularité d'agrégation. · **S**
- [ ] **D2-T3** — *(voie sans backend, à considérer d'abord)* Export/import d'un rapport de
      diagnostic anonymisé que les utilisateurs partagent **eux-mêmes** (forum, Discord).
      Livre 80 % de la valeur d'usage pour ~5 % du coût, et prolonge **E2-T1**. · **M**

---

## 6. Hors périmètre — et pourquoi

| Piste | Décision | Raison |
| :-- | :-- | :-- |
| Ingestion des données de **Performance HUD** (mod 40509) | **Écarté** | Overlay in-game, aucune sortie structurée parsable — le doc de veille le conclut lui-même. Reste en recommandation documentaire (**D1-T1**). |
| **Mesure FPS maison** par instrumentation du jeu | **Écarté, reformulé** | Impossible depuis une app externe : SMAPI n'expose ni FPS ni mémoire à un tiers hors du process. Remplacé par **D1-T5** (delta entre deux sessions Profiler), qui répond au même besoin — « quel est l'impact de ce nouveau mod ? » — avec des données réelles. |
| **xnbcli** / conversion d'assets `.xnb` | **Écarté** | Outillage de moddeur, hors de la promesse « gérer et traduire ses mods ». *Nuance* : la lecture de `Content/Strings/*.xnb` reste pertinente pour le glossaire de **C3-T4**. |
| **SMAPI-Android-Installer**, moteur de jeu open-source | **Écarté** | Sans rapport avec une app macOS de gestion de mods. |
| Copier les **profils Stardrop** tels quels | **Écarté** | Le clonage sans dimension FR reproduit un concurrent sans raison d'exister ; **B3-T4** relie au contraire profil, diagnostic et couverture de traduction. |
| *audit* Activation Stardop par **junctions/symlinks** (`SMAPI_MODS_PATH`) | **Écarté** | Choix d'architecture différent du prefixe `X`/`.X` natif SMAPI : plus complexe et dépendant des permissions OS. Notre convention reste plus simple et fiable. Cf. `docs/audit-stardrop.md`. |
| *audit* **`SimpleObscure`** (chiffrement maison de la clé Nexus côté Stardop) | **Écarté** | Obfuscation : clé AES + IV stockées en clair à côté du ciphertext. Inférieure au **Keychain macOS** que StarHubFR utilise déjà. |
| *audit* **Auto-update in-app façon Stardop** (move + restart) | **Écarté (pour l'instant)** | Fragile sur macOS. Si on l'ouvre un jour → **Sparkle**, pas ce bricolage. |
| Collections Nexus (complétude d'un modpack) | **Reporté** | Fort couplage à des collections mouvantes ; à reconsidérer après **E1**. |

*(La piste GMCM/Modern Config Menu a quitté cette section : elle est réintégrée au
périmètre en **C4-T3**, sous forme de spike avec décision go/no-go.)*

---

## 7. Axe F — Dette technique (transverse, à répartir)

Ce n'est pas une release : c'est une contrainte qui traverse toutes les autres.

> **Méthode, ordre des extractions et état d'avancement : [`REFACTORING.md`](REFACTORING.md).**
> Ce document-ci ne garde que les tâches ; le comment vit là-bas.

- [ ] **F1** — **Découper le God module.** `StarHubTHViewModel.swift` fait **4278 lignes**
      et concentre profils, scan, Nexus, logs, configs et sauvegardes.
      **Méthode imposée par l'environnement** : `swift test` est inutilisable ici, donc un
      refactor n'a pour filet que la **compilation** (`python3 build_app.py`) — ce qui
      exclut tout big-bang. Deux règles :
  - [ ] **F1-T1** — Extraire deux domaines nets et autonomes en types dédiés, chacun dans
        un commit isolé, sans changement de comportement. · **M**
        **Domaine 1 livré le 2026-08-01 — journal SMAPI**, en trois commits :
        `LogEntry` sort du ViewModel (sa présentation `Color` l'excluait du module testable),
        `SmapiLogParser` est extrait avec 9 tests, puis le bloc des mises à jour avec 4 tests.
        Le ViewModel passe de 4390 à 4239 lignes. **Sonde préalable décisive** : un
        `@MainActor final class … : ObservableObject` **compile dans `StarHubTHCore` et
        s'y teste** — c'est ce qui rend l'extraction de stores payante ici, et non un
        simple rangement sans filet. Vérifié puis retiré.
        **Domaine 2 livré le 2026-08-01 — catalogue des traductions** : le découpage du
        tableau Markdown passe en Core avec 11 tests (`ThaiTranslationTable`), et
        `ThaiTranslationMod` perd les deux méthodes qui prenaient le ViewModel en
        paramètre — un modèle remontant d'une couche, ce qui l'excluait du module
        testable (correction 2.1 de l'upstream). Une des deux était morte.
        **F1-T1 est donc terminé** : le ViewModel passe de 4390 à 4153 lignes sur la
        journée, avec 24 tests neufs là où il n'y en avait aucun.
        La suite de l'axe F relève de **F1-T2** (règle permanente : toute fonctionnalité
        neuve naît dans son propre type) — que le plan du hub de traduction respecte déjà,
        sa logique pure naissant directement en Core.
        **Audit de l'upstream** (`AppleBoiy/StarHubTH`, refactor phases 0-9 achevé le
        2026-07-25, postérieur à notre fork) : leur découpage par couches
        `Models/ → Services/ (protocole + Live) → Features/<X>Store → vues`, avec un
        `Tests/Stubs/` par protocole, est la référence. **Non repris** : XcodeGen, les
        tests `XCUIApplication` et la capture d'écran — ils dépendent d'une chaîne de build
        que nous n'avons pas. Leurs correctifs *pendant* le refactor valent plus que leur
        plan : c'est ainsi qu'a été trouvé le bloc de mises à jour jamais détecté (corrigé
        ici même) et le `uniqueId: ""` des groupes ci-dessous.
  - [ ] **F1-T2** — **Règle permanente** : chaque axe extrait ce qu'il touche. Une
        fonctionnalité nouvelle ne rentre plus dans le VM ; elle arrive dans son propre
        type, que le VM se contente d'appeler. *(Le risque noté en v1.15 disparaît alors
        de lui-même.)*
- [ ] **F4** — **Les en-têtes de pack portent `uniqueId: ""`.**
      `StarHubTHViewModel.swift:1207` construit chaque groupe avec une identité vide.
      L'upstream a traité le même défaut (leur 2.4) : une dépendance déclarée avec un
      identifiant vide peut alors se résoudre sur un groupe et passer pour satisfaite.
      **Non reproduit ici** — notre `rebuildDependencyIndexes()` n'indexe que les enfants
      d'un groupe, jamais le groupe lui-même, donc la chaîne d'exploitation semble
      coupée. À instruire avant de conclure, puis soit clore, soit corriger
      structurellement (leur réponse : un groupe cesse de porter une identité de mod). · **S**
- [ ] **F3** — **Latence de frappe dans la recherche de la liste des mods.** Rapportée par
      l'auteur le 2026-08-01 : un délai perceptible entre deux lettres, sur sa modlist
      réelle (822 dossiers de premier niveau, 918 manifests).
      **Déjà mesuré, et écarté — ne pas y revenir** :
  - le filtrage (`filteredMods`) coûte **~2 à 5 ms par frappe** à cette échelle ;
  - le tri **0,04 ms**, y compris le cas `.name` dont la closure renvoie toujours `false` ;
  - un index de recherche pré-minusculé (au lieu de `localizedCaseInsensitiveContains`)
        ferait gagner ~2 ms : sans rapport avec l'ordre de grandeur perçu.
      **Piste restante** : le **rendu**, pas le calcul — chaque frappe reconstruit les 15
      lignes de la page avec leurs images, badges, interrupteurs et boutons. Noter qu'un
      debounce de 200 ms a été retiré en 1.7.0 *parce qu'il aggravait* le lag perçu ; le
      remettre suppose un réglage différent, pas un retour en arrière.
      **Non tranché : régression ou défaut préexistant.** `bundles/StarHubFR_v1.11.1.zip`
      est la version d'avant B1-T2 et sert de témoin pour un A/B — première étape de la
      passe, avant d'écrire quoi que ce soit : les deux réponses mènent à des travaux
      opposés.
      **Arbitrage de l'auteur (2026-08-01) : traiter dans une passe de performance
      groupée, en fin de projet** — pas au fil de l'eau. Ne pas rouvrir isolément ; y
      joindre les autres constats de perf accumulés d'ici là. · **M**
- [ ] **F2** — **Audit optimisation & sécurité.** Vitesse et mémoire au démarrage et au
      scan (~900 mods), concurrence (`scanMods()` parallèle, verrous du registre), et
      surface de sécurité : extraction d'archives (traversée de chemin, zip-bomb — déjà
      partiellement couverte), stockage de la clé Nexus, gestion du protocole `nxm://`,
      écritures dans `Mods/`. · **M** · *à faire après F1-T1 : auditer 4278 lignes de VM
      monolithique coûte plus cher que d'auditer des types séparés.*

---

## 8. Ordre recommandé et arbitrage

L'ordre **A4 → C → B → A → D → E** se justifie ainsi :

1. **La bissection d'abord** parce qu'elle est en tête de la liste de l'auteur, qu'elle
   réutilise une mécanique existante, et qu'elle résout le problème le plus douloureux à
   grande échelle : trouver le mod fautif parmi des centaines.
2. **La traduction FR ensuite** parce que c'est la seule promesse du dépôt encore non
   tenue dans les fonctionnalités, et le seul axe introuvable ailleurs — sur macOS, la
   référence i18n existante est Windows uniquement. Tant qu'il n'est pas livré, StarHubFR
   reste un fork techniquement bon mais substituable.
3. **L'ergonomie (B)** ensuite : ce sont des dettes d'usage sur des fonctionnalités déjà
   payées (profils, backups, fiche mod), donc un fort rapport valeur/effort.
4. **La compatibilité (A2)** est utile mais dépend d'une source externe dont l'avenir est
   annoncé comme incertain : ne pas en faire un pilier.
5. **D et E** sont des extensions ; les ouvrir avant que C soit stable reproduirait
   exactement la dispersion que le doc de veille reproche.

**Cet arbitrage est tranché — par les faits.** La question posée ici était :
*réparer d'abord une modlist qui casse, ou tenir d'abord la promesse francophone ?*
Les deux ont été faits. La bissection est sortie en v1.11.0, et l'axe C a suivi sans
attendre : diagnostic (v1.13.0), éditeur (v1.15.0), glossaire et IA locale
(v1.16.0), les trois voies sans modèle local (v1.17.0). Le « plus petit incrément
qui rende le positionnement défendable » — `C1` + `C2` — est livré depuis la
v1.13.0.

**L'arbitrage ouvert aujourd'hui.** La pré-traduction est complète depuis la
v1.17.0 : locale, par son propre chat, par API distante, plus la traduction
d'une sélection — toutes validées à l'écran. Ce qui reste de C n'est plus une
promesse tenue à moitié mais des extensions : l'export ZIP, C4 la config
lisible, C5 le hub agnostique de la langue. Le raisonnement du point 3 ci-dessus
plaide pour **ouvrir B** (profils, backups, fiche mod — des dettes d'usage sur
des fonctionnalités déjà payées) dès que C est *stable* : il l'est.

**Où en est B (2026-08-24).** Ouvert le 2026-08-21, livré dans cet ordre :
**B4** en entier sauf T4 (page des sauvegardes navigable, compte rendu de
restauration, restauration qui remplace le mod là où il est), puis **B3-T1/T3**
(profil vide par défaut, duplication) et **B3-T4 partiel** (mods manquants).
Trois défauts trouvés en chemin, tous corrigés : l'application d'un profil
gelait l'interface, un échec d'application était écrit dans le profil comme s'il
avait été voulu, et une restauration déposait un second dossier du même mod.

**Ce qui a suivi, le même jour** : B3-T4 complété (dépendances non satisfaites,
en réutilisant `ModDependencyStatus` sur l'état *futur* du parc) et **B4-T4**
livré en entier — récupération d'un fichier isolé, puis clé à clé pour les
traductions. Le tout est sorti en **v1.18.0**.

**Ce que B garde de plus valeureux**, dans l'ordre où je le prendrais :
1. ~~**B2-T6**~~ et ~~**B2-T2**~~ *(livrés)* — deux affichages dont la donnée
   était déjà là. Chacun a ouvert une suite : **B2-T8** (la porte de back-off
   peut s'aligner sur l'instant de remise à zéro, désormais connu) et **B2-T9**
   (trier la liste des mods par poids — sur le parc réel, 12,7 Go dorment dans
   des mods en pause, et rien ne dit encore lesquels sans ouvrir 863 fiches).
   B2-T9 est livré à leur suite (poids par ligne, tri, total du cadrage).
2. ~~**B3-T2**~~ *(livré)* — favoris de mods, avec « importer les favoris dans
   ce profil ». L'import renseigne `ProfileModMetadata` dans la même passe :
   sans quoi le diagnostic de profil n'aurait plus su nommer les mods entrés
   par ce chemin, des mois plus tard.
3. ~~**B1-T3**~~ *(livré)* — pastilles d'anomalie dans la liste des mods.
   Ce que la mesure a tranché : compter toutes versions confondues aurait fait
   crier la pastille pour des problèmes déjà réglés par une mise à jour.
4. **B3-T5** (configs par profil) reste le plus gros et le plus risqué : il
   écrit dans les configs des mods. À instruire avant d'engager.

**Ce que B4-T4 laisse ouvert** : les sauvegardes de configs
(`Backups/ModConfigs`) comme seconde source de récupération, et une porte
d'entrée depuis l'onglet Traduction d'un mod — aujourd'hui la comparaison ne
s'atteint que depuis la page des sauvegardes.

---

## 9. Suivi

- Ce fichier est la référence ; le `CHANGELOG.md` reste le journal de ce qui est livré.
- Cocher une case **au moment du commit** qui livre la tâche, en citant l'identifiant
  (`feat(i18n): couverture de traduction par mod (C1-T1)`).
- Réviser la table de réconciliation (§3) à chaque release majeure : elle perd toute
  valeur dès qu'elle ment sur l'état réel du code.
