import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS stage 2 (2026-11-09): the court, camera and characters of Android MinikCrossPong 257e058 … fcfd6b2 (at
// dd94c09). Pins the camera transforms (a9140c3 CrossCamera, 5375378 ReceptionCamera), the shared close-camera preference
// (`cross/close_camera`, default off), the terrace foliage pass (3b52d51) and the traced front hands (4969038, d376d64, b0cdeb3,
// fcfd6b2). The court's numbers themselves (tilt, margin, fit, reach) are compared with the Kotlin source by
// Scripts/audit-multi-pong.py.
final class MultiStageTwoTests: XCTestCase {
    private let viewport = CGRect(x: 8, y: 74, width: 414, height: 678)

    // ---- Android CrossCamera (a9140c3, 5375378) ----

    /// The default whole-court view never zooms or slides, whatever the rally does.
    func testWholeCourtViewIsStationary() {
        var camera = CrossCamera()
        for _ in 0..<120 {
            camera.update(1.0 / 60, close: false, viewport: viewport, required: CGRect(x: 200, y: 400, width: 10, height: 10), holding: false)
        }
        XCTAssertEqual(1, camera.zoom)
        XCTAssertEqual(CGPoint(x: 123, y: 456), camera.painted(CGPoint(x: 123, y: 456)))
        XCTAssertEqual(.zero, camera.shift)
    }

    /// The close view zooms at most 1.48 times about the fixed centre of the court area (no tracking pan), and touches use the
    /// exact inverse.
    func testCloseCameraZoomsAboutAFixedPivotWithoutPan() {
        var camera = CrossCamera()
        let centre = CGPoint(x: viewport.midX, y: viewport.midY)
        for _ in 0..<600 {
            camera.update(1.0 / 60, close: true, viewport: viewport, required: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10), holding: false)
        }
        XCTAssertEqual(1.48, camera.zoom, accuracy: 1e-6)
        XCTAssertEqual(centre.x, camera.painted(centre).x, accuracy: 1e-9)
        XCTAssertEqual(centre.y, camera.painted(centre).y, accuracy: 1e-9)
        let p = CGPoint(x: 31, y: 642), back = camera.base(camera.painted(p))
        XCTAssertEqual(p.x, back.x, accuracy: 1e-9)
        XCTAssertEqual(p.y, back.y, accuracy: 1e-9)
        // A required area reaching the viewport's edge leaves no room to zoom.
        for _ in 0..<600 { camera.update(1.0 / 60, close: true, viewport: viewport, required: viewport, holding: false) }
        XCTAssertEqual(1, camera.zoom)
    }

    /// A held finger freezes the transform so a drag keeps its coordinates; a new layout resets it.
    func testCloseCameraFreezesWhileHoldingAndResets() {
        var camera = CrossCamera()
        let small = CGRect(x: viewport.midX - 5, y: viewport.midY - 5, width: 10, height: 10)
        camera.update(0.1, close: true, viewport: viewport, required: small, holding: false)
        let zoom = camera.zoom
        XCTAssertGreaterThan(zoom, 1)
        camera.update(0.1, close: true, viewport: viewport, required: small, holding: true)
        XCTAssertEqual(zoom, camera.zoom)
        // Android: (1 − e^(−dt / 0.65)) of the way while zooming in.
        XCTAssertEqual(1 + 0.48 * (1 - exp(-0.1 / 0.65)), zoom, accuracy: 1e-12)
        camera.reset()
        XCTAssertEqual(1, camera.zoom)
    }

    /// Android 5375378 ReceptionCamera: the classic court's reception zoom pivots at (50 %, 62 %) of the view and never pans.
    func testClassicReceptionZoomHasAFixedPivot() {
        var camera = CrossReceptionCamera()
        camera.update(0.05, assist: CrossReception(), local: 0, width: 400, height: 800, holding: false, zoomOwn: true, follow: true)
        XCTAssertEqual(200, Double(camera.focus.x), accuracy: 1e-9)
        XCTAssertEqual(496, Double(camera.focus.y), accuracy: 1e-9)
        XCTAssertEqual(0, camera.amount)
        XCTAssertEqual(CGPoint(x: 10, y: 20), camera.painted(CGPoint(x: 10, y: 20)))
    }

    /// Android a9140c3 `cross/close_camera`: one remembered close camera for every cross court, off by default.
    func testCloseCameraIsOffByDefaultAndRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "stage2-\(UUID())"))
        let preferences = MPPreferences(defaults)
        XCTAssertFalse(preferences.crossCloseCamera)
        preferences.crossCloseCamera = true
        XCTAssertTrue(MPPreferences(defaults).crossCloseCamera)
    }

    // ---- Android 3b52d51 SunsetTerrace foreground ----

    /// The traced foliage covers the painting's lower corners and leaves its middle (the court) open, in both orientations.
    func testTerraceFoliageCoversOnlyTheLowerCorners() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        for portrait in [true, false] {
            let path = MPXTerraceFoliage.path(portrait: portrait, in: rect)
            XCTAssertTrue(path.contains(CGPoint(x: 5, y: 995)), "\(portrait)")
            XCTAssertTrue(path.contains(CGPoint(x: 995, y: 995)), "\(portrait)")
            XCTAssertFalse(path.contains(CGPoint(x: 500, y: 500)), "\(portrait)")
            XCTAssertFalse(path.contains(CGPoint(x: 500, y: 990)), "\(portrait)")
        }
    }

    // ---- Android PongPlayerAtlas (a9140c3, 4969038, d376d64, b0cdeb3, fcfd6b2); needs the bundled pose art ----

    /// Minik, Mia, Flare and Kyra have traced front hands for all four phases, on the drawn pose and mirrored about the foot; other
    /// characters have none.
    func testFrontHandsFollowThePoseAndItsMirror() throws {
        let atlas = MPXPoseAtlas.shared
        try XCTSkipUnless(atlas.has("minik") && atlas.geometry("minik", .front, mirror: false, foot: .zero, height: 100, phase: 0) != nil, "pose art not bundled")
        let foot = CGPoint(x: 300, y: 400)
        for id in ["minik", "mia", "flare", "kyra"] {
            for phase in 0...3 {
                let hands = try XCTUnwrap(atlas.frontHands(id, mirror: false, foot: foot, height: 120, phase: phase)).boundingBoxOfPath
                let mirrored = try XCTUnwrap(atlas.frontHands(id, mirror: true, foot: foot, height: 120, phase: phase)).boundingBoxOfPath
                let pose = try XCTUnwrap(atlas.geometry(id, .front, mirror: false, foot: foot, height: 120, phase: phase)).bounds
                XCTAssertFalse(hands.isEmpty, "\(id) \(phase)")
                XCTAssertTrue(pose.intersects(hands), "\(id) \(phase)")
                XCTAssertEqual(Double(2 * foot.x - hands.maxX), Double(mirrored.minX), accuracy: 1e-6, "\(id) \(phase)")
                XCTAssertEqual(Double(hands.minY), Double(mirrored.minY), accuracy: 1e-6, "\(id) \(phase)")
            }
        }
        XCTAssertNil(atlas.frontHands("miniko", mirror: false, foot: foot, height: 120, phase: 0))
    }

    /// Android a9140c3: both shoes' floor supports (two points at most) lie in the bottom 16 % of the visible body.
    func testFloorSupportsAreBothShoes() throws {
        let atlas = MPXPoseAtlas.shared
        try XCTSkipUnless(atlas.has("gaya") && atlas.geometry("gaya", .side, mirror: false, foot: .zero, height: 100, phase: 0) != nil, "pose art not bundled")
        for phase in 0...3 {
            let soles = atlas.floorSupports("gaya", .side, mirror: false, foot: .zero, height: 100, phase: phase)
            let bounds = try XCTUnwrap(atlas.geometry("gaya", .side, mirror: false, foot: .zero, height: 100, phase: phase)).bounds
            XCTAssertTrue((1...2).contains(soles.count), "\(phase)")
            for sole in soles {
                XCTAssertGreaterThanOrEqual(Double(sole.y), Double(bounds.maxY) - Double(bounds.height) * 0.16 - 1, "\(phase)")
                XCTAssertLessThanOrEqual(Double(sole.y), Double(bounds.maxY), "\(phase)")
            }
        }
    }
}
