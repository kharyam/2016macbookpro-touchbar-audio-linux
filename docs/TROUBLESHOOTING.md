# Troubleshooting

## The strip is dark after reboot

First, run the wake script manually and watch the strip:

```bash
sudo /usr/local/bin/touchbar-wake
```

Possible outcomes:

### "iBridge USB device (05ac:8600) not found"

Your T1 chip isn't enumerating on USB at all. Check:

```bash
lsusb | grep 05ac
```

If you don't see `05ac:8600`, the T1 is either in a deep fault state or the
USB bus to it is dead. Try a full power-cycle (shut down completely, wait
30 seconds, power on). If still nothing, boot into macOS once — sometimes
that resets the T1 firmware to a known state.

### "Touch Bar wake sequence sent." but the strip stays dark

The script ran but the T1 didn't respond. A few possibilities:

**1. Interface 1 isn't the right interface on your unit.** The wake script
hardcodes `wIndex = 1`. On some MBPs the right interface might be different.
Run the diagnostic loop to find the right one:

```bash
sudo systemctl stop keyd 2>/dev/null     # if keyd is installed
sudo python3 -c '
import usb.core
dev = usb.core.find(idVendor=0x05ac, idProduct=0x8600)
for intf in dev.get_active_configuration():
    n = intf.bInterfaceNumber
    try:
        if dev.is_kernel_driver_active(n):
            dev.detach_kernel_driver(n)
    except: pass
for ifnum in (0, 1, 2, 3):
    for rep_type in (0x02, 0x03):
        for rep_id in (0, 1, 2):
            try:
                dev.ctrl_transfer(0x40, 0x09, (rep_type<<8)|rep_id,
                                  ifnum, bytes([1]), 1000)
                print(f"OK ifnum={ifnum} type={rep_type} id={rep_id}")
            except: pass
'
```

If the strip lights up during this and you see "OK" lines for an interface
other than 1, edit `/usr/local/bin/touchbar-wake` and change `TARGET_INTERFACE`.

Please also open an issue with your MacBookPro model and what interface
worked — we'd like to make the script auto-detect.

**2. The HID grab race condition.** If you have `keyd` or another input
remapper that grabs `/dev/input/event*` aggressively, it can sometimes
interfere with the kernel driver reattach after our script finishes. Try:

```bash
sudo systemctl stop keyd
sudo /usr/local/bin/touchbar-wake
sudo systemctl start keyd
```

If the strip lights up this way but not normally, the wake script needs to
run *before* keyd. Edit `/etc/systemd/system/touchbar-wake.service` and add:

```ini
Before=keyd.service
```

## The strip lights up but key taps don't register

Stop your input remapper temporarily (`sudo systemctl stop keyd`) and test
with `evtest`:

```bash
cat /proc/bus/input/devices | grep -A 6 -i ibridge
# Note the event number, e.g. event6

sudo evtest --grab /dev/input/event6
# Tap the strip
```

If you see `EV_KEY` events with codes like `KEY_ESC` and `KEY_F1`-`KEY_F12`,
keys are working — your input remapper just hasn't picked up the new device.

If you see no events at all, the mode command may have been wrong on your
hardware. Try a different mode value (the script uses `1` which is
Esc + Fn keys; try `0` for Esc-only or `2` for the special-key mode).

## The strip goes dark after resume from suspend

Check the resume service ran:

```bash
journalctl -u touchbar-resume.service --since "10 minutes ago"
```

If it didn't run, check the service is enabled:

```bash
systemctl is-enabled touchbar-resume.service
```

If it ran but failed, the output will tell you what went wrong. The most
common cause is USB not being fully back up by the time we try to talk to
the iBridge. Increase the `ExecStartPre` sleep in
`/etc/systemd/system/touchbar-resume.service` from 1s to 3s.

## The strip lights up but keys are slightly delayed or unreliable

This is usually a kernel issue with USB autosuspend kicking in. Disable
autosuspend for the iBridge specifically:

```bash
sudo tee /etc/udev/rules.d/99-ibridge-no-autosuspend.rules <<EOF
ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8600", ATTR{power/control}="on"
EOF
sudo udevadm control --reload
sudo udevadm trigger
```

## Module verification failed in dmesg

If you have Secure Boot enabled you'll see messages like:

```
apple_ibridge: module verification failed: signature and/or required key missing
```

This doesn't apply to *this* repo — we're not loading any kernel modules.
But if you previously tried installing the out-of-tree T1 driver, those
messages may remain in dmesg. Harmless.

## Reverting / clean start

If you've tried multiple approaches and want to start fresh:

```bash
# Remove this repo's install
sudo ./uninstall.sh

# Remove any old DKMS modules from previous attempts
sudo dkms remove appleibridge/0.1 --all 2>/dev/null
sudo dkms remove macbook12-spi-driver/0.1 --all 2>/dev/null
sudo rm -rf /usr/src/appleibridge-*
sudo rm -rf /usr/src/macbook12-spi-driver-*

# Remove any blacklists you may have added
sudo rm -f /etc/modprobe.d/blacklist-appletb-intree.conf
sudo rm -f /etc/modprobe.d/blacklist-apple-ibridge.conf

# Rebuild initramfs to forget all of the above
sudo dracut -f          # Fedora
# sudo update-initramfs -u   # Debian/Ubuntu
# sudo mkinitcpio -P         # Arch

# Reboot, then re-run install.sh
```

## Still stuck?

Open an issue with:

1. Output of `cat /sys/class/dmi/id/product_name`
2. Output of `uname -a`
3. Output of `lsusb -t` and `lsusb | grep 05ac`
4. Output of `sudo dmesg | grep -iE 'apple|ibridge|8600'`
5. Output of `cat /proc/bus/input/devices | grep -A 6 -i ibridge`
6. What you've already tried
