// 豆包 AI 开机动画 —— 外置浮层小程序（macOS）
// 检测豆包桌面端启动 → 盖在它的主窗口上播放开屏动画 → 进入循环帧后半透明、点击穿透，作为循环背景一直播放，点「跳过」关掉。
// 不修改 Doubao.app 的任何文件。
//
// 架构与实现参考 wynneceles/ai-boot-animations（GPL-3.0），目标应用由 Claude 替换为豆包。
// 本程序以 GNU GPL v3 发布。

import AppKit
import AVFoundation
import CoreImage

// 豆包桌面端 bundle id（本机实测：/Applications/Doubao.app → com.bot.pc.doubao）
let doubaoBundleID = "com.bot.pc.doubao"
let showSettingsNote = Notification.Name("io.github.doubao.boot-animation.show-settings")

// MARK: - 配置

struct Config: Codable {
    /// 豆包启动时播放开屏动画
    var playIntro = true
    /// 开屏后（或不放开屏时直接）保留半透明的循环背景
    var loopBackground = true
    /// 成片里进入循环帧的时间点（秒）。当前 intro.mp4 时长 7.0s
    var fadeStartSeconds = 6.4
    /// 从不透明淡到半透明用多久
    var fadeDurationSeconds = 1.2
    /// 循环背景的不透明度（0 = 看不见，1 = 完全挡住）
    var residualAlpha = 0.25
    /// 开屏动画音量 0~1
    var introVolume = 1.0
    /// 是否显示字幕
    var showSubtitles = false
    /// 字幕入场、出场各渐变多久
    var subtitleFadeSeconds = 0.5
    /// 字幕大小：第一句大约占窗口宽度的比例（0.6 = 60%）
    var subtitleWidthRatio = 0.6
    var subtitles: [Subtitle] = [
        Subtitle(text: "你好，我是豆包。", start: 2.0, end: 4.5),
        Subtitle(text: "有什么我可以帮你？", start: 5.0, end: 6.6),
    ]

    init() {}
    // 老版本的设置文件缺字段时，用默认值补上，不会整个作废
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Config()
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        playIntro = get(.playIntro, def.playIntro)
        loopBackground = get(.loopBackground, def.loopBackground)
        fadeStartSeconds = get(.fadeStartSeconds, def.fadeStartSeconds)
        fadeDurationSeconds = get(.fadeDurationSeconds, def.fadeDurationSeconds)
        residualAlpha = get(.residualAlpha, def.residualAlpha)
        introVolume = get(.introVolume, def.introVolume)
        showSubtitles = get(.showSubtitles, def.showSubtitles)
        subtitleFadeSeconds = get(.subtitleFadeSeconds, def.subtitleFadeSeconds)
        subtitleWidthRatio = get(.subtitleWidthRatio, def.subtitleWidthRatio)
        subtitles = get(.subtitles, def.subtitles)
    }

    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DoubaoBootAnimation")
    }
    static var file: URL { dir.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
              let c = try? JSONDecoder().decode(Config.self, from: data) else {
            let c = Config(); c.save(); return c
        }
        c.save()   // 补齐新字段
        return c
    }
    func save() {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Config.file)
    }
}

struct Subtitle: Codable { var text: String; var start: Double; var end: Double }

// MARK: - 日志

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/DoubaoBootAnimation.log")

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: logURL)
    }
}

// MARK: - 找豆包的主窗口（只读位置、PID、层级，不读标题，不需要任何授权）

struct TargetWindow { let number: Int; let cocoaFrame: NSRect }

func findDoubaoWindow(pid: pid_t) -> TargetWindow? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return nil }
    var best: (Int, CGRect)?
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let num = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        if let a = w[kCGWindowAlpha as String] as? Double, a <= 0 { continue }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if r.width < 300 || r.height < 200 { continue }
        if best == nil || r.width * r.height > best!.1.width * best!.1.height { best = (num, r) }
    }
    guard let (num, r) = best, let primary = NSScreen.screens.first else { return nil }
    // CG 坐标原点在主屏左上角，Cocoa 在主屏左下角
    let y = primary.frame.height - r.origin.y - r.height
    return TargetWindow(number: num, cocoaFrame: NSRect(x: r.origin.x, y: y, width: r.width, height: r.height))
}

// MARK: - 把成片 + 循环拼成一整条（约 8 小时），播放器全程只放一个文件，接缝不会卡；放到头再跳回循环开头

struct Timeline { let asset: AVAsset; let loopStart: CMTime }

func buildTimeline(intro: URL?, loop: URL, repeats: Int = 5000) -> Timeline {   // 5000 段 ≈ 8 小时
    let comp = AVMutableComposition()
    let vT = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let aT = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    var cursor = CMTime.zero

    func append(_ url: URL) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let sv = asset.tracks(withMediaType: .video).first else { return }
        let vDur = sv.timeRange.duration
        try? vT.insertTimeRange(CMTimeRange(start: sv.timeRange.start, duration: vDur), of: sv, at: cursor)
        if vT.preferredTransform != sv.preferredTransform { vT.preferredTransform = sv.preferredTransform }
        if let sa = asset.tracks(withMediaType: .audio).first {
            let aDur = CMTimeMinimum(sa.timeRange.duration, vDur)
            try? aT.insertTimeRange(CMTimeRange(start: sa.timeRange.start, duration: aDur), of: sa, at: cursor)
        }
        cursor = cursor + vDur
    }

    if let intro { append(intro) }
    let loopStart = cursor
    for _ in 0..<repeats { append(loop) }
    return Timeline(asset: comp.copy() as! AVComposition, loopStart: loopStart)
}

/// 8 小时的时间线现场拼要 3~4 秒，所以程序启动时就在后台拼好存着，点播放时直接用。
/// 后台还没拼好时，先现场拼一条短的（300 段 ≈ 29 分钟，约 0.1 秒）顶上，放到头照样跳回循环开头继续。
final class TimelineCache {
    let introURL: URL, loopURL: URL, repeats: Int
    private var ready: [Bool: Timeline] = [:]
    init(introURL: URL, loopURL: URL, repeats: Int) {
        self.introURL = introURL; self.loopURL = loopURL; self.repeats = repeats
        for withIntro in [true, false] {
            DispatchQueue.global(qos: .utility).async {
                let t0 = Date()
                let t = buildTimeline(intro: withIntro ? introURL : nil, loop: loopURL, repeats: repeats)
                DispatchQueue.main.async {
                    self.ready[withIntro] = t
                    log("后台时间线准备好（\(withIntro ? "开屏+循环" : "只循环")，\(repeats) 段，\(Int(Date().timeIntervalSince(t0) * 1000))ms）")
                }
            }
        }
    }
    var isReady: Bool { ready.count == 2 }
    func get(withIntro: Bool) -> Timeline {
        if let t = ready[withIntro] { return t }
        log("后台时间线还没好，先用短的顶上")
        return buildTimeline(intro: withIntro ? introURL : nil, loop: loopURL, repeats: min(repeats, 300))
    }
}

// MARK: - 视图

final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer!.backgroundColor = NSColor.black.cgColor
        layer!.cornerRadius = 10          // 跟豆包窗口圆角对齐
        layer!.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer!.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class SkipButtonView: NSView {
    var onClick: (() -> Void)?
    private let label = NSTextField(labelWithString: "跳过 ›")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.cornerRadius = frame.height / 2
        layer!.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        layer!.borderColor = NSColor(white: 1, alpha: 0.35).cgColor
        layer!.borderWidth = 1
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (frame.height - 17) / 2, width: frame.width, height: 17)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// 字幕：白字 + 细黑描边 + 柔和阴影，背景再亮也看得清
final class SubtitleView: NSView {
    let outline = NSTextField(labelWithString: "")
    let fill = NSTextField(labelWithString: "")
    let label = NSView()
    var widthRatio = 0.6
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.wantsLayer = true
        label.alphaValue = 0
        for f in [outline, fill] { f.alignment = .center; label.addSubview(f) }
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        let size = max(18, min(bounds.width * widthRatio / 15.5, bounds.height * 0.09))
        let font = NSFont(name: "PingFangSC-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.75)
        shadow.shadowBlurRadius = size * 0.25
        shadow.shadowOffset = .zero
        outline.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font, .paragraphStyle: para, .foregroundColor: NSColor.clear,
            .strokeColor: NSColor(white: 0, alpha: 0.9), .strokeWidth: 5.0,
            .shadow: shadow,
        ])
        fill.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font, .paragraphStyle: para, .foregroundColor: NSColor.white,
        ])
        layoutLabel()
    }
    func layoutLabel() {
        fill.sizeToFit()
        let w = min(fill.frame.width + 24, bounds.width - 40), h = fill.frame.height + 12
        label.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height * 0.15 - h / 2, width: w, height: h)
        outline.frame = label.bounds; fill.frame = label.bounds
    }
    override func layout() { super.layout(); layoutLabel() }
}

func makeBorderlessWindow(_ frame: NSRect) -> NSWindow {
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.isReleasedWhenClosed = false
    w.level = .normal
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    return w
}

// MARK: - 一次播放

final class Show {
    enum Phase { case intro, revealed, ending, done }

    let pid: pid_t
    var config: Config
    let withIntro: Bool
    let onDone: () -> Void
    var phase = Phase.intro

    let overlay: NSWindow
    let skipWin: NSWindow
    let subWin: NSWindow
    let subView: SubtitleView
    let playerView: PlayerView
    let player = AVPlayer()
    let timeline: Timeline
    let item: AVPlayerItem
    let videoOut = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    var subObserver: Any?
    var currentSub = -1
    var tick: Timer?
    var rampTimer: Timer?
    var timeObserver: Any?
    var volObserver: Any?
    var readyObs: NSKeyValueObservation?
    var activateObs: NSObjectProtocol?
    var inLoopAudio = false
    var endObserver: NSObjectProtocol?
    var lastTarget = -1
    var lastFrame = NSRect.zero

    init(pid: pid_t, target: TargetWindow, config: Config, withIntro: Bool,
         timeline: Timeline, onDone: @escaping () -> Void) {
        self.pid = pid; self.config = config; self.withIntro = withIntro; self.onDone = onDone
        self.timeline = timeline
        item = AVPlayerItem(asset: timeline.asset)
        item.add(videoOut)

        overlay = makeBorderlessWindow(target.cocoaFrame)
        playerView = PlayerView(frame: NSRect(origin: .zero, size: target.cocoaFrame.size))
        playerView.autoresizingMask = [.width, .height]
        overlay.contentView = playerView

        skipWin = makeBorderlessWindow(NSRect(x: 0, y: 0, width: 72, height: 28))
        let btn = SkipButtonView(frame: NSRect(x: 0, y: 0, width: 72, height: 28))
        skipWin.contentView = btn

        subWin = makeBorderlessWindow(target.cocoaFrame)
        subWin.ignoresMouseEvents = true
        subView = SubtitleView(frame: NSRect(origin: .zero, size: target.cocoaFrame.size))
        subView.autoresizingMask = [.width, .height]
        subWin.contentView = subView
        btn.onClick = { [weak self] in self?.skipIntro() }

        playerView.playerLayer.player = player
        let shownAt = Date()
        readyObs = playerView.playerLayer.observe(\.isReadyForDisplay) { l, _ in
            if l.isReadyForDisplay { DispatchQueue.main.async { log("第一帧出画面，用时 \(Int(Date().timeIntervalSince(shownAt) * 1000))ms") } }
        }
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .none

        // 一整条（约 8 小时）放完后跳回循环段开头继续，背景不会掉
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, self.phase != .done else { return }
            log("时间线放到头，跳回循环开头继续")
            self.player.seek(to: self.timeline.loopStart, toleranceBefore: .zero, toleranceAfter: .zero)
            self.player.play()
        }

        if withIntro {
            overlay.ignoresMouseEvents = false
            player.volume = Float(config.introVolume)
            let fadeAt = CMTimeMinimum(CMTime(seconds: config.fadeStartSeconds, preferredTimescale: 600), timeline.loopStart)
            timeObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: fadeAt)], queue: .main) { [weak self] in
                self?.reveal()
            }
            if config.showSubtitles && !config.subtitles.isEmpty {
                subObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
                    self?.updateSubtitle(at: t.seconds)
                }
            }
            volObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: timeline.loopStart)], queue: .main) { [weak self] in
                guard let self, self.phase == .revealed else { return }
                self.inLoopAudio = true
                self.rampVolume(to: 0, over: 1.5)
            }
        } else {
            phase = .revealed
            inLoopAudio = true
            overlay.ignoresMouseEvents = true
            playerView.layer?.backgroundColor = NSColor.clear.cgColor
            overlay.alphaValue = 0
            player.volume = 0
        }

        place(target)
        if withIntro {
            overlay.addChildWindow(subWin, ordered: .above)
            overlay.addChildWindow(skipWin, ordered: .above)
        }
        overlay.orderFront(nil)
        overlay.order(.above, relativeTo: target.number)
        player.play()
        log(withIntro ? "开始播放开屏动画，豆包窗口 \(target.number) \(target.cocoaFrame)"
                      : "直接开启循环背景，豆包窗口 \(target.number)")
        if !withIntro {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = config.fadeDurationSeconds
                overlay.animator().alphaValue = config.residualAlpha
            }
        }

        tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.follow() }
        RunLoop.main.add(tick!, forMode: .common)
        activateObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.follow() }
    }

    func place(_ t: TargetWindow) {
        if t.cocoaFrame != lastFrame {
            overlay.setFrame(t.cocoaFrame, display: true)
            subWin.setFrame(t.cocoaFrame, display: true)
            let f = t.cocoaFrame
            skipWin.setFrameOrigin(NSPoint(x: f.maxX - 72 - 18, y: f.maxY - 28 - 44))
            lastFrame = f
        }
    }

    /// 跟着豆包窗口移动/缩放，并保持正好压在它上面
    func follow() {
        guard phase != .done else { return }
        guard let t = findDoubaoWindow(pid: pid) else {
            if overlay.isVisible { overlay.orderOut(nil) }
            if NSRunningApplication(processIdentifier: pid) == nil { finish(fast: true) }
            return
        }
        place(t)
        if !overlay.isVisible { overlay.orderFront(nil) }
        let doubaoFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let level: NSWindow.Level = doubaoFront ? .floating : .normal
        if overlay.level != level {
            for w in [overlay, subWin, skipWin] { w.level = level }
        }
        if !doubaoFront { overlay.order(.above, relativeTo: t.number) }
        if t.number != lastTarget { lastTarget = t.number; log("跟随窗口 \(t.number)") }
    }

    /// 点「跳过」：跳过开屏。开着循环背景就直接跳到循环段并透出界面，否则整个关掉
    func skipIntro() {
        guard phase == .intro else { return }
        log("点了跳过开屏")
        guard config.loopBackground else { finish(fast: true); return }
        hideSubtitles()
        let snap = CALayer()
        if let img = currentFrameImage() {
            snap.contents = img
            snap.contentsGravity = .resizeAspectFill
            snap.frame = playerView.bounds
            snap.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerView.layer!.addSublayer(snap)
        }
        player.seek(to: timeline.loopStart, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.9)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.setCompletionBlock { snap.removeFromSuperlayer() }
                snap.opacity = 0
                CATransaction.commit()
            }
        }
        inLoopAudio = true
        rampVolume(to: 0, over: 0.9)
        reveal(quick: true)
    }

    func currentFrameImage() -> CGImage? {
        let t = item.currentTime()
        guard let pb = videoOut.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        return CIContext(options: nil).createCGImage(ci, from: ci.extent)
    }

    func updateSubtitle(at t: Double) {
        guard phase == .intro || phase == .revealed, config.showSubtitles else { return }
        let fade = config.subtitleFadeSeconds
        guard let i = config.subtitles.firstIndex(where: { t >= $0.start && t <= $0.end }) else {
            if currentSub >= 0 && subView.label.alphaValue > 0 { log(String(format: "字幕 %d 消失，视频时间 %.3fs", currentSub + 1, t)) }
            subView.label.alphaValue = 0; return
        }
        let sub = config.subtitles[i]
        if i != currentSub { currentSub = i; subView.widthRatio = config.subtitleWidthRatio; subView.setText(sub.text); log(String(format: "字幕 %d 出现，视频时间 %.3fs", i + 1, t)) }
        let a = min(1, (t - sub.start) / fade, (sub.end - t) / fade)
        subView.label.alphaValue = CGFloat(max(0, a))
    }

    func hideSubtitles() {
        if let o = subObserver { player.removeTimeObserver(o); subObserver = nil }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            subView.label.animator().alphaValue = 0
        }
    }

    func reveal(quick: Bool = false) {
        guard phase == .intro else { return }
        phase = .revealed
        overlay.ignoresMouseEvents = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.removeChildWindow(skipWin); skipWin.orderOut(nil)
        if !config.loopBackground {
            log("进入循环帧，循环背景已关，淡出")
            finish(fast: false); return
        }
        log("进入循环帧，透出界面")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = quick ? 0.9 : config.fadeDurationSeconds
            overlay.animator().alphaValue = config.residualAlpha
        }
    }

    /// 菜单里拖滑块时实时生效
    func apply(_ c: Config) {
        config = c
        guard phase != .ending && phase != .done else { return }
        if phase == .revealed { overlay.alphaValue = c.residualAlpha }
        rampTimer?.invalidate()
        player.volume = inLoopAudio ? 0 : Float(c.introVolume)
    }

    func rampVolume(to target: Float, over seconds: Double, then: (() -> Void)? = nil) {
        rampTimer?.invalidate()
        let start = player.volume, t0 = Date()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let k = min(1, Date().timeIntervalSince(t0) / max(seconds, 0.01))
            self.player.volume = start + (target - start) * Float(k)
            if k >= 1 { timer.invalidate(); then?() }
        }
    }

    func finish(fast: Bool) {
        guard phase != .ending && phase != .done else { return }
        phase = .ending
        overlay.ignoresMouseEvents = true
        let d = fast ? 0.4 : 1.2
        log(fast ? "关闭（跳过）" : "淡出")
        skipWin.orderOut(nil)
        hideSubtitles()
        rampVolume(to: 0, over: d)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = d
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.teardown() })
    }

    func teardown() {
        guard phase != .done else { return }
        phase = .done
        tick?.invalidate(); rampTimer?.invalidate()
        if let o = timeObserver { player.removeTimeObserver(o) }
        if let o = volObserver { player.removeTimeObserver(o) }
        if let o = subObserver { player.removeTimeObserver(o) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = activateObs { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        player.pause(); player.replaceCurrentItem(with: nil)
        overlay.removeChildWindow(skipWin); overlay.removeChildWindow(subWin)
        skipWin.orderOut(nil); subWin.orderOut(nil); overlay.orderOut(nil)
        log("播放结束")
        onDone()
    }
}

// MARK: - 菜单里的滑块

final class SliderRow: NSView {
    let slider: NSSlider
    let valueLabel = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(title: String, value: Double, max: Double) {
        slider = NSSlider(value: value, minValue: 0, maxValue: max, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 46))
        let t = NSTextField(labelWithString: title)
        t.font = .menuFont(ofSize: 13)
        t.frame = NSRect(x: 20, y: 24, width: 170, height: 17)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 190, y: 24, width: 50, height: 17)
        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 20)
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(changed)
        addSubview(t); addSubview(valueLabel); addSubview(slider)
        refreshLabel()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refreshLabel() { valueLabel.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%" }
    @objc func changed() { refreshLabel(); onChange?(slider.doubleValue) }
}

// MARK: - 设置窗口（菜单栏图标被系统藏起来时也能调）

final class SettingsWindow: NSWindowController {
    let intro = NSButton(checkboxWithTitle: "打开豆包时播放开屏动画", target: nil, action: nil)
    let loop = NSButton(checkboxWithTitle: "保留循环背景", target: nil, action: nil)
    var rows: [SliderRow] = []
    weak var app: AppDelegate?

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "豆包开机动画"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        intro.target = self; intro.action = #selector(toggled)
        loop.target = self; loop.action = #selector(toggled)
        let c = app.config
        let r1 = SliderRow(title: "背景不透明度", value: c.residualAlpha, max: 0.8)
        r1.onChange = { [weak app] v in app?.update { $0.residualAlpha = v } }
        let r2 = SliderRow(title: "开屏音量", value: c.introVolume, max: 1)
        r2.onChange = { [weak app] v in app?.update { $0.introVolume = v } }
        rows = [r1, r2]
        let b1 = NSButton(title: "播放一次开屏动画", target: app, action: #selector(AppDelegate.previewIntro))
        let b2 = NSButton(title: "开启循环背景", target: app, action: #selector(AppDelegate.previewLoop))
        let b3 = NSButton(title: "关掉动画 / 背景", target: app, action: #selector(AppDelegate.stopShow))
        let tip = NSTextField(wrappingLabelWithString: "以后想打开这个窗口：在聚焦搜索（⌘空格）里搜 DoubaoBootAnimation 打开。")
        tip.font = .systemFont(ofSize: 11); tip.textColor = .secondaryLabelColor
        for r in rows { r.widthAnchor.constraint(equalToConstant: 260).isActive = true
                        r.heightAnchor.constraint(equalToConstant: 46).isActive = true }
        let stack = NSStackView(views: [intro, loop] + rows + [b1, b2, b3, tip])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.setCustomSpacing(16, after: loop); stack.setCustomSpacing(16, after: r2)
        tip.preferredMaxLayoutWidth = 260
        w.contentView = stack
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        guard let c = app?.config else { return }
        intro.state = c.playIntro ? .on : .off
        loop.state = c.loopBackground ? .on : .off
        rows[0].slider.doubleValue = c.residualAlpha
        rows[1].slider.doubleValue = c.introVolume
        rows.forEach { $0.refreshLabel() }
    }
    @objc func toggled() {
        app?.update { $0.playIntro = intro.state == .on; $0.loopBackground = loop.state == .on }
        app?.refreshMenu()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var config = Config.load()
    var statusItem: NSStatusItem!
    var introItem: NSMenuItem!
    var loopItem: NSMenuItem!
    var stopItem: NSMenuItem!
    var alphaRow: SliderRow!
    var introVolRow: SliderRow!
    var show: Show?
    var waiting: Timer?
    var settings: SettingsWindow?
    lazy var cache: TimelineCache = {
        let args = CommandLine.arguments
        let reps = args.firstIndex(of: "--repeats").flatMap { i in i + 1 < args.count ? Int(args[i + 1]) : nil } ?? 5000
        return TimelineCache(introURL: introURL, loopURL: loopURL, repeats: reps)
    }()
    let previewOnly = CommandLine.arguments.contains("--preview")
    let loopOnlyPreview = CommandLine.arguments.contains("--loop-only")

    var introURL: URL { Bundle.main.url(forResource: "intro", withExtension: "mp4")! }
    var loopURL: URL { Bundle.main.url(forResource: "loop", withExtension: "mp4")! }

    func applicationDidFinishLaunching(_ n: Notification) {
        if !(previewOnly || loopOnlyPreview) { _ = cache }
        if CommandLine.arguments.contains("--wait-cache") {
            _ = cache
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
                guard let self, self.cache.isReady else { return }
                t.invalidate()
                if !self.startOnCurrentWindow(withIntro: !self.loopOnlyPreview, exitWhenDone: true) { exit(1) }
            }
            return
        }
        if previewOnly || loopOnlyPreview {
            log(loopOnlyPreview ? "预览模式（只循环背景）" : "预览模式")
            guard startOnCurrentWindow(withIntro: !loopOnlyPreview, exitWhenDone: true) else {
                log("没找到正在运行的豆包窗口"); exit(1)
            }
            return
        }
        // 只留一个常驻：文件锁判断，抢不到锁说明已经有一个在跑，通知它弹设置窗口后退出
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let lockFD = open(Config.dir.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
        if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            log("已经有一个在运行，通知它弹出设置窗口后退出")
            DistributedNotificationCenter.default().postNotificationName(showSettingsNote, object: nil, userInfo: nil, deliverImmediately: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: showSettingsNote, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        setupMenu()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        log("常驻启动，开屏=\(config.playIntro) 循环背景=\(config.loopBackground)")
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.statusItem.button?.performClick(nil) }
        }
    }

    func setupMenu() {
        let posKey = "NSStatusItem Preferred Position main"
        if UserDefaults.standard.object(forKey: posKey) == nil || CommandLine.arguments.contains("--reset-icon") {
            UserDefaults.standard.set(230, forKey: posKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "main"
        statusItem.behavior = []
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "豆包开机动画")
        let m = NSMenu(); m.delegate = self

        let h1 = NSMenuItem(title: "打开豆包时", action: nil, keyEquivalent: ""); h1.isEnabled = false
        m.addItem(h1)
        introItem = item("播放开屏动画", #selector(toggleIntro), m)
        loopItem = item("保留循环背景", #selector(toggleLoop), m)
        m.addItem(.separator())

        alphaRow = SliderRow(title: "背景不透明度", value: config.residualAlpha, max: 0.8)
        alphaRow.onChange = { [weak self] v in self?.update { $0.residualAlpha = v } }
        addView(alphaRow, m)
        introVolRow = SliderRow(title: "开屏音量", value: config.introVolume, max: 1)
        introVolRow.onChange = { [weak self] v in self?.update { $0.introVolume = v } }
        addView(introVolRow, m)
        m.addItem(.separator())

        let h2 = NSMenuItem(title: "现在，在豆包窗口上", action: nil, keyEquivalent: ""); h2.isEnabled = false
        m.addItem(h2)
        item("播放一次开屏动画", #selector(previewIntro), m)
        item("开启循环背景", #selector(previewLoop), m)
        stopItem = item("关掉动画 / 背景", #selector(stopShow), m)
        m.addItem(.separator())
        item("设置窗口…", #selector(openSettings), m)
        item("打开设置文件…", #selector(openConfig), m)
        item("卸载豆包开机动画…", #selector(uninstall), m)
        statusItem.menu = m
        refreshMenu()
    }

    @discardableResult
    func item(_ title: String, _ sel: Selector, _ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i); return i
    }
    func addView(_ v: NSView, _ m: NSMenu) { let i = NSMenuItem(); i.view = v; m.addItem(i) }

    func menuWillOpen(_ menu: NSMenu) { config = Config.load(); refreshMenu() }

    func refreshMenu() {
        settings?.refresh()
        introItem.state = config.playIntro ? .on : .off
        loopItem.state = config.loopBackground ? .on : .off
        stopItem.isEnabled = show != nil
        alphaRow.slider.doubleValue = config.residualAlpha; alphaRow.refreshLabel()
        introVolRow.slider.doubleValue = config.introVolume; introVolRow.refreshLabel()
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config); config.save(); show?.apply(config)
    }

    @objc func toggleIntro() { update { $0.playIntro.toggle() }; refreshMenu(); log("开屏动画 → \(config.playIntro)") }
    @objc func toggleLoop() { update { $0.loopBackground.toggle() }; refreshMenu(); log("循环背景 → \(config.loopBackground)") }
    @objc func previewIntro() { show?.teardown(); _ = startOnCurrentWindow(withIntro: true, exitWhenDone: false) }
    @objc func previewLoop() { show?.teardown(); _ = startOnCurrentWindow(withIntro: false, exitWhenDone: false) }
    @objc func stopShow() { show?.finish(fast: true) }
    @objc func openConfig() { NSWorkspace.shared.open(Config.file) }

    /// 彻底卸载：删登录项、小程序、设置、日志，然后退出。Doubao.app 从来没被改过，不用还原。
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "卸载豆包开机动画？"
        a.informativeText = "会删除这个小程序、开机自启、设置和日志。豆包本身没有被改过，卸载后就是原装的样子。"
        a.addButton(withTitle: "卸载"); a.addButton(withTitle: "取消")
        a.buttons[0].hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        show?.teardown()
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let label = bundleLabel
        try? fm.removeItem(at: home.appendingPathComponent("Library/LaunchAgents/\(label).plist"))
        try? fm.removeItem(at: Config.dir)
        try? fm.removeItem(at: logURL)
        try? fm.removeItem(at: home.appendingPathComponent("Library/Preferences/\(label).plist"))
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" { try? fm.removeItem(at: bundle) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }
    @objc func openSettings() {
        config = Config.load()
        if settings == nil { settings = SettingsWindow(app: self) }
        settings!.refresh()
        settings!.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        settings!.showWindow(nil)
        settings!.window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return false
    }

    @discardableResult
    func startOnCurrentWindow(withIntro: Bool, exitWhenDone: Bool) -> Bool {
        guard show == nil,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: doubaoBundleID).first,
              let t = findDoubaoWindow(pid: app.processIdentifier) else { return false }
        start(pid: app.processIdentifier, target: t, withIntro: withIntro, exitWhenDone: exitWhenDone)
        return true
    }

    @objc func appLaunched(_ n: Notification) {
        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == doubaoBundleID else { return }
        config = Config.load()
        log("检测到豆包启动 pid=\(app.processIdentifier)，开屏=\(config.playIntro) 循环背景=\(config.loopBackground)")
        guard config.playIntro || config.loopBackground else { return }
        show?.teardown()
        let withIntro = config.playIntro
        // 等主窗口出现，最多 30 秒
        let pid = app.processIdentifier, deadline = Date().addingTimeInterval(30)
        waiting?.invalidate()
        waiting = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let t = findDoubaoWindow(pid: pid) {
                timer.invalidate(); self.start(pid: pid, target: t, withIntro: withIntro, exitWhenDone: false)
            } else if Date() > deadline || app.isTerminated {
                timer.invalidate(); log("等不到豆包主窗口，放弃这次")
            }
        }
    }

    func start(pid: pid_t, target: TargetWindow, withIntro: Bool, exitWhenDone: Bool) {
        var s: Show!
        let t0 = Date()
        s = Show(pid: pid, target: target, config: config, withIntro: withIntro,
                 timeline: cache.get(withIntro: withIntro)) { [weak self] in
            if self?.show === s { self?.show = nil }
            if exitWhenDone { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) } }
        }
        show = s
        if let i = CommandLine.arguments.firstIndex(of: "--test-skip"), i + 1 < CommandLine.arguments.count,
           let sec = Double(CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak s] in s?.skipIntro() }
        }
        log("从点击到浮层出现 \(Int(Date().timeIntervalSince(t0) * 1000))ms")
    }
}

// MARK: - 常量（与 bundle / 脚本保持一致）

let bundleLabel = "io.github.doubao.boot-animation"

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
