import SceneKit
import UIKit

/// 霓虹、秋林的屋顶（RhythmScene+Roofs）
extension RhythmScene {
    /// 霓虹：平顶，屋子外沿描一圈亮着的灯管，顶上立一块带灯框的招牌，旁边一根天线顶着一颗灯
    @MainActor func neonRoof(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, H = f.H, zc = f.zc, zf = f.front + 1, open = k.open
        let pink = k.lamp(theme.cards[0]), cyan = k.lamp(theme.cards[1 % theme.cards.count])
        k.box([W + 10, 6, f.depth + 10], [0, T + 3, zc], k.material(s.roof, 90), 0.4)
        k.rod([-W / 2 - 5, T + 6, zf + 4], [W / 2 + 5, T + 6, zf + 4], 1.1, pink)
        k.rod([-W / 2 - 5, T, zf + 4], [W / 2 + 5, T, zf + 4], 1.1, cyan)
        k.rod([-open * W / 2, 0, zf], [-open * W / 2, T, zf], 1, cyan)
        k.rod([open * W / 2, H, zf], [open * W / 2, T, zf], 1, cyan)
        k.rod([-W / 2, f.up - 1, zf + 1], [W / 2, f.up - 1, zf + 1], 0.8, pink)
        // 招牌：深色底、灯管框，后面两根细杆撑着
        let y = T + 6 + 16, z = f.back + 22
        hangSign(k, s, [0, y, z])
        for (a, b) in [([-27, -9], [27, -9]), ([-27, 9], [27, 9]), ([-27, -9], [-27, 9]), ([27, -9], [27, 9])] as [([Float], [Float])] {
            k.rod([a[0], y + a[1], z + 1.2], [b[0], y + b[1], z + 1.2], 0.9, pink)
        }
        for x: Float in [-18, 18] { k.rod([x, T + 6, z - 2], [x, y - 8, z - 1], 0.7, k.material(.rgb(0.3, 0.26, 0.4), 40)) }
        let ax = -open * W * 0.36
        k.rod([ax, T + 6, f.back + 10], [ax, T + 6 + f.rise * 0.6, f.back + 10], 0.6, k.material(.rgb(0.4, 0.36, 0.5), 60))
        k.blob([2.4, 2.4, 2.4], [ax, T + 6 + f.rise * 0.6 + 2, f.back + 10], pink)
    }

    /// 秋林：整个屋顶是一朵大红蘑菇的伞盖，盖上一圈白点，底下一圈奶白的菌褶；墙边爬着一根藤，几片叶子
    @MainActor func mushroomRoof(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, zc = f.zc
        let r = SIMD3<Float>(W / 2 + 18, f.rise + 16, f.depth / 2 + 14), base = T - 3
        cupola(k, r, [0, base, zc], k.material(s.roof, 40))
        let gill = SCNCylinder(radius: 1, height: CGFloat(2 * k.u))
        gill.radialSegmentCount = 32
        gill.materials = [k.material(.rgb(0.95, 0.86, 0.72), 6)]
        k.add(SCNNode(geometry: gill), [0, base, zc]).simdScale = [r.x * k.u, 1, r.z * k.u]
        // 白点：伞盖朝前那半边上，按经纬放
        let dot = k.material(s.ridge, 20)
        for (t, p) in [(Float(0.5), Float(0.45)), (1.3, 0.7), (2.2, 0.4), (2.8, 0.75), (1.8, 0.2), (0.25, 0.85), (2.6, 0.12), (1.05, 0.3)] {
            let d = SIMD3<Float>(cos(t) * cos(p), sin(p), sin(t) * cos(p))
            let c = SIMD3<Float>(0, base, zc) + d * r
            let size: Float = 3.2 + 2 * cos(p)
            let n = k.blob([size, 1.6, size], c, dot)
            n.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(d / (r * r)))
        }
        let vine = k.material(.rgb(0.38, 0.52, 0.24), 10), leaf = k.material(.rgb(0.55, 0.7, 0.3), 10)
        let x = -k.open * (f.W / 2 + 2.5)
        let pts = (0...16).map { j -> SIMD3<Float> in
            let y = Float(j) / 16 * (T - 4)
            return [x, y, f.front - 8 + 4 * sin(Float(j) * 0.8)]
        }
        strand(k, pts, 1.2, vine)
        for j in stride(from: 2, to: pts.count, by: 3) {
            let n = k.blob([4, 1, 2.4], pts[j] + [-k.open * 2, 0, 2], leaf)
            n.eulerAngles = SCNVector3(0.6, Float(j), 0.8 * k.open)
        }
        hangSign(k, s, [0, base + r.y * 0.3, zc + r.z * 0.95 + 3])
    }
}
