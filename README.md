# Touch Bar for T1 MacBook Pros on Linux

A userspace workaround that makes the Touch Bar work on 2016 and 2017 MacBook
Pros running Linux. The OLED lights up at boot, the Esc and F1–F12 keys
register correctly, and the strip relights after suspend.

No kernel module, no DKMS, no recompile when your kernel updates. Just a tiny
Python script and two systemd unit files.

## The problem this solves

The 2016 and 2017 MacBook Pros (`MacBookPro13,*` and `MacBookPro14,*`) include
the **T1 "iBridge" chip** that drives the Touch Bar. The mainline Linux kernel
got Touch Bar support in 6.15 (`hid-appletb-kbd`, `hid-appletb-bl`,
`appletbdrm`) — but those drivers only support the **T2** chip in 2018+ Macs.

For T1, you're on your own. The out-of-tree forks that historically targeted
T1 (`roadrunner2`, `marc-git`, `F13-Kr1pt0n` and friends) haven't been updated
for modern kernels. They either fail to build, build but hang on init, or
build and load but never bind to the device.

The good news: the T1 doesn't actually need much. It enumerates as a USB
device, and once you send it a few USB control transfers, it lights up and
starts sending keypress events through `hid-generic` like any other USB
keyboard. That's all this repo does — send those control transfers from
userspace at boot and on resume from suspend.

## What you get

- Touch Bar OLED lit at the login screen and throughout your session
- Working Esc and F1–F12 keys, sent as standard keycodes
- Relights automatically after resume from suspend / hibernate
- Survives kernel updates (it's not a kernel module)

## What you don't get

- Dynamic per-app Touch Bar layouts (the "Touch Bar adapts to the app you're
  using" thing from macOS). That requires deep app integration that doesn't
  exist on Linux.
- Touch Bar brightness control via the existing Fn keys
- Anything fancy. This is a wake-up shim, not a driver.

## Compatibility

**Tested on:**

- `MacBookPro13,3` (15-inch 2016 with Touch Bar) on Fedora 44 / kernel 7.0.4

**Should work on:**

- `MacBookPro13,2` (13-inch 2016 with Touch Bar)
- `MacBookPro14,2` (13-inch 2017 with Touch Bar)
- `MacBookPro14,3` (15-inch 2017 with Touch Bar)

**Not applicable:**

- `MacBookPro13,1` and `MacBookPro14,1` — these are the entry-level 13-inch
  models without a Touch Bar (function row only). Nothing to fix.
- 2018+ MacBook Pros — these have the T2 chip and are supported by mainline
  kernel drivers as of 6.15. Just use `tiny-dfr` or wait for distro packaging.

If `lsusb` on your Mac shows `05ac:8600` (Apple Inc. iBridge), you have a T1
and this should work.

## Install

You need `python3-pyusb` and a systemd-based Linux distro.

**Fedora / RHEL / CentOS / Rocky:**

```bash
sudo dnf install -y python3-pyusb
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

**Debian / Ubuntu / Linux Mint / Pop!_OS:**

```bash
sudo apt install -y python3-usb
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

**Arch / Manjaro / EndeavourOS:**

```bash
sudo pacman -S python-pyusb
git clone https://github.com/YOUR-USERNAME/mbp-t1-touchbar-linux.git
cd mbp-t1-touchbar-linux
sudo ./install.sh
```

Reboot. The strip should be lit at the login screen.

## Verify it's working

```bash
# Strip should be lit. If not:
sudo /usr/local/bin/touchbar-wake

# Both services should be enabled:
systemctl status touchbar-wake.service
systemctl status touchbar-resume.service

# Tap a Fn key on the strip and confirm it registers:
sudo showkey
```

Close the lid (or `systemctl suspend`), wait a second, reopen. The strip
should relight within a second.

## Uninstall

```bash
sudo ./uninstall.sh
```

## How it works

In one paragraph: the T1 iBridge enumerates as USB device `05ac:8600`. The
kernel's `hid-generic` driver claims it as a keyboard but doesn't know how
to actually wake it. The chip needs an HID `Set_Report` over USB control
endpoint 0 telling it which mode to enter (Esc-only, Esc+Fn, etc.), plus
another telling it to turn the OLED on. Once it has those, it starts sending
keypress events through the normal HID path. We do this from Python via
PyUSB at boot and on resume from suspend.

See [`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md) for the technical details
including the exact USB protocol, why this isn't a kernel driver, and what
would be needed to upstream T1 support properly.

## Troubleshooting

Strip stays dark, keys don't register, service fails to start, etc:
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

## Bonus: speakers

The same vintage of MacBook Pro has a Cirrus CS8409 audio codec whose
speaker amp needs Apple-specific HDA init verbs that aren't in any mainline
or distro firmware package. Headphones work out of the box on modern kernels;
internal speakers need davidjo's out-of-tree driver, built with a custom DKMS
config that handles the kernel 6.17+ HDA directory reshuffle.

See [`docs/AUDIO.md`](docs/AUDIO.md) for the recipe.

## Credits

- **F13-Kr1pt0n's** [`macbook-pro-touchbar-driver`](https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver)
  fork and its predecessors by **roadrunner2** and **marc-git** — for the
  HID command structure, the mode/display protocol, and years of T1
  reverse engineering work that this repo distills into a few lines of Python.
- The mainline `hid-appletb-*` drivers (T2-only) — for documentation of the
  HID report structure that's similar enough on T1 to be useful.
- **davidjo's** [`snd_hda_macbookpro`](https://github.com/davidjo/snd_hda_macbookpro) —
  for the audio side of the puzzle.
- **Fábio Ranquetat's** [Medium guide](https://medium.com/@ranquetat/how-to-install-kernel-6-17-and-fix-sound-on-macs-cirrus-cs8409-running-linux-8641c1cf4d98)
  on building the audio driver against post-6.17 kernels.

## Contributing

PRs welcome, especially:

- Confirmation of working on `MacBookPro13,2`, `MacBookPro14,2`,
  `MacBookPro14,3` (please open an issue with your model and distro)
- Packaging for AUR / COPR / PPA
- Wake-up trigger that's more elegant than `sleep 3` (currently the boot
  service waits 3s to make sure USB is enumerated)

## License

MIT. See [`LICENSE`](LICENSE).
