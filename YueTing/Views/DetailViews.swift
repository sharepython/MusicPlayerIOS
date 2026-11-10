import SwiftUI

/// 专辑详情：大封面 + 播放按钮 + 按曲目号排的歌
struct AlbumDetailView: View {
    let name: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let album = library.album(name) {
            List {
                VStack(spacing: 8) {
                    ArtworkView(song: album.songs.first, size: 220, radius: 14)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    Text(album.id).font(.title3.bold()).multilineTextAlignment(.center)
                    NavigationLink(value: Route.artist(LibraryStore.splitArtists(album.artist)[0])) {
                        Text(album.artist).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(album.artist == "群星")
                    Text("\(album.songs.count) 首 · \(formatTime(album.songs.reduce(0) { $0 + $1.duration }))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                PlayButtons(songs: album.songs)
                ForEach(Array(album.songs.enumerated()), id: \.element.id) { i, song in
                    SongRow(song: song, trackNumber: song.trackNumber)
                        .onTapGesture { player.play(album.songs, startAt: i) }
                        .songActions(song)
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("专辑已不在曲库中", systemImage: "square.stack")
        }
    }
}

/// 歌手详情：TA 的专辑横向滑动 + 全部歌曲
struct ArtistDetailView: View {
    let name: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let artist = library.artist(name) {
            let albums = library.albums.filter { a in artist.songs.contains { library.album($0.album)?.id == a.id } }
            List {
                PlayButtons(songs: artist.songs)
                if albums.count > 1 {
                    Section("专辑") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(albums) { album in
                                    NavigationLink(value: Route.album(album.id)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ArtworkView(song: album.songs.first, size: 120, radius: 10)
                                            Text(album.id).font(.caption).lineLimit(1).frame(width: 120, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section("歌曲 · \(artist.songs.count) 首") {
                    ForEach(Array(artist.songs.enumerated()), id: \.element.id) { i, song in
                        SongRow(song: song)
                            .onTapGesture { player.play(artist.songs, startAt: i) }
                            .songActions(song)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(artist.id)
        } else {
            ContentUnavailableView("歌手已不在曲库中", systemImage: "music.mic")
        }
    }
}

/// 「搜索」Tab：歌名 / 歌手 / 专辑，支持拼音全拼和首字母
struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var query = ""

    var body: some View {
        let r = library.search(query)
        List {
            if !r.artists.isEmpty {
                Section("歌手") {
                    ForEach(r.artists.prefix(5)) { a in
                        NavigationLink(value: Route.artist(a.id)) { Label(a.id, systemImage: "music.mic") }
                    }
                }
            }
            if !r.albums.isEmpty {
                Section("专辑") {
                    ForEach(r.albums.prefix(5)) { a in
                        NavigationLink(value: Route.album(a.id)) {
                            HStack(spacing: 12) {
                                ArtworkView(song: a.songs.first, size: 40)
                                VStack(alignment: .leading) {
                                    Text(a.id).lineLimit(1)
                                    Text(a.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !r.songs.isEmpty {
                Section("歌曲") {
                    ForEach(Array(r.songs.enumerated()), id: \.element.id) { i, song in
                        SongRow(song: song)
                            .onTapGesture { player.play(r.songs, startAt: i) }
                            .songActions(song)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if query.isEmpty {
                suggestions
            } else if r.songs.isEmpty && r.albums.isEmpty && r.artists.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "歌名 / 歌手 / 专辑，支持拼音首字母")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    /// 没输入时：曲库里歌最多的几位歌手，点一下直接搜
    private var suggestions: some View {
        let top = library.artists.sorted { $0.songs.count > $1.songs.count }.prefix(12)
        return ScrollView {
            if top.isEmpty {
                ContentUnavailableView("搜索本地音乐", systemImage: "magnifyingglass", description: Text("导入歌曲后可以按歌名、歌手、专辑搜索"))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("曲库里的歌手").font(.subheadline).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(top) { a in
                            Button(a.id) { query = a.id }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}

/// 按行自动换行排列子视图，用于搜索页的歌手标签
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return (points, maxX, y + rowHeight)
    }
}
