import SwiftUI

@main
struct YueTingApp: App {
    @State private var library: LibraryStore
    @State private var player: PlayerController
    @State private var lyrics: LyricsStore
    @State private var system: SystemLyrics
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = LibraryStore()
        _library = State(initialValue: library)
        let player = PlayerController(library: library), lyrics = LyricsStore()
        _player = State(initialValue: player)
        _lyrics = State(initialValue: lyrics)
        _system = State(initialValue: SystemLyrics(player: player, store: lyrics))
        // 律动模式的歌词用宋体，第一次启动时在后台下载
        RhythmArt.loadLyricFont()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(lyrics)
                .environment(system)
                // 在「文件」等 App 里选「用小狗音乐打开」：导入后立刻播放
                .onOpenURL { url in
                    Task {
                        let ids = await library.importFiles([url])
                        let songs = library.songs(ids)
                        if !songs.isEmpty {
                            player.play(songs)
                        }
                    }
                }
                // 回到前台时重新扫描，拿到用户在「文件」App 或 Finder 里新放进来 / 删掉的歌
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        Task { await library.sync() }
                    }
                    lyrics.isActive = phase == .active
                }
                // 曲库变化时给新歌排队生成歌词；正在播放的歌插队
                .onChange(of: library.songs, initial: true) { _, songs in lyrics.sync(songs) }
                .onChange(of: player.currentSong?.id, initial: true) { _, id in lyrics.prioritize(id) }
        }
    }
}
