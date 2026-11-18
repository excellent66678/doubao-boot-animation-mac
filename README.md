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

## 仓库文件说明

| 路径 | 作用 |
|---|---|
| `Sources/main.swift` | 主程序：窗口识别与跟随、时间线拼接、播放浮层、点击穿透、菜单栏/设置窗口、配置读写 |
| `build.sh` | 编译 arm64 + x86_64 通用二进制，连同素材打成 `build/DoubaoBootAnimation.app` |
| `install.sh` | 编译（或用现成 .app）→ 装到 `~/Applications` → 挂登录自启 → 启动并弹设置窗口 |
| `uninstall.sh` | 停常驻、删登录项、删小程序/配置/日志，一键还原 |
| `web-install.sh` | 在线安装脚本（从 Release 下载打包好的 .app 再走 `install.sh`） |
| `assets/` | 放视频素材（`intro.mp4`、`loop.mp4`，已被 `.gitignore` 排除，不进 git） |
| `.gitignore` | 排除 `build/`、`.app`、`assets/*.mp4`、日志与临时文件 |
| `README.md` / `LICENSE` | 说明文档 / GPL-3.0 许可 |

## 怎么把素材接进去

### 1. 准备两段视频

把你拥有使用权的两段画面放到 `assets/`，文件名必须是：

- `assets/intro.mp4` —— **开屏动画**：从点开豆包到界面透出之前播放，**带音轨**
- `assets/loop.mp4` —— **循环背景**：开屏结束后半透明循环播放，静音即可（带了音轨程序也会自动静音）

规格要求：

| 项 | 要求 |
|---|---|
| 编码 | H.264 或 HEVC（`hvc1` 标签）；推荐 1280×720 或更高，横屏 |
| 音轨 | 只放 `intro.mp4`；`loop.mp4` 静音 |
| 衔接 | 开屏最后一帧能接上循环第一帧；`loop.mp4` 首尾尽量相接，否则循环接缝会跳一下 |
| 时长 | 开屏建议 5–12 秒；循环段 3–10 秒均可 |

> 一段长视频想拆成两段：用剪映/QuickTime/ffmpeg 裁出开头段当 `intro.mp4`、结尾稳定段当 `loop.mp4` 即可。

### 2. 按素材长度调时间点

打开 `Sources/main.swift`，在 `struct Config` 里按你的 `intro.mp4` 实际时长改这几项（首次运行后也会写到 `~/Library/Application Support/DoubaoBootAnimation/config.json`，改那个也行）：

| 配置项 | 作用 | 怎么定 |
|---|---|---|
| `fadeStartSeconds` | 开屏播到第几秒开始淡出、透出豆包界面 | 取开屏收尾前 0.5–1 秒；不要超过 intro 总时长 |
| `fadeDurationSeconds` | 透出界面的渐变时长（秒），默认 1.2 | 一般不用动 |
| `showSubtitles` | 是否显示字幕，默认 `false` | 素材没有配套字幕就保持关 |
| `subtitles` | 字幕文字 + 起止秒数；开启 `showSubtitles` 后才生效 | 按你视频里的台词时间填 `start` / `end` |
| `subtitleWidthRatio` | 字幕宽度占窗口比例，默认 0.6 | 字偏大/偏小时调 |

### 3. 打包安装

```zsh
# 方式 A：素材已放进 assets/，直接编译安装
./install.sh

# 方式 B：打包时临时指定另外两段视频（不改名也行）
./build.sh 我的开屏.mp4 我的循环.mp4
./install.sh
```

装完彻底退出豆包再重开；想立刻预览，点菜单栏 ✨ →「播放一次开屏动画」。

### 4. 换素材后的自查

- 开屏有声音、循环背景静音
- 开屏结尾自然淡出，不会把最后一帧黑住
- 循环背景点击能穿透到豆包，不挡操作
- 循环接缝若明显跳变：换一段首尾姿态更接近的 `loop.mp4`，或在两段之间加一帧淡入淡出

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
