# Politique de sécurité

*[English version below](#security-policy).*

## Versions suivies

Seule la [dernière version publiée](../../releases/latest) reçoit des correctifs.

## Ce qui compte comme une faille

StarHubFR télécharge, décompresse et installe des archives de mods (`.zip`, `.7z`, `.rar`), écrit dans le dossier du jeu, garde une clé API Nexus dans le trousseau macOS et peut appeler un service de traduction. Une faille, par exemple :

- une archive qui écrit hors du dossier `Mods/` (chemin `../`, lien symbolique) ou contourne les limites de taille ;
- une clé API qui fuit (journal, fichier en clair, requête vers un autre domaine) ;
- un fichier de mod ou de configuration qui fait exécuter du code par l'app ;
- un lien `nxm://` forgé qui déclenche une action non voulue.

Un mod malveillant en lui-même n'est pas une faille de StarHubFR : signalez-le à Nexus Mods.

## Signaler une faille

**N'ouvrez pas d'issue publique.** Utilisez le signalement privé de GitHub : onglet **Security** du dépôt, puis **[Report a vulnerability](https://github.com/mrbabilo/StarHubFR/security/advisories/new)**. Seuls vous et le mainteneur voyez le rapport.

Indiquez :

1. la version de StarHubFR et de macOS ;
2. les étapes pour reproduire, avec l'archive ou le fichier en cause si possible ;
3. l'effet obtenu.

Vous recevez une première réponse sous sept jours. Le correctif sort dans une nouvelle version, et le rapporteur est crédité dans le CHANGELOG, sauf s'il préfère l'anonymat.

## Bonnes pratiques

- Téléchargez les mods depuis leur page officielle (Nexus Mods, ou le dépôt de leur auteur).
- Gardez StarHubFR à jour.
- L'app n'est pas notarisée : téléchargez-la uniquement depuis la [page Releases](../../releases) de ce dépôt.

---

# Security policy

## Supported versions

Only the [latest release](../../releases/latest) receives fixes.

## What counts as a vulnerability

StarHubFR downloads, extracts and installs mod archives, writes into the game folder, keeps a Nexus API key in the macOS Keychain and may call a translation service. Examples: an archive writing outside `Mods/` (`../` paths, symlinks) or bypassing size limits; an API key leaking; a mod or config file making the app run code; a crafted `nxm://` link triggering an unwanted action. A malicious mod by itself is not a StarHubFR flaw: report it to Nexus Mods.

## Reporting

**Do not open a public issue.** Use GitHub's private reporting: the repository's **Security** tab, then **[Report a vulnerability](https://github.com/mrbabilo/StarHubFR/security/advisories/new)**. Include the StarHubFR and macOS versions, steps to reproduce, and the impact. You get a first answer within seven days; the fix ships in a new release and the reporter is credited in the CHANGELOG unless they prefer otherwise.
