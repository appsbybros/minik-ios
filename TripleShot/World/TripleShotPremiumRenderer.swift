import Foundation
import Metal
import QuartzCore
import simd

// Port of view/TripleShotPremiumRenderer.kt (TripleShotGame 6c38131), statement by statement (spec 06 sections 3.4,
// 4.1-4.10, 4.13, 7, 8 and 9.3). The GLSurfaceView.Renderer becomes a Metal renderer driven from the main thread:
// TripleShotGpuWorldView calls `onSurfaceCreated` / `onSurfaceChanged` / `onDrawFrame` from AChoreographer's
// post-traversal phase (after the court views submitted this vsync's snapshot), so everything that was @Volatile or
// concurrent on Android (snapshot, cameraFrame, ready, spriteRegions, pending) is plain main-thread state here.
//
// GL -> Metal (spec 06 section 9.3):
//  - one program -> two MTLRenderPipelineStates that differ only in blending: `over` (ONE, ONE_MINUS_SRC_ALPHA) and
//    `add` (ONE, ONE); the GL depth state (GL_DEPTH_TEST, glDepthMask, glDepthFunc) is tracked exactly like the GL
//    state machine and mapped per draw to cached MTLDepthStencilStates (the four used: always/no write,
//    lessEqual/write, lessEqual/no write, greater/no write);
//  - EGL MSAA 4/2/0 -> 4x (2x, 1x fallback) multisampled colour (memoryless on a device, private in the simulator)
//    resolved into the CAMetalLayer drawable (.bgra8Unorm), .depth32Float depth cleared to 1;
//  - client vertex arrays -> MTLBuffers for the static meshes (made when the meshes are built) and setVertexBytes
//    for the reused 6-vertex quad (copied at encode time, like GL reads client arrays at glDrawArrays);
//  - glUniform* (sticky) -> one `TripleUniforms` value sent with every draw; texture unit 0 -> fragment texture 0
//    (texture "0" = a 1x1 opaque black placeholder: GLES samples an unbound unit as (0, 0, 0, 1)); sampler
//    linear/clamp-to-edge, no mipmaps;
//  - GLUtils.texImage2D of a premultiplied bitmap -> a premultiplied RGBA8 MTLTexture (row 0 = image top = v 0),
//    made by the preparation worker (TripleShotTextureFactory); installing one per frame keeps Android's
//    "one upload per GL frame" readiness timing; byte accounting = bitmap.allocationByteCount (w * h * 4);
//  - presentsWithTransaction: commit, waitUntilScheduled, present, so the Canvas overlay (labels, markers) and the
//    3D frame change in the same Core Animation transaction.
// Geometry services (project, actorBounds, screenGround, socket) use the GL-convention matrices on the CPU and return
// Android PIXELS (the surface size in px), DESIGN section 9. android.opengl.Matrix.invertM/multiplyMV are ported
// exactly (Float maths in the AOSP order). Diagnostics (frame-gap histogram, TRIPLE_GPU/TRIPLE_PLAY/TRIPLE_TEXTURE
// logs) are kept; glGetError -> the previous command buffer's error, glGetString -> the Metal device name.

/** Consumes immutable presentation state. Never advances physics, possession, AI or scores. */
final class TripleShotPremiumRenderer {
    /// Kotlin `Texture(glId, bytes, regions)`: `glId` is the GPU texture (a GL texture name on Android).
    private struct Texture {
        let glId: MTLTexture
        let bytes: Int
        let regions: [ADrawableRes: TripleShotSpriteRegion]
    }
    private struct CameraFrame {
        let matrix: [Float]
        let width: Int
        let height: Int
    }
    private struct Sprite {
        let frame: CharacterSpriteFrame?
        let region: TripleShotSpriteRegion
        let width: Float
        let height: Float
        let anchorX: Float
        let anchorY: Float
    }
    private let selector = TripleShotPlayerRenderer(context: nil)
    private let density = AResources.density
    private var snapshot: TripleShotWorldSnapshot?
    private var cameraFrame: CameraFrame?
    private(set) var ready = false
    private var textures = KLinkedMap<String, Texture>()
    private var spriteRegions: [String: [ADrawableRes: TripleShotSpriteRegion]] = [:]
    private var pending: [TripleShotPreparedTexture] = []
    private let camera = TripleShotWorldCamera()
    private var floor = TripleShotCourtMeshBuilder.floor()
    private var surround: TripleShotCourtSurround?
    private var courtBack: Float = -11
    private var courtCenter: Float = 0
    private let ground = TripleShotCourtMeshBuilder.ground()
    private var baskets: TripleShotBasketMeshes?
    private var hoopKey: [CourtPoint]?
    /// Kotlin `quadBuffer` (6 x 8 floats) wrapped by the `quad` mesh.
    private let quad = TripleShotMesh(vertices: [Float](repeating: 0, count: 6 * 8), count: 6)
    private let identity: [Float] = TripleShotPremiumRenderer.setIdentityM()
    private var width = 1
    private var height = 1
    private let textureEvicted: (String) -> Void
    private let contextCreated: () -> Void

    // GL program and state -> Metal device objects (made once per process: Metal has no context loss).
    /// The Metal device (nil only where Metal is unavailable; nothing is drawn then).
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineOver: MTLRenderPipelineState?
    private let pipelineAdd: MTLRenderPipelineState?
    private var depthStates: [Int: MTLDepthStencilState] = [:]
    private let samplerState: MTLSamplerState?
    private let placeholder: MTLTexture?
    /// The EGL config chooser's MSAA sample count (4, then 2, then 0 -> 1 here).
    let sampleCount: Int
    private var msaaColor: MTLTexture?
    private var depthTexture: MTLTexture?
    private var targetWidth = 0
    private var targetHeight = 0
    private var meshBuffers: [ObjectIdentifier: (mesh: TripleShotMesh, buffer: MTLBuffer)] = [:]
    private var encoder: MTLRenderCommandEncoder?
    private var uniforms = TripleUniforms()
    private var lastCommandBuffer: MTLCommandBuffer?
    // The GL state machine (glEnable/glDisable(GL_DEPTH_TEST), glDepthMask, glDepthFunc, glBlendFunc).
    private var glDepthTest = true
    private var glDepthMaskOn = true
    private var glDepthFuncGreater = false
    private var glBlendAdd = false

    private var previous: Int64 = 0
    private var began: Int64 = 0
    private var logAt: Int64 = 0
    private var frames = 0
    private var histogram = [Int](repeating: 0, count: 1001)
    private var severe = 0
    private var maximum = 0
    private var elapsed: Int64 = 0
    private var measured = 0
    private var generation = 0
    private var missing = 0
    private var glErrors = 0

    init(context: Any?, textureEvicted: @escaping (String) -> Void, contextCreated: @escaping () -> Void) {
        self.textureEvicted = textureEvicted
        self.contextCreated = contextCreated
        let objects = TripleShotPremiumRenderer.deviceObjects
        device = objects?.device
        commandQueue = objects?.commandQueue
        pipelineOver = objects?.pipelineOver
        pipelineAdd = objects?.pipelineAdd
        samplerState = objects?.samplerState
        placeholder = objects?.placeholder
        sampleCount = objects?.sampleCount ?? 1
        for test in [false, true] { for write in [false, true] { for greater in [false, true] {
            _ = depthState(test: test, write: write, greater: greater)
        } } }
    }

    /// Kotlin positional call form `TripleShotPremiumRenderer(context, textureEvicted, contextCreated)`.
    convenience init(_ context: Any?, _ textureEvicted: @escaping (String) -> Void, _ contextCreated: @escaping () -> Void) {
        self.init(context: context, textureEvicted: textureEvicted, contextCreated: contextCreated)
    }

    func submit(scene: TripleShotWorldSnapshot) { snapshot = scene }
    func enqueue(texture: TripleShotPreparedTexture) { pending.append(texture) }
    func discardPending() {
        while !pending.isEmpty { let p = pending.removeFirst(); p.bitmap.recycle() }
    }
    func resumeFrameClock() { previous = 0 }
    func project(point: CourtPoint) -> (first: Float, second: Float)? {
        guard let it = cameraFrame else { return nil }
        return TripleShotWorldMath.project(m: it.matrix, p: point, width: it.width, height: it.height)
    }
    func actorBounds(actor: TripleShotWorldActor) -> ARectF? {
        guard let s = sprite(actor: actor) else { return nil }
        let left: Float = -s.width * s.anchorX
        let top: Float = actor.position.y + s.height * s.anchorY
        guard let a = project(point: CourtPoint(x: actor.position.x + left * TripleShotWorldMath.RIGHT_X, y: top,
                                                z: actor.position.z + left * TripleShotWorldMath.RIGHT_Z)) else { return nil }
        guard let b = project(point: CourtPoint(x: actor.position.x + (left + s.width) * TripleShotWorldMath.RIGHT_X, y: top - s.height,
                                                z: actor.position.z + (left + s.width) * TripleShotWorldMath.RIGHT_Z)) else { return nil }
        return ARectF(kmin(a.first, b.first), kmin(a.second, b.second), kmax(a.first, b.first), kmax(a.second, b.second))
    }
    func screenGround(x: Float, y: Float) -> CourtPoint? {
        guard let f = cameraFrame else { return nil }
        return TripleShotPremiumRenderer.screenGround(matrix: f.matrix, width: f.width, height: f.height, x: x, y: y)
    }

    /// The body of Kotlin `screenGround(x, y)` for a camera frame (the matrix, surface width and height in px).
    static func screenGround(matrix: [Float], width: Int, height: Int, x: Float, y: Float) -> CourtPoint? {
        var inverse = [Float](repeating: 0, count: 16)
        if !invertM(mInv: &inverse, mInvOffset: 0, m: matrix, mOffset: 0) { return nil }
        let a: [Float] = [2 * x / width.toFloat() - 1, 1 - 2 * y / height.toFloat(), -1, 1]
        let b: [Float] = [a[0], a[1], 1, 1]
        var near = [Float](repeating: 0, count: 4)
        var far = [Float](repeating: 0, count: 4)
        multiplyMV(resultVec: &near, resultVecOffset: 0, lhsMat: inverse, lhsMatOffset: 0, rhsVec: a, rhsVecOffset: 0)
        multiplyMV(resultVec: &far, resultVecOffset: 0, lhsMat: inverse, lhsMatOffset: 0, rhsVec: b, rhsVecOffset: 0)
        for i in 0...2 { near[i] /= near[3]; far[i] /= far[3] }
        let dy = far[1] - near[1]
        if abs(dy) < 0.00001 { return nil }
        let t = -near[1] / dy
        return CourtPoint(x: near[0] + (far[0] - near[0]) * t, y: 0, z: near[2] + (far[2] - near[2]) * t)
    }

    private func sprite(actor: TripleShotWorldActor) -> Sprite? {
        let key = "actor:\(actor.state.characterId ?? "bob")"
        guard let regions = spriteRegions[key] else { return nil }
        guard let resolved = selector.worldFrame(state: actor.state) else {
            return regions[TripleShotPreparedTexture.VECTOR_REGION].map { Sprite(frame: nil, region: $0, width: 2.45, height: 2.45, anchorX: 0.5, anchorY: 0.9375) }
        }
        let set = resolved.first, frame = resolved.second
        guard let region = regions[frame.resId] else { return nil }
        let h: Float
        if let targetHeightDp = frame.targetHeightDp {
            h = targetHeightDp * 0.012
        } else {
            h = region.sourceHeight.toFloat() / set.referenceHeightPx * set.referenceHeightDp * 0.012
        }
        return Sprite(frame: frame, region: region, width: h * region.sourceWidth.toFloat() / region.sourceHeight.toFloat(), height: h,
                      anchorX: frame.anchorX01, anchorY: frame.anchorY01)
    }
    func socket(actor: TripleShotWorldActor, inFront: Bool = true) -> CourtPoint {
        let s = sprite(actor: actor)
        let state = actor.state
        var x: Float
        if let s = s, let frame = s.frame, frame.hasBallAnchor {
            x = (frame.ballSourceX! / s.region.sourceWidth.toFloat() - s.anchorX) * s.width
        } else {
            x = 0.22
        }
        var y: Float
        if let s = s, let frame = s.frame, frame.hasBallAnchor {
            y = (s.anchorY - frame.ballSourceY! / s.region.sourceHeight.toFloat()) * s.height
        } else {
            y = 1.25
        }
        if state.mirrorX { x = -x }
        if state.motion == TripleShotPlayerRenderer.Motion.DRIBBLE {
            let phase = state.dribblePhase01.coerceIn(0, 1)
            // One hand, one floor bounce. Do not cross the body on every frame/cycle.
            x = abs(x).coerceAtLeast(0.60) * state.dribbleHandSign
            let hand = y.coerceIn(0.95, 1.55)
            let bounce = abs(ksin(phase * PI_F))
            y = hand - (hand - 0.24) * bounce
        } else if state.motion == TripleShotPlayerRenderer.Motion.IDLE && state.dribbleHandSign < 0 { x = -x }
        var depth: Float = inFront ? 0.20 : -0.20
        if state.crossoverProgress >= 0 && state.crossoverProgress <= Float(0.999) {
            let t = state.crossoverProgress; let radius = abs(x).coerceAtLeast(0.62)
            x = radius * (state.crossoverFrom + (state.dribbleHandSign - state.crossoverFrom) * t)
            y = Float(0.24) + Float(1.02) * abs(2 * t - 1)
            if state.crossoverBehind { depth = Float(-0.46) * ksin(t * PI_F) }
        }
        return CourtPoint(x: actor.position.x + x * TripleShotWorldMath.RIGHT_X - depth * TripleShotWorldMath.RIGHT_Z,
                          y: actor.position.y + y,
                          z: actor.position.z + x * TripleShotWorldMath.RIGHT_Z + depth * TripleShotWorldMath.RIGHT_X)
    }

    /// GLSurfaceView.Renderer.onSurfaceCreated: called by TripleShotGpuWorldView on the first frame after every attach
    /// (Android: a GL thread and EGL context per attach). The program, GL state and EGL config are the Metal device
    /// objects made once in init (no context loss on Metal); the resident textures are forgotten as on Android.
    func onSurfaceCreated() {
        generation += 1; ready = false; textures.clear(); spriteRegions.removeAll(); discardPending()
        glDepthTest = true; glDepthFuncGreater = false; glBlendAdd = false
        previous = 0; began = ASystem.nanoTime(); for i in histogram.indices { histogram[i] = 0 }; measured = 0; severe = 0; elapsed = 0; maximum = 0
        contextCreated()
        ALog.i("TRIPLE_GPU", "contextCreated=\(generation) GLES=Metal renderer=\(device?.name ?? "none") depth=32 samples=\(sampleCount)")
    }
    func onSurfaceChanged(w: Int, h: Int) { width = w.coerceAtLeast(1); height = h.coerceAtLeast(1) }
    private func upload(p: TripleShotPreparedTexture) {
        // glGenTextures + GL_LINEAR / GL_CLAMP_TO_EDGE (the sampler) + GLUtils.texImage2D: normally made by the worker.
        var made = p.texture
        if made == nil, let device = device, !p.bitmap.isRecycled {
            made = TripleShotTextureFactory.makeTexture(device: device, bitmap: p.bitmap)
        }
        guard let name = made else {
            ALog.e("TRIPLE_TEXTURE", "upload failed=\(p.key)")
            p.bitmap.recycle()
            return
        }
        _ = textures.remove(p.key) // glDeleteTextures: the old texture is released with its last reference
        textures[p.key] = Texture(glId: name, bytes: p.bitmap.allocationByteCount, regions: p.regions); spriteRegions[p.key] = p.regions
        p.bitmap.recycle()
        ALog.i("TRIPLE_TEXTURE", "uploaded=\(p.key) textures=\(textures.count) bytes=\(textures.values.reduce(0) { $0 + $1.bytes })")
    }

    /// GLSurfaceView.Renderer.onDrawFrame, presenting into `layer` (the GL surface). The frame's state work (uploads,
    /// readiness, eviction, camera) runs even when no drawable is available.
    func onDrawFrame(layer: CAMetalLayer) {
        let now = ASystem.nanoTime(); let dt: Float = previous == 0 ? 1 / 60 : (now - previous).toFloat() / 1e9
        if previous != 0 && now - began > 5_000_000_000 {
            let ms = ((now - previous) / 1_000_000).toInt(); histogram[ms.coerceIn(0, 1000)] += 1; measured += 1; elapsed += now - previous; maximum = Swift.max(maximum, ms); if ms > 50 { severe += 1 }
        }
        previous = now; frames += 1
        // glClear respects the depth write mask on Pixel 3's Adreno driver.
        glDepthMaskOn = true
        let commandBuffer = commandQueue?.makeCommandBuffer()
        let drawable = commandBuffer == nil ? nil : layer.nextDrawable()
        if let commandBuffer = commandBuffer, let drawable = drawable {
            encoder = beginPass(commandBuffer, drawable) // glClearColor(.035, .055, .09, 1); glClear(COLOR | DEPTH)
        }
        defer { endFrame(commandBuffer, drawable) }
        guard let scene = snapshot else { return }
        if !pending.isEmpty { upload(p: pending.removeFirst()) }
        var keep = Set(scene.actors.map { "actor:\($0.state.characterId ?? "bob")" })
        for ball in scene.balls { keep.insert("ball:\(ball.resource)") }
        keep.insert("court:\(scene.courtId)")
        ready = keep.allSatisfy { textures.containsKey($0) }
        if textures.values.reduce(0, { $0 + $1.bytes }) > 96 * 1024 * 1024 {
            let remove = textures.keys.filter { !keep.contains($0) }
            for key in remove { _ = textures.remove(key); spriteRegions[key] = nil; textureEvicted(key) }
        }
        if hoopKey != scene.hoops {
            hoopKey = scene.hoops; baskets = TripleShotBasketMeshes(hoops: scene.hoops)
            courtCenter = scene.teamSize == 1 ? scene.hoops.first!.x : 0
            courtBack = scene.teamSize == 1 ? scene.hoops.first!.z - 2.4 : -11
            floor = TripleShotCourtMeshBuilder.floor(centerX: courtCenter, back: courtBack)
            surround = TripleShotCourtSurround(centerX: courtCenter, back: courtBack)
            meshBuffers.removeAll()
        }
        camera.update(scene: scene, aspect: width.toFloat() / height.toFloat(), dt: dt)
        cameraFrame = CameraFrame(matrix: camera.viewProjection, width: width, height: height)
        uniforms.time = (now % 100_000_000_000).toFloat() / 1e9
        uniforms.flex = SIMD2<Float>(0, 0)
        let forest = scene.courtId == "enchanted_forest" || ["skyforge_peaks", "frostline", "rain_break", "midnight_arena"].contains(scene.courtId)
        uniforms.court = forest ? 1 : 0
        uniforms.team = scene.teamSize > 1 ? 1 : 0
        if scene.courtId == "neon_falls" { uniforms.floorPhoto = SIMD4<Float>(0.430, 0.658, 0.356, 0.497) }
        else { uniforms.floorPhoto = SIMD4<Float>(0.325, 0.594, 0.326, 0.490) }
        let hoop = scene.hoops.first ?? CourtPoint(x: 0, y: 3.35, z: -7)
        uniforms.hoop = SIMD2<Float>(hoop.x, hoop.z)
        let bg = textures["court:\(scene.courtId)"]
        if let bg = bg {
            glDepthTest = false; glDepthMaskOn = false
            putQuad(x: -1, top: 1, z: 0, w: 2, h: 2); draw(mesh: quad, r: 1, g: 1, b: 1, a: 1, mode: 8, texture: bg, matrix: identity)
            glDepthTest = true; glDepthMaskOn = true
        }
        // The scenery's soft lower edge must reveal ground, not a stretched sky column.
        // Transparent scenery also must not prevent that ground from passing depth later.
        draw(mesh: ground, r: 0.11, g: 0.12, b: 0.18, a: 1, mode: 7)
        if let bg = bg {
            glDepthMaskOn = false
            // A distant vertical scenery plane, with no baked basketball equipment in its crop.
            billboard(x: courtCenter - 4.6, top: forest ? 18 : 7.1, z: courtBack - 7, w: 70, h: forest ? 18.1 : 7.2, anchor: 0.5, v1: forest ? 0.56 : 0.18)
            draw(mesh: quad, r: 1, g: 1, b: 1, a: 1, mode: 9, texture: bg)
            glDepthMaskOn = true
        }
        if let it = surround {
            draw(mesh: it.deck, r: 0.22, g: 0.19, b: 0.24, a: 1, mode: 0)
            draw(mesh: it.metal, r: 0.10, g: 0.15, b: 0.23, a: 1, mode: 0)
            draw(mesh: it.foliage, r: 0.11, g: 0.36, b: 0.24, a: 1, mode: 0)
            draw(mesh: it.cyan, r: 0.08, g: 0.80, b: 1, a: 1, mode: 6)
            draw(mesh: it.pink, r: 1, g: 0.12, b: 0.65, a: 1, mode: 6)
        }
        draw(mesh: floor, r: 1, g: 1, b: 1, a: 1, mode: 2, texture: bg)
        // Low illuminated boundary plinth gives the floor a physical edge in the world.
        let basket = baskets
        if let basket = basket {
            draw(mesh: basket.structure, r: 0.08, g: 0.19, b: 0.29, a: 1, mode: 0)
            draw(mesh: basket.trim, r: 0.76, g: 0.89, b: 0.95, a: 1, mode: 0)
            uniforms.flex = SIMD2<Float>(scene.rimShake, 0)
            draw(mesh: basket.rims, r: 1, g: 0.29, b: 0.055, a: 1, mode: 0)
            uniforms.flex = SIMD2<Float>(scene.rimShake, scene.netSway)
            draw(mesh: basket.nets, r: 0.94, g: 0.96, b: 1, a: 1, mode: 0)
            uniforms.flex = SIMD2<Float>(0, 0)
        }
        glDepthMaskOn = false
        for a in scene.actors {
            horizontal(x: a.position.x, y: 0.015, z: a.position.z, w: 1.35, d: 0.78)
            draw(mesh: quad, r: 0.018, g: 0.02, b: 0.045, a: 0.52 / (1 + a.position.y), mode: 3)
            if a.controlled || a.team == 1 {
                horizontal(x: a.position.x, y: 0.022, z: a.position.z, w: 1.45, d: 0.98)
                draw(mesh: quad, r: 0.10, g: 0.95, b: 0.68, a: a.controlled ? 0.88 : 0.32, mode: 4)
            }
        }
        for b in scene.balls.filter({ $0.owner == nil }) {
            horizontal(x: b.position.x, y: 0.023, z: b.position.z, w: 0.4, d: 0.29); draw(mesh: quad, r: 0.01, g: 0.02, b: 0.05, a: 0.4 / (1 + b.position.y * 0.35), mode: 3)
        }
        glDepthMaskOn = true; missing = 0
        for p in scene.guides { billboard(x: p.x, top: p.y + 0.045, z: p.z, w: 0.09, h: 0.09, anchor: 0.5); draw(mesh: quad, r: 1, g: 0.85, b: 0.30, a: 0.8, mode: 3) }
        for a in scene.actors {
            let tex = textures["actor:\(a.state.characterId ?? "bob")"]
            let s = sprite(actor: a)
            if tex == nil || s == nil { missing += 1; continue }
            let r = s!.region
            let left = a.state.mirrorX ? r.u1 : r.u0; let right = a.state.mirrorX ? r.u0 : r.u1
            billboard(x: a.position.x, top: a.position.y + s!.height * s!.anchorY, z: a.position.z, w: s!.width, h: s!.height,
                      anchor: s!.anchorX, u0: left, u1: right, v0: r.v0, v1: r.v1)
            draw(mesh: quad, r: 1, g: 1, b: 1, a: 1, mode: 1, texture: tex)
        }
        for ball in scene.balls {
            let a = ball.owner.flatMap { owner in scene.actors.first { $0.id == owner } }
            let p = a == nil ? ball.position : socket(actor: a!, inFront: ball.inFront)
            guard let tex = textures["ball:\(ball.resource)"] else { missing += 1; continue }
            let radius: Float = 0.26
            // A subtle locator stays visible through an occluding defender; the real ball still
            // obeys depth, so it never appears painted on top of a face or the basket.
            glDepthTest = false; glDepthMaskOn = false
            billboard(x: p.x, top: p.y + radius * 1.45, z: p.z, w: radius * 2.9, h: radius * 2.9, anchor: 0.5)
            draw(mesh: quad, r: 1, g: 0.73, b: 0.12, a: 0.22, mode: 4)
            glDepthTest = true; glDepthMaskOn = true
            billboard(x: p.x, top: p.y + radius, z: p.z, w: radius * 2, h: radius * 2, anchor: 0.5)
            uniforms.spin = ball.rotation * PI_F / 180
            draw(mesh: quad, r: 1, g: 1, b: 1, a: 1, mode: 5, texture: tex)
            glDepthMaskOn = false; glDepthFuncGreater = true
            draw(mesh: quad, r: 0.65, g: 0.65, b: 0.65, a: 0.65, mode: 5, texture: tex)
            glDepthFuncGreater = false; glDepthMaskOn = true
        }
        // Preserve the source pack's explicit fingertip mask as a small physical layer.
        for a in scene.actors {
            if !scene.balls.contains(where: { $0.owner == a.id }) { continue }
            guard let s = sprite(actor: a) else { continue }; guard let mask = s.frame?.ballForegroundRect01 else { continue }
            guard let tex = textures["actor:\(a.state.characterId ?? "null")"] else { continue }; let r = s.region
            let localLeft: Float = (mask.left - s.anchorX) * s.width
            let offset: Float = a.state.mirrorX ? -localLeft - mask.width() * s.width : localLeft
            let centerX: Float = a.position.x + offset * TripleShotWorldMath.RIGHT_X - 0.24 * TripleShotWorldMath.RIGHT_Z
            let centerZ: Float = a.position.z + offset * TripleShotWorldMath.RIGHT_Z + 0.24 * TripleShotWorldMath.RIGHT_X
            let u0: Float = r.u0 + (r.u1 - r.u0) * mask.left; let u1: Float = r.u0 + (r.u1 - r.u0) * mask.right
            billboard(x: centerX, top: a.position.y + (s.anchorY - mask.top) * s.height, z: centerZ, w: mask.width() * s.width, h: mask.height() * s.height, anchor: 0,
                      u0: a.state.mirrorX ? u1 : u0, u1: a.state.mirrorX ? u0 : u1, v0: r.v0 + (r.v1 - r.v0) * mask.top, v1: r.v0 + (r.v1 - r.v0) * mask.bottom)
            draw(mesh: quad, r: 1, g: 1, b: 1, a: 1, mode: 1, texture: tex)
        }
        // Glass is the only translucent physical surface. Test against actor/ball/rim depth.
        glDepthMaskOn = false
        if let basket = basket { draw(mesh: basket.glass, r: 0.35, g: 0.80, b: 0.90, a: 0.13, mode: 0) }
        glBlendAdd = true
        for p in surround?.lights ?? [] {
            billboard(x: p.x, top: p.y + 0.46, z: p.z, w: 0.92, h: 0.92, anchor: 0.5)
            if p.x < courtCenter { draw(mesh: quad, r: 0.08, g: 0.55, b: 1, a: 0.55, mode: 3) } else { draw(mesh: quad, r: 1, g: 0.08, b: 0.45, a: 0.55, mode: 3) }
        }
        for a in scene.actors.filter({ $0.state.hotHand }) {
            let p = socket(actor: a); billboard(x: p.x, top: p.y + 0.48, z: p.z, w: 0.96, h: 0.96, anchor: 0.5); draw(mesh: quad, r: 1, g: 0.34, b: 0.035, a: 0.32, mode: 3)
        }
        glBlendAdd = false
        glDepthMaskOn = true
        if now - logAt > 2_000_000_000 {
            logAt = now; let error = lastCommandBuffer?.error == nil ? 0 : 1; if error != 0 { glErrors += 1 }
            func percentile(_ p: Int) -> Int { var total = 0; for i in histogram.indices { total += histogram[i]; if total * 100 >= measured * p { return i } }; return 0 }
            let bytes = textures.values.reduce(0) { $0 + $1.bytes }
            let fps: Double = elapsed > 0 ? Double(measured) * 1e9 / Double(elapsed) : 0.0
            ALog.i("TRIPLE_GPU", "mode=\(scene.teamSize)v\(scene.teamSize) actors=\(scene.actors.count) missingTextures=\(missing) textures=\(textures.count) bytes=\(bytes) glError=\(error) glErrors=\(glErrors) context=\(generation) cameraDistance=\(javaString(camera.distance)) focus=\(javaString(camera.focusX)),\(javaString(camera.focusZ)) fps=\(javaString(fps)) frames=\(measured) p95Ms=\(percentile(95)) p99Ms=\(percentile(99)) maxGapMs=\(maximum) severeGaps=\(severe)")
            ALog.i("TRIPLE_PLAY", "actors=" + scene.actors.map { a in "\(a.id):\(a.state.motion.name)@\(javaString(a.position.x)),\(javaString(a.position.z)):heightPx=\(actorBounds(actor: a).map { javaString($0.height()) } ?? "null")" }.joined(separator: ", ")
                + " ball=" + scene.balls.map { "\($0.owner ?? "null"):\($0.position)" }.joined(separator: ", "))
        }
    }
    /// Kotlin `quadBuffer.put(...)` x 8 at the buffer position (`quadBuffer.clear()` resets it to 0).
    private func putVertex(_ index: inout Int, _ px: Float, _ py: Float, _ pz: Float, _ u: Float, _ v: Float,
                           _ nx: Float, _ ny: Float, _ nz: Float) {
        quad.vertices[index] = px; quad.vertices[index + 1] = py; quad.vertices[index + 2] = pz
        quad.vertices[index + 3] = u; quad.vertices[index + 4] = v
        quad.vertices[index + 5] = nx; quad.vertices[index + 6] = ny; quad.vertices[index + 7] = nz
        index += 8
    }
    private func putQuad(x: Float, top: Float, z: Float, w: Float, h: Float, u0: Float = 0, u1: Float = 1, v0: Float = 0, v1: Float = 1) {
        var index = 0
        func v(_ px: Float, _ py: Float, _ u: Float, _ v: Float) { putVertex(&index, px, py, z, u, v, 0, 0, 1) }
        v(x, top, u0, v0); v(x, top - h, u0, v1); v(x + w, top - h, u1, v1)
        v(x, top, u0, v0); v(x + w, top - h, u1, v1); v(x + w, top, u1, v0)
    }
    private func billboard(x: Float, top: Float, z: Float, w: Float, h: Float, anchor: Float, u0: Float = 0, u1: Float = 1, v0: Float = 0, v1: Float = 1) {
        var index = 0
        func v(_ offset: Float, _ y: Float, _ u: Float, _ v: Float) {
            putVertex(&index, x + offset * TripleShotWorldMath.RIGHT_X, y, z + offset * TripleShotWorldMath.RIGHT_Z, u, v,
                      -TripleShotWorldMath.RIGHT_Z, 0, TripleShotWorldMath.RIGHT_X)
        }
        let l: Float = -w * anchor; let r: Float = l + w
        v(l, top, u0, v0); v(l, top - h, u0, v1); v(r, top - h, u1, v1)
        v(l, top, u0, v0); v(r, top - h, u1, v1); v(r, top, u1, v0)
    }
    private func horizontal(x: Float, y: Float, z: Float, w: Float, d: Float) {
        var index = 0
        func v(_ px: Float, _ pz: Float, _ u: Float, _ v: Float) { putVertex(&index, px, y, pz, u, v, 0, 1, 0) }
        v(x - w / 2, z - d / 2, 0, 0); v(x - w / 2, z + d / 2, 0, 1); v(x + w / 2, z + d / 2, 1, 1)
        v(x - w / 2, z - d / 2, 0, 0); v(x + w / 2, z + d / 2, 1, 1); v(x + w / 2, z - d / 2, 1, 0)
    }
    private func draw(mesh: TripleShotMesh, r: Float, g: Float, b: Float, a: Float, mode: Int, texture: Texture? = nil, matrix: [Float]? = nil) {
        let m = matrix ?? camera.viewProjection
        uniforms.vp = TripleShotPremiumRenderer.matrix(m); uniforms.color = SIMD4<Float>(r, g, b, a); uniforms.mode = Int32(mode)
        guard let encoder = encoder, mesh.count > 0,
              let pipeline = glBlendAdd ? pipelineAdd : pipelineOver,
              let depthState = depthState(test: glDepthTest, write: glDepthMaskOn, greater: glDepthFuncGreater) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        if let tex = texture?.glId ?? placeholder { encoder.setFragmentTexture(tex, index: 0) }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TripleUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TripleUniforms>.stride, index: 1)
        if mesh === quad {
            quad.vertices.withUnsafeBytes { raw in
                if let base = raw.baseAddress { encoder.setVertexBytes(base, length: raw.count, index: 0) }
            }
        } else {
            guard let buffer = meshBuffer(mesh) else { return }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.count)
    }

    // MARK: - Metal plumbing (EGL config, program link, GL state objects, render pass)

    /// The device-wide Metal objects (the GL program, EGL config and GL state of every renderer).
    private struct DeviceObjects {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue?
        let pipelineOver: MTLRenderPipelineState
        let pipelineAdd: MTLRenderPipelineState
        let samplerState: MTLSamplerState?
        let placeholder: MTLTexture?
        let sampleCount: Int
    }

    /// Made once (by the first renderer) and shared: the Metal library is compiled at run time, as in Android's
    /// glCompileShader.
    private static let deviceObjects: DeviceObjects? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return makeDeviceObjects(device)
    }()

    /// Kotlin `link(VERTEX, FRAGMENT)` + the EGL config chooser + the GL state set in onSurfaceCreated, as Metal
    /// device objects. A shader that does not compile fails like Android's `check(ok)`.
    private static func makeDeviceObjects(_ device: MTLDevice) -> DeviceObjects {
        var sampleCount = 1
        for samples in [4, 2, 1] where device.supportsTextureSampleCount(samples) {
            sampleCount = samples
            ALog.i("TRIPLE_GPU", "Metal depth32Float MSAA=\(samples == 1 ? 0 : samples)")
            break
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: TripleShotPremiumShaders.source, options: nil)
        } catch {
            preconditionFailure("TripleShotPremiumShaders: \(error)")
        }
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3; vertexDescriptor.attributes[0].offset = 0; vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2; vertexDescriptor.attributes[1].offset = 12; vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float3; vertexDescriptor.attributes[2].offset = 20; vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 32; vertexDescriptor.layouts[0].stepFunction = .perVertex
        func pipeline(additive: Bool) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: TripleShotPremiumShaders.VERTEX_FUNCTION)
            descriptor.fragmentFunction = library.makeFunction(name: TripleShotPremiumShaders.FRAGMENT_FUNCTION)
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.rasterSampleCount = sampleCount
            descriptor.depthAttachmentPixelFormat = .depth32Float
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            // glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA) or glBlendFunc(GL_ONE, GL_ONE).
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                preconditionFailure("TripleShotPremiumRenderer pipeline: \(error)")
            }
        }
        let pipelineOver = pipeline(additive: false)
        let pipelineAdd = pipeline(additive: true)
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear; sampler.magFilter = .linear; sampler.mipFilter = .notMipmapped
        sampler.sAddressMode = .clampToEdge; sampler.tAddressMode = .clampToEdge
        let samplerState = device.makeSamplerState(descriptor: sampler)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let placeholder = device.makeTexture(descriptor: descriptor)
        var black: [UInt8] = [0, 0, 0, 255]
        placeholder?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        return DeviceObjects(device: device, commandQueue: device.makeCommandQueue(), pipelineOver: pipelineOver, pipelineAdd: pipelineAdd,
                             samplerState: samplerState, placeholder: placeholder, sampleCount: sampleCount)
    }

    /// The MTLDepthStencilState of the GL depth state: test disabled = always and no writes (GL skips depth writes
    /// when GL_DEPTH_TEST is off); otherwise GL_LEQUAL or GL_GREATER with glDepthMask.
    private func depthState(test: Bool, write: Bool, greater: Bool) -> MTLDepthStencilState? {
        let key = !test ? 0 : (greater ? 2 : 4) + (write ? 1 : 0)
        if let state = depthStates[key] { return state }
        guard let device = device else { return nil }
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = !test ? .always : (greater ? .greater : .lessEqual)
        descriptor.isDepthWriteEnabled = test && write
        let state = device.makeDepthStencilState(descriptor: descriptor)
        depthStates[key] = state
        return state
    }

    /// The static mesh's vertices in a GPU buffer, made once per mesh (the mesh is kept alive with its buffer).
    private func meshBuffer(_ mesh: TripleShotMesh) -> MTLBuffer? {
        let id = ObjectIdentifier(mesh)
        if let entry = meshBuffers[id] { return entry.buffer }
        guard let device = device else { return nil }
        let made = mesh.vertices.withUnsafeBytes { raw -> MTLBuffer? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        guard let buffer = made else { return nil }
        meshBuffers[id] = (mesh: mesh, buffer: buffer)
        return buffer
    }

    /// glViewport + glClearColor(.035, .055, .09, 1) + glClear(COLOR | DEPTH) on the multisampled targets.
    private func beginPass(_ commandBuffer: MTLCommandBuffer, _ drawable: CAMetalDrawable) -> MTLRenderCommandEncoder? {
        guard let device = device else { return nil }
        let w = drawable.texture.width, h = drawable.texture.height
        if w != targetWidth || h != targetHeight || depthTexture == nil {
            targetWidth = w; targetHeight = h
            #if targetEnvironment(simulator)
            let storage = MTLStorageMode.private
            #else
            let storage = MTLStorageMode.memoryless
            #endif
            if sampleCount > 1 {
                let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
                color.textureType = .type2DMultisample; color.sampleCount = sampleCount
                color.usage = [.renderTarget]; color.storageMode = storage
                msaaColor = device.makeTexture(descriptor: color)
            } else {
                msaaColor = nil
            }
            let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
            depth.textureType = sampleCount > 1 ? .type2DMultisample : .type2D; depth.sampleCount = sampleCount
            depth.usage = [.renderTarget]; depth.storageMode = storage
            depthTexture = device.makeTexture(descriptor: depth)
        }
        let pass = MTLRenderPassDescriptor()
        let color = pass.colorAttachments[0]!
        if sampleCount > 1, let msaa = msaaColor {
            color.texture = msaa; color.resolveTexture = drawable.texture; color.storeAction = .multisampleResolve
        } else {
            color.texture = drawable.texture; color.storeAction = .store
        }
        color.loadAction = .clear
        color.clearColor = MTLClearColor(red: 0.035, green: 0.055, blue: 0.09, alpha: 1)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        encoder.setCullMode(.none) // glDisable(GL_CULL_FACE)
        if let sampler = samplerState { encoder.setFragmentSamplerState(sampler, index: 0) }
        return encoder
    }

    /// eglSwapBuffers: ends the pass and presents in the Core Animation transaction (presentsWithTransaction).
    private func endFrame(_ commandBuffer: MTLCommandBuffer?, _ drawable: CAMetalDrawable?) {
        guard let commandBuffer = commandBuffer else { return }
        if let encoder = encoder {
            encoder.endEncoding()
            self.encoder = nil
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable?.present()
            lastCommandBuffer = commandBuffer
        }
    }

    /// Kotlin FloatArray(16) (column-major, as glUniformMatrix4fv with transpose false) -> simd_float4x4 (column c is
    /// m[c * 4 ..< c * 4 + 4]).
    static func matrix(_ m: [Float]) -> simd_float4x4 {
        return simd_float4x4(columns: (SIMD4<Float>(m[0], m[1], m[2], m[3]), SIMD4<Float>(m[4], m[5], m[6], m[7]),
                                       SIMD4<Float>(m[8], m[9], m[10], m[11]), SIMD4<Float>(m[12], m[13], m[14], m[15])))
    }

    // MARK: - android.opengl.Matrix (AOSP frameworks/base/opengl/java/android/opengl/Matrix.java), Float maths in order

    /// Matrix.setIdentityM(sm, 0).
    static func setIdentityM() -> [Float] {
        var sm = [Float](repeating: 0, count: 16)
        var i = 0
        while i < 16 { sm[i] = 0; i += 1 }
        i = 0
        while i < 16 { sm[i] = 1; i += 5 }
        return sm
    }

    /// Matrix.invertM: inverts a 4 x 4 matrix using Cramer's rule; false (and `mInv` untouched) when singular.
    @discardableResult
    static func invertM(mInv: inout [Float], mInvOffset: Int, m: [Float], mOffset: Int) -> Bool {
        // Invert a 4 x 4 matrix using Cramer's Rule

        // transpose matrix
        let src0: Float = m[mOffset + 0]
        let src4: Float = m[mOffset + 1]
        let src8: Float = m[mOffset + 2]
        let src12: Float = m[mOffset + 3]

        let src1: Float = m[mOffset + 4]
        let src5: Float = m[mOffset + 5]
        let src9: Float = m[mOffset + 6]
        let src13: Float = m[mOffset + 7]

        let src2: Float = m[mOffset + 8]
        let src6: Float = m[mOffset + 9]
        let src10: Float = m[mOffset + 10]
        let src14: Float = m[mOffset + 11]

        let src3: Float = m[mOffset + 12]
        let src7: Float = m[mOffset + 13]
        let src11: Float = m[mOffset + 14]
        let src15: Float = m[mOffset + 15]

        // calculate pairs for first 8 elements (cofactors)
        let atmp0: Float = src10 * src15
        let atmp1: Float = src11 * src14
        let atmp2: Float = src9 * src15
        let atmp3: Float = src11 * src13
        let atmp4: Float = src9 * src14
        let atmp5: Float = src10 * src13
        let atmp6: Float = src8 * src15
        let atmp7: Float = src11 * src12
        let atmp8: Float = src8 * src14
        let atmp9: Float = src10 * src12
        let atmp10: Float = src8 * src13
        let atmp11: Float = src9 * src12

        // calculate first 8 elements (cofactors)
        let dst0: Float = (atmp0 * src5 + atmp3 * src6 + atmp4 * src7)
            - (atmp1 * src5 + atmp2 * src6 + atmp5 * src7)
        let dst1: Float = (atmp1 * src4 + atmp6 * src6 + atmp9 * src7)
            - (atmp0 * src4 + atmp7 * src6 + atmp8 * src7)
        let dst2: Float = (atmp2 * src4 + atmp7 * src5 + atmp10 * src7)
            - (atmp3 * src4 + atmp6 * src5 + atmp11 * src7)
        let dst3: Float = (atmp5 * src4 + atmp8 * src5 + atmp11 * src6)
            - (atmp4 * src4 + atmp9 * src5 + atmp10 * src6)
        let dst4: Float = (atmp1 * src1 + atmp2 * src2 + atmp5 * src3)
            - (atmp0 * src1 + atmp3 * src2 + atmp4 * src3)
        let dst5: Float = (atmp0 * src0 + atmp7 * src2 + atmp8 * src3)
            - (atmp1 * src0 + atmp6 * src2 + atmp9 * src3)
        let dst6: Float = (atmp3 * src0 + atmp6 * src1 + atmp11 * src3)
            - (atmp2 * src0 + atmp7 * src1 + atmp10 * src3)
        let dst7: Float = (atmp4 * src0 + atmp9 * src1 + atmp10 * src2)
            - (atmp5 * src0 + atmp8 * src1 + atmp11 * src2)

        // calculate pairs for second 8 elements (cofactors)
        let btmp0: Float = src2 * src7
        let btmp1: Float = src3 * src6
        let btmp2: Float = src1 * src7
        let btmp3: Float = src3 * src5
        let btmp4: Float = src1 * src6
        let btmp5: Float = src2 * src5
        let btmp6: Float = src0 * src7
        let btmp7: Float = src3 * src4
        let btmp8: Float = src0 * src6
        let btmp9: Float = src2 * src4
        let btmp10: Float = src0 * src5
        let btmp11: Float = src1 * src4

        // calculate second 8 elements (cofactors)
        let dst8: Float = (btmp0 * src13 + btmp3 * src14 + btmp4 * src15)
            - (btmp1 * src13 + btmp2 * src14 + btmp5 * src15)
        let dst9: Float = (btmp1 * src12 + btmp6 * src14 + btmp9 * src15)
            - (btmp0 * src12 + btmp7 * src14 + btmp8 * src15)
        let dst10: Float = (btmp2 * src12 + btmp7 * src13 + btmp10 * src15)
            - (btmp3 * src12 + btmp6 * src13 + btmp11 * src15)
        let dst11: Float = (btmp5 * src12 + btmp8 * src13 + btmp11 * src14)
            - (btmp4 * src12 + btmp9 * src13 + btmp10 * src14)
        let dst12: Float = (btmp2 * src10 + btmp5 * src11 + btmp1 * src9)
            - (btmp4 * src11 + btmp0 * src9 + btmp3 * src10)
        let dst13: Float = (btmp8 * src11 + btmp0 * src8 + btmp7 * src10)
            - (btmp6 * src10 + btmp9 * src11 + btmp1 * src8)
        let dst14: Float = (btmp6 * src9 + btmp11 * src11 + btmp3 * src8)
            - (btmp10 * src11 + btmp2 * src8 + btmp7 * src9)
        let dst15: Float = (btmp10 * src10 + btmp4 * src8 + btmp9 * src9)
            - (btmp8 * src9 + btmp11 * src10 + btmp5 * src8)

        // calculate determinant
        let det: Float = src0 * dst0 + src1 * dst1 + src2 * dst2 + src3 * dst3

        if det == 0.0 {
            return false
        }

        // calculate matrix inverse
        let invdet: Float = 1.0 / det
        mInv[mInvOffset] = dst0 * invdet
        mInv[1 + mInvOffset] = dst1 * invdet
        mInv[2 + mInvOffset] = dst2 * invdet
        mInv[3 + mInvOffset] = dst3 * invdet

        mInv[4 + mInvOffset] = dst4 * invdet
        mInv[5 + mInvOffset] = dst5 * invdet
        mInv[6 + mInvOffset] = dst6 * invdet
        mInv[7 + mInvOffset] = dst7 * invdet

        mInv[8 + mInvOffset] = dst8 * invdet
        mInv[9 + mInvOffset] = dst9 * invdet
        mInv[10 + mInvOffset] = dst10 * invdet
        mInv[11 + mInvOffset] = dst11 * invdet

        mInv[12 + mInvOffset] = dst12 * invdet
        mInv[13 + mInvOffset] = dst13 * invdet
        mInv[14 + mInvOffset] = dst14 * invdet
        mInv[15 + mInvOffset] = dst15 * invdet

        return true
    }

    /// Matrix.multiplyMV: resultVec = lhsMat (column-major 4 x 4) x rhsVec.
    static func multiplyMV(resultVec: inout [Float], resultVecOffset: Int, lhsMat: [Float], lhsMatOffset: Int,
                           rhsVec: [Float], rhsVecOffset: Int) {
        let x: Float = rhsVec[rhsVecOffset + 0]
        let y: Float = rhsVec[rhsVecOffset + 1]
        let z: Float = rhsVec[rhsVecOffset + 2]
        let w: Float = rhsVec[rhsVecOffset + 3]
        let r0: Float = lhsMat[lhsMatOffset + 0] * x + lhsMat[lhsMatOffset + 4] * y + lhsMat[lhsMatOffset + 8] * z + lhsMat[lhsMatOffset + 12] * w
        let r1: Float = lhsMat[lhsMatOffset + 1] * x + lhsMat[lhsMatOffset + 5] * y + lhsMat[lhsMatOffset + 9] * z + lhsMat[lhsMatOffset + 13] * w
        let r2: Float = lhsMat[lhsMatOffset + 2] * x + lhsMat[lhsMatOffset + 6] * y + lhsMat[lhsMatOffset + 10] * z + lhsMat[lhsMatOffset + 14] * w
        let r3: Float = lhsMat[lhsMatOffset + 3] * x + lhsMat[lhsMatOffset + 7] * y + lhsMat[lhsMatOffset + 11] * z + lhsMat[lhsMatOffset + 15] * w
        resultVec[resultVecOffset + 0] = r0
        resultVec[resultVecOffset + 1] = r1
        resultVec[resultVecOffset + 2] = r2
        resultVec[resultVecOffset + 3] = r3
    }

    // MARK: - Test seams (unit tests only)

    /// Installs a camera frame as `onDrawFrame` publishes it (matrix = the view-projection, size in px).
    func installCameraFrameForTests(matrix: [Float], width: Int, height: Int) {
        cameraFrame = CameraFrame(matrix: matrix, width: width, height: height)
    }

    /// Installs the sprite regions of a resident texture key (what `upload` records).
    func installSpriteRegionsForTests(key: String, regions: [ADrawableRes: TripleShotSpriteRegion]) {
        spriteRegions[key] = regions
    }
}
