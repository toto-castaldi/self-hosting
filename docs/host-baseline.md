# Host baseline — jarvis

Runbook breve per portare e mantenere `jarvis` (Ubuntu 26.04, 16 GB RAM,
mini PC casalingo) a uno stato hardened verificabile. Coverage:
HOST-01..HOST-05 (vedi `.planning/REQUIREMENTS.md`).

## Cosa fanno i due script

| Script | Scopo | Side effects |
|--------|-------|--------------|
| `bin/host-audit.sh` | Fotografa lo stato attuale e produce un report markdown. | **Read-only.** Nessuna mutazione: niente apt, niente systemctl start, niente ufw enable, niente mkdir. Solo `getent`, `stat`, `sshd -T`, `ufw status`, ecc. |
| `bin/host-apply.sh` | Applica i fix necessari, idempotente, con conferma interattiva per gruppo. | **Mutativo (sudo).** Crea `/etc/ssh/sshd_config.d/10-hardening.conf`, installa Docker (repo apt pinnato a `noble`), aggiunge `toto` a gruppo `docker`, crea `/home/toto/{jarvis,lumio}` e `/etc/cloudflared`, abilita `ufw` default-deny con SSH solo da `tailscale0`, attiva `unattended-upgrades`. |

Il flusso canonico è **audit prima, apply dopo**. L'audit produce evidenza
di cosa manca; l'apply chiude i gap. Dopo l'apply, una seconda esecuzione
dell'audit dovrebbe tornare 0 con tutti i check verdi (idempotenza).

## Esecuzione (da laptop, via SSH/Tailscale)

> ⚠️ **Pre-flight:** la sessione SSH che esegue `host-apply.sh` **deve venire
> da Tailscale**, perché lo step `apply_ufw` chiude SSH su tutte le altre
> interfacce. Verifica preventiva: `ssh jarvis` deve risolvere via Tailscale
> (cf. `tailscale ip -4 jarvis`).

```bash
# 1. Audit iniziale — produce report di cosa manca
ssh jarvis "sudo bash -s -- --output /tmp/host-audit-initial.md" < bin/host-audit.sh
scp jarvis:/tmp/host-audit-initial.md \
    .planning/phases/01-foundations-repo-sanitize/host-audit-report.md

# 2. Review del report
${PAGER:-less} .planning/phases/01-foundations-repo-sanitize/host-audit-report.md

# 3. Apply (interattivo: chiede conferma per ogni gruppo)
# Copia gli script su jarvis in modo che apply possa source-are l'audit:
scp bin/host-audit.sh bin/host-apply.sh jarvis:/tmp/
ssh -t jarvis "cd /tmp && sudo bash host-apply.sh"

# 4. Audit finale — verifica che tutti i check siano verdi
ssh jarvis "sudo bash -s -- --output /tmp/host-audit-final.md" < bin/host-audit.sh
scp jarvis:/tmp/host-audit-final.md \
    .planning/phases/01-foundations-repo-sanitize/host-audit-report.md

# 5. Commit del report finale come evidence
git add .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
git commit -m "docs(01-01): host audit report post-apply (HOST-01..05 all green)"
```

Per esecuzione non-interattiva (CI futura, automazione):

```bash
ssh jarvis "cd /tmp && sudo bash host-apply.sh --yes"
```

## I cinque gruppi di fix (HOST-01..05)

### HOST-01 — SSH key-only + unattended-upgrades

- Crea `/etc/ssh/sshd_config.d/10-hardening.conf` con:
  ```
  PasswordAuthentication no
  PubkeyAuthentication yes
  KbdInteractiveAuthentication no
  PermitRootLogin prohibit-password
  ```
  Il drop-in vince sul file principale `/etc/ssh/sshd_config` senza modificarlo.
- `sshd -t` per validare la config, poi `systemctl reload ssh`.
- Installa `unattended-upgrades` + `apt-listchanges`, uncomment della linea
  `"${distro_id}:${distro_codename}-security";` in `50unattended-upgrades`,
  abilita timer `apt-daily.timer` + `apt-daily-upgrade.timer`.

### HOST-02 — Docker + `toto` senza sudo

- Repo apt ufficiale Docker, **pinnato a `noble`** (Ubuntu 26.04 codename
  `resolute`/`questing` non ancora supportato dal repo upstream — workaround
  documentato in `PROJECT.md` § Key Decisions, identico al pin di
  `cloudflared` in Phase 2).
- Installa: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`.
- `usermod -aG docker toto` se non già membro. Richiede logout/login per
  attivare il gruppo nella shell corrente.

> ⚠️ `toto` nel gruppo `docker` ≡ root sul host. Accettato esplicitamente
> (single-user box, no multi-tenant). Vedi threat model HOST T-01-06.

### HOST-03 — Tailscale verifica (no install)

L'audit verifica che Tailscale sia già installato e attivo
(`tailscaled` running, BackendState `Running`, IP in `100.64.0.0/10`). Lo
script di apply **non installa** Tailscale: assume sia già presente dal
setup originale di jarvis. Se Tailscale non è attivo, `apply_ufw` aborta
pre-flight per evitare di chiudere l'unico canale admin.

### HOST-04 — Layout filesystem

```text
/home/toto/jarvis/      toto:toto 0755   ← config dev + script di host
/home/toto/lumio/       toto:toto 0755   ← stack Lumio (Phase 3+)
/etc/cloudflared/       root:cloudflared 0750  ← config tunnel (Phase 2)
```

Creato anche utente/gruppo system `cloudflared` (no-home, shell `nologin`)
come **prerequisito per Phase 2**. Lo stub viene creato qui per non
dover toccare il layout filesystem più volte.

### HOST-05 — `ufw` default-deny + SSH via `tailscale0`

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH from tailnet only'
ufw --force enable
```

> ⚠️ **Step più rischioso del runbook.** Se la sessione SSH corrente NON è
> via Tailscale, dopo `ufw --force enable` perdi l'accesso. `apply_ufw`
> chiede conferma esplicita prima di procedere.
>
> Mitigazione consigliata: apri una seconda sessione SSH a jarvis via
> Tailscale come safety net prima di eseguire `host-apply.sh`. Recupero
> hard: accesso fisico al mini PC (tastiera + monitor).

## Health check periodico

Lo script audit è pensato come **health check ripetibile**: idempotente,
read-only, zero side effect. Ri-eseguibile in qualunque momento:

```bash
ssh jarvis "sudo bash -s -- --quiet" < bin/host-audit.sh
# stdout: Audit: OK=N MISSING=0 WARN=0 Overall=OK
# exit 0 = tutto green; exit 1 = uno o più check falliti
```

Comoda integrazione in cron locale (laptop) per warning se il setup di
jarvis driftasse:

```bash
# Crontab esempio (settimanale)
0 9 * * 1 ssh jarvis "sudo bash -s -- --quiet" < ~/scm-projects/self-hosting/bin/host-audit.sh || \
          notify-send "jarvis audit drift" "Vedi exit code != 0"
```

## Dipendenze

- **Tailscale** installato e attivo su jarvis (`tailscaled` running, account
  Antonio loggato). Non gestito dagli script (è stato fatto manualmente al
  setup iniziale del mini PC).
- **SSH key** ed25519 del laptop autorizzata in `~/.ssh/authorized_keys` di
  `toto@jarvis`. Tipicamente già presente: senza questa, l'audit non parte.
- **Workaround `/etc/hosts` del laptop**: riga `100.113.232.126 jarvis`
  aggiunta nel laptop perché MagicDNS Tailscale è rotto lato laptop (vedi
  memory `project_laptop_hosts_jarvis.md`; investigazione differita post-v1).

## Riferimenti

- `.planning/REQUIREMENTS.md` § HOST — i cinque requisiti
- `.planning/phases/01-foundations-repo-sanitize/01-host-harden-PLAN.md` —
  decisioni di plan (audit-first, ufw vs nftables, ordine di esecuzione)
- `.planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md` — D-01..D-03
  (stato `jarvis`, audit-first, scelta `ufw`)
- `.planning/research/ARCHITECTURE.md` § Coexistence con Tailscale
- `PROJECT.md` § Key Decisions — pin `noble` per Docker e cloudflared

---

*Runbook generated by Phase 1 Plan 01 (host-harden). Update insieme agli
script in caso di drift.*
