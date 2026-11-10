import AVFoundation
import CryptoKit

/// 一首歌的歌词，按歌曲 id 缓存在 Application Support/Lyrics 里
struct Lyrics: Codable, Hashable {
    enum Source: String, Codable {
        /// 和歌曲同名的 .lrc 文件，或音频文件里内嵌的歌词
        case local
        /// 在线歌词库（网易云、酷狗、QQ 音乐、LRCLIB）
        case online
        /// 本机语音识别生成，可能有错字
        case recognized
        /// 纯音乐，没有歌词
        case instrumental
        /// 哪里都没找到
        case notFound
    }

    struct Line: Codable, Hashable {
        /// 这一行开始的秒数；不带时间轴的歌词为 nil
        var time: Double?
        var text: String
        /// 逐字时间（网易云、酷狗的逐字歌词）；没有时按字数估算每个字什么时候唱
        var words: [Word]?
        /// 外文歌的中文翻译
        var translation: String?
    }

    struct Word: Codable, Hashable {
        /// 开始的秒数
        var time: Double
        /// 唱多久（秒）
        var duration: Double
        var text: String
    }

    var songID: String
    var source: Source
    /// 在线歌词来自哪个来源，如「QQ 音乐」
    var provider: String?
    var lines: [Line] = []

    /// 带时间轴，可以随播放滚动
    var synced: Bool { lines.first?.time != nil }
    /// 带逐字时间
    var wordTimed: Bool { lines.contains { $0.words != nil } }
    /// 带翻译
    var translated: Bool { lines.contains { $0.translation != nil } }

    /// 整体挪 s 秒：正数是歌词提前，每一行、每个字的时间都减去 s
    func shifted(by s: Double) -> Lyrics {
        guard s != 0 else { return self }
        var l = self
        l.lines = lines.map { line in
            var line = line
            line.time = line.time.map { $0 - s }
            line.words = line.words?.map { w in
                var w = w
                w.time -= s
                return w
            }
            return line
        }
        return l
    }

    private static let timeTag = try? Regex(#"^\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)

    /// 解析 LRC：「[01:23.45]歌词」，一行可以带多个时间。没有任何时间标签时按纯文本歌词处理
    static func parse(_ text: String) -> [Line] {
        var timed: [Line] = [], plain: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while let tag = timeTag, let m = rest.prefixMatch(of: tag),
                  let min = m[1].substring.flatMap({ Double($0) }),
                  let sec = m[2].substring.flatMap({ Double($0.replacingOccurrences(of: ":", with: ".")) }) {
                times.append(min * 60 + sec)
                rest = rest[m.range.upperBound...]
            }
            let line = rest.trimmingCharacters(in: .whitespaces)
            if !times.isEmpty {
                // 只有时间没有字的行是间奏标记，不显示
                if !line.isEmpty {
                    timed += times.map { Line(time: $0, text: line) }
                }
            } else if !line.isEmpty, !line.hasPrefix("[") {
                // 「[ar:歌手]」这类元信息行跳过
                plain.append(Line(text: line))
            }
        }
        return timed.isEmpty ? plain : timed.sorted { $0.time! < $1.time! }
    }

    private static let yrcLine = try? Regex(#"^\[(\d+),(\d+)\]"#)
    private static let yrcWord = try? Regex(#"\((\d+),(\d+),-?\d+\)"#)

    /// 解析网易云逐字歌词：「[13850,5480](13850,440,0)心(14290,360,0)之…」，时间都是毫秒。
    /// 开头「{"t":0,"c":[…]}」这类 JSON 行是作词作曲署名，跳过
    static func parseWords(_ text: String) -> [Line] {
        guard let lineTag = yrcLine, let wordTag = yrcWord else {
            return []
        }
        return text.components(separatedBy: .newlines).compactMap { raw -> Line? in
            guard let head = raw.prefixMatch(of: lineTag), let start = head[1].substring.flatMap({ Double($0) }) else { return nil }
            let rest = raw[head.range.upperBound...]
            let tags = rest.matches(of: wordTag)
            var words: [Word] = []
            for (i, m) in tags.enumerated() {
                let end = i + 1 < tags.count ? tags[i + 1].range.lowerBound : rest.endIndex
                guard let t = m[1].substring.flatMap({ Double($0) }), let d = m[2].substring.flatMap({ Double($0) }) else { continue }
                let w = String(rest[m.range.upperBound..<end])
                if !w.isEmpty {
                    words.append(Word(time: t / 1000, duration: d / 1000, text: w))
                }
            }
            // 行尾的空格去掉；行首不动，免得和逐字时间对不上
            let line = String(words.map(\.text).joined().reversed().drop(while: \.isWhitespace).reversed())
            guard !line.isEmpty else { return nil }
            return Line(time: start / 1000, text: line, words: words)
        }
        .sorted { $0.time! < $1.time! }
    }

    private static let krcWord = try? Regex(#"<(\d+),(\d+),-?\d+>"#)

    /// 解析酷狗 KRC（已解密）：「[1707,960]<0,202,0>周<202,608,0>杰…」，字的时间是相对行首的毫秒。
    /// 翻译在「[language:base64 JSON]」里，type 1 是翻译，按顺序一行对一行；type 0 是中文空耳，不用
    static func parseKRC(_ text: String) -> [Line] {
        guard let lineTag = yrcLine, let wordTag = krcWord else {
            return []
        }
        var lines: [Line] = []
        var translation: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespaces))
            if raw.hasPrefix("[language:"), raw.hasSuffix("]") {
                translation = krcTranslation(String(raw.dropFirst(10).dropLast()))
                continue
            }
            guard let head = raw.prefixMatch(of: lineTag), let start = head[1].substring.flatMap({ Double($0) }) else { continue }
            let rest = raw[head.range.upperBound...]
            let tags = rest.matches(of: wordTag)
            var words: [Word] = []
            for (i, m) in tags.enumerated() {
                let end = i + 1 < tags.count ? tags[i + 1].range.lowerBound : rest.endIndex
                guard let t = m[1].substring.flatMap({ Double($0) }), let d = m[2].substring.flatMap({ Double($0) }) else { continue }
                let w = String(rest[m.range.upperBound..<end])
                if !w.isEmpty {
                    words.append(Word(time: (start + t) / 1000, duration: d / 1000, text: w))
                }
            }
            // 翻译按行序对应，空行也要占位，所以先收下再过滤
            let line = String(words.map(\.text).joined().reversed().drop(while: \.isWhitespace).reversed())
            lines.append(Line(time: start / 1000, text: line, words: words))
        }
        for i in lines.indices where translation.indices.contains(i) {
            let t = translation[i].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t != lines[i].text {
                lines[i].translation = t
            }
        }
        return lines.filter { !$0.text.isEmpty }.sorted { $0.time! < $1.time! }
    }

    private static func krcTranslation(_ base64: String) -> [String] {
        struct Lang: Decodable {
            struct C: Decodable {
                var type: Int
                var lyricContent: [[String]]
            }
            var content: [C]
        }
        guard let data = Data(base64Encoded: base64), let lang = try? JSONDecoder().decode(Lang.self, from: data),
              let trans = lang.content.first(where: { $0.type == 1 }) else { return [] }
        return trans.lyricContent.map { $0.joined() }
    }

    /// 把翻译（也是 LRC）按时间配到每一行上。网易云的翻译里「//」表示这一行不用翻
    static func attach(translation: String, to lines: [Line]) -> [Line] {
        let trans = parse(translation).filter { $0.time != nil && $0.text != "//" }
        guard !trans.isEmpty else { return lines }
        return lines.map { line in
            guard let t = line.time,
                  let m = trans.min(by: { abs($0.time! - t) < abs($1.time! - t) }),
                  abs(m.time! - t) < 0.6, m.text != line.text else { return line }
            var l = line
            l.translation = m.text
            return l
        }
    }
}

extension Lyrics.Line {
    /// 播放到 t 秒时这一行唱到第几个字（按 UTF-16 计数，可以带小数），卡拉 OK 式填色用。
    /// 只有带逐字时间的歌词才逐字填色；只有逐行时间的整行一起亮，不去估算每个字什么时候唱
    func progress(at t: Double) -> Double {
        let count = Double(text.utf16.count)
        if let words {
            var done = 0.0
            for w in words {
                let n = Double(w.text.utf16.count)
                if t >= w.time + w.duration {
                    done += n
                    continue
                }
                if t > w.time {
                    done += n * (t - w.time) / max(w.duration, 0.01)
                }
                break
            }
            return done
        }
        return count
    }
}

/// 歌词缓存的读写。每首一个 JSON 文件，按歌曲 id 的哈希命名
enum LyricsDisk {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lyrics")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func file(_ songID: String) -> URL {
        let hash = SHA256.hash(data: Data(songID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(hash + ".json")
    }

    static func loadAll() -> [String: Lyrics] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var all: [String: Lyrics] = [:]
        for f in files {
            if let data = try? Data(contentsOf: f), let l = try? JSONDecoder().decode(Lyrics.self, from: data) {
                all[l.songID] = l
            }
        }
        return all
    }

    static func write(_ l: Lyrics) {
        if let data = try? JSONEncoder().encode(l) {
            try? data.write(to: file(l.songID), options: .atomic)
        }
    }

    static func remove(_ songID: String) {
        try? FileManager.default.removeItem(at: file(songID))
    }

    /// 本地歌词：先找同名 .lrc（UTF-8 或 GBK），再看音频文件里有没有内嵌歌词
    static func local(_ song: Song) async -> [Lyrics.Line]? {
        let lrc = song.fileURL.deletingPathExtension().appendingPathExtension("lrc")
        if let data = try? Data(contentsOf: lrc) {
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb) {
                let lines = Lyrics.parse(text)
                if !lines.isEmpty {
                    return lines
                }
            }
        }
        if let text = try? await AVURLAsset(url: song.fileURL).load(.lyrics) {
            let lines = Lyrics.parse(repairGBK(text))
            // 只有一两行的多半是「xx音乐论坛→网址」这类广告，不算歌词
            if lines.count >= 4 {
                return lines
            }
        }
        return nil
    }

    /// 老 MP3 的内嵌歌词常是 GBK 编码却标成 Latin-1，读出来是「·ãÇéÒô」这样的乱码，按 GBK 重新解码
    private static func repairGBK(_ s: String) -> String {
        guard s.unicodeScalars.allSatisfy({ $0.value <= 0xFF }), s.unicodeScalars.contains(where: { $0.value >= 0x80 }),
              let bytes = s.data(using: .isoLatin1) else { return s }
        return String(data: bytes, encoding: gb) ?? s
    }

    private static let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
