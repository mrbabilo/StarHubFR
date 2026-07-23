> [!IMPORTANT]
> Ce fork ajoute le support de la langue française, ainsi qu'une UX/UI « french touch ». Pour la version originale en thaï, consultez le [README thaï](README_TH.md). Pour la version anglaise, consultez le [README anglais](README_EN.md).

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0288D1?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://www.python.org"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python"></a>
  <a href="#"><img src="https://img.shields.io/badge/Plateforme-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Licence-MIT-yellow" alt="MIT License"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="Fonctionnalités principales" width="300">
</p>

*   **Lancement facile du jeu** : Lancez Stardew Valley en mode Vanilla (original) ou via SMAPI pour jouer avec des mods.
*   **Gestionnaire de Mods** : Activez ou désactivez vos mods facilement grâce à une interface élégante — plus besoin de déplacer les fichiers manuellement.
*   **Installation de Mods par Glisser-Déposer** : Glissez un fichier `.zip` directement dans l'application pour installer un ou plusieurs mods. Détection automatique de la structure (mono-mod, pack multi-mods), validation d'intégrité (anti-zip-bomb, < 500 Mo), aperçu des conflits et suggestions de dépendances manquantes.
*   **Profils de Mods** : Regroupez vos mods dans plusieurs profils et passez de l'un à l'autre en un seul clic.
*   **Centre de Traductions Thaï** : Un espace dédié listant tous les mods de traduction en thaï — parcourez, vérifiez le statut, téléchargez et suivez les mises à jour au même endroit.
*   **Vérification des Mises à jour Nexus Mods** : Vérifiez manuellement les mises à jour de vos mods via l'API Nexus Mods. Clé API stockée en toute sécurité dans le trousseau macOS (Keychain), détection des mises à jour même à version identique (comparaison de date d'upload).
*   **Sauvegardes de Mods** :
    *   *Sauvegarde d'installation* : Sauvegarde automatique avant l'écrasement d'un mod, avec rétention hybride (5 plus récents + ≤30 jours + 1 par mois au-delà).
    *   *Sauvegarde de configuration* : Sauvegarde et restauration des fichiers `config.json`/`fr.json` des mods activés.
*   **Éditeur de Configuration de Mods** : Modifiez le fichier `config.json` d'un mod directement dans l'application, via un éditeur visuel hiérarchique (arborescence de réglages typés avec recherche) ou un éditeur JSON brut avec numéros de ligne et validation en direct. Boutons de réinitialisation et de restauration depuis une sauvegarde locale.
*   **Liste des Mods Avancée** : Filtrage par catégories, pagination (15 mods/page avec saut de page direct), filtre pour mods non catégorisés, filtre « Avec config » (mods configurables uniquement), tri par nom (A-Z/Z-A), auteur, version ou ordre d'activation, et support des images de description. Un bouton d'engrenage sur chaque mod configurable ouvre directement l'éditeur de configuration.
*   **Gestionnaire de Sauvegardes** :
    *   Consultez les détails de toutes vos sauvegardes (argent, heure dans le jeu, saison, type de ferme)
    *   Dupliquez ou supprimez des sauvegardes
    *   Modifiez l'argent et les statistiques de base du personnage
*   **Journaux de Développement** : Suivez la sortie SMAPI en temps réel directement dans l'application.
*   **Journal des Modifications Intégré** : Consultez l'historique des versions (`CHANGELOG.md`) directement depuis la barre latérale de l'application.
*   **Support Multilingue** : Basculez instantanément la langue de l'application entre le français, l'anglais et le thaï (ภาษาไทย).
*   **Interface Native macOS** : Une interface propre et intuitive conçue pour s'intégrer parfaitement à macOS.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/screenshots_banner.png" alt="Captures d'écran" width="300">
</p>

|   |   |
| :---: | :---: |
| <img src="screenshots/1.png" width="400"> | <img src="screenshots/2.png" width="400"> |
| <img src="screenshots/3.png" width="400"> | <img src="screenshots/4.png" width="400"> |
| <img src="screenshots/5.png" width="400"> | <img src="screenshots/6.png" width="400"> |
| <img src="screenshots/7.png" width="400"> | <img src="screenshots/8.png" width="400"> |
| <img src="screenshots/9.png" width="400"> | <img src="screenshots/10.png" width="400"> |
| <img src="screenshots/11.png" width="400"> | <img src="screenshots/12.png" width="400"> |

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="Installation" width="300">
</p>

### Configuration minimale
*   **Système d'exploitation** : macOS 14.0 (Sonoma) ou ultérieur
*   **Stardew Valley** : le jeu installé sur macOS (version Steam ou GOG)
*   **Optionnel** : [SMAPI](https://smapi.io/) pour jouer avec des mods

### Étapes d'installation
1. **Télécharger** : Récupérez la dernière version depuis la page [Releases](../../releases).
2. **Installer** : Décompressez le fichier et glissez `StarHubTH.app` dans votre dossier Applications, puis double-cliquez pour le lancer.
3. **Définir le dossier du jeu** : Au premier lancement, l'application tentera de détecter automatiquement le dossier du jeu Steam. Si celui-ci n'est pas trouvé, vous pouvez sélectionner manuellement le répertoire du jeu (ex. `/Applications/Stardew Valley.app/Contents/MacOS`).
4. **C'est prêt !** : Gérez vos mods ou vos sauvegardes, puis cliquez sur **« Lancer le jeu »** sur la page d'accueil.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/developers_banner.png" alt="Pour les développeurs" width="300">
</p>

Cette application est développée en **Swift** et **SwiftUI** en tant qu'application macOS native.

### Prérequis
*   macOS 14.0 (Sonoma) ou ultérieur
*   Xcode 15.0 ou ultérieur (pour compiler depuis les sources)

### Lancer le projet
Vous pouvez ouvrir le projet dans Xcode ou compiler via le Terminal avec le script de build :
```bash
python3 build_app.py
open StarHubTH.app
```

### Créer une version Release
Pour empaqueter l'application dans un fichier `.zip` pour la distribution :
```bash
python3 release.py
```
Les fichiers Release seront sauvegardés dans le dossier `bundles/`.

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/credits_banner.png" alt="Crédits et Licence" width="300">
</p>

Ce projet est publié sous la [Licence MIT](LICENSE). N'hésitez pas à forker, modifier et l'améliorer.
