# Audit — codes de jeu dans les traductions françaises du parc *(2026-09-29)*

Parti du libellé « Activer le Profilateur » d'UltraSmooth (en réalité « passer
l'intro », [`audit-ultrasmooth-2.4.0.md`](audit-ultrasmooth-2.4.0.md)).

**Ce que n'est pas `TranslationBaselines/`.** La référence par clé n'est pas la
sortie du hub : elle photographie ce que l'anglais et le français disaient **le
jour où l'app les a vus** (`TranslationBaseline.swift`). Une traduction
communautaire déjà décalée ce jour-là y entre telle quelle. Rien ne montre que
le `fr.json` d'UltraSmooth (8 septembre, absent du registre
`installed_translations.json`) vienne du hub.

## Méthode

Pour chaque dossier `i18n` actif ayant `default.json` et `fr.json`, comparer
clé par clé les **codes de jeu** : portraits (`$0`–`$9`, `$h $s $u $l $a $k`),
coupures de bulle (`#$b#`, `#$e#`), narration (`%` en tête), commandes
(`$q $r $p $d $y $c $k`), jetons `{{…}}` — sélecteurs de genre `${…^…}$` retirés
d'abord (le français en ajoute à raison, mémoire
`gender-selector-is-not-a-token`). Les nombres en prose ne sont pas un signal :
« 8-legged » → « huit pattes » est juste.

## Résultat sur disque

**446 clés sur 24 140** traduites (118 mods) ont des codes divergents ; **aucune
question ni réponse `$q`/`$r`** touchée.

| Mod | Clés | Portraits seuls (réparable) | Structure changée |
|---|---|---|---|
| Cropgenics | 385 / 4 694 | 254 | 131 |
| Cape Stardew 1.6 | 49 / 821 | 4 | 45 |
| Cornucopia Cooking Recipes | 8 | | |
| AutoForager, Evelyn Expansion, StardewGallery, Downhill Project | 1 chacun | | |

- **Cropgenics** : traduction installée pour la **1.2.6.2** (registre des
  traductions), mod en **1.4.3** — l'auteur a changé des portraits et redécoupé
  des bulles depuis.
- **Cape Stardew (Annetta)** : portraits **ajoutés** par le traducteur ; une
  question rapide `$y` (`Annetta.Schedule.Dialogue.004`) a perdu sa question —
  les réponses et leurs suites sont décalées, le dialogue s'affiche faux.
- La référence du premier jour signalait bien plus (1 458) : Ridgeside, SVE,
  East Scarp y figuraient, mais leurs fichiers actuels sont propres.
