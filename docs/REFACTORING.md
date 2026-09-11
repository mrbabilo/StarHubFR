# StarHubFR — Plan de refactorisation

> **Statut** : document de travail, versionné (contrairement à `docs/superpowers/`,
> qui est gitignoré). Transposition à nos contraintes du refactor mené en amont par
> `AppleBoiy/StarHubTH` (phases 0-9, achevé le 2026-07-25, donc **postérieur à notre
> fork**). Rattaché à l'**axe F** de `ROADMAP.md`.

## 1. Le problème

`StarHubTHViewModel.swift` concentre profils, scan, Nexus, journal, configurations,
sauvegardes et bissection. Il est passé de 4390 à 4153 lignes le 2026-08-01, ce qui
ne change pas sa nature : c'est un module fourre-tout dont **aucune ligne n'est
testable**.

⚠️ **Mesure du 2026-09-10 : 11 902 lignes**, ramenées à **11 498** par les points 1 à 3 et la première tranche du point 4. La série, relevée par `git rev-list` sur
les commits de fin de journée — chaque chiffre est le fichier tel qu'il était, pas une
reconstitution :

| Date | Lignes | Écart |
| --- | --- | --- |
| 2026-07-30 | 4 296 | relevé initial |
| 2026-08-11 | 4 394 | +98 en 12 jours |
| 2026-08-28 | 8 389 | **+3 995 en 17 jours** — le chiffre resté écrit ici jusqu'au 2026-09-10 |
| 2026-09-04 | 10 192 | +1 803 en 7 jours |
| 2026-09-10 | **11 902** | +1 710 en 6 jours |

*Le « 4278 » consigné jusqu'ici pour le 2026-07-30 n'était pas faux : c'est le fichier
à `feat(diagnostics): persist per-version error history`, en milieu de journée. Le
tableau prend la fin de journée pour toutes les dates, d'où 4 296. Écart de 18 lignes,
sans portée — mais deux conventions de relevé qui se croisent produisent des séries
incomparables, alors celle-ci est fixée.*

**+177 % en 41 jours**, dont **+3 513 lignes après** que ce document eut constaté le
problème et posé la règle censée l'empêcher. Le rythme de la dernière semaine est de
~285 lignes/jour. Le VM pèse **11 902 des 71 956 lignes Swift** du dépôt : un sixième
de l'application dans un fichier.

Le gain de 237 lignes d'août 2026 a été effacé et quadruplé. Chaque axe livré depuis
(traduction, profils, découverte, entretien, corbeille, clavier) y a déposé sa part, ce
que **F1-T2** était censé empêcher. Deux constats à en tirer, plus utiles que le
chiffre :

- **F1-T2 comme règle écrite ne fonctionne pas.** Elle est posée depuis le 2026-08-01 et
  a été violée par tous les axes livrés depuis, sans exception. Une règle que six
  chantiers consécutifs ignorent n'est pas une règle : c'est un vœu. Le dépôt a déjà
  la réponse à cette classe d'échec — le cliquet (`check_standards.py`), qui échoue à
  l'augmentation d'un compteur et exige un `--update` visible dans le diff. Y inscrire
  le nombre de lignes du ViewModel est le seul mécanisme qui rende F1-T2 opposable.
- **Le dossier `Stores/`, tranché le 2026-08-01 (§9), n'a jamais été créé.** La décision
  est prise, elle n'attend rien ; elle n'a simplement jamais eu de première occupation.

Le coût est déjà constaté, pas théorique : le 2026-07-31 a produit trois listes de
chemins d'outils divergentes et quatre nettoyeurs de manifeste incompatibles, faute
d'un endroit unique où chaque chose vit.

## 2. La contrainte qui décide de tout

**Ce qui est testable ici, c'est ce qui est inscrit aux `sources:` de `StarHubTHCore`
dans `Package.swift` et n'importe pas SwiftUI.** Rien d'autre. `swift test` ne voit
que ce module ; le ViewModel et les vues n'ont pour filet que la compilation
(`python3 build_app.py`).

Deux sondes ont été passées le 2026-08-01 pour savoir jusqu'où ce module peut aller :

| Sonde | Résultat | Conséquence |
| --- | --- | --- |
| `@MainActor final class … : ObservableObject` dans Core | **compile et se teste** | Un store extrait devient testable — l'extraction n'est pas qu'un rangement |
| `NexusUpdateChecker.swift` (894 lignes, `Foundation` + `Security`) ajouté aux sources | **compile sans modification** | Un fichier sans dépendance SwiftUI rejoint Core par simple déclaration |

**Corollaire méthodologique** : avant d'extraire quoi que ce soit, vérifier si le
fichier n'importe que `Foundation`. Si oui, l'ajouter aux sources coûte une ligne et
rend tout son contenu testable — inutile de déplacer du code.

## 3. Ce qu'on retient de l'upstream, et ce qu'on écarte

**Retenu** — leur découpage en couches, où chaque dossier correspond à une couche,
de sorte qu'une violation se voit dans le chemin du fichier :

```
Models/ (Foundation seul)  →  Services/ (I/O, protocole + implémentation)  →  Stores  →  Vues
```

Retenu aussi : leur ordre d'extraction (le moins enchevêtré d'abord), leur recette
par domaine, et leur exigence d'**un commit par étape numérotée**, pour qu'un
`git bisect` reste trivial.

**Et surtout leur mécanisme de testabilité, qui n'a pas encore d'équivalent ici** :
un protocole par frontière d'I/O (`ModScanning`, `SaveStoring`, `PreferenceStoring`,
`FilePicking`…), une implémentation `Live`, et un **bouchon par protocole** dans
`Tests/Stubs/`. C'est ce qui leur permet de tester un store qui lit le disque ou le
réseau — sans quoi « extraire un store » ne fait que déplacer du code intestable.

Ce mécanisme n'était **pas encore nécessaire** tant que les trois extractions faites
portaient sur de la logique **pure** (parseurs, comparaison), qui se teste sans
bouchon. ⚠️ **Il l'est devenu le 2026-09-10** : le point 1 du §5 est le registre des
mods installés, qui lit et écrit `UserDefaults`. Introduire le protocole **avec** son
bouchon dans le même commit, et non « plus tard », faute de quoi le store arrivera
dans Core sans un seul test possible.

### 3 bis. Ce que leur code livré donne — relevé du 2026-09-10

Les §3, §8 et §9 n'avaient examiné que leur **plan** et leurs **correctifs**. Leur
code résultant n'avait jamais été lu. Il l'a été via le remote `upstream` (pas de
clone : `git show upstream/main:<chemin>`).

**D'abord, leur refactor a abouti** — ce n'est pas une opinion : plus aucun
ViewModel dans l'arbre, plus gros fichier **392 lignes**, 16 301 lignes réparties sur
166 fichiers, `Tests/Stubs/` peuplé de 9 bouchons. Le doute raisonnable (« ils ont
peut-être juste déplacé le fourre-tout ») est levé. Leur application est plus petite
que la nôtre en fonctionnalités, mais la forme, elle, tient.

**Quatre choses à reprendre, et pourquoi :**

| Quoi | Pourquoi maintenant |
| --- | --- |
| ~~**`PreferenceStoring` + `PreferenceStore` + `StubPreferenceStoring`**~~ ❌ **écarté le 2026-09-10, à l'extraction même qui devait l'inaugurer** | Le relevé fait au moment d'écrire le store a retourné l'argument. **Ce dépôt a déjà sa frontière de préférences, et elle est plus simple** : `UserDefaults` entre par l'initialiseur — `ModVersionAnchorStore.init(defaults:)`, dont le commentaire l'érige en convention (« la dépendance à l'environnement entre par l'initialiseur, pas par un singleton »), `ModUpdateSnoozer`, `DefaultsMigration` — et trois suites l'exercent déjà en `UserDefaults(suiteName:)`. Le protocole n'ajouterait rien qu'un passe-plat de 10 méthodes, **et une seconde façon d'injecter les préférences dans Core** : exactement la divergence dont le dépôt sait le coût. Le défaut qu'il fallait corriger en le reprenant (`set([String], forKey:)` sans getter) **n'existe pas** avec `UserDefaults`, où `stringArray(forKey:)` est natif : l'argument qui justifiait le port se retourne contre lui. `InstalledModRegistryStore` prend donc `defaults: UserDefaults = .standard`. |
| **`AppCoordinator`** — ce qui remplace le ViewModel | Il **ne publie rien** — vérifié sur les déclarations, pas sur sa prose : zéro `@Published`, seulement **10 références** (7 stores, plus `AppEnvironment`, `AlertStore`, `ToastStore` ; leur commentaire en annonce 8), et `ObservableObject` uniquement pour être injectable en `@EnvironmentObject`. L'argument porté par le code : ne rien posséder, c'est ne jamais pouvoir dériver de ce qu'on coordonne. **Cela répond à la question ouverte de notre §6 (« Cible »)**, où l'on écartait la suppression du ViewModel faute de filet : on n'a pas à le supprimer, il faut le **vider de son état publié**. La cible fonctionnelle qu'on s'était donnée trouve ici sa forme concrète. |
| **Le patron « ce qui n'est pas à moi arrive en paramètre »** | Leur en-tête de `ModsStore` : `gameDir`, `chainToggleDependencies`, `showModal`, `log`, `refresh` « ne sont pas possédés ici » et sont passés en paramètres ou en closures. C'est la réponse aux deux blocages du §5 — les sorties `log(…)`/alerte du registre, et les cinq dépendances croisées des prédicats de liste. Ce n'est pas une astuce : c'est la même règle que notre critère d'entrée. |
| ~~**`check_file_length` (> 400 lignes)**~~ ✅ **repris le 2026-09-10** | **C'était la seule de leurs six règles que nous n'avions pas** (les cinq autres — `get`, classes non `final`, `.shared`, `DispatchQueue`, `@Published` sans `private(set)` — étaient déjà couvertes), et précisément celle qui aurait crié pendant les 41 jours où le God module a triplé. Voir ci-dessous : reprise **avec un écart**, la leur n'aurait rien attrapé. |

**L'écart sur la règle de taille, et pourquoi il fallait le faire** — leur
`check_file_length` compte les **fichiers** en dépassement. Transposé tel quel chez
nous, ce compteur serait resté figé à 37 pendant que le ViewModel passait de 4 296 à
11 902 lignes : un fichier trop gros qui grossit ne change pas de catégorie. **Le
cliquet n'aurait jamais rougi sur le défaut même qu'on cherche à empêcher.** D'où deux
compteurs plutôt qu'un :

| Compteur | Base au 2026-09-10 | Ce qu'il interdit |
| --- | ---: | --- |
| `oversized_files` | 37 | Ouvrir un **nouveau** fourre-tout |
| `oversized_excess_lines` (somme des dépassements) | 27 414 | **Engraisser** ceux qui existent — et il tombe dès qu'un fichier repasse sous le seuil, donc il récompense le découpage |

Seul compteur du script à se mesurer sur les lignes **brutes**, commentaires compris :
les autres cherchent des violations, et écrire *sur* une violation n'en est pas une ;
celui-ci demande si le fichier est maniable, et 3 000 lignes de commentaires se
scrollent et saturent le type-checker comme 3 000 lignes de code. C'est aussi ce que
rend `wc -l`, donc ce qu'on vérifie à la main sans se demander quelle convention
s'applique.

**Un défaut du script trouvé en l'étendant, et corrigé** : l'empreinte de fraîcheur qui
évite de re-balayer 260 fichiers ne couvrait que les **sources**, pas le jeu de règles.
Ajouter une règle sans toucher au Swift rendait donc un relevé d'où elle était absente —
et `main()` n'itérant que sur les clés reçues, elle n'était **ni vérifiée ni signalée
comme inconnue** : sautée en silence, sur le chemin exact qu'emprunte `build_app.py`.
Le contrefactuel a été mesuré, pas déduit : avec une base truquée à 36 pour 37 réels et
un cache privé des deux clés, l'ancien code sort **0**, le nouveau **1**.

**Leur échappatoire mérite d'être reprise à côté de la nôtre, pas à sa place.** Ils
autorisent le silence par un commentaire `// STANDARDS-EXCEPTION: <règle> — <raison>`
**sur la ligne signalée**, vérifié par constat et non par catégorie. Notre cliquet, lui,
compte et exige un `--update` visible dans le diff. Les deux ne font pas le même
travail : le nôtre empêche la dérive globale, le leur oblige à **écrire la raison à
l'endroit exact**. Pour les **70 `@Published` sans `private(set)`**, c'est le second
qu'il faut : le §6 demande de classer chaque propriété (domaine → store, présentation →
`@State` de la vue), et une annotation par site *est* ce classement, sous une forme que
le script peut compter.

**Un piège Swift qu'ils ont documenté et qu'on rencontrera au premier gros store** :
`private` et `private(set)` sont de portée **fichier**, pas type. Découper un store en
extensions (`ModsStore+Toggle.swift`…) force donc à élargir la visibilité des
propriétés que les méthodes déplacées écrivent encore. Leur contournement est
l'annotation d'exception ; le savoir avant évite de croire à une régression.

**Ce qu'on n'importe pas, et pourquoi :**

- **Leur mode de sortie.** Leur `check_standards.py` est un scan pleine base
  *warnings-only* (`exit 0`) sauf `--strict`. Le nôtre est un vrai cliquet contre
  baseline. Ne pas régresser vers le leur : un contrôle qui sort 0 sur un échec est
  exactement le défaut que le §8 leur reproche par ailleurs.
- **La sûreté du registre ne vient pas de la frontière d'I/O.** Qu'on injecte un
  protocole ou `UserDefaults`, on n'obtient qu'un passe-plat : nos trois mécanismes
  (sauvegarde avant écriture, restauration sur corruption, reconstruction depuis le
  disque) vivent **au-dessus**, dans le store. C'est le bon découpage — mais il serait
  facile de croire que l'injection les apporte. Ce sont des **tests** qui les tiennent,
  et ils n'en avaient aucun jusqu'au 2026-09-10.
- **Leur prose a dérivé comme la nôtre.** L'en-tête de `ModsStore` renvoie à un
  ViewModel qui n'existe plus, et leur §8 parle de « 43 `@Published` » d'un état
  révolu. Lire leur **code**, jamais leurs commentaires, pour établir un fait.

**Leurs coordonnées ne sont pas transposables.** Leur ViewModel faisait 2102 lignes,
le nôtre en faisait 4378 au moment de l'audit : tous les numéros de ligne de leur
plan (`4.1 LocalizationStore 380–413`…) sont inutilisables. Ce qui vaut, c'est
l'**ordre** et les **dépendances entre domaines**, pas les emplacements.

**Écarté**, parce que dépendant d'une chaîne de build que nous n'avons pas : XcodeGen
(`project.yml`), les tests `XCUIApplication`, la capture d'écran automatisée, et leur
lanceur de tests maison (nous utilisons swift-testing via SwiftPM).

**Leurs correctifs pendant le refactor valent plus que leur plan.** C'est en les
lisant qu'on a trouvé le bloc de mises à jour SMAPI jamais détecté — bug réel,
présent à l'identique ici, corrigé le 2026-08-01 (`54113eb`).

Deux autres de leurs défauts ont été cherchés chez nous, avec des résultats
opposés — les noter évite de refaire la recherche :

| Leur défaut | Chez nous |
| --- | --- |
| Groupes construits avec `uniqueId: ""` (leur 2.4) : une dépendance à identifiant vide peut se résoudre sur un groupe et passer pour satisfaite | **Présent dans le code** (`StarHubTHViewModel.swift:1207`), mais la chaîne d'exploitation semble coupée : `rebuildDependencyIndexes()` n'indexe que les enfants, jamais le groupe. Ouvert en **F4**, à instruire avant de conclure |
| `customModTags` relu depuis `UserDefaults` à chaque lecture — un décodage de plist par ligne et par redessin (leur 3.5) | **N'existe pas ici.** Cherché explicitement : aucune occurrence. Ce n'est donc **pas** l'explication de la latence de frappe (**F3**), et la piste « rendu » reste non confirmée |

## 4. Méthode

Une extraction se fait dans cet ordre, et chaque étape est un commit :

1. **Chercher la logique pure d'abord.** Un parseur, un calcul, une classification
   enfouis dans le ViewModel ou une vue. C'est là qu'est la valeur : ce code décide
   de ce que voit l'utilisateur, et personne ne le vérifie.
2. **Écrire les tests avant l'extraction**, sur le comportement existant. Un test qui
   n'a jamais été rouge ne prouve rien — le vérifier en cassant volontairement le
   code (fait pour le bloc des mises à jour).
3. **Déplacer sans modifier — sauf à améliorer, et alors le consigner.**
   Swift n'ayant pas d'imports par fichier, un déplacement pur ne peut pas changer
   le comportement : si le build casse, ce n'était pas un déplacement pur.
   **Corriger au passage est autorisé** quand cela répare ou améliore réellement
   le code (arbitrage de l'auteur, 2026-08-01) — à la condition stricte que la
   déviation soit **écrite** : dans la documentation du code *et* au tableau
   ci-dessous. Une amélioration tacite est indiscernable d'une régression
   introduite par mégarde.
4. **Traiter les violations de couche qui bloquent.** Un modèle qui prend le
   ViewModel en paramètre, ou qui porte un `Color`, ne peut pas entrer dans Core.
   Le remplacer par une **clé** ou un **état**, que la vue rend.
5. **Vérifier des deux côtés** : `./run_tests.sh` *et* `python3 build_app.py`.
   Aucun agent ne lance l'application — la vérification visuelle revient à l'auteur.
6. **Poser un repère avant de commencer un domaine.** Un tag
   `pre-refactor-<domaine>` sur le commit de départ : c'est ce qui rend un `git diff`
   de fin d'extraction lisible, et une marche arrière possible sans reconstituer
   l'historique. Repris de leur 0.1. ⚠️ *« Jamais fait ici jusqu'à présent » était
   faux* : `git tag -l 'pre-refactor*'` en rend **huit**, dont sept posés le
   2026-08-01 — et `pre-refactor-installed-registry` était déjà pris par l'extraction
   de la règle pure. Vérifier avant de nommer ; le repère du store est
   `pre-refactor-registry-store` (`eed26dc`).
7. **Se méfier de l'outillage autant que du code.** Un « build vert » ne vaut que si
   le script échoue vraiment quand il doit échouer. Épreuve passée le 2026-08-01 (les
   deux sortent en 1 : parité de clés rompue, assertion fausse) — **à refaire après
   toute modification de `build_app.py`, `run_tests.sh` ou `release.py`**. C'est là
   qu'étaient les bugs les plus coûteux de l'upstream : voir §8.

## 5. État

### Livré le 2026-08-01

| # | Domaine | Résultat |
| --- | --- | --- |
| 1 | **Journal SMAPI** | `LogEntry` sort du ViewModel (sa présentation `Color` l'en excluait) ; `SmapiLogParser` + le bloc des mises à jour passent en Core avec 13 tests. **Un bug réel corrigé** : les mises à jour signalées par SMAPI n'étaient jamais détectées. |
| 2 | **Catalogue des traductions** | `ThaiTranslationTable` en Core avec 11 tests ; `ThaiTranslationMod` perd ses deux méthodes prenant le ViewModel (une était morte). |
| — | **Comparaison de versions** | `NexusUpdateChecker` rejoint Core sans modification ; 11 tests sur `compare(_:_:)`. Aucun défaut, mais un comportement contraire à l'usage Stardew consigné en A2-T2. |

**F1-T1 est clos.** ViewModel : 4390 → 4153 lignes. 35 tests neufs sur du code qui
n'en avait aucun.

### Prochaines extractions — ordre re-dérivé le 2026-09-10

> ⚠️ **L'ordre précédent est périmé et a été retiré.** Il avait été écrit contre un
> ViewModel de 4 153 lignes : ses quatre premiers points totalisaient ~841 lignes, soit
> **7 % du fichier d'aujourd'hui**. Son point 1 (`consolidateUpdatesByPack` +
> `pickHighestVersion`, ~78 l.) reste juste mais coûterait plusieurs jours pour 0,7 %.
> Le tableau ci-dessous le remplace intégralement.

> 🚩 **Ne jamais découper d'après les `// MARK:`.** Elles mentent, et le vérifier a
> failli fausser cette révision même. Classer les 38 sections par taille désigne
> « Couverture française d'un profil (B3-T4) » comme la plus grosse, à 1 493 lignes ;
> en lisant les bornes, cette section contient ~180 lignes de couverture FR, **puis
> tout le bloc de tête du §6** — `detectDefaultGameDir`, `selectGameDir`, `L(_:)`,
> `cachedBundle`, `fetchSteamUser`, `checkSmapiVersion`, `scanMods`, `parseModFolder`,
> `performInitialLoad` — jusqu'à la ligne 3196, sous une étiquette qui parle d'autre
> chose. Le God module n'a pas rétréci : une `MARK` s'est insérée au-dessus de lui et
> l'a enfoui. **Tout relevé se fait sur les déclarations, pas sur les étiquettes.**

**Relevé du 2026-09-10** — 34 blocs contigus, bornes lues sur les déclarations de
membres. La somme fait exactement 11 902 : la partition est exhaustive, aucun bloc
n'est oublié.

| Lignes | Bornes | Bloc |
| ---: | --- | --- |
| 1 284 | 1913–3196 | **Tête n°2** — état divers, Environnement, Localisation, Steam, `performInitialLoad`, `scanMods`/`parseModFolder` |
| 916 | 4393–5308 | Nexus — vérification des mises à jour, smapi.io, repli Pathoschild, apprentissage d'ids |
| 906 | 798–1703 | Pré-traduction assistée, lot, glossaire, `saveTranslation`, export/import de lot |
| 852 | 6481–7332 | Traductions communautaires (A3-T3) — recherche, dépôt, addons, suppléments |
| 630 | 10743–11372 | Cadrage de la liste (prédicats), `toggleAllMods`, `deleteMod`, `forgetStores` |
| 588 | 10155–10742 | R2 reprise d'application + `applyProfile` + `applyProfileToFilesystem` |
| 579 | 3562–4140 | Bascule des mods, install SMAPI, états de focus, `launchGame`, `log` |
| 574 | 1–574 | **Tête n°1** — état publié, fiche mod Nexus, phases de lancement, `mods`, `healthIssues` |
| 568 | 9296–9863 | Récupération d'un fichier isolé (B4-T4), mods manquants, favoris/blacklist et configs par profil |
| 491 | 5475–5965 | Nexus — ancrage, snooze, catégories, identifiants, liens, métadonnées |
| 487 | 5966–6452 | Nexus — archives, file de téléchargement, `nxm://`, erreurs d'installation |
| 387 | 8578–8964 | Sauvegardes — CRUD, timeline, notes, backups globaux |
| 384 | 11509–11892 | Entretien (X25) |
| 365 | 3197–3561 | Poids du parc, index de dépendances, `parseSMAPILog`, outils d'archive |
| 324 | 7333–7656 | Découverte (axe G) |
| 323 | 8255–8577 | Registre des mods installés (version + date) |
| 265 | 7951–8215 | Delta de clés de mise à jour (C2-T4) + renommage de clés |
| 252 | 4141–4392 | Journal SMAPI — lecture, historique d'erreurs par mod, diagnostics |
| 223 | 575–797 | Couverture FR d'un mod |
| 209 | 1704–1912 | Couverture FR d'un profil (B3-T4) |
| 193 | 9962–10154 | Configs par profil — capture et restauration (B3-T5) |
| 188 | 8965–9152 | Hub de traduction thaï |
| 166 | 5309–5474 | Renommer le dossier d'un mod (X60) |
| 153 | 7671–7823 | Mise à jour de l'app (release GitHub) |
| 143 | 9153–9295 | Profils — chargement, CRUD, profil par défaut |
| 136 | 11373–11508 | Corbeille des mods supprimés (X103-B) |
| 127 | 7824–7950 | Bilan d'installation, file de dépôt, navigation demandée |
| 39 | 8216–8254 | Blacklist, configs gérées, horodatages (persistance) |
| 38 | 9924–9961 | Bissection |
| 35 | 9889–9923 | Incompatibilités entre mods (A5-T2) |
| 28 | 6453–6480 | Persistance des surcharges |
| 25 | 9864–9888 | Notes de mod (B3-T6) |
| 14 | 7657–7670 | Favoris (persistance) |
| 10 | 11893–11902 | `L10nResolver` (hors classe) |

**Regroupés par domaine**, ce que le découpage en blocs ne montre pas — un domaine est
éparpillé, c'est précisément le symptôme :

| Domaine | Lignes | Blocs |
| --- | ---: | --- |
| **Traduction FR** | ~2 190 | 798–1703, 6481–7332, 575–797, 1704–1912 |
| **Nexus** (hors Découverte) | ~2 000 | 4393–5308, 5475–5965, 5966–6452, 6453–6480, + la fiche mod de la tête n°1 |
| **Bloc de tête** (Environnement, Localisation, Scan, état) | ~1 858 | 1–574, 1913–3196 |
| **Profils** | ~1 490 | 10155–10742, 9962–10154, 9153–9295, une part de 9296–9863 |
| **Liste & parc** | ~1 350 | 10743–11372, 3197–3561, 8255–8577 |
| **Sauvegardes** | ~560 | 8578–8964, une part de 9296–9863 |

**Ordre retenu.** Il ne suit pas la taille : une extraction se juge à son rapport
logique pure / enchevêtrement, pas à son volume (§4.1).

> 🔎 **Critère de choix, éprouvé le 2026-09-10 : ce sont les *entrées* qui décident,
> pas la taille ni la pureté apparente.** Une cible est extractible quand ce dont elle
> a besoin lui arrive **en valeurs** ; elle ne l'est pas quand elle va le chercher sur
> `self`, même si son corps est du calcul pur. C'est ce contrôle qui a fait inverser
> les deux premiers points ci-dessous — le faire avant d'écrire coûte un `grep`, le
> découvrir après coûte l'extraction.

| Ordre | Cible | Pourquoi |
| --- | --- | --- |
| ~~1~~ ✅ | **Registre des mods installés** — livré le 2026-09-10 | `StarHubTH/Stores/InstalledModRegistryStore.swift` (**première occupation du dossier `Stores/` tranché au §9**), inscrit aux `sources:` de `StarHubTHCore` : le store est donc testé, pas seulement déplacé. **22 tests neufs sur les trois mécanismes de sûreté que rien ne vérifiait** — copie de secours à chaque écriture, restauration depuis le secours (avec promotion en clé principale), purge des blobs corrompus — plus la migration v2, la grâce et le `Mods/` illisible. Les sept ont été **prouvés rouges** par sabotage (§4.2). ViewModel : **11 902 → 11 657 lignes** (−245), `oversized_excess_lines` 27 414 → 27 169. `allInstalledMods()` **reste** au VM comme prévu (13 appelants). |
| ~~2~~ ✅ | **Prédicats de cadrage de la liste** — **clos le 2026-09-10**, en trois lots | `Models/ModListScoping.swift` : `matchesSelfOrAnyChild`, `matchesSearch`, `matchesConfig`, `matchesFavorites`, `matchesBlacklisted` — **20 tests**, dont la sur-correction (un pack favori par l'un de ses composants) et le nom **logique** d'un mod en pause, tous deux prouvés rouges. Le VM garde des **façades provisoires** (§6, condition 1) : `ModListView` appelle ces prédicats directement en six endroits, elles tomberont au découpage de la vue (P8).<br>⚠️ **Le décompte de dépendances de ce plan était faux — cinq annoncées, *neuf* mesurées le 2026-09-10** : aux `anomaly(for:)`, `category(for:)`/`inferredTagKey(for:)`, `isBlacklisted` et `frenchCoverage(for:)` s'ajoutent `isFavorite`, `outdatedKeyCount(for:)`, `modActivationTimestamps` et `sizeOnDisk(of:)`. Mais quatre d'entre elles sont des **valeurs** (`favoriteMods`, `blacklistedMods`, `staleTranslationMods` : des `Set` ; `modActivationTimestamps` : un dictionnaire) — d'où ce lot 1, qui n'a eu besoin d'aucun objet de paramètres.<br>**Lot 2 livré le 2026-09-10** : `matchesTranslation` et `inferredTagKey`. Relevé qui a évité une closure inutile — `frenchCoverage(for:)` et `outdatedKeyCount(for:)` sont eux aussi de **simples lectures de dictionnaire**, si bien que les cinq cas de couverture française passent avec des valeurs (`ModListScoping.TranslationState`), pas des closures ; `inferredTagKey` s'appuyait déjà sur `ModItem.inferTag`, en Core. 13 tests de plus, dont les quatre distinctions mesurées sur le parc : non mesuré ≠ non traduit, 1 % ≠ 0, 310 mods sans i18n hors de « à traduire », zéro clé obsolète ≠ signal.<br>**Lot 3 livré le 2026-09-10** — le point 2 est **clos** : `matchesCategory`, la composition `matches(_:filters:inputs:)`, `scoped(_:scope:hasAnomaly:)` et tout le bloc de tri. `Inputs` porte **deux closures** (`category`, `hasAnomaly`) et cinq valeurs ; les deux restent paresseuses à dessein, et un test le vérifie — sous « Tous », la closure d'anomalie n'est **jamais** appelée. 16 tests de plus (49 en tout sur le fichier). Trois déviations consignées au §6, dont le départage des ex æquo par nom. ViewModel **11 902 → 11 538** sur les trois lots, `oversized_excess_lines` 27 414 → 27 050. |
| ~~3~~ ✅ | **Couverture FR** — **clos le 2026-09-10** | ⚠️ **Pas extrait par le volume** : les ~430 lignes annoncées sont pour l'essentiel des enveloppes `Task.detached` autour de fonctions Core (`translationDiff`, `translationStaleness`, `backupTranslation`, `unloadableLocaleFiles`) — de la plomberie d'I/O sans décision dedans, que déplacer n'achète rien. Ce qui est parti dans `Models/FrenchCoveragePass.swift`, ce sont les **trois endroits qui décident** : quels mods mesurer (liste), quels mods mesurer (profils), et comment un lot entre dans l'état. **23 tests**.<br>✅ **F6-T1 est devenu observable sans être corrigé** : `merging` prend une génération, ce qui met la course dans un test — lot de la passe précédente arrivé après le recalcul suivant, écarté. Le chemin livré n'a toujours qu'une génération et le paramètre y est inerte ; la ROADMAP demande de ne pas corriger F6-T1 isolément faute d'observable, et le câblage attend la re-mesure ciblée qui lui donnera un sens.<br>🚩 **Les deux règles de sélection divergent, et c'est voulu** : la liste ne mesure que les mods livrant du français, les profils prennent aussi ceux à `default.json` sans `fr.json` — ce sont eux qui font l'intérêt de cet écran (8, 28 et 15 sur les trois profils). Les unifier ferait surgir une pastille « 0 % » dans la liste. Deux types séparés, et un test qui éprouve la divergence des deux côtés. |
| 4 | **Le bloc de tête** (1–574 + 1913–3196, ~1 858 l.) | Le God module proprement dit — décomposé au §6, dont **les coordonnées sont périmées** (voir l'encadré en tête de ce §6). **Première tranche livrée le 2026-09-10, le point reste ouvert** : la lecture d'un manifeste (`Models/ManifestFields.swift`, 9 tests) n'a plus qu'une écriture — les deux branches de `parseModFolder` et `ModManifest.init?(dict:)` en portaient chacune une copie, et elles avaient déjà divergé sur `Version`. Le lecteur rend les champs **bruts** : le repli du scan est le nom **logique du dossier**, que rien en Core ne connaît, et `ModManifest` refuse le manifeste — poser un défaut au milieu casse l'un ou l'autre.<br>Le décodage a suivi (`ManifestJSON.decodeInstalled`, 6 tests) : le scan était le seul appelant du dépôt à ne pas passer par la source consolidée X29. **Deux mesures sur les 1 108 manifestes du parc** l'ont tranché — l'expression régulière qui retirait les commentaires bloc était *inutile* (JSON5 les gère, 47 manifestes concernés, zéro écart de verdict ou de champ) et *nuisible* (elle amputait une valeur de chaîne contenant `/* … */`, défaut latent, aucun cas réel).<br>🚩 **Tranché le 2026-09-10, dans le sens de la parité de jeu.** Le constat ci-dessus tenait sur une crainte non vérifiée — « ses 7 appelants, dont des `config.json` où la sévérité du jeu est voulue ». La vérification a renversé la prémisse : **les huit** appelants de `decode` lisent tous des manifestes ou des fichiers du parc en contexte de récupération, aucun ne juge un `config.json` ; le seul juge de configuration, `ConfigJSONTree`, ne passe pas par `ManifestJSON` — la sévérité voulue vit là, hors de portée de ce type. Et l'« accepté par Newtonsoft » a été **exécuté**, pas déduit : la DLL exacte de SMAPI (`smapi-internal/Newtonsoft.Json.dll`, 13.0.0.0, pilotée par un projet dotnet de vingt lignes) accepte les quatre formes, l'hexadécimal y compris — `0x1F` y devient l'entier 31. `decode` gagne donc `.json5Allowed` : les deux portes parlent la langue du jeu, seule la sortie les distingue (`nil` vs `throw`). **Invariance mesurée sur le parc** : 1 106/1 106 manifestes décodent à l'identique avant et après, aucun n'emploie les quatre formes — la correction vaut pour les mods à venir. Le test qui épinglait la frontière (`fourJson5FormsPassWhereTheJudgingDoorRefuses`) est retourné, plus un test sur la lecture hexadécimale en entier.<br>⚠️ Ce qui **reste** du point 4 : `parseModFolder` demeure une fonction imbriquée qui va chercher `installedModDate`, `manifestCache` et `log` sur `self` — non extractible au sens du critère des entrées ci-dessus. Les conditions 1 et 2 du §6 (plus aucune fonction au VM, `@Published` classés) sont intactes. ViewModel : 11 521 → 11 498.<br>**Deuxième tranche (même jour) — Environnement, premier domaine de l'ordre du §6, extrait** : `SteamLoginUsers` (la boucle VDF), `GameDirLocator` (détection + avatar), le lecteur `SmapiVersionEvidence.installedVersion` (qui quitte `SmapiInstaller` — Foundation seul, §4.4) et le store `GameEnvironmentStore` (état publié du domaine, `private(set)`). **Naissance du premier protocole du dépôt** — `FilePicking` (Core) + `LiveFilePicker` (app) + bouchon dans le **même** commit, comme le §3 l'exigeait. 32 tests neufs, chacun prouvé rouge par sabotage (§4.2). Le VM garde quatre façades de lecture et `selectGameDir()`, **marquées provisoires** dans le code (§6 cond. 1), avec relais `objectWillChange` tant que les vues observent le VM. ViewModel : 11 498 → **11 410**, `published_without_private_set` 75 → 71 (cliquet resserré). ⚠️ Condition 4 : l'exercice manuel à l'écran (choisir un dossier, nom Steam, pastille SMAPI) reste à faire par l'auteur. |
| ~~5~~ 🔶 | **Nexus** — tranches entamées le 2026-09-11 | **Tranche 1 extraite** — `Models/SmapiVerdicts.swift` (Core, **15 tests**, chacun prouvé rouge par sabotage sur un mécanisme distinct) : l'application d'une réponse smapi.io au parc — classification (une erreur **et** une suggestion coexistent : la suggestion reste un verdict, l'erreur reste un blocage affiché), filet « sans réponse » (override manuel, puis dump Pathoschild, sinon silence — le mod UltraSmooth mesuré), fusion avec le cache plat (« absent de la réponse » n'est pas « à jour » ; purge des désinstallés ; re-confrontation de la ligne conservée à l'ancre), fusion des verdicts de compatibilité (contredit → retiré, hors parc → purgé). Tout ce que `applySmapiResults` allait chercher sur `self` lui arrive en valeurs ; le journal sort en **rapport** (`Report`), que le VM phrase aux mêmes conditions — patron `SyncReport` du store du registre. Une déviation consignée au §6 (départage du tri de `merged`). ViewModel : 10 723 → **10 558**. ⚠️ Restent au VM, chaque bloc attend sa tranche : `checkNexusUpdates` (composition réseau, patron `ModDetailRefresh`), la reprise Nexus page à page, clé/compte/quota, la file de téléchargement, les archives |
| ~~6~~ 🔶 | **Nexus, tranche 2 — la reprise** — livrée le 2026-09-11 | `Models/NexusResume.swift` (Core, **9 tests**, prouvés rouges par sabotage sur trois mécanismes) : ce qu'une page fait à l'état de la reprise (`applyPage` — page **sans version** = échec et non verdict, le quitus inventé que la reprise existe pour supprimer ; 429 = arrêt propre ; `.noApiKey`/`.error` = échec silencieux ; verdicts **nommés** mod par mod) et le bilan final (`settle` — substitution des lignes du cache par `UniqueID`, décompte honnête tente/trouvé/confirmé/échoué). Le journal sort en lignes prêtes (texte + `LogLevel`), émises telles quelles — le journal de l'app n'étant pas localisé, le texte EST la décision. La récursion réseau, la progression et le relâchement des drapeaux restent au VM. Second site de la déviation de tri (départage des ex æquo par `UniqueID`, §6). ViewModel : 10 558 → **10 491** |
| ~~7~~ 🔶 | **Nexus, tranche 3 — la composition du check** — livrée le 2026-09-11 | `Models/NexusUpdateCheck.swift` (Core, **7 tests**, prouvés rouges par sabotage sur quatre mécanismes) : le QUOI de `checkNexusUpdates`, sur le patron `ModDetailRefresh` — le filet Pathoschild part **systématiquement** en parallèle de smapi.io (pas seulement sur échec : 478 entrées sur 1 080 mesurées), l'application n'est rendue **qu'une fois les deux résolues** (sinon l'appelant lirait un index Pathoschild vide), la version du jeu part sanitisée, et les décisions de fin de passe sortent avec la composition : succès enregistré seulement si la passe est **complète** (X47), le 429 nommé `rate_limited`, les lignes de journal (filet limité, passe amputée, échec, cas dégradé). Les tampons `pendingSmapi*` — trois propriétés du VM ne servant qu'à capturer le résultat smapi.io en attendant le dump — deviennent des variables locales au type, qui ne publie rien. `SmapiUpdateClient.Failure` devient `Equatable` (additif). ⚠️ Le premier essai de sabotage a révélé un test creux sur l'invariant de synchronisation — renforcé (vidage déterministe de la queue) avant preuve rouge. Deux déviations consignées au §6 (ordre de deux lignes de journal ; notify posé avant le départ des requêtes). ViewModel : 10 491 → **10 448**. ⚠️ Restent au VM : clé/compte/quota, la file de téléchargement, les archives, les catégories |
| ~~8~~ 🔶 | **Nexus, tranche 4 — les catégories** — livrée le 2026-09-11 | `Models/NexusCategoryResolver.swift` (Core, **10 tests**, prouvés rouges par sabotage sur trois mécanismes) : la précédence de la catégorie affichée — override utilisateur (par nom de dossier, en-tête de pack compris) > catégorie API par identifiant Nexus **effectif** > pour un en-tête de pack sans id propre, le **dominant** de ses enfants > rien. Le dominant n'exige pas de majorité (un seul enfant connu suffit) et départage les ex æquo par l'identifiant de catégorie le plus bas.<br>🚩 **La mémoïsation reste au VM, double optionnel compris** : `categoryCache` est un `[String: NexusCategory?]` où un `nil` mémoïsé signifie « inconnu, déjà calculé » — l'aplatir en `[String: NexusCategory]` ferait rebalayer les ~949 mods sans catégorie à chaque appel, soit exactement le chemin que **F3** met en cause.<br>⚠️ **Un « bug latent » relevé puis réfuté** : `setCustomCategory` semblait ne pas invalider le cache (grep). La lecture du code montre l'inverse — `nexusMetadataCancellable` souscrit à `objectWillChange` du store et purge `categoryCache` à chaque écriture (VM `:2129`). La doc du cache dit vrai ; ne pas rouvrir. ViewModel : 10 448 → **10 413** |
| ~~9~~ 🔶 | **Nexus, tranche 5 — la file de téléchargement** — livrée le 2026-09-11 | `Models/NexusDownloadFlow.swift` (Core, **9 tests**, prouvés rouges par sabotage sur quatre mécanismes). ⚠️ **Se juge à ses duplications supprimées, pas à ses lignes** (−2 au VM) :<br>• le prédicat **« créneau occupé »** (un transfert court **ou** une feuille d'installation attend d'être fermée) vivait en **trois exemplaires** — refus d'un nouveau clic, aiguillage, drainage ;<br>• la table des **neuf messages d'erreur** vivait en **deux exemplaires** — le VM et `NexusDownloadError.errorDescription`, mêmes neuf clés, deux résolveurs. La table rend désormais la **clé et ses arguments** ; chaque site la résout avec son bundle (principal pour `errorDescription`, vivant pour ce que l'utilisateur voit — seul le second suit un changement de langue en session). Une table, deux résolveurs.<br>S'y ajoute la classification d'un résultat : succès installable (avec les faits **X9**, `nil` quand la page ne datait pas son fichier), annulation qui journalise **sans alerter** (annuler n'est pas une panne), vraie panne qui alerte et journalise. `NexusDownloadOutcome` quitte `NexusDownloader.swift` (réseau, hors Core) pour `NexusDownloadAPI.swift` — déplacement pur, sans lequel la classification ne pouvait pas rejoindre Core. ViewModel : 10 413 → **10 411** |
| ✅ | **Nexus — clos pour la logique** (2026-09-11) | Les deux blocs restants ont été **lus pour trancher, pas laissés de côté** (§6, cond. 3 : le noter plutôt que laisser croire à un oubli).<br>• **Clé / compte / quota** (~43 l.) : chaque ligne est un appel au singleton `NexusUpdateChecker.shared` (Trousseau, réseau) ou une écriture de `@Published`. Le seul calcul est un `trimmingCharacters` avec garde non-vide — un type pour ça n'achèterait rien.<br>• **Archives** (~74 l.) : `NexusArchiveStore` porte **déjà** en Core, et testé, tout ce qui décide — `keep`, `applyRetention`, `remove`, `removeAll`, `entries`. Ce qui reste au VM est le garde de préférence, les I/O et le journal. La règle la plus subtile du bloc (réinstaller travaille sur une **copie**, jamais sur l'archive elle-même — la feuille efface le fichier qu'on lui confie, donc réinstaller détruirait le moyen de réinstaller) est documentée au point d'usage ; l'extraire séparerait la règle de l'appel `FileManager` qu'elle protège.<br>**Bilan du domaine** : 5 tranches, **50 tests** neufs, ViewModel **10 723 → 10 411** (−312). Reste **Traduction FR** (~2 190 l. annoncées, ~1 750 réelles — la couverture FR est partie au point 3), dernier des deux lourds — entamé, voir les deux lignes suivantes |
| ~~10~~ 🔶 | **Traduction FR, tranche 1 — où une traduction s'écrit** — livrée le 2026-09-11 | `Models/TranslationTarget.swift` (Core, **14 tests**, prouvés rouges par **six** sabotages sur six mécanismes) : la décision la plus dangereuse du domaine, jusqu'ici enfouie au milieu des 240 lignes de `saveTranslation`. Un seul `.json` posé à la racine d'un dossier rangé en **layout B** fait cesser la lecture de *tous* ses sous-dossiers par SMAPI, pour toutes les locales. Quatre règles : le fichier qui porte déjà la clé gagne (**replié** — SMAPI compare en `OrdinalIgnoreCase`, écrire `Greet` à côté de `greet` créerait un doublon que le jeu tranche sans nous) ; un fichier de locale unique accepte une clé neuve ; plusieurs fichiers sans la clé **refusent** plutôt que d'inventer la section ; une locale absente n'est créée à la racine que si les sources y vivent aussi.<br>**Mesure du parc (2026-09-11)** : 665 dossiers `i18n`, **7 en layout B dont 5 traduits en français** (`.Merchant`, `East Scarp NPCs`, `[CP] Button's Extra Books`, `Hootin' & Hollerin'`, `[CP] Sword & Sorcery`) ; **aucun** cas de racine masquant un `fr/`. Les fixtures portent ce que le parc porte : UTF-16, CRLF, et un fichier produit par le vrai écrivain (`TranslationDocument` + `TranslationFileStore`). Deux déviations consignées au §6. ViewModel : 10 411 → **10 334** |
| ~~11~~ 🔶 | **Traduction FR, tranche 2 — la comptabilité du lot** — livrée le 2026-09-11 | `Models/TranslationBatchRun.swift` (Core, **15 tests**, prouvés rouges par **sept** sabotages sur sept mécanismes) : six compteurs, la coupure du service de secours et une sortie de boucle nommée, jusqu'ici mêlés au réseau et à l'écriture dans `runBatch`. Le type ne connaît ni l'un ni l'autre — l'appelant traduit, écrit, **soumet ce qui s'est passé** et reçoit ce qu'il doit faire (patron `NexusResume`). Quatre règles que rien ne gardait : une proposition **non écrite** est une erreur et ne nourrit ni les traduites ni le signalement du glossaire (celui-ci porte sur ce qui est *sur le disque*) ; une erreur de point d'accès due à **notre propre annulation** n'est pas comptée (sinon chaque arrêt demandé rapportait une erreur fantôme) ; quota, rythme refusé et clé refusée sont trois causes distinctes parce que ce sont trois remèdes distincts ; le lot ne survit à la coupure que si l'IA locale est réglée.<br>`BatchProgress` et `BatchReport` deviennent des **alias** vers les types Core — les quatre sites de vues qui les nomment restent en place (P8). Une déviation consignée au §6. ViewModel : 10 334 → **10 270** |
| ~~🚩~~ ✅ | **Un N+1ᵉ chemin, corrigé le 2026-09-11** | Le report de renommage de clés (C2-T4, `applyRenameReportTranslation`) composait `i18n/fr.json` **en dur** : sur un mod en layout B la lecture échouait, la boucle faisait `continue` **sans journaliser**, et l'écran annonçait « rien à reporter ». Les cinq mods relevés ci-dessus ne sont pas les plus petits — `East Scarp NPCs` porte **11** fichiers français, `[CP] Button's Extra Books` 6, `.Merchant` 3, `[CP] Sword & Sorcery` 2, `Hootin' & Hollerin'` 1, et **aucun** n'a de `fr.json`. `RenameReport.applyToFrenchFiles` (Core, **7 tests**, trois sabotages rouges) répartit les paires sur tous les fichiers de la locale : une paire va dans le fichier qui porte sa clé, **une seule fois** même si deux fichiers la portent (SMAPI ne sert que la première — compter les deux annoncerait plus de clés reportées qu'il n'y en a), un fichier que rien ne change n'est pas réécrit, un fichier illisible n'emporte pas les autres. Les paires sont **ventilées par fichier** pour qu'une écriture ratée ne retire du bilan que les siennes. Corrigé en TDD dans son propre commit (`09781b3`), jamais glissé dans une extraction |
| ~~12~~ 🔶 | **Traduction FR, tranche 3 — l'identité d'un dépôt** — livrée le 2026-09-11 | `Models/DepositIdentity.swift` (Core, **13 tests**, prouvés rouges par **six** sabotages sur six mécanismes) : de quelle page Nexus vient ce qu'on dépose dans un mod, jusqu'ici quatre `??` chaînés au milieu de `depositIntoMod`. La priorité (fiche Nexus > nom du fichier > identifiant du téléchargement) et la règle de date — **celle du dépôt, jamais celle que porte le nom**, et aucune date pour un dépôt que rien n'identifie, sinon `isNewer` conclurait « à jour » sur une provenance inconnue. `Resolved.entry(…)` devient la fabrique **unique** de la ligne de registre : la sonde de doublon et la ligne gardée ne peuvent plus diverger. `incumbent(in:kind:host:probe:)` dit ce qu'un dépôt remplace — une greffe n'écarte jamais la traduction du même mod.<br>🚩 **Un test creux trouvé par le sabotage, et corrigé** : la priorité « fiche > nom » était portée **en double** — un ternaire `nexus == nil ? … : nil` *et* l'ordre des `??` — si bien qu'aucun sabotage unique ne pouvait la faire rougir. Une seule porte reste. C'est le second cas du dépôt (après la tranche 3 de Nexus) où le sabotage révèle que le test ne prouvait rien.<br>ViewModel : 10 270 → **10 269** — la tranche se juge à ses règles mises sous test, pas à ses lignes |
| ~~13~~ 🔶 | **Traduction FR, tranche 4 — présence et mise à jour** — livrée le 2026-09-11 | `Models/TranslationPresence.swift` (Core, **13 tests**, prouvés rouges par quatre sabotages). ⚠️ **Se juge à ses duplications supprimées** : deux règles vivaient en double exemplaire.<br>• « une version plus récente existe-t-elle » était écrite **deux fois** — `translationUpdateAvailable` et `addonUpdateAvailable`. Le type prend explicitement **les deux moitiés** de résultats, parce que celui qui porte la mise à jour est par nature celui qu'on a **retiré** des propositions : ne regarder que la première faisait disparaître la pastille, défaut déjà payé une fois et jusqu'ici sans test.<br>• « ce mod est-il traduit » réimplémentait à la main ce que `I18nLocaleResolver` porte déjà — **sans la règle « la racine gagne »**. Un dossier avec un `.json` à la racine et un sous-dossier `fr/` était annoncé traduit alors que SMAPI ne sert jamais ce `fr/`. Le quatrième sabotage rejoue exactement l'ancienne implémentation et rougit ce cas. Aucun mod du parc n'est concerné (mesuré) : la correction vaut pour les prochains.<br>ViewModel : 10 269 → **10 256** ; `try_optional` 334 → 333 en prime |
| ✅ | **Traduction FR — clos pour la logique** (2026-09-11) | Les zones restantes ont été **lues pour trancher**, pas laissées de côté (§6, cond. 3).<br>• **`saveTranslation`** (164 l.) : la cible est partie en tranche 1 ; la garde de dérogation qui reste ne compose que `TranslationTokenCheck.mismatches` et `TranslationWaiver.isAccepted`, **tous deux déjà en Core et testés**. Ce qui l'entoure est une lecture disque conditionnelle (ne consulter le magasin que si un blocage est en jeu) et l'écriture — l'extraire séparerait la règle de l'I/O qu'elle gouverne.<br>• **Export / import de lot** (146 l.) : `TranslationLot.build`, `TranslationLotImport.read` / `writableRows` / `identity` portent déjà tout ce qui décide. Reste la boucle d'écriture, les drapeaux « à relire » et le journal.<br>• **Glossaire** (~95 l.) : `GlossaryBuilder`, `GlossarySource`, `GlossaryStore.needsRebuild` sont en Core ; `glossaryMatches` fait **une ligne** (`Glossary.matchEntries`, où vit l'index par premier mot). Reste le drapeau « une fois par lancement » et l'I/O. Seul résidu notable : `gameAssetSuffix(for:)`, 6 lignes de correspondance `fr` → `fr-FR` à un seul appelant.<br>• **`archivePaths(under:)`** — **pas un reste : extrait** (tranche 5, `Models/ArchivePaths.swift`, 6 tests, trois sabotages rouges). Elle était `static` et sans `self`, donc §4.4 s'appliquait, et elle produit l'**entrée** de tout le classement d'un dépôt : une liste vide y fait passer une archive valide pour « contenu non reconnu ». Elle porte la normalisation `/var` ↔ `/private/var` **des deux côtés** — le sabotage qui la retire vide la liste entière. ⚠️ Elle vit dans son **propre fichier** : l'ajouter à `ManifestlessArchive.swift` faisait franchir à celui-ci le seuil de `oversized_files` (37 → 38), et le cliquet l'a dit — patron à corriger, pas à assumer.<br>• **`rootFileOwners()`** (30 l.) : lit `allInstalledMods()` sur `self` — **non extractible** au sens du critère des entrées. Reste au VM.<br>• **Traductions communautaires** (~850 l.) : après les tranches 3 et 4, ce qui reste est de l'orchestration réseau et des écritures `@Published` — `searchTranslations`, `searchSupplements`, `installTranslation`, `linkToNexus`, `removeTranslation`. `NexusModSearch.partition` / `confirmedNexusId` / `supplements`, `ManifestlessArchive.classify` et `ManifestlessInstaller` décident déjà en Core.<br>**Bilan du domaine** : 5 tranches + 1 correctif de bug, **68 tests** neufs, ViewModel **10 411 → 10 241** (−170). Le **bloc de tête** (point 4, ~1 858 l.) redevient la plus grosse cible ouverte |
| 14 🔶 | **Profils, tranche 1 — l'aiguillage d'une activation** — livrée le 2026-09-11 | `Models/ProfileActivation.swift` (Core, **16 tests**, prouvés rouges par cinq sabotages). `applyProfile` portait six branches, chacune avec sa raison, et aucune sous test — or ce sont les **rares** qui portent le risque : elles ne se rencontrent qu'après un crash (reprise R2) ou une application partielle, quand l'état du parc est déjà fragile. Un re-clic du profil actif fait **trois** choses selon l'état de la reprise (re-présenter le résolveur, reprendre les déplacements, adopter les bascules manuelles), et le journal prime sur la reprise muette quand les deux coexistent ; quitter capture les réglages du profil quitté **même si aucun dossier ne bouge** et tranche la question posée par le crash ; le journal du profil **entrant** est gardé, celui de tout autre effacé ; un identifiant orphelin vaut « quitter », jamais une activation au hasard.<br>⚠️ **`isGameRunning()` passe en closure paresseuse, et un test épingle la paresse** : cette fonction informe au passage le garde anti double-lancement (`launchGate.noticeGameRunning()`) — la consulter pour un départ ou un refus déplacerait ce garde sans qu'aucune activation soit en jeu. Même patron que les closures d'`Inputs` du cadrage de la liste (§6). Le trouver a demandé de **lire** `isGameRunning`, pas de supposer qu'un prédicat est pur.<br>Repère : `pre-refactor-profile-activation` (`bd5cdec`) — `pre-refactor-profiles` était déjà pris (§4.6). ViewModel : 10 241 → **10 223**. ⚠️ Restent au domaine : `applyProfileToFilesystem`, capture/restauration des configs (B3-T5), la reprise R2 elle-même, le CRUD |
| 15 🔶 | **Profils, tranche 2 — les abstentions de la capture** — livrée le 2026-09-11 | `Models/ProfileConfigCapture.swift` (Core, **14 tests**, six sabotages rouges). `captureProfileConfigs` refuse de mémoriser les `config.json` dans **trois** états, chacun documenté et aucun éprouvé. Ils partagent une règle : **laisser le trou visible plutôt que maquiller une donnée fausse** — dans les trois cas le disque ne porte pas ce que le profil croit y avoir, et capturer lui attribuerait le contenu d'un autre, dans le geste même censé préserver ses réglages. Le jeu passe **en premier** (c'est la cause que l'utilisateur peut traiter tout de suite) ; la désynchronisation et le journal ne valent que pour **ce** profil ; l'application interrompue est nommée par le **journal**, qui survit au renommage comme à la suppression. Le compte de fin dit ce que la passe a **changé** — ajouts, retraits, textes modifiés — jamais le total du magasin.<br>⚠️ **Reste non testé dans `restoreProfileConfigs`**, et noté ici pour ne pas être omis d'un futur bilan (le précédent d'`archivePaths`) : le **merge d'abord, repli verbatim** (§5.3 — le verbatim écrasait les clés neuves d'un mod mis à jour) et le choix entre les deux messages de bilan (« deux comptes plutôt qu'un » : « restaurés » seul masquerait qu'une partie l'a été sans merge). ViewModel : 10 223 → **10 220** |
| 16 🔶 | **Profils, tranche 3 — les deux gestes du dialogue R2** — livrée le 2026-09-11 | `Models/ProfileRecovery.swift` (Core, **11 tests**, quatre sabotages rouges). « Reprendre l'application » et « Garder l'état actuel » ne se rencontrent qu'après un crash survenu **en cours d'application**, quand `Mods/` est à moitié déplacé : les chemins les moins parcourus, et les plus coûteux à se tromper. Un profil **supprimé** ne peut pas être repris — le journal est tranché plutôt que laissé, sinon l'alerte revient à chaque lancement sans issue ; le jeu ouvert refuse mais **garde** le journal ; « Garder l'état actuel » n'adopte les bascules que si le profil interrompu est encore l'actif.<br>Cliquet : `oversized_excess_lines` +7, **assumé** — le `switch` est plus long que les gardes qu'il remplace, et il rend onze chemins vérifiables. ViewModel : 10 220 → **10 227**.<br>⚠️ **Condition 4 (§4.5) pour les trois tranches Profils** : aucun agent n'a lancé l'application, et ce sont les tranches qui déplacent des centaines de dossiers et réécrivent des `config.json`. Scénario minimal à exercer par l'auteur — (1) jeu fermé, basculer A → B → A et lire au journal « configs mémorisés » puis « restaurés », avec un compte plausible et non le total du magasin ; (2) re-cliquer le profil actif : il adopte les bascules manuelles sans rien déplacer ; (3) **jeu ouvert**, tenter une activation : refus nommé et **aucune** mutation — c'est la branche dont l'ordre des gardes n'a été vérifié que par lecture |
| 17 🔶 | **Entretien, tranche 1 — la résolution du dossier réel** — livrée le 2026-09-11 | `Models/ModRootResolver.swift` (Core, **8 tests**, quatre sabotages rouges). `resolvingModRoot` était `static` et sans `self` dans le ViewModel : §4.4 s'appliquait, et elle porte la règle du toggle par préfixe point, celle qui a déjà coûté quatre défauts en une soirée. L'actif prime sur la pause quand les deux coexistent (cas réel du parc), et un composant manquant rend `nil` plutôt qu'un chemin plausible — le rendre ferait écrire dans un dossier inexistant, ou dans un autre mod.<br>**Mesure inscrite au type pour ne pas la refaire** : **721 dossiers en pause à la racine**, et **un seul** dossier pointé au niveau 2 sur tout le parc — qui n'est pas un mod (`.ModCollectionAlbum/.config`). Le point vit donc bien sur l'entrée de tête.<br>🚩 **Trois autres résolutions coexistent et divergent — relevées, mesurées, non unifiées** : `ModConfigBackupManager` et `ModInstallBackupManager.restoreBackup` ne préfixent que la tête (ils ne trouveraient pas `Pack/.Composant`), et le second garde exprès les deux chemins pour détecter leur coexistence. Les aligner demanderait de toucher trois chemins d'**écriture** pour corriger un défaut que le parc ne porte pas : la divergence est consignée dans la doc du type, à traiter au contact. ViewModel : 10 227 → **10 212**.<br>⚠️ **Le domaine n'est pas clos** : restent `buildMaintenanceReport`, `readMaintenanceReport`, `walkBackup`, `purgeInstallBackups`, `cleanStaleMaintenanceEntries` et `installedState`. Condition 4 : vérifier à l'écran qu'un fichier protégé se récupère depuis l'Entretien — c'est `ModRootResolver` qui lui trouve désormais son dossier |
| 18 🔶 | **Découverte, tranche 1 — les trois écarts de la vitrine** — livrée le 2026-09-11 | `Models/DiscoveryScoping.swift` (Core, **14 tests**, cinq sabotages rouges). La vitrine écarte trois choses en une passe — contenu adulte (spec §8), traductions non françaises, « masquer les installés » — puis reconnaît ce qui est déjà au parc. Le filtre francophone ne vaut **que pour les traductions** (l'appliquer à tout viderait la vitrine) et **pas du tout à la recherche par nom**, où l'on cherche un mod précis ; un mod est reconnu installé par son identifiant **ou par son titre** (compte gratuit = installation à la main = pas d'identifiant) ; « masquer » retire la ligne, jamais le badge ; l'ordre de Nexus est gardé, c'est le tri de la section demandée ; et **l'offset de « voir plus » compte le reçu, jamais l'affiché** — compter les visibles ferait redemander sans fin ce que les filtres viennent d'écarter.<br>🚩 **Fixture corrigée en cours de route, second cas de la session** : elle posait `categoryName: "Translations"`, mais c'est le **tag** `Translation` qui range un mod parmi les traductions (`Hit.isTranslation`). La fixture décrivait un état que Nexus ne produit pas, et le filtre francophone y paraissait inopérant. `DiscoveryRow` devient un alias vers `DiscoveryScoping.Row` (P8). ViewModel : 10 212 → **10 207**.<br>⚠️ **Le domaine n'est pas clos** : restent `fetchDiscoverySection`, `searchDiscovery`, `loadMoreDiscoverySearch`, `loadDiscoveryDetail` et les deux compteurs d'époque. Condition 4 : ouvrir Découvrir, vérifier qu'une section se remplit **puis que « voir plus » ajoute des cartes sans boucler** — c'est l'offset qui a changé de porte |
| 19 🔶 | **Profils, tranche 4 — la métadonnée d'un import** — livrée le 2026-09-11 | `ProfileFactory.metadata(forIds:in:)` (Core, **6 tests**, quatre sabotages rouges). ⚠️ **Se juge à sa duplication supprimée** : `importFavorites` et `importBlacklisted` portaient la **même** boucle d'enrichissement de `modMetadata`, à l'identique — leur documentation le disait déjà (« strictement symétrique », « le même enrichissement ») sans que le code en tire la conséquence. La résolution est **insensible à la casse des deux côtés** (les `UniqueID` des manifestes ne s'accordent pas dessus, et une résolution stricte perdrait la métadonnée en silence), la clé rendue est l'identifiant **tel que demandé** — celui qui entre dans `enabledModIds`, une autre ne serait jamais retrouvée — et le premier gagne quand deux dossiers partagent un identifiant, cas réel du parc.<br>Cette métadonnée n'est pas décorative : c'est la seule source qui permette encore de **nommer** un mod du profil une fois qu'il aura été désinstallé. ViewModel : 10 207 → **10 203**.<br>⚠️ Condition 4 : importer les favoris dans un profil et vérifier que le compte annoncé correspond |
| 20 🔶 | **Entretien, tranche 2 — le tri de « vider les mods désactivés »** — livrée le 2026-09-11 | `Models/DisabledModsCleanup.swift` (Core, **11 tests**, cinq sabotages rouges). ⚠️ **Cette fonction supprime définitivement — pas à la corbeille** — et son tri n'était pas vérifiable. L'enjeu n'est pas théorique : **721 dossiers du parc sont en pause** et partiraient tous d'un seul geste. Le scan traite tout dossier en point comme un mod en pause : sans la garde `OSJunk`, `.Spotlight-V100` et `.Trashes` seraient emportés par un bouton qui promet de ne toucher qu'à des mods — c'est le défaut qu'`OSJunk` a déjà corrigé une fois côté scan (quatre copies, une amputée). « Supprimés avec succès » n'est jamais dit sur zéro dossier, un échec partiel n'est pas masqué par le compte des réussites, et une passe qui n'a rien touché ne déclenche pas de rescan — plusieurs secondes sur ~900 mods.<br>**Mesure consignée** : les 721 entrées pointées sont **toutes** des dossiers de mods, aucun résidu système parmi elles. ViewModel : 10 203 → **10 201**.<br>⚠️ Condition 4 : ce bouton confirme, mais **sa confirmation ne dit pas combien** de dossiers partent. Sur ce parc, c'est 721. À trancher par l'auteur — l'ajouter serait une fonctionnalité, pas une extraction |
| 🔎 | **Relevé de rendement — 2026-09-11, à lire avant de reprendre** | Les cinq tranches 15 à 19 totalisent **−20 lignes de ViewModel** (−13, −15, −5, −4, +7). L'argument « se juge à ses duplications supprimées » tient pour `TranslationPresence`, `ModRootResolver` et `ProfileFactory.metadata` — il ne tient pas pour les autres. Pendant ce temps, **trois zones n'ont jamais été ouvertes** : **Sauvegardes** (~560 l.), **Liste & parc** (~1 350 l.) et la part de **B4-T4** qui **écrit dans les dossiers de mods** — `scanRecoverableFiles`, `recoverFile`, `resetModConfigToDefaults`, `profileConfigDiffs`, `topLevelJSONKeys`. Les passer au critère des entrées (§5) **avant** toute nouvelle micro-tranche |
| 21 🔶 | **Accueil — le slot thaï se résout comme les autres** — livrée le 2026-09-11 | `CoreModSlot.resolve` gagne un `folderName:` optionnel (Core, **6 tests**, quatre sabotages rouges). `coreExtensionsSnapshot` portait une cascade écrite à la main pour le hub thaï — quatre `??` — à côté du type qui fait ce travail pour Content Patcher, SpaceCore et SVE : une copie de plus de la même règle, et la seule des deux qui n'était pas testée. Le **nom de dossier** connu prime sur une correspondance de nom (un auteur peut renommer son mod), mais **ce qui tourne prime sur le dossier exact en pause** — l'accueil doit annoncer ce qui sert au joueur. Sans `folderName`, la cascade reste exactement celle d'origine, et un test l'épingle. ViewModel inchangé en lignes : la tranche se juge à la copie supprimée |
| 🛑 | **Constat d'arrêt — le ViewModel n'a plus de logique pure extractible** (mesuré le 2026-09-11, après la tranche 21) | Relevé sur le fichier lui-même, pas déduit : **337 fonctions**, dont **69 d'I/O**, **151 qui mutent l'état publié**, et 117 « calculs » qui sont en fait des **enveloppes de 1 à 13 lignes déléguant à Core**. Le plus gros calcul pur restant fait **13 lignes**. Les **128 `@Published`** (135 au relevé du §6, −7 depuis) sont désormais le sujet, et le §6 le disait déjà : *« les 135 propriétés publiées sont le vrai sujet »*.<br>**Conséquence pour la prochaine session** : chercher une tranche d'extraction de plus dans ce fichier produira des gains de quelques lignes — c'est ce que le relevé de rendement ci-dessous constate déjà sur les tranches 15 à 21. La suite est la **phase « vider le VM de son état publié »** (stores + P8), qui demande un **cadrage architectural dédié** et ne s'ouvre pas au fil d'une session d'extraction. Ne pas la commencer sans l'accord explicite de l'auteur |

**Non classés, et pourquoi** : Nexus (~2 000 l.) et Traduction FR (~2 190 l.) sont les
deux plus gros domaines, mais ce sont aussi les deux plus enchevêtrés avec le réseau et
le disque — les ouvrir en premier ferait porter le premier protocole *et* le premier
gros déplacement par le même commit. Ils viennent après que la recette a été éprouvée
sur les points 1 à 3.

*(Mise à jour 2026-09-11 : la recette ayant été éprouvée sur les points 1 à 4,
Nexus a commencé — voir la ligne 5 du tableau ci-dessus. Traduction FR reste
non classée.)*

**Deux chantiers transverses, repris de leurs phases 8 et 9** — absents de la
première version de ce plan :

| Chantier | Quand | Pourquoi ici |
| --- | --- | --- |
| **Découper les vues** (leur P8, cible ~150 lignes) | **Au contact** : quand on extrait un domaine, on découpe la vue qui le consomme, dans le même mouvement | Au 2026-09-10 : `ModListView` **2340** lignes, `ModDetailView` **2145**, `MainView` **1536**, `SavesView` **1162**, `LogsView` 746 — la même pente que le ViewModel (`ModDetailView` a triplé depuis le relevé de 683). Une campagne dédiée serait un big-bang sans filet ; couplé à l'extraction, le découpage a une raison d'être et un périmètre |
| **Verrouiller les règles** (leur P9) | ✅ **Fait le 2026-09-10** | `build_app.py` refuse désormais qu'un fichier du target SPM importe SwiftUI — barre dure, échec rapide avant compilation (pas un cliquet), épreuve §4.7 faite (injection volontaire → `[ERROR]` → restauration). **Elle a mordu à l'installation** : `NexusCategory` et `SaveFarmerPalette` importaient SwiftUI pour leurs couleurs — conversion §4.4 en `RGBColor` (Core) rendu par `Color(RGBColor)` (AppDesignUI). `AppKit` reste volontairement hors barrière : quatre fichiers Core en dépendent (dette ci-dessous, au contact de chacun) |

**Deux dettes de couche, à traiter au contact plutôt qu'en campagne** — trouvées en
passant leurs correctifs en revue (§8), et sans urgence propre :

| Dette | Déclencheur |
| --- | --- |
| `NSOpenPanel` appelé depuis le ViewModel (`:2321` dans `selectGameDir`, `:8728` dans `selectCustomAvatar` — coordonnées du 2026-09-10), ce qui rend ces fonctions intestables | ✅ **La moitié est faite** : le protocole `FilePicking` est né avec l'extraction d'Environnement (2026-09-10) et `selectGameDir` ne voit plus AppKit. **Reste** `selectCustomAvatar` (coordonnée à re-relever) — le protocole gagnera alors un `pickFile`, au moment où l'extraction touchera l'avatar, avec son bouchon dans le même commit |
| AppKit importé hors des vues par `ContrastChecker`, `SaveManager`, `DescriptionBlockParser` et le ViewModel — les trois premiers étant **déjà dans Core** | À traiter quand on modifie l'un d'eux, pas avant : ils compilent, la gêne est théorique tant qu'on n'y touche pas |
| `ModVersionAnchorStore.swift:26` porte `private static let registryKey = "installedModRegistry"` **en littéral, hors `UDKey`** — second lecteur de la clé que possède désormais `InstalledModRegistryStore` (relevé le 2026-09-10) | Au prochain passage sur la migration `migrateAwayFromNexusVersion`. Ce n'est pas une ligne à changer à l'aveugle : cette migration réécrit le **JSON brut** du registre, c'est-à-dire qu'elle contourne volontairement le type `InstalledModRecord`, et l'ordre de ses trois appels au lancement est déjà délicat (voir l'avertissement en tête du store). **Complété par la revue du 2026-09-10** : elle ne réécrit que la clé principale — jamais le secours — et si la clé principale est illisible au moment de migrer, elle rend « illisible » pendant que le store, lui, restaurerait depuis un secours qu'elle n'aurait pas touché : c'est le contournement exact des trois mécanismes de sûreté que l'extraction a mis en place. Rien ne l'applique dans le code ; seul l'ordre de lancement (migrer avant `warmCache`) y pourvoie |
| `ModManifest.init?(dict:)` construit le `ManifestFields` **complet** (dépendances, clés de mise à jour, identifiant Nexus) avant la garde `Name`/`UniqueID` — l'ancien code gardait d'abord sur deux lectures de dictionnaire (revue du 2026-09-10) | Aucun, volontairement. Le gaspillage ne porte que sur le chemin de rejet d'un manifeste invalide — rare, initié par l'utilisateur, quelques microsecondes de lectures de dictionnaire. Garder d'abord réimpliquerait une seconde lecture insensible à la casse à côté de `ManifestFields`, la source unique : deux portes pour une règle, le motif que ce dépôt chasse |

**Règle permanente (F1-T2)** : une fonctionnalité neuve ne rentre plus dans le
ViewModel. Elle naît dans son propre type, que le ViewModel se contente d'appeler.
Le plan du hub de traduction la respecte déjà.


## 6. Le bloc de tête — ~1 858 lignes en **deux morceaux**, 135 propriétés publiées

> ⚠️ **Coordonnées corrigées le 2026-09-10.** Ce § disait « 1934 lignes, 70 propriétés
> publiées, 36 fonctions », et « tout ce qui précède la première `MARK` ». Les trois
> chiffres et la définition sont faux aujourd'hui :
> - le bloc de tête n'est plus contigu. Il occupe **1–574** *et* **1913–3196**,
>   séparés par 1 338 lignes de traduction (pré-traduction, glossaire, couverture) ;
> - « ce qui précède la première `MARK` » ne désigne plus que 797 lignes, parce
>   qu'une `MARK` s'est insérée au milieu du bloc — la moitié du God module vit
>   sous l'étiquette « Couverture française d'un profil (B3-T4) » (voir l'encadré
>   du §5) ;
> - le fichier porte **135 `@Published`** (et non 70), dont **70 sans
>   `private(set)`**, et **52 accès à `UserDefaults`** (et non 33 — voir §9, P3).
>   ⚠️ Ces trois nombres se comptent **hors commentaires** : un `grep` nu sur
>   `@Published` en rend 166 et sur `UserDefaults` 73, parce que la
>   documentation du fichier parle abondamment des deux (31 mentions pour le
>   premier, 21 pour le second). `check_standards.py` retire les commentaires
>   avant de compter — c'est son chiffre qui fait foi, et le contrôle croisé
>   tombe juste : 70 dans le VM + 5 ailleurs = les 75 de la baseline.
>
> Ce qui suit — la table des domaines, le tri des `@Published`, la cible, l'ordre
> interne, les quatre conditions — **reste valable** : c'est du raisonnement, pas des
> coordonnées. Seuls les emplacements avaient bougé.
>
> **Relevé d'après-tranche (2026-09-10, fin de journée)** : le VM est à **11 410
> lignes** et porte **131 `@Published`**, dont **66 sans `private(set)`** — quatre
> propriétés d'Environnement sont parties dans `GameEnvironmentStore` avec un
> accesseur protégé, et le cliquet est resserré en conséquence (75 → 71 : 66 au VM
> + 5 ailleurs). Le domaine Environnement est sorti des deux morceaux ; ce qui
> reste du bloc de tête est inchangé par nature.
>
> **Relevé d'après-tranche (2026-09-10, Localisation)** : le VM est à **11 341
> lignes** et porte **130 `@Published`**, dont **65 sans `private(set)`** —
> `currentLanguage` vit dans `LocalizationStore` (Core, testé), et le domaine
> Localisation est sorti **entièrement** : plus aucune fonction, plus aucune
> façade définitive, plus de relais — les vues et l'App observent le store
> directement. Le cliquet atteste la migration : `vm_dot_L_calls` est descendu
> de 1 462 **à 0** et y est verrouillé.
>
> **Relevé d'après-tranche (2026-09-11, Nexus t1)** : le VM est à **10 558
> lignes** — `applySmapiResults` n'y garde plus que publication, persistance,
> journal (via le rapport `SmapiVerdicts.Report`) et lancement de la reprise.
> La classification, le filet « sans réponse » et les fusions vivent dans
> `SmapiVerdicts` (Core, 15 tests prouvés rouges par sabotage).
>
> **Relevé d'après-tranches (2026-09-11, Nexus t2→t5)** : le VM est à
> **10 411 lignes** — catégories (`NexusCategoryResolver`, 10 tests ; la
> mémoïsation et ses invalidations restent au VM) et file de téléchargement
> (`NexusDownloadFlow`, 9 tests) ont suivi. La tranche 5 se juge à ses
> duplications supprimées — trois copies d'un prédicat, deux d'une table de
> messages — plus qu'à ses deux lignes. La reprise Nexus (verdicts nommés, substitution du cache, décompte
> honnête) vit dans `NexusResume` (Core, 9 tests) et la composition du check
> dans `NexusUpdateCheck` (Core, 7 tests) — les tampons `pendingSmapi*` ont
> quitté le VM avec elle.

C'est le God module lui-même. Le décomposer est le vrai travail ; le reste n'en est
que la préparation.

### Domaines qu'on y distingue

| Domaine | Fonctions représentatives | Destination |
| --- | --- | --- |
| **Environnement** | `detectDefaultGameDir`, `selectGameDir`, `fetchSteamUser`, `checkSmapiVersion` | ✅ **Extrait le 2026-09-10** — `GameEnvironmentStore` (Core, testé), `FilePicking` + `LiveFilePicker` dans le même commit. Façades provisoires au VM tant que les vues ne réobservent pas le store (voir le point 4 du §5) |
| **Localisation** | `L(_:)`, `localizedString(for:)`, `cachedBundle(for:)` | ✅ **Extrait le 2026-09-10, en deux commits** comme prescrit — `LocalizationStore` (Core, 13 tests prouvés rouges par sabotage sur trois mécanismes), puis le remplacement mécanique des appels : 1 453 sites dans 45 fichiers de vues, 180 appels internes du VM, les menus de l'App, `BisectionRunner`, l'écriture du sélecteur de langue. Le store appartient à l'App (`@StateObject` passé au VM à l'init) : les menus résolvent leurs libellés avant toute vue. Les vues reçoivent le store en paramètre (76 structs) — **aucune façade n'a survécu** : le VM n'a plus ni `L`, ni `currentLanguage`, ni la conformité `L10nResolver` (passée au store ; `SavesView` lui passe directement). ⚠️ Condition 4 : l'exercice manuel de bascule de langue à l'écran reste dû à l'auteur (celui d'Environnement aussi) |
| **Scan** | `scanMods`, `parseModFolder`, `scanEntryForMods`, `cachedManifest`, `migrateDisabledModsToDotPrefix`, `isOsJunk` | 🔶 **Tranche 1 extraite le 2026-09-10** — `ModScanner` (Core, 11 tests) : balayage de `Mods/`, lecture des manifestes, **cache mtime** (l'état du domaine quitte le VM), groupement des packs, repli du nom logique, décision `Mods_disabled` ; `DisabledModsMigration` (Core, 6 tests) pour la migration one-shot. Le critère des entrées a été honoré *a posteriori* : ce que `parseModFolder` allait chercher sur `self` (`installedModDate`, le cache, `log`) lui arrive en valeurs et closures. `scanMods` reste au VM comme **orchestration** — réparation, journal SMAPI, registre, doublons, publication — car chaque étape touche un autre domaine ; c'est elle que la suite du §6 videra. Régression de la course de juillet 2026 testée (4 threads × 5 scans sur une instance). ⚠️ L'état publié (`mods`, `scanProgress`) attend la reprise des vues pour rejoindre un store |
| **Dépendances** | `rebuildDependencyIndexes`, `getMissingDependencies`, `getDisabledDependencies`, `dependencyTree`, `slot(matching:)` | ✅ **Extrait le 2026-09-10** — `DependencyIndex` (Core, 6 tests) : les quatre index dérivés du parc (aplatissement packs, pli de casse, doublons sortis du même parcours) et les requêtes. `duplicateIndex` reste publié au VM (il nourrit les anomalies de ligne) ; les trois requêtes y demeurent en façades minces (5 appelants dans les vues). Le sabotage de l'escalade optionnelle→requise a révélé un test creux — première occurrence déjà requise — renforcé avant preuve rouge. `coreExtensionsSnapshot`/`slot(matching:)` relèvent de l'accueil, pas de ce domaine |
| **Bascule des mods** | `toggleMod`, `processNextToggleIfNeeded`, `performToggle` | 🔶 **Tranche 1 extraite le 2026-09-10** — `TogglePlan` (Core, 8 tests) : le QUOI de la bascule (rapprochement enfant de pack → dossier, re-dérivation de l'état visé depuis l'instantané, chaînage des dépendances requises, republication en mémoire). Le COMMENT reste au VM — renommages disque (via `renameModFolder`, partagé avec bascule en masse et profils), file séquentielle, poids et horodatages — car il est l'orchestration de l'état publié et du disque. Le sabotage de l'escalade a révélé un test creux (première occurrence déjà requise), renforcé avant preuve rouge |
| **Détail de mod** | `loadModDetail`, `fetchModDetailRemote`, `markDetailNotLoading` | ✅ **Tranches 1 à 3 extraites les 2026-09-10/11** — `ModDetailState` (Core, 5 tests) : les transitions cache instantané → repli local → rafraîchissement, et l'arrêt du spinner propre au mod affiché ; `NexusModIdentity` (Core, 4 tests) : l'identifiant effectif (override utilisateur > manifeste), l'id résolu d'un pack (premier enfant qui a quelque chose), le lien public, l'extra ; `ModDetailRefresh` (Core, 3 tests, fetchers injectés) : la composition réseau description→changelogs — une description vide invalide le tout, un changelog vide est acceptable. Le VM garde `loadModDetail` comme séquence orchestrée (cache/repli → fetch → garde anti-course → application), sous façades provisoires (§6, cond. 1). La logique du domaine est en Core ; le réseau et l'état relèvent de Nexus, non classé |

### Les 135 propriétés publiées sont le vrai sujet

Elles sont de deux natures que le fichier ne distingue pas :

- **État de domaine** (`mods`, `smapiDiagnostics`, `outOfDateMods`…) : il appartient au
  futur store.
- **État de présentation** (`viewingModDetail`, `editingModConfig`, `showAlert`,
  `selectedModID`…) : il appartient à la **vue qui le possède**, en `@State` — c'est la
  règle 5.3 de l'upstream.

Le tri n'est pas cosmétique : chaque `@Published` du ViewModel publie à **toute** la
fenêtre, `MainView` l'observant en entier. C'est le mécanisme qu'a montré B1-T2 —
sortir le cadrage de la liste dans `ModListState` a restauré la portée d'origine.

**Règle** : à chaque domaine extrait, classer ses `@Published`. Ceux de présentation
ne suivent pas dans le store ; ils redescendent dans la vue.

### Cible

L'upstream a **supprimé** son ViewModel (leur 4.9 : « s'il reste quelque chose, c'est
qu'il n'a pas été classé »). Ce n'est pas l'objectif ici : sans filet de test sur
l'UI, viser la suppression pousserait au big-bang que le §7 exclut.

La cible est **fonctionnelle, pas numérique** : plus aucune logique métier dans le
ViewModel, qui ne garde que la composition — instancier les stores et les relier aux
vues. Le nombre de lignes en découlera ; le viser directement ferait déplacer du code
pour le plaisir du compteur.

### Ordre

**Écart d'ordre assumé (2026-08-01)** : la logique pure du scan est passée
**avant** Environnement. Ce dernier est petit, sans duplication à récupérer, et
`selectGameDir` y appelle `NSOpenPanel` — il demande donc le protocole `FilePicking`
et son bouchon, soit un chantier propre. La méthode (§4.1, « chercher la logique
pure d'abord ») l'emporte ici sur l'ordre indicatif.

Environnement ✅ → **Localisation ✅** → *(logique pure du scan ✅ —
`parseModFolder` vit dans `ModScanner` ; le point 4 du §5 reste ouvert pour
l'état divers du bloc de tête)* → **Scan 🔶 (tranche 1)** → Dépendances →
Bascule → Détail de mod. Chaque étape est un commit, précédée de ses tests quand la
cible est du calcul pur.

**Cet ordre est interne au §5.5** : on n'y entre qu'après avoir traité les points 1 à 4
du tableau des extractions. Le dire, parce que « l'environnement est le moins
enchevêtré » se lit sinon comme « commencer par lui ».

### Quand un domaine est-il extrait ?

Quatre conditions, toutes vérifiables. Sans elles, « extrait » veut seulement dire
« déplacé », ce qui ne vaut pas le risque pris :

1. **Plus aucune de ses fonctions dans le ViewModel** — pas même une façade qui
   délègue, sauf si des vues non encore migrées l'appellent, auquel cas la façade est
   marquée comme provisoire dans le code.
2. **Ses `@Published` sont classés** : l'état de domaine est parti dans le type extrait,
   l'état de présentation est redescendu en `@State` dans la vue qui le possède (§6).
3. **Sa logique pure est testée** — pas son câblage, sa logique. Si l'extraction n'a
   produit aucun test, c'est que le domaine n'en contenait pas : le noter dans le
   message de commit plutôt que de laisser croire à un oubli.
4. **Les deux gates passent** (`./run_tests.sh`, `python3 build_app.py`) et l'auteur a
   exercé la fonctionnalité à la main — aucun agent ne lance l'application.

### Déviations assumées

Tout écart au « déplacer sans modifier », par extraction. Le tableau existe parce
qu'une de ces trois lignes avait été appliquée sans être dite.

| Extraction | Déviation | Pourquoi, et portée |
| --- | --- | --- |
| Regroupement Nexus (`d802b62`) | `precondition(!updates.isEmpty)` → retour optionnel | Retire un point de crash. L'invariance tenait — les listes viennent d'un regroupement — mais l'exprimer vaut mieux que compter dessus. Aucun appelant affecté |
| Registre des mods (`4d50349`, consigné après coup par `838e32c`) | `Date()` évalué à chaque enregistrement → un instant unique pour tout le lot | Rend la logique vérifiable (l'horloge devient un paramètre) et donne un lot cohérent. Écart réel de quelques microsecondes entre mods d'un même scan ; sans portée, cette date se comparant à une date de mise en ligne dont la granularité est l'heure |
| Résidu système (`OSJunk`) | Le scan reconnaît trois entrées de plus : `Icon\r`, `.Spotlight-V100`, `.Trashes` | **Correction, pas simple déplacement.** Sa copie locale était amputée ; or le scan traite tout dossier en `.` comme un mod en pause, si bien qu'un `.Spotlight-V100` s'affichait comme un mod désactivé nommé « Spotlight-V100 ». Trois autres copies étaient déjà correctes |
| Arbre des sauvegardes (`4204c6e`) | Filtre par étiquette appliqué **après** le tri, au lieu d'avant | Conséquence de l'extraction : `SaveTree.build` trie en construisant. Résultat identique — un filtre ne réordonne pas ce qu'il conserve |
| Store du registre (2026-09-10) | `mutate` rend la valeur produite par son corps | Supprime `WasEmptyBox`, la boîte à un élément qui existait uniquement pour faire échapper un booléen d'une closure `inout`. Le commentaire qui l'expliquait disparaît avec elle |
| Store du registre (2026-09-10) | `anchorStore` et les versions suggérées **arrivent en paramètres** au lieu d'être lus sur `self` et sur `NexusUpdateChecker.shared` | C'est ce qui fait tenir le store dans Core (Foundation seul) et rend `anchorModsUpdatedOnDisk` testable — quatre de ses tests reposent sur une suggestion posée par l'appelant. Le VM garde la lecture du cache plat, avec la mise en garde de course qui la motive |
| Store du registre (2026-09-10) | Les deux `log(…)` sortent en **rapport rendu** (`SyncReport`) | Le store ne connaît ni le journal de l'app ni sa localisation. L'appelant journalise exactement les deux mêmes lignes, aux deux mêmes conditions |
| Lecture du manifeste (2026-09-10) | Le scan ne retire plus les commentaires bloc par expression régulière | **Correction, pas simple déplacement.** JSON5 les gère déjà — mesuré neutre sur les 1 108 manifestes du parc, dont les 47 qui en portent — et l'expression régulière amputait une valeur de chaîne contenant `/* … */`, faute de pouvoir être consciente des chaînes. Défaut latent : aucun manifeste du parc n'en porte dans une valeur |
| Lecture du manifeste (2026-09-10) | Le message du journal ne cite plus le chemin absolu du manifeste illisible | `ManifestJSON.decodeInstalled` ne connaît pas le chemin qu'on lui lit. La ligne journalisée garde le nom du mod (dossier logique ou chemin relatif), qui l'identifie ; la cause vient de `error.localizedDescription`, testée non vide |
| Cadrage de la liste, lot 3 (2026-09-10) | **À dates égales, le tri départage par nom** au lieu de rendre `false` | Changement de comportement réel, et une correction : rendre `false` pour deux éléments équivalents ne donne un ordre reproductible **que si** `sorted(by:)` est stable — la bibliothèque standard ne le garantit pas (elle l'est aujourd'hui, par implémentation). C'est l'argument déjà retenu pour le tri `.name` à blanc, appliqué ici aux ex æquo. Porte sur `.activationOrder` et `.installDate` ; testé |
| Cadrage de la liste, lot 3 (2026-09-10) | Le patron « date décroissante, sans-date en fin, départage par nom » vivait **en deux exemplaires identiques** — un seul `byDateThenName` | Deux copies d'une même règle divergent à la première retouche : c'est le constat de X45 (dix réécritures) et de `isOsJunk` (quatre copies dont une amputée) |
| Cadrage de la liste, lot 3 (2026-09-10) | `Inputs` porte **deux closures et cinq valeurs**, là où le §5 prescrivait « un objet de paramètres portant ces verdicts déjà résolus » | Résoudre les verdicts d'avance transformerait deux chemins paresseux en balayage inconditionnel des 949 mods — `category(for:)` est mémoïsé derrière `categoryCache`, et `ModListView.scopeCounts` existe précisément pour ne pas refaire le balayage de dépendances d'`anomaly(for:)`. Ce serait une régression sur le chemin que **F3** met en cause. L'intention du plan (« ne pas aller chercher sur `self` ») est tenue ; sa forme littérale ne l'est pas |
| Environnement, `GameDirLocator` (2026-09-10) | `gogRoot` arrive en paramètre (défaut `/Applications`), et `restoreGameDir` le laisse passer | Pas un changement de comportement — le défaut vaut l'ancien littéral — mais une couture à consigner : sans elle, la branche GOG est **intrôlable en test** sur la machine de référence, où le jeu est justement installé sous `/Applications`. Même raison pour `home`, `fm`, `systemUserName` : les états de la machine ne sont pas des entrées de test |
| Environnement, `selectGameDir` (2026-09-10) | Un **OK sans URL** vaut désormais annulation ; l'original affectait `panel.url?.path ?? ""` puis relançait `refresh()` — vidant `gameDir` et rescannant | Cas impossible en pratique sur un panneau dossiers-seuls (le bouton est sans effet sans sélection), mais l'ancien chemin écrasait l'état en silence. La nouvelle forme refuse d'écrire quand le panneau ne dit rien |
| Localisation, `LocalizationStore` (2026-09-10) | Le cache de bundles passe de **`static` (sur le type) à l'instance** ; le verrou `NSLock` reste | Même comportement pour l'app, qui ne crée qu'un store ; en test, chaque essai a son cache au lieu d'un cache de type partagé (CLAUDE.md : un cache global impose des tests `.serialized`) — les deux tests de bascule de langue utilisent des racines de ressources différentes |
| Localisation, `LocalizationStore` (2026-09-10) | La racine des ressources **arrive en paramètre** (`resourceURL`, défaut `Bundle.main.resourceURL`) | Couture de test, même motif que `gogRoot` chez Environnement : sous `swift test`, `Bundle.main` n'est pas l'app — sans elle, la chaîne `Bundle(url:)` → `localizedString` serait **intrôlable** ; les tests construisent de vrais `.lproj` temporaires |
| Localisation (2026-09-10) | Le store **appartient à l'App**, pas au VM : `@StateObject` créé dans `StarHubTHApp.init`, passé au VM à l'init et aux vues en paramètre | Les menus de `CommandMenu` résolvent leurs libellés avant toute vue ; s'ils passaient par un relais du VM, ils resteraient figés après une bascule de langue dès la suppression des façades. Un seul `let store` habille les deux `@StateObject` — un wrapper ne peut pas lire un autre wrapper dans l'`init` de la même struct |
| Localisation (2026-09-10) | `knownLanguageCodes`, statique du VM, est **supprimé** plutôt que déplacé | Mort : zéro appelant dans le code comme dans les tests — son commentaire renvoyait à `ModConfigEditorView` qui ne s'en sert plus. Récupérable à `pre-refactor-localisation` si un besoin reparaît |
| Localisation (2026-09-10) | `CompatibilityWarning.label`/`.message` prennent `_ l10n: LocalizationStore` au lieu du VM ; `ConflictActivationGate` et la fonction libre `anomalyReasons` lisent `vm.localization` ; les closures `L:` des composants reçoivent `localization.L` | Ces helpers ne se servaient du VM **que** pour résoudre des clés. La signature du gate et de la fonction libre ne change pas côté appelants (`vm.localization` est un `let` interne du VM) ; les trois fonctions statiques, elles, changent de signature — quatre appelants mis à jour |
| Localisation (2026-09-10) | `MainView` et `ModProfilesView` sont **découpées** au passage (`destinationView`, `handleTabChange`, `sidebarColumn`, `navHistoryButtons`, `profileRow`, `profileDeletionMessage`) | L'ajout d'un argument `localization:` à chaque destination de `MainView` a fait franchir au `body` le seuil de saturation du type-checker — erreurs « unable to type-check in reasonable time » réelles au build. Le découpage en sous-vues est le remède documenté (CLAUDE.md, pièges SwiftUI) ; comportement inchangé, +92 lignes au cliquet `oversized_excess_lines`, assumées |
| Scan, `ModScanner` (2026-09-10) | Le scanner est une **classe**, pas une struct ; le cache mtime est son état d'instance (il était une propriété du VM) | Deux `scanMods()` concurrents (refresh + chargement initial, activation de profil croisant un refresh) doivent toucher le **même** cache : une struct copiée vaudrait deux caches, et la course sur le subscript non protégé est le `EXC_BAD_ACCESS` de juillet 2026 — la régression est testée (4 threads × 5 scans sur une instance partagée) |
| Scan, `ModScanner` (2026-09-10) | La trame de progrès (0/N) qui précède la réparation **reste au VM** ; tout le reste des progrès (throttle ~12/s compris) est émis par le scanner via `onProgress` | L'ordre historique publie la trame **avant** la passe de réparation pour que l'écran de lancement ne soit pas figé pendant qu'elle tourne ; la faire émettre par le scanner l'aurait passée après, la réparation restant chez l'appelant. L'appelant repasse sur le fil principal dans sa closure `onProgress` |
| Scan, `DisabledModsMigration` (2026-09-10) | `defaults`, `fm` et `log` arrivent en paramètres (le journal pré-lié aux niveaux `LogLevel` de Core) | Même couture que `gogRoot`/`resourceURL` : les états de la machine et le journal de l'app ne sont pas des entrées de test — la fonction est contrôlable de bout en bout, drapeau compris |
| Nexus, `SmapiVerdicts` (2026-09-11) | Le tri de `merged` **départage les ex æquo par `UniqueID`**, alors que le code déplacé triait sur le seul nom (casse pliée) | `sorted` n'étant pas stable, deux homonymes changeaient d'ordre d'une vérification à l'autre. La règle est déjà appliquée à `unverifiable` dans la même fonction déplacée, et au cadrage de la liste (lot 3). Testé |
| Nexus, `NexusResume` (2026-09-11) | Le tri de la substitution (`settle`) **départage les ex æquo par `UniqueID`**, même écart que la ligne au-dessus | Second site de la même règle, trouvé dans le même domaine : le code déplacé triait `(kept + found)` sur le seul nom. Testé |
| Nexus, `NexusUpdateCheck` (2026-09-11) | Les lignes de journal de fin de passe partent **toutes ensemble** en tête de complétion ; le code d'origine émettait « passe amputée » **après** `applySmapiResults` (qui journalise ses propres lignes) | Contenu identique, ordre de deux lignes indépendantes : aucune condition n'en dépend, et la lecture gagne un bloc regroupé. Le type a deux coutures : `queue` (la complétion est rendue dessus — `.main` en production) et le `notify` **posé avant le départ des requêtes** (nécessaire aux fetchers synchrones en test, sans effet en production où les fetchs sont asynchrones). Testé |
| Nexus, `NexusUpdateCheck` (2026-09-11) | `dispatch_queue` du cliquet passe 154 → 155 : le paramètre `queue: DispatchQueue` du type | La couture de test du type, même patron que `defaults:`/`resourceURL`/`gogRoot` — un `--update` visible dans le diff l'assume, et verrouille la baisse de `oversized_excess_lines` (26 296 → 26 021) qui accompagnait la tranche |
| Nexus, `NexusCategoryResolver` (2026-09-11) | La récursion du dominant **ne préchauffe plus le cache** de chaque enfant : l'original appelait `category(for:)`, le point d'entrée mémoïsé, si bien que résoudre un en-tête de pack remplissait au passage l'entrée de tous ses composants | Verdict identique, coût négligeable et mesurable de tête plutôt que par campagne : **19 packs à plat** au parc, un enfant non-groupe coûte deux lectures de dictionnaire et un `NexusCategory.from`, et le résultat de l'en-tête reste mémoïsé — la récursion tourne une fois par pack et par génération de cache. Écrit ici parce que le §5 lot 3 désigne nommément `category(for:)` mémoïsé comme le chemin que **F3** met en cause : sans cette ligne, l'écart se retrouve dans six mois sans qu'on sache s'il est voulu |
| Traduction, `TranslationTarget` (2026-09-11) | Le layout d'un dossier `i18n` se décide sur des chemins **résolus** (`resolvingSymlinksInPath`), là où le code déplacé comparait les chaînes brutes | **Correction, pas simple déplacement.** `contentsOfDirectory` rend des URLs dont les liens symboliques sont suivis (`/var/…` → `/private/var/…`) : la comparaison brute concluait « layout B » sur un dossier en layout A et **refusait une traduction légitime**. Sans portée en production — `gameDir` ne passe par aucun lien — mais c'est le premier test en dossier temporaire qui l'a fait apparaître, et le piège `/var` est déjà consigné au CLAUDE.md |
| Traduction, `TranslationTarget` (2026-09-11) | Les messages d'échec sortent en **raison** (`Refusal.reason`), que l'appelant préfixe de son contexte | Patron `NexusResume` : le journal de l'app n'est pas localisé, donc le texte EST la décision. `saveTranslation` compose exactement les mêmes quatre phrases qu'avant ; un second appelant (report de renommage, voir ci-dessous) préfixera les siennes |
| Traduction, `TranslationBatchRun` (2026-09-11) | `hasLocalEngine` est **figé à l'ouverture du lot**, là où `runBatch` relisait `isLocalAIConfigured` au moment de la coupure du secours | Un réglage changé pendant qu'un lot tourne ne déplace plus le point d'arrêt. C'est ce qui fait tenir la règle d'arrêt en Core ; l'écart demanderait d'ouvrir les réglages d'IA locale au milieu d'un lot déjà lancé et de compter sur un quota DeepL épuisé dans la même minute |
| Profils, `ProfileActivation` (2026-09-11) | `gameRunning` arrive en **closure**, là où `applyProfile` appelait `isGameRunning()` dans le fil de ses gardes | Pas un changement de verdict, mais un changement d'**effets**, et c'est pour ça qu'il est écrit : `isGameRunning()` appelle `launchGate.noticeGameRunning()` quand le jeu tourne. Le passer en valeur l'aurait fait consulter à chaque départ et à chaque refus, déplaçant le garde anti double-lancement sans qu'aucune activation soit en jeu. Un test vérifie que la closure n'est **pas** appelée dans ces deux cas |
| Profils, `ProfileRecovery` (2026-09-11) | `gameRunning` arrive en **closure** — second site du patron ci-dessus | Même raison, même preuve : `resumeInterruptedApply` ne consultait le jeu qu'après ses trois premières gardes, et un test vérifie que la closure n'est appelée ni sans journal, ni pendant une application, ni pour un profil supprimé. Écrit séparément parce qu'un lecteur qui ne verrait que la ligne au-dessus croirait le patron limité à l'activation |

### Travail concurrent

Ce dépôt est travaillé par plusieurs sessions et plusieurs modèles. Une extraction
touche `StarHubTHViewModel.swift`, c'est-à-dire le fichier que **toute** autre session
risque de modifier. Deux précautions : annoncer le domaine en cours avant de commencer,
et préférer plusieurs petits commits poussés vite à une grosse extraction gardée
locale — un conflit sur 80 lignes se règle, sur 800 il se subit.

## 7. Ce que ce plan ne fait pas

- **Pas de big-bang.** La roadmap l'exclut explicitement : sans filet de test sur
  l'UI, un refactor massif ne se vérifie pas.
- **Pas de renommage de masse.** Leur phase 6 (balayage de nommage) touche des
  centaines d'appels pour un gain cosmétique ; sans revue automatisée, le rapport
  risque/valeur est mauvais ici.
- **Pas de conversion à la concurrence structurée** (leur phase 5) tant que les
  domaines ne sont pas séparés : `@MainActor` sur un fourre-tout de 4000 lignes
  révélerait des dizaines de problèmes réels d'un coup, sans moyen de les isoler.

## 8. Leurs correctifs pendant le refactor, passés en revue

Une vingtaine de commits `fix:` entre le 2026-07-24 et le 2026-07-27. Le tri
complet est ci-dessous pour que personne ne le refasse. **La majorité est sans
objet** : elle porte sur leur chaîne de build (CI, Xcode 16.2, `XCUIApplication`,
capture d'écran, `App Sandbox`), que nous n'avons pas.

Ce qui nous concernait :

| Leur correctif | Vérification ici | Résultat |
| --- | --- | --- |
| Le bloc de mises à jour SMAPI ne détectait jamais rien (une ligne vide le refermait) | reproduit sur un journal de test, en cassant volontairement la correction | **Présent à l'identique. Corrigé** le 2026-08-01 (`54113eb`) |
| `build_app.py` imprimait `[ERROR]` puis sortait en **0** sur échec de compilation ; leur `run_tests.py` ignorait le code de sortie du binaire de test | épreuve empirique : parité de clés cassée volontairement, puis test délibérément faux | **Sain ici.** `build_app.py` → code 1 ; `run_tests.sh` (`set -euo pipefail` + `swift test`) → code 1 |
| `NSOpenPanel` dans le ViewModel rend ses fonctions intestables (leur 3.4) | `grep` | **Présent** : deux occurrences (`StarHubTHViewModel.swift:2321` et `:8728`, relevées le 2026-09-10). Ce sera le premier besoin de protocole (`FilePicking`) — voir §3 |
| AppKit confiné à un seul fichier non-vue (leur B.2) | `grep` sur les imports | **Non respecté** : `ContrastChecker`, `SaveManager`, `DescriptionBlockParser` et le ViewModel importent Cocoa/AppKit. Les trois premiers sont **déjà dans Core**, où ils compilent — mais c'est une violation de couche à traiter quand on y touchera |
| `bump_version.py` écrivait `Info.plist` avant de valider le CHANGELOG, laissant un état incohérent | lecture de notre flux | **Sans objet** : nous n'avons pas ce script. `release.py` se contente de **lire** `Info.plist`. Le risque n'existe que si un humain bumpe la version sans toucher au CHANGELOG — l'ordre inverse (CHANGELOG d'abord) reste la bonne pratique |
| `CFBundleVersion` figé à 1 depuis la v1.0.0 | lecture d'`Info.plist` | **Sans objet** : incrémenté à chaque release (8 au 2026-08-01) |

Instruits en second passage, après avoir été écartés à tort sur la seule foi de leur
titre — aucun ne s'applique, mais l'un a fait apparaître l'angle mort ci-dessus :

| Leur correctif | Chez nous |
| --- | --- |
| Tests d'intégration qui se sautaient à chaque exécution : `UserDefaults(suiteName:)` rend **nil** quand le nom de suite égale le bundle ID du processus appelant | **Non concernés** : aucune occurrence de `suiteName`. Le piège reste bon à connaître — notre bundle ID est resté `com.appleboiy.StarHubTH` |
| Capture non-`Sendable` dans `continuation.onTermination` de leur surveillance du journal, erreur dure en mode Swift 6 | **Forme différente** : notre surveillance est un `Timer.scheduledTimer` (`BisectionRunner.swift:155`), pas un `AsyncStream` + `DispatchSource`. Mais **nous ne compilons pas en concurrence stricte**, donc l'équivalent chez nous serait invisible — voir P5 au §9 |

**Ce que ce passage en revue apprend, au-delà des correctifs** : leurs bugs les plus
coûteux n'étaient pas dans le code refactoré mais dans **l'outillage qui prétendait
le vérifier** — un script qui sort 0 sur un échec, des tests d'intégration qui se
sautaient silencieusement à chaque exécution. Vérifier que l'outillage échoue bien
quand il doit échouer vaut autant que vérifier le code.

## 9. Leur plan est-il transposable ? — phase par phase

Verdict : **oui pour sept phases sur dix**, mais jamais telle quelle — leurs
coordonnées et leur outillage ne se transposent pas (§3).

| Leur phase | Transposable ? | Chez nous |
| --- | --- | --- |
| **P0 Garde-fous** | **Oui, et déjà fait pour l'essentiel** | Leur 0.3 — « extraire la logique pure en fonctions libres, la tester, *puis* refactorer autour » — est exactement la méthode du §4, appliquée trois fois le 2026-08-01. **Manquent** : un tag `pre-refactor-baseline`, et le compteur d'avertissements de concurrence (`-Xfrontend -warn-concurrency` dans `build_app.py`) qui sert de jalon à leur P5 |
| **P1 Sortir les types des fichiers fourre-tout** | Oui, mécanique | Fait pour `LogEntry`, `ThaiTranslationMod`, `ModUpdateInfo`. **Mais leur table `current → target` vise une arborescence que nous n'avons pas** — voir la question ouverte ci-dessous |
| **P2 Corriger les violations de couche** | Oui, partiellement fait | `LogLevel.color` et les méthodes de `ThaiTranslationMod` prenant le ViewModel : faits. **Restent** : `Mod.Kind` (qui supprimerait les `flatMap { isGroup ? children : [self] }` réécrits trois fois), les identifiants typés (`Mod.ID` / `NexusID` / `FolderName`), et le `uniqueId` vide des groupes (**F4**) |
| **P3 Protocoles et injection** | Oui — **plus urgent chez nous**, et l'écart se creuse | Ils comptaient 26 accès directs à `UserDefaults` ; nous en avions 33 dans le seul ViewModel au 2026-08-01, **52 au 2026-09-10** (hors commentaires ; 73 au `grep` nu). `NSOpenPanel` y est toujours appelé deux fois (`:2321`, `:8728`). Pas besoin de leur `DependencyContainer` : un protocole ici, c'est un fichier de plus dans `Package.swift` |
| **P4 Découper le ViewModel** | Oui — c'est le §6 | Leur ordre vaut, leurs numéros de ligne non |
| **P5 Concurrence structurée** | **Douteux — et angle mort** | Ni `build_app.py` ni `Package.swift` ne passent `-swift-version 6` ou `-strict-concurrency` : **nous ne savons pas combien de problèmes existent**, faute de les avoir jamais fait compter (leur 0.4 sert à ça). À ne pas ouvrir avant que les domaines soient séparés — `@MainActor` sur un fourre-tout de 4000 lignes en révélerait des dizaines d'un coup, sans moyen de les isoler. **Première étape, peu coûteuse : mesurer** en ajoutant l'avertissement, sans rien corriger |
| **P6 Balayage de nommage** | **Non** | Des centaines d'appels touchés pour un gain cosmétique, sans revue automatisée. Écarté (§7) |
| **P7 Erreurs typées** | Oui | **Swift 6.3.3** ici : `throws(E)` est disponible. Ce qui les a mordus (une CI sur Xcode 15.4) ne nous concerne pas |
| **P8 Découpage des vues** | Oui — **et ça manquait à ce plan** | Ils visent ~150 lignes par vue. Chez nous, au 2026-09-10 : `ModListView` **2340**, `ModDetailView` **2145**, `MainView` **1536**, `SavesView` **1162**, `LogsView` 746. À traiter au contact, en même temps que le domaine correspondant |
| **P9 Verrouiller** | Oui — **et ça manquait aussi** | Leur `check_standards.py` empêche la dette de revenir. L'équivalent ici est bon marché : un contrôle dans `build_app.py` refusant qu'un fichier de `Models/` importe SwiftUI, sur le modèle du contrôle de parité des clés qui existe déjà |

### Arborescence — tranché le 2026-08-01 : un dossier `Stores/`

**Décision** : les stores extraits vont dans `StarHubTH/Stores/`, à côté de `Models/`
et `Views/`. Additif, aucun déplacement, `build_app.py` compile déjà `StarHubTH/`
récursivement. Réversible : adopter leur arborescence complète plus tard reste
possible si `Stores/` devient illisible.

**Pourquoi pas leur arborescence tout de suite** : leur meilleure idée — rendre une
violation de couche visible dans le chemin du fichier — est déjà obtenue autrement ici,
et plus solidement. Ce qui est dans `StarHubTHCore` ne peut pas importer SwiftUI, et
c'est le **compilateur** qui le vérifie, pas une convention de nommage. Déplacer des
dizaines de fichiers pour gagner une convention plus faible que la contrainte existante
serait un mauvais échange.

Le détail de leur découpage, pour mémoire — Leur arborescence est `App/`, `Features/<Domaine>/`, `Services/<Domaine>/`, `Models/`,
`DesignSystem/`, `Localization/`, `Support/`. Nous avons `Models/`, `Views/`, et la
racine. **Ce plan ne tranche pas** où vivront les stores extraits au §6.

Deux voies, à choisir une fois pour toutes plutôt qu'au coup par coup :

1. **Adopter leur arborescence.** Une violation de couche devient visible dans le
   chemin du fichier, ce qui est leur meilleure idée. Coût : `build_app.py` compile
   déjà tout `StarHubTH/` récursivement, donc **aucun changement de build** — mais
   beaucoup de fichiers déplacés en une fois, et des commits de déplacement pur qui
   brouillent l'historique récent.
2. **Un seul dossier `Stores/`** à côté de `Models/` et `Views/`, sans toucher au
   reste. Moins expressif, mais additif et sans déplacement.

*(C'est la voie 2 qui a été retenue, cf. la décision ci-dessus.)*
