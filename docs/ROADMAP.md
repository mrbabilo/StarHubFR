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
| **§new** | Refactoriser le God module | **À faire** | `StarHubTHViewModel.swift` = **4278 lignes** → **F1** |
| **§new** | Vérifier optimisation (vitesse, mémoire) et sécurité du code | **À faire** | → **F2** |
| **§new** | Copier/coller du NexusID impossible | **Non reproduit** | Fonctionne ; le menu Édition est présent → **X1** clos |
| **§new** | BBCode/Markdown non rendu dans la description | **Corrigé ✅** | 6 défauts reproduits sur SVE (3753) puis corrigés (tokeniseur récursif) ; rendu typé ajouté (titres/listes/code/citations/centrage/couleur/souligné), vérifié sur 51 descriptions → **X2** |
| **§new** | Rafraîchissement automatique dès qu'on renseigne l'identifiant Nexus | **À faire** | → **B2-T3** |
| **§new** | `smapi.io/json` comme analyseur de référence pour les JSON Stardew | *(précision)* | Affine la définition de « manifest valide » → **A1-T2** |
| **§new** | `stardew-i18n-translator` comme référence de pipeline i18n | *(précision)* | Affine **C3** — voir la réserve de licence en §5 |
| §1 | Refonte du log SMAPI façon *Log Doctor* | **Fait** | `Models/SmapiLogDiagnostics.swift`, `Views/Components/SmapiHealthCard.swift`, v1.9.x–1.10.0 |
| §1 | Optimiser l'affichage des ~2000 lignes | **Fait** | `LazyVStack` + repliement par famille (`Models/LogNoise.swift`), v1.10.0 |
| §1 | Signaler les mods incompatibles (`smapi.io/mods`) | **Partiel** | `brokenMods` extrait des avertissements *du log SMAPI* — aucune base externe → **A2** |
| §1 | Activer automatiquement les dépendances | **Partiel** | `DependencyTreeView.swift:124` : bouton **Activer** par nœud. Manque l'action groupée → **A1-T1** |
| §1 | Détecter un `manifest.json` corrompu, proposer une réinstallation | **Partiel** | `ModFolderRepairer.swift` répare des structures de dossiers, pas des manifests invalides → **A1-T2** |
| §1 | Mise en évidence des problèmes dans la liste des mods | **Partiel** | Historique d'erreurs visible sur la fiche mod ; rien dans la liste → **B1-T3** |
| §2 | Dates Nexus (création / mise à jour) | **À revérifier** | `updated_timestamp` existe dans `NexusUpdateChecker.swift`, mais le champ présent ≠ affichage correct, et l'anomalie est re-signalée → **B2-T5** |
| §2 | ETA pendant le téléchargement | **À faire** | Rien dans `Models/NexusDownloader.swift` → **B2-T1** |
| §2 | Poids du mod, taille de `Mods/`, espace disque restant | **À faire** | Tailles calculées uniquement pour les backups → **B2-T2** |
| §2 | Splashscreen en fenêtre dédiée | **Fait** | `Views/LaunchSplashWindow.swift`, v1.10.0 |
| §2 | Boutons **Activer** / **Supprimer** sur la fiche mod | **Livré** (2026-08-01) | `ModDetailView.actionRow` → **B1-T1** |
| §2 | Le retour depuis la fiche conserve tri / filtres / scroll | **Partiel** (2026-08-01) | `ModListFilters` porté par le ViewModel ; **le scroll ne l'est pas** → **B1-T2** |
| §2 | Vérifier le bouton d'activation de la page dépendances | **Bug présumé** | Le bouton existe (`DependencyTreeView.swift:124`) ; c'est son effet qui est douteux → **X3** |
| §2 | Boutons de rafraîchissement (quarantaine, alertes système) | **À faire** | → **B2-T3** |
| §3 | Reconnaître les mods de traduction (i18n seul) | **Partiel** | `ModItem.languages`, filtre `FrenchTranslationScope` et heuristique de nom (`ModItem.swift:99`) — mais **aucun test structurel** → **C1-T4** |
| §3 | Nouveau profil créé **vide** | **À faire** | `createProfile()` capture au contraire les mods actifs → **B3-T1** |
| §3 | Favoris de mods + import dans un profil | **À faire** | Les favoris n'existent que pour les sauvegardes de jeu → **B3-T2** |
| §3 | Duplication d'un profil | **À faire** | Aucune fonction `duplicateProfile` → **B3-T3** |
| §3 | Recherche automatique des NexusID manquants | **À faire** | Saisie manuelle sur la fiche mod → **A3-T1** |
| §4 | Backups : feedback après restauration, tri, regroupement, recherche | **À faire** | `ModInstallBackupsView.swift` / `ModConfigBackupsView.swift` : liste brute → **B4** |
| §4 | Un mod restauré met à jour le registre | **À vérifier** | `ModInstallBackupManager` restaure les fichiers ; la cohérence du registre n'est pas prouvée → **B4-T3** |
| §4 | Sauvegarde / restauration de `config.json` et `fr.json` | **Fait** | `ModConfigBackupManager.swift` + `Extensions/ModConfigFiles.swift` |
| §5 | Éditeur de config exploitant les clés de traduction | **À faire** | `ModConfigEditorView.swift` affiche les clés brutes → **C4-T1** |
| §5 | Intégrer *Modern Config Menu* / GMCM (49382, 49437) | **À instruire** | Réintégré au périmètre à la demande de l'auteur → **C4-T3** (spike) |
| §5 | Aide à la configuration des raccourcis clavier | **À faire** | → **C4-T2** |
| §6 | Éditeur `fr.json` avec diagnostic des clés | **À faire** | → **C2**, **C3** |
| §6 | Chaînes anglaises non traduites hors i18n (`events.json`, `dialogues.json`…) | **À faire** | → **C3-T2** |
| §6 | Pré-traduction (DeepL / Claude / Google) | **Partiel ✅** | Voie **locale** livrée (Ollama / LM Studio, par clé et par lot, glossaire du jeu imposé) → **C3-T3**. Voie **distante** spécifiée, non livrée → **C3-T7** |
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
| *audit* | Compatibilité mods via l'**API live `smapi.io`** (plutôt que le dump statique `mods.jsonc`) | **À faire** | Plus riche : statut + mise à jour suggérée + URL unofficial. Repositionne **A2** |
| *audit* | **Configs par profil** (un même mod, plusieurs `config.json`) | **À faire** | Manquante ; merge JSON non-destructif → **B3-T5** |
| *audit* | Notes libres par mod | **À faire** | → **B3-T6** |
| *audit* | Quota Nexus quotidien visible | **À faire** | Header déjà reçu, non affiché → **B2-T6** |
| *audit* | `UpdateCautionMessage` (alerte auteur avant mise à jour) | **À faire** | → **B2-T7** |
| *audit* | Panneau de downloads observable (%, vitesse, annulation) | **À faire** | Élargit **B2-T1** |

**Bilan** — 45 demandes de la liste initiale : **4 livrées**, **7 partielles**, **4 bugs à
corriger** (dont **1 bloquant**), **2 à (re)vérifier**, **1 à instruire** (GMCM),
**1 reformulée** (FPS), **1 neutralisée** (hub thaï), **2 précisions de cadrage**,
**23 à faire**. S'y ajoutent **6 pistes issues de l'audit Stardop** (5 nouvelles tâches :
B3-T5/T6, B2-T6/T7, et **A2 repositionné** autour de smapi.io), toutes marquées
`§audit-stardrop`. L'axe diagnostic de log est derrière nous ; l'essentiel du reste tient
dans A, B et C.

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

## 5. Roadmap versionnée

Effort : **S** ≈ une session · **M** ≈ 2–3 sessions · **L** ≈ chantier multi-sessions.

---

### v1.11.0 — Bissection guidée — **Axe A**

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

### v1.13.0 — Hub de traduction FR, phase 1 : *diagnostic* — **Axe C**

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

### v1.14.0 — Hub de traduction FR, phase 2 : *édition & assistance* — **Axe C**

C'est la version qui fait de StarHubFR autre chose qu'un Stardrop macOS.

> *Les numéros de cette section sont des libellés de planification : les livraisons
> réelles ont glissé vers d'autres versions — C3-T1 en v1.15.0, C3-T6 après elle.
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
- [ ] **C3-T5** — Export/import d'un lot de travail (`.json`) pour traduire à plusieurs,
      puis fusion contrôlée. · **M**
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

- [ ] **C3-T7** — **Secours de traduction en ligne (DeepL)** : quand l'IA locale
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

### v1.15.0 — Profils, favoris & backups exploitables — **Axe B**

#### B3 — Profils

- [ ] **B3-T1** — Choix à la création : profil **vide** (défaut demandé) ou instantané des
      mods actifs. · **S** · *change le comportement actuel — à annoncer au CHANGELOG.*
- [ ] **B3-T2** — Favoris de mods (persistés au registre), avec « importer les favoris dans
      ce profil ». · **M**
- [ ] **B3-T3** — Duplication d'un profil. · **S**
- [ ] **B3-T4** — Diagnostic de profil au changement : mods manquants, dépendances non
      satisfaites, couverture FR (réutilise **C1-T1**). · **M**
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

- [ ] **B4-T1** — Regroupement par mod puis par version, tri (dernier backup, A→Z, Z→A),
      recherche. · **M**
- [ ] **B4-T2** — Retour utilisateur explicite après restauration (ce qui a été écrit, où). · **S**
- [ ] **B4-T3** — Garantir qu'une restauration met à jour le registre : version, écrasement
      du dossier existant, recréation s'il a disparu. · **M** · *comportement actuel non
      prouvé — commencer par un test de caractérisation.*
- [ ] **B4-T4** — **Récupérer un fichier isolé depuis une sauvegarde**, sans restaurer le mod
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

#### B2 — Ergonomie transverse

- [ ] **B2-T1** — ETA et débit pendant les téléchargements Nexus, et **panneau de downloads
      observable** : statut par téléchargement, %, vitesse, annulation, retry (inspiration :
      `DownloadPanel` de Stardop). Aujourd'hui StarHubFR ne fait que du
      `URLSession.downloadTask` fire-and-forget, sans progression live. · **M** · *§audit-stardrop*
- [ ] **B2-T2** — Poids par mod, total de `Mods/`, espace disque restant (en pied de barre
      latérale, près de l'indicateur d'état). · **M**
- [ ] **B2-T3** — Boutons de rafraîchissement sur la quarantaine et les alertes système ;
      sur la fiche mod, rafraîchissement **automatique** dès qu'un NexusID est saisi. · **S**
- [ ] **B2-T4** — Guidage quand `unrar`/`unar`/`7z` manque. *Socle déjà en place* : l'accueil
      affiche l'état d'installation de `unar` avec la commande Homebrew
      (`home_tool_unar_*`). Ce qui manque : au **moment de l'échec**, un message actionnable
      avec commande copiable — aujourd'hui une phrase anglaise codée en dur (cf. **X6**). · **S**
- [ ] **B2-T5** — Reprendre l'affichage des dates d'un mod : distinguer explicitement
      *date de création Nexus* et *date de mise à jour*, et vérifier laquelle est montrée
      où (liste, fiche, bandeau de mise à jour). · **S**
- [ ] **B2-T6** — Quota Nexus quotidien visible (header `x-rl-daily-remaining`). StarHubFR
      gère déjà le rate-limit réactif (`Retry-After`) mais n'affiche pas le quota restant —
      trivial, deux headers déjà reçus à chaque réponse. · **S** · *§audit-stardrop*
- [ ] **B2-T7** — `UpdateCautionMessage` : si un manifest installé expose ce champ
      (extension SMAPI tolérée, absente = pas d'alerte), alerter l'utilisateur **avant**
      d'écraser la version existante (breaking change annoncé par l'auteur). · **S** ·
      *§audit-stardrop*
- [ ] **B1-T3** — Pastilles d'anomalie dans la liste des mods (erreurs récentes, dépendance
      manquante, manifest illisible) alimentées par `ModErrorHistory`. · **M**

**Critère de succès** : un profil se crée, se duplique et s'applique sans surprise ; un
backup se retrouve en moins de dix secondes.

---

### v1.16.0 — Fiabilité du registre & compatibilité — **Axe A**

#### A1 — Registre robuste

- [ ] **A1-T1** — Action groupée « activer toutes les dépendances manquantes » : l'activation
      unitaire existe déjà par nœud (`DependencyTreeView.swift:124`, cf. **X3**) ; il manque
      la résolution transitive en un geste, avec récapitulatif avant application. · **M**
- [ ] **A1-T2** — Détecter un `manifest.json` illisible et proposer la réparation :
      restauration depuis backup, sinon réinstallation Nexus. La validation doit accepter
      ce que SMAPI accepte (JSON5 : commentaires, virgules traînantes) — `smapi.io/json`
      sert de référence de comportement, et les messages d'erreur doivent être aussi
      explicites que les siens. · **M**

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

- [ ] **A2-T1** — Client de l'API `smapi.io/api/v3.0/mods` : POST `ModSearchData`
      (UniqueID + version installée + update keys + version SMAPI + version du jeu) pour
      chaque mod à version valide. Réponse typée par mod : `SuggestedUpdate`,
      `CompatibilityStatus` (`Ok`/`Broken`/`Abandoned`/`Obsolete`/`Unofficial`/`Workaround`),
      `Unofficial` (URL de mise à jour non officielle), `Main`/`CustomUrl`. DTO portables
      depuis Stardop (`ModSearchEntry`, `ModEntry`, `ModEntryMetadata`).
      **Filtres obligatoires** (validés par le spike) : ne soumettre que les mods
      `HasValidVersion && HasUpdateKeys` (comme Stardop) et **normaliser les `UpdateKeys`**
      (strip espaces : `"Nexus: 20290"` → `"Nexus:20290"`, sinon le mod est invisible). · **M**
- [ ] **A2-T2** — Afficher le statut, `brokeIn` et le **lien de mise à jour non officielle /
      mod de remplacement** sur la fiche mod et dans la carte de santé. · **M**
      ⚠️ **Constat du 2026-08-01, à traiter ici** : `NexusUpdateChecker.compare(_:_:)`
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

> ⚠️ **Réserve conservée** : `smapi.io/mods` annonce lui-même ne plus être mis à jour
> exhaustivement, et son avenir est incertain. À traiter comme **complément** au
> diagnostic de log, jamais comme source unique de vérité — d'où le fallback `mods.jsonc`.

#### A3 — Métadonnées Nexus

- [ ] **A3-T1** — Recherche automatique des `NexusID` manquants (correspondance nom +
      auteur, proposition validée par l'utilisateur, jamais d'écriture aveugle). · **M** ·
      risque : quota d'API Nexus, faux positifs.

**Critère de succès** : passer de « ce mod a planté » à « ce mod est cassé depuis
SMAPI 3.0, voici son remplaçant ».

---

### v1.17.0 — Performance mesurée — **Axe D**

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

### v2.0.0 — Packs, distribution & pédagogie — **Axe E**

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

**Point d'arbitrage restant** : v1.11 (bissection) et v1.13–1.14 (traduction FR) sont
interchangeables sans dommage. La question est : *le besoin le plus urgent est-il de
réparer une modlist qui casse, ou de tenir la promesse francophone ?* La roadmap tranche
pour la première ; cet ordre se renverse en une ligne.

**Si un seul chantier devait être fait** : `C1` + `C2` (couverture + diff EN/FR) — le plus
petit incrément qui rende le positionnement défendable.

---

## 9. Suivi

- Ce fichier est la référence ; le `CHANGELOG.md` reste le journal de ce qui est livré.
- Cocher une case **au moment du commit** qui livre la tâche, en citant l'identifiant
  (`feat(i18n): couverture de traduction par mod (C1-T1)`).
- Réviser la table de réconciliation (§3) à chaque release majeure : elle perd toute
  valeur dès qu'elle ment sur l'état réel du code.
