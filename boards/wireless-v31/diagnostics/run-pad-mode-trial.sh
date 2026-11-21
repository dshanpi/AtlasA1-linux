#!/usr/bin/env bash
# Temporary pin withstand mode plus SDIO diagnostic; no PMIC voltage writes.
set -euo pipefail
[[ $EUID == 0 && $# == 4 ]] || { echo 'Usage: PAD_KO MODE SDIO_KO NEW_LOG' >&2; exit 2; }
pad=$(realpath -e "$1")
mode=$2
sdio=$(realpath -e "$3")
[[ $mode == 1 || $mode == 3 ]]
test ! -e "$4"
exec > >(tee "$4") 2>&1
dev=/sys/bus/platform/devices/4021000.mmc
drivers=/sys/bus/platform/drivers
test "$(basename "$(readlink "$dev/driver")")" = sunxi-mmc
test ! -d /sys/module/atlasa1_wireless_pad_mode
test ! -d /sys/module/atlasa1_sdio_diag
bt=$(cat /sys/class/rfkill/rfkill0/soft)
cleanup() {
    if [[ -L $dev/driver ]]; then
        driver=$(basename "$(readlink "$dev/driver")")
        echo 4021000.mmc > "$drivers/$driver/unbind"
    fi
    if [[ -d /sys/module/atlasa1_sdio_diag ]]; then rmmod atlasa1_sdio_diag; fi
    if [[ -d /sys/module/atlasa1_wireless_pad_mode ]]; then rmmod atlasa1_wireless_pad_mode; fi
    printf '\n' > "$dev/driver_override"
    echo "$bt" > /sys/class/rfkill/rfkill0/soft
    if [[ ! -L $dev/driver ]]; then echo 4021000.mmc > "$drivers/sunxi-mmc/bind"; fi
}
trap cleanup EXIT
uname -a
sha256sum "$pad" "$sdio"
cat /sys/devices/platform/7083000.regulator/wireless_snapshot
echo 4021000.mmc > "$drivers/sunxi-mmc/unbind"
insmod "$pad" mode="$mode"
echo 0 > /sys/class/rfkill/rfkill0/soft
echo atlasa1-sdio-diag > "$dev/driver_override"
insmod "$sdio" cmd_phase=0
sleep 6
find /sys/bus/sdio/devices -mindepth 1 -maxdepth 1 -printf '%f\n'
for f in /sys/bus/sdio/devices/*/uevent; do [[ ! -f $f ]] || cat "$f"; done
cat /sys/devices/platform/7083000.regulator/wireless_snapshot
cleanup
trap - EXIT
sleep 2
dmesg | grep -E 'atlas-wireless-pad|atlasa1-sdio-diag|mmc1:' | tail -80
readlink "$dev/driver"
cat "$dev/driver_override"
systemctl is-active display-manager
systemctl --failed --no-legend
