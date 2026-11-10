import Metal
import SceneKit

/// 律动画面上下边缘淡出：SceneKit 画完一帧后再画一个全屏三角形，用混合把目标颜色乘上淡出系数。
/// 代替 SwiftUI 的 .mask（那个每帧都要系统离屏合成整块区域）。
/// 着色器写在字符串里，运行时编译一次，不依赖构建机上的 Metal 工具链
final class RhythmFade: NSObject, SCNSceneRendererDelegate {
    /// 上、下各多少比例的高度内淡出：底部留给进度条和控件，淡得多一些
    static let edge = SIMD2<Float>(0.05, 0.12)

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float y; };
    vertex V rhythm_fade_vertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2) * 2.0 - 1.0;
        V v; v.position = float4(p, 0, 1); v.y = p.y * 0.5 + 0.5; return v;
    }
    fragment half4 rhythm_fade_fragment(V v [[stage_in]], constant float2 &edge [[buffer(0)]]) {
        return half4(half(min(saturate((1.0 - v.y) / edge.x), saturate(v.y / edge.y))));
    }
    """

    private var pipeline: MTLRenderPipelineState?
    private var depth: MTLDepthStencilState?
    /// 渲染目标的格式变了（比如换了抗锯齿设置）才重建管线
    private var formats: [Int] = []
    private var failed = false

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard !failed, let encoder = renderer.currentRenderCommandEncoder,
              let color = renderer.currentRenderPassDescriptor.colorAttachments[0].texture else { return }
        let pass = renderer.currentRenderPassDescriptor
        let depthFormat = pass.depthAttachment.texture?.pixelFormat ?? .invalid
        let stencilFormat = pass.stencilAttachment.texture?.pixelFormat ?? .invalid
        let key = [Int(color.pixelFormat.rawValue), Int(depthFormat.rawValue), Int(stencilFormat.rawValue), color.sampleCount]
        if key != formats || pipeline == nil {
            formats = key
            build(device: color.device, color: color.pixelFormat, depth: depthFormat, stencil: stencilFormat, samples: color.sampleCount)
        }
        guard let pipeline else { return }
        var edge = Self.edge
        encoder.pushDebugGroup("RhythmFade")
        encoder.setRenderPipelineState(pipeline)
        if let depth {
            encoder.setDepthStencilState(depth)
        }
        encoder.setCullMode(.none)
        encoder.setFragmentBytes(&edge, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.popDebugGroup()
    }

    /// 混合：目标 × 源（源是淡出系数），颜色和透明度一起乘，透明视图下边缘就露出背后的播放页
    private func build(device: MTLDevice, color: MTLPixelFormat, depth depthFormat: MTLPixelFormat,
                       stencil: MTLPixelFormat, samples: Int) {
        do {
            let library = try device.makeLibrary(source: Self.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "rhythm_fade_vertex")
            d.fragmentFunction = library.makeFunction(name: "rhythm_fade_fragment")
            d.rasterSampleCount = samples
            d.depthAttachmentPixelFormat = depthFormat
            d.stencilAttachmentPixelFormat = stencil
            let c = d.colorAttachments[0]!
            c.pixelFormat = color
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add
            c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .zero
            c.sourceAlphaBlendFactor = .zero
            c.destinationRGBBlendFactor = .sourceAlpha
            c.destinationAlphaBlendFactor = .sourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: d)
            let s = MTLDepthStencilDescriptor()
            s.depthCompareFunction = .always
            s.isDepthWriteEnabled = false
            depth = depthFormat == .invalid && stencil == .invalid ? nil : device.makeDepthStencilState(descriptor: s)
        } catch {
            failed = true
            print("[RhythmFade] 着色器编译失败：\(error)")
        }
    }
}
