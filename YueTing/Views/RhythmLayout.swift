import CoreGraphics
import Foundation

/// 摆放：一句一组卡片，组和组之间接一段架子。每首歌先随机定下偏爱哪几种摆法和架子，再一组组往下摆，
/// 左右来回拐，可以超出屏幕两边，镜头跟着移。小球的走向按物理来：从架子上滚出去、蹦下去都顺着原来的方向往前，
/// 只有落到斜着的卡片上才能弹回头，所以掉头只发生在一组的第一张卡片上。
/// 每放一样东西都查一遍有没有和前面的东西、小球走过的路线重叠，重叠先换另一边，再往下挪（挪得有限，免得落差太大），
/// 小球不会穿过卡片和架子
extension RhythmStage {
    private enum Shape {
        case row, stairs, wave, zigzag
    }

    /// 一段架子的尺寸：往前走多远、往下落多少、中间往下兜多少；前面地方不够时最短缩到 minLen
    private struct Spec {
        var kind: Track.Kind
        var len: CGFloat
        var rise: CGFloat
        var sag: CGFloat = 0
        var minLen: CGFloat = 50
    }

    /// 字的颜色轮流挑：嫩绿、柠檬黄、粉、天蓝、紫
    private static let inkHues: [Double] = [0.36, 0.14, 0.95, 0.57, 0.78]
    /// 两个字隔这么久以上就铺一块长木板，小球在上面一直往前慢慢滚
    static let longGap = 2.4
    /// 一组里平均每个字不到这么久算节奏快，多半摆成左一个右一个
    private static let fast = 0.42

    /// 一组卡片相对第一张的位置（往右排；往左排时 x 取反）：横排略往下斜、斜着往下的台阶、一高一低的波浪、
    /// 左一个右一个往下走的之字形。相邻两张中心至少隔 60 点，卡片和字不挤在一起
    private static func offsets(_ shape: Shape, _ n: Int, _ rng: inout SeededRandom) -> [(CGFloat, CGFloat)] {
        let ks = (0..<n).map { CGFloat($0) }
        switch shape {
        case .row:
            let s = CGFloat.random(in: 62...70, using: &rng)
            return ks.map { (s * $0, 5 * $0) }
        case .stairs:
            let dx = CGFloat.random(in: 56...64, using: &rng), dy = CGFloat.random(in: 34...44, using: &rng)
            return ks.map { (dx * $0, dy * $0) }
        case .wave:
            let s = CGFloat.random(in: 60...66, using: &rng)
            return ks.map { (s * $0, 8 * $0 + (Int($0) % 2 == 1 ? 18 : 0)) }
        case .zigzag:
            let w = CGFloat.random(in: 74...88, using: &rng), dy = CGFloat.random(in: 36...44, using: &rng)
            let drift = CGFloat.random(in: 4...12, using: &rng)
            return ks.map { (drift * $0 + (Int($0) % 2 == 1 ? w : 0), dy * $0) }
        }
    }

    private static func pick<T>(_ items: [(T, Double)], _ rng: inout SeededRandom) -> T {
        var r = Double.random(in: 0..<items.reduce(0) { $0 + $1.1 }, using: &rng)
        for (item, w) in items {
            if r < w {
                return item
            }
            r -= w
        }
        return items[items.count - 1].0
    }

    /// 一块几乎水平的长木板：隔得越久越长，前面放不下就缩短，小球滚得慢一点
    private static func plank(_ gap: Double) -> Spec {
        let len = min(CGFloat(gap) * 80 + 60, 900)
        return Spec(kind: .plank, len: len, rise: len * 0.03, minLen: min(len, 220))
    }

    /// 两个字之间铺哪段架子：唱完了没有架子，这里只是估一下后面要给小猫留多少地方；间隔长是一块长木板；
    /// 不到 0.9 秒是一小截挡板；中间的按这首歌的偏好挑一段双轨、短木板或者弯管。都只往下落一点，不会一下掉半屏
    private static func spec(_ gap: Double, _ kinds: [(Track.Kind, Double)], _ rng: inout SeededRandom) -> Spec {
        if !gap.isFinite {
            return Spec(kind: .rail, len: 230, rise: 20, sag: 70, minLen: 160)
        }
        if gap >= longGap {
            return plank(gap)
        }
        if gap < 0.9 {
            return Spec(kind: .rail, len: .random(in: 50...70, using: &rng), rise: 18, sag: 4)
        }
        switch pick(kinds, &rng) {
        case .rail:
            return Spec(kind: .rail, len: .random(in: 140...210, using: &rng), rise: .random(in: 30...60, using: &rng),
                        sag: .random(in: 10...24, using: &rng), minLen: 90)
        case .plank:
            let len = CGFloat.random(in: 140...200, using: &rng)
            return Spec(kind: .plank, len: len, rise: len * 0.06, minLen: 90)
        case .tube:
            return Spec(kind: .tube, len: .random(in: 80...120, using: &rng), rise: .random(in: 70...100, using: &rng), minLen: 70)
        }
    }

    /// 从 e 开始往 dir 方向的一段架子，取 33 个点。弯管上头是竖着的，小球笔直掉进去，下头斜着朝前出来
    private static func path(_ k: Spec, from e: Point3, dir: CGFloat) -> [Point3] {
        (0...32).map { j in
            let s = CGFloat(j) / 32, u = k.kind == .tube ? s * s : s
            return Point3(x: e.x + dir * k.len * u, y: e.y + k.rise * s + k.sag * sin(.pi * s), z: Self.trackZ)
        }
    }
}

extension RhythmStage {
    private typealias Disc = RhythmOccupancy.Disc

    /// 小球从 a 离开（a 是它最后贴着的东西 skip 上的点），往 dir 方向接一段架子，入口在 a 前方 lead.0、往下 lead.1，
    /// 小球按 drop 那么高的弧掉上去。只往前放、不掉头：前面不够长就缩短，太短就不放；挡住了就往下挪，最多挪 reach。
    /// strict 时挪到头还挡着就不放（好换另一边试），否则用挪到头的那个
    private static func rack(_ spec: Spec, from a: Point3, skip: Int, dir: CGFloat, lead: (CGFloat, CGFloat), drop: CGFloat,
                             bounds: ClosedRange<CGFloat>, reach: CGFloat, strict: Bool,
                             room: inout RhythmOccupancy, id: Int) -> Track? {
        var k = spec
        let x = a.x + dir * lead.0
        let free = dir > 0 ? bounds.upperBound - x : x - bounds.lowerBound
        if free < k.len {
            guard free >= min(k.minLen, 50) else { return nil }
            if k.kind == .plank {
                k.rise *= free / k.len
            }
            k.len = free
        }
        var chosen: (Track, [Disc], [Disc])?
        for extra in stride(from: CGFloat(0), through: reach, by: 25) {
            let p = path(k, from: Point3(x: x, y: a.y + lead.1 + extra, z: trackZ), dir: dir)
            let track = Track(kind: k.kind, path: p, arrive: 0, leave: 0)
            let statics = discs(track: track, id: id)
            let ball = discs(ball: arc(a, p[0], height: drop) + p, skip: (skip, id))
            let clear = !room.hits(statics) && !room.hits(ball)
            if clear || !strict {
                chosen = (track, statics, ball)
            }
            if clear {
                break
            }
        }
        guard let (track, statics, ball) = chosen else { return nil }
        room.add(statics)
        room.add(ball)
        return track
    }

    /// 从架子出口蹦到 b 要飞多久：离开出口时顺着架子末端的方向（往上翘的就往上抛），按重力算正好落在 b 上
    static func exitFlight(_ k: Track, to b: Point3) -> Double {
        let a = k.at(1), c = k.at(0.97), sx = abs(a.x - c.x)
        let slope = sx > 0.5 ? min(max((a.y - c.y) / sx, -1), 3) : 3
        let d = b.y - a.y - slope * abs(b.x - a.x)
        return min(max(sqrt(Double(max(d, 8)) / 800), 0.12), 0.6)
    }

    /// 排一段架子的时间：t0 时小球离开上一样东西，过 drop 秒落到入口，滚到出口，再飞 exitFlight 秒正好 t1 时落到 b 上
    private static func timed(_ k: Track, t0: Double, t1: Double, drop: Double, to b: Point3) -> Track {
        var k = k
        let gap = max(t1 - t0, 0.05)
        k.arrive = t0 + min(drop, gap * 0.25)
        k.leave = max(t1 - min(exitFlight(k, to: b), gap * 0.3), k.arrive + gap * 0.05)
        return k
    }

    /// 一组卡片占的地方，和小球从 e 按 rise 那么高的弧蹦上第一张、再一张张跳过去的路线
    private static func discs(group ts: [Tile], start: Int, from e: Point3, rise: (Point3) -> CGFloat, skip: Int) -> (statics: [Disc], ball: [Disc]) {
        let statics = ts.indices.flatMap { discs(card: ts[$0], id: start + $0) }
        let land = ts.map { Point3(x: $0.x, y: $0.y, z: trackZ) }
        var ball = discs(ball: arc(e, land[0], height: rise(land[0])), skip: (skip, start))
        for k in ts.indices.dropLast() {
            ball += discs(ball: arc(land[k], land[k + 1], height: hopHeight(ts[k + 1].time - ts[k].time)),
                          skip: (start + k, start + k + 1))
        }
        return (statics, ball)
    }

    /// 小狗、小猫的家占的地方：连屋顶在内的一整块
    private static func discs(room r: Room, id: Int) -> [Disc] {
        stride(from: r.top + 10, through: r.floor + 6, by: 20).flatMap { y in
            stride(from: r.x.lowerBound, through: r.x.upperBound, by: 20).map { Disc(x: $0, y: y, r: 13, id: id) }
        }
    }

    /// 小狗的家，加上小球在小狗面前蹦的那一竖条
    private static func discs(pup room: Room, toy: Point3, id: Int) -> (statics: [Disc], ball: [Disc]) {
        let top = Point3(x: toy.x, y: toy.y - ballistic(dribble), z: toy.z)
        return (discs(room: room, id: id), discs(ball: [toy, top], skip: (id, id)))
    }

    /// 唱完后给小猫找个家：在最后一张卡片 a 旁边，敞开的那边朝着 a，小猫在里头脸朝门口。
    /// 球从卡片落到门外的台子上，滚进门、滚到小猫爪子前面。先往 dir 那边找，挡住了换另一边、离远一点、再往下挪；
    /// 都不行就用第一个
    private mutating func nestKitty(from a: Point3, at t0: Double, skip: Int, dir: CGFloat, bounds: ClosedRange<CGFloat>,
                                    room: inout RhythmOccupancy, id: Int) {
        var chosen: (room: Room, k: Point3, flight: Double, statics: [Disc], ball: [Disc])?, first = chosen
        search: for extra in stride(from: CGFloat(0), through: 600, by: 25) {
            for d in [dir, -dir] {
                for gap: CGFloat in [50, 80, 120, 170] {
                    let edge = a.x + d * gap
                    let land = Point3(x: edge - d * 28, y: a.y + 30 + extra, z: Self.trackZ)
                    let paw = Point3(x: land.x + d * (Self.catReach + Self.catPorch), y: land.y, z: Self.trackZ)
                    let k = Point3(x: paw.x + d * Self.catPaw, y: land.y, z: Self.trackZ)
                    let far = edge + d * (Self.catReach + Self.catPorch + Self.catPaw - 28 + Room.furniture - 10)
                    guard bounds.contains(far) else { continue }
                    let flight = min(0.42 + Double(land.y - a.y) / 1000 + Double(gap) / 1500, 0.8)
                    let path = Self.arc(a, land, height: Self.ballistic(flight))
                    let r = Room(x: min(edge, far)...max(edge, far), floor: land.y, height: 125, open: -d)
                    // 球擦着门口落下来，不能碰到二楼那截侧墙和屋檐（球和自己家不算碰，要单独看）
                    let grazes = path.contains { q in
                        let out = (edge - q.x) * d, up = land.y - q.y + 2 * Self.ballRadius
                        return out < Self.ballRadius + 4 && up > r.height || out < Self.ballRadius + 22 && up > r.walls - 10
                    }
                    let statics = Self.discs(room: r, id: id)
                    let up = Point3(x: paw.x, y: paw.y - Self.ballistic(0.6), z: Self.trackZ)
                    let ball = Self.discs(ball: path + [land, paw, up], skip: (skip, id))
                    let c = (r, k, flight, statics, ball)
                    if first == nil {
                        first = c
                    }
                    if !grazes, !room.hits(statics), !room.hits(ball) {
                        chosen = c
                        break search
                    }
                }
            }
        }
        // 两边都出界（屏幕太窄）时贴着卡片下面放
        let fallback = Room(x: a.x - 60...a.x + 200, floor: a.y + 80, height: 125, open: -1)
        let c = chosen ?? first ?? (fallback, Point3(x: a.x + 50, y: a.y + 80, z: Self.trackZ), 0.5, [], [])
        kittyRoom = c.room
        kitty = c.k
        kittyDir = c.room.open
        catchAt = t0 + c.flight
        room.add(c.statics)
        room.add(c.ball)
    }
}

extension RhythmStage {
    /// 一句里两个字隔了 1.6 秒以上（句中停顿）就从这里断开另起一组，停顿时小球在架子上滚过去；太长时平均拆开。
    /// 前奏时一只小狗在歌名下面自己家里玩球，开唱前 throwFlight 秒把球从门口顶出去落到第一张卡片上。然后每组：
    /// 第一张卡片在上一段架子出口的正前下方（小球顺着原来的方向飞过去），整组接着往前排，前面放不下或者随机到了
    /// 就从第一张折回来；节奏快的组多半摆成左一个右一个。组后面那段架子顺着最后两张卡片的方向往前接。
    /// 挡住了先换另一边，再往下挪
    mutating func layout(_ notes: [[(Double, String)]], _ rng: inout SeededRandom) {
        let pieces = notes.flatMap { line -> [[(Double, String)]] in
            var out: [[(Double, String)]] = [[]]
            for n in line {
                if let last = out[out.count - 1].last, n.0 - last.0 > 1.6 {
                    out.append([])
                }
                out[out.count - 1].append(n)
            }
            return out
        }
        let chunks = pieces.flatMap { line -> [[(Double, String)]] in
            let parts = (line.count + Self.perRow - 1) / Self.perRow
            let size = (line.count + parts - 1) / parts
            return stride(from: 0, to: line.count, by: size).map { Array(line[$0..<min($0 + size, line.count)]) }
        }
        guard !chunks.isEmpty else { return }
        // 这首歌偏爱哪几种摆法和架子
        let shapes: [(Shape, Double)] = [(.row, .random(in: 0.6...2, using: &rng)), (.stairs, .random(in: 0.3...1.6, using: &rng)),
                                         (.wave, .random(in: 0.2...1.2, using: &rng))]
        let kinds: [(Track.Kind, Double)] = [(.rail, .random(in: 1...2.5, using: &rng)), (.plank, .random(in: 0.2...1.4, using: &rng)),
                                             (.tube, .random(in: 0.1...1, using: &rng))]
        let flip = Double.random(in: 0.1...0.3, using: &rng)
        var hue = Int.random(in: 0..<Self.inkHues.count, using: &rng)
        let lo = Self.margin - spread + 30, hi = width - Self.margin + spread - 30
        // 架子出口离两边留出一张卡片的地方，出口前面总放得下下一组的第一张
        let rackBounds = lo + 40...hi - 40
        var dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
        var room = RhythmOccupancy(), id = 1_000_000
        let drop = 0.35

        let first = chunks[0][0].0
        introStart = min(0, first - 1.5)
        throwAt = first - Self.throwFlight
        pupDir = dir
        pup = Point3(x: width / 2 + dir * 20, y: -40, z: Self.trackZ)
        let door = pup.x + dir * Room.pupSpot, back = door - dir * (Room.pupSpot + Room.furniture)
        pupRoom = Room(x: min(door, back)...max(door, back), floor: pup.y, height: 125, open: dir)
        let nest = Self.discs(pup: pupRoom, toy: toy, id: id)
        room.add(nest.statics)
        room.add(nest.ball)
        var prev: Track?
        var e = toy
        var prevId = id
        id += 1

        for (r, chunk) in chunks.enumerated() {
            let n = chunk.count
            let pace = n > 1 ? (chunk[n - 1].0 - chunk[0].0) / Double(n - 1) : 1
            let zig = n >= 3 && pace < Self.fast && Double.random(in: 0..<1, using: &rng) < 0.8
            var shape: Shape = n <= 2 ? .row : zig ? .zigzag : Self.pick(shapes, &rng)
            var off = Self.offsets(shape, n, &rng)
            let next = r + 1 < chunks.count ? chunks[r + 1][0].0 : Double.infinity
            let spec = Self.spec(next - chunk[n - 1].0, kinds, &rng)
            // 第一组离搁板远一点、低一点，小狗顶出去的球从搁板边上越过去
            let lead: (CGFloat, CGFloat) = r == 0 ? (90, 110) : (40, 60)
            let base = min(max(e.x + dir * lead.0, lo), hi)
            // 往 d 排的话，排完后面还有多少地方放架子
            func after(_ d: CGFloat, _ w: CGFloat) -> CGFloat {
                let x = base + d * (w + 36)
                return d > 0 ? rackBounds.upperBound - x : x - rackBounds.lowerBound
            }
            let long = spec.kind == .plank && spec.len > 200 || !next.isFinite
            var w = off.map(\.0).max() ?? 0
            let need = long ? spec.len : spec.minLen
            // 第一组只能在小狗家门口那边
            var g = dir
            if r == 0 {
            } else if long {
                // 后面是长木板，往地方大的那边排
                if after(-g, w) > after(g, w) {
                    g = -g
                }
            } else if after(g, w) < need || (after(-g, w) >= need && Double.random(in: 0..<1, using: &rng) < flip) {
                g = -g
            }
            // 两边都排不下时改成左一个右一个，占的宽度小；还不够再把左右挤近一点，相邻两张仍隔开 60 点以上
            if after(g, w) < spec.minLen, n >= 3, shape != .zigzag {
                shape = .zigzag
                off = Self.offsets(shape, n, &rng)
                w = off.map(\.0).max() ?? 0
            }
            let fit = after(g, w) - spec.minLen
            if fit < 0, w > 0 {
                off = off.map { ($0.0 * max(shape == .zigzag ? 0.78 : 0.92, 1 + fit / w), $0.1) }
            }

            let yaw = CGFloat.random(in: -0.15...0.15, using: &rng)
            let yaws = (0..<n).map { _ in yaw + CGFloat.random(in: -0.12...0.12, using: &rng) }
            let start = tiles.count
            let rise: (Point3) -> CGFloat = { b in
                r == 0 ? Self.ballistic(Self.throwFlight) : prev.map { Self.ballistic(Self.exitFlight($0, to: b)) } ?? 24
            }
            var group: [Tile] = [], taken: (statics: [Disc], ball: [Disc]) = ([], [])
            // 挡住了先试另一边（前面有地方的话），都不行再往下挪
            let sides = r > 0 && after(-g, w) >= spec.minLen ? [g, -g] : [g]
            search: for extra in stride(from: CGFloat(0), through: 400, by: 25) {
                for d in sides where extra <= 100 || d == g {
                    group = (0..<n).map { k in
                        Tile(x: base + d * off[k].0, y: e.y + lead.1 + extra + off[k].1, time: chunk[k].0, text: chunk[k].1,
                             hue: Self.inkHues[(hue + k) % Self.inkHues.count], yaw: yaws[k], row: r)
                    }
                    taken = Self.discs(group: group, start: start, from: e, rise: rise, skip: prevId)
                    if !room.hits(taken.statics) && !room.hits(taken.ball) {
                        g = d
                        break search
                    }
                }
            }
            room.add(taken.statics)
            room.add(taken.ball)
            tiles += group
            hue += n

            let last = group[n - 1], a = Point3(x: last.x, y: last.y, z: Self.trackZ)
            // 唱完了接给小猫；不然架子先在两边各试着往下挪一点，都挡着才往下多挪
            var made: Track?
            if !next.isFinite {
                // 小猫的家后面不用再接东西，可以一直摆到最边上
                nestKitty(from: a, at: last.time, skip: tiles.count - 1, dir: g, bounds: lo...hi, room: &room, id: id)
            }
            for (d, reach, strict) in [(g, CGFloat(75), true), (-g, 75, true), (g, 400, false), (-g, 400, false)] where next.isFinite {
                made = Self.rack(spec, from: a, skip: tiles.count - 1, dir: d, lead: (36, 50), drop: Self.ballistic(drop),
                                 bounds: rackBounds, reach: reach, strict: strict, room: &room, id: id)
                if made != nil {
                    dir = d
                    break
                }
            }
            if made != nil {
                id += 1
            }
            tracks.append(made.map { [$0] } ?? [])
            let ys = group.map(\.y) + (made?.path.map(\.y) ?? []) + (next.isFinite ? [] : [kittyRoom.top - 10, kittyRoom.floor + 30])
            rows.append(Row(tiles: start..<tiles.count, start: chunk[0].0, end: last.time, span: ys.min()! - 80...ys.max()! + 50))
            prev = made
            e = made.map { $0.path[$0.path.count - 1] } ?? a
            prevId = made == nil ? tiles.count - 1 : id - 1
        }

        // 卡片都摆好了再排架子上的时间：从架子蹦出去飞多久要看落到哪张卡片上
        for r in rows.indices {
            let i = rows[r].tiles.upperBound
            guard let k = tracks[r].first, i < tiles.count else { continue }
            tracks[r] = [Self.timed(k, t0: tiles[i - 1].time, t1: tiles[i].time, drop: drop, to: landing(i))]
        }
    }
}
