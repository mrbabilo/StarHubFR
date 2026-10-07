# Stardropium — session réelle du 7 octobre 2026

Journal SMAPI local : début 14:36:40, dernière ligne 14:54:31 (heure locale).
SMAPI 4.5.2, Stardew Valley 1.6.15, Stardropium 0.2.2-beta chargé,
UltraSmooth ignoré car en pause, SLO chargé. Session exécutée par l'utilisateur.

## Relevés conservés

```text
[14:44:16 INFO  Stardropium] [Morning Memory Optimizer (Background)] RAM: 655 MB -> 660 MB (Managed Heap: 3445 MB -> 3444 MB, 0 cached textures purged/bounded).
[14:54:11 INFO  Stardew Loading Optimizer] [SAVE WRITE TOTAL] 16433.8 ms from SMAPI Saving through Saved, location=FarmHouse, screen=0.
[14:54:12 INFO  Stardropium] [Morning Memory Optimizer (Background)] RAM: 1561 MB -> 1565 MB (Managed Heap: 3749 MB -> 3751 MB, 0 cached textures purged/bounded).
```

| Heure | Mémoire résidente avant → après | Mémoire gérée avant → après | Textures purgées |
|---|---|---|---|
| 14:44:16 | 655 → 660 Mio (+5) | 3 445 → 3 444 Mio (−1) | 0 |
| 14:54:12 | 1 561 → 1 565 Mio (+4) | 3 749 → 3 751 Mio (+2) | 0 |

Unités : la DLL divise les octets par 1 048 576 avant d'écrire « MB » ; ce sont
des Mio, arrondis à l'entier. Source : `MemoryOptimizationModule.TrimMemory`,
DLL décompilée 0.2.2-beta. `RAM` vient d'`Environment.WorkingSet`, `Managed Heap`
de `GC.GetTotalMemory(false)` : mesures distinctes, à ne pas additionner ni
traiter comme total et sous-total strictement comparables.

## Ce que cette session permet de conclure

- Le format matinal est confirmé dans un vrai journal 0.2.2-beta : prérequis
  de D2-T5 satisfait. Deux mesures ponctuelles, espacées de 9 min 56 s.
- Pas de baisse de mémoire résidente visible immédiatement après ces deux
  opérations. Le jeu continue pendant le travail en arrière-plan : les écarts
  ne permettent pas d'attribuer toute variation au seul nettoyage.
- Aucune texture purgée annoncée. Dans ce chemin `isOvernight`, la DLL évite
  l'appel direct à `PurgeTextureCaches` : zéro n'est pas une preuve de panne.
- Mémoire résidente après traitement : +905 Mio entre les deux points ; mémoire
  gérée : +307 Mio. Deux points d'une session ne démontrent pas une fuite.
- SLO rapporte 16,434 s pour l'écriture de sauvegarde (événements Saving → Saved),
  pas pour toute la nuit. Pas de mesure témoin permettant d'attribuer cette durée
  à Stardropium ou de conclure à un gain/perte de fluidité.
- Aucun message de bascule « Detected low-memory / unified memory device » dans
  ce journal. Absence de message ≠ profil normal démontré.

## Erreurs distinctes de la mesure

Trois problèmes figurent dans les entrées de niveau ERROR : dépendance
Alternative Textures absente pour `(AT) Vanilla Forage Crops and Bushes`, patch
Sunberry Village sur le gel du temps de CJB Cheats Menu en échec, authentification
Galaxy non connectée. Aucune entrée ERROR attribuée à Stardropium, SLO ou la
sonde dans ce journal. Les avertissements FTM sur des objets introuvables restent
à examiner séparément ; ils ne prouvent pas un problème mémoire.

## Contrat d'affichage pour D2-T5

Afficher des points horodatés avant/après, séparément pour mémoire résidente
et mémoire gérée. Conserver les hausses, les baisses et les zéros ; ne pas
transformer une hausse en « mémoire libérée ». Ne pas dessiner une courbe
continue présentée comme mesure entre ces points. Indiquer source, version,
unités et nombre de relevés. Sans ligne exploitable, afficher « Aucune mesure
Stardropium dans ce journal ». Profil basse mémoire inconnu sans preuve positive.

Ces extraits servent de fixtures ciblées sans copier le journal complet ni les
données de partie. D2-T5 est implémenté dans `StardropiumMemoryReport` et la carte
« Mémoire — Stardropium » de Performances : lecture hors du fil principal via
`SessionEnvironmentStore`, points avant/après sans ligne interpolée, détails
horodatés et conclusion sur le dernier relevé. La carte reste explicitement
attachée au dernier journal, indépendamment des sessions comparées de la sonde.
Vérification visuelle par l'utilisateur encore à faire.

## Validation du lancement guidé — 16:41 à 16:47

Mesure effectuée par l'utilisateur après les corrections de reprise. Le journal
commence à **16:41:48**, charge Stardropium **0.2.2-beta**, SLO **1.0.0** et
la sonde **0.9.22**, puis se ferme normalement à **16:47:38**.

```text
[16:46:44 INFO  Stardropium] [Morning Memory Optimizer (Background)] RAM: 2097 MB -> 2099 MB (Managed Heap: 4246 MB -> 4244 MB, 0 cached textures purged/bounded).
```

Le reçu `StardropiumDiagnostic/memory_report.json`, terminé à **16:47:42**,
contient exactement ce relevé, le début de cette session, la bonne version et
zéro ligne illisible. Aucun instantané de restauration SLO ou Stardropium ne
subsiste. Stardropium est revenu en pause ; SLO et la sonde sont actifs,
UltraSmooth reste en pause. La transaction est terminée ; les octets de la
configuration initiale ne sont plus disponibles pour une comparaison indépendante.

RAM résidente : **+2 Mio** ; mémoire gérée : **−2 Mio** ; **0 texture purgée**.
Un seul relevé ne démontre aucun gain global ni amélioration de fluidité. Aucun
WARN/ERROR attribué à Stardropium, SLO ou la sonde. Les trois problèmes déjà
observés restent distincts : Alternative Textures absent, patch Sunberry Village
sur CJB Cheats Menu en échec, authentification Galaxy non connectée.

Acquisition et fin de transaction validées par les fichiers. L'affichage des
graphiques et des confirmations reste à confirmer visuellement par l'utilisateur.
