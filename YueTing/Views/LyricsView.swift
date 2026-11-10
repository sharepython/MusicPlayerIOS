import SwiftUI

/// 播放页的歌词，效果对齐 QQ 音乐：当前行停在正中、放大，按逐字时间从左到右填亮（没有逐字时间时按字数估算），
/// 外文歌下面带翻译。手指拖动歌词时中间出现定位线，点左边的播放按钮从那一行开始播，松手 3 秒后回到当前行。
/// 点歌词切回封面
struct LyricsView: View {
    let song: Song
    /// 点歌词时调用，播放页切回封面
    var onTap: () -> Void = {}
    @Environment(PlayerController.self) private var player
    @Environment(LyricsStore.self) private var lyrics
    /// 手指在拖歌词，或者松手还不到 3 秒，这时显示定位线、不自动滚动
    @State private var browsing = false
    @State private var hideTask: Task<Void, Never>?
    /// 拖动时停在定位线上的那一行
    @State private var centered: Int?

    static let font = Font.system(size: 21, weight: .bold)

    var body: some View {
        if let l = lyrics.lyrics(for: song.id), !l.lines.isEmpty {
            content(l)
        } else {
            status(lyrics.cache[song.id])
        }
    }

    private func content(_ l: Lyrics) -> some View {
        let current = l.synced ? currentLine(l) : nil
        return GeometryReader { g in
            let mid = g.size.height / 2
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 26) {
                        if l.source == .recognized {
                            Label("本机识别生成，可能有错字", systemImage: "waveform").font(.caption).foregroundStyle(.white.opacity(0.5))
                        }
                        ForEach(Array(l.lines.enumerated()), id: \.offset) { i, line in
                            row(l, i, current: current)
                                .id(i)
                                .onGeometryChange(for: Bool.self) { p in
                                    abs(p.frame(in: .named("lyrics")).midY - mid) <= p.size.height / 2 + 13
                                } action: {
                                    if $0 {
                                        centered = i
                                    }
                                }
                        }
                        footer(l)
                    }
                    .padding(.horizontal, 12)
                    // 上下留半屏，第一行和最后一行也能停到中间
                    .padding(.vertical, mid)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                }
                .coordinateSpace(.named("lyrics"))
                .modifier(UserScrollWatcher(began: beginBrowsing, ended: endBrowsing))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                             .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    if browsing, l.synced {
                        locator(l, proxy)
                    }
                }
                // 还没唱到第一行（前奏、拖回开头）时停在第一行
                .onChange(of: current) { _, i in
                    guard l.synced, !browsing else { return }
                    withAnimation(.spring(duration: 0.6)) { proxy.scrollTo(i ?? 0, anchor: .center) }
                }
                .onChange(of: browsing) { _, b in
                    guard !b, l.synced else { return }
                    withAnimation(.spring(duration: 0.6)) { proxy.scrollTo(currentLine(l) ?? 0, anchor: .center) }
                }
                .onAppear {
                    if l.synced {
                        proxy.scrollTo(current ?? 0, anchor: .center)
                    }
                }
            }
        }
        .accessibilityIdentifier("lyrics")
    }

    /// 一行歌词：当前行放大、逐字填亮，其他行半透明；有翻译时翻译在下面
    private func row(_ l: Lyrics, _ i: Int, current: Int?) -> some View {
        let line = l.lines[i]
        let isCurrent = i == current
        let dim = !l.synced ? 0.85 : browsing && i == centered ? 0.7 : 0.4
        return VStack(spacing: 6) {
            if isCurrent {
                KaraokeLine(line: line)
            } else {
                Text(line.text).font(Self.font).foregroundStyle(.white.opacity(dim))
            }
            if let t = line.translation {
                Text(t).font(.callout.weight(.medium)).foregroundStyle(.white.opacity(isCurrent ? 0.85 : dim * 0.8))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .scaleEffect(isCurrent ? 1.08 : 1)
        .animation(.spring(duration: 0.4), value: isCurrent)
    }

    /// 拖动歌词时的定位线：左边从这一行播放，右边是这一行的时间
    private func locator(_ l: Lyrics, _ proxy: ScrollViewProxy) -> some View {
        let time = centered.flatMap { l.lines.indices.contains($0) ? l.lines[$0].time : nil }
        return HStack(spacing: 8) {
            Button {
                guard let time else { return }
                player.seek(to: max(time, 0))
                if !player.isPlaying {
                    player.togglePlay()
                }
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { browsing = false }
            } label: {
                Image(systemName: "play.fill").font(.footnote).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从这里播放")
            Line().stroke(style: StrokeStyle(lineWidth: 0.6, dash: [3, 3])).frame(height: 1)
            Text(formatTime(time ?? 0)).font(.caption.monospacedDigit()).frame(minWidth: 40)
        }
        .foregroundStyle(.white.opacity(0.75))
        .transition(.opacity)
    }

    private func beginBrowsing() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { browsing = true }
    }

    private func endBrowsing() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { browsing = false }
        }
    }

    private func footer(_ l: Lyrics) -> some View {
        VStack(spacing: 8) {
            if let provider = l.provider {
                Text("歌词来自 \(provider)").font(.caption)
            }
            Button { lyrics.refresh(song.id) } label: {
                Label(l.source == .recognized ? "重新识别" : "重新获取歌词", systemImage: "arrow.clockwise").font(.footnote)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.5)).padding(.top, 12)
    }

    /// 没有歌词时的提示：正在查 / 正在识别 / 等授权识别 / 纯音乐 / 没找到 / 没网 / 排队中
    @ViewBuilder
    private func status(_ l: Lyrics?) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if let activity = lyrics.activity(for: song.id) {
                ProgressView().tint(.white)
                if activity == .searching {
                    Text("正在查找歌词…")
                } else {
                    Text("在线没有找到，正在用本机语音识别生成歌词…")
                    Text("识别一首歌大约需要十几秒到一分钟").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            } else if l?.source == .instrumental {
                Image(systemName: "music.note").font(.largeTitle)
                Text("纯音乐，请欣赏")
            } else if l != nil {
                Image(systemName: "text.badge.xmark").font(.largeTitle)
                Text("没有找到歌词")
                retry
            } else if lyrics.needsPermission, lyrics.waitingForRecognition(song.id) {
                Image(systemName: "waveform").font(.largeTitle)
                Text("在线歌词库里没有这首歌")
                Text("可以用本机语音识别听写歌词，全程在手机上完成，音频不会上传；伴奏会干扰识别，可能有错字")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                Button("用语音识别生成") { lyrics.allowRecognition() }
                    .buttonStyle(.bordered).tint(.white)
            } else if lyrics.offline {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                Text("连不上歌词服务器")
                Text("请检查网络；如果是第一次使用，请到「设置 › 小狗音乐 › 无线数据」里允许使用网络")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                retry
            } else {
                ProgressView().tint(.white)
                Text(lyrics.remaining > 1 ? "歌词排队生成中，还剩 \(lyrics.remaining) 首" : "歌词生成中…")
                if lyrics.serverBusy {
                    Text("歌词服务器繁忙，稍后自动重试").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityIdentifier("lyrics")
    }

    private var retry: some View {
        Button("重新获取") { lyrics.refresh(song.id) }
            .buttonStyle(.bordered).tint(.white)
    }

    /// 当前该高亮的行：开始时间不晚于播放位置的最后一行
    private func currentLine(_ l: Lyrics) -> Int? {
        let t = player.position + 0.2
        var lo = 0, hi = l.lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if (l.lines[mid].time ?? 0) <= t {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }
}

/// 正在唱的那一行：有逐字时间时随播放逐帧刷新，唱过的字是白色，没唱到的半透明，正在唱的字从左到右渐亮；
/// 只有逐行时间时整行亮着，不用逐帧刷新
private struct KaraokeLine: View {
    let line: Lyrics.Line
    @Environment(PlayerController.self) private var player

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying || line.words == nil)) { _ in
            let text = Text(line.text).font(LyricsView.font)
            if #available(iOS 18, *) {
                text.textRenderer(KaraokeRenderer(progress: line.progress(at: now)))
            } else {
                text.foregroundStyle(.white)
            }
        }
    }

    /// position 每秒只更新 4 次，逐字填色太卡，播放时直接读播放器的时间
    private var now: Double {
        let t = player.player.currentTime().seconds
        return player.isPlaying && t.isFinite ? t : player.position
    }
}

/// 卡拉 OK 式填色：前 progress 个字（UTF-16 计数，可以带小数）画白色并带一点光晕，其余画半透明
@available(iOS 18, *)
private struct KaraokeRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        guard let base = layout.first?.first?.first?.characterIndices.first else { return }
        for line in layout {
            for run in line {
                for slice in run {
                    let rect = slice.typographicBounds.rect
                    let chars = slice.characterIndices
                    guard let first = chars.first else { continue }
                    let start = Double(base.distance(to: first))
                    let fraction = min(max((progress - start) / Double(max(chars.count, 1)), 0), 1)
                    var dim = ctx
                    dim.opacity = 0.4
                    dim.draw(slice)
                    guard fraction > 0 else { continue }
                    var lit = ctx
                    lit.clip(to: Path(CGRect(x: rect.minX, y: rect.minY - 4, width: rect.width * fraction, height: rect.height + 8)))
                    lit.addFilter(.shadow(color: .white.opacity(0.45), radius: 4))
                    lit.draw(slice)
                }
            }
        }
    }
}

/// 识别用户手指拖动歌词：iOS 18 用滚动阶段（包含松手后的惯性滑动），iOS 17 退回拖动手势
private struct UserScrollWatcher: ViewModifier {
    let began: () -> Void
    let ended: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { old, new in
                if new == .interacting {
                    began()
                }
                if new == .idle, old != .idle, old != .animating {
                    ended()
                }
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in began() }.onEnded { _ in ended() })
        }
    }
}

/// 定位线
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
