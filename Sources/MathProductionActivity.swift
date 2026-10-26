import Foundation

enum MathProductionReadiness: String, Hashable, Sendable {
    case implementedPrototype
    case blockedProductDefinition
    case planned
}

enum MathProductionCurriculumRole: Hashable, Sendable {
    case curriculum
    case nonCurriculum
}

enum MathProductionLaunchRoute: Hashable, Sendable {
    case curriculumEngine(MathActivityKind)
    case m1Production
    case m2Production
    case m3Production
    case m4Production
    case m5Production
    case m6Production
    case m7Production
    case m8Production
    case m9Production
    case m10Production
    case pingPong
}

/// Canonical child-visible Math identities, separate from reusable engines.
enum MathProductionActivityID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case learnMath, mathPairs, buildNumber, buildQuantity, visualToAnswer
    case answerToRepresentation, buildMath, mathMixed, mathCards
    case mathSoccer, mathTower, mathMemory, pingPong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learnMath: return String(localized: "Learn Math")
        case .mathPairs: return String(localized: "Math Pairs")
        case .buildNumber: return String(localized: "Build Number")
        case .buildQuantity: return String(localized: "Build Quantity")
        case .visualToAnswer: return String(localized: "Visual → Answer")
        case .answerToRepresentation: return String(localized: "Answer → Representation")
        case .buildMath: return String(localized: "Build Math")
        case .mathMixed: return String(localized: "Math Mixed")
        // Learn Math teaches one fact per screen; Math Cards gives sixteen useful rules with
        // examples (Android Math Plus ab3e427), so it takes Android's name again.
        case .mathCards: return String(localized: "Math Cards")
        case .mathSoccer: return String(localized: "Math Soccer")
        case .mathTower: return String(localized: "Math Tower")
        case .mathMemory: return String(localized: "Math Memory")
        case .pingPong: return String(localized: "Ping Pong")
        }
    }

    var subtitle: String {
        switch self {
        case .learnMath: return String(localized: "Step by step: one fact at a time, with pictures")
        case .mathPairs: return String(localized: "Match equal math representations")
        case .buildNumber: return String(localized: "Construct the matching number")
        case .buildQuantity: return String(localized: "Construct the requested quantity")
        case .visualToAnswer: return String(localized: "Choose the answer for a visual prompt")
        case .answerToRepresentation: return String(localized: "Choose an equivalent representation")
        case .buildMath: return String(localized: "Build an answer or expression in order")
        case .mathMixed: return String(localized: "Practice approved modes for this level")
        case .mathCards: return String(localized: "Discover useful rules with examples")
        case .mathSoccer: return String(localized: "Kick the correct math answer")
        case .mathTower: return String(localized: "Build the target value")
        case .mathMemory: return String(localized: "Find equivalent math pairs")
        case .pingPong: return String(localized: "Play table tennis with Minik")
        }
    }

    var symbolName: String {
        switch self {
        case .learnMath: return "sparkles"
        case .mathPairs: return "square.grid.2x2"
        case .buildNumber: return "number.square"
        case .buildQuantity: return "square.grid.3x3.fill"
        case .visualToAnswer: return "photo.badge.checkmark"
        case .answerToRepresentation: return "rectangle.grid.2x2"
        case .buildMath: return "square.and.pencil"
        case .mathMixed: return "shuffle"
        case .mathCards: return "tablecells"
        case .mathSoccer: return "soccerball"
        case .mathTower: return "building.columns"
        case .mathMemory: return "rectangle.on.rectangle"
        case .pingPong: return "figure.table.tennis"
        }
    }

    var theme: ActivityTheme {
        switch self {
        case .learnMath, .mathMemory, .mathCards: return .sky
        case .visualToAnswer, .answerToRepresentation: return .sunshine
        case .buildNumber, .buildQuantity, .buildMath: return .coral
        case .mathPairs, .mathSoccer: return .meadow
        case .mathMixed, .mathTower, .pingPong: return .berry
        }
    }

    var curriculumRole: MathProductionCurriculumRole {
        self == .pingPong ? .nonCurriculum : .curriculum
    }

    var readiness: MathProductionReadiness {
        switch self {
        case .learnMath, .mathPairs, .buildNumber, .buildQuantity,
             .visualToAnswer, .answerToRepresentation, .buildMath,
             .mathMixed, .mathCards, .mathSoccer, .mathTower,
             .mathMemory, .pingPong:
            return .implementedPrototype
        }
    }

    var engine: MathActivityKind? {
        switch self {
        case .learnMath: return .learn
        case .mathPairs: return .pairs
        case .visualToAnswer: return .multipleChoice
        case .buildMath: return .build
        case .mathSoccer: return .soccer
        case .mathTower: return .tower
        case .mathMemory: return .memory
        case .buildNumber, .buildQuantity, .answerToRepresentation,
             .mathMixed, .mathCards, .pingPong:
            return nil
        }
    }

    func launchRoute(for levelID: MathCurriculumLevelID) -> MathProductionLaunchRoute? {
        if self == .pingPong { return .pingPong }
        if levelID == .m1 { return .m1Production }
        if levelID == .m2 { return .m2Production }
        if levelID == .m3 { return .m3Production }
        if levelID == .m4 { return .m4Production }
        if levelID == .m5 { return .m5Production }
        if levelID == .m6 { return .m6Production }
        if levelID == .m7 { return .m7Production }
        if levelID == .m8 { return .m8Production }
        if levelID == .m9 { return .m9Production }
        if levelID == .m10 { return .m10Production }
        guard readiness == .implementedPrototype,
              let engine,
              MathCurriculumPolicy.specification(for: engine, levelID: levelID) != nil else {
            return nil
        }
        return .curriculumEngine(engine)
    }

    static let sections: [ActivitySection<MathProductionActivityID>] = [
        // "Learn" alone was translated for the Language apps ("learning the letters").
        ActivitySection(
            id: "math-learn",
            title: String(localized: "Learn and review"),
            subtitle: String(localized: "Learn this level's facts step by step, then discover useful rules."),
            activities: [.learnMath, .mathCards]
        ),
        ActivitySection(
            id: "math-practice",
            title: String(localized: "Practice"),
            subtitle: String(localized: "Explore the same idea in different ways."),
            activities: [
                .mathPairs, .buildNumber, .buildQuantity, .visualToAnswer,
                .answerToRepresentation, .buildMath, .mathMixed
            ]
        ),
        ActivitySection(
            id: "math-games",
            title: String(localized: "Games"),
            subtitle: String(localized: "Keep math moving and hands-on."),
            activities: [.mathSoccer, .mathTower, .mathMemory, .pingPong]
        )
    ]
}
