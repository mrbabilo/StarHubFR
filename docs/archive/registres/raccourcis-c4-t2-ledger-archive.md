# Archive du ledger SDD — raccourcis-c4-t2-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-28-raccourcis-c4-t2/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-28-raccourcis-c4-t2.md`.

2026-08-28-raccourcis-c4-t2.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-28-raccourcis-c4-t2.md

Spec : docs/superpowers/specs/2026-08-28-raccourcis-c4-t2-design.md (lisible,
autorité — ses constats de mesure §6 font autorité sur le plan). Branche :
`main`, convention du dépôt (CLAUDE.md) et consentement de session (même
choix que le plan H-T2/T3). Pas de worktree.

## Scan de pré-vol

### Paires de tâches partageant un fichier ou une interface

| A → B | Produit / consommé | Constat |
|---|---|---|
| T0 → T1 | `sbutton.swift` (190 entrées) + `keyboardValues` à coller | Cohérent : les steps de T0 produisent exactement ce que T1 step 4 demande de coller. |
| T0 → T2 | relevés contrôles (step 3) + constat de mesure (step 5) | Cohérent : T2 step 1 exige la lecture du constat avant d'ajuster les tests R1-R3. |
| T0 → T4 | volume du rapport → liste plate ou DisclosureGroup | Cohérent : la décision est explicitement reportée à T0, T4 step 2 la porte. |
| T1 → T2 | `KeybindParser.parse`, `KeybindCombo`, `SButtonTable` | Cohérent : signatures identiques des deux côtés (vérifiées à l'écriture du plan). |
| T2 → T3 | `KeybindScanner.ModScan` / `.report` | Cohérent. |
| T3 → T4 | `KeybindScanService` (`scan(mods:gameDir:)`, `report`, `isScanning`) | Cohérent : la vue appelle exactement ça. |
| T1 ↔ T2 | `Package.swift` | Régions disjointes (liste target vs nouveau testTarget) ; dispatch séquentiel. |
| T4 ↔ rien | `MainView.swift` une ligne dans `SystemAlertsView` | Aucune autre tâche ne touche ce fichier. |

### Cohérence interne de chaque tâche

| Tâche | Constat |
|---|---|
| T0 | Sans commit **par design** (jetable + spec gitignorée). Livrables = constat + données collables. |
| T1 | Tests ↔ impl d'accord ; RED = échec de compilation (le type n'existe pas) — accepté pour un nouveau module. `KeybindCombo(buttons:)` failable utilisé partout. |
| T2 | Le test `gameControlConflictOnlyForSingleButtonCombos` suppose `W` dans les défauts (moveUp) — donnée T0 à vérifier avant GREEN ; si le relevé dit autre chose, le test s'ajuste au relevé (le relevé est la mesure). |
| T3 | Échappatoire Sendable prévue dans le brief ; signature `ConfigJSONTree.parse` à vérifier avant écriture — dans le brief. |
| T4 | Vue complète dans le brief ; `id: \.self` exige Hashable — déclaré en T2 (interfaces à jour). `.strings` régénérés au commit. |
| T5 | Docs purs, gate final complet. |

### Ce que le plan mandate et qu'une revue pourrait prendre pour un défaut

| Point | Ruling préventif |
|---|---|
| T0 ne committe rien | Ruling P1 — voulu par le plan (« jetable, sans commit ») ; les livrables vivent dans la spec (gitignorée) et les commits de T1/T2 portent les données. |
| Test T2 dur par défaut (`W`) | Ruling P2 — le défaut `W = moveUp` est un fait mesurable du constructeur d'Options ; si le relevé T0 le dément, le test s'ajuste AU relevé, pas à la commodité. |
| `vm.L` nouveaux → cliquet | Ruling P3 — hausse délibérée, `--update` explicite exigé par le plan (CLAUDE.md le prévoit). |

## Rulings

## Progression
Task 0: DONE (rapport reçu 2026-08-28 23:41) — 190 SButton reproduits,
  Keys ⊂ SButton (160 clavier), 28 champs InputButton[] lus (P2 confirmé :
  moveUpButton=[W]), parc : 545 config.json (92 actifs), R2 rédigé = 72 % FP
  → règle gelée numériques exclus = 0 % FP, unrecognized durci = 0 entrée,
  18 collisions exact-combo, 11 contrôles / 18 entrées jeu, combo max
  3 boutons, verdict volume liste plate (29 lignes affichées ; plafond 51
  si parc réactivé).
Task 0: note — le plan T2 est patché avec la règle gelée (classify durci :
  origine numérique jamais R2 ; unrecognized exige un jeton reconnaissable)
  + 2 tests encodeurs, AVANT dispatch de T2, comme l'exige la contrainte
  globale du plan.
Task 0: incident — le premier relecteur est mort en 429 (quota 5 h épuisé,
  reset 06:27) ; redispatché le 2026-08-29 10:13.
Task 0: review (redispatché, 2026-08-29 10:21) — tous les nombres reproduits
  indépendamment par le relecteur (545/92/453/1 ; 18 collisions ; plafond 51
  rejoué). Verdict : Needs fixes. Important : (1) « 28 champs » faux → 27
  réels, gamecontrol.swift a 26 entrées (tmpKeyToReplace probablement écarté
  à juste titre — à rendre explicite) ; (2) la règle gelée omet les tableaux
  numériques ([34,95] RGB passerait R2). Minor : provenance unrec 0 mal
  attribuée ; plafond 51 sans artefact ; entier 0 → combo {"None"} (latent,
  côté T1).
Task 0: fix round 1/5 — contrôleur : plan T1 patché (entier 0 → combo vide,
  « None + F8 » → nil, tests ajoutés) ; implémenteur : 27 partout, clause
  tableaux numériques dans la spec, provenance, artefact measure-all.out.
Task 0: fix round 1/5 (5 addressed, 0 open — relecteur a re-dérivé 27
  déclarations IL, 50/51 collisions delta = fantôme B de CollectionsMod,
  unrec durci imprimé par le pipeline).
Task 0: complete (tâche de mesure, sans commit — livrables : spec §6 constat
  + /tmp/c4t2/* ; revue propre après 1 ronde)
Task 0: minor (deferred): rapport:151 porte encore « plafond 51 » obsolète
  (la spec dit 50) — une ligne au prochain passage dans ce fichier.
Task 0: minor (deferred): décalage de citation defaults.txt:13→17-18 dans le
  rapport ; en-tête measure2.py sans la clause listes (script jetable, la
  spec est l'autorité).
Task 0: Ruling — collage gamecontrol.swift : lignes positionnelles
  (name, buttons) sous étiquette `control:` ; T2 colle dans
  GameControl(name:buttons:) — renommage d'étiquette à la pose, sans autre
  friction. Porté au dispatch de T2.
Task 1: complete (commits 1c4795e..04d90d8, review clean — Approved,
  spec conforme, 190/160 re-vérifiés byte-exact par le relecteur)
Task 1: minor (deferred): pas de test du tableau MIXTE chaînes+entiers
  (couvre tout-chaînes et tout-entiers ; le code le gère par lecture).
Task 1: minor (deferred): un token « + » seul parse en combo vide au lieu
  de nil — dégénéré, hérité du canevas.
Task 1: Ruling — 4 déviations au canevas validées par la revue (Comparable,
  deux « ! », CRLF un seul caractère — le piège documenté du dépôt attrapé
  par le test du plan —, chaîne vide → nil) : le TDD a joué son rôle.
Task 2: Ruling — trailer. L'implémenteur s'est signé « Claude Haiku 4.5 »
  contre l'instruction ; l'erreur 429 du 2026-08-28 a montré le modèle
  réellement envoyé à l'API : glm-5.3. CLAUDE.md : le modèle actif est GLM
  quel que soit l'alias affiché. Trailer corrigé par amend du contrôleur
  (bf5f9b2 → b2260d4, non poussé, code inchangé).
  *Coût si faux* : un trailer mentionnant un modèle qui n'a pas écrit le
  commit — exactement ce que CLAUDE.md interdit dans l'autre sens.
Task 2: complete (commits 04d90d8..b2260d4 [amend trailer, ruling ci-dessus],
  review clean — Approved ; 15 tests, 26 contrôles vérifiés contre l'artefact)
Task 2: minor (deferred): liste non hintée « K, MouseLeft » — le combo non
  distinctif K entre à l'index (comportement du canevas gelé, non épinglé
  par test).
Task 2: minor (deferred): literal(of:) rend « ? » pour un unrecognized
  tableau (scalaires couverts).
Task 2: minor (deferred): tri des uses par modName seul — modID en
  départagerait deux homonymes (déterminisme repose sur la stabilité du
  tri Swift).
Task 3: review (11:18) — Approved partout sauf 1 Important : id: mod.name
  fusionne les homonymes dans la dédup (Set(modID) >= 2), collision manquée
  sur un parc à doublons documentés. Arbitrage : id = folderName (l'identité
  de ModItem, clé du registre, stable à la pause) ; uniqueId exclu (111 mods
  sans → chaînes vides fusionneraient). Défaut du canevas du plan (corrigé
  dans le plan pour le record).
Task 3: fix round 1/5 lancée — amend de 5a9a105, id: mod.folderName.
Task 3: fix round 1/5 (1 addressed, 0 open — folderName vérifié Identifiable,
  jamais pointé, chemin pour composants ; « chemisé » dans le commentaire :
  cosmétique, laissé)
Task 3: complete (commit b2260d4..89b02a1 [amend], review clean après
  1 ronde)
Task 3.5 (hors plan, contrôleur, avant reprise SDD) : deux défauts vus à la
  relecture du Core avant d'écrire la vue, corrigés en TDD dans 7739d28
  (1680/1680). Ruling : (a) `report()` dédupliquait pas les usages — « F8, F8 »
  rend deux combos identiques, le même ModUse entrait deux fois dans le seau
  et la vue aurait reçu deux lignes de même identité (`ForEach id: \.self`) ;
  corrigé côté Core avec test, pas dans la vue. (b) `KeybindScanService.scan`
  ne gardait pas `gameDir` vide : les chemins auraient été bâtis sur « » et le
  rapport serait revenu à 0 conflit — un vert mensonger.
  *Coût si faux* : correctifs écrits par le contrôleur, donc non passés par la
  boucle de revue de tâche ; la revue T4 et la revue finale les voient dans le
  diff de branche.
Task 4: Ruling A — groupes repliés (DisclosureGroup) et non liste plate.
  Le plan renvoie la décision à T0 ; T0 mesure 29 lignes sur le profil courant
  MAIS 50 collisions plafond parc réactivé, au-dessus du seuil de 40 qu'il
  pose lui-même. Réactiver des mods est ce que l'app sert à faire : on prend
  l'option défensive, dépliée quand la section est petite.
  *Coût si faux* : un clic de plus pour voir 18 collisions sur ce profil.
Task 4: Ruling B — 12 clés au lieu des 10 du plan. Le vert « aucun conflit »
  ne doit sortir que si quelque chose a été scanné : deux états neufs, dossier
  de jeu absent et aucun mod actif porteur de config.json.
  *Coût si faux* : deux clés de trop dans les deux locales.
Task 4: Ruling C — `.onAppear` conditionnel (`report == nil`). Le changement
  d'onglet détruit le `@StateObject` (piège documenté du dépôt) : sans garde,
  545 config.json relus à chaque retour sur l'onglet. « Relancer l'analyse »
  reste le seul rafraîchissement.
  *Coût si faux* : rapport périmé après activation d'un mod, jusqu'au clic.
Task 4: Ruling D — les trois en-têtes de section portent leur compte, donc
  format `%lld` au lieu du texte nu du plan (exigé par les libellés de
  DisclosureGroup, conséquence du Ruling A).
  *Coût si faux* : formulation d'en-tête à retoucher.
Task 4: Ruling E — espacements/paddings via `AppDesign.Spacing` (posé par
  H-T1, employé dans Views/Components/), tailles de police du canevas gardées,
  aucun token neuf. `SystemAlertsView` est encore en valeurs brutes et H doit
  la reskinner.
  *Coût si faux* : friction mineure au reskin de H.
Task 4: dispatché (implémenteur Sonnet, BASE 7739d28) avec les rulings A–E
  portés dans le brief de dispatch. Build attendu 8–12 min.
Task 4: implémenteur DONE (commit 873f9b9, 1680/1680, build EXIT=0 après
  `check_standards.py --update` — cliquet relevé de +12 `vm.L` et +21 `vm`,
  baseline dans le commit). Doute remonté par l'implémenteur : les noms de
  contrôles du jeu s'affichent bruts (`moveUpButton`, `inventorySlot11`) —
  comportement du canevas, à trancher par le contrôleur si la revue ne le
  relève pas.
Task 4: revue dispatchée (Opus, 7739d28..873f9b9). Ce code de vue n'a aucun
  gate automatique : la revue est le seul filet avant l'écran.
Task 4: revue (11:53) — Corrections nécessaires. Conformité formelle propre
  et vérifiée (parité 12/12 dans les 4 fichiers de locale, clés toutes
  câblées et utilisées, une seule ligne dans MainView, tokens exacts,
  cliquet délibéré). 4 Importants, 4 Mineurs.
Task 4: Ruling F (constat 1, *contre mon propre Ruling C*) — le relecteur a
  raison : `SystemAlertsView` vit dans une chaîne `if/else if` d'un `Group`,
  donc le `@StateObject` est recréé à chaque retour d'onglet, donc `report`
  est toujours `nil` à l'entrée et la garde ne garde rien — pire, son
  commentaire proclame l'inverse. On corrige la cause, pas le commentaire :
  le service devient une propriété du `StarHubTHViewModel` (même acteur
  principal), la vue l'observe. La garde retrouve alors son sens et le
  rapport survit au changement d'onglet.
  *Coût si faux* : une propriété de plus sur un ViewModel déjà gros ; repli
  prévu = commentaire honnête si l'implémenteur bute.
Task 4: Ruling G (constat 2) — le vert « aucun conflit » disparaît dès que
  `unrecognized` n'est pas vide. Affirmer l'absence de conflit sur un lot
  dont on vient d'admettre N entrées illisibles, c'est le vert mensonger que
  le Ruling B visait ; B n'avait couvert que « rien n'a été scanné ».
  *Coût si faux* : un profil sans conflit mais avec un keybind malformé perd
  sa coche verte — il garde ses compteurs.
Task 4: Ruling H (constat 3) — la réserve « contrôles par défaut » sort du
  `DisclosureGroup`. Conséquence non vue du Ruling A : replié au-delà de 10,
  l'utilisateur lit « Conflits avec les contrôles du jeu (26) » sans savoir
  que la comparaison porte sur les défauts — la phrase qui évite la fausse
  alerte chez qui a remappé son clavier.
Task 4: Ruling I (constat 4, imposé par le plan) — la ligne d'un conflit jeu
  porte désormais la ou les touches en cause (`GameControl.buttons`, déjà
  sur la structure rendue), le nom de champ restant en second. Le groupe des
  collisions montre son combo ; celui-ci n'en montrait aucun, et
  « inventorySlot11 » n'est actionnable pour personne. Traduire les 27 noms
  de contrôles en 27 clés × 2 locales est un chantier à part : porté en
  point ouvert du constat T5, pas fait ici.
  *Coût si faux* : une ligne encore technique là où un libellé français
  complet serait mieux.
Task 4: Ruling J — le Mineur 7 (en-tête non borné en fenêtre étroite) entre
  dans la ronde de correction malgré la règle « les mineurs n'entrent pas
  dans la boucle » : c'est exactement la classe de défaut que l'utilisateur
  a renvoyée trois fois à l'écran, et il coûte une ligne. Les mineurs 5, 6
  et 8 restent différés.
Task 4: minor (deferred): 5 — si `gameDir` passe de vide à renseigné pendant
  que la vue reste montée, la section n'affiche plus que son en-tête
  (`.onChange(of:)` fermerait le trou) ; peu atteignable, récupérable au
  bouton.
Task 4: minor (deferred): 6 — `.foregroundColor(.primary)` neutralise
  l'atténuation du bouton désactivé ; il paraît cliquable sans dossier de
  jeu.
Task 4: minor (deferred): 8 — un groupe basculé à la main garde son état
  pour la vie de la vue, même si un rescan fait passer de 3 à 60 collisions.
Task 4: fix round 1/5 lancée (implémenteur d'origine repris, FIX_BASE
  873f9b9) — 5 constats envoyés : possession du service par le ViewModel
  (F), vert supprimé si `unrecognized` non vide (G), réserve hors du pli
  (H), touches affichées sur les conflits jeu (I), en-tête borné (J).
Task 4: fix round 1/5 — implémenteur DONE (commit 54c4584, 1680/1680,
  build EXIT=0, cliquet +4 `abbreviation_vm`). Cause du constat 1 corrigée
  sans repli : service porté par `StarHubTHViewModel.keybindScanService`
  (patron `smapiInstaller`), observé en `@ObservedObject`. Doute signalé
  par l'implémenteur : `nonisolated init() {}` ajouté à `KeybindScanService`
  pour construire une classe `@MainActor` depuis une classe non isolée
  (patron `BisectionRunner.init(vm:)`) — pointé à la re-revue, le dépôt a un
  historique de pièges de concurrence Swift.
Task 4: re-revue scopée dispatchée (Opus, 873f9b9..54c4584).
Task 4: fix round 1/5 (5 addressed, 0 open — mais 1 Important neuf + 1
  Mineur neufs dans le diff de correction). `nonisolated init()` validé par
  la re-revue : n'assigne que des valeurs par défaut Sendable, patron
  `BisectionRunner`, aucun cycle de rétention (le service ne tient pas le
  ViewModel), le `Task` de `scan` est même plus sûr qu'avant. Cliquet
  re-dérivé à l'identique par le relecteur (2275 / 1201), build lancé non
  pipé.
Task 4: Ruling K (casse neuve, `" + "` sur des touches alternatives) —
  correction retenue : `" / "`. `GameControlDefaults` liste des touches
  *équivalentes* (`actionButton ["X","MouseRight"]`), pas un accord ; le
  scan n'en a matché qu'une. Or `" + "` signifie un accord quarante pixels
  plus haut, dans le groupe des collisions (`KeybindCombo.display`) — deux
  sens opposés pour une même notation sur le même panneau, et sur les quatre
  contrôles les plus disputés. Montrer la touche exacte est impossible dans
  le périmètre : `GameControlConflict` ne porte pas le bouton matché.
Task 4: Ruling L (observation hors périmètre du relecteur, retenue quand
  même) — depuis que le service vit sur le ViewModel, le scan n'a plus lieu
  qu'une fois pour la vie de l'app : qui active un mod et revient sur
  Alertes système lit un rapport calculé contre l'ancien parc, sans que rien
  ne le signale. C'est mon Ruling F qui a changé le sens du Ruling C. La
  correction reste dans le service : une signature du parc scanné, et un
  `scanIfNeeded` qui rescanne quand elle a changé.
  *Coût si faux* : un rescan de plus quand le parc bouge — exactement le
  comportement d'avant, mais seulement quand il a bougé.
Task 4: minor (deferred): l'état plié/déplié des trois groupes repart à ses
  valeurs par défaut à chaque changement d'onglet (`@State expanded`), alors
  que le rapport, lui, survit désormais.
Task 4: fix round 2/5 lancée (FIX_BASE 54c4584) — `" / "`, bloc de
  commentaire dupliqué au ViewModel, et `scanIfNeeded`.
Task 4: fix round 2/5 (3 addressed, 0 open, aucune casse neuve — signature
  vérifiée stable : `flattenedMods` est un flatMap sur Array, aucun hashValue
  de Set en jeu ; retenue seulement quand le scan part).
Task 4: complete (commits 7739d28..fcf53a5, review clean après 2 rondes)
Task 4: minor (deferred): la logique de signature reste hors `swift test`
  (méthodes privées de `KeybindScanService`, @MainActor) — sa panne serait
  silencieuse ; candidate à un type pur en Core.

## Mesure sur le parc réel (contrôleur, 12:25) — le vrai scanner, pas un
## portage Python

Test jetable branché sur `KeybindScanner.report` et le vrai `Mods/` :
545 candidats, 92 actifs, 453 en pause, 183 raccourcis lus,
**29 collisions**, **20 conflits jeu**, 0 non reconnu.

⚠️ La tâche 0 annonçait 18 collisions et 11 contrôles : son `measure.py` ne
descendait pas dans les **tableaux d'objets**, alors que
`ConfigEditorModel.collect` le fait (`path + ["[i]"]`). Sans le Hub, le vrai
scanner donne 17 collisions — d'où la concordance trompeuse avec les 18 de
T0. Les chiffres du constat ROADMAP doivent être ceux-ci, pas ceux de T0.
Le verdict de volume (groupes repliés) n'en est que mieux justifié.

Retour utilisateur du 2026-08-29 12:19, cinq points :
 1. `ModShortcutReferenceHub` (ZeroXPatch, actif) est un **catalogue** de
    raccourcis, pas un consommateur : son config.json déclare
    `Shortcuts[i].KeyCombo` pour tout l'alphabet — **42 combos distincts**,
    2,6× le suivant (ItemBags, 16). Il pèse **12 des 29 collisions** et
    **9 des 20 conflits jeu**. Mesuré, pas supposé.
 2. Ni la pastille « Alertes système » ni l'accueil ne comptent les
    problèmes de raccourcis — la section est invisible tant qu'on n'ouvre
    pas l'onglet.
 3. Les conflits sont signalés sans aucun chemin vers la config du mod.
 4. La fiche détaillée d'un mod n'a pas de bouton vers sa config.
 5. La fiche détaillée ne dit rien des problèmes de raccourcis du mod.
Défaut trouvé en passant : un mod qui lie la même touche dans deux réglages
s'affiche deux fois sur la même ligne (`ItemBags | ItemBags`,
`ChestsAnywhere | ChestsAnywhere`, `Hub | Hub`) — dédup par (modID, keyPath),
donc légitime côté données, bruit côté écran.
Task 6: Ruling M — la règle du catalogue, **mesurée avant d'être écrite**.
  Exclure `ModShortcutReferenceHub` en bloc serait faux : son
  `OpenMenuKey = "K"` est une vraie liaison, en vrai conflit avec Swim.
  C'est son tableau `Shortcuts[]` (42 entrées `KeyCombo`/`Description`/
  `IsCustom`, 10 marquées IsCustom) qui documente les autres mods.
  Mesure sur les 92 mods actifs, forme de chemin = chemin dont chaque indice
  de tableau est réduit à `[]` : 142 formes au total, la plus fournie après
  le Hub en porte **2** (`ChestsAnywhere.Controls.NextChest`,
  `ItemBags.GamepadSettings.*`, `Swim.DiveKey` — des alternatives légitimes
  dans un seul champ). Le Hub : **42**. Marge de 20×.
  Règle retenue : plus de **8 combos distincts sous une même forme de
  chemin, dans un même mod** ⇒ cette forme est un catalogue, ses feuilles ne
  sont pas des liaisons. Aucun UniqueID en dur, aucune liste noire.
  *Coût si faux* : un mod qui lierait réellement plus de 8 touches sous un
  même tableau verrait ce tableau ignoré — aucun cas dans le parc, et le
  seuil est 4× l'observé.
Task 6: implémenteur DONE (commit eb0ca52, 1684/1684, build EXIT=0, cliquet
  +1/+1). Parc réel : collisions 29 → 18, conflits jeu 20 → 11, raccourcis
  lus 183 → 141 (−42, exactement le catalogue). `catalogModsIgnored =
  ["ModShortcutReferenceHub"]`. L'implémenteur signale deux corrections
  faites avant commit : numéral redondant retiré d'une chaîne, et la logique
  de regroupement par mod déplacée de la vue vers Core
  (`KeybindScanner.groupedUses`) avec test.
Task 6: revue dispatchée (Opus, fcf53a5..eb0ca52).
Task 7/8/9: briefs écrits par le contrôleur (le plan ne les portait pas —
  ils viennent du retour utilisateur). Décisions posées dans les briefs :
  - T7 Ruling N : les conflits de raccourcis se fondent dans le compteur
    « alertes » existant (pastille latérale + tuile d'accueil), pas de
    cinquième chiffre ni de nouvel item — les deux mènent déjà à la page qui
    les porte. Compte = collisions + conflits jeu, les non reconnus exclus
    (illisibles ≠ problèmes avérés). Scan déclenché depuis le `didSet` de
    `mods` (précédent : `recomputeFrenchCoverage`), la signature rendant
    l'appel répété sans coût.
    *Coût si faux* : un compteur « alertes » qui agrège deux natures de
    problème vers la même page.
  - T8 Ruling O : la navigation inter-onglets passe par le patron
    `pendingTranslationFocus` (champ d'intention consommé DANS le
    `onChange(of: currentTab)`, après la remise à zéro) — le seul qui marche
    ici, l'ordre inverse ayant déjà échoué et été documenté dans le code.
  - T9 Ruling P : zéro conflit ⇒ rien à l'écran sur une fiche de mod (une
    ligne verte sur 900 fiches serait du bruit), et aucun rapport ⇒ muet
    plutôt que « aucun conflit » — l'inverse de la règle du rapport global,
    où le vert répond à une question posée.
Task 6: revue (12:50) — Corrections nécessaires. Règle validée sur les
  quatre points de vigilance (portée par mod vérifiée à la ligne de
  déclaration de `combosByShape` dans la boucle, Set de combos donc valeurs
  distinctes, seuil 8 reste / 9 tombe, `pathShape` n'écrase que des segments
  entiers `^\[\d+\]$` donc le champ terminal survit). Déplacement de
  `groupedUses` en Core salué comme le bon arbitrage. 1 Important : la
  phrase d'exclusion.
Task 6: Ruling Q — la phrase d'exclusion est refaite, logique inchangée. Elle
  disait « pas de vraies liaisons » d'un mod dont la collision K avec Swim
  s'affiche quelques lignes plus haut : la règle écarte une *forme de
  chemin*, pas un mod. Et son pluriel était faux dans le seul cas réel
  (count == 1). Nouvelle forme : « Documentation de raccourcis écartée du
  scan (%1$lld) : %2$@ » — nom de masse (juste aux deux nombres), compte en
  tête pour survivre à la troncature au milieu que la vue applique.
Task 6: fix round 1/5 lancée (FIX_BASE eb0ca52) — la chaîne, plus 3 mineurs
  entrés par arbitrage : dédup des catalogues sur l'identité et non le nom
  (Swim est installé deux fois sur ce parc), purge des feuilles de catalogue
  hors de `unrecognized`, et deux tests verrouillant occurrences ≠ valeurs
  distinctes et la non-fusion de deux champs sous un même tableau.
Task 6: fix round 1/5 — implémenteur DONE (commit e5a70f8, 1688/1688, build
  EXIT=0, cliquet inchangé, nombres de parc inchangés). Re-revue dispatchée
  (Sonnet, eb0ca52..e5a70f8).
Task 7: dispatché (implémenteur Sonnet, BASE e5a70f8) en parallèle de la
  re-revue T6 — fichiers disjoints (T7 : MainView/HomeView/ViewModel ;
  correction T6 : KeybindScanner + locales + section). Le relecteur est
  prévenu de ne pas rejouer de git.
Task 6: fix round 1/5 (4 addressed, 0 open, aucune casse neuve — le
  relecteur a vérifié que chaque test neuf échouerait sous l'ancien code,
  donc non tautologique, et que la typographie française du deux-points suit
  la convention déjà en usage dans assets/fr.json).
Task 6: complete (commits fcf53a5..e5a70f8, review clean après 1 ronde)
Task 7: implémenteur DONE (commit d970fb0, 1689/1689, build EXIT=0, cliquet
  `abbreviation_vm` 2276→2283 relevé délibérément). Revue dispatchée (Opus,
  e5a70f8..d970fb0), avec un point de vigilance ajouté par le contrôleur :
  après ce commit l'analyseur signale sur HomeView.swift:77 « unable to
  type-check this expression in reasonable time » — le build passe, mais
  l'expression a pu s'alourdir.
Task 8: dispatché (implémenteur Sonnet, BASE d970fb0) en parallèle de la
  revue T7.
Reprise de session (15:55) : la revue T7 et l'implémenteur T8, dispatchés à
13:11, sont morts avec la session sans rendre de résultat (aucun commit après
d970fb0, arbre propre, pas de rapport T8). Les deux sont re-dispatchés à
l'identique : revue T7 sur fichier de diff (Opus), implémenteur T8 (Sonnet,
BASE d970fb0).
Task 7: revue (16:06) — Approved. Spec ✅ sur les 4 exigences et les 5
  décisions du Ruling N ; les 5 risques nommés vérifiés hors diff
  (@Published report, garde avant signature, ordre init/performInitialLoad,
  arithmétique des tests corrigée en 4+1, HomeView:77). Zéro Critical,
  zéro Important.
Task 7: ⚠️ résolu par le contrôleur : trailer d970fb0 = Claude Sonnet 5
  (l'implémenteur), pas de push (11 d'avance) — conforme.
Task 7: minor (deferred): somme `smapiErrors.count + keybindProblemCount`
  dupliquée MainView/HomeView — une propriété ViewModel centraliserait.
Task 7: minor (deferred): fenêtre de course héritée — mods mute pendant un
  scan ⇒ dernier état non rescanné jusqu'à prochaine mutation/onAppear
  (sémantique préexistante du service).
Task 7: minor (deferred): prose du rapport T7 disait « +5 tests » (c'est 4 ;
  total 1689 juste).
Task 7: minor (deferred): HomeView.swift:77 — extraire le Button par compteur
  en sous-vue privée pour désengorger attentionStrip (type-checker limite).
Task 7: complete (commits e5a70f8..d970fb0, review clean)
Task 8: implémenteur DONE (commit c443bfa, 1689/1689, build EXIT=0, cliquet
  relevé explicitement — 3 compteurs, conventions maison). Bouton
  « Réglages du mod » dans actionRow (prédicat liste repris verbatim),
  engrenage 18×18 sur les lignes du rapport via vm.pendingConfigFocus
  (patron pendingTranslationFocus consommé dans le onChange). Zéro clé L10n
  neuve (réutilisation config_mod_settings).
Task 8: Ruling R — le trailer GLM 5.3 de c443bfa est correct, pas d'amendement.
  La session route via glm.sh : l'alias « sonnet » du sous-agent est servi par
  GLM 5.3, cas documenté dans CLAUDE.md et précédent établi sur T2 ce matin.
Task 8: Ruling S — T9 attend le verdict de la revue T8 avant d'être dispatché.
  T8 et T9 partagent ModDetailView (+ ViewModel possible) : une ronde de fix
  T8 ne doit jamais s'entremêler avec l'écriture T9, et le brief T9 réutilise
  le chemin T8 — si la revue y trouve un défaut, T9 le répliquerait.
  *Coût si faux* : ~30 min de sérialisation supplémentaires.
Task 8: revue dispatchée (Opus, d970fb0..c443bfa).
Task 8: revue (16:25) — Approved. Spec ✅ sur toutes les exigences du brief
  (prédicat repris verbatim vérifié hors diff contre ModListView:1655,
  patron pendingConfigFocus conforme au Ruling O au pixel près, retrait
  folderName qui ne bascule l'onglet que si trouvé, 18×18 + contentShape,
  fixedSize+layoutPriority pour le non-débordement, réutilisation L10n
  réelle vérifiée dans les deux locales, style des voisins repris). Zéro
  Critical, zéro Important.
Task 8: ⚠️ résolus par le contrôleur : preuves tests/build lues dans le
  rapport (EXIT=0) ; vérification écran = l'utilisateur, scénarios fournis.
Task 8: minor (deferred): vm.L(configModSettings) évalué deux fois par
  ligne (.help + accessibilityLabel) — KeybindReportSection.swift:229-230.
Task 8: minor (deferred): .fixedSize() redondant avec frame 18×18 +
  layoutPriority — KeybindReportSection.swift:232.
Task 8: complete (commits d970fb0..c443bfa, review clean)
Task 9: dispatché (implémenteur Sonnet, BASE c443bfa) — dernier point du
  retour utilisateur ; TDD sur la sélection Core, zone lecture seule sur
  ModDetailView, réutilisation du chemin openModConfig(forFolder:) de T8.
Task 9: implémenteur DONE (commit cfe2184, 1692/1692 — les 3 tests du
  brief, build EXIT=0, cliquet relevé explicitement abbreviation_vm +8 /
  vm_dot_L_calls +4). KeybindReport.conflicts(affecting:) en Core, zone
  lecture seule sur ModDetailView muette sans rapport comme sans conflit,
  zéro clé L10n neuve.
Task 9: revue dispatchée (Opus, c443bfa..cfe2184). Point de vigilance
  transmis sans verdict : le rapport documente que la zone ne porte pas de
  bouton propre (sur la fiche on est déjà dans l'onglet Mods ;
  openModConfig n'y serait jamais consommé) — le routeur est le bouton
  actionRow de T8 ; le brief dit « renvoie vers l'éditeur de config par le
  chemin ouvert en tâche 8 ». Le relecteur juge la conformité.
Task 9: revue (16:56) — Approved. Spec ✅ sur les dix points du brief ;
  interprétation du chemin T8 vérifiée à la source par le relecteur
  (pendingConfigFocus consommé uniquement dans onChange(of: currentTab) ;
  l'appeler depuis la fiche ouvrirait l'éditeur d'un mod quitté — le
  routage par le bouton actionRow est le comportement correct). Zéro
  Critical, zéro Important.
Task 9: ⚠️ résolu par le contrôleur : trailer cfe2184 = GLM 5.3 (modèle
  réellement actif via glm.sh).
Task 9: minor (deferred): ligne jeu sans lineLimit(1)/troncation —
  ModDetailView, diff T9 211-218.
Task 9: minor (deferred): le renvoi vers l'éditeur est implicite (rien de
  visible dans la zone ne désigne le bouton Réglages du mod) — inversable à
  bas coût si l'utilisateur veut un renvoi visible.
Task 9: minor (deferred): littéral 2 intra-collision au lieu d'un token
  AppDesign.Spacing, dupliqué avec KeybindReportSection 241/261.
Task 9: complete (commits c443bfa..cfe2184, review clean)
Revue finale: dispatchée (Opus, 1c4795e..cfe2184, 12 commits, paquet 118 Ko).
  Portée : plan + briefs T7-T9 + spec §6 ; triage des 8 minors différés
  actionnables ; question posée sur la case ROADMAP C4-T2 (T5 l'exigeait).
Revue finale (17:12) — « With fixes ». Zéro Critical. 2 Importants :
  (1) T5 jamais exécutée : ROADMAP:778 toujours - [ ], le constat doit
  porter les chiffres post-catalogue (18/11/141, pas 29/20 de T0) et le
  scénario écran de la spec §10 ; (2) staleness : saveConfig() n'invalide
  pas la signature du scan, le rapport garde le conflit corrigé — fix
  proposé : didSet sur editingModConfig force le rescan à la transition
  nil. Triage minors : corriger 1 (somme dupliquée→propriété VM), 3
  (attentionStrip→sous-vue), 4 (vm.L doublé→let), 5 (fixedSize en passant),
  6 (lineLimit ligne jeu fiche) + minor T2 relevé (tri non stable par
  modName→tie-break modID, Core testable) ; laisser 2 (course héritée),
  7 (routeur implicite — décision utilisateur), 8 (littéral 2), et
  unreadableMods version complète (une ligne au constat suffit).
  Points forts vérifiés : table 190 entrées ré-auditée par script, 36 tests
  comportementaux, branche entièrement en lecture seule sur le parc,
  cohrence inter-tâches confirmée aux trois consommateurs.
Vague de correctifs finale: dispatchée (Sonnet, BASE cfe2184) — T5 ROADMAP
  + constat, didSet editingModConfig, 6 correctifs de polish listés
  ci-dessus.
Vague de correctifs finale: livrée (commit 1e17512) — 2 Importants clos (T5 :
  ROADMAP:778 cochée + constat aux chiffres post-catalogue 141/18/11 ;
  staleness : didSet sur editingModConfig qui relance le scan à la fermeture
  de l'éditeur) et 6 poli appliqués (somme dupliquée → systemAlertCount sur le
  VM, AttentionCounterTile extrait de HomeView, vm.L évalué une fois,
  .fixedSize() retiré, lineLimit sur la ligne de conflit jeu, tri des usages
  départagé par modID — TDD). 1694 tests, build EXIT=0, cliquet sans hausse.
  Branche C4-T2 close (1c4795e..1e17512, 13 commits, non poussés).
  ⚠️ Ce commit est du code de réponse à une revue : il n'a été relu par
  personne.
