#!/usr/bin/env bash
# host-apply.sh — Applica fix idempotenti su jarvis guidati da host-audit.sh.
#
# Per ogni gruppo (HOST-01..HOST-05) lo script:
#   1. Verifica se il fix serve (richiama le funzioni check_* di host-audit.sh).
#   2. Chiede conferma interattiva (saltabile con --yes per CI).
#   3. Applica solo se non già conforme (idempotenza).
#
# Al termine ri-esegue l'audit e sovrascrive
#   .planning/phases/01-foundations-repo-sanitize/host-audit-report.md
# come "report post-apply" — committato come evidence.
#
# REQUISITI: deve girare con sudo (EUID 0). Tailscale già attivo (verifica
# pre-flight): apply_ufw chiude SSH a tutto tranne tailscale0, quindi se la
# sessione corrente NON è via Tailscale, l'utente perde l'accesso.
#
# Exit codes:
#   0 = successo (eventuali skip "già conforme" inclusi)
#   1 = errore in uno degli apply_*
#   2 = pre-flight failure (no sudo, Tailscale assente, ecc.)

set -euo pipefail

# -----------------------------------------------------------------------------
# Costanti / path
# -----------------------------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AUDIT_SCRIPT="${SCRIPT_DIR}/host-audit.sh"
readonly REPORT_PATH=".planning/phases/01-foundations-repo-sanitize/host-audit-report.md"
readonly SSHD_DROPIN="/etc/ssh/sshd_config.d/10-hardening.conf"
readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
readonly DOCKER_SOURCES="/etc/apt/sources.list.d/docker.list"

# Flags CLI
OPT_YES=0

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

log()      { printf '[host-apply] %s\n' "$*" >&2; }
log_step() { printf '\n=== %s ===\n' "$*" >&2; }
log_ok()   { printf '[host-apply] OK: %s\n' "$*" >&2; }
log_warn() { printf '[host-apply] WARN: %s\n' "$*" >&2; }
log_skip() { printf '[host-apply] SKIP (già conforme): %s\n' "$*" >&2; }
die()      { printf '[host-apply] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

# -----------------------------------------------------------------------------
# CLI parsing
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [options]

Options:
  -y, --yes      Skip prompt interattivi (per CI futura)
  -h, --help     Mostra questo help

NB: deve girare con sudo. Tailscale deve essere attivo (pre-flight).
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) OPT_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      *) die "Opzione sconosciuta: $1" 2 ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Deve girare come root (usa 'sudo bash $0')." 2
  fi
}

require_audit_script() {
  if [[ ! -r "$AUDIT_SCRIPT" ]]; then
    die "Script audit non trovato: $AUDIT_SCRIPT" 2
  fi
}

require_tailscale_active() {
  if ! systemctl is-active tailscaled >/dev/null 2>&1; then
    die "tailscaled NON è attivo. Senza Tailscale, apply_ufw chiuderebbe l'unico canale SSH. Aborting." 2
  fi
}

confirm() {
  local prompt=$1
  if [[ "$OPT_YES" -eq 1 ]]; then
    log "AUTO-YES: $prompt"
    return 0
  fi
  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# apply_ssh (HOST-01)
# -----------------------------------------------------------------------------
# Crea /etc/ssh/sshd_config.d/10-hardening.conf con i settings di sicurezza,
# poi reload sshd. Installa unattended-upgrades e abilita security source.

apply_ssh() {
  log_step "HOST-01: SSH key-only + unattended-upgrades"

  # 1. sshd drop-in
  # NB: cache sshd -T output once so awk doesn't SIGPIPE it (under set -o
  # pipefail, an early `exit` in awk closes the pipe, sshd gets SIGPIPE,
  # subshell exits 141 → set -e kills the script silently).
  local sshd_out pwauth pkauth
  sshd_out=$(sshd -T 2>/dev/null || true)
  pwauth=$(printf '%s\n' "$sshd_out" | awk '/^passwordauthentication/ {print $2}' | head -n1)
  pkauth=$(printf '%s\n' "$sshd_out" | awk '/^pubkeyauthentication/ {print $2}' | head -n1)

  local need_sshd_fix=0
  [[ "$pwauth" != "no" ]]   && need_sshd_fix=1
  [[ "$pkauth" != "yes" ]]  && need_sshd_fix=1

  if [[ "$need_sshd_fix" -eq 0 && -f "$SSHD_DROPIN" ]]; then
    log_skip "sshd hardening drop-in già attivo ($SSHD_DROPIN)"
  else
    if confirm "Applicare hardening sshd (drop-in $SSHD_DROPIN)?"; then
      cat > "$SSHD_DROPIN" <<'EOF'
# Managed by bin/host-apply.sh — hardening baseline jarvis
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
      chmod 0644 "$SSHD_DROPIN"
      if ! sshd -t; then
        die "sshd -t fallisce dopo creazione di $SSHD_DROPIN — config invalida, abort."
      fi
      systemctl reload ssh || systemctl reload sshd || log_warn "reload ssh fallito (controlla journalctl)"
      log_ok "sshd hardening attivo via $SSHD_DROPIN"
    else
      log_warn "sshd hardening SKIPPATO dall'utente"
    fi
  fi

  # 2. unattended-upgrades
  local uu_active
  uu_active=$(systemctl is-active unattended-upgrades 2>/dev/null || true)
  local uu_cfg="/etc/apt/apt.conf.d/50unattended-upgrades"
  local uu_security_present=0
  if [[ -r "$uu_cfg" ]] && grep -E '^[[:space:]]*"\$\{distro_id\}:\$\{distro_codename\}-security' "$uu_cfg" >/dev/null 2>&1; then
    uu_security_present=1
  fi

  if [[ "$uu_active" == "active" && "$uu_security_present" -eq 1 ]]; then
    log_skip "unattended-upgrades attivo con security source"
  else
    if confirm "Installare/abilitare unattended-upgrades + security source?"; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges
      # Uncomment security source se commentata
      if [[ -r "$uu_cfg" ]] && grep -qE '^[[:space:]]*//[[:space:]]*"\$\{distro_id\}:\$\{distro_codename\}-security' "$uu_cfg"; then
        sed -i 's|^[[:space:]]*//[[:space:]]*\("\${distro_id}:\${distro_codename}-security"\)|\t\1|' "$uu_cfg"
      fi
      systemctl enable --now unattended-upgrades.service
      systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
      log_ok "unattended-upgrades attivo, security source attiva"
    else
      log_warn "unattended-upgrades SKIPPATO dall'utente"
    fi
  fi
}

# -----------------------------------------------------------------------------
# apply_docker (HOST-02)
# -----------------------------------------------------------------------------
# Installa Docker CE + plugin compose dal repo apt ufficiale (pinnato a 'noble'
# come workaround Ubuntu 26.04). Aggiunge toto al gruppo docker.

apply_docker() {
  log_step "HOST-02: Docker + toto senza sudo"

  local need_docker=0
  if ! command -v docker >/dev/null 2>&1; then
    need_docker=1
  fi

  local toto_in_docker=0
  if getent passwd toto >/dev/null 2>&1 && id -nG toto 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    toto_in_docker=1
  fi

  if [[ "$need_docker" -eq 0 && "$toto_in_docker" -eq 1 ]]; then
    log_skip "Docker installato e toto in gruppo docker"
    return
  fi

  if ! confirm "Installare/aggiornare Docker e aggiungere toto a gruppo docker?"; then
    log_warn "Docker apply SKIPPATO dall'utente"
    return
  fi

  if [[ "$need_docker" -eq 1 ]]; then
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f "$DOCKER_KEYRING" ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_KEYRING"
      chmod 0644 "$DOCKER_KEYRING"
    fi
    # Pin su 'noble' (Ubuntu 26.04 'resolute'/'questing' NOT YET nel repo upstream).
    # Documented in PROJECT.md key decisions.
    local arch
    arch=$(dpkg --print-architecture)
    cat > "$DOCKER_SOURCES" <<EOF
deb [arch=${arch} signed-by=${DOCKER_KEYRING}] https://download.docker.com/linux/ubuntu noble stable
EOF
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log_ok "Docker installato (repo apt pinned a 'noble')"
  fi

  if [[ "$toto_in_docker" -eq 0 ]]; then
    if getent passwd toto >/dev/null 2>&1; then
      usermod -aG docker toto
      log_ok "toto aggiunto a gruppo docker (richiede logout/login per attivare nella shell corrente)"
    else
      log_warn "Utente toto non esiste — skip gruppo docker"
    fi
  fi
}

# -----------------------------------------------------------------------------
# apply_filesystem (HOST-04)
# -----------------------------------------------------------------------------
# Crea /home/toto/jarvis, /home/toto/lumio (toto:toto 0755) e
# /etc/cloudflared (root:cloudflared 0750). Crea il gruppo cloudflared se
# manca (prerequisito per Phase 2 ma stub creato qui).

apply_filesystem() {
  log_step "HOST-04: Filesystem layout"

  local need_fs_fix=0
  for d in /home/toto/jarvis /home/toto/lumio; do
    if [[ ! -d "$d" ]]; then
      need_fs_fix=1; break
    fi
    local own
    own=$(stat -c '%U:%G' "$d")
    if [[ "$own" != "toto:toto" ]]; then
      need_fs_fix=1; break
    fi
  done

  local need_cf_group=0
  if ! getent group cloudflared >/dev/null 2>&1; then
    need_cf_group=1; need_fs_fix=1
  fi

  if [[ ! -d /etc/cloudflared ]]; then
    need_fs_fix=1
  else
    local own perm
    own=$(stat -c '%U:%G' /etc/cloudflared)
    perm=$(stat -c '%a' /etc/cloudflared)
    if [[ "$own" != "root:cloudflared" || "$perm" != "750" ]]; then
      need_fs_fix=1
    fi
  fi

  if [[ "$need_fs_fix" -eq 0 ]]; then
    log_skip "Layout filesystem già conforme"
    return
  fi

  if ! confirm "Creare layout filesystem (/home/toto/{jarvis,lumio}, /etc/cloudflared, gruppo cloudflared)?"; then
    log_warn "Filesystem apply SKIPPATO dall'utente"
    return
  fi

  # /home/toto/{jarvis,lumio}
  install -d -o toto -g toto -m 0755 /home/toto/jarvis
  install -d -o toto -g toto -m 0755 /home/toto/lumio
  log_ok "/home/toto/jarvis e /home/toto/lumio create (toto:toto 0755)"

  # cloudflared group (e user system, riservato per Phase 2)
  if [[ "$need_cf_group" -eq 1 ]]; then
    # Creiamo l'utente system cloudflared se non esiste — il gruppo viene creato come side-effect.
    # Il pacchetto cloudflared di Phase 2 userà questo utente se presente.
    if ! getent passwd cloudflared >/dev/null 2>&1; then
      useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared
    fi
    # In ogni caso assicuriamoci che il gruppo esista
    if ! getent group cloudflared >/dev/null 2>&1; then
      groupadd --system cloudflared
    fi
    log_ok "Utente/gruppo cloudflared creato (riservato per Phase 2)"
  fi

  # /etc/cloudflared
  install -d -o root -g cloudflared -m 0750 /etc/cloudflared
  log_ok "/etc/cloudflared creato (root:cloudflared 0750)"
}

# -----------------------------------------------------------------------------
# apply_ufw (HOST-05)
# -----------------------------------------------------------------------------
# Default-deny inbound, allow loopback, allow SSH solo su tailscale0.
# CRITICO: se la sessione SSH corrente NON è via Tailscale, dopo `ufw enable`
# l'utente perde la connessione. Pre-flight: require Tailscale attivo +
# warning interattivo esplicito (--yes salta).

apply_ufw() {
  log_step "HOST-05: ufw default-deny + SSH solo via tailscale0"

  if ! command -v ufw >/dev/null 2>&1; then
    if confirm "ufw non installato — installarlo?"; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    else
      log_warn "ufw install SKIPPATO dall'utente"
      return
    fi
  fi

  local ufw_status
  ufw_status=$(ufw status verbose 2>/dev/null || true)

  local need_apply=0
  if ! printf '%s\n' "$ufw_status" | grep -qE '^Status:[[:space:]]+active'; then
    need_apply=1
  elif ! printf '%s\n' "$ufw_status" | grep -qE '^Default:.*deny[[:space:]]*\(incoming\)'; then
    need_apply=1
  elif ! printf '%s\n' "$ufw_status" | grep -qE 'tailscale0.*ALLOW|22/tcp.*ALLOW IN.*tailscale0'; then
    need_apply=1
  fi

  if [[ "$need_apply" -eq 0 ]]; then
    log_skip "ufw già attivo con default-deny + SSH via tailscale0"
    return
  fi

  log_warn "STAI PER APPLICARE ufw DEFAULT-DENY + SSH solo via tailscale0."
  log_warn "Se la tua sessione SSH attuale NON è via Tailscale, perderai l'accesso."
  log_warn "Verifica: la sessione SSH che esegue questo script deve venire dall'interfaccia tailscale0."

  if ! confirm "Sei loggato via Tailscale e procedo a chiudere SSH su ogni altra interfaccia?"; then
    log_warn "ufw apply SKIPPATO dall'utente"
    return
  fi

  # Ordine importante: regola allow PRIMA di enable per non perdere la sessione.
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow in on lo
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH from tailnet only'
  ufw --force enable
  log_ok "ufw attivo: default-deny inbound, SSH solo via tailscale0"
}

# -----------------------------------------------------------------------------
# apply_post_audit — re-esegue audit e salva report
# -----------------------------------------------------------------------------

apply_post_audit() {
  log_step "Post-apply audit (re-run host-audit.sh)"

  # Determina dove salvare il report. Se eseguiamo lo script dal repo,
  # REPORT_PATH è relativo. Se eseguiamo su jarvis con script copiato in
  # /tmp, scriviamo in /tmp e l'utente farà scp.
  local final_path
  if [[ -d ".planning/phases/01-foundations-repo-sanitize" ]]; then
    final_path="$REPORT_PATH"
  else
    final_path="/tmp/host-audit-final.md"
  fi

  # Re-esegue audit con --output (lo script è già SCRIPT_DIR/host-audit.sh)
  bash "$AUDIT_SCRIPT" --output "$final_path" || true
  log_ok "Report finale: $final_path"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  require_root
  require_audit_script
  require_tailscale_active

  apply_ssh
  apply_docker
  apply_filesystem
  apply_ufw
  apply_post_audit

  log "Apply completato. Verifica il report finale e committalo come evidence."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
