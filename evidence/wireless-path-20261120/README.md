# v47 无线通路对照（2026-11-20）

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

下一步需要此前成功使用的 Tina 镜像身份，以提取实际启动配置继续对照；
若仍无法区分，需要模组端电压、使能、晶振、CLK/CMD 波形证据。


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


## 2026-11-21 schematic follow-up

See [AW869C schematic audit](SCHEMATIC-AUDIT-20261121.md). The module identity
is AIC8800D80. External LPO/PM0 assumptions were corrected; a read-only SW2
snapshot patch compiled but is not installed. WLAN/BT remain unverified.


[2026-11-21 PMIC / pad-mode hardware results](RUNTIME-TRIALS-20261121.md) supersede the earlier compile-only PMIC status. Still no SDIO enumeration.
