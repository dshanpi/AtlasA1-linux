# 2026-11-21 PMIC and GPIO withstand-mode hardware trials

Outcome: AW869C/AIC8800D80 is still not enumerated. WLAN/BT remain unaccepted.
These hardware results supersede the previous compile-only PMIC status.

## PMIC snapshot, booted candidate

Built an ARM64 Image from the existing v47 configuration with only the read-only
wireless snapshot addition. Reused the v47 initramfs, DTB, and modules.
The candidate keeps v47 module ABI; filename, Image checksum, build timestamp,
and new sysfs attribute distinguish it from the original v47.

- Raw SHA256: `240ed8dcdc794b2e2225f67f3f410e13b444c02f7a5d2b8b0eb8d406f5c4b44b`
- Gzip SHA256: `9bb2563d4862429ea5f6dca8b56f334c839af101e2f7e60d9d5b4e1a545e2a99`
- Boot ID: `23d69103-d4f8-4647-a546-bd39675cd079`
- PMIC: ID=03, reg10=ff, reg11=1f, reg12=17, reg22=52, reg38=0d.
- DCDC1 on with 3.3 V setpoint; SW2 on; DLDO5 on with 1.8 V setpoint.

This rules out a missing SW2 enable in the observed boot. It does not measure
voltage at the module. DCDC2 snapshot remained 900 mV. GNOME was active, NVMe
enumerated and remained unmounted. Diagnostics did not write PMIC supplies or SSD data.

## GPIO definitions and trials

Source: local T736_User Manual_V0.92.pdf, physical pages 1609/1955, printed
1589/1935, visually inspected. PG is reg02000040[13:12]; PM is reg07025340[3:2].
Both define 01=auto, 10=3.3V, 11=1.8V. These select pad withstand configuration,
not supply voltage. Treating the observed 10 value as adaptive is unsupported.

Baseline PG=0aaaaaaa and PM=000aaaaa both select 10. The existing mainline
board pinctrl drivers do not program these fields. A temporary module changed
only these fields, restoring them on unload.

| Trial | Register readback | Outcome |
| --- | --- | --- |
| Native host, automatic pads | PG=0aaa9aaa, PM=000aaaa6 | No SDIO function |
| Native host, manual 1.8 V pads | PG=0aaabaaa, PM=000aaaae | No SDIO function |
| Manual pads + delayed path diagnostic | Same manual values; PM4 high during queries | Two CMD52 and four CMD5 timeouts; IRQ=104, response=0 |
| Manual pads + GPIO CMD5 diagnostic | CLK readback 2/3, duration 3.073197 ms | No response start bit; native queries also timeout |

Raw pad value registers stayed G=01154540, M=00000001. Their PG/PM fields do
not decode as valid measured voltages under this manual. Do not report them as
confirmed pad voltages or proof of a bad module. GPIO waveform was not measured.
Pad modes alone did not resolve failure; no permanent pad-mode fix was installed.

## Reproduction and restoration

Sources: `boards/wireless-v31/diagnostics/atlasa1-wireless-pad-mode.c` and
`run-pad-mode-trial.sh`, built against configured v47. The script confines
unbind/rebind to 4021000.mmc, saves rfkill, restores PG/PM fields, unloads both
diagnostic modules, and clears driver_override. Initial native trials used the
same restoration sequence through SSH.

Each trial restored PG=0aaaaaaa, PM=000aaaaa, sunxi-mmc binding and empty
override; GNOME stayed active with no failed units. Default boot aliases were
never changed. Final original-v47 cold-boot verification is recorded in
`restored-default-20261121.txt` when completed.

Raw logs: `pmic-snapshot-20261121.txt`, `pad-auto-20261121.txt`,
`pad-1v8-20261121.txt`, `pad-1v8-path-20261121.txt`, and
`pad-1v8-bitbang-20261121.txt`. Logs include earlier ring-buffer entries;
use the last pad-voltage/GPIO block for the current trial.

The next discriminating baseline is a complete known-working Tina boot chain,
including its actual pad, power-key and SDIO settings. The prior failed Tina
kernel jump under source U-Boot is not a valid substitute.
