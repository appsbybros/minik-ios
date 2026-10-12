import Metal
import QuartzCore
import UIKit

/// Android `WorldBlock` (interior cover for the Pro arenas; Splash's three arenas have none).
struct WorldBlock: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let depth: Double
    let height: Double
}

/// Android `ArenaInset`: the close-up camera and its viewport (points, top-left origin).
struct ArenaInset: Equatable {
    let camera: ArenaCamera
    let left: Int
    let top: Int
    let width: Int
    let height: Int
}

/// Android `ArenaFrame`: everything the GPU ground needs for one frame.
struct ArenaFrame: Equatable {
    var camera: ArenaCamera
    var scene: String
    var width: Double
    var depth: Double
    var time: Double
    var night: Float = 0
    var level: Int = 0
    var blocks: [WorldBlock] = []
    var inset: ArenaInset? = nil
}

/// Port of Android world/ArenaWorldView.kt (an OpenGL ES 2 GLSurfaceView): the perspective arena
/// ground under the Core Graphics actors. iOS renders the same three passes with Metal (shader
/// below, compiled at run time from source): the sky gradient, the arena's sky band and the
/// shaded ground plane with its court line, sheen and distance fog, plus the close-up inset.
/// The frame is drawn synchronously when submitted and presented with the Core Animation
/// transaction, so the ground never lags the sprites drawn above it.
@MainActor
final class ArenaWorldView: UIView {
    /// Called once, after the first real frame (Android fades the loading screen then).
    var firstFrame: (() -> Void)?

    private var frame0 = ArenaFrame(camera: ArenaCamera(8.0, 8.0, distance: 34.0), scene: "park", width: 16.0, depth: 16.0, time: 0.0)
    private var renderer: ArenaRenderer?
    private var firstRendered = false

    override class var layerClass: AnyClass { return CAMetalLayer.self }

    private var metalLayer: CAMetalLayer? { return layer as? CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = true
        backgroundColor = UIColor(red: 0.045, green: 0.14, blue: 0.23, alpha: 1)
        isAccessibilityElement = false
        if let metal = metalLayer, let device = MTLCreateSystemDefaultDevice() {
            metal.device = device
            metal.pixelFormat = .bgra8Unorm
            metal.framebufferOnly = true
            metal.isOpaque = true
            metal.presentsWithTransaction = true
            renderer = ArenaRenderer(device: device)
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(traitCollection.displayScale, 1)
        metalLayer?.contentsScale = scale
        metalLayer?.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
    }

    /// Android `submit(frame)`: store the frame and render it now.
    func submit(_ frame: ArenaFrame) {
        frame0 = frame
        render()
    }

    private func render() {
        guard bounds.width > 0, bounds.height > 0, window != nil else { return }
        if let metal = metalLayer, let renderer = renderer, renderer.ready {
            let scale = Double(metal.contentsScale)
            renderer.draw(frame0, layer: metal, scale: scale)
        }
        if !firstRendered {
            firstRendered = true
            let callback = firstFrame
            firstFrame = nil
            callback?()
        }
    }
}

/// The Metal port of Android `ArenaRenderer` (GLES2): same quads, uniforms and shader maths.
@MainActor
private final class ArenaRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var textures: [String: MTLTexture] = [:]
    private var missing = Set<String>()

    var ready: Bool { return pipeline != nil && queue != nil }

    init(device: MTLDevice) {
        self.device = device
        self.queue = device.makeCommandQueue()
        do {
            let library = try device.makeLibrary(source: ArenaRenderer.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "arenaVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "arenaFragment")
            let color = descriptor.colorAttachments[0]
            color?.pixelFormat = .bgra8Unorm
            // GL_BLEND with glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) for colour and alpha.
            color?.isBlendingEnabled = true
            color?.rgbBlendOperation = .add
            color?.alphaBlendOperation = .add
            color?.sourceRGBBlendFactor = .sourceAlpha
            color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color?.sourceAlphaBlendFactor = .sourceAlpha
            color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Minik Splash arena shader failed: %@", String(describing: error))
            pipeline = nil
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Android `texture(name)`: `pro-world/<name>.webp` decoded into a premultiplied RGBA bitmap
    /// (GLUtils.texImage2D), linear filtering, clamped, no mipmaps.
    private func texture(_ name: String) -> MTLTexture? {
        if let cached = textures[name] { return cached }
        if missing.contains(name) { return nil }
        guard let image = UIImage(named: name)?.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            missing.insert(name)
            return nil
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard drawn, let made = device.makeTexture(descriptor: descriptor) else {
            missing.insert(name)
            return nil
        }
        pixels.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                made.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
            }
        }
        textures[name] = made
        return made
    }

    func draw(_ f: ArenaFrame, layer: CAMetalLayer, scale: Double) {
        guard let pipeline = pipeline, let queue = queue, let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.045, green: 0.14, blue: 0.23, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        if let sampler = sampler { encoder.setFragmentSamplerState(sampler, index: 0) }
        let fullW = Double(drawable.texture.width)
        let fullH = Double(drawable.texture.height)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: fullW, height: fullH, znear: 0, zfar: 1))
        renderScene(encoder, f, fullW, fullH)
        if let i = f.inset {
            // Android: scissor and viewport on the inset, then the same scene with the close camera.
            let left = Double(i.left) * scale
            let top = Double(i.top) * scale
            let width = Double(i.width) * scale
            let height = Double(i.height) * scale
            let x0 = max(0, min(Int(left), Int(fullW)))
            let y0 = max(0, min(Int(top), Int(fullH)))
            let x1 = max(x0, min(Int(left + width), Int(fullW)))
            let y1 = max(y0, min(Int(top + height), Int(fullH)))
            if x1 > x0 && y1 > y0 {
                encoder.setScissorRect(MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
                encoder.setViewport(MTLViewport(originX: left, originY: top, width: width, height: height, znear: 0, zfar: 1))
                var close = f
                close.camera = i.camera
                close.inset = nil
                renderScene(encoder, close, width, height)
                encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(fullW), height: Int(fullH)))
            }
        }
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilScheduled()
        drawable.present()
    }

    /// Android `renderScene`: background gradient, sky band, then the shaded ground plane.
    private func renderScene(_ encoder: MTLRenderCommandEncoder, _ f: ArenaFrame, _ w: Double, _ h: Double) {
        let c = f.camera
        let scene: String
        switch f.scene {
        case "beach": scene = "beach"
        case "andromeda": scene = "andromeda"
        default: scene = "park"
        }
        let sceneValue: Float
        switch f.scene {
        case "beach": sceneValue = 1
        case "andromeda": sceneValue = 2
        case "parking": sceneValue = 3
        case "building": sceneValue = 4
        default: sceneValue = 0
        }
        var uniforms: [SIMD4<Float>] = [
            SIMD4<Float>(Float(c.x), Float(c.y), Float(c.distance), Float(c.focusHeight)),
            SIMD4<Float>(Float(sin(c.tilt)), Float(cos(c.tilt)), Float(1 / tan(c.fov * Double.pi / 360)), Float(w / max(h, 1))),
            SIMD4<Float>(Float(cos(c.yaw)), Float(sin(c.yaw)), Float(1 - 2 * c.centerY), 0),
            SIMD4<Float>(sceneValue, Float(f.time.truncatingRemainder(dividingBy: 1000)), f.night, 1),
            SIMD4<Float>(Float(f.width), Float(f.depth), 0, 0)
        ]
        func mode(_ value: Float, _ tex: String?, _ alpha: Float = 1) {
            uniforms[2].w = value
            uniforms[3].w = alpha
            let texture = self.texture(tex ?? "micro") ?? self.texture("micro")
            if let texture = texture { encoder.setFragmentTexture(texture, index: 0) }
        }
        func quad(_ p: [Float], _ u0: Float = 0, _ v0: Float = 0, _ u1: Float = 1, _ v1: Float = 1) {
            // p: x0 y0 z0, x1 y1 z1, x2 y2 z2, x3 y3 z3 (Android `quad` vertex order and UVs).
            var data: [Float] = [p[0], p[1], p[2], u0, v1, p[3], p[4], p[5], u1, v1, p[6], p[7], p[8], u0, v0,
                                 p[6], p[7], p[8], u0, v0, p[3], p[4], p[5], u1, v1, p[9], p[10], p[11], u1, v0]
            encoder.setVertexBytes(&data, length: data.count * MemoryLayout<Float>.stride, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniforms.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: uniforms.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        mode(0, nil)
        quad([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0])
        let skyBottom = Float(1 - 2 * (w / max(h, 1)) / 2.2528)
        mode(1, scene + "_sky")
        quad([-1.06, skyBottom, 0, 1.06, skyBottom, 0, -1.06, 1, 0, 1.06, 1, 0], 0.39, 0, 0.61, 1)
        mode(2, scene == "beach" ? "sand" : "grass")
        let floorZ = Float(Double(f.level) * 3.4 - 0.025)
        quad([-150, 160, floorZ, 150, 160, floorZ, -150, -200, floorZ, 150, -200, floorZ], 0, 0, 60, 60)
        // Android draws building and parking props only for the Pro "building"/"parking" scenes;
        // Splash's beach, park and Andromeda never reach them. Interior cover is composited in
        // depth order with the actors on the foreground canvas.
    }

    /// Android VERT and FRAG (GLSL ES 1.0), translated to the Metal Shading Language. The vertex
    /// depth maps GL clip z (`1.00134*depth-.40027`, range -w..w) to Metal's 0..w range.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct ArenaVaryings {
        float4 position [[position]];
        float2 uv;
        float3 world;
    };

    vertex ArenaVaryings arenaVertex(uint vid [[vertex_id]], constant float *data [[buffer(0)]], constant float4 *u [[buffer(1)]]) {
        float3 pos = float3(data[vid * 5], data[vid * 5 + 1], data[vid * 5 + 2]);
        ArenaVaryings o;
        o.uv = float2(data[vid * 5 + 3], data[vid * 5 + 4]);
        o.world = pos;
        float4 cam = u[0];
        float4 lens = u[1];
        float2 yaw = u[2].xy;
        float center = u[2].z;
        float mode = u[2].w;
        if (mode < 1.5) {
            o.position = float4(pos, 1.0);
            return o;
        }
        float2 delta = pos.xy - cam.xy;
        float rx = yaw.x * delta.x - yaw.y * delta.y;
        float dy = yaw.y * delta.x + yaw.x * delta.y;
        float dz = pos.z - cam.w;
        float depth = cam.z - lens.x * dy - lens.y * dz;
        float yy = -lens.y * dy + lens.x * dz;
        float glz = 1.00134 * depth - 0.40027;
        o.position = float4(rx * lens.z / lens.w, yy * lens.z + center * depth, (glz + depth) * 0.5, depth);
        return o;
    }

    static float arenaHash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    static float arenaNoise(float2 p) {
        float2 a = floor(p);
        float2 b = fract(p);
        b = b * b * (3.0 - 2.0 * b);
        return mix(mix(arenaHash(a), arenaHash(a + float2(1.0, 0.0)), b.x),
                   mix(arenaHash(a + float2(0.0, 1.0)), arenaHash(a + float2(1.0, 1.0)), b.x), b.y);
    }

    fragment float4 arenaFragment(ArenaVaryings in [[stage_in]], constant float4 *u [[buffer(0)]],
                                  texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
        float mode = u[2].w;
        float scene = u[3].x;
        float time = u[3].y;
        float night = u[3].z;
        float alpha = u[3].w;
        float2 bounds = u[4].xy;
        if (mode < 0.5) {
            float3 col = mix(float3(0.05, 0.23, 0.35), float3(0.19, 0.55, 0.72), in.uv.y);
            if (scene > 1.5 && scene < 2.5) {
                col = mix(float3(0.09, 0.04, 0.23), float3(0.34, 0.2, 0.52), in.uv.y);
            }
            return float4(col * (1.0 - night * 0.75), 1.0);
        }
        if (mode < 1.5 || (mode > 2.5 && mode < 3.5)) {
            float4 col = tex.sample(smp, in.uv);
            if (col.a < 0.025) {
                discard_fragment();
            }
            col.rgb *= mix(float3(1.04, 1.02, 1.0), float3(0.40, 0.48, 0.74), night);
            return float4(col.rgb, col.a * alpha);
        }
        if (mode > 3.5) {
            return float4(float3(0.22, 0.55, 0.61) * alpha, 1.0);
        }
        float2 p = in.world.xy;
        float3 material = tex.sample(smp, abs(fract(p * 0.12) * 2.0 - 1.0)).rgb;
        float n = arenaNoise(p * 0.34);
        float3 col = mix(float3(0.18, 0.34, 0.17), material, 0.67) * (0.85 + n * 0.12);
        if (scene > 0.5 && scene < 1.5) {
            col = material * (0.93 + n * 0.13);
        }
        if (scene > 1.5 && scene < 2.5) {
            float grid = max(step(0.975, fract(p.x * 0.32)), step(0.975, fract(p.y * 0.32)));
            col = mix(float3(0.15, 0.10, 0.26), float3(0.27, 0.19, 0.42), n);
            col += float3(0.10, 0.55, 0.62) * grid * 0.44;
        }
        if (scene > 2.5) {
            col = mix(float3(0.13, 0.19, 0.26), float3(0.24, 0.32, 0.38), n * 0.5);
            float stripe = step(0.94, fract(p.x * 0.16)) * step(0.12, fract(p.y * 0.22)) * step(fract(p.y * 0.22), 0.85);
            col += float3(0.70, 0.60, 0.30) * stripe * 0.65;
        }
        float edge = min(min(p.x, bounds.x - p.x), min(p.y, bounds.y - p.y));
        float line = 1.0 - smoothstep(0.02, 0.065, abs(edge - 0.15));
        col = mix(col, float3(0.81, 0.93, 0.78), line * 0.68);
        float sheen = pow(max(0.0, 1.0 - abs(p.x - bounds.x * 0.46) / 20.0), 6.0);
        col += float3(0.10, 0.17, 0.14) * sheen * 0.22;
        col *= mix(float3(1.0), float3(0.24, 0.32, 0.53), night);
        if (night > 0.1) {
            float pool = exp(-length(p - float2(bounds.x * 0.23, bounds.y * 0.28)) * 0.14);
            col += float3(0.40, 0.25, 0.09) * pool * night;
            float spot = exp(-length(p - float2(bounds.x * (0.5 + 0.32 * sin(time * 0.28)), bounds.y * (0.5 + 0.35 * cos(time * 0.2)))) * 0.30);
            col += float3(0.08, 0.27, 0.36) * spot * night;
        }
        float distanceFog = smoothstep(22.0, 75.0, length(p - bounds * 0.5)) * 0.32;
        col = mix(col, float3(0.40, 0.58, 0.62), distanceFog);
        return float4(col, 1.0);
    }
    """
}
