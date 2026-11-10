import UIKit

/// 律动画面的场景主题：墙、卡片、支架、架子、小球、灯光、歌名、两个小家的配色，和飘在画面里的雪花、花瓣这些。
/// 小狗、小猫、门上的 CW / CC 和门外台子上的两个词不跟主题走（RhythmScene.keepLight），换哪个主题都一样
struct RhythmTheme {
    enum Id: String, CaseIterable, Identifiable {
        case shuffle, cream, starry, sakura, snow, ocean, neon, autumn
        var id: String { rawValue }

        var name: String {
            switch self {
            case .shuffle: "每首随机"
            case .cream: "奶油拼板"
            case .starry: "星夜"
            case .sakura: "樱花"
            case .snow: "雪国"
            case .ocean: "深海"
            case .neon: "霓虹"
            case .autumn: "秋林"
            }
        }

        var note: String {
            switch self {
            case .shuffle: "每首歌换一个场景"
            case .cream: "浅色拼板墙、粉色亚克力"
            case .starry: "水晶跳板、光轨，天文台"
            case .sakura: "樱花跳板、竹架，飞檐小楼"
            case .snow: "积雪冰块、冰棱，雪屋"
            case .ocean: "水母跳板、珍珠绳，贝壳屋"
            case .neon: "发光线框、激光轨，霓虹屋"
            case .autumn: "蘑菇跳板、树枝，蘑菇屋"
            }
        }

        /// 真正的场景（不含「每首随机」）
        static let scenes = allCases.filter { $0 != .shuffle }
    }

    /// 墙上的图案
    enum Wall {
        case panels, stars, blossoms, snowflakes, waves, grid, boards
    }
    /// 画面里飘的东西
    enum Drift {
        case snow, petals, fireflies, bubbles, sparks, leaves
    }
    /// 场景里东西的造型：跳板、架子、搁板、房子、小球、踩中的效果都按它换一套。
    /// classic 是原来的亚克力卡片和镀铬铁丝；crystal 漂浮的六角水晶、天文台；blossom 樱花跳板、竹子、两层飞檐；
    /// ice 积雪的冰块、冰棱、雪屋；reef 水母、绳子和珍珠、扇贝屋顶；neon 发光线框、激光、平顶霓虹屋；forest 蘑菇、树枝、蘑菇屋
    enum Look {
        case classic, crystal, blossom, ice, reef, neon, forest
    }

    /// 两个小家的调色：先按 sat 去掉一些饱和度，再往 tint 混 amount，最后整体乘 bright。默认什么都不改
    struct Grade {
        var tint: UIColor = .white, amount: CGFloat = 0, bright: CGFloat = 1, sat: CGFloat = 1

        func callAsFunction(_ c: UIColor) -> UIColor {
            guard amount != 0 || bright != 1 || sat != 1 else { return c }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            var t = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
            tint.getRed(&t.r, green: &t.g, blue: &t.b, alpha: &t.a)
            let l = 0.3 * r + 0.59 * g + 0.11 * b
            func f(_ x: CGFloat, _ tx: CGFloat) -> CGFloat {
                let s = l + (x - l) * sat
                return min(1, max(0, (s + (tx - s) * amount) * bright))
            }
            return UIColor(red: f(r, t.r), green: f(g, t.g), blue: f(b, t.b), alpha: a)
        }

        /// 自己发光的东西（窗玻璃、镜子）只混一半颜色，不压暗
        var glow: Grade { Grade(tint: tint, amount: amount / 2, bright: 1, sat: sat) }
    }

    let id: Id
    var look: Look = .classic
    var wall: Wall
    var wallColor: UIColor
    /// 墙上图案的颜色，第二种颜色（霓虹网格的竖线）
    var accent: UIColor
    var accent2: UIColor
    /// 卡片按组轮流用的颜色，第一种也用在小狗、小猫家底下的搁板上（除非另给了 shelf）
    var cards: [UIColor]
    /// 搁板上印着门外那两个词，太艳的卡片色衬不出字，这时另给一个颜色
    var shelf: UIColor?
    /// 卡片的不透明度、镜面反光
    var cardClear: CGFloat = 0.8
    var cardShine: CGFloat = 0.18
    /// 卡片没踩到时、踩到后的自发光
    var cardIdle: CGFloat = 0
    var cardLit: CGFloat = 0.15
    /// 卡片上的字乘上的颜色：饱和度、亮度（色相按字）
    var labelSat: CGFloat = 0.32
    var labelBright: CGFloat = 0.95
    /// 金属支架：乘上的颜色（白色是镀铬，金色是黄铜）和底色的灰度
    var metal: UIColor = .white
    var metalBase: CGFloat = 0.3
    var plank: UIColor
    var tube: UIColor
    var tubeClear: CGFloat = 0.42
    var ball: UIColor
    /// 踩中时的光环、溅起的光点的饱和度
    var ring: UIColor = .white
    var spark: CGFloat = 0.45
    /// 歌名每个字轮流用的色相、饱和度、自发光
    var titleHues: [CGFloat] = [0.36, 0.15, 0.93, 0.78, 0.52]
    var titleSat: CGFloat = 0.55
    var titleGlow: CGFloat = 0.55
    /// 歌名下面那行小字
    var ink: UIColor
    /// 平行光、环境光（颜色、强度）
    var light: (UIColor, CGFloat) = (.rgb(1, 0.97, 0.94), 850)
    var ambient: (UIColor, CGFloat) = (.rgb(0.85, 0.87, 0.95), 600)
    /// 两个小家
    var house = Grade()
    /// 屋顶换成这个颜色（雪国的积雪），nil 是原来的
    var roof: UIColor?
    /// 窗外：玻璃（天空）、太阳（月亮）、白云（星星、气泡），nil 是原来的白天
    var glass: UIColor?
    var orb: UIColor?
    var cloud: UIColor?
    var drift: Drift?
    var driftColor: UIColor = .white

    /// 按设置里选的主题定下这首歌的场景；「每首随机」按歌的 id 挑，同一首歌每次一样。
    /// 奶油拼板沿用每首歌自己的那套配色（RhythmStage.palette）
    static func make(_ id: Id, song: String, palette: Int) -> RhythmTheme {
        var pick = id
        if id == .shuffle {
            var rng = SeededRandom(song + "#theme")
            pick = Id.scenes.randomElement(using: &rng) ?? .cream
        }
        let p = RhythmPalette.all[min(max(palette, 0), RhythmPalette.all.count - 1)]
        switch pick {
        case .shuffle, .cream: return cream(p)
        case .starry: return starry
        case .sakura: return sakura
        case .snow: return snow
        case .ocean: return ocean
        case .neon: return neon
        case .autumn: return autumn
        }
    }

    /// 原来的样子：偏灰的拼板墙、粉色亚克力卡片、镀铬支架
    static func cream(_ p: RhythmPalette) -> RhythmTheme {
        RhythmTheme(id: .cream, wall: .panels, wallColor: p.wallColor, accent: p.wallColor, accent2: p.wallColor, cards: [p.card],
                    plank: .rgb(0.86, 0.74, 0.58), tube: p.tube, ball: .rgb(1, 0.45, 0.64), ink: p.ink)
    }
}

extension UIColor {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    var components: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// 往 other 混 k（0 是自己，1 是 other）
    func mixed(_ other: UIColor, _ k: CGFloat) -> UIColor {
        let x = components, y = other.components
        return .rgb(x.r + (y.r - x.r) * k, x.g + (y.g - x.g) * k, x.b + (y.b - x.b) * k)
    }
}

extension RhythmTheme {
    /// 星夜：深蓝的夜空墙上满是星星，长春花色的半透明卡片、银色支架、金色的星星小球，萤火虫慢慢飘；
    /// 小家在月光下暗一些，窗外是夜空和月亮
    static let starry: RhythmTheme = {
        var t = RhythmTheme(id: .starry, wall: .stars, wallColor: .rgb(0.11, 0.13, 0.27), accent: .rgb(1, 0.95, 0.82),
                            accent2: .rgb(0.45, 0.4, 0.85),
                            cards: [.rgb(0.62, 0.66, 1), .rgb(0.78, 0.66, 1), .rgb(0.55, 0.8, 1)],
                            plank: .rgb(0.4, 0.37, 0.55), tube: .rgb(0.78, 0.82, 1), ball: .rgb(1, 0.8, 0.35), ink: .rgb(0.82, 0.85, 1))
        t.look = .crystal
        t.cardClear = 0.74
        t.cardShine = 0.3
        t.cardIdle = 0.12
        t.cardLit = 0.35
        t.labelSat = 0.22
        t.labelBright = 1
        t.metal = .rgb(0.85, 0.9, 1)
        t.metalBase = 0.25
        t.tubeClear = 0.35
        t.ring = .rgb(1, 0.92, 0.6)
        t.spark = 0.35
        t.titleHues = [0.12, 0.58, 0.75, 0.14, 0.53]
        t.titleSat = 0.42
        t.titleGlow = 0.7
        t.light = (.rgb(0.78, 0.82, 1), 700)
        t.ambient = (.rgb(0.45, 0.5, 0.85), 430)
        t.house = Grade(tint: .rgb(0.3, 0.35, 0.7), amount: 0.22, bright: 0.92, sat: 0.9)
        t.glass = .rgb(0.1, 0.14, 0.36)
        t.orb = .rgb(1, 0.96, 0.78)
        t.cloud = .rgb(0.55, 0.6, 0.85)
        t.drift = .fireflies
        t.driftColor = .rgb(1, 0.88, 0.5)
        return t
    }()

    /// 樱花：豆沙粉的墙纸上印着樱花，珍珠白和樱花粉的卡片、玫瑰金支架、白桦木板，花瓣斜着飘下来
    static let sakura: RhythmTheme = {
        var t = RhythmTheme(id: .sakura, wall: .blossoms, wallColor: .rgb(0.8, 0.63, 0.69), accent: .rgb(0.91, 0.77, 0.81),
                            accent2: .rgb(0.7, 0.5, 0.57),
                            cards: [.rgb(1, 0.93, 0.95), .rgb(1, 0.72, 0.8)],
                            plank: .rgb(0.93, 0.83, 0.72), tube: .rgb(0.85, 0.97, 0.9), ball: .rgb(1, 0.5, 0.66), ink: .rgb(0.4, 0.2, 0.28))
        t.look = .blossom
        t.cardClear = 0.84
        t.cardShine = 0.25
        t.labelSat = 0.45
        t.labelBright = 0.9
        t.metal = .rgb(1, 0.84, 0.8)
        t.metalBase = 0.32
        t.spark = 0.4
        t.titleHues = [0.95, 0.3, 0.92, 0.1, 0.97]
        t.titleSat = 0.45
        t.light = (.rgb(1, 0.95, 0.95), 850)
        t.ambient = (.rgb(0.95, 0.86, 0.9), 620)
        t.house = Grade(tint: .rgb(1, 0.78, 0.85), amount: 0.2)
        t.drift = .petals
        t.driftColor = .rgb(1, 0.82, 0.88)
        return t
    }()

    /// 雪国：冰蓝的墙上一朵朵雪花，冰块一样透亮的卡片、银色支架，下着雪；两个小家的屋顶积了雪，窗外是冬天的淡蓝天
    static let snow: RhythmTheme = {
        var t = RhythmTheme(id: .snow, wall: .snowflakes, wallColor: .rgb(0.44, 0.55, 0.7), accent: .rgb(0.63, 0.73, 0.87),
                            accent2: .rgb(0.38, 0.48, 0.63),
                            cards: [.rgb(0.82, 0.93, 1), .rgb(0.95, 0.98, 1)],
                            plank: .rgb(0.78, 0.66, 0.54), tube: .rgb(0.95, 0.97, 1), ball: .rgb(0.45, 0.75, 1), ink: .rgb(0.14, 0.22, 0.36))
        t.look = .ice
        t.cardClear = 0.68
        t.cardShine = 0.45
        t.labelSat = 0.3
        t.labelBright = 1
        t.metal = .rgb(0.92, 0.96, 1)
        t.metalBase = 0.35
        t.tubeClear = 0.5
        t.spark = 0.25
        t.titleHues = [0.58, 0.98, 0.33, 0.55, 0.12]
        t.titleSat = 0.45
        t.light = (.rgb(0.95, 0.98, 1), 900)
        t.ambient = (.rgb(0.82, 0.9, 1), 600)
        t.house = Grade(tint: .rgb(0.7, 0.8, 0.95), amount: 0.16, bright: 0.95, sat: 0.9)
        t.roof = .rgb(0.97, 0.98, 1)
        t.glass = .rgb(0.78, 0.88, 0.98)
        t.orb = .rgb(1, 0.95, 0.82)
        t.cloud = .white
        t.drift = .snow
        return t
    }()
}

extension RhythmTheme {
    /// 深海：墨绿的海水里晃着一道道光纹，水母一样微微发光的青绿、浅蓝、珊瑚色卡片，黄铜支架、浮木架子，气泡往上冒
    static let ocean: RhythmTheme = {
        var t = RhythmTheme(id: .ocean, wall: .waves, wallColor: .rgb(0.08, 0.3, 0.4), accent: .rgb(0.4, 0.8, 0.82),
                            accent2: .rgb(0.05, 0.22, 0.32),
                            cards: [.rgb(0.45, 0.95, 0.88), .rgb(0.55, 0.8, 1), .rgb(1, 0.62, 0.58)],
                            plank: .rgb(0.62, 0.56, 0.48), tube: .rgb(0.6, 0.95, 1), ball: .rgb(0.35, 0.85, 1), ink: .rgb(0.75, 0.95, 1))
        t.look = .reef
        t.cardClear = 0.7
        t.cardShine = 0.3
        t.cardIdle = 0.1
        t.cardLit = 0.35
        t.labelSat = 0.3
        t.labelBright = 1
        t.metal = .rgb(1, 0.82, 0.5)
        t.tubeClear = 0.35
        t.ring = .rgb(0.75, 1, 1)
        t.spark = 0.4
        t.titleHues = [0.5, 0.13, 0.02, 0.45, 0.58]
        t.titleSat = 0.5
        t.titleGlow = 0.65
        t.light = (.rgb(0.8, 1, 0.98), 700)
        t.ambient = (.rgb(0.4, 0.72, 0.85), 480)
        t.house = Grade(tint: .rgb(0.2, 0.65, 0.75), amount: 0.25, bright: 0.92)
        t.glass = .rgb(0.15, 0.5, 0.7)
        t.orb = .rgb(0.8, 1, 0.95)
        t.cloud = .rgb(0.75, 0.95, 1)
        t.drift = .bubbles
        t.driftColor = .rgb(0.75, 0.95, 1)
        return t
    }()

    /// 霓虹：近黑的墙上一张品红、青色的发光网格，卡片一直亮着、踩到更亮，黑色的金属、发光的小球，空中飘着小光点
    static let neon: RhythmTheme = {
        var t = RhythmTheme(id: .neon, wall: .grid, wallColor: .rgb(0.07, 0.05, 0.13), accent: .rgb(1, 0.25, 0.75),
                            accent2: .rgb(0.2, 0.85, 1),
                            cards: [.rgb(1, 0.3, 0.75), .rgb(0.25, 0.9, 1), .rgb(0.62, 0.42, 1)],
                            plank: .rgb(0.16, 0.13, 0.24), tube: .rgb(0.3, 0.95, 1), ball: .rgb(1, 0.35, 0.8), ink: .rgb(0.9, 0.85, 1))
        t.look = .neon
        t.cardClear = 0.75
        t.cardShine = 0.35
        t.cardIdle = 0.35
        t.cardLit = 0.9
        t.labelSat = 0.5
        t.labelBright = 1
        t.metal = .rgb(0.65, 0.6, 0.9)
        t.metalBase = 0.08
        t.tubeClear = 0.4
        t.ring = .rgb(0.4, 1, 1)
        t.shelf = .rgb(0.3, 0.22, 0.5)
        t.spark = 0.75
        t.titleHues = [0.9, 0.52, 0.78, 0.15]
        t.titleSat = 0.7
        t.titleGlow = 0.9
        t.light = (.rgb(0.9, 0.8, 1), 620)
        t.ambient = (.rgb(0.55, 0.4, 0.9), 380)
        t.house = Grade(tint: .rgb(0.5, 0.2, 0.7), amount: 0.3, bright: 0.78, sat: 1.15)
        t.glass = .rgb(0.12, 0.05, 0.28)
        t.orb = .rgb(1, 0.4, 0.8)
        t.cloud = .rgb(0.4, 0.95, 1)
        t.drift = .sparks
        t.driftColor = .rgb(0.5, 0.9, 1)
        return t
    }()

    /// 秋林：一面竖着拼的木板墙，琥珀、橘红、麦黄的卡片，紫铜支架、深色木板，枫叶打着转落下来；窗外是傍晚的夕阳
    static let autumn: RhythmTheme = {
        var t = RhythmTheme(id: .autumn, wall: .boards, wallColor: .rgb(0.62, 0.44, 0.32), accent: .rgb(0.46, 0.3, 0.2),
                            accent2: .rgb(0.72, 0.53, 0.4),
                            cards: [.rgb(1, 0.72, 0.35), .rgb(1, 0.5, 0.32), .rgb(0.98, 0.85, 0.45)],
                            plank: .rgb(0.72, 0.5, 0.32), tube: .rgb(1, 0.88, 0.6), ball: .rgb(1, 0.55, 0.2), ink: .rgb(1, 0.9, 0.75))
        t.look = .forest
        t.cardShine = 0.22
        t.labelSat = 0.4
        t.labelBright = 1
        t.metal = .rgb(1, 0.72, 0.5)
        t.ring = .rgb(1, 0.92, 0.7)
        t.spark = 0.55
        t.titleHues = [0.08, 0.13, 0.02, 0.25, 0.11]
        t.titleSat = 0.6
        t.light = (.rgb(1, 0.9, 0.78), 850)
        t.ambient = (.rgb(0.95, 0.8, 0.68), 560)
        t.house = Grade(tint: .rgb(1, 0.62, 0.32), amount: 0.18)
        t.glass = .rgb(1, 0.8, 0.55)
        t.orb = .rgb(1, 0.55, 0.3)
        t.cloud = .rgb(1, 0.92, 0.82)
        t.drift = .leaves
        t.driftColor = .rgb(1, 0.58, 0.25)
        return t
    }()
}
