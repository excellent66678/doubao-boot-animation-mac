#!/bin/zsh
# 编译 → 装到 ~/Applications → 设为登录自动启动 → 弹出设置窗口
# 不会修改 Doubao.app 的任何文件
# 在源码目录里运行会现场编译；在 Release 压缩包里运行（旁边有编好的 .app）就直接装
set -e
cd "${0:A:h}"
if [[ -f Sources/main.swift ]]; then
  ./build.sh
  SRC_APP=build/DoubaoBootAnimation.app
else
  SRC_APP=DoubaoBootAnimation.app
  [[ -d "$SRC_APP" ]] || { echo "找不到 $SRC_APP"; exit 1; }
fi
LABEL=io.github.doubao.boot-animation
DEST="$HOME/Applications/DoubaoBootAnimation.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_=$(id -u)
# 先停掉旧版本
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f 'DoubaoBootAnimation.app/Contents/MacOS/DoubaoBootAnimation' 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"; ditto "$SRC_APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/DoubaoBootAnimation</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
launchctl bootstrap "gui/$UID_" "$PLIST"
sleep 1.5
open "$DEST"   # 已在运行时再打开一次 = 弹出设置窗口
echo
echo "✨ 装好了！菜单栏右边（电池左边）出现 ✨ 图标，也弹出了设置窗口。"
echo "   下次打开豆包就会播放开机动画。想马上看：菜单栏 ✨ →「播放一次开屏动画」。"
