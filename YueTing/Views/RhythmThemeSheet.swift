import SwiftUI

/// 律动场景：墙、卡片、支架、灯光、两个小家的样子一起换，小狗、小猫、门上的 CW / CC 和台子上的两个词不变。
/// 弹得矮，律动画面还露在上面，点一下马上换，边点边看
struct RhythmThemeSheet: View {
    @AppStorage("rhythmTheme") private var themeID = RhythmTheme.Id.cream.rawValue

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 14) {
            Text("律动场景").font(.headline).padding(.top, 18)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(RhythmTheme.Id.allCases) { id in item(id) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: themeID)
    }

    private func item(_ id: RhythmTheme.Id) -> some View {
        let on = themeID == id.rawValue
        return Button { themeID = id.rawValue } label: {
            HStack(spacing: 10) {
                swatch(id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.name).font(.subheadline.weight(.semibold))
                    Text(id.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.pink : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink).padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id.name)
        .accessibilityHint(id.note)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("theme-\(id.rawValue)")
    }

    /// 小样：墙的颜色上斜着两张卡片、一颗小球；「每首随机」是四个场景拼起来
    @ViewBuilder private func swatch(_ id: RhythmTheme.Id) -> some View {
        if id == .shuffle {
            let picks = Array(RhythmTheme.Id.scenes.dropFirst().prefix(4))
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { c in
                            Color(RhythmTheme.make(picks[r * 2 + c], song: "", palette: 0).wallColor)
                        }
                    }
                }
            }
            .overlay(Image(systemName: "shuffle").font(.title3.weight(.bold)).foregroundStyle(.white).shadow(radius: 2))
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            let t = RhythmTheme.make(id, song: "", palette: 0)
            ZStack {
                Color(t.wallColor)
                ForEach(0..<2, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(t.cards[k % t.cards.count]).opacity(t.cardClear))
                        .frame(width: 18, height: 6)
                        .rotationEffect(.degrees(k == 0 ? 12 : -12))
                        .offset(x: k == 0 ? -10 : 11, y: k == 0 ? 6 : 14)
                }
                Circle().fill(Color(t.ball)).frame(width: 11, height: 11).offset(x: -8, y: -6)
                    .shadow(color: Color(t.ball).opacity(0.6), radius: 3)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}
