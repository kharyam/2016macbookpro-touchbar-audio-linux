# Touch Bar for T1 MacBook Pros on Linux

Get the Touch Bar working on 2016 and 2017 MacBook Pros under Linux — the
OLED lights up at boot, the keys work, you can toggle between media controls
and F-keys with the Fn key, and everything survives suspend.

No kernel module. No DKMS. No recompile on kernel updates.

## What's in the box

Two install options. Both keep the Touch Bar lit. The recommended one adds
proper media-key behavior.

### Simple mode

Just keeps the strip lit with the **Esc + F1–F12** layout. The keys work as
F-keys. That's it. Minimal dependencies, minimal moving parts.

### Daemon mode (recommended)

The strip defaults to showing **media glyphs** — brightness, keyboard
backlight, rewind / play-pause / fast forward, mute, volume. Tapping those
glyphs does the right thing: brightness changes, volume adjusts,
music plays/pauses. **Tap the Fn key** (bottom-left of the main keyboard)
to toggle to F-keys mode; tap again to return.

The daemon does this by grabbing the iBridge keyboard exclusively, watching
the SPI keyboard for `KEY_FN` events, and translating the Touch Bar's F-key
events to media keycodes on the fly via a uinput virtual keyboard. It also
sends the appropriate mode-change command to the T1 chip whenever you
toggle, so the OLED glyphs update to match.

## Background

The 2016 and 2017 MacBook Pros (`MacBookPro13,*` and `MacBookPro14,*`)
include the **T1 "iBridge" chip** that drives the Touch Bar. The mainline
Linux kernel got Touch Bar support in 6.15 (`hid-appletb-kbd`,
`hid-appletb-bl`, `appletbdrm`) — but those drivers only support the **T2**
chip in 2018+ Macs.

For T1, the existing out-of-tree forks (`roadrunner2`, `marc-git`,
`F13-Kr1pt0n`) don't build on modern kernels. This repo skips the kernel
driver path entirely: the T1 just needs a few USB control transfers at boot
to wake up, after which it sends keypress events through `hid-generic` like
any other USB keyboard. PyUSB sends those control transfers from userspace.
PyEvdev grabs and translates the resulting keypresses. systemd ties it all
together.

## What you get

- Touch Bar OLED lit at the login screen and throughout your session
- Working Esc key and F1–F12 (or media keys, depending on mode)
- (Daemon mode) Fn key toggles between layouts, with the OLED glyphs and
  the actual keycodes both changing in sync
- (Daemon mode) Fn + arrow keys still work as Home/End/PageUp/PageDown
  without triggering a toggle
- Relights automatically after resume from suspend / hibernate
- Survives kernel updates

## Compatibility

**Tested on:**

- `MacBookPro13,3` (15-inch 2016 with Touch Bar) on Fedora 44 / kernel 7.0.4

**Should work on:**

- `MacBookPro13,2` (13-inch 2016 with Touch Bar)
- `MacBookPro14,2` (13-inch 2017 with Touch Bar)
- `MacBookPro14,3` (15-inch 2017 with Touch Bar)

**Not applicable:**

- 13-inch 2016/2017 models without Touch Bar (function row only)
- 2018+ MacBook Pros (T2 — supported by mainline kernel)

If `lsusb` on your Mac shows `05ac:8600` (Apple Inc. iBridge), you have a T1.

## Install

You need a systemd-based Linux and Python 3 with `pyusb`. For daemon mode
you also need `evdev`.

**Fedora / RHEL / CentOS / Rocky:**

```bash
sudo dnf install -y python3-pyusb python3-evdev
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

**Debian / Ubuntu / Linux Mint / Pop!_OS:**

```bash
sudo apt install -y python3-usb python3-evdev
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

**Arch / Manjaro / EndeavourOS:**

```bash
sudo pacman -S python-pyusb python-evdev
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

The installer will prompt you to choose simple or daemon mode. You can also
pass `--simple` or `--daemon` to skip the prompt.

Reboot. The strip should be lit at the login screen.

## Switching modes later

```bash
sudo ./install.sh --simple    # downgrade to lit-strip-only
sudo ./install.sh --daemon    # upgrade to full toggle daemon
```

The installer cleanly removes one mode's services before installing the
other's, so flipping back and forth is safe.

## Verify

**Simple mode:**

```bash
systemctl status touchbar-wake.service
systemctl status touchbar-resume.service
# Both should be "active" / loaded.
```

**Daemon mode:**

```bash
systemctl status touchbar-daemon.service
journalctl -u touchbar-daemon.service -f
# Tap keys on the Touch Bar; the journal will show the daemon working.
```

Test the resume case in both modes: `systemctl suspend`, wait, reopen.
Strip should relight within a second.

## Uninstall

```bash
sudo ./uninstall.sh
```

Cleans everything regardless of which mode you installed.

## Documentation

- [`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md) — the USB protocol and
  why this isn't a kernel driver
- [`docs/DAEMON.md`](docs/DAEMON.md) — daemon architecture and behavior
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — common issues
- [`docs/AUDIO.md`](docs/AUDIO.md) — getting internal speakers working
  (bonus, unrelated to the Touch Bar)

## Credits

- **F13-Kr1pt0n's** [`macbook-pro-touchbar-driver`](https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver)
  fork and its predecessors by **roadrunner2** and **marc-git** — for the
  HID command structure, the mode/display protocol, and years of T1
  reverse engineering work that this repo distills into a few lines of Python.
- The mainline `hid-appletb-*` drivers (T2-only) — for documentation of the
  HID report structure.
- **davidjo's** [`snd_hda_macbookpro`](https://github.com/davidjo/snd_hda_macbookpro) —
  for the audio side of the puzzle.
- **Fábio Ranquetat's** [Medium guide](https://medium.com/@ranquetat/how-to-install-kernel-6-17-and-fix-sound-on-macs-cirrus-cs8409-running-linux-8641c1cf4d98)
  on building the audio driver against post-6.17 kernels.

## Contributing

PRs welcome. Things that would help:

- Confirmation on `MacBookPro13,2`, `MacBookPro14,2`, `MacBookPro14,3`
- Packaging for AUR / COPR / PPA
- Mode-3 ("special") investigation — what's on the OLED?
- A udev rule so the daemon can run as a non-root user

## License

MIT. See [`LICENSE`](LICENSE).
