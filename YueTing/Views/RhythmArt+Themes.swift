import UIKit

/// 各个主题的墙（1024 见方、四边接得上的贴图）和飘在画面里的小东西的贴图，都是现画的
extension RhythmArt {
    @MainActor private static var walls: [String: UIImage] = [:]

    /// 主题的墙；同一种墙画一次
    @MainActor static func wall(_ t: RhythmTheme) -> UIImage {
        let c = t.wallColor.components
        let key = "\(t.id.rawValue)|\(c.r)|\(c.g)|\(c.b)"
        if let image = walls[key] {
            return image
        }
        let size: CGFloat = 1024
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let g = ctx.cgContext
            t.wallColor.setFill()
            g.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SeededRandom("wall-\(t.id.rawValue)")
            switch t.wall {
            case .panels: panels(g, t.wallColor, size)
            case .stars: stars(g, t, size, &rng)
            case .blossoms: blossoms(g, t, size, &rng)
            case .snowflakes: snowflakes(g, t, size, &rng)
            case .waves: waves(g, t, size, &rng)
            case .grid: grid(g, t, size, &rng)
            case .boards: boards(g, t, size, &rng)
            }
        }
        walls[key] = image
        return image
    }

    /// 在九个位置各画一遍，贴到边外面的部分从另一边露出来，重复铺时接得上
    private static func tiled(_ size: CGFloat, _ draw: (CGFloat, CGFloat) -> Void) {
        for dx in [-size, 0, size] { for dy in [-size, 0, size] { draw(dx, dy) } }
    }

    private static func r(_ rng: inout SeededRandom, _ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &rng)
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ k: CGFloat) -> UIColor {
        a.mixed(b, k)
    }

    /// 奶油拼板：一整片哑光的浅色，被细细的深色缝分成大小不一的长方形面板。
    /// 横缝贯穿整张图，竖缝只在两道横缝之间，图的四边都正好是缝
    private static func panels(_ g: CGContext, _ base: UIColor, _ size: CGFloat) {
        let p = base.components
        let bands: [CGFloat] = [0, 300, 520, 860, 1024]
        let cuts: [[CGFloat]] = [[0, 380], [0, 640], [0, 260, 820], [0, 520]]
        for b in 0..<4 {
            let xs = cuts[b] + [size]
            for k in 0..<(xs.count - 1) {
                // 每块面板亮度差一点点，看得出是拼起来的
                let shade = 1 + 0.025 * CGFloat((b * 3 + k * 5) % 5 - 2)
                UIColor(red: p.r * shade, green: p.g * shade, blue: p.b * shade, alpha: 1).setFill()
                g.fill(CGRect(x: xs[k], y: bands[b], width: xs[k + 1] - xs[k], height: bands[b + 1] - bands[b]))
            }
        }
        let seam = UIColor(red: p.r * 0.55, green: p.g * 0.55, blue: p.b * 0.58, alpha: 1)
        let light = UIColor(red: min(1, p.r * 1.12), green: min(1, p.g * 1.12), blue: min(1, p.b * 1.12), alpha: 1)
        for b in 0..<4 {
            seam.setFill()
            g.fill(CGRect(x: 0, y: bands[b], width: size, height: 3))
            light.setFill()
            g.fill(CGRect(x: 0, y: bands[b] + 3, width: size, height: 1.5))
            for x in cuts[b] {
                seam.setFill()
                g.fill(CGRect(x: x, y: bands[b], width: 3, height: bands[b + 1] - bands[b]))
                light.setFill()
                g.fill(CGRect(x: x + 3, y: bands[b] + 3, width: 1.5, height: bands[b + 1] - bands[b] - 3))
            }
        }
    }

    /// 软软的一团光：中间 color、往外透明
    private static func haze(_ g: CGContext, _ c: CGPoint, _ radius: CGFloat, _ color: UIColor, _ alpha: CGFloat) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
    }

    /// 星夜：几团淡紫的星云，满天大大小小的星星，几颗亮的带十字星芒
    private static func stars(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        for _ in 0..<6 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 180...320), a = r(&rng, 0.14...0.26)
            tiled(size) { dx, dy in haze(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, t.accent2, a) }
        }
        for _ in 0..<340 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 0.8...2.3)
            let color = mix(t.accent, .white, r(&rng, 0...1)).withAlphaComponent(r(&rng, 0.3...0.95))
            g.setFillColor(color.cgColor)
            tiled(size) { dx, dy in g.fillEllipse(in: CGRect(x: c.x + dx - radius, y: c.y + dy - radius, width: 2 * radius, height: 2 * radius)) }
        }
        g.setLineCap(.round)
        for _ in 0..<16 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), len = r(&rng, 9...20)
            tiled(size) { dx, dy in
                let p = CGPoint(x: c.x + dx, y: c.y + dy)
                haze(g, p, len * 1.4, t.accent, 0.45)
                g.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                g.setLineWidth(1.4)
                g.strokeLineSegments(between: [CGPoint(x: p.x - len, y: p.y), CGPoint(x: p.x + len, y: p.y),
                                               CGPoint(x: p.x, y: p.y - len), CGPoint(x: p.x, y: p.y + len)])
                g.setFillColor(UIColor.white.cgColor)
                g.fillEllipse(in: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2))
            }
        }
    }

    /// 一朵五瓣的樱花
    private static func flower(_ g: CGContext, _ c: CGPoint, _ radius: CGFloat, _ angle: CGFloat, _ petal: UIColor, _ heart: UIColor) {
        g.saveGState()
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: angle)
        g.setFillColor(petal.cgColor)
        for k in 0..<5 {
            g.saveGState()
            g.rotate(by: CGFloat(k) * 2 * .pi / 5)
            g.fillEllipse(in: CGRect(x: -radius * 0.33, y: -radius, width: radius * 0.66, height: radius * 0.98))
            g.restoreGState()
        }
        g.setFillColor(heart.cgColor)
        g.fillEllipse(in: CGRect(x: -radius * 0.16, y: -radius * 0.16, width: radius * 0.32, height: radius * 0.32))
        g.restoreGState()
    }

    /// 樱花：豆沙粉的墙纸上散着浅色的樱花和几片落下的花瓣
    private static func blossoms(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        for _ in 0..<48 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 14...36), angle = r(&rng, 0...6.3)
            let petal = t.accent.withAlphaComponent(r(&rng, 0.55...0.95))
            tiled(size) { dx, dy in flower(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, angle, petal, t.accent2) }
        }
        for _ in 0..<36 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 5...10), angle = r(&rng, 0...6.3)
            let color = t.accent.withAlphaComponent(r(&rng, 0.4...0.8))
            tiled(size) { dx, dy in
                g.saveGState()
                g.translateBy(x: c.x + dx, y: c.y + dy)
                g.rotate(by: angle)
                g.setFillColor(color.cgColor)
                g.fillEllipse(in: CGRect(x: -radius * 0.4, y: -radius, width: radius * 0.8, height: radius * 2))
                g.restoreGState()
            }
        }
    }

    /// 一朵六瓣的雪花：六条主枝，每条上两对小杈
    private static func flake(_ g: CGContext, _ c: CGPoint, _ radius: CGFloat, _ angle: CGFloat, _ color: UIColor, _ width: CGFloat) {
        g.saveGState()
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: angle)
        g.setStrokeColor(color.cgColor)
        g.setLineWidth(width)
        g.setLineCap(.round)
        for k in 0..<6 {
            g.saveGState()
            g.rotate(by: CGFloat(k) * .pi / 3)
            var seg = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -radius)]
            for (at, len) in [(0.45, 0.3), (0.72, 0.2)] as [(CGFloat, CGFloat)] {
                let y = -radius * at, l = radius * len
                seg += [CGPoint(x: 0, y: y), CGPoint(x: -l * 0.8, y: y - l * 0.6),
                        CGPoint(x: 0, y: y), CGPoint(x: l * 0.8, y: y - l * 0.6)]
            }
            g.strokeLineSegments(between: seg)
            g.restoreGState()
        }
        g.restoreGState()
    }

    /// 雪国：冰蓝的墙上大大小小的雪花，深一点的几团雾，零星的小雪点
    private static func snowflakes(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        for _ in 0..<5 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 200...340)
            tiled(size) { dx, dy in haze(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, t.accent2, 0.35) }
        }
        for _ in 0..<34 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 16...46), angle = r(&rng, 0...1.05)
            let color = t.accent.withAlphaComponent(r(&rng, 0.5...0.9))
            tiled(size) { dx, dy in flake(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, angle, color, max(1.5, radius / 11)) }
        }
        for _ in 0..<160 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 1...2.6)
            g.setFillColor(t.accent.withAlphaComponent(r(&rng, 0.3...0.7)).cgColor)
            tiled(size) { dx, dy in g.fillEllipse(in: CGRect(x: c.x + dx - radius, y: c.y + dy - radius, width: 2 * radius, height: 2 * radius)) }
        }
    }

    /// 深海：上浅下深的海水，一道道弯弯的光纹（水面透下来的焦散）和浮着的小光点。
    /// 光纹的波长都能整除 1024，左右接得上；上下的明暗用余弦，也接得上
    private static func waves(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        let deep = mix(t.wallColor, t.accent2, 0.7)
        for y in stride(from: CGFloat(0), to: size, by: 8) {
            mix(t.wallColor, deep, 0.5 + 0.5 * cos(y / size * 2 * .pi)).setFill()
            g.fill(CGRect(x: 0, y: y, width: size, height: 8))
        }
        g.setLineCap(.round)
        for _ in 0..<26 {
            let y0 = r(&rng, 0...size), amp = r(&rng, 10...34), phase = r(&rng, 0...6.3)
            let waves = CGFloat([1, 2, 2, 3, 4].randomElement(using: &rng)!), amp2 = r(&rng, 3...10)
            let alpha = r(&rng, 0.12...0.32), width = r(&rng, 1.5...5)
            g.setStrokeColor(t.accent.withAlphaComponent(alpha).cgColor)
            g.setLineWidth(width)
            for dy in [-size, 0, size] {
                let path = CGMutablePath()
                for x in stride(from: CGFloat(0), through: size, by: 8) {
                    let a = x / size * 2 * .pi
                    let p = CGPoint(x: x, y: y0 + dy + amp * sin(a * waves + phase) + amp2 * sin(a * waves * 3 + phase * 2))
                    if x == 0 {
                        path.move(to: p)
                    } else {
                        path.addLine(to: p)
                    }
                }
                g.addPath(path)
                g.strokePath()
            }
        }
        for _ in 0..<70 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 3...9), a = r(&rng, 0.15...0.4)
            tiled(size) { dx, dy in haze(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, t.accent, a) }
        }
    }

    /// 霓虹：近黑的墙，品红的横线、青色的竖线组成网格，线带一圈光晕，交点更亮；底下几团暗紫的光
    private static func grid(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        for _ in 0..<4 {
            let c = CGPoint(x: r(&rng, 0...size), y: r(&rng, 0...size)), radius = r(&rng, 260...420)
            tiled(size) { dx, dy in haze(g, CGPoint(x: c.x + dx, y: c.y + dy), radius, mix(t.accent, t.accent2, 0.5), 0.12) }
        }
        let step: CGFloat = 128
        let lines: [(UIColor, Bool)] = [(t.accent, true), (t.accent2, false)]
        for (color, across) in lines {
            for (width, alpha, blur) in [(9, 0.12, 18), (4, 0.35, 8), (1.6, 0.95, 0)] as [(CGFloat, CGFloat, CGFloat)] {
                g.saveGState()
                g.setShadow(offset: .zero, blur: blur, color: color.cgColor)
                g.setStrokeColor(mix(color, .white, width < 2 ? 0.35 : 0).withAlphaComponent(alpha).cgColor)
                g.setLineWidth(width)
                for k in 0...Int(size / step) {
                    let p = CGFloat(k) * step
                    g.strokeLineSegments(between: across ? [CGPoint(x: -20, y: p), CGPoint(x: size + 20, y: p)]
                                                         : [CGPoint(x: p, y: -20), CGPoint(x: p, y: size + 20)])
                }
                g.restoreGState()
            }
        }
        for i in 0...Int(size / step) { for j in 0...Int(size / step) {
            haze(g, CGPoint(x: CGFloat(i) * step, y: CGFloat(j) * step), 10, .white, 0.5)
        } }
    }

    /// 秋林：竖着拼的木板，每块深浅不一，带细细的木纹和一两个节疤，板缝深色。
    /// 板宽能整除 1024，木纹是正弦，上下接得上
    private static func boards(_ g: CGContext, _ t: RhythmTheme, _ size: CGFloat, _ rng: inout SeededRandom) {
        let w: CGFloat = 128
        for k in 0..<Int(size / w) {
            let x = CGFloat(k) * w
            mix(t.wallColor, k % 2 == 0 ? t.accent2 : t.accent, r(&rng, 0.05...0.3)).setFill()
            g.fill(CGRect(x: x, y: 0, width: w, height: size))
            g.setLineWidth(1.2)
            for _ in 0..<9 {
                let x0 = x + r(&rng, 8...(w - 8)), amp = r(&rng, 2...6), phase = r(&rng, 0...6.3)
                let waves = CGFloat(Int.random(in: 1...3, using: &rng))
                g.setStrokeColor(t.accent.withAlphaComponent(r(&rng, 0.15...0.35)).cgColor)
                let path = CGMutablePath()
                for y in stride(from: CGFloat(0), through: size, by: 8) {
                    let p = CGPoint(x: x0 + amp * sin(y / size * 2 * .pi * waves + phase), y: y)
                    if y == 0 {
                        path.move(to: p)
                    } else {
                        path.addLine(to: p)
                    }
                }
                g.addPath(path)
                g.strokePath()
            }
            for _ in 0..<Int.random(in: 1...2, using: &rng) {
                let c = CGPoint(x: x + r(&rng, 30...(w - 30)), y: r(&rng, 60...(size - 60))), rx = r(&rng, 6...11)
                for (scale, alpha) in [(2.2, 0.18), (1.5, 0.3), (1, 0.6)] as [(CGFloat, CGFloat)] {
                    g.setStrokeColor(t.accent.withAlphaComponent(alpha).cgColor)
                    g.setLineWidth(1.4)
                    g.strokeEllipse(in: CGRect(x: c.x - rx * scale, y: c.y - rx * scale * 1.8, width: 2 * rx * scale, height: 3.6 * rx * scale))
                }
                g.setFillColor(t.accent.withAlphaComponent(0.7).cgColor)
                g.fillEllipse(in: CGRect(x: c.x - rx * 0.6, y: c.y - rx, width: rx * 1.2, height: rx * 2))
            }
        }
        let seam = mix(t.accent, .black, 0.4)
        for k in 0..<Int(size / w) {
            let x = CGFloat(k) * w
            seam.setFill()
            g.fill(CGRect(x: x, y: 0, width: 4, height: size))
            mix(t.wallColor, .white, 0.2).withAlphaComponent(0.5).setFill()
            g.fill(CGRect(x: x + 4, y: 0, width: 1.5, height: size))
        }
    }
}

extension RhythmArt {
    /// 一片花瓣（白色，粒子按主题染色）：一头圆一头带个小缺口
    static let petal: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { c in
        let g = c.cgContext
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 30))
        path.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 2, y: 22), control2: CGPoint(x: 3, y: 6))
        path.addLine(to: CGPoint(x: 16, y: 7))
        path.addLine(to: CGPoint(x: 20, y: 3))
        path.addCurve(to: CGPoint(x: 16, y: 30), control1: CGPoint(x: 29, y: 6), control2: CGPoint(x: 30, y: 22))
        g.addPath(path)
        g.setFillColor(UIColor.white.cgColor)
        g.fillPath()
        g.setFillColor(UIColor(white: 0.85, alpha: 0.6).cgColor)
        g.fillEllipse(in: CGRect(x: 13, y: 20, width: 6, height: 8))
    }

    /// 一片枫叶（白色，粒子按主题染色）：五个尖，带叶柄和叶脉
    static let leaf: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { c in
        let g = c.cgContext
        let center = CGPoint(x: 24, y: 26)
        let path = CGMutablePath()
        let tips: [(CGFloat, CGFloat)] = [(-90, 22), (-35, 19), (20, 15), (160, 15), (215, 19)]
        let notch: CGFloat = 8
        for (k, tip) in tips.enumerated() {
            let a = tip.0 * .pi / 180
            let next = tips[(k + 1) % tips.count].0 * .pi / 180
            var mid = (a + (next < a ? next + 2 * .pi : next)) / 2
            if k == 2 {
                mid = .pi / 2
            }
            let p = CGPoint(x: center.x + tip.1 * cos(a), y: center.y + tip.1 * sin(a))
            if k == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
            path.addLine(to: CGPoint(x: center.x + notch * cos(mid), y: center.y + notch * sin(mid)))
        }
        path.closeSubpath()
        g.addPath(path)
        g.setFillColor(UIColor.white.cgColor)
        g.fillPath()
        g.setStrokeColor(UIColor(white: 0.7, alpha: 0.8).cgColor)
        g.setLineWidth(1.2)
        g.setLineCap(.round)
        for tip in tips {
            let a = tip.0 * .pi / 180
            g.strokeLineSegments(between: [center, CGPoint(x: center.x + tip.1 * 0.8 * cos(a), y: center.y + tip.1 * 0.8 * sin(a))])
        }
        g.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
        g.setLineWidth(2)
        g.strokeLineSegments(between: [center, CGPoint(x: 24, y: 46)])
    }

    /// 一个气泡：透明的球，一圈亮边，左上一点高光
    static let bubble: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { c in
        let g = c.cgContext
        let colors = [UIColor.white.withAlphaComponent(0.05).cgColor, UIColor.white.withAlphaComponent(0.15).cgColor,
                      UIColor.white.withAlphaComponent(0.85).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 0.88, 1])!
        g.drawRadialGradient(grad, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                             endCenter: CGPoint(x: 16, y: 16), endRadius: 15, options: [])
        g.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        g.fillEllipse(in: CGRect(x: 9, y: 8, width: 6, height: 4))
    }
}
