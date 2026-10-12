import Foundation

/// Port of Android core/Ranks.kt: colour ranks earned with points (ink is the text colour on the rank).
struct ProgressRank: Equatable {
    let threshold: Int
    let en: String
    let he: String
    let color: UInt32
    let ink: UInt32

    init(_ threshold: Int, _ en: String, _ he: String, _ color: UInt32, _ ink: UInt32 = 0xff17283f) {
        self.threshold = threshold
        self.en = en
        self.he = he
        self.color = color
        self.ink = ink
    }
}

enum ProgressRanks {
    static let all: [ProgressRank] = [
        ProgressRank(0, "White", "לבן", 0xfffafafa), ProgressRank(100, "Yellow", "צהוב", 0xffffe761),
        ProgressRank(250, "Cyan", "טורקיז", 0xff62eced), ProgressRank(500, "Light blue", "תכלת", 0xff8dcaff),
        ProgressRank(1000, "Orange", "כתום", 0xffffa64f), ProgressRank(1800, "Pink", "ורוד", 0xffff75b5),
        ProgressRank(3000, "Red", "אדום", 0xffef5350), ProgressRank(5000, "Blue", "כחול", 0xff2459c5, 0xffffffff),
        ProgressRank(8000, "Brown", "חום", 0xff795548, 0xffffffff), ProgressRank(12000, "Silver", "כסף", 0xffd8e0e9),
        ProgressRank(18000, "Gold", "זהב", 0xffffcf40)
    ]

    static func at(_ points: Int) -> ProgressRank {
        return all.last { points >= $0.threshold } ?? all[0]
    }
}

/// Android `RewardLedger`: cumulative receipt totals allow pause/resume without duplicate rewards.
final class RewardLedger {
    var points: Int
    var receipts: [String: Int]

    init(points: Int = 0, receipts: [String: Int] = [:]) {
        self.points = points
        self.receipts = receipts
    }

    @discardableResult
    func record(_ match: String, _ earned: Int) -> Int {
        let old = receipts[match] ?? 0
        let delta = max(earned - old, 0)
        if delta > 0 {
            points += delta
            receipts[match] = earned
        }
        return delta
    }
}
