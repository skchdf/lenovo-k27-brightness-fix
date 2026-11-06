# 本机参数（Lenovo ZHAOYANG K27）

> 最后核实：**2026-11-06**
> 用途：重装系统后照本文件直接恢复亮度修复，**不需要重新诊断**。
> 如果换了硬件、换了内核大版本，或 `intel_backlight` 的行为变了，再按
> [docs/diagnosis.md](docs/diagnosis.md) 重新确认。

## 1. 整机

| 项目 | 值 |
|---|---|
| 型号 | Lenovo ZHAOYANG K27（昭阳 K27，2011） |
| 主板 / BIOS | `KLx` / `46CN21WW`，Legacy BIOS（无 UEFI，无 ESP） |
| CPU | Intel Pentium B970 @ 2.30 GHz（2 核 2 线程，Sandy Bridge） |
| 内存 | 3.7 GiB |
| GPU | Intel 2nd Gen Core iGPU（`8086:0106`，驱动 `i915`） |
| 显示 | LVDS 内置面板 |
| 系统 | Arch Linux，kernel `7.2.14-zen1-1-zen` |
| 桌面 | KDE Plasma `6.8.2`（Wayland / kwin_wayland） |
| 启动 | GRUB（`grub-mkconfig`），Legacy BIOS |
| 电源 | 电池 + 电源适配器 |

## 2. 修复前（故障现场）

```text
$ ls /sys/class/backlight/
acpi_video0

$ cat /sys/class/backlight/acpi_video0/type
firmware

$ cat /sys/class/backlight/acpi_video0/max_brightness
10

$ cat /sys/class/backlight/acpi_video0/brightness
10
```

- 桌面滑块从 10% 拖到 90%，`brightness` / `actual_brightness` 都跟着变。
- 屏幕亮度**完全不变**。
- `dmesg` 没有背光相关的报错（没有报错本身就是线索：硬件没坏，是接口在"假装"）。
- `i915`、`video`、`ideapad_laptop` 模块都已加载。
- 关键实验：启动参数加 `acpi=off` 后，亮度调节恢复正常。

## 3. 修复内容

只改了一行 `/etc/default/grub`：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=2 zswap.enabled=0 acpi_backlight=native"
```

然后：

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

> 这台机器没有 UEFI，**不需要** `grub-install --target=x86_64-efi`，也不需要 ESP。
> 只改内核参数时，`grub-mkconfig` 就足够了。

当前 `/proc/cmdline`：

```text
BOOT_IMAGE=/boot/vmlinuz-linux-zen root=UUID=<根分区UUID> rw loglevel=2 zswap.enabled=0 acpi_backlight=native
```

当前 GRUB 相关配置：

| 项目 | 值 |
|---|---|
| `GRUB_DEFAULT` | `"Windows"`（按菜单标题，不是数字） |
| `GRUB_TIMEOUT` | `2` |
| `GRUB_DISABLE_SUBMENU` | `y` |
| `GRUB_DISABLE_OS_PROBER` | `false` |
| 默认启动 | Windows（个人选择，与亮度修复无关） |

## 4. 修复后（当前状态）

```text
$ ls /sys/class/backlight/
intel_backlight

$ cat /sys/class/backlight/intel_backlight/type
raw

$ cat /sys/class/backlight/intel_backlight/max_brightness
4882

$ cat /sys/class/backlight/intel_backlight/brightness
4882

$ cat /sys/class/backlight/intel_backlight/actual_brightness
4882
```

背光设备挂在 i915 的 LVDS 连接器下：

```text
$ readlink -f /sys/class/backlight/intel_backlight/device
/sys/devices/pci0000:00/0000:00:02.0/drm/card1/card1-LVDS-1
```

`/sys/class/backlight/intel_backlight/` 下没有 `min_brightness` 接口（这颗内核的
i915 LVDS 背光不提供）。所以**内核不会阻止写入 0**，需要用户自己注意。

### 亮度数值对照

| 百分比 | 写入值 | 说明 |
|---:|---:|---|
| 0% | `0` | **背光完全关闭，屏幕全黑** |
| 5% | `244` | 本仓库建议的最低安全值 |
| 10% | `488` | 很暗但可见 |
| 25% | `1220` | |
| 50% | `2441` | |
| 75% | `3661` | |
| 100% | `4882` | 最大亮度 |

计算公式：

```text
value = floor(4882 × percent / 100)
```

## 5. 验证命令（重装后逐条执行）

```bash
# 内核参数
cat /proc/cmdline | grep -o 'acpi_backlight=[^ ]*'
# 期望：acpi_backlight=native

# 背光设备
ls /sys/class/backlight/
# 期望：intel_backlight

# 类型与范围
cat /sys/class/backlight/intel_backlight/type
# 期望：raw
cat /sys/class/backlight/intel_backlight/max_brightness
# 期望：4882

# 实际测试（不要用 0）
echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 2441 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 4882 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

KDE 侧：系统设置 → 电源管理 → 亮度，或键盘亮度快捷键，应能实时改变屏幕亮度。

## 6. 重装后的最小恢复步骤

```bash
# 1. 若尚未包含，则在现有参数后追加（不会重复添加）
grep -q 'acpi_backlight=native' /etc/default/grub || \
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_backlight=native"/' /etc/default/grub

# 2. 确认
grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub

# 3. 重新生成
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 4. 重启
sudo reboot
```

或者直接运行 [`scripts/apply-fix.sh`](scripts/apply-fix.sh)。

## 7. 已知坑

1. **亮度 0 = 黑屏**：不是 bug，是原生背光的正常行为。救援见
   [docs/recovery.md](docs/recovery.md)。
2. **不要用 `acpi=off` 代替**：它能让亮度恢复，但会关掉整台机器的 ACPI 功能。
3. **不要以为 `acpi_video0` 的 symlink 指向 GPU 就代表它在控制 GPU**：
   它指向 `0000:00:02.0` 只说明 ACPI 设备关联，`_BCM` 是否真的写硬件是另一回事。
4. **`brightnessctl` 不是必需的**：直接写 sysfs 就能验证；本机也没装。
5. **KDE 滑块能到 0**：桌面不会帮你兜底，别把滑块拖到底。
