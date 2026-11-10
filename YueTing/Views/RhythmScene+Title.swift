import SceneKit
import UIKit

/// 墙顶上的歌名：仿视频里的「童话镇」，每个字是一个带倒角的立体字，颜色轮流换，墙上落一块影子；
/// 下面一行小字是歌手（没有时间轴歌词时换成提示）。放在第一排上面，开唱后随着镜头往下移慢慢移出画面。
/// 镜头抬高多少，歌名就跟着抬高多少（setAspect 里挪），前奏时歌名才在画面上部
extension RhythmScene {
    /// 标题块（含小字）的底边，在前奏小狗的家上面留出空
    static let titleBottom: CGFloat = -370

    @MainActor func buildTitle() {
        let text = stage.title.trimmingCharacters(in: .whitespaces)
        let root = titleNode
        let subtitleY = Self.titleBottom - 10
        if !stage.subtitle.isEmpty {
            root.addChildNode(subtitle(stage.subtitle, y: subtitleY))
        }
        guard !text.isEmpty else { scene.rootNode.addChildNode(root); return }
        let lines = Self.titleLines(text, width: stage.width - 2 * RhythmStage.margin)
        let font = UIFont(name: "PingFangSC-Semibold", size: lines.size) ?? .systemFont(ofSize: lines.size, weight: .heavy)
        let lineHeight = lines.size * 1.12
        var hue = 0
        for (n, line) in lines.text.enumerated() {
            // 这一行的中线（屏幕点，往下为正）
            let mid = subtitleY - 34 - CGFloat(lines.text.count - 1 - n) * lineHeight - lines.size * 0.42
            let advances = line.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            var x = (stage.width - advances.reduce(0, +)) / 2
            for (ch, adv) in zip(line, advances) {
                defer { x += adv }
                guard !ch.isWhitespace else { continue }
                // 字的颜色按主题轮流用，奶油拼板是嫩绿、柠檬黄、粉、紫、青
                let color = UIColor(hue: theme.titleHues[hue % theme.titleHues.count], saturation: theme.titleSat, brightness: 1, alpha: 1)
                hue += 1
                root.addChildNode(glyph(String(ch), font: font, color: color, x: x, mid: mid))
                root.addChildNode(titleShadow(x: x + adv / 2, y: mid, size: lines.size))
            }
        }
        scene.rootNode.addChildNode(root)
    }

    /// 按 84 号字排，一行放不下时缩小；缩到 44 号以下就拆成两行（外文在中间附近的空格处断开）
    private static func titleLines(_ s: String, width: CGFloat) -> (text: [String], size: CGFloat) {
        func fit(_ parts: [String]) -> CGFloat {
            let probe = UIFont(name: "PingFangSC-Semibold", size: 100) ?? .systemFont(ofSize: 100)
            let widest = parts.map { ($0 as NSString).size(withAttributes: [.font: probe]).width }.max() ?? 1
            return min(84, 100 * width / max(widest, 1))
        }
        let one = fit([s])
        guard one < 44, s.count > 1 else { return ([s], max(one, 28)) }
        let chars = Array(s), half = chars.count / 2
        let spaces = chars.indices.filter { chars[$0] == " " }
        let cut = spaces.min { abs($0 - half) < abs($1 - half) } ?? half
        let parts = [String(chars[..<cut]), String(chars[cut...])].map { $0.trimmingCharacters(in: .whitespaces) }
        return (parts, max(fit(parts), 28))
    }

    /// 一个立体字：正面亮、侧面和倒角暗一些，看得出厚度；离墙 14 点
    @MainActor private func glyph(_ s: String, font: UIFont, color: UIColor, x: CGFloat, mid: CGFloat) -> SCNNode {
        let text = SCNText(string: s, extrusionDepth: 10)
        text.font = font
        text.flatness = 0.5
        text.chamferRadius = 1.6
        let front = SCNMaterial()
        front.lightingModel = .blinn
        front.diffuse.contents = color
        front.emission.contents = color
        front.emission.intensity = theme.titleGlow
        front.specular.contents = UIColor.white
        front.shininess = 30
        let side = SCNMaterial()
        side.lightingModel = .lambert
        side.diffuse.contents = color.withBrightness(0.55)
        side.emission.contents = color.withBrightness(0.4)
        side.emission.intensity = 0.4
        text.materials = [front, side, side, front, side]
        let node = SCNNode(geometry: text)
        node.scale = SCNVector3(Self.unit, Self.unit, Self.unit)
        // SCNText 的原点在左边的基线上；字的中线大约在基线上面 0.37 个字号处
        node.simdPosition = v(Point3(x: x, y: mid + font.pointSize * 0.37, z: 14))
        return node
    }

    /// 字落在墙上的软影子，往右下偏一点
    private func titleShadow(x: CGFloat, y: CGFloat, size: CGFloat) -> SCNNode {
        let node = shadowNode(at: Point3(x: x, y: y - 6, z: 0), w: size * 1.5, h: size * 1.3, material: materials().shade)
        node.renderingOrder = Self.shadowOrder
        return node
    }

    /// 歌手那一行：深色小字，贴在墙前面
    @MainActor private func subtitle(_ s: String, y: CGFloat) -> SCNNode {
        let image = RhythmArt.label(s)
        // 贴图按 64 号字画，这里显示成 17 号
        let k = 17.0 / 64 * Self.unit
        let plane = SCNPlane(width: image.size.width * k, height: image.size.height * k)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.multiply.contents = theme.ink
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.simdPosition = v(Point3(x: stage.width / 2, y: y, z: 4))
        node.renderingOrder = Self.labelOrder
        return node
    }
}

private extension UIColor {
    func withBrightness(_ b: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return UIColor(hue: h, saturation: min(1, s * 1.2), brightness: b, alpha: a)
    }
}
