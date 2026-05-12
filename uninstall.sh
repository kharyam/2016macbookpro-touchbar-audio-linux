#!/bin/bash
#
# uninstall.sh - remove the T1 Touch Bar wake script and systemd services.

set -euo pipefail

NC='\033[0m'; BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
hdr()  { echo; echo -e "${BOLD}==== $* ====${NC}"; }

if [ "$EUID" -ne 0 ]; then
    fail "Must run as root. Try: sudo ./uninstall.sh"
fi

hdr "Disabling services"

for svc in touchbar-wake.service touchbar-resume.service; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
        systemctl disable --now "$svc" 2>/dev/null || true
        log "Disabled $svc"
    else
        log "$svc not installed; skipping."
    fi
done

hdr "Removing files"

for f in \
    /usr/local/bin/touchbar-wake \
    /etc/systemd/system/touchbar-wake.service \
    /etc/systemd/system/touchbar-resume.service
do
    if [ -e "$f" ]; then
        rm -f "$f"
        log "Removed $f"
    fi
done

systemctl daemon-reload

hdr "Uninstall complete"

cat <<EOF

The Touch Bar will go dark on the next reboot (or whenever the iBridge is
next power-cycled).

To remove the python3-pyusb dependency if you no longer need it:
  Fedora:  sudo dnf remove python3-pyusb
  Debian:  sudo apt remove python3-usb
  Arch:    sudo pacman -R python-pyusb

EOF
