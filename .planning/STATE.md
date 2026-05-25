---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in_progress
last_updated: "2026-05-25T18:10:00.000Z"
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 3
  completed_plans: 2
---

# Project State: jarvis (self-hosting)

**Last updated:** 2026-05-25 dopo Phase 1 Plan 02 (repo-sanitize) chiuso OK

## Current Position

- ✅ PROJECT.md scritto e committato (`83501b6`)
- ✅ config.json scritto e committato (`161c434`)
- ✅ Research inline completata (4 aree: STACK, ARCHITECTURE, BACKUP, PITFALLS) + SUMMARY → committato (`d731145`)
- ✅ REQUIREMENTS.md scritto e committato (`1084181`)
- ✅ ROADMAP.md scritto (5 phases, mvp mode) (`f7e10b8`)
- ✅ Phase 1 CONTEXT.md + DISCUSSION-LOG.md scritti (4 gray areas chiuse)
- ✅ GSD subagents installati (`npx get-shit-done-cc@latest --global` + `npm install -g --force` per gsd-sdk 1.42.3)
- ✅ Phase 1 PLAN scritti (3 plan) — plan-checker PASS su 8/8 dimensioni
- ✅ **Plan 01 host-harden CHIUSO** (`803afcb`, audit finale 24/0/0 OK) — HOST-01..05 completati
- ✅ **Plan 02 repo-sanitize CHIUSO** (`e641d9d`, gitleaks worktree exit 0 / 0 finding) — REPO-01/02/03/05 completati. 2 deviazioni auto-fixed (allowlist `.planning/.*` esteso, README cert.pem path sanificato). 9 commit atomici.
- ⏳ **Next:** Plan 03 `03-repo-publish-PLAN.md` (pre-publish checklist, squash a orphan `public-v1`, force-push, flip visibility public, smoke verify)
- **Resume file:** `.planning/phases/01-foundations-repo-sanitize/03-repo-publish-PLAN.md`

## ⚠️ Cleanup pendente (da fare ora o post-phase)

- **Rimuovere NOPASSWD sudoers temp su jarvis**: era stato abilitato per orchestrazione. Comando: `ssh jarvis 'sudo rm /etc/sudoers.d/toto-nopasswd-temp'` (o equivalente — il file esatto dipende da cosa è stato creato). Plan 02 non richiede sudo, quindi si può rimuovere subito.

## Phase Status

| # | Phase | Status |
|---|-------|--------|
| 1 | Foundations & Repo Sanitize | In Progress (2/3 plan, host hardened + repo sanitized) |
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
