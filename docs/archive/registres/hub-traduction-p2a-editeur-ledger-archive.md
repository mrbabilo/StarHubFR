# Archive du ledger SDD — hub-traduction-p2a-editeur-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-15-hub-traduction-fr-phase2a-editeur/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-15-hub-traduction-fr-phase2a-editeur.md`.

2026-08-15-hub-traduction-fr-phase2a-editeur.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-15-hub-traduction-fr-phase2a-editeur.md

## État à l'ouverture du ledger

Les tâches 1 à 6 ont été exécutées **hors SDD**, à la main, plus tôt dans la
session, et sont poussées sur `main` (`5fbdb55..78dbd1e`). 832 tests verts,
build vert. Elles ne sont pas à redispatcher.

- Task 1: complete (commit 9739e8e, hors SDD) — OrderedJSONWriter
- Task 2: complete (commit 553407c, hors SDD) — TranslationTokenCheck
- Task 3: complete (commit a4f120d, hors SDD) — TranslationComponentResolver
- Task 4: complete (commit e1884ef, hors SDD) — TranslationDocument
- Task 5: complete (commit 7daf07d, hors SDD) — TranslationFileStore
- Task 6: complete (commit 41baa8e, hors SDD) — TranslationWaiver
- Hors plan, issus d'une revue par agents : 6068662 (3 marques coupées),
  81dff53 (plantage clé en double, perte muette, gourmandise `#$`)

Reste : tâches 7 (câblage ViewModel) et 8 (éditeur SwiftUI).

## Rulings de préflight

Ruling: rester sur `main` sans worktree — `CLAUDE.md` prescrit « Travailler sur
main », instruction de projet qui prime sur le défaut du skill, et les 9
commits du jour y sont déjà. Coût si faux : les commits des sous-agents
atterrissent sur main ; atténué par le fait que rien n'est poussé sans
demande explicite de david.

Ruling: annuler ma modification non commitée de la tâche 7 (~70 lignes du
ViewModel, jamais buildée) avant de dispatcher — sinon l'implémenteur hérite
d'un travail qu'il n'a pas écrit et la revue rubber-stamp mon code au lieu de
le contrôler. Coût si faux : quelques minutes de réécriture.

Ruling: pas de revue finale sur toute la branche au sens du skill — le
périmètre livré aujourd'hui (tâches 1-6) a déjà reçu une revue par agents,
dont les constats sont corrigés et poussés. La revue finale portera sur les
seules tâches 7 et 8. Coût si faux : un défaut d'intégration entre le Core
déjà revu et le nouveau câblage passe inaperçu ; atténué parce que la revue
finale voit le diff 7+8 dans son entier.

## Scan de préflight (tâches 7 et 8)

| Ce qui est vérifié | Constat |
|---|---|
| T7 produit `saveTranslation(mod:locale:row:value:acceptingTokenMismatch:)` / T8 le consomme | Signatures identiques dans les deux textes. Accord. |
| T7 consomme `TranslationDocument`, `TranslationFileStore`, `TranslationComponentResolver`, `TranslationWaiver`, `TranslationTokenCheck` | Les cinq existent, livrés en tâches 2-6, signatures vérifiées à la main avant l'ouverture du ledger. Accord. |
| T8 consomme `TranslationCoverage.DiffRow` (`key`, `english`, `french`, `state`, `component`, `id`) | Tous présents (phase 1). `id` vaut `component/key`. Accord. |
| T8 modifie `TranslationDiffView` que T7 ne touche pas | Pas de conflit de fichier. |
| T7 : cohérence interne (texte contre code) | Le texte dit « ne rien écrire dans le baseline ici », et le code qu'il donne écrit **l'accord** dans le baseline. Ce n'est pas une contradiction : la référence anglaise est adoptée par `TranslationBaselineRules`, l'accord non. Levée par le commentaire du code. |
| T8 : cohérence interne | Les 9 clés L10n sont déclarées trois fois chacune (fr, en, L10n.swift). Parité tenue. |
| Contrainte globale « aucun test ne touche `UserDefaults.standard` ni le dossier `Mods/` réel » | T7 et T8 n'ajoutent aucun test (code ViewModel/UI). Sans objet. |

Scan clos, aucun conflit à arbitrer.

## Exécution

Task 7: dispatché (implémenteur sonnet, BASE 78dbd1e) — câblage `saveTranslation` au ViewModel
Task 7: rendu DONE_WITH_CONCERNS (commit 2f58fb9, 832 tests verts, build vert, cliquet try_optional 190→191)
Task 7: Ruling: la consultation de `TranslationWaiver.isAccepted` appartient à `saveTranslation`, pas à l'UI — c'est là que la décision de bloquer se prend, et l'interface n'a pas à connaître le magasin de dérogations. Motif aggravant : le commentaire écrit par l'implémenteur promettait déjà ce comportement, que le code ne faisait pas (même famille que le paramètre `force` retiré hier). Renvoyé à l'implémenteur avant revue, réserve de correction. Coût si faux : la lecture disque se paie au mauvais endroit, à déplacer vers l'UI en tâche 8.
Task 7: Ruling: réserve n°3 acceptée sans changement — `acceptingTokenMismatch` figure au contrat d'interface du brief, et `@MainActor` est imposé par le compilateur. Coût si faux : nul, les deux écarts sont documentés au commit.
Task 7: correction rendue (commit bda6e82) — `saveTranslation` consulte désormais l'accord ; clé orpheline vérifiée sans changement (elle tient son rang du fichier cible, pas de la source)
Task 7: revue dispatchée (opus, diff 78dbd1e..bda6e82) — modèle haut de gamme délibérément : premier code du projet qui écrit dans le dossier de mods réel
Task 7: revue opus décrochée après 600 s, sans rendre un constat (4e décrochage de la session)
Task 7: Ruling: redispatcher la revue sur `sonnet` plutôt que sur le modèle le plus capable. Motif empirique : sur 7 agents de la session, les 4 décrochages sont tous sur le modèle haut de gamme, et les 3 aboutis sur sonnet — dont l'implémenteur de cette même tâche, qui lisait le même brief. Une revue qui aboutit vaut mieux qu'une revue haut de gamme qui n'arrive jamais. Coût si faux : la revue rate un défaut subtil qu'un modèle plus capable aurait vu ; atténué par la revue finale sur le diff 7+8 et par la vérification humaine dans l'app.
Task 7: revue rendue — conformité ✅, qualité NON approuvée : 2 Critiques, 1 Important, 1 Mineur
Task 7: Ruling: les deux Critiques sont **des défauts de mon plan**, pas de l'implémenteur — le Step 2 du brief dictait verbatim le code fautif. Je tranche en faveur des constats contre le texte du plan : la spec (« ne jamais casser un fichier ») est l'autorité, et le brief contredit ce que `I18nLocaleResolver` documente explicitement. Vérifié moi-même : le module dit « composer `i18n/<langue>.json` à la main revient à afficher "pas de traduction" sur un mod traduit », et le parc porte 7 dossiers en layout B dont 5 avec du français (dont un dossier `Fr` majuscule). Coût si faux : nul, les constats sont prouvés sur données réelles.
Task 7: Ruling: l'Important (échec indistinguable d'un succès pour l'appelant) entre aussi dans la boucle, et la signature devient un `SaveOutcome` à trois cas. La tâche 8 n'étant pas écrite, changer le contrat maintenant ne coûte rien ; plus tard, il aurait fallu reprendre l'UI. Coût si faux : une énumération là où un `throws` aurait suffi.
Task 7: fix round 1/5 dispatché (4 constats, implémenteur repris)
Task 7: fix round 1/5 — implémenteur interrompu par une mise en veille machine pendant la rédaction du rapport, MAIS le correctif était commité (96fb1fc) et l'arbre propre. Vérifié moi-même plutôt que cru : 832 tests verts, build vert, cliquet intact, et les 4 constats traités dans le code (layout B via I18nLocaleResolver.files, clé repliée, SaveOutcome à 3 cas, échec d'accord journalisé). Rapport de correction probablement incomplet.
Task 7: fix round 1/5 (4 traités, 0 ouvert ; commits bda6e82..96fb1fc) — re-revue ciblée : aucune casse nouvelle
Task 7: minor (deferred): en layout B, le fichier *source* servant à la garde de lisibilité et à l'ordre des clés neuves est choisi par correspondance de nom avec la cible, à défaut le premier de `sourceFiles`. Si les noms divergent entre `default/` et `<locale>/`, l'heuristique peut viser un source sans rapport. Pire cas : un faux refus (`.failed`), jamais une écriture au mauvais endroit — `target`/`realKey` restent corrects. À trier par la revue finale.
Task 7: complete (commits 78dbd1e..96fb1fc, revue clean)

Task 8: rendu DONE (commit 88a9539, 832 tests verts, build vert)
Task 8: Ruling: cliquet relevé par `--update` sur `abbreviation_vm` (+15) et `vm_dot_L_calls` (+10) — accepté. Ce sont les deux compteurs de l'idiome dominant de `Views/` (`vm.L(...)`), et j'ai relevé les mêmes moi-même plus tôt dans la session pour la même raison. `try_optional` n'a **pas** bougé, c'est celui qui compte. Coût si faux : deux compteurs plus permissifs de 25 unités sur un fichier d'UI neuf.
Task 8: revue dispatchée (sonnet, diff 96fb1fc..88a9539)
Task 8: revue rendue — conformité ✅, qualité approuvée, 1 Important + 2 Mineurs
Task 8: Ruling: l'Important (zone `statusNotice` à hauteur fixe qui tronque le message d'échec et coupe l'indice sur l'accord) vient de **mon brief**, qui imposait 36pt et des `lineLimit`. Je tranche contre le texte du plan : garder la hauteur fixe — l'intention (ne pas faire sauter le champ entre deux clés) est juste — mais la dimensionner sur le pire cas. Coût si faux : quelques points de hauteur en trop sur une feuille de 470pt.
Task 8: minor (deferred): `staleness` n'est pas rafraîchi par `onSaved` — le bandeau « l'anglais a été modifié après le français » peut rester affiché sur une clé qu'on vient de retraduire. Correctif d'une ligne. À trier par la revue finale.
Task 8: minor (deferred): deux points non vérifiables par lecture, à confier à la vérification humaine — `.onTapGesture` sur une rangée qui contient déjà du texte sélectionnable (clic contre clic-glissé), et `.keyboardShortcut(.defaultAction)` alors que le focus est dans un `TextEditor` multi-ligne (Retour pourrait insérer un saut de ligne).
Task 8: fix round 1/5 dispatché (1 Important)
Task 8: fix round 1/5 (1 traité, 0 ouvert ; commits 88a9539..3b21836) — hauteur vérifiée par calcul indépendant (315 car. pour le pire message, 155 mesurés dans fr.json pour l'indice), hauteur restée fixe
Task 8: minor (deferred): au-delà des pires cas calculés (marge 8-19pt), un contenu trop haut ne se coupe pas mais **chevauche** la rangée de boutons — `.frame(height:)` impose au parent sans clipper. Conséquence assumée du choix hauteur fixe + retrait des lineLimit, pas une régression.
Task 8: complete (commits 96fb1fc..3b21836, revue clean)

## Revue finale (tâches 7 et 8)
Revue finale rendue — NON livrable en l'état : 2 bloquants confirmés par moi dans le code.
Ruling: bloquant 1 confirmé — `guard let found else { return .failed }` (VM:573) refuse toute clé absente des fichiers de la locale **dès que `localeFiles` n'est pas vide**. Sur un mod déjà partiellement traduit (layout A, un seul `fr.json`), traduire une clé `.missing` échoue donc systématiquement : c'est le cas d'usage central de l'écran. Le garde-fou écrit pour l'ambiguïté du layout B capture aussi le layout A, où il n'y a aucune ambiguïté. Coût si faux : nul, vérifié ligne à ligne.
Ruling: bloquant 2 confirmé — `invalidateFrenchCoverage` (VM:689) vide `frenchCoverageByMod`/`staleTranslationMods` sans republier `mods`. Les deux autres appelants (deleteMod:4860, ModInstallView:555) enchaînent sur un `refresh()`/`scanMods()` ; `saveTranslation` non. La carte de couverture disparaît de la fiche mod après le premier enregistrement, jusqu'à la fin de la session. Coût si faux : nul, les trois appelants comparés.
Ruling: une seule vague de correctifs pour les 4 points (2 bloquants + staleness + garde « rien n'a changé »), confiée à l'implémenteur de la tâche 7 qui a écrit `saveTranslation`. Coût si faux : le correctif de vue est fait par qui ne l'a pas écrite.
Vague de correctifs finale rendue (commit 56b9315, 832 tests verts, build vert, cliquet abbreviation_vm +1)
Ruling: réserve de l'implémenteur sur la garde « rien n'a changé » — examinée et **non fondée**. Le bouton « Enregistrer quand même » n'apparaît que si `blocked` est non vide, `blocked` n'est peuplé que par une sauvegarde ayant franchi la garde, et `onChange(of: draft)` le vide dès que le texte revient à l'identique. Aucun chemin ne rend le bouton cliquable pendant que la garde s'appliquerait. Coût si faux : un accord de dérogation impossible à donner sans retoucher le texte.
