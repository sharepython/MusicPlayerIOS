import SceneKit
import UIKit

/// 各个主题的房子外面：星夜是天文台（圆顶开一道缝、伸出一架望远镜），樱花是两层飞檐的小楼挂着灯笼，
/// 雪国是积雪的尖顶挂满冰棱，深海是扇贝壳屋顶缠着海草，霓虹是平顶描着灯管、顶上一块招牌，秋林是一朵大蘑菇。
/// 门上的 CW / CC 和门外台子上的字不在这里，一直是原来的样子
extension RhythmScene {
    /// 墙纸、墙、屋顶的颜色按主题换；门、地毯、家具这些还是原来的，门上的字才看得清
    func lookStyle(_ s: HouseStyle) -> HouseStyle {
        let cat = s.pet == .kitty
        func c(_ pup: UIColor, _ kitty: UIColor) -> UIColor {
            cat ? kitty : pup
        }
        let colors: (paper: UIColor, pattern: UIColor, wall: UIColor, roof: UIColor, ridge: UIColor, chimney: UIColor)
        switch theme.look {
        case .classic: return s
        case .crystal:
            colors = (.rgb(0.88, 0.9, 1), c(.rgb(0.98, 0.86, 0.5), .rgb(0.78, 0.76, 1)), .rgb(0.82, 0.84, 0.98),
                      c(.rgb(0.6, 0.66, 0.88), .rgb(0.68, 0.6, 0.9)), .rgb(0.98, 0.8, 0.42), s.chimney)
        case .blossom:
            // 抹茶色的墙上开着粉花，红木色的侧墙；白色的小狗小猫在上面才看得清
            colors = (c(.rgb(0.7, 0.8, 0.52), .rgb(0.62, 0.76, 0.6)), .rgb(1, 0.76, 0.84), .rgb(0.84, 0.5, 0.4),
                      c(.rgb(0.42, 0.33, 0.4), .rgb(0.36, 0.38, 0.46)), .rgb(0.86, 0.26, 0.24), s.chimney)
        case .ice:
            // 屋里是深一点的冰蓝，白雪花墙纸；外面的屋顶还是白雪
            colors = (c(.rgb(0.5, 0.66, 0.88), .rgb(0.56, 0.6, 0.88)), .rgb(0.8, 0.9, 1), .rgb(0.46, 0.6, 0.84),
                      s.roof, s.ridge, .rgb(0.72, 0.76, 0.84))
        case .reef:
            colors = (.rgb(0.9, 0.97, 0.96), .rgb(0.68, 0.88, 0.9), .rgb(0.99, 0.91, 0.86),
                      c(.rgb(1, 0.74, 0.66), .rgb(1, 0.82, 0.62)), .rgb(1, 0.93, 0.88), s.chimney)
        case .neon:
            colors = (.rgb(0.36, 0.28, 0.52), c(.rgb(0.95, 0.45, 0.85), .rgb(0.4, 0.85, 1)), .rgb(0.3, 0.24, 0.44),
                      .rgb(0.14, 0.11, 0.22), .rgb(0.2, 0.16, 0.3), s.chimney)
        case .forest:
            colors = (.rgb(0.98, 0.93, 0.82), c(.rgb(0.72, 0.82, 0.5), .rgb(0.95, 0.7, 0.45)), .rgb(0.96, 0.89, 0.75),
                      c(.rgb(0.86, 0.26, 0.2), .rgb(0.9, 0.52, 0.22)), .rgb(1, 0.98, 0.92), s.chimney)
        }
        return HouseStyle(paper: colors.paper, pattern: colors.pattern, wall: colors.wall, roof: colors.roof, ridge: colors.ridge,
                          rug: s.rug, rugEdge: s.rugEdge, chimney: colors.chimney, door: s.door, sofa: s.sofa, quilt: s.quilt,
                          ink: s.ink, sign: s.sign, picture: s.picture, pet: s.pet)
    }

    /// 墙纸上的花样（64×64 一格），原来的波点、条纹返回 false 让原来的代码画
    func lookPattern(_ g: CGContext, _ s: HouseStyle) -> Bool {
        func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            let p = RhythmArt.starPath(r, inner: 0.4)
            p.apply(CGAffineTransform(translationX: x, y: y))
            g.addPath(p.cgPath)
            g.fillPath()
        }
        let spots = [(CGFloat(16), CGFloat(16)), (48, 48)]
        switch theme.look {
        case .classic: return false
        case .crystal:
            for (x, y) in spots { star(x, y, 7) }
            for (x, y) in [(CGFloat(46), CGFloat(12)), (14, 46), (32, 30)] { g.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)) }
        case .blossom:
            for (x, y) in spots {
                for k in 0..<5 {
                    let a = CGFloat(k) * 2 * .pi / 5
                    g.fillEllipse(in: CGRect(x: x + 4.5 * sin(a) - 3.5, y: y - 4.5 * cos(a) - 3.5, width: 7, height: 7))
                }
            }
        case .ice:
            g.setStrokeColor(theme.house(s.pattern).cgColor)
            g.setLineWidth(2)
            g.setLineCap(.round)
            for (x, y) in spots {
                for k in 0..<3 {
                    let a = CGFloat(k) * .pi / 3
                    g.move(to: CGPoint(x: x - 8 * cos(a), y: y - 8 * sin(a)))
                    g.addLine(to: CGPoint(x: x + 8 * cos(a), y: y + 8 * sin(a)))
                }
            }
            g.strokePath()
        case .reef:
            g.setStrokeColor(theme.house(s.pattern).cgColor)
            g.setLineWidth(2)
            for (x, y, r) in [(CGFloat(16), CGFloat(18), CGFloat(6)), (46, 44, 8), (30, 50, 3), (52, 14, 3)] {
                g.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        case .neon:
            g.fill(CGRect(x: 0, y: 0, width: 64, height: 2))
            g.fill(CGRect(x: 0, y: 0, width: 2, height: 64))
            if s.stripes {
                g.fill(CGRect(x: 31, y: 0, width: 2, height: 64))
            }
        case .forest:
            for (x, y, a) in [(CGFloat(16), CGFloat(18), CGFloat(0.6)), (48, 46, -0.7)] {
                g.saveGState()
                g.translateBy(x: x, y: y)
                g.rotate(by: a)
                g.fillEllipse(in: CGRect(x: -9, y: -4, width: 18, height: 8))
                g.restoreGState()
            }
        }
        return true
    }

    /// 屋顶、牌子。classic 和雪国走原来的尖屋顶，雪国再加积雪和冰棱
    @MainActor func lookRoof(_ k: Kit, _ s: HouseStyle, _ f: Frame, trim: SCNMaterial) {
        switch theme.look {
        case .classic: break
        case .ice: iceRoof(k, s, f)
        case .crystal: observatory(k, s, f)
        case .blossom: pagoda(k, s, f)
        case .reef: shellRoof(k, s, f)
        case .neon: neonRoof(k, s, f)
        case .forest: mushroomRoof(k, s, f)
        }
    }

    /// 平面路径（屏幕点，y 朝上）沿 z 拉出 d 厚，正中放在 c
    @MainActor @discardableResult func extrude(_ k: Kit, _ path: UIBezierPath, _ d: Float, _ c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
        path.flatness = 0.3
        let g = SCNShape(path: path, extrusionDepth: CGFloat(d))
        g.materials = [m]
        let n = k.add(SCNNode(geometry: g), c)
        n.simdScale = [k.u, k.u, k.u]
        return n
    }

    /// 半个椭球，底面正中在 c，三个半径 r（屏幕点）
    @MainActor @discardableResult func cupola(_ k: Kit, _ r: SIMD3<Float>, _ c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
        let g = RhythmArt.dome(rings: 12, sides: 32)
        g.materials = [m]
        let n = k.add(SCNNode(geometry: g), c)
        n.simdScale = r * k.u
        return n
    }

    /// 一串点（屏幕点）连成的软管
    @MainActor func strand(_ k: Kit, _ pts: [SIMD3<Float>], _ r: Float, _ m: SCNMaterial) {
        let n = SCNNode(geometry: RhythmArt.sweep(pts.map { $0 * k.u }, radius: r * k.u, sides: 6))
        n.geometry?.materials = [m]
        k.house.addChildNode(n)
    }

    @MainActor func hangSign(_ k: Kit, _ s: HouseStyle, _ c: SIMD3<Float>) {
        k.box([50, 15, 1.6], c, signMaterial(s.sign), 0.6)
    }

    /// 雪国：屋檐两头堆着雪、前沿挂一排冰棱，烟囱顶上一团雪
    @MainActor private func iceRoof(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, rise = f.rise, z = f.front + 9
        // 冰棱挂在白墙前面，颜色要比墙蓝一些才看得出来
        let ice = Self.lit(.rgb(0.6, 0.8, 1), shine: 120, clear: 0.9)
        let snow = k.material(.rgb(0.98, 0.99, 1), 8)
        for side: Float in [-1, 1] {
            for (j, t) in stride(from: Float(0.06), through: 0.86, by: 0.1).enumerated() {
                let len = [Float(6), 11, 8, 13, 7][j % 5]
                let cone = SCNCone(topRadius: CGFloat(2.4 * k.u), bottomRadius: 0, height: CGFloat(len * k.u))
                cone.radialSegmentCount = 6
                cone.materials = [ice]
                k.add(SCNNode(geometry: cone), [side * (W / 2 + 8) * (1 - t), T + (rise + 4) * t - 6 - len / 2, z])
            }
            k.blob([12, 6, f.depth / 2 + 4], [side * (W / 2 + 6), T - 2, f.zc], snow)
        }
        k.blob([9, 4, 9], [-k.open * W * 0.27, T + rise * 0.46 + 23, f.back + 16], snow)
    }
}
