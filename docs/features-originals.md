# Les features originales de StarHubFR face à la concurrence

> **Date** : 2026-10-10 (état du code après v1.62.0).
> **Objet** : dire, preuve en main, ce que StarHubFR fait qu'aucun autre
> gestionnaire de mods Stardew Valley ne fait. Document de positionnement :
> il alimentera la page Nexus (**E2-T3**) et le README.
> **Sources** : audits concurrentiels versionnés
> ([`audit-stardrop.md`](audit-stardrop.md), 2026-07-31 ;
> [`audit-stardrop-nativemac.md`](audit-stardrop-nativemac.md), 2026-10-04 ;
> [`audit-gestionnaires.md`](audit-gestionnaires.md)), items livrés du
> [`ROADMAP.md`](ROADMAP.md) §11 et code du dépôt. Chaque affirmation porte
> sa référence — rien ici n'est déduit d'une capture d'écran marketing.
>
> **Concurrents couverts** :
> - **Stardop** (`Floogen/Stardrop`, C#/Avalonia, cross-platform) — le plus
>   mature, référence de l'écosystème ;
> - **Stardrop-NativeMac** (`machelajr/Stardrop-NativeMac`, SwiftUI) — port
>   natif macOS, premier concurrent direct sur notre créneau ;
> - **Vortex / Nexus Mods App** — gestionnaires généralistes, couverts par
>   [`audit-gestionnaires.md`](audit-gestionnaires.md) ;
> - **RimManager** — autre jeu (RimWorld), veille d'architecture seulement
>   (§10 de la roadmap).

---

## 1. Le positionnement en une phrase

StarHubFR est le seul gestionnaire **natif macOS** et **francophone** qui
prend au sérieux trois choses que la concurrence n'aborde pas : **la santé
de la modlist** (diagnostic, conflits, compatibilité), **la traduction
française** (de la couverture à l'édition assistée), et **la performance
mesurée en jeu** (sonde dédiée).

Le positionnement est vérifié ligne à ligne dans les audits : le §3.8 de
[`audit-stardrop.md`](audit-stardrop.md) liste ce que Stardop ne fait pas —
diagnostic de log, bissection, réparation, détection de doublons,
traduction — et le §3.9 de
[`audit-stardrop-nativemac.md`](audit-stardrop-nativemac.md) conclut :
« Tout l'avantage différenciant de StarHubFR tient encore. »

---

## 2. Traduction française — l'axe que personne d'autre n'a

C'est le différenciateur produit (axe C de la roadmap, livré de v1.13.0 à
v1.17.0 puis complété jusqu'au 2026-10-02). **Aucun gestionnaire cité
ci-dessus n'offre la moindre fonction de traduction** — Stardop n'en a pas,
le port natif macOS est UI anglaise seule, Vortex est hors sujet.

Ce que StarHubFR fait, de bout en bout, sans quitter l'app :

| Capacité | Détail | Référence |
|---|---|---|
| **Couverture par mod** | pourcentage de traduction, clés vides comprises, filtre « À revoir » | C1-T1/T2/T7 |
| **Diff EN/FR** | côte à côte par clé et par section de commentaire, états traduit / manquant / obsolète / identique | C2-T1/T3/T5 |
| **Éditeur `fr.json` en place** | écriture atomique, backup systématique, jetons du jeu (`{{Token}}`, `$q`, `#$b#`) protégés | C3-T1 |
| **Pré-traduction assistée** | trois voies : IA locale (Ollama, sans donnée qui sort), API distante (DeepL…), traduction d'une sélection | C3-T3/T7/T8 |
| **Glossaire du jeu** | noms de PNJ, objets, saisons — amorcé des traductions officielles, injecté dans chaque lot | C3-T4 |
| **Lots de traduction** | export/import JSON et ZIP, fusion entre traducteurs avec écran d'arbitrage | C3-T5 |
| **Delta de clés après mise à jour** | l'anglais d'un mod ne se fige plus : les clés ajoutées/retirées/renommées par une mise à jour sont rapportées, les renommages réconciliés | C2-T4 |
| **Parseur i18n tolérant** | commentaires, virgules finales, clés dupliquées — comportement **mesuré contre la vraie DLL Newtonsoft du jeu**, pas déduit d'un schéma ; ~40 % des i18n réels refuseraient un lecteur strict | C1-T6, C3-T6 |
| **Vitrine FR** | page « Traductions FR » : cherche sur Nexus les traductions françaises des mods installés | C5-T1 |

La promesse tenue : *traduire un mod moyen de bout en bout sans quitter
StarHubFR, et pouvoir revenir en arrière à tout moment* (aucune écriture
sans backup ni diff).

---

## 3. Diagnostic et santé de la modlist

Le §3.8 de l'audit Stardop est sans appel : Stardop lit `SMAPI-latest.txt`
uniquement pour en extraire les versions. StarHubFR, lui :

- **Carte de santé du journal SMAPI** — parseur complet (`SmapiLogParser`),
  repliement du bruit, erreurs **attribuées par mod** avec historique par
  version, alertes unifiées par gravité (`HealthIssue`).
- **Bissection guidée** — identifier le mod responsable d'un plantage parmi
  ~900 en une dizaine d'essais guidés, avec retour exact à l'état initial
  (A4, v1.11.0). Absent de tout concurrent.
- **Réparateur de dossiers** — quarantaine des structures cassées,
  restauration d'un manifeste illisible depuis sa sauvegarde d'installation
  (`ModFolderRepairer`, A1-T2).
- **Anomalies comptées honnêtement** — doublons d'`UniqueID`, collision de
  noms de dossier (`X` et `.X`), manifestes illisibles, tout ce que le
  dédoublonnage silencieux de Stardop cache.

## 4. Compatibilité : trois sources croisées, une liste noire

- **API live smapi.io** (statut, `brokeIn`, mise à jour non officielle,
  mod de remplacement), **fallback hors-ligne** `mods.jsonc`, et depuis
  A2-T5 une **troisième source locale** : `smapi-internal/metadata.json`
  du SMAPI installé — sans elle, 14 faux signaux sur le parc de référence
  pour 1 réel.
- **Liste noire SMAPI des mods malveillants** (A2-T7) : croisée au disque
  selon les règles réelles de SMAPI (identifiants, empreintes de DLL,
  fichiers piégés — X116), alerte critique **avant le lancement**, jamais
  de suppression automatique.
- **Verdict de compatibilité calculé sur les versions réelles** du jeu et
  de SMAPI lues dans le journal — le port macOS concurrent envoie des
  versions codées en dur à smapi.io (défaut n° 2 de son audit).

## 5. Conflits entre mods : prévenir, pas constater

Aucun concurrent ne détecte de conflits (§3.8 Stardop, §3.9 port Mac).
StarHubFR en couvre quatre natures :

1. **Collisions de raccourcis clavier** — entre mods **et avec le jeu**,
   par contexte d'écoute relevé dans le code des mods (C4-T17), vue
   clavier physique AZERTY/QWERTY fidèle à ce que le jeu Mac lit
   (C4-T15), capture de raccourci au lieu du champ texte (C4-T10),
   export Markdown du rapport (C4-T13).
2. **Incompatibilités déclarées ou soupçonnées** — signalement manuel,
   écartable, persistant (A5-T2), plus le paragraphe de compatibilité de
   l'auteur sur la fiche (A5-T3).
3. **Dépendances cachées dans le code** — les chaînes des DLL des mods C#
   résolues contre les types réels des autres mods : 161 paires citant →
   cible sur le parc de référence, dont 21 actives non déclarées au
   manifeste (A5-T6). Et les mods de performance qui patchent les mêmes
   méthodes Harmony : catalogue décompilé + carte Harmony de la sonde
   (A5-T7, A5-T10).
4. **Conflits de ressources Content Patcher** — deux packs qui
   réclament le même asset en priorité `Exclusive` **sont annoncés avant
   activation**, y compris par « Tout activer » ou un profil (A5-T4,
   A5-T8) : 3 duos dormants trouvés sur le parc, zéro actif — le seul
   gestionnaire qui prévient *avant* que rien ne s'applique.

## 6. Sauvegardes de partie : ce que les mods y laissent

Personne d'autre ne regarde *dans* les sauvegardes :

- **Fiche d'une sauvegarde** : nomme les mods en pause qui y ont laissé du
  contenu — objets, bâtiments, données (A1-T6) — et mettre en pause chiffre
  ce qui resterait orphan (A1-T8).
- **Mods disparus** ayant écrit dans la sauvegarde : détection par clés
  `smapi/mod-data` (A1-T9).
- **Nettoyage clé par clé** sous backup vérifié, écriture atomique, BOM
  préservé (A1-T10).
- **Mise à jour d'un mod sans perte de progression** : tout fichier absent
  de l'archive neuve est une donnée locale et est remis en place, au
  bilan (A1-T7 — règle mesurée : 100 fichiers certains sur 52 mods du
  parc).

## 7. Performance mesurée : la sonde StarHubFR

Un **mod compagnon open source** (`companion/StarHubFR.Probe`) écrit pour
l'occasion, qui n'optimise rien et ne touche à aucun autre mod : il mesure.
Concurrents : rien d'équivalent n'existe — ni chez Stardop, ni chez le port
natif (scan synchrone sur le fil principal chez ce dernier).

- Coût **par mod et par gestionnaire d'événement** (ms/s, allocations),
  mesuré en jeu et validé contre *Profiler* et UltraSmooth (D4-T1/T5).
- **Carte Harmony** : quels mods patchent quelle méthode (D4-T2).
- **Mémoire retenue** par textures, attribuée par pack via `OnBehalfOf`
  (D4-T6 ; à l'écran, validation en jeu en cours).
- **Benchmark guidé avant/après** : « quel est l'impact de ce nouveau
  mod ? » avec sessions appariées, mémoire, FPS, chargements (D5-A/B/C).
- **Bornes des options GMCM** lues dans l'éditeur de config (D4-T7) et
  diagnostics tiers exploités (SLO, Stardropium — D2).

## 8. Intégrité et sécurité des données

- **Clé Nexus dans le Trousseau macOS** — là où Stardop chiffre la sienne
  avec clé et IV posées en clair à côté (`SimpleObscure`, écarté à juste
  titre par l'audit).
- **Suppression réversible** : corbeille dédiée (`_StarHubFR_Corbeille`)
  distincte de la quarantaine du réparateur, remise en place possible,
  purge toujours explicite (X103) ; rétention optionnelle des archives
  Nexus pour réinstaller hors-ligne à la version exacte.
- **Application de profil protégée** : garde jeu (refus net si le jeu
  tourne), journal write-ahead et **reprise au lancement après un crash**
  (R2/R2bis), plan d'application prouvé idempotent (R6), retour arrière
  aux instantanés d'avant un geste de masse (R5).
- **Extraction d'archives défensive** : format identifié par les octets
  (X4/X5), plafond zip-bomb lu avant extraction, chemins traversants
  rejetés — chaque garde éprouvée sur des archives fabriquées pour
  l'occasion (tranche F2).
- **Écran Entretien** : inventaire mesuré (sauvegardes orphelines, clés
  mortes, poids), purge par cran sous confirmation, jamais automatique
  (X25).

## 9. Ergonomie et francophonie

- **UI bilingue en/fr par construction** : parité des clés **validée au
  build** — un texte ajouté d'un seul côté casse la compilation. Stardop
  affiche 14 langues sans aucun garde-fou ; le port natif n'en a aucune.
- **Guide de premier lancement** en huit étapes, rejouable (E2-T4).
- **Multi-sélection fine** (clic, ⌘, ⇧, ⌘A, Espace — I-T20), palette de
  commandes ⌘K (I-T2), raccourcis ⌘1…⌘9 (I-T1).
- **Approbations Nexus** depuis la fiche (A3-T8), quota quotidien visible
  (B2-T6), avertissement `UpdateCautionMessage` de l'auteur d'un mod avant
  écrasement (B2-T7).
- **Rapport de modlist exportable** Markdown/HTML (E2-T1), guide de
  coexistence des gestionnaires (E2-T2).
- Une liste fluide **à l'échelle réelle** : conçue et mesurée sur un parc
  de ~966 mods (pagination, tri localisé comme macOS — X73).

---

## 10. Ce que la concurrence a et que StarHubFR n'a pas (encore)

Un positionnement honnête vaut mieux qu'une liste parfaite :

| Manque | Statut | Concurrent qui l'a |
|---|---|---|
| Groupes/séparateurs pliables dans la liste | ouvert (**I-T21**) | Stardrop-NativeMac |
| Export/import de profils et packs distribuables | ouvert (**E1**) | Stardop (modpack léger) |
| Auto-update de l'app | non engagé (visé : Sparkle) | Stardop |
| Signature / notarisation / page Nexus | ouvert (**E2-T3**) | — |
| Multiples thèmes | non prévu | Stardop (12 thèmes) |

## 11. Pourquoi ces avantages sont durables

Ce ne sont pas des couches de paint sur un scanner : chaque axe repose sur
des **mesures contre le réel** — comportement de Newtonsoft exécuté depuis
la DLL du jeu, formats i18n du parc (UTF-16/32 réels), décompilation IL
des mods C#, archive Nexus dépecée octet par octet. C'est le coût d'entrée
que chacun de ces tableaux représente pour un concurrent, et la raison
pour laquelle « un autre Stardrop en français » n'est pas notre projet :
StarHubFR vaut par ce que Stardop ne fera pas, pas par ce qu'il fait
mieux.

---

*Vérifications d'usage : les affirmations « absent chez le concurrent »
datent des audits cités (2026-07-31 et 2026-10-04) ; les affirmation
« livré » sont celles du §11 de la roadmap, recoupées avec le code. Mettre
ce fichier à jour à chaque audit concurrent neuf, pas seulement à chaque
release.*
