import SwiftUI

/// 排好序的列表里首字母相同、挨在一起的一段
struct LetterRun<T>: Identifiable {
    /// 这一段第一项在整个列表里的位置
    var id: Int
    var letter: String
    var items: [(offset: Int, element: T)]
}

/// 拼音首字母，不是 A–Z 开头的（数字、符号）算「#」
func indexLetter(_ pinyin: String) -> String {
    guard let c = pinyin.unicodeScalars.first, ("a"..."z").contains(c) || ("A"..."Z").contains(c) else { return "#" }
    return String(c).uppercased()
}

/// 按首字母把排好序的列表切成几段；同一个字母不挨在一起时分成几段，索引跳到第一段
func letterRuns<T>(_ items: [T], key: (T) -> String) -> [LetterRun<T>] {
    var runs: [LetterRun<T>] = []
    for (i, item) in items.enumerated() {
        let l = indexLetter(key(item))
        if runs.last?.letter == l {
            runs[runs.count - 1].items.append((i, item))
        } else {
            runs.append(LetterRun(id: i, letter: l, items: [(i, item)]))
        }
    }
    return runs
}

extension View {
    /// 右边一列首字母：点一下或者按住上下滑，列表跳到那个字母开头的地方，屏幕中间浮出放大的字母。
    /// letters 按列表里出现的顺序给；jump 收到字母后自己滚动列表
    func sectionIndex(_ letters: [String], jump: @escaping (String) -> Void) -> some View {
        modifier(SectionIndex(letters: letters, jump: jump))
    }
}

private struct SectionIndex: ViewModifier {
    let letters: [String]
    let jump: (String) -> Void
    @State private var active: String?
    @State private var feedback = UISelectionFeedbackGenerator()
    private let row: CGFloat = 16, pad: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if letters.count > 1 {
                    strip
                }
            }
            .overlay {
                if let active {
                    Text(active)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 84, height: 84)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { l in
                Text(l)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active == l ? Color.white : Color.accentColor)
                    .frame(width: 18, height: row)
                    .background {
                        if active == l {
                            Circle().fill(Color.accentColor)
                        }
                    }
            }
        }
        .padding(.vertical, pad)
        .background(Capsule().fill(.thinMaterial).opacity(active == nil ? 0 : 1))
        // 比字母宽一点好按到
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let i = Int(((g.location.y - pad) / row).rounded(.down))
                    let l = letters[min(max(i, 0), letters.count - 1)]
                    guard l != active else { return }
                    active = l
                    feedback.selectionChanged()
                    jump(l)
                }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { active = nil } }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sectionIndex")
    }
}
