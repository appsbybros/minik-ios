import XCTest
@testable import MinikSplash

/// Ports of Android ReplicaEventsTest.kt and ReplicaTimelineTest.kt.
final class ReplicaTests: XCTestCase {
    func testRepeatsAndReconnectDoNotReplaySounds() {
        func snapshot(_ at: Double) -> Node {
            let actor: Node = ["pickupAt": at, "throwAt": at, "recoveryUntil": at]
            let burst: Node = ["id": String(at), "hit": "p2"]
            return ["actors": ["p1": actor] as Node, "bursts": [burst]]
        }
        let c = ReplicaEvents()
        XCTAssertTrue(c.accept(snapshot(1.0)).isEmpty)
        let events = c.accept(snapshot(2.0))
        XCTAssertEqual(events.map { $0.0 }, ["pickup", "wrong", "hit"])
        for _ in 0..<60 { XCTAssertTrue(c.accept(snapshot(2.0)).isEmpty) }
        c.clear()
        XCTAssertTrue(c.accept(snapshot(3.0)).isEmpty)
    }

    func testFramesInterpolateWithoutPredictingHitsOrLeakingPrivateQuestions() {
        let members = (0...5).map { i in Member("p\(i)", Characters.all[i].id, team: i / 3, bot: false) }
        let source = SplashEngine(members: members)
        let replica = SplashEngine(members: members)
        for a in replica.actors {
            a.question = nil
            a.choices = []
        }
        let t = ReplicaTimeline()
        source.actors[0].position = V(2, 3)
        source.restoreClock(1.0)
        t.accept(WorldCodec.shared(source), 1000)
        t.render(replica, 1000)
        source.actors[0].position = V(4, 3)
        source.restoreClock(1.1)
        t.accept(WorldCodec.shared(source), 1100)
        t.render(replica, 1150)
        XCTAssertEqual(replica.actors[0].position.x, 3.0, accuracy: 0.001)
        XCTAssertEqual(replica.time, 1.05, accuracy: 0.001)
        t.render(replica, 3000)
        XCTAssertEqual(replica.actors[0].position.x, 4.0, accuracy: 0.001)
        XCTAssertNil(replica.actors[0].question)
        XCTAssertEqual(replica.actors[0].score, 0)
    }

    func testCommittedResultReplacesStaleAuthorityCheckpointExactly() {
        let e = SplashEngine(members: [Member("a", "mia"), Member("b", "minik")])
        e.restoreClock(24.074)
        e.actor("a")?.score = 9
        e.finish()
        let committed = MatchResult(id: "room-r1", winners: ["a"], scores: ["a": 10, "b": 5], teamScores: [0, 0], draw: false, elapsed: 24.076333)
        WorldCodec.applyResult(e, committed)
        XCTAssertEqual(e.result, committed)
        XCTAssertEqual(e.time, committed.elapsed)
        XCTAssertEqual(e.actor("a")?.score, 10)
        e.tick(0.1)
        XCTAssertEqual(e.result, committed)
    }

    /// Firebase delivers lists as arrays and booleans as CFBoolean NSNumbers; both decode.
    func testFoundationValuesDecodeLikeAndroid() {
        let node: Node = ["flag": NSNumber(value: true), "count": NSNumber(value: 3), "list": NSArray(array: [1, 2]),
                          "sparse": ["1": "b", "0": "a"] as NSDictionary, "secret": NSNumber(value: Int64(-9_000_000_000_000_000_123))]
        XCTAssertTrue(node.flag("flag"))
        XCTAssertFalse(node.flag("count"))
        XCTAssertEqual(node.num("count"), 3)
        XCTAssertEqual(node.num("flag", -1), -1)
        XCTAssertEqual(node.list("list").count, 2)
        XCTAssertEqual(node.list("sparse").compactMap { $0 as? String }, ["a", "b"])
        XCTAssertEqual(NodeValue.int64(node["secret"]), -9_000_000_000_000_000_123)
    }
}
