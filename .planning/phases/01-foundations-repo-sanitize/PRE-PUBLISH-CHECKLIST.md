# Pre-publish checklist — jarvis self-hosting v1

**Run by:** Antonio Castaldi
**Run at:** 2026-05-25T18:30:00+02:00 (local) — closing timestamp added post Publication
**Repo state pre-checklist:** working tree clean (`c764585`), 27 commits ahead of `origin/main` (`615feb4`)
**Checklist source:** PLAN `03-repo-publish-PLAN.md` modificato (Option A — vedi sezione "Architectural deviation accepted") + `.planning/research/PITFALLS.md` §6
**Decision per CONTEXT.md D-07:** reflog ~90gg post-publish risk accepted, no GitHub Support ticket.

---

## Architectural deviation accepted (Option A)

Il PLAN originale assumeva: repo PRIVATO → squash → force-push → flip a PUBLIC.

**Realtà verificata 2026-05-25T18:25 (gh api):**

```json
{"createdAt":"2026-04-28T07:13:12Z",
 "isPrivate":false,
 "nameWithOwner":"toto-castaldi/self-hosting",
 "pushedAt":"2026-05-12T14:38:44Z",
 "visibility":"PUBLIC"}
```

Il repo è **già PUBLIC dal 2026-04-28** (~30 giorni). Su `origin/main` HEAD = `615feb4 "rifare"` con README pre-sanitize che contiene UUID tunnel reale, IP DigitalOcean, email, hostname Lumio. I 27 commit locali (`.planning/`, scripts, README sanitizzato) **non sono mai stati pushati al remote.**

**Decisione utente (Option A, esplicitamente confermata):**
- Eseguire tutta la pre-publish checklist
- Force-push del nuovo orphan `public-v1:main --force-with-lease` per sostituire la canonical leaked history
- Step "flip visibility" → marcato SKIPPED (già PUBLIC; `gh repo edit --visibility public` sarebbe no-op)
- Nessuna mitigazione attiva oltre al force-push: GitHub Search re-indexa auto al push (~24h)
- Asset "leakati" sono identificativi pubblici (UUID, IP DO, email author-trailer, hostname DNS) → non richiedono rotazione

---

## Tooling installation (preliminare, non in scope dei 10 step PITFALLS)

| Tool | Stato pre-Plan 03 | Stato post-install | Method |
|------|-------------------|--------------------|--------|
| `gitleaks` | v8.21.2 (`~/.local/bin/gitleaks`) | unchanged | already present |
| `gh` | v2.86 (SSH auth, account `toto-castaldi`) | unchanged | already present |
| `trufflehog` | NOT installed | **v3.95.3** (`~/.local/bin/trufflehog`) | `curl -sSfL .../install.sh | sh -s -- -b ~/.local/bin` |
| `pre-commit` | NOT installed | **v4.6.0** (`~/.local/bin/pre-commit`) | `pip install --user --break-system-packages pre-commit` (pipx assente, apt richiede sudo password, fallback su pip user) |
| pre-push hook | not installed | installed (`pre-commit install --hook-type pre-push`) | hook file `.git/hooks/pre-push` (596 byte) |

`pipx` non installato e `sudo apt install pipx` richiede password — fallback su `pip install --user --break-system-packages` documentato come deviazione minore. Effetto user-level only, no system pollution.

---

## Step 0 — Full history backup (recovery path)

**Cmd:**
```bash
git bundle create ~/self-hosting-private.bundle --all
git bundle verify ~/self-hosting-private.bundle
```

**Output:**
- Bundle path: `/home/toto/self-hosting-private.bundle`
- Size: **455K**
- Verify: `is okay`, "The bundle records a complete history" (4 refs)

**Status:** [x] OK
**Timestamp:** 2026-05-25T18:29Z

**Razionale:** la squash a orphan butta via la history visibile (`615feb4 "rifare"`, `7d247ba "pre push"`, 5 commit GSD); il bundle resta sul laptop come safety net.

---

## Step 1 — Inventario stringhe sensibili (grep manuale) sul working tree

**Cmd:**
```bash
grep -rE '(toto-castaldi\.com|6b09204a|192\.168\.0\.72|192\.168\.0\.137|146\.190|188\.166|152\.42\.138|toto\.castaldi@|inspiron|remy\.ns|wanda\.ns)' --exclude-dir=.git --exclude-dir=.planning .
```

**Output:**

```
.gitleaks.toml:111:description = "Real subdomain of toto-castaldi.com — must be example.com in public docs"
```

**Analisi:** 1 match in `.gitleaks.toml` linea 111 — è la **regex literal** della rule `private-fqdn` che cerca leak di `toto-castaldi.com`. Il file `.gitleaks.toml` è already nella `[allowlist] paths` global. Non è un leak operativo, è il detector stesso. Accepted as expected.

**Status:** [x] PASS (0 real leak, 1 expected detector-literal match in allowlisted file)
**Timestamp:** 2026-05-25T18:29Z

---

## Step 2 — Gitleaks su HISTORY completa (pre-squash)

**Cmd:**
```bash
gitleaks detect --config .gitleaks.toml --no-banner --redact -v \
  > .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt 2>&1
```

**Output (43 finding, all in commit `7d247ba`):**

```
33 commits scanned
scan completed in 1.54s
leaks found: 43
gitleaks exit: 1
```

| Metric | Value |
|--------|-------|
| Total findings | **43** |
| Findings in commit `7d247ba9a65c00b9defa35ea27b832b38580461f` ("pre push") | 43 (100%) |
| Findings in commit `615feb4` ("rifare") | 0 |
| Findings in commit `c764585` (Plan 02 final, post-sanitize) | 0 |
| Findings in any Plan 01/02 GSD commit | 0 |

| RuleID | Count |
|--------|-------|
| `private-fqdn` (toto-castaldi.com subdomains) | 26 |
| `public-ipv4` (146.190.*, 188.166.*, 152.42.*) | 9 |
| `cf-tunnel-uuid` (6b09204a-...) | 4 |
| `cred-paths` (`/etc/cloudflared/*.json`) | 3 |
| `personal-email` (toto.castaldi@gmail.com) | 1 |

**Files affected:** README.md only (in commit `7d247ba`, which is `615feb4`'s ancestor → live on `origin/main`).

**Analisi:**
- I 43 finding sono **tutti** in `7d247ba` (commit "pre push", l'ultimo prima di GSD setup), tutti in README.md, e sono **esattamente** la motivazione della squash.
- 0 finding nei 27 commit GSD post-Plan 02 — la sanitizzazione di Plan 02 ha funzionato.
- Razionale squash confermato: il commit `7d247ba` è ancestor di `origin/main` (615feb4) → live e pubblicamente accessibile da 30 giorni. Force-push del nuovo orphan eliminerà questo commit da `origin/main` (resta solo nel reflog ~90gg, D-07 accepted).

**Status:** [x] OK (finding solo pre-squash, accettabile — sono il razionale della squash)
**Timestamp:** 2026-05-25T18:30Z
**Evidence file:** `.planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt` (549 righe, 19 KB)

---

## Step 3 — Trufflehog verified-only sul working tree

**Cmd:**
```bash
trufflehog filesystem . --only-verified --json --no-update \
  > .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt 2>&1
```

**Output:**

```json
{"finished scanning","chunks":287,"bytes":1494833,
 "verified_secrets":0,"unverified_secrets":0,
 "scan_duration":"214.50489ms",
 "trufflehog_version":"3.95.3"}
```

**Status:** [x] OK (0 verified, 0 unverified)
**Timestamp:** 2026-05-25T18:30Z
**Evidence file:** `.planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt`

**Note:** la modalità `filesystem . --only-verified` scansiona il working tree, **non** la git history. Per la history la copertura è di `gitleaks detect` (Step 2). Il combo trufflehog+gitleaks è il dual-engine raccomandato in PITFALLS.md §6.

---

## Step 4 — Exiftool su asset binari (PNG/JPG)

**Cmd:**
```bash
find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                 -o -iname '*.gif' -o -iname '*.tiff' -o -iname '*.bmp' \) \
  -not -path './.git/*'
```

**Output:** vuoto (0 file)

**Status:** [x] OK (0 file binari nel repo — docs-only v1)
**Timestamp:** 2026-05-25T18:30Z

**Note future:** Phase 4 (Lumio cutover) potrebbe aggiungere screenshot Studio. Eseguire `exiftool -all=` su ognuno prima del commit.

---

## Step 5 — .gitignore verify pattern critici

**Cmd:**
```bash
for pat in '.env' '.env.local' 'foo.cloudflared.json' 'cert.pem' \
           'volumes/storage/foo' 'volumes/db/data/foo.bin' \
           '.aws/credentials' 'docker-compose.override.yml' \
           'id_ed25519' 'authorized_keys' 'somefile-override.conf' \
           'tailscale.state' '6b09204a-58fd-4632-b699-15b1b9eb24a0.json' \
           'lumio/.env' 'lumio/volumes/storage/files/x.png' ; do
  git check-ignore -v "$pat"
done
git status --short | grep '^??'
```

**Output (sintetico — tutti pattern critici IGNORATI correttamente):**

| Pattern | Match in .gitignore | Note |
|---------|---------------------|------|
| `.env`, `.env.local` | line 15 | ✓ |
| `*.cloudflared.json` | line 36 | ✓ |
| `*.pem` (cert.pem) | line 63 | ✓ |
| `**/volumes/` | line 48 | ✓ (Docker mount roots, ricorsivo) |
| `.aws/` | line 76 | ✓ |
| `docker-compose.override.yml` | line 52 | ✓ |
| `id_ed25519`, `authorized_keys` | line 62, 68 | ✓ |
| `*-override.conf` | line 80 | ✓ (systemd drop-in) |
| `tailscale.state` | line 43 | ✓ |
| UUID `.json` (`6b09204a-...json`) | via `*.cloudflared.json` | NO — solo se nome contiene `cloudflared`. Mitigazione: regola `cf-tunnel-uuid` in gitleaks copre il caso uuid leak in qualsiasi file (file-name diventa irrelevant) |
| `lumio/.env`, `lumio/volumes/...` | line 15, 48 | ✓ (subdir paths) |

**Untracked:** solo `gitleaks-history-report.txt` e `trufflehog-report.txt` (i 2 evidence da committare).

**Status:** [x] OK
**Timestamp:** 2026-05-25T18:30Z

---

## Step 6 — Pre-push hook smoke test (deviation flagged)

**Cmd:**
```bash
git checkout -b smoke-test-prepush
echo 'UUID: 11111111-2222-3333-4444-555555555555' > leak-test-scratch.md
git add leak-test-scratch.md
git commit -m "smoke: scratch leak fixture" --no-verify
git push --dry-run origin smoke-test-prepush
```

**Output ATTESO:** push bloccato dal hook gitleaks (exit non-zero, leak detected).
**Output OSSERVATO:**

```
Detect hardcoded secrets.................................................Passed
To github.com:toto-castaldi/self-hosting.git
 * [new branch]      smoke-test-prepush -> smoke-test-prepush
EXIT_CODE: 0
```

**Diagnosi:** il hook ufficiale upstream `gitleaks/gitleaks` (rev v8.24.2) ha `entry: gitleaks git --pre-commit --staged` (verificato in `~/.cache/pre-commit/repo*/.pre-commit-hooks.yaml`). In stage `pre-push` non ci sono file staged → scan ritorna "no leaks" → hook passa anche con leak nel commit. **Il hook upstream non è effective al pre-push stage.**

**Status:** [x] KNOWN LIMITATION — pre-push hook locale è no-op, GH Action gitleaks (CI) è il vero secondo gate (runna `gitleaks detect` su full repo dopo il push).

**Implicazione operativa:** un push contenente leak NON viene bloccato localmente, ma la GH Action gitleaks fallisce il job e segnala l'errore subito dopo. Per repo personale solo-Antonio è accettabile. Per repo multi-contributor sarebbe da fix.

**Possibile fix (deferred, non in scope di Plan 03 perché modificherebbe `.pre-commit-config.yaml` already committed):** sostituire il repo upstream con un hook `repo: local` che invochi `gitleaks detect --no-banner --exit-code 1` direttamente. Catturato come deferred-item in Phase 1 closeout.

**Timestamp:** 2026-05-25T18:38Z

---

## Step 7 — (RIDOTTO) Verifica decisione GO/NO-GO PRE-SQUASH

- [x] Step 0-5 completati con esito OK
- [x] Step 6 documentato come known limitation (accettato — GH Action è il second gate)
- [x] Working tree clean (solo 2 evidence file untracked, da committare ora)
- [x] Backup bundle creato e verificato
- [x] Rischio reflog accettato esplicitamente (D-07)
- [x] Architectural deviation Option A confermata dall'utente (force-push su repo già PUBLIC, nessun flip visibility)

**GO:** procedere a Step 8 (squash + force-push).
**Final decision:** [x] GO

**Timestamp checkpoint-1 GO:** 2026-05-25T18:40Z (utente ha confermato Option A nel prompt iniziale; questo step è formal closure pre-squash)

---

## Step 8 — Squash a orphan branch `public-v1` (post-GO)

**Cmd:**
```bash
git tag pre-squash-snapshot          # safety ref before orphan
git checkout --orphan public-v1
git rm -rf --cached .
git add -A
git commit -m "Initial public release of jarvis self-hosting v1

Personal self-hosting setup (Ubuntu mini PC, Supabase self-hosted,
Cloudflare Tunnel, backup workflow). See README.md for overview."
```

**Output:** [filled post-execution]

**Status:** [ ] OK
**Timestamp:** [filled post-execution]

---

## Step 9 — Re-run gitleaks su orphan branch (post-squash)

**Cmd:**
```bash
gitleaks detect --config .gitleaks.toml --no-banner --redact -v
```

**Output:** [filled post-execution]

**Status:** [ ] OK (atteso: 0 finding)
**Timestamp:** [filled post-execution]

---

## Step 10 — CHECKPOINT-2 GO/NO-GO PRE-FORCE-PUSH

- [ ] Orphan branch ha 1 commit, 0 parent
- [ ] Gitleaks su orphan = 0 finding
- [ ] Working tree clean
- [ ] Bundle backup intact
- [ ] User confirmed GO

**GO:** procedere a Step 11 (force-push).
**Final decision:** [ ] GO / [ ] NO-GO

**Timestamp:** [filled post-execution]

---

## Step 11 — Force-push `public-v1:main --force-with-lease`

**Cmd:**
```bash
git push origin public-v1:main --force-with-lease=main:$(git rev-parse origin/main)
git ls-remote origin main
```

**Output:** [filled post-execution]

**Status:** [ ] OK
**Timestamp:** [filled post-execution]

---

## Step 12 — Flip visibility a PUBLIC

**Status:** [x] **SKIPPED** — repo già PUBLIC dal 2026-04-28.
Comando `gh repo edit --visibility public --accept-visibility-change-consequences` sarebbe no-op.
Verifica: `gh repo view --json visibility` → `"PUBLIC"`.

**Timestamp:** 2026-05-25T18:25Z (decisione presa pre-Plan-execution, ratificata in Option A)

---

## Step 13 — Smoke verify post-publish

**Cmd:**
```bash
SMOKE=$(mktemp -d)
git clone https://github.com/toto-castaldi/self-hosting.git "$SMOKE/repo"
cd "$SMOKE/repo"
git log --oneline | wc -l                                  # atteso: 1
gitleaks detect --config .gitleaks.toml --no-banner        # atteso exit 0
grep -rE '(toto-castaldi\.com|6b09204a|146\.190|188\.166|152\.42|toto\.castaldi@|inspiron)' --exclude-dir=.git .
gh api repos/toto-castaldi/self-hosting/readme --jq .download_url
curl -fsSL <readme-url> | grep -E '(toto-castaldi|6b09204a|146\.190|188\.166|152\.42|toto\.castaldi@gmail)'
```

**Output:** [filled post-execution]

**Status:** [ ] OK
**Timestamp:** [filled post-execution]

---

## Step 14 — GH Action gitleaks post-publish

**Cmd:**
```bash
gh run list --workflow=gitleaks.yml --limit 1
gh run view <RUN_ID> --log | tail -50
```

**Output:** [filled post-execution]

**Status:** [ ] OK
**Timestamp:** [filled post-execution]

---

## Publication complete

**Repo public URL:** https://github.com/toto-castaldi/self-hosting
**Public commit SHA:** [filled post-execution]
**Old history bundle:** `/home/toto/self-hosting-private.bundle` (455 KB) — laptop-only safety net
**Visibility:** PUBLIC (verified via `gh repo view`; already public since 2026-04-28, no flip needed)
**Pre-existing public commits squashed:** `615feb4` ("rifare"), `7d247ba` ("pre push"), `4c1156f` (roadmap), `396f37a` (requirements), `fbcd5bb` (research summary), `83501b6` (PROJECT.md) → reflog ~90gg accepted (D-07)
**GH Actions gitleaks:** [filled post-execution]
**Completed at:** [filled post-execution]

---

## Risks accepted (per CONTEXT.md D-07 + Option A architectural deviation)

- **Reflog GitHub ~90gg post force-push**: la old history del repo (incluso `7d247ba` con 43 leak in README.md) era già accessibile pubblicamente dal 2026-04-28 (~30 giorni di esposizione effettiva). Il force-push la rimuove da `origin/main` ma resta:
  - Nel reflog GitHub interno per ~90 giorni (accessibile via direct SHA reference, non via `git clone`)
  - Negli indici di GitHub Search (re-indexa automaticamente al push, ~24h convergenza)
  - In eventuali fork o clone che terze parti potrebbero aver fatto durante i 30 giorni (out of control)
- **No GitHub Support ticket** per reflog purge: declinato esplicitamente in CONTEXT.md D-07 e ratificato in Option A.
- **No rotazione asset leakati**: i 43 finding del commit `7d247ba` sono **identificativi pubblici** (UUID tunnel, IP DigitalOcean, hostname DNS, email author-trailer). Non sono secret (no token, no credential). Asset utility per attacchi: minimo (UUID tunnel non è auth, è un identificatore; IP DO è dismesso post-cutover Phase 4; email è già nei git author-trailer in altri repo pubblici).
- **`readme-placeholder-map.md` in `.planning/`** post-publish: contiene mapping real→placeholder; valori reali sono comunque recuperabili via Certificate Transparency + WHOIS quindi il valore informativo dell'audit trail supera il rischio incrementale di esposizione (vedi T-02-05 threat model Plan 02).
- **Pre-push gitleaks hook locale è no-op** (Step 6): GH Action gitleaks è il vero secondo gate. Per repo solo-Antonio, accettabile in v1. Catturato come deferred-item.
- **Tooling install via `pip --user --break-system-packages`**: PEP 668 violation user-level only (no system pollution). Accettabile in assenza di pipx e sudo password.
