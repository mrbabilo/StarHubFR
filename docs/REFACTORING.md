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

**Non classés, et pourquoi** : Nexus (~2 000 l.) et Traduction FR (~2 190 l.) sont les
deux plus gros domaines, mais ce sont aussi les deux plus enchevêtrés avec le réseau et
le disque — les ouvrir en premier ferait porter le premier protocole *et* le premier
gros déplacement par le même commit. Ils viennent après que la recette a été éprouvée
sur les points 1 à 3.

**Deux chantiers transverses, repris de leurs phases 8 et 9** — absents de la
première version de ce plan :

| Chantier | Quand | Pourquoi ici |
| --- | --- | --- |
| **Découper les vues** (leur P8, cible ~150 lignes) | **Au contact** : quand on extrait un domaine, on découpe la vue qui le consomme, dans le même mouvement | Au 2026-09-10 : `ModListView` **2340** lignes, `ModDetailView` **2145**, `MainView` **1536**, `SavesView` **1162**, `LogsView` 746 — la même pente que le ViewModel (`ModDetailView` a triplé depuis le relevé de 683). Une campagne dédiée serait un big-bang sans filet ; couplé à l'extraction, le découpage a une raison d'être et un périmètre |
| **Verrouiller les règles** (leur P9) | **Dès que le premier store existe** | Leur `check_standards.py` empêche la dette de revenir. L'équivalent ici est bon marché : un contrôle dans `build_app.py` refusant qu'un fichier de `Models/` importe SwiftUI — même forme que le contrôle de parité des clés qui existe déjà, et qui sort en `SystemExit(1)` |

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
| **Détail de mod** | `loadModDetail`, `fetchModDetailRemote`, `markDetailNotLoading` | Réseau Nexus ; rejoint le domaine Nexus déjà identifié |

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
