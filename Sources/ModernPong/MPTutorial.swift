import Foundation

/// Android ModernTutorial order: three serves, the Beginner automatic return, five tap/aim returns, then the two Pro
/// spin lessons (2026-10).
enum MPTutorialStep: Int, CaseIterable {
    case serveMiddle, serveLeft, serveRight, autoReturn, middleAny, middleRight, leftMiddle, leftLeft, rightLeft, topspin, sidespin
    var serve: Bool { rawValue < 3 }
    /// Android `TutorialLesson.spin`.
    var spin: Bool { self == .topspin || self == .sidespin }
    /// The automatic-return lesson runs on Beginner, the spin lessons on Android HARD (iOS `.superHard`, Pro); every
    /// other lesson uses Android's EASY court (iOS `.medium`).
    var level: MPLevel { self == .autoReturn ? .beginner : spin ? .superHard : .medium }
    /// Android `ModernTutorial.newEngine(expectedSpin=)`: 1 top spin, 2 side spin, 0 none.
    var expectedSpin: Int { self == .topspin ? 1 : self == .sidespin ? 2 : 0 }
    var incoming: Double? { switch self { case .middleAny, .middleRight: return 0; case .autoReturn, .leftMiddle, .leftLeft: return -1; case .rightLeft: return 1; default: return nil } }
    var target: MPZone? { switch self { case .serveMiddle, .leftMiddle: return .middle; case .serveLeft, .leftLeft, .rightLeft: return .left; case .serveRight, .middleRight: return .right; default: return nil } }
    var aim: Double { switch self { case .serveLeft, .leftLeft, .rightLeft: return -1; case .serveRight, .middleRight: return 1; case .leftMiddle: return 0.025 / 0.085; default: return 0 } }
    var exercise: MPExercise { .init(serve: serve, incoming: incoming, expected: target) }
    /// Android `TutorialLesson.swipeDirection`: the aimed returns' demonstrated swipe direction.
    var swipeDirection: Double? { switch self { case .middleRight, .leftMiddle: return 1; case .leftLeft, .rightLeft: return -1; default: return nil } }
    /// Android `ModernTutorial.demonstrate` (2026-10): the demonstrated Standard swipe `standardSwipe(Vec(aim, -0.9))`.
    var demoAim: Double { switch self { case .leftLeft: return -0.15; case .rightLeft: return -0.68; case .leftMiddle: return 0.35; default: return 0.60 } }
    /// Android `ModernTutorial.demonstrate`: the spin lessons' demonstrated Pro strokes.
    var demoStroke: MPPongStroke? {
        switch self {
        case .topspin: return MPPongStroke(aim: -0.5, power: 0.7, top: 0.8, side: 0)
        case .sidespin: return MPPongStroke(aim: 0.6, power: 0.7, top: 0, side: -0.8)
        default: return nil
        }
    }
    var servePoint: MPPoint { switch self { case .serveLeft: return .init(0.16, 0.22); case .serveRight: return .init(0.84, 0.22); default: return .init(0.5, 0.85) } }
    func title(_ he: Bool) -> String {
        // Android `guide_spin_title` for both spin lessons.
        let en = ["Serve: try a tap", "Serve to the left", "Serve to the right", "Move into place. We time the hit!", "Return with a tap", "Aim from the middle to a side", "Return from a side to the middle", "Return to the same side", "Return to the opposite side", "Pro spin workshop", "Pro spin workshop"]
        let heb = ["הגשה: נסו נגיעה", "הגישו לשמאל", "הגישו לימין", "מזיזים והמחבט חובט", "החזירו בנגיעה", "כוונו מהאמצע לצד", "החזירו מהצד לאמצע", "החזירו לאותו הצד", "החזירו לצד הנגדי", "סדנת סיבוב למקצוענים", "סדנת סיבוב למקצוענים"]
        return (he ? heb : en)[rawValue]
    }
    /// Android `guide_spin_hint` for the spin lessons' try; nil for the others.
    func hint(_ he: Bool) -> String? {
        spin ? (he ? "קשת לסיבוב קדמי, שינוי כיוון לסיבוב צדדי. שחררו כדי לחבוט." : "Swipe an arc for topspin, or change direction for sidespin. Release to hit.") : nil
    }
    /// The lesson texts. The aimed returns and spin lessons follow Android 2026-10 (`guide_middle_right` …
    /// `guide_sidespin`): move to the ball, then swipe as it arrives; no tap first. The house player is Mega Minik.
    func instruction(_ he: Bool) -> String {
        let en = [
            "Tap any point on the table to aim your serve there. First, tap the middle of your side of the table to get a feel for serving. The ball bounces on your side, then Mega Minik’s side.",
            "Tap the left third of Mega Minik’s side of the table. Your serve must land on that side. Left and right are as you see them on the screen.",
            "Now tap the right third of Mega Minik’s side of the table. Watch the diagonal serve and where it lands.",
            "Beginner is the default. Drag your paddle into the incoming ball’s path on your side. You can position it early and lift your finger: it stays there and hits at the right time. Move left to meet this ball.",
            "Mega Minik sends a gentle ball to the middle. Tap anywhere on your half as it approaches your paddle. Timing matters; you do not need to tap directly on the ball. You can return anywhere.",
            "Move to the ball. As it reaches your paddle, swipe diagonally right to aim right. No tap first: swipe speed sets the return speed and depth.",
            "Move left to meet the ball, then swipe gently toward the right as it arrives to aim toward the middle.",
            "Move left to meet the ball, then swipe slightly left as it reaches the paddle. A very wide sideways swipe can go out.",
            "Move right to meet the ball, then swipe diagonally left as it arrives to send it across the table.",
            "Pro topspin: swipe a forward arc and release as the ball approaches. The arc makes the ball rise and dip; a faster arc adds stronger spin, without unlimited shot speed. Land one topspin return on the far half.",
            "Pro sidespin: swipe left then right and release. The final direction aims right while the spin curves left. Reverse the gesture for the opposite shot. Land one sidespin return on the far half."
        ]
        let heb = [
            "געו בכל נקודה בשולחן כדי לכוון אליה את ההגשה. תחילה, געו באמצע הצד שלכם בשולחן כדי להרגיש את ההגשה. הכדור קופץ בצד שלכם ואז בצד של מגה מיניק.",
            "געו בשליש השמאלי בצד של מגה מיניק בשולחן. ההגשה צריכה לנחות שם. שמאל וימין הם כפי שרואים אותם על המסך.",
            "עכשיו געו בשליש הימני בצד של מגה מיניק בשולחן. שימו לב להגשה האלכסונית ולמקום שבו הכדור נוחת.",
            "ברמת מתחילים מספיק להציב את המחבט בדרך של הכדור בצד שלכם. אפשר לגרור אותו מראש ולהרים את האצבע — הוא יישאר במקום ויחבוט בזמן הנכון. נסו להזיז אותו שמאלה לקראת הכדור.",
            "מגה מיניק שולח כדור קל לאמצע. הקישו במקום כלשהו בחצי שלכם כשהכדור מתקרב למחבט. חשוב לתזמן את ההקשה; אין צורך לגעת בכדור עצמו. אפשר להחזיר לכל מקום.",
            "זוזו לכדור. כשהוא מגיע למחבט, החליקו באלכסון ימינה כדי לכוון ימינה. אין צורך להקיש קודם: מהירות ההחלקה קובעת את מהירות ועומק ההחזרה.",
            "זוזו שמאלה אל הכדור, ואז החליקו בעדינות ימינה כשהוא מגיע כדי לכוון למרכז.",
            "זוזו שמאלה אל הכדור ואז החליקו מעט שמאלה כשהוא מגיע למחבט. החלקה חזקה הצדה עלולה להוציא את הכדור.",
            "זוזו ימינה אל הכדור, ואז החליקו באלכסון שמאלה כשהוא מגיע כדי להעביר אותו לצד השני.",
            "סיבוב קדמי למקצוענים: כשהכדור מתקרב, החליקו בקשת קדימה ושחררו. הכדור עולה ואז צולל; קשת מהירה מחזקת את הסיבוב בלי להאיץ את הכדור ללא הגבלה. הנחיתו חבטה מסובבת בצד השני.",
            "סיבוב צדדי למקצוענים: החליקו שמאלה ואז ימינה ושחררו. הכיוון האחרון מכוון ימינה והסיבוב מעקם שמאלה. הפכו את התנועה לחבטה הפוכה. הנחיתו חבטה עם סיבוב צדדי בצד השני."
        ]; return (he ? heb : en)[rawValue]
    }
}
enum MPTutorialPhase { case explanation, demonstration, attempt, feedback }
