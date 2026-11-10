import SceneKit
import UIKit

/// 雪国、深海、霓虹、秋林的跳板
extension RhythmScene {
    /// 雪国：一块圆角的冰，顶上盖着一层雪、边上垂下来两团，底下挂一排冰棱；一根结霜的铁杆从底下斜插进墙里
    @MainActor func icePad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode,
                           mats: Materials) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick), L = RhythmStage.keyLength
        let m = Self.lit(color, shine: 120, clear: 0.74)
        m.reflective.contents = RhythmArt.chrome
        m.reflective.intensity = 0.5
        m.fresnelExponent = 1.2
        let key = SCNNode()
        part(SCNBox(width: 36 * u, height: CGFloat(H + 6) * u, length: 36 * u, chamferRadius: 2.6 * u), m, [0, -3, 0], to: key)
        let snow = Self.lit(.rgb(0.98, 0.99, 1), shine: 8)
        key.addChildNode(blob([17, 2.4, 17], at: [0, H / 2 - 0.6, 0], snow))
        for x: Float in [-9, 7] { key.addChildNode(blob([5, 3.6, 3], at: [x, H / 2 - 2.6, 16.5], snow)) }
        let icicle = Self.lit(color.mixed(.white, 0.3), shine: 120, clear: 0.8)
        for (x, len) in [(Float(-13), Float(8)), (-6, 13), (1, 6), (7, 11), (13, 7)] {
            let cone = SCNCone(topRadius: 2 * u, bottomRadius: 0, height: CGFloat(len) * u)
            cone.radialSegmentCount = 8
            part(cone, icicle, [x, -H / 2 - 6 - len / 2, 15], to: key)
        }
        let a = at(L / 2, 0, CGFloat(H) + 6), foot = SIMD3<Float>(a.x, a.y - Float(22 * u), 0)
        fixed.addChildNode(RhythmArt.rod(a, foot, radius: 2 * u, material: mats.metal))
        fixed.addChildNode(RhythmArt.mount(foot, radius: 5 * u, material: mats.metal))
        let lump = blob([6, 4, 3], at: .zero, snow)
        lump.simdPosition = foot + SIMD3(0, Float(4 * u), Float(2 * u))
        fixed.addChildNode(lump)
        return (key, m)
    }

    /// 深海：一只水母，伞顶就是跳板，里面一团亮一点的芯，伞沿一圈花边，底下飘着细触手和几条口腕，一直慢慢晃
    @MainActor func jellyPad(_ color: UIColor) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick), base = H / 2 - 10
        let m = Self.lit(color, shine: 60, clear: 0.72)
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: """
            float f = pow(1.0 - abs(dot(_surface.normal, _surface.view)), 2.0);
            _output.color.rgb += _output.color.rgb * 0.8 * f;
            """]
        let key = SCNNode()
        part(RhythmArt.dome(), m, [0, base, 0], to: key).simdScale = SIMD3(20, 10, 20) * Float(u)
        part(RhythmArt.dome(rings: 6, sides: 18), Self.flat(color.mixed(.white, 0.55), clear: 0.55), [0, base, 0], to: key)
            .simdScale = SIMD3(11, 6.5, 11) * Float(u)
        let rim = SCNTorus(ringRadius: 19.5 * u, pipeRadius: 1.3 * u)
        rim.ringSegmentCount = 28
        rim.pipeSegmentCount = 6
        part(rim, m, [0, base, 0], to: key)

        let legs = SCNNode()
        legs.simdPosition = [0, base * Float(u), 0]
        let thin = Self.flat(color.mixed(.white, 0.4), clear: 0.6), thick = Self.flat(color.mixed(.white, 0.2), clear: 0.65)
        for k in 0..<8 {
            let a = Float(k) * .pi / 4 + 0.2, r: Float = 16
            let path = (0...9).map { j -> SIMD3<Float> in
                let y = Float(j), w = 1.8 * sin(y * 0.9 + Float(k))
                return SIMD3(r * cos(a) + w * cos(a), -y * 2.6, r * sin(a) + w * sin(a)) * Float(u)
            }
            legs.addChildNode(SCNNode(geometry: RhythmArt.sweep(path, radius: Float(0.6 * u), sides: 4)))
            legs.childNodes.last?.geometry?.materials = [thin]
        }
        for k in 0..<3 {
            let a = Float(k) * 2 * .pi / 3
            let path = (0...7).map { j -> SIMD3<Float> in
                let y = Float(j), w = 2.4 * sin(y * 1.3 + Float(k) * 2)
                return SIMD3(4 * cos(a) + w, -y * 2.2, 4 * sin(a)) * Float(u)
            }
            legs.addChildNode(SCNNode(geometry: RhythmArt.sweep(path, radius: Float(1.7 * u), sides: 6)))
            legs.childNodes.last?.geometry?.materials = [thick]
        }
        key.addChildNode(legs)
        // 触手一直慢慢地来回摆，每只的节奏错开一点
        let swing = Double.random(in: 1.4...2)
        legs.runAction(.repeatForever(.sequence([.rotateBy(x: 0.14, y: 0.3, z: 0.1, duration: swing),
                                                 .rotateBy(x: -0.14, y: -0.3, z: -0.1, duration: swing)])))
        return (key, m)
    }

    /// 霓虹：一块深色的玻璃，十二条边都是亮着的灯管，底下一圈小光环；一根细细的光线连到墙上
    @MainActor func neonPad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick), L = RhythmStage.keyLength, w: Float = 17
        let edge = SCNMaterial()
        edge.lightingModel = .constant
        edge.diffuse.contents = color.mixed(.black, 0.7)
        let key = SCNNode()
        let glass = Self.lit(.rgb(0.1, 0.07, 0.18), shine: 110, clear: 0.6)
        glass.reflective.contents = RhythmArt.chrome
        glass.reflective.intensity = 0.35
        part(SCNBox(width: 34 * u, height: CGFloat(H) * u, length: 34 * u, chamferRadius: 0.4 * u), glass, [0, 0, 0], to: key)
        let h = H / 2
        var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
        for y in [-h, h] {
            lines += [([-w, y, -w], [w, y, -w]), ([-w, y, w], [w, y, w]), ([-w, y, -w], [-w, y, w]), ([w, y, -w], [w, y, w])]
        }
        for x in [-w, w] { for z in [-w, w] { lines.append(([x, -h, z], [x, h, z])) } }
        for (a, b) in lines { key.addChildNode(RhythmArt.rod(a * Float(u), b * Float(u), radius: 0.9 * u, material: edge)) }
        let halo = SCNTorus(ringRadius: 9 * u, pipeRadius: 0.7 * u)
        part(halo, edge, [0, -h - 4, 0], to: key)
        let beam = Self.flat(color.mixed(.black, 0.35), clear: 0.8)
        let a = at(L * 0.3, 0, CGFloat(H)), foot = SIMD3<Float>(a.x, a.y - Float(14 * u), 0)
        fixed.addChildNode(RhythmArt.rod(a, foot, radius: 0.6 * u, material: beam))
        fixed.addChildNode(RhythmArt.mount(foot, radius: 2.5 * u, material: beam))
        return (key, edge)
    }

    /// 秋林：一朵蘑菇，菌盖是跳板，盖上几颗白点，底下一圈菌褶、一截带菌环的菌柄；一根树枝从墙里伸出来，蘑菇长在枝头
    @MainActor func mushroomPad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick), L = RhythmStage.keyLength, base = H / 2 - 10
        let m = Self.lit(color, shine: 50)
        let key = SCNNode()
        part(RhythmArt.dome(), m, [0, base, 0], to: key).simdScale = SIMD3(21, 10, 21) * Float(u)
        let dot = Self.lit(.rgb(1, 0.98, 0.92), shine: 20)
        for (t, p) in [(Float(0.3), Float(0.55)), (2.1, 0.62), (4.0, 0.5), (5.2, 0.8), (1.2, 0.85), (3.1, 0.9)] {
            let c = SIMD3<Float>(21 * sin(p) * cos(t), base + 10 * cos(p), 21 * sin(p) * sin(t))
            key.addChildNode(blob([2.6, 1.4, 2.6], at: c, dot))
        }
        let cream = Self.lit(.rgb(0.97, 0.9, 0.78), shine: 10)
        part(SCNCylinder(radius: 20 * u, height: 1 * u), Self.lit(.rgb(0.9, 0.78, 0.62), shine: 4), [0, base - 0.5, 0], to: key)
        part(SCNCylinder(radius: 5.5 * u, height: 17 * u), cream, [0, base - 9, 0], to: key)
        part(SCNTorus(ringRadius: 6 * u, pipeRadius: 1.3 * u), cream, [0, base - 5, 0], to: key)

        let a = at(L / 2, 0, CGFloat(H) + 27), w = SIMD3<Float>(a.x + Float(8 * u), a.y - Float(10 * u), 0)
        let branch = Self.curve(a, SIMD3(a.x, a.y - Float(6 * u), a.z * 0.5), w, 8)
        let stick = SCNNode(geometry: RhythmArt.sweep(branch, radius: Float(3 * u), sides: 7))
        stick.geometry?.materials = [Self.barkMaterial()]
        fixed.addChildNode(stick)
        let moss = Self.lit(.rgb(0.45, 0.6, 0.3), shine: 4)
        let lump = blob([7, 5, 4], at: .zero, moss)
        lump.simdPosition = a
        fixed.addChildNode(lump)
        let leaf = blob([6, 1.2, 3], at: .zero, Self.lit(.rgb(0.9, 0.45, 0.2), shine: 10))
        leaf.simdPosition = branch[5] + SIMD3(0, Float(3 * u), 0)
        leaf.eulerAngles.z = 0.6
        fixed.addChildNode(leaf)
        return (key, m)
    }
}
