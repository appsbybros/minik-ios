import Foundation

/// App Store screenshot captures show the app in use rather than freshly installed:
/// a child with points and a few days of practice. It runs only when the app is
/// launched with `-MinikScreenshotScene` (see StoreScreenshotScene), before the
/// hub loads anything, and seeds once per install.
@MainActor
enum StoreScreenshotSampleData {
    static func seedIfNeeded(product: ProductVariant) {
        guard StoreScreenshotScene.name != nil,
              product == .minikPlus || product == .minikPlusEnglish else { return }
        let hebrew = Locale.preferredLanguages.first?.hasPrefix("he") == true
        let name = hebrew ? "נועה" : "Noa"
        let store = ChildProfileStore(product: product)
        // The same install is captured in each language: the child's name follows it.
        if let child = store.children.first {
            if child.name != name { store.renameChild(child.id, to: name) }
            return
        }
        guard store.addChild(named: name) == nil else { return }
        recordPractice(product: product)
    }

    private static func recordPractice(product: ProductVariant) {
        let progress = LocalProgressRepository()
        let rewards = LanguageWordPracticeRewardService(repository: LocalRewardRepository())
        let choices: [(activity: String, skill: SkillID)] = [
            ("language.imageToWord", LanguageSkillIDs.wordImageAssociation),
            ("language.wordToImage", LanguageSkillIDs.wordImageAssociation),
            ("language.firstLetterChoices", LanguageSkillIDs.initialLetterAssociation)
        ]
        let games = ["language.memory", "language.tower", "language.soccer", "language.learn"]
        let now = Date()
        for day in 1...5 {
            let start = now.addingTimeInterval(-Double(day) * 86_400)
            for (index, choice) in choices.enumerated() where (day + index) % 3 != 0 {
                let context = ActivityEventContext(
                    product: product,
                    activityID: ProgressActivityID(rawValue: choice.activity),
                    skillID: choice.skill
                )
                let session = ActivitySessionID()
                let opened = start.addingTimeInterval(Double(index) * 600)
                record(session, context, .sessionStarted, opened, into: progress)
                for item in 1...10 {
                    // About one answer in seven is wrong, as a child's would be.
                    let correct = (item + day + index) % 7 != 0
                    guard let attempt = ActivityAttemptData(
                        itemID: ActivityItemID(rawValue: "sample-\(day)-\(index)-\(item)"),
                        attemptIndex: 1,
                        result: correct ? .correct : .incorrect,
                        responseDurationSeconds: 4,
                        activityFamily: .multipleChoice,
                        skillID: choice.skill
                    ), let event = ActivityEvent(
                        sessionID: session,
                        context: context,
                        kind: .gradedAttempt,
                        occurredAt: opened.addingTimeInterval(Double(item) * 20),
                        attemptData: attempt
                    ) else { continue }
                    try? progress.record(event)
                    try? rewards.processAttempt(event)
                }
                record(session, context, .sessionEnded, opened.addingTimeInterval(240),
                       duration: 240, into: progress)
            }
            let game = games[day % games.count]
            let context = ActivityEventContext(product: product, activityID: ProgressActivityID(rawValue: game))
            let session = ActivitySessionID()
            let opened = start.addingTimeInterval(2_400)
            record(session, context, .sessionStarted, opened, into: progress)
            record(session, context, .completed, opened.addingTimeInterval(300), into: progress)
            record(session, context, .sessionEnded, opened.addingTimeInterval(300), duration: 300, into: progress)
        }
    }

    private static func record(
        _ session: ActivitySessionID,
        _ context: ActivityEventContext,
        _ kind: ActivityEventKind,
        _ date: Date,
        duration: Double? = nil,
        into progress: LocalProgressRepository
    ) {
        guard let event = ActivityEvent(
            sessionID: session,
            context: context,
            kind: kind,
            occurredAt: date,
            practiceDurationSeconds: duration
        ) else { return }
        try? progress.record(event)
    }
}
