import CoreGraphics
import Darwin

/// 三维空间里的一个点，单位是屏幕点：x 往右，y 沿着墙往下，z 从墙面往外（朝着人）
struct Point3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
}

/// 卡片的尺寸、小球的运动和镜头的位置
extension RhythmStage {
    /// 卡片是一块方的亚克力板，平着伸出墙
    static let keyLength: CGFloat = 34
    static let keyWidth: CGFloat = 34
    static let keyThick: CGFloat = 5
    /// 卡片后端离墙多远，中间露出两根铁丝支架；离得远一点看得出东西都是架在墙前面的
    static let keyGap: CGFloat = 30
    static let ballRadius: CGFloat = 18
    /// 架子离墙多远（小球走的那条线），和卡片中间一样远
    static let trackZ: CGFloat = keyGap + keyLength / 2

    struct Ball {
        /// 落脚的地方（球底贴着的点）
        var ground: Point3
        var lift: CGFloat
        /// 刚踩过第几张卡片，还没踩第一张时为 nil
        var hit: Int?
    }

    /// 镜头在哪、看着哪
    struct CameraPose {
        var eye: Point3
        var target: Point3
    }

    func yaw(_ i: Int) -> CGFloat {
        tiles[i].yaw
    }

    /// 卡片上的一点：along 从后端（靠墙）0 到前端 keyLength，across 从左到右，down 从顶面往下
    func point(_ i: Int, along l: CGFloat, across a: CGFloat = 0, down h: CGFloat = 0) -> Point3 {
        let yaw = yaw(i), m = l - Self.keyLength / 2
        return Point3(x: tiles[i].x + a * cos(yaw) + m * sin(yaw),
                  y: tiles[i].y + h,
                  z: Self.keyGap + Self.keyLength / 2 + m * cos(yaw) - a * sin(yaw))
    }

    /// 小球落在卡片正中
    func landing(_ i: Int) -> Point3 {
        point(i, along: Self.keyLength / 2)
    }

    /// 最后一张落脚时间不晚于 t 的卡片
    func lastHit(_ t: Double) -> Int? {
        var lo = 0, hi = tiles.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if tiles[mid].time <= t {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    /// 小球一直在往下走：同一组两个字之间抛物线跳过去，隔得越久跳得越高（按重力算，封顶）；
    /// 换组时掉到后面那段架子上滚过去，间隔长时在一块长木板上一直往前慢慢滚，从出口顺着原来的方向飞到下一组第一张卡片上。
    /// 前奏时在小狗面前的搁板上一下下蹦，到时候被小狗顶出去；唱完从最后一张卡片弹到小猫的搁板上，陪小猫玩
    func ball(at t: Double) -> Ball {
        guard !tiles.isEmpty else { return Ball(ground: Point3(x: 0, y: 0, z: 0), lift: 0, hit: nil) }
        guard let k = lastHit(t) else { return play(t) }
        let a = landing(k), r = tiles[k].row
        if k + 1 < rows[r].tiles.upperBound {
            let gap = tiles[k + 1].time - tiles[k].time
            let u = CGFloat(min(max((t - tiles[k].time) / max(gap, 0.01), 0), 1))
            return Self.leap(a, landing(k + 1), u, height: Self.hopHeight(gap), hit: k)
        }
        guard k + 1 < tiles.count else { return caught(t, from: a, hit: k) }
        return ride(tracks[r], from: a, to: landing(k + 1), t, tiles[k].time, tiles[k + 1].time, hit: k)
    }

    /// 飞 T 秒的抛物线有多高：按每秒² 1600 点的重力算。这样飞的弧线起落的方向都和真的抛出去一样
    static func ballistic(_ T: Double) -> CGFloat {
        200 * CGFloat(T * T)
    }

    /// 同一组两个字之间跳多高：按重力算，最矮 12、最高 90
    static func hopHeight(_ T: Double) -> CGFloat {
        min(max(ballistic(T), 12), 90)
    }
    /// 前奏时小球在搁板上蹦一下多久；小狗顶出去后飞多久落到第一张卡片上
    static let dribble = 0.5
    static let throwFlight = 0.7
    /// 球停在小猫面前时离它多远；小猫一爪子把球拍出去多远；球落在门外台子上时离拍出去最远的地方还有多远；拍一回多久
    static let catPaw: CGFloat = 46
    static let catReach: CGFloat = 34
    static let catPorch: CGFloat = 56
    static let catLoop = 2.6

    /// 前奏：小球在小狗面前的搁板上一下下蹦（每下正好在 throwAt 前后落地），throwAt 时被顶出去，按重力飞到第一张卡片上
    private func play(_ t: Double) -> Ball {
        if t >= throwAt {
            let f = max(tiles[0].time - throwAt, 0.01)
            return Self.leap(toy, landing(0), CGFloat((t - throwAt) / f), height: Self.ballistic(f), hit: nil)
        }
        let u = (t - throwAt) / Self.dribble, q = CGFloat(u - floor(u))
        return Ball(ground: toy, lift: Self.ballistic(Self.dribble) * 4 * q * (1 - q), hit: nil)
    }

    /// t0 时从 a 弹起来掉到第一段架子上，每段按它的 arrive、leave 滚过去，t1 时从最后一段飞到 b。都按重力飞
    private func ride(_ ks: [Track], from a: Point3, to b: Point3, _ t: Double, _ t0: Double, _ t1: Double, hit: Int?) -> Ball {
        func fly(_ p: Point3, _ q: Point3, _ from: Double, _ to: Double) -> Ball {
            Self.leap(p, q, CGFloat((t - from) / max(to - from, 0.01)), height: Self.ballistic(to - from), hit: hit)
        }
        guard let f = ks.first, let l = ks.last else { return fly(a, b, t0, t1) }
        if t < f.arrive {
            return fly(a, f.at(0), t0, f.arrive)
        }
        for j in ks.indices {
            let k = ks[j]
            if t < k.leave {
                return Ball(ground: k.at(Self.roll(k.kind, CGFloat((t - k.arrive) / max(k.leave - k.arrive, 0.01)))), lift: 0, hit: hit)
            }
            if j + 1 < ks.count, t < ks[j + 1].arrive {
                return fly(k.at(1), ks[j + 1].at(0), k.leave, ks[j + 1].arrive)
            }
        }
        return fly(l.at(1), b, l.leave, t1)
    }

    /// 唱完了：最后一张卡片把球弹到小猫家门外的台子上，顺势滚进门、滚到它爪子前面，之后陪小猫玩（kittyToy）
    private func caught(_ t: Double, from a: Point3, hit: Int) -> Ball {
        if t < catchAt {
            let f = max(catchAt - tiles[hit].time, 0.01)
            return Self.leap(a, kittyLanding, CGFloat((t - tiles[hit].time) / f), height: Self.ballistic(f), hit: hit)
        }
        let (d, lift) = kittyToy(t)
        return Ball(ground: Point3(x: kittyPaw.x + kittyDir * d, y: kitty.y, z: Self.trackZ), lift: lift, hit: hit)
    }

    /// 小猫玩球一回 catLoop 秒：一爪子把球拍出去，球越滚越慢、又滚回来，在爪子前面停一会；
    /// 每三回里有一回两只爪子把球往上捞，球蹦两下落回爪子前面。n 是第几回、u 是这一回里的秒数，
    /// 球落到搁板上时正好在第 0 回往回滚的那一半
    func kittyPhase(_ t: Double) -> (n: Int, u: Double) {
        let w = t - catchAt + 1, n = Int(floor(w / Self.catLoop))
        return (n, w - Double(n) * Self.catLoop)
    }

    static func kittyScoops(_ n: Int) -> Bool {
        n % 3 == 2
    }

    /// 球离小猫爪子前面多远、离搁板多高
    func kittyToy(_ t: Double) -> (d: CGFloat, lift: CGFloat) {
        let (n, u) = kittyPhase(t), D = Self.catReach
        if Self.kittyScoops(n) {
            if u < 0.6 {
                let q = CGFloat(u / 0.6)
                return (0, Self.ballistic(0.6) * 4 * q * (1 - q))
            }
            if u < 1 {
                let q = CGFloat((u - 0.6) / 0.4)
                return (0, Self.ballistic(0.4) * 4 * q * (1 - q))
            }
            return (0, 0)
        }
        if u < 1 {
            let q = CGFloat(u)
            return (D * (1 - (1 - q) * (1 - q)), 0)
        }
        // 第 0 回是球从门外滚进来
        if u < 2 {
            let q = CGFloat(u - 1)
            return ((n == 0 ? D + Self.catPorch : D) * (1 - q * q), 0)
        }
        return (0, 0)
    }

    /// 沿着架子从入口 0 走到出口 1，p 从 0 到 1：木板几乎是平的，差不多匀速滚过去；轨道和管子越滚越快
    private static func roll(_ kind: Track.Kind, _ p: CGFloat) -> CGFloat {
        let q = min(max(p, 0), 1)
        return kind == .plank ? q * (0.85 + 0.15 * q) : q * (0.55 + 0.45 * q)
    }

    /// 从 a 抛物线跳到 b，u 从 0 到 1
    private static func leap(_ a: Point3, _ b: Point3, _ u: CGFloat, height: CGFloat, hit: Int?) -> Ball {
        let u = min(max(u, 0), 1)
        return Ball(ground: Point3(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, z: a.z + (b.z - a.z) * u),
                    lift: height * 4 * u * (1 - u), hit: hit)
    }
}

extension RhythmStage {
    /// 卡片左右的倾斜（弧度，往右下斜为正）。按小球落下来和弹出去的方向算：顶面的法线在两个方向正中，
    /// 像真的从斜面上弹开。所以组头的卡片斜着把球弹向组里，组尾的斜着把球送到后面的架子上
    func tilt(_ i: Int) -> CGFloat {
        let p = landing(i), row = tiles[i].row
        // 抛物线落地时的方向是 (dx, dy + 4h)，起跳时是 (dx, dy - 4h)，和跳多久无关（y 往下为正）
        let from: Point3, rise: CGFloat
        if i > rows[row].tiles.lowerBound {
            from = landing(i - 1); rise = Self.hopHeight(tiles[i].time - tiles[i - 1].time)
        } else if row > 0, let k = tracks[row - 1].last {
            from = k.at(1); rise = Self.ballistic(tiles[i].time - k.leave)
        } else if row == 0 {
            from = toy; rise = Self.ballistic(tiles[i].time - throwAt)
        } else {
            from = Point3(x: p.x, y: p.y - 70, z: p.z); rise = 0
        }
        let to: Point3, lift: CGFloat
        if i + 1 < rows[row].tiles.upperBound {
            to = landing(i + 1); lift = Self.hopHeight(tiles[i + 1].time - tiles[i].time)
        } else if i + 1 == tiles.count {
            to = kittyLanding; lift = Self.ballistic(catchAt - tiles[i].time)
        } else {
            let k = tracks[row].first
            to = k?.at(0) ?? Point3(x: p.x, y: p.y + 70, z: p.z); lift = k.map { Self.ballistic($0.arrive - tiles[i].time) } ?? 0
        }

        func unit(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat) {
            let l = max(hypot(x, y), 1e-6)
            return (x / l, y / l)
        }
        let a = unit(p.x - from.x, p.y - from.y + 4 * rise), b = unit(to.x - p.x, to.y - p.y - 4 * lift)
        let n = (b.0 - a.0, b.1 - a.1)
        guard hypot(n.0, n.1) > 1e-3 else { return 0 }
        return min(max(atan2(n.0, -n.1), -Self.maxTilt), Self.maxTilt)
    }

    /// 卡片最多斜多少，太斜了看着要掉
    static let maxTilt: CGFloat = 0.45

    /// 镜头离墙多远
    static let eyeDistance: CGFloat = 560
    /// 视线比小球的落脚点低多少
    static let cameraLead: CGFloat = 20
    /// 前奏刚开始时镜头比小狗高多少，让墙顶上的歌名落在画面中上部
    static let introLift: CGFloat = 285
    /// 镜头左右跟多少：全跟的话小球一拐弯画面就甩，只跟七成，小球在画面里也会左右走
    static let follow: CGFloat = 0.7

    /// 镜头正对着墙，跟着小球走过的路线左右、往下移（marks 按时间连成折线），
    /// 再用前后 2 秒的三角窗加权平均磨掉拐弯处的突变。不直接跟小球，
    /// 否则小球蹦一下、在架子上来回荡时镜头都会跟着一顿一冲
    func camera(at t: Double) -> CameraPose {
        let n = 16, span = 2.0
        var x: CGFloat = 0, y: CGFloat = 0, weight: CGFloat = 0
        for i in -n...n {
            let w = CGFloat(n + 1 - abs(i)), p = mark(t + span * Double(i) / Double(n))
            x += w * p.0
            y += w * p.1
            weight += w
        }
        let eye = Point3(x: width / 2 + Self.follow * (x / weight - width / 2), y: y / weight + Self.cameraLead, z: Self.eyeDistance)
        return CameraPose(eye: eye, target: Point3(x: eye.x, y: eye.y, z: 0))
    }

    /// t 时刻镜头跟着的点，在相邻两个 mark 之间按时间线性过渡
    private func mark(_ t: Double) -> (CGFloat, CGFloat) {
        guard let f = marks.first, let l = marks.last else { return (width / 2, 0) }
        if t <= f.t {
            return (f.x, f.y)
        }
        if t >= l.t {
            return (l.x, l.y)
        }
        var lo = 0, hi = marks.count - 1
        while lo + 1 < hi {
            let m = (lo + hi) / 2
            if marks[m].t <= t {
                lo = m
            } else {
                hi = m
            }
        }
        let a = marks[lo], b = marks[hi]
        let u = b.t > a.t ? CGFloat((t - a.t) / (b.t - a.t)) : 1
        return (a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
    }
}
