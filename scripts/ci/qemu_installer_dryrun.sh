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
CHARDNV_LOG="$WORK/serial-chardev.log"
QEMU_ERR="$WORK/qemu.err"
SOCK="$WORK/serial.sock"
DISK="$WORK/testdisk.img"
KERNEL_REL="sigmaos/boot/x86_64/vmlinuz-linux"
INITRD_REL="sigmaos/boot/x86_64/initramfs-linux.img"

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
mkdir -p "$WORK"
: > "$LOG"
: > "$CHARDNV_LOG"
: > "$QEMU_ERR"
rm -f "$SOCK"

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

# -chardev socket with logfile= records the raw serial stream independent of
# the python client, so a client-side failure can never hide what the guest
# actually emitted. QEMU's own stderr goes to qemu.err for postmortems.
qemu-system-x86_64 "${QEMU_ACCEL[@]}" \
    -m 3072 -smp 2 \
    -display none \
    -chardev "socket,id=ser0,path=$SOCK,server=on,wait=off,logfile=$CHARDNV_LOG" \
    -serial chardev:ser0 \
    -monitor none \
    -cdrom "$ISO" \
    -kernel "$WORK/vmlinuz-linux" \
    -initrd "$WORK/initramfs-linux.img" \
    -append "archisobasedir=sigmaos archisodevice=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} img_dev=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} console=ttyS0" \
    -drive "file=$DISK,if=virtio,format=raw" \
    -no-reboot 2>"$QEMU_ERR" &
QPID=$!

# Bidirectional serial driver: waits for prompts, sends credentials and the
# installer command, then watches for the dry-run plan markers.
python3 - "$SOCK" "$LOG" "$TIMEOUT" "$QPID" <<'PYEOF'
import socket, sys, time, re, os, signal

sock_path, log_path, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])
qpid = int(sys.argv[4])
deadline = time.time() + timeout
buf = b""

def logwrite(data):
    with open(log_path, "ab") as f:
        f.write(data)

def qemu_alive():
    try:
        os.kill(qpid, 0)
        return True
    except OSError:
        return False

def connect():
    # The unix socket chardev may not exist until QEMU finishes init.
    for _ in range(600):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(sock_path)
            s.settimeout(0.5)
            return s
        except OSError:
            if not qemu_alive():
                raise SystemExit("qemu exited before serial socket was ready")
            time.sleep(0.5)
    raise SystemExit("could not connect to serial socket")

s = connect()
state = "boot"
pass_since = None
sent_install = False
result = "timeout"

while time.time() < deadline:
    if not qemu_alive():
        result = "qemu-died"
        break
    try:
        chunk = s.recv(65536)
        if chunk:
            buf += chunk
            logwrite(chunk)
        else:
            # EOF: QEMU closed the chardev — guest is gone or socket dropped.
            result = "serial-eof"
            break
    except socket.timeout:
        pass
    except OSError:
        result = "serial-error"
        break
    text = buf.decode("utf-8", "replace")

    # Prompts are matched anywhere in the accumulated buffer: once a state
    # advances it never re-fires, and trailing kernel/service output must
    # not hide an earlier prompt. The shell prompt may carry trailing
    # escape sequences, so the pass-state also has a time fallback: the
    # serial tty line-buffers input, so sending the command a bit early is
    # safe — bash reads it as soon as the login shell starts.
    if state == "boot" and "login:" in text:
        s.sendall(b"liveuser\n")
        state = "user"
    elif state == "user" and "assword:" in text:
        s.sendall(b"sigmaos\n")
        state = "pass"
        pass_since = time.time()
    elif state == "pass":
        prompted = re.search(r"[\$#%]\s*(?:\x1b\[[0-9;]*m)*\s*$", text)
        if prompted or (pass_since and time.time() - pass_since > 90):
            s.sendall(b"sigmaos-install --dry-run /dev/vda\n")
            state = "install"
    elif state == "install":
        if "DRY RUN" in text and "[PLAN]" in text:
            result = "dry-run-plan"
            break
        if "FATAL" in text or "Error:" in text:
            result = "installer-error"
            break
        if "Login incorrect" in text:
            result = "login-failed"
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

# Give the guest a few seconds to honour poweroff, then kill QEMU so `wait`
# can never hang the step.
sleep 5
QEXIT=0
if kill -0 "$QPID" 2>/dev/null; then
    kill "$QPID" 2>/dev/null || true
    sleep 3
    kill -9 "$QPID" 2>/dev/null || true
fi
wait "$QPID" 2>/dev/null || QEXIT=$?

echo "[inst-test] qemu exit=$QEXIT pyrc=$PYRC"
if [[ $PYRC -ne 0 ]]; then
    echo "[inst-test] FAIL — installer dry-run did not produce plan" >&2
    echo "--- qemu stderr (tail) ---" >&2
    tail -30 "$QEMU_ERR" >&2 || true
    echo "--- serial log (tail) ---" >&2
    tail -50 "$LOG" >&2 || true
    if [[ ! -s "$LOG" && -s "$CHARDNV_LOG" ]]; then
        echo "--- chardev log (tail; python saw nothing) ---" >&2
        tail -50 "$CHARDNV_LOG" >&2 || true
    fi
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
