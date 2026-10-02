# Guide utilisateur — StarHubFR

Les réponses aux trois questions qui reviennent quand un autre gestionnaire de
mods a déjà touché au jeu, ou qu'on veut retirer StarHubFR proprement. Pour ce
que l'app sait faire, voir le [README](README.md).

## Coexistence avec les autres gestionnaires

StarHubFR, Vortex, Stardrop et le Nexus Mods App lisent **le même dossier**
`Mods/` du jeu. Ils ne se contredisent pas en mémoire, mais :

- **Un seul outil bascule les mods à la fois.** Une pause chez StarHubFR est un
  dossier préfixé d'un point (`.X`) ; Vortex et Stardrop l'ignorent ou le
  marquent autrement. Si vous passez d'un outil à l'autre, remettez tous les mods
  dans l'état voulu avec **un seul** des deux.
- **L'installation se fait une fois pour toutes.** Un mod installé par
  StarHubFR est un dossier ordinaire dans `Mods/` : Vortex et Stardrop le voient
  comme s'il avait été posé à la main. Rien à refaire.
- **Le lancement passe par SMAPI**, pas par le gestionnaire : un mod installé
  tourne pareil quel que soit l'outil qui l'a posé.

## La convention `X` / `.X` : un mod en pause n'est pas un mod supprimé

Mettre un mod en pause renomme son dossier en le **préfixant d'un point** :
`Mods/ColorfulVolume` devient `Mods/.ColorfulVolume`. C'est la même convention
que SMAPI : un dossier à point n'est pas chargé.

Trois conséquences pratiques :

- **Le Finder cache ces dossiers** (`⇧⌘.` les montre). Un mod « disparu » du
  jeu mais présent dans l'espace disque est presque toujours un mod en pause.
- **Ne triez pas à la main** : les dossiers à point de `Mods/` sont vos mods en
  pause, pas des fichiers cachés à nettoyer. StarHubFR les liste et les fait
  revenir d'un clic.
- **Les sauvegardes de partie se souviennent des mods actifs.** Réactiver un
  mod en pause remet les choses en ordre ; supprimer son dossier non.

## Avant de désinstaller StarHubFR

Les mods mis en pause vivent dans des dossiers cachés de `Mods/`. Si vous
retirez StarHubFR sans les remettre, le jeu ne les chargera plus et ils
sembleront perdus.

1. Dans **Gestion des mods**, réactivez tous les mods : le menu de bascule
   groupée (« Tout activer ») fait le travail en un geste.
2. Vérifiez qu'il ne reste aucune ligne en pause (le cadrage « En pause » de la
   liste les compte).
3. Quittez StarHubFR. Le dossier `Mods/` est alors un dossier SMAPI ordinaire —
   le jeu, SMAPI et les autres gestionnaires n'ont besoin de rien d'autre.

Les données propres à l'app (favoris, notes, historique, traductions en cours)
vivent dans `~/Library/Application Support/StarHubFR/` : les supprimer n'est
nécessaire que si vous voulez effacer aussi ces souvenirs.
