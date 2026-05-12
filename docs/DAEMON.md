# The Toggle Daemon

If you installed in daemon mode (`sudo ./install.sh --daemon`), this is
how it behaves.

## Default state

The Touch Bar shows **media glyphs** left to right:

```
Esc  Bri↓  Bri↑      KbdBri↓  KbdBri↑  ⏮  ⏯  ⏭  🔇  🔉  🔊
```

(There's a small visual gap between Bri↑ and KbdBri↓ where F3/F4 would
have been — the T1 firmware just skips those positions.)

Tap the strip in this state and you get real media keycodes:
`KEY_BRIGHTNESSDOWN`, `KEY_PLAYPAUSE`, `KEY_VOLUMEUP`, etc. Your
desktop environment handles them natively.

## Toggling

The Fn key (bottom-left of main keyboard, next to Control) is the
control surface:

| Action | Effect |
|---|---|
| Tap Fn (quick press + release) | Toggle between media and F-keys |
| Tap Fn again | Toggle back |
| Hold Fn for >700ms | Force-reset to media (default) |
| Double-tap Fn (within 400ms) | Force-reset to media (default) |
| Fn + other key (e.g. Fn+←) | Acts as a hardware modifier; **does NOT** toggle |

The "force-reset to media" cases exist for when state gets out of sync
(e.g. the daemon restarted or you forgot which mode you were in). They
guarantee you can always get back to the default with a known action.

## Why is Fn + arrow special-cased?

On Macs, the Fn key has dual purpose:

- Pressed alone, it's a regular keycode (`KEY_FN`, 464)
- Held with another key, it modifies that other key in firmware
  (Fn+← becomes Home, Fn+→ becomes End, Fn+↑ becomes PageUp, Fn+↓
  becomes PageDown)

If the daemon treated *every* Fn press/release as a toggle, you'd
toggle modes every time you hit Home or End via the Fn shortcut. To
avoid that, the daemon watches for *any* key press while Fn is held
down; if any other key fires during the hold, the subsequent Fn
release does nothing.

## Tuning

If the timing doesn't feel right, edit
`/usr/local/bin/touchbar-daemon` and adjust these constants near
the top:

```python
TAP_MAX_MS = 300          # held shorter than this = tap
LONGPRESS_MIN_MS = 700    # held longer than this = long press
DOUBLETAP_WINDOW_MS = 400 # second tap within this window = double tap
```

Then restart:

```bash
sudo systemctl restart touchbar-daemon.service
```

Common adjustments:

- **Tap detection too aggressive** (you accidentally toggle when
  trying to do Fn-as-modifier shortcuts): increase `TAP_MAX_MS`
  to 400 or 500
- **Long press too short** (your "long press" gets caught as just
  a tap): decrease `LONGPRESS_MIN_MS` to 500
- **Double tap too sensitive** (slow double-clicks miss the window):
  increase `DOUBLETAP_WINDOW_MS` to 600

## What the daemon writes to the journal

```bash
journalctl -u touchbar-daemon.service -f
```

Sample output:

```
[10:21:33] Touch Bar: /dev/input/event6 (Apple Inc. iBridge)
[10:21:33] Main kbd:  /dev/input/event4 (Apple SPI Keyboard)
[10:21:33] Virtual keyboard: touchbar-virtual
[10:21:33] Touch Bar grabbed (exclusive)
[10:21:33] Mode: None -> 2
[10:21:33] Daemon ready. Default: media.
[10:23:14] Tap -> fn
[10:23:14] Mode: 2 -> 1
[10:23:48] Tap -> media
[10:23:48] Mode: 1 -> 2
[10:24:02] Long-press -> media
```

## Suspend / resume

The `touchbar-daemon-resume.service` unit fires after wake-from-suspend
and sends `SIGUSR1` to the daemon. The daemon's signal handler triggers
a full re-init: re-find the iBridge input device (its `eventN` number
may have changed during suspend), re-grab it, and re-send the current
mode to the T1 (which sometimes forgets across sleep).

If the strip stays dark after resume, check that both services are
enabled:

```bash
systemctl is-enabled touchbar-daemon.service
systemctl is-enabled touchbar-daemon-resume.service
```

## Mode 3 ("special")

The T1 driver source mentions a fourth mode (0, 1, 2, 3) labeled
"special." We don't know what it actually shows on the OLED for T1
hardware. If you're curious, set it manually:

```bash
sudo systemctl stop touchbar-daemon.service
sudo python3 -c "
import usb.core
dev = usb.core.find(idVendor=0x05ac, idProduct=0x8600)
detached=[]
for intf in dev.get_active_configuration():
    n = intf.bInterfaceNumber
    try:
        if dev.is_kernel_driver_active(n):
            dev.detach_kernel_driver(n); detached.append(n)
    except: pass
for rt in (0x02,0x03):
    for ri in (0,1,2):
        try: dev.ctrl_transfer(0x40,0x09,(rt<<8)|ri,1,bytes([3]),1000)
        except: pass
for n in detached:
    try: dev.attach_kernel_driver(n)
    except: pass
"
```

Look at the strip, then `sudo systemctl start touchbar-daemon.service`
to return to normal.

If you discover what mode 3 does and want it integrated, open an issue.
