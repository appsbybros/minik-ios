import Foundation

/// The owner's rule of 15 November 2026, as promised in the App Review reply for Minik Plus: the
/// grown-up check (ParentalGateView) comes before the Parent Area opens, in every app that shows
/// ParentAreaView. One passed check covers the whole visit: the actions inside (purchases,
/// restore, links that leave the app, the leaderboard switches, rate and share) and the Parent
/// Area's own pages (Progress, Records, Learning progress) do not ask again. Leaving the Parent
/// Area ends the visit, and the next one asks again.
///
/// Purchases that can be reached from outside the Parent Area keep their own check: the Minik
/// Plus welcome screen, wall and free-week chip, the Remove Ads reminder, and the other apps'
/// parents pages.
struct ParentAreaVisit: Equatable, Sendable {
    private(set) var isOpen = false

    /// The grown-up check before the Parent Area was passed.
    mutating func grownUpCheckPassed() {
        isOpen = true
    }

    /// The Parent Area and its pages were left.
    mutating func leave() {
        isOpen = false
    }

    /// Back from one of the Parent Area's pages leads into the Parent Area only within a visit
    /// the grown-up check opened; otherwise it leads to the main screen.
    var backFromPageOpensParentArea: Bool {
        isOpen
    }
}
