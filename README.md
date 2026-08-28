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
*   ✍️ **Vous traduisez les mods dans l'app** — un éditeur clé par clé écrit le `fr.json`, avec les marqueurs du jeu protégés au passage.
*   🩺 **Il vous explique ce qui ne va pas** — StarHubFR lit le journal SMAPI à votre place et vous dit quoi faire, en langage clair, au lieu de vous laisser face à un mur de texte technique.
*   🍎 **Vraiment natif macOS** — Swift et SwiftUI, sans Electron ni couche web, accessible à VoiceOver.
*   🧩 **Calibré pour les grosses collections** — pensé et testé sur des installations de plusieurs centaines de mods (SVE et compagnie).
*   🧭 **Trouver de nouveaux mods sans quitter l'app** — tendances, mises à jour récentes et sélection française, croisées en permanence avec ce que vous avez déjà.

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
*   **Journaux lisibles** — les lignes répétitives (un vrai journal en compte des milliers) sont repliées en une ligne dépliable, et un bouton regroupe les entrées par mod, les plus problématiques en tête. Rien n'est supprimé : le détail reste à un clic.
*   **Suivi des erreurs par version** — chaque mod garde l'historique des erreurs et avertissements qu'il a journalisés, **version par version**, consultable depuis sa fiche : de quoi savoir si une nouvelle version se comporte moins bien que la précédente.
*   **Recherche du mod responsable** — quand le jeu plante sans que le journal désigne personne, StarHubFR met vos mods en pause par moitiés et vous pose une seule question à chaque étape. Une dizaine d'essais suffisent, même avec des centaines de mods. Rien n'est supprimé, tout se remet en un clic.

### 📦 Installation et organisation des mods

*   **Glisser-déposer une archive** (`.zip`, `.7z`, `.rar`) — détection automatique de la structure (mod seul ou pack multi-composants), validation d'intégrité (taille d'archive plafonnée à 500 Mo, garde anti-zip-bomb à 2 Go décompressés couvrant les trois formats, détection du vrai format par la signature du fichier et non son extension), aperçu des conflits et suggestion des dépendances manquantes.
*   **Un fichier destiné à un autre mod s'installe au bon endroit** — certains téléchargements Nexus sont du contenu pour un framework (un sac *ItemBags*, par ex.), pas un mod autonome, et ne portent pas de `manifest.json`. L'app les reconnaît et propose de les placer où ils appartiennent, en montrant le chemin exact et en sauvegardant d'abord un fichier existant ; un mod hôte en pause est géré, et une sauvegarde qui échoue annule l'installation plutôt que d'écraser.
*   **Activation sans déplacer de fichiers** — activez ou désactivez un mod d'un clic, ou **tous vos mods d'un coup** (barre de progression, aucune perte). Supprimez un mod ou un pack du disque après confirmation.
*   **Profils de mods** — regroupez vos mods en plusieurs profils et basculez de l'un à l'autre en un clic.
*   **Liste avancée** — classification automatique par type (UI, Framework, Content Patcher, Traduction, PNJ, Audio, Carte…) déduite du manifeste, qui sert aussi de repli hors ligne. Filtres par catégorie, mods non catégorisés, mods configurables ; tri par nom, auteur, version ou ordre d'activation ; pagination avec saut de page direct.

### 🔄 Mises à jour et téléchargements

*   **Détection des mises à jour** via [smapi.io](https://smapi.io/) — sans clé API ni compte Nexus : la vérification lit ce que chaque mod déclare dans son manifeste, et un mod qu'elle n'a pas pu joindre reste signalé au lieu de passer pour à jour.
*   **« Je l'ai déjà »** — certains auteurs publient une nouvelle version sans incrémenter celle de leur manifeste : le contrôle voit un écart qui n'existe pas et le réaffiche à chaque passage. La ligne porte un bouton qui enregistre la version réellement installée, puis s'efface.
*   **Téléchargement dans l'application** — bouton *MàJ Premium* pour les comptes Premium, ou *MàJ Nexus* via le lien `nxm://` pour les comptes gratuits. La clé API Nexus, stockée dans le trousseau macOS, ne sert qu'à télécharger.
*   **Réconciliation automatique du `manifest.json`** après installation, pour qu'un mod mis à jour ne réapparaisse pas indéfiniment comme « à mettre à jour ».

### 🧭 Découvrir de nouveaux mods

L'app savait tout faire **à partir d'un mod installé** — traductions, suppléments — et rien **sans point de départ**. L'onglet *Découvrir* comble ce trou.

*   **Trois vitrines servies par Nexus** — tendances (les plus endossés), mises à jour récentes, et **sélection française**. Une requête par section, mise en cache 24 h : seul le bouton de rafraîchissement redemande au réseau, jamais l'ouverture de l'onglet.
*   **Vous voyez tout de suite ce que vous avez déjà** — chaque carte porte une pastille « Installé », croisée avec votre parc par identifiant Nexus **et** par titre, et un filtre masque les mods installés en affichant toujours combien il en a masqué. Sur plusieurs centaines de mods, l'essentiel des tendances vous est déjà connu.
*   **Filtre par catégorie** — les 26 catégories du jeu, appliquées **au serveur** : « Portraits » redemande des portraits à Nexus plutôt que de trier les vingt mods déjà reçus. Chaque catégorie garde son propre cache.
*   **Recherche par nom** dans la même vitrine, avec le total réel annoncé — une poignée de résultats n'est jamais tout ce qui existe.
*   **La vitrine est francophone** — une traduction n'y figure que si elle est française ; les japonaises, chinoises ou brésiliennes n'ont rien à y faire. La recherche par nom, elle, rend ce que vous lui demandez, sans filtre de langue.
*   **Fiche éclair** — bandeau illustré, endossements, version, âge de la mise à jour, catégorie, et la description rendue comme sur la page du mod. De là : **Installer** (compte Nexus Premium requis par l'API de téléchargement) ou **Ouvrir sur Nexus**, qui vise directement l'onglet des fichiers — le lien `nxm://` ramène ensuite l'archive dans l'app, sur compte gratuit comme Premium.
*   **Jamais muette** — sans clé d'API, quota atteint, panne réseau, ou filtres qui ne laissent rien passer : chaque état dit ce qui se passe **et porte l'action qui le lève**.

### 📖 Fiche détaillée de mod

*   **Description complète** rendue en texte natif (BBCode/HTML) — gras, listes, liens, images à taille native, spoilers repliables.
*   **Journal des modifications** du mod, et **arbre de dépendances transitif** avec statut (activé, désactivé, manquant), actions *Activer* / *Nexus* / *Chercher*, et navigation d'un mod à l'autre.
*   Édition de la catégorie et de l'identifiant Nexus directement depuis le volet.
*   Bannières mises en cache pour un affichage instantané.

### 🌐 Traduction française — clé par clé

Un onglet **Traduction** sur la fiche de chaque mod vous montre l'état réel de son français, là où la liste se contentait d'un « FR disponible » dès qu'un `fr.json` existait — une demi-vérité sur un mod traduit à 8 %. Et c'est un éditeur, pas seulement un rapport : le français s'écrit ici, sans quitter l'app.

*   **Traduire sans quitter l'app** — cliquez une ligne pour l'ouvrir en édition : l'anglais à gauche, en lecture seule ; votre français à droite. Passez à la clé suivante, ou revenez à la précédente, sans repasser par la liste. Un mod qui n'a pas encore de `fr.json` en obtient un au premier enregistrement — l'onglet s'ouvre aussi sur les mods sans aucun français, pas seulement là où le travail est déjà commencé.
*   **Une IA locale propose le français** — un modèle qui tourne sur votre Mac remplit le brouillon, clé par clé ou par lot que vous pouvez arrêter et reprendre. Les propositions arrivent marquées « À relire », avec un filtre pour les retrouver, et passent par le même contrôle de marqueurs que la saisie manuelle. Rien ne quitte la machine : l'app n'accepte qu'une adresse en loopback, sans proxy et sans suivre de redirection.
*   **Le glossaire vient du jeu lui-même** — plus de mille noms d'objets, d'outils, de personnages, de lieux et de saisons, lus dans les fichiers de votre installation et imposés au modèle : une proposition dit « Minerai d'iridium », pas un synonyme inventé. Les termes en jeu s'affichent en pastilles dans l'éditeur, à insérer d'un clic.
*   **L'app dit quel modèle installer** — un Ollama fraîchement installé n'a aucun modèle, et le bon nom n'est pas devinable. Les réglages lisent la mémoire du Mac, nomment un modèle qui lui convient et donnent la commande à lancer — ou pointent un modèle convenable déjà présent, plutôt qu'un téléchargement de plusieurs gigaoctets pour rien.
*   **Les marqueurs du jeu sont protégés pendant la traduction** — dans l'éditeur, ils s'insèrent d'un clic plutôt qu'ils ne se retapent ; un enregistrement qui en fait disparaître un est refusé, en nommant celui qui manque. Une issue existe quand l'omission est délibérée : une phrase française neutre n'a que faire d'un sélecteur de genre.
*   **Chaque clé sous ses deux langues** — l'anglais et le français côte à côte, avec l'état de la clé (traduit, à traduire, vide, identique à l'anglais, orphelin). Chaque filtre porte son compte, pour qu'un « Vides 3 » saute aux yeux avant même de cliquer.
*   **Ce qui ne doit pas être traduit est visible** — une valeur mêle la phrase et les marques que le jeu lit : token Content Patcher, séparateur de dialogue, commande qui change une expression de portrait. Les traduire ou les déplacer casse le mod ; elles s'affichent en chasse fixe et en couleur, dans les deux colonnes. Plus de la moitié des valeurs en contiennent au moins une.
*   **Les sections mises en évidence** — celles qu'un auteur a écrites dans son fichier deviennent des titres repliables, avec ce qu'il reste à y faire, et une liste permet de sauter directement à l'une.
*   **Taux de traduction par mod** — une pastille donne le pourcentage réel : verte quand c'est complet, ambre sinon. Elle ne lit 100 % que si toutes les clés sont faites, donc un mod à une clé près lit 99 %.
*   **Clé absente ou clé vide, la différence compte** — une clé absente retombe sur l'anglais et ne casse rien ; une clé vide n'affiche rien du tout, silencieusement. Les deux sont listées séparément, vides d'abord, car un mod à 98 % dont les 2 % restants sont vides est plus cassé qu'un mod à 60 %.
*   **Traduction obsolète signalée** — si l'anglais a été édité plus récemment que le français, la fiche donne l'écart de date et un filtre « À revoir » les rassemble ; les clés obsolètes sont marquées dans l'onglet, l'ancien anglais barré.
*   **Traduction perdue lors d'une mise à jour** — les mises à jour remplacent tout le dossier et les auteurs ne renvoient pas toujours les traductions communautaires. Quand une sauvegarde StarHubFR en conserve une, la fiche le dit avec sa date.
*   **Filtre des mods entamés mais inachevés** — pour isoler le travail qui reste parmi ceux déjà commencés, noyés dans le reste.
*   **Des fichiers lus comme leurs auteurs les écrivent** — commentaires, virgules en fin de ligne, clés sans guillemets, fins de ligne Windows (CRLF), encodages UTF-16/UTF-32/8 bits hérités : le lecteur permissif accepte ce que le jeu lui-même accepte, vérifié fichier par fichier contre sa propre bibliothèque JSON.

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
| <img src="screenshots/1.jpg" width="400"> | <img src="screenshots/2.jpg" width="400"> |
| <img src="screenshots/3.jpg" width="400"> | <img src="screenshots/4.jpg" width="400"> |
| <img src="screenshots/5.jpg" width="400"> | <img src="screenshots/6.jpg" width="400"> |
| <img src="screenshots/7.jpg" width="400"> | <img src="screenshots/8.jpg" width="400"> |
| <img src="screenshots/9.jpg" width="400"> | <img src="screenshots/10.jpg" width="400"> |
| <img src="screenshots/11.jpg" width="400"> | <img src="screenshots/12.jpg" width="400"> |
| <img src="screenshots/13.jpg" width="400"> | <img src="screenshots/14.jpg" width="400"> |

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

La **découverte de mods et la vérification des mises à jour** reposent sur deux services publics :

*   [**Nexus Mods**](https://www.nexusmods.com/stardewvalley) — l'onglet *Découvrir* et la recherche interrogent son API GraphQL v2. Elle n'est **pas documentée publiquement** : sa forme a été relevée par introspection du schéma, et le client de l'app est écrit pour encaisser un changement sans préavis — analyse tolérante, échec propre, jamais une panne déguisée en « aucun résultat ». Merci à Nexus de la laisser ouverte.
*   [**smapi.io**](https://smapi.io/) — l'API de mise à jour de SMAPI, qui répond pour Nexus, CurseForge, ModDrop et GitHub à partir du seul manifeste, **sans clé ni compte**. C'est elle qui permet à StarHubFR de vérifier vos mods sans rien vous demander.

La **traduction assistée** (glossaire des termes du jeu, pré-traduction IA) doit beaucoup aux travaux suivants :

*   [**lzxd**](https://github.com/Lonami/lzxd) par **Lonami** (MIT / Apache-2.0) — notre décodeur LZX, qui lit les fichiers de traduction officiels du jeu directement depuis votre installation, est une translittération en Swift de cette implémentation.
*   [**stardew-i18n-translator**](https://github.com/Nana1873/stardew-i18n-translator) par **Nana1873** (GPL-3.0) — application Windows de traduction de mods dont le workflow a servi de référence de conception à la nôtre. Aucun code n'est repris : les licences l'excluent.
*   [**StardewXnbHack**](https://github.com/Pathoschild/StardewXnbHack) par **Pathoschild** (MIT) — sert d'oracle pour valider notre lecteur de fichiers du jeu, octet par octet.
*   [**Ollama**](https://ollama.com) (MIT) — le serveur d'IA locale que l'app détecte, vers lequel elle oriente, et le seul destinataire de ce qu'elle envoie. StarHubFR ne l'installe pas et ne l'embarque pas : il tourne chez vous, sous votre contrôle.
*   [**LM Studio**](https://lmstudio.ai) — détecté au même titre qu'Ollama quand il expose son API compatible OpenAI (gratuit, propriétaire).
*   [**Qwen2.5**](https://ollama.com/library/qwen2.5) par l'**équipe Qwen** (Apache-2.0) — la famille conseillée par défaut : multilingue, tailles régulières, et surtout **sans raisonnement** — un modèle qui délibère avant de répondre épuise son budget de jetons et rend une traduction tronquée. Le choix reste le vôtre : le champ Modèle accepte n'importe quel modèle servi par votre serveur.
