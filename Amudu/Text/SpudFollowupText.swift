import Foundation

/// Android `SpudFollowupText` (amudu/SpudFollowupText.kt): `copy` rows `English key -> [en, he, es, ar, hi, nl]`, joined
/// before `GameText`'s own overrides (Kotlin `SpudFollowupText.copy + mapOf(...)`). Generated from the Kotlin source.
enum SpudFollowupText {
    /// Kotlin `mapOf` order; a repeated key keeps its first position and takes the last value.
    static let ordered: [(String, [String])] = [
        ("Return to game", ["Return to game", "חזרה למשחק", "Volver al juego", "العودة إلى اللعبة", "खेल में लौटें", "Terug naar het spel"]),
        ("Return to practice", ["Return to practice", "חזרה לאימון", "Volver a practicar", "العودة إلى التدريب", "अभ्यास में लौटें", "Terug naar de oefening"]),
        ("Tap Catch as the ball arrives: you have half a second. Jump over low balls or duck under high balls. Low balls are hardest to catch; high balls are a little harder than centre throws. Skill, speed and facing still matter.", ["Tap Catch as the ball arrives: you have half a second. Jump over low balls or duck under high balls. Low balls are hardest to catch; high balls are a little harder than centre throws. Skill, speed and facing still matter.", "לחצו תפיסה כשהכדור מגיע: יש לכם חצי שנייה. קפצו מעל כדור נמוך או התכופפו מתחת לכדור גבוה. כדור נמוך הכי קשה לתפוס; כדור גבוה קצת קשה יותר מכדור למרכז הגוף. המיומנות, המהירות וכיוון העמידה עדיין משפיעים.", "Toca Atrapar cuando llegue la pelota: tienes medio segundo. Salta sobre pelotas bajas o agáchate bajo las altas. Las bajas son las más difíciles de atrapar; las altas, algo más que las dirigidas al torso. La habilidad, la velocidad y la orientación siguen contando.", "اضغط إمساك عند وصول الكرة: لديك نصف ثانية. اقفز فوق الكرة المنخفضة أو انحنِ تحت العالية. المنخفضة هي الأصعب إمساكًا؛ والعالية أصعب قليلًا من الموجهة إلى وسط الجسم. المهارة والسرعة واتجاه الوقوف تؤثر أيضًا.", "गेंद पहुँचने पर कैच दबाएँ: आपके पास आधा सेकंड है। नीची गेंद के ऊपर कूदें या ऊँची गेंद के नीचे झुकें। नीची गेंद पकड़ना सबसे कठिन है; ऊँची गेंद, धड़ की ओर आई गेंद से थोड़ी कठिन है। कौशल, गति और मुँह की दिशा भी मायने रखते हैं।", "Tik op Vangen als de bal aankomt: je hebt een halve seconde. Spring over lage ballen of buk onder hoge ballen. Lage ballen zijn het moeilijkst te vangen; hoge iets moeilijker dan worpen naar je romp. Vaardigheid, snelheid en kijkrichting blijven meetellen."]),
        ("Drag to run · Time your catch\nJump low balls · Duck high balls", ["Drag to run · Time your catch\nJump low balls · Duck high balls", "גררו לריצה · תזמנו את התפיסה\nקפצו מעל כדור נמוך · התכופפו מתחת לגבוה", "Arrastra para correr · Atrapa a tiempo\nSalta las bajas · Agáchate ante las altas", "اسحب للركض · وقّت الإمساك\nاقفز فوق المنخفضة · انحنِ تحت العالية", "दौड़ने को खींचें · सही समय पर कैच करें\nनीची गेंद पर कूदें · ऊँची पर झुकें", "Sleep om te rennen · Vang op tijd\nSpring over laag · Buk onder hoog"]),
        ("The other players are choosing a nickname for you.\nThe game will continue when they finish.", ["The other players are choosing a nickname for you.\nThe game will continue when they finish.", "השחקנים האחרים בוחרים לכם כינוי.\nהמשחק ימשיך כשיסיימו.", "Los demás están eligiendo un apodo para ti.\nEl juego continuará cuando terminen.", "يختار اللاعبون الآخرون لقبًا لك.\nستستمر اللعبة عندما ينتهون.", "दूसरे खिलाड़ी आपके लिए एक उपनाम चुन रहे हैं।\nउनके चुनने के बाद खेल आगे बढ़ेगा।", "De andere spelers kiezen een bijnaam voor je.\nHet spel gaat verder zodra ze klaar zijn."]),
        ("Could not connect. Check your connection and try again.", ["Could not connect. Check your connection and try again.", "לא הצלחנו להתחבר. בדקו את החיבור ונסו שוב.", "No se pudo conectar. Revisa la conexión e inténtalo de nuevo.", "تعذّر الاتصال. تحقق من اتصالك وحاول مجددًا.", "कनेक्ट नहीं हो सका। कनेक्शन जाँचें और फिर से कोशिश करें।", "Verbinden is niet gelukt. Controleer je verbinding en probeer het opnieuw."]),
        ("Start & learn", ["Start & learn", "מתחילים ולומדים", "Empieza y aprende", "ابدأ وتعلّم", "शुरू करें और सीखें", "Beginnen en leren"]),
        ("Play", ["Play", "משחקים", "Jugar", "العب", "खेलें", "Spelen"]),
        ("Saved games", ["Saved games", "משחקים שמורים", "Partidas guardadas", "الألعاب المحفوظة", "सहेजे गए खेल", "Opgeslagen spellen"]),
        ("Advanced", ["Advanced", "מתקדם", "Más opciones", "خيارات إضافية", "और विकल्प", "Meer opties"]),
        ("White", ["White", "לבן", "Blanco", "أبيض", "सफ़ेद", "Wit"]),
        ("Yellow", ["Yellow", "צהוב", "Amarillo", "أصفر", "पीला", "Geel"]),
        ("Orange", ["Orange", "כתום", "Naranja", "برتقالي", "नारंगी", "Oranje"]),
        ("Green", ["Green", "ירוק", "Verde", "أخضر", "हरा", "Groen"]),
        ("Cyan", ["Cyan", "טורקיז", "Cian", "سماوي", "आसमानी", "Cyaan"]),
        ("Light blue", ["Light blue", "תכלת", "Azul claro", "أزرق فاتح", "हल्का नीला", "Lichtblauw"]),
        ("Pink", ["Pink", "ורוד", "Rosa", "وردي", "गुलाबी", "Roze"]),
        ("Red", ["Red", "אדום", "Rojo", "أحمر", "लाल", "Rood"]),
        ("Blue", ["Blue", "כחול", "Azul", "أزرق", "नीला", "Blauw"]),
        ("Purple", ["Purple", "סגול", "Morado", "بنفسجي", "बैंगनी", "Paars"]),
        ("Brown", ["Brown", "חום", "Marrón", "بني", "भूरा", "Bruin"]),
        ("Silver", ["Silver", "כסף", "Plata", "فضي", "चाँदी", "Zilver"]),
        ("Gold", ["Gold", "זהב", "Oro", "ذهبي", "सोना", "Goud"]),
        ("Catch, jump or duck!", ["Catch, jump or duck!", "תפסו, קפצו או התכופפו!", "¡Atrapa, salta o agáchate!", "أمسك أو اقفز أو انحنِ!", "कैच लें, कूदें या झुकें!", "Vang, spring of buk!"]),
        ("Privacy policy", ["Privacy policy", "מדיניות פרטיות", "Política de privacidad", "سياسة الخصوصية", "गोपनीयता नीति", "Privacybeleid"]),
        ("Family league", ["Family league", "ליגה משפחתית", "Liga familiar", "الدوري العائلي", "पारिवारिक लीग", "Familiecompetitie"]),
        ("Create a family league", ["Create a family league", "יצירת ליגה משפחתית", "Crear liga familiar", "إنشاء دوري عائلي", "पारिवारिक लीग बनाएँ", "Familiecompetitie maken"]),
        ("Join a family league", ["Join a family league", "הצטרפות לליגה משפחתית", "Unirse a una liga familiar", "الانضمام إلى دوري عائلي", "पारिवारिक लीग में जुड़ें", "Aan familiecompetitie meedoen"]),
        ("Choose your house players once. Friends join with the same code each time. Only players who join a round receive points for it.", ["Choose your house players once. Friends join with the same code each time. Only players who join a round receive points for it.", "בוחרים שחקני בית פעם אחת. חברים מצטרפים בכל פעם עם אותו קוד. רק מי שמשתתף במשחק מקבל בו נקודות.", "Elige los jugadores de la casa una vez. Tus amigos usan siempre el mismo código. Solo quienes participan en una ronda reciben sus puntos.", "اختر لاعبي اللعبة مرة واحدة. ينضم الأصدقاء بالرمز نفسه كل مرة. تُحسب نقاط الجولة لمن شاركوا فيها فقط.", "कंप्यूटर खिलाड़ी एक बार चुनें। दोस्त हर बार उसी कोड से जुड़ते हैं। अंक केवल उस दौर में शामिल खिलाड़ियों को मिलते हैं।", "Kies de huisgenoten één keer. Vrienden gebruiken steeds dezelfde code. Alleen deelnemers aan een ronde krijgen er punten voor."]),
        ("You already belong to a family league.", ["You already belong to a family league.", "כבר יש לכם ליגה משפחתית.", "Ya perteneces a una liga familiar.", "أنت عضو في دوري عائلي بالفعل.", "आप पहले से एक पारिवारिक लीग में हैं।", "Je hoort al bij een familiecompetitie."]),
        ("A win earns 3 points. Ties are ordered by fewer penalty points. Absent players keep their totals.", ["A win earns 3 points. Ties are ordered by fewer penalty points. Absent players keep their totals.", "ניצחון מזכה ב־3 נקודות. בשוויון, פחות נקודות חובה קובעות. הניקוד של מי שלא משתתף נשאר ללא שינוי.", "Ganar da 3 puntos. En caso de empate, queda delante quien tenga menos penalizaciones. Los ausentes mantienen sus totales.", "الفوز يمنح 3 نقاط. عند التعادل يتقدم صاحب نقاط الجزاء الأقل. لا يتغير رصيد الغائبين.", "जीत पर 3 अंक मिलते हैं। बराबरी पर कम पेनल्टी अंक वाला आगे रहता है। अनुपस्थित खिलाड़ियों के कुल अंक नहीं बदलते।", "Een overwinning levert 3 punten op. Bij gelijkstand staat degene met minder strafpunten hoger. Afwezigen houden hun totalen."]),
        ("Player", ["Player", "שחקן", "Jugador", "اللاعب", "खिलाड़ी", "Speler"]),
        ("Points", ["Points", "נקודות", "Puntos", "النقاط", "अंक", "Punten"]),
        ("Wins", ["Wins", "ניצחונות", "Victorias", "الانتصارات", "जीत", "Gewonnen"]),
        ("Penalties", ["Penalties", "נקודות חובה", "Penalizaciones", "نقاط الجزاء", "पेनल्टी अंक", "Strafpunten"]),
        ("Games", ["Games", "משחקים", "Partidas", "المباريات", "खेल", "Wedstrijden"]),
        ("Nickname history", ["Nickname history", "היסטוריית כינויים", "Historial de apodos", "سجل الألقاب", "उपनामों का इतिहास", "Bijnamengeschiedenis"]),
        ("Join this round", ["Join this round", "הצטרפות למשחק", "Unirse a esta ronda", "الانضمام إلى الجولة", "इस दौर में जुड़ें", "Aan deze ronde meedoen"]),
        ("New league game", ["New league game", "משחק חדש בליגה", "Nueva partida de liga", "مباراة جديدة في الدوري", "लीग का नया खेल", "Nieuwe competitiewedstrijd"]),
        ("Delete league", ["Delete league", "מחיקת הליגה", "Eliminar liga", "حذف الدوري", "लीग हटाएँ", "Competitie verwijderen"]),
        ("Delete league?", ["Delete league?", "למחוק את הליגה?", "¿Eliminar la liga?", "هل تريد حذف الدوري؟", "लीग हटाएँ?", "Competitie verwijderen?"]),
        ("This deletes the league roster and standings for everyone.", ["This deletes the league roster and standings for everyone.", "הפעולה תמחק את רשימת המשתתפים ואת טבלת הליגה לכולם.", "Se eliminarán la lista de jugadores y la clasificación para todos.", "سيُحذف أعضاء الدوري وترتيبه لدى الجميع.", "इससे सभी के लिए लीग की सूची और अंक तालिका मिट जाएगी।", "Dit verwijdert de deelnemerslijst en de stand voor iedereen."]),
        ("The current round is still open. Join it before starting another.", ["The current round is still open. Join it before starting another.", "המשחק הנוכחי עדיין פתוח. הצטרפו אליו לפני פתיחת משחק נוסף.", "La ronda actual sigue abierta. Únete antes de iniciar otra.", "الجولة الحالية ما زالت مفتوحة. انضم إليها قبل بدء جولة أخرى.", "मौजूदा दौर अभी खुला है। नया शुरू करने से पहले उसमें जुड़ें।", "De huidige ronde staat nog open. Doe daaraan mee voordat je een nieuwe begint."]),
        ("Finish the current round before deleting the league.", ["Finish the current round before deleting the league.", "סיימו את המשחק הנוכחי לפני מחיקת הליגה.", "Termina la ronda actual antes de eliminar la liga.", "أنهِ الجولة الحالية قبل حذف الدوري.", "लीग हटाने से पहले मौजूदा दौर पूरा करें।", "Maak de huidige ronde af voordat je de competitie verwijdert."]),
        ("Back to league", ["Back to league", "חזרה לליגה", "Volver a la liga", "العودة إلى الدوري", "लीग में लौटें", "Terug naar competitie"]),
        ("Open league round", ["Open league round", "פתיחת משחק בליגה", "Abrir ronda de liga", "فتح جولة في الدوري", "लीग का दौर खोलें", "Competitieronde openen"]),
        ("You + {0} house players · {1} places for friends", ["You + {0} house players · {1} places for friends", "אתם + {0} שחקני בית · {1} מקומות לחברים", "Tú + {0} jugadores de la casa · {1} plazas para amigos", "أنت + {0} لاعبين من اللعبة · {1} أماكن للأصدقاء", "आप + {0} कंप्यूटर खिलाड़ी · दोस्तों के लिए {1} जगह", "Jij + {0} huisgenoten · {1} plaatsen voor vrienden"]),
        ("Room capacity", ["Room capacity", "מספר מקומות בחדר", "Capacidad de la sala", "سعة الغرفة", "रूम की क्षमता", "Plaatsen in de kamer"]),
        ("Choose at least one house player.", ["Choose at least one house player.", "בחרו לפחות שחקן בית אחד.", "Elige al menos un jugador de la casa.", "اختر لاعبًا واحدًا على الأقل من لاعبي اللعبة.", "कम से कम एक कंप्यूटर खिलाड़ी चुनें।", "Kies minstens één huisgenoot."]),
        ("Leave at least one place for a friend: remove a house player or increase room capacity (maximum 10).", ["Leave at least one place for a friend: remove a house player or increase room capacity (maximum 10).", "השאירו לפחות מקום אחד לחבר: הסירו שחקן בית או הגדילו את מספר המקומות (עד 10).", "Deja al menos una plaza para un amigo: quita un jugador de la casa o amplía la sala (máximo 10).", "اترك مكانًا واحدًا على الأقل لصديق: أزل لاعبًا من اللعبة أو زد سعة الغرفة (بحد أقصى 10).", "दोस्त के लिए कम से कम एक जगह रखें: एक कंप्यूटर खिलाड़ी हटाएँ या क्षमता बढ़ाएँ (अधिकतम 10)।", "Laat minstens één plaats vrij voor een vriend: verwijder een huisgenoot of vergroot de kamer (maximaal 10)."]),
        ("Ready ✓", ["Ready ✓", "מוכנים ✓", "Listo ✓", "جاهز ✓", "तैयार ✓", "Klaar ✓"]),
        ("{0} players here · {1} free places. Start with the players who have joined (at least 2).", ["{0} players here · {1} free places. Start with the players who have joined (at least 2).", "{0} שחקנים כאן · {1} מקומות פנויים. מתחילים עם מי שהצטרף (לפחות 2).", "{0} jugadores aquí · {1} plazas libres. Empieza con quienes se hayan unido (al menos 2).", "{0} لاعبين هنا · {1} أماكن خالية. ابدأ بمن انضموا (لاعبان على الأقل).", "यहाँ {0} खिलाड़ी · {1} खाली जगह। जुड़े हुए खिलाड़ियों के साथ शुरू करें (कम से कम 2)।", "{0} spelers aanwezig · {1} plaatsen vrij. Begin met wie er is (minstens 2)."]),
        ("This room has ended. Create a new game.", ["This room has ended. Create a new game.", "החדר הסתיים. אפשר ליצור משחק חדש.", "Esta sala ha terminado. Crea una nueva partida.", "انتهت هذه الغرفة. أنشئ مباراة جديدة.", "यह रूम समाप्त हो गया है। नया खेल बनाएँ।", "Deze kamer is afgelopen. Maak een nieuw spel."]),
        ("This room is already open.", ["This room is already open.", "החדר כבר פתוח.", "Esta sala ya está abierta.", "هذه الغرفة مفتوحة بالفعل.", "यह रूम पहले से खुला है।", "Deze kamer is al open."]),
        ("Join this game through your family league.", ["Join this game through your family league.", "הצטרפו למשחק דרך הליגה המשפחתית.", "Únete a esta partida desde tu liga familiar.", "انضم إلى المباراة من خلال الدوري العائلي.", "अपने पारिवारिक लीग से इस खेल में जुड़ें।", "Doe mee via je familiecompetitie."]),
        ("Jump ↑", ["Jump ↑", "קפיצה ↑", "Saltar ↑", "قفز ↑", "कूदें ↑", "Springen ↑"]),
        ("Duck", ["Duck", "כיפוף", "Agacharse", "انحناء", "झुकें", "Bukken"]),
        ("Catch", ["Catch", "תפיסה", "Atrapar", "إمساك", "कैच", "Vangen"]),
    ]

    static let copy: [String: [String]] = {
        var map: [String: [String]] = [:]
        for (key, values) in ordered { map[key] = values }
        return map
    }()
}
