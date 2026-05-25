# Research Summary — jarvis self-hosting v1

Sintesi delle 4 aree di ricerca: Supabase self-host, Cloudflare Tunnel + Access,
backup Postgres, repo public-ready hardening. Tutti i dettagli, fonti e snippet
sono nei singoli file (`STACK.md`, `ARCHITECTURE.md`, `BACKUP.md`,
`PITFALLS.md`).

---

## TL;DR — decisioni proposte per v1

| Area | Scelta v1 | Perché |
|------|-----------|--------|
| Stack Supabase | Snapshot pinnato di `supabase/supabase` master, copiato in `/home/toto/lumio/`. Tutta la lista di image tags fissata (Postgres 15.8, Kong 3.9.1, Studio 2026.04.27, ecc.). | Master è la fonte ufficiale, ma "pin a commit" evita drift. PG15 perché Lumio Cloud è PG15 (same-major restore). |
| Network | Kong (8000) come unico ingress. CF Tunnel espone solo `/auth /rest /realtime /storage /functions/v1`. Studio/admin SOLO via Tailscale. | CF termina TLS al loro edge → plaintext visibile a CF. Non mettere strumenti DB-mutating sul tunnel. |
| Tunnel | Local-managed + credentials file (no dashboard token). Pacchetto cloudflared con repo pinnato a `noble`. systemd hardening (User=cloudflared, ProtectSystem=strict, ecc.). | Dashboard token = pivot in caso di CF account compromise. Ubuntu 26.04 non ha ancora repo apt cloudflared. |
| Migrazione Lumio Cloud → jarvis | `supabase db dump` 3-file approach (roles + schema + data), restore in single-transaction con `session_replication_role=replica`. Storage objects via `aws s3 sync` separato. | `pg_dump` raw perde schemi Supabase (auth/storage/_realtime). JWT secret cambia → users forzati a re-login (accettabile in alpha). |
| Backup v1 | `pg_dump --format=custom` + `pg_dumpall --globals-only` daily via systemd timer. Storage via `rsync --link-dest`. Crittografia `age` (chiave pubblica on-host, privata off-host). Retention GFS 7d + 4w + 3m. Restore drill mensile su container disposable. | Single-node alpha → logical dumps semplici e portabili. pgBackRest archiviato Apr 2026 → da evitare. |
| Repo public-ready | `gitleaks` v8 pre-push + GitHub Action, con custom rules per UUID tunnel / IP pubblici / email / paths cloudflared. `trufflehog filesystem --only-verified` come second opinion pre-publish. **History squash a orphan branch `public-v1`** (la storia attuale ha "rifare" + "pre push" → nessun valore narrativo). | Nessun secret deve mai arrivare al remote public; pulizia post-fatto è sempre incompleta (reflog GitHub ~90 giorni). |
| LICENSE | **Nessuna LICENSE** (all-rights-reserved) oppure dual MIT (codice) + CC BY 4.0 (prose). | Repo è "narrative referenceable", non lib riusabile. |

---

## Watch Out For (top 6 gotchas)

1. **JWT secret rotation invalida tutte le sessioni esistenti** — accettabile solo perché Lumio è in alpha. Documentare in cutover runbook.
2. **`storage.objects` table si dumpa, i file no**: serve `aws s3 sync` (o equivalente) sui bucket Supabase Cloud → filesystem locale `volumes/storage/`.
3. **`pgsodium` master key non è recuperabile da Supabase Cloud**: se è in uso, vault data va re-crittografata o accettata come persa in cutover.
4. **Ingress catch-all è un security control**, non solo syntax: senza `http_status:404` di default, hostnames non documentati restano esposti. CI check con `cloudflared tunnel ingress validate`.
5. **`supabase db dump` strippa schemi Supabase** (auth, storage, _realtime). Non usarlo per disaster recovery. Usare la combinazione 3-file + `globals-only` per backup veri.
6. **Cloudflare deprecated signing key removed 30 April 2026**: calendar item esplicito per refresh chiave repo apt cloudflared.

---

## Table Stakes (features attese in un self-hosting setup)

- App pubblica accessibile via dominio HTTPS (no port forwarding sul router)
- Admin path (Studio, dashboards, SSH) NON pubblico
- Backup automatici + testati (un backup non restorato non è un backup)
- Secrets fuori dal repo, .env in .gitignore, encryption-at-rest per backup
- Documentazione del setup (architettura, scelte) e runbook ops minimo

## Differentiators (cose che il setup di Antonio fa diverse)

- Doppio canale di esposizione (CF Tunnel pubblico + Tailscale admin) — più sicuro del classico VPS con `ufw allow 443`
- Repo narrativo pubblicato — molti homelabber tengono tutto privato
- GSD workflow per planning/execution — non lo fa quasi nessuno per progetti homelab

## Anti-features (esplicitamente NON in v1)

- Backup off-site (B2/Hetzner) — Phase 5
- Helix (secondo stack Supabase) — v2
- Observability stack (Grafana/Loki/Prometheus) — post v1
- HA / replica Postgres — solo se Lumio esce da alpha
- Estrazione librerie riusabili — non è una lib

---

## Reference Files

- **`.planning/research/STACK.md`** — Supabase self-host: services, secrets, network, migration, version pins (PG15.8, Kong 3.9.1, ...)
- **`.planning/research/ARCHITECTURE.md`** — Cloudflare Tunnel + Access: deb822 source per Ubuntu 26.04, credentials model, ingress, systemd hardening, Tailscale coexistence
- **`.planning/research/BACKUP.md`** — Postgres backup: 5-tool comparison, systemd timer pattern, age encryption, GFS retention, restore drill, 5 decisioni aperte
- **`.planning/research/PITFALLS.md`** — Repo public-ready: gitleaks custom rules, history squash, .gitignore gaps, LICENSE decision, pre-publish checklist
