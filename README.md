# 豆包 AI 开机动画（macOS 版）· Doubao Boot Animation

给 **豆包桌面端**（macOS）加一段开屏动画：打开豆包时先在窗口上播放一段开屏，进入循环画面后慢慢透出真正的界面，留下一层半透明的动态背景。

> 非官方同人项目，与字节跳动 / 豆包开发方无关。豆包是其各自权利人的商标。

- 🎬 **开屏动画**：开屏 `intro.mp4` 播完后，淡出透出界面，进入静音循环背景 `loop.mp4`
- 🌙 **循环背景**：开屏结束后半透明循环播放，点击直接穿透到豆包，不影响使用
- ⏭ **跳过**：开屏时右上角有「跳过」，点了淡出接到循环背景；进入循环后跳过键自动消失
- ✨ **菜单栏常驻**：开屏开关、循环背景开关、背景不透明度、开屏音量，拖滑块实时生效
- 🧼 **不改豆包本体**：独立小程序盖在豆包窗口上方播放；豆包更新、签名、权限都不受影响，卸载后什么都不留

## 它和参考项目的关系

架构与实现参考 [wynneceles/ai-boot-animations](https://github.com/wynneceles/ai-boot-animations)（GPL-3.0，Claude 版），把目标应用从 Claude 替换为豆包：

| 项 | Claude 参考版 | 本项目（豆包版） |
|---|---|---|
| 目标 bundle id | `com.anthropic.claudefordesktop` | `com.bot.pc.doubao`（本机实测） |
| 小程序名 | `ClaudeBootAnimation` | `DoubaoBootAnimation` |
| 配置目录 | `~/Library/Application Support/ClaudeBootAnimation` | `~/Library/Application Support/DoubaoBootAnimation` |
| 日志 | `~/Library/Logs/ClaudeBootAnimation.log` | `~/Library/Logs/DoubaoBootAnimation.log` |
| 包标识 | `io.github.celestewynne0506-pixel.claude-boot-animation` | `io.github.doubao.boot-animation` |

## 要求

- macOS 13 或更新（Apple 芯片 / Intel 均可）
- 从源码编译需要 Xcode 命令行工具：`xcode-select --install`
- 动画素材**不随仓库公开**：编译前自备 `assets/intro.mp4`、`assets/loop.mp4`（见「素材」）

## 安装（从源码编译）

1. 自备两段视频放入 `assets/`（见「素材」）
2. 打开终端，进入本目录：

```zsh
cd doubao-boot-animation-mac
./install.sh
```

脚本会现场编译 → 装到 `~/Applications/DoubaoBootAnimation.app` → 设为登录自启 → 弹出设置窗口。菜单栏右边（电池左边）出现 ✨。

> 不想编译：把编好的 `DoubaoBootAnimation.app` 放到本目录旁，再跑 `./install.sh`，脚本会直接装它。

## 菜单栏 ✨ 能干什么

| 播放开屏动画 | 保留循环背景 | 效果 |
|:---:|:---:|---|
| ✅ | ✅ | 默认：先放开屏，再透出界面，留下半透明动态背景 |
| ✅ | ❌ | 只放开屏，透出界面时整个淡出消失 |
| ❌ | ✅ | 不放开屏，豆包一打开就直接有动态背景 |
| ❌ | ❌ | 原装启动，什么都不放 |

- **背景不透明度**（0–80%）：循环背景多浓，默认 25%
- **开屏音量**：开屏音效音量；循环背景本身静音
- **现在，在豆包窗口上**：马上播一次开屏 / 开启循环背景 / 关掉
- 菜单里还能打开设置窗口、设置文件、卸载

## 设置文件

`~/Library/Application Support/DoubaoBootAnimation/config.json`，改完保存下次播放生效：

| 键 | 默认 | 含义 |
|---|---|---|
| `playIntro` | true | 打开豆包时播放开屏动画 |
| `loopBackground` | true | 保留半透明循环背景 |
| `residualAlpha` | 0.25 | 循环背景不透明度 |
| `introVolume` | 1.0 | 开屏音量 |
| `fadeStartSeconds` | 6.4 | 开屏里开始透出界面的时间（秒） |
| `fadeDurationSeconds` | 1.2 | 透出界面的渐变时长 |
| `showSubtitles` | false | 是否显示字幕 |
| `subtitles` | 两句 | 字幕文字和起止秒数 |
| `subtitleFadeSeconds` | 0.5 | 字幕渐显渐隐时长 |
| `subtitleWidthRatio` | 0.6 | 字幕大小（第一句约占窗口宽度比例） |

## 素材

仓库**不包含视频素材**（`assets/*.mp4` 已在 `.gitignore` 排除）。编译前自备两段你拥有使用权的画面：

- `assets/intro.mp4` —— 开屏动画（带音轨，H.264 / HEVC `hvc1`）
- `assets/loop.mp4` —— 循环背景（静音即可，带了也会被静音）

要点：

- 开屏最后一帧能接上循环第一帧，循环首尾相接
- 改了开屏长度，记得在配置里调 `fadeStartSeconds` 和字幕时间
- 也可以打包时换素材：`./build.sh 你的开屏.mp4 你的循环.mp4`
- 参考本地配置：`fadeStartSeconds = 6.4`、`showSubtitles = false`

> 素材版权归原权利人，请使用你拥有使用权的内容，勿商用或再发布未授权素材。

## 原理

- 小程序登录后后台常驻（`~/Library/LaunchAgents`），监听豆包启动
- 用 `CGWindowListCopyWindowInfo` 只读豆包主窗口的位置和大小（不读标题和内容，不需要辅助功能 / 屏幕录制授权），在其正上方盖一个无边框窗口播放动画，跟随窗口移动、缩放
- 开屏和循环在内存里拼成一条约 8 小时时间线一次播放，放到头自动跳回循环开头
- 进入循环后窗口变半透明并开启点击穿透，豆包照常使用

日志：`~/Library/Logs/DoubaoBootAnimation.log`

开发用参数：`--preview`（在当前豆包窗口预览）、`--loop-only`、`--test-skip 秒`、`--repeats N`、`--show-menu`、`--settings`。

## 卸载

菜单栏 ✨ →「卸载豆包开机动画…」，或运行：

```zsh
./uninstall.sh
```

会删除小程序、登录自启、设置和日志。豆包本身从未被改过，卸载后就是原装的样子。

## 授权

- 代码：参考项目 GPL-3.0 移植，本项目代码同样以 **GPL-3.0** 发布；发布改版须同样开源并保留署名。
- 动画素材：请使用你拥有使用权的素材，版权归原权利人。
