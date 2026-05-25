# Backup strategy — Supabase self-hosted (Lumio v1)

Status: research note for Phase planning (v1). On-host only; off-site
deferred to Phase 5.
Host: `jarvis` (Ubuntu 26.04, 16 GB RAM, single node, Docker).
Stack: `/home/toto/lumio/` (official Supabase docker-compose).
Posture: alpha, few users, "precious data". Target RPO ≈ 0 (≤ 15 min
window), RTO can be hours. Security wins ties.

---

## TL;DR — v1 recommendation

1. **Logical backups** (`pg_dump --format=custom` per DB +
   `pg_dumpall --globals-only` for roles), **daily**, via
   `systemd` timer. Simple, restorable, debuggable.
2. **WAL archiving** to a local directory using built-in
   `archive_command` → enables ~15 min RPO and PITR on top of the daily
   base. This is the v1 "RPO ≈ 0" win without adopting a heavy tool.
3. **Storage volume**: nightly `rsync --link-dest` snapshot of
   `volumes/storage/` into the same backup tree (taken **after** the
   logical dump, with both moments logged so we can prove
   metadata/object ordering on restore).
4. **No pgBackRest / WAL-G in v1.** pgBackRest is in maintenance-only
   mode after April 2026; WAL-G shines when you have S3 — we don't, yet.
   Revisit in Phase 5 together with off-site (B2/Hetzner).
5. **Encryption at rest**: pipe every artifact through `age` with a
   public recipient stored on `jarvis`; private key kept off-host (1Password
   / paper). Defense in depth even though the data never leaves the box.
6. **Retention**: GFS-ish — 7 daily + 4 weekly + 3 monthly.
7. **Restore drill**: monthly automated drill restores latest dump into
   a throwaway `postgres` container, runs smoke queries, then destroys it.
   A backup that hasn't been restored doesn't exist.

Storage target for v1: `/var/backups/lumio/` on the same disk is
acceptable for alpha (the threat we're mitigating is *Postgres
corruption / fat-finger DROP*, not full disk loss — disk loss is the
Phase 5 off-site story). Mount a separate disk if/when one is added.

---

## 1. Backup approaches — comparison

| Approach | RPO | RTO | Setup cost | PITR | Notes |
|---|---|---|---|---|---|
| `pg_dumpall` (plain SQL) | 24h (last dump) | medium | trivial | no | Single file, easy to grep. Slow for big DBs. Drops sequences/ownership cleanly. |
| `pg_dump --format=custom` per DB + `pg_dumpall --globals-only` | 24h | low (parallel `pg_restore -j`) | trivial | no | **The sweet spot for alpha.** Custom format → selective restore, parallel restore, smaller files (built-in compression). |
| `pg_basebackup` + `archive_command` WAL archiving | ~15 min (archive_timeout) | medium | medium (config + cron + retention scripts) | yes | Physical backup; binary-compatible only with the exact same major version. Adds real PITR. |
| `pgBackRest` | ~minutes | low | high | yes | Best-in-class, but **archived April 2026** ([thebuild.com](https://thebuild.com/blog/2026/04/30/after-pgbackrest/)); v2.58.0 is final. Still works, but no future fixes. |
| `WAL-G` | ~minutes | low | medium | yes | Cloud-native (S3/GCS/Azure/SSH). Officially recommended by Supabase for self-hosted ([supabase.com](https://supabase.com/docs/guides/platform/backups)). Overkill until we have an S3 endpoint. |
| `Barman` | ~minutes | low | medium-high | yes | On-prem favorite; assumes a separate backup host. We have one node. |

### Why logical + WAL archiving, not pgBackRest / WAL-G, for v1

- **Single node, single major version, ~hobby scale.** The killer
  features of pgBackRest/WAL-G (parallel block-level diff, cloud
  retention windows, parallel restore from object storage) buy us
  little when the destination is `/var/backups/` on the same box.
- **pgBackRest is unmaintained going forward.** Adopting it in v1 only
  to migrate again in Phase 5 is wasted work.
- **WAL-G without S3 is awkward.** WAL-G can target a local
  filesystem, but its sweet spot is cloud object storage; better to
  introduce it together with B2/Hetzner in Phase 5.
- **Logical dumps survive PG major upgrades.** Physical backups don't.
  Across the next 18 months we will likely cross at least one PG major
  (Supabase tracks PG 15 → 16 → 17 → ...). Logical-first means we are
  never blocked.
- **Restorability beats elegance.** A 200 MB `*.dump` we can hand-pipe
  into `pg_restore` at 3am during an incident is worth more than a
  pgBackRest stanza nobody on the team has touched in 6 months.

### When to revisit (Phase 5 triggers)

- Lumio DB > 20 GB (logical dumps start hurting).
- We add Helix and need a unified backup story.
- Off-site target picked (B2 or Hetzner): WAL-G slots in naturally.
- We want RTO < 15 min: physical/PITR becomes worth the cost.

---

## 2. Supabase specifics — what to dump, what to skip

Supabase ships preinstalled extensions (`pgcrypto`, `pgjwt`,
`pg_graphql`, `pg_stat_statements`, `uuid-ossp`, `pg_net`, `vault`,
`pgsodium`, `pg_cron`, sometimes `pgvector`) and a fixed role hierarchy
(`supabase_admin`, `supabase_auth_admin`, `supabase_storage_admin`,
`authenticator`, `anon`, `authenticated`, `service_role`, plus
function-level grant chains).

### The gotchas (these will bite us if we just `pg_dump` blindly)

1. **`supabase_admin` ownership.** Many Supabase-managed objects are
   owned by `supabase_admin`. A raw `pg_dump` produces `ALTER ...
   OWNER TO "supabase_admin"` statements which fail on a fresh
   restore until that role exists with the right grants
   ([supascale.app](https://www.supascale.app/blog/supabase-self-hosted-backup-restore-guide)).
   → Always dump **roles first**, restore roles first.
2. **Internal schemas.** The official `supabase db dump` filter
   excludes the managed schemas (`auth`, `storage`,
   `_realtime`, `_analytics`, `_supavisor`, `pgsodium`,
   `graphql`, `graphql_public`, `extensions`, `vault`,
   `pg_*`, `net`, `cron`,
   `supabase_functions`) ([supabase.com docs](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)).
   For **self-hosted disaster recovery** we want the **opposite**: we
   want auth users, storage metadata, and migration history *included*
   — because we're restoring onto our own empty Postgres, not into a
   fresh Supabase platform project.
3. **Sequences & search_path.** Custom format dump handles these
   correctly; plain-SQL dumps require careful ordering on restore.
4. **`storage.buckets_vectors` / `storage.vector_indexes`.** Should be
   excluded from the data dump to avoid double encryption on restore
   ([supabase.com](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)).
5. **`pgsodium` / `vault` secret keys.** If we ever enabled
   `pgsodium`, the server-side root key lives outside the DB (in
   `pgsodium_getkey()` config or the Vault file). Backing up Postgres
   alone is not enough — record the Vault key in the same encrypted
   bundle, or restoration will succeed but `vault.decrypted_secrets`
   will return nulls.
6. **`pg_cron` jobs.** Live in `cron.job`; included automatically as
   long as we don't exclude the `cron` schema. Note their
   `cluster`-scoped state may need fixups on restore (different DB OID).

### Concrete v1 dump set

Use a Postgres client whose major version matches the server (run from
inside the same `supabase/postgres` image to avoid version skew).
Connect as the superuser configured for the cluster (`postgres` in
the official compose, owner of `supabase_admin`):

```bash
# 1) Roles + tablespaces (no DB data)
pg_dumpall \
  --host=127.0.0.1 --port=5432 --username=postgres \
  --globals-only --no-role-passwords \
  --file="${OUT}/globals.sql"
# (Use --no-role-passwords for safety; restore sets passwords from .env.)

# 2) Full custom-format dump of the postgres database
pg_dump \
  --host=127.0.0.1 --port=5432 --username=postgres \
  --dbname=postgres \
  --format=custom --compress=9 \
  --no-owner --no-privileges \
  --exclude-table-data='storage.buckets_vectors' \
  --exclude-table-data='storage.vector_indexes' \
  --file="${OUT}/lumio.dump"

# 3) Plain-SQL companion (grep-friendly, for forensic diffing)
pg_dump \
  --host=127.0.0.1 --port=5432 --username=postgres \
  --dbname=postgres \
  --format=plain --schema-only \
  --no-owner --no-privileges \
  --file="${OUT}/lumio.schema.sql"
```

Notes:

- `--no-owner --no-privileges` keeps the dump portable across
  installations; we re-apply GRANTs from `globals.sql` + the
  Supabase init scripts at restore time.
- We deliberately do **not** use `supabase db dump`. That tool is
  for migrating *application schema* between Supabase projects and
  strips exactly the schemas we need for DR ([supabase docs](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)).
- The `*.schema.sql` plain text companion is small (< 5 MB) and
  invaluable: it gives us a diffable record of schema drift between
  daily backups, useful for catching unexpected schema changes.

### Restore order (documented in `RESTORE.md`, to be produced in execute phase)

1. Bring up a clean `supabase/postgres` container (matching minor
   version!).
2. `psql -f globals.sql` (creates roles, grants).
3. `pg_restore --no-owner --no-privileges -d postgres -j 4 lumio.dump`.
4. Re-run Supabase init scripts (`/docker-entrypoint-initdb.d/`) if
   any of the managed schemas need bootstrapping (auth.users triggers
   on `auth.identities` etc.).
5. Restart the rest of the Supabase stack pointing at the restored DB.
6. Smoke test: `select count(*) from auth.users; select count(*) from
   storage.objects; <one app-table query>`.

---

## 3. Storage backup — files vs. metadata

Supabase Storage on self-hosted = a Node service that writes objects
to `volumes/storage/` (bind mount in the compose) using a custom
directory layout. **The PostgreSQL `storage.objects` table holds the
metadata that maps logical paths → on-disk filenames**
([supabase.com docs](https://supabase.com/docs/guides/self-hosting/storage/config)).

This decoupling creates two consistency hazards:

- **Orphan rows**: `storage.objects` has a row, file missing on disk
  → app shows broken downloads.
- **Orphan files**: file on disk, no row → wasted space, but harmless.

The asymmetry tells us the ordering: **back up the files first, then
the DB**. If a write happens between the two steps it produces an
orphan file (harmless) rather than an orphan row (broken).

### Don't try to copy files into another Supabase install raw

Per the official S3 migration guide, directly placing files in
`volumes/storage/` of another instance won't work — Storage uses an
internal layout and metadata expectations
([supabase.com](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3)).
That's fine for our case (we restore back onto the same Storage
service, same layout). For cross-instance moves we'd use the S3
protocol endpoint with `rclone`, **but that's a migration tool, not a
backup tool** — and it's pinned to `rclone` ≤ v1.67 because newer
versions adopt AWS SDK v2
([github discussion #22200](https://github.com/orgs/supabase/discussions/22200)).

### v1 storage backup pattern

```bash
# Step 1: snapshot storage files (fast, file-level)
rsync -a --delete \
  --link-dest="${BACKUP_ROOT}/storage/latest/" \
  /home/toto/lumio/volumes/storage/ \
  "${BACKUP_ROOT}/storage/${TS}/"
ln -sfn "${BACKUP_ROOT}/storage/${TS}" "${BACKUP_ROOT}/storage/latest"

# Step 2: dump Postgres (commands from §2)

# Step 3: pack both into the encrypted bundle (§6)
```

`rsync --link-dest` gives near-instant snapshotting via hardlinks
(only changed files cost disk). For a few-user alpha this is
essentially free.

For Phase 5 we will likely switch to **`restic`** for the storage
side — it dedupes across snapshots and encrypts natively, and we can
point it at B2 later. Out of scope for v1.

---

## 4. Cron / systemd + retention + storage location

### systemd timer (preferred over cron)

`systemd` units give us logs in `journalctl`, `OnFailure=` hooks for
alerting, and `Persistent=true` to recover missed runs after a host
reboot.

`/etc/systemd/system/lumio-backup.service`:

```ini
[Unit]
Description=Lumio Supabase nightly backup
Wants=docker.service
After=docker.service

[Service]
Type=oneshot
User=root
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
ExecStart=/usr/local/sbin/lumio-backup.sh
StandardOutput=journal
StandardError=journal
OnFailure=lumio-backup-failed@%n.service
```

`/etc/systemd/system/lumio-backup.timer`:

```ini
[Unit]
Description=Daily Lumio backup at 03:17

[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=600
Persistent=true
Unit=lumio-backup.service

[Install]
WantedBy=timers.target
```

The 3:17 + `RandomizedDelaySec=600` jitters runs to avoid synchronized
load (matters more once we have Helix too).

### Retention (GFS — Grandfather/Father/Son)

- **Daily**: keep the last 7. Rotates at every run.
- **Weekly**: promote Sunday's run; keep 4.
- **Monthly**: promote the 1st of the month; keep 3.

Total worst case: 14 generations. Implement with a shell script (a
`find ... -mtime +N -delete` against the daily dir, plus `cp -al`
hardlinks into `weekly/` / `monthly/` on the appropriate days) — see
[medium.com on retention](https://medium.com/@ngza5tqf/postgresql-backup-retention-policies-how-to-set-up-backup-retention-policies-020b10749367)
for the standard pattern.

### Where to store on `jarvis`

- v1 acceptable: `/var/backups/lumio/` on the same root disk.
  - Backups still survive: Postgres corruption, accidental `DROP`,
    bad migration, ransomware-via-app-bug (DB-level only),
    container nuke, distro upgrade gone wrong.
  - Backups do **not** survive: physical drive failure, host theft,
    full-disk encryption keystore loss.
  - That last bucket is exactly what off-site (Phase 5) addresses,
    so deferring it is consistent with the roadmap.
- v1 better, if a second disk is available: mount it at
  `/srv/backups/` (separate filesystem, separate fstab entry,
  `nofail` so a missing disk doesn't block boot). One extra `mount`
  call is worth the protection against a single bad sector hitting
  both live data and backups.
- **Permissions**: `chmod 0700` on the backup root, owned by a
  dedicated `backup` user. No reason for application processes to
  see backup blobs.

---

## 5. Restore drill — the only valid backup is a restored one

Lesson restated by every backup post-mortem ever
([pgdash.io](https://pgdash.io/blog/testing-postgres-backups.html),
[oneuptime.com](https://oneuptime.com/blog/post/2026-01-21-postgresql-backup-testing/view)).

### Levels we care about for v1

| Level | Check | v1? |
|---|---|---|
| 1 | File exists & size > N MB | yes — at end of each backup run |
| 2 | Integrity (`pg_restore --list` parses) | yes — at end of each run |
| 3 | Restore schema to throwaway DB | yes — monthly drill |
| 4 | Restore full data + run smoke queries | yes — monthly drill |
| 5 | App-level: spin Supabase services pointing at restored DB | quarterly (manual) |

### Monthly drill pattern (automated)

```bash
# /usr/local/sbin/lumio-restore-drill.sh (sketch)
set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
LATEST="${BACKUP_ROOT}/daily/latest"
WORK=$(mktemp -d)

# 1. Decrypt latest dump to scratch space
age -d -i /root/.age/jarvis.key \
  "${LATEST}/lumio.dump.age" > "${WORK}/lumio.dump"

# 2. Spin a disposable Postgres
docker run -d --rm --name pg-drill-${TS} \
  -e POSTGRES_PASSWORD=drill \
  -v "${WORK}:/restore:ro" \
  supabase/postgres:<pinned-version>

# 3. Wait for ready, replay globals, restore dump
docker exec pg-drill-${TS} bash -c '
  until pg_isready -U postgres; do sleep 1; done
  psql -U postgres -f /restore/globals.sql || true
  pg_restore --no-owner --no-privileges \
    -U postgres -d postgres -j 2 /restore/lumio.dump
'

# 4. Smoke queries — pick a row count we expect to be > 0
docker exec pg-drill-${TS} psql -U postgres -tAc \
  "select count(*) from auth.users" | grep -E '^[1-9]'
docker exec pg-drill-${TS} psql -U postgres -tAc \
  "select count(*) from storage.objects" | grep -E '^[0-9]'
# Add 1–2 application-table assertions here.

# 5. Verify against checksum recorded at backup time
sha256sum -c "${LATEST}/lumio.dump.sha256"

# 6. Tear down + report
docker stop pg-drill-${TS}
echo "drill ${TS} PASS" | systemd-cat -t lumio-drill
```

Drive this script from a second `systemd` timer
(`lumio-restore-drill.timer`, `OnCalendar=monthly`).
Wire `OnFailure=` to whatever alerting we choose in Phase 2 (e.g. a
ntfy / Gotify push).

**Storage drill**: occasionally restore one snapshot of
`volumes/storage/` to a scratch path and verify file count matches
`select count(*) from storage.objects` from the same backup window.
A discrepancy > a few percent is a red flag.

---

## 6. Encryption at rest

Even though backups stay on-host in v1, **encrypt them**. Reasons:

- The disk isn't FDE'd by default on a desktop Ubuntu install
  (worth checking on `jarvis` — if LUKS is on, this is *additional*
  defense in depth; if not, it's *the* defense).
- Phase 5 is going to ship these blobs off-host. If they're encrypted
  from day one, off-site is a `rclone copy` away — no retroactive
  re-encryption pass.
- If the host is ever sold / decommissioned / stolen, a bad actor
  finding `lumio.dump` shouldn't be a P0.

### age, not gpg

`age` (by Filippo Valsorda) is the modern simple choice in 2025/26
([blog.filippo.io / hsiao.dev](https://luke.hsiao.dev/blog/gpg-to-age/),
[fr0stb1rd.gitlab.io](https://fr0stb1rd.gitlab.io/posts/a-modern-and-simple-alternative-to-gpg-age-and-its-cryptographic-engineering/)):

- Two commands (`age`, `age-keygen`), no daemon, no keyring DB.
- Modern primitives (X25519 + ChaCha20-Poly1305 + scrypt for
  passphrase mode).
- Public keys are 62-char strings, identities are single text files —
  trivial to put one on `jarvis` and the matching secret in 1Password.
- Streaming-friendly: works as a pipe stage, no temp file needed.

`gpg` remains acceptable; the only reason to pick it would be if we
*also* need detached signatures or smartcard integration (we don't).

### Recipient/identity layout

- `/etc/lumio/backup-recipients.txt` — one or more `age` public keys.
  - Primary: a recipient whose secret lives in 1Password (`age-keygen`
    output, never touches `jarvis`).
  - Optional secondary: a paper-printed key in a fireproof box.
- We **encrypt to recipients**, not with a passphrase. That way
  decrypting requires the key, not memory of a string.

### Pipeline

```bash
# Encrypt-in-place at the end of the backup script
for f in globals.sql lumio.dump lumio.schema.sql; do
  age -R /etc/lumio/backup-recipients.txt \
      -o "${OUT}/${f}.age" \
      "${OUT}/${f}"
  shred -u "${OUT}/${f}"            # remove plaintext
done

# Storage bundle (one tar per snapshot, encrypted on the fly)
tar -C "${BACKUP_ROOT}/storage" -cf - "${TS}/" \
  | age -R /etc/lumio/backup-recipients.txt \
        -o "${OUT}/storage-${TS}.tar.age"

# Manifest + checksums (kept plaintext for verifiability)
( cd "${OUT}" && sha256sum *.age > MANIFEST.sha256 )
```

The drill script (§5) reverses this with `age -d -i <identity>`.

**Trade-off note**: encrypting the daily dump means a small dump
(~100 MB) becomes opaque to `diff`. We keep the `lumio.schema.sql.age`
companion specifically so that *if* we want to compare schemas
across days, we decrypt two small files (~5 MB each) and diff them —
without needing to decrypt the full data dump.

---

## Outstanding decisions (record in PROJECT.md before execute phase)

1. **WAL archiving on/off in v1?** Recommendation: **on**, with a
   conservative `archive_timeout=900` (15 min) and a local archive
   dir. Cheap to add, gives us PITR without WAL-G/pgBackRest.
   Push-back acceptable if we want to keep v1 strictly logical and
   defer all PITR to Phase 5.
2. **Second physical disk for `/srv/backups/`?** If yes → mount it.
   If no → `/var/backups/lumio/` is acceptable for alpha, document
   the limitation.
3. **age recipient(s)**: confirm 1Password as the secret store; mint
   a paper backup of the identity at first run.
4. **Alert sink for `OnFailure=`**: ntfy / Gotify / email / something
   else? (Likely Phase 2 territory; for v1 even `journalctl` + a
   weekly human eyeball check is acceptable given "few users".)
5. **PG version pin**: the drill image tag must equal the live
   container tag. Bake the version into the backup manifest so the
   drill picks it up automatically.

---

## Sources

- [Supabase Database Backups (official docs)](https://supabase.com/docs/guides/platform/backups) — WAL-G as the recommended self-hosted tool, with explicit setup/resource caveats.
- [Supabase: Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) — exact `supabase db dump` commands for roles/schema/data, and the `storage.buckets_vectors` / `storage.vector_indexes` exclusions.
- [Supabase GH Discussion #37748 — Recommended procedure for full backup and restore of self-hosted (unanswered, but maintainer guidance on volumes)](https://github.com/orgs/supabase/discussions/37748).
- [Supabase GH Discussion #22200 — Backups (database & storage) without supabase-cli](https://github.com/orgs/supabase/discussions/22200) — community pg_dump patterns, rclone version pin.
- [Supabase: Copy Storage Objects from Platform](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3) — why direct file copy into `volumes/storage/` doesn't work cross-instance.
- [Supabase: Storage self-hosting config](https://supabase.com/docs/guides/self-hosting/storage/config) — confirms default local filesystem backend.
- [Supabase: Self-Hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker) — volume layout (`volumes/db/data`, `volumes/storage`).
- [Supascale: Complete Guide to Supabase Self-Hosted Backup and Restore](https://www.supascale.app/blog/supabase-self-hosted-backup-restore-guide) — `supabase_admin` ownership gotcha and the `ALTER ... OWNER TO` workaround.
- [Medium: Backup your Supabase DB with pg_dump (Jeff P)](https://waxlyrical.medium.com/backup-your-supabase-db-with-pg-dump-14f08c40e456) — practical pg_dump invocation.
- [Christophe Pettus — "After pgBackRest, the build" (Apr 2026)](https://thebuild.com/blog/2026/04/30/after-pgbackrest/) — pgBackRest archived, alternatives compared.
- [Bytebase: Top Open-Source Postgres Backup Solutions in 2026](https://www.bytebase.com/blog/top-open-source-postgres-backup-solution/) — landscape.
- [DEV.to — Postgres backup tools comparison: Databasus, WAL-G, pgBackRest, Barman](https://dev.to/piteradyson/postgresql-backup-tools-comparison-databasus-wal-g-pgbackrest-and-barman-2kg).
- [DBLog — Enterprise Backup Tools Compared (pgBackRest vs Barman vs WAL-G)](https://dblog.co.kr/en/posts/postgresql-part-5).
- [Medium — Top 5 PostgreSQL backup tools in 2025](https://medium.com/@rostislavdugin/top-5-postgresql-backup-tools-in-2025-82da772c89e5).
- [pgDash — Automated Testing of PostgreSQL Backups](https://pgdash.io/blog/testing-postgres-backups.html).
- [OneUptime — How to Test PostgreSQL Backup Restoration](https://oneuptime.com/blog/post/2026-01-21-postgresql-backup-testing/view).
- [DEV.to — PostgreSQL backup verification](https://dev.to/piteradyson/postgresql-backup-verification-how-to-test-and-validate-your-postgresql-backups-2al8).
- [PostgreSQL docs — `pg_verifybackup`](https://www.postgresql.org/docs/current/app-pgverifybackup.html).
- [PostgreSQL docs — `pg_dumpall`](https://www.postgresql.org/docs/current/app-pg-dumpall.html), [`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html).
- [Medium — PostgreSQL backup encryption (Nazar Egorov)](https://medium.com/@ngza5tqf/postgresql-backup-encryption-how-to-encrypt-your-postgresql-database-backups-448707297cf2).
- [Medium — PostgreSQL backup retention policies (Nazar Egorov)](https://medium.com/@ngza5tqf/postgresql-backup-retention-policies-how-to-set-up-backup-retention-policies-020b10749367).
- [Luke Hsiao — Switching from GPG to age](https://luke.hsiao.dev/blog/gpg-to-age/).
- [fr0stb1rd — A Modern and Simple Alternative to GPG: age](https://fr0stb1rd.gitlab.io/posts/a-modern-and-simple-alternative-to-gpg-age-and-its-cryptographic-engineering/).
- [DEV.to — A Production-Ready Linux Backup Pipeline with restic + systemd timers](https://dev.to/lyraalishaikh/a-production-ready-linux-backup-pipeline-with-restic-systemd-timers-5hmo) — systemd timer pattern, retention idioms.
