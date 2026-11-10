import AVFoundation
import Observation

/// 播放器：维护播放队列，驱动 AVPlayer，并把状态发布给界面。
/// 系统相关部分（音频会话、锁屏/控制中心、断点续播）在 PlayerController+System.swift
@MainActor @Observable
final class PlayerController {
    // 以下状态界面只读，只由 PlayerController 及其扩展修改（扩展分在别的文件，所以没法用 private(set)）
    /// 当前播放顺序；随机模式下是打乱后的顺序
    var queue: [QueueEntry] = []
    /// 当前播放项在 queue 里的下标，没有时为 -1
    var index = -1
    /// 是否在播放（含缓冲中），播放/暂停按钮按它显示
    private(set) var isPlaying = false
    /// 当前位置（秒）。播放时每 0.25 秒刷新；seek 时立刻改成目标位置，进度条不会跳回旧位置
    var position: Double = 0
    /// 当前歌曲时长（秒）
    private(set) var duration: Double = 0
    var mode: PlayMode = .loop
    var shuffle: Bool { mode == .shuffle }

    var currentEntry: QueueEntry? { queue.indices.contains(index) ? queue[index] : nil }
    var currentSong: Song? { currentEntry.flatMap { library.song($0.songID) } }

    /// 系统音频服务重置后要换一个新的（rebuildPlayer）
    @ObservationIgnored private(set) var player = AVPlayer()
    @ObservationIgnored let library: LibraryStore
    /// 未打乱的原始顺序，关闭随机时按它恢复
    @ObservationIgnored var original: [QueueEntry] = []
    @ObservationIgnored var observers: [Any] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    /// seek 进行中时忽略周期回调，否则会先回调旧位置导致进度条闪一下
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var seeking = false
    /// 本次加载是否已记过一次播放
    @ObservationIgnored private var playCounted = false
    /// 连续加载失败次数，整个队列都坏掉时停止，避免无限跳歌
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var lastSavedPosition: Double = 0
    /// 被电话等打断前是否在播，打断结束后据此恢复
    @ObservationIgnored var resumeAfterInterruption = false
    /// 用户想不想播：只在用户（或耳机、锁屏）播放、暂停时改，系统打断时不变。
    /// isPlaying 跟着播放器的状态异步更新，打断开始的通知到的时候可能已经变成 false，不能拿它判断打断前在不在播
    @ObservationIgnored var wantsToPlay = false
    /// 锁屏、控制中心、车机标题处显示的正在唱的那句（SystemLyrics 设）；nil 时显示歌名
    @ObservationIgnored var nowPlayingLine: String? {
        didSet {
            if nowPlayingLine != oldValue {
                updateNowPlaying()
            }
        }
    }

    init(library: LibraryStore) {
        self.library = library
        observePlayer()
        observers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.itemFinished()
            }
        })
        setUpSystem()
        restore()
    }

    // MARK: - 播放控制

    /// 播放一组歌，从第 [start] 首开始。shuffle 传 true 切到随机播放，传 false 时随机播放改回列表循环，传 nil 沿用当前模式
    func play(_ songs: [Song], startAt start: Int? = nil, shuffle newShuffle: Bool? = nil) {
        guard !songs.isEmpty else { return }
        if newShuffle == true {
            mode = .shuffle
        }
        if newShuffle == false, mode == .shuffle {
            mode = .loop
        }
        let entries = songs.map { QueueEntry(songID: $0.id) }
        original = entries
        if shuffle {
            // 随机时点中的那首先播，其余打乱
            let head = start.map { entries[min(max($0, 0), entries.count - 1)] } ?? entries.randomElement()!
            queue = [head] + entries.filter { $0.id != head.id }.shuffled()
            load(0, play: true)
        } else {
            queue = entries
            load(min(max(start ?? 0, 0), entries.count - 1), play: true)
        }
    }

    /// 给 player 挂上进度回调和播放状态的监听
    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, p === self.player, self.isPlaying != playing else { return }
                self.isPlaying = playing
                self.updateNowPlaying()
                if !playing {
                    self.persist()
                }
            }
        }
    }

    /// 系统音频服务重置后，旧的 AVPlayer 再也出不了声：换一个新的，重新加载当前这首，停在原来的位置，原来在播就接着播
    func rebuildPlayer() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        player.replaceCurrentItem(with: nil)
        player = AVPlayer()
        observePlayer()
        isPlaying = false
        guard currentEntry != nil else { return }
        load(index, play: wantsToPlay, at: position)
    }

    func togglePlay() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentEntry != nil else { return }
        wantsToPlay = true
        activateSession()
        if player.currentItem == nil {
            load(index, play: true, at: position)
        } else {
            player.play()
        }
    }

    func pause() {
        wantsToPlay = false
        player.pause()
    }

    /// 下一首；到队尾时回到第一首
    func next() {
        guard !queue.isEmpty else { return }
        load(index + 1 < queue.count ? index + 1 : 0, play: isPlaying)
    }

    /// 上一首；在第一首时跳到队尾，和 next() 对称
    func previous() {
        guard !queue.isEmpty else { return }
        load(index > 0 ? index - 1 : queue.count - 1, play: isPlaying)
    }

    /// 跳到当前歌曲的 [seconds] 处，暂停时也立刻生效
    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = target
        guard player.currentItem != nil else { return }
        seekGeneration += 1
        let gen = seekGeneration
        seeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                // 连续拖动时只认最后一次 seek 的完成回调
                guard let self, gen == self.seekGeneration else { return }
                self.seeking = false
                self.updateNowPlaying()
                self.persist()
            }
        }
        updateNowPlaying()
    }

    /// 切到下一个播放模式；进出随机播放时打乱或恢复队列，当前这首不受影响
    func cycleMode() {
        let wasShuffle = shuffle
        mode = mode.next
        if shuffle != wasShuffle, let cur = currentEntry {
            if shuffle {
                queue = [cur] + original.filter { $0.id != cur.id }.shuffled()
                index = 0
            } else {
                queue = original
                index = queue.firstIndex { $0.id == cur.id } ?? 0
            }
        }
        persist()
    }

    // MARK: - 加载与自动切歌

    /// 加载队列第 [i] 项，[start] 是起始秒数
    func load(_ i: Int, play: Bool, at start: Double = 0) {
        guard queue.indices.contains(i), let song = library.song(queue[i].songID) else { stop(); return }
        index = i
        nowPlayingLine = nil
        let item = AVPlayerItem(url: song.fileURL)
        itemObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                if status == .failed {
                    self.itemFailed()
                }
                // 标签里读不出时长时用播放器解析出来的
                if status == .readyToPlay, self.duration <= 0, seconds.isFinite {
                    self.duration = seconds
                    self.updateNowPlaying()
                }
            }
        }
        seekGeneration += 1
        seeking = false
        player.replaceCurrentItem(with: item)
        duration = song.duration
        position = start
        playCounted = false
        if start > 0 {
            seek(to: start)
        }
        if play {
            wantsToPlay = true
            activateSession()
            player.play()
        }
        updateNowPlaying(newSong: true)
        persist()
    }

    private func tick(_ t: Double) {
        guard !seeking, t.isFinite, player.currentItem != nil else { return }
        position = t
        if t > 1 {
            failures = 0
        }
        if !playCounted, let id = currentEntry?.songID, t >= min(30, max(duration / 2, 1)) {
            playCounted = true
            library.recordPlay(id)
        }
        if abs(t - lastSavedPosition) >= 5 {
            persist()
        }
    }

    private func itemFinished() {
        if mode == .one {
            seek(to: 0)
            player.play()
            return
        }
        load(index + 1 < queue.count ? index + 1 : 0, play: true)
    }

    private func itemFailed() {
        failures += 1
        library.notice = "「\(currentSong?.title ?? "")」无法播放，已跳过"
        if failures >= queue.count {
            stop()
        } else {
            load(index + 1 < queue.count ? index + 1 : 0, play: true)
        }
    }

    /// 清空队列并停止
    func stop() {
        wantsToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        original = []
        index = -1
        position = 0
        duration = 0
        updateNowPlaying(newSong: true)
        persist()
    }

    func markSaved() {
        lastSavedPosition = position
    }
}
