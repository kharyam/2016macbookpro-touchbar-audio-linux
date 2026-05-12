#!/bin/bash
#
# install.sh - install the T1 Touch Bar wake script and systemd services.
#
# Idempotent: safe to re-run.

set -euo pipefail

NC='\033[0m'; BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
hdr()  { echo; echo -e "${BOLD}==== $* ====${NC}"; }

# --- pre-flight checks ---

if [ "$EUID" -ne 0 ]; then
    fail "Must run as root. Try: sudo ./install.sh"
fi

if ! command -v systemctl >/dev/null 2>&1; then
    fail "This installer requires systemd. Your distro doesn't appear to use it."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- hardware check ---

hdr "Hardware check"

if [ -r /sys/class/dmi/id/product_name ]; then
    product=$(cat /sys/class/dmi/id/product_name)
    log "Detected: $product"
    case "$product" in
        MacBookPro13,*|MacBookPro14,*)
            log "Compatible MacBook Pro model."
            ;;
        *)
            warn "This model is not in the tested list (MacBookPro13,*/14,*)."
            warn "Continuing anyway — if you have an iBridge it should still work."
            ;;
    esac
else
    warn "Cannot read DMI info. Continuing."
fi

if ! lsusb 2>/dev/null | grep -q '05ac:8600'; then
    fail "No Apple iBridge USB device (05ac:8600) detected. This Mac doesn't have a T1 Touch Bar, or the chip is in a fault state. Aborting."
fi
log "iBridge USB device found."

# --- python / pyusb check ---

hdr "Python / pyusb check"

if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 not found. Install it via your package manager."
fi

if ! python3 -c "import usb.core" >/dev/null 2>&1; then
    fail "python3 pyusb library not found. Install it first:
    Fedora:  sudo dnf install python3-pyusb
    Debian:  sudo apt install python3-usb
    Arch:    sudo pacman -S python-pyusb"
fi
log "pyusb is available."

# --- install files ---

hdr "Installing files"

install -m 0755 "$SCRIPT_DIR/src/touchbar-wake" /usr/local/bin/touchbar-wake
log "/usr/local/bin/touchbar-wake"

install -m 0644 "$SCRIPT_DIR/systemd/touchbar-wake.service" /etc/systemd/system/touchbar-wake.service
log "/etc/systemd/system/touchbar-wake.service"

install -m 0644 "$SCRIPT_DIR/systemd/touchbar-resume.service" /etc/systemd/system/touchbar-resume.service
log "/etc/systemd/system/touchbar-resume.service"

# --- enable services ---

hdr "Enabling systemd services"

systemctl daemon-reload
systemctl enable touchbar-wake.service
systemctl enable touchbar-resume.service
log "Services enabled (will run on next boot and on resume)."

# --- immediate test ---

hdr "Test run"

log "Running touchbar-wake now — look at the Touch Bar strip."
if /usr/local/bin/touchbar-wake; then
    log "Wake command sent successfully."
    log "Did the strip light up showing Esc + F1-F12?"
    log "If yes, you're done. Reboot to confirm it works at startup."
    log "If no, see docs/TROUBLESHOOTING.md."
else
    warn "Wake command exited non-zero. Check the message above."
fi

hdr "Installation complete"

cat <<EOF

What was installed:
  /usr/local/bin/touchbar-wake               (Python wake script)
  /etc/systemd/system/touchbar-wake.service  (runs at boot)
  /etc/systemd/system/touchbar-resume.service (runs after resume)

Next steps:
  1. Reboot to confirm the strip is lit at the login screen.
  2. After reboot, test suspend/resume:
       systemctl suspend
     (then resume and verify the strip relights)
  3. Tap an Fn key on the strip and verify it registers:
       sudo showkey

To uninstall: sudo ./uninstall.sh

EOF
