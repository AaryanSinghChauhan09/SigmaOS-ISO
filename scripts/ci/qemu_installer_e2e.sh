#!/usr/bin/env bash
# qemu_installer_e2e.sh — full destructive-install test in QEMU.
#
# Phase A: boots the ISO (direct kernel/initramfs), attaches a blank virtio
# disk and user-mode networking, logs in as liveuser, and runs
# `sigmaos-install --destructive --confirm-disk /dev/vda`, answering the
# installer's interactive prompts over the serial console.
#
# Phase B: powers off, patches console=ttyS0 into the installed GRUB config
# on the EFI System Partition (via mtools, no root needed), then boots the
# disk under OVMF/UEFI and requires systemd/userspace markers on serial —
# proving the installed system actually boots, not just that the installer
# exited 0.
#
# Requires: qemu-system-x86_64, qemu-img, python3, mtools, OVMF firmware,
#           xorriso/bsdtar/7z. Uses KVM when /dev/kvm is writable.
#
# Usage: qemu_installer_e2e.sh <iso> [workdir] [install-timeout] [boot-timeout]
set -euo pipefail

ISO="${1:?usage: qemu_installer_e2e.sh <iso> [workdir] [install-timeout] [boot-timeout]}"
WORK="${2:-$(mktemp -d /tmp/sigmaos-e2e-XXXXXX)}"
INSTALL_TIMEOUT="${3:-1800}"
BOOT_TIMEOUT="${4:-600}"
SOCK="$WORK/serial.sock"
CHARDNV_LOG="$WORK/serial-chardev.log"
QEMU_ERR="$WORK/qemu.err"
DISK="$WORK/installdisk.img"
KERNEL_REL="sigmaos/boot/x86_64/vmlinuz-linux"
INITRD_REL="sigmaos/boot/x86_64/initramfs-linux.img"
ESP_OFF=""

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
mkdir -p "$WORK"
: > "$CHARDNV_LOG"; : > "$QEMU_ERR"
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

qemu-img create -f raw "$DISK" 24G >/dev/null

QEMU_ACCEL=()
if [[ -w /dev/kvm ]]; then QEMU_ACCEL=(-enable-kvm -cpu host); fi

OVMF_CODE=""
OVMF_VARS_T=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/ovmf/OVMF_CODE_4M.fd \
         /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f "$c" ]] && OVMF_CODE="$c" && break
done
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/edk2/ovmf/OVMF_VARS_4M.fd \
         /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$v" ]] && OVMF_VARS_T="$v" && break
done

echo "[e2e] === Phase A: install to blank disk ==="
qemu-system-x86_64 "${QEMU_ACCEL[@]}" \
    -m 4096 -smp 4 \
    -display none \
    -chardev "socket,id=ser0,path=$SOCK,server=on,wait=off,logfile=$CHARDNV_LOG" \
    -serial chardev:ser0 \
    -monitor none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -cdrom "$ISO" \
    -kernel "$WORK/vmlinuz-linux" \
    -initrd "$WORK/initramfs-linux.img" \
    -append "archisobasedir=sigmaos archisodevice=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} img_dev=${SIGMAOS_QEMU_CDROM_DEV:-/dev/sr0} console=ttyS0" \
    -drive "file=$DISK,if=virtio,format=raw" \
    -no-reboot 2>"$QEMU_ERR" &
QPID=$!

python3 - "$SOCK" "$WORK/install-serial.log" "$INSTALL_TIMEOUT" "$QPID" <<'PYEOF'
import socket, sys, time, re, os

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
sudook_since = None
user_mark = 0
sudo_mark = 0
sent = set()
result = "timeout"

def once(key, data):
    if key not in sent:
        sent.add(key)
        s.sendall(data)

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
            result = "serial-eof"
            break
    except socket.timeout:
        pass
    except OSError:
        result = "serial-error"
        break
    text = buf.decode("utf-8", "replace")

    if state == "boot" and "login:" in text:
        once("user", b"liveuser\n")
        state = "user"
        user_mark = len(text)
    elif state == "user" and "assword" in text[user_mark:]:
        once("pass", b"sigmaos\n")
        state = "shell"
        pass_since = time.time()
    elif state == "shell":
        # Wait for a shell prompt (or a generous fallback), then validate
        # sudo credentials so the installer can run non-interactively.
        prompted = re.search(r"[\$#%❯>]\s*(?:\x1b\[[0-9;]*m)*\s*$", text)
        if prompted or (pass_since and time.time() - pass_since > 60):
            once("sudo-v", b"sudo -v\n")
            state = "sudo"
            sudo_mark = len(text)
    elif state == "sudo":
        # Only match prompts emitted AFTER sudo -v was sent — the login
        # "Password:" text is still in the buffer and would otherwise fire
        # instantly, feeding the password to the shell's readline instead
        # of sudo (observed: password echoed at the shell, sudo then ate
        # the installer command as its password attempt).
        newtext = text[sudo_mark:]
        if "try again" in newtext:
            sent.discard("sudo-pw")
            sudo_mark = len(text)
            newtext = ""
        if "sudo-pw" not in sent and "assword" in newtext:
            once("sudo-pw", b"sigmaos\n")
            state = "sudook"
            sudook_since = time.time()
    elif state == "sudook":
        # sudo -v prints nothing on success; give it a moment then launch.
        if time.time() - sudook_since > 8:
            # DEVICE is positional AND must match --confirm-disk; without the
            # positional arg the installer drops into an interactive prompt.
            # sudo -v above cached credentials, so this sudo won't reprompt.
            once("install", b"sudo sigmaos-install --destructive --confirm-disk /dev/vda /dev/vda\n")
            state = "inst-rootpw"
            pass_since = time.time()
    elif state == "inst-rootpw":
        if "Root password" in text:
            once("rootpw", b"\n")
            state = "inst-user"
    elif state == "inst-user":
        if "Username for daily use" in text:
            once("username", b"\n")
            state = "inst-pw1"
    elif state == "inst-pw1":
        if "assword for sigma" in text:
            once("userpw1", b"test1234\n")
            state = "inst-pw2"
    elif state == "inst-pw2":
        if "onfirm password" in text:
            once("userpw2", b"test1234\n")
            state = "inst-done"
    elif state == "inst-done":
        if "SigmaOS installed on" in text:
            result = "installed"
            break
    if state.startswith("inst-"):
        # pacstrap downloads ~1 GB; on slow links/mirrors this legitimately
        # takes tens of minutes, so the stall limit tracks the outer timeout.
        if pass_since and time.time() - pass_since > timeout - 300:
            result = "install-stalled"
            break
        if "FATAL" in text or "Error:" in text:
            result = "installer-error"
            break
    time.sleep(0.2)

print(f"RESULT={result}")
sys.exit(0 if result == "installed" else 1)
PYEOF
PYRC=$?

sleep 3
if kill -0 "$QPID" 2>/dev/null; then kill "$QPID" 2>/dev/null || true; fi
sleep 2
kill -9 "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

if [[ $PYRC -ne 0 ]]; then
    echo "[e2e] FAIL — install phase did not complete" >&2
    tail -30 "$QEMU_ERR" >&2 || true
    tail -60 "$WORK/install-serial.log" >&2 || true
    exit 1
fi
echo "[e2e] install phase complete — disk now has SigmaOS"

# Sanity: the disk must actually be partitioned now.
if sgdisk -p "$DISK" 2>/dev/null | grep -q "SigmaOS\|EFI\|GPT"; then
    echo "[e2e] disk partition table present"
else
    echo "[e2e] FAIL — disk has no usable partition table" >&2
    exit 1
fi

echo "[e2e] === Phase B: patch ESP grub.cfg for serial, boot under OVMF ==="
# ESP is partition 1 starting at 1 MiB (sgdisk default). Locate it properly.
ESP_START_SECTORS=$(sfdisk -J "$DISK" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in d['partitiontable']['partitions']:
    if p['type'].lower().startswith('c12a7328') or p.get('name','').upper() in ('EFI','ESP'):
        print(p['start']); break
" 2>/dev/null || true)
if [[ -z "$ESP_START_SECTORS" ]]; then
    ESP_START_SECTORS=2048  # sgdisk default first usable sector
fi
ESP_OFF=$((ESP_START_SECTORS * 512))
echo "[e2e] ESP offset: $ESP_OFF bytes (sector $ESP_START_SECTORS)"

# Pull grub.cfg off the FAT32 ESP, add console=ttyS0 to every linux line,
# and write it back. mtools @@offset addresses a partition inside a disk.
if ! mdir -i "$DISK@@$ESP_OFF" :: 2>/dev/null | grep -qi grub; then
    echo "[e2e] FAIL — could not list ESP via mtools" >&2
    mdir -i "$DISK@@$ESP_OFF" :: >&2 || true
    exit 1
fi
mcopy -o -i "$DISK@@$ESP_OFF" ::grub/grub.cfg "$WORK/grub.cfg" 2>/dev/null || \
mcopy -o -i "$DISK@@$ESP_OFF" ::/grub/grub.cfg "$WORK/grub.cfg"
if [[ ! -s "$WORK/grub.cfg" ]]; then
    echo "[e2e] FAIL — grub.cfg not found on ESP" >&2
    mdir -i -b -s -i "$DISK@@$ESP_OFF" ::/grub >&2 || mdir -i "$DISK@@$ESP_OFF" -s ::/grub >&2 || true
    exit 1
fi
# grub.cfg menuentry bodies are tab-indented — anchor on the first word
# being 'linux' after optional whitespace, not on column 0.
sed -E -i 's/^([[:space:]]*linux[[:space:]][^#]*)$/\1 console=ttyS0/' "$WORK/grub.cfg"
grep -q "console=ttyS0" "$WORK/grub.cfg" || {
    echo "[e2e] FAIL — could not patch grub.cfg" >&2; exit 1; }
mcopy -o -i "$DISK@@$ESP_OFF" "$WORK/grub.cfg" ::grub/grub.cfg
sync

# The installer cannot register an NVRAM boot entry from the live env
# (no efivarfs), so OVMF finds no Boot#### for the disk. Deploy the
# removable-media fallback loader \EFI\BOOT\BOOTX64.EFI — the same path
# real firmware falls back to — copied from the SigmaOS GRUB dir.
if mdir -i "$DISK@@$ESP_OFF" ::EFI/SigmaOS 2>/dev/null | grep -qi 'BOOTX64\.EFI'; then
    mmd -i "$DISK@@$ESP_OFF" ::EFI/BOOT 2>/dev/null || true
    mcopy -o -i "$DISK@@$ESP_OFF" ::EFI/SigmaOS/BOOTX64.EFI ::EFI/BOOT/BOOTX64.EFI
    sync
    echo "[e2e] deployed \\EFI\\BOOT\\BOOTX64.EFI fallback loader"
else
    echo "[e2e] FAIL — no BOOTX64.EFI under \\EFI\\SigmaOS on ESP" >&2
    mdir -i -s "$DISK@@$ESP_OFF" ::EFI >&2 || true
    exit 1
fi

if [[ -z "$OVMF_CODE" || -z "$OVMF_VARS_T" ]]; then
    echo "[e2e] FAIL — OVMF firmware not found" >&2; exit 1
fi
cp "$OVMF_VARS_T" "$WORK/OVMF_VARS.fd"
BOOT_LOG="$WORK/installed-boot.log"
BOOT_SOCK="$WORK/installed-serial.sock"
CHARDNV2_LOG="$WORK/installed-chardev.log"
: > "$BOOT_LOG"; : > "$CHARDNV2_LOG"; rm -f "$BOOT_SOCK"

qemu-system-x86_64 "${QEMU_ACCEL[@]}" \
    -m 4096 -smp 4 \
    -display none \
    -chardev "socket,id=ser1,path=$BOOT_SOCK,server=on,wait=off,logfile=$CHARDNV2_LOG" \
    -serial chardev:ser1 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$WORK/OVMF_VARS.fd" \
    -monitor none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -drive "file=$DISK,if=virtio,format=raw" \
    -no-reboot 2>"$QEMU_ERR" &
QPID=$!

# Interactive Phase B: boot the installed disk, log in on the serial
# console as the user created during install, and verify the system is
# actually usable — pacman database populated, btrfs root, SigmaOS
# tools on PATH. Booting to a login prompt alone does not prove the
# install produced a working system.
python3 - "$BOOT_SOCK" "$BOOT_LOG" "$BOOT_TIMEOUT" "$QPID" <<'PYEOF'
import socket, sys, time, re, os

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
marks = {}
checks = {}
order = [
    ("PKGCOUNT", "pacman -Q 2>/dev/null | wc -l"),
    ("FSTYPE",   "findmnt -no FSTYPE /"),
    ("TOOLS",    "for t in sigmaos-update sigmaos-snapshot sigmaos-doctor sigmaos-install; do command -v $t || echo MISSING-$t; done"),
    ("FAILED",   "systemctl --failed --no-legend --plain 2>/dev/null | wc -l"),
]
idx = 0
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
            result = "serial-eof"
            break
    except socket.timeout:
        pass
    except OSError:
        result = "serial-error"
        break
    text = buf.decode("utf-8", "replace")

    if state == "boot":
        if "login:" in text:
            s.sendall(b"sigma\n")
            state = "user"
            marks["user"] = len(text)
        elif re.search(r'Kernel panic|Failed to mount|Emergency shell|BdsDxe: failed', text):
            result = "boot-failure-marker"
            break
    elif state == "user":
        if "assword" in text[marks.get("user", 0):]:
            s.sendall(b"test1234\n")
            state = "shell"
            marks["shell"] = time.time()
    elif state == "shell":
        prompted = re.search(r"[\$#%❯>]\s*(?:\x1b\[[0-9;]*m)*\s*$", text)
        if prompted or time.time() - marks.get("shell", 0) > 60:
            if idx < len(order):
                name, cmd = order[idx]
                s.sendall(f"{cmd}; echo __{name}__=$?\n".encode())
                marks[f"sent_{name}"] = len(text)
                state = f"check_{name}"
            else:
                result = "verified"
                break
    elif state.startswith("check_"):
        name = state[len("check_"):]
        marker = f"__{name}__="
        pos = text.rfind(marker)
        if pos != -1:
            seg = text[marks.get(f"sent_{name}", 0):pos]
            checks[name] = seg
            idx += 1
            state = "shell"
    time.sleep(0.2)

print(f"RESULT={result}")
summary = [f"RESULT={result}"]

def clean(seg):
    return [re.sub(r'\x1b\[[0-9;]*m', '', l).replace('\r', '').strip()
            for l in seg.splitlines()]

def last_matching(seg, pred):
    vals = [l for l in clean(seg) if pred(l)]
    return vals[-1] if vals else ""

pkgcount = last_matching(checks.get("PKGCOUNT", ""), lambda l: re.fullmatch(r"\d+", l))
fstype   = last_matching(checks.get("FSTYPE", ""), lambda l: re.fullmatch(r"[a-z0-9_]+", l))
toolslines = [l for l in clean(checks.get("TOOLS", "")) if "/" in l or "MISSING-" in l]
failedcnt = last_matching(checks.get("FAILED", ""), lambda l: re.fullmatch(r"\d+", l))

summary.append(f"VALUE_PKGCOUNT={pkgcount}")
summary.append(f"VALUE_FSTYPE={fstype}")
summary.append(f"VALUE_TOOLS={';'.join(toolslines)}")
summary.append(f"VALUE_FAILED_UNITS={failedcnt}")
for line in summary:
    print(line)
# Mirror the summary into the serial log so the bash-side assertions
# can grep it (driver stdout goes to the CI log, not the logfile).
with open(log_path, "a") as f:
    f.write("\n".join(summary) + "\n")
sys.exit(0 if result == "verified" else 1)
PYEOF
PYRC=$?

sleep 2
if kill -0 "$QPID" 2>/dev/null; then kill "$QPID" 2>/dev/null || true; fi
sleep 2
kill -9 "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

if [[ $PYRC -ne 0 ]]; then
    echo "[e2e] FAIL — installed system did not verify" >&2
    tail -30 "$QEMU_ERR" >&2 || true
    tail -80 "$BOOT_LOG" >&2 || true
    exit 1
fi

# Hard verification on the VALUE_* lines the driver appended to the log.
PKGCOUNT="$(grep -oE 'VALUE_PKGCOUNT=[0-9]+' "$BOOT_LOG" | tail -1 | cut -d= -f2)"
FSTYPE="$(grep -oE 'VALUE_FSTYPE=[a-z0-9_]+' "$BOOT_LOG" | tail -1 | cut -d= -f2)"
TOOLS_LINE="$(grep -oE 'VALUE_TOOLS=[^ ]*' "$BOOT_LOG" | tail -1)"
echo "[e2e] installed system: packages=${PKGCOUNT:-?} rootfs=${FSTYPE:-?} tools=${TOOLS_LINE#VALUE_TOOLS=}"

[[ "${PKGCOUNT:-0}" -ge 100 ]] || { echo "[e2e] FAIL — pacman DB has only ${PKGCOUNT:-0} packages" >&2; exit 1; }
[[ "$FSTYPE" == "btrfs" ]] || { echo "[e2e] FAIL — root filesystem is '$FSTYPE', expected btrfs" >&2; exit 1; }
if [[ "$TOOLS_LINE" == *MISSING-* ]]; then
    echo "[e2e] FAIL — SigmaOS tools missing on installed system ($TOOLS_LINE)" >&2; exit 1
fi

echo "[e2e] PASS — installed system booted under OVMF, logged in, and verified (btrfs root, ${PKGCOUNT} packages, SigmaOS tools present)"
exit 0
