import ImageIO
import XCTest
@testable import MinikTripleShot

// Area t-visuals parity tests: TripleShotPlayerRenderer, TripleShotCharacterVisuals (catalog), BasketballSpriteCompletion,
// BasketballSupplement, BasketballFeedbackArt and TripleShotShotPresentation (spec 07).
// 1. TripleShotShotPresentationTest.kt (app/src/test/.../view) ported 1:1 with the same assertions.
// 2. RefinementTest.everyCharacterHasRealDecodedDirectionalActionFrames (androidTest) ported.
// 3. JVM golden vectors. work/t-visuals/src/Main.kt compiles the snapshot's own Kotlin (dd722e5: the six files of this
//    area plus TripleShotPhysics/TripleShotCharacters/TripleShotModels) against stub Android classes and prints
//    golden.txt; work/t-visuals/gen_tests.py embeds it at the end of this file. Regenerated for Android 6c38131
//    (the same harness and generator over the 6c38131 copies of those nine files: coach67 frames, playfulHold, bob
//    heights, the renderer's crossover fields). Floats are compared by bit pattern
//    (`%08x` of floatToRawIntBits). Covered: the fully resolved catalog of the 12 roster ids (every slot: drawable,
//    anchors, socket, display height, foreground rect), digests of the raw tables (including the frames that the
//    catalog composition overrides), heldBallPosition / worldFrame / visualTopY for 1500 states at densities 1, 2
//    and 3, the spec 07 section 4.5 table, winnerJumpOffsetPx and the shot bridge.
// 4. Every drawable the catalog files reference is a drawable-nodpi image with the recorded pixel size.
// 5. The vector fallback (the 512 x 512 texture GpuWorldView rasterises for ids without sprites) and the legacy
//    Canvas paths are drawn into bitmaps and probed at points well inside each shape.

// MARK: - Encodings shared with the Kotlin harness

/// Kotlin `String.format("%08x", java.lang.Float.floatToRawIntBits(f))`.
private func fb(_ f: Float) -> String {
    return String(format: "%08x", f.bitPattern)
}

private func fbo(_ f: Float?) -> String {
    guard let f = f else { return "-" }
    return fb(f)
}

/// Harness `fr(frame)`: drawable, anchors, socket, display height, foreground rect.
private func fr(_ f: CharacterSpriteFrame?) -> String {
    guard let f = f else { return "-" }
    let rect: String
    if let r = f.ballForegroundRect01 {
        rect = "\(fb(r.left)):\(fb(r.top)):\(fb(r.right)):\(fb(r.bottom))"
    } else {
        rect = "-"
    }
    return "\(f.resId),\(fb(f.anchorX01)),\(fb(f.anchorY01)),\(fbo(f.ballSourceX)),\(fbo(f.ballSourceY)),"
        + "\(fbo(f.targetHeightDp)),\(rect)"
}

/// Harness `setEncoding(set)`: every field of a set, one line per slot, in a fixed order.
private func setEncoding(_ s: CharacterSpriteSet) -> String {
    var l: [String] = []
    l.append("set=\(s.characterId),\(fb(s.referenceHeightPx)),\(fb(s.referenceHeightDp))")
    l.append("idleBack=\(fr(s.idleBack))")
    l.append("idleFront=\(fr(s.idleFront))")
    l.append("idleSide=\(fr(s.idleSide))")
    let shots: [(String, CharacterShotSprites)] = [("shotBack", s.shotBack), ("shotSide", s.shotSide), ("shotFront", s.shotFront)]
    for (n, sh) in shots {
        l.append("\(n).low=\(fr(sh.low))")
        l.append("\(n).mid=\(fr(sh.mid))")
        l.append("\(n).set=\(fr(sh.set))")
        l.append("\(n).release=\(fr(sh.release))")
    }
    let actions: [(String, CharacterDirectionalActionSprites?)] = [("steal", s.steal), ("block", s.block), ("rebound", s.rebound)]
    for (n, a) in actions {
        l.append("\(n).back=\(fr(a?.back))")
        l.append("\(n).side=\(fr(a?.side))")
        l.append("\(n).front=\(fr(a?.front))")
    }
    for (i, a) in s.locomotion.enumerated() {
        l.append("locomotion\(i).back=\(fr(a.back))")
        l.append("locomotion\(i).side=\(fr(a.side))")
        l.append("locomotion\(i).front=\(fr(a.front))")
    }
    for (i, d) in s.dunks.enumerated() {
        l.append("dunk\(i)=\(d.facing.name),\(fb(d.preferredSpeed01)),\(fb(d.weight)),\(fb(d.contactLiftDp)),"
            + "\(fb(d.contactOutwardDp)),\(d.playerInFrontOfHoop),\(fr(d.frame))")
    }
    l.append("winner=\(fr(s.winner))")
    l.append("loser=\(fr(s.loser))")
    l.append("spectator=\(fr(s.spectator))")
    return l.joined(separator: "\n")
}

/// FNV-1a 64 over UTF-8, printed like java.lang.Long.toHexString.
private func fnv(_ s: String) -> String {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01b3
    }
    return String(h, radix: 16)
}

/// The frame at a harness slot path ("idleBack", "shotSide.mid", "locomotion1.front", ...).
private func slotFrame(_ s: CharacterSpriteSet, _ path: String) -> Result<CharacterSpriteFrame?, VisualsTestError> {
    func shot(_ x: CharacterShotSprites, _ part: String) -> Result<CharacterSpriteFrame?, VisualsTestError> {
        switch part {
        case "low": return .success(x.low)
        case "mid": return .success(x.mid)
        case "set": return .success(x.set)
        case "release": return .success(x.release)
        default: return .failure(VisualsTestError(message: "unknown slot \(path)"))
        }
    }
    func dir(_ x: CharacterDirectionalActionSprites?, _ part: String) -> Result<CharacterSpriteFrame?, VisualsTestError> {
        switch part {
        case "back": return .success(x?.back)
        case "side": return .success(x?.side)
        case "front": return .success(x?.front)
        default: return .failure(VisualsTestError(message: "unknown slot \(path)"))
        }
    }
    switch path {
    case "idleBack": return .success(s.idleBack)
    case "idleFront": return .success(s.idleFront)
    case "idleSide": return .success(s.idleSide)
    case "winner": return .success(s.winner)
    case "loser": return .success(s.loser)
    case "spectator": return .success(s.spectator)
    default: break
    }
    let parts = path.components(separatedBy: ".")
    guard parts.count == 2 else { return .failure(VisualsTestError(message: "unknown slot \(path)")) }
    switch parts[0] {
    case "shotBack": return shot(s.shotBack, parts[1])
    case "shotSide": return shot(s.shotSide, parts[1])
    case "shotFront": return shot(s.shotFront, parts[1])
    case "steal": return dir(s.steal, parts[1])
    case "block": return dir(s.block, parts[1])
    case "rebound": return dir(s.rebound, parts[1])
    case "locomotion0": return dir(s.locomotion.count > 0 ? s.locomotion[0] : nil, parts[1])
    case "locomotion1": return dir(s.locomotion.count > 1 ? s.locomotion[1] : nil, parts[1])
    default: return .failure(VisualsTestError(message: "unknown slot \(path)"))
    }
}

private struct VisualsTestError: Error {
    let message: String
}

/// Golden block lines split at `|` (empty fields kept, like Kotlin `split`).
private func goldenRows(_ block: String) -> [[String]] {
    return block.split(separator: "\n").map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
}

/// The 12 roster ids, in RefinementTest order.
private let refinementIds = ["woman_dark", "nova", "coach_67", "zephyr", "flare", "bob", "rooza", "unicorn_32", "kyra",
                             "ace_23", "buddy_23", "kyra_original"]

// MARK: - TripleShotShotPresentationTest.kt

final class TripleShotShotPresentationTest: XCTestCase {
    private let geometry = TripleShotPhysics.Geometry(1200, 750, 340, 655, 845, 5, 860, 215, 397, 505, 704, 792, 20)
    private let hoop = CourtPoint(3, 3.35, 0)

    private func state() -> TripleShotPhysics.ShotState {
        return TripleShotPhysics.ShotState(430, 700, 0, -500, 430, 700, 750, 340, 0, -500, 1200, 1,
                                           TripleShotPhysics.ShotPathMode.NORMAL, 0)
    }

    func testReleaseStartsAtTheActualWorldHand() {
        let bridge = TripleShotShotPresentation()
        bridge.held = CourtPoint(-1.5, 1.8, 5.2)
        let p = bridge.sample(state(), geometry, hoop, 0.0055)
        XCTAssertEqual(bridge.held.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(bridge.held.y, p.y, accuracy: 0.0001)
        XCTAssertEqual(bridge.held.z, p.z, accuracy: 0.0001)
    }

    func testRimContactsAndMakeUseTheBasketCrossSection() {
        let bridge = TripleShotShotPresentation()
        let s = state()
        s.elapsedSeconds = 1; s.y = 340; s.x = 655; s.rimHits = 1
        XCTAssertEqual(0.55, bridge.sample(s, geometry, hoop, 0.0055).z, accuracy: 0.0001)
        s.x = 845
        XCTAssertEqual(-0.55, bridge.sample(s, geometry, hoop, 0.0055).z, accuracy: 0.0001)
        s.x = 750; s.made = true
        let p = bridge.sample(s, geometry, hoop, 0.0055)
        XCTAssertEqual(hoop, p)
    }

    func testBackboardLivesBehindTheRimInsteadOfBesideIt() {
        let bridge = TripleShotShotPresentation()
        let s = state()
        s.elapsedSeconds = 1; s.x = 840; s.y = 280; s.backboardHits = 1
        let p = bridge.sample(s, geometry, hoop, 0.0055)
        XCTAssertEqual(hoop.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(-0.46, p.z, accuracy: 0.002)
        XCTAssertTrue(p.y > hoop.y)
    }

    func testRestingBallTouchesTheMeshDespiteLegacyImageStretch() {
        let bridge = TripleShotShotPresentation()
        let s = state()
        s.elapsedSeconds = 2; s.x = 655; s.y = 315; s.rimHits = 100
        let p = bridge.sample(s, geometry, hoop, 0.014)
        XCTAssertEqual(hoop.y + 0.21 + 0.045, p.y, accuracy: 0.0001)
        XCTAssertEqual(0.55, p.z, accuracy: 0.0001)
        XCTAssertFalse(s.made)
        XCTAssertEqual(100, s.rimHits)
    }

    func testRecordedReplayStartsInHandAndReachesTheSameRimPlane() {
        let bridge = TripleShotShotPresentation()
        bridge.held = CourtPoint(-2, 1.7, 4)
        XCTAssertEqual(bridge.held, bridge.sampleRecorded(430, 700, 430, 700, 0, hoop, 750, 340, 190, 0.0055))
        let rim = bridge.sampleRecorded(655, 340, 430, 700, 1, hoop, 750, 340, 190, 0.0055)
        XCTAssertEqual(hoop.x, rim.x, accuracy: 0.0001)
        XCTAssertEqual(hoop.y, rim.y, accuracy: 0.0001)
        XCTAssertEqual(0.55, rim.z, accuracy: 0.0001)
    }
}

// MARK: - Shot bridge golden vectors (harness `presentation()`)

final class TripleShotShotPresentationGoldenTests: XCTestCase {
    private let g = TripleShotPhysics.Geometry(1200, 750, 340, 655, 845, 5, 860, 215, 397, 505, 704, 792, 20)
    private let hoop = CourtPoint(3, 3.35, 0)

    private func st() -> TripleShotPhysics.ShotState {
        return TripleShotPhysics.ShotState(430, 700, 0, -500, 430, 700, 750, 340, 0, -500, 1200, 1,
                                           TripleShotPhysics.ShotPathMode.NORMAL, 0)
    }

    private func pt(_ c: CourtPoint) -> String {
        return "\(fb(c.x)),\(fb(c.y)),\(fb(c.z))"
    }

    /// Kotlin `fs(f)`: Float.toString without a trailing ".0".
    private func fs(_ f: Float) -> String {
        let s = javaString(f)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    func testShotBridgeMatchesTheJvmBitForBit() {
        var out: [String] = []
        let br = TripleShotShotPresentation()
        br.held = CourtPoint(-1.5, 1.8, 5.2)
        let s = st()
        for t: Float in [0, 0.25, 0.5, 0.75, 1] {
            s.elapsedSeconds = t
            s.x = 430 + (750 - 430) * t
            s.y = 700 - 360 * t * (2 - t)
            out.append("PRESENT_FLIGHT|\(fs(t))|\(fb(s.x))|\(fb(s.y))|\(pt(br.sample(s, g, hoop, 0.0055)))")
        }
        let r = st()
        r.elapsedSeconds = 2; r.x = 655; r.y = 315; r.rimHits = 100
        out.append("PRESENT_REST|\(pt(TripleShotShotPresentation().sample(r, g, hoop, 0.014)))")
        let bb = st()
        bb.elapsedSeconds = 1; bb.x = 840; bb.y = 280; bb.backboardHits = 1
        out.append("PRESENT_BOARD|\(pt(TripleShotShotPresentation().sample(bb, g, hoop, 0.0055)))")
        let rec = TripleShotShotPresentation()
        rec.held = CourtPoint(-2, 1.7, 4)
        for t: Float in [0, 0.5, 1] {
            let p = rec.sampleRecorded(430 + 225 * t, 700 - 360 * t, 430, 700, t, hoop, 750, 340, 190, 0.0055)
            out.append("PRESENT_REC|\(fs(t))|\(pt(p))")
        }
        // Identity latch: the release point is captured only when a new ShotState instance arrives.
        let br2 = TripleShotShotPresentation()
        br2.held = CourtPoint(1, 2, 3)
        let a = st()
        a.elapsedSeconds = 0.4; a.x = 520; a.y = 480
        out.append("PRESENT_X1|\(pt(br2.sample(a, g, hoop, 0.0055)))")
        br2.held = CourtPoint(9, 9, 9)
        a.elapsedSeconds = 0.6; a.x = 600; a.y = 420
        out.append("PRESENT_X2|\(pt(br2.sample(a, g, hoop, 0.0055)))")
        let a2 = a.copy()
        out.append("PRESENT_X3|\(pt(br2.sample(a2, g, hoop, 0.0055)))")
        let far = st()
        far.elapsedSeconds = 1.2; far.x = 870; far.y = 300; far.backboardHits = 2
        out.append("PRESENT_X4|\(pt(TripleShotShotPresentation().sample(far, g, hoop, 0.0055)))")
        let net = st()
        net.elapsedSeconds = 0.9; net.x = 760; net.y = 420; net.touchingNet = true
        let netBridge = TripleShotShotPresentation()
        netBridge.held = CourtPoint(-1, 1.2, 2)
        out.append("PRESENT_X5|\(pt(netBridge.sample(net, g, hoop, 0.0055)))")
        let quick = TripleShotPhysics.ShotState(430, 700, 0, -500, 430, 700, 750, 340, 0, -500, 1200, 0.05,
                                                TripleShotPhysics.ShotPathMode.NORMAL, 0)
        quick.elapsedSeconds = 0.03; quick.x = 450; quick.y = 690
        let quickBridge = TripleShotShotPresentation()
        quickBridge.held = CourtPoint(-1, 1.2, 2)
        out.append("PRESENT_X6|\(pt(quickBridge.sample(quick, g, hoop, 0.0055)))")
        let rimFar = st()
        rimFar.elapsedSeconds = 1.1; rimFar.x = 870; rimFar.y = 330; rimFar.rimHits = 1
        out.append("PRESENT_X7|\(pt(TripleShotShotPresentation().sample(rimFar, g, hoop, 0.0055)))")
        let low = st()
        low.elapsedSeconds = 1.5; low.x = 600; low.y = 900
        let lowBridge = TripleShotShotPresentation()
        lowBridge.held = CourtPoint(0, 0.2, 0)
        out.append("PRESENT_X8|\(pt(lowBridge.sample(low, g, hoop, 0.0055)))")
        let rec9 = TripleShotShotPresentation()
        rec9.held = CourtPoint(-2, 1.7, 4)
        out.append("PRESENT_X9|\(pt(rec9.sampleRecorded(500, 900, 430, 700, 1.4, hoop, 750, 340, 0.5, 0.0055)))")
        let rec10 = TripleShotShotPresentation()
        rec10.held = CourtPoint(-2, 1.7, 4)
        let p10 = rec10.sampleRecorded(600, 500, 430, 700, 0.3, CourtPoint(-3, 3.35, -1), 760, 350, 210, 0.0061)
        out.append("PRESENT_X10|\(pt(p10))")

        let expected = visualsPresentationGolden.split(separator: "\n").map(String.init)
        XCTAssertEqual(expected.count, out.count)
        for (e, o) in zip(expected, out) {
            XCTAssertEqual(e, o)
        }
    }
}

// MARK: - Catalog

final class TripleShotCharacterVisualCatalogTests: XCTestCase {
    /// RefinementTest.everyCharacterHasRealDecodedDirectionalActionFrames.
    func testEveryCharacterHasRealDecodedDirectionalActionFrames() {
        for id in refinementIds {
            guard let s = TripleShotCharacterVisualCatalog.find(characterId: id) else {
                XCTFail("\(id): no sprite set")
                continue
            }
            XCTAssertEqual(s.idleFront.resId, TripleShotCharacterVisualCatalog.previewResId(characterId: id),
                           "Roster portrait must use the authored gameplay identity")
            XCTAssertNotNil(s.idleSide)
            XCTAssertEqual(2, s.locomotion.count)
            XCTAssertTrue(s.dunks.count >= 3)
            guard let steal = s.steal, let block = s.block, let rebound = s.rebound, let idleSide = s.idleSide,
                  let backRelease = s.shotBack.release, let sideRelease = s.shotSide.release,
                  let frontRelease = s.shotFront.release else {
                XCTFail("\(id): an action or release frame is missing")
                continue
            }
            let actions = [steal, block, rebound] + s.locomotion
            let shots = [s.shotBack, s.shotSide, s.shotFront]
            let releases = [backRelease, sideRelease, frontRelease]
            var frames = [s.idleBack, s.idleFront, idleSide, s.winner, s.loser, s.spectator]
            frames += actions.flatMap { [$0.front, $0.back, $0.side] }
            for (shot, release) in zip(shots, releases) {
                frames += [shot.low, shot.mid, shot.set, release]
            }
            frames += s.dunks.map { $0.frame }
            var seen = Set<String>()
            for f in frames where seen.insert(f.resId).inserted {
                guard let image = AResources.cgImage(f.resId) else {
                    XCTFail("\(id):\(f.resId) does not decode")
                    continue
                }
                XCTAssertTrue(image.width > 32 && image.height > 32, "\(id):\(f.resId)")
                let alpha = image.alphaInfo
                XCTAssertTrue(alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast, "\(id):\(f.resId) has no alpha")
            }
        }
    }

    func testEveryRosterCharacterHasVisuals() {
        let roster = TripleShotCharacterRoster.all.map { $0.id }
        XCTAssertEqual(Set(roster), Set(refinementIds))
        for id in roster {
            XCTAssertTrue(TripleShotCharacterVisualCatalog.hasVisuals(characterId: id), id)
        }
        // The legacy roster id is normalised by the roster, not by the catalog.
        XCTAssertFalse(TripleShotCharacterVisualCatalog.hasVisuals(characterId: "minik"))
        XCTAssertFalse(TripleShotCharacterVisualCatalog.hasVisuals(characterId: nil))
    }

    /// Spec 07 Appendix A: every slot of the 12 resolved sets, the dunk tuning, the standing-dribble frames,
    /// portraits, unknown ids and playableCharacterIds(), as printed on the JVM.
    func testResolvedCatalogMatchesTheJvm() {
        var checked = 0
        for f in goldenRows(visualsCatalogGolden) {
            checked += 1
            switch f[0] {
            case "SET":
                guard let s = TripleShotCharacterVisualCatalog.find(characterId: f[1]) else {
                    XCTFail("no set for \(f[1])")
                    continue
                }
                let got = "\(s.characterId)|\(fb(s.referenceHeightPx))|\(fb(s.referenceHeightDp))|\(s.dunks.count)|\(s.locomotion.count)"
                XCTAssertEqual(f[2...6].joined(separator: "|"), got, f[1])
            case "SLOT":
                guard let s = TripleShotCharacterVisualCatalog.find(characterId: f[1]) else {
                    XCTFail("no set for \(f[1])")
                    continue
                }
                switch slotFrame(s, f[2]) {
                case .success(let frame): XCTAssertEqual(f[3], fr(frame), "\(f[1]) \(f[2])")
                case .failure(let error): XCTFail(error.message)
                }
            case "DUNK":
                guard let s = TripleShotCharacterVisualCatalog.find(characterId: f[1]), let i = Int(f[2]), i < s.dunks.count else {
                    XCTFail("no dunk \(f[2]) for \(f[1])")
                    continue
                }
                let d = s.dunks[i]
                let got = "\(d.facing.name)|\(fb(d.preferredSpeed01))|\(fb(d.weight))|\(fb(d.contactLiftDp))|"
                    + "\(fb(d.contactOutwardDp))|\(d.playerInFrontOfHoop)|\(fr(d.frame))"
                XCTAssertEqual(f[3...9].joined(separator: "|"), got, "\(f[1]) dunk \(i)")
            case "DRIBBLE":
                guard let facing = TripleShotPlayerRenderer.Facing.named(f[2]) else {
                    XCTFail("bad facing \(f[2])")
                    continue
                }
                XCTAssertEqual(f[3], fr(BasketballFeedbackArt.dribble(id: f[1], facing: facing)), "\(f[1]) \(f[2])")
            case "PREVIEW":
                XCTAssertEqual(f[2], TripleShotCharacterVisualCatalog.previewResId(characterId: f[1]) ?? "-", f[1])
            case "NOSET":
                let id: String? = f[1] == "<null>" ? nil : f[1]
                let got = "\(TripleShotCharacterVisualCatalog.find(characterId: id) == nil)|"
                    + "\(TripleShotCharacterVisualCatalog.hasVisuals(characterId: id))|"
                    + "\(TripleShotCharacterVisualCatalog.previewResId(characterId: id) ?? "-")"
                XCTAssertEqual(f[2...4].joined(separator: "|"), got, f[1])
            case "PLAYABLE":
                XCTAssertEqual(f[1], TripleShotCharacterVisualCatalog.playableCharacterIds().elements.joined(separator: ","))
            default:
                XCTFail("unknown golden row \(f[0])")
            }
        }
        XCTAssertEqual(VISUALS_CATALOG_ROWS, checked)
    }

    /// Digests of every table: the five hand-authored sets as written, the 11 Completion packs (with the
    /// Supplement), BasketballFeedbackArt.kyra and the 12 resolved sets.
    func testRawTablesMatchTheJvm() {
        var checked = 0
        for f in goldenRows(visualsRawGolden) {
            checked += 1
            let set: CharacterSpriteSet?
            switch f[1] {
            case "hand":
                switch f[2] {
                case "womanDark": set = TripleShotCharacterVisualCatalog.womanDark
                case "miaEssenceSkies": set = TripleShotCharacterVisualCatalog.miaEssenceSkies
                case "coach67": set = TripleShotCharacterVisualCatalog.coach67
                case "zephyr": set = TripleShotCharacterVisualCatalog.zephyr
                case "flare": set = TripleShotCharacterVisualCatalog.flare
                default: set = nil
                }
            case "completion": set = BasketballSpriteCompletion.find(id: f[2])
            case "feedback": set = BasketballFeedbackArt.kyra
            case "catalog": set = TripleShotCharacterVisualCatalog.find(characterId: f[2])
            case "fnv-check":
                XCTAssertEqual(f[3], fnv(f[2]))
                continue
            case "nulls":
                XCTAssertEqual(f[2], "\(BasketballSpriteCompletion.find(id: nil) == nil)")
                XCTAssertEqual(f[3], "\(BasketballSpriteCompletion.find(id: "kyra_original") == nil)")
                XCTAssertEqual(f[4], "\(BasketballFeedbackArt.dribble(id: nil, facing: .FRONT) == nil)")
                continue
            default:
                set = nil
            }
            guard let s = set else {
                XCTFail("no table for \(f[1]) \(f[2])")
                continue
            }
            let e = setEncoding(s)
            XCTAssertEqual(f[3], fnv(e), "\(f[1]) \(f[2])")
            XCTAssertEqual(f[4], "\(e.split(separator: "\n", omittingEmptySubsequences: false).count)", "\(f[1]) \(f[2])")
        }
        XCTAssertEqual(VISUALS_RAW_ROWS, checked)
    }

    /// The iOS catalog is composed once; Android's `find()` re-composes six sets on every call. Re-running the
    /// Kotlin `find` expression with the public pieces must give the same sets.
    func testPrecomputedCatalogEqualsThePerCallComposition() {
        let hand: [String: CharacterSpriteSet] = [
            TripleShotCharacterVisualCatalog.womanDark.characterId: TripleShotCharacterVisualCatalog.womanDark,
            TripleShotCharacterVisualCatalog.miaEssenceSkies.characterId: TripleShotCharacterVisualCatalog.miaEssenceSkies,
            TripleShotCharacterVisualCatalog.coach67.characterId: TripleShotCharacterVisualCatalog.coach67,
            TripleShotCharacterVisualCatalog.zephyr.characterId: TripleShotCharacterVisualCatalog.zephyr,
            TripleShotCharacterVisualCatalog.flare.characterId: TripleShotCharacterVisualCatalog.flare
        ]
        func kotlinFind(_ characterId: String?) -> CharacterSpriteSet? {
            guard let it = characterId else { return nil }
            if it == "kyra_original" { return BasketballFeedbackArt.kyra }
            if let set = hand[it] {
                return BasketballFeedbackArt.folded(old: BasketballSpriteCompletion.enrich(old: set))
            }
            return BasketballSpriteCompletion.find(id: it).map { BasketballFeedbackArt.folded(old: $0) }
        }
        let ids: [String?] = refinementIds + [nil, "", "minik", "Bob", "kyra_originalx", "character_preview_bob", "mia_angel"]
        for id in ids {
            XCTAssertEqual(kotlinFind(id), TripleShotCharacterVisualCatalog.find(characterId: id), id ?? "nil")
            XCTAssertEqual(TripleShotCharacterVisualCatalog.find(characterId: id), TripleShotCharacterVisualCatalog.find(characterId: id))
        }
    }

    func testCompositionTransformsKeepTheirInputsForOtherIds() {
        let bob = BasketballSpriteCompletion.find(id: "bob")!
        XCTAssertEqual(bob, BasketballFeedbackArt.folded(old: bob))
        XCTAssertEqual(bob, BasketballSupplement.enrich(old: bob))
        XCTAssertEqual(BasketballFeedbackArt.kyra, BasketballSpriteCompletion.enrich(old: BasketballFeedbackArt.kyra))
        XCTAssertEqual(BasketballFeedbackArt.kyra, BasketballSupplement.enrich(old: BasketballFeedbackArt.kyra))
        XCTAssertNil(BasketballFeedbackArt.dribble(id: "kyra_original", facing: .FRONT))
        XCTAssertEqual("basket_gaya_ground_21", BasketballFeedbackArt.dribble(id: "kyra", facing: .FRONT)?.resId)
        XCTAssertEqual("basket_gaya_ground_22", BasketballFeedbackArt.dribble(id: "kyra", facing: .BACK)?.resId)
        XCTAssertEqual("basket_comet_ground_23", BasketballFeedbackArt.dribble(id: "zephyr", facing: .SIDE)?.resId)
    }

    func testDataClassDefaults() {
        let f = CharacterSpriteFrame(resId: R.drawable.basket_bob_00)
        XCTAssertEqual(0.5, f.anchorX01)
        XCTAssertEqual(1, f.anchorY01)
        XCTAssertNil(f.ballSourceX)
        XCTAssertNil(f.ballSourceY)
        XCTAssertNil(f.targetHeightDp)
        XCTAssertNil(f.ballForegroundRect01)
        XCTAssertFalse(f.hasBallAnchor)
        XCTAssertFalse(CharacterSpriteFrame(resId: R.drawable.basket_bob_00, ballSourceX: 1).hasBallAnchor)
        XCTAssertFalse(CharacterSpriteFrame(resId: R.drawable.basket_bob_00, ballSourceY: 1).hasBallAnchor)
        XCTAssertTrue(CharacterSpriteFrame(resId: R.drawable.basket_bob_00, ballSourceX: 0, ballSourceY: 0).hasBallAnchor)
        let d = CharacterDunkSprite(f, TripleShotPlayerRenderer.Facing.SIDE)
        XCTAssertEqual(fb(0.82), fb(d.preferredSpeed01))
        XCTAssertEqual(1, d.weight)
        XCTAssertEqual(0, d.contactLiftDp)
        XCTAssertEqual(0, d.contactOutwardDp)
        XCTAssertFalse(d.playerInFrontOfHoop)
        let shot = CharacterShotSprites(f, f, f)
        XCTAssertNil(shot.release)
        // Positional order of CharacterDirectionalActionSprites is BACK, SIDE, FRONT.
        let a = CharacterSpriteFrame(resId: "a"), b = CharacterSpriteFrame(resId: "b"), c = CharacterSpriteFrame(resId: "c")
        let dir = CharacterDirectionalActionSprites(a, b, c)
        XCTAssertEqual(["a", "b", "c"], [dir.back.resId, dir.side.resId, dir.front.resId])
    }

    /// Every drawable the catalog files reference (TripleShotCharacterVisuals, BasketballSpriteCompletion,
    /// BasketballSupplement, BasketballFeedbackArt: 606 names) is a drawable-nodpi image of this pixel size, and the
    /// Swift tables reference exactly these names.
    func testEveryReferencedDrawableIsADrawableNodpiImage() {
        var expected: [String: (Int, Int)] = [:]
        for line in visualsDrawables.split(separator: "\n") {
            let p = line.split(separator: " ").map(String.init)
            expected[p[0]] = (Int(p[1])!, Int(p[2])!)
        }
        XCTAssertEqual(VISUALS_DRAWABLE_COUNT, expected.count)
        for (name, size) in expected.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(name, AResources.getIdentifier(name, "drawable"), name)
            XCTAssertTrue(AResources.drawableExists(name), name)
            let table = AResources.drawablePixelSize(name)
            XCTAssertEqual(size.0, table.width, name)
            XCTAssertEqual(size.1, table.height, name)
            let intrinsic = AResources.drawableIntrinsicSize(name)
            XCTAssertEqual(size.0, intrinsic.width, name)
            XCTAssertEqual(size.1, intrinsic.height, name)
            guard let url = AResources.drawableURL(name) else {
                XCTFail("\(name): no file")
                continue
            }
            XCTAssertEqual("drawable-nodpi", url.deletingLastPathComponent().lastPathComponent, name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                XCTFail("\(name): not an image")
                continue
            }
            XCTAssertEqual(size.0, props[kCGImagePropertyPixelWidth] as? Int, name)
            XCTAssertEqual(size.1, props[kCGImagePropertyPixelHeight] as? Int, name)
        }

        // Names reachable through the Swift tables: the hand-authored sets, the Completion packs (with the
        // Supplement), the feedback sets and the standing-dribble frames. Only the never-shown portrait
        // fallbacks (previewDrawables) are private.
        var reachable = Set<String>()
        func add(_ s: CharacterSpriteSet) {
            for line in setEncoding(s).split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let value = line[line.index(after: eq)...]
                let fields = value.split(separator: ",", omittingEmptySubsequences: false)
                if line.hasPrefix("set=") { continue }
                let nameField = line.hasPrefix("dunk") ? fields[6] : fields[0]
                if nameField != "-" { reachable.insert(String(nameField)) }
            }
        }
        [TripleShotCharacterVisualCatalog.womanDark, TripleShotCharacterVisualCatalog.miaEssenceSkies,
         TripleShotCharacterVisualCatalog.coach67, TripleShotCharacterVisualCatalog.zephyr,
         TripleShotCharacterVisualCatalog.flare, BasketballFeedbackArt.kyra].forEach(add)
        for id in ["buddy_23", "ace_23", "rooza", "unicorn_32", "kyra", "bob", "woman_dark", "nova", "coach_67", "zephyr", "flare"] {
            add(BasketballSpriteCompletion.find(id: id)!)
        }
        for id in refinementIds {
            add(TripleShotCharacterVisualCatalog.find(characterId: id)!)
            for facing in TripleShotPlayerRenderer.Facing.allCases {
                if let frame = BasketballFeedbackArt.dribble(id: id, facing: facing) { reachable.insert(frame.resId) }
            }
        }
        let previews: Set<String> = ["character_preview_bob", "character_preview_rooza", "character_preview_nova",
                                     "character_preview_unicorn_32", "character_preview_coach_67", "character_preview_kyra",
                                     "character_preview_zephyr", "character_preview_flare", "character_preview_ace_23",
                                     "character_preview_buddy_23"]
        XCTAssertEqual(Set(expected.keys), reachable.union(previews))
        XCTAssertTrue(reachable.isDisjoint(with: previews))
    }
}

// MARK: - Renderer

final class TripleShotPlayerRendererTests: XCTestCase {
    func testEnumsKeepKotlinNamesAndOrdinals() {
        XCTAssertEqual(["HUMAN", "BOT"], TripleShotPlayerRenderer.Style.allCases.map { $0.name })
        XCTAssertEqual(["NORMAL", "WINNER", "LOSER", "SPECTATOR"], TripleShotPlayerRenderer.Pose.allCases.map { $0.name })
        XCTAssertEqual(["PRO", "GRANNY"], TripleShotPlayerRenderer.ShotStyle.allCases.map { $0.name })
        XCTAssertEqual(["BACK", "SIDE", "FRONT"], TripleShotPlayerRenderer.Facing.allCases.map { $0.name })
        XCTAssertEqual([0, 1, 2], TripleShotPlayerRenderer.Facing.allCases.map { $0.ordinal })
        XCTAssertEqual(["IDLE", "WAITING", "WALK", "DRIBBLE", "STEAL", "BLOCK", "REBOUND", "DUNK", "SHOT_LOW", "SHOT_MID",
                        "SHOT_SET", "RELEASE"], TripleShotPlayerRenderer.Motion.allCases.map { $0.name })
        XCTAssertEqual(TripleShotPlayerRenderer.Motion.DUNK, TripleShotPlayerRenderer.Motion.named("DUNK"))
        XCTAssertEqual(7, TripleShotPlayerRenderer.Motion.DUNK.ordinal)
    }

    func testStateDefaultsAndDataClassEquality() {
        let s = TripleShotPlayerRenderer.State(x: 1, footY: 2, fineAim: 3, pullBack: 4, dribbleBouncePx: 5, hotHand: true)
        XCTAssertEqual(TripleShotPlayerRenderer.Style.HUMAN, s.style)
        XCTAssertEqual(TripleShotPlayerRenderer.Pose.NORMAL, s.pose)
        XCTAssertEqual(0, s.celebrationProgress)
        XCTAssertEqual(TripleShotPlayerRenderer.ShotStyle.GRANNY, s.shotStyle)
        XCTAssertEqual(TripleShotPlayerRenderer.Facing.BACK, s.facing)
        XCTAssertEqual(TripleShotPlayerRenderer.Motion.IDLE, s.motion)
        XCTAssertEqual(0, s.dribblePhase01)
        XCTAssertEqual(1, s.dribbleHandSign)
        XCTAssertFalse(s.moving)
        XCTAssertFalse(s.movingFast)
        XCTAssertEqual(-1, s.locomotionFrameIndex)
        XCTAssertNil(s.characterId)
        XCTAssertFalse(s.mirrorX)
        XCTAssertEqual(-1, s.actionFrameIndex)
        XCTAssertEqual(1, s.visualScale)
        // Android 6c38131: crossoverProgress = 1, crossoverFrom = 1, crossoverBehind = false, playfulHold = false.
        XCTAssertEqual(1, s.crossoverProgress)
        XCTAssertEqual(1, s.crossoverFrom)
        XCTAssertFalse(s.crossoverBehind)
        XCTAssertFalse(s.playfulHold)
        XCTAssertEqual(s, TripleShotPlayerRenderer.State(1, 2, 3, 4, 5, true))
        // Kotlin data-class equality compares Float properties with Float.compare (harness DATAEQ: true, false).
        var nan = s
        nan.x = Float.nan
        XCTAssertEqual(nan, nan)
        var zero = s
        zero.x = 0
        var negativeZero = s
        negativeZero.x = -0.0
        XCTAssertNotEqual(zero, negativeZero)
    }

    /// Spec 07 section 4.5 golden table (density 1), every unspecified field at its State default.
    func testSpecHeldBallTable() {
        let r = TripleShotPlayerRenderer(density: 1)
        r.uptimeMillis = { 0 }
        typealias S = TripleShotPlayerRenderer.State
        func pro(_ x: Float, _ footY: Float, _ id: String) -> S {
            var s = S(x: x, footY: footY, fineAim: 0, pullBack: 0, dribbleBouncePx: 0, hotHand: false)
            s.shotStyle = .PRO
            s.characterId = id
            return s
        }
        var cases: [String: S] = [:]
        cases["maya-idle-back"] = pro(500, 900, "woman_dark")
        var s = pro(500, 900, "woman_dark"); s.dribbleHandSign = -1
        cases["maya-idle-back-left-hand"] = s
        s = pro(500, 900, "woman_dark"); s.facing = .SIDE; s.motion = .SHOT_SET; s.mirrorX = true; s.visualScale = 1.10
        cases["maya-set-side-mirror-1v1"] = s
        s = pro(200, 600, "bob"); s.facing = .FRONT; s.motion = .SHOT_SET
        cases["bob-set-front"] = s
        s = pro(300, 700, "kyra"); s.dribbleBouncePx = 24.5; s.facing = .FRONT; s.motion = .DRIBBLE; s.dribblePhase01 = 0.25
        cases["gaya-dribble-front-025"] = s
        s.dribblePhase01 = 0.75
        cases["gaya-dribble-front-075"] = s
        s = pro(400, 800, "nova"); s.dribbleBouncePx = 49; s.facing = .BACK; s.motion = .DRIBBLE; s.dribbleHandSign = -1
        s.moving = true; s.movingFast = true; s.locomotionFrameIndex = 1
        cases["mia-fast-dribble-back"] = s
        s = pro(500, 900, "woman_dark"); s.fineAim = 0.2; s.pullBack = 0.5; s.facing = .FRONT; s.motion = .BLOCK
        cases["maya-block-front-legacy"] = s
        s = pro(500, 900, "woman_dark"); s.facing = .SIDE; s.motion = .DUNK; s.actionFrameIndex = 7
        cases["maya-dunk-side-7"] = s
        cases["granny-no-id"] = S(x: 100, footY: 300, fineAim: -1, pullBack: 1.4, dribbleBouncePx: 5, hotHand: false)

        let rows = goldenRows(visualsSpecGolden)
        XCTAssertEqual(10, rows.count)
        for f in rows {
            guard let state = cases[f[1]] else {
                XCTFail("no case \(f[1])")
                continue
            }
            let held = r.heldBallPosition(state)
            XCTAssertEqual(f[2], r.worldFrame(state)?.second.resId ?? "-", f[1])
            XCTAssertEqual(f[3], fb(held.x), f[1])
            XCTAssertEqual(f[4], fb(held.y), f[1])
            // The decimal values of the spec table.
            XCTAssertEqual(Double(f[5])!, Double(held.x), accuracy: 0.001, f[1])
            XCTAssertEqual(Double(f[6])!, Double(held.y), accuracy: 0.001, f[1])
        }
    }

    /// heldBallPosition, worldFrame and visualTopY against the JVM for 1500 states: every id (12 roster ids, null and
    /// "minik") x motion x facing at density 1, the per-branch variants (mirror, hand sign, locomotion index, fast
    /// dribble, dribble phase and bounce clamps, outcome poses, GRANNY, dunk index, visual scale, wall clock) for
    /// woman_dark, kyra, kyra_original and null, and densities 2 and 3.
    /// Row: `density id MOTION FACING [field=value ...] > worldFrame heldX heldY visualTopY`; every field not
    /// listed has the harness default below.
    func testHeldBallWorldFrameAndVisualTopMatchTheJvm() {
        var failures: [String] = []
        var count = 0
        for line in visualsHeldGolden.split(separator: "\n") {
            count += 1
            let halves = line.components(separatedBy: " > ")
            let key = halves[0].split(separator: " ").map(String.init)
            let expected = halves[1].split(separator: " ").map(String.init)
            guard key.count >= 4, expected.count == 4, let density = Float(key[0]),
                  let motion = TripleShotPlayerRenderer.Motion.named(key[2]),
                  let facing = TripleShotPlayerRenderer.Facing.named(key[3]) else {
                failures.append("bad row: \(line)")
                continue
            }
            var s = TripleShotPlayerRenderer.State(x: 500, footY: 900, fineAim: 0.2, pullBack: 0.5, dribbleBouncePx: 24.5,
                                                   hotHand: false)
            s.shotStyle = .PRO
            s.dribblePhase01 = 0.25
            s.characterId = key[1] == "-" ? nil : key[1]
            s.motion = motion
            s.facing = facing
            var uptime: Int64 = 0
            var bad = false
            for option in key.dropFirst(4) {
                let kv = option.split(separator: "=", maxSplits: 1).map(String.init)
                let v = kv.count == 2 ? kv[1] : ""
                switch kv[0] {
                case "pose": if let p = TripleShotPlayerRenderer.Pose.named(v) { s.pose = p } else { bad = true }
                case "style": if let p = TripleShotPlayerRenderer.Style.named(v) { s.style = p } else { bad = true }
                case "shot": if let p = TripleShotPlayerRenderer.ShotStyle.named(v) { s.shotStyle = p } else { bad = true }
                case "x": if let f = Float(v) { s.x = f } else { bad = true }
                case "y": if let f = Float(v) { s.footY = f } else { bad = true }
                case "aim": if let f = Float(v) { s.fineAim = f } else { bad = true }
                case "pull": if let f = Float(v) { s.pullBack = f } else { bad = true }
                case "b": if let f = Float(v) { s.dribbleBouncePx = f } else { bad = true }
                case "hot": s.hotHand = v == "1"
                case "cel": if let f = Float(v) { s.celebrationProgress = f } else { bad = true }
                case "ph": if let f = Float(v) { s.dribblePhase01 = f } else { bad = true }
                case "hs": if let f = Float(v) { s.dribbleHandSign = f } else { bad = true }
                case "mv": s.moving = v == "1"
                case "fast": s.movingFast = v == "1"
                case "loco": if let i = Int(v) { s.locomotionFrameIndex = i } else { bad = true }
                case "mir": s.mirrorX = v == "1"
                case "act": if let i = Int(v) { s.actionFrameIndex = i } else { bad = true }
                case "vs": if let f = Float(v) { s.visualScale = f } else { bad = true }
                case "up": if let u = Int64(v) { uptime = u } else { bad = true }
                default: bad = true
                }
            }
            if bad {
                failures.append("bad row: \(line)")
                continue
            }
            let r = TripleShotPlayerRenderer(density: density)
            r.uptimeMillis = { uptime }
            let world = r.worldFrame(s)?.second.resId ?? "-"
            let held = r.heldBallPosition(s)
            let top = r.visualTopY(s)
            let got = [world, fb(held.x), fb(held.y), fb(top)]
            if got != expected {
                failures.append("\(halves[0]): expected \(expected.joined(separator: " ")), got \(got.joined(separator: " "))")
            }
        }
        XCTAssertEqual(VISUALS_HELD_ROWS, count)
        XCTAssertEqual([], Array(failures.prefix(25)), "\(failures.count) mismatching rows")
    }

    func testWorldFrameFollowsPoseAndIgnoresShotStyle() {
        let r = TripleShotPlayerRenderer(density: 1)
        var s = TripleShotPlayerRenderer.State(x: 0, footY: 0, fineAim: 0, pullBack: 0, dribbleBouncePx: 0, hotHand: false,
                                               characterId: "flare")
        XCTAssertEqual(TripleShotPlayerRenderer.ShotStyle.GRANNY, s.shotStyle)
        XCTAssertEqual("flare_back_standing", r.worldFrame(s)?.second.resId)
        XCTAssertEqual("flare", r.worldFrame(s)?.first.characterId)
        s.pose = .WINNER
        XCTAssertEqual("flare_front_celebrate", r.worldFrame(s)?.second.resId)
        s.pose = .LOSER
        XCTAssertEqual("flare_front_sitting_sad", r.worldFrame(s)?.second.resId)
        s.pose = .SPECTATOR
        XCTAssertEqual("flare_front_sitting", r.worldFrame(s)?.second.resId)
        s.characterId = nil
        XCTAssertNil(r.worldFrame(s))
        s.characterId = "minik"
        XCTAssertNil(r.worldFrame(s))
    }

    /// The Android quirks spec 07 sections 4.5 and 8 says to keep, written out (the golden rows cover them bit for bit).
    func testHeldBallQuirksAreKept() {
        let r = TripleShotPlayerRenderer(density: 1)
        func maya(_ motion: TripleShotPlayerRenderer.Motion, _ facing: TripleShotPlayerRenderer.Facing) -> TripleShotPlayerRenderer.State {
            var s = TripleShotPlayerRenderer.State(x: 500, footY: 900, fineAim: 0, pullBack: 0, dribbleBouncePx: 0, hotHand: false)
            s.shotStyle = .PRO
            s.characterId = "woman_dark"
            s.motion = motion
            s.facing = facing
            return s
        }
        // IDLE socket: woman_dark_back_standing at the reference scale 200 dp / 500 px = 0.4.
        var s = maya(.IDLE, .BACK)
        XCTAssertEqual(538.2, r.heldBallPosition(s).x, accuracy: 0.001)
        XCTAssertEqual(812.0, r.heldBallPosition(s).y, accuracy: 0.001)
        s.mirrorX = true
        XCTAssertEqual(461.8, r.heldBallPosition(s).x, accuracy: 0.001)
        // A mirrored pose whose ball is in the left hand mirrors twice (back to the unmirrored side).
        s.dribbleHandSign = -1
        XCTAssertEqual(538.2, r.heldBallPosition(s).x, accuracy: 0.001)
        // Socket-less hand-authored frames use the legacy point, mirrored only for PRO sprites.
        s = maya(.BLOCK, .FRONT)
        XCTAssertEqual(518, r.heldBallPosition(s).x, accuracy: 0.001)
        XCTAssertEqual(836, r.heldBallPosition(s).y, accuracy: 0.001)
        s.mirrorX = true
        XCTAssertEqual(482, r.heldBallPosition(s).x, accuracy: 0.001)
        s.shotStyle = .GRANNY
        XCTAssertEqual(518, r.heldBallPosition(s).x, accuracy: 0.001)
        // visualScale moves the canvas socket (the GPU body ignores it).
        s = maya(.IDLE, .BACK)
        s.visualScale = 1.1
        XCTAssertEqual(542.02, r.heldBallPosition(s).x, accuracy: 0.001)
        s.visualScale = 3
        XCTAssertEqual(547.75, r.heldBallPosition(s).x, accuracy: 0.001)
        // DUNK: the action index wins over the facing; without an index the first dunk of the facing is used.
        s = maya(.DUNK, .SIDE)
        s.actionFrameIndex = 0
        XCTAssertEqual("woman_dark_dunk_back_one_hand", r.worldFrame(s)?.second.resId)
        s.actionFrameIndex = -1
        XCTAssertEqual("woman_dark_dunk_side_two_hand_gather", r.worldFrame(s)?.second.resId)
        s.actionFrameIndex = 99
        XCTAssertEqual("woman_dark_dunk_side_two_hand_gather", r.worldFrame(s)?.second.resId)
        // RELEASE: every set has a front follow-through after Completion.enrich (the Kotlin comment is stale).
        s = maya(.RELEASE, .FRONT)
        XCTAssertEqual("basket_woman_dark_15", r.worldFrame(s)?.second.resId)
        s.facing = .BACK
        XCTAssertEqual("woman_dark_back_after_throw", r.worldFrame(s)?.second.resId)
        // Standing-dribble art exists only for the winged characters, and only while not moving.
        var gaya = TripleShotPlayerRenderer.State(x: 300, footY: 700, fineAim: 0, pullBack: 0, dribbleBouncePx: 24.5, hotHand: false)
        gaya.shotStyle = .PRO
        gaya.characterId = "kyra"
        gaya.motion = .DRIBBLE
        gaya.facing = .FRONT
        XCTAssertEqual("basket_gaya_ground_21", r.worldFrame(gaya)?.second.resId)
        gaya.moving = true
        gaya.locomotionFrameIndex = 0
        XCTAssertEqual("basket_gaya_ground_03", r.worldFrame(gaya)?.second.resId)
        gaya.locomotionFrameIndex = 3
        XCTAssertEqual("basket_gaya_ground_04", r.worldFrame(gaya)?.second.resId)
        gaya.motion = .IDLE
        XCTAssertEqual("basket_gaya_ground_04", r.worldFrame(gaya)?.second.resId, "a lingering moving flag shows locomotion")
        // Wall-clock locomotion (no index): 250 ms per step, 205 ms when moving fast.
        gaya.locomotionFrameIndex = -1
        r.uptimeMillis = { 249 }
        XCTAssertEqual("basket_gaya_ground_03", r.worldFrame(gaya)?.second.resId)
        r.uptimeMillis = { 250 }
        XCTAssertEqual("basket_gaya_ground_04", r.worldFrame(gaya)?.second.resId)
        gaya.movingFast = true
        r.uptimeMillis = { 205 }
        XCTAssertEqual("basket_gaya_ground_04", r.worldFrame(gaya)?.second.resId)
        r.uptimeMillis = { 410 }
        XCTAssertEqual("basket_gaya_ground_03", r.worldFrame(gaya)?.second.resId)
    }

    func testFeedbackArtSocketQuirkFollowsTheCellIndex() {
        // Socket x is 0.7 * width for every cell index % 3 == 2: the BACK walk cell 05 gets it, the SIDE walk cell 07 not.
        let kyra = TripleShotCharacterVisualCatalog.find(characterId: "kyra_original")!
        XCTAssertEqual("basket_kyra_original_05", kyra.locomotion[0].back.resId)
        XCTAssertEqual(146.3, kyra.locomotion[0].back.ballSourceX!, accuracy: 0.0001)
        XCTAssertEqual("basket_kyra_original_07", kyra.locomotion[0].side.resId)
        XCTAssertEqual(104.5, kyra.locomotion[0].side.ballSourceX!, accuracy: 0.0001)
        XCTAssertEqual(146.3, kyra.idleSide!.ballSourceX!, accuracy: 0.0001)
        // flare's FRONT pack dunk keeps its 0.77 hand (all other packs 0.28): 135 px * 0.77.
        let flarePack = BasketballSpriteCompletion.find(id: "flare")!
        XCTAssertEqual(135 * Float(0.77), flarePack.dunks[0].frame.ballSourceX)
        // Composition order: Gaya's shot MID comes from the folded-wing art, her block/winner from the supplement.
        let gaya = TripleShotCharacterVisualCatalog.find(characterId: "kyra")!
        XCTAssertEqual("basket_gaya_ground_12", gaya.shotFront.mid.resId)
        XCTAssertEqual("basket_kyra_extra_03", gaya.block?.front.resId)
        XCTAssertEqual("basket_kyra_extra_09", gaya.winner.resId)
        XCTAssertEqual("basket_kyra_15", gaya.shotFront.release?.resId)
        // Comet uses only frames 15 and 17 of his pack; his idle front is the folded-wing art.
        let comet = TripleShotCharacterVisualCatalog.find(characterId: "zephyr")!
        XCTAssertEqual("basket_comet_ground_00", comet.idleFront.resId)
        XCTAssertEqual("basket_zephyr_15", comet.shotFront.release?.resId)
        XCTAssertEqual("basket_zephyr_17", comet.shotSide.release?.resId)
        XCTAssertEqual("zephyr_back_after_throw", comet.shotBack.release?.resId)
        XCTAssertEqual(10, comet.dunks.count)
    }

    func testWinnerJumpOffsetMatchesTheJvm() {
        let rows = goldenRows(visualsJumpGolden)
        XCTAssertEqual(27, rows.count)
        for f in rows {
            let r = TripleShotPlayerRenderer(density: Float(f[1])!)
            XCTAssertEqual(f[3], fb(r.winnerJumpOffsetPx(Float(f[2])!)), "density \(f[1]) progress \(f[2])")
        }
    }

    func testDefaultInitUsesTheDisplayDensity() {
        var s = TripleShotPlayerRenderer.State(x: 400, footY: 800, fineAim: 0.3, pullBack: 0.4, dribbleBouncePx: 3, hotHand: false)
        XCTAssertEqual(TripleShotPlayerRenderer(density: AResources.density).heldBallPosition(s), TripleShotPlayerRenderer().heldBallPosition(s))
        s.shotStyle = .PRO
        s.characterId = "rooza"
        s.motion = .SHOT_MID
        XCTAssertEqual(TripleShotPlayerRenderer(density: AResources.density).heldBallPosition(s), TripleShotPlayerRenderer(nil).heldBallPosition(s))
    }

    // MARK: Canvas paths (pixel probes)

    private func assertPixel(_ bitmap: ABitmap, _ x: Int, _ y: Int, _ color: Int, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let p = bitmap.getPixel(x, y)
        let got = [AColor.alpha(p), AColor.red(p), AColor.green(p), AColor.blue(p)]
        let want = [AColor.alpha(color), AColor.red(color), AColor.green(color), AColor.blue(color)]
        let close = zip(got, want).allSatisfy { abs($0 - $1) <= 3 }
        XCTAssertTrue(close, "\(what) at (\(x), \(y)): got ARGB \(got), want \(want)", file: file, line: line)
    }

    /// GpuWorldView.prepareActor: the vector figure rasterised for an id without sprites. With
    /// `scale = 400 / (density * 120)` the texture is the same on every density: 1 dp = 10/3 texture px, feet at
    /// (256, 480) (spec 07 section 4.7).
    func testVectorFallbackRasterIsDensityIndependent() {
        let skin = AColor.rgb(242, 190, 145), jersey = AColor.rgb(8, 126, 112), pants = AColor.rgb(32, 55, 71)
        for density: Float in [1, 2, 3] {
            let bitmap = ABitmap.createBitmap(512, 512, .ARGB_8888)
            let canvas = ACanvas(bitmap)
            let scale = Float(400) / (density * 120)
            canvas.scale(scale, scale)
            TripleShotPlayerRenderer(density: density).draw(
                canvas, TripleShotPlayerRenderer.State(256 / scale, 480 / scale, 0, 0, 0, false, characterId: "minik"))
            let d = "density \(density)"
            assertPixel(bitmap, 256, 140, skin, "head, \(d)")
            assertPixel(bitmap, 256, 320, jersey, "jersey, \(d)")
            assertPixel(bitmap, 258, 252, skin, "left arm, \(d)")
            assertPixel(bitmap, 223, 420, pants, "left leg, \(d)")
            assertPixel(bitmap, 291, 420, pants, "right leg, \(d)")
            assertPixel(bitmap, 256, 498, AColor.argb(70, 0, 0, 0), "shadow, \(d)")
            assertPixel(bitmap, 20, 20, AColor.TRANSPARENT, "outside, \(d)")
            assertPixel(bitmap, 256, 30, AColor.TRANSPARENT, "above the head, \(d)")
            assertPixel(bitmap, 400, 300, AColor.TRANSPARENT, "beside the body, \(d)")
        }
    }

    func testLegacyVectorPosesAndHotHand() {
        let skin = AColor.rgb(242, 190, 145)
        func draw(_ configure: (inout TripleShotPlayerRenderer.State) -> Void) -> ABitmap {
            let bitmap = ABitmap.createBitmap(300, 300, .ARGB_8888)
            let canvas = ACanvas(bitmap)
            var s = TripleShotPlayerRenderer.State(x: 150, footY: 250, fineAim: 0, pullBack: 0, dribbleBouncePx: 0, hotHand: false)
            configure(&s)
            TripleShotPlayerRenderer(density: 1).draw(canvas, s)
            return bitmap
        }
        let bot = draw { $0.style = .BOT; $0.hotHand = true }
        assertPixel(bot, 150, 190, AColor.rgb(118, 73, 167), "BOT jersey")
        assertPixel(bot, 140, 232, AColor.rgb(53, 43, 92), "BOT leg")
        assertPixel(bot, 150, 148, skin, "BOT head")
        assertPixel(bot, 150, 255, AColor.argb(70, 0, 0, 0), "shadow")
        assertPixel(bot, 126, 162, AColor.argb(175, 255, 90, 20), "hot-hand flame")
        let winner = draw { $0.pose = .WINNER }
        assertPixel(winner, 150, 146, skin, "winner head")
        assertPixel(winner, 121, 126, skin, "winner raised hand")
        assertPixel(winner, 150, 189, AColor.rgb(8, 126, 112), "winner jersey")
        let loser = draw { $0.pose = .LOSER }
        assertPixel(loser, 153, 162, skin, "loser head")
        assertPixel(loser, 150, 210, AColor.rgb(8, 126, 112), "loser jersey")
        let spectator = draw { $0.pose = .SPECTATOR }
        assertPixel(spectator, 150, 158, skin, "spectator head")
        assertPixel(spectator, 150, 205, AColor.rgb(8, 126, 112), "spectator jersey")
    }

    /// Legacy Canvas sprite path (no production caller): the drawable lands inside the bounds the harness
    /// recorded (bob WALK FRONT at density 2: 202,258,397,698; woman_dark SHOT_SET SIDE mirrored around x 300:
    /// 181,260,399,700 -> 201..419).
    func testLegacySpriteDrawingStaysInsideTheRecordedBounds() {
        func check(_ id: String, _ motion: TripleShotPlayerRenderer.Motion, _ facing: TripleShotPlayerRenderer.Facing,
                   _ mirror: Bool, _ left: Int, _ top: Int, _ right: Int) {
            let bitmap = ABitmap.createBitmap(800, 800, .ARGB_8888)
            let canvas = ACanvas(bitmap)
            var s = TripleShotPlayerRenderer.State(x: 300, footY: 700, fineAim: 0.7, pullBack: 0.6, dribbleBouncePx: 30,
                                                   hotHand: false)
            s.shotStyle = .PRO
            s.motion = motion
            s.facing = facing
            s.characterId = id
            s.mirrorX = mirror
            s.visualScale = 1.1
            TripleShotPlayerRenderer(density: 2).draw(canvas, s)
            var inside = 0
            for y in stride(from: 0, to: 800, by: 4) {
                for x in stride(from: 0, to: 800, by: 4) {
                    let a = AColor.alpha(bitmap.getPixel(x, y))
                    let inBox = x >= left - 2 && x <= right + 2 && y >= top - 2
                    if !inBox && y < 690 {
                        if a != 0 {
                            XCTFail("\(id): pixel (\(x), \(y)) drawn outside the sprite bounds")
                            return
                        }
                    } else if inBox && y < 690 && a > 200 {
                        inside += 1
                    }
                }
            }
            XCTAssertTrue(inside > 50, "\(id): sprite not drawn (\(inside) opaque samples)")
        }
        check("bob", .WALK, .FRONT, false, 202, 258, 397)
        check("woman_dark", .SHOT_SET, .SIDE, true, 201, 260, 419)
    }
}

// MARK: - Golden data (generated by work/t-visuals/gen_tests.py from golden.txt)

private let VISUALS_CATALOG_ROWS = 534
private let VISUALS_RAW_ROWS = 31
private let VISUALS_HELD_ROWS = 1500
private let VISUALS_DRAWABLE_COUNT = 606

/// TripleShotShotPresentation golden rows (harness `presentation()`).
private let visualsPresentationGolden = """
PRESENT_FLIGHT|0|43d70000|442f0000|bfc00000,3fe66666,40a66666
PRESENT_FLIGHT|0.25|43ff0000|4407a000|bec00000,401abae1,40334e26
PRESENT_FLIGHT|0.5|44138000|43d70000|3f400000,403a28f6,3fac2056
PRESENT_FLIGHT|0.75|44278000|43b54000|3ff00000,404ee8f5,3f03f538
PRESENT_FLIGHT|1|443b8000|43aa0000|40400000,40566666,00000000
PRESENT_REST|40400000,4066b852,3f0ccccd
PRESENT_BOARD|40400000,406b851e,beeb8520
PRESENT_REC|0|c0000000,3fd9999a,40800000
PRESENT_REC|0.5|3f000000,4019ae14,3fbc2056
PRESENT_REC|1|40400000,40566666,3f0ccccd
PRESENT_X1|3fe66666,402dd441,3fca2a20
PRESENT_X2|400ccccd,403cd20a,3f711d41
PRESENT_X3|40accccc,40597e12,3fa9b58a
PRESENT_X4|40400000,40647ae1,bf6147ae
PRESENT_X5|40400000,403a3aa7,bd6c8881
PRESENT_X6|3e4cccc0,3faeefb3,3fe4c92e
PRESENT_X7|40400000,405c760a,bf496935
PRESENT_X8|40400000,3e8a3d70,3f5e50d8
PRESENT_X9|40400000,3e8a3d70,43898000
PRESENT_X10|c0133333,40267c9a,3f75cf5b
"""

/// winnerJumpOffsetPx: `JUMP|density|progress|bits`.
private let visualsJumpGolden = """
JUMP|1|0|00000000
JUMP|1|0.05|413c175e
JUMP|1|0.125|41a00000
JUMP|1|0.3|413c1764
JUMP|1|0.5|366aac7a
JUMP|1|0.77|409f295f
JUMP|1|1|36eaac7a
JUMP|1|1.5|36eaac7a
JUMP|1|-0.5|00000000
JUMP|2|0|00000000
JUMP|2|0.05|41bc175e
JUMP|2|0.125|42200000
JUMP|2|0.3|41bc1764
JUMP|2|0.5|36eaac7a
JUMP|2|0.77|411f295f
JUMP|2|1|376aac7a
JUMP|2|1.5|376aac7a
JUMP|2|-0.5|00000000
JUMP|3|0|00000000
JUMP|3|0.05|420d1186
JUMP|3|0.125|42700000
JUMP|3|0.3|420d118b
JUMP|3|0.5|3730015b
JUMP|3|0.77|416ebe0e
JUMP|3|1|37b0015b
JUMP|3|1.5|37b0015b
JUMP|3|-0.5|00000000
"""

/// Spec 07 section 4.5: `SPEC|case|worldFrame|heldX|heldY|x|y`.
private let visualsSpecGolden = """
SPEC|maya-idle-back|woman_dark_back_standing|44068ccd|444b0000|538.2|812.0
SPEC|maya-idle-back-left-hand|woman_dark_back_standing|43e6e666|444b0000|461.8|812.0
SPEC|maya-set-side-mirror-1v1|woman_dark_shot_side_set|43e6cb9c|442fa7e7|461.5907|702.6235
SPEC|bob-set-front|basket_bob_12|43480000|43c97495|200.0|402.9108
SPEC|gaya-dribble-front-025|basket_gaya_ground_21|43990000|4423c8c0|306.0|655.1367
SPEC|gaya-dribble-front-075|basket_gaya_ground_21|43930000|4423c8c0|294.0|655.1367
SPEC|mia-fast-dribble-back|basket_nova_06|43c18000|443dc000|387.0|759.0
SPEC|maya-block-front-legacy|woman_dark_block_front|4401cccd|44534000|519.2|845.0
SPEC|maya-dunk-side-7|woman_dark_dunk_side_reverse_gather|44084800|442e3c00|545.125|696.9375
SPEC|granny-no-id|-|42e00000|43818000|112.0|259.0
"""

/// Raw-table digests: `RAW|source|name|fnv1a64(setEncoding)|lines`.
private let visualsRawGolden = """
RAW|hand|womanDark|9871a18461d2f1a4|38
RAW|hand|miaEssenceSkies|c675791141cec7ea|38
RAW|hand|coach67|34e9a35f7babdab2|38
RAW|hand|zephyr|410b20235b6d7238|38
RAW|hand|flare|c9875b13bc4b9c67|38
RAW|completion|buddy_23|e77b6e72faab89b6|37
RAW|completion|ace_23|e82c6c6ff0e7d119|37
RAW|completion|rooza|145b82c5dc87ab37|37
RAW|completion|unicorn_32|10e46d73edc5f38e|37
RAW|completion|kyra|8cb8776397cf510|37
RAW|completion|bob|ba768e4b563ed824|37
RAW|completion|woman_dark|15025cee12900361|37
RAW|completion|nova|84a61e001b73d9a|37
RAW|completion|coach_67|a1b403b9b48cb1bf|37
RAW|completion|zephyr|9cf7fd96b19946f1|37
RAW|completion|flare|75a3d9c83ff9a4d6|37
RAW|feedback|kyra|586756cf234adc07|37
RAW|catalog|bob|ba768e4b563ed824|37
RAW|catalog|woman_dark|2e9aa81e3f05c5dd|44
RAW|catalog|rooza|145b82c5dc87ab37|37
RAW|catalog|nova|973fcdea4cf494ef|44
RAW|catalog|unicorn_32|10e46d73edc5f38e|37
RAW|catalog|coach_67|5b08f3d535a34533|44
RAW|catalog|zephyr|1e768af8e4c9dacb|44
RAW|catalog|kyra|7fbd9c1eccd38e33|37
RAW|catalog|kyra_original|586756cf234adc07|37
RAW|catalog|flare|13aca919124925c0|44
RAW|catalog|ace_23|e82c6c6ff0e7d119|37
RAW|catalog|buddy_23|e77b6e72faab89b6|37
RAW|fnv-check|abc|e71fa2190541574b|1
RAW|nulls|true|true|true
"""

/// Resolved catalog: `SET|id|characterId|refPx|refDp|dunks|locomotion`, `SLOT|id|slot|frame`,
/// `DUNK|id|i|facing|speed|weight|lift|outward|inFront|frame`, `DRIBBLE|id|facing|frame`, `PREVIEW|id|drawable`,
/// `NOSET|id|findIsNull|hasVisuals|preview`, `PLAYABLE|ids`. frame = drawable,anchorX,anchorY,ballX,ballY,height,rect.
private let visualsCatalogGolden = """
SET|bob|bob|43700000|43480000|3|2
SLOT|bob|idleBack|basket_bob_01,3f000000,3f800000,429e5c29,4302e667,43300000,-
SLOT|bob|idleFront|basket_bob_00,3f000000,3f800000,429b6667,4302e667,43300000,-
SLOT|bob|idleSide|basket_bob_02,3f000000,3f800000,4231999a,43037333,43300000,-
SLOT|bob|shotBack.low|basket_bob_10,3f000000,3f800000,4294eb85,43002e14,431bc28f,-
SLOT|bob|shotBack.mid|basket_bob_extra_01,3f000000,3f800000,42ae0000,42f4cccd,434d0000,-
SLOT|bob|shotBack.set|basket_bob_13,3f000000,3f800000,42560000,41630a3d,43508f5c,-
SLOT|bob|shotBack.release|basket_bob_16,3f000000,3f800000,42af70a4,410f5c29,43460000,-
SLOT|bob|shotSide.low|basket_bob_11,3f000000,3f800000,42e5147b,42c43333,431bc28f,-
SLOT|bob|shotSide.mid|basket_bob_extra_02,3f000000,3f800000,429c0000,42f0cccd,434d0000,-
SLOT|bob|shotSide.set|basket_bob_14,3f000000,3f800000,42701eb8,4164cccd,43508f5c,-
SLOT|bob|shotSide.release|basket_bob_17,3f000000,3f800000,4296f5c3,410e3d71,43460000,-
SLOT|bob|shotFront.low|basket_bob_09,3f000000,3f800000,42990000,42fa8f5c,431bc28f,-
SLOT|bob|shotFront.mid|basket_bob_extra_00,3f000000,3f800000,42bc0000,42f66666,434d0000,-
SLOT|bob|shotFront.set|basket_bob_12,3f000000,3f800000,42520000,41630a3d,43508f5c,-
SLOT|bob|shotFront.release|basket_bob_15,3f000000,3f800000,4208a3d7,4111999a,43460000,-
SLOT|bob|steal.back|basket_bob_19,3f000000,3f800000,430547ae,40d4cccd,4313d70a,-
SLOT|bob|steal.side|basket_bob_20,3f000000,3f800000,43033d71,40d70a3e,4313d70a,-
SLOT|bob|steal.front|basket_bob_18,3f000000,3f800000,430c147b,40dca3d7,4313d70a,-
SLOT|bob|block.back|basket_bob_extra_04,3f000000,3f800000,42b8cccd,41547ae1,436d0000,-
SLOT|bob|block.side|basket_bob_extra_05,3f000000,3f800000,42c08000,41533333,436d0000,-
SLOT|bob|block.front|basket_bob_extra_03,3f000000,3f800000,42bd3333,41566666,436d0000,-
SLOT|bob|rebound.back|basket_bob_extra_07,3f000000,3f800000,42bd3333,4155c28f,436d0000,-
SLOT|bob|rebound.side|basket_bob_extra_08,3f000000,3f800000,429e6666,415147ae,436d0000,-
SLOT|bob|rebound.front|basket_bob_extra_06,3f000000,3f800000,42cdb333,41570a3d,436d0000,-
SLOT|bob|locomotion0.back|basket_bob_05,3f000000,3f800000,429ce148,43037333,43300000,-
SLOT|bob|locomotion0.side|basket_bob_07,3f000000,3f800000,430ed1ec,42f78000,43300000,-
SLOT|bob|locomotion0.front|basket_bob_03,3f000000,3f800000,429870a4,43037333,43300000,-
SLOT|bob|locomotion1.back|basket_bob_06,3f000000,3f800000,429fd70a,42fbe667,43300000,-
SLOT|bob|locomotion1.side|basket_bob_08,3f000000,3f800000,430d570a,42f20000,43300000,-
SLOT|bob|locomotion1.front|basket_bob_04,3f000000,3f800000,42910a3e,43014000,43300000,-
DUNK|bob|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_bob_21,3f000000,3f800000,4223851f,4104b852,433d3333,-
DUNK|bob|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_bob_22,3f000000,3f800000,42af70a4,4105d70a,433d3333,-
DUNK|bob|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_bob_23,3f000000,3f800000,4299ae15,4108a3d7,433d3333,-
SLOT|bob|winner|basket_bob_extra_09,3f000000,3f800000,42c7199a,414ae148,43570000,-
SLOT|bob|loser|basket_bob_extra_10,3f000000,3f800000,42b58000,414ccccd,43480000,-
SLOT|bob|spectator|basket_bob_extra_11,3f000000,3f800000,42b58000,414c28f6,43480000,-
DRIBBLE|bob|BACK|-
DRIBBLE|bob|SIDE|-
DRIBBLE|bob|FRONT|-
PREVIEW|bob|basket_bob_00
SET|woman_dark|woman_dark|43fa0000|43480000|10|2
SLOT|woman_dark|idleBack|woman_dark_back_standing,3f000000,3f800000,43560000,438b0000,-,-
SLOT|woman_dark|idleFront|woman_dark_front_defense,3f000000,3f800000,436e0000,43770000,-,-
SLOT|woman_dark|idleSide|basket_woman_dark_02,3f000000,3f800000,4299eb85,43150ccd,43480000,-
SLOT|woman_dark|shotBack.low|woman_dark_shot_back_low,3efd70a4,3f800000,43930000,4400c000,43350000,-
SLOT|woman_dark|shotBack.mid|woman_dark_shot_back_mid,3f008312,3f800000,438b8000,43250000,43350000,-
SLOT|woman_dark|shotBack.set|woman_dark_shot_back_set,3f000000,3f800000,43720000,42780000,43480000,-
SLOT|woman_dark|shotBack.release|woman_dark_back_after_throw,3f000000,3f800000,-,-,-,-
SLOT|woman_dark|shotSide.low|woman_dark_shot_side_low,3ef3b646,3f800000,4409c000,440ac000,43350000,-
SLOT|woman_dark|shotSide.mid|woman_dark_shot_side_mid,3ef33333,3f800000,4426c000,43c40000,433a0000,3f19999a:3e3851ec:3f800000:3ec7ae14
SLOT|woman_dark|shotSide.set|woman_dark_shot_side_set,3f0b4396,3f800000,44090000,42fe0000,43480000,3f147ae1:00000000:3f800000:3e8a3d71
SLOT|woman_dark|shotSide.release|basket_woman_dark_17,3f000000,3f800000,42ae147b,4114f5c3,43610000,-
SLOT|woman_dark|shotFront.low|woman_dark_shot_front_low,3f000000,3f800000,439f0000,44110000,43350000,-
SLOT|woman_dark|shotFront.mid|woman_dark_shot_front_mid,3f000000,3f800000,43840000,43820000,433c0000,-
SLOT|woman_dark|shotFront.set|woman_dark_shot_front_set,3f028f5c,3f800000,436e0000,42880000,43480000,-
SLOT|woman_dark|shotFront.release|basket_woman_dark_15,3f000000,3f800000,41eb3333,411ccccd,43610000,-
SLOT|woman_dark|steal.back|woman_dark_steal_back,3f000000,3f800000,-,-,43320000,-
SLOT|woman_dark|steal.side|woman_dark_steal_side,3f000000,3f800000,-,-,43190000,-
SLOT|woman_dark|steal.front|woman_dark_steal_front,3f000000,3f8e147b,-,-,42dc0000,-
SLOT|woman_dark|block.back|woman_dark_block_back,3f000000,3f800000,-,-,434b0000,-
SLOT|woman_dark|block.side|woman_dark_block_side,3f000000,3f800000,-,-,43500000,-
SLOT|woman_dark|block.front|woman_dark_block_front,3f000000,3f800000,-,-,432a0000,-
SLOT|woman_dark|rebound.back|woman_dark_rebound_back,3f000000,3f800000,-,-,43290000,-
SLOT|woman_dark|rebound.side|woman_dark_rebound_side,3f000000,3f800000,-,-,434e0000,-
SLOT|woman_dark|rebound.front|woman_dark_rebound_front,3f000000,3f800000,-,-,43370000,-
SLOT|woman_dark|locomotion0.back|basket_woman_dark_05,3f000000,3f800000,4296f5c3,43148000,43480000,-
SLOT|woman_dark|locomotion0.side|basket_woman_dark_07,3f000000,3f800000,4303b852,43037333,43480000,-
SLOT|woman_dark|locomotion0.front|basket_woman_dark_03,3f000000,3f800000,42940000,4313f333,43480000,-
SLOT|woman_dark|locomotion1.back|basket_woman_dark_06,3f000000,3f800000,429ce148,4305a667,43480000,-
SLOT|woman_dark|locomotion1.side|basket_woman_dark_08,3f000000,3f800000,43023d71,4300b333,43480000,-
SLOT|woman_dark|locomotion1.front|basket_woman_dark_04,3f000000,3f800000,4296f5c3,4313f333,43480000,-
DUNK|woman_dark|0|BACK|3f70a3d7|3f99999a|40c00000|00000000|false|woman_dark_dunk_back_one_hand,3f000000,3f800000,441a4000,42540000,43660000,-
DUNK|woman_dark|1|BACK|3f570a3d|3f866666|41900000|40000000|true|woman_dark_dunk_back_two_hand_power,3f000000,3f800000,43f28000,422c0000,43680000,-
DUNK|woman_dark|2|BACK|3f428f5c|3f6b851f|41a00000|40800000|true|woman_dark_dunk_back_two_hand_hang,3f000000,3f800000,43f28000,42200000,436a0000,-
DUNK|woman_dark|3|FRONT|3f570a3d|3f866666|40a00000|00000000|false|woman_dark_dunk_front_two_hand_power,3f000000,3f800000,43f50000,42340000,43660000,-
DUNK|woman_dark|4|FRONT|3f400000|3f6b851f|41600000|40800000|true|woman_dark_dunk_front_two_hand_hang,3f000000,3f800000,43e38000,42000000,436a0000,-
DUNK|woman_dark|5|FRONT|3f75c28f|3f970a3d|40c00000|40000000|false|woman_dark_dunk_front_statue,3f000000,3f800000,44200000,42700000,43680000,-
DUNK|woman_dark|6|SIDE|3f3851ec|3f6147ae|41900000|41400000|true|woman_dark_dunk_side_two_hand_gather,3f000000,3f800000,440c0000,425c0000,43620000,-
DUNK|woman_dark|7|SIDE|3f4ccccd|3f666666|41b00000|41700000|true|woman_dark_dunk_side_reverse_gather,3f000000,3f800000,44098000,42d20000,43640000,-
DUNK|woman_dark|8|SIDE|3f5c28f6|3f866666|41980000|41500000|true|woman_dark_dunk_side_two_hand_hang,3f000000,3f800000,44068000,42340000,43680000,-
DUNK|woman_dark|9|SIDE|3f7ae148|3f9c28f6|40e00000|40800000|false|woman_dark_dunk_side_statue,3f000000,3f800000,441cc000,42600000,43680000,-
SLOT|woman_dark|winner|woman_dark_front_celebrate,3f07ae14,3f800000,-,-,-,-
SLOT|woman_dark|loser|woman_dark_front_sitting_sad,3f000000,3f800000,-,-,-,-
SLOT|woman_dark|spectator|woman_dark_front_sitting,3f000000,3f800000,-,-,-,-
DRIBBLE|woman_dark|BACK|-
DRIBBLE|woman_dark|SIDE|-
DRIBBLE|woman_dark|FRONT|-
PREVIEW|woman_dark|woman_dark_front_defense
SET|rooza|rooza|43700000|43480000|3|2
SLOT|rooza|idleBack|basket_rooza_01,3f000000,3f800000,42b7851f,4306c000,43480000,-
SLOT|rooza|idleFront|basket_rooza_00,3f000000,3f800000,42beeb85,43048ccd,43480000,-
SLOT|rooza|idleSide|basket_rooza_02,3f000000,3f800000,42c651ec,4307d99a,43480000,-
SLOT|rooza|shotBack.low|basket_rooza_10,3f000000,3f800000,42a53d70,4301eb85,43310000,-
SLOT|rooza|shotBack.mid|basket_rooza_extra_01,3f000000,3f800000,42e10000,43053333,434d0000,-
SLOT|rooza|shotBack.set|basket_rooza_13,3f000000,3f800000,42780000,415b1eb8,436d0000,-
SLOT|rooza|shotBack.release|basket_rooza_16,3f000000,3f800000,42aa0000,4108a3d7,43610000,-
SLOT|rooza|shotSide.low|basket_rooza_11,3f000000,3f800000,4305a148,42d29999,43310000,-
SLOT|rooza|shotSide.mid|basket_rooza_extra_02,3f000000,3f800000,42e30000,43073333,434d0000,-
SLOT|rooza|shotSide.set|basket_rooza_14,3f000000,3f800000,42a2d70a,415c0000,436d0000,-
SLOT|rooza|shotSide.release|basket_rooza_17,3f000000,3f800000,42c7eb85,41066666,43610000,-
SLOT|rooza|shotFront.low|basket_rooza_09,3f000000,3f800000,42a128f6,43043d70,43310000,-
SLOT|rooza|shotFront.mid|basket_rooza_extra_00,3f000000,3f800000,42e90000,43073333,434d0000,-
SLOT|rooza|shotFront.set|basket_rooza_12,3f000000,3f800000,42820000,415b1eb8,436d0000,-
SLOT|rooza|shotFront.release|basket_rooza_15,3f000000,3f800000,421ccccd,410a51ec,43610000,-
SLOT|rooza|steal.back|basket_rooza_19,3f000000,3f800000,42fcf5c3,40e7d70a,43280000,-
SLOT|rooza|steal.side|basket_rooza_20,3f000000,3f800000,4300851f,40ed70a4,43280000,-
SLOT|rooza|steal.front|basket_rooza_18,3f000000,3f800000,4304999a,40e5999a,43280000,-
SLOT|rooza|block.back|basket_rooza_extra_04,3f000000,3f800000,430d599a,414d70a4,436d0000,-
SLOT|rooza|block.side|basket_rooza_extra_05,3f000000,3f800000,42e8199a,414d70a4,436d0000,-
SLOT|rooza|block.front|basket_rooza_extra_03,3f000000,3f800000,4310a666,41600000,436d0000,-
SLOT|rooza|rebound.back|basket_rooza_extra_07,3f000000,3f800000,42d9cccd,4158f5c3,436d0000,-
SLOT|rooza|rebound.side|basket_rooza_extra_08,3f000000,3f800000,42d68000,4160a3d7,436d0000,-
SLOT|rooza|rebound.front|basket_rooza_extra_06,3f000000,3f800000,42d8b333,4158f5c3,436d0000,-
SLOT|rooza|locomotion0.back|basket_rooza_05,3f000000,3f800000,429ce148,43086667,43480000,-
SLOT|rooza|locomotion0.side|basket_rooza_07,3f000000,3f800000,430828f6,4301cccd,43480000,-
SLOT|rooza|locomotion0.front|basket_rooza_03,3f000000,3f800000,42abae15,4308f333,43480000,-
SLOT|rooza|locomotion1.back|basket_rooza_06,3f000000,3f800000,42a151ec,43048ccd,43480000,-
SLOT|rooza|locomotion1.side|basket_rooza_08,3f000000,3f800000,430ed1ec,4301cccd,43480000,-
SLOT|rooza|locomotion1.front|basket_rooza_04,3f000000,3f800000,42a2cccd,43098000,43480000,-
DUNK|rooza|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_rooza_21,3f000000,3f800000,421deb85,410428f6,43570000,-
DUNK|rooza|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_rooza_22,3f000000,3f800000,42af70a4,410ae148,43570000,-
DUNK|rooza|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_rooza_23,3f000000,3f800000,42bd0a3e,41030a3d,43570000,-
SLOT|rooza|winner|basket_rooza_extra_09,3f000000,3f800000,42f20000,4159999a,43570000,-
SLOT|rooza|loser|basket_rooza_extra_10,3f000000,3f800000,42d56666,415ccccd,43480000,-
SLOT|rooza|spectator|basket_rooza_extra_11,3f000000,3f800000,42e3b333,415f5c29,43480000,-
DRIBBLE|rooza|BACK|-
DRIBBLE|rooza|SIDE|-
DRIBBLE|rooza|FRONT|-
PREVIEW|rooza|basket_rooza_00
SET|nova|nova|44610000|43480000|10|2
SLOT|nova|idleBack|nova_idle_back,3f000000,3f800000,43a6c000,43f87333,-,-
SLOT|nova|idleFront|nova_idle_front,3f000000,3f800000,440ae666,43ef4000,-,-
SLOT|nova|idleSide|basket_nova_02,3f000000,3f800000,42406667,430f8ccd,43480000,-
SLOT|nova|shotBack.low|nova_shot_back_low,3f000000,3f800000,43354ccd,43bba666,43350000,-
SLOT|nova|shotBack.mid|nova_shot_back_mid,3f000000,3f800000,43378000,42f0cccd,433c0000,-
SLOT|nova|shotBack.set|nova_shot_back_set,3f000000,3f800000,43396666,423a0000,43480000,-
SLOT|nova|shotBack.release|nova_release_back,3f000000,3f800000,-,-,-,-
SLOT|nova|shotSide.low|nova_shot_side_low,3f000000,3f800000,43db599a,43cd4000,43350000,-
SLOT|nova|shotSide.mid|nova_shot_side_mid,3f000000,3f800000,43c2a666,436e8000,433c0000,-
SLOT|nova|shotSide.set|nova_shot_side_set,3f000000,3f800000,43b9599a,42ca999a,43480000,-
SLOT|nova|shotSide.release|basket_nova_17,3f000000,3f800000,429b0a3e,411e7ae1,43610000,-
SLOT|nova|shotFront.low|nova_shot_front_low,3f000000,3f800000,4344cccd,43d4cccd,43350000,-
SLOT|nova|shotFront.mid|nova_shot_front_mid,3f000000,3f800000,433c6666,433d3333,433c0000,-
SLOT|nova|shotFront.set|nova_shot_front_set,3f000000,3f800000,433b0000,42506666,43480000,-
SLOT|nova|shotFront.release|basket_nova_15,3f000000,3f800000,41fae148,411d5c29,43610000,-
SLOT|nova|steal.back|nova_steal_back,3f000000,3f800000,-,-,43320000,-
SLOT|nova|steal.side|nova_steal_side,3f000000,3f800000,-,-,43190000,-
SLOT|nova|steal.front|nova_steal_front,3f000000,3f8e147b,-,-,42dc0000,-
SLOT|nova|block.back|nova_block_back,3f000000,3f800000,-,-,434b0000,-
SLOT|nova|block.side|nova_block_side,3f000000,3f800000,-,-,43500000,-
SLOT|nova|block.front|nova_block_front,3f000000,3f800000,-,-,432a0000,-
SLOT|nova|rebound.back|nova_rebound_back,3f000000,3f800000,-,-,43290000,-
SLOT|nova|rebound.side|nova_rebound_side,3f000000,3f800000,-,-,434e0000,-
SLOT|nova|rebound.front|nova_rebound_front,3f000000,3f800000,-,-,43370000,-
SLOT|nova|locomotion0.back|basket_nova_05,3f000000,3f800000,42853333,4310199a,43480000,-
SLOT|nova|locomotion0.side|basket_nova_07,3f000000,3f800000,43018000,4302599a,43480000,-
SLOT|nova|locomotion0.front|basket_nova_03,3f000000,3f800000,4286ae15,4310199a,43480000,-
SLOT|nova|locomotion1.back|basket_nova_06,3f000000,3f800000,42940000,43074ccd,43480000,-
SLOT|nova|locomotion1.side|basket_nova_08,3f000000,3f800000,431aa8f6,43048ccd,43480000,-
SLOT|nova|locomotion1.front|basket_nova_04,3f000000,3f800000,4286ae15,4310a667,43480000,-
DUNK|nova|0|BACK|3f70a3d7|3f99999a|40c00000|00000000|false|nova_dunk_back_one_hand,3f000000,3f800000,43f40000,42520000,43660000,-
DUNK|nova|1|BACK|3f570a3d|3f866666|41900000|40000000|true|nova_dunk_back_two_hand_power,3f000000,3f800000,43dacccd,42320000,43680000,-
DUNK|nova|2|BACK|3f428f5c|3f6b851f|41a00000|40800000|true|nova_dunk_back_two_hand_hang,3f000000,3f800000,43ae0ccd,4210cccd,436a0000,-
DUNK|nova|3|FRONT|3f570a3d|3f866666|40a00000|00000000|false|nova_dunk_front_two_hand_power,3f000000,3f800000,43a2b333,4227999a,43660000,-
DUNK|nova|4|FRONT|3f400000|3f6b851f|41600000|40800000|true|nova_dunk_front_two_hand_hang,3f000000,3f800000,438e0000,41fb3333,436a0000,-
DUNK|nova|5|FRONT|3f75c28f|3f970a3d|40c00000|40000000|false|nova_dunk_front_statue,3f000000,3f800000,4417a000,42646666,43680000,-
DUNK|nova|6|SIDE|3f3851ec|3f6147ae|41900000|41400000|true|nova_dunk_side_two_hand_gather,3f000000,3f800000,43f3599a,425a6666,43620000,-
DUNK|nova|7|SIDE|3f4ccccd|3f666666|41b00000|41700000|true|nova_dunk_side_reverse_gather,3f000000,3f800000,43e04ccd,42d20000,43640000,-
DUNK|nova|8|SIDE|3f5c28f6|3f866666|41980000|41500000|true|nova_dunk_side_two_hand_hang,3f000000,3f800000,43ca4000,420f3333,43680000,-
DUNK|nova|9|SIDE|3f7ae148|3f9c28f6|40e00000|40800000|false|nova_dunk_side_statue,3f000000,3f800000,43e7e666,42686666,43680000,-
SLOT|nova|winner|nova_winner,3f000000,3f800000,-,-,433e0000,-
SLOT|nova|loser|nova_loser,3f000000,3f800000,-,-,43000000,-
SLOT|nova|spectator|nova_spectator,3f000000,3f800000,-,-,43000000,-
DRIBBLE|nova|BACK|-
DRIBBLE|nova|SIDE|-
DRIBBLE|nova|FRONT|-
PREVIEW|nova|nova_idle_front
SET|unicorn_32|unicorn_32|43700000|43480000|3|2
SLOT|unicorn_32|idleBack|basket_unicorn_32_01,3f000000,3f800000,43076b85,4308f333,43480000,-
SLOT|unicorn_32|idleFront|basket_unicorn_32_00,3f000000,3f800000,4308e667,4308f333,43480000,-
SLOT|unicorn_32|idleSide|basket_unicorn_32_02,3f000000,3f800000,42cf3333,430a999a,43480000,-
SLOT|unicorn_32|shotBack.low|basket_unicorn_32_10,3f000000,3f800000,42d52e14,4305fae1,43310000,-
SLOT|unicorn_32|shotBack.mid|basket_unicorn_32_extra_01,3f000000,3f800000,42eb0000,43006666,434d0000,-
SLOT|unicorn_32|shotBack.set|basket_unicorn_32_13,3f000000,3f800000,429f0000,415ea3d7,436d0000,-
SLOT|unicorn_32|shotBack.release|basket_unicorn_32_16,3f000000,3f800000,42d428f6,411b1eb8,43610000,-
SLOT|unicorn_32|shotSide.low|basket_unicorn_32_11,3f000000,3f800000,43198ccd,42d0cccc,43310000,-
SLOT|unicorn_32|shotSide.mid|basket_unicorn_32_extra_02,3f000000,3f800000,42f10000,43020000,434d0000,-
SLOT|unicorn_32|shotSide.set|basket_unicorn_32_14,3f000000,3f800000,42b2051f,416147ae,436d0000,-
SLOT|unicorn_32|shotSide.release|basket_unicorn_32_17,3f000000,3f800000,42ceb852,4112b852,43610000,-
SLOT|unicorn_32|shotFront.low|basket_unicorn_32_09,3f000000,3f800000,42c8f0a4,43043d70,43310000,-
SLOT|unicorn_32|shotFront.mid|basket_unicorn_32_extra_00,3f000000,3f800000,43038000,4302cccd,434d0000,-
SLOT|unicorn_32|shotFront.set|basket_unicorn_32_12,3f000000,3f800000,42ab0000,415dc28f,436d0000,-
SLOT|unicorn_32|shotFront.release|basket_unicorn_32_15,3f000000,3f800000,4230f5c3,410547ae,43610000,-
SLOT|unicorn_32|steal.back|basket_unicorn_32_19,3f000000,3f800000,431dc28f,40dee148,43280000,-
SLOT|unicorn_32|steal.side|basket_unicorn_32_20,3f000000,3f800000,431a5c29,40e6b852,43280000,-
SLOT|unicorn_32|steal.front|basket_unicorn_32_18,3f000000,3f800000,431bb852,40e6b852,43280000,-
SLOT|unicorn_32|block.back|basket_unicorn_32_extra_04,3f000000,3f800000,42f0e666,4151eb85,436d0000,-
SLOT|unicorn_32|block.side|basket_unicorn_32_extra_05,3f000000,3f800000,42d2199a,415c28f6,436d0000,-
SLOT|unicorn_32|block.front|basket_unicorn_32_extra_03,3f000000,3f800000,430a999a,41570a3d,436d0000,-
SLOT|unicorn_32|rebound.back|basket_unicorn_32_extra_07,3f000000,3f800000,42dae666,41566666,436d0000,-
SLOT|unicorn_32|rebound.side|basket_unicorn_32_extra_08,3f000000,3f800000,42f20000,4163d70a,436d0000,-
SLOT|unicorn_32|rebound.front|basket_unicorn_32_extra_06,3f000000,3f800000,42cfe666,415c28f6,436d0000,-
SLOT|unicorn_32|locomotion0.back|basket_unicorn_32_05,3f000000,3f800000,42f43333,43098000,43480000,-
SLOT|unicorn_32|locomotion0.side|basket_unicorn_32_07,3f000000,3f800000,431b6667,42f9b334,43480000,-
SLOT|unicorn_32|locomotion0.front|basket_unicorn_32_03,3f000000,3f800000,42e85c29,430c4000,43480000,-
SLOT|unicorn_32|locomotion1.back|basket_unicorn_32_06,3f000000,3f800000,42f2b852,43048ccd,43480000,-
SLOT|unicorn_32|locomotion1.side|basket_unicorn_32_08,3f000000,3f800000,4312851f,42f9b334,43480000,-
SLOT|unicorn_32|locomotion1.front|basket_unicorn_32_04,3f000000,3f800000,42fa1eb9,430a0ccd,43480000,-
DUNK|unicorn_32|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_unicorn_32_21,3f000000,3f800000,423b0a3d,4106f5c3,43570000,-
DUNK|unicorn_32|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_unicorn_32_22,3f000000,3f800000,42e9eb85,40fd1eb8,43570000,-
DUNK|unicorn_32|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_unicorn_32_23,3f000000,3f800000,42d0147b,4107851f,43570000,-
SLOT|unicorn_32|winner|basket_unicorn_32_extra_09,3f000000,3f800000,43040000,41570a3d,43570000,-
SLOT|unicorn_32|loser|basket_unicorn_32_extra_10,3f000000,3f800000,42facccd,415c28f6,43480000,-
SLOT|unicorn_32|spectator|basket_unicorn_32_extra_11,3f000000,3f800000,42ff3333,415b851f,43480000,-
DRIBBLE|unicorn_32|BACK|-
DRIBBLE|unicorn_32|SIDE|-
DRIBBLE|unicorn_32|FRONT|-
PREVIEW|unicorn_32|basket_unicorn_32_00
SET|coach_67|coach_67|43ee8000|43480000|10|2
SLOT|coach_67|idleBack|coach_67_back_standing,3f000000,3f800000,435d199a,43838ccd,-,-
SLOT|coach_67|idleFront|coach_67_front_defense,3f000000,3f800000,4391199a,43666666,-,-
SLOT|coach_67|idleSide|basket_coach_67_02,3f000000,3f800000,428828f6,430d599a,43480000,-
SLOT|coach_67|shotBack.low|coach_67_shot_back_mid,3f000000,3f800000,43050000,42780000,434a0000,3e75c28f:3d6147ae:3f428f5c:3e3851ec
SLOT|coach_67|shotBack.mid|coach_67_shot_back_mid,3f000000,3f800000,43050000,42893333,434a0000,3e75c28f:3d6147ae:3f428f5c:3e3851ec
SLOT|coach_67|shotBack.set|coach_67_shot_back_set,3f000000,3f800000,42ff6666,4204cccd,435e0000,3e75c28f:3c23d70a:3f428f5c:3deb851f
SLOT|coach_67|shotBack.release|coach_67_back_after_throw,3f000000,3f800000,-,-,-,-
SLOT|coach_67|shotSide.low|coach_67_shot_side_low,3f000000,3f800000,43633333,435bcccd,434c0000,-
SLOT|coach_67|shotSide.mid|coach_67_shot_side_mid,3f000000,3f800000,4373b333,4302199a,43520000,3f266666:3e3851ec:3f7d70a4:3eb851ec
SLOT|coach_67|shotSide.set|coach_67_shot_side_set,3f000000,3f800000,4363b333,4263999a,43550000,3f2147ae:3d23d70a:3f7d70a4:3e6b851f
SLOT|coach_67|shotSide.release|basket_coach_67_17,3f000000,3f800000,42ba51ec,411ccccd,43610000,-
SLOT|coach_67|shotFront.low|coach_67_shot_front_low,3f000000,3f800000,43233333,4348b333,43350000,-
SLOT|coach_67|shotFront.mid|coach_67_shot_front_mid,3f000000,3f800000,43033333,42d70000,43500000,3e800000:3e23d70a:3f400000:3ea8f5c3
SLOT|coach_67|shotFront.set|coach_67_shot_front_set,3f000000,3f800000,43020000,42120000,43600000,3e800000:3c23d70a:3f400000:3e051eb8
SLOT|coach_67|shotFront.release|basket_coach_67_15,3f000000,3f800000,423b0a3d,4105d70a,43610000,-
SLOT|coach_67|steal.back|coach_67_steal_back,3f000000,3f800000,-,-,43460000,-
SLOT|coach_67|steal.side|coach_67_steal_side,3f000000,3f800000,-,-,431d0000,-
SLOT|coach_67|steal.front|coach_67_steal_front,3f000000,3f7ae148,-,-,43170000,-
SLOT|coach_67|block.back|coach_67_block_back,3f000000,3f800000,-,-,43640000,-
SLOT|coach_67|block.side|coach_67_block_side,3f000000,3f800000,-,-,43640000,-
SLOT|coach_67|block.front|coach_67_block_front,3f000000,3f800000,-,-,43550000,-
SLOT|coach_67|rebound.back|coach_67_rebound_back,3f000000,3f800000,-,-,43650000,-
SLOT|coach_67|rebound.side|coach_67_rebound_side,3f000000,3f800000,-,-,43640000,-
SLOT|coach_67|rebound.front|coach_67_rebound_front,3f000000,3f800000,-,-,43660000,-
SLOT|coach_67|locomotion0.back|basket_coach_67_05,3f000000,3f800000,42c35c29,430bb333,43480000,-
SLOT|coach_67|locomotion0.side|basket_coach_67_07,3f000000,3f800000,4319eb85,43002667,43480000,-
SLOT|coach_67|locomotion0.front|basket_coach_67_03,3f000000,3f800000,42b7851f,430f8ccd,43480000,-
SLOT|coach_67|locomotion1.back|basket_coach_67_06,3f000000,3f800000,42beeb85,43037333,43480000,-
SLOT|coach_67|locomotion1.side|basket_coach_67_08,3f000000,3f800000,4317b333,43002667,43480000,-
SLOT|coach_67|locomotion1.front|basket_coach_67_04,3f000000,3f800000,42ba7ae1,430f8ccd,43480000,-
DUNK|coach_67|0|BACK|3f70a3d7|3f99999a|40c00000|00000000|false|coach_67_dunk_back_one_hand,3f000000,3f800000,437e999a,42060000,43660000,-
DUNK|coach_67|1|BACK|3f570a3d|3f866666|41900000|40000000|true|coach_67_dunk_back_two_hand_power,3f000000,3f800000,433d4ccd,41e4cccd,43680000,-
DUNK|coach_67|2|BACK|3f428f5c|3f6b851f|41a00000|40800000|true|coach_67_dunk_back_two_hand_hang,3f000000,3f800000,4360b333,41a80000,436a0000,-
DUNK|coach_67|3|FRONT|3f570a3d|3f866666|40a00000|00000000|false|coach_67_dunk_front_two_hand_power,3f000000,3f800000,432eb333,41d4cccd,43660000,-
DUNK|coach_67|4|FRONT|3f400000|3f6b851f|41600000|40800000|true|coach_67_dunk_front_two_hand_hang,3f000000,3f800000,43250000,41a33333,436a0000,-
DUNK|coach_67|5|FRONT|3f75c28f|3f970a3d|40c00000|40000000|false|coach_67_dunk_front_statue,3f000000,3f800000,438ad99a,421a0000,43680000,-
DUNK|coach_67|6|SIDE|3f3851ec|3f6147ae|41900000|41400000|true|coach_67_dunk_side_two_hand_gather,3f000000,3f800000,4374199a,42086666,43620000,-
DUNK|coach_67|7|SIDE|3f4ccccd|3f666666|41b00000|41700000|true|coach_67_dunk_side_reverse_gather,3f000000,3f800000,435e6666,4277999a,43640000,-
DUNK|coach_67|8|SIDE|3f5c28f6|3f866666|41980000|41500000|true|coach_67_dunk_side_two_hand_hang,3f000000,3f800000,43664ccd,41d00000,43680000,-
DUNK|coach_67|9|SIDE|3f7ae148|3f9c28f6|40e00000|40800000|false|coach_67_dunk_side_statue,3f000000,3f800000,4391d99a,42133333,43680000,-
SLOT|coach_67|winner|coach_67_front_celebrate,3f000000,3f800000,-,-,-,-
SLOT|coach_67|loser|coach_67_front_sitting_sad,3f000000,3f800000,-,-,-,-
SLOT|coach_67|spectator|coach_67_front_sitting,3f000000,3f800000,-,-,-,-
DRIBBLE|coach_67|BACK|-
DRIBBLE|coach_67|SIDE|-
DRIBBLE|coach_67|FRONT|-
PREVIEW|coach_67|coach_67_front_defense
SET|zephyr|zephyr|43a10000|43480000|10|2
SLOT|zephyr|idleBack|basket_comet_ground_01,3f000000,3f778b59,42d00000,432d28f6,435b1439,-
SLOT|zephyr|idleFront|basket_comet_ground_00,3f000000,3f791490,42d00000,432d28f6,435b1439,-
SLOT|zephyr|idleSide|basket_comet_ground_02,3f000000,3f791490,4311999a,432d28f6,435b1439,-
SLOT|zephyr|shotBack.low|basket_comet_ground_10,3f000000,3f7417ec,42d00000,43258ccd,434606a8,-
SLOT|zephyr|shotBack.mid|basket_comet_ground_13,3f000000,3f7ce076,42d00000,42df0a3d,4357c9fc,-
SLOT|zephyr|shotBack.set|basket_comet_ground_16,3f000000,3f7da858,42d00000,419d70a4,4357c9fc,-
SLOT|zephyr|shotBack.release|zephyr_back_after_throw,3f000000,3f800000,-,-,-,-
SLOT|zephyr|shotSide.low|basket_comet_ground_11,3f000000,3f7ae5de,4311999a,43258ccd,434606a8,-
SLOT|zephyr|shotSide.mid|basket_comet_ground_14,3f000000,3f7f381d,4311999a,42df0a3d,4357c9fc,-
SLOT|zephyr|shotSide.set|basket_comet_ground_17,3f000000,3f800000,4311999a,419d70a4,4357c9fc,-
SLOT|zephyr|shotSide.release|basket_zephyr_17,3f000000,3f800000,42c11eb8,4122f5c3,43610000,-
SLOT|zephyr|shotFront.low|basket_comet_ground_09,3f000000,3f7417ec,42cf0000,43258ccd,434606a8,-
SLOT|zephyr|shotFront.mid|basket_comet_ground_12,3f000000,3f7f381d,42d00000,42df0a3d,4357c9fc,-
SLOT|zephyr|shotFront.set|basket_comet_ground_15,3f000000,3f7e703b,42cf0000,419d70a4,4357c9fc,-
SLOT|zephyr|shotFront.release|basket_zephyr_15,3f000000,3f800000,4239eb85,411a8f5c,43610000,-
SLOT|zephyr|steal.back|basket_comet_ground_19,3f000000,3f5b2f45,42d00000,431b7ae1,4344b604,-
SLOT|zephyr|steal.side|basket_comet_ground_20,3f000000,3f62085b,4311999a,431b7ae1,4344b604,-
SLOT|zephyr|steal.front|basket_comet_ground_18,3f000000,3f5a53b9,42d00000,431b7ae1,4344b604,-
SLOT|zephyr|block.back|zephyr_block_back,3f000000,3f800000,-,-,434b0000,-
SLOT|zephyr|block.side|zephyr_block_side,3f000000,3f800000,-,-,43500000,-
SLOT|zephyr|block.front|zephyr_block_front,3f000000,3f800000,-,-,432a0000,-
SLOT|zephyr|rebound.back|zephyr_rebound_back,3f000000,3f800000,-,-,43290000,-
SLOT|zephyr|rebound.side|zephyr_rebound_side,3f000000,3f800000,-,-,434e0000,-
SLOT|zephyr|rebound.front|zephyr_rebound_front,3f000000,3f800000,-,-,43370000,-
SLOT|zephyr|locomotion0.back|basket_comet_ground_05,3f000000,3f791490,4311999a,432d28f6,435b1439,-
SLOT|zephyr|locomotion0.side|basket_comet_ground_07,3f000000,3f7ae5de,42d00000,431c851f,434606a8,-
SLOT|zephyr|locomotion0.front|basket_comet_ground_03,3f000000,3f7b630b,42cf0000,432d28f6,435b1439,-
SLOT|zephyr|locomotion1.back|basket_comet_ground_06,3f000000,3f800000,42d00000,431c851f,434606a8,-
SLOT|zephyr|locomotion1.side|basket_comet_ground_08,3f000000,3f7bbf72,4311999a,431c851f,434606a8,-
SLOT|zephyr|locomotion1.front|basket_comet_ground_04,3f000000,3f800000,42d00000,432d28f6,435b1439,-
DUNK|zephyr|0|BACK|3f70a3d7|3f99999a|40c00000|00000000|false|zephyr_dunk_back_one_hand,3f000000,3f800000,436acccd,41ae6666,43660000,-
DUNK|zephyr|1|BACK|3f570a3d|3f866666|41900000|40000000|true|zephyr_dunk_back_two_hand_power,3f000000,3f800000,436f8000,41af3333,43680000,-
DUNK|zephyr|2|BACK|3f428f5c|3f6b851f|41a00000|40800000|true|zephyr_dunk_back_two_hand_hang,3f000000,3f800000,437a199a,41926666,436a0000,-
DUNK|zephyr|3|FRONT|3f570a3d|3f866666|40a00000|00000000|false|zephyr_dunk_front_two_hand_power,3f000000,3f800000,436b3333,41a80000,43660000,-
DUNK|zephyr|4|FRONT|3f400000|3f6b851f|41600000|40800000|true|zephyr_dunk_front_two_hand_hang,3f000000,3f800000,43426666,41900000,436a0000,-
DUNK|zephyr|5|FRONT|3f75c28f|3f970a3d|40c00000|40000000|false|zephyr_dunk_front_statue,3f000000,3f800000,439bcccd,41cf3333,43680000,-
DUNK|zephyr|6|SIDE|3f3851ec|3f6147ae|41900000|41400000|true|zephyr_dunk_side_two_hand_gather,3f000000,3f800000,437cb333,41cf3333,43620000,-
DUNK|zephyr|7|SIDE|3f4ccccd|3f666666|41b00000|41700000|true|zephyr_dunk_side_reverse_gather,3f000000,3f800000,4377cccd,423c6666,43640000,-
DUNK|zephyr|8|SIDE|3f5c28f6|3f866666|41980000|41500000|true|zephyr_dunk_side_two_hand_hang,3f000000,3f800000,4342b333,41a0cccd,43680000,-
DUNK|zephyr|9|SIDE|3f7ae148|3f9c28f6|40e00000|40800000|false|zephyr_dunk_side_statue,3f000000,3f800000,438c7333,41c8cccd,43680000,-
SLOT|zephyr|winner|zephyr_front_celebrate,3f000000,3f800000,-,-,-,-
SLOT|zephyr|loser|zephyr_front_sitting_sad,3f000000,3f800000,-,-,-,-
SLOT|zephyr|spectator|zephyr_front_sitting,3f000000,3f800000,-,-,-,-
DRIBBLE|zephyr|BACK|basket_comet_ground_22,3f000000,3f6fbb30,42d00000,431b7ae1,4344b604,-
DRIBBLE|zephyr|SIDE|basket_comet_ground_23,3f000000,3f649a56,4311999a,431b7ae1,4344b604,-
DRIBBLE|zephyr|FRONT|basket_comet_ground_21,3f000000,3f6a9889,42cf0000,431b7ae1,4344b604,-
PREVIEW|zephyr|basket_comet_ground_00
SET|kyra|kyra|43700000|43480000|3|2
SLOT|kyra|idleBack|basket_gaya_ground_01,3f000000,3f789b52,43000000,43100a3d,4351d917,-
SLOT|kyra|idleFront|basket_gaya_ground_00,3f000000,3f7a747e,43000000,43100a3d,4351d917,-
SLOT|kyra|idleSide|basket_gaya_ground_02,3f000000,3f7b6113,43333333,43100a3d,4351d917,-
SLOT|kyra|shotBack.low|basket_gaya_ground_10,3f000000,3f6fae14,43000000,430a0ccd,433e26e9,-
SLOT|kyra|shotBack.mid|basket_gaya_ground_13,3f000000,3f7c432d,43000000,42ba51ec,434f9375,-
SLOT|kyra|shotBack.set|basket_gaya_ground_16,3f000000,3f7c432d,43000000,4183851f,434f9375,-
SLOT|kyra|shotBack.release|basket_kyra_16,3f000000,3f800000,42be6667,412028f6,43610000,-
SLOT|kyra|shotSide.low|basket_gaya_ground_11,3f000000,3f78dc33,43333333,430a0ccd,433e26e9,-
SLOT|kyra|shotSide.mid|basket_gaya_ground_14,3f000000,3f7f10cb,43333333,42ba51ec,434f9375,-
SLOT|kyra|shotSide.set|basket_gaya_ground_17,3f000000,3f800000,43333333,4183851f,434f9375,-
SLOT|kyra|shotSide.release|basket_kyra_17,3f000000,3f800000,429c6667,4125c28f,43610000,-
SLOT|kyra|shotFront.low|basket_gaya_ground_09,3f000000,3f78dc33,43000000,430a0ccd,433e26e9,-
SLOT|kyra|shotFront.mid|basket_gaya_ground_12,3f000000,3f7e2196,43000000,42ba51ec,434f9375,-
SLOT|kyra|shotFront.set|basket_gaya_ground_15,3f000000,3f7c432d,43000000,4183851f,434f9375,-
SLOT|kyra|shotFront.release|basket_kyra_15,3f000000,3f800000,421f0a3d,411d5c29,43610000,-
SLOT|kyra|steal.back|basket_gaya_ground_19,3f000000,3f6c6541,43000000,42e6e148,43282e98,-
SLOT|kyra|steal.side|basket_gaya_ground_20,3f000000,3f6fdb4d,43333333,42e6e148,43282e98,-
SLOT|kyra|steal.front|basket_gaya_ground_18,3f000000,3f6eb3bc,43000000,42e6e148,43282e98,-
SLOT|kyra|block.back|basket_kyra_extra_04,3f000000,3f800000,42d2199a,41666666,436d0000,-
SLOT|kyra|block.side|basket_kyra_extra_05,3f000000,3f800000,42c08000,41666666,436d0000,-
SLOT|kyra|block.front|basket_kyra_extra_03,3f000000,3f800000,42cecccd,41666666,436d0000,-
SLOT|kyra|rebound.back|basket_kyra_extra_07,3f000000,3f800000,42cecccd,41666666,436d0000,-
SLOT|kyra|rebound.side|basket_kyra_extra_08,3f000000,3f800000,42b46666,41666666,436d0000,-
SLOT|kyra|rebound.front|basket_kyra_extra_06,3f000000,3f800000,42cdb333,41666666,436d0000,-
SLOT|kyra|locomotion0.back|basket_gaya_ground_05,3f000000,3f7f136a,43333333,43100a3d,4351d917,-
SLOT|kyra|locomotion0.side|basket_gaya_ground_07,3f000000,3f800000,43000000,4302851f,433e26e9,-
SLOT|kyra|locomotion0.front|basket_gaya_ground_03,3f000000,3f7e26d5,43000000,43100a3d,4351d917,-
SLOT|kyra|locomotion1.back|basket_gaya_ground_06,3f000000,3f800000,43000000,4302851f,433e26e9,-
SLOT|kyra|locomotion1.side|basket_gaya_ground_08,3f000000,3f800000,43333333,4302851f,433e26e9,-
SLOT|kyra|locomotion1.front|basket_gaya_ground_04,3f000000,3f800000,43000000,43100a3d,4351d917,-
DUNK|kyra|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_21,3f000000,3f800000,4226e148,410e3d71,43570000,-
DUNK|kyra|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_22,3f000000,3f800000,42b4e148,41093333,43570000,-
DUNK|kyra|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_23,3f000000,3f800000,42e31eb8,410547ae,43570000,-
SLOT|kyra|winner|basket_kyra_extra_09,3f000000,3f800000,42eb6666,41666666,43570000,-
SLOT|kyra|loser|basket_kyra_extra_10,3f000000,3f800000,42de3333,41666666,43480000,-
SLOT|kyra|spectator|basket_kyra_extra_11,3f000000,3f800000,42f66666,41666666,43480000,-
DRIBBLE|kyra|BACK|basket_gaya_ground_22,3f000000,3f6d8cd2,43000000,42e6e148,43282e98,-
DRIBBLE|kyra|SIDE|basket_gaya_ground_23,3f000000,3f7350b1,43333333,42e6e148,43282e98,-
DRIBBLE|kyra|FRONT|basket_gaya_ground_21,3f000000,3f6eb3bc,43000000,42e6e148,43282e98,-
PREVIEW|kyra|basket_gaya_ground_00
SET|kyra_original|kyra_original|43700000|43480000|3|2
SLOT|kyra_original|idleBack|basket_kyra_original_01,3f000000,3f7b72c5,42d10000,42ea0000,43514d50,-
SLOT|kyra_original|idleFront|basket_kyra_original_00,3f000000,3f7c9668,42d10000,42ea0000,43514d50,-
SLOT|kyra_original|idleSide|basket_kyra_original_02,3f000000,3f7edd05,43124ccd,42ea0000,43514d50,-
SLOT|kyra_original|shotBack.low|basket_kyra_original_10,3f000000,3f786595,42d10000,42de3333,433be831,-
SLOT|kyra_original|shotBack.mid|basket_kyra_original_25,3f000000,3f7abfdb,42d10000,4284999a,4335651f,-
SLOT|kyra_original|shotBack.set|basket_kyra_original_13,3f000000,3f7ba494,42d10000,4161999a,435a9ae1,-
SLOT|kyra_original|shotBack.release|basket_kyra_original_16,3f000000,3f7ee8d1,42d10000,4161999a,435a9ae1,-
SLOT|kyra_original|shotSide.low|basket_kyra_original_11,3f000000,3f7ebb99,43124ccd,42de3333,433be831,-
SLOT|kyra_original|shotSide.mid|basket_kyra_original_26,3f000000,3f7c100e,43124ccd,4284999a,4335651f,-
SLOT|kyra_original|shotSide.set|basket_kyra_original_14,3f000000,3f7cbb1b,43124ccd,4161999a,435a9ae1,-
SLOT|kyra_original|shotSide.release|basket_kyra_original_17,3f000000,3f800000,43124ccd,4161999a,435a9ae1,-
SLOT|kyra_original|shotFront.low|basket_kyra_original_09,3f000000,3f75dcc6,42d10000,42de3333,433be831,-
SLOT|kyra_original|shotFront.mid|basket_kyra_original_24,3f000000,3f796fa8,42d10000,4284999a,4335651f,-
SLOT|kyra_original|shotFront.set|basket_kyra_original_12,3f000000,3f7cbb1b,42d10000,4161999a,435a9ae1,-
SLOT|kyra_original|shotFront.release|basket_kyra_original_15,3f000000,3f7ee8d1,42d10000,4161999a,435a9ae1,-
SLOT|kyra_original|steal.back|basket_kyra_original_19,3f000000,3f66a401,42d10000,42dc7ae1,43453581,-
SLOT|kyra_original|steal.side|basket_kyra_original_20,3f000000,3f6a4357,43124ccd,42dc7ae1,43453581,-
SLOT|kyra_original|steal.front|basket_kyra_original_18,3f000000,3f656f54,42d10000,42dc7ae1,43453581,-
SLOT|kyra_original|block.back|basket_kyra_original_28,3f000000,3f76cf42,42d10000,42cacccd,4335651f,-
SLOT|kyra_original|block.side|basket_kyra_original_29,3f000000,3f800000,43124ccd,42cacccd,4335651f,-
SLOT|kyra_original|block.front|basket_kyra_original_27,3f000000,3f6c4ef9,42d10000,42cacccd,4335651f,-
SLOT|kyra_original|rebound.back|basket_kyra_original_31,3f000000,3f791490,42d10000,42c06666,432c17cf,-
SLOT|kyra_original|rebound.side|basket_kyra_original_32,3f000000,3f791490,43124ccd,42c06666,432c17cf,-
SLOT|kyra_original|rebound.front|basket_kyra_original_30,3f000000,3f74ee39,42d10000,42c06666,432c17cf,-
SLOT|kyra_original|locomotion0.back|basket_kyra_original_05,3f000000,3f7edd05,43124ccd,42ea0000,43514d50,-
SLOT|kyra_original|locomotion0.side|basket_kyra_original_07,3f000000,3f7d7732,42d10000,42d2147b,433be831,-
SLOT|kyra_original|locomotion0.front|basket_kyra_original_03,3f000000,3f7edd05,42d10000,42ea0000,43514d50,-
SLOT|kyra_original|locomotion1.back|basket_kyra_original_06,3f000000,3f800000,42d10000,42d2147b,433be831,-
SLOT|kyra_original|locomotion1.side|basket_kyra_original_08,3f000000,3f7d7732,43124ccd,42d2147b,433be831,-
SLOT|kyra_original|locomotion1.front|basket_kyra_original_04,3f000000,3f800000,42d10000,42ea0000,43514d50,-
DUNK|kyra_original|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_original_21,3f000000,3f800000,42d10000,414b851f,43453581,-
DUNK|kyra_original|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_original_22,3f000000,3f800000,42d10000,414b851f,43453581,-
DUNK|kyra_original|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_kyra_original_23,3f000000,3f800000,43124ccd,414b851f,43453581,-
SLOT|kyra_original|winner|basket_kyra_original_33,3f000000,3f7a771d,42d10000,42c06666,432c17cf,-
SLOT|kyra_original|loser|basket_kyra_original_34,3f000000,3f7bd902,42d10000,42c06666,432c17cf,-
SLOT|kyra_original|spectator|basket_kyra_original_35,3f000000,3f7a771d,43124ccd,42c06666,432c17cf,-
DRIBBLE|kyra_original|BACK|-
DRIBBLE|kyra_original|SIDE|-
DRIBBLE|kyra_original|FRONT|-
PREVIEW|kyra_original|basket_kyra_original_00
SET|flare|flare|43b00000|43480000|10|2
SLOT|flare|idleBack|flare_back_standing,3f000000,3f800000,4342999a,434c4ccd,-,-
SLOT|flare|idleFront|flare_front_defense,3f000000,3f800000,437f3333,432f4ccd,-,-
SLOT|flare|idleSide|basket_flare_02,3f000000,3f800000,426ccccd,43074ccd,43480000,-
SLOT|flare|shotBack.low|flare_shot_back_low,3f000000,3f800000,4304b333,43024ccd,43350000,-
SLOT|flare|shotBack.mid|flare_shot_back_mid,3f000000,3f800000,42f10000,425b999a,43350000,-
SLOT|flare|shotBack.set|flare_shot_back_set,3f000000,3f800000,42c86666,41c40000,43480000,-
SLOT|flare|shotBack.release|flare_back_after_throw,3f000000,3f800000,-,-,-,-
SLOT|flare|shotSide.low|flare_shot_side_low,3f000000,3f800000,4342cccd,43156666,43350000,-
SLOT|flare|shotSide.mid|flare_shot_side_mid,3f000000,3f800000,4327e666,42b80000,433a0000,-
SLOT|flare|shotSide.set|flare_shot_side_set,3f000000,3f800000,4307999a,42280000,43480000,-
SLOT|flare|shotSide.release|basket_flare_17,3f000000,3f800000,42bd0a3e,410c8f5c,43610000,-
SLOT|flare|shotFront.low|flare_shot_front_low,3f000000,3f800000,4309b333,43144ccd,43350000,-
SLOT|flare|shotFront.mid|flare_shot_front_mid,3f000000,3f800000,42f96666,4296cccd,433c0000,-
SLOT|flare|shotFront.set|flare_shot_front_set,3f000000,3f800000,42df0000,41d73333,43480000,-
SLOT|flare|shotFront.release|basket_flare_15,3f000000,3f800000,42368f5c,4113d70a,43610000,-
SLOT|flare|steal.back|flare_steal_back,3f000000,3f800000,-,-,43320000,-
SLOT|flare|steal.side|flare_steal_side,3f000000,3f800000,-,-,43190000,-
SLOT|flare|steal.front|flare_steal_front,3f000000,3f8e147b,-,-,42dc0000,-
SLOT|flare|block.back|flare_block_back,3f000000,3f800000,-,-,434b0000,-
SLOT|flare|block.side|flare_block_side,3f000000,3f800000,-,-,43500000,-
SLOT|flare|block.front|flare_block_front,3f000000,3f800000,-,-,432a0000,-
SLOT|flare|rebound.back|flare_rebound_back,3f000000,3f800000,-,-,43290000,-
SLOT|flare|rebound.side|flare_rebound_side,3f000000,3f800000,-,-,434e0000,-
SLOT|flare|rebound.front|flare_rebound_front,3f000000,3f800000,-,-,43370000,-
SLOT|flare|locomotion0.back|basket_flare_05,3f000000,3f800000,42b90000,4306c000,43480000,-
SLOT|flare|locomotion0.side|basket_flare_07,3f000000,3f800000,431fd70a,43002667,43480000,-
SLOT|flare|locomotion0.front|basket_flare_03,3f000000,3f800000,42beeb85,43086667,43480000,-
SLOT|flare|locomotion1.back|basket_flare_06,3f000000,3f800000,42bbf5c3,43014000,43480000,-
SLOT|flare|locomotion1.side|basket_flare_08,3f000000,3f800000,4325051f,42facccd,43480000,-
SLOT|flare|locomotion1.front|basket_flare_04,3f000000,3f800000,42c06667,43086667,43480000,-
DUNK|flare|0|BACK|3f70a3d7|3f99999a|40c00000|00000000|false|flare_dunk_back_one_hand,3f000000,3f800000,4399999a,41da6666,43660000,-
DUNK|flare|1|BACK|3f570a3d|3f866666|41900000|40000000|true|flare_dunk_back_two_hand_power,3f000000,3f800000,43464ccd,41f0cccd,43680000,-
DUNK|flare|2|BACK|3f428f5c|3f6b851f|41a00000|40800000|true|flare_dunk_back_two_hand_hang,3f000000,3f800000,4386999a,41c0cccd,436a0000,-
DUNK|flare|3|FRONT|3f570a3d|3f866666|40a00000|00000000|false|flare_dunk_front_two_hand_power,3f000000,3f800000,43370000,41fa6666,43660000,-
DUNK|flare|4|FRONT|3f400000|3f6b851f|41600000|40800000|true|flare_dunk_front_two_hand_hang,3f000000,3f800000,43220000,41c66666,436a0000,-
DUNK|flare|5|FRONT|3f75c28f|3f970a3d|40c00000|40000000|false|flare_dunk_front_statue,3f000000,3f800000,43a77333,42073333,43680000,-
DUNK|flare|6|SIDE|3f3851ec|3f6147ae|41900000|41400000|true|flare_dunk_side_two_hand_gather,3f000000,3f800000,43a4f333,4236cccd,43620000,-
DUNK|flare|7|SIDE|3f4ccccd|3f666666|41b00000|41700000|true|flare_dunk_side_reverse_gather,3f000000,3f800000,4391a666,4285999a,43640000,-
DUNK|flare|8|SIDE|3f5c28f6|3f866666|41980000|41500000|true|flare_dunk_side_two_hand_hang,3f000000,3f800000,43800ccd,42086666,43680000,-
DUNK|flare|9|SIDE|3f7ae148|3f9c28f6|40e00000|40800000|false|flare_dunk_side_statue,3f000000,3f800000,43b0599a,42426666,43680000,-
SLOT|flare|winner|flare_front_celebrate,3f000000,3f800000,-,-,-,-
SLOT|flare|loser|flare_front_sitting_sad,3f000000,3f800000,-,-,-,-
SLOT|flare|spectator|flare_front_sitting,3f000000,3f800000,-,-,-,-
DRIBBLE|flare|BACK|-
DRIBBLE|flare|SIDE|-
DRIBBLE|flare|FRONT|-
PREVIEW|flare|flare_front_defense
SET|ace_23|ace_23|43700000|43480000|3|2
SLOT|ace_23|idleBack|basket_ace_23_01,3f000000,3f800000,42cf3333,430f0000,43480000,-
SLOT|ace_23|idleFront|basket_ace_23_00,3f000000,3f800000,42e270a4,430e7333,43480000,-
SLOT|ace_23|idleSide|basket_ace_23_02,3f000000,3f800000,4263eb85,430f8ccd,43480000,-
SLOT|ace_23|shotBack.low|basket_ace_23_10,3f000000,3f800000,42a951eb,4301570a,43310000,-
SLOT|ace_23|shotBack.mid|basket_ace_23_extra_01,3f000000,3f800000,42e70000,43073333,434d0000,-
SLOT|ace_23|shotBack.set|basket_ace_23_13,3f000000,3f800000,428a0000,41630a3d,436d0000,-
SLOT|ace_23|shotBack.release|basket_ace_23_16,3f000000,3f800000,42acb852,410dae15,43610000,-
SLOT|ace_23|shotSide.low|basket_ace_23_11,3f000000,3f800000,42db1eb8,42ce1999,43310000,-
SLOT|ace_23|shotSide.mid|basket_ace_23_extra_02,3f000000,3f800000,42bc0000,430a6666,434d0000,-
SLOT|ace_23|shotSide.set|basket_ace_23_14,3f000000,3f800000,4285dc29,41668f5c,436d0000,-
SLOT|ace_23|shotSide.release|basket_ace_23_17,3f000000,3f800000,42a5eb85,4116a3d7,43610000,-
SLOT|ace_23|shotFront.low|basket_ace_23_09,3f000000,3f800000,42ae6b85,4300c28f,43310000,-
SLOT|ace_23|shotFront.mid|basket_ace_23_extra_00,3f000000,3f800000,42e40000,4307999a,434d0000,-
SLOT|ace_23|shotFront.set|basket_ace_23_12,3f000000,3f800000,42990000,4163eb85,436d0000,-
SLOT|ace_23|shotFront.release|basket_ace_23_15,3f000000,3f800000,420f5c29,410ae148,43610000,-
SLOT|ace_23|steal.back|basket_ace_23_19,3f000000,3f800000,4315999a,40e23d71,43280000,-
SLOT|ace_23|steal.side|basket_ace_23_20,3f000000,3f800000,43123333,40e23d71,43280000,-
SLOT|ace_23|steal.front|basket_ace_23_18,3f000000,3f800000,4306a3d7,40e23d71,43280000,-
SLOT|ace_23|block.back|basket_ace_23_extra_04,3f000000,3f800000,42cb8000,415d70a4,436d0000,-
SLOT|ace_23|block.side|basket_ace_23_extra_05,3f000000,3f800000,42c08000,4160a3d7,436d0000,-
SLOT|ace_23|block.front|basket_ace_23_extra_03,3f000000,3f800000,42e3b333,4159999a,436d0000,-
SLOT|ace_23|rebound.back|basket_ace_23_extra_07,3f000000,3f800000,42dc0000,4159999a,436d0000,-
SLOT|ace_23|rebound.side|basket_ace_23_extra_08,3f000000,3f800000,42d2199a,415f5c29,436d0000,-
SLOT|ace_23|rebound.front|basket_ace_23_extra_06,3f000000,3f800000,42e2999a,4159999a,436d0000,-
SLOT|ace_23|locomotion0.back|basket_ace_23_05,3f000000,3f800000,42ba7ae1,4310199a,43480000,-
SLOT|ace_23|locomotion0.side|basket_ace_23_07,3f000000,3f800000,42fb999a,42fd0000,43480000,-
SLOT|ace_23|locomotion0.front|basket_ace_23_03,3f000000,3f800000,42b3147b,4310a667,43480000,-
SLOT|ace_23|locomotion1.back|basket_ace_23_06,3f000000,3f800000,42b01eb8,4301cccd,43480000,-
SLOT|ace_23|locomotion1.side|basket_ace_23_08,3f000000,3f800000,4306ae15,42fbe667,43480000,-
SLOT|ace_23|locomotion1.front|basket_ace_23_04,3f000000,3f800000,42b01eb8,4310a667,43480000,-
DUNK|ace_23|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_ace_23_21,3f000000,3f800000,42333333,410b70a4,43570000,-
DUNK|ace_23|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_ace_23_22,3f000000,3f800000,42c53333,410f5c29,43570000,-
DUNK|ace_23|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_ace_23_23,3f000000,3f800000,42d0147b,4109c28f,43570000,-
SLOT|ace_23|winner|basket_ace_23_extra_09,3f000000,3f800000,42e18000,415851ec,43570000,-
SLOT|ace_23|loser|basket_ace_23_extra_10,3f000000,3f800000,42ca6666,4155c28f,43480000,-
SLOT|ace_23|spectator|basket_ace_23_extra_11,3f000000,3f800000,42c7199a,41566666,43480000,-
DRIBBLE|ace_23|BACK|-
DRIBBLE|ace_23|SIDE|-
DRIBBLE|ace_23|FRONT|-
PREVIEW|ace_23|basket_ace_23_00
SET|buddy_23|buddy_23|43700000|43480000|3|2
SLOT|buddy_23|idleBack|basket_buddy_23_01,3f000000,3f800000,42cdb852,4307d99a,43480000,-
SLOT|buddy_23|idleFront|basket_buddy_23_00,3f000000,3f800000,43053333,43074ccd,43480000,-
SLOT|buddy_23|idleSide|basket_buddy_23_02,3f000000,3f800000,43053333,43086667,43480000,-
SLOT|buddy_23|shotBack.low|basket_buddy_23_10,3f000000,3f800000,42a951eb,4303147b,43310000,-
SLOT|buddy_23|shotBack.mid|basket_buddy_23_extra_01,3f000000,3f800000,42cf0000,42fa6666,434d0000,-
SLOT|buddy_23|shotBack.set|basket_buddy_23_13,3f000000,3f800000,42850000,415ea3d7,436d0000,-
SLOT|buddy_23|shotBack.release|basket_buddy_23_16,3f000000,3f800000,42e06667,4108a3d7,43610000,-
SLOT|buddy_23|shotSide.low|basket_buddy_23_11,3f000000,3f800000,42f25c29,42cfe666,43310000,-
SLOT|buddy_23|shotSide.mid|basket_buddy_23_extra_02,3f000000,3f800000,42cb0000,42fccccd,434d0000,-
SLOT|buddy_23|shotSide.set|basket_buddy_23_14,3f000000,3f800000,42de2e14,415dc28f,436d0000,-
SLOT|buddy_23|shotSide.release|basket_buddy_23_17,3f000000,3f800000,42d83d71,410d1eb8,43610000,-
SLOT|buddy_23|shotFront.low|basket_buddy_23_09,3f000000,3f800000,42ab5c29,4301570a,43310000,-
SLOT|buddy_23|shotFront.mid|basket_buddy_23_extra_00,3f000000,3f800000,42d50000,42fb3333,434d0000,-
SLOT|buddy_23|shotFront.set|basket_buddy_23_12,3f000000,3f800000,42900000,415ea3d7,436d0000,-
SLOT|buddy_23|shotFront.release|basket_buddy_23_15,3f000000,3f800000,421deb85,4108a3d7,43610000,-
SLOT|buddy_23|steal.back|basket_buddy_23_19,3f000000,3f800000,431e70a4,40e11eb8,43280000,-
SLOT|buddy_23|steal.side|basket_buddy_23_20,3f000000,3f800000,4325eb85,40dee148,43280000,-
SLOT|buddy_23|steal.front|basket_buddy_23_18,3f000000,3f800000,4310d70a,40e35c29,43280000,-
SLOT|buddy_23|block.back|basket_buddy_23_extra_04,3f000000,3f800000,42ca6666,41547ae1,436d0000,-
SLOT|buddy_23|block.side|basket_buddy_23_extra_05,3f000000,3f800000,42be4ccd,41566666,436d0000,-
SLOT|buddy_23|block.front|basket_buddy_23_extra_03,3f000000,3f800000,42e4cccd,41533333,436d0000,-
SLOT|buddy_23|rebound.back|basket_buddy_23_extra_07,3f000000,3f800000,42d8b333,41547ae1,436d0000,-
SLOT|buddy_23|rebound.side|basket_buddy_23_extra_08,3f000000,3f800000,42ca6666,4153d70a,436d0000,-
SLOT|buddy_23|rebound.front|basket_buddy_23_extra_06,3f000000,3f800000,42cc999a,4153d70a,436d0000,-
SLOT|buddy_23|locomotion0.back|basket_buddy_23_05,3f000000,3f800000,42cc3d71,430a0ccd,43480000,-
SLOT|buddy_23|locomotion0.side|basket_buddy_23_07,3f000000,3f800000,4313428f,42f66667,43480000,-
SLOT|buddy_23|locomotion0.front|basket_buddy_23_03,3f000000,3f800000,42d0ae15,4305a667,43480000,-
SLOT|buddy_23|locomotion1.back|basket_buddy_23_06,3f000000,3f800000,42c947ae,42ff3334,43480000,-
SLOT|buddy_23|locomotion1.side|basket_buddy_23_08,3f000000,3f800000,4311c7ae,42f54ccd,43480000,-
SLOT|buddy_23|locomotion1.front|basket_buddy_23_04,3f000000,3f800000,42d0ae15,43074ccd,43480000,-
DUNK|buddy_23|0|FRONT|3f51eb85|3f800000|00000000|00000000|false|basket_buddy_23_21,3f000000,3f800000,421deb85,4105d70a,43570000,-
DUNK|buddy_23|1|BACK|3f51eb85|3f800000|00000000|00000000|false|basket_buddy_23_22,3f000000,3f800000,42d6e148,41027ae1,43570000,-
DUNK|buddy_23|2|SIDE|3f51eb85|3f800000|00000000|00000000|false|basket_buddy_23_23,3f000000,3f800000,42e88f5c,4103999a,43570000,-
SLOT|buddy_23|winner|basket_buddy_23_extra_09,3f000000,3f800000,42e4cccd,4149999a,43570000,-
SLOT|buddy_23|loser|basket_buddy_23_extra_10,3f000000,3f800000,42e06666,414a3d71,43480000,-
SLOT|buddy_23|spectator|basket_buddy_23_extra_11,3f000000,3f800000,42d7999a,414b851f,43480000,-
DRIBBLE|buddy_23|BACK|-
DRIBBLE|buddy_23|SIDE|-
DRIBBLE|buddy_23|FRONT|-
PREVIEW|buddy_23|basket_buddy_23_00
NOSET|<null>|true|false|-
NOSET|minik|true|false|-
NOSET||true|false|-
NOSET|Bob|true|false|-
NOSET|kyra_originalx|true|false|-
NOSET|character_preview_bob|true|false|-
PLAYABLE|woman_dark,nova,coach_67,zephyr,flare,kyra_original,bob,rooza,unicorn_32,kyra,ace_23,buddy_23
"""

/// heldBallPosition / worldFrame / visualTopY. Defaults of the fields not listed: pose NORMAL, style HUMAN,
/// shot PRO, x 500, y (footY) 900, aim 0.2, pull 0.5, b (bounce) 24.5, hot 0, cel 0, ph (phase) 0.25, hs (hand
/// sign) 1, mv (moving) 0, fast 0, loco -1, mir (mirrorX) 0, act -1, vs (visualScale) 1, up (uptimeMillis) 0.
private let visualsHeldGolden = """
1 bob IDLE BACK > basket_bob_01 4401bf60 444d3333 44350000
1 bob IDLE SIDE > basket_bob_02 43ff4d56 444d3333 44350000
1 bob IDLE FRONT > basket_bob_00 4401a8a8 444d3333 44350000
1 bob WAITING BACK > basket_bob_01 4401bf60 444d3333 44350000
1 bob WAITING SIDE > basket_bob_02 43ff4d56 444d3333 44350000
1 bob WAITING FRONT > basket_bob_00 4401a8a8 444d3333 44350000
1 bob WALK BACK > basket_bob_01 4401bf60 444d3333 44350000
1 bob WALK SIDE > basket_bob_02 43ff4d56 444d3333 44350000
1 bob WALK FRONT > basket_bob_00 4401a8a8 444d3333 44350000
1 bob DRIBBLE BACK > basket_bob_01 43febf60 44535333 44350000
1 bob DRIBBLE SIDE > basket_bob_02 43fd0000 44535333 44350000
1 bob DRIBBLE FRONT > basket_bob_00 43fea8a8 44535333 44350000
1 bob STEAL BACK > basket_bob_19 4403dce6 443d5567 443c0a3e
1 bob STEAL SIDE > basket_bob_20 4403affd 443d5567 443c0a3e
1 bob STEAL FRONT > basket_bob_18 4403f4ec 443d5567 443c0a3e
1 bob BLOCK BACK > basket_bob_extra_04 43fcff89 44281eb8 4425c000
1 bob BLOCK SIDE > basket_bob_extra_05 43fd245d 44281eb8 4425c000
1 bob BLOCK FRONT > basket_bob_extra_03 43fd0ac6 44281eb8 4425c000
1 bob REBOUND BACK > basket_bob_extra_07 43fd0d1b 44281eb8 4425c000
1 bob REBOUND SIDE > basket_bob_extra_08 43fc9bf3 44281eb8 4425c000
1 bob REBOUND FRONT > basket_bob_extra_06 43fd4c2c 44281eb8 4425c000
1 bob DUNK BACK > basket_bob_22 4401986e 44335b02 4431b333
1 bob DUNK SIDE > basket_bob_23 4400f166 44335b02 4431b333
1 bob DUNK FRONT > basket_bob_21 43ed2dda 44335b02 4431b333
1 bob SHOT_LOW BACK > basket_bob_10 43fa83b6 4450a52c 443a0f5c
1 bob SHOT_LOW SIDE > basket_bob_11 44052271 444b953f 443a0f5c
1 bob SHOT_LOW FRONT > basket_bob_09 43fa8a75 4450a52c 443a0f5c
1 bob SHOT_MID BACK > basket_bob_extra_01 43fa0000 44424000 442dc000
1 bob SHOT_MID SIDE > basket_bob_extra_02 43fa0000 44424000 442dc000
1 bob SHOT_MID FRONT > basket_bob_extra_00 43fa0000 44424000 442dc000
1 bob SHOT_SET BACK > basket_bob_13 43fa0000 442fba4b 442cdc29
1 bob SHOT_SET SIDE > basket_bob_14 4400509e 442fba4b 442cdc29
1 bob SHOT_SET FRONT > basket_bob_12 43fa0000 442fba4b 442cdc29
1 bob RELEASE BACK > basket_bob_16 44017d64 44313b85 442f8000
1 bob RELEASE SIDE > basket_bob_17 4400e4cc 44313b85 442f8000
1 bob RELEASE FRONT > basket_bob_15 43efc7b8 44313b85 442f8000
1 woman_dark IDLE BACK > woman_dark_back_standing 44068ccd 444b0000 442f3333
1 woman_dark IDLE SIDE > basket_woman_dark_02 44019aec 444a8000 442f0000
1 woman_dark IDLE FRONT > woman_dark_front_defense 4407999a 444b9999 4432e666
1 woman_dark WAITING BACK > woman_dark_back_standing 44068ccd 444b0000 442f3333
1 woman_dark WAITING SIDE > basket_woman_dark_02 44019aec 444a8000 442f0000
1 woman_dark WAITING FRONT > woman_dark_front_defense 4407999a 444b9999 4432e666
1 woman_dark WALK BACK > woman_dark_back_standing 44068ccd 444b0000 442f3333
1 woman_dark WALK SIDE > basket_woman_dark_02 44019aec 444a8000 442f0000
1 woman_dark WALK FRONT > woman_dark_front_defense 4407999a 444b9999 4432e666
1 woman_dark DRIBBLE BACK > woman_dark_back_standing 4401c666 44512000 442f3333
1 woman_dark DRIBBLE SIDE > basket_woman_dark_02 43fe9aec 4450a000 442f0000
1 woman_dark DRIBBLE FRONT > woman_dark_front_defense 44024ccd 4451b999 4432e666
1 woman_dark STEAL BACK > woman_dark_steal_back 4401cccd 44596000 44348000
1 woman_dark STEAL SIDE > woman_dark_steal_side 4401cccd 44596000 443ac000
1 woman_dark STEAL FRONT > woman_dark_steal_front 4401cccd 44596000 4442799a
1 woman_dark BLOCK BACK > woman_dark_block_back 4401cccd 44596000 442e4000
1 woman_dark BLOCK SIDE > woman_dark_block_side 4401cccd 44596000 442d0000
1 woman_dark BLOCK FRONT > woman_dark_block_front 4401cccd 44596000 44368000
1 woman_dark REBOUND BACK > woman_dark_rebound_back 4401cccd 44596000 4436c000
1 woman_dark REBOUND SIDE > woman_dark_rebound_side 4401cccd 44596000 442d8000
1 woman_dark REBOUND FRONT > woman_dark_rebound_front 4401cccd 44596000 44334000
1 woman_dark DUNK BACK > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK SIDE > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK FRONT > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark SHOT_LOW BACK > woman_dark_shot_back_low 43fa37a6 4446c9fd 4433c000
1 woman_dark SHOT_LOW SIDE > woman_dark_shot_side_low 44077d05 44485174 4433c000
1 woman_dark SHOT_LOW FRONT > woman_dark_shot_front_low 43fa096f 44491f45 4433c000
1 woman_dark SHOT_MID BACK > woman_dark_shot_back_mid 43f9eaff 4439d0b0 4433c000
1 woman_dark SHOT_MID SIDE > woman_dark_shot_side_mid 4406d7ab 443e8c2f 44328000
1 woman_dark SHOT_MID FRONT > woman_dark_shot_front_mid 43fa09bc 443be301 44320000
1 woman_dark SHOT_SET BACK > woman_dark_shot_back_set 43fa0a89 44318d2b 442f0000
1 woman_dark SHOT_SET SIDE > woman_dark_shot_side_set 4405baba 44342446 442f0000
1 woman_dark SHOT_SET FRONT > woman_dark_shot_front_set 43f99cee 4431c3a4 442f0000
1 woman_dark RELEASE BACK > woman_dark_back_after_throw 4401cccd 44596000 442d4ccd
1 woman_dark RELEASE SIDE > basket_woman_dark_17 4401df47 442ab800 4428c000
1 woman_dark RELEASE FRONT > basket_woman_dark_15 43f0b800 442ab800 4428c000
1 rooza IDLE BACK > basket_rooza_01 440312cf 444a8000 442f0000
1 rooza IDLE SIDE > basket_rooza_02 44038297 444a8000 442f0000
1 rooza IDLE FRONT > basket_rooza_00 44036c59 444a8000 442f0000
1 rooza WAITING BACK > basket_rooza_01 440312cf 444a8000 442f0000
1 rooza WAITING SIDE > basket_rooza_02 44038297 444a8000 442f0000
1 rooza WAITING FRONT > basket_rooza_00 44036c59 444a8000 442f0000
1 rooza WALK BACK > basket_rooza_01 440312cf 444a8000 442f0000
1 rooza WALK SIDE > basket_rooza_02 44038297 444a8000 442f0000
1 rooza WALK FRONT > basket_rooza_00 44036c59 444a8000 442f0000
1 rooza DRIBBLE BACK > basket_rooza_01 44000968 4450a000 442f0000
1 rooza DRIBBLE SIDE > basket_rooza_02 4400414c 4450a000 442f0000
1 rooza DRIBBLE FRONT > basket_rooza_00 4400362c 4450a000 442f0000
1 rooza STEAL BACK > basket_rooza_19 4403cb05 44387852 44370000
1 rooza STEAL SIDE > basket_rooza_20 4403bd64 44387852 44370000
1 rooza STEAL FRONT > basket_rooza_18 440430f4 44387852 44370000
1 rooza BLOCK BACK > basket_rooza_extra_04 43febe62 44281eb8 4425c000
1 rooza BLOCK SIDE > basket_rooza_extra_05 43fde506 44281eb8 4425c000
1 rooza BLOCK FRONT > basket_rooza_extra_03 43fe73c4 44281eb8 4425c000
1 rooza REBOUND BACK > basket_rooza_extra_07 43fd75eb 44281eb8 4425c000
1 rooza REBOUND SIDE > basket_rooza_extra_08 43fd4aaa 44281eb8 4425c000
1 rooza REBOUND FRONT > basket_rooza_extra_06 43fd7172 44281eb8 4425c000
1 rooza DUNK BACK > basket_rooza_22 44020856 442d219a 442b4000
1 rooza DUNK SIDE > basket_rooza_23 4402bf43 442d219a 442b4000
1 rooza DUNK FRONT > basket_rooza_21 43ebdec1 442d219a 442b4000
1 rooza SHOT_LOW BACK > basket_rooza_10 43faa3da 444e6a3e 4434c000
1 rooza SHOT_LOW SIDE > basket_rooza_11 44070c0a 4448a99a 4434c000
1 rooza SHOT_LOW FRONT > basket_rooza_09 43fa9d01 444e6a3d 4434c000
1 rooza SHOT_MID BACK > basket_rooza_extra_01 43fa0000 44424000 442dc000
1 rooza SHOT_MID SIDE > basket_rooza_extra_02 43fa0000 44424000 442dc000
1 rooza SHOT_MID FRONT > basket_rooza_extra_00 43fa0000 44424000 442dc000
1 rooza SHOT_SET BACK > basket_rooza_13 43fa0000 4429023d 4425c000
1 rooza SHOT_SET SIDE > basket_rooza_14 44025044 4429023d 4425c000
1 rooza SHOT_SET FRONT > basket_rooza_12 43fa0000 4429023d 4425c000
1 rooza RELEASE BACK > basket_rooza_16 44022fdf 442ab800 4428c000
1 rooza RELEASE SIDE > basket_rooza_17 4403339a 442ab800 4428c000
1 rooza RELEASE FRONT > basket_rooza_15 43ebf8be 442ab800 4428c000
1 nova IDLE BACK > nova_idle_back 4404f1c7 444a9b06 442f0000
1 nova IDLE SIDE > basket_nova_02 43fffa1e 444a8000 442f0000
1 nova IDLE FRONT > nova_idle_front 440a7333 44499555 442f0000
1 nova WAITING BACK > nova_idle_back 4404f1c7 444a9b06 442f0000
1 nova WAITING SIDE > basket_nova_02 43fffa1e 444a8000 442f0000
1 nova WAITING FRONT > nova_idle_front 440a7333 44499555 442f0000
1 nova WALK BACK > nova_idle_back 4404f1c7 444a9b06 442f0000
1 nova WALK SIDE > basket_nova_02 43fffa1e 444a8000 442f0000
1 nova WALK FRONT > nova_idle_front 440a7333 44499555 442f0000
1 nova DRIBBLE BACK > nova_idle_back 4400f8e4 4450bb06 442f0000
1 nova DRIBBLE SIDE > basket_nova_02 43fd0000 4450a000 442f0000
1 nova DRIBBLE FRONT > nova_idle_front 4403b99a 444fb555 442f0000
1 nova STEAL BACK > nova_steal_back 4401cccd 44596000 44348000
1 nova STEAL SIDE > nova_steal_side 4401cccd 44596000 443ac000
1 nova STEAL FRONT > nova_steal_front 4401cccd 44596000 4442799a
1 nova BLOCK BACK > nova_block_back 4401cccd 44596000 442e4000
1 nova BLOCK SIDE > nova_block_side 4401cccd 44596000 442d0000
1 nova BLOCK FRONT > nova_block_front 4401cccd 44596000 44368000
1 nova REBOUND BACK > nova_rebound_back 4401cccd 44596000 4436c000
1 nova REBOUND SIDE > nova_rebound_side 4401cccd 44596000 442d8000
1 nova REBOUND FRONT > nova_rebound_front 4401cccd 44596000 44334000
1 nova DUNK BACK > nova_dunk_back_one_hand 440a7edd 442adb9f 44278000
1 nova DUNK SIDE > nova_dunk_side_two_hand_gather 44097954 442bed7c 44288000
1 nova DUNK FRONT > nova_dunk_front_two_hand_power 4403ab85 442a2d4c 44278000
1 nova SHOT_LOW BACK > nova_shot_back_low 43fa2177 44469e87 4433c000
1 nova SHOT_LOW SIDE > nova_shot_side_low 44078b12 44486397 4433c000
1 nova SHOT_LOW FRONT > nova_shot_front_low 43f9e11c 444925f2 4433c000
1 nova SHOT_MID BACK > nova_shot_back_mid 43fa0d5f 4438499d 44320000
1 nova SHOT_MID SIDE > nova_shot_side_mid 4405f217 443e747b 44320000
1 nova SHOT_MID FRONT > nova_shot_front_mid 43fa256f 443be165 44320000
1 nova SHOT_SET BACK > nova_shot_back_set 43fa27d3 44319555 442f0000
1 nova SHOT_SET SIDE > nova_shot_side_set 4405df4a 4434a0b6 442f0000
1 nova SHOT_SET FRONT > nova_shot_front_set 43fa5556 4431e4fa 442f0000
1 nova RELEASE BACK > nova_release_back 4401cccd 44596000 442f0000
1 nova RELEASE SIDE > basket_nova_17 44011421 442ab800 4428c000
1 nova RELEASE FRONT > basket_nova_15 43f0229f 442ab800 4428c000
1 unicorn_32 IDLE BACK > basket_unicorn_32_01 4405d1bc 444a8000 442f0000
1 unicorn_32 IDLE SIDE > basket_unicorn_32_02 4403aaab 444a8000 442f0000
1 unicorn_32 IDLE FRONT > basket_unicorn_32_00 4405ea69 444a8000 442f0000
1 unicorn_32 WAITING BACK > basket_unicorn_32_01 4405d1bc 444a8000 442f0000
1 unicorn_32 WAITING SIDE > basket_unicorn_32_02 4403aaab 444a8000 442f0000
1 unicorn_32 WAITING FRONT > basket_unicorn_32_00 4405ea69 444a8000 442f0000
1 unicorn_32 WALK BACK > basket_unicorn_32_01 4405d1bc 444a8000 442f0000
1 unicorn_32 WALK SIDE > basket_unicorn_32_02 4403aaab 444a8000 442f0000
1 unicorn_32 WALK FRONT > basket_unicorn_32_00 4405ea69 444a8000 442f0000
1 unicorn_32 DRIBBLE BACK > basket_unicorn_32_01 440168de 4450a000 442f0000
1 unicorn_32 DRIBBLE SIDE > basket_unicorn_32_02 44005556 4450a000 442f0000
1 unicorn_32 DRIBBLE FRONT > basket_unicorn_32_00 44017534 4450a000 442f0000
1 unicorn_32 STEAL BACK > basket_unicorn_32_19 4405d04c 44387852 44370000
1 unicorn_32 STEAL SIDE > basket_unicorn_32_20 440554a7 44387852 44370000
1 unicorn_32 STEAL FRONT > basket_unicorn_32_18 44056772 44387852 44370000
1 unicorn_32 BLOCK BACK > basket_unicorn_32_extra_04 43fdf4be 44281eb8 4425c000
1 unicorn_32 BLOCK SIDE > basket_unicorn_32_extra_05 43fd4a2e 44281eb8 4425c000
1 unicorn_32 BLOCK FRONT > basket_unicorn_32_extra_03 43fe719a 44281eb8 4425c000
1 unicorn_32 REBOUND BACK > basket_unicorn_32_extra_07 43fd8507 44281eb8 4425c000
1 unicorn_32 REBOUND SIDE > basket_unicorn_32_extra_08 43fda959 44281eb8 4425c000
1 unicorn_32 REBOUND FRONT > basket_unicorn_32_extra_06 43fd415b 44281eb8 4425c000
1 unicorn_32 DUNK BACK > basket_unicorn_32_22 44045d00 442d219a 442b4000
1 unicorn_32 DUNK SIDE > basket_unicorn_32_23 44031de9 442d219a 442b4000
1 unicorn_32 DUNK FRONT > basket_unicorn_32_21 43e99ca1 442d219a 442b4000
1 unicorn_32 SHOT_LOW BACK > basket_unicorn_32_10 43faccfc 444e6a3d 4434c000
1 unicorn_32 SHOT_LOW SIDE > basket_unicorn_32_11 4408a4ed 4448a99a 4434c000
1 unicorn_32 SHOT_LOW FRONT > basket_unicorn_32_09 43fac3c2 444e6a3d 4434c000
1 unicorn_32 SHOT_MID BACK > basket_unicorn_32_extra_01 43fa0000 44424000 442dc000
1 unicorn_32 SHOT_MID SIDE > basket_unicorn_32_extra_02 43fa0000 44424000 442dc000
1 unicorn_32 SHOT_MID FRONT > basket_unicorn_32_extra_00 43fa0000 44424000 442dc000
1 unicorn_32 SHOT_SET BACK > basket_unicorn_32_13 43fa0000 4429023d 4425c000
1 unicorn_32 SHOT_SET SIDE > basket_unicorn_32_14 4402ac38 4429023d 4425c000
1 unicorn_32 SHOT_SET FRONT > basket_unicorn_32_12 43fa0000 4429023d 4425c000
1 unicorn_32 RELEASE BACK > basket_unicorn_32_16 4402b3c1 442ab800 4428c000
1 unicorn_32 RELEASE SIDE > basket_unicorn_32_17 4402dfc1 442ab800 4428c000
1 unicorn_32 RELEASE FRONT > basket_unicorn_32_15 43e991bf 442ab800 4428c000
1 coach_67 IDLE BACK > coach_67_back_standing 4406f7f3 444a9420 442f0000
1 coach_67 IDLE SIDE > basket_coach_67_02 44014bb4 444a8000 442f0000
1 coach_67 IDLE FRONT > coach_67_front_defense 440a2d15 444bf906 4433d262
1 coach_67 WAITING BACK > coach_67_back_standing 4406f7f3 444a9420 442f0000
1 coach_67 WAITING SIDE > basket_coach_67_02 44014bb4 444a8000 442f0000
1 coach_67 WAITING FRONT > coach_67_front_defense 440a2d15 444bf906 4433d262
1 coach_67 WALK BACK > coach_67_back_standing 4406f7f3 444a9420 442f0000
1 coach_67 WALK SIDE > basket_coach_67_02 44014bb4 444a8000 442f0000
1 coach_67 WALK FRONT > coach_67_front_defense 440a2d15 444bf906 4433d262
1 coach_67 DRIBBLE BACK > coach_67_back_standing 4401fbfa 4450b420 442f0000
1 coach_67 DRIBBLE SIDE > basket_coach_67_02 43fe4bb4 4450a000 442f0000
1 coach_67 DRIBBLE FRONT > coach_67_front_defense 4403968a 44521906 4433d262
1 coach_67 STEAL BACK > coach_67_steal_back 4401cccd 44596000 442f8000
1 coach_67 STEAL SIDE > coach_67_steal_side 4401cccd 44596000 4439c000
1 coach_67 STEAL FRONT > coach_67_steal_front 4401cccd 44596000 443c0148
1 coach_67 BLOCK BACK > coach_67_block_back 4401cccd 44596000 44280000
1 coach_67 BLOCK SIDE > coach_67_block_side 4401cccd 44596000 44280000
1 coach_67 BLOCK FRONT > coach_67_block_front 4401cccd 44596000 442bc000
1 coach_67 REBOUND BACK > coach_67_rebound_back 4401cccd 44596000 4427c000
1 coach_67 REBOUND SIDE > coach_67_rebound_side 4401cccd 44596000 44280000
1 coach_67 REBOUND FRONT > coach_67_rebound_front 4401cccd 44596000 44278000
1 coach_67 DUNK BACK > coach_67_dunk_back_one_hand 44095953 442b4ab5 44278000
1 coach_67 DUNK SIDE > coach_67_dunk_side_two_hand_gather 44085895 442c6c87 44288000
1 coach_67 DUNK FRONT > coach_67_dunk_front_two_hand_power 4403d72c 442acbdd 44278000
1 coach_67 SHOT_LOW BACK > coach_67_shot_back_mid 43fa0000 443530af 442e8000
1 coach_67 SHOT_LOW SIDE > coach_67_shot_side_low 440857be 444541c1 442e0000
1 coach_67 SHOT_LOW FRONT > coach_67_shot_front_low 43fa0aee 44492b46 4433c000
1 coach_67 SHOT_MID BACK > coach_67_shot_back_mid 43fa0000 4435e700 442e8000
1 coach_67 SHOT_MID SIDE > coach_67_shot_side_mid 44085cd2 443a5abe 442c8000
1 coach_67 SHOT_MID FRONT > coach_67_shot_front_mid 43fa0ae3 44386e76 442d0000
1 coach_67 SHOT_SET BACK > coach_67_shot_back_set 43fa0b25 442d1cea 44298000
1 coach_67 SHOT_SET SIDE > coach_67_shot_side_set 44078527 4431e88c 442bc000
1 coach_67 SHOT_SET FRONT > coach_67_shot_front_set 43fa0000 442cd96e 44290000
1 coach_67 RELEASE BACK > coach_67_back_after_throw 4401cccd 44596000 4429f7f3
1 coach_67 RELEASE SIDE > basket_coach_67_17 4401f43a 442ab800 4428c000
1 coach_67 RELEASE FRONT > basket_coach_67_15 43e8b4c0 442ab800 4428c000
1 zephyr IDLE BACK > basket_comet_ground_01 43fa0000 44488503 442c0a10
1 zephyr IDLE SIDE > basket_comet_ground_02 4403d794 444830e2 442bb5ef
1 zephyr IDLE FRONT > basket_comet_ground_00 43fa0000 444830e2 442bb5ef
1 zephyr WAITING BACK > basket_comet_ground_01 43fa0000 44488503 442c0a10
1 zephyr WAITING SIDE > basket_comet_ground_02 4403d794 444830e2 442bb5ef
1 zephyr WAITING FRONT > basket_comet_ground_00 43fa0000 444830e2 442bb5ef
1 zephyr WALK BACK > basket_comet_ground_01 43fa0000 44488503 442c0a10
1 zephyr WALK SIDE > basket_comet_ground_02 4403d794 444830e2 442bb5ef
1 zephyr WALK FRONT > basket_comet_ground_00 43fa0000 444830e2 442bb5ef
1 zephyr DRIBBLE BACK > basket_comet_ground_22 43fd0000 4452a51a 4432f28f
1 zephyr DRIBBLE SIDE > basket_comet_ground_23 44006bcb 4454c85e 443515d3
1 zephyr DRIBBLE FRONT > basket_comet_ground_21 43fd0000 4453a1a6 4433ef1b
1 zephyr STEAL BACK > basket_comet_ground_19 43fa0000 44507789 4436e4fe
1 zephyr STEAL SIDE > basket_comet_ground_20 4403d796 444f26c4 44359439
1 zephyr STEAL FRONT > basket_comet_ground_18 43fa0000 4450a1b6 44370f2b
1 zephyr BLOCK BACK > zephyr_block_back 4401cccd 44596000 442e4000
1 zephyr BLOCK SIDE > zephyr_block_side 4401cccd 44596000 442d0000
1 zephyr BLOCK FRONT > zephyr_block_front 4401cccd 44596000 44368000
1 zephyr REBOUND BACK > zephyr_rebound_back 4401cccd 44596000 4436c000
1 zephyr REBOUND SIDE > zephyr_rebound_side 4401cccd 44596000 442d8000
1 zephyr REBOUND FRONT > zephyr_rebound_front 4401cccd 44596000 44334000
1 zephyr DUNK BACK > zephyr_dunk_back_one_hand 440b9053 442aaa58 44278000
1 zephyr DUNK SIDE > zephyr_dunk_side_two_hand_gather 440de248 442cc760 44288000
1 zephyr DUNK FRONT > zephyr_dunk_front_two_hand_power 440a2492 442b2b93 44278000
1 zephyr SHOT_LOW BACK > basket_comet_ground_10 43fa0000 444d064e 4431cbca
1 zephyr SHOT_LOW SIDE > basket_comet_ground_11 4403d793 444bb570 44307aec
1 zephyr SHOT_LOW FRONT > basket_comet_ground_09 43fa0000 444d064e 4431cbca
1 zephyr SHOT_MID BACK > basket_comet_ground_13 43fa0000 443e0d90 442bb5fe
1 zephyr SHOT_MID SIDE > basket_comet_ground_14 4403d793 443d8f32 442b37a0
1 zephyr SHOT_MID FRONT > basket_comet_ground_12 43fa0000 443d8f32 442b37a0
1 zephyr SHOT_SET BACK > basket_comet_ground_16 43fa0000 442ec880 442b8bdf
1 zephyr SHOT_SET SIDE > basket_comet_ground_17 4403d793 442e4a22 442b0d81
1 zephyr SHOT_SET FRONT > basket_comet_ground_15 43fa0000 442e9e61 442b61c0
1 zephyr RELEASE BACK > zephyr_back_after_throw 4401cccd 44596000 442be4f8
1 zephyr RELEASE SIDE > basket_zephyr_17 4401f0d3 442ab800 4428c000
1 zephyr RELEASE FRONT > basket_zephyr_15 43eb1d38 442ab800 4428c000
1 kyra IDLE BACK > basket_gaya_ground_01 43fa0000 44495556 442e0d98
1 kyra IDLE SIDE > basket_gaya_ground_02 4406b26b 4448c3e3 442d7c25
1 kyra IDLE FRONT > basket_gaya_ground_00 43fa0000 4448f45e 442daca0
1 kyra WAITING BACK > basket_gaya_ground_01 43fa0000 44495556 442e0d98
1 kyra WAITING SIDE > basket_gaya_ground_02 4406b26b 4448c3e3 442d7c25
1 kyra WAITING FRONT > basket_gaya_ground_00 43fa0000 4448f45e 442daca0
1 kyra WALK BACK > basket_gaya_ground_01 43fa0000 44495556 442e0d98
1 kyra WALK SIDE > basket_gaya_ground_02 4406b26b 4448c3e3 442d7c25
1 kyra WALK FRONT > basket_gaya_ground_00 43fa0000 4448f45e 442daca0
1 kyra DRIBBLE BACK > basket_gaya_ground_22 43fd0000 4455f92f 4439fc16
1 kyra DRIBBLE SIDE > basket_gaya_ground_23 4401d937 445506ca 443909b1
1 kyra DRIBBLE FRONT > basket_gaya_ground_21 43fd0000 4455c8c0 4439cba7
1 kyra STEAL BACK > basket_gaya_ground_19 43fa0000 445009bb 443a2ca2
1 kyra STEAL SIDE > basket_gaya_ground_20 4406b26e 444f7835 44399b1c
1 kyra STEAL FRONT > basket_gaya_ground_18 43fa0000 444fa8c0 4439cba7
1 kyra BLOCK BACK > basket_kyra_extra_04 43fd24bf 44281eb8 4425c000
1 kyra BLOCK SIDE > basket_kyra_extra_05 43fce156 44281eb8 4425c000
1 kyra BLOCK FRONT > basket_kyra_extra_03 43fd181c 44281eb8 4425c000
1 kyra REBOUND BACK > basket_kyra_extra_07 43fd181c 44281eb8 4425c000
1 kyra REBOUND SIDE > basket_kyra_extra_08 43fcb2fc 44281eb8 4425c000
1 kyra REBOUND FRONT > basket_kyra_extra_06 43fd13e5 44281eb8 4425c000
1 kyra DUNK BACK > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK SIDE > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK FRONT > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra SHOT_LOW BACK > basket_gaya_ground_10 43fa0000 444ea372 44347e18
1 kyra SHOT_LOW SIDE > basket_gaya_ground_11 4406b26e 444cef0a 4432c9b0
1 kyra SHOT_LOW FRONT > basket_gaya_ground_09 43fa0000 444cef0a 4432c9b0
1 kyra SHOT_MID BACK > basket_gaya_ground_13 43fa0000 443f81f3 442ddd18
1 kyra SHOT_MID SIDE > basket_gaya_ground_14 4406b26d 443ef07b 442d4ba0
1 kyra SHOT_MID FRONT > basket_gaya_ground_12 43fa0000 443f20f9 442d7c1e
1 kyra SHOT_SET BACK > basket_gaya_ground_16 43fa0000 4430fa30 442ddd18
1 kyra SHOT_SET SIDE > basket_gaya_ground_17 4406b26d 4430383b 442d1b23
1 kyra SHOT_SET FRONT > basket_gaya_ground_15 43fa0000 4430fa30 442ddd18
1 kyra RELEASE BACK > basket_kyra_16 4401f4d0 442ab800 4428c000
1 kyra RELEASE SIDE > basket_kyra_17 4400ef07 442ab800 4428c000
1 kyra RELEASE FRONT > basket_kyra_15 43ed7e2e 442ab800 4428c000
1 kyra_original IDLE BACK > basket_kyra_original_01 43fa0000 4448d06a 442d9ad8
1 kyra_original IDLE SIDE > basket_kyra_original_02 4406b88e 44481db8 442ce826
1 kyra_original IDLE FRONT > basket_kyra_original_00 43fa0000 444894ce 442d5f3c
1 kyra_original WAITING BACK > basket_kyra_original_01 43fa0000 4448d06a 442d9ad8
1 kyra_original WAITING SIDE > basket_kyra_original_02 4406b88e 44481db8 442ce826
1 kyra_original WAITING FRONT > basket_kyra_original_00 43fa0000 444894ce 442d5f3c
1 kyra_original WALK BACK > basket_kyra_original_01 43fa0000 4448d06a 442d9ad8
1 kyra_original WALK SIDE > basket_kyra_original_02 4406b88e 44481db8 442ce826
1 kyra_original WALK FRONT > basket_kyra_original_00 43fa0000 444894ce 442d5f3c
1 kyra_original DRIBBLE BACK > basket_kyra_original_01 43fd0000 444ef06a 442d9ad8
1 kyra_original DRIBBLE SIDE > basket_kyra_original_02 4401dc47 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT > basket_kyra_original_00 43fd0000 444eb4ce 442d5f3c
1 kyra_original STEAL BACK > basket_kyra_original_19 43fa0000 444e3804 443494e6
1 kyra_original STEAL SIDE > basket_kyra_original_20 4406b88e 444d856c 4433e24e
1 kyra_original STEAL FRONT > basket_kyra_original_18 43fa0000 444e7376 4434d058
1 kyra_original BLOCK BACK > basket_kyra_original_28 43fa0000 444cdc51 4435477e
1 kyra_original BLOCK SIDE > basket_kyra_original_29 4406b88e 444b3b8b 4433a6b8
1 kyra_original BLOCK FRONT > basket_kyra_original_27 43fa0000 444eb887 443723b4
1 kyra_original REBOUND BACK > basket_kyra_original_31 43fa0000 444d8302 443723c1
1 kyra_original REBOUND SIDE > basket_kyra_original_32 4406b88f 444d8302 443723c1
1 kyra_original REBOUND FRONT > basket_kyra_original_30 43fa0000 444e358b 4437d64a
1 kyra_original DUNK BACK > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original SHOT_LOW BACK > basket_kyra_original_10 43fa0000 444d4174 44336b20
1 kyra_original SHOT_LOW SIDE > basket_kyra_original_11 4406b88f 444c17ce 4432417b
1 kyra_original SHOT_LOW FRONT > basket_kyra_original_09 43fa0000 444db882 4433e22f
1 kyra_original SHOT_MID BACK > basket_kyra_original_25 43fa0000 4443fffc 443494d4
1 kyra_original SHOT_MID SIDE > basket_kyra_original_26 4406b88e 4443c46d 44345945
1 kyra_original SHOT_MID FRONT > basket_kyra_original_24 43fa0000 44443b8a 4434d062
1 kyra_original SHOT_SET BACK > basket_kyra_original_13 43fa0000 442e8ed8 442b4767
1 kyra_original SHOT_SET SIDE > basket_kyra_original_14 4406b890 442e5362 442b0bf1
1 kyra_original SHOT_SET FRONT > basket_kyra_original_12 43fa0000 442e5362 442b0bf1
1 kyra_original RELEASE BACK > basket_kyra_original_16 43fa0000 442ddc53 442a94e2
1 kyra_original RELEASE SIDE > basket_kyra_original_17 4406b890 442da0b9 442a5948
1 kyra_original RELEASE FRONT > basket_kyra_original_15 43fa0000 442ddc53 442a94e2
1 flare IDLE BACK > flare_back_standing 4409045d 4449bf45 442cba2e
1 flare IDLE SIDE > basket_flare_02 4400e706 444a8000 442f0000
1 flare IDLE FRONT > flare_front_defense 440cb974 444b4f46 443268ba
1 flare WAITING BACK > flare_back_standing 4409045d 4449bf45 442cba2e
1 flare WAITING SIDE > basket_flare_02 4400e706 444a8000 442f0000
1 flare WAITING FRONT > flare_front_defense 440cb974 444b4f46 443268ba
1 flare WALK BACK > flare_back_standing 4409045d 4449bf45 442cba2e
1 flare WALK SIDE > basket_flare_02 4400e706 444a8000 442f0000
1 flare WALK FRONT > flare_front_defense 440cb974 444b4f46 443268ba
1 flare DRIBBLE BACK > flare_back_standing 4403022e 444fdf45 442cba2e
1 flare DRIBBLE SIDE > basket_flare_02 43fde706 4450a000 442f0000
1 flare DRIBBLE FRONT > flare_front_defense 4404dcba 44516f46 443268ba
1 flare STEAL BACK > flare_steal_back 4401cccd 44596000 44348000
1 flare STEAL SIDE > flare_steal_side 4401cccd 44596000 443ac000
1 flare STEAL FRONT > flare_steal_front 4401cccd 44596000 4442799a
1 flare BLOCK BACK > flare_block_back 4401cccd 44596000 442e4000
1 flare BLOCK SIDE > flare_block_side 4401cccd 44596000 442d0000
1 flare BLOCK FRONT > flare_block_front 4401cccd 44596000 44368000
1 flare REBOUND BACK > flare_rebound_back 4401cccd 44596000 4436c000
1 flare REBOUND SIDE > flare_rebound_side 4401cccd 44596000 442d8000
1 flare REBOUND FRONT > flare_rebound_front 4401cccd 44596000 44334000
1 flare DUNK BACK > flare_dunk_back_one_hand 440c35ad 442aaa32 44278000
1 flare DUNK SIDE > flare_dunk_side_two_hand_gather 44097a88 442cc661 44288000
1 flare DUNK FRONT > flare_dunk_front_two_hand_power 4403d9cf 442b2a5d 44278000
1 flare SHOT_LOW BACK > flare_shot_back_low 43fa0f18 4446f499 4433c000
1 flare SHOT_LOW SIDE > flare_shot_side_low 4409c5bc 44486c82 4433c000
1 flare SHOT_LOW FRONT > flare_shot_front_low 43fa0ece 44493086 4433c000
1 flare SHOT_MID BACK > flare_shot_back_mid 43fa0000 443aa1ab 4433c000
1 flare SHOT_MID SIDE > flare_shot_side_mid 44070254 443f0ba3 44328000
1 flare SHOT_MID FRONT > flare_shot_front_mid 43fa0e28 443c6c46 44320000
1 flare SHOT_SET BACK > flare_shot_back_set 43fa0eb7 44328526 442f0000
1 flare SHOT_SET SIDE > flare_shot_side_set 440552e4 44350467 442f0000
1 flare SHOT_SET FRONT > flare_shot_front_set 43fa0000 4432d4f8 442f0000
1 flare RELEASE BACK > flare_back_after_throw 4401cccd 44596000 442b9746
1 flare RELEASE SIDE > basket_flare_17 44029b69 442ab800 4428c000
1 flare RELEASE FRONT > basket_flare_15 43eab800 442ab800 4428c000
1 ace_23 IDLE BACK > basket_ace_23_01 44037627 444a8000 442f0000
1 ace_23 IDLE SIDE > basket_ace_23_02 44008a4c 444a8000 442f0000
1 ace_23 IDLE FRONT > basket_ace_23_00 440416bc 444a8000 442f0000
1 ace_23 WAITING BACK > basket_ace_23_01 44037627 444a8000 442f0000
1 ace_23 WAITING SIDE > basket_ace_23_02 44008a4c 444a8000 442f0000
1 ace_23 WAITING FRONT > basket_ace_23_00 440416bc 444a8000 442f0000
1 ace_23 WALK BACK > basket_ace_23_01 44037627 444a8000 442f0000
1 ace_23 WALK SIDE > basket_ace_23_02 44008a4c 444a8000 442f0000
1 ace_23 WALK FRONT > basket_ace_23_00 440416bc 444a8000 442f0000
1 ace_23 DRIBBLE BACK > basket_ace_23_01 44003b14 4450a000 442f0000
1 ace_23 DRIBBLE SIDE > basket_ace_23_02 43fd8a4c 4450a000 442f0000
1 ace_23 DRIBBLE FRONT > basket_ace_23_00 44008b5e 4450a000 442f0000
1 ace_23 STEAL BACK > basket_ace_23_19 44053bd2 44387852 44370000
1 ace_23 STEAL SIDE > basket_ace_23_20 44050bea 44387852 44370000
1 ace_23 STEAL FRONT > basket_ace_23_18 44046909 44387852 44370000
1 ace_23 BLOCK BACK > basket_ace_23_extra_04 43fd2b01 44281eb8 4425c000
1 ace_23 BLOCK SIDE > basket_ace_23_extra_05 43fcf43d 44281eb8 4425c000
1 ace_23 BLOCK FRONT > basket_ace_23_extra_03 43fd9b77 44281eb8 4425c000
1 ace_23 REBOUND BACK > basket_ace_23_extra_07 43fd7c3c 44281eb8 4425c000
1 ace_23 REBOUND SIDE > basket_ace_23_extra_08 43fd3e1c 44281eb8 4425c000
1 ace_23 REBOUND FRONT > basket_ace_23_extra_06 43fd9700 44281eb8 4425c000
1 ace_23 DUNK BACK > basket_ace_23_22 44027ae0 442d219a 442b4000
1 ace_23 DUNK SIDE > basket_ace_23_23 44030473 442d219a 442b4000
1 ace_23 DUNK FRONT > basket_ace_23_21 43eacda0 442d219a 442b4000
1 ace_23 SHOT_LOW BACK > basket_ace_23_10 43faa8a7 444e6a3d 4434c000
1 ace_23 SHOT_LOW SIDE > basket_ace_23_11 44056acb 4448a99a 4434c000
1 ace_23 SHOT_LOW FRONT > basket_ace_23_09 43faae83 444e6a3d 4434c000
1 ace_23 SHOT_MID BACK > basket_ace_23_extra_01 43fa0000 44424000 442dc000
1 ace_23 SHOT_MID SIDE > basket_ace_23_extra_02 43fa0000 44424000 442dc000
1 ace_23 SHOT_MID FRONT > basket_ace_23_extra_00 43fa0000 44424000 442dc000
1 ace_23 SHOT_SET BACK > basket_ace_23_13 43fa0000 4429023d 4425c000
1 ace_23 SHOT_SET SIDE > basket_ace_23_14 44012af9 4429023d 4425c000
1 ace_23 SHOT_SET FRONT > basket_ace_23_12 43fa0000 4429023d 4425c000
1 ace_23 RELEASE BACK > basket_ace_23_16 44021520 442ab800 4428c000
1 ace_23 RELEASE SIDE > basket_ace_23_17 4401978e 442ab800 4428c000
1 ace_23 RELEASE FRONT > basket_ace_23_15 43ed39ce 442ab800 4428c000
1 buddy_23 IDLE BACK > basket_buddy_23_01 4403c0c7 444a8000 442f0000
1 buddy_23 IDLE SIDE > basket_buddy_23_02 4405b5ae 444a8000 442f0000
1 buddy_23 IDLE FRONT > basket_buddy_23_00 4405c7ce 444a8000 442f0000
1 buddy_23 WAITING BACK > basket_buddy_23_01 4403c0c7 444a8000 442f0000
1 buddy_23 WAITING SIDE > basket_buddy_23_02 4405b5ae 444a8000 442f0000
1 buddy_23 WAITING FRONT > basket_buddy_23_00 4405c7ce 444a8000 442f0000
1 buddy_23 WALK BACK > basket_buddy_23_01 4403c0c7 444a8000 442f0000
1 buddy_23 WALK SIDE > basket_buddy_23_02 4405b5ae 444a8000 442f0000
1 buddy_23 WALK FRONT > basket_buddy_23_00 4405c7ce 444a8000 442f0000
1 buddy_23 DRIBBLE BACK > basket_buddy_23_01 44006064 4450a000 442f0000
1 buddy_23 DRIBBLE SIDE > basket_buddy_23_02 44015ad7 4450a000 442f0000
1 buddy_23 DRIBBLE FRONT > basket_buddy_23_00 440163e7 4450a000 442f0000
1 buddy_23 STEAL BACK > basket_buddy_23_19 4405c37a 44387852 44370000
1 buddy_23 STEAL SIDE > basket_buddy_23_20 44064501 44387852 44370000
1 buddy_23 STEAL FRONT > basket_buddy_23_18 4404eeb2 44387852 44370000
1 buddy_23 BLOCK BACK > basket_buddy_23_extra_04 43fd48a4 44281eb8 4425c000
1 buddy_23 BLOCK SIDE > basket_buddy_23_extra_05 43fd0f4d 44281eb8 4425c000
1 buddy_23 BLOCK FRONT > basket_buddy_23_extra_03 43fdbc0b 44281eb8 4425c000
1 buddy_23 REBOUND BACK > basket_buddy_23_extra_07 43fd8408 44281eb8 4425c000
1 buddy_23 REBOUND SIDE > basket_buddy_23_extra_08 43fd4b2d 44281eb8 4425c000
1 buddy_23 REBOUND FRONT > basket_buddy_23_extra_06 43fd5458 44281eb8 4425c000
1 buddy_23 DUNK BACK > basket_buddy_23_22 44038f8c 442d219a 442b4000
1 buddy_23 DUNK SIDE > basket_buddy_23_23 44040a45 442d219a 442b4000
1 buddy_23 DUNK FRONT > basket_buddy_23_21 43ec0c28 442d219a 442b4000
1 buddy_23 SHOT_LOW BACK > basket_buddy_23_10 43faa669 444e6a3e 4434c000
1 buddy_23 SHOT_LOW SIDE > basket_buddy_23_11 44063ab2 4448a99a 4434c000
1 buddy_23 SHOT_LOW FRONT > basket_buddy_23_09 43faaaaf 444e6a3d 4434c000
1 buddy_23 SHOT_MID BACK > basket_buddy_23_extra_01 43fa0000 44424000 442dc000
1 buddy_23 SHOT_MID SIDE > basket_buddy_23_extra_02 43fa0000 44424000 442dc000
1 buddy_23 SHOT_MID FRONT > basket_buddy_23_extra_00 43fa0000 44424000 442dc000
1 buddy_23 SHOT_SET BACK > basket_buddy_23_13 43fa0000 4429023d 4425c000
1 buddy_23 SHOT_SET SIDE > basket_buddy_23_14 4404313a 4429023d 4425c000
1 buddy_23 SHOT_SET FRONT > basket_buddy_23_12 43fa0000 4429023d 4425c000
1 buddy_23 RELEASE BACK > basket_buddy_23_16 4403d8ca 442ab800 4428c000
1 buddy_23 RELEASE SIDE > basket_buddy_23_17 4403636e 442ab800 4428c000
1 buddy_23 RELEASE FRONT > basket_buddy_23_15 43ebb29f 442ab800 4428c000
1 - IDLE BACK > - 4401cccd 44596000 44450000
1 - IDLE SIDE > - 4401cccd 44596000 44450000
1 - IDLE FRONT > - 4401cccd 44596000 44450000
1 - WAITING BACK > - 4401cccd 44596000 44450000
1 - WAITING SIDE > - 4401cccd 44596000 44450000
1 - WAITING FRONT > - 4401cccd 44596000 44450000
1 - WALK BACK > - 4401cccd 44596000 44450000
1 - WALK SIDE > - 4401cccd 44596000 44450000
1 - WALK FRONT > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT > - 4401cccd 44596000 44450000
1 - STEAL BACK > - 4401cccd 44596000 44450000
1 - STEAL SIDE > - 4401cccd 44596000 44450000
1 - STEAL FRONT > - 4401cccd 44596000 44450000
1 - BLOCK BACK > - 4401cccd 44596000 44450000
1 - BLOCK SIDE > - 4401cccd 44596000 44450000
1 - BLOCK FRONT > - 4401cccd 44596000 44450000
1 - REBOUND BACK > - 4401cccd 44596000 44450000
1 - REBOUND SIDE > - 4401cccd 44596000 44450000
1 - REBOUND FRONT > - 4401cccd 44596000 44450000
1 - DUNK BACK > - 4401cccd 44596000 44450000
1 - DUNK SIDE > - 4401cccd 44596000 44450000
1 - DUNK FRONT > - 4401cccd 44596000 44450000
1 - SHOT_LOW BACK > - 4401cccd 44596000 44450000
1 - SHOT_LOW SIDE > - 4401cccd 44596000 44450000
1 - SHOT_LOW FRONT > - 4401cccd 44596000 44450000
1 - SHOT_MID BACK > - 4401cccd 44596000 44450000
1 - SHOT_MID SIDE > - 4401cccd 44596000 44450000
1 - SHOT_MID FRONT > - 4401cccd 44596000 44450000
1 - SHOT_SET BACK > - 4401cccd 44596000 44450000
1 - SHOT_SET SIDE > - 4401cccd 44596000 44450000
1 - SHOT_SET FRONT > - 4401cccd 44596000 44450000
1 - RELEASE BACK > - 4401cccd 44596000 44450000
1 - RELEASE SIDE > - 4401cccd 44596000 44450000
1 - RELEASE FRONT > - 4401cccd 44596000 44450000
1 minik IDLE BACK > - 4401cccd 44596000 44450000
1 minik IDLE SIDE > - 4401cccd 44596000 44450000
1 minik IDLE FRONT > - 4401cccd 44596000 44450000
1 minik WAITING BACK > - 4401cccd 44596000 44450000
1 minik WAITING SIDE > - 4401cccd 44596000 44450000
1 minik WAITING FRONT > - 4401cccd 44596000 44450000
1 minik WALK BACK > - 4401cccd 44596000 44450000
1 minik WALK SIDE > - 4401cccd 44596000 44450000
1 minik WALK FRONT > - 4401cccd 44596000 44450000
1 minik DRIBBLE BACK > - 4401cccd 44596000 44450000
1 minik DRIBBLE SIDE > - 4401cccd 44596000 44450000
1 minik DRIBBLE FRONT > - 4401cccd 44596000 44450000
1 minik STEAL BACK > - 4401cccd 44596000 44450000
1 minik STEAL SIDE > - 4401cccd 44596000 44450000
1 minik STEAL FRONT > - 4401cccd 44596000 44450000
1 minik BLOCK BACK > - 4401cccd 44596000 44450000
1 minik BLOCK SIDE > - 4401cccd 44596000 44450000
1 minik BLOCK FRONT > - 4401cccd 44596000 44450000
1 minik REBOUND BACK > - 4401cccd 44596000 44450000
1 minik REBOUND SIDE > - 4401cccd 44596000 44450000
1 minik REBOUND FRONT > - 4401cccd 44596000 44450000
1 minik DUNK BACK > - 4401cccd 44596000 44450000
1 minik DUNK SIDE > - 4401cccd 44596000 44450000
1 minik DUNK FRONT > - 4401cccd 44596000 44450000
1 minik SHOT_LOW BACK > - 4401cccd 44596000 44450000
1 minik SHOT_LOW SIDE > - 4401cccd 44596000 44450000
1 minik SHOT_LOW FRONT > - 4401cccd 44596000 44450000
1 minik SHOT_MID BACK > - 4401cccd 44596000 44450000
1 minik SHOT_MID SIDE > - 4401cccd 44596000 44450000
1 minik SHOT_MID FRONT > - 4401cccd 44596000 44450000
1 minik SHOT_SET BACK > - 4401cccd 44596000 44450000
1 minik SHOT_SET SIDE > - 4401cccd 44596000 44450000
1 minik SHOT_SET FRONT > - 4401cccd 44596000 44450000
1 minik RELEASE BACK > - 4401cccd 44596000 44450000
1 minik RELEASE SIDE > - 4401cccd 44596000 44450000
1 minik RELEASE FRONT > - 4401cccd 44596000 44450000
1 woman_dark IDLE BACK mir=1 > woman_dark_back_standing 43e6e666 444b0000 442f3333
1 woman_dark IDLE SIDE mir=1 > basket_woman_dark_02 43f0ca28 444a8000 442f0000
1 woman_dark IDLE FRONT mir=1 > woman_dark_front_defense 43e4cccc 444b9999 4432e666
1 woman_dark DRIBBLE BACK mir=1 > woman_dark_back_standing 4401c666 44512000 442f3333
1 woman_dark DRIBBLE SIDE mir=1 > basket_woman_dark_02 43fe9aec 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mir=1 > woman_dark_front_defense 44024ccd 4451b999 4432e666
1 woman_dark SHOT_SET BACK mir=1 > woman_dark_shot_back_set 43f9f577 44318d2b 442f0000
1 woman_dark SHOT_SET SIDE mir=1 > woman_dark_shot_side_set 43e88a8c 44342446 442f0000
1 woman_dark SHOT_SET FRONT mir=1 > woman_dark_shot_front_set 43fa6312 4431c3a4 442f0000
1 woman_dark STEAL BACK mir=1 > woman_dark_steal_back 43f06666 44596000 44348000
1 woman_dark STEAL SIDE mir=1 > woman_dark_steal_side 43f06666 44596000 443ac000
1 woman_dark STEAL FRONT mir=1 > woman_dark_steal_front 43f06666 44596000 4442799a
1 woman_dark DUNK BACK mir=1 > woman_dark_dunk_back_one_hand 43db36ac 442aacab 44278000
1 woman_dark DUNK SIDE mir=1 > woman_dark_dunk_side_two_hand_gather 43e27556 442bbcab 44288000
1 woman_dark DUNK FRONT mir=1 > woman_dark_dunk_front_two_hand_power 43ea6d56 442a3200 44278000
1 woman_dark RELEASE BACK mir=1 > woman_dark_back_after_throw 43f06666 44596000 442d4ccd
1 woman_dark RELEASE SIDE mir=1 > basket_woman_dark_17 43f04172 442ab800 4428c000
1 woman_dark RELEASE FRONT mir=1 > basket_woman_dark_15 4401a400 442ab800 4428c000
1 woman_dark IDLE BACK hs=-1 > woman_dark_back_standing 43e6e666 444b0000 442f3333
1 woman_dark IDLE SIDE hs=-1 > basket_woman_dark_02 43f0ca28 444a8000 442f0000
1 woman_dark IDLE FRONT hs=-1 > woman_dark_front_defense 43e4cccc 444b9999 4432e666
1 woman_dark DRIBBLE BACK hs=-1 > woman_dark_back_standing 43f07333 44512000 442f3333
1 woman_dark DRIBBLE SIDE hs=-1 > basket_woman_dark_02 43f56514 4450a000 442f0000
1 woman_dark DRIBBLE FRONT hs=-1 > woman_dark_front_defense 43ef6666 4451b999 4432e666
1 woman_dark SHOT_LOW BACK hs=-1 > woman_dark_shot_back_low 43fa37a6 4446c9fd 4433c000
1 woman_dark SHOT_LOW SIDE hs=-1 > woman_dark_shot_side_low 44077d05 44485174 4433c000
1 woman_dark SHOT_LOW FRONT hs=-1 > woman_dark_shot_front_low 43fa096f 44491f45 4433c000
1 woman_dark IDLE BACK mv=1 loco=0 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark IDLE BACK mv=1 loco=1 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark IDLE BACK mv=1 loco=2 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark IDLE BACK mv=1 loco=5 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark IDLE SIDE mv=1 loco=0 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark IDLE SIDE mv=1 loco=1 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark IDLE SIDE mv=1 loco=2 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark IDLE SIDE mv=1 loco=5 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark IDLE FRONT mv=1 loco=0 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark IDLE FRONT mv=1 loco=1 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark IDLE FRONT mv=1 loco=2 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark IDLE FRONT mv=1 loco=5 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark WALK BACK mv=1 loco=0 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark WALK BACK mv=1 loco=1 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark WALK BACK mv=1 loco=2 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark WALK BACK mv=1 loco=5 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark WALK SIDE mv=1 loco=0 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark WALK SIDE mv=1 loco=1 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark WALK SIDE mv=1 loco=2 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark WALK SIDE mv=1 loco=5 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark WALK FRONT mv=1 loco=0 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark WALK FRONT mv=1 loco=1 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark WALK FRONT mv=1 loco=2 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark WALK FRONT mv=1 loco=5 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark DRIBBLE BACK mv=1 loco=0 > basket_woman_dark_05 43fe8889 4450a000 442f0000
1 woman_dark DRIBBLE BACK mv=1 loco=1 > basket_woman_dark_06 43ff3c0d 4450a000 442f0000
1 woman_dark DRIBBLE BACK mv=1 loco=2 > basket_woman_dark_05 43fe8889 4450a000 442f0000
1 woman_dark DRIBBLE BACK mv=1 loco=5 > basket_woman_dark_06 43ff3c0d 4450a000 442f0000
1 woman_dark DRIBBLE SIDE mv=1 loco=0 > basket_woman_dark_07 440177f8 4450a000 442f0000
1 woman_dark DRIBBLE SIDE mv=1 loco=1 > basket_woman_dark_08 44018348 4450a000 442f0000
1 woman_dark DRIBBLE SIDE mv=1 loco=2 > basket_woman_dark_07 440177f8 4450a000 442f0000
1 woman_dark DRIBBLE SIDE mv=1 loco=5 > basket_woman_dark_08 44018348 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 loco=0 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 loco=1 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 loco=2 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 loco=5 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark WAITING BACK mv=1 loco=0 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark WAITING BACK mv=1 loco=1 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark WAITING BACK mv=1 loco=2 > basket_woman_dark_05 44018889 444a8000 442f0000
1 woman_dark WAITING BACK mv=1 loco=5 > basket_woman_dark_06 44023c0d 444a8000 442f0000
1 woman_dark WAITING SIDE mv=1 loco=0 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark WAITING SIDE mv=1 loco=1 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark WAITING SIDE mv=1 loco=2 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark WAITING SIDE mv=1 loco=5 > basket_woman_dark_08 44060690 444a8000 442f0000
1 woman_dark WAITING FRONT mv=1 loco=0 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark WAITING FRONT mv=1 loco=1 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark WAITING FRONT mv=1 loco=2 > basket_woman_dark_03 44017602 444a8000 442f0000
1 woman_dark WAITING FRONT mv=1 loco=5 > basket_woman_dark_04 44018cd9 444a8000 442f0000
1 woman_dark DRIBBLE BACK mv=1 fast=1 loco=1 > basket_woman_dark_06 44013e06 4450a000 442f0000
1 woman_dark DRIBBLE BACK hs=-1 mv=1 fast=1 loco=1 > basket_woman_dark_06 43f183f3 4450a000 442f0000
1 woman_dark DRIBBLE BACK hs=0 mv=1 fast=1 loco=1 > basket_woman_dark_06 44013e06 4450a000 442f0000
1 woman_dark DRIBBLE BACK hs=-0.3 mv=1 fast=1 loco=1 > basket_woman_dark_06 43f183f3 4450a000 442f0000
1 woman_dark DRIBBLE SIDE mv=1 fast=1 loco=1 > basket_woman_dark_08 44032348 4450a000 442f0000
1 woman_dark DRIBBLE SIDE hs=-1 mv=1 fast=1 loco=1 > basket_woman_dark_08 43edb970 4450a000 442f0000
1 woman_dark DRIBBLE SIDE hs=0 mv=1 fast=1 loco=1 > basket_woman_dark_08 44032348 4450a000 442f0000
1 woman_dark DRIBBLE SIDE hs=-0.3 mv=1 fast=1 loco=1 > basket_woman_dark_08 43edb970 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 loco=1 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT hs=-1 mv=1 fast=1 loco=1 > basket_woman_dark_04 43f23327 4450a000 442f0000
1 woman_dark DRIBBLE FRONT hs=0 mv=1 fast=1 loco=1 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT hs=-0.3 mv=1 fast=1 loco=1 > basket_woman_dark_04 43f23327 4450a000 442f0000
1 woman_dark DRIBBLE BACK ph=0 > woman_dark_back_standing 44068ccd 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=0.5 > woman_dark_back_standing 43fa0000 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=0.75 > woman_dark_back_standing 43f07333 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=1 > woman_dark_back_standing 43e6e666 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=1.3 > woman_dark_back_standing 43e6e666 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=-0.2 > woman_dark_back_standing 44068ccd 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=0.499 > woman_dark_back_standing 43fa09c8 44512000 442f3333
1 woman_dark DRIBBLE BACK ph=0.501 > woman_dark_back_standing 43f9f639 44512000 442f3333
1 woman_dark DRIBBLE SIDE ph=0 > basket_woman_dark_02 44019aec 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=0.5 > basket_woman_dark_02 43fa0000 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=0.75 > basket_woman_dark_02 43f56514 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=1 > basket_woman_dark_02 43f0ca28 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=1.3 > basket_woman_dark_02 43f0ca28 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=-0.2 > basket_woman_dark_02 44019aec 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=0.499 > basket_woman_dark_02 43fa04b7 4450a000 442f0000
1 woman_dark DRIBBLE SIDE ph=0.501 > basket_woman_dark_02 43f9fb49 4450a000 442f0000
1 woman_dark DRIBBLE FRONT ph=0 > woman_dark_front_defense 4407999a 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=0.5 > woman_dark_front_defense 43fa0000 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=0.75 > woman_dark_front_defense 43ef6666 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=1 > woman_dark_front_defense 43e4cccc 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=1.3 > woman_dark_front_defense 43e4cccc 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=-0.2 > woman_dark_front_defense 4407999a 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=0.499 > woman_dark_front_defense 43fa0adb 4451b999 4432e666
1 woman_dark DRIBBLE FRONT ph=0.501 > woman_dark_front_defense 43f9f525 4451b999 4432e666
1 woman_dark DRIBBLE FRONT b=0 ph=0.75 > woman_dark_front_defense 43ef6666 444b9999 4432e666
1 woman_dark DRIBBLE SIDE b=0 mv=1 fast=1 loco=0 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark DRIBBLE FRONT b=49 ph=0.75 > woman_dark_front_defense 43ef6666 4457d999 4432e666
1 woman_dark DRIBBLE SIDE b=49 mv=1 fast=1 loco=0 > basket_woman_dark_07 44004000 4456c000 442f0000
1 woman_dark DRIBBLE FRONT b=60 ph=0.75 > woman_dark_front_defense 43ef6666 445a9999 4432e666
1 woman_dark DRIBBLE SIDE b=60 mv=1 fast=1 loco=0 > basket_woman_dark_07 44004000 44598000 442f0000
1 woman_dark DRIBBLE FRONT b=-5 ph=0.75 > woman_dark_front_defense 43ef6666 444b9999 4432e666
1 woman_dark DRIBBLE SIDE b=-5 mv=1 fast=1 loco=0 > basket_woman_dark_07 4405efef 444a8000 442f0000
1 woman_dark DRIBBLE FRONT b=12.3 ph=0.75 > woman_dark_front_defense 43ef6666 444eaccc 4432e666
1 woman_dark DRIBBLE SIDE b=12.3 mv=1 fast=1 loco=0 > basket_woman_dark_07 44048277 444d9333 442f0000
1 woman_dark IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 > woman_dark_front_celebrate 44000000 4456c000 44450000
1 woman_dark IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 mir=1 > woman_dark_front_celebrate 43f40000 4456c000 44450000
1 woman_dark IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 > woman_dark_front_sitting_sad 44000000 4456c000 44450000
1 woman_dark IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 mir=1 > woman_dark_front_sitting_sad 43f40000 4456c000 44450000
1 woman_dark IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 > woman_dark_front_sitting 44000000 4456c000 44450000
1 woman_dark IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 mir=1 > woman_dark_front_sitting 43f40000 4456c000 44450000
1 woman_dark IDLE FRONT style=BOT shot=GRANNY > woman_dark_front_defense 4401cccd 44596000 44450000
1 woman_dark IDLE FRONT style=BOT shot=GRANNY mir=1 > woman_dark_front_defense 4401cccd 44596000 44450000
1 woman_dark SHOT_SET FRONT style=BOT shot=GRANNY > woman_dark_shot_front_set 4401cccd 44596000 44450000
1 woman_dark SHOT_SET FRONT style=BOT shot=GRANNY mir=1 > woman_dark_shot_front_set 4401cccd 44596000 44450000
1 woman_dark DUNK BACK > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK BACK act=0 > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK BACK act=1 > woman_dark_dunk_back_two_hand_power 44048d55 44299911 44270000
1 woman_dark DUNK BACK act=2 > woman_dark_dunk_back_two_hand_hang 44049e00 4428f000 44268000
1 woman_dark DUNK BACK act=3 > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark DUNK BACK act=4 > woman_dark_dunk_front_two_hand_hang 4402ca00 44287333 44268000
1 woman_dark DUNK BACK act=5 > woman_dark_dunk_front_statue 440deaaa 442aa000 44270000
1 woman_dark DUNK BACK act=6 > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK BACK act=7 > woman_dark_dunk_side_reverse_gather 44084800 442e3c00 44280000
1 woman_dark DUNK BACK act=8 > woman_dark_dunk_side_two_hand_hang 4407c111 4429b800 44270000
1 woman_dark DUNK BACK act=9 > woman_dark_dunk_side_statue 440d219a 442a6222 44270000
1 woman_dark DUNK BACK act=10 > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK SIDE > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK SIDE act=0 > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK SIDE act=1 > woman_dark_dunk_back_two_hand_power 44048d55 44299911 44270000
1 woman_dark DUNK SIDE act=2 > woman_dark_dunk_back_two_hand_hang 44049e00 4428f000 44268000
1 woman_dark DUNK SIDE act=3 > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark DUNK SIDE act=4 > woman_dark_dunk_front_two_hand_hang 4402ca00 44287333 44268000
1 woman_dark DUNK SIDE act=5 > woman_dark_dunk_front_statue 440deaaa 442aa000 44270000
1 woman_dark DUNK SIDE act=6 > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK SIDE act=7 > woman_dark_dunk_side_reverse_gather 44084800 442e3c00 44280000
1 woman_dark DUNK SIDE act=8 > woman_dark_dunk_side_two_hand_hang 4407c111 4429b800 44270000
1 woman_dark DUNK SIDE act=9 > woman_dark_dunk_side_statue 440d219a 442a6222 44270000
1 woman_dark DUNK SIDE act=10 > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK FRONT > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark DUNK FRONT act=0 > woman_dark_dunk_back_one_hand 440c64aa 442aacab 44278000
1 woman_dark DUNK FRONT act=1 > woman_dark_dunk_back_two_hand_power 44048d55 44299911 44270000
1 woman_dark DUNK FRONT act=2 > woman_dark_dunk_back_two_hand_hang 44049e00 4428f000 44268000
1 woman_dark DUNK FRONT act=3 > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark DUNK FRONT act=4 > woman_dark_dunk_front_two_hand_hang 4402ca00 44287333 44268000
1 woman_dark DUNK FRONT act=5 > woman_dark_dunk_front_statue 440deaaa 442aa000 44270000
1 woman_dark DUNK FRONT act=6 > woman_dark_dunk_side_two_hand_gather 4408c555 442bbcab 44288000
1 woman_dark DUNK FRONT act=7 > woman_dark_dunk_side_reverse_gather 44084800 442e3c00 44280000
1 woman_dark DUNK FRONT act=8 > woman_dark_dunk_side_two_hand_hang 4407c111 4429b800 44270000
1 woman_dark DUNK FRONT act=9 > woman_dark_dunk_side_statue 440d219a 442a6222 44270000
1 woman_dark DUNK FRONT act=10 > woman_dark_dunk_front_two_hand_power 4404c955 442a3200 44278000
1 woman_dark SHOT_SET SIDE mir=1 vs=0.5 > woman_dark_shot_side_set 43eb28f8 443aded6 44368000
1 woman_dark IDLE FRONT vs=0.5 > woman_dark_front_defense 4406028f 444ecf5c 4439d0a4
1 woman_dark SHOT_SET SIDE mir=1 vs=1.1 > woman_dark_shot_side_set 43e6cb9c 442fa7e7 442a0000
1 woman_dark IDLE FRONT vs=1.1 > woman_dark_front_defense 4408a8f6 444975c2 442e4a3d
1 woman_dark SHOT_SET SIDE mir=1 vs=2 > woman_dark_shot_side_set 43e42d30 4428ed58 44228000
1 woman_dark IDLE FRONT vs=2 > woman_dark_front_defense 440a4000 44464000 44276000
1 woman_dark SHOT_SET SIDE mir=1 vs=0.9 > woman_dark_shot_side_set 43ea4980 4438a0a6 44340000
1 woman_dark IDLE FRONT vs=0.9 > woman_dark_front_defense 44068a3e 444dbd71 44378290
1 woman_dark DRIBBLE FRONT mv=1 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=204 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=204 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=205 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=205 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=249 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=249 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=250 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=250 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=409 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=409 > basket_woman_dark_04 4400e66c 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=410 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=410 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=499 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=499 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=500 > basket_woman_dark_03 43fe7602 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=500 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 up=123456789 > basket_woman_dark_04 43fe8cd9 4450a000 442f0000
1 woman_dark DRIBBLE FRONT mv=1 fast=1 up=123456789 > basket_woman_dark_03 4400db01 4450a000 442f0000
1 kyra IDLE BACK mir=1 > basket_gaya_ground_01 43fa0000 44495556 442e0d98
1 kyra IDLE SIDE mir=1 > basket_gaya_ground_02 43e69b2a 4448c3e3 442d7c25
1 kyra IDLE FRONT mir=1 > basket_gaya_ground_00 43fa0000 4448f45e 442daca0
1 kyra DRIBBLE BACK mir=1 > basket_gaya_ground_22 43fd0000 4455f92f 4439fc16
1 kyra DRIBBLE SIDE mir=1 > basket_gaya_ground_23 4401d937 445506ca 443909b1
1 kyra DRIBBLE FRONT mir=1 > basket_gaya_ground_21 43fd0000 4455c8c0 4439cba7
1 kyra SHOT_SET BACK mir=1 > basket_gaya_ground_16 43fa0000 4430fa30 442ddd18
1 kyra SHOT_SET SIDE mir=1 > basket_gaya_ground_17 43e69b26 4430383b 442d1b23
1 kyra SHOT_SET FRONT mir=1 > basket_gaya_ground_15 43fa0000 4430fa30 442ddd18
1 kyra STEAL BACK mir=1 > basket_gaya_ground_19 43fa0000 445009bb 443a2ca2
1 kyra STEAL SIDE mir=1 > basket_gaya_ground_20 43e69b24 444f7835 44399b1c
1 kyra STEAL FRONT mir=1 > basket_gaya_ground_18 43fa0000 444fa8c0 4439cba7
1 kyra DUNK BACK mir=1 > basket_kyra_22 43ef7ee8 442d219a 442b4000
1 kyra DUNK SIDE mir=1 > basket_kyra_23 43ec6c28 442d219a 442b4000
1 kyra DUNK FRONT mir=1 > basket_kyra_21 4403efcc 442d219a 442b4000
1 kyra RELEASE BACK mir=1 > basket_kyra_16 43f01660 442ab800 4428c000
1 kyra RELEASE SIDE mir=1 > basket_kyra_17 43f221f2 442ab800 4428c000
1 kyra RELEASE FRONT mir=1 > basket_kyra_15 440340e9 442ab800 4428c000
1 kyra IDLE BACK hs=-1 > basket_gaya_ground_01 43fa0000 44495556 442e0d98
1 kyra IDLE SIDE hs=-1 > basket_gaya_ground_02 43e69b2a 4448c3e3 442d7c25
1 kyra IDLE FRONT hs=-1 > basket_gaya_ground_00 43fa0000 4448f45e 442daca0
1 kyra DRIBBLE BACK hs=-1 > basket_gaya_ground_22 43f70000 4455f92f 4439fc16
1 kyra DRIBBLE SIDE hs=-1 > basket_gaya_ground_23 43f04d92 445506ca 443909b1
1 kyra DRIBBLE FRONT hs=-1 > basket_gaya_ground_21 43f70000 4455c8c0 4439cba7
1 kyra SHOT_LOW BACK hs=-1 > basket_gaya_ground_10 43fa0000 444ea372 44347e18
1 kyra SHOT_LOW SIDE hs=-1 > basket_gaya_ground_11 4406b26e 444cef0a 4432c9b0
1 kyra SHOT_LOW FRONT hs=-1 > basket_gaya_ground_09 43fa0000 444cef0a 4432c9b0
1 kyra IDLE BACK mv=1 loco=0 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra IDLE BACK mv=1 loco=1 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra IDLE BACK mv=1 loco=2 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra IDLE BACK mv=1 loco=5 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra IDLE SIDE mv=1 loco=0 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra IDLE SIDE mv=1 loco=1 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra IDLE SIDE mv=1 loco=2 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra IDLE SIDE mv=1 loco=5 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra IDLE FRONT mv=1 loco=0 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra IDLE FRONT mv=1 loco=1 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra IDLE FRONT mv=1 loco=2 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra IDLE FRONT mv=1 loco=5 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra WALK BACK mv=1 loco=0 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra WALK BACK mv=1 loco=1 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra WALK BACK mv=1 loco=2 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra WALK BACK mv=1 loco=5 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra WALK SIDE mv=1 loco=0 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra WALK SIDE mv=1 loco=1 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra WALK SIDE mv=1 loco=2 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra WALK SIDE mv=1 loco=5 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra WALK FRONT mv=1 loco=0 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra WALK FRONT mv=1 loco=1 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra WALK FRONT mv=1 loco=2 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra WALK FRONT mv=1 loco=5 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra DRIBBLE BACK mv=1 loco=0 > basket_gaya_ground_05 4401d936 444e21f4 442cba36
1 kyra DRIBBLE BACK mv=1 loco=1 > basket_gaya_ground_06 43fd0000 44504e88 44317646
1 kyra DRIBBLE BACK mv=1 loco=2 > basket_gaya_ground_05 4401d936 444e21f4 442cba36
1 kyra DRIBBLE BACK mv=1 loco=5 > basket_gaya_ground_06 43fd0000 44504e88 44317646
1 kyra DRIBBLE SIDE mv=1 loco=0 > basket_gaya_ground_07 43fd0000 44504e88 44317646
1 kyra DRIBBLE SIDE mv=1 loco=1 > basket_gaya_ground_08 4401d937 44504e88 44317646
1 kyra DRIBBLE SIDE mv=1 loco=2 > basket_gaya_ground_07 43fd0000 44504e88 44317646
1 kyra DRIBBLE SIDE mv=1 loco=5 > basket_gaya_ground_08 4401d937 44504e88 44317646
1 kyra DRIBBLE FRONT mv=1 loco=0 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 loco=1 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 loco=2 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 loco=5 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra WAITING BACK mv=1 loco=0 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra WAITING BACK mv=1 loco=1 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra WAITING BACK mv=1 loco=2 > basket_gaya_ground_05 4406b26b 444801f4 442cba36
1 kyra WAITING BACK mv=1 loco=5 > basket_gaya_ground_06 43fa0000 444a2e88 44317646
1 kyra WAITING SIDE mv=1 loco=0 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra WAITING SIDE mv=1 loco=1 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra WAITING SIDE mv=1 loco=2 > basket_gaya_ground_07 43fa0000 444a2e88 44317646
1 kyra WAITING SIDE mv=1 loco=5 > basket_gaya_ground_08 4406b26e 444a2e88 44317646
1 kyra WAITING FRONT mv=1 loco=0 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra WAITING FRONT mv=1 loco=1 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra WAITING FRONT mv=1 loco=2 > basket_gaya_ground_03 43fa0000 44483270 442ceab2
1 kyra WAITING FRONT mv=1 loco=5 > basket_gaya_ground_04 43fa0000 4447d178 442c89ba
1 kyra DRIBBLE BACK mv=1 fast=1 loco=1 > basket_gaya_ground_06 44002000 44504e88 44317646
1 kyra DRIBBLE BACK hs=-1 mv=1 fast=1 loco=1 > basket_gaya_ground_06 43f3c000 44504e88 44317646
1 kyra DRIBBLE BACK hs=0 mv=1 fast=1 loco=1 > basket_gaya_ground_06 44002000 44504e88 44317646
1 kyra DRIBBLE BACK hs=-0.3 mv=1 fast=1 loco=1 > basket_gaya_ground_06 43f3c000 44504e88 44317646
1 kyra DRIBBLE SIDE mv=1 fast=1 loco=1 > basket_gaya_ground_08 44037937 44504e88 44317646
1 kyra DRIBBLE SIDE hs=-1 mv=1 fast=1 loco=1 > basket_gaya_ground_08 43ed0d92 44504e88 44317646
1 kyra DRIBBLE SIDE hs=0 mv=1 fast=1 loco=1 > basket_gaya_ground_08 44037937 44504e88 44317646
1 kyra DRIBBLE SIDE hs=-0.3 mv=1 fast=1 loco=1 > basket_gaya_ground_08 43ed0d92 44504e88 44317646
1 kyra DRIBBLE FRONT mv=1 fast=1 loco=1 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT hs=-1 mv=1 fast=1 loco=1 > basket_gaya_ground_04 43f3c000 444df178 442c89ba
1 kyra DRIBBLE FRONT hs=0 mv=1 fast=1 loco=1 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT hs=-0.3 mv=1 fast=1 loco=1 > basket_gaya_ground_04 43f3c000 444df178 442c89ba
1 kyra DRIBBLE BACK ph=0 > basket_gaya_ground_22 44000000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=0.5 > basket_gaya_ground_22 43fa0000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=0.75 > basket_gaya_ground_22 43f70000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=1 > basket_gaya_ground_22 43f40000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=1.3 > basket_gaya_ground_22 43f40000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=-0.2 > basket_gaya_ground_22 44000000 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=0.499 > basket_gaya_ground_22 43fa0312 4455f92f 4439fc16
1 kyra DRIBBLE BACK ph=0.501 > basket_gaya_ground_22 43f9fcee 4455f92f 4439fc16
1 kyra DRIBBLE SIDE ph=0 > basket_gaya_ground_23 4406b26e 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=0.5 > basket_gaya_ground_23 43fa0000 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=0.75 > basket_gaya_ground_23 43f04d92 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=1 > basket_gaya_ground_23 43e69b24 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=1.3 > basket_gaya_ground_23 43e69b24 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=-0.2 > basket_gaya_ground_23 4406b26e 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=0.499 > basket_gaya_ground_23 43fa09ee 445506ca 443909b1
1 kyra DRIBBLE SIDE ph=0.501 > basket_gaya_ground_23 43f9f612 445506ca 443909b1
1 kyra DRIBBLE FRONT ph=0 > basket_gaya_ground_21 44000000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=0.5 > basket_gaya_ground_21 43fa0000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=0.75 > basket_gaya_ground_21 43f70000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=1 > basket_gaya_ground_21 43f40000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=1.3 > basket_gaya_ground_21 43f40000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=-0.2 > basket_gaya_ground_21 44000000 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=0.499 > basket_gaya_ground_21 43fa0312 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT ph=0.501 > basket_gaya_ground_21 43f9fcee 4455c8c0 4439cba7
1 kyra DRIBBLE FRONT b=0 ph=0.75 > basket_gaya_ground_21 43f70000 444fa8c0 4439cba7
1 kyra DRIBBLE SIDE b=0 mv=1 fast=1 loco=0 > basket_gaya_ground_07 44000000 444a2e88 44317646
1 kyra DRIBBLE FRONT b=49 ph=0.75 > basket_gaya_ground_21 43f70000 445be8c0 4439cba7
1 kyra DRIBBLE SIDE b=49 mv=1 fast=1 loco=0 > basket_gaya_ground_07 44004000 44566e88 44317646
1 kyra DRIBBLE FRONT b=60 ph=0.75 > basket_gaya_ground_21 43f70000 445ea8c0 4439cba7
1 kyra DRIBBLE SIDE b=60 mv=1 fast=1 loco=0 > basket_gaya_ground_07 44004000 44592e88 44317646
1 kyra DRIBBLE FRONT b=-5 ph=0.75 > basket_gaya_ground_21 43f70000 444fa8c0 4439cba7
1 kyra DRIBBLE SIDE b=-5 mv=1 fast=1 loco=0 > basket_gaya_ground_07 44000000 444a2e88 44317646
1 kyra DRIBBLE FRONT b=12.3 ph=0.75 > basket_gaya_ground_21 43f70000 4452bbf3 4439cba7
1 kyra DRIBBLE SIDE b=12.3 mv=1 fast=1 loco=0 > basket_gaya_ground_07 44001011 444d41bb 44317646
1 kyra IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 > basket_kyra_extra_09 44000000 4456c000 44450000
1 kyra IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_extra_09 43f40000 4456c000 44450000
1 kyra IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 > basket_kyra_extra_10 44000000 4456c000 44450000
1 kyra IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_extra_10 43f40000 4456c000 44450000
1 kyra IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 > basket_kyra_extra_11 44000000 4456c000 44450000
1 kyra IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_extra_11 43f40000 4456c000 44450000
1 kyra IDLE FRONT style=BOT shot=GRANNY > basket_gaya_ground_00 4401cccd 44596000 44450000
1 kyra IDLE FRONT style=BOT shot=GRANNY mir=1 > basket_gaya_ground_00 4401cccd 44596000 44450000
1 kyra SHOT_SET FRONT style=BOT shot=GRANNY > basket_gaya_ground_15 4401cccd 44596000 44450000
1 kyra SHOT_SET FRONT style=BOT shot=GRANNY mir=1 > basket_gaya_ground_15 4401cccd 44596000 44450000
1 kyra DUNK BACK > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=0 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK BACK act=1 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=2 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK BACK act=3 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=4 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=5 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=6 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=7 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=8 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=9 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK BACK act=10 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK SIDE > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=0 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK SIDE act=1 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK SIDE act=2 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=3 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=4 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=5 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=6 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=7 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=8 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=9 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK SIDE act=10 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK FRONT > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=0 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=1 > basket_kyra_22 4402408c 442d219a 442b4000
1 kyra DUNK FRONT act=2 > basket_kyra_23 4403c9ec 442d219a 442b4000
1 kyra DUNK FRONT act=3 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=4 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=5 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=6 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=7 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=8 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=9 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra DUNK FRONT act=10 > basket_kyra_21 43ec2067 442d219a 442b4000
1 kyra SHOT_SET SIDE mir=1 vs=0.5 > basket_gaya_ground_17 43e983e0 44378965 4434e3de
1 kyra IDLE FRONT vs=0.5 > basket_gaya_ground_00 43fa0000 444c8fb6 44355f88
1 kyra SHOT_SET SIDE mir=1 vs=1.1 > basket_gaya_ground_17 43e4aaaa 442b5773 4427eaa6
1 kyra IDLE FRONT vs=1.1 > basket_gaya_ground_00 43fa0000 44468cce 44288ab0
1 kyra SHOT_SET SIDE mir=1 vs=2 > basket_gaya_ground_17 43e1c1f0 44240649 442021ec
1 kyra IDLE FRONT vs=2 > basket_gaya_ground_00 43fa0000 4442f175 4420d7c8
1 kyra SHOT_SET SIDE mir=1 vs=0.9 > basket_gaya_ground_17 43e88ba2 44351902 44324ba0
1 kyra IDLE FRONT vs=0.9 > basket_gaya_ground_00 43fa0000 444b5bef 4432ce91
1 kyra DRIBBLE FRONT mv=1 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 fast=1 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 up=204 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 fast=1 up=204 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 up=205 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 fast=1 up=205 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 up=249 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 fast=1 up=249 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 up=250 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 fast=1 up=250 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 up=409 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 fast=1 up=409 > basket_gaya_ground_04 44002000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 up=410 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 fast=1 up=410 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 up=499 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 fast=1 up=499 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 up=500 > basket_gaya_ground_03 43fd0000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 fast=1 up=500 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra DRIBBLE FRONT mv=1 up=123456789 > basket_gaya_ground_04 43fd0000 444df178 442c89ba
1 kyra DRIBBLE FRONT mv=1 fast=1 up=123456789 > basket_gaya_ground_03 44002000 444e5270 442ceab2
1 kyra_original IDLE BACK mir=1 > basket_kyra_original_01 43fa0000 4448d06a 442d9ad8
1 kyra_original IDLE SIDE mir=1 > basket_kyra_original_02 43e68ee4 44481db8 442ce826
1 kyra_original IDLE FRONT mir=1 > basket_kyra_original_00 43fa0000 444894ce 442d5f3c
1 kyra_original DRIBBLE BACK mir=1 > basket_kyra_original_01 43fd0000 444ef06a 442d9ad8
1 kyra_original DRIBBLE SIDE mir=1 > basket_kyra_original_02 4401dc47 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mir=1 > basket_kyra_original_00 43fd0000 444eb4ce 442d5f3c
1 kyra_original SHOT_SET BACK mir=1 > basket_kyra_original_13 43fa0000 442e8ed8 442b4767
1 kyra_original SHOT_SET SIDE mir=1 > basket_kyra_original_14 43e68ee0 442e5362 442b0bf1
1 kyra_original SHOT_SET FRONT mir=1 > basket_kyra_original_12 43fa0000 442e5362 442b0bf1
1 kyra_original STEAL BACK mir=1 > basket_kyra_original_19 43fa0000 444e3804 443494e6
1 kyra_original STEAL SIDE mir=1 > basket_kyra_original_20 43e68ee4 444d856c 4433e24e
1 kyra_original STEAL FRONT mir=1 > basket_kyra_original_18 43fa0000 444e7376 4434d058
1 kyra_original DUNK BACK mir=1 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE mir=1 > basket_kyra_original_23 43e68ee4 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT mir=1 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original RELEASE BACK mir=1 > basket_kyra_original_16 43fa0000 442ddc53 442a94e2
1 kyra_original RELEASE SIDE mir=1 > basket_kyra_original_17 43e68ee0 442da0b9 442a5948
1 kyra_original RELEASE FRONT mir=1 > basket_kyra_original_15 43fa0000 442ddc53 442a94e2
1 kyra_original IDLE BACK hs=-1 > basket_kyra_original_01 43fa0000 4448d06a 442d9ad8
1 kyra_original IDLE SIDE hs=-1 > basket_kyra_original_02 43e68ee4 44481db8 442ce826
1 kyra_original IDLE FRONT hs=-1 > basket_kyra_original_00 43fa0000 444894ce 442d5f3c
1 kyra_original DRIBBLE BACK hs=-1 > basket_kyra_original_01 43f70000 444ef06a 442d9ad8
1 kyra_original DRIBBLE SIDE hs=-1 > basket_kyra_original_02 43f04772 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT hs=-1 > basket_kyra_original_00 43f70000 444eb4ce 442d5f3c
1 kyra_original SHOT_LOW BACK hs=-1 > basket_kyra_original_10 43fa0000 444d4174 44336b20
1 kyra_original SHOT_LOW SIDE hs=-1 > basket_kyra_original_11 4406b88f 444c17ce 4432417b
1 kyra_original SHOT_LOW FRONT hs=-1 > basket_kyra_original_09 43fa0000 444db882 4433e22f
1 kyra_original IDLE BACK mv=1 loco=0 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original IDLE BACK mv=1 loco=1 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original IDLE BACK mv=1 loco=2 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original IDLE BACK mv=1 loco=5 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original IDLE SIDE mv=1 loco=0 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original IDLE SIDE mv=1 loco=1 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original IDLE SIDE mv=1 loco=2 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original IDLE SIDE mv=1 loco=5 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original IDLE FRONT mv=1 loco=0 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original IDLE FRONT mv=1 loco=1 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original IDLE FRONT mv=1 loco=2 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original IDLE FRONT mv=1 loco=5 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original WALK BACK mv=1 loco=0 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original WALK BACK mv=1 loco=1 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original WALK BACK mv=1 loco=2 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original WALK BACK mv=1 loco=5 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original WALK SIDE mv=1 loco=0 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original WALK SIDE mv=1 loco=1 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original WALK SIDE mv=1 loco=2 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original WALK SIDE mv=1 loco=5 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original WALK FRONT mv=1 loco=0 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original WALK FRONT mv=1 loco=1 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original WALK FRONT mv=1 loco=2 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original WALK FRONT mv=1 loco=5 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original DRIBBLE BACK mv=1 loco=0 > basket_kyra_original_05 4401dc47 444e3db8 442ce826
1 kyra_original DRIBBLE BACK mv=1 loco=1 > basket_kyra_original_06 43fd0000 44509380 443205f4
1 kyra_original DRIBBLE BACK mv=1 loco=2 > basket_kyra_original_05 4401dc47 444e3db8 442ce826
1 kyra_original DRIBBLE BACK mv=1 loco=5 > basket_kyra_original_06 43fd0000 44509380 443205f4
1 kyra_original DRIBBLE SIDE mv=1 loco=0 > basket_kyra_original_07 43fd0000 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE mv=1 loco=1 > basket_kyra_original_08 4401dc48 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE mv=1 loco=2 > basket_kyra_original_07 43fd0000 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE mv=1 loco=5 > basket_kyra_original_08 4401dc48 44510a8e 44327d03
1 kyra_original DRIBBLE FRONT mv=1 loco=0 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 loco=1 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 loco=2 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 loco=5 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original WAITING BACK mv=1 loco=0 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original WAITING BACK mv=1 loco=1 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original WAITING BACK mv=1 loco=2 > basket_kyra_original_05 4406b88e 44481db8 442ce826
1 kyra_original WAITING BACK mv=1 loco=5 > basket_kyra_original_06 43fa0000 444a7380 443205f4
1 kyra_original WAITING SIDE mv=1 loco=0 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original WAITING SIDE mv=1 loco=1 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original WAITING SIDE mv=1 loco=2 > basket_kyra_original_07 43fa0000 444aea8e 44327d03
1 kyra_original WAITING SIDE mv=1 loco=5 > basket_kyra_original_08 4406b88f 444aea8e 44327d03
1 kyra_original WAITING FRONT mv=1 loco=0 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original WAITING FRONT mv=1 loco=1 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original WAITING FRONT mv=1 loco=2 > basket_kyra_original_03 43fa0000 44481db8 442ce826
1 kyra_original WAITING FRONT mv=1 loco=5 > basket_kyra_original_04 43fa0000 4447e23e 442cacac
1 kyra_original DRIBBLE BACK mv=1 fast=1 loco=1 > basket_kyra_original_06 44002000 44509380 443205f4
1 kyra_original DRIBBLE BACK hs=-1 mv=1 fast=1 loco=1 > basket_kyra_original_06 43f3c000 44509380 443205f4
1 kyra_original DRIBBLE BACK hs=0 mv=1 fast=1 loco=1 > basket_kyra_original_06 44002000 44509380 443205f4
1 kyra_original DRIBBLE BACK hs=-0.3 mv=1 fast=1 loco=1 > basket_kyra_original_06 43f3c000 44509380 443205f4
1 kyra_original DRIBBLE SIDE mv=1 fast=1 loco=1 > basket_kyra_original_08 44037c48 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE hs=-1 mv=1 fast=1 loco=1 > basket_kyra_original_08 43ed0771 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE hs=0 mv=1 fast=1 loco=1 > basket_kyra_original_08 44037c48 44510a8e 44327d03
1 kyra_original DRIBBLE SIDE hs=-0.3 mv=1 fast=1 loco=1 > basket_kyra_original_08 43ed0771 44510a8e 44327d03
1 kyra_original DRIBBLE FRONT mv=1 fast=1 loco=1 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT hs=-1 mv=1 fast=1 loco=1 > basket_kyra_original_04 43f3c000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT hs=0 mv=1 fast=1 loco=1 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT hs=-0.3 mv=1 fast=1 loco=1 > basket_kyra_original_04 43f3c000 444e023e 442cacac
1 kyra_original DRIBBLE BACK ph=0 > basket_kyra_original_01 44000000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=0.5 > basket_kyra_original_01 43fa0000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=0.75 > basket_kyra_original_01 43f70000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=1 > basket_kyra_original_01 43f40000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=1.3 > basket_kyra_original_01 43f40000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=-0.2 > basket_kyra_original_01 44000000 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=0.499 > basket_kyra_original_01 43fa0312 444ef06a 442d9ad8
1 kyra_original DRIBBLE BACK ph=0.501 > basket_kyra_original_01 43f9fcee 444ef06a 442d9ad8
1 kyra_original DRIBBLE SIDE ph=0 > basket_kyra_original_02 4406b88e 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=0.5 > basket_kyra_original_02 43fa0000 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=0.75 > basket_kyra_original_02 43f04772 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=1 > basket_kyra_original_02 43e68ee4 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=1.3 > basket_kyra_original_02 43e68ee4 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=-0.2 > basket_kyra_original_02 4406b88e 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=0.499 > basket_kyra_original_02 43fa09f4 444e3db8 442ce826
1 kyra_original DRIBBLE SIDE ph=0.501 > basket_kyra_original_02 43f9f60c 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT ph=0 > basket_kyra_original_00 44000000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=0.5 > basket_kyra_original_00 43fa0000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=0.75 > basket_kyra_original_00 43f70000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=1 > basket_kyra_original_00 43f40000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=1.3 > basket_kyra_original_00 43f40000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=-0.2 > basket_kyra_original_00 44000000 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=0.499 > basket_kyra_original_00 43fa0312 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT ph=0.501 > basket_kyra_original_00 43f9fcee 444eb4ce 442d5f3c
1 kyra_original DRIBBLE FRONT b=0 ph=0.75 > basket_kyra_original_00 43f70000 444894ce 442d5f3c
1 kyra_original DRIBBLE SIDE b=0 mv=1 fast=1 loco=0 > basket_kyra_original_07 44000000 444aea8e 44327d03
1 kyra_original DRIBBLE FRONT b=49 ph=0.75 > basket_kyra_original_00 43f70000 4454d4ce 442d5f3c
1 kyra_original DRIBBLE SIDE b=49 mv=1 fast=1 loco=0 > basket_kyra_original_07 44004000 44572a8e 44327d03
1 kyra_original DRIBBLE FRONT b=60 ph=0.75 > basket_kyra_original_00 43f70000 445794ce 442d5f3c
1 kyra_original DRIBBLE SIDE b=60 mv=1 fast=1 loco=0 > basket_kyra_original_07 44004000 4459ea8e 44327d03
1 kyra_original DRIBBLE FRONT b=-5 ph=0.75 > basket_kyra_original_00 43f70000 444894ce 442d5f3c
1 kyra_original DRIBBLE SIDE b=-5 mv=1 fast=1 loco=0 > basket_kyra_original_07 44000000 444aea8e 44327d03
1 kyra_original DRIBBLE FRONT b=12.3 ph=0.75 > basket_kyra_original_00 43f70000 444ba801 442d5f3c
1 kyra_original DRIBBLE SIDE b=12.3 mv=1 fast=1 loco=0 > basket_kyra_original_07 44001011 444dfdc1 44327d03
1 kyra_original IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 > basket_kyra_original_33 44000000 4456c000 44450000
1 kyra_original IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_original_33 43f40000 4456c000 44450000
1 kyra_original IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 > basket_kyra_original_34 44000000 4456c000 44450000
1 kyra_original IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_original_34 43f40000 4456c000 44450000
1 kyra_original IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 > basket_kyra_original_35 44000000 4456c000 44450000
1 kyra_original IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 mir=1 > basket_kyra_original_35 43f40000 4456c000 44450000
1 kyra_original IDLE FRONT style=BOT shot=GRANNY > basket_kyra_original_00 4401cccd 44596000 44450000
1 kyra_original IDLE FRONT style=BOT shot=GRANNY mir=1 > basket_kyra_original_00 4401cccd 44596000 44450000
1 kyra_original SHOT_SET FRONT style=BOT shot=GRANNY > basket_kyra_original_12 4401cccd 44596000 44450000
1 kyra_original SHOT_SET FRONT style=BOT shot=GRANNY mir=1 > basket_kyra_original_12 4401cccd 44596000 44450000
1 kyra_original DUNK BACK > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=0 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=1 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=2 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=3 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=4 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=5 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=6 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=7 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=8 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=9 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK BACK act=10 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=0 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=1 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=2 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=3 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=4 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=5 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=6 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=7 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=8 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=9 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK SIDE act=10 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=0 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=1 > basket_kyra_original_22 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=2 > basket_kyra_original_23 4406b88e 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=3 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=4 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=5 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=6 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=7 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=8 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=9 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original DUNK FRONT act=10 > basket_kyra_original_21 43fa0000 4432a7e8 442fb2a0
1 kyra_original SHOT_SET SIDE mir=1 vs=0.5 > basket_kyra_original_14 43e97972 4435ed47 443323c0
1 kyra_original IDLE FRONT vs=0.5 > basket_kyra_original_00 43fa0000 444c3e7b 44351dbf
1 kyra_original SHOT_SET SIDE mir=1 vs=1.1 > basket_kyra_original_14 43e49d2a 4429421f 4425a6bc
1 kyra_original IDLE FRONT vs=1.1 > basket_kyra_original_00 43fa0000 444623af 4428358e
1 kyra_original SHOT_SET SIDE mir=1 vs=2 > basket_kyra_original_14 43e1b298 4421a83b 441d8eed
1 kyra_original IDLE FRONT vs=2 > basket_kyra_original_00 43fa0000 44427a00 4420770a
1 kyra_original SHOT_SET SIDE mir=1 vs=0.9 > basket_kyra_original_14 43e88098 443364a6 44307126
1 kyra_original IDLE FRONT vs=0.9 > basket_kyra_original_00 43fa0000 444b05ec 443288e9
1 kyra_original DRIBBLE FRONT mv=1 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 fast=1 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 up=204 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=204 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 up=205 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=205 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 up=249 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=249 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 up=250 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=250 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 up=409 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=409 > basket_kyra_original_04 44002000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 up=410 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=410 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 up=499 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=499 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 up=500 > basket_kyra_original_03 43fd0000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=500 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 kyra_original DRIBBLE FRONT mv=1 up=123456789 > basket_kyra_original_04 43fd0000 444e023e 442cacac
1 kyra_original DRIBBLE FRONT mv=1 fast=1 up=123456789 > basket_kyra_original_03 44002000 444e3db8 442ce826
1 - IDLE BACK mir=1 > - 4401cccd 44596000 44450000
1 - IDLE SIDE mir=1 > - 4401cccd 44596000 44450000
1 - IDLE FRONT mir=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mir=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mir=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mir=1 > - 4401cccd 44596000 44450000
1 - SHOT_SET BACK mir=1 > - 4401cccd 44596000 44450000
1 - SHOT_SET SIDE mir=1 > - 4401cccd 44596000 44450000
1 - SHOT_SET FRONT mir=1 > - 4401cccd 44596000 44450000
1 - STEAL BACK mir=1 > - 4401cccd 44596000 44450000
1 - STEAL SIDE mir=1 > - 4401cccd 44596000 44450000
1 - STEAL FRONT mir=1 > - 4401cccd 44596000 44450000
1 - DUNK BACK mir=1 > - 4401cccd 44596000 44450000
1 - DUNK SIDE mir=1 > - 4401cccd 44596000 44450000
1 - DUNK FRONT mir=1 > - 4401cccd 44596000 44450000
1 - RELEASE BACK mir=1 > - 4401cccd 44596000 44450000
1 - RELEASE SIDE mir=1 > - 4401cccd 44596000 44450000
1 - RELEASE FRONT mir=1 > - 4401cccd 44596000 44450000
1 - IDLE BACK hs=-1 > - 4401cccd 44596000 44450000
1 - IDLE SIDE hs=-1 > - 4401cccd 44596000 44450000
1 - IDLE FRONT hs=-1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK hs=-1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE hs=-1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT hs=-1 > - 4401cccd 44596000 44450000
1 - SHOT_LOW BACK hs=-1 > - 4401cccd 44596000 44450000
1 - SHOT_LOW SIDE hs=-1 > - 4401cccd 44596000 44450000
1 - SHOT_LOW FRONT hs=-1 > - 4401cccd 44596000 44450000
1 - IDLE BACK mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - IDLE BACK mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - IDLE BACK mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - IDLE BACK mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - IDLE SIDE mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - IDLE SIDE mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - IDLE SIDE mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - IDLE SIDE mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - IDLE FRONT mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - IDLE FRONT mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - IDLE FRONT mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - IDLE FRONT mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WALK BACK mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WALK BACK mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WALK BACK mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WALK BACK mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WALK SIDE mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WALK SIDE mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WALK SIDE mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WALK SIDE mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WALK FRONT mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WALK FRONT mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WALK FRONT mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WALK FRONT mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WAITING BACK mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WAITING BACK mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WAITING BACK mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WAITING BACK mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WAITING SIDE mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WAITING SIDE mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WAITING SIDE mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WAITING SIDE mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - WAITING FRONT mv=1 loco=0 > - 4401cccd 44596000 44450000
1 - WAITING FRONT mv=1 loco=1 > - 4401cccd 44596000 44450000
1 - WAITING FRONT mv=1 loco=2 > - 4401cccd 44596000 44450000
1 - WAITING FRONT mv=1 loco=5 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK hs=-1 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK hs=0 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK hs=-0.3 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE hs=-1 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE hs=0 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE hs=-0.3 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT hs=-1 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT hs=0 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT hs=-0.3 mv=1 fast=1 loco=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=0.5 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=0.75 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=1.3 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=-0.2 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=0.499 > - 4401cccd 44596000 44450000
1 - DRIBBLE BACK ph=0.501 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=0.5 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=0.75 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=1.3 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=-0.2 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=0.499 > - 4401cccd 44596000 44450000
1 - DRIBBLE SIDE ph=0.501 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=0 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=0.5 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=0.75 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=1.3 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=-0.2 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=0.499 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT ph=0.501 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT b=0 ph=0.75 > - 4401cccd 44534000 44450000
1 - DRIBBLE SIDE b=0 mv=1 fast=1 loco=0 > - 4401cccd 44534000 44450000
1 - DRIBBLE FRONT b=49 ph=0.75 > - 4401cccd 445f8000 44450000
1 - DRIBBLE SIDE b=49 mv=1 fast=1 loco=0 > - 4401cccd 445f8000 44450000
1 - DRIBBLE FRONT b=60 ph=0.75 > - 4401cccd 44624000 44450000
1 - DRIBBLE SIDE b=60 mv=1 fast=1 loco=0 > - 4401cccd 44624000 44450000
1 - DRIBBLE FRONT b=-5 ph=0.75 > - 4401cccd 44520000 44450000
1 - DRIBBLE SIDE b=-5 mv=1 fast=1 loco=0 > - 4401cccd 44520000 44450000
1 - DRIBBLE FRONT b=12.3 ph=0.75 > - 4401cccd 44565333 44450000
1 - DRIBBLE SIDE b=12.3 mv=1 fast=1 loco=0 > - 4401cccd 44565333 44450000
1 - IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 > - 44000000 4456c000 44450000
1 - IDLE BACK pose=WINNER aim=-1 pull=1.4 b=5 mir=1 > - 44000000 4456c000 44450000
1 - IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 > - 44000000 4456c000 44450000
1 - IDLE BACK pose=LOSER aim=-1 pull=1.4 b=5 mir=1 > - 44000000 4456c000 44450000
1 - IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 > - 44000000 4456c000 44450000
1 - IDLE BACK pose=SPECTATOR aim=-1 pull=1.4 b=5 mir=1 > - 44000000 4456c000 44450000
1 - IDLE FRONT style=BOT shot=GRANNY > - 4401cccd 44596000 44450000
1 - IDLE FRONT style=BOT shot=GRANNY mir=1 > - 4401cccd 44596000 44450000
1 - SHOT_SET FRONT style=BOT shot=GRANNY > - 4401cccd 44596000 44450000
1 - SHOT_SET FRONT style=BOT shot=GRANNY mir=1 > - 4401cccd 44596000 44450000
1 - DUNK BACK > - 4401cccd 44596000 44450000
1 - DUNK BACK act=0 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=1 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=2 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=3 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=4 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=5 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=6 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=7 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=8 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=9 > - 4401cccd 44596000 44450000
1 - DUNK BACK act=10 > - 4401cccd 44596000 44450000
1 - DUNK SIDE > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=0 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=1 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=2 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=3 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=4 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=5 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=6 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=7 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=8 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=9 > - 4401cccd 44596000 44450000
1 - DUNK SIDE act=10 > - 4401cccd 44596000 44450000
1 - DUNK FRONT > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=0 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=1 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=2 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=3 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=4 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=5 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=6 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=7 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=8 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=9 > - 4401cccd 44596000 44450000
1 - DUNK FRONT act=10 > - 4401cccd 44596000 44450000
1 - SHOT_SET SIDE mir=1 vs=0.5 > - 4401cccd 44596000 44493333
1 - IDLE FRONT vs=0.5 > - 4401cccd 44596000 44493333
1 - SHOT_SET SIDE mir=1 vs=1.1 > - 4401cccd 44596000 44423333
1 - IDLE FRONT vs=1.1 > - 4401cccd 44596000 44423333
1 - SHOT_SET SIDE mir=1 vs=2 > - 4401cccd 44596000 443e0000
1 - IDLE FRONT vs=2 > - 4401cccd 44596000 443e0000
1 - SHOT_SET SIDE mir=1 vs=0.9 > - 4401cccd 44596000 4447cccd
1 - IDLE FRONT vs=0.9 > - 4401cccd 44596000 4447cccd
1 - DRIBBLE FRONT mv=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=204 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=204 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=205 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=205 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=249 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=249 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=250 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=250 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=409 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=409 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=410 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=410 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=499 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=499 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=500 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=500 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 up=123456789 > - 4401cccd 44596000 44450000
1 - DRIBBLE FRONT mv=1 fast=1 up=123456789 > - 4401cccd 44596000 44450000
2 woman_dark IDLE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 444bd28f 44c91ccd 44aa8852
2 woman_dark IDLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 4440f1a1 44c89000 44aa5000
2 woman_dark IDLE FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 444e21eb 44c9c5c2 44ae9a3d
2 woman_dark WAITING BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 444bd28f 44c91ccd 44aa8852
2 woman_dark WAITING SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 4440f1a1 44c89000 44aa5000
2 woman_dark WAITING FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 444e21eb 44c9c5c2 44ae9a3d
2 woman_dark WALK BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 444bd28f 44c91ccd 44aa8852
2 woman_dark WALK SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 4440f1a1 44c89000 44aa5000
2 woman_dark WALK FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 444e21eb 44c9c5c2 44ae9a3d
2 woman_dark DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 44415148 44cc2ccd 44aa8852
2 woman_dark DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 443be0d0 44cba000 44aa5000
2 woman_dark DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 444278f6 44ccd5c2 44ae9a3d
2 woman_dark STEAL BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_back 4440699a 44d6a000 44b05ccd
2 woman_dark STEAL SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_side 4440699a 44d6a000 44b73ccd
2 woman_dark STEAL FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_front 4440699a 44d6a000 44bfbc29
2 woman_dark BLOCK BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_block_back 4440699a 44d6a000 44a97ccd
2 woman_dark BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_block_side 4440699a 44d6a000 44a81ccd
2 woman_dark BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_block_front 4440699a 44d6a000 44b29000
2 woman_dark REBOUND BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_back 4440699a 44d6a000 44b2d666
2 woman_dark REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_side 4440699a 44d6a000 44a8a99a
2 woman_dark REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_front 4440699a 44d6a000 44aefccd
2 woman_dark DUNK BACK x=731.25 y=1802.5 > woman_dark_dunk_back_one_hand 44559955 44aafcab 44a7d000
2 woman_dark DUNK SIDE x=731.25 y=1802.5 > woman_dark_dunk_side_two_hand_gather 444e5aaa 44ac0cab 44a8d000
2 woman_dark DUNK FRONT x=731.25 y=1802.5 > woman_dark_dunk_front_two_hand_power 444662aa 44aa8200 44a7d000
2 woman_dark SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_back_low 44370d36 44c47afd 44af899a
2 woman_dark SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_side_low 444de30c 44c6299a 44af899a
2 woman_dark SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_front_low 4436da60 44c70c00 44af899a
2 woman_dark SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_back_mid 4436b8e6 44b6358f 44af899a
2 woman_dark SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_side_mid 444c7744 44bb6a34 44ae299a
2 woman_dark SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_front_mid 4436dab5 44b87ce8 44ad9ccd
2 woman_dark SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_back_set 4436c469 44ad1e7c 44aa5000
2 woman_dark SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_side_set 44239b9c 44aff7e7 44aa5000
2 woman_dark SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_front_set 44373cfa 44ad5a68 44aa5000
2 woman_dark RELEASE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_after_throw 4440699a 44d6a000 44a87148
2 woman_dark RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_17 44418803 44a59a66 44a37000
2 woman_dark RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_15 442c9a66 44a59a66 44a37000
2 kyra IDLE BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44c74778 44a9455a
2 kyra IDLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 444c2552 44c6a77a 44a8a55c
2 kyra IDLE FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44c6dcce 44a8dab0
2 kyra WAITING BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44c74778 44a9455a
2 kyra WAITING SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 444c2552 44c6a77a 44a8a55c
2 kyra WAITING FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44c6dcce 44a8dab0
2 kyra WALK BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44c74778 44a9455a
2 kyra WALK SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 444c2552 44c6a77a 44a8a55c
2 kyra WALK FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44c6dcce 44a8dab0
2 kyra DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_22 4439d000 44d1821b 44b6654c
2 kyra DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_23 44417aac 44d07778 44b55aa9
2 kyra DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_21 4439d000 44d14cd3 44b63004
2 kyra STEAL BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_19 4436d000 44cea781 44b69ab2
2 kyra STEAL SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_20 444c2557 44ce076d 44b5fa9e
2 kyra STEAL FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_18 4436d000 44ce3cd3 44b63004
2 kyra BLOCK BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_04 443a4538 44a2be97 44a02333
2 kyra BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_05 4439fb11 44a2be97 44a02333
2 kyra BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_03 443a3752 44a2be97 44a02333
2 kyra REBOUND BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_07 443a3752 44a2be97 44a02333
2 kyra REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_08 4439c816 44a2be97 44a02333
2 kyra REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_06 443a32ae 44a2be97 44a02333
2 kyra DUNK BACK x=731.25 y=1802.5 > basket_kyra_22 44415119 44ad719a 44ab9000
2 kyra DUNK SIDE x=731.25 y=1802.5 > basket_kyra_23 444463d8 44ad719a 44ab9000
2 kyra DUNK FRONT x=731.25 y=1802.5 > basket_kyra_21 4428f067 44ad719a 44ab9000
2 kyra SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_10 4436d000 44cd1d64 44b05ab4
2 kyra SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_11 444c2559 44cb3d58 44ae7aa8
2 kyra SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_09 4436d000 44cb3d58 44ae7aa8
2 kyra SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_13 4436d000 44bc788b 44a91001
2 kyra SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_14 444c2556 44bbd887 44a86ffd
2 kyra SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_12 4436d000 44bc0dde 44a8a554
2 kyra SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_16 4436d000 44ac7cce 44a91001
2 kyra SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_17 44217aaa 44aba773 44a83aa6
2 kyra SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_15 4436d000 44ac7cce 44a91001
2 kyra RELEASE BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_16 4441b762 44a59a66 44a37000
2 kyra RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_17 443f7776 44a59a66 44a37000
2 kyra RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_15 44290dff 44a59a66 44a37000
2 - IDLE BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - IDLE SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - IDLE FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WAITING BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WAITING SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WAITING FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WALK BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WALK SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - WALK FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - STEAL BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - STEAL SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - STEAL FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - BLOCK BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - REBOUND BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - DUNK BACK x=731.25 y=1802.5 > - 4440699a 44d6a000 44c55000
2 - DUNK SIDE x=731.25 y=1802.5 > - 4440699a 44d6a000 44c55000
2 - DUNK FRONT x=731.25 y=1802.5 > - 4440699a 44d6a000 44c55000
2 - SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - RELEASE BACK x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
2 - RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > - 4440699a 44d6a000 44c28333
3 woman_dark IDLE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 445653d6 44bd0332 448f247a
3 woman_dark IDLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 44460271 44bc3000 448ed000
3 woman_dark IDLE FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 4459cae2 44be00a4 44953f5c
3 woman_dark WAITING BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 445653d6 44bd0332 448f247a
3 woman_dark WAITING SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 44460271 44bc3000 448ed000
3 woman_dark WAITING FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 4459cae2 44be00a4 44953f5c
3 woman_dark WALK BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 445653d6 44bd0332 448f247a
3 woman_dark WALK SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 44460271 44bc3000 448ed000
3 woman_dark WALK FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 4459cae2 44be00a4 44953f5c
3 woman_dark DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_standing 444691eb 44c01332 448f247a
3 woman_dark DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_02 443e6938 44bf4000 448ed000
3 woman_dark DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_front_defense 44484d71 44c110a4 44953f5c
3 woman_dark STEAL BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_back 44453666 44cfc000 4497e333
3 woman_dark STEAL SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_side 44453666 44cfc000 44a23333
3 woman_dark STEAL FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_steal_front 44453666 44cfc000 44aef23d
3 woman_dark BLOCK BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_block_back 44453666 44cfc000 448d9333
3 woman_dark BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_block_side 44453666 44cfc000 448b8333
3 woman_dark BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_block_front 44453666 44cfc000 449b3000
3 woman_dark REBOUND BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_back 44453666 44cfc000 449b999a
3 woman_dark REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_side 44453666 44cfc000 448c5666
3 woman_dark REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_rebound_front 44453666 44cfc000 4495d333
3 woman_dark DUNK BACK x=731.25 y=1802.5 > woman_dark_dunk_back_one_hand 4464fe00 448fd300 448b1000
3 woman_dark DUNK SIDE x=731.25 y=1802.5 > woman_dark_dunk_side_two_hand_gather 445a2000 44916b00 448c9000
3 woman_dark DUNK FRONT x=731.25 y=1802.5 > woman_dark_dunk_front_two_hand_power 444e2c00 448f1b00 448b1000
3 woman_dark SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_back_low 44372bd2 44b6107a 4496a666
3 woman_dark SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_side_low 44596c92 44b89666 4496a666
3 woman_dark SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_front_low 4436df91 44b9e9ff 4496a666
3 woman_dark SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_back_mid 4436ad58 44a0a856 4496a666
3 woman_dark SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_side_mid 44574ae6 44a8774d 44949666
3 woman_dark SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > woman_dark_shot_front_mid 4436e010 44a4135c 4493c334
3 woman_dark SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_back_set 4436be9e 449305ba 448ed000
3 woman_dark SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_side_set 441a016a 44974bdb 448ed000
3 woman_dark SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > woman_dark_shot_front_set 44377377 44935f9c 448ed000
3 woman_dark RELEASE BACK x=731.25 y=1802.5 vs=1.1 > woman_dark_back_after_throw 44453666 44cfc000 448c01ec
3 woman_dark RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_17 4446e405 4487bf9a 44848000
3 woman_dark RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > basket_woman_dark_15 44277f9a 4487bf9a 44848000
3 kyra IDLE BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44ba4334 448d4008
3 kyra IDLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 4456cffb 44b95336 448c500a
3 kyra IDLE FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44b9a335 448ca009
3 kyra WAITING BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44ba4334 448d4008
3 kyra WAITING SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 4456cffb 44b95336 448c500a
3 kyra WAITING FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44b9a335 448ca009
3 kyra WALK BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_01 4436d000 44ba4334 448d4008
3 kyra WALK SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_02 4456cffb 44b95336 448c500a
3 kyra WALK FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_00 4436d000 44b9a335 448ca009
3 kyra DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_22 443b5000 44c81328 44a0eff2
3 kyra DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_23 4446d001 44c68333 449f5ffd
3 kyra DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_21 443b5000 44c7c33c 44a0a006
3 kyra STEAL BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_19 4436d000 44c55341 44a1400b
3 kyra STEAL SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_20 4456d002 44c46323 44a04fed
3 kyra STEAL FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_18 4436d000 44c4b33c 44a0a006
3 kyra BLOCK BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_04 443bffd5 448375e3 447f1999
3 kyra BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_05 443b909a 448375e3 447f1999
3 kyra BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_03 443beafa 448375e3 447f1999
3 kyra REBOUND BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_07 443beafa 448375e3 447f1999
3 kyra REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_08 443b4420 448375e3 447f1999
3 kyra REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_extra_06 443be406 448375e3 447f1999
3 kyra DUNK BACK x=731.25 y=1802.5 > basket_kyra_22 444691a6 44938266 4490b000
3 kyra DUNK SIDE x=731.25 y=1802.5 > basket_kyra_23 444b2dc5 44938266 4490b000
3 kyra DUNK FRONT x=731.25 y=1802.5 > basket_kyra_21 4422009a 44938266 4490b000
3 kyra SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_10 4436d000 44c30414 4497e00d
3 kyra SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_11 4456d006 44c03403 44950ffc
3 kyra SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_09 4436d000 44c03403 44950ffc
3 kyra SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_13 4436d000 44aa0cd1 448cf002
3 kyra SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_14 4456d002 44a91cca 448bfffb
3 kyra SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > basket_gaya_ground_12 4436d000 44a96ccd 448c4ffe
3 kyra SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_16 4436d000 44921336 448cf002
3 kyra SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_17 4416cffe 4490d32d 448baff9
3 kyra SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > basket_gaya_ground_15 4436d000 44921336 448cf002
3 kyra RELEASE BACK x=731.25 y=1802.5 vs=1.1 > basket_kyra_16 44472b14 4487bf9a 44848000
3 kyra RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > basket_kyra_17 4443cb31 4487bf9a 44848000
3 kyra RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > basket_kyra_15 44222cfe 4487bf9a 44848000
3 - IDLE BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - IDLE SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - IDLE FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WAITING BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WAITING SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WAITING FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WALK BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WALK SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - WALK FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - DRIBBLE BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - DRIBBLE SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - DRIBBLE FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - STEAL BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - STEAL SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - STEAL FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - BLOCK BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - BLOCK SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - BLOCK FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - REBOUND BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - REBOUND SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - REBOUND FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - DUNK BACK x=731.25 y=1802.5 > - 44453666 44cfc000 44b75000
3 - DUNK SIDE x=731.25 y=1802.5 > - 44453666 44cfc000 44b75000
3 - DUNK FRONT x=731.25 y=1802.5 > - 44453666 44cfc000 44b75000
3 - SHOT_LOW BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_LOW SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_LOW FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_MID BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_MID SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_MID FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_SET BACK x=731.25 y=1802.5 mir=1 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_SET SIDE x=731.25 y=1802.5 mir=1 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - SHOT_SET FRONT x=731.25 y=1802.5 mir=1 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - RELEASE BACK x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - RELEASE SIDE x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
3 - RELEASE FRONT x=731.25 y=1802.5 vs=1.1 > - 44453666 44cfc000 44b31ccd
"""

/// The 606 drawables referenced by the catalog files: `name width height` (drawable-nodpi pixels).
private let visualsDrawables = """
woman_dark_back_standing 237 498
woman_dark_front_defense 264 461
woman_dark_shot_back_low 588 1224
woman_dark_shot_back_mid 558 1231
woman_dark_shot_back_set 483 1215
woman_dark_back_after_throw 186 517
woman_dark_shot_side_low 563 1221
woman_dark_shot_side_mid 730 1513
woman_dark_shot_side_set 611 1235
woman_dark_front_throw 174 488
woman_dark_shot_front_low 635 1228
woman_dark_shot_front_mid 527 1236
woman_dark_shot_front_set 476 1230
woman_dark_steal_back 272 355
woman_dark_steal_side 356 306
woman_dark_steal_front 225 220
woman_dark_block_back 220 405
woman_dark_block_side 221 416
woman_dark_block_front 198 340
woman_dark_rebound_back 126 337
woman_dark_rebound_side 207 412
woman_dark_rebound_front 151 366
woman_dark_dunk_back_one_hand 720 960
woman_dark_dunk_back_two_hand_power 720 960
woman_dark_dunk_back_two_hand_hang 720 960
woman_dark_dunk_front_two_hand_power 720 960
woman_dark_dunk_front_two_hand_hang 720 960
woman_dark_dunk_front_statue 720 960
woman_dark_dunk_side_two_hand_gather 720 960
woman_dark_dunk_side_reverse_gather 720 960
woman_dark_dunk_side_two_hand_hang 720 960
woman_dark_dunk_side_statue 720 960
woman_dark_front_celebrate 220 390
woman_dark_front_sitting_sad 182 287
woman_dark_front_sitting 150 361
nova_idle_back 381 900
nova_idle_front 627 900
nova_shot_back_low 360 900
nova_shot_back_mid 366 900
nova_shot_back_set 368 900
nova_release_back 455 900
nova_shot_side_low 458 900
nova_shot_side_mid 436 900
nova_shot_side_set 422 900
nova_release_side 421 900
nova_shot_front_low 396 900
nova_shot_front_mid 374 900
nova_shot_front_set 368 900
nova_release_front 421 900
nova_steal_back 900 762
nova_steal_side 900 607
nova_steal_front 900 713
nova_block_back 578 900
nova_block_side 673 900
nova_block_front 502 900
nova_rebound_back 367 900
nova_rebound_side 414 900
nova_rebound_front 386 900
nova_dunk_back_one_hand 554 899
nova_dunk_back_two_hand_power 549 900
nova_dunk_back_two_hand_hang 473 900
nova_dunk_front_two_hand_power 442 900
nova_dunk_front_two_hand_hang 411 900
nova_dunk_front_statue 673 900
nova_dunk_side_two_hand_gather 576 900
nova_dunk_side_reverse_gather 575 900
nova_dunk_side_two_hand_hang 530 900
nova_dunk_side_statue 527 900
nova_winner 483 900
nova_loser 552 900
nova_spectator 386 900
coach_67_back_standing 252 477
coach_67_front_defense 329 431
coach_67_shot_back_low 327 409
coach_67_shot_back_mid 266 468
coach_67_shot_back_set 255 510
coach_67_back_after_throw 177 525
coach_67_shot_side_low 240 482
coach_67_shot_side_mid 274 493
coach_67_shot_side_set 261 492
coach_67_front_throw 211 539
coach_67_shot_front_low 326 424
coach_67_shot_front_mid 262 489
coach_67_shot_front_set 260 531
coach_67_steal_back 365 465
coach_67_steal_side 413 367
coach_67_steal_front 324 351
coach_67_block_back 263 500
coach_67_block_side 289 505
coach_67_block_front 290 459
coach_67_rebound_back 199 497
coach_67_rebound_side 226 519
coach_67_rebound_front 232 510
coach_67_dunk_back_one_hand 291 508
coach_67_dunk_back_two_hand_power 240 512
coach_67_dunk_back_two_hand_hang 306 451
coach_67_dunk_front_two_hand_power 239 464
coach_67_dunk_front_two_hand_hang 240 431
coach_67_dunk_front_statue 310 523
coach_67_dunk_side_two_hand_gather 291 491
coach_67_dunk_side_reverse_gather 287 505
coach_67_dunk_side_two_hand_hang 303 488
coach_67_dunk_side_statue 333 522
coach_67_front_celebrate 283 462
coach_67_front_sitting_sad 228 432
coach_67_front_sitting 235 396
zephyr_back_standing 351 322
zephyr_front_defense 346 373
zephyr_shot_back_low 345 366
zephyr_shot_back_mid 333 326
zephyr_shot_back_set 336 372
zephyr_back_after_throw 333 342
zephyr_shot_side_low 268 340
zephyr_shot_side_mid 263 360
zephyr_shot_side_set 287 363
zephyr_front_throw 334 338
zephyr_shot_front_low 357 350
zephyr_shot_front_mid 299 408
zephyr_shot_front_set 337 334
zephyr_steal_back 342 343
zephyr_steal_side 392 382
zephyr_steal_front 395 374
zephyr_block_back 305 397
zephyr_block_side 288 422
zephyr_block_front 357 303
zephyr_rebound_back 312 383
zephyr_rebound_side 325 385
zephyr_rebound_front 260 361
zephyr_dunk_back_one_hand 269 396
zephyr_dunk_back_two_hand_power 302 352
zephyr_dunk_back_two_hand_hang 340 362
zephyr_dunk_front_two_hand_power 320 329
zephyr_dunk_front_two_hand_hang 282 352
zephyr_dunk_front_statue 347 376
zephyr_dunk_side_two_hand_gather 301 342
zephyr_dunk_side_reverse_gather 319 395
zephyr_dunk_side_two_hand_hang 257 335
zephyr_dunk_side_statue 321 317
zephyr_front_celebrate 303 413
zephyr_front_sitting_sad 286 374
zephyr_front_sitting 313 391
flare_back_standing 220 368
flare_front_defense 289 328
flare_shot_back_low 265 307
flare_shot_back_mid 241 361
flare_shot_back_set 200 348
flare_back_after_throw 197 376
flare_shot_side_low 205 327
flare_shot_side_mid 189 341
flare_shot_side_set 155 349
flare_front_throw 240 375
flare_shot_front_low 275 313
flare_shot_front_mid 249 340
flare_shot_front_set 223 351
flare_steal_back 284 285
flare_steal_side 341 258
flare_steal_front 289 247
flare_block_back 208 355
flare_block_side 226 360
flare_block_front 241 348
flare_rebound_back 138 348
flare_rebound_side 163 341
flare_rebound_front 165 352
flare_dunk_back_one_hand 352 496
flare_dunk_back_two_hand_power 250 483
flare_dunk_back_two_hand_hang 366 476
flare_dunk_front_two_hand_power 249 491
flare_dunk_front_two_hand_hang 235 485
flare_dunk_front_statue 373 490
flare_dunk_side_two_hand_gather 393 604
flare_dunk_side_reverse_gather 375 560
flare_dunk_side_two_hand_hang 338 568
flare_dunk_side_statue 403 614
flare_front_celebrate 436 601
flare_front_sitting_sad 310 513
flare_front_sitting 345 567
character_preview_bob 480 480
character_preview_rooza 480 480
character_preview_nova 512 512
character_preview_unicorn_32 480 480
character_preview_coach_67 512 512
character_preview_kyra 337 480
character_preview_zephyr 512 512
character_preview_flare 289 328
character_preview_ace_23 480 480
character_preview_buddy_23 480 480
basket_buddy_23_00 180 246
basket_buddy_23_01 139 247
basket_buddy_23_02 180 248
basket_buddy_23_03 141 243
basket_buddy_23_04 141 246
basket_buddy_23_05 138 251
basket_buddy_23_06 136 232
basket_buddy_23_07 199 224
basket_buddy_23_08 197 223
basket_buddy_23_09 168 223
basket_buddy_23_10 166 226
basket_buddy_23_11 146 231
basket_buddy_23_12 144 253
basket_buddy_23_13 133 253
basket_buddy_23_14 161 252
basket_buddy_23_15 141 244
basket_buddy_23_16 165 244
basket_buddy_23_17 159 252
basket_buddy_23_18 213 203
basket_buddy_23_19 233 201
basket_buddy_23_20 244 199
basket_buddy_23_21 141 239
basket_buddy_23_22 158 233
basket_buddy_23_23 171 235
basket_ace_23_00 153 259
basket_ace_23_01 140 260
basket_ace_23_02 77 261
basket_ace_23_03 121 263
basket_ace_23_04 119 263
basket_ace_23_05 126 262
basket_ace_23_06 119 236
basket_ace_23_07 170 230
basket_ace_23_08 182 229
basket_ace_23_09 171 222
basket_ace_23_10 166 223
basket_ace_23_11 132 229
basket_ace_23_12 153 259
basket_ace_23_13 138 258
basket_ace_23_14 97 262
basket_ace_23_15 128 248
basket_ace_23_16 127 253
basket_ace_23_17 122 269
basket_ace_23_18 198 202
basket_ace_23_19 220 202
basket_ace_23_20 215 202
basket_ace_23_21 160 249
basket_ace_23_22 145 256
basket_ace_23_23 153 246
basket_rooza_00 129 241
basket_rooza_01 124 245
basket_rooza_02 134 247
basket_rooza_03 116 249
basket_rooza_04 110 250
basket_rooza_05 106 248
basket_rooza_06 109 241
basket_rooza_07 184 236
basket_rooza_08 193 236
basket_rooza_09 158 228
basket_rooza_10 162 224
basket_rooza_11 161 234
basket_rooza_12 130 249
basket_rooza_13 124 249
basket_rooza_14 118 250
basket_rooza_15 140 247
basket_rooza_16 125 244
basket_rooza_17 147 240
basket_rooza_18 195 205
basket_rooza_19 186 207
basket_rooza_20 189 212
basket_rooza_21 141 236
basket_rooza_22 129 248
basket_rooza_23 139 234
basket_unicorn_32_00 185 249
basket_unicorn_32_01 183 249
basket_unicorn_32_02 140 252
basket_unicorn_32_03 157 255
basket_unicorn_32_04 169 251
basket_unicorn_32_05 165 250
basket_unicorn_32_06 164 241
basket_unicorn_32_07 210 227
basket_unicorn_32_08 198 227
basket_unicorn_32_09 197 228
basket_unicorn_32_10 209 231
basket_unicorn_32_11 185 232
basket_unicorn_32_12 171 252
basket_unicorn_32_13 159 253
basket_unicorn_32_14 129 256
basket_unicorn_32_15 158 238
basket_unicorn_32_16 156 277
basket_unicorn_32_17 152 262
basket_unicorn_32_18 229 206
basket_unicorn_32_19 232 199
basket_unicorn_32_20 227 206
basket_unicorn_32_21 167 241
basket_unicorn_32_22 172 226
basket_unicorn_32_23 153 242
basket_kyra_00 162 254
basket_kyra_01 159 253
basket_kyra_02 91 258
basket_kyra_03 149 256
basket_kyra_04 151 255
basket_kyra_05 158 255
basket_kyra_06 156 240
basket_kyra_07 186 235
basket_kyra_08 186 236
basket_kyra_09 156 230
basket_kyra_10 157 238
basket_kyra_11 134 241
basket_kyra_12 143 285
basket_kyra_13 141 287
basket_kyra_14 88 292
basket_kyra_15 142 281
basket_kyra_16 140 286
basket_kyra_17 115 296
basket_kyra_18 236 189
basket_kyra_19 208 194
basket_kyra_20 238 185
basket_kyra_21 149 254
basket_kyra_22 133 245
basket_kyra_23 167 238
basket_bob_00 105 238
basket_bob_01 107 238
basket_bob_02 60 239
basket_bob_03 103 239
basket_bob_04 98 235
basket_bob_05 106 239
basket_bob_06 108 229
basket_bob_07 193 225
basket_bob_08 191 220
basket_bob_09 150 216
basket_bob_10 146 221
basket_bob_11 138 218
basket_bob_12 105 258
basket_bob_13 107 258
basket_bob_14 87 260
basket_bob_15 122 260
basket_bob_16 129 256
basket_bob_17 111 254
basket_bob_18 206 197
basket_bob_19 196 190
basket_bob_20 193 192
basket_bob_21 146 237
basket_bob_22 129 239
basket_bob_23 113 244
basket_woman_dark_00 160 271
basket_woman_dark_01 142 271
basket_woman_dark_02 104 271
basket_woman_dark_03 100 269
basket_woman_dark_04 102 269
basket_woman_dark_05 102 270
basket_woman_dark_06 106 243
basket_woman_dark_07 178 239
basket_woman_dark_08 176 234
basket_woman_dark_09 128 222
basket_woman_dark_10 133 224
basket_woman_dark_11 123 233
basket_woman_dark_12 137 276
basket_woman_dark_13 132 278
basket_woman_dark_14 86 282
basket_woman_dark_15 105 280
basket_woman_dark_16 112 278
basket_woman_dark_17 128 266
basket_woman_dark_18 195 206
basket_woman_dark_19 197 201
basket_woman_dark_20 176 207
basket_woman_dark_21 125 242
basket_woman_dark_22 128 224
basket_woman_dark_23 138 239
basket_nova_00 104 259
basket_nova_01 103 259
basket_nova_02 65 261
basket_nova_03 91 262
basket_nova_04 91 263
basket_nova_05 90 262
basket_nova_06 100 246
basket_nova_07 175 237
basket_nova_08 209 241
basket_nova_09 174 215
basket_nova_10 178 220
basket_nova_11 119 225
basket_nova_12 111 275
basket_nova_13 108 273
basket_nova_14 66 275
basket_nova_15 112 281
basket_nova_16 118 288
basket_nova_17 114 283
basket_nova_18 221 193
basket_nova_19 207 193
basket_nova_20 229 197
basket_nova_21 126 228
basket_nova_22 134 239
basket_nova_23 103 248
basket_coach_67_00 177 255
basket_coach_67_01 181 254
basket_coach_67_02 92 257
basket_coach_67_03 124 261
basket_coach_67_04 126 261
basket_coach_67_05 132 254
basket_coach_67_06 129 239
basket_coach_67_07 208 233
basket_coach_67_08 205 233
basket_coach_67_09 179 218
basket_coach_67_10 194 220
basket_coach_67_11 140 241
basket_coach_67_12 171 267
basket_coach_67_13 164 267
basket_coach_67_14 90 276
basket_coach_67_15 167 239
basket_coach_67_16 160 250
basket_coach_67_17 137 280
basket_coach_67_18 220 207
basket_coach_67_19 224 207
basket_coach_67_20 215 214
basket_coach_67_21 159 265
basket_coach_67_22 146 242
basket_coach_67_23 142 244
basket_zephyr_00 192 243
basket_zephyr_01 193 243
basket_zephyr_02 114 247
basket_zephyr_03 177 247
basket_zephyr_04 178 248
basket_zephyr_05 189 251
basket_zephyr_06 185 238
basket_zephyr_07 216 233
basket_zephyr_08 223 226
basket_zephyr_09 184 216
basket_zephyr_10 198 217
basket_zephyr_11 175 248
basket_zephyr_12 176 272
basket_zephyr_13 176 271
basket_zephyr_14 130 275
basket_zephyr_15 166 276
basket_zephyr_16 176 283
basket_zephyr_17 142 291
basket_zephyr_18 213 203
basket_zephyr_19 228 198
basket_zephyr_20 219 209
basket_zephyr_21 183 257
basket_zephyr_22 170 250
basket_zephyr_23 175 246
basket_flare_00 162 245
basket_flare_01 164 242
basket_flare_02 80 246
basket_flare_03 129 248
basket_flare_04 130 248
basket_flare_05 125 245
basket_flare_06 127 235
basket_flare_07 216 233
basket_flare_08 223 228
basket_flare_09 189 223
basket_flare_10 185 212
basket_flare_11 131 230
basket_flare_12 154 264
basket_flare_13 151 263
basket_flare_14 95 268
basket_flare_15 163 264
basket_flare_16 159 258
basket_flare_17 139 251
basket_flare_18 234 180
basket_flare_19 224 176
basket_flare_20 215 173
basket_flare_21 135 265
basket_flare_22 123 256
basket_flare_23 144 252
basket_buddy_23_extra_00 213 314
basket_buddy_23_extra_01 207 313
basket_buddy_23_extra_02 203 316
basket_buddy_23_extra_03 208 330
basket_buddy_23_extra_04 184 332
basket_buddy_23_extra_05 173 335
basket_buddy_23_extra_06 186 331
basket_buddy_23_extra_07 197 332
basket_buddy_23_extra_08 184 331
basket_buddy_23_extra_09 208 315
basket_buddy_23_extra_10 204 316
basket_buddy_23_extra_11 196 318
basket_ace_23_extra_00 228 339
basket_ace_23_extra_01 231 338
basket_ace_23_extra_02 188 346
basket_ace_23_extra_03 207 340
basket_ace_23_extra_04 185 346
basket_ace_23_extra_05 175 351
basket_ace_23_extra_06 206 340
basket_ace_23_extra_07 200 340
basket_ace_23_extra_08 191 349
basket_ace_23_extra_09 205 338
basket_ace_23_extra_10 184 334
basket_ace_23_extra_11 181 335
basket_rooza_extra_00 233 338
basket_rooza_extra_01 225 333
basket_rooza_extra_02 227 338
basket_rooza_extra_03 263 350
basket_rooza_extra_04 257 321
basket_rooza_extra_05 211 321
basket_rooza_extra_06 197 339
basket_rooza_extra_07 198 339
basket_rooza_extra_08 195 351
basket_rooza_extra_09 220 340
basket_rooza_extra_10 194 345
basket_rooza_extra_11 207 349
basket_unicorn_32_extra_00 263 327
basket_unicorn_32_extra_01 235 321
basket_unicorn_32_extra_02 241 325
basket_unicorn_32_extra_03 252 336
basket_unicorn_32_extra_04 219 328
basket_unicorn_32_extra_05 191 344
basket_unicorn_32_extra_06 189 344
basket_unicorn_32_extra_07 199 335
basket_unicorn_32_extra_08 220 356
basket_unicorn_32_extra_09 240 336
basket_unicorn_32_extra_10 228 344
basket_unicorn_32_extra_11 232 343
basket_kyra_extra_00 222 350
basket_kyra_extra_01 214 352
basket_kyra_extra_02 181 358
basket_kyra_extra_03 188 360
basket_kyra_extra_04 191 360
basket_kyra_extra_05 175 360
basket_kyra_extra_06 187 360
basket_kyra_extra_07 188 360
basket_kyra_extra_08 164 360
basket_kyra_extra_09 214 360
basket_kyra_extra_10 202 360
basket_kyra_extra_11 224 360
basket_bob_extra_00 188 308
basket_bob_extra_01 174 306
basket_bob_extra_02 156 301
basket_bob_extra_03 172 335
basket_bob_extra_04 168 332
basket_bob_extra_05 175 330
basket_bob_extra_06 187 336
basket_bob_extra_07 172 334
basket_bob_extra_08 144 327
basket_bob_extra_09 181 317
basket_bob_extra_10 165 320
basket_bob_extra_11 165 319
basket_kyra_original_00 209 225
basket_kyra_original_01 209 225
basket_kyra_original_02 209 225
basket_kyra_original_03 209 225
basket_kyra_original_04 209 225
basket_kyra_original_05 209 225
basket_kyra_original_06 209 202
basket_kyra_original_07 209 202
basket_kyra_original_08 209 202
basket_kyra_original_09 209 202
basket_kyra_original_10 209 202
basket_kyra_original_11 209 202
basket_kyra_original_12 209 235
basket_kyra_original_13 209 235
basket_kyra_original_14 209 235
basket_kyra_original_15 209 235
basket_kyra_original_16 209 235
basket_kyra_original_17 209 235
basket_kyra_original_18 209 212
basket_kyra_original_19 209 212
basket_kyra_original_20 209 212
basket_kyra_original_21 209 212
basket_kyra_original_22 209 212
basket_kyra_original_23 209 212
basket_kyra_original_24 209 195
basket_kyra_original_25 209 195
basket_kyra_original_26 209 195
basket_kyra_original_27 209 195
basket_kyra_original_28 209 195
basket_kyra_original_29 209 195
basket_kyra_original_30 209 185
basket_kyra_original_31 209 185
basket_kyra_original_32 209 185
basket_kyra_original_33 209 185
basket_kyra_original_34 209 185
basket_kyra_original_35 209 185
basket_gaya_ground_00 256 277
basket_gaya_ground_01 256 277
basket_gaya_ground_02 256 277
basket_gaya_ground_03 256 277
basket_gaya_ground_04 256 277
basket_gaya_ground_05 256 277
basket_gaya_ground_06 256 251
basket_gaya_ground_07 256 251
basket_gaya_ground_08 256 251
basket_gaya_ground_09 256 251
basket_gaya_ground_10 256 251
basket_gaya_ground_11 256 251
basket_gaya_ground_12 256 274
basket_gaya_ground_13 256 274
basket_gaya_ground_14 256 274
basket_gaya_ground_15 256 274
basket_gaya_ground_16 256 274
basket_gaya_ground_17 256 274
basket_gaya_ground_18 256 222
basket_gaya_ground_19 256 222
basket_gaya_ground_20 256 222
basket_gaya_ground_21 256 222
basket_gaya_ground_22 256 222
basket_gaya_ground_23 256 222
basket_comet_ground_00 208 333
basket_comet_ground_01 208 333
basket_comet_ground_02 208 333
basket_comet_ground_03 207 333
basket_comet_ground_04 208 333
basket_comet_ground_05 208 333
basket_comet_ground_06 208 301
basket_comet_ground_07 208 301
basket_comet_ground_08 208 301
basket_comet_ground_09 207 301
basket_comet_ground_10 208 301
basket_comet_ground_11 208 301
basket_comet_ground_12 208 328
basket_comet_ground_13 208 328
basket_comet_ground_14 208 328
basket_comet_ground_15 207 328
basket_comet_ground_16 208 328
basket_comet_ground_17 208 328
basket_comet_ground_18 208 299
basket_comet_ground_19 208 299
basket_comet_ground_20 208 299
basket_comet_ground_21 207 299
basket_comet_ground_22 208 299
basket_comet_ground_23 208 299
"""
