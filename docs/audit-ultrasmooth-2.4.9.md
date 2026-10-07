# UltraSmooth 2.4.9 — delta et coexistence (2026-10-07)

**Conseil : garder UltraSmooth en pause pour les prochaines mesures.** La 2.4.9
ajoute des interventions sur Content Patcher et les sauvegardes SpaceCore. Le
verdict favorable sur les réglages par défaut de la 2.4.5 ne couvre pas ce delta.
Un défaut de contrat Content Patcher est identifié ; les interactions de
sauvegarde demandent une validation en jeu, sans conclure à une corruption.

## Périmètre et preuves

Comparaison ILSpy 10.1.1 des DLL locales 2.4.6 (sauvegarde d'installation du
2026-10-06, `130815_A64FDE50-88FD-426D-A4E9-9160936FA557`) et 2.4.9 installée
dans `Mods/.UltraSmooth`. Lecture des DLL Content Patcher **2.9.1**, SpaceCore
**1.28.4**, SLO **1.0.0** et Stardropium **0.2.2-beta** du même parc.
Changelog Nexus lu lors du contrôle des sources ; le code décompilé prime sur
ses annonces. [Page officielle UltraSmooth](https://www.nexusmods.com/stardewvalley/mods/50971).

SHA-256 des binaires :

| Binaire | SHA-256 |
|---|---|
| UltraSmooth 2.4.6 | `5ca390774c6f1013dd799fea655c1c5942735c55262ed95140e49f7a60cb5c83` |
| UltraSmooth 2.4.9 | `8694cc1ae3d9502a0ac0c1d6d4358fad013ab5616862a0eb58c42eabd2aa918f` |
| Content Patcher 2.9.1 | `5203af255c6a826a598470a642e0eb488fd943196354f79fe05fcd08bf6c941f` |
| SpaceCore 1.28.4 | `ecf3140f9c96b56a06c1a67d140d88153ebdd84c636f4f9c10904a8f9658b3a6` |

Audit statique ciblé, pas validation exhaustive du mod. Aucun lancement de jeu,
aucune sauvegarde ni configuration réelle modifiée. Les commentaires ILSpy
« Unknown result type » dus aux références manquantes ne sont pas des défauts
attribués aux DLL.

## 1. Content Patcher : accélération qui retombe sur le chemin normal

`ContentPatcherOptimizer.OnAssetRequested_Prefix` matérialise les chargeurs et
éditeurs en **`object[]`**, puis appelle par réflexion :

```csharp
ApplyPatchesToAsset<T>(AssetRequestedEventArgs e, LoadPatch[] loaders, IPatch[] editors)
```

Cette signature est celle de Content Patcher 2.9.1 installé. Un `object[]` ne
devient pas un `LoadPatch[]` ou un `IPatch[]`, même si ses éléments ont le bon
type. Dès qu'un tableau contient un patch, l'invocation échoue ; le `catch`
silencieux renvoie `true`, laissant Content Patcher recommencer normalement.
Conséquence attendue si ce préfixe est posé : allocations, parcours et exception
supplémentaires sur ce chemin, sans l'accélération annoncée. Coût non mesuré.
Le cas sans aucun patch court-circuite sans cette invocation.

**Contrat reproduit** par un programme C# autonome sous .NET 10.0.401 :
invocation avec `object[]` rejetée par `ArgumentException` avant exécution de la
cible ; contrôle avec tableaux typés accepté. Ce test ne charge ni Harmony ni
le jeu et ne prouve pas que tous les patches UltraSmooth s'installent en jeu.
Reproduction minimale : appeler `MethodInfo.Invoke` avec `new object[] { new
LoadPatch() }` pour un paramètre déclaré `LoadPatch[]`.

Autre écart : `ignoreLoadPatches` n'est jamais respecté par le préfixe, alors que
Content Patcher évite explicitement `GetCurrentLoaders` quand il vaut `true`.
Le repli actuel protège l'appel final ; corriger uniquement les types laisserait
ce deuxième défaut. Les préfixes ne consultent pas les options après installation.

`EnableContentPatcherOptimizer` vaut **true par défaut** ; la clé est absente du
config local, donc son absence ne désactive pas ce nouveau module. UltraSmooth
s'efface en présence de l'un des deux IDs reconnus du mod autonome Content
Patcher Optimizer. Il faut vérifier le journal d'installation des patches pour
établir quels chemins fonctionnent effectivement pendant une session.

## 2. Sauvegarde SpaceCore : remplacement partagé avec Stardropium

Le nouveau `SpaceCoreSaveOptimizer` remplace
`SaveGamePatcher.FindAndRemoveModNodes` à la racine `/1`. Stardropium remplace
**la même méthode, au même point**, avec son propre parcours. Aucun garde de
coexistence avec Stardropium n'apparaît dans ce module UltraSmooth. Les deux
préfixes peuvent court-circuiter l'original : ne pas additionner leurs gains ni
présumer lequel sera exécuté sans observer l'ordre effectif des patches.

Deux différences avec SpaceCore original méritent validation :

- UltraSmooth ignore des branches selon leur seul nom (`stats`, `options`,
  `mailbox`, etc.), quel que soit leur emplacement, **avant** de vérifier
  `xsi:type="Mods_…"`. SpaceCore parcourt tout. Un élément moddé portant l'un de
  ces noms ne suivrait donc pas le même chemin. Aucune occurrence problématique
  démontrée dans une sauvegarde réelle du parc.
- Les indices XML occupent un tableau loué avec `Rent(64)`, sans croissance.
  Un arbre dépassant sa capacité peut faire échouer `BuildXPath`. Le `catch`
  reprend SpaceCore sans restaurer l'arbre ou la liste déjà modifiés. Risque
  conditionnel ; aucune sauvegarde réelle de cette profondeur vérifiée.

Exposition locale si les mods sont réactivés : UltraSmooth
`EnableFastSaveEngine=true`, Stardropium `EnableSpaceCoreSaveOptimization=true`.
Les deux mods sont actuellement **en pause**.

SLO agit ici sur `InitializeSerializers` et `DeserializeProxy`, pas sur ce
parcours d'écriture. Pas de conflit direct établi entre ces trois méthodes ;
ce constat ciblé ne certifie pas toute la coexistence SLO/UltraSmooth.

## 3. Mémoire, horloge et autres changements

- **Mémoire macOS** : `SafeWindowMemoryManager` appelle le nettoyage natif
  `malloc_zone_pressure_relief` après collecte mémoire et attente des
  finaliseurs lors de `Saving`. Travail synchrone susceptible d'allonger cette
  étape ; pas de durée mesurée. Stardropium possède aussi ses nettoyages :
  chevauchement d'objectif, pas preuve de blocage. Le message « Freed » borne
  les différences à zéro : il ne montre pas une éventuelle hausse de mémoire.
- **Horloge** : nouveau remplacement de `GameLocation.passTimeForObjects`.
  Il saute `minutesElapsed` pour certains objets jugés inertes. Les extensions
  dépendant de cet appel demandent validation. Garde global `EnableMod`, sans
  option dédiée dans ce préfixe. Pas de régression concrète établie sur le parc.
- **Affinité CPU** : nouveauté réservée à Windows ; aucun gain à promettre
  sur ce Mac.
- **2.4.7/2.4.8** : changelogs annoncent corrections du rythme Radiance/UI et
  des monstres à fréquence élevée. Classes de pacing modifiées dans le delta ;
  gains et comportement visuel non vérifiés en jeu.

Le config local conserve aussi `EnableFurnitureCulling=true` : ce n'est pas
le profil par défaut évalué favorablement dans l'audit 2.4.5. Aucun réglage
installé n'a été changé pendant cette analyse.

## Conséquences pour StarHubFR et prochaine mesure

1. Garder UltraSmooth en pause pour isoler la prochaine mesure Stardropium.
   Son activation automatique n'entre pas dans le diagnostic SLO.
2. D2-T5 reste conditionné à un **vrai journal Stardropium 0.2.2-beta** après
   passage d'une nuit. Les chaînes de l'ancienne DLL ne suffisent pas à livrer
   un nouveau parseur. Mesurer séparément mémoire totale du processus, mémoire
   gérée et durée du passage au jour suivant ; une baisse mémoire seule ne
   démontre pas une meilleure fluidité.
3. Pour réévaluer UltraSmooth, attendre correction du chemin Content Patcher
   ou le désactiver avant lancement, puis tester sur copie de partie avec
   Stardropium en pause. Vérifier sauvegarde, rechargement et contenu moddé.
   Ce protocole proposé n'a pas été exécuté.
4. Ne pas afficher une incompatibilité certaine dans StarHubFR sur cette seule
   analyse. Distinguer défaut de contrat confirmé, chevauchement de patches et
   risque conditionnel. Ne pas changer la baseline sources pour masquer le delta.

Les autres écarts du contrôle sources du 2026-10-07 ne demandent pas de
modification applicative démontrée : fork propre attendu, traduction i18n 2.3,
Event Studio 1.0.1, blacklist SMAPI (schéma stable, cache local déjà à jour),
dépôt partagé UI Framework dont le delta concerne HolidaySalesContinued.
