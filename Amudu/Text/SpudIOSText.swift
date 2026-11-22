import Foundation

/// iOS-only texts and rewordings from the bug report of 22 November 2026, in the app's six languages
/// `[en, he, es, ar, hi, nl]`, keyed by their English text. `GameText.t` reads them before the catalog generated from
/// Android (`AmuduCatalog.json`), so `model.tr(en, he)` finds every language. Android still shows the older wording
/// (docs/amudu-ios-handoff.md, "Deliberate differences 2026-11-22"); `Scripts/audit-amudu.py` lists the Android
/// sentences these replace.
enum SpudIOSText {
    static let languages = ["en", "he", "es", "ar", "hi", "nl"]

    /// Catching: no promise of a duration the code can change (bug report 10.2; the window is
    /// `CatchPhysics.HUMAN_WINDOW`).
    static let catchBrief = "Tap Catch as the ball arrives, before it touches the ground."
    static let helpCatch = "Tap Catch as the ball arrives; you only have a short moment. Jump over low balls or duck under high balls. Low balls are hardest to catch; high balls are a little harder than centre throws. Skill, speed and facing still matter."
    /// The lessons' throw choices (bug report 12).
    static let howYouThrow = "How you throw"
    static let yourThrow = "Your throw: the same choices as in a game. Change them to feel the difference."
    /// Andromeda in the lessons' conditions (bug report 11).
    static let conditionsNote = "Andromeda is a space arena with low gravity: the ball and the players stay in the air longer. Evening and night change only how the park looks."
    /// "Steps after calling" explained (bug report 14).
    static let stepsExplained = "After someone calls Stop! everyone freezes. The ball holder may still take this many steps toward a player before throwing. None: throw from where you stand."

    /// The Hebrew of an English key (for `model.tr(en, he)`).
    static func he(_ en: String) -> String {
        return copy[en]?[1] ?? en
    }

    static let copy: [String: [String]] = [
        catchBrief: [catchBrief,
                     "געו בתפיסה כשהכדור מגיע, לפני שהוא נוגע בקרקע.",
                     "Toca Atrapar cuando llegue la pelota, antes de que toque el suelo.",
                     "اضغط «التقط» عند وصول الكرة، قبل أن تلمس الأرض.",
                     "गेंद आते ही, ज़मीन छूने से पहले, पकड़ें दबाएँ।",
                     "Tik op Vang als de bal aankomt, voordat hij de grond raakt."],
        helpCatch: [helpCatch,
                    "לחצו תפיסה כשהכדור מגיע; יש לכם רק רגע קצר. קפצו מעל כדור נמוך או התכופפו מתחת לכדור גבוה. כדור נמוך הכי קשה לתפוס; כדור גבוה קצת קשה יותר מכדור למרכז הגוף. המיומנות, המהירות וכיוון העמידה עדיין משפיעים.",
                    "Toca Atrapar cuando llegue la pelota; solo tienes un momento. Salta sobre pelotas bajas o agáchate bajo las altas. Las bajas son las más difíciles de atrapar; las altas, algo más que las dirigidas al torso. La habilidad, la velocidad y la orientación siguen contando.",
                    "اضغط «التقط» عند وصول الكرة؛ لديك لحظة قصيرة فقط. اقفز فوق الكرة المنخفضة أو انحنِ تحت العالية. المنخفضة هي الأصعب إمساكًا؛ والعالية أصعب قليلًا من الموجهة إلى وسط الجسم. المهارة والسرعة واتجاه الوقوف تؤثر أيضًا.",
                    "गेंद पहुँचने पर पकड़ें दबाएँ; आपके पास बस एक छोटा-सा पल है। नीची गेंद के ऊपर कूदें या ऊँची गेंद के नीचे झुकें। नीची गेंद पकड़ना सबसे कठिन है; ऊँची गेंद, धड़ की ओर आई गेंद से थोड़ी कठिन है। कौशल, गति और मुँह की दिशा भी मायने रखते हैं।",
                    "Tik op Vang als de bal aankomt; je hebt maar een kort moment. Spring over lage ballen of buk onder hoge ballen. Lage ballen zijn het moeilijkst te vangen; hoge iets moeilijker dan worpen naar je romp. Vaardigheid, snelheid en kijkrichting blijven meetellen."],
        howYouThrow: [howYouThrow, "איך זורקים", "Cómo lanzas", "طريقة الرمي", "आप कैसे फेंकते हैं", "Hoe je gooit"],
        yourThrow: [yourThrow,
                    "הזריקה שלכם: אותן אפשרויות כמו במשחק. שנו אותן כדי להרגיש את ההבדל.",
                    "Tu lanzamiento: las mismas opciones que en una partida. Cámbialas para notar la diferencia.",
                    "رميتك: الخيارات نفسها كما في اللعبة. غيّرها لتشعر بالفرق.",
                    "आपकी थ्रो: खेल जैसे ही विकल्प। फ़र्क़ महसूस करने के लिए इन्हें बदलें।",
                    "Jouw worp: dezelfde keuzes als in een spel. Verander ze om het verschil te voelen."],
        conditionsNote: [conditionsNote,
                         "אנדרומדה היא זירה בחלל עם כבידה נמוכה: הכדור והשחקנים נשארים באוויר יותר זמן. ערב ולילה משנים רק את מראה הפארק.",
                         "Andrómeda es un escenario espacial con poca gravedad: la pelota y los jugadores pasan más tiempo en el aire. La tarde y la noche solo cambian el aspecto del parque.",
                         "أندروميدا ساحة في الفضاء بجاذبية منخفضة: تبقى الكرة واللاعبون في الهواء وقتًا أطول. المساء والليل يغيّران شكل الحديقة فقط.",
                         "एंड्रोमेडा कम गुरुत्व वाला अंतरिक्ष मैदान है: गेंद और खिलाड़ी हवा में ज़्यादा देर रहते हैं। शाम और रात सिर्फ़ पार्क का रूप बदलते हैं।",
                         "Andromeda is een speelveld in de ruimte met lage zwaartekracht: de bal en de spelers blijven langer in de lucht. Avond en nacht veranderen alleen hoe het park eruitziet."],
        stepsExplained: [stepsExplained,
                         "אחרי שקוראים עמודו! כולם קופאים במקום. מחזיק הכדור עדיין יכול לצעוד מספר צעדים כזה לעבר שחקן לפני הזריקה. ללא: זורקים מהמקום.",
                         "Cuando alguien grita «¡Pies quietos!», todos se quedan quietos. Quien tiene la pelota aún puede dar ese número de pasos hacia un jugador antes de lanzar. Ninguno: lanza desde donde estás.",
                         "عندما ينادي أحدهم «ستوب!» يتجمّد الجميع. يمكن لحامل الكرة أن يخطو هذا العدد من الخطوات نحو لاعب قبل الرمي. لا خطوات: ارمِ من مكانك.",
                         "किसी के “STOP!” कहने पर सब रुक जाते हैं। गेंद वाला खिलाड़ी फेंकने से पहले किसी खिलाड़ी की ओर इतने कदम चल सकता है। कोई नहीं: जहाँ खड़े हैं वहीं से फेंकें।",
                         "Als iemand Stop! roept, staat iedereen stil. Wie de bal heeft, mag nog zoveel stappen naar een speler zetten voordat hij gooit. Geen: gooi vanaf je plek."],
    ]
}
