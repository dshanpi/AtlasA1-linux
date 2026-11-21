#!/usr/bin/env bash
# Diagnostic only, SDIO1 only. Never cycle the shared PCIe/WLAN 3.3 V supply.
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { echo "Usage: sudo $0 MODULE NEW_LOG" >&2; exit 2; }
module=$(realpath -e "$1")
test ! -e "$2"
exec > >(tee "$2") 2>&1
device=/sys/bus/platform/devices/4021000.mmc
test "$(basename "$(readlink "$device/driver")")" = sunxi-mmc
original_bt=$(cat /sys/class/rfkill/rfkill0/soft)
cleanup() {
    if [[ -L $device/driver ]]; then
        driver=$(basename "$(readlink "$device/driver")")
        if [[ $driver == atlasa1-sdio-diag ]]; then
            echo 4021000.mmc > /sys/bus/platform/drivers/atlasa1-sdio-diag/unbind
        fi
    fi
    printf '\n' > "$device/driver_override"
    rmmod atlasa1_sdio_diag 2>/dev/null || true
    if [[ ! -L $device/driver ]]; then
        echo 4021000.mmc > /sys/bus/platform/drivers/sunxi-mmc/bind
    fi
    echo "$original_bt" > /sys/class/rfkill/rfkill0/soft
}
trap cleanup EXIT
uname -r
sha256sum "$module"
echo 1 > /sys/class/rfkill/rfkill0/soft
for phase in 0; do
    printf 'COMMAND_SAMPLE_PHASE %s\n' "$phase"
    echo 4021000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind
    cat /sys/kernel/debug/gpio
sleep 1
echo 1 > /sys/class/rfkill/rfkill0/soft
echo atlasa1-sdio-diag > "$device/driver_override"
    insmod "$module" cmd_phase="$phase"
    sleep 6
    find /sys/bus/sdio/devices -mindepth 1 -maxdepth 1 -printf '%f\n'
    dmesg | grep 'atlasa1-sdio-diag' | tail -24
    echo 4021000.mmc > /sys/bus/platform/drivers/atlasa1-sdio-diag/unbind
    rmmod atlasa1_sdio_diag
    printf '\n' > "$device/driver_override"
    echo 4021000.mmc > /sys/bus/platform/drivers/sunxi-mmc/bind
    sleep 3
done
lsblk -n -o NAME,SIZE /dev/nvme0n1
