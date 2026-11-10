import Foundation
import Observation

/// 曲库：歌曲、歌单、收藏、播放统计，整体存成一个 JSON。
/// 专辑和歌手不落盘，每次歌曲变化时重新聚合。只在主线程读写
@MainActor @Observable
final class LibraryStore {
    /// 全部歌曲，按标题拼音排好
    private(set) var songs: [Song] = [] { didSet { rebuild() } }
    private(set) var songsByID: [String: Song] = [:]
    /// 认得出专辑名的全部专辑（不含「未知专辑」），按拼音排好
    private(set) var albums: [Album] = []
    /// 专辑页的「单曲」：所在专辑只有这一首、或者没有专辑名的歌，按歌手排好
    private(set) var singles: [Song] = []
    @ObservationIgnored private var albumsByKey: [String: Album] = [:]
    private(set) var artists: [Artist] = []
    @ObservationIgnored private var artistsByKey: [String: Artist] = [:]
    /// 在线整理专辑的结果，歌曲 id → 改成的专辑；见 LibraryStore+Albums
    var albumFixes: [String: AlbumFix] = [:]
    /// 正在在线整理专辑：查到第几首 / 一共几首
    var albumProgress: (done: Int, total: Int)?
    @ObservationIgnored var albumTask: Task<Void, Never>?
    /// 查过封面的歌 → 封面从哪来；文件里有封面或没查到的是空字符串
    var onlineCovers: [String: String] = [:]
    var coverProgress: (done: Int, total: Int)?
    /// 每存下一张在线封面加一，封面视图跟着重新加载
    var coverRevision = 0
    @ObservationIgnored var coverTask: Task<Void, Never>?
    private(set) var playlists: [Playlist] = []
    /// 收藏的歌曲 id，最近收藏的在前
    private(set) var favorites: [String] = [] { didSet { favoriteSet = Set(favorites) } }
    private(set) var favoriteSet: Set<String> = []
    private(set) var stats: [String: PlayStat] = [:]
    /// 正在扫描或导入，工具栏显示转圈
    private(set) var isScanning = false
    /// 顶部浮出的一句提示，例如「已导入 3 首」，界面显示 2 秒后清空
    var notice: String?

    /// 歌曲被删除（或文件被用户在「文件」App 里删掉）后通知播放器把它们移出队列
    @ObservationIgnored var onRemove: ((Set<String>) -> Void)?
    /// 最近一次扫描任务；新扫描排在它后面，保证导入后的扫描不会因为「正在扫」被跳过
    @ObservationIgnored var scanTask: Task<Int, Never>?
    /// 入库时用的标签识别规则版本，比 MetadataReader.version 旧时下次扫描重读全部标签
    @ObservationIgnored var metadataVersion = MetadataReader.version

    private struct Snapshot: Codable {
        var songs: [Song]
        var playlists: [Playlist]
        var favorites: [String]
        var stats: [String: PlayStat]
        /// 老版本存的没有这个字段，算作 1
        var metadataVersion: Int?
        var albumFixes: [String: AlbumFix]?
        var onlineCovers: [String: String]?
    }

    init() {
        // 同步加载，保证播放器恢复上次队列时歌曲已经在了
        if let data = try? Data(contentsOf: LibraryPaths.libraryFile),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            songs = s.songs
            playlists = s.playlists
            favorites = s.favorites
            stats = s.stats
            metadataVersion = s.metadataVersion ?? 1
            albumFixes = s.albumFixes ?? [:]
            onlineCovers = s.onlineCovers ?? [:]
        }
    }

    func save() {
        let s = Snapshot(songs: songs, playlists: playlists, favorites: favorites, stats: stats, metadataVersion: metadataVersion, albumFixes: albumFixes,
                     onlineCovers: onlineCovers)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: LibraryPaths.libraryFile, options: .atomic)
        }
    }

    func song(_ id: String) -> Song? {
        songsByID[id]
    }

    func songs(_ ids: [String]) -> [Song] {
        ids.compactMap { songsByID[$0] }
    }

    /// 按歌曲上写的专辑名找专辑，繁简、全角半角、大小写、首尾空格不同也算同一张
    func album(_ name: String) -> Album? {
        albumsByKey[Self.nameKey(name)]
    }

    /// 歌手也一样，「林俊傑」和「林俊杰」是同一位
    func artist(_ name: String) -> Artist? {
        artistsByKey[Self.nameKey(name)]
    }

    func playlist(_ id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// 替换整个歌曲列表（扫描、导入、删除后调用），保持按拼音排序；重读过标签的歌重新套上在线查到的专辑
    func setSongs(_ list: [Song]) {
        songs = list.map(applyFix).sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
    }

    private func rebuild() {
        songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // 「哎呦，不错哦」和「哎呦,不错哦」、「葉惠美」和「叶惠美」算一张；没有专辑名的歌不凑成一张「未知专辑」
        let byAlbum = Dictionary(grouping: songs.filter { $0.album != Self.unknownAlbum }) { Self.nameKey($0.album) }
        albums = byAlbum.values.map { list in
            let sorted = list.sorted { a, b in
                // 没有曲目号的排在最后，同号按标题
                (a.trackNumber == 0 ? Int.max : a.trackNumber, a.sortKey) < (b.trackNumber == 0 ? Int.max : b.trackNumber, b.sortKey)
            }
            let name = Self.mostCommon(list.map(\.album))
            return Album(id: name, artist: Self.albumArtist(list), songs: sorted, sortKey: MetadataReader.pinyin(name))
        }.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        albumsByKey = Dictionary(albums.map { (Self.nameKey($0.id), $0) }, uniquingKeysWith: { a, _ in a })
        singles = songs.filter { album($0.album).map { $0.songs.count < 2 } ?? true }
            .map { (MetadataReader.pinyin($0.artist), $0) }.sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }.map(\.1)
        var byArtist: [String: (names: [String], songs: [Song])] = [:]
        for s in songs {
            for name in Self.splitArtists(s.artist) {
                byArtist[Self.nameKey(name), default: ([], [])].names.append(name)
                byArtist[Self.nameKey(name)]!.songs.append(s)
            }
        }
        artists = byArtist.values.map { a in
            let name = Self.mostCommon(a.names)
            return Artist(id: name, songs: a.songs, sortKey: MetadataReader.pinyin(name))
        }.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        artistsByKey = Dictionary(artists.map { (Self.nameKey($0.id), $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 读不到专辑标签时 MetadataReader 填的专辑名
    static let unknownAlbum = "未知专辑"

    /// 判断是不是同一张专辑、同一位歌手用：繁体转简体、全角转半角、去掉首尾空格、不分大小写
    nonisolated static func nameKey(_ name: String) -> String {
        let s = name.precomposedStringWithCanonicalMapping
        let h = s.applyingTransform(Han.toSimplified, reverse: false) ?? s
        return (h.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? h).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// 同一个名字的几种写法里显示哪种：有简体写法就用简体的，再挑出现最多的
    private static func mostCommon(_ names: [String]) -> String {
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { a, b in
            (Han.isSimplified(a.key) ? 1 : 0, a.value, b.key) < (Han.isSimplified(b.key) ? 1 : 0, b.value, a.key)
        }!.key
    }

    /// 专辑歌手：每首歌拆出的第一位歌手里最多的那位，「周杰伦/杨瑞代」这种合唱不会把整张专辑变成群星；
    /// 不到一半的歌是同一位歌手时才算群星
    private static func albumArtist(_ list: [Song]) -> String {
        let main = mostCommon(list.map { splitArtists($0.artist)[0] }), key = nameKey(main)
        return list.filter { splitArtists($0.artist).map(nameKey).contains(key) }.count * 2 > list.count ? main : "群星"
    }

    /// 「周杰伦/费玉清」「A、B」「A & B」拆成多位歌手
    static func splitArtists(_ s: String) -> [String] {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "/、;；&＆"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? [s] : parts
    }

    // MARK: - 排序与智能列表

    func sorted(_ sort: SongSort) -> [Song] {
        switch sort {
        case .title: songs
        // 先算好每首的歌手拼音再排，避免比较时反复转换
        case .artist: songs.map { (MetadataReader.pinyin($0.artist), $0) }.sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }.map(\.1)
        case .album: albums.flatMap(\.songs) + songs.filter { $0.album == Self.unknownAlbum }
        case .added: songs.sorted { $0.addedAt > $1.addedAt }
        }
    }

    func songs(for kind: PlaylistKind) -> [Song] {
        switch kind {
        case .favorites: songs(favorites)
        case .recentlyAdded: Array(songs.sorted { $0.addedAt > $1.addedAt }.prefix(100))
        case .recentlyPlayed:
            songs(stats.filter { $0.value.count > 0 }.sorted { $0.value.lastPlayed > $1.value.lastPlayed }.prefix(100).map(\.key))
        case .mostPlayed:
            songs(stats.filter { $0.value.count > 0 }.sorted { $0.value.count > $1.value.count }.prefix(100).map(\.key))
        case .user(let id): songs(playlist(id)?.songIDs ?? [])
        }
    }

    func title(for kind: PlaylistKind) -> String {
        switch kind {
        case .favorites: "我喜欢"
        case .recentlyAdded: "最近添加"
        case .recentlyPlayed: "最近播放"
        case .mostPlayed: "最常播放"
        case .user(let id): playlist(id)?.name ?? "歌单"
        }
    }

    /// 搜索：歌名 / 歌手 / 专辑的原文、全拼、拼音首字母，忽略大小写和空格
    func search(_ query: String) -> (songs: [Song], albums: [Album], artists: [Artist]) {
        let q = query.lowercased().replacingOccurrences(of: " ", with: "")
        guard !q.isEmpty else { return ([], [], []) }
        return (songs.filter { $0.searchKey.contains(q) },
                albums.filter { MetadataReader.searchKey([$0.id]).contains(q) },
                artists.filter { MetadataReader.searchKey([$0.id]).contains(q) })
    }

    // MARK: - 收藏、统计、歌单

    func isFavorite(_ id: String) -> Bool {
        favoriteSet.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if favoriteSet.contains(id) {
            favorites.removeAll { $0 == id }
        } else {
            favorites.insert(id, at: 0)
        }
        save()
    }

    /// 播放器在一首歌播过 30 秒（短歌播过一半）时调用，每次加载只记一次
    func recordPlay(_ id: String) {
        stats[id, default: PlayStat()].count += 1
        stats[id]?.lastPlayed = Date()
        save()
    }

    @discardableResult
    func createPlaylist(_ name: String, songIDs: [String] = []) -> Playlist {
        let p = Playlist(name: name, songIDs: songIDs)
        playlists.append(p)
        save()
        return p
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        editPlaylist(id) { $0.name = name }
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    /// 加入歌单，已经在里面的歌不重复加；返回实际新增的数量
    @discardableResult
    func add(_ songIDs: [String], to id: UUID) -> Int {
        var added = 0
        editPlaylist(id) { p in
            for s in songIDs where !p.songIDs.contains(s) { p.songIDs.append(s); added += 1 }
        }
        return added
    }

    func removeFromPlaylist(_ id: UUID, at offsets: IndexSet) {
        editPlaylist(id) { $0.songIDs.remove(atOffsets: offsets) }
    }

    func movePlaylistSongs(_ id: UUID, from: IndexSet, to: Int) {
        editPlaylist(id) { $0.songIDs.move(fromOffsets: from, toOffset: to) }
    }

    private func editPlaylist(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
        save()
    }

    /// 歌曲从曲库消失后，把它在歌单、收藏、统计里的痕迹一起清掉
    func purge(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for i in playlists.indices { playlists[i].songIDs.removeAll { ids.contains($0) } }
        favorites.removeAll { ids.contains($0) }
        for id in ids { stats[id] = nil; onlineCovers[id] = nil }
        onRemove?(ids)
        Task { for id in ids { await ArtworkLoader.shared.forget(id) } }
    }

    func setScanning(_ v: Bool) {
        isScanning = v
    }
}
