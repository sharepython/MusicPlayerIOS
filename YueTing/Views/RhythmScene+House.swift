import CoreText
import SceneKit
import UIKit

/// 小狗、小猫各自的小家：像娃娃屋一样前面敞开，镜头看得见里面，两层楼。搁板上铺一层木地板，后墙贴着波点 / 条纹墙纸，
/// 尖屋顶带烟囱，屋檐下挂着「小狗的家」「小猫的家」的小木牌。
/// 一楼是小动物玩球的地方：门口那边（Room.open）没有墙，只有一根门柱，球从那边进出；里面那头后墙上一扇关着的门，
/// 门前一块脚垫，墙上挂一幅画，楼板底下吊一盏小灯，门口那半边是带窗帘的窗户，小动物趴在圆地毯上；最里面一架梯子从楼板上的洞口爬上二楼。
/// 二楼：一张铺着被子、带枕头的床，床头柜上一盏台灯，床上面一扇圆窗，门口那边是墙。
/// 两家摆的东西不一样：小狗家一楼一张沙发、一个饭盆一个水盆，二楼一个衣柜、一只足球；
/// 小猫家一楼一架猫爬架、一个毛线球，二楼一个书架、一盆花，床头是圆的。两家的圆窗外都是白天的太阳和云。
/// 小猫家从墙往前深一倍（Room.kittyDepth），前面多出来的地方一楼摆猫隧道、猫窝、饭盆水盆、玩具老鼠、铃铛球和一盆绿植，
/// 二楼摆懒人沙发、小茶几、玩具箱，里面那面墙前一张梳妆台，墙上一串彩旗。
/// 换主题时房子的颜色按 RhythmTheme.house 调（雪国屋顶积雪、窗外换成夜空这些），门上的 CW / CC 和门外台子上的字不变
extension RhythmScene {
    enum Pet {
        case pup, kitty
    }

    struct HouseStyle {
        let paper, pattern, wall, roof, ridge, rug, rugEdge, chimney, door, sofa, quilt: UIColor
        /// 门板上和门外台子上的字的颜色，比门深一些
        let ink: UIColor
        let sign: String, picture: String, pet: Pet
        /// 小猫家的墙纸是竖条纹，小狗家是波点
        var stripes: Bool { pet == .kitty }
    }

    private static func style(_ pet: Pet) -> HouseStyle {
        switch pet {
        case .pup:
            // 墙纸、墙要比白色的小狗深一截，小狗才显得出来
            return HouseStyle(paper: UIColor(red: 0.96, green: 0.78, blue: 0.58, alpha: 1),
                              pattern: UIColor(red: 1, green: 0.9, blue: 0.74, alpha: 1),
                              wall: UIColor(red: 0.93, green: 0.72, blue: 0.52, alpha: 1),
                              roof: UIColor(red: 0.93, green: 0.48, blue: 0.4, alpha: 1),
                              ridge: UIColor(red: 0.8, green: 0.36, blue: 0.3, alpha: 1),
                              rug: UIColor(red: 0.62, green: 0.8, blue: 0.97, alpha: 1),
                              rugEdge: UIColor(red: 0.85, green: 0.93, blue: 1, alpha: 1),
                              chimney: UIColor(red: 0.78, green: 0.5, blue: 0.4, alpha: 1),
                              door: UIColor(red: 0.45, green: 0.66, blue: 0.9, alpha: 1),
                              sofa: UIColor(red: 0.98, green: 0.72, blue: 0.4, alpha: 1),
                              quilt: UIColor(red: 0.6, green: 0.84, blue: 0.62, alpha: 1),
                              ink: UIColor(red: 0.24, green: 0.44, blue: 0.72, alpha: 1),
                              sign: "小狗的家", picture: "🦴", pet: .pup)
        case .kitty:
            return HouseStyle(paper: UIColor(red: 0.74, green: 0.7, blue: 0.93, alpha: 1),
                              pattern: UIColor(red: 0.84, green: 0.8, blue: 0.98, alpha: 1),
                              wall: UIColor(red: 0.68, green: 0.63, blue: 0.9, alpha: 1),
                              roof: UIColor(red: 0.72, green: 0.6, blue: 0.93, alpha: 1),
                              ridge: UIColor(red: 0.6, green: 0.48, blue: 0.84, alpha: 1),
                              rug: UIColor(red: 0.66, green: 0.9, blue: 0.8, alpha: 1),
                              rugEdge: UIColor(red: 0.88, green: 0.98, blue: 0.93, alpha: 1),
                              chimney: UIColor(white: 0.97, alpha: 1),
                              door: UIColor(red: 0.5, green: 0.8, blue: 0.68, alpha: 1),
                              sofa: UIColor(red: 0.74, green: 0.64, blue: 0.95, alpha: 1),
                              quilt: UIColor(red: 1, green: 0.7, blue: 0.8, alpha: 1),
                              ink: UIColor(red: 0.3, green: 0.6, blue: 0.48, alpha: 1),
                              sign: "小猫的家", picture: "🐟", pet: .kitty)
        }
    }

    /// 往房子里摆东西：坐标是屏幕点，x 从房子正中往右，y 从一楼地板往上，z 离墙多远；at(c) 是离里面那堵墙 c 远的 x
    @MainActor struct Kit {
        let scene: RhythmScene, house: SCNNode, W: Float, open: Float
        var u: Float { Float(RhythmScene.unit) }
        func at(_ c: Float) -> Float {
            -open * (W / 2 - c)
        }

        @discardableResult func add(_ n: SCNNode, _ c: SIMD3<Float>) -> SCNNode {
            n.simdPosition = c * u
            house.addChildNode(n)
            return n
        }

        @discardableResult func box(_ size: SIMD3<Float>, _ c: SIMD3<Float>, _ m: SCNMaterial, _ chamfer: Float = 0.8) -> SCNNode {
            let b = SCNBox(width: CGFloat(size.x * u), height: CGFloat(size.y * u), length: CGFloat(size.z * u),
                           chamferRadius: CGFloat(chamfer * u))
            b.materials = [m]
            return add(SCNNode(geometry: b), c)
        }

        @discardableResult func blob(_ r: SIMD3<Float>, _ c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
            let n = scene.blob(r, at: c, m)
            house.addChildNode(n)
            return n
        }

        /// 一个凸起的字，正中放在 c，字高 h 点
        @discardableResult func letter(_ s: Character, height h: CGFloat, _ c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode? {
            let base = UIFont.systemFont(ofSize: 100, weight: .heavy)
            let font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 100) as CTFont
            var chars = Array(String(s).utf16), glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count),
                  let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
            let path = UIBezierPath(cgPath: outline), b = path.bounds, k = h / b.height
            path.apply(CGAffineTransform(translationX: -b.midX, y: -b.midY).concatenating(CGAffineTransform(scaleX: k, y: k)))
            path.flatness = 0.2
            let shape = SCNShape(path: path, extrusionDepth: 1)
            shape.materials = [m]
            let node = add(SCNNode(geometry: shape), c)
            node.simdScale = [u, u, u]
            return node
        }

        /// 平躺在台面上的几行凸起的字，逆时针转 90 度：顺着台子从外往里读（屏幕上从下往上），字头朝左，
        /// 第一行在左边，每行开头对齐在外面那头。整块缩到顺着读的方向不超过 fit.width、横着不超过 fit.height，正中放在 c
        /// gap 给了时两行基线隔开 gap，字号跟着定（排不下再缩）；没给时整块字缩放到正好塞进 fit
        @discardableResult func label(_ lines: [String], fit: CGSize, gap: CGFloat? = nil, _ c: SIMD3<Float>, _ m: SCNMaterial) -> SCNNode {
            let base = UIFont.systemFont(ofSize: 100, weight: .heavy)
            let font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 100)
            let outline = CGMutablePath()
            for (row, s) in lines.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
                for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                    let n = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: n), at = [CGPoint](repeating: .zero, count: n)
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    CTRunGetPositions(run, CFRange(), &at)
                    for i in 0..<n {
                        var t = CGAffineTransform(translationX: at[i].x, y: at[i].y - CGFloat(row) * 118)
                        if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) {
                            outline.addPath(g)
                        }
                    }
                }
            }
            let path = UIBezierPath(cgPath: outline), b = path.bounds
            let k = gap.map { min($0 / 118, fit.width / b.width) } ?? min(fit.width / b.width, fit.height / b.height)
            // 按行距排时以两行基线的正中对准 c，两行正好落在 1/3、2/3 处
            let midY = gap == nil ? b.midY : -CGFloat(lines.count - 1) * 118 / 2 + 36
            path.apply(CGAffineTransform(translationX: -b.midX, y: -midY).concatenating(CGAffineTransform(scaleX: k, y: k)))
            path.flatness = 0.2
            let shape = SCNShape(path: path, extrusionDepth: 0.6)
            shape.materials = [m]
            let node = add(SCNNode(geometry: shape), c)
            node.simdScale = [u, u, u]
            // 字的前进方向朝里（-z），字头朝左（-x），凸起朝上
            node.simdOrientation = simd_quatf(simd_float3x3(columns: ([0, 0, -1], [-1, 0, 0], [0, 1, 0])))
            return node
        }

        func rod(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r: CGFloat, _ m: SCNMaterial) {
            house.addChildNode(RhythmArt.rod(a * u, b * u, radius: r * RhythmScene.unit, material: m))
        }

        /// 按主题调过色的材质；keep 是原来的颜色（门上、台子上的字）
        func material(_ c: UIColor, _ shine: CGFloat) -> SCNMaterial {
            scene.furMaterial(scene.theme.house(c), shine: shine)
        }

        func keep(_ c: UIColor, _ shine: CGFloat) -> SCNMaterial {
            scene.furMaterial(c, shine: shine)
        }

        /// 自己发光的东西（窗玻璃、镜子）按主题混一点颜色；lamp 是亮着的灯，不调
        func glow(_ c: UIColor) -> SCNMaterial {
            lamp(scene.theme.house.glow(c))
        }

        func lamp(_ c: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = c
            return m
        }

        /// 不跟主题走的字：原来的颜色，只让原来那组灯照
        func protect(_ n: SCNNode?) {
            n?.categoryBitMask = RhythmScene.keepLight
        }
    }

    /// 墙、楼板、屋顶的尺寸（屏幕点）
    struct Frame {
        let W: Float, H: Float, U: Float, T: Float, rise: Float
        let back: Float = 12
        var front: Float = 74
        var depth: Float { front - back }
        var zc: Float { (back + front) / 2 }
        /// 二楼地板顶面
        var up: Float { H + Float(RhythmStage.Room.slab) }
    }
}

extension RhythmScene {
    /// 在 node 里搭一个家：底下是搁板，pet 是小动物站的 x（地毯铺在它下面）
    @MainActor func buildHouse(_ r: RhythmStage.Room, _ pet: Pet, pet x: CGFloat, into node: SCNNode) {
        let s = lookStyle(Self.style(pet))
        let pointed = theme.look == .classic || theme.look == .ice
        let porchW = pet == .kitty ? RhythmStage.Room.kittyPorch : RhythmStage.Room.porch
        let porch = r.open * porchW, ends = [r.x.lowerBound, r.x.upperBound, (r.open > 0 ? r.x.upperBound : r.x.lowerBound) + porch]
        let deep = pet == .kitty ? RhythmStage.Room.kittyDepth : RhythmStage.Room.depth
        buildShelf(node, from: ends.min()!, to: ends.max()!, y: r.floor, shade: (r.floor - (r.floor - r.top) / 2 + 6, r.floor - r.top + 50),
                   depth: deep)
        let f = Frame(W: Float(r.width), H: Float(r.height), U: Float(r.upper), T: Float(r.walls), rise: Float(r.rise), front: 12 + Float(deep))
        let house = SCNNode()
        house.simdPosition = v(Point3(x: r.mid, y: r.floor, z: 0))
        node.addChildNode(house)
        let k = Kit(scene: self, house: house, W: f.W, open: Float(r.open))
        let W = f.W, H = f.H, T = f.T, back = f.back, front = f.front, depth = f.depth, zc = f.zc
        let open = k.open, closed = -open
        let wood = k.material(UIColor(red: 0.88, green: 0.7, blue: 0.52, alpha: 1), 20)
        let trim = k.material(UIColor(white: 0.98, alpha: 1), 20)
        let wall = k.material(s.wall, 4)
        // 雪国的屋顶积了雪，屋脊是深一点的雪
        let roof = k.material(theme.roof ?? s.roof, 30)

        // 一楼地板、整面后墙（墙纸）、山墙、靠里那边的侧墙、门口的门柱、门口那边二楼的侧墙、两层的踢脚线
        k.box([W, 1.4, depth], [0, 0.7, zc], wood, 0.3)
        k.box([W, T, 4], [0, T / 2, back + 2], wallpaper(s, w: W, h: T), 0)
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: -CGFloat(W / 2 * k.u), y: 0))
        tri.addLine(to: CGPoint(x: CGFloat(W / 2 * k.u), y: 0))
        tri.addLine(to: CGPoint(x: 0, y: CGFloat(f.rise * k.u)))
        tri.close()
        let gable = SCNShape(path: tri, extrusionDepth: CGFloat(4 * k.u))
        gable.materials = [wall]
        if pointed {
            k.add(SCNNode(geometry: gable), [0, T, back + 2])
        }
        k.box([5, T, depth], [closed * (W / 2 - 2.5), T / 2, zc], wall)
        k.box([5, H, 5], [open * (W / 2 - 2.5), H / 2, front - 2.5], trim)
        k.box([5, T - H, depth], [open * (W / 2 - 2.5), (T + H) / 2, zc], wall)
        k.box([W, 3, 2], [0, 1.5, back + 4.5], trim, 0.3)
        k.box([W, 3, 2], [0, f.up + 1.5, back + 4.5], trim, 0.3)

        // 楼板：最里面靠前留一个洞口给梯子，前沿一道白边
        let hole: Float = 30, slab = f.up - H, mid = H + slab / 2
        k.box([W - hole, slab, depth], [open * hole / 2, mid, zc], wood, 0.3)
        k.box([hole, slab, depth - 26], [k.at(hole / 2), mid, back + (depth - 26) / 2], wood, 0.3)
        k.box([W - hole, slab + 1, 2.4], [open * hole / 2, mid, front + 0.6], trim, 0.4)
        // 梯子：两根扶手稍微往后靠，伸出楼板一截好抓
        let rail = k.material(UIColor(red: 0.76, green: 0.55, blue: 0.38, alpha: 1), 20)
        let foot: Float = front - 8, head: Float = front - 18, ladderTop = f.up + 18
        for c: Float in [7, 23] { k.rod([k.at(c), 0, foot], [k.at(c), ladderTop, head], 1.4, rail) }
        for y in stride(from: Float(12), through: f.up + 6, by: 14) {
            let z = foot + (head - foot) * y / ladderTop
            k.rod([k.at(7), y, z], [k.at(23), y, z], 1, rail)
        }

        // 尖屋顶：左右两块斜板，前沿一道白边，屋尖一颗圆球，靠里那边一个烟囱；别的主题换成自己的屋顶（RhythmScene+Roofs）
        lookRoof(k, s, f, trim: trim)
        if pointed {
        let rise = f.rise, half = hypot(W / 2, rise), angle = atan2(rise, W / 2)
        for side: Float in [-1, 1] {
            let t = SIMD2<Float>(-side * W / 2, rise) / half, n = SIMD2<Float>(side * rise, W / 2) / half
            let c = SIMD2<Float>(side * W / 4, T + rise / 2) - t * 6 + n * 3
            k.box([half + 12, 6, depth + 14], [c.x, c.y, zc + 1], roof, 1.5).eulerAngles.z = -side * angle
            k.box([half + 12, 7, 2], [c.x, c.y, zc + depth / 2 + 9], trim, 0.8).eulerAngles.z = -side * angle
        }
        k.blob([4, 4, 4], [0, T + rise + 4, zc + depth / 2 + 9], k.material(theme.roof.map { $0.mixed(.rgb(0.55, 0.62, 0.75), 0.3) } ?? s.ridge, 30))
        let cx = closed * W * 0.27, cy = T + rise * (1 - 0.54) + 9
        let brick = k.material(s.chimney, 10)
        k.box([11, 22, 11], [cx, cy, back + 16], brick)
        k.box([14, 3, 14], [cx, cy + 12, back + 16], brick)

        // 牌子挂在屋檐下面正中
        let sign = k.box([50, 15, 1.6], [0, T + rise * 0.33, front + 6], signMaterial(s.sign), 0.6)
        sign.eulerAngles.x = -0.08
        let cord = k.material(UIColor(red: 0.6, green: 0.42, blue: 0.3, alpha: 1), 4)
        for side: Float in [-1, 1] {
            k.rod([side * 18, T + rise * 0.33 + 7, front + 6], [side * 10, T + rise * 0.62, front + 6], 0.5, cord)
        }
        }

        groundFloor(k, s, f, pet: Float(x - r.mid))
        // 门外伸出去的那截台子上写字：小狗家 Class Winner，小猫家 Challenge Certificate，各分两行、左边对齐。
        // 小猫家的台子深一倍、宽 1.5 倍，两行字隔开写在台子宽度的 1/3 和 2/3 处，离门柱远一点
        let porchX = k.open * (W / 2 + Float(porchW) / 2)
        if s.pet == .pup {
            k.protect(k.label(["Class", "Winner"], fit: CGSize(width: 52, height: 34), [porchX, 0.3, zc], k.keep(s.ink, 40)))
        } else {
            k.protect(k.label(["Challenge", "Certificate"], fit: CGSize(width: CGFloat(depth - 10), height: 60), gap: porchW / 3,
                              [porchX, 0.3, zc], k.keep(s.ink, 40)))
        }
        if s.pet == .kitty {
            kittyGround(k, s, f)
        }
        upstairs(k, s, f)
        if s.pet == .kitty {
            kittyUpstairs(k, s, f)
        }
    }
}
extension RhythmScene {
    /// 一楼：窗户在门口那半边（球在窗前玩），里面那头一扇关着的门、一张沙发或一架猫爬架，地毯铺在小动物底下，前面是饭盆或毛线球
    @MainActor private func groundFloor(_ k: Kit, _ s: HouseStyle, _ f: Frame, pet: Float) {
        let W = f.W, H = f.H, z = f.back + 4, open = k.open
        let trim = k.material(UIColor(white: 0.98, alpha: 1), 20)
        let wood = k.material(UIColor(red: 0.85, green: 0.65, blue: 0.45, alpha: 1), 20)

        // 窗户：天蓝色玻璃、十字窗棂、窗台、窗帘杆和两片窗帘
        let curtain = k.material(s.pet == .pup ? UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1) : UIColor(red: 1, green: 0.72, blue: 0.8, alpha: 1), 8)
        let wx = open * W * 0.24, wy = H * 0.6
        k.box([36, 30, 2], [wx, wy, z + 1], trim, 0.6)
        k.box([30, 24, 2.2], [wx, wy, z + 1.3], theme.glass.map(k.lamp) ?? k.glow(UIColor(red: 0.72, green: 0.88, blue: 1, alpha: 1)), 0)
        k.box([1.6, 24, 2.8], [wx, wy, z + 1.5], trim, 0.3)
        k.box([30, 1.6, 2.8], [wx, wy, z + 1.5], trim, 0.3)
        k.box([42, 2.5, 6], [wx, wy - 16, z + 3], trim, 0.6)
        k.rod([wx - 24, wy + 18, z + 4], [wx + 24, wy + 18, z + 4], 0.9, trim)
        for side: Float in [-1, 1] {
            k.blob([5, 17, 1.8], [wx + side * 19, wy + 1, z + 4.5], curtain).eulerAngles.z = side * 0.08
        }

        // 关着的门：白门框、两块凸起的门板、金色的圆把手，门上一颗小爱心，门前一块脚垫。
        // 两块门板上写字：小猫家上下各一个 C，小狗家上面 C 下面 W；爱心挪到两块门板中间
        let dx = k.at(50), dw: Float = 34, dh: Float = 70
        let door = k.material(s.door, 30), inset = k.material(Self.paler(s.door, 0.25), 30)
        k.box([dw + 7, dh + 4, 2], [dx, (dh + 4) / 2, z + 1], trim, 0.6)
        k.box([dw, dh, 2.6], [dx, dh / 2 + 0.5, z + 1.8], door, 0.8)
        k.box([dw - 10, 24, 3.4], [dx, dh * 0.7, z + 1.8], inset, 0.8)
        k.box([dw - 10, 22, 3.4], [dx, dh * 0.27, z + 1.8], inset, 0.8)
        let knob = k.material(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), 90)
        k.blob([2.4, 2.4, 2], [dx + open * (dw / 2 - 5), dh * 0.48, z + 4.4], knob)
        k.box([7, 1.2, 1], [dx + open * (dw / 2 - 5), dh * 0.48, z + 3.4], knob, 0.4)
        let heart = UIBezierPath()
        heart.move(to: CGPoint(x: 0, y: -2.6))
        heart.addCurve(to: CGPoint(x: 0, y: 1.6), controlPoint1: CGPoint(x: -4.4, y: 0.6), controlPoint2: CGPoint(x: -2, y: 3.8))
        heart.addCurve(to: CGPoint(x: 0, y: -2.6), controlPoint1: CGPoint(x: 2, y: 3.8), controlPoint2: CGPoint(x: 4.4, y: 0.6))
        heart.apply(CGAffineTransform(scaleX: CGFloat(k.u), y: CGFloat(k.u)))
        let love = SCNShape(path: heart, extrusionDepth: CGFloat(1 * k.u))
        love.materials = [k.material(UIColor(red: 1, green: 0.5, blue: 0.62, alpha: 1), 40)]
        let ink = k.keep(s.ink, 40)
        // W 比 C 宽，字高小一点才在门板里放得下
        let marks: [(Character, CGFloat)] = s.pet == .kitty ? [("C", 15), ("C", 15)] : [("C", 15), ("W", 13)]
        for (m, y) in zip(marks, [dh * 0.7, dh * 0.27]) { k.protect(k.letter(m.0, height: m.1, [dx, y, z + 3.9], ink)) }
        k.add(SCNNode(geometry: love), [dx, dh * 0.475, z + 3.4]).simdScale = [1.1, 1.1, 1]
        k.box([dw + 2, 0.8, 12], [dx, 1.8, z + 12], k.material(UIColor(red: 0.95, green: 0.66, blue: 0.5, alpha: 1), 2), 0.4)

        // 小狗家是一张沙发，画挂在沙发上面；小猫家是一架猫爬架，画挂得高一点免得被挡住
        let sx = k.at(98), py: Float = s.pet == .pup ? 56 : 98
        if s.pet == .pup {
            sofa(k, s, x: sx, z: z)
        } else {
            catTree(k, s, x: sx, z: z)
        }
        k.box([24, 20, 1.6], [sx, py, z + 0.8], wood, 0.5)
        k.box([19, 15, 1.8], [sx, py, z + 1], pictureMaterial(s.picture), 0)

        // 楼板底下吊一盏小灯：一根线、一顶小灯罩、一颗暖黄的灯泡
        let lx = k.at(72)
        k.rod([lx, H, z + 26], [lx, H - 10, z + 26], 0.45, k.material(UIColor(white: 0.35, alpha: 1), 4))
        let cone = SCNCone(topRadius: CGFloat(2 * k.u), bottomRadius: CGFloat(8 * k.u), height: CGFloat(7 * k.u))
        cone.materials = [k.material(s.roof, 40)]
        k.add(SCNNode(geometry: cone), [lx, H - 12, z + 26])
        k.blob([3, 3, 3], [lx, H - 16, z + 26], k.lamp(UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1)))

        // 圆地毯，外面一圈浅色
        for (i, (c, scale)) in [(s.rugEdge, Float(1)), (s.rug, 0.8)].enumerated() {
            let disc = SCNCylinder(radius: CGFloat(k.u), height: CGFloat(0.6 * k.u))
            disc.radialSegmentCount = 36
            disc.materials = [k.material(c, 2)]
            k.add(SCNNode(geometry: disc), [pet, 1.6 + Float(i) * 0.3, f.back + 34]).simdScale = [min(W * 0.3, 44) * scale, 1, 24 * scale]
        }
        petThing(k, s, at: [k.at(112), 0, f.front - 12])
    }
}
extension RhythmScene {
    /// 角落里的东西：小猫家是毛线球，小狗家是饭盆
    @MainActor private func petThing(_ k: Kit, _ s: HouseStyle, at c: SIMD3<Float>) {
        if s.pet == .kitty {
            // 毛线球：一团紫色，缠着两圈线，拖出一截线头
            let yarn = k.material(UIColor(red: 0.78, green: 0.66, blue: 0.98, alpha: 1), 6)
            k.blob([7, 7, 7], [c.x, 8.4, c.z], yarn)
            for (ax, ay): (Float, Float) in [(0.5, 0.2), (-0.4, 1.1)] {
                let ring = SCNTorus(ringRadius: CGFloat(6.6 * k.u), pipeRadius: CGFloat(0.7 * k.u))
                ring.materials = [k.material(UIColor(red: 0.66, green: 0.52, blue: 0.92, alpha: 1), 6)]
                k.add(SCNNode(geometry: ring), [c.x, 8.4, c.z]).eulerAngles = SCNVector3(ax, ay, 0.3)
            }
            k.rod([c.x + k.open * 5, 2.2, c.z + 4], [c.x + k.open * 18, 2, c.z + 8], 0.7, yarn)
        } else {
            // 饭盆：粉色的碗，里面一堆狗粮；旁边一个蓝色的水盆，盛着水
            let bowl = SCNCylinder(radius: CGFloat(8 * k.u), height: CGFloat(5 * k.u))
            bowl.materials = [k.material(UIColor(red: 1, green: 0.55, blue: 0.68, alpha: 1), 40)]
            k.add(SCNNode(geometry: bowl), [c.x, 3.9, c.z])
            k.blob([6.5, 2, 6.5], [c.x, 6.6, c.z], k.material(UIColor(red: 0.7, green: 0.45, blue: 0.28, alpha: 1), 6))
            let wx = c.x - k.open * 18
            let pail = SCNCylinder(radius: CGFloat(7 * k.u), height: CGFloat(4.4 * k.u))
            pail.materials = [k.material(UIColor(red: 0.45, green: 0.66, blue: 0.95, alpha: 1), 40)]
            k.add(SCNNode(geometry: pail), [wx, 3.6, c.z])
            let water = SCNCylinder(radius: CGFloat(5.8 * k.u), height: CGFloat(0.4 * k.u))
            water.materials = [k.material(UIColor(red: 0.78, green: 0.92, blue: 1, alpha: 1), 120)]
            k.add(SCNNode(geometry: water), [wx, 5.7, c.z])
        }
    }

    /// 小狗家的沙发：靠背、两边扶手、两块坐垫、一个小抱枕
    @MainActor private func sofa(_ k: Kit, _ s: HouseStyle, x sx: Float, z: Float) {
        let sofa = k.material(s.sofa, 12), cushion = k.material(Self.paler(s.sofa, 0.3), 12)
        k.box([46, 22, 7], [sx, 18, z + 4], sofa, 3)
        k.box([46, 10, 20], [sx, 8, z + 11], sofa, 3)
        for side: Float in [-1, 1] {
            k.box([6, 17, 20], [sx + side * 22, 10, z + 11], sofa, 3)
            k.box([19, 4, 16], [sx + side * 9.8, 14.5, z + 12.5], cushion, 2)
        }
        k.blob([5, 5, 2.4], [sx - k.open * 11, 21, z + 9], k.material(UIColor(white: 0.98, alpha: 1), 6)).eulerAngles.z = 0.3
    }

    /// 小猫家的猫爬架：底座、一根缠着麻绳的柱子、高低两块圆台，顶上一块软垫，低的那块圆台边上吊着一颗绒球
    @MainActor private func catTree(_ k: Kit, _ s: HouseStyle, x sx: Float, z: Float) {
        let felt = k.material(s.sofa, 10), pad = k.material(Self.paler(s.sofa, 0.35), 10)
        let rope = k.material(UIColor(red: 0.9, green: 0.78, blue: 0.58, alpha: 1), 6)
        let cz = z + 14, open = k.open
        k.box([36, 5, 26], [sx, 2.5, cz], felt, 2)
        let post = SCNCylinder(radius: CGFloat(3.6 * k.u), height: CGFloat(62 * k.u))
        post.materials = [rope]
        k.add(SCNNode(geometry: post), [sx, 36, cz])
        for y in stride(from: Float(9), through: 63, by: 6) {
            let ring = SCNTorus(ringRadius: CGFloat(3.6 * k.u), pipeRadius: CGFloat(0.5 * k.u))
            ring.materials = [k.material(UIColor(red: 0.8, green: 0.66, blue: 0.46, alpha: 1), 6)]
            k.add(SCNNode(geometry: ring), [sx, y, cz])
        }
        for (dx, y, r): (Float, Float, Float) in [(open * 8, 34, 13), (-open * 5, 66, 14)] {
            let disc = SCNCylinder(radius: CGFloat(r * k.u), height: CGFloat(3.4 * k.u))
            disc.radialSegmentCount = 36
            disc.materials = [felt]
            k.add(SCNNode(geometry: disc), [sx + dx, y, cz])
        }
        k.blob([11, 3, 10], [sx - open * 5, 69.5, cz], pad)
        let tip = sx + open * 18
        k.rod([tip, 32.4, cz + 4], [tip, 20, cz + 4], 0.4, k.material(UIColor(white: 0.5, alpha: 1), 4))
        k.blob([3, 3, 3], [tip, 18, cz + 4], k.material(UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1), 10))
    }

    /// 二楼：里面那头梯子口旁边是床头柜和台灯，然后是床（床头靠里、被子盖到床尾），床上面一扇圆窗；
    /// 门口那头小狗家是衣柜和足球，小猫家是书架和一盆花
    @MainActor private func upstairs(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let y = f.up, z = f.back + 4, open = k.open
        let wood = k.material(UIColor(red: 0.82, green: 0.6, blue: 0.42, alpha: 1), 20)
        let trim = k.material(UIColor(white: 0.98, alpha: 1), 20)

        // 床头柜和台灯
        let nx = k.at(44)
        k.box([16, 18, 16], [nx, y + 9, z + 10], wood, 1.2)
        k.box([10, 1.4, 1], [nx, y + 12, z + 18.2], trim, 0.4)
        k.blob([1.2, 1.2, 1], [nx, y + 12, z + 19], trim)
        k.rod([nx, y + 18, z + 10], [nx, y + 27, z + 10], 0.7, trim)
        let cone = SCNCone(topRadius: CGFloat(3 * k.u), bottomRadius: CGFloat(6 * k.u), height: CGFloat(8 * k.u))
        cone.materials = [k.lamp(UIColor(red: 1, green: 0.93, blue: 0.68, alpha: 1))]
        k.add(SCNNode(geometry: cone), [nx, y + 30, z + 10])

        // 床：床头板、床尾板、床垫、被子、枕头
        let bx = k.at(94), bl: Float = 72
        let head = bx - open * bl / 2, foot = bx + open * bl / 2
        k.box([4, 32, 30], [head, y + 16, z + 17], wood, 1.5)
        if s.pet == .kitty {
            // 小猫的床头上面是圆的
            let arch = SCNCylinder(radius: CGFloat(15 * k.u), height: CGFloat(4 * k.u))
            arch.radialSegmentCount = 36
            arch.materials = [wood]
            k.add(SCNNode(geometry: arch), [head, y + 32, z + 17]).eulerAngles.z = .pi / 2
        }
        k.box([4, 18, 30], [foot, y + 9, z + 17], wood, 1.5)
        k.box([bl, 6, 28], [bx, y + 7, z + 17], wood, 1)
        k.box([bl - 4, 6, 26], [bx, y + 13, z + 17], trim, 2.5)
        let quilt = k.material(s.quilt, 8)
        k.box([bl * 0.62, 4, 28], [bx + open * bl * 0.17, y + 15.5, z + 17], quilt, 2)
        k.box([bl * 0.62, 10, 2.4], [bx + open * bl * 0.17, y + 12, z + 31], quilt, 1.2)
        k.box([bl * 0.62, 1.2, 28.6], [bx + open * (bl * 0.17 - bl * 0.31 + 2), y + 15.8, z + 17], trim, 0.5)
        k.blob([10, 4, 9], [head + open * 13, y + 18.5, z + 17], k.material(UIColor(white: 1, alpha: 1), 10))

        // 床上面一扇圆窗：白框、十字窗棂，外面是蓝天上的太阳和白云（按主题换成夜空的月亮和星星、海里的光和气泡这些）
        let wy = y + f.U * 0.62
        let ring = SCNTorus(ringRadius: CGFloat(11 * k.u), pipeRadius: CGFloat(1.6 * k.u))
        ring.materials = [trim]
        k.add(SCNNode(geometry: ring), [bx, wy, z + 1.5]).eulerAngles.x = .pi / 2
        let glass = SCNCylinder(radius: CGFloat(10.5 * k.u), height: CGFloat(1 * k.u))
        glass.materials = [theme.glass.map(k.lamp) ?? k.glow(UIColor(red: 0.58, green: 0.82, blue: 1, alpha: 1))]
        k.add(SCNNode(geometry: glass), [bx, wy, z + 1]).eulerAngles.x = .pi / 2
        k.box([1.4, 21, 1.4], [bx, wy, z + 2.4], trim, 0.3)
        k.box([21, 1.4, 1.4], [bx, wy, z + 2.4], trim, 0.3)
        k.blob([3.4, 3.4, 0.6], [bx - 5, wy + 5, z + 1.8], theme.orb.map(k.lamp) ?? k.glow(UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)))
        for (cx, cy, r): (Float, Float, Float) in [(3, -4, 2.4), (6, -3.4, 2), (4.6, -2.2, 1.8), (-4, -5.5, 1.6), (-2.2, -5, 1.4)] {
            k.blob([r, r * 0.8, 0.5], [bx + cx, wy + cy, z + 1.8], theme.cloud.map(k.lamp) ?? k.glow(.white))
        }
        if s.pet == .pup {
            wardrobe(k, s, x: k.at(f.W - 44), y: y, z: z)
            football(k, at: [k.at(f.W - 16), y + 7, f.front - 16])
            return
        }

        // 书架：两层隔板、一排高高矮矮的彩色书
        let shx = k.at(f.W - 44), shelf = k.material(UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1), 14)
        // 前面敞开：背板、两边侧板、顶板
        k.box([30, 50, 2], [shx, y + 25, z + 1], shelf, 0.5)
        for side: Float in [-1, 1] { k.box([2, 50, 14], [shx + side * 14, y + 25, z + 7], shelf, 0.5) }
        k.box([30, 2, 14], [shx, y + 49, z + 7], shelf, 0.5)
        let colors: [UIColor] = [.init(red: 1, green: 0.6, blue: 0.6, alpha: 1), .init(red: 0.6, green: 0.78, blue: 1, alpha: 1),
                                 .init(red: 1, green: 0.85, blue: 0.45, alpha: 1), .init(red: 0.65, green: 0.88, blue: 0.62, alpha: 1),
                                 .init(red: 0.8, green: 0.66, blue: 1, alpha: 1)]
        for (row, by) in [(0, y + 4), (1, y + 27)] {
            k.box([28, 1.6, 13], [shx, by - 1, z + 7.6], wood, 0.3)
            var bxk = shx - 12
            for j in 0..<5 {
                let h: Float = [16, 13, 18, 14, 15][(j + row * 2) % 5], w: Float = j == 2 ? 5 : 4
                k.box([w, h, 10], [bxk + w / 2, by + h / 2, z + 8], k.material(colors[(j + row * 3) % 5], 20), 0.4)
                bxk += w + 0.8
            }
        }

        // 一盆花：陶土盆、绿叶、三朵小花
        let fx = k.at(f.W - 16)
        let pot = SCNCone(topRadius: CGFloat(6 * k.u), bottomRadius: CGFloat(4.4 * k.u), height: CGFloat(10 * k.u))
        pot.materials = [k.material(UIColor(red: 0.88, green: 0.52, blue: 0.38, alpha: 1), 10)]
        k.add(SCNNode(geometry: pot), [fx, y + 5, f.front - 16])
        let leaf = k.material(UIColor(red: 0.45, green: 0.78, blue: 0.45, alpha: 1), 20)
        for (dx, h, tilt): (Float, Float, Float) in [(-3, 14, 0.35), (0, 18, 0), (3, 13, -0.4)] {
            k.blob([2.6, 7, 1.6], [fx + dx, y + 10 + h / 2.4, f.front - 16], leaf).eulerAngles.z = tilt
        }
        for (dx, dy, c) in [(-4, 20, UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1)), (1, 25, UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)),
                            (5, 19, UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1))] as [(Float, Float, UIColor)] {
            k.blob([3, 3, 2], [fx + dx, y + dy, f.front - 14], k.material(c, 20))
        }
    }

    /// 小狗家的衣柜：两扇门、门上凸起的门板、两颗圆把手，顶上一圈檐，底下四只小脚
    @MainActor private func wardrobe(_ k: Kit, _ s: HouseStyle, x wx: Float, y: Float, z: Float) {
        let body = k.material(Self.paler(s.door, 0.45), 16), panel = k.material(Self.paler(s.door, 0.65), 16)
        let wood = k.material(UIColor(red: 0.82, green: 0.6, blue: 0.42, alpha: 1), 20)
        for (dx, dz): (Float, Float) in [(-13, 3), (13, 3), (-13, 13), (13, 13)] { k.box([3, 2.4, 3], [wx + dx, y + 1.2, z + dz], wood, 0.4) }
        k.box([32, 56, 16], [wx, y + 30, z + 8], body, 1.2)
        k.box([36, 3, 18], [wx, y + 59.5, z + 8], wood, 0.8)
        k.box([0.8, 52, 0.8], [wx, y + 30, z + 16.2], k.material(UIColor(white: 0.45, alpha: 1), 4), 0)
        for side: Float in [-1, 1] {
            k.box([11, 44, 1], [wx + side * 8, y + 30, z + 16.3], panel, 0.6)
            k.blob([1.3, 1.3, 1.2], [wx + side * 2.4, y + 30, z + 17.2], k.material(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), 90))
        }
    }

    /// 小狗的足球：白球上几块黑斑
    @MainActor private func football(_ k: Kit, at c: SIMD3<Float>) {
        k.blob([7, 7, 7], c, k.material(UIColor(white: 0.98, alpha: 1), 50))
        let patch = k.material(UIColor(white: 0.12, alpha: 1), 50)
        for d: SIMD3<Float> in [[0, 0.2, 1], [0.85, 0.35, 0.4], [-0.85, 0.3, 0.45], [0.2, 0.95, 0.2], [-0.45, -0.55, 0.7], [0.55, -0.6, 0.6]] {
            k.blob([2.3, 2.3, 2.3], c + simd_normalize(d) * 5.6, patch)
        }
    }

    /// 比 c 浅一点的颜色（往白色那边混 amount）
    static func paler(_ c: UIColor, _ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }
}
extension RhythmScene {
    /// 墙纸：小狗家是波点，小猫家是竖条纹，按墙的大小重复铺
    @MainActor private func wallpaper(_ s: HouseStyle, w: Float, h: Float) -> SCNMaterial {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            theme.house(s.paper).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            theme.house(s.pattern).setFill()
            if lookPattern(ctx.cgContext, s) {
            } else if s.stripes {
                ctx.fill(CGRect(x: 0, y: 0, width: 22, height: 64))
            } else {
                for (x, y) in [(16, 16), (48, 48)] { ctx.cgContext.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)) }
            }
        }
        let m = furMaterial(.white, shine: 4)
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(w / 30, h / 30, 1)
        return m
    }

    /// 屋檐下的木牌：浅木色底、深棕色的字
    @MainActor func signMaterial(_ text: String) -> SCNMaterial {
        let size = CGSize(width: 200, height: 60)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            theme.house(UIColor(red: 0.96, green: 0.86, blue: 0.7, alpha: 1)).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont(name: "PingFangSC-Semibold", size: 36) ?? .boldSystemFont(ofSize: 36),
                                                        .foregroundColor: theme.house(UIColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1))]
            let t = text as NSString, ts = t.size(withAttributes: attrs)
            t.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
        let m = furMaterial(.white, shine: 10)
        m.diffuse.contents = image
        return m
    }

    /// 墙上小画：奶白色底上一个小图案（骨头、小鱼）
    @MainActor private func pictureMaterial(_ emoji: String) -> SCNMaterial {
        let size = CGSize(width: 96, height: 76)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            theme.house(UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 50)]
            let t = emoji as NSString, ts = t.size(withAttributes: attrs)
            t.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
        let m = furMaterial(.white, shine: 4)
        m.diffuse.contents = image
        return m
    }
}

extension RhythmScene {
    /// 一条侧身的小鱼：圆鼓鼓的身子朝门口，后面一条三角尾巴，一只小黑眼睛
    @MainActor private func fish(_ k: Kit, at c: SIMD3<Float>, size r: Float, _ m: SCNMaterial) {
        k.blob([r, r * 0.6, r * 0.4], c, m)
        for side: Float in [-1, 1] {
            k.blob([r * 0.4, r * 0.24, r * 0.16], [c.x - k.open * r * 1.15, c.y + side * r * 0.28, c.z], m).eulerAngles.z = k.open * side * 0.6
        }
        k.blob([r * 0.12, r * 0.12, r * 0.08], [c.x + k.open * r * 0.55, c.y + r * 0.12, c.z + r * 0.34], k.material(UIColor(white: 0.08, alpha: 1), 90))
    }
}

extension RhythmScene {
    /// 小猫家一楼前面多出来的那截：里面那头一盆绿植、一条猫隧道，中间一张圆猫窝（里面一条小鱼抱枕），
    /// 再往门口是饭盆和水盆，地上散着玩具老鼠和两颗铃铛球。都比较矮，挡不住后面的小猫和滚出门的球
    @MainActor private func kittyGround(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let open = k.open
        let pink = UIColor(red: 1, green: 0.62, blue: 0.74, alpha: 1)

        // 绿植：陶土盆里几片高高的叶子
        let px = k.at(42), pz: Float = f.back + 98
        let pot = SCNCone(topRadius: CGFloat(8 * k.u), bottomRadius: CGFloat(6 * k.u), height: CGFloat(13 * k.u))
        pot.materials = [k.material(UIColor(red: 0.88, green: 0.52, blue: 0.38, alpha: 1), 10)]
        k.add(SCNNode(geometry: pot), [px, 6.5, pz])
        let leaf = k.material(UIColor(red: 0.4, green: 0.74, blue: 0.42, alpha: 1), 20)
        for (dx, dz, h, tilt): (Float, Float, Float, Float) in [(-4, 0, 26, 0.4), (0, -2, 32, 0), (4, 1, 24, -0.45), (-1, 3, 20, 0.15), (2, -3, 22, -0.2)] {
            k.blob([3, h / 2.4, 1.6], [px + dx, 13 + h / 2.4, pz + dz], leaf).eulerAngles.z = tilt
        }

        // 猫隧道：横躺的一截软管，两头一圈深色的口
        let tx = k.at(80), tz: Float = f.back + 86, tr: Float = 8.5
        let tube = SCNTube(innerRadius: CGFloat((tr - 1) * k.u), outerRadius: CGFloat(tr * k.u), height: CGFloat(36 * k.u))
        tube.materials = [k.material(UIColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 1), 20)]
        k.add(SCNNode(geometry: tube), [tx, tr, tz]).eulerAngles.z = .pi / 2
        for side: Float in [-1, 1] {
            let rim = SCNTorus(ringRadius: CGFloat((tr - 0.4) * k.u), pipeRadius: CGFloat(1.1 * k.u))
            rim.materials = [k.material(UIColor(red: 0.3, green: 0.5, blue: 0.85, alpha: 1), 20)]
            k.add(SCNNode(geometry: rim), [tx + side * 18, tr, tz]).eulerAngles.z = .pi / 2
        }

        // 玩具老鼠：灰色的身子、两只粉耳朵、一根长尾巴
        let mx = k.at(104), mz: Float = f.back + 114
        let grey = k.material(UIColor(white: 0.7, alpha: 1), 10)
        k.blob([5, 3.4, 3.4], [mx, 3.4, mz], grey)
        for side: Float in [-1, 1] { k.blob([1.6, 1.8, 0.6], [mx + open * 3, 6, mz + side * 1.8], k.material(pink, 10)) }
        k.blob([0.6, 0.6, 0.6], [mx + open * 5, 3.6, mz], k.material(pink, 40))
        k.rod([mx - open * 4.6, 2, mz], [mx - open * 13, 1, mz + 5], 0.4, k.material(pink, 10))

        // 圆猫窝：一圈软软的边、底下一块垫子，里面躺一条小鱼抱枕
        let bx = k.at(140), bz: Float = f.back + 94
        let ring = SCNTorus(ringRadius: CGFloat(12 * k.u), pipeRadius: CGFloat(4 * k.u))
        ring.materials = [k.material(s.sofa, 10)]
        k.add(SCNNode(geometry: ring), [bx, 4.6, bz])
        let base = SCNCylinder(radius: CGFloat(13 * k.u), height: CGFloat(2 * k.u))
        base.radialSegmentCount = 36
        base.materials = [k.material(s.sofa, 10)]
        k.add(SCNNode(geometry: base), [bx, 1.6, bz])
        k.blob([10, 1.6, 10], [bx, 3, bz], k.material(Self.paler(s.sofa, 0.4), 8))
        fish(k, at: [bx, 6, bz], size: 6, k.material(UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 1), 20))

        // 饭盆里一堆猫粮，水盆盛着水
        for (c, food) in [(Float(186), true), (204, false)] {
            let x = k.at(c), z: Float = f.back + 104
            let bowl = SCNCylinder(radius: CGFloat(7 * k.u), height: CGFloat(4.4 * k.u))
            bowl.materials = [k.material(food ? pink : UIColor(red: 0.5, green: 0.7, blue: 0.95, alpha: 1), 40)]
            k.add(SCNNode(geometry: bowl), [x, 3.6, z])
            if food {
                k.blob([5.6, 1.8, 5.6], [x, 6, z], k.material(UIColor(red: 0.72, green: 0.48, blue: 0.3, alpha: 1), 6))
            } else {
                let water = SCNCylinder(radius: CGFloat(5.8 * k.u), height: CGFloat(0.4 * k.u))
                water.materials = [k.material(UIColor(red: 0.78, green: 0.92, blue: 1, alpha: 1), 120)]
                k.add(SCNNode(geometry: water), [x, 5.5, z])
            }
        }
        k.box([40, 0.6, 18], [k.at(195), 1.7, f.back + 104], k.material(UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), 2), 0.3)

        // 两颗铃铛球：彩色镂空的小球，里面一颗金铃铛
        let gold = k.material(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), 90)
        for (c, z, color) in [(Float(168), f.back + 118, UIColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)),
                              (232, f.back + 90, UIColor(red: 0.6, green: 0.86, blue: 0.5, alpha: 1))] as [(Float, Float, UIColor)] {
            let x = k.at(c)
            for a: Float in [0, 1.05, 2.1] {
                let band = SCNTorus(ringRadius: CGFloat(4.4 * k.u), pipeRadius: CGFloat(0.6 * k.u))
                band.materials = [k.material(color, 30)]
                k.add(SCNNode(geometry: band), [x, 4.6, z]).eulerAngles = SCNVector3(Float.pi / 2, a, 0)
            }
            k.blob([2.2, 2.2, 2.2], [x, 4.6, z], gold)
        }
    }
}

extension RhythmScene {
    /// 小猫家二楼：里面那面墙上一串彩旗，床和书架中间一张梳妆台（椭圆镜子、香水瓶）和小圆凳；
    /// 前面多出来的那截一张懒人沙发、地毯上一张小茶几（茶杯和饼干），门口那头一个装满玩具的箱子
    @MainActor private func kittyUpstairs(_ k: Kit, _ s: HouseStyle, _ f: Frame) {
        let y = f.up, z = f.back + 4, open = k.open
        let wood = k.material(UIColor(red: 0.82, green: 0.6, blue: 0.42, alpha: 1), 20)
        let trim = k.material(UIColor(white: 0.98, alpha: 1), 20)
        let colors: [UIColor] = [.init(red: 1, green: 0.55, blue: 0.62, alpha: 1), .init(red: 1, green: 0.85, blue: 0.4, alpha: 1),
                                 .init(red: 0.55, green: 0.8, blue: 1, alpha: 1), .init(red: 0.62, green: 0.88, blue: 0.58, alpha: 1),
                                 .init(red: 0.8, green: 0.66, blue: 1, alpha: 1)]

        // 彩旗：两段往下垂的绳子，上面挂一串小三角旗
        let flag = UIBezierPath()
        flag.move(to: CGPoint(x: -3.2 * CGFloat(k.u), y: 0))
        flag.addLine(to: CGPoint(x: 3.2 * CGFloat(k.u), y: 0))
        flag.addLine(to: CGPoint(x: 0, y: -7 * CGFloat(k.u)))
        flag.close()
        let cord = k.material(UIColor(white: 0.55, alpha: 1), 4)
        var n = 0
        for (a, b): (Float, Float) in [(24, 130), (130, 236)] {
            let top = y + 92, sag: Float = 7, steps = 8
            func at(_ t: Float) -> SIMD3<Float> {
                [k.at(a + (b - a) * t), top - sag * 4 * t * (1 - t), z + 1.6]
            }
            for i in 0..<steps { k.rod(at(Float(i) / Float(steps)), at(Float(i + 1) / Float(steps)), 0.3, cord) }
            for i in 1..<steps {
                let shape = SCNShape(path: flag, extrusionDepth: CGFloat(0.4 * k.u))
                shape.materials = [k.material(colors[n % colors.count], 10)]
                n += 1
                k.add(SCNNode(geometry: shape), at(Float(i) / Float(steps)))
            }
        }

        // 梳妆台：桌面、两条桌腿中间一个小抽屉，上面一面白框的椭圆镜子，桌上一瓶香水和一把梳子
        let vx = k.at(166), body = k.material(Self.paler(s.sofa, 0.55), 16)
        k.box([34, 2.4, 14], [vx, y + 20, z + 7], body, 0.6)
        for side: Float in [-1, 1] { k.box([3, 19, 12], [vx + side * 15, y + 9.5, z + 7], body, 0.4) }
        k.box([22, 6, 12], [vx, y + 15.6, z + 7], body, 0.5)
        k.blob([1.2, 1.2, 1], [vx, y + 15.6, z + 13.4], trim)
        let frame = SCNTorus(ringRadius: CGFloat(10 * k.u), pipeRadius: CGFloat(1.4 * k.u))
        frame.materials = [trim]
        let frameNode = k.add(SCNNode(geometry: frame), [vx, y + 36, z + 2])
        frameNode.simdScale = [0.8, 1, 1.2]
        frameNode.eulerAngles.x = .pi / 2
        let mirror = SCNCylinder(radius: CGFloat(9.6 * k.u), height: CGFloat(0.8 * k.u))
        mirror.materials = [k.glow(UIColor(red: 0.82, green: 0.93, blue: 1, alpha: 1))]
        let mirrorNode = k.add(SCNNode(geometry: mirror), [vx, y + 36, z + 1.6])
        mirrorNode.simdScale = [0.8, 1, 1.2]
        mirrorNode.eulerAngles.x = .pi / 2
        k.box([4, 6, 4], [vx - open * 9, y + 24.2, z + 8], k.material(UIColor(red: 0.9, green: 0.7, blue: 1, alpha: 1), 120), 1)
        k.blob([1.6, 1.6, 1.6], [vx - open * 9, y + 28.4, z + 8], k.material(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), 90))
        k.box([9, 1.2, 3], [vx + open * 8, y + 21.8, z + 9], k.material(colors[0], 20), 0.4)
        let stool = SCNCylinder(radius: CGFloat(6 * k.u), height: CGFloat(3 * k.u))
        stool.materials = [k.material(colors[0], 10)]
        k.add(SCNNode(geometry: stool), [vx, y + 11, z + 26])
        for (dx, dz): (Float, Float) in [(-3.6, -3.6), (3.6, -3.6), (-3.6, 3.6), (3.6, 3.6)] {
            k.rod([vx + dx, y, z + 26 + dz], [vx + dx * 0.8, y + 9.6, z + 26 + dz * 0.8], 0.6, wood)
        }

        // 懒人沙发：一大团软软的，上面压出一个坑，搭一个小抱枕
        let sx = k.at(64), sz: Float = f.back + 92
        let bean = k.material(UIColor(red: 0.98, green: 0.78, blue: 0.5, alpha: 1), 8)
        k.blob([15, 9, 13], [sx, y + 9, sz], bean)
        k.blob([11, 7, 6], [sx - open * 3, y + 15, sz - 7], bean)
        k.blob([8, 3, 7], [sx + open * 2, y + 16.4, sz + 1], k.material(Self.paler(UIColor(red: 0.98, green: 0.78, blue: 0.5, alpha: 1), 0.4), 8))
        k.blob([4.4, 4.4, 2], [sx - open * 7, y + 19, sz - 1], k.material(colors[4], 8)).eulerAngles.z = open * 0.4

        // 椭圆地毯上一张小圆茶几：一根粗腿、圆桌面，上面一杯茶、一碟饼干
        let tx = k.at(122), tz: Float = f.back + 92
        for (i, (c, scale)) in [(Self.paler(s.rug, 0.3), Float(1)), (s.rug, 0.78)].enumerated() {
            let disc = SCNCylinder(radius: CGFloat(k.u), height: CGFloat(0.6 * k.u))
            disc.radialSegmentCount = 36
            disc.materials = [k.material(c, 2)]
            k.add(SCNNode(geometry: disc), [tx, y + 0.4 + Float(i) * 0.3, tz]).simdScale = [28 * scale, 1, 17 * scale]
        }
        let leg = SCNCylinder(radius: CGFloat(2.2 * k.u), height: CGFloat(10 * k.u))
        leg.materials = [wood]
        k.add(SCNNode(geometry: leg), [tx, y + 6, tz])
        let top = SCNCylinder(radius: CGFloat(12 * k.u), height: CGFloat(2 * k.u))
        top.radialSegmentCount = 36
        top.materials = [k.material(UIColor(white: 0.98, alpha: 1), 30)]
        k.add(SCNNode(geometry: top), [tx, y + 12, tz])
        let cup = SCNCylinder(radius: CGFloat(2.4 * k.u), height: CGFloat(4 * k.u))
        cup.materials = [k.material(colors[2], 40)]
        k.add(SCNNode(geometry: cup), [tx - open * 5, y + 15, tz])
        let tea = SCNCylinder(radius: CGFloat(2 * k.u), height: CGFloat(0.3 * k.u))
        tea.materials = [k.material(UIColor(red: 0.75, green: 0.5, blue: 0.3, alpha: 1), 60)]
        k.add(SCNNode(geometry: tea), [tx - open * 5, y + 16.9, tz])
        let plate = SCNCylinder(radius: CGFloat(4.4 * k.u), height: CGFloat(0.6 * k.u))
        plate.materials = [trim]
        k.add(SCNNode(geometry: plate), [tx + open * 4, y + 13.3, tz + 2])
        let cookie = k.material(UIColor(red: 0.9, green: 0.68, blue: 0.4, alpha: 1), 6)
        for (dx, dz): (Float, Float) in [(-1.6, -1), (1.8, 0.6), (0, 1.8)] {
            k.blob([1.8, 0.7, 1.8], [tx + open * (4 + dx), y + 14.2, tz + 2 + dz], cookie)
        }

        // 玩具箱：箱盖往后掀开，里面露出小球、小鱼、逗猫棒和一颗星星
        let bx = k.at(200), bz: Float = f.back + 96
        let chest = k.material(colors[2], 16)
        k.box([26, 13, 16], [bx, y + 6.5, bz], chest, 1)
        k.box([26, 2, 16], [bx, y + 13.4, bz], k.material(Self.paler(colors[2], 0.4), 16), 0.6)
        k.box([27, 1.6, 15], [bx, y + 19, bz - 10], chest, 0.6).eulerAngles.x = -1.2
        k.box([8, 6, 0.6], [bx, y + 6.5, bz + 8.1], trim, 0.3)
        k.blob([4, 4, 4], [bx - open * 6, y + 15, bz - 1], k.material(colors[0], 30))
        fish(k, at: [bx + open * 3, y + 15.4, bz + 3], size: 4.4, k.material(colors[1], 20))
        k.rod([bx + open * 8, y + 13, bz - 2], [bx + open * 14, y + 30, bz - 4], 0.5, wood)
        k.blob([2.4, 2.4, 2.4], [bx + open * 14.4, y + 31, bz - 4], k.material(colors[4], 6))
        k.letter("★", height: 8, [bx - open * 1, y + 18, bz - 4], k.material(colors[1], 60))
    }
}
