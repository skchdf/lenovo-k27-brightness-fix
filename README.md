# Lenovo ZHAOYANG K27 亮度调节修复（ACPI 假背光 → i915 原生背光）

> 一台 2011 年的联想昭阳 K27，在 Arch Linux + KDE Plasma Wayland 下，
> 亮度滑块能从 10% 拖到 90%，系统里的数值确实变了，**屏幕亮度却纹丝不动**。
>
> 本仓库记录从现象到根因的完整诊断、修复步骤、验证与回滚方法、亮度归零黑屏的
> 救援办法，以及可复用的 AI 提示词。
>
> 修复只需要在内核命令行加一个参数：`acpi_backlight=native`。
> 不需要装驱动、不用 DKMS、不用改显示管理器。

## 症状

- 系统设置里有亮度滑块，拖动后百分比会变化。
- `/sys/class/backlight/acpi_video0/brightness` 的数值也跟着变。
- 屏幕实际亮度完全不变——不是"变化很小"，是**完全没反应**。
- 换桌面、换用户、重启都一样。
- **关键线索**：启动时加 `acpi=off`（关闭 ACPI）后，亮度反而能调。

## 适用环境

| 项目 | 值 |
|---|---|
| 机型 | Lenovo ZHAOYANG K27（昭阳 K27，2011，Legacy BIOS / MBR） |
| 系统 | Arch Linux，kernel `7.2.14-zen1-1-zen` |
| 桌面 | KDE Plasma `6.8.2`（Wayland / kwin_wayland） |
| GPU | Intel Sandy Bridge 核显（`8086:0106`，i915） |
| 面板 | LVDS，`intel_backlight` `max_brightness=4882` |
| 修复前 | `/sys/class/backlight/acpi_video0`，`type=firmware`，`max_brightness=10` |
| 修复后 | `/sys/class/backlight/intel_backlight`，`type=raw`，`max_brightness=4882` |

> 修复当时内核是 `7.2.4-arch1-2`；之后滚动到 `7.2.14-zen1-1-zen`，
> 参数和背光接口保持不变。

> 这套思路适用于所有"背光接口存在、数值能写、但屏幕不动"的 Linux 笔记本，
> 尤其是 2010–2013 年前后的老机器；不限于联想 K27，也不限于 Intel。

## 根因（一句话版）

内核默认注册了 ACPI 的 `acpi_video0` 背光接口（`type=firmware`），但这台机器的
ACPI 固件 `_BCM` 是个"假接口"：它只记住亮度数值，没有真正去驱动 i915 的 PWM。
所以系统认为亮度改了，屏幕没改。

加上 `acpi_backlight=native` 后，内核跳过 ACPI 背光，改用 i915 原生背光
（`/sys/class/backlight/intel_backlight`，`type=raw`），直接写 GPU 寄存器 / PWM，
亮度才真正生效。

更详细的机制、排除过程见 [docs/diagnosis.md](docs/diagnosis.md)。

## 修复（重装系统后照做）

### 1. 备份

```bash
sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d%H%M%S)
sudo cp /boot/grub/grub.cfg /boot/grub/grub.cfg.bak.$(date +%Y%m%d%H%M%S)
```

### 2. 在现有内核参数后追加 `acpi_backlight=native`

编辑 `/etc/default/grub`，把：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=2 zswap.enabled=0"
```

改成：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=2 zswap.enabled=0 acpi_backlight=native"
```

> **不要覆盖**你已有的参数（比如 `quiet`、`nowatchdog`、`zswap.enabled=0`），
> 只在末尾追加。参数顺序通常无所谓，但保留原参数可以避免引入新变量。

或者直接用仓库里的脚本（会备份、显示 diff、重新生成并校验）：

```bash
sudo ./scripts/apply-fix.sh
```

### 3. 重新生成 GRUB 配置

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

> 这台机器是 **Legacy BIOS + MBR**，没有 UEFI/ESP。改内核参数只需要
> `grub-mkconfig`，**不需要** `grub-install`。
> UEFI 机器同样只需要 `grub-mkconfig`；只有重装/修复引导时才需要
> `grub-install`。

### 4. 重启

```bash
sudo reboot
```

## 验证

```bash
# 1. 内核命令行里应该有 acpi_backlight=native
cat /proc/cmdline

# 2. 背光设备应该变成 intel_backlight，且 type=raw
ls /sys/class/backlight/
cat /sys/class/backlight/intel_backlight/type
# 期望输出：raw

# 3. 记录最大亮度，然后手动测试中间值
cat /sys/class/backlight/intel_backlight/max_brightness   # 本机 4882
echo 244  | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 2440 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 4882 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

每写一个值，屏幕应立刻变暗 / 变亮。KDE 的亮度滑块和快捷键也应同时生效。

> **不要用 `0` 测试！** `0` 是真正的"关背光"，屏幕会全黑，见下一节。
> 日常测试用 5%（244）就够了。

也可以运行只读检查脚本：

```bash
./scripts/verify.sh
```

## 大坑：亮度调到 0 会黑屏

`intel_backlight` 的 `brightness` 直接控制 PWM，**`0` = 背光完全关闭**。
KDE 的滑块可以一路拖到 0，于是屏幕全黑，但系统还在正常运行。

救援（本机 `sshd` 已启用）：

```bash
# 从另一台机器 SSH 进来
ssh <user>@<host>
echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

`244` 是本机最大亮度 `4882` 的 5%，极暗但仍可见。也可以：

- 连按亮度增加快捷键（如果 KDE/硬件仍响应）；
- 接外接显示器，在外接屏上操作；
- 直接重启（i915 初始化通常会恢复默认亮度，但不要把它当唯一手段）。

预防：

- 日常不要把滑块/快捷键减到 0，留 1 格（本机约 5% = 244）。
- 经常误触的话，可选用 `scripts/brightness-guard.sh` + systemd 守护，
  检测到 0 自动抬回 5%。**本机没有安装**——知道坑在哪、留一格就够了。

完整的黑屏判断与救援步骤见 [docs/recovery.md](docs/recovery.md)。

## 为什么不用 `acpi=off`？

`acpi=off` 确实能让亮度恢复正常，但它是"把整栋楼的电闸拉了来修一盏灯"：

- 关闭 ACPI 后，电池电量、温度传感器、风扇策略、休眠/唤醒、合盖、电源键、
  亮度快捷键等都可能失效；
- 部分机器会失去多核调度、PCIe 热插拔等能力；
- 系统可能能开机，但变成一个"能用但残废"的状态。

正确做法是只让 ACPI 交出背光控制权：`acpi_backlight=native`。

## 回滚

找到备份文件（带时间戳），覆盖回去：

```bash
ls -l /etc/default/grub.bak.* /boot/grub/grub.cfg.bak.*
sudo cp /etc/default/grub.bak.<时间戳> /etc/default/grub
sudo cp /boot/grub/grub.cfg.bak.<时间戳> /boot/grub/grub.cfg
sudo reboot
```

或者手动删掉 `acpi_backlight=native`，再执行一次
`sudo grub-mkconfig -o /boot/grub/grub.cfg`。

## 目录结构

```
.
├── README.md                        # 本文件：症状、原理、修复、验证、坑
├── MACHINE.md                       # 本机完整参数与修复前后现场数据
├── PROMPTS.md                       # 可复用的 AI 诊断/修复/救援提示词
├── docs/
│   ├── diagnosis.md                 # 深入诊断：为什么 ACPI 背光是假的
│   ├── recovery.md                  # 亮度归零黑屏的救援手册
│   └── experience.md                # 复盘：这次修复是怎么一步步完成的
├── scripts/
│   ├── diagnose.sh                  # 只读诊断，收集现场证据
│   ├── apply-fix.sh                 # 备份 + 修改 GRUB + 校验
│   ├── verify.sh                    # 重启后的只读验证
│   ├── brightness-guard.sh          # 可选：防止亮度归零的守护脚本
│   └── brightness-guard.service     # 可选的 systemd 服务
└── LICENSE                          # MIT
```

## 快速自检清单（重装后）

- [ ] `/proc/cmdline` 含 `acpi_backlight=native`
- [ ] `ls /sys/class/backlight/` 只有 `intel_backlight`（没有 `acpi_video0`）
- [ ] `cat /sys/class/backlight/intel_backlight/type` 是 `raw`
- [ ] `echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness` 屏幕立刻变暗
- [ ] KDE 滑块 / 快捷键能真实调节
- [ ] 知道 `0` 会黑屏，以及 SSH 救援命令

## 相关

- 同机型触控板修复：[lenovo-k27-alps-touchpad-fix](https://github.com/skchdf/lenovo-k27-alps-touchpad-fix)
- 同机型显示缩放：[screensmith](https://github.com/skchdf/screensmith)
- 详细诊断：[docs/diagnosis.md](docs/diagnosis.md)
- 黑屏救援：[docs/recovery.md](docs/recovery.md)
- 修复复盘：[docs/experience.md](docs/experience.md)
- AI 提示词：[PROMPTS.md](PROMPTS.md)
- 本机参数：[MACHINE.md](MACHINE.md)

## English summary

On this 2011 Lenovo ZHAOYANG K27 (Sandy Bridge, Arch Linux, KDE Plasma Wayland),
the brightness slider changed values but the panel stayed at full brightness.
The kernel exposed only `acpi_video0` (`type=firmware`), whose ACPI `_BCM` method
is a no-op on this firmware. Adding `acpi_backlight=native` to the kernel command
line makes i915 register `intel_backlight` (`type=raw`) and drive the PWM directly.

Beware: brightness `0` turns the panel off completely; recover over SSH with
`echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness`.

## License

MIT
