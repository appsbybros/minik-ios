import StoreKit
import SwiftUI
import UIKit

/// The Parent Area's "rate, share and feedback" actions: Android Minik DailyLearningActivity
/// and Android Minik Math Plus ParentScreens' "Keep in touch" (a4ea9be, 7682b75). Each one
/// leaves the app, so the Parent Area opens it behind the grown-up check.
enum MinikKeepInTouchAction: String, Hashable, Sendable {
    case rate
    case share
    case feedback
}

enum MinikAppFeedback {
    static let feedbackAddress = "appsbybros.dev@gmail.com"
    /// The app's name when the bundle has none (it always has one).
    static let fallbackAppName = "Minik"

    /// The page shared with the app's name. Android shares the app's Google Play listing;
    /// these apps have no App Store link yet, so the share carries the app's own page at
    /// miniklearn.com (the family catalogue's landing page), as the other iPhone ports do.
    static func publicPage(for product: ProductVariant) -> String {
        switch product {
        case .minikMath:
            return "https://miniklearn.com/apps/minik-math-plus/"
        case .minikPingPong:
            return "https://miniklearn.com/apps/minik-ping-pong/"
        case .minikPlus, .minikPlusEnglish:
            return "https://miniklearn.com/apps/minik-plus/"
        }
    }

    /// Android's e-mail subject, in English in every language.
    static func feedbackSubject(for product: ProductVariant) -> String {
        switch product {
        case .minikMath:
            return "Minik Math Plus feedback"
        case .minikPlus, .minikPlusEnglish, .minikPingPong:
            return "Minik feedback"
        }
    }

    /// Android Minik: the app's name, a new line, and the app's page. Android Math Plus
    /// shares the page alone.
    static func shareText(for product: ProductVariant, bundle: Bundle = .main) -> String {
        if case .minikMath = product {
            return publicPage(for: product)
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackAppName
        return name + "\n" + publicPage(for: product)
    }

    /// Android ACTION_SENDTO mailto:appsbybros.dev@gmail.com with the subject.
    static func feedbackURL(for product: ProductVariant) -> URL? {
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = feedbackAddress
        mail.queryItems = [URLQueryItem(name: "subject", value: feedbackSubject(for: product))]
        return mail.url
    }

    /// The Info.plist key with the app's App Store ID (its Apple ID in App Store Connect,
    /// digits only), from the MINIK_APP_STORE_ID build setting.
    static let appStoreIDInfoKey = "MinikAppStoreID"

    /// The app's App Store ID, when this build has one.
    static func appStoreID(bundle: Bundle = .main) -> String? {
        let raw = (bundle.object(forInfoDictionaryKey: appStoreIDInfoKey) as? String) ?? ""
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return value
    }

    /// Android opens the store listing to rate the app; iOS opens the App Store's
    /// "Write a Review" page when the app's App Store ID is known (as Ivrit Together does).
    static func reviewURL(bundle: Bundle = .main) -> URL? {
        guard let id = appStoreID(bundle: bundle) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    /// Without the App Store ID, iOS asks the App Store for its own rating prompt. The App
    /// Store decides whether to show it: never in TestFlight, and only a few times a year.
    @MainActor
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }
}

/// The text handed to the system share sheet (Android Intent.createChooser).
struct MinikShareText: Identifiable {
    let id = UUID()
    let text: String
}

/// The system share sheet for a text.
struct MinikShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
