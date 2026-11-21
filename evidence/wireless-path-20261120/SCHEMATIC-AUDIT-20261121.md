# AW869C / AIC8800D80 schematic audit

The initial compile-only status below is superseded by
[same-day hardware trials](RUNTIME-TRIALS-20261121.md): the PMIC snapshot was
booted and read, SW2 is on, and pad-mode trials also failed to enumerate SDIO.

## Scope and status

AW869C is the module; AIC8800D80 is its chipset. The user confirmed both.
This audit does not change that identity or select a different driver.
Current v47 still has no SDIO function. WLAN/BT are not accepted as working.
The initial schematic-audit session only read board status; it did not reset the module, reboot,
change the installed kernel, or write the NVMe drive.

The available drawings are Allwinner reference designs, not a separately
verified AtlasA1 as-built schematic. Population conclusions below refer to
those drawings/BOMs; they are not measurements of the fitted board.

## Sources

- Core reference PDF: T736_DEMO_CORE_AXP8191_LP4_4X_32X1_V2_0-20260128,
  physical pages 7 and 16; SHA256
  `5e5903620e36cf37408ef8c615e0399f4b89df84e05833def5733f96e5f9f708`.
- Base reference PDF: T736_DEMO_DBOARD_V2_0, physical pages 10 and 22;
  SHA256 `3425121b5f51512fdfb534110ab9874919be69ce6205539c6357e2525d13cd08`.
- T736_DEMO_DBOARD_V2_1-BOM.xlsx: RW62 and RW101 marked NC/0R.
- [AW869C manufacturer-submitted specification, FCC document 8113782](https://fccid.io/2BNUT-AW869C/User-Manual/User-manual-8113782),
  [PDF mirror](https://device.report/m/823f2638d6e38c9ab6faf37960bd1c76bdf13b5c798a7a15f6c320325d04571a.pdf),
  printed pages 13-14 for pin definitions. Public extraction was available;
  direct PDF download returned HTTP 403. No internal oscillator detail is inferred.
- Tina `bsp/drivers/power/regulator/axp2101-regulator.c`: AXP8191 DC1SW2
  uses DCDC_CTL2 bit 4; DCDC1 selector 23 means 3.3 V.

Private source drawings were viewed locally; they are not copied into this record.

## Electrical route in the reference design

| Function | Route | Software implication |
| --- | --- | --- |
| Main module supply | DCDC1 -> internal SW2 -> SWOUT2 -> RP465 -> VCC-WIFI -> UW2 pin 9 | Checking DCDC1 alone misses SW2; RP466 direct bypass is NC |
| Shared supply | SWOUT2 branch -> RP235 -> PCIe 3.3 V | Do not cycle this rail while the user's SSD is active |
| I/O supply | DLDO5 -> RP139 VCC-PG; RP217 VCCIO-WIFI; RP36 VCC-PM; base RW103 links VCC-PG to module VDDIO pin 22 | Existing 1.8 V configuration is consistent; do not experiment with 3.3 V |
| Enable | PM4 -> J48/J71 pin 11 -> WL_REG_ON -> Q46 -> WL_EN -> UW2 pin 12 | Q46 is a non-inverting level shifter; keep active-high power-key control |
| SDIO | PG0..5 -> J47/J70 pins 62,64,66,68,70,72 -> UW2 CLK17,CMD16,D0=18,D1=19,D2=14,D3=15 | Current SDIO1 assignment matches |
| Bluetooth UART | PG6..9 -> J47/J70 pins 74,76,78,80 -> module UART nets | UART visibility alone does not establish Bluetooth firmware operation |

AW869C-specific corrections from its specification: pin 12 is an active-high
power key; pin 24 LPO is to be left unconnected; pin 34 is reserved GPIOB7;
pins 10/11 are USB pins to leave unconnected, not external crystal pins.
The reference's generic UW2 symbol labels must not override these definitions.
RW101 (LPO), RW62 (BT reset), and YW3 (external crystal) are NC in the
reference population. Do not copy the neighboring NF3205Q option's clock/reset
requirements into the AW869C configuration.

## Consequences for earlier experiments

The external-32k and PM0 reset trials remain valid records of host operations,
but do not prove signals reached AW869C or test requirements of this module.
The PM4 active-high trials remain relevant and already failed to elicit CMD5.
No reason was found to invert PM4 or repeat those trials unchanged.

SW2 is a missing diagnostic field, not an established root cause. Older SPL
logs reportedly show 0x11 values with bit 4 set, and the working SSD is
consistent with an enabled shared branch. A new runtime snapshot is still needed.
Schematics establish intended connectivity; they do not establish actual voltage
or waveform at a pad. No hardware-defect conclusion is supported.

## Read-only diagnostic prepared, not installed

`diagnostic-pmic-wireless-snapshot-v47.patch` adds a `wireless_snapshot` sysfs
attribute to the existing PMIC owner. It takes the same owner and transaction
locks as the CPU snapshot, checks PMIC identity, and reads 0x10/0x11/0x12/0x22/0x38.
It performs no PMIC register writes and no probe-time reads. Values describe
programmed configuration, not measured output voltage.

Base file SHA256:
`92bf62666babb5e5605fff61a821977bc5415385a0feaf6b3f552400ddf219d9`.
Apply to the running v47 source, which already contains the DLDO5 and DCDC2
snapshot changes; the older top-level board template is not this base.

Compiled against the existing v47 configured kernel using an isolated external
directory, target `t736-gpu-supply.o`; compilation succeeded. No full image,
module loading, reboot, or runtime validation was performed for this change.
Candidate source SHA256:
`d987bdd7801cfcbe3284408977f0dcf9a4ad319c2684d526f9265e419d156c48`.
Object SHA256:
`69479a363aa21429942d5f5840e0e821ae06800e64924fba03328a3d131d59e6`.

Next software step: integrate this read-only diagnostic into a recoverable
candidate kernel and obtain current SW2/DLDO5 settings. Do not unbind the live
GPU/PMIC driver or use a second raw TWI controller owner to obtain the values.
Then compare a complete known-working Tina boot's initialization, if one can
be captured safely; the failed cross-chain Tina kernel jump is not that baseline.
