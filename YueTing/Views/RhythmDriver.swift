import QuartzCore
import SceneKit

/// 在 SceneKit 渲染每一帧之前把场景推到这一帧的时间。
/// 以前在主线程另开一个 CADisplayLink 改场景，和 SceneKit 渲染线程的节拍对不齐：
/// 有的帧赶上了、有的帧没赶上，画面就一帧不动、下一帧挪两步，镜头往下移时看着一顿一顿的。
/// 现在主线程只记下「播放器时间 ↔ 系统时间」的对应关系，渲染线程按这一帧的系统时间推算播放时间，
/// 每帧走的距离一样。场景、时钟都用锁保护，主线程和渲染线程都可能碰
final class RhythmDriver: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var scene: RhythmScene?
    /// 播放器时间 media 对应系统时间 host；播放中按 1 倍速往后推
    private var media = 0.0
    private var host = 0.0
    private var playing = false
    private var lastTime = -1.0
    private let fade = RhythmFade()

    func set(_ scene: RhythmScene, at t: Double) {
        lock.lock(); defer { lock.unlock() }
        self.scene = scene
        media = t
        host = CACurrentMediaTime()
        lastTime = t
        scene.update(t)
    }

    /// 新场景还在准备时先停下：画面停在旧场景的这一帧，不再跟着新歌的时间走
    func hold() {
        lock.lock(); defer { lock.unlock() }
        scene = nil
    }

    func setAspect(_ a: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        scene?.setAspect(a)
    }

    /// 主线程每帧报一次播放器时间。拖进度条、暂停、继续播放时直接对齐；
    /// 平时差一点（读时间的早晚误差、刚 seek 完播放器还在追）就每帧悄悄补上一成，画面不会一下跳一截。
    /// 暂停时直接在主线程更新场景（渲染线程这时不跑）
    func sync(_ t: Double, playing now: Bool) {
        lock.lock(); defer { lock.unlock() }
        let clock = CACurrentMediaTime()
        let predicted = playing ? media + (clock - host) : media
        let error = t - predicted
        if now != playing || abs(error) > 0.25 {
            media = t
            host = clock
        } else if abs(error) > 0.01 {
            media += error * 0.1
        }
        playing = now
        if !now, t != lastTime {
            lastTime = t
            scene?.update(t)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        guard playing, let scene else { return }
        let t = media + (time - host)
        guard t != lastTime else { return }
        lastTime = t
        scene.update(t)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        fade.renderer(renderer, didRenderScene: scene, atTime: time)
    }
}
