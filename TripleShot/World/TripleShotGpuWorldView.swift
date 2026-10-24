import Foundation
import Metal
import QuartzCore
import UIKit

// Port of view/TripleShotGpuWorldView.kt (TripleShotGame 6c38131), statement by statement (spec 06 sections 3.5, 4.1-4.4,
// 4.11, 8 and 9.3): TripleShotSpriteRegion, TripleShotPreparedTexture, TripleShotGpuWorldView and
// TripleShotWorldHostView. The texture work of `decode` / `prepareActor` lives in TripleShotTextureFactory.swift.
//
// GLSurfaceView -> an AView whose layer is a CAMetalLayer (no backing store: SurfaceView sets willNotDraw). Android's
// GL thread (RENDERMODE_CONTINUOUSLY) becomes an AChoreographer post-traversal handler: it runs on every 60 Hz vsync
// while the view is attached and not paused, after the TRAVERSAL phase in which the court views (subclasses of
// TripleShotWorldHostView, drawn in the traversal) built and submitted this frame's snapshot. The GL lifecycle is
// kept: `onSurfaceCreated` on the first frame after every attach (a new GL thread and EGL context on Android, so the
// view stays single-use: its worker is shut down on detach), `onSurfaceChanged` with the size in px, `onPause` /
// `onResume` from the host's window visibility (the GL thread pauses; resume resets the frame clock). No frame is
// drawn while the view is unsized or not shown (SurfaceView has no surface then).
//
// The worker (Executors.newSingleThreadExecutor) is a serial DispatchQueue; `generation` and isAttachedToWindow,
// which the Android worker reads across threads, are mirrored into a locked gate. The worker also makes the
// MTLTexture (MTLDevice is thread-safe) and hands the prepared texture to the renderer on the main thread, where one
// is installed per frame (Android: `pending.poll()` once per GL frame). `recreateContextForDiagnostics` and the host's
// `recreateWorldContextForDiagnostics` are debug-QA only (TripleShotQaActivity) and are not ported (DESIGN 3).
//
// Units: everything is Android pixels (DESIGN 2.5 / 9): the surface (drawable) size is the view's px size, so
// project / screenGround / actorBounds work in the court views' px coordinates, and the overlay draws through an
// ACanvas in px.

/// Atlas UV rectangle (v down) and the frame's ORIGINAL pixel size.
struct TripleShotSpriteRegion: Hashable {
    var u0: Float
    var v0: Float
    var u1: Float
    var v1: Float
    var sourceWidth: Int
    var sourceHeight: Int

    init(u0: Float, v0: Float, u1: Float, v1: Float, sourceWidth: Int, sourceHeight: Int) {
        self.u0 = u0
        self.v0 = v0
        self.u1 = u1
        self.v1 = v1
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
    }

    /// Kotlin positional constructor form.
    init(_ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float, _ sourceWidth: Int, _ sourceHeight: Int) {
        self.init(u0: u0, v0: v0, u1: u1, v1: v1, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }
}

/// The worker's output. Region keys are drawable names (Android: resIds; 0 = the vector fallback).
struct TripleShotPreparedTexture: @unchecked Sendable {
    /// Kotlin region key `0` (the vector fallback's single full-texture region).
    static let VECTOR_REGION: ADrawableRes = ""

    var key: String
    var bitmap: ABitmap
    var regions: [ADrawableRes: TripleShotSpriteRegion]
    /// iOS: the GPU copy of `bitmap` (made by the worker; Android uploads on the GL thread).
    var texture: MTLTexture?

    init(key: String, bitmap: ABitmap, regions: [ADrawableRes: TripleShotSpriteRegion] = [:]) {
        self.key = key
        self.bitmap = bitmap
        self.regions = regions
        self.texture = nil
    }
}

/// The worker thread's view of `generation` and `isAttachedToWindow` (Android reads both fields from the worker).
private final class TripleShotGpuWorkerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var attached = false

    func set(generation: Int, attached: Bool) {
        lock.lock()
        self.generation = generation
        self.attached = attached
        lock.unlock()
    }

    /// `token == generation && isAttachedToWindow`.
    func allows(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation && attached
    }
}

/** Decode and atlas preparation run on a bounded worker, entirely outside the GL frame path. */
final class TripleShotGpuWorldView: AView, TripleShotWorldSink {
    override class var layerClass: AnyClass { return CAMetalLayer.self }

    private let worker = DispatchQueue(label: "com.appsbybros.minik.swish.TripleShotGpuWorldView.worker", qos: .userInitiated)
    /// `worker.isShutdown` (shutdownNow on detach; the worker is never recreated).
    private var workerShutdown = false
    private var scheduled = Set<String>()
    private var generation = 0 { didSet { syncGate() } }
    private var latest: TripleShotWorldSnapshot?
    private var premiumRenderer: TripleShotPremiumRenderer!
    private let gate = TripleShotGpuWorkerGate()
    /// isAttachedToWindow as the GL thread sees it (false from onDetachedFromWindow on).
    private var windowAttached = false
    /// GLSurfaceView.onPause / onResume.
    private var renderPaused = false
    /// The post-traversal handler (the GL thread) is registered.
    private var rendering = false
    /// A new GL thread / EGL context: onSurfaceCreated runs on the next frame.
    private var surfaceCreatedPending = true

    private var metalLayer: CAMetalLayer { return layer as! CAMetalLayer }

    override init() {
        super.init()
        premiumRenderer = TripleShotPremiumRenderer(
            context: nil,
            textureEvicted: { [weak self] key in
                self?.post { self?.scheduled.remove(key) }
            },
            contextCreated: { [weak self] in
                self?.post {
                    guard let self = self else { return }
                    self.generation += 1; self.scheduled.removeAll(); if let latest = self.latest { self.prepare(scene: latest) }
                }
            }
        )
        // setEGLContextClientVersion(2); setEGLConfigChooser(RGBA 8888, depth >= 16, MSAA 4/2/0) (the renderer's
        // device objects); preserveEGLContextOnPause = true (Metal keeps everything); RENDERMODE_CONTINUOUSLY.
        let metal = metalLayer
        metal.device = premiumRenderer.device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = true
        metal.presentsWithTransaction = true
        isOpaque = true
        setWillNotDraw(true)
        isAccessibilityElement = false
    }

    /// Kotlin `TripleShotGpuWorldView(context)`.
    convenience init(context: Any?) {
        self.init()
    }

    func submit(snapshot: TripleShotWorldSnapshot) {
        latest = snapshot; premiumRenderer.submit(scene: snapshot); prepare(scene: snapshot)
    }
    func project(p: CourtPoint) -> (first: Float, second: Float)? { return premiumRenderer.project(point: p) }
    func actorSocket(actor: TripleShotWorldActor, inFront: Bool = true) -> CourtPoint { return premiumRenderer.socket(actor: actor, inFront: inFront) }
    func screenGround(x: Float, y: Float) -> CourtPoint? { return premiumRenderer.screenGround(x: x, y: y) }
    func actorBounds(actor: TripleShotWorldActor) -> ARectF? { return premiumRenderer.actorBounds(actor: actor) }
    func isWorldReady() -> Bool { return premiumRenderer.ready }

    // Kotlin positional call forms (`gpuWorld.project(p)`, `gpuWorld.actorSocket(actor, inFront)`, ...).
    func project(_ p: CourtPoint) -> (first: Float, second: Float)? { return project(p: p) }
    func actorSocket(_ actor: TripleShotWorldActor, _ inFront: Bool = true) -> CourtPoint { return actorSocket(actor: actor, inFront: inFront) }
    func screenGround(_ x: Float, _ y: Float) -> CourtPoint? { return screenGround(x: x, y: y) }
    func actorBounds(_ actor: TripleShotWorldActor) -> ARectF? { return actorBounds(actor: actor) }

    /// GLSurfaceView.onResume (the GL thread runs again) + `queueEvent { premiumRenderer.resumeFrameClock() }`.
    func onResume() {
        renderPaused = false; updateRendering()
        premiumRenderer.resumeFrameClock()
    }

    /// GLSurfaceView.onPause: the GL thread stops rendering (the context is preserved).
    func onPause() {
        renderPaused = true; updateRendering()
    }

    private func prepare(scene: TripleShotWorldSnapshot) {
        let background = TripleShotCourtCatalog.find(id: scene.courtId).resolveBackgroundResId(context: nil, orientation: TripleShotGameOrientation.LANDSCAPE)
        let courtKey = "court:\(scene.courtId)"
        schedule(key: courtKey) {
            TripleShotPreparedTexture(key: courtKey, bitmap: try TripleShotTextureFactory.decode(id: background, maxEdge: 2048))
        }
        for actor in scene.actors {
            let id = actor.state.characterId ?? "bob"
            schedule(key: "actor:\(id)") { try TripleShotTextureFactory.prepareActor(id: id) }
        }
        for ball in scene.balls {
            let resource = ball.resource
            schedule(key: "ball:\(resource)") {
                TripleShotPreparedTexture(key: "ball:\(resource)", bitmap: try TripleShotTextureFactory.decode(id: resource, maxEdge: 256))
            }
        }
    }

    private func schedule(key: String, produce: @escaping @Sendable () throws -> TripleShotPreparedTexture) {
        // A scene can be submitted before attachment. Do not reserve a texture key
        // until its worker is allowed to prepare it, or the first frame can wait forever.
        if !isAttachedToWindow || workerShutdown || !scheduled.insert(key).inserted { return }
        let token = generation
        let gate = self.gate
        let device = premiumRenderer.device
        worker.async { [weak self] in
            if !gate.allows(token) { return }
            let started = ASystem.nanoTime()
            do {
                var prepared = try produce()
                if !gate.allows(token) { prepared.bitmap.recycle(); return }
                // GLUtils.texImage2D's copy, made here instead of on the render path (the bitmap is no longer needed).
                if let device = device, let texture = TripleShotTextureFactory.makeTexture(device: device, bitmap: prepared.bitmap) {
                    prepared.texture = texture
                    prepared.bitmap.recycle()
                }
                let result = prepared
                DispatchQueue.main.async {
                    self?.enqueuePrepared(result, token)
                }
                ALog.i("TRIPLE_TEXTURE", "prepared=\(key) ms=\((ASystem.nanoTime() - started) / 1_000_000)")
            } catch {
                ALog.e("TRIPLE_TEXTURE", "Failed \(key); retry on context recreation", error)
            }
        }
    }

    /// `premiumRenderer.enqueue(prepared)` on the render (main) thread, unless the generation changed meanwhile.
    private func enqueuePrepared(_ prepared: TripleShotPreparedTexture, _ token: Int) {
        if token != generation || !windowAttached { prepared.bitmap.recycle(); return }
        premiumRenderer.enqueue(texture: prepared)
    }

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        // GLSurfaceView.onAttachedToWindow: a (new) GL thread creates its EGL context on the first frame.
        windowAttached = true; syncGate()
        surfaceCreatedPending = true
        updateRendering()
    }

    override func onDetachedFromWindow() {
        generation += 1; workerShutdown = true; premiumRenderer.discardPending()
        // GLSurfaceView.onDetachedFromWindow: the GL thread exits.
        windowAttached = false; syncGate(); updateRendering()
        super.onDetachedFromWindow()
    }

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // SurfaceHolder.Callback.surfaceChanged -> GLSurfaceView.Renderer.onSurfaceChanged (surface size in px).
        metalLayer.drawableSize = CGSize(width: Swift.max(w, 1), height: Swift.max(h, 1))
        premiumRenderer.onSurfaceChanged(w: w, h: h)
    }

    private func syncGate() {
        gate.set(generation: generation, attached: windowAttached)
    }

    /// Starts or stops the GL thread equivalent (the per-vsync post-traversal render).
    private func updateRendering() {
        let shouldRender = windowAttached && !renderPaused
        if shouldRender == rendering { return }
        rendering = shouldRender
        if shouldRender {
            AChoreographer.getInstance().addPostTraversalHandler(self) { [weak self] _ in
                self?.renderTick()
            }
        } else {
            AChoreographer.getInstance().removePostTraversalHandler(self)
        }
    }

    /// One GL-thread iteration: onSurfaceCreated / onSurfaceChanged when due, then onDrawFrame.
    private func renderTick() {
        if width <= 0 || height <= 0 || !isShown { return }
        if surfaceCreatedPending {
            surfaceCreatedPending = false
            premiumRenderer.onSurfaceCreated()
            premiumRenderer.onSurfaceChanged(w: width, h: height)
        }
        premiumRenderer.onDrawFrame(layer: metalLayer)
    }
}

/// The Canvas overlay above the GL surface: weather, player labels and floor markers (Kotlin `object : View`).
private final class TripleShotWorldOverlayView: AView {
    weak var host: TripleShotWorldHostView?

    override init() {
        super.init()
        isAccessibilityElement = false
    }

    override func onDraw(_ canvas: ACanvas) {
        guard let host = host else { return }
        guard let scene = host.worldScene else { return }
        host.weather.draw(canvas: canvas, atmosphere: scene.atmosphere, width: width, height: height, nowMs: ASystemClock.uptimeMillis())
        host.textPaint.textSize = AResources.density * 9
        for a in scene.actors where !a.label.isEmpty {
            host.textPaint.color = a.labelColor
            if let p = host.gpuWorld.project(p: CourtPoint(x: a.position.x, y: a.position.y + 2.65, z: a.position.z)) {
                canvas.drawText(a.label, p.first, p.second, host.textPaint)
            }
        }
        host.textPaint.color = AColor.WHITE
        host.textPaint.textSize = AResources.density * 14
        for marker in scene.markers {
            if let p = host.gpuWorld.project(p: marker.position) { canvas.drawText(marker.text, p.first, p.second, host.textPaint) }
        }
    }
}

/** Android controls stay above this surface. The old views continue to own their simulation. */
class TripleShotWorldHostView: AFrameLayout {
    let gpuWorld = TripleShotGpuWorldView()
    private var courtAudio: BasketballAudio?
    fileprivate let weather = TripleShotAtmosphereRenderer()
    var worldScene: TripleShotWorldSnapshot?
    private var readyCallbacks: [() -> Void] = []
    private let loadingScrim: AView = {
        let view = AView()
        view.setBackgroundColor(argbInt(0xFF101724))
        return view
    }()
    private let loading = AProgressBar()
    func whenWorldReady(action: @escaping () -> Void) { if gpuWorld.isWorldReady() { post(action) } else { readyCallbacks.append(action) } }
    fileprivate let textPaint: APaint = {
        let paint = APaint(APaint.ANTI_ALIAS_FLAG)
        paint.color = AColor.WHITE; paint.textAlign = APaint.Align.CENTER; paint.typeface = ATypeface.DEFAULT_BOLD
        paint.setShadowLayer(3, 0, 2, AColor.BLACK)
        return paint
    }()
    private let overlay = TripleShotWorldOverlayView()

    override init() {
        super.init()
        overlay.host = self
        setWillNotDraw(false); addView(gpuWorld, AFrameLayout.LayoutParams(-1, -1)); addView(overlay, AFrameLayout.LayoutParams(-1, -1))
        addView(loadingScrim, AFrameLayout.LayoutParams(-1, -1))
        let size = (40 * AResources.density).toInt(); addView(loading, AFrameLayout.LayoutParams(size, size, AGravity.CENTER))
    }

    /// Kotlin `TripleShotWorldHostView(context, attrs)`.
    convenience init(context: Any?, attrs: Any? = nil) {
        self.init()
    }

    /// Android redraws the court views' onDraw (their snapshot builder) every vsync through present() ->
    /// postInvalidateOnAnimation(); they draw nothing on the canvas, so they run in the Choreographer traversal.
    override var drawsInTraversal: Bool { return true }

    func present(scene: TripleShotWorldSnapshot) {
        if isShown { if courtAudio == nil { courtAudio = BasketballAudio() }; courtAudio?.frame(scene) }
        worldScene = scene; gpuWorld.submit(snapshot: scene); overlay.invalidate(); postInvalidateOnAnimation()
        let ready = gpuWorld.isWorldReady(); loading.visibility = ready ? AView.GONE : AView.VISIBLE
        loadingScrim.visibility = ready ? AView.GONE : AView.VISIBLE
        if ready && !readyCallbacks.isEmpty {
            let actions = readyCallbacks; readyCallbacks.removeAll(); post { actions.forEach { $0() } }
        }
    }

    /// Kotlin positional call form `present(scene)`.
    func present(_ scene: TripleShotWorldSnapshot) { present(scene: scene) }

    override func onDetachedFromWindow() { courtAudio?.close(); courtAudio = nil; super.onDetachedFromWindow() }
    override func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool { return true }
    override func dispatchTouchEvent(_ ev: AMotionEvent) -> Bool {
        return !gpuWorld.isWorldReady() ? true : super.dispatchTouchEvent(ev)
    }
    override func onWindowVisibilityChanged(_ visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if childCount > 0 { if visibility == AView.VISIBLE { gpuWorld.onResume() } else { gpuWorld.onPause() } }
    }
}
