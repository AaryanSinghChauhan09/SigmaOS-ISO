#!/usr/bin/env bash
# qemu_firmware_boot.sh — real firmware boot test for a SigmaOS ISO.
#
# Unlike qemu_iso_boot.sh (which extracts kernel+initramfs and boots them
# directly, bypassing all boot firmware), this test boots the ISO as a CD
# under actual firmware:
#
#   bios — SeaBIOS (QEMU default), exercises the syslinux El Torito path
#   uefi — OVMF, exercises the systemd-boot El Torito/GPT path
#
# Success requires kernel boot messages on the serial console. The ISO's
# boot entries carry console=ttyS0 (see kernel_params_x86_64 in
# iso/archiso/profiledef.sh), so a firmware that fails to load the boot
# image produces an empty/failure log while a working boot prints
# "Linux version" and archiso userspace markers.
#
# Usage: qemu_firmware_boot.sh <iso> <bios|uefi|both> [workdir] [timeout-sec]
# Requires: qemu-system-x86_64, OVMF firmware (uefi mode only).
set -euo pipefail

ISO="${1:?usage: qemu_firmware_boot.sh <iso> <bios|uefi|both> [workdir] [timeout]}"
MODE="${2:-both}"
WORK="${3:-$(mktemp -d /tmp/sigmaos-fw-XXXXXX)}"
TIMEOUT="${4:-600}"

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
mkdir -p "$WORK"

OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}"

run_mode() {
    local mode="$1"
    local log="$WORK/${mode}.log"
    local vars_img=""
    : > "$log"

    local -a qemu_args=(
        qemu-system-x86_64
        -m 3072 -smp 2
        -display none -serial "file:$log" -monitor none
        -cdrom "$ISO"
        -no-reboot
    )

    if [[ "$mode" == "uefi" ]]; then
        [[ -f "$OVMF_CODE" && -f "$OVMF_VARS" ]] || {
            echo "[fw-boot] OVMF firmware not found ($OVMF_CODE / $OVMF_VARS)" >&2
            return 2
        }
        vars_img="$WORK/OVMF_VARS.fd"
        cp "$OVMF_VARS" "$vars_img"
        qemu_args+=(
            -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
            -drive if=pflash,format=raw,file="$vars_img"
            -boot d
        )
    fi

    if [[ -w /dev/kvm ]]; then
        qemu_args+=(-enable-kvm -cpu host)
    fi

    echo "[fw-boot] $mode: booting $ISO (timeout ${TIMEOUT}s)"
    "${qemu_args[@]}" &
    local qpid=$!

    local found="" elapsed=0
    while (( elapsed < TIMEOUT )); do
        if ! kill -0 "$qpid" 2>/dev/null; then
            echo "[fw-boot] $mode: QEMU exited early" >&2
            break
        fi
        # Kernel boot banner or archiso userspace markers on serial.
        if grep -qE 'Linux version|Command line:|Run /init|login:|Reached target' "$log" 2>/dev/null; then
            found="kernel/userspace"
            break
        fi
        # Firmware explicitly reporting it cannot load the boot image.
        if grep -qE 'failed to load Boot|No bootable device|Boot failed' "$log" 2>/dev/null; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    kill "$qpid" 2>/dev/null || true
    wait "$qpid" 2>/dev/null || true

    if [[ -n "$found" ]]; then
        echo "[fw-boot] $mode: PASS — boot reached kernel/userspace"
        return 0
    fi
    echo "[fw-boot] $mode: FAIL — no kernel boot evidence within ${TIMEOUT}s" >&2
    echo "--- last 40 lines of $mode serial log ---" >&2
    tail -40 "$log" >&2 || true
    return 1
}

rc=0
case "$MODE" in
    bios)  run_mode bios  || rc=1 ;;
    uefi)  run_mode uefi  || rc=1 ;;
    both)  run_mode bios || rc=1; run_mode uefi || rc=1 ;;
    *) echo "mode must be bios, uefi, or both" >&2; exit 2 ;;
esac
exit "$rc"
