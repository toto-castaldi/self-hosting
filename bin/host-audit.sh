#!/usr/bin/env bash
# host-audit.sh — Audit idempotente READ-ONLY dello stato di hardening di jarvis.
#
# Verifica HOST-01..HOST-05 (vedi .planning/REQUIREMENTS.md) producendo un report
# markdown strutturato. NESSUN comando muta lo stato del sistema: solo lettura.
#
# Esempi:
#   sudo bash host-audit.sh                                  # report su stdout + file di default
#   sudo bash host-audit.sh --output /tmp/audit.md           # path custom
#   sudo bash host-audit.sh --quiet                          # solo summary
#   sudo bash host-audit.sh --no-write                       # solo stdout, no file
#   sudo bash host-audit.sh --require-sudo                   # esce 2 se non root
#
# Exit codes:
#   0 = tutti i check OK
#   1 = uno o più check MISSING/WARN
#   2 = errore di esecuzione (es. dipendenze mancanti, sudo richiesto ma assente)

set -euo pipefail

# -----------------------------------------------------------------------------
# Costanti
# -----------------------------------------------------------------------------

readonly AUDIT_SCRIPT_VERSION="v1"
readonly DEFAULT_REPORT_PATH=".planning/phases/01-foundations-repo-sanitize/host-audit-report.md"
readonly TAILSCALE_CGNAT_REGEX='100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'

# -----------------------------------------------------------------------------
# Stato globale (riempito dai check_*)
# -----------------------------------------------------------------------------

# Array associativi/numerici per accumulare righe di ogni sezione.
# Ogni elemento: "Check|Expected|Actual|Status"
declare -a ROWS_HOST01=()
declare -a ROWS_HOST02=()
declare -a ROWS_HOST03=()
declare -a ROWS_HOST04=()
declare -a ROWS_HOST05=()

# Contatori globali
COUNT_OK=0
COUNT_MISSING=0
COUNT_WARN=0

# Flags CLI
OPT_QUIET=0
OPT_NO_WRITE=0
OPT_REQUIRE_SUDO=0
OPT_OUTPUT="${AUDIT_REPORT_PATH:-$DEFAULT_REPORT_PATH}"

# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

# add_row <array_name> <check> <expected> <actual> <status>
# Aggiorna l'array passato (passaggio per nome via nameref) e i contatori.
add_row() {
  local -n arr=$1
  local check=$2 expected=$3 actual=$4 status=$5
  # Replace internal '|' with '/' to keep the pipe-delimited row parseable.
  check=${check//|//}
  expected=${expected//|//}
  actual=${actual//|//}
  status=${status//|//}
  arr+=("${check}|${expected}|${actual}|${status}")
  case "$status" in
    OK)      COUNT_OK=$((COUNT_OK + 1)) ;;
    MISSING) COUNT_MISSING=$((COUNT_MISSING + 1)) ;;
    WARN)    COUNT_WARN=$((COUNT_WARN + 1)) ;;
  esac
}

# Esegue un comando catturando stdout+stderr; restituisce sempre 0 (per non
# uccidere set -e). Stampa output trimmed su stdout.
safe_run() {
  local out
  if out=$("$@" 2>&1); then
    printf '%s' "$out"
  else
    printf '%s' "$out"
  fi
}

# Sanitizza una stringa per la pipe-delimited row (sostituisce | e newline).
sanitize() {
  printf '%s' "$1" | tr '\n|' '  ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

# Scrub: rimuove dal report eventuali MagicDNS suffix (tail-xxxxx.ts.net) e
# IP non CGNAT (lasciamo solo 100.64.0.0/10). Conservativo.
# Legge da stdin (usato come pipe a fine generate_report).
scrub() {
  sed -E 's/\b[a-z0-9-]+\.ts\.net\b/<magicdns-suffix-scrubbed>/g'
}

# -----------------------------------------------------------------------------
# CLI parsing
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -q, --quiet           Solo summary su stdout
  -o, --output PATH     Path del report markdown (default: $DEFAULT_REPORT_PATH)
      --no-write        Non scrivere file, solo stdout
      --require-sudo    Esce con errore se non lanciato come root/sudo
  -h, --help            Mostra questo help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--quiet)         OPT_QUIET=1; shift ;;
      -o|--output)        OPT_OUTPUT="$2"; shift 2 ;;
      --no-write)         OPT_NO_WRITE=1; shift ;;
      --require-sudo)     OPT_REQUIRE_SUDO=1; shift ;;
      -h|--help)          usage; exit 0 ;;
      --)                 shift; break ;;
      *)                  echo "Opzione sconosciuta: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Check di pre-requisiti
# -----------------------------------------------------------------------------

require_root_if_needed() {
  if [[ "$OPT_REQUIRE_SUDO" -eq 1 && "$(id -u)" -ne 0 ]]; then
    echo "ERROR: --require-sudo richiesto, ma EUID=$(id -u). Re-run con 'sudo'." >&2
    exit 2
  fi
}

# -----------------------------------------------------------------------------
# check_ssh_keyonly (HOST-01)
# -----------------------------------------------------------------------------
# Verifica configurazione SSH effective (sshd -T) e unattended-upgrades attivo.

check_ssh_keyonly() {
  local sshd_out
  if [[ "$(id -u)" -eq 0 ]]; then
    sshd_out=$(safe_run sshd -T)
  else
    sshd_out=$(safe_run sudo -n sshd -T 2>/dev/null || true)
    if [[ -z "$sshd_out" ]]; then
      add_row ROWS_HOST01 "sshd -T effective config" "leggibile (root)" "non eseguibile senza sudo" "WARN"
      return
    fi
  fi

  # PasswordAuthentication
  local pwauth
  pwauth=$(printf '%s\n' "$sshd_out" | awk '/^passwordauthentication/ {print $2; exit}')
  if [[ "$pwauth" == "no" ]]; then
    add_row ROWS_HOST01 "PasswordAuthentication" "no" "$pwauth" "OK"
  else
    add_row ROWS_HOST01 "PasswordAuthentication" "no" "${pwauth:-<assente>}" "MISSING"
  fi

  # PubkeyAuthentication
  local pkauth
  pkauth=$(printf '%s\n' "$sshd_out" | awk '/^pubkeyauthentication/ {print $2; exit}')
  if [[ "$pkauth" == "yes" ]]; then
    add_row ROWS_HOST01 "PubkeyAuthentication" "yes" "$pkauth" "OK"
  else
    add_row ROWS_HOST01 "PubkeyAuthentication" "yes" "${pkauth:-<assente>}" "MISSING"
  fi

  # PermitRootLogin
  local rootlogin
  rootlogin=$(printf '%s\n' "$sshd_out" | awk '/^permitrootlogin/ {print $2; exit}')
  if [[ "$rootlogin" == "no" || "$rootlogin" == "prohibit-password" ]]; then
    add_row ROWS_HOST01 "PermitRootLogin" "no|prohibit-password" "$rootlogin" "OK"
  else
    add_row ROWS_HOST01 "PermitRootLogin" "no|prohibit-password" "${rootlogin:-<assente>}" "WARN"
  fi

  # KbdInteractiveAuthentication
  local kbd
  kbd=$(printf '%s\n' "$sshd_out" | awk '/^kbdinteractiveauthentication/ {print $2; exit}')
  if [[ "$kbd" == "no" ]]; then
    add_row ROWS_HOST01 "KbdInteractiveAuthentication" "no" "$kbd" "OK"
  else
    add_row ROWS_HOST01 "KbdInteractiveAuthentication" "no" "${kbd:-<assente>}" "WARN"
  fi

  # unattended-upgrades active
  local uu_active
  uu_active=$(safe_run systemctl is-active unattended-upgrades)
  if [[ "$uu_active" == "active" ]]; then
    add_row ROWS_HOST01 "unattended-upgrades service" "active" "$uu_active" "OK"
  else
    add_row ROWS_HOST01 "unattended-upgrades service" "active" "$uu_active" "MISSING"
  fi

  # security source in 50unattended-upgrades
  local uu_cfg="/etc/apt/apt.conf.d/50unattended-upgrades"
  if [[ -r "$uu_cfg" ]]; then
    if grep -E '^[[:space:]]*"\$\{distro_id\}:\$\{distro_codename\}-security' "$uu_cfg" >/dev/null 2>&1; then
      add_row ROWS_HOST01 "unattended-upgrades security source" "uncommented" "presente" "OK"
    else
      add_row ROWS_HOST01 "unattended-upgrades security source" "uncommented" "commentata o assente" "MISSING"
    fi
  else
    add_row ROWS_HOST01 "unattended-upgrades security source" "uncommented" "$uu_cfg assente" "MISSING"
  fi
}

# -----------------------------------------------------------------------------
# check_docker (HOST-02)
# -----------------------------------------------------------------------------

check_docker() {
  # docker binary
  if command -v docker >/dev/null 2>&1; then
    local docker_ver
    docker_ver=$(docker --version 2>&1 | head -1)
    add_row ROWS_HOST02 "docker binary" "presente" "$(sanitize "$docker_ver")" "OK"
  else
    add_row ROWS_HOST02 "docker binary" "presente" "command not found" "MISSING"
    add_row ROWS_HOST02 "docker compose plugin" "v2 presente" "non testabile (docker mancante)" "MISSING"
    add_row ROWS_HOST02 "toto in docker group" "membro" "non testabile (docker mancante)" "MISSING"
    add_row ROWS_HOST02 "docker info senza sudo (toto)" "exit 0" "non testabile (docker mancante)" "MISSING"
    return
  fi

  # docker compose plugin
  if docker compose version >/dev/null 2>&1; then
    local compose_ver
    compose_ver=$(docker compose version 2>&1 | head -1)
    add_row ROWS_HOST02 "docker compose plugin" "v2 presente" "$(sanitize "$compose_ver")" "OK"
  else
    add_row ROWS_HOST02 "docker compose plugin" "v2 presente" "non disponibile" "MISSING"
  fi

  # toto in docker group
  if getent passwd toto >/dev/null 2>&1; then
    if id -nG toto 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
      add_row ROWS_HOST02 "toto in docker group" "membro" "membro" "OK"
    else
      add_row ROWS_HOST02 "toto in docker group" "membro" "non membro" "MISSING"
    fi
  else
    add_row ROWS_HOST02 "toto user" "esistente" "non esistente" "MISSING"
  fi

  # docker info senza sudo (come toto)
  local docker_info_status
  if [[ "$(id -u)" -eq 0 ]]; then
    if runuser -u toto -- docker info >/dev/null 2>&1; then
      docker_info_status="OK"
    else
      docker_info_status="MISSING"
    fi
  else
    if [[ "$(id -un)" == "toto" ]]; then
      if docker info >/dev/null 2>&1; then
        docker_info_status="OK"
      else
        docker_info_status="MISSING"
      fi
    else
      docker_info_status="WARN-not-tested-as-toto"
    fi
  fi

  case "$docker_info_status" in
    OK)
      add_row ROWS_HOST02 "docker info senza sudo (toto)" "exit 0" "exit 0" "OK" ;;
    MISSING)
      add_row ROWS_HOST02 "docker info senza sudo (toto)" "exit 0" "exit != 0" "MISSING" ;;
    *)
      add_row ROWS_HOST02 "docker info senza sudo (toto)" "exit 0" "non testato (audit non come root né toto)" "WARN" ;;
  esac
}

# -----------------------------------------------------------------------------
# check_tailscale (HOST-03)
# -----------------------------------------------------------------------------

check_tailscale() {
  # tailscaled service
  local ts_active
  ts_active=$(safe_run systemctl is-active tailscaled)
  if [[ "$ts_active" == "active" ]]; then
    add_row ROWS_HOST03 "tailscaled service" "active" "$ts_active" "OK"
  else
    add_row ROWS_HOST03 "tailscaled service" "active" "$ts_active" "MISSING"
    add_row ROWS_HOST03 "tailscale BackendState" "Running" "non testabile (tailscaled inattivo)" "MISSING"
    return
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    add_row ROWS_HOST03 "tailscale CLI" "presente" "command not found" "MISSING"
    return
  fi

  # BackendState (richiede jq)
  if command -v jq >/dev/null 2>&1; then
    local backend_state
    backend_state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')
    if [[ "$backend_state" == "Running" ]]; then
      add_row ROWS_HOST03 "tailscale BackendState" "Running" "$backend_state" "OK"
    else
      add_row ROWS_HOST03 "tailscale BackendState" "Running" "${backend_state:-<vuoto>}" "MISSING"
    fi

    # MagicDNS suffix presente — scrubbed nel report
    local magic_dns
    magic_dns=$(tailscale status --json 2>/dev/null | jq -r '.MagicDNSSuffix // empty')
    if [[ -n "$magic_dns" ]]; then
      add_row ROWS_HOST03 "MagicDNSSuffix" "non vuoto" "<magicdns-suffix-scrubbed>" "OK"
    else
      add_row ROWS_HOST03 "MagicDNSSuffix" "non vuoto" "<vuoto>" "WARN"
    fi
  else
    add_row ROWS_HOST03 "jq dipendenza" "presente per parse status" "non installato" "WARN"
    local backend_state
    backend_state=$(tailscale status 2>/dev/null | head -1 || true)
    add_row ROWS_HOST03 "tailscale status (fallback)" "running" "$(sanitize "$backend_state")" "WARN"
  fi

  # IP nel CGNAT 100.64.0.0/10
  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null | head -1 || true)
  if [[ -n "$ts_ip" ]] && printf '%s' "$ts_ip" | grep -qE "^${TAILSCALE_CGNAT_REGEX}"; then
    add_row ROWS_HOST03 "tailscale IPv4 in 100.64.0.0/10" "match CGNAT" "$ts_ip" "OK"
  else
    add_row ROWS_HOST03 "tailscale IPv4 in 100.64.0.0/10" "match CGNAT" "${ts_ip:-<vuoto>}" "MISSING"
  fi

  # tailscale0 interfaccia esiste
  if ip -o link show tailscale0 >/dev/null 2>&1; then
    add_row ROWS_HOST03 "interfaccia tailscale0" "esistente" "presente" "OK"
  else
    add_row ROWS_HOST03 "interfaccia tailscale0" "esistente" "assente" "MISSING"
  fi
}

# -----------------------------------------------------------------------------
# check_filesystem_layout (HOST-04)
# -----------------------------------------------------------------------------

check_filesystem_layout() {
  # /home/toto/jarvis — toto:toto, 0755 o 0750
  if [[ -d /home/toto/jarvis ]]; then
    local own perm
    own=$(stat -c '%U:%G' /home/toto/jarvis)
    perm=$(stat -c '%a' /home/toto/jarvis)
    if [[ "$own" == "toto:toto" && ( "$perm" == "755" || "$perm" == "750" ) ]]; then
      add_row ROWS_HOST04 "/home/toto/jarvis" "toto:toto 755|750" "$own $perm" "OK"
    else
      add_row ROWS_HOST04 "/home/toto/jarvis" "toto:toto 755|750" "$own $perm" "WARN"
    fi
  else
    add_row ROWS_HOST04 "/home/toto/jarvis" "toto:toto 755|750" "assente" "MISSING"
  fi

  # /home/toto/lumio — toto:toto, 0755 o 0750
  if [[ -d /home/toto/lumio ]]; then
    local own perm
    own=$(stat -c '%U:%G' /home/toto/lumio)
    perm=$(stat -c '%a' /home/toto/lumio)
    if [[ "$own" == "toto:toto" && ( "$perm" == "755" || "$perm" == "750" ) ]]; then
      add_row ROWS_HOST04 "/home/toto/lumio" "toto:toto 755|750" "$own $perm" "OK"
    else
      add_row ROWS_HOST04 "/home/toto/lumio" "toto:toto 755|750" "$own $perm" "WARN"
    fi
  else
    add_row ROWS_HOST04 "/home/toto/lumio" "toto:toto 755|750" "assente" "MISSING"
  fi

  # /etc/cloudflared — root:cloudflared 0750
  if [[ -d /etc/cloudflared ]]; then
    local own perm
    own=$(stat -c '%U:%G' /etc/cloudflared)
    perm=$(stat -c '%a' /etc/cloudflared)
    if [[ "$own" == "root:cloudflared" && "$perm" == "750" ]]; then
      add_row ROWS_HOST04 "/etc/cloudflared" "root:cloudflared 750" "$own $perm" "OK"
    else
      add_row ROWS_HOST04 "/etc/cloudflared" "root:cloudflared 750" "$own $perm" "WARN"
    fi
  else
    add_row ROWS_HOST04 "/etc/cloudflared" "root:cloudflared 750" "assente" "MISSING"
  fi

  # cloudflared user/group (stub per Phase 2, ma il group serve per /etc/cloudflared)
  if getent group cloudflared >/dev/null 2>&1; then
    add_row ROWS_HOST04 "group cloudflared" "esistente" "presente" "OK"
  else
    add_row ROWS_HOST04 "group cloudflared" "esistente" "assente" "MISSING"
  fi
}

# -----------------------------------------------------------------------------
# check_ufw (HOST-05)
# -----------------------------------------------------------------------------

check_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    add_row ROWS_HOST05 "ufw binary" "presente" "command not found" "MISSING"
    return
  fi
  add_row ROWS_HOST05 "ufw binary" "presente" "presente" "OK"

  # ufw status verbose richiede root
  local ufw_out=""
  if [[ "$(id -u)" -eq 0 ]]; then
    ufw_out=$(safe_run ufw status verbose)
  else
    ufw_out=$(safe_run sudo -n ufw status verbose 2>/dev/null || true)
  fi

  if [[ -z "$ufw_out" ]]; then
    add_row ROWS_HOST05 "ufw status verbose" "leggibile (root)" "non eseguibile senza sudo" "WARN"
    return
  fi

  # Status: active
  if printf '%s\n' "$ufw_out" | grep -qE '^Status:[[:space:]]+active'; then
    add_row ROWS_HOST05 "ufw Status" "active" "active" "OK"
  else
    add_row ROWS_HOST05 "ufw Status" "active" "inactive" "MISSING"
  fi

  # Default: deny (incoming)
  if printf '%s\n' "$ufw_out" | grep -qE '^Default:.*deny[[:space:]]*\(incoming\)'; then
    add_row ROWS_HOST05 "ufw Default incoming" "deny" "deny" "OK"
  else
    local def
    def=$(printf '%s\n' "$ufw_out" | awk -F: '/^Default:/ {print $2; exit}' | sed 's/^[[:space:]]*//')
    add_row ROWS_HOST05 "ufw Default incoming" "deny" "${def:-<sconosciuto>}" "MISSING"
  fi

  # Regola SSH solo via tailscale0 (o CIDR 100.64.0.0/10)
  # NB: `ufw status` rendering is "22/tcp on tailscale0   ALLOW IN   Anywhere",
  # i.e., port → interface → action. Cover all orderings to be defensive.
  if printf '%s\n' "$ufw_out" | grep -qE '(22/tcp.*tailscale0.*ALLOW IN|22/tcp.*ALLOW IN.*tailscale0|tailscale0.*ALLOW IN.*22|tailscale0.*22/tcp.*ALLOW)'; then
    add_row ROWS_HOST05 "regola SSH su tailscale0" "ALLOW IN 22/tcp on tailscale0" "presente" "OK"
  elif printf '%s\n' "$ufw_out" | grep -qE '22/tcp.*ALLOW IN.*100\.64\.'; then
    add_row ROWS_HOST05 "regola SSH su tailscale0" "ALLOW IN 22/tcp on tailscale0|CGNAT" "presente (via CIDR)" "OK"
  else
    add_row ROWS_HOST05 "regola SSH su tailscale0" "ALLOW IN 22/tcp on tailscale0" "assente" "MISSING"
  fi

  # No regola open 22/tcp su ANY (regressione: SSH al world)
  if printf '%s\n' "$ufw_out" | grep -qE '^22/tcp[[:space:]]+ALLOW IN[[:space:]]+Anywhere'; then
    add_row ROWS_HOST05 "no 22/tcp ALLOW Anywhere" "assente" "PRESENTE (regressione SSH al world)" "MISSING"
  else
    add_row ROWS_HOST05 "no 22/tcp ALLOW Anywhere" "assente" "assente" "OK"
  fi
}

# -----------------------------------------------------------------------------
# check_overall — aggrega e setta exit code
# -----------------------------------------------------------------------------

check_overall() {
  if [[ "$COUNT_MISSING" -gt 0 ]]; then
    OVERALL_STATUS="FAIL"
    OVERALL_EXIT=1
  elif [[ "$COUNT_WARN" -gt 0 ]]; then
    OVERALL_STATUS="WARN"
    OVERALL_EXIT=1
  else
    OVERALL_STATUS="OK"
    OVERALL_EXIT=0
  fi
}

# -----------------------------------------------------------------------------
# Report writer
# -----------------------------------------------------------------------------

print_section() {
  local title=$1
  shift
  local -n rows=$1
  printf '## %s\n\n' "$title"
  if [[ "${#rows[@]}" -eq 0 ]]; then
    printf '_(nessun check eseguito)_\n\n'
    return
  fi
  printf '| Check | Expected | Actual | Status |\n'
  printf '| --- | --- | --- | --- |\n'
  local row check expected actual status
  for row in "${rows[@]}"; do
    IFS='|' read -r check expected actual status <<<"$row"
    printf '| %s | %s | %s | %s |\n' "$check" "$expected" "$actual" "$status"
  done
  printf '\n'
}

# Determina la riga "Run at:" e separa la versione idempotente del resto.
# Costruzione del report: header + sezioni + summary.
build_report() {
  local now hostname_v os_v kernel_v
  now=$(date -Is)
  hostname_v=$(hostname)
  os_v=$(safe_run lsb_release -ds || true)
  if [[ -z "$os_v" ]]; then
    os_v=$(safe_run sh -c '. /etc/os-release && echo "$PRETTY_NAME"')
  fi
  kernel_v=$(uname -r)

  {
    printf '# Host Audit Report — jarvis\n\n'
    printf '**Hostname:** %s  \n' "$hostname_v"
    printf '**OS:** %s  \n' "$os_v"
    printf '**Kernel:** %s  \n' "$kernel_v"
    printf '**Run at:** %s  \n' "$now"
    printf '**Audit script version:** %s  \n\n' "$AUDIT_SCRIPT_VERSION"
    printf -- '---\n\n'

    print_section "HOST-01: SSH key-only + unattended-upgrades" ROWS_HOST01
    print_section "HOST-02: Docker + toto senza sudo"            ROWS_HOST02
    print_section "HOST-03: Tailscale running"                   ROWS_HOST03
    print_section "HOST-04: Filesystem layout"                   ROWS_HOST04
    print_section "HOST-05: ufw default-deny + SSH via tailscale0" ROWS_HOST05

    printf -- '---\n\n'
    printf '## Summary\n\n'
    printf -- '- **OK:** %d\n' "$COUNT_OK"
    printf -- '- **MISSING:** %d\n' "$COUNT_MISSING"
    printf -- '- **WARN:** %d\n' "$COUNT_WARN"
    printf -- '- **Overall:** %s\n\n' "$OVERALL_STATUS"
    if [[ "$OVERALL_EXIT" -ne 0 ]]; then
      printf '_Run_ `bin/host-apply.sh` _per applicare i fix proposti (richiede sudo)._\n'
    else
      printf '_Stato hardened OK — nessuna azione richiesta._\n'
    fi
  } | scrub
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  require_root_if_needed

  check_ssh_keyonly
  check_docker
  check_tailscale
  check_filesystem_layout
  check_ufw
  check_overall

  local report
  report=$(build_report)

  if [[ "$OPT_NO_WRITE" -eq 0 ]]; then
    local dir
    dir=$(dirname "$OPT_OUTPUT")
    if [[ -n "$dir" && "$dir" != "." && ! -d "$dir" ]]; then
      printf 'WARN: directory %s non esiste, salto scrittura file (--output)\n' "$dir" >&2
    else
      printf '%s' "$report" > "$OPT_OUTPUT"
    fi
  fi

  if [[ "$OPT_QUIET" -eq 1 ]]; then
    printf 'Audit: OK=%d MISSING=%d WARN=%d Overall=%s\n' \
      "$COUNT_OK" "$COUNT_MISSING" "$COUNT_WARN" "$OVERALL_STATUS"
  else
    printf '%s\n' "$report"
  fi

  exit "$OVERALL_EXIT"
}

# Esegui main solo se script è eseguito (non sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
