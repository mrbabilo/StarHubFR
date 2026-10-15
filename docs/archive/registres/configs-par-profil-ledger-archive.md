# Archive du ledger SDD — configs-par-profil-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-27-configs-par-profil/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-27-configs-par-profil.md`.

2026-08-27-configs-par-profil.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-27-configs-par-profil.md

Spec: docs/superpowers/specs/2026-08-27-configs-par-profil-design.md (lue)

## Rulings de pré-vol

Ruling: exécution sur `main`, sans worktree — CLAUDE.md dit « Travailler sur
`main` » et c'est une consigne explicite de l'utilisateur, qui prime sur le
défaut de la skill. Coût si faux : des commits sur main à défaire par
`git reset`, jamais poussés (pousser demande sa demande explicite).

Ruling: modèle `sonnet` pour tous les implémenteurs et relecteurs de tâche,
`opus` pour la relecture finale. Le plan porte le code complet (transcription),
mais l'environnement de build est capricieux — `run_tests.sh` peut échouer sur
`no such module 'Testing'`, `build_app.py` dure 8 à 12 min et son code de
sortie se perd s'il est pipé. Un modèle trop faible qui s'y enlise coûte plus
que l'économie. Coût si faux : quelques euros de plus.

## Scan de pré-vol — table

| Paire / tâche | Ce qui est partagé | Constat |
|---|---|---|
| T1 → T3 | `ProfileConfigStore.{fileURL,load,save,captured,configURL}`, `ProfileConfigEntry` | OK — T3 n'appelle que ce que T1 déclare |
| T1 → T4 | `ProfileConfigStore.{fileURL,load,configURL}` | OK |
| T2 → T3 | `vm.profileManagedConfigMods` | OK |
| T2 → T4 | `canManageProfileConfig`, `isProfileConfigManaged`, `setProfileConfigManaged` | OK après correction (voir ruling ci-dessous) |
| T2 → T5 | `isProfileConfigManaged` | OK |
| T3 → suite | `captureProfileConfigs`, `restoreProfileConfigs` | Consommés par personne — internes à `applyProfile` |
| T4 → interne | `profileConfigHolders`, `resetModConfigToDefaults`, `configHolders`, `refreshConfigHolders` | OK — définis et employés dans T4 |
| T2, T3, T4 | `StarHubTHViewModel.swift` | Séquentiel et additif — pas de collision |
| T3, T4, T5 | `L10n.swift`, `assets/{en,fr}.json` | Clés disjointes (`vm_profile_configs_*` / `mods_profile_config_*`) — additif |
| T1 (interne) | tests ↔ implémentation | OK — toutes les signatures des tests existent dans le code de T1 |
| T3 (interne) | code ↔ clés L10n | OK — les 3 clés employées sont déclarées au Step 1 |
| T4 (interne) | code ↔ clés L10n | OK — les 9 clés employées sont déclarées au Step 1 |
| T5 (interne) | code ↔ clé L10n | OK — la clé employée est déclarée au Step 1 |
| T3 (interne) | journal de capture | **DÉFAUT** — voir ruling |

Ruling: le journal de capture annonçait `entries.count`, le total du magasin,
là où le journal de restauration annonce ce que la passe a écrit. « 12 configs
mémorisés » quand un seul a bougé aurait donné une fausse idée du geste. Plan
corrigé avant dispatch : compte des entrées ajoutées, changées ou retirées.
Coût si faux : un nombre trompeur dans le journal, corrigible en une ligne.

Ruling: `.superpowers/` n'était pas dans `.gitignore` alors que la skill le
suppose ignoré. Ajouté — sans quoi l'espace de travail entrerait dans les
commits. Coût si faux : aucun, c'est du scratch.

## Progression

Task 1: complete (commits da4742d..d1b93e5, 10 tests verts, 1468 au total)

Ruling: cliquet `try_optional` relevé de 4 (256→260) plutôt que corrigé. Les
quatre `try?` sont ligne pour ligne ceux de `TranslationCoverageCache`
(119, 128, 136, 137) — convention du dépôt pour un magasin sur disque, pas un
patron qu'on regretterait. Coût si faux : 4 points de dette de plus au compteur,
annulables par un `--update` après correction.

Ruling: **défaut de plan de ma part.** Le plan figeait
`Co-Authored-By: Claude Opus 5` dans les 6 messages de commit, alors que les
implémenteurs tournent sur Sonnet 5 et que CLAUDE.md interdit un nom figé.
L'implémenteur de T1 a suivi le brief et signalé le conflit — il avait raison.
Commit de T1 amendé en `Claude Sonnet 5` ; les 5 blocs restants du plan portent
désormais `<MODÈLE ACTIF>` avec la consigne de le remplacer. Coût si faux :
un trailer inexact dans l'historique, amendable tant que rien n'est poussé.
Task 1: review clean (spec ✅, quality Approved)
Task 1: important (résolu par le contrôleur) — rapport périmé après mon amend ;
  note de correction ajoutée au rapport. Le reviewer a lui-même vérifié que le
  code est identique à l'octet près entre le commit testé et le commit final.
Task 1: minor (deferred): `saveThenLoadRoundTrips` n'assure que `text`, pas `capturedAt`
Task 1: minor (deferred): pas de fixture CRLF ni de clé avec `/` à travers save→load
  (seulement à travers `captured`/`configURL` isolés) — le dépôt s'est déjà fait
  mordre deux fois par CRLF, c'est le mineur le plus susceptible de compter
Task 1: minor (deferred): `load` non testé sur fichier vide ni sur JSON valide mais mal formé (`[]`)
Task 1: minor (deferred): `fileURL` — seule fonction à effet de bord — sans test
Task 1: complete (commits da4742d..d1b93e5, review clean, 4 minors deferred)

Task 2: implémentée (commit 8d48a8c), build EXIT=0 après relevé de cliquet
  (try_optional 260→262).

Ruling: **ne pas purger** `profileManagedConfigMods` à la suppression définitive
d'un mod, contrairement à `favoriteMods` qui purge. L'asymétrie est voulue : le
§6.5 de la spec promet qu'un config mémorisé pour un mod désinstallé est gardé,
« réinstaller le mod doit lui rendre ses réglages ». Purger la marque ferait
mentir cette promesse — le mod reviendrait démarqué et son config mémorisé
dormirait sans que rien ne le rejoue. Un favori, lui, ne décrit qu'un goût :
il n'a rien à rendre. Coût si faux : quelques noms morts dans un `Set` de
préférences, purgeables en une ligne.

Ruling: la couture logique/physique signalée par l'implémenteur pour T3 est
**déjà traitée dans le plan** — `managedConfigTargets()` filtre sur
`$0.folderName` (logique) et bâtit l'URL avec `$0.physicalFolderName`. À porter
dans le dispatch de T3 pour que l'implémenteur ne « corrige » pas ce qui est
juste. Coût si faux : nul, c'est une vérification.
Task 2: review clean (spec ✅, quality Approved)

Ruling (maintenu, contre l'avis du relecteur de T2) : toujours **ne pas purger**.
Son contre-argument, consigné pour la relecture finale : « réinstaller un dossier
sous le même nom est courant à ~900 mods ; la marque périmée ressuscite en
silence, et la restauration de T3 écrirait alors dans la nouvelle installation
un config capturé sur une installation précédente et sans rapport. »
Pourquoi je maintiens : le cas qu'il décrit et celui que la spec vise sont le
même geste vu de deux côtés. §6.5 tranche explicitement — « réinstaller le mod
doit lui rendre ses réglages » — et l'utilisateur a validé cette spec. Le seul
cas où son objection mord vraiment est un dossier de même nom portant un *autre*
mod, ou une version majeure dont le schéma de config a changé ; dans le second,
SMAPI recomble les clés manquantes par leurs défauts et ignore les mortes, donc
pas de perte. Et la fiche annonce « diffère du disque » : l'état est visible.
Coût si faux : un config périmé réécrit dans un mod fraîchement réinstallé,
visible sur sa fiche et annulable par le bouton « repartir des défauts ».

Task 2: minor (résolu par le relecteur, pas différé) — `isProfileConfigManaged`
  ne re-teste pas `!mod.isGroup` : correct ainsi, un getter doit dire
  l'appartenance réelle. Vérifié côté consommateurs : `managedConfigTargets()`
  (T3) aplatit les packs et n'en retient que les composants ; la vue (T4) borne
  déjà `isProfileConfigManaged` dans la branche `canManageProfileConfig`.
  Aucun changement nécessaire.
Task 2: complete (commits d1b93e5..8d48a8c, review clean)

Task 3: implémentée (commit 7d3878a), build EXIT=0, invariant §6.3 prouvé par
  grep (2 déclarations, 3 appels, tous entre les lignes 7062 et 7110
  d'`applyProfile`, aucun dans `applyProfileToFilesystem` ni `applyEnabledFolders`).

Ruling: **défaut de spec, trouvé par l'implémenteur. À corriger, pas à parquer.**
Le §6.4 dit « si le jeu tourne, la moitié configs ne s'exécute pas du tout ».
J'avais raisonné que c'était équivalent au premier passage. C'est faux, et le
chemin de perte est exactement celui que le §6.3 devait fermer :
  1. A actif, jeu ouvert, l'utilisateur bascule vers B.
  2. Les dossiers bougent. Capture et restauration sautées.
  3. Le disque porte les configs de A ; B est désormais le profil actif.
  4. Plus tard, jeu fermé, l'utilisateur bascule B → C.
  5. `captureProfileConfigs(for: B)` lit le disque — qui porte ceux de **A** —
     et les mémorise au crédit de **B**.
Les réglages de A entrent dans le magasin de B, en silence. Parquer un défaut
qui détruit des données serait indéfendable : passage en ronde de correction 1/5.
Correctif retenu, le plus petit qui ferme le trou : une clé de préférences
retenant « ce profil est actif mais le disque ne porte pas ses configs », posée
quand la moitié configs est sautée, consultée par la capture, effacée par une
transition normale. Persistée, car quitter l'app entre les deux ramènerait le bug.
Coût si faux : une capture sautée de trop après un redémarrage — le profil garde
ses configs mémorisés précédents, rien n'est écrasé.
Task 3: fix round 1/5 (1 addressed, 0 open — trou de désynchronisation jeu ouvert ;
  commits 7d3878a..5a956eb)
Task 3: review clean (spec ✅, quality Approved, 5 questions tracées dans le code)

Ruling: **accepter** la nuance relevée par le relecteur — quand la marque fait
sauter la capture du profil sortant, la restauration du profil entrant tourne
quand même. C'est juste : les configs mémorisés du profil entrant sont bien les
siens. Le coût réel est ailleurs et il est celui, assumé, du §6.4 : une bascule
faite jeu ouvert ne mémorise pas les réglages courants du profil sortant, et la
bascule suivante les recouvre. L'utilisateur en est averti **au moment où ça
arrive** (« Configs non touchés : le jeu est ouvert »). L'alternative — refuser
la bascule entière quand le jeu tourne — est un changement de comportement que
le plan exclut explicitement. À dire dans le CHANGELOG (T6) : basculer de profil
jeu ouvert ne mémorise rien. Coût si faux : des réglages perdus pour qui bascule
jeu ouvert malgré l'avertissement.

Task 3: complete (commits 8d48a8c..5a956eb, review clean, 1 fix round)

Task 4: implémentée (commit e8b697a), build EXIT=0 après relevé de cliquet
  (abbreviation_vm 2044→2058, vm_dot_L_calls 1088→1096, try_optional 263→264 —
  l'idiome `vm.`/`vm.L` des vues, convention du dépôt).
  L'agent a calé deux fois en lançant son build en arrière-plan puis en
  s'arrêtant pour l'attendre ; réveillé deux fois, aucun travail perdu.

Ruling: le constat de l'implémenteur est **réel** — basculer l'état actif d'un
mod change son `physicalFolderName`, donc le fichier que `matchesDisk` compare
n'est plus là, et la fiche affiche « diffère du disque » à tort jusqu'à
réouverture. Ce n'est pas une perte de données, mais c'est précisément le signal
que j'ai ajouté pour que l'absence d'effet ne se lise pas comme une panne : un
« différent » faux est pire que pas d'étiquette. Correctif : un `.onChange(of:
mod.isEnabled)` qui rappelle `refreshConfigHolders()`. **Plié dans le dispatch
de T5** plutôt qu'en ronde de correction — T5 touche déjà des vues et paie déjà
un build de 8 à 12 min ; une ronde séparée en paierait un second pour une ligne.
Coût si faux : une ligne à retirer.
Task 4: review 1 — spec ✅, quality NON approuvée (1 Critical, 1 Important, 1 aggravation)

Ruling: le « Critical » du relecteur (dossiers de mods en 0555) est **réel mais
mal calibré**. Il cite le commentaire de `FileRecovery.swift` — « une bonne part
du parc a ses dossiers en 0555 ». Mesuré aujourd'hui sur le parc : **1 dossier
sur 1015**. Le commentaire du dépôt est périmé. J'ai fait corriger quand même :
le piège est réel, les archives le ramènent, et il touche surtout
`restoreProfileConfigs` qui écrit à *chaque* bascule. Outil retenu :
`RecoveredFileWriter.withWriteAccess` plutôt que celui proposé par le relecteur,
parce qu'il **rend les droits tels qu'il les a trouvés** — un mod doit rester
comme son auteur l'a empaqueté. Coût si faux : quelques lignes de plus sur deux
chemins d'écriture, sans effet observable.

Ruling: **mon correctif du tour précédent était faux.** J'avais prévu un
`.onChange(of: mod.isEnabled)` ; le relecteur a vu que `mod` est une copie figée
prise à l'ouverture de la fiche (ModDetailView:235 documente `live` pour cette
raison exacte) — le `.onChange` n'aurait jamais tiré, et toute la section visait
un chemin périmé après une mise en pause. Corrigé en passant par `live`.
Le regroupement des trois constats en une seule ronde a économisé un cycle de
build. Coût si faux : nul, c'est la correction d'une erreur de ma part.

Task 4: fix round 1/5 (3 addressed — droits 0555, no-op silencieux du bouton,
  copie figée vs `live` ; commits e8b697a..718d1b7)
Task 4: re-review — 3/3 ADDRESSED (droits ouverts puis rendus, no-op journalisé,
  `live` partout + `.onChange(of: live.isEnabled)`). 1 nouveau Important né du
  correctif.

Ruling: le nouveau Important est **ma phrase**. J'avais dicté « SMAPI en écrira
un au prochain lancement » pour le cas « aucun config.json à supprimer ». C'est
faux pour la majorité des mods concernés : un mod qui n'appelle jamais
`helper.ReadConfig<T>()` n'aura jamais de config.json — ma propre mesure le dit
(547 dossiers sur 1015 en portent un, donc ~46 % n'en auront jamais). Le message
promet quelque chose qui n'arrivera pas. Corrigé en retirant la promesse.
Coût si faux : une phrase à réécrire.

Ruling: ce correctif de chaîne, plus le journal de succès resté **en dur en
français** (`"config.json supprimé : %@"`, relevé en différé par le relecteur —
l'app est bilingue), sont **portés dans le dispatch de T5** au lieu d'une ronde 2.
T5 touche déjà `L10n.swift` et les deux fichiers d'assets, et paie déjà un build
de 8 à 12 min ; une ronde séparée en paierait un second pour deux chaînes. Ce
n'est pas un abandon : les deux sont nommés comme obligations dans le dispatch
de T5 et seront relus avec lui. Coût si faux : deux chaînes qui traînent d'une
tâche, visibles dans la relecture finale.

Task 4: complete (commits 5a956eb..718d1b7, 1 fix round, 2 chaînes reportées en T5)

Task 5: implémentée (commit 3f1f4cc), build EXIT=0 au premier plan après relevé
  de cliquet. Icône + cible 18×18 + les 2 chaînes reportées de T4.

Ruling: l'implémenteur signale que la fausse promesse corrigée dans la chaîne
subsiste dans le **commentaire de doc** de `resetModConfigToDefaults` (« SMAPI le
réécrit au prochain lancement »). Il a eu raison de ne pas y toucher — hors de son
périmètre. Porté dans T6 : c'est la dernière tâche, elle paiera un build complet
qui vaudra de toute façon comme validation finale de l'ensemble livré. Coût si
faux : un commentaire faux de plus dans le code, sans effet utilisateur.
Task 5: review clean (spec ✅, quality Approved — chaîne de modificateurs
  identique à l'icône des notes, les 2 chaînes reportées de T4 vérifiées en place,
  cliquet expliqué à 100 % par le code ajouté)
Task 5: complete (commits 718d1b7..3f1f4cc, review clean)

Ruling: `docs/ROADMAP.md` et `.gitignore`, tenus hors périmètre depuis T1, entrent
dans le commit de T6. Le bloc ROADMAP est l'instruction de ce chantier et
l'entrée de T6 s'y raccroche ; l'ajout de `.superpowers/` au `.gitignore` est ce
qui a empêché l'espace de travail d'entrer dans les commits. Les garder hors de
l'historique en ferait des orphelins non versionnés. Coût si faux : deux fichiers
de plus dans un commit de documentation.
Task 6: implémentée (commit 56f155f) — 1468 tests verts, build EXIT=0, cliquet
  immobile. CHANGELOG (limite jeu ouvert dite), ROADMAP (B3-T5 décochée),
  commentaire à fausse promesse réécrit, `.gitignore` et le bloc ROADMAP commités.

Ruling: **pas de relecture de tâche séparée pour T6**, fondue dans la relecture
finale de branche. T6 ne touche aucun code produit hors un commentaire de doc ;
la relecture finale tourne sur le modèle le plus capable et couvre le même diff,
en plus du reste. Une relecture sonnet du commit de docs serait strictement
dominée. Ses exigences propres (style du CHANGELOG, B3-T5 restée décochée,
véracité du commentaire) sont nommées dans le dispatch final. Coût si faux : un
défaut de documentation qui passerait la relecture finale.
