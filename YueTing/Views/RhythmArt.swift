import CoreText
import SceneKit
import UIKit

/// 一首歌的配色：墙、卡片、磨砂管。每首歌按 id 挑一套，墙都是偏灰的浅色，卡片都是粉色系的亚克力
struct RhythmPalette {
    var wall: (CGFloat, CGFloat, CGFloat)
    var card: UIColor
    var tube: UIColor
    /// 墙上的小字（歌手）用的深色
    var ink: UIColor

    var wallColor: UIColor { UIColor(red: wall.0, green: wall.1, blue: wall.2, alpha: 1) }

    static let all: [RhythmPalette] = [
        // 视频里那套：灰蓝墙、粉卡片、淡紫管
        RhythmPalette(wall: (0.54, 0.59, 0.72), card: UIColor(red: 0.98, green: 0.62, blue: 0.72, alpha: 1),
                      tube: UIColor(red: 0.86, green: 0.80, blue: 0.96, alpha: 1), ink: UIColor(red: 0.2, green: 0.23, blue: 0.33, alpha: 1)),
        // 灰绿墙、樱花粉卡片
        RhythmPalette(wall: (0.56, 0.63, 0.58), card: UIColor(red: 0.99, green: 0.68, blue: 0.76, alpha: 1),
                      tube: UIColor(red: 0.80, green: 0.95, blue: 0.88, alpha: 1), ink: UIColor(red: 0.18, green: 0.25, blue: 0.2, alpha: 1)),
        // 暖灰墙、蜜桃粉卡片
        RhythmPalette(wall: (0.70, 0.65, 0.59), card: UIColor(red: 0.99, green: 0.66, blue: 0.68, alpha: 1),
                      tube: UIColor(red: 0.98, green: 0.84, blue: 0.80, alpha: 1), ink: UIColor(red: 0.3, green: 0.24, blue: 0.2, alpha: 1)),
        // 灰紫墙、玫瑰粉卡片
        RhythmPalette(wall: (0.61, 0.58, 0.73), card: UIColor(red: 0.97, green: 0.60, blue: 0.76, alpha: 1),
                      tube: UIColor(red: 0.80, green: 0.90, blue: 0.99, alpha: 1), ink: UIColor(red: 0.24, green: 0.2, blue: 0.33, alpha: 1)),
        // 灰青墙、浅粉卡片
        RhythmPalette(wall: (0.48, 0.61, 0.65), card: UIColor(red: 0.99, green: 0.70, blue: 0.78, alpha: 1),
                      tube: UIColor(red: 0.95, green: 0.88, blue: 0.75, alpha: 1), ink: UIColor(red: 0.15, green: 0.25, blue: 0.28, alpha: 1)),
    ]
}

/// 律动场景用到的贴图和几何体，都是现画的，不带图片资源
enum RhythmArt {
    /// 墙上的软影子：中间灰、往外变白。用相乘混合贴在墙上，白的地方不变暗
    static let shadow: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { c in
        UIColor.white.setFill()
        c.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let colors = [UIColor(white: 0.62, alpha: 1).cgColor, UIColor(white: 0.8, alpha: 1).cgColor, UIColor.white.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1])!
        c.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                       endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    /// 轨道在墙上的影子：横着一条，中间灰、两边变白（v 方向），沿着轨道拉长
    static let strip: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 64)).image { c in
        let colors = [UIColor.white.cgColor, UIColor(white: 0.72, alpha: 1).cgColor, UIColor.white.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
    }

    /// 粒子用的软光点
    static let dot: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { c in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        c.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                       endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }

    /// 镀铬金属反射的环境（经纬图）：上面是亮白的天，中间一道深色的地平线，下面是灰的地面再一道亮线。
    /// 反差大，细铁丝上也看得出一道道高光
    static let chrome: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 256)).image { c in
        let colors = [UIColor(white: 1, alpha: 1), UIColor(red: 0.82, green: 0.88, blue: 0.97, alpha: 1),
                      UIColor(white: 0.18, alpha: 1), UIColor(white: 0.42, alpha: 1), UIColor(white: 0.9, alpha: 1),
                      UIColor(white: 0.3, alpha: 1)].map(\.cgColor) as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.5, 0.62, 0.74, 1])!
        c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
    }

    /// 玻璃弹珠里面的花芯和小气泡（经纬图，只用透明度）：两条扭着的白带子绕一圈，几个小泡。贴在球上跟着转，看得出在滚
    static let marble: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { c in
        let g = c.cgContext
        for (amp, phase, width, alpha) in [(54.0, 0.0, 22.0, 0.85), (40.0, 2.2, 9.0, 0.55)] {
            let path = CGMutablePath()
            for x in stride(from: 0.0, through: 512, by: 4) {
                let y = 128 + amp * sin(2 * .pi * x / 512 * 2 + phase)
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            g.addPath(path)
            g.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
            g.setLineWidth(width)
            g.setLineCap(.round)
            g.strokePath()
        }
        let bubbles: [(CGFloat, CGFloat, CGFloat)] = [(60, 70, 6), (150, 190, 4), (230, 60, 5), (330, 170, 7), (420, 90, 4),
                                                       (470, 200, 5), (280, 120, 3), (110, 140, 3)]
        for (x, y, r) in bubbles {
            g.setFillColor(UIColor(white: 1, alpha: 0.25).cgColor)
            g.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            g.setStrokeColor(UIColor(white: 1, alpha: 0.7).cgColor)
            g.setLineWidth(1.5)
            g.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// 字的贴图，按 64 号字画：宋体白字，底下往右下叠几层灰色的字当厚度，像一块立着的字，用的时候乘上颜色。同一个字只画一次
    @MainActor private static var labels: [String: UIImage] = [:]

    @MainActor static func label(_ s: String) -> UIImage {
        if let image = labels[s] {
            return image
        }
        let font = lyricFont(for: s, size: 64), depth: CGFloat = 4
        let face: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = (s as NSString).size(withAttributes: face)
        let image = UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width + depth) + 8, height: ceil(size.height + depth) + 8)).image { _ in
            for j in stride(from: depth, to: 0, by: -1) {
                let side: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.62 + 0.06 * (depth - j), alpha: 1)]
                (s as NSString).draw(at: CGPoint(x: 4 + j * 0.6, y: 4 + j), withAttributes: side)
            }
            (s as NSString).draw(at: CGPoint(x: 4, y: 4), withAttributes: face)
        }
        labels[s] = image
        return image
    }

    /// 歌词用宋体。iOS 自带的宋体要先下载（loadLyricFont），没下好时用自带的明朝体，明朝体里缺字再用苹方
    private static let songti = "STSongti-SC-Regular", mincho = "HiraMinProN-W3"

    @MainActor private static func lyricFont(for s: String, size: CGFloat) -> UIFont {
        for name in [songti, mincho] {
            guard let font = UIFont(name: name, size: size) else { continue }
            let chars = Array(s.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            if CTFontGetGlyphsForCharacters(font as CTFont, chars, &glyphs, chars.count) {
                return font
            }
        }
        return UIFont(name: "PingFangSC-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    /// 后台下载系统的宋体（只下一次，之后一直在），下好后清掉已经画好的字，下一首歌就用宋体
    static func loadLyricFont() {
        guard UIFont(name: songti, size: 12) == nil else { return }
        let want = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: songti] as CFDictionary)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([want] as CFArray, nil) { state, _ in
            if state == .didFinish {
                Task { @MainActor in labels.removeAll() }
            }
            return true
        }
    }

    /// 连接两点的圆柱（支架、横档用）
    static func rod(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let d = b - a, len = simd_length(d)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(len))
        cylinder.radialSegmentCount = 8
        cylinder.materials = [material]
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (a + b) / 2
        if len > 0 {
            node.simdOrientation = simd_quatf(from: [0, 1, 0], to: d / len)
        }
        return node
    }

    /// 一个小球（柱头、底座用）
    static func knob(_ p: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 10
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.simdPosition = p
        return node
    }

    /// 支架插进墙里的地方：墙上一块圆的金属底座
    static func mount(_ p: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let disc = SCNCylinder(radius: radius, height: radius * 0.5)
        disc.radialSegmentCount = 16
        disc.materials = [material]
        let node = SCNNode(geometry: disc)
        node.simdPosition = SIMD3(p.x, p.y, Float(radius * 0.25))
        node.eulerAngles.x = .pi / 2
        return node
    }

    /// 两点之间的「侧向」：路径都在和墙平行的平面里，和 z 轴叉乘，竖着走的地方也不会退化
    private static func side(_ path: [SIMD3<Float>], _ k: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        let t = simd_normalize(path[min(k + 1, path.count - 1)] - path[max(k - 1, 0)])
        return (t, simd_normalize(simd_cross(t, [0, 0, 1])))
    }

    /// 沿着 path 扫出一根圆管（铁轨、磨砂管用），法线朝外，两头不封口
    static func sweep(_ path: [SIMD3<Float>], radius r: Float, sides n: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
        let m = n + 1
        for k in path.indices {
            let (t, side) = side(path, k)
            let up = simd_cross(side, t)
            for j in 0...n {
                let a = 2 * Float.pi * Float(j) / Float(n)
                let d = side * cos(a) + up * sin(a)
                vertices.append(SCNVector3(path[k] + d * r))
                normals.append(SCNVector3(d))
            }
            guard k > 0 else { continue }
            let b = UInt32((k - 1) * m), e = UInt32(k * m)
            for j in 0..<UInt32(n) { indices += [b + j, b + j + 1, e + j, b + j + 1, e + j + 1, e + j] }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// 沿着 path 铺一条宽 w 的平带（贴在墙上的影子），v 从一边 0 到另一边 1
    static func ribbon(_ path: [SIMD3<Float>], width w: Float) -> SCNGeometry {
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [UInt32] = []
        for k in path.indices {
            let (_, side) = side(path, k)
            vertices += [SCNVector3(path[k] - side * w / 2), SCNVector3(path[k] + side * w / 2)]
            uv += [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)]
            guard k > 0 else { continue }
            let b = UInt32(2 * (k - 1))
            indices += [b, b + 1, b + 2, b + 1, b + 3, b + 2]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
