# SigmaOS Supported Features

This document clearly identifies which SigmaOS features are **verified and supported** versus which are **experimental or in development**. This helps users understand what to expect and what may require additional work.

## ✅ Verified Features (Production-Ready)

These features have been implemented, tested, and are actively supported.

### Installation
- **ISO Image**: 3.4 GB bootable ISO with BIOS (syslinux) and UEFI (systemd-boot) support
- **Live Session**: Fully functional live environment with Hyprland, Waybar, and all desktop tools
- **QEMU Boot Test**: Verified boot-to-userspace and graphical target in QEMU
- **Firmware Boot Test**: Verified BIOS and UEFI boot modes

### Security
- **AppArmor**: Enabled by default in enforcement mode (advantage over Arch/Omarchy)
- **Kernel Hardening**: ASLR, ptrace restrictions, network hardening, unprivileged BPF disabled
- **auditd**: Pre-installed for security event logging
- **Automatic Security Updates**: systemd timer with randomized delay (daily)
- **Secure Boot Tools**: sbctl, tpm2-tools included (signing requires manual setup)

### Package Management
- **pacman Integration**: Uses standard Arch Linux pacman
- **Signed Packages**: archlinux-keyring package included for package verification
- **Mirror Ranking**: reflector package with weekly systemd timer for automatic mirror optimization
- **Dependency Resolution**: Uses pacman's native solver
- **Conflict Handling**: Uses pacman's native conflict resolution

### Filesystem & Recovery
- **BTRFS Default**: Uses BTRFS with zstd:3 compression
- **Subvolume Layout**: @, @home, @var, @var_tmp, @snapshots
- **Automatic Snapshots**: BTRFS snapshots before/after pacman transactions via hooks
- **Rollback Utility**: sigmaos-snapshot rollback for easy system recovery
- **SSD Detection**: Auto-detects SSDs and applies ssd,discard=async mount options for TRIM

### Desktop Environment
- **Window Manager**: Hyprland (Wayland compositor)
- **Status Bar**: Waybar with app launcher and media player integration
- **Terminal**: kitty with enhanced zsh configuration
- **Shell**: zsh with starship prompt, larger history, better completion, AUTO_PUSHD, eza aliases, git/tmux aliases, zoxide integration, fzf history search
- **Theme System**: SigmaOS UI kit for cross-framework theming
- **Wallpaper**: Configured
- **Keybindings**: Hyprland window rules configured for common applications

### Hardware Support (QEMU Verified)
- **Software Rendering Fallbacks**: pixman, llvmpipe for VM compatibility
- **Wayland Compositors**: Hyprland
- **Audio**: PipeWire stack (pipewire, pipewire-pulse, pipewire-alsa, pipewire-jack)
- **Networking**: NetworkManager, iwd, bluez, bluez-utils
- **Graphics**: Mesa, Vulkan, lib32 variants

### CI/CD
- **ISO Build Automation**: GitHub workflow (build-iso.yml) with Docker-based build
- **Boot Smoke Tests**: QEMU boot-to-userspace test on every build
- **Firmware Boot Tests**: BIOS and UEFI boot tests on every build
- **Installer Dry-Run Test**: Verifies installer produces plan without writing to disk
- **Installer E2E Test**: Weekly full destructive install test (installer-e2e.yml)

## ⚠️ Partial Features (Functional but Needs Enhancement)

These features work but may need additional testing, hardware verification, or polish.

### Installation
- **Installer**: Script-based installer exists (sigmaos-install), needs end-to-end hardware testing
- **Automatic Partitioning**: Installer supports it, needs verification on real hardware
- **LUKS Encryption**: Installer supports it, needs verification on real hardware

### Hardware Support
- **GPU Drivers**: Software rendering works; AMDGPU, NVIDIA, Intel need real hardware testing
- **Wi-Fi**: NetworkManager + iwd configured, needs real hardware testing
- **Bluetooth**: bluez + blueman included, needs real hardware testing
- **Audio**: PipeWire configured, needs real hardware testing
- **Touchpad**: libinput configured, needs real hardware testing
- **Desktop Portals**: xdg-desktop-portal-hyprland, xdg-desktop-portal-gtk, xdg-desktop-portal-wlr included, needs verification
- **Screen Sharing**: xdg-desktop-portal included, needs verification

### Package Management
- **Interrupted Upgrade Recovery**: BTRFS snapshots enable rollback, needs real-world testing
- **AUR Support**: Has AUR helper repo (sigma-aur), needs testing

### Desktop
- **Theme Changes**: SigmaOS UI kit exists, needs live theme switch testing
- **Keybinding Customization**: Hyprland configured, needs user customization testing

## 🔬 Experimental Features (Not Production-Ready)

These features are marked as experimental and should not be relied upon for production use.

### Package Management
- **sigpkg**: Custom package manager (marked experimental in README)

### Kernel
- **Custom Microkernel**: Separate research track (not part of main distribution)

### Security
- **SELinux**: Not implemented
- **Advanced Firewall Configuration**: Needs manual setup

## 📝 Documentation Status

| Documentation Type | Status |
|-------------------|--------|
| Parity Matrix | ✅ Created |
| Supported Features | ✅ This document |
| Installation Guide | ⚠️ Partial (installer script exists, needs comprehensive guide) |
| API Documentation | ⚠️ Partial (some repos have docs, needs enhancement) |
| GitHub Wiki | ⚠️ 104 pages staged, needs enhancement from READMEs |
| AGENTS.md per repo | ✅ 13/100 repos normalized |

## 🔄 Rolling Release Model

SigmaOS follows a rolling release model like Arch Linux:
- No release tags
- Continuous updates via pacman
- ISO images are dated builds for installation
- Features are verified as they are added

## 📊 Verification Evidence

- **ISO Build**: Automated via GitHub Actions (build-iso.yml)
- **Boot Tests**: QEMU boot smoke test, firmware boot test
- **Installer Tests**: Dry-run test (every build), E2E test (weekly)
- **Package Management**: Uses standard Arch Linux repositories
- **Security**: AppArmor enforcement verified in kernel command line

## 🎯 Next Steps

1. **High Priority:**
   - Test hardware support on real machines (GPU, Wi-Fi, audio, Bluetooth)
   - Verify desktop portals and screen sharing
   - Complete comprehensive installation guide

2. **Medium Priority:**
   - Consolidate overlapping repos (plugin marketplace, themes, shell configs)
   - Enhance GitHub Wiki with full content from READMEs (104 pages)
   - Add CI evidence for more features

3. **Low Priority:**
   - sigpkg development (currently experimental)
   - Custom microkernel research track
   - Additional security features (SELinux, advanced hardening)

## 📞 Support

For issues with verified features, please open a GitHub issue with:
- SigmaOS version (ISO date)
- Hardware configuration
- Error messages or logs
- Steps to reproduce

For experimental features, please understand they are not production-ready and may change without notice.

---

Last Updated: 2026-10-15
