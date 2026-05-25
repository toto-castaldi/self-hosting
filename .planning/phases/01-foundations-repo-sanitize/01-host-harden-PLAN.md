---
phase: 01-foundations-repo-sanitize
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/host-audit.sh
  - bin/host-apply.sh
  - docs/host-baseline.md
  - .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
autonomous: false
requirements: [HOST-01, HOST-02, HOST-03, HOST-04, HOST-05]
user_setup:
  - service: jarvis (Ubuntu 26.04 host)
    why: "Hardening richiede privilegi sudo + accesso fisico/SSH al mini PC"
    env_vars: []
    dashboard_config:
      - task: "Antonio deve essere loggato come `toto` su jarvis via SSH (Tailscale) e avere sudo password pronta"
        location: "ssh jarvis (100.113.232.126 via /etc/hosts workaround)"

must_haves:
  truths:
    - "`ssh jarvis` da Tailscale funziona; password auth disabilitata (PasswordAuthentication no in sshd effective config)"
    - "`docker ps` runna come utente `toto` senza sudo (toto è in gruppo docker)"
    - "`ufw status verbose` mostra default-deny inbound; allow SSH solo da Tailscale CIDR 100.64.0.0/10 e loopback"
    - "`/home/toto/jarvis/`, `/home/toto/lumio/`, `/etc/cloudflared/` esistono con ownership corretti (toto:toto per /home, root:cloudflared 0750 per /etc/cloudflared)"
    - "`systemctl is-active unattended-upgrades` ritorna `active`; security source attivo per ubuntu-security"
    - "Tailscale up e funzionante (`tailscale status` mostra jarvis online)"
    - "L'audit script in seconda esecuzione (post-apply) ritorna exit 0 con tutti i check verdi"
  artifacts:
    - path: "bin/host-audit.sh"
      provides: "Script Bash idempotente read-only che verifica HOST-01..05 e produce report markdown"
      contains: "check_ssh_keyonly, check_docker_group, check_tailscale, check_filesystem_layout, check_ufw, check_unattended_upgrades"
    - path: "bin/host-apply.sh"
      provides: "Script Bash idempotente che applica fix guidati dall'audit (chiede conferma per ogni gruppo di modifiche)"
      contains: "apply_ssh, apply_docker, apply_ufw, apply_filesystem, apply_unattended_upgrades"
    - path: ".planning/phases/01-foundations-repo-sanitize/host-audit-report.md"
      provides: "Report iniziale audit pre-apply + report finale post-apply, committato come evidence"
    - path: "docs/host-baseline.md"
      provides: "Runbook breve in italiano per replicare/aggiornare baseline jarvis (chi vuole capire cosa fanno gli script)"
  key_links:
    - from: "bin/host-audit.sh"
      to: "bin/host-apply.sh"
      via: "audit produce il report; apply legge il report e propone azioni"
      pattern: "host-apply.sh deve poter parsare l'output strutturato di host-audit.sh"
    - from: "ufw allow"
      to: "Tailscale interface (tailscale0)"
      via: "regola ufw che permette SSH solo da `tailscale0`"
      pattern: "ufw allow in on tailscale0 to any port 22 proto tcp"
---

<objective>
Portare jarvis (Ubuntu 26.04, 16 GB RAM, mini PC casalingo) a uno stato hardened
verificabile end-to-end (HOST-01..HOST-05) tramite due script idempotenti
committati nel repo: prima un **audit read-only** che fotografa lo stato attuale
e produce un report, poi un **apply** guidato dall'audit che chiude i gap.

Purpose: chiudere il prerequisito infrastrutturale per Phase 2..5. Senza un host
hardened con Docker + Tailscale + ufw + filesystem layout, le phase successive
non possono partire. La forma "script idempotente + report" rende l'operazione
ripetibile (utile se si riformatta jarvis o si replica il setup su un altro mini PC
in v2 per Helix).

Output: 2 script Bash committati, 1 runbook IT, 1 report di audit committato come
evidence in `.planning/`.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md
@.planning/research/SUMMARY.md
@.planning/research/ARCHITECTURE.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1.1: Scrivere `bin/host-audit.sh` (audit idempotente read-only)</name>
  <files>bin/host-audit.sh</files>
  <read_first>
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md (D-01: stato `jarvis` parzialmente configurato; D-02: audit-first è la prima task)
    - .planning/REQUIREMENTS.md sezione HOST (i 5 requisiti HOST-01..05 esatti)
    - .planning/ROADMAP.md §"Phase 1" Success Criteria 1 e 2 (ssh keyonly, docker no-sudo, ufw default-deny + tailscale SSH only)
    - .planning/research/ARCHITECTURE.md §5 (Tailscale coexistence — interfaccia `tailscale0`, MagicDNS)
    - CLAUDE.md §"Layout filesystem (target)" (paths /home/toto/jarvis, /home/toto/lumio, /etc/cloudflared)
  </read_first>
  <action>
Creare `bin/host-audit.sh` come script Bash POSIX-friendly (shebang `#!/usr/bin/env bash`, `set -euo pipefail`) **strettamente read-only**: nessun comando che muta stato (no `apt`, no `usermod`, no `systemctl start/enable`, no `ufw enable`, no `mkdir`). Solo: `getent`, `id`, `groups`, `ss -lntp`, `systemctl is-active|is-enabled`, `stat`, `test -d`, `grep` su `/etc/ssh/sshd_config.d/*.conf` + `sshd -T` (output effective config), `ufw status verbose` (read-only), `tailscale status --json`, `dpkg -l | grep <pkg>`, `docker --version`, `docker compose version`.

Lo script implementa 6 funzioni `check_*`, una per requisito + una per Tailscale verification:

- `check_ssh_keyonly` (HOST-01): parsa `sudo sshd -T 2>/dev/null | grep -E '^(passwordauthentication|pubkeyauthentication|permitrootlogin|kbdinteractiveauthentication)'`. Atteso: `passwordauthentication no`, `pubkeyauthentication yes`, `permitrootlogin no` (o `prohibit-password`), `kbdinteractiveauthentication no`. Verifica anche unattended-upgrades: `systemctl is-active unattended-upgrades` + presenza di `/etc/apt/apt.conf.d/50unattended-upgrades` con linea non-commented contenente `"${distro_id}:${distro_codename}-security"`.
- `check_docker` (HOST-02): `command -v docker` exit 0, `docker --version` parsa versione, `docker compose version` exit 0, `id -nG toto | tr ' ' '\n' | grep -qx docker`, `docker info` riesce **senza sudo** runnando come `toto` (usa `runuser -u toto -- docker info` se script gira come root, altrimenti diretto).
- `check_tailscale` (HOST-03): `systemctl is-active tailscaled`, `tailscale status --json | jq -r '.BackendState'` deve essere `Running`, `tailscale ip -4` ritorna un IP nel CGNAT `100.64.0.0/10`. MagicDNS: `tailscale status --json | jq -r '.MagicDNSSuffix'` non vuoto.
- `check_filesystem_layout` (HOST-04): `test -d /home/toto/jarvis && stat -c '%U:%G %a' /home/toto/jarvis` deve essere `toto:toto 755` (o 750); idem `/home/toto/lumio` (può essere assente in audit iniziale — è OK, va creato in apply); `test -d /etc/cloudflared && stat -c '%U:%G %a' /etc/cloudflared` atteso `root:cloudflared 0750` (cloudflared user/group può non esistere ancora — è OK, scope di Phase 2).
- `check_ufw` (HOST-05): `command -v ufw`, `ufw status verbose` parsato: `Status: active`, `Default: deny (incoming)`, regole esplicite per `22/tcp` solo su `tailscale0` (o da CIDR 100.64.0.0/10). Verifica assenza regole open su `0.0.0.0/0` per porte != ICMP echo-reply.
- `check_overall` aggrega tutti i check e setta exit code: 0 = all green, 1 = qualcosa manca (report mostra cosa).

Output: report markdown su stdout E scritto su `${AUDIT_REPORT_PATH:-.planning/phases/01-foundations-repo-sanitize/host-audit-report.md}`. Struttura:

- Header con `**Hostname:** $(hostname)`, `**OS:** $(lsb_release -ds)`, `**Kernel:** $(uname -r)`, `**Run at:** $(date -Is)`, `**Audit script version:** v1`.
- Una sezione per requisito (`## HOST-01: SSH key-only + unattended-upgrades`, ecc.), ognuna con tabella `| Check | Expected | Actual | Status |`. `Status` = `OK` (verde) / `MISSING` (rosso) / `WARN` (giallo, es. config presente ma non identica).
- Sezione finale `## Summary` con conteggio OK/MISSING/WARN e suggerimento "Run `bin/host-apply.sh` per applicare i fix proposti".

CLI flags: `-q|--quiet` (solo summary), `-o|--output PATH` (override path report), `--no-write` (solo stdout), `--require-sudo` (esce errore se non lanciato con sudo — necessario per `sshd -T` e `ufw status`).

Permessi: `chmod 0755 bin/host-audit.sh`.

Lingua: commenti e prose IT (es. `# Verifica che SSH abbia password auth disabilitata`); identificatori, variabili, output strutturato in EN per essere parsato dall'apply script.
  </action>
  <verify>
    <automated>
bash -n bin/host-audit.sh                                  # sintassi OK
shellcheck bin/host-audit.sh || true                       # warning visibili ma non bloccanti
grep -q '^set -euo pipefail$' bin/host-audit.sh            # strict mode attivo
grep -cE '^(apt|usermod|systemctl (start|enable|restart)|ufw (enable|allow|deny)|mkdir)' bin/host-audit.sh | grep -v '^#' | grep -qx '0' && echo "READ-ONLY confirmed"
grep -c 'check_ssh_keyonly\|check_docker\|check_tailscale\|check_filesystem_layout\|check_ufw' bin/host-audit.sh | awk '$1 >= 5 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <acceptance_criteria>
    - File `bin/host-audit.sh` esiste, è eseguibile (mode 0755), shebang `#!/usr/bin/env bash`, `set -euo pipefail` come seconda riga non-commento.
    - Grep statico conferma zero comandi mutativi (apt/usermod/systemctl start|enable|restart/ufw enable|allow|deny/mkdir) in righe non-commento.
    - Script definisce le 5 funzioni `check_ssh_keyonly`, `check_docker`, `check_tailscale`, `check_filesystem_layout`, `check_ufw` + `check_overall`.
    - Eseguito su jarvis via `ssh jarvis 'sudo bash -s' < bin/host-audit.sh` produce un report markdown su stdout con almeno 5 sezioni (una per HOST-NN) e una tabella `| Check | Expected | Actual | Status |` per sezione.
    - Eseguito una seconda volta consecutiva produce output identico (idempotente: nessun side effect sullo stato del sistema). Verifica: `md5sum` di due run consecutive identici a meno della linea `Run at:`.
    - Report scritto anche su `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` (eseguendo localmente con `--output`).
  </acceptance_criteria>
  <done>
Lo script audit è in repo, eseguibile, read-only verificato staticamente, produce report markdown strutturato con stato per ogni HOST-NN. Esecuzione su jarvis produce il primo report committabile come evidence dello stato pre-apply.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 1.2: Eseguire audit iniziale su jarvis + review report</name>
  <what-built>Script `bin/host-audit.sh` pronto per essere eseguito su jarvis e produrre il report dello stato attuale (pre-apply).</what-built>
  <how-to-verify>
1. Antonio esegue da laptop:
   ```bash
   ssh jarvis "sudo bash -s --" < bin/host-audit.sh --output /tmp/host-audit-initial.md
   scp jarvis:/tmp/host-audit-initial.md .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
   ```
2. Legge `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` e verifica:
   - Header mostra `Hostname: jarvis`, OS `Ubuntu 26.04`, kernel `6.x` (qualunque), data `2026-05-XX`.
   - Sezione `## HOST-03: Tailscale` mostra `Status: OK` (Tailscale già installato e funzionante per CONTEXT.md D-01).
   - Sezione `## HOST-01: SSH key-only` mostra almeno `passwordauthentication no` e `pubkeyauthentication yes` come OK (confermato in CONTEXT.md D-01).
   - Sezioni `## HOST-02 Docker`, `## HOST-04 Filesystem layout`, `## HOST-05 ufw` mostrano una mix di OK/MISSING coerente con "stato parzialmente configurato".
3. Conferma che il report è leggibile, completo, e riflette accuratamente la situazione di jarvis.
  </how-to-verify>
  <resume-signal>Scrivi "approved" per procedere con apply, oppure descrivi cosa manca/è sbagliato nell'audit (es. "manca check unattended-upgrades", "il check Tailscale è troppo restrittivo", ecc.).</resume-signal>
</task>

<task type="auto">
  <name>Task 1.3: Scrivere `bin/host-apply.sh` (apply idempotente guidato da audit) + eseguirlo su jarvis</name>
  <files>bin/host-apply.sh, docs/host-baseline.md, .planning/phases/01-foundations-repo-sanitize/host-audit-report.md</files>
  <read_first>
    - bin/host-audit.sh (per riusare le funzioni check_* via `source`)
    - .planning/phases/01-foundations-repo-sanitize/host-audit-report.md (l'output di Task 1.2 — guida cosa applicare)
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md (D-02: apply guidato da audit; D-03: ufw, non nftables)
    - .planning/research/ARCHITECTURE.md §1, §5, §6 (cloudflared user/group setup, Tailscale interface name, hardening systemd)
    - README.md (sezione `## NOTE / ## init` per vedere comandi originali eseguiti la prima volta — non re-eseguire pari pari, sono già storici)
  </read_first>
  <action>
Creare `bin/host-apply.sh` come script Bash strict (`set -euo pipefail`), **idempotente** (ogni operazione testa lo stato pre-modifica e skippa se già conforme — usa le funzioni `check_*` di `host-audit.sh` via `source bin/host-audit.sh`). Lo script raggruppa apply in funzioni per requisito e chiede conferma interattiva per ogni gruppo (`read -r -p "Applicare fix per HOST-XX? [y/N] " ans`), supporta `--yes` per skip interactive (per CI futura), e produce un nuovo audit report **post-apply** come ultima azione (re-source delle funzioni check + dump del report finale).

Funzioni richieste:

- `apply_ssh` (HOST-01): se `sshd -T` mostra `passwordauthentication yes` o equivalent missing → crea `/etc/ssh/sshd_config.d/10-hardening.conf` con:
  ```
  PasswordAuthentication no
  PubkeyAuthentication yes
  KbdInteractiveAuthentication no
  PermitRootLogin prohibit-password
  ```
  Poi `sshd -t` (test syntax), poi `systemctl reload ssh`. **NON modificare** `/etc/ssh/sshd_config` direttamente (il drop-in vince).
  Per unattended-upgrades: `apt install -y unattended-upgrades apt-listchanges`; verifica `/etc/apt/apt.conf.d/50unattended-upgrades` ha linea active `"${distro_id}:${distro_codename}-security";` (uncomment se commentata via `sed -i 's|^//\s*"\${distro_id}:\${distro_codename}-security";|"\${distro_id}:\${distro_codename}-security";|'`), `systemctl enable --now unattended-upgrades.service`, `systemctl enable --now apt-daily.timer apt-daily-upgrade.timer`.
- `apply_docker` (HOST-02): se `command -v docker` fallisce → installa via repo apt ufficiale Docker (path documentato in README.md `## docker`): `install -m 0755 -d /etc/apt/keyrings`; `curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc` (idempotent: `--continue` non applicabile, usa `test -f` guard); aggiunge `/etc/apt/sources.list.d/docker.list` con riga `deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable` (NOTA: noble forzato, stesso workaround di cloudflared — Ubuntu 26.04 codename `resolute` non ancora supportato, documentato in PROJECT.md key decisions); `apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`. Aggiunge `toto` a group docker solo se non già: `id -nG toto | grep -qw docker || usermod -aG docker toto` (avviso utente: serve logout/login per attivare il gruppo nella sessione corrente).
- `apply_filesystem` (HOST-04): `install -d -o toto -g toto -m 0755 /home/toto/jarvis /home/toto/lumio`; per `/etc/cloudflared/`: se cloudflared user non esiste, `useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared`, poi `install -d -o root -g cloudflared -m 0750 /etc/cloudflared`. (Cloudflared install pacchetto è Phase 2; qui solo dir + user per riservare il layout.)
- `apply_ufw` (HOST-05): se `ufw` non installato → `apt install -y ufw`. Determina interfaccia Tailscale: `TS_IFACE=$(tailscale status --json | jq -r '.Self.TailscaleIPs[0]' && ip -4 -o addr show | awk '/100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\./ {print $2; exit}')` — più affidabile: scrive regola sull'interfaccia `tailscale0` direttamente. Comandi (idempotenti: ufw delete è idempotente con `|| true`, ufw allow è additive ma non duplica):
  ```bash
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow in on lo
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH from tailnet only'
  ufw --force enable
  ```
  Esplicitamente NO `ufw allow 22/tcp` su `any` (sarebbe regressione: aprirebbe SSH al world).
- `apply_post_audit`: re-esegue audit, salva report in `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` (sovrascrive il pre-apply o appende `## Post-apply` — preferenza: sovrascrive, perché il pre-apply è già un commit storico).

Sicurezza importante: lo script **deve** girare con sudo (`require_root` check all'inizio). Failure mode: se `apply_ufw` sta per chiudere SSH al laptop, scrive un warning evidente e chiede conferma esplicita "Sei loggato via Tailscale? Procedere chiuderà SSH su ogni altra interfaccia. [y/N]".

Anche `bin/host-apply.sh` mode 0755.

**Creare contestualmente `docs/host-baseline.md`** (runbook IT, ~80-120 righe): spiega cosa fanno i 2 script, come eseguirli (audit-first, review report, poi apply), come ri-eseguire periodicamente come "health check", il workaround `noble` per Docker apt repo (riferimento a PROJECT.md), la dipendenza da Tailscale già installato.

**Eseguire `bin/host-apply.sh` su jarvis** dopo conferma utente (vedi flow: questa task è `auto` ma include un punto di intervento esplicito perché modifica jarvis). Sequenza eseguibile:
```bash
ssh jarvis "sudo bash -s -- --yes" < bin/host-apply.sh
ssh jarvis "sudo bash -s -- --output /tmp/host-audit-final.md" < bin/host-audit.sh
scp jarvis:/tmp/host-audit-final.md .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
```
Verifica finale che il report finale ha tutti `Status: OK` su HOST-01..05.
  </action>
  <verify>
    <automated>
bash -n bin/host-apply.sh
shellcheck bin/host-apply.sh || true
grep -q '^set -euo pipefail$' bin/host-apply.sh
grep -q 'require_root\|EUID' bin/host-apply.sh                       # check sudo obbligatorio
grep -q 'apply_ssh\|apply_docker\|apply_filesystem\|apply_ufw' bin/host-apply.sh
grep -q 'ufw allow in on tailscale0' bin/host-apply.sh               # D-03: ufw + interfaccia tailscale
grep -qv 'ufw allow 22/tcp$' bin/host-apply.sh                       # NON aprire SSH al world
test -f docs/host-baseline.md
test -s .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
grep -c 'Status: OK' .planning/phases/01-foundations-repo-sanitize/host-audit-report.md | awk '$1 >= 5 { exit 0 } { exit 1 }'
ssh jarvis "id -nG toto | tr ' ' '\n' | grep -qx docker" && echo "toto in docker group"
ssh jarvis "sudo ufw status verbose | grep -q 'Status: active'"
ssh jarvis "sudo ufw status verbose | grep -qE '22/tcp.*ALLOW IN.*tailscale0|tailscale0.*ALLOW IN'"
ssh jarvis "sudo sshd -T | grep -q '^passwordauthentication no$'"
ssh jarvis "systemctl is-active unattended-upgrades"
ssh jarvis "test -d /home/toto/jarvis -a -d /home/toto/lumio -a -d /etc/cloudflared"
    </automated>
  </verify>
  <acceptance_criteria>
    - `bin/host-apply.sh` esiste, mode 0755, strict mode attivo, richiede sudo (check EUID).
    - `docs/host-baseline.md` esiste, in IT, descrive flow audit→apply e i 5 fix per HOST-NN.
    - Dopo esecuzione su jarvis: `sudo sshd -T | grep '^passwordauthentication'` → `no`; `id -nG toto | grep -w docker` → match; `sudo ufw status verbose` mostra `Status: active`, `Default: deny (incoming)`, regola `tailscale0 ALLOW IN` per port 22; `systemctl is-active unattended-upgrades` → `active`; le 3 directory `/home/toto/jarvis`, `/home/toto/lumio`, `/etc/cloudflared` esistono con ownership corretti.
    - Report finale `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` ha `Status: OK` su tutte e 5 le sezioni HOST-NN (verificabile con `grep -c 'Status: OK'` ≥ 5).
    - Lo script è idempotente: ri-esecuzione `host-apply.sh --yes` produce 0 modifiche reali (tutti i check passano, ogni `apply_*` skippa con messaggio "già conforme").
    - SSH a jarvis funziona ancora post-ufw enable (la regola tailscale0 protegge questa sessione).
  </acceptance_criteria>
  <done>
jarvis è hardened end-to-end: SSH key-only + unattended-upgrades attivo, Docker installato e `toto` può `docker ps` senza sudo, ufw attivo default-deny con SSH consentito solo da tailscale0, layout filesystem creato, Tailscale verificato. Report finale committato come evidence. Gli script sono ri-eseguibili come health check periodico.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Internet → jarvis | NESSUNA porta aperta diretta (no port forwarding sul router casalingo). L'esposizione internet arriva solo via cloudflared (Phase 2). In Phase 1 il boundary è chiuso. |
| Tailnet (CGNAT 100.64.0.0/10) → jarvis SSH | Unico canale admin. Confine fidato in base a: (a) Tailscale device auth, (b) chiavi SSH ed25519, (c) ufw filtra solo `tailscale0`. |
| Laptop Antonio → jarvis (provisioning) | Trusted runner che esegue script via SSH. Trust transitivo dalla sicurezza del laptop (FileVault/LUKS + 2FA Google per Tailscale). |
| `toto` user → root (sudo) | Sudo password-based; futura iter v2: NOPASSWD per script specifici via `/etc/sudoers.d/`. |
| Docker daemon → host | `toto` in gruppo `docker` ≡ root equivalent sul host (accettato esplicitamente, single-user box, no multi-tenant). Documentato in `docs/host-baseline.md`. |

## STRIDE Threat Register (ASVS Level 1)

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-01 | Spoofing | SSH login a jarvis | mitigate | `PasswordAuthentication no` + `PubkeyAuthentication yes` (drop-in sshd_config.d/10-hardening.conf); chiave ed25519 client-side; ufw chiude SSH a tutto tranne `tailscale0`. |
| T-01-02 | Tampering | Script `host-audit.sh` runnato con sudo | mitigate | Script committato in repo e versionato; modifiche tracciate via git; pre-publish gitleaks (Plan 02) impedisce che lo script committato leaks credenziali; lo script è read-only verificato staticamente (grep gate in `<verify>`). |
| T-01-03 | Repudiation | Esecuzione apply senza traccia | accept | Sessione SSH è loggata da journald di jarvis (`journalctl _SYSTEMD_UNIT=ssh.service`) + storia git del repo. Per single-dev personal infra, audit log centralizzato è overkill (Out of Scope v1). |
| T-01-04 | Information Disclosure | `host-audit-report.md` committato in `.planning/` potrebbe contenere hostname/IP | mitigate | Script output **non** include IP pubblici (solo CGNAT 100.x è OK, allowlisted in gitleaks rules Plan 02). Hostname `jarvis` è scelta narrativa pubblica (vedi CLAUDE.md). MagicDNS suffix `tail-xxxxx.ts.net` viene scrubato dal report (regex sostitutiva nel report writer). |
| T-01-05 | Denial of Service | `ufw enable` chiude SSH al laptop in corso di esecuzione | mitigate | `apply_ufw` aggiunge regola `tailscale0 ALLOW 22/tcp` **prima** di `ufw --force enable`; warning interattivo "Sei loggato via Tailscale?" prima di procedere; fallback: reset hard via accesso fisico al mini PC se chiusura accidentale. |
| T-01-06 | Elevation of Privilege | `toto` in gruppo `docker` ≡ root | accept | Single-user box, no multi-tenant, no servizi privilegiati esposti a `toto` oltre Docker. Documented trade-off in `docs/host-baseline.md`. Mitigazione futura (v2): rootless Docker. |
| T-01-SC | Tampering | Package legitimacy: apt packages installati (`docker-ce`, `ufw`, `unattended-upgrades`) | mitigate | Pacchetti da repo ufficiali Ubuntu (verified GPG signing via apt) + repo Docker ufficiale (signing key in `/etc/apt/keyrings/docker.asc`). NO npm/pip/cargo installs in questo plan → Package Legitimacy Gate non si applica. |
</threat_model>

<verification>
Eseguibili end-to-end (manuali, perché toccano jarvis vero):

```bash
# 1. Connettività post-hardening
ssh jarvis 'echo OK'                                          # ssh via Tailscale ancora funziona

# 2. SSH config
ssh jarvis 'sudo sshd -T | grep -E "^(password|pubkey)authentication"'
# atteso: passwordauthentication no, pubkeyauthentication yes

# 3. Docker no-sudo
ssh jarvis 'docker ps'                                         # come toto, no sudo
ssh jarvis 'docker compose version'

# 4. ufw
ssh jarvis 'sudo ufw status verbose'
# atteso: Status: active, Default: deny (incoming), regole su tailscale0 e lo

# 5. Tailscale
ssh jarvis 'tailscale status --json | jq .BackendState'
# atteso: "Running"

# 6. Filesystem
ssh jarvis 'ls -ld /home/toto/jarvis /home/toto/lumio /etc/cloudflared'

# 7. Unattended-upgrades
ssh jarvis 'systemctl is-active unattended-upgrades'
ssh jarvis 'grep -E "^[^/]" /etc/apt/apt.conf.d/50unattended-upgrades | grep security'

# 8. Audit idempotente
ssh jarvis 'sudo bash -s -- --quiet' < bin/host-audit.sh
echo "Exit code: $?"                                           # atteso: 0
```
</verification>

<success_criteria>
Plan 01 è completo quando:
- [ ] `bin/host-audit.sh` e `bin/host-apply.sh` esistono, mode 0755, idempotenti, strict mode.
- [ ] `docs/host-baseline.md` esiste in IT e descrive il flow.
- [ ] `.planning/phases/01-foundations-repo-sanitize/host-audit-report.md` esiste con tutti `Status: OK` per HOST-01..05.
- [ ] jarvis ha: SSH key-only, Docker + toto in docker group, ufw default-deny + SSH only via tailscale0, layout filesystem creato, unattended-upgrades attivo, Tailscale verificato.
- [ ] Ri-eseguendo `host-apply.sh --yes` su jarvis non produce modifiche reali (idempotenza verificata).
</success_criteria>

<output>
Create `.planning/phases/01-foundations-repo-sanitize/01-01-SUMMARY.md` when done.

Il SUMMARY deve includere:
- Versione finale dello stato di jarvis (output `lsb_release -ds`, kernel, ufw status sintetico).
- Eventuali drift dall'audit iniziale all'apply (cosa è stato modificato per davvero).
- Note operative emerse durante l'esecuzione (es. "MagicDNS suffix è X", "ufw ha richiesto Y", ecc.) — utili come input per Phase 2 cloudflared install.
- Conferma idempotenza (output di un terzo run audit).
</output>
