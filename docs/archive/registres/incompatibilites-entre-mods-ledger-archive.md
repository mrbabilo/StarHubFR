# Archive du ledger SDD — incompatibilites-entre-mods-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-29-incompatibilites-entre-mods/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-29-incompatibilites-entre-mods.md`.

2026-08-29-incompatibilites-entre-mods.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-29-incompatibilites-entre-mods.md

Spec : docs/superpowers/specs/2026-08-29-incompatibilites-entre-mods-design.md (lue).
BASE de branche : 13ca03e.

Ruling: exécution sur `main`, sans worktree — CLAUDE.md impose « Travailler sur main »,
  et les axes précédents (C4-T2, H-T1..T3) s'y sont faits. Coût si faux : un
  historique moins isolé, rattrapable par branche a posteriori.

## Scan préalable — paires de tâches partageant un fichier ou une interface

| tâches | ce qui est produit → consommé | constat |
| :-- | :-- | :-- |
| 1 → 2 | `CompatibilityNote.find(in:)`, même fichier | T2 remplace le `return nil` final ; T1 n'en a **qu'un**. OK |
| 1,2 → 3 | `CompatibilityNote.find(in:)` | signature identique des deux côtés. OK |
| 3, 9 | `ModDetailView.swift`, `assets/*.json`, `L10n.swift` | T3 ajoute à `enum Mods`, T9 à `enum Conflicts`. Pas de collision de clé. **Mais voir défaut ci-dessous** |
| 4 → 5 | `ContentPatcherConflicts.read(from:)`, `LoadConflict` | noms et types concordants. OK |
| 5 → 9 | `conflictFolderNames(_:)` | produit en T5 step 3, consommé en T9. OK |
| 6 → 7 | `ModConflictVerdicts` (Codable) | T7 encode/décode ; `Codable` conforme en T6. OK |
| 6 → 8 | `.declared` / `.dismissed` / `orphans(among:)` | les trois existent en T6. OK |
| 8, 9 | fichiers distincts (`ModConflictSection` vs `ModDetailView`) | pas de collision. OK |
| 1, 4, 6 | `Package.swift` | trois insertions séquentielles, pas concurrentes. OK |

## Scan préalable — cohérence interne de chaque tâche

| tâche | vérification | constat |
| :-- | :-- | :-- |
| 1 | tests ↔ code : niveaux (`l <= level`), corps vide, premier titre gagnant, pliage d'accents | les 7 tests suivent le code écrit. OK |
| 2 | `tail.count == lines.count - opener - 1` gouverne le débordement sur les blocs suivants ; vérifié sur les 4 tests | OK |
| 3 | clé L10n déclarée dans les deux locales **et** `L10n.swift` | OK |
| 4 | `LogEntry(timestamp:message:level:source:modName:)` — **signature vérifiée dans le source**, elle existe telle quelle | OK |
| 5 | dépend de `smapiLogPath` et `resolveModFolder` : les deux portent un ⚠️ de vérification | OK |
| 6 | `ModConflictPair.contains` utilisé par le test `orphans` : présent | OK |
| 7 | `InstalledTranslationStore.supportDirectory` porte un ⚠️ de vérification | OK |
| 8 | vue en prose ; clés L10n déclarées dans les deux locales et `L10n.swift` | OK |
| 9 | clés L10n déclarées dans les deux locales | 🔴 **DÉFAUT : rien ne dit de les ajouter à `L10n.swift`** |

Ruling: T9 — les cinq clés de la tâche 9 doivent rejoindre `enum Conflicts` dans
  `L10n.swift`, comme celles de la tâche 8. Le plan l'omet ; la consigne partira dans
  le brief de dispatch de T9. Coût si faux : aucun — sans cela le code ne compile pas,
  le défaut se serait vu au gate.

Task 1: complete (commit 13ca03e..9ef0e5f, review clean — spec conforme, qualité approuvée, 1715 tests).
Task 1: minor (deferred): un titre « compatib » au corps vide fait `continue` au lieu de
  `return nil` ; comportement défendable mais ni spécifié ni couvert par un test dédié.
Task 1: minor (deferred): `import Foundation` inutile dans le fichier de tests.

Task 2: livrée (commit 0d3b59a, 1719 tests). Revue : conformité ✅, qualité 2 Important.
Ruling: constat 1 (le débordement rejette un bloc `.text` suivant EN ENTIER dès qu'il
  contient un gras isolé, perdant les lignes qui le précèdent) est **mandaté par mon
  plan** — le canevas de l'étape 3 porte ce code. Je tranche POUR le relecteur : la spec
  dit que la section court « jusqu'au bloc de gras isolé **suivant** », donc le bloc doit
  être *tronqué* à cette ligne, pas jeté. Mon canevas raisonnait au niveau du bloc dans le
  seul endroit où il ne fallait pas — le piège même que la spec nomme. Coût si faux : une
  note un peu plus longue que voulu, jamais une note fausse.
Ruling: constat 2 (la condition `tail.count == …` passerait encore si on la remplaçait
  par `true`) — accepté, c'est un test qui n'atteste rien. Coût si faux : nul, un test de
  plus.
Task 2: fix round 1/5 (1 adressé + 2 mineurs, 1 ouvert — la condition `tail.count == …`
  reste remplaçable par `true` en dur sans faire échouer un test ; prouvé par mutation
  et relance de la suite par le re-relecteur, 1720/1720. Commits 0d3b59a..0b94960).
Task 2: fix round 2/5 (1 adressé, 0 ouvert — test `aSectionClosedInsideItsBlockDoesNotSpillOver`
  vérifié discriminant par mutation, exécutée par le contrôleur ET par le re-relecteur.
  Commits 0b94960..d1c5553).
Task 2: complete (commits 9ef0e5f..d1c5553, review clean, 1721 tests).

Task 3: livrée (commit a93ce2a, build EXIT=0, 1721 tests). L'implémenteur signale deux
  divergences du canevas, dont une de fond : garde `!isChangelog`.
Ruling: la garde `!isChangelog` est **acceptée**. `blocksView(isChangelog:)` est partagée
  entre les onglets Description et Changelog ; sans elle, un changelog portant un titre
  « Compatibility fixes » ferait apparaître la carte sous Changelog. La spec définit la
  carte comme « ce que l'auteur dit de la compatibilité » **dans sa description** : la
  garde sert la spec contre mon canevas, qui ignorait ce partage. Coût si faux : une
  carte de moins sur un onglet où elle n'a rien à faire.
Task 3: complete (commit d1c5553..a93ce2a, review clean — conformité sans réserve, qualité
  sans blocage ; garde `!isChangelog` confirmée nécessaire par le relecteur, partage de
  `blocksView(isChangelog:)` vérifié à la source lignes 1204/1214).
Task 3: minor (deferred): les deux blocs de commentaire au-dessus de la carte se lisent
  comme deux textes collés plutôt qu'un seul.
Task 3: minor (deferred): la garde `!isChangelog` — le point le plus subtil du lot — n'a
  pas de test, alors qu'elle est testable en Swift pur hors de la vue.
--- Lot T3 (tâches 1-3) livré : premier incrément visible. Vérification à l'écran due. ---

Task 4: livrée (commit 578d5fb, 1727 tests). Revue : conformité ✅, qualité 1 Critical +
  1 Important, tous deux hérités de mon canevas.
Ruling: Critical (un pack nommé « Bed and Breakfast » fait rendre 3 packs au lieu de 2,
  sans erreur) — corrigé par **abstention arithmétique** : le message dit littéralement
  « **Two** content packs », donc exactement deux noms sont attendus ; si le découpage sur
  « and » en rend un autre nombre, le parseur ne peut pas savoir où est la frontière et
  rend `nil` au lieu d'une paire fausse. C'est la règle constante du dépôt — mieux vaut
  ne rien dire que désigner le mauvais mod. La forme « Multiple » garde `> 1` : son arité
  est variable, aucun contrôle équivalent n'est possible ; la virgule dans un nom de mod
  reste une limite documentée. Coût si faux : un conflit rare non affiché, jamais un
  conflit attribué au mauvais mod.
Task 4: fix round 1/5 (1 Critical + 1 Important + 1 mineur adressés, 0 ouvert — abstention
  par arité paramétrée, forme « Multiple » intacte, limite virgule documentée.
  Commits 578d5fb..bad3870).
Task 4: complete (commits a93ce2a..bad3870, review clean, 1728 tests).

Ruling: Task 5 — la propriété `conflictsObservedAt` de mon plan **ne sera pas créée**.
  `@Published var smapiLogDate: Date?` existe déjà (ViewModel:33), alimentée par
  `computeSmapiDiagnostics` qui lit exactement le `.modificationDate` du journal (:3823),
  avec en prime `smapiLogStale`. Ajouter la mienne aurait fait deux copies divergentes de
  la même date. Coût si faux : aucun — la date affichée est la même, par construction.
Ruling: Task 5 — les conflits se calculent sur les entrées **avant** `trimPreservingSignal`.
  Le trim écrête à `maxLogEntries` ; il sacrifie les TRACE en premier, donc les ERROR
  survivent en pratique, mais lire la liste non écrêtée retire la question. Coût si faux :
  nul, la liste complète est déjà en main à cet endroit.

Task 5: livrée (commit 047acc8, build EXIT=0, 1728 tests), avec une inquiétude de
  correction soulevée par l'implémenteur — vérifiée et fondée.
Ruling: les conflits doivent aussi être alimentés par `parseSMAPILog()`. Vérifié :
  cette fonction est appelée depuis `scanMods` (:2119) et :2784 — le chemin de
  rafraîchissement ordinaire — tandis que `loadSmapiLog()` n'est appelée que depuis
  l'onglet Journaux, le veilleur et la bissection. Sans ce second câblage, la section
  « Conflits » afficherait une liste vide jusqu'à ce que l'utilisateur ouvre les
  Journaux, à côté d'une `smapiLogDate` fraîche : un « rien à signaler » mensonger,
  exactement ce que la spec interdit. `parseSMAPILog` a déjà le texte en main et publie
  déjà la date sœur. Coût si faux : un `SmapiLogParser.parse` de plus par scan sur un
  journal de ~390 Ko, à côté d'un `computeSmapiDiagnostics` qui parcourt déjà tout.
Task 5: fix round 1/5 (inquiétude de correction adressée avant revue — les deux chemins
  alimentent la liste, branche « fichier absent » incluse. Commits 047acc8..b4051e7).
Task 5: complete (commits bad3870..b4051e7, review clean — conformité sans réserve, 0
  Critical, 0 Important ; relecteur a vérifié que les deux chemins lisent bien le MÊME
  fichier, ce que je n'avais pas demandé).
Task 5: minor (deferred): `parseSMAPILog` balaie désormais le journal trois fois
  (diagnostics, boucle d'erreurs, SmapiLogParser) — fusion possible plus tard, hors
  thread principal donc non bloquant.

Task 6: livrée (commit ea88823, 1733 tests). Revue : conformité ✅, qualité 1 Critical +
  1 Important, hérités de mon canevas.
Ruling: Critical (tri sur `first` seul → ordre non déterministe entre paires partageant
  ce `first`, prouvé par 5 exécutions donnant 5 ordres) — corrigé par un tri sur le
  **couple** `(first, second)`, qui est un ordre total. C'est chargeant pour la tâche 7 :
  sans cela le fichier JSON serait réécrit différemment à chaque sauvegarde sans qu'aucune
  donnée n'ait changé. Coût si faux : nul, un ordre total ne peut pas être moins stable
  qu'un ordre partiel.
Task 6: fix round 1/5 (1 Critical + 1 Important + 1 mineur adressés, 0 ouvert ; le
  relecteur a en prime constaté que `orphans(among:)` portait le même défaut et qu'il a
  été corrigé aussi. Commits ea88823..76eaab5).
Task 6: complete (commits b4051e7..76eaab5, review clean, 1734 tests).
Task 6: minor (deferred): le test d'ordre total n'échouerait pas *à coup sûr* avec
  l'ancien tri — il pourrait retomber par hasard sur le bon ordre ; la preuve du défaut
  reste les 5 exécutions du relecteur.

Ruling: Task 7 — la persistance ne vit PAS dans le ViewModel comme mon plan l'écrivait,
  mais dans un `enum ModConflictVerdictsStore` en Core, calqué sur
  `InstalledTranslationStore` (`directory` / `fileURL` / `load()` / `save() -> Bool`).
  Deux raisons : c'est le patron du dépôt pour tout registre utilisateur, et du code en
  Core est **testable** alors que le même code dans le ViewModel ne l'est pas. Coût si
  faux : un fichier de plus, et une cible de test de plus.

Task 7: livrée (commit 6d9d148, build EXIT=0, 1738 tests). Revue : conformité ✅,
  qualité 2 Important.
Ruling: Important 1 (le calcul du dossier Application Support recopié au lieu d'être
  réutilisé depuis `InstalledTranslationStore.directory`, atteignable, même cible) —
  **corrigé**. Les deux copies sont identiques aujourd'hui, mais c'est exactement le
  patron qui a déjà coûté cher à ce dépôt (4 copies d'`isOsJunk`, une amputée, un
  `.Spotlight-V100` affiché comme mod). Coût si faux : nul, une ligne.
Ruling: Important 2 (un fichier corrompu rend un magasin vide, et la sauvegarde suivante
  l'écrase — perte silencieuse et irréversible) — **PARQUÉ, réel et non corrigé ici**.
  Le défaut est hérité tel quel d'`InstalledTranslationStore` et vaut à l'identique pour
  lui : le corriger dans un seul des deux magasins recréerait la divergence que
  l'Important 1 vient de retirer. Il appartient à une tâche qui traite les deux ensemble.
  Coût si faux : sur un fichier corrompu — cas jamais observé sur ce parc — l'utilisateur
  reperd ses signalements sans être averti. À remonter à l'utilisateur en fin de plan.
Task 7: minor (deferred): `load(from:)`/`save(_:to:)` publics avec URL optionnelle ; une
  surcharge `internal` à URL obligatoire aurait rendu l'oubli impossible au compilateur
  plutôt qu'à la discipline (patron déjà employé 7 fois par `ProfileConfigStore`).
Task 7: fix round 1/5 (1 Important adressé, 1 parqué volontairement, 0 ouvert.
  Commits 6d9d148..59ded92).
Task 7: complete (commits 76eaab5..59ded92, review clean, 1738 tests, build EXIT=0).

Task 8: livrée (commit e17b28a, build EXIT=0 vérifié au texte, 1738 tests). Revue :
  conformité tenue sauf un point, qualité 2 Important.
Ruling: Important 1 (le vert « aucun conflit dans le journal » peut s'afficher alors que
  le journal en contenait, simplement écartés par l'utilisateur) — **corrigé**. C'est le
  vert mensonger que la spec et la section sœur refusent, entré par la porte que le
  commentaire de tête croyait fermée. La défense « même patron que pausedIgnored » ne
  tient pas : ces compteurs-là comptent ce qui n'a jamais été scanné, pas ce qui a été
  détecté puis masqué par choix. Coût si faux : une phrase plus prudente là où on
  pouvait affirmer.
Ruling: Important 2 (le badge dit littéralement « Les deux sont actifs » pour un conflit
  à trois packs) — **corrigé**, faux par construction et non par accident.
Task 8: minor (deferred, corrigé au passage): glyphe d'en-tête figé sur l'alerte orange
  même quand le corps affiche le vert.
Note pour Task 9: `pair()` rend `nil` pour un conflit à 3+ packs, qui n'est donc **jamais**
  filtré par un écartement — il ne « revient » pas, il ne part jamais. Conséquence
  affichable : « 1 écarté(s) » sous une ligne restée visible. À cadrer en tâche 9.
Task 8: fix round 1/5 (2 Important + 1 mineur adressés, 0 ouvert. Commits e17b28a..ed5e966).
Task 8: ⚠️ résolu par le contrôleur : le symbole `arrow.triangle.merge`, dont
  l'implémenteur craignait qu'il n'existe pas (un nom erroné compile et rend un rectangle
  vide), est présent au catalogue SF Symbols du système — vérifié dans
  `CoreGlyphs.bundle/.../name_availability.plist`. Pas de vérification écran nécessaire.
Task 8: complete (commits 59ded92..ed5e966, review clean, 1738 tests, build EXIT=0).

Ruling: Task 9 — l'avertissement de conflit n'étend PAS `activationWarning(for:)`, qui
  rend `(component: ModItem, verdict: ModCompatibility)?`, un tuple taillé pour le verdict
  smapi.io et consommé par un dialogue déjà livré et relu (`ModListView:1763`). Une
  fonction **séparée** `conflictWarning(for:)` s'ajoute à côté, et la vue interroge les
  deux. Changer le type de retour existant ferait rippler un dialogue en production pour
  aucun gain. Coût si faux : deux états de dialogue dans la ligne de mod au lieu d'un.
