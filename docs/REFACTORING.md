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
par domaine, et surtout leur exigence d'**un commit par étape numérotée**, pour qu'un
`git bisect` reste trivial.

**Écarté**, parce que dépendant d'une chaîne de build que nous n'avons pas : XcodeGen
(`project.yml`), les tests `XCUIApplication`, la capture d'écran automatisée, et leur
lanceur de tests maison (nous utilisons swift-testing via SwiftPM).

**Leurs correctifs pendant le refactor valent plus que leur plan.** C'est en les
lisant qu'on a trouvé le bloc de mises à jour SMAPI jamais détecté — bug réel,
présent à l'identique ici, corrigé le 2026-08-01 (`54113eb`).

## 4. Méthode

Une extraction se fait dans cet ordre, et chaque étape est un commit :

1. **Chercher la logique pure d'abord.** Un parseur, un calcul, une classification
   enfouis dans le ViewModel ou une vue. C'est là qu'est la valeur : ce code décide
   de ce que voit l'utilisateur, et personne ne le vérifie.
2. **Écrire les tests avant l'extraction**, sur le comportement existant. Un test qui
   n'a jamais été rouge ne prouve rien — le vérifier en cassant volontairement le
   code (fait pour le bloc des mises à jour).
3. **Déplacer sans modifier.** Swift n'ayant pas d'imports par fichier, un
   déplacement pur ne peut pas changer le comportement : si le build casse, ce
   n'était pas un déplacement pur.
4. **Traiter les violations de couche qui bloquent.** Un modèle qui prend le
   ViewModel en paramètre, ou qui porte un `Color`, ne peut pas entrer dans Core.
   Le remplacer par une **clé** ou un **état**, que la vue rend.
5. **Vérifier des deux côtés** : `./run_tests.sh` *et* `python3 build_app.py`.
   Aucun agent ne lance l'application — la vérification visuelle revient à l'auteur.

## 5. État

### Livré le 2026-08-01

| # | Domaine | Résultat |
| --- | --- | --- |
| 1 | **Journal SMAPI** | `LogEntry` sort du ViewModel (sa présentation `Color` l'en excluait) ; `SmapiLogParser` + le bloc des mises à jour passent en Core avec 13 tests. **Un bug réel corrigé** : les mises à jour signalées par SMAPI n'étaient jamais détectées. |
| 2 | **Catalogue des traductions** | `ThaiTranslationTable` en Core avec 11 tests ; `ThaiTranslationMod` perd ses deux méthodes prenant le ViewModel (une était morte). |
| — | **Comparaison de versions** | `NexusUpdateChecker` rejoint Core sans modification ; 11 tests sur `compare(_:_:)`. Aucun défaut, mais un comportement contraire à l'usage Stardew consigné en A2-T2. |

**F1-T1 est clos.** ViewModel : 4390 → 4153 lignes. 35 tests neufs sur du code qui
n'en avait aucun.

### Prochaines extractions, du moins au plus enchevêtré

| Ordre | Cible | Pourquoi |
| --- | --- | --- |
| 1 | `consolidateUpdatesByPack` + `pickHighestVersion` (~78 l.) | Transformations pures ; leur type est déjà en Core. Elles décident quelles mises à jour tu vois — un mauvais regroupement en fait disparaître une. |
| 2 | Registre des mods installés (~298 l.) | Version et date d'installation : de la logique de rapprochement, testable. |
| 3 | Profils (~115 l.) | Petit, mais la bissection s'appuie sur la même machinerie (dépendance croisée signalée dans `ROADMAP.md`) — extraire l'état avant les opérations. |
| 4 | Sauvegardes (~350 l., 4 sections éparpillées) | `SaveManager` est déjà en Core : le gain est surtout de lisibilité. |
| 5 | Le bloc de tête (~2000 l. non marquées) | Scan, filtres, dépendances. Le plus gros et le plus enchevêtré : à faire en dernier, par morceaux. |

**Règle permanente (F1-T2)** : une fonctionnalité neuve ne rentre plus dans le
ViewModel. Elle naît dans son propre type, que le ViewModel se contente d'appeler.
Le plan du hub de traduction la respecte déjà.

## 6. Ce que ce plan ne fait pas

- **Pas de big-bang.** La roadmap l'exclut explicitement : sans filet de test sur
  l'UI, un refactor massif ne se vérifie pas.
- **Pas de renommage de masse.** Leur phase 6 (balayage de nommage) touche des
  centaines d'appels pour un gain cosmétique ; sans revue automatisée, le rapport
  risque/valeur est mauvais ici.
- **Pas de conversion à la concurrence structurée** (leur phase 5) tant que les
  domaines ne sont pas séparés : `@MainActor` sur un fourre-tout de 4000 lignes
  révélerait des dizaines de problèmes réels d'un coup, sans moyen de les isoler.
