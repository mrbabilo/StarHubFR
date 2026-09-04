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
- **Axe H — Cohérence UI** *(transverse)* : généraliser à toute l'app le langage
  visuel établi par l'onglet Découvrir (axe G) — navigation regroupée, accueil
  tableau de bord, reskin écran par écran, bibliothèque de composants vivante.
- **Axe I — Expérience utilisateur** *(après H)* : navigation optimisée et
  accessibilité en **capacités** — clavier, palette de commandes, VoiceOver.

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
- [ ] **X47** — **Le `break` du premier lot en échec coûte les lots suivants.** Un
      503 ponctuel sur le lot 3 de 8 renonce aux lots 4 à 8, que rien n'incriminait :
      795 mods repartent en reprise Nexus (quota payant) là où un simple passage au
      lot suivant les aurait couverts gratuitement. Le fichier assume ce choix (« ne
      pas cogner une API publique gratuite »), et il protège d'une rafale d'erreurs.
      Redessiner la politique — continuer, ou réessayer le lot une fois avec un
      retrait — est une décision de conception, pas un correctif d'audit. X46 rend
      au moins le fait visible et réessayable. · **S**
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
- [ ] **X54** — **Le journal annonce « profil créé » sur un simple ajout.**
      `L10n.VM.profileCreated` (« Profil « %@ » créé (%lld mods) ») est journalisé
      en quatre endroits : `createProfile` (juste), `duplicateProfile`
      (acceptable), mais aussi `addModToProfile` et `importFavorites`, qui ne
      créent rien. Demande deux clés L10n neuves, en parité `en`/`fr`. Non corrigé
      dans la passe d'audit pour ne pas mêler un ajout de clés à des correctifs de
      perte de données. · **S**
- [ ] **X58** — **`warnings` mérite un filtre de plateforme, pas un rejet.**
      Le champ existe sur 24 entrées du dump, et **17 parlent d'Android** —
      « Broken on Android », « Only works on Android » : du bruit pur sur
      macOS, et les deux exemplaires du parc en font partie (le second dit
      « use Nexus, ModDrop is NOT updated », ce qu'on fait déjà). Les remonter
      tels quels ferait **contredire la source primaire** : smapi.io déclare
      `Ok` ces deux mods-là. Mais les six autres valent la lecture — télémétrie
      non divulguée et non annoncée sur la page du mod, plantages au chargement
      d'une sauvegarde, archive à la structure fausse qu'il faut dézipper deux
      fois, incompatibilité multijoueur. Ce qui manque n'est pas le champ,
      c'est la règle qui écarte ce qui ne concerne pas la plateforme — et un
      endroit où le dire qui ne soit pas le verdict de compatibilité, puisque
      ces mods ne sont pas cassés. Zéro exemplaire utile sur le parc
      aujourd'hui : à faire quand l'écran d'alertes gagnera une ligne
      « à savoir ». · **S**
- [ ] **X59** — **Changer de profil jette la liste de ses échecs.**
      `applyProfileToFilesystem` capture chaque déplacement raté dans un
      `MoveFailure` — son propre commentaire dit que l'ancienne version « avalait
      toute erreur de système de fichiers […] sans signal pour l'utilisateur », et
      que celle-ci les capture. Elle les capture bien, et les journalise une par
      une. Mais sur **quatre appels, un seul** les consomme (la restauration de
      bissection, L. 8713) : l'adoption des bascules manuelles (L. 8616, 8920) ne
      passe pas de complétion, et **le changement de profil (L. 8938) reçoit les
      échecs sous `_`**. C'est l'action la plus courante des trois. Un mod resté du
      mauvais côté après un changement de profil n'est donc annoncé nulle part où
      l'utilisateur regarde — il faut ouvrir les journaux pour l'apprendre.
      Aucune donnée n'est détruite (`moveItem` échoue si la destination existe, il
      n'écrase pas), mais l'état affiché ne correspond plus au disque.
      Constaté le 2026-09-04 en vérifiant **R2**. · **S**

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

### Hub de traduction FR, phase 1 : *diagnostic* — **Axe C** · livrée en **v1.13.0**, sauf **C2-T4**

Objectif : tenir la promesse du dépôt (« traduction en français ») **en lecture seule**,
sans risque d'écriture destructive.

#### C1 — Couverture de traduction par mod

> ✅ **Les 8 items de ce lot sont livrés.** Leur récit et leurs mesures vivent dans [`roadmap-archive.md`](roadmap-archive.md) ; l'index du §11 dit lesquels.


#### C2 — Vue diff EN/FR

- [ ] **C2-T4** — Après mise à jour d'un mod, signaler les clés de config **et** de
      traduction ajoutées ou disparues (s'appuie sur les références par clé adoptées
      en C2-T2 — l'empreinte prévue n'a pas été retenue, cf. C2-T2). · **M**

**Risques** : formats i18n hétérogènes (tous les mods n'ont pas de `default.json`) ; gros
mods (SVE ≈ milliers de clés) → calcul hors du thread principal.
**Critère de succès** : savoir en un coup d'œil quels mods installés sont traduits,
partiellement traduits ou pas du tout, sans ouvrir un seul fichier.

---

### Hub de traduction FR, phase 2 : *édition & assistance* — **Axe C** · livrée par morceaux (**v1.15.0** → **v1.17.0**), **8 items ouverts**

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
      ▸ **Confirmé par l'audit du 2026-09-04** (décompilation —
      [`audit-mods-config-perf.md`](audit-mods-config-perf.md)) : les deux patterns
      cohabitent. UltraSmooth suit `camelCase(champ)` à 100 % (115 clés, toutes
      retombées) ; SLO choisit librement (`config.fast-warp.name` pour un champ nommé
      `EnableFastWarpTransitions`). Le rapprochement par tige reste la bonne règle,
      avec repli assumé sur la clé brute. Piste pour élargir le plafond : **les bornes
      vivent parfois en prose dans l'infobulle** (« Clamped 256–4096 KB »,
      UltraSmooth) — la seule trace sur disque des min/max des mods C#.
- [ ] **C4-T8** — **Prévisualiser la normalisation en lisant ce que le mod a fait,
      pas en devinant ses bornes.** SLO journalise sa configuration normalisée
      **entière** au démarrage, sous `[OPTIMIZER CONFIG]` (relevé dans le journal SMAPI
      réel de l'auteur) — et l'app sait déjà lire ce journal en profondeur. Comparer la
      valeur du `config.json` à celle que le mod a annoncée au dernier lancement dirait
      « le mod a ramené 8192 à 4096 » sans coder une seule borne, et sans périmer à la
      version suivante. À instruire : combien de mods du parc journalisent leur config,
      et sous quelle forme. · **M**
- [ ] **C4-T7** — `audit-mods-config-perf.md` — **Les angles morts keybind de C4-T2.**
      Chevauchements sous-ensemble (A = `K`, B = `K`+Shift co-déclenchent sur le geste
      long — spec §12), composants de pack, mods en pause ; et donner aux collisions
      **manette** leur catégorie visible — cas réel mesuré le 2026-09-04 : `LeftStick`
      partagé par deux frameworks ValleyBonds. · **M**

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

### Cohérence UI : un seul langage pour toute l'app — **Axe H** · **5 items ouverts sur 13**

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

### 8.0 Priorité courante — **le risque de perte de données** (2026-09-04)

Les 73 items ouverts ont été confrontés au code le 2026-09-04, un par un : pas
lus, **vérifiés** — la condition que chacun affirme, cherchée là où il dit
qu'elle est. Résultat de la passe : **une case fausse** (`F1-T1`, terminé le
2026-08-01, son propre corps l'écrivait), **un doublon d'une tâche livrée**
(`R4` = `B3-T5`), **un constat neuf** (`X59`, trouvé en vérifiant `R2`) ; tous
les autres constats sont **encore vrais aujourd'hui**.

L'ordre ci-dessous répond à une question précise — *qu'est-ce qui peut détruire,
corrompre ou faire disparaître quelque chose sans le dire ?* — et non à
« qu'est-ce qui a le plus de valeur ». Les deux ne donnent pas le même ordre.

**P1 — peut faire perdre quelque chose**

| Rang | Item | Ce qui se perd | Ce que la vérification a établi |
|---|---|---|---|
| ~~1~~ | ~~**X55**~~ | ✅ **Corrigé le 2026-09-04** — politique « on efface tout » tranchée par l'auteur. 35 entrées fantômes mesurées dans les préférences réelles au moment du correctif ; les anciennes restent, les balayer heurterait X25. Voir l'archive |
| ~~2~~ | ~~**X25**~~ | ✅ **Livré le 2026-09-04** — l'écran « Entretien » : inventaire mesuré (1,80 Go de sauvegardes, 340 dossiers orphelins, 35 clés mortes, 1 seule copie protégée), purge par cran sous confirmation, nettoyage explicite des orphelins et clés — jamais de passe automatique. Voir l'archive |
| 3 | **R6** | Rien encore — c'est le filet qui manque | Aucun test d'idempotence sur `applyProfileToFilesystem` (vérifié : aucun `Tests/` ne contient le mot). Caractériser un double-apply **avant** de toucher au code, comme le dit l'item |
| 4 | **R2** | Un état partiel, pas des octets | `moveItem` **échoue** si la destination existe — il n'écrase pas — et chaque échec est journalisé. Reste vrai : aucune garde « jeu en cours », aucun instantané au niveau profil, des renommages en série interruptibles |

**P2 — masque une information, ou en affirme une fausse**

| Rang | Item | Ce qui est caché ou faux |
|---|---|---|
| 5 | **X59** | Un mod resté du mauvais côté après un changement de profil : l'échec est journalisé, jamais annoncé là où l'utilisateur agit (3 appels sur 4 jettent la liste) |
| 6 | **X31** | La version de SMAPI installée, si elle a été posée hors de l'app — l'app propose alors éternellement une mise à jour déjà faite |
| 7 | **X54** | Le journal annonce « profil créé » sur un simple ajout de mod et sur un import de favoris |
| 8 | **X49** | Deux recherches Nexus rapprochées peuvent revenir dans le désordre |
| 9 | **F6-T4** | Une ancre « je l'ai déjà » ratée quand le manifeste et l'ancre diffèrent par la casse |
| 10 | **X58**, **C2-T4**, **X47** | Ce qu'un mod garde en silence (avertissements filtrés par plateforme), les clés de config perdues à une mise à jour, les lots smapi.io abandonnés après un échec |

**P3 — latent : la condition est vraie, zéro exemplaire sur le parc**

`X28` (`__MACOSX` niché), `X29` (détection de doublons sans appelant),
`X32` (drapeaux de l'installateur SMAPI), `X43` (dialogue de conflit mort —
code mort, rien de cassé), `X45` (dix dépliages manuels, aucun divergent),
`F4` (`uniqueId: ""` sur les groupes — chaîne d'exploitation coupée),
`F6-T1` (course à l'annulation, sans observable), `F6-T3` (deux parseurs du
même journal). Vérifiés un par un : tous encore exacts, aucun ne se manifeste.
À traiter quand on passe à côté, pas pour eux-mêmes.

**P4 — chantiers et fonctionnalités** *(rien à perdre, tout à construire)*

Par lot, dans l'ordre de ce que l'axe « perte de données » recommande de faire
ensuite : **F2** (audit sécurité et perf — c'est lui qui trouverait les X à
venir), **F5** (identité de bundle partagée avec l'amont : 31 clés de
préférences et le Trousseau en commun), puis **C4** (T1/T7/T8, éditeur de
config), **H** (5 lots restants), **A** (A1-T1/T2, A2-T5, A5-T4/T5), **D1/D2**
(Profiler et télémétrie), **C3/C5/C6**, **I** (accessibilité, après H),
**E1–E3** et **D3** (horizon, sous décision produit).

**Non classés ici parce qu'ils attendent une décision, pas un développement** :
`X47` (politique de reprise smapi.io), `X55` (politique de purge), `D3-T1`
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

**Hub de traduction FR, phase 1 : diagnostic — Axe C · livrée en v1.13.0, sauf C2-T4**

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

**Cohérence UI : un seul langage pour toute l'app — Axe H · à faire**

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
