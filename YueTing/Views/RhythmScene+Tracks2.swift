import SceneKit
import UIKit

/// 各个主题的木板和管子
extension RhythmScene {
    /// 原来那样的 L 形托架：板子底下一根往后、一根斜着往上插进墙里
    private func brackets(_ k: RhythmStage.Track, thick: CGFloat, depth: CGFloat, step: CGFloat, _ tm: TrackMaterials, _ fixed: SCNNode) {
        let u = Self.unit, z = RhythmStage.trackZ
        for s in stations(k, step: step) {
            let p = k.at(s), y = p.y + thick + 1.5
            let front = v(Point3(x: p.x, y: y, z: z + depth / 2 - 8)), back = v(Point3(x: p.x, y: y, z: z - depth / 2))
            let foot = v(Point3(x: p.x, y: y + 22, z: 0))
            fixed.addChildNode(RhythmArt.rod(front, back, radius: 1.6 * u, material: tm.post))
            fixed.addChildNode(RhythmArt.rod(back, foot, radius: 1.6 * u, material: tm.post))
            fixed.addChildNode(RhythmArt.rod(back, v(Point3(x: p.x, y: y, z: 0)), radius: 1.3 * u, material: tm.post))
            if tm.mounts {
                fixed.addChildNode(RhythmArt.mount(foot, radius: 5 * u, material: tm.post))
            }
        }
    }

    func lookPlank(_ k: RhythmStage.Track, fixed: SCNNode, shade: SCNNode, mats: Materials, _ tm: TrackMaterials) {
        let u = Float(Self.unit), a = k.path[0], b = k.path[k.path.count - 1], z = RhythmStage.trackZ
        let len = Float(hypot(b.x - a.x, b.y - a.y) + 24), depth: Float = 56, thick: Float = 8
        // 板子自己的坐标：原点在顶面正中（小球滚的那条线），x 顺着板子，y 朝上，z 朝外，单位屏幕点
        let plank = SCNNode()
        plank.simdPosition = v(Point3(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: z))
        // 板子往左走时 atan2 接近 ±π，会把板子上下翻过来；只取 ±90° 以内的斜度
        var tilt = Float(atan2(b.y - a.y, b.x - a.x))
        if tilt > .pi / 2 {
            tilt -= .pi
        } else if tilt < -.pi / 2 {
            tilt += .pi
        }
        plank.simdOrientation = simd_quatf(angle: -tilt, axis: [0, 0, 1])
        @discardableResult func put(_ g: SCNGeometry, _ m: SCNMaterial, _ c: SIMD3<Float>) -> SCNNode {
            part(g, m, c, to: plank)
        }

        func slab(_ m: SCNMaterial, chamfer: CGFloat = 1) {
            put(SCNBox(width: CGFloat(len * u), height: CGFloat(thick * u), length: CGFloat(depth * u), chamferRadius: chamfer * CGFloat(u)), m, [0, -thick / 2, 0])
        }

        func edge(_ y: Float, _ z: Float, _ m: SCNMaterial, _ r: CGFloat = 0.9) {
            plank.addChildNode(RhythmArt.rod(SIMD3(-len / 2, y, z) * u, SIMD3(len / 2, y, z) * u, radius: r * CGFloat(u), material: m))
        }
        let steps = stride(from: -len / 2 + 12, through: len / 2 - 12, by: 14).map { $0 }
        switch theme.look {
        case .classic: break
        case .crystal:
            let glass = Self.lit(theme.accent2.mixed(.white, 0.3), shine: 120, clear: 0.45)
            glass.reflective.contents = RhythmArt.chrome
            glass.reflective.intensity = 0.4
            slab(glass)
            for zz in [depth / 2, -depth / 2] { edge(0, zz, tm.rail) }
            for (j, x) in steps.enumerated() where j % 3 == 1 {
                let star = starNode(Point3(x: 0, y: 0, z: 0), radius: 4, tm.accent)
                star.simdPosition = SIMD3(x, -16 - Float(j % 2) * 5, depth / 2 - 6) * u
                plank.addChildNode(star)
            }
        case .blossom:
            let bamboo = Self.lit(.rgb(0.68, 0.8, 0.45), shine: 50)
            for zz in stride(from: -depth / 2 + 4, through: depth / 2 - 4, by: 8) {
                put(SCNCylinder(radius: 4 * CGFloat(u), height: CGFloat(len * u)), bamboo, [0, -4, zz]).eulerAngles.z = .pi / 2
            }
            for x in [-len * 0.36, len * 0.36] { put(SCNBox(width: 3 * CGFloat(u), height: 9.5 * CGFloat(u), length: CGFloat((depth + 1) * u), chamferRadius: CGFloat(u)), tm.accent, [x, -4, 0]) }
            brackets(k, thick: CGFloat(thick), depth: CGFloat(depth), step: 110, tm, fixed)
        case .ice:
            slab(tm.rail, chamfer: 3)
            for (j, x) in steps.enumerated() {
                plank.addChildNode(blob([8, 3, 4], at: [x, -0.5, depth / 2 - 1], tm.accent))
                put(SCNCone(topRadius: 1.8 * CGFloat(u), bottomRadius: 0, height: CGFloat([6, 11, 8][j % 3] * u)), tm.rail,
                    [x + 5, -thick - [6, 11, 8][j % 3] / 2, depth / 2 - 3])
            }
            brackets(k, thick: CGFloat(thick), depth: CGFloat(depth), step: 110, tm, fixed)
        case .reef:
            let wood = SCNMaterial()
            wood.lightingModel = .lambert
            wood.diffuse.contents = UIColor.rgb(0.66, 0.52, 0.38)
            slab(wood, chamfer: 3)
            let coral = Self.lit(.rgb(1, 0.5, 0.42), shine: 20)
            let sea = SCNShape(path: RhythmArt.starPath(7 * CGFloat(u), inner: 0.42), extrusionDepth: 2 * CGFloat(u))
            put(sea, coral, [-len * 0.22, -thick / 2, depth / 2 + 1]).eulerAngles.z = 0.3
            put(RhythmArt.dome(rings: 5, sides: 14), Self.lit(.rgb(1, 0.88, 0.8), shine: 40), [len * 0.25, -thick + 1, depth / 2 + 0.5])
                .simdScale = SIMD3(7, 6, 2.5) * u
            brackets(k, thick: CGFloat(thick), depth: CGFloat(depth), step: 110, tm, fixed)
        case .neon:
            slab(Self.lit(.rgb(0.08, 0.06, 0.14), shine: 100), chamfer: 0.4)
            edge(0, depth / 2, tm.accent)
            edge(-thick, depth / 2, tm.rail)
            edge(0, -depth / 2, tm.rail, 0.6)
            for s in stations(k, step: 80) {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y + CGFloat(thick), z: z - 20)), v(Point3(x: p.x, y: p.y + 24, z: 0)),
                                                 radius: 0.6 * Self.unit, material: tm.post))
            }
        case .forest:
            // 一根横着的圆木，两头是年轮
            let r: Float = 11
            let log = SCNCylinder(radius: CGFloat(r * u), height: CGFloat(len * u))
            log.radialSegmentCount = 16
            let bark = Self.barkMaterial(len / 40), cut = Self.lit(.white, shine: 4)
            cut.diffuse.contents = RhythmArt.rings
            log.materials = [bark, cut, cut]
            let n = SCNNode(geometry: log)
            n.simdPosition = [0, -r * u, 0]
            n.eulerAngles.z = .pi / 2
            plank.addChildNode(n)
            let cap = Self.lit(.rgb(0.85, 0.35, 0.22), shine: 30), stem = Self.lit(.rgb(0.97, 0.9, 0.78), shine: 6)
            for (x, s) in [(-len * 0.3, Float(1)), (-len * 0.3 + 6, 0.7), (len * 0.28, 0.85)] {
                // 长在圆木朝外那一侧，往外歪一点，矮到碰不到滚过去的小球
                let root: SIMD3<Float> = [x, -r + sqrt(r * r - pow(r * 0.95, 2)), r * 0.95]
                put(SCNCylinder(radius: 1.4 * CGFloat(u * s), height: 6 * CGFloat(u * s)), stem, root + [0, 2 * s, 0.6]).eulerAngles.x = 0.5
                put(RhythmArt.dome(rings: 5, sides: 14), cap, root + [0, 5 * s, 2 * s]).simdScale = SIMD3(5, 3.5, 5) * u * s
            }
            for s in stations(k, step: 110) {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y + CGFloat(r), z: z - CGFloat(r) + 2)), v(Point3(x: p.x + 8, y: p.y + 30, z: 0)),
                                                 radius: 2.4 * Self.unit, material: tm.post))
            }
        }
        // 合并成一个节点时中间这层空节点的变换会丢，先把每块摆到场景里的位置再挂到 fixed 上
        for n in plank.childNodes {
            n.simdTransform = plank.simdTransform * n.simdTransform
            fixed.addChildNode(n)
        }
        trackShadow(k, width: 18, down: CGFloat(thick) + 8, shade: shade, mats: mats)
    }

    func lookTube(_ k: RhythmStage.Track, row: SCNNode, fixed: SCNNode, shade: SCNNode, mats: Materials, _ tm: TrackMaterials) {
        let u = Self.unit, r = RhythmStage.ballRadius + 7, look = theme.look
        let color: UIColor = [.crystal: theme.accent2.mixed(.white, 0.5), .neon: .rgb(0.2, 0.14, 0.32),
                              .blossom: .rgb(0.82, 0.95, 0.8)][look] ?? theme.tube
        let clear: CGFloat = [.crystal: 0.3, .neon: 0.32, .ice: 0.55][look] ?? theme.tubeClear
        tubeBody(k, row: row, color: color, clear: clear)
        func center(_ s: CGFloat) -> SIMD3<Float> {
            let p = k.at(s)
            return v(Point3(x: p.x, y: p.y - RhythmStage.ballRadius, z: p.z))
        }
        let ends = [CGFloat(0.04), 0.96]
        switch look {
        case .classic: break
        case .crystal:
            for s in stations(k, step: 40) { fixed.addChildNode(hoop(center(s), axis: tangent(k, s), radius: r + 1, pipe: 1, tm.accent)) }
        case .blossom:
            for s in stations(k, step: 28) { fixed.addChildNode(hoop(center(s), axis: tangent(k, s), radius: r + 0.5, pipe: 2.2, tm.post)) }
        case .ice:
            for (j, s) in stations(k, step: 16).enumerated() {
                let c = center(s)
                let lump = blob([7, 3, 6], at: .zero, tm.accent)
                lump.simdPosition = c + SIMD3(0, Float(r * u) - 0.005, 0)
                fixed.addChildNode(lump)
                let p = k.at(s)
                fixed.addChildNode(icicle(Point3(x: p.x, y: p.y - RhythmStage.ballRadius + r - 1, z: p.z + 6), length: [6, 11, 8][j % 3], tm.rail))
            }
        case .reef:
            let coral = Self.lit(.rgb(1, 0.55, 0.5), shine: 20)
            for s in stations(k, step: 36) { fixed.addChildNode(hoop(center(s), axis: tangent(k, s), radius: r + 1.5, pipe: 2.6, coral)) }
        case .neon:
            for (j, s) in stations(k, step: 22).enumerated() {
                fixed.addChildNode(hoop(center(s), axis: tangent(k, s), radius: r + 0.8, pipe: 1.1, Self.flat(theme.cards[j % theme.cards.count])))
            }
        case .forest:
            // 一根藤绕着管子盘上去，藤上隔一段一片叶子
            let n = 120
            var vine: [SIMD3<Float>] = []
            for j in 0...n {
                let s = CGFloat(j) / CGFloat(n), t = tangent(k, s)
                let side = simd_normalize(simd_cross(t, [0, 0, 1])), up = simd_cross(side, t), a = Float(j) * 0.32
                vine.append(center(s) + (side * cos(a) + up * sin(a)) * Float((r + 1.5) * u))
            }
            let stem = SCNNode(geometry: RhythmArt.sweep(vine, radius: Float(1.2 * u), sides: 5))
            stem.geometry?.materials = [Self.lit(.rgb(0.4, 0.55, 0.25), shine: 10)]
            fixed.addChildNode(stem)
            let leaf = Self.lit(.rgb(0.5, 0.68, 0.3), shine: 10)
            for j in stride(from: 6, to: n, by: 9) {
                let l = blob([4.5, 1, 2.5], at: .zero, leaf)
                l.simdPosition = vine[j]
                l.eulerAngles = SCNVector3(Float(j) * 0.7, Float(j), 0.5)
                fixed.addChildNode(l)
            }
        }
        // 两头各一根杆插进墙里；星夜、霓虹的管子飘着
        if look != .crystal && look != .neon {
            for s in ends {
                let back = center(s) - SIMD3<Float>(0, 0, Float(r * u))
                fixed.addChildNode(RhythmArt.rod(back, SIMD3(back.x, back.y, 0), radius: 1.6 * u, material: tm.post))
                if tm.mounts {
                    fixed.addChildNode(RhythmArt.mount(back, radius: 5 * u, material: tm.post))
                }
            }
        }
        trackShadow(k, width: 2 * r + 10, down: 10, shade: shade, mats: mats)
    }
}
