# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The SMAPI diagnostics owe a lot to [SMAPILogDoctor.py](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py)
by ZeroXPatch (the idea of a player-facing SMAPI log doctor), to SMAPI's own
[log parser](https://smapi.io/log/), and to the [SMAPI sources](https://github.com/pathoschild/SMAPI)
where the exact log format was verified.

## [Unreleased]

### Fixed

- **Mettre à jour un composant de pack ne laisse plus la mise à jour affichée** : après une installation venue de Nexus, l'app ancre la version qu'elle vient de poser, retient l'identifiant de la page et réconcilie le numéro du manifeste — trois gestes qui relisent le mod à l'endroit où il a été écrit. Or la feuille d'installation recalculait cet endroit de son côté, en cherchant le mod déjà installé parmi les seules lignes de premier niveau : jamais un composant de pack, soit **239 des 1 095 mods de votre parc**. Elle reprenait en plus le nom de dossier de l'archive, ce qui détache un composant de son pack. Le chemin étant faux, les trois gestes ne trouvaient rien et s'abstenaient en silence : la mise à jour restait annoncée après avoir été installée, et l'identifiant Nexus se perdait. L'installateur dit désormais lui-même où il a écrit. Une installation que vous choisissez de *renommer* fait exception à l'ancrage, et volontairement : elle laisse l'ancienne copie en place, deux dossiers portent alors le même identifiant, et affirmer la version de la copie mise en pause décrirait mal celle que le jeu charge.

## [1.35.2] - 2026-09-03

### Fixed

- **Le framework qu'exige un mod ne manque plus à ses dépendances** : la plupart des mods de contenu ne déclarent leur seule exigence — Content Patcher, Farm Type Manager, Fashion Sense… — que par le champ `ContentPackFor` du manifeste, et l'aperçu d'installation ne lisait pas ce champ. Sur votre parc, **625 des 1 085 manifestes** le déclarent : 254 s'annonçaient « aucune dépendance » alors qu'ils ne font rien sans leur framework, et 340 affichaient une liste amputée de celui-ci — dont 483 mods, au total, qui attendent Content Patcher. L'écran lisait les dépendances par une boucle à lui, quand la liste des mods installés passait déjà, elle, par un lecteur qui sait le faire. Les deux partagent désormais ce lecteur, qui écarte aussi les doublons : **8 mods du parc déclarent deux fois la même dépendance** (six fois pour *Distant Lands*), ce qui affichait 13 lignes en double.

- **Une dépendance installée dans un pack n'est plus annoncée manquante** : la feuille d'installation cherchait chaque dépendance parmi les seules lignes de premier niveau de votre liste de mods. Or un pack n'y occupe qu'une ligne, ses composants vivant à l'intérieur — et ce sont eux que les autres mods réclament. Sur votre parc, **296 déclarations de dépendances** (109 identifiants distincts) désignent un composant de pack : `FlashShifter.SVE-FTM`, `Rafseazz.RSVCC`, `ichortower.HatMouseLacey.Core`… Toutes s'affichaient en rouge « manquante », avec une recherche Nexus proposée pour un mod déjà installé. L'installateur, lui, savait déjà regarder dans les packs : sa règle est désormais la seule du dépôt, partagée par les deux écrans.

- **Deux sauvegardes différentes ne sont plus prises pour la même** : l'empreinte qui décide si une sauvegarde est redondante — et donc supprimable — comparait les fichiers par leur seul nom, sans le sous-dossier qui les porte. macOS y est pour quelque chose : le dossier des sauvegardes passe par `/var`, un lien vers `/private/var`, et le calcul du chemin relatif échouait sur ce décalage puis se rabattait sur le nom de fichier nu. Deux arbres ne différant que par **quel** sous-dossier contient chaque fichier rendaient la même empreinte : la seconde sauvegarde était jugée en double et effacée. Le chemin est désormais résolu par `realpath(3)` — la fonction Foundation habituelle, mesurée, ne résout justement pas `/var`.

- **Écrire dans une sauvegarde ne détruit plus la structure d'un champ** : le lecteur de fiche joueur ne refermait pas correctement une balise auto-fermée. Un champ composé uniquement de telles balises était rendu comme une **valeur** portant son propre markup — et l'écriture acceptait de l'écraser par un nombre, emportant la structure dans le fichier enregistré. Sur votre sauvegarde *Zofia*, **cinq champs** sont dans ce cas : `shieldSlot` (`<Item xsi:nil="true" />`), `adventureBar` (16 sous-balises), `lastGotPrizeFromGil`, `lastDesertFestivalFishingQuest` et `SpaceCore_PersonalCurrencies`. Les champs réellement lus par l'app (genre, santé, cheveux…) sont tous scalaires : leur lecture est inchangée.

- **Un lien de téléchargement expiré n'accuse plus votre clé API** : un `403` de Nexus était toujours rendu « échec de l'authentification — vérifiez votre clé API dans les Réglages ». Or un lien `nxm://` ne sert qu'une fois et se périme vite : c'est le lien qui est mort, pas la clé. Le message envoyait réparer ce qui n'était pas cassé. Le même statut couvre en fait trois pannes distinctes selon l'appel — abonnement requis, lien expiré, clé en cause — et l'app les distingue désormais : pour un lien expiré, elle dit de relancer le téléchargement depuis la page du mod.

- **Déposer un fichier dans un mod hôte protégé n'échoue plus sans recours** : le dépôt d'un contenu reconnu (un sac d'objets dans son mod hôte, par exemple) écrivait sans ouvrir les droits du dossier visé — le seul chemin d'installation du dépôt à ne pas le faire. Les archives restituent leurs modes à l'extraction : un hôte revenu d'une mise à jour avec ses dossiers en lecture seule refusait le dépôt, panneau d'erreur à l'appui. Le mécanisme est vivant sur votre parc — `.[CP] Toothless Pet` porte encore six dossiers dans ce cas ; l'hôte de la seule règle actuelle est inscriptible aujourd'hui, d'où un défaut latent plutôt qu'ouvert. Les droits sont maintenant ouverts puis rendus tels quels, sans jamais remonter au-delà du mod hôte.

- **Le drapeau « à relire » de l'éditeur de traduction dit enfin ce qu'il est** : quand la traduction par lot écrit une valeur sans qu'elle ait été relue, la ligne porte un petit glyphe orange. Son sens ne s'apprend qu'au survol — mais le glyphe faisait 8 points, moitié moins que ce qu'un curseur peut tenir immobile les deux secondes qu'exige macOS : l'info-bulle ne s'affichait donc jamais, et le drapeau restait une décoration inexplicable. Sa zone de survol passe à 18×18, sans bouger d'un pixel à l'écran.


## [1.35.1] - 2026-09-03

### Fixed

- **Activer un mod ne peut plus déplacer le dossier d'un autre** : mettre un mod en pause le renomme en le préfixant d'un point, et l'app considère les deux formes comme un seul nom. Deux mods différents peuvent pourtant les occuper — sur votre parc, `[CP] Seaside Sounds` (actif, de witchtopia) et son homonyme en pause (de Liana) sont deux mods de deux auteurs. Réactiver celui en pause aurait écarté l'autre sous un nom de sauvegarde, lui faisant perdre favori, note, configuration de profil et identifiant Nexus — sans un mot. L'app vérifie désormais à qui appartient le dossier avant d'y toucher, et refuse en le disant. Le dossier écarté, lui, est enfin masqué au jeu.

- **Un dossier disputé par deux mods est enfin signalé** : c'est le versant visible du correctif ci-dessus. Tant que rien ne le nommait, l'un des deux mods **disparaissait de la liste** sans explication — ils partagent leur identité d'affichage — et partageaient aussi identifiant Nexus, catégorie, favori, note et configuration de profil. L'écran Alertes système porte désormais une ligne qui nomme le dossier et les deux mods, avec un bouton **Montrer dans le Finder** qui sélectionne les deux dossiers côte à côte : de quoi voir lequel porte le point de tête, et renommer celui qu'on veut.

- **Une mise à jour ne disparaît plus dans la ligne d'un pack voisin** : le regroupement par pack de l'écran des mises à jour s'indexait sur l'identifiant Nexus, qui n'identifie pourtant pas un mod. Sur votre parc, **4 identifiants** sont déclarés à la fois par un composant de pack et par un mod extérieur — `Automate` revendique par exemple la page de *Powered Automation*, une clé copiée à tort par son auteur — et le mod extérieur se faisait absorber : une seule ligne pour deux mods, la seconde mise à jour invisible. Deux identifiants sont même revendiqués par plusieurs packs (l'un par trois), auquel cas la mise à jour d'un pack s'affichait sous le nom d'un autre. Le regroupement passe par l'identifiant unique du mod.


## [1.35.0] - 2026-09-03

### Added

- **« Je l'ai déjà » n'est plus un aller sans retour** : la page Mises à jour porte désormais un bloc repliable « *N* mods marqués “Je l'ai déjà” », visible **même quand tout est annoncé à jour** — c'est justement là qu'il manquait. Chaque ligne montre le numéro que vous avez affirmé **et** celui que le dossier déclare, l'écart en couleur, avec deux boutons : **Voir la fiche** — qui ouvre le mod sur son onglet État, de quoi juger avant de décider — et **Réafficher**. Une explication dit ce que le geste a fait et ce que le bouton défait. Sur une installation de référence, 34 mods étaient éteints sans que rien ne le dise, dont plusieurs par mégarde — l'un affirmé en 1.3.0 pour un dossier en 0.1.0.

### Fixed

- **La vérification des mises à jour ne rendait plus qu'un sixième du parc** : quand vous cliquez « Je l'ai déjà », l'app retient le numéro **affiché** — souvent l'étiquette libre d'une page Nexus (« 5 », « 1.01 »). Or smapi.io, interrogé avec un numéro qu'il ne sait pas lire, répond « tout va bien » et **une liste vide pour les 150 mods du même envoi**, sans erreur ni message. Sur votre installation, 15 mods étaient dans ce cas. L'app sait re-découper un lot vide pour isoler l'entrée fautive, mais ce filet a un budget de 32 requêtes pour toute la vérification : quinze entrées toxiques l'épuisent d'emblée. Résultat mesuré : **471 mods rendus sur 1 073**, **4 mises à jour visibles sur 7** — trois disparaissaient avec leur lot — et 40 requêtes au lieu de 8, dont deux seulement nommaient le mod fautif. Le numéro envoyé est désormais traduit en une forme que le serveur sait lire : le filet n'a plus rien à rattraper, l'affirmation « je l'ai déjà » continue de valoir, et le journal dit quand une substitution a lieu.

- **Préparer un lot de traduction ne fige plus l'app pendant deux minutes** : chaque phrase du lot était confrontée aux 1 126 termes du glossaire, un par un — 9 ms par phrase, sur le fil principal, sans rien afficher. Sur le plus gros mod à traduire du parc (16 482 clés sans français), « Exporter un lot » demandait **149 secondes** ; l'import, qui reconstruit le même lot, autant. Les termes sont désormais rangés par premier mot : **3 secondes**, et exactement les mêmes termes trouvés (vérifié sur 20 762 phrases du parc).

- **L'accord en genre ne bloque plus la traduction** : `${fermier^fermière}$` — la forme que le jeu emploie pour accorder selon le genre du personnage joué — était traitée comme une marque à recopier telle quelle. Son contenu, pourtant du texte affiché, était voilé au traducteur et rendu en anglais par la traduction par lot ; et le français en ajoute là où l'anglais reste neutre, si bien que **1 092 des 4 331 lignes** signalées « marque perdue » sur le parc étaient des traductions justes, refusées à l'enregistrement. Les bornes restent protégées, l'intérieur se traduit — et les marques qu'il porte restent vérifiées. La localisation française du jeu fait de même dans 10 cas sur 10.

## [1.34.1] - 2026-09-03

### Fixed

- **Une réponse HTTP 200 illisible ne détruit plus le cache de compatibilité** : la liste Pathoschild était écrite sur le disque dès la réponse reçue, avant toute vérification. Une page d'erreur de GitHub, un portail captif ou un transfert coupé rendent tous un 200 dont le contenu n'est pas lisible — l'app écrasait alors ses 919 Ko de données valides et annonçait « 0 mod » comme un succès. Ce cache sert aussi à retrouver la page Nexus des mods que smapi.io ignore, hors ligne : un seul mauvais téléchargement emportait les deux. Le journal dit désormais lequel des trois cas s'est produit.
- **Les Journaux n'inventent plus de mods** : quand SMAPI journalise une erreur sous son propre nom, l'app cherche le mod responsable en tête du message — utile pour de vraies erreurs, mais ses propres alertes y passaient aussi. « You can update 1 mod » et « Galaxy auth failure » s'affichaient donc en pastille cliquable qui ne menait nulle part, et comme groupes dans l'affichage « par mod ». Un nom deviné n'est retenu que s'il désigne un mod installé ; les noms que SMAPI écrit lui-même, eux, ne sont jamais remis en cause (1 439 sur le journal de référence, inchangés).
- **Le lien d'une mise à jour annoncée par SMAPI mène enfin à la bonne page** : SMAPI accole la version installée derrière l'adresse (`…/releases (you have 1.6.1…)`), et cette parenthèse faisait partie du lien. Le bouton « Ouvrir la page » arrivait donc sur un 404, et le lien cliquable affichait l'adresse encodée en clair. La seule mise à jour annoncée dans le journal de référence était dans ce cas.
- **Le filet de compatibilité hors ligne ne peut plus se taire en silence** : la liste Pathoschild (4 720 mods, le filet quand smapi.io ne répond pas) était lue par un découpage aveugle aux fins de ligne Windows. Le dump publié est en LF aujourd'hui, mais s'il passait en CRLF, le premier commentaire du fichier emportait tout le reste : zéro verdict et zéro identifiant Nexus, sans un mot. Vérifié en convertissant le dump réel — refusé avant, 4 720 entrées après.

- **Six mods retrouvent la description de leurs options** : leur `content.json` était déclaré illisible et l'éditeur de configuration n'affichait plus que des clés brutes. Sur les 606 `content.json` du parc, **14 étaient refusés pour des formes que le jeu, lui, accepte** — une clé écrite sans guillemets, une chaîne entre apostrophes, une valeur qui court sur plusieurs lignes, une marque d'ordre des octets en tête. Douze se lisent désormais, dont sept qui décrivent des options : 126 options reviennent (95 pour `[CP] Friendable Mr Qi`, 12 pour `.HB`). Les 1 187 autres fichiers se lisent exactement comme avant.
- **Un caractère hors du plan de base ne rend plus un fichier illisible** : un emoji écrit en paire de substitution (`\uD83D\uDE00`), la forme que produit .NET, faisait échouer la lecture du `config.json` ou du `content.json` entier. Aucun cas sur le parc actuel — trois fichiers de traduction en portent, eux, et passaient déjà par un autre lecteur.
- **Le compte de raccourcis n'annonce plus des touches qui n'en sont pas** : un réglage laissé sur « None » ne lie rien, mais était compté. L'écran d'analyse affichait ainsi 76 raccourcis pour 58 liaisons réelles — 18 réglages désactivés (5 dans CJB Cheats Menu, 7 dans UI Info Suite 2) gonflaient le chiffre.

## [1.34.0] - 2026-09-03

### Changed

- **Les liens `nxm://` et téléchargements lancés pendant qu'un autre tourne — ou pendant que la feuille d'installation est ouverte — ne sont plus refusés** : ils attendent dans une file (un clic répété sur le même fichier ne duplique pas l'entrée) et démarrent tour à tour quand le créneau se libère. Les dépôts de traduction gardent l'ancien comportement.

### Fixed

- **Une archive sans manifeste nommée en clair retrouve son mod** : quand le dossier de l'archive écrit le nom en toutes lettres (`UI Info Suite 2 Alternative FR`) et que le mod, lui, le tasse (`UIInfoSuite2Alt`), aucun mot n'était partagé — la feuille « à quel mod ? » proposait quatre mods, tous faux, sans le bon. Une suite de majuscules se coupe désormais avant le mot qu'elle précède.
- **Les dépôts déjà enregistrés sans identifiant se réparent au chargement** : leur nom d'archive porte l'identifiant de la page et la version, que l'app n'apprenait à relire que depuis le 29 août. Sur les 13 dépôts enregistrés, **4 retrouvent ainsi leur page et leur suivi de mise à jour** — un identifiant déjà connu, lui, n'est jamais retouché.
- **Une archive téléchargée par l'app garde le nom que Nexus lui donne** : elle était posée sous un nom en UUID, ce qui jetait l'identifiant de la page et la version que ce nom porte. Un lot de sacs ou une traduction déposés depuis un lien `nxm://` s'affichaient donc dans la fiche du mod sous un nom comme `78388FD4-DBBA-4FCD-B747-29425800BBDB`, sans suivi de mise à jour — 4 des 13 dépôts enregistrés étaient dans ce cas. Et l'identifiant de la page est retenu même si Nexus n'avait pas nommé le fichier.
- **Le nom d'une archive sans extension reconnue n'est plus tronqué** au dernier point : `FishingLogbook - FR 50233 1.1.0 …` perdait tout ce qui suivait `1.1`.
- **Une description Nexus au balisage pathologique ne peut plus tuer l'app** : `[center]` est la seule balise qui fasse récurser le lecteur de blocs, et 10 000 niveaux imbriqués débordaient la pile. La récursion s'arrête au huitième niveau — le centrage se perd au-delà, le texte et les images restent — et une description à 2 000 niveaux se lit désormais en 50 ms au lieu de 2,9 s.
- **Un exemple de config replié dans un spoiler ne s'ouvre plus sur du vide** : le bloc `[code]` était extrait avant conversion et remplacé par un marqueur, que la relecture du spoiler résolvait contre rien. C'est la forme la plus courante d'un spoiler de page de mod.
- **Les descriptions Nexus ne mangent plus les `<…>` qu'un auteur voulait montrer** : les entités HTML étaient décodées *avant* le retrait des balises, si bien que `&lt;ContentPackMainFolder&gt;` devenait une balise puis disparaissait. Mesuré sur 39 descriptions réelles : 3 en portaient, dont une consigne d'installation et une signature d'API C#.
- **Une balise BBCode suivie d'une parenthèse ne s'affiche plus en clair** : `[font=Tahoma](assets > …)` survivait au nettoyage final, qui épargnait toute balise suivie d'une parenthèse pour protéger les liens déjà produits. Le garde ne protège plus que les liens et les couleurs que l'app émet elle-même.
- **Une destination de lien sans hôte n'est plus rendue comme un lien** : `[url=http:]` ou `[url=http://]` autour d'une URL lisible — vu chez « Happy Birthday » — produisait un lien mort dont le crochet fermant s'affichait. Le libellé reste, la destination est abandonnée ; une image sans hôte n'est plus proposée non plus.
- **Une ligne vide referme désormais un groupe d'avertissements SMAPI** : `"".allSatisfy` rendant `true` par vacuité, la ligne vide était prise pour un séparateur de tirets et le groupe restait ouvert — la puce d'un message de mod qui suivait se faisait compter parmi les mods cassés, patchés ou à accès console direct.
- **Un registre des traductions corrompu ne se perd plus en silence** : chaque écriture pose désormais un backup à côté du fichier, et un fichier illisible se restaure tout seul au chargement — sans lui, la désinstallation des traductions déjà posées devenait impossible, sans qu'aucun message le dise.
- **Un échec d'écriture de l'historique d'erreurs se signale désormais** : cette histoire ne se rebâtit pas (chaque journal SMAPI écrase le précédent) ; une panne disque passait jusque-là pour une sauvegarde réussie.
- **Les traductions de secours étaient cherchées par un chemin reconstruit à la main** — trois copies du même chemin à travers la VM et les managers ; un changement de layout des managers aurait fait chercher le finder dans le vide, en silence. Les managers exposent désormais `backupsDirectory`, source unique.
- **La passe d'ancrage des versions lisait `nexusUpdates` depuis le fil du scan** — propriété publiée sur le fil principal, donc en course, et consolidée par pack : un enfant de pack perdant la consolidation n'y figure pas et perd sa suggestion de version. Elle lit désormais le cache plat sous son verrou, qui a une ligne par mod.
- **« Tout activer / tout désactiver » pouvait croiser la file des bascules unitaires** — un renommage unitaire en vol rencontrait les renommages en masse sur les mêmes dossiers ; les gardes disque contenaient la collision, un garde sur la file l'empêche désormais d'exister.

## [1.33.0] - 2026-09-02

### Changed

- **Alertes système en liste unifiée triée par gravité** (critique, avertissement, information) : diagnostics SMAPI, raccourcis en collision et conflits entre mods sont désormais fusionnés et triés dans un seul écran, avec un pied « N problèmes · M critiques ». Un badge partagé (glyphe + couleur + libellé) affiche la gravité partout, jamais la couleur seule.
- **Quarantaine (doublons, dossiers isolés) plus lisible** : identités de ligne stables, couleurs aux tokens de l'app, troncature d'un chemin long désormais annoncée.
- **Le rapport de restauration d'un backup d'installation** quitte l'alerte texte pour un panneau à sept champs étiquetés.
- **`SystemAlertsView` et `QuarantineView` sortent de `MainView.swift`** (1519 → 1163 lignes), sans changement de comportement.
- **`activeConflictCount` dérive maintenant de `healthIssues`**, comme `systemAlertCount` — l'ancien recalcul séparé (reconstruction de `activeFolders`/`candidates` puis rappel de `liveConflictCount`) est retiré.
- **Les deux panoramas de l'écran d'alertes portent leur compte** : le rapport de raccourcis et la vue des conflits affichent le nombre de lignes détectées sur leur bouton, capsule masquée à zéro. Leur fenêtre passe de 640×580 à 980×720 — les deux alignent des noms de mods tronqués à une ligne, et un conflit en montre deux côte à côte.
- **Une ligne d'information mène désormais aux deux endroits** : la fiche du mod concerné *et* la ligne du journal. La fiche dit ce qu'est le mod, le journal ce qui s'est passé. Les lignes critiques gardent un chemin unique.

### Fixed

- **Le bouton « Restaurer » d'une sauvegarde de config de mod ne restaurait rien.** Il relisait la sauvegarde ciblée depuis un état déjà remis à `nil` par la fermeture de l'alerte de confirmation — le bouton s'affichait, la confirmation s'ouvrait, mais rien n'était restauré. Le bouton « Supprimer » portait la même faille. Les deux sont corrigés.
- **La pastille d'alertes sonnait sur un parc sain.** Les notices SMAPI bénignes (`.info`) étaient comptées comme des problèmes dans la pastille de la barre latérale, la tuile d'accueil et le pied de l'écran d'alertes — mesuré : 7 notices bénignes, 0 échec, 0 conflit affichaient « 7 problèmes ». Elles restent visibles dans la liste, mais seules les lignes critique/avertissement comptent désormais.
- **Un mod à la fois « failed » et « skipped » aurait produit deux lignes critiques** sous deux titres différents (l'un avec la version, l'autre sans), indétectables à l'œil. Garde ajoutée par symétrie avec celle qui protège déjà les dépendances manquantes.
- **Les conflits de mods affichaient des noms de dossiers** (`ModConflictPair.folderName`) au lieu de noms de mods, seule ligne de l'écran d'alertes à le faire.
- **Le bouton d'une alerte n'emmenait nulle part de précis** : il ouvrait la liste des mods entière, jamais le mod fautif, et « Voir les journaux » ouvrait la vue générale, jamais l'erreur en cause. Chaque ligne désigne maintenant sa cible — la fiche du mod concerné, ou les journaux filtrés sur le message —, et son libellé dit laquelle.
- **Le rapport de raccourcis et le panorama des conflits étaient devenus inatteignables** en sortant `SystemAlertsView` de `MainView.swift`. Les deux reviennent en feuilles, depuis la barre d'outils de l'écran d'alertes ; le bouton « Écarter » d'un conflit redevient accessible.
- **Une ligne d'alerte s'intitulait « apiIntegration »** — un nom de symbole, en anglais. SMAPI décrivant ses propres sections (« … you can ignore this warning. ») était pris pour un mod relativisant son erreur. Les notices sans mod portent désormais un titre traduit ; la carte de santé en comptait une de trop.
- **Le bouton d'un conflit ne trouvait pas un mod installé sous un pack.** Seuls les dossiers de premier niveau étaient comparés, alors qu'un conflit peut nommer un composant.
- **Ouvrir un mod depuis une alerte tombait sur sa description**, alors que l'alerte parle de son état. La fiche s'ouvre maintenant directement sur l'onglet « État » — compatibilité, erreurs, raccourcis, conflits.

## [1.32.0] - 2026-09-02

### Changed

- **Bandeau de la fiche de sauvegarde remis à plat** : le contenu passe de deux rangées empilées à une seule rangée centrée, ce qui libère la hauteur existante — titre de 20 à 26 pt, sous-titre de 12 à 15 pt, avatar de 44 à 76 pt, vignette de ferme de 80×78 à 96×92. La hauteur du bandeau (`heroHeight`) est inchangée. Le sous-titre sépare désormais la date et le nom de la ferme par un point, et seule la ferme se tronque quand la place manque.
- **Lisibilité du texte du bandeau** : un second voile, horizontal, part du bord gauche là où le texte vit et s'efface avant la vignette. Le voile de pied seul ne couvrait pas la hauteur où le titre se pose — celui-ci se lisait donc selon la zone d'illustration qu'il recouvrait.
- **Cadrage de l'avatar** : zoom ×1,34 et remontée du visage, valeurs mesurées sur les deux illustrations. Le cadrage plein pot laissait la moitié du disque au décor de la ferme et la tête trop basse.
- **Vignettes de ferme allégées** : 248×260 → 190×200 pour un affichage à 80×78, soit 985 Ko → 588 Ko dans le bundle.
- **Lecture d'une sauvegarde 4× plus rapide** (`H-T5d`). Les scalaires de niveau `<SaveGame>` — `whichFarm`, `goldenWalnuts`, `whichModFarm` — sont écrits par le jeu **après** ses grandes collections : mesurés sur les 6 fichiers du parc, ils vivent dans le dernier 1,2 % du fichier. Les chercher sur le fichier entier coûtait ~313 ms chacun. Ils sont désormais cherchés dans la queue, avec une **ancre** (`whichFarm`) qui vérifie qu'on a bien attrapé cette zone et fait repartir du fichier entier sinon — le résultat ne peut donc pas être pire qu'avant. Et la date (`yearForSaveGame`, `seasonForSaveGame`, `dayOfMonthForSaveGame`), qui est un champ du fermier, sort de la passe unique sur `<player>` au lieu de trois balayages de plus. Mesure : **1028 ms → 228 ms** sur la sauvegarde de 37 Mo, 1191 → 287 ms sur l'ensemble des parties listées.
- **Une sauvegarde inchangée n'est plus relue du tout.** `fetchSaves()` reparsait chaque dossier à chaque rafraîchissement de la page Parties, dossiers de secours compris. La lecture est mémorisée par chemin, avec une empreinte qui croise **date de modification et taille** : la date seule ne suffit pas (restaurer une sauvegarde de secours recopie un fichier en la préservant), la taille seule non plus (éditer 500 en 600 ne la change pas). Tout chemin d'écriture — édition, suppression, duplication, restauration, inventaire — vide le cache explicitement, ce que l'empreinte seule ne pouvait pas couvrir : une restauration serait passée inaperçue et la fiche aurait continué d'afficher la sauvegarde d'avant.
- **Build incrémental de l'app** (`F2-T2`, outil de développement). `python3 build_app.py --incremental` compile en objets par fichier avec le suivi de dépendances de swiftc, au lieu de recompiler les 211 fichiers en un seul module à chaque fois. Mesuré : 141,7 s → 2,4 s pour une modification isolée, 30,1 s dans le pire cas (changement de signature dans le ViewModel). Le binaire produit porte le même nombre de symboles définis (70 791) et la même architecture. **C'est désormais le chemin par défaut**, après vérification au lancement ; `--whole-module` rend l'ancien.
- **Quick wins sur la chaîne de build** (`F2-T1` dans la ROADMAP) : `build_app.py` ne réécrit plus `compile_commands.json` quand l'ensemble des fichiers Swift (chemin absolu + ordre) est inchangé depuis la dernière passe — fingerprint dans `.build/compile_commands.fingerprint`. `check_standards.py` cache son verdict par empreinte (mtime agrégé + tailles par fichier) dans `.standards-source-freshness{.counts,.info}` : un build chaud où rien n'a bougé passe de **860 ms à 49 ms (×17)**, les 10 regex sur 211 fichiers étant skippés. `--report` et `--update` court-circuitent le cache. Lecture de `L10n.swift` passée sous `with open(...)` (correction d'une fuite de FD), et strip des commentaires `//` avant le regex `static let \w+ = "..."` (un commentaire évoquant une clé pouvait la faire déclarer « undeclared »). Net sur le build complet : ~1 s sur 2m22s — le bottleneck `swiftc` whole-module ne bouge pas et relève de `F2-T2` (refactor d'architecture : compiler en `-c` par fichier avec cache objet, ou basculer la cible UI en SPM à deux cibles).

### Fixed

- **Supprimer une partie ne demandait aucune confirmation.** Les trois points d'entrée — menu contextuel d'une carte, menu d'une ligne, bouton de la fiche — appelaient la suppression directement. Le dossier complet de la partie part à la corbeille : récupérable, mais sans avertissement, et l'inverse du réglage voisin puisque supprimer une simple *sauvegarde de secours*, elle, confirmait déjà. Les trois chemins passent désormais par une confirmation nommant la corbeille.
- **Les confirmations de la timeline de sauvegardes ne s'ouvraient qu'à moitié.** `SaveTimelineView` portait **deux** modificateurs `.alert` : dans ce cas une seule des deux se présente. « Restaurer » ne demandait donc jamais confirmation, pendant que « Supprimer » le faisait. Changer d'API n'a fait que déplacer le perdant — mesuré dans les deux sens — et c'est le nombre de modificateurs qui est en cause, pas leur génération. Les deux confirmations passent désormais par **un seul** `.alert` piloté par un enum à deux cas. La sauvegarde ciblée transite par `presenting:` plutôt que d'être relue depuis l'état : les actions s'exécutent après la fermeture, quand le binding a déjà remis la valeur à `nil`.
- **La date de la sauvegarde pouvait être celle d'un monstre de quête.** Même faute que pour le sexe du fermier : `yearForSaveGame` et consorts étaient pris à la première occurrence du fichier, et un monstre imbriqué dans `<player>` porte les siens. Ils viennent maintenant du fermier, avec repli hors du bloc pour les sauvegardes qui ne les porteraient pas là.
- **Les deux vignettes du hero s'éteignaient sur une sauvegarde qui porte une icône préréglée et une ferme de mod.** Deux causes indépendantes : l'icône personnalisée prenait le pas sur le portrait illustré *quelle qu'elle soit*, or un préréglage (`preset:person`) est un pictogramme générique, strictement moins informatif que le visage qu'il remplaçait — seule une vraie image passe désormais devant (`SaveHeroPortrait`), les préréglages restant affichés dans les lignes de la liste comme toujours. Et une ferme de mod retombait sur `questionmark.square.fill`, le pictogramme du « je ne sais pas ce que c'est » : depuis qu'elle est reconnue, on sait exactement ce que c'est — une ferme dont l'illustration manque — et elle porte un glyphe de ferme.
- **La fiche de sauvegarde lisait les champs d'un monstre de quête au lieu de ceux du fermier.** Les balises du joueur étaient prises à la première occurrence du fichier ; or un monstre imbriqué **dans** `<player>` porte ses propres `<gender>`, `<hair>`, `<maxHealth>`… bien avant celles du fermier (mesuré : 294 `<gender>` dans une save du parc, celle du fermier en quatrième position). Conséquences visibles corrigées : une fermière s'affichait avec le visage masculin, et la santé maximale lue était celle du monstre (24 au lieu de 150). Tous les champs du fermier passent désormais par ses **enfants directs** (`SavePlayerFields`), en une seule passe sur le bloc `<player>`. C'est une correction d'exactitude, pas de vitesse : mesurée sur la save de 37 Mo du parc, cette passe coûte 37 ms pour les 12 champs, là où les regex qu'elle remplace trouvaient leur cible tôt dans le fichier et coûtaient quelques millisecondes chacune.
- **Éditer une sauvegarde écrivait dans le mauvais nœud.** Même cause côté écriture : `updateSave` visait la première occurrence du bloc `<player>`, donc celle du monstre. Sur une save réelle, modifier la santé maximale l'écrivait dans le monstre de quête et laissait celle du fermier inchangée. L'écriture cible désormais l'enfant direct, avec repli sur l'ancien comportement pour les champs qui vivent hors de `<player>` (`goldenWalnuts`).
- **Une ferme de mod s'affichait comme « Ferme standard ».** `<whichFarm>` n'est pas toujours un entier : une ferme de mod y écrit son identifiant (`FrontierFarm`), et `Int(...) ?? 0` le faisait passer pour la ferme 0 — vignette illustrée, libellé et infobulle compris. L'identifiant est désormais reconnu et affiché comme nom de la ferme, ce qui rend aussi atteignable le repli pictogramme prévu pour ces fermes. À noter : `<whichModFarm>`, la balise sur laquelle ce repli s'appuyait, n'existe dans aucune sauvegarde du parc.
- **L'icône personnalisée d'une sauvegarde revient sur son hero.** Elle restait visible dans la liste mais avait disparu du bandeau de la fiche, remplacée par l'illustration générique ; elle y reprend la priorité.
- **La chevelure du repli vectoriel de l'avatar était dessinée sur le menton** (formes ancrées en bas du cadre au lieu du haut).
- **Caches d'images sous verrou.** Les deux caches statiques des vignettes de ferme et des visages étaient mutés sans protection ; ils prennent un `NSLock` dédié, comme le cache de regex voisin, et mémorisent aussi les échecs de chargement (une resource absente relisait le disque à chaque rendu).
- **Audit Phase 1.2 §A — `currentLanguage` single owner + `detectDefaultGameDir` symlink resolution**: `StarHubTHApp.init()` no longer writes `AppleLanguages` (the `currentLanguage` `didSet` is now the sole owner — eliminates a triple write on first launch), the rejection branch is refactored to normalize-first to avoid the `didSet → didSet` cascade on an unsupported value, and the key now goes through `UDKey.appleLanguagesOverride` instead of the `"AppleLanguages"` literal (AGENTS §4.3). `detectDefaultGameDir()` resolves symlinks (`resolvingSymlinksInPath()`) before `fileExists`, per AGENTS §4.9 (`/tmp` → `/private/tmp`, `Application Support` can vary across OS versions).
- **Audit Phase 1.2 §J — `scanMods`/`manifestCache` hardening**: the `gameDir.isEmpty` path now resets `selectedMod = nil` alongside `mods = []` (prevents an orphan mod in the detail pane when the game directory is invalidated), the scan's `DispatchQueue.main.async` blocks carry `[weak self]` (AGENTS §4.6), a single `ModFolderRepairer` instance is reused across `repairIfNeeded` + `detectDuplicates`, and malformed JSON manifests are logged at `warning` level (`log("Invalid manifest for …")`) instead of silently producing a mod with empty metadata. The critical-section refactor of `manifestCache` (TOCTOU between two concurrent `stat()` calls) is deferred to §W to be tackled together with the installed-mod registry backup/restore.
- **Audit Phase 1.2 §L — `toggleMod`/`performToggle` isolated and hardened**: `toggleMod`, `processNextToggleIfNeeded`, and `performToggle` are now annotated `@MainActor`, closing the theoretical data race on the unprotected `pendingToggles` queue and `isToggling` flag (these fields are UI-driven and never touched from a background thread now) and silencing any future `@Published` mutations from background threads. The per-mod `moveItem` path now guards against an empty `folderName` (`guard !m.folderName.isEmpty`, otherwise `dstName` would collapse to `.` which `moveItem` rejects on macOS). The post-toggle `DispatchQueue.main.async` block uses `[weak self]` with a `guard let self else { completion?(); return }` fallback, so a deallocated VM still honours the completion instead of hanging the toggle queue (AGENTS §4.6).
- **Audit Phase 1.2 §W — installed mod registry hardening**: `installedModDate(for:)` now reads `installedModRegistryCache` directly under the existing lock (instead of going through `loadInstalledModRegistry()`, which lock+cache-checked twice on every per-mod lookup — 1 × `lock/unlock` per mod × ~1000 mods per scan). The V2-migration flag (`registryMigrationV2Done`) is now set **inside** the `mutateInstalledModRegistry` closure, **after** the wipe lands, so a crash mid-wipe leaves the flag at `false` and the wipe re-runs on the next scan (the previous code set the flag before the wipe, so a crash could leave the registry with stale archive-mtime entries forever). The `wasEmpty` rebuild-counter is now ferried out of the closure via a small `WasEmptyBox` reference type, which also fixes a pre-existing latent bug: the closure captured the outer `var wasEmpty = false` by value, so the post-closure log line at the end of `syncInstalledModRegistry` could never see `wasEmpty == true` — the registry rebuild message was effectively dead code. Three more `UserDefaults` keys (`modActivationTimestamps`, `installDateGrace`, `registryMigrationV2Done`) are now centralized in `UDKey.swift` per AGENTS §4.3.
- **Audit Phase 1.2 §O — `checkNexusUpdates` race + log levels fixed**: `isCheckingNexusUpdates` is now reset to `false` **after** `applySmapiResults` / `applyPathoschildFallback` finish in the `DispatchGroup.notify` callback. The previous code reset it before the heavy processing block, which let a fast user re-trigger a second `checkNexusUpdates` while the first was still applying results (on a large mod park `applySmapiResults` takes seconds). The "Pathoschild dump unavailable" log is now at `.warning` level instead of `.info` — it's a degradation of the safety net (mods without an smapi.io answer won't be picked up by the Nexus fallback), not an informational note. The `PathoschildCompatibilityList.fetch` closure in `checkNexusUpdates` was simplified by removing a dead `[weak self]` capture and `_ = self` line that did nothing (the closure never used `self`).

## [1.31.0] - 2026-09-01

### Added
- **`PathoschildNexusIndex` lit le dump Pathoschild pour récupérer le `nexusID`** : `PathoschildCompatibilityList.Entry` expose désormais le champ `nexus` du JSONC, et `PathoschildNexusIndex.loadFromCache()` construit un index `UniqueID → nexusID` offline. Combiné au téléchargement systématique du dump (cf. `Changed`), cela permet à `applySmapiResults` de résoudre les mods que smapi.io omet silencieusement (cas vécu : UltraSmooth / 50971), et de les pousser vers la reprise Nexus directe (`recheckBlockedViaNexus`).

### Changed
- **Hero de sauvegarde** : vignette de ferme (8 vanilla) + avatar fermier colorés depuis la save, le hero local ne dépend plus d'image externe.
- **Profiles page joins the unified list pattern** (H-T5, part 1): page title and bordered container are gone, "Add" moves to a fixed toolbar, and each profile row leads with labelled columns for its key figures (mods · issues · configs) instead of stacked sentences. Issues stay clickable through to the diagnostics sheet; a zero reads neutral, a non-zero adds a warning glyph. The French-coverage and orphan-configs badges are unchanged.
- **Saves page follows the same pattern** (H-T5, part 2): the toolbar gains an inline search field (replacing the system `.searchable`, same filtering as you type) with the view-mode toggle and reload; sort and tag filter become chips. The list leaves its `Form` for the standard fixed-header/scrolling-list/fixed-footer layout — the count and auto-fetch note now live in that footer in both list and grid modes. Each row shows the farmer, farm and in-game date, with money and total earned as aligned columns instead of a long sentence; the grid cards drop their hover zoom.
- **The save editor opens on a hero band and key figures** (H-T5, part 3): the farmer's avatar, name, farm and in-game date sit on a neutral band above a three-column strip (in-game date · money · total earned), with the backup-history button moved to a thin band underneath — the editing form below is unchanged.
- **The Parties sheets move to design tokens** (H-T5, part 4): the profile diagnostics sheet, the backup timeline and the duplicate/branch sheets drop their last hardcoded fonts and colors. "Not installed" in the dependency gaps now carries a warning glyph (never colour alone), the timeline's "Branch" action uses the app's installed tint, and the timeline's pencil/trash buttons meet the 18×18 hover target so their tooltips can actually show.

### Fixed
- **`AppDelegate` isolé sur le main thread** : annotation `@MainActor` ajoutée sur la classe pour verrouiller au niveau du type la garantie que `pendingURLs`/`isReady` ne sont jamais mutés hors main thread (AppKit le faisait déjà, mais la convention était implicite).
- **Deux warnings triviaux retirés** : `await` superflu sur `log(...)` (VM:1356, `log` est synchrone) et `??` sur non-optional autour de `L(L10n.VM.defaultFarmerName)` (VM:2499, `L(_:)` retourne `String` non-optionnel). Aucun changement de comportement ; les 6 warnings Sendable restants sont hors périmètre.
- **Clé `AppleLanguages` centralisée dans `UDKey.swift`** : la string littérale écrite au lancement (`forKey: "AppleLanguages"`) passe par la constante `UDKey.appleLanguagesOverride`, conformément à §4.3 d'AGENTS.md.
- **Les vignettes de ferme du hero de sauvegarde deviennent des illustrations** : les glyphes vectoriels dessinés à la main étaient illisibles à 80×56 — les 8 fermes vanilla s'affichent désormais en vignettes illustrées embarquées (ordre du wiki), et une ferme de mod retombe sur un pictogramme proportionnel. L'avatar du fermier est corrigé du même coup.
- **Le bandeau du hero de sauvegarde porte l'illustration du splash**, avec un voile dégradé en pied pour que le nom du fermier reste lisible par-dessus.
- **L'avatar du fermier devient une vignette circulaire sur le visage du personnage** — fermier ou fermière selon le sexe lu dans la sauvegarde (`<gender>`), avec liseré et ombre pour se détacher du bandeau ; la vignette de ferme, quasi carrée, garde son toit entier.
- **L'avatar du fermier du hero de sauvegarde lit les vraies balises du jeu** : la coiffure vit dans `<hair>` et la couleur dans `<hairstyleColor>` (une couleur R/G/B libre, pas un index) — les balises `<hairStyle>`/`<hairColor>` supposées n'existent pas, et l'avatar restait chauve, couleur 0, sur toutes les saves. *(Correction du 2026-09-02 : ces valeurs ne sont rendues que par le repli vectoriel — l'illustration du visage, elle, est fixe par sexe.)*
- **La fenêtre de succès défile quand un pack pose beaucoup de mods** : la liste des mods installés est bornée et défilante — le titre et le bouton restent visibles même à 15 noms ou plus, au lieu d'être coupés hors cadre.
- **Les packs de plus de 10 mods s'installent** : la limite refusait des packs Nexus réels (« Hidden Pelican Village », 13 composants ; « MultiverseArchive », 15) avec « trop de mods » — elle monte à 50, seules les archives absurdes restent refusées.
- **Les MAJ Nexus que smapi.io omet silencieusement sont détectées** : smapi.io renvoie parfois une entrée avec `metadata: nil, errors: []` pour un `UniqueID` qu'elle ne connaît pas (cas vécu : UltraSmooth / 50971, et ~515 mods du parc mesuré). `applySmapiResults` ne peuplait `blocked` que sur `errors.first`, donc ces mods restaient sans reprise. Le dump Pathoschild est désormais téléchargé systématiquement (pas seulement sur échec smapi.io), son champ `nexus` est décodé, et tout mod envoyé mais sans réponse smapi.io est poussé vers `recheckBlockedViaNexus` avec un `metadataNexusId` issu soit de l'override manuel (champ « Nexus Mod ID » de la fiche détail), soit du dump Pathoschild. Sur le parc : **26 → 515 mods repris, 2 → 15 MAJ détectées** par vérification.
- **Le filet Pathoschild arme le pire cas et le cas vécu** : avant, `PathoschildCompatibilityList.fetch` n'était appelé que sur échec smapi.io, donc le cache cache `pathoschild_mods.jsonc` n'était jamais posé sur un parc où smapi.io répond (même partiellement). Le déclenchement est désormais systématique, synchronisé avec smapi.io par un `DispatchGroup`, et alimente `PathoschildNexusIndex` pour `applySmapiResults`. Le coût reste marginal : 1 requête HTTPS de ~4 Mo au premier lancement, cachée 6 h (comportement existant, juste déplacé hors de la branche échec).
- **Déposer plusieurs archives d'un coup les traite toutes** : seul le premier zip du dépôt était analysé, les autres ignorés en silence. Chaque archive a maintenant sa fiche l'une après l'autre (bouton « Terminé » enchaîne), un fichier étranger glissé dans le lot est écarté, et une archive refusée ou annulée n'arrête pas les suivantes.
- **Les noms des types de ferme sont désormais localisés en français et anglais** (auparavant codés en dur en thaï dans `SaveManager.farmTypeName`).
- **Phantom updates on mods whose author doesn't bump the manifest** (X9): the Nexus label an author sets on a file and the version inside the archive's manifest are two different vocabularies — when they diverge (real case: labels moved 1→5 in two days, manifest stuck at 1.2.0), the update row came back after every install. When the app itself downloaded the file, it now remembers which Nexus file it laid down, and the check judges by that: an update exists only when the page publishes a **newer** main file than the one held — labels no longer decide. This also catches re-uploads at the same version number (a new file id means a re-upload). Manual installs keep the label-based rule; `nxm://` links and pack installs are left out for now.

## [1.30.0] - 2026-08-31

### Added
- **Update checks no longer hit smapi.io on every launch**: a check that returned a response keeps the next automatic one away for 12 hours — the list still opens on the cached results. The manual "Check" button on the Updates page always refreshes.
- **Pathoschild list as a fallback when smapi.io is silent** (A2-T3): if the live check fails or times out, the app fetches `Pathoschild/SmapiCompatibilityList`'s `data/mods.jsonc` dump, joins it on `UniqueID`, and fills in the verdicts that smapi.io didn't return. The compatibility health card now carries a small badge naming the source — smapi.io (live), the Pathoschild dump, or the cached dump with its date — so a fallback isn't mistaken for fresh data. The dump is cached on disk for 6 hours and re-used when the network is down.
- **A mod with a hand-installed French translation can now be declared** (A3-T6): when the registry has no entry for a mod but its folder ships an `i18n/fr.json` (or `i18n/fr/*.json`), the translation tab on the mod page now shows a "Translation present, origin unknown" banner with two actions — search Nexus, or declare manually (Nexus mod id + name + optional version). The declaration is stored alongside installed translations, back-compatibly, and undeclaring only touches the registry — files on disk are not modified, since the app never installed them.

### Fixed

- **The update check compared against an outdated main file** (X8): with several MAIN files listed on Nexus, the check took the first one returned instead of the most recent (`uploaded_timestamp`) — a mod could read up to date while a newer MAIN exists, or report an older version than the real one. The comparison now takes the newest MAIN.
- **"Download mod" no longer resolves to an outdated main file**: when no specific file is designated (direct install, translations), the downloader took the first MAIN returned; it now takes the most recent one — the same rule as the update check.

## [1.29.0] - 2026-08-30

### Added
- **Conflict rows now name the patches fighting over the asset** when Content Patcher logged them right after the error ("Affected patches: Pack > Patch"). The row stays silent if the log dropped those `TRACE` entries.
- **A grid mode joins the mod list**: cards in the Discover style, one per pack or mod, opening the detail page on click. Each card carries the cached Nexus screenshot, its category, and tells at a glance whether the mod is active or paused. A flat pack doesn't borrow its first component's picture. The dense-list / grid choice persists across sessions.
- **The mod detail page is rebuilt on the Discover pattern**: full-width image banner, a strip of key figures — version, freshness, size, languages — and the action that matters, enable or pause, as a single switch, alongside favorites, config, conflict reporting, delete, and a button that reveals the mod's folder in the Finder. The mod's state (compatibility, translation, errors, keybinds, conflicts) gets its own "State" tab; toolbar chevrons walk the current scope without returning to the list, and a pack component's page leads back to its pack's.

### Changed
- **The mod list speaks the app's language.** Search lives in the toolbar, journal-style, and row colors and sizes move to design-system tokens — a paused mod reads as a glyph, never color alone.
- **The "config" and "favorites" filter pills shrink to their glyph**, the label moving to the tooltip: the toolbar's second row breathes, the favorites count stays visible.
- **Filter menus report what the view contains**: categories, inferred types, and translation states are now counted on the displayed scope ("All", "Enabled", "Paused", "Issues") rather than the whole library.
- **A card with no Nexus screenshot shows the app illustration** instead of a gray rectangle — 148 of the 887 folders have no picture to serve.
- **The toolbar's active profile leads to the profiles page.**
- **Anomaly, note, and per-profile config align in the metadata band**, in fixed columns from one row to the next instead of trailing the name's length. Anomaly and note also open on click, as a popover; the grid card carries the same attributes as the row.

### Fixed
- **A mod's size vanished on activation**: the toggle renames its folder (the pause dot), and the size measurement stayed indexed under the old name until the next full scan — the detail page and the rows showed "—". The measurement now follows the rename, and the "paused size" subtotal with it.
- **Three icons were missing from filter menus**: two symbols don't exist on macOS 26 ("Name (Z-A)", "To translate"), and the active sort replaced its own icon with a redundant checkmark — the menu button already names the current sort.
- **The anomaly badge's tooltip never opened**: its hover target was too small for the stationary hover macOS requires.
- **A pack component started left of its pack's name**: its indent was a flat constant instead of being computed from the chevron and star preceding it.

## [1.28.0] - 2026-08-30

### Added
- **Les incompatibilités entre mods se voient.** « Alertes système » reprend les paires que Content Patcher journalise quand deux packs veulent le même asset exclusif (« Neither will be applied ») — sans rien déduire. Depuis la fiche, on signale une incompatibilité à la main ou on écarte un faux positif ; activer un mod dont le pair signalé ou observé est actif demande confirmation, une paire dormante n'interrompt rien ; la pastille « Alertes système » compte les paires aux deux côtés actifs.
- **La fiche d'un mod montre le paragraphe de compatibilité de son auteur** quand la description Nexus en écrit un (15 % des mods) : la phrase remonte telle quelle, c'est l'utilisateur qui juge.

## [1.27.0] - 2026-08-29

### Added
- **Les raccourcis clavier qui se marchent dessus se voient.** Un rapport lit les touches que déclarent les mods installés — 141 liaisons sur les 92 mods actifs — et signale les **18 collisions** entre mods et les **11 conflits avec les touches du jeu**. La pastille « Alertes système » les compte.
- **La fiche d'un mod montre ses propres conflits de touches**, et un bouton mène droit à la configuration à corriger — depuis la fiche comme depuis le rapport.
- **Une traduction déposée à la main retrouve sa page Nexus toute seule.** Le nom du fichier téléchargé porte l'identifiant et la version (`… FR 46333 2.9.0 2026-08-10T13-50Z …`, ou `…-34339-1-0-1748539543`) : l'app les lit au dépôt au lieu d'afficher « aucune vérification de mise à jour » et d'attendre un rattachement à la main. Un nom qui ne dit rien ne fait rien inventer.

### Changed
- **La navigation est refaite** : un seul style d'item pour les 13 destinations, rangées en quatre familles (Bibliothèque, Parties, Santé & secours, Application), et les badges passent en capsule sur l'item — la zone de statut séparée disparaît. Aucune destination retirée ni enterrée.
- **L'accueil devient un tableau de bord** : quatre compteurs cliquables — mises à jour, alertes SMAPI, quarantaine, parc — toujours affichés, zéros compris, et une carte de lancement qui dit d'un coup d'œil si on peut jouer, avec l'action qui lève l'empêchement quand il y en a un.
- **Les Réglages absorbent l'identité de l'installation** : dossier du jeu, gestion SMAPI, extensions cœur et crédits quittent l'accueil. « Installer SMAPI » y reste tant que SMAPI manque.

### Fixed
- **Une traduction emballée deux fois trouve enfin son mod.** Certaines archives répètent leur nom avant le dossier visé (`… FR - v2.9.0/… FR - v2.9.0/UIInfoSuite2Alt/i18n/fr.json`) : l'app s'arrêtait au premier emballage et proposait quatre destinations dont aucune n'était la bonne. Elle descend maintenant jusqu'au mod installé et dépose le fichier sans rien demander.

## [1.26.0] - 2026-08-28

### Added
- **Les réglages d'un mod sont enfin décrits, quand le mod les décrit.** Les content packs publient un schéma à côté de leur contenu : l'éditeur en tire les **sections** à la place de la liste à plat, une **explication sous chaque nom** — 1926 réglages du parc en gagnent une —, et une **liste déroulante** là où il fallait deviner la valeur à taper (954 réglages). Les libellés sont pris dans les traductions du pack lui-même, en français quand il en a : 1889 réglages y gagnent un nom lisible à la place de leur clé. Un réglage qui s'écarte de ce que l'auteur avait prévu porte une pastille « modifié » et un bouton pour y revenir. Les mods qui ne décrivent rien s'affichent comme avant.
- **Un auteur peut annoncer ce que sa mise à jour casse : l'app le montre avant d'écraser.** `UpdateCautionMessage` (extension Stardrop, ignorée par SMAPI) s'affiche en avertissement dans la préview d'installation, pour chaque mod déjà installé concerné. Le message paraît tel que l'auteur l'a écrit — en anglais le plus souvent ; seul l'habillage de la bannière est traduit. Aucun mod du parc ne l'expose encore.
- **La version de l'app s'affiche dans les Réglages**, en pied de page sous la dernière section — elle n'était lisible que sur l'accueil.

### Changed
- **Les réglages d'un mod s'affichent dans l'ordre où son auteur les a écrits**, plus par ordre alphabétique — qui séparait des options faites pour aller ensemble (`BigSilo_BuildCost` atterrissait à côté de `BigSilo`, loin du groupe où l'auteur l'avait rangé). 363 des 462 configurations du parc étaient réordonnées.
- **Modifier un réglage ne réécrit plus tout le fichier.** Seule la valeur touchée change ; le reste garde la forme exacte que l'auteur lui a donnée, `1.50` compris. Un fichier de configuration écrit avec des commentaires ou une virgule traînante s'ouvre désormais au lieu d'afficher « Format JSON invalide » : c'est ce que le jeu accepte lui-même.
- **L'enregistrement met la configuration précédente dans les sauvegardes de configurations** — datée et visible depuis leur écran — au lieu de déposer un `config.json.bak` dans le dossier du mod ; une par mod et par jour — c'est la première du jour qui fait filet, celle d'avant la première modification. Y compris quand le mod est en pause. « Restaurer la configuration » charge la version sauvegardée dans l'éditeur : c'est « Enregistrer » qui l'applique, après avoir mis l'actuelle à l'abri.
- **Quota Nexus épuisé : l'attendre, pas le tester tous les quarts d'heure.** L'instant de remise à zéro est connu depuis le relevé des en-têtes `x-rl-*` (2 000 requêtes/heure, 20 000/jour) : la porte s'y aligne désormais. Sans cet instant, le plafond de 15 minutes reste.

### Fixed
- **L'éditeur de configuration s'ouvre sur les réglages**, plus sur le JSON brut, et ses contrôles s'alignent en colonne au lieu de tomber à trois abscisses différentes.
- **La description d'un réglage n'est plus tronquée à deux lignes** — elle s'affiche entière ; c'est souvent la seule chose qui explique à quoi sert le réglage. 158 des 1926 descriptions du parc dépassaient deux lignes, jusqu'à cinq pour la plus longue.
- **Un réglage à virgule s'affichait arrondi** — `0,5` apparaissait `0`, `1,25` apparaissait `1` — et le champ refusait ensuite la valeur qu'il venait d'afficher. 758 des 11 891 réglages du parc sont concernés.

## [1.25.0] - 2026-08-28

### Added
- **Onglet « Découvrir » : trouver un mod sans en avoir un pour point de départ.** Trois sections servies par Nexus — tendances, mises à jour récentes, sélection française — plus une recherche par nom. Chaque carte dit si le mod est déjà dans le parc, et « masquer les installés » affiche toujours combien il a masqué. Les listes sont mises en cache 24 h ; seul le bouton de rafraîchissement redemande au réseau.
- **Fiche éclair depuis une carte** — description rendue comme sur la page du mod, catégorie, auteur, endossements, et « Ouvrir sur Nexus » pour ramener le fichier dans l'app par `nxm://`. Sans clé d'API, l'onglet le dit au lieu de rester vide ; un quota atteint et une panne réseau ont chacun leur message.
- **Installer un mod directement depuis sa fiche.** Le bouton emprunte le pipeline des mises à jour — le fichier principal est résolu, téléchargé, et la feuille d'installation habituelle prend le relais. Il demande un compte Nexus Premium, faute de quoi l'API de lien refuse la demande ; sur un compte gratuit le bouton est grisé et le dit, « Ouvrir sur Nexus » restant la voie de toujours. Un mod déjà installé n'est pas réinstallé depuis la vitrine : sa mise à jour se fait depuis la liste des mods.
- **La catégorie sur chaque carte, et un filtre par catégorie.** La pastille est celle de la liste des mods installés — même couleur, même nom traduit. Le filtre part au serveur Nexus : choisir « Portraits » redemande des portraits plutôt que de trier les vingt mods déjà reçus, qui se répartissent sur une quinzaine de catégories. Il vaut pour les sections **et** pour les résultats de recherche, de sorte que le total annoncé parle du même ensemble que les cartes ; chaque catégorie garde son propre cache de 24 h.
- **Les cartes portent la vignette du mod** quand Nexus en sert une, sa place étant réservée dans tous les cas — beaucoup de traductions n'ont pas d'image, et une carte plus courte décalerait toute la rangée. Les images sont gardées en mémoire d'un défilement à l'autre. Les sections écartent les traductions d'autres langues que le français ; la recherche par nom, elle, rend ce qu'on lui a demandé.
- **Voir plus de mods dans une section, et dans les résultats de recherche.** Chaque bande s'arrêtait à vingt mods sur des sections qui en comptent des milliers ; un bouton en demande la suite et l'ajoute à ce qui est déjà là, sans doublon. Il disparaît quand tout est chargé.

### Changed
- **L'onglet Découvrir redessiné.** Une seule rangée de commandes au lieu de trois — les trois boutons de rafraîchissement des sections déclenchaient tous le même rechargement. La carte occupe désormais sa case de grille, sa vignette passe en 16/9 pleine largeur (elle laissait deux marges grises), et « Installé » se pose sur l'image en pastille verte pleine, lisible sur une vignette claire comme sombre, plutôt qu'en bas de pile. La fiche s'ouvre sur un bandeau illustré et une bande de quatre chiffres — endossements, version, âge de la mise à jour, catégorie.
- **Les sections s'affichent en grille, quatre mods d'abord.** Elles défilaient horizontalement : sur la largeur d'un écran, 4 ou 5 mods visibles sur 20, sans ascenseur pour dire qu'il y en avait d'autres. « Voir plus » déplie maintenant de quatre en quatre — d'abord ce qui est déjà en cache, puis la tranche suivante demandée au serveur — et une barre de liens saute directement à une section, y compris quand celle du dessus a été dépliée.
- **Un état vide propose ce qui le lève.** Sans clé d'API il mène aux réglages, filtré à outrance il retire les filtres, en panne il réessaie — au lieu d'un simple constat. Le message de panne devient un bandeau visible plutôt qu'une ligne de légende.
- **« Ouvrir sur Nexus » ouvre l'onglet des fichiers** et referme la fiche derrière lui, au lieu de laisser la modale ouverte sur la description qu'on vient de quitter. Sur un compte gratuit, c'est aussi lui qui devient le bouton principal : l'installation directe y étant refusée par l'API, autant mettre en avant le chemin qui marche.
- **« 20 affichés sur 33 204 » ne comparait rien à rien.** Le second nombre était le catalogue entier du jeu, sans rapport avec la bande. Les sections annoncent maintenant ce qui est montré par rapport à ce qui a été **reçu** — ce que la mention voulait dire depuis le début : signaler qu'un filtre a écarté des mods. Les résultats de recherche gardent leur total serveur, qui lui dit bien que la liste est plafonnée.

### Fixed
- **La pastille « installé » s'allume dès la fin de l'installation.** Elle attendait le scan complet du parc — passe de réparation comprise, deux parcours de plus de cent mille fichiers — soit plusieurs secondes pendant lesquelles le mod qu'on venait d'installer s'affichait comme absent. L'app retient maintenant la page d'où vient l'installation immédiatement, y compris pour un pack livrant plusieurs dossiers et pour un mod dont le manifeste porte déjà son identifiant.
- **Le filtre par catégorie accepte un second choix.** Chaque sélection reconstruit la vitrine et la recherche affichée, donc la hiérarchie sous le menu ouvert : le choix suivant ne partait plus.
- **Une panne réseau ne laisse plus son bandeau d'erreur en haut de l'onglet.** Le message n'était effacé nulle part : une fois affiché, il survivait à tous les chargements réussis qui suivaient. Il disparaît maintenant dès la tentative suivante, et une section qui ne parvient pas à se rafraîchir le dit au lieu de laisser croire que ses mods sont à jour.
- **Une section vide ne dit plus « Rien n'est encore chargé ».** Elle avait pourtant répondu — ce sont les filtres qui ne laissaient rien passer, et le message envoyait rafraîchir pour rien.
- **Le cache des images est borné** (400 vignettes, 128 Mo, au poids réel des pixels). Il ne rendait la mémoire que sous la pression du système, alors que dérouler la vitrine peut demander des centaines de vignettes.

## [1.24.0] - 2026-08-27

### Added
- **Les mods que smapi.io refuse de juger sont repris auprès de Nexus.** Un mod dont smapi.io ne sait rien dire — page introuvable, aucune version indexable, clé de mise à jour malformée — restait sans verdict d'aucune source, et la fenêtre passait dessus en silence. Après chaque vérification, l'app interroge Nexus pour ceux-là, sans clé d'API elle s'abstient, et un mod tranché quitte la liste des invérifiables. Sur le parc de référence : 52 mods repris sur 42 pages, et **10 mises à jour trouvées là où smapi.io seule n'en voyait que 3**. Deux comparaisons sont refusées volontairement — une page revendiquée par des mods de versions différentes, et un correctif `-unofficial` face à l'officiel de même numéro.
- **Le journal nomme chaque mod que la reprise Nexus tranche**, avec la version installée et celle de la page dans les deux cas. Une mise à jour trouvée finit dans la fenêtre, mais un mod *confirmé à jour* n'apparaissait nulle part — alors que c'est précisément le verdict qu'on vient de gagner sur un mod qui n'en avait d'aucune source. Une page qui ne publie aucune version le dit aussi, en comptant les mods qu'elle laisse sans réponse.

### Fixed
- **Un lot de 150 mods ne disparaît plus parce qu'un seul déplaît à smapi.io.** Le service répond « tout va bien » et une liste vide quand une entrée du lot lui est indigeste — 150 mods repartaient alors sans verdict, sans erreur, et sans que rien ne le dise. Un lot vide est désormais re-découpé jusqu'à isoler le mod fautif, qui rejoint la liste des invérifiables au lieu d'emporter ses voisins. Sur le parc de référence, un mod en pause dont l'auteur a livré un numéro de version non substitué privait 149 autres mods de toute vérification.
- **Un profil supprimé n'abandonne plus ses configs mémorisés sur le disque.** Le magasin d'un profil vivait dans `Application Support`, indexé sur son identifiant ; le supprimer laissait le fichier derrière, que plus rien ne lisait, ne nommait ni n'effaçait. Il part maintenant avec le profil, et la confirmation prévient de ce qui va disparaître quand il y a quelque chose à perdre. Les magasins laissés par des suppressions antérieures sont retirés au démarrage — jamais quand la liste des profils est vide, une préférence illisible ne devant pas passer pour « plus aucun profil ».

## [1.23.0] - 2026-08-27

### Added
- **Configurations par profil** — un mod peut désormais garder un `config.json` différent selon le profil. Le réglage se prend sur sa fiche ; le fichier est mémorisé quand on quitte un profil et restauré quand on y revient. Rien n'est écrit tant que le profil d'arrivée n'a rien mémorisé. Basculer de profil pendant que le jeu est ouvert ne mémorise rien : SMAPI garde les configs en mémoire et les réécrit à sa fermeture, donc l'app refuse volontairement d'y toucher et le journal le dit — les réglages changés depuis le dernier changement de profil « propre » ne sont pas mémorisés, et le prochain changement les écrase.
- **Comparer ce que deux profils retiennent d'un mod** — « Comparer avec… » sur la fiche d'un mod dont les configs sont gérés par profil montre, clé à clé et dans l'ordre du fichier, ce que le profil actif et un autre profil ont mémorisé de son `config.json` : les clés propres à l'un, celles propres à l'autre, et les valeurs qui divergent côte à côte. Lecture seule. Un config mémorisé qui ne se parse pas le dit, plutôt que d'afficher une comparaison inventée.
- **La fiche d'un profil compte ses configs mémorisés** — et nomme ceux dont le mod n'est plus installé. Ces configs-là sont **gardés, pas purgés** : réinstaller le mod lui rend ses réglages.

### Changed
- **La restauration d'un config fusionne au lieu d'écraser.** Un mod mis à jour depuis la dernière mémorisation a souvent gagné des clés dans son `config.json` ; les réécrire tels que le profil les avait retenus les effaçait. Le fichier sur disque sert désormais de base, les réglages du profil se réappliquent par-dessus, et le journal distingue ce qui a été fusionné de ce qui a été restauré tel quel — un texte illisible retombe sur l'ancien comportement plutôt que d'être abandonné.
- **Supprimer un profil actif laisse choisir lequel activer ensuite.** L'app ne proposait que le profil par défaut ; elle propose maintenant chacun des profils restants, dans l'ordre de la liste. Supprimer sans en activer aucun reste possible et le bouton le dit — rien ne déplace de dossiers sans un clic explicite.
- **Les mises à jour se lisent par ordre alphabétique.** La liste annonçait « les plus récemment mises en ligne d'abord » — une promesse devenue fausse au passage à smapi.io, qui ne renvoie aucune date de mise en ligne : le tri portait donc sur des valeurs toutes égales, et pouvait rendre un ordre différent d'une vérification à l'autre sans que rien n'ait bougé. Les mods sont désormais triés par nom, casse et accents ignorés, comme la liste des alertes SMAPI juste au-dessus ; les mods invérifiables aussi. La mention d'ordre disparaît de l'en-tête : une liste alphabétique se voit.

### Fixed
- **La fenêtre des mises à jour taisait les mods invérifiables** — quand smapi.io répond une erreur pour un mod (page retirée, aucune version exploitable…), la fenêtre concluait « Tous les mods sont à jour » alors qu'il n'avait de verdict d'aucune source. Ces mods sont désormais comptés et nommés avec leur motif, et le satisfecit ne parle plus que des mods vérifiables.

## [1.22.0] - 2026-08-27

### Added
- **Un téléchargement Nexus ne se fait plus en aveugle.** Un mod de 500 Mo n'avait pour tout témoin qu'un rond qui tourne : ni progression, ni temps restant, ni moyen d'arrêter. Le pied de la barre latérale montre désormais le mod téléchargé, le volume reçu, le débit, le temps restant, et porte un bouton d'annulation — visible quel que soit l'onglet, puisqu'un lien `nxm://` peut arriver du navigateur à tout moment. Le pourcentage et l'annulation sont repris sur la ligne des mises à jour. Quand le serveur n'annonce pas la taille du fichier — fréquent sur un CDN —, ni barre ni pourcentage ni estimation : seulement le volume et le débit, qui eux sont vrais. Annuler son propre téléchargement n'ouvre plus d'alerte d'erreur.
- **Un profil dit ce qu'il affichera en français.** La ligne du profil porte désormais une pastille « FR 94 % · 23 à traduire », et l'écran de diagnostic nomme les mods concernés, du plus gros reste au plus petit, avec un bouton qui ouvre directement l'onglet Traduction du mod. Mesuré sur trois profils réels : 94 %, 86 % et 93 % des clés, pour 23, 50 et 21 mods à traduire. Une clé sans traduction s'affiche en anglais — rien n'est cassé, et l'écran le dit. Les mods qui n'ont rien à traduire et ceux qui ne sont plus installés ne comptent pas. La mesure est **gardée d'une session à l'autre**, validée par l'empreinte des fichiers de traduction de chaque mod : 14,8 s la première fois, 2,7 s ensuite — et un mod retraduit est remesuré tout seul.

### Changed
- **Le journal nomme le mod, au lieu de son seul numéro.** « Téléchargement du mod 41318 » demandait d'ouvrir Nexus pour savoir de quoi il s'agissait ; c'est désormais « Téléchargement de « Kalash's More Fruit Trees » (mod 41318) », et la bannière de la barre latérale porte le nom plutôt que le numéro. Le nom vient des mods installés ou de la liste des mises à jour ; quand aucun des deux ne le connaît — un lien `nxm://` pour un mod jamais vu —, le numéro seul reste, plutôt qu'un nom inventé.
- **La fenêtre des mises à jour dit ce qu'elle montre.** Sans mise à jour Nexus, elle répondait « Aucune alerte système » — le libellé d'une autre page. Les mods signalés par SMAPI n'avaient aucun en-tête, leur version s'affichait nue sous le nom du mod alors que c'est la version *disponible*, une phrase leur prêtait « de nouvelles fonctionnalités et des corrections de bugs » que l'app ne connaît pas, et leur bouton disait « Télécharger » alors qu'il ouvre une fiche où rien ne se télécharge. Ces mods sont maintenant triés par nom — SMAPI les listait dans son ordre de chargement, qui change d'un lancement à l'autre — et la liste Nexus annonce le sien : les plus récemment mises en ligne d'abord.

### Fixed
- **Une archive aux noms de fichiers à l'ancienne s'installe désormais.** `/usr/bin/unzip` refuse de créer un nom qui n'est pas de l'UTF-8 valide — les vieux zips encodent les leurs à la mode DOS — et il s'arrête en cours de route, après avoir extrait le reste. L'installation échouait alors sans rien dire. Elle se reprend maintenant avec `7zz` ou `unar`, qui transcrivent ces noms correctement. Mesuré sur « Kalash's More Fruit Trees » : `unzip` s'arrêtait à 315 fichiers sur 320, le repli les installe tous.
- **Le journal reçoit les erreurs d'installation.** Une extraction qui échouait ne laissait aucune trace consultable : il fallait relancer l'app depuis un terminal pour lire ce que l'outil avait dit. Le journal porte désormais le statut de l'extracteur et son message, ainsi qu'une note quand l'extraction a dû s'y reprendre avec un autre outil.
- **L'installation d'un gros mod ne se fige plus sur « Analyse de l'archive… ».** Le contrôle anti-zip-slip attendait la fin de `unzip` avant de lire ce que celui-ci écrivait. Passé la capacité d'un tube — 64 Ko, soit environ 1 500 fichiers —, les deux se bloquaient l'un l'autre : l'app restait sur l'analyse, et le processus `unzip` survivait, immobile. Un mod à 3 000 entrées produit 411 Ko de listing. Au passage, une archive qui contient deux fois le même chemin ne peut plus poser de question à laquelle personne ne répondra.

## [1.21.0] - 2026-08-27

### Added
- **Un mod peut porter une note, et la liste s'en souvient.** « Désactivé en multi car désync », « à mettre à jour » : des choses qu'on sait un jour et qu'on cherche six mois plus tard. La note s'écrit sur la fiche, se sauvegarde d'un clic ailleurs (pas de bouton), et vit **dans le profil actif** — elle documente l'usage de ce mod dans ce profil et change avec lui. L'icône près du nom la signale dans la liste, note entière en infobulle. Les profils existants se relisent sans rien perdre ; une note vidée est retirée plutôt que rangée vide.
- **La fiche d'un mod dit son âge quand il dort.** « Dernière mise à jour : 12/03/2021 » demandait une soustraction mentale ; la ligne dit désormais « 12/03/2021 · il y a 5 ans » — mais seulement à partir d'un an révolu, une mise à jour récente se lisant fraîche d'elle-même. La date de création Nexus reste non demandée : l'ancienneté de la dernière mise à jour est le signal qui décide.
- **La commande d'installation de l'outil RAR se copie d'un clic.** L'erreur d'extraction `.rar` la donne en toutes lettres (`brew install unar`) — il fallait la recopier à la main dans Terminal. L'alerte offre désormais « Copier la commande », sur cette erreur seule : aucune autre erreur d'installation n'en porte.
- **Un mod sans page Nexus en retrouve une, quand smapi.io la connaît.** Chaque vérification de mises à jour reçoit déjà l'identifiant Nexus de tout mod que la base de compatibilité connaît — l'app le jetait, sauf sur les lignes de mise à jour. Sans identifiant, un mod n'a ni suivi de version, ni bouton vers sa page, ni recherche de traduction, et rien ne le disait. Sur un parc réel, **148 mods n'ont aucune clé Nexus dans leur manifeste et 30 sont pourtant identifiés** : dix avaient été renseignés à la main, et **les dix concordent exactement** avec ce que smapi.io répond. Les 20 autres sont désormais reliés tout seuls. Ce qui est saisi à la main n'est jamais écrasé, et le manifeste garde le dernier mot.
- **Un mod que smapi.io ne connaît pas non plus peut être identifié à partir de son seul nom.** Sa fiche propose une recherche Nexus par nom, pour les 83 mods du parc réel restés sans identifiant. Les traductions sont écartées d'office — **61 % des candidats rendus**, mesuré, et le titre d'une traduction commence toujours par celui du mod, donc rien d'autre ne les sépare. La concordance d'auteur n'ordonne que la liste : le même mod publie parfois sous un autre pseudo, et filtrer dessus perdrait des candidats justes. Rien n'est relié sans un clic explicite — un mod lié à la mauvaise fiche suit les mauvaises mises à jour — et « aucun résultat », la réponse la plus fréquente (deux mods sur trois), est écrite en toutes lettres plutôt que laissée à deviner.
- **La quarantaine et les alertes système se rafraîchissent sur demande.** Aucun chemin ne rafraîchissait ces deux pages sans repasser par l'accueil : le rapport de quarantaine datait du dernier scan, les alertes du dernier lancement du jeu. « Relancer l'analyse » rejoue le rafraîchissement complet, réparation incluse, et se met en pause le temps du scan ; « Revérifier le journal » relit le seul journal SMAPI, sans rescaner tout le parc — et reste proposé quand tout est vert, car un journal silencieux avant une installation ne dit rien d'après. Ces deux pages sont désormais **toujours dans la barre latérale** : elles n'y apparaissaient qu'une fois quelque chose allé mal, ce qui rendait la vérification inaccessible tant que tout allait bien — seule la pastille de compteur disparaît à zéro. La page des alertes proclamait aussi « Tous les mods sont à jour » en l'absence d'erreur — un propos de mises à jour Nexus, sans rapport avec elle ; elle dit désormais ce qu'elle est.

### Changed
- **La liste des mods suit l'alphabet, packs mêlés.** Les packs occupaient le haut de la liste et les mods simples venaient ensuite : chercher un nom y dépendait de la nature du mod, pas de l'alphabet. Packs et mods simples partagent désormais un seul ordre alphabétique ; les composants d'un pack restent dans sa ligne dépliable.

## [1.20.0] - 2026-08-26

### Added
- **An archive that is not a mod is no longer just refused.** Dropping a translation or a bag pack used to end on "manifest.json missing" and nothing else. The app now works out which installed mod the files are for and offers to add them — and when the archive's folder name matches no installed mod, it asks you which one rather than guessing. On a set of nine real archives, seven were placed on their own and two were handed back as a choice with the right mod first. Whatever is overwritten is backed up first, and a translation dropped this way gets the same **Remove** button on the mod's page as one found on Nexus.
- **A mod's page can find, install, follow and remove its French translation.** A translation is not a mod — it is files dropped *inside* the mod it translates — so it lives where it makes sense: on that mod's page. Nexus is searched by the mod's own name, narrowed by the `French` tag its authors use (77 of 80 translations carry it; the title is only a fallback). Installing puts every file it overwrites safely aside first, so removing gives back the `fr.json` the mod's own author shipped instead of leaving it with no French at all. A newer version is spotted by Nexus dates, not version numbers — translators routinely reuse the translated mod's number.
- **A mod known to be broken now says so — and says it before you turn it on.** Every update check already received smapi.io's verdict on each mod, and threw it away. It is now kept: the mod's page carries a banner naming the status, the Stardew Valley version that broke it, and buttons to whatever the entry points at — a replacement mod, an unofficial fix, a GitHub release. The same warning stands in the way of *turning a mod on*, of installing one, and of enabling it as a dependency; pausing one is never questioned, since that is the thing to do. **The SMAPI health card states both numbers**, because one without the other misleads: on a real library, 7 mods are reported broken — and **552 of 840 are unknown to smapi.io**, which is not the same as being sound.
- **The "Issues" tab now holds every kind of trouble, not just missing dependencies.** It listed one thing: an enabled mod whose required dependency was missing or paused. The badge beside a mod's name already covered more than that — logged errors, a manifest with no identifier — so a mod could carry a badge and still be absent from the tab meant to gather them. They now follow the same rule, and two more signals join it: **a mod smapi.io reports as broken**, and **a mod installed more than once**. Being paused no longer hides a mod from the tab; it grades it. A broken mod that is on, or two copies of the same mod both on, is an error — the rest is a warning, still listed, because a folder to delete is a folder to delete.
- **Mods installed twice are now named as such.** Same `UniqueID`, two folders: SMAPI loads one and ignores the other, and which one is not predictable. On a real library this found **7 mods installed twice across 14 folders — three of them with both copies on**, one mod present both loose and inside its download folder. Nothing had ever said so.

- **A mod's page can look for what plugs into it.** Bag definitions, compatibility patches, content packs built on top of it: Nexus has no notion of "add-on", so the search asks the only question it can answer — which mods name this one in their title — and says so plainly rather than pretending to certainty. Translations are set aside by the tag Nexus puts on them, which is the only thing that separates them: searching "Sword and Sorcery" returns 26 results of which the first eight are Japanese, Chinese, Hungarian and Brazilian translations. The list is capped and **the total is stated**: "Wildflour's Atelier Goods" yields 3 candidates out of 12, while "Content Patcher" holds 428, and a handful shown without that number would look like the whole answer.

- **A downloaded config file is now installed where it belongs.** A whole genre of Nexus downloads is a single file replacing one a mod already ships — an alternative `bagconfig.json` for ItemBags, say. Both recognisers turned it away: one sorts by folder structure and it has none, the other by JSON key signature and a config file has none it knows. The app now matches the file **name** against what installed mods carry at their root. On a real library **76 of 91 distinct root JSON names belong to exactly one mod**, which is what makes the answer certain — while `config.json` belongs to 544 and `content.json` to 522, so those ask which mod rather than guess, and a bare `manifest.json` is never treated as a replacement. The file it overwrites is backed up, and it can be removed from the mod's page afterwards.
- **What is already installed is shown as such, and stops being offered again.** Both the French-translation and the add-on sections now open with what the mod already carries, each row offering removal — and, when a newer version has been published, an update. Anything in place leaves the list of suggestions, so the two lists no longer overlap. An add-on installed as a mod of its own is named as such and left alone: it updates through the ordinary path.
- **Updates are followed for things installed by hand, which is all of them on a free account.** Direct download needs Nexus Premium, so every translation and add-on arrives through the install sheet — with no Nexus page attached, and therefore no way to spot a newer version. The app now recognises the page on its own: the downloaded file name carries the Nexus id (14 of 15 reference archives do) and the title confirms it. Two independent signals agreeing, or nothing is attached — a row with no update tracking beats a row tracking the wrong mod. A menu remains for the archive renamed by hand.

### Changed
- **Search results can be closed.** Once a search had run, its list stayed on the mod's page with no way to dismiss it. A close control now sits beside the search button. It clears only what is on screen: the "a newer version exists" mark on the installed row survives, and so do the add-ons the mod actually carries — those come from disk, not from the search.
- **The search buttons look like buttons, and say why they are greyed out.** They were plain clickable text with long labels, disabled and silent when no Nexus key was saved. They are now bordered and short — "French translation", "Add-ons" — and the reason is written out, not just offered as a tooltip, since a disabled control is not guaranteed to show one.
- **The app no longer offers a download your account cannot make.** Nexus reserves direct API downloads for Premium accounts; on a free one every such button ended in the same error, discovered only after clicking. The account's status is now read once and kept for a week, and the three places that offered a direct download — mod updates, profile diagnostics, translations — disable it and say why. A **Nexus** button sits next to it, opening the mod's Files tab where the free Mod Manager download lives. Nothing is hidden while the status is unknown: a button that might fail beats a missing button for someone entitled to it.

### Fixed
- **Searching Nexus for a mod whose name starts with `[CP]` no longer comes back empty.** That bracketed prefix names the *framework* that loads the content pack — Content Patcher, Farm Type Manager, Alternative Textures — a folder convention, not part of the mod's title on Nexus. The search matches a substring of the title, so the prefix made it fail outright, silently: the page simply said no French translation exists. Measured on six names from a real library: 0 results with the prefix, 1 to 12 without. **148 manifests out of 995 carry one.**
- **An archive of several bags now installs all of them.** A file recognised as content for another mod — an ItemBags bag, say — was installed one at a time: the first of the archive, silently, with the rest left behind. Two of the reference archives hold ten and five bags. Every recognised file now goes in, and the confirmation names the count and the folder that will receive them.

## [1.19.1] - 2026-08-25

### Added
- **The mod list flags what is going wrong.** An orange badge next to a mod's name gathers three signals: errors and warnings SMAPI logged for it, a required dependency that is missing or paused, and a manifest with no identifier — which SMAPI will not load at all. Hover for the detail. The counts cover **the installed version only**, like the mod's own page: on a real library one mod had 76 errors on record but a single one on the version actually installed, and three others only had history against a version replaced since. A pack shows its components' trouble on its header, so nothing hides behind a collapsed row.

### Changed
- **The mod list lines up.** Category, author and version, then dates, weight, languages and French coverage: each value sits in a column of its own, at the same place on every row — comparing two weights or two dates across 863 mods no longer means hunting for them. A field with nothing to show keeps its slot, so what follows never shifts up. A long author name is trimmed in the middle, keeping both the original author and whoever maintains it now, with the full name on hover; so is a long version number. The bullets that used to separate these fields are gone — columns need no separators.

## [1.19.0] - 2026-08-25

### Added
- **Mods can be starred, and a profile can import what you starred.** A star on every row of the mod list, a chip in the toolbar to scope to them, and an "Import favourites" entry in a profile's ⋯ menu. The import says what it did: how many entered the profile, and by name the ones that could not — a mod uninstalled since, or one whose manifest declares no identifier, which a profile cannot hold. On the active profile it asks first, since importing there enables the mods on disk right away. A pack is starred as a whole and brings in every component it holds.
- **The mod list carries the weight of every mod, and can be sorted by it.** Finding what takes up the room used to mean opening mods one at a time. The figure sits in each row's metadata strip and turns orange past 100 MB — on a real library that marks 22 folders out of 863, holding 87% of the 16.8 GB. A new "Weight" sort brings them to the top, and the toolbar totals whatever the filters currently keep: scope to paused mods and it reads 12.7 GB, which is the answer to "how much can I get back".
- **The sidebar now says what your mods weigh, and what is left on the disk.** A bar splits the total between active and paused mods, and on a real library it lands where it hurts: 16.8 GB of mods, of which **12.7 GB paused** — 746 folders out of 863, three quarters of the weight returning nothing. The bar counts mods only; free space stays a line of text below, turning orange when less room is left than the mods already take. A mod's own weight also shows on its detail page; a pack states the weight of its whole folder rather than repeating it on each component. The measurement runs in the background after every scan of the mods folder, and says so while it works.
- **The Nexus quota left is now visible in Settings.** Nexus announces on every single response how many calls you have left today and this hour — the app simply threw those numbers away. They now show under the Nexus section, with the reset time, and are read on failures too: a refused call is exactly when the remaining count reads zero. No extra request is made to obtain them. Since the app only talks to the Nexus API on demand, a fresh install says so plainly rather than showing a blank or a false zero.

### Changed
- **The "All" view no longer groups mods by enabled/disabled.** It split the page into two sections before anything else, which overrode the sort you picked: sorting by weight surfaced the heaviest *enabled* mod, never the heaviest mod, even though three quarters of the weight sits in paused ones. The list now follows its sort order straight through. A mod's state still reads at a glance from the green or grey accent bar and the dot beside its name.

### Fixed
- **Creating a profile without a name silently did nothing.** Both "Create empty profile" and "Take the mods currently enabled" closed the dialog without creating anything, indistinguishable from Cancel. The name field now arrives filled in, and the two buttons are disabled if you clear it.
- **Deleting the active profile left the mods with no owner.** No profile was active any more, while the mods the deleted profile had enabled stayed on disk, and nothing said so. The delete dialog now also offers "Delete and activate <profile>", which picks up the default profile — next to plain deletion, since re-activating on its own would move hundreds of folders unasked.
- **A saved DeepL key no longer leaves its field open for editing.** Like the Nexus key, it is replaced by a mask once saved, so an existing key cannot be overwritten by accident.

## [1.18.0] - 2026-08-24

### Added
- **A translation can be recovered key by key, not just as a whole file.** When a mod update resets its French file and you retranslate part of it, replacing the file would cost you what you just wrote. The keys the installed file no longer has are put back one by one, leaving everything else untouched — and the screen shows the full comparison with the backup: keys only in the backup, keys added since, and the ones whose text changed, side by side. Translations that merely differ from their backup are listed too, for comparison only: nothing to replace there, the installed file is the newer one.
- **A backup can now give back a single file, without restoring the whole mod.** Updating a mod overwrites its entire folder, taking with it what the author does not ship — the French translation you installed by hand, your settings. The backups page lists what a backup can give back: files that are gone from the mod, or whose backup holds settings the installed file no longer has. A file you simply changed is never listed — that is not a loss. Preview before writing, one file at a time, and what is already in place is backed up first. On a real library: ten French translations that only exist in a backup.
- **A profile now says what will stop it from working.** An orange badge on the profile row opens a diagnostic in two parts. The mods it asks for and no longer has: named where anything still knows them, with a restore from backup when one exists and a Nexus download when the identifier is known. And the required dependencies the profile leaves out — a mod you added without its framework: the profile would pause SpaceCore and the mod that needs it would not run. One click adds the dependency back. It matters most for frameworks — a missing SpaceCore or Json Assets breaks every mod that depends on it, and the game used to just start without them.
- **Profiles now remember the name and Nexus id of each mod they hold.** Until now a profile stored bare identifiers, so a mod uninstalled later could not even be named. Profiles saved before this version keep working; they fill in as you change them.
- **A profile can be duplicated.** From its ⋯ menu: the copy carries the same mods under its own name, and is not activated — duplicating is how you start from a working set and change a few things.
- **The backups page can be browsed at last.** It listed every backup flat — 1 494 of them on a real library. Now one collapsible row per mod, its versions inside, plus search across name, folder, author and version, and four sort orders.

### Changed
- **A new profile now starts empty.** Creating one silently captured whatever was enabled at that moment — while the dialog claimed the opposite. It now asks: an empty profile, to fill mod by mod, or a copy of the mods enabled right now.
- **Restoring a backup now tells you what it did.** Instead of "restored successfully": the mod and version written, how many files, the folder they went to, whether the mod is enabled or paused, and which replaced version was kept as a backup — with a button to open the folder in the Finder.

### Fixed
- **Switching profiles no longer freezes the app, and shows what it is doing.** The mod folders were moved on the interface's own thread with nothing on screen: on a large library the window sat locked, with no sign of progress and no way to tell whether anything was happening. The moves now run in the background, behind a progress overlay that counts the folders as they go.
- **A profile no longer absorbs an activation that failed.** When a mod folder could not be moved — held open, permissions — or when the profile named a mod that is no longer installed, the app wrote the resulting state back into the profile: the mod left enabled by the failure became a mod the profile *asked for*, and the missing one was dropped for good. The profile now keeps what you asked for, and clicking the active profile again resumes the move instead of recording where it stopped.
- **Rolling back to an older version is no longer reported as up to date.** The app kept claiming the version it had before the restore — the update check refuses to follow a version *down*, reading it as an unfinished update — so the newer release you deliberately stepped away from stopped being offered. A restore now anchors the version it actually wrote.
- **Restoring a backup no longer leaves two copies of the mod.** Restoring over a mod you have enabled dropped the backup into a paused folder beside the live one — the same mod twice, the restored version invisible to the game. It now replaces the mod where it sits, and lands paused only when the mod is gone.
- **Backups stop piling up.** Copies byte-identical to another backup of the same folder are dropped — 172 MB on a real library — and the retention sweep now runs after an install, not only when you happen to open the backups page.

## [1.17.0] - 2026-08-21

### Added
- **You can now translate a mod with the chat you already use — no local server, no API key, no quota.** Export the keys with no French yet into one self-contained file, hand it to the chat, reimport what comes back. Existing French is never overwritten; a moved source, or a marker the chat lost or doubled, sets that one key aside by name — the rest still imports.
- **When the local AI fails — or isn't there at all — DeepL can take over.** Off by default, inert without a key, with a link to where DeepL shows it (the desktop app isn't one). Markers are shielded, your quota is read from your account, and the report says what came from where.
- **Select an English word or phrase and have just that translated.** Right-click the source, or use the button under it: the proposal comes back as a chip you click to insert where you want it. The whole sentence travels as context, untranslated.

## [1.16.0] - 2026-08-20

### Added
- **The app can now suggest a French translation, from a model running on your own machine.** One key at a time, or a batch you can stop. Suggestions arrive marked *Needs review*, with a filter to find them, and the game's markers are verified before anything is written. Nothing leaves your Mac.
- **The app warns when your model reasons before answering.** It spends its whole answer budget deliberating, so every key comes back truncated and refused — on one Mac, over 300 seconds for a single word. Settings asks the server what the model does, and says so before you start a batch.
- **The app now tells you which model to install.** A fresh Ollama has no model, and the right name is not guessable. Settings reads this Mac's memory, names one that answers rather than deliberates, and gives the command to run — or points at a suitable model you already have.
- **Suggestions speak the game's own French.** A glossary built from your installed game — 1 126 names, from items and tools to characters, locations and seasons — is imposed on the model, so a suggestion reads *Minerai d’iridium*, not an invented synonym. The terms show as chips in the editor.

### Fixed
- **A marker mismatch you accepted no longer comes back to block you.** Saying yes to a deliberate omission is recorded on the key, but it was dropped the moment the key was re-anchored — the next translation pass refused the save again, on a divergence you had already approved.
- **A translation key written twice now reads the value the game uses.** The game keeps the **last** value of a duplicated key, the app kept the first — so the Translation tab could show text the game never displays, and saving a mod wrote back the value the game ignores. The parser now keeps the last value, at the first occurrence's position: the game's own rule, measured on its bundled Newtonsoft.Json. On a real library, 58 translation files carry a duplicated key and 39 of them show two values that disagree.

## [1.15.0] - 2026-08-18

### Added
- **You can now translate a mod into French from the app.** The Translation tab was a report; it is now an editor. Click any line to open it side by side — English on the left, read-only; French on the right, yours to write — then step to the next key, or back to the previous one, without returning to the list. A mod with no French file yet gets one on the first save.
- **The game's markers are protected as you translate.** A translation mixes the sentence with things the game reads: a Content Patcher token, a dialogue break, the command that changes a portrait's expression. Losing one breaks the mod, silently. They show as clickable chips you insert rather than retype, and a save that drops one is refused, naming what is missing — with a way through when the omission is deliberate, since a gender-neutral French sentence has no use for a gender switch.
- **The Translation tab now opens on mods that have no French at all.** It was shown only where the work was already done: 115 translatable folders in a real library had no way in.

### Fixed
- **Clicking a line in the Translation tab opens it.** Selectable text covered nearly the whole row and swallowed the click, so only the status icon and the margins responded — the editor looked inert on every line you would naturally aim at.
- **A mod's existing French no longer vanishes when one of its folders ships no English file.** The whole component was dropped, and since a sibling folder still listed keys, nothing said so — 724 already-translated lines were simply absent from the tab.
- **Game markers are highlighted correctly in the Translation tab.** Three forms were being cut in half, so part of a command showed as ordinary text a translator could edit: `$10` read as `$1`, leaving the `0` behind; `%kid1` and `%kid2` both read as `%kid`, making the first and second child indistinguishable; and `#$action AddQuest` shrank to `$a`, leaving "ction AddQuest" looking translatable. Found by measuring the reader against 2365 real translation files.

### Removed
- **Internal: the update check's dedupe window is gone.** It had held no value and answered no question since the check moved to smapi.io — nothing stamped the timestamp, nothing read it. Behaviour is unchanged; the orphaned `nexusLastCheckAt` preference is simply no longer used.

## [1.14.1] - 2026-08-14

### Fixed
- **The update list no longer changes count between a check and a restart.** Mods belonging to one pack were grouped into a single row when the app started, but not after clicking Check for updates — so the same library read differently depending on how you got there. The list shown is now always the grouping of the list stored, whichever path you take. A stored row could also end up carrying a pack's name in place of its own.
- **Removing your Nexus API key no longer erases the updates found.** They were cleared along with the cached account data, from a time when they came from Nexus itself. They come from smapi.io, which has no account — there was nothing to clear, and getting them back meant running the whole check again.

## [1.14.0] - 2026-08-14

### Added
- **"I already have it" on an update you've already installed.** Some authors ship a new version without bumping the `Version` in their manifest, so the check sees a gap that isn't there and reports it again at every pass, forever. The row now carries a button that records the version you actually have and drops the row. On a pack it covers the component the row stands for, not every mod in the pack.

### Fixed
- **A `nxm://` link no longer leaves the app stuck.** Clicking "Mod Manager Download" on Nexus while StarHubFR was closed started the download during the launch screen, so the install window opened on a main window that wasn't on screen yet: it couldn't be closed, and the app itself couldn't be reached. The link is now handled once the window is up. A window that appears during launch can also no longer be mistaken for the main one and revealed in its place.
- **An update now carries the mod's own name.** The row was labelled from SMAPI's compatibility list, which only covers mods listed there: on a real library 15 of 23 updates fell back to the raw identifier — "xzqute.ChoreTrail" instead of "ChoreTrail". Each row now shows the name the mod declares, the same one the mods list shows, so a mod no longer changes name from one screen to the next.
- **The download button is back on updates that had lost it.** A row only offered the in-app download when smapi.io returned the mod's Nexus id, and it only knows that for mods on its compatibility list: on a real library 15 of 23 updates came back without one, though every one of them declared a Nexus link in its own manifest. That link is now read when smapi.io has nothing. A mod tracked only on GitHub or CurseForge still shows no download button — there is no Nexus page to fetch.
- **The update check no longer comes back empty.** The request never said which client was asking, and smapi.io answers such a client with metadata only — it computes no update suggestions at all, leaving the caller to compare versions itself. So the check ran its seven batches, got an answer for all 909 mods, and reported not one update. The same request with that one field declared finds 42.
- **A stray character in the game version can no longer empty the whole check.** The version is read from the SMAPI log with a pattern that accepts a trailing dot, and smapi.io answers an unparsable version with an empty list — no error, no message, every mod in the batch simply gone. Only a version the server can read is sent now, with a known-good fallback otherwise.
- **Installing one mod no longer clears another mod's update.** The just-installed mod's row was dropped by Nexus id, and a Nexus id names a page, not a mod: 47 of them in a real library are claimed by several mods, and one — 8828 — by three unrelated mods whose author reused the same update key. Installing any of the three made the other two read as up to date until the next check. Only what was actually written to disk is cleared now.
- **Checking for updates no longer needs a Nexus API key.** The check runs through smapi.io, which asks for neither key nor quota, but the button stayed greyed out without one — and the "add a key" prompt sat where the list of updates should have been, so a user without a Nexus account saw no update at all. The key is now only what it still is: what the in-app download needs.
- **Mod updates are found again.** The app was recording whatever Nexus had published as the version you had installed, so it compared that version against itself, concluded you were current, and dropped the row — every update erased itself on the next check. A mod the check couldn't reach keeps its row instead of passing for up to date, and the Logs tab reports how many mods could not be checked at all — 109 of them on a 966-mod library, where nothing distinguished them from a mod verified and current.
- **A mod no longer shows a version it doesn't have.** 52 folders of a 966-mod library displayed the version published on Nexus instead of the one their own `manifest.json` declares — the same wrong reading that made updates vanish. Each mod now shows its own version.
- **A mod installed from Nexus is now linked to its Nexus page.** The app knew the mod's id at download time and discarded it, so a mod whose manifest omits `UpdateKeys` was never checked for updates again, with nothing said. New installs only — mods already installed still need the id entered by hand.
- **Deleting, duplicating, backing up or restoring a save no longer freezes the window.** Each copies or removes a whole save folder — tens of megabytes over hundreds of files — on the main thread. They now run in the background, buttons disabled meanwhile so a second click can't start a second copy.
- **Installing a pack no longer fires a burst of Nexus requests.** Once installed, the app looks up each mod's Nexus page, and the loop sent every request at once — a 20-mod pack opened 20 connections in one go, the fastest way to get rate-limited. They now go six at a time, the same bound the update check uses.

## [1.13.1] - 2026-08-11

### Added
- **A French translation the English has moved past is now flagged.** The mod's page names the date English was last edited and the gap to the French translation, and a "To review" filter gathers them. Its Translation tab marks outdated keys too, once opened, old English struck through.

### Fixed
- **Installing a `.7z` or `.rar` works again.** The zip-slip guard added in 1.13.0 read the archive's own absolute path from the listing header and took it for an entry escaping the folder, so every such archive was refused as "failed to extract". Only zips were unaffected — anyone on 1.13.0 could not install a 7z or RAR mod at all.
- **A mod's translation file saved as UTF-32 is now readable.** It came back with a null character between every letter, because its byte-order mark starts with UTF-16's. Measured against .NET's own reader, which the game uses — as was a second, smaller alignment: a file name holding a stray newline now folds to its language code the way the game folds it.
- **A translation key holding a quote is no longer orphaned.** The Translation tab read `a\"b` where the parser gives `a"b`, so the key matched nothing: no section, no rank, no place in the outline.
- **Editing a save field that was empty now works.** Filling in a blank favourite thing changed nothing on disk — and still reported success.
- **The config editor speaks French.** Nine of its messages were written in English whatever the interface language, and a failed `.bak` restore left no trace at all: the file picker just opened, unexplained. The backup counter also read "12 gérer les sauvegardes"; it now reads "12 sauvegarde(s)".
- **A SMAPI install that half-succeeds now says so.** The version marker can fail to write while SMAPI itself installs fine — the app would then believe SMAPI was missing at the next launch, with nothing in the Logs tab about it.
- **Mod install errors now speak the app's language.** The ten failures an install can report — extraction refused, backup failed, mod not found — only ever came out in English, whatever the interface was set to.
- **A downloaded archive is no longer lost when a second Nexus link arrives.** A second `nxm://` link while the install sheet was open replaced the waiting archive: the first was orphaned in the temp folder, and the cleanup then deleted the wrong one. The second download is now refused until the first is installed.
- **A translation the game will never load no longer counts as one.** The game opens bare language codes only, so a `pt-BR.json` is dead weight — 26 of them in a real library. They were credited to their base language; the mod's page now names each and the name it should carry.

## [1.13.0] - 2026-08-06

### Added
- **The translation tab now has an outline.** Sections an author wrote in their file are headed, collapsible, and carry what's left to do in them — so a section that's done stops competing for attention. A sections list jumps straight to one: Ridgeside Village has 1881 of them.
- **See the French of a mod key by key.** A new Translation tab on a mod's page lists every key with its English and French side by side, and what state it's in — translated, to translate, empty, same as English, orphan. Each filter carries its count, so "Empty 3" catches the eye before you click. Components of a multi-part mod stay separate, each with its own English source.
- **What must not be translated is now visible.** A translation value mixes the sentence with marks the game reads: a Content Patcher token, a dialogue separator, the command that changes a portrait's expression. Translate or move one and the mod breaks. They now show in monospace and colour, in both columns. Across 450 French files, 54% of values contain at least one.
- **A French translation lost to a mod update is now reported.** Mod updates replace the whole folder, and authors don't always ship back the community translations sent to them — the `fr.json` just vanishes. Where a StarHubFR backup still holds one, the mod's page says so with its date. In a real library that's 43 of the 86 translatable mods without French: half of them.
- **A mod's page now says what's missing from its French, not just how much.** A key that's *absent* falls back to English and nothing breaks; a key that's *empty* shows nothing at all, silently — a mod at 98% whose last 2% are empty is more broken than one at 60%. The two are listed separately, empty first. 24 mods in a real library carry empty keys and nothing flagged them. A progress bar and the key counts sit above.
- **The translation filter can now show the mods you've started but not finished.** 392 mods fully translated against 31 partly done: those 31 are the work left, and they were unfindable among the rest.
- **Every mod now shows how much of it is actually translated into French.** The list carried "FR available" as soon as an `fr.json` existed — a half-truth on a mod translated at 8%. A pill now gives the rate: green when it's complete, amber when it isn't. It only reads 100% when every key is done, so a mod one key short reads 99%. The figure is measured in the background after a scan, so it appears shortly after the list.
- **A download that belongs inside another mod is now installed there.** Some Nexus files are content for a framework, not mods of their own — an ItemBags bag, say — and carry no `manifest.json`. The app recognises them and offers to put the file where it belongs, showing the exact path first. It works while the host mod is paused, and says so. An existing file is backed up first; a backup that fails cancels the install rather than overwriting anyway.
- **Mod translation files are read the way their authors write them.** Comments, trailing commas, unquoted keys, raw line breaks, CRLF endings — a strict JSON reader refuses 912 of the 2357 files in a real modlist. Checked against the game's own JSON library, file by file: what it loads, we now read.

### Fixed
- **A failed quarantine action no longer looks like a success.** Emptying the trash could fail, but the error was shown with a green checkmark; a failure now shows in red with an error icon.
- **A mod's update link is now clickable, and its dead info button is gone.** The "visit website" URL rendered as raw Markdown text instead of a link; the info button next to it did nothing, so it was removed.
- **The cancel button on the restore confirmation now says Cancel, not OK.**
- **The Thai translation hub now matches a mod the same way when checking and when installing.** The two steps stripped the `[CP]` prefix differently, so a content pack whose name had no space after `[CP]` could be detected but installed under the wrong zip name.
- **A logged mod name now resolves to the right mod, not just the first whose name contains it.** An exact match is tried first, and among partial matches the most specific (shortest) name wins — so "Farm" no longer resolves to "FarmExpansion".
- **Installing a Thai translation no longer uses a blind `unzip`.** It now extracts through the same archive handler as mod installs, so a translation shipped as `.7z` or `.rar` installs instead of silently failing.
- **Cloning a save no longer reports success when rewriting its internal XML fails.** The clone got a new folder name but its inner name fields were left stale, so Stardew saw a save that didn't match — yet it was shown as a success. A failed rewrite now aborts and removes the partial clone.
- **A mod's version is now read through its JSON parser, not a raw text match.** A `"Version"` left in a comment — common in Stardew's JSONC manifests — was matched before the real one, so the wrong version could be read or compared.
- **A failed Nexus download is no longer saved as the mod file.** A 403 (expired link) or 429 (rate limit) returns an HTML page, which was kept as the archive; the HTTP status is now checked before saving.
- **Duplicate detection no longer truncates a mod's path when the mods folder appears more than once in it.** It reuses the canonical relative-path helper instead of a string replace that cut at every occurrence.
- **A leftover set-aside folder is now removed even when it carries read-only permissions.** The old version moved aside during a restore couldn't always be deleted, leaving a `.stale_*` folder the mod scanner mistook for a paused mod.
- **The zip-bomb guard now covers 7z and RAR archives, not just zip.** It relied on `unzip -l`, which only lists zips, so a crafted 7z or RAR — which compresses far harder than zip — slipped past the pre-extraction size check. The 7z tool, which also reads RAR, now lists those formats first so the same 2 GB cap applies.
- **Finding a broken mod by bisection no longer blames the wrong step.** Each step's log evidence was read from a value that had already advanced to the next trial by the time the log was parsed, so the "appears only with" clue was computed on shifted data. The mods enabled for a step are now frozen at the moment it is answered.
- **An archive whose name lies about its format no longer fails as corrupt.** A `.zip` that is really a `.7z` was read by its extension, sent to the wrong extractor, and rejected as "corrupted". Format now comes from the file's signature, as the Nexus download path already did, and it installs in its true format.
- **Toggling a mod on then straight off no longer leaves it on.** A rapid double-click scheduled the on and the off one after the other, and both fired — so the first click won, the second was lost, and the mod ended up in the state you'd already moved away from. The second click now cancels the first before it runs.
- **The profile list no longer loads on the wrong thread at startup.** The launch sequence read the saved mod profiles on a background queue and assigned them straight to a published property — a pattern SwiftUI flags as unsafe, which could leave the profile list empty or inconsistent until the next redraw. The load now runs on the main queue, with the rest of the launch steps.
- **Updating a mod no longer discards its translations.** The "install with backup" path snapshotted a mod's `config.json` and language files before replacing the folder, then restored them — but it looked for `fr.json` and the rest at the mod's root, where they never live, instead of under `i18n/`. They were never snapshotted, never restored: a community translation the author didn't ship back vanished on every update. The manual config backup had the mirror flaw, restoring language files to the root where SMAPI never reads them. Both now key by relative path and recreate `i18n/`, through one shared search so they can't diverge again. The 16 `fr.json` that survive only in a backup are how long this went unnoticed.
- **A mod description's links no longer break when its text uses Windows line endings.** The Nexus web editor writes `\r\n`, which Swift counts as a single line-break character — so a check for `\n` missed it. A multi-line link label was then emitted as broken Markdown, and its closing `](https://…)` showed up raw. Headings and coloured spans had the same blind spot; all now detect a line break by what it is, not by the character it isn't.
- **Branching a save whose name has a dot no longer produces an empty branch.** Stardew ties a save folder to an internal file of the same name. Branching from a backup recovered that name by splitting on `.` and taking the first piece — fine for `Alice`, wrong for `Farm.1`, which became `Farm`. The internal file was then never renamed to match the new folder, so the game ignored the branch silently. The backup already carried the original name; the branch now reads it from there.
- **Three more kinds of code are now flagged in translations.** The gender selector `${him^her^them}$` — 1520 of them in a real library — had its `^` read as a line break and its words as translatable text, so translating "him" would have broken the selection. Mail commands like `%item object 349 10 %%` only had their first word marked, leaving the item IDs exposed.
- **Translation files that aren't UTF-8 are read again.** Four files in a real library were refused outright: one in UTF-16, three in a legacy 8-bit encoding. The game reads all four — the first perfectly, the other three with their accents replaced — and the app now does the same, telling the two cases apart instead of rejecting both.
- **The "to translate" filter no longer buries what you're looking for.** It returned 397 mods, 310 of which ship no translation files at all — a mod with no text to translate isn't missing a French translation, it's beside the point. The filter now asks for mods that can actually be translated: 87 instead of 397. Renamed too: "No FR" described an absence, "To translate" describes what you'll find.
- **The French filter no longer misses most of your translated mods.** Language detection only looked at `<mod>/i18n`, and only at file names. But a content pack keeps its `i18n` one level down, and a mod can put a whole folder per language. On a 821-mod library that came to **90 mods read wrongly, 81 of them with their French invisible** — so the filter, the mod page and the language list were all wrong about them. Regional variants (`pt-BR`) now count towards their base language, and Vietnamese was missing from the list of languages entirely.
- **An archive that isn't a mod no longer tells you to check the file for damage.** Refusing it is right; sending you to re-download an intact file was not. The app now says the archive is fine and what the file appears to be. Same for a dropped file whose format isn't supported.
- **A save whose farm, player or spouse name contains `&` or `<` no longer turns unreadable.** These characters are illegal in raw XML, and the save editor wrote them in as-is; at the next scan the save failed to parse and dropped out of the list. Names are now escaped on write and unescaped on read, matching how Stardew itself stores them.
- **Installing a mod where one already exists no longer deletes the old folder if the copy then fails.** The destination was removed before the copy began, so a full disk or a permission error mid-copy left nothing to fall back to. The existing folder is now set aside first and restored if the copy fails.
- **Restoring your mods after an interrupted bisection no longer disables them all.** The restore path filtered the folders to re-enable through a list that is empty in recovery mode, so it ended up enabling none — turning "Restore" into "disable everything". The recovery path now applies the saved set directly.
- **A crafted archive can no longer write files outside its install folder during extraction.** The extractor ran the archive tool without first checking its entry list, so an entry like `../../etc/x` would land above the install folder (zip-slip). Entry paths are now validated before extraction.
- **The config editor no longer offers Save on an empty box.** An empty `config.json` is invalid, and the Save button stayed active when the text was cleared, so a misclick wrote an empty file that stops the mod loading.
- **String values in a mod's `config.json` array are now editable.** Only numbers and toggles were modelled; a name or a path sat as raw text the editor silently dropped, so changing it did nothing.
- **A backup's note no longer drifts onto a different backup when a newer one is added.** The list was keyed by row index, but it is ordered newest-first, so each new backup shifted every index down by one and inherited the note being typed on the row that took its place.
- **Deleting a config backup now tells you if it failed, instead of silently reloading the list.** A read-only backup couldn't be removed, but the error was swallowed and the row stayed, looking like the click did nothing.
- **A mod's picture no longer shows the previous mod's image when its own fails to load.** The old image was left in place if the new URL errored, so a missing banner showed whatever you had open before.

### Changed
- **Internal —** Every shipped build now carries its own build number. `release.py` increments `CFBundleVersion` before building instead of it being kept by hand, which is the number macOS and any future update check compare. The version you see is unchanged.
- **Internal —** Development tooling: a domain-knowledge document for contributors, and a ratchet that fails the build on any *new* breach of the project's Swift conventions while leaving the existing ones alone.
- **Internal —** A full audit of the Swift codebase (~72 findings across 8 areas) is now written down in `docs/audit-swift-2026-08-05.md`, each one verified by reading the code. The previous audit's detail lived only in a session and was lost between them. The nine high-severity findings it raised have been fixed.

## [1.12.1] - 2026-08-01

### Fixed
- **System files no longer show up as paused mods.** The scan treats any dot-prefixed folder as a paused mod, but its idea of "system litter" was narrower than the app's three other copies of that same rule — it didn't know `.Spotlight-V100`, `.Trashes` or a folder's custom `Icon` file. A `.Spotlight-V100` therefore sat in the list as a disabled mod named "Spotlight-V100".
- **Updates SMAPI reports are detected again.** The "You can update N mods" block SMAPI writes at startup was read until the first line not carrying an `ALERT SMAPI` tag — but the real format puts a blank line between entries, right after the header. The block was therefore closed before a single entry had been read, so no such update ever showed up: not in the sidebar count, not on the Updates screen, not in the footer, and with nothing said about it.

## [1.12.0] - 2026-08-01

### Added
- **Pause or delete a mod from its own page.** Both actions were only in the list, so deciding a mod's fate meant going back to it — right after reading the very description, dependencies and error history that informed the decision. Same confirmations as the list, and a pack's components don't carry them: the pack header does, as before.

### Fixed
- **The mod list keeps its sort, filters and page when you open a mod and come back.** Sorting by install date, scoping to one category, paging to the mod you wanted, opening it — and landing back on page 1 of an unsorted, unfiltered list. Opening a mod replaces the list rather than covering it, so it was rebuilt from scratch on the way back; leaving for another tab did the same. The search box keeps its text too.

## [1.11.1] - 2026-08-01

### Added
- **The mod the search found is no longer just a name.** Its page in the app and its Nexus page open in one click, and "keep this mod paused" closes the search without switching it back on — until now the only button on that screen turned the culprit back on, and accepting the verdict meant clicking nothing. The mods the log blames open the same way.

### Fixed
- **Jumping to a mod now works for packs.** Opening a mod from a log line, from the health card or from the search looked it up by display name among individual mods only, so a multi-component pack matched nothing and the jump did nothing at all.
- **The end of a search no longer claims your mods are back on before they are.** The closing screen is reached before the restore finishes, so a restore that partly failed left the claim on screen while the failure alert contradicted it. The screens now state what actually happened, and say what to try — closing a Finder window on the Mods folder is the usual culprit.


## [1.11.0] - 2026-08-01

### Added
- **Find the mod that breaks your game.** The app pauses half your mods, starts the game, and asks one question — "is the problem still there?" — narrowing down over roughly seven steps for a hundred mods. It ends on a confirmation run, because halving produces a lead, not a proof.
- Each step reports how many mods are already in the clear. When no single mod can be blamed, the ones still involved are named rather than withheld.
- The mods in the clear, and those still in the trial, can be expanded and copied out of the app; the lists scroll and flow into columns.
- **The report says what each error was, and what makes it appear.** Naming a mod and a count answers neither "what went wrong" nor "why does it sometimes stop". Each blamed mod now shows the error itself, and — by comparing the steps where it complained against those where it ran quietly — the mods that have to be on for that error to show up at all.
- **The log is watched while you play, and cross-checked against the search.** StarHubFR's own log view now stays current instead of refreshing only when you answer. Mods the log blames are named at the end, with how often each appeared while the problem was present — an intermittent error shows up in some steps, not all.
- When the log blames a different mod than the search concluded, the card says so: two mods that don't get along make either one "the" culprit, and the search can only name one of them.
- Nothing is deleted: your starting state is written to disk before any folder moves, and "put everything back" is one click away at every step. A search interrupted by quitting the app is offered back on the home screen.

### Fixed
- **Errors SMAPI logs on a mod's behalf are now attributed to that mod.** SMAPI writes some failures itself, with the mod's name only as a prefix in the message — `[SMAPI] [ERROR] Gunther's Guide: …`. Those went to nobody: not to the mod's own error history, not to the guided search. Warnings count now too, not just errors.
- **Mods whose manifest keeps SMAPI's own template comments now install.** The template ships with `//` comments and a trailing comma, which many authors leave in place. Only the scan accepted them, so a valid mod was refused with "manifest.json missing" while showing up fine if copied in by hand. All four places that read a manifest now share one reader. Reproduced on *Susan of Emerald Farm* (Nexus 45990).
- An archive with no recognisable mod structure now lists what it does contain, instead of only saying what it lacks.
- **The search no longer accuses the wrong mod.** Pausing a framework left the content packs that need it running without it, changing the game for reasons unrelated to the mod being hunted. Packs are now paused alongside their framework.
- The next step waits for you to quit the game, instead of launching a second copy over the running one.
- **Skipped-mod lines fold into one row.** SMAPI names the mod without quotes, so nothing matched — a search that pauses fifty folders filled the log with fifty near-identical lines.
- The diagnostic card no longer pushes the log list and its own collapse chevron off-screen.

## [1.10.3] - 2026-07-31

### Added
- **`.7z` archives install**, alongside `.zip` and `.rar`, on all four routes: drag-and-drop, the install button, a Nexus update, and an `nxm://` click. Extraction uses whichever of `7zz`, `7z`, `7za`, `7zr` or `unar` is present.
- A 7-Zip status row on the home screen, beside the one for The Unarchiver, so a missing tool is visible before an install fails.
- The launch screen shows the app version, beside its name.

### Fixed
- **An unsupported archive is no longer called corrupted.** The message now names the formats that are accepted.
- **A mod downloaded from Nexus keeps its real format.** The temporary file was named from the download URL, which for free downloads carries no usable extension — a `.7z` was saved as `.zip` and handed to `unzip`. The format is now read from the file's own first bytes.
- Extraction tools are found wherever they are installed: MacPorts, Nix, `~/bin` and the user's `PATH` were all missed by the previous four-directory search.
- A mod folder no longer keeps its archive extension when the archive has no enclosing directory.

## [1.10.2] - 2026-07-31

### Added
- **Mod descriptions render their structure, not just their text.** Headings, lists, code blocks, quotes and centring are now drawn in the app's own typography; author colours are honoured after automatic contrast correction to WCAG AA, and `[u]` is a real underline. Verified across 51 cached descriptions.

### Fixed
- **Descriptions no longer show their own markup.** Rendering was a chain of text substitutions, which cannot see structure. Twelve distinct defects, all reproduced on real Nexus pages:
  - Nested spoilers printed a leftover `[/spoiler]` and hid 5 of 22 images.
  - `[size]` became bold whatever its value, so pages where the author sized their paragraphs came out entirely bold, headings indistinguishable.
  - `[CP]` was erased — it is not markup but the literal name of SVE's folders, so install instructions were displayed wrong.
  - Images inside a heading, a list or a link were printed as markup; stray `**` and bare `](https://…)` appeared throughout.
  - Nested colours were mispaired, emphasis ate the space beside it, and a multi-line link label produced a broken link.
- **Updating a mod whose folders are read-only no longer fails.** Some archives ship directories as `r-xr-xr-x`, and removing a directory's contents needs write access on it — the app could not undo a tree it had just written. Permissions are normalised at extraction, and a blocked update repairs them and retries.

## [1.10.1] - 2026-07-30

### Fixed
- **Archives packaged on Windows are no longer rejected.** They use backslashes as path separators; `unzip` converts them and extracts everything, but exits with a warning status the app treated as failure. Since most of what Nexus serves is packaged on Windows, this affected a large share of installs. Success is now confirmed on what actually landed on disk.
- **RAR mods can be updated, not just installed.** Every Nexus download was written to a file named `.zip` regardless of its format, so a RAR update was handed to `unzip`.

### Changed
- The install flow no longer claims to accept only zip files: eight of its nine strings said "zip" while RAR has been accepted since 1.7.1.
- The missing-RAR-tool error is localized, and recommends `unar` — the same tool the home screen names.

## [1.10.0] - 2026-07-30

### Added
- **Repetitive log lines are folded into families** — a real SMAPI log is ~90 % TRACE, dominated by a few shapes with a varying name (`Content Patcher loaded asset 'X'` ×646, `Loaded 'X'` ×396). Runs of five or more consecutive same-shape lines now collapse into one expandable row showing the first message and "N similar lines", taking a 4000-line log down to a few hundred readable rows. Nothing is discarded: the detail is one click away, and "copy all" and the entry count still cover every real line.
- **Optional per-mod grouping in the Logs tab** — a toolbar toggle switches the log from one chronological stream to collapsible per-mod sections, each with its line count and a red or orange dot so a mod with errors can be spotted while collapsed. Sections are ordered by what needs attention (errors, then warnings, then the noisiest), and SMAPI's own output gets its own section that always sorts last. Chronological remains the default.
- **Per-version error tracking for each mod** — StarHubFR now records the errors and warnings a mod logs, per mod version, and the mod detail page shows them under **"Error tracking"**: counts, when they were last seen, a few sample messages, and a marker on the version you currently have installed. This answers the question a new version raises — does it behave worse than the one before? Stored as its own file so the install registry stays untouched, and forgotten when a mod is deleted.
- **Jump between a diagnostic and what it refers to** — every mod named in the health card carries two buttons: one opens it in the Mods list (scoped to it), the other filters the log down to its lines. Risk-category headers also get a button showing SMAPI's own block for that category — the complete list of affected mods as written in the log, beyond the few the card displays.
- **Plain-language SMAPI diagnostics** — the health card now explains what the log means instead of quoting it. It leads with **"What you can do"**: actionable advice in the user's language (install a missing dependency, remove a duplicate install, update a mod that doesn't support your game version, back up saves before playing with a save-serializer mod, narrow down a crash by halving the list of code-patching mods). Below it, each risk category — mods changing game code, mods changing your saves, broken mods, console-access mods — is listed with a one-line, jargon-free explanation of what it means for the player, plus the mods logging the most errors. Risk categories are parsed from SMAPI's own warning-group sections (skipping the separator line, unlike the reference implementation) and are treated as informational, so a large modlist doesn't read as permanently "unhealthy".
- **"Errors you can ignore" in the SMAPI diagnostics** — known-harmless log lines are recognized and explained rather than alarming the player: platform sign-in (GOG Galaxy), an optional integration with another mod that couldn't be wired up (typically a config menu, usually a version gap), an optional companion mod that isn't installed, and mods failing to read their own data. Each entry names the mod, shows how many times it recurred, quotes the original message as evidence, and offers a button that scopes the Logs view to that mod's lines. Matching works on families of phrasings rather than exact wordings, and a mod that declares its own warning ignorable is taken at its word. Crucially these no longer feed the per-mod error tally, which was blaming working mods for optional integrations they can live without; genuine errors keep their full weight.
- **SMAPI health card in the Logs tab** — a new collapsible card above the log list (visible on the All and SMAPI tabs) summarizes SMAPI log health at a glance: SMAPI + Stardew Valley versions, loaded mod and content-pack counts, skipped mods (with reasons), failed mods (with reasons, missing dependencies surfaced plainly), and known external conflicts (e.g. RivaTuner Statistics Server). It auto-collapses to a green "All healthy" summary when there are no problems and expands to list issues when some are found. An orange badge flags a stale log when `SMAPI-latest.txt` predates the current StarHubFR session (i.e. no game launch logged since the app opened), shown with a relative timestamp, and an "Open SMAPI log in Finder" button reveals the file. Backed by a new pure, unit-tested `SmapiDiagnostics` parser (Core target) mirroring `SMAPILogDoctor` output; mod update alerts stay on the separate Updates tab.
- **Tooltips on icon-only buttons** — the icon-only buttons across the app now show a localized tooltip on hover explaining what they do: Mods list pagination (previous/next page), window back/forward navigation, Saves view-mode (list/grid) + reload + expand/collapse + close editor + clear inventory slot, install-preview mod details, save-timeline edit-note + delete-backup, and the Logs clear-search button. (11 new tooltip strings, en/fr; `InfoPopoverButton` was deliberately skipped since it already surfaces help via a popover.)
- **Logs tab: clearer app activity + destructive-action guard** — StarHubFR now logs previously-silent user actions in the user's language: app startup ("StarHubFR started", previously the stale "StarHubTH started"), profile creation (name + mod count) and deletion, and Nexus download success/failure (only the start was logged before). "Clear logs" in the Logs tab now asks for confirmation before wiping, and clarifies that only StarHubFR entries are removed (SMAPI entries are kept).

### Changed
- **The launch splash is its own window** — it used to be drawn inside the main window, so the 900×600 frame and its title bar were on screen before anything had loaded, and the native menus had to be torn down and restored just to stop Cmd+W acting on a half-built UI. The splash is now a separate centred panel and the main window doesn't appear at all until the app is ready, then fades in. Its backdrop is tinted from the cover artwork rather than flat black, which read as a hole punched behind the image.
- **"Logs" is now "Diagnostics & Performance"** — the sidebar entry name reflects what the tab has become: a health card that explains your SMAPI log, not just a stream of lines.
- **The diagnostics card is readable at a glance** — it had grown into eight sections stacked with identical spacing, everything between 9 and 12pt, with no way to gauge the situation without expanding and counting entries by hand. The header now carries the verdict: status, versions, and a strip of counts per severity (won't load / missing / to watch / harmless). Each section became its own tinted card with a severity rail and an icon chip, colour-coded by how much it matters — a skipped mod no longer looks like a console-access note. Per-mod actions are grouped into one control with proper hit targets, raw log excerpts sit in their own inset block, and suggestions are numbered in priority order. The expanded card takes two thirds of the view and no longer blends into the log list behind it.
- **Logs tab: faster rendering + leaner filter bar** — the source and level filters are merged into one row (was three stacked bars), reclaiming vertical space for the list. Filtering is now single-pass (one pass per render instead of ~9 recomputed filter passes), and the list moved from `List` to a lazy stack — opening the "All" tab no longer spins the wait cursor for several seconds on large SMAPI logs (the previous `List` built/measured all ~2000 rows instead of virtualizing).
- **Logs tab surfaces severity at a glance** — StarHubFR's own log entries are now colored by level (badge + message), so an app error/warning is no longer indistinguishable from an info entry; SMAPI TRACE entries are dimmed to stay readable. The level filter pills now carry per-level count badges (scoped to the selected source), the app source tab is labeled "StarHubFR" (was the stale "StarHubTH"), and "Reload SMAPI log" now replaces the previous snapshot instead of relying on a manual clear.

### Fixed
- **Startup warnings and errors were missing from the Logs tab** — they were counted and explained in the diagnostics card, and plainly present in `SMAPI-latest.txt`, but absent from the list. The card parses the whole file while the list capped at 2000 entries by keeping the *last* 2000 — and SMAPI writes its entire diagnostic at startup, at the top of the file. On a 4038-line log that discarded the first 2038 lines, holding 174 WARN/ERROR/INFO entries. Trimming now sheds TRACE noise instead of the head of the log, so every warning and error survives (measured on the same log: 3 kept before, 11 after — all of them).
- **Clicking a mod name in the log showed the full mod list** — the click switched to the Mods tab but the list arrived unfiltered, because the request was handled by a view that doesn't exist until that tab is open. It now travels through the ViewModel, so the list scopes itself to the mod on arrival, clearing any filter that would exclude it.
- **"Reload SMAPI log" wiped the StarHubFR log** — reloading appended up to 2000 SMAPI entries then trimmed the combined list from the front, which evicted the StarHubFR (app) entries whenever the SMAPI log was large. The cap is now budgeted per source, so app entries are never evicted.
- **Copied log lines lost their origin and mod** — "Copy line" / "Copy all" now include the source (StarHubFR/SMAPI) and the mod name: `[ts] [Source] [LEVEL] Mod: message` (mod prefix omitted when absent).
- **TRACE level label leaked "SMAPI"** — the internal level case (rawValue "SMAPI") was renamed `.trace` (`"TRACE"`), so copied TRACE lines read `[SMAPI] [TRACE]` instead of the confusing `[SMAPI] [SMAPI]`; the TRACE level pill is also now hidden on the StarHubFR source (app entries are never TRACE).
- **Duplicate SMAPI log entries piled up on every game launch** — `startSmapiLogWatcher()` (called after each launch path) routed to `loadSmapiLog()` → `parseAndAppendSmapiLog()`, which appended the full `SMAPI-latest.txt` without clearing or dedup, so N launches left N stacked copies in the Logs tab. Fix: `parseAndAppendSmapiLog` now replaces the existing `.smapi` entries (reload semantics) before appending. Also removed the dead `logOutput` buffer (written app-only, never read) and simplified `appendLogEntry`/`log()`.
- **Launch splash progress bar looked frozen / teleported** — `launchProgress` is published as a few discrete weights (0.05 → 0.15 → 0.25 → …) with real wall-clock gaps between them, so the bar snapped between weights then sat still during the registry decode and the folder-repair sweep (which runs before per-mod names stream), giving the impression of a frozen bar that jumped straight to ~15 %. It also briefly regressed at the end of the scan: clearing `scanProgress` before advancing `launchProgress` to the scan-end weight snapped the bar back to the scan-start value. Fixes: (1) the progress bar now *creeps* toward its target on a timer — always moving, even mid-gap, never teleporting; (2) `scanMods` publishes an early `(0/N)` frame ("Preparing mods…") before the repair sweep so the count + caption show during that phase instead of nothing; (3) `launchProgress` is advanced to the scan-end weight before `scanProgress` is cleared, so the bar no longer dips at the end of the scan.
- **Multi-component mod packs installed as separate mods instead of one pack (e.g. Lilybrook)** — `ModZipInstaller.detectZipStructure` classified any zip with more than one manifest folder as `.multiMod`, and `buildInfo` then used only the last path component as each component's install destination (`destFolderName = lastPathComponent`), discarding the shared parent folder. A pack like Lilybrook (`[CC]`, `[CP]`, `[FTM]` under one `Lilybrook/` folder) was therefore extracted as separate top-level folders under `Mods/`, and since the scanner only groups mods nested under a single top-level folder, it appeared as individual mods. Fix: in the `.multiMod` branch, when every component shares one top-level parent, preserve it (`Mods/<Parent>/<leaf>`) via a new `commonParent(of:)` helper so the scanner groups the pack into a single entry; flat collections (no shared parent) keep the existing one-folder-per-component behavior. Also fixes a related defect: a bundled dependency shipping its own nested manifest (e.g. `MyMod/lib/SomeDep/manifest.json`) was yanked to a separate top-level mod folder — a manifest folder nested under another manifest folder is now ignored during structure detection.

## [1.9.1] - 2026-07-28

### Changed
- **Default Nexus auto-check setting set to true** — `autoCheckNexusUpdates` now defaults to `true` (using `UDKey.autoCheckNexusUpdates` in `SettingsView.swift` and `StarHubTHViewModel.swift`), enabling automatic Nexus update checks at startup when an API key is saved.
- **Dot-prefix mod toggle (Mods/.X = disabled)** — toggling a mod no longer moves its folder between `Mods/` and `Mods_disabled/`. Instead, a disabled mod is renamed in place inside `Mods/` with a leading dot (e.g. `Mods/CJBCheats` ↔ `Mods/.CJBCheats`), which SMAPI ignores natively. The toggle is now an atomic same-parent rename (O(1)) instead of a cross-folder move, eliminating the brief UI freeze on large mods. `ModItem.folderName` stays logical (never dotted) so the install registry, profiles, activation timestamps and backups are unchanged.
- **One-way migration on first launch** — on the first launch of this version, any mods in the legacy `Mods_disabled/` folder are moved into `Mods/` as `.X` and `Mods_disabled/` is removed. The install registry, activation timestamps and profiles need **no** migration (they key on the logical folder name, which is unchanged). This is a one-way door: downgrading after this migration loses visibility of disabled mods. A permanent warning surfaces in the log if `Mods_disabled/` is ever recreated (by another tool or a cross-version skip).
- **"Clean disabled mods" now removes `Mods/.*`** — the setting no longer deletes a `Mods_disabled/` folder; it enumerates the top level of `Mods/` and removes every dot-prefixed disabled entry. The no-op and error messages were updated accordingly.
- **Duplicate UniqueID detection scans Mods/ only** — the repairer now detects duplicates between an enabled (`Mods/X`) and a disabled (`Mods/.X`) mod within the same `Mods/` folder, instead of across two folders.
- **Manifest decode cache in the scanner** — `scanMods()` now caches each manifest's decoded JSON keyed by file mtime, so a rescan following a single-mod toggle (which re-stat()s every mod but only one manifest changed) does ~N `stat()` calls and zero JSON decodes instead of N decodes.
- **Instant mod toggle (no rescan)** — toggling a mod previously triggered a full `scanMods()` that re-walks the entire `Mods/` tree (enumerating every file of every mod: ~5 s for ~900 mods) just to reflect one folder's renamed state. The toggle still renames `Mods/X ↔ Mods/.X`, but now flips `isEnabled` in memory and rebuilds the lightweight dependency index instead of rescanning — O(toggled) instead of O(total files). The recursive folder-repair pass is also skipped after a toggle (a rename can't create junk, orphans or X/.X duplicates); it still runs on launch, refresh, install, delete and profile-apply. The index rebuild was extracted into `rebuildDependencyIndexes()` so the full scan and the toggle share it.
- **Faster launch + live scan progress** — the launch scan took ~17 s for large mod collections (~900 mods): the folder-repair pass re-decoded every manifest a second time (via `collectUniqueIds`) on top of the scanner's own decode, and the overlay's progress bar froze at 25 % for the whole "Scanning mods" phase. Duplicate detection now runs O(N) in memory from the already-scanned mods (new `ModFolderRepairer.detectDuplicates(from:)`); `scanMods` calls the repair with `detectDuplicates: false` and computes duplicates after the scan. `_Trash_*` folders are excluded from the top-level scan (quarantined mods no longer appear or pollute duplicate detection) and the unused per-file `isDirectory` prefetch is dropped. While scanning, `scanMods` streams the current mod name + `done/total` (throttled ~12/s) via `scanProgress`, so the overlay refines the bar within the scan slice and shows `NomDuMod (X/N)` instead of freezing.

### Fixed
- **Stale Nexus overview header version reported in updates (e.g. latest version 1 vs 2 on Files tab)** — `fetchModInfo` previously relied solely on the `version` field from `mods/{id}.json`, which can be left outdated by mod authors when uploading new versions (e.g. Mod #49782 showing header version "1" while the Files tab features version "2.0.0"). Fix: `NexusUpdateChecker` now queries `files.json` for the primary Main file (`category_id == 1`), resolving the true latest version of the downloadable file.
- **Mod packs failed to activate / toggle (e.g. Stardew Valley Expanded)** — in `scanEntryForMods`, checking `pathComponents.count > 1` on subfolder relative paths (which are evaluated relative to the top-level folder entry itself, yielding a component count of 1 for 1-level-deep sub-mods) caused multi-mod pack folders to split into individual standalone items instead of grouping under the top-level folder. Toggling any of these sub-mods failed because `performToggle` searched for `Mods/<SubMod>` instead of the actual on-disk folder `Mods/<PackFolder>/<SubMod>`. Fix: pass `topLevelLogicalFolder` to `scanEntryForMods` so all manifests found inside a top-level folder correctly group into a single `isGroup` pack with `folderName` set to the top-level folder.
- **Nexus auto-check was skipped silently at startup** — when `autoCheckNexusUpdates` was disabled or no Nexus API key was set, `checkNexusUpdates` returned silently without feedback. An explicit log message is now recorded explaining why auto-check was skipped (`"Auto-check for Nexus updates skipped (disabled in Settings)"` or `"Auto-check for Nexus updates skipped (no Nexus API key set)"`).
- **Removed invalid server entry in `.mcp.json`** — cleaned up the project `.mcp.json` config file by removing an invalid `github` HTTP server block.
- **Disabled mods couldn't be re-enabled, opened in Finder, or config-edited** — for a top-level disabled mod whose on-disk folder is `.X`, `scanMods()` derived `folderName` from the physical path's last path component, yielding `.X` *with* the dot. Since `ModItem.physicalFolderName = "." + folderName`, every on-disk path then resolved to the non-existent `Mods/..X`: the toggle's `fileExists` guard skipped the rename (so the switch snapped back), "Open in Finder" opened nothing, and the config editor couldn't find `config.json`. Only simple (non-pack) disabled mods were affected — pack children derive `folderName` from a `relativePath` that is already computed against the physical root and never carries the dot. Fix: strip the leading dot when deriving the logical folder name in `parseModFolder`, mirroring the `logicalFolder` stripping `ModFolderRepairer` already did.
- **`build_app.py` failed to compile on macOS 26 / Tahoe** — `swiftc` was invoked directly with no explicit deployment target, so it derived `arm64-apple-macosx26.0` from the SDK and failed with `unable to load standard library for target 'arm64-apple-macosx26.0'`; and even with a pinned target the direct invocation lacked the toolchain env (SDKROOT) that `xcrun` provides. Fix: pin `-target <arch>-apple-macosx14.0` (matching `Package.swift` / `Info.plist`, with host-arch detection so Intel isn't broken) and run swiftc through `xcrun`.

### Added
- **Download spinner on Mod Updates rows** — when a Nexus mod download is in flight (both the Premium in-app download and the free `nxm://` "Mod Manager Download" path), the row's action buttons are replaced by an inline spinner tagged to the specific mod being fetched (`downloadingNexusModId`), instead of just disabling every Premium button. Other rows keep their buttons disabled until the download completes.
- **Mod-list row metadata strip** — each mod row now surfaces a compact metadata line under the category/author/version: shipped i18n language codes (with a green "FR available" badge when `i18n/fr.json` is present), the Nexus last-updated date (relative format), and the local install date (folder modification time). The strip is omitted entirely when none of the values are known.
- **French-translation filter** — a new three-state chip ("Trad. FR" / "FR available" / "No FR") in the Mods toolbar scopes the list to mods that ship (or don't ship) an `i18n/fr.json`. Works with the same AND semantics as the existing config-only and category filters, and resolves packs via their children.

## [1.9.0] - 2026-07-27

### Added
- **Smaller, centered launch splash with hidden menus** — the launch overlay is no longer stretched to fill the entire window. It now renders as a contained card centered on an opaque dark scrim: the cover artwork is capped at 440pt wide (preserving its native 16:9 ratio), with the app name and progress bar stacked below it. Native macOS menus (File / Edit / View / Window / Help) and their keyboard shortcuts are hidden for the duration of the splash via `NSApp.mainMenu = nil`, then restored verbatim once `isLaunching` flips to false — so no Cmd+W / Cmd+R etc. can act on the half-loaded UI. The hide also runs in `onAppear` (not only `onChange`) so the menus are gone from the very first frame.
- **Determinate launch overlay with cover artwork** — the indeterminate spinner shown during cold launch is replaced by a full-window overlay using the project's `nexus_cover_final.png` as background, with the app name at the top and a linear progress bar + localized step label at the bottom. The bar advances through every startup phase so the user sees concrete progress instead of a generic "Loading…":
  1. *Initializing…* (0–5%)
  2. *Loading mod registry…* (5–15%) — warms the in-memory JSON cache
  3. *Scanning mods…* (15–70%) — walks `Mods/` and `Mods_disabled/`, parses every manifest, syncs the registry
  4. *Loading saves…* (70–80%)
  5. *Loading profiles…* (80–90%) — also fetches the Steam user identity and seeds Nexus caches + user overrides
  6. *Ready* (100%)
  The cover image is bundled as a resource by `build_app.py` (no dependency on the source tree at runtime).

### Changed
- **Faster time-to-first-paint** — `StarHubTHViewModel.init()` previously blocked the main thread on ~6 UserDefaults JSON decodes (Nexus updates / categories / extras caches, user overrides) plus a pack-consolidation pass, all before the app window could even appear. All that work now runs on the background launch task (`seedNexusAndUserData`), so the window renders the launch overlay immediately. The Nexus caches, user category overrides, activation timestamps, and profile list are seeded asynchronously and published on the main thread once ready.
- **In-memory cache for the install registry** — `loadInstalledModRegistry` no longer re-decodes the ~100KB JSON blob from UserDefaults on every call. It now memoizes the registry in a thread-safe (NSLock-guarded) instance property, refreshed on every save. Since `effectiveVersion` calls `installedModNexusVersion` once per mod during each scan, this previously triggered 100+ full JSON decodes per scan (~10MB of decode churn). After the fix, the decode runs once per session.
- **Install registry save skips no-op writes** — `syncInstalledModRegistry` now tracks a `didChange` flag and skips the JSON encode + double UserDefaults write when nothing actually changed (the common case of a plain refresh with no install, no delete, no version bump). `saveInstalledModRegistry` also encodes the blob exactly once instead of twice (the primary and backup share the same `Data`).
- **Mod Updates sidebar entry always visible** — the "Mod Updates" item in the sidebar was previously hidden when there were zero pending updates, leaving no way to reach the tab to manually trigger a Nexus check. It is now always visible; the numeric badge is hidden when the count is 0.
- **Sidebar search bar removed** — the search field at the top of the sidebar duplicated nothing useful (the Mods list has its own search) and consumed vertical space. It has been removed along with its `searchText` state and `matchesSearch` helper.
- **Centralized Nexus request builder** — all Nexus API calls now go through a single `NexusRequestBuilder.makeRequest(...)` helper (`StarHubTH/Models/NexusRequestBuilder.swift`), which reads the app version live from the bundle's `CFBundleShortVersionString`. Previously `Application-Version` was hardcoded inconsistently (`"1.0.9"` in `NexusUpdateChecker`, `"1.1.0"` in `NexusDownloader`), making Nexus see two different clients for the same app and producing wrong usage statistics.
- **Centralized UserDefaults keys** — shared keys (`gameDir`, `currentLanguage`, `modProfiles`, `activeProfileId`, `launchProfile`, `closeAfterLaunch`, `chainToggleDependencies`, `installedModRegistry`, `installedModRegistryBackup`) now live in a single public `UDKey` enum (`StarHubTH/UDKey.swift`), replacing 16 raw-string literals across 5 files. Typos are now compile-time errors instead of silent cross-key writes.
- **Shared Nexus UpdateKeys parser** — the `nexus:<id>[@variant]` parsing convention (used to resolve a mod's Nexus id) is centralized in `ModManifest.parseNexusId(fromUpdateKeys:)` (public static). Previously duplicated inline in `StarHubTHViewModel.parseModFolder` and `ModManifest.init`.
- **`LANG=C` enforced on child Processes** — `Process()` invocations that parse text output (notably `/usr/bin/unzip -l` in `ModZipInstaller.uncompressedSize`) now set `LANG=C` / `LC_ALL=C` via a shared `cLocaleEnvironment`. Without this, a non-English user locale would translate the summary line ("3 files" → "3 fichiers") and silently disable the zip-bomb size guard when parsing failed.
- **`[weak self]` on background closures** — four `DispatchQueue.global().async` closures in `StarHubTHViewModel` (`refresh`, `performInitialLoad`, `loadSmapiLog`, `reloadSaves`) now capture `self` weakly, matching the convention already applied to the other 11 sites. Prevents future retain cycles if the VM ever stops being an app-lifetime singleton.
- **No `.allowFragments` when a dict is expected** — manifest.json parsers (`ModZipInstaller.scanFolder`, `ModInstallBackupManager.extractModMetadata`, `ModFolderRepairer.collectUniqueIds`) no longer pass `.allowFragments`, which was redundant (the subsequent `as? [String: Any]` would have failed on a non-object fragment anyway) and masked genuinely corrupt files. `.json5Allowed` is preserved where relevant; `.fragmentsAllowed` is kept on Nexus API responses because mod descriptions embed raw control chars.

### Fixed
- **Nexus UpdateKeys with leading whitespace silently dropped** — `parseNexusId` now trims the key *before* the `hasPrefix("nexus:")` check, so values like `"  Nexus:240"` (previously rejected) resolve correctly. Latent bug in both pre-refactor call sites, surfaced by the new `ParseNexusIdTests` suite.
- **Force-unwrapped `as!` in `CodeEditorView`** — the `scrollView.documentView as! NSTextView` casts in `makeNSView` and `updateNSView` are replaced with defensive `guard let ... as?` so a future AppKit change degrades gracefully instead of crashing.

### Fixed
- **Mods re-flagged as updatable after a non-Nexus install** — when a mod was installed/updated by drag-and-drop, manual folder copy, or any path other than the in-app Nexus download, the install registry never recorded the Nexus version (only the in-app flow called `reconcileManifestVersion`). Mods whose author forgot to bump the manifest Version were therefore permanently re-flagged as updatable, because the update checker kept comparing the stale manifest version against the live Nexus version. The registry is now populated for ALL install paths: `syncInstalledModRegistry` reads the Nexus version from the cached `nexusModExtras` map (keyed by Nexus mod id) on every scan, regardless of how the mod landed on disk.
- **`nexusVersion` lost on update** — when `syncInstalledModRegistry` detected a version change (re-install/update), it rebuilt the `InstalledModRecord` without carrying over the previously reconciled `nexusVersion`, silently dropping it back to `nil` and re-introducing the false-positive flag on the next check. The record now preserves (or refreshes) the known Nexus version across updates.
- **`recordInstalledModNexusVersion` no-op when entry missing** — the function silently returned if the folder wasn't yet in the registry, which could happen when it was called right after an install but before the first scan completed. It now creates the entry instead of bailing.

### Added
- **`NexusRequestBuilder`** — single source of truth for Nexus API URL request construction (`apiBase`, `gameDomain`, `appName`, `appVersion` from bundle, `userAgent`).
- **`UDKey`** — centralized `UserDefaults` keys (public enum).
- **`ParseNexusIdTests`** — 6 new unit tests locking the contract of `ModManifest.parseNexusId(fromUpdateKeys:)` (plain key, case/whitespace tolerance, `@variant` suffix, multi-key selection, zero/negative rejection, nil/empty input).
- **Nexus auto-check toggle in Settings** — a new `Auto-check Nexus updates at startup` toggle lives under the Nexus Mods settings section. When enabled **and** a Nexus API key is stored, the app automatically triggers `checkNexusUpdates(force:)` right after the launch overlay dismisses. The toggle is persisted via `UDKey.autoCheckNexusUpdates` / `L10n.Settings.nexusAutoCheck` with matching `en.json` and `fr.json` strings.

### Changed
- **Splash image enlarged to 640×360** — the launch card's cover artwork now uses a larger contained frame while preserving its native 16:9 aspect ratio (`nexus_cover_final.png` is 1672×941). The progress bar width stays at 400pt, keeping the card visually balanced.
- **Navigation buttons hidden when unused** — the back/forward toolbar buttons are now hidden (`opacity = 0`, animated) when there is no navigation history or forward stack, instead of only being disabled. This removes dead UI chrome from the first frame and from any tab with no history.

## [1.8.0] - 2026-07-26

### Added
- **Automatic mod folder repair** — a new `ModFolderRepairer` runs before every scan, quarantining OS junk files (`.DS_Store`, `__MACOSX`, `._*`, `Thumbs.db`), empty folders, and orphan folders without any `manifest.json` into a timestamped `_Trash_<datetime>/` folder inside the game directory. Nothing is ever deleted; the user can inspect or restore quarantined items manually.
- **Duplicate UniqueID detection** — the repairer detects mods that exist in both `Mods/` and `Mods_disabled/` under the same UniqueID and reports them without auto-resolving (surfaced in a new Quarantine tab).
- **Quarantine tab** — a new sidebar section provides access to the last repair report, an "Open Quarantine Folder" button, and an "Empty to Mac Trash" action that moves all `_Trash_*` folders to the Mac Trash via `NSWorkspace.recycle` with a confirmation dialog.
- **SMAPI error logging** — SMAPI errors detected by `parseSMAPILog()` are now journaled to the app log (level `.warning`). The Journaux tab is now visible to all users and serves as the persistent consultable record of system alerts.
- **Content-diffing for SMAPI error journaling** — the VM tracks the last-logged error set, so only genuinely new alerts are appended to the log across re-parses (no duplicate re-logging when counts fluctuate).
- **Launch spinner overlay** — a full-window `ProgressView` overlay (with localized caption) is shown during the initial mod scan + profile load (`vm.isLaunching`), giving immediate feedback on cold launch instead of a blank window. The scan runs off-main-thread via `performInitialLoad()` and flips the flag once `mods` is published.
- **Per-row spinners for destructive operations** — mod deletion, backup restore/delete, and profile activation now show an inline `ProgressView` on the affected row instead of leaving the UI silent during the (potentially slow) folder operation:
  - **Mod deletion** (`ModListView`): the trash button is replaced by a spinner while `vm.pendingDeleteFolder` matches the row; other delete buttons are disabled concurrently.
  - **Backup restore/delete** (`ModInstallBackupsView`): the global `isBusy` bool is replaced by `busyBackupId: UUID?`, showing a spinner on the in-flight row and disabling the rest.
  - **Profile activation** (`ModProfilesView`): the Activate button collapses to a spinner while `vm.applyingProfileId` matches the row's profile.
- **Profile activation error reporting** — when a profile application has problems (move failures and/or missing mods), the alert now names the affected mods (capped to 8 with a "+N" suffix). Each move failure is logged individually with a localized structured message, and profile entries referencing uninstalled mods are detected and reported as "missing" — instead of being silently skipped.
- **Persistent install-date registry** — a new JSON registry (`installedModRegistry`) records the version and install timestamp of every mod on disk, replacing the unreliable on-disk folder mtime for same-version update detection. The registry is synchronized at the end of every scan (`syncInstalledModRegistry`), so mods added by any means — app installer, drag-and-drop, or manual copy into `Mods/` / `Mods_disabled/` — are automatically tracked. Entries for deleted folders are pruned. When a mod's version changes (update/overwrite), its record is stamped with the current time. The registry is backed by a redundant copy (`installedModRegistryBackup`): if the primary blob is corrupt or missing, it is transparently restored from the backup; if both are unavailable, the registry is fully rebuilt from disk on the next scan and the event is logged.

### Changed
- **Sticky mods header & pagination** (`ModListView`) — the toolbar (scope picker, filters, sort) and the pagination footer are now fixed above and below a scrollable list, mirroring `LogsView`'s layout. Previously the entire view (toolbar + list + pagination) scrolled together.
- **Sidebar reorganized** — the bulky 48px account badge is replaced by a compact `AccountHeaderCard` (macOS System Settings style) that consolidates the user identity, active profile, and key metadata (mods active/total + SMAPI status) into a single card. The floating `SystemStatusFooter` (redundant with the card) is removed. The Logs entry moves into the System section (was floating without a header), and the duplicate Quarantine entry is removed (the conditional badge at the top of the sidebar suffices).
- **Sidebar badge items separated** — "Mod Updates" (Nexus updates + out-of-date mods) and "System Alerts" (SMAPI errors) are now distinct sidebar items with their own accent colors (blue and orange) and dedicated views. The Quarantine item appears only when items have been moved.
- **UpdatesView simplified** — the SMAPI errors section has been moved to its own `SystemAlertsView` with a "View Logs" shortcut to the Journaux tab.
- **Overwrite install preserves nested pack-child location** — when overwriting a mod installed inside a pack group folder (e.g. `PackName/ChildMod`), the installer now preserves the full nested `folderName` instead of dropping the child to top-level.
- **`showDeveloperLogs` AppStorage removed from MainView** — the Logs tab is always visible; the dead `@AppStorage` property on `MainView` was unused and removed.
- **Sidebar labels clarified** — "Mods" → "Gestion des mods" and "Mod Backup Management" / "Gestion des sauvegardes de mods" → "Sauvegardes des mods" (EN: "Mod Management" / "Mod Backups"), for clearer navigation labels matching their content.

### Fixed
- **Same-version mods re-flagged as updatable after install** — `FileManager.copyItem` preserves the source folder's mtime (the modder's packaging date, not the install date), so the update checker's same-version detection (`nexusUpload > folderMtime`) always saw a stale date and re-listed the mod on every check. The install date is now sourced from the persistent `installedModRegistry` (stamped with `Date()` on every install/update), with the folder mtime used only as a fallback for pre-existing mods. The installer also touches the installed folder's mtime to `now` as an additional safety net.
- **Backup/restore now handles nested pack-child paths** — `ModInstallBackupManager.createBackup`, `restoreBackup`, and `registerSetAsideFolderAsBackup` correctly create intermediate parent directories for nested folder names like `PackName/ChildMod`.
- **Install tolerates corrupted missing existing mods** — `ModZipInstaller.install()` catches `.modNotFound` during backup as non-fatal when the existing folder is already gone from disk.
- **Temp file leaks in install** — config snapshot files now have a `defer` cleanup that runs regardless of whether the install completes or fails mid-way.
- **Temp extract dir leak on install failure** — `ModInstallView` now calls `cleanupTempDir` on the error path as well as the success path.
- **Background-thread mutation of `@Published` properties** — the `lastRepairReport` from `ModFolderRepairer` is captured on the background scan thread and published on the main queue alongside `self.mods`.
- **Manifest parsing parity for JSON5** — `ModFolderRepairer.collectUniqueIds` now matches the scanner's reading options (`.json5Allowed` on macOS 12+), so JSON5 manifests are not silently skipped by duplicate detection.
- **Dead localization keys** — `quarantine_empty` and `logs_system_alerts_section` (unused) were pruned to maintain the 590-key parity contract between `en.json` and `fr.json`.
- **Multi-mod pack false-positive updates** — `NexusUpdateChecker` de-duplication now keeps the candidate with the highest version per Nexus mod id, instead of the first alphabetically-encountered child. Multi-mod packs (e.g. Swim Mod) that share a Nexus id via `@variant` UpdateKeys no longer permanently flag a false-positive update because a lower-versioned child was selected.
- **Stale manifest versions no longer cause false updates** — `parseModFolder` now resolves an `effectiveVersion` from the registry's recorded Nexus version when it is newer than the manifest's `Version`. Authors who forget to bump the manifest no longer cause permanent re-flagging, and the manifest.json is never rewritten.
- **Registry stores Nexus version instead of patching manifest** — `reconcileManifestVersion` now records the Nexus version in the `installedModRegistry` rather than surgically editing the user's manifest.json. This removes fragility and unexpected disk writes while achieving the same anti-re-flagging behavior.
- **Registry uses install time instead of folder mtime** — `syncInstalledModRegistry` now stamps new entries with `Date()` rather than the folder's modification date, which `FileManager.copyItem` preserves from the modder's archive packaging and would otherwise trigger a spurious same-version update.
- **One-shot registry migration** — a `registryMigrationV2Done` flag wipes and rebuilds the install registry on first launch after this fix, so existing stale mtime-based entries are replaced with clean `Date()` timestamps and the false-positive cycle is broken exactly once.

## [1.7.1] - 2026-07-25

### Added
- **Config & translation preservation on update** — when updating an installed mod (overwrite + backup), the installer now preserves not only `config.json` and `fr.json` but every supported SMAPI language file (`default.json`, `en.json`, `de.json`, `es.json`, `fr.json`, `hu.json`, `id.json`, `it.json`, `ja.json`, `ko.json`, `pl.json`, `pt.json`, `ru.json`, `th.json`, `tr.json`, `uk.json`, `zh.json`) via the shared `ModConfigFiles.preservable` list. The full mod folder is still backed up before overwrite.
- **Dependency sorting & filter toggle in install preview** — dependencies are now sorted by priority (missing/disabled required → missing/disabled optional → satisfied), and a toggle switches between "problems only" (default) and "show all". A pack with many dependencies no longer buries the critical missing ones.
- **Nexus search menu on missing dependencies** — the install preview's missing-dependency rows now offer the same name/author search menu (by mod name via `?gsearch=`, by author via `/games/stardewvalley/mods?author=`) used elsewhere, replacing the old generic `?terms=` link.
- **Resizable install preview sheet** — the popup is now scrollable as a whole and capped to a reasonable height, so packs with many mods/dependencies/conflicts no longer push the action buttons off screen.
- **RAR archive support** — `.rar` mods are now accepted (drag-and-drop, file picker, and validation). Extraction uses the first available of `unrar`, `unar`, or `7z` (checked at runtime in Homebrew/standard PATH). If none is installed, a clear error message prompts `brew install unrar`.
- **Multi-mod pack with wrapper folder detection** — a zip like `Parchment/` containing `Parchment/` + `[CP] Parchment Example Pack/` (multiple mods under a shared wrapper folder) is now correctly classified as a multi-mod pack. Previously only one mod was scanned and the rest silently dropped.
- **Pack-group conflict detection** — updates of mods installed as part of a multi-mod pack group (whose headers have an empty `uniqueId`) are now correctly detected as conflicts, offering backup/overwrite.

### Changed
- **Nexus missing-dependency search** — clicking a missing dependency now opens a menu offering two distinct searches: by mod name (readable split-camelCase, e.g. `Content Patcher`) or by author (e.g. `Pathoschild`). The author search uses the dedicated Nexus filter (`/games/stardewvalley/mods?author=`) for precise results, and is applied consistently in both the mod list and the dependency tree in the detail pane.
- **Mod list search reverted to real-time** — the 200 ms debounce introduced in 1.7.0 caused perceived input lag; restored the instant real-time filtering of 1.6.0 (the precomputed dependency index keeps per-keystroke cost negligible).
- **Deprecated `onChange(of:perform:)` migrated** — all 8 occurrences across `ModListView`, `LogsView`, `MainView`, and `ModConfigEditorView` now use the macOS 14+ two-parameter `onChange(of:initial:_:)` API, removing all deprecation warnings.

## [1.7.0] - 2026-07-25

### Added
- **Design token system** — introduced `AppDesignCore` (SPM-testable pure tokens) and `AppDesignUI` (SwiftUI fonts/colors) to eliminate magic numbers across the UI. All spacing, radius, and opacity values now go through `AppDesign.Spacing/Radius/Opacity`.
- **Design system tests** — 10 tests in the new `StarHubTHCore` target verifying token values and migration correctness.
- **Accessibility infrastructure** — added `ContrastChecker` (WCAG 2.1 compliant luminance utility in SPM for testability) and 7 new `ContrastCheckerTests`.
- **System status footer** — new compact sidebar bar showing enabled mod count, pending updates, and SMAPI error count at a glance.
- **Empty-state drop zone** — when no mods are installed, the list shows a large visual drop zone rather than plain text.
- **Cached async image loader** — `CachedAsyncImage` replaces the system `AsyncImage` in the mod detail pane, caching fetched mod pictures in `NSCache` to avoid redundant downloads.

### Changed
- **Accessibility labels added** — 17 total `accessibilityLabel`/`Value`/`Hint` calls across `ModListRow`, icon-only buttons, sidebar nav, search bar, `SystemStatusFooter`, and `EmptyStateDropZone` so VoiceOver announces the full UI in French or English.
- **Nexus dependency search aligned** — missing-dependency buttons now use the same `…/search/?gsearch=` format as the dependency tree and present human-readable terms (`Content Patcher` instead of `Pathoschild.ContentPatcher`).
- **LazyVStack reverted in ModSectionGroup** — pagination already caps rows at 15, so `LazyVStack`'s benefit is marginal; switched back to deterministic `VStack`.
- **EmptyStateDropZone hover fill semantics** — `.overlay` replaced by `.background` since the hover tint is a fill behind the content, not on top.
- **Nexus tooltip fixed** — the `info.circle` button on each row now correctly opens the mod details sheet (was pointing to the wrong action).
- **Localized accessibility strings** — all VoiceOver strings now go through `L10n` (e.g. `main_system_status_a11y`), removing hardcoded English accessibility copy.

### Fixed
- **Toggle spinner while enabling/disabling mods** — replaced an `alert(isPresented:)` that showed on every toggle with an inline `ProgressView` tied to `pendingToggleFolder`.
- **Dead code warning for `InstallationError`** — the typed enum was never instantiated; confirmed removed from `Package.swift` and its phantom L10n keys were pruned.

## [1.6.0] - 2026-07-25

### Added
- **Home page banner**: the home page now leads with a full-width Nexus banner, with the **Steam avatar floating on the banner** (overlapping its bottom edge over a solid disc so it reads as one cohesive hero), followed by the username and version — replacing the standalone centered avatar.
- **README banner**: the README is now headed by the banner image, above the badges row.

### Changed
- **Richer mod / pack detail pane**: the detail pane now leads with a **fixed hero** — a full-width illustration banner plus a metadata band showing the mod/pack **name**, its **category tag** (Nexus category or the inferred type), version/author, Nexus & bug-report links, and metadata stacked on the right: **last Nexus update**, **install date**, and the mod's **languages** (detected from its `i18n/` folder, recursing subfolders, with `default.json` counted as English). The **Description / Changelog / Dependencies** tabs stay pinned under the hero while their content scrolls; a **pack now lists its contents** (each child mod + enabled state + version) inside the Description tab, alongside the category and Nexus-id editors.
- **Mod packs now show their latest Nexus version** in the mod list: a pack is a single Nexus mod installed as several sub-mods, whose own manifest versions can differ or lag, so the list previously showed a shared child version or "—". It now displays the pack's latest Nexus version (the Main file / changelog version) once an update check (or a per-mod fetch) has retrieved it.

## [1.5.0] - 2026-07-25

### Changed
- **French is now the default language**: the app launches in French regardless of the system locale (an existing saved language choice is still respected); English is used only when explicitly selected.
- **Language & theme switchers moved to the sidebar**: language (🇫🇷 / 🇬🇧) is now a flag toggle pinned bottom-right of the sidebar, and the app theme (System / Light / Dark) an icon toggle bottom-left — one-click access, both re-localize / re-theme the UI live. The corresponding pickers were removed from Settings (its remaining "Developer" section keeps the developer-logs toggle).

## [1.4.0] - 2026-07-25

### Added
- **Default mod profile on first run**: a fresh install now automatically gets a "Default" profile capturing the current mod setup, so there is always an active profile to work from. It is created once (never re-created if you delete your other profiles) and **cannot be deleted**.
- **Active-profile indicator on the Mods page**: the mod list's filter row now shows which profile is currently applied (a read-only accent chip), so you always know the context you're editing in.
- **Install Backups moved to its own sidebar section**: the automatic pre-install / pre-update / pre-restore backups now have a dedicated **Install Backups** sidebar entry (a redesigned `ModInstallBackupsView`) — card-style rows with a reason badge, a backup count, icon-only restore/delete buttons, and a clearer empty state — instead of being reachable only from a button inside the install sheet. The view also spells out the **backup retention policy** (kept up to 30 days, plus the most recent backup per calendar month for longer history, always keeping at least the 5 most recent).

### Changed
- **Mod Profiles page redesigned**: profile actions now live directly on each row instead of behind an info-button detail sheet. Each row shows its **mod count** and a clear **"Active" badge**; an **Activate** button switches to a profile, **Manage mods** applies it and jumps to the Mods page to edit it (replacing the redundant in-sheet mod checklist that duplicated the main mod manager), and a **⋯ menu** (also right-click) offers **Rename** and **Delete**.
- **Safer profile activation**: the profile row is no longer one big tap target that silently switched profiles (which moves mod folders on disk) — switching now requires an explicit button. Activation is **serialized** (the Activate/Manage buttons disable while another profile is still being applied) and **exclusive** (only one profile active at a time). Deleting a profile now asks for confirmation.
- **Mod install window polish**: the install sheet gained a close (✕) button, and its drop zone is now **clickable to browse** for a `.zip` (in addition to drag-and-drop); the redundant "Manage Backups" button was removed from its header.
- **Sidebar reorganized**: the **Thai Translation Hub is now hidden by default** (behind a toggle) to declutter the bilingual app, game-related items were reordered (Profiles before Saves), and several sidebar labels were clarified ("Saves" → "Game Saves", "Config Backups" → "Configuration Backups", "Manage Backups" → "Mod Backup Management").

### Fixed
- **Profile data loss**: applying a profile no longer sweeps mods that have no manifest `UniqueID` into `Mods_disabled`. Profiles key on `UniqueID`, so such mods could never be "covered" and were silently disabled on every profile switch — they are now left untouched.
- Removed a dead "Help" button on the profile detail (its click did nothing).

## [1.3.0] - 2026-07-24

### Changed
- **Mod list toolbar redesign**: the flat single-row toolbar is split into a **two-tier layout** for clearer visual hierarchy — the scope segmented picker (All / Enabled / Disabled / Issues) and primary actions (bulk toggle, install button) sit on the top row, while secondary filters (sort, config-only toggle, category picker) are grouped below with visual dividers so they read as a single "refine the list" unit.
- **Pagination redesign**: the clunky text-field "go to page" input is replaced by **numbered page buttons** with smart ellipsis logic (first, last, current, and neighbors shown; gaps collapsed with "…"). The current page is highlighted in accent color. Removed the now-dead `pageJumpDraft` state and `commitPageJump()` helper.
- **Mod list row UX overhaul** (`ModListView`): each mod row now carries a colored **status accent bar** on its left edge (green = enabled, muted = disabled) for instant at-a-glance scanning, and disabled mods are **visually dimmed** (content opacity reduced to ~72%, name in secondary color, inline status dot) so active mods naturally draw the eye first. The toggle's tint changed from blue to green to match the new accent, and **hover** now shows a tinted fill with a subtle accent focus ring instead of a flat gray wash.
- **Version badges**: mod versions are now displayed in a compact monospaced pill (`VersionBadge`) instead of bare text, making them stand out as distinct scannable units in the metadata row.
- **Dependency warnings restyled**: missing/disabled-dependency warnings now appear in a tinted red box with a border, and disabled dependencies are shown in **orange** (vs. red for missing) for clearer severity distinction.
- **Link cursor fix** (`ViewExtensions`): `.pointingHandCursor()` now uses `onContinuousHover` instead of `onHover`, so the pointing hand correctly persists over links inside `.textSelection(.enabled)` description text (the hosted NSTextView was re-asserting the I-beam cursor on every mouse move).

## [1.2.0] - 2026-07-24

### Added
- **Bulk enable/disable all mods**: a power-button menu in the mods toolbar lets you enable or disable every installed mod at once, with a confirmation dialog.
  - A **full-screen progress overlay** (determinate progress bar + done/total counter) blocks the list during the operation, keeping the UI responsive by running all file moves on a background queue.
  - **Lossless moves**: each move uses a stale-duplicate-aside safety pattern — if a move fails, the destination is restored, so no mod can ever end up lost from both `Mods/` and `Mods_disabled/`. Individual toggles are blocked during the operation to prevent concurrent folder races.
- **Delete mod / mod pack**: a trash button on every mod row (and a context-menu entry) permanently deletes a mod from disk after a per-row confirmation dialog. Packs show a dedicated message clarifying that all child mods are deleted together. Fails with a user-visible alert if the folder can't be removed.
- **Rich mod detail pane**: the small mod-info popover is replaced by an inline detail pane (in the detail column, reached from the mod's info button) with **Description / Changelog / Dependencies** tabs.
  - **Rich description rendering**: the full Nexus description is rendered as native text — BBCode/HTML converted to **bold**/italic/lists/links (with a pointing-hand cursor on links), inline images shown at their **native size** (never upscaled/blurred), collapsible **spoilers** (which now render their own images and formatting), and `[hr]`/`[line]` shown as real dividers. The parser strips *every* stray/unknown tag (not just a whitelist) so no raw BBCode leaks onto the screen, collapses large blank-line runs, and drops meaningless empty/punctuation-only emphasis.
  - **Complete changelog**: pulled from Nexus's dedicated all-versions changelog endpoint (not a single file's changelog), newest version first.
  - **Fast & offline-aware**: raw description/changelog are file-cached and shown instantly on reopen, then refreshed in the background; offline (or no API key) falls back to the local manifest description. Mod **packs** resolve to their first child with a Nexus id so the pane still shows content.
  - The **category override editor** and a **Nexus mod-id editor** (with on-save metadata fetch) moved from the old popover into the pane's settings section.
- **Transitive dependency tree** (mod detail pane, Dependencies tab): the flat dependency list is replaced by an interactive, indented tree showing dependencies-of-dependencies (cycle-safe), with each entry resolved to its installed mod's name/author and a three-state status (enabled / installed-but-disabled / missing). Per-row actions: **Enable** a disabled dependency, open an installed one on **Nexus**, or **Search Nexus** for a missing one; clicking an installed row opens that mod's own detail pane. Content packs now resolve their framework dependency correctly (the manifest's `ContentPackFor` is read alongside `Dependencies`), which also sharpens the Issues filter.
- **Offline mod type tags**: each mod is auto-classified into a type (UI, Framework, Content Patcher, Translation, Cosmetic, NPC, Audio, Map, Gameplay, …) inferred from its manifest — shown as a badge and filterable. Used as an **offline fallback** for the category filter: mods with no Nexus category are now grouped under their inferred type instead of a single "uncategorized" bucket. Ported from upstream, localized (en/th/fr).
- **Launch Game button** (Home page): starts Stardew Valley directly from StarHubFR using the launch profile configured in Settings (SMAPI or Vanilla), with the active profile shown beneath the button — wiring up launch logic that previously existed in the code but was never reachable from the UI.
  - Install-type aware: Steam installs launch through Steam (`steam://run/413150`), while direct/GOG installs run SMAPI's in-place launcher (`StardewValley`) directly. Previously the launch always routed through Steam whenever Steam was installed at all, which hijacked direct/GOG launches (Steam opened but the game never started).
- **Mod Config Editor** (`ModConfigEditorView` / `CodeEditorView`): Edit a mod's `config.json` directly from the app, opened via the "Code Editor" entry in a mod's context menu.
  - Hierarchical **visual editor**: settings are parsed into a searchable tree of typed rows (boolean, string, number), grouped by their nesting path, with an inline search bar to filter by key.
  - **Raw JSON editor** tab: a line-numbered, monospaced code editor (`CodeEditorView`, an `NSViewRepresentable` text view) for direct JSON editing, with live validation and an invalid-JSON warning.
  - **Reset** button (revert unsaved edits) and **Restore Config** button (roll back to a local `config.json.bak`, or pick another `.json` file to restore from), independent of the existing `ModConfigBackupManager` history reachable from the "ConfigBackups" tab.
- **In-App Changelog Viewer** (`AppChangelogView`): New sidebar entry rendering this `CHANGELOG.md` inside the app itself (lightweight Markdown: headings, bullets, inline emphasis), bundled into the app resources at build time.
- **Mod List Toolbar Rework**: the Install button moved from its own row to the right end of the filter row and renamed "Install mods"; the sort menu gained Name (Z-A), Author, and Version options (its button icon is now fixed instead of changing per selection); a new "With Config" filter scopes the list to mods (or packs with a qualifying child) that have a `config.json`; each configurable mod's row now shows a gear icon opening the config editor directly, matching upstream's discoverability while keeping the existing right-click "Code Editor" entry as a second access point.
- **Full French Localization** (`assets/fr.json`, 496 strings): French added as a third supported app language (alongside English and Thai), selectable in Settings and prioritized as the default for French-locale systems — matching this fork's own name (StarHubFR).
- App renamed to **StarHubFR** in the version string shown on the Home page.
- App Info's Developer row now credits **mrbabilo** for this fork's development, alongside **AppleBoiy** for the original app.
- **In-App Nexus Downloads** (on the **Mod Updates** page — the mod-update panel, previously mislabelled "Software Update"): Download mods directly from StarHubFR, complementing (never replacing) manual drag-and-drop install. Both paths feed the existing install pipeline (`ModZipInstaller`), which shows the conflict preview before installing:
  - **Premium update** — an in-app button that fetches the file directly (requires a Nexus Premium account for a direct download link; a clear message points free users to the Nexus path otherwise).
  - **Nexus update** — opens the mod's **Files** tab on Nexus, where the free green "Mod Manager Download" button hands the app an `nxm://` link; the app downloads the file and opens the install preview. The app now uses a single `Window`, so repeated `nxm://` links always route into the existing window instead of stacking new ones.
  - The **Mod Updates** list drops a mod as soon as you install its update (and won't re-list it on next launch), and orders mods most-recently-updated first.
- **Manifest version auto-correction**: after installing a mod update downloaded from Nexus (premium button or free `nxm://`), StarHubFR reconciles the installed `manifest.json` so the mod stops showing a phantom "update available". If the author forgot to bump the `Version`, it is surgically corrected to the mod's Nexus version — the exact version the update checker flags on, so the mod actually clears (only the `Version` value changes — comments/formatting preserved; never downgrades). For a same-version minor update (version unchanged but the Nexus upload is newer), it instead refreshes the mod's modification date so the update checker stops flagging it. Abstains on structured-dict version forms and multi-mod packs.

### Changed
- **App renamed to StarHubFR**: the app now identifies as **StarHubFR** to macOS — Dock, menu bar, Finder, and window title (`CFBundleName`/`CFBundleDisplayName`), and the built bundle and executable are now `StarHubFR.app` / `StarHubFR`. Only the bundle identifier (`com.appleboiy.StarHubTH`) is kept unchanged, to preserve access to the Keychain-stored Nexus API key and existing user preferences.
- **Settings Layout**: the Nexus Mods API key section moved from the bottom of Settings to right after the language picker; its footer now explains that the key is stored in the macOS Keychain, encrypted by the system, and never saved in plain text.
- **Mod Config Backup Manager**: now backs up every language/translation file a mod ships (en/de/es/fr/hu/id/it/ja/ko/pl/pt/ru/th/tr/uk/zh + `default.json`), not just `fr.json` — a backup now captures a mod's full set of localized overrides.
- **Automated test coverage** expanded across `SaveManager` (backup/restore/duplicate/branch folder operations), `ModConfigBackupManager`, and `ModInstallBackupManager` (created/restore/delete/cleanup-retention paths), using Swift Testing against a dedicated SPM package (`Package.swift`) — including a same-second backup-folder-name collision fix and a `listBackups` parsing fix uncovered while writing the new coverage.

### Removed
- **Thai UI language**: Thai is no longer a selectable app language — its translations (`assets/th.json` / `th.lproj`) and the Thai README (`README_TH.md`) were removed, leaving the app **bilingual (English / French)**. The **Thai Translation Hub** (browsing/tracking Thai translation mods) is unchanged. Existing users set to Thai fall back to French (French-locale systems) or English.

### Fixed
- **SMAPI Installer — installation was completely broken.** Two compounding issues, both root-caused against SMAPI's actual current distribution:
  - The hardcoded download endpoint (`smapi.io/get/latest`) no longer exists (confirmed: bare HTTP 404, no redirect). Fixed by resolving the current release dynamically through the GitHub Releases API instead, so this can't go stale again on future SMAPI versions.
  - Even after the download was fixed, installation still failed: SMAPI's packaging changed from a flat `internal/mac/payload` folder (which this app used to copy file-by-file) to a real installer program (`internal/macOS/SMAPI.Installer`) that decides internally which files go where and under what names — not something recoverable from the zip's structure alone. `install()`/`uninstall()` now run this official installer directly (non-interactively, via its stdin prompts) instead of reimplementing its file placement by hand. This also fixes `uninstall()` leaving orphaned `StardewModdingAPI*` files behind, which the old manual/local removal never accounted for.
- **SMAPI Installed Version Display**: `getInstalledVersion()` relied on `smapi-internal/manifest.json`, which no longer exists in SMAPI's current packaging, so the version shown right after installing stayed a generic "Installed" with no number until the game had been launched once. `install()` now records the exact release tag it downloaded, and the version display reads that back first.
- **Mod List Pagination**: toggling the new "With Config" filter didn't reset the current page, unlike every other filter — could leave the pagination footer's prev/next buttons in a stale state until the next navigation.

## [1.1.0] - 2026-07-22

### Added
- **Mod Zip Installer** (`ModZipInstaller` / `ZipModInfo`): Install mods by drag-and-dropping `.zip` files directly into the app. Heuristic multi-level structure detection: single folder with `manifest.json` → base folder; multiple folders with `manifest.json` → multi-mod pack; `manifest.json` at root → base = root.
  - Integrity validation: `.zip` extension + ZIP file signature (`PK\x03\x04`) + size limit (< 500 MB) + zip-bomb detection via `unzip -l` uncompressed-size check before extraction.
  - Dependency handling: scans dependencies via `manifest.json`, flags missing ones, suggests enabling installed-but-disabled mods, lists missing mods with Nexus links.
  - Config protection: never overwrites existing mods' `config.json` or `fr.json` (conflict reported instead).
  - Temporary extraction into `/tmp/StarHubTH_<timestamp>/` with conflict preview, then atomic move to `Mods_disabled` after user validation for full rollback.
  - Active-mod update preservation: when updating an already-enabled mod (in `Mods/`), the new version installs directly into `Mods/` to preserve enabled state; disabled or new mods always go to `Mods_disabled/`.
- **Mod Install Backup Manager** (`ModInstallBackupManager`): Automatic backup before overwriting an existing mod installation. Hybrid 3-tier retention: (1) 5 most recent always kept, (2) all backups ≤ 30 days kept, (3) beyond 30 days the most recent per calendar month kept.
- **Mod Config Backup Manager** (`ModConfigBackupManager`): Backup and restore `config.json`/`fr.json` files for enabled mods.
  - New dedicated error case (`.nothingToBackUp`) distinguishing "no enabled mods" from "mods exist but have no config files" — the empty backup folder is removed instead of creating a zero-content entry.
  - `createDirectory` failures are now propagated instead of silently swallowed.
  - Auto-cleanup removes index entries only after confirmed file deletion on disk.
  - Locking around on-disk JSON index prevents lost updates from concurrent create/restore/delete/cleanup calls.
  - Fixed nested folder path flattening for single-mod "pack" folders.
- **Nexus Mods Update Checker** (`NexusUpdateChecker`): Manual check for mod updates via Nexus Mods API (button-triggered, never automatic).
  - API key stored per-user in macOS Keychain (shared/embedded keys banned by Nexus).
  - Update detection: version strictly higher, OR same version but Nexus upload date more recent than local `installedFileDate` (folder modification date).
  - Bounded concurrency (6 parallel requests via `DispatchSemaphore` + `DispatchGroup`) with immediate abort on HTTP 429.
  - Category names (`category_2..27`) now localized instead of silently falling back to English.
- **Nexus Category Mapping** (`NexusCategory`): Full mapping of 26 Nexus Mods categories with localized names.
- **Install Preview View** (`InstallPreview`): Conflict preview screen showing existing vs. incoming files before installation.
- **Mod Install/Config Backups Views**: Dedicated UI for browsing and restoring installation and configuration backups.
- **Complete Localization**: Added 138 missing translation keys across English and Thai (100% key parity, 480 total keys) so every UI label resolves to real text instead of the raw key.
- **French Documentation**: Introduced `README.md` in French as the default project README, with cross-references to Thai (`README_TH.md`) and English (`README_EN.md`) versions.

### Changed
- **SMAPI Installer**: Refactored `install` and `uninstall` to run asynchronously on a background queue (`DispatchQueue.global(qos: .userInitiated)`) with staged progress updates (20% → 60% → 100%) so the caller is no longer blocked.
- **Mod List View**: Major rebuild (`+1135` lines) with category filter menu, pagination (15/page with direct page jump), uncategorized mod filter, mod activation order sorting, and mod description image support.
- **Main Thread Safety**: `fetchSteamUser`, `editSave`, `saveInventory`, and `zipToDesktop` (Settings backup buttons) now perform file I/O off the main thread instead of blocking the UI.
- **Dependency Cascade**: `applyChainToSet`'s disable cascade now only walks through currently-enabled mods, matching `toggleMod`'s equivalent BFS.
- **Save Manager**: Refactored (`+265`/`-` lines) with improved save branching and XML manipulation safety.
- **Thai Translation Hub**: Refactored view for cleaner download logic using GitHub Releases with normalized zip name comparison (handles dots vs. spaces in GitHub asset naming).
- **Toggle Button**: Fixed visual rebound and data-loss race condition during toggling.
- **Nexus Cache Reads**: `hasRecentCheck`/`cachedUpdates`/`cachedCategories`/`cachedExtras` now take the same lock every cache-write path already used.
- **Shared Avatar Component**: Remaining inline avatar-circle implementations in `ModProfilesView` now use the shared `InitialsAvatar` component (already applied elsewhere in this release).
- **Toggle Staleness**: `toggleMod`'s target enable/disable state is now re-derived from the current mod list at execution time instead of the (possibly stale) snapshot captured when the toggle was queued.

### Fixed
- **Nexus Update Checker**: A run that found real data (updates and/or categories/extras) no longer gets collapsed into `.error`/`.rateLimited` just because one other candidate failed or a 429 cut it short — previously discarded already-fetched data.
- **Category Counts**: `availableCategories` now resolves the same way the `.category` filter branch does (top-level mod), instead of counting each group child individually.
- **String Formatting**: 3 sites in `installThaiTranslation` building `"%@"`-template messages via concatenation instead of `String(format:)` now format correctly.
- **SMAPI Message Keys**: Concatenation bug in SMAPI message keys fixed.
- **Localization**: Hardcoded English strings routed through L10n: `build_app.py` codesign return code now checked, Steam Account/Player fallback/None tag and avatar-preset tooltips (previously Thai-only), missing "Profiles" case in `navigationTitleText`, unused `saves_item_id` key now applied.
- **Empty Backups**: Fixed creation of empty backup entries when no `config.json`/`fr.json` files are found in any enabled mod.
- **Index Consistency**: Fixed backup index diverging from disk when file deletion fails during automatic cleanup.
- **Mod Config Backup Path**: Fixed `ModConfigBackupManager` flattening a mod's nested folder path (single-mod "pack" folders resolved to the wrong phantom location).
- **Temp Directory Leak**: Fixed temp-dir leak on mid-analysis sheet dismissal and guarded against dropped zip destroying in-flight temp directories.

## [1.0.9] - 2026-07-18

### Fixed
- **Thai Translation Hub**: Fixed a bug where Group Mods were not correctly evaluated as installed. The app now recursively checks sub-folders (children) of group mods for the `th.json` translation file.
- **Thai Translation Hub**: Enhanced the UI by removing the confusing yellow warning triangle icon for installed translations, and updated the localized text to a positive confirmation message.

## [1.0.8] - 2026-07-08

### Added
- **Inventory Editor**: Added a new section in the Save Editor to view and modify player inventory items.
  - Safely edit stack amounts for items.
  - Delete items directly from your inventory.
  - Implemented safe XML manipulation using `XMLDocument` to prevent save file corruption.

### Fixed
- Fixed an issue in `StandardSection` where excessive padding caused large gaps between UI rows in Settings and App Info pages.

## [1.0.6] - 2026-07-04

### Added
- **SMAPI Log Viewer v2** — Logs page fully rebuilt:
  - **Source tabs**: Clearly separates StarHubTH app logs from SMAPI logs. Switch tabs to view only the source you need.
  - **Level filter pills**: Filter by INFO / WARN / ERROR / TRACE at any time. Works in combination with source tabs (e.g. SMAPI + WARN = only SMAPI warnings).
  - **Structured log entries**: Each entry carries a level, real SMAPI timestamp (HH:MM:SS), message, source, and mod name.
  - **Continuation line merging**: SMAPI log lines without a `[` prefix (continuation lines) are automatically merged into the previous entry.
  - **Reload button**: Reload `SMAPI-latest.txt` at any time without clearing app logs. SMAPI buffers and flushes in batches, not line-by-line.
  - **Clear app logs**: "Clear Logs" button removes only app-generated entries, leaving SMAPI log intact.
  - **Search bar**: Real-time search across message text and mod names.
  - **Clickable mod name badges**: Mod names in SMAPI log entries are clickable — navigates to the Mods page and highlights that mod.
  - **Copy button**: Copies all currently filtered entries to the clipboard.
  - **Auto-scroll toggle**: Opt in or out of auto-scrolling to the latest entry.
  - **Status bar**: Shows filtered entry count vs. total.
  - **Context menu**: Right-click any entry to copy that line.
  - **Color coding**: Red (ERROR), orange (WARN), blue (SMAPI/TRACE), default (INFO/app).
- **Centralized JSON Localization Source**: Added `assets/en.json` and `assets/th.json` as the source of truth for UI text. `build_app.py` now regenerates `Localizable.strings` from these files and fails if Thai/English keys do not match.

### Changed
- `LogEntry` now has a `source` field (`.app` / `.smapi`) to distinguish log origin.
- `log()` in ViewModel always sets `source: .app`.
- `loadSmapiLog()` sets `source: .smapi` and parses timestamps directly from the SMAPI format `[HH:MM:SS LEVEL  Context]`, including double-space handling. SMAPI buffers log output and flushes it in batches rather than line-by-line, so the Reload button may need pressing again after closing the game to see the complete log.
- Removed Japanese localization and the Japanese language picker option. The app now supports English and Thai only.
- Unsupported or removed saved language values now normalize to a supported language, preferring Thai when the user's system language is Thai.
- Thai save-branching terminology now uses "สร้างเซฟใหม่" instead of "แตกสาขา".
- `build_app.py` now uses a project-local Swift module cache so local builds work without writing to the user-level compiler cache.

### Fixed
- Fixed Thai season names appearing inside the English Saves list by making save seasons use centralized localization keys.
- Fixed nested save branches disappearing from the parent-child Saves tree by rebuilding the hierarchy recursively from detected parent folders instead of using a single-level `_copy` / `_branch` regex.
- Fixed mixed-language Backup Timeline labels by localizing backup, restore, branch/create-save, relative time, and date display through the selected app language.
- Fixed several remaining hardcoded Save/Settings/Logs/Mod List strings so Thai and English translations stay in sync.

## [1.0.5] - 2026-07-04

### Added
- **Typed Localization System (L10n)**: Replaced all raw Thai string keys with a typed `L10n` enum. Every UI string now goes through `vm.L(L10n.Section.key)` — compiler will catch missing or mistyped keys instead of silently falling back.
- **Auto-toggle Dependencies Setting**: Added a new "Mod Behavior" section in Settings with a toggle to enable/disable automatic dependency chain toggling. When enabled, opening a mod also enables its required dependencies, and closing a mod closes mods that depend on it. Can now be turned off for manual per-mod control.
- **Mod Profile Improvements**:
  - Profile detail sheet now reflects actual filesystem state when the active profile is opened (no more "0 mods" display).
  - Creating a new profile now snapshots currently enabled mods automatically instead of starting empty.
  - Profile checkbox list now groups mods the same way as the main Mod List page (groups stay grouped instead of being flattened).
  - Checking a mod in a profile now respects the "Auto-toggle Dependencies" setting — checking one mod can cascade-enable its dependencies.
  - Toggling mods on the main Mod List page now syncs the active profile's stored list automatically.
  - Fixed a critical bug where group mods (e.g. Eli & Dylan with 15 sub-mods) were incorrectly matched by `uniqueId = ""` in `applyProfileToFilesystem`, causing only standalone mods to apply correctly. Groups now match by checking if any child is in the enabled list.
  - `updateProfile` (OK button) now correctly applies changes to the filesystem when editing the active profile, instead of being overwritten by a sync from the old filesystem state.
- **Core Extensions — 3-State Status**: The Core Extensions section on the Home screen now distinguishes between three states:
  - ✅ Green: Installed and enabled
  - 🟠 Orange: Installed but disabled
  - ❌ Red: Not installed
- **Core Extensions — Author & Version**: Each core mod row now shows the author name and installed version when the mod is found on disk.
- **Core Extensions — SVE**: Added Stardew Valley Expanded (SVE) to the Core Extensions tracking list.
- **English README & Nexus Description**: Added `README_EN.md` and `nexus_description_en.txt` for international users. Added `[!IMPORTANT]` callout at the top of the Thai README linking to the English version.

### Changed
- `smapiInstalledVersion` changed from `String` (using a Thai sentinel string) to `String?` (`nil` = not installed) — removes a fragile string comparison from business logic.
- `SmapiInstaller` status messages now use `L10n.Smapi` keys instead of `String(localized:)`, ensuring they go through the same runtime language bundle as the rest of the app.
- `applyChain` in `ProfileDetailSheet` now delegates entirely to `vm.applyChainToSet(mod:enable:currentEnabled:)` in the ViewModel — single source of truth, guaranteed identical behavior between the Mod List page and the Profile detail page.

### Fixed
- Fixed profile mod count showing 0 on re-open by loading from actual filesystem state for the active profile in `onAppear`.
- Fixed `applyProfileToFilesystem` not moving group mod folders because `uniqueId` for groups is always `""`.
- Fixed `syncActiveProfileIds` being called after `applyProfileToFilesystem` overwrote the newly saved `enabledModIds` with the old filesystem state.
- Fixed sidebar section headers being re-translated via `LocalizedStringKey` after already receiving a translated string — headers now use `Text(string)` directly.
- Fixed hardcoded Thai strings in `SaveEditorView`, `SettingsView`, `ModListView`, `MainView` alert, and `toggleMod` log messages.

## [1.0.4] - 2026-07-04

### Added
- Added **Mod Profiles** feature: Create, switch, and delete multiple mod profiles to manage different mod setups easily.
- Added a Profile Indicator badge next to the Steam avatar on the Home screen to quickly identify the active profile.
- Added "Select All" and "Deselect All" buttons in the Mod Profiles management window.
- Added Mod ID (`UniqueID`) support to the Mod List search bar, allowing you to search mods by their internal ID.

### Changed
- **Smart Dependency Management**:
  - When enabling a mod, the app now automatically and recursively enables all REQUIRED dependencies.
  - When disabling a mod, the app now automatically and recursively disables all enabled mods that rely on it, preventing crashes from missing dependencies.
  - This system correctly navigates group folders to find the exact sub-mods involved in the dependency chain.
- Enhanced the Dependency Status Indicator in the Mod Info popup with 3 clear states:
  - ✅ Green Checkmark: Dependency is installed AND enabled.
  - ❕ Orange Exclamation: Dependency is installed BUT disabled.
  - ❌ Red Cross: Dependency is NOT installed.
- Simplified the Mod List toolbar by removing the redundant API status indicator (this status is already available on the Home screen).

### Fixed
- Fixed a major flaw in the mod toggle logic where group folders failed to resolve sub-mod dependencies.
- Fixed the API indicator styling conflict that caused a "double border" glitch due to native macOS toolbar styling.

## [1.0.3] - 2026-07-03

### Changed
- Standardized UI components (Settings/Toggles) to match native macOS aesthetics.
- Replaced custom toggle switches with native macOS `SwitchToggleStyle`.
- Improved UI alignment by allowing components to size naturally and align right in settings.
- Moved search bars and action buttons (like refresh/status badges) to the native macOS Navigation Toolbar.
- Renamed "Game System Info" section to "App Info".
- Added native-style section headers to the Sidebar (e.g., "Game Management", "System Settings", "Online Services") to group menu items logically.

### Fixed
- Fixed app launching to the incorrect default tab (now opens to the Home/Profile page).
- Implemented full Navigation History, allowing the macOS Back/Forward toolbar buttons to correctly navigate through previously visited tabs.
- Reduced sizes of toggle switches and info popover buttons to be properly proportional to the surrounding text.
- Removed redundant English parenthetical texts from localized Thai UI strings.
- Fixed a bug where English and Japanese localizations in the Settings page failed to display properly due to mismatched translation keys.

## [1.0.2] - 2026-07-03

### Added
- Added full **Japanese Localization** (Trilingual Support).

### Fixed
- Fixed a bug where navigation titles and `String(localized:)` did not dynamically update when changing languages in-app.
- Fixed a type mismatch bug that caused save file money to display as corrupted memory addresses when formatted with commas.
- Improved localized format strings in the Saves View to respect native language grammar structures.
- Cleaned up redundant English parentheses in Thai and Japanese UI texts.

## [1.0.1] - 2026-07-01

### Added
- Added partial Thai translation (~41%) for **Sword & Sorcery** by DaisyNiko.
  - ✅ **Mateo** — Core dialogue, Events (0H–14H), Marriage dialogue, Custom Talk (CH2–CH5)
  - ✅ **Hector / Biróg** — Core dialogue, Events (0H–14H) including D&D session, river restoration, and grove revelation; Marriage dialogue; Custom Talk (CH2–CH5 + Other)
  - ✅ **Eyvind** — Chapter 2–4 dialogue (backstory with Mateo)
  - ✅ **Cirrus** — Core dialogue, Festival dialogue (all seasons), Gift reactions, Movie reactions, Resort dialogue, Player Death reactions
  - 🔄 **Cirrus** — Marriage dialogue, Events (0H–10H), Strings (in progress)
  - ⏳ **Dandelion, Roslin, and remaining characters** — Pending
- Updated README.md to include Sword & Sorcery and added full Thai-language README section.

## [1.0.0] - 2026-07-01

### Added
- Initial release of the Thai translation collection.
- Added translation for **UI Info Suite 2 Alternative** (v2.8.32) by DazUki.
- Added translation for **Unlockable Bundles** (v4.3.1) by DeLiXx.
- Added translation for **Wear More Rings** (v7.9) by bcmpinc.
- Added translation for **World Navigator** (v1.4.2) by pneuma163.

[Unreleased]: https://github.com/mrbabilo/StarHubFR/compare/v1.26.0...HEAD
[1.26.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.25.0...v1.26.0
[1.25.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.24.0...v1.25.0
[1.24.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.23.0...v1.24.0
[1.23.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.22.0...v1.23.0
[1.22.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.21.0...v1.22.0
[1.21.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.20.0...v1.21.0
[1.20.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.19.1...v1.20.0
[1.19.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.19.0...v1.19.1
[1.19.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.18.0...v1.19.0
[1.18.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.17.0...v1.18.0
[1.17.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.16.0...v1.17.0
[1.16.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.15.0...v1.16.0
[1.15.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.14.1...v1.15.0
[1.14.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.14.0...v1.14.1
[1.14.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.13.1...v1.14.0
[1.13.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.13.0...v1.13.1
[1.13.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.12.1...v1.13.0
[1.12.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.12.0...v1.12.1
[1.12.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.11.1...v1.12.0
[1.11.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.11.0...v1.11.1
[1.11.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.10.3...v1.11.0
[1.10.3]: https://github.com/mrbabilo/StarHubFR/compare/v1.10.2...v1.10.3
[1.10.2]: https://github.com/mrbabilo/StarHubFR/compare/v1.10.1...v1.10.2
[1.10.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.9.1...v1.10.0
[1.9.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.7.1...v1.8.0
[1.7.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mrbabilo/StarHubFR/compare/e38c4eb...v1.1.0
[1.0.9]: https://github.com/mrbabilo/StarHubFR/commit/e38c4eb
[1.0.8]: https://github.com/mrbabilo/StarHubFR/commit/b367896
[1.0.6]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/mrbabilo/StarHubFR/releases/tag/v1.0.0
