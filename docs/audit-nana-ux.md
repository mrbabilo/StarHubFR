# Audit UX/UI — `Nana1873/stardew-i18n-translator`

Analyse de l'interface du seul outil comparable au hub de traduction de
StarHubFR. Pendant de [`audit-stardrop.md`](audit-stardrop.md), qui couvre la
gestion de mods ; celui-ci ne parle que de **traduction**.

**Licence GPL-3.0, incompatible avec notre MIT** : rien n'est recopié. On lit des
décisions d'interface, on en retient le principe. Chaque constat ci-dessous a été
vérifié dans les sources, pas déduit d'une capture.

Relevé le 2026-08-03 sur `main`. React + Tauri, CSS maison sans framework,
`@tanstack/react-virtual` pour les listes. Six écrans : `dashboard`, `mods`,
`strings`, `results`, `settings`, `setup`.

---

## 1. La règle qu'ils écrivent noir sur blanc

`src/strings/status.ts` porte ce commentaire, qui vaut mieux que la plupart des
chartes :

> *Design rule: a status is always shown as hue + glyph (+ 3px row edge in the
> table) — **any one signal alone is sufficient**. Gold is reserved for
> brand/selection and must never appear here.*

Deux principes en une phrase :

1. **Redondance du codage.** Aucun état ne tient à la seule couleur. Un daltonien
   lit le glyphe ; un balayage rapide lit la teinte ; le liseré de 3 px situe la
   ligne. C'est la bonne pratique d'accessibilité, appliquée sans se donner des
   airs.
2. **Réserve chromatique.** L'or appartient à la marque et à la sélection ; il ne
   dit jamais un état. Sans cette réserve, une couleur finit par vouloir dire
   deux choses.

**Chez nous** : la pastille de couverture suit le premier principe — le taux
écrit est le second signal, la couleur ne fait que le renforcer. Le second n'a
pas d'équivalent formulé : notre vert sert à la fois « mod actif » (barre
d'accent de la ligne) et « traduction complète ». À trancher si un troisième
usage apparaît.

### Leur vocabulaire de statuts

| statut | glyphe | couleur | ce qu'il dit |
| --- | --- | --- | --- |
| `untranslated` | `○` | gris | rien n'a été fait |
| `translated` | `✓` | vert | fait |
| `outdated` | `↻` | violet | la source a changé depuis |
| `review-needed` | `⚑` | orange | fait, mais à vérifier |

Les deux derniers n'existent pas chez nous et supposent une **baseline stockée**
— ils relèvent de notre phase 2 (C2-T2). Le violet pour « obsolète » est un choix
juste : ni alarmant comme le rouge, ni satisfait comme le vert.

---

## 2. La ligne de mod

`src/mods/ModList.tsx`, `ProgressCell` : une **barre de 5 px suivie du
pourcentage**, jamais le nombre seul.

- La barre donne la comparaison instantanée en balayage ; le nombre donne la
  précision quand on s'arrête. Deux rôles, deux éléments.
- `font-variant-numeric: tabular-nums`, `min-width: 30px`, `text-align: right` :
  les pourcentages s'alignent verticalement d'une ligne à l'autre. Sans cela,
  chaque valeur danse et la colonne devient illisible.
- `—` explicite quand il n'y a **rien** à traduire — distinct de « 0 % ».
- Vert uniquement à 100 % ; or sinon.
- Les composants d'un même paquet sont **groupés**, avec les compteurs
  additionnés (`groupByPackage`) — comme nos packs multi-composants.

**Repris** : la chasse fixe sur les chiffres (`.monospacedDigit()`), pour la même
raison qu'eux.

**Écarté** : la barre dans la liste. Notre ligne de métadonnées porte déjà le
globe, les codes de langue, la date de mise à jour et la date d'installation, là
où ils disposent d'une colonne dédiée dans un tableau. La barre a sa place sur la
**fiche mod** (C1-T3), où l'espace existe.

**Défaut à ne pas reprendre** : `Math.round(progress * 100)`. Un mod à 99,6 %
affiche « 100 % ». Nos tests l'interdisent explicitement — annoncer un travail
terminé qui ne l'est pas est le seul arrondi qu'un tel badge ne peut pas se
permettre.

---

## 3. Le tableau de bord

`src/dashboard/Dashboard.tsx` ouvre sur quatre cartes. Deux méritent d'être
transposées :

- **« Overall translated »** — un pourcentage global avec sa barre.
- **« In progress — mods between 1–99% »** — la liste vraiment utile. Sur le parc
  de référence : 392 mods complets, **31 partiels**. Ce sont ces 31 qu'on veut
  voir, et ils sont aujourd'hui noyés parmi les autres.

Le reste (salutation selon l'heure, gros bouton de scan) tient à leur modèle :
une application dont la traduction est **l'unique** objet. StarHubFR est un
gestionnaire de mods ; sa page d'accueil a d'autres devoirs.

---

## 4. L'éditeur de chaînes — pour nos phases 2 et 3

`src/strings/StringTable.tsx`, à relire quand on ouvrira l'édition :

- **Table virtualisée** (`useVirtualizer`) : indispensable au-delà de quelques
  milliers de lignes. `East Scarp NPCs` en compte 11 021 à lui seul, et notre
  vue diff les affichera.
- **Tri par colonne** (statut, fichier, clé, source, cible) et **filtre par
  statut**, avec le **compte par statut affiché dans le libellé du filtre** — on
  sait ce qu'on va trouver avant de cliquer.
- **Séparateurs de section** entre les runs de lignes d'un même fichier : la
  table reste lisible quand plusieurs fichiers sont fusionnés.
- Une **échappatoire quand la recherche ne donne rien** (réinitialiser recherche
  et filtre d'un geste) — le détail qui évite l'impasse.
- Le double-clic ouvre l'éditeur ; la ligne se met à jour sur place après
  enregistrement, sans rechargement.

---

## 5. Hygiène générale

`:focus-visible` et `prefers-reduced-motion` sont présents dans leur CSS, et les
régions portent des `aria-label`. Notre application applique cela de façon
inégale — c'est une dette à traiter globalement, pas au fil de l'eau.

---

## 6. Ce qu'on en fait

| Constat | Décision |
| --- | --- |
| Chiffres à chasse fixe | **Repris** (`beda7ed`) |
| Redondance couleur + second signal | **Déjà appliqué** sur la pastille |
| Barre de progression | **Prévu** sur la fiche mod — C1-T3 |
| Carte « mods entre 1 et 99 % » | **À prévoir** — la liste utile |
| Statuts `outdated` / `review-needed` | **Phase 2**, supposent une baseline (C2-T2) |
| Table virtualisée + filtre par statut compté | **Phase 2**, pour la vue diff |
| Réserve chromatique explicite | À trancher si le vert prend un troisième sens |
| `Math.round` du pourcentage | **Écarté** — nos tests l'interdisent |
| Barre dans la ligne de liste | **Écarté** — notre ligne est déjà dense |
