# jarvis — Personal self-hosting narrative

> This repo documents how I (a single dev) self-host a small set of services
> (Supabase, Cloudflare Tunnel, backups) on a home mini-PC named `jarvis`. It
> is a **narrative/reference**, not a reusable framework. All identifying
> assets (hostnames, UUIDs, IPs, emails) have been replaced with documentation
> placeholders (`example.com`, `203.0.113.X`, generic UUIDs). License: MIT
> (see [`LICENSE`](./LICENSE)).

**Note**: to enable the secret-scanning pre-push hook locally, after cloning run
`pre-commit install --hook-type pre-push` (requires the `pre-commit` Python
tool — e.g. `pipx install pre-commit`).

---

# BACKUP RSYNC

setup VPN mesh Tailscale
setup crontab


# SUPABASE

## Obiettivo

Spostare l'intero stack Supabase (DB Postgres, Auth, Storage, Edge Functions, Realtime) dei progetti **Lumio** e **Helix** dal servizio Supabase Cloud a un mini PC self-hosted in casa, chiamato `jarvis`.

**Vincoli e contesto:**

- Unico utente attuale è Antonio → si possono accettare brevi periodi di down.
- Mini PC con Ubuntu Server 26.04, IP dinamico in LAN, no port forwarding sul router.
- Esposizione a internet via **Cloudflare Tunnel** (uscita outbound, niente NAT/firewall da configurare).
- Due stack Supabase **separati** (uno per Lumio, uno per Helix), non un singolo stack condiviso.
- Lumio è in produzione: il suo frontend (`app.example.com`) resta su DigitalOcean, cambia solo il backend Supabase.

---

## Architettura target

```
                    Internet
                       |
                   Cloudflare
              (DNS + Tunnel edge)
                       |
                       | QUIC/HTTPS outbound
                       v
              ┌─────────────────────┐
              │  jarvis (mini PC)   │
              │  Ubuntu Server 26   │
              │                     │
              │  cloudflared        │
              │       │             │
              │       v             │
              │  ┌─────────────┐    │
              │  │ Stack Lumio │    │
              │  │  - Postgres │    │
              │  │  - Kong     │    │
              │  │  - Studio   │    │
              │  │  - GoTrue   │    │
              │  │  - Storage  │    │
              │  │  - Realtime │    │
              │  └─────────────┘    │
              │  ┌─────────────┐    │
              │  │ Stack Helix │    │
              │  │   (idem)    │    │
              │  └─────────────┘    │
              └─────────────────────┘
```

Sottodomini target (da creare nei prossimi step):

|Hostname|Servizio|
|---|---|
|`api.app.example.com`|Kong API gateway Lumio|
|`studio.app.example.com`|Supabase Studio Lumio|
|`api.service-a.example.com`|Kong API gateway Helix|
|`studio.service-a.example.com`|Supabase Studio Helix|

---

## Decisioni architetturali (registro)

|#|Decisione|Motivazione|
|---|---|---|
|1|Due stack Supabase separati invece di uno condiviso|Isolamento Auth/Storage/Realtime, backup indipendenti, aggiornamenti separati. RAM costo accettabile.|
|2|Cloudflare Tunnel come metodo di esposizione|Niente port forwarding, no IP statico, TLS gestito, gratis. Funziona dietro CGNAT.|
|3|DNS gestito da Cloudflare (intera zona spostata da GoDaddy)|Cloudflare ha rimosso il "Partial setup" dal piano Free → impossibile delegare solo un sottodominio. Spostamento completo è la via pulita.|
|4|Registrazione dominio resta su GoDaddy (no transfer)|Cambio NS è sufficiente. Il transfer è un'operazione ICANN separata, eventualmente in futuro.|
|5|`cloudflared` installato come servizio systemd|Riparte al boot, riconnette automaticamente, log su journald. Aggiornamenti via apt.|
|6|Layout filesystem `/home/toto/{lumio,helix,jarvis}`|Tutto sotto utente non-root, niente sudo per operazioni quotidiane.|
|7|Tutti i record DNS in modalità "DNS only" (non Proxied) durante la migrazione|Evita conflitti TLS con Let's Encrypt esistenti su GitHub Pages, Lumio, Helix, Docora.|

---

## Asset e credenziali

|Cosa|Valore|
|---|---|
|Account Cloudflare|`you@example.com` (SSO Google, no 2FA Cloudflare diretto — gestito lato Google)|
|Nome account Cloudflare|`user`|
|Nameserver Cloudflare assegnati|`nsX.example-dns.com`, `nsY.example-dns.com`|
|Registrar `example.com`|GoDaddy|
|Hostname jarvis|`jarvis`|
|Utente Linux|`toto`|
|IP LAN attuale|`192.168.0.X` (DHCP)|
|Tunnel Cloudflare nome|`jarvis`|
|Tunnel UUID|`00000000-0000-0000-0000-000000000000`|
|Tunnel credentials file|`/etc/cloudflared/<TUNNEL_UUID>.json`|
|Tunnel certificato origine|`~/.cloudflared/cert.pem` (origin CA cert, owner-only)|
|Cloudflared config|`/etc/cloudflared/config.yml`|
|Versione Docker|29.4.3 (Compose v5.1.3)|
|Versione cloudflared|2026.3.0|

---

## Step 1 — Preparazione infrastruttura DNS e host ✅

### Step 1.0 — Migrazione DNS `example.com` → Cloudflare

#### Inventario record DNS pre-migrazione

L'inventario è stato fatto due volte:

1. `dig` su sottodomini "comuni" → incompleto, mancavano `helix`, `m-lumio`, `docora`, ecc.
2. **Certificate Transparency logs via Certspotter API** → lista completa e affidabile.

```bash
# Comando definitivo per inventario sottodomini reali
curl -s "https://api.certspotter.com/v1/issuances?domain=example.com&include_subdomains=true&expand=dns_names" \
  | jq -r '.[].dns_names[]' \
  | sort -u
```

**11 record migrati su Cloudflare:**

|Hostname|Tipo|Target|Note|
|---|---|---|---|
|`example.com`|A (×4)|`203.0.113.10-13`|GitHub Pages|
|`www.example.com`|CNAME|`toto-castaldi.github.io`|GitHub Pages|
|`app.example.com`|A|`203.0.113.20`|DigitalOcean — Lumio frontend prod|
|`mobile.example.com`|A|`203.0.113.20`|Lumio mobile/marketing|
|`deck.app.example.com`|CNAME|`app.example.com`|Lumio deck|
|`service-a.example.com`|A|`203.0.113.20`|Helix frontend|
|`live.service-a.example.com`|A|`203.0.113.20`|Helix live|
|`coach.service-a.example.com`|A|`203.0.113.20`|Helix coach UI|
|`service-b.example.com`|A|`203.0.113.30`|Docora frontend|
|`api.service-b.example.com`|A|`203.0.113.30`|Docora API|
|`workflow.example.com`|A|`203.0.113.40`|n8n self-host (attualmente down)|

Niente MX/SPF/DKIM/DMARC: nessuna email su questo dominio. Migrazione "indolore".

#### Procedura eseguita

1. Account Cloudflare creato via SSO Google.
2. Tentativo iniziale con sottodominio `h.example.com` → **fallito**, Cloudflare Free non accetta più sottodomini come zone.
3. Aggiunta zona apex `example.com` su Cloudflare Free, import automatico (parziale: solo apex + `www` + `n8n`).
4. Aggiunta manuale degli 8 record mancanti tramite UI dashboard.
5. Tutti i record impostati su **DNS only** (nuvoletta grigia), record `_domainconnect` di GoDaddy ignorato.
6. Cambio nameserver su GoDaddy: `nsXX.domaincontrol.com` → `remy/nsY.example-dns.com`.
7. Propagazione completata in pochi minuti su `1.1.1.1` e `8.8.8.8`.
8. Smoke test su 11 hostname: 10/10 OK, n8n down per cause indipendenti.

### Step 1.1 — Docker su Jarvis

Installazione di Docker Engine + Compose v2 plugin via repo apt ufficiale Docker. Standard, nessun problema.

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker toto
```

Versione installata: **Docker 29.4.3**, **Compose v5.1.3**.

### Step 1.2 — Cloudflared + creazione tunnel

#### Inghippo Ubuntu 26.04

Il repo apt di Cloudflare non aveva ancora i pacchetti per il codename `resolute` (Ubuntu 26.04 LTS rilasciata pochi giorni prima). **Workaround**: forzato `noble` (24.04) come distribuzione del repo. Funziona perché `cloudflared` è praticamente un binario standalone Go senza dipendenze ABI fragili.

```bash
# /etc/apt/sources.list.d/cloudflared.list
deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
  https://pkg.cloudflare.com/cloudflared noble main
```

> **TODO futuro**: quando Cloudflare pubblicherà i pacchetti per `resolute`, cambiare `noble` → `resolute` e fare `apt update && apt upgrade`.

#### Creazione tunnel

```bash
cloudflared tunnel login        # autorizza zona example.com via browser
cloudflared tunnel create jarvis
```

Il tunnel `jarvis` è **uno solo per tutta l'infra**: il routing per hostname si fa nel file `config.yml` (sezione `ingress`).

### Step 1.3 — Test end-to-end con hello world

Procedura validata che dimostra il pipeline `internet → Cloudflare DNS → tunnel QUIC → cloudflared su Jarvis → servizio Docker locale`:

1. nginx in Docker su `localhost:8080`.
2. Regola `ingress` per `hello.example.com` → `http://localhost:8080`.
3. Comando `cloudflared tunnel route dns jarvis hello.example.com` per creare il CNAME automaticamente.
4. `cloudflared tunnel ... run jarvis` in foreground, 4 connessioni QUIC registrate (Roma `fco01` e Milano `mxp04/mxp06`).
5. Test da laptop esterno: `curl -I https://hello.example.com` → **HTTP/2 200**.

Edge case incontrato: il laptop usava Tailscale MagicDNS (`100.100.100.100`) come resolver di sistema, che ha cachato la NXDOMAIN iniziale. Bypass via `curl --resolve` per validare il pipeline; problema MagicDNS lasciato per dopo (non blocca nulla).

### Step 1.4 — cloudflared come servizio systemd

Spostata config in `/etc/cloudflared/`, installato come servizio:

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

Service stato: `active (running)`, ~18MB RAM, riparte al boot, log su `journalctl -u cloudflared`.

#### Stato attuale di `/etc/cloudflared/config.yml`

```yaml
tunnel: 00000000-0000-0000-0000-000000000000
credentials-file: /etc/cloudflared/<TUNNEL_UUID>.json

# Routing per hostname → servizio locale
ingress:
  # (Vuoto: aggiungeremo Lumio e Helix nei prossimi step)

  # Catch-all obbligatorio (deve essere l'ultimo)
  - service: http_status:404
```

---

## Convenzioni operative

### Aggiungere un nuovo servizio esposto via Cloudflare Tunnel

Tre passi standard:

1. **Aggiungi una regola `ingress`** in `/etc/cloudflared/config.yml` _prima_ del catch-all:
    
    ```yaml
    ingress:
      - hostname: nuovo-servizio.example.com
        service: http://localhost:PORTA
      - service: http_status:404
    ```
    
2. **Riavvia il tunnel:**
    
    ```bash
    sudo systemctl restart cloudflared
    ```
    
3. **Crea il record DNS:**
    
    ```bash
    cloudflared tunnel route dns jarvis nuovo-servizio.example.com
    ```
    

### Layout filesystem standard

```
/home/toto/jarvis/      ← cloudflared config dev, script di backup, docs
/home/toto/lumio/       ← stack Supabase Lumio (compose + volumi)
/home/toto/helix/       ← stack Supabase Helix (compose + volumi)
/etc/cloudflared/       ← config produttiva del tunnel (root-owned)
```

### Smoke test rapido del DNS

```bash
# Da qualsiasi macchina, test propagazione su big resolver
dig +short NS example.com @1.1.1.1
dig +short NS example.com @8.8.8.8
```

---

## Roadmap rimanente

- [ ] **Step 2** — Stack Supabase per Lumio
    - [ ] 2.1 Layout `/home/toto/lumio/`, scaricare docker-compose ufficiale
    - [ ] 2.2 Generare secret (JWT, anon key, service_role key, password Postgres)
    - [ ] 2.3 Configurare `.env` e fare primo `docker compose up`
    - [ ] 2.4 Esporre Kong su `api.app.example.com` e Studio su `studio.app.example.com`
    - [ ] 2.5 Verifica accesso Studio dall'esterno
- [ ] **Step 3** — Migrazione dati Lumio
    - [ ] 3.1 Dump da Supabase Cloud (schema + dati + auth.users + storage objects)
    - [ ] 3.2 Restore su Jarvis
    - [ ] 3.3 Verifica integrità (conteggio righe, sample queries)
- [ ] **Step 4** — Switch frontend Lumio
    - [ ] Aggiornare env vars di web (Vite), mobile (Expo), edge functions
    - [ ] Aggiornare CI/CD se applicabile
    - [ ] Smoke test funzionale
- [ ] **Step 5** — Replica del processo per Helix (Step 2-4)
- [ ] **Step 6** — Backup automatici
    - [ ] `pg_dump` schedulato via cron/systemd timer
    - [ ] Sync oggetti Storage su cloud esterno (Backblaze B2 / Hetzner Storage Box)
- [ ] **Step 7 (bonus)** — Migrare anche n8n su Jarvis (eventualmente)

---

## Note e issue aperti

### n8n attualmente down

`workflow.example.com` (DigitalOcean `203.0.113.40`) non risponde — issue del droplet, non legato alla migrazione DNS. Da affrontare a parte; candidato naturale per migrazione su Jarvis nello Step 7.

### MagicDNS / Tailscale negative cache sul laptop

Sul laptop principale, il resolver `100.100.100.100` (Tailscale MagicDNS) ha cachato un NXDOMAIN per `hello.example.com` durante i test. Né `resolvectl flush-caches` né `systemctl restart tailscaled` hanno risolto. **Workaround attuale**: usare `dig @1.1.1.1` per verifiche DNS e `curl --resolve` per test HTTPS. Da indagare con calma in un altro momento.

### Record `_domainconnect` ancora su Cloudflare

Era un CNAME di GoDaddy importato automaticamente. Lasciato per ora ma può essere cancellato senza impatto: serviva solo a integrazioni one-click sul pannello GoDaddy che non usiamo più.

### Pacchetti `cloudflared` per Ubuntu 26.04 (`resolute`)

Repo apt fissato su `noble` (24.04). Quando Cloudflare pubblicherà per `resolute`, cambiare in `/etc/apt/sources.list.d/cloudflared.list`.

### 2FA su Cloudflare

Login via SSO Google → 2FA non configurabile direttamente su Cloudflare. La sicurezza dipende dal 2FA dell'account Google. Per le operazioni critiche future considerare la creazione di **API token Cloudflare** scoped (es. per script di backup DNS).

# VISION

digital-ocean Docora
digital-ocean static-web-sites
google photo
google drive extension
password manager
Obsidian Sync
Spotify
# NOTE

## init

cat ~/.ssh/id_ed25519.pub | ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password toto@192.168.0.Y 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'


sudo nano /etc/ssh/sshd_config
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
sudo grep -r PasswordAuthentication /etc/ssh/

sudo nano /etc/systemd/logind.conf
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
sudo systemctl restart systemd-logind


sudo vi /etc/netplan/00-installer-config.yaml
dhcp4

sudo vbetool dpms off

## rsync

curl -fsSL https://tailscale.com/install.sh | sh
tailscale !!!

rsync

rsync -avh --delete Documents/ jarvis:~/backups/laptop-documents/


## docker

sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/nul
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker toto

## cloudfare

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg  https://pkg.cloudflare.com/cloudflared noble main"  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main"  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
sudo apt install -y cloudflared
cloudflared --version

cloudflared tunnel login
ls -la ~/.cloudflared/
cloudflared tunnel create jarvis
cloudflared tunnel list

#computer #home 