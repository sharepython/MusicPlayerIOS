import SceneKit
import UIKit

/// 各个主题的小球：原来是玻璃弹珠；星夜是一颗发光的小星球、樱花是里面开着花的玻璃球、雪国是雪球、
/// 深海是一颗珍珠、霓虹是缠着发光线的黑球、秋林是一个带蒂的小南瓜
extension RhythmScene {
    /// marble 是原来的玻璃弹珠材质，classic 用它
    func ballMaterial(marble: SCNMaterial) -> SCNMaterial {
        func vec(_ c: UIColor) -> String {
            let x = c.components
            return "float3(\(x.r), \(x.g), \(x.b))"
        }
        let c = vec(theme.ball)
        switch theme.look {
        case .classic: return marble
        case .blossom:
            marble.diffuse.contents = RhythmArt.blossomCore
            return marble
        case .crystal:
            // 中间亮、边上一圈更亮的光晕，左上一个高光点
            let m = Self.flat(.white)
            m.shaderModifiers = [.fragment: """
                float3 n = _surface.normal;
                float e = 1.0 - saturate(dot(n, _surface.view));
                float spot = pow(saturate(dot(n, normalize(float3(-0.45, 0.55, 0.7)))), 40.0);
                float3 c = mix(float3(1.0, 0.98, 0.85), \(c), smoothstep(0.1, 0.9, e)) + spot;
                _output.color = float4(min(c * (1.0 + 0.6 * e), float3(1.0)), 1.0);
                """]
            return m
        case .ice:
            let m = Self.lit(.rgb(0.96, 0.98, 1), shine: 10)
            m.emission.contents = RhythmArt.snowSpecks
            m.emission.intensity = 0.5
            m.shaderModifiers = [.fragment: """
                float e = 1.0 - saturate(dot(_surface.normal, _surface.view));
                _output.color.rgb = mix(_output.color.rgb, \(c), e * e * 0.7);
                """]
            return m
        case .reef:
            // 珍珠：乳白底、斜着看泛出彩虹色，一个亮亮的高光
            let m = Self.lit(.rgb(0.96, 0.95, 0.98), shine: 90)
            m.shaderModifiers = [.fragment: """
                float e = 1.0 - saturate(dot(_surface.normal, _surface.view));
                float3 rainbow = 0.5 + 0.5 * cos(6.2832 * (e * 1.3 + float3(0.0, 0.33, 0.67)));
                _output.color.rgb = mix(_output.color.rgb, rainbow * \(c) * 1.4, e * 0.6) + 0.15;
                """]
            return m
        case .neon:
            let m = Self.flat(.white)
            m.diffuse.contents = RhythmArt.neonLines
            m.shaderModifiers = [.fragment: """
                float e = 1.0 - saturate(dot(_surface.normal, _surface.view));
                float line = _surface.diffuse.a;
                float3 c = mix(float3(0.06, 0.04, 0.1), \(c) * 1.3, line) + \(c) * pow(e, 3.0) * 0.8;
                _output.color = float4(min(c, float3(1.0)), 1.0);
                """]
            return m
        case .forest:
            let m = Self.lit(.white, shine: 30)
            m.diffuse.contents = RhythmArt.pumpkin
            return m
        }
    }

    /// 挂在小球上的东西：星夜、霓虹外面一圈柔光，秋林一截瓜蒂和一片叶子
    func dressBall() {
        let u = Self.unit, r = RhythmStage.ballRadius
        switch theme.look {
        case .crystal, .neon:
            let plane = SCNPlane(width: r * 4.4 * u, height: r * 4.4 * u)
            let m = Self.flat(theme.look == .neon ? theme.ball : .rgb(1, 0.86, 0.5))
            m.diffuse.contents = RhythmArt.dot
            m.multiply.contents = theme.look == .neon ? theme.ball : UIColor.rgb(1, 0.86, 0.5)
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.transparency = 0.6
            plane.materials = [m]
            let halo = SCNNode(geometry: plane)
            halo.constraints = [SCNBillboardConstraint()]
            halo.renderingOrder = Self.ballOrder - 1
            ball.addChildNode(halo)
        case .forest:
            let stem = SCNCylinder(radius: 2.4 * u, height: 7 * u)
            stem.materials = [Self.lit(.rgb(0.42, 0.5, 0.25), shine: 10)]
            let n = SCNNode(geometry: stem)
            n.simdPosition = [0, Float((r + 2) * u), 0]
            n.eulerAngles.z = 0.25
            ball.addChildNode(n)
            let leaf = blob([6, 1, 3.5], at: [5, Float(r) + 1, 0], Self.lit(.rgb(0.4, 0.62, 0.3), shine: 10))
            leaf.eulerAngles.z = -0.4
            ball.addChildNode(leaf)
            ball.simdScale = [1.06, 0.92, 1.06]
        default: break
        }
    }
}
