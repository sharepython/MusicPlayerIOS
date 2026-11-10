import Foundation

/// 在线补封面：文件里没有封面的歌挨个用 CoverFinder 查，查到的图存在 App 自己的目录里，文件不动，随时可以清掉。
/// 查过的歌下次不再查，中途退出下次接着查
extension LibraryStore {
    /// 还没查过封面的歌
    var coverTodo: [Song] { songs.filter { onlineCovers[$0.id] == nil } }

    /// 有在线查到的封面可以清掉
    var hasOnlineCovers: Bool { onlineCovers.values.contains { !$0.isEmpty } }

    func findCovers() {
        guard coverTask == nil else { return }
        let todo = coverTodo
        guard !todo.isEmpty else { notice = "所有歌都查过封面了"; return }
        coverProgress = (0, todo.count)
        coverTask = Task {
            var found = 0, offline = false
            for (i, song) in todo.enumerated() {
                if Task.isCancelled {
                    break
                }
                if await ArtworkLoader.shared.hasOwn(song) {
                    onlineCovers[song.id] = ""
                } else {
                    do {
                        if let c = try await CoverFinder.find(song), await ArtworkLoader.shared.saveOnline(c.data, for: song.id) {
                            onlineCovers[song.id] = c.source
                            coverRevision += 1
                            found += 1
                        } else {
                            onlineCovers[song.id] = ""
                        }
                    } catch is LyricsFetcher.Offline {
                        offline = true
                        break
                    } catch {
                        // 服务器忙，这首不记，下次再查
                    }
                    save()
                    try? await Task.sleep(for: .milliseconds(300))
                }
                coverProgress = (i + 1, todo.count)
            }
            save()
            coverProgress = nil
            coverTask = nil
            notice = offline ? "没有网络，补封面停下了" : found == 0 ? "没有查到新的封面" : "补好了，\(found) 首歌有了封面"
        }
    }

    func stopFindingCovers() {
        coverTask?.cancel()
    }

    /// 删掉在线查到的封面，查过的记录也清掉
    func clearCovers() {
        stopFindingCovers()
        let ids = onlineCovers.filter { !$0.value.isEmpty }.map(\.key)
        onlineCovers = [:]
        save()
        Task {
            await ArtworkLoader.shared.forgetOnline(ids)
            coverRevision += 1
        }
        notice = "在线封面已清除"
    }
}
