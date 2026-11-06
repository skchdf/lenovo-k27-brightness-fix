# 诊断笔记：为什么亮度滑块"能调"，屏幕却不动？

本文记录从现象到根因的完整推导。重点不是记住 `acpi_backlight=native` 这条命令，
而是理解**怎样判断问题出在 ACPI 背光这条路，而不是硬件、驱动或桌面环境**。

## 1. 现象

- 联想昭阳 K27（2011，Sandy Bridge，Arch Linux + KDE Plasma Wayland）。
- 系统设置里有亮度滑块；拖动后百分比会变。
- `/sys/class/backlight/acpi_video0/brightness` 的数值也会变。
- 屏幕亮度**完全不变**。
- 没有报错，没有闪屏，没有花屏，就是"数值在动，灯不动"。

这种"接口存在、写入成功、硬件无反应"的组合，最容易让人误判为"背光坏了"或
"驱动没装"。但后续的实验会证明：**硬件和驱动都是好的，坏的是 ACPI 这条控制路径。**

## 2. 第一轮取证（修复前）

### 2.1 有哪些背光设备？

```bash
$ ls /sys/class/backlight/
acpi_video0
```

只有一个 `acpi_video0`，说明内核当前选择的是 ACPI 背光，而不是 i915 原生背光。

```bash
$ cat /sys/class/backlight/acpi_video0/type
firmware

$ cat /sys/class/backlight/acpi_video0/max_brightness
10

$ cat /sys/class/backlight/acpi_video0/brightness
10
```

`type=firmware` 表示这个接口由固件（ACPI）负责，不是内核驱动直接控制硬件。
`max_brightness=10` 也是 ACPI video 常见的档位式范围。

### 2.2 写入真的生效了吗？

把 `brightness` 从 10 写到 1、5、9：

```bash
echo 1 | sudo tee /sys/class/backlight/acpi_video0/brightness
cat /sys/class/backlight/acpi_video0/brightness
cat /sys/class/backlight/acpi_video0/actual_brightness
```

数值确实变了，`actual_brightness` 也跟着变——**但屏幕没有任何变化**。

这说明：

1. 权限没问题；
2. sysfs 接口没坏；
3. 内核的 backlight 子系统在正常工作；
4. 问题出在"这个接口背后到底有没有真的写硬件"。

### 2.3 驱动和模块

```bash
$ lspci -nnk | grep -A3 -i vga
00:02.0 VGA compatible controller [0300]: Intel Corporation 2nd Generation Core Processor Family Integrated Graphics Controller [8086:0106] (rev 09)
        Subsystem: Lenovo Device [17aa:3975]
        Kernel driver in use: i915
        Kernel modules: i915

$ lsmod | grep -E 'i915|video|ideapad'
i915                 5099520  30
video                  81920  2 ideapad_laptop,i915
ideapad_laptop         ...
```

i915 已加载，`video`（ACPI video）也已加载。硬件识别正常。

### 2.4 dmesg 没有背光报错

```bash
sudo dmesg | grep -iE 'backlight|brightness|acpi_video|i915'
```

没有有用的报错。**"没有报错"本身是重要线索**：如果 PWM、面板或驱动真的坏了，
通常会看到初始化失败、I2C/DPCD 超时、PWM 注册失败之类的消息。这里什么都没有，
更像是"接口在正常地做无用功"。

> 注意：普通用户读 `dmesg` 可能被 `kernel.dmesg_restrict=1` 拦住，
> 需要 `sudo dmesg` 或 `journalctl -k`。

## 3. 关键实验：关掉 ACPI 反而正常

启动时临时加 `acpi=off`（在 GRUB 里按 `e` 编辑，或写入测试配置），结果：

- 亮度滑块/快捷键恢复，屏幕真的变亮变暗。
- 说明 **PWM、面板、i915 硬件链路全是好的**。
- 也说明桌面环境、KDE 的亮度控制链路是好的。

这个实验把问题范围缩到了唯一一处：**ACPI 背光接口**。

逻辑链：

```
滑块有                 → 桌面/内核接口存在
写 brightness 数值变    → sysfs/backlight 子系统正常
屏幕不变               → 数值没有变成硬件动作
acpi=off 后屏幕会变     → 硬件、PWM、i915、桌面全都没问题
∴ 问题在 ACPI 背光这条路径
```

## 4. 机制：ACPI 背光 vs i915 原生背光

### 4.1 ACPI video 背光

ACPI 规范里，显示设备可以通过 `_BCM`（Brightness Control Method）设置亮度，
通过 `_BQC`（Brightness Query Current）查询当前亮度。`acpi_video` 驱动会把它们
包装成 `/sys/class/backlight/acpi_video0/`。

关键点：**`_BCM` 是固件（BIOS/EC）实现的**。它内部可以：

- 真的去写 GPU/EC 的 PWM 寄存器；
- 也可以只是把值存进一个 ACPI 变量，什么硬件都不碰。

这台 2011 年的联想，固件属于后者。于是：

- 内核写 `_BCM(5)`；
- ACPI 固件更新自己的"当前亮度"变量；
- `_BQC` 返回 5；
- `brightness` / `actual_brightness` 都显示 5；
- 但 PWM 占空比没变，屏幕当然不变。

`acpi_video0/device` 这个 symlink 指向 `0000:00:02.0`（GPU），只表示 ACPI 设备
和 GPU 的关联关系，**不代表 `_BCM` 真的在写 GPU 寄存器**。这是很容易误判的一点。

### 4.2 i915 原生背光

Sandy Bridge 的 LVDS 背光由 i915 直接控制 PWM 寄存器。i915 注册的接口是：

```text
/sys/class/backlight/intel_backlight/
```

`type=raw` 表示它不是固件代理，而是驱动直接算 PWM：

```text
brightness 0    → PWM 占空比 0，背光完全关闭
brightness max  → PWM 占空比 100%
```

在本机上 `max_brightness=4882`，所以写入值就是 PWM 的原始刻度。

### 4.3 内核如何二选一

内核启动时会检测可用的背光接口。默认策略下，ACPI video 往往优先注册，
一旦 `acpi_video0` 出现，用户空间（KDE、systemd-logind）就会优先用它。
i915 的原生接口可能仍然存在，也可能被隐藏/不注册，取决于内核版本和检测顺序。

`acpi_backlight=native` 的作用就是告诉内核：

> 不要用 ACPI video 的背光接口，优先让原生驱动（这里是 i915）来注册背光。

重启后 `acpi_video0` 消失，`intel_backlight` 出现，亮度控制直接落到 PWM 上。

## 5. 为什么 `acpi=off` 也能好，但不能用它

`acpi=off` 让 ACPI 整个不工作，`acpi_video` 驱动自然不会注册背光，i915 就退回
原生背光——所以亮度"好了"。

但代价是：

- 电池电量、温度传感器、风扇策略可能失效；
- 休眠/唤醒、合盖、电源键、亮度快捷键可能失效；
- 部分机器会失去多核调度、PCIe 热插拔等能力；
- 系统日志、电源管理、热管理都会变得不可靠。

这相当于"为了修一盏灯，把整栋楼的配电都断了"。`acpi_backlight=native` 只针对
背光这一项，范围小得多。

## 6. 方案对比

| 方案 | 效果 | 风险 / 评价 |
|---|---|---|
| `acpi_backlight=native` | 跳过 ACPI 背光，用 i915 原生 PWM | **本机采用**，范围最小 |
| `acpi=off` | 亮度恢复 | 关闭整个 ACPI，副作用大，不推荐 |
| `acpi_backlight=video` | 强制用 ACPI video | 本机正是它坏了，无效 |
| `acpi_backlight=vendor` | 优先厂商驱动（如 ideapad_laptop） | 可尝试；本机未验证，native 已解决 |
| `acpi_backlight=none` | 禁用 ACPI 背光接口 | 可能导致完全没有背光接口，慎用 |
| `video.use_native_backlight=1` | 老内核的类似开关 | 新内核已移除/不推荐，统一用 `acpi_backlight=native` |
| `i915.enable_dpcd_backlight=1` | 针对 eDP/DPCD 背光 | 本机是 LVDS，不适用 |

> 顺序建议：先 `native`；不行再试 `vendor`；再不行才考虑 `video`/`none`。
> 每次只改一个参数，改完重启验证，不要一次加一堆。

## 7. 改 GRUB 时的风险控制

改内核参数本身很简单，但 GRUB 是"改错就开不了机"的区域。这次的做法：

1. **双备份**：`/etc/default/grub` 和 `/boot/grub/grub.cfg` 都带时间戳备份。
2. **只改一行**：只替换 `GRUB_CMDLINE_LINUX_DEFAULT`，不动 `GRUB_DEFAULT`、
   `GRUB_TIMEOUT`、主题、os-prober 设置。
3. **记录菜单项**：改之前 `grep -a -E '^(menuentry|submenu) '` 记录顺序。
4. **重新生成**：`grub-mkconfig -o /boot/grub/grub.cfg`。
5. **事后核对**：
   - 菜单项数量和顺序是否一致；
   - `acpi_backlight=native` 是否出现在 linux 启动项；
   - `GRUB_DEFAULT` 是否仍是原来的值。
6. **重启验证**：`/proc/cmdline`、`ls /sys/class/backlight/`、手动写亮度。

> 本机是 Legacy BIOS + MBR，改内核参数不需要 `grub-install`。只有引导本身
> （MBR/core.img）损坏或重装时才需要 `grub-install --target=i386-pc`。

### 关于菜单标题变成中文

`grub-mkconfig` 会根据当前 `LANG`/`LC_ALL` 翻译菜单标题。这次重新生成后，
`Advanced options for Arch Linux` 显示成了 `Arch Linux 的高级选项`。这是纯显示
文本，不影响启动项、顺序或默认项。想保持英文可以在生成时加 `LC_ALL=C`。

## 8. 修复后的验证

```bash
$ cat /proc/cmdline
... acpi_backlight=native

$ ls /sys/class/backlight/
intel_backlight

$ cat /sys/class/backlight/intel_backlight/type
raw

$ cat /sys/class/backlight/intel_backlight/max_brightness
4882
```

然后手动写 244 / 2441 / 4882，屏幕应实时变化。

## 9. 通用诊断流程（其他机器）

```text
1. ls /sys/class/backlight/
   ├─ 没有任何设备 → 查驱动/固件，可能是另一个问题
   └─ 有设备 → 继续

2. 记录 type / max_brightness，写一个中间值
   ├─ 写入报错（EACCES/EINVAL）→ 权限或范围问题
   └─ 写入成功 → 继续

3. 屏幕是否变化？
   ├─ 变 → 正常，结束
   └─ 不变 → 继续

4. 看 type
   ├─ firmware / platform → 可能是固件假接口，重点怀疑 ACPI
   └─ raw → 原生驱动已接管但屏幕仍不变 → 查 PWM/面板/DPCD

5. 临时用 acpi=off 启动测试
   ├─ 亮度恢复 → 几乎可以确定是 ACPI 背光路径问题
   └─ 仍然不变 → 不是 ACPI 的问题，转查硬件/驱动

6. 在 GRUB 加 acpi_backlight=native，重启验证
   ├─ 出现 intel_backlight 且生效 → 修复完成
   └─ 无效 → 试 vendor，或查该机型的专用 quirk/驱动
```

## 10. 什么情况下这套方法不适用

- **完全没有 `/sys/class/backlight/` 设备**：可能是驱动没加载、面板不被支持，
  或内核根本没注册背光。先解决驱动，不是加 `acpi_backlight`。
- **`intel_backlight` 已存在，但写值仍无变化**：说明原生驱动已经接管，
  问题可能在 PWM 通道、面板、EC 或硬件本身。
- **`brightness` 写入返回 `EINVAL`**：值超出 `max_brightness`，或被驱动拒绝。
- **外接显示器亮度**：通常由显示器自己的 DDC/CI 控制，不走这里的 sysfs。
- **NVIDIA 独显直连 / AMD GPU**：原生驱动名字和接口不同，但"让 ACPI 交出背光、
  用原生驱动"的思路相同；具体参数要按厂商文档调整。

## 11. 参考

- 内核参数文档：`acpi_backlight=` 的 `vendor` / `video` / `native` / `none` 语义。
- 内核 backlight 子系统：`/sys/class/backlight/<device>/{type,max_brightness,brightness,actual_brightness}`。
- ACPI 规范：`_BCM`（设置亮度）、`_BQC`（查询亮度）。
- 本机实测记录：[MACHINE.md](../MACHINE.md)。
- 黑屏救援：[recovery.md](recovery.md)。
