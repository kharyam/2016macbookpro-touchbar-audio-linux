#!/bin/bash
#
# uninstall.sh — remove T1 Touch Bar support cleanly.

set -euo pipefail

NC='\033[0m'; BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
fail() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
hdr()  { echo; echo -e "${BOLD}==== $* ====${NC}"; }

if [ "$EUID" -ne 0 ]; then
    fail "Run as root: sudo ./uninstall.sh"
fi

hdr "Disabling services"
for svc in \
    touchbar-daemon.service \
    touchbar-daemon-resume.service \
    touchbar-wake.service \
    touchbar-resume.service
do
    if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
        systemctl disable --now "$svc" 2>/dev/null || true
        log "Disabled $svc"
    fi
done

hdr "Removing files"
for f in \
    /usr/local/bin/touchbar-wake \
    /usr/local/bin/touchbar-daemon \
    /etc/systemd/system/touchbar-wake.service \
    /etc/systemd/system/touchbar-resume.service \
    /etc/systemd/system/touchbar-daemon.service \
    /etc/systemd/system/touchbar-daemon-resume.service \
    /etc/keyd/00-ignore-ibridge.conf
do
    if [ -e "$f" ]; then
        rm -f "$f"
        log "Removed $f"
    fi
done

# If we removed the keyd exclusion, restart keyd so it picks up the
# change (otherwise it'll keep the iBridge ungrabbed until next reload).
if systemctl is-active keyd.service >/dev/null 2>&1; then
    systemctl restart keyd.service 2>/dev/null || true
    log "Restarted keyd."
fi

systemctl daemon-reload

hdr "Uninstall complete"
cat <<EOF

The Touch Bar will go dark on the next iBridge power-cycle (reboot).

To also remove Python dependencies you no longer need:
  Fedora:  sudo dnf remove python3-pyusb python3-evdev
  Debian:  sudo apt remove python3-usb python3-evdev
  Arch:    sudo pacman -R python-pyusb python-evdev

EOF
