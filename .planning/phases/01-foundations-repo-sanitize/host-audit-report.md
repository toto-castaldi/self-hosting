# Host Audit Report — jarvis

**Hostname:** jarvis  
**OS:** Ubuntu 26.04 LTS  
**Kernel:** 7.0.0-15-generic  
**Run at:** 2026-05-25T15:56:34+00:00  
**Audit script version:** v1  

---

## HOST-01: SSH key-only + unattended-upgrades

| Check | Expected | Actual | Status |
| --- | --- | --- | --- |
| PasswordAuthentication | no | no | OK |
| PubkeyAuthentication | yes | yes | OK |
| PermitRootLogin | no/prohibit-password | prohibit-password | OK |
| KbdInteractiveAuthentication | no | no | OK |
| unattended-upgrades service | active | active | OK |
| unattended-upgrades security source | uncommented | presente | OK |

## HOST-02: Docker + toto senza sudo

| Check | Expected | Actual | Status |
| --- | --- | --- | --- |
| docker binary | presente | Docker version 29.4.3, build 055a478 | OK |
| docker compose plugin | v2 presente | Docker Compose version v5.1.3 | OK |
| toto in docker group | membro | membro | OK |
| docker info senza sudo (toto) | exit 0 | exit 0 | OK |

## HOST-03: Tailscale running

| Check | Expected | Actual | Status |
| --- | --- | --- | --- |
| tailscaled service | active | active | OK |
| tailscale BackendState | Running | Running | OK |
| MagicDNSSuffix | non vuoto | <magicdns-suffix-scrubbed> | OK |
| tailscale IPv4 in 100.64.0.0/10 | match CGNAT | 100.113.232.126 | OK |
| interfaccia tailscale0 | esistente | presente | OK |

## HOST-04: Filesystem layout

| Check | Expected | Actual | Status |
| --- | --- | --- | --- |
| /home/toto/jarvis | toto:toto 755/750 | toto:toto 755 | OK |
| /home/toto/lumio | toto:toto 755/750 | toto:toto 755 | OK |
| /etc/cloudflared | root:cloudflared 750 | root:cloudflared 750 | OK |
| group cloudflared | esistente | presente | OK |

## HOST-05: ufw default-deny + SSH via tailscale0

| Check | Expected | Actual | Status |
| --- | --- | --- | --- |
| ufw binary | presente | presente | OK |
| ufw Status | active | active | OK |
| ufw Default incoming | deny | deny | OK |
| regola SSH su tailscale0 | ALLOW IN 22/tcp on tailscale0 | presente | OK |
| no 22/tcp ALLOW Anywhere | assente | assente | OK |

---

## Summary

- **OK:** 24
- **MISSING:** 0
- **WARN:** 0
- **Overall:** OK

_Stato hardened OK — nessuna azione richiesta._