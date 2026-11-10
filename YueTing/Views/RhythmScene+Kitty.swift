import SceneKit
import UIKit

/// 唱完后接球的小白猫：趴在自己家里（RhythmScene+House），两只前爪伸在前面，脸朝着门口飞进来的球。
/// 球落在门口、滚回它爪子前面；之后它一爪子把球拍出去，看着球滚远又滚回来，再用两只爪子按住；
/// 每三回有一回把球往上一捞，球蹦两下。脑袋一直跟着球，耳朵时不时抖一下，会眨眼，尾巴一直慢慢摇。
/// 和小狗一样用球、胶囊和圆锥拼出来
extension RhythmScene {
    @MainActor func buildKitty() {
        guard !stage.tiles.isEmpty else { return }
        let u = Float(Self.unit), k = stage.kitty
        let fur = furMaterial(UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1), shine: 6)
        let pink = furMaterial(UIColor(red: 1, green: 0.62, blue: 0.74, alpha: 1), shine: 30)
        let rose = furMaterial(UIColor(red: 1, green: 0.42, blue: 0.62, alpha: 1), shine: 60)
        let iris = furMaterial(UIColor(red: 0.36, green: 0.62, blue: 0.98, alpha: 1), shine: 120)
        let dark = furMaterial(UIColor(white: 0.06, alpha: 1), shine: 120)
        let white = SCNMaterial()
        white.lightingModel = .constant
        white.diffuse.contents = UIColor.white
        buildHouse(stage.kittyRoom, .kitty, pet: k.x, into: kittyShelf)

        kittyNode.simdPosition = v(Point3(x: k.x, y: k.y, z: k.z - 8))
        kittyNode.simdOrientation = simd_quatf(angle: Float(stage.kittyDir) * 0.9, axis: [0, 1, 0])
        kittyNode.addChildNode(kittyBody)
        // 趴着的身子、鼓鼓的胸口、两边的后腿和后脚
        kittyBody.addChildNode(blob([15, 11, 21], at: [0, 11, -8], fur))
        kittyBody.addChildNode(blob([12, 11, 10], at: [0, 14, 6], fur))
        for s: Float in [-1, 1] {
            kittyBody.addChildNode(blob([8, 9, 11], at: [s * 8, 9, -18], fur))
            kittyBody.addChildNode(blob([4.5, 3, 6], at: [s * 11, 3, -6], fur))
            // 两只前腿往前伸着，绕肩膀转就是抬爪子
            let paw = SCNNode()
            paw.simdPosition = SIMD3<Float>(s * 6.5, 5, 8) * u
            let capsule = SCNCapsule(capRadius: 3.8 * Self.unit, height: 16 * Self.unit)
            capsule.materials = [fur]
            let shin = SCNNode(geometry: capsule)
            shin.simdPosition = SIMD3<Float>(0, 0, 6) * u
            shin.eulerAngles.x = .pi / 2
            paw.addChildNode(shin)
            paw.addChildNode(blob([4.5, 3.2, 5], at: [0, -1, 14], fur))
            paw.addChildNode(blob([1.6, 1, 1], at: [0, -2.6, 17.5], pink))
            kittyBody.addChildNode(paw)
            kittyPaws.append(paw)
        }

        // 脑袋：圆脑袋、两团嘴巴、小下巴、粉鼻头、蓝眼睛、粉脸蛋、尖耳朵、胡子，左耳上一个蝴蝶结
        kittyHead.simdPosition = SIMD3<Float>(0, 24, 10) * u
        kittyBody.addChildNode(kittyHead)
        kittyHead.addChildNode(blob([14, 12.5, 12.5], at: [0, 6, 0], fur))
        kittyHead.addChildNode(blob([4, 2.5, 3.5], at: [0, -1, 9.5], fur))
        kittyHead.addChildNode(blob([1.8, 1.3, 1.2], at: [0, 4.6, 13.2], rose))
        let whisker = furMaterial(UIColor(white: 0.78, alpha: 1), shine: 30)
        for s: Float in [-1, 1] {
            kittyHead.addChildNode(blob([4.8, 3.8, 4], at: [s * 3.6, 1.8, 10.5], fur))
            let eye = SCNNode()
            eye.simdPosition = SIMD3<Float>(s * 5.8, 7.5, 10.3) * u
            eye.eulerAngles.y = s * 0.25
            eye.addChildNode(blob([3, 3.6, 1.6], at: [0, 0, 0], iris))
            eye.addChildNode(blob([1.5, 2.6, 0.8], at: [0, 0, 1.2], dark))
            eye.addChildNode(blob([0.9, 0.9, 0.5], at: [-0.9, 1.2, 1.9], white))
            kittyHead.addChildNode(eye)
            kittyEyes.append(eye)
            kittyHead.addChildNode(blob([2.6, 1.6, 0.8], at: [s * 9.5, 2.5, 9], pink))
            let ear = SCNNode()
            ear.simdPosition = SIMD3<Float>(s * 8.5, 15.5, -1) * u
            ear.eulerAngles.z = -s * 0.3
            ear.simdScale = [1, 1, 0.55]
            let cone = SCNCone(topRadius: 0, bottomRadius: 5.5 * Self.unit, height: 11 * Self.unit)
            cone.materials = [fur]
            let outer = SCNNode(geometry: cone)
            outer.simdPosition = SIMD3<Float>(0, 5, 0) * u
            ear.addChildNode(outer)
            let lining = SCNCone(topRadius: 0, bottomRadius: 3.6 * Self.unit, height: 8 * Self.unit)
            lining.materials = [pink]
            let inner = SCNNode(geometry: lining)
            inner.simdPosition = SIMD3<Float>(0, 4.5, 2.4) * u
            ear.addChildNode(inner)
            kittyHead.addChildNode(ear)
            kittyEars.append(ear)
            for w: Float in [-1, 0, 1] {
                let a = SIMD3<Float>(s * 6.5, 2.2 + w * 0.8, 11.5) * u, b = SIMD3<Float>(s * 17, 3 + w * 2.6, 10 - abs(w)) * u
                kittyHead.addChildNode(RhythmArt.rod(a, b, radius: 0.3 * Self.unit, material: whisker))
            }
        }
        let bow = SCNNode()
        bow.simdPosition = SIMD3<Float>(-7, 15.5, 4) * u
        bow.eulerAngles.z = 0.35
        for s: Float in [-1, 1] {
            let wing = blob([3.6, 2.4, 1.4], at: [s * 3.2, 0, 0], rose)
            wing.eulerAngles.z = s * 0.35
            bow.addChildNode(wing)
        }
        bow.addChildNode(blob([1.6, 1.6, 1.6], at: [0, 0, 0.6], rose))
        kittyHead.addChildNode(bow)

        // 尾巴：从屁股后面竖起来、尖上往旁边卷，沿着这条线一颗挨一颗地叠白毛球（和身子同一种毛，接缝看不出来），
        // 越往尖越细一点，尖上一团圆头；摇的时候整根绕根部转
        let tail = SCNNode()
        tail.simdPosition = SIMD3<Float>(0, 7, -26) * u
        var p = SIMD3<Float>(0, 0, 0), path = [p]
        for j in 1...24 {
            let s = Float(j) / 24, phi = 0.15 + 2.5 * s * s
            p += SIMD3<Float>(sin(phi), cos(phi), -0.28) * 1.35
            path.append(p)
        }
        for (j, q) in path.enumerated() {
            let r = 3 - 0.4 * Float(j) / Float(path.count - 1)
            tail.addChildNode(blob([r, r, r], at: q, fur))
        }
        tail.addChildNode(blob([3.4, 3.4, 3.4], at: path[path.count - 1], fur))
        kittyBody.addChildNode(tail)
        kittyTail = [tail]
        kittyHide(true)
        scene.rootNode.addChildNode(kittyNode)
    }

    private func kittyHide(_ hide: Bool) {
        kittyNode.isHidden = hide
        kittyShelf.isHidden = hide
    }

    /// 小猫的家进了要画的范围（view，和卡片组一样在画面下沿以下多留一截）就显示，免得镜头移过去时突然冒出来；
    /// 脑袋看着球，前爪按玩球的节奏抬起、拍下
    func updateKitty(_ t: Double, ball b: RhythmStage.Ball, view: ClosedRange<CGFloat>) {
        let r = stage.kittyRoom
        let hide = !(r.top - 20...r.floor + 60).overlaps(view)
        if kittyNode.isHidden != hide {
            kittyHide(hide)
        }
        guard !hide else { return }
        let dir = Float(stage.kittyDir), k = stage.kitty
        let since = t - stage.catchAt

        // 脑袋看着球心：球在上面就抬头，在面前搁板上就低头看；脸稍微往镜头这边偏，歪着头
        let c = Point3(x: b.ground.x, y: b.ground.y - b.lift - RhythmStage.ballRadius, z: b.ground.z)
        let ahead = max((c.x - k.x) * CGFloat(dir) - 14, 12), up = (k.y - 30) - c.y
        let pitch = min(max(-Float(atan2(up, ahead)), -0.7), 0.45)
        let roll = 0.16 * Float(sin(1.7 * t)) + (since > 0 ? 0.06 : 0)
        kittyHead.simdOrientation = simd_quatf(angle: -dir * 0.35, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])

        // 球飞过来前扭屁股，准备扑
        let wiggle = since < 0 && since > -1.2 ? 0.08 * Float(sin(2 * .pi * 4.5 * t)) : 0
        let breathe = 1 + 0.02 * Float(sin(2 * .pi * t / 1.6))
        kittyBody.simdOrientation = simd_quatf(angle: wiggle, axis: [0, 1, 0])
        kittyBody.simdScale = [1, breathe, 1]

        // 两只前爪（0 在 -x 那边，1 在 +x 那边）：抬起多少（弧度）和往前伸多少
        var lift: [Float] = [0, 0], reach: [Float] = [0, 0]
        let near = dir > 0 ? 0 : 1  // 靠镜头那只，用它拍球
        if since < 0 {
            if since > -0.5 {
                let q = Float(since + 0.5) / 0.5
                lift = [0.6 * q, 0.6 * q]
            }
        } else {
            let (n, u) = stage.kittyPhase(t)
            let scoop = RhythmStage.kittyScoops(n), next = RhythmStage.kittyScoops(n + 1)
            func bump(_ a: Double, _ b: Double) -> Float {
                u > a && u < b ? Float(sin(.pi * (u - a) / (b - a))) : 0
            }
            if scoop {
                let up = 1.0 * bump(-0.01, 0.22) + 0.7 * bump(0.5, 0.75)
                lift = [up, up]
                reach = [3 * up, 3 * up]
            } else {
                if u < 0.15 {
                    let q = Float(u / 0.15)
                    lift[near] = 1.3 * (1 - q)
                    reach[near] = 7 * sin(.pi * q)
                }
                if u > 2.2, !next {
                    let q = Float(min((u - 2.2) / 0.3, 1))
                    lift[near] = 1.3 * q * q * (3 - 2 * q)
                }
                let pat = 0.45 * bump(1.82, 2.12)
                lift = lift.map { max($0, pat) }
                if u > 2.3, next {
                    let q = Float(min((u - 2.3) / 0.3, 1))
                    lift = lift.map { max($0, 0.3 * q) }
                }
            }
        }
        for (i, paw) in kittyPaws.enumerated() {
            let s: Float = i == 0 ? -1 : 1
            paw.simdOrientation = simd_quatf(angle: -lift[i], axis: [1, 0, 0])
            paw.simdPosition = SIMD3<Float>(s * 6.5, 5, 8 + reach[i]) * Float(Self.unit)
        }

        // 耳朵隔一会抖一下，隔一会眨一下眼
        let twitch = t.truncatingRemainder(dividingBy: 3.3) < 0.18 ? 0.25 * Float(sin(.pi * t.truncatingRemainder(dividingBy: 3.3) / 0.09)) : 0
        for (i, ear) in kittyEars.enumerated() {
            let s: Float = i == 0 ? -1 : 1
            ear.eulerAngles.z = -s * 0.3 + (i == 1 ? twitch : 0)
        }
        let w = t.truncatingRemainder(dividingBy: 4.1), blink: Float = w < 0.14 ? 0.15 + 0.85 * abs(Float(cos(.pi * w / 0.14))) : 1
        for eye in kittyEyes { eye.simdScale = [1, blink, 1] }

        // 尾巴左右慢慢摇，尖上那团跟着画个小圈；接到球以后摇得更欢
        let amp: Float = since > 0 ? 0.32 : 0.2, f = since > 0 ? 1.1 : 0.6, w2 = 2 * .pi * f * t
        kittyTail.first?.simdOrientation = simd_quatf(angle: amp * Float(sin(w2)), axis: [0, 0, 1])
            * simd_quatf(angle: 0.5 * amp * Float(sin(w2 - 1.2)), axis: [0, 1, 0])
    }
}
