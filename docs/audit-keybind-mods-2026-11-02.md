# Trois mods de raccourcis décompilés — 2026-11-02

Keybind Sheet 1.0.1, MLD's Keybind 0.2.0 et Taum's Inventory Hotkeys 1.0.3,
pris dans le parc où ils sont en pause. Analyse statique seulement : aucun des
trois n'a été lancé, rien n'a été téléchargé. Aucun n'a de dépôt de sources
public. Les notes détaillées, sans code recopié, vivent hors du dépôt :
`~/Outils/analyses/{keybindsheet-1.0.1,mldkeybind-0.2.0,taumshotkeys-1.0.3}/mecaniques.md`.
Elles complètent [`audit-keybind-radar-savesaver.md`](audit-keybind-radar-savesaver.md)
et l'entrée hotkey hub de [`SOURCES.md`](SOURCES.md) §5.

## Ce que cela change pour StarHubFR

- **Corrigé le jour même : restaurer des configs jeu ouvert.** La restauration
  d'une sauvegarde de configs ne regardait pas si le jeu tournait. Or un mod
  chargé réécrit son `config.json` au prochain enregistrement de ses réglages,
  et MLD's Keybind en déclenche à chaque changement : la restauration était
  défaite sans un mot. La confirmation nomme désormais les mods restaurés qui
  sont actifs pendant que le jeu tourne (`ConfigRestoreWhileRunning`), comme le
  bandeau de l'éditeur de config. Elle prévient, elle ne bloque pas.
- **Taum's Inventory Hotkeys fabrique de fausses collisions.** Son `config.json`
  porte une copie des boutons du profil actif, et `Tabs[].Keybinds` contient les
  touches **des autres mods**, qu'il rejoue. Notre `KeybindScanner` les prend
  pour des liaisons du mod. La règle du catalogue (plus de 8 combinaisons) les
  écarte pour le profil 2 (15), pas pour le profil 5 livré (8 exactement) : huit
  fausses collisions, contre UltraSmooth, Automate, MultiSave et d'autres. Ses
  boutons à la souris (`ActivateMouse`, `EditMouse`) sortent en conflit avec les
  contrôles du jeu alors qu'ils n'écoutent que sur ses propres éléments de
  l'inventaire. Piste : une entrée dans `assets/keybind-contexts.json` et une
  règle « touches émises » pour ce champ (hotkey hub relève de la même).
- **Taum's : la mise à jour garde bien les profils.** Mesuré dans le journal
  d'installation : aux mises à jour du 2026-11-01 et du 2026-11-02, le tri
  A1-T11 a gardé les quatre profils modifiés comme retouches et le profil 6
  comme fichier local. Le risque restant est une installation sans référence
  d'auteur (dépôt manuel sans manifeste Nexus en cache), où les profils
  d'exemple de l'archive remplacent ceux de l'utilisateur dans le dossier actif.
- **Taum's : une mise à jour qui renaît.** Le manifeste dit 1.0.3 et n'a pas
  d'`UpdateKeys` ; les fichiers Nexus sont numérotés « 6 », « 7 », « 9 », dont
  deux DLL différentes sous 1.0.3. Le journal connaît le fichier installé
  (`nexusFileId` 189589), l'ancre de version ne le porte pas : la protection X9
  ne peut pas jouer, et « 7 » ou « 9 » l'emporte toujours sur 1.0.3 dès que
  l'identifiant Nexus est connu.
- **Keybind Sheet garde des données non régénérables dans des fichiers livrés.**
  Les notes saisies en jeu sont réécrites dans `assets/catalog.json`, que la
  mise à jour suivante remplace. Il garde aussi `translation.cache.json`,
  `catalog.pack.json`, `catalog.pending.json`, `keybinds.csv` et
  `catalog.json.bak` à la racine de son dossier (régénérables). Ses clés d'API
  de traduction (DeepL, Google, OpenAI, DeepSeek) sont **en clair** dans son
  `config.json` (vides sur le parc) : notre éditeur de config les afficherait
  telles quelles.
- **MLD's Keybind écrit plus tôt et plus large que son README.** Dès la première
  ouverture de son tableau (F9), l'apprentissage des valeurs par défaut peut
  appeler le `Reset` puis le `Save` d'un autre mod : le `config.json` d'un mod
  jamais touché est réécrit, et ses réglages absents de GMCM reviennent à leurs
  défauts. Réaffecter un raccourci remplace toute la liste par une seule
  combinaison : la touche manette d'une liste « F5, LeftStick » est perdue.
  C'est l'inverse de `KeybindPlanWriter`, qui ne touche qu'une alternative.
  Il lit GMCM par réflexion sur ses internes, sans contrôle de version (les
  noms visés existent dans GMCM 1.16.0, la version installée). Notre plan de
  réaffectation est protégé (refus jeu ouvert, écriture depuis le texte
  courant, annulation refusée si le fichier a changé) : le risque est un plan
  périmé, pas une perte.

## Comparaison avec notre scanner

| | Keybind Sheet | MLD's Keybind | StarHubFR |
|---|---|---|---|
| Source | JSON sur disque | registre GMCM (réflexion) | JSON sur disque |
| Mods en pause | lus (dossiers pointés parcourus) | invisibles (pas chargés) | lus, collisions latentes |
| Raccourci reconnu par | la valeur, le nom classe | le type de l'option GMCM | grammaire, nom et valeur (R1-R4) |
| Vanilla | 26 contrôles (le README dit 27) | options du jeu | `GameControlDefaults` + préférences |
| Conflits | chaîne entière, trois couleurs | dernière touche de la première combinaison | signatures canoniques, contextes |
| Écrit | son dossier seulement | configs des autres mods, `default_options` | plan explicite, jeu fermé |

Ni l'un ni l'autre n'a de notion de contexte (menu ou jeu).

## Idées retenues, à peser

- **La règle orange de Keybind Sheet** : une touche seule masquée par la
  combinaison d'un autre mod qui la contient, calculée sur nos signatures.
- **Les changements en attente de MLD** (Annuler, Tout jeter, Appliquer),
  écrits par fichier en une fois.
- **Les défauts par réglage**, lus hors jeu sur la classe de config d'un mod.
- **Le relais mort de Taum's**, réimaginé : signaler un bouton dont la
  combinaison n'est liée par aucun mod actif.

## Cadre

Décompilation à fin d'interopérabilité (CPI, art. L122-6-1 IV) : faire lire
correctement à StarHubFR les configs et les données de mods installés. Keybind
Sheet est sous licence MIT ; MLD's Keybind et Taum's Inventory Hotkeys n'en
déclarent aucune. Aucun code repris ; DLL et exports hors de Git, non
redistribués.
