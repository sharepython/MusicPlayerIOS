import Foundation

/// 按顺序问各个在线歌词来源（见 LyricsProvider.all），挑出歌名、歌手、时长都对得上的那首取歌词
enum LyricsFetcher {
    /// 没网，或者用户没允许小狗音乐使用网络
    struct Offline: Error {
    }
    /// 有来源服务器忙，其他来源又没找到，过一会再查
    struct Busy: Error {
    }

    /// 找到返回歌词（纯音乐时歌词为空）；所有来源都确定没有时返回 nil
    static func fetch(_ song: Song) async throws -> Lyrics? {
        var busy = false
        /// 只有纯文本、不带时间轴的结果先留着，其他来源都没有带时间轴的才用它
        var plain: Lyrics?
        /// 带时间轴但没有逐字时间的结果先留着，再问问能给逐字歌词的来源
        var lineSynced: Lyrics?
        /// 前面来源的翻译，后面逐字歌词没带翻译时配上
        var translation: String?
        for p in LyricsProvider.all {
            if lineSynced != nil, !p.wordTimed {
                continue
            }
            thisProvider: for s in variants(song) {
                do {
                    for c in rank(try await p.search(s), s).prefix(3) {
                        guard let raw = c.instrumental ? LyricsProvider.Raw(lrc: "纯音乐") : try await p.lyrics(c) else { continue }
                        let text = raw.lrc
                        var lines = Lyrics.parse(text)
                        // 「此歌曲为没有填词的纯音乐，请您欣赏」这类一两行的提示
                        if text.contains("纯音乐"), lines.count <= 3, lineSynced == nil {
                            return Lyrics(songID: song.id, source: .instrumental, provider: p.name)
                        }
                        guard lines.count >= 4 else { continue }
                        // 有逐字歌词就用逐字的，行数差太多说明对不上，不用
                        if let w = raw.words, w.count >= max(4, lines.count * 2 / 3) {
                            lines = w
                        }
                        if let t = raw.translation {
                            lines = Lyrics.attach(translation: t, to: lines)
                            if translation == nil {
                                translation = t
                            }
                        }
                        if let t = translation, !lines.contains(where: { $0.translation != nil }) {
                            lines = Lyrics.attach(translation: t, to: lines)
                        }
                        let l = Lyrics(songID: song.id, source: .online, provider: p.name, lines: simplified(lines, for: s))
                        if l.synced, l.wordTimed {
                            return l
                        }
                        if l.synced {
                            if lineSynced == nil {
                                lineSynced = l
                            }
                            // 这个来源的其他候选多半也只有逐行的，换下一个来源
                            break thisProvider
                        }
                        if plain == nil {
                            plain = l
                        }
                    }
                } catch is Busy {
                    busy = true
                }
            }
        }
        if let l = lineSynced ?? plain {
            return l
        }
        if busy {
            throw Busy()
        }
        return nil
    }

    /// 要查的几种歌名歌手：先用标签里的，文件名是「歌手 - 歌名」且和标签不一样时再用文件名的。
    /// 网上下载的歌标签常是乱写的，如歌名「『M』幻听」、歌手「网络歌手」，文件名反而是对的
    static func variants(_ song: Song) -> [Song] {
        let parts = URL(fileURLWithPath: song.id).deletingPathExtension().lastPathComponent.components(separatedBy: " - ")
        guard parts.count == 2 else { return [song] }
        var s = song
        s.artist = parts[0].trimmingCharacters(in: .whitespaces)
        s.title = parts[1].trimmingCharacters(in: .whitespaces)
        guard !s.artist.isEmpty, !s.title.isEmpty, query(s) != query(song) else { return [song] }
        return [song, s]
    }

    /// 挑候选：歌名必须对得上，时长差 8 秒以上多半是别的版本不要；歌手对不上的只在时长几乎一样时才要；
    /// 「(纯音乐)」「(伴奏)」「(DJ 版)」这类版本，本地歌名里没写就不要。
    /// 歌名完全一样、歌手对得上、时长最接近的排前面
    static func rank(_ list: [LyricsProvider.Candidate], _ song: Song) -> [LyricsProvider.Candidate] {
        let titles = titleKeys(song.title)
        let artists = artistKeys(song.artist)
        let own = normalize(song.title)
        return list.compactMap { c -> (LyricsProvider.Candidate, Double)? in
            guard titles.contains(normalize(cleanTitle(c.title))) || titles.contains(normalize(c.title)) else { return nil }
            if otherVersion.contains(where: { normalize(c.title).contains($0) && !own.contains($0) }) {
                return nil
            }
            let diff = song.duration > 0 ? c.duration.map { abs($0 - song.duration) } : nil
            if let diff, diff > 8 {
                return nil
            }
            let artistOK = artists.isEmpty || c.artists.flatMap(artistKeys).contains { a in
                artists.contains { a.contains($0) || $0.contains(a) }
            }
            if !artistOK, (diff ?? 99) > 2 {
                return nil
            }
            return (c, (diff ?? 4) + (artistOK ? 0 : 5) + (normalize(c.title) == own ? 0 : 3))
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    private static let otherVersion = ["纯音乐", "伴奏", "instrumental", "inst.", "offvocal", "karaoke", "dj", "remix", "铃声", "钢琴版", "片段"]

    /// 搜索词：去掉括号后缀的歌名 + 第一位歌手
    static func query(_ song: Song) -> String {
        let artist = song.artist == "未知歌手" ? "" : firstArtist(song.artist)
        return (cleanTitle(song.title) + " " + artist).trimmingCharacters(in: .whitespaces)
    }

    private static let bracketed = try? Regex(#"[(（\[【]([^)）\]】]+)[)）\]】]"#)

    /// 歌名的几种写法：原样、去掉括号、括号里的（如「삐삐 (BBIBBI)」里的 BBIBBI）
    private static func titleKeys(_ s: String) -> Set<String> {
        var keys = [s, cleanTitle(s)]
        if let tag = bracketed {
            keys += s.matches(of: tag).compactMap { $0[1].substring.map(String.init) }
        }
        return Set(keys.map(normalize).filter { !$0.isEmpty })
    }

    /// 每位歌手的原名和去掉括号的名字，如「七叔（叶泽浩）」→ 七叔（叶泽浩）、七叔
    static func artistKeys(_ s: String) -> [String] {
        guard s != "未知歌手" else { return [] }
        return s.components(separatedBy: separators)
            .flatMap { [normalize($0), normalize(cleanTitle($0))] }
            .filter { !$0.isEmpty }
    }

    private static let separators = CharacterSet(charactersIn: "、/&,，;；")

    /// 「周杰伦、Lara梁心颐」「排骨教主/王胖子」只取第一位
    static func firstArtist(_ s: String) -> String {
        let first = s.components(separatedBy: separators).first ?? s
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// 去掉「(Live)」「（深情版）」「[伴奏]」这类括号；整个歌名都在括号里时（如「(笑)」）保持原样
    static func cleanTitle(_ s: String) -> String {
        let t = s.replacingOccurrences(of: #"\s*[(（\[【][^)）\]】]*[)）\]】]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? s : t
    }

    private static let hant = Han.toSimplified

    /// 比较时忽略大小写、空格、繁简、全角半角（「（笑）」和「(笑)」算同一个）。
    /// 先转 NFC：文件名来的韩文是拆开的字母，全角半角转换会把它们变成半角字母，和服务器给的整字对不上
    private static func normalize(_ s: String) -> String {
        let s = s.precomposedStringWithCanonicalMapping
        let t = (s.applyingTransform(hant, reverse: false) ?? s)
        return (t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t).lowercased().filter { !$0.isWhitespace }
    }

    /// 歌词库里很多中文歌是繁体。歌名歌手本身是简体时把歌词也转成简体；有日文假名时不转，免得改坏日文汉字
    private static func simplified(_ lines: [Lyrics.Line], for song: Song) -> [Lyrics.Line] {
        let meta = song.title + song.artist + song.album
        guard meta.applyingTransform(hant, reverse: false) == meta else { return lines }
        let kana = lines.contains { $0.text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) } }
        if kana {
            return lines
        }
        return lines.map {
            var l = $0
            l.text = han(l.text)
            l.words = l.words?.map { Lyrics.Word(time: $0.time, duration: $0.duration, text: han($0.text)) }
            return l
        }
    }

    /// 逐字转简体；繁简转换是一字对一字，不会让逐字时间错位
    private static func han(_ s: String) -> String {
        s.applyingTransform(hant, reverse: false) ?? s
    }

    /// GET 一个 JSON 接口。404 或解析不了返回 nil；没网抛 Offline；服务器忙（5xx / 429）或超时退避重试，仍不行抛 Busy。
    /// [retries] 是每次失败后等几秒再试，最后一个 0 表示不再等
    static func get<T: Decodable>(_ url: String, _ params: [String: String], referer: String? = nil,
                                  retries: [Double] = [1, 3, 0]) async throws -> T? {
        var c = URLComponents(string: url)!
        // 从文件名取的歌名是 NFD（韩文拆成字母），服务器按 NFD 搜不到，统一转成 NFC
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value.precomposedStringWithCanonicalMapping) }
        var req = URLRequest(url: c.url!, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 YueTing/1.0 (iOS local music player)", forHTTPHeaderField: "User-Agent")
        if let referer {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        for delay in retries {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    // 返回的 JSON 字符串里偶尔夹着未转义的控制字符，标准解析器会拒绝；换成空格不影响内容
                    let clean = Data(data.map { $0 < 0x20 ? 0x20 : $0 })
                    return try? JSONDecoder().decode(T.self, from: clean)
                }
                if status < 500 && status != 429 {
                    return nil
                }
            } catch let e as URLError where [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(e.code) {
                // 没网，或者用户没允许小狗音乐联网，重试也没用
                throw Offline()
            } catch {}
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw Busy()
    }
}
