# Signature de StarHubFR

Décision du 2026-10-15 : **pas de notarisation** (pas d'abonnement Apple
Developer). Gatekeeper avertit donc toujours au premier lancement d'une app
téléchargée — Réglages Système › Confidentialité et sécurité › « Ouvrir quand
même », ou Sentinel (voir le README). Ce qui suit ne lève pas cet avertissement ;
ça donne une identité stable à l'app et une preuve d'origine aux releases.

## 1. Certificat auto-signé — identité stable de l'app

Une signature ad hoc (`codesign -s -`) change à chaque build : le Trousseau
redemande alors l'accès à la clé Nexus après une mise à jour. Avec un
certificat, l'exigence de signature reste la même d'un build à l'autre.

À faire **une fois**, sur la machine qui compile :

1. Trousseau d'accès › menu Trousseau d'accès › Assistant de certification ›
   **Créer un certificat…**
2. Nom : `StarHubFR Signature` · Type d'identité : **Racine auto-signée** ·
   Type de certificat : **Signature de code** · Créer.
3. Dans le trousseau « session », double-cliquer le certificat › **Se fier** ›
   « Signature de code » : **Toujours approuver**. Fermer (mot de passe demandé).
4. Vérifier : `security find-identity -v -p codesigning` doit lister
   `"StarHubFR Signature"`.

Sans l'étape 3, `codesign` refuse le certificat (« no identity found », vérifié
le 2026-10-15) et `build_app.py` retombe sur la signature ad hoc en le disant.
Un autre nom : variable `STARHUBFR_SIGNING_IDENTITY`.

Au premier lancement signé par le certificat, le Trousseau demande une dernière
fois l'accès à la clé Nexus : « Toujours autoriser ».

**Sauvegarder le certificat** (Exporter… en `.p12`, avec un mot de passe) : le
perdre change l'identité, avec les mêmes redemandes qu'en ad hoc.

## 2. Empreinte des releases — `SHA256SUMS`

`release.py` écrit `bundles/SHA256SUMS` à côté du zip et le publie avec lui.
Pour vérifier un téléchargement, dans son dossier :

```bash
shasum -a 256 -c SHA256SUMS
```

## 3. Tags signés — « Verified » sur GitHub

À faire une fois :

```bash
ssh-keygen -t ed25519 -f ~/.ssh/starhubfr_signing -C "StarHubFR tags"
git config gpg.format ssh
git config user.signingkey ~/.ssh/starhubfr_signing.pub
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/starhubfr_signing.pub --type signing --title "StarHubFR tags"
```

Ensuite `release.py` crée le tag signé (`git tag -s`), le pousse, puis publie la
release sur ce tag (`gh release create --verify-tag`). Sans clé, il prévient et
laisse GitHub créer un tag non signé, comme avant.

Vérifier un tag en local demande la liste des signataires :

```bash
echo "$(git config user.email) $(cat ~/.ssh/starhubfr_signing.pub)" > ~/.ssh/allowed_signers
git config gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
git tag -v v1.67.0
```
