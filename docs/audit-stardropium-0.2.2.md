# Audit — Stardropium 0.2.2-beta *(2026-10-04)*

Suite des audits 0.1.3 / 0.1.4-beta résumés dans
[`audit-mods-config-perf.md`](audit-mods-config-perf.md). Delta 0.2.0-beta →
0.2.2-beta décompilé et comparé (`ilspycmd`, 40 fichiers, ~1 757 lignes) ; le
0.2.0 vient du backup d'installation du 2026-10-04, le 0.2.2 du parc.
Cross-check possible avec les sources GitHub (`ArshiaS1381/StardropiumMod`,
suivi `mod/stardropium-src`) — non nécessaire : le décompilé fait foi.
Rien du mod n'est repris.

| | |
|---|---|
| **Identité** | `ArshiaS1381.Stardropium` · 0.2.2-beta · Nexus 52803 · **en pause** sur le parc (`.Stardropium`, DLL du 2026-10-03 23:03) — corrige l'état « actif » porté jusque-là |
| **Surfaces** | réseau 0 / chargement de code 0 / écriture de fichiers 0, avant comme après (Socket 20→19 = un libellé i18nisé, pas une API ; `GetAssemblies()` nouveau = énumération, pas un chargement) |
| **Verdict** | **GARDER ACTUEL** — le delta corrige de vrais défauts, aucune clé à forcer au-delà de l'existant |

## Prétentions de l'auteur

- **Caméra** (confirmé au code) : `Game1__UpdateViewPort__Prefix` réécrit —
  cible = clamp vanilla, lerp réel, clamp du lerp en float avant arrondi.
  L'ancien gelait le suivi sur les bords droit/bas des grandes cartes
  (mines, fermes) jusqu'au snap 64 px.
- **« OnDayStart GC retiré »** (partiel — **différé, pas retiré**) : le trim
  du matin devient une machine à états async (≤ 60 × 500 ms) qui attend
  `IsWorldReady && !fadeToBlack && gameMode == 3` puis trim hors fil. Le GC du
  matin existe toujours, il sort de la fenêtre de chargement. Contrepartie :
  un `GC.Collect(2)` nouveau sur `SaveLoaded` (une fois par partie).
- **« PIF save retention »** (confirmé, cohérent) : `customData` sorti de
  `VanillaIgnoredBranches`, et tout lieu dont le `<name>` commence par
  `DLX.PIF_` / `Custom_` bascule le sous-arbre entier vers
  `SpaceCoreFindAndRemoveFallback` — promenade complète sans pruning vanilla,
  équivalente à SpaceCore. Garde vérifié non mort sur une sauvegarde réelle du
  parc (376 noms `Custom_*` prendront la voie non-prunée : coût légèrement
  supérieur, comportement identique).
- **Mac** (confirmé) : `ShouldRelieveMacMemory` stoppe
  `malloc_zone_pressure_relief` pendant les fondus (ce que la 0.2.0 faisait
  en pleine transition) ; trim du matin différé hors fondus ;
  `LowLatencyGCModule` sort du mode `SustainedLowLatency` au retour au titre
  (la 0.2.0 n'en sortait jamais). P/Invoke tous OS-gatés, rien de Windows-only
  ne fuit.
- **i18n** (confirmé côté code) : un `i18n/default.json` anglais — pas de
  `fr.json`, notre éditeur affichera l'anglais, sans objet pour nous.

## SpaceCore — pas de jumeau d'UltraSmooth

Zéro `XmlSerializer`, `Prewarm`, `InitializeSerializers` dans l'arbre. Le
module ne touche que la promenade XML de sauvegarde
(`FindAndRemoveModNodes`, prefix sur `currPath == "/1"`), avec repli sur
l'original à toute exception. La course de sérialiseurs qui casse les
sauvegardes chez UltraSmooth n'a pas d'équivalent ici. Le module d'écrasement
de mises à jour Content Patcher retiré à la parution **n'est pas
réintroduit** (jeu de patches identique avant/après ; les 101 lignes du
module CP = cache de `PropertyInfo` + i18n).

## Défauts — 3 × 🟡, aucun 🔴/🟠

- **Cache d'images CPU sans invalidation** (régression pure) : la 0.2.0
  revalidait chaque hit contre taille + mtime du fichier ; la 0.2.2 sert le
  cache sur un `TryGetValue` nu. Un PNG de mod réécrit en cours de session
  sert l'ancien décodage. Rare, et `PurgeTextureCaches` reste le nurse.
- **Patch « SaveSaver » sur-large** : balayage réflexif des assemblies
  contenant « SaveSaver », patch de toute méthode `*Location*(Prune|Remove|
  Clean|Valid|Check)`, `__result = true`, exceptions avalées en `Trace`.
  Inerte aujourd'hui (SaveSaver absent du parc) ; à surveiller si un jour il
  arrive.
- Mineur : `IsLocalPlayerInLocation` est du code mort ; 7 `Id` de modules
  renommés (cosmétique).

## Config — 2 défauts changés, sans effet sur le parc

`MaxTextureCacheMB` 512 → 2048 (re-plafonné à 256 en `LowMemoryMode` ; le
config du parc fixe 512 explicitement) ; `ManageSinZCache` true → false (le
parc fixe true explicitement). Le préchauffage de données
`EnablePreWarmDataLoader: true` du parc existe toujours, désormais borné à
`MaxDegreeOfParallelism = 2` (constat 4 de l'audit 0.1.1, maintenant borné).

## Points à remonter à l'auteur si contact

Invalidation du cache d'images (taille+mtime), et périmètre du patch
SaveSaver.
