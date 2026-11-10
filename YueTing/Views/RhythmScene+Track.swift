import SceneKit
import UIKit

/// 组和组之间的架子：带柱子的双轨、木板、磨砂的弯管。都用镀铬的杆子架在离墙一段的地方，
/// 杆子插进墙的地方一块金属底座
extension RhythmScene {
    func addTrack(_ k: RhythmStage.Track, row: SCNNode, fixed: SCNNode, shade: SCNNode, mats: Materials) {
        guard k.path.count > 1 else { return }
        // 别的主题换成自己的架子（RhythmScene+Tracks）
        guard theme.look == .classic else { return lookTrack(k, row: row, fixed: fixed, shade: shade, mats: mats) }
        switch k.kind {
        case .rail: addRail(k, fixed: fixed, shade: shade, mats: mats)
        case .plank: addPlank(k, fixed: fixed, shade: shade, mats: mats)
        case .tube: addTube(k, row: row, fixed: fixed, shade: shade, mats: mats)
        }
    }

    /// 架子在墙上的影子：沿着路线的一条软带，往右下偏（离墙有一段，偏得开一些）
    func trackShadow(_ k: RhythmStage.Track, width: CGFloat, down: CGFloat, shade: SCNNode, mats: Materials) {
        let path = k.path.map { v(Point3(x: $0.x + 14, y: $0.y + down + 10, z: 0.5)) }
        let node = SCNNode(geometry: RhythmArt.ribbon(path, width: Float(width * Self.unit)))
        node.geometry?.materials = [mats.strip]
        shade.addChildNode(node)
    }

    /// 沿着路线大约每 step 点取一个位置
    func stations(_ k: RhythmStage.Track, step: CGFloat) -> [CGFloat] {
        var length: CGFloat = 0
        for j in 1..<k.path.count { length += hypot(k.path[j].x - k.path[j - 1].x, k.path[j].y - k.path[j - 1].y) }
        let n = max(1, Int((length / step).rounded()))
        return (0...n).map { (0.06 + 0.88 * CGFloat($0) / CGFloat(n)) }
    }

    /// 两根银色的轨道，小球骑在中间；底下隔一段一根短杆往下、拐个弯插进墙里
    private func addRail(_ k: RhythmStage.Track, fixed: SCNNode, shade: SCNNode, mats: Materials) {
        let u = Self.unit
        for dz: CGFloat in [-8, 8] {
            let path = k.path.map { v(Point3(x: $0.x, y: $0.y - 1, z: $0.z + dz)) }
            let node = SCNNode(geometry: RhythmArt.sweep(path, radius: Float(1.8 * u), sides: 6))
            node.geometry?.materials = [mats.metal]
            fixed.addChildNode(node)
        }
        for s in stations(k, step: 30) {
            let p = k.at(s)
            let knob = v(Point3(x: p.x, y: p.y + 12, z: p.z - 4))
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 8)), v(Point3(x: p.x, y: p.y, z: p.z + 8)),
                                             radius: 1.2 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: p.y, z: p.z - 4)), knob, radius: 1.3 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.rod(knob, v(Point3(x: p.x, y: p.y + 12, z: 0)), radius: 1.3 * u, material: mats.metal))
            // 拐弯处补一个和杆子一样粗的球，接口是圆的
            fixed.addChildNode(RhythmArt.knob(knob, radius: 1.3 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(knob, radius: 4.5 * u, material: mats.metal))
        }
        trackShadow(k, width: 22, down: 16, shade: shade, mats: mats)
    }

    /// 一块几乎水平的木板，小球在上面滚；板子底下隔一段一个镀铬的 L 形托架插进墙里，
    /// 板子后边离墙留出一段空
    private func addPlank(_ k: RhythmStage.Track, fixed: SCNNode, shade: SCNNode, mats: Materials) {
        let u = Self.unit, a = k.path[0], b = k.path[k.path.count - 1], z = RhythmStage.trackZ
        // 板子两头各多出 12，小球掉上来、滚下去都在板子里面
        let len = hypot(b.x - a.x, b.y - a.y) + 24, depth: CGFloat = 56, thick: CGFloat = 8
        let wood = SCNMaterial()
        wood.lightingModel = .lambert
        wood.diffuse.contents = theme.plank
        let board = SCNBox(width: len * u, height: thick * u, length: depth * u, chamferRadius: 1 * u)
        board.materials = [wood]
        let node = SCNNode(geometry: board)
        node.simdPosition = v(Point3(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + thick / 2, z: z))
        node.simdOrientation = simd_quatf(angle: -Float(atan2(b.y - a.y, b.x - a.x)), axis: [0, 0, 1])
        fixed.addChildNode(node)
        for s in stations(k, step: 110) {
            let p = k.at(s), y = p.y + thick + 1.5
            let front = v(Point3(x: p.x, y: y, z: z + depth / 2 - 8)), back = v(Point3(x: p.x, y: y, z: z - depth / 2))
            let foot = v(Point3(x: p.x, y: y + 22, z: 0))
            fixed.addChildNode(RhythmArt.rod(front, back, radius: 1.6 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.rod(back, foot, radius: 1.6 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.rod(v(Point3(x: p.x, y: y, z: z - depth / 2)), v(Point3(x: p.x, y: y, z: 0)),
                                             radius: 1.3 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(foot, radius: 5 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(v(Point3(x: p.x, y: y, z: 0)), radius: 4 * u, material: mats.metal))
        }
        trackShadow(k, width: 18, down: thick + 8, shade: shade, mats: mats)
    }

    /// 一根磨砂的半透明管子，小球从上头掉进去、从下头出来；两头各套一个金属环，环上一根杆插进墙里
    private func addTube(_ k: RhythmStage.Track, row: SCNNode, fixed: SCNNode, shade: SCNNode, mats: Materials) {
        let u = Self.unit, r = RhythmStage.ballRadius + 7
        let center = tubeBody(k, row: row, color: theme.tube, clear: theme.tubeClear)
        for j in [1, center.count - 2] {
            let axis = simd_normalize(center[j + 1] - center[j - 1])
            let torus = SCNTorus(ringRadius: (r + 1) * u, pipeRadius: 2.2 * u)
            torus.ringSegmentCount = 24
            torus.pipeSegmentCount = 6
            torus.materials = [mats.metal]
            let ring = SCNNode(geometry: torus)
            ring.simdPosition = center[j]
            ring.simdOrientation = simd_quatf(from: [0, 1, 0], to: axis)
            fixed.addChildNode(ring)
            let back = center[j] - SIMD3<Float>(0, 0, Float(r * u))
            fixed.addChildNode(RhythmArt.rod(back, SIMD3(back.x, back.y, 0), radius: 1.6 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(back, radius: 5 * u, material: mats.metal))
        }
        trackShadow(k, width: 2 * r + 10, down: 10, shade: shade, mats: mats)
    }

    /// 管子本身（磨砂、半透明，越斜着看越不透明），返回管子中线（小球球心走的线）的场景坐标
    @discardableResult func tubeBody(_ k: RhythmStage.Track, row: SCNNode, color: UIColor, clear: CGFloat) -> [SIMD3<Float>] {
        let u = Self.unit, r = RhythmStage.ballRadius + 7
        let center = k.path.map { v(Point3(x: $0.x, y: $0.y - RhythmStage.ballRadius, z: $0.z)) }
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor.white
        m.shininess = 20
        m.transparency = clear
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        // 越斜着看越不透明，看得出管壁的厚度
        m.shaderModifiers = [.fragment: """
            float f = pow(1.0 - abs(dot(_surface.normal, _surface.view)), 2.0);
            _output.color.rgb *= 0.75 + 0.6 * f;
            """]
        let tube = SCNNode(geometry: RhythmArt.sweep(center, radius: Float(r * u), sides: 18))
        tube.geometry?.materials = [m]
        tube.renderingOrder = Self.tubeOrder
        row.addChildNode(tube)
        return center
    }
}
