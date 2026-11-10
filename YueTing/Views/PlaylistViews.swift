import SwiftUI

/// 「歌单」Tab：智能列表（我喜欢、最近添加、最近播放、最常播放）+ 自建歌单
struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var creating = false
    @State private var newName = ""

    private let smart: [(PlaylistKind, String, Color)] = [
        (.favorites, "heart.fill", .pink),
        (.recentlyAdded, "clock.badge.plus", .orange),
        (.recentlyPlayed, "clock.arrow.circlepath", .blue),
        (.mostPlayed, "flame.fill", .red),
    ]

    var body: some View {
        List {
            Section {
                ForEach(smart, id: \.0) { kind, icon, color in
                    NavigationLink(value: Route.playlist(kind)) {
                        HStack(spacing: 12) {
                            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(library.title(for: kind))
                                Text("\(library.songs(for: kind).count) 首").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("我的歌单") {
                Button { creating = true } label: {
                    Label("新建歌单", systemImage: "plus")
                }
                ForEach(library.playlists) { p in
                    NavigationLink(value: Route.playlist(.user(p.id))) {
                        HStack(spacing: 12) {
                            ArtworkView(song: library.songs(p.songIDs).first, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).lineLimit(1)
                                Text("\(p.songIDs.count) 首").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { library.deletePlaylist(library.playlists[i].id) }
                }
            }
        }
        .navigationTitle("歌单")
        .alert("新建歌单", isPresented: $creating) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                if !name.isEmpty {
                    library.createPlaylist(name)
                }
            }
        }
    }
}

/// 歌单详情。自建歌单可以拖动排序、左滑移除、重命名、删除
struct PlaylistDetailView: View {
    let kind: PlaylistKind
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editMode: EditMode = .inactive

    private var userID: UUID? {
        if case .user(let id) = kind {
            id
        } else {
            nil
        }
    }

    var body: some View {
        let songs = library.songs(for: kind)
        List {
            if !editMode.isEditing {
                PlayButtons(songs: songs)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                if editMode.isEditing {
                    SongRow(song: song)
                } else {
                    SongRow(song: song)
                        .onTapGesture { player.play(songs, startAt: i) }
                        .songActions(song, onRemove: removeAction(i))
                }
            }
            .onMove(perform: userID.map { id in { library.movePlaylistSongs(id, from: $0, to: $1) } })
            .onDelete(perform: userID.map { id in { library.removeFromPlaylist(id, at: $0) } })
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "music.note.list")
            }
        }
        .navigationTitle(library.title(for: kind))
        .toolbar {
            if let id = userID {
                if editMode.isEditing {
                    Button("完成") { withAnimation { editMode = .inactive } }.bold()
                } else {
                    Menu {
                        Button { withAnimation { editMode = .active } } label: { Label("调整顺序", systemImage: "arrow.up.arrow.down") }
                            .disabled(songs.isEmpty)
                        Button { newName = library.playlist(id)?.name ?? ""; renaming = true } label: { Label("重命名", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删除歌单", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("更多")
                }
            }
        }
        .alert("重命名歌单", isPresented: $renaming) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let id = userID, !name.isEmpty {
                    library.renamePlaylist(id, to: name)
                }
            }
        }
        .confirmationDialog("删除歌单「\(library.title(for: kind))」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) {
                if let id = userID {
                    dismiss()
                    library.deletePlaylist(id)
                }
            }
        } message: {
            Text("歌曲文件不会被删除。")
        }
    }

    private var emptyText: String {
        switch kind {
        case .favorites: "点播放页的 ♡ 收藏喜欢的歌"
        case .recentlyPlayed, .mostPlayed: "还没有播放记录"
        case .recentlyAdded: "还没有歌曲"
        case .user: "长按歌曲选「加入歌单」"
        }
    }

    /// 自建歌单里的歌，菜单里多一项「从歌单移除」
    private func removeAction(_ i: Int) -> (() -> Void)? {
        guard let id = userID else { return nil }
        return { library.removeFromPlaylist(id, at: [i]) }
    }
}
