# Audit des mods de référence — config, keybinds, performance

> **Objet** — ce que la décompilation de cinq mods du jeu (GMCM, Modern
> Config Menu, UltraSmooth, Faster Menu Load, Stardew Loading Optimizer)
> apprend à StarHubFR, sur quatre axes : gestion des fichiers de config,
> éditeur de `config.json`, détecteur de collision de touches, analyse
> d'impact mémoire/FPS. Précédé du même geste que
> [`audit-config-menus.md`](audit-config-menus.md) (2026-08-28) : décompiler
> les menus de config pour instruire C4 — ici pour instruire C4-T1, le
> chantier D et la surveillance des sources.
>
> **Méthode** — les archives viennent de `mods tests/` (gitignoré). DLL
> décompilées avec `ilspycmd` 10.1.1 (`DOTNET_ROOT` doit pointer sur le
> cellar Homebrew pour que l'apphost trouve le runtime) ; le SLO s'étudie
> depuis son zip « Source Code » (0.5.0-rc.18). Les affirmations chiffrées
> sont mesurées : sur le parc réel
> (`/Applications/Stardew Valley.app/Contents/MacOS/Mods`), sur le journal
> SMAPI réel (`~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt`, 489 Ko,
> session du 2026-09-01), ou par scan UTF-16 des chaînes des DLL.
> Relevé : **2026-09-04**. Voir aussi `docs/SOURCES.md` §6.

---

## 1. Gestion des fichiers de config

### Qui écrit quoi

- **GMCM n'écrit jamais le `config.json` des autres mods.** Chaque mod
  enregistre deux callbacks — `Register(mod, reset, save,
  titleScreenOnly)` — où `save` est presque toujours
  `Helper.WriteConfig(config)`. GMCM invoque le callback ; le mod écrit.
- La sémantique des quatre boutons (`SpecificModConfigMenu`) :
  - **Save / Save & Close** : `BeforeSave` (chaque option) → `Save` →
    `AfterSave`. Rien ne s'écrit à la fermeture seule.
  - **Reset to Default** : `Reset` (nouvelle instance par défaut) → hooks
    → **sauvegarde immédiate**.
  - **Cancel** : `Close()` sans rien défaire. Les setters des options
    écrivent **directement l'objet config vivant** du mod : « Annuler » ne
    restaure pas — il ne fait que ne pas sauver sur disque. Les changements
    restent actifs jusqu'au redémarrage du jeu. *(Piège UX que notre
    éditeur n'a pas : lui écrit un fichier, ses annulations sont vraies.)*
- **La vue « raccourcis » de GMCM sauvegarde d'un coup tous les mods** qui
  ont au moins une option `SButton` ou `KeybindList` — un seul « Save » y
  réécrit N `config.json`.
- **Un mod peut réécrire sa config à tout moment** : UltraSmooth appelle
  `WriteConfig` à quatre sites de son `ModEntry` (migration, bascule de
  profil, commandes), MCM à cinq. Conclusion pratique : `config.json` est
  **volatile tant que le jeu tourne**.

### Le patron SLO (le plus abouti)

`ModConfig.Normalize()` au chargement, puis réécriture si migration :

- **champ de version** (`OptimizationProfileVersion`, actuellement 12) et
  migration : version 0 = installation neuve → défauts stables ; version
  antérieure → profil hérité inféré depuis les valeurs ;
- **`Math.Clamp` sur chaque champ numérique** (24 bornes documentées dans
  le code) ;
- **champs retirés fail-closed** : `EnableBackgroundMapPreparation` est
  forcé à `false` à chaque chargement, le champ restant dans le JSON pour
  ne pas casser la désérialisation ;
- **profils** (LowMemory/Balanced/HighMemory) qui **écrasent** une dizaine
  de champs : éditer `ResourceProfile` dans le JSON rend les champs
  dépendants caduques jusqu'au prochain `Normalize()` ;
- `PrepareToUninstall` : état de config qui coupe tout avant retrait.

### Conséquences pour StarHubFR

1. **Toute valeur hors borne écrite par notre éditeur sera silencieusement
   clampée au prochain lancement du jeu** — et les bornes ne vivent que
   dans le code des mods (voir §2). Un éditeur honnête doit soit connaître
   les bornes, soit dire qu'il ne les connaît pas.
2. **Un `config.json` peut être non normalisé sur le disque** (écrit à la
   main, ou par une version antérieure du mod) : l'éditeur ne doit pas le
   juger invalide tant que la grammaire JSON tient.
3. **Champs inconnus** : un JSON peut porter des champs retirés (SLO les
   garde volontairement) ou des champs d'une version plus récente du mod —
   jamais une erreur.
4. Si le jeu tourne, avertir : l'édition hors du jeu peut être écrasée par
   un `WriteConfig` du mod au moment de la fermeture de session.

---

## 2. Corpus de types pour l'éditeur de config.json

### Les onze types d'options GMCM

`SimpleModOption<T>` (bool, int, float, string, **SButton**,
**KeybindList**), `ChoiceModOption<T>` (texte à `allowedValues` :
l'équivalent de nos énumérés), `NumericModOption<T>` (int/float avec
`min`/`max`/`interval`/`formatValue`), `SectionTitle`,
`SectionSubHeader`, `Paragraph`, `Image`, `PageLink` (sous-pages),
`ComplexOption` (dessin arbitraire), `ReadOnly`. MCM y ajoute sliders,
menus déroulants, zones de texte — et **importe tel quel** un enregistrement
GMCM (chaînes mesurées dans son DLL : « Generic Mod Config Menu detected »,
« not installed; nothing to import »).

### Ce que le fichier ne dit pas

- **Les bornes n'existent nulle part dans `config.json`** : ni min/max des
  nombres, ni `allowedValues` des choix. GMCM les connaît en marche (à
  l'enregistrement), SLO les garde dans `Normalize()`. UltraSmooth, lui,
  les met **en prose dans l'infobulle** : « Clamped 256–4096 KB ».
- **Le `fieldId` GMCM n'est pas le nom du champ config** : SLO utilise
  `resource-profile` pour `ResourceProfile`, `fast-warp` pour
  `EnableFastWarpTransitions` — kebab libre, aucun rapport garanti.
- **La clé i18n n'est pas non plus garantie** : UltraSmooth suit la
  convention `config.<champCamelCase>.name` (115 clés), SLO choisit
  `config.fast-warp.name` pour un champ nommé autrement. Notre
  rapprochement clé↔champ est un *best effort* avec repli.
- Les tableaux existent (`PrefetchExtensions: string[]`), tout comme int
  **et** float (piège connu du `NumberFormatter` sans décimale).

### Conséquences pour StarHubFR

Un « schéma » complet ne se déduit pas du seul JSON. Trois niveaux, du
moins au plus cher : (a) **inférence typée** depuis le JSON existant
(booléens, entiers, flottants, énumérés observés, tableaux) — déjà notre
socle ; (b) **bornes lues de la prose des infobulles** quand la regex
« clamped/between X and Y » matche — fragile mais gratuite ; (c)
**bibliothèque de schémas curative** pour les mods lourds du parc
(UltraSmooth, SLO…), inspirée de ce que `ConfigSchema` de Content Patcher
fait déjà pour les packs. Le patron SLO (« normalise au chargement »)
suggère aussi une **prévisualisation de normalisation** : montrer ce que
le mod fera de la valeur saisie — à terme, en exécutant les règles connues.

---

## 3. Détecteur de collision de touches

### Le format, mesuré sur le parc

Les valeurs keybind dans `config.json` sont du **SMAPI verbatim** :
`"F7"` (bouton seul), `"LeftControl + Q"` (combinaison, séparateur
espace-plus-espace), `"None"` (non lié), et plusieurs keybinds séparés par
`", "`. Les noms `SButton` couvrent clavier (`OemQuotes`, `D9`), souris
(`MouseX2`) et **manette** (`LeftStick`). La table du nom complet vit dans
l'enum `SButton` de SMAPI (source créditée `docs/SOURCES.md` §3).

### Ce que fait MCM — et sa règle fautive

MCM a déjà un détecteur (`GetKeybindConflictReason`,
`ModernConfigMenuUI`) : catégorie « Conflicts ⚠️ », motifs
`[!] Conflicts with <mod> (<option>)` et
`[!] Conflicts with default game controls` — ce dernier lu dans
`Game1.options` **en marche** (10 catégories : déplacements, action,
outil, menu, journal, carte, chat). Mais sa règle compare **le premier
bouton du premier keybind** : `LeftControl + Q` se réduit à `LeftControl`,
donc deux combinaisons partageant un modificateur sont faussement en
conflit, et un conflit réel entre ensembles différents est manqué.

### Prototype sur le parc réel (2026-09-04)

Détection statique par **ensemble exact de touches** (parseur ci-dessus,
champs dont le nom finit par Key/Hotkey/Keybind/Button, valeur
imparsable ignorée, `None` ignoré) :

- **31 keybinds liés dans 16 mods** ;
- **3 collisions exactes** : `K` (LanguageSwitcher·HotKey vs
  ValleyBonds.PokeMorphFramework·OpenMenuKey), `LeftStick`
  (deux frameworks ValleyBonds — collision **manette**), `F7`
  (UltraSmooth·ToggleOverlayKey vs SDV-Radiance·ToggleKey) ;
- la règle MCM (premier bouton) verrait 4 groupes — dont sa classe de faux
  positifs.

### Réconciliation avec C4-T2 — livré, et meilleur que ce prototype

**Ce détecteur existe déjà dans StarHubFR depuis le 2026-08-29**
(C4-T2) : `SButtonTable` figée depuis un relevé IL, `KeybindParser`,
`KeybindScanner` en Core, sémantique **exact-combo** avec le contre-exemple
MCM couvert par une non-régression, règle du catalogue R4, restitution dans
les Alertes système et sur la fiche du mod. Mesuré à la livraison sur le
parc réel : **141 liaisons, 18 collisions, 11 conflits jeu** — mon prototype
ci-dessus (31 liaisons) voyait moins de champs : son heuristique de nommage
(suffixe Key/Hotkey) est plus étroite que le scanner livré. La mesure reste
utile comme contre-vérification indépendante, et pour un constat que la
livraison ne couvrait pas : les collisions **manette** (`LeftStick`) sont
bien réelles sur le parc.

Les angles morts documentés à la livraison restent ouverts (spec §12) :
chevauchements sous-ensemble (A = `K`, B = `K`+Shift), composants de pack,
mods en pause. La fusion avec les contrôles remappés du joueur (lus dans la
sauvegarde) reste une suite possible — MCM les lit en marche dans
`Game1.options` (10 catégories), nous les versionnerions depuis la
sauvegarde.

---

## 4. Impact mémoire / FPS des mods

### Ce qui s'ingère aujourd'hui, sans rien installer

- **SLO journalise sa config normalisée entière** au démarrage — ligne
  `INFO Stardew Loading Optimizer` préfixée `[OPTIMIZER CONFIG]`, mesurée
  dans le vrai journal : profil, chaque limite de cache, et pour chaque
  optimisation le triplet *configuré/effectif/raison*
  (`fastWarp=configured=True,effective=True,reason=single-player-session`).
  C'est un état de config **résolu**, gratuit à parser.
- **MCM journalise chaque menu enregistré** :
  `Registered config menu for Ultra Smooth (palmhacker13.UltraSmooth)` —
  la liste des mods configurables par menu, lue dans le journal.
- **UltraSmooth écrit des rapports de trace sur le disque** :
  `LagTraceRecorder` produit `UltraSmooth_TraceReport_<horodatage>.txt`
  **dans le dossier du mod** (`helper.DirectoryPath`), sections balisées
  (`🚩 [CPU UPDATE LOOP OVERLOAD DETECTED]`, `[GPU PRESENTATION / RENDER
  DELAY DETECTED]`), budget de trame 16,6 ms, causes racines proposées.
  StarHubFR peut les lire directement. ⚠️ Le parc est en 0555 par endroits
  (piège X7) : l'écriture peut y échouer silencieusement — le mod se
  contente d'un avertissement en journal.
- Son **instantané de benchmark** (`PerformanceSnapshot`) ne porte que
  `FpsAvg` et `TickAvgMs` ; l'overlay live (FPS, frametimes, RAM, ticks)
  n'est pas exporté autrement.

### Ce qui n'existe pas

- **Pas d'attribution par mod du temps de trame côté SMAPI 4.5.2** : scan
  UTF-16 des DLL de l'installation — aucune chaîne d'avertissement de
  lenteur par mod (« frame time », « eating », « slow » : zéro). Les
  avertissements de lenteur qu'on trouve en ligne viennent de versions
  antérieures ou d'autres cheminées ; ne pas bâtir dessus.
- L'`ModAnalyzer` d'UltraSmooth mesure **ses propres sections**
  (`TotalMs`/`PeakMs`/appels), pas les autres mods — son nom est trompeur.

### Conséquences pour StarHubFR

Un écran « Performance » a trois sources réelles, par coût croissant :

1. **Statique** (déjà en partie en place) : poids des dossiers, nombre de
   patches Content Patcher par mod (TRACE affected-patches existe déjà),
   dépendances lourdes (SLO en porte 13).
2. **Journal** : parser `[OPTIMIZER CONFIG]` (état SLO résolu),
   `Registered config menu` (couverture menus), bornes de chargement que
   SLO mesure (`SAVE LOAD START`), et les rapports de trace d'UltraSmooth
   détectés dans `Mods/*/UltraSmooth_TraceReport_*.txt`.
3. **Session instrumentée** : inviter à lancer le jeu avec
   `EnablePerformanceMeasurement`/`EnableDetailedDiagnostics` (SLO) ou la
   touche benchmark (UltraSmooth, `F9` par défaut ici), puis ingérer le
   journal et les rapports au retour. La mesure reste celle des mods —
   StarHubFR orchestre et restitue.

La ventilation fine « ce mod coûte X ms » reste hors de portée sans
instrumentation SMAPI dédiée ; ne pas la promettre dans l'UI.

---

## 5. Propositions — réalignées sur l'existant (consignées en ROADMAP)

La première rédaction de cette table proposait un détecteur keybind (P3)
que **C4-T2 avait déjà livré** le 2026-08-29 — vérifié, cf. §3. La table
ci-dessous ne porte que ce qui manque vraiment :

| # | Proposition | Aboutit à | Taille |
|---|---|---|---|
| P1 | Éditeur : avertissement « jeu en cours » (config volatile, un `WriteConfig` mod peut écraser) + prévisualisation « sera normalisé au prochain lancement » pour les mods connus pour normaliser (SLO, UltraSmooth) | **C4-T6** | S |
| P2 | Bornes : lecture de la prose d'infobulle (« Clamped X–Y ») puis bibliothèque de schémas curative pour les gros mods C# du parc — complète le `ConfigSchema` des packs (C4-T4) | **C4-T1** (instruction) | M |
| P3' | Keybinds : les angles morts livrés — chevauchements sous-ensemble, composants de pack, mods en pause — et la collision manette rendue visible dans le rapport existant | **C4-T2 suite** | M |
| P4 | Écran « Performance » : ingestion `[OPTIMIZER CONFIG]` (SLO), `UltraSmooth_TraceReport_*.txt`, `Registered config menu` (MCM), corrélée aux patches CP par mod — en complément du log Profiler (D1) | **D2** | M |
| P5 | Session instrumentée : « lancer avec diagnostics » (EnablePerformanceMeasurement SLO / benchmark UltraSmooth) et analyse au retour | **D2** | M |

Fait dans la foulée : SOURCES.md §6 porte ces cinq mods, **tous surveillés**
par `check_sources.py` — la version de chaque page via l'oracle smapi.io
(gratuit, sans clé : les pages Nexus renvoient 403 aux clients
non-navigateurs), la source de GMCM et de FasterMenuLoad via leurs monorepos
GitHub.

---

## 6. Verdicts par mod

| Mod | Verdict | Détail |
|---|---|---|
| **GMCM** | **référence, ne pas copier aveuglément** | Son modèle save/revert par callbacks et son `Cancel` mensonger (setters live, rien n'est défait) sont les pièges à ne pas reproduire ; sa taxonomie d'options (11 types) et sa vue raccourcis groupée sont l'ergonomie de référence. Notre éditeur est déjà plus honnête : ses annulations sont vraies. |
| **Modern Config Menu** | **observer, dépasser** | Front alternatif qui importe les enregistrements GMCM (mesuré dans son DLL) — preuve que la couche d'enregistrement est le vrai contrat, pas l'UI. Sa règle de collision au premier bouton est l'anti-pattern documenté ; C4-T2 la couvre en non-régression. |
| **UltraSmooth** | **exploiter** | Corpus de test de l'éditeur (115 clés `config.*`, sections, choix, boutons, clé maison) **et** source de télémétrie : ses `UltraSmooth_TraceReport_*.txt` écrits dans son dossier sont ingérables tels quels (→ D2). Ses `config.json` réécrits à 4 sites imposent l'avertissement « jeu en cours » (→ P1). |
| **Faster Menu Load** | **crédit, pas de code** | `LazyTab` : une page-placeholder qui ne génère la vraie qu'à l'activation — élégant, hors du périmètre d'un gestionnaire. ZeroXPatch déjà crédité pour SMAPILogDoctor ; sa source vit dans le monorepo suivi (`log-doctor`). |
| **Stardew Loading Optimizer** | **le patron à imiter côté éditeur** | `Normalize()` versionné (24 clamps, migration, champs retirés fail-closed, profils) est exactement ce qu'un éditeur de config devrait *prévisualiser* (→ P1/P2) ; sa ligne `[OPTIMIZER CONFIG]` au démarrage est un état de config résolu gratuit (→ D2). Constat défavorable à journaliser : son manifeste exige 13 dépendances que son README dit optionnelles. |
