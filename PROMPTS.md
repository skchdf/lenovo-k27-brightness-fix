# 可复用的 AI 提示词

以下提示词可以直接粘贴给有终端权限的 AI 助手（OpenCode、Claude Code、Codex 等），
用来复现本仓库的诊断、修复、验证与救援过程。把 `<...>` 替换成你的实际信息。

> **使用原则**：先让 AI 取证，再让它动手；一次只改一个变量；改 GRUB / 分区 /
> 磁盘前必须备份。AI 看不到你的屏幕，"屏幕到底变没变"必须由你明确告诉它。
>
> **只想重装后快速恢复？** 直接复制 [RESTORE.md](RESTORE.md) 里的端到端提示词，
> 不需要从本文挑。

---

## 0. 本次实际使用的提示词（脱敏）

### 0.1 初始描述（最关键的一条）

```text
我的电脑调整亮度不起作用。具体表现为：系统里有亮度调节滑块，但无论调到
50%、10%、90%，屏幕亮度都始终没有变化——系统认为自己已经调整了亮度，但我
看到的没有变化。等我关闭 ACPI 后再尝试，亮度调节反而可以起作用了。

机器是 <机型>，系统是 <发行版 + 内核 + 桌面环境>。
请先诊断原因，不要直接改配置。
```

这条提示词之所以有效，是因为它同时给了：

1. **现象**：有滑块、数值变、屏幕不变；
2. **关键差分**：关 ACPI 后正常；
3. **环境**：机型、系统、桌面；
4. **约束**：先诊断，不要直接改。

### 0.2 修复时的约束

```text
要的，但是要注意不要把我 GRUB 菜单里那些启动项顺序给改了。
```

### 0.3 修复后的追问

```text
你是怎么实现让屏幕能调整亮度的？请解释原理，不要只给命令。
```

### 0.4 发现新问题

```text
现在好了，可是当我把屏幕亮度调为 0 的时候，屏幕居然直接灭了，
整得我必须用 SSH 才调回来。请分析这是不是 bug，以及怎么避免/救援。
```

---

## 1. 初诊：判断是不是"ACPI 假背光"

```text
我在 <发行版 + 桌面环境> 上遇到亮度问题：
机型 <机型>，GPU <Intel/AMD/NVIDIA + 型号>，内核 <版本>。

现象：
- 系统设置里有亮度滑块；
- 拖动后百分比会变，/sys/class/backlight/<设备>/brightness 的数值也会变；
- 但屏幕实际亮度完全不变；
- <如果试过> 启动时加 acpi=off 后，亮度反而能调；
- dmesg 没有明显报错。

请按以下步骤诊断，不要先改配置，先收集证据：

1. `ls /sys/class/backlight/`，列出所有背光设备；
2. 对每个设备读取 type、max_brightness、brightness、actual_brightness；
3. `cat /proc/cmdline`，看当前内核参数；
4. `lspci -nnk | grep -A3 -i vga`，确认 GPU 和驱动；
5. `lsmod | grep -E 'i915|amdgpu|nouveau|video|ideapad'`；
6. `sudo dmesg | grep -iE 'backlight|brightness|acpi_video|i915'`；
7. 根据结果判断：
   - 如果 type=firmware/platform 且写值后屏幕不变：重点怀疑 ACPI 假背光；
   - 如果 type=raw 且屏幕仍不变：查 PWM/面板/DPCD/硬件；
   - 如果根本没有背光设备：查驱动/固件，不要直接加 acpi_backlight。

输出：设备列表、类型、范围、当前值、GPU/驱动、根因判断、建议的下一步。
```

## 2. 修复：加 `acpi_backlight=native`

```text
上一步确认了：<机型> 只有 acpi_video0（type=firmware），写值屏幕不变，
i915 已加载，硬件正常。请用 acpi_backlight=native 修复。

约束（重要）：
1. 先备份 /etc/default/grub 和 /boot/grub/grub.cfg，文件名带时间戳；
2. 只在现有 GRUB_CMDLINE_LINUX_DEFAULT 末尾追加 acpi_backlight=native，
   不要覆盖已有参数（如 quiet、zswap.enabled=0、nowatchdog）；
3. 不要改 GRUB_DEFAULT、GRUB_TIMEOUT、主题、os-prober 设置；
4. 修改前记录 menuentry/submenu 顺序，重新生成后核对顺序和默认项；
5. 用 `grub-mkconfig -o /boot/grub/grub.cfg` 重新生成；
   这是 <Legacy BIOS / UEFI> 机器，<不需要 / 需要> grub-install；
6. 验证 grub.cfg 中包含 acpi_backlight=native，且原有参数仍在；
7. 先不要重启，把 diff、生成的参数行、菜单核对结果给我看。
```

## 3. 重启后验证

```text
我已经重启，/proc/cmdline 里有 acpi_backlight=native。
请给我一份只读验证清单：

1. `ls /sys/class/backlight/` 应该看到什么？acpi_video0 是否应该消失？
2. `cat /sys/class/backlight/intel_backlight/type` 应该是什么？
3. 如何读取 max_brightness 并计算 5%/10%/50% 的安全测试值？
4. 如何用 `echo <值> | sudo tee .../brightness` 测试，而不把亮度设到 0？
5. KDE/GNOME 的滑块和快捷键应该如何验证？
6. 如果 intel_backlight 没出现，最可能的原因是什么？
   （参数没进 grub.cfg、没重启、内核不支持、被其他 acpi_backlight 参数覆盖）
7. 回滚步骤是什么？
```

## 4. 亮度 0 黑屏救援

```text
我把亮度调到 0，屏幕全黑了，但系统还在运行（电源灯亮、SSH 能连、
音乐还在播）。请给我救援步骤：

1. 从 SSH 读取 max_brightness，按 5% 计算一个安全值；
2. 给出写入 brightness 的命令，并确认 actual_brightness；
3. 如果 SSH 不可用，还有哪些办法（快捷键、外接屏、重启）？
4. 如何避免再次发生？优先不装常驻服务，给出"留一格"的操作建议；
5. 如果确实需要守护，给出一个最小 systemd 方案（轮询、检测 0、抬回 5%、
   记录日志、可卸载）；
6. 不要建议 acpi=off。
```

## 5. 通用模板（其他机型 / 其他 GPU）

```text
<发行版> + <桌面> + <Wayland/X11>，机型 <机型>，
GPU <Intel/AMD/NVIDIA + 型号>，内核 <版本>。
现象：亮度滑块有，数值会变，但屏幕亮度不变。
<如果试过> acpi=off 后正常 / 外接屏正常 / 某内核版本正常。

请帮我：
1. 判断这是 ACPI 假背光、驱动问题、PWM/面板问题，还是桌面设置问题；
2. 如果是 ACPI 假背光，按 acpi_backlight=native → vendor → video 的顺序
   给出最小改动方案，每次只改一个；
3. 给出只读取证命令、修改步骤、验证清单、回滚步骤；
4. 说明该方案在这个机型上的已知限制（亮度 0、快捷键、休眠唤醒）；
5. 不要用 acpi=off 作为长期方案，不要装不必要的包。

要求：先收集证据再动手；改 GRUB 前备份；不要改 /etc/fstab。
```

## 6. 让 AI 复盘并整理成教程

```text
请把这次亮度修复整理成一个 GitHub 教程仓库，面向遇到同样问题的 Linux 用户。

要求：
1. README：症状、适用环境、根因、修复步骤、验证、坑、回滚、目录结构；
2. MACHINE.md：本机型号、GPU、内核、桌面、修复前后 sysfs 值、亮度百分比对照；
3. docs/diagnosis.md：详细诊断过程、ACPI 背光 vs i915 原生背光的原理、
   通用诊断流程、不适用情况；
4. docs/recovery.md：亮度 0 黑屏的判断与救援、可选守护脚本；
5. docs/experience.md：复盘时间线、关键线索、踩过的坑、复用清单；
6. PROMPTS.md：本次实际提示词 + 可复用的诊断/修复/救援/通用模板；
7. scripts/：只读诊断、备份+修改+校验、验证、可选守护脚本；
8. 不要包含密码、用户名、IP、SSH 密钥等隐私信息；
9. 所有命令都要能复制执行，并注明预期输出；
10. 明确区分"接口值变化"和"屏幕实际变化"。
```

---

## 附：本次使用的系统提示（精简版）

```text
你是一名 Linux 背光 / ACPI 调试专家。目标：修复笔记本亮度调节无效的问题。

约束：
- 先只读取证（sysfs、dmesg、lspci、lsmod、/proc/cmdline），再改配置；
- 一次只改一个变量；每步先验证再继续；
- 改 GRUB 前备份 /etc/default/grub 和 /boot/grub/grub.cfg；
- 只追加/替换内核参数，不覆盖用户已有参数，不改菜单顺序和默认项；
- 不推荐 acpi=off 作为长期方案；
- 明确区分"brightness 数值变化"和"屏幕实际亮度变化"；
- 不装不必要的包；能用 sysfs 验证就不装 brightnessctl；
- 所有命令解释目的；给出验证、回滚、以及亮度归零黑屏的救援方案；
- 不要把密码、用户名、IP 等隐私写进命令或文档。
```

---

## 提示词写法建议

1. **说"屏幕有没有变"，不要只说"亮度不能调"**。
   "数值变了但屏幕不变"和"滑块是灰的"是完全不同的问题。
2. **给出关键差分**：关 ACPI 后正常吗？外接屏正常吗？换内核正常吗？
   这是最快锁定根因的信息。
3. **说清约束**：不要改菜单顺序、不要重装、不要装某个包、不要动 fstab。
4. **要求先取证**：让 AI 先列证据再给方案，避免上来就 `sed -i`。
5. **一次只改一个变量**：同时加三四个内核参数，出了问题不知道是谁的锅。
6. **要求给回滚**：尤其是 GRUB、分区、驱动相关操作。
7. **物理观察必须由人反馈**：AI 看不到屏幕，别让它"猜"屏幕变没变。
