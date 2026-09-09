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

**Ce document ne porte que ce qui reste à faire.** Les items terminés — leur récit,
leurs mesures, ce qu'ils ont écarté au passage — vivent dans
[`roadmap-archive.md`](roadmap-archive.md), et le §11 dit lequel s'y trouve. La
séparation date du 2026-09-04 : les items livrés occupaient **plus des deux tiers**
du fichier, et la question « que reste-t-il ? » s'y lisait à une ligne contre quatre.

⚠️ **Les cases traînent derrière le code.** C'est le piège numéro un de ce
document, et il s'est produit plusieurs fois en une semaine : une tâche livrée
reste `- [ ]` parce que le commit qui la livrait parlait d'autre chose.
**Avant de traiter un item ouvert, vérifier `git log -S` sur le symbole concerné
et lire le code** — pas la case.

**Ce qui fait autorité, dans l'ordre** : ce que l'auteur demande ; le code ;
`CHANGELOG.md` pour ce qui est publié ; ce document pour l'intention et l'ordre.
Un chiffre écrit ici a été mesuré à une date donnée — sur le parc de référence
(~1 060 mods), sauf mention contraire — et n'a pas été revérifié depuis.

**Les identifiants de tâche** (`X56`, `C4-T6`, `B3-T5`…) sont stables et cités
tels quels dans le code et les messages de commit. Un identifiant qui ne se
trouve plus ici est livré : le chercher dans l'archive.

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
- ~~**Axe H — Cohérence UI**~~ *(transverse)* ✅ **clos le 2026-09-09** :
  généraliser à toute l'app le langage visuel établi par l'onglet Découvrir
  (axe G) — navigation regroupée, accueil tableau de bord, reskin écran par
  écran, bibliothèque de composants vivante.
- **Axe I — Expérience utilisateur** *(**débloqué** : H est clos)* : navigation
  optimisée et accessibilité en **capacités** — clavier, palette de commandes,
  VoiceOver.

**Règle de discipline reprise du document de veille** :
> *Chaque release ne sert qu'un seul axe principal, plus quelques correctifs gratuits.*

---

## 3. Table de réconciliation

La table qui appariait chaque demande de la liste du 2026-07-30 à une tâche a été
**déplacée dans l'archive** ([`roadmap-archive.md`](roadmap-archive.md)) : établie
contre l'état de la v1.10.0, elle n'a pas été tenue à jour et plusieurs de ses
états sont désormais faux — elle donne les configurations par profil « à faire »
alors que **B3-T5** est livré depuis le 2026-08-22. La rejouer demande de
confronter chaque ligne au code, ce qui est un travail à part entière.

Ce qui reste ouvert se lit directement : **§4** pour les correctifs, **§5** pour
les chantiers, **§7** pour la dette technique.

---

## 4. Correctifs identifiés — à traiter en premier

Ce ne sont pas des fonctionnalités : ce sont des choses cassées ou dégradées.
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

> ✅ **Les 6 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.

> **Changement d'ordre assumé** : la version précédente de cette roadmap plaçait la
> traduction FR en v1.11. La bissection passe devant parce que l'auteur l'a placée en
> tête de sa liste, qu'elle s'appuie sur une mécanique déjà en place
> (`applyProfileToFilesystem`), et qu'à ~900 mods une bissection à la main coûte des
> heures par incident. Voir §7 pour l'arbitrage.

#### A4 — Recherche dichotomique du mod fautif

> ✅ **Les 6 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


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

### Hub de traduction FR, phase 1 : *diagnostic* — **Axe C** · livrée en **v1.13.0**, C2-T4 le 2026-09-08

Objectif : tenir la promesse du dépôt (« traduction en français ») **en lecture seule**,
sans risque d'écriture destructive.

#### C1 — Couverture de traduction par mod

> ✅ **Les 8 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


#### C2 — Vue diff EN/FR

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

**Risques** : formats i18n hétérogènes (tous les mods n'ont pas de `default.json`) ; gros
mods (SVE ≈ milliers de clés) → calcul hors du thread principal.
**Critère de succès** : savoir en un coup d'œil quels mods installés sont traduits,
partiellement traduits ou pas du tout, sans ouvrir un seul fichier.

---

### Hub de traduction FR, phase 2 : *édition & assistance* — **Axe C** · livrée par morceaux (**v1.15.0** → **v1.17.0**), **5 items ouverts** *(compteur relevé le 2026-09-09 : C3-T2, C3-T5, C5-T1, C5-T2, C6-T1 — **C4 est clos en entier**)*

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

- [ ] **C3-T2** — Scan élargi aux assets Content Patcher (`events.json`, `dialogues.json`,
      `content.json`) : repérer les chaînes affichées restées en anglais. · **L** ·
      risque : forte hétérogénéité des packs → livrer en « suggestions », jamais en verdict.
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


#### C4 — Éditeur de config lisible

> **Deux populations, deux sources — c'est la distinction qui manquait ici.**
> Un **content pack** décrit ses options dans un schéma posé sur le disque ; un **mod
> C#** ne décrit rien nulle part, et ses libellés ne s'attrapent que par son `i18n/`.
> Établi le 2026-08-28 par décompilation et mesure → `§audit-config-menus`,
> [`audit-config-menus.md`](audit-config-menus.md). **Prendre C4-T4 avant C4-T1.**

- [x] **C4-T1** — *(voie secondaire — pour les mods C#, qui n'ont pas de schéma)*
      Étiqueter les champs de `config.json` avec les libellés `config.*` que le mod publie
      dans son `i18n/` (en FR si disponible), au lieu des clés brutes. · **M**
      ✅ **Livré le 2026-09-09** — type Core `ConfigLabelResolver` (12 tests) branché sur
      `ConfigEditorModel.groups(labeledBy:)` : le schéma d'un pack gagne, sinon la tige
      i18n (`config.<clé>.name|label|title` / `description|tooltip|desc`, insensible à la
      casse, FR champ par champ sur l'anglais), sinon la clé brute. Les deux dispositions
      i18n de SMAPI couvertes (`I18nLocaleResolver`), BOM compris (`I18nFileDecoder`).
      Une description orpheline (`config.x.tooltip` sans `name`) aide sous la clé brute.
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
      ▸ **Confirmé par l'audit du 2026-09-04** (décompilation —
      [`audit-mods-config-perf.md`](audit-mods-config-perf.md)) : les deux patterns
      cohabitent. UltraSmooth suit `camelCase(champ)` à 100 % (115 clés, toutes
      retombées) ; SLO choisit librement (`config.fast-warp.name` pour un champ nommé
      `EnableFastWarpTransitions`). Le rapprochement par tige reste la bonne règle,
      avec repli assumé sur la clé brute. Piste pour élargir le plafond : **les bornes
      vivent parfois en prose dans l'infobulle** (« Clamped 256–4096 KB »,
      UltraSmooth) — la seule trace sur disque des min/max des mods C#.
- [x] **C4-T8** — ⛔️ **Constat réfuté, clos sans code le 2026-09-09** *(option A,
      tranchée par l'auteur — §8.2)*. **Prévisualiser la normalisation en lisant ce que
      le mod a fait, pas en devinant ses bornes.** SLO journalise sa configuration normalisée
      **entière** au démarrage, sous `[OPTIMIZER CONFIG]` (relevé dans le journal SMAPI
      réel de l'auteur) — et l'app sait déjà lire ce journal en profondeur. Comparer la
      valeur du `config.json` à celle que le mod a annoncée au dernier lancement dirait
      « le mod a ramené 8192 à 4096 » sans coder une seule borne, et sans périmer à la
      version suivante. À instruire : combien de mods du parc journalisent leur config,
      et sous quelle forme. · **M**
      ⛔️ **Instruit le 2026-09-09 — la prémisse est fausse sur le parc mesuré. Ne pas
      coder en l'état ; go/no-go à l'auteur, cadré en §8.2.** Journal réel de l'auteur
      (`SMAPI-latest.txt`, 9,5 Mo, 119 486 lignes horodatées, run du 2026-09-08,
      verbose actif) balayé **en entier** — pas seulement la fenêtre de démarrage, car
      un mod peut publier sa config à `SaveLoaded` ou au premier usage.
      **1. Deux mods sur ~966 publient leur configuration entière**, et un seul est
      visible sans journal verbeux : SLO en `INFO` (`[OPTIMIZER CONFIG]`, 48 clés) et
      **UI Info Suite 2 Alternative** en `TRACE` (`ModEntry: initial config`, 85 clés).
      Comptage par niveau, sources non-SMAPI, ≥ 3 paires `clé=valeur` : `INFO` 2 sources
      (SLO + un avertissement de dépréciation GMCM), `DEBUG` 1 (Fish Helper UI — des
      poissons, pas sa config), `TRACE` 4 (Font Settings, Wizardry, UIS2, Wildroot).
      L'idiome `[TAG EN MAJUSCULES]` n'a **qu'un** porteur : SLO. Font Settings, le plus
      bavard (30 lignes, 20 paires), journalise ses `FontConfigModel` **effectifs par
      contexte** — son `config.json` ne porte, lui, que des bornes `Min*/Max*` : aucune
      clé commune, rien à rapprocher.
      **2. Le mod qui a motivé la tâche est justement celui qu'on ne peut pas
      rapprocher.** SLO renomme ses clés dans le journal : **3 clés communes sur 46
      (config) / 48 (journal)**. `prefetchLimit` ↔ `PrefetchMaximumMegabytes`,
      `fastWarpMultiplier` ↔ `FastWarpTransitionMultiplier`, `profile` ↔
      `OptimizationProfileVersion` — aucune règle de tige (celle de C4-T1) ne relie ces
      paires. Il faudrait une **table de correspondance par mod**, qui périmerait à la
      version suivante exactement comme les bornes codées en dur que la tâche voulait
      éviter. UIS2, à l'inverse, se rapproche parfaitement : **85 clés journalisées sur
      85 retombent sur le `config.json`** (les 13 clés restantes du fichier sont des
      raccourcis, non journalisés).
      **3. Et là où le rapprochement marche, il n'y a rien à montrer.** UIS2 : **0 écart**
      entre les 85 valeurs journalisées et le `config.json`. SLO, sur les cinq clés
      rapprochables à la main : `workingSetSoftLimit=4096` = `…SoftLimitMegabytes: 4096`,
      `prefetchLimit=256 MB` = `256`, `fastWarpMultiplier=6.5x` = `6.5`, `profile=12`
      = `12`, `mapCacheLimit=1024 MB` = `1024`. **Le « 8192 ramené à 4096 » du libellé
      n'existe pas dans ce journal** : 4096 est la valeur que l'auteur a écrite. Le
      journal *reproduit* la configuration lue, il n'expose pas de correction.
      ▸ **Ce qui survit, et qui n'est pas cette tâche** : SLO publie sa vraie
      normalisation sous une **autre** forme, un triplet lisible tel quel, sans aucun
      rapprochement de clé — `backgroundMapPreparation=configured=False,effective=false,`
      `reason=retired-thread-affinity` (idem `fastWarp`, `deferredTileSheets`). C'est le
      mod qui dit lui-même *voulu / effectif / pourquoi*. Un seul porteur sur le parc :
      pas de quoi faire une fonctionnalité, à reprendre si un second apparaît.
      ⚠️ **Limite de l'échantillon** : un seul journal, un seul lancement — le dossier
      `ErrorLogs/` n'en contient pas d'autre. Cela établit « rare », pas « exactement
      deux ».
      ▸ **Tranché le 2026-09-09 : option A, clore sans code** (comparer `X59`, coché
      en constat faux). **Ne pas ré-instruire** : la mesure est faite et datée ci-dessus.
      Le signal qui rouvrirait la case n'est *pas* le nombre de mods bavards, mais
      l'apparition d'un **second** mod publiant un triplet *voulu / effectif / pourquoi*
      — l'option B deviendrait alors une tâche neuve, à écrire comme telle.
- [x] **C4-T7** — `audit-mods-config-perf.md` — **Les angles morts keybind de C4-T2.**
      Chevauchements sous-ensemble (A = `K`, B = `K`+Shift co-déclenchent sur le geste
      long — spec §12), composants de pack, mods en pause ; et donner aux collisions
      **manette** leur catégorie visible — cas réel mesuré le 2026-09-04 : `LeftStick`
      partagé par deux frameworks ValleyBonds. · **M**
      ✅ **Livré le 2026-09-09** — `SubsetOverlap` (sous-ensemble strict, jamais au sein
      d'un même mod, signalé sans peser sur le badge) ; collisions manette dans leur
      catégorie (`KeybindCombo.isGamepad`, figée sur la table SButton) ; les liaisons
      des mods en pause sont scannées et leurs collisions publiées comme **latentes**
      (`latentCollisions`, hors `problemCount`, l'état de chacun lisible sur l'usage) ;
      la règle du catalogue R4 court pour tous. Composants de pack : déjà couverts par
      `flattenedMods` du service de scan. 11 tests nouveaux (43 dans la suite).

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

### Profils, favoris & backups exploitables — **Axe B** · **livré** (23 items, B3 et B4 compris)

> ✅ **Les 23 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.

#### B3 — Profils

> ✅ **Les 7 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


#### B4 — Page de backups

> ✅ **Les 4 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


#### B2 — Ergonomie transverse

> ✅ **Les 12 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


**Critère de succès** : un profil se crée, se duplique et s'applique sans surprise ; un
backup se retrouve en moins de dix secondes.

---

### Fiabilité du registre & compatibilité — **Axe A** · **5 items ouverts sur 19**

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

> ✅ **Les 6 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


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

> Source ajoutée au registre le 2026-09-04 : `SinZ.Profiler` 2.0.0, page et
> monorepo **surveillés** (`mod/profiler`, `profiler-source`). La chaîne de
> journal à parser est mesurée dans la DLL : `[BigLoop] In total, it took
> {0:N}ms handling {1}{2}`. ⚠️ Sur le parc de référence, Profiler est
> **installé mais en pause** (`.Profiler/`) : sa détection doit regarder les
> mods en pause, pas seulement les actifs — et son activation n'efface pas
> l'historique : le dernier journal date d'avant la mise en pause.

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

#### D2 — Les sources de télémétrie déjà installées — [`audit-mods-config-perf.md`](audit-mods-config-perf.md)

Complément de D1 : trois mods déjà présents sur le parc écrivent de la télémétrie
exploitable **sans rien installer de plus**. Établi par décompilation et mesure sur
le journal réel le 2026-09-04.

- [ ] **D2-T1** — Parser `[OPTIMIZER CONFIG]` (SLO, une ligne INFO au démarrage) :
      profil, limites de cache, et le triplet configuré/effectif/**raison** de chaque
      optimisation. Modèle Core testable ; échec silencieux si la ligne change de
      forme. · **S**
- [ ] **D2-T2** — Ingérer les `Mods/*/UltraSmooth_TraceReport_*.txt` : sections
      balisées (surcharge boucle CPU, délai de présentation GPU, budget de trame
      16,6 ms), rapprochées du mod et de la session. ⚠️ Les dossiers de mods sont
      en 0555 par endroits (piège X7) : l'écriture du rapport peut y échouer —
      l'absence de rapport n'est pas une absence de problème. · **M**
- [ ] **D2-T3** — Vue « Performance » dans l'onglet Diagnostic (à côté de D1-T3) :
      état SLO résolu, derniers rapports UltraSmooth, couverture des menus de config
      (`Registered config menu` de MCM), le tout corrélé aux patches Content Patcher
      par mod. · **M**
- [ ] **D2-T4** — Session instrumentée : « Lancer avec diagnostics » — activer
      `EnablePerformanceMeasurement` (SLO) ou le benchmark UltraSmooth (F9 par défaut
      ici) le temps d'une session, puis ingérer journal et rapports au retour. · **M**

**Risques** : mêmes que D1 — formats de sortie de mods tiers, parseurs tolérants,
**ne jamais inventer de chiffre**. La ventilation fine « ce mod coûte X ms »
n'existe pas dans SMAPI 4.5.2 (scan des DLL) : ne pas la promettre dans l'UI.
**Critère de succès** : sans installer quoi que ce soit de nouveau, l'écran dit si
SLO est actif et ce que la dernière session a mesuré.

---

### Découverte de nouveaux mods — **Axe G** · livré en **v1.25.0**

> ✅ **Les 3 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.

L'app sait tout faire **à partir d'un mod installé** — traductions (**A3-T3**),
suppléments (**A3-T4**) — et rien **sans point de départ**. La vitrine
« Découvrir » comble ce trou : tendances, récents, sélection FR, recherche
libre. Nexus seul (GraphQL v2) : le panorama des sources a été passé au crible
et les autres n'apportent rien de mesurable — CurseForge/ModDrop sont déjà
couverts pour les mises à jour via smapi.io, forums/Discord/Naver n'ont pas
d'API. Spec : `docs/superpowers/specs/2026-08-27-decouverte-mods-design.md`
(local, gitignoré comme les autres specs SDD).


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

### Cohérence UI : un seul langage pour toute l'app — **Axe H** · ✅ **CLOS le 2026-09-09** *(13 items : 12 livrés, H-T5c abandonné par décision de l'auteur. Les six critères §10 sont tenus — le n°6, l'audit de fidélité de Découvrir, mesuré à zéro écart en H-T9.)*

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
> **H-T5b livré le 2026-08-31 en huit tâches, refondu le 2026-09-01, revu et corrigé le 2026-09-02.**
> **Ce qui tourne aujourd'hui** : le hero de la fiche de sauvegarde porte le bandeau du splash (`nexus_banner_final`) voilé d'un dégradé, une vignette de ferme illustrée (8 PNG embarqués 190×200 découpés de `fermes.png`, ordre du wiki ; pictogramme SF Symbol pour une ferme de mod) et un avatar 44 pt — l'icône personnalisée de la sauvegarde si elle existe, sinon l'illustration du visage **fixe par sexe**. Le tooltip résolu affiche « Type de ferme : <nom> ».
> **Écart assumé** : coiffure, couleur de cheveux et peau sont lues dans la save mais **ne sont rendues que par le repli vectoriel**. Les teinter sur l'illustration est impraticable — ce sont des crops de l'affiche du jeu, où le brun des cheveux est celui du bois de la ferme derrière le personnage : aucun masque colorimétrique ne les sépare. Un portrait fidèle demanderait de recomposer la tête, pas de la teinter. → voir **H-T5c**.
> **Abandonné en route** (2026-09-01) : les glyphes vectoriels dessinés à la main, illisibles à cette taille, et `SaveFarmPalette` avec eux.
> **Corrigé à la revue** (2026-09-02) : lecture et écriture des champs du fermier par **enfant direct** de `<player>` (`SavePlayerFields`) — la première occurrence attrapait un monstre de quête imbriqué, ce qui affichait une fermière en homme et écrivait la santé du fermier dans le monstre ; `<whichFarm>` non entier reconnu comme ferme de mod (`SaveFarmType`) — `FrontierFarm` s'affichait « Ferme standard » ; icône personnalisée rendue au hero ; chevelure du repli replacée sur le crâne ; caches d'images sous `NSLock`.
> Ferme en passant un bug latent : `SaveManager.farmTypeName` retournait du thaï codé en dur depuis l'origine — désormais localisé via 10 clés `L10n.Saves.farmType*` + `heroFarmHelpFormat`. Architecture : `L10nResolver` protocole Core + `SaveFarmNameResolver` injecté (VM pas god-object-ifié).


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

**Risques** : cohabitation ancien/nouveau style pendant le chantier (bornée :
chaque lot livré est cohérent avec le système) ; `MainView` remet ses états
de détail à `nil` au changement d'onglet — tout nouvel écran suit le motif
« sheet interne à la vue » de Découvrir ; l'accueil puise dans le God module
(8389 lignes) → touches minimales, logique pure côté `Models/`.
**Critère de succès** : plus aucun écran ne parle sa langue propre — mesurable :
zéro valeur de style hors tokens dans les vues migrées, un seul style d'item
de sidebar, Découvrir inchangé au closage.

---

### Expérience utilisateur : navigation & accessibilité — **Axe I** · à faire — **plus rien devant : H est clos depuis le 2026-09-09**

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

### Horizon 2.x — Mutualisation communautaire — **Axe D3**

#### D3 — Diagnostics et mesures partagés entre utilisateurs (cf. `circinus.sh`)

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

- [ ] **D3-T1** — *(préalable)* Décider si StarHubFR devient un produit avec backend.
      Tant que la réponse n'est pas oui, les tâches ci-dessous n'existent pas.
- [ ] **D3-T2** — Étudier `circinus.sh` : quelles données remontent, sous quel consentement,
      quelle granularité d'agrégation. · **S**
- [ ] **D3-T3** — *(voie sans backend, à considérer d'abord)* Export/import d'un rapport de
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
  - [x] **F1-T1** ✅ *(terminé le 2026-08-01 par `b25a550` — case corrigée le 2026-09-04, l'item se déclarait lui-même terminé)* — Extraire deux domaines nets et autonomes en types dédiés, chacun dans
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
        **Première application du sens inverse (2026-09-07)** — extraire ce qu'on
        veut tester : les quatre enums de cadrage de la liste (`ModFilter`,
        `FrenchTranslationScope`, `CategoryScope`, `ModSortOrder`) descendent de
        `ModListView.swift` vers `Models/ModListFilters.swift`, et `NexusCategory`
        entre dans le module (`AppDesignCore` y prouve que SwiftUI compile).
        `ModListFilters` devient testable : **11 tests de caractérisation**,
        dont le contrat de pagination — tout critère qui change le nombre de
        résultats ramène à la page 1, le tri n'y touche pas, et `focus(on:)`
        lève tout filtre susceptible d'écarter. C'était le déblocage que X91
        avait laissé documenté. 2 370 tests verts.
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
      ▸ **Rattrapage de l'inventaire livré (2026-09-09)** — les 5 derniers ⛔️ de
      l'audit 2026-08-05 sont refermés : remariage sans promotion du nouveau
      conjoint (`3565e10`, XML mesuré contre les DLL du jeu), `updateSave`/
      `updateInventory` hors verrou + `dismiss()` inconditionnel des feuilles de
      sauvegarde (`dfc55c7`), « http » pris pour un nom de mod (`df2ce99`),
      `lastError` **réfuté** (site supprimé avec `check()`). L'audit 2026-08-05
      est désormais **clôturé** ; il reste la grille de patterns, pas un stock de
      tâches.
      ▸ **Tranche « écritures » livrée (2026-09-09)** — la grille `policy.ts` de
      Vortex (jamais absorber `smapi-internal/`, jamais d'attribution racine,
      jamais de `Content/`) passée sur les 151 sites d'écriture du dépôt, par
      aire. Verdicts : `Content/` — aucune écriture ; `smapi-internal/` — seul
      le marqueur de version délibéré (écrit après succès officiel, échec
      journalisé) ; l'installeur ne pose jamais rien hors `Mods/<dossier>/` ;
      attribution de contenu déposé — hôte obligatoirement installé, table de
      règles à signature de clés, refus plutôt qu'assainissement, préfixe
      vérifié après construction, chmod par `RecoveredFileWriter`, sauvegarde
      de l'hôte par l'appelant (`ModInstallView:898`) ; rollback complet côté
      `ManifestlessInstaller`. Écritures directes du VM, réparateur, magasins,
      `nxm://` (`NxmLink.parse` strict), clé Nexus (SecItemAdd vérifié,
      2026-08-11) : relus, rien à corriger. **Zéro nouveau défaut, une question
      de conception sortie : `X103`** (permanence de la suppression des mods
      vs corbeille/quarantaine et rétention des archives).
      ▸ **Tranche « extraction d'archives » passée (2026-09-09)** — reprise à neuf
      des gardes d'extraction, chaque prémisse éprouvée par l'expérience et non
      par la seule lecture. **Zéro nouveau défaut, une prémisse réfutée, une
      nuance documentée** :
      - la prémisse du zip-slip de l'audit 2026-08-05 (« `unzip` extrait les
        `../` tels quels ») **ne se reproduit pas** sur l'`/usr/bin/unzip`
        actuel. Mesuré sur six archives fabriquées pour l'occasion : `..` en
        tête et en milieu de chemin, chemin absolu, backslashes avec et sans
        drapeau MS-DOS — l'outil élimine les composantes `..`, ampute les
        chemins absolus (« stripped absolute path »), et rien ne sort jamais
        du dossier de destination ;
      - nuance : `containsTraversalPath` ne découpe que sur `/`, donc les
        noms `..\..\x` passent le contrôle statique — mais l'extraction
        reste saine (l'outil sanitise, cf. ci-dessus), et pré-rejeter ces
        noms casserait de vraies archives Windows : le backslash est un
        caractère de nom légal sur APFS. Documenté, délibérément non
        « corrigé » ;
      - la garde pré-extraction reste posée pour les **outils tiers**
        (`unrar`/`unar`/`7zz`, versions non maîtrisées) : défense en
        profondeur, à garder ;
      - zip-bomb : le plafond 2 Go décompressé est bien lu **avant**
        extraction dans les deux voies (`unzip -l` sous locale C,
        `7zz l -slt` via `totalSizeFromSevenZipListing`), avec fail-open
        assumé et documenté (en-tête 7z chiffré illisible) ;
      - le rouge Phase 2 sur `SmapiInstaller` (scénario concurrent) est
        **clos par le correctif X81** (racine temporaire par UUID +
        `defer` de nettoyage) : plus aucun chemin statique partagé entre
        deux `install()`, le test concurrentiel qu'appelait l'audit n'a
        plus d'objet ;
      - un écart résiduel noté, sans action aujourd'hui : le hub thaï
        (`StarHubTHViewModel.swift:8666`) extrait directement dans
        `Mods/` via le même `extractArchive` — zip-slip et détection de
        format couverts, mais sans la garde symlinks ni le strip
      `__MACOSX`. Source unique et curatée à ce jour ; à reprendre le
      jour où le hub s'ouvre à d'autres sources.
      ▸ **Tranche « perf & concurrence » passée (2026-09-09)** — re-vérification
      des constats accumulés contre le code, puis balayage de la surface de
      concurrence du scan. **Zéro nouveau défaut, un constat périmé corrigé** :
      - `healthIssues` (`StarHubTHViewModel.swift:419`) reste une computed
        `@MainActor` réévaluée à chaque accès, sans mémoïsation — le patron
        est reconnu dans le code (la doc d'`affirmedUpdates` raconte l'avoir
        publié *pour* l'éviter) et son traitement reste **porté en F3**
        (arbitrage du 2026-08-01 : passe groupée, pas au fil de l'eau) ;
      - `exportTranslationLot`/`importTranslationLot`
        (`StarHubTHViewModel.swift:1485`, `:1534`) restent synchrones sur le
        fil principal — `TranslationLot.build` inline, sans `Task.detached`
        ni progression, alors que le patron de la tâche détachée est déjà
        celui du VM partout ailleurs (couverture FR, profil, mesures) ; F3 ;
      - **constat périmé corrigé** : `scanProgress` n'est plus « publié par
        mod » (note du 2026-09-02) — throttlé à ~12/s et publié sur main
        depuis `87de592` ; l'annotation est posée sur la note ;
      - la latence de frappe (F3) reste non tranchée régression/défaut
        préexistant : le témoin A/B `v1.11.1` exige une manipulation à
        l'écran — interdite à l'agent, à l'auteur de jouer ;
      - **surface de concurrence**, balayage complet des états mutés par
        `scanMods()` (qui peut courir contre lui-même, queue globale
        concurrente, cas admis au `manifestCache`) : le cache est verrouillé
        des deux côtés (lecture `:2752`, écriture `:2894`) ; les trois index
        de dépendances (`installedUniqueIds`, `installedModStates`,
        `installedModsByUniqueId`) n'ont **pas** de verrou et n'en ont pas
        besoin — écrits uniquement sous `main.async` (`:3099`, `:3770`),
        lus par les rendus de vues : **confinement main, invariant à
        préserver** (les déplacer hors main sans verrou referait la classe
        `EXC_BAD_ACCESS` qu'a eue le cache) ; registre
        (`installedModRegistryLock` + `defer`), mesure du poids
        (`modsSizeLock` + drapeau de re-demande), `parseSMAPILog` (parsé en
        fond, publié sur main) : tous au pattern ;
      - **une observation, sans défaut** : la quarantaine du réparateur est
        nommée à la seconde (`ModFolderRepairer.nowStamp`, pas d'UUID —
        même forme que X81), donc deux réparations concurrentes dans la
        même seconde partagent le même `_Trash_`. Conséquence nulle :
        `moveToTrash` est fail-safe par item (échec → item laissé en place,
        jamais d'abandon, la passe suivante le reprend), pas de perte
        possible. Un suffixe UUID serait l'endurcissement trivial si le
        réparateur prend un jour un état de passe.
      **L'audit F2 est complet.** Restent ouverts ses deux sous-items de
      build — **F2-T1** livré, **F2-T2** (le bottleneck `swiftc`, un choix
      d'architecture) — et les **correctifs** de perf, dont le seau désigné
      est **F3**.
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

### 8.0 Priorité courante — **le risque de perte de données** (2026-09-04)

Les 73 items ouverts ont été confrontés au code le 2026-09-04, un par un : pas
lus, **vérifiés** — la condition que chacun affirme, cherchée là où il dit
qu'elle est. Résultat de la passe : **une case fausse** (`F1-T1`, terminé le
2026-08-01, son propre corps l'écrivait), **un doublon d'une tâche livrée**
(`R4` = `B3-T5`), **un constat neuf** (`X59`, trouvé en vérifiant `R2`) ; tous
les autres constats sont **encore vrais aujourd'hui**. `X59` a été **clos le
même jour, sans correctif** : la vérification qui l'a ouvert s'était arrêtée au
paramètre `completion`, sans lire les cinquante lignes où la méthode montre
elle-même l'alerte. Un constat n'est acquis qu'une fois le chemin lu **jusqu'à
l'écran**.

L'ordre ci-dessous répond à une question précise — *qu'est-ce qui peut détruire,
corrompre ou faire disparaître quelque chose sans le dire ?* — et non à
« qu'est-ce qui a le plus de valeur ». Les deux ne donnent pas le même ordre.

**P1 — peut faire perdre quelque chose**

| Rang | Item | Ce qui se perd | Ce que la vérification a établi |
|---|---|---|---|
| ~~1~~ | ~~**X55**~~ | ✅ **Corrigé le 2026-09-04** — politique « on efface tout » tranchée par l'auteur. 35 entrées fantômes mesurées dans les préférences réelles au moment du correctif ; les anciennes restent, les balayer heurterait X25. Voir l'archive |
| ~~2~~ | ~~**X25**~~ | ✅ **Livré le 2026-09-04** — l'écran « Entretien » : inventaire mesuré (1,80 Go de sauvegardes, 340 dossiers orphelins, 35 clés mortes, 1 seule copie protégée), purge par cran sous confirmation, nettoyage explicite des orphelins et clés — jamais de passe automatique. Voir l'archive |
| ~~3~~ | ~~**R6**~~ | ✅ **Livré le 2026-09-04** — la règle extraite dans `ProfileApplyPlan` (Core), 10 tests dont la propriété sur 200 parcs engendrés. Verdict : **idempotent**, la seconde passe ne redemande que ce que le disque a refusé. Ce que la propriété a mis au jour : `X60`. Voir l'archive |
| ~~4~~ | ~~**R2**~~ | ✅ **Livré le 2026-09-06** — garde jeu (refus net, quatre entrées), journal write-ahead + dialogue de reprise au lancement, blocage de l'adoption silencieuse après crash, desync marqué au saut jeu ouvert. Le « backup timestamped » RimManager écarté : l'état pré-apply = le plan, quelques Ko. Voir l'archive |
| ~~4bis~~ | ~~**R2bis**~~ | ✅ **Livré le 2026-09-07** — complément trouvé en vérifiant R2 : le bouton de lancement pouvait repartir une seconde instance dans la fenêtre aveugle où le jeu n'apparaît pas encore dans `NSWorkspace`. Refus net jeu ouvert + délai de 10 s (`GameLaunchGate`). Voir l'archive |

**P2 — masque une information, ou en affirme une fausse**

| Rang | Item | Ce qui est caché ou faux |
|---|---|---|
| ~~5~~ | ~~**X59**~~ | ✅ **Constat faux, clos le 2026-09-04** — l'alerte existe et nomme les mods : `applyProfileToFilesystem` appelle `showModal` avant de rendre la main, et `MainView` porte le `.alert` en permanence. Le `_` du changement de profil ne jette qu'un **compte**, pas le signal. Voir l'archive |
| ~~6~~ | ~~**X31**~~ | ✅ **Corrigé le 2026-09-04** — marqueur et journal départagés par leur date d'écriture (`SmapiVersionEvidence`, 13 tests). Voir l'archive |
| ~~7~~ | ~~**X54**~~ | ✅ **Corrigé le 2026-09-04** — deux clés neuves : l'ajout nomme le mod, l'import dit combien de favoris sont entrés. Voir l'archive |
| ~~8~~ | ~~**X49**~~ | ✅ **Corrigé le 2026-09-04** — jeton d'époque (`RequestEpoch`, Core, 6 tests) sur la recherche **et** sur la fiche, second exemplaire trouvé en câblant. Voir l'archive |
| 9 | **F6-T4** | Une ancre « je l'ai déjà » ratée quand le manifeste et l'ancre diffèrent par la casse. ⚠️ **Réévalué le 2026-09-04 : ce n'est pas un S.** Corriger la seule lecture créerait la divergence que l'item décrit ; le faire d'un bloc demande de normaliser la clé à l'écriture **et** de migrer les ancres déjà posées. Aucun observable sur le parc — ne pas le reprendre comme « petit correctif » |
| 10 | ~~**X58**~~ ✅, ~~**X60**~~ ✅, ~~**C2-T4**~~ ✅, ~~**X47**~~ ✅ | ~~Ce qu'un mod garde en silence~~, ~~l'échange de noms de dossier qu'un profil ne peut pas faire~~, ~~les lots smapi.io abandonnés après un échec~~ *(corrigés le 2026-09-05 — voir l'archive)* et ~~les clés de config perdues à une mise à jour~~ *(livré le 2026-09-08 — la case C2-T4 ci-dessus porte le constat)* |

**P3 — latent : la condition est vraie, zéro exemplaire sur le parc**

`F4` (`uniqueId: ""` sur les groupes — chaîne d'exploitation coupée),
`F6-T1` (course à l'annulation, sans observable), `F6-T3` (deux parseurs du
même journal). Vérifiés un par un : tous encore exacts, aucun ne se manifeste.
À traiter quand on passe à côté, pas pour eux-mêmes.

**P4 — chantiers et fonctionnalités** *(rien à perdre, tout à construire)*

Par lot, dans l'ordre de ce que l'axe « perte de données » recommande de faire
ensuite : **F2** (audit sécurité et perf — c'est lui qui trouverait les X à
venir), **F5** (identité de bundle partagée avec l'amont : 31 clés de
préférences et le Trousseau en commun), puis ~~**C4**~~ *(clos le
2026-09-09 : T1 et T7 livrés, T8 réfuté et coché sans code — §8.2)*,
~~**H**~~ *(clos le 2026-09-09)*, **A** (A1-T1/T2, A2-T5, A5-T4/T5), **D1/D2**
(Profiler et télémétrie), **C3/C5/C6**, **I** (accessibilité — **débloqué**, H est clos),
**E1–E3** et **D3** (horizon, sous décision produit).

**Non classés ici parce qu'ils attendent une décision, pas un développement** :
~~`X55`~~ *(politique de purge — **rien n'attend** : tranchée « on efface tout »
le 2026-09-04 et implémentée (`ModRemovalPurge`). Son seul reliquat assumé —
les 35 entrées fantômes déjà en place, à balayer « comme un ménage explicite,
jamais comme un automatisme » — est **couvert par X25** :
`MaintenanceInventory.stalePreferenceKeys` juge exactement les quatre magasins
que X55 a câblés, sous bouton, avec la garde du parc vide que X55 réclamait.
**Mesuré sur les préférences réelles le 2026-09-09 : 0 fantôme** sur 735
entrées — 537 horodatages d'activation, 188 identifiants Nexus, 10 configs de
profil, tous pointant sur un dossier existant. Ne pas rouvrir)*,
`X103` (suppression des mods : corbeille livrée en
X103-B ; reste la rétention des archives Nexus, §8.1 option C), `D3-T1`
(un backend ou non), `F5` (quand casser la cohabitation avec l'amont),
`F1-T2` (règle permanente, pas une tâche).


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

### 8.1 Cadrage X103 — la suppression peut-elle se défaire ? *(instruit le 2026-09-09, **B tranché et livré le jour même** ; C encore ouvert)*

> **Arbitrage rendu le jour même (2026-09-09) : option B, livrée en séance** —
> type Core `ModTrash` (corbeille `Mods/_Trash_*`, 15 tests), « Remettre »
> en désactivé, purge nominative et « Vider » à l'écran Entretien, jamais de
> purge automatique. L'option C (rétention des archives Nexus) reste une
> suite possible, non planifiée.
>
> **Ce que l'option C coûterait, mesuré le 2026-09-09** — les chiffres
> manquaient au tableau ci-dessous, qui la jugeait « M-L » sans les avoir.
> Sur le parc de référence : **723 manifestes sur 1 102 (65 %) déclarent un
> `Nexus:<id>`** et sont donc éligibles ; ils pèsent **3,1 Go décompressés**
> sur les 13 Go du parc — les 379 restants, sans clé Nexus, en pèsent dix à
> eux seuls (gros packs de contenu). Une archive conservée par mod éligible
> ferait donc de l'ordre de **1,7 Go**.
> ⚠️ **Mais ce coût ne s'applique pas rétroactivement** : l'option ne peut
> garder que les archives des mods **installés depuis l'app**, à partir du
> jour où elle existe. L'empreinte part de zéro et croît à l'usage — ce qui
> change la nature de la décision : la question n'est pas « accepte-t-on
> 1,7 Go », mais « veut-on une rétention à régler, et sur quel critère ».
> Le geste existe déjà pour les sauvegardes (rétention par âge/taille de
> `ModInstallBackupManager`) et son écran aussi (Entretien, X25) : c'est
> autant de neuf en moins que ne le disait « nouveau magasin, nouvelle
> rétention, nouvelle UI ».

> Les faits ci-dessous sont relevés dans le code au jour dit, pas supposés.
> La question : supprimer un mod est définitif (`removeItem` direct, confirmé
> aux trois points d'entrée — `ModListView:558`, `ModListView:2093`,
> `ModDetailView:155`), là où le réparateur met en quarantaine et les
> sauvegardes se restaurent. L'uninstall Vortex, lui, reste réversible
> (archive conservée en staging, purge = geste séparé).

**Ce que la suppression laisse déjà derrière elle** (`deleteMod`,
`StarHubTHViewModel.swift:10796` + `forgetStores`) :

- les **sauvegardes d'installation** (`ModInstallBackupManager`) et de
  config (`ModConfigBackupManager`) **survivent** au mod supprimé — la
  restauration d'une sauvegarde d'installation recrée le mod **en
  désactivé** (`Mods/.X`) depuis le navigateur de sauvegardes. *Un chemin
  de retour existe donc déjà* — mais il n'est pas garanti : la rétention
  hybride (`cleanupOldBackups`, purge par âge/taille) peut emporter la
  dernière sauvegarde d'un mod qui n'est plus là pour la re-provoquer ;
- huit magasins + l'historique d'erreurs + la baseline de traduction +
  favoris + liste « à écarter » sont purgés nommément — les ramener du
  retour ne restitue pas favori ni verdicts : un mod restauré est un mod
  **neuf** pour l'app ;
- l'**archive Nexus** ne survit jamais : posée dans
  `tmp/StarHubFR-download-<UUID>/`, elle est effacée **à la fermeture de
  la feuille d'installation** — installée, annulée ou échouée
  (`MainView:304-312`). Réinstaller un mod supprimé = retélécharger.

**Trois issues** :

| Option | Geste | Coût | Ce qu'elle vaut / ce qu'elle risque |
|---|---|---|---|
| **A — permanence assumée** | rien, documenter (« la sauvegarde d'installation est votre corbeille, dans la limite de la rétention ») | ~0 | Zéro code, zéro surface. Risque : la rétention peut déjà avoir mangé le retour — promettre « réversible » serait mentir |
| **B — corbeille dédiée** | `deleteMod` déplace vers `Mods/_Trash_<horodatage>/` (le préfixe que le scanner skip déjà) ; purge = bouton Entretien ou rétention bornée ; restaurer = remettre en `Mods/.X` | **M** | Le retour devient garanti et à un geste. Le pattern `_Trash_` existe (`ModFolderRepairer.trashPrefix`, fail-safe X-épreuve). Attention : la corbeille grossit dans le dossier du jeu — la faire compter dans la mesure du poids et la purge automatique doit être explicite, jamais une heuristique silencieuse (leçon X25) |
| **C — rétention des archives Nexus** | garder l'archive dans un dossier d'application (pas tmp), rétention par âge/taille, « réinstaller depuis l'archive » sur un mod absent | **M-L** | L'équivalent Vortex exact : réinstallation instantanée, hors-ligne, même version. Nouveau magasin, nouvelle rétention, nouvelle UI — et ne sert qu'aux mods installés via Nexus |

**Recommandation de l'agent** : **B minimal**, le plus proche du geste déjà
posé par le réparateur — il rend le retour garanti sans créer de magasin
nouveau. **C** n'a de sens que si l'auteur veut la réinstallation instantanée ;
le faire seul (sans B) laisserait la suppression aussi définitive
qu'aujourd'hui pour un mod installé à la main. **A** reste défendable si la
page des sauvegardes gagne d'abord une porte « restaurer sur un mod
supprimé » — le retour existe, il n'est juste pas *trouvable*.

---

### 8.2 Cadrage C4-T8 — le journal SMAPI peut-il montrer la normalisation ? *(instruit le 2026-09-09, **tranché A le jour même**)*

> ✅ **Décision de l'auteur, 2026-09-09 : option A — clore sans code.** C4-T8 est
> cochée en constat réfuté. Les options B et C ne sont pas retenues ; la section
> reste ici pour porter la mesure, et le signal de réouverture est nommé dans la
> case (un **second** mod publiant un triplet *voulu / effectif / pourquoi*).

> **Verdict de la mesure : non, pas sur ce parc.** La tâche pariait qu'un mod
> journalise sa configuration *normalisée*, et qu'il suffirait de la comparer au
> `config.json` pour dire « le mod a ramené 8192 à 4096 » sans coder de borne.
> Les trois maillons du pari ont été vérifiés dans le journal réel de l'auteur, un
> par un. Les trois cèdent — le détail chiffré est dans la case **C4-T8** ci-dessus.

| Maillon du pari | Ce que la mesure donne |
|---|---|
| « Assez de mods journalisent leur config » | **2 sur ~966**, un seul hors `TRACE`. Un journal non verbeux — celui de la plupart des utilisateurs — n'en porte **qu'un** |
| « On rapproche la ligne du `config.json` » | **SLO, l'exemple qui a motivé la tâche : 3 clés communes sur 46.** Il renomme tout dans son journal. Le rapprochement demanderait une table par mod — qui périme comme les bornes qu'on refusait de coder. UIS2, lui, se rapproche à **85/85** |
| « L'écart révèle la normalisation » | **0 écart sur les 85 clés d'UIS2**, et les 5 clés SLO rapprochables à la main sont identiques au fichier. Le journal **reproduit** la config lue ; il ne montre pas de correction |

**Trois issues** :

| Option | Geste | Coût | Ce qu'elle vaut / ce qu'elle risque |
|---|---|---|---|
| **A — clore sans code** | décocher C4-T8 comme constat réfuté, garder la mesure ici | ~0 | Honnête, et daté : si le parc change (un second mod adopte l'idiome), la case se rouvre sur des chiffres. Risque : aucun — la fonctionnalité n'aurait rien affiché sur les deux seuls mods éligibles |
| **B — lire les triplets de SLO** | afficher tel quel `configured=X, effective=Y, reason=Z` sur les 3 options SLO qui le publient, sans rapprochement de clé | **S** | C'est la **vraie** normalisation, et elle se lit sans deviner. Mais **un seul porteur sur le parc** : une fonctionnalité écrite pour un mod, avec le risque que sa prochaine version change le format |
| **C — table de correspondance par mod** | écrire à la main `prefetchLimit ↔ PrefetchMaximumMegabytes`… | **M**, récurrent | Rendrait SLO rapprochable — mais c'est exactement la dette que la tâche disait éviter, et pour montrer **zéro écart** aujourd'hui |

**Recommandation de l'agent** : **A**. Le pari n'échoue pas sur la rareté seule
— il échoue sur le troisième maillon, celui qu'on ne peut pas contourner en
attendant plus de mods : là où le rapprochement fonctionne parfaitement (UIS2,
85/85), l'écart mesuré est nul. **B** est la seule piste qui apprend quelque
chose à l'écran, mais elle n'est pas cette tâche : elle ne compare rien, elle
répète ce qu'un mod unique déclare. À rouvrir si un second mod publie un triplet
*voulu / effectif / pourquoi* — c'est le signal à guetter, pas le nombre de mods
bavards.

---

### 8.3 Cadrage H-T5c — recomposer le portrait du fermier ? *(instruit le 2026-09-09, **abandonné le jour même**)*

> ⛔️ **Décision de l'auteur, 2026-09-09 : abandon.** H-T5c est fermé — ni
> option B ni option C : l'item ne migre pas vers un autre axe, il ne se fait
> pas. L'avatar garde son illustration fixe par sexe. La section reste ici pour
> porter la **réfutation du prérequis** : si la question revient, elle repart de
> ces mesures et non de la phrase fausse qu'elle a remplacée.

> **La question n'est pas « est-ce possible » — ça l'est — mais « est-ce que
> l'axe H a le droit de le faire ».** Le prérequis qui bloquait cet item est
> faux : les calques existent dans le `Content` du jeu installé, et le dépôt
> décompresse déjà le LZX. Les chiffres sont dans la case **H-T5c** ci-dessus.
> Ce qui l'arrête désormais, c'est le non-but §9 de la spec de refonte :
> « **aucune fonctionnalité nouvelle** ». Un lecteur de textures n'est pas du
> restylage.

**Ce que ça demanderait vraiment**, au-delà de ce qui existe :

| Brique | État | Ce qu'il faut écrire |
|---|---|---|
| Décompression LZX | ✅ existe (`Lzxd*`, 4 fichiers) | rien |
| Lecture XNB | ⚠️ partielle | le dépôt lit des **dictionnaires de chaînes**, pas des pixels : il manque le `Texture2DReader` (format de surface, dimensions, mips, RGBA) |
| Index des coiffures | ❌ | `<hair>` → région dans `hairstyles.xnb` / `hairstyles2.xnb`, avec le seuil de bascule entre les deux |
| Palette de peau | ❌ | `skinColors.xnb` (non compressé — le plus facile des trois) |
| Composition | ❌ | ordre des calques, teinte de `<hairstyleColor>`, cadrage tête |

**Trois issues** :

| Option | Geste | Coût | Ce qu'elle vaut / ce qu'elle risque |
|---|---|---|---|
| **A — laisser fermé dans l'axe H** | garder le repli actuel (illustration fixe par sexe), déplacer H-T5c hors de H | ~0 | Respecte §9 sans discussion. L'avatar reste faux pour qui a changé de coiffure — un défaut d'exactitude, pas d'esthétique |
| **B — exception §9 explicite** | ouvrir H-T5c comme lot, en assumant que l'axe H produit une capacité neuve | **L**, pas M | Le portrait devient juste. Mais c'est le plus gros morceau de code neuf de l'axe, et il ouvre une dépendance au format d'assets du jeu — qui change à chaque version majeure |
| **C — sortir de l'axe H** | en faire un item d'un axe « fonctionnalités » (D ou E), planifié pour lui-même | ~0 aujourd'hui | Honnête sur sa nature, et le fait juger sur sa valeur propre plutôt que dans un lot d'uniformisation où il détonne |

**Recommandation de l'agent** : **C**. La réfutation du prérequis vaut d'être
gardée — elle transforme un item « impossible » en item « faisable et
chiffré ». Mais le faire *sous l'axe H* obligerait à lire §9 comme une règle
qu'on contourne dès qu'un item est tentant ; et H-T9, le closage, aurait à
auditer la fidélité visuelle d'un écran qui aurait changé de nature pendant le
chantier. **A** revient au même si l'auteur ne veut pas de l'item du tout.

⚖️ **Contrainte à connaître avant de trancher, pas après** : lire le `Content/`
du jeu **installé sur la machine de l'utilisateur**, à l'exécution, ne
redistribue rien — c'est son propre exemplaire. En revanche l'app ne doit
**jamais embarquer** de sprites extraits dans son bundle ni dans le dépôt : ce
serait redistribuer des assets sous copyright ConcernedApe. Toute
implémentation lit à l'exécution, et échoue proprement si le dossier est
absent.

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
      · **M** · ~~*à pousser dans l'axe H (cohérence UI), après H-T1.*~~
      ⚠️ **Ancrage caduc depuis le 2026-09-09 : l'axe H est clos et R1 n'y a
      pas été traité.** Il n'a jamais été un item H — il y était seulement
      *renvoyé*. Reste ouvert et sans axe : à rattacher (I, ou un lot de thème)
      ou à instruire pour lui-même. Ne pas le croire livré parce que H l'est.
- [x] **R2** ✅ *(livré le 2026-09-06)* — **Écriture atomique + apply guard pour
      `applyProfileToFilesystem`.** Le garde jeu (refus net, quatre entrées), le
      journal write-ahead et le dialogue de reprise au lancement sont livrés ; le
      « backup timestamped » du pattern RimManager a été écarté — l'état
      pré-apply est le plan lui-même, quelques Ko au lieu de dizaines de Go sur
      le parc. Récit et mesures : archive §4. Spec :
      `docs/superpowers/specs/2026-09-06-r2-apply-guard-design.md`.
- [x] **R3** ✅ *(livré le 2026-09-07)* — **Snooze d'updates Nexus.** Granularité : 1 semaine / jusqu'à prochaine
      version du mod / jusqu'à prochaine version de Stardew. Persiste en UserDefaults,
      expire tout seul, retire le mod de la liste « updates » sans le masquer dans
      l'inventaire. Répond à un vrai UX gap : aujourd'hui, ignorer un update = l'avoir
      en permanence sous les yeux.
      · **S** · *axe B.*
- [x] **R4** ✅ *(sans objet — c'est **B3-T5**, livré ; constaté le 2026-09-04)* —
      **Profils = modlist + configs isolées.** La veille RimManager a redemandé ce que
      l'axe B avait déjà livré : `profileManagedConfigMods` existe en production
      (`UDKey.swift:52`, `StarHubTHViewModel.swift:316`), la capture se fait au profil
      sortant et la restauration au profil entrant. Voir **B3-T5** dans l'archive.
- [ ] **R5** — **Historique append-only des actions.** Modèle RimManager : chaque
      `apply`, `sort`, `install`, `delete` crée un snapshot, restaurable sans
      réécrire l'historique. Pinning (étoile) protège du pruning auto à 30 j. Remplace
      l'actuel *« annuler la dernière action »* (s'il existe) par un vrai timeline.
      · **M** · *B3-T1+ : à concevoir avec R4 pour partager le store.*

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

---

## 11. Index des items livrés

Un item terminé n'occupe plus la roadmap : son récit, ses mesures et ce qu'il a
écarté au passage vivent dans [`roadmap-archive.md`](roadmap-archive.md). Cette
table dit seulement **quoi chercher et où** — les identifiants sont ceux que
citent le code et les messages de commit, et un `grep` dessus dans l'archive
rend le texte complet.

⚠️ **Deux exceptions à cette table.** Un item coché reste sur place quand le
sortir perdrait son sens : les sous-items d'un parent ouvert (`F1-T1`, `F2-T1`,
`F2-T2`, `F6-T2` — au §7, sous leur parent) et `R4` au §10.3, qui n'existe que
pour dire à la prochaine lecture de la veille que cette action-là est déjà
livrée sous le nom `B3-T5`. Et un identifiant qui ne se trouve ni ici
ni dans l'archive n'a jamais existé sous cette forme — vérifier la casse et le
suffixe (`H-T5b`, pas `H-T5B`).

**4. Correctifs identifiés — à traiter en premier**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **X1** | 2026-07-30 | Le copier/coller fonctionne dans le champ NexusID comme ailleurs dans l'app (vérifié par l'utilisateur, 2026-07-30).… |
| **X2** | — | Le rendu des descriptions casse sur du BBCode réel |
| **X4** | — | Toute archive créée sous Windows est refusée à l'installation |
| **X5** | — | RAR non pris en charge dans le flux de mise à jour |
| **X6** | — | Tout le parcours d'installation parle de « zip » alors qu'il accepte aussi le RAR |
| **X7** | — | La mise à jour d'un mod échoue si ses dossiers sont en lecture seule |
| **X8** | 2026-08-31 | Le MAIN pris pour référence sur files.json peut être obsolète |
| **X9** | 2026-08-31 | Le check compare le manifeste installé au libellé Nexus posé par l'auteur — deux vocabulaires différents |
| **X3** | 2026-07-30 | Bouton « Activer » de la page dépendances sans effet |
| **X10** | 2026-09-03 | L'accord en genre était traité comme une marque intouchable |
| **X11** | 2026-09-03 | Une version affirmée illisible vidait un lot de 150 mods |
| **X12** | 2026-09-03 | « Je l'ai déjà » était un aller sans retour, et invisible |
| **X13** | 2026-09-03 | Rien ne disait qu'un dossier était disputé par deux mods |
| **X14** | 2026-09-03 | Deux sauvegardes différentes rendaient la même empreinte, et l'une était supprimée |
| **X15** | 2026-09-03 | Un champ composé de balises auto-fermées se lisait comme un scalaire — et l'écriture détruisait sa structure |
| **X16** | 2026-09-03 | Un 403 de lien expiré accusait la clé API |
| **X17** | 2026-09-03 | Déposer un contenu reconnu dans un hôte en 0555 échouait sans recours |
| **X18** | 2026-09-03 | Le framework qu'exige un content pack manquait à ses dépendances, à l'installation |
| **X19** | 2026-09-03 | Une dépendance installée dans un pack était annoncée manquante |
| **X20** | 2026-09-03 | L'ancrage d'après- installation visait un dossier qui n'existe pas, pour un composant de pack |
| **X21** | 2026-09-03 | L'app rendait la sauvegarde sans la marque d'octets que le jeu y met |
| **X22** | 2026-09-03 | La restauration d'un composant de pack fabriquait un pack jumeau |
| **X23** | 2026-09-03 | Supprimer une sauvegarde de composant laissait son dossier horodaté vide |
| **X24** | 2026-09-03 | Le ménage automatique ne réparait pas les droits avant de supprimer |
| **X26** | 2026-09-04 | Le balayage des résidus posait deux questions au disque par entrée avant de regarder le nom |
| **X27** | 2026-09-04 | La garde du premier niveau du réparateur n'énumérait que les résidus fichiers |
| **X30** | 2026-09-04 | Une réponse refusée par l'installateur SMAPI figeait l'app en avalant la mémoire |
| **X33** | 2026-09-04 | Le filet de la récupération de fichiers bloquait la récupération d'un mod en pause |
| **X34** | 2026-09-04 | La restauration d'une config écrivait au nom logique, la sauvegarde lisait le nom physique |
| **X35** | 2026-09-04 | Le filet d'avant restauration ne couvrait pas ce qu'il écrasait |
| **X36** | 2026-09-04 | Un fichier impossible à écrire abandonnait toute la restauration de configs |
| **X37** | 2026-09-04 | Une restauration de configs annonçait « restaurée » même quand elle avait tout sauté |
| **X42** | 2026-09-04 | Trois lectures divergentes du champ Version d'un manifeste |
| **X44** | 2026-09-04 | Quel mod on trouve quand deux dossiers déclarent le même UniqueID dépendait de l'ordre du dossier Mods/ |
| **X46** | 2026-09-04 | Une vérification amputée était enregistrée comme un passage réussi du parc entier |
| **X48** | 2026-09-04 | Une branche du lancement pouvait laisser l'app sans aucune fenêtre |
| **X50** | 2026-09-04 | Tranche des fichiers racine de StarHubTH/ terminée |
| **X51** | 2026-09-04 | « Tout activer » supprimait définitivement le mod qui portait le même nom de dossier |
| **X52** | 2026-09-04 | La vérification des mises à jour se déclarait terminée pendant la reprise Nexus |
| **X53** | 2026-09-04 | Le hub thaï cherchait sous le nom logique |
| **X56** | 2026-09-04 | Le filet de compatibilité était muet sur les mods dont il ne connaît que la mise à jour non officielle |
| **X57** | 2026-09-04 | La bascule en masse agissait sur le parc entier, depuis une liste filtrée |
| **X55** | 2026-09-04 | Le ménage à la suppression d'un mod était partiel — quatre magasins survivaient au dossier |
| **X25** | 2026-09-04 | 340 dossiers de sauvegarde orphelins et 35 clés de préférences mortes — l'écran « Entretien » les nomme avant de les retirer, jamais automatiquement |
| **X59** | 2026-09-04 | Constat faux, clos sans correctif : l'alerte de fin d'application nomme déjà les mods restés du mauvais côté |
| **R6** | 2026-09-04 | Le plan d'application d'un profil extrait dans Core et prouvé idempotent sur 200 parcs engendrés |
| **X54** | 2026-09-04 | Le journal annonçait « profil créé » sur un ajout de mod et sur un import de favoris |
| **X31** | 2026-09-04 | La version de SMAPI affichée restait celle que l'app avait installée, même après une mise à jour faite ailleurs |
| **X49** | 2026-09-04 | Deux recherches Nexus rapprochées pouvaient revenir dans le désordre, et une réponse tardive ressuscitait une liste fermée |
| **X61** | 2026-09-04 | Le résidu écarté par la bascule en masse restait chargé par SMAPI, faute du point de tête que l'autre chemin posait |
| **X62** | 2026-09-04 | « Je l'ai déjà » ne tenait pas quand la version affirmée était une étiquette Nexus libre — 15 mods sur 38 revenaient à chaque vérification |
| **X76** | 2026-09-05 | Un index de sauvegardes absent ou corrompu rendait orphelines toutes les sessions réelles — 203 corbeillées d'un clic |
| **X47** | 2026-09-05 | Un lot smapi.io en échec sacrifiait les suivants — 795 mods livrés au quota Nexus pour un 503 qui ne les visait pas ; continuer, puis une seconde chance avec retrait |
| **X72** | 2026-09-05 | Le renommage offert à un composant de pack en collision était mort par construction — l'offre ne se fait plus (tranché par l'auteur) |
| **X75** | 2026-09-05 | L'inventaire étiquetait « traduction » le `i18n/fr.json` d'auteur d'un mod dès qu'un *autre* mod avait sa traduction au même chemin — 59 fichiers, protections fantômes en attente |
| **X74** | 2026-09-05 | Les préférences posées sur un en-tête de pack étaient jugées mortes — l'écran Entretien ne comptait que les composants |
| **X73** | 2026-09-05 | « Nom (A→Z) » triait par scalaires Unicode quand les six autres tris comparaient comme macOS — 190 des 951 mods du parc changeaient de place, et les deux sens du tri n'étaient pas inverses |
| **X71** | 2026-09-05 | Un `Mods/` illisible rendait un lot vide que le balayage purgeait sans condition — 1 097 entrées de registre et 251 ancres, copie de secours comprise |
| **X70** | 2026-09-05 | Le ménage jugeait mortes **toutes** les préférences quand aucun mod n'était lu — 616 entrées du parc effaçables d'un clic |
| **X69** | 2026-09-05 | Le registre des traductions suivait un renommage mais survivait à une suppression — un orphelin réel sur le parc |
| **X68** | 2026-09-05 | Le fond servant à corriger le contraste était lu sans apparence : blanc même en thème sombre, la correction partait à l'envers |
| **X67** | 2026-09-05 | La recherche GraphQL et le téléchargement voyaient un `429` sans armer le délai d'attente partagé, et ignoraient `Retry-After` |
| **X66** | 2026-09-05 | Trois chemins réécrivaient un `config.json` sans périmer le rapport de raccourcis ; seul l'éditeur le faisait |
| **X65** | 2026-09-05 | Le filet de sécurité des 30 s révélait la fenêtre sans délivrer les liens `nxm://` en attente |
| **X64** | 2026-09-05 | Le budget de re-découpage épuisé rendait un lot vide en silence, et la passe smapi.io se déclarait quand même complète |
| **X63** | 2026-09-05 | Installer un mod neuf effaçait le mod en pause qui portait le même nom de dossier — ni sauvegarde ni message |
| **X58** | 2026-09-05 | Le champ `warnings` du dump était ignoré en bloc ; il est désormais tamisé par plateforme et rendu en ligne « à savoir » |
| **X28** | 2026-09-06 | Un dossier de résidu OS niché dans un mod était vidé fichier par fichier mais sa coquille restait pour toujours — il part désormais en bloc, comme au premier niveau |
| **X43** | 2026-09-06 | Le dialogue de conflit de `config.json` n'a jamais existé à l'écran — ses enums et son champ de sélection, vestiges d'une bascule de conception, sont retirés ; la préservation automatique reste le comportement livré |
| **X45** | 2026-09-06 | Le dépliage des packs restait réécrit à la main en dix sites après la consolidation de `flattenedMods` — `ModItem.components` couvre désormais la forme à un seul mod, et les dix sites l'appellent |
| **X29** | 2026-09-06 | La détection de doublons sur disque gardait une quatrième copie de la lecture de manifeste (regex aveugle aux chaînes) — elle lit par `ManifestJSON.decode` comme le scan ; parité mesurée : 1 101 manifestes, zéro divergence |
| **X32** | 2026-09-06 | L'installateur SMAPI se pilotait par quatre réponses à l'aveugle dont l'ordre était supposé stable — invoqué par ses drapeaux `--install/--uninstall --game-path`, une seule question reste et un dossier refusé rend son diagnostic |
| **X77** | 2026-09-06 | La présence de SMAPI se jugeait sur `StardewValley-original`, jamais posé par une installation propre — elle se juge désormais sur `smapi-internal/`, partagé avec les preuves de réussite de l'installateur |
| **X78** | 2026-09-07 | La file Nexus écrasait l'entrée Premium d'un `fileId` par une `nxm://` arrivée ensuite avec clé bornée — le payeur voyait son téléchargement refusé pour un partage de session |
| **X79** | 2026-09-07 | « Traduction espagnole de X » passait pour une traduction française dans les annonces Nexus — les variantes longues des autres langues annulent désormais le match |
| **X80** | 2026-09-07 | La clé `nxm://` n'était protégée que partiellement dans l'URL — le percent-encoding couvre `&`, `=`, `+`, `;` et `%` |
| **X81** | 2026-09-07 | Un double-clic sur « Installer SMAPI » faisait partager fichiers de travail et téléchargement entre deux passes — dossier temp nommé par UUID, créé à la demande, nettoyé par `defer` |
| **X82** | 2026-09-07 | Les trois `Process` de l'installateur SMAPI (`unzip`, `xattr`, installateur .NET) héritaient de la locale système — `en_US_POSIX` posé, le verdict de succès lit des chaînes anglaises |
| **X83** | 2026-09-07 | Le download GitHub de SMAPI n'avait aucun timeout — session dédiée et éphémère, 30 s par ressource, 60 s global |
| **X84** | 2026-09-07 | DeepL ignorait le `Retry-After` d'un 429 et jetait la traduction après un délai fixe — le délai du serveur est lu et appliqué, borné à 60 s |
| **X85** | 2026-09-07 | Le LLM local tronquait toute source de plus de ~700 caractères (`max_tokens` 1024, `finish_reason=length`) — plafond 4096, dérivé de la source (2 × `source.count`, plancher 64) |
| **X86** | 2026-09-07 | La requête smapi.io ne gardait pas `platform` : `"macOS"` rend un HTTP 200 et une liste vide en silence — une `precondition` au plus près de la sérialisation fait tomber le test rouge au geste fautif |
| **X87** | 2026-09-07 | smapi.io n'avait pas de mur de rate-limit entre les lots — un 429/503 arme une porte de 30 s, désarmée au premier lot réussi, et un `fetch` concurrent est sérialisé |
| **X88** | 2026-09-07 | Le download SMAPI ne distinguait pas 4xx et 5xx — « fichier indisponible » contre « réessayez dans quelques minutes » |
| **X89** | 2026-09-07 | Le renommage d'un mod avalait l'échec de persistance du suivi des traductions (`_ =` au site 12 de X60) — le registre relu gardait l'ancien hôte, la désinstallation ne retrouvait plus les fichiers ; les huit autres sites qui écrivent ce registre le disaient déjà |
| **X90** | 2026-09-07 | `ModConfigBackupManager.saveIndex` se taisait en échec — sauvegarde complète sur disque mais invisible dans la liste, et purgable comme orpheline ; aligné sur le `print` CRITICAL du manager jumeau (`dd6b4d1`) |
| **X91** | 2026-09-07 | Trois fichiers de `Models/` n'ont jamais été listés dans `Package.swift` (`ModCompatibilityStore`, `ModDetailCache`, `NexusFileDownload`) — compilés dans l'app, invisibles de `swift build` et des tests ; ajoutés, preuve par 2 359 tests verts. `ModListFilters`, extrait du VM pour être testable, reste bloqué : il dépend de `FrenchTranslationScope` défini dans une vue |
| **X92** | 2026-09-08 | `loadBlacklistedMods()` n'a jamais eu d'appelant — la marque « à écarter » s'écrivait mais repartait à vide à chaque ouverture ; chargée au démarrage dans le lot des magasins, symétrique des favoris (`799382c`) |
| **X93** | 2026-09-08 | La barre latérale était une pile plein-fixe sans défilement : en fenêtre basse, son bas (poids de `Mods/`, thème, langue) était écrêté — groupes déportés dans un `ScrollView`, pied épinglé (`ff7c154`) |
| **X94** | 2026-09-08 | Le snapshot des clés parsait les i18n en JSON strict : 125 des 241 fichiers EN/FR du parc (commentaires, virgules finales) refusés que le jeu charge — le composant disparaissait et le delta comptait faux dans les deux sens ; `I18nLenientParser.lenientObject` (une valeur numérique reste lisible), `config.json` reste strict (`400ade8`) |
| **X95** | 2026-09-08 | « Voir la fiche » posait les pendings puis `currentTab = "Mods"` depuis… l'onglet Mods : aucune affectation ne change, le `.onChange` ne tourne jamais — fiche fantôme au prochain changement d'onglet et `pendingDetailTab` imposant « État » à la fiche suivante ; ouverture directe quand on y est déjà (`5e0187e`) |
| **X96** | 2026-09-08 | Les paires de config s'affichaient au point plein vert (signal sûr) alors qu'elles ne viennent QUE de l'heuristique de nom — la config n'a pas de signal par valeur ; point creux (`3bf2a87`) |
| **X97** | 2026-09-08 | Le garde d'écriture (config.json changé sous nos pieds), un fichier illisible ou un échec d'écriture rendaient `[]` → « Rien à reporter », indistingable du lot vide ; `KeyRenameReportOutcome` distingue appliqué / rien / annulé (`3bf2a87`) |
| **X98** | 2026-09-08 | La fiche relisait le delta sur disque et rejouait tout le matcher de renommage à chaque republication du VM — O(retirées × ajoutées) Levenshtein sans pré-filtre sur le fil principal ; caches par uniqueId+révision et pré-filtre de longueur normalisée (`a89e204`) |
| **X99** | 2026-09-08 | Supprimer un pack ne purgeait pas les deltas de ses composants : l'en-tête de groupe a `uniqueId` `""`, `remove` visait un fichier « .json » inexistant — fiches ressuscitant l'ancien install après réinstallation (X55 rompu pour ce store) ; `removeAll` passe les enfants (`d6633bd`) |
| **X100** | 2026-09-08 | Un report de traduction dont la paire CHANGE de composant écrivait la forme brute de la nouvelle clé dans le fr.json de l'ANCIEN — orpheline chez l'ancien, cible non traduite, paire passée réconciliée en silence ; `RenameReport.routeByOldComponent` les écarte et l'écran les annonce (`d50d2e6`) |
| **X101** | 2026-09-08 | Les préfixes de composants du report venaient de `mod.children` — nil sur la fiche d'un enfant imbriqué (les descendants d'un groupe vivent à plat sous l'en-tête) : clés qualifiées affichées mais « Rien à reporter » à jamais ; dérivés de l'arbre scanné par préfixe de folderName (`d50d2e6`) |
| **X102** | 2026-09-08 | Le snapshot ne découvrait les composants qu'à UN niveau contre `maxModDepth` pour la traversée de référence (commentaire « même convention » faux) — 6 mods imbriqués sur le parc dont 3 avec i18n se taisaient dans le delta ; récursion, composant nommé par chemin relatif (`d50d2e6`) |
| **X103** | 2026-09-09 | *Question de conception, sortie de la grille de revue des écritures (F2)* — supprimer un mod est définitif (`removeItem` direct, confirmé aux trois points d'entrée) là où les sauvegardes vont à la corbeille et le réparateur quarantaine ; l'archive Nexus est effacée après install — l'uninstall Vortex, lui, reste réversible (archive conservée). À trancher : quarantaine des mods supprimés, rétention des archives ? — **cadré en §8.1 puis tranché B le jour même, livré** : corbeille `Mods/_Trash_*` (type Core `ModTrash`, 15 tests, marqueur qui distingue la corbeille de la quarantaine du réparateur — même préfixe), « Remettre » en désactivé, purge explicite à l'écran Entretien, zéro purge automatique ; l'option C (rétention des archives Nexus) reste une suite possible |
| **X104** | 2026-09-09 | Déposer une traduction Nexus laissait son dossier `StarHubFR-download-<UUID>` vide en tmp — le `defer` n'effaçait que le fichier, quand le flux des mods passe par `discardDownloaded` (fichier + dossier) à la fermeture de la feuille ; **corrigé en séance** : `discardDownloaded` au `defer` — l'archive y vient toujours du téléchargeur, le geste est sûr sans condition (`MainView:onDismiss` déjà au pattern) |
| **B1-T1** | 2026-08-01 | Boutons Activer/Désactiver et Supprimer sur la fiche mod (parité avec la liste, mêmes confirmations). Absents pour un… |
| **B1-T2** | 2026-08-01 | Tri, filtres, catégorie, page et recherche portés par ModListFilters dans le ViewModel. La remise à la page 1 est por… |

**Bissection guidée — Axe A · livrée en v1.11.0**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **A4-T1** | — | Modèle de session de bissection (Core, testable) : ensemble de départ, partition en deux, verdict utilisateur (« ça p… |
| **A4-T2** | — | Application d'une étape : activer/désactiver la moitié courante en réutilisant la machinerie de profils, avec instant… |
| **A4-T3** | — | UI de session dans l'onglet Diagnostic : étape n sur ~log₂(N), liste des mods de l'essai courant, boutons de verdict,… |
| **A4-T4** | — | Respect des dépendances : ne jamais désactiver un framework dont un mod actif de l'essai dépend (sinon les faux posit… |
| **A4-T5** | — | Conclusion : l'écran final nomme le mod trouvé, le laisse en pause (tous les autres sont réactivés) et offre « tout r… |
| **A4-T6** | — | Actions sur le mod trouvé : page Nexus, fiche du mod (où vit son historique d'erreurs), et « garder ce mod en pause »… |

**Hub de traduction FR, phase 1 : diagnostic — Axe C · livrée en v1.13.0, C2-T4 le 2026-09-08**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **C1-T1** | — | Calculer, pour chaque mod, la couverture i18n : clés de i18n/default.json (ou en.json) présentes/absentes dans i18n/f… |
| **C1-T2** | — | Badge de couverture dans la liste des mods, branché sur le filtre FrenchTranslationScope existant. Livré (c6d4fec, be… |
| **C1-T3** | — | Section « Traduction » sur la fiche mod : compteur, date du dernier fr.json, lien vers l'éditeur. · M Livré (v1.13.0)… |
| **C1-T7** | — | Isoler les mods partiellement traduits : sur le parc, 392 sont complets et 31 ne le sont qu'en partie. Livré (6755f22… |
| **C1-T4** | — | ~~Test structurel « mod de traduction pure »~~ → requalifié et livré autrement (46ce633), après mesure sur le parc. -… |
| **C1-T5** | 2026-08-01 | Signaler qu'un fr.json disparu existe encore dans une sauvegarde. Mesuré le 2026-08-01 sur le parc réel : 92 mods ont… |
| **C1-T6** | — | Décoder les i18n/.json comme le fait SMAPI, dont le comportement a été mesuré sur la DLL du jeu : File.ReadAllText ho… |
| **C1-T8** | — | Un mod dont la seule traduction est fr-FR.json (variante régionale) s'affiche « traduit en français » dans le filtre… |
| **C2-T1** | — | Vue côte à côte : clé, valeur EN, valeur FR, état (traduite / manquante / identique à l'EN / obsolète). · M Livré (85… |
| **C2-T2** | — | Détection d'obsolescence : une valeur FR est suspecte si la valeur EN a changé depuis la dernière écriture du fr.json… |
| **C2-T3** | — | Recherche et filtre par état. Livré avec la vue diff (8538c17) : un cadrage par état dont le libellé porte le compte,… |
| **C2-T5** | — | Regrouper les lignes du diff par section de commentaire du fichier. Répond au besoin de « voir les dialogues par pers… |

**Hub de traduction FR, phase 2 : édition & assistance — Axe C · livrée par morceaux (v1.15.0 → v1.17.0)**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **C3-T1** | — | Édition en place depuis la vue diff (écriture atomique, backup systématique via ModConfigBackupManager). · M · risque… |
| **C3-T3** | 2026-08-19 | Pré-traduction assistée. Deux voies, l'une n'exclut pas l'autre : API distante (DeepL/Claude/Google, clé au trousseau… |
| **C3-T4** | 2026-08-19 | Glossaire de termes du jeu pour la cohérence (noms de PNJ, objets, saisons), amorcé depuis les traductions officielle… |
| **C3-T6** | 2026-08-18 | I18nLenientParser garde la première occurrence d'une clé JSON dupliquée ; le jeu (Newtonsoft) garde la dernière. Trou… |
| **C3-T7** | 2026-08-20 | Secours de traduction en ligne (DeepL) |
| **C3-T8** | 2026-08-21 | Traduire une sélection de la source |
| **C4-T4** | 2026-08-28 | §audit-config-menus — Lire le ConfigSchema de content.json (Content Patcher) : type, valeur par défaut, valeurs admis… |
| **C4-T5** | 2026-08-28 | §audit-config-menus — Sortir l'éditeur de JSONSerialization. Défaut indépendant des menus de config, trouvé en instru… |
| **C4-T6** | 2026-09-04 | Dire quand le fichier va être réécrit sous nos pieds |
| **C4-T1** | 2026-09-09 | Étiqueter les options des mods C# avec les libellés `config.*` de leur `i18n/` (FR champ par champ, repli clé brute) — `ConfigLabelResolver` + `groups(labeledBy:)`, 12 tests |
| **C4-T7** | 2026-09-09 | Angles morts keybind : co-déclenchements sous-ensemble (`SubsetOverlap`, jamais intra-mod), catégorie manette (`isGamepad`), collisions latentes des mods en pause (hors `problemCount`), R4 pour tous — 11 tests |
| **C4-T8** | 2026-09-09 | Constat réfuté, clos sans code (option A de §8.2) : le journal SMAPI ne montre pas la normalisation. 2 mods sur ~966 publient leur config entière, un seul hors `TRACE` ; SLO — l'exemple qui a motivé la tâche — renomme ses clés (3 communes sur 46) ; et là où le rapprochement est parfait (UIS2, 85/85), l'écart mesuré est **nul**. Le journal reproduit la config lue |
| **C4-T2** | 2026-08-29 | Champs de raccourcis clavier : validation des noms SButton, détection des collisions entre mods. · M §audit-config-me… |
| **C4-T3** | 2026-08-28 | Spike mené le 2026-08-28. Verdict : non-go sur les menus de config — et une meilleure source trouvée à côté. §audit-c… |

**Profils, favoris & backups exploitables — Axe B · B4 livré en v1.18.0, B3 aux trois quarts**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **B3-T1** | 2026-08-24 | Choix à la création : profil vide (défaut demandé) ou instantané des mods actifs. · S · validé à l'écran le 2026-08-2… |
| **B3-T2** | — | Favoris de mods, avec « importer les favoris dans ce profil ». Livré : étoile sur chaque ligne de premier niveau et s… |
| **B3-T3** | — | Duplication d'un profil. · S · ProfileFactory.duplicate, la copie porte son propre identifiant et n'est pas activée |
| **B3-T4** | 2026-08-24 | Diagnostic de profil au changement : mods manquants, dépendances non satisfaites, couverture FR (réutilise C1-T1). ·… |
| **B3-T5** | 2026-08-27 | Configurations par profil |
| **B3-T7** | 2026-08-27 | Supprimer un profil laisse son magasin de configs derrière lui. deleteProfile (StarHubTHViewModel.swift:7002) retire… |
| **B3-T6** | 2026-08-27 | Notes libres par mod, persistées au profil (annotations contextuelles : « désactivé en multi car désync », « à mettre… |
| **B4-T1** | 2026-08-22 | Regroupement par mod puis par version, tri (dernier backup, A→Z, Z→A), recherche. · M · livré le 2026-08-22 (7c9efce)… |
| **B4-T2** | 2026-08-24 | Retour utilisateur explicite après restauration (ce qui a été écrit, où). · S · validé à l'écran le 2026-08-24. ModIn… |
| **B4-T3** | 2026-08-24 | Garantir qu'une restauration met à jour le registre : version, écrasement du dossier existant, recréation s'il a disp… |
| **B4-T4** | 2026-08-01 | Récupérer un fichier isolé depuis une sauvegarde |
| **B2-T1** | 2026-08-27 | ETA et débit pendant les téléchargements Nexus, et panneau de downloads observable : statut par téléchargement, %, vi… |
| **B2-T2** | — | Poids par mod, total de Mods/, espace disque restant (en pied de barre latérale). Livré : Models/ModsFolderSizer.swif… |
| **B2-T3** | 2026-08-26 | Boutons de rafraîchissement sur la quarantaine et les alertes système ; sur la fiche mod, rafraîchissement automatiqu… |
| **B2-T4** | 2026-08-25 | Guidage quand unrar/unar/7z manque. Socle déjà en place : l'accueil affiche l'état d'installation de unar avec la com… |
| **B2-T5** | 2026-08-25 | ~~Reprendre l'affichage des dates d'un mod~~ → requalifié en ajout, puis livré. · S Revérifié le 2026-08-25 : ce n'ét… |
| **B2-T6** | — | Quota Nexus quotidien visible (header x-rl-daily-remaining). Livré : les six en-têtes x-rl- sont relevés sur toute ré… |
| **B2-T10** | 2026-08-27 | Re-vérifier par Nexus les mods que smapi.io n'a pas pu juger. La détection des mises à jour est intégralement délégué… |
| **B2-T9** | — | Trier la liste des mods par poids. Livré : chaque ligne porte sa taille (teintée au-delà de 100 Mo — 22 dossiers du p… |
| **B2-T8** | 2026-08-25 | Cesser d'émettre quand le quota est à zéro. NexusRateLimitGate replafonne son back-off à 15 min (maxBackoff) : sur un… |
| **B2-T7** | 2026-08-25 | UpdateCautionMessage : si un manifest installé expose ce champ (extension SMAPI tolérée, absente = pas d'alerte), ale… |
| **B1-T4** | 2026-08-25 | Réunir les problèmes dans l'onglet qui porte ce nom |
| **B1-T3** | — | Pastilles d'anomalie dans la liste des mods. Livré : une pastille orange près du nom réunit les trois signaux — erreu… |

**Fiabilité du registre & compatibilité — Axe A · à faire**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **A1-T3** | — | Installer une archive sans manifest.json |
| **A2-T1** | 2026-08-25 | Client de l'API smapi.io/api/v3.0/mods : POST ModSearchData (UniqueID + version installée + update keys + version SMA… |
| **A2-T2** | 2026-08-25 | Afficher le statut, brokeIn et le lien de mise à jour non officielle / mod de remplacement sur la fiche mod et dans l… |
| **A2-T3** | 2026-08-31 | Fallback sur Pathoschild/SmapiCompatibilityList (mods.jsonc, jointure sur UniqueID) quand smapi.io est injoignable, e… |
| **A2-T4** | 2026-08-25 | Cache persistant + update check incrémental |
| **A3-T5** | 2026-08-26 | Ce qui est posé se voit, se suit et ne se propose plus |
| **A3-T1** | 2026-08-25 | Recherche automatique des NexusID manquants (correspondance nom + auteur, proposition validée par l'utilisateur, jama… |
| **A3-T2** | 2026-08-25 | Client de recherche Nexus (GraphQL v2) |
| **A3-T3** | — | Trouver les traductions françaises des mods installés |
| **A3-T4** | 2026-08-25 | Trouver les suppléments d'un mod installé |
| **A3-T6** | 2026-08-29 | Déclarer une traduction que l'app n'a pas posée |
| **A5-T1** | 2026-08-29 | Lire les conflits que Content Patcher journalise |
| **A5-T2** | 2026-08-30 | Signaler soi-même une incompatibilité, ou en écarter une |
| **A5-T3** | 2026-08-29 | Le paragraphe de compatibilité de l'auteur, sur la fiche |

**Découverte de nouveaux mods — Axe G · livré en v1.25.0**

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **G-T1** | 2026-08-25 | Spike de validation API : mods triés (endossements, mise à jour, création), filtre par tag French, champ endossements… |
| **G-T2** | — | Onglet « Découvrir » : trois sections (une requête chacune, cache 24 h, rafraîchissement manuel seul), recherche par… |
| **G-T3** | — | Install direct depuis la fiche : pipeline des mises à jour appliqué à un mod non installé. API réservée Premium — 403… |

**Cohérence UI : un seul langage pour toute l'app — Axe H · ✅ clos le 2026-09-09** *(12 livrés, 1 abandonné)*

| Item | Livré | Ce qui était en cause |
|---|---|---|
| **H-T1** | — | Châssis |
| **H-T2** | — | Navigation |
| **H-T3** | — | Accueil tableau de bord |
| **H-T4** | — | Mods, pilote du reskin |
| **H-T5** | 2026-08-31 | Lot Parties |
| **H-T5b** | 2026-08-31 | Hero de sauvegarde illustré |
| **H-T5d** | 2026-09-02 | Lecture d'une sauvegarde : la queue au lieu du fichier entier |
| **H-T6** | 2026-09-02 | Lot Santé & secours |
| **H-T7** | 2026-09-09 | Lots Journaux & Réglages, deux releases : `LogsView` 26 tailles littérales → 0, `SettingsView` 53 → 0 ; tokens monospace ; onze sections rangées en quatre groupes par un type Core sous test ; état vide qui dit s'il est filtré ; quatre infobulles de toolbar rendues atteignables (cible ~13 pt → 18×18, elles ne sortaient jamais) |
| **H-T8** | 2026-09-09 | Hub de traduction, reskin de continuité : 74 littérales → 0 sur cinq vues, deux tokens monospace de plus (10 et 9 pt). Le reste du lot est un **constat** — accessibilité et états vides étaient déjà tenus, six faux positifs sur six ; aucun correctif inventé. `ThaiTranslationHubView` écarté : `C5-T1` doit le refondre |
| **H-T5e** | 2026-09-09 | Vignette illustrée d'une ferme de mod : image de l'auteur recadrée sur mesure (profil de luminance pour situer cartouche et bordure) au format exact des sept autres ; le SF Symbol reste le filet |
| **H-T5c** | 2026-09-09 | ⛔️ **Abandonné** (décision de l'auteur, §8.3). Son prérequis était faux — les calques du fermier existent dans le `Content` du jeu installé — mais un lecteur de `Texture2D` est une capacité neuve, que §9 exclut de l'axe H |
| **H-T9** | 2026-09-09 | Closage : audit de fidélité de Découvrir à **zéro écart** (29 valeurs de style identiques v1.25.0 ↔ aujourd'hui, tokens résolus ; 21 « écarts » initiaux tous faux, dus à un périmètre trop étroit), artboard `Screens` ajouté à `/design`, trois images mortes retirées du bundle |
