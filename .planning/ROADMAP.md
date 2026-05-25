# Roadmap: jarvis (self-hosting) v1

**Created:** 2026-05-22
**Project mode:** Vertical MVP — ogni phase consegna una capability osservabile end-to-end.
**Total phases:** 5 (coarse)
**Total requirements mapped:** 30 / 30 ✓

---

## Phase 1: Foundations & Repo Sanitize
**Goal:** `jarvis` è un host Ubuntu 26.04 hardened pronto a ospitare servizi, e il repo `self-hosting` è privo di leak identificativi pronto al push public.
**Mode:** mvp
**Requirements:** HOST-01, HOST-02, HOST-03, HOST-04, HOST-05, REPO-01, REPO-02, REPO-03, REPO-04, REPO-05, REPO-06, REPO-07
**Success Criteria:**
1. `ssh jarvis` funziona via Tailscale; password auth disabilitata; `docker ps` runna da utente `toto` senza sudo
2. `ufw status` mostra default-deny inbound; solo SSH (Tailscale CIDR) e loopback aperti
3. `gitleaks detect --no-git` (working tree) e `gitleaks detect` (history dopo squash) tornano 0 finding sul repo
4. Repo pushato su GitHub come pubblico, README pubblico verificato senza leak (UUID/IP/email/paths sostituiti con placeholder)
5. Pre-publish checklist eseguita e committata come evidence in `.planning/`

**Plans:** 3 plans

Plans:
- [x] 01-host-harden-PLAN.md — Audit-first + hardening Ubuntu (SSH, Docker, ufw, filesystem layout, unattended-upgrades, Tailscale verify)
- [x] 02-repo-sanitize-PLAN.md — .gitignore esteso, gitleaks v8 + custom rules + pre-push + GH Action, README sanitize-in-place, LICENSE MIT
- [x] 03-repo-publish-PLAN.md — Pre-publish checklist, squash a orphan public-v1, force-push, flip visibility public (SKIPPED — già public), smoke verify

**UI hint:** no

---

## Phase 2: Public Pipe (Cloudflare Tunnel + Access)
**Goal:** Un tunnel Cloudflare named, hardened e configurato espone un endpoint placeholder di jarvis su un dominio pubblico, pronto a essere riprogrammato verso Lumio.
**Mode:** mvp
**Requirements:** NET-01, NET-02, NET-03, NET-04, NET-05
**Success Criteria:**
1. `systemctl status cloudflared` running come user `cloudflared` con tutte le direttive hardening attive
2. `curl https://<placeholder-host>.<dominio>/health` ritorna 200 da Internet (via CF) puntando a un container placeholder su jarvis
3. `curl https://<placeholder-host>.<dominio>/_admin` (path non in ingress) ritorna 404 dal catch-all
4. `cloudflared tunnel ingress validate` exit 0 in CI/local pre-deploy
5. Cloudflare Access policy esiste e funziona su almeno un hostname admin (anche se non c'è ancora Studio reale dietro)

**UI hint:** no

---

## Phase 3: Lumio Stack Up (Supabase self-hosted)
**Goal:** Lo stack Supabase di Lumio gira su jarvis in `/home/toto/lumio/` con tutti i 13 services healthy, ma **senza dati produzione ancora** (database vuoto di Lumio, secrets già rigenerati).
**Mode:** mvp
**Requirements:** LUMIO-01, LUMIO-02, LUMIO-03
**Success Criteria:**
1. `docker compose ps` in `/home/toto/lumio/` mostra tutti i 13 services healthy
2. Studio accessibile via Tailscale (`http://jarvis:3000`) con auth dashboard, non accessibile via tunnel pubblico
3. Versioni runtime esattamente quelle pinnate in `STACK.md` (verificato con `docker compose images`)
4. `.env` di Lumio è in `.gitignore` (tested via `git check-ignore`), tutti i 17 secrets generati con strumenti adatti (no defaults)
5. Schema Supabase base (auth, storage, _realtime, public) presente e PostgREST risponde a `/rest/v1/` con HTTP 200 (anche se nessuna tabella custom)

**UI hint:** yes (Studio dashboard è UI, anche se admin-only)

---

## Phase 4: Lumio Cutover (Dati + DNS)
**Goal:** Lumio è completamente migrato da Supabase Cloud + DigitalOcean a jarvis: dati DB + storage migrati, frontend integrato, DNS pubblico flippato, smoke test passato.
**Mode:** mvp
**Requirements:** LUMIO-04, LUMIO-05, LUMIO-06, LUMIO-07
**Success Criteria:**
1. `supabase db dump` (3-file) eseguito su Cloud, restore single-transaction su jarvis completato; row counts su tabelle chiave matchano source ± delta atteso
2. `aws s3 sync` ha copiato i file dei buckets storage da Cloud → `volumes/storage/` su jarvis; consistency check passato (no row senza file, file orfani accettati)
3. Frontend Lumio (production deployment) usa il nuovo `https://<lumio-host>.<dominio>` di jarvis; login + creazione record + upload/download funzionano end-to-end
4. DNS pubblico flippato sul nuovo tunnel CF; vecchio progetto Supabase Cloud + droplet DO ancora accesi ma "frozen" (read-only, marcatura visibile)
5. Calendar item creato per spegnimento definitivo di Cloud + DO dopo 30 giorni di stabilità

**UI hint:** yes (frontend Lumio + Studio)

---

## Phase 5: Backup & Restore Drill
**Goal:** Lumio su jarvis ha backup automatici cifrati con retention, e un restore drill verificato ha provato che da un backup si torna a uno stato operativo.
**Mode:** mvp
**Requirements:** BACKUP-01, BACKUP-02, BACKUP-03, BACKUP-04, BACKUP-05
**Success Criteria:**
1. `systemctl list-timers` mostra timer giornaliero backup attivo; ultimo run completed status 0
2. `/var/backups/lumio/` contiene artefatti `age`-encrypted con retention GFS applicata (7 daily + 4 weekly + 3 monthly visibili)
3. Restore drill mensile ha runnato almeno una volta: container disposable, restore, smoke queries, tear-down — tutto exit 0
4. Chiave privata `age` NON è sul host (verifica esplicita); chiave pubblica `age` documentata in `.planning/PROJECT.md` Key Decisions
5. Documento `runbook-backup.md` in repo (post-sanitize, no path leak) descrive: come fare restore manuale, dove trovare la chiave privata, frequenza retention, cosa controllare se drill fallisce

**UI hint:** no

---

## Phase Dependencies

```
Phase 1 (Foundations + Repo) ──┐
                               ├──→ Phase 2 (Public Pipe) ──→ Phase 3 (Lumio Stack) ──→ Phase 4 (Cutover) ──→ Phase 5 (Backup)
                               │
                               └─ REPO può procedere in parallelo a HOST nella Phase 1
                                  ma il push public NON avviene finché Phase 1 non chiude
                                  (perché serve gitleaks su tutto il repo, README incluso)
```

Phase 1 è la sola con due tracks paralleli (host setup + repo sanitize); le altre sono strettamente sequenziali per dipendenze infrastrutturali.

## Open Decisions (da chiudere in plan-phase)

Queste decisioni emergono dalla research e sono parcheggiate per la phase rilevante:

- **REPO-05 LICENSE**: nessuna (all-rights-reserved) vs dual MIT + CC BY 4.0 → decidi in Phase 1
- **LUMIO-04 frontend host**: resta dov'è (Vercel/Netlify) vs ospitato su jarvis dietro Kong → decidi in Phase 4
- **BACKUP WAL archiving**: solo `pg_dump` (RPO ~24h) vs WAL archiving locale (RPO ~15min) → decidi in Phase 5
- **BACKUP storage location**: stesso disco `/var/backups/` (semplice) vs secondo disco USB (più sicuro a fronte di guasto disco) → decidi in Phase 5
- **BACKUP alert sink**: email (semplice) vs ntfy / Telegram bot → decidi in Phase 5
