import SwiftUI

/// 歌曲封面；没有封面时是按歌名配色的渐变 + 音符
struct ArtworkView: View {
    let song: Song?
    var size: CGFloat
    var radius: CGFloat = 6
    @State private var image: UIImage?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: Self.placeholderColors(song), startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // 在线补到封面后跟着换
        .task(id: "\(library.coverRevision)|\(song?.id ?? "")") {
            guard let song else { image = nil; return }
            image = ArtworkLoader.shared.cached(song.id)
            if image == nil {
                image = await ArtworkLoader.shared.image(for: song)
            }
        }
    }

    /// 同一张专辑每次颜色一样（不用 hashValue，它每次启动都会变），不同专辑颜色错开
    static func placeholderColors(_ song: Song?) -> [Color] {
        let sum = (song?.album ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let h = Double(sum % 360) / 360
        return [Color(hue: h, saturation: 0.45, brightness: 0.85), Color(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.6)]
    }
}

/// 列表里的一行歌曲：封面、歌名、歌手 · 专辑；正在播放的歌名高亮并带波形图标
struct SongRow: View {
    let song: Song
    /// 专辑页里不需要再显示专辑名和封面，改成显示曲目号
    var trackNumber: Int?
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let current = player.currentSong?.id == song.id
        HStack(spacing: 12) {
            if let trackNumber {
                Text(trackNumber > 0 ? "\(trackNumber)" : "–")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
            } else {
                ArtworkView(song: song, size: 46)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).lineLimit(1).foregroundStyle(current ? Color.accentColor : .primary)
                Text(trackNumber == nil ? "\(song.artist) · \(song.album)" : song.artist)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if library.isFavorite(song.id) {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            }
            if current {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 歌曲的长按菜单 / 左滑操作；[onRemove] 不为空时多出一项「从歌单移除」
struct SongActions: ViewModifier {
    let song: Song
    var onRemove: (() -> Void)?
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var addingToPlaylist = false
    @State private var confirmDelete = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { player.playNext([song]) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { player.addToQueue([song]) } label: { Label("加入播放队列", systemImage: "text.badge.plus") }
                Button { addingToPlaylist = true } label: { Label("加入歌单…", systemImage: "music.note.list") }
                Button { library.toggleFavorite(song.id) } label: {
                    library.isFavorite(song.id) ? Label("取消喜欢", systemImage: "heart.slash") : Label("喜欢", systemImage: "heart")
                }
                Divider()
                if library.album(song.album) != nil {
                    NavigationLink(value: Route.album(song.album)) { Label("查看专辑", systemImage: "square.stack") }
                }
                NavigationLink(value: Route.artist(LibraryStore.splitArtists(song.artist)[0])) { Label("查看歌手", systemImage: "music.mic") }
                Divider()
                if let onRemove {
                    Button(role: .destructive, action: onRemove) { Label("从歌单移除", systemImage: "minus.circle") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("删除歌曲文件", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                Button { player.playNext([song]) } label: { Label("下一首", systemImage: "text.line.first.and.arrowtriangle.forward") }.tint(.indigo)
                Button { player.addToQueue([song]) } label: { Label("加入队列", systemImage: "text.badge.plus") }.tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                if let onRemove {
                    Button(role: .destructive, action: onRemove) { Label("移除", systemImage: "minus.circle") }
                }
                Button { library.toggleFavorite(song.id) } label: {
                    Label("喜欢", systemImage: library.isFavorite(song.id) ? "heart.slash" : "heart")
                }.tint(.pink)
            }
            .sheet(isPresented: $addingToPlaylist) { AddToPlaylistSheet(songIDs: [song.id]) }
            .confirmationDialog("删除「\(song.title)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { library.deleteSongs([song.id]) }
            } message: {
                Text("会从手机上删除这个音频文件，并从所有歌单中移除。")
            }
    }
}

extension View {
    func songActions(_ song: Song, onRemove: (() -> Void)? = nil) -> some View {
        modifier(SongActions(song: song, onRemove: onRemove))
    }
}
