# Troubleshooting

## Simple mode

### The strip is dark after reboot

Run the wake script manually:

```bash
sudo /usr/local/bin/touchbar-wake
```

If you see `iBridge USB device (05ac:8600) not found`, your T1 isn't
enumerating. Check `lsusb | grep 05ac`. If the device is missing, try a
full power-cycle (shutdown, wait 30s, power on) or boot into macOS once
to reset the T1 firmware state.

If the wake script reports success but the strip stays dark, your unit
may need a different `TARGET_INTERFACE` value than 1. See the
"interface mismatch" section below.

### The strip goes dark after resume

```bash
systemctl is-enabled touchbar-resume.service
journalctl -u touchbar-resume.service --since "10 minutes ago"
```

If the service isn't enabled, re-run `sudo ./install.sh`. If it ran but
failed, the journal tells you why. The most common cause is USB taking
longer than 1s to come back up after resume. Increase the
`ExecStartPre=/bin/sleep 1` to 3 in
`/etc/systemd/system/touchbar-resume.service`.

## Daemon mode

### The daemon won't start

```bash
sudo systemctl status touchbar-daemon.service
journalctl -u touchbar-daemon.service -n 50
```

Common errors:

- `iBridge USB device (05ac:8600) not found` — T1 not enumerated on USB
- `iBridge keyboard input device not found` — T1 enumerated but no
  HID interface present (rare)
- `Apple SPI Keyboard not found` — your distro's `applespi` driver isn't
  loaded; check `lsmod | grep applespi` and `dmesg | grep applespi`
- `Missing dependency: python3-evdev` — install it via your package
  manager

### The daemon starts but tapping the strip does nothing

Check that the daemon successfully grabbed the device:

```bash
journalctl -u touchbar-daemon.service | grep -E '(grab|mode)'
```

You should see `Touch Bar grabbed (exclusive)` and `Mode: None -> 2`.

If you see `Grab failed: [Errno 16] Device or resource busy`, jump to the
keyd / input grabber section below.

### keyd (or other input grabber) holds the iBridge

This is the most common post-install issue. The daemon needs exclusive
access to the iBridge keyboard so it can intercept and translate F-keys
to media keys. If another process (almost always `keyd`, occasionally
`kanata`, `interception-tools`, or `xkeysnail`) is already grabbing it,
our grab fails with `[Errno 16] Device or resource busy`.

The install script tries to detect keyd and auto-configure an exclusion.
If you installed keyd *after* running `install.sh`, or if the auto-config
didn't run for some reason, apply it manually:

```bash
sudo tee /etc/keyd/00-ignore-ibridge.conf > /dev/null <<'EOF'
[ids]
-05ac:8600
EOF
sudo systemctl restart keyd
sudo systemctl restart touchbar-daemon.service
journalctl -u touchbar-daemon.service -n 10
```

You should now see `Touch Bar grabbed (exclusive)` in the journal.

For other input remappers, the principle is the same: tell them to
exclude USB device `05ac:8600`. Consult that tool's docs for the
specific syntax. An open issue if your remapper isn't supported by
this exclusion logic and we'll add detection for it.

### Tapping a glyph fires the wrong action

Almost certainly a mode-state desync — the daemon thinks it's in media
mode but the T1 is actually in fn mode, or vice versa. Hold Fn for
~1 second to force-reset to the default media state, or double-tap Fn.
You should see `Long-press -> media` or `Double-tap -> media` in the
journal.

If desyncs happen often, file an issue with the journal output.

### Fn key isn't toggling

In a separate terminal:

```bash
journalctl -u touchbar-daemon.service -f
```

Tap the Fn key (bottom-left of main keyboard). You should see a `Tap ->
fn` or `Tap -> media` line within a couple of seconds.

If nothing logs, the daemon isn't seeing your Fn key events. Likely causes:

- Another tool is grabbing `/dev/input/event<N>` for the SPI keyboard
  (some accessibility tools, `keyd` configured for the main keyboard, etc.)
- Your applespi driver is producing a different keycode than `KEY_FN` (464)
  — run `sudo evtest /dev/input/event<N>` on the SPI keyboard and verify

If `KEY_FN` is logged but classified wrong (e.g. always treated as
modifier-used), try editing the timing constants in
`/usr/local/bin/touchbar-daemon` and `systemctl restart
touchbar-daemon.service`. See `docs/DAEMON.md` for guidance.

### Daemon respawns repeatedly

```bash
journalctl -u touchbar-daemon.service -n 100
```

If you see repeated `Touch Bar read error` followed by re-grabs, your
unit may be in a state where the iBridge input device is unstable
(USB autosuspend kicking in, maybe). Disable autosuspend for it:

```bash
sudo tee /etc/udev/rules.d/99-ibridge-no-autosuspend.rules <<'EOF'
ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8600", ATTR{power/control}="on"
EOF
sudo udevadm control --reload
sudo udevadm trigger
sudo systemctl restart touchbar-daemon.service
```

## Interface mismatch (rare)

`TARGET_INTERFACE = 1` is hardcoded in both the wake script and the
daemon. It works on tested hardware (`MacBookPro13,3`) but may differ on
other revisions. If neither simple nor daemon mode succeeds in lighting
the strip, run this diagnostic to find the right interface:

```bash
sudo systemctl stop touchbar-daemon.service 2>/dev/null
sudo systemctl stop keyd 2>/dev/null

sudo python3 -c '
import usb.core
dev = usb.core.find(idVendor=0x05ac, idProduct=0x8600)
detached = []
for intf in dev.get_active_configuration():
    n = intf.bInterfaceNumber
    try:
        if dev.is_kernel_driver_active(n):
            dev.detach_kernel_driver(n); detached.append(n)
    except: pass
for ifnum in range(0, 5):
    for rt in (0x02, 0x03):
        for ri in (0, 1, 2):
            try:
                dev.ctrl_transfer(0x40, 0x09, (rt<<8)|ri, ifnum,
                                  bytes([1]), 1000)
                print(f"OK ifnum={ifnum} type={rt} id={ri}")
            except: pass
for n in detached:
    try: dev.attach_kernel_driver(n)
    except: pass
'
```

Watch the strip during this. If it lights up, note which `ifnum` was
on screen at the moment. Then edit `/usr/local/bin/touchbar-wake` AND
`/usr/local/bin/touchbar-daemon`, change `TARGET_INTERFACE = 1` to
your discovered value, and `sudo systemctl restart
touchbar-daemon.service`.

**Please also open an issue with your MacBook Pro model and the working
interface number.** We want to make this auto-detect eventually.

## Clean slate

If you've gotten into a tangled state:

```bash
sudo ./uninstall.sh

# Also clean up any old failed attempts at out-of-tree drivers:
sudo dkms remove appleibridge/0.1 --all 2>/dev/null
sudo dkms remove macbook12-spi-driver/0.1 --all 2>/dev/null
sudo rm -rf /usr/src/appleibridge-* /usr/src/macbook12-spi-driver-*
sudo rm -f /etc/modprobe.d/blacklist-appletb-intree.conf
sudo rm -f /etc/modprobe.d/blacklist-apple-ibridge.conf

# Rebuild initramfs to forget everything:
sudo dracut -f              # Fedora
# sudo update-initramfs -u  # Debian/Ubuntu
# sudo mkinitcpio -P        # Arch

sudo reboot
# Then re-run install.sh
```

## Issue template

If you open an issue, please include:

1. `cat /sys/class/dmi/id/product_name`
2. `uname -a`
3. `lsusb | grep 05ac`
4. `cat /proc/bus/input/devices | grep -A 6 -i ibridge`
5. `cat /proc/bus/input/devices | grep -B 1 -A 6 'SPI Keyboard'`
6. `systemctl status touchbar-daemon.service` (if daemon mode)
7. `journalctl -u touchbar-daemon.service -n 100` (if daemon mode)
8. What's working and what isn't
9. What you've already tried
