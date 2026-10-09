> [!IMPORTANT]
> Ce fork ajoute la prise en charge de la langue française, ainsi qu'une UX/UI « French touch ». Pour la version anglaise, consultez le [README anglais](README_EN.md).
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
  <a href="https://github.com/mrbabilo/StarHubFR/releases/latest"><img src="https://img.shields.io/github/v/release/mrbabilo/StarHubFR?label=Version&color=2ea44f" alt="Version"></a>
  <a href="https://www.stardewvalley.net"><img src="https://img.shields.io/badge/Stardew%20Valley-1.6-5BA04E" alt="Stardew Valley 1.6"></a>
  <a href="https://smapi.io"><img src="https://img.shields.io/badge/SMAPI-4.x-6A5ACD" alt="SMAPI 4.x"></a>
  <a href="#"><img src="https://img.shields.io/badge/Langues-FR%20%7C%20EN-0055A4" alt="Langues FR et EN"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Licence-MIT-yellow" alt="MIT License"></a>
  <a href="https://github.com/mrbabilo/StarHubFR/actions/workflows/ci.yml"><img src="https://github.com/mrbabilo/StarHubFR/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>


**StarHubFR est un gestionnaire de mods Stardew Valley natif pour macOS, en français.**
Installez, organisez et dépannez vos mods sans passer par le Finder ni le terminal, même avec plusieurs centaines de mods.

Le **[guide utilisateur](GUIDE.md)** explique la cohabitation avec d'autres gestionnaires, la convention `X` / `.X` des mods en pause et la désinstallation propre de l'app.

## Pourquoi StarHubFR

*   🇫🇷 **En français de bout en bout** — interface, erreurs et diagnostics, avec bascule instantanée vers l'anglais.
*   🩺 **Il explique ce qui ne va pas** — il lit le journal SMAPI à votre place et dit quoi faire, en clair.
*   ✍️ **Vous traduisez les mods dans l'app** — un éditeur clé par clé écrit le `fr.json` sans casser les marqueurs du jeu.
*   🍎 **Vraiment natif** — Swift et SwiftUI, sans couche web, utilisable avec VoiceOver.
*   🧩 **Fait pour les grosses collections** — conçu et testé sur des installations de plusieurs centaines de mods (SVE et compagnie).
*   🧭 **De nouveaux mods sans quitter l'app** — tendances, mises à jour récentes et sélection française, croisées avec ce que vous avez déjà.

<p align="center">
  <img src="assets/banners/features_banner.png" alt="Fonctionnalités principales" width="300">
</p>

### 🩺 Diagnostic SMAPI

Quand le jeu plante ou qu'un mod refuse de se charger, StarHubFR transforme le journal SMAPI en diagnostic lisible.

*   **Des conseils, pas du jargon** — « installez telle dépendance », « ce mod est installé en double », « ce mod ne prend pas en charge votre version du jeu ».
*   **L'état de santé en un coup d'œil** — versions de SMAPI et du jeu, mods chargés, ignorés ou en échec avec leur raison, dépendances manquantes.
*   **Les mods à surveiller** — ceux qui modifient le code du jeu ou vos sauvegardes, ceux qui produisent le plus d'erreurs, avec ce que cela implique.
*   **Les fausses alertes mises à part** — GOG Galaxy, intégration optionnelle absente, mod compagnon manquant : le message est cité, un bouton mène à ses lignes, et le mod n'est plus accusé à tort.
*   **Un journal qui se lit** — lignes répétitives repliées, regroupement par mod (les plus problématiques en tête), badge si le journal date d'avant votre session.
*   **Les erreurs suivies version par version** — la fiche d'un mod dit si sa nouvelle version se comporte moins bien que la précédente.
*   **Tous vos raccourcis et leurs conflits** — chaque touche des mods actifs, cherchable par mod, réglage ou touche ; à la capture, l'éditeur de config dit si un autre mod l'utilise déjà.
*   **Les conflits prévus avant de jouer** — deux mods qui chargent le même asset en exclusif sont signalés, et l'activation (seule, groupée ou par profil) prévient en nommant l'asset.
*   **Retrouver le mod fautif** — quand rien ne désigne de coupable, l'app met vos mods en pause par moitiés et pose une question par étape. Une dizaine d'essais suffisent ; tout se remet en un clic.

### ⏱️ Performances

La sonde StarHubFR, un petit mod SMAPI installé à votre demande, mesure le jeu pendant que vous jouez. L'onglet *Performances* compare deux moments et dit ce qui a changé.

*   **Temps de chargement** — lancement et chargement de partie, comparés à l'état précédent de votre parc, avec les mods qui pèsent le plus.
*   **Benchmark automatique** — l'app enchaîne seule plusieurs lancements en alternant les deux états, puis remet votre parc comme avant.
*   **Fluidité et mémoire** — temps d'image, saccades, mémoire du processus et textures par mod, minute par minute, avec ce qui sépare deux sessions (mods, versions, réglages, scène).
*   **Pas de verdict au hasard** — un écart ne compte qu'au-delà du bruit mesuré entre vos propres sessions ; sinon il reste gris.
*   **Diagnostics guidés et réversibles** — pour Stardew Loading Optimizer et Stardropium, l'app installe si besoin, active les mesures le temps d'une partie, puis restaure réglages et mods, même après une interruption.
*   **Carte « Environnement »** — réglages réellement appliqués par Stardew Loading Optimizer, mods configurables, poids et conflits de chaque pack Content Patcher.

### 📦 Installation et organisation

*   **Glisser-déposer une archive** (`.zip`, `.7z`, `.rar`) — structure détectée (mod seul ou pack), format reconnu à ses octets, limites de sécurité (500 Mo d'archive, 2 Go décompressés), conflits et dépendances manquantes annoncés.
*   **Le contenu d'un autre mod s'installe au bon endroit** — un fichier pour un framework (un sac *ItemBags*, par exemple) est placé dans son mod hôte, chemin montré et fichier existant sauvegardé d'abord.
*   **Activer sans déplacer de fichiers** — un mod, une sélection (clic, ⌘, ⇧, ⌘A, puis Espace) ou tous à la fois. Les mods livrés avec SMAPI restent actifs.
*   **Profils** — plusieurs ensembles de mods, un clic pour passer de l'un à l'autre.
*   **Une liste qui se trie** — catégories déduites du manifeste, filtres (configurables, « à écarter », non catégorisés…), tris par nom, auteur, approbations ou mise à jour la plus ancienne ; cadrages Tous, Activés, En pause, **Problèmes** et **Mises à jour**.
*   **Approbations Nexus** — le pouce de chaque mod donne son nombre d'approbations et approuve d'un clic.
*   **Marque « à écarter »** — un mod à retirer de la circulation sans le désinstaller : grisé, regroupé par un filtre, importable dans un profil.

### 🔄 Mises à jour et téléchargements

*   **Vérification sans compte** via [smapi.io](https://smapi.io/), à partir des manifestes. Un bouton « Arrêter » interrompt la vérification à tout moment.
*   **Si smapi.io tombe** — l'app le dit et propose de vérifier directement sur Nexus : un tri sans clé ne revérifie que les pages modifiées, quelques dizaines de requêtes au lieu de plusieurs milliers.
*   **Les mods sans verdict, expliqués** — ceux que ni smapi.io ni Nexus n'ont pu juger, chacun avec sa raison (aucun identifiant, page masquée ou supprimée…). Un identifiant saisi à la main remplace une clé cassée du manifeste.
*   **Chaque mod dit qu'il a une mise à jour** — pastille « ↑ version » sur sa ligne et bandeau sur sa fiche. La correspondance se fait par identifiant de manifeste, jamais par identifiant Nexus.
*   **« Je l'ai déjà »** — pour l'auteur qui publie sans changer la version de son manifeste : la ligne enregistre la version réellement installée, puis disparaît.
*   **Téléchargement dans l'app** — direct avec un compte Premium, ou par le lien `nxm://` avec un compte gratuit. La clé API reste dans le trousseau macOS.
*   **Ce qu'une mise à jour change** — options de config ajoutées ou retirées, textes à traduire, traductions écartées ; les clés renommées sont reportées, jamais écrasées. L'aperçu prévient aussi quand des mods actifs lisent le code interne du mod remplacé.

### 🧭 Découvrir

*   **Trois vitrines Nexus** — tendances, mises à jour récentes et sélection française, mises en cache 24 h.
*   **Ce que vous avez déjà se voit** — pastille « Installé » et filtre pour les masquer, avec le nombre masqué.
*   **Catégories et recherche** — 26 catégories filtrées côté serveur, recherche par nom avec le total réel.
*   **Fiche éclair** — description, version, approbations, puis **Installer** (Premium) ou **Ouvrir sur Nexus**.
*   **Jamais muette** — sans clé, quota atteint ou panne réseau, chaque état dit ce qui se passe et propose l'action qui le lève.

### 📖 Fiche de mod

*   **Six onglets** — Aperçu, Santé, Dépendances, Traduction, Historique, Gestion.
*   **La compatibilité d'abord** — le verdict de smapi.io et ce qu'en dit l'auteur, réunis dans une carte.
*   **Santé** — un verdict et huit vérifications (liste noire SMAPI, chargement, smapi.io, journal, incompatibilités, raccourcis, doublons, page Nexus), avec « non vérifié » quand la donnée manque.
*   **Dépendances** — arbre complet avec statut et actions, plus les mods dont celui-ci lit le code interne sans le déclarer.
*   **Description et journal des modifications** rendus en texte natif (gras, listes, liens, images, spoilers).
*   **Identifiant Nexus et catégorie** modifiables sur place.

### 🌐 Traduction française

Chaque fiche a un onglet **Traduction** qui montre l'état réel du français et sert d'éditeur.

*   **Anglais à gauche, français à droite**, clé par clé ; un mod sans `fr.json` en reçoit un au premier enregistrement.
*   **Une IA locale propose le brouillon** — un modèle qui tourne sur votre Mac (Ollama, LM Studio), par clé ou par lots, marqué « À relire ». Rien ne quitte la machine.
*   **Le glossaire vient du jeu** — plus de mille noms d'objets, personnages et lieux, lus dans votre installation et imposés au modèle.
*   **Les marqueurs du jeu protégés** — affichés en couleur, insérés d'un clic ; un enregistrement qui en perd un est refusé.
*   **Le vrai taux de traduction** — 100 % seulement si toutes les clés sont faites ; clés vides, absentes ou obsolètes listées à part.
*   **Page « Traductions FR »** — les traductions publiées sur Nexus pour vos mods, et les mises à jour de celles installées.
*   **À plusieurs** — export d'un lot ZIP pour un traducteur, fusion clé par clé à son retour.
*   **Mode focus** — bandeaux et barre latérale masqués (Échap pour sortir).

### ⚙️ Configuration et sauvegardes

*   **Éditeur de config** — arborescence de réglages typés avec recherche, ou JSON brut validé en direct ; listes déroulantes avec les libellés traduits du mod.
*   **Sauvegardes des mods** — avant chaque écrasement, plus vos `config.json` et `fr.json`, et les fichiers qu'une mise à jour a emportés.
*   **Parties** — détail, copie, suppression, et retouche de l'argent ou des statistiques.
*   **Ce que vos mods laissent dans vos parties** — chiffré avant la mise en pause ; « Nettoyer… » retire les données de mods disparus, après une sauvegarde.

### 🎮 Au quotidien

*   **Un accueil qui va à l'essentiel** — compteurs utiles et **Lancer le jeu**, en Vanilla ou via SMAPI.
*   **Journaux en temps réel** — sortie SMAPI et StarHubFR, filtrables par source et par niveau.
*   **Les mods dont l'app a besoin** — listés dans les réglages, avec leur rôle, leur état et leur lien d'installation.
*   **Accessible et lisible** — VoiceOver, et des boutons qui passent en icônes quand la fenêtre est étroite.

<p align="center">
  <img src="assets/banners/screenshots_banner.png" alt="Captures d'écran" width="300">
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
| <img src="screenshots/15.jpg" width="400"> | <img src="screenshots/16.jpg" width="400"> |
| <img src="screenshots/17.jpg" width="400"> | <img src="screenshots/18.jpg" width="400"> |
| <img src="screenshots/19.jpg" width="400"> | <img src="screenshots/20.jpg" width="400"> |
| <img src="screenshots/21.jpg" width="400"> | <img src="screenshots/22.jpg" width="400"> |
| <img src="screenshots/23.jpg" width="400"> | <img src="screenshots/24.jpg" width="400"> |
| <img src="screenshots/25.jpg" width="400"> | <img src="screenshots/26.jpg" width="400"> |
| <img src="screenshots/27.jpg" width="400"> | <img src="screenshots/28.jpg" width="400"> |
| <img src="screenshots/29.jpg" width="400"> | <img src="screenshots/30.jpg" width="400"> |
| <img src="screenshots/31.jpg" width="400"> |  |

<p align="center">
  <img src="assets/banners/install_banner.png" alt="Installation" width="300">
</p>

### Configuration requise

*   macOS 14 (Sonoma) ou ultérieur.
*   Stardew Valley installé sur macOS (Steam ou GOG).
*   [SMAPI](https://smapi.io/) pour jouer avec des mods ; l'app sait l'installer.

### Installer

1. Téléchargez la dernière version sur la page [Releases](../../releases).
2. Décompressez l'archive et glissez `StarHubFR.app` dans Applications.
3. Au premier lancement, macOS peut bloquer l'app, qui n'est pas notarisée : ouvrez **Réglages Système › Confidentialité et sécurité**, puis **Ouvrir quand même**.
4. L'app cherche le dossier du jeu ; s'il n'est pas trouvé, indiquez-le (par exemple `/Applications/Stardew Valley.app/Contents/MacOS`).

Pour passer à une nouvelle version, quittez complètement l'app (⌘Q) avant de remplacer le bundle.

<p align="center">
  <img src="assets/banners/developers_banner.png" alt="Pour les développeurs" width="300">
</p>

L'app est écrite en **Swift** et **SwiftUI**. Il faut macOS 14 et Xcode 16 (la version utilisée par la CI).

```bash
python3 build_app.py   # compile, vérifie les conventions et produit StarHubFR.app
open StarHubFR.app
./run_tests.sh         # tests du cœur (Swift Testing)
python3 release.py     # archive de release dans bundles/
```

Il n'y a pas de projet Xcode : `build_app.py` compile toutes les sources, et `Package.swift` ne décrit que le cœur testé.

<p align="center">
  <img src="assets/banners/credits_banner.png" alt="Crédits et Licence" width="300">
</p>

StarHubFR est publié sous [licence MIT](LICENSE) : forkez, modifiez, améliorez. Il dérive de [StarHubTH](https://github.com/AppleBoiy/StarHubTH) par **AppleBoiy**, qui en propose une version en **thaï**.

### Remerciements

StarHubFR s'appuie sur le travail de nombreux projets. La liste complète — API interrogées, fichiers lus, code repris, état de chacun — est tenue à jour dans [`docs/SOURCES.md`](docs/SOURCES.md).

**SMAPI et diagnostic**

*   [**SMAPI**](https://github.com/pathoschild/SMAPI), [**Content Patcher**](https://github.com/Pathoschild/StardewMods/tree/develop/ContentPatcher), [**StardewXnbHack**](https://github.com/Pathoschild/StardewXnbHack) et la [**liste de compatibilité**](https://github.com/Pathoschild/SmapiCompatibilityList) par **Pathoschild** (MIT) — format des journaux et des manifestes vérifié dans les sources, points de mesure du chargement, schéma de config des packs, lecture des fichiers du jeu, verdicts hors ligne. L'installateur intégré télécharge les releases de SMAPI.
*   [**smapi.io**](https://smapi.io/) — l'API de mise à jour qui répond pour Nexus, CurseForge, ModDrop et GitHub sans clé ni compte, son [analyseur de journaux](https://smapi.io/log/) et sa [liste noire](https://smapi.io/SMAPI.blacklist.json).
*   [**SMAPILogDoctor.py**](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py) par **ZeroXPatch** — l'idée d'un diagnostic de journal pensé pour le joueur.

**Nexus Mods**

*   [**Nexus Mods**](https://www.nexusmods.com/stardewvalley) — API v1 pour les fiches et les téléchargements, API GraphQL v2 (non documentée, relevée par introspection) pour la découverte, la recherche et le tri sans clé. Merci de la laisser ouverte.
*   [**Nexus Mods App**](https://nexus-mods.github.io/NexusMods.App/developers/), [**node-nexus-api**](https://github.com/Nexus-Mods/node-nexus-api) et [**Vortex**](https://github.com/Nexus-Mods/Vortex) — protocole `nxm://`, forme des réponses, conventions de gestionnaire.

**Traduction**

*   [**lzxd**](https://codeberg.org/Lonami/lzxd) par **Lonami** (MIT / Apache-2.0) — transposé en Swift pour lire les traductions officielles du jeu ; [**libmspack**](https://github.com/kyz/libmspack) par **Stuart Caie** (LGPL-2.1) en référence, sans code repris.
*   [**stardew-i18n-translator**](https://github.com/Nana1873/stardew-i18n-translator) par **Nana1873** (GPL-3.0) — modèle de conception de notre éditeur, jusqu'à la protection des marqueurs. Aucun code repris.
*   [**Transtar**](https://github.com/wanniwa/transtar) par **wanniwa**, [**Internationalization**](https://www.nexusmods.com/stardewvalley/mods/21317) par **bcmpinc** et [**ModTRANS**](https://www.nexusmods.com/stardewvalley/mods/53388) — d'autres approches de la traduction de mods, étudiées pour les nôtres.
*   [**Ollama**](https://ollama.com) (MIT) et [**LM Studio**](https://lmstudio.ai) — les serveurs d'IA locale que l'app détecte, sans les embarquer ; [**Qwen2.5**](https://ollama.com/library/qwen2.5) par l'**équipe Qwen** (Apache-2.0), le modèle conseillé ; [**DeepL**](https://www.deepl.com/pro-api), secours facultatif avec votre propre clé.

**Configuration et sauvegardes**

*   [**Generic Mod Config Menu**](https://www.nexusmods.com/stardewvalley/mods/5098) par **spacechase0** et [**Modern Config Menu**](https://www.nexusmods.com/stardewvalley/mods/49437) par **palmhacker13** — ce que les mods déclarent de leurs réglages, et le menu en jeu de la sonde.
*   [**stardew-save-editor**](https://github.com/colecrouter/stardew-save-editor) par **colecrouter** — référence pour lire et modifier les sauvegardes.
*   **Newtonsoft.Json** (MIT), tel qu'embarqué par le jeu et exécuté sous Mono — l'oracle de ce que SMAPI accepte vraiment comme JSON.

**Performances**

*   [**Profiler**](https://github.com/SinZ163/StardewMods/tree/main/Profiler) par **SinZ** (MIT) — minuteurs de trame et lecture des pauses du ramasse-miettes repris par la sonde ; sa visionneuse [Stardew Utilities](https://stardew.361zn.is) a guidé la lecture du chargement.
*   [**FastLoads**](https://www.nexusmods.com/stardewvalley/mods/19454) par **spajus**, [**Stardew Loading Optimizer**](https://www.nexusmods.com/stardewvalley/mods/50153) par **neoiw**, [**Stardropium**](https://www.nexusmods.com/stardewvalley/mods/52803) par **Arshia1381**, [**UltraSmooth**](https://www.nexusmods.com/stardewvalley/mods/50971) par **palmhacker13** et [**SDV-Radiance**](https://www.nexusmods.com/stardewvalley/mods/49397) par **PHUICMT** — décompilés et étudiés pour savoir ce qu'ils changent au jeu, et donc ce que nos mesures doivent voir.

**Outils**

*   [**ILSpy**](https://github.com/icsharpcode/ILSpy) (MIT) — décompilation des mods pour en auditer les changements.
*   [**dnfile**](https://github.com/malwarefrank/dnfile) (MIT) — oracle Python de notre lecteur de métadonnées .NET.
*   [**7-Zip**](https://www.7-zip.org), [**The Unarchiver**](https://theunarchiver.com) (`unar`) et **unrar** — utilisés, s'ils sont installés, pour ouvrir les archives `.7z` et `.rar`.

**Inspirations**

*   [**Stardrop**](https://github.com/Floogen/Stardrop) par **Floogen** et son port macOS [**Stardrop – Native MacOS**](https://www.nexusmods.com/stardewvalley/mods/53356) par **kautsaralbaa** — vérification en direct, notes, configurations par profil.
*   [**JuniGrid**](https://www.nexusmods.com/stardewvalley/mods/53227) par **MLD210** et [**StarModsManager**](https://github.com/Arborsm/StarModsManager) par **Arborsm** — d'autres gestionnaires, lus pour leurs idées comme pour leurs pièges.
*   [**Keybind Radar**](https://www.nexusmods.com/stardewvalley/mods/52710) par **Wooa** et [**SaveSaver**](https://www.nexusmods.com/stardewvalley/mods/52709) par **Sky** — ils ont nourri le signal de conflit à la capture et le nettoyage guidé des parties.
