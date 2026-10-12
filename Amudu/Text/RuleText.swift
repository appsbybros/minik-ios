import Foundation

/// Android `RuleText`: the two playable rule sets and their six-language texts (English, Hebrew, Spanish, Arabic,
/// Hindi, Dutch). Rule names describe our two playable variants, not a claim of universal playground rules.
enum RuleText {
    private static let copy: [String: [String]] = [
        "mode": ["Game rules", "חוקי המשחק", "Reglas del juego", "قواعد اللعب", "खेल के नियम", "Spelregels"],
        "nicknames": ["Stop! · Funny nicknames", "עמודו · כינויים מצחיקים", "¡Pies quietos! · Apodos divertidos", "ستوب! · ألقاب مضحكة", "STOP! · मज़ेदार उपनाम", "Stop! · Grappige bijnamen"],
        "spud": ["SPUD · Four letters", "בטטה · ארבע אותיות", "PAPA · Cuatro letras", "قفوا · أربعة أحرف", "अजगर · चार अक्षर", "STOP · Vier letters"],
        "connectionLost": ["Connection lost. Reconnecting… You can use Back to leave.", "החיבור אבד. מתחברים מחדש… אפשר לחזור באמצעות החץ.", "Sin conexión. Reconectando… Puedes volver con la flecha.", "انقطع الاتصال. جارٍ الاتصال… يمكنك الرجوع بالسهم.", "कनेक्शन टूट गया। फिर जुड़ रहे हैं… वापस जाने के लिए तीर दबाएँ।", "Verbinding verbroken. Opnieuw verbinden… Ga terug met de pijl."],
        "environment": ["Environment", "סביבה", "Entorno", "البيئة", "माहौल", "Omgeving"],
        "advanced": ["Advanced rules", "חוקים מתקדמים", "Reglas avanzadas", "قواعد متقدمة", "अतिरिक्त नियम", "Extra spelregels"],
        "time": ["Time to act", "זמן לפעולה", "Tiempo para actuar", "مهلة التصرف", "चाल चलने का समय", "Tijd voor je actie"],
        "timerHint": ["With two or more active human players. Picking up the ball starts a fresh timer; aiming does not.", "כשיש לפחות שני שחקנים אנושיים פעילים. איסוף הכדור מתחיל זמן חדש; כיוון לא מאפס אותו.", "Con dos o más personas activas. Recoger el balón reinicia el tiempo; apuntar no.", "عند وجود لاعبين بشريين نشطين أو أكثر. التقاط الكرة يبدأ مهلة جديدة؛ التصويب لا يجددها.", "दो या अधिक सक्रिय मानव खिलाड़ियों के साथ। गेंद उठाने पर नया समय मिलता है; निशाना लगाने पर नहीं।", "Bij twee of meer actieve menselijke spelers. De bal oprapen start een nieuwe timer; richten niet."],
        "noLimit": ["No limit", "ללא הגבלה", "Sin límite", "بلا حد", "कोई सीमा नहीं", "Geen limiet"],
        "callRule": ["Call before throwing", "קריאה לפני זריקה", "Gritar antes de lanzar", "النداء قبل الرمي", "फेंकने से पहले पुकार", "Roepen vóór het gooien"],
        "optional": ["Optional", "לא חובה", "Opcional", "اختياري", "वैकल्पिक", "Niet verplicht"],
        "required": ["Required", "חובה", "Obligatorio", "إلزامي", "ज़रूरी", "Verplicht"],
        "steps": ["Steps after calling", "צעדים אחרי הקריאה", "Pasos después de gritar", "الخطوات بعد النداء", "पुकारने के बाद कदम", "Stappen na het roepen"],
        "none": ["None", "ללא", "Ninguno", "لا خطوات", "कोई नहीं", "Geen"],
        "afterCall": ["After the call", "אחרי הקריאה", "Después del grito", "بعد النداء", "पुकारने के बाद", "Na het roepen"],
        "spectating": ["You are watching", "אתם צופים במשחק", "Estás mirando", "أنت تشاهد اللعب", "आप खेल देख रहे हैं", "Je kijkt mee"],
        "askReturn": ["Ask to return", "בקשה לחזור למשחק", "Pedir volver", "اطلب العودة", "वापसी का अनुरोध", "Vraag om terug te komen"],
        "queued": ["Return request queued for the next point", "הבקשה ממתינה לנקודת החובה הבאה", "Solicitud pendiente hasta el próximo punto", "طلب العودة ينتظر النقطة التالية", "वापसी का अनुरोध अगले अंक पर दिखेगा", "Je verzoek wacht op het volgende strafpunt"],
        "noRequests": ["No return requests left this time", "לא נותרו בקשות חזרה הפעם", "No quedan solicitudes de regreso", "لم تتبق طلبات عودة هذه المرة", "इस बार वापसी के अनुरोध खत्म हो गए", "Je kunt nu niet meer om terugkeer vragen"],
        "spudOut": ["Out for this game. Watch your friends!", "יצאתם מהמשחק הזה. אפשר לצפות בחברים!", "Fuera de esta partida. ¡Mira a tus amigos!", "خرجت من هذه الجولة. شاهد أصدقاءك!", "इस खेल से बाहर। दोस्तों का खेल देखें!", "Dit spel ben je uit. Kijk mee met je vrienden!"],
        "returnVote": ["Allow %s to return?", "לאפשר ל%s לחזור?", "¿Puede volver %s?", "هل نسمح بعودة %s؟", "क्या %s को वापस आने दें?", "Mag %s terugkomen?"],
        "pausedVote": ["Play is paused while everyone votes.", "המשחק מושהה בזמן ההצבעה.", "El juego está en pausa durante la votación.", "اللعب متوقف أثناء التصويت.", "मतदान के दौरान खेल रुका है।", "Het spel staat stil tijdens het stemmen."],
        "yes": ["Yes", "כן", "Sí", "نعم", "हाँ", "Ja"],
        "no": ["No", "לא", "No", "لا", "नहीं", "Nee"],
        "voted": ["Vote recorded", "ההצבעה נקלטה", "Voto registrado", "تم تسجيل التصويت", "मत दर्ज हो गया", "Stem opgeslagen"],
        "seconds": ["%d seconds left", "נותרו %d שניות", "Quedan %d segundos", "بقيت %d ثوانٍ", "%d सेकंड बाकी", "Nog %d seconden"],
        "status": ["Players & scores", "שחקנים ונקודות", "Jugadores y puntuación", "اللاعبون والنتائج", "खिलाड़ी और अंक", "Spelers en scores"],
        "you": ["You", "אתם", "Tú", "أنت", "आप", "Jij"],
        "watching": ["Watching", "צופים", "Mirando", "يشاهد", "दर्शक", "Kijkt mee"],
        "lastStanding": ["Last player standing wins", "השחקן האחרון מנצח", "Gana quien quede en juego", "يفوز آخر لاعب يبقى في اللعب", "आख़िर तक बचा खिलाड़ी जीतता है", "De laatste speler wint"],
        "mustCall": ["Tap %s first, then aim and throw.", "לחצו קודם על %s, ואז כוונו וזרקו.", "Pulsa %s primero; después apunta y lanza.", "اضغط %s أولاً، ثم صوّب وارمِ.", "पहले %s दबाएँ, फिर निशाना लगाकर फेंकें।", "Tik eerst op %s, richt en gooi dan."],
        "mayCall": ["Aim and throw now, or tap %s to stop the runners.", "אפשר לכוון ולזרוק מיד, או ללחוץ %s לעצירת הרצים.", "Apunta y lanza, o pulsa %s para detener a los demás.", "صوّب وارمِ الآن، أو اضغط %s لإيقاف العدّائين.", "अभी निशाना लगाकर फेंकें, या सबको रोकने के लिए %s दबाएँ।", "Richt en gooi, of tik op %s om de anderen te stoppen."],
        "stepsLeft": ["Step allowance left: %.1f", "נותרו צעדים: %.1f", "Pasos restantes: %.1f", "الخطوات المتبقية: %.1f", "कदम बाकी: %.1f", "Stappen over: %.1f"],
        "timeout": ["%s ran out of time. Next player.", "נגמר הזמן של %s. עוברים לשחקן הבא.", "Se acabó el tiempo de %s. Siguiente jugador.", "انتهى وقت %s. اللاعب التالي.", "%s का समय खत्म। अगले खिलाड़ी की बारी।", "De tijd van %s is op. Volgende speler."],
        "waiting": ["Waiting for active players", "ממתינים לשחקנים פעילים", "Esperando jugadores activos", "بانتظار لاعبين نشطين", "सक्रिय खिलाड़ियों का इंतज़ार", "Wachten op actieve spelers"],
        "rulesHint": ["Playground games have family variations. Choose your rules; everyone in the room shares them.", "למשחקי חצר יש גרסאות משפחתיות. בחרו חוקים; הם יחולו על כל החדר.", "Cada familia tiene sus variantes. Elige las reglas para todos en la sala.", "لألعاب الساحات نسخ عائلية مختلفة. اختر القواعد لتسري على الجميع في الغرفة.", "हर परिवार के खेलने के नियम अलग हो सकते हैं। चुने हुए नियम पूरे कमरे पर लागू होंगे।", "Iedere familie speelt anders. Kies regels die voor de hele kamer gelden."],
        "nickHelp": ["Funny nicknames: every three penalties, others choose a word. You always see “You” for yourself; remember your nickname! Fewest penalties wins when the game ends.", "כינויים מצחיקים: בכל שלוש נקודות האחרים בוחרים מילה. לעצמכם תמיד מוצג ״אתם״; זכרו את הכינוי! בסיום מנצחים עם הכי מעט נקודות חובה.", "Apodos: cada tres penalizaciones, los demás eligen una palabra. Para ti siempre aparece «Tú»: ¡recuerda tu apodo! Gana quien tenga menos penalizaciones.", "الألقاب: كل ثلاث عقوبات يختار الآخرون كلمة. ترى «أنت» لنفسك دائماً؛ تذكّر لقبك! الأقل عقوبات يفوز في النهاية.", "उपनाम: हर तीन दंड पर बाकी खिलाड़ी एक शब्द चुनते हैं। आपको अपना नाम «आप» दिखेगा; उपनाम याद रखें! अंत में सबसे कम दंड वाला जीतता है।", "Bijnamen: na elke drie strafpunten kiezen de anderen een woord. Bij jezelf staat altijd ‘Jij’; onthoud je bijnaam! De minste strafpunten wint."],
        "spudHelp": ["SPUD: each penalty adds a letter: S, P, U, D. Four letters means watching until the next game. No nicknames. The last active player wins.", "בטטה: כל נקודת חובה מוסיפה אות: ב, ט, ט, ה. אחרי ארבע אותיות צופים עד המשחק הבא. בלי כינויים. האחרון שנשאר מנצח.", "PAPA: cada penalización añade P, A, P o A. Con cuatro letras, miras hasta la próxima partida. Sin apodos. Gana el último jugador.", "قفوا: تضيف كل عقوبة حرفاً من ق، ف، و، ا. بعد أربعة أحرف تشاهد حتى المباراة التالية. بلا ألقاب. يفوز آخر لاعب.", "अजगर: हर दंड पर अ, ज, ग, र में अगला अक्षर मिलता है। चार अक्षर होने पर अगले खेल तक दर्शक बनते हैं। उपनाम नहीं। अंतिम खिलाड़ी जीतता है।", "STOP: elk strafpunt geeft een letter: S, T, O, P. Na vier letters kijk je mee tot het volgende spel. Geen bijnamen. De laatste speler wint."],
        "idleHelp": ["With two active human players, the action timer counts down only in the last five seconds. Three unfinished turns means watching. In the nickname game, you can ask to return up to three times; active people vote during a pause.", "כשיש שני שחקנים אנושיים פעילים, הספירה מוצגת רק בחמש השניות האחרונות. אחרי שלוש פעולות שלא הושלמו עוברים לצפייה. במשחק הכינויים אפשר לבקש לחזור עד שלוש פעמים; השחקנים הפעילים מצביעים בהפסקה.", "Con dos personas activas, el contador aparece en los últimos cinco segundos. Tres turnos sin completar te dejan mirando. En el modo de apodos puedes pedir volver tres veces; se vota con el juego en pausa.", "مع لاعبين بشريين نشطين يظهر العد في آخر خمس ثوانٍ. بعد ثلاث فرص دون إكمال الدور تصبح مشاهداً. في وضع الألقاب يمكنك طلب العودة ثلاث مرات ويصوّت اللاعبون أثناء توقف اللعب.", "दो सक्रिय मानव खिलाड़ियों के साथ आख़िरी पाँच सेकंड में उलटी गिनती दिखती है। तीन अधूरे अवसरों के बाद आप दर्शक बनते हैं। उपनाम वाले खेल में तीन बार वापसी माँग सकते हैं; खेल रोककर मतदान होता है।", "Bij twee actieve menselijke spelers zie je de laatste vijf seconden aftellen. Na drie onvoltooide beurten kijk je mee. In het bijnamenspel kun je drie keer terugkeer vragen; het spel pauzeert voor de stemming."],
    ]

    /// Kotlin `RuleText[key]`: the column of the app language (English for any other language).
    static subscript(key: String) -> String {
        let i: Int
        switch AppText.language {
        case "he": i = 1
        case "es": i = 2
        case "ar": i = 3
        case "hi": i = 4
        case "nl": i = 5
        default: i = 0
        }
        guard let values = copy[key], i < values.count else { return key }
        return values[i]
    }

    /// Kotlin `String.format` of a `%s` template.
    static func format(_ template: String, _ value: String) -> String {
        return template.replacingOccurrences(of: "%s", with: value)
    }

    /// Kotlin `String.format` of a `%d` template (default locale, like Java).
    static func format(_ template: String, _ value: Int) -> String {
        return String(format: template, locale: Locale.current, value)
    }

    /// Kotlin `String.format` of a `%.1f` template (default locale, like Java).
    static func format(_ template: String, _ value: Double) -> String {
        return String(format: template, locale: Locale.current, value)
    }

    static func mode(_ r: RuleSet) -> String {
        return RuleText[r == .spud ? "spud" : "nicknames"]
    }

    static func penaltyWord(_ language: String = AppText.language) -> String {
        switch language {
        case "he": return "בטטה"
        case "es": return "PAPA"
        case "ar": return "قفوا"
        case "hi": return "अजगर"
        case "nl": return "STOP"
        default: return "SPUD"
        }
    }

    /// The spoken and shown call: the letters word for SPUD rules, the localized stop call for nicknames.
    static func call(_ r: RuleSet) -> String {
        return r == .spud ? penaltyWord() + "!" : GameText.stopCall()
    }

    /// SPUD rules show the letters earned so far (Kotlin `take` counts UTF-16 units); nickname rules the penalties.
    static func score(_ a: GameActor, _ r: RuleSet) -> String {
        if r == .spud {
            let letters = String(decoding: Array(penaltyWord().utf16.prefix(min(max(a.penalties, 0), 4))), as: UTF16.self)
            return letters.isEmpty ? "—" : letters
        }
        return String(a.penalties)
    }

    /// "You" for the local player; everyone else by their current (nick)name.
    static func name(_ a: GameActor, _ own: String) -> String {
        return a.member.id == own ? RuleText["you"] : a.fullName(hebrew: AppText.language == "he")
    }
}
