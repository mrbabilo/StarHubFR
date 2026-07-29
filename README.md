> [!IMPORTANT]
> Ce fork ajoute le support de la langue française, ainsi qu'une UX/UI « french touch ». Pour la version anglaise, consultez le [README anglais](README_EN.md).
>
> Projet original : [StarHubTH](https://github.com/AppleBoiy/StarHubTH) par **AppleBoiy** — qui propose une version en **thaï**.

<p align="center">
  <img src="assets/nexus_banner_final.png" alt="StarHubFR Banner">
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0288D1?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://www.python.org"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python"></a>
  <a href="#"><img src="https://img.shields.io/badge/Plateforme-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Licence-MIT-yellow" alt="MIT License"></a>
</p>

**StarHubFR est un gestionnaire de mods Stardew Valley natif pour macOS, en français.**
Installez, organisez et dépannez votre collection de mods sans jamais toucher au Finder ni au terminal — même avec plusieurs centaines de mods.

## Pourquoi StarHubFR

*   🇫🇷 **Entièrement en français** — interface, messages d'erreur et diagnostics, avec bascule instantanée vers l'anglais.
*   🩺 **Il vous explique ce qui ne va pas** — StarHubFR lit le journal SMAPI à votre place et vous dit quoi faire, en langage clair, au lieu de vous laisser face à un mur de texte technique.
*   🍎 **Vraiment natif macOS** — Swift et SwiftUI, sans Electron ni couche web, accessible à VoiceOver.
*   🧩 **Calibré pour les grosses collections** — pensé et testé sur des installations de plusieurs centaines de mods (SVE et compagnie).

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="Fonctionnalités principales" width="300">
</p>

### 🩺 Diagnostic SMAPI — le point fort

Quand le jeu plante ou qu'un mod refuse de se charger, StarHubFR transforme le journal SMAPI en diagnostic lisible.

*   **« Ce que vous pouvez faire »** — des conseils actionnables, pas du jargon : « installez telle dépendance », « ce mod est installé en double, gardez une seule copie », « ce mod ne prend pas en charge votre version du jeu ».
*   **Un état de santé en un coup d'œil** — versions SMAPI et jeu, mods et packs chargés, mods ignorés ou en échec **avec leur raison**, dépendances manquantes.
*   **Les mods à surveiller** — ceux qui modifient le code du jeu, ceux qui changent vos sauvegardes, ceux qui génèrent le plus d'erreurs — chacun avec une explication de ce que ça implique pour vous.
*   **« Erreurs que vous pouvez ignorer »** — les fausses alertes sont reconnues et expliquées (connexion GOG Galaxy, intégration optionnelle indisponible, mod compagnon absent, données de mod illisibles) : le mod est nommé, le message d'origine est cité comme preuve, et un bouton vous emmène directement à ses lignes dans le journal. Elles ne comptent plus comme des problèmes — un mod qui marche n'est plus accusé à tort.
*   **Journal périmé** — un badge vous prévient si le journal date d'avant votre session, et un bouton l'ouvre dans le Finder.

### 📦 Installation et organisation des mods

*   **Glisser-déposer un `.zip`** — détection automatique de la structure (mod seul ou pack multi-composants), validation d'intégrité (anti-zip-bomb, < 500 Mo), aperçu des conflits et suggestion des dépendances manquantes.
*   **Activation sans déplacer de fichiers** — activez ou désactivez un mod d'un clic, ou **tous vos mods d'un coup** (barre de progression, aucune perte). Supprimez un mod ou un pack du disque après confirmation.
*   **Profils de mods** — regroupez vos mods en plusieurs profils et basculez de l'un à l'autre en un clic.
*   **Liste avancée** — classification automatique par type (UI, Framework, Content Patcher, Traduction, PNJ, Audio, Carte…) déduite du manifeste, qui sert aussi de repli hors ligne. Filtres par catégorie, mods non catégorisés, mods configurables ; tri par nom, auteur, version ou ordre d'activation ; pagination avec saut de page direct.

### 🔄 Mises à jour et téléchargements Nexus Mods

*   **Détection des mises à jour** via l'API Nexus Mods — clé stockée dans le trousseau macOS, détection fiable même à numéro de version identique (comparaison par date d'upload).
*   **Téléchargement dans l'application** — bouton *MàJ Premium* pour les comptes Premium, ou *MàJ Nexus* via le lien `nxm://` pour les comptes gratuits.
*   **Réconciliation automatique du `manifest.json`** après installation, pour qu'un mod mis à jour ne réapparaisse pas indéfiniment comme « à mettre à jour ».

### 📖 Fiche détaillée de mod

*   **Description complète** rendue en texte natif (BBCode/HTML) — gras, listes, liens, images à taille native, spoilers repliables.
*   **Journal des modifications** du mod, et **arbre de dépendances transitif** avec statut (activé, désactivé, manquant), actions *Activer* / *Nexus* / *Chercher*, et navigation d'un mod à l'autre.
*   Édition de la catégorie et de l'identifiant Nexus directement depuis le volet.
*   Bannières mises en cache pour un affichage instantané.

### ⚙️ Configuration et sauvegardes

*   **Éditeur de configuration** — modifiez le `config.json` d'un mod via un éditeur visuel hiérarchique (arborescence de réglages typés avec recherche) ou un éditeur JSON brut avec numéros de ligne et validation en direct. Réinitialisation et restauration depuis une sauvegarde locale.
*   **Sauvegarde d'installation** — copie automatique avant l'écrasement d'un mod, avec rétention hybride (5 plus récentes + celles de moins de 30 jours + 1 par mois au-delà).
*   **Sauvegarde de configuration** — sauvegardez et restaurez les `config.json` / `fr.json` de vos mods activés.
*   **Gestionnaire de sauvegardes de partie** — consultez le détail de vos parties (argent, date en jeu, saison, type de ferme), dupliquez-les, supprimez-les, ou ajustez l'argent et les statistiques du personnage.

### 🎮 Au quotidien

*   **Lancement du jeu** — démarrez Stardew Valley en mode Vanilla ou via SMAPI, directement depuis l'accueil.
*   **Journaux en temps réel** — sortie SMAPI et StarHubFR dans l'application, avec filtrage par source et par niveau (compteurs à l'appui), recherche, et copie de lignes conservant l'origine et le mod concerné.
*   **Indicateur d'état système** — mods actifs, mises à jour disponibles et erreurs SMAPI, visibles en permanence en bas de la barre latérale.
*   **Journal des modifications intégré** — l'historique des versions se consulte depuis la barre latérale.
*   **Accessibilité VoiceOver** — navigation complète au lecteur d'écran sur la liste des mods, les boutons d'action et la barre latérale.
*   **Détails qui comptent** — zone de glisser-déposer dédiée quand aucun mod n'est installé, recherche Nexus avec des termes lisibles (« Content Patcher » plutôt que `Pathoschild.ContentPatcher`), infobulles sur tous les boutons d'icône.

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
2. **Installer** : Décompressez le fichier et glissez `StarHubFR.app` dans votre dossier Applications, puis double-cliquez pour le lancer.
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
open StarHubFR.app
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
Projet original : [StarHubTH](https://github.com/AppleBoiy/StarHubTH) par **AppleBoiy** — qui propose une version en **thaï**.

### Remerciements

Le **diagnostic SMAPI** de StarHubFR doit beaucoup aux travaux suivants :

*   [**SMAPILogDoctor.py**](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py) par **ZeroXPatch** — l'idée d'un diagnostiqueur de journal SMAPI orienté joueur (mods ignorés avec leur raison, dépendances manquantes, catégories de risque, suggestions de correction) a servi de point de départ à notre analyseur.
*   [**smapi.io/log**](https://smapi.io/log/) — l'analyseur de journaux officiel de SMAPI, référence pour les informations à extraire d'un journal.
*   [**SMAPI**](https://github.com/pathoschild/SMAPI) par **Pathoschild** — le format exact des journaux (sections d'avertissement, niveaux, en-têtes) a été vérifié directement dans les sources, notamment `LogManager.cs`.
