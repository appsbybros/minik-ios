import CryptoKit
import ImageIO
import UIKit
import XCTest
@testable import MinikTripleShot

/// The Android resources on iOS (DESIGN 2.7 and 5): string tables, the language rule, plural rules, android.R
/// strings, R constants, drawable sizes and the bundled files written by Scripts/tripleshot-sync-resources.py.
///
/// The expected texts are aapt2's own results for the Android XML (aapt2 2.19-12006047 and 2.20-13193326, read back
/// from resources.arsc): whitespace runs collapse to one space, \' \n and &amp; are resolved, format specifiers stay
/// in Java syntax. The colours are aapt2's ARGB values. The image sizes are the file headers (also checked with an
/// independent decoder) — Android's intrinsic size for drawable-nodpi. The plural vectors are icu4j-68.2 (the ICU of
/// Android 12) `PluralRules.forLocale(locale).select(quantity)`. The android.R.string.cancel texts are the
/// framework's (Android SDK android-36 data/res).
final class ResourcesTests: XCTestCase {

    override func tearDown() {
        AResources.localeOverride = nil
        super.tearDown()
    }

    // MARK: - Strings

    func testHebrewDefaultStrings() {
        XCTAssertEqual(AResources.text(R.string.app_name, language: "he"), "טריפל שוט")
        // values/minik_swish_bot.xml has "\n" and a run of three spaces before 🏀: aapt2 keeps one space.
        XCTAssertEqual(AResources.text(R.string.minik_swish_bot_result_summary, language: "he"),
                       "🤖 %1$s — ניקוד: %2$d נק׳\n🧠 שיא רצף ידע: %3$d 🏀 שיא רצף קליעות: %4$d")
        XCTAssertEqual(AResources.text(R.string.minik_swish_horse_penalties, language: "he"), "אני %1$d/5 • מיניק %2$d/5")
        XCTAssertEqual(AResources.text(R.string.minik_swish_opponent_streaks_line, language: "he"),
                       "🧠 רצף ידע: %1$d 🏀 רצף קליעות: %2$d")
        XCTAssertEqual(AResources.text(R.string.minik_swish_live_hud_players, language: "he"), "לייב %1$d/4")
        XCTAssertEqual(AResources.text(R.string.minik_swish_one_on_one_shot_quality, language: "he"), "איכות הזריקה • %1$d%%")
        XCTAssertEqual(AResources.text(R.string.minik_swish_horse_move_help_short, language: "he"),
                       "בחרו מקום לזריקה ולחצו „מוכן — קבע מיקום”.")
        // "?" is plain text for aapt2 (an attribute reference needs a name).
        XCTAssertEqual(AResources.text(R.string.minik_swish_tutorial_help_symbol, language: "he"), "?")
        XCTAssertEqual(AResources.text(R.string.minik_swish_privacy_policy_url, language: "he"), "")
        XCTAssertEqual(AResources.text(android.R.string.cancel, language: "he"), "ביטול")
    }

    func testEnglishStrings() {
        XCTAssertEqual(AResources.text(R.string.app_name, language: "en"), "Triple Shot")
        XCTAssertEqual(AResources.text(R.string.minik_swish_horse_bot_turn, language: "en"), "MINIK's turn")
        XCTAssertEqual(AResources.text(R.string.minik_swish_info_privacy_title, language: "en"), "Information & privacy")
        XCTAssertEqual(AResources.text(R.string.minik_swish_character_stats_defense, language: "en"), "Defense & handle")
        XCTAssertEqual(AResources.text(R.string.minik_swish_one_on_one_shot_quality_default, language: "en"), "Shot quality • 0%")
        XCTAssertEqual(AResources.text(R.string.minik_swish_horse_penalties, language: "en"), "Me %1$d/5 • MINIK %2$d/5")
        XCTAssertEqual(AResources.text(R.string.minik_swish_bot_result_summary, language: "en"),
                       "🤖 %1$s — Score: %2$d pts\n🧠 Best knowledge streak: %3$d 🏀 Best shooting streak: %4$d")
        XCTAssertEqual(AResources.text(R.string.minik_swish_horse_move_help_short, language: "en"),
                       "Choose a shooting spot, then tap “Ready — set spot”.")
        XCTAssertEqual(AResources.text(R.string.minik_swish_one_on_one_spin, language: "en"),
                       "Spin attempt — move into any space you create.")
        let howTo = AResources.text(R.string.minik_swish_team_intro_how_to, language: "en")
        XCTAssertEqual(howTo,
                       "Move: swipe the court.\nPass: tap a teammate.\nShoot: hold empty court for about one second, then release. "
                       + "We aim at the basket; distance, the defender and your character's shooting ability determine the chance. "
                       + "A full meter helps but does not guarantee a basket. Drive close for a layup or dunk.\n"
                       + "Alley-oop: double-tap a teammate.\nScreen: hold a teammate.\n"
                       + "Defense: move close and tap anywhere on the court. Tap a teammate to switch defender.\n"
                       + "Shoot before the 24-second shot clock expires.\n"
                       + "Change hands: swipe left-right-left. Repeat quickly for a behind-the-back crossover.\n"
                       + "Spin: draw a small circle while dribbling. Quick repeats help, but a guard can still stay with you.\n"
                       + "A teammate comes to screen a close guard. Move around the screen; do not try to walk through the defender.")
        XCTAssertEqual(howTo.filter { $0 == "\n" }.count, 9)
        XCTAssertEqual(AResources.text(android.R.string.cancel, language: "en"), "Cancel")
    }

    /// The keys the Android device tests read (spec 24 §6.1), in both tables.
    func testDeviceTestKeysInBothLanguages() {
        let pairs: [(AStringRes, String, String)] = [
            (R.string.minik_swish_team_intro_start, "Start game", "מתחילים"),
            (R.string.minik_swish_horse_ready_to_aim, "Ready — lock spot", "מוכן — קבע מיקום"),
            (R.string.minik_swish_one_on_one_exit_game, "Exit game", "יציאה מהמשחק"),
            (R.string.minik_swish_team_home, "Home", "לתפריט"),
            (R.string.minik_swish_bot_setup_title, "Play vs bot", "משחק נגד בוט"),
            (R.string.minik_swish_bot_mode_game, "Game", "משחק"),
            (R.string.daily_court_journey, "Daily court journey", "אתגר יומי"),
        ]
        for (id, english, hebrew) in pairs {
            XCTAssertEqual(AResources.text(id, language: "en"), english, id)
            XCTAssertEqual(AResources.text(id, language: "he"), hebrew, id)
        }
    }

    func testEnglishFallsBackToValuesPerResource() {
        // translatable="false", only in values/: Android takes it from the default resources.
        XCTAssertEqual(AResources.english.untranslated, ["minik_swish_privacy_policy_url"])
        XCTAssertEqual(AResources.text(R.string.minik_swish_privacy_policy_url, language: "en"), "")
        XCTAssertEqual(AResources.hebrew.strings.count, 510)
        XCTAssertEqual(AResources.english.strings.count, 510)
        XCTAssertEqual(Set(AResources.hebrew.strings.keys), Set(AResources.english.strings.keys))
        XCTAssertEqual(AResources.hebrew.language, "he")
        XCTAssertEqual(AResources.english.language, "en")
    }

    // MARK: - Language (DESIGN 2.7)

    func testTableLanguageIsEnglishOnlyForEnglish() {
        for tag in ["en", "en-US", "en-GB", "en-IL", "en-Latn-US"] {
            XCTAssertEqual(AResources.tableLanguage(ALocale.forLanguageTag(tag)), "en", tag)
        }
        // values/ is the default: Hebrew for he/iw and for every third language, LTR or RTL.
        for tag in ["he", "he-IL", "iw", "iw-IL", "fr-FR", "ar", "ar-SA", "ru", "fa-IR", "zh-Hant-TW", "es-419", "und"] {
            XCTAssertEqual(AResources.tableLanguage(ALocale.forLanguageTag(tag)), "he", tag)
        }
    }

    func testLanguageFollowsTheConfigurationLocale() {
        AResources.localeOverride = nil
        let first = AConfiguration.locales.locales.first ?? ALocale.getDefault()
        XCTAssertEqual(AResources.configurationLocale, first)
        XCTAssertEqual(AResources.language, first.language == "en" ? "en" : "he")
        AResources.localeOverride = ALocale("en", "GB")
        XCTAssertEqual(AResources.language, "en")
        XCTAssertEqual(AResources.languageOverride, "en-GB")
        AResources.languageOverride = "he-IL"
        XCTAssertEqual(AResources.configurationLocale, ALocale("he", "IL"))
        XCTAssertEqual(AResources.language, "he")
        AResources.languageOverride = nil
        XCTAssertNil(AResources.localeOverride)
    }

    func testGlobalGettersFollowTheLanguage() {
        AResources.localeOverride = ALocale("en")
        XCTAssertEqual(AResources.language, "en")
        XCTAssertEqual(getString(R.string.app_name), "Triple Shot")
        XCTAssertEqual(getText(R.string.triple_shot_title), "TRIPLE SHOT")
        XCTAssertEqual(AResources.getString(R.string.triple_shot_home), "Home")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 1), "1 topic selected")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 3), "%d topics selected")
        XCTAssertEqual(getString(android.R.string.cancel), "Cancel")
        AResources.localeOverride = ALocale("he", "IL")
        XCTAssertEqual(getString(R.string.app_name), "טריפל שוט")
        XCTAssertEqual(getString(R.string.triple_shot_home), "לתפריט")
        XCTAssertEqual(getString(android.R.string.cancel), "ביטול")
        XCTAssertEqual(AResources.getQuantityString(R.plurals.minik_swish_topics_count, 2), "%d נושאים נבחרו")
    }

    /// A French device: Android shows the Hebrew values/ texts, chooses their plural items with the FRENCH rules
    /// (0 and 1 are "one") and shows the framework's own "Annuler".
    func testThirdLanguageDeviceGetsHebrewTextsAndItsOwnRules() {
        AResources.localeOverride = ALocale("fr", "FR")
        XCTAssertEqual(AResources.language, "he")
        XCTAssertEqual(getString(R.string.app_name), "טריפל שוט")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 0), "נושא אחד נבחר")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 1), "נושא אחד נבחר")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 3), "%d נושאים נבחרו")
        XCTAssertEqual(getString(android.R.string.cancel), "Annuler")
        // Filipino: 3, 5, 7, 8 and 10 are "one" (i % 10 != 4, 6, 9), so 3 topics show the singular Hebrew text.
        AResources.localeOverride = ALocale.forLanguageTag("fil-PH")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 3), "נושא אחד נבחר")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 4), "%d נושאים נבחרו")
        XCTAssertEqual(getString(android.R.string.cancel), "Kanselahin")
        // Arabic: RTL device, Hebrew texts, Arabic framework text.
        AResources.localeOverride = ALocale("ar")
        XCTAssertEqual(getString(R.string.triple_shot_home), "לתפריט")
        XCTAssertEqual(getString(android.R.string.cancel), "إلغاء")
    }

    /// android.R.string.cancel is resolved by the framework for the device language (English when the framework
    /// has no translation), not by the app's values folders.
    func testFrameworkCancelFollowsTheDeviceLanguage() {
        let expected: [(String, String)] = [
            ("he", "ביטול"), ("iw", "ביטול"), ("he-IL", "ביטול"), ("en", "Cancel"), ("en-GB", "Cancel"),
            ("fr-CA", "Annuler"), ("de-DE", "Abbrechen"), ("es-419", "Cancelar"), ("pt-BR", "Cancelar"),
            ("pt-PT", "Cancelar"), ("ru", "Отмена"), ("uk", "Скасувати"), ("ar-SA", "إلغاء"), ("fa", "لغو"),
            ("zh-Hans-CN", "取消"), ("zh-Hant-TW", "取消"), ("ja", "キャンセル"), ("ko", "취소"), ("id", "Batal"),
            ("in", "Batal"), ("sr", "Откажи"), ("sr-Latn", "Otkaži"), ("sr-Latn-RS", "Otkaži"), ("fil", "Kanselahin"),
            ("tl", "Kanselahin"), ("nb", "Avbryt"), ("km", "បោះ\u{200B}បង់\u{200B}"), ("ga", "Cancel"), ("yi", "Cancel"),
            ("und", "Cancel"),
        ]
        for (tag, text) in expected {
            XCTAssertEqual(AResources.text(android.R.string.cancel, locale: ALocale.forLanguageTag(tag)), text, tag)
        }
        XCTAssertEqual(AResources.framework["cancel"]?.count, 75)
        XCTAssertEqual(AResources.framework["cancel"]?[""], "Cancel")
    }

    func testFormattedGettersUseJavaFormat() {
        AResources.localeOverride = ALocale("he")
        XCTAssertEqual(getString(R.string.minik_swish_live_hud_players, 3), "לייב 3/4")
        XCTAssertEqual(getString(R.string.minik_swish_horse_title, "MINIK"), "חיובים נגד MINIK")
        XCTAssertEqual(getString(R.string.minik_swish_character_bot_result_win, "Gaya", 7, 5), "ניצחתם את Gaya! 7–5 🏆")
        XCTAssertEqual(getString(R.string.minik_swish_progress_accuracy_format, 80), "80% נכונות")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 3, 3), "3 נושאים נבחרו")
        AResources.localeOverride = ALocale("en", "US")
        XCTAssertEqual(getQuantityString(R.plurals.minik_swish_topics_count, 3, 3), "3 topics selected")
        XCTAssertEqual(getString(R.string.minik_swish_one_on_one_shot_quality, 72), "Shot quality • 72%")
        // The double spaces of values-en collapse (aapt2): "Us %1$d  •  %2$d Them" shows "Us 2 • 3 Them".
        XCTAssertEqual(getString(R.string.minik_swish_team_score_format, 2, 3), "Us 2 • 3 Them")
        // Repeated and reordered positional arguments (GameFragment:3254-3274).
        XCTAssertEqual(getString(R.string.minik_swish_character_bot_result_tie, "Gaya", 4), "Tie with Gaya: 4–4 🤝")
        XCTAssertEqual(getString(R.string.minik_swish_character_bot_result_loss, "Gaya", 2, 5), "You lost to Gaya: 5–2")
        XCTAssertEqual(getString(R.string.minik_swish_feedback_answer_partial, 50), "🟡 Partially correct (50%)")
        // Never formatted without arguments: the literal "0%" stays.
        XCTAssertEqual(getString(R.string.minik_swish_one_on_one_shot_quality_default), "Shot quality • 0%")
        XCTAssertEqual(AResources.getString(R.string.minik_swish_one_on_one_shot_quality, 9), "Shot quality • 9%")
    }

    // MARK: - Plurals

    /// icu4j-68.2 `PluralRules.forLocale(locale).select(q)` (Android 12): quantities 0...199, then `big`, then
    /// `negative`; z = zero, o = one, t = two, f = few, m = many, x = other. The whole 0...1099 range of all 234
    /// ICU locale ids was compared as well (scratch harness, 0 differences).
    private static let icu68: [(id: String, head: String, big: String, negative: String)] = [
        ("he", "xotxxxxxxxxxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxx", "mmxmmmxmmmmmmxmxxxmm", "xxxxxxmx"),
        ("iw", "xotxxxxxxxxxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxxmxxxxxxxxx", "mmxmmmxmmmmmmxmxxxmm", "xxxxxxmx"),
        ("en", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("en_GB", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("ar", "zotffffffffmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmxxxffffffffmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm", "xxxxxxmxxxxxxxxxmmxx", "otffmmxm"),
        ("fr", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "mmxmxmxxxxxxxxxxxxxm", "xxxxxxxx"),
        ("ru", "mofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmm", "mmommmmmmmmmmomommmm", "xxxxxxmx"),
        ("uk", "mofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmm", "mmommmmmmmmmmomommmm", "xxxxxxmx"),
        ("pl", "mofffmmmmmmmmmmmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmmmmmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmm", "mmmmmmmmmmmmmmmmmmmm", "xxxxxxmx"),
        ("fil", "ooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxoox", "oooooooooooooooooooo", "oooooooo"),
        ("tl", "ooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxooxooooxoxoox", "oooooooooooooooooooo", "oooooooo"),
        ("pt", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("pt_PT", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("pt_AO", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("es", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("de", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("ro", "foffffffffffffffffffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxffffffffffffffffffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxffxx", "xffffxxx"),
        ("mt", "fofffffffffmmmmmmmmmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxfffffffffmmmmmmmmmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxmmxx", "offfmxxx"),
        ("cy", "zotfxxmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "otfxxxxx"),
        ("lv", "zoxxxxxxxxzzzzzzzzzzzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzzzzzzzzzzzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxxzoxxxxxxxx", "zzozzzxzzzzzzozozzzz", "oxxxzozx"),
        ("lt", "xoffffffffxxxxxxxxxxxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxxxxxxxxxxxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffffxoffffffff", "xxoxxxfxxxxxxoxoxxxx", "offfxoxf"),
        ("br", "xotffxxxxfxxxxxxxxxxxotffxxxxfxotffxxxxfxotffxxxxfxotffxxxxfxotffxxxxfxxxxxxxxxxxotffxxxxfxxxxxxxxxxxotffxxxxfxxxxxxxxxxxotffxxxxfxotffxxxxfxotffxxxxfxotffxxxxfxotffxxxxfxxxxxxxxxxxotffxxxxfxxxxxxxxxx", "mmomxmxxxxxxxoxoxxxm", "otfxxoxx"),
        ("kw", "zotfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxxxmtfxxxxxxxxxxxxxxxx", "xxmxtxxtxttttmxmxxtx", "otfxxmxx"),
        ("gv", "fotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxxfotxxxxxxxxotxxxxxxx", "ffofffxffffffofoooff", "xxxxxxfx"),
        ("gd", "xotffffffffotfffffffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "otffoxxx"),
        ("ga", "xotffffmmmmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "otffxxxx"),
        ("sl", "xotffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxotffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("cs", "xofffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("be", "mofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmm", "mmommmmmmmmmmomommmm", "offmmomm"),
        ("shi", "oofffffffffxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "offfxxxx"),
        ("lag", "zoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("ksh", "zoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("tzm", "ooxxxxxxxxxoooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxooxx"),
        ("is", "xoxxxxxxxxxxxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxxxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("mk", "xoxxxxxxxxxxxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxxxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxxxoxxxxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("hi", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("fa", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("da", "xoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("si", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("ak", "ooxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "oxxxxxxx"),
        ("sr", "xofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("sr_Latn", "xofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("hr", "xofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxxxxxxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxxxofffxxxxx", "xxoxxxxxxxxxxoxoxxxx", "xxxxxxxx"),
        ("se", "xotxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "otxxxxxx"),
        ("ja", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("zh_Hant_TW", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("in", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
        ("root", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxx", "xxxxxxxx"),
    ]
    private static let bigQuantities = [1000000, 2000000, 1000001, 10000000, 100000, 1000000000, 2147483647, 1100000,
                                        21000, 40000, 101000, 1000, 2000, 1001, 100, 101, 111, 1011, 120000, 3000000]
    private static let negativeQuantities = [-1, -2, -3, -5, -11, -21, -100, -2147483647]

    private static func keyword(_ code: Character) -> String {
        switch code {
        case "z": return "zero"
        case "o": return "one"
        case "t": return "two"
        case "f": return "few"
        case "m": return "many"
        default: return "other"
        }
    }

    func testPluralRulesAreAndroid12Icu() {
        for row in Self.icu68 {
            let locale = row.id == "root" ? ALocale.ROOT : ALocale.forLanguageTag(row.id)
            XCTAssertEqual(row.head.count, 200, row.id)
            for (quantity, code) in row.head.enumerated() {
                XCTAssertEqual(AResources.PluralRules.select(locale, quantity), Self.keyword(code), "\(row.id) \(quantity)")
            }
            for (quantity, code) in zip(Self.bigQuantities, row.big) {
                XCTAssertEqual(AResources.PluralRules.select(locale, quantity), Self.keyword(code), "\(row.id) \(quantity)")
            }
            for (quantity, code) in zip(Self.negativeQuantities, row.negative) {
                XCTAssertEqual(AResources.PluralRules.select(locale, quantity), Self.keyword(code), "\(row.id) \(quantity)")
            }
        }
    }

    func testHebrewAndEnglishPluralRules() {
        let rules = AResources.PluralRules.self
        // Hebrew (CLDR 38): one / two / many / other.
        XCTAssertEqual(rules.select("he", 0), "other")
        XCTAssertEqual(rules.select("he", 1), "one")
        XCTAssertEqual(rules.select("he", 2), "two")
        XCTAssertEqual(rules.select("he", 3), "other")
        XCTAssertEqual(rules.select("he", 10), "other")
        XCTAssertEqual(rules.select("he", 11), "other")
        XCTAssertEqual(rules.select("he", 20), "many")
        XCTAssertEqual(rules.select("he", 21), "other")
        XCTAssertEqual(rules.select("he", 100), "many")
        XCTAssertEqual(rules.select("iw", 2), "two")
        // ICU 68 keeps the sign in the operand i: -1 and -2 are "other", -20 (n = 20) is "many".
        XCTAssertEqual(rules.select("he", -1), "other")
        XCTAssertEqual(rules.select("he", -2), "other")
        XCTAssertEqual(rules.select("he", -20), "many")
        XCTAssertEqual(rules.select("en", 0), "other")
        XCTAssertEqual(rules.select("en", 1), "one")
        XCTAssertEqual(rules.select("en", 2), "other")
        XCTAssertEqual(rules.select("en", -1), "other")
        XCTAssertEqual(rules.select("en", 21), "other")
        XCTAssertEqual(rules.select(ALocale("he", "IL"), 2), "two")
        XCTAssertEqual(rules.select(ALocale("en", "US"), 1), "one")
    }

    func testPluralSelectionFallsBackToOther() {
        // The Hebrew plurals define only "one" and "other": two and many use "other" (Resources.getQuantityText).
        XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, 1, language: "he"), "נושא אחד נבחר")
        for n in [0, 2, 3, 10, 20, 100, -1] {
            XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, n, language: "he"), "%d נושאים נבחרו")
        }
        XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, 1, language: "en"), "1 topic selected")
        for n in [0, 2, 11, 21, -1] {
            XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, n, language: "en"), "%d topics selected")
        }
        // The app asks for 3...11 topics (HomeFragment:957-962): "other" in both languages.
        for n in 3...11 {
            XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, n, locale: ALocale("he", "IL")),
                           "%d נושאים נבחרו")
            XCTAssertEqual(AResources.quantityText(R.plurals.minik_swish_topics_count, n, locale: ALocale("en", "US")),
                           "%d topics selected")
        }
        XCTAssertEqual(AResources.hebrew.plurals[R.plurals.minik_swish_topics_count]?.keys.sorted(), ["one", "other"])
        XCTAssertEqual(AResources.english.plurals[R.plurals.minik_swish_topics_count]?.keys.sorted(), ["one", "other"])
        XCTAssertTrue(AResources.hebrew.arrays.isEmpty)
        XCTAssertTrue(AResources.english.arrays.isEmpty)
    }

    // MARK: - R

    func testRConstantsAreTheAndroidNames() {
        XCTAssertEqual(R.string.minik_swish_court_enchanted_forest, "minik_swish_court_enchanted_forest")
        XCTAssertEqual(R.plurals.minik_swish_topics_count, "minik_swish_topics_count")
        XCTAssertEqual(R.drawable.zephyr_steal_side, "zephyr_steal_side")
        XCTAssertEqual(R.drawable.triple_play, "triple_play")
        XCTAssertEqual(R.mipmap.ic_launcher, "ic_launcher")
        XCTAssertEqual(R.raw.basket_swish, "basket_swish")
        XCTAssertEqual(R.id.courtView, "courtView")
        XCTAssertEqual(R.layout.fragment_triple_shot_game, "fragment_triple_shot_game")
        XCTAssertEqual(R.style.Theme_TripleShot, "Theme.TripleShot")
        XCTAssertEqual(android.R.string.cancel, "android:cancel")
        XCTAssertEqual(android.R.attr.progressBarStyleHorizontal, 16842872)
        XCTAssertEqual(android.R.attr.state_pressed, 16842919)
        XCTAssertEqual(android.R.layout.simple_spinner_item, "android:simple_spinner_item")
        XCTAssertEqual(AResourceIndex.id.count, 120)
        XCTAssertEqual(AResourceIndex.xmlDrawables, ["triple_help", "triple_pause", "triple_play", "triple_shot_answer_idle",
                                                     "triple_shot_answer_selected", "triple_shot_feedback_panel", "triple_shot_panel"])
    }

    func testColorsAreAapt2ArgbValues() {
        XCTAssertEqual(R.color.triple_shot_ink, Int(Int32(bitPattern: 0xFF12333A)))
        XCTAssertEqual(R.color.triple_shot_ink, -15584454)
        XCTAssertEqual(R.color.triple_shot_green, -16220560)          // #FF087E70
        XCTAssertEqual(R.color.triple_shot_teal, -13451352)           // #FF32BFA8
        XCTAssertEqual(R.color.triple_shot_gold, -14275)              // #FFFFC83D
        XCTAssertEqual(R.color.triple_shot_red, -1684908)             // #FFE64A54
        XCTAssertEqual(R.color.triple_shot_blue, -14124074)           // #FF287BD6
        XCTAssertEqual(R.color.triple_shot_purple, -9021482)          // #FF7657D6
        XCTAssertEqual(R.color.triple_shot_card, -851972)             // #FFF2FFFC
        XCTAssertEqual(R.color.triple_shot_white_92, -335544321)      // #EBFFFFFF
        XCTAssertEqual(R.color.triple_shot_black_35, 1493172224)      // #59000000
        XCTAssertEqual(R.color.tripleshot_launcher_background, -16575955)  // #FF03122D
        XCTAssertEqual(android.R.color.transparent, 0)
        XCTAssertEqual(ContextCompat_getColor(R.color.triple_shot_ink), R.color.triple_shot_ink)
    }

    // MARK: - Identifiers

    func testGetIdentifier() {
        // TripleShotCourtCatalog: portrait art present for sunset_pulse, absent for skyforge (Android id 0).
        XCTAssertEqual(AResources.getIdentifier("triple_shot_court_sunset_pulse_portrait", "drawable"),
                       "triple_shot_court_sunset_pulse_portrait")
        XCTAssertNil(AResources.getIdentifier("triple_shot_court_skyforge_peaks_portrait", "drawable"))
        XCTAssertNil(AResources.getIdentifier("triple_shot_court_enchanted_forest_landscape", "drawable"))
        XCTAssertEqual(AResources.getIdentifier("triple_play", "drawable"), "triple_play")
        XCTAssertEqual(AResources.getIdentifier("drawable/ball", ""), "ball")
        XCTAssertEqual(AResources.getIdentifier("com.appsbybros.minik.swish:drawable/ball", ""), "ball")
        XCTAssertNil(AResources.getIdentifier("com.other.app:drawable/ball", ""))
        XCTAssertNil(AResources.getIdentifier("ball", "string"))
        XCTAssertEqual(AResources.getIdentifier("app_name", "string"), "app_name")
        XCTAssertEqual(AResources.getIdentifier("minik_swish_topics_count", "plurals"), "minik_swish_topics_count")
        XCTAssertEqual(AResources.getIdentifier("android:string/cancel", ""), "android:cancel")
        XCTAssertEqual(AResources.getIdentifier("android:cancel", "string"), "android:cancel")
        XCTAssertNil(AResources.getIdentifier("android:string/ok", ""))
        XCTAssertEqual(AResources.getIdentifier("basket_swish", "raw"), "basket_swish")
        XCTAssertEqual(AResources.getIdentifier("courtView", "id"), "courtView")
        XCTAssertEqual(AResources.getIdentifier("fragment_triple_shot_home", "layout"), "fragment_triple_shot_home")
        XCTAssertEqual(AResources.getIdentifier("triple_shot_ink", "color"), "triple_shot_ink")
        XCTAssertEqual(AResources.getIdentifier("Theme.TripleShot", "style"), "Theme.TripleShot")
        XCTAssertEqual(AResources.getIdentifier("ic_launcher", "mipmap"), "ic_launcher")
        XCTAssertNil(AResources.getIdentifier("", "drawable"))
        XCTAssertNil(AResources.getIdentifier("nope", "drawable"))
    }

    // MARK: - Drawables

    private static let sampleSizes: [(String, Int, Int)] = [
        ("ball", 124, 123),                                     // drawable/, WebP VP8X
        ("basketball", 159, 160),                               // drawable/, WebP VP8X
        ("basket_bob_00", 105, 238),                            // WebP VP8X
        ("basket_comet_ground_00", 208, 333),                   // WebP VP8L
        ("triple_shot_court_neon_falls_landscape", 1672, 941),  // WebP VP8
        ("triple_shot_court_sunset_pulse_portrait", 1024, 1536),
        ("triple_shot_court_background", 1024, 1536),           // PNG
        ("character_preview_bob", 480, 480),                    // PNG
        ("zephyr_steal_side", 392, 382),
        ("tripleshot_launcher_art", 768, 768),
    ]

    func testDrawablePixelSizes() {
        for (name, width, height) in Self.sampleSizes {
            let size = AResources.drawablePixelSize(name)
            XCTAssertEqual(size.width, width, name)
            XCTAssertEqual(size.height, height, name)
            XCTAssertTrue(AResources.drawableExists(name), name)
        }
        let xml = AResources.drawablePixelSize(R.drawable.triple_shot_panel)
        XCTAssertEqual(xml.width, -1)
        XCTAssertEqual(xml.height, -1)
        XCTAssertTrue(AResources.drawableExists(R.drawable.triple_shot_panel))
        XCTAssertNil(AResources.drawableURL(R.drawable.triple_shot_panel))
        XCTAssertNil(AResources.image(R.drawable.triple_shot_panel))
        XCTAssertFalse(AResources.drawableExists("nope"))
    }

    func testDrawableTableMatchesDrawableSizesJson() throws {
        let data = try Data(contentsOf: AResources.resURL.appendingPathComponent("drawable-sizes.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertEqual(json.count, 725)
        XCTAssertEqual(AResources.drawables.count, json.count)
        for (name, entry) in json {
            let size = AResources.drawablePixelSize(name)
            XCTAssertEqual(size.width, entry["width"] as? Int, name)
            XCTAssertEqual(size.height, entry["height"] as? Int, name)
            XCTAssertEqual(AResources.drawableURL(name)?.lastPathComponent,
                           (entry["file"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }, name)
        }
    }

    func testImageIOReadsEveryImageAtItsAndroidSize() throws {
        for (name, drawable) in AResources.drawables {
            let url = try XCTUnwrap(AResources.drawableURL(name))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), name)
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], name)
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, drawable.width, name)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, drawable.height, name)
        }
    }

    func testDecodedImagesArePixelSized() throws {
        for (name, width, height) in Self.sampleSizes {
            let image = try XCTUnwrap(AResources.image(name), name)
            XCTAssertEqual(image.scale, 1, name)
            XCTAssertEqual(image.size, CGSize(width: width, height: height), name)
            let cgImage = try XCTUnwrap(AResources.cgImage(name), name)
            XCTAssertEqual(cgImage.width, width, name)
            XCTAssertEqual(cgImage.height, height, name)
            XCTAssertTrue(AResources.image(name) === image, "cached: \(name)")
        }
    }

    func testIntrinsicSizeScalesOnlyDefaultDensityImages() {
        let dpi = Float(AResources.displayMetrics.densityDpi)
        let ball = AResources.drawableIntrinsicSize(R.drawable.ball)          // drawable/ = mdpi
        XCTAssertEqual(ball.width, Int(Float(124) * (dpi / 160) + 0.5))
        XCTAssertEqual(ball.height, Int(Float(123) * (dpi / 160) + 0.5))
        let sprite = AResources.drawableIntrinsicSize(R.drawable.zephyr_steal_side)  // drawable-nodpi
        XCTAssertEqual(sprite.width, 392)
        XCTAssertEqual(sprite.height, 382)
    }

    // MARK: - Raw, assets and the source manifest

    func testRawAndAssets() throws {
        for name in [R.raw.basket_bounce, R.raw.basket_catch, R.raw.basket_swish, R.raw.beach_version_36_to_45] {
            let url = try XCTUnwrap(AResources.rawURL(name), name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
        }
        XCTAssertNil(AResources.rawURL("nope"))
        let words = try AResources.openAsset("question_banks/words.xml")
        XCTAssertEqual(String(decoding: words.prefix(5), as: UTF8.self), "<?xml")
        XCTAssertTrue(AResources.assetExists("question_banks/en/english.xml"))
        XCTAssertTrue(AResources.assetExists("question_banks/arithmetic.xml"))
        XCTAssertFalse(AResources.assetExists("question_banks"))
        XCTAssertFalse(AResources.assetExists("question_banks/missing.xml"))
        XCTAssertThrowsError(try AResources.openAsset("question_banks/missing.xml")) { error in
            XCTAssertTrue(error is AResources.FileNotFoundException)
        }
    }

    func testBundledFilesAreTheAndroidBytes() throws {
        let data = try Data(contentsOf: AResources.resURL.appendingPathComponent("android-source.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let android = try XCTUnwrap(manifest["android"] as? [String: Any])
        XCTAssertEqual(android["commit"] as? String, "6c38131")
        let files = try XCTUnwrap(manifest["files"] as? [String: String])
        XCTAssertEqual(files.count, 762)   // 725 images + 15 raw + 22 question banks
        // Android's Ogg Vorbis raw files are bundled as CAF/ALAC conversions (AVAudioFile cannot read Ogg).
        let converted = try XCTUnwrap(manifest["converted"] as? [String: [String: String]])
        XCTAssertEqual(converted.count, 10)
        XCTAssertEqual(converted["raw/basket_menu.caf"]?["source"], "app/src/main/res/raw/basket_menu.ogg")
        XCTAssertTrue(converted.keys.allSatisfy { files[$0] != nil && $0.hasSuffix(".caf") })
        XCTAssertEqual(files.keys.filter { $0.hasPrefix("assets/question_banks/") }.count, 22)
        let generated = try XCTUnwrap(manifest["generated"] as? [String: String])
        XCTAssertEqual(generated.keys.sorted(),
                       ["R.swift", "drawable-sizes.json", "strings/android.json", "strings/en.json", "strings/he.json"])
        // R.swift is compiled, not necessarily bundled; every other file must be the generated / Android bytes.
        for (path, sha256) in files.merging(generated, uniquingKeysWith: { a, _ in a }) where path != "R.swift" {
            let bytes = try Data(contentsOf: AResources.resURL.appendingPathComponent(path))
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, sha256, path)
        }
    }

    // MARK: - Display metrics

    func testDisplayMetricsArePixels() {
        let metrics = AResources.displayMetrics
        XCTAssertEqual(metrics.density, Float(UIScreen.main.scale))
        XCTAssertEqual(AResources.density, metrics.density)
        XCTAssertEqual(metrics.scaledDensity, metrics.density)
        XCTAssertEqual(metrics.densityDpi, Int((metrics.density * 160).rounded()))
        XCTAssertGreaterThan(metrics.widthPixels, 0)
        XCTAssertGreaterThan(metrics.heightPixels, 0)
        XCTAssertEqual(dp(10), 10 * metrics.density)
        XCTAssertEqual(dp(Float(1.5)), Float(1.5) * metrics.density)
        XCTAssertEqual(dp(18), Float(18) * AResources.density)
    }

    func testDensityIsReadOffTheMainThreadToo() {
        let main = AResources.density
        let done = expectation(description: "background density")
        DispatchQueue.global().async {
            XCTAssertEqual(AResources.density, main)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
