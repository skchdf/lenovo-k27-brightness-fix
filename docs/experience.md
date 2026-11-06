# 复盘：这次亮度修复是怎么一步步完成的

> 本文不是命令手册，而是"经验"部分：哪些信息让诊断变快、哪些坑差点踩进去、
> 以及换一台机器时怎样复用这套思路。具体命令见 [diagnosis.md](diagnosis.md)，
> 操作步骤见 [../README.md](../README.md)。

## 1. 起点：一个被忽略的关键线索

最初的描述是：

> 系统里有亮度滑块，但不管调到 50%、10%、90%，屏幕亮度都始终没有变化。
> 系统认为自己已经调整了亮度。**等我关闭 ACPI 以后再进行尝试，亮度调节反而
> 可以起作用了。**

这句话里其实已经包含了 80% 的答案：

- "滑块有、数值变" → 桌面和 sysfs 接口正常；
- "屏幕不变" → 数值没有变成硬件动作；
- "关 ACPI 后正常" → 硬件、PWM、i915、桌面全都正常，问题只在 ACPI 背光路径。

如果只看到"亮度不能调"就去重装驱动、换内核、装 `brightnessctl`，会绕很远。
**先把现象拆成"哪一层正常、哪一层不正常"，比盲目试错快得多。**

## 2. 时间线

### 2026-09-11 21:55 — 初次诊断

AI 先做只读取证，没有改任何配置：

- `ls /sys/class/backlight/` → 只有 `acpi_video0`；
- `type=firmware`，`max_brightness=10`；
- 写 `brightness` 数值会变，`actual_brightness` 也变；
- `lspci` 确认是 Intel Sandy Bridge + i915；
- `dmesg` 没有背光报错；
- DMI 确认机型是联想昭阳 K27，面板是 LVDS。

结论：**ACPI video 接口存在且"工作正常"，但它没有真正驱动 PWM。**

### 21:58–22:01 — 排除其他可能

- 检查 `video` 模块参数、`ideapad_laptop` 参数；
- 检查 `acpi_video0` 的 `type`、`bl_power`、`actual_brightness`；
- 确认 GPU 驱动是 i915，面板是 LVDS；
- 没有发现硬件错误。

这一步的意义是：**确认不是权限、不是范围、不是驱动没加载、不是面板坏。**

### 22:01 — 给出方案

AI 提出：在 GRUB 内核命令行加 `acpi_backlight=native`，强制走 i915 原生背光。
预期重启后 `acpi_video0` 消失，出现 `intel_backlight`。

同时明确说了原理：ACPI 的 `_BCM` 只是"假装"改值，i915 原生接口才真正写 PWM。

### 22:02–22:16 — 用户提出约束，谨慎修改

用户说：

> 要的，要的，但是要注意不要把我 grub 菜单里那些启动项顺序给改了。

这是一个非常好的约束。于是操作变成：

1. 备份 `/etc/default/grub` 和 `/boot/grub/grub.cfg`；
2. 记录当前 `menuentry` / `submenu` 顺序；
3. 只替换 `GRUB_CMDLINE_LINUX_DEFAULT` 一行；
4. `grub-mkconfig` 重新生成；
5. 核对菜单顺序、`GRUB_DEFAULT`、参数是否都还在；
6. 确认无误后才重启。

实际结果是：菜单顺序没变，`GRUB_DEFAULT` 没变，只有 `Advanced options` 的
显示文字因为 locale 变成了中文（纯显示，无影响）。

### 2026-09-12 00:30 — 重启验证

- `ls /sys/class/backlight/` → `intel_backlight`；
- `type=raw`，`max_brightness=4882`；
- 亮度滑块/快捷键真正生效。

修复成功。

### 00:30–00:33 — 新问题：亮度 0 黑屏

用户把亮度调到 0，屏幕直接全黑，只能 SSH 进去调回来。

AI 检查了：

- 内核版本 7.2.4；
- `intel_backlight` 没有 `min_brightness` 接口；
- KDE 滑块没有最小值限制；
- `brightnessctl` / `inotifywait` 都没装。

提出两个方案：

1. 装一个守护脚本，检测到 0 自动抬回 5%；
2. 不装，日常留一格，记住 SSH 救援命令。

用户选择**不装**。这个决定是合理的：知道 0 会黑、留一格，比多一个常驻服务简单。
仓库仍然保留守护脚本，供需要的人选用。

## 3. 这次为什么能快速修好

### 3.1 关键差分实验

"关 ACPI 后正常"是一个天然的 A/B 测试：

| 条件 | 结果 |
|---|---|
| 默认（ACPI 背光） | 数值变，屏幕不变 |
| `acpi=off`（无 ACPI） | 屏幕真的变 |

两组的唯一差别是 ACPI 背光路径，于是根因被直接锁定。

### 3.2 区分"接口正常"和"硬件被驱动"

`brightness` 写入成功、`actual_brightness` 同步变化，只能证明**内核的
backlight 子系统**正常，不能证明**硬件**被驱动。这是本次最大的认知点。

### 3.3 选择最小改动

没有重装驱动、没有换内核、没有装 `brightnessctl`、没有改 `fstab`、
没有长期使用 `acpi=off`。只加了一个内核参数。

### 3.4 改 GRUB 前先备份、改完核对

GRUB 是"改错就开不了机"的区域。备份 + 只改一行 + 核对菜单顺序 +
核对默认项，这套流程值得保留。

### 3.5 把"修复后的坑"也算进修复

亮度 0 黑屏不是新故障，而是原生背光的正常行为。修复方案如果不包含
"如何避免/如何救援"，就不算完整。

## 4. 踩过的坑 / 差点踩的坑

| 坑 | 后果 | 正确做法 |
|---|---|---|
| 用 `acpi=off` 长期使用 | 电池、温度、休眠、快捷键、多核等可能失效 | 只用 `acpi_backlight=native` |
| 直接覆盖 `GRUB_CMDLINE_LINUX_DEFAULT` | 丢失 `zswap.enabled=0` 等已有参数 | 在现有值后追加 |
| 改完不核对菜单 | 启动项顺序/默认项可能变化 | 备份 + 记录 + 重新生成后核对 |
| 用 0 测试亮度 | 屏幕全黑 | 用 5%（244）测试 |
| 以为 `acpi_video0` 的 symlink 指向 GPU 就是在控制 GPU | 误判根因 | 看 `type` 和实际屏幕反应 |
| 装一堆背光工具 | 不一定解决问题，还增加依赖 | 先直接写 sysfs 验证 |

## 5. 给未来的自己：换机器时的复用清单

1. **先描述现象，不要先猜原因**：
   - 有没有滑块？
   - 数值变不变？
   - 屏幕变不变？
   - 关 ACPI / 换内核 / 外接屏时有没有变化？
2. **只读取证**：
   ```bash
   ls /sys/class/backlight/
   for d in /sys/class/backlight/*; do
     echo "$d type=$(cat $d/type) max=$(cat $d/max_brightness) cur=$(cat $d/brightness)"
   done
   cat /proc/cmdline
   lspci -nnk | grep -A3 -i vga
   sudo dmesg | grep -iE 'backlight|brightness|acpi_video|i915'
   ```
3. **做差分实验**：临时 `acpi=off` 或换 `acpi_backlight=` 的取值，一次只改一个。
4. **选最小方案**：优先 `acpi_backlight=native`，不行再 `vendor`。
5. **改 GRUB 前备份，改完核对**。
6. **修复后想清楚边界**：0 会不会黑？快捷键是否生效？休眠唤醒后是否保持？
7. **记录下来**：机型、内核、GPU、修复前后 sysfs 值、验证命令。下次重装直接照做。

## 6. AI 在這次修复里做了什么、没做什么

**做了**：

- 读 sysfs / dmesg / lspci / 模块参数，收集证据；
- 把"关 ACPI 后正常"翻译成"ACPI 背光路径有问题"；
- 给出 `acpi_backlight=native` 这个最小改动；
- 备份、改 GRUB、重新生成、核对；
- 发现 0 黑屏后，继续查 `min_brightness` 和桌面限制，给出救援/守护方案。

**没做**：

- 看不到屏幕，必须靠用户描述"屏幕到底变没变"；
- 不能替用户决定"要不要装守护服务"；
- 不能保证所有机型都适用，换机要重新验证。

**结论**：AI 适合做"证据整理 + 方案枚举 + 风险控制"，但**物理观察和最终决策
仍然在人这边**。提示词里把现象、约束、已经试过的操作说清楚，效果会好很多。

## 7. 一句话总结

> 亮度滑块能动，不等于背光被驱动；`acpi=off` 能好，不等于应该用它。
> 找到"哪一层在假装工作"，然后只改那一层。
