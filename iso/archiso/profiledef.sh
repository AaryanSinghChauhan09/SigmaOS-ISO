#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# profiledef.sh: archiso profile definition for SigmaOS live media

iso_name="sigmaos-desktop"
iso_label="SIGMAOS_$(date +%Y%m)"
iso_publisher="SigmaOS Architecture <https://github.com/AaryanSinghChauhan09/SigmaOS>"
iso_application="SigmaOS Sovereign Live Desktop"
iso_version="$(date +%Y.%m.%d)"
install_dir="sigmaos"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
# Serial console output makes firmware-level boot failures diagnosable in
# QEMU/CI and on headless hardware; harmless on machines without a serial port.
# AppArmor enabled for better security than default Arch/Omarchy.
kernel_params_x86_64="console=ttyS0 apparmor=1 security=apparmor"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/sigma-aur"]="0:0:755"
  ["/usr/local/bin/sigmaos-doctor"]="0:0:755"
  ["/usr/local/bin/sigmaos-install"]="0:0:755"
  ["/usr/local/bin/sigmaos-provision-owner"]="0:0:755"
  ["/usr/local/bin/sigmaos-secureboot"]="0:0:755"
  ["/usr/local/bin/sigmaos-snapshot"]="0:0:755"
  ["/usr/local/bin/sigmaos-theme"]="0:0:755"
  ["/usr/local/bin/sigmaos-theme-picker"]="0:0:755"
  ["/usr/local/bin/sigmaos-update"]="0:0:755"
  ["/usr/local/bin/sigmaos-welcome"]="0:0:755"
  ["/etc/skel/.config/hypr/autostart.sh"]="0:0:755"
  ["/etc/systemd/system/apparmor-enforce.service"]="0:0:644"
  ["/etc/systemd/system/sysinit.target.wants/apparmor-enforce.service"]="0:0:777"
  ["/etc/sysctl.d/99-sigmaos-hardening.conf"]="0:0:644"
  ["/etc/apparmor.d"]="0:0:755"
  ["/usr/share/sigmaos"]="0:0:755"
  ["/usr/share/sigmaos/welcome.txt"]="0:0:644"
  ["/etc/skel/.config/starship.toml"]="0:0:644"
)
