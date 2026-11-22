import Foundation

/// iOS payment model (CLAUDE.md): the iOS-only texts of the full-game purchase, in the app's six languages. They are
/// not in `AmuduCatalog.json`, which is generated from Android and checked by `Scripts/audit-amudu.py`. The language
/// is chosen exactly as `AppText` chooses it (`AppText.language`).
enum StoreText {
    /// Column order of `table`.
    static let languages = ["en", "he", "es", "ar", "hi", "nl"]

    enum Key: String, CaseIterable {
        case title
        case intro
        case featurePlayers
        case featureCharacters
        case featureArenas
        case featureBalls
        case featurePaint
        case featureChallenges
        case oneTime
        case buy
        case restore
        case thanksTitle
        case thanksBody
        case loading
        case offline
        case notAnswering
        case productUnavailable
        case purchasesNotAllowed
        case reload
        case working
        case pending
        case purchaseFailed
        case restoreFailed
        case nothingToRestore
        case settingsOwned
        case settingsNotOwned
        case paintTomorrow
        case challengeLocked
        case roomFull
    }

    static let table: [Key: [String]] = [
        .title: ["Unlock the full game", "פתיחת המשחק המלא", "Desbloquea el juego completo", "افتح اللعبة الكاملة",
                 "पूरा गेम अनलॉक करें", "Ontgrendel het volledige spel"],
        .intro: ["The full game adds:", "המשחק המלא מוסיף:", "El juego completo añade:", "تضيف اللعبة الكاملة:",
                 "पूरे गेम में यह भी मिलता है:", "Het volledige spel voegt toe:"],
        // {0}: SpudAccess.fullPlayers (bug report 2026-11-22, 10.2: a number the code sets is never typed into a text).
        .featurePlayers: ["• Up to {0} players in a game", "• עד {0} שחקנים במשחק", "• Hasta {0} jugadores por partida",
                          "• حتى {0} لاعبين في اللعبة الواحدة", "• एक गेम में {0} तक खिलाड़ी", "• Tot {0} spelers per spel"],
        .featureCharacters: ["• Flare, Kyra, Gaya and Mia as your character or house players",
                             "• ברק, ספיר, גאיה ומיה כדמות שלכם או כשחקני בית",
                             "• Flare, Kyra, Gaya y Mia como tu personaje o como jugadores de la casa",
                             "• Flare وKyra وGaya وMia كشخصيتك أو كلاعبين من اللعبة",
                             "• Flare, Kyra, Gaya और Mia आपके किरदार या घर के खिलाड़ी के रूप में",
                             "• Flare, Kyra, Gaya en Mia als je eigen figuur of als huisspelers"],
        .featureArenas: ["• All arenas, with the Tropical beach and Andromeda", "• כל הזירות, כולל החוף הטרופי ואנדרומדה",
                         "• Todos los escenarios, también la Playa tropical y Andrómeda",
                         "• كل الساحات، ومنها الشاطئ الاستوائي وأندروميدا",
                         "• सारे मैदान, उष्णकटिबंधीय समुद्र तट और एंड्रोमेडा भी",
                         "• Alle speelvelden, ook het Tropisch strand en Andromeda"],
        .featureBalls: ["• All balls, with the Beach ball, Neon party and the Tennis ball",
                        "• כל הכדורים, כולל כדור ים, כדור ניאון וכדור טניס",
                        "• Todas las pelotas, también la Pelota de playa, Fiesta neón y la pelota de tenis",
                        "• كل الكرات، ومنها كرة الشاطئ وحفلة نيون وكرة التنس",
                        "• सारी गेंदें, बीच बॉल, निऑन पार्टी और टेनिस बॉल भी",
                        "• Alle ballen, ook de Strandbal, Neonfeest en de tennisbal"],
        .featurePaint: ["• Paint balloons any time", "• בלוני צבע מתי שרוצים", "• Globos de pintura cuando quieras",
                        "• بالونات الألوان في أي وقت", "• रंग के गुब्बारे कभी भी", "• Verfballonnen wanneer je wilt"],
        .featureChallenges: ["• Every daily challenge", "• כל האתגרים היומיים", "• Todos los retos diarios",
                             "• كل التحديات اليومية", "• हर दैनिक चुनौती", "• Elke dagelijkse uitdaging"],
        .oneTime: ["One purchase, no ads. Family Sharing included.", "רכישה אחת, בלי פרסומות. כולל שיתוף משפחתי.",
                   "Una sola compra, sin anuncios. Incluye En familia.",
                   "عملية شراء واحدة، بلا إعلانات. تشمل المشاركة العائلية.",
                   "एक ही बार की ख़रीदारी, कोई विज्ञापन नहीं। फ़ैमिली शेयरिंग शामिल है।",
                   "Eén aankoop, geen advertenties. Inclusief Delen met gezin."],
        .buy: ["Unlock the full game · {0}", "פתיחת המשחק המלא · {0}", "Desbloquear el juego completo · {0}",
               "افتح اللعبة الكاملة · {0}", "पूरा गेम अनलॉक करें · {0}", "Volledige spel ontgrendelen · {0}"],
        .restore: ["Restore purchases", "שחזור רכישות", "Restaurar compras", "استعادة المشتريات", "खरीदारी बहाल करें",
                   "Aankopen herstellen"],
        .thanksTitle: ["Thank you!", "תודה!", "¡Gracias!", "شكرًا لك!", "धन्यवाद!", "Dank je wel!"],
        .thanksBody: ["The full game is unlocked. Have fun!", "המשחק המלא פתוח. שיהיה כיף!",
                      "El juego completo está desbloqueado. ¡A divertirse!",
                      "تم فتح اللعبة الكاملة. نتمنى لك وقتًا ممتعًا!", "पूरा गेम अनलॉक हो गया है। मज़े करें!",
                      "Het volledige spel is ontgrendeld. Veel plezier!"],
        .loading: ["Loading the App Store price…", "טוענים את המחיר מה-App Store…", "Cargando el precio del App Store…",
                   "جارٍ تحميل السعر من App Store…", "App Store से कीमत लोड हो रही है…", "De prijs wordt geladen uit de App Store…"],
        // Bug report 2026-11-22 (2.2): the message names the real problem (`SpudStoreProblem`); "check the connection"
        // only when the device is offline.
        .offline: ["There is no internet connection. Connect to Wi-Fi or mobile data and try again.",
                   "אין חיבור לאינטרנט. התחברו ל-Wi-Fi או לנתונים סלולריים ונסו שוב.",
                   "No hay conexión a internet. Conéctate a una red Wi-Fi o a los datos móviles y vuelve a intentarlo.",
                   "لا يوجد اتصال بالإنترنت. اتصل بشبكة Wi-Fi أو ببيانات الجوال وحاول مرة أخرى.",
                   "इंटरनेट कनेक्शन नहीं है। Wi-Fi या मोबाइल डेटा से जुड़ें और फिर कोशिश करें।",
                   "Er is geen internetverbinding. Maak verbinding met wifi of mobiele data en probeer het opnieuw."],
        .notAnswering: ["The App Store isn't answering right now. Please try again in a little while.",
                        "ה־App Store לא עונה כרגע. נסו שוב בעוד כמה רגעים.",
                        "El App Store no responde en este momento. Vuelve a intentarlo dentro de un rato.",
                        "App Store لا يستجيب الآن. يُرجى المحاولة مرة أخرى بعد قليل.",
                        "App Store अभी जवाब नहीं दे रहा है। थोड़ी देर बाद फिर कोशिश करें।",
                        "De App Store reageert nu niet. Probeer het over een tijdje opnieuw."],
        .productUnavailable: ["The full game isn't available in the App Store right now. Please try again later.",
                              "המשחק המלא לא זמין כרגע ב־App Store. נסו שוב מאוחר יותר.",
                              "El juego completo no está disponible en el App Store en este momento. Vuelve a intentarlo más tarde.",
                              "اللعبة الكاملة غير متاحة في App Store الآن. يُرجى المحاولة مرة أخرى لاحقًا.",
                              "पूरा गेम अभी App Store में उपलब्ध नहीं है। कृपया बाद में फिर कोशिश करें।",
                              "Het volledige spel is nu niet beschikbaar in de App Store. Probeer het later opnieuw."],
        .purchasesNotAllowed: ["Purchases are turned off on this device. A parent can allow them in Settings > Screen Time.",
                               "הרכישות כבויות במכשיר הזה. הורה יכול לאפשר אותן בהגדרות > זמן מסך.",
                               "Las compras están desactivadas en este dispositivo. Un adulto puede permitirlas en Ajustes > Tiempo de uso.",
                               "عمليات الشراء متوقفة على هذا الجهاز. يمكن لأحد الوالدين السماح بها من الإعدادات > مدة استخدام الجهاز.",
                               "इस डिवाइस पर ख़रीदारी बंद है। माता-पिता इसे सेटिंग्स > स्क्रीन टाइम में चालू कर सकते हैं।",
                               "Aankopen staan uit op dit apparaat. Een ouder kan ze toestaan via Instellingen > Schermtijd."],
        // Bug report 2026-11-22 (2.2): "Load the price again" was wrong (the price never loaded).
        .reload: ["Try again", "לנסות שוב", "Intentar de nuevo", "حاول مرة أخرى", "फिर कोशिश करें", "Opnieuw proberen"],
        .working: ["One moment…", "רק רגע…", "Un momento…", "لحظة من فضلك…", "बस एक पल…", "Even geduld…"],
        .pending: ["Waiting for approval. The full game unlocks as soon as the purchase is approved.",
                   "ממתינים לאישור. המשחק המלא ייפתח מיד כשהרכישה תאושר.",
                   "Esperando la aprobación. El juego completo se desbloqueará en cuanto se apruebe la compra.",
                   "بانتظار الموافقة. ستُفتح اللعبة الكاملة فور الموافقة على الشراء.",
                   "मंज़ूरी का इंतज़ार है। ख़रीदारी मंज़ूर होते ही पूरा गेम अनलॉक हो जाएगा।",
                   "Wachten op goedkeuring. Het volledige spel wordt ontgrendeld zodra de aankoop is goedgekeurd."],
        .purchaseFailed: ["The purchase did not go through. Please try again.", "הרכישה לא הושלמה. אפשר לנסות שוב.",
                          "La compra no se completó. Vuelve a intentarlo.", "لم تكتمل عملية الشراء. يُرجى المحاولة مرة أخرى.",
                          "ख़रीदारी पूरी नहीं हुई। कृपया फिर कोशिश करें।", "De aankoop is niet gelukt. Probeer het opnieuw."],
        .restoreFailed: ["Purchases could not be restored. Please try again.", "לא ניתן היה לשחזר את הרכישות. אפשר לנסות שוב.",
                         "No se pudieron restaurar las compras. Vuelve a intentarlo.",
                         "تعذّرت استعادة المشتريات. يُرجى المحاولة مرة أخرى.",
                         "खरीदारी बहाल नहीं हो सकी। कृपया फिर कोशिश करें।",
                         "De aankopen konden niet worden hersteld. Probeer het opnieuw."],
        .nothingToRestore: ["No earlier purchase of the full game was found.", "לא נמצאה רכישה קודמת של המשחק המלא.",
                            "No se encontró ninguna compra anterior del juego completo.",
                            "لم يتم العثور على شراء سابق للعبة الكاملة.", "पूरे गेम की कोई पिछली ख़रीदारी नहीं मिली।",
                            "Er is geen eerdere aankoop van het volledige spel gevonden."],
        .settingsOwned: ["Full game: unlocked ✓", "המשחק המלא: פתוח ✓", "Juego completo: desbloqueado ✓",
                         "اللعبة الكاملة: مفتوحة ✓", "पूरा गेम: अनलॉक है ✓", "Volledig spel: ontgrendeld ✓"],
        .settingsNotOwned: ["Full game: not unlocked yet", "המשחק המלא: עדיין לא נפתח", "Juego completo: aún sin desbloquear",
                            "اللعبة الكاملة: لم تُفتح بعد", "पूरा गेम: अभी अनलॉक नहीं है", "Volledig spel: nog niet ontgrendeld"],
        .paintTomorrow: ["The next free paint balloon game comes tomorrow.", "משחק החינם הבא עם בלון צבע יגיע מחר.",
                         "La próxima partida gratis con globo de pintura llega mañana.",
                         "اللعبة المجانية التالية ببالون الألوان ستكون غدًا.",
                         "रंग के गुब्बारे वाला अगला मुफ़्त गेम कल मिलेगा।",
                         "Het volgende gratis spel met de verfballon komt morgen."],
        // {0}: SpudAccess.freeChallenges.
        .challengeLocked: ["This challenge is part of the full game. The first {0} challenges are free.",
                           "האתגר הזה הוא חלק מהמשחק המלא. {0} האתגרים הראשונים בחינם.",
                           "Este reto es parte del juego completo. Los primeros {0} retos son gratis.",
                           "هذا التحدي جزء من اللعبة الكاملة. أول {0} تحديات مجانية.",
                           "यह चुनौती पूरे गेम का हिस्सा है। पहली {0} चुनौतियाँ मुफ़्त हैं।",
                           "Deze uitdaging hoort bij het volledige spel. De eerste {0} uitdagingen zijn gratis."],
        // {0}: SpudAccess.freePlayers.
        .roomFull: ["Leave at least one place for a friend: remove a house player. Without the full game, a game has up to {0} players.",
                    "השאירו לפחות מקום אחד לחבר: הסירו שחקן בית. בלי המשחק המלא יש עד {0} שחקנים במשחק.",
                    "Deja al menos una plaza para un amigo: quita un personaje. Sin el juego completo, una partida tiene hasta {0} jugadores.",
                    "اترك مكانًا واحدًا على الأقل لصديق: أزل إحدى شخصيات اللعبة. بدون اللعبة الكاملة تتسع اللعبة لـ {0} لاعبين كحد أقصى.",
                    "किसी दोस्त के लिए कम से कम एक जगह छोड़ें: गेम का एक खिलाड़ी हटाएँ। पूरे गेम के बिना एक गेम में ज़्यादा से ज़्यादा {0} खिलाड़ी होते हैं।",
                    "Laat minstens één plek vrij voor een vriend: verwijder een huisgenoot. Zonder het volledige spel heeft een spel maximaal {0} spelers."],
    ]

    private static func column(_ language: String) -> Int {
        return languages.firstIndex(of: AppText.normalize(language)) ?? 0
    }

    /// The numbers some texts carry ({0}), always from the rule that sets them (bug report 2026-11-22, 10.2).
    static func number(_ key: Key) -> Int? {
        switch key {
        case .featurePlayers: return SpudAccess.fullPlayers
        case .challengeLocked: return SpudAccess.freeChallenges
        case .roomFull: return SpudAccess.freePlayers
        default: return nil
        }
    }

    static func get(_ key: Key, language: String = AppText.language) -> String {
        guard let values = table[key] else { return key.rawValue }
        let text = values[column(language)]
        guard key != .buy, let n = number(key) else { return text }
        return text.replacingOccurrences(of: "{0}", with: String(n))
    }

    /// The message of a store problem.
    static func problem(_ problem: SpudStoreProblem, language: String = AppText.language) -> String {
        switch problem {
        case .offline: return get(.offline, language: language)
        case .notAnswering: return get(.notAnswering, language: language)
        case .productUnavailable: return get(.productUnavailable, language: language)
        case .purchasesNotAllowed: return get(.purchasesNotAllowed, language: language)
        }
    }

    /// "Unlock the full game · <price>"; the price keeps its own direction inside Hebrew and Arabic.
    static func buy(price: String, language: String = AppText.language) -> String {
        return get(.buy, language: language).replacingOccurrences(of: "{0}", with: "\u{2068}" + price + "\u{2069}")
    }

    // MARK: "N free paint balloon games left"

    /// CLDR plural categories, as far as these languages use them.
    enum Plural: Equatable {
        case zero, one, two, few, many, other
    }

    static func plural(_ n: Int, language: String = AppText.language) -> Plural {
        switch AppText.normalize(language) {
        case "ar":
            let rest = n % 100
            if n == 0 { return .zero }
            if n == 1 { return .one }
            if n == 2 { return .two }
            if rest >= 3 && rest <= 10 { return .few }
            if rest >= 11 && rest <= 99 { return .many }
            return .other
        case "hi":
            return n == 0 || n == 1 ? .one : .other
        default:
            return n == 1 ? .one : .other
        }
    }

    private static let paintLeft: [String: [Plural: String]] = [
        "en": [.one: "1 free paint balloon game left", .other: "{0} free paint balloon games left"],
        "he": [.one: "נשאר משחק חינם אחד עם בלון צבע", .other: "נשארו {0} משחקי חינם עם בלון צבע"],
        "es": [.one: "Te queda 1 partida gratis con globo de pintura", .other: "Te quedan {0} partidas gratis con globo de pintura"],
        "ar": [.zero: "لم تتبقَّ ألعاب مجانية ببالون الألوان",
               .one: "تبقّت لعبة مجانية واحدة ببالون الألوان",
               .two: "تبقّت لعبتان مجانيتان ببالون الألوان",
               .few: "تبقّت {0} ألعاب مجانية ببالون الألوان",
               .many: "تبقّت {0} لعبةً مجانية ببالون الألوان",
               .other: "تبقّت {0} لعبة مجانية ببالون الألوان"],
        "hi": [.one: "रंग के गुब्बारे वाला {0} मुफ़्त गेम बाकी है", .other: "रंग के गुब्बारे वाले {0} मुफ़्त गेम बाकी हैं"],
        "nl": [.one: "Nog 1 gratis spel met de verfballon", .other: "Nog {0} gratis spellen met de verfballon"],
    ]

    /// "N free paint balloon games left" with the language's plural form.
    static func paintGamesLeft(_ n: Int, language: String = AppText.language) -> String {
        let code = AppText.normalize(language)
        let forms = paintLeft[code] ?? paintLeft["en"] ?? [:]
        let template = forms[plural(n, language: code)] ?? forms[.other] ?? ""
        return template.replacingOccurrences(of: "{0}", with: String(n))
    }

    /// The setup and practice line for the paint balloon without the full game.
    static func paintLine(gamesLeft: Int, language: String = AppText.language) -> String {
        return gamesLeft > 0 ? paintGamesLeft(gamesLeft, language: language) : get(.paintTomorrow, language: language)
    }

    /// Every language's forms, for the tests.
    static func paintForms(_ language: String) -> [Plural: String] {
        return paintLeft[AppText.normalize(language)] ?? [:]
    }
}
