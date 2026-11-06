#!/usr/bin/env bash
# Read-only diagnosis for Linux backlight problems.
# Usage: ./diagnose.sh
# Nothing is modified. Some sections may ask for sudo to read dmesg.

set -u

echo "===== 1. system ====="
uname -a
grep -E '^(PRETTY_NAME|ID)=' /etc/os-release 2>/dev/null || true
printf 'desktop: %s\n' "${XDG_CURRENT_DESKTOP:-unknown}"
printf 'session: %s\n' "${XDG_SESSION_TYPE:-unknown}"

echo
echo "===== 2. kernel command line ====="
cat /proc/cmdline

echo
echo "===== 3. backlight devices ====="
shopt -s nullglob
devs=(/sys/class/backlight/*)
if [ "${#devs[@]}" -eq 0 ]; then
    echo "(none) — no backlight device registered"
else
    for d in "${devs[@]}"; do
        echo "--- $d"
        for f in type max_brightness brightness actual_brightness bl_power scale; do
            if [ -r "$d/$f" ]; then
                printf '  %-18s = %s\n' "$f" "$(cat "$d/$f" 2>/dev/null)"
            fi
        done
        if [ -e "$d/device" ]; then
            printf '  %-18s -> %s\n' "device" "$(readlink -f "$d/device")"
        fi
    done
fi

echo
echo "===== 4. GPU ====="
lspci -nnk 2>/dev/null | grep -A3 -iE 'vga|3d|display' || echo "(lspci unavailable)"

echo
echo "===== 5. relevant modules ====="
lsmod 2>/dev/null | grep -E '^(i915|amdgpu|radeon|nouveau|nvidia|acpi_video|video|ideapad_laptop|thinkpad_acpi)\b' || echo "(none matched)"

echo
echo "===== 6. video module parameters ====="
if [ -d /sys/module/video/parameters ]; then
    for f in /sys/module/video/parameters/*; do
        [ -e "$f" ] || continue
        printf '  %-32s = %s\n' "$(basename "$f")" "$(cat "$f" 2>/dev/null)"
    done
else
    echo "(video module not loaded)"
fi

echo
echo "===== 7. dmesg (backlight related) ====="
if [ "$(id -u)" -eq 0 ]; then
    dmesg 2>/dev/null
elif sudo -n dmesg >/dev/null 2>&1; then
    sudo -n dmesg 2>/dev/null
else
    echo "(需要 sudo 读取 dmesg；跳过)"
    echo "可手动执行: sudo dmesg | grep -iE 'backlight|brightness|acpi_video|i915'"
fi | grep -iE 'backlight|brightness|acpi_video|i915|amdgpu|nouveau' | tail -40 || true

echo
echo "===== 8. quick hints ====="
if [ "${#devs[@]}" -eq 0 ]; then
    echo "- 没有任何背光设备：先查 GPU 驱动/固件，不要直接加 acpi_backlight。"
else
    for d in "${devs[@]}"; do
        t=$(cat "$d/type" 2>/dev/null || echo "?")
        case "$t" in
            firmware|platform)
                echo "- $d 是 $t：可能是固件/ACPI 背光。若写值屏幕不变，可考虑 acpi_backlight=native。"
                ;;
            raw)
                echo "- $d 是 raw：原生驱动已接管。若屏幕仍不变，查 PWM/面板/DPCD，而不是 ACPI。"
                ;;
            *)
                echo "- $d 类型为 $t，请结合 dmesg 判断。"
                ;;
        esac
    done
fi
