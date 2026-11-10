import CoreGraphics
import Foundation

/// 卡片和架子的摆放（世界坐标，单位是屏幕点：x 往右，可以超出屏幕两边 spread，镜头跟着左右移；
/// y 沿着墙往下增加；z 是离墙多远）
struct RhythmStage {
    struct Tile {
        /// 卡片左右的中心和顶面的高度
        var x: CGFloat
        var y: CGFloat
        /// 小球落到这张卡片上的秒数
        var time: Double
        var text: String
        /// 字的颜色（色相），每个字挑一种粉彩
        var hue: Double
        /// 卡片绕竖轴转开多少（弧度），每张随机一点
        var yaw: CGFloat
        /// 在第几组
        var row: Int
    }

    /// 一组卡片：一句（太长时半句）歌词
    struct Row {
        var tiles: Range<Int>
        /// 第一个字和最后一个字的时间
        var start: Double
        var end: Double
        /// 这一组卡片加上后面那段架子在墙上占的高度，镜头外的不画
        var span: ClosedRange<CGFloat>
    }

    /// 一段架子：小球掉上来，沿着它从 at(0) 走到 at(1)，再掉到下一段或者蹦到下一组第一张卡片上
    struct Track {
        enum Kind {
            case rail, plank, tube
        }
        var kind: Kind
        /// 小球贴着走的地方（球底的接触点），s 从 0 到 1 均匀取的点
        var path: [Point3]
        /// 小球落到 at(0) 和离开 at(1) 的秒数
        var arrive: Double
        var leave: Double

        func at(_ s: CGFloat) -> Point3 {
            let x = min(max(s, 0), 1) * CGFloat(path.count - 1), j = min(Int(x), path.count - 2), q = x - CGFloat(j)
            let a = path[j], b = path[j + 1]
            return Point3(x: a.x + (b.x - a.x) * q, y: a.y + (b.y - a.y) * q, z: a.z + (b.z - a.z) * q)
        }
    }

    /// 小狗、小猫的家：两层楼，横向从 x 的一头到另一头，地板顶面在 floor，一楼高 height，楼板上面二楼高 upper，
    /// 再往上是尖屋顶。前面敞开（镜头看得到里面），open 那边（1 右、-1 左）也没有墙，球从一楼那边进出
    struct Room {
        var x: ClosedRange<CGFloat>
        var floor: CGFloat
        var height: CGFloat
        var upper: CGFloat = 100
        var open: CGFloat
        /// 门外搁板多伸出去的一截台子，球落在上面再滚进门
        static let porch: CGFloat = 46
        /// 小猫家门外的台子宽 1.5 倍，两行字分开写在台子的 1/3 和 2/3 处，门柱挡不住
        static let kittyPorch: CGFloat = 69
        static let slab: CGFloat = 6
        /// 小动物离门口那边多远，再往里留多少地方放家具
        static let pupSpot: CGFloat = 72
        static let furniture: CGFloat = 160
        /// 搁板和小狗家从墙往前多深；小猫家深一倍，前面多出来的地方摆家具和玩具，门外台子上的字也写得下大一点
        static let depth: CGFloat = 62
        static let kittyDepth: CGFloat = 124
        var width: CGFloat { x.upperBound - x.lowerBound }
        var mid: CGFloat { (x.lowerBound + x.upperBound) / 2 }
        var walls: CGFloat { height + Self.slab + upper }
        var rise: CGFloat { min(width * 0.26, 60) }
        /// 连屋顶、烟囱在内最高到哪
        var top: CGFloat { floor - walls - rise - 14 }
    }

    var tiles: [Tile] = []
    var rows: [Row] = []
    /// tracks[r] 是接在第 r 组后面的一串架子（间隔长时是一级级往下的木板），最后一组后面没有架子，是接球的小猫
    var tracks: [[Track]] = []
    /// 前奏时陪小球玩的小狗站在哪（脚下那块搁板顶面的中间），脸朝 pupDir 那边（1 往右，-1 往左）
    var pup = Point3(x: 0, y: 0, z: 0)
    var pupDir: CGFloat = 1
    /// 小狗把球顶出去的秒数，球按重力飞到第一张卡片上
    var throwAt = 0.0
    /// 镜头从歌名开始往下移的秒数
    var introStart = 0.0
    /// 小球在小狗面前的搁板上蹦的地方
    var toy: Point3 { Point3(x: pup.x + pupDir * 44, y: pup.y, z: Self.trackZ) }
    var pupRoom = Room(x: 0...0, floor: 0, height: 0, open: 1)
    /// 唱完后接球的小猫趴在哪（脚下那块搁板顶面的中间），脸朝 kittyDir 那边；球落到搁板上的秒数
    var kitty = Point3(x: 0, y: 0, z: 0)
    var kittyDir: CGFloat = 1
    var catchAt = 0.0
    var kittyRoom = Room(x: 0...0, floor: 0, height: 0, open: 1)
    /// 球停在小猫爪子前面的地方，和球落下来的地方（门外的台子上）
    var kittyPaw: Point3 { Point3(x: kitty.x + kittyDir * Self.catPaw, y: kitty.y, z: Self.trackZ) }
    var kittyLanding: Point3 { Point3(x: kittyPaw.x + kittyDir * (Self.catReach + Self.catPorch), y: kitty.y, z: Self.trackZ) }
    /// 镜头跟着走的点（时间、x、y），按时间排好
    private(set) var marks: [(t: Double, x: CGFloat, y: CGFloat)] = []
    private(set) var beatOnly = false
    let width: CGFloat
    /// 墙顶上的歌名和下面一行小字（歌手；没有时间轴歌词时是提示）
    let title: String
    private(set) var subtitle: String
    /// 用哪套配色（RhythmPalette.all）
    private(set) var palette = 0

    static let perRow = 6
    static let margin: CGFloat = 50

    /// 卡片和架子最多超出屏幕两边多远
    var spread: CGFloat { width * 0.45 }

    init(lyrics: Lyrics?, duration: Double, width: CGFloat, title: String = "", artist: String = "", seed: String = "") {
        self.width = max(width, 200)
        self.title = title
        subtitle = artist
        var notes = Self.notes(lyrics, title: title, artist: artist)
        if notes.isEmpty {
            beatOnly = true
            subtitle = "没有带时间轴的歌词，按固定节拍跳"
            notes = Self.beats(duration > 0 ? duration : 240)
        }
        var rng = SeededRandom(seed)
        palette = Int.random(in: 0..<RhythmPalette.all.count, using: &rng)
        layout(notes, &rng)
        track()
    }

    /// 每句歌词拆成一个个字（时间 + 字）。有逐字时间用逐字的；没有时按字数估算，和歌词页的填色一致
    private static func notes(_ l: Lyrics?, title: String, artist: String) -> [[(Double, String)]] {
        guard let l, l.synced else { return [] }
        // 开头的歌名、作词作曲这些署名，前面一行行跳过；中间夹着的署名（编曲、制作人、版权声明）也不要
        let lead = l.lines.prefix { credit($0.text, title: title, artist: artist) }.count
        return l.lines.indices.dropFirst(lead).compactMap { i -> [(Double, String)]? in
            let line = l.lines[i]
            if credit(line.text, title: title, artist: artist, strict: true) {
                return nil
            }
            guard let start = line.time else { return nil }
            if let words = line.words {
                let list = words.compactMap { w -> (Double, String)? in
                    let s = w.text.trimmingCharacters(in: .whitespaces)
                    return s.isEmpty ? nil : (w.time, s)
                }
                return list.isEmpty ? nil : list
            }
            // 外文按空格分词，中日韩按字
            let latin = line.text.contains(" ") && line.text.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
            let parts = latin ? line.text.split(whereSeparator: \.isWhitespace).map(String.init)
                              : line.text.filter { !$0.isWhitespace }.map(String.init)
            guard !parts.isEmpty else { return nil }
            let next = l.lines.indices.contains(i + 1) ? l.lines[i + 1].time ?? .infinity : .infinity
            let span = max(min(next - start, max(1, Double(parts.count) * 0.35)), 0.3)
            let each = span / Double(parts.count)
            return parts.enumerated().map { (start + each * Double($0.offset), $0.element) }
        }
    }

    private static let roles = ["作词", "作曲", "编曲", "词", "曲", "演唱", "原唱", "翻唱", "制作", "监制", "出品", "发行", "混音", "录音",
                                "母带", "和声", "配唱", "吉他", "贝斯", "鼓", "键盘", "弦乐", "钢琴", "人声", "企划", "统筹", "策划",
                                "营销", "推广", "版权", "封面", "设计", "op", "sp", "lyrics", "lyricist", "composer", "composed",
                                "arranger", "arranged", "producer", "produced", "mix", "mixed", "master", "vocal", "written"]

    /// 是不是歌词以外的描述：「作词：xx」「Composed by xx」「歌名 - 歌手」、版权声明。
    /// strict 时只认带职务名的，免得把正好带冒号的歌词也去掉；开头那几行不 strict，冒号前很短的都算
    private static func credit(_ text: String, title: String, artist: String, strict: Bool = false) -> Bool {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty || s.contains("著作权") || s.contains("未经") || s.contains("版权所有") || s.contains("翻译作品") {
            return true
        }
        if let c = s.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let head = s[..<c].trimmingCharacters(in: .whitespaces)
            if roles.contains(where: { head.hasPrefix($0) || head.hasSuffix($0) }) {
                return true
            }
            if !strict, head.count <= 8 {
                return true
            }
        }
        if s.hasPrefix("lyrics by") || s.hasPrefix("music by") || s.hasPrefix("composed by") || s.hasPrefix("produced by")
            || s.hasPrefix("arranged by") || s.hasPrefix("written by") {
            return true
        }
        guard !strict else { return false }
        let t = title.lowercased(), a = artist.lowercased()
        if !t.isEmpty, s == t || (s.contains(t) && (s.contains(" - ") || s.contains("-") || (!a.isEmpty && s.contains(a)))) {
            return true
        }
        return s.contains("纯音乐") || s.contains("请欣赏")
    }

    private static func beats(_ duration: Double) -> [[(Double, String)]] {
        let times = Array(stride(from: 0.5, to: duration, by: 0.5))
        return stride(from: 0, to: times.count, by: perRow).map { i in times[i..<min(i + perRow, times.count)].map { ($0, "") } }
    }

    /// 镜头跟着的点：前奏刚开始时看着墙顶上的歌名和下面小狗的家，快扔球时移到小狗身上；然后是每张卡片的落点，
    /// 架子上取两头（小球在上面走得久，镜头跟着平移）或中间；唱完停在小猫的家上
    private mutating func track() {
        guard !tiles.isEmpty else { return }
        let open = min(introStart + 1, tiles[0].time - 3)
        marks = [(open, width / 2, pup.y - 40 - Self.introLift)]
        if throwAt - 0.4 > open {
            marks.append((throwAt - 0.4, toy.x, toy.y - 30))
        }

        func follow(_ ks: [Track]) {
            for k in ks {
                if k.leave - k.arrive > 1.5 {
                    let a = k.at(0.1), b = k.at(0.9)
                    marks += [(k.arrive, a.x, a.y), (k.leave, b.x, b.y)]
                } else {
                    let p = k.at(0.5)
                    marks.append(((k.arrive + k.leave) / 2, p.x, p.y))
                }
            }
        }
        for i in tiles.indices {
            let p = landing(i)
            marks.append((tiles[i].time, p.x, p.y))
            if i + 1 == rows[tiles[i].row].tiles.upperBound {
                follow(tracks[tiles[i].row])
            }
        }
        marks.append((catchAt + 1.2, kittyRoom.mid, kitty.y - 80))
    }
}

/// 按歌的 id 算的随机数（FNV-1a 做种子，SplitMix64 出数），同一首歌每次摆得一样
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        state = h
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
