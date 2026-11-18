# 素材（需自备，不随仓库公开）

本目录的 `*.mp4` 已在 `.gitignore` 中排除，不会推到 GitHub。打包前请自行放入两段你拥有使用权的视频：

  intro.mp4   开屏动画（带音轨，H.264 / HEVC hvc1）
  loop.mp4    循环背景（静音即可，首尾相接；带音轨程序也会自动静音）

参考配置（Sources/main.swift / config.json）：
  fadeStartSeconds = 6.4   开屏第 6.4s 开始淡出透出界面（按你的 intro 时长调整）
  showSubtitles    = false 无配套字幕时保持关闭

要求：
- 开屏最后一帧能接上循环第一帧，循环首尾相接
- 改了开屏长度后，在 config.json 调 fadeStartSeconds 与字幕起止时间
- 也可以打包时传入：../build.sh 你的开屏.mp4 你的循环.mp4

素材版权归原权利人，请使用你拥有使用权的内容，勿商用或再发布未授权素材。
