# How it works

A walk through the technical details of why the Touch Bar is dark by default
on Linux and what we do to fix it.

## The T1 chip

The 2016 and 2017 MacBook Pros include the **T1**, Apple's first ARM
co-processor in a Mac. It runs a stripped-down variant of watchOS (yes,
really) and is responsible for:

- Driving the Touch Bar OLED
- Reading touches on the strip and reporting them as HID events
- Talking to the Touch ID fingerprint sensor
- Handling the FaceTime HD camera
- Securely managing the SSD encryption keys
- Bridging the iBridge USB device to the main system

Apple replaced the T1 with the much more capable T2 in 2018 (MBP 15-inch) and
2019 (rest of the lineup). The T2 has its own SEP, runs bridgeOS, and is
fundamentally different from the T1. **Mainline Linux kernel support for the
Touch Bar (landed in 6.15) is for T2 only.** T1 has never had mainline
support and probably never will.

## What Linux sees

Boot a 2016 MBP into Linux and run `lsusb`. You'll see:

```
Bus 001 Device 002: ID 05ac:8600 Apple, Inc. iBridge
```

The iBridge is a USB composite device. The kernel's HID core enumerates its
interfaces and binds `hid-generic` to the ones that present as keyboards. You
can see this in `dmesg`:

```
input: Apple Inc. iBridge as /devices/.../1-3:1.2/0003:05AC:8600.0001/input/input6
hid-generic 0003:05AC:8600.0001: input,hidraw0: USB HID v1.01 Keyboard [Apple Inc. iBridge]
```

So the kernel thinks there's a USB keyboard attached. But tap the strip and
nothing happens. The OLED is dark. The device is enumerated but inert.

## Why is it inert?

The T1 boots into a low-power state where the OLED is off and it doesn't
generate input events. macOS sends it a sequence of USB control transfers
during boot to wake it up and configure it. Linux, without a T1-aware driver,
sends nothing.

The wake sequence the T1 expects is documented in the source of the out-of-tree
T1 drivers (`apple-ib-tb.c` in F13-Kr1pt0n's fork, which was forked from
marc-git, which was forked from roadrunner2, which was based on cb22's
original 2017 reverse engineering work). It consists of two HID
`Set_Report` requests over USB control endpoint 0:

### The mode command

| Field | Value | Meaning |
|---|---|---|
| `bmRequestType` | `0x40` | OUT, vendor request, recipient = device |
| `bRequest` | `0x09` | `HID_SET_REPORT` |
| `wValue` | `(report_type << 8) | report_id` | Which report this is |
| `wIndex` | `1` (on tested hardware) | Interface number |
| `wLength` | `1` | One byte of payload |
| data | `0x01` | Mode: 0=Esc only, 1=Esc+Fn, 2=Esc+special, 3=off |

### The display command

| Field | Value | Meaning |
|---|---|---|
| `bmRequestType` | `0x21` | OUT, class request, recipient = interface |
| `bRequest` | `0x09` | `HID_SET_REPORT` |
| `wValue` | `(0x03 << 8) | report_id` | Feature report |
| `wIndex` | `1` | Interface number |
| `wLength` | `11` | 11-byte payload |
| data | `[id, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]` | Display state byte = 1 (on) |

## The "which report?" problem

A USB HID Set_Report request is addressed to a specific *report ID* and
*report type* on the device. Normally, a driver finds these by parsing the
HID descriptor at probe time and looking for fields with specific usage
codes (`HID_GD_KEYBOARD` / `HID_USAGE_MODE` for the mode command,
`HID_USAGE_APPLE_APP` / `HID_USAGE_DISP` for display).

Doing that descriptor parsing from a Python script is a chunk of code. The
report IDs are also somewhat consistent across T1 units, but not perfectly —
slight firmware variations exist.

Pragmatic solution: brute force. There are only six plausible combinations:

- report_type = `0x02` (Output) or `0x03` (Feature)
- report_id = `0`, `1`, or `2`

Six USB control transfers take a few milliseconds total. The wrong ones get
silently rejected by the device. The right one wakes the chip. We don't need
to know which one was right, we just need *one* of them to be right.

## Why not just write a kernel driver?

There are several existing kernel drivers for the T1 (linked in the README).
They're all unmaintained, none of them build cleanly on recent kernels, and
the few that build hang on init. Porting them to current kernels would be a
real C kernel project — the HID subsystem, HDA framework, and DRM all got
significant API changes in 2025–2026.

For something that just needs to send a few USB control transfers at boot,
userspace is the right place. PyUSB exists, systemd exists. We're done.

If you wanted to upstream T1 support, you'd write a proper HID driver that:

- Matches on `USB_VENDOR_ID_APPLE` and `USB_DEVICE_ID_APPLE_IBRIDGE`
- Parses the HID descriptor for the mode and display fields
- Sends the right reports at probe time and after resume
- Probably also implements multi-touch report parsing for the few apps that
  could meaningfully use it
- Coordinates with `appletbdrm` (the mainline T2 DRM driver) to optionally
  drive the OLED with dynamic content

That's a real driver project. Anyone interested is encouraged to look at the
existing forks for the bones of it; the work is mostly already done, it just
needs porting to current kernel APIs.

## Why does this need root?

PyUSB on Linux goes through `libusb`, which needs either:

- Read/write permission on the underlying `/dev/bus/usb/NNN/MMM` node, or
- The ability to detach kernel drivers from interfaces

Both require either root or a udev rule giving your user group access. We
take the simpler path: systemd runs the wake script as root at boot, which
is when wake-up needs to happen anyway. A future improvement could be a udev
rule + uaccess tag so a regular user can run `touchbar-wake` manually
without sudo.
