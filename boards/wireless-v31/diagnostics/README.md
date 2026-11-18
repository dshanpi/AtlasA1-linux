# AtlasA1 SDIO1 register diagnostics

These optional modules reproduce the three v33 board runs. Each is an instrumented copy of the GPL Linux SDIO host driver with a distinct platform driver name and a single T736 SDIO compatible. The eMMC controller has a different compatible and driver.

Prepare an empty directory on the build host and export `LINUX` and `KOUT` for the v33 source and configured build output, and `DIAG` for this directory. Copy the host driver and apply the diagnostic patch. For the RTC output test, additionally apply `diagnostic-32k.patch`. For the settling-time test, start from the base diagnostic patch and additionally apply `diagnostic-extra-settle.patch`.

```sh
cp "$LINUX/drivers/mmc/host/sunxi-mmc.c" atlasa1-sdio-diag.c
patch --batch --fuzz=0 -p1 -i "$DIAG/diag-only.patch"
printf '%s\n' 'obj-m += atlasa1-sdio-diag.o' > Makefile
make -C "$LINUX" O="$KOUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M="$PWD" modules
modinfo -F vermagic atlasa1-sdio-diag.ko
```

Bind the module to `4021000.mmc` on the v33 board for one scan. For the settling-time run, enable the board's Bluetooth rfkill switch as well and restore its previous value afterwards. The optional RTC module uses a device-managed action to restore the original output-gate bit when unbound.

```sh
set -eu
test "$(uname -r)" = 6.18.63-t736-hw-v33
id=4021000.mmc
dev=/sys/bus/platform/devices/$id
drivers=/sys/bus/platform/drivers
test "$(tr -d '\000' < "$dev/of_node/compatible")" = allwinner,t736-sdio
test "$(basename "$(readlink -f "$dev/driver")")" = sunxi-mmc
insmod ./atlasa1-sdio-diag.ko
restore() {
    if [ "$(basename "$(readlink -f "$dev/driver")")" = atlasa1-sdio-diag ]; then
        echo "$id" > "$drivers/atlasa1-sdio-diag/unbind"
    fi
    printf '\n' > "$dev/driver_override"
    rmmod atlasa1_sdio_diag
    if [ ! -L "$dev/driver" ]; then echo "$id" > "$drivers/sunxi-mmc/bind"; fi
}
trap restore EXIT
echo atlasa1-sdio-diag > "$dev/driver_override"
echo "$id" > "$drivers/sunxi-mmc/unbind"
echo "$id" > "$drivers/atlasa1-sdio-diag/bind"
sleep 7
journalctl -k -b -o cat | grep 'atlasa1-sdio-diag'
```
