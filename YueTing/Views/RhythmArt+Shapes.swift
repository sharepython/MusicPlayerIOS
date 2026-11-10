import SceneKit
import UIKit

/// 换造型用到的形状和贴图：半球（水母伞、蘑菇盖、天文台穹顶）、五角星、球里的花纹、树皮和年轮
extension RhythmArt {
    /// 朝上的单位半球：半径 1，开口在 y = 0，法线朝外，贴图坐标按经纬
    static func dome(rings: Int = 10, sides: Int = 28) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = [], indices: [UInt32] = []
        for i in 0...rings {
            let phi = Float.pi / 2 * Float(i) / Float(rings)
            for j in 0...sides {
                let a = 2 * Float.pi * Float(j) / Float(sides)
                let p = SIMD3<Float>(sin(phi) * cos(a), cos(phi), sin(phi) * sin(a))
                vertices.append(SCNVector3(p))
                normals.append(SCNVector3(p))
                uv.append(CGPoint(x: CGFloat(j) / CGFloat(sides), y: CGFloat(i) / CGFloat(rings)))
            }
        }
        let m = UInt32(sides + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(sides) {
                let a = i * m + j, b = a + m
                indices += [a, a + 1, b, a + 1, b + 1, b]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// 五角星的轮廓，外圈半径 r、内圈 r × inner，尖朝上
    static func starPath(_ r: CGFloat, inner: CGFloat = 0.45) -> UIBezierPath {
        let path = UIBezierPath()
        for k in 0..<10 {
            let l = k % 2 == 0 ? r : r * inner, a = CGFloat.pi / 2 + CGFloat(k) * .pi / 5
            let p = CGPoint(x: l * cos(a), y: l * sin(a))
            if k == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        path.close()
        return path
    }

    /// 粒子用的小星星：白色，外面一圈柔光
    static let star: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { c in
        let g = c.cgContext, path = starPath(19)
        path.apply(CGAffineTransform(translationX: 24, y: 24))
        g.setShadow(offset: .zero, blur: 5, color: UIColor.white.cgColor)
        g.setFillColor(UIColor.white.cgColor)
        g.addPath(path.cgPath)
        g.fillPath()
    }

    /// 樱花球里的花（经纬图，只用透明度）：一圈白色的五瓣小花，贴在球上跟着转
    static let blossomCore: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { c in
        let g = c.cgContext
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(40, 120, 26), (150, 80, 20), (240, 150, 28), (340, 95, 22), (440, 140, 26),
                                                    (95, 185, 14), (300, 200, 14), (400, 60, 13), (200, 50, 12), (490, 70, 12)]
        for (x, y, r) in spots {
            for k in 0..<5 {
                let a = CGFloat(k) * 2 * .pi / 5 + x
                g.saveGState()
                g.translateBy(x: x + cos(a) * r * 0.5, y: y + sin(a) * r * 0.5)
                g.rotate(by: a)
                g.setFillColor(UIColor(white: 1, alpha: 0.8).cgColor)
                g.fillEllipse(in: CGRect(x: -r * 0.5, y: -r * 0.3, width: r, height: r * 0.6))
                g.restoreGState()
            }
            g.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
            g.fillEllipse(in: CGRect(x: x - r * 0.18, y: y - r * 0.18, width: r * 0.36, height: r * 0.36))
        }
    }

    /// 雪球上一闪一闪的冰晶（只用透明度）
    static let snowSpecks: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 128)).image { c in
        var rng = SeededRandom("snowball")
        for _ in 0..<160 {
            let x = CGFloat.random(in: 0...256, using: &rng), y = CGFloat.random(in: 8...120, using: &rng)
            let r = CGFloat.random(in: 0.6...1.8, using: &rng)
            c.cgContext.setFillColor(UIColor(white: 1, alpha: CGFloat.random(in: 0.4...1, using: &rng)).cgColor)
            c.cgContext.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// 霓虹球上的发光线（只用透明度）：一道粗的赤道、两道细的纬线、四道经线
    static let neonLines: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { c in
        let g = c.cgContext
        g.setFillColor(UIColor.white.cgColor)
        for (y, h) in [(128.0, 9.0), (70.0, 3.0), (186.0, 3.0)] { g.fill(CGRect(x: 0, y: y - h / 2, width: 512, height: h)) }
        for x in stride(from: 0.0, to: 512, by: 128) { g.fill(CGRect(x: x - 2, y: 0, width: 4, height: 256)) }
    }

    /// 南瓜皮（经纬图）：橘色，一道道竖着的深色瓣沟
    static let pumpkin: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 128)).image { c in
        let g = c.cgContext
        let colors = [UIColor.rgb(0.78, 0.36, 0.08), UIColor.rgb(1, 0.6, 0.2), UIColor.rgb(1, 0.66, 0.26), UIColor.rgb(0.78, 0.36, 0.08)]
            .map(\.cgColor) as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.65, 1])!
        for k in 0..<12 {
            let x0 = CGFloat(k) * 512 / 12
            g.saveGState()
            g.clip(to: CGRect(x: x0, y: 0, width: 512 / 12, height: 128))
            g.drawLinearGradient(grad, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x0 + 512 / 12, y: 0), options: [])
            g.restoreGState()
        }
    }

    /// 树皮：深浅两种棕色的竖纹，按长度重复铺
    static let bark: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { c in
        let g = c.cgContext
        UIColor.rgb(0.45, 0.3, 0.2).setFill()
        g.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        var rng = SeededRandom("bark")
        for _ in 0..<26 {
            let y = CGFloat.random(in: 0...128, using: &rng), w = CGFloat.random(in: 30...90, using: &rng)
            let x = CGFloat.random(in: 0...128, using: &rng), h = CGFloat.random(in: 2...5, using: &rng)
            let dark = Bool.random(using: &rng)
            g.setFillColor((dark ? UIColor.rgb(0.32, 0.2, 0.13) : UIColor.rgb(0.56, 0.4, 0.27)).cgColor)
            for dx: CGFloat in [-128, 0, 128] {
                g.fill(CGRect(x: x + dx, y: y, width: w, height: h))
            }
        }
    }

    /// 木头截面的年轮：浅木色上一圈圈深一点的环
    static let rings: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { c in
        let g = c.cgContext
        UIColor.rgb(0.93, 0.78, 0.56).setFill()
        g.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        g.setStrokeColor(UIColor.rgb(0.78, 0.58, 0.38).cgColor)
        for r in stride(from: CGFloat(8), through: 60, by: 9) {
            g.setLineWidth(r > 54 ? 6 : 2)
            g.strokeEllipse(in: CGRect(x: 64 - r, y: 64 - r, width: 2 * r, height: 2 * r))
        }
    }
}
