import AVKit
import CoreText
import os
import UIKit

/// 桌面歌词：iOS 不让 App 在桌面上浮窗口，能浮在桌面和别的 App 上面的只有画中画。
/// 这里把歌词画成一帧帧图像送进 AVSampleBufferDisplayLayer，再用它开画中画，小窗可以拖动、收到屏幕边上。
/// 画面做成 14:1 的细长条，系统按画面比例定小窗形状，小窗就是一根矮矮的横条，只放正在唱的那一句。
/// 小窗上只留关闭按钮：播放 / 暂停、快进快退和「直播」标记用苹果没公开的 controlsStyle 去掉（系统没有这个属性时就保持默认）。
/// 开关打开后不马上弹小窗：App 退到后台时系统自动把小窗开起来，回到 App 时收掉。
/// 承载画面的 hostView 要挂在窗口里（RootView 背景里一小块，被界面盖住看不见），不然系统不让开画中画
@MainActor
final class DesktopLyrics: NSObject {
    struct Frame: Equatable {
        /// 正在唱的那句；还没开唱时是「歌名 · 歌手」
        var text: String
        /// 唱到第几个字（UTF-16 计数，可以带小数），唱过的字填亮色
        var progress: Double
    }

    static var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// 和画面一样 14:1，小窗从这里弹出来时不变形
    let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 20))
    var isPlaying: () -> Bool = { false }
    var onStop: () -> Void = {}

    private let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?
    private var last: Frame?
    /// 系统随时会问小窗现在是不是暂停（不一定在主线程），存一份
    private nonisolated let paused = OSAllocatedUnfairLock(initialState: true)
    /// 小窗画面的像素尺寸，14:1
    private static let size = CGSize(width: 1400, height: 100)

    override init() {
        super.init()
        hostView.isUserInteractionEnabled = false
        layer.frame = hostView.bounds
        layer.videoGravity = .resizeAspect
        hostView.layer.addSublayer(layer)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(Self.size.width),
            kCVPixelBufferHeightKey as String: Int(Self.size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        render(Frame(text: "小狗音乐", progress: 4))
        guard Self.supported else { return }
        let c = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
        c.delegate = self
        c.requiresLinearPlayback = true
        // 1：只留关闭和回到 App，不要播放控件和左下角的「直播」
        if c.responds(to: NSSelectorFromString("setControlsStyle:")) {
            c.setValue(1, forKey: "controlsStyle")
        }
        controller = c
    }

    /// 退到后台时自动开小窗
    var automatic: Bool {
        get { controller?.canStartPictureInPictureAutomaticallyFromInline ?? false }
        set { controller?.canStartPictureInPictureAutomaticallyFromInline = newValue }
    }

    /// 小窗正浮着
    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    func stop() {
        if isActive {
            controller?.stopPictureInPicture()
        }
    }

    /// 播放状态变了，让小窗上的播放 / 暂停按钮跟着变
    func invalidate() {
        let p = !isPlaying()
        paused.withLock { $0 = p }
        controller?.invalidatePlaybackState()
    }

    /// 画一帧送进小窗；和上一帧一样时不画
    func render(_ frame: Frame) {
        guard frame != last, let pool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let drawn = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(Self.size.width), height: Int(Self.size.height),
                              bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            .map { Self.paint(frame, in: $0); return true } ?? false
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard drawn else { return }
        last = frame
        enqueue(buffer)
    }

    private func enqueue(_ buffer: CVPixelBuffer) {
        if format == nil || !CMVideoFormatDescriptionMatchesImageBuffer(format!, imageBuffer: buffer) {
            format = nil
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        }
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sample)
    }
}

extension DesktopLyrics {
    /// 深色底，一行字居中：唱过的字白色带一点光晕，没唱到的半透明
    private static func paint(_ f: Frame, in ctx: CGContext) {
        let W = size.width, H = size.height
        ctx.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // CGContext 的原点在左下角，y 朝上
        let line = fitted(f.text, size: H * 0.55, weight: .semibold, width: W - H * 0.6)
        let x = draw(line, centerY: H / 2, width: W, color: UIColor(white: 1, alpha: 0.4), in: ctx)
        let lit = litWidth(line, progress: f.progress)
        guard lit > 0 else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x, y: 0, width: lit, height: H))
        ctx.setShadow(offset: .zero, blur: 6, color: UIColor(white: 1, alpha: 0.45).cgColor)
        _ = draw(line, centerY: H / 2, width: W, color: .white, in: ctx)
        ctx.restoreGState()
    }

    /// 一行字排不下时先缩小字号（最小到 0.65 倍），还排不下就在末尾截成省略号
    private static func fitted(_ s: String, size: CGFloat, weight: UIFont.Weight, width: CGFloat) -> CTLine {
        func make(_ pt: CGFloat) -> CTLine {
            let font = UIFont.systemFont(ofSize: pt, weight: weight)
            let a = NSAttributedString(string: s, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])
            return CTLineCreateWithAttributedString(a)
        }
        let full = make(size), w = CTLineGetTypographicBounds(full, nil, nil, nil)
        guard w > width else { return full }
        let line = make(max(size * width / w, size * 0.65))
        guard CTLineGetTypographicBounds(line, nil, nil, nil) > width else { return line }
        let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
            .font: UIFont.systemFont(ofSize: size * 0.65, weight: weight),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]))
        return CTLineCreateTruncatedLine(line, width, .end, dots) ?? line
    }

    /// 水平居中画一行，返回这行左边的 x
    private static func draw(_ line: CTLine, centerY: CGFloat, width: CGFloat, color: UIColor, in ctx: CGContext) -> CGFloat {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let w = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let x = (width - w) / 2
        ctx.setFillColor(color.cgColor)
        ctx.textPosition = CGPoint(x: x, y: centerY - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        return x
    }

    /// 唱到第 progress 个字时，从这行左边算起亮到哪
    private static func litWidth(_ line: CTLine, progress p: Double) -> CGFloat {
        guard p > 0 else { return 0 }
        let i = Int(p.rounded(.down)), frac = CGFloat(p - Double(i))
        let x0 = CTLineGetOffsetForStringIndex(line, i, nil), x1 = CTLineGetOffsetForStringIndex(line, i + 1, nil)
        return x0 + max(x1 - x0, 0) * frac
    }
}

extension DesktopLyrics: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onStop() } }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onStop() } }
    }

    /// 点小窗上的「回到 App」：小窗关掉，桌面歌词也就关了
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}

extension DesktopLyrics: AVPictureInPictureSampleBufferPlaybackDelegate {
    /// 小窗上没有播放 / 暂停按钮，系统只会在点关闭时叫一声「暂停」（照着看视频的习惯）。
    /// 歌词条关了不该停歌，这里什么都不做
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {
    }

    /// 无限长的时间范围：系统当成直播，小窗上没有进度条
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool {
        paused.withLock { $0 }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
