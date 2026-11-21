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

## v47 通路对照（2026-11-20）

结果：尚未枚举 AIC8800D80；Wi-Fi、蓝牙均未验收通过。

在当前 GNOME v47 上做了五组 SDIO1 重绑实验：主控/CCU 只读记录、
关闭 CE-ATA 位、WLAN/BT 同时复位保持 1 秒、GPIO 模拟 CMD5、
400 kHz 时钟开启后再复位 WLAN 100 ms 并稳定 1 秒。
每组两条 CMD52 和四条 CMD5 均返回 `IRQ=0x104, resp0=0`。
日志含此前环形缓冲的记录；以最后一组 `pad voltage` 起始行区分本次数据。

时钟门读回：SMHC1 `8000001d`、bus `00010001`、store `110103ff`、
MSI lite1 `00030001`，store bit24 和 MSI bit0 已置位。
CE-ATA 清零读回正确，WLAN 延后复位时 PM4 低/高读回正确，仍无响应。
GPIO 模拟使用 CMD0 CRC `95`、CMD5 CRC `5b`，256 个采样周期未见 CMD 起始位，
测试后 PG 复用恢复 `22222222`。该测试没有示波器验证模组端时序，不能作为硬件故障定论。

现存 Debian11 XFCE boot0-preserved 和 Buildroot LPDDR5 镜像中，包含无线节点的
DTB 都为 213741 字节，SHA-256 见 results.json；两者均采用 PM4 WLAN、PM0 BT、
SDIO1 PG0～5、3.3 V VBAT 与 1.8 V VIO。它们是否就是用户以前可用的镜像仍待确认。
未重启旧 Tina 内核，未写入任何旧镜像。

AIC BSP/FDRV 已针对当前 v47 重新编译，vermagic 和 SHA-256 见 modules-v47.json。
两模块均未加载，固件未安装/下载，不能将编译成功记为无线可用。

实验结束：sunxi-mmc 已重新绑定、override 清空、诊断模块卸载、rfkill 原状态恢复；
GNOME display-manager active，0 failed units。未改默认启动，未切共享 3.3 V，未写 SSD。

详见 [五组实验与恢复记录](../evidence/wireless-path-20261120/README.md)。


## Debian11 对照及 GPIO 输出补验

用户回复“1”，本轮按第一类 Debian11 XFCE 镜像处理；具体文件名未再次确认。
直接核对 boot0_preserved 镜像内 rootfs.fex 与保留的原内核 rootfs 稀疏文件，
SHA-256 相同：`f98b44654730ea8629dc04a8cfaca12656ea3804011c15a7f7d6d9502af4d105`。
用 debugfs 只读提取镜像内脚本，确认与 staging 两份脚本逐字节相同。
解稀疏临时 raw 已删除，未额外长期占用约 2.5 GB。

旧系统顺序为 BSP → FDRV → BTLPM → btwrite=1 → hciattach aic。
模组固件目录包括 aic8800d80；只保存文件清单，未安装或分发固件内容。
旧镜像 PG0=20mA，PG1～5=10mA，均上拉；当前运行设备树相同。
旧 DTBO 修改板号/触摸屏等内容，没有无线供电或引脚覆盖。

GPIO 模拟改为 Linux GPIO 同款数据寄存器 RMW 后，CLK 低/高分别读回
0x2/0x3（CMD 保持高），整个查询及采样耗时 3.081322 ms。
256 个响应时钟内 CMD 一直为高，未检测到起始位；原生 CMD52/CMD5 仍六次超时。
这验证主控端输出寄存器切换，不代表已测到模组端波形，也不能据此认定硬件损坏。

已恢复 sunxi-mmc、清空 override、卸载诊断模块、恢复 rfkill 原状态；
display-manager active，无 failed units。下一步缺模组端测量，已询问现场测量条件。


## 外部 32 kHz 时钟源对照

后续原理图与 AW869C 专用手册复核已纠正本节试验的解释：AW869C 的
LPO 脚要求悬空，独立 BT_DIS 为保留脚，参考图中两条串联电阻均标 NC。
不能将外部 32 kHz 或 PM0 当作 AW869C 启动的必需条件。芯片型号仍是
用户确认的 AIC8800D80。详见
[2026-11-21 原理图复核](../evidence/wireless-path-20261120/SCHEMATIC-AUDIT-20261121.md)。

用户暂时不方便测量，本轮继续验证 RTC 时钟源。只读快照为：
LOSC_CTRL=0x4010，LOSC_STATUS=0，FANOUT=0，XO_CTRL=0x983fb0f7。
按 Tina `ccu-sun60iw2-rtc.c` 定义，外部晶振已开启，状态未报异常，
但 OSC32K 的 parent bit0 仍选内部 RC；Tina 初始化会选择外部晶振。
此前仅打开输出门的试验没有覆盖这个源选择差异。

临时按 Tina 选择外部晶振（0x4010→0x4011）并打开 32 kHz 输出门。
分别在 BT 使能、BT 保持复位两种条件下重新枚举 SDIO，均为两条 CMD52、
四条 CMD5 响应超时，未出现 SDIO function。不能把这个差异当成已确定根因。
试验后只还原修改过的源选择位；快照确认 LOSC_CTRL=0x4010、FANOUT=0，
XO_CTRL/状态保持原值。sunxi-mmc 绑定、override、rfkill 均恢复，诊断模块卸载，
GNOME display-manager active，0 failed units，未改变默认镜像和共享电源。

诊断源/补丁和两组原始日志已保存。未进行晶振频率或模组端波形实测，
目前仍不能确定是启动链配置遗漏还是模组端电气通路问题。


## 2026-11-21 实板电源与耐压模式复测

已临时启动只读 PMIC 诊断内核：DCDC1、SW2、DLDO5 均开启，配置电压为 3.3 V / 1.8 V；不代表模组端电压实测。PG/PM 按 T736 手册分别试自动和固定 1.8 V 耐压模式，并复测延时 CMD5、GPIO 模拟查询，仍无 SDIO 响应。每组均恢复原配置，未安装永久修复。详见 [实板记录](../evidence/wireless-path-20261120/RUNTIME-TRIALS-20261121.md)。
