import SwiftUI
import UniformTypeIdentifiers

/// 五个 Tab，每个 Tab 底部都悬着迷你播放条；点它展开全屏播放页
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(SystemLyrics.self) private var system
    @State private var showPlayer = false
    /// 迷你播放条的高度，每页底部空出这么多，列表最后几行能滚到它上面
    @State private var miniHeight: CGFloat = 0

    var body: some View {
        TabView {
            tab(SongsView(), "歌曲", "music.note")
            tab(AlbumsView(), "专辑", "square.stack")
            tab(ArtistsView(), "歌手", "music.mic")
            tab(PlaylistsView(), "歌单", "music.note.list")
            tab(SearchView(), "搜索", "magnifyingglass")
        }
        .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
        .overlay(alignment: .top) { NoticeBanner() }
        .background(alignment: .topLeading) {
            DesktopLyricsHost(desktop: system.desktop).frame(width: 280, height: 20).allowsHitTesting(false)
        }
    }

    private func tab(_ content: some View, _ title: String, _ icon: String) -> some View {
        NavigationStack {
            content
                .modifier(BottomRoom(height: player.currentSong == nil ? 0 : miniHeight))
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .album(let name): AlbumDetailView(name: name)
                        case .artist(let name): ArtistDetailView(name: name)
                        case .playlist(let kind): PlaylistDetailView(kind: kind)
                        case .singles: SinglesView()
                        }
                    }
                    .modifier(BottomRoom(height: player.currentSong == nil ? 0 : miniHeight))
                }
        }
        // 浮在 NavigationStack 上面，进到详情页也一直在。
        // 在外层用 safeAreaInset 让不出位置：导航里的列表收不到外面的安全区，最后几行会被挡住，所以每页自己在底部空出来
        .overlay(alignment: .bottom) {
            if player.currentSong != nil {
                MiniPlayer { showPlayer = true }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { miniHeight = $0 }
            }
        }
        .tabItem { Label(title, systemImage: icon) }
    }
}

/// 页面底部空出一段给迷你播放条，列表可以滚过它
private struct BottomRoom: ViewModifier {
    var height: CGFloat

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if height > 0 {
                Color.clear.frame(height: height).allowsHitTesting(false)
            }
        }
    }
}

/// 顶部浮出的一句提示，2 秒后自动消失
private struct NoticeBanner: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let text = library.notice {
            Text(text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { library.notice = nil }
                }
        }
    }
}

/// 导入按钮：从「文件」里选歌曲或整个文件夹，拷进小狗音乐的曲库
struct ImportButton: View {
    /// 带文字的大按钮（空曲库引导里用）；默认是工具栏上的「+」图标
    var titled = false
    @Environment(LibraryStore.self) private var library
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            if titled {
                Label("导入歌曲", systemImage: "square.and.arrow.down")
            } else if library.isScanning {
                ProgressView()
            } else {
                Image(systemName: "plus")
            }
        }
        .accessibilityLabel("导入歌曲")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(urls) }
            }
        }
    }
}

/// 曲库为空时的引导：告诉用户三种放歌进来的方法
struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("还没有歌曲", systemImage: "music.note.house")
        } description: {
            Text("""
            点右上角「+」从「文件」导入歌曲或文件夹；
            也可以把歌放进「文件 › 我的 iPhone › 小狗音乐」；
            或者用电脑 Finder / iTunes 的「文件共享」拖进来。
            """)
        } actions: {
            ImportButton(titled: true).buttonStyle(.borderedProminent)
        }
    }
}
