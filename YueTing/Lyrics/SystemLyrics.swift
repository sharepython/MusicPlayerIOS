import Observation
import UIKit

/// 把歌词显示到 App 外面：锁屏 / 控制中心 / 车机（正在唱的那句放进标题），和画中画小窗做的桌面歌词（DesktopLyrics）。
/// 平时每 0.25 秒看一次唱到哪句；桌面歌词开着、正在播放时每秒 20 帧，正在唱的那句逐字填色。
/// App 在后台也一直在跑（后台音频模式），锁屏时照样更新
@MainActor @Observable
final class SystemLyrics {
    /// 锁屏和控制中心显示歌词，默认开
    var lockScreen = UserDefaults.standard.object(forKey: "lockScreenLyrics") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(lockScreen, forKey: "lockScreenLyrics")
            tick()
        }
    }
    /// 桌面歌词开关：开着时 App 一退到后台就浮出歌词长条，回到 App 收起。
    /// 在长条上点关闭只是这次收起，开关不变，下次退到后台还会出来
    private(set) var desktopOn = UserDefaults.standard.bool(forKey: "desktopLyrics")
    /// 这台手机能不能开画中画
    var desktopSupported: Bool { DesktopLyrics.supported }

    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let store: LyricsStore
    @ObservationIgnored let desktop = DesktopLyrics()
    /// 按微调挪过时间的歌词，每 0.25 秒重取一次，逐帧画的时候不用每次都挪
    @ObservationIgnored private var lyrics: Lyrics?
    @ObservationIgnored private var lastSlow = 0.0
    @ObservationIgnored private var lastPlaying: Bool?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observer: Any?

    init(player: PlayerController, store: LyricsStore) {
        self.player = player
        self.store = store
        desktop.isPlaying = { [weak player] in player?.isPlaying ?? false }
        desktop.automatic = desktopOn
        if desktopOn {
            draw()
        }
        // 回到 App 时把长条收起来，歌词在 App 里看
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktop.stop() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                let fast = self.desktop.isActive && self.player.isPlaying
                try? await Task.sleep(for: .milliseconds(fast ? 50 : 250))
            }
        }
    }

    /// 打开 / 关掉桌面歌词开关，立刻生效、记下来，下次打开 App 还是这样
    func setDesktop(_ on: Bool) {
        guard on != desktopOn else { return }
        desktopOn = on
        UserDefaults.standard.set(on, forKey: "desktopLyrics")
        if on {
            draw()
        }
        desktop.automatic = on
        if !on {
            desktop.stop()
        }
    }

    private func tick() {
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastSlow >= 0.2 {
            lastSlow = now
            lyrics = player.currentSong.flatMap { store.lyrics(for: $0.id) }
            player.nowPlayingLine = lockScreen ? current(at: player.position + 0.2)?.text : nil
            if lastPlaying != player.isPlaying {
                lastPlaying = player.isPlaying
                desktop.invalidate()
            }
        }
        if desktopOn {
            draw()
        }
    }

    /// 正在唱的那句；还没开唱、没有带时间的歌词时为 nil
    private func current(at t: Double) -> Lyrics.Line? {
        guard let lines = lyrics?.lines, lyrics?.synced == true else { return nil }
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if (lines[mid].time ?? 0) <= t {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard let i = found, !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return lines[i]
    }

    /// 画一帧桌面歌词：只有正在唱的那句（逐字填色）；没在唱时显示歌名和歌手
    private func draw() {
        guard let song = player.currentSong else { desktop.render(.init(text: "小狗音乐", progress: 4)); return }
        let t = player.player.currentTime().seconds
        let now = player.isPlaying && t.isFinite ? t : player.position
        // 和歌词页一样：提前 0.2 秒换到下一句，逐字填色按实际时间；没有逐字时间的整句亮
        if let line = current(at: now + 0.2) {
            desktop.render(.init(text: line.text, progress: line.progress(at: now)))
        } else {
            let s = song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)"
            desktop.render(.init(text: s, progress: Double(s.utf16.count)))
        }
    }
}
