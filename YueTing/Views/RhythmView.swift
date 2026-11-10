import SwiftUI

/// 律动模式，仿抖音「节奏小球」：背景是一面墙（默认是拼板的浅色墙，设置里能换成星夜、樱花这些场景，RhythmTheme），歌词的每个字是一张亚克力卡片，由一根铁丝支架撑在墙上，
/// 一句一组：横排、斜着往下的台阶或者高低错开的波浪。组和组之间用各种架子接起来：带柱子的双轨、
/// 木板、磨砂的 S 形管，间隔长时是一级级往下的长木板。前奏时一只小白狗陪球玩，唱完后一只小白猫把球接住、拍着玩。
/// 每首歌按 id 定下配色和这些元素的搭配，同一首歌每次一样、不同的歌不一样（RhythmStage）。
/// 用 SceneKit 做成真 3D 场景（RhythmScene），镜头正对着墙，跟着小球左右、往下移，小球落在画面从上往下 0.55 处。
/// 小球是一颗透明的玻璃球，按逐字时间从一张卡片跳到下一张，踩中的卡片亮一下；卡片按小球弹开的方向斜着。
/// 墙顶上是立体的歌名和歌手。没有带时间轴的歌词（纯音乐、没找到）时按每拍 0.5 秒铺没有字的卡片。
/// 画面铺满整个播放页，点击由播放页处理（呼出 / 收起控件）
struct RhythmView: View {
    let song: Song
    @Environment(PlayerController.self) private var player
    @Environment(LyricsStore.self) private var lyrics
    /// 律动场景，RhythmTheme.Id 的 rawValue
    @AppStorage("rhythmTheme") private var themeID = RhythmTheme.Id.cream.rawValue

    var body: some View {
        GeometryReader { g in
            let stage = RhythmStage(lyrics: lyrics.cache[song.id], duration: player.duration, width: g.size.width,
                                    title: song.title, artist: song.artist, seed: song.id)
            let theme = RhythmTheme.make(RhythmTheme.Id(rawValue: themeID) ?? .cream, song: song.id, palette: stage.palette)
            RhythmSceneView(stage: stage, theme: theme,
                            key: "\(song.id)|\(stage.tiles.count)|\(Int(g.size.width))|\(Int(player.duration))|\(theme.id.rawValue)",
                            player: player, offset: lyrics.offset(for: song.id))
        }
        .accessibilityElement()
        .accessibilityLabel("律动")
        .accessibilityIdentifier("rhythm")
    }
}
