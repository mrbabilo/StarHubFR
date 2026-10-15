# Archive du ledger SDD — lot-json-traduction-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-20-lot-json-traduction/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-20-lot-json-traduction.md`.

2026-08-20-lot-json-traduction.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-20-lot-json-traduction.md

Ruling: on implémente sur `main`, sans worktree — le `CLAUDE.md` du dépôt
prescrit « Travailler sur main », et une consigne du dépôt prime sur le skill.
Coût si erreur : les commits atterrissent sur main sans isolation ; annulables
par `git revert`, l'arbre étant propre et la 1.16.0 taguée juste avant.

## Scan préalable du plan (6 tâches)

| Tâches | Fichier / interface partagé | Ce qui est produit → consommé | Constat |
|---|---|---|---|
| 1 → 2 | `Models/TranslationLot.swift` | `TranslationLot.Entry`, `init(mod:language:entries:)` → `build(...)` l'appelle | cohérent |
| 1 → 3 | `TranslationLot` (Codable, `digest`, `formatVersion`) | décodé et comparé par `TranslationLotImport.read` | cohérent |
| 2 → 4 | `TranslationLot.build(mod:language:rows:glossary:)` | appelé par `exportTranslationLot` **et** `importTranslationLot` | cohérent — le lot attendu est reconstruit à l'identique à l'import, c'est ce qui fait tenir l'empreinte |
| 3 → 4 | `Report`, `Rejection`, `FileRefusal` | affichés par `LotOutcome` | cohérent |
| 4 → 5 | `exportTranslationLot`, `importTranslationLot`, `LotOutcome` | boutons et compte rendu | cohérent |
| 1,2 → 3 | tests | tâche 2 crée `TranslationLotBuildTests` dans le fichier de la tâche 1 | cohérent (même cible de test) |

| Tâche | Cohérence interne | Constat |
|---|---|---|
| 1 | tests ↔ code | cohérent ; `instructions` testé sur son contenu, pas sur sa forme exacte |
| 2 | tests ↔ code | **défaut connu, signalé dans le plan** : l'aide `row(...)` est un `fatalError` à écrire contre l'initialiseur réel de `DiffRow`. Ruling : c'est délibéré (douze champs, l'inventer mentirait) ; l'implémenteur reçoit la consigne de le lire par `grep`. Coût si erreur : une tâche 2 qui échoue au premier build, rattrapée dans la boucle. |
| 3 | tests ↔ code | cohérent ; `anInventedKeyIsRejected` altère les entrées **après** construction, donc l'empreinte du lot envoyé reste valable — c'est bien ce que le code teste |
| 4 | pas de test unitaire | assumé et expliqué : le VM n'est pas dans la cible Core |
| 5 | UI + L10n | cohérent ; parité des clés garantie par le build |
| 6 | validation | cohérent |

Ruling: le plan §3 s'écarte de la spec (« valide tout avant toute écriture »)
en séparant refus du fichier et refus d'une entrée. Décidé : on suit le plan.
La spec est l'autorité, mais sa phrase se lit comme « aucune écriture partielle
en cours de scan », et le tout-ou-rien strict ferait perdre 500 clés pour une.
Coût si erreur : une ligne à changer dans `TranslationLotImport.read`.

Task 1: complete (commits ffcd020..c66ef31, review clean — spec ✅, qualité approuvée)
Task 1: ⚠️ résolu par le contrôleur — « target vide à l'export » n'est pas
  imposé par le type : c'est la tâche 2 qui l'impose, et elle a son test
  (`everyExportedEntryHasAnEmptyTarget`). Pas un manque.
Task 1: minor (deferred): l'empreinte trie des chaînes jointes par \u{1F}
  plutôt qu'un triplet structuré. Choix du plan, inoffensif sur des données
  réelles (pas de caractères de contrôle dans les clés i18n).
Task 2: review — spec ✅, qualité : 2 Important + 1 Mineur.
Task 2: Ruling: le correctif du filtre passe par `TranslationBatchPlanner.eligibleRows`
  plutôt qu'une nouvelle condition d'états. Le dépôt a déjà une définition de
  « ce qui reste à traduire » ; en avoir deux qui divergent est le piège
  [[diverging-copies-hide-bugs]] qu'il a déjà payé. Coût si erreur : un couplage
  de plus entre le lot JSON et le planneur du lot IA — annulable en une ligne.
Task 2: fix round 1/5 dispatché (implémenteur ae4f72c repris).
Task 2: fix round 1/5 (2 traités, 1 ouvert — fixture orpheline non discriminante ;
  commits 8fc8fe2..47bcaf8)
Task 2: Ruling: le constat 2(b) est **résolu, pas parqué**. Le re-relecteur
  demandait un test prouvant que `.orphan` est exclu indépendamment du garde
  `!english.isEmpty`. Ce test **existe déjà**, au bon endroit et avec exactement
  la fixture demandée : `Tests/TranslationBatchPlannerTests/…:15-22`
  (`eligibleRowsTakesMissingAndEmptyOnly`), dont la rangée orpheline porte
  `english: "enlost"` — non vide. L'exclusion des orphelines est désormais la
  responsabilité de `TranslationBatchPlanner`, et elle y est prouvée. La
  redupliquer dans les tests du lot recréerait la seconde définition que le
  correctif venait justement de supprimer.
  Coût si erreur : si quelqu'un retire un jour `.orphan` de `eligibleRows`, le
  lot exporterait des orphelines — mais le test du planneur virerait au rouge
  d'abord. Vérifié, pas supposé.
Task 2: complete (commits ffcd020..47bcaf8, review clean après 1 tour)
Task 3: l'implémenteur (adce7ed) a été coupé par une mise en veille de la
  machine, après avoir commité af3d8c8 mais avant d'écrire son rapport.
  Vérifié par `git log` et les gates, pas par son récit : 1030 tests verts,
  travail complet sur disque.
Task 3: Ruling: cliquet relevé (`try_optional` 209 → 211) plutôt que corrigé.
  Les deux `try?` sont ceux de `TranslationLotImport.decode`, dont le contrat
  est « nil quand on ne sait pas lire » — ils viennent du code du plan et
  l'échec de décodage y est une branche attendue. Coût si erreur : deux unités
  de mou dans un compteur qu'on resserre par ailleurs.
Task 3: review — spec ✅, qualité : 3 Important + 2 Mineurs.
Task 3: Ruling: le correctif du découpage n'introduit **pas** `I18nLenientParser`,
  contrairement à ce que la section « Interfaces » du cahier des charges annonce.
  Le parseur rend un dictionnaire, or il faut ici un décodage Codable vers
  `TranslationLot` ; reconstruire le type depuis un dictionnaire coûterait plus
  qu'il ne rapporte. Ordre retenu : décodage direct → contenu de la clôture ``` →
  découpage première-{/dernière-}. Coût si erreur : un fichier exotique refusé
  que le parseur permissif aurait sauvé — l'utilisateur réexporte.
Task 3: minor (deferred): `target` élagué pour le test de vide, stocké brut.
Task 3: minor (deferred): une marque **ajoutée** ne bloque pas (seule la perte).
  Conforme au cahier des charges, à confirmer comme intention à la revue finale.
Task 3: ⚠️ à vérifier en tâche 4 — l'appelant doit reconstruire `sent` depuis
  l'état **courant** du mod à chaque import, sinon la garantie « un lot exporté
  avant une mise à jour ne peut pas écrire » ne tient pas. Le plan le fait
  (`importTranslationLot` appelle `TranslationLot.build`), à confirmer sur le code.
Task 3: ⚠️ parqué — deux entrées de même (composant, clé) dans un lot revenu
  seraient acceptées deux fois ; la seconde écriture écrase la première avec sa
  propre valeur. Sans danger, non testé.
Task 3: fix round 1/5 dispatché (implémenteur adce7ed repris).
Task 3: fix round 1/5 (2 traités, 1 ouvert — `anInventedKeyIsRejected` toujours
  non discriminant : la clé inventée est en dernière position, donc `break` n'y
  coûte rien ; commits e9bc4cf..d297efb). Re-relecture faite **par mutation du
  code**, pas par lecture seule — c'est ce qui a démasqué le point.
Task 3: fix round 2/5 dispatché (implémenteur adce7ed repris).
Task 3: à faire en fin de tâche — le correctif a supprimé les deux `try?` :
  le cliquet est à 211 pour un compte réel de 209, à resserrer.
Task 3: fix round 2/5 (1 traité, 0 ouvert — clé inventée placée en tête par
  `insert(at: 0)` ; l'implémenteur a fourni la preuve par mutation : le test
  échoue seul sous `continue` → `break`, les 11 autres restent verts).
Task 3: Ruling: le diff du tour 2 (9 lignes, tests seuls, preuve de mutation
  fournie) a été relu **par moi** plutôt que par un re-relecteur dispatché.
  Sous ~6 Ko et sans code de production touché, la lecture directe est plus
  rapide et aussi sûre. Coût si erreur : un défaut de test non vu — le tour
  suivant et la revue finale restent des filets.
Task 3: cliquet resserré 211 → 209 (le correctif a supprimé les deux `try?`).
Task 3: complete (commits 47bcaf8..80ef9cb, review clean après 2 tours)
Task 4: review — spec ✅ (la garantie `sent` = état courant est confirmée sur
  le code, ViewModel:1099). Qualité : 2 Important + 2 Mineurs.
Task 4: ⚠️ résolu — « l'appelant recalcule-t-il `rows` avant l'import ? » : pas
  encore d'appelant, c'est la tâche 5. À porter dans son dispatch.
Task 4: Ruling: le constat Important 2 (le `.bak` par entrée ne restitue plus
  l'état d'avant le lot quand N entrées visent le même fichier) est **parqué**,
  pas corrigé. C'est une caractéristique préexistante de `TranslationFileStore`,
  déjà partagée avec `runBatch`, et le risque est borné : le lot n'écrit que sur
  des clés **absentes ou vides**, donc un `.bak` incomplet ne peut faire perdre
  que des traductions machine, jamais du travail humain. Coût si erreur :
  annuler un import massif demande de réexporter plutôt qu'un simple retour
  arrière. À reprendre dans un chantier « instantané avant lot ».
Task 4: minor (deferred): un `defaultDirectory()` nil laisserait des entrées
  écrites sans drapeau « à relire ».
Task 4: fix round 1/5 dispatché (implémenteur a474b22 repris) — fidélité du
  compte rendu + symétrie de `byIdentity`.
Task 4: fix round 1/5 (2 traités, 0 ouvert — `written + writeFailures ==
  report.accepted.count` vérifié par le relecteur, sans trou ni double compte ;
  `byIdentity` filtré comme `sent` ; commits a0687d0..fec9dac).
Task 4: minor (deferred): le commentaire de `writeFailures` ne mentionne pas la
  branche « rangée introuvable », qui l'incrémente aussi.
Task 4: minor (deferred): `.failed` est désormais journalisé deux fois (dans
  `saveTranslation` puis au site d'appel). Cosmétique.
Task 4: le relecteur a vérifié que deux `DiffRow` de même identité sont
  **structurellement impossibles** (un dictionnaire par composant) — le risque
  du Mineur 1 était théorique, il est clos par construction.
Task 4: complete (commits c1ec89d..fec9dac, review clean après 1 tour)
Task 5: review — spec ✅ (fraîcheur des `rows` vérifiée : pas de point de
  suspension entre la relecture et l'appel, un seul site d'appel dans le dépôt).
  Qualité : 1 Important + 4 Mineurs.
Task 5: Ruling: le cliquet est **relevé** (abbreviation_vm +25, vm_dot_L_calls
  +17) et non corrigé — 225 lignes de vue et 11 clés de localisation, les `vm.L`
  sont le patron du dépôt (820 appels existants). Coût si erreur : deux
  compteurs plus hauts sur un code qui suit la convention.
Task 5: Ruling: `.wrongLanguage` et `.unsupportedFormat` restent repliés sur
  « illisible ». Les deux cas sont inatteignables aujourd'hui (l'app n'exporte
  que le français, et il n'existe qu'une version de format) et la phrase
  générique n'est pas fausse. Coût si erreur : un message imprécis le jour où
  un lot édité à la main porte une autre langue.
Task 5: minor (deferred): `rejectionLabel` diverge de `DiffRow.id` sur le cas
  d'un composant vide, alors que son commentaire affirme l'identité.
Task 5: fix round 1/5 dispatché (implémenteur aefe584 repris) — les échecs
  d'écriture doivent être visibles et nommés.
Task 5: fix round 1/5 (1 traité, 0 ouvert — trois nombres distincts comme le
  rapport du lot IA, et le commentaire de `rejectionLabel` dit désormais le
  format exact ; commits 9928d55..610b985).
Task 5: Ruling: diff du tour (35 lignes de vue + une chaîne) relu **par moi**
  plutôt que dispatché. Le constat était précis et le correctif tient en un
  changement de format de chaîne ; la revue finale reste le filet.
Task 5: complete (commits fec9dac..610b985, review clean après 1 tour)
Task 6: gates verts (1032 tests, build vert), entrée CHANGELOG ajoutée (d355bce).
Task 6: Ruling: j'ai retouché la formulation de l'entrée moi-même plutôt que de
  rouvrir une boucle — « Export what's missing French » était agrammatical, et
  « an outdated batch » ne disait pas par rapport à quoi. C'est de la copie,
  pas du code : la boucle de relecture n'y apporte rien. Coût si erreur : une
  phrase à retoucher, visible dans le diff.
