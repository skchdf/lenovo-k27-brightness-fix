# 重装系统后：一条提示词让 AI 直接恢复亮度修复

> 适用：**同一台 Lenovo ZHAOYANG K27**，重装 Arch Linux 后亮度滑块再次失效。
> 换了机器就不要直接套，先按 [PROMPTS.md](PROMPTS.md) 的通用诊断流程走。

## 直接复制这段给 agent

```text
我刚重装完系统（Arch Linux + KDE Plasma，Legacy BIOS），机器是联想昭阳 K27。
亮度滑块有，数值会变，但屏幕亮度不变。

请从 https://github.com/skchdf/lenovo-k27-brightness-fix
读取 README.md 和 MACHINE.md，然后按下面的步骤恢复：

1. 先核对机型：
   cat /sys/class/dmi/id/product_name
   输出应包含 ZHAOYANG 和 K27。如果不是，立刻停止，不要改任何配置。

2. 只读取证，不要先改配置：
   ls /sys/class/backlight/
   cat /proc/cmdline
   lspci -nnk | grep -A3 -i vga
   确认当前是 acpi_video0（type=firmware），而不是 intel_backlight。
   如果已经是 intel_backlight，说明不用修，直接告诉我。

3. 备份：
   sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d%H%M%S)
   sudo cp /boot/grub/grub.cfg /boot/grub/grub.cfg.bak.$(date +%Y%m%d%H%M%S)

4. 在现有 GRUB_CMDLINE_LINUX_DEFAULT 末尾追加 acpi_backlight=native。
   不要覆盖已有参数；不要改 GRUB_DEFAULT、GRUB_TIMEOUT、菜单顺序。

5. 重新生成并确认：
   sudo grub-mkconfig -o /boot/grub/grub.cfg
   grep -a -o acpi_backlight=native /boot/grub/grub.cfg | head -1

6. 不要自动重启。把修改前后的参数行、菜单核对结果给我，我确认后自己重启。

7. 重启后运行仓库里的 scripts/verify.sh，并告诉我：
   - 亮度 0 会黑屏；
   - 救援命令是
     echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness

如果你能访问仓库，优先运行 sudo ./scripts/apply-fix.sh。
如果访问不了 GitHub，就按下面的"无网络兜底"直接做。
需要 sudo 密码时停下来让我自己输入，不要让我把密码写进对话。
```

## 无网络兜底（不需要 git、不需要仓库）

重装后如果 GitHub 打不开、也没装 `git`，在终端里按顺序执行：

```bash
# 1. 核对机型（应包含 ZHAOYANG 和 K27）
cat /sys/class/dmi/id/product_name

# 2. 备份
sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d%H%M%S)
sudo cp /boot/grub/grub.cfg /boot/grub/grub.cfg.bak.$(date +%Y%m%d%H%M%S)

# 3. 追加参数（已有则跳过，保留原有参数）
grep -q 'acpi_backlight=native' /etc/default/grub || \
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_backlight=native"/' /etc/default/grub

# 4. 重新生成
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 5. 确认
grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub
grep -a -o 'acpi_backlight=native' /boot/grub/grub.cfg | head -1

# 6. 重启
sudo reboot
```

重启后验证：

```bash
ls /sys/class/backlight/                         # 期望：intel_backlight
cat /sys/class/backlight/intel_backlight/type    # 期望：raw
cat /sys/class/backlight/intel_backlight/max_brightness  # 本机：4882

# 不要用 0 测试；5% = 244
echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 2441 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 4882 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

## 重启后如果屏幕是黑的

说明亮度被写成了 0（不是死机）。用 SSH 从另一台机器进来：

```bash
ssh <user>@<host>
echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

详见 [docs/recovery.md](docs/recovery.md)。

## 注意

- 这条提示词只针对 **Lenovo ZHAOYANG K27**；换机型先诊断。
- 不要用 `acpi=off` 当长期方案，它会让电池、温度、休眠、快捷键等一起失效。
- 本机 `intel_backlight` 没有 `min_brightness`，内核不会阻止写 0。
- 重装后如果内核/桌面版本变化，先跑 `scripts/verify.sh` 确认 `type=raw`。
