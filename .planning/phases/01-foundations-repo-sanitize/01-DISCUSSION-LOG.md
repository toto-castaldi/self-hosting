# Phase 1: Foundations & Repo Sanitize - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-24
**Phase:** 1-Foundations & Repo Sanitize
**Areas discussed:** Baseline jarvis, Firewall stack, README sanitize approach, LICENSE + GitHub remote (+ reflog risk follow-up)

---

## Baseline jarvis (stato attuale host)

| Option | Description | Selected |
|--------|-------------|----------|
| Greenfield | Ubuntu 26.04 appena installato, niente fatto | |
| Parzialmente configurato | toto + SSH key-only + Tailscale già attivi, resto da verificare | ✓ |
| Quasi pronto | Tutto HOST-01..05 già in piedi, Phase 1 = audit + chiusura buchi | |

**User's choice:** Parzialmente configurato
**Notes:** Confermato via memory `project_laptop_hosts_jarvis.md` (`100.113.232.126 jarvis`) — Tailscale funzionante e jarvis raggiungibile.

### Follow-up — audit step

| Option | Description | Selected |
|--------|-------------|----------|
| Sì, audit prima | Script idempotente che check HOST-01..05 e produce report di cosa manca | ✓ |
| No, so cosa manca | Confermo manualmente cosa è OK e cosa va aggiunto | |
| Audit + verifica esplicita | Audit + 2-3 conferme upfront per skip ovvio | |

**User's choice:** Sì, audit prima
**Notes:** Prima task della phase = audit script.

---

## Firewall stack

| Option | Description | Selected |
|--------|-------------|----------|
| ufw | Wrapper su nftables, sintassi semplice, sufficient per policy v1 | ✓ |
| nftables nativo | Default Ubuntu 26.04 puro, potente ma syntax meno friendly | |
| ufw ora, nftables se serve | ufw v1, nftables solo se emergono use case | |

**User's choice:** ufw
**Notes:** Scelta secca per ufw, non "ufw ora nftables dopo" — niente provisional thinking.

---

## README sanitize approach

| Option | Description | Selected |
|--------|-------------|----------|
| Sanitize-in-place | Preservi narrative, swappi leak con placeholder | ✓ |
| Rewrite from scratch | Nuovo README con struttura REPO-03 formale | |
| Rewrite + cita parti vecchie | Rewrite + recupera blocchi tecnici utili | |

**User's choice:** Sanitize-in-place
**Notes:** Velocità + preservazione del narrative attuale (387 righe, ASCII diagram incluso).

---

## LICENSE

| Option | Description | Selected |
|--------|-------------|----------|
| Nessuna LICENSE | All-rights-reserved di default | |
| Dual MIT + CC BY 4.0 | MIT per codice, CC BY 4.0 per prose | |
| Solo MIT | MIT su tutto | ✓ |

**User's choice:** Solo MIT
**Notes:** Standard e zero attrition di split tecnico.

---

## GitHub remote

| Option | Description | Selected |
|--------|-------------|----------|
| Nuovo repo pubblico | Crea nuovo repo fresh, repo privato attuale = archivio storico | |
| Flip visibility esistente | Squash + force-push, poi flip private→public dal settings | ✓ |
| Nuovo repo + archivia vecchio | Come 1 ma con archive esplicito del privato | |

**User's choice:** Flip visibility esistente
**Notes:** Triggera follow-up sul rischio reflog.

### Follow-up — reflog risk

| Option | Description | Selected |
|--------|-------------|----------|
| Mitigazione GitHub Support | Ticket per invalidate cached refs / purge reflog | |
| Accetto rischio | Repo attuale ha solo commit benigni, niente catastrofico se trapela | ✓ |
| Cambio idea → nuovo repo | Riconsidero per evitare del tutto il reflog risk | |

**User's choice:** Accetto rischio
**Notes:** Esplicita acceptance del rischio reflog ~90gg. Razionale: history corrente = 5 commit GSD + 2 messy, nessun secret hardcoded già verificato pre-squash. Safety net = gitleaks su tutta la history pre-squash come parte della pre-publish checklist (REPO-06).

---

## Claude's Discretion

- Linguaggio/flag/output format dell'audit script (D-02)
- Regex patterns esatti per le custom gitleaks rules (PITFALLS.md ha le classi)
- Ordine task HOST vs REPO dentro la phase (sono indipendenti)
- Comando esatto per la squash (`git checkout --orphan` vs `git filter-repo`)
- Pre-commit framework vs hook nativo per gitleaks pre-push

## Deferred Ideas

- Investigare MagicDNS Tailscale rotto sul laptop (workaround `/etc/hosts` attivo)
- Migration a nftables nativo se future use case richiedono sets/maps avanzati
- GitHub Support ticket per reflog purge (esplicitamente declinato ora)
- Dual licensing MIT + CC BY 4.0 (se future serve attribution su prose)
- Rewrite README from scratch con struttura REPO-03 formale (alternativa v2)
