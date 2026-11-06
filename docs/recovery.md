# 救援手册：亮度调到 0，屏幕全黑了怎么办

## 先判断：是"黑屏"还是"死机"

`intel_backlight` 的 `brightness=0` 会真的把背光 PWM 关掉，但**系统本身还在运行**。
典型表现：

- 电源灯亮，风扇转，硬盘/SSD 有读写；
- 键盘大小写灯能切换；
- 音乐/视频可能还在播放；
- 从另一台机器 `ping` 得通，SSH 能登录；
- 只是屏幕看起来像关机。

如果连 SSH 都不通、ping 也不通，那才可能是死机/内核崩溃，按死机处理。

## 方法一：连按亮度增加快捷键

很多机器即使屏幕全黑，亮度快捷键仍由 EC/固件处理，能直接把亮度加回来。
试 `Fn + 亮度+`（不同机型键位不同），连按 5–10 次。

如果 KDE 把快捷键完全接管了，而屏幕又黑，可能没反应——转方法二。

## 方法二：SSH 进去改 sysfs（最可靠）

本机 `sshd` 已启用。从手机（Termux）、另一台电脑或平板：

```bash
ssh <user>@<host>
```

登录后：

```bash
# 先看当前值和最大值
cat /sys/class/backlight/intel_backlight/brightness
cat /sys/class/backlight/intel_backlight/max_brightness

# 抬到 5%（本机 244），极暗但可见
echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness

# 如果觉得太暗，再抬到 10%（488）或 50%（2441）
echo 488 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

如果 sudo 需要密码，直接交互输入即可。**不要**把密码写进命令历史或脚本里。

> 只要 SSH 能进，这就是 100% 有效的救援方式。建议平时就确认 `sshd` 是
> `enabled + active`，并把这条命令记在手机里。

## 方法三：接外接显示器

如果有 HDMI/VGA 显示器：

1. 接上外接屏；
2. 系统通常会自动扩展/镜像桌面；
3. 在外接屏上打开终端，执行上面的 `echo 244 | sudo tee ...`；
4. 内置屏恢复后，再拔掉外接屏。

## 方法四：重启

i915 初始化时通常会重新设置一个默认亮度（多数机器是最大或固件保存值），
所以**大多数情况下重启就能恢复**。

但不要把它当唯一手段：

- 有的机器会把亮度保存在 EC/NVRAM 里，重启后仍是 0；
- 如果重启后还是黑，接外接屏或进 live 环境处理。

强制重启：长按电源键 5–10 秒。

## 预防：把最低亮度留在 5%

最省事的办法：**别把滑块/快捷键一路减到 0**。本机 5% = 244，已经非常暗，
但还能看见。日常使用留一格即可。

KDE 的亮度滑块没有"最小值限制"，也不会有二次确认，所以只能靠自己注意。

## 可选：brightness-guard 守护脚本

如果你经常误触 0，或者要给家人用，可以装一个小守护：

- 每 2 秒读一次 `brightness`；
- 发现是 0，就写回最大亮度的 5%（本机 244）；
- 通过 `logger` 记录一条系统日志；
- 由 systemd 常驻，挂了自动拉起。

### 安装

> 以下命令在仓库根目录执行。

```bash
sudo install -m 755 scripts/brightness-guard.sh /usr/local/bin/brightness-guard.sh
sudo install -m 644 scripts/brightness-guard.service /etc/systemd/system/brightness-guard.service
sudo systemctl daemon-reload
sudo systemctl enable --now brightness-guard.service
```

### 检查

```bash
systemctl status brightness-guard.service
journalctl -t brightness-guard -n 20
```

### 测试

先把亮度调到 10% 左右（避免真黑），再临时写 0：

```bash
echo 488 | sudo tee /sys/class/backlight/intel_backlight/brightness
echo 0   | sudo tee /sys/class/backlight/intel_backlight/brightness
sleep 3
cat /sys/class/backlight/intel_backlight/brightness
# 期望：244（或你配置的 MIN_PERCENT 对应值）
```

> 测试时屏幕会黑最多 2 秒，这是正常的轮询间隔。怕黑的话先用外接屏或 SSH。

### 调整阈值

编辑 service 的 `Environment=`，或者直接改脚本里的默认值：

```bash
MIN_PERCENT=10   # 10%
INTERVAL=1       # 轮询间隔（秒）
```

改完：

```bash
sudo systemctl daemon-reload
sudo systemctl restart brightness-guard.service
```

### 卸载

```bash
sudo systemctl disable --now brightness-guard.service
sudo rm /etc/systemd/system/brightness-guard.service
sudo rm /usr/local/bin/brightness-guard.sh
sudo systemctl daemon-reload
```

> **本机没有安装这个守护**。原会话里评估过，但结论是"知道 0 会黑、留一格"
> 就足够了。仓库保留脚本，给需要的人选用。

## 一张图记住

```text
屏幕黑
├─ 电源灯亮 / SSH 通 / 音乐还在 → 背光被关，不是死机
│  ├─ Fn+亮度+ 连按
│  ├─ SSH: echo 244 | sudo tee /sys/class/backlight/intel_backlight/brightness
│  ├─ 外接显示器操作
│  └─ 重启
└─ 完全无响应 → 按死机处理（长按电源键）
```
