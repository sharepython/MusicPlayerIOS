import CoreImage
import SwiftUI

/// 全屏播放页：封面 / 歌词 / 律动小球、歌名、进度条、播放控制、收藏、播放模式、播放队列。
/// 律动模式铺满整个屏幕（歌名立在画面顶上的墙上），控件浮在画面上：播放中 3 秒没操作就收起，
/// 只留进度条；点画面呼出或收起，暂停时一直显示
struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(LyricsStore.self) private var lyrics
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var addingToPlaylist = false
    @State private var adjustingLyrics = false
    @State private var choosingTheme = false
    /// 封面区域显示封面、歌词还是律动小球
    @AppStorage("stage") private var stage = Stage.cover
    /// 律动模式下控件是否收起
    @State private var immersive = false
    /// 每次呼出控件或有操作时加一，重新开始自动收起的倒计时
    @State private var activity = 0
    /// 切播放模式后弹一下的提示，toastID 每次加一重新计时
    @State private var toast: String?
    @State private var toastID = 0

    enum Stage: String {
        case cover, lyrics, rhythm
    }

    var body: some View {
        let song = player.currentSong
        let rhythm = stage == .rhythm && canRhythm
        let chrome = !(rhythm && immersive)
        GeometryReader { g in
            VStack(spacing: 0) {
                if chrome {
                    header.transition(.opacity)
                }
                if stage == .lyrics, let song {
                    LyricsView(song: song) { show(.cover) }
                        // 换歌时重建歌词视图，滚动位置和拖动状态不沿用上一首的
                        .id(song.id)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                } else if rhythm {
                    // 律动画面在背景里铺满全屏，这里留空；点空白处呼出 / 收起控件
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toggleChrome() }
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 12)
                    ArtworkView(song: song, size: min(g.size.width - 64, g.size.height * 0.42), radius: 18)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                        .scaleEffect(player.isPlaying ? 1 : 0.88)
                        .animation(.spring(duration: 0.45), value: player.isPlaying)
                        // 点封面切到歌词
                        .onTapGesture { show(.lyrics) }
                        .transition(.opacity)
                    Spacer(minLength: 12)
                }
                if !rhythm {
                    titleRow(song)
                }
                ProgressSlider { activity += 1 }.padding(.top, 18)
                if chrome {
                    VStack(spacing: 0) {
                        controls.padding(.top, 14)
                        bottomRow.padding(.top, 22)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        // 提示弹在屏幕正中，不挡歌名和按钮
        .overlay {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityIdentifier("toast")
            }
        }
        .task(id: toastID) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
        .background {
            ZStack {
                BlurredBackground(song: song)
                // 换歌时不重建：同一个 SCNView 里换场景，新的画面准备好之前一直显示上一首的
                if rhythm, let song {
                    RhythmView(song: song)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!chrome)
        .persistentSystemOverlays(chrome ? .automatic : .hidden)
        .task(id: AutoHide(activity: activity, rhythm: rhythm, playing: player.isPlaying, immersive: immersive)) {
            guard rhythm, player.isPlaying, !immersive, !showQueue, !addingToPlaylist, !adjustingLyrics, !choosingTheme else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !showQueue, !addingToPlaylist, !adjustingLyrics, !choosingTheme else { return }
            withAnimation(.easeInOut(duration: 0.3)) { immersive = true }
        }
        // 暂停时把控件呼出来
        .onChange(of: player.isPlaying) { _, playing in
            if !playing {
                withAnimation(.easeInOut(duration: 0.3)) { immersive = false }
            }
        }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $addingToPlaylist) { AddToPlaylistSheet(songIDs: song.map { [$0.id] } ?? []) }
        .sheet(isPresented: $adjustingLyrics) {
            if let song {
                LyricsOffsetSheet(song: song)
            }
        }
        .sheet(isPresented: $choosingTheme) { RhythmThemeSheet() }
        // 关掉微调、场景面板后重新开始自动收起的倒计时
        .onChange(of: adjustingLyrics) { _, open in
            if !open {
                activity += 1
            }
        }
        .onChange(of: choosingTheme) { _, open in
            if !open {
                activity += 1
            }
        }
        // 队列清空后自动收起
        .onChange(of: player.currentEntry == nil) { _, empty in
            if empty {
                dismiss()
            }
        }
    }

    /// 自动收起倒计时依赖的状态，任何一项变了都重新计时
    private struct AutoHide: Equatable {
        var activity: Int, rhythm: Bool, playing: Bool, immersive: Bool
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.3)) { immersive.toggle() }
        activity += 1
    }

    /// 顶栏：收起、加入歌单；律动模式下右上角多一个换场景（星夜、樱花、雪国这些）的按钮，别的页面没有
    private var header: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("收起")
            Spacer()
            if stage == .rhythm && canRhythm {
                Button { choosingTheme = true } label: { Image(systemName: "paintpalette").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("律动场景")
                    .accessibilityIdentifier("rhythmTheme")
                    .transition(.opacity)
            }
            Button { addingToPlaylist = true } label: { Image(systemName: "text.badge.plus").font(.title3).frame(width: 44, height: 44) }
                .accessibilityLabel("加入歌单")
        }
        // 拖动条放在正中，不跟着右边按钮多少挪动
        .overlay { Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5) }
        .padding(.top, 4)
    }

    private func titleRow(_ song: Song?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song?.title ?? "").font(.title2.bold()).lineLimit(1)
                    .accessibilityIdentifier("nowPlayingTitle")
                Text([song?.artist, song?.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.body).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 12)
            if let song {
                let fav = library.isFavorite(song.id)
                Button { library.toggleFavorite(song.id) } label: {
                    Image(systemName: fav ? "heart.fill" : "heart").font(.title2)
                        .foregroundStyle(fav ? .pink : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(fav ? "取消喜欢" : "喜欢")
                .sensoryFeedback(.impact(weight: .light), trigger: fav)
            }
        }
    }

    /// 和 QQ 音乐一样：左边一个按钮切播放模式，右边打开播放队列
    private var controls: some View {
        HStack {
            Button {
                player.cycleMode()
                withAnimation(.easeOut(duration: 0.2)) { toast = player.mode.label }
                toastID += 1
                UIAccessibility.post(notification: .announcement, argument: player.mode.label)
            } label: {
                Image(systemName: player.mode.icon).font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.mode.label)
            .accessibilityHint("切换播放模式")
            .accessibilityIdentifier("playMode")
            Spacer()
            Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 30)) }
                .accessibilityLabel("上一首")
            Spacer()
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("playPause")
            Spacer()
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)) }
                .accessibilityLabel("下一首")
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("播放队列")
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { activity += 1 })
    }

    /// 律动模式要逐字时间：小球一个字一个字砸卡片。只有逐行时间（或还没有歌词）的歌按钮置灰，
    /// 停在律动模式时切到这种歌先显示封面，再切回带逐字时间的歌接着放律动
    private var canRhythm: Bool {
        player.currentSong.flatMap { lyrics.cache[$0.id] }?.wordTimed == true
    }

    /// 底部一排功能按钮，平均铺满一行：歌词微调、律动模式、歌词。封面页没有歌词时间可调，微调按钮置灰；
    /// 没有逐字时间的歌律动按钮置灰。换律动场景的按钮只在律动模式的顶栏里
    private var bottomRow: some View {
        let song = player.currentSong
        let shifted = song.map { lyrics.offset(for: $0.id) != 0 } ?? false
        let rhythm = stage == .rhythm && canRhythm
        let canShift = (stage == .lyrics || rhythm) && song != nil
        return HStack(spacing: 0) {
            // 按首微调歌词时间，调过的话图标是实心的
            Button { adjustingLyrics = true } label: {
                tool("timer", on: shifted && canShift).foregroundStyle(shifted && canShift ? .pink : .white)
                    .opacity(canShift ? 1 : 0.3)
            }
            .disabled(!canShift)
            .accessibilityLabel("歌词微调")
            .accessibilityValue(canShift ? LyricsOffsetSheet.describe(song.map { lyrics.offset(for: $0.id) } ?? 0) : "")
            .accessibilityIdentifier("lyricsOffset")
            Button { show(rhythm ? .cover : .rhythm) } label: {
                tool("circle.dotted.circle", on: rhythm).opacity(canRhythm ? 1 : 0.3)
            }
            .disabled(!canRhythm)
            .accessibilityLabel(rhythm ? "退出律动" : "律动模式")
            Button { show(stage == .lyrics ? .cover : .lyrics) } label: { tool("quote.bubble", on: stage == .lyrics) }
                .accessibilityLabel(stage == .lyrics ? "显示封面" : "显示歌词")
        }
        .buttonStyle(.plain)
    }

    private func tool(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon).font(.title2.weight(.medium))
            .symbolVariant(on ? .fill : .none)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
    }

    private func show(_ s: Stage) {
        withAnimation(.easeInOut(duration: 0.25)) { stage = s; immersive = false }
        activity += 1
    }
}

/// 进度条：拖动时只改本地值，松手才 seek；seek 时播放器立刻把 position 改成目标值，所以松手后不会闪回旧位置
struct ProgressSlider: View {
    /// 开始拖动时通知外面（律动模式据此推迟收起控件）
    var onInteract: () -> Void = {}
    @Environment(PlayerController.self) private var player
    /// 拖动中的目标秒数，nil 表示没在拖
    @State private var dragging: Double?

    var body: some View {
        let total = max(player.duration, 0)
        let shown = dragging ?? player.position
        let fraction = total > 0 ? min(max(shown / total, 0), 1) : 0
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: g.size.width * fraction)
                }
                .frame(height: dragging == nil ? 6 : 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard total > 0 else { return }
                            if dragging == nil {
                                onInteract()
                            }
                            withAnimation(.easeOut(duration: 0.15)) {
                                dragging = min(max(v.location.x / g.size.width, 0), 1) * total
                            }
                        }
                        .onEnded { _ in
                            if let t = dragging {
                                player.seek(to: t)
                            }
                            onInteract()
                            withAnimation(.easeOut(duration: 0.15)) { dragging = nil }
                        }
                )
            }
            .frame(height: 24)
            HStack {
                Text(formatTime(shown))
                Spacer()
                Text("-" + formatTime(max(total - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(dragging == nil ? 0.6 : 0.95))
        }
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(formatTime(shown))，共 \(formatTime(total))")
        .accessibilityAdjustableAction { dir in
            player.seek(to: player.position + (dir == .increment ? 15 : -15))
        }
    }
}

/// 播放页背景：把封面缩小后高斯模糊，再压一层暗色，保证白字看得清。
/// 模糊只在换歌时算一次，画成一张小图再拉伸铺满：实时的 .blur 每次画面有变化（律动、歌词滚动）都要系统重新模糊整屏，很耗 GPU
private struct BlurredBackground: View {
    let song: Song?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: ArtworkView.placeholderColors(song), startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Color.black.opacity(0.45)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: song?.id) {
            guard let song else { image = nil; return }
            let art = ArtworkLoader.shared.cached(song.id)
            guard let art = art == nil ? await ArtworkLoader.shared.image(for: song) : art else { image = nil; return }
            image = await Task.detached(priority: .userInitiated) { Self.blurred(art) }.value
        }
    }

    nonisolated private static let context = CIContext()

    /// 缩到 96 像素再模糊，半径按原来在整屏上 60 点的比例换算，边缘先往外延伸，免得四周发黑
    nonisolated private static func blurred(_ art: UIImage) -> UIImage? {
        guard let cg = art.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = 96 / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blur = small.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: small.extent)
        guard let out = context.createCGImage(blur, from: small.extent) else { return nil }
        return UIImage(cgImage: out)
    }
}
