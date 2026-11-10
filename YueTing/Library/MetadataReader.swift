import AVFoundation
import CryptoKit
import UIKit

/// 读取音频文件的标签（歌名、歌手、专辑、曲目号、时长、封面），以及中文拼音转换
enum MetadataReader {
    /// AVFoundation 能播放的音频扩展名；ogg / ape / wma 系统不支持，不收录
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "caf", "flac"]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// 读一首歌的信息；读到封面时顺带缓存缩略图。在后台线程执行
    static func read(_ relativePath: String, addedAt: Date) async -> Song {
        let url = LibraryPaths.documents.appendingPathComponent(relativePath)
        let asset = AVURLAsset(url: url)
        var title: String?, artist: String?, album: String?, artwork: Data?
        var track = 0
        var duration = 0.0
        if let d = try? await asset.load(.duration), d.isNumeric {
            duration = d.seconds
        }
        for item in (try? await asset.load(.commonMetadata)) ?? [] {
            switch item.commonKey {
            case .commonKeyTitle?: title = await string(item)
            case .commonKeyArtist?: artist = await string(item)
            case .commonKeyAlbumName?: album = await string(item)
            case .commonKeyArtwork?: artwork = try? await item.load(.dataValue)
            default: break
            }
        }
        // 曲目号不在 common 里，MP3 是 ID3 的 TRCK（"3/12"），M4A 是 iTunes 的 trkn（二进制）
        for item in (try? await asset.load(.metadata)) ?? []
        where item.identifier == .id3MetadataTrackNumber || item.identifier == .iTunesMetadataTrackNumber {
            if let s = try? await item.load(.stringValue) {
                track = Int(s.split(separator: "/").first ?? "") ?? 0
            } else if let d = try? await item.load(.dataValue), d.count >= 4 {
                track = Int(d[d.startIndex + 2]) << 8 | Int(d[d.startIndex + 3])
            }
        }
        // 文件名是「歌手 - 歌名.mp3」时，用它补上缺的标签；标签和文件名对不上时以文件名为准。
        // 网上下载的歌标签常是乱写的，如歌手「网络歌手」「华语群星」、歌名「『M』幻听」「**的青春」或乱码
        let base = url.deletingPathExtension().lastPathComponent
        if let (fa, ft) = splitFileName(base) {
            let wrong = title.map { !sameTitle($0, ft) } ?? false || artist.map { !sameArtist($0, fa) } ?? false
            if wrong || title == nil {
                title = ft
            }
            if wrong || artist == nil {
                artist = fa
            }
        } else if title == nil {
            title = base
        }
        if let artwork {
            saveArtwork(artwork, to: artworkFile(relativePath))
        }
        let t = title ?? base, a = artist ?? "未知歌手", al = album ?? "未知专辑"
        return Song(id: relativePath, title: t, artist: a, album: al, duration: duration, trackNumber: track,
                    addedAt: addedAt, searchKey: searchKey([t, a, al]), sortKey: pinyin(t))
    }

    /// 只取封面原始数据，缓存被系统清掉后重新提取用
    static func artworkData(_ url: URL) async -> Data? {
        for item in (try? await AVURLAsset(url: url).load(.commonMetadata)) ?? [] where item.commonKey == .commonKeyArtwork {
            if let d = try? await item.load(.dataValue) {
                return d
            }
        }
        return nil
    }

    /// 封面缓存文件，按歌曲 id 的哈希命名；online 是在线查到的封面
    static func artworkFile(_ songID: String, online: Bool = false) -> URL {
        let hash = SHA256.hash(data: Data(songID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return (online ? LibraryPaths.onlineArtwork : LibraryPaths.artwork).appendingPathComponent(hash + ".jpg")
    }

    /// 缩到最长边 600px 存成 JPEG，返回缩好的图
    @discardableResult
    static func saveArtwork(_ data: Data, to file: URL) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 600 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.jpegData(compressionQuality: 0.85)?.write(to: file, options: .atomic)
        return small
    }

    /// 取字符串标签并修正乱码
    private static func string(_ item: AVMetadataItem) async -> String? {
        guard let s = try? await item.load(.stringValue) else { return nil }
        let fixed = fixMojibake(s).trimmingCharacters(in: .whitespacesAndNewlines)
        return fixed.isEmpty ? nil : fixed
    }

    /// 很多国内 MP3 的 ID3 标签实际是 GBK 编码却标成了 Latin-1，读出来是「ÖÜ½ÜÂ×」这种乱码。
    /// 所有字符都落在 Latin-1 范围且含高位字符时，按 GB18030 重新解码一次
    static func fixMojibake(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard scalars.allSatisfy({ $0.value < 256 }), scalars.contains(where: { $0.value >= 0x80 }) else { return s }
        let bytes = Data(scalars.map { UInt8($0.value) })
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: bytes, encoding: gb) ?? s
    }

    /// 标签识别规则的版本，改了规则就加一，已入库的歌会重读一遍标签
    static let version = 2

    /// 文件名「歌手 - 歌名」拆成两半；「01 - 晴天」这种前面是曲目号的不算（只看阿拉伯数字，「贰佰」这类歌手名不算曲目号）
    private static func splitFileName(_ base: String) -> (artist: String, title: String)? {
        let parts = base.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts[0].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return (parts[0], parts[1])
    }

    private static let bracket = try? Regex(#"\s*[(（\[【]([^)）\]】]*)[)）\]】]\s*"#)

    /// 去掉括号后一样（「不要說話(國)」和「不要说话」），或者一边是另一边括号里的写法（「Red Bean(红豆)」和「红豆」）
    private static func sameTitle(_ a: String, _ b: String) -> Bool {
        guard let tag = bracket else {
            return compareKey(a) == compareKey(b)
        }

        func stripped(_ s: String) -> String {
            let t = compareKey(s.replacing(tag, with: ""))
            return t.isEmpty ? compareKey(s) : t
        }

        func keys(_ s: String) -> Set<String> {
            Set([stripped(s)] + s.matches(of: tag).compactMap { $0[1].substring.map { compareKey(String($0)) } })
        }
        return keys(b).contains(stripped(a)) || keys(a).contains(stripped(b))
    }

    /// 至少有一位歌手对得上，如「88rising/Stephanie Poetri/王嘉尔」和「Stephanie Poetri、王嘉尔」
    private static func sameArtist(_ a: String, _ b: String) -> Bool {
        func split(_ s: String) -> [String] {
            s.components(separatedBy: CharacterSet(charactersIn: "/、&＆,，;；")).map(compareKey).filter { !$0.isEmpty }
        }
        let others = split(b)
        return split(a).contains { x in others.contains { x.contains($0) || $0.contains(x) } }
    }

    private static let hant = StringTransform("Hant-Hans")

    /// 比较用：忽略大小写、空格、繁简、全角半角
    private static func compareKey(_ s: String) -> String {
        let t = s.applyingTransform(hant, reverse: false) ?? s
        return (t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t).lowercased().filter { !$0.isWhitespace }
    }

    /// 中文转小写拼音，字与字之间有空格：「周杰伦」→「zhou jie lun」
    static func pinyin(_ s: String) -> String {
        let m = NSMutableString(string: s) as CFMutableString
        CFStringTransform(m, nil, kCFStringTransformToLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
        return (m as String).lowercased()
    }

    /// 每个字段拼出「原文|全拼|首字母」，搜索时直接做包含匹配
    static func searchKey(_ fields: [String]) -> String {
        fields.map { s in
            let py = pinyin(s)
            let initials = py.split(separator: " ").compactMap(\.first).map(String.init).joined()
            return [s.lowercased(), py.replacingOccurrences(of: " ", with: ""), initials].joined(separator: "|")
        }.joined(separator: "|")
    }
}

/// 封面加载：内存缓存 → 磁盘缩略图 → 从音频文件重新提取 → 在线查到的封面
actor ArtworkLoader {
    static let shared = ArtworkLoader()
    nonisolated private let memory = NSCache<NSString, UIImage>()
    /// 本次运行里确认没有封面的歌，避免反复读文件
    private var missing: Set<String> = []

    /// 只查内存，界面首次绘制时用，避免先闪一下占位图
    nonisolated func cached(_ songID: String) -> UIImage? {
        memory.object(forKey: songID as NSString)
    }

    func image(for song: Song) async -> UIImage? {
        if let img = cached(song.id) {
            return img
        }
        if missing.contains(song.id) {
            return nil
        }
        let file = MetadataReader.artworkFile(song.id)
        var image = UIImage(contentsOfFile: file.path)
        if image == nil, let data = await MetadataReader.artworkData(song.fileURL) {
            image = MetadataReader.saveArtwork(data, to: file)
        }
        if image == nil {
            image = UIImage(contentsOfFile: MetadataReader.artworkFile(song.id, online: true).path)
        }
        if let image {
            memory.setObject(image, forKey: song.id as NSString)
        } else {
            missing.insert(song.id)
        }
        return image
    }

    /// 文件里有没有封面，在线补封面时只补没有的
    func hasOwn(_ song: Song) async -> Bool {
        if FileManager.default.fileExists(atPath: MetadataReader.artworkFile(song.id).path) {
            return true
        }
        guard let data = await MetadataReader.artworkData(song.fileURL) else { return false }
        return MetadataReader.saveArtwork(data, to: MetadataReader.artworkFile(song.id)) != nil
    }

    /// 存下在线查到的封面；图片坏了返回 false
    func saveOnline(_ data: Data, for songID: String) -> Bool {
        guard let image = MetadataReader.saveArtwork(data, to: MetadataReader.artworkFile(songID, online: true)) else { return false }
        memory.setObject(image, forKey: songID as NSString)
        missing.remove(songID)
        return true
    }

    /// 删掉在线查到的封面
    func forgetOnline(_ ids: [String]) {
        for id in ids {
            memory.removeObject(forKey: id as NSString)
            try? FileManager.default.removeItem(at: MetadataReader.artworkFile(id, online: true))
        }
    }

    /// 歌曲被删除时清掉它的缓存
    func forget(_ songID: String) {
        memory.removeObject(forKey: songID as NSString)
        missing.remove(songID)
        try? FileManager.default.removeItem(at: MetadataReader.artworkFile(songID))
        try? FileManager.default.removeItem(at: MetadataReader.artworkFile(songID, online: true))
    }
}
