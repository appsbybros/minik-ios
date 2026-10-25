import Foundation
import XCTest
@testable import MinikPlus

final class ActivityOutcomeDispatcherTests: XCTestCase {
    func testDispatchWritesProgressBeforeOptionalRewardBoundary() throws {
        let sink = RecordingEventSink()
        var rewardedEventID: UUID?
        let dispatcher = ActivityOutcomeDispatcher(
            progressSink: sink,
            rewardHandler: { event in rewardedEventID = event.id }
        )
        let event = try XCTUnwrap(makeEvent())

        try dispatcher.dispatch(event)

        XCTAssertEqual(sink.events, [event])
        XCTAssertEqual(rewardedEventID, event.id)
    }

    func testMathCanPersistWithoutInventingRewardPolicy() throws {
        let sink = RecordingEventSink()
        let dispatcher = ActivityOutcomeDispatcher(progressSink: sink)
        let event = try XCTUnwrap(makeEvent())

        try dispatcher.dispatch(event)

        XCTAssertEqual(sink.events, [event])
    }

    func testPracticeTimeCountsOnlyWhilePracticeIsOnScreen() throws {
        let sink = RecordingEventSink()
        let clock = PracticeTimeClock()
        let dispatcher = ActivityOutcomeDispatcher(progressSink: sink, practiceClock: clock)
        let start = Date(timeIntervalSince1970: 1_000)
        // On screen 10 s, in the background 60 s, back on screen 5 s, then answered.
        clock.setRunning(true, at: start)
        clock.setRunning(false, at: start.addingTimeInterval(10))
        clock.setRunning(true, at: start.addingTimeInterval(70))
        let event = try XCTUnwrap(makeEvent(
            responseDurationSeconds: 75,
            occurredAt: start.addingTimeInterval(75)
        ))

        try dispatcher.dispatch(event)

        XCTAssertEqual(sink.events.first?.id, event.id)
        XCTAssertEqual(try XCTUnwrap(sink.events.first?.practiceDurationSeconds), 15, accuracy: 0.001)
    }

    func testPracticeTimeIsZeroWhenPracticeWasNeverOnScreen() throws {
        let sink = RecordingEventSink()
        let dispatcher = ActivityOutcomeDispatcher(progressSink: sink, practiceClock: PracticeTimeClock())
        let event = try XCTUnwrap(makeEvent(
            responseDurationSeconds: 30,
            occurredAt: Date(timeIntervalSince1970: 100)
        ))

        try dispatcher.dispatch(event)

        XCTAssertEqual(sink.events.first?.practiceDurationSeconds, 0)
    }

    private func makeEvent(
        responseDurationSeconds: Double? = nil,
        occurredAt: Date = Date(timeIntervalSince1970: 1)
    ) -> ActivityEvent? {
        let attempt = ActivityAttemptData(
            itemID: ActivityItemID(rawValue: "m2.test"),
            attemptIndex: 1,
            result: .correct,
            responseDurationSeconds: responseDurationSeconds,
            activityFamily: .multipleChoice,
            mathLevelID: .m2,
            skillID: MathSkillIDs.addition
        )
        return attempt.flatMap {
            ActivityEvent(
                sessionID: ActivitySessionID(),
                context: ActivityEventContext(
                    product: .minikMath,
                    activityID: ProgressActivityID(rawValue: "math.multipleChoice"),
                    curriculumStageID: MathCurriculumLevelID.m2.curriculumStageID,
                    skillID: MathSkillIDs.addition
                ),
                kind: .gradedAttempt,
                occurredAt: occurredAt,
                attemptData: $0
            )
        }
    }
}

private final class RecordingEventSink: ActivityEventSink {
    private(set) var events: [ActivityEvent] = []

    func record(_ event: ActivityEvent) throws {
        events.append(event)
    }
}
