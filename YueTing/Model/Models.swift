import Foundation

/// App 用到的几个目录
enum LibraryPaths {
    /// 歌曲文件都放这里；「文件」App 和电脑 Finder 里看到的就是这个目录
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    /// 曲库索引、歌单、收藏、播放统计
    static let libraryFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()
    /// 在线查到的封面；查一次要好几秒，不放缓存目录，免得被系统清掉
    static let onlineArtwork: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OnlineArtwork")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    /// 封面缩略图缓存；系统清理掉也没关系，用到时会从音频文件重新提取
    static let artwork: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// 一首本地歌曲。id 是相对 Documents 的路径，重新扫描时保持不变，歌单和收藏都记这个 id
struct Song: Identifiable, Codable, Hashable {
    /// 相对 Documents 的路径，例如「周杰伦 - 稻香.mp3」或「专辑/01.flac」
    var id: String
    var title: String
    var artist: String
    var album: String
    /// 时长（秒），读不出来时为 0，播放时再用播放器给的时长
    var duration: Double
    /// 碟内曲目序号，专辑页按它排序；没有时为 0
    var trackNumber: Int
    /// 加入曲库的时间，「最近添加」用
    var addedAt: Date
    /// 搜索用：标题、歌手、专辑的原文、拼音全拼、拼音首字母，全部小写
    var searchKey: String
    /// 排序用：标题的拼音
    var sortKey: String

    var fileURL: URL { LibraryPaths.documents.appendingPathComponent(id) }
}

/// 在线整理专辑查到的结果。文件里的专辑标签不动，只在曲库里换掉；
/// 标签后来被改过（和 original 对不上）就不再套用。album 和 original 一样表示查过、不用改
struct AlbumFix: Codable, Hashable {
    var original: String
    var album: String
}

/// 用户自建歌单，只存歌曲 id，按用户排好的顺序
struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [String] = []
    var createdAt = Date()
}

/// 单曲播放统计，「最近播放」「最常播放」用
struct PlayStat: Codable, Hashable {
    var count = 0
    var lastPlayed = Date.distantPast
}

/// 由歌曲按专辑名聚合出来，不落盘
struct Album: Identifiable, Hashable {
    /// 专辑名；写法稍有不同（全角半角、大小写）的算一张，用最多的那种写法
    var id: String
    /// 大多数歌的主唱是同一位时是 TA 的名字（合唱不算），否则是「群星」
    var artist: String
    /// 按曲目序号排好
    var songs: [Song]
    var sortKey: String
}

/// 由歌曲按歌手聚合出来，「A/B」「A、B」这类合唱会同时归到两位歌手下
struct Artist: Identifiable, Hashable {
    var id: String
    var songs: [Song]
    var sortKey: String
}

/// 播放队列里的一项。同一首歌可以在队列里出现多次，所以单独给每项一个 id
struct QueueEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var songID: String
}

/// 播放模式，播放页一个按钮轮流切换，和 QQ 音乐一样
enum PlayMode: String, Codable {
    /// 列表循环：按队列顺序播，播完从头再来
    case loop
    /// 单曲循环
    case one
    /// 随机播放：队列打乱后循环
    case shuffle

    var next: PlayMode {
        switch self {
        case .loop: .one
        case .one: .shuffle
        case .shuffle: .loop
        }
    }

    var icon: String {
        switch self {
        case .loop: "repeat"
        case .one: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    var label: String {
        switch self {
        case .loop: "列表循环"
        case .one: "单曲循环"
        case .shuffle: "随机播放"
        }
    }
}

/// 歌曲列表的排序方式
enum SongSort: String, CaseIterable, Identifiable {
    case title, artist, album, added
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: "歌名"
        case .artist: "歌手"
        case .album: "专辑"
        case .added: "最近添加"
        }
    }
}

/// 歌单页的几种列表：智能列表由曲库数据算出来，user 是用户自建歌单
enum PlaylistKind: Hashable {
    case favorites, recentlyAdded, recentlyPlayed, mostPlayed
    case user(UUID)
}

/// 各 Tab 的 NavigationStack 共用的跳转目标
enum Route: Hashable {
    case album(String)
    case artist(String)
    case playlist(PlaylistKind)
    /// 专辑页最后的「单曲」：只有一首的专辑和没有专辑名的歌
    case singles
}

/// 秒数格式化成「3:05」，超过一小时是「1:02:03」
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds.rounded(.down))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
