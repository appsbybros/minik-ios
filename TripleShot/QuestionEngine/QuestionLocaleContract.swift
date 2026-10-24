import Foundation

// Port of questionenginelib QuestionLocaleContract.kt (questionenginelib 578ed22). Spec 04 §3.2, §7.

enum QuestionLocaleContract {
    static let contentLocales: KLinkedSet<String> = KLinkedSet(["en", "he", "ar", "es", "hi"])

    /// Trim (Kotlin whitespace), lowercase, keep the part before the first '-' then before the first '_',
    /// `iw` -> `he`; anything that is not a content locale (including null and "") is "en".
    static func normalize(languageCode: String?) -> String {
        let base = QuestionsKotlin.substringBefore(
            QuestionsKotlin.substringBefore((languageCode ?? "").ktrim().lowercased(), "-"), "_")
        let normalized = base == "iw" ? "he" : base
        return contentLocales.contains(normalized) ? normalized : "en"
    }
}
