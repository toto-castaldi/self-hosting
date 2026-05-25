# Phase 1: Foundations & Repo Sanitize - Context

**Gathered:** 2026-05-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Due track paralleli che chiudono in un'unica phase:

1. **HOST track** — `jarvis` (Ubuntu 26.04, 16 GB RAM) è un host hardened
   pronto a ospitare i futuri stack Supabase. Coverage: HOST-01..HOST-05.
2. **REPO track** — il repo `self-hosting` è privo di leak identificativi
   (UUID tunnel, IP, email, paths credentials), ha LICENSE, ha gitleaks
   pre-push + GH Action, ed è pushato pubblico su GitHub con README
   sanitizzato. Coverage: REPO-01..REPO-07.

Out of scope per Phase 1: Cloudflare Tunnel (Phase 2), Supabase stack
(Phase 3), cutover Lumio (Phase 4), backup (Phase 5).

</domain>

<decisions>
## Implementation Decisions

### Host baseline strategy
- **D-01:** Stato attuale di `jarvis` = **parzialmente configurato**. Confermato: utente `toto` esiste, SSH key-only attivo, Tailscale installato (jarvis raggiungibile via Tailscale dal laptop tramite `/etc/hosts` workaround: `100.113.232.126 jarvis`). Da verificare: Docker, ufw, filesystem layout, unattended-upgrades, sudoers config.
- **D-02:** **Audit-first.** La prima task della Phase 1 è uno script idempotente che verifica HOST-01..HOST-05 sullo stato attuale e produce un report di cosa manca. Le task successive sono guidate dall'output dell'audit, non da assunzioni a priori.

### Firewall
- **D-03:** **`ufw`** (non `nftables`). Wrapper su nftables è sufficiente per la policy minimale di v1 (default-deny inbound + allow SSH dal Tailscale CIDR + loopback). Sintassi friendly = runbook pubblico leggibile. Se in futuro emergono use case che richiedono sets/maps atomici, si migra a nftables nativo (decisione differita).

### README & repo content
- **D-04:** **Sanitize-in-place** del README esistente (387 righe). Preservi il narrative attuale (sezione BACKUP RSYNC, sezione SUPABASE setup, ASCII architecture diagram), sostituendo ogni leak con placeholder: UUID generico, `example.com`, `203.0.113.x` (TEST-NET-3), path `/etc/cloudflared/cert.pem.example`, email scrubbed. NON rewrite from scratch.

### LICENSE & GitHub pubblicazione
- **D-05:** **LICENSE = MIT** (solo MIT, no dual licensing). Repo è "narrative referenceable" ma MIT non costa nulla e copre sia codice (script, compose snippets) sia prose senza split tecnico. Semplice e standard.
- **D-06:** **Flip visibility del repo esistente** (NON nuovo repo). Sequenza: squash a orphan branch `public-v1` → force-push come `main` del repo privato attuale → settings GitHub: private → public.
- **D-07:** **Rischio reflog GitHub (~90gg post force-push) accettato esplicitamente.** Razionale: la storia attuale ha solo 5 commit GSD + 2 commit messy ("rifare", "pre push"); nessun catastrofico secret hard-coded già verificato pre-squash. NO mitigation via GitHub Support ticket. La pre-publish checklist (REPO-06) deve comunque includere gitleaks su tutta la history pre-squash come safety net last-mile.

### Claude's Discretion
- Dettaglio del audit script (linguaggio, flag, output format) → planner decide.
- Custom gitleaks rules exact regex patterns → planner decide (research/PITFALLS.md ha già la lista delle classi: UUID v4, IP pubblici, email, paths cloudflared, JWT-like).
- Ordine delle task HOST vs REPO all'interno della phase → planner decide (sono indipendenti, l'unico vincolo è che il push public non avviene finché entrambi i track non chiudono).
- Esatto comando `git filter-repo` / `git checkout --orphan` per la squash → planner decide; il vincolo è "orphan branch chiamato `public-v1`".

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/PROJECT.md` — overview, constraints, key decisions (filesystem layout, esposizione model)
- `.planning/REQUIREMENTS.md` §HOST §REPO — i 12 requirement mappati su Phase 1 (HOST-01..05, REPO-01..07)
- `.planning/ROADMAP.md` §Phase 1 — goal, success criteria, dipendenze
- `CLAUDE.md` — naming rules (jarvis lowercase, HAL ≠ this project), filesystem layout target, lingua

### Research per implementazione
- `.planning/research/SUMMARY.md` — TL;DR di tutte le scelte v1
- `.planning/research/PITFALLS.md` — gitleaks setup, custom rules classes, history squash strategy, LICENSE rationale, pre-publish checklist (REPO-06)
- `.planning/research/STACK.md` — version pins (utili per HOST-02 Docker version baseline)
- `.planning/research/ARCHITECTURE.md` §"Coexistence con Tailscale" — vincoli firewall + Tailscale interface

### Stato corrente
- `README.md` (radice repo) — il file da sanitizzare in-place; 387 righe; contiene leak (UUID, IP, email, paths)
- `.gitignore` (radice repo) — baseline GSD auto-generated; va esteso con cloudflared credentials JSON, cert.pem, mount roots Docker volume, Tailscale state, SSH keys, TLS material, systemd drop-in override (REQUIREMENTS REPO-02)
- `.planning/STATE.md` — stato GSD corrente

### Memory dell'utente (dal sistema)
- `~/.claude/projects/-home-toto-scm-projects-self-hosting/memory/project_self_hosting.md` — questo repo usa `jarvis` letterale; regole HAL NON si applicano
- `~/.claude/projects/-home-toto-scm-projects-self-hosting/memory/project_laptop_hosts_jarvis.md` — workaround `/etc/hosts` laptop perché MagicDNS Tailscale rotto sul laptop (da investigare, possibile follow-up task)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Nessuno — il repo è solo docs (README.md + .planning/). Niente codice esistente da riusare.

### Established Patterns
- **GSD workflow** (`.planning/`): tutto il planning è già strutturato. Le task di Phase 1 vanno scritte come PLAN.md → executor → SUMMARY.md.
- **Lingua mix:** prose discorsiva in italiano, file strutturati (script, config, log JSON) in inglese. Da rispettare in ogni nuovo file di Phase 1.

### Integration Points
- README.md radice → diventa il README pubblico post-sanitize.
- `.gitignore` → da estendere prima del primo commit di Phase 1 (qualunque artefatto Phase 1 produca, .env scratch dell'audit, ecc., non deve essere committato).
- Le Phase 2..5 dipendono da: (a) `toto` può `docker` senza sudo, (b) filesystem layout `/home/toto/{jarvis,lumio}/` esiste, (c) `/etc/cloudflared/` esiste root-owned. Lock questi prima di chiudere Phase 1.

</code_context>

<specifics>
## Specific Ideas

- L'audit script di D-02 deve essere **idempotente e read-only**: la prima run NON modifica nulla, solo report. Le modifiche arrivano in task successive esplicite. Razionale: l'utente vuole vedere il delta prima di accettarlo.
- Per la squash a orphan: usa `git checkout --orphan public-v1` (semplice) anziché `git filter-repo` (potente ma overkill — non serve preservare history selettiva, si butta tutto).
- Per il flip visibility: prima force-push, poi flip private→public dal settings UI di GitHub. Sequenza importante: se si flippa prima e si force-pusha dopo, c'è una finestra in cui la old history è pubblicamente accessibile.
- Pre-push gitleaks hook: locale via `pre-commit` framework o hook nativo? `pre-commit` è più portabile/condivisibile in repo public; hook nativo è zero-dep ma non si committa. Decisione → planner (Claude's discretion).
- ASCII architecture diagram nel README: mantenere quello attuale, ma "Jarvis (mini PC)" → "jarvis (mini PC)" (lowercase per coerenza naming).

</specifics>

<deferred>
## Deferred Ideas

- **Investigare perché MagicDNS Tailscale è rotto sul laptop** (richiede `/etc/hosts` workaround). Non blocca Phase 1; tracciare come task standalone post-v1 o spostare a memory pulizia post-milestone.
- **`nftables` migration** se in futuro emergono use case avanzati (rate limit complessi, policy per docker bridge isolate). Non in v1.
- **GitHub Support ticket per reflog purge** — esplicitamente declinato in D-07; lasciare nota per future milestone se la sensibilità cambia.
- **Dual licensing MIT + CC BY 4.0** — declinato in D-05; se in futuro qualcuno chiede attribution esplicita sulla prose, si può aggiungere.
- **Rewrite README from scratch** con la struttura formale REPO-03 (overview → diagram → stack → decisions → security model → screenshots) — declinato in D-04; alternativa per v2 se il narrative attuale invecchia male.
- **Repo archive del privato originale post-publish** — non applicabile (D-06: flip visibility, non nuovo repo).

</deferred>

---

*Phase: 1-Foundations & Repo Sanitize*
*Context gathered: 2026-05-24*
