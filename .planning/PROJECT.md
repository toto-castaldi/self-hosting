# jarvis (self-hosting)

## What This Is

`jarvis` è un mini PC casalingo (Ubuntu 26.04, 16 GB RAM) che Antonio sta
trasformando in piattaforma self-hosted personale. L'obiettivo è ospitare
progressivamente i servizi attualmente sparsi tra Supabase Cloud e
DigitalOcean, partendo da Lumio — un'app web fullstack in alpha — e
arrivando a una piattaforma multi-stack documentata e riferibile.

## Core Value

**Lumio gira in produzione su jarvis con un Supabase self-hosted, e il
repo che racconta il setup è pubblicabile su GitHub senza leak di
identificativi.** Tutto il resto (Helix, backup off-site, observability
avanzata) è secondario.

## Requirements

### Validated

(Nessuna — v1 deve ancora chiudere)

### Active

- [ ] Lumio web app gira end-to-end su jarvis (frontend + Supabase self-hosted) con dominio Cloudflare
- [ ] Stack Supabase di Lumio installato in `/home/toto/lumio/` (Docker Compose, volumi locali)
- [ ] Backup automatico Postgres + storage Lumio on-host con retention (no off-site in v1)
- [ ] Cloudflare Tunnel espone l'app pubblica; admin via Tailscale + CF Access
- [ ] Cutover Lumio da Supabase Cloud + DigitalOcean → jarvis (alpha, nessun utente reale, finestra rilassata)
- [ ] Repo sanitizzato: niente UUID tunnel, IP, email, percorsi credentials nel codice/docs
- [ ] README narrativo che racconta il setup (architettura, scelte, screenshots) per uso referenziale
- [ ] Repo pushabile public su GitHub con LICENSE + CI minima

### Out of Scope

- Helix (secondo stack Supabase per progetto separato) — deferito a v2; v1 deve dimostrare il pattern con Lumio prima di replicarlo
- Backup off-site (Backblaze B2 / Hetzner) — i dati Lumio in alpha sono preziosi ma non production-critical; backup on-host accettabile in v1
- Observability avanzata (Grafana, Loki, Prometheus stack) — logs base + healthcheck Docker sufficienti in v1
- HA / replica Postgres — single-node accettabile per scala attuale; HA solo se Lumio passa da alpha a production reale
- Estrazione librerie riusabili dal repo — il repo nasce come setup personale referenziabile, non come prodotto per terzi
- Migrazione di altri servizi DO (oltre Lumio) — focus stretto su Lumio in v1

## Context

- **Stack di partenza Lumio**: app web fullstack su Supabase Cloud (DB + Auth + Storage) con qualcosa hostato su DigitalOcean. La migrazione tira giù tutto su jarvis.
- **Stato Lumio**: alpha, nessun utente reale, traffico zero. Cutover può essere rilassato (no hard window notturna).
- **Dati Lumio**: pochi ma preziosi (schema, config, test data costruita nel tempo) — perdere non è disastro ma è lavoro buttato, quindi backup robusto serve da subito.
- **Vincolo Ubuntu 26.04**: repo apt `cloudflared` non ha ancora pacchetto per `oracular`/`plucky`/`questing`; workaround → fissare repo su `noble`. Documentato come decisione.
- **Memoria utente**: c'è un altro progetto distinto chiamato HAL (con regole tipo `HAL_SKIP_GITLEAKS`, `hal` lowercase). Quelle regole **non si applicano qui**. In questo repo l'host si chiama letteralmente `jarvis`.
- **Repo non ancora public**: README originale contiene asset identificativi (Tunnel UUID, IP, email account, percorsi credentials). Phase 1 esiste apposta per ripulire prima di pushare pubblico.
- **Lingua**: PROJECT.md, risposte all'utente, contenuti discorsivi in **italiano**. Codice, commenti tecnici, file strutturati (REQUIREMENTS, ROADMAP, JSON) in **inglese**.

## Constraints

- **Hardware**: Mini PC 16 GB RAM, single host — niente cluster, niente HA cross-node. Capacità da rispettare in scelte di stack.
- **Sicurezza**: in caso di trade-off scope vs. sicurezza, **vince la sicurezza** (es. niente porte aperte sul router, tutto dietro Cloudflare Tunnel + Tailscale).
- **Tech stack**: Supabase self-hosted via Docker Compose; Cloudflare Tunnel + Cloudflare Access; Tailscale per admin path. Stack imposto, non da rivalutare.
- **Timeline**: nessuna deadline. Qualità sopra velocità. Niente shortcut che indeboliscono la sicurezza per chiudere prima.
- **Repo public-ready**: nessun secret, UUID, IP o email nel codice committato. Pre-push hook o equivalente per prevenire regressioni.
- **Project mode**: Vertical MVP — ogni fase deve consegnare una capability end-to-end osservabile, non un layer tecnico orizzontale.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Due stack Supabase separati (Lumio + Helix), non condivisi | Isolation tra progetti, possibilità di spegnere/aggiornare uno senza toccare l'altro | — Pending (Helix è v2) |
| Esposizione public via Cloudflare Tunnel; admin via Tailscale + CF Access | Niente porte aperte sul router, doppio canale (pubblico/admin) con auth diverse | — Pending |
| Cutover Lumio: finestra rilassata, no hard window notturna | App in alpha senza utenti reali — il vincolo "hard window" del setup originale non è più necessario | — Pending |
| Backup off-site deferito a Phase 5 (scelta B2 vs Hetzner vs entrambi a Phase 5) | v1 deve chiudere; off-site è ortogonale al goal "Lumio gira su jarvis" | — Pending |
| Repo apt cloudflared fissato su `noble` (Ubuntu 26.04 workaround) | Pacchetto non disponibile per `oracular`/`plucky`/`questing` | — Pending |
| Layout filesystem: `/home/toto/jarvis/`, `/home/toto/lumio/`, `/etc/cloudflared/` | Separazione netta tra config tunnel, stack app, e config produttiva root-owned | — Pending |

## Evolution

Questo documento evolve a phase transitions e milestone boundaries.

**Dopo ogni phase transition** (via `/gsd-transition`):
1. Requirement invalidato? → sposta in Out of Scope con motivazione
2. Requirement validato? → sposta in Validated con phase reference
3. Nuovi requirement emersi? → aggiungi in Active
4. Decisioni da loggare? → aggiungi a Key Decisions
5. "What This Is" ancora accurato? → aggiorna se drift

**Dopo ogni milestone** (via `/gsd:complete-milestone`):
1. Review completa di tutte le sezioni
2. Core Value — ancora la priorità giusta?
3. Audit Out of Scope — i motivi reggono ancora?
4. Update Context con lo stato corrente

---
*Last updated: 2026-05-22 dopo inizializzazione*
