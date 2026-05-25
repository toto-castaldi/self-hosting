---
phase: 01-foundations-repo-sanitize
plan: 02
type: execute
wave: 2
depends_on: ["01-01"]
files_modified:
  - .gitignore
  - .gitleaks.toml
  - .pre-commit-config.yaml
  - .github/workflows/gitleaks.yml
  - LICENSE
  - README.md
  - .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md
  - .planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt
autonomous: false
requirements: [REPO-01, REPO-02, REPO-03, REPO-05]

must_haves:
  truths:
    - "`gitleaks detect --no-git --config .gitleaks.toml --no-banner --redact` sul working tree esce con exit 0 e zero finding"
    - "README.md pubblico non contiene: UUID `6b09204a-58fd-4632-b699-15b1b9eb24a0`, IP `146.190.232.60` / `192.168.0.72` / `185.199.108.X` / `188.166.97.177` / `152.42.138.218`, email `toto.castaldi@gmail.com` (case-insensitive), path `/etc/cloudflared/6b09204a-*.json`, hostname `lumio.toto-castaldi.com` (e 10 altri sottodomini reali)"
    - "Pre-push gitleaks hook installato e blocca push se trova finding (testato con un finding fittizio in un commit scratch)"
    - "GitHub Actions workflow `.github/workflows/gitleaks.yml` esiste, valida sintatticamente, scansiona history completa (fetch-depth: 0)"
    - "`.gitignore` impedisce commit di: `*.cloudflared.json`, `cert.pem`, `**/volumes/`, `tailscale.state`, `*.pem`/`*.key`/`*.crt`, `*-override.conf`, etc."
    - "LICENSE è MIT standard (testo SPDX MIT identifier), copyright `Antonio Castaldi <toto.castaldi@gmail.com>` 2026"
    - "README narrative preservato (sezioni `# BACKUP RSYNC`, `# SUPABASE`, ASCII diagram, decision log, runbook ops) — sostituiti solo gli identificativi sensibili"
  artifacts:
    - path: ".gitignore"
      provides: "Estensione baseline GSD con tutte le classi di infra secrets (cloudflared, Tailscale, Docker volumes, TLS, systemd drop-in)"
      contains: "**/cloudflared/*.json, cert.pem, **/volumes/, tailscale.state, *.pem, *.key, *-override.conf"
    - path: ".gitleaks.toml"
      provides: "Custom rules + allowlists per gli identificativi specifici di questo repo (UUID Cloudflare, IP pubblici esclusi RFC1918/CGNAT/TEST-NET, email personali, paths cloudflared, JWT-loose, hostname *.toto-castaldi.com)"
      contains: "[extend] useDefault = true, [[rules]] cf-tunnel-uuid, [[rules]] public-ipv4, [[rules]] personal-email, [[rules]] private-fqdn"
    - path: ".pre-commit-config.yaml"
      provides: "Hook gitleaks v8 pinnato come pre-push (non pre-commit per non rallentare inner loop)"
      contains: "repo: gitleaks/gitleaks rev: v8.24.2, hook id: gitleaks, stages: [push]"
    - path: ".github/workflows/gitleaks.yml"
      provides: "CI gate su push/PR che scansiona history completa con .gitleaks.toml"
      contains: "uses: gitleaks/gitleaks-action@v2, fetch-depth: 0, GITLEAKS_CONFIG"
    - path: "LICENSE"
      provides: "MIT standard text con copyright Antonio Castaldi 2026"
    - path: "README.md"
      provides: "README sanitizzato in-place — narrative preservato, identificativi reali sostituiti con placeholder canonici (example.com, 203.0.113.X, you@example.com, UUID 00000000-...)"
    - path: ".planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md"
      provides: "Mapping documentato real → placeholder usato (audit trail della sanitizzazione, utile per future verifiche e per il PRE-PUBLISH-CHECKLIST.md di Plan 03)"
  key_links:
    - from: ".pre-commit-config.yaml"
      to: ".gitleaks.toml"
      via: "hook gitleaks legge automaticamente .gitleaks.toml nella root del repo se presente"
      pattern: "default config discovery: `.gitleaks.toml` o passato via `--config`"
    - from: ".github/workflows/gitleaks.yml"
      to: ".gitleaks.toml"
      via: "env: GITLEAKS_CONFIG: .gitleaks.toml"
      pattern: "GITLEAKS_CONFIG env var picked up by gitleaks-action@v2"
    - from: ".gitignore"
      to: ".env.example"
      via: "negazione `!.env.example` per permettere template committable"
      pattern: "esistente in baseline GSD — NON rompere"
---

<objective>
Trasformare il repo `self-hosting` da privato-con-leak a working-tree pulito + tooling
anti-regressione attivo. Tre output paralleli:

1. **Detection layer**: gitleaks v8 + custom rules + pre-push hook locale + GH Action CI.
2. **Prevention layer**: `.gitignore` esteso con tutte le classi di infra secret (cloudflared
   credentials JSON, cert.pem, mount roots Docker, Tailscale state, SSH/TLS material,
   systemd drop-in).
3. **Content layer**: README.md sanitizzato in-place preservando narrative + ASCII diagram,
   sostituendo ogni asset identificativo con placeholder documentati; LICENSE MIT.

Il working tree deve uscire `gitleaks detect --no-git` clean (0 finding). La history NON viene
toccata in questo plan — è scope di Plan 03 (squash a orphan `public-v1`).

Purpose: chiudere REPO-01, REPO-02, REPO-03, REPO-05 prima del pre-publish check (REPO-06 in
Plan 03). Senza working tree pulito e tooling attivo, Plan 03 non può procedere al push public.

Output: 5 file infra (.gitignore esteso, .gitleaks.toml, .pre-commit-config.yaml, GH workflow,
LICENSE), 1 file content (README.md sanitizzato), 2 file evidence (placeholder map, gitleaks
worktree report).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md
@.planning/research/PITFALLS.md
@README.md
@.gitignore
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 2.1: Costruire `.gitignore` esteso + `.gitleaks.toml` + LICENSE MIT</name>
  <files>.gitignore, .gitleaks.toml, LICENSE</files>
  <read_first>
    - .gitignore (baseline GSD attuale — 32 righe, da NON sovrascrivere ma estendere)
    - .planning/research/PITFALLS.md §3 ".gitignore additions" (lista classi cloudflared / Tailscale / Docker volumes / SSH-TLS / Supabase / systemd)
    - .planning/research/PITFALLS.md §1 "Custom rules to add to .gitleaks.toml" (5 regole esempio: cf-tunnel-uuid, public-ipv4, personal-email, jwt-loose, cred-paths, cf-origin-ca, private-fqdn)
    - .planning/research/PITFALLS.md §5 "LICENSE choice" + CONTEXT.md D-05 (decisione MIT solo)
    - README.md (per identificare classi di leak presenti in working tree: scan riga per riga)
  </read_first>
  <action>
**A. Estendere `.gitignore`** (append, NON sovrascrivere baseline GSD esistente):

Aggiungere in fondo al file, separato da commento header `# ── infra secrets (jarvis self-hosting) ──`, le seguenti classi (ognuna preceduta da commento di sezione IT):

```
# ── infra secrets (jarvis self-hosting) ──

# cloudflared
*.cloudflared.json
**/cloudflared/*.json
**/cloudflared/cert.pem
**/cloudflared/config.yml
.cloudflared/

# Tailscale
tailscale.state
/var/lib/tailscale/
*.tailscale.key

# Docker compose state / volumes
**/volumes/
**/data/
**/postgres-data/
**/storage-data/
docker-compose.override.yml

# Supabase
.env.local
.env.production
supabase/.branches/
supabase/.temp/

# SSH / TLS / GPG
id_rsa
id_ed25519
*.pem
*.key
*.crt
*.pfx
*.p12
authorized_keys
known_hosts
*.gpg
*.asc

# Secrets-ish dotfiles
.netrc
.pgpass
.aws/
.kube/config

# systemd drop-in con secret
*-override.conf

# editor scratch
*.bak
*.orig

# host-audit scratch (script audit può lasciare /tmp/host-audit-*.md locali)
host-audit-*.md
!.planning/phases/*/host-audit-report.md
```

L'ultima riga (`!.planning/...`) esplicitamente PERMETTE il report committato come evidence, escludendolo dal pattern wildcard. Verificare con `git check-ignore -v .planning/phases/01-foundations-repo-sanitize/host-audit-report.md` → atteso: nessun output (non ignorato).

**B. Creare `.gitleaks.toml`** alla root del repo. Struttura TOML completa con:

```toml
title = "self-hosting (jarvis) custom rules"

[extend]
useDefault = true              # mantieni i ~150 rules built-in di gitleaks v8

# ─── Cloudflare Tunnel UUID v4 ───
[[rules]]
id = "cf-tunnel-uuid"
description = "Cloudflare Tunnel UUID (or any UUID v4 used as credential filename)"
regex = '''\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'''
tags = ["cloudflare", "tunnel", "uuid"]
[rules.allowlist]
description = "Documentation placeholders only"
regexes = [
  '''00000000-0000-0000-0000-000000000000''',
  '''xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx''',
  '''aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa''',
]

# ─── Public IPv4 (excludes RFC1918 / loopback / CGNAT / TEST-NET / link-local) ───
[[rules]]
id = "public-ipv4"
description = "Public IPv4 address — redact to documentation range 203.0.113.X (TEST-NET-3)"
regex = '''\b(?:\d{1,3}\.){3}\d{1,3}\b'''
[rules.allowlist]
description = "Private/reserved/documentation ranges are fine"
regexes = [
  '''\b10\.(?:\d{1,3}\.){2}\d{1,3}\b''',
  '''\b172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.){1}\d{1,3}\b''',
  '''\b192\.168\.\d{1,3}\.\d{1,3}\b''',
  '''\b127\.\d{1,3}\.\d{1,3}\.\d{1,3}\b''',
  '''\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b''',
  '''\b169\.254\.\d{1,3}\.\d{1,3}\b''',
  '''\b(192\.0\.2|198\.51\.100|203\.0\.113)\.\d{1,3}\b''',
  '''\b1\.2\.3\.4\b''',
  '''\b0\.0\.0\.0\b''',
  '''\b255\.255\.255\.(?:0|255)\b''',
]

# ─── Personal/work email ───
[[rules]]
id = "personal-email"
description = "Personal/work email leaked in docs or commits"
regex = '''(?i)\b[a-z0-9._%+-]+@(?:gmail|outlook|hotmail|yahoo|proton(?:mail)?|icloud|me|fastmail)\.[a-z]{2,}\b'''
[rules.allowlist]
regexes = [
  '''you@example\.com''',
  '''user@example\.com''',
  '''noreply@.*''',
  '''test@example\.com''',
]

# ─── JWT (loose pattern, complements built-in) ───
[[rules]]
id = "jwt-loose"
description = "JWT (loose: 3 base64url segments)"
regex = '''\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'''
tags = ["jwt"]

# ─── Filesystem paths to real cert/credential files ───
[[rules]]
id = "cred-paths"
description = "Filesystem path to a real cert/credentials file"
regex = '''(?i)(?:/etc/cloudflared|/home/[^/\s]+/\.cloudflared|/etc/letsencrypt/live)/[^\s'"]+\.(?:json|pem|key|crt)'''
[rules.allowlist]
regexes = [
  '''/etc/cloudflared/00000000-0000-0000-0000-000000000000\.json''',
  '''cert\.pem\.example''',
  '''/etc/cloudflared/<UUID>\.json''',
]

# ─── Cloudflare Origin CA Key (worth pinning) ───
[[rules]]
id = "cf-origin-ca"
regex = '''\bv1\.0-[a-f0-9]{24}-[a-f0-9]{146}\b'''
tags = ["cloudflare"]

# ─── Personal hostname/subdomain (project-specific) ───
[[rules]]
id = "private-fqdn"
description = "Real subdomain of toto-castaldi.com — must be example.com in public docs"
regex = '''\b[a-z0-9-]+\.toto-castaldi\.com\b'''
tags = ["fqdn"]
```

Validare il file con `gitleaks detect --config .gitleaks.toml --no-git --no-banner --redact -v` su un file scratch contenente sia leak veri che placeholder noti — i placeholder non devono triggerare false positive.

**C. Creare `LICENSE`** (MIT standard, no dual licensing per D-05):

Testo MIT canonico SPDX:
```
MIT License

Copyright (c) 2026 Antonio Castaldi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR DEALINGS IN THE
SOFTWARE.
```

NOTA: il testo SOPRA contiene l'email personale come copyright? **NO** — il pattern canonico MIT mette solo il nome (`Copyright (c) 2026 Antonio Castaldi`), niente email. Questo evita di triggerare la regola `personal-email` di gitleaks su LICENSE stesso.

Verificare che `gitleaks detect --no-git --config .gitleaks.toml --no-banner` sul LICENSE solo (`gitleaks detect --no-git --config .gitleaks.toml --source LICENSE`) ritorna 0 finding.

NESSUN tocco al README.md in questa task — Task 2.3 lo affronta separatamente con audit trail completo.
  </action>
  <verify>
    <automated>
test -f .gitleaks.toml
test -f LICENSE
grep -q '^MIT License$' LICENSE
grep -q 'Copyright (c) 2026 Antonio Castaldi$' LICENSE
grep -cE '@(gmail|outlook|hotmail|yahoo|proton|icloud|me|fastmail)\.' LICENSE | grep -qx '0'    # no email in LICENSE
grep -q 'useDefault = true' .gitleaks.toml
grep -q 'id = "cf-tunnel-uuid"' .gitleaks.toml
grep -q 'id = "public-ipv4"' .gitleaks.toml
grep -q 'id = "personal-email"' .gitleaks.toml
grep -q 'id = "private-fqdn"' .gitleaks.toml
grep -q '\*\*/cloudflared/\*\.json' .gitignore
grep -q '\*\*/volumes/' .gitignore
grep -q '\*-override\.conf' .gitignore
# baseline GSD preservato
grep -q '^\.gsd$' .gitignore
grep -q '^!\.env\.example$' .gitignore
# gitleaks valida la config TOML (richiede gitleaks v8 installato — se non presente, skip)
command -v gitleaks && gitleaks detect --config .gitleaks.toml --no-git --no-banner --source LICENSE && echo "LICENSE clean" || echo "gitleaks non installato, skip"
    </automated>
  </verify>
  <acceptance_criteria>
    - `.gitignore` esiste e contiene sia le righe baseline GSD originali (.gsd, .env, !.env.example, node_modules/, ecc.) SIA le 7 classi di infra secret aggiunte (cloudflared, Tailscale, Docker volumes, Supabase, SSH/TLS, dotfiles secrets-ish, systemd drop-in).
    - `git check-ignore -v` ritorna match per: `test.cloudflared.json`, `volumes/postgres-data/data`, `tailscale.state`, `mykey.pem`, `cloudflared-override.conf`.
    - `git check-ignore -v .planning/phases/01-foundations-repo-sanitize/host-audit-report.md` NON ritorna match (negation funziona).
    - `.gitleaks.toml` esiste, è TOML valido (parsabile), contiene `[extend] useDefault = true` e le 7 rule `id` documentate sopra. Allowlists per UUID placeholder, RFC1918/CGNAT/TEST-NET, email noreply funzionano.
    - `LICENSE` esiste, è testo MIT canonico SPDX, copyright `Antonio Castaldi 2026` (no email in copyright per evitare auto-leak).
    - Eseguendo `gitleaks detect --no-git --config .gitleaks.toml --no-banner` SOLO su LICENSE → 0 finding.
  </acceptance_criteria>
  <done>
Infra layer di REPO-01, REPO-02, REPO-05 in piedi: `.gitignore` esteso, `.gitleaks.toml` con custom rules, LICENSE MIT. Il README sanitization e i pre-push/CI hook sono nelle task successive.
  </done>
</task>

<task type="auto">
  <name>Task 2.2: Installare gitleaks pre-push hook (pre-commit framework) + GitHub Actions workflow</name>
  <files>.pre-commit-config.yaml, .github/workflows/gitleaks.yml</files>
  <read_first>
    - .planning/research/PITFALLS.md §1 "Install pattern (v1, minimal)" — pre-commit-config.yaml shape e gitleaks-action@v2 reference
    - .planning/research/PITFALLS.md §1 "Pre-push (not pre-commit) is preferable" — razionale per stages: [push]
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md §Specifics ultimo bullet (decisione pre-commit framework vs hook nativo → Claude's discretion. Scelta: **pre-commit framework** perché si committa nel repo public e altri possono replicarlo)
    - .gitleaks.toml (da Task 2.1 — config che la GH Action leggerà via GITLEAKS_CONFIG)
  </read_first>
  <action>
**A. Creare `.pre-commit-config.yaml`** alla root del repo:

```yaml
# pre-commit framework configuration
# Install: pip install pre-commit (or pipx); then `pre-commit install --hook-type pre-push`
# Why pre-push (not pre-commit): runs once before network round-trip, doesn't slow per-commit
# inner loop; still blocks secrets before they leave the laptop.
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2          # pinned — do not float
    hooks:
      - id: gitleaks
        stages: [pre-push]
        # gitleaks autodiscovers .gitleaks.toml in repo root
        # add --config arg if config lives elsewhere
```

NOTA: il rev `v8.24.2` è il valore in PITFALLS.md (research). Se al moment dell'esecuzione una versione più recente è disponibile e PITFALLS.md è stato superato, è OK bumpare — il vincolo è "v8.x pinned, no floating tag" non quel valore esatto.

**B. Creare `.github/workflows/gitleaks.yml`**:

```yaml
name: gitleaks

on:
  push:
    branches: ['**']
  pull_request:
    branches: ['**']

jobs:
  scan:
    name: Detect secrets in commits and tree
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout (full history)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0       # full history per scan diff completo

      - name: Run gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITLEAKS_CONFIG: .gitleaks.toml
          # GITLEAKS_NOTIFY_USER_LIST e GITLEAKS_ENABLE_COMMENTS lasciati ai default
```

NOTA: la GH Action `gitleaks/gitleaks-action@v2` storicamente richiedeva `GITLEAKS_LICENSE` per repo org-scope; per repo individuali pubblici è gratis e non serve token. Documentare questo in commento.

**C. Eseguire localmente i due check** per validare che funzionano (richiede gitleaks installato sul laptop di Antonio o nel devcontainer):

```bash
# Validate workflow file syntax (offline, basic YAML check)
python -c "import yaml; yaml.safe_load(open('.github/workflows/gitleaks.yml'))"

# Validate pre-commit config syntax
python -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))"

# Se pre-commit è installato: installare hook (Antonio deve runnare manualmente)
# pre-commit install --hook-type pre-push
# pre-commit run --hook-stage pre-push --all-files
```

L'installazione del pre-push hook locale (`pre-commit install --hook-type pre-push`) richiede pre-commit CLI installato sul laptop di Antonio — è uno step manuale documentato in README + verificato a Task 2.3 (perché serve il README sanitizzato prima per ovvi motivi di non auto-leak).

**D. Smoke test del workflow YAML** via `gh workflow view` (se gh CLI è autenticata sul repo locale — atteso fallisce se workflow non è ancora committato, OK skip):

```bash
gh workflow list 2>/dev/null || echo "gh non configurato, skip smoke test"
```
  </action>
  <verify>
    <automated>
test -f .pre-commit-config.yaml
test -f .github/workflows/gitleaks.yml
python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gitleaks.yml'))"
grep -q 'gitleaks/gitleaks' .pre-commit-config.yaml
grep -q 'rev: v8\.' .pre-commit-config.yaml
grep -q 'stages: \[pre-push\]' .pre-commit-config.yaml
grep -q 'uses: gitleaks/gitleaks-action@v2' .github/workflows/gitleaks.yml
grep -q 'fetch-depth: 0' .github/workflows/gitleaks.yml
grep -q 'GITLEAKS_CONFIG: \.gitleaks\.toml' .github/workflows/gitleaks.yml
    </automated>
  </verify>
  <acceptance_criteria>
    - `.pre-commit-config.yaml` esiste, YAML valido, pinna gitleaks a un tag v8.x esplicito (NO `master`, NO unpinned), hook `id: gitleaks` con `stages: [pre-push]`.
    - `.github/workflows/gitleaks.yml` esiste, YAML valido, trigger su push e pull_request (tutti i branch), step di checkout con `fetch-depth: 0`, step gitleaks-action@v2 con env `GITLEAKS_CONFIG: .gitleaks.toml`.
    - Nessuno dei due file contiene leak (eseguito gitleaks puntuale sui due file → 0 finding).
    - Documentato in README (post-sanitize Task 2.3) o in un commento: per attivare il pre-push hook localmente, eseguire `pre-commit install --hook-type pre-push` una volta dopo clone.
  </acceptance_criteria>
  <done>
Detection layer attivo per: (a) push da laptop di Antonio (via pre-commit framework pre-push), (b) push verso GitHub remote (via gitleaks-action@v2). Entrambi leggono `.gitleaks.toml`. Storicamente Plan 03 useranno la stessa config per pre-publish history scan.
  </done>
</task>

<task type="auto">
  <name>Task 2.3: Sanitize README.md in-place con placeholder map documentata</name>
  <files>README.md, .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md, .planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt</files>
  <read_first>
    - README.md (intero — 387 righe, contiene leak in più sezioni, da analizzare riga per riga prima di sostituire)
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md §D-04 (sanitize-in-place, preservare narrative, NON rewrite from scratch)
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md §Specifics (ASCII diagram: "Jarvis (mini PC)" → "jarvis (mini PC)" lowercase)
    - .planning/research/PITFALLS.md §4 "Anonymization conventions" — tabella mapping canonico (real → placeholder)
    - .gitleaks.toml (da Task 2.1 — usato per verificare clean al termine)
  </read_first>
  <action>
**A. Costruire la placeholder map** scrivendo `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` PRIMA di modificare README. Mappa completa, ordinata per categoria. Usa la tabella canonica di PITFALLS.md §4 estesa con i valori specifici scoperti grep-ando README.md:

```markdown
# README sanitization placeholder map

**Created:** 2026-05-XX (Plan 02 Task 2.3)
**Purpose:** audit trail della sostituzione real→placeholder in README.md.
Ogni riga = una classe di leak; la sostituzione è applicata via sed con regex anchor sicuri.

## Domini e sottodomini

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `toto-castaldi.com` | `example.com` | RFC2606 reserved per docs |
| `lumio.toto-castaldi.com` | `app.example.com` | placeholder canonico |
| `m-lumio.toto-castaldi.com` | `mobile.example.com` | |
| `deck.lumio.toto-castaldi.com` | `deck.app.example.com` | |
| `helix.toto-castaldi.com` | `service-a.example.com` | maschera anche il nome progetto secondario (Helix è v2) |
| `live.helix.toto-castaldi.com` | `live.service-a.example.com` | |
| `coach.helix.toto-castaldi.com` | `coach.service-a.example.com` | |
| `docora.toto-castaldi.com` | `service-b.example.com` | |
| `api.docora.toto-castaldi.com` | `api.service-b.example.com` | |
| `n8n.toto-castaldi.com` | `workflow.example.com` | |
| `supabase-lumio.toto-castaldi.com` | `api.app.example.com` | |
| `studio-lumio.toto-castaldi.com` | `studio.app.example.com` | |
| `supabase-helix.toto-castaldi.com` | `api.service-a.example.com` | |
| `studio-helix.toto-castaldi.com` | `studio.service-a.example.com` | |
| `hello.toto-castaldi.com` | `hello.example.com` | |

## IP

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `185.199.108.153` (e .109/.110/.111) | `203.0.113.10` (e .11/.12/.13) | TEST-NET-3 (RFC5737) per GitHub Pages mock |
| `146.190.232.60` | `203.0.113.20` | TEST-NET-3 — DigitalOcean droplet originale Lumio |
| `188.166.97.177` | `203.0.113.30` | TEST-NET-3 — Docora droplet |
| `152.42.138.218` | `203.0.113.40` | TEST-NET-3 — n8n droplet |
| `192.168.0.72` | `192.168.0.X` (con `X` letterale come placeholder) | RFC1918 può stare ma maschero last-octet per principio |
| `192.168.0.137` | `192.168.0.Y` | come sopra |

## UUID / credentials

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `6b09204a-58fd-4632-b699-15b1b9eb24a0` | `00000000-0000-0000-0000-000000000000` | allowlisted in .gitleaks.toml |
| `/etc/cloudflared/6b09204a-58fd-4632-b699-15b1b9eb24a0.json` | `/etc/cloudflared/<TUNNEL_UUID>.json` | placeholder esplicito |

## Email e account

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `Toto.castaldi@gmail.com` (case variants) | `you@example.com` | allowlisted in .gitleaks.toml |
| `toto.castaldi@gmail.com` | `you@example.com` | |
| Account Cloudflare "toto" | "user" | |

## Hostname e naming

| Real | Placeholder/Modifica | Razionale |
|------|----------------------|-----------|
| `jarvis` (hostname) | **KEEP** (è l'identità del progetto, narrative asset) | CONTEXT.md, CLAUDE.md, PITFALLS.md concordano |
| `Jarvis` (Title Case in ASCII diagram) | `jarvis` (lowercase per coerenza) | CONTEXT.md §Specifics |
| `toto` (linux user) | **KEEP** (low sensitivity, UID 1000 ubiquo) | PITFALLS.md tabella |

## DNS infrastruttura

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `remy.ns.cloudflare.com`, `wanda.ns.cloudflare.com` | `nsX.example-dns.com`, `nsY.example-dns.com` | nomi NS Cloudflare assegnati sono pubblicamente derivabili dalla zona ma non serve esporli |
| `GoDaddy` (registrar) | **KEEP** (riferimento generico, non identificativo) | |

## Sezioni speciali

- **Sezione `# NOTE / ## init`** (righe ~328-340 nel README originale): contiene `ssh ... toto@192.168.0.137 'mkdir -p ~/.ssh ...'`. Sostituire `192.168.0.137` con `192.168.0.Y`, lasciare `toto` (low sens), lasciare il pattern shell. È un esempio di provisioning iniziale, ha valore narrative.
- **Sezione `## rsync`** (riga ~358): comando `rsync -avh --delete Documents/ jarvis:~/backups/inspiron-documents/`. `jarvis` rimane (narrative); `inspiron-documents` rivela hostname laptop (Inspiron Dell). **Sostituire** `inspiron-documents` → `laptop-documents`.
- **Sezione `## docker` e `## cloudfare`** (righe ~362-386): contengono history numbered (`60 sudo apt update ...`) — questo è esattamente l'anti-pattern PITFALLS §6 punto 6 ("Shell history in commits"). **Decisione**: mantenere il narrative MA: (a) sostituire numbered prefix (`60 `, `61 `, ecc.) con commento `# ` (rimuove l'aspetto history-leak), (b) verificare zero URL/token nei comandi (visivamente già OK in README). **Verifica posta-modifica**: nessun match su pattern `^\s+\d+\s+(sudo|curl|echo)` (lo shell history pattern).
```

**B. Applicare le sostituzioni** via script Bash dedicato (one-shot, non commit) `scripts/sanitize-readme.sh` (questo script NON viene committato — è scratch). Lo script:

```bash
#!/usr/bin/env bash
set -euo pipefail

cp README.md README.md.bak.preserveme   # safety net locale (gitignored via *.bak)

# Sostituzioni in ordine (più specifiche prima per evitare race):
sed -i '
# UUID Cloudflare Tunnel
s|6b09204a-58fd-4632-b699-15b1b9eb24a0|00000000-0000-0000-0000-000000000000|g
# Email (case-insensitive)
s|[Tt]oto\.[Cc]astaldi@gmail\.com|you@example.com|g
# Sottodomini specifici prima del replace generico di toto-castaldi.com
s|supabase-lumio\.toto-castaldi\.com|api.app.example.com|g
s|studio-lumio\.toto-castaldi\.com|studio.app.example.com|g
s|supabase-helix\.toto-castaldi\.com|api.service-a.example.com|g
s|studio-helix\.toto-castaldi\.com|studio.service-a.example.com|g
s|m-lumio\.toto-castaldi\.com|mobile.example.com|g
s|deck\.lumio\.toto-castaldi\.com|deck.app.example.com|g
s|lumio\.toto-castaldi\.com|app.example.com|g
s|live\.helix\.toto-castaldi\.com|live.service-a.example.com|g
s|coach\.helix\.toto-castaldi\.com|coach.service-a.example.com|g
s|helix\.toto-castaldi\.com|service-a.example.com|g
s|api\.docora\.toto-castaldi\.com|api.service-b.example.com|g
s|docora\.toto-castaldi\.com|service-b.example.com|g
s|n8n\.toto-castaldi\.com|workflow.example.com|g
s|hello\.toto-castaldi\.com|hello.example.com|g
# Apex domain ultimo
s|toto-castaldi\.com|example.com|g
# IP pubblici
s|185\.199\.108-111\.153|203.0.113.10-13|g
s|185\.199\.108\.153|203.0.113.10|g
s|146\.190\.232\.60|203.0.113.20|g
s|188\.166\.97\.177|203.0.113.30|g
s|152\.42\.138\.218|203.0.113.40|g
# RFC1918 last-octet mask
s|192\.168\.0\.72|192.168.0.X|g
s|192\.168\.0\.137|192.168.0.Y|g
# Cloudflare nameserver
s|remy\.ns\.cloudflare\.com|nsX.example-dns.com|g
s|wanda\.ns\.cloudflare\.com|nsY.example-dns.com|g
# Account Cloudflare email field "Toto.castaldi@gmail.com" già coperto sopra
# Account name "toto" in tabella asset specifica
s|\|Nome account Cloudflare\|`toto`\||\|Nome account Cloudflare\|`user`\||g
# Hostname laptop
s|inspiron-documents|laptop-documents|g
s|laptop Inspiron|laptop|g
# Title case Jarvis → jarvis nell ASCII diagram
s|Jarvis (mini PC)|jarvis (mini PC)|g
# Shell history prefix rimosso (mantieni il comando, togli il numero)
s|^\(\s*\)\([0-9]\+\)\s\+\(sudo\|curl\|echo\|cloudflared\|ls\)|\1# \3|g
# Path credentials esplicito
s|/etc/cloudflared/00000000-0000-0000-0000-000000000000\.json|/etc/cloudflared/<TUNNEL_UUID>.json|g
' README.md

rm -f README.md.bak.preserveme
```

Eseguire lo script una volta, poi **rimuovere lo script** (non committato — è scratch one-shot). La regola gitleaks `cf-tunnel-uuid` ha allowlist per `00000000-...` quindi la sostituzione è idempotente rispetto al detector.

**C. Aggiungere blocco "Disclaimer" e link a LICENSE in README.md** (post-sanitize, append/edit a inizio README):

Inserire all'inizio del README (riga 1, prima di `# BACKUP RSYNC`) un blocco header:

```markdown
# jarvis — Personal self-hosting narrative

> This repo documents how I (a single dev) self-host a small set of services
> (Supabase, Cloudflare Tunnel, backups) on a home mini-PC named `jarvis`. It is
> a **narrative/reference**, not a reusable framework. All identifying assets
> (hostnames, UUIDs, IPs, emails) have been replaced with documentation
> placeholders (`example.com`, `203.0.113.X`, generic UUIDs). License: MIT.

**Note**: to enable the secret-scanning pre-push hook locally, after cloning run
`pre-commit install --hook-type pre-push` (requires the `pre-commit` Python tool).

---
```

**D. Eseguire `gitleaks detect --no-git --config .gitleaks.toml --no-banner --redact -v`** sul working tree e salvare l'output in `.planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt`. Atteso: exit 0, "No leaks found". Se trova residui, iterare sulla sed map.

**E. Grep manuale di sicurezza** per garantire zero residui delle classi note:

```bash
# Nessun residuo:
! grep -rE '(6b09204a|toto-castaldi\.com|146\.190\.232\.60|toto\.castaldi@gmail|inspiron)' --include='*.md' --include='*.yml' --include='*.yaml' --include='*.sh' --include='LICENSE' .
```

Se il grep ritorna match in `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` (la map STESSA contiene i valori reali nella colonna sinistra), considerare due opzioni:
- **Opzione A (preferita)**: la placeholder map contiene i valori reali by design (è il diff documentation). **Aggiungere `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` all'allowlist di gitleaks** via `[allowlist] paths = [...]` nel `.gitleaks.toml` — oppure più chirurgicamente, via inline `[[rules.allowlist.regexes]]` non si può, ma `[allowlist] files` sì.
  - Aggiungere in `.gitleaks.toml` un top-level allowlist:
    ```toml
    [allowlist]
    description = "Audit-trail files che documentano le sanitizzazioni"
    paths = [
      '''\.planning/phases/.*/readme-placeholder-map\.md''',
    ]
    ```
- **Opzione B**: in alternativa, escludere il file via `.gitleaksignore`.

Scegliere Opzione A (più discoverable, in-config).

Re-run `gitleaks detect --no-git --config .gitleaks.toml --no-banner` deve essere clean.
  </action>
  <verify>
    <automated>
test -f .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md
test -f README.md
# Zero residui dei leak noti nel README sanitizzato
! grep -qE '6b09204a-58fd-4632-b699-15b1b9eb24a0' README.md
! grep -qiE '@gmail\.com' README.md
! grep -qE 'toto-castaldi\.com' README.md
! grep -qE '146\.190\.232\.60|188\.166\.97\.177|152\.42\.138\.218|185\.199\.108\.153' README.md
! grep -qE 'inspiron' README.md
# Narrative preservato: sezioni chiave ancora presenti
grep -q '^# BACKUP RSYNC' README.md || grep -q 'BACKUP RSYNC' README.md
grep -q '^# SUPABASE' README.md
grep -q 'Architettura target' README.md
grep -qE 'jarvis \(mini PC\)' README.md
! grep -qE 'Jarvis \(mini PC\)' README.md   # title case corretto a lowercase
# LICENSE referenziato in header
grep -q 'License: MIT' README.md || grep -q 'LICENSE' README.md
# Placeholder map esiste con sezioni richieste
grep -q '## Domini e sottodomini' .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md
grep -q '## IP' .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md
grep -q '## UUID' .planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md
# Gitleaks clean (richiede gitleaks installato — se assente, skip ma WARN)
if command -v gitleaks; then
  gitleaks detect --no-git --config .gitleaks.toml --no-banner --redact -v > .planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt 2>&1
  grep -q 'leaks found: 0\|No leaks found' .planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt
else
  echo "WARN: gitleaks non installato — report non generato, run manuale richiesto pre-Plan 03" | tee .planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt
fi
# Placeholder map è allowlisted in .gitleaks.toml
grep -q 'readme-placeholder-map' .gitleaks.toml
    </automated>
  </verify>
  <acceptance_criteria>
    - `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` esiste, contiene 5 sezioni (Domini, IP, UUID, Email/account, Hostname/naming) con tabelle real→placeholder esaustive per ogni classe trovata nel README originale.
    - `README.md` esiste, mantiene la struttura narrative (sezioni `# BACKUP RSYNC`, `# SUPABASE`, `## Architettura target`, ASCII diagram, `## Decisioni architetturali`, `## Asset e credenziali`, ecc.) ma con TUTTI gli identificativi reali sostituiti con placeholder.
    - Zero residui (grep gates sopra tutti verdi): no UUID `6b09204a`, no `toto-castaldi.com`, no email gmail, no IP `146.190.*` / `188.166.*` / `152.42.*` / `185.199.*`, no `inspiron`.
    - ASCII diagram usa `jarvis (mini PC)` lowercase (CONTEXT.md §Specifics).
    - README ha un blocco header introduttivo che dichiara: scopo narrative, placeholder convention, link a LICENSE, istruzioni pre-commit hook.
    - `gitleaks detect --no-git --config .gitleaks.toml --no-banner` sul working tree esce exit 0 con "No leaks found" (output salvato in `.planning/phases/01-foundations-repo-sanitize/gitleaks-worktree-report.txt`). Se gitleaks non è installato sul laptop al momento dell'esecuzione, lo step di Plan 03 (pre-publish) lo ripeterà come gate bloccante.
    - `.gitleaks.toml` ha `[allowlist] paths` che esclude `readme-placeholder-map.md` (file che by design contiene i valori reali nella colonna sinistra).
  </acceptance_criteria>
  <done>
README pubblicabile: narrative preservato (387 → ~390 righe con header disclaimer), zero leak identificativi, ASCII diagram corretto a lowercase. La placeholder map è committata come audit trail. Il working tree è clean rispetto a `.gitleaks.toml`. Plan 03 può procedere al pre-publish check + squash + push.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 2.4: Review README sanitizzato + verify gitleaks clean</name>
  <what-built>README sanitizzato in-place, .gitignore esteso, .gitleaks.toml con custom rules, .pre-commit-config.yaml + GH workflow, LICENSE MIT. Tutto il working tree pulito.</what-built>
  <how-to-verify>
1. Antonio legge `README.md` end-to-end e verifica:
   - Le sezioni narrative attese sono tutte presenti: `# BACKUP RSYNC`, `# SUPABASE` + `## Obiettivo` + `## Architettura target` (con ASCII diagram), `## Decisioni architetturali`, `## Asset e credenziali`, `## Step 1` (1.0, 1.1, 1.2, 1.3, 1.4), `## Convenzioni operative`, `## Roadmap rimanente`, `## Note e issue aperti`, `# VISION`, `# NOTE`.
   - Il diagram ASCII ha `jarvis (mini PC)` lowercase.
   - Zero match per i pattern (verificare visualmente o con grep):
     ```
     grep -nE '6b09204a|toto-castaldi\.com|toto\.castaldi@|146\.190|188\.166|152\.42\.138|185\.199\.108|inspiron' README.md
     ```
     atteso: nessun match.
2. Antonio legge `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` e conferma che la mappa documenta tutte le sostituzioni.
3. Antonio installa pre-commit framework + hook (una tantum):
   ```
   pipx install pre-commit  # o pip install --user pre-commit
   pre-commit install --hook-type pre-push
   ```
4. Antonio esegue una verifica gitleaks finale (locale, se installato):
   ```
   gitleaks detect --no-git --config .gitleaks.toml --no-banner --redact -v
   ```
   atteso: "leaks found: 0" o "No leaks found".
5. Antonio verifica `.gitignore` blocca i file giusti:
   ```
   touch test.cloudflared.json fake.pem volumes/test.txt
   git status   # nessuno dei 3 file deve apparire
   rm test.cloudflared.json fake.pem; rm -rf volumes/
   ```
6. Antonio apre `LICENSE` e conferma: testo MIT canonico, copyright `Antonio Castaldi 2026`, no email.
  </how-to-verify>
  <resume-signal>Scrivi "approved" per procedere a Plan 03 (pre-publish + squash + push public), oppure indica cosa va aggiustato nel README/config (es. "manca menzione di X", "il placeholder Y è sbagliato", "ho trovato un leak residuo in linea N").</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Laptop Antonio (working copy) → git remote GitHub (push) | Boundary critico. Pre-push hook (.pre-commit-config.yaml) deve bloccare secret prima che lascino il laptop. |
| Git remote privato attuale → utenti casuali (post-flip Plan 03) | Tutto ciò che sopravvive a Plan 02 sarà pubblicamente visibile. README + tutti i file tracciati devono essere clean. |
| Repo file system → developer terzo che clona | Il README + .gitleaks.toml + docs guidano l'uso del repo come reference. La sicurezza dipende dalla qualità della sanitizzazione. |
| External (PR contributor) → repo | GH Actions gitleaks workflow gate i PR. Permissions: `contents: read` only (no write). |

## STRIDE Threat Register (ASVS Level 1)

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-02-01 | Information Disclosure | Leak di UUID/IP/email/path in README pre-sanitize | mitigate | Sanitize in-place via sed map documentata; placeholder map committata come audit trail; gitleaks scan clean sul working tree è gate bloccante prima di Plan 03; `.gitleaks.toml` con 7 custom rules + allowlist mirate; pre-push hook locale + GH Action CI come anti-regressione. |
| T-02-02 | Information Disclosure | Futuro commit di .env/credentials per dimenticanza | mitigate | `.gitignore` esteso copre 7 classi di infra secret; `.env.*` con `!.env.example` exception preservato; pre-push hook gitleaks intercetta secrets non match-ati da gitignore. |
| T-02-03 | Tampering | Custom rules `.gitleaks.toml` regex broken o troppo permissive (false negative) | mitigate | Rules validate contro placeholder noti (allowlists) + leak noti (grep test); GH Action CI ri-valida ad ogni push (anche modifiche al .gitleaks.toml stesso); review umana del file in Task 2.4. |
| T-02-04 | Tampering | Pre-commit framework che potrebbe bypassare la verifica (commit con --no-verify) | accept | Pre-push, non pre-commit; chi vuole bypassare può sempre, ma il gate GH Action sul remote è il safety net. Solo Antonio commit-a in v1 → trust del developer. |
| T-02-05 | Information Disclosure | `readme-placeholder-map.md` ESSO STESSO contiene i valori reali nella colonna sx | mitigate | Aggiunto a `[allowlist] paths` in `.gitleaks.toml` esplicitamente. Documentato in placeholder map stessa che è "by design audit trail, non pubblicabile fuori repo" — ma siccome il file vive in `.planning/` e tutto `.planning/` viene committato pubblicamente (per la sua natura di documentazione GSD), bisogna decidere se: (a) accettare che la map vive in chiaro nel repo public ANCHE post-flip — questo è un leak reale, perché contiene i mapping. **Decisione**: la map vive sul repo ma è una decisione consapevole — il valore di avere il diff documentato supera il rischio (i valori reali sono già recuperabili via Certificate Transparency per il dominio + WHOIS per gli IP). Documentato in `<deferred>` di CONTEXT.md analogo: future audit potrebbe rimuovere o cifrare la map. |
| T-02-06 | Spoofing | Attaccante crea PR malevolo che modifica `.gitleaks.toml` per disabilitare rules | mitigate | GH branch protection rules su `main` post-publish (Plan 03 prevede di mantenerle); review umana per ogni PR; per repo single-dev v1 il rischio è basso (no contribuzioni attese). |
| T-02-07 | Repudiation | Sanitizzazione manuale senza trail | mitigate | `readme-placeholder-map.md` committato; lo script `sanitize-readme.sh` non viene committato ma la sed map è dentro la action di questo plan, riproducibile e auditabile via git log del README. |
| T-02-SC | Tampering | Package supply chain: gitleaks rev pinning, pre-commit framework, gitleaks-action@v2 | mitigate | `rev: v8.24.2` (o tag specifico al moment dell'install) NON `master`; gitleaks-action@v2 è action ufficiale del progetto; nessun npm/pip install in scope di questo plan oltre `pre-commit` Python tool che è di GitHub (Yelp originale, poi PCA). Package Legitimacy Gate full audit non si applica (no package new install in build). |
</threat_model>

<verification>
End-to-end del plan 02 (eseguibile localmente sul laptop di Antonio):

```bash
# 1. Sintassi config
python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gitleaks.yml'))"

# 2. .gitignore funziona
git check-ignore -v test.cloudflared.json 2>/dev/null || echo "FAIL"
git check-ignore -v fake.pem 2>/dev/null || echo "FAIL"

# 3. Gitleaks clean working tree
gitleaks detect --no-git --config .gitleaks.toml --no-banner --redact -v
echo "Exit: $?"   # atteso 0

# 4. Grep negativi sul README (zero leak noti)
grep -nE '(6b09204a|toto-castaldi\.com|toto\.castaldi@|146\.190|188\.166|152\.42\.138|185\.199\.108\.153|inspiron)' README.md
echo "Exit: $?"   # atteso 1 (nessun match)

# 5. Sezioni narrative preservate
grep -c '^#' README.md   # atteso ≥ 10 sezioni
grep -q 'jarvis (mini PC)' README.md && echo "OK lowercase"

# 6. LICENSE
head -1 LICENSE   # atteso: "MIT License"
grep -q 'Copyright (c) 2026 Antonio Castaldi$' LICENSE
```
</verification>

<success_criteria>
Plan 02 è completo quando:
- [ ] `.gitignore` esteso con 7 classi di infra secret + baseline GSD preservato.
- [ ] `.gitleaks.toml` esiste con 7 custom rules + allowlist + path allowlist per placeholder map.
- [ ] `.pre-commit-config.yaml` esiste, pinna gitleaks v8.x, stages `[pre-push]`.
- [ ] `.github/workflows/gitleaks.yml` esiste, fetch-depth: 0, gitleaks-action@v2, GITLEAKS_CONFIG impostato.
- [ ] `LICENSE` esiste, MIT canonico, copyright 2026 Antonio Castaldi (no email).
- [ ] `README.md` sanitizzato in-place: zero leak (UUID/IP/email/FQDN/hostname laptop), narrative + ASCII preservati, header introduttivo aggiunto.
- [ ] `.planning/phases/01-foundations-repo-sanitize/readme-placeholder-map.md` documenta tutte le sostituzioni.
- [ ] `gitleaks detect --no-git --config .gitleaks.toml` sul working tree esce 0 finding (report salvato in `.planning/.../gitleaks-worktree-report.txt`).
- [ ] Human verify (Task 2.4) approvato.
</success_criteria>

<output>
Create `.planning/phases/01-foundations-repo-sanitize/01-02-SUMMARY.md` when done.

Il SUMMARY deve includere:
- Conteggio finale dei file modificati/creati.
- Output sintetico di `gitleaks detect` finale (0 finding atteso).
- Lista delle 7 classi di leak sostituite nel README, con esempi pre/post.
- Versione gitleaks effettivamente pinnata (può differire da v8.24.2 se al moment una più recente è disponibile).
- Note operative per Plan 03 (es. "pre-commit hook installato? sì/no", "gitleaks installato localmente? versione X").
</output>
