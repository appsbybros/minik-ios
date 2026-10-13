import Foundation

/// Port of Android MinikFamilyServices FamilyText.java: the shared family-message controls in the
/// additional languages (generated from the Java table; product copy comes from the catalogue).
enum FamilyText {
    static let languages = ["es", "ar", "hi", "nl", "fr", "de", "ru", "pt", "uk", "am"]

    private static let rows: [String: [String]] = [
        "More Minik apps & games": ["Más apps y juegos de Minik", "المزيد من تطبيقات وألعاب مينيك", "Minik के और ऐप और गेम", "Meer Minik-apps en spellen", "Autres applications et jeux Minik", "Weitere Minik-Apps und Spiele", "Другие приложения и игры Minik", "Mais aplicações e jogos Minik", "Інші застосунки та ігри Minik", "ተጨማሪ የሚኒክ መተግበሪያዎች እና ጨዋታዎች"],
        "Try again.": ["Inténtalo de nuevo.", "حاول مرة أخرى.", "फिर कोशिश करें।", "Probeer opnieuw.", "Réessayez.", "Versuche es noch einmal.", "Попробуйте ещё раз.", "Tente novamente.", "Спробуйте ще раз.", "እንደገና ይሞክሩ።"],
        "Cancel": ["Cancelar", "إلغاء", "रद्द करें", "Annuleren", "Annuler", "Abbrechen", "Отмена", "Cancelar", "Скасувати", "ይቅር"],
        "Continue": ["Continuar", "متابعة", "जारी रखें", "Verder", "Continuer", "Weiter", "Продолжить", "Continuar", "Продовжити", "ቀጥል"],
        "Answer": ["Respuesta", "الإجابة", "उत्तर", "Antwoord", "Réponse", "Antwort", "Ответ", "Resposta", "Відповідь", "መልስ"],
        "For a grown-up": ["Para una persona adulta", "لشخص بالغ", "किसी बड़े के लिए", "Voor een volwassene", "Pour un adulte", "Für Erwachsene", "Для взрослого", "Para um adulto", "Для дорослого", "ለአዋቂ"],
        "Ad-free play": ["Juega sin anuncios", "اللعب بدون إعلانات", "बिना विज्ञापन खेलें", "Spelen zonder advertenties", "Jouer sans publicité", "Werbefrei spielen", "Игра без рекламы", "Jogue sem anúncios", "Гра без реклами", "ያለ ማስታወቂያ ይጫወቱ"],
        "Would you like to remove the ads? You can keep playing either way.": ["¿Quieres quitar los anuncios? Puedes seguir jugando de todos modos.", "هل تريد إزالة الإعلانات؟ يمكنك مواصلة اللعب في كل الأحوال.", "क्या आप विज्ञापन हटाना चाहते हैं? आप दोनों ही तरह खेल जारी रख सकते हैं।", "Wil je de advertenties verwijderen? Je kunt hoe dan ook blijven spelen.", "Voulez-vous supprimer les publicités ? Vous pouvez continuer à jouer dans tous les cas.", "Möchtest du die Werbung entfernen? Du kannst in jedem Fall weiterspielen.", "Хотите убрать рекламу? Продолжать играть можно в любом случае.", "Quer remover os anúncios? Pode continuar a jogar de qualquer forma.", "Бажаєте прибрати рекламу? Продовжувати грати можна в будь-якому разі.", "ማስታወቂያዎችን ማስወገድ ይፈልጋሉ? በማንኛውም ሁኔታ መጫወት መቀጠል ይችላሉ።"],
        "Remove ads": ["Quitar anuncios", "إزالة الإعلانات", "विज्ञापन हटाएँ", "Advertenties verwijderen", "Supprimer les publicités", "Werbung entfernen", "Убрать рекламу", "Remover anúncios", "Прибрати рекламу", "ማስታወቂያዎችን አስወግድ"],
        "Remind me later": ["Recordar más tarde", "ذكّرني لاحقًا", "बाद में याद दिलाएँ", "Herinner me later", "Me le rappeler plus tard", "Später erinnern", "Напомнить позже", "Lembrar mais tarde", "Нагадати пізніше", "በኋላ አስታውሰኝ"],
        "Don't show again": ["No volver a mostrar", "لا تعرض مجددًا", "दोबारा न दिखाएँ", "Niet meer tonen", "Ne plus afficher", "Nicht mehr anzeigen", "Больше не показывать", "Não mostrar novamente", "Більше не показувати", "እንደገና አታሳይ"],
        "From the Minik family": ["De la familia Minik", "من عائلة مينيك", "Minik परिवार की ओर से", "Van de Minik-familie", "De la famille Minik", "Aus der Minik-Familie", "От семьи Minik", "Da família Minik", "Від родини Minik", "ከሚኒክ ቤተሰብ"],
        "Discover all our apps and games at miniklearn.com.": ["Descubre todas nuestras aplicaciones y juegos en miniklearn.com.", "اكتشف جميع تطبيقاتنا وألعابنا على miniklearn.com.", "हमारे सभी ऐप और गेम miniklearn.com पर देखें।", "Ontdek al onze apps en spellen op miniklearn.com.", "Découvrez toutes nos applications et tous nos jeux sur miniklearn.com.", "Entdecke alle unsere Apps und Spiele auf miniklearn.com.", "Все наши приложения и игры — на miniklearn.com.", "Descubra todas as nossas aplicações e jogos em miniklearn.com.", "Усі наші застосунки та ігри — на miniklearn.com.", "ሁሉንም መተግበሪያዎቻችንን እና ጨዋታዎቻችንን በminiklearn.com ያግኙ።"],
        "Keep playing": ["Seguir jugando", "متابعة اللعب", "खेलते रहें", "Verder spelen", "Continuer à jouer", "Weiterspielen", "Продолжить игру", "Continuar a jogar", "Продовжити гру", "መጫወት ቀጥል"],
        "View on Google Play": ["Ver en Google Play", "عرض على Google Play", "Google Play पर देखें", "Bekijken op Google Play", "Voir sur Google Play", "Auf Google Play ansehen", "Открыть в Google Play", "Ver no Google Play", "Відкрити в Google Play", "በGoogle Play ይመልከቱ"],
        "Meet this app": ["Conoce esta aplicación", "تعرّف على التطبيق", "इस ऐप को जानें", "Ontdek deze app", "Découvrir cette application", "Diese App entdecken", "Узнать о приложении", "Conheça esta aplicação", "Дізнатися про застосунок", "ይህን መተግበሪያ ይወቁ"],
        "Play on the website": ["Jugar en la web", "العب على الموقع", "वेबसाइट पर खेलें", "Spelen op de website", "Jouer sur le site", "Auf der Website spielen", "Играть на сайте", "Jogar no site", "Грати на сайті", "በድረ ገጹ ላይ ይጫወቱ"],
        "Also available for iPhone": ["También para iPhone", "متاح أيضًا على iPhone", "iPhone के लिए भी उपलब्ध", "Ook voor iPhone", "Également sur iPhone", "Auch für iPhone", "Также для iPhone", "Também para iPhone", "Також для iPhone", "ለiPhoneም ይገኛል"],
        "All our apps & games": ["Todas nuestras apps y juegos", "جميع تطبيقاتنا وألعابنا", "हमारे सभी ऐप और गेम", "Al onze apps en spellen", "Toutes nos applications et jeux", "Alle unsere Apps und Spiele", "Все наши приложения и игры", "Todas as nossas aplicações e jogos", "Усі наші застосунки та ігри", "ሁሉም መተግበሪያዎቻችን እና ጨዋታዎቻችን"],
        "No browser is available.": ["No hay un navegador disponible.", "لا يوجد متصفح متاح.", "कोई ब्राउज़र उपलब्ध नहीं है।", "Er is geen browser beschikbaar.", "Aucun navigateur disponible.", "Kein Browser verfügbar.", "Браузер недоступен.", "Nenhum navegador disponível.", "Браузер недоступний.", "አሳሽ አልተገኘም።"]
    ]

    /// Android `FamilyText.get(language, english)`.
    static func get(_ language: String, _ english: String) -> String {
        guard let row = rows[english], let i = languages.firstIndex(of: language) else { return english }
        return row[i]
    }
}
