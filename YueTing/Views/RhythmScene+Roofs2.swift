import SceneKit
import UIKit

/// 各主题屋顶的样子（RhythmScene+Roofs）
extension RhythmScene {
    /// 星夜：墙顶一圈金边，上面一个银蓝色的圆顶，正面一道深色的观测缝，缝里斜伸出一架黄铜望远镜，顶上一颗金星星
    @MainActor func observatory(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, zc = f.zc
        let r = SIMD3<Float>(W / 2 + 4, min(f.rise + 8, W * 0.4), f.depth / 2 + 6), base = T + 5
        let gold = k.material(s.ridge, 80), brass = k.material(.rgb(0.95, 0.74, 0.36), 90)
        k.box([W + 10, 5, f.depth + 12], [0, T + 2.5, zc], gold, 1.2)
        let shell = k.material(s.roof, 90)
        shell.reflective.contents = RhythmArt.chrome
        shell.reflective.intensity = 0.3
        cupola(k, r, [0, base, zc], shell)
        // 观测缝：顺着圆顶表面从底下爬到顶上
        let x0 = W * 0.12, c = sqrt(1 - x0 * x0 / (r.x * r.x)) * 1.02
        let slit = (0...14).map { j -> SIMD3<Float> in
            let a = Float(j) / 14 * .pi / 2
            return [x0, base + r.y * c * sin(a), zc + r.z * c * cos(a)]
        }
        strand(k, slit, 3.4, k.lamp(.rgb(0.1, 0.1, 0.26)))
        let foot = SIMD3<Float>(x0, base + r.y * 0.72, zc + r.z * 0.6), dir = simd_normalize(SIMD3<Float>(0.45, 0.75, 0.5))
        let tip = foot + dir * r.y * 0.75
        k.rod(foot, tip, 3.2, brass)
        k.rod(tip - dir * 7, tip + dir * 2, 4.4, brass)
        extrude(k, RhythmArt.starPath(7, inner: 0.45), 2, [0, base + r.y + 8, zc], k.lamp(.rgb(1, 0.88, 0.5)))
        for (x, y) in [(-W * 0.3, r.y * 0.55), (W * 0.36, r.y * 0.25), (-W * 0.12, r.y * 0.85)] {
            k.blob([1.6, 1.6, 1.6], [x, base + y, zc + r.z * sqrt(max(0, 1 - x * x / (r.x * r.x) - y * y / (r.y * r.y))) + 1],
                   k.lamp(.rgb(1, 0.95, 0.75)))
        }
        hangSign(k, s, [0, base + r.y * 0.28, zc + r.z + 4])
    }

    /// 樱花：两层往上翘的飞檐，中间一截红柱子的小阁楼，屋脊两头翘起，檐角各挂一盏红灯笼
    @MainActor func pagoda(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, rise = f.rise, zc = f.zc, depth = f.depth
        let tile = k.material(s.roof, 30), red = k.material(s.ridge, 30), paper = k.material(s.paper, 6)
        // 一层檐：底边两头往上翘，顶边收到 top 宽
        func eave(_ half: Float, _ y: Float, _ h: Float, _ top: Float) -> UIBezierPath {
            let p = UIBezierPath()
            func pt(_ x: Float, _ y: Float) -> CGPoint {
                CGPoint(x: CGFloat(x), y: CGFloat(y))
            }
            p.move(to: pt(-half, y + 8))
            p.addQuadCurve(to: pt(-half + 20, y), controlPoint: pt(-half + 8, y + 1))
            p.addLine(to: pt(half - 20, y))
            p.addQuadCurve(to: pt(half, y + 8), controlPoint: pt(half - 8, y + 1))
            p.addLine(to: pt(half - 5, y + 11))
            p.addQuadCurve(to: pt(top, y + h), controlPoint: pt(half * 0.55, y + h * 0.3))
            p.addLine(to: pt(-top, y + h))
            p.addQuadCurve(to: pt(-half + 5, y + 11), controlPoint: pt(-half * 0.55, y + h * 0.3))
            p.close()
            return p
        }
        let low = rise * 0.42, mid = rise * 0.3
        extrude(k, eave(W / 2 + 20, 0, low, W * 0.27), depth + 16, [0, T - 2, zc + 1], tile)
        let y1 = T - 2 + low, d1 = depth * 0.6
        k.box([W * 0.5, mid + 4, d1], [0, y1 + mid / 2, zc], paper, 0.5)
        for x in [-W * 0.25, W * 0.25] { k.box([3.4, mid + 4, 3.4], [x, y1 + mid / 2, zc + d1 / 2], red, 0.6) }
        k.box([W * 0.5 + 4, 2.4, 3], [0, y1 + mid + 1, zc + d1 / 2], red, 0.4)
        let y2 = y1 + mid + 2
        extrude(k, eave(W * 0.37, 0, rise * 0.36, W * 0.07), d1 + 12, [0, y2, zc], tile)
        let top = y2 + rise * 0.36
        k.box([W * 0.14 + 6, 3, d1 + 4], [0, top + 1.5, zc], red, 0.8)
        for side: Float in [-1, 1] {
            let horn = SCNCone(topRadius: 0, bottomRadius: CGFloat(2.2 * k.u), height: CGFloat(7 * k.u))
            horn.materials = [red]
            k.add(SCNNode(geometry: horn), [side * (W * 0.07 + 4), top + 5, zc]).eulerAngles.z = -side * 0.5
            // 檐角的灯笼
            let x = side * (W / 2 + 13), hy = T + 5, z = f.front + 7
            k.rod([x, hy, z], [x, hy - 8, z], 0.4, red)
            k.blob([4.6, 5.6, 4.6], [x, hy - 13, z], k.lamp(.rgb(1, 0.42, 0.32)))
            for dy: Float in [-7.4, 7.4] { k.box([5, 1.4, 5], [x, hy - 13 + dy * 0.75, z], k.material(.rgb(0.95, 0.75, 0.3), 60), 0.5) }
        }
        hangSign(k, s, [0, y1 + mid / 2 + 1, zc + d1 / 2 + 3])
    }

    /// 深海：一片扇贝壳当屋顶，壳面上一道道放射的棱，底下一个壳铰，壳顶一颗珍珠；侧墙外面飘着两根海草，壳上趴一只海星
    @MainActor func shellRoof(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let W = f.W, T = f.T, zc = f.zc, rx = W / 2 + 10, ry = f.rise + 10, n = 9, zf = f.front + 8.2
        // 贝壳不跟着海水调色，不然发灰
        let shell = k.keep(s.roof, 50), rib = k.keep(s.ridge, 50)
        let p = UIBezierPath()
        for j in 0...(n * 8) {
            let a = Float.pi * Float(j) / Float(n * 8), bump = 1 + 0.05 * abs(sin(a * Float(n)))
            let q = CGPoint(x: CGFloat(-rx * cos(a) * bump), y: CGFloat(ry * sin(a) * bump))
            if j == 0 {
                p.move(to: q)
            } else {
                p.addLine(to: q)
            }
        }
        p.close()
        extrude(k, p, f.depth + 14, [0, T - 2, zc + 1], shell)
        for j in 1..<n {
            let a = Float.pi * Float(j) / Float(n)
            k.rod([0, T - 2, zf], [-rx * cos(a) * 0.98, T - 2 + ry * sin(a) * 0.98, zf], 1.5, rib)
        }
        k.blob([11, 6, 3], [0, T - 1, zf], rib)
        let pearl = Self.lit(.rgb(0.97, 0.96, 1), shine: 120)
        k.blob([5, 5, 5], [0, T - 2 + ry * 1.05 + 4, zc], pearl)
        extrude(k, RhythmArt.starPath(9, inner: 0.42), 2, [k.open * rx * 0.5, T + ry * 0.32, zf + 0.8], k.material(.rgb(1, 0.5, 0.42), 20))
            .eulerAngles.z = 0.3
        let weed = k.material(.rgb(0.32, 0.62, 0.42), 10)
        for (dx, h) in [(Float(6), Float(1)), (13, 0.7)] {
            let x = -k.open * (W / 2 + dx)
            strand(k, (0...14).map { j in
                let y = Float(j) / 14 * T * h
                return [x + 3 * sin(Float(j) * 0.9 + dx), y, f.front - 4 - dx]
            }, 1.6, weed)
        }
        hangSign(k, s, [0, T + ry * 0.48, zf + 3])
    }
}
