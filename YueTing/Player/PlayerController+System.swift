import AVFoundation
import MediaPlayer
import UIKit

/// 播放器的系统集成：音频会话、打断与耳机拔出、音频服务重置、锁屏 / 控制中心 / 耳机和音箱按键、断点续播
extension PlayerController {
    private struct SavedState: Codable {
        var queue: [QueueEntry]
        var original: [QueueEntry]
        var index: Int
        var position: Double
        var mode: PlayMode?
        // 旧版本分开存的随机和循环，只在读旧存档时用
        var shuffle: Bool?
        var repeatMode: String?

        /// 旧存档：随机开着算随机播放，单曲循环算单曲循环，其他（含已去掉的顺序播放）算列表循环
        var playMode: PlayMode {
            mode ?? (shuffle == true ? .shuffle : repeatMode == "one" ? .one : .loop)
        }
    }

    private static var stateFile: URL { LibraryPaths.libraryFile.deletingLastPathComponent().appendingPathComponent("player.json") }

    func setUpSystem() {
        configureSession()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // 拔耳机 / 断开蓝牙时暂停，不外放
            if reason == .oldDeviceUnavailable {
                MainActor.assumeIsolated { self?.pause() }
            }
        })
        // 系统音频服务崩了重启（少见）：会话设置和播放器都作废了，重新设一遍、换个播放器
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.configureSession()
                self.rebuildPlayer()
            }
        })
        // 切到后台、被杀前存一次进度
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        })
        library.onRemove = { [weak self] ids in self?.removeSongs(ids) }
        setUpRemoteCommands()
    }

    /// 按长时间听音乐的 App 设置：AirPlay 2 / HomePod 会把它和「音乐」App 一样对待，选输出设备时按整段音乐分配
    func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }

    func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            resumeAfterInterruption = wantsToPlay
        } else {
            let opts = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            // 电话挂断等系统允许恢复时，接着播；不允许时就停在暂停，下次别的打断结束也不会自己播起来
            if resumeAfterInterruption, opts.contains(.shouldResume) {
                resume()
            } else if resumeAfterInterruption {
                wantsToPlay = false
            }
            resumeAfterInterruption = false
        }
    }

    // MARK: - 锁屏、控制中心、耳机线控

    private func setUpRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget(handler: command { $0.resume() })
        c.pauseCommand.addTarget(handler: command { $0.pause() })
        c.togglePlayPauseCommand.addTarget(handler: command { $0.togglePlay() })
        c.nextTrackCommand.addTarget(handler: command { $0.next() })
        c.previousTrackCommand.addTarget(handler: command { $0.previous() })
        c.changePlaybackPositionCommand.addTarget(handler: command { p, e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return false }
            p.seek(to: e.positionTime)
            return true
        })
    }

    private func command(_ action: @escaping @MainActor (PlayerController) -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        command { p, _ in action(p); return true }
    }

    /// 队列是空的（没有可播的歌）时告诉系统，车机、锁屏按这个显示，不假装执行成功
    private func command(_ action: @escaping @MainActor (PlayerController, MPRemoteCommandEvent) -> Bool) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, self.currentEntry != nil else { return .noActionableNowPlayingItem }
                return action(self, e) ? .success : .commandFailed
            }
        }
    }

    /// 刷新锁屏 / 控制中心的信息。[newSong] 为 true 时连封面一起换
    func updateNowPlaying(newSong: Bool = false) {
        let center = MPNowPlayingInfoCenter.default()
        guard let song = currentSong else { center.nowPlayingInfo = nil; return }
        var info = center.nowPlayingInfo ?? [:]
        // 有歌词时标题换成正在唱的那句，歌名和歌手挪到第二行
        if let line = nowPlayingLine {
            info[MPMediaItemPropertyTitle] = line
            info[MPMediaItemPropertyArtist] = song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)"
        } else {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist
        }
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if newSong {
            info[MPMediaItemPropertyArtwork] = nil
            let id = song.id
            Task {
                guard let image = await ArtworkLoader.shared.image(for: song), currentSong?.id == id else { return }
                let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                i[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = i
            }
        }
        center.nowPlayingInfo = info
    }

    // MARK: - 断点续播

    /// 保存队列和进度，下次打开从这里继续
    func persist() {
        markSaved()
        let s = SavedState(queue: queue, original: original, index: index, position: position, mode: mode)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: Self.stateFile, options: .atomic)
        }
    }

    /// 恢复上次的队列，停在上次的位置但不自动播放
    func restore() {
        guard let data = try? Data(contentsOf: Self.stateFile),
              let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        mode = s.playMode
        queue = s.queue.filter { library.song($0.songID) != nil }
        original = s.original.filter { library.song($0.songID) != nil }
        guard !queue.isEmpty else { return }
        let cur = s.queue.indices.contains(s.index) ? s.queue[s.index].id : nil
        let i = queue.firstIndex { $0.id == cur } ?? 0
        load(i, play: false, at: queue[i].id == cur ? s.position : 0)
    }

    // MARK: - 编辑队列

    /// 插到当前歌曲后面
    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        if currentEntry == nil {
            play(songs)
            return
        }
        let entries = songs.map { QueueEntry(songID: $0.id) }
        queue.insert(contentsOf: entries, at: index + 1)
        if let cur = currentEntry, let o = original.firstIndex(of: cur) {
            original.insert(contentsOf: entries, at: o + 1)
        } else {
            original += entries
        }
        persist()
        library.notice = "将在下一首播放"
    }

    /// 加到队列末尾
    func addToQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        if currentEntry == nil {
            play(songs)
            return
        }
        let entries = songs.map { QueueEntry(songID: $0.id) }
        queue += entries
        original += entries
        persist()
        library.notice = "已加入播放队列"
    }

    func playQueueItem(_ i: Int) {
        load(i, play: true)
    }

    /// 从队列里删掉几项；删到当前歌时接着播下一首
    func removeFromQueue(at offsets: IndexSet) {
        let removed = Set(offsets.map { queue[$0].id })
        removeEntries(removed)
    }

    func moveQueue(from: IndexSet, to: Int) {
        let cur = currentEntry
        queue.move(fromOffsets: from, toOffset: to)
        index = queue.firstIndex { $0 == cur } ?? index
        if !shuffle {
            original = queue
        }
        persist()
    }

    /// 曲库删除歌曲后，把它们从队列里去掉
    func removeSongs(_ ids: Set<String>) {
        removeEntries(Set(queue.filter { ids.contains($0.songID) }.map(\.id)))
    }

    private func removeEntries(_ removed: Set<UUID>) {
        guard !removed.isEmpty else { return }
        let cur = currentEntry
        let wasPlaying = isPlaying
        // 当前歌被删时，接着播它后面第一首没被删的
        let following = queue.suffix(from: max(index, 0)).first { !removed.contains($0.id) }
        queue.removeAll { removed.contains($0.id) }
        original.removeAll { removed.contains($0.id) }
        guard !queue.isEmpty else { stop(); return }
        if let cur, !removed.contains(cur.id) {
            index = queue.firstIndex(of: cur) ?? 0
            persist()
        } else {
            load(following.flatMap { f in queue.firstIndex(of: f) } ?? 0, play: wasPlaying)
        }
    }
}
