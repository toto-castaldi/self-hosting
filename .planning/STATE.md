---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in_progress
last_updated: "2026-05-25T18:42:00.000Z"
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 3
  completed_plans: 3
---

# Project State: jarvis (self-hosting)

**Last updated:** 2026-05-25 dopo Phase 1 COMPLETA (Plan 03 repo-publish chiuso)

## Current Position

- ✅ PROJECT.md, config.json, REQUIREMENTS, ROADMAP, research (cf. commit storici squashati in `5cb1ece`)
- ✅ Phase 1 CONTEXT.md + DISCUSSION-LOG.md (4 gray areas chiuse)
- ✅ GSD subagents installati
- ✅ Phase 1 PLAN (3 plan) — plan-checker PASS 8/8
- ✅ **Plan 01 host-harden CHIUSO** — HOST-01..05 completati, audit 24/0/0 OK
- ✅ **Plan 02 repo-sanitize CHIUSO** — REPO-01/02/03/05 completati, gitleaks worktree 0 finding
- ✅ **Plan 03 repo-publish CHIUSO** (`5cb1ece` orphan come `origin/main`) — REPO-04/06/07 completati. Architectural deviation Option A (repo era già public): force-push squash + flip-visibility SKIPPED. Smoke verify 0 finding.
- 🎉 **Phase 1 COMPLETA** (3/3 plan, 12/12 requirement)
- ⏳ **Next:** Phase 2 `Public Pipe (Cloudflare Tunnel + Access)` — NET-01..05. Iniziare con `/gsd-discuss-phase 2` o `/gsd-plan-phase 2` (inline se subagent non disponibili).
- **Resume file:** non applicabile (Phase 1 chiusa)

## ⚠️ Cleanup pendente

- **Rimuovere NOPASSWD sudoers temp su jarvis**: era stato abilitato per orchestrazione Plan 01. Comando indicativo: `ssh jarvis 'sudo ls /etc/sudoers.d/'` per identificare il file, poi `ssh jarvis 'sudo rm /etc/sudoers.d/<nome>'`. Phase 2 toccherà cloudflared che richiede sudo, ma è meglio re-abilitare on-demand per quella fase.
- **Monitor GH Action gitleaks first run** su `toto-castaldi/self-hosting`: `gh run list --workflow=gitleaks.yml --limit 1`. Atteso: exit 0, 0 finding sulla 1-commit history.
- **Deferred-item v2 (pre-push hook)**: `.pre-commit-config.yaml` usa upstream gitleaks default che è no-op a `pre-push` stage (entry `gitleaks git --pre-commit --staged`). Per gate effettivo locale, refactor a `repo: local` con `entry: gitleaks detect`. Per ora GH Action è il gate funzionante.

## Phase Status

| # | Phase | Status |
|---|-------|--------|
| 1 | Foundations & Repo Sanitize | ✅ Complete (3/3 plan, host hardened + repo sanitized + repo pubblicato) |
| 2 | Public Pipe (Cloudflare Tunnel + Access) | Pending |
| 3 | Lumio Stack Up (Supabase self-hosted) | Pending |
| 4 | Lumio Cutover (Dati + DNS) | Pending |
| 5 | Backup & Restore Drill | Pending |

## Active Decisions (parcheggiate per le rispettive phase)

- ✅ REPO-05 LICENSE → **MIT** (chiuso in Phase 1 discuss)
- LUMIO-04 frontend host location → Phase 4
- BACKUP WAL archiving on/off → Phase 5
- BACKUP storage location (disco unico vs secondo disco) → Phase 5
- BACKUP alert sink (email/ntfy/Telegram) → Phase 5

## Notes

- GSD subagents non installati in questo ambiente: research è stata fatta inline (4 agenti general-purpose paralleli), roadmap scritta inline. Per le phase successive, considerare `npx get-shit-done-cc@latest --global` per abilitare gsd-phase-researcher, gsd-planner, gsd-executor.
- Cloudflare deprecated signing key removed **30 April 2026** → calendar item per refresh repo apt cloudflared.
- Project mode: Vertical MVP — ogni phase deve consegnare capability end-to-end osservabile, non layer tecnici.
