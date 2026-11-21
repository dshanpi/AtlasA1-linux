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


## v47 follow-up

`atlasa1-sdio-path-v47.c` is the exact register-diagnostic source built for the
2026-11-20 v47 trials. Copy it as `atlasa1-sdio-diag.c` into an empty external
module directory with `obj-m += atlasa1-sdio-diag.o` in Makefile and build against
the **running v47** kernel source/output. It includes the earlier temporary
32 kHz, settling-time and phase diagnostics. This is not a production driver.

Apply at most one of `diagnostic-noceata.patch`, `diagnostic-gpio-cmd5.patch`,
or `diagnostic-reset-after-clock.patch` to that copy for the corresponding trial.
`diagnostic-path-registers.patch` records the change from the prior phase source;
it is already incorporated in the complete v47 source, so do not apply it again.

`run-path-trial.sh MODULE NEW_LOG` runs phase 0 and restores the original binding.
`run-dual-reset-trial.sh` additionally asserts both WLAN/BT enables low for one
second before releasing Bluetooth and starting SDIO. Both require root and are
restricted to controller 4021000.mmc. Logs include older kernel lines; use the last
pad-voltage block for the current run. No shared supply is toggled.
GPIO timing has not been verified with an oscilloscope; its negative result is
not proof that the module is defective. All five v47 trials still failed to
identify an SDIO function. See the evidence directory for exact outcomes.

Apply `diagnostic-gpio-rmw-readback.patch` **after** `diagnostic-gpio-cmd5.patch`
for the subsequent GPIO data-register RMW diagnostic. CLK register readback
is 0x2/0x3 with CMD high, but CMD5 still receives no start bit. This is not
a measurement at the module and is not a production fix.

`diagnostic-external-32k.patch` applies to the complete v47 path snapshot. It
requires the external crystal already enabled and its instability bit clear,
selects it using the RTC write key, then restores only the source-selection bit
on driver release. The fanout gate restoration is inherited from the base.
Both BT-enabled and `run-wlan-only-trial.sh` runs still fail to enumerate SDIO.
`atlasa1-rtc-snapshot.c` is the separate read-only RTC snapshot module.

## AW869C schematic audit, 2026-11-21

AW869C uses AIC8800D80. Its dedicated pin specification marks LPO unconnected
and BT_DIS reserved; the reference population omits their series resistors.
The earlier host clock/reset diagnostics are not evidence of those signals at
the module. See the evidence directory's `SCHEMATIC-AUDIT-20261121.md`.

`diagnostic-pmic-wireless-snapshot-v47.patch` applies to the v47 PMIC driver
(base SHA256 recorded in that audit), not the older board template. It adds
read-only, serialized DCDC1/SW2/DLDO5 configuration reporting. Its object was
compiled successfully, but no candidate image was installed or tested. Do not
load it beside the live PMIC owner or unbind the GPU supply to try it.

Follow-up: the PMIC diagnostic was booted as a one-shot Image on 2026-11-21.
SW2/DCDC1/DLDO5 were enabled. `atlasa1-wireless-pad-mode.c` and
`run-pad-mode-trial.sh` cover temporary PG/PM automatic and manual-1.8V modes.
All trials remained unable to enumerate SDIO and restored prior configuration.
See `RUNTIME-TRIALS-20261121.md` in the wireless evidence directory; these are
diagnostic candidates, not production wireless fixes.
