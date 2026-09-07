# Audit Phase 3 — Persistance & données locales

**Date** : 2026-09-07
**Scope** : 16 fichiers Swift (~3 000 lignes) — secrets & clés, les neuf magasins
de persistance, récupération de fichiers et les trois managers de sauvegarde/réparation
**Reference** : `docs/prompt-audit.md` (phase 3), `AGENTS.md` §4.3/§4.6,
`docs/DOMAINE.md`, `docs/ROADMAP.md` §4 + archive
**Précédent** : Phase 1 (cœur applicatif, achevée par tranches — voir
`audit-phase1-2-2026-09-01.md` et l'index §11), Phase 2 réseau
(`audit-phase2-2026-09-07.md`, X78–X88)

---

## 1. Bilan

| Tranche | Fichiers | Lignes | Constats |
|---|---:|---:|---|
| A — secrets & clés (`UDKey`, `KeychainSecret`, `TokenShield`) | 3 | ~224 | 0 |
| B — les neuf `*Store` | 9 | ~800 | 1 (**X89**, site d'appel VM) |
| C — `FileRecovery`, `ModConfigBackupManager`, `ModInstallBackupManager`, `ModFolderRepairer` | 4 | ~1 990 | 1 (**X90**) |

Les deux constats sont des **silences résiduels** — une persistance dont l'échec
n'est dit nulle part alors qu'un succès est affirmé à l'utilisateur — pas des
pertes directes. Corrigés le jour même, build vert, 2 359 tests verts.

La Phase 2 avait laissé un point d'entrée : « `DeepLClient:9` — key en clair
dans `Credentials`, à vérifier Phase 3 ». **Faux positif** (§3, piste 1).

## 2. Constats

### X89 — le renommage d'un mod avalait l'échec d'écriture du suivi des traductions

`InstalledTranslationStore.save` rend `false` sur échec et son contrat dit que
l'appelant doit le dire. Neuf sites l'appellent dans le ViewModel ; huit
consomment le booléen et journalisent la conséquence. Le neuvième — la surface
12 du renommage X60 (`e43b32f`), `_ = InstalledTranslationStore.save(...)` —
l'avalait. Scénario : disque plein ou droits refusés au moment du renommage →
le registre **en mémoire** est renommé, le fichier non ; au redémarrage le
registre relu porte l'ancien hôte, la traduction posée ne se rattache plus au
mod renommé, et sa désinstallation ne retrouve plus les fichiers à retirer —
le « contraire du service rendu », selon les termes du store lui-même.
Correctif : l'idiome des huit voisins (`if !save { log(…, level: .warning) }`).

### X90 — `ModConfigBackupManager.saveIndex` se taisait en échec

`createBackup` copie les fichiers puis écrit l'entrée d'index ; la copie
réussie consomme du disque, et l'écriture de `metadata.json` peut échouer
juste après (disque devenu plein entre les deux). La sauvegarde **complète**
existe alors sur disque, `createBackup` la rend comme créée, mais aucune liste
ne la montre — et l'écran Entretien la propose à la purge comme orpheline, puis
qu'elle est un dossier sans entrée d'index. Le manager jumeau
`ModInstallBackupManager.saveIndex` dit exactement cet échec depuis l'audit du
2026-08-05 (`dd6b4d1` : `print("CRITICAL: … backups may be orphaned")`) — deux
fichiers miroirs, l'un avait appris, l'autre non. Correctif : alignement sur le
jumeau. La contrepartie : `print_calls` monte de 23 à 24 au cliquet, relevé
avec `--update` (idiome déjà celui du jumeau et des quatre `print` de ce
fichier) ; `try_optional` descend de 305 à 303 dans le même diff.

## 3. Pistes écartées, avec la mesure ou la lecture qui les ferme

1. **« Clé DeepL en clair » (renvoi Phase 2)** — faux positif. La clé vit au
   trousseau (`KeychainSecret.deepLApiKey`, VM `setDeepLKey`/`clearDeepLKey`) ;
   `DeepLClient.Credentials` n'est qu'un type de passage. Et la soumission
   d'une clé vide est gardée : `saveFallbackKey` trimpe et `guard !key.isEmpty`
   (`SettingsView.swift:731-732`), une entrée `""` au trousseau — qui rendrait
   `hasDeepLKey` vrai mais le secours mort — est inatteignable.
2. **Casse-exacte de `ModVersionAnchorStore`** — c'est **F6-T4**, ouvert et
   documenté (« à traiter d'un bloc ou pas du tout »). Ne pas re-signaler.
3. **`ModVersionAnchorStore.mutate` avale l'échec d'encode** — assumé par le
   fichier : les ancres se reposent sur constat, les perdre coûte une
   redécouverte, pas une donnée irremplaçable.
4. **`ModConfigBackupManager.renameMod` capture `changed` à travers deux
   `map` imbriqués** — un backup dont les items n'ont pas changé est
   reconstruit à valeurs identiques si un backup précédent a déjà armé le
   drapeau. Travail en plus, aucun observable.
5. **`TokenShield.unwrap` débaliserait un `<x>` littéral d'une réponse** —
   c'est le contrat du tag (il voyage pour être ignoré par le moteur), et la
   vérification a posteriori est `TranslationTokenCheck`, qui ne réinsère
   jamais une marque absente.
6. **`ModFolderRepairer.moveToTrash` rend `false` en silence** — documenté
   « never risk data loss » : l'item reste en place et le scan suivant
   retente. Le `_Trash_` préserve la structure relative, tout est restaurable
   à la main.
7. **`saveIndex` muette dans `deleteBackup`/`cleanupOldBackups`** (les deux
   managers) — un échec y laisse des entrées d'index fantômes : bénin, la
   restauration saute les sources absentes (`guard fileExists` →
   `skippedMods`), `mostRecentBackedUpFile` saute les fichiers absents, et la
   retentative au prochain geste réécrit l'index.
8. **`ModDetailCache.save` muette** — c'est un cache sous `Caches/`,
   reposable par contrat ; le JSON y est re-encodé depuis les types, pas une
   copie d'octets étrangers (le seul cas dangereux du dépôt, déjà corrigé).
9. **Drapeaux de migration one-shot toujours présents dans `UDKey`** —
   connu de la tranche racine : les retirer sans retirer la migration la
   ferait rejouer. Ménage délibéré, pas un défaut.
10. **Clés `UserDefaults` littérales hors `UDKey`** — grep sur tout le module :
    les seules chaînes `forKey: "…"` restantes sont des clés de **manifeste
    JSON** (`UniqueID`, `UpdateKeys`…), pas des préférences. Zéro collision.

## 4. Cross-références

- **Tableau X69** (les trois chemins qui touchent les magasins indexés par
  dossier : renommage 12 / suppression 5 / ménage 4) rejoué sur le périmètre :
  aucun magasin nouveau — tout ce que la Phase 3 a lu est couvert par le
  renommage X60. `GlossaryStore` et `ModCompatibilityStore` sont indexés par
  langue / `UniqueID`, hors tableau à raison.
- Les stores indexés par `UniqueID` (`ModVersionAnchorStore`,
  `ModConflictVerdictsStore`, `ModCompatibilityStore`) sont insensibles au
  renommage de dossier par construction — c'est le point d'indexer ainsi.
- `ModInstallBackupManager` n'a rien donné : X76 (`indexWasReadable`),
  rollback de restauration, mise de côté préfixée point, suppression robuste
  des permissions, purge sur empreinte d'octets et rétention hybride sont tous
  en place et commentés avec leurs mesures.

## 5. Verdict global

La persistance est **solide et homogène** : écritures atomiques partout,
verrous `NSLock` sur les deux index read-modify-write, la distinction
absent/illisible est systématique (`LoadOutcome` du glossaire, `.bak` promu du
registre des traductions, `indexWasReadable` des sauvegardes d'installation,
`orphanFileNames` qui refuse de conclure sur une liste vide de profils), et
les droits ouverts pour écrire dans un mod sont rendus tels quels
(`RecoveredFileWriter.withWriteAccess`), bornés au dossier de tête. Les deux
constats corrigés étaient les derniers silences du lot.

**Suite de l'audit global** (brief `prompt-audit.md`) : Phase 4 — `Tests/` et
`run_tests.sh`, puis Phase 5 — `Package.swift`, `Info.plist`, `build_app.py`,
`release.py` et les deux cliquets (en lecture).
