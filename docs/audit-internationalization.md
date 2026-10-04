# Audit Internationalization — éditeur de traductions en jeu

> **Date** : 2026-10-04.
> **Objet** : **Internationalization** — bcmpinc, Nexus
> [21317](https://www.nexusmods.com/stardewvalley/mods/21317) (v0.5 affichée),
> dépôt [`bcmpinc/StardewHack`](https://github.com/bcmpinc/StardewHack)
> (le mod vit dans `Internationalization/` d'une collection), manifeste **v0.7**
> @ `d3419ce` (2026-10-03 — la veille de l'audit) ; **0.8.0 courant** selon
> smapi.io au relevé (le changelog Nexus ne détaille que 0.6 et 0.7). Né le
> 2024-03-27,
> **14 commits en 2026** : actif depuis 2,5 ans. 55 endossements.
> **Licence** : **LGPL-3.0** (`LICENSE.txt` à la racine du dépôt) — idées
> relevables, code non reprise sans trancher la licence.
> **Méthode** : clone lecture-seule `--depth 50` dans `/tmp` (supprimé après
> audit). Tout le mod se lit : **~627 lignes C#** (9 fichiers) +
> `Static/index.html` (23) + `Static/script.js` (407). net6.0, SMAPI ≥ 4.0.
> **Suivi** : sonde `mod/internationalization` dans `check_sources.py`, rangée
> §5 de `docs/SOURCES.md`. Rien commité par l'audit lui-même.

---

## 1. Ce que c'est

Un mod SMAPI qui **édite les traductions i18n depuis un navigateur, en cours
de partie** : un serveur `HttpListener` sur `http://localhost:8018/` (pollé
depuis `UpdateTicking`, fil du jeu), une page servie depuis le dossier du mod.
Le geste complet — couvrir, éditer, voir, sauver — vit dans le navigateur.

| | Leur réponse | Notre réponse (axe C) |
|---|---|---|
| Où | **en jeu**, navigateur à côté | dans l'app, hors jeu |
| Couverture | couleur rouge/jaune/vert par mod × langue | badge FR % + `TranslationCoverage` |
| Aperçu | **vivant en jeu** (injection réflexive dans SMAPI) | relance du jeu requise |
| Édition | cellules du navigateur, recherche d'entrées vides | éditeur `fr.json` intégré, diff EN/FR, assistance IA locale |
| Langues | toute langue déclarée + langues custom | français |
| Tolérance i18n | parseur regex maison (commentaires mono/multi-lignes) | `I18nLenientParser` (oracle Newtonsoft) |
| Écriture | **greffe sur octets bruts** : commentaires, ordre et format d'origine intacts | `OrderedJSONWriter` : ordre conservé, **commentaires perdus** |
| Sauvegarde disque | backup `fichier~` voisin, PUT du fichier entier | écriture atomique, baselines, restauration |

## 2. Architecture — ce qui est habile

1. **Serveur web fil du jeu** (`ModEntry.process`, à chaque tick : accept +
   vidage des requêtes complétées). Zéro course : tout passe par le fil du jeu.
   `IsLocal` vérifié, connexion distante avortée.
2. **Aperçu vivant par réflexion dans SMAPI** (`TranslationRegistry.Entry`) :
   lecture du champ privé `Translations.Translator`, puis `All` (locale →
   clés), `ForLocale`, `GetRaw`, et construction de `Translation` par réflexion
   — un `Set` modifie la table de SMAPI en place et la partie **affiche la
   nouvelle chaîne sans relance** (sauf si le mod a copié/caché sa traduction).
   C'est leur feature signature, et son prix : un couplage aux entrailles
   privées de SMAPI, à recasser à chaque montée majeure.
3. **Greffe d'octets bruts à la sauvegarde** (`script.js generate_file`) : le
   fichier d'origine est conservé octet par octet ; seuls les littéraux
   modifiés sont remplacés, **par leur position dans le texte source**.
   Commentaires, ordre, formatage, échappements d'origine : intacts. Les
   entrées vidées sont exclues de la greffe (commit du 2026-10-03) : vider une
   cellule ne peut plus écraser une traduction par une chaîne vide.
4. **Parseur i18n tolérant côté navigateur** : regex reconnaissant les
   commentaires — le même besoin que notre `I18nLenientParser`, réglé en
   JavaScript pour l'éditeur.

## 3. Défauts relevés (leurs angles morts)

1. 🔴 **`File.OpenWrite` sans troncature** (`TranslationFile.Put`) : si le
   `File.Move` du backup échoue (cas banal : `fichier~` existe déjà d'une
   sauvegarde précédente — `File.Move` lève, le `catch {}` l'avale), le fichier
   original reste en place et l'écriture **sans troncature** y laisse une
   queue de l'ancien contenu dès que le nouveau est plus court. Fichier
   corrompu, sans erreur remontée (`NotFound` mensonger au navigateur).
2. 🔴 **Backup à génération unique, silencieusement absent** : le `catch {}`
   du `File.Move` signifie que toute sauvegarde après la première se fait
   **sans backup** — et le backup `~` vit dans `i18n/` du mod (invisible,
   jamais nettoyé).
3. **Pas d'écriture atomique** : un crash en plein `CopyTo` laisse un demi-
   fichier. Nous : écriture atomique + relecture avant de rendre le texte.
4. **`UpdateKeys: ["Nexus:0"]`** (manifeste) : clé cassée — les alertes de
   mise à jour **en jeu** de SMAPI ne fonctionneront jamais pour ce mod. Le
   relevé smapi.io, lui, résout par `UniqueID` et voit 0.8.0 : la clé cassée
   ne pénalise que le joueur, pas notre sonde.
5. **Pas de vérification de jetons** : `{{…}}` figure dans leur ToDo ; rien
   ne contrôle que la traduction garderait ses jetons de jeu. Nous :
   `TranslationTokenCheck` + refus corrigible ligne à ligne.
6. **Clés nouvelles impossibles** : `Set` n'accepte qu'une clé déjà chargée
   par SMAPI pour la session — une clé ajoutée par l'auteur d'une mise à jour
   ne devient éditable qu'après relance.
7. Aucune notion de fraîcheur/baseline, glossaire, ni assistance IA.

## 4. Ce qu'on en tire

- **Idée candidate (axe C)** : la **greffe sur octets bruts** — préserver
  commentaires et format exact du fichier d'auteur en ne remplaçant que les
  littéraux. Notre `OrderedJSONWriter` conserve l'ordre mais **perd les
  commentaires** des i18n réécrits (mesuré : aucun `comment` dans le module).
  À peser en termes de valeur réelle (combien d'i18n du parc portent des
  commentaires utiles ?) avant d'engager.
- **Écart assumé, non poursuivi** : l'aperçu vivant en jeu. Il exige un mod
  compagnon réflexif dans les parties privées de SMAPI — exactement la
  fragilité que notre sonde évite (ses lectures passent par des postfix
  publics). Le coût d'entretien n'est pas notre style.
- **Ne pas porter** : `File.OpenWrite` sans troncature, backup silencieux
  mono-génération dans le dossier du mod, écriture non atomique.

## 5. Menace

Faible et d'une autre nature : **complément** (en jeu) plus que concurrent
(hors jeu) de notre axe C. Actif depuis 2,5 ans, modeste (55 endossements),
Windows-comme-macOS (mod SMAPI neutre). À revoir si son auteur arrête le
navigateur pour une intégration jeu-native.
