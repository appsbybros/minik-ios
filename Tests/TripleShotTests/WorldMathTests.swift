import XCTest
@testable import MinikTripleShot

// Area t-world parity tests (TripleShotWorldSnapshot / TripleShotWorldMath / TripleShotCourtMeshBuilder).
// 1. TripleShotWorldMathTest.kt (app/src/test/.../view) ported 1:1 with the same assertions.
// 2. Spec 06 section 9.6 reference values (float64 replica, tolerance 1e-3) and section 4.9 vertex counts.
// 3. Exact Float bit patterns and java.util.Arrays.hashCode(float[]) checksums produced on the JVM by compiling the
//    snapshot's own Kotlin (TripleShotWorldSnapshot.kt, TripleShotWorldMath.kt, TripleShotCourtMeshBuilder.kt,
//    dd722e5) with the harness work/t-world/harness/WorldGolden.kt; this file is generated from its output by
//    work/t-world/gen_tests.py. Regenerated for Android 6c38131 (the camera's maximumDistance 26 -> 42 changes the
//    camera script vectors); the spec-defaults literal below is patched by hand. Hashes use floatToIntBits (`toBits()`), so the NaN sign (x86 0xFFC00000 vs arm64
//    0x7FC00000) does not matter.

private func worldState() -> TripleShotPlayerRenderer.State {
    return TripleShotPlayerRenderer.State(x: 0, footY: 0, fineAim: 0, pullBack: 0, dribbleBouncePx: 0, hotHand: false)
}

/// java.util.Arrays.hashCode(float[]).
private func javaArrayHash(_ values: [Float]) -> Int32 {
    var h: Int32 = 1
    for f in values { h = h &* 31 &+ f.toBits() }
    return h
}

// MARK: - TripleShotWorldMathTest.kt

final class TripleShotWorldMathTest: XCTestCase {
    private func actor(_ id: String, _ x: Float, _ z: Float) -> TripleShotWorldActor {
        return TripleShotWorldActor(id: id, position: CourtPoint(x: x, y: 0, z: z), state: worldState(), controlled: id == "0")
    }

    private func scene(_ spread: Float = 1) -> TripleShotWorldSnapshot {
        return TripleShotWorldSnapshot(
            timeNanos: 0, courtId: "sunset_pulse", teamSize: 3,
            actors: (0..<6).map { actor("\($0)", Float($0 % 3 - 1) * spread, Float($0 / 3) * spread) },
            balls: [], hoops: [CourtPoint(x: 0, y: 3.35, z: -4)], atmosphere: .NONE)
    }

    func testProjectionPreservesPerspectiveAndCentresTheLookTarget() {
        var view = [Float](repeating: 0, count: 16); var lens = [Float](repeating: 0, count: 16)
        var vp = [Float](repeating: 0, count: 16)
        TripleShotWorldMath.lookAt(out: &view, eye: CourtPoint(x: 0, y: 4, z: 12), target: CourtPoint(x: 0, y: 1, z: 0))
        TripleShotWorldMath.perspective(out: &lens, fov: 44, aspect: 2); TripleShotWorldMath.multiply(out: &vp, a: lens, b: view)
        let centre = TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 0, y: 1, z: 0), width: 2000, height: 1000)!
        XCTAssertEqual(1000, centre.first, accuracy: 0.01); XCTAssertEqual(500, centre.second, accuracy: 0.01)
        let near = TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: 3), width: 2000, height: 1000)!.first - 1000
        let far = TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: -3), width: 2000, height: 1000)!.first - 1000
        XCTAssertTrue(near > far)
        XCTAssertNil(TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 0, y: 4, z: 20), width: 2000, height: 1000))
    }

    func testClusteredTeamStaysLargeAndSpreadTriggersASmoothDolly() {
        let camera = TripleShotWorldCamera(); camera.update(scene: scene(), aspect: 2, dt: 0.016)
        let close = camera.distance
        for _ in 0..<180 {
            let before = camera.distance; camera.update(scene: scene(5), aspect: 2, dt: Float(1) / 60)
            XCTAssertTrue(abs(camera.distance - before) < 1)
        }
        let wide = camera.distance; XCTAssertTrue(wide > close + 1)
        for _ in 0..<240 { camera.update(scene: scene(), aspect: 2, dt: Float(1) / 60) }
        XCTAssertTrue(camera.distance < wide - 1)
        XCTAssertTrue(camera.distance >= 10.3)
        XCTAssertEqual(camera.projection[5], 1 / ktan(22 * PI_F / 180), accuracy: 0.0001)
    }

    func testFramingIncludesAHighReleasedBallAndBothTeams() {
        let camera = TripleShotWorldCamera()
        var s = scene(); s.balls = [TripleShotWorldBall(position: CourtPoint(x: 0, y: 8, z: -2), resource: "")]
        camera.update(scene: s, aspect: 2, dt: 0.016)
        let p = TripleShotWorldMath.project(m: camera.viewProjection, p: s.balls[0].position, width: 2000, height: 1000)!
        XCTAssertTrue(p.second > 100, "High ball must remain below the HUD: \(p)")
        for it in s.actors {
            let foot = TripleShotWorldMath.project(m: camera.viewProjection, p: it.position, width: 2000, height: 1000)!
            XCTAssertTrue((Float(50)...Float(1950)).contains(foot.first) && (Float(100)...Float(990)).contains(foot.second))
        }
    }

    func testSingleFrameFocusChangeDoesNotSnapTheCamera() {
        let camera = TripleShotWorldCamera(); camera.update(scene: scene(), aspect: 2, dt: 0.016)
        let before = camera.focusX
        var moved = scene()
        moved.actors = scene().actors.map { a in
            var c = a; c.position = c.position.copy(x: c.position.x + 8); return c
        }
        camera.update(scene: moved, aspect: 2, dt: 0.016)
        XCTAssertTrue(abs(camera.focusX - before) < 0.5)
    }
}

// MARK: - Golden values (spec 06 section 9.6 and the JVM harness)

final class TripleShotWorldGoldenTest: XCTestCase {
    private func actor(_ id: String, _ x: Float, _ z: Float) -> TripleShotWorldActor {
        return TripleShotWorldActor(id: id, position: CourtPoint(x: x, y: 0, z: z), state: worldState(), controlled: id == "0")
    }

    private func scene(_ spread: Float = 1) -> TripleShotWorldSnapshot {
        return TripleShotWorldSnapshot(
            timeNanos: 0, courtId: "sunset_pulse", teamSize: 3,
            actors: (0..<6).map { actor("\($0)", Float($0 % 3 - 1) * spread, Float($0 / 3) * spread) },
            balls: [], hoops: [CourtPoint(x: 0, y: 3.35, z: -4)], atmosphere: .NONE)
    }

    private func assertProjected(_ p: (first: Float, second: Float)?, _ x: UInt32, _ y: UInt32,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let p = p else { return XCTFail("projection is nil", file: file, line: line) }
        XCTAssertEqual([p.first.bitPattern, p.second.bitPattern], [x, y], file: file, line: line)
    }

    private func assertPoint(_ p: CourtPoint, _ expected: [UInt32], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual([p.x.bitPattern, p.y.bitPattern, p.z.bitPattern], expected, file: file, line: line)
    }

    /// Kotlin `cameraHash`: 31 * h + floatToIntBits over focus, distance, view, projection, viewProjection.
    private func cameraHash(_ c: TripleShotWorldCamera, _ h0: Int32) -> Int32 {
        var h = h0
        func add(_ f: Float) { h = h &* 31 &+ f.toBits() }
        add(c.focusX); add(c.focusY); add(c.focusZ); add(c.distance)
        c.view.forEach { add($0) }; c.projection.forEach { add($0) }; c.viewProjection.forEach { add($0) }
        return h
    }

    private func assertMesh(_ mesh: TripleShotMesh, count: Int, floats: Int, hash: Int32, first8: [UInt32]?,
                            last8: [UInt32]?, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(mesh.count, count, name, file: file, line: line)
        XCTAssertEqual(mesh.vertices.count, floats, name, file: file, line: line)
        XCTAssertEqual(javaArrayHash(mesh.vertices), hash, name, file: file, line: line)
        if let first8 = first8 {
            XCTAssertEqual(Array(mesh.vertices.prefix(8)).map { $0.bitPattern }, first8, name, file: file, line: line)
        }
        if let last8 = last8 {
            XCTAssertEqual(Array(mesh.vertices.suffix(8)).map { $0.bitPattern }, last8, name, file: file, line: line)
        }
    }

    func testCourtPointKeepsKotlinDataClassEquality() {
        XCTAssertNotEqual(CourtPoint(x: 0, y: 0, z: 0), CourtPoint(x: -0.0, y: 0, z: 0))
        XCTAssertEqual(CourtPoint(x: .nan, y: 0, z: 0), CourtPoint(x: .nan, y: 0, z: 0))
        XCTAssertEqual(CourtPoint(x: 1, y: 2, z: 3), CourtPoint(x: 1, y: 2, z: 3))
        XCTAssertEqual([CourtPoint(x: 1, y: 2, z: 3)], [CourtPoint(x: 1, y: 2, z: 3)])
        XCTAssertEqual(Set([CourtPoint(x: .nan, y: 1, z: 1), CourtPoint(x: .nan, y: 1, z: 1)]).count, 1)
        XCTAssertEqual(CourtPoint(x: 1, y: 2, z: 3).copy(y: 5), CourtPoint(x: 1, y: 5, z: 3))
        XCTAssertEqual(TripleShotWorldCoordinates.solo(sourceX: 750, sourceY: 948, lift: 3.35).description,
                       "CourtPoint(x=3.332, y=3.35, z=0.0)")
    }

    func testDefaultsMatchKotlin() {
        let actor = TripleShotWorldActor(id: "a", position: CourtPoint(x: 0, y: 0, z: 0), state: worldState())
        XCTAssertFalse(actor.controlled); XCTAssertEqual(actor.team, 0); XCTAssertEqual(actor.label, "")
        XCTAssertEqual(actor.labelColor, AColor.WHITE); XCTAssertEqual(actor.labelColor, -1)
        let ball = TripleShotWorldBall(position: CourtPoint(x: 0, y: 0, z: 0), resource: "")
        XCTAssertNil(ball.owner); XCTAssertEqual(ball.rotation, 0); XCTAssertTrue(ball.inFront)
        let s = TripleShotWorldSnapshot(timeNanos: 0, courtId: "x", teamSize: 1, actors: [], balls: [], hoops: [], atmosphere: .NONE)
        XCTAssertTrue(s.markers.isEmpty); XCTAssertTrue(s.guides.isEmpty)
        XCTAssertEqual(s.rimShake, 0); XCTAssertEqual(s.netSway, 0); XCTAssertEqual(s.activeHoopIndex, 0)
        let spec = TripleShotCameraSpec()
        XCTAssertEqual([spec.fovY, spec.minimumDistance, spec.maximumDistance, spec.elevation], [44, 10.3, 42, 0.43])   // 6c38131 (1ddda77): maximumDistance 26 -> 42
        let camera = TripleShotWorldCamera()
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance], [0, 2, 0, 10.3])
        XCTAssertEqual(camera.view.count, 16); XCTAssertEqual(camera.viewProjection, [Float](repeating: 0, count: 16))
    }

    func testCoordinateMapsAndConstants() {
        assertPoint(TripleShotWorldCoordinates.solo(sourceX: 750, sourceY: 948, lift: 3.35), [0x40553F7D, 0x40566666, 0x00000000])
        assertPoint(TripleShotWorldCoordinates.solo(sourceX: 512, sourceY: 1250), [0x00000000, 0x00000000, 0x40A449BB])
        assertPoint(TripleShotWorldCoordinates.solo(sourceX: 333.3, sourceY: 1017.7, lift: 0.03), [0xC0201D7F, 0x3CF5C28F, 0x3F97AAD0])
        assertPoint(TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 304, lift: TripleShotWorldCoordinates.RIM_HEIGHT),
                    [0x00000000, 0x40566666, 0xC0F6F9DC])
        assertPoint(TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 758, lift: TripleShotWorldCoordinates.RIM_HEIGHT),
                    [0x00000000, 0x40566666, 0x40F6F9DC])
        assertPoint(TripleShotWorldCoordinates.team(sourceX: 1200.5, sourceY: 99.25, lift: 0.21), [0x40A43127, 0x3E570A3D, 0xC16ADF3C])
        XCTAssertEqual(TripleShotWorldCoordinates.RIM_HEIGHT.bitPattern, 0x40566666)
        XCTAssertEqual(TripleShotWorldMath.RIGHT_X.bitPattern, 0x3F55CD5B)
        XCTAssertEqual(TripleShotWorldMath.RIGHT_Z.bitPattern, 0xBF0CCCCD)
        // Spec 06 9.6: solo hoop (3.332, 3.35, 0), solo feet (0, 0, 5.134).
        let hoop = TripleShotWorldCoordinates.solo(sourceX: 750, sourceY: 948, lift: 3.35)
        XCTAssertEqual(hoop.x, 3.332, accuracy: 0.001); XCTAssertEqual(hoop.y, 3.35, accuracy: 0.001); XCTAssertEqual(hoop.z, 0, accuracy: 0.001)
        XCTAssertEqual(TripleShotWorldCoordinates.solo(sourceX: 512, sourceY: 1250).z, 5.134, accuracy: 0.001)
    }

    func testMatrixHelpersAreBitExact() {
        var view = [Float](repeating: 0, count: 16); var lens = [Float](repeating: 0, count: 16)
        var vp = [Float](repeating: 0, count: 16)
        TripleShotWorldMath.lookAt(out: &view, eye: CourtPoint(x: 0, y: 4, z: 12), target: CourtPoint(x: 0, y: 1, z: 0))
        TripleShotWorldMath.perspective(out: &lens, fov: 44, aspect: 2); TripleShotWorldMath.multiply(out: &vp, a: lens, b: view)
        XCTAssertEqual(view.map { $0.bitPattern }, [
            0x3F800000, 0x80000000, 0x00000000, 0x00000000,
            0x00000000, 0x3F785B42, 0x3E785B42, 0x00000000,
            0x80000000, 0xBE785B42, 0x3F785B42, 0x00000000,
            0x80000000, 0xBF785B40, 0xC149CA26, 0x3F800000
        ])
        XCTAssertEqual(lens.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(vp.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x4019AD0B, 0xBE795A16, 0xBE785B42,
            0x00000000, 0xBF19AD0B, 0xBF795A16, 0xBF785B42,
            0x00000000, 0xC019AD0A, 0x41442F83, 0x4149CA26
        ])
        assertProjected(TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 0, y: 1, z: 0), width: 2000, height: 1000), 0x447A0000, 0x43FA0000)
        assertProjected(TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: 3), width: 2000, height: 1000), 0x448D5AAF, 0x4414CC86)
        assertProjected(TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: -3), width: 2000, height: 1000), 0x44871FC2, 0x43DC88E1)
        XCTAssertNil(TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 0, y: 4, z: 20), width: 2000, height: 1000))
        // perspective() clears the whole array first (Kotlin out.fill(0f)).
        var dirty = [Float](repeating: 7, count: 16)
        TripleShotWorldMath.perspective(out: &dirty, fov: 60, aspect: 0.4615385)
        XCTAssertEqual(dirty.map { $0.bitPattern }, [
            0x40702D7E, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x3FDDB3D8, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        // Degenerate lookAt (eye == target) and a straight-down view use the coerceAtLeast(.001) floors.
        var same = [Float](repeating: 9, count: 16)
        TripleShotWorldMath.lookAt(out: &same, eye: CourtPoint(x: 1, y: 2, z: 3), target: CourtPoint(x: 1, y: 2, z: 3))
        XCTAssertEqual(same.map { $0.bitPattern }, [
            0x00000000, 0x80000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x80000000, 0x80000000, 0x00000000, 0x00000000,
            0x80000000, 0x80000000, 0x80000000, 0x3F800000
        ])
        var above = [Float](repeating: 0, count: 16)
        TripleShotWorldMath.lookAt(out: &above, eye: CourtPoint(x: 2, y: 10, z: -1), target: CourtPoint(x: 2, y: 0, z: -1))
        XCTAssertEqual(above.map { $0.bitPattern }, [
            0x00000000, 0x80000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x3F800000, 0x00000000,
            0x80000000, 0x80000000, 0x00000000, 0x00000000,
            0x80000000, 0x80000000, 0xC1200000, 0x3F800000
        ])
        let a = (0..<16).map { Float($0 * 3 % 7) * 0.5 - 1.25 }; let b = (0..<16).map { Float($0 * 5 % 11) * 0.3 - 1.1 }
        var ab = [Float](repeating: 0, count: 16); TripleShotWorldMath.multiply(out: &ab, a: a, b: b)
        XCTAssertEqual(ab.map { $0.bitPattern }, [
            0x40119999, 0x4034CCCD, 0xC00E6667, 0x400B3334,
            0xBFC66666, 0x401CCCCD, 0x403CCCCC, 0x3FACCCCE,
            0xBFA00000, 0x3FA00002, 0x40166667, 0x3FACCCCD,
            0x3F333332, 0x3D4CCD00, 0x3DCCCCC0, 0xBFF99999
        ])
        // project() rejects clip w <= 0.2 exactly.
        var m = [Float](repeating: 0, count: 16); m[15] = 0.2
        XCTAssertNil(TripleShotWorldMath.project(m: m, p: CourtPoint(x: 0, y: 0, z: 0), width: 100, height: 100))
        m[15] = 0.20000002
        assertProjected(TripleShotWorldMath.project(m: m, p: CourtPoint(x: 0, y: 0, z: 0), width: 100, height: 100), 0x42480000, 0x42480000)
        // Spec 06 9.6 (float64 replica, tolerance 1e-3).
        let specLens: [Float] = [1.237543, 0, 0, 0, 0, 2.475087, 0, 0, 0, 0, -1.004008, -1, 0, 0, -0.400802, 0]
        let specView: [Float] = [1, 0, 0, 0, 0, 0.970143, 0.242536, 0, 0, -0.242536, 0.970143, 0, 0, -0.970143, -12.611853, 1]
        for i in 0..<16 {
            XCTAssertEqual(lens[i], specLens[i], accuracy: 0.001); XCTAssertEqual(view[i], specView[i], accuracy: 0.001)
        }
        let near = TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: 3), width: 2000, height: 1000)!
        XCTAssertEqual(near.first, 1130.834, accuracy: 0.001); XCTAssertEqual(near.second, 595.196, accuracy: 0.001)
        let far = TripleShotWorldMath.project(m: vp, p: CourtPoint(x: 1, y: 1, z: -3), width: 2000, height: 1000)!
        XCTAssertEqual(far.first, 1080.992, accuracy: 0.001); XCTAssertEqual(far.second, 441.069, accuracy: 0.001)
    }

    func testCameraOnTheAndroidTestScene() {
        let camera = TripleShotWorldCamera(); camera.update(scene: scene(), aspect: 2, dt: 0.016)
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance].map { $0.bitPattern },
                       [0x00000000, 0x40000000, 0xBFC00000, 0x413A8B84])
        XCTAssertEqual(camera.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC7, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4113, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA61, 0x3F4469D8, 0x00000000,
            0xBF533328, 0xC01542E3, 0xC1454983, 0x3F800000
        ])
        XCTAssertEqual(camera.projection.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(camera.viewProjection.map { $0.bitPattern }, [
            0x3F844B72, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB1099, 0xBECA4113,
            0xBF2E3F00, 0xBF510A51, 0xBF453360, 0xBF4469D8,
            0xBF82AF3A, 0xC0B8B7A1, 0x413FAA42, 0x41454983
        ])
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: CourtPoint(x: -1, y: 0, z: 0), width: 2000, height: 1000), 0x4451FBF5, 0x442FFA40)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: CourtPoint(x: 0, y: 3.35, z: -4), width: 2000, height: 1000), 0x448C1C68, 0x439F3999)
        // Spec 06 9.6: focus (0, 2, -1.5), distance 11.659064, eye (6.412485, 7.013397, 8.237238).
        XCTAssertEqual(camera.distance, 11.659064, accuracy: 0.001)
        XCTAssertEqual(camera.focusX - camera.distance * TripleShotWorldMath.RIGHT_Z, 6.412485, accuracy: 0.001)
        XCTAssertEqual(camera.focusY + camera.distance * 0.43, 7.013397, accuracy: 0.001)
        XCTAssertEqual(camera.focusZ + camera.distance * TripleShotWorldMath.RIGHT_X, 8.237238, accuracy: 0.001)
        let specVp: [Float] = [1.033553, -0.537750, -0.507293, -0.505268, 0, 2.273786, -0.396611, -0.395028,
                               -0.680649, -0.816564, -0.770315, -0.767240, -1.020973, -5.772418, 11.979068, 12.330449]
        for i in 0..<16 { XCTAssertEqual(camera.viewProjection[i], specVp[i], accuracy: 0.001) }
        let minus1 = TripleShotWorldMath.project(m: camera.viewProjection, p: CourtPoint(x: -1, y: 0, z: 0), width: 2000, height: 1000)!
        XCTAssertEqual(minus1.first, 839.937, accuracy: 0.001); XCTAssertEqual(minus1.second, 703.910, accuracy: 0.001)
        let hoop = TripleShotWorldMath.project(m: camera.viewProjection, p: CourtPoint(x: 0, y: 3.35, z: -4), width: 2000, height: 1000)!
        XCTAssertEqual(hoop.first, 1120.888, accuracy: 0.001); XCTAssertEqual(hoop.second, 318.450, accuracy: 0.001)

        // 180 spread frames widen the dolly, 240 clustered frames tighten it again (every distance, bit for bit).
        var widen: [UInt32] = []; var hash: Int32 = 1
        for _ in 0..<180 {
            camera.update(scene: scene(5), aspect: 2, dt: Float(1) / 60); widen.append(camera.distance.bitPattern)
            hash = cameraHash(camera, hash)
        }
        XCTAssertEqual(widen, [
            0x413FE09D, 0x4144EED0, 0x4149B9CC, 0x414E450E, 0x415293E6, 0x4156A977,
            0x415A88BA, 0x415E3482, 0x4161AF7B, 0x4164FC2E, 0x41681D02, 0x416B143F,
            0x416DE40D, 0x41708E79, 0x41731574, 0x41757AD5, 0x4177C05A, 0x4179E7AC,
            0x417BF25B, 0x417DE1E5, 0x417FB7B2, 0x4180BA8D, 0x41818DB0, 0x418255DB,
            0x418313A1, 0x4183C78C, 0x4184721F, 0x418513D6, 0x4185AD27, 0x41863E81,
            0x4186C84F, 0x41874AF5, 0x4187C6D2, 0x41883C40, 0x4188AB94, 0x41891520,
            0x41897931, 0x4189D80F, 0x418A3200, 0x418A8745, 0x418AD81D, 0x418B24C2,
            0x418B6D6C, 0x418BB250, 0x418BF3A0, 0x418C318B, 0x418C6C3F, 0x418CA3E7,
            0x418CD8AB, 0x418D0AB1, 0x418D3A1E, 0x418D6714, 0x418D91B5, 0x418DBA1F,
            0x418DE06F, 0x418E04C2, 0x418E2732, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8
        ])
        XCTAssertEqual(hash, 1302796847)
        XCTAssertEqual(camera.distance, 17.785083, accuracy: 0.001)
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance].map { $0.bitPattern },
                       [0x00000000, 0x40000000, 0x3EFFDFA5, 0x418E47D8])
        XCTAssertEqual(camera.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC7, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4113, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA61, 0x3F4469D8, 0x00000000,
            0x3E8CBB00, 0xBFD61344, 0xC1A443CA, 0x3F800000
        ])
        XCTAssertEqual(camera.projection.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(camera.viewProjection.map { $0.bitPattern }, [
            0x3F844B72, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB1099, 0xBECA4113,
            0xBF2E3F00, 0xBF510A51, 0xBF453360, 0xBF4469D8,
            0x3EAE28F9, 0xC08476B5, 0x41A1B77F, 0x41A443CA
        ])
        var tighten: [UInt32] = []; hash = 1
        for _ in 0..<240 {
            camera.update(scene: scene(), aspect: 2, dt: Float(1) / 60); tighten.append(camera.distance.bitPattern)
            hash = cameraHash(camera, hash)
        }
        XCTAssertEqual(tighten, [
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8, 0x418E47D8,
            0x418E47D8, 0x418E47D8, 0x418D452C, 0x418C47D5, 0x418B4FB7, 0x418A5CB7,
            0x41896EB9, 0x418885A4, 0x4187A15D, 0x4186C1CB, 0x4185E6D5, 0x41851062,
            0x41843E5B, 0x418370A9, 0x4182A735, 0x4181E1E8, 0x418120AC, 0x4180636C,
            0x417F5426, 0x417DE919, 0x417C8588, 0x417B294C, 0x4179D43E, 0x41788638,
            0x41773F15, 0x4175FEB1, 0x4174C4E8, 0x41739197, 0x4172649C, 0x41713DD6,
            0x41701D23, 0x416F0264, 0x416DED7A, 0x416CDE45, 0x416BD4A8, 0x416AD085,
            0x4169D1BF, 0x4168D839, 0x4167E3D8, 0x4166F481, 0x41660A1A, 0x41652488,
            0x416443B2, 0x4163677E, 0x41628FD4, 0x4161BC9D, 0x4160EDC1, 0x41602328,
            0x415F5CBD, 0x415E9A69, 0x415DDC17, 0x415D21B1, 0x415C6B23, 0x415BB859,
            0x415B093E, 0x415A5DC0, 0x4159B5CB, 0x4159114C, 0x41587032, 0x4157D26A,
            0x415737E3, 0x4156A08B, 0x41560C52, 0x41557B27, 0x4154ECFB, 0x415461BD,
            0x4153D95E, 0x415353CF, 0x4152D101, 0x415250E5, 0x4151D36D, 0x4151588C,
            0x4150E033, 0x41506A55, 0x414FF6E6, 0x414F85D8, 0x414F171F, 0x414EAAAE,
            0x414E4079, 0x414DD875, 0x414D7296, 0x414D0ED1, 0x414CAD1A, 0x414C4D67,
            0x414BEFAD, 0x414B93E2, 0x414B39FB, 0x414AE1EF, 0x414A8BB3, 0x414A373F,
            0x4149E488, 0x41499386, 0x41494430, 0x4148F67C, 0x4148AA62, 0x41485FDA,
            0x414816DC, 0x4147CF5F, 0x4147895B, 0x414744C9, 0x414701A1, 0x4146BFDB,
            0x41467F70, 0x41464059, 0x4146028F, 0x4145C60B, 0x41458AC7, 0x414550BC,
            0x414517E3, 0x4144E036, 0x4144A9AF, 0x41447448, 0x41443FFB, 0x41440CC2,
            0x4143DA97, 0x4143A975, 0x41437956, 0x41434A35, 0x41431C0D, 0x4142EED8,
            0x4142C292, 0x41429736, 0x41426CBF, 0x41424328, 0x41421A6C, 0x4141F287,
            0x4141CB75, 0x4141A531, 0x41417FB7, 0x41415B03, 0x41413711, 0x414113DC,
            0x4140F161, 0x4140CF9C, 0x4140AE89, 0x41408E25, 0x41406E6C, 0x41404F5A,
            0x414030EC, 0x4140131F, 0x413FF5EF, 0x413FD959, 0x413FBD5A, 0x413FA1EF,
            0x413F8715, 0x413F6CC8, 0x413F5306, 0x413F39CC, 0x413F2117, 0x413F08E5,
            0x413EF132, 0x413ED9FC, 0x413EC341, 0x413EACFE, 0x413E9730, 0x413E81D6,
            0x413E6CEC, 0x413E5871, 0x413E4462, 0x413E30BD, 0x413E1D7F, 0x413E0AA7,
            0x413DF832, 0x413DE61F, 0x413DD46B, 0x413DC315, 0x413DB21A, 0x413DA179,
            0x413D912F, 0x413D813B, 0x413D719C, 0x413D624F, 0x413D5353, 0x413D44A6,
            0x413D3646, 0x413D2832, 0x413D1A69, 0x413D0CE8, 0x413CFFAF, 0x413CF2BB,
            0x413CE60C, 0x413CD9A0, 0x413CCD75, 0x413CC18B, 0x413CB5DF, 0x413CAA71,
            0x413C9F3F, 0x413C9448, 0x413C898B, 0x413C7F07, 0x413C74BA, 0x413C6AA4,
            0x413C60C3, 0x413C5716, 0x413C4D9C, 0x413C4454, 0x413C3B3D, 0x413C3256,
            0x413C299E, 0x413C2114, 0x413C18B7, 0x413C1087, 0x413C0882, 0x413C00A7
        ])
        XCTAssertEqual(hash, -1701351832)
        XCTAssertEqual(camera.distance, 11.750164, accuracy: 0.001)
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance].map { $0.bitPattern },
                       [0x00000000, 0x40000000, 0xBFBFFF99, 0x413C00A7])
        XCTAssertEqual(camera.view.map { $0.bitPattern }, [
            0x3F55CD5A, 0xBE5E7ACA, 0x3F015940, 0x00000000,
            0x00000000, 0x3F6B2DE8, 0x3ECA4114, 0x00000000,
            0xBF0CCCCD, 0xBEA8EA63, 0x3F4469D9, 0x00000000,
            0xBF5332C0, 0xC01542D4, 0xC146DFBA, 0x3F800000
        ])
        XCTAssertEqual(camera.projection.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(camera.viewProjection.map { $0.bitPattern }, [
            0x3F844B73, 0xBF09AA03, 0xBF01DDF8, 0xBF015940,
            0x00000000, 0x401185B6, 0xBECB109A, 0xBECA4114,
            0xBF2E3F01, 0xBF510A54, 0xBF453361, 0xBF4469D9,
            0xBF82AEF9, 0xC0B8B78E, 0x4141421A, 0x4146DFBA
        ])
    }

    func testCameraFramesAHighBallAndDampsAOneFrameJump() {
        let camera = TripleShotWorldCamera()
        var s = scene(); s.balls = [TripleShotWorldBall(position: CourtPoint(x: 0, y: 8, z: -2), resource: "")]
        camera.update(scene: s, aspect: 2, dt: 0.016)
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance].map { $0.bitPattern },
                       [0x00000000, 0x405DC28F, 0xBFC00000, 0x418CBDC3])
        XCTAssertEqual(camera.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC6, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4112, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA60, 0x3F4469D8, 0x00000000,
            0xBF533330, 0xC06B654E, 0xC19AF1CD, 0x3F800000
        ])
        XCTAssertEqual(camera.projection.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(camera.viewProjection.map { $0.bitPattern }, [
            0x3F844B72, 0xBF09AA00, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB1098, 0xBECA4112,
            0xBF2E3F00, 0xBF510A50, 0xBF453360, 0xBF4469D8,
            0xBF82AF3E, 0xC111A7FD, 0x41985BF2, 0x419AF1CD
        ])
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.balls[0].position, width: 2000, height: 1000), 0x447ECB9E, 0x4345E680)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[0].position, width: 2000, height: 1000), 0x4460279D, 0x4432E092)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[1].position, width: 2000, height: 1000), 0x446CD24A, 0x4437C0DD)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[2].position, width: 2000, height: 1000), 0x447A2AAE, 0x443CE407)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[3].position, width: 2000, height: 1000), 0x445635F2, 0x443A6211)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[4].position, width: 2000, height: 1000), 0x44632138, 0x443FAA0A)
        assertProjected(TripleShotWorldMath.project(m: camera.viewProjection, p: s.actors[5].position, width: 2000, height: 1000), 0x4470C52F, 0x44453D84)
        let snap = TripleShotWorldCamera(); snap.update(scene: scene(), aspect: 2, dt: 0.016)
        XCTAssertEqual(snap.focusX.bitPattern, 0x00000000)
        var moved = scene()
        moved.actors = scene().actors.map { a in var c = a; c.position = c.position.copy(x: c.position.x + 8); return c }
        snap.update(scene: moved, aspect: 2, dt: 0.016)
        XCTAssertEqual(snap.focusX.bitPattern, 0x3E4AC318)
        XCTAssertEqual([snap.focusX, snap.focusY, snap.focusZ, snap.distance].map { $0.bitPattern },
                       [0x3E4AC318, 0x40000000, 0xBFC00000, 0x413CE8F0])
        XCTAssertEqual(snap.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC7, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4113, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA61, 0x3F4469D8, 0x00000000,
            0xBF7D88F0, 0xC012820D, 0xC1497654, 0x3F800000
        ])
        XCTAssertEqual(snap.projection.map { $0.bitPattern }, [
            0x3F9E67D2, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(snap.viewProjection.map { $0.bitPattern }, [
            0x3F844B72, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB1099, 0xBECA4113,
            0xBF2E3F00, 0xBF510A51, 0xBF453360, 0xBF4469D8,
            0xBF9CE156, 0xC0B54F5D, 0x4143DB5B, 0x41497654
        ])
    }

    func testCameraSoloPortraitAndTeamLandscapeFraming() {
        // Spec 06 9.6: solo portrait 1080x2340, hoop solo(750, 948, 3.35), one controlled actor at solo(512, 1250).
        let soloHoop = TripleShotWorldCoordinates.solo(sourceX: 750, sourceY: 948, lift: 3.35)
        let soloFoot = TripleShotWorldCoordinates.solo(sourceX: 512, sourceY: 1250)
        let solo = TripleShotWorldCamera()
        let human = TripleShotWorldActor(id: "human", position: soloFoot, state: worldState(), controlled: true, team: 1)
        solo.update(scene: TripleShotWorldSnapshot(timeNanos: 0, courtId: "enchanted_forest", teamSize: 1, actors: [human],
                                                   balls: [], hoops: [soloHoop], atmosphere: .NONE),
                    aspect: Float(1080) / 2340, dt: Float(1) / 60)
        XCTAssertEqual([solo.focusX, solo.focusY, solo.focusZ, solo.distance].map { $0.bitPattern },
                       [0x400C3958, 0x40000000, 0x402449BB, 0x41A9746C])
        XCTAssertEqual(solo.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC8, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4114, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA62, 0x3F4469D8, 0x00000000,
            0xBED603A0, 0xBF03B138, 0xC1D763BE, 0x3F800000
        ])
        XCTAssertEqual(solo.projection.map { $0.bitPattern }, [
            0x40AB9B23, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(solo.viewProjection.map { $0.bitPattern }, [
            0x408F51BB, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB109A, 0xBECA4114,
            0xC03CC43F, 0xBF510A53, 0xBF453360, 0xBF4469D8,
            0xC00F761D, 0xBFA2F992, 0x41D50BE8, 0x41D763BE
        ])
        assertProjected(TripleShotWorldMath.project(m: solo.viewProjection, p: soloHoop, width: 1080, height: 2340), 0x444E94EE, 0x446CD3DE)
        assertProjected(TripleShotWorldMath.project(m: solo.viewProjection, p: soloFoot, width: 1080, height: 2340), 0x430393C7, 0x44B506C7)
        XCTAssertEqual(solo.focusX, 2.1910, accuracy: 0.001); XCTAssertEqual(solo.focusY, 2, accuracy: 0.001)
        XCTAssertEqual(solo.focusZ, 2.5670, accuracy: 0.001); XCTAssertEqual(solo.distance, 21.1819, accuracy: 0.001)
        let hoopOnScreen = TripleShotWorldMath.project(m: solo.viewProjection, p: soloHoop, width: 1080, height: 2340)!
        XCTAssertEqual(hoopOnScreen.first, 826.33, accuracy: 0.01); XCTAssertEqual(hoopOnScreen.second, 947.31, accuracy: 0.01)
        let feetOnScreen = TripleShotWorldMath.project(m: solo.viewProjection, p: soloFoot, width: 1080, height: 2340)!
        XCTAssertEqual(feetOnScreen.first, 131.58, accuracy: 0.01); XCTAssertEqual(feetOnScreen.second, 1448.21, accuracy: 0.01)

        // Spec 06 9.6: team landscape 2340x1080, sunset hoops (0, 3.35, -/+7.718), six actors team(700 + 60i, 450 + 80(i%2)).
        let top = TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 304, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        let bottom = TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 758, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        let actors = (0..<6).map { i in
            TripleShotWorldActor(id: "p\(i)", position: TripleShotWorldCoordinates.team(sourceX: 700 + Float(60 * i),
                                 sourceY: 450 + Float(80 * (i % 2))), state: worldState())
        }
        let team = TripleShotWorldCamera()
        team.update(scene: TripleShotWorldSnapshot(timeNanos: 0, courtId: "sunset_pulse", teamSize: 3, actors: actors, balls: [],
                                                   hoops: [top, bottom], atmosphere: .COLORED_LIGHTS),
                    aspect: Float(2340) / 1080, dt: Float(1) / 60)
        XCTAssertEqual([team.focusX, team.focusY, team.focusZ, team.distance].map { $0.bitPattern },
                       [0x3E656040, 0x40000000, 0xC0781063, 0x415F2080])
        XCTAssertEqual(team.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC7, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4113, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA61, 0x3F4469D8, 0x00000000,
            0xC0146878, 0xC0445084, 0xC151C052, 0x3F800000
        ])
        XCTAssertEqual(team.projection.map { $0.bitPattern }, [
            0x3F923873, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(team.viewProjection.map { $0.bitPattern }, [
            0x3F743C83, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB1099, 0xBECA4113,
            0xBF20D7B1, 0xBF510A51, 0xBF453360, 0xBF4469D8,
            0xC029889C, 0xC0F2F29E, 0x414C2DDB, 0x4151C052
        ])
        XCTAssertEqual(team.focusX, 0.2240, accuracy: 0.001); XCTAssertEqual(team.focusY, 2, accuracy: 0.001)
        XCTAssertEqual(team.focusZ, -3.8760, accuracy: 0.001); XCTAssertEqual(team.distance, 13.9454, accuracy: 0.001)

        // No actors, balls or hoops: target (0, 2, 0), minimum distance.
        let empty = TripleShotWorldCamera()
        empty.update(scene: TripleShotWorldSnapshot(timeNanos: 0, courtId: "sunset_pulse", teamSize: 3, actors: [], balls: [],
                                                    hoops: [], atmosphere: .NONE), aspect: 1.5, dt: Float(1) / 60)
        XCTAssertEqual([empty.focusX, empty.focusY, empty.focusZ, empty.distance].map { $0.bitPattern },
                       [0x00000000, 0x40000000, 0x00000000, 0x4124CCCD])
        XCTAssertEqual(empty.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC8, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4114, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA62, 0x3F4469D8, 0x00000000,
            0x80000000, 0xBFEB2DE6, 0xC14007E4, 0x3F800000
        ])
        XCTAssertEqual(empty.projection.map { $0.bitPattern }, [
            0x3FD33518, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(empty.viewProjection.map { $0.bitPattern }, [
            0x3FB06498, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB109A, 0xBECA4114,
            0xBF6853FF, 0xBF510A53, 0xBF453360, 0xBF4469D8,
            0x00000000, 0xC09185B4, 0x413A633E, 0x414007E4
        ])
        // A non-default spec (Kotlin keeps the parameters although only the defaults are used).
        let custom = TripleShotWorldCamera(spec: TripleShotCameraSpec(fovY: 50, minimumDistance: 8, maximumDistance: 12, elevation: 0.6))
        custom.update(scene: scene(3), aspect: 1.2, dt: 0.03)
        XCTAssertEqual([custom.focusX, custom.focusY, custom.focusZ, custom.distance].map { $0.bitPattern },
                       [0x00000000, 0x40000000, 0xBF000000, 0x41400000])
        XCTAssertEqual(custom.view.map { $0.bitPattern }, [
            0x3F55CD5A, 0xBE90E1CC, 0x3EF17852, 0x00000000,
            0x00000000, 0x3F5B84A8, 0x3F03B5FF, 0x00000000,
            0xBF0CCCCD, 0xBEDC0028, 0x3F375576, 0x00000000,
            0xBE8CCCD0, 0xBFF704AC, 0xC16AA4AC, 0x3F800000
        ])
        XCTAssertEqual(custom.projection.map { $0.bitPattern }, [
            0x3FE4BF55, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x40093F9A, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(custom.viewProjection.map { $0.bitPattern }, [
            0x3FBF0AAF, 0xBF1B59AA, 0xBEF27015, 0xBEF17852,
            0x00000000, 0x3FEB610F, 0xBF043D24, 0xBF03B5FF,
            0xBF7B9F44, 0xBF6BE57C, 0xBF381193, 0xBF375576,
            0xBEFB9F4A, 0xC0846EDF, 0x41652BBF, 0x416AA4AC
        ])
    }

    /// Kotlin `scriptScene(frame)`: deterministic scenes that exercise every camera branch (empty lists, held and loose
    /// balls, an out-of-range activeHoopIndex, portrait/landscape aspects, dt clamping, the dolly state machine).
    private func scriptScene(_ frame: Int) -> (scene: TripleShotWorldSnapshot, aspect: Float, dt: Float) {
        let team = frame < 300
        let count = frame % 97 == 0 ? 0 : 1 + (frame / 50) % 6
        let controlledIndex = frame % 3 == 0 ? -1 : (frame / 100) % max(1, count)
        var actors: [TripleShotWorldActor] = []
        for i in 0..<count {
            let x: Float = Float((frame * 7 + i * 13) % 40) * 0.25 - 5
            let z: Float = Float((frame * 3 + i * 11) % 30) * 0.3 - 4.5
            let y: Float = Float((frame + i * 5) % 20) * 0.05
            actors.append(TripleShotWorldActor(id: "a\(i)", position: CourtPoint(x: x, y: y, z: z), state: worldState(),
                                               controlled: i == controlledIndex, team: 1 + i % 2))
        }
        var balls: [TripleShotWorldBall] = []
        if frame % 4 != 0 {
            let bx: Float = Float((frame * 5) % 50) * 0.2 - 5
            let by: Float = Float((frame * 11) % 90) * 0.1
            let bz: Float = Float((frame * 13) % 40) * 0.25 - 5
            balls.append(TripleShotWorldBall(position: CourtPoint(x: bx, y: by, z: bz), resource: "", owner: frame % 3 == 0 ? "a0" : nil))
        }
        let hoops: [CourtPoint]
        if frame % 101 == 0 {
            hoops = []
        } else if team {
            hoops = [CourtPoint(x: 0, y: 3.35, z: -7.718), CourtPoint(x: 0, y: 3.35, z: 7.718)]
        } else {
            hoops = [CourtPoint(x: 3.332, y: 3.35, z: 0)]
        }
        let active = team ? (frame / 30) % 3 : 0
        let aspect: Float = (frame / 150) % 2 == 0 ? Float(2340) / Float(1080) : Float(1080) / Float(2340)
        let dt: Float
        switch frame % 10 {
        case 0: dt = 0.1
        case 1: dt = 0
        case 2: dt = -0.01
        default: dt = Float(1) / 60
        }
        let s = TripleShotWorldSnapshot(timeNanos: Int64(frame), courtId: "sunset_pulse", teamSize: team ? 3 : 1, actors: actors,
                                        balls: balls, hoops: hoops, atmosphere: .NONE, activeHoopIndex: active)
        return (s, aspect, dt)
    }

    func testCameraScriptIsBitExactOverSixHundredFrames() {
        // (frame, running hash, focusX/Y/Z, distance) checkpoints printed by the Kotlin harness.
        let checkpoints: [(Int, Int32, [UInt32], UInt32)] = [
            (0, 1927905251, [0x00000000, 0x40000000, 0x00000000], 0x4124CCCD),
            (1, 1060254405, [0x00000000, 0x40000000, 0x00000000], 0x4124CCCD),
            (2, 1958123687, [0x00000000, 0x40000000, 0x00000000], 0x4124CCCD),
            (49, 882397963, [0xBE283843, 0x401F8D03, 0x3F82F4A0], 0x414E0288),
            (99, 1145646796, [0xBE4887CE, 0x402615B4, 0xC00D700F], 0x4169840B),
            (149, -1626513136, [0xBE55570B, 0x4033DA78, 0x3F933720], 0x4185535D),
            (199, 234380599, [0xBDCAF5EA, 0x4027CACD, 0xC00856B4], 0x41F3A583),
            (249, 542685856, [0xBE273CB8, 0x4024ED00, 0xBE8F9B58], 0x42054E34),
            (299, 106071993, [0xBD89B3C9, 0x40283264, 0xBFFF68FF], 0x420E538E),
            (349, -259722443, [0x3FD52791, 0x402B9FF1, 0xBE44A537], 0x41F1E5FF),
            (399, -1131341582, [0x3F996913, 0x40221281, 0xBEA2D489], 0x4190CF4E),
            (449, -1443204488, [0x3EE30AB2, 0x40220D7D, 0xBE70A8BA], 0x417B5C6F),
            (499, 801464452, [0x3F103905, 0x4034EF26, 0xBEAC2408], 0x41DBB01E),
            (549, 505241992, [0x3ED5AD45, 0x402C3D1C, 0xBEC01CC2], 0x41F3D309),
            (599, -1122657524, [0x3ED8B0B4, 0x40263544, 0xBE8077B8], 0x4201AD18),
        ]
        let camera = TripleShotWorldCamera()
        var hash: Int32 = 1
        var next = 0
        for frame in 0..<600 {
            let step = scriptScene(frame)
            camera.update(scene: step.scene, aspect: step.aspect, dt: step.dt)
            hash = cameraHash(camera, hash)
            if next < checkpoints.count && checkpoints[next].0 == frame {
                let c = checkpoints[next]
                XCTAssertEqual(hash, c.1, "frame \(frame)")
                XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ].map { $0.bitPattern }, c.2, "frame \(frame)")
                XCTAssertEqual(camera.distance.bitPattern, c.3, "frame \(frame)")
                next += 1
            }
        }
        XCTAssertEqual(next, checkpoints.count)
        XCTAssertEqual(hash, -1122657524)
        XCTAssertEqual([camera.focusX, camera.focusY, camera.focusZ, camera.distance].map { $0.bitPattern },
                       [0x3ED8B0B4, 0x40263544, 0xBE8077B8, 0x4201AD18])
        XCTAssertEqual(camera.view.map { $0.bitPattern }, [
            0x3F55CD59, 0xBE5E7AC8, 0x3F01593F, 0x00000000,
            0x00000000, 0x3F6B2DE6, 0x3ECA4114, 0x00000000,
            0xBF0CCCCC, 0xBEA8EA62, 0x3F4469D8, 0x00000000,
            0xBEFBA120, 0xC0181A68, 0xC211586C, 0x3F800000
        ])
        XCTAssertEqual(camera.projection.map { $0.bitPattern }, [
            0x40AB9B23, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x401E67D2, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0xBF808356, 0xBF800000,
            0x00000000, 0x00000000, 0xBECD35DE, 0x00000000
        ])
        XCTAssertEqual(camera.viewProjection.map { $0.bitPattern }, [
            0x408F51BB, 0xBF09AA01, 0xBF01DDF7, 0xBF01593F,
            0x00000000, 0x401185B4, 0xBECB109A, 0xBECA4114,
            0xC03CC43F, 0xBF510A53, 0xBF453360, 0xBF4469D8,
            0xC028AD1D, 0xC0BC3BF7, 0x42105322, 0x4211586C
        ])
    }

    func testMeshesMatchKotlinVertexForVertex() {
        // Spec 06 4.9 vertex counts: deck/metal/cyan/pink/foliage 390/1194/300/270/4704; baskets solo
        // 168/270/1788/4032/6 and team 336/540/3576/8064/12; floor/ground 6. Hashes cover every float.
        let soloHoop = TripleShotWorldCoordinates.solo(sourceX: 750, sourceY: 948, lift: 3.35)
        let teamTop = TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 304, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        let teamBottom = TripleShotWorldCoordinates.team(sourceX: 834, sourceY: 758, lift: TripleShotWorldCoordinates.RIM_HEIGHT)
        // Renderer: courtCenter = hoops.first().x, courtBack = hoops.first().z - 2.4f for solo; 0 / -11 for teams.
        let soloCenter = soloHoop.x; let soloBack = soloHoop.z - 2.4
        XCTAssertEqual([soloCenter.bitPattern, soloBack.bitPattern], [0x40553F7D, 0xC019999A])
        let soloSurround = TripleShotCourtSurround(centerX: soloCenter, back: soloBack)
        let teamSurround = TripleShotCourtSurround(centerX: 0, back: -11)
        let dupSurround = TripleShotCourtSurround(centerX: 0, back: 1)   // back + 10 == 11: distinct() drops a lamp row
        let soloBaskets = TripleShotBasketMeshes(hoops: [soloHoop])
        let teamBaskets = TripleShotBasketMeshes(hoops: [teamTop, teamBottom])
        let emptyBaskets = TripleShotBasketMeshes(hoops: [])
        assertMesh(TripleShotCourtMeshBuilder.floor(), count: 6, floats: 48, hash: 1731828225,
                   first8: [0xC1000000, 0x00000000, 0xC1300000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000],
                   last8: [0x41000000, 0x00000000, 0xC1300000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "floorDefault")
        assertMesh(TripleShotCourtMeshBuilder.ground(), count: 6, floats: 48, hash: 1422240649,
                   first8: [0xC2B40000, 0xBDB851EC, 0xC2B40000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000],
                   last8: [0x42B40000, 0xBDB851EC, 0xC2B40000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "ground")
        assertMesh(TripleShotCourtMeshBuilder.floor(centerX: soloCenter, back: soloBack), count: 6, floats: 48, hash: 424177712,
                   first8: [0xC0956042, 0x00000000, 0xC019999A, 0x00000000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000],
                   last8: [0x41354FDF, 0x00000000, 0xC019999A, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "floorSolo")
        assertMesh(TripleShotCourtMeshBuilder.floor(centerX: 0, back: -11), count: 6, floats: 48, hash: 1731828225,
                   first8: [0xC1000000, 0x00000000, 0xC1300000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000],
                   last8: [0x41000000, 0x00000000, 0xC1300000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "floorTeam")
        assertMesh(soloSurround.deck, count: 390, floats: 3120, hash: -462986328,
                   first8: [0xC0C56042, 0xBC75C290, 0x41500000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x4147B646, 0x3F251EB9, 0x40ACCCCC, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloDeck")
        assertMesh(soloSurround.metal, count: 1194, floats: 9552, hash: 1756776528,
                   first8: [0xC09C418A, 0x3DF5C28F, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x413D4FDF, 0x3E99999A, 0xC039999A, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloMetal")
        assertMesh(soloSurround.cyan, count: 300, floats: 2400, hash: 1038382929,
                   first8: [0xC09A2D0F, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x413D4FDF, 0x3EA7AE15, 0xC03147AE, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloCyan")
        assertMesh(soloSurround.pink, count: 270, floats: 2160, hash: -2360000,
                   first8: [0x413645A2, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x413E78D5, 0x3EB33333, 0x41240000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloPink")
        assertMesh(soloSurround.foliage, count: 4704, floats: 37632, hash: 1384612383,
                   first8: [0xC0B89376, 0x3F23D70A, 0xBFB33334, 0x00000000, 0x00000000, 0xBEB33333, 0x3F800000, 0x80000000],
                   last8: [0x414EF6AD, 0x3FA59989, 0x4134F13F, 0x3F800000, 0x00000000, 0xBEAF04C8, 0x3F800000, 0x3D99F0B3], "soloFoliage")
        assertMesh(teamSurround.deck, count: 390, floats: 3120, hash: 554379913,
                   first8: [0xC1180000, 0xBC75C290, 0x41500000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41126667, 0x3F251EB9, 0xC04CCCCC, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamDeck")
        assertMesh(teamSurround.metal, count: 1194, floats: 9552, hash: 521530155,
                   first8: [0xC10370A4, 0x3DF5C28F, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41080000, 0x3E99999A, 0xC1380000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamMetal")
        assertMesh(teamSurround.cyan, count: 300, floats: 2400, hash: -436134802,
                   first8: [0xC1026667, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41080000, 0x3EA7AE15, 0xC135EB85, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamCyan")
        assertMesh(teamSurround.pink, count: 270, floats: 2160, hash: 846059172,
                   first8: [0x4100F5C3, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x410928F6, 0x3EB33333, 0x41240000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamPink")
        assertMesh(teamSurround.foliage, count: 4704, floats: 37632, hash: -1908595757,
                   first8: [0xC111999A, 0x3F23D70A, 0xC1200000, 0x00000000, 0x00000000, 0xBEB33333, 0x3F800000, 0x80000000],
                   last8: [0x4119A6CE, 0x3FA59989, 0x4134F13F, 0x3F800000, 0x00000000, 0xBEAF04C8, 0x3F800000, 0x3D99F0B3], "teamFoliage")
        assertMesh(dupSurround.deck, count: 330, floats: 2640, hash: -1257441539,
                   first8: [0xC1180000, 0xBC75C290, 0x41500000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41126667, 0x3F251EB9, 0x410CCCCD, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "dupDeck")
        assertMesh(dupSurround.metal, count: 978, floats: 7824, hash: 611439498,
                   first8: [0xC10370A4, 0x3DF5C28F, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41080000, 0x3E99999A, 0x3EFFFFFF, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "dupMetal")
        assertMesh(dupSurround.foliage, count: 3528, floats: 28224, hash: 1237887733,
                   first8: [0xC111999A, 0x3F23D70A, 0x40000000, 0x00000000, 0x00000000, 0xBEB33333, 0x3F800000, 0x80000000],
                   last8: [0x4119A6CE, 0x3FA59989, 0x4134F13F, 0x3F800000, 0x00000000, 0xBEAF04C8, 0x3F800000, 0x3D99F0B3], "dupFoliage")
        assertMesh(dupSurround.cyan, count: 240, floats: 1920, hash: 399629105,
                   first8: [0xC1026667, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x41080000, 0x3EA7AE15, 0x3F2147AD, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "dupCyan")
        assertMesh(dupSurround.pink, count: 210, floats: 1680, hash: 681374855,
                   first8: [0x4100F5C3, 0x3E170A3D, 0x41400000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x410928F6, 0x3EB33333, 0x41240000, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "dupPink")
        assertMesh(soloBaskets.structure, count: 168, floats: 1344, hash: -997275559,
                   first8: [0x4036D917, 0x3EB851EC, 0xBF866666, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x404ED917, 0x40666666, 0xBFD33333, 0x3F800000, 0x00000000, 0xBF000000, 0x3F5B2678, 0xBE062C79], "soloStructure")
        assertMesh(soloBaskets.trim, count: 270, floats: 2160, hash: 18512155,
                   first8: [0x404A5E35, 0x3EDAE148, 0xBFB9EB84, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x40709BA6, 0x40800000, 0xBF1F5C29, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloTrim")
        assertMesh(soloBaskets.rims, count: 1788, floats: 14304, hash: 8171366,
                   first8: [0x404ED917, 0x3FAA3D71, 0xBFB9EB84, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x405BA5E3, 0x405947AE, 0xBF31EB85, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "soloRims")
        assertMesh(soloBaskets.nets, count: 4032, floats: 32256, hash: -1106454299,
                   first8: [0x40770B2E, 0x40566666, 0xBB83665B, 0x00000000, 0x00000000, 0x3F652F5F, 0x00000000, 0xBEE41FEC],
                   last8: [0x4067003D, 0x40266666, 0xBD66E9EB, 0x3F800000, 0x00000000, 0xBEFEC46C, 0x3F5DB3D7, 0x3D48BDBF], "soloNets")
        assertMesh(soloBaskets.glass, count: 6, floats: 48, hash: 1485825907,
                   first8: [0x4005E354, 0x4090A3D7, 0xBF2B851F, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x40924DD3, 0x4090A3D7, 0xBF2B851F, 0x3F800000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000], "soloGlass")
        assertMesh(teamBaskets.structure, count: 336, floats: 2688, hash: 379779801,
                   first8: [0xBEF33333, 0x3EB851EC, 0xC10C49BA, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3DCCCCCD, 0x40666666, 0x4115E354, 0x3F800000, 0x00000000, 0x3F000000, 0x3F5B2677, 0x3E062C7C], "teamStructure")
        assertMesh(teamBaskets.trim, count: 540, floats: 4320, hash: 1934841205,
                   first8: [0xBE2E147B, 0x3EDAE148, 0xC112BA5E, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3EDAE148, 0x40800000, 0x41050C4A, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamTrim")
        assertMesh(teamBaskets.rims, count: 3576, floats: 28608, hash: -2143717643,
                   first8: [0xBDCCCCCD, 0x3FAA3D71, 0xC112BA5E, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3DCCCCCD, 0x405947AE, 0x41029BA6, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "teamRims")
        assertMesh(teamBaskets.nets, count: 8064, floats: 64512, hash: -1413125627,
                   first8: [0x3F072EC3, 0x40566666, 0xC0F71AB6, 0x00000000, 0x00000000, 0x3F652F5B, 0x00000000, 0xBEE41FFD],
                   last8: [0x3E8E05FD, 0x40266666, 0x40F52C08, 0x3F800000, 0x00000000, 0xBEFEC46E, 0x3F5DB3D7, 0x3D48BD05], "teamNets")
        assertMesh(teamBaskets.glass, count: 12, floats: 96, hash: 737872939,
                   first8: [0xBF9EB852, 0x4090A3D7, 0xC1063540, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3F9EB852, 0x4090A3D7, 0x41063540, 0x3F800000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000], "teamGlass")
        assertMesh(emptyBaskets.structure, count: 0, floats: 0, hash: 1,
                   first8: nil, last8: nil, "emptyStructure")
        assertMesh(emptyBaskets.glass, count: 0, floats: 0, hash: 1,
                   first8: nil, last8: nil, "emptyGlass")
        assertMesh(TripleShotCourtMeshBuilder().box(x: 1.5, y: 0.25, z: -2, w: 0.7, h: 0.5, d: 1.3).build(), count: 30, floats: 240, hash: 232092312,
                   first8: [0x3F933333, 0x3F000000, 0xBFACCCCD, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3FECCCCD, 0x3F000000, 0xC029999A, 0x3F800000, 0x00000000, 0x00000000, 0x3F800000, 0x00000000], "primBox")
        assertMesh(TripleShotCourtMeshBuilder().quad(a: CourtPoint(x: 0, y: 1, z: 0), b: CourtPoint(x: 0, y: 0, z: 0), c: CourtPoint(x: 1, y: 0, z: 0), d: CourtPoint(x: 1, y: 1, z: 0), n: CourtPoint(x: 0, y: 0, z: 1), u0: 0.1, v0: 0.2, u1: 0.8, v1: 0.9).build(), count: 6, floats: 48, hash: 1212959638,
                   first8: [0x00000000, 0x3F800000, 0x00000000, 0x3DCCCCCD, 0x3E4CCCCD, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0x3F800000, 0x3F800000, 0x00000000, 0x3F4CCCCD, 0x3E4CCCCD, 0x00000000, 0x00000000, 0x3F800000], "primQuadUv")
        assertMesh(TripleShotCourtMeshBuilder().tube(a: CourtPoint(x: 0.3, y: 0.5, z: -1), b: CourtPoint(x: 0.3, y: 5.1, z: -1), r: 0.055, sides: 8).build(), count: 48, floats: 384, hash: -180529995,
                   first8: [0x3E99999A, 0x3F000000, 0xBF870A3D, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0xBF800000],
                   last8: [0x3E99999A, 0x3F000000, 0xBF870A3D, 0x3F800000, 0x00000000, 0x3F3504F3, 0x00000000, 0xBF3504F3], "primTubeVertical")
        assertMesh(TripleShotCourtMeshBuilder().tube(a: CourtPoint(x: 0, y: 3.6, z: -9.368), b: CourtPoint(x: 0, y: 3.75, z: -8.388), r: 0.10).build(), count: 36, floats: 288, hash: 1590387501,
                   first8: [0xBDCCCCCD, 0x40666666, 0xC115E354, 0x00000000, 0x00000000, 0xBF800000, 0x00000000, 0x00000000],
                   last8: [0xBDCCCCCD, 0x40666666, 0xC115E354, 0x3F800000, 0x00000000, 0xBF000000, 0x3F5B2678, 0xBE062C75], "primTubeSlant")
        assertMesh(TripleShotCourtMeshBuilder().tube(a: CourtPoint(x: 1, y: 1, z: 1), b: CourtPoint(x: 1, y: 1, z: 1), r: 0.2, sides: 3).build(), count: 18, floats: 144, hash: -125252095,
                   first8: nil, last8: nil, "primTubeDegenerate")
        assertMesh(TripleShotCourtMeshBuilder().ring(x: 3.332, y: 3.35, z: 0, radius: 0.55, wire: 0.045).build(), count: 1728, floats: 13824, hash: 286488349,
                   first8: [0x407592FC, 0x40566666, 0xBB40E04C, 0x00000000, 0x00000000, 0xBF7F73B1, 0x00000000, 0xBD85F118],
                   last8: [0x407545E5, 0x40566666, 0xBD8CFF51, 0x3F800000, 0x00000000, 0xBEFF73B1, 0x3F5DB3D7, 0x3D05F118], "primRing")
        assertMesh(TripleShotCourtMeshBuilder().ring(x: 0, y: 2.6, z: -7.718, radius: 0.295, wire: 0.012, segments: 32).build(), count: 1152, floats: 9216, hash: -1527743223,
                   first8: [0x3E90ECF3, 0x40266666, 0xC0F7037E, 0x00000000, 0x00000000, 0xBF7EC46E, 0x00000000, 0xBDC8BD05],
                   last8: [0x3E8E05FD, 0x40266666, 0xC0F8C7AF, 0x3F800000, 0x00000000, 0xBEFEC46E, 0x3F5DB3D7, 0x3D48BD05], "primRing32")
        assertMesh(TripleShotCourtMeshBuilder().leaf(x: -5.768, y: 0.64, z: 1.13, angle: Float(2.39996) * 5, length: 0.42 + 0.22 * ksin(10), rise: 0.46 + 0.38 * (0.5 + 0.5 * kcos(15)), width: 0.12).build(), count: 42, floats: 336, hash: 729146899,
                   first8: [0xC0B89375, 0x3F23D70A, 0x3F90A3D7, 0x00000000, 0x00000000, 0xBE97330A, 0x3F800000, 0x3E405E49],
                   last8: [0xC0B0BB4B, 0x3F8E4F86, 0x3F8493FC, 0x3F800000, 0x00000000, 0xBE97330A, 0x3F800000, 0x3E405E49], "primLeaf")
        assertMesh(TripleShotCourtMeshBuilder().box(x: 0, y: 0, z: 0, w: 1, h: 1, d: 1).box(x: 1, y: 1, z: 1, w: 2, h: 2, d: 2).ring(x: 0, y: 1, z: 0, radius: 1, wire: 0.1, segments: 3).build(), count: 168, floats: 1344, hash: -726584241,
                   first8: [0xBF000000, 0x3F000000, 0x3F000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3F800000],
                   last8: [0xBF0CCCCD, 0x3F800000, 0xBF478841, 0x3F800000, 0x00000000, 0xBE800000, 0x3F5DB3D7, 0x3EDDB3D8], "primChain")
        XCTAssertEqual(soloSurround.lights.flatMap { [$0.x, $0.y, $0.z] }.map { $0.bitPattern }, [
            0xC0B22D10, 0x409B3333, 0xBFB33334, 0xC0B22D10, 0x409B3333, 0x40466666,
            0xC0B22D10, 0x409B3333, 0x40F33333, 0xC0B22D10, 0x409B3333, 0x41300000,
            0x4143B646, 0x409B3333, 0xBFB33334, 0x4143B646, 0x409B3333, 0x40466666,
            0x4143B646, 0x409B3333, 0x40F33333, 0x4143B646, 0x409B3333, 0x41300000
        ])
        XCTAssertEqual(teamSurround.lights.flatMap { [$0.x, $0.y, $0.z] }.map { $0.bitPattern }, [
            0xC10E6667, 0x409B3333, 0xC1200000, 0xC10E6667, 0x409B3333, 0xC0B00000,
            0xC10E6667, 0x409B3333, 0xBF800000, 0xC10E6667, 0x409B3333, 0x41300000,
            0x410E6667, 0x409B3333, 0xC1200000, 0x410E6667, 0x409B3333, 0xC0B00000,
            0x410E6667, 0x409B3333, 0xBF800000, 0x410E6667, 0x409B3333, 0x41300000
        ])
        XCTAssertEqual(dupSurround.lights.flatMap { [$0.x, $0.y, $0.z] }.map { $0.bitPattern }, [
            0xC10E6667, 0x409B3333, 0x40000000, 0xC10E6667, 0x409B3333, 0x40D00000,
            0xC10E6667, 0x409B3333, 0x41300000, 0x410E6667, 0x409B3333, 0x40000000,
            0x410E6667, 0x409B3333, 0x40D00000, 0x410E6667, 0x409B3333, 0x41300000
        ])
        // Spec 06 4.9: solo lamps at x -5.568 and 12.232, y 4.85, z -1.4, 3.1, 7.6, 11.
        let lampX = soloSurround.lights.map { $0.x }; let lampZ = soloSurround.lights.map { $0.z }
        for (i, x) in [-5.568, -5.568, -5.568, -5.568, 12.232, 12.232, 12.232, 12.232].enumerated() {
            XCTAssertEqual(lampX[i], Float(x), accuracy: 0.001)
        }
        for (i, z) in [-1.4, 3.1, 7.6, 11, -1.4, 3.1, 7.6, 11].enumerated() { XCTAssertEqual(lampZ[i], Float(z), accuracy: 0.001) }
    }
}
