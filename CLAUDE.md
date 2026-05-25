# self-hosting (jarvis)

Piattaforma self-hosted personale di Antonio: un mini PC casalingo
(`jarvis`, Ubuntu 26.04, 16 GB RAM) che ospita progressivamente i
servizi attualmente sparsi tra Supabase Cloud e DigitalOcean. v1 è
focalizzato su **migrazione completa di Lumio** (app web fullstack
in alpha, nessun utente reale) + **repo public-ready su GitHub**.

## GSD workflow

Questo progetto usa il workflow [Get Shit Done](https://github.com/get-shit-done-cc).
Prima di lavorare:

1. Leggi `.planning/STATE.md` per sapere dove siamo.
2. Per pianificare la fase corrente: `/gsd-plan-phase <N>`.
3. Per eseguire: `/gsd-execute-phase` (richiede agenti GSD installati).
4. Per progresso/situazione: `/gsd-progress`.

I documenti vivi sono in `.planning/`:
- `PROJECT.md` — contesto, requirement, decisioni, vincoli (in **italiano**).
- `REQUIREMENTS.md` — v1 requirement con REQ-IDs e mapping fasi.
- `ROADMAP.md` — 5 fasi coarse, vertical MVP mode.
- `STATE.md` — memoria di sessione corrente.
- `research/SUMMARY.md` — research inline su Supabase self-host, Cloudflare Tunnel, backup, repo hardening (subagent GSD non installati → general-purpose agenti inline).
- `research/STACK.md`, `ARCHITECTURE.md`, `BACKUP.md`, `PITFALLS.md` — dettagli completi.
- `config.json` — preferenze workflow (yolo, coarse, sequential, quality models).

## Configurazione GSD

- **Mode**: `yolo` — auto-approve durante esecuzione
- **Granularity**: `coarse` — 5 fasi, 1-3 plan ciascuna
- **Execution**: `sequential` — un plan alla volta (dipendenze dure infra)
- **Commit docs**: `true` — `.planning/` committato in git
- **Model profile**: `quality` — Opus per research/roadmap
- **Workflow agents**: research ON, plan-check ON, verifier ON
- **Project mode**: `mvp` (Vertical MVP)

## ⚠️ Avvertimenti

1. **GSD agents non installati globalmente** in questo ambiente. Prima
   di `/gsd-plan-phase` o `/gsd-execute-phase`, esegui:
   ```
   npx get-shit-done-cc@latest --global
   ```
   Altrimenti l'orchestratore deve fare planning ed esecuzione inline.

2. **Repo NON ancora public-ready.** La Phase 1 esiste apposta. Fino al
   completamento di Phase 1, evita di pushare il repo su GitHub
   pubblicamente — il README originale contiene asset identificativi
   (Tunnel UUID, IP, email account, percorsi credentials) che
   vanno auditati prima.

3. **Lingua**: PROJECT.md, le risposte all'utente, e i contenuti
   discorsivi sono in **italiano**. Codice, commenti tecnici e file
   strutturati in inglese.

4. **Naming**: l'host si chiama `jarvis`. (Esiste un altro progetto
   separato chiamato HAL — non c'entra qui, le memory rules su
   "hal lowercase / HAL_SKIP_GITLEAKS" non si applicano a questo repo.)

5. **Sicurezza wins ties**: in caso di trade-off scope vs. sicurezza,
   vince la sicurezza.

## Layout filesystem (target)

```
/home/toto/jarvis/      ← cloudflared dev config, script, docs
/home/toto/lumio/       ← stack Supabase Lumio (compose + volumi)
/home/toto/helix/       ← stack Supabase Helix (compose + volumi) [v2]
/etc/cloudflared/       ← config produttiva del tunnel (root-owned)
```

## Decisioni chiave

Vedi `.planning/PROJECT.md` § Key Decisions. In sintesi:

- Due stack Supabase **separati** (Lumio + Helix), non condivisi.
- Esposizione: **Cloudflare Tunnel** per public, **Tailscale + CF Access** per admin.
- Cutover Lumio: **finestra rilassata** (alpha, no utenti) — no hard window.
- Backup on-host con `age` + restore drill mensile in v1; off-site (B2 vs Hetzner) deferito a milestone v2.
- Repo apt cloudflared fissato su `noble` (workaround Ubuntu 26.04). Refresh chiave firma entro 30 Apr 2026.
- History repo: squash a orphan branch `public-v1` prima del push pubblico (la storia attuale non ha valore narrativo).
