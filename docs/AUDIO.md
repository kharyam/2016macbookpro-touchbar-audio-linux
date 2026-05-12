# Bonus: getting the internal speakers working

The same 2016/2017 MacBook Pros that have the T1 chip also have a **Cirrus
CS8409** audio codec driving a **MAX98706** speaker amplifier. On modern
kernels the in-tree `snd_hda_codec_cs8409` driver detects the codec and
sets up audio routing — headphones and the mic work fine — but the speaker
amp needs Apple-specific HDA init verbs that aren't in any mainline or
distro firmware package. The result: headphone jack works, internal
speakers are silent.

The standard solution is **davidjo's** [`snd_hda_macbookpro`](https://github.com/davidjo/snd_hda_macbookpro)
out-of-tree driver. It includes the Apple-specific patches inline rather
than loading them from a firmware file.

## The kernel 6.17+ wrinkle

Linux 6.17 reorganized the HDA source tree. Files moved from
`sound/pci/hda/` to `sound/hda/codecs/cirrus/`. Davidjo's installer script
has not yet been updated to handle the new layout, so the default
`install.cirrus.driver.sh` fails with:

```
tar: linux-6.17.x/sound/pci/hda: Not found in archive
```

The workaround, originally documented in
[Fábio Ranquetat's Medium article](https://medium.com/@ranquetat/how-to-install-kernel-6-17-and-fix-sound-on-macs-cirrus-cs8409-running-linux-8641c1cf4d98)
and confirmed working on kernel 7.0.4 / Fedora 44, is to write a custom
`dkms.conf` that:

- Points the build to the new HDA subdirectory
- Injects `CFLAGS_MODULE` flags to tolerate stricter GCC 14+ warnings
- Sets the correct install location for the new module path

## Recipe (Fedora 44+, kernel 6.17+)

```bash
# 1. Build deps
sudo dnf install -y kernel-devel kernel-headers dkms gcc make git alsa-utils

# 2. Clean up any prior attempt
sudo dkms remove snd_hda_macbookpro/1.0 --all 2>/dev/null || true
sudo rm -rf /usr/src/snd_hda_macbookpro-1.0

# 3. Get the source into /usr/src
cd /tmp
git clone --depth 1 https://github.com/davidjo/snd_hda_macbookpro.git
sudo mkdir -p /usr/src/snd_hda_macbookpro-1.0
sudo cp -r snd_hda_macbookpro/. /usr/src/snd_hda_macbookpro-1.0/
sudo chmod +x /usr/src/snd_hda_macbookpro-1.0/install.cirrus.driver.sh

# 4. Override the DKMS config with one that handles the new HDA layout
sudo tee /usr/src/snd_hda_macbookpro-1.0/dkms.conf > /dev/null <<'EOF'
PACKAGE_NAME="snd_hda_macbookpro"
PACKAGE_VERSION="1.0"
PRE_BUILD="install.cirrus.driver.sh -k $kernelver"
MAKE="make KERNELRELEASE=${kernelver} KDIR=/lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build/build/hda CFLAGS_MODULE='-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function -Wno-error -Wno-incompatible-pointer-types'"
BUILT_MODULE_NAME[0]="snd-hda-codec-cs8409"
BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"
DEST_MODULE_LOCATION[0]="/updates/codecs/cirrus"
AUTOINSTALL="yes"
EOF

# 5. Build and install
sudo dkms add -m snd_hda_macbookpro -v 1.0
sudo dkms install -m snd_hda_macbookpro -v 1.0 --force --verbose
sudo depmod -a

# 6. Reboot
sudo reboot
```

## Verify

After reboot:

```bash
lsmod | grep cs8409
pactl list short sinks
speaker-test -c 2 -t wav
```

You should hear the test tone from the internal speakers.

## What to do on other distros

Debian / Ubuntu users should follow Ranquetat's article directly — it's
written for LMDE 7 / Trixie and covers installing the necessary kernel
backports.

The DKMS config block above is distro-agnostic, only the prerequisite
package commands change. Adjust accordingly.

## Why isn't this in this repo?

Two reasons:

1. **It's not our code.** Davidjo did the years of reverse engineering work
   to capture the right HDA init verbs, and Ranquetat figured out the DKMS
   workaround for the 6.17 reshuffle. Wrapping their work in our installer
   would obscure who deserves credit.

2. **It's likely to be obsolete soon.** The mainline kernel's `cs8409.c`
   already knows how to load Apple init verbs from a `cs8409-apple`
   firmware patch file — it just isn't shipped in `linux-firmware` yet.
   When it is, the entire DKMS dance becomes unnecessary; you'll just
   install a firmware package and reboot.

If you're hitting this in 2027+, check whether `linux-firmware` has shipped
`cs8409-apple` before doing anything else.
