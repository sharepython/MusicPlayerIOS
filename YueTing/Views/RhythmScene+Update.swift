import SceneKit
import UIKit

/// 小球、灯光、镜头，以及每一帧随播放时间的更新
extension RhythmScene {
    /// 玻璃弹珠（颜色按主题，原来是粉色）：越往边上颜色越深、越不透明，左上一个高光点，右下透进来一块亮斑（光折射进去聚在背光那面）；
    /// 里面两条白色的花芯和几个小气泡画在贴图上，跟着球一起转，滚起来看得出来。不画影子
    func buildBall() {
        let sphere = SCNSphere(radius: RhythmStage.ballRadius * Self.unit)
        sphere.segmentCount = 40
        func vec(_ c: UIColor) -> String {
            let x = c.components
            return "float3(\(x.r), \(x.g), \(x.b))"
        }
        let core = vec(theme.ball.mixed(.white, 0.8)), shine = vec(theme.ball.mixed(.white, 0.55))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = RhythmArt.marble
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            float3 n = _surface.normal;
            float e = 1.0 - saturate(dot(n, _surface.view));
            float key = saturate(dot(n, normalize(float3(-0.45, 0.55, 0.7))));
            float spot = pow(key, 70.0);
            float glow = pow(saturate(dot(n, normalize(float3(0.4, -0.55, 0.73)))), 4.0);
            float core = _surface.diffuse.a * (1.0 - 0.6 * e);
            float3 pink = \(vec(theme.ball));
            float3 c = mix(pink * (0.62 + 0.5 * glow), \(core), core * 0.8);
            c = mix(c, pink * float3(0.72, 0.5, 0.62), smoothstep(0.55, 1.0, e) * 0.75);
            c += float3(1.0) * (spot + 0.18 * pow(key, 8.0)) + \(shine) * 0.3 * glow;
            float a = saturate(0.4 + 0.5 * pow(e, 2.0) + 0.4 * core + spot + 0.25 * glow);
            _output.color = float4(min(c, float3(1.0)) * a, a);
            """]
        // 别的主题换成自己的小球（RhythmScene+Ball）
        sphere.materials = [ballMaterial(marble: m)]
        ball.geometry = sphere
        ball.renderingOrder = Self.ballOrder
        dressBall()
        scene.rootNode.addChildNode(ball)
        for _ in 0..<4 {
            let torus = SCNTorus(ringRadius: 0.16, pipeRadius: 0.006)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = theme.ring
            torus.materials = [m]
            let ring = SCNNode(geometry: torus)
            ring.opacity = 0
            scene.rootNode.addChildNode(ring)
            rings.append(ring)
        }
    }

    func fade(from a: Float, to b: Float) -> SCNParticlePropertyController {
        let anim = CABasicAnimation()
        anim.fromValue = a
        anim.toValue = b
        return SCNParticlePropertyController(animation: anim)
    }

    /// 一盏从左前上方照过来的平行光（不投影）加一盏环境光。墙和字、玻璃球不受灯光影响。
    /// 主题的一组照场景；原来的一组只照小狗、小猫和不跟主题走的字
    func buildLights() {
        let groups: [(Int, (UIColor, CGFloat), (UIColor, CGFloat))] = [
            (Self.sceneLight, theme.light, theme.ambient),
            (Self.keepLight, (.rgb(1, 0.97, 0.94), 850), (.rgb(0.85, 0.87, 0.95), 600)),
        ]
        for (mask, key, fill) in groups {
            let light = SCNLight()
            light.type = .directional
            light.color = key.0
            light.intensity = key.1
            light.categoryBitMask = mask
            let sun = SCNNode()
            sun.light = light
            sun.simdLook(at: [0.35, -0.7, -1], up: [0, 1, 0], localFront: [0, 0, -1])
            scene.rootNode.addChildNode(sun)
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = fill.0
            ambient.intensity = fill.1
            ambient.categoryBitMask = mask
            let n = SCNNode()
            n.light = ambient
            scene.rootNode.addChildNode(n)
        }
    }

    /// 镜头一直正对着墙，没有后期效果。投影在 setAspect 里按画面比例算
    func buildCamera() {
        let c = SCNCamera()
        c.zNear = 0.1
        c.zFar = 40
        cameraNode.camera = c
        scene.rootNode.addChildNode(cameraNode)
    }

    /// 视线落在画面从上往下 1/3 的地方，透视的角度由它定
    static let eyeLine: CGFloat = 1.0 / 3
    /// 小球那一排落在画面从上往下多少的地方。律动铺满全屏，放在 1/3 显得太靠上；
    /// 透视角度不变，把镜头整体抬高，让这一排出现在下面
    static let ballLine: CGFloat = 0.55

    /// 横向刚好装下琴键那一层再留点边；投影往下偏，让视线落在 eyeLine 处。
    /// 再按画面比例算出镜头要抬高多少，小球那一排才落在 ballLine 处
    func setAspect(_ a: CGFloat) {
        guard a > 0, abs(a - aspect) > 0.001, let c = cameraNode.camera else { return }
        aspect = a
        let depth = RhythmStage.eyeDistance - RhythmStage.keyGap - RhythmStage.keyLength / 2
        let sx = Float(depth / (stage.width / 2 + 16))
        var p = c.projectionTransform
        p.m11 = sx
        p.m22 = sx / Float(a)
        p.m31 = 0
        p.m32 = Float(2 * Self.eyeLine - 1)
        c.projectionTransform = p
        // 琴键这一层上的点每往下 1 点，在画面上往下移 1 / ((宽 + 32) × 高宽比) 个画面高度
        cameraLift = (Self.ballLine - Self.eyeLine) * (stage.width + 32) * a
        titleNode.simdPosition.y = Float(cameraLift * Self.unit)
    }

    /// 没踩到是卡片本来的颜色，踩中后亮一下，字也亮起来
    func style(_ i: Int, lit: Bool) {
        let m = keyMaterials[i]
        m.emission.contents = keyColors[i]
        m.emission.intensity = lit ? theme.cardLit : theme.cardIdle
        labelMaterials[i]?.diffuse.intensity = lit ? 1.15 : 0.85
    }

    /// 某一时刻的画面：亮起到第几张卡片、刚踩中的闪一下并往下压、小球、小狗、镜头
    func update(_ t: Double) {
        guard !stage.tiles.isEmpty else { return }
        let k = stage.lastHit(t)
        let count = (k ?? -1) + 1
        if count != litCount {
            for i in min(count, litCount)..<max(count, litCount) {
                style(i, lit: i < count)
                // 拖进度条往回拖时，还在弹的卡片放回原样
                if i >= count {
                    react(i, since: 1)
                }
            }
            // 跳到的是下一张才溅光点，拖进度条时不溅
            if count == litCount + 1, let k, t - stage.tiles[k].time < 0.3 {
                burst(k)
            }
            litCount = count
        }
        if let k {
            for i in max(0, k - 8)...k {
                let since = t - stage.tiles[i].time
                keyMaterials[i].emission.intensity = theme.cardLit + 0.5 * max(0, 1 - since / 0.4)
                react(i, since: since)
            }
        }
        let b = stage.ball(at: t)
        let c = Point3(x: b.ground.x, y: b.ground.y - b.lift - RhythmStage.ballRadius, z: b.ground.z)
        ball.simdPosition = v(c)
        roll(to: c, grounded: b.lift == 0)
        let pose = stage.camera(at: t)
        cameraNode.simdPosition = v(Point3(x: pose.eye.x, y: pose.eye.y - cameraLift, z: pose.eye.z))
        let view = showRows(near: pose.eye.y - cameraLift)
        updatePup(t, ball: b)
        updateKitty(t, ball: b, view: view)
    }

    /// 小球滚动：在架子上按走过的路长转（往右走顺时针转），飞在空中照着左右走的快慢接着转；
    /// 拖进度条一下跳很远时不转
    private func roll(to c: Point3, grounded: Bool) {
        if let last = lastBall {
            let dx = c.x - last.x, d = grounded && abs(dx) > 0.2 ? copysign(hypot(dx, c.y - last.y), dx) : dx
            if abs(d) < 120 {
                spin -= Float(d / RhythmStage.ballRadius)
            }
        }
        lastBall = c
        ball.simdOrientation = simd_quatf(angle: spin, axis: [0, 0, 1]) * Self.ballTilt
    }

    /// 花芯斜着摆，正面看得见
    private static let ballTilt = simd_quatf(angle: 0.7, axis: [1, 0, 0]) * simd_quatf(angle: 0.4, axis: [0, 1, 0])

    /// 只画镜头里的组：画面上沿以上留一点、下沿以下多留一些，其余藏起来。返回这段要画的范围
    @discardableResult private func showRows(near y: CGFloat) -> ClosedRange<CGFloat> {
        let h = (stage.width + 32) * max(aspect, 1.5)
        let view = (y - h * Self.eyeLine - 150)...(y + h * (1 - Self.eyeLine) + 250)
        for i in rowNodes.indices {
            let on = stage.rows[i].span.overlaps(view)
            if on != rowShown[i] {
                rowNodes[i].isHidden = !on
                rowShown[i] = on
            }
        }
        return view
    }
}
