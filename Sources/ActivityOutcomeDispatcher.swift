import Foundation

/// Shared boundary for persisting typed activity outcomes and optionally
/// forwarding them to a product-owned reward policy. Math intentionally
/// configures no reward handler until its scoring values are approved.
final class ActivityOutcomeDispatcher {
    typealias RewardHandler = (ActivityEvent) throws -> Void

    private let progressSink: ActivityEventSink
    private let rewardHandler: RewardHandler?
    private let practiceClock: PracticeTimeClock?

    init(
        progressSink: ActivityEventSink,
        rewardHandler: RewardHandler? = nil,
        practiceClock: PracticeTimeClock? = nil
    ) {
        self.progressSink = progressSink
        self.rewardHandler = rewardHandler
        self.practiceClock = practiceClock
    }

    func dispatch(_ event: ActivityEvent) throws {
        let event = practiceTimed(event)
        try progressSink.record(event)
        try rewardHandler?(event)
    }

    /// With a practice clock, an answer adds to the practice time only the part of its
    /// response span in which practice was on screen with the app active, not the time
    /// on menus, Progress, the Parent Area or in the background.
    private func practiceTimed(_ event: ActivityEvent) -> ActivityEvent {
        guard let practiceClock,
              event.practiceDurationSeconds == nil,
              let response = event.attemptData?.responseDurationSeconds else { return event }
        let seconds = practiceClock.practiceSeconds(
            from: event.occurredAt.addingTimeInterval(-response),
            to: event.occurredAt
        )
        return ActivityEvent(
            id: event.id,
            sessionID: event.sessionID,
            context: event.context,
            kind: event.kind,
            occurredAt: event.occurredAt,
            practiceDurationSeconds: seconds,
            attemptData: event.attemptData
        ) ?? event
    }
}
