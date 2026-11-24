#!/usr/bin/env bash
# qemu_installer_dryrun.sh — installer dry-run + disk-safety test in QEMU.
#
# Boots the ISO (direct kernel/initramfs boot, same as qemu_iso_boot.sh),
# attaches a blank raw disk, logs in on the serial console as liveuser,
# and runs `sigmaos-install --dry-run` against the virtual disk. Asserts:
#
#   1. The installer prints its DRY RUN plan and exits without writing.
#   2. The virtual disk's first sectors remain untouched afterwards.
#
# Requires the ISO to ship serial-getty@ttyS0 (see airootfs systemd wants)
# and console=ttyS0 in the boot entries.
#
# Usage: qemu_installer_dryrun.sh <iso> [workdir] [timeout-sec]
set -euo pipefail

ISO="${1:?usage: qemu_installer_dryrun.sh <iso> [workdir] [timeout]}"
WORK="${2:-$(mktemp -d /tmp/sigmaos-inst-XXXXXX)}"
TIMEOUT="${3:-900}"
LOG="$WORK/serial.log"
SOCK="$WORK/serial.sock"
DISK="$WORK/testdisk.img"
KERNEL_REL="sigmaos/boot/x86_64/vmlinuz-linux"
INITRD_REL="sigmaos/boot/x86_64/initramfs-linux.img"

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
mkdir -p "$WORK"
: > "$LOG"

extract_file() {
    local rel="$1" out="$2"
    if command -v xorriso >/dev/null 2>&1; then
        xorriso -osirrox on -indev "$ISO" -extract "/$rel" "$out" >/dev/null
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xOf "$ISO" "/$rel" > "$out"
    elif command -v 7z >/dev/null 2>&1; then
        7z e -so "$ISO" "$rel" > "$out"
    else
        echo "no ISO extraction tool" >&2; return 1
    fi
}
extract_file "$KERNEL_REL" "$WORK/vmlinuz-linux"
extract_file "$INITRD_REL" "$WORK/initramfs-linux.img"
[[ -s "$WORK/vmlinuz-linux" && -s "$WORK/initramfs-linux.img" ]] || {
    echo "failed to extract kernel/initramfs" >&2; exit 1; }

# Blank raw disk the installer may target — raw (not qcow2) so the host can
# verify afterwards that nothing was written to it.
qemu-img create -f raw "$DISK" 8G >/dev/null
# Snapshot first 1 MiB for before/after comparison.
dd if="$DISK" of="$WORK/disk-before.bin" bs=1M count=1 status=none

QEMU_ACCEL=()
if [[ -w /dev/kvm ]]; then QEMU_ACCEL=(-enable-kvm -cpu host); fi

qemu-system-x86_64 "${QEMU_ACCEL[@]}" \
    -m 3072 -smp 2 \
    -display none \
    -serial "unix:$SOCK,server=on,wait=off" \
    -monitor none \
    -cdrom "$ISO" \
    -kernel "$WORK/vmlinuz-linux" \
    -initrd "$WORK/initramfs-linux.img" \
    -append "archisobasedir=sigmaos archisodevice=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} img_dev=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} console=ttyS0" \
    -drive "file=$DISK,if=virtio,format=raw" \
    -no-reboot &
QPID=$!

# Bidirectional serial driver: waits for prompts, sends credentials and the
# installer command, then watches for the dry-run plan markers.
python3 - "$SOCK" "$LOG" "$TIMEOUT" <<'PYEOF'
import socket, sys, time, re

sock_path, log_path, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])
deadline = time.time() + timeout
buf = b""

def logwrite(data):
    with open(log_path, "ab") as f:
        f.write(data)

def connect():
    # The unix socket chardev may not exist until QEMU finishes init.
    for _ in range(600):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(sock_path)
            s.settimeout(0.5)
            return s
        except OSError:
            time.sleep(0.5)
    raise SystemExit("could not connect to serial socket")

s = connect()
state = "boot"
sent_install = False
result = "timeout"

while time.time() < deadline:
    try:
        chunk = s.recv(65536)
        if chunk:
            buf += chunk
            logwrite(chunk)
    except socket.timeout:
        pass
    text = buf.decode("utf-8", "replace")

    # Prompts are matched anywhere in the accumulated buffer: once a state
    # advances it never re-fires, and trailing kernel/service output must
    # not hide an earlier prompt.
    if state == "boot" and "login:" in text:
        s.sendall(b"liveuser\n")
        state = "user"
    elif state == "user" and "assword:" in text:
        s.sendall(b"sigmaos\n")
        state = "pass"
    elif state == "pass" and re.search(r"\$\s*$", text):
        s.sendall(b"sigmaos-install --dry-run /dev/vda\n")
        state = "install"
    elif state == "install":
        if "DRY RUN" in text and "[PLAN]" in text:
            result = "dry-run-plan"
            break
        if "FATAL" in text or "Error:" in text:
            result = "installer-error"
            break
    time.sleep(0.2)

# Best-effort clean shutdown, then report.
try:
    s.sendall(b"poweroff -f\n")
except OSError:
    pass
print(f"RESULT={result}")
sys.exit(0 if result == "dry-run-plan" else 1)
PYEOF
PYRC=$?

sleep 3
kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

if [[ $PYRC -ne 0 ]]; then
    echo "[inst-test] FAIL — installer dry-run did not produce plan" >&2
    tail -50 "$LOG" >&2 || true
    exit 1
fi

# Verify the disk was not modified: compare first MiB.
dd if="$DISK" of="$WORK/disk-after.bin" bs=1M count=1 status=none
if cmp -s "$WORK/disk-before.bin" "$WORK/disk-after.bin"; then
    echo "[inst-test] PASS — dry-run printed plan and disk untouched"
else
    echo "[inst-test] FAIL — disk contents changed during dry-run" >&2
    exit 1
fi
