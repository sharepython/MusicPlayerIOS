import SceneKit
import UIKit

/// 各个主题的架子：小球走的线（Track.path）不变，换成别的东西搭。
/// 星夜：发光的光轨、玻璃桥，底下飘着小星星，不用支架；樱花：竹子、竹筏、竹节管；雪国：冰轨挂冰棱、积雪的冰板；
/// 深海：缀着珍珠的绳子、浮木板上趴着海星、套着珊瑚环的管子；霓虹：激光、灯管描边的黑板、一圈圈光环的隧道；
/// 秋林：带叶子的树枝、横着的圆木、缠着藤的琥珀管
extension RhythmScene {
    struct TrackMaterials {
        var rail: SCNMaterial, post: SCNMaterial, accent: SCNMaterial
        /// 支架插进墙的地方要不要一块底座
        var mounts = true
    }

    func trackMaterials(_ mats: Materials) -> TrackMaterials {
        switch theme.look {
        case .classic: return TrackMaterials(rail: mats.metal, post: mats.metal, accent: mats.metal)
        case .crystal:
            return TrackMaterials(rail: Self.flat(theme.accent2.mixed(.white, 0.45)), post: Self.flat(theme.accent2.mixed(.white, 0.2)),
                                  accent: Self.flat(.rgb(1, 0.88, 0.55)), mounts: false)
        case .blossom:
            return TrackMaterials(rail: Self.lit(.rgb(0.6, 0.78, 0.42), shine: 50), post: Self.lit(.rgb(0.5, 0.68, 0.36), shine: 40),
                                  accent: Self.lit(.rgb(1, 0.66, 0.76), shine: 20), mounts: false)
        case .ice:
            let ice = Self.lit(.rgb(0.82, 0.93, 1), shine: 120, clear: 0.85)
            ice.reflective.contents = RhythmArt.chrome
            ice.reflective.intensity = 0.4
            return TrackMaterials(rail: ice, post: mats.metal, accent: Self.lit(.rgb(0.97, 0.99, 1), shine: 8))
        case .reef:
            return TrackMaterials(rail: Self.lit(.rgb(0.86, 0.74, 0.55), shine: 5), post: mats.metal,
                                  accent: Self.lit(.rgb(0.98, 0.96, 0.97), shine: 90))
        case .neon:
            return TrackMaterials(rail: Self.flat(theme.cards[1]), post: Self.flat(theme.cards[2].mixed(.black, 0.4)),
                                  accent: Self.flat(theme.cards[0]), mounts: false)
        case .forest:
            return TrackMaterials(rail: Self.barkMaterial(), post: Self.barkMaterial(), accent: Self.lit(.rgb(0.88, 0.45, 0.18), shine: 10),
                                  mounts: false)
        }
    }

    func lookTrack(_ k: RhythmStage.Track, row: SCNNode, fixed: SCNNode, shade: SCNNode, mats: Materials) {
        let tm = trackMaterials(mats)
        switch k.kind {
        case .rail: lookRail(k, fixed: fixed, shade: shade, mats: mats, tm)
        case .plank: lookPlank(k, fixed: fixed, shade: shade, mats: mats, tm)
        case .tube: lookTube(k, row: row, fixed: fixed, shade: shade, mats: mats, tm)
        }
    }

    /// 路线上 s 处往前走的方向（场景坐标）
    func tangent(_ k: RhythmStage.Track, _ s: CGFloat) -> SIMD3<Float> {
        let d = v(k.at(s + 0.01)) - v(k.at(s - 0.01))
        return simd_length(d) > 0 ? simd_normalize(d) : [1, 0, 0]
    }

    /// 一个圆环套在 c 上，环面和 axis 垂直
    func hoop(_ c: SIMD3<Float>, axis: SIMD3<Float>, radius r: CGFloat, pipe: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let torus = SCNTorus(ringRadius: r * Self.unit, pipeRadius: pipe * Self.unit)
        torus.ringSegmentCount = 20
        torus.pipeSegmentCount = 6
        torus.materials = [m]
        let n = SCNNode(geometry: torus)
        n.simdPosition = c
        n.simdOrientation = simd_quatf(from: [0, 1, 0], to: axis)
        return n
    }

    /// 尖朝下的冰棱，根部在 top（屏幕点）
    func icicle(_ top: Point3, length: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let cone = SCNCone(topRadius: 1.8 * Self.unit, bottomRadius: 0, height: length * Self.unit)
        cone.radialSegmentCount = 6
        cone.materials = [m]
        let n = SCNNode(geometry: cone)
        n.simdPosition = v(Point3(x: top.x, y: top.y + length / 2, z: top.z))
        return n
    }

    /// 正对着镜头的一颗小星星，中心在 c（屏幕点），外圈半径 r
    func starNode(_ c: Point3, radius r: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let path = RhythmArt.starPath(r * Self.unit)
        let shape = SCNShape(path: path, extrusionDepth: 1.5 * Self.unit)
        shape.materials = [m]
        let n = SCNNode(geometry: shape)
        n.simdPosition = v(c)
        return n
    }

    /// 原来那样的支架：两根轨道底下一根横杆，正中一根短杆往下、拐个弯插进墙里
    private func posts(_ k: RhythmStage.Track, step: CGFloat, _ tm: TrackMaterials, _ fixed: SCNNode) {
        let u = Self.unit
        for s in stations(k, step: step) {
            let p = k.at(s), knob = v(Point3(x: p.x, y: p.y + 12, z: p.z - 4))
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 8)), v(Point3(x: p.x, y: p.y, z: p.z + 8)), radius: 1.2 * u, material: tm.post))
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 4)), knob, radius: 1.3 * u, material: tm.post))
            fixed.addChildNode(RhythmArt.rod(knob, v(Point3(x: p.x, y: p.y + 12, z: 0)), radius: 1.3 * u, material: tm.post))
            fixed.addChildNode(RhythmArt.knob(knob, radius: 1.3 * u, material: tm.post))
            if tm.mounts {
                fixed.addChildNode(RhythmArt.mount(knob, radius: 4.5 * u, material: tm.post))
            }
        }
    }

    private func lookRail(_ k: RhythmStage.Track, fixed: SCNNode, shade: SCNNode, mats: Materials, _ tm: TrackMaterials) {
        let u = Self.unit, look = theme.look
        let r: CGFloat = [.neon: 1.1, .reef: 1.7, .forest: 2.4, .blossom: 2.2][look] ?? 1.6
        for dz: CGFloat in [-8, 8] {
            let path = k.path.map { v(Point3(x: $0.x, y: $0.y - 1, z: $0.z + dz)) }
            let rail = SCNNode(geometry: RhythmArt.sweep(path, radius: Float(r * u), sides: 6))
            rail.geometry?.materials = [tm.rail]
            fixed.addChildNode(rail)
            if look == .neon {
                // 激光外面一层淡淡的光晕
                let glow = Self.flat(theme.cards[1], clear: 0.25)
                glow.blendMode = .add
                glow.writesToDepthBuffer = false
                let halo = SCNNode(geometry: RhythmArt.sweep(path, radius: Float(3.6 * u), sides: 8))
                halo.geometry?.materials = [glow]
                fixed.addChildNode(halo)
            }
        }
        switch look {
        case .crystal:
            for (j, s) in stations(k, step: 42).enumerated() {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 8)), v(Point3(x: p.x, y: p.y, z: p.z + 8)), radius: 0.8 * u, material: tm.post))
                fixed.addChildNode(starNode(Point3(x: p.x, y: p.y + 10 + CGFloat(j % 2) * 5, z: p.z), radius: j % 2 == 0 ? 5 : 3.5, tm.accent))
            }
        case .blossom:
            for s in stations(k, step: 16) {
                let p = k.at(s), t = tangent(k, s)
                for dz: CGFloat in [-8, 8] { fixed.addChildNode(hoop(v(Point3(x: p.x, y: p.y - 1, z: p.z + dz)), axis: t, radius: r, pipe: 0.7, tm.post)) }
            }
            posts(k, step: 48, tm, fixed)
        case .ice:
            for (j, s) in stations(k, step: 12).enumerated() {
                let p = k.at(s)
                fixed.addChildNode(icicle(Point3(x: p.x, y: p.y, z: p.z + 8), length: [7, 12, 5, 10][j % 4], tm.rail))
            }
            posts(k, step: 40, tm, fixed)
        case .reef:
            for s in stations(k, step: 14) {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.knob(v(Point3(x: p.x, y: p.y + 1.5, z: p.z + 8)), radius: 2.4 * u, material: tm.accent))
            }
            posts(k, step: 40, tm, fixed)
        case .neon:
            for s in stations(k, step: 60) {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 8)), v(Point3(x: p.x, y: p.y + 14, z: 0)), radius: 0.6 * u, material: tm.post))
            }
        case .forest:
            for (j, s) in stations(k, step: 20).enumerated() {
                let p = k.at(s), side: Float = j % 2 == 0 ? 1 : -1
                let leaf = blob([5, 1, 2.6], at: .zero, tm.accent)
                leaf.simdPosition = v(Point3(x: p.x, y: p.y + 2, z: p.z + 8 * CGFloat(side) + 4 * CGFloat(side)))
                leaf.eulerAngles = SCNVector3(0, side * 0.6, side * 0.4)
                fixed.addChildNode(leaf)
            }
            for s in stations(k, step: 50) {
                let p = k.at(s)
                fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z)), v(Point3(x: p.x + 6, y: p.y + 22, z: 0)), radius: 1.8 * u, material: tm.post))
            }
        case .classic: posts(k, step: 30, tm, fixed)
        }
        if look != .crystal && look != .neon {
            trackShadow(k, width: 22, down: 16, shade: shade, mats: mats)
        }
    }
}
