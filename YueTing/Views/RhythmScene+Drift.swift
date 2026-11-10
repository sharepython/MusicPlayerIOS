import SceneKit
import UIKit

/// 主题里飘在画面中的东西：雪、花瓣、萤火虫、气泡、霓虹光点、落叶。
/// 一个粒子系统挂在镜头下面、跟着镜头走，发射区是镜头前一块盒子（离镜头 230 到 550 点，正好在卡片前面），
/// 一进来就已经飘满（warmup），每颗慢慢出现、慢慢消失。不受灯光影响，画在最上面
extension RhythmScene {
    func buildDrift() {
        guard let kind = theme.drift else { return }
        let near: CGFloat = 230, far: CGFloat = 550, mid = (near + far) / 2
        // 镜头前距离 D 处：画面半宽 D / sx、半高 D × a / sx，中心往下 D × a / (3 sx)（视线落在 1/3 处）
        let sx = (RhythmStage.eyeDistance - RhythmStage.keyGap - RhythmStage.keyLength / 2) / (stage.width / 2 + 16)
        let a: CGFloat = 2.3, u = Self.unit
        let box = SCNBox(width: 2 * far / sx * u, height: 2 * far * a / sx * u, length: (far - near) * u, chamferRadius: 0)

        let p = SCNParticleSystem()
        p.emitterShape = box
        p.birthLocation = .volume
        p.isLocal = true
        p.isLightingEnabled = false
        p.blendMode = .alpha
        p.sortingMode = .none
        p.particleColor = theme.driftColor
        p.particleImage = RhythmArt.dot
        p.propertyControllers = [.opacity: Self.fadeInOut()]
        switch kind {
        case .snow:
            p.particleSize = 0.045
            p.particleSizeVariation = 0.025
            p.particleColor = theme.driftColor.withAlphaComponent(0.85)
            p.emittingDirection = SCNVector3(0.1, -1, 0)
            p.spreadingAngle = 20
            p.particleVelocity = 0.3
            p.particleVelocityVariation = 0.12
            p.particleLifeSpan = 9
            p.birthRate = 14
        case .petals:
            p.particleImage = RhythmArt.petal
            p.particleSize = 0.07
            p.particleSizeVariation = 0.03
            p.particleColor = theme.driftColor.withAlphaComponent(0.9)
            p.particleColorVariation = SCNVector4(0.02, 0.15, 0.05, 0)
            p.emittingDirection = SCNVector3(0.45, -1, 0)
            p.spreadingAngle = 25
            p.particleVelocity = 0.35
            p.particleVelocityVariation = 0.12
            p.particleAngleVariation = 180
            p.particleAngularVelocity = 50
            p.particleAngularVelocityVariation = 100
            p.particleLifeSpan = 9
            p.birthRate = 8
        case .fireflies:
            p.particleSize = 0.07
            p.particleSizeVariation = 0.035
            p.blendMode = .additive
            p.spreadingAngle = 180
            p.particleVelocity = 0.07
            p.particleVelocityVariation = 0.05
            p.particleLifeSpan = 6
            p.particleLifeSpanVariation = 2
            p.birthRate = 6
        case .bubbles:
            p.particleImage = RhythmArt.bubble
            p.particleSize = 0.05
            p.particleSizeVariation = 0.035
            p.emittingDirection = SCNVector3(0, 1, 0)
            p.spreadingAngle = 10
            p.particleVelocity = 0.3
            p.particleVelocityVariation = 0.15
            p.particleLifeSpan = 8
            p.birthRate = 10
        case .sparks:
            p.particleSize = 0.035
            p.particleSizeVariation = 0.02
            p.blendMode = .additive
            p.particleColorVariation = SCNVector4(0.25, 0.2, 0, 0)
            p.spreadingAngle = 180
            p.particleVelocity = 0.12
            p.particleVelocityVariation = 0.08
            p.particleLifeSpan = 5
            p.particleLifeSpanVariation = 1.5
            p.birthRate = 14
        case .leaves:
            p.particleImage = RhythmArt.leaf
            p.particleSize = 0.1
            p.particleSizeVariation = 0.04
            p.particleColorVariation = SCNVector4(0.04, 0.1, 0.15, 0)
            p.emittingDirection = SCNVector3(-0.3, -1, 0)
            p.spreadingAngle = 25
            p.particleVelocity = 0.4
            p.particleVelocityVariation = 0.12
            p.particleAngleVariation = 180
            p.particleAngularVelocity = 70
            p.particleAngularVelocityVariation = 120
            p.particleLifeSpan = 8
            p.birthRate = 6
        }
        p.warmupDuration = p.particleLifeSpan

        let node = SCNNode()
        node.simdPosition = SIMD3(0, Float(-mid * a / (3 * sx) * u), Float(-mid * u))
        node.renderingOrder = Self.driftOrder
        node.addParticleSystem(p)
        cameraNode.addChildNode(node)
    }

    /// 每颗粒子前 15% 的时间慢慢出现、最后 20% 慢慢消失
    private static func fadeInOut() -> SCNParticlePropertyController {
        let anim = CAKeyframeAnimation()
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, 0.15, 0.8, 1]
        return SCNParticlePropertyController(animation: anim)
    }
}
