import Foundation

/// 在线整理专辑：专辑页「单曲」里的歌（专辑只有这一首、没有专辑名或专辑名乱写的）挨个用 AlbumFinder 查出所在专辑，
/// 查到的记进 albumFixes 并换到曲库里，文件不动，随时可以还原。查过的歌下次不再查，中途退出下次接着查
extension LibraryStore {
    /// 还没查过的单曲；查过之后标签又被改过的也算没查过
    var albumTodo: [Song] { singles.filter { s in albumFixes[s.id].map { s.album != $0.album } ?? true } }

    /// 有改过的专辑可以还原
    var hasAlbumFixes: Bool { albumFixes.values.contains { $0.album != $0.original } }

    func organizeAlbums() {
        guard albumTask == nil else { return }
        let todo = albumTodo
        guard !todo.isEmpty else { notice = "单曲里的歌都查过了"; return }
        albumProgress = (0, todo.count)
        albumTask = Task {
            var changed = 0, offline = false
            for (i, song) in todo.enumerated() {
                if Task.isCancelled {
                    break
                }
                // 前面刚查到的专辑也算进去，同一张专辑后面的歌能归到一起
                let known = Set(albums.filter { $0.songs.contains { $0.id != song.id } }.map { Self.nameKey($0.id) })
                do {
                    let found = try await AlbumFinder.find(song, known: known)
                    if let found, Self.nameKey(found.album) != Self.nameKey(song.album) {
                        fixAlbum(song.id, to: found.album)
                        changed += 1
                    } else {
                        fixAlbum(song.id, to: song.album)
                    }
                } catch is LyricsFetcher.Offline {
                    offline = true
                    break
                } catch {
                    // 服务器忙，这首不记，下次再查
                }
                albumProgress = (i + 1, todo.count)
                try? await Task.sleep(for: .milliseconds(300))
            }
            albumProgress = nil
            albumTask = nil
            notice = offline ? "没有网络，专辑整理停下了" : changed == 0 ? "没有查到新的专辑" : "整理好了，\(changed) 首歌换了专辑"
        }
    }

    func stopOrganizing() {
        albumTask?.cancel()
    }

    /// 所有歌回到文件里写的专辑，查过的记录也清掉
    func restoreAlbums() {
        stopOrganizing()
        let fixes = albumFixes
        albumFixes = [:]
        setSongs(songs.map { s in
            guard let f = fixes[s.id], s.album == f.album else { return s }
            return Self.withAlbum(s, f.original)
        })
        save()
        notice = "专辑已还原"
    }

    /// 记下查到的专辑并换到曲库里；album 和现在一样表示查过、不用改
    private func fixAlbum(_ id: String, to album: String) {
        guard let s = song(id) else { return }
        let original = albumFixes[id].flatMap { s.album == $0.album ? $0.original : nil } ?? s.album
        albumFixes[id] = AlbumFix(original: original, album: album)
        if s.album != album {
            setSongs(songs.map { $0.id == id ? Self.withAlbum($0, album) : $0 })
        }
        save()
    }

    /// 重读过标签的歌标签还是原来那个时，换回查到的专辑
    func applyFix(_ s: Song) -> Song {
        guard let f = albumFixes[s.id], s.album == f.original, f.album != f.original else { return s }
        return Self.withAlbum(s, f.album)
    }

    private static func withAlbum(_ s: Song, _ album: String) -> Song {
        var s = s
        s.album = album
        s.searchKey = MetadataReader.searchKey([s.title, s.artist, album])
        return s
    }
}
