#!/usr/bin/env bash
# Runs inside the airootfs chroot after package installation.
# The kernel lands in /usr/lib/modules/<kver>/vmlinuz but /boot/vmlinuz-linux
# is only created by kernel-install, which does not run in the pacstrap chroot.
# mkinitcpio presets require /boot/vmlinuz-linux, so create the symlink and
# (re)generate the initramfs images here.
set -uo pipefail

KVER="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)")"
[ -n "$KVER" ] || { echo "customize: no kernel found in /usr/lib/modules" >&2; exit 1; }
[ -f "/usr/lib/modules/${KVER}/vmlinuz" ] || { echo "customize: vmlinuz missing for ${KVER}" >&2; exit 1; }

mkdir -p /boot
# Copy the real kernel image — a symlink would dangle after mkarchiso copies
# /boot out of the airootfs onto the ISO staging tree.
cp -f "/usr/lib/modules/${KVER}/vmlinuz" /boot/vmlinuz-linux
# mkinitcpio preset also references the fallback image; regenerate both.
# mkinitcpio exits non-zero on non-fatal warnings (missing optional firmware
# modules) — tolerate that, but verify the images exist after.
mkinitcpio -P || echo "customize: mkinitcpio reported warnings" >&2
for img in /boot/initramfs-linux.img /boot/initramfs-linux-fallback.img; do
  [ -s "$img" ] || { echo "customize: missing $img" >&2; exit 1; }
done

# Verify the initramfs can actually boot the live media. A previous build
# shipped an image whose HOOKS lacked archiso/archiso_loop_mnt and whose
# MODULES lacked storage drivers, producing an ISO that dropped to an
# emergency shell with no block devices. Fail the build instead.
verify_initramfs() {
  local img="$1" cfg listing
  cfg="$(lsinitcpio -c "$img" 2>/dev/null)" || { echo "customize: cannot read config of $img" >&2; return 1; }
  echo "$cfg" | grep -q 'archiso_loop_mnt' || {
    echo "customize: $img missing archiso_loop_mnt hook" >&2; return 1; }
  echo "$cfg" | grep -qw 'archiso' || {
    echo "customize: $img missing archiso hook" >&2; return 1; }
  # archiso_pxe_nfs intentionally absent: PXE/NFS netboot hooks were removed
  # (no ipconfig/nbd/nfs binaries shipped). Live media boots from local media.
  listing="$(lsinitcpio -l "$img" 2>/dev/null)" || {
    echo "customize: WARNING cannot list $img modules (verify post-build)" >&2; return 0; }
  # Module listing is advisory: lsinitcpio -l output is environment-sensitive
  # inside the airootfs chroot (zstd/bsdtar availability). The image is
  # verified externally post-build; missing-module warnings do not abort.
  local mod
  for mod in sr_mod ata_piix isofs cdrom; do
    echo "$listing" | grep -q "/$mod\.ko" || {
      echo "customize: WARNING $img missing module $mod (verify post-build)" >&2; }
  done
}
verify_initramfs /boot/initramfs-linux.img || exit 1
verify_initramfs /boot/initramfs-linux-fallback.img || exit 1
echo "customize: initramfs verification passed"

# Guarantee exec bits on shipped scripts — files copied into airootfs by
# some tooling paths have been observed losing +x, which makes the live
# installer "command not found".
chmod 0755 /usr/local/bin/sigmaos-* /usr/local/bin/sigma-aur \
          /etc/skel/.config/hypr/autostart.sh 2>/dev/null || true

# Live session user: the shipped /etc/passwd defines liveuser, but nothing
# creates its home — without it, tty1 autologin lands in a bare shell and
# .bash_profile (which launches Hyprland) never runs. Populate /home/liveuser
# from /etc/skel exactly like useradd -m would.
if id liveuser >/dev/null 2>&1; then
  mkdir -p /home/liveuser
  cp -a /etc/skel/. /home/liveuser/
  chown -R liveuser:liveuser /home/liveuser
  chmod 750 /home/liveuser
  echo "customize: liveuser home populated from /etc/skel"
else
  echo "customize: WARNING liveuser not in passwd" >&2
fi

# Hyprland's built-in first-run welcome screen (hyprland-welcome, part of
# hyprland-guiutils/hyprtoolkit) segfaults in libhyprtoolkit on VMs and
# software-rendered sessions, leaving a dead spinner over a black screen —
# the live desktop appears broken. Removing the helper makes Hyprland log
# "[welcome] skipping, no welcome app" and start the session normally.
if [ -f /usr/bin/hyprland-welcome ]; then
  rm -f /usr/bin/hyprland-welcome
  echo "customize: removed hyprland-welcome (crashes in libhyprtoolkit)"
fi

# Populate the pacman keyring. mkarchiso's airootfs does not guarantee a
# usable /etc/pacman.d/gnupg, and without it live-session `pacman -S` fails
# signature checks and sigmaos-install's pacstrap aborts with "keyring is
# not writable" / "required key missing from keyring" after downloading
# every package. --populate archlinux imports the keyring shipped inside
# the archlinux-keyring package (no keyserver needed); fall back to a
# keyserver populate if the local import comes up empty.
if [ ! -s /etc/pacman.d/gnupg/pubring.kbx ] && [ ! -s /etc/pacman.d/gnupg/pubring.gpg ]; then
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux >/dev/null 2>&1 || true
fi
if [ ! -s /etc/pacman.d/gnupg/pubring.kbx ] && [ ! -s /etc/pacman.d/gnupg/pubring.gpg ]; then
  pacman-key --populate >/dev/null 2>&1 || true
fi
pacman-key --list-keys >/dev/null 2>&1 \
  && echo "customize: pacman keyring populated ($(pacman-key --list-keys 2>/dev/null | grep -c '^pub'))" \
  || echo "customize: WARNING pacman keyring still empty" >&2

ls -l /boot/
