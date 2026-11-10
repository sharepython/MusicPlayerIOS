import SceneKit
import SwiftUI

/// 把 RhythmScene 放进 SwiftUI。场景只在歌词、尺寸或主题变了时重建，每一帧按播放时间更新
struct RhythmSceneView: UIViewRepresentable {
    let stage: RhythmStage
    let theme: RhythmTheme
    /// 歌、歌词、宽度、时长、主题都没变时 key 不变，不重建场景
    let key: String
    let player: PlayerController
    /// 这首歌的歌词微调：正数是歌词提前，场景按「播放时间 + offset」走，调的时候不用重建
    var offset = 0.0

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    /// 60 帧、按 2 倍屏画、2 倍抗锯齿；暂停时不推进场景时间，画面不变就不重画。
    /// 视图是透明的，上下边缘由 RhythmFade 淡出，露出播放页背景。
    /// 不接收触摸：它铺在播放页控件下面当背景，接了触摸会把底部按钮的点击吞掉
    func makeUIView(context: Context) -> SCNView {
        let view = QuietSCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.contentScaleFactor = 2
        view.rendersContinuously = false
        view.isPlaying = player.isPlaying
        view.delegate = context.coordinator.driver
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.offset = offset
        context.coordinator.load(stage, theme: theme, key: key)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// 场景每帧的更新在 RhythmDriver 里跟着 SceneKit 渲染走；这里的 CADisplayLink 只负责把播放器时间、
    /// 播放状态和画面尺寸同步过去
    @MainActor final class Coordinator: NSObject {
        let player: PlayerController
        weak var view: SCNView?
        let driver = RhythmDriver()
        private var scene: RhythmScene?
        private var key = ""
        private var link: CADisplayLink?
        var offset = 0.0

        init(player: PlayerController) {
            self.player = player
        }

        /// 第一次直接换上。之后（换歌、歌词到了、换主题）先在后台把新场景的几何和贴图传到显卡，好了再换，
        /// 中间旧画面一直在：直接换的话新场景头几帧还没传完、画不出来，透明的视图会露出底下纯色的播放页背景
        func load(_ stage: RhythmStage, theme: RhythmTheme, key: String) {
            guard key != self.key || scene == nil else { return }
            self.key = key
            let s = RhythmScene(stage: stage, theme: theme)
            if let view, view.bounds.width > 0 {
                s.setAspect(view.bounds.height / view.bounds.width)
            }
            guard let view, scene != nil else { show(s); return }
            driver.hold()
            view.prepare([s.scene, s.kittyNode, s.kittyShelf]) { [weak self] _ in
                Task { @MainActor in
                    // 准备期间又换了（连按下一首），这个就不要了
                    guard let self, self.key == key else { return }
                    self.show(s)
                }
            }
        }

        private func show(_ s: RhythmScene) {
            scene = s
            if let view, view.bounds.width > 0 {
                s.setAspect(view.bounds.height / view.bounds.width)
            }
            driver.set(s, at: now)
            view?.scene = s.scene
            view?.pointOfView = s.cameraNode
            // 小猫和它的家一开始藏着，先在后台把几何和贴图传到显卡，露出来那一帧不卡
            view?.prepare([s.kittyNode, s.kittyShelf]) { _ in }
        }

        func start() {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick() {
            guard let view else { return }
            if view.bounds.width > 0 {
                driver.setAspect(view.bounds.height / view.bounds.width)
            }
            driver.sync(now, playing: player.isPlaying)
            if view.isPlaying != player.isPlaying {
                view.isPlaying = player.isPlaying
            }
        }

        /// position 每秒只更新 4 次，播放时直接读播放器的时间
        private var now: Double {
            let t = player.player.currentTime().seconds
            return (player.isPlaying && t.isFinite ? t : player.position) + offset
        }
    }
}

/// SceneKit 会把场景里每个节点都暴露成无障碍元素（几千个），读屏和 UI 测试每次都要遍历。
/// 整块画面由 RhythmView 当成一个元素，这里一个子元素都不报
private final class QuietSCNView: SCNView {
    override var accessibilityElements: [Any]? { get { [] } set {} }
    override func accessibilityElementCount() -> Int {
        0
    }
}
