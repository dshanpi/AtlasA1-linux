# AtlasA1 板载 Wi‑Fi 和蓝牙

## 2026-11-20：确认 AIC8800D80，枚举仍未通过

用户已确认实装为 AW869C / AIC8800D80。后续驱动与固件按此型号适配，
不再等待模组型号确认；预期 ROM SDIO ID 为 `c8a1:0182`，实板尚未读到。

v45 上已编译 Tina AIC BSP 和 FDRV 外部模块；FDRV 需要匹配标准 Linux 6.18
的 cfg80211 回调签名，并避开未提供的 Sunxi 专有 host-wake 接口。
模块尚未加载、固件尚未安装，不能将编译成功当作 Wi-Fi 通过。

将此前独立测试的 32 kHz 输出门、蓝牙使能和额外 1 秒稳定时间组合后，
CMD52/CMD5 仍全部响应超时（IRQ `0x104`、响应为零）。试验结束已确认
`4021000.mmc` 重新绑定 `sunxi-mmc`、driver_override 清空、蓝牙恢复 soft block，
诊断模块卸载。未切断与 PCIe 共用的 3.3 V，SSD 始终可枚举。

AIC BSP 通过 SDIO 下载蓝牙固件；未下载固件时的裸 UART H4 无响应，不能
独立证明蓝牙硬件故障。当前首先需要解决 SDIO ROM 无响应，模组端的实际
供电和 CLK/CMD 波形仍缺少测量证据。下文保留早期型号未确定时的历史记录。

Ubuntu 26.04 RC1 使用 `6.18.63-t736-media-v30`。其最终内核配置关闭了 `CFG80211`、`RFKILL` 和 `MMC_SUNXI`。早期 Armbian 板级配置里列出的通用无线驱动，并未进入这份 RC1 镜像。

## v31 板级候选

`atlasa1-wireless-v31.patch` 给 Linux 增加 T736 的 SDIO1 主机、独立总线时钟和复位，配置四线蓝牙 UART1。内核配置同时将 8250 可注册串口数从 1 增为 2，并启用 rfkill、cfg80211 和 HCI UART H4。复用 RC1 的 eMMC、显示、Cedar 和 PowerVR 实现，单独生成 `6.18.63-t736-hw-v31` 内核包和匹配的 PowerVR 模块。

```sh
bash tools/build_atlasa1_release_kernel.sh /src/linux /src/tina /tmp/atlas-v31 --wireless-v31
(cd /tmp/atlas-v31 && sha256sum -c SHA256SUMS)
```

首个参数为包含工程锁定版本的 upstream Linux 仓库，也可使用发布脚本支持的已校验 Linux 源码归档；第三个参数使用新目录。补丁位于 [patches/linux/atlasa1-wireless-v31.patch](../patches/linux/atlasa1-wireless-v31.patch)，附加内核配置位于 [boards/wireless-v31/kernel.config](../boards/wireless-v31/kernel.config)。

| 接口 | 核心板和底板接线 | v31 配置 |
| --- | --- | --- |
| SDIO1 | PG0 CLK，PG1 CMD，PG2～5 D0～D3，PM4 WL_REG_ON | `0x04021000`，SPI 162，四位 SDR，枚举 400 kHz，最高 12 MHz。PM4 拉高后等待 200 ms |
| UART1 | PG6 TX，PG7 RX，PG8 RTS，PG9 CTS | `0x02501000`，SPI 3，24 MHz，别名 `serial1` |
| 蓝牙电源 | PM0 BT_RESETN，PM1 AP_WAKE_BT，PM2 BT_WAKE_AP | `atlasa1-bluetooth` rfkill 管理 PM0，默认阻止。PM1、PM2 与 WLAN 唤醒 PM3 留待模组驱动接管 |
| 电源 | 原厂有效 FDT 指向 AXP8191 的 DCDC1 3.3 V 和 DLDO5 1.8 V | v31 仅提供固定电压描述。RC1 冷启动日志显示 DLDO5 关闭 |

## v33 I/O 供电修正

本次 FES 重烧后，SPL 在真实 eMMC 冷启动读到 `DC1SW1=17->1f`、`LDO_EN3=40->42`。AXP8191 的 0x11 位 4 控制 SWOUT2，读值表明 3.3 V 开关已开启。0x22 位 4 控制 DLDO5，SPL 返回时该位为零。核心板图第 7 页确认，DLDO5 分别经 RP139、RP217、RP36 连到 VCC-PG、VCCIO-WIFI、VCC-PM。

v33 包含 v31 总线支持、v32 PCIe 以及 DLDO5 供电修正。该版本复用现有 AXP8191 总线驱动和互斥锁。仅在 DLDO5 关闭时，按原厂电压表将 0x38 低 5 位设为 0x0d（1.8 V），保持同一使能寄存器的其他位，核对回读后等待 1 ms。已开启的供电只有在其设定为 1.8 V 时才接受。一次清洁构建 v33 内核、包含 PCIe 与无线的 DTB、模块包和 PowerVR 可使用以下命令。

```sh
bash tools/build_atlasa1_release_kernel.sh /src/linux /src/tina /tmp/atlas-v33 --hardware-v33
(cd /tmp/atlas-v33 && sha256sum -c SHA256SUMS)
```

## 2026-11-18 实板结果

| 实板版本 | Wi‑Fi 总线 | 蓝牙 |
| --- | --- | --- |
| v32 | 主控制器请求复位返回 `-524`，未注册 `mmc1` | PG6～9 已选 UART1，出现 `ttyS1` 和 rfkill 开关。H4 115200 发出 Reset，7 秒内收到 0 个控制器事件 |
| v33 | 增加 10 µs 硬件复位脉冲，`mmc1` 成功注册。DLDO5 读回为 `0x42→0x52`，电压码保持 `0x0d`；未枚举 SDIO function | 同参数复测仍未收到芯片 HCI 事件 |

在 v33 上只重绑了 SDIO1 主机。分别测试正常时序、打开专用 32 kHz 输出门，以及同时开启蓝牙和 WLAN 并额外延时 1 秒。每次都在 400 kHz 下记录到两条 CMD52、四条 CMD5。全部 18 次均返回中断状态 `0x104`（命令完成及响应超时），响应字为零。WL_REG_ON 的主控端在命令期间读回高电平，专用时钟门由 0 置 1 后也已还原。现场仍缺少模组端 3.3 V、1.8 V、使能、CLK/CMD 波形以及芯片丝印。下一步先在实际焊位确认这些信号，再依据 SDIO ID 选择固件与驱动。[原始寄存器与 HCI 记录](../evidence/atlasa1-wireless-v33-hardware-20261118.json)

## 模组和时钟证据

T736 核心板原理图第 16 页、A736 参考底板第 10、22 页提供引脚对应。3.3 V 由核心板 J47 第 153 脚送到底板 J70 第 153 脚；底板 RW100（NC/0R）提供另一条供电路径。RW103 连接 VCC-PG 与模组 VCCIO。AP-CK32K-OUT 经 J48/J71 第 154 脚到达底板。

硬件指南列出参考板默认 AW869C Wi‑Fi 6。底板图同时画出 UW2（AW869 系列，另有 AP6281s 晶振备注）和 U53（NF3205Q）焊位。参考设计 BOM 分别列有 UW2 和 U53 两个位置，并将 RW62、RW101 和 YW3 标为 NC。U53 的 32 kHz 走 RW92（0R），UW2 的 LPO 走 RW101（NC/0R），UW2 的蓝牙使能另经过 RW62（NC/0R）。Tina 的有效设备树没有为 WLAN 或 BT 注册可控的 32 kHz 时钟。实装型号仍须结合 SDIO ID 或实板丝印确认。

历史 Tina 串口记录中 `aicbsp_init` 和 `rwnx` 开始初始化，但 SDIO CMD52、CMD5 多次响应超时，驱动退出，未报告 SDIO 厂商或设备 ID。v31 先使用通用 SDIO 枚举读取身份，再据此选用驱动与固件。

## 2026-11-20 补充：已确认 AIC8800D80

用户确认实装 AW869C / AIC8800D80，且同一板此前在 Tina 中正常使用。
因此上述历史超时记录不能用来推断模组损坏或 Tina 一直不可用。
当前软件排查应以恢复原厂工作时的供电、引脚和主控启动状态为目标。

本轮开启 32 kHz、延长使能稳定时间、扫描命令相位仍未枚举 SDIO function。
PG0～5 的 GPIO 上拉读值为 111111，下拉为 011111，禁用拉阻为 111111；
这与 CMD/DATA 外部上拉相符，不能把复用态的 DAT0 读值当成所有数据线拉低。
诊断补丁位于 `boards/wireless-v31/diagnostics/`，不是已验证的无线功能。
AIC BSP/FDRV 模块已编译，但固件下载、Wi-Fi 扫描与蓝牙 HCI 均未验收。
蓝牙固件依赖 SDIO 下载，不能只靠出现 UART/rfkill 就宣称蓝牙通过。

尝试原厂 6.6.98 内核加不挂载磁盘的 RAM 根文件系统时，内核入口后即复位，
未进入测试脚本，因此没有取得原厂 SDIO 对照结果。此实验还留下异常的
CPU 电源/时钟状态，源 U-Boot 的保护检查拒绝升频，导致后续暖启动明显变慢。
完整断电后默认 v45 恢复 1.014 GHz 配置。跨启动链的暖复位兼容问题尚未修复，
不可直接重做该原厂内核试验，也不能将它记作“Tina 无线失败”。
共享 3.3 V 同时供应 PCIe SSD，本轮未切断该电源，未写入 SSD。

## 实板验收

下列命令可通过串口执行。保留内核版本，以免混淆 RC1 和 v31 的结果。

```sh
uname -r
ls /sys/class/mmc_host
cat /sys/kernel/debug/mmc1/ios
for f in /sys/bus/sdio/devices/*/uevent; do [ ! -f "$f" ] || cat "$f"; done
ls -l /dev/ttyS1
rfkill list
journalctl -k -b | grep -Ei '4021000|2501000|mmc1|sdio|rfkill|ttyS1|Bluetooth'
```

Wi‑Fi 通过条件为取得 SDIO ID、芯片驱动绑定、扫描到 AP、建立连接并传输数据。蓝牙须通过 HCI 读到控制器地址和版本，完成设备发现、配对和重连。仅出现 `ttyS1`、`mmc1` 或 rfkill 开关，都只能验证主控侧。板级通路探测可用 `rfkill` 单独开启本板蓝牙开关，再用 `btattach -B /dev/ttyS1 -P h4 -S 115200` 和 `btmgmt info` 读取事件；最终协议、波特率及固件下载流程须与实装模组匹配。
