import SceneKit
import UIKit

/// 每组卡片和后面那段架子
extension RhythmScene {
    /// 每组一个节点。每个字一张亚克力卡片（颜色按主题，几种颜色时按组轮流）（带圆角的扁方块），左右两根金属铁丝从后端勾住卡片、托在底下，
    /// 再斜着插进墙里，墙上各一块金属底座，卡片悬在离墙一段的地方；卡片后端上方浮着字，墙上一块影子。组后面接一段架子
    @MainActor func buildRows() {
        let u = Self.unit, L = RhythmStage.keyLength, H = RhythmStage.keyThick
        let mats = materials()
        for r in stage.rows.indices {
            let row = SCNNode(), fixed = SCNNode(), shade = SCNNode()
            let color = theme.cards[r % theme.cards.count]
            for i in stage.rows[r].tiles {
                // 先绕自己的前后中线左右斜，再左右转开；绕顶面的中线转，小球的落点不动
                let q = simd_quatf(angle: Float(stage.yaw(i)), axis: [0, 1, 0])
                    * simd_quatf(angle: -Float(stage.tilt(i)), axis: [0, 0, 1])
                func below(_ along: CGFloat, _ down: CGFloat) -> SIMD3<Float> {
                    v(stage.point(i, along: along)) + q.act([0, -Float(down * u), 0])
                }

                // 卡片上一点：离后端 along、往右 across、从顶面往下 down，跟着卡片一起斜
                func at(_ along: CGFloat, _ across: CGFloat, _ down: CGFloat) -> SIMD3<Float> {
                    v(stage.point(i, along: along)) + q.act([Float(across * u), -Float(down * u), 0])
                }
                // 跳板的样子和托着它的东西按主题来（RhythmScene+Pads）
                let (key, m) = makePad(color, at: at, fixed: fixed, mats: mats)
                key.simdOrientation = q
                key.simdPosition = below(L / 2, H / 2)
                key.renderingOrder = Self.cardOrder
                key.enumerateHierarchy { n, _ in n.renderingOrder = Self.cardOrder }
                row.addChildNode(key)
                keys.append(key)
                keyBase.append(q)
                keyMaterials.append(m)
                keyColors.append(color)
                keyRest.append(key.simdPosition)
                let t = stage.tiles[i]
                shade.addChildNode(shadowNode(at: Point3(x: t.x, y: t.y + 4, z: 0), w: 62, h: 40, material: mats.shade))

                labelMaterials.append(t.text.isEmpty ? nil : addLabel(i, to: row))
                style(i, lit: false)
            }
            for k in stage.tracks[r] {
                addTrack(k, row: row, fixed: fixed, shade: shade, mats: mats)
            }
            // 一组的支架、影子各合成一个节点，少很多次绘制
            row.addChildNode(fixed.flattenedClone())
            let shadows = shade.flattenedClone()
            shadows.renderingOrder = Self.shadowOrder
            row.addChildNode(shadows)
            row.isHidden = true
            scene.rootNode.addChildNode(row)
            rowNodes.append(row)
            rowShown.append(false)
        }
    }

    /// 字浮在卡片后端上方、跟着卡片转向，白字乘上这个字的颜色；外文单词太长时缩小
    @MainActor private func addLabel(_ i: Int, to row: SCNNode) -> SCNMaterial {
        let image = RhythmArt.label(stage.tiles[i].text)
        let pt = 24.0 / 64 * Self.unit
        var w = image.size.width * pt, h = image.size.height * pt
        let limit = 60 * Self.unit
        if w > limit {
            h *= limit / w
            w = limit
        }
        let plane = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        // 奶油拼板和参考视频一样是偏灰的粉彩色，不要太艳；深色的墙上字要亮一些
        m.multiply.contents = UIColor(hue: stage.tiles[i].hue, saturation: theme.labelSat, brightness: theme.labelBright, alpha: 1)
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.simdPosition = v(stage.point(i, along: 4, down: -10 - h / 2 / Self.unit))
        node.eulerAngles = SCNVector3(0, Float(stage.yaw(i)), 0)
        node.renderingOrder = Self.labelOrder
        row.addChildNode(node)
        return m
    }
}
