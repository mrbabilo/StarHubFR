# Archive du ledger SDD — lot-sante-secours-h-t6-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-09-02-lot-sante-secours-h-t6/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-09-02-lot-sante-secours-h-t6.md`.

2026-09-02-lot-sante-secours-h-t6.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-02-lot-sante-secours-h-t6.md

Spec: docs/superpowers/specs/2026-09-02-lot-sante-secours-h-t6-design.md (lue)
Branche: main (CLAUDE.md impose main ; instruction projet > demande de worktree du skill)
BASE du lot: 9881cec

## Scan de conflits pré-vol

Paires partageant un fichier ou une interface :

| A | B | fichier / interface | constat |
|---|---|---|---|
| T1 | T2 | Package.swift (sources) | séquentiel, pas de conflit |
| T1 | T2,T3 | Tests/HealthIssueTests/ | fichiers de test distincts, OK |
| T2 | T3 | Models/HealthIssueResolver.swift | T2 crée `smapiIssues`, T3 ajoute `keybindIssues`/`conflictIssues`/`resolve` — cohérent |
| T3 | T4 | `resolve(diagnostics:keybindReport:conflicts:)` | signature produite = signature consommée, OK |
| T4 | T7 | `vm.healthIssues` | produit en T4, consommé en T7, OK |
| T5 | T7,T9 | `SeverityBadge(severity:label:)` | **CONFLIT F1** — voir R1 |
| T5 | T7 | enum L10n du lot | **CONFLIT F2** — voir R2 |
| T6 | T7,T8 | SystemAlertsView / QuarantineView | T6 crée les fichiers, T7/T8 les modifient — ordre correct |
| T1 | T5 | `Severity` cases vs switch du badge | .critical/.warning/.info des deux côtés, OK |

Auto-cohérence de chaque tâche :

| tâche | constat |
|---|---|
| T1 | init du test = init du type, OK |
| T2 | fixture n'utilise que des `var` et des `init` publics vérifiés dans SmapiLogDiagnostics.swift, OK |
| T3 | fixture au patron réel du dépôt (`KeybindScanner.report(mods:)`), `.object(...)` signalé à vérifier |
| T4 | `liveConflicts` ajouté en étape 0 TDD, `conflictPair` existe déjà dans le VM, OK |
| T5 | `AppDesign.Font.caption(.medium)` existe, OK |
| T6 | déplacement pur, critère de diff posé (suppressions ≈ insertions), OK |
| T7 | dépend de T4 et T5 ; `currentTab` déjà présent dans la vue d'origine, OK |
| T8 | identité de ForEach signalée à mesurer (dédup à la source), OK |
| T9 | 7 champs du rapport relevés du code ; clés L10n signalées à vérifier, OK |
| T10 | consigne anti-tranche-d'indices sur la ROADMAP, OK |

## Décisions de pré-vol

Ruling: F1 — `severityKey(...)` était appelé en T7 sans être défini nulle part.
Décision : la clé de libellé devient `Severity.l10nKey` en Core (T1), utilisée
par T5 et T7. Pourquoi : deux tables de correspondance divergeraient et une
gravité s'afficherait sous deux noms selon l'écran. Coût si faux : `l10nKey`
force T1 à créer l'enum `L10n.Health` avant T5 — un ordre de plus à tenir.

Ruling: F2 — T5 hésitait entre `L10n.Updates` et un enum `Health`, T7 utilisait
`L10n.Alerts` ; ni `Alerts` ni `Health` n'existait. Décision : `L10n.Health`,
créé en T1, partout. Pourquoi : un seul enum pour le vocabulaire du lot. Coût
si faux : une clé mal rangée, renommage trivial.

Ruling: le script `task-brief` du skill exige des titres « Task N » ; le plan
est en français (« Tâche N »). Décision : extracteur local
`extract-brief.py`, qui joint aussi les contraintes globales à chaque brief.
Pourquoi : angliciser un plan relu et validé pour plaire à un script est le
mauvais sens. Coût si faux : un script de plus à maintenir, 15 lignes.

## Journal

BASE tâche 1: 9881cec
Task 1: implémenté (commit 7611974, 1877 tests verts, gate exit 0)
Task 1: doute de l'implémenteur écarté — les 7 commits qu'il a vus arriver sur
main (8e1453a→9881cec) sont ceux de la session courante, pas d'une session
parallèle. Aucun chevauchement de fichiers.
Task 1: revue dépêchée sur review-9881cec..7611974.diff
Task 1: revue — conformité ✅, qualité approuvée, 0 critique, 0 important.
Task 1: ⚠️ non vérifiable par le relecteur (le gate a-t-il réellement tourné) —
résolu par le contrôleur : gate relancé, SUCCESS, 1877 tests verts.
Task 1: minor (deferred): commentaire faux sur « Comparable synthétisé » —
l'implémentation écrit un `static func <` explicite ; Swift ne synthétise pas
Comparable pour un enum Int. Vient de mon plan, pas de l'implémenteur.
Task 1: minor (deferred): `CaseIterable` ajouté au-delà du brief, non utilisé.
Task 1: minor (deferred): `identityComesFromContent` passerait avec n'importe
quel Equatable synthétisé — la vraie preuve d'identité dérivée du contenu se
joue en T2, qui construit des HealthIssue depuis SmapiDiagnostics. À porter
dans la dépêche de T2.
Task 1: complete (commits 9881cec..7611974, review clean)
BASE tâche 2: 7611974
Task 2: implémenté (commit 5377196, 1882 tests verts).
Task 2: le mineur porté depuis T1 est traité — l'implémenteur a MUTÉ le code
pour utiliser les UUID source et confirmé que `identitiesAreStableAcrossTwoResolutions`
échoue alors, puis reverté. La contrainte d'identité est donc réellement prouvée.
Task 2: revue dépêchée sur review-7611974..5377196.diff
Task 2: revue — conformité ✅ au brief, mais qualité NON APPROUVÉE : 1 critique,
1 important, 2 mineurs. Le critique vient du plan, pas de l'implémenteur.

Ruling: T2 critique — double comptage. Mon plan traitait `missingDeps` comme une
source disjointe. Vérifié dans SmapiLogDiagnostics.swift : il est documenté
« promoted from failed/skipped » et « a subset of failed/skipped », et le
`problemCount` du parseur l'exclut pour cette raison précise. Un mod en échec
produisait donc DEUX lignes critiques. Décision : `missingDeps` n'émet plus de
ligne propre — il enrichit le `detail` de la ligne failed/skipped correspondante,
et n'émet une ligne que si son mod est absent des deux listes (défensif).
Pourquoi : la spec fait du compteur honnête l'argument central du lot ; un
double comptage le ruine. Coût si faux : la dépendance manquante devient un
détail au lieu d'une ligne — moins visible, mais comptée juste.

Ruling: T2 sous-comptage symétrique, relevé par moi et non par le relecteur. Le
`problemCount` du parseur vaut `skipped + failed + externalConflicts +
brokenMods` ; mon résolveur ignorait `externalConflicts` et `brokenMods`, qui
sont des problèmes de chargement avérés selon la définition du dépôt lui-même.
Décision : les ajouter en critique. Pourquoi : aligner notre notion de problème
sur celle, déjà testée, du parseur — sinon l'écran sous-estime. Coût si faux :
deux familles de lignes en plus, à retirer si elles s'avèrent bruyantes à
l'écran.

Ruling: T2 important — la fixture n'était pas productible par le vrai parseur,
ce qui a masqué le double comptage. Décision : exiger un test construit par
`SmapiDiagnostics.parse(logContent:)` sur le journal du test existant
`promotesMissingDependenciesFromFailedAndSkipped`. Pourquoi : c'est le seul
test qui aurait attrapé le défaut. Coût si faux : aucun, c'est un test en plus.

Task 2: fix round 1/5 dépêché (3 constats)
Task 2: fix round 1/5 (5 traités, 0 ouvert ; commits 5377196..132ebfc).
  Contre-épreuve du relecteur : rejeu du commit parent → le mod produisait bien
  2 lignes critiques avant, 1 après. Le test attrape réellement le défaut.
Task 2: minor (deferred): `enrichedDetail` compare par sous-chaîne brute, sans
  normalisation de casse/espaces. Sans effet aujourd'hui ; à surveiller si le
  parseur reformule un jour `reason` et `missingDeps` différemment.
Task 2: minor (deferred): `detail` porte du texte diagnostique brut, hors L10n.
  C'est de la donnée (noms de mods, raisons du journal), pas de la copie d'UI —
  choix assumé. À porter dans la dépêche de T7, qui l'affiche.
Task 2: complete (commits 7611974..132ebfc, review clean)
BASE tâche 3: 132ebfc
Task 3: implémenteur coupé par une limite de session en pleine écriture
  (127 lignes non commitées, aucun rapport). Repris plutôt que rejeté : son
  contexte connaissait ces lignes. Il a confirmé avoir vu le rouge par stash.
Task 3: implémenté (commit 45e0544, 1889 tests verts).
Task 3: revue dépêchée.
Task 3: revue — conformité globalement ✅ (réserve sur l'invariant), qualité
  NON approuvée : 2 importants, 2 mineurs. Le premier important vient du brief.

Ruling: T3 important — l'id d'une collision de raccourci s'écrit
`"keybind-collision-\(mods)"`, sans le combo, alors que `report.collisions` est
indexé PAR combo. Deux touches différentes disputées par les deux mêmes mods
donnent donc deux HealthIssue de MÊME id — plausible sur un parc de ~900 mods.
Décision : inclure le combo dans l'id. Pourquoi : `Identifiable` à id dupliqué
est exactement le piège `ForEach` documenté dans CLAUDE.md, et la contrainte du
lot veut une identité stable ET unique, pas seulement dérivée du contenu. Coût
si faux : aucun, l'id s'allonge.

Ruling: T3 important — la branche `gameConflicts` de `keybindIssues` n'est
exercée par aucun test ; une implémentation qui l'omettrait ou lui donnerait la
mauvaise gravité passerait tout le lot. La fixture actuelle ne peut structurellement
pas en produire (combos à 2 boutons ; un conflit jeu exige un bouton unique).
Décision : exiger une fixture à bouton unique qui produise un vrai gameConflict.
Pourquoi : l'invariant annoncé porte sur `collisions + gameConflicts` et n'est
aujourd'hui prouvé que sur le premier terme. Coût si faux : un test de plus.

Task 3: fix round 1/5 dépêché (2 importants)
Task 3: fix round 1/5 (2 traités, 0 ouvert ; commits 45e0544..e35264c).
  Contre-épreuve : l'ancien résolveur rejoué fait bien échouer le test d'id, et
  lui seul. `KeybindCombo.init?` fait `Array(Set(buttons)).sorted()`, donc la
  représentation du combo dans l'id est déterministe — la stabilité tient.
Task 3: minor (deferred): l'unicité des id de `gameConflicts` est correcte par
  construction (un conflit par nom de contrôle) mais aucun test ne l'affirme.
Task 3: complete (commits 132ebfc..e35264c, review clean)
BASE tâche 4: e35264c
Task 4: implémenté (commit a11ecf1, 1893 tests, gate SUCCESS, cliquet inchangé).
Task 4: l'implémenteur a trié `liveConflicts` via le helper existant `sortPairs`,
  au-delà du brief : l'ancien filtre passait par un Set non ordonné, sans effet
  tant que seul `.count` sortait, mais l'ordre serait devenu visible maintenant
  que la liste alimente un affichage. Même famille que les défauts d'identité
  du lot — attrapé en amont cette fois.
Task 4: revue dépêchée.
Task 4: revue — conformité ✅ sur les 5 points, qualité : 0 critique,
  1 important, 1 mineur. Les deux viennent du brief.

Ruling: T4 important — `sortPairs` corrige un ordre non déterministe mais aucun
test n'inspecte le tableau renvoyé, seulement des `.count`. Une régression
future retirerait le tri sans rougir. Décision : exiger un test qui donne les
candidats dans un ordre mélangé et affirme l'ordre exact du résultat. Pourquoi :
c'est la famille de défaut la plus fréquente du lot (index, combo manquant,
Set non ordonné) et la seule non couverte ici. Coût si faux : un test de plus.

Ruling: T4 mineur — `liveConflictCountDerivesFromTheList`, repris verbatim de
mon brief, est tautologique : `liveConflictCount` étant DÉFINI comme
`liveConflicts(...).count`, l'égalité est vraie même si `liveConflicts` renvoie
[]. Décision : le traiter dans la même ronde plutôt que le différer — corriger
l'important exige d'affirmer le contenu, ce qui dissout la tautologie. Pourquoi :
même fichier, même geste. Coût si faux : aucun.

Task 4: fix round 1/5 dépêché (1 important + 1 mineur adjacent)
Task 4: fix round 1/5 (2 traités, 0 ouvert ; commits a11ecf1..cd300cd).
  Le compte de tests inchangé s'explique : remplacement 1-pour-1, l'ancien test
  tautologique cède la place à un test qui affirme le contenu exact ET conserve
  son invariant de dérivation. Rouge vérifié en retirant `sortPairs`.
Task 4: minor (deferred): le test d'ordre est probabiliste — `Array(Set(...))`
  a un ordre d'itération dépendant du hachage aléatoire par processus, donc
  l'échec sans `sortPairs` est fiable en pratique mais non garanti à chaque
  exécution. Limite inhérente, pas un défaut.
Task 4: complete (commits e35264c..cd300cd, review clean)
BASE tâche 5: cd300cd
Task 5: implémenté (commit 34bd8ba, gate SUCCESS, parité L10n OK).
Task 5: 7e défaut issu de mes documents — le brief annonçait
  « Produit : SeverityBadge(severity:) » dans son bloc Interfaces alors que son
  corps de code montrait `severity` + `label`. Mon scan pré-vol avait vérifié la
  cohérence entre les SITES D'APPEL de T7/T9 et le composant, mais pas entre le
  bloc Interfaces et le corps de code du MÊME brief. L'implémenteur a suivi le
  corps de code, cohérent avec le patron `CategoryBadge` du dépôt. Bon choix.
Task 5: `exclamationmark.octagon.fill` confirmé disponible sur macOS 14 (déjà
  utilisé dans ModListView.swift:1939) — pas de repli triangle nécessaire.
Task 5: revue dépêchée.
Task 5: revue — conformité ✅ sur 1,2,3,5 ; 1 important sur le point 4 ;
  1 mineur (doc citant le mauvais composant de référence).

Ruling: T5 important — l'implémenteur a justifié `severity:label:` en invoquant
`CategoryBadge`, qui fait en réalité L'INVERSE : il prend `category` + une
closure `L` et résout lui-même. Vérifié dans le code. Le relecteur en déduit
qu'il fallait `SeverityBadge(severity:L:)`.
  MAIS son remède, appliqué tel quel, casserait la tâche 9 : elle affiche
« Activé »/« En pause » sur une gravité, donc un libellé qui n'est PAS celui de
la gravité. Le relecteur ne pouvait pas le voir, il n'avait que le brief de T5.
  Décision : DEUX initialiseurs. `init(severity:L:)` résout via `l10nKey` — le
cas courant, où la divergence devient impossible par construction ; et
`init(severity:label:)` conservé pour le cas délibérément différent. T7 passe
au premier, T9 garde le second. Plan mis à jour en conséquence.
  Pourquoi : le paramètre `label` n'est pas redondant, il est nécessaire une
fois sur deux ; le supprimer aurait déplacé le problème en tâche 9. Coût si
faux : un initialiseur de plus, que personne n'utiliserait.

Task 5: fix round 1/5 dépêché (1 important + 1 mineur)
Task 5: fix round 1/5 (2 traités, 0 ouvert ; commits 34bd8ba..adf333e).
  Cliquet vérifié à la source : le regex `(?<![\w.])L\(` capture exactement la
  nouvelle occurrence, +1 pour +1. Pas de sur-relevé masquant autre chose.
Task 5: minor (deferred): la protection de `init(severity:label:)` contre le
  mésusage reste documentaire, pas structurelle. Le relecteur suggère un
  nommage distinctif (`overrideLabel:`). À trier à la revue globale — je ne
  rouvre pas la boucle pour ça.
Task 5: complete (commits cd300cd..adf333e, review clean)
BASE tâche 6: adf333e
Task 6: implémenté (commit 5887d04). Déplacement pur : 357 insertions /
  356 suppressions ; MainView 1519 → 1163 lignes. Le +1 net vient d'une
  normalisation de ligne blanche à la coupure, expliquée au rapport. Aucun
  changement de visibilité requis. Gate exit 0 lu dans le fichier.
Task 6: revue dépêchée.
Task 6: revue — déplacement pur confirmé par `diff` réel (exit 0 sur
  QuarantineView, une seule ligne blanche d'écart sur SystemAlertsView).
  Signatures, sites d'appel et visibilités inchangés. 0 constat, tous niveaux.
Task 6: complete (commits adf333e..5887d04, review clean)
BASE tâche 7: 5887d04
Task 7: implémenté (commit cb4d0ba, gate exit 0, cliquet inchangé).

Ruling: T7 — DÉFAUT DE MON PROCESSUS, pas du plan. J'ai corrigé le plan après la
revue de T5 (SeverityBadge à deux initialiseurs) mais les briefs avaient déjà
été TOUS extraits au démarrage : celui de T7 portait donc encore l'ancien appel
`severity:label:`, contredisant la consigne en prose de ma dépêche.
L'implémenteur a suivi la prose et signalé la contradiction — bon choix.
  Décision : ré-extraire les briefs 8, 9 et 10 depuis le plan à jour, et
règle pour la suite : toute correction du plan en cours d'exécution impose de
régénérer les briefs des tâches non encore dépêchées. Coût si faux : aucun,
la régénération est idempotente.

Task 7: revue dépêchée.
Task 7: revue — conformité ✅ sur les 8 points, qualité bonne, 0 critique,
  0 important, 2 mineurs.
Task 7: minor (deferred) À TRIER EN PRIORITÉ À LA REVUE GLOBALE :
  `vm.healthIssues` est une propriété CALCULÉE, lue 4 fois par rendu (isEmpty,
  ForEach, .count, .filter). Chaque lecture reconstruit un Set sur
  `flattenedMods` et refait le tri. Sur le parc réel de l'auteur (~966 mods),
  ce n'est pas gratuit, et un rendu SwiftUI est fréquent. Vient de l'exemple de
  mon brief, pas de l'implémenteur. Correctif trivial : un `let issues =
  vm.healthIssues` en tête de body. Classé mineur par le relecteur, mais
  l'échelle du parc en fait un candidat sérieux.
Task 7: minor (deferred): deux clés L10n orphelines après le refactor
  (`updates_errors_found`, `updates_error_description`). Hors périmètre T7.
Task 7: complete (commits 5887d04..cb4d0ba, review clean)
BASE tâche 8: cb4d0ba
Task 8: implémenté (commit 8c41912, gate exit 0, cliquet +2 vm.L).
Task 8: 9e défaut de mes documents — le brief annonçait
  `report.quarantined: [String]`, c'est `[ModFolderRepairer.Item]` (Equatable,
  pas Hashable). L'implémenteur a mesuré et suivi le code, comme demandé.
  Identités : `relativePath` pour `quarantined` (unique), wrapper rang+contenu
  pour `duplicates` (valeur collisionnable). Réponse nuancée, pas uniforme.
Task 8: écart de périmètre signalé par l'implémenteur : il a étendu le
  nettoyage des couleurs à tout le fichier, au-delà des deux `.purple` cités,
  au nom de la contrainte globale. Justifié et déclaré — à valider en revue.
Task 8: revue dépêchée.
Task 8: revue — conformité ✅, qualité bonne, 0 critique, 0 important,
  2 mineurs. Unicité de `relativePath` vérifiée DANS le code du réparateur
  (le sweep déplace avant que la boucle top-niveau n'énumère), pas sur parole.
  Extension du nettoyage des couleurs jugée justifiée, conversions 1:1.
Task 8: minor (deferred) À SIGNALER À LA REVUE GLOBALE : l'unicité de
  `relativePath` repose sur un ORDRE D'EXÉCUTION (sweep avant top-niveau,
  synchrone, mono-thread), pas sur une invariance structurelle du type `Item`.
  Aucun test ni commentaire dans `ModFolderRepairer` ne fige cette garantie :
  une parallélisation ou un réordonnancement futur la briserait en silence,
  sans que QuarantineView en soit averti. Fragilité latente typique.
Task 8: minor (deferred): le rapport analyse `detectDuplicates(modsPath:)`
  alors que la vue câble `detectDuplicates(from:)` — conclusion juste, mais
  narration portant sur le mauvais chemin de code.
Task 8: complete (commits cb4d0ba..8c41912, review clean)
BASE tâche 9: 8c41912
Task 9: implémenté (commit 4194223, gate exit 0, 1893 tests verts).
  Présentateurs : ModInstallBackupsView 4→1, ModConfigBackupsView 3→1.
Task 9: BUG RÉEL TROUVÉ ET CORRIGÉ EN PASSANT — dans ModConfigBackupsView,
  l'action de l'alerte de restauration relisait `backupToRestore`, déjà remis à
  `nil` par le binding à la fermeture. Le bouton « Restaurer » d'une sauvegarde
  de config NE RESTAURAIT RIEN. C'est exactement le piège que le plan décrivait
  en théorie ; il était en production. À signaler à l'auteur.
Task 9: 10e/11e défauts de mes documents — `SectionHeader(title:)` n'existe pas
  (le vrai composant exige countText/moreTitle/moreDisabled/more) ; les clés
  L10n.Mods.name/version/folder/paused n'existaient pas, et Mods.enabled est un
  libellé pluriel de filtre inadapté à l'état d'un mod. 5 clés créées sous
  ModInstall en parité.
Task 9: revue dépêchée.
Task 9: revue — conformité ✅ (présentateurs 1 et 1, patron `presenting:`
  correct, 7 champs rendus, parité L10n, cliquet réconcilié ligne à ligne).
  Qualité : 0 critique, 2 IMPORTANTS, 2 mineurs.
Task 9: BUG DE PRODUCTION CONFIRMÉ par lecture de `git show 8c41912:` —
  `ModConfigBackupsView` remettait `backupToRestore` à nil à la fermeture puis
  le relisait dans l'action : « Restaurer » ne restaurait rien. Le relecteur
  ajoute que `delete` portait la MÊME exposition (corrigée par ricochet), et
  que `ModInstallBackupsView` y échappait parce qu'il utilisait un booléen
  simple qui ne remettait jamais la valeur à nil.

Ruling: T9 important 1 — `displayPath` et `replacedVersions` passent par
`StatColumn` en `lineLimit(1)` sans `help:`, alors que le composant documente
ce paramètre précisément pour le cas tronqué. Ce sont les deux champs les plus
longs, et la raison d'être du panneau était que sept champs ne tiennent pas
dans un paragraphe. Décision : fournir `help:` sur ces deux colonnes. Coût si
faux : deux infobulles de trop.

Ruling: T9 important 2 — RÉGRESSION INTRODUITE PAR LA CORRECTION. Fusionner
trois `@State` indépendants en un seul `confirmation` crée une collision que
les trois états séparés rendaient impossible : la complétion en tâche de fond
de `createBackup()` pose `.cleanup(...)` et peut ÉCRASER une confirmation
`.restore`/`.delete` déjà ouverte par l'utilisateur — le contenu de l'alerte
change sous ses yeux, et il valide autre chose que ce qu'il croit. Décision :
une pose spontanée ne doit pas écraser une confirmation déjà ouverte.
Pourquoi : c'est un bouton destructeur, et l'utilisateur confirmerait une
action qu'il n'a pas demandée. Coût si faux : un message de fin de sauvegarde
perdu quand une confirmation est ouverte — bien moindre que l'inverse.

Task 9: fix round 1/5 dépêché (2 importants)
Task 9: fix round 1/5 (2 traités, 0 ouvert ; commits 4194223..727d7e0).
  Garde de collision vérifiée atomique : la pose est déjà dans un
  `DispatchQueue.main.async`, lecture et écriture dans le même bloc sérialisé
  sur le fil unique. Comportement en collision : le toast de purge est perdu,
  la confirmation de l'utilisateur reste intacte — l'asymétrie voulue.
Task 9: minor (deferred): `isBusy` ne verrouille pas la liste pendant
  `performRestore`/`performDelete` — PRÉEXISTANT, non introduit par le lot.
  Ces chemins n'écrivent pas `confirmation` (ils passent par vm.alertMessage),
  donc pas de collision possible de ce côté.
Task 9: complete (commits 8c41912..727d7e0, review clean)
BASE tâche 10: 727d7e0
Task 10: implémenté (commit 41df924, gate exit 0, cliquet inchangé).
Ruling: T10 — revue par tâche FONDUE dans la revue globale. Pourquoi : c'est
  une tâche purement documentaire, sans code, dont le diff sera intégralement
  couvert par la revue de branche qui suit immédiatement ; une revue séparée
  dupliquerait le même examen à quelques minutes d'intervalle. L'édition de la
  ROADMAP a été vérifiée structurellement par l'implémenteur (diff = insertions
  + une seule suppression, décomptes d'identifiants voisins inchangés). Coût si
  faux : un défaut documentaire vu à la revue globale au lieu d'avant.
Task 10: complete (commits 727d7e0..41df924, revue fondue dans la globale)

=== TOUTES LES TÂCHES IMPLÉMENTÉES — revue globale de branche ===

=== REVUE GLOBALE DE BRANCHE — 7 bloquants ===

Ruling: GLOBAL-1 (CRITIQUE) — les notices bénignes de SMAPI sont résolues en
`HealthIssue .info` ET comptées dans `systemAlertCount`. Mesuré sur le vrai
journal de l'auteur : 0 failed, 0 skipped, 0 conflit — mais 7 notices bénignes.
Donc pastille à 7, tuile d'accueil en « attention », pied « 7 problèmes ·
0 critiques » sur un parc SAIN. `SmapiLogDiagnostics` documente pourtant ces
notices « These never count as problems » et les exclut de son `problemCount` —
le résolveur invoque cette autorité pour AJOUTER externalConflicts/brokenMods,
puis ajoute aussi ce qu'elle exclut. Deux lectures opposées de la même source.
  Décision : `.info` n'entre PAS dans le compte de la pastille ni dans le total
du pied. Les lignes `.info` restent AFFICHÉES dans la liste — la spec voulait
que le niveau ait une source réelle, elle ne voulait pas qu'il fasse sonner
l'alarme. Le compte devient donc « problèmes actionnables » = critique +
avertissement. Pourquoi : une pastille qui s'allume sur un parc sain apprend à
l'utilisateur à l'ignorer, ce qui détruit l'argument central du lot. Coût si
faux : une notice bénigne visible mais non comptée — exactement ce que le
parseur fait déjà.

Ruling: GLOBAL-2 (§2.2) — la disjonction failed ∩ skipped n'a jamais été
vérifiée ; un mod présent dans les deux produirait deux lignes critiques aux
titres différents. Le journal actuel est propre, donc non tranchable
empiriquement. Décision : poser le garde par symétrie avec celui de
`missingDeps` plutôt que d'attendre un journal qui le prouve. Pourquoi : le
garde coûte trois lignes, l'attente coûte un compteur faux non détecté. Coût si
faux : un garde inutile.

Ruling: GLOBAL-3 à 7 — les cinq autres bloquants sont des correctifs sans
arbitrage : libellé du bouton d'action, vocabulaire d'identité des lignes de
conflit, `activeConflictCount` qui doit dériver de `healthIssues` (exigence
explicite de la spec §6 bis, non faite), déclaration de la disparition des deux
écrans dans CHANGELOG et ROADMAP, et le collapse `let issues = vm.healthIssues`.

Ruling: GLOBAL-8 — le badge `.info` gris signifie « tout va bien » sur l'écran
des sauvegardes et « problème mineur » sur celui des alertes. Décision : la
vague de correction traite ce point avec GLOBAL-1, les deux étant le même
défaut de vocabulaire. Coût si faux : un libellé à revoir.

Vague de correction unique dépêchée (7 bloquants + 1 mesure).

=== RE-REVUE DE LA VAGUE FINALE : 7/7 traités, 0 régression ===

Ruling: RÉSIDU-1 — le pied affichera « 0 problème · 0 critique » au-dessus de
7 lignes visibles sur le parc actuel de l'auteur. Le relecteur confirme le
risque de lisibilité : sans le contexte, ça se lit comme un compteur cassé et
non comme une distinction voulue entre « affiché » et « actionnable ».
  Décision : PARQUÉ, remonté à l'auteur. Pourquoi : c'est une conséquence
directe de mon arbitrage GLOBAL-1, et le choix entre « ne plus afficher les
informations », « les compter à part » ou « laisser tel quel » relève de ce
qu'il veut voir sur SON écran, pas d'une règle technique. Le processus
n'autorise pas de seconde vague de correction. Coût si faux : un pied
déroutant jusqu'à sa décision.

Ruling: RÉSIDU-2 — `isSameMod` retire toujours le dernier mot du nom `skipped`.
Un mod « Mod » et un mod DIFFÉRENT nommé « Mod 2 » (où « 2 » fait partie du nom,
pas de la version) fusionneraient à tort. Décision : PARQUÉ. Pourquoi : bien
plus étroit que le défaut initial (égalité de mot exacte, pas de sous-chaîne),
jamais observé, et le garde reste défensif. Coût si faux : une ligne critique
manquante dans un cas de nommage improbable.

Ruling: RÉSIDU-3 — commentaire de doc périmé dans L10n.swift:745 (« le total
est healthIssues.count ») alors que le pied lit `actionableCount`. Décision :
PARQUÉ, pure documentation. Coût si faux : un commentaire faux de plus.
