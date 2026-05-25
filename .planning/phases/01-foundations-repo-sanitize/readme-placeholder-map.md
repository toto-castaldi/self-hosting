# README sanitization placeholder map

**Created:** 2026-05-25 (Plan 02 Task 2.3)
**Purpose:** audit trail della sostituzione real → placeholder applicata a `README.md` durante la sanitizzazione in-place pre-push public.

Ogni riga = una classe di leak; le sostituzioni sono state applicate via un singolo `sed -i` deterministico (script `scripts/sanitize-readme.sh` non committato — il vero record canonico è il git diff del README + questa mappa).

Questo file vive in `.planning/` ed è committato pubblicamente (per la natura di documentazione GSD del progetto). È stato esplicitamente aggiunto all'`[allowlist] paths` di `.gitleaks.toml` perché contiene **by design** i valori reali nella colonna sinistra. Decisione consapevole: i valori reali sono già recuperabili via Certificate Transparency (per i sottodomini) + WHOIS / reverse DNS (per gli IP DigitalOcean); il valore di avere il diff documentato supera il rischio residuo (cfr. threat T-02-05 nel PLAN).

## Domini e sottodomini

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `toto-castaldi.com` | `example.com` | RFC2606 reserved per docs |
| `lumio.toto-castaldi.com` | `app.example.com` | placeholder canonico |
| `m-lumio.toto-castaldi.com` | `mobile.example.com` | |
| `deck.lumio.toto-castaldi.com` | `deck.app.example.com` | |
| `helix.toto-castaldi.com` | `service-a.example.com` | maschera anche il nome progetto secondario (Helix è v2) |
| `live.helix.toto-castaldi.com` | `live.service-a.example.com` | |
| `coach.helix.toto-castaldi.com` | `coach.service-a.example.com` | |
| `docora.toto-castaldi.com` | `service-b.example.com` | |
| `api.docora.toto-castaldi.com` | `api.service-b.example.com` | |
| `n8n.toto-castaldi.com` | `workflow.example.com` | |
| `supabase-lumio.toto-castaldi.com` | `api.app.example.com` | |
| `studio-lumio.toto-castaldi.com` | `studio.app.example.com` | |
| `supabase-helix.toto-castaldi.com` | `api.service-a.example.com` | |
| `studio-helix.toto-castaldi.com` | `studio.service-a.example.com` | |
| `hello.toto-castaldi.com` | `hello.example.com` | |
| `nuovo-servizio.toto-castaldi.com` | `nuovo-servizio.example.com` | esempio nel runbook |

## IP

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `185.199.108-111.153` (GitHub Pages range) | `203.0.113.10-13` | TEST-NET-3 (RFC5737) |
| `185.199.108.153` | `203.0.113.10` | TEST-NET-3 |
| `146.190.232.60` | `203.0.113.20` | TEST-NET-3 — DigitalOcean droplet originale Lumio |
| `188.166.97.177` | `203.0.113.30` | TEST-NET-3 — Docora droplet |
| `152.42.138.218` | `203.0.113.40` | TEST-NET-3 — n8n droplet |
| `192.168.0.72` | `192.168.0.X` (letterale) | RFC1918 sarebbe innocuo, ma maschero last-octet per principio (consistency con altri repo personali) |
| `192.168.0.137` | `192.168.0.Y` | come sopra |

## UUID / credentials

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `6b09204a-58fd-4632-b699-15b1b9eb24a0` | `00000000-0000-0000-0000-000000000000` | allowlisted in `.gitleaks.toml` (cf-tunnel-uuid) |
| `/etc/cloudflared/6b09204a-58fd-4632-b699-15b1b9eb24a0.json` | `/etc/cloudflared/<TUNNEL_UUID>.json` | placeholder esplicito per il path |
| `/home/toto/.cloudflared/cert.pem` | `~/.cloudflared/cert.pem` (owner-only) | il path assoluto rivela il username; tilde è equivalente narrative |

## Email e account

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `Toto.castaldi@gmail.com` | `you@example.com` | case variants normalizzate; allowlisted in `.gitleaks.toml` (personal-email) |
| `toto.castaldi@gmail.com` | `you@example.com` | |
| Account Cloudflare label "toto" | "user" | nella tabella "Asset e credenziali" — single-token leak |

## Hostname e naming

| Real | Placeholder/Modifica | Razionale |
|------|----------------------|-----------|
| `jarvis` (hostname) | **KEEP** (identità del progetto, narrative asset) | CONTEXT.md, CLAUDE.md, PITFALLS.md concordano |
| `Jarvis` (Title Case in ASCII diagram + altrove) | `jarvis` (lowercase) | CONTEXT.md §Specifics — coerenza naming |
| `toto` (Linux user) | **KEEP** (low sensitivity, UID 1000 ubiquo) | PITFALLS.md tabella anonymization |
| `inspiron-documents` (subdir backup, rivela modello laptop) | `laptop-documents` | leak modello hardware → generico |
| `laptop Inspiron` (testo discorsivo) | `laptop` | come sopra |

## DNS infrastruttura

| Real | Placeholder | Razionale |
|------|-------------|-----------|
| `remy.ns.cloudflare.com` | `nsX.example-dns.com` | NS Cloudflare assegnati: derivabili dalla zona ma non serve esporli |
| `wanda.ns.cloudflare.com` | `nsY.example-dns.com` | |
| `GoDaddy` (registrar) | **KEEP** | riferimento generico, non identificativo |

## Sezioni speciali

- **`# NOTE / ## init`** (provisioning iniziale): contiene `ssh ... toto@192.168.0.137 'mkdir -p ~/.ssh ...'`. Sostituito `192.168.0.137` → `192.168.0.Y`; `toto` resta (low sens); pattern shell preservato come istruzione narrative.
- **`## rsync`**: comando `rsync -avh --delete Documents/ jarvis:~/backups/inspiron-documents/`. `jarvis` resta; `inspiron-documents` → `laptop-documents`.
- **`## docker` e `## cloudfare`** (shell history numbered, anti-pattern PITFALLS §6.6): rimosso il prefisso numerico (`60 `, `61 `, …) e prependato `# ` per declassare a "comandi documentati" invece di shell history dump. Zero URL/token presenti nei comandi originali (verificato visivamente prima).
