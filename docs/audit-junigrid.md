# Audit JuniGrid — code et fonctionnalités à étudier

> **Date** : 2026-10-01.
> **Objet** : lire le code de **JuniGrid** (`github.com/MLD-yu/JuniGrid`, Nexus mod
> [53227](https://www.nexusmods.com/stardewvalley/mods/53227), MLD210), gestionnaire de
> mods Windows paru le jour même en v1.2.4, pour juger sa qualité et repérer ce qui vaut
> d'être étudié pour StarHubFR.
> **Méthode** : clone en lecture seule au commit `86dca38` (2026-10-01 15:41 UTC), lecture
> ciblée des services qui recoupent nos axes, recoupement avec le code de StarHubFR. Les
> chemins `JuniGrid/…` désignent leur dépôt. **Rien n'est repris tel quel** — consigne
> du dépôt : critiquer l'amont avant d'intégrer.
> **Suivi** : `check_sources.py` (clé `JuniGrid`) ; carte dans `docs/SOURCES.md` §5.

---

## 1. Ce qu'est JuniGrid

Lanceur et gestionnaire de mods **Windows seul** : WPF + Blazor dans WebView2, .NET
autonome, EN/ZH. ~28 000 lignes de C# hors banc de test (45 services), dont une page
`Components/Pages/Mods.razor` de **4 659 lignes** qui porte une bonne part de la logique
métier. Dépôt créé le 2026-09-02, très actif (dernier push le jour de l'audit), 3 ★.
Sa spécificité : il **change la version du jeu** (DepotDownloader, de 1.0 à 1.6) et gère
les sauvegardes que cela rend illisibles. Hors périmètre pour nous (macOS, pas de dépôt
Steam en direct).

## 2. Qualité du code — verdict

**Sérieux sur la robustesse, fragile sur la structure.** Les commentaires documentent des
mesures réelles (« 实测 », dates, nombre de cas) comme les nôtres ; plusieurs défauts
qu'ils ont corrigés sont des défauts que nous avons connus.

Ce qui est bien fait :

- **Format d'archive identifié par les octets** (`ModService.cs:2455`, en-têtes zip / rar /
  7z / xnb / png / html) — notre règle « croire les octets, pas les noms ».
- **Zip-slip gardé** sur rar/7z (`ModService.cs:2484`, entrée `../` ou absolue sautée,
  chemin résolu vérifié sous la racine) ; `ZipFile.ExtractToDirectory` de .NET le garde
  déjà pour le zip.
- **Écritures atomiques** (`AtomicFile.cs`, `.tmp` + `File.Move`), tâches persistantes
  (`TaskCenterService.cs`, une tâche « running » au redémarrage devient « échec »).
- **États d'erreur distincts** : le pont de commandes distingue cinq raisons
  d'indisponibilité au lieu d'un « copié » muet (`CommandBridgeService.cs:181`).
- **OAuth PKCE propre** (§3.1).

Défauts relevés (aucun ne nous concerne directement — ce sont des pièges à ne pas
reproduire) :

| Défaut | Où | Pourquoi c'est un problème |
|---|---|---|
| **Réécrit le `Version` du `manifest.json` de l'auteur** avec le libellé du fichier Nexus après une installation | `ModService.cs:3067` (`TrySetManifestVersion`) | Les libellés de version Nexus sont du bruit (« 14 » avant 1.4.1, cf. mémoire du dépôt) : le manifeste prend une version fausse, et la vérification de mise à jour de **SMAPI** compare ensuite contre elle. Toucher un fichier d'auteur, c'est exactement ce que notre règle interdit |
| « Déjà installé » déduit de la **présence du zip téléchargé** `nxm-<mod>-<fichier>.zip` | `ModService.cs:3140` | Un téléchargement dont l'installation a échoué passe pour installé ; la mise à jour disparaît |
| Jetons OAuth (accès **et** rafraîchissement) **en clair** dans le fichier de config | `ConfigService.cs:318` | Pas de DPAPI ; chez nous la clé vit au Trousseau |
| Traduction de l'interface par des **points d'accès non documentés** (Chrome `clients5.google.com`, Edge, Youdao « aidemo ») | `TranslationService.cs:13`, `:40` | Hors conditions d'utilisation, cassable à tout moment |
| **Vide le jeu de travail du processus du jeu** (`EmptyWorkingSet`) sur seuil mémoire | `MemoryService.cs:120` | Les pages reviennent au premier accès : saccades en jeu, pour un gain d'affichage du « mémoire libre » |
| Logique métier dans la vue : `Mods.razor` 4 659 lignes | `Components/Pages/` | Intestable ; leur banc de test est un `Program.cs` maison de 8 855 lignes |
| Sauvegardes des surcouches **dans le dossier du mod hôte** (`x.json.junigrid_backup`) | `ModService.cs:913` | Elles disparaissent avec le dossier à la mise à jour du mod ; chez nous, les copies vivent dans `Application Support` |

## 3. Fonctionnalités à étudier

Classées par intérêt pour StarHubFR. Chaque ligne dit ce que nous avons déjà.

### 3.1 Connexion Nexus par OAuth — **à prévoir avant toute distribution publique**

`NexusOAuthService.cs` : code d'autorisation + **PKCE S256**, client public (aucun secret
embarqué), `client_id` délivré par Nexus après validation de l'application (`junigrid`),
retour sur un **port loopback enregistré** (`http://localhost:49162/auth/callback`),
`scope` vide, profil par `validate.json`, rafraîchissement automatique (un 4xx au
rafraîchissement = autorisation révoquée ⇒ déconnexion). Leur récepteur loopback accepte
plusieurs connexions et ignore les pré-connexions vides du navigateur et `favicon` — un
piège qu'ils documentent (`:258`).

**Pourquoi c'est important pour nous** : la
[politique d'utilisation de l'API Nexus](https://help.nexusmods.com/article/114-api-acceptable-use-policy)
tolère les **clés personnelles** pour une application en test ou à usage personnel ; une
application publique doit être **enregistrée auprès de Nexus** (support@nexusmods.com), et
seule une application approuvée peut utiliser le SSO. StarHubFR demande aujourd'hui la clé
personnelle de l'utilisateur (`NexusAccountStore`) : c'est acceptable tant que l'app reste
un outil personnel, **pas** pour la distribution de l'axe E (E2-T3, 2.0.0).

Transposition macOS : `ASWebAuthenticationSession` avec un schéma d'URL propre ou un
loopback, jetons au Trousseau. Préalable non technique : enregistrer l'app chez Nexus.

### 3.2 Reprise des téléchargements interrompus — **petit, utile, natif**

`ResumableDownload.cs` : sur coupure, reprise par `Range: bytes=<écrit>-`, 5 tentatives ;
un serveur qui renvoie 200 au lieu de 206 fait repartir de zéro ; progression limitée à
une notification toutes les 0,4 s. Motif documenté : le CDN gratuit de Nexus coupe souvent
(« retombe à 0 % vers 3 % »).

**Chez nous** : `NexusFileDownload` lance un `downloadTask` sans reprise — une coupure
fait échouer le téléchargement entier. `URLSession` sait reprendre nativement :
`downloadTask(withResumeData:)` avec les données de reprise que porte l'erreur
(`NSURLSessionDownloadTaskResumeData`). Aucune dépendance à ajouter.

### 3.3 Mod remplacé : étiquette neutre au lieu du silence

`Mods.razor:1480-1560`. Quand smapi.io signale un mod (cassé, abandonné, version non
officielle) **mais** que la version installée est déjà le remplaçant, ils retirent
l'alerte et **gardent une étiquette neutre** (« repris par la communauté », « l'auteur a
arrêté ») : le fait que l'auteur d'origine ne maintient plus le mod reste vrai et
utile. Deux autres détails :

- un remplaçant qui **ne vit pas sur Nexus** (fil de forum, releases GitHub — mesuré chez
  eux sur Wind Effects, SAAT, Show Birthdays) : le lien du résumé est ouvert tel quel ;
- le premier lien **vers une page de mod Nexus** du résumé est pris, pas le premier lien
  tout court (Adventurer's Guild en donne deux).

**Chez nous** : `CompatibilityResolution` juge déjà le verdict réglé (7 cas sur 9 sur le
parc) — mais le verdict réglé disparaît. L'étiquette neutre et les deux détails de lien
sont à comparer avec nos 9 cas.

### 3.4 Surcouches de traduction restaurables fichier par fichier

`ModService.cs:910-1420`, `ConfigService.cs:593` (`OverlayRecord`). Un paquet de
traduction **sans manifeste** qui écrase des fichiers d'un autre mod devient une
« surcouche » :

- une entrée par fichier : hôte, chemin, **empreinte de l'original**, **empreinte du
  fichier posé**, copie du paquet (réactiver sans retélécharger), état actif ;
- plusieurs paquets sur le même fichier (un seul en place, les autres en réserve) ;
- **santé** à chaque analyse : le fichier sur le disque est-il celui qu'on a posé ? Une
  mise à jour du mod hôte efface la surcouche en silence — ils la **signalent sans la
  reposer** (`:1202`), parce que l'auteur a pu corriger sa propre traduction entre-temps.

**Chez nous** : le hub FR traduit en place avec un fichier compagnon (C3), et la mise à
jour d'un mod préserve `fr.json`. Ce qui nous manque : l'**installation d'un paquet de
traduction Nexus qui écrase un autre mod** (le cas des « French translation » sans
manifeste) avec un registre par fichier et un retour arrière. Le principe « signaler,
jamais reposer d'office » est à garder.

### 3.5 Commandes vers la console SMAPI depuis l'app

`smapi-bridge/ModEntry.cs`, `CommandBridgeService.cs`. SMAPI 4 n'a **aucune API publique**
pour exécuter une commande, ne lit pas l'entrée standard redirigée, et l'injection de
touches ne passe pas (mesuré chez eux). Leur mod compagnon retrouve par réflexion le
`CommandManager` de SMAPI (par **nom de type**, pas par signature figée — un SMAPI
renommé donne « version non prise en charge » au lieu d'un plantage), exécute les
commandes sur `UpdateTicked`, et les reçoit par un tube nommé ; la découverte passe par un
fichier de poignée de main (nom du tube, jeton, PID vérifié vivant). La sortie n'est pas
renvoyée : elle est déjà dans `SMAPI-latest.txt`.

**Chez nous** : notre sonde (`mrbabilo.StarHubFR.Probe`) est déjà dans le jeu et fait déjà
de la réflexion. Un canal de commandes (`patch reload`, `patch summary`, `reload_i18n`)
serait un ajout à la sonde, pas un second mod. Intérêt moyen : utile au hub de traduction
(recharger un i18n sans relancer le jeu).

### 3.6 Le reste

| Fonctionnalité | Fichier | Verdict |
|---|---|---|
| Temps de jeu par jour (carte de chaleur), compté toutes les 30 s pour survivre à un arrêt brutal | `PlayTimeService.cs` | faible — nos sessions de sonde le donnent déjà |
| Avis « dépendance installée mais désactivée » | `Mods.razor` | déjà chez nous (`ModDependencyStatus`, `ModAnomaly`) |
| Mise à jour jugée sur le fichier installé (identifiant de fichier + version) | `ModService.cs:2989` | déjà chez nous (A1-T11) ; leur heuristique du zip présent est à **ne pas** reprendre |
| Garde-fou « versions à un seul nombre contre plusieurs » (« 1 » contre « 0.0.1 ») | `ModService.cs:3196` | à vérifier chez nous : comparaison d'un libellé Nexus « 1 » contre un manifeste « 0.0.1 » |
| Sauvegardes illisibles par une version plus ancienne du jeu, Steam Cloud | `SaveVersionService.cs` | hors périmètre. **Piège noté** : retirer des sauvegardes de `Saves/` avec Steam Cloud actif les fait effacer du cloud à la sortie (« Removing from cloud », `:22`). StarHubFR ne déplace une sauvegarde que sur geste explicite — vérifié le 2026-10-01 |
| Portraits, versions du jeu, compression mémoire, traduction de l'interface | — | hors périmètre ou à proscrire (§2) |

## 4. Recommandations

1. **OAuth Nexus avant la distribution publique** (axe E). Préalable : demander
   l'enregistrement de l'app à Nexus. Sans lui, publier StarHubFR en demandant une clé
   personnelle sort de la politique d'utilisation de l'API.
2. **Reprise des téléchargements** (`resumeData`) — petit chantier, gain direct sur les
   coupures du CDN.
3. **Étiquette neutre pour un remplacement déjà fait** + liens hors Nexus — petit ajout à
   `CompatibilityResolution`, à vérifier sur nos 9 cas.
4. **Paquets de traduction qui écrasent un autre mod** — à spécifier avec le hub FR ;
   reprendre le registre par fichier et la règle « signaler sans reposer ».
5. **Canal de commandes dans la sonde** — après les trois premiers.
