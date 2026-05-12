# How it works

Technical walkthrough of why the Touch Bar is dark by default on Linux,
what we send to the T1 to wake it up, and how the optional daemon does
mode toggling.

## The T1 chip

The 2016 and 2017 MacBook Pros include the **T1**, Apple's first ARM
co-processor in a Mac. It runs a stripped-down variant of watchOS and is
responsible for the Touch Bar OLED, Touch ID, the FaceTime HD camera,
secure SSD encryption keys, and bridging the iBridge USB device to the
main system.

Apple replaced the T1 with the much more capable T2 in 2018. **Mainline
Linux kernel support for the Touch Bar (landed in 6.15) is for T2 only.**
T1 has never had mainline support.

## What Linux sees

```
$ lsusb | grep 05ac
Bus 001 Device 002: ID 05ac:8600 Apple, Inc. iBridge
```

The iBridge is a USB composite device. The kernel's HID core enumerates
its interfaces and binds `hid-generic` to the ones that present as
keyboards:

```
input: Apple Inc. iBridge as /devices/.../0003:05AC:8600.0001/input/input6
hid-generic 0003:05AC:8600.0001: input,hidraw0: USB HID v1.01 Keyboard
```

So the kernel thinks there's a USB keyboard attached. But tap the strip —
nothing happens. The OLED is dark. The device is enumerated but inert.

## Why is it inert?

The T1 boots into a low-power state where the OLED is off and it doesn't
generate input events. macOS sends it a sequence of USB control transfers
during boot to wake it up. Linux, without a T1-aware driver, sends nothing.

The wake sequence is documented in the source of the out-of-tree T1
drivers (the chain goes cb22 → roadrunner2 → marc-git → F13-Kr1pt0n).
It consists of two HID `Set_Report` requests over USB control endpoint 0.

### The mode command

| Field | Value | Meaning |
|---|---|---|
| `bmRequestType` | `0x40` | OUT, vendor request, recipient = device |
| `bRequest` | `0x09` | `HID_SET_REPORT` |
| `wValue` | `(report_type << 8) | report_id` | Which report this is |
| `wIndex` | `1` (on tested hardware) | Interface number |
| `wLength` | `1` | One byte of payload |
| data | `0x01` | Mode: 0=Esc only, 1=Esc+Fn, 2=Esc+media, 3=off |

### The display command

| Field | Value | Meaning |
|---|---|---|
| `bmRequestType` | `0x21` | OUT, class request, recipient = interface |
| `bRequest` | `0x09` | `HID_SET_REPORT` |
| `wValue` | `(0x03 << 8) | report_id` | Feature report |
| `wIndex` | `1` | Interface number |
| `wLength` | `11` | 11-byte payload |
| data | `[id, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]` | Display state = on |

## The "which report?" problem

A USB HID Set_Report request is addressed to a specific *report ID* and
*report type* on the device. A real kernel driver would parse the HID
descriptor at probe time to find the right values by looking for fields
with specific usage codes.

Doing that in Python is a chunk of code. The search space is small enough
(2 types × 3 plausible IDs = 6 combinations) that brute force is
cheaper. The wrong combinations get silently rejected by the device, the
right one wakes the chip. We don't need to know which one was right —
we just need *one* of them to be right.

## Mode 2 — the media OLED is firmware-rendered, but the keycodes are F-keys

Here's a fun finding. On a 2016 MBP, sending **mode = 2** to the T1
causes the OLED to display media glyphs: brightness, keyboard backlight,
rewind, play/pause, fast forward, mute, volume up/down. So far so good.

But tap one of those glyphs and the iBridge sends... a regular `KEY_F1`
or `KEY_F2` etc. The glyphs are firmware-rendered but the keycodes the
device produces are unchanged from mode 1.

That's actually how macOS works too. The macOS HID layer intercepts these
F-keys and translates them to brightness / volume / media actions based
on which Touch Bar mode is currently displayed.

The daemon in this repo does the same translation:

| OLED glyph | T1 sends | We translate to |
|---|---|---|
| Esc | KEY_ESC | KEY_ESC (unchanged) |
| Brightness ↓ | KEY_F1 | KEY_BRIGHTNESSDOWN |
| Brightness ↑ | KEY_F2 | KEY_BRIGHTNESSUP |
| Kbd brightness ↓ | KEY_F5 | KEY_KBDILLUMDOWN |
| Kbd brightness ↑ | KEY_F6 | KEY_KBDILLUMUP |
| Rewind | KEY_F7 | KEY_PREVIOUSSONG |
| Play/Pause | KEY_F8 | KEY_PLAYPAUSE |
| Fast forward | KEY_F9 | KEY_NEXTSONG |
| Mute | KEY_F10 | KEY_MUTE |
| Volume ↓ | KEY_F11 | KEY_VOLUMEDOWN |
| Volume ↑ | KEY_F12 | KEY_VOLUMEUP |

Notice F3 and F4 are skipped. The T1 firmware leaves a visual gap in the
mode 2 layout between brightness and keyboard-brightness; touches in
that gap produce nothing.

## How the daemon does the toggle

`touchbar-daemon` runs as root and:

1. Sends mode-2 to the T1 at startup so the OLED shows media glyphs
2. Grabs `/dev/input/event<N>` (the iBridge keyboard) exclusively via
   `EVIOCGRAB`, so the raw F-key events don't reach apps directly
3. Creates a `uinput` virtual keyboard called `touchbar-virtual` and
   emits translated events through it. Apps see media keycodes from
   `touchbar-virtual`, never the raw F-keys from the iBridge.
4. Watches the main `Apple SPI Keyboard` for `KEY_FN` events (the Fn key
   sends a regular keycode 464 on press and release)
5. Tracks a state machine for Fn:
   - Press: start a timer, clear the "modifier used" flag
   - Any other key pressed while Fn is held: set "modifier used" flag
     so we know Fn was being used as a hardware modifier (Fn+arrow etc.)
   - Release: if "modifier used" is true, do nothing. Otherwise, classify
     by duration and recency: a short clean press is a tap (toggle), a
     long press is a force-reset to media, two taps in quick succession
     is a double-tap reset.
6. When mode changes, sends the appropriate USB command to the T1 to
   update the OLED glyphs, then switches the internal translation table

After resume from suspend, the T1 sometimes forgets its mode. A small
companion service (`touchbar-daemon-resume.service`) sends `SIGUSR1` to
the daemon after wake, and the daemon re-initializes (re-finds the
input device, re-grabs it, re-sends the current mode).

## Why not a kernel driver?

The existing T1 driver forks (linked in the README) are all unmaintained
and don't build on current kernels. Porting them is a real C kernel
project: the HID subsystem, HDA framework, and DRM all got significant
API changes in 2025–2026.

For something that just needs to send a few USB control transfers at
boot and remap a few keycodes, userspace is the right place. PyUSB,
PyEvdev, uinput, and systemd already exist and are easy to compose.

If you wanted to upstream T1 support properly, you'd write a proper
`hid-apple-ibridge` driver that:

- Matches on the iBridge USB ID
- Parses the HID descriptor for the mode/display report fields
  (so we don't have to brute force them)
- Provides a sysfs knob for mode selection
- Coordinates with a backported version of `appletbdrm` (the mainline
  T2 DRM driver) to optionally render Touch Bar content beyond what
  the T1 firmware does natively

The reverse engineering work for that is already done in the F13-Kr1pt0n
fork. It just needs porting to current kernel APIs.

## Why root?

PyUSB on Linux goes through `libusb`, which needs either:

- Read/write permission on the underlying `/dev/bus/usb/NNN/MMM` node, or
- The ability to detach kernel drivers from interfaces

The daemon also creates a `uinput` device, which usually needs root.

A future improvement would be a udev rule + `uaccess` tag so the daemon
could run as a regular user in the input group. PRs welcome.
