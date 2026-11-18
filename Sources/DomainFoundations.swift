import Foundation

struct ContentItemID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A content item identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct SkillID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A skill identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct CurriculumStageID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A curriculum stage identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct ChallengeID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A challenge identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct ChoiceID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A choice identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct AssetReference: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "An asset reference cannot be empty.")
        self.rawValue = rawValue
    }
}

struct RepresentationStructureID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A representation structure identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

/// An exact fraction reduced to lowest terms with a positive denominator.
struct Rational: Hashable, Sendable {
    let numerator: Int
    let denominator: Int

    init?(numerator: Int, denominator: Int) {
        guard denominator != 0, denominator != .min else {
            return nil
        }

        let divisor = Int(Self.greatestCommonDivisor(
            numerator.magnitude,
            denominator.magnitude
        ))
        let reducedNumerator = numerator / divisor
        let reducedDenominator = denominator / divisor

        if reducedDenominator < 0 {
            guard reducedNumerator != .min else {
                return nil
            }
            self.numerator = -reducedNumerator
            self.denominator = -reducedDenominator
        } else {
            self.numerator = reducedNumerator
            self.denominator = reducedDenominator
        }
    }

    private static func greatestCommonDivisor(_ first: UInt, _ second: UInt) -> UInt {
        var a = first
        var b = second

        while b != 0 {
            (a, b) = (b, a % b)
        }

        return a
    }
}

enum SemanticValue: Hashable, Sendable {
    case contentItem(ContentItemID)
    case integer(Int)
    case rational(Rational)
}

extension SemanticValue {
    var exactNumericValue: ExactNumericValue? {
        switch self {
        case .integer(let value): return .integer(value)
        case .rational(let value): return .rational(value)
        case .contentItem: return nil
        }
    }

    func isNumericallyEquivalent(to other: SemanticValue) -> Bool {
        guard let first = exactNumericValue?.normalizedRational,
              let second = other.exactNumericValue?.normalizedRational else {
            return false
        }
        return first == second
    }
}

enum ContentDirection: String, Hashable, Codable, Sendable {
    case leftToRight
    case rightToLeft
}

struct LearningTextRepresentation: Hashable, Sendable {
    let text: String
    let language: LanguageIdentifier?
    let direction: ContentDirection?
    let speechText: String?

    init(
        text: String,
        language: LanguageIdentifier?,
        direction: ContentDirection?,
        speechText: String? = nil
    ) {
        self.text = text
        self.language = language
        self.direction = direction
        self.speechText = speechText
    }
}

struct MathExpressionRepresentation: Hashable, Sendable {
    let expression: String
    let structureID: RepresentationStructureID
}

struct VisualQuantityRepresentation: Hashable, Sendable {
    let quantity: Int
    let structureID: RepresentationStructureID
}

enum Representation: Hashable, Sendable {
    case learningText(LearningTextRepresentation)
    case imageAsset(AssetReference)
    case audioAsset(AssetReference)
    case mathExpression(MathExpressionRepresentation)
    case visualQuantity(VisualQuantityRepresentation)
    case math(MathRepresentation)
}

extension Representation {
    var accessibilityDescription: String {
        switch self {
        case .learningText(let value): return value.text
        case .imageAsset: return String(localized: "Educational image")
        case .audioAsset: return String(localized: "Audio")
        case .mathExpression(let value): return value.expression
        case .visualQuantity(let value):
            return value.quantity == 0
                ? String(localized: "Empty quantity")
                : String(format: String(localized: "Quantity of %lld"), Int64(value.quantity))
        case .math(let value): return value.accessibilityDescription
        }
    }
}

struct Prompt: Hashable, Sendable {
    let representations: [Representation]
    let speechCue: LearningSpeechUtterance?

    init?(
        representations: [Representation],
        speechCue: LearningSpeechUtterance? = nil
    ) {
        guard !representations.isEmpty else {
            return nil
        }
        self.representations = representations
        self.speechCue = speechCue
    }

    var learningSpeechCue: LearningSpeechUtterance? {
        speechCue ?? representations.lazy.compactMap(\.learningSpeechCue).first
    }
}

struct Choice: Hashable, Sendable {
    let id: ChoiceID
    let representation: Representation
    let semanticValue: SemanticValue
    let speechCue: LearningSpeechUtterance?

    init(
        id: ChoiceID,
        representation: Representation,
        semanticValue: SemanticValue,
        speechCue: LearningSpeechUtterance? = nil
    ) {
        self.id = id
        self.representation = representation
        self.semanticValue = semanticValue
        self.speechCue = speechCue
    }

    var learningSpeechCue: LearningSpeechUtterance? {
        speechCue ?? representation.learningSpeechCue
    }
}

enum ValidationRule: String, Hashable, Codable, Sendable {
    case exactIdentity
    case numericEquivalence
    case structuralMatch
    case orderedSequence
    case unorderedSelection
    case pairMatching
}

enum Interaction: String, Hashable, Codable, Sendable {
    case singleChoice
    case numericInput
    case textInput
    case orderedTokens
    case unorderedSelection
    case matching
}

struct SemanticPair: Hashable, Sendable {
    let first: SemanticValue
    let second: SemanticValue
}

enum ExpectedAnswer: Hashable, Sendable {
    case semanticValue(SemanticValue)
    case structure(RepresentationStructureID)
    case orderedValues([SemanticValue])
    case unorderedValues(Set<SemanticValue>)
    case pairs(Set<SemanticPair>)
}

struct Difficulty: Hashable, Sendable {
    let value: Double

    init?(_ value: Double) {
        guard (0.0 ... 1.0).contains(value) else {
            return nil
        }
        self.value = value
    }
}

struct Challenge: Hashable, Sendable {
    let id: ChallengeID
    let prompt: Prompt
    let choices: [Choice]
    let interaction: Interaction
    let validationRule: ValidationRule
    let expectedAnswer: ExpectedAnswer
    let primarySkill: SkillID
    let secondarySkills: Set<SkillID>
    let curriculumStage: CurriculumStageID
    let difficulty: Difficulty
    /// The vocabulary word a Language word page asks about (the correct picture or word,
    /// or the word whose first letter is asked); Android WriteScreen counts each answer
    /// for that word. Nil on every other page, Math included.
    var languageContentItemID: ContentItemID? = nil
}
