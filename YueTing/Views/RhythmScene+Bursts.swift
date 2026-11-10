import SceneKit
import UIKit

/// 踩中时卡片的动作和溅起来的东西，按主题各不一样
extension RhythmScene {
    /// 落下来那一下之后 since 秒卡片的样子：都先往下压一下；水晶转一下、樱花转着弹一弹、冰块晃两下、
    /// 水母伞一缩一张、蘑菇被压扁再弹回来、霓虹闪着胀一下
    func react(_ i: Int, since s: Double) {
        let t = Float(max(s, 0)), u = Float(Self.unit)
        let press: Float = t < 0.2 ? 1 - t / 0.2 : 0
        // 衰减的弹簧：0 秒时 0，很快冲到 1 再来回晃着停下
        let spring: Float = t < 1 ? exp(-t * 6) * sin(t * 24) : 0
        func ease(_ x: Float) -> Float {
            let x = min(max(x, 0), 1)
            return x * x * (3 - 2 * x)
        }
        var turn: Float = 0, wobble: Float = 0, squash: Float = 0, grow: Float = 0, depth: Float = 4
        switch theme.look {
        case .classic: break
        case .crystal: turn = t < 0.6 ? .pi / 3 * ease(t / 0.6) : 0
        case .blossom: turn = t < 0.7 ? 2 * .pi / 5 * ease(t / 0.7) : 0; squash = 0.2 * spring
        case .ice: wobble = 0.1 * spring
        case .reef: squash = 0.28 * spring; depth = 7
        case .neon: grow = t < 0.3 ? 0.14 * (1 - t / 0.3) : 0
        case .forest: squash = 0.34 * spring; depth = 2
        }
        let key = keys[i]
        key.simdPosition = keyRest[i] + keyBase[i].act([0, -depth * u * press, 0])
        guard theme.look != .classic else { return }
        key.simdOrientation = keyBase[i] * simd_quatf(angle: turn, axis: [0, 1, 0]) * simd_quatf(angle: wobble, axis: [0, 0, 1])
        let side = 1 + squash * 0.5 + grow
        key.simdScale = [side, 1 - squash + grow, side]
    }

    /// 踩中时：顶面上一圈扩散的光环，再溅出一些东西。原来是往上溅再落下的光点；水晶溅星星、樱花飘花瓣、
    /// 冰块扬起一圈雪粉、水母吐泡泡往上冒、霓虹的光环更大更快、火花更亮，蘑菇喷一团孢子带两片叶子
    func burst(_ i: Int) {
        let p = v(stage.landing(i)) + keys[i].simdOrientation.act([0, 0.01, 0])
        let color = UIColor(hue: stage.tiles[i].hue, saturation: theme.spark, brightness: 1, alpha: 1)
        let torus = rings[nextRing % rings.count]
        nextRing += 1
        torus.removeAllActions()
        torus.simdPosition = p
        torus.simdOrientation = keyBase[i]
        torus.scale = SCNVector3(1, 1, 1)
        torus.opacity = theme.look == .neon ? 1 : 0.7
        let spread: CGFloat = theme.look == .neon ? 3.6 : theme.look == .reef ? 1.8 : 2.5
        torus.runAction(.group([.scale(to: spread, duration: 0.45), .fadeOut(duration: 0.45)]))

        let sparks = SCNParticleSystem()
        sparks.birthRate = 250
        sparks.emissionDuration = 0.03
        sparks.loops = false
        sparks.particleLifeSpan = 0.5
        sparks.particleLifeSpanVariation = 0.15
        sparks.particleSize = 0.028
        sparks.particleImage = RhythmArt.dot
        sparks.particleColor = color.withAlphaComponent(0.55)
        sparks.particleVelocity = 1.3
        sparks.particleVelocityVariation = 0.5
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.spreadingAngle = 60
        sparks.acceleration = SCNVector3(0, -4, 0)
        sparks.blendMode = .alpha
        sparks.isLightingEnabled = false
        sparks.propertyControllers = [.opacity: fade(from: 1, to: 0)]
        switch theme.look {
        case .classic: break
        case .crystal:
            sparks.birthRate = 120
            sparks.particleImage = RhythmArt.star
            sparks.particleSize = 0.045
            sparks.particleSizeVariation = 0.02
            sparks.particleColor = theme.ring.withAlphaComponent(0.9)
            sparks.particleLifeSpan = 0.8
            sparks.particleAngularVelocityVariation = 360
            sparks.acceleration = SCNVector3(0, -1.5, 0)
            sparks.blendMode = .additive
        case .blossom:
            sparks.birthRate = 90
            sparks.particleImage = RhythmArt.petal
            sparks.particleSize = 0.06
            sparks.particleSizeVariation = 0.02
            sparks.particleColor = theme.driftColor.withAlphaComponent(0.95)
            sparks.particleVelocity = 0.9
            sparks.particleLifeSpan = 1.1
            sparks.particleAngleVariation = 180
            sparks.particleAngularVelocityVariation = 400
            sparks.acceleration = SCNVector3(0.4, -1.2, 0)
            sparks.dampingFactor = 2
        case .ice:
            sparks.birthRate = 400
            sparks.particleSize = 0.03
            sparks.particleColor = UIColor.white.withAlphaComponent(0.85)
            sparks.particleVelocity = 0.7
            sparks.particleVelocityVariation = 0.4
            sparks.spreadingAngle = 85
            sparks.particleLifeSpan = 0.7
            sparks.acceleration = SCNVector3(0, -1.6, 0)
            sparks.dampingFactor = 2.5
        case .reef:
            sparks.birthRate = 80
            sparks.particleImage = RhythmArt.bubble
            sparks.particleSize = 0.04
            sparks.particleSizeVariation = 0.025
            sparks.particleColor = theme.driftColor.withAlphaComponent(0.9)
            sparks.particleVelocity = 0.5
            sparks.spreadingAngle = 35
            sparks.particleLifeSpan = 1.2
            sparks.acceleration = SCNVector3(0, 1.2, 0)
        case .neon:
            sparks.birthRate = 350
            sparks.particleSize = 0.022
            sparks.particleColor = UIColor(hue: stage.tiles[i].hue, saturation: 0.8, brightness: 1, alpha: 1)
            sparks.particleVelocity = 2
            sparks.spreadingAngle = 80
            sparks.particleLifeSpan = 0.4
            sparks.blendMode = .additive
        case .forest:
            sparks.birthRate = 160
            sparks.particleColor = UIColor.rgb(1, 0.92, 0.6).withAlphaComponent(0.6)
            sparks.particleSize = 0.022
            sparks.particleVelocity = 0.6
            sparks.spreadingAngle = 70
            sparks.particleLifeSpan = 1
            sparks.acceleration = SCNVector3(0, -0.3, 0)
            sparks.dampingFactor = 1.5
        }
        var systems = [sparks]
        if theme.look == .forest {
            let leaves = SCNParticleSystem()
            leaves.birthRate = 60
            leaves.emissionDuration = 0.03
            leaves.loops = false
            leaves.particleImage = RhythmArt.leaf
            leaves.particleSize = 0.06
            leaves.particleColor = theme.driftColor
            leaves.particleColorVariation = SCNVector4(0.05, 0.15, 0.1, 0)
            leaves.particleLifeSpan = 1.1
            leaves.particleVelocity = 0.9
            leaves.emittingDirection = SCNVector3(0, 1, 0)
            leaves.spreadingAngle = 50
            leaves.particleAngleVariation = 180
            leaves.particleAngularVelocityVariation = 300
            leaves.acceleration = SCNVector3(0, -1.8, 0)
            leaves.isLightingEnabled = false
            leaves.propertyControllers = [.opacity: fade(from: 1, to: 0)]
            systems.append(leaves)
        }
        // 粒子系统由渲染线程用完移除，加的时候要锁住场景
        SCNTransaction.lock()
        for s in systems { scene.addParticleSystem(s, transform: SCNMatrix4MakeTranslation(p.x, p.y, p.z)) }
        SCNTransaction.unlock()
    }
}
