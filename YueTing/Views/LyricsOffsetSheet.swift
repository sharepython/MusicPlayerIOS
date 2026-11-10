import SwiftUI

/// 歌词微调：有的歌词整体比歌声早或晚一点，按首单独挪。歌词比歌声慢就点「提前」，快就点「延后」。
/// 弹得矮，歌词页 / 律动画面还露在上面，边调边看对没对上
struct LyricsOffsetSheet: View {
    let song: Song
    @Environment(LyricsStore.self) private var lyrics

    var body: some View {
        let offset = lyrics.offset(for: song.id)
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("歌词微调").font(.headline)
                Text(Self.describe(offset))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText(value: offset))
                    .animation(.snappy, value: offset)
                    .accessibilityIdentifier("lyricsOffset")
                Text("歌词比歌声慢就点提前，快就点延后，只对这首歌生效")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                step("延后", 0.5, by: -0.5)
                step("延后", 0.1, by: -0.1)
                step("提前", 0.1, by: 0.1)
                step("提前", 0.5, by: 0.5)
            }
            Button("还原") { lyrics.setOffset(0, for: song.id) }
                .disabled(offset == 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: offset)
    }

    private func step(_ verb: String, _ amount: Double, by delta: Double) -> some View {
        let offset = lyrics.offset(for: song.id)
        let next = offset + delta
        return Button { lyrics.setOffset(next, for: song.id) } label: {
            VStack(spacing: 2) {
                Text(verb).font(.footnote)
                Text("\(amount, specifier: "%.1f") 秒").font(.subheadline.monospacedDigit().weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .disabled(abs(next) > LyricsStore.maxOffset + 0.01)
        .accessibilityLabel("\(verb) \(amount, specifier: "%.1f") 秒")
    }

    static func describe(_ s: Double) -> String {
        if s == 0 {
            return "歌词与歌曲同步"
        }
        return String(format: s > 0 ? "歌词提前 %.1f 秒" : "歌词延后 %.1f 秒", abs(s))
    }
}
