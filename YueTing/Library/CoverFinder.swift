import Foundation

/// 在线补封面：每首歌按自己的歌名、歌手先问 QQ 音乐，搜不到再问 iTunes（台湾区），用对得上的那首的封面；
/// 单曲发行的歌拿到的是单曲封面，在专辑里的拿到专辑封面。几个版本都对得上时，和本地专辑名一样的优先，再是不是 Live、精选的。
/// 都搜不到这首歌、但 QQ 音乐认得这位歌手时，用歌手照片。只发送歌名和歌手
enum CoverFinder {
    struct Found {
        var data: Data
        var source: String
    }

    static func find(_ song: Song) async throws -> Found? {
        var busy = false
        var photo: URL?
        for (name, search) in sources {
            for s in LyricsFetcher.variants(song) {
                do {
                    let raw = try await search(s)
                    if photo == nil {
                        photo = artistPhoto(raw, s)
                    }
                    let list = LyricsFetcher.rank(raw, s).filter { $0.cover != nil && AlbumFinder.sameSong($0, s) }
                    let album = LibraryStore.nameKey(song.album)
                    let pick = list.first { LibraryStore.nameKey(AlbumFinder.clean($0.album ?? "")) == album }
                        ?? list.first { !AlbumFinder.isOther($0, s) } ?? list.first
                    if let pick, let data = try await download(pick.cover!) {
                        return Found(data: data, source: name)
                    }
                } catch is LyricsFetcher.Busy {
                    busy = true
                }
            }
        }
        if let photo, let data = try await download(photo) {
            return Found(data: data, source: "歌手照片")
        }
        if busy {
            throw LyricsFetcher.Busy()
        }
        return nil
    }

    private static let sources: [(String, (Song) async throws -> [LyricsProvider.Candidate])] = [
        ("QQ 音乐", LyricsProvider.qq.search),
        ("iTunes", AlbumFinder.itunes),
    ]

    /// 搜索结果里和本地歌手对得上的那位歌手的照片
    private static func artistPhoto(_ list: [LyricsProvider.Candidate], _ song: Song) -> URL? {
        let mine = LyricsFetcher.artistKeys(song.artist)
        guard !mine.isEmpty else { return nil }
        for c in list {
            for (name, url) in c.artistPhotos {
                let theirs = LyricsFetcher.artistKeys(name)
                if theirs.contains(where: { a in mine.contains { a == $0 } }) {
                    return url
                }
            }
        }
        return nil
    }

    /// 下载图片；404 返回 nil，没网抛 Offline，服务器忙抛 Busy
    private static func download(_ url: URL) async throws -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 YueTing/1.0 (iOS local music player)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return data
            }
            if status < 500 && status != 429 {
                return nil
            }
        } catch let e as URLError where [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(e.code) {
            throw LyricsFetcher.Offline()
        } catch {}
        throw LyricsFetcher.Busy()
    }
}
