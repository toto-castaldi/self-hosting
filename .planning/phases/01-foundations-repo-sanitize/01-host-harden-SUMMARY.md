---
phase: 01-foundations-repo-sanitize
plan: 01
subsystem: infra
tags: [bash, ssh, docker, ufw, tailscale, ubuntu-26.04, unattended-upgrades, audit-script]

requires:
  - phase: roadmap
    provides: HOST-01..HOST-05 requirements
provides:
  - "bin/host-audit.sh — idempotent read-only audit of HOST-01..05"
  - "bin/host-apply.sh — idempotent apply with per-group confirmation"
  - "docs/host-baseline.md — IT runbook for baseline replication"
  - "/home/toto/jarvis on host (toto:toto 0755)"
  - "/home/toto/lumio on host (toto:toto)"
  - "/etc/cloudflared on host (root:cloudflared 0750) + group cloudflared"
  - "ufw active, default-deny inbound, SSH only on tailscale0"
  - "Evidence: host-audit-report-pre-apply.md + host-audit-report-post-apply.md"
affects: [phase-02-public-pipe, phase-03-lumio-stack, phase-04-cutover, phase-05-backup]

tech-stack:
  added: [ufw, unattended-upgrades, cloudflared-group-stub]
  patterns: [audit-first-then-apply, idempotent-bash-scripts, per-group-confirm]

key-files:
  created:
    - bin/host-audit.sh
    - bin/host-apply.sh
    - docs/host-baseline.md
    - .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
    - .planning/phases/01-foundations-repo-sanitize/host-audit-report-pre-apply.md
    - .planning/phases/01-foundations-repo-sanitize/host-audit-report-post-apply.md
  modified: []

key-decisions:
  - "Audit-first: script read-only produce report markdown; apply legge audit e propone fix per gruppo con conferma"
  - "ufw allow on interface (tailscale0) invece di CIDR 100.64.0.0/10: rule order esplicita PRIMA di `ufw enable` per evitare SSH lockout"
  - "Group cloudflared creato stub in Phase 1 (anche se cloudflared user/binary arriveranno in Phase 2): serve per chown /etc/cloudflared 0750 ora"
  - "NOPASSWD sudoers temporaneo accettato per esecuzione orchestrata; da rimuovere post-phase"

patterns-established:
  - "Audit/apply pair: ogni hardening check è una funzione check_* in audit + apply_* in apply, idempotente, exit 0 = già conforme"
  - "Report markdown pipe-delimited row, sanitizzazione `|` interna in add_row, scrub MagicDNS suffix prima di emissione"
  - "set -euo pipefail + cache di comandi che parlano in pipe (es. sshd -T) per evitare SIGPIPE silenti"

requirements-completed: [HOST-01, HOST-02, HOST-03, HOST-04, HOST-05]

duration: ~80min (incluso debug 3 bug emersi all'esecuzione)
completed: 2026-05-25
---

# Phase 1 · Plan 01: Host Harden Summary

**jarvis (Ubuntu 26.04) hardened via audit/apply scripts idempotenti: SSH key-only, Docker rootless, ufw default-deny con SSH solo su tailscale0, filesystem layout per Phase 2/3, unattended-upgrades attivo.**

## Performance

- **Duration:** ~80 min (60 min planning/scripting + 20 min debug in esecuzione)
- **Started:** 2026-05-25 verso le 15:30 UTC
- **Completed:** 2026-05-25T15:50:00+00:00 (audit finale)
- **Tasks (logical):** 5 (audit-script, apply-script, runbook, audit-on-jarvis, apply+verify-on-jarvis)
- **Commits:** 8 (3 feat/docs + 3 fix + 2 evidence)

## Accomplishments

- Due script Bash idempotenti commitati nel repo (`bin/host-audit.sh`, `bin/host-apply.sh`) replicabili su qualsiasi host Ubuntu per il setup baseline
- Report di audit pre/post apply committati come evidence in `.planning/` (17 OK / 5 MISSING / 2 WARN → 24 OK / 0 / 0)
- Idempotenza verificata con 3 run consecutivi dell'audit (exit 0 al terzo run, zero drift)
- Runbook IT `docs/host-baseline.md` per replicare/aggiornare baseline
- Group `cloudflared` creato come stub (consumato in Phase 2)

## Task Commits

1. **bin/host-audit.sh** (initial) — `a586670` (feat)
2. **bin/host-apply.sh** (initial) — `1c18c60` (feat)
3. **docs/host-baseline.md** — `4ee6ac6` (docs)
4. **fix: scrub() reads stdin** — `0b9ca21` (fix, found during first audit run)
5. **fix: add_row sanitize `|` + printf `--` for summary lines** — `d60c832` (fix, found during second audit run)
6. **evidence pre-apply report** — `70be41f` (evidence)
7. **fix: apply_ssh cache sshd -T (SIGPIPE under pipefail)** — `ab5f56e` (fix, found during apply)
8. **fix: ufw rule check matches real ufw status rendering** — `29635c9` (fix, found during final audit)
9. **evidence post-apply report** — `803afcb` (evidence)

## Files Created/Modified

- `bin/host-audit.sh` — audit idempotente read-only, 5 sezioni HOST-01..05, output report markdown
- `bin/host-apply.sh` — apply idempotente, 5 gruppi con conferma interattiva, pre-flight Tailscale, post-audit
- `docs/host-baseline.md` — runbook IT
- `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` — report finale (sliding pointer)
- `.planning/phases/01-foundations-repo-sanitize/host-audit-report-pre-apply.md` — evidence stato iniziale
- `.planning/phases/01-foundations-repo-sanitize/host-audit-report-post-apply.md` — evidence stato finale

## Decisions Made

- **NOPASSWD sudoers temp:** abilitato in `/etc/sudoers.d/` per consentire orchestrazione via SSH; DA RIMUOVERE post-phase (vedi "Issues Encountered")
- **`/home/toto/jarvis` perm 0755:** apply ha chiuso a 0755 (era 0775). Plan accettava 0755 o 0750. Scelto 0755 per allinearsi al default Ubuntu user home subdir
- **Cloudflared group **prima** dell'user:** consente chown 0750 su `/etc/cloudflared` ora; user `cloudflared` arriva in Phase 2 e si aggiunge al group esistente

## Deviations from Plan

### Auto-fixed Issues (4 bug emersi in esecuzione)

**1. [Rule: shell scripting] `scrub()` non legge da stdin**
- **Found during:** primo run audit su jarvis (`$1: unbound variable`)
- **Issue:** `scrub` chiamato come pipe (`} | scrub`) ma usava `$1`; sotto `set -u` esplodeva
- **Fix:** rimosso `$1`, usa `sed` direttamente come pipe filter
- **Commit:** `0b9ca21`

**2. [Rule: shell scripting] add_row + printf summary**
- **Found during:** secondo run audit (HOST-04 colonne disallineate; `printf: -: invalid option` sullo stderr)
- **Issue:** `add_row` non scrubava `|` dagli arg (causa: stringhe Expected con `755|750`); summary printf con format starting `-` veniva interpretato come flag
- **Fix:** sanitize `|` → `/` in add_row; `printf --` per summary lines
- **Commit:** `d60c832`

**3. [Rule: shell scripting + pipefail] SIGPIPE su sshd -T**
- **Found during:** prima esecuzione `host-apply.sh` (sessione SSH chiusa subito dopo `=== HOST-01 ===`)
- **Issue:** `sshd -T 2>/dev/null | awk '... ; exit'` — awk esce dopo primo match, sshd riceve SIGPIPE, exit 141, pipefail propaga, set -e killa silenziosamente
- **Fix:** cache `sshd -T` in variabile, poi `printf | awk` (idiom già in audit.sh)
- **Commit:** `ab5f56e`
- **Generalizzazione:** pattern utile per QUALSIASI tool che parla in stream lungo + pipefail

**4. [Rule: regex coverage] ufw rule check pattern mismatch**
- **Found during:** audit finale post-apply (1 MISSING falso)
- **Issue:** check ufw cercava `22/tcp.*ALLOW IN.*tailscale0` o `tailscale0.*ALLOW IN.*22`, ma ufw renderizza `22/tcp on tailscale0   ALLOW IN   Anywhere` (port → interface → action)
- **Fix:** aggiunto pattern `22/tcp.*tailscale0.*ALLOW IN` come 4° alternativa
- **Commit:** `29635c9`

---

**Total deviations:** 4 auto-fixed (tutti bug nello scripting emersi solo in esecuzione su host reale; nessuno scope creep)
**Impact on plan:** zero deviazioni semantiche; il design audit-first ha fatto esattamente il suo lavoro (emergere bug prima dell'apply distruttivo)

## Issues Encountered

- **Apply prima volta chiuso silente dopo `=== HOST-01 ===`:** diagnosi via re-ssh (jarvis vivo, sshd active, ufw inactive) → trovato SIGPIPE in apply_ssh. Vedi auto-fix #3.
- **NOPASSWD temporaneo (sicurezza):** abilitato da toto in `/etc/sudoers.d/` per consentire esecuzione orchestrata. **TODO post-phase: rimuovere il file** (es. `sudo rm /etc/sudoers.d/toto-nopasswd-temp`). Segnalo in STATE.md → Active Decisions / cleanup.
- **MagicDNS Tailscale rotto sul laptop:** workaround `/etc/hosts` `100.113.232.126 jarvis` presente (memory user_role); MagicDNS funziona invece su jarvis stesso. Investigare in v2.

## User Setup Required

Nessun setup esterno richiesto. Tutto on-host via SSH/Tailscale.

## Next Phase Readiness

- **Plan 02 (repo-sanitize) ready:** working tree pulito su `main`, niente blocker
- **Phase 2 prerequisiti:** filesystem layout (`/etc/cloudflared` + group), Tailscale up, ufw configurato → tutti presenti
- **Cleanup TODO:** rimuovere NOPASSWD sudoers temp file su jarvis (segnalare in STATE.md)

---
*Phase: 01-foundations-repo-sanitize*
*Completed: 2026-05-25*
