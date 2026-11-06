#!/usr/bin/env bash
# Read-only verification after adding acpi_backlight=native.
# Usage: ./scripts/verify.sh
# Exit code: 0 if the key checks pass, 1 otherwise.

set -u

DEV="${BACKLIGHT_DEV:-/sys/class/backlight/intel_backlight}"
fail=0

echo "===== 1. kernel ====="
uname -r

echo
echo "===== 2. kernel command line ====="
cat /proc/cmdline
if grep -q 'acpi_backlight=native' /proc/cmdline; then
    echo "✅ acpi_backlight=native 已生效"
else
    echo "❌ 当前内核命令行没有 acpi_backlight=native"
    fail=1
fi

echo
echo "===== 3. backlight devices ====="
shopt -s nullglob
devs=(/sys/class/backlight/*)
if [ "${#devs[@]}" -eq 0 ]; then
    echo "❌ 没有任何背光设备"
    fail=1
else
    for d in "${devs[@]}"; do
        printf '%s: type=%s max=%s brightness=%s actual=%s\n' \
            "$d" \
            "$(cat "$d/type" 2>/dev/null || echo '?')" \
            "$(cat "$d/max_brightness" 2>/dev/null || echo '?')" \
            "$(cat "$d/brightness" 2>/dev/null || echo '?')" \
            "$(cat "$d/actual_brightness" 2>/dev/null || echo '?')"
    done
fi

echo
echo "===== 4. intel_backlight checks ====="
if [ -d "$DEV" ]; then
    type=$(cat "$DEV/type" 2>/dev/null || echo '?')
    if [ "$type" = "raw" ]; then
        echo "✅ $DEV type=raw"
    else
        echo "⚠️  $DEV type=$type（期望 raw）"
    fi

    if [ -d /sys/class/backlight/acpi_video0 ]; then
        echo "⚠️  acpi_video0 仍然存在；确认桌面实际使用的是哪个接口"
    else
        echo "✅ acpi_video0 不存在"
    fi

    max=$(cat "$DEV/max_brightness" 2>/dev/null || echo 0)
    if [ "$max" -gt 0 ] 2>/dev/null; then
        echo
        echo "亮度测试值（不要用 0）："
        printf '  5%%   = %s\n' "$((max * 5 / 100))"
        printf '  10%%  = %s\n' "$((max * 10 / 100))"
        printf '  50%%  = %s\n' "$((max * 50 / 100))"
        printf '  100%% = %s\n' "$max"
        echo
        echo "手动测试："
        echo "  echo $((max * 5 / 100)) | sudo tee $DEV/brightness"
        echo "  echo $((max * 50 / 100)) | sudo tee $DEV/brightness"
        echo "  echo $max | sudo tee $DEV/brightness"
    fi
else
    echo "❌ 找不到 $DEV"
    fail=1
fi

echo
echo "===== 5. result ====="
if [ "$fail" -eq 0 ]; then
    echo "✅ 关键检查通过。请再手动确认屏幕亮度确实随写入值变化。"
else
    echo "❌ 有检查未通过，请看上面的输出。"
fi

exit "$fail"
