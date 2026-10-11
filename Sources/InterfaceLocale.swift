import Foundation
import SwiftUI

enum InterfaceLocaleID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case english = "en"
    case amharic = "am"
    case arabic = "ar"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case hebrew = "he"
    case dutch = "nl"
    case portugueseBrazil = "pt-BR"
    case portuguesePortugal = "pt-PT"
    case russian = "ru"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        self == .hebrew || self == .arabic ? .rightToLeft : .leftToRight
    }

    /// LocalizedStringResource selects the translation language. The locale
    /// argument of String(localized: key, locale:) only formats interpolations.
    func text(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: locale))
    }

    /// Maps a device language tag such as "he-IL", "iw", "pt-PT" or "ar-SA".
    init?(languageTag: String) {
        let parts = languageTag
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard let language = parts.first?.lowercased() else { return nil }
        switch language {
        case "iw":
            self = .hebrew
        case "pt":
            let region = parts.dropFirst().first(where: { $0.count == 2 })?.uppercased()
            self = region == "PT" ? .portuguesePortugal : .portugueseBrazil
        default:
            guard let match = InterfaceLocaleID(rawValue: language) else { return nil }
            self = match
        }
    }
}

enum InterfaceLocalePolicy {
    static func allowedLocales(for product: ProductVariant) -> [InterfaceLocaleID] {
        product == .minikPlusEnglish
            ? InterfaceLocaleID.allCases.filter { $0 != .hebrew }
            : InterfaceLocaleID.allCases
    }

    static func resolve(
        _ requested: InterfaceLocaleID?,
        for product: ProductVariant
    ) -> InterfaceLocaleID {
        let allowed = allowedLocales(for: product)
        if let requested, allowed.contains(requested) { return requested }
        return .english
    }

    /// As on Android, the primary device language decides the starting interface
    /// language. Unsupported languages, and Hebrew in English Only, start in English.
    static func deviceDefault(
        for product: ProductVariant,
        preferredLanguages: [String]
    ) -> InterfaceLocaleID {
        resolve(preferredLanguages.first.flatMap { InterfaceLocaleID(languageTag: $0) }, for: product)
    }
}

final class InterfaceLocaleRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let preferredLanguages: () -> [String]

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "minik.interface-locale.v1",
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.preferredLanguages = preferredLanguages
    }

    /// The language on screen, Android's app locale: the last language the app
    /// switched to wins; otherwise the interface follows the device language.
    func load(for product: ProductVariant) -> InterfaceLocaleID {
        if let stored = userDefaults.string(forKey: storageKey).flatMap({ InterfaceLocaleID(rawValue: $0) }),
           InterfaceLocalePolicy.allowedLocales(for: product).contains(stored) {
            return stored
        }
        return InterfaceLocalePolicy.deviceDefault(for: product, preferredLanguages: preferredLanguages())
    }

    func save(_ locale: InterfaceLocaleID, for product: ProductVariant) {
        userDefaults.set(
            InterfaceLocalePolicy.resolve(locale, for: product).rawValue,
            forKey: storageKey
        )
    }

    /// Android's userHostingLang_<slot>: the interface language chosen in the
    /// Parent Area for the learner who plays now (a child, or the guest while no
    /// child exists). ChildProfileStore keeps each learner's own value and puts
    /// the playing learner's under this key.
    static func learnerChoiceKey(for product: ProductVariant) -> String {
        "minik.interface-locale.learner.v1.\(product.rawValue)"
    }

    /// The playing learner's own interface language; nil when none was chosen
    /// for this learner (a new child) or the product does not offer it.
    func loadLearnerChoice(for product: ProductVariant) -> InterfaceLocaleID? {
        guard let stored = userDefaults.string(forKey: Self.learnerChoiceKey(for: product))
            .flatMap({ InterfaceLocaleID(rawValue: $0) }),
              InterfaceLocalePolicy.allowedLocales(for: product).contains(stored) else {
            return nil
        }
        return stored
    }

    func saveLearnerChoice(_ locale: InterfaceLocaleID, for product: ProductVariant) {
        userDefaults.set(
            InterfaceLocalePolicy.resolve(locale, for: product).rawValue,
            forKey: Self.learnerChoiceKey(for: product)
        )
    }
}

@MainActor
final class InterfaceLocaleController: ObservableObject {
    @Published private(set) var selectedLocale: InterfaceLocaleID
    let product: ProductVariant
    private let repository: InterfaceLocaleRepository

    init(product: ProductVariant, repository: InterfaceLocaleRepository = InterfaceLocaleRepository()) {
        self.product = product
        self.repository = repository
        selectedLocale = repository.load(for: product)
    }

    var allowedLocales: [InterfaceLocaleID] {
        InterfaceLocalePolicy.allowedLocales(for: product)
    }

    /// Android's Parent Area language picker (LanguagesAndLevelsDialogFragment
    /// applyHostingLanguage): the app switches to the language, and it is saved
    /// as the playing child's own (or, while no child exists, as the app's).
    /// Picking the language already shown changes nothing, as an Android
    /// spinner reports no selection for its current item.
    func select(_ locale: InterfaceLocaleID) {
        let resolved = InterfaceLocalePolicy.resolve(locale, for: product)
        guard resolved != selectedLocale else { return }
        selectedLocale = resolved
        repository.save(resolved, for: product)
        repository.saveLearnerChoice(resolved, for: product)
    }

    /// Android IntroScreen.selectUser: a child who has an interface language of
    /// their own brings it back; a child without one (a new child) keeps the
    /// language on screen.
    func applyLearnerChoice() {
        guard let chosen = repository.loadLearnerChoice(for: product),
              chosen != selectedLocale else { return }
        selectedLocale = chosen
        repository.save(chosen, for: product)
    }
}

private struct InterfaceLocaleEnvironmentKey: EnvironmentKey {
    static let defaultValue: InterfaceLocaleID = .english
}

extension EnvironmentValues {
    var interfaceLocaleID: InterfaceLocaleID {
        get { self[InterfaceLocaleEnvironmentKey.self] }
        set { self[InterfaceLocaleEnvironmentKey.self] = newValue }
    }
}
