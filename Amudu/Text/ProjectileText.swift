import Foundation

/// Android `ProjectileText` (amudu/ProjectileText.kt): with the paint balloon, gameplay copy says "balloon" instead of
/// "ball". Applied only to gameplay copy, never menu names or shared translations.
enum ProjectileText {
    static func apply(_ text: String, kind: BallKind, language: String) -> String {
        if kind != .paint { return text }
        var s = text
        let words: [(String, String)]
        switch language {
        case "he":
            words = [("כדורים", "בלונים"), ("כדור", "בלון")]
        case "es":
            words = [("Las pelotas", "Los globos"), ("las pelotas", "los globos"), ("La pelota", "El globo"), ("la pelota", "el globo"), ("una pelota", "un globo"), ("pelotas", "globos"), ("pelota", "globo")]
        case "ar":
            words = [("الكرات", "البالونات"), ("الكرة", "البالون"), ("كرة", "بالون")]
        case "hi":
            words = [("गेंद को", "गुब्बारे को"), ("गेंद से", "गुब्बारे से"), ("गेंद के", "गुब्बारे के"), ("गेंद", "गुब्बारा")]
        case "nl":
            words = [("Ballen", "Ballonnen"), ("ballen", "ballonnen"), ("Bal", "Ballon"), ("bal", "ballon")]
        default:
            words = [("Balls", "Balloons"), ("balls", "balloons"), ("Ball", "Balloon"), ("ball", "balloon")]
        }
        let plain = ["he", "ar", "hi"].contains(language)
        for (a, b) in words {
            if plain {
                s = s.replacingOccurrences(of: a, with: b)
            } else {
                // Kotlin `Regex("\\b" + Regex.escape(a) + "\\b").replace(s, b)` (ICU word boundaries on Android).
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: a) + "\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(location: 0, length: (s as NSString).length)
                s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                   withTemplate: NSRegularExpression.escapedTemplate(for: b))
            }
        }
        return s
    }
}
