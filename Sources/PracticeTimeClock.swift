import Foundation

/// Progress & Statistics' practice time: it runs only while a practice or game screen
/// is open and the app is active. Activities time each answer from when its question
/// appeared, by the wall clock, so that span also takes in time on other screens and
/// in the background; the clock keeps the spans in which practice really was on
/// screen, and an answer's practice time is the part of its span inside them.
final class PracticeTimeClock {
    /// Spans that ended longer ago than this no longer matter to an answer being recorded.
    private static let retention: TimeInterval = 12 * 60 * 60

    private var runningSince: Date?
    private var spans: [DateInterval] = []

    var isRunning: Bool { runningSince != nil }

    func setRunning(_ running: Bool, at now: Date = Date()) {
        if running {
            if runningSince == nil { runningSince = now }
            return
        }
        guard let start = runningSince else { return }
        runningSince = nil
        if now > start {
            spans.append(DateInterval(start: start, end: now))
        }
        let oldest = now.addingTimeInterval(-Self.retention)
        spans.removeAll { $0.end < oldest }
    }

    /// The seconds between `start` and `end` during which practice was on screen.
    func practiceSeconds(from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        var counted = spans
        if let runningSince, end > runningSince {
            counted.append(DateInterval(start: runningSince, end: end))
        }
        return counted.reduce(0) { total, span in
            let overlap = min(span.end, end).timeIntervalSince(max(span.start, start))
            return total + max(0, overlap)
        }
    }
}
