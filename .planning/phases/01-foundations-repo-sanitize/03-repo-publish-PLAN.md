---
phase: 01-foundations-repo-sanitize
plan: 03
type: execute
wave: 3
depends_on: ["01-02"]
files_modified:
  - .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
  - .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt
  - .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt
autonomous: false
requirements: [REPO-04, REPO-06, REPO-07]

must_haves:
  truths:
    - "Pre-publish checklist eseguita end-to-end e committata come evidence in `.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md`"
    - "`gitleaks detect` su history completa (pre-squash) eseguito e report committato (atteso: alcuni finding storici sui commit 'rifare'/'pre push' pre-sanitize — questo è il razionale della squash)"
    - "`trufflehog filesystem . --only-verified` eseguito sul working tree, 0 verified secret trovati"
    - "`exiftool -all=` runnato su tutti i .png/.jpg presenti nel repo (se ce ne sono — in questo repo solo docs MD, ma controllo formale eseguito)"
    - "Backup full history del repo privato originale in `~/self-hosting-private.bundle` PRIMA della squash (recovery path)"
    - "Squash: `git checkout --orphan public-v1` → `git add -A` → single commit 'Initial public release of jarvis self-hosting v1' → reflog locale verificato"
    - "Force-push come `main` del remote esistente (privato), eseguito con `git push origin public-v1:main --force-with-lease`"
    - "Repo visibility flippata da `private` a `public` via `gh repo edit --visibility public --accept-visibility-change-consequences`"
    - "Smoke verify post-publish: clone fresh in tmp dir, `gitleaks detect` esce 0 finding sulla history post-squash, README rendering verificato su github.com/<user>/<repo>"
  artifacts:
    - path: ".planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md"
      provides: "Checklist eseguita step-by-step con timestamp, output sintetico di ogni check, decisione GO/NO-GO finale"
      contains: "0. Backup bundle, 1. Grep inventario leak, 2. Gitleaks history scan, 3. Trufflehog verified, 4. Exiftool screenshots, 5. .gitignore verify, 6. Squash, 7. Force-push, 8. Flip visibility, 9. Smoke clone"
    - path: ".planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt"
      provides: "Output di `gitleaks detect --config .gitleaks.toml --redact -v` su tutta la history pre-squash (evidence dei finding storici che giustificano la scelta orphan branch)"
    - path: ".planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt"
      provides: "Output di `trufflehog filesystem . --only-verified --json` (atteso: zero verified)"
  key_links:
    - from: "Squash orphan branch `public-v1`"
      to: "Remote `origin/main` post force-push"
      via: "`git push origin public-v1:main --force-with-lease`"
      pattern: "force-with-lease evita race se qualcun altro pushava in parallelo (sicurezza per single-dev: comunque safe perché repo privato non collaborato)"
    - from: "Pre-publish gitleaks scan"
      to: "Decisione GO/NO-GO flip visibility"
      via: "Se gitleaks history POST-squash trova qualcosa → NO-GO, fix prima di flippare"
      pattern: "checkpoint umano esplicito tra step 7 (push) e step 8 (flip visibility)"
    - from: "Reflog ~90gg post force-push (D-07 risk accepted)"
      to: "Documentazione del rischio in PRE-PUBLISH-CHECKLIST.md"
      via: "Sezione esplicita 'Risks accepted' con riferimento a CONTEXT.md D-07"
      pattern: "no mitigation tramite GitHub Support ticket; accept consapevole"
---

<objective>
Eseguire la **pre-publish checklist** (REPO-06), fare la **squash a orphan branch
`public-v1`** (REPO-04), force-push come `main` del remote esistente, flippare la
visibility del repo da private a public (REPO-07), e fare smoke verify post-publish.

Questo è il plan **publication-critical**: tutto ciò che sopravvive Plan 02 viene
esposto pubblicamente. La checklist è la safety net last-mile per cogliere residui
che Plan 02 potrebbe aver mancato (gitleaks su HISTORY pre-squash, non solo working
tree; trufflehog come second-opinion engine; exiftool per metadata binarie).

Tre output di evidence committati in `.planning/`:
1. `PRE-PUBLISH-CHECKLIST.md` — log eseguibile della checklist, con output sintetico per step e timestamp.
2. `gitleaks-history-report.txt` — gitleaks su full history (atteso: finding storici sui commit `rifare`/`pre push`).
3. `trufflehog-report.txt` — trufflehog verified-only (atteso: 0).

D-06: **flip visibility del repo esistente**, NON creare nuovo repo. Sequenza
importante: prima force-push, POI flip private→public. Se si flippa prima e si
force-pusha dopo, c'è una finestra in cui la old history è pubblicamente accessibile.

D-07: rischio reflog ~90gg post force-push **accettato esplicitamente**; nessuna
mitigation via GitHub Support ticket in scope.

Output: 3 file evidence + un repo `jarvis self-hosting` pubblico su GitHub con README
sanitizzato, history pulita (orphan single commit), LICENSE MIT, gitleaks GH Action
verde sulla nuova history.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md
@.planning/research/PITFALLS.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 3.1: Eseguire pre-publish checklist (steps 0-5: backup, scan, audit)</name>
  <files>.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md, .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt, .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt</files>
  <read_first>
    - .planning/research/PITFALLS.md §6 "Pre-publish checklist (run in order)" — comandi esatti da eseguire
    - .planning/research/PITFALLS.md §6 "Common mistakes when publishing infra repos" — lista 13 anti-pattern da scorrere
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md §D-07 (rischio reflog accettato, pre-publish DEVE includere gitleaks su history come safety net)
    - .gitleaks.toml (config da Plan 02 — usato per scan history)
    - .planning/phases/01-foundations-repo-sanitize/01-02-SUMMARY.md (output di Plan 02 — verifica che gitleaks working tree era già clean)
  </read_first>
  <action>
Creare `.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md` come documento eseguito (ogni step ha: comando lanciato, output sintetico, timestamp, GO/NO-GO):

```markdown
# Pre-publish checklist — jarvis self-hosting v1

**Run by:** Antonio Castaldi
**Run at:** 2026-05-XX HH:MM:SS+02:00
**Repo state pre-checklist:** working tree clean post Plan 02 (commit SHA: <fill>)
**Checklist source:** .planning/research/PITFALLS.md §6
**Decision per CONTEXT.md D-07:** reflog ~90gg post-publish risk accepted, no GitHub Support ticket.

---

## Step 0 — Full history backup (recovery path)

**Cmd:**
\```bash
git bundle create ~/self-hosting-private.bundle --all
\```

**Output:** `Writing objects: 100% (NNN/NNN), done.` — atteso file ~XX KB.
**Verify:** `git bundle verify ~/self-hosting-private.bundle` → "is okay"
**Status:** [ ] OK

**Razionale:** la squash a orphan butta via la history visibile (Plan 03 Task 3.2);
il bundle resta sul laptop di Antonio come safety net se serve recuperare un
commit storico (es. messaggi GSD commit, decisioni). Il bundle NON va sul repo
public — vive solo localmente in `~/` (gitignored già dal pattern home).

## Step 1 — Inventario stringhe sensibili (grep manuale)

**Cmd:**
\```bash
grep -rE '(toto-castaldi\.com|6b09204a|192\.168\.0\.72|192\.168\.0\.137|146\.190|188\.166|152\.42\.138|toto\.castaldi|inspiron|remy\.ns|wanda\.ns)' \
  --exclude-dir=.git --exclude-dir=.planning .
\```

**Output atteso:** zero match (Plan 02 ha sanitizzato il working tree).
NOTA: escludiamo `.planning/` perché contiene `readme-placeholder-map.md` by design (allowlisted in `.gitleaks.toml`).
**Status:** [ ] PASS (0 match) / [ ] FAIL — se FAIL: investigare, fixare, ripetere checklist

## Step 2 — Gitleaks su HISTORY completa (pre-squash)

**Cmd:**
\```bash
gitleaks detect --config .gitleaks.toml --redact -v --no-banner \
  > .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt 2>&1 || true
\```

**Output atteso:** **alcuni finding storici** sui commit `rifare` (615feb4) e `pre push` (7d247ba) e commit pre-Plan 02 che contenevano README originale con leak. Questo è il razionale della squash: gli storici NON vanno mai sul remote public.

**Decisione:**
- Se i finding sono SOLO sui commit pre-squash (data < quando Plan 02 ha sanitizzato), allora **OK procedere alla squash** (la squash li butta via).
- Se i finding sono sui commit POST Plan 02 (significa che Plan 02 ha lasciato qualcosa, oppure la sanitizzazione non era completa), allora **STOP** — fix prima.

**Status:** [ ] OK (finding solo pre-squash, accettabile) / [ ] FAIL (finding post Plan 02)

## Step 3 — Trufflehog verified-only sul working tree

**Cmd:**
\```bash
trufflehog filesystem . --only-verified --no-update --json \
  > .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt 2>&1 || true
\```

**Output atteso:** vuoto o un JSON con `"DetectorName": ...` ma `"Verified": false` filtrati out → 0 verified.
**Razionale:** Trufflehog verified = ha tentato l'auth contro il servizio reale. Zero verified = nessun secret attivo. Diverso da gitleaks che è regex-only.

**Status:** [ ] OK (0 verified) / [ ] FAIL

**Setup note:** se `trufflehog` non è installato:
\```bash
# install one-shot via Homebrew, Go, o release binary:
curl -sSL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
trufflehog --version
\```

## Step 4 — Exiftool su asset binari (PNG/JPG)

**Cmd:**
\```bash
find . -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \
  | grep -v '\.git/' \
  | tee /tmp/binary-assets.txt

# Se l'output è vuoto: skip; altrimenti:
xargs -a /tmp/binary-assets.txt exiftool -all= -overwrite_original
\```

**Output atteso:** zero file matchati (questo repo è docs-only in v1, niente screenshot). Documentare comunque l'esecuzione.

**Status:** [ ] OK (0 file presenti, nessun metadata da strippare) / [ ] DONE (N file processati)

**Note future:** se in Phase 4 (Lumio cutover) si aggiungono screenshot Studio, eseguire exiftool prima di ogni commit.

## Step 5 — Verify .gitignore cattura i file giusti

**Cmd:**
\```bash
git status --ignored
\```

**Output atteso:** la sezione "Ignored files" mostra .gsd, .DS_Store, eventuali .env locali, `~/.cloudflared/` reference paths se esistono nel CWD. La sezione "Untracked" deve essere vuota o contenere solo file che vogliamo committare (i 3 evidence file di Plan 03).

**Status:** [ ] OK

## Decision: GO / NO-GO per squash + push

- [ ] Tutti gli step 0-5 sono OK / accettabili.
- [ ] Working tree gitleaks è clean (verificato in Plan 02 Task 2.3).
- [ ] Backup bundle creato e verificato.
- [ ] Rischio reflog accettato esplicitamente (D-07).

**GO:** procedere a Task 3.2 (squash + push).
**NO-GO:** stop, log issue, fix, ripeti checklist.

**Final decision:** [ ] GO / [ ] NO-GO (motivare)
```

Eseguire effettivamente gli step (run dei comandi documentati), inserire timestamp e exit code reali nelle sezioni. Salvare i 3 file di evidence (`PRE-PUBLISH-CHECKLIST.md`, `gitleaks-history-report.txt`, `trufflehog-report.txt`) prima di procedere alla task 3.2.

Se trufflehog non è installato e non si vuole installare in questo plan (è un Go binary, install è veloce ma è un'altra dipendenza), documentare come `[ ] SKIPPED — trufflehog non installato, gitleaks dual-engine sufficient per v1` con razionale esplicito. **MA**: la checklist di PITFALLS.md lo elenca come step richiesto, quindi preferenza forte è installare e runnare. Decision Claude: install trufflehog (binary one-line install, no system pollution).

Aggiungere alla fine del PRE-PUBLISH-CHECKLIST.md una sezione "Risks accepted":

```markdown
## Risks accepted (per CONTEXT.md D-07)

- **Reflog GitHub ~90gg post force-push** (Task 3.3): la old history del repo privato resta accessibile via direct SHA reference per ~90gg dopo il force-push. **Accettato** perché:
  - La storia attuale ha solo 5 commit GSD + 2 commit messy (`rifare`, `pre push`), nessun secret catastrofico hard-coded già verificato pre-squash.
  - Pre-publish checklist ha runnato gitleaks su FULL history come safety net last-mile.
  - Nessun outsider conosce gli SHA dei commit pre-squash (repo era private).
- **No GitHub Support ticket** per reflog purge: declinato esplicitamente in CONTEXT.md.
- **`readme-placeholder-map.md` in `.planning/`** post-publish: contiene mapping real→placeholder; valori reali sono comunque recuperabili via Certificate Transparency + WHOIS quindi il valore informativo dell'audit trail supera il rischio incrementale di esposizione (vedi T-02-05 threat model Plan 02).
```
  </action>
  <verify>
    <automated>
test -f .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
test -f .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt
test -f .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt
grep -q '## Step 0' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Step 1' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Step 2' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Step 3' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Step 4' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Step 5' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q 'GO\|NO-GO' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q 'Risks accepted' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
# Step 1 grep negativo (zero residui sul working tree escluso .planning)
! grep -rE '(toto-castaldi\.com|6b09204a|146\.190\.232\.60)' --exclude-dir=.git --exclude-dir=.planning . 2>/dev/null
# Backup bundle esiste localmente
test -f ~/self-hosting-private.bundle && git bundle verify ~/self-hosting-private.bundle 2>&1 | grep -q 'is okay'
    </automated>
  </verify>
  <acceptance_criteria>
    - `.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md` esiste con 6 sezioni `## Step N` (0-5) + sezione "Decision" + sezione "Risks accepted".
    - Ogni step ha: comando eseguito, output sintetico (almeno exit code + linea summary), timestamp ISO 8601, status checkbox PASS/FAIL/SKIPPED motivato.
    - Step 0: bundle creato in `~/self-hosting-private.bundle`, verifica `git bundle verify` esce "is okay".
    - Step 1: grep su working tree (escluso `.planning/`) ritorna 0 match per i pattern leak noti.
    - Step 2: `gitleaks-history-report.txt` esiste, contiene output gitleaks su full history. Se ci sono finding, devono essere SOLO sui commit pre-Plan 02 (verificare data commit SHA).
    - Step 3: `trufflehog-report.txt` esiste, mostra 0 verified secret (oppure è documentato SKIPPED con razionale).
    - Step 4: exiftool eseguito (anche se 0 file matchati, documentato).
    - Step 5: `git status --ignored` eseguito, output documentato.
    - Decisione finale "GO" raggiunta (o "NO-GO" e in tal caso plan si ferma e va ripetuta).
  </acceptance_criteria>
  <done>
Pre-publish checklist eseguita, evidence committata, decisione GO documentata. Repo è pronto per la squash + push.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3.2: Review checklist + autorizzare squash + push + flip visibility</name>
  <what-built>Pre-publish checklist completata con 3 file evidence in `.planning/phases/01-foundations-repo-sanitize/`. Decisione GO o NO-GO esplicita.</what-built>
  <how-to-verify>
1. Antonio apre `.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md` e legge:
   - Step 0: backup bundle path + verifica OK.
   - Step 1: grep risultato zero match (al netto di `.planning/`).
   - Step 2: gitleaks history report — verifica visivamente che i finding (se ci sono) sono SOLO sui commit `rifare` / `pre push` / pre-Plan 02. Se ci sono finding su commit POST Plan 02 → NO-GO, stop, fix Plan 02 prima.
   - Step 3: trufflehog 0 verified (o SKIPPED motivato).
   - Step 4: exiftool 0 file (atteso per docs-only repo).
   - Step 5: git status ignored mostra solo file attesi.
   - Decision: GO esplicito.
2. Antonio apre i due report supporting:
   - `gitleaks-history-report.txt`: skim per confermare i finding sono storici, non recenti.
   - `trufflehog-report.txt`: confermare empty o `"verified": false`.
3. Antonio considera **una volta esplicitamente** il rischio reflog 90gg (D-07). Se cambia idea → NO-GO + scope a `GitHub Support` ticket (deferred ideas).
4. Antonio decide: **procedere con squash + force-push + flip visibility** (Task 3.3) oppure stop.

**IMPORTANTE:** dopo questo checkpoint, Task 3.3 farà:
- `git checkout --orphan public-v1` (modifica branch locale)
- `git push origin public-v1:main --force-with-lease` (modifica IRREVERSIBILE del remote — overwrites main)
- `gh repo edit --visibility public` (FLIP IRREVERSIBILE — il repo diventa pubblico al mondo)

Se hai dubbi, dì NO-GO ora.
  </how-to-verify>
  <resume-signal>Scrivi "approved — procedere con squash, push, flip public" per confermare Task 3.3 (irreversibile). Oppure scrivi "NO-GO: <motivo>" per fermare e fixare.</resume-signal>
</task>

<task type="auto">
  <name>Task 3.3: Squash a orphan branch `public-v1` + force-push come `main` + flip visibility a public + smoke verify</name>
  <files>.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md</files>
  <read_first>
    - .planning/phases/01-foundations-repo-sanitize/01-CONTEXT.md §D-06, §D-07 (flip visibility del repo esistente; rischio reflog accettato; sequenza force-push PRIMA del flip)
    - .planning/research/PITFALLS.md §2 "Concrete plan" — comandi exact orphan + push
    - .planning/research/PITFALLS.md §6 punto 12 ("Force-pushing the sanitized branch over leaked history" — reflog awareness)
    - .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md (da Task 3.1 — verifica decisione GO)
  </read_first>
  <action>
**Pre-flight check:** verificare che `gh` CLI sia autenticato + che il remote `origin` punti al repo privato corretto:

```bash
gh auth status
git remote -v   # atteso: origin -> github.com:<user>/self-hosting (private)
gh repo view --json visibility,name,owner -q '{name,owner:.owner.login,visibility}'
# atteso: {"name":"self-hosting","owner":"<user>","visibility":"PRIVATE"}
```

Se gh non autenticato: `gh auth login` (richiede interaction utente, fail e chiedere ad Antonio).

**Step 6 — Squash a orphan branch:**

```bash
# Lavorare su un fresh clone temporaneo per evitare di sporcare il working tree corrente
WORK=$(mktemp -d)
git clone . "$WORK/repo"
cd "$WORK/repo"

# Verifica che HEAD del clone è il commit più recente con tutto sanitizzato
git log -1 --oneline   # atteso: ultimo commit di Plan 02 (Plan 03 doc + il checklist)

# Crea orphan branch
git checkout --orphan public-v1
git add -A
git commit -m "Initial public release of jarvis self-hosting v1

Narrative repo: documents how I self-host a small set of services
(Supabase, Cloudflare Tunnel, backups) on a home mini-PC.
This is a reference, not a reusable framework. License: MIT."

# Verify orphan: parent count = 0
git log --pretty=format:'%h %p %s' -1
# atteso: <SHA> (vuoto, no parent) Initial public release...
git log --oneline | wc -l
# atteso: 1
```

**Step 7 — Force-push come `main` del remote esistente:**

```bash
# Push del nuovo orphan branch come main (force-with-lease per safety)
git push origin public-v1:main --force-with-lease
# atteso: + <old SHA>...<new SHA> public-v1 -> main (forced update)
```

Tornare al working dir originale del repo locale e re-syncare:

```bash
cd -    # torna al repo originale
git fetch origin
git checkout main
git reset --hard origin/main
# Verifica che la history locale ora è solo 1 commit
git log --oneline | wc -l   # atteso: 1
```

**Step 8 — Flip visibility private → public:**

```bash
gh repo edit --visibility public --accept-visibility-change-consequences
# atteso: success message
gh repo view --json visibility -q '.visibility'   # atteso: PUBLIC
```

Aggiornare la sezione "Step 6-8" del `PRE-PUBLISH-CHECKLIST.md` con:
- Step 6: SHA del commit orphan
- Step 7: output del force-push
- Step 8: output del flip + visibility confermato PUBLIC + URL pubblico del repo

**Step 9 — Smoke verify post-publish:**

```bash
# Fresh clone in tmp
SMOKE=$(mktemp -d)
cd "$SMOKE"
git clone https://github.com/<user>/self-hosting.git
cd self-hosting

# Verifica history = 1 commit
git log --oneline | wc -l   # atteso: 1

# Gitleaks scan
gitleaks detect --config .gitleaks.toml --redact -v --no-banner
echo "Exit: $?"   # atteso: 0 (no leaks)

# Grep leak noti (zero match)
grep -rE '(toto-castaldi\.com|6b09204a|146\.190\.232\.60|toto\.castaldi@)' --exclude-dir=.git .
echo "Exit: $?"   # atteso: 1 (no match)

# Verifica README rendering on github.com (manual o gh CLI)
gh repo view --web   # apre browser su https://github.com/<user>/self-hosting

cd -
rm -rf "$SMOKE"
```

Aggiungere "Step 9" alla checklist con output sintetico e link al repo pubblico.

**Sezione finale "Publication complete"** in PRE-PUBLISH-CHECKLIST.md:

```markdown
## Publication complete

**Repo public URL:** https://github.com/<user>/self-hosting
**Public commit SHA:** <orphan SHA>
**Old history bundle:** ~/self-hosting-private.bundle (size: XX KB) — keep on laptop only
**Visibility:** PUBLIC (verified via `gh repo view --json visibility`)
**GH Actions gitleaks:** [verify post-publish] — should run on the orphan commit; if green, anti-regression is live.
**Completed at:** 2026-05-XX HH:MM:SS+02:00
```

**Verifica finale della GH Action:**

```bash
# Aspettare ~30s che la GH Action si triggera, poi:
gh run list --workflow=gitleaks.yml --limit 1
gh run view --log <RUN_ID> | tail -50
# atteso: success, "No leaks found"
```

Se la GH Action fallisce post-publish: emergenza, ripristinare da bundle:
```bash
# (recovery path — DA NON ESEGUIRE se tutto OK)
git push origin --delete main   # IF needed
git checkout -b main-recovery <old SHA from bundle>
# investigate, fix, retry
```
  </action>
  <verify>
    <automated>
# Repo è pubblico
gh repo view --json visibility -q '.visibility' | grep -qx 'PUBLIC'
# History remote ha 1 commit
git log origin/main --oneline | wc -l | awk '$1 == 1 { exit 0 } { exit 1 }'
# Working tree locale è in sync
git log main --oneline | wc -l | awk '$1 == 1 { exit 0 } { exit 1 }'
# PRE-PUBLISH-CHECKLIST.md ha le sezioni nuove
grep -q '## Step 6\|## Step 7\|## Step 8\|## Step 9' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q '## Publication complete' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
grep -q 'Visibility:.*PUBLIC' .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
# Bundle esiste localmente
test -f ~/self-hosting-private.bundle
# GH Actions ha runnato
gh run list --workflow=gitleaks.yml --limit 1 --json conclusion -q '.[0].conclusion' | grep -qx 'success'
# Smoke clone gitleaks clean (re-run in tmp)
SMOKE=$(mktemp -d) && git clone --quiet https://github.com/$(gh repo view --json nameWithOwner -q '.nameWithOwner').git "$SMOKE/r" && cd "$SMOKE/r" && gitleaks detect --config .gitleaks.toml --no-banner --redact 2>&1 | grep -qE 'leaks found: 0|No leaks found' && cd - && rm -rf "$SMOKE"
    </automated>
  </verify>
  <acceptance_criteria>
    - Branch orphan `public-v1` creato localmente con 1 commit, 0 parent (verificato via `git log --pretty=format:'%p' -1` → vuoto).
    - Remote `origin/main` ora ha 1 solo commit (storia squashata).
    - `gh repo view --json visibility -q '.visibility'` ritorna `PUBLIC`.
    - URL pubblico del repo accessibile da incognito browser (manual verify nel checkpoint umano post — vedi Task 3.4).
    - Smoke verify: clone fresh + gitleaks scan = 0 finding.
    - GitHub Action gitleaks.yml ha runnato sul nuovo commit e ha conclusion `success`.
    - `PRE-PUBLISH-CHECKLIST.md` aggiornato con Step 6, 7, 8, 9 + "Publication complete" + URL pubblico + SHA orphan commit + timestamp.
    - Bundle `~/self-hosting-private.bundle` ancora esiste (safety net).
  </acceptance_criteria>
  <done>
Repo `self-hosting` è pubblico su GitHub con: history orphan single-commit, README sanitizzato, LICENSE MIT, gitleaks GH Action verde, working tree clean rispetto a `.gitleaks.toml`. Bundle privato preservato localmente. Phase 1 chiuso end-to-end.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3.4: Verifica pubblica del repo + README rendering</name>
  <what-built>Repo flippato a public con history squashata e gitleaks Action verde. PRE-PUBLISH-CHECKLIST.md completo.</what-built>
  <how-to-verify>
1. Antonio apre in browser **incognito** (no auth GitHub) l'URL pubblico del repo:
   ```
   https://github.com/<user>/self-hosting
   ```
2. Verifica:
   - Il README renderizza correttamente sulla home del repo.
   - Le sezioni narrative sono presenti (BACKUP RSYNC, SUPABASE, ASCII diagram, ecc.).
   - L'ASCII diagram mostra `jarvis (mini PC)` lowercase.
   - Header introduttivo del README cita "narrative/reference", placeholder convention, License MIT.
   - Nessun `toto-castaldi.com`, `6b09204a`, `@gmail.com`, IP `146.190.*`, `inspiron` visibile in nessuna pagina.
3. Verifica il tab "Code" mostra: README.md, LICENSE, .gitignore, .gitleaks.toml, .pre-commit-config.yaml, .github/workflows/gitleaks.yml, bin/, docs/, .planning/.
4. Verifica il tab "Actions": deve esserci un run del workflow `gitleaks` con status verde (success).
5. Verifica il tab "About" (sidebar): la descrizione potrebbe essere vuota — opzionale: chiedere se vuole settarla via `gh repo edit --description "..."`.
6. Verifica visibility: in alto a destra accanto al nome del repo c'è il badge "Public".
7. Apre `.planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md` e legge la sezione "Publication complete": URL, SHA, timestamp, visibility confermato.
8. Verifica che `~/self-hosting-private.bundle` esiste ancora sul laptop (safety net).
  </how-to-verify>
  <resume-signal>Scrivi "approved — Phase 1 chiusa" per chiudere la fase (commit finale + transition), oppure descrivi cosa va sistemato (es. "il README ha un placeholder rotto in linea N", "il GH Action ha fallito", "voglio aggiungere description al repo").</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Laptop locale → remote `origin` (force-push) | Operazione IRREVERSIBILE (a parte reflog 90gg). Force-with-lease è il guardrail. |
| Remote private → remote public (flip visibility) | Operazione IRREVERSIBILE all'atto del flip. Da questo momento il mondo può clonare il repo. |
| Repo public → Certificate Transparency / Wayback Machine / forks | Tutto ciò che esiste anche per un istante sul main public può essere clonato da bot/scraper. |
| `~/self-hosting-private.bundle` → laptop filesystem | Bundle resta solo localmente. Trust = sicurezza del laptop. |

## STRIDE Threat Register (ASVS Level 1)

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-03-01 | Information Disclosure | Reflog GitHub ~90gg post force-push espone vecchia history (con leak storici) | accept | D-07 esplicito; pre-publish gitleaks su full history pre-squash come safety net (Step 2); commit pre-squash hanno SHA non noti pubblicamente (repo era private); accettato consciously. Mitigazione futura (se cambiasse mind): GitHub Support ticket per purge. |
| T-03-02 | Information Disclosure | Window di esposizione tra force-push e flip private→public | mitigate | Sequenza esplicita: PRIMA force-push (mentre repo è ancora private), POI flip visibility. Se si flippa prima e si force-pusha dopo, finestra di esposizione del private cleanup. CONTEXT.md §Specifics esplicito. |
| T-03-03 | Tampering | Force-push perde commit storici "buoni" (planning GSD) | mitigate | Bundle `~/self-hosting-private.bundle` creato in Step 0 prima della squash; verificato con `git bundle verify`; resta sul laptop come safety net se serve recuperare un commit (es. messaggi di decisione). |
| T-03-04 | Spoofing | Attaccante MITM su `git push` esfiltra credenziali GitHub | mitigate | `gh` CLI usa HTTPS + OAuth/personal access token + 2FA su GitHub account; SSH alternative via ed25519 key; trust transitivo dal laptop + 2FA dell'account. |
| T-03-05 | Denial of Service | Misconfigured push lascia il repo in stato non-funzionante | mitigate | `--force-with-lease` (non `--force` pieno) abort se qualcuno ha pushato in parallelo (defensive, anche se single-dev); smoke clone post-push come verifica end-to-end (Step 9). |
| T-03-06 | Information Disclosure | Smoke clone fresh espone secret leftover non catturati da gitleaks | mitigate | Step 9 esegue `gitleaks detect` sul fresh clone (cattura sia working tree che history); se finding → recovery via bundle + investigate. |
| T-03-07 | Repudiation | Operazione publication senza trail | mitigate | `PRE-PUBLISH-CHECKLIST.md` log eseguito step-by-step con timestamp e exit code; committato in `.planning/` come evidence audit; git log dell'orphan commit ha messaggio descrittivo. |
| T-03-08 | Information Disclosure | `gh repo edit --visibility public` può silently rivelare branch protetti o secrets di Actions | mitigate | Pre-flight check: `gh repo view --json` dump dello stato pre-flip; nessun GitHub Actions secret è impostato sul repo (gitleaks-action@v2 non richiede secret per repo personali); branch protection può essere aggiunto post-flip ma non blocca la flip. |
| T-03-SC | Tampering | Package supply chain: `gh` CLI + gitleaks + trufflehog | mitigate | `gh` da Homebrew/repo ufficiale (binary signed); gitleaks v8.x pinned in `.pre-commit-config.yaml`; trufflehog binary install via script `trufflesecurity/trufflehog`. NESSUN npm/pip/cargo install nuovo in scope. Package Legitimacy Gate non si applica (binaries only, from project owners). |
</threat_model>

<verification>
End-to-end del plan 03:

```bash
# 1. Repo è pubblico
gh repo view --json visibility -q '.visibility'   # atteso: PUBLIC

# 2. History orphan = 1 commit
git log origin/main --oneline | wc -l   # atteso: 1
git log origin/main --pretty=format:'%p' -1   # atteso: vuoto (no parent)

# 3. Smoke clone clean
SMOKE=$(mktemp -d)
git clone https://github.com/$(gh repo view --json nameWithOwner -q '.nameWithOwner').git "$SMOKE/r"
cd "$SMOKE/r"
gitleaks detect --config .gitleaks.toml --no-banner --redact -v
echo "Gitleaks exit: $?"   # atteso: 0
grep -rE '(toto-castaldi\.com|6b09204a|146\.190\.232\.60|toto\.castaldi@)' --exclude-dir=.git .
echo "Grep exit: $?"   # atteso: 1 (no match)
cd - && rm -rf "$SMOKE"

# 4. GH Action gitleaks è verde
gh run list --workflow=gitleaks.yml --limit 1 --json conclusion -q '.[0].conclusion'   # atteso: success

# 5. Bundle locale ancora esiste
test -f ~/self-hosting-private.bundle && git bundle verify ~/self-hosting-private.bundle 2>&1 | grep -q 'is okay'

# 6. PRE-PUBLISH-CHECKLIST.md committata
git ls-files .planning/phases/01-foundations-repo-sanitize/PRE-PUBLISH-CHECKLIST.md
git ls-files .planning/phases/01-foundations-repo-sanitize/gitleaks-history-report.txt
git ls-files .planning/phases/01-foundations-repo-sanitize/trufflehog-report.txt
```
</verification>

<success_criteria>
Plan 03 è completo (e con esso Phase 1) quando:
- [ ] PRE-PUBLISH-CHECKLIST.md eseguita end-to-end (Step 0-9 + Publication complete + Risks accepted) e committata.
- [ ] gitleaks-history-report.txt e trufflehog-report.txt committati come evidence.
- [ ] `~/self-hosting-private.bundle` creato e verificato (safety net locale).
- [ ] Repo squashato in orphan branch `public-v1`, force-pushed come `origin/main`.
- [ ] Visibility flippata a PUBLIC via `gh repo edit`.
- [ ] Smoke clone fresh + gitleaks scan = 0 finding.
- [ ] GitHub Actions gitleaks workflow run = success sul commit orphan.
- [ ] README pubblico verificato rendering corretto (incognito browser, Task 3.4).
- [ ] Phase 1 success criteria #1-5 (ROADMAP.md) tutti verificati.
</success_criteria>

<output>
Create `.planning/phases/01-foundations-repo-sanitize/01-03-SUMMARY.md` when done.

Il SUMMARY deve includere:
- URL pubblico del repo + commit SHA dell'orphan.
- Path al bundle locale di backup.
- Sintesi gitleaks history scan: quanti finding trovati pre-squash, quanti sui commit "rifare"/"pre push" vs Plan 02 SHA → confermare che la squash era necessaria/sufficiente.
- Sintesi trufflehog: 0 verified confermato.
- Status delle GH Actions post-publish (success).
- Link diretti al README pubblico, alla LICENSE, alla prima run gitleaks Action.
- Eventuali follow-up emersi (es. "voglio aggiungere description al repo via `gh repo edit --description ...`", "considerare branch protection su main", "investigare MagicDNS rotto sul laptop" — deferred ideas).
- Phase 1 closure note: tutti i 12 requisiti HOST-01..05 + REPO-01..07 verified, success criteria ROADMAP Phase 1 1-5 verified.
</output>
