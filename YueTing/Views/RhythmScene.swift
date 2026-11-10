import SceneKit
import UIKit

/// 律动模式的 3D 场景：墙、撑在墙上的亚克力卡片和铁丝支架、组和组之间的架子、字、玻璃球和镜头。
/// 摆放和运动都按 RhythmStage 算（单位是屏幕点），这里换成 SceneKit 的坐标：100 点 = 1，y 朝上。
/// 为了省电不用实时阴影、PBR 和后期效果：墙上的面板缝画在贴图里，影子是相乘混合贴在墙上的软斑，
/// 卡片和架子只用一盏平行光加环境光的便宜光照，金属用一张环境贴图做出镀铬的反光。
/// 墙、卡片、支架、灯光、两个小家这些的样子按 RhythmTheme 来，小狗、小猫和门上、台子上的字不跟主题走。
/// 在主线程建好；之后每帧的 update 在 SceneKit 的渲染线程里调用（由 RhythmDriver 加锁），画面和渲染同步
final class RhythmScene: @unchecked Sendable {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let stage: RhythmStage
    let theme: RhythmTheme
    var keys: [SCNNode] = []
    var keyMaterials: [SCNMaterial] = []
    /// 每张卡片的颜色，亮起时按它发光
    var keyColors: [UIColor] = []
    /// 卡片不压下去时的位置，踩中时顺着卡片自己的朝向往下压
    var keyRest: [SIMD3<Float>] = []
    /// 卡片本来的朝向，踩中时有的主题会转一下、压扁一下，过后回到这里
    var keyBase: [simd_quatf] = []
    /// 每张卡片上的字，没有字时为 nil
    var labelMaterials: [SCNMaterial?] = []
    /// 每组一个节点（卡片、字、支架、影子、后面那段架子），镜头外的组藏起来不画
    var rowNodes: [SCNNode] = []
    var rowShown: [Bool] = []
    let ball = SCNNode()
    /// 小球滚了多少圈（绕 z 轴的角度）和上一帧的球心，按走过的路算转多少
    var spin: Float = 0
    var lastBall: Point3?
    /// 前奏时玩球的小狗：整只、头、尾巴、拍球的那只前爪、两只耳朵
    let pupNode = SCNNode(), pupHead = SCNNode(), pupTail = SCNNode(), pupPaw = SCNNode()
    /// 小狗的家（连同底下的搁板和托架）
    let pupShelf = SCNNode()
    var pupEars: [SCNNode] = []
    /// 唱完后接球的小猫：整只、身子、头、它的家，两只前爪、两只耳朵、尾巴、两只眼睛（眨眼时压扁）
    let kittyNode = SCNNode(), kittyBody = SCNNode(), kittyHead = SCNNode(), kittyShelf = SCNNode()
    var kittyPaws: [SCNNode] = [], kittyEars: [SCNNode] = [], kittyTail: [SCNNode] = [], kittyEyes: [SCNNode] = []
    /// 已经亮起的卡片数
    var litCount = 0
    /// 踩中时扩散的光环，建好后一直挂在场景里轮流用：渲染线程会同时遍历子节点，逐帧增删节点会崩
    var rings: [SCNNode] = []
    var nextRing = 0
    /// 画面的高宽比，镜头的投影按它算
    var aspect: CGFloat = 0
    /// 镜头比小球那一排高出多少（屏幕点），setAspect 里算
    var cameraLift: CGFloat = 0
    /// 墙顶上的歌名和歌手
    let titleNode = SCNNode()

    static let unit: CGFloat = 0.01
    /// 绘制顺序：墙最先，再是贴在墙上的影子、不透明的支架和架子、半透明的卡片、字、玻璃球，最后是磨砂管
    static let wallOrder = -10, shadowOrder = 1, cardOrder = 3, labelOrder = 6, ballOrder = 8, tubeOrder = 10, driftOrder = 12
    /// 灯光分两组：场景跟主题走的灯，和照小狗、小猫、门上台子上的字的原来那组灯
    static let sceneLight = 1, keepLight = 2

    @MainActor init(stage: RhythmStage, theme: RhythmTheme) {
        self.stage = stage
        self.theme = theme
        scene.background.contents = UIColor.clear
        buildWall()
        buildRows()
        buildTitle()
        buildPup()
        buildKitty()
        buildBall()
        buildLights()
        buildCamera()
        buildDrift()
        split(scene.rootNode, keep: false)
    }

    /// 小狗、小猫（连同它们身上的东西）和已经标成原样的字只让原来那组灯照，别的都让主题的灯照
    private func split(_ node: SCNNode, keep: Bool) {
        let keep = keep || node === pupNode || node === kittyNode || node.categoryBitMask == Self.keepLight
        if node.light == nil {
            node.categoryBitMask = keep ? Self.keepLight : Self.sceneLight
        }
        for child in node.childNodes { split(child, keep: keep) }
    }

    /// 屏幕点坐标转场景坐标
    func v(_ p: Point3) -> SIMD3<Float> {
        SIMD3(Float((p.x - stage.width / 2) * Self.unit), Float(-p.y * Self.unit), Float(p.z * Self.unit))
    }

    /// 一整面墙从歌名上面铺到最后一组下面，左右比镜头能移到的地方还宽，拼板贴图重复铺，不受灯光影响
    @MainActor private func buildWall() {
        let top: CGFloat = 1400
        let bottom = stage.rows.last?.span.upperBound ?? 0
        let w = 2 * (stage.width + stage.spread) * Self.unit + 4, h = (bottom + 1600 + top) * Self.unit
        let plane = SCNPlane(width: w, height: h)
        let tile = stage.width * 2.2 * Self.unit
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = RhythmArt.wall(theme)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(w / tile), Float(h / tile), 1)
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, Float(top * Self.unit - h / 2), 0)
        node.renderingOrder = Self.wallOrder
        scene.rootNode.addChildNode(node)
    }

    /// 金属（铁丝、轨道、支架、墙上的底座，按主题是镀铬、黄铜、紫铜这些）、墙上的影子
    struct Materials {
        let metal = SCNMaterial(), shade = SCNMaterial(), strip = SCNMaterial()
    }

    /// plain 是原来的镀铬，不跟主题走（小狗的铃铛）
    func materials(plain: Bool = false) -> Materials {
        let s = Materials()
        s.metal.lightingModel = .blinn
        s.metal.diffuse.contents = UIColor(white: plain ? 0.3 : theme.metalBase, alpha: 1)
        s.metal.specular.contents = UIColor.white
        s.metal.shininess = 120
        s.metal.reflective.contents = RhythmArt.chrome
        s.metal.reflective.intensity = 0.95
        s.metal.multiply.contents = plain ? UIColor.white : theme.metal
        for (m, image) in [(s.shade, RhythmArt.shadow), (s.strip, RhythmArt.strip)] {
            m.lightingModel = .constant
            m.diffuse.contents = image
            m.blendMode = .multiply
            m.writesToDepthBuffer = false
        }
        return s
    }

    /// 墙上的一块软影子，往右下偏（光从左上来，东西离墙有一段，影子偏得开一些）
    func shadowNode(at p: Point3, w: CGFloat, h: CGFloat, material: SCNMaterial) -> SCNNode {
        let plane = SCNPlane(width: w * Self.unit, height: h * Self.unit)
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdPosition = v(Point3(x: p.x + 14, y: p.y + 24, z: 0.5))
        return node
    }
}
