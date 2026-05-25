# PITFALLS — Sanitizing a personal infra repo before going public

Scoped research note for Phase 1 of `self-hosting` (host: `jarvis`). The repo
will be published as a **narrative/reference** project (README + architecture
+ decision log + screenshots), not as a reusable library. Security wins ties.

Sources are cited inline as `[n]` and listed at the bottom.

---

## 1. Secret / leak detection — tool choice for v1

### TL;DR recommendation

- **Pre-push hook + CI gate**: `gitleaks` v8.x.
- **Periodic deep audit** (every milestone, plus once before going public):
  `trufflehog filesystem` + `trufflehog git --only-verified` against full
  history.
- Skip `git-secrets` — it's the original AWS Labs tool, regex-only,
  unmaintained pace, and superseded by gitleaks. [1][2]

Rationale: gitleaks is the fastest of the three (sub-second on a small
diff), uses TOML rules that are easy to extend with custom patterns, and
has a first-class `pre-commit-hooks.yaml` plus a maintained GitHub Action
(`gitleaks/gitleaks-action@v2`). TruffleHog's distinguishing feature is
**credential verification** (it tries to authenticate against the live
service), which is overkill for the commit hot path but extremely useful
for the one-shot "is this repo safe to publish?" check. [1][3][6]

### Install pattern (v1, minimal)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2          # pin, do not float
    hooks:
      - id: gitleaks
```

```yaml
# .github/workflows/gitleaks.yml
name: gitleaks
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }       # full history for diff scan
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITLEAKS_CONFIG: .gitleaks.toml
```

Pre-push (not pre-commit) is preferable here: pre-commit fires per
file-stage and slows the inner loop; pre-push fires once before the
network round-trip and still blocks before anything leaves the laptop.
Install via `pre-commit install --hook-type pre-push`. [7]

### Custom rules to add to `.gitleaks.toml`

Gitleaks's default ruleset covers ~150 vendor patterns (AWS, GitHub,
Slack, Stripe, Anthropic `sk-ant-…`, JWT-ish strings) but **does not**
catch the identifying assets in this repo. Add the following. All
patterns are Go RE2 syntax. [4][5]

```toml
title = "self-hosting custom rules"
[extend]
useDefault = true              # keep all 150 built-in rules

# ─── Cloudflare Tunnel UUID (and any UUID v4 cred file) ───
[[rules]]
id = "cf-tunnel-uuid"
description = "Cloudflare Tunnel UUID (or any UUID v4 used as credential filename)"
regex = '''\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'''
tags = ["cloudflare", "tunnel", "uuid"]
[rules.allowlist]
description = "Doc placeholders only"
regexes = [
  '''00000000-0000-0000-0000-000000000000''',
  '''xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx''',
]

# ─── Public IPv4 (allow RFC1918 / loopback / CGNAT / TEST-NET) ───
[[rules]]
id = "public-ipv4"
description = "Public IPv4 address — redact to 1.2.3.4 / example.com"
regex = '''\b(?:\d{1,3}\.){3}\d{1,3}\b'''
[rules.allowlist]
description = "Private + reserved ranges are fine in docs"
regexes = [
  '''\b10\.(?:\d{1,3}\.){2}\d{1,3}\b''',                    # RFC1918
  '''\b172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.){1}\d{1,3}\b''',
  '''\b192\.168\.\d{1,3}\.\d{1,3}\b''',
  '''\b127\.\d{1,3}\.\d{1,3}\.\d{1,3}\b''',                 # loopback
  '''\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b''', # CGNAT
  '''\b169\.254\.\d{1,3}\.\d{1,3}\b''',                     # link-local
  '''\b(192\.0\.2|198\.51\.100|203\.0\.113)\.\d{1,3}\b''',  # TEST-NET-1/2/3
  '''\b1\.2\.3\.4\b''',                                     # convention
  '''\b0\.0\.0\.0\b''',
]

# ─── Personal email ───
[[rules]]
id = "personal-email"
description = "Personal/work email leaked in docs or commits"
regex = '''(?i)\b[a-z0-9._%+-]+@(?:gmail|outlook|hotmail|yahoo|proton(?:mail)?|icloud|me|fastmail)\.[a-z]{2,}\b'''
[rules.allowlist]
regexes = [
  '''you@example\.com''',
  '''user@example\.com''',
  '''noreply@.*''',
]

# ─── JWT (built-in rule misses some shapes — see issue #1208) ───
[[rules]]
id = "jwt-loose"
description = "JWT (loose: 3 base64url segments, ≥20 chars header)"
regex = '''\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'''
tags = ["jwt"]

# ─── Cert / credentials filesystem paths ───
[[rules]]
id = "cred-paths"
description = "Filesystem path that points to a real cert/credentials file"
regex = '''(?i)(?:/etc/cloudflared|/home/[^/\s]+/\.cloudflared|/etc/letsencrypt/live)/[^\s'"]+\.(?:json|pem|key|crt)'''

# ─── Cloudflare Origin CA Key (built-in but worth pinning) ───
[[rules]]
id = "cf-origin-ca"
regex = '''\bv1\.0-[a-f0-9]{24}-[a-f0-9]{146}\b'''

# ─── Personal hostname/subdomain leak (project-specific) ───
[[rules]]
id = "private-fqdn"
description = "Real subdomain of toto-castaldi.com — should be example.com in public docs"
regex = '''\b[a-z0-9-]+\.toto-castaldi\.com\b'''
```

Run `gitleaks detect --config .gitleaks.toml --no-banner --redact` once
to validate the rules don't false-positive on legitimate docs (the
allowlists above are tuned for that). [4][8]

---

## 2. History rewrite — keep, squash, or nuke?

### Current state of this repo

```
615feb4 rifare
7d247ba pre push
4c1156f docs: create roadmap (5 phases)
396f37a docs: define v1 requirements
fbcd5bb docs: add inline research summary (no agents installed)
```

Five commits, all docs, no code, all authored locally, never pushed
publicly. The commit messages "rifare" and "pre push" are throwaway —
**history has zero narrative value** here.

### Decision matrix

| Approach | When it fits | Cost | Verdict for this repo |
|---|---|---|---|
| **Squash to a single "initial public commit"** | Repo small, history is noise, you want a clean public face | Trivial: `git checkout --orphan public && git commit -m "Initial public release"` | **RECOMMENDED for v1.** Cleanest. Sanitization is verifiable by reading one tree. |
| **`git filter-repo`** | History matters AND you only need to strip specific files/strings | Medium: requires fresh clone, force-push, contributors must re-clone | Overkill — there's no narrative to preserve. |
| **BFG Repo-Cleaner** | Large repo with big-blob or password-file removal | Low (10–720× faster than `filter-branch`) but BFG **can't differentiate paths** (`README.md` at root vs. in subdir) and **won't touch the current HEAD** by default | Wrong shape: we don't have big blobs, we have leaked strings in HEAD itself. |
| **Keep history as-is** | History is already clean | Free | Not safe: "pre push" commit may contain pre-sanitization README. |

[9][10][11]

### Concrete plan

1. On a **fresh clone** (not the working copy), create an orphan branch:
   ```bash
   git checkout --orphan public-v1
   git add -A
   git commit -m "Initial public release: jarvis self-hosting narrative"
   ```
2. Run gitleaks against the working tree (`gitleaks detect --no-git`).
3. Run `trufflehog filesystem . --only-verified` as a second opinion.
4. Replace `main` with `public-v1` and push to a **new** GitHub repo
   (do not force-push over an existing public history — even if there
   isn't one, building the muscle memory is cheap).
5. Keep the old `main` with full history in a private mirror or local
   bundle (`git bundle create ../self-hosting-private.bundle --all`)
   for your own reference.

If at some future point you *do* want to preserve history but strip a
specific committed file, prefer `git filter-repo` over BFG — it's the
upstream-recommended successor to `filter-branch`, handles full paths
correctly, and applies filters to HEAD by default. [9][10]

---

## 3. `.gitignore` additions

The current `.gitignore` covers editor + build artifacts + `.env*` but
misses every infrastructure-specific file in this project. Append:

```gitignore
# ── cloudflared ──
*.cloudflared.json
**/cloudflared/*.json
**/cloudflared/cert.pem
**/cloudflared/config.yml          # contains tunnel UUID
.cloudflared/

# ── Tailscale ──
tailscale.state
/var/lib/tailscale/                # never commit, but defensive
*.tailscale.key

# ── Docker compose state / volumes ──
**/volumes/
**/data/
**/postgres-data/
**/storage-data/
docker-compose.override.yml        # local-only overrides

# ── Supabase ──
.env.local
.env.production
supabase/.branches/
supabase/.temp/

# ── SSH / TLS / GPG ──
id_rsa
id_ed25519
*.pem
*.key
*.crt
*.pfx
*.p12
authorized_keys
known_hosts
*.gpg
*.asc

# ── Secrets-ish dotfiles ──
.netrc
.pgpass
.aws/
.kube/config

# ── systemd drop-ins with secrets ──
*-override.conf

# ── editor scratch ──
*.bak
*.orig
```

Use `git check-ignore -v <path>` to verify a file is actually ignored
before committing.

For the **template** that should be committed, ship `.env.example` with
all keys present but values blanked or set to `CHANGE_ME`. The existing
`!.env.example` line already permits this.

---

## 4. README narrative patterns — reference homelab repos

### 3 concrete examples to study

1. **`khuedoan/homelab`** — declarative GitOps homelab, ~10k stars. Strong
   patterns: single-paragraph hook at top, Mermaid architecture diagram,
   "Features", "Quick start", "Detailed documentation" hierarchy, screenshot
   gallery at bottom. Anonymizes by using `example.com` everywhere. [12]
2. **`lento234/homelab`** — personal Nix-based homelab, smaller scale. Good
   model for *narrative* (not reusable): describes the **why** (learning,
   self-hosting), shows the hardware, links to per-service folders. [12]
3. **`geerlingguy/*`** family (Ansible roles, Pi clusters) — Jeff Geerling
   pairs each repo with a blog post / video. The README is the abstract;
   the long-form lives on his blog. Good pattern for a **referenceable**
   project: README answers "what is this and why does it exist?", the
   commit log + linked posts answer "how was it built?". [12]

Also worth grepping for inspiration: `awesome-architecture-md` curates
~100 ARCHITECTURE.md files from real OSS projects. [13]

### Recommended README structure for `self-hosting`

```
# Title + one-line tagline + status badge
> 2–4 sentence "what & why" (also the GitHub repo description)

## Architecture
  - ASCII or Mermaid diagram (no real IPs / UUIDs)
  - Stack list table

## Decisions (decision log / ADR-lite)
  - Same table you already have in README.md §"Decisioni architetturali"
  - Each row: # | Decision | Rationale

## Security model
  - Threat model in 3 bullets
  - Public exposure surface (Cloudflare Tunnel only)
  - Admin surface (Tailscale + CF Access)
  - Secret storage approach

## Stack
  - Per-service short paragraph + link to subfolder

## Screenshots
  - Sanitized: blur real hostnames, redact tunnel UUIDs in Cloudflare UI

## Lessons learned
  - One section per surprise (Ubuntu 26.04 cloudflared repo, MagicDNS cache, …)

## Reuse
  - Explicit: "this is a personal narrative, not a reusable framework"
  - Link to khuedoan/homelab etc. for actual frameworks

## License
```

### Anonymization conventions (use everywhere in public docs)

| Real | Public placeholder |
|---|---|
| `toto-castaldi.com` | `example.com` |
| `lumio.toto-castaldi.com` | `app.example.com` |
| `toto.castaldi@gmail.com` | `you@example.com` |
| `6b09204a-58fd-4632-b699-15b1b9eb24a0` | `00000000-0000-0000-0000-000000000000` |
| `146.190.232.60` (DigitalOcean) | `203.0.113.10` (TEST-NET-3, RFC5737) |
| `192.168.0.72` | keep — RFC1918 is fine |
| `100.x.x.x` Tailscale IPs | keep `100.64.0.0/10` shape, randomize last 2 octets |
| Username `toto` | `user` or keep — low sensitivity, but be aware it's the literal Linux UID 1000 |
| Hostname `jarvis` | keep — it's the project's identity |

RFC5737 reserves `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`
specifically for documentation; prefer these over invented IPs.

### Screenshot hygiene

Before pasting any screenshot:
- Crop or blur: top-bar account email, real hostnames in the URL bar,
  Tailscale device names (often include real laptop hostnames),
  Cloudflare Tunnel UUID in dashboard sidebars, monitoring graphs that
  embed public IPs in labels.
- Re-encode: PNG metadata can carry username/path of the source machine.
  `exiftool -all= screenshot.png` strips it. macOS `screencapture` and
  GNOME Screenshot both write EXIF/text chunks by default.
- If the screenshot is of a terminal: also check the prompt
  (`user@hostname:~/path$` is a triple leak).

---

## 5. LICENSE choice for a narrative repo

### Options

| License | What it grants | When to pick |
|---|---|---|
| **No LICENSE file** | Default copyright = all rights reserved. Others can view/fork (GitHub ToS) but not legally reuse. [14][15] | You want the code present *as evidence/narrative* but explicitly **not** as a kit others should run. |
| **CC BY 4.0** | Free use with attribution, for **non-code** content | Best fit for prose, diagrams, screenshots — but ambiguous for code. |
| **MIT** | Anyone can use code, must keep copyright notice | If you don't mind people lifting snippets; minimal obligations on them. |
| **Apache-2.0** | MIT + explicit patent grant | Larger codebases; overkill here. |
| **CC0 / Unlicense** | Public domain dedication | Maximum permissiveness; Unlicense is legally weak in some jurisdictions. |

### Recommendation for this repo

**Dual approach** (matches what e.g. Julia Evans does on her notes repos):

- Add a `LICENSE` file = **MIT** for the code/snippets/compose files.
  The bar to writing a `docker-compose.yml` is low; gatekeeping it
  is performative.
- Add a `LICENSE-docs` file (or a note in the README) = **CC BY 4.0**
  for the prose, diagrams, screenshots, and decision log.
- Explicitly state in the README:
  > "This is a narrative of how I run my homelab, not a reusable
  > framework. PRs that improve clarity welcome; please don't expect
  > this to be a supported project."

If you want maximum simplicity and you don't actually want anyone
reusing anything: **omit the LICENSE file**. The repo is then under
default copyright, which is legally clear (all rights reserved) even
though it makes the repo not "open source" in the OSI sense. [14][15]

---

## 6. Common mistakes when publishing infra repos

A checklist distilled from public post-mortems and security research,
ordered by how often they actually happen.

1. **Committing `.env.local` / `.env.production`** — `.env*` ignored, but
   `.env.local` often slips through if `.gitignore` uses `.env`
   without the wildcard. The current `.gitignore` already uses `.env.*`
   with a `!.env.example` exception — good, but double-check before
   the first public push: `git ls-files | grep -E '\.env'`.

2. **Screenshot of a dashboard with real values visible** — top right
   corner email, sidebar tunnel UUID, Grafana panel titles containing
   the public IP. Use a checklist (above) before each screenshot.

3. **Tailscale device names** — `tailscale status` output committed
   verbatim leaks every device hostname and the user's tailnet name
   (`tail-xxxxx.ts.net`). Anonymize device names in any pasted output.

4. **Hardcoded UID/GID in compose files** — `user: "1000:1000"` reveals
   you're a single-user box and gives an attacker a useful hint for
   any local-FS exploit. Prefer named users or `${UID}:${GID}` env vars.

5. **Cloudflared credentials JSON in `/home/user/.cloudflared/`** — easy
   to accidentally include if you `cp -r ~/.cloudflared ./jarvis/`
   for backup. The custom gitleaks rules above (`cf-tunnel-uuid` +
   `cred-paths`) catch this.

6. **Shell history in commits** — pasting `history | tail -50` into
   a README is a known pattern (your current README does it — see the
   `## docker` and `## cloudfare` sections with numbered command
   history). These often contain `curl … | bash`, tokens passed on
   the command line, and absolute paths to credential files.

7. **Cert files in `volumes/`** — `docker compose up` populates
   bind-mounted volumes with state including Postgres data dirs,
   storage objects, and any cert material mounted in. The `**/volumes/`
   gitignore rule above is essential.

8. **`config.yml` for cloudflared committed verbatim** — contains the
   tunnel UUID and the credentials file path. Either commit a
   `config.example.yml` with placeholders, or scrub before commit.

9. **systemd unit files with `Environment=` containing tokens** —
   commit only the `.service` *template*; keep `Environment=` in a
   drop-in under `/etc/systemd/system/foo.service.d/override.conf`
   that's gitignored.

10. **Certificate Transparency reveals the rest** — even if you scrub
    subdomains from the repo, anyone can run the same Certspotter
    query you used (`api.certspotter.com/v1/issuances?domain=...`)
    and recover the full subdomain list. Accept that the *list of
    subdomains* is not actually a secret; focus on protecting tunnel
    IDs, credentials, IPs, and emails.

11. **GitHub Pages / Wiki leaking what the main branch hid** — if you
    enable Pages from `/docs`, anything in there is served even if
    you later remove it from `main`. Disable Pages until Phase 1 is
    complete.

12. **Force-pushing the sanitized branch over leaked history** — the
    old commits remain in GitHub's reflog/forks for ~90 days and
    are reachable via direct SHA. If a secret was *ever* pushed
    publicly: **rotate the secret**, do not just rewrite history.
    [9][10]

13. **Dependency lockfiles with private registry URLs** — `npm`'s
    `.npmrc`, `pip`'s `pip.conf`, `cargo`'s `config.toml` can contain
    `//npm.pkg.github.com/:_authToken=...`. None apply to this repo
    today but add to the checklist before any Phase 2 code lands.

### Pre-publish checklist (run in order)

```bash
# 0. Backup full history locally
git bundle create ~/self-hosting-private.bundle --all

# 1. Inventory potentially sensitive strings
grep -rE '(toto-castaldi\.com|6b09204a|192\.168\.|146\.190|toto\.castaldi)' \
  --exclude-dir=.git .

# 2. Run gitleaks with custom config against working tree
gitleaks detect --no-git --config .gitleaks.toml --redact -v

# 3. Run trufflehog filesystem scan
trufflehog filesystem . --only-verified

# 4. Strip metadata from any screenshots
find . -name '*.png' -o -name '*.jpg' | xargs exiftool -all=

# 5. Verify .gitignore is actually catching the right files
git status --ignored

# 6. Create the orphan public branch (see §2)
git checkout --orphan public-v1 && git add -A && git commit -m "Initial public release"

# 7. Push to a NEW repo (not over the old one)
git remote add public git@github.com:toto-castaldi/self-hosting.git
git push public public-v1:main
```

Only after the pre-publish checklist passes clean: flip the GitHub
repo to public.

---

## Sources

- [1] [Gitleaks vs TruffleHog 2026: Secret Scanner Benchmarks — AppSecSanta](https://appsecsanta.com/secret-scanning-tools/gitleaks-vs-trufflehog)
- [2] [detect-secrets vs Gitleaks vs TruffleHog vs GitGuardian (2026) — NomadX](https://devsecops.ae/secrets-scanners-comparison-2026/)
- [3] [TruffleHog vs. Gitleaks: A Detailed Comparison — Jit](https://www.jit.io/resources/appsec-tools/trufflehog-vs-gitleaks-a-detailed-comparison-of-secret-scanning-tools)
- [4] [gitleaks/config/gitleaks.toml — built-in ruleset](https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml)
- [5] [Detection rule id 'jwt' cannot detect jwt leaks — gitleaks#1208](https://github.com/gitleaks/gitleaks/issues/1208)
- [6] [Gitleaks: Open-Source Secret Scanning for Git Repos in 2026 — dev.to](https://dev.to/pickuma/gitleaks-open-source-secret-scanning-for-git-repos-in-2026-4ceb)
- [7] [Add a Local Gitleaks Pre-Commit Hook (No Frameworks) — d4b.dev](https://www.d4b.dev/blog/2026-02-01-gitleaks-pre-commit-hook/)
- [8] [Leveraging Custom GitLeaks TOML with Secret Magpie — Punk Security](https://punksecurity.co.uk/blog/secret_magpie_gitleaks_toml/)
- [9] [git-filter-repo: converting from BFG Repo-Cleaner](https://github.com/newren/git-filter-repo/blob/main/Documentation/converting-from-bfg-repo-cleaner.md)
- [10] [newren/git-filter-repo on GitHub](https://github.com/newren/git-filter-repo)
- [11] [BFG Repo-Cleaner project page](https://rtyley.github.io/bfg-repo-cleaner/)
- [12] [khuedoan/homelab](https://github.com/khuedoan/homelab), [lento234/homelab](https://github.com/lento234/homelab), [geerlingguy](https://github.com/geerlingguy)
- [13] [awesome-architecture-md — curated ARCHITECTURE.md files](https://github.com/noahbald/awesome-architecture-md)
- [14] [No License — choosealicense.com](https://choosealicense.com/no-permission/)
- [15] [Licensing a repository — GitHub Docs](https://docs.github.com/articles/licensing-a-repository)
