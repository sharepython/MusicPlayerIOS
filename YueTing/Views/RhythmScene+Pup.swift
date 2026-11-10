import SceneKit
import UIKit

/// 前奏时在歌名下面玩球的小白狗：坐在自己家里（RhythmScene+House），身子朝着门口的球。
/// 球在它面前一下下蹦，它抬起一只前爪，球落下来时往下一拍，脑袋跟着球上下看，耳朵一甩一甩，尾巴一直摇；
/// 开唱前一爪子把球拍出去，自己高兴地蹦一下，低头看着球落到第一张卡片上。都用球和胶囊拼出来
extension RhythmScene {
    @MainActor func buildPup() {
        let u = Self.unit, p = stage.pup, dir = Float(stage.pupDir)
        let fur = furMaterial(UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1), shine: 6)
        let pink = furMaterial(UIColor(red: 1, green: 0.55, blue: 0.68, alpha: 1), shine: 30)
        let dark = furMaterial(UIColor(white: 0.05, alpha: 1), shine: 120)
        let white = SCNMaterial()
        white.lightingModel = .constant
        white.diffuse.contents = UIColor.white
        buildHouse(stage.pupRoom, .pup, pet: p.x, into: pupShelf)

        pupNode.simdPosition = v(Point3(x: p.x, y: p.y, z: p.z - 8))
        pupNode.simdOrientation = simd_quatf(angle: dir * 0.55, axis: [0, 1, 0])
        let body = SCNNode()
        pupNode.addChildNode(body)
        // 身子、胸口一团毛、坐着的后腿和脚
        body.addChildNode(blob([18, 21, 18], at: [0, 20, -3], fur))
        body.addChildNode(blob([12, 12, 11], at: [0, 25, 8], fur))
        for s: Float in [-1, 1] {
            body.addChildNode(blob([10, 9, 12], at: [s * 11, 10, -6], fur))
            body.addChildNode(blob([6, 4, 9], at: [s * 13, 3.5, 6], fur))
        }
        // 两只前腿：一只撑着，一只（球那边的）抬起来拍球
        let side = dir
        body.addChildNode(leg(at: [-side * 7, 17, 9], fur))
        pupPaw.simdPosition = SIMD3<Float>(side * 7, 17, 9) * Float(u)
        pupPaw.addChildNode(leg(at: [0, 0, 0], fur))
        body.addChildNode(pupPaw)
        // 粉色项圈和一颗镀铬的小铃铛
        let collar = SCNTorus(ringRadius: 11.5 * u, pipeRadius: 2.2 * u)
        collar.materials = [pink]
        let ring = SCNNode(geometry: collar)
        ring.simdPosition = SIMD3<Float>(0, 34, 1) * Float(u)
        ring.eulerAngles.x = 0.25
        body.addChildNode(ring)
        body.addChildNode(RhythmArt.knob(SIMD3<Float>(0, 30, 12.5) * Float(u), radius: 3 * u, material: materials(plain: true).metal))

        // 脑袋：圆脑袋、鼓鼓的嘴巴、黑鼻头、小舌头、亮晶晶的黑眼睛、粉脸蛋、头顶一撮毛、两只耷拉的耳朵
        pupHead.simdPosition = SIMD3<Float>(0, 35, 2) * Float(u)
        body.addChildNode(pupHead)
        pupHead.addChildNode(blob([18, 16, 17], at: [0, 14, 2], fur))
        pupHead.addChildNode(blob([9, 7, 7.5], at: [0, 8, 15.5], fur))
        pupHead.addChildNode(blob([3.8, 2.9, 2.8], at: [0, 11, 22.5], dark))
        pupHead.addChildNode(blob([3, 2.2, 2.4], at: [0, 3.2, 19.5], pink))
        pupHead.addChildNode(blob([5, 5, 5], at: [0, 29, 3], fur))
        for s: Float in [-1, 1] {
            pupHead.addChildNode(blob([3.2, 3.6, 2.6], at: [s * 7, 17, 15.5], dark))
            pupHead.addChildNode(blob([1, 1, 1], at: [s * 7 - 1, 18.5, 18], white))
            pupHead.addChildNode(blob([3.4, 2.2, 1.2], at: [s * 11.5, 9.5, 13.5], pink))
            let ear = SCNNode()
            ear.simdPosition = SIMD3<Float>(s * 13, 24, 0) * Float(u)
            let flap = blob([5.5, 11, 3.5], at: [s * 3, -8, 0], fur)
            flap.eulerAngles.z = s * 0.35
            ear.addChildNode(flap)
            let inner = blob([3.2, 7.5, 1.5], at: [s * 3.2, -8, 2.6], pink)
            inner.eulerAngles.z = s * 0.35
            ear.addChildNode(inner)
            pupHead.addChildNode(ear)
            pupEars.append(ear)
        }
        // 尾巴从屁股后面翘起来
        pupTail.simdPosition = SIMD3<Float>(0, 12, -19) * Float(u)
        let tail = SCNCapsule(capRadius: 3.5 * u, height: 18 * u)
        tail.materials = [fur]
        let stick = SCNNode(geometry: tail)
        stick.simdPosition = SIMD3<Float>(0, 7, -3) * Float(u)
        stick.eulerAngles.x = -0.5
        pupTail.addChildNode(stick)
        body.addChildNode(pupTail)
        scene.rootNode.addChildNode(pupNode)
    }

    func furMaterial(_ color: UIColor, shine: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor(white: shine > 20 ? 0.9 : 0.25, alpha: 1)
        m.shininess = shine
        return m
    }

    /// 一个椭球：三个方向的半径（屏幕点），中心在 at（小动物自己的坐标，屏幕点，y 朝上、z 朝外）
    func blob(_ r: SIMD3<Float>, at c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: Self.unit)
        sphere.segmentCount = 20
        sphere.materials = [m]
        let node = SCNNode(geometry: sphere)
        node.simdPosition = c * Float(Self.unit)
        node.simdScale = r
        return node
    }

    /// 一条前腿：从肩膀 at 往下，底下一只圆圆的爪子
    func leg(at c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.simdPosition = c * Float(Self.unit)
        let capsule = SCNCapsule(capRadius: 4.5 * Self.unit, height: 17 * Self.unit)
        capsule.materials = [m]
        let shin = SCNNode(geometry: capsule)
        shin.simdPosition = SIMD3<Float>(0, -7, 1) * Float(Self.unit)
        node.addChildNode(shin)
        node.addChildNode(blob([5.5, 4.5, 6.5], at: [0, -14, 3], m))
        return node
    }

    /// 小狗、小猫的家底下的亚克力搁板（主题的 shelf，没有就用卡片的第一种颜色），从 a 到 b、顶面在 y，两头各一个金属托架斜撑着插进墙里；
    /// 墙上一块影子，中心在 shade.y、高 shade.h
    @MainActor func buildShelf(_ node: SCNNode, from a: CGFloat, to b: CGFloat, y top: CGFloat, shade s: (y: CGFloat, h: CGFloat),
                               depth: CGFloat = RhythmStage.Room.depth) {
        let u = Self.unit
        // 后沿离墙 12，往前伸 depth
        let thick: CGFloat = 7, z = RhythmStage.trackZ - 35 + depth / 2
        let box = SCNBox(width: (b - a) * u, height: thick * u, length: depth * u, chamferRadius: 1.6 * u)
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = theme.shelf ?? theme.cards[0]
        m.specular.contents = UIColor.white
        m.shininess = 70
        m.transparency = min(1, theme.cardClear + 0.05)
        let fixed = SCNNode()
        let themed = lookShelf(m, from: a, to: b, y: top, thick: thick, depth: depth, z: z, fixed: fixed)
        box.materials = [m]
        let board = SCNNode(geometry: box)
        board.simdPosition = v(Point3(x: (a + b) / 2, y: top + thick / 2, z: z))
        board.renderingOrder = Self.cardOrder
        let mats = materials()
        for x in [a + 14, b - 14] where !themed {
            let y = top + thick + 1.5
            let front = v(Point3(x: x, y: y, z: z + depth / 2 - 8)), back = v(Point3(x: x, y: y, z: z - depth / 2))
            let foot = v(Point3(x: x, y: y + 26, z: 0)), wall = v(Point3(x: x, y: y, z: 0))
            for (s, e) in [(front, back), (back, wall), (front, foot)] {
                fixed.addChildNode(RhythmArt.rod(s, e, radius: 1.6 * u, material: mats.metal))
            }
            fixed.addChildNode(RhythmArt.mount(foot, radius: 5 * u, material: mats.metal))
            fixed.addChildNode(RhythmArt.mount(wall, radius: 4 * u, material: mats.metal))
        }
        let shade = shadowNode(at: Point3(x: (a + b) / 2, y: s.y - 24, z: 0), w: b - a + 40, h: s.h, material: mats.shade)
        shade.renderingOrder = Self.shadowOrder
        node.addChildNode(fixed.flattenedClone())
        node.addChildNode(board)
        node.addChildNode(shade)
        scene.rootNode.addChildNode(node)
    }

    /// 前奏时小狗跟着球动；唱起来以后镜头早移走了，整个藏起来
    func updatePup(_ t: Double, ball b: RhythmStage.Ball) {
        let gone = t > (stage.tiles.first?.time ?? 0) + 6
        if pupNode.isHidden != gone {
            pupNode.isHidden = gone
            pupShelf.isHidden = gone
        }
        guard !gone else { return }
        let dir = Float(stage.pupDir), since = t - stage.throwAt
        let u = (t - stage.throwAt) / RhythmStage.dribble, q = Float(u - floor(u))
        let wag = Float(sin(2 * .pi * t * (since > 0 ? 5 : 3.2)))
        pupTail.simdOrientation = simd_quatf(angle: 0.7 * wag, axis: [0, 1, 0])
        var paw: Float, pitch: Float, hop: Float = 0
        if since < 0 {
            // 球往上走时爪子慢慢抬起来，球落地那一下往下拍；脑袋跟着球抬起、低下
            paw = q < 0.3 ? 0 : q < 0.85 ? (q - 0.3) / 0.55 : 1 - (q - 0.85) / 0.15
            pitch = -0.08 - 0.42 * Float(b.lift / RhythmStage.ballistic(RhythmStage.dribble))
            hop = 1.5 * Float(sin(2 * .pi * Double(q)))
        } else {
            // 一爪子把球拍出去，蹦一下，再低头看着球往下掉
            let s = Float(since)
            paw = s < 0.35 ? 1.6 * sin(.pi * s / 0.35) : 0
            pitch = min(s / 0.5, 1) * 0.35
            if s > 0.1, s < 0.6 {
                hop = 10 * sin(.pi * (s - 0.1) / 0.5)
            }
        }
        pupPaw.simdOrientation = simd_quatf(angle: -0.25 - 1.1 * paw, axis: [1, 0, 0])
        let roll = 0.14 * Float(sin(2.1 * t))
        pupHead.simdOrientation = simd_quatf(angle: dir * 0.3, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        let flop = 0.18 * Float(sin(2 * .pi * Double(q) + 1))
        for (k, ear) in pupEars.enumerated() { ear.eulerAngles.z = (k == 0 ? -1 : 1) * flop }
        pupNode.simdPosition.y = Float(-(stage.pup.y - CGFloat(hop)) * Self.unit)
    }
}
