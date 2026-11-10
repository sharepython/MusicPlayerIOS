import SwiftUI

/// 「歌曲」Tab：全部歌曲，可切换排序；点「选择」进入多选，批量加歌单 / 加队列 / 删除
struct SongsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @AppStorage("songSort") private var sort: SongSort = .title
    @State private var showSettings = false
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var addingToPlaylist = false
    @State private var confirmDelete = false

    var body: some View {
        let songs = library.sorted(sort)
        Group {
            if library.songs.isEmpty {
                EmptyLibraryView()
            } else {
                let runs = indexKey.map { letterRuns(songs, key: $0) } ?? [LetterRun(id: 0, letter: "", items: Array(songs.enumerated()))]
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                        if !editMode.isEditing {
                            PlayButtons(songs: songs)
                        }
                        ForEach(runs) { run in
                            Section {
                                ForEach(run.items, id: \.element.id) { i, song in
                                    // 多选时点行是勾选，不能被点击播放拦掉
                                    if editMode.isEditing {
                                        SongRow(song: song)
                                    } else {
                                        SongRow(song: song)
                                            .onTapGesture { player.play(songs, startAt: i) }
                                            .songActions(song)
                                    }
                                }
                            } header: {
                                if !run.letter.isEmpty {
                                    Text(run.letter)
                                }
                            }
                        }
                        Text("\(songs.count) 首歌曲").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                            .accessibilityIdentifier("songCount")
                    }
                    .listStyle(.plain)
                    .refreshable { await library.sync() }
                    .sectionIndex(indexKey == nil ? [] : unique(runs.map(\.letter))) { l in
                        if let run = runs.first(where: { $0.letter == l }) {
                            proxy.scrollTo(run.items[0].element.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationTitle("歌曲")
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.count == songs.count ? "全不选" : "全选") {
                        selection = selection.count == songs.count ? [] : Set(songs.map(\.id))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { endEditing() }.bold()
                }
                ToolbarItemGroup(placement: .bottomBar) { selectionActions(songs).disabled(selection.isEmpty) }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(SongSort.allCases) { Text($0.label).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("排序")
                    if !library.songs.isEmpty {
                        Button("选择") { withAnimation { editMode = .active } }
                    }
                    ImportButton()
                }
            }
        }
        .sheet(isPresented: $addingToPlaylist, onDismiss: endEditing) { AddToPlaylistSheet(songIDs: selectedIDs(songs)) }
        .confirmationDialog("删除选中的 \(selection.count) 首歌？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { library.deleteSongs(selection); endEditing() }
        } message: {
            Text("会从手机上删除这些音频文件，并从所有歌单中移除。")
        }
    }

    @ViewBuilder
    private func selectionActions(_ songs: [Song]) -> some View {
        let picked = library.songs(selectedIDs(songs))
        Button { player.playNext(picked); endEditing() } label: { Image(systemName: "text.line.first.and.arrowtriangle.forward") }
            .accessibilityLabel("下一首播放")
        Spacer()
        Button { player.addToQueue(picked); endEditing() } label: { Image(systemName: "text.badge.plus") }
            .accessibilityLabel("加入播放队列")
        Spacer()
        Button { addingToPlaylist = true } label: { Image(systemName: "music.note.list") }
            .accessibilityLabel("加入歌单")
        Spacer()
        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
            .accessibilityLabel("删除")
    }

    /// 按歌名、歌手、专辑排时右边有首字母索引，按最近添加排时没有
    private var indexKey: ((Song) -> String)? {
        switch sort {
        case .title: { $0.sortKey }
        case .artist: { MetadataReader.pinyin($0.artist) }
        case .album: { [library] in library.album($0.album)?.sortKey ?? "#" }
        case .added: nil
        }
    }

    /// 选中项按当前列表顺序排，批量加入时顺序和看到的一致
    private func selectedIDs(_ songs: [Song]) -> [String] {
        songs.map(\.id).filter(selection.contains)
    }

    private func endEditing() {
        withAnimation { editMode = .inactive }
        selection = []
    }
}

/// 去掉重复，保留第一次出现的顺序
func unique(_ list: [String]) -> [String] {
    var seen: Set<String> = []
    return list.filter { seen.insert($0).inserted }
}

/// 「专辑」Tab：两列封面网格，只放有两首以上的专辑；只有一首的专辑和没有专辑名的歌收进最后一格「单曲」
struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = library.albums.filter { $0.songs.count > 1 }
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(albums) { album in
                    NavigationLink(value: Route.album(album.id)) {
                        cell(Text(album.id), "\(album.artist) · \(album.songs.count) 首") {
                            GeometryReader { g in ArtworkView(song: album.songs.first, size: g.size.width, radius: 10) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !library.singles.isEmpty {
                    NavigationLink(value: Route.singles) {
                        cell(Text("单曲"), "\(library.singles.count) 首 · 专辑里只有一首的歌") {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.gradient)
                                .overlay { Image(systemName: "music.note.list").font(.system(size: 44, weight: .medium)).foregroundStyle(.white) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("singles")
                }
            }
            .padding(16)
        }
        .overlay {
            if library.songs.isEmpty {
                EmptyLibraryView()
            }
        }
        .navigationTitle("专辑")
        .toolbar { ImportButton() }
        .refreshable { await library.sync() }
    }
}

/// 「歌手」Tab：按拼音首字母分段，右边首字母索引
struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let runs = letterRuns(library.artists) { $0.sortKey }
        ScrollViewReader { proxy in
            List {
                ForEach(runs) { run in
                    Section(run.letter) {
                        ForEach(run.items, id: \.element.id) { _, artist in
                            NavigationLink(value: Route.artist(artist.id)) {
                                HStack(spacing: 12) {
                                    ArtworkView(song: artist.songs.first, size: 46, radius: 23)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(artist.id).lineLimit(1)
                                        Text("\(artist.songs.count) 首").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .sectionIndex(unique(runs.map(\.letter))) { l in
                if let run = runs.first(where: { $0.letter == l }) {
                    proxy.scrollTo(run.items[0].element.id, anchor: .top)
                }
            }
        }
        .overlay {
            if library.songs.isEmpty {
                EmptyLibraryView()
            }
        }
        .navigationTitle("歌手")
        .toolbar { ImportButton() }
        .refreshable { await library.sync() }
    }
}

extension AlbumsView {
    /// 网格里的一格：方形封面，下面专辑名和一行小字
    private func cell(_ title: Text, _ detail: String, @ViewBuilder cover: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            cover().aspectRatio(1, contentMode: .fit)
            title.font(.subheadline.weight(.medium)).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// 专辑页最后一格「单曲」点进来：只有一首的专辑和没有专辑名的歌，按歌手排
struct SinglesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        let songs = library.singles
        List {
            PlayButtons(songs: songs)
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                SongRow(song: song)
                    .onTapGesture { player.play(songs, startAt: i) }
                    .songActions(song)
            }
        }
        .listStyle(.plain)
        .navigationTitle("单曲 · \(songs.count) 首")
        .navigationBarTitleDisplayMode(.inline)
    }
}
