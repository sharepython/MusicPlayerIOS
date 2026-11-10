import SwiftUI

/// 把歌加入歌单：列出已有歌单，也可以就地新建
struct AddToPlaylistSheet: View {
    let songIDs: [String]
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button { creating = true } label: { Label("新建歌单", systemImage: "plus") }
                ForEach(library.playlists) { p in
                    Button {
                        let n = library.add(songIDs, to: p.id)
                        library.notice = n > 0 ? "已加入「\(p.name)」" : "已经在「\(p.name)」里了"
                        dismiss()
                    } label: {
                        HStack {
                            ArtworkView(song: library.songs(p.songIDs).first, size: 40)
                            VStack(alignment: .leading) {
                                Text(p.name).foregroundStyle(.primary)
                                Text("\(p.songIDs.count) 首").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(songIDs.count > 1 ? "加入歌单（\(songIDs.count) 首）" : "加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .alert("新建歌单", isPresented: $creating) {
                TextField("歌单名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    newName = ""
                    guard !name.isEmpty else { return }
                    library.createPlaylist(name, songIDs: songIDs)
                    library.notice = "已加入「\(name)」"
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 列表顶部的「播放全部 / 随机播放」两个按钮
struct PlayButtons: View {
    let songs: [Song]
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Button { player.play(songs, startAt: 0, shuffle: false) } label: {
                Label("播放", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            Button { player.play(songs, shuffle: true) } label: {
                Label("随机播放", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(songs.isEmpty)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

/// 底部迷你播放条：封面、歌名、歌手、播放/暂停、下一首，底边一条进度线
struct MiniPlayer: View {
    let onOpen: () -> Void
    @Environment(PlayerController.self) private var player

    var body: some View {
        let song = player.currentSong
        HStack(spacing: 12) {
            ArtworkView(song: song, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(song?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(song?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 40, height: 40)
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 40)
            }
            .accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { g in
                Capsule().fill(Color.accentColor)
                    .frame(width: g.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        // 作为容器暴露给自动化测试，里面的按钮仍可单独访问
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniPlayer")
        .padding(.horizontal, 8).padding(.bottom, 4)
    }

    private var progress: CGFloat {
        player.duration > 0 ? CGFloat(min(max(player.position / player.duration, 0), 1)) : 0
    }
}
