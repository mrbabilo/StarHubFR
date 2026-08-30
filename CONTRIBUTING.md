# Contribuer à StarHubFR

Merci de votre intérêt pour StarHubFR, le hub de gestion et de traduction française pour mods Stardew Valley ! Ce document explique comment participer efficacement au projet.

## Façons de contribuer

- **Signaler un bug** : mod non détecté, erreur d'installation, crash SMAPI, etc.
- **Proposer une traduction** : améliorer ou compléter la couverture FR d'un mod.
- **Corriger ou améliorer le code** : Swift, logique de scraping Nexus, interface.
- **Améliorer la documentation** : README, guides, captures d'écran.

## Avant de commencer

1. Vérifiez les [issues existantes](../../issues) pour éviter les doublons.
2. Pour un changement important (nouvelle fonctionnalité, refonte), ouvrez d'abord une issue de discussion avant de coder.
3. Pour une correction mineure (typo, petit bug), une pull request directe est bienvenue.

## Workflow de contribution

1. Forkez le dépôt et créez une branche depuis `main` :
   `git checkout -b fix/nom-court-descriptif`
2. Faites vos modifications avec des commits clairs et atomiques (un commit = un changement logique).
3. Lancez les tests localement avant de proposer votre PR :
   `./run_tests.sh`
4. Vérifiez les standards du projet :
   `python3 check_standards.py`
5. Ouvrez une pull request vers `main` avec :
   - Un titre clair décrivant le changement.
   - Une description du problème résolu ou de la fonctionnalité ajoutée.
   - Des captures d'écran si l'interface est modifiée.

## Convention de commits

Utilisez des messages de commit en anglais ou en français, au format impératif court :
- `fix: corrige la détection SMAPI sur macOS 15`
- `feat: ajoute le filtre par catégorie de mod`
- `docs: complète le guide d'installation`

## Contribuer une traduction

Les traductions de mods sont au cœur de StarHubFR. Pour proposer ou corriger une traduction :

1. Identifiez le mod concerné et sa fiche Nexus Mods.
2. Suivez le format de traduction déjà utilisé par les autres mods du projet (voir le dossier `docs/` pour les conventions).
3. Précisez dans votre PR le nom du mod, sa version, et la source de la traduction (traduction originale, adaptation, etc.).
4. Respectez le droit d'auteur : ne proposez que des traductions que vous avez le droit de partager.

## Style de code Swift

- Respectez le style déjà en place dans le projet (indentation, nommage).
- Préférez des fonctions courtes et documentées avec des commentaires `///` pour les API publiques.
- Évitez d'introduire de nouvelles dépendances externes sans discussion préalable.

## Rapporter un bug

Utilisez le template d'issue "Bug SMAPI / installation" ou "Mod non détecté" selon le cas. Plus votre rapport est précis (version de StarHubFR, OS, logs SMAPI, étapes de reproduction), plus vite il pourra être traité.

## Code de conduite

Ce projet suit un principe de respect mutuel : soyez bienveillant, constructif, et patient avec les autres contributeurs et utilisateurs, qui viennent d'horizons et de niveaux techniques variés.

## Questions

Pour toute question qui ne rentre pas dans le cadre d'un bug ou d'une feature, ouvrez une issue avec le label `question` ou utilisez les Discussions du dépôt si elles sont activées.
