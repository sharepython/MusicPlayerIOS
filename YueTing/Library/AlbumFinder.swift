import Foundation

/// 在线认专辑：按歌名、歌手、时长先问 QQ 音乐，搜不到再问 iTunes（台湾区，周杰伦这类歌国区没有），取对得上的那首所在的专辑。
/// 只发送歌名和歌手。同一首歌会出现在原专辑、演唱会、精选集里，所以 Live、精选这类专辑不要（本地歌名或专辑名里写了的除外）；
/// 几张专辑都对得上时，曲库里已经有的那张优先，同一张专辑的歌才能凑到一起
enum AlbumFinder {
    struct Found {
        /// 繁体已经转成简体
        var album: String
        var source: String
    }

    /// known：曲库里已经有别的歌在的专辑（nameKey）
    static func find(_ song: Song, known: Set<String>) async throws -> Found? {
        var busy = false
        for (name, search) in sources {
            for s in LyricsFetcher.variants(song) {
                do {
                    let list = LyricsFetcher.rank(try await search(s), s).filter { usable($0, s) }
                    if let c = list.first(where: { known.contains(LibraryStore.nameKey(clean($0.album!))) }) ?? list.first {
                        return Found(album: Han.simplified(clean(c.album!)), source: name)
                    }
                } catch is LyricsFetcher.Busy {
                    busy = true
                }
            }
        }
        if busy {
            throw LyricsFetcher.Busy()
        }
        return nil
    }

    private static let sources: [(String, (Song) async throws -> [LyricsProvider.Candidate])] = [
        ("QQ 音乐", LyricsProvider.qq.search),
        ("iTunes", itunes),
    ]

    /// 演唱会、精选集、翻唱合集、歌单、综艺节目
    private static let otherAlbum = ["live", "演唱会", "演唱會", "精选", "精選", "合辑", "合輯", "合集", "珍藏", "金曲", "全记录", "全紀錄",
                                     "best", "greatest hits", "hits", "playlist", "串烧", "串燒", "翻唱", "我们的歌", "唱起来", "纯享"]
    /// 综艺节目的「第 4 期」「第三季」
    private static let episode = try? Regex(#"第\s*[0-9一二三四五六七八九十]+\s*[期季]"#)

    /// 去掉商店加的「(Explicit)」「- EP」「- Single」
    static func clean(_ album: String) -> String {
        album.replacingOccurrences(of: #"\s*(\((Explicit|Deluxe Edition)\)|- (EP|Single))\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// 有专辑名、不是 Live / 精选这类专辑、歌手对得上
    private static func usable(_ c: LyricsProvider.Candidate, _ song: Song) -> Bool {
        guard let album = c.album?.trimmingCharacters(in: .whitespaces), !album.isEmpty else { return false }
        return !isOther(c, song) && sameSong(c, song)
    }

    /// Live、精选、综艺这类专辑。只看本地歌名：本地专辑名常是乱写的「精选全纪录」，不能因为它放过精选集
    static func isOther(_ c: LyricsProvider.Candidate, _ song: Song) -> Bool {
        let album = c.album ?? ""
        let own = song.title.lowercased(), theirs = (c.title + " " + album).lowercased()
        let isEpisode = episode.map { album.contains($0) } ?? false
        return otherAlbum.contains { theirs.contains($0) && !own.contains($0) } || isEpisode
    }

    /// 歌手对得上；没有歌手的歌要时长几乎一样
    static func sameSong(_ c: LyricsProvider.Candidate, _ song: Song) -> Bool {
        let mine = LyricsFetcher.artistKeys(song.artist)
        guard !mine.isEmpty else {
            guard let d = c.duration, song.duration > 0 else { return false }
            return abs(d - song.duration) <= 2
        }
        return c.artists.flatMap(LyricsFetcher.artistKeys).contains { a in mine.contains { a.contains($0) || $0.contains(a) } }
    }

    /// [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/)：
    /// 苹果公开的接口，每分钟大约 20 次，每次先等 3 秒。合辑的专辑歌手是 Various Artists，专辑名不要，封面可以用
    static func itunes(_ song: Song) async throws -> [LyricsProvider.Candidate] {
        struct R: Decodable {
            var results: [Item]
        }
        struct Item: Decodable {
            var trackId: Int?, trackName: String?, artistName: String?, collectionName: String?, collectionArtistName: String?
            var trackTimeMillis: Double?, artworkUrl100: String?
        }
        try await Task.sleep(for: .seconds(3))
        let r: R? = try await LyricsFetcher.get("https://itunes.apple.com/search",
            ["term": LyricsFetcher.query(song), "entity": "song", "country": "tw", "limit": "10"])
        return (r?.results ?? []).compactMap { i in
            guard let title = i.trackName else { return nil }
            return LyricsProvider.Candidate(id: String(i.trackId ?? 0), title: title, artists: [i.artistName ?? ""],
                                            duration: i.trackTimeMillis.map { $0 / 1000 },
                                            album: i.collectionArtistName == "Various Artists" ? nil : i.collectionName,
                                            cover: i.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) })
        }
    }
}

/// 繁简：比较时繁简不分；显示时只把繁体转成简体，不反过来转（简转繁一字对多字，「周杰伦」会转成「周傑倫」）。
/// 逐字转，转出来是扩展区生僻字的那个字不转（「马頔」会被转成「马𬱖」）；有日文假名的整段不转，免得改坏日文汉字
enum Han {
    static let toSimplified = StringTransform("Hant-Hans")

    static func simplified(_ s: String) -> String {
        if s.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return s
        }
        return String(s.map { c -> Character in
            let t = String(c).applyingTransform(toSimplified, reverse: false) ?? String(c)
            guard t.count == 1, !t.unicodeScalars.contains(where: { $0.value > 0xFFFF }) else { return c }
            return Character(t)
        })
    }

    static func isSimplified(_ s: String) -> Bool {
        simplified(s) == s
    }
}
