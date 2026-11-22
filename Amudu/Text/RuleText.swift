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
        "timerHint": ["In games with two or more people, each turn has a time limit. Picking up the ball starts the time again.", "במשחק עם שני אנשים או יותר, לכל תור יש זמן מוגבל. איסוף הכדור מתחיל את הזמן מחדש.", "En partidas con dos o más personas, cada turno tiene un tiempo límite. Recoger la pelota reinicia el tiempo.", "في الألعاب التي يشارك فيها شخصان أو أكثر، لكل دور وقت محدد. التقاط الكرة يبدأ الوقت من جديد.", "दो या ज़्यादा लोगों वाले खेल में हर बारी का समय तय होता है। गेंद उठाने पर समय फिर से शुरू होता है।", "In spellen met twee of meer mensen heeft elke beurt een tijdslimiet. De bal oprapen start de tijd opnieuw."],
        "noLimit": ["No limit", "ללא הגבלה", "Sin límite", "بلا حد", "कोई सीमा नहीं", "Geen limiet"],
        "callRule": ["Call before throwing", "קריאה לפני זריקה", "Gritar antes de lanzar", "النداء قبل الرمي", "फेंकने से पहले पुकार", "Roepen vóór het gooien"],
        "optional": ["Optional", "לא חובה", "Opcional", "اختياري", "वैकल्पिक", "Niet verplicht"],
        "required": ["Required", "חובה", "Obligatorio", "إلزامي", "ज़रूरी", "Verplicht"],
        "steps": ["Steps after Stop!", "צעדים אחרי עמודו!", "Pasos después de «¡Pies quietos!»", "الخطوات بعد «ستوب!»", "“STOP!” के बाद कदम", "Stappen na Stop!"],
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
        "idleHelp": ["A countdown appears near the end of your turn. Miss a few turns in a row and you sit out and watch. In the nickname game you can ask to come back, and the other players vote.", "לקראת סוף התור מופיעה ספירה לאחור. מי שמפספס כמה תורות ברצף יוצא לצפות. במשחק הכינויים אפשר לבקש לחזור, והשחקנים האחרים מצביעים.", "Cerca del final de tu turno aparece una cuenta atrás. Si te saltas varios turnos seguidos, pasas a mirar. En el juego de apodos puedes pedir volver y los demás votan.", "يظهر عدّ تنازلي قرب نهاية دورك. إذا فاتتك عدة أدوار متتالية تصبح مشاهدًا. في لعبة الألقاب يمكنك طلب العودة ويصوّت اللاعبون الآخرون.", "आपकी बारी खत्म होने से पहले उलटी गिनती दिखती है। लगातार कुछ बारियाँ छूटने पर आप बाहर बैठकर देखते हैं। उपनाम वाले खेल में आप वापस आने को कह सकते हैं, और बाकी खिलाड़ी वोट करते हैं।", "Tegen het einde van je beurt verschijnt een aftelling. Mis je een paar beurten achter elkaar, dan kijk je mee. In het bijnamenspel kun je vragen om terug te komen en stemmen de anderen."],
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
