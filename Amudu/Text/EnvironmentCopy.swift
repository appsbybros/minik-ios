import Foundation

/// Android `EnvironmentCopy` (amudu/EnvironmentCopy.kt): keyed rows `[en, he, es, ar, hi, nl]`. Generated from the Kotlin
/// source.
enum EnvironmentCopy {
    private static let languages = ["en", "he", "es", "ar", "hi", "nl"]

    static let ordered: [(String, [String])] = [
        ("timer", ["Limits how long a player can leave their turn unfinished, for example if they stop responding or disconnect. With at least two active people, three unfinished turns move that player to watching. No limit turns this timer off.", "מגביל כמה זמן אפשר להשאיר תור ללא פעולה, למשל אם שחקן לא מגיב או מתנתק. כשיש לפחות שני אנשים פעילים, אחרי שלושה תורים שלא הושלמו השחקן עובר לצפייה. ללא הגבלה מבטל את הטיימר.", "Limita cuánto puede quedar un turno sin terminar, por ejemplo si alguien deja de responder o se desconecta. Con al menos dos personas activas, tres turnos sin terminar pasan al jugador a espectador. Sin límite desactiva el temporizador.", "يحدد مدة بقاء الدور دون إكمال، مثل توقف اللاعب عن الاستجابة أو انقطاع اتصاله. مع وجود شخصين نشطين على الأقل، يصبح اللاعب مشاهداً بعد ثلاثة أدوار غير مكتملة. خيار بلا حد يلغي المؤقت.", "यह अधूरी बारी की समय सीमा है, जैसे खिलाड़ी जवाब न दे या उसका कनेक्शन टूट जाए। कम से कम दो सक्रिय लोगों के साथ तीन अधूरी बारियों के बाद वह दर्शक बनता है। बिना सीमा चुनने पर टाइमर बंद रहता है।", "Beperkt hoelang een beurt onafgemaakt blijft, bijvoorbeeld als iemand niet reageert of de verbinding verliest. Bij minstens twee actieve mensen wordt die speler na drie onafgemaakte beurten toeschouwer. Zonder limiet zet de timer uit."]),
        ("light_title", ["Light and wind", "אור ורוח", "Luz y viento", "الضوء والرياح", "रोशनी और हवा", "Licht en wind"]),
        ("light_body", ["Try the same throw in evening light and at night. Light changes what you see; wind bends the flight. Watch the ground shadow and adjust your aim. Try each setting below.", "נסו את אותה זריקה באור ערב ובלילה. האור משנה את הראות; הרוח מסיטה את הזריקה. עקבו אחר הצל על הקרקע והתאימו את הכיוון. נסו את האפשרויות שלמטה.", "Prueba el mismo lanzamiento al atardecer y de noche. La luz cambia la visibilidad; el viento desvía la trayectoria. Observa la sombra en el suelo y ajusta la puntería. Prueba las opciones de abajo.", "جرّب الرمية نفسها مساءً وليلاً. يغيّر الضوء الرؤية، وتغيّر الرياح المسار. راقب الظل على الأرض وعدّل تصويبك. جرّب الخيارات أدناه.", "शाम और रात में एक ही थ्रो आज़माएँ। रोशनी से दृश्य बदलता है और हवा गेंद का रास्ता मोड़ती है। ज़मीन की छाया देखकर निशाना बदलें। नीचे की स्थितियाँ आज़माएँ।", "Probeer dezelfde worp bij avondlicht en 's nachts. Licht verandert het zicht; wind buigt de vlucht. Volg de schaduw op de grond en pas je richting aan. Probeer de instellingen hieronder."]),
        ("Not allowed", ["Not allowed", "אסור", "No permitido", "غير مسموح", "अनुमति नहीं", "Niet toegestaan"]),
        ("Allowed", ["Allowed", "מותר", "Permitido", "مسموح", "अनुमति है", "Toegestaan"]),
    ]

    static let rows: [String: [String]] = {
        var map: [String: [String]] = [:]
        for (key, values) in ordered { map[key] = values }
        return map
    }()

    /// Kotlin `rows.getValue(key)[languages.indexOf(AppText.language).coerceAtLeast(0)]`.
    static func get(_ key: String) -> String {
        guard let values = rows[key] else { return key }
        return values[max(0, languages.firstIndex(of: AppText.language) ?? -1)]
    }
}
