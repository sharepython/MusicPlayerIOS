import SceneKit
import UIKit

/// 各个主题的跳板：小球落在顶面正中（stage.landing），顶面的位置、朝向和原来的卡片一样，形状和托着它的东西各不相同。
/// key 节点放在顶面往下 keyThick / 2 处，x 横着、z 从后端往前端、y 朝上；跳板上的装饰都挂在它下面，踩中时跟着动
extension RhythmScene {
    /// 受主题灯光照的材质，clear 是不透明度
    static func lit(_ c: UIColor, shine: CGFloat = 40, clear: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = c
        m.specular.contents = UIColor(white: shine > 60 ? 1 : 0.5, alpha: 1)
        m.shininess = shine
        m.transparency = clear
        return m
    }

    /// 自己发光、不受灯光影响的材质
    static func flat(_ c: UIColor, clear: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.transparency = clear
        return m
    }

    /// 树皮：贴图按长度重复
    static func barkMaterial(_ repeats: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = RhythmArt.bark
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(1, repeats, 1)
        return m
    }

    /// 往 key 里挂一块：c 是 key 自己坐标里的屏幕点
    @discardableResult func part(_ g: SCNGeometry, _ m: SCNMaterial, _ c: SIMD3<Float>, to key: SCNNode) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = c * Float(Self.unit)
        key.addChildNode(n)
        return n
    }

    /// 沿着二次贝塞尔曲线取的点：a 到 b，中间往 c 拐
    static func curve(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ b: SIMD3<Float>, _ n: Int = 10) -> [SIMD3<Float>] {
        (0...n).map { k in
            let t = Float(k) / Float(n)
            return a * (1 - t) * (1 - t) + c * 2 * t * (1 - t) + b * t * t
        }
    }

    /// 一张跳板，返回节点（还没放到位置上）和亮起时发光的材质。at 是卡片上一点的场景坐标（离后端 along、往右 across、
    /// 从顶面往下 down），托架这些不动的东西加进 fixed
    @MainActor func makePad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode, mats: Materials) -> (SCNNode, SCNMaterial) {
        switch theme.look {
        case .classic: return classicPad(color, at: at, fixed: fixed, mats: mats)
        case .crystal: return crystalPad(color)
        case .blossom: return blossomPad(color, at: at, fixed: fixed)
        case .ice: return icePad(color, at: at, fixed: fixed, mats: mats)
        case .reef: return jellyPad(color)
        case .neon: return neonPad(color, at: at, fixed: fixed)
        case .forest: return mushroomPad(color, at: at, fixed: fixed)
        }
    }

    /// 原来的亚克力卡片：两根铁丝从后端勾住、托在底下，再斜着插进墙里
    @MainActor private func classicPad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode,
                                       mats: Materials) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, L = RhythmStage.keyLength, H = RhythmStage.keyThick
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor.white
        m.shininess = 70
        m.reflective.contents = RhythmArt.chrome
        m.reflective.intensity = theme.cardShine
        m.fresnelExponent = 1.5
        m.transparency = theme.cardClear
        let box = SCNBox(width: RhythmStage.keyWidth * u, height: H * u, length: L * u, chamferRadius: 1.6 * u)
        box.materials = [m]
        for a: CGFloat in [-10, 10] {
            let top = at(-1.2, a, -1.2), back = at(-1.2, a, H + 1.2)
            let foot = SIMD3<Float>(back.x, back.y - Float(16 * u), 0)
            for (s, e) in [(at(7, a, -1.2), top), (top, back), (back, at(L * 0.62, a, H + 1.2)), (back, foot)] {
                fixed.addChildNode(RhythmArt.rod(s, e, radius: 1.1 * u, material: mats.metal))
            }
            fixed.addChildNode(RhythmArt.knob(back, radius: 1.8 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(foot, radius: 4 * u, material: mats.metal))
        }
        return (SCNNode(geometry: box), m)
    }

    /// 星夜：一块六角水晶，底下收成尖，尖上挂一颗小亮珠；没有支架，就飘在墙前面
    @MainActor private func crystalPad(_ color: UIColor) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick)
        let m = Self.lit(color, shine: 100, clear: 0.8)
        m.reflective.contents = RhythmArt.chrome
        m.reflective.intensity = 0.4
        m.fresnelExponent = 2
        let key = SCNNode()
        let hex = SCNCylinder(radius: 20 * u, height: CGFloat(H) * u)
        hex.radialSegmentCount = 6
        part(hex, m, [0, 0, 0], to: key).eulerAngles.y = .pi / 6
        let tip = SCNCone(topRadius: 20 * u, bottomRadius: 0, height: 16 * u)
        tip.radialSegmentCount = 6
        part(tip, m, [0, -H / 2 - 8, 0], to: key).eulerAngles.y = .pi / 6
        let bead = SCNSphere(radius: 2 * u)
        part(bead, Self.flat(.rgb(1, 0.93, 0.7)), [0, -H / 2 - 18, 0], to: key)
        return (key, m)
    }

    /// 樱花：一朵五瓣的樱花，花心一圈黄色花蕊，底下绿色的花萼；一根带叶子的花枝从墙里伸出来托着
    @MainActor private func blossomPad(_ color: UIColor, at: (CGFloat, CGFloat, CGFloat) -> SIMD3<Float>, fixed: SCNNode) -> (SCNNode, SCNMaterial) {
        let u = Self.unit, H = Float(RhythmStage.keyThick), L = RhythmStage.keyLength
        let m = Self.lit(color, shine: 30, clear: 0.95)
        let key = SCNNode()
        let path = UIBezierPath()
        for k in 0...120 {
            let a = CGFloat(k) / 120 * 2 * .pi
            // 五片花瓣，瓣尖中间凹一个小口
            let lobe = abs(cos(2.5 * a)), r = 21 * (0.62 + 0.38 * pow(lobe, 0.6)) - 2.2 * pow(lobe, 40)
            let p = CGPoint(x: r * cos(a + .pi / 2) * u, y: r * sin(a + .pi / 2) * u)
            if k == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(H) * u)
        shape.chamferRadius = 1.4 * u
        part(shape, m, [0, 0, 0], to: key).eulerAngles.x = -.pi / 2
        let heart = Self.lit(.rgb(1, 0.62, 0.72), shine: 10)
        let disc = SCNCylinder(radius: 6 * u, height: 0.6 * u)
        part(disc, heart, [0, H / 2 + 0.1, 0], to: key)
        let pollen = Self.lit(.rgb(1, 0.85, 0.4), shine: 20)
        for k in 0..<6 {
            let a = Float(k) * .pi / 3
            part(SCNSphere(radius: 1.1 * u), pollen, [7.5 * cos(a), H / 2 + 0.3, 7.5 * sin(a)], to: key)
        }
        let sepal = SCNCone(topRadius: 9 * u, bottomRadius: 2.5 * u, height: 6 * u)
        part(sepal, Self.lit(.rgb(0.45, 0.68, 0.38)), [0, -H / 2 - 3, 0], to: key)

        // 花枝：从花萼底下往后、往下弯进墙里，中间长两片叶子
        let a = at(L / 2, 0, CGFloat(H) + 5), w = SIMD3<Float>(a.x - Float(6 * u), a.y - Float(30 * u), 0)
        let c = SIMD3<Float>(a.x, a.y - Float(20 * u), a.z * 0.7)
        let branch = Self.curve(a, c, w)
        let stick = SCNNode(geometry: RhythmArt.sweep(branch, radius: Float(2 * u), sides: 6))
        stick.geometry?.materials = [Self.barkMaterial()]
        fixed.addChildNode(stick)
        let leaf = Self.lit(.rgb(0.5, 0.75, 0.42), shine: 20)
        for (j, s) in [(4, Float(1)), (7, -1)] {
            let n = blob([5, 1.2, 2.6], at: .zero, leaf)
            n.simdPosition = branch[j] + SIMD3(s * Float(5 * u), 0, Float(2 * u))
            n.eulerAngles.z = s * 0.5
            fixed.addChildNode(n)
        }
        return (key, m)
    }
}
