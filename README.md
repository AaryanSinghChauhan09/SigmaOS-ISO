# SigmaOS-ISO

The bootable SigmaOS system: an Arch-based live ISO with a pre-configured
SigmaOS-inspired Hyprland desktop, plus the installer and release pipeline.
This is the repository that produces the downloadable `.iso`.

SigmaOS is **not** a custom-kernel project — it ships the stock standard Linux
kernel and official Arch packages (`pacman`).

## What you get

- Live Hyprland (Wayland) desktop, autologin as `liveuser`
- Waybar status bar, Rofi launcher, foot terminal, hyprlock
- 3 tested themes: catppuccin, tokyo-night, gruvbox (`sigmaos-theme`)
- `sigmaos-doctor` — one-command health check (session, network, audio, disk, updates)
- `sigmaos-welcome` — first-login cheatsheet
- `sigmaos-install` — installer (dry-run by default; destructive steps are guarded)
- Boots via BIOS (syslinux) **and** UEFI (systemd-boot)

## Live session credentials

- **user:** `liveuser` — **password:** `sigmaos`
- `liveuser` is in `wheel`; `sudo` uses the same password.
- `root` is locked in the live image. `sigmaos-install` prompts for new
  credentials on install.

## Download

Releases: <https://github.com/AaryanSinghChauhan09/SigmaOS-ISO/releases>

The ISO is published as split parts (`*.part00`, `*.part01`, …) to stay under
GitHub's 2 GiB asset limit. Reassemble and verify:

```bash
cat sigmaos-desktop-*.iso.part* > sigmaos-desktop.iso
sha256sum -c sigmaos-desktop-*.iso.sha256   # or .parts.sha256 for the parts
```

Site download page: <https://aaryansinghchauhan09.github.io/Sigma/download.html>

## Requirements

- x86_64 CPU, 4 GiB RAM (8 GiB recommended), ~10 GiB free disk for install
- UEFI or legacy BIOS boot
- For VMs: QEMU/KVM or any mainstream hypervisor works

## Build

Requires Docker **or** a standard Linux host with `archiso`.

```bash
# Validate the profile only (any host):
scripts/build_archiso.sh --validate-only

# Build via Docker (works on Ubuntu/Debian hosts):
scripts/build_archiso.sh --docker

# Build natively on standard Linux:
sudo scripts/build_archiso.sh --native
```

Output: `out/sigmaos-desktop-<date>-x86_64.iso`. The build fails if the ISO is
missing, suspiciously small, or not a readable ISO9660 image.

The ISO is produced by `mkarchiso` (archiso), which writes a hybrid
MBR/GPT El Torito image with the EFI system partition appended as a GPT
partition — the same mechanism official Arch ISOs use.

## Verification

```bash
# Direct kernel/initramfs boot test (fast, bypasses firmware):
bash scripts/ci/qemu_iso_boot.sh out/*.iso

# Real firmware boot test — SeaBIOS + OVMF, requires kernel markers on
# the serial console (boot entries include console=ttyS0):
bash scripts/ci/qemu_firmware_boot.sh out/*.iso both
```

Both run in CI on every ISO build. A release is only published after these
pass.

Manual QEMU test:

```bash
qemu-system-x86_64 -m 4G -enable-kvm -cdrom out/*.iso
# UEFI: add OVMF pflash drives and -boot d (see qemu_firmware_boot.sh)
```

## Repository layout

- `iso/archiso/` — archiso profile (packages, bootloader entries, airootfs)
- `iso_root/` — installer root filesystem bits
- `scripts/` — build, signing, reassembly, CI helpers
- `installer/` — `sigmaos-install` implementation

## Compatibility matrix

| Platform | Status |
|---|---|
| BIOS boot (SeaBIOS, syslinux) | Verified in QEMU |
| UEFI boot (OVMF/EDK2, systemd-boot) | Verified in QEMU (2026.11.24+) |
| `dd`-written USB | Supported (hybrid ISO) |
| Secure Boot | Not supported — image is unsigned |
| NVIDIA GPUs | Experimental — untested |
| aarch64 / ARM | Not supported (x86_64 only) |

## Known issues

- Releases before `sigmaos-desktop-2026.11.24-uefi` have a broken UEFI
  boot path — use BIOS mode or upgrade to the 2026.11.24 release.
- Full OS installation (`sigmaos-install --destructive`) is experimental;
  the dry-run and disk-safety paths are CI-tested, end-to-end install is
  not yet verified.
- Snapshot/rollback features are not yet implemented end-to-end; do not
  rely on them.

## Recovery

- **Bad theme/config:** `sigmaos-theme reset` restores defaults (backs up
  current config first); `sigmaos-doctor` (SUPER+/) diagnoses session,
  network, audio, disk, and update problems.
- **Boot problems:** boot the ISO in a VM first; the live session needs no
  installation. Serial console (`console=ttyS0`) shows kernel logs.
- **Failed updates:** boot the previous known-good environment; package
  state can be inspected with `pacman -Q` / `journalctl -b -p err`.

## Support status

- **Verified:** BIOS + UEFI boot in QEMU, live Hyprland session, MVP tools
  present in the shipped image, installer dry-run safety in QEMU.
- **Experimental:** installer end-to-end install in VM, Secure Boot signing
  (needs enrolled keys), snapshot/rollback features, NVIDIA hardware.

Report issues: <https://github.com/AaryanSinghChauhan09/SigmaOS-ISO/issues>

## Documentation

Detailed Wiki documentation is available in the standalone Wiki repository:

- [SigmaOS-ISO-Wiki](https://github.com/AaryanSinghChauhan09/SigmaOS-ISO-Wiki) - Full Wiki documentation

For the complete SigmaOS Wiki catalog, see:
- [SigmaOS Wiki Staging](https://github.com/AaryanSinghChauhan09/sigmaos-wiki-staging)

## See Also

Related SigmaOS **Core System** repositories:

- [SigmaOS-sigma-kernel](../SigmaOS-sigma-kernel/README.md) — SigmaOS microkernel / x86_64 kernel
- [SigmaOS-sigma-sh](../SigmaOS-sigma-sh/README.md) — SigmaOS interactive userspace shell
- [SigmaOS-sigma-sys](../SigmaOS-sigma-sys/README.md) — SigmaOS syscall ABI & userspace interface
- [SigmaOS-initramfs](../SigmaOS-initramfs/README.md) — SigmaOS initramfs builder & hook planner
- [SigmaOS-sigma-bootloader](../SigmaOS-sigma-bootloader/README.md) — SigmaOS bootloader
- [SigmaOS-installer](../SigmaOS-installer/README.md) — SigmaOS system installer
