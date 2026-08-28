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
- **Axe H — Cohérence UI** *(transverse)* : généraliser à toute l'app le langage
  visuel établi par l'onglet Découvrir (axe G) — navigation regroupée, accueil
  tableau de bord, reskin écran par écran, bibliothèque de composants vivante.
- **Axe I — Expérience utilisateur** *(après H)* : navigation optimisée et
  accessibilité en **capacités** — clavier, palette de commandes, VoiceOver.

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
| *audit* | Quota Nexus quotidien visible | **Fait** | Relevé sur toute réponse, affiché dans les réglages (**B2-T6**, pas encore publié) |
| *audit* | `UpdateCautionMessage` (alerte auteur avant mise à jour) | **À faire** | → **B2-T7** |
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
dans le VM — 8389 lignes au 2026-08-28 — que **F1-T1** désigne justement comme premier candidat à
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
      brutes. Faisable sans dépendance externe. · **M**
      ✅ **Hypothèse validée le 2026-08-28, sur le parc réel** — pas sur un échantillon.
      Sur les **1017 mods** installés, **547 ont un `config.json`** et **267 d'entre eux
      publient des clés `config.*`** dans leur `i18n/`, dont **229 déjà traduites en
      français** par les auteurs des mods.
      ⚠️ **Le chiffre qui compte pour ce que l'utilisateur voit aujourd'hui est plus
      petit** : le parc de référence est en pause à 88 %. Ventilé —
      **actifs : 125 mods, 92 configurables, 47 dans la cible dont 40 en FR** ;
      **en pause : 892 mods, 455 configurables, 220 dans la cible dont 189 en FR**.
      Le rapport est le même dans les deux populations (**51 %** contre **48 %**) : la
      règle tient, elle n'est pas un artefact de la masse en pause. Le gain visible
      immédiatement porte donc sur **47 mods**, et grandit à chaque réactivation.
      *(À la marge : 285 mods publient des clés `config.*` mais 18 n'ont pas encore de
      `config.json` — SMAPI ne l'écrit qu'au premier lancement. La cible croît.)*
      Aujourd'hui `ModConfigEditorView.swift:6` affiche `keyPath.joined(separator: " > ")` :
      la clé brute, pour tous. La mesure a dû lire du **JSON5** (commentaires en fin de
      ligne, CRLF, virgules traînantes) — 28 fichiers sur 2506 restent illisibles même
      ainsi, 1 % : l'implémentation doit se replier sur la clé brute, jamais échouer.
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

> **Le socle de C4 est déjà découpé, et dormant.** Un plan local de 67 étapes
> (`docs/superpowers/plans/2026-08-03-c4-socle-core.md`, marqué « Plan 1/3 ») détaille les
> dix types Core que C4-T1 suppose — `ConfigValue`, `ConfigDoc`, `ConfigOption`,
> `ModConfigInferrer`, `ConfigLabelResolver`, `ConfigEdit`, `ConfigValidator`,
> `ConfigWriter`. **Aucun n'existe** : les `Config*.swift` du dépôt viennent tous de
> **B3-T5**, et les plans 2/3 et 3/3 n'ont jamais été écrits. Sa tâche 1 est une
> mesure-échantillon avec décision go/no-go — précisément l'hypothèse que C4-T1 dit devoir
> valider avant engagement.

#### C5 — Hub de traduction agnostique de la langue

- [ ] **C5-T1** — Rendre `ThaiTranslationHubView` générique (langue en paramètre) et
      exposer une vue **FR** par défaut ; supprimer le drapeau `showThaiTranslationHub` ou
      le transformer en sélecteur de langue. · **M**
- [ ] **C5-T2** — Aligner README/CHANGELOG (la mention du hub thaï quitte le discours
      produit). · **S**

#### C6 — Signaux de demande de traduction (`needs:fr`)

Origine : panorama des canaux de traduction FR (2026-08-27). Sur les canaux listés, un
seul était inconnu du dépôt — les autres sont couverts (Nexus + tag `French` = **A3-T3**,
livré ; pages « What do you want VF » = mods Nexus ordinaires) ou sans API
(stardewvalley.fr, Discord FR — rien à câbler). Le dépôt GitHub
`Pathoschild/SMAPI-ModTranslationClassifier` tient des **issues taguées `needs:fr`** :
les mods sans traduction française dont l'auteur en demande une, maintenues par
l'auteur de SMAPI. C'est l'inverse exact du hub actuel, qui trouve ce qui **existe**.

- [ ] **C6-T1** — Croiser le parc avec les issues `needs:fr` : sur la fiche d'un mod
      sans traduction FR (C1 le sait déjà), dire si une traduction est **activement
      demandée** — issue ouverte, âge, lien. API GitHub publique, sans clé : mesurable
      sans passer par l'utilisateur. · **M** · *à mesurer avant d'engager :*
      - **la clé de croisement** — les issues du classifier référencent-elles les mods
        par `UniqueID` (alors le parc croise directement — contrairement à Nexus, qui
        ne rend pas l'identifiant d'un mod non installé) ou par nom de mod ?
      - **la couverture** — sur les mods du parc sans traduction FR, combien figurent
        dans le classifier (Pathoschild scanne les mods SMAPI qu'il connaît, pas tout
        Nexus). Repli si la couverture est dérisoire : ne pas livrer une pastille qui
        ne s'allume jamais.

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
- [ ] **A2-T5** — `§audit-gestionnaires` · *(faible priorité)* — Lire la base de
      compatibilité **locale** de SMAPI (`smapi-internal/metadata.json`, livrée avec
      l'installation) comme troisième source hors ligne, derrière l'API live et
      `mods.jsonc`. ⚠️ **La comparaison de bornes de version est obligatoire** : chaque
      motif y est assorti d'une clause de version, et l'apparier sans la lire signalerait
      **14 mods à tort** sur le parc de référence — pour **1 seul** réellement concerné.
      C'est ce rapport, pas la difficulté, qui fixe la priorité. · **S**

> ⚠️ **Réserve conservée** : `smapi.io/mods` annonce lui-même ne plus être mis à jour
> exhaustivement, et son avenir est incertain. À traiter comme **complément** au
> diagnostic de log, jamais comme source unique de vérité — d'où le fallback `mods.jsonc`.

> **`§audit-gestionnaires` — sort des cinq candidats.** L'audit du 2026-08-27
> ([`audit-gestionnaires.md`](audit-gestionnaires.md), versionné) annonçait en en-tête que
> ses décisions seraient marquées ici. Elles ne l'étaient pas ; elles le sont :
>
> | # | Trouvaille | Source | Sort |
> | :-- | :-- | :-- | :-- |
> | 1 | Base locale `smapi-internal/metadata.json` | NexusMods.App | **La seule encore ouverte** → **A2-T5** |
> | 2 | `MinimumApiVersion` / `MinimumGameVersion` non lus | NexusMods.App | Préventif — **0 mod** sur le parc mesuré ; à rouvrir si le compte bouge |
> | 3 | Dépendance installée sous sa `MinimumVersion` | NexusMods.App | Préventif — **0 mod**, même règle |
> | 4 | Garde-fous d'écriture (`policy.ts`) | Vortex | À reprendre **comme revue**, pas comme code → à joindre à **F2** |
> | 5 | Constantes de durée relisibles + audit des TTL | Vortex | C'est le TTL manquant de **A2-T4** |

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

### Découverte de nouveaux mods — **Axe G** · livré en **v1.25.0**

L'app sait tout faire **à partir d'un mod installé** — traductions (**A3-T3**),
suppléments (**A3-T4**) — et rien **sans point de départ**. La vitrine
« Découvrir » comble ce trou : tendances, récents, sélection FR, recherche
libre. Nexus seul (GraphQL v2) : le panorama des sources a été passé au crible
et les autres n'apportent rien de mesurable — CurseForge/ModDrop sont déjà
couverts pour les mises à jour via smapi.io, forums/Discord/Naver n'ont pas
d'API. Spec : `docs/superpowers/specs/2026-08-27-decouverte-mods-design.md`
(local, gitignoré comme les autres specs SDD).

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

**Livré au-delà des trois tâches** (2026-08-28, retours d'écran successifs) :
filtre par **catégorie** appliqué au serveur — `categoryName` est un champ de
`ModsFilter` que le relevé du spike avait manqué, et filtrer les 20 mods reçus
n'aurait rien valu (50 mods de tendances = 15 catégories) ; **pagination**
(`offset`, « voir plus » par paliers de 4, le réseau livrant par 20) ; vitrine
**francophone** (une traduction n'y figure que taguée `French` — au prix
mesuré de 3 traductions françaises sur 80 écartées à tort) ; et une **refonte
UI** : barre d'outils unique, cartes en 16/9 pleine largeur, états dégradés
porteurs de l'action qui les lève, fiche à bandeau et bande de chiffres.

**Risques** : l'API GraphQL v2 n'est pas documentée (peut changer sans préavis
→ parsing tolérant, échec propre) ; les recommandations « selon mon parc »
n'ont aucune donnée source — la v1 ne sert que des filtres (tendance × FR ×
non installé), jamais des prédictions.

---

### Cohérence UI : un seul langage pour toute l'app — **Axe H** · à faire

L'onglet Découvrir (axe G) a établi de fait un langage — cartes en grille
adaptative, états qui portent l'action qui les lève, comptes honnêtes, un
geste par intention. Le reste de l'UI date de plusieurs époques : tokens
rétrofités en v1.7.0, styles ad hoc par vue, zone de statut séparée au-dessus
des groupes de la barre latérale, accueil « identité + réglages » qui ne
montre pas ce qui demande attention. Quatre douleurs confirmées au cadrage
(2026-08-28) : incohérence entre onglets, navigation encombrée (14 entrées),
liste des mods à 966 mods, accueil peu utile. Spec complète — huit principes
P1–P8, lots, critères mesurables — :
`docs/superpowers/specs/2026-08-28-refonte-ui-design.md` (local, gitignoré
comme les autres specs SDD).

Approche validée : **le châssis d'abord** — design system extrait de
Découvrir et bibliothèque de composants vivante (projet claude.ai/design,
dossier `design/` versionné), puis navigation + accueil, puis reskin écran
par lot, une release par lot. Périmètre : visuel + navigation —
**aucune fonctionnalité nouvelle**, aucun parcours interne refondu.

- [ ] **H-T1** — **Châssis** : tokens manquants (`Grid`, `Metrics`, `Shadow`,
      `Icon`), extraction des 7 composants de `DiscoverView` vers
      `Views/Components/` (`ModCard`, `StateCard`, `ErrorBanner`, `StatStrip`,
      `HeroHeader`, `SectionHeader`, `CategoryBadge`), Découvrir bascule dessus
      **sans changement visuel** (l'extraction sans bascule créerait des copies
      divergentes), bibliothèque `/design` créée (Foundations + Components),
      `UX_UI_Specifications.md` retiré avec bandeau de renvoi. · **M**
- [ ] **H-T2** — **Navigation** : un seul style d'item de sidebar, badge
      capsule sur l'item (motif Mail) — fin de la zone de statut séparée ;
      4 groupes : Bibliothèque / Parties / Santé & secours / Application.
      Aucune destination supprimée ni enterrée, identifiants d'onglet
      inchangés (pas de migration d'état). · **S**
- [ ] **H-T3** — **Accueil tableau de bord** : bande des 4 compteurs
      cliquables (mises à jour, alertes SMAPI, quarantaine, parc — un zéro
      affiché est une information), carte de lancement (mode + profil + dossier
      suivis d'un coup d'œil), parc et socle en version constat ; identité et
      réglages déménagent (version, crédits, dossier, SMAPI détaillé →
      Réglages ; « Installer SMAPI » reste sur l'accueil quand SMAPI manque). · **M**
- [ ] **H-T4** — **Mods, pilote du reskin** : toolbar unifiée au motif
      Découvrir (un seul geste par intention), rangée à hauteur réservée avec
      état codé glyph + couleur + barre d'accent (jamais la couleur seule),
      grille optionnelle réutilisant `ModCard` telle quelle, fiche
      `HeroHeader` + `StatStrip` où l'action praticable est la proéminente. · **L**
- [ ] **H-T5** — **Lot Parties** : profils en cartes à chiffres clés (jamais
      un formulaire nu), sauvegardes au même motif. · **M**
- [ ] **H-T6** — **Lot Santé & secours** : alertes système, quarantaine,
      backups ×2 — gravité toujours glyph + couleur, rapports en tableaux
      lisibles. · **M**
- [ ] **H-T7** — **Lots Journaux & Réglages** : reskin léger des journaux
      (la perf est déjà faite), Réglages absorbe les déménagés de l'accueil
      en sections unifiées. · **S**
- [ ] **H-T8** — **Hub de traduction** : reskin de continuité seulement —
      monde à part, déjà structuré. · **M**
- [ ] **H-T9** — **Closage** : audit de fidélité (Découvrir visuellement
      identique à la v1.25.0 malgré les évolutions du système), bibliothèque
      `/design` complétée (Screens), nettoyage des vestiges. · **S**

**Risques** : cohabitation ancien/nouveau style pendant le chantier (bornée :
chaque lot livré est cohérent avec le système) ; `MainView` remet ses états
de détail à `nil` au changement d'onglet — tout nouvel écran suit le motif
« sheet interne à la vue » de Découvrir ; l'accueil puise dans le God module
(8389 lignes) → touches minimales, logique pure côté `Models/`.
**Critère de succès** : plus aucun écran ne parle sa langue propre — mesurable :
zéro valeur de style hors tokens dans les vues migrées, un seul style d'item
de sidebar, Découvrir inchangé au closage.

---

### Expérience utilisateur : navigation & accessibilité — **Axe I** · à faire, **après H**

Ce que H pose en **règles** (cibles ≥ 18×18, jamais la couleur seule, contraste
vérifié), I le transforme en **capacités** : naviguer au clavier, piloter à la
voix, aller partout sans souris. L'ordre n'est pas négociable pour une raison
d'économie : la bibliothèque de composants issue de H est le point d'entrée
unique — chaque trait d'accessibilité s'y pose **une fois par composant**,
au lieu d'une fois par écran sur une UI bientôt remplacée.

Cadrage volontairement léger ici : la spec SDD complète se fera à son tour,
sur les composants réels. Les tâches ci-dessous sont des hypothèses de
travail, pas des engagements.

- [ ] **I-T1** — Raccourcis clavier d'onglets (⌘1…⌘9) et de vues, focus
      visible et géré (entrer/sortir des fiches, des feuilles, de la liste). · **S**
- [ ] **I-T2** — Palette de commandes ⌘K : mods, profils, onglets et actions
      (installer, mettre à jour, restaurer) appelables depuis partout. · **M**
- [ ] **I-T3** — VoiceOver : labels, traits et ordre de lecture sur chaque
      composant de la bibliothèque, écrans majeurs vérifiés à l'oreille. · **M**
- [ ] **I-T4** — Réglages d'accessibilité système respectés (réduire les
      animations, réduire la transparence, augmenter le contraste) et taille
      de texte réglable dans l'app. · **M**
- [ ] **I-T5** — Audit de navigation : chemins cliqués mesurés avant/après sur
      des tâches représentatives (mettre à jour un mod, restaurer un backup,
      changer de profil). · **S**

**Risques** : démarrer I avant H imposerait de refaire l'accessibilité sur
des écrans voués au remplacement ; la palette de commandes touche au routage
de `MainView` — le piège des états de détail remis à `nil` au changement
d'onglet s'applique à chaque saut.
**Critère de succès** : les tâches représentatives s'exécutent au clavier
seul, et VoiceOver restitue chaque écran majeur sans piège.

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

- [ ] **F1** — **Découper le God module.** `StarHubTHViewModel.swift` fait **8389 lignes**
      (mesuré le 2026-08-28 ; **4278** au relevé initial du 2026-07-30, soit **+96 %** —
      le module grossit plus vite qu'on ne l'allège) et concentre profils, scan, Nexus,
      logs, configs et sauvegardes.
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
      écritures dans `Mods/`. · **M** · *à faire après F1-T1 : auditer 8389 lignes de VM
      monolithique coûte plus cher que d'auditer des types séparés.*
      ⚠️ **Une partie de l'inventaire existe déjà** :
      [`audit-swift-2026-08-05.md`](audit-swift-2026-08-05.md) — 309 lignes, ~72 findings
      recensés, les 9 hauts corrigés au 2026-08-11 — couvre la surface de sécurité et une
      part de la performance. Il porte son propre avertissement de péremption (il a listé
      comme ouverts pendant cinq jours trois findings corrigés entre-temps) : `git log -S`
      sur le symbole avant d'attaquer une ligne. **F2 le complète, il ne le refait pas.**
      À y joindre le candidat **#4 de `§audit-gestionnaires`** : la liste explicite de
      garde-fous d'écriture de Vortex (`policy.ts`), à reprendre **comme grille de revue
      de nos chemins d'écriture**, pas comme code à porter.
- [ ] **F5** — **StarHubFR et StarHubTH écrivent dans les mêmes données.** Le fork a changé
      le nom du produit, pas son identité : le bundle reste `com.appleboiy.StarHubTH` et
      les fichiers vivent sous `~/Library/Application Support/StarHubTH/`. Deux
      installations sur la même machine partagent donc **31 clés de préférences**,
      l'entrée de Trousseau qui porte la clé Nexus, et l'enregistrement du protocole
      `nxm://` — qui revient à la dernière application enregistrée. Mesuré le 2026-08-26,
      revérifié dans le code le 2026-08-28 : rien n'a bougé.
      *Provenance : `docs/superpowers/plans/2026-08-26-migration-identite-starhubfr.md`
      (local, gitignoré). Les faits qui décident sont recopiés ci-dessus ; le plan ne garde
      que le détail des 41 étapes.*
  - [ ] **F5-T1** — *(phase 1, livrable seule)* Déplacer les données de fichiers vers
        `~/Library/Application Support/StarHubFR/` derrière un **accesseur unique** qui
        migre à la première lecture — **pas au lancement** : il n'existe aucun point de
        lancement assez tôt pour garantir que rien n'a encore lu l'ancien chemin. · **M**
  - [ ] **F5-T2** — *(phase 2, livrable seule)* Changer l'identifiant de bundle, ce qui
        sépare préférences, Trousseau et `nxm://`, puis recopier l'ancien domaine vers le
        nouveau. Seule, T2 laisse les fichiers en commun ; seule, T1 laisse les préférences
        et le Trousseau en commun. · **M**

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

**G — Découverte (2026-08-27 → 2026-08-28).** Spec rédigé puis relu
sceptiquement (deux erreurs de fait corrigées), spike mené sans clé — l'API
GraphQL v2 répond non authentifiée — puis les trois tâches livrées d'affilée.
Ce que le spike a coûté de ne pas avoir vu : son relevé de `ModsFilter` ne
listait que 4 champs sur 27, et il a fallu réinterroger l'introspection le
lendemain pour trouver `categoryName`. **Réinterroger `__type` en entier avant
de conclure qu'un filtre n'existe pas** — en curl, jamais en python
(Cloudflare, code 1010). Reste ouvert : les vignettes en cache d'une version
antérieure ne portent pas `categoryId` (pastille absente jusqu'au premier
rafraîchissement), et `languageName` existe au filtre — piste pour la sélection
FR sans passer par le tag.

---

## 9. Suivi

- Ce fichier est la référence ; le `CHANGELOG.md` reste le journal de ce qui est livré.
- Cocher une case **au moment du commit** qui livre la tâche, en citant l'identifiant
  (`feat(i18n): couverture de traduction par mod (C1-T1)`).
- Réviser la table de réconciliation (§3) à chaque release majeure : elle perd toute
  valeur dès qu'elle ment sur l'état réel du code.
- **Un plan ou une spec de `docs/superpowers/` ne vaut pas suivi.** Ce dossier est
  gitignoré : il n'existe que sur le poste qui l'a écrit. Toute décision qu'il porte et
  qui engage la suite doit être recopiée **ici, avec ses faits** — un renvoi seul
  disparaît au premier clone. Contrôle du 2026-08-28 : sur 29 plans et 27 specs,
  4 fichiers étaient cités depuis ce document, et le plan de migration d'identité
  (41 étapes, deux phases) n'y figurait nulle part → repris en **F5**.
- **Les cases des plans de `docs/superpowers/` ne sont jamais cochées.** Aucune, sur
  aucun plan — y compris celui de la découverte, sortie en v1.25.0. Leur état `- [ ]`
  ne dit rien de ce qui est fait ; seuls ce fichier et le code font foi.
- **`UX_UI_Specifications.md` est périmé et orphelin.** Il s'épingle au commit `a3937f6`
  (v1.6.0), soit 19 releases de retard, et aucun document du dépôt ne le cite. À ne pas
  utiliser comme source : à réécrire contre le code, ou à retirer.
