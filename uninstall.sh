#!/bin/zsh
# 彻底卸载：停掉常驻、删登录项、删小程序、删设置和日志。Doubao.app 本来就没被改过。
LABEL=io.github.doubao.boot-animation
UID_=$(id -u)
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f 'DoubaoBootAnimation.app/Contents/MacOS/DoubaoBootAnimation' 2>/dev/null
rm -rf "$HOME/Applications/DoubaoBootAnimation.app"
rm -rf "$HOME/Library/Application Support/DoubaoBootAnimation"
rm -f  "$HOME/Library/Logs/DoubaoBootAnimation.log"
defaults delete "$LABEL" 2>/dev/null
echo "已卸载干净。"
