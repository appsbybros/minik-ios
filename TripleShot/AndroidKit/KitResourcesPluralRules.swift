// AndroidKit resources (kit-resources): the plural rules behind Resources.getQuantityText / getQuantityString.
//
// Android: ResourcesImpl.getQuantityText(id, quantity) picks the <plurals> item named by
// `android.icu.text.PluralRules.forLocale(configuration.locales[0]).select(quantity)` and falls back to "other"
// when the resource has no such item. The rules are those of the DEVICE locale, not of the values folder the text
// comes from: on a French device the Hebrew texts of values/ are chosen with the French rules (0 and 1 are "one").
//
// This is ICU 68.2 / CLDR 38.1, the ICU of Android 12 (the owner's reference Pixel 3), for the integer quantities
// Resources passes (Kotlin Int). ICU 68 operands of an integer q: n = |q| (FixedDecimal.source) but i = q WITH its
// sign (integerValue = (long) q), v = w = f = t = e = 0; `%` keeps the dividend's sign like Java. So rules written
// with `i` never match a negative quantity (select(-1) is "other" in English and Hebrew) while rules written with
// `n` do. Checked against icu4j-68.2 for every locale ICU knows, quantities -2147483647 ... 2147483647
// (Tests/TripleShotTests/ResourcesTests.swift has the vectors).
//
// Newer Android (ICU 72+, Android 14+) differs only outside the app's resources: Hebrew lost "many", i is the
// absolute value (select(-1) is "one"), Romanian 101 is "few", Maltese 2 is "two", and es/it/ca/pt get "many" for
// millions. The app's only plurals resource defines just "one" and "other" and is asked for 3 and more, so every
// Android version shows the same text.

extension AResources {
    enum PluralRules {
        /// `PluralRules.forLocale(locale).select(quantity)`: ICU looks the rules up by the locale id, then its
        /// parents (pt_PT has its own rules; every other region and script uses its language's rules).
        static func select(_ locale: ALocale, _ quantity: Int) -> String {
            if locale.language == "pt" && locale.country == "PT" {
                return select("pt_PT", quantity)
            }
            return select(locale.language, quantity)
        }

        /// The cardinal rules of an ICU rules locale id ("he", "en", "pt_PT", ...; "iw", "in", "ji", "tl", "mo" and
        /// "no" are accepted as ICU accepts them). Unknown languages have only "other" (ICU's root rules).
        static func select(_ id: String, _ quantity: Int) -> String {
            let n = quantity.magnitude
            let i = quantity
            let n10 = n % 10
            let n100 = n % 100
            let i10 = i % 10
            let i100 = i % 100
            switch id {

            // one: n = 1
            case "af", "an", "asa", "az", "bem", "bez", "bg", "brx", "ce", "cgg", "chr", "ckb", "da", "dv", "ee", "el",
                 "eo", "es", "eu", "fo", "fur", "gsw", "ha", "haw", "hu", "jgo", "jmc", "ka", "kaj", "kcg", "kk", "kkj",
                 "kl", "ks", "ksb", "ku", "ky", "lb", "lg", "mas", "mgo", "ml", "mn", "mr", "nah", "nb", "nd", "ne", "nn",
                 "nnh", "no", "nr", "ny", "nyn", "om", "or", "os", "pap", "ps", "rm", "rof", "rwk", "saq", "sd", "sdh",
                 "seh", "sn", "so", "sq", "ss", "ssy", "st", "syr", "ta", "te", "teo", "tig", "tk", "tn", "tr", "ts",
                 "ug", "uz", "ve", "vo", "vun", "wae", "xh", "xog":
                // da: "n = 1 or t != 0 and i = 0,1" (t = 0 for an integer).
                return n == 1 ? "one" : "other"

            // one: i = 1 and v = 0
            case "ast", "ca", "de", "en", "et", "fi", "fy", "gl", "ia", "io", "it", "ji", "lij", "nl", "pt_PT", "sc",
                 "scn", "sv", "sw", "ur", "yi":
                return i == 1 ? "one" : "other"

            // one: i = 0 or n = 1
            case "am", "as", "bn", "doi", "fa", "gu", "hi", "kn", "pcm", "zu":
                return i == 0 || n == 1 ? "one" : "other"

            // one: i = 0,1
            case "ff", "hy", "kab":
                return i == 0 || i == 1 ? "one" : "other"

            // one: i = 0..1
            case "pt":
                return i >= 0 && i <= 1 ? "one" : "other"

            // one: i = 0,1; many: e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
            case "fr":
                if i == 0 || i == 1 { return "one" }
                if i != 0 && i % 1_000_000 == 0 { return "many" }
                return "other"

            // one: n = 0..1 (si: "n = 0,1 or i = 0 and f = 1")
            case "ak", "bho", "guw", "ln", "mg", "nso", "pa", "si", "ti", "wa":
                return n <= 1 ? "one" : "other"

            // one: n = 0..1 or n = 11..99
            case "tzm":
                return n <= 1 || (n >= 11 && n <= 99) ? "one" : "other"

            // one: t = 0 and i % 10 = 1 and i % 100 != 11 or t != 0
            // mk: one: v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
            case "is", "mk":
                return i10 == 1 && i100 != 11 ? "one" : "other"

            // one: v = 0 and i = 1,2,3 or v = 0 and i % 10 != 4,6,9 or v != 0 and f % 10 != 4,6,9
            case "ceb", "fil", "tl":
                return (i >= 1 && i <= 3) || (i10 != 4 && i10 != 6 && i10 != 9) ? "one" : "other"

            // zero: n % 10 = 0 or n % 100 = 11..19 or v = 2 and f % 100 = 11..19
            // one: n % 10 = 1 and n % 100 != 11 or v = 2 and f % 10 = 1 and f % 100 != 11 or v != 2 and f % 10 = 1
            case "lv", "prg":
                if n10 == 0 || (n100 >= 11 && n100 <= 19) { return "zero" }
                if n10 == 1 && n100 != 11 { return "one" }
                return "other"

            // zero: n = 0; one: i = 0,1 and n != 0
            case "lag":
                if n == 0 { return "zero" }
                if (i == 0 || i == 1) && n != 0 { return "one" }
                return "other"

            // zero: n = 0; one: n = 1
            case "ksh":
                if n == 0 { return "zero" }
                if n == 1 { return "one" }
                return "other"

            // one: n = 1; two: n = 2
            case "iu", "naq", "sat", "se", "sma", "smi", "smj", "smn", "sms":
                if n == 1 { return "one" }
                if n == 2 { return "two" }
                return "other"

            // one: i = 0 or n = 1; few: n = 2..10
            case "shi":
                if i == 0 || n == 1 { return "one" }
                if n >= 2 && n <= 10 { return "few" }
                return "other"

            // one: i = 1 and v = 0; few: v != 0 or n = 0 or n % 100 = 2..19
            case "ro", "mo":
                if i == 1 { return "one" }
                if n == 0 || (n100 >= 2 && n100 <= 19) { return "few" }
                return "other"

            // one: v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
            // few: v = 0 and i % 10 = 2..4 and i % 100 != 12..14 or f % 10 = 2..4 and f % 100 != 12..14
            case "bs", "hr", "sh", "sr":
                if i10 == 1 && i100 != 11 { return "one" }
                if i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14) { return "few" }
                return "other"

            // one: n = 1,11; two: n = 2,12; few: n = 3..10,13..19
            case "gd":
                if n == 1 || n == 11 { return "one" }
                if n == 2 || n == 12 { return "two" }
                if (n >= 3 && n <= 10) || (n >= 13 && n <= 19) { return "few" }
                return "other"

            // one: v = 0 and i % 100 = 1; two: v = 0 and i % 100 = 2; few: v = 0 and i % 100 = 3..4 or v != 0
            // dsb, hsb: the same for integers (their f clauses need a fraction)
            case "sl", "dsb", "hsb":
                if i100 == 1 { return "one" }
                if i100 == 2 { return "two" }
                if i100 >= 3 && i100 <= 4 { return "few" }
                return "other"

            // one: i = 1 and v = 0; two: i = 2 and v = 0; many: v = 0 and n != 0..10 and n % 10 = 0
            case "he", "iw":
                if i == 1 { return "one" }
                if i == 2 { return "two" }
                if n > 10 && n10 == 0 { return "many" }
                return "other"

            // one: i = 1 and v = 0; few: i = 2..4 and v = 0; many: v != 0
            case "cs", "sk":
                if i == 1 { return "one" }
                if i >= 2 && i <= 4 { return "few" }
                return "other"

            // one: i = 1 and v = 0; few: v = 0 and i % 10 = 2..4 and i % 100 != 12..14
            // many: v = 0 and i != 1 and i % 10 = 0..1 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 12..14
            case "pl":
                if i == 1 { return "one" }
                if i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14) { return "few" }
                if (i != 1 && i10 >= 0 && i10 <= 1) || (i10 >= 5 && i10 <= 9) || (i100 >= 12 && i100 <= 14) {
                    return "many"
                }
                return "other"

            // one: n % 10 = 1 and n % 100 != 11; few: n % 10 = 2..4 and n % 100 != 12..14
            // many: n % 10 = 0 or n % 10 = 5..9 or n % 100 = 11..14
            case "be":
                if n10 == 1 && n100 != 11 { return "one" }
                if n10 >= 2 && n10 <= 4 && !(n100 >= 12 && n100 <= 14) { return "few" }
                if n10 == 0 || (n10 >= 5 && n10 <= 9) || (n100 >= 11 && n100 <= 14) { return "many" }
                return "other"

            // one: n % 10 = 1 and n % 100 != 11..19; few: n % 10 = 2..9 and n % 100 != 11..19; many: f != 0
            case "lt":
                let teen = n100 >= 11 && n100 <= 19
                if n10 == 1 && !teen { return "one" }
                if n10 >= 2 && n10 <= 9 && !teen { return "few" }
                return "other"

            // one: n = 1; few: n = 0 or n % 100 = 2..10; many: n % 100 = 11..19
            case "mt":
                if n == 1 { return "one" }
                if n == 0 || (n100 >= 2 && n100 <= 10) { return "few" }
                if n100 >= 11 && n100 <= 19 { return "many" }
                return "other"

            // one: v = 0 and i % 10 = 1 and i % 100 != 11; few: v = 0 and i % 10 = 2..4 and i % 100 != 12..14
            // many: v = 0 and i % 10 = 0 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 11..14
            case "ru", "uk":
                if i10 == 1 && i100 != 11 { return "one" }
                if i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14) { return "few" }
                if i10 == 0 || (i10 >= 5 && i10 <= 9) || (i100 >= 11 && i100 <= 14) { return "many" }
                return "other"

            // one: n % 10 = 1 and n % 100 != 11,71,91; two: n % 10 = 2 and n % 100 != 12,72,92
            // few: n % 10 = 3..4,9 and n % 100 != 10..19,70..79,90..99; many: n != 0 and n % 1000000 = 0
            case "br":
                if n10 == 1 && n100 != 11 && n100 != 71 && n100 != 91 { return "one" }
                if n10 == 2 && n100 != 12 && n100 != 72 && n100 != 92 { return "two" }
                if (n10 == 3 || n10 == 4 || n10 == 9)
                    && !((n100 >= 10 && n100 <= 19) || (n100 >= 70 && n100 <= 79) || (n100 >= 90 && n100 <= 99)) {
                    return "few"
                }
                if n != 0 && n % 1_000_000 == 0 { return "many" }
                return "other"

            // one: n = 1; two: n = 2; few: n = 3..6; many: n = 7..10
            case "ga":
                if n == 1 { return "one" }
                if n == 2 { return "two" }
                if n >= 3 && n <= 6 { return "few" }
                if n >= 7 && n <= 10 { return "many" }
                return "other"

            // one: v = 0 and i % 10 = 1; two: v = 0 and i % 10 = 2; few: v = 0 and i % 100 = 0,20,40,60,80
            // many: v != 0
            case "gv":
                if i10 == 1 { return "one" }
                if i10 == 2 { return "two" }
                if i100 == 0 || i100 == 20 || i100 == 40 || i100 == 60 || i100 == 80 { return "few" }
                return "other"

            // zero: n = 0; one: n = 1
            // two: n % 100 = 2,22,42,62,82 or n % 1000 = 0 and n % 100000 = 1000..20000,40000,60000,80000
            //      or n != 0 and n % 1000000 = 100000
            // few: n % 100 = 3,23,43,63,83; many: n != 1 and n % 100 = 1,21,41,61,81
            case "kw":
                if n == 0 { return "zero" }
                if n == 1 { return "one" }
                let n100000 = n % 100_000
                if n100 == 2 || n100 == 22 || n100 == 42 || n100 == 62 || n100 == 82
                    || (n % 1000 == 0 && ((n100000 >= 1000 && n100000 <= 20000) || n100000 == 40000
                                          || n100000 == 60000 || n100000 == 80000))
                    || (n != 0 && n % 1_000_000 == 100_000) {
                    return "two"
                }
                if n100 == 3 || n100 == 23 || n100 == 43 || n100 == 63 || n100 == 83 { return "few" }
                if n != 1 && (n100 == 1 || n100 == 21 || n100 == 41 || n100 == 61 || n100 == 81) { return "many" }
                return "other"

            // zero: n = 0; one: n = 1; two: n = 2; few: n % 100 = 3..10; many: n % 100 = 11..99
            case "ar", "ars":
                if n == 0 { return "zero" }
                if n == 1 { return "one" }
                if n == 2 { return "two" }
                if n100 >= 3 && n100 <= 10 { return "few" }
                if n100 >= 11 && n100 <= 99 { return "many" }
                return "other"

            // zero: n = 0; one: n = 1; two: n = 2; few: n = 3; many: n = 6
            case "cy":
                switch n {
                case 0: return "zero"
                case 1: return "one"
                case 2: return "two"
                case 3: return "few"
                case 6: return "many"
                default: return "other"
                }

            // bm bo dz id ig ii in ja jbo jv kde kea km ko lkt lo ms my nqo osa sah ses sg su th to vi wo yo yue zh,
            // and every language ICU has no rules for (root).
            default:
                return "other"
            }
        }
    }
}
