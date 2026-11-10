import Foundation

/// 曲库与磁盘文件的同步：扫描 Documents、从外部导入、删除
extension LibraryStore {
    /// 扫描 Documents：新文件读标签入库，消失的文件移出曲库。返回新增的歌曲数。
    /// 启动、回到前台、导入后都会调用；同时只跑一个，后来的排队
    @discardableResult
    func sync() async -> Int {
        let previous = scanTask
        let task = Task { () -> Int in
            _ = await previous?.value
            return await self.scanOnce()
        }
        scanTask = task
        return await task.value
    }

    private func scanOnce() async -> Int {
        setScanning(true)
        defer { setScanning(false) }
        let paths = await Task.detached { LibraryFiles.scanDocuments() }.value
        let known = Set(songsByID.keys)
        let added = paths.subtracting(known)
        let removed = known.subtracting(paths)
        // 识别规则改过时，已入库的歌也重读一遍标签，加入时间不变
        let reread = metadataVersion < MetadataReader.version ? paths.intersection(known) : []
        guard !added.isEmpty || !removed.isEmpty || !reread.isEmpty else { return 0 }
        let now = Date()
        let jobs = added.union(reread).sorted().map { ($0, songsByID[$0]?.addedAt ?? now) }
        // 最多 6 个文件同时读标签，大批量导入时既快又不占满 CPU
        let newSongs: [Song] = await withTaskGroup(of: Song.self) { group in
            var result: [Song] = []
            var pending = jobs.makeIterator()
            for _ in 0..<6 {
                if let (p, d) = pending.next() {
                    group.addTask { await MetadataReader.read(p, addedAt: d) }
                }
            }
            while let s = await group.next() {
                result.append(s)
                if let (p, d) = pending.next() {
                    group.addTask { await MetadataReader.read(p, addedAt: d) }
                }
            }
            return result
        }
        // 读标签期间曲库可能又变了，以当前 songs 为准合并
        let fresh = Dictionary(newSongs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        setSongs(songs.filter { !removed.contains($0.id) }.map { fresh[$0.id] ?? $0 } + newSongs.filter { songsByID[$0.id] == nil })
        metadataVersion = MetadataReader.version
        purge(removed)
        save()
        return newSongs.filter { added.contains($0.id) }.count
    }

    /// 从「文件」选择器或「用小狗音乐打开」导入：拷进 Documents 后扫描。返回这些文件在曲库里的 id
    @discardableResult
    func importFiles(_ urls: [URL]) async -> [String] {
        let ids = await Task.detached { LibraryFiles.copyIn(urls) }.value
        let added = await sync()
        notice = ids.isEmpty ? "没有找到可播放的音频文件" : added > 0 ? "已导入 \(added) 首" : "这些歌已经在曲库里了"
        return ids
    }

    /// 删除歌曲文件，并从歌单、收藏、播放队列里移除
    func deleteSongs(_ ids: Set<String>) {
        for id in ids { try? FileManager.default.removeItem(at: LibraryPaths.documents.appendingPathComponent(id)) }
        setSongs(songs.filter { !ids.contains($0.id) })
        purge(ids)
        save()
        notice = "已删除 \(ids.count) 首"
    }
}

/// 纯文件操作，在后台线程执行
enum LibraryFiles {
    /// Documents 的真实路径（带末尾斜杠），用来把绝对路径换成相对路径
    static var root: String { LibraryPaths.documents.resolvingSymlinksInPath().path + "/" }

    /// 列出 Documents 下所有音频文件的相对路径（含子文件夹，跳过隐藏文件）
    static func scanDocuments() -> Set<String> {
        Set(audioFiles(in: LibraryPaths.documents).compactMap(relativePath))
    }

    /// 文件在 Documents 里时返回相对路径，否则 nil
    static func relativePath(_ url: URL) -> String? {
        let p = url.resolvingSymlinksInPath().path
        let r = root
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : nil
    }

    static func audioFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in e where MetadataReader.isAudio(url) { out.append(url) }
        return out
    }

    /// 把外部文件或文件夹里的音频拷进 Documents 根目录，返回它们的相对路径。
    /// 本来就在 Documents 里的直接用；同名同大小视为同一首，不重复拷
    static func copyIn(_ urls: [URL]) -> [String] {
        var out: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let files = isDir ? audioFiles(in: url) : (MetadataReader.isAudio(url) ? [url] : [])
            for f in files {
                if let rel = relativePath(f) {
                    out.append(rel)
                    continue
                }
                if let name = copy(f) {
                    out.append(name)
                }
            }
        }
        return out
    }

    private static func copy(_ src: URL) -> String? {
        let fm = FileManager.default
        let ext = src.pathExtension
        let base = src.deletingPathExtension().lastPathComponent
        let size = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        for n in 1...999 {
            let name = n == 1 ? src.lastPathComponent : "\(base) \(n).\(ext)"
            let dest = LibraryPaths.documents.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) {
                if (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) == size {
                    return name
                }
                continue
            }
            return (try? fm.copyItem(at: src, to: dest)) != nil ? name : nil
        }
        return nil
    }
}
