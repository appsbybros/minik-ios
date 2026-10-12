import Metal
import MetalKit
import UIKit

/// Android `world/WorldBlock` (solid cover of the Pro scenes; part of the frame format).
struct WorldBlock: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let depth: Double
    let height: Double
}

/// Android `world/ArenaFrame`: what the world renderer draws this frame.
struct ArenaFrame: Equatable {
    let camera: ArenaCamera
    let scene: String
    let width: Double
    let depth: Double
    let time: Double
    var night: Float = 0
    var level: Int = 0
    var blocks: [WorldBlock] = []
}

private final class WorldBundleToken {}

/// Android `world/ArenaWorldView` (an OpenGL ES 2 `GLSurfaceView`, `RENDERMODE_WHEN_DIRTY`): the perspective ground,
/// sky band and gradient behind the arena, drawn with Metal. The quads, uniforms and shader math are the Android ones
/// statement by statement (GLSL → Metal Shading Language); OpenGL's clip depth [-w, w] is mapped to Metal's [0, w], so
/// the near (0.2) and far (≈300) planes clip the ground exactly as on Android. The Pro-only "building" and "parking"
/// scenes and the undrawn cut-out sheets are not part of this edition.
final class ArenaWorldView: UIView {
    override class var layerClass: AnyClass { return CAMetalLayer.self }

    /// Kotlin uniforms, by index: 0-3 uCamera, 4-7 uLens, 8 uCenterX, 9 uCenter, 10 uMode, 11 uAlpha, 12 uScene,
    /// 13 uTime, 14 uNight, 15-16 uBounds.
    private static let uniformCount = 20

    private let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var textures: [String: MTLTexture] = [:]
    private var arenaFrame = ArenaFrame(camera: ArenaCamera(x: 8.0, y: 8.0, distance: 34.0), scene: "park", width: 16.0, depth: 16.0, time: 0.0)
    /// False when Metal could not be set up; the arena then shows the scene picture instead.
    private(set) var ready = false
    /// Android `onFirstFrame`: runs once on the main thread after the first world frame is drawn (when Metal is
    /// unavailable, as soon as the scene picture stands in). Setting it later still delivers it.
    var onFirstFrame: (@MainActor () -> Void)? {
        didSet {
            if delivered { notifyFirstFrame() }
        }
    }
    private var delivered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = true
        backgroundColor = UIColor(red: 0.045, green: 0.14, blue: 0.23, alpha: 1)
        isAccessibilityElement = false
        setUp()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private var metalLayer: CAMetalLayer? { return layer as? CAMetalLayer }

    private func setUp() {
        guard let device, let metal = metalLayer else { return }
        metal.device = device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = true
        queue = device.makeCommandQueue()
        do {
            let library = try device.makeLibrary(source: ArenaWorldView.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "worldVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "worldFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA).
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            pipeline = nil
            print("ArenaWorldView: Metal pipeline unavailable: \(error)")
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        let loader = MTKTextureLoader(device: device)
        let bundle = Bundle(for: WorldBundleToken.self)
        // Android loads every sheet; this edition draws only the three skies and the two ground materials.
        for name in ["park_sky", "beach_sky", "andromeda_sky", "grass", "sand"] {
            guard let image = UIImage(named: name, in: bundle, compatibleWith: nil) ?? UIImage(named: name), let cg = image.cgImage else {
                print("ArenaWorldView: Missing world art \(name)")
                continue
            }
            // Texels are used as stored (no sRGB decoding), like GLUtils.texImage2D on Android.
            if let texture = try? loader.newTexture(cgImage: cg, options: [MTKTextureLoader.Option.SRGB: false]) {
                textures[name] = texture
            }
        }
        ready = pipeline != nil && queue != nil && sampler != nil && textures.count == 5
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metal = metalLayer else { return }
        let scale = min(max(traitCollection.displayScale, 1), 2)
        metal.contentsScale = scale
        metal.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        render()
    }

    /// Android `submit(frame)`: store the frame and draw it.
    func submit(_ frame: ArenaFrame) {
        arenaFrame = frame
        render()
    }

    private func render() {
        if !ready {
            if bounds.width > 1 && bounds.height > 1 { firstFrameDrawn() }
            return
        }
        guard bounds.width > 1, bounds.height > 1, let metal = metalLayer, let queue, let pipeline, let sampler,
              let drawable = metal.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.045, green: 0.14, blue: 0.23, alpha: 1)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        draw(encoder, arenaFrame, Float(drawable.texture.width), Float(drawable.texture.height))
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        firstFrameDrawn()
    }

    private func firstFrameDrawn() {
        if delivered { return }
        delivered = true
        notifyFirstFrame()
    }

    private func notifyFirstFrame() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onFirstFrame?()
            }
        }
    }

    /// Kotlin `onDrawFrame`.
    private func draw(_ encoder: MTLRenderCommandEncoder, _ f: ArenaFrame, _ w: Float, _ h: Float) {
        let c = f.camera
        var u = [Float](repeating: 0, count: ArenaWorldView.uniformCount)
        u[0] = Float(c.x)
        u[1] = Float(c.y)
        u[2] = Float(c.distance)
        u[3] = Float(c.focusHeight)
        u[4] = Float(sin(c.tilt))
        u[5] = Float(cos(c.tilt))
        u[6] = Float(1 / tan(c.fov * Double.pi / 360))
        u[7] = w / h
        u[8] = Float(2 * c.centerX - 1)
        u[9] = Float(1 - 2 * c.centerY)
        u[13] = Float(f.time.truncatingRemainder(dividingBy: 1000))
        u[14] = f.night
        let scene: String
        switch f.scene {
        case "beach": scene = "beach"
        case "andromeda": scene = "andromeda"
        default: scene = "park"
        }
        switch f.scene {
        case "beach": u[12] = 1
        case "andromeda": u[12] = 2
        case "parking": u[12] = 3
        case "building": u[12] = 4
        default: u[12] = 0
        }
        u[15] = Float(f.width)
        u[16] = Float(f.depth)
        if mode(encoder, &u, 0, scene + "_sky") {
            quad(encoder, [-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0])
        }
        let skyBottom = 1 - 2 * (w / h) / 2.2528
        if mode(encoder, &u, 1, scene + "_sky") {
            quad(encoder, [-1.06, skyBottom, 0, 1.06, skyBottom, 0, -1.06, 1, 0, 1.06, 1, 0], 0.39, 0, 0.61, 1)
        }
        if mode(encoder, &u, 2, scene == "beach" ? "sand" : "grass") {
            let floorZ = Float(Double(f.level) * 3.4 - 0.025)
            quad(encoder, [-150, 160, floorZ, 150, 160, floorZ, -150, -200, floorZ, 150, -200, floorZ], 0, 0, 60, 60)
        }
    }

    /// Kotlin `mode(value, tex, alpha)`: sets uMode/uAlpha and binds the texture; false when the art is missing.
    private func mode(_ encoder: MTLRenderCommandEncoder, _ u: inout [Float], _ value: Float, _ texture: String, _ alpha: Float = 1) -> Bool {
        guard let bound = textures[texture] else { return false }
        u[10] = value
        u[11] = alpha
        encoder.setVertexBytes(u, length: MemoryLayout<Float>.stride * u.count, index: 1)
        encoder.setFragmentBytes(u, length: MemoryLayout<Float>.stride * u.count, index: 0)
        encoder.setFragmentTexture(bound, index: 0)
        return true
    }

    /// Kotlin `quad(x0,y0,z0, x1,y1,z1, x2,y2,z2, x3,y3,z3, u0,v0,u1,v1)`: two triangles with the same vertex order.
    private func quad(_ encoder: MTLRenderCommandEncoder, _ p: [Float], _ u0: Float = 0, _ v0: Float = 0, _ u1: Float = 1, _ v1: Float = 1) {
        let data: [Float] = [p[0], p[1], p[2], u0, v1, p[3], p[4], p[5], u1, v1, p[6], p[7], p[8], u0, v0,
                             p[6], p[7], p[8], u0, v0, p[3], p[4], p[5], u1, v1, p[9], p[10], p[11], u1, v0]
        encoder.setVertexBytes(data, length: MemoryLayout<Float>.stride * data.count, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    /// Android `VERT` and `FRAG`, in Metal Shading Language. `u` holds the uniforms listed at `uniformCount`.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct WorldVertex {
        float4 position [[position]];
        float2 uv;
        float3 world;
    };

    vertex WorldVertex worldVertex(uint vid [[vertex_id]], constant float *data [[buffer(0)]], constant float *u [[buffer(1)]]) {
        WorldVertex out;
        float3 aPos = float3(data[vid * 5], data[vid * 5 + 1], data[vid * 5 + 2]);
        out.uv = float2(data[vid * 5 + 3], data[vid * 5 + 4]);
        out.world = aPos;
        float4 p;
        if (u[10] < 1.5) {
            p = float4(aPos, 1.0);
        } else {
            float dy = aPos.y - u[1];
            float dz = aPos.z - u[3];
            float depth = u[2] - u[4] * dy - u[5] * dz;
            float yy = -u[5] * dy + u[4] * dz;
            p = float4((aPos.x - u[0]) * u[6] / u[7] + u[8] * depth, yy * u[6] + u[9] * depth, 1.00134 * depth - 0.40027, depth);
        }
        p.z = 0.5 * (p.z + p.w);
        out.position = p;
        return out;
    }

    static float worldHash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    static float worldNoise(float2 p) {
        float2 a = floor(p);
        float2 b = fract(p);
        b = b * b * (3.0 - 2.0 * b);
        return mix(mix(worldHash(a), worldHash(a + float2(1.0, 0.0)), b.x), mix(worldHash(a + float2(0.0, 1.0)), worldHash(a + float2(1.0, 1.0)), b.x), b.y);
    }

    fragment float4 worldFragment(WorldVertex in [[stage_in]], constant float *u [[buffer(0)]],
                                  texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
        float mode = u[10];
        float alpha = u[11];
        float scene = u[12];
        float time = u[13];
        float night = u[14];
        float2 bounds = float2(u[15], u[16]);
        float2 vUv = in.uv;
        if (mode < 0.5) {
            float3 col = mix(float3(0.05, 0.23, 0.35), float3(0.19, 0.55, 0.72), vUv.y);
            if (scene > 1.5 && scene < 2.5) col = mix(float3(0.09, 0.04, 0.23), float3(0.34, 0.2, 0.52), vUv.y);
            return float4(col * (1.0 - night * 0.75), 1.0);
        }
        if (mode < 1.5 || (mode > 2.5 && mode < 3.5)) {
            float4 col = tex.sample(s, vUv);
            if (col.a < 0.025) discard_fragment();
            col.rgb *= mix(float3(1.04, 1.02, 1.0), float3(0.40, 0.48, 0.74), night);
            return float4(col.rgb, col.a * alpha);
        }
        if (mode > 3.5) {
            return float4(float3(0.22, 0.55, 0.61) * alpha, 1.0);
        }
        float2 p = in.world.xy;
        float3 material = tex.sample(s, abs(fract(p * 0.12) * 2.0 - 1.0)).rgb;
        float n = worldNoise(p * 0.34);
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
