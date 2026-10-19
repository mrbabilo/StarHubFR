# Guide utilisateur — StarHubFR

*[English version](GUIDE_EN.md).*

Comment s'en servir au quotidien, et quoi faire quand quelque chose coince. Pour la liste complète de ce que l'app sait faire, voir le [README](README.md).

**Sommaire**

1. [Premier lancement](#1-premier-lancement)
2. [Installer des mods](#2-installer-des-mods)
3. [Activer, mettre en pause : la convention `X` / `.X`](#3-activer-mettre-en-pause--la-convention-x--x)
4. [Profils et groupes](#4-profils-et-groupes)
5. [Mises à jour](#5-mises-à-jour)
6. [Quand le jeu plante ou qu'un mod refuse de charger](#6-quand-le-jeu-plante-ou-quun-mod-refuse-de-charger)
7. [Raccourcis clavier en conflit](#7-raccourcis-clavier-en-conflit)
8. [Mesurer les performances](#8-mesurer-les-performances)
9. [Traduire un mod en français](#9-traduire-un-mod-en-français)
10. [Retrouver ce qui a été remplacé ou supprimé](#10-retrouver-ce-qui-a-été-remplacé-ou-supprimé)
11. [Avec d'autres gestionnaires de mods](#11-avec-dautres-gestionnaires-de-mods)
12. [Désinstaller StarHubFR proprement](#12-désinstaller-starhubfr-proprement)

---

<!-- help: first-launch -->
## 1. Premier lancement

1. Téléchargez la dernière version sur la page [Releases](../../releases), décompressez-la et glissez `StarHubFR.app` dans **Applications**.
2. L'app n'est pas notarisée : au premier lancement, macOS peut la bloquer. Ouvrez **Réglages Système › Confidentialité et sécurité**, puis **Ouvrir quand même**. Si macOS refuse encore ou dit l'app « endommagée », glissez `StarHubFR.app` sur la zone **Allow unsigned app to launch** de [Sentinel](https://itsalin.com/appInfo/?id=sentinel) (`brew install --cask alienator88-sentinel`) ; la procédure complète est dans le [README](README.md#lever-la-quarantaine-avec-sentinel). À refaire après chaque nouvelle version.
3. L'app cherche Stardew Valley. Si elle ne le trouve pas, désignez **l'application du jeu elle-même** ; le dossier `Mods/` est trouvé à partir de là.
4. Si SMAPI n'est pas installé, l'app propose de l'installer. Sans SMAPI, le jeu ne charge aucun mod.

**La clé API Nexus est facultative.** Sans elle, l'app vérifie déjà les mises à jour (par smapi.io) et parcourt Découvrir. Avec elle (**Réglages › Clé API**), elle télécharge et installe depuis Nexus, et vous pouvez approuver un mod d'un clic. La clé reste dans le trousseau macOS.

Pour passer à une nouvelle version de l'app, quittez-la complètement (⌘Q) avant de remplacer `StarHubFR.app`.

<!-- help: install -->
## 2. Installer des mods

**Depuis une archive.** Glissez un `.zip`, `.7z` ou `.rar` sur la fenêtre de l'app, depuis n'importe quelle page, ou passez par **Fichier › Installer des mods…** (⌘O). L'app reconnaît un mod seul ou un pack, annonce les dépendances manquantes et les conflits, puis installe. Si vous en déposez plusieurs à la fois, « Archive suivante » passe de l'une à l'autre.

**Depuis Nexus.** Avec un compte Premium, le bouton **Installer** télécharge directement. Avec un compte gratuit, la page Nexus s'ouvre : cliquez **Mod Manager Download**, l'app récupère l'archive.

Ce qu'il faut savoir :

- **Un mod neuf arrive en pause.** Activez-le dans la liste quand vous êtes prêt. Une mise à jour d'un mod actif le laisse actif.
- **Vos réglages sont gardés.** Le `config.json` et le `fr.json` d'un mod déjà installé ne sont jamais écrasés par une archive.
- **L'ancienne version est sauvegardée** avant d'être remplacée (voir [section 10](#10-retrouver-ce-qui-a-été-remplacé-ou-supprimé)).
- **Un fichier destiné à un autre mod** (un sac pour *ItemBags*, par exemple) est rangé dans le mod hôte, et l'app vous montre où.

<!-- help: pause -->
## 3. Activer, mettre en pause : la convention `X` / `.X`

Mettre un mod en pause renomme son dossier en le **préfixant d'un point** : `Mods/ColorfulVolume` devient `Mods/.ColorfulVolume`. SMAPI ne charge pas les dossiers à point. Rien n'est déplacé ni supprimé.

- **Un mod, une sélection ou tous.** Cliquez l'interrupteur d'une ligne ; sélectionnez plusieurs lignes (clic, ⌘clic, ⇧clic, ⌘A) puis Espace ; ou **Tout activer** sur la liste filtrée.
- **Le Finder cache ces dossiers** (⇧⌘. les montre). Un mod « disparu » du jeu mais qui prend toujours de la place est presque toujours un mod en pause.
- **Ne les supprimez pas à la main** : les dossiers à point de `Mods/` sont vos mods en pause, pas des fichiers cachés à nettoyer.
- **Les mods livrés avec SMAPI** (ConsoleCommands, SaveBackup) restent actifs, et ni eux ni la sonde StarHubFR ne se suppriment depuis l'app : elle vous le dit si vous essayez.
- **Avant de mettre en pause un mod qui écrit dans vos parties**, l'app mesure ce qu'il y a laissé. **Parties › Nettoyer…** retire les données des mods disparus, après une copie de la partie. Dans l'autre sens, **Réactiver ces mods** réactive les mods en pause dont une partie a besoin, avec leurs dépendances.
- **Revenir en arrière.** L'app enregistre l'état de vos mods avant chaque activation groupée, changement de profil, recherche du mod responsable ou benchmark. Pour y revenir : **Gestion des mods › ⏻ › Revenir à un état d'avant…**. Si une de ces opérations a été interrompue, l'**Accueil** vous le signale et propose « Tout remettre comme avant ».

<!-- help: profiles -->
## 4. Profils et groupes

Un **profil** décrit un **état** : quels mods sont actifs. Un **groupe** décrit un **rangement** : comment la liste est organisée. Les deux se complètent.

**Profils de mods.** Créez un profil vide, ou copiez les mods actifs du moment. Passer d'un profil à l'autre active et met en pause les mods d'un geste. Chaque profil peut garder ses propres réglages de mods (**Configuration par profil**) : en changeant de profil, vous retrouvez les `config.json` de ce profil.

**Prévisualiser un profil.** Cliquez la colonne **Mods** d'un profil (ou **Aperçu…** dans son menu) pour voir ce que son activation changerait : les mods qui seraient activés, ceux qui seraient mis en pause, et les conflits qui apparaîtraient. Aucun dossier n'est modifié. La colonne **Configs** affiche les configurations enregistrées pour ce profil et permet de les comparer à celles du profil actif.

**Profil appliqué incorrectement.** Si l'activation d'un profil n'est pas allée jusqu'au bout, une pastille orange l'indique sur sa ligne (« Application interrompue », « Appliqué à moitié » ou « Configs non réécrites »), avec un bouton pour corriger la situation.

**Groupes.** Dans **Gestion des mods**, « Regrouper par » vos groupes ou par catégorie. Un groupe se replie, s'active ou se met en pause d'un geste ; « Ranger dans » place une ligne ou une sélection dans un groupe.

**Marque « à écarter ».** Un mod que vous voulez sortir de la circulation sans le désinstaller : il reste grisé et regroupé sous son filtre.

<!-- help: updates -->
## 5. Mises à jour

**Mise à jour des mods** (⇧⌘U) vérifie tout votre parc sans compte ni clé, par smapi.io. Chaque mod concerné porte une pastille « ↑ version » dans la liste. Les mises à jour des mods en pause sont regroupées à part, dans une section repliée.

- **Avant d'installer**, l'aperçu dit ce que la nouvelle version change : options de config ajoutées ou retirées, textes à traduire, mods actifs qui lisent son code interne.
- **« Je l'ai déjà »** : pour un mod dont l'auteur publie sans changer le numéro de son manifeste. La ligne enregistre la version réellement installée et disparaît.
- **Les mods sans verdict** sont listés avec leur raison (pas d'identifiant, page masquée…). Un identifiant Nexus saisi à la main répare une clé cassée.
- **Si smapi.io ne répond pas**, l'app le dit et propose de vérifier directement sur Nexus.

<!-- help: troubleshooting -->
## 6. Quand le jeu plante ou qu'un mod refuse de charger

1. Lancez le jeu via SMAPI, reproduisez le problème, puis ouvrez **Diagnostic & Performances › Santé**. L'app lit le journal SMAPI et dit quoi faire, en clair : dépendance à installer, mod en double, mod incompatible avec votre version du jeu. Sous « Ce que vous pouvez faire », chaque conseil a un bouton pour l'appliquer. Si le journal est antérieur à votre dernière modification, le bouton est grisé et l'app en explique la raison.
2. **Journal** montre les lignes elles-mêmes, regroupées par mod, les plus problématiques en tête.
3. Si rien ne désigne de coupable, la carte **Trouver le mod responsable** met vos mods en pause par moitiés et vous pose une question à chaque relance. Une dizaine d'essais suffisent ; tout se remet comme avant en un clic.
4. **Alertes système** regroupe ce qui demande votre attention sur tout le parc, en trois onglets : **Alertes** (dépendances manquantes, doublons, dossiers à réparer), **Raccourcis clavier** et **Conflits entre mods** (deux mods qui remplacent le même contenu). « Voir le mod » ouvre la fiche de l'un ou l'autre des mods concernés.
5. **Une dépendance manque ou est en pause ?** Dans l'onglet **Dépendances** de la fiche, elle apparaît en premier, sous « À régler », avec un bouton « Activer » ou « Installer ». Le même bouton figure dans l'encart rouge sous la ligne du mod, dans la liste.

Pour demander de l'aide, déposez `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt` sur [smapi.io/log](https://smapi.io/log) et partagez le lien obtenu.

<!-- help: shortcuts -->
## 7. Raccourcis clavier en conflit

**Alertes système › Raccourcis clavier** liste chaque touche utilisée par vos mods actifs, cherchable par mod, réglage ou touche. Deux mods sur la même touche se déclenchent ensemble.

**« Proposer un plan »** calcule une solution :

- **Conflits seuls** : seul le mod qui cède change de touche.
- **Tout ranger par famille** : lettres pour les mods d'action, chiffres pour l'information courante, touches F pour ce qui sert rarement.

Décochez une ligne pour garder une touche ; corrigez la famille d'un mod mal deviné, l'app s'en souviendra. **Appliquer** sauvegarde d'abord les `config.json` concernés, puis ne change que le raccourci visé ; le bilan dit ce qui a bougé et ce qui reste. **Annuler le plan** remet les fichiers, tant qu'aucune autre sauvegarde n'est passée entre-temps.

Fermez le jeu avant d'appliquer : un mod relit sa configuration au lancement. Après un changement de profil qui crée des conflits, une alerte sur **Profils de mods** mène directement au plan.

<!-- help: performance -->
## 8. Mesurer les performances

**Diagnostic & Performances › Performances** répond à « ce mod ralentit-il mon jeu ? ».

1. **Installez la sonde StarHubFR**, un petit mod SMAPI livré avec l'app. Elle n'utilise pas le réseau et ne change rien d'autre ; elle mesure les chargements, la fluidité et la mémoire pendant que vous jouez.
2. **Jouez normalement** : l'onglet compare deux moments et dit ce qui a changé (mods, versions, réglages).
3. Pour une réponse nette sur un changement précis, **Mesurer** lance une mesure guidée : la sonde conduit la partie avant puis après, et l'app rend le comparatif. Vous gardez le changement ou revenez à l'état d'avant, même après une interruption.

Un écart n'est affiché comme gain ou perte qu'au-delà du bruit mesuré entre vos propres sessions ; en dessous, il reste gris. Pour arrêter la sonde, mettez-la en pause comme n'importe quel mod.

<!-- help: translate -->
## 9. Traduire un mod en français

Ouvrez la fiche d'un mod, onglet **Traduction**.

- **Anglais à gauche, français à droite**, clé par clé. Un mod sans `fr.json` en reçoit un au premier enregistrement.
- **Les marqueurs du jeu** (noms de joueur, retours à la ligne, couleurs…) s'affichent en couleur et s'insèrent d'un clic. Une marque qui casse le jeu (commande de dialogue, `#` seul, `{{…}}`) perdue ou ajoutée bloque l'enregistrement, et l'app dit laquelle est manquante ou en trop. Un portrait, le nom du joueur (`@`) ou un saut de page déplacés s'affichent sous le champ, « À vérifier », sans bloquer.
- **Brouillon par IA locale** : avec [Ollama](https://ollama.com) ou [LM Studio](https://lmstudio.ai) sur votre Mac, l'app propose une traduction marquée « À relire ». Rien ne quitte votre machine. Le glossaire des noms officiels du jeu est imposé au modèle. Si aucun moteur de traduction n'est configuré, le message d'erreur propose **Ouvrir les réglages de traduction**.
- **Traductions FR**, segment **À finir** : les traductions commencées et pas finies, ou à revoir, du plus gros reste au plus petit ; « Traduire » ouvre la fiche. Segment **Sur Nexus** : les traductions déjà publiées pour vos mods, souvent il suffit d'en installer une. Pour écarter un résultat erroné, cliquez le pouce vers le bas ; la liste « Écartés », en bas de page, permet de le rétablir. Le badge de la barre latérale indique combien de mods actifs ont une traduction à installer ou à mettre à jour.

Une traduction écrite dans l'app vit dans le dossier du mod. Une mise à jour du mod ne l'écrase pas ; l'aperçu de mise à jour dit quelles clés sont à reprendre.

<!-- help: recover -->
## 10. Retrouver ce qui a été remplacé ou supprimé

- **Une mise à jour a remplacé un mod, vous voulez l'ancienne version** — **Sauvegardes des mods** › Restaurer (le mod revient en pause).
- **Un `config.json` a été réécrit** (éditeur de config, plan de raccourcis) — le menu **Restaurer** de l'éditeur propose les dernières versions. Vous pouvez aussi passer par **Sauvegardes des mods** › Configuration, où les sauvegardes sont classées par mod ; « Comparer » affiche les différences avant de restaurer.
- **Vous avez supprimé une sauvegarde de mod ou de configuration** — elle est dans la Corbeille du Mac tant que vous ne l'avez pas vidée ; elle ne revient pas dans la liste de l'app.
- **Vous avez mis des mods à la corbeille depuis l'app** — **Entretien** › Restaurer, ou **Tout restaurer** pour un lot. Le lien « Corbeille des mods › » de **Sauvegardes des mods** y conduit aussi.
- **Les sauvegardes prennent trop de place** — **Entretien** › Libérer de la place : choisissez combien en conserver par mod (1, 3 ou 5) ; les autres sont placées dans la Corbeille du Mac. Indépendamment de ce choix, l'app conserve automatiquement toutes les sauvegardes de moins de 30 jours, comme l'indique le segment Installations.
- **Un dossier illisible ou parasite a disparu de `Mods/`** — **Quarantaine** : les analyses y mettent de côté ce qui gênait, rien n'est supprimé.
- **Une partie** — **Parties** : copie avant chaque modification.
- **Une copie complète, à garder à part** — **Entretien** › Sauvegarder le dossier des mods (mods en pause compris), ou l'icône d'archive de **Parties** : un `.zip` dans le dossier de votre choix. L'app vérifie la place, estime la durée, montre l'avancement ; « Annuler » ne laisse rien derrière.

Tout cela vit dans `~/Library/Application Support/StarHubFR/`.

<!-- help: other-managers -->
## 11. Avec d'autres gestionnaires de mods

StarHubFR, Vortex, Stardrop et le Nexus Mods App lisent **le même dossier** `Mods/` du jeu.

- **Un seul outil met en pause à la fois.** La pause de StarHubFR est un dossier à point ; Vortex et Stardrop l'ignorent ou font autrement. Si vous passez d'un outil à l'autre, remettez les mods dans l'état voulu avec **un seul** des deux.
- **Un mod installé par StarHubFR est un dossier ordinaire.** Les autres outils le voient comme s'il avait été posé à la main.
- **Le jeu se lance toujours par SMAPI** : un mod tourne pareil quel que soit l'outil qui l'a installé.

<!-- help: uninstall -->
## 12. Désinstaller StarHubFR proprement

Les mods en pause vivent dans des dossiers à point de `Mods/`. Si vous retirez l'app sans les remettre, le jeu ne les chargera plus et ils sembleront perdus.

1. Dans **Gestion des mods**, choisissez le cadrage **Tous**, puis **Tout activer** ; ou supprimez vous-même les mods en pause dont vous ne voulez plus.
2. Vérifiez que le cadrage **En pause** est vide.
3. Mettez en pause ou supprimez le dossier `Mods/StarHubFR Probe` si vous aviez installé la sonde. La mettre en pause depuis l'app la retire aussi de la liste de chargement prioritaire de SMAPI.
4. Quittez StarHubFR et mettez `StarHubFR.app` à la corbeille. Le dossier `Mods/` est alors un dossier SMAPI ordinaire.

Pour effacer aussi les données de l'app (profils, sauvegardes de mods, historiques, traductions en cours) :

- supprimez `~/Library/Application Support/StarHubFR/` ;
- supprimez `~/Library/Preferences/com.mrbabilo.StarHubFR.plist` ;
- dans **Trousseau d'accès**, supprimez les éléments `com.mrbabilo.StarHubFR` (clé Nexus, clé DeepL).

Le dossier `Backups/` contient les anciennes versions de vos mods : regardez-le avant de le supprimer.
