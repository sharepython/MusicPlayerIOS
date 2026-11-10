import Foundation

/// 一个在线歌词来源：先按歌名、歌手搜出候选歌曲，LyricsFetcher 挑出对得上的那首，再取它的歌词。
/// 只发送歌名、歌手和时长，不上传音频。QQ 音乐、网易云、酷狗的接口是网页版和客户端用的非公开接口，没有稳定性保证
struct LyricsProvider {
    struct Candidate {
        var id: String
        var title: String
        var artists: [String]
        /// 秒
        var duration: Double?
        var instrumental = false
        /// 搜索结果里已经带着歌词的来源（LRCLIB）直接放这里
        var lyrics: String?
        /// 取歌词要带的凭证（酷狗的 accesskey）
        var key: String?
        /// 所在专辑，在线整理专辑用（QQ 音乐、iTunes 有）
        var album: String?
        /// 封面图地址和歌手照片地址（歌手名 → 地址），在线补封面用
        var cover: URL?
        var artistPhotos: [String: URL] = [:]
    }

    /// 取到的歌词原文
    struct Raw {
        /// LRC；纯音乐时是含「纯音乐」的提示文字
        var lrc: String
        /// 解析好的逐字歌词（网易云、酷狗），可能已经带着翻译
        var words: [Lyrics.Line]?
        /// 翻译，也是 LRC
        var translation: String?
    }

    var name: String
    /// 能给逐字歌词。前面的来源只有逐行歌词时，还会接着问这类来源
    var wordTimed = false
    var search: (Song) async throws -> [Candidate]
    var lyrics: (Candidate) async throws -> Raw?

    /// 按顺序尝试：网易云、酷狗多数歌带逐字歌词，网易云还常带翻译，放前面；QQ 音乐曲库最全（有周杰伦）；LRCLIB 补外文歌
    static let all = [netease, kugou, qq, lrclib]

    static let qq = LyricsProvider(name: "QQ 音乐", search: { song in
        let r: QQSearch? = try await LyricsFetcher.get("https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
            ["w": LyricsFetcher.query(song), "format": "json", "p": "1", "n": "10", "cr": "1"], referer: "https://y.qq.com/")
        return (r?.data?.song.list ?? []).map {
            Candidate(id: $0.songmid, title: $0.songname, artists: $0.singer.map(\.name), duration: $0.interval, album: $0.albumname,
                      cover: qqPhoto("T002", $0.albummid),
                      artistPhotos: Dictionary($0.singer.compactMap { s in qqPhoto("T001", s.mid).map { (s.name, $0) } }) { a, _ in a })
        }
    }, lyrics: { c in
        struct R: Decodable {
            var lyric: String?
        }
        let r: R? = try await LyricsFetcher.get("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
            ["songmid": c.id, "format": "json"], referer: "https://y.qq.com/")
        // 歌词是 base64 编码的
        return r?.lyric.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }.map { Raw(lrc: $0) }
    })

    static let netease = LyricsProvider(name: "网易云音乐", wordTimed: true, search: { song in
        let r: NESearch? = try await LyricsFetcher.get("https://music.163.com/api/search/get",
            ["s": LyricsFetcher.query(song), "type": "1", "limit": "10"], referer: "https://music.163.com/")
        // 访问太频繁时返回 200，但 code 不是 200
        if let code = r?.code, code != 200 {
            throw LyricsFetcher.Busy()
        }
        return (r?.result?.songs ?? []).map {
            Candidate(id: String($0.id), title: $0.name, artists: $0.artists.map(\.name), duration: $0.duration / 1000)
        }
    }, lyrics: { c in
        // yv、tv 要逐字歌词和翻译，不少歌两样都有
        let r: NELyric? = try await LyricsFetcher.get("https://music.163.com/api/song/lyric/v1",
            ["id": c.id, "lv": "1", "yv": "1", "tv": "1"], referer: "https://music.163.com/")
        // 网易云把没收录歌词的歌也标成 nolyric，是不是纯音乐交给后面的 QQ 音乐判断
        if r?.nolyric == true {
            return nil
        }
        return r?.lrc?.lyric.map { Raw(lrc: $0, words: r?.yrc?.lyric.map(Lyrics.parseWords), translation: r?.tlyric?.lyric) }
    })

    /// 酷狗：歌词搜索接口直接按「歌手 - 歌名」和时长搜，下载的 KRC 是逐字歌词，部分外文歌带翻译。
    /// lyrics.kugou.com 经常断开连接，用同一服务的 krcs.kugou.com
    static let kugou = LyricsProvider(name: "酷狗音乐", wordTimed: true, search: { song in
        let title = LyricsFetcher.cleanTitle(song.title)
        let keyword = song.artist == "未知歌手" ? title : LyricsFetcher.firstArtist(song.artist) + " - " + title
        let r: KGSearch? = try await LyricsFetcher.get("https://krcs.kugou.com/search",
            ["ver": "1", "man": "yes", "client": "mobi", "keyword": keyword, "hash": "",
             "duration": song.duration > 0 ? String(Int(song.duration * 1000)) : ""], retries: kugouRetries)
        return (r?.candidates ?? []).map {
            Candidate(id: $0.id, title: $0.song, artists: [$0.singer], duration: $0.duration.map { $0 / 1000 }, key: $0.accesskey)
        }
    }, lyrics: { c in
        struct R: Decodable {
            var content: String?
        }
        let r: R? = try await LyricsFetcher.get("https://krcs.kugou.com/download",
            ["ver": "1", "client": "pc", "id": c.id, "accesskey": c.key ?? "", "fmt": "krc", "charset": "utf8"], retries: kugouRetries)
        guard let text = r?.content.flatMap(decryptKRC) else { return nil }
        let lines = Lyrics.parseKRC(text)
        guard !lines.isEmpty else { return nil }
        // 逐行的 LRC 由逐字歌词拼出来，给后面统一的行数、纯音乐判断用
        let lrc = lines.map { String(format: "[%02d:%05.2f]", Int($0.time!) / 60, $0.time!.truncatingRemainder(dividingBy: 60)) + $0.text }
        return Raw(lrc: lrc.joined(separator: "\n"), words: lines)
    })

    /// 酷狗经常直接断开连接（约一半请求），断开很快，多试几次
    private static let kugouRetries: [Double] = [0.5, 0.5, 1, 1, 2, 2, 0]

    /// KRC 解密：base64 解码后去掉「krc1」4 字节，按固定密钥异或，再 zlib 解压
    private static func decryptKRC(_ base64: String) -> String? {
        let key: [UInt8] = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
        guard let raw = Data(base64Encoded: base64), raw.count > 6, raw.prefix(4) == Data("krc1".utf8) else { return nil }
        let body = Data(raw.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % key.count] })
        // 带 2 字节 zlib 头，系统的 .zlib 解的是不带头的 deflate
        guard let out = try? (body.dropFirst(2) as NSData).decompressed(using: .zlib) else { return nil }
        return String(data: out as Data, encoding: .utf8)
    }

    static let lrclib = LyricsProvider(name: "LRCLIB", search: { song in
        let list: [LRCLIBRecord]? = try await LyricsFetcher.get("https://lrclib.net/api/search",
            ["track_name": LyricsFetcher.cleanTitle(song.title), "artist_name": LyricsFetcher.firstArtist(song.artist)])
        return (list ?? []).map {
            Candidate(id: "", title: $0.trackName ?? "", artists: [$0.artistName ?? ""], duration: $0.duration,
                      instrumental: $0.instrumental == true, lyrics: $0.syncedLyrics ?? $0.plainLyrics)
        }
    }, lyrics: { $0.lyrics.map { Raw(lrc: $0) } })
}

private struct QQSearch: Decodable {
    struct D: Decodable {
        var song: S
    }
    struct S: Decodable {
        var list: [Item]
    }
    struct Item: Decodable {
        var songmid: String; var songname: String; var interval: Double?; var singer: [Singer]
        var albumname: String?, albummid: String?
    }
    struct Singer: Decodable {
        var name: String
        var mid: String?
    }
    var data: D?
}

/// QQ 音乐的图片地址：T002 是专辑封面，T001 是歌手照片，后面接专辑或歌手的 mid
private func qqPhoto(_ kind: String, _ mid: String?) -> URL? {
    guard let mid, !mid.isEmpty else { return nil }
    return URL(string: "https://y.gtimg.cn/music/photo_new/\(kind)R500x500M000\(mid).jpg")
}

private struct NESearch: Decodable {
    struct R: Decodable {
        var songs: [Item]?
    }
    struct Item: Decodable {
        var id: Int
        var name: String
        var artists: [Name]
        var duration: Double
    }
    var code: Int?
    var result: R?
}

private struct NELyric: Decodable {
    struct L: Decodable {
        var lyric: String?
    }
    var lrc: L?
    var yrc: L?
    var tlyric: L?
    var nolyric: Bool?
}

private struct KGSearch: Decodable {
    struct Item: Decodable {
        var id: String
        var accesskey: String
        var song: String
        var singer: String
        var duration: Double?
    }
    var candidates: [Item]?
}

private struct LRCLIBRecord: Decodable {
    var trackName: String?
    var artistName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?
}

private struct Name: Decodable {
    var name: String
}
