# Audit Morning Dew — gestionnaire de mods Windows

> **Date** : 2026-10-09 (lendemain de sa publication).
> **Objet** : **Morning Dew Mod Manager**, Nexus
> [53612](https://www.nexusmods.com/stardewvalley/mods/53612) — Nesryn Rose
> Juincy (envoi NesrynRoseAstra), catégorie *Modding Tools*. Mis en ligne le
> 2026-10-08 à 21:09 UTC, v1.5 puis **v1.6.2** 48 minutes plus tard ; 12
> téléchargements, 0 endossement au relevé (API v2 GraphQL, sans clé).
> Application **Windows seule** (10/11 x64), WPF sur **.NET 8**, un `.exe`
> autonome de 66 Mo. Aucun dépôt public, licence non déclarée.
> **Méthode** : archive Nexus fournie par l'auteur du dépôt
> (`mods tests/MorningDew 53612 1.6.2 …zip`, SHA-256 de l'exe
> `525950ac…f856d`), extraite à part. Le bundle .NET *single-file* (format 6,
> 228 fichiers) a été désassemblé, puis `MorningDew.dll` (UI) et
> `MorningDew.Core.dll` décompilés avec `ilspycmd` : 8 578 lignes lues ou
> filtrées. **Rien d'exécuté.** Les deux points mesurables l'ont été : la
> route smapi.io et le détecteur de conflits, rejoué en Python sur le parc.
> **Suivi** : rangée « Concurrents observés » de `docs/SOURCES.md` §5. Pas de
> sonde `check_sources.py` : ni dépôt ni mod SMAPI (smapi.io ne le connaît
> pas) ; à reprendre si un dépôt apparaît.

---

## 1. Positionnement

Concurrent **indirect** : même public débutant, même périmètre de base (activer
par préfixe point, lancer SMAPI, lire le journal, mises à jour, jeux de mods,
nettoyage), mais Windows seul. Notre créneau macOS n'est pas touché. Il fait
**moins** que nous : ni installation ni `nxm://`, ni traduction, ni sonde, ni
configs par profil, ni sauvegardes de jeu, ni historique de mises à jour.

## 2. Surfaces

| Surface | Ce que fait le code |
|---|---|
| Réseau | `https://smapi.io/api/v4.0.0/mods` (lots de 40, `platform: "Windows"`) ; Nexus API **v1** avec l'en-tête `apikey` ; rien sans le bouton « Check online » et un consentement mémorisé |
| Secret | **clé Nexus en clair** dans `%APPDATA%\MorningDew` (`AppSettings.NexusApiKey`, JSON) — chez nous : Trousseau |
| Processus | `explorer.exe`, l'exe SMAPI, le navigateur ; registre `HKCU\Software\Valve\Steam` pour trouver le jeu |
| Écritures | bascule = `Directory.Move` (préfixe point) ; suppression = corbeille Windows, ou `Directory.Delete` récursif **refusé** à travers un point de réparse (lien, jonction) ; nettoyage = mise en quarantaine réversible avec index |
| Rien de | téléchargement, extraction d'archive, chargement de code, écriture dans les fichiers des mods |

## 3. Défauts relevés — ne pas porter

1. **Le détecteur de conflits Content Patcher ignore `Priority`.**
   `ConflictFinder.AnalyzePatches` classe en **erreur** (« Content Patcher
   will skip the rest ») deux `Load` inconditionnels sur la même cible, que
   l'un ou l'autre déclare une `Priority` ou non. Or un `Load` qui déclare une
   priorité n'est plus exclusif : c'est ce qui faisait tomber notre spike A5
   de 12 à 3 paires. **Rejoué sur le parc actif du jour** : 2 erreurs, **2
   fausses** — East Scarp NPCs × Law and Order SV (`Data/Events/Blacksmith`),
   Night Market Expansion × SVE (`Maps/Beach-NightMarket`). A5-T4 : 0 paire
   active. Son texte se trompe aussi sur l'effet : « only one can win », là où
   Content Patcher n'applique **aucun** des deux.
2. **Lecteur JSON strict et sensible à la casse.** `JsonDocument` accepte
   commentaires et virgules finales, mais ni `.03`, ni `'…'`, ni `,,` (A5-T5).
   Les clés `Changes`/`Action`/`When`/`Target` sont lues à la casse exacte,
   alors que Content Patcher ne la regarde pas (193 `action` en minuscules
   relevées au parc en D2-T3). Un fichier illisible est sauté par un `catch`
   vide : **25 fichiers** du parc actif, perdus sans le dire.
3. **« Le dernier appliqué gagne, par ordre de nom de dossier »** : affirmation
   affichée à l'utilisateur pour les `EditImage`/`EditMap`, sans source. SMAPI
   ordonne d'abord par dépendances.
4. **smapi.io sans les gardes connues.** `installedVersion` part brute depuis
   le manifeste : une version illisible vide le lot de 40 en silence
   (`docs/SOURCES.md` §2.1). Et `apiVersion` est omise quand la version de
   SMAPI n'est pas connue, ce qui rend zéro suggestion. La route `v4.0.0` est
   valide : mesuré le 2026-10-09, même réponse que notre `v3.0` pour Content
   Patcher. Rien à changer chez nous.
5. **Clé Nexus en clair** (§2).

## 4. Idées à peser

1. **Bascule groupée transactionnelle.** `ToggleEngine.SetEnabledAsync`
   empile chaque renommage réussi. Au premier échec, il défait la pile en ordre
   inverse et marque les mods restants « non appliqués » : le lot passe en
   entier, ou rien ne passe. Chez nous, un lot partiel est rescanné et signalé
   (`bulkTogglePartial`), sans retour automatique. Depuis R5, un retour
   **manuel** existe : l'instantané d'avant le geste. Un retour automatique
   éviterait un parc à moitié basculé, mais il défait aussi les réussites
   qu'on voulait garder. **À trancher par l'auteur, rien d'engagé.**
2. **Refus de supprimer à travers un lien.** Le contrôle `ReparsePoint` sur
   le dossier et ses parents est une bonne garde. Notre suppression passe par
   la corbeille de l'app (`ModTrash`), dont le comportement face à un lien n'a
   pas été mesuré : **à vérifier** avant de conclure quoi que ce soit.

Déjà chez nous, donc rien à prendre : relevé « You can update » du journal SMAPI
(`SmapiLogParser`, `UpdateCount`), rapport copiable (`ModlistReport`, E2-T1),
doublons d'`UniqueID`, dépendances manquantes, quarantaine réversible.
