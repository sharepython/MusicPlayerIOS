import Foundation
import Observation

/// 歌词缓存，以及在后台给整个曲库自动生成歌词。
/// 每首歌依次尝试：同名 .lrc / 内嵌歌词 → 在线歌词库 → 本机语音识别。正在播放的歌插队优先处理
@MainActor @Observable
final class LyricsStore {
    enum Activity {
        case searching, recognizing
    }

    private(set) var cache: [String: Lyrics] = [:]
    /// 正在处理的那首歌
    private(set) var working: (id: String, activity: Activity)?
    /// 等着查本地 / 在线歌词的歌
    private(set) var pendingOnline: [String] = []
    /// 在线没查到、等着语音识别的歌
    private(set) var pendingRecognize: [String] = []
    /// App 在前台时才做语音识别，后台只查在线歌词
    var isActive = true { didSet {
        if isActive && !oldValue {
            retryDeferred()
        }
    } }
    /// 没网，或者没允许小狗音乐使用网络
    private(set) var offline = false
    /// 歌词库服务器忙，队列暂停一会后自动继续
    private(set) var serverBusy = false
    /// 有歌等着识别，但用户还没授权语音识别。授权框只在用户打开歌词页点按钮时弹
    private(set) var needsPermission = LyricsRecognizer.supported && LyricsRecognizer.notAsked

    /// 每首歌的歌词时间微调（秒），正数是歌词提前。存在 UserDefaults 里，重新获取歌词也不丢
    private(set) var offsets = UserDefaults.standard.dictionary(forKey: "lyricsOffsets") as? [String: Double] ?? [:]
    static let maxOffset = 10.0

    func offset(for id: String) -> Double {
        offsets[id] ?? 0
    }

    /// 按 0.1 秒取整，最多挪 maxOffset 秒；挪回 0 就删掉这条
    func setOffset(_ s: Double, for id: String) {
        let s = (min(max(s, -Self.maxOffset), Self.maxOffset) * 10).rounded() / 10
        offsets[id] = s == 0 ? nil : s
        UserDefaults.standard.set(offsets, forKey: "lyricsOffsets")
    }

    /// 按这首歌的微调挪过时间的歌词；歌词页用它，律动模式改用 offset 挪播放时间（免得每调一下就重建场景）
    func lyrics(for id: String) -> Lyrics? {
        cache[id].map { $0.shifted(by: offset(for: id)) }
    }

    /// 这首歌在线没找到，正等着识别
    func waitingForRecognition(_ id: String) -> Bool {
        pendingRecognize.contains(id)
    }

    /// 后台还没处理完的歌曲数
    var remaining: Int { pendingOnline.count + pendingRecognize.count + (working == nil ? 0 : 1) }

    @ObservationIgnored private var songs: [String: Song] = [:]
    /// 正在播放的歌，下一个就处理它
    @ObservationIgnored private var urgent: String?
    @ObservationIgnored private var playing: String?
    /// 因为没网这次没查成的歌，回到前台或用户点重新获取时重新排队
    @ObservationIgnored private var deferred: Set<String> = []
    /// 连续遇到服务器忙的次数，决定歇多久
    @ObservationIgnored private var busyStreak = 0
    /// 每首歌因为服务器忙重查了几次
    @ObservationIgnored private var busyRetries: [String: Int] = [:]
    /// 处理完当前这首后要歇的时间
    @ObservationIgnored private var cooldown: Duration?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var loaded = false

    init() {
        Task {
            let disk = await Task.detached { LyricsDisk.loadAll() }.value
            cache.merge(disk) { new, _ in new }
            loaded = true
            enqueueMissing()
            schedule()
        }
    }

    func activity(for id: String) -> Activity? {
        working?.id == id ? working?.activity : nil
    }

    /// 曲库变化时调用：新歌排队生成，删掉的歌清掉缓存
    func sync(_ list: [Song]) {
        songs = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in cache.keys where songs[id] == nil {
            cache[id] = nil
            LyricsDisk.remove(id)
        }
        pendingOnline.removeAll { songs[$0] == nil }
        pendingRecognize.removeAll { songs[$0] == nil }
        enqueueMissing()
        schedule()
    }

    /// 回到前台时，把之前因为网络没查成的歌重新排队
    private func retryDeferred() {
        pendingOnline += deferred.filter { songs[$0] != nil && !pendingOnline.contains($0) }
        deferred.removeAll()
        schedule()
    }

    /// 切到这首歌时调用，让它插队
    func prioritize(_ id: String?) {
        playing = id
        guard let id, cache[id] == nil, working?.id != id else { return }
        urgent = id
        if !pendingOnline.contains(id) && !pendingRecognize.contains(id) {
            pendingOnline.insert(id, at: 0)
        }
        schedule()
    }

    /// 用户点「重新获取」：丢掉旧结果，马上重新查
    func refresh(_ id: String) {
        guard working?.id != id else { return }
        cache[id] = nil
        LyricsDisk.remove(id)
        pendingRecognize.removeAll { $0 == id }
        deferred.remove(id)
        if !pendingOnline.contains(id) {
            pendingOnline.insert(id, at: 0)
        }
        urgent = id
        schedule()
    }

    private func enqueueMissing() {
        guard loaded else { return }
        let queued = Set(pendingOnline + pendingRecognize).union(deferred)
        pendingOnline += songs.values
            .filter { cache[$0.id] == nil && !queued.contains($0.id) && working?.id != $0.id }
            .sorted { $0.sortKey < $1.sortKey }
            .map(\.id)
    }

    private func schedule() {
        guard loaded, worker == nil else { return }
        worker = Task { await run() }
    }

    private func run() async {
        while let (id, online) = next() {
            guard let song = songs[id], cache[id] == nil else { continue }
            working = (id, online ? .searching : .recognizing)
            if online {
                await lookUp(song)
            } else {
                await recognize(song)
            }
            working = nil
            if let pause = cooldown {
                cooldown = nil
                try? await Task.sleep(for: pause)
            }
        }
        worker = nil
    }

    /// 取下一首：先插队的，再查在线，最后做识别（只在前台、并且用户已经回答过授权）
    private func next() -> (String, Bool)? {
        let canRecognize = isActive && !needsPermission
        if let id = urgent {
            urgent = nil
            if let i = pendingOnline.firstIndex(of: id) {
                pendingOnline.remove(at: i)
                return (id, true)
            }
            if canRecognize, let i = pendingRecognize.firstIndex(of: id) {
                pendingRecognize.remove(at: i)
                return (id, false)
            }
        }
        if !pendingOnline.isEmpty {
            return (pendingOnline.removeFirst(), true)
        }
        if canRecognize, !pendingRecognize.isEmpty {
            return (pendingRecognize.removeFirst(), false)
        }
        return nil
    }

    /// 用户在歌词页点「用语音识别生成」：弹授权框，回答后开始识别排队的歌
    func allowRecognition() {
        Task {
            await LyricsRecognizer.requestPermission()
            needsPermission = false
            schedule()
        }
    }

    private func lookUp(_ song: Song) async {
        if let lines = await LyricsDisk.local(song) {
            return store(Lyrics(songID: song.id, source: .local, lines: lines))
        }
        do {
            if let l = try await LyricsFetcher.fetch(song) {
                store(l)
            } else {
                notFoundOnline(song)
            }
            offline = false
            serverBusy = false
            busyStreak = 0
        } catch is LyricsFetcher.Busy {
            // 有来源服务器忙、其他来源又没找到：这首放到队尾稍后再查（正在播放的放队首），试 5 次还不行就当作在线没有
            busyStreak += 1
            busyRetries[song.id, default: 0] += 1
            if busyRetries[song.id, default: 0] >= 5 {
                notFoundOnline(song)
            } else if song.id == playing {
                pendingOnline.insert(song.id, at: 0)
            } else {
                pendingOnline.append(song.id)
            }
            // 连续好几首都碰到服务器忙，整个队列歇一会，越忙歇得越久
            if busyStreak >= 3 {
                serverBusy = true
                cooldown = .seconds(min(10 * busyStreak, 300))
            }
        } catch {
            // 没网：剩下的先不查，等回到前台（比如去设置里允许了联网）或用户点重新获取时再试
            offline = true
            deferred.insert(song.id)
            deferred.formUnion(pendingOnline)
            pendingOnline.removeAll()
        }
    }

    /// 在线确定没有，转去识别；正在播放的歌继续插队
    private func notFoundOnline(_ song: Song) {
        busyRetries[song.id] = nil
        pendingRecognize.append(song.id)
        if song.id == playing {
            urgent = song.id
        }
    }

    private func recognize(_ song: Song) async {
        let lines = await LyricsRecognizer.recognize(song)
        guard songs[song.id] != nil else { return }
        // 识别到一半切到后台导致失败的，回到前台再试
        if lines == nil, !isActive {
            return pendingRecognize.insert(song.id, at: 0)
        }
        store(Lyrics(songID: song.id, source: lines == nil ? .notFound : .recognized, lines: lines ?? []))
    }

    private func store(_ l: Lyrics) {
        guard songs[l.songID] != nil else { return }
        cache[l.songID] = l
        Task.detached { LyricsDisk.write(l) }
    }
}
