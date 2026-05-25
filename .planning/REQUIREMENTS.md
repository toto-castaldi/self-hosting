# Requirements: jarvis (self-hosting)

**Defined:** 2026-05-22
**Core Value:** Lumio gira in produzione su jarvis con Supabase self-hosted, e il repo che racconta il setup è pubblicabile su GitHub senza leak di identificativi.

## v1 Requirements

Each requirement is observable / user-testable from Antonio's perspective (he is both operator and end user of jarvis).

### HOST — Baseline jarvis

- [x] **HOST-01**: Ubuntu 26.04 su `jarvis` ha utenti non-root con sudo, SSH key-only (no password auth), unattended-upgrades attivo per security patches
- [x] **HOST-02**: Docker Engine + Compose v2 installati e funzionanti, utente `toto` può eseguire `docker` senza sudo
- [x] **HOST-03**: Tailscale installato e attivo come servizio; `jarvis` raggiungibile dal MagicDNS della tailnet
- [x] **HOST-04**: Layout filesystem creato: `/home/toto/jarvis/`, `/home/toto/lumio/`, `/etc/cloudflared/` con ownership corretti
- [x] **HOST-05**: Firewall (ufw o nftables) attivo, default-deny inbound tranne SSH da Tailscale e loopback

### NET — Cloudflare Tunnel + Access

- [ ] **NET-01**: `cloudflared` installato da apt con repo pinnato a `noble` (workaround Ubuntu 26.04), gestito come systemd service con hardening (User=cloudflared, ProtectSystem=strict, NoNewPrivileges)
- [ ] **NET-02**: Tunnel named creato via `cloudflared tunnel create`, credentials file `<UUID>.json` mode `0640 root:cloudflared` in `/etc/cloudflared/`
- [ ] **NET-03**: Config tunnel in `/etc/cloudflared/config.yml` con ingress rules hostname-based: app pubblica → Kong 8000 sui soli path `/auth /rest /realtime /storage /functions/v1`, catch-all `http_status:404`
- [ ] **NET-04**: Cloudflare Access policy attiva su tutto ciò che non è il path pubblico dell'app (in v1: nessun admin path pubblico — Studio resta solo Tailscale)
- [ ] **NET-05**: CI check (locale o GH Action) che valida `cloudflared tunnel ingress validate` prima del deploy di un config modificato

### LUMIO — Stack Supabase self-hosted + cutover

- [ ] **LUMIO-01**: Snapshot pinnato di `supabase/supabase` (commit hash documentato in `.planning/PROJECT.md`) copiato in `/home/toto/lumio/`
- [ ] **LUMIO-02**: `.env` di Lumio con tutti i 17 secrets rigenerati (JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY, POSTGRES_PASSWORD, DASHBOARD_USERNAME/PASSWORD, VAULT_ENC_KEY 32-char, ecc.) — file NON in git, presente in `.gitignore`
- [ ] **LUMIO-03**: Stack Supabase up con tutti i 13 services healthy (`docker compose ps` → tutti healthy), versioni pinnate (PG 15.8.1.085, Kong 3.9.1, Studio 2026.04.27, ecc.)
- [ ] **LUMIO-04**: Frontend Lumio (dovunque sia hostato — Vercel o jarvis stesso, scelta da fare in plan-phase) parla con il Supabase di jarvis via il nuovo dominio pubblico
- [ ] **LUMIO-05**: Dati Lumio Cloud migrati su jarvis: `supabase db dump` (roles + schema + data, 3-file approach), `aws s3 sync` per i file dei buckets storage. Restore single-transaction con `session_replication_role=replica`
- [ ] **LUMIO-06**: Smoke test post-cutover passato: login utente (creato pre-cutover), creazione record, fetch record, upload+download di un file storage — tutti funzionanti contro jarvis
- [ ] **LUMIO-07**: DNS pubblico (Cloudflare) flippato sul nuovo tunnel; vecchio progetto Supabase Cloud + droplet DO spenti (non cancellati subito — keep 30 giorni come safety net)

### BACKUP — Postgres + storage on-host

- [ ] **BACKUP-01**: Systemd timer giornaliero esegue `pg_dump --format=custom` + `pg_dumpall --globals-only` del Postgres di Lumio, output in `/var/backups/lumio/`
- [ ] **BACKUP-02**: Storage Lumio (`volumes/storage/`) viene snapshottato giornalmente con `rsync --link-dest`, **prima** del dump DB per evitare orphan rows (orphan files OK)
- [ ] **BACKUP-03**: Tutti gli artefatti backup sono cifrati con `age` (chiave pubblica on-host, chiave privata off-host in 1Password + copia cartacea)
- [ ] **BACKUP-04**: Retention GFS attiva: 7 daily + 4 weekly + 3 monthly, cleanup automatico via systemd timer
- [ ] **BACKUP-05**: Restore drill mensile: systemd timer spinge container `supabase/postgres` disposable, restora ultimo backup, runna 3 smoke queries, tear-down; output loggato. Se fallisce, alert (email o ntfy).

### REPO — Public-ready GitHub

- [x] **REPO-01**: `gitleaks` v8 configurato come pre-push hook locale + GitHub Action; custom rules per Cloudflare Tunnel UUID, IP pubblici, email personali, paths cloudflared, JWT-like strings
- [x] **REPO-02**: `.gitignore` esteso con: cloudflared credentials JSON / cert.pem, `.env*` (incluso `.env.local`), Docker volume mount roots, Tailscale state, SSH keys, materiale TLS, systemd drop-in override
- [x] **REPO-03**: README narrativo nuovo: overview → architecture diagram → stack list → decision log → security model → screenshots. Ogni asset identificativo sostituito con placeholder (`example.com`, `203.0.113.x`, UUID generico)
- [ ] **REPO-04**: History squash su orphan branch `public-v1` (la storia attuale "rifare", "pre push" non ha valore narrativo e potrebbe contenere il README pre-sanitize)
- [x] **REPO-05**: `LICENSE` aggiunto (decisione: nessuna LICENSE = all-rights-reserved, OPPURE dual MIT/CC BY 4.0 — da chiudere in plan-phase Repo)
- [ ] **REPO-06**: Pre-publish checklist passata (bundle backup → grep → gitleaks → trufflehog → exiftool sugli screenshot → push su nuovo remote public) — output loggato come evidence in `.planning/`
- [ ] **REPO-07**: Repo pushato pubblico su GitHub, README pubblico verificato (rendering, no leak visibile)

## v2 Requirements

Deferred to next milestone.

### HELIX — Secondo stack Supabase

- **HELIX-01**: Stack Supabase separato in `/home/toto/helix/` per progetto Helix (porte diverse, secrets separati)
- **HELIX-02**: Pattern di deploy/backup riusato da Lumio, documentato come "playbook" generico

### OFFSITE — Backup esterni

- **OFFSITE-01**: Replica notturna degli artefatti `age`-encrypted verso destinazione off-site (B2 vs Hetzner — decisione differita)
- **OFFSITE-02**: Restore drill cross-storage (restore da off-site, non solo on-host)

## Out of Scope

| Feature | Reason |
|---------|--------|
| HA / replica Postgres | Lumio è in alpha, single-node accettabile; HA solo se traffico/criticità giustificano costo operativo |
| Observability stack avanzato (Grafana / Loki / Prometheus) | Logs Docker + healthcheck Compose sufficienti in v1; dashboard avanzate aggiungono ops overhead non giustificato |
| Estrazione librerie riusabili dal repo | Il repo nasce come setup personale referenziabile, non come prodotto per terzi |
| Migrazione altri servizi DO oltre Lumio | Focus stretto v1; altri servizi solo dopo che il pattern Lumio è stabile |
| CI/CD su jarvis (GH Actions self-hosted runner) | Non richiesto per v1; deploy manuale + scripts è sufficiente |
| Public exposure di Studio Supabase | Non si espone mai uno strumento DB-mutating via tunnel — Studio resta dietro Tailscale forever |

## Traceability

Aggiornato dopo creazione ROADMAP.md.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOST-01 ... HOST-05 | Phase 1 | Complete (Plan 01 host-harden) |
| REPO-01, REPO-02, REPO-03, REPO-05 | Phase 1 | Complete (Plan 02 repo-sanitize) |
| REPO-04, REPO-06, REPO-07 | Phase 1 | Pending (Plan 03 repo-publish) |
| NET-01 ... NET-05 | Phase 2 | Pending |
| LUMIO-01 ... LUMIO-03 | Phase 3 | Pending |
| LUMIO-04 ... LUMIO-07 | Phase 4 | Pending |
| BACKUP-01 ... BACKUP-05 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0

---
*Requirements defined: 2026-05-22*
*Last updated: 2026-05-22 dopo inizializzazione*
