# Audit ModTRANS — traducteur de mods par IA externe

> **Date** : 2026-10-04 (jour de sa publication).
> **Objet** : **ModTRANS — Universal Mod Translator**, Nexus
> [53388](https://www.nexusmods.com/stardewvalley/mods/53388), v1 mise en ligne
> le 2026-10-04 à 18:45, un fichier, 0 endossement au relevé. Outil externe
> **Windows** (`.exe` autonome, GUI) : traduit les mods Stardew par IA **cloud**
> (OpenRouter, clé collée en clair dans `config.toml`).
> **Méthode et limite** : page Nexus seule (deux lectures le soir même ; le
> lecteur web passe la muraille anti-bot, `curl` reçoit une coquille de 5 Ko).
> Binaire fermé, sans dépôt public repéré — **rien de téléchargé ni exécuté**,
> aucun code lu : audit de conception à distance. L'auteur n'a pas été relevé
> par l'extraction (bloc absent du texte rendu) — à compléter au prochain
> passage. Chiffres = ceux affichés page.
> **Suivi** : rangée « Concurrents observés » de `docs/SOURCES.md` §5. Pas de
> sonde `check_sources.py` : rien à sonder (ni dépôt, ni API de notre part, et
> la page est sous muraille) — à reprendre si un dépôt apparaît.

---

## 1. Positionnement

Concurrent **indirect** de notre axe C (Traductions FR) : même geste — traduire
un mod que personne n'a traduit — mais depuis l'extérieur (outil autonome
Windows), cloud d'abord. Notre position : intégré à l'app macOS, IA locale
d'abord, glossaire unpacké, jetons vérifiés.

| | Leur réponse | Notre réponse |
|---|---|---|
| Moteur | OpenRouter (cloud), clé API **en clair** dans `config.toml` | IA locale d'abord (points compatibles OpenAI locaux) ; le contenu des mods ne quitte pas la machine |
| Cibles | `i18n/default.json`, texte codé en dur de `content.json` (« surgical injection »), `Description` du `manifest.json` | fichiers `i18n/` in-place + sidecar ; `content.json` codé en dur = **C3-T2, pesé et non engagé** (233 chaînes EN sur 11 packs du parc réel, 4 092 déjà FR) |
| Garde-fous | « AI Judge » ×2 optionnel (juge LLM répare les balises), statut BLOCK (l'IA se censure, laisse l'original) | vérification **déterministe** des jetons (3 formes composées, comptage), 6 garanties d'écriture, baselines |
| Revue | fenêtre de relecture manuelle | éditeur `fr.json` intégré, diff EN/FR, lignes refusées **corrigibles une à une** (`TranslationEditorView`, cas `.blocked(mismatches)`) |
| Déploiement | export automatique dans `Mods/` | écriture depuis l'app, baselines + restauration |
| Entrée | ZIP auto-dézippé | installation existante (ZIP comprise) |
| Sauvegarde | backup « caché » + bouton Restore | sidecar/baselines + backups d'installation |

## 2. Leurs angles morts (nos pièges déjà payés)

1. **Clé API en clair + contenu du parc vers un cloud tiers.** Position
   contraire à la nôtre, non négociable : parc de ~900 mods, textes d'auteurs,
   machine de l'utilisateur.
2. **« Surgical injection » dans `content.json` sans grammaire.** Le texte codé
   en dur vit au milieu de jetons (`{{…}}`, sélecteur de genre `${…}$`,
   conditions) : un LLM jugé par un LLM n'est pas une grammaire. Leur propre
   section « Troubleshooting » documente les échecs — BLOCK = l'IA « sent » le
   risque. Nous : jetons comparés exactement (et la leçon compte : un mauvais
   comptage de jetons nous refusait 1 092 traductions justes).
3. **`manifest.json` `Description` traduit.** Change les métadonnées du mod :
   diffs avec l'amont faux, journaux SMAPI qui portent la description traduite,
   retours d'auteur confus.
4. **Juges ×2 = jusqu'à trois passes LLM par lot.** Sur un parc de 900 mods :
   coût cloud et limite de débit ; notre passe locale reste gratuite et
   reproductible.
5. **Zéro notion de fraîcheur.** Ni baseline, ni « l'auteur a bougé son i18n
   depuis ta traduction » (notre `TranslationBaselines` + staleness EN/FR).
6. **Encodages et fins de ligne non mentionnés.** Le parc réel porte des i18n
   UTF-16/UTF-32 (BE et LE — notre `I18nFileDecoder`) et le CRLF compte pour un
   caractère en Swift (deux bugs, une fixture dédiée). Un outil naïf casse
   dessus en silence.

## 3. Ce qu'on en tire

**Rien à porter.** Leurs différenciateurs sont soit contraires à nos positions
(cloud, clé en clair, manifeste traduit, auto-déploiement sans revue), soit
déjà couverts chez nous :

- la file des lignes refusées corrigibles une à une **existe**
  (`TranslationEditorView`, `.blocked([TranslationTokenCheck.Mismatch])`) ;
- la relecture avant écriture **existe** (éditeur intégré, diff) ;
- le « juge » nous paraît inférieur à la vérification déterministe des jetons,
  qu'on fait déjà localement.

Leur centre — `content.json` codé en dur — est exactement notre C3-T2 :
**mesuré** (233 chaînes EN sur 11 packs, 192 dans un seul, noyées dans 4 092
déjà françaises) et clos sans code le 2026-10-02. Leur pari ne change pas la
mesure : le verdict devrait juger la langue, pas l'absence de `{{i18n}}`.

**Menace** : nulle à court terme — jour 1, 0 endossement, Windows seul, sans
dépôt. À revoir si : dépôt public (audit de code), port macOS, ou adoption
réelle.

## 4. Ce que cet audit ne dit pas

Tout ce qui vit dans le binaire : format du backup « caché », réel respect des
jetons, gestion des erreurs réseau. Aucune exécution, aucun octet lu — les
points §2.2 et §2.5 sont des inférences de conception, étiquetées comme telles.
