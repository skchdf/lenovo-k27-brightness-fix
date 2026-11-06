#!/usr/bin/env bash
# Add acpi_backlight=native to GRUB_CMDLINE_LINUX_DEFAULT and regenerate grub.cfg.
#
# Usage:
#   sudo ./scripts/apply-fix.sh
#
# This script:
#   1. backs up /etc/default/grub and /boot/grub/grub.cfg with a timestamp;
#   2. appends acpi_backlight=native without dropping existing parameters;
#   3. records menu entries before/after and verifies they did not change;
#   4. regenerates grub.cfg with LC_ALL=C (stable menu titles);
#   5. verifies the parameter is present.
#
# It does NOT reboot. Review the output, then reboot manually.

set -euo pipefail

GRUB_DEFAULT_FILE="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
GRUB_CFG="${GRUB_CFG:-/boot/grub/grub.cfg}"
PARAM="acpi_backlight=native"

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 root 运行：sudo $0" >&2
    exit 1
fi

if [ ! -f "$GRUB_DEFAULT_FILE" ]; then
    echo "找不到 $GRUB_DEFAULT_FILE" >&2
    exit 1
fi

if [ ! -f "$GRUB_CFG" ]; then
    # Common fallback on Fedora/openSUSE-style layouts
    if [ -f /boot/grub2/grub.cfg ]; then
        GRUB_CFG=/boot/grub2/grub.cfg
    else
        echo "找不到 $GRUB_CFG" >&2
        exit 1
    fi
fi

if ! command -v grub-mkconfig >/dev/null 2>&1; then
    echo "找不到 grub-mkconfig，请先安装 grub" >&2
    exit 1
fi

ts="$(date +%Y%m%d%H%M%S).$$"
backup_grub="$GRUB_DEFAULT_FILE.bak.$ts"
backup_cfg="$GRUB_CFG.bak.$ts"

cp -a "$GRUB_DEFAULT_FILE" "$backup_grub"
cp -a "$GRUB_CFG" "$backup_cfg"

trap 'echo "出错了。备份在：$backup_grub 和 $backup_cfg" >&2' ERR

echo "已备份：$backup_grub"
echo "已备份：$backup_cfg"
echo

# Current menu entries and default, for a before/after comparison.
before_menu=$(grep -a -E '^(menuentry|submenu) ' "$GRUB_CFG" || true)
before_default=$(grep -a -m1 'set default=' "$GRUB_CFG" || true)

line=$(grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT_FILE" | tail -1 || true)
if [ -z "$line" ]; then
    echo "未找到 GRUB_CMDLINE_LINUX_DEFAULT，请手动编辑 $GRUB_DEFAULT_FILE" >&2
    exit 1
fi

value=${line#*=}
# Strip matching surrounding quotes (double or single).
value=${value%\"}; value=${value#\"}
value=${value%\'}; value=${value#\'}

# Collapse whitespace and trim.
value=$(printf '%s\n' "$value" | tr -s '[:space:]' ' ' | sed -E 's/^ +//; s/ +$//')

if [[ " $value " == *" $PARAM "* ]]; then
    echo "已经包含 $PARAM，无需修改参数行。"
else
    # Drop any existing acpi_backlight=... so we do not end up with two values.
    value=$(printf '%s\n' "$value" | sed -E 's/(^|[[:space:]])acpi_backlight=[^[:space:]]+//g')
    value=$(printf '%s\n' "$value" | tr -s '[:space:]' ' ' | sed -E 's/^ +//; s/ +$//')
    value="${value:+$value }$PARAM"
    newline="GRUB_CMDLINE_LINUX_DEFAULT=\"$value\""

    echo "将修改 $GRUB_DEFAULT_FILE："
    echo "  - $line"
    echo "  + $newline"
    echo

    tmp=$(mktemp)
    awk -v newline="$newline" '
        BEGIN { done = 0 }
        /^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ && !done {
            print newline
            done = 1
            next
        }
        { print }
    ' "$GRUB_DEFAULT_FILE" > "$tmp"

    # cat > keeps the original inode and permissions.
    cat "$tmp" > "$GRUB_DEFAULT_FILE"
    rm -f "$tmp"
fi

echo "== 重新生成 $GRUB_CFG =="
LC_ALL=C grub-mkconfig -o "$GRUB_CFG"
echo

after_menu=$(grep -a -E '^(menuentry|submenu) ' "$GRUB_CFG" || true)
after_default=$(grep -a -m1 'set default=' "$GRUB_CFG" || true)

echo "== 菜单项（修改后） =="
printf '%s\n' "$after_menu"
echo

if [ "$before_menu" != "$after_menu" ]; then
    echo "⚠️  菜单项与修改前不完全一致，请人工确认："
    echo "--- before ---"
    printf '%s\n' "$before_menu"
    echo "--- after ---"
    printf '%s\n' "$after_menu"
else
    echo "✅ 菜单项与修改前一致"
fi

if [ "$before_default" != "$after_default" ]; then
    echo "⚠️  默认启动项可能变化："
    echo "  before: $before_default"
    echo "  after:  $after_default"
else
    echo "✅ 默认启动项未变：$after_default"
fi

echo
if grep -aq -- "$PARAM" "$GRUB_CFG"; then
    echo "✅ $PARAM 已写入 $GRUB_CFG"
else
    echo "❌ 未在 $GRUB_CFG 中找到 $PARAM" >&2
    exit 1
fi

echo
echo "完成。重启后验证："
echo "  cat /proc/cmdline"
echo "  ls /sys/class/backlight/"
echo "  cat /sys/class/backlight/intel_backlight/type    # 期望 raw"
echo "  ./scripts/verify.sh"
echo
echo "如果出现问题，回滚："
echo "  cp $backup_grub $GRUB_DEFAULT_FILE"
echo "  cp $backup_cfg $GRUB_CFG"
echo "  reboot"
