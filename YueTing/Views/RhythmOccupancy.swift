import CoreGraphics
import Foundation

/// 摆放防穿模用：墙上已经被占住的地方，记成一个个圆（屏幕点），按格子分桶查得快。
/// 卡片、字、支架、架子是实心的；小球走过的路线也记下来，后面摆的东西不能挡在上面。
/// 小球贴着的那张卡片、那段架子不算（skip）
struct RhythmOccupancy {
    struct Disc {
        var x: CGFloat, y: CGFloat, r: CGFloat
        /// 是哪个东西的；小球走过的地方是 -1
        var id: Int
        /// 小球这时贴着的东西，碰到不算
        var skip: (Int, Int) = (-2, -2)
        var ball: Bool { id == -1 }
    }

    private var cells: [Int64: [Disc]] = [:]
    private static let cell: CGFloat = 48

    private static func key(_ i: Int, _ j: Int) -> Int64 {
        Int64(i) << 32 | Int64(UInt32(bitPattern: Int32(j)))
    }

    mutating func add(_ discs: [Disc]) {
        for d in discs {
            cells[Self.key(Int(floor(d.x / Self.cell)), Int(floor(d.y / Self.cell))), default: []].append(d)
        }
    }

    /// 和已经占住的地方有没有重叠：小球和小球不算，小球和它贴着的东西不算
    func hits(_ discs: [Disc]) -> Bool {
        for d in discs {
            let i = Int(floor(d.x / Self.cell)), j = Int(floor(d.y / Self.cell))
            for di in -1...1 {
                for dj in -1...1 {
                    for e in cells[Self.key(i + di, j + dj)] ?? [] {
                        if d.ball && e.ball {
                            continue
                        }
                        if d.ball && (e.id == d.skip.0 || e.id == d.skip.1) {
                            continue
                        }
                        if e.ball && (d.id == e.skip.0 || d.id == e.skip.1) {
                            continue
                        }
                        if hypot(d.x - e.x, d.y - e.y) < d.r + e.r {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
}

extension RhythmStage {
    /// 小球占的圆比球小一圈，擦边不算
    static let ballDisc: CGFloat = ballRadius * 0.8

    /// 一张卡片占的地方：卡片本身（两边多留一点，别的组的卡片不会贴上来）、底下的两点支架、上面的字
    static func discs(card t: Tile, id i: Int) -> [RhythmOccupancy.Disc] {
        var d = [-14, 0, 14].map { RhythmOccupancy.Disc(x: t.x + $0, y: t.y + 2, r: 10, id: i) }
        d += [RhythmOccupancy.Disc(x: t.x, y: t.y + 14, r: 6, id: i), RhythmOccupancy.Disc(x: t.x, y: t.y + 24, r: 6, id: i)]
        if !t.text.isEmpty {
            d.append(RhythmOccupancy.Disc(x: t.x, y: t.y - 24, r: 13, id: i))
        }
        return d
    }

    /// 一段架子占的地方：轨道或木板，加上底下的柱子；管子按管壁算
    static func discs(track k: Track, id: Int) -> [RhythmOccupancy.Disc] {
        samples(k.path, step: 8).flatMap { p -> [RhythmOccupancy.Disc] in
            switch k.kind {
            case .rail: return [.init(x: p.x, y: p.y + 2, r: 4, id: id), .init(x: p.x, y: p.y + 13, r: 5, id: id)]
            case .plank: return [.init(x: p.x, y: p.y + 4, r: 6, id: id)]
            case .tube: return [.init(x: p.x, y: p.y - ballRadius, r: ballRadius + 9, id: id)]
            }
        } + (k.kind == .plank ? [k.path[0], k.path[k.path.count - 1]].map { .init(x: $0.x, y: $0.y + 4, r: 14, id: id) } : [])
    }

    /// 小球沿着 path（球底的接触点）走过的地方
    static func discs(ball path: [Point3], skip: (Int, Int)) -> [RhythmOccupancy.Disc] {
        samples(path, step: 8).map { .init(x: $0.x, y: $0.y - ballRadius, r: ballDisc, id: -1, skip: skip) }
    }

    /// 从 a 抛物线跳到 b 时小球底部走过的点
    static func arc(_ a: Point3, _ b: Point3, height h: CGFloat) -> [Point3] {
        (0...16).map { j in
            let u = CGFloat(j) / 16
            return Point3(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u - h * 4 * u * (1 - u), z: a.z)
        }
    }

    /// 折线上大约每 step 点取一个点
    private static func samples(_ path: [Point3], step: CGFloat) -> [Point3] {
        guard var last = path.first else { return [] }
        var out = [last]
        for p in path.dropFirst() {
            let d = hypot(p.x - last.x, p.y - last.y)
            let n = Int(ceil(d / step))
            guard n > 0 else { continue }
            for j in 1...n {
                let u = CGFloat(j) / CGFloat(n)
                out.append(Point3(x: last.x + (p.x - last.x) * u, y: last.y + (p.y - last.y) * u, z: p.z))
            }
            last = p
        }
        return out
    }
}
