#!/bin/bash
#
# install.sh — install T1 Touch Bar support on Linux.
#
# Two modes:
#   Default (simple):  Just keep the strip lit at boot, no key remapping.
#                      Esc + F1-F12 layout. Minimal dependencies.
#   --daemon:          Run the toggle daemon. Default state is media glyphs
#                      with F-keys translated to media keys. Tap Fn to toggle
#                      to F-key layout. Requires python3-evdev.
#
# Idempotent: safe to re-run.

set -euo pipefail

NC='\033[0m'; BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
hdr()  { echo; echo -e "${BOLD}==== $* ====${NC}"; }

INSTALL_MODE="ask"
for arg in "$@"; do
    case "$arg" in
        --daemon)  INSTALL_MODE="daemon" ;;
        --simple)  INSTALL_MODE="simple" ;;
        -h|--help)
            cat <<EOF
Usage: sudo ./install.sh [OPTION]

  --simple   Install the simple wake script only (lights the strip at boot)
  --daemon   Install the toggle daemon (Fn key cycles between media and F-keys)
  (none)     Interactively ask which to install

EOF
            exit 0
            ;;
        *) fail "Unknown argument: $arg" ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    fail "Run as root: sudo ./install.sh"
fi
if ! command -v systemctl >/dev/null 2>&1; then
    fail "This installer requires systemd."
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hdr "Hardware check"
if [ -r /sys/class/dmi/id/product_name ]; then
    product=$(cat /sys/class/dmi/id/product_name)
    log "Detected: $product"
    case "$product" in
        MacBookPro13,*|MacBookPro14,*) log "Compatible model." ;;
        *) warn "Untested model. Continuing anyway." ;;
    esac
fi
if ! lsusb 2>/dev/null | grep -q '05ac:8600'; then
    fail "No Apple iBridge USB device (05ac:8600) detected. Aborting."
fi
log "iBridge USB device found."

if [ "$INSTALL_MODE" = "ask" ]; then
    hdr "Which install mode?"
    cat <<EOF
[1] Simple — just keep the Touch Bar lit (Esc + F1-F12). Minimal deps.
[2] Daemon — Fn key toggles between media glyphs and F-keys, with media
    keycode translation (brightness, volume, play/pause). Requires
    python3-evdev. RECOMMENDED.
EOF
    read -r -p "Choice [1/2, default 2]: " choice
    case "${choice:-2}" in
        1) INSTALL_MODE="simple" ;;
        2) INSTALL_MODE="daemon" ;;
        *) fail "Unrecognized choice." ;;
    esac
fi
log "Install mode: $INSTALL_MODE"

hdr "Python dependency check"
if ! python3 -c "import usb.core" >/dev/null 2>&1; then
    fail "python3 pyusb not found. Install: sudo dnf install python3-pyusb (Fedora) / sudo apt install python3-usb (Debian) / sudo pacman -S python-pyusb (Arch)"
fi
log "pyusb OK."
if [ "$INSTALL_MODE" = "daemon" ]; then
    if ! python3 -c "import evdev" >/dev/null 2>&1; then
        fail "python3 evdev not found. Install: sudo dnf install python3-evdev (Fedora) / sudo apt install python3-evdev (Debian) / sudo pacman -S python-evdev (Arch)"
    fi
    log "evdev OK."
fi

hdr "Installing files"
install -m 0755 "$SCRIPT_DIR/src/touchbar-wake" /usr/local/bin/touchbar-wake
log "/usr/local/bin/touchbar-wake"

if [ "$INSTALL_MODE" = "daemon" ]; then
    install -m 0755 "$SCRIPT_DIR/src/touchbar-daemon" /usr/local/bin/touchbar-daemon
    log "/usr/local/bin/touchbar-daemon"
fi

cleanup_simple_services() {
    for svc in touchbar-wake.service touchbar-resume.service; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
            systemctl disable --now "$svc" 2>/dev/null || true
        fi
        rm -f "/etc/systemd/system/$svc"
    done
}
cleanup_daemon_services() {
    for svc in touchbar-daemon.service touchbar-daemon-resume.service; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
            systemctl disable --now "$svc" 2>/dev/null || true
        fi
        rm -f "/etc/systemd/system/$svc"
    done
}

if [ "$INSTALL_MODE" = "simple" ]; then
    cleanup_daemon_services
    install -m 0644 "$SCRIPT_DIR/systemd/touchbar-wake.service" /etc/systemd/system/
    install -m 0644 "$SCRIPT_DIR/systemd/touchbar-resume.service" /etc/systemd/system/
    log "/etc/systemd/system/touchbar-wake.service"
    log "/etc/systemd/system/touchbar-resume.service"
else
    cleanup_simple_services
    install -m 0644 "$SCRIPT_DIR/systemd/touchbar-daemon.service" /etc/systemd/system/
    install -m 0644 "$SCRIPT_DIR/systemd/touchbar-daemon-resume.service" /etc/systemd/system/
    log "/etc/systemd/system/touchbar-daemon.service"
    log "/etc/systemd/system/touchbar-daemon-resume.service"
fi

hdr "Enabling systemd units"
systemctl daemon-reload
if [ "$INSTALL_MODE" = "simple" ]; then
    systemctl enable touchbar-wake.service touchbar-resume.service
else
    systemctl enable touchbar-daemon.service touchbar-daemon-resume.service
fi
log "Services enabled."

hdr "Starting now"
if [ "$INSTALL_MODE" = "simple" ]; then
    /usr/local/bin/touchbar-wake || warn "Wake command exited non-zero."
else
    systemctl start touchbar-daemon.service || warn "Daemon start failed (see logs)."
    sleep 2
    systemctl --no-pager status touchbar-daemon.service | head -15 || true
fi

hdr "Installation complete ($INSTALL_MODE mode)"

if [ "$INSTALL_MODE" = "simple" ]; then
    cat <<EOF

The Touch Bar should be lit with Esc + F1-F12. Reboot to confirm it works
at startup, and try suspend/resume.

To upgrade to the toggle daemon later:
    sudo ./install.sh --daemon

EOF
else
    cat <<EOF

The toggle daemon is running. Default state is media glyphs.

  - Tap the Fn key (bottom-left of main keyboard) to toggle to F-keys.
  - Tap Fn again to return to media.
  - Hold Fn for >700ms, or double-tap, to force-reset to media.
  - Tapping the strip in media mode sends real media keycodes.

To see what the daemon is doing in real time:
    journalctl -u touchbar-daemon.service -f

To downgrade to the simple wake-only setup:
    sudo ./install.sh --simple

EOF
fi
