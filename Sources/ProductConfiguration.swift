import Foundation

/// A learned-language identifier backed by a locale identifier so the domain
/// can grow without adding a case to `ProductVariant`.
struct LanguageIdentifier: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A language identifier cannot be empty.")
        self.rawValue = rawValue
    }

    static let english = LanguageIdentifier(rawValue: "en")
    static let hebrew = LanguageIdentifier(rawValue: "he")
}

enum ProductVariant: String, Codable, Hashable, Sendable {
    case minikPlus
    case minikPlusEnglish
    case minikMath
    case minikPingPong
}

extension ProductVariant {
    /// The shared family messages (Family/, Android MinikFamilyServices): the "More Minik apps &
    /// games" card, its ad-break promotion and reminder. Android Minik dropped them (59f6dd6), so
    /// Minik Plus and Minik Plus English show none and never load the family catalogue.
    var showsFamilyMessages: Bool {
        self != .minikPlus && self != .minikPlusEnglish
    }
}

enum ContentDomain: Equatable, Sendable {
    case language
    case math
    case game
}

enum ProductLaunchExperience: Equatable, Sendable {
    case activityHub
    case pingPong
}

struct ProductConfiguration: Equatable, Sendable {
    let variant: ProductVariant
    let displayName: String
    let contentDomain: ContentDomain
    let allowedLearnedLanguages: Set<LanguageIdentifier>
    let fixedLearnedLanguage: LanguageIdentifier?
    let isLearningLanguageSelectionAvailable: Bool

    private init(
        variant: ProductVariant,
        displayName: String,
        contentDomain: ContentDomain,
        allowedLearnedLanguages: Set<LanguageIdentifier>,
        fixedLearnedLanguage: LanguageIdentifier?,
        isLearningLanguageSelectionAvailable: Bool
    ) {
        precondition(
            fixedLearnedLanguage.map(allowedLearnedLanguages.contains) ?? true,
            "A fixed learned language must also be allowed."
        )

        self.variant = variant
        self.displayName = displayName
        self.contentDomain = contentDomain
        self.allowedLearnedLanguages = allowedLearnedLanguages
        self.fixedLearnedLanguage = fixedLearnedLanguage
        self.isLearningLanguageSelectionAvailable = isLearningLanguageSelectionAvailable
    }

    func allowsLearnedLanguage(_ language: LanguageIdentifier) -> Bool {
        allowedLearnedLanguages.contains(language)
    }

    var launchExperience: ProductLaunchExperience {
        variant == .minikPingPong ? .pingPong : .activityHub
    }

    /// Resolves persisted user state against the current product rules.
    func resolveRestoredLearnedLanguage(
        _ restoredLanguage: LanguageIdentifier?
    ) -> LanguageIdentifier? {
        if let fixedLearnedLanguage {
            return fixedLearnedLanguage
        }

        guard let restoredLanguage, allowsLearnedLanguage(restoredLanguage) else {
            return nil
        }

        return restoredLanguage
    }

    static func configuration(for variant: ProductVariant) -> ProductConfiguration {
        switch variant {
        case .minikPlus:
            return ProductConfiguration(
                variant: variant,
                displayName: "Minik Plus",
                contentDomain: .language,
                allowedLearnedLanguages: [.english, .hebrew],
                fixedLearnedLanguage: nil,
                isLearningLanguageSelectionAvailable: true
            )
        case .minikPlusEnglish:
            return ProductConfiguration(
                variant: variant,
                displayName: "Minik Plus English",
                contentDomain: .language,
                allowedLearnedLanguages: [.english],
                fixedLearnedLanguage: .english,
                isLearningLanguageSelectionAvailable: false
            )
        case .minikMath:
            return ProductConfiguration(
                variant: variant,
                displayName: "Minik Math",
                contentDomain: .math,
                allowedLearnedLanguages: [],
                fixedLearnedLanguage: nil,
                isLearningLanguageSelectionAvailable: false
            )
        case .minikPingPong:
            return ProductConfiguration(
                variant: variant,
                displayName: "Minik Ping Pong",
                contentDomain: .game,
                allowedLearnedLanguages: [],
                fixedLearnedLanguage: nil,
                isLearningLanguageSelectionAvailable: false
            )
        }
    }
}
