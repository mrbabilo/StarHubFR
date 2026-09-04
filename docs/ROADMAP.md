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
- [ ] **X25** — **340 dossiers de sauvegarde orphelins restent sur le disque**, séquelle
      de X23 (321) et de X24 (19) : vides ou ne portant qu'un dossier vide, ~0 octet, invisibles dans
      l'app. Un ménage automatique fondé sur « non référencé par l'index » est
      **dangereux tel quel** : `loadIndex()` rend un index **vide** dès que le fichier
      est illisible ou mal décodé — et ce magasin porte les traces d'écritures
      difficiles (un `install_metadata.json.sb-*` traîne à côté). Tout le parc
      passerait alors pour orphelin. Il inverserait aussi la règle que ce fichier
      énonce lui-même : *une suppression ne se décide jamais sur une absence.* Gain
      ≈ 0 octet : à traiter comme un nettoyage explicite, jamais comme un automatisme
      silencieux. · **S**
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
- [ ] **X28** — **Un `__MACOSX` niché dans un mod perd ses fichiers mais garde son
      dossier.** Le balayage profond ne déplace que des fichiers (`if isDir { continue }`)
      et la passe de premier niveau ne traite `OSJunk.folders` qu'à la profondeur 1 :
      un `__MACOSX` à l'intérieur d'un dossier de mod voit ses fichiers mis en
      quarantaine un par un, et la coquille reste indéfiniment. Zéro exemplaire sur le
      parc aujourd'hui — même classe de latence que X27. · **S**
- [ ] **X29** — **La détection de doublons sur disque n'a aucun appelant en
      production** : le ViewModel passe `detectDuplicates: false` et utilise la
      version en mémoire. La version disque garde donc sa propre lecture de
      manifeste (regex de commentaires bloc + `.json5Allowed`) au lieu de
      `ManifestJSON.decode`, quatrième copie d'une règle consolidée ailleurs. La
      seule divergence nommable — la marque d'octets, présente sur **142 des 1 095
      manifestes** — a été testée : elle ne se reproduit pas, `JSONSerialization`
      tolère la marque. Deux tests de parité épinglent le comportement ; unifier
      serait un changement de comportement sur un chemin sans appelant, donc à ne
      faire qu'en même temps qu'on lui en donne un (ou qu'on le retire). · **S**
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
- [ ] **X31** — **Le marqueur de version SMAPI peut mentir indéfiniment.**
      `getInstalledVersion` lit d'abord `smapi-internal/.starhubth-installed-version`,
      écrit par l'app seule. Une mise à jour de SMAPI faite autrement (son propre
      installateur) ne le réécrit pas : l'app annonce alors éternellement l'ancienne
      version et propose une mise à jour déjà faite. Le repli — la première ligne de
      `SMAPI-latest.txt` — dirait vrai mais n'est jamais consulté. Piste : comparer
      les dates des deux sources et croire la plus récente (le journal peut être en
      retard sur une installation dont le jeu n'a pas encore été lancé). **Non
      mesuré** : sur le parc, marqueur et journal disent tous deux `4.5.2`. · **S**
- [ ] **X32** — **L'installateur SMAPI accepte `--install` / `--uninstall` /
      `--game-path`.** Vérifié dans le binaire 4.5.2 (`"You can't specify both
      --install and --uninstall command-line flags."`, `'You specified --game-path "'`).
      L'app, elle, répond à l'aveugle à une séquence de questions dont l'ordre est
      supposé stable — c'est ce qui rend X30 possible. Les drapeaux ne suppriment pas
      la question du jeu de couleurs (mesuré : elle est posée quand même), mais ils
      retireraient le chemin et l'action de la file d'attente. À faire avec une vraie
      installation de contrôle, impossible depuis un agent. · **M**
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
- [ ] **X43** — **Le dialogue de conflit de configuration est mort dans sa
      totalité.** `ConflictType.configFilesConflict` et `.dependencyMissing` n'ont
      **aucun site de construction** ; `ConfigResolution` (`keepExisting`, `useNew`,
      `merge`) n'est jamais posé — `InstallSelection.configResolution` vaut `nil` à
      tous les sites de l'UI, qui se contente de le recopier, et `ModZipInstaller` ne
      le lit nulle part ; `ConflictResolution.keepExisting`/`.useNew` ne sont
      construits nulle part non plus (juste traités dans un `switch` exhaustif,
      L. 1113). C'est le **résidu d'une bascule de conception** : demander à
      l'utilisateur ce qu'il veut faire de son `config.json` a été remplacé par la
      préservation automatique (`snapshotUserConfigs`, L. 1108), qui est le bon
      comportement et fonctionne. Rien n'est cassé ; le retrait touche une signature
      de Core (`InstallSelection`), quatre sites de `InstallPreview` et douze lignes
      de tests — à faire d'un bloc, ou pas du tout. · **S**
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
- [ ] **X45** — **Le dépliage des packs a encore dix copies manuelles.**
      `flattenedMods` affirme dans son propre en-tête avoir remplacé les 22
      réécritures de 2026-08-01 ; il en reste **dix** : trois portent sur un tableau
      complet et pourraient l'appeler directement (`StarHubTHViewModel` L. 8404,
      8648, 8714), sept sur un mod isolé (`mod.isGroup ? (mod.children ?? []) :
      [mod]` — VM L. 4421 et 7326, `BisectionRunner` L. 395 et 416,
      `ModFolderRepairer` L. 359, `ModGridCardValues` L. 55), forme qu'aucune API ne
      couvre aujourd'hui. **Vérifié : elles ne divergent pas** — toutes écrivent
      `?? []`. C'est donc un constat de forme, pas un bug ; il vaut surtout pour ce
      qu'il annonce, un `ModItem.components` manquant. · **S**
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
- [ ] **X47** — **Le `break` du premier lot en échec coûte les lots suivants.** Un
      503 ponctuel sur le lot 3 de 8 renonce aux lots 4 à 8, que rien n'incriminait :
      795 mods repartent en reprise Nexus (quota payant) là où un simple passage au
      lot suivant les aurait couverts gratuitement. Le fichier assume ce choix (« ne
      pas cogner une API publique gratuite »), et il protège d'une rafale d'erreurs.
      Redessiner la politique — continuer, ou réessayer le lot une fois avec un
      retrait — est une décision de conception, pas un correctif d'audit. X46 rend
      au moins le fait visible et réessayable. · **S**
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
- [ ] **X49** — **Deux recherches Nexus lancées coup sur coup peuvent revenir dans
      le désordre.** `searchDiscovery(name:)` écrase `discoverySearch` sans vérifier
      que le terme demandé est encore celui qu'on attend. Le voisin immédiat,
      `loadMoreDiscoverySearch`, porte pourtant la garde (`now.term == current.term,
      now.loaded == current.loaded`) — une règle présente d'un côté, absente de
      l'autre. Atténué par le déclenchement : la recherche part sur Entrée ou sur le
      bouton loupe, pas à chaque frappe, et un champ vidé ne relance rien. Il faut
      donc deux soumissions rapprochées, et le résultat affiché reste cohérent avec
      l'étiquette qu'il porte — simplement pas avec le dernier terme tapé. Le
      correctif demande un compteur d'époque dans le ViewModel, non testable ici : à
      faire en même temps qu'on touchera cet écran. · **S**
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
- [ ] **X54** — **Le journal annonce « profil créé » sur un simple ajout.**
      `L10n.VM.profileCreated` (« Profil « %@ » créé (%lld mods) ») est journalisé
      en quatre endroits : `createProfile` (juste), `duplicateProfile`
      (acceptable), mais aussi `addModToProfile` et `importFavorites`, qui ne
      créent rien. Demande deux clés L10n neuves, en parité `en`/`fr`. Non corrigé
      dans la passe d'audit pour ne pas mêler un ajout de clés à des correctifs de
      perte de données. · **S**
- [ ] **X55** — **Le ménage à la suppression d'un mod est partiel.** `deleteMod`
      purge `favoriteMods`, `modErrorHistory`, la référence de traduction et la
      couverture FR, mais laisse quatre magasins indexés sur le même `folderName` :
      `profileManagedConfigMods`, `modActivationTimestamps`, `nexusCustomModIds`,
      `nexusCustomCategories` — et `recentNexusInstalls`, indexé sur l'identifiant
      Nexus. Effet le plus visible : la vitrine Découverte continue d'afficher
      « Je l'ai » pour un mod installé puis supprimé dans la même session
      (`installedNexusIds()` ne fait qu'ajouter à cet ensemble, jamais retrancher —
      le patron de X38). Effet le plus gênant, mais rare : un dossier réutilisé par
      un autre mod hérite du drapeau « sa config suit le profil ». Demande une
      décision de politique (tout purger ? garder l'identifiant Nexus, qui est
      souvent le bon au réinstall ?), pas seulement du code. · **S**
- [ ] **X56** — **Trois champs du dump de compatibilité ne sont pas décodés.**
      `PathoschildCompatibilityList.Entry` lit `id`, `status`, `brokeIn`,
      `summary`, `nexusID`. Le dump (4 720 mods) en porte trois autres :
      `unofficialUpdate` (67 mods), `abandonedReason` (277) et `warnings` (24).
      Croisé avec le parc le 2026-09-04 — 1 090 identifiants, 292 connus du
      dump : **5 mods ont une mise à jour non officielle** (Bus Locations,
      Informant, SAAT ×2, Mod Update Menu), **2 ont un avertissement**
      (« use Nexus, ModDrop is NOT updated » ; « Broken on Android »), aucun n'a
      de motif d'abandon. Les cinq premiers sont des correctifs communautaires
      installables pour des mods que rien ne signale aujourd'hui — exactement le
      « et maintenant, quoi ? » que l'écran de diagnostic doit porter. · **M**
- [ ] **X57** — **La bascule en masse agit sur le parc entier, depuis une liste
      filtrée.** Le bouton « Tout activer / Tout désactiver » vit dans
      `ModListView` — qui a une recherche, des catégories et une pagination à 15
      — mais `toggleAllMods` parcourt `mods` en entier, **949 dossiers de tête**.
      Filtrer sur « Content Patcher » puis cliquer « Tout désactiver » désactive
      le parc. Stardrop a résolu exactement ça le 2026-09-01 (`c630c11`), et
      formule bien la règle : *« bulk actions run through this so that what the
      user is looking at is what they act on »*, filtre de source, recherche,
      filtres actif/inactif et masqués sous une règle unique, évaluée sur l'état
      courant plutôt que relue de la vue. Voir `docs/SOURCES.md` §5. · **M**
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
      **Vérifié sur le jeu réel le 2026-09-03** (audit tranche E) : les 9 tables sont
      présentes et appariées, et **aucune description ne fuit** dans le glossaire —
      les 85 valeurs retenues portées par une clé qui n'est pas un `_Name` ont été
      relues une à une, toutes de vrais noms d'objet. Ne pas refaire cette mesure.
      **Son appariement, lui, était lent** : `matchEntries` cherchait les 1 126 termes
      dans chaque valeur (9,04 ms), désormais indexés par premier mot (`dc052a6`) —
      voir le constat joint à **F3** pour ce qui reste.
- [ ] **C3-T5** — **Partiel ✅** — Export/import d'un lot de travail (`.json`) pour
      traduire à plusieurs, puis fusion contrôlée. · **M**
      ⚠️ **Corrigé en séance le 2026-09-03** : préparer un lot figeait le fil principal
      **149 s** sur le plus gros mod à traduire du parc, l'import autant (il reconstruit
      le même lot). Cause : l'appariement du glossaire, corrigé sous **C3-T4**. Il reste
      3,2 s de fil principal nu, sans progression — porté en **F3**, pas ici.
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

> **Deux populations, deux sources — c'est la distinction qui manquait ici.**
> Un **content pack** décrit ses options dans un schéma posé sur le disque ; un **mod
> C#** ne décrit rien nulle part, et ses libellés ne s'attrapent que par son `i18n/`.
> Établi le 2026-08-28 par décompilation et mesure → `§audit-config-menus`,
> [`audit-config-menus.md`](audit-config-menus.md). **Prendre C4-T4 avant C4-T1.**

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
- [ ] **C4-T1** — *(voie secondaire — pour les mods C#, qui n'ont pas de schéma)*
      Étiqueter les champs de `config.json` avec les libellés `config.*` que le mod publie
      dans son `i18n/` (en FR si disponible), au lieu des clés brutes. · **M**
      ⚠️ **Mesure du 2026-08-28, qui remplace celle du matin** — la première comptait les
      mods *ayant des clés `config.*`*, pas ceux dont les clés **retombent** sur le
      `config.json`. Règle appliquée : comparer la **tige** (clé i18n privée du préfixe
      `config.` et du suffixe `name|description|tooltip|desc|label|title`) à la clé de
      configuration, insensible à la casse. Résultat —
      **actifs : 47 mods candidats, 782 clés dont 304 étiquetées (39 %) ; 25 mods en
      tirent au moins un libellé, 13 la totalité.** Parc entier : 258 candidats,
      4468/6118 clés (73 %), 192 partiels, 140 complets.
      **Le plafond est structurel** : une option GMCM porte un `FieldId` choisi par
      l'auteur, sans lien avec la clé du `config.json`, et rien sur le disque ne les
      relie — 6172 clés `config.*` du parc ne retombent sur aucune clé de configuration.
      *(L'écart 39 % / 73 % n'est pas expliqué ; 47 mods actifs, échantillon trop petit
      pour en tirer une règle.)*
      Aujourd'hui `ModConfigEditorView.swift:6` affiche `keyPath.joined(separator: " > ")` :
      la clé brute, pour tous.
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

> **Le socle de C4 est déjà découpé, et dormant.** Un plan local de 67 étapes
> (`docs/superpowers/plans/2026-08-03-c4-socle-core.md`, marqué « Plan 1/3 ») détaille les
> dix types Core que C4-T1 suppose — `ConfigValue`, `ConfigDoc`, `ConfigOption`,
> `ModConfigInferrer`, `ConfigLabelResolver`, `ConfigEdit`, `ConfigValidator`,
> `ConfigWriter`. **Aucun n'existe** : les `Config*.swift` du dépôt viennent tous de
> **B3-T5**, et les plans 2/3 et 3/3 n'ont jamais été écrits. Sa tâche 1 est une
> mesure-échantillon avec décision go/no-go — précisément l'hypothèse que C4-T1 dit devoir
> valider avant engagement.
>
> ⚠️ **Le plan a vieilli, et deux de ses dix types sont à abandonner** (2026-08-28) :
> `ConfigValue` fait doublon avec **`ConfigJSONTree.Value`**, livré depuis par B3-T5 et
> supérieur (ordre des clés retenu, littéral numérique gardé en `String`, tolérance
> calquée sur Newtonsoft) — le reprendre créerait une quatrième copie divergente.
> `ModConfigInferrer` n'a **aucune matière** : sur les 547 `config.json` voisins d'un
> `manifest.json`, **zéro** porte un commentaire hors chaîne. Les `ValueSpan` que le
> plan prévoyait pour préserver ces commentaires ne protègent donc rien ici ; ce qui
> mérite d'être préservé, c'est l'**ordre des clés**, et `ConfigJSONTree` le fait déjà
> — voir **C4-T5**.

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
> | 5 | Constantes de durée relisibles + audit des TTL | Vortex | C'était le TTL manquant de **A2-T4** — livré le 2026-08-31 |

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

Trois choses existent déjà et ne sont **pas** à refaire : les collisions de raccourcis
(**C4-T2**), les doublons d'`UniqueID` (`ModDuplicateIndex`), et le verdict de
compatibilité **mod ↔ SMAPI** (**A2**). Ce qui manque est l'autre axe : **deux mods qui
réclament la même ressource**, ce que ni SMAPI ni le manifeste ne disent.

> 🧪 **Deux spikes, 2026-08-29 — et ils ont retourné l'ordre des tâches.**
>
> **Ce que Content Patcher fait vraiment** (décompilation IL `ikdasm` de
> `ContentPatcher.dll`, méthode d'`audit-config-menus.md`). Sa propre phrase :
> *« Two content packs want to load the 'X' asset with the `Exclusive` priority
> (A and B). **Neither will be applied.** »* Trois enseignements :
> 1. **aucun des deux ne s'applique** — l'asset reste vanilla ; ce n'est pas
>    « le second perd » ;
> 2. le conflit ne vaut que pour la priorité `Exclusive`. Vérifié des deux côtés :
>    `AssetLoadPriority.Exclusive = 0x7FFFFFFF` dans SMAPI, et
>    `PatchLoader::TryParsePriority` reçoit exactement ce défaut — **un `Load` sans
>    `Priority` est exclusif**, un `Load` qui en déclare une ne l'est plus ;
> 3. **Content Patcher journalise cette phrase**, mot pour mot.
>
> **Ce que l'analyse statique donne vraiment.** L'estimation est passée par
> **18 → 6 → 12 → 3** au fil des vérifications, chacune la corrigeant à la baisse :
>
> | | cibles `Load` lisibles | paires |
> | :-- | --: | --: |
> | `content.json` seuls, sans les conditions | 1 358 | 18 |
> | en écartant les revendications conditionnelles | 1 358 | 6 |
> | en suivant les `Include` (**273 des 536 packs en usent**) | **8 207** | 12 |
> | en tenant compte de `Priority` (**812 patches en déclarent une**) | 8 207 | **3** |
>
> Les trois paires réelles ont toutes au moins un côté en pause : sur le profil
> actif, **zéro**. Angles morts comptés : 31 `Include` vers un fichier absent
> (3 mods), 339 fichiers illisibles, 1 280 cibles à jetons `{{…}}`.
>
> **Ce que les auteurs déclarent** (200 descriptions Nexus tirées au sort) :
> 30 mentionnent la compatibilité, **6 nomment un mod précis**, 2 à 3 de ces mods
> sont installés → extrapolé, 8 à 11 paires sur le parc. Un cas vivant :
> « Make Gunther Real » écrit *« inherently NOT compatible with SVE »*, et
> `[CP] Stardew Valley Expanded` est actif. Mais un regex naïf a **20 % de
> précision** (24 des 30 mentions désignent une catégorie, ou sont des négations),
> et l'ancrage par lien Nexus échoue : les liens voisins d'une mention sont
> surtout la liste des mods **compatibles**.
>
> 🔴 **Conséquence sur l'ordre.** L'analyse statique est la seule qui *prévient*,
> mais elle coûte le plus cher (récursion des `Include`, sémantique des priorités,
> 13 Mo de JSON) pour **trois paires dormantes**. Elle passe donc en dernier.

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
- [ ] **A5-T4** — **L'analyse statique des cibles disputées** — repoussée, et cadrée
      par le spike : suivre les `Include` récursivement (garde anti-boucle, fichiers
      absents comptés), lire `Priority`, ne tenir pour **certain** que deux `Load`
      inconditionnels et exclusifs sur la même cible. Réutiliser `ConfigJSONTree.parse`
      (analyseur tolérant déjà écrit pour C4) plutôt qu'un second lecteur JSON. La
      signature de scan doit inclure la **date de modification** des `content.json` :
      une mise à jour de mod les réécrit sans changer ni le nom du dossier ni son
      état. · **L**
- [ ] **A5-T5** — **Élargir le signal**, une source à la fois et chacune mesurée avant
      d'être codée : les 339 fichiers illisibles, les 1 280 cibles à jetons, et les
      `EditData`/`EditImage` sur une même entrée. · **L** ·
      ⚠️ *Deux `EditImage` sur la même cible **se composent** le plus souvent : crier au
      conflit là où Content Patcher compose ferait plus de bruit que de service.*

**Critère de succès** : passer de « ce mod a planté » à « ce mod est cassé depuis
SMAPI 3.0, voici son remplaçant » — et, avant d'activer un mod, savoir ce qu'il va
écraser.

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

- [x] **H-T1** — **Châssis** : tokens manquants (`Grid`, `Metrics`, `Shadow`,
      `Icon`), extraction vers `Views/Components/` des 6 composants de
      `DiscoverView` (`ModCard`, `StateCard`, `ErrorBanner`, `StatStrip`,
      `HeroHeader`, `SectionHeader`) et de `CategoryBadge` — défini dans
      `ModListView.swift`, déjà consommé par les deux vues —, Découvrir bascule dessus
      **sans changement visuel** (l'extraction sans bascule créerait des copies
      divergentes), bibliothèque `/design` créée (Foundations + Components),
      `UX_UI_Specifications.md` retiré avec bandeau de renvoi. · **M**

> **H-T1 livré (2026-08-28).** Huit composants dans `Views/Components/` —
> `CategoryBadge` déménagé de `ModListView`, plus `StateCard`, `ErrorBanner`,
> `SectionHeader`, `NeutralBadge`, `ModCard`, `HeroHeader`, `StatStrip` (le
> cadrage en annonçait 6 + 1 : le badge neutre « FR » de la vitrine s'est
> révélé être un composant à part entière). Quatre groupes de tokens
> (`Grid`, `Metrics`, `Shadow`, `Icon`) sous test SPM — 1647 tests verts,
> contre 1641. `DiscoverView` bascule dessus sans changement visuel et passe
> de 675 à 519 lignes ; **plus aucune taille de police littérale** n'y
> subsiste (2 avant, 0 après) — le critère de succès n°1, atteint pour cette
> vue. Cliquet des conventions rendu **à sa valeur exacte d'avant le lot**,
> sans `--update`. Bibliothèque visuelle versionnée dans `design/`
> (artboards `.dc.html` + canevas) ; `UX_UI_Specifications.md` retiré au
> profit d'un renvoi (1318 lignes → 21).
>
> **Quatre choses apprises en chemin, qui coûteraient à qui les réapprendrait :**
> 1. Le token d'ombre **doit être typé** `(radius: CGFloat, y: CGFloat)` :
>    sans annotation Swift en infère des `Int` que `.shadow()` refuse.
> 2. `thumbRatio` ne se teste **pas** à l'identique — `#expect` a rendu
>    `false` sur deux valeurs s'imprimant toutes deux `1.7777777777777777`.
>    Une tolérance dit ce qu'on veut savoir. (Même famille de piège que le
>    `#expect` de B2-T8.)
> 3. Éclater le `switch` d'`ErrorBanner` en trois branches rendant chacune
>    son bandeau **a arrêté le gate** : deux des trois cas portent la même
>    action, la duplication a fait monter le cliquet de 3. L'original
>    repliait déjà ces deux cas.
> 4. Aucune des 26 teintes de catégorie n'atteint 4,5:1 sur les **deux**
>    thèmes (mesuré : « Bétail et animaux » 4,56 en clair / 2,18 en sombre,
>    « Cultures » 2,43 / 3,95). La couleur étant la même des deux côtés,
>    c'est structurel. Le sens tient — le nom est toujours écrit —, la
>    lecture non. → **I-T3**.
>
> **Trois exceptions assumées**, à reprendre plus tard :
> `InferredTagBadge` (`ModListView`) ne rend pas comme `NeutralBadge` —
> police, fond et couleur de texte diffèrent : les fusionner serait un
> changement visuel, c'est au lot **H-T4** de le faire. L'en-tête de
> `searchResults` garde sa forme propre pour la même raison. Et le bouton de
> fermeture de `HeroHeader` reste sous la cible de 18×18 pt exigée par la
> spec §7, sans `help()` : l'agrandir déplacerait le glyphe et le libeller
> demanderait une chaîne nouvelle, deux choses interdites en phase 0 →
> **I-T3**.
>
> **À vérifier à l'écran (onglet Découvrir), avant d'ouvrir H-T2 :**
> 1. **Sélection française** — les cartes sans vignette gardent la même
>    hauteur que leurs voisines, la rangée ne décale pas (place réservée).
> 2. **Pastille « installé »** sur une vignette claire — toujours vert plein,
>    texte blanc, ombre visible ; elle ne doit pas s'être éclaircie.
> 3. **Sans clé d'API** — le bandeau orange s'affiche avec « Ouvrir les
>    réglages », et les sections montrent leur carte d'état avec son action.
> 4. **Un libellé de catégorie long** — « Animaux de compagnie / Chevaux »,
>    le plus long des 26 — dans une carte à la largeur minimale : la pastille
>    ne doit pas pousser les endossements hors de la ligne.
> 5. **La fiche d'un mod** — bandeau à la même hauteur, dégradé identique, la
>    croix de fermeture au même endroit, et les quatre chiffres alignés en
>    colonnes égales.
> 6. **Liste des mods** — la pastille de catégorie y est inchangée
>    (`CategoryBadge` a déménagé, pas changé).
>
> **Vérifié à l'écran le 2026-08-28 : rien à signaler.** Les six points sont
> passés — places réservées tenues sur la sélection française, pastille
> « installé » inchangée, états et bandeau de panne rendus avec leur action,
> le plus long libellé de catégorie logé dans une carte à 240 px, fiche et
> liste des mods identiques. **La phase 0 tient sa revendication : aucun
> changement visuel.** L'audit de fidélité du closage (H-T9) part donc d'une
> base constatée, pas supposée.
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

> **H-T2 et H-T3 livrés (2026-08-28, phase 1 du chantier).**
>
> **H-T2** : un seul `SidebarItem` pour les 13 destinations, quatre en-têtes
> (`main_group_*`), badge capsule sur l'item — la zone de statut séparée
> n'existe plus. Identifiants d'onglet inchangés : aucune migration d'état.
> Le cliquet monte de +1/+1, le coût exact du quatrième en-tête, relevé avec
> le commit. Les trois items badgés gagnent au passage un survol et le trait
> VoiceOver `.isSelected` que l'ancien style ne leur donnait pas — dans le
> scénario ci-dessous.
>
> **H-T3** : les Réglages absorbent dossier du jeu, gestion SMAPI, extensions
> cœur et crédits (la version de l'app y vivait déjà depuis la v1.26.0).
> L'accueil devient tableau de bord : bande des 4 compteurs toujours rendus,
> zéros compris, chacun menant à son onglet ; carte de lancement à trois
> états, dont les deux empêchés portent l'action qui les lève. Bannière,
> avatar et nom d'utilisateur partent ; « Installer SMAPI » reste sur
> l'accueil, avec sa progression. `HomeView` 408→391 lignes et **plus aucun
> littéral `.system(size:)`** (8 avant) — le critère n°1 tenu sur cette vue.
> Le cliquet monte de +35/+15, relevé avec le commit : c'est le coût du
> tableau de bord neuf et des sections constat (accueil) / commandes
> (Réglages) que la spec veut présentes deux fois — pas une duplication
> oubliée ; les clés `main_game_management`, `main_system`, `main_online` et
> `home_version_string` sont retirées des deux locales.
>
> **Reste ouvert, repris par le scénario puis H-T9** : le `Group { }` de
> `SettingsView` (plafond ViewBuilder atteint à 12 enfants) et son
> commentaire ; les exceptions assumées de H-T1 (`InferredTagBadge`, en-tête
> de recherche, cible 18×18 de `HeroHeader`) restent candidats H-T4/I-T3.
>
> **À vérifier à l'écran, avant d'ouvrir H-T4 :**
> 1. **Les 13 destinations sont là**, dans quatre groupes, et chacune ouvre bien
>    sa page — Changelog et Hub thaï compris.
> 2. **Le fond de sélection est le même partout** (accent système) : Mises à
>    jour, Alertes et Quarantaine ne se peignent plus en bleu/orange/violet.
>    *C'est le changement voulu par H-T2* — vérifier qu'il ne surprend pas.
> 3. **Les badges** apparaissent sur l'item, disparaissent à zéro, et l'item
>    reste cliquable à zéro.
> 4. **L'accueil rend les quatre compteurs sans défiler**, y compris à zéro
>    partout, et chacun mène à son onglet.
> 5. **Dossier du jeu non défini** → l'accueil propose « Choisir le dossier », et
>    le choisir depuis là fonctionne.
> 6. **SMAPI absent** → « Installer SMAPI » est sur l'accueil, et **la barre de
>    progression s'affiche pendant l'installation**.
> 7. **Réglages** : dossier du jeu, désinstallation de SMAPI et extensions cœur
>    y sont, et la version de l'app n'y apparaît **qu'une fois**.
> 8. **Fenêtre minimale** : la bande de quatre compteurs ne déborde pas.
>
> **Vérifié à l'écran le 2026-08-28 : rien à signaler.** Les huit points sont
> passés — sélection unifiée qui ne surprend pas, badges et compteurs menant
> chacun à sa page, états empêchés de la carte de lancement portant l'action
> qui les lève, Réglages complets sans doublon de version. **La phase 1 tient
> ses revendications** — H-T4 est débloqué.
- [x] **H-T4** — **Mods, pilote du reskin** : toolbar unifiée au motif
      Découvrir (un seul geste par intention), rangée à hauteur réservée avec
      état codé glyph + couleur + barre d'accent (jamais la couleur seule),
      grille optionnelle réutilisant `ModCard` via un adaptateur de valeurs
      (un `ModItem` n'a ni endossements ni catégorie Nexus servis), fiche
      `HeroHeader` + `StatStrip` où l'action praticable est la proéminente. · **L**
>
> **H-T4a (la liste) est livré et vérifié à l'écran le 2026-08-30.** Toolbar
> unifiée (recherche inline, bascule liste/grille persistée), rangée
> délittéralisée au glyph `pause.circle`, grille de cartes servie par
> `ModGridCardValues`. Trois défauts relevés à la vérification, corrigés dans
> la foulée : cartes nues (les captures Nexus dorment déjà dans
> `nexusCachedExtras` — **739 des 887 dossiers** en obtiennent une, et la
> carte dit désormais l'état, la catégorie et « FR »), glyph de bascule
> illisible, pastilles de filtre trop bavardes.
>
> Trois lots de polish ont suivi (`96ba974`→`0711fda`, poussés) : les six
> retours d'écran pris ce jour-là (vignette par défaut quand Nexus n'a rien
> servi, infobulle du problème, badge de profil, alignement pack/composant,
> icônes des menus de filtre, facettes comptées sur le cadrage affiché —
> « Tous », « Activés », « En pause », « Problèmes »), la date d'installation
> qu'un pack montre enfin, puis les attributs — anomalie, note, config de
> profil — qui quittent le flanc du nom pour fermer la bande de métadonnées
> en colonnes tenues, l'anomalie et la note s'ouvrant aussi au clic en
> popover, et la carte de grille portant les mêmes attributs que la rangée.
>
> **H-T4b (la fiche) livré et vérifié à l'écran le 2026-08-30.** Hero +
> bande fine + `StatStrip`, onglet « État » regroupant le diagnostic, pager
> ‹ › dans la barre d'outils de la fenêtre sur le cadrage courant,
> composants de pack cliquables, dossier du mod dans le Finder. Trois
> retours d'écran pris dans la foulée : chevrons montés hors du hero
> (blanc mort sur capture claire), interrupteur vert rétabli — le bouton
> bleu essayé se lisait moins bien —, bouton Finder ajouté. Deux bugs
> honorés au passage : `renamingFolder` fait survivre le poids mesuré à la
> bascule (Core, TDD), et l'enum d'onglets ferme le deep-link « traduis ce
> mod » aux réordonnancements. **La case est cochée : le pilote Mods est
> complet.**
- [x] **H-T5** — **Lot Parties** : profils en cartes à chiffres clés (jamais
      un formulaire nu), sauvegardes au même motif. · **M**
      ✅ (livré le 2026-08-31)
> **H-T5 livré le 2026-08-31, en quatre tâches sur autant de gates.** Les
> profils perdent titre de page et conteneur à bordure : « Ajouter » monte
> en toolbar fixe et la rangée mène par ses chiffres en colonnes tenues —
> Mods · Anomalies · Configs (`StatColumn`, composant partagé avec les
> rangées de sauvegardes) — la pastille FR et les orphelins de configs
> restant la ligne d'attention. Les sauvegardes suivent le patron Mods de
> bout en bout : recherche inline à la frappe (fin de `.searchable`), tri
> et filtre tag en chips, liste sortie du `Form` vers header fixe +
> défilement + footer à compte honnête, rangée fermier › ferme · date avec
> argent et total en colonnes, grille sans zoom de survol. La fiche
> s'ouvre sur un hero local (avatar du fermier — `HeroHeader` partagé
> intact) + `StatStrip` (date de jeu · argent · total) + bande fine
> portant l'historique ; le formulaire d'édition demeure verbatim. Les
> sheets annexes passent aux tokens : « Not installed » gagne son glyph
> (P6), « Branch » prend la teinte `installed`, crayon et corbeille à
> cible 18×18. Périmètre retenu au cadrage : tout, sheets comprises. La
> vérification écran reste à l'humain — scénario remis avec le lot ; cinq
> clés L10n nouvelles, cliquet relevé à chaque tâche (+1/+2, +4, +7/+7).
- [x] **H-T5b** — **Hero de sauvegarde illustré**. ✅ (livré le 2026-08-31)
> **H-T5b livré le 2026-08-31 en huit tâches, refondu le 2026-09-01, revu et corrigé le 2026-09-02.**
> **Ce qui tourne aujourd'hui** : le hero de la fiche de sauvegarde porte le bandeau du splash (`nexus_banner_final`) voilé d'un dégradé, une vignette de ferme illustrée (8 PNG embarqués 190×200 découpés de `fermes.png`, ordre du wiki ; pictogramme SF Symbol pour une ferme de mod) et un avatar 44 pt — l'icône personnalisée de la sauvegarde si elle existe, sinon l'illustration du visage **fixe par sexe**. Le tooltip résolu affiche « Type de ferme : <nom> ».
> **Écart assumé** : coiffure, couleur de cheveux et peau sont lues dans la save mais **ne sont rendues que par le repli vectoriel**. Les teinter sur l'illustration est impraticable — ce sont des crops de l'affiche du jeu, où le brun des cheveux est celui du bois de la ferme derrière le personnage : aucun masque colorimétrique ne les sépare. Un portrait fidèle demanderait de recomposer la tête, pas de la teinter. → voir **H-T5c**.
> **Abandonné en route** (2026-09-01) : les glyphes vectoriels dessinés à la main, illisibles à cette taille, et `SaveFarmPalette` avec eux.
> **Corrigé à la revue** (2026-09-02) : lecture et écriture des champs du fermier par **enfant direct** de `<player>` (`SavePlayerFields`) — la première occurrence attrapait un monstre de quête imbriqué, ce qui affichait une fermière en homme et écrivait la santé du fermier dans le monstre ; `<whichFarm>` non entier reconnu comme ferme de mod (`SaveFarmType`) — `FrontierFarm` s'affichait « Ferme standard » ; icône personnalisée rendue au hero ; chevelure du repli replacée sur le crâne ; caches d'images sous `NSLock`.
> Ferme en passant un bug latent : `SaveManager.farmTypeName` retournait du thaï codé en dur depuis l'origine — désormais localisé via 10 clés `L10n.Saves.farmType*` + `heroFarmHelpFormat`. Architecture : `L10nResolver` protocole Core + `SaveFarmNameResolver` injecté (VM pas god-object-ifié).

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

- [ ] **H-T5e** — **Vignette illustrée pour une ferme de mod.** ⏸️ *En attente
      d'une image de l'auteur — rien à faire côté code d'ici là.*
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

- [ ] **H-T5c** — **Portrait du fermier fidèle à la sauvegarde.** L'avatar du hero
      est aujourd'hui une illustration fixe par sexe ; `<hair>`, `<hairstyleColor>`
      et `<skin>` sont lues et correctes mais ne pilotent aucun pixel. Recomposer
      la tête (base + calques coiffure/peau) plutôt que teinter un crop.
      Prérequis : des calques séparés, que l'affiche du jeu ne fournit pas. · **M**
- [x] **H-T6** — **Lot Santé & secours** : alertes système, quarantaine,
      backups ×2 — gravité toujours glyph + couleur, rapports en tableaux
      lisibles. · **M**
      ✅ (livré le 2026-09-02)
> **Ce qui tourne aujourd'hui** : un modèle de gravité pur et testé —
> `HealthIssue` (critique / avertissement / information) et
> `HealthIssueResolver`, qui agrège trois sources (diagnostics SMAPI,
> collisions de raccourcis, conflits entre mods) et trie par gravité
> décroissante, de façon stable. Le ViewModel expose `healthIssues` ;
> `systemAlertCount` en dérive, donc l'accueil, le badge de la barre
> latérale et l'écran d'alertes lisent tous la même résolution. Composant
> partagé `SeverityBadge` : glyphe **et** couleur **et** libellé, jamais la
> couleur seule. `SystemAlertsView` et `QuarantineView` sortent de
> `MainView.swift` (1519 → 1163 lignes) ; l'écran d'alertes devient une
> liste unifiée triée, avec un pied « N problèmes · M critiques ». Côté
> quarantaine : identités de ligne stables, couleurs aux tokens, troncature
> annoncée. Le rapport de restauration d'un backup d'installation quitte
> l'alerte pour un panneau à sept champs étiquetés ; `ModInstallBackupsView`
> et `ModConfigBackupsView` reviennent à un seul modificateur de
> présentation chacune (4→1 et 3→1).
> **Bug réel trouvé et corrigé en passant** : dans `ModConfigBackupsView`,
> le bouton « Restaurer » relisait la sauvegarde ciblée depuis un état déjà
> remis à `nil` par la fermeture de l'alerte — le bouton s'affichait, la
> confirmation s'ouvrait, rien n'était restauré. La suppression portait la
> même faille. Corrigé (commit `727d7e0`).
> **Écarts assumés** : la quarantaine ne fusionne pas dans la liste des
> alertes — deux questions différentes, deux onglets ; aucun changement de
> logique de détection, le lot présente ce que l'app sait déjà ; pas de
> filtre par source sur les alertes.
> **Suites après vérification à l'écran (H-T6b/H-T6c, 2026-09-02)** : l'auteur
> a constaté que l'écran signalait sans conduire — le bouton d'une ligne
> ouvrait la liste des mods entière, jamais le mod fautif, et « Voir les
> journaux » la vue générale. `HealthIssue.Action` porte désormais une cible
> (`.openMod(query:)` / `.openLogs(searchText:)`), transportée par
> `pendingModDetailFocus` et `pendingLogFocus`. `KeybindReportSection` et
> `ModConflictSection`, restées sans appelant, reviennent en feuilles depuis
> la barre d'outils de l'écran — le bouton « Écarter » d'un conflit est de
> nouveau atteignable. Mesuré ensuite sur le journal réel : une ligne
> intitulée « apiIntegration » (encart de SMAPI pris pour un mod) supprimée,
> les notices sans mod dotées d'un titre traduit, et le dossier d'un
> composant de pack redevenu résolvable.
> **Second tour d'écran (H-T6d, 2026-09-02, vérifié)** : pastille de compte sur
> chacun des deux panoramas (masquée à zéro), leur feuille élargie de 640×580
> à 980×720 — les deux alignent des noms tronqués à une ligne, un conflit en
> montre deux côte à côte. `HealthIssue.action` devient `actions: [Action]` :
> une information qui nomme un mod mène aux DEUX endroits (sa fiche et la
> ligne du journal), une ligne critique garde son chemin unique. Et
> `pendingDetailTab` ouvre la fiche sur l'onglet « État », pas sur la prose :
> c'est de l'état du mod que l'alerte parle. Sur le parc de l'auteur la
> pastille clavier affiche 78 (58 collisions + 20 conflits jeu), celle des
> conflits reste masquée.
> **Revue globale de branche (2026-09-02)** : 7 bloquants corrigés en une
> vague — la pastille comptait les notices SMAPI bénignes (`.info`) comme des
> problèmes (7 sur un parc sans le moindre échec ni conflit), pas de garde
> contre un mod à la fois `failed` et `skipped`, le bouton d'action annonçait
> toujours « Voir les journaux » même vers l'onglet Mods, les conflits
> affichaient des noms de dossiers au lieu de noms de mods, et
> `activeConflictCount` recalculait à part plutôt que de dériver de
> `healthIssues` comme le prévoyait la spec §6 bis. `[HealthIssue].actionableCount`
> (critique + avertissement, `.info` exclu) est la règle unique désormais lue
> par la pastille et le pied de liste.
- [ ] **H-T7** — **Lots Journaux & Réglages** : reskin léger des journaux
      (la perf est déjà faite), Réglages absorbe les déménagés de l'accueil
      en sections unifiées. Deux releases — phases 5 et 6 de la spec. · **S**
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

*(La piste GMCM/Modern Config Menu a quitté cette section, a été instruite en **C4-T3**
le 2026-08-28, et y revient : **aucun des deux n'écrit de schéma hors du jeu**. Le spike
a en revanche trouvé la source qui manquait — le `ConfigSchema` de Content Patcher, en
**C4-T4**. Détail : `docs/audit-config-menus.md`.)*

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
      **Constat accumulé (audit du 2026-09-02), à joindre à la passe groupée** — autre
      sujet, même seau : `healthIssues` (`StarHubTHViewModel.swift:379`, `@MainActor`
      computed) est recalculé à chaque accès — aplatissement des ~966 mods, `Set`,
      résolution complète — et lu plusieurs fois par rendu (`systemAlertCount`,
      `activeConflictCount`, écran d'alertes, accueil). Chaque tick de `scanProgress`
      (publié **par mod** pendant un scan) fait réévaluer les corps observateurs : ~un
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
- [ ] **F2** — **Audit optimisation & sécurité.** Vitesse et mémoire au démarrage, au scan
      (~900 mods) et **au build** (`python3 build_app.py`, `run_tests.sh`), concurrence
      (`scanMods()` parallèle, verrous du registre), et surface de sécurité : extraction
      d'archives (traversée de chemin, zip-bomb — déjà partiellement couverte), stockage
      de la clé Nexus, gestion du protocole `nxm://`, écritures dans `Mods/`. · **M** ·
      *à faire après F1-T1 : auditer 8389 lignes de VM monolithique coûte plus cher que
      d'auditer des types séparés.*
      ⚠️ **Une partie de l'inventaire existe déjà** :
      [`audit-swift-2026-08-05.md`](audit-swift-2026-08-05.md) — 309 lignes, ~72 findings
      recensés, les 9 hauts corrigés au 2026-08-11 — couvre la surface de sécurité et une
      part de la performance. Il porte son propre avertissement de péremption (il a listé
      comme ouverts pendant cinq jours trois findings corrigés entre-temps) : `git log -S`
      sur le symbole avant d'attaquer une ligne. **F2 le complète, il ne le refait pas.**
      À y joindre le candidat **#4 de `§audit-gestionnaires`** : la liste explicite de
      garde-fous d'écriture de Vortex (`policy.ts`), à reprendre **comme grille de revue
      de nos chemins d'écriture**, pas comme code à porter.
      Le périmètre « build » a son propre découpage — voir **F2-T1** (gains rapides déjà
      identifiés) et **F2-T2** (le bottleneck réel, qui relève d'un choix d'architecture
      et non d'un script Python).
  - [x] **F2-T1** — **Quick wins sur la chaîne de build.** Mesure au 2026-09-01
        (`python3 build_app.py` à froid puis à chaud) : `swiftc` whole-module consomme
        **~99 %** du temps (2m22s sur les deux passes — il n'a pas de cache objet
        utilisable quand tout le module est recompilé d'un coup). Les étapes
        périphériques (`compile_commands.json`, `check_standards.py`, copie d'assets,
        codesign) ne pèsent que ~1 s au total — mais c'est précisément la part que
        des quick wins Python peuvent bouger sans toucher au compilateur. · **S**
        **Livré** (2026-09-01) :
        ▸ `build_app.py` saute la réécriture de `compile_commands.json` quand
          l'ensemble des fichiers Swift (avec leur chemin absolu) est inchangé
          depuis la dernière passe — fingerprint dans
          `.build/compile_commands.fingerprint`. Évite ~200 ms + un réindex
          SourceKit-LSP inutile à chaque build, et supprime le bruit dans la sortie.
        ▸ `check_standards.py` cache le verdict par empreinte (mtime agrégé +
          tailles par fichier) dans `.standards-source-freshness{.counts,.info}` :
          un build chaud où rien n'a bougé passe de **860 ms à 49 ms (×17)** —
          les 10 regex sur 211 fichiers sont skippés. `--report` et `--update`
          court-circuitent le cache, qui n'a de sens que pour la vérification
          silencieuse de `build_app.py`.
        ▸ Lecture de `L10n.swift` passée sous `with open(...)` (correction
          d'une fuite de FD), et strip des commentaires `//` avant le regex
          `static let \w+ = "..."` — sans cela, un commentaire évoquant une clé
          déjà connue la faisait ressembler à une déclaration, ce qui aurait
          pu la déclarer « undeclared » sur certaines branches de doc.
        ▸ `run_tests.sh` et `Package.swift` non touchés : `swift test` est déjà
          incrémental (5 s chaud sur le parc de tests actuel), et le découpage
          SPM existant n'a rien à gagner côté script sans le refactor de F1.
        ▸ **Net sur le build complet** : gain marginal mesuré (~1 s sur
          2m22s), le bottleneck `swiftc` ne bouge pas — c'est le propos de F2-T2.
  - [x] **F2-T2** — **Compilation incrémentale de l'app.** ✅ *(livré le
        2026-09-02, **défaut** depuis vérification au lancement)*
        Constat de départ : `swiftc` invoqué sur les 211 fichiers en un seul
        module produit un binaire monolithique et **n'a rien à réutiliser** au
        build suivant, d'où l'égalité froid/chaud. `-incremental` ne s'applique
        qu'au mode `-c` + link.
        **Livré (piste P1)** : `build_app.py --incremental` écrit une table de
        sorties par fichier (`.build/output-file-map.json`), compile en `.o`
        individuels dans `.build/objects/` avec les `.swiftdeps` que swiftc
        tient lui-même, puis lie. C'est le **chemin par défaut** ;
        `--whole-module` rend l'ancien, comme filet et comme référence.
        **Mesures** (8 cœurs), sur de vraies modifications de contenu et non de
        simples `touch` — les deux ont été comparés, mêmes chiffres :

        | cas | whole-module | incrémental | rapport |
        |---|---|---|---|
        | build complet à froid | 141,7 s | 59,4 s | ×2,4 |
        | à chaud, rien touché | 141,7 s | 2,2 s | ×64 |
        | un fichier feuille modifié | 141,7 s | 2,4 s | ×59 |
        | corps du ViewModel modifié | 141,7 s | 5,4 s | ×26 |
        | signature publique du ViewModel | 141,7 s | 30,1 s | ×4,7 |

        Les 141,7 s reproduisent exactement les 2m22s mesurées en F2-T1 par une
        autre session : les deux relevés se confirment.
        **Critère de succès (build chaud sous 30 s) : tenu dans tous les cas**,
        y compris le pire.
        **Équivalence du binaire vérifiée** : même architecture, **70 791
        symboles définis des deux côtés**, 5,9 Ko d'écart sur 30 Mo (+0,02 %),
        signature valide.
        **Pourquoi le basculement a attendu** : un binaire qui se lie n'est pas
        un binaire qui démarre, et aucun agent ne lance l'app dans ce dépôt.
        L'équivalence des symboles ne prouvait rien de plus qu'une équivalence
        de symboles. Le défaut n'a bougé qu'après un lancement réel par
        l'auteur, le 2026-09-02.
        ⚠️ **Piège rencontré, à ne pas refaire** : swiftc compare les chemins de
        l'`output-file-map` **comme des chaînes**. Clés absolues + arguments
        relatifs = aucune correspondance, incrémental désactivé en silence
        (« has no swiftDeps file »), objets écrits dans le répertoire courant —
        214 `.o` et 214 `.swiftdeps` semés à la racine du dépôt, **et code de
        retour 0**. Seul le décompte des objets attendus avant l'édition de
        liens a transformé cet échec muet en erreur.
        Le pire cas (30 s) est celui d'un changement de signature dans le
        god-object de 8 389 lignes : le découper (**F1**) ferait baisser ce pire
        cas, pas seulement le cas moyen.
        ▸ **(P2)** SPM à deux cibles et **(P3)** cache partagé restent sans
        objet tant que P1 tient le critère.
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
- [ ] **F6** — **Constats laissés ouverts par l'audit des 2026-09-02/03.** *(audit
      fichier-par-fichier : `StarHubTHApp.swift` et tranches ①-④ du ViewModel —
      aucun bug bloquant, deux corrections livrées au commit `7e0896a`. Les items
      ci-dessous sont les constats volontairement non traités ; le constat de perf
      du même audit est allé grossir **F3**, son seau désigné.)*
      **Étendu le 2026-09-03** : l'audit fichier-par-fichier de `StarHubTH/Models/` est
      **achevé** — 119 fichiers, tranches A→M, aucun bug bloquant. Les correctifs qui en
      sont sortis sont inscrits en §4 (**X10**–**X17**), auxquels s'ajoutent les
      corrections de la chaîne de traduction et du chemin des mises à jour livrées en
      v1.35.0/v1.35.1 ; tous prouvés sur le parc réel. Reste de l'audit global : `Views/`,
      `Extensions/`, `AppDesignCore`, puis les phases 2-5 du brief (clients réseau
      restants, persistance, `Tests/`, configuration de build).
  - [ ] **F6-T1** — **Course à l'annulation dans `recomputeFrenchCoverage`.** · **S**
        (`StarHubTHViewModel.swift:473`) Le `cancel()` d'un recalcul n'interrompt pas un
        `await mergeFrenchCoverage(…)` déjà engagé : un lot de ≤ 25 mesures de la
        génération précédente peut atterrir après le recalcul de la génération suivante.
        Bénin tant que le contenu des fichiers ne change pas entre les deux (mesures
        identiques — c'est le cas aujourd'hui) ; devient réel le jour de la re-mesure
        ciblée d'un seul mod, cas que le commentaire du code (~L.530) anticipe déjà.
        **Ne pas corriger isolément maintenant** — aucun observable aujourd'hui. Quand la
        re-mesure ciblée arrivera : poser une garde de génération (compteur incrémenté à
        chaque recalcul, merge ignoré si sa génération est dépassée).
  - [x] **F6-T2** — **`fetchModDetailRemote` suppose une complétion exactement une fois.**
        (`StarHubTHViewModel.swift:245`) Les deux appels imbriqués
        (`NexusUpdateChecker.fetchRawDescription` puis `fetchChangelogs`) ne posent
        aucune garde : si l'un appelle sa complétion zéro fois (erreur avalée, réessai
        interne) la fiche reste `isLoading` à vie ; deux fois, la complétion se rejoue.
        **Clos le 2026-09-03, vérifié à la lecture** (audit tranche ③) : chaque
        complétion de `NexusUpdateChecker` est appelée **exactement une fois** sur
        tous les chemins — un `dataTask` URLSession ne rend son rappel qu'une fois
        (annulation comprise, traduite en échec), `fetchRawDescription` et
        `fetchChangelogs` n'ont qu'une sortie par branche, et le cas le plus subtil
        (`fetchModInfo`, requête secondaire `files.json` imbriquée) passe par un
        `finalize` appelé exactement une fois sur chacune de ses deux sorties.
        Seule échappatoire théorique : `fetchSingleMod` rend sans complétion si
        `self` a disparu en vol — singleton éternel, indéallocable. L'hypothèse
        tient ; rien à blinder.
  - [ ] **F6-T4** — **`AffirmedUpdates.rows` apparie l'`UniqueID` en respectant la
        casse.** · **S** Seul appariement d'`UniqueID` du dépôt à le faire — partout
        ailleurs la comparaison est insensible à la casse. Mais **tout le sous-système
        d'ancres** (écriture, `remove`, `all`, l'écran X12) est casse-exact de bout en
        bout : un mod affirmé sous une casse et relu sous une autre est déjà traité
        comme deux entrées à l'écriture. Corriger la seule lecture créerait la
        divergence — une ancre trouvée à l'affichage, introuvable à la suppression.
        **À traiter d'un bloc ou pas du tout** : normaliser la clé à l'écriture, avec
        une migration des ancres déjà posées. Aucun observable sur le parc actuel.
  - [ ] **F6-T3** — **Deux parseurs du même journal SMAPI.** *(tranche ④,
        2026-09-03)* `smapiErrors` est extrait par un scanner inline du
        ViewModel (~L.3142 : chirurgie de chaînes sur « ERROR SMAPI] », drapeau
        `isParsingErrors`), pendant que `SmapiLogParser` (Core, testé) parse le
        même fichier pour les entrées de l'onglet Journaux, les conflits
        Content Patcher et l'historique d'erreurs par mod. Le patron « copies
        divergentes » — cf. `isOsJunk`, 4 copies dont une amputée : chaque
        évolution du format SMAPI se corrige deux fois, et rien ne signale la
        divergence le jour où l'un des deux seul est adapté. Fix = mapper les
        consommateurs de `smapiErrors` sur `SmapiLogParser` et retirer le
        scanner inline. Pas au fil de l'eau : ça touche l'affichage du volet
        erreurs, à faire avec un vrai journal SMAPI sous la main. · **M**

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
- ~~**`UX_UI_Specifications.md` est périmé et orphelin.**~~ *(traité le 2026-08-28,
  H-T1)* Il s'épinglait au commit `a3937f6` (v1.6.0), soit 19 releases de retard, et
  aucun document du dépôt ne le citait. Ses 1318 lignes sont remplacées par un bandeau
  de renvoi vers la ROADMAP, le code, les tests et `design/` ; le contenu reste dans
  l'historique.

---

## 10. Veille concurrentielle — `SalehBusbait/RimManager` (2026-08-31)

Gestionnaire de mods **RimWorld** (.NET 10 + Avalonia 12, MIT, `1.0.0-beta.3`, 1 488 tests,
usage quotidien sur 565 mods). Domaine différent (RimWorld, Mono, XML) mais architecture
soignée et features originales exportables.

**Fait foi** : [`CLAUDE.md`](https://github.com/SalehBusbait/RimManager/blob/main/CLAUDE.md)
du dépôt, `docs/{sorting,conflicts,modlists-and-history,updates-and-workshop,sharing,rwlist-v1}.md`.
**Limite** : 0 ⭐, 0 fork, pré-release — observer, ne pas importer aveuglément.

### 10.1 Architecture de référence (à observer, pas à copier)

Séparation `Core` (pur, zéro I/O) → `Storage` (seul I/O disque) → `Integrations` (réseau
+ process) → `App` (UI). Règle absolue : *« Anything testable lives below the shell, not
in it. »* C'est la **cible** de notre **F1** mais le mapping avec notre monolithe
`StarHubTHViewModel` (8 389 lignes au 2026-08-28, dernier mesuré — voir **F1** pour la
tendance) demandera plusieurs itérations.

### 10.2 Traps documentés (anti-pattern book gratuit)

Le `CLAUDE.md` liste 9 pièges Avalonia trouvés en production. Le plus transposable tel
quel : *« A number on screen is a claim and has to be measured against a real install. »*
— c'est la même règle que **F2** (audit perf) énonce chez nous en creux. Leçon : un
audit outillé sans mesure sur la modlist de l'auteur ne vaut rien.

### 10.3 Six actions à pousser en roadmap

Périmètre : ce qui est **conceptuellement réutilisable** et **techniquement faisable**
sur macOS / SwiftUI. Les features trop spécifiques à RimWorld (Cecil analyzer,
`ModsConfig.xml` byte-exact, Steamworks bindings) sont écartées.

- [ ] **R1** — **Indexer les couleurs catégories en palette, pas en hex.** Les 26 entrées
      de `NexusCategory.swift` (`Color(red: 0.80, …)`) sont des hex codés en dur. Le mode
      dark est géré par un asset 1:1 qui ne survivra pas à un thème custom. Pattern
      RimManager : stocker un `paletteIndex: Int` (0–5), interpréter via le thème
      courant au rendu. Bénéfice futur : un thème custom n'a pas à migrer les données.
      · **M** · *à pousser dans l'axe H (cohérence UI), après H-T1.*
- [ ] **R2** — **Écriture atomique + apply guard pour `applyProfileToFilesystem`.**
      Pattern RimManager : `guard !isGameRunning` → backup timestamped → write
      atomique (tmp + rename) → validation post-write. Un crash en cours d'activation
      de profil peut aujourd'hui laisser l'état partiel (pas de backup de l'état
      pré-apply au niveau profil — seulement au niveau mod). Réutilise
      `ModInstallBackupManager` côté backup, ajoute l'atomique.
      · **M** · *cible F2 (audit sécurité) ou §4 (correctifs X9).*
- [ ] **R3** — **Snooze d'updates Nexus.** Granularité : 1 semaine / jusqu'à prochaine
      version du mod / jusqu'à prochaine version de Stardew. Persiste en UserDefaults,
      expire tout seul, retire le mod de la liste « updates » sans le masquer dans
      l'inventaire. Répond à un vrai UX gap : aujourd'hui, ignorer un update = l'avoir
      en permanence sous les yeux.
      · **S** · *axe B.*
- [ ] **R4** — **Profils = modlist + configs isolées.** Chaque profil capture ses propres
      `config.json` / `fr.json` au switch (toggle par profil, off par défaut). Le scan
      actuel distingue déjà la config par mod ; il manque l'association config↔profil
      et le snapshot au moment du switch. Faisable en s'appuyant sur
      `ModConfigBackupManager` déjà livré.
      · **L** · *B3-T1 → successeur direct.*
- [ ] **R5** — **Historique append-only des actions.** Modèle RimManager : chaque
      `apply`, `sort`, `install`, `delete` crée un snapshot, restaurable sans
      réécrire l'historique. Pinning (étoile) protège du pruning auto à 30 j. Remplace
      l'actuel *« annuler la dernière action »* (s'il existe) par un vrai timeline.
      · **M** · *B3-T1+ : à concevoir avec R4 pour partager le store.*
- [ ] **R6** — **Property-test « idempotent » sur `applyProfileToFilesystem`.**
      Appliquer deux fois un même profil = appliquer une fois (état final stable).
      Mesure RimManager : 100+ cas générés automatiquement, propriété tenue. Notre code
      a probablement des cas où un double-apply renomme deux fois (toggle
      X→.X→X) — à property-tester pour **caractériser** avant de **corriger**.
      · **S** · *F2 (audit perf & sécurité).*

### 10.4 Ce qu'on **n'importe PAS**

- **Conflict detection binaire (Cecil)** : trop spécifique à .NET. SMAPI détecte déjà
  ses propres conflits Harmony au runtime, et `SmapiLogParser` les parse. Notre
  valeur ajoutée reste dans le diagnostic, pas dans l'analyse statique.
- **Drift detection ModsConfig.xml** : on n'écrit pas dans un fichier que l'utilisateur
  peut modifier. Notre `installedModRegistry` (UserDefaults) est sous notre seul
  contrôle.
- **Rule editor 3-sources (auteur / communauté / utilisateur)** : pas de DB
  communautaire équivalente pour Stardew, et la granularité des deps est plus faible
  que sur RimWorld.
- **Workshop = externalisation totale** : RimManager délègue à Steam ; nous téléchargeons
  depuis Nexus, c'est correct (Stardew n'a pas de Steam Workshop). Mais le **principe**
  est confirmé : l'autorité, c'est **notre scan du disque**, pas Nexus — ce qu'on fait
  déjà.
