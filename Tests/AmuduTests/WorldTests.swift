import XCTest
@testable import MinikAmudu

/// Ports of Android `world/ArenaCameraTest.kt`, `world/LandscapeFramingTest.kt`, `world/StableLabelsTest.kt` and
/// `localization/PresentationLanguageTest.kt`.
final class WorldTests: XCTestCase {
    func testTouchProjectionMatchesWorldAtEveryCamera() {
        for size in [(1080.0, 2160.0), (1080.0, 2400.0), (720.0, 1280.0)] {
            for d in [20.0, 26.0, 40.0] {
                for x in [1.0, 10.0, 25.0] {
                    for y in [1.0, 12.0, 26.0] {
                        let c = ArenaCamera(x: 14.0, y: 14.0, distance: d)
                        let p = c.project(x, y, 0.0, size.0, size.1)
                        let q = c.ground(p.x, p.y, size.0, size.1)
                        XCTAssertEqual(x, q.x, accuracy: 0.0001)
                        XCTAssertEqual(y, q.y, accuracy: 0.0001)
                    }
                }
            }
        }
    }

    func testSmoothCameraConvergesWithoutOvershoot() {
        var c = ArenaCamera(x: 0.0, y: 0.0)
        let target = c.copy(x: 12.0, y: 20.0, distance: 22.0)
        for _ in 0..<600 {
            c = c.toward(target, 1.0 / 60)
            XCTAssertTrue(c.x <= 12 && c.y <= 20)
        }
        XCTAssertEqual(12.0, c.x, accuracy: 0.001)
    }

    func testShortAndWideScreensFitFullCourtAndPreserveGroundTouch() {
        for (w, h) in [(640.0, 300.0), (760.0, 360.0), (920.0, 420.0), (1200.0, 600.0)] {
            let left = 180.0
            let right = w - 12.0
            let top = 64.0
            let bottom = h - 12.0
            let points = [(0.6, 0.6), (27.4, 0.6), (0.6, 17.4), (27.4, 17.4)]
            let base = ArenaCamera(x: 14.0, y: 9.0, distance: 20.0, centerY: (top + (bottom - top) * 0.60) / h, centerX: (left + right) / 2 / w)
            let c = LandscapeFraming.fit(base, points, w, h, left, right, top, bottom, 3.8)
            for (x, y) in points {
                for z in [0.0, 3.8] {
                    let p = c.project(x, y, z, w, h)
                    XCTAssertTrue(p.x >= left && p.x <= right && p.y >= top && p.y <= bottom)
                }
                let p = c.project(x, y, 0.0, w, h)
                let back = c.ground(p.x, p.y, w, h)
                XCTAssertEqual(x, back.x, accuracy: 0.0001)
                XCTAssertEqual(y, back.y, accuracy: 0.0001)
            }
        }
    }

    func testPortraitDefaultsUnchangedAndRotationCentersFollowTarget() {
        let p = ArenaCamera(x: 8.0, y: 8.0)
        XCTAssertEqual(0.5, p.centerX)
        XCTAssertEqual(0.61, p.centerY)
        let t = p.copy(centerX: 0.63, centerY: 0.56)
        let moved = p.toward(t, 0.016)
        XCTAssertEqual(t.centerX, moved.centerX)
        XCTAssertEqual(t.centerY, moved.centerY)
    }

    func testUnchangedSceneDoesNotOscillateBetweenSlots() {
        let l = StableLabels()
        let bounds = LabelBox(x: 0, y: 0, w: 400, h: 650)
        let bodies = [LabelBox(x: 130, y: 250, w: 90, h: 150), LabelBox(x: 185, y: 350, w: 85, h: 140)]
        var first: [LabelBox]?
        for _ in 0..<500 {
            var used: [LabelBox] = []
            for i in 0...5 {
                used.append(l.place("p\(i)", 170 + Float(i) * 7, 385 + Float(i) * 10, 70, 22, bounds, bodies, used, 24))
            }
            if let first {
                XCTAssertEqual(first, used)
            } else {
                first = used
            }
        }
    }

    func testTinyMotionKeepsPreviousSlotAndEdgeTargetsRemainTouchable() {
        let l = StableLabels()
        let b = LabelBox(x: 8, y: 100, w: 380, h: 500)
        let a = l.place("a", 200, 300, 80, 24, b, [LabelBox(x: 160, y: 295, w: 100, h: 50)], [], 24)
        let next = l.place("a", 200.1, 300.1, 80, 24, b, [], [], 24)
        XCTAssertEqual(a.x + 0.1, next.x, accuracy: 0.02)
        XCTAssertEqual(a.y + 0.1, next.y, accuracy: 0.02)
        let edge = l.place("far", -2000, 2500, 80, 24, b, [], [], 24)
        XCTAssertTrue(edge.x >= b.x && edge.right <= b.right && edge.y >= b.y && edge.bottom <= b.bottom)
    }

    func testRecentControlsAndCameraHintsResolveForEverySupportedTranslation() {
        let old = AppText.language
        defer { AppText.configure(old) }
        let keys = ["Your question", "Your colour ranks", "Game orientation", "Hard · aim the arc; swipe for power", "Standard · tap anywhere to throw",
                    "Action view · switch", "Choose a player", "Learn to play with Minik", "Learn to play with Mia"]
        for lang in ["es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for key in keys {
                let translated = AppText.t(key)
                XCTAssertFalse(Kotlin.isBlank(translated), "Empty \(lang): \(key)")
                XCTAssertNotEqual(key, translated, "English fallback in \(lang): \(key)")
            }
        }
    }
}
