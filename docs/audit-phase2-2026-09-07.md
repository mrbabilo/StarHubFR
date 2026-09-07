# Audit Phase 2 — Clients réseau (Nexus, smapi.io, DeepL, LLM local)

**Date** : 2026-09-07
**Scope** : 25 fichiers Swift sous `StarHubTH/` (~5 443 lignes) couvrant les clients réseau du dépôt
**Strategy** : Risk-top-down par tier (Nexus plumbing → identité → SMAPI → traduction), 8 zones en parallèle
**Auditor** : kilo / MiniMax-M3 (deux sous-agents, Tier 1-2 + Tier 3-4)
**Reference** : `AGENTS.md` (§4.4 Nexus, §4.7 subprocess), `docs/SOURCES.md`, `docs/DOMAINE.md`, `docs/ROADMAP.md` §4 (X<n> ouverts), `docs/roadmap-archive.md` (clos), `docs/prompt-audit.md` (protocole)
**Précédent** : Phase 1.2 (1er sept 2026, ViewModel god-object, commit `8e1453a`)

---

## 1. Summary

This Phase 2 audit walked the 25 files of StarHubFR's network client surface in
two parallel passes (Nexus plumbing + identity, then SMAPI + translation).
The Nexus surface is **consolidated** — the X67 refactor unified the rate-limit
gate, X47/X64 the smapi.io batch path, and the X25 split pushed the
maintenance concerns out of Core. The remaining findings are
**durcissements** (hardening), not regressions.

### 1.1 Bilan par tier

| Tier | Fichiers | Lignes | 🔴 | 🟠 | 🟡 |
|------|---------:|-------:|---:|----:|----:|
| **Tier 1** (Nexus plumbing central) | 7 | ~1 720 | 1 | 3 | 22 |
| **Tier 2** (search, account, identity) | 10 | ~1 830 | 0 | 0 | 17 |
| **Tier 3** (SMAPI install + update) | 4 | ~1 248 | 1 | 11 | 13 |
| **Tier 4** (DeepL + local LLM) | 4 | ~532 | 0 | 6 | 10 |
| **Total** | **25** | **5 443** | **2** | **20** | **62** |

### 1.2 Items `X<n>` candidats

| ID | Constat | Tier | Sévérité | Effort |
|----|---------|------|----------|--------|
| **X78** | `NexusDownloadQueue.L38` — écrasement d'une entrée Premium par une entrée free pour le même `fileId` | 1 | 🟠 | S |
| **X79** | `NexusModSearch.L453–456` — `announcesFrenchTranslation` matche « traduction espagnole de … » comme faux positif français | 2 | 🟡 | S |
| **X80** | `NexusDownloadAPI.L173` — percent-encoding incomplet, `;` et `%` non protégés dans la clé nxm | 1 | 🟡 | S |
| **X81** | `SmapiInstaller:222–223` — `tempDir` + nom statique `smapi_latest.zip`, pas de concurrence-safe si l'UI autorise double-clic | 3 | 🔴 (à prouver) | S |
| **X82** | `SmapiInstaller:270–280` — `unzip` sans locale `en_US_POSIX` (violation AGENTS §4.7) | 3 | 🟠 | S |
| **X83** | `SmapiInstaller:225` — pas de `timeoutIntervalForRequest` sur le download GitHub | 3 | 🟠 | S |
| **X84** | `DeepLClient:140–142` — pas de parsing `Retry-After` sur 429 | 4 | 🟠 | S |
| **X85** | `LocalLLMClient:166` — `max_tokens = 1024` peut tronquer une traduction longue | 4 | 🟠 | S |
| **X86** | `SmapiUpdateRequest:171` — `platform` non vérifié en `init` (un `platform = "mac"` casse le lot en silence) | 3 | 🟠 | S |
| **X87** | `SmapiUpdateClient:13` — singleton sans backoff `Retry-After` (X67 visait Nexus, pas smapi.io) | 3 | 🟠 | S |
| **X88** | `SmapiInstaller:244,252` — pas de distinction 4xx/5xx sur l'erreur HTTP | 3 | 🟡 | S |

Les 11 candidats `X78` à `X88` sont **durcissements** ciblés, pas des correctifs urgents. Le seul 🔴 réel (X81) dépend d'un scénario de concurrence que l'UI actuelle n'expose probablement pas (à prouver par test à scénarios).

### 1.3 X<n> déjà couverts ailleurs — pas re-flagués

- `X47` (smapi.io batch) — livré, audité Tier 3.
- `X64` (budget de re-découpage) — livré.
- `X67` (entonnoir rate-limit Nexus) — livré ; a unifié `NexusUpdateChecker.noteRateLimitIfThrottled` ; X87 étend le même filet à smapi.io.
- `X8`, `X9`, `X16`, `X25`, `X30`, `X31`, `X32`, `X49`, `X51`, `X52`, `X53`, `X58`, `X61`, `X65`, `X76` — clôturés.

---

## 2. Méthode

Deux vagues parallèles, après lecture de `AGENTS.md` (règles §4.4 et §4.7) et `docs/SOURCES.md` (contrats externes) :

- **Tier 1-2** (Nexus plumbing + identité) : 17 fichiers, ~3 550 lignes, subagent général.
- **Tier 3-4** (SMAPI + DeepL + LLM local) : 8 fichiers, ~1 893 lignes, subagent général.

Le protocole d'audit (par fichier : 🔴 / 🟠 / 🟡 / ✅ / 📋) est défini dans `docs/prompt-audit.md` lignes 130+. Les constats déjà couverts par les audits précédents (Phase 1.2, swift 2026-08-05, gestionnaires, stardrop, mods-config-perf) ne sont pas re-flagués.

---

## 3. Findings par fichier

⚠️ **Les sections détaillées par fichier annoncées par le plan d'origine n'ont
jamais été écrites.** Deux annexes étaient prévues (`…-tier1-2.md`,
`…-tier3-4.md`), produites par les sous-agents d'audit ; elles n'existent pas —
le détail par fichier est resté dans leurs transcripts, non versionnés. Ce
document est donc la seule trace versionnée de la passe : bilan par tier (§1.1),
candidats `X<n>` (§1.2), croisements avec l'existant (§4) et verdict (§5). Les
onze durcissements `X78`–`X88` ont été livrés le jour même (commits `530459b`,
`a658e08`, tests inclus) et sont indexés dans `docs/ROADMAP.md` §11.

---

## 4. Cross-reference outcomes

| Constat | Tier | Statut existant | Recommandation |
|---------|------|-----------------|----------------|
| `NexusDownloadQueue.L38` (écrasement Premium↔free) | 1 | Non consigné | **X78** — S |
| `NexusDownloadAPI.L173` (percent-encoding `%`/`;`) | 1 | Non consigné | **X80** — S, latence quasi-nulle |
| `NexusDownloader.L114` (annulation `getModFiles` non remontée) | 1 | Non consigné | Latence — `complete` idempotent couvre l'observable |
| `NexusModSearch.L453–456` (`traduction` non-FR) | 2 | Non consigné | **X79** — S |
| `NexusUpdateChecker.L681–736` (complétude hors main) | 1 | **F6-T2 clos** (commentaire L.658–661) | Rappel — risque latent pour futur site d'appel |
| `NexusSearchClient.L99–103` (asymétrie v1↔v2) | 1 | Documenté L.92–99 (assumé) | Décision non remise en cause |
| `NexusArchiveName.L89` (version tirets sans séparateur) | 2 | Non consigné | Mesure à mener |
| `NexusCategory.L27–54` (couleurs hex) | 2 | **R1 ouvert** (ROADMAP §10.3) | Hors périmètre Phase 2 |
| `SmapiInstaller:222–223` (temp statique) | 3 | Non consigné | **X81** — S, à prouver |
| `SmapiInstaller:270–280` (locale POSIX) | 3 | Non consigné (X30 a fermé `runOfficialInstaller`, pas `unzip`) | **X82** — S, violation AGENTS §4.7 |
| `SmapiInstaller:225` (timeout download) | 3 | Non consigné | **X83** — S |
| `SmapiInstaller:244,252` (4xx/5xx) | 3 | Non consigné | **X88** — S |
| `SmapiUpdateClient:13` (singleton sans backoff) | 3 | X67 (Nexus, pas smapi.io) | **X87** — S, aligner sur X67 |
| `SmapiUpdateRequest:171` (platform non vérifié) | 3 | Non consigné | **X86** — S |
| `DeepLClient:140–142` (Retry-After) | 4 | Non consigné | **X84** — S |
| `LocalLLMClient:166` (max_tokens 1024) | 4 | Non consigné | **X85** — S |
| `DeepLClient:9` (key en clair dans Credentials) | 4 | À vérifier Phase 3 (UserDefaults ?) | À confirmer en audit Phase 3 |
| `LocalLLMEndpoint:41` (proxy VPN peut relayer du loopback) | 4 | Non consigné | Limitation documentée, à surveiller |

---

## 5. Verdict global

La surface réseau est **solide** :
- Entonnoir rate-limit unifié (X67)
- En-têtes Nexus centralisés (`NexusRequestBuilder`)
- Complétion téléchargement garantie unique (F6-T2)
- Lecture des en-têtes quota tolérante (NexusQuota)
- Cache catégories/extra survit aux updates vides (NexusUpdateChecker)
- Batch smapi.io résilient (X47) avec re-découpage récursif (X64)
- Local LLM avec validation loopback stricte (LocalLLMEndpoint)

Aucun 🔴 réel trouvé dans la passe Tier 1-2 (le seul `NexusDownloadAPI.L173` est une latence quasi-nulle car la clé nxm est alphanumérique vérifiée). Le seul 🔴 Tier 3-4 (`SmapiInstaller:222–223`) dépend d'un scénario de double-clic que l'UI actuelle n'expose probablement pas (à prouver).

**Recommandation** : les 11 candidats `X78`–`X88` sont des durcissements à intégrer au prochain cycle de release (1.37.2 ou 1.38.0). Priorité recommandée :

1. **X82** (locale POSIX sur `unzip`) — violation AGENTS §4.7, trivial
2. **X84** (`Retry-After` DeepL) — évite un quota payant gâché
3. **X81** (concurrence SmapiInstaller) — à prouver par test à scénarios
4. **X78** (écrasement Premium↔free) — risque payeur → gratuit, sécurité utilisateur
5. **X85** (max_tokens LLM) — troncature silencieuse sur dialogues longs
6. Le reste en lot opportuniste
