# STACK.md — Self-hosting Supabase via Docker Compose (2025-2026)

Research notes for migrating **Lumio** from Supabase Cloud onto `jarvis`
(Ubuntu 26.04, 16 GB RAM, mini-PC). Target dir: `/home/toto/lumio/`.
Public exposure via **Cloudflare Tunnel** (no open ports); admin via
**Tailscale + Cloudflare Access**. Security wins ties.

All recommendations are prescriptive. Versions and tags are pinned to
values present on `supabase/supabase@master` as of the April 2026
snapshot in the official repo (see versions.md citations below).

---

## 1. Source repo, layout, services

### 1.1 Repo + branch

There is **no separate "self-hosted" repo**. Self-hosting lives in the
main monorepo under the `docker/` subdirectory, on the `master` branch.

```bash
# In /home/toto/  (NOT inside lumio/, see below)
git clone --depth 1 https://github.com/supabase/supabase supabase-src

# Materialize the runtime tree
mkdir -p /home/toto/lumio
cp -rf supabase-src/docker/* /home/toto/lumio/
cp     supabase-src/docker/.env.example /home/toto/lumio/.env
```

Source: [Self-Hosting with Docker — supabase.com/docs](https://supabase.com/docs/guides/self-hosting/docker)
and [supabase/supabase/tree/master/docker](https://github.com/supabase/supabase/tree/master/docker).

**Why clone separately?** The docker/ tree is updated continuously
(rolling release: Supabase ships master-tagged images and there is no
"LTS" branch). Keeping the upstream clone separate from `/home/toto/lumio/`
lets you `git pull` and diff what changed before copying overrides.
Officially the project ships **no SemVer tag** for the compose stack —
the recommended cadence is "pull master periodically and rebuild after
diffing `.env.example`, `docker-compose.yml`, `volumes/`".

> **Pin strategy for jarvis**: take a snapshot commit hash now (write it
> into `.planning/PROJECT.md` § Decisions) and only bump on intentional
> upgrade windows. Do **not** track `master` blindly in production.

### 1.2 Files shipped in `docker/`

From [github.com/supabase/supabase/tree/master/docker](https://github.com/supabase/supabase/tree/master/docker):

| Path                              | Purpose                                                                     |
| --------------------------------- | --------------------------------------------------------------------------- |
| `docker-compose.yml`              | Main stack (Postgres 15 default)                                            |
| `docker-compose.pg17.yml`         | Override that swaps in `supabase/postgres:17.x` (use for new installs)      |
| `docker-compose.s3.yml`           | Override: external S3-compatible storage backend (vs local disk)            |
| `docker-compose.rustfs.yml`       | Override: RustFS storage backend                                            |
| `docker-compose.nginx.yml`        | Sample override placing nginx in front of Kong                              |
| `docker-compose.caddy.yml`        | Sample override using Caddy as TLS terminator                               |
| `docker-compose.envoy.yml`        | Envoy reverse-proxy variant                                                 |
| `.env.example`                    | Required template (see §2)                                                  |
| `volumes/api/kong.yml`            | Kong declarative config — routes + basic-auth on Studio                     |
| `volumes/db/`                     | Bootstrap SQL: `realtime.sql`, `roles.sql`, `webhooks.sql`, `_supabase.sql` |
| `volumes/functions/`              | Edge function source mounts                                                 |
| `volumes/logs/vector.yml`         | Vector pipeline config                                                      |
| `volumes/storage/`                | Local-storage backend mount                                                 |
| `utils/generate-keys.sh`          | Generates JWT_SECRET + signs ANON_KEY/SERVICE_ROLE_KEY                      |
| `utils/add-new-auth-keys.sh`      | Adds asymmetric JWKS (new keys system, optional but recommended)            |
| `reset.sh`                        | Destructive wipe helper                                                     |
| `versions.md`                     | Changelog of pinned image versions                                          |
| `CONFIG.md`                       | Per-service env var reference                                               |

### 1.3 Services in `docker-compose.yml` (13 services)

Pinned tags from a fresh fetch of [docker/docker-compose.yml](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml)
(April 2026 snapshot):

| Service     | Image:Tag                                | Role                               | Host port?                          |
| ----------- | ---------------------------------------- | ---------------------------------- | ----------------------------------- |
| `db`        | `supabase/postgres:15.8.1.085`           | Postgres 15 (Supabase build)       | **internal only**                   |
| `studio`    | `supabase/studio:2026.04.27-sha-5f60601` | Dashboard UI                       | **internal only** (proxied by Kong) |
| `kong`      | `kong/kong:3.9.1`                        | API gateway / single ingress       | `8000:8000`, `8443:8443`            |
| `auth`      | `supabase/gotrue:v2.186.0`               | GoTrue auth                        | internal only                       |
| `rest`      | `postgrest/postgrest:v14.8`              | PostgREST → DB                     | internal only                       |
| `realtime`  | `supabase/realtime:v2.76.5`              | Phoenix WS for DB changes          | internal only                       |
| `storage`   | `supabase/storage-api:v1.48.26`          | Storage API (objects metadata)     | internal only                       |
| `imgproxy`  | `darthsim/imgproxy:v3.30.1`              | On-the-fly image transforms        | internal only                       |
| `meta`      | `supabase/postgres-meta:v0.96.3`         | DB introspection used by Studio    | internal only                       |
| `functions` | `supabase/edge-runtime:v1.71.2`          | Deno edge runtime                  | internal only                       |
| `analytics` | `supabase/logflare:1.36.1`               | Logflare backend (needs DB schema) | internal only                       |
| `vector`    | `timberio/vector:0.53.0-alpine`          | Log shipper → Logflare             | internal only                       |
| `supavisor` | `supabase/supavisor:2.7.4`               | Pooler (5432 session, 6543 txn)    | `5432:5432`, `6543:6543`            |

Sources: [docker/docker-compose.yml @ master](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml)
and [docker/versions.md](https://github.com/supabase/supabase/blob/master/docker/versions.md).

**Note on default ingress:** Only **Kong** (8000/8443) and **Supavisor**
(5432/6543) bind to host ports out of the box. For jarvis we will
**unbind Supavisor's host ports** in our override (see §3.3) — direct
Postgres access goes through Tailscale, not the host firewall.

### 1.4 Studio + Kong default posture (must harden)

- Studio container has **no auth of its own**. Protection comes from
  Kong's `basic-auth` plugin in `volumes/api/kong.yml`, which checks
  `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` on the route to Studio.
- The default `DASHBOARD_PASSWORD` in `.env.example` is literally
  `this_password_is_insecure_and_should_be_updated`.
- Kong runs in **DB-less mode** with `KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml`.
- Kong's `consumers` block declares one user; rotating Studio creds
  means editing `.env` **and** restarting Kong (config is rendered at
  container start).
- Kong exposes a separate route `/analytics` (Logflare) protected by
  the same basic-auth consumer.
- The Studio route also requires a valid JWT signed by `JWT_SECRET`
  (ANON_KEY for read, SERVICE_ROLE_KEY for write actions). The
  basic-auth + JWT chain is what guards the admin surface.

### 1.5 Resource fit on jarvis (16 GB RAM)

A vanilla stack idles at roughly:
- `db` Postgres: ~250-400 MB
- `analytics` (Logflare on BEAM): ~400-700 MB
- `realtime` (Phoenix on BEAM): ~250-400 MB
- `supavisor` (BEAM): ~200-300 MB
- `vector`: ~50-100 MB
- everything else combined: ~600-900 MB

→ ~2.5-3.5 GB resident, plus Postgres shared_buffers headroom. Fits 16 GB
comfortably **if you do not also run heavy app services** on the same host.

Official docs explicitly allow trimming: "If you don't need specific
services, such as Logflare (Analytics), Realtime, Storage, imgproxy, or
Edge Runtime (Functions), you can remove the corresponding sections
and dependencies from `docker-compose.yml`."
([self-hosting/docker](https://supabase.com/docs/guides/self-hosting/docker)).
For **Lumio v1 we keep all services** (Lumio uses auth, postgrest,
storage; analytics is harmless and useful for debugging). Revisit in
Phase 4 if RAM pressure appears.

---

## 2. Secrets generation (mandatory rotation list)

Every default in `.env.example` must be replaced before first `up`.
Source: [docker/.env.example](https://github.com/supabase/supabase/blob/master/docker/.env.example).

### 2.1 The full mandatory rotation set

| Variable                       | Default in .env.example                             | What it does                          | How to regenerate                                |
| ------------------------------ | --------------------------------------------------- | ------------------------------------- | ------------------------------------------------ |
| `POSTGRES_PASSWORD`            | `your-super-secret-and-long-postgres-password`      | superuser/postgres role + pooler auth | `openssl rand -base64 36`                        |
| `JWT_SECRET`                   | `your-super-secret-jwt-token-with-at-least-32-...`  | HS256 secret for legacy ANON/SERVICE  | `openssl rand -base64 64`                        |
| `ANON_KEY`                     | pre-baked HS256 JWT                                 | client-side JWT (anon role)           | `utils/generate-keys.sh` (signs with JWT_SECRET) |
| `SERVICE_ROLE_KEY`             | pre-baked HS256 JWT                                 | server-side JWT (full DB)             | `utils/generate-keys.sh`                         |
| `SUPABASE_PUBLISHABLE_KEY`     | empty                                               | opaque client key (new key system)    | `utils/add-new-auth-keys.sh`                     |
| `SUPABASE_SECRET_KEY`          | empty                                               | opaque server key (new key system)    | `utils/add-new-auth-keys.sh`                     |
| `JWT_KEYS` / `JWT_JWKS`        | empty / `{"keys":[]}`                               | EC keypair JWKS for new key system    | `utils/add-new-auth-keys.sh`                     |
| `DASHBOARD_USERNAME`           | `supabase`                                          | Studio basic-auth user                | manual; pick a non-default name                  |
| `DASHBOARD_PASSWORD`           | `this_password_is_insecure_and_should_be_updated`   | Studio basic-auth pass                | `openssl rand -base64 24` (alphanumeric — see §2.4) |
| `SECRET_KEY_BASE`              | placeholder                                         | Realtime + Supavisor session signing  | `openssl rand -hex 32` (≥ 64 chars output)       |
| `VAULT_ENC_KEY`                | placeholder                                         | Supavisor tenant config encryption    | **exactly 32 chars** — `openssl rand -hex 16`    |
| `PG_META_CRYPTO_KEY`           | placeholder                                         | Studio↔pg-meta secret column encrypt  | `openssl rand -hex 32`                           |
| `LOGFLARE_PUBLIC_ACCESS_TOKEN` | placeholder                                         | analytics ingestion/query             | `openssl rand -hex 32`                           |
| `LOGFLARE_PRIVATE_ACCESS_TOKEN`| placeholder                                         | analytics admin                       | `openssl rand -hex 32`                           |
| `POOLER_TENANT_ID`             | placeholder                                         | Supavisor tenant id (used in conn str)| any short slug, e.g. `lumio`                     |
| `S3_PROTOCOL_ACCESS_KEY_ID`    | sample                                              | S3-compat front for storage           | `openssl rand -hex 16` (only if S3 proto used)   |
| `S3_PROTOCOL_ACCESS_KEY_SECRET`| sample                                              | "                                     | `openssl rand -base64 36`                        |

### 2.2 Canonical generator

```bash
cd /home/toto/lumio
sh utils/generate-keys.sh     # writes JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY
sh utils/add-new-auth-keys.sh # writes JWT_KEYS, JWT_JWKS, PUBLISHABLE/SECRET
```

Both scripts are idempotent and rewrite `.env` in place. Source:
[guides/self-hosting/docker.mdx](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/self-hosting/docker.mdx)
and [guides/self-hosting/self-hosted-auth-keys.mdx](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/self-hosting/self-hosted-auth-keys.mdx).

For everything else (passwords, encryption keys) the generator does
NOT touch them — do them by hand:

```bash
# One-shot bootstrap script (write under /home/toto/lumio/bootstrap-secrets.sh, .gitignored)
echo "POSTGRES_PASSWORD=$(openssl rand -base64 36 | tr -d '/+=' | head -c 32)"
echo "DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
echo "SECRET_KEY_BASE=$(openssl rand -hex 32)"          # 64 hex chars
echo "VAULT_ENC_KEY=$(openssl rand -hex 16)"            # exactly 32 chars
echo "PG_META_CRYPTO_KEY=$(openssl rand -hex 32)"
echo "LOGFLARE_PUBLIC_ACCESS_TOKEN=$(openssl rand -hex 32)"
echo "LOGFLARE_PRIVATE_ACCESS_TOKEN=$(openssl rand -hex 32)"
```

### 2.3 Storage / handling

- `.env` lives at `/home/toto/lumio/.env`, owner `toto:toto`, mode `0600`.
- **Never commit `.env`** — gitleaks pre-commit will catch this. The
  shipped `.gitignore` in `docker/` already excludes it.
- For v1 single-dev there is no Vault — just keep an offline copy
  (encrypted with `age` or in a password manager). Phase 5 may
  introduce HashiCorp Vault / sops-age if it gains team members.
- Rotation in-place: bump value in `.env`, `docker compose up -d`
  (Compose recreates affected containers). The JWT secret rotation is
  **destructive to existing tokens** — schedule during the cutover
  window.

### 2.4 Caveats (well-documented footguns)

- **DASHBOARD_PASSWORD must be alphanumeric only.** Kong's basic-auth
  plugin chokes on certain shell-special chars (`$`, `!`, `'`, `"`),
  and the docs explicitly say "no special characters, no numbers-only,
  must contain at least one letter."
- **VAULT_ENC_KEY is exactly 32 bytes.** Supavisor `cloak` library
  validates length; longer/shorter → crash loop.
- **POSTGRES_PASSWORD is used in URL strings** (`postgres://...`) by
  multiple services. If it contains `@`, `:`, `/`, or `?`, services
  will misparse the URL. Restrict to URL-safe charset
  (`tr -d '/+=@:?#&'`).
- The **legacy** `ANON_KEY` / `SERVICE_ROLE_KEY` and the **new**
  `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY` coexist. For Lumio
  v1, keep both (apps still using anon/service keys keep working);
  start moving clients to the new opaque keys in Phase 4.

---

## 3. Network model

### 3.1 Single ingress = Kong

Kong is the **only** HTTP entrypoint defined by Supabase. Default
declarative routes in `volumes/api/kong.yml`:

| External path        | Upstream service        | Auth chain (default)         |
| -------------------- | ----------------------- | ---------------------------- |
| `/` (root → Studio)  | `studio:3000`           | **basic-auth** (DASHBOARD_*) |
| `/auth/v1/*`         | `auth:9999`             | JWT (ANON/SERVICE)           |
| `/rest/v1/*`         | `rest:3000` (PostgREST) | JWT                          |
| `/realtime/v1/*`     | `realtime:4000`         | JWT                          |
| `/storage/v1/*`      | `storage:5000`          | JWT                          |
| `/functions/v1/*`    | `functions:9000`        | JWT                          |
| `/pg/*`              | `meta:8080` (pg-meta)   | basic-auth (DASHBOARD_*)     |
| `/analytics/*`       | `analytics:4000`        | basic-auth                   |

Source: [docker/volumes/api/kong.yml](https://github.com/supabase/supabase/blob/master/docker/volumes/api/kong.yml).

### 3.2 What jarvis exposes via Cloudflare Tunnel

**Public hostname** (e.g. `api.lumio.example.com`) → cloudflared →
`http://127.0.0.1:8000` (Kong HTTP). Tunnel ingress rules should
**explicitly allow only the public API paths and block admin paths**:

```yaml
# /etc/cloudflared/config.yml (sketch)
ingress:
  - hostname: api.lumio.example.com
    path: ^/(auth|rest|realtime|storage|functions)/v1/.*
    service: http://127.0.0.1:8000
  - hostname: api.lumio.example.com
    service: http_status:404         # everything else → 404 at the edge
```

This means **Studio, `/pg`, `/analytics`, and `/` are not reachable
from the public Cloudflare hostname at all** — defense in depth even if
Kong basic-auth were misconfigured.

> Cloudflare Tunnel rule ordering matters: list specific paths first,
> then the catch-all 404. Test with `cloudflared tunnel ingress validate`
> and `cloudflared tunnel ingress rule https://api.lumio.example.com/rest/v1/`.

### 3.3 Admin plane = Tailscale + Cloudflare Access

For Studio / pg-meta / analytics, the rule is **not publicly reachable
at all**. Two compatible options:

**Option A (recommended for v1): Tailscale only.**
- Add `tailscale0` interface as a Kong listener via override file (see
  below) OR bind Kong's `8000` to `100.x.x.x` (jarvis's tailnet IP) and
  drop the public Cloudflare hostname for `/` entirely.
- Admin browses to `http://jarvis.tail-scale.ts.net:8000` from any
  device on the tailnet.

**Option B: Separate Cloudflare hostname behind CF Access.**
- `admin.lumio.example.com` → cloudflared → `http://127.0.0.1:8000`
- Cloudflare Access policy: require email = `toto.castaldi@gmail.com`
  + WebAuthn. CF Access enforces auth **before** the request hits Kong.
- Kong basic-auth still applies (belt + suspenders).

**For jarvis v1 use Option A** (simpler, no public surface at all for
admin). Add Option B later if you ever need admin from a non-Tailscale
device.

### 3.4 Postgres direct access (Supavisor 5432/6543)

The default compose **publishes** Supavisor on host ports 5432 + 6543.
For jarvis we want **no public Postgres** ever:

- Override `docker-compose.override.yml` to **unbind** these ports from
  `0.0.0.0` and bind only to `127.0.0.1` (and optionally the tailnet IP).
- Application services (Lumio app on DigitalOcean → jarvis) connect to
  Postgres only through Cloudflare Tunnel TCP forwarding **or** the
  Supabase REST/Realtime APIs over the public Kong hostname. **Prefer
  the latter** — exposing raw Postgres via tunnel TCP is supported but
  costs perf + adds attack surface.
- For local psql / pg_dump from your laptop: SSH/Tailscale into jarvis,
  then `psql postgres://postgres.lumio:<pw>@127.0.0.1:5432/postgres`.

Override snippet to drop from `/home/toto/lumio/docker-compose.override.yml`:

```yaml
services:
  supavisor:
    ports: !reset
      - "127.0.0.1:5432:5432"
      - "127.0.0.1:6543:6543"
  kong:
    ports: !reset
      - "127.0.0.1:8000:8000"
      - "127.0.0.1:8443:8443"
```

(`!reset` is a Compose YAML directive — drops parent list, then
appends.) Cloudflared and Tailscale both run on the host and can reach
`127.0.0.1`, so this is enough to slam the firewall shut.

Then on the host (Ubuntu 26.04 ships nftables):
```bash
sudo ufw default deny incoming
sudo ufw allow in on tailscale0
sudo ufw allow ssh                # if you don't use Tailscale SSH
sudo ufw enable
```

---

## 4. Data migration: Supabase Cloud → self-hosted

Primary source: [Restore a Platform Project to Self-Hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

### 4.1 Three-file dump (preferred over raw pg_dump)

```bash
# From your dev box (laptop), with current supabase CLI installed
export SOURCE_DB_URL='postgres://postgres.<ref>:<pw>@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'

supabase db dump --db-url "$SOURCE_DB_URL" -f roles.sql  --role-only
supabase db dump --db-url "$SOURCE_DB_URL" -f schema.sql
supabase db dump --db-url "$SOURCE_DB_URL" -f data.sql --use-copy --data-only
```

**Why the CLI and not raw `pg_dump`?** The Supabase CLI:
- excludes Supabase-internal schemas (`_supabase`, `_realtime`, etc.)
  that already exist in the target,
- strips reserved cloud-only roles (`supabase_admin`, `supabase_auth_admin`
  permissions),
- adds `IF NOT EXISTS` clauses for idempotence,
- handles `auth.*` and `storage.*` schemas correctly.

Raw `pg_dump` will reproduce internals and the restore will fail with
permission errors. ([Restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform).)

### 4.2 Restore command

```bash
export TARGET_DB_URL='postgres://postgres.lumio:<pw>@127.0.0.1:5432/postgres'

psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname "$TARGET_DB_URL"
```

- `session_replication_role = replica` disables triggers during data
  load — critical to avoid **double-encryption of vault columns** and
  duplicate audit rows.
- `--single-transaction` rolls back atomically on any error.
- `ON_ERROR_STOP=1` makes psql fail fast.

### 4.3 `auth.users` migration — what survives, what doesn't

**Survives the dump:**
- `auth.users.encrypted_password` (bcrypt hashes) — users keep their
  passwords. No re-enrollment needed for email/password accounts.
- `auth.identities` (OAuth provider link rows) — preserved.
- MFA factors, recovery codes, sessions metadata.

**Does NOT survive (must re-do manually):**
- **All issued JWTs are invalidated** because `JWT_SECRET` is freshly
  generated on jarvis. Active sessions across all Lumio users die at
  cutover; everyone re-logs-in. Communicate this in maintenance notice.
- **OAuth provider config** (Google/Apple/etc.) is in cloud
  project settings, not in the dump. Re-set `GOTRUE_EXTERNAL_<PROVIDER>_*`
  env vars in jarvis `.env`, and **update redirect URLs in each provider
  console** to point to `https://api.lumio.example.com/auth/v1/callback`.
- **SMTP config** — set `SMTP_HOST/PORT/USER/PASS/SENDER_NAME` in `.env`.
- **Custom email templates** (Confirm Sign-up, Magic Link, Reset, etc.)
  — re-author by editing `volumes/storage/...` or via Studio UI post-restore.
- **Hooks (auth hooks, SMS hooks)** — re-configure under
  `GOTRUE_HOOK_*` env vars.

### 4.4 `storage.objects` — schema vs. files

The dump captures the `storage.objects` **table** (metadata: bucket,
path, mimetype, owner, size). It does **not** copy the actual file
bytes — those live in cloud project's S3 bucket and must be copied
separately.

Two paths for the byte copy:

**A. Direct S3-to-disk (recommended for Lumio's volume).**
Supabase Cloud's S3 bucket is reachable via the cloud project's
`Settings → Storage → S3 connection` page (gives you access key, secret,
endpoint, bucket name).

```bash
# On jarvis, target = local storage backend at volumes/storage/
aws s3 sync \
  s3://<cloud-bucket>/ \
  /home/toto/lumio/volumes/storage/stub/stub/ \
  --endpoint-url https://<project-ref>.supabase.co/storage/v1/s3 \
  --profile supabase-cloud
```

The triple `stub/stub/` is because the self-hosted local backend mounts
under `${GLOBAL_S3_BUCKET}/${TENANT_ID}/` and `.env.example` ships both
as `stub`. Verify your `.env` values before running.

**B. Use [supabase-storage-migrate](https://github.com/supabase-community/supabase-storage-migrate)**
(community tool that walks `storage.objects` and uses Storage API on
both ends). Slower but handles signed URLs and bucket-level RLS.

**Caveats:**
- File ownership is recorded as `owner` UUID = `auth.users.id`. After
  the auth dump+restore the owners line up — but if you restored auth
  with **partial** users, you'll get orphan objects.
- Public buckets stay public; private buckets need their RLS policies,
  which are part of `schema.sql`.
- The `storage.buckets` table is in the dump too — buckets recreate
  automatically.

### 4.5 Custom roles + secrets

- Roles with `LOGIN` come over **without passwords** (`pg_dump
  --role-only` deliberately strips them). Reset each:
  ```sql
  ALTER ROLE my_custom_role WITH PASSWORD 'new-strong-pw';
  ```
- `pgsodium` master key: if the cloud project used `pgsodium`-managed
  secrets (Vault), the master key is held by Supabase Cloud and is
  **not exportable**. Plan a one-time re-encryption: dump secret
  values via the Vault decrypted view on the cloud side, then re-insert
  on jarvis under the new master key.
- Extensions: enumerate before cutover and enable on target:
  ```sql
  -- On cloud
  SELECT extname, extversion FROM pg_extension ORDER BY extname;
  -- On target, CREATE EXTENSION IF NOT EXISTS ... for each
  ```

### 4.6 Cutover dry-run procedure (recommended)

1. **Dry run** (T-7 days): take a non-prod dump, restore into a scratch
   jarvis stack, smoke-test login + a few writes. Time the restore.
2. **Freeze write window** (T-0): put cloud project into read-only
   (revoke INSERT/UPDATE/DELETE on app role) — this is the cleanest
   way to bound the dataset.
3. **Final dump**: re-run the three commands.
4. **Restore on jarvis**.
5. **DNS / app config flip**: point Lumio app at
   `https://api.lumio.example.com`. Update `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY` in app env.
6. **Smoke test** end-to-end (signup, login, one of each CRUD).
7. **Keep cloud project for 30 days read-only** before deletion (rollback
   window).

No logical replication — confirmed in `.planning/PROJECT.md` (hard
cutover window). This dry-run + freeze approach replaces it.

---

## 5. Version pins (prescriptive for jarvis v1)

### 5.1 Recommended pinned versions

| Component                | Pin                                       | Why this value                          |
| ------------------------ | ----------------------------------------- | --------------------------------------- |
| `supabase/postgres`      | **`15.8.1.085`**                          | Compose-default through May 2026; shipping Supabase build; broad extension support. ([versions.md](https://github.com/supabase/supabase/blob/master/docker/versions.md)) |
| `kong/kong`              | `3.9.1`                                   | Compose-pinned                          |
| `supabase/gotrue`        | `v2.186.0`                                | Compose-pinned                          |
| `postgrest/postgrest`    | `v14.8`                                   | Compose-pinned                          |
| `supabase/realtime`      | `v2.76.5`                                 | Compose-pinned                          |
| `supabase/storage-api`   | `v1.48.26`                                | Compose-pinned                          |
| `darthsim/imgproxy`      | `v3.30.1`                                 | Compose-pinned                          |
| `supabase/postgres-meta` | `v0.96.3`                                 | Compose-pinned                          |
| `supabase/edge-runtime`  | `v1.71.2`                                 | Compose-pinned                          |
| `supabase/logflare`      | `1.36.1`                                  | Compose-pinned                          |
| `timberio/vector`        | `0.53.0-alpine`                           | Compose-pinned                          |
| `supabase/supavisor`     | `2.7.4`                                   | Compose-pinned                          |
| `supabase/studio`        | `2026.04.27-sha-5f60601`                  | Date-tagged; refresh quarterly          |

### 5.2 Postgres 15 vs 17 decision

**For Lumio v1 → use Postgres 15** (the compose default), because:
- The cloud project Lumio is currently on **is Postgres 15** (Supabase
  Cloud rolled to PG17 default in late 2025, but existing projects
  stayed on 15 unless explicitly upgraded). Restore is then a
  same-major operation — zero version-skew gotchas.
- PG 15 image is the production default until **week of 15 June 2026**,
  when [docker-compose.yml flips to PG17](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17).
  Pinning now gives you a stable target.
- Known PG17-only migration friction: `auth.oauth_clients` and
  `storage.buckets_vectors` exist only in newer schemas; restoring a PG15
  dump into PG17 is fine, but the inverse is not.

**Switch to Postgres 17** in Phase 4 or later if:
- Lumio cloud project gets upgraded to PG17 first, OR
- you need PG17-only features (`MERGE` improvements, incremental backups
  via `pg_basebackup --incremental`, JSON_TABLE, etc.).

To enable PG17 on a **new** install (not for Lumio v1):
```bash
docker compose -f docker-compose.yml -f docker-compose.pg17.yml up -d
```
([upgrade guide](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17))

**Hard blockers for PG17 upgrade** (per upstream): databases using
`timescaledb`, `plv8`, `plcoffee`, or `plls` extensions **cannot**
upgrade — these are not packaged in Supabase's PG17 image. Verify
Lumio's extension list does not include any of these before any future
upgrade.

### 5.3 Docker Compose version

- **Compose v2 only** (`docker compose`, not `docker-compose`). Ships
  in `docker-ce` ≥ 23.0 — Ubuntu 26.04's `docker-compose-plugin`
  package is v2.x and is fine. The shipped `docker-compose.yml` uses
  no obsolete `version: "3.x"` header (modern style).
- Pin the Docker engine via Ubuntu's `docker-ce` apt repo, not the
  distro `docker.io` package (which lags). Holdback to LTS minor
  releases:
  ```bash
  sudo apt-mark hold docker-ce docker-ce-cli containerd.io \
                     docker-buildx-plugin docker-compose-plugin
  ```

### 5.4 Upgrade hygiene

- Pin all images via override file at first deploy (not by editing
  upstream files, which `git pull` will clobber):
  ```yaml
  # /home/toto/lumio/docker-compose.override.yml
  services:
    db:       { image: supabase/postgres:15.8.1.085 }
    studio:   { image: supabase/studio:2026.04.27-sha-5f60601 }
    # ...etc
  ```
- Bi-monthly: `cd supabase-src && git pull`, diff `docker/versions.md`,
  evaluate, then bump tags in the override.
- Snapshot Postgres data volume before any version bump:
  ```bash
  docker compose stop db
  sudo tar -C /home/toto/lumio/volumes/db -czf /backups/db-$(date +%F).tgz .
  docker compose start db
  ```

---

## Reference index

- [Self-Hosting with Docker (canonical guide)](https://supabase.com/docs/guides/self-hosting/docker)
- [Restore a Platform Project to Self-Hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform)
- [Self-hosted Auth Keys (new asymmetric system)](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/self-hosting/self-hosted-auth-keys.mdx)
- [Upgrade Self-Hosted to Postgres 17](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17)
- [Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [supabase/supabase/tree/master/docker](https://github.com/supabase/supabase/tree/master/docker)
- [docker/.env.example](https://github.com/supabase/supabase/blob/master/docker/.env.example)
- [docker/docker-compose.yml](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml)
- [docker/versions.md](https://github.com/supabase/supabase/blob/master/docker/versions.md)
- [docker/volumes/api/kong.yml](https://github.com/supabase/supabase/blob/master/docker/volumes/api/kong.yml)
- [Self-Hosting Analytics](https://supabase.com/docs/reference/self-hosting-analytics/introduction)
- [Migrating Auth Users Between Projects](https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects)
- [Docker Compose for Supabase: Production Best Practices (supascale.app)](https://www.supascale.app/blog/docker-compose-for-supabase-production-best-practices)
- [Upgrading Self-Hosted Supabase: Version Migration Guide (supascale.app)](https://www.supascale.app/blog/upgrading-selfhosted-supabase-a-complete-version-migration-g)
- [Lovable Cloud → Self-hosted Supabase Migration (wz-it.com)](https://wz-it.com/en/expertises/supabase/from-lovable/)
- [Ultimate Supabase self-hosting Guide (activeno.de)](https://activeno.de/blog/2023-08/the-ultimate-supabase-self-hosting-guide/)
- Community discussion on PG15→17 upgrade: [#36903](https://github.com/orgs/supabase/discussions/36903)
- Community discussion on Docker Swarm self-host: [#27467](https://github.com/orgs/supabase/discussions/27467)
