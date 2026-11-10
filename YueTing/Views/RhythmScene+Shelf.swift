import SceneKit
import UIKit

/// 小狗、小猫家底下那块搁板按主题换：星夜是玻璃板描金边、底下飘星星，樱花是浅木板镶粉边、竹子托着，
/// 雪国是冰板盖着雪挂冰棱，深海是浮木板缀着贝壳，霓虹是深色板描两道灯管，秋林是木板边上一层苔藓、长两朵小蘑菇。
/// 台子上的 Class Winner / Challenge Certificate 不在这里，一直是原来的样子
extension RhythmScene {
    /// 改好 m（搁板的材质），装饰和托架加进 fixed。返回 false 时还用原来的金属托架
    @MainActor func lookShelf(_ m: SCNMaterial, from a: CGFloat, to b: CGFloat, y top: CGFloat, thick: CGFloat, depth: CGFloat,
                              z: CGFloat, fixed: SCNNode) -> Bool {
        let u = Self.unit, front = z + depth / 2, mats = materials(), tm = trackMaterials(mats)
        // 顺着前沿一根棍；dy 从顶面往下
        func edge(_ dy: CGFloat, _ mat: SCNMaterial, _ r: CGFloat = 1.1, dz: CGFloat = 0) {
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: a, y: top + dy, z: front + dz)), v(Point3(x: b, y: top + dy, z: front + dz)), radius: r * u, material: mat))
        }

        // 前沿上隔一段放一个
        func along(_ step: CGFloat, inset: CGFloat = 10, _ f: (Int, CGFloat) -> Void) {
            for (j, x) in stride(from: a + inset, through: b - inset, by: step).enumerated() { f(j, x) }
        }

        func supports(_ mat: SCNMaterial, _ r: CGFloat = 1.6) {
            for x in [a + 14, b - 14] {
                let y = top + thick + 1.5
                let front = v(Point3(x: x, y: y, z: z + depth / 2 - 8)), back = v(Point3(x: x, y: y, z: z - depth / 2))
                let foot = v(Point3(x: x, y: y + 26, z: 0)), wall = v(Point3(x: x, y: y, z: 0))
                for (s, e) in [(front, back), (back, wall), (front, foot)] { fixed.addChildNode(RhythmArt.rod(s, e, radius: r * u, material: mat)) }
            }
        }
        m.transparency = 1
        switch theme.look {
        case .classic: return false
        case .crystal:
            m.diffuse.contents = theme.accent2.mixed(.white, 0.35)
            m.transparency = 0.7
            m.reflective.contents = RhythmArt.chrome
            m.reflective.intensity = 0.35
            edge(0, tm.accent)
            edge(thick, tm.rail, 0.8)
            along(36, inset: 20) { j, x in
                fixed.addChildNode(starNode(Point3(x: x, y: top + thick + 12 + CGFloat(j % 2) * 7, z: front - 6), radius: j % 2 == 0 ? 5 : 3.5, tm.accent))
            }
        case .blossom:
            m.diffuse.contents = UIColor.rgb(0.95, 0.84, 0.68)
            edge(0.5, tm.accent, 1.3)
            supports(tm.post, 2.2)
            along(30) { _, x in
                fixed.addChildNode(RhythmArt.knob(v(Point3(x: x, y: top + thick / 2, z: front + 0.5)), radius: 1.6 * u, material: tm.accent))
            }
        case .ice:
            m.diffuse.contents = UIColor.rgb(0.84, 0.93, 1)
            m.transparency = 0.85
            m.reflective.contents = RhythmArt.chrome
            m.reflective.intensity = 0.4
            along(12, inset: 4) { j, x in
                fixed.addChildNode(blob([7, 3, 4], at: v(Point3(x: x, y: top + 0.5, z: front - 1)) / Float(u), tm.accent))
                fixed.addChildNode(icicle(Point3(x: x + 4, y: top + thick, z: front - 3), length: [6, 11, 8, 13][j % 4], tm.rail))
            }
            supports(mats.metal)
        case .reef:
            m.diffuse.contents = UIColor.rgb(0.72, 0.6, 0.46)
            let shell = Self.lit(.rgb(1, 0.86, 0.8), shine: 50), coral = Self.lit(.rgb(1, 0.5, 0.42), shine: 20)
            along(44, inset: 18) { j, x in
                let c = v(Point3(x: x, y: top + thick / 2 + 1, z: front + 0.5))
                if j % 2 == 0 {
                    let g = RhythmArt.dome(rings: 5, sides: 14)
                    g.materials = [shell]
                    let n = SCNNode(geometry: g)
                    n.simdPosition = c
                    n.simdScale = SIMD3(5, 4, 2) * Float(u)
                    n.eulerAngles.x = .pi / 2
                    fixed.addChildNode(n)
                } else {
                    let g = SCNShape(path: RhythmArt.starPath(5 * u, inner: 0.42), extrusionDepth: 1.5 * u)
                    g.materials = [coral]
                    let n = SCNNode(geometry: g)
                    n.simdPosition = c
                    n.eulerAngles.z = Float(j)
                    fixed.addChildNode(n)
                }
            }
            supports(tm.post)
        case .neon:
            m.diffuse.contents = theme.shelf ?? UIColor.rgb(0.3, 0.22, 0.5)
            edge(0, tm.accent, 1)
            edge(thick, tm.rail, 1)
            for x in [a + 20, b - 20] {
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: x, y: top + thick, z: z - depth / 2 + 4)), v(Point3(x: x, y: top + 30, z: 0)),
                                                 radius: 0.6 * u, material: tm.post))
            }
        case .forest:
            m.diffuse.contents = UIColor.rgb(0.8, 0.64, 0.46)
            edge(-0.5, Self.lit(.rgb(0.45, 0.6, 0.3), shine: 4), 1.8, dz: -1.5)
            // 前沿上长着几朵扁扁的树舌，不挡台子上的字
            let fungus = Self.lit(.rgb(0.86, 0.6, 0.36), shine: 10)
            along(26, inset: 16) { j, x in
                let g = RhythmArt.dome(rings: 5, sides: 16)
                g.materials = [fungus]
                let n = SCNNode(geometry: g)
                n.simdPosition = v(Point3(x: x, y: top + thick * (j % 2 == 0 ? 0.35 : 0.75), z: front))
                n.simdScale = SIMD3(j % 2 == 0 ? 7 : 5, 1.8, 4) * Float(u)
                fixed.addChildNode(n)
            }
            for x in [a + 24, b - 24] {
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: x, y: top + thick, z: z - depth / 2 + 6)), v(Point3(x: x + 8, y: top + 34, z: 0)),
                                                 radius: 2.6 * u, material: tm.post))
            }
        }
        return true
    }
}
