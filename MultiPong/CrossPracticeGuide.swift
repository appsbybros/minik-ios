import Foundation

/// Android cross/CrossPracticeGuide.kt (MinikCrossPong c93e760, dd94c09): the Daily Challenge and Learn instructions and the live
/// tip describe the assisted practice gestures (drag the player to meet the ball, tap a court to aim; the paddle hits
/// automatically). Competitive controls are unchanged. English and Hebrew verbatim; the other languages through `MPText` (the
/// catalog group dailyGuide2026).
enum CrossPracticeGuide {
    private static func t0(_ he: Bool) -> String { MPText.t("Drag your player left or right to meet the ball. The paddle hits automatically.", "גררו את הדמות ימינה או שמאלה כדי לפגוש את הכדור. המחבט חובט אוטומטית.", he) }
    private static func t1(_ he: Bool) -> String { MPText.t("To aim, tap a spot on another court before contact. Each safe return counts.", "כדי לכוון, הקישו על נקודה בצד אחר לפני החבטה. כל החזרה שנוחתת על השולחן נחשבת.", he) }
    private static func t2(_ he: Bool) -> String { MPText.t("Tap the gold target first, then drag your player left or right to meet the ball.", "קודם הקישו על המטרה הזהובה, ואז גררו את הדמות ימינה או שמאלה כדי לפגוש את הכדור.", he) }
    private static func t3(_ he: Bool) -> String { MPText.t("The paddle returns toward your selected spot automatically. A hit on the target counts.", "המחבט מחזיר אוטומטית לכיוון הנקודה שבחרתם. פגיעה במטרה נחשבת.", he) }
    private static func t4(_ he: Bool) -> String { MPText.t("Follow the numbered gold targets in order.", "עברו לפי הסדר בין המטרות הזהובות הממוספרות.", he) }
    private static func t5(_ he: Bool) -> String { MPText.t("Meet the ball on your left for a backhand.", "פגשו את הכדור בצד שמאל שלכם לחבטת גב כף היד.", he) }
    private static func t6(_ he: Bool) -> String { MPText.t("Meet the ball on your right for a forehand.", "פגשו את הכדור בצד ימין שלכם לחבטת כף היד.", he) }
    private static func t7(_ he: Bool) -> String { MPText.t("Tap the highlighted court to serve. The ball must bounce on your side, then on the highlighted court.", "הקישו על הצד המודגש כדי להגיש. הכדור צריך לקפוץ בצד שלכם ואז בצד המודגש.", he) }
    private static func t8(_ he: Bool) -> String { MPText.t("Tap your teammate's court, then drag left or right to meet the ball. The paddle passes automatically. One teammate pass is allowed before returning to an opponent.", "הקישו על הצד של חבר הקבוצה ואז גררו ימינה או שמאלה כדי לפגוש את הכדור. המחבט מוסר אוטומטית. מותרת מסירה אחת לחבר לפני שמחזירים ליריב.", he) }
    private static func t9(_ he: Bool) -> String { MPText.t("Drag your player into the ball's path. Tap twice quickly near the approaching ball to send a high pass to your teammate.", "גררו את הדמות למסלול הכדור. הקישו פעמיים במהירות ליד הכדור המתקרב כדי למסור כדור גבוה לחבר הקבוצה.", he) }
    private static func t10(_ he: Bool) -> String { MPText.t("Your teammate sends a high pass. Wait for it to bounce on your court, then swipe up through the ball toward an opponent. This smash needs a swipe, not an automatic hit.", "חבר הקבוצה מוסר כדור גבוה. חכו לקפיצה בצד שלכם ואז החליקו למעלה דרך הכדור לכיוון יריב. ההנחתה הזאת דורשת החלקה, ולא חבטה אוטומטית.", he) }
    private static func t11(_ he: Bool) -> String { MPText.t("Tap opponents' courts to aim and drag left or right to meet the ball. Returns paint; serves do not. Cover more territory in 90 seconds and make at least three returns yourself.", "הקישו על צדדי היריבים כדי לכוון וגררו ימינה או שמאלה כדי לפגוש את הכדור. החזרות צובעות; הגשות לא. כסו יותר שטח בתוך 90 שניות והחזירו לפחות שלושה כדורים בעצמכם.", he) }
    private static func t12(_ he: Bool) -> String { MPText.t("Tap the gold target to start the next ball.", "הקישו על המטרה הזהובה כדי להתחיל את הכדור הבא.", he) }
    private static func t13(_ he: Bool) -> String { MPText.t("Target chosen. Drag left or right to meet the ball.", "המטרה נבחרה. גררו ימינה או שמאלה כדי לפגוש את הכדור.", he) }
    private static func t14(_ he: Bool) -> String { MPText.t("Drag left or right. The paddle hits automatically.", "גררו ימינה או שמאלה. המחבט חובט אוטומטית.", he) }
    private static func t15(_ he: Bool) -> String { MPText.t("Wait for your teammate's high pass.", "חכו למסירה הגבוהה של חבר הקבוצה.", he) }
    private static func t16(_ he: Bool) -> String { MPText.t("Tap your teammate's court, then meet the ball.", "הקישו על הצד של חבר הקבוצה ואז פגשו את הכדור.", he) }
    /// Android `instruction`: the stage brief, the Help card (after the controls line) and the Learn lessons.
    static func instruction(_ s: CrossStage, _ he: Bool) -> String {
        switch s.skill {
        case .serve: return t7(he)
        case .returning, .defend: return t0(he) + "\n\n" + t1(he)
        case .aim: return t2(he) + "\n\n" + t3(he)
        case .backhand: return t2(he) + "\n\n" + t5(he) + " " + t3(he)
        case .forehand: return t2(he) + "\n\n" + t6(he) + " " + t3(he)
        case .shape: return t4(he) + "\n\n" + t2(he) + " " + t3(he)
        case .pass: return t8(he)
        case .set: return t9(he)
        case .smash: return t10(he)
        case .paint: return t11(he)
        }
    }
    /// Android `tip`: the live tip of a practice. An aiming lesson asks for the gold target until one is chosen (the feeder waits,
    /// CrossPractice.advance); the set practice shows the double-tap hint while it applies.
    static func tip(_ p: CrossPractice, _ he: Bool) -> String {
        if p.stage.aimed { return p.engine.selectedAim == nil ? t12(he) : t13(he) }
        switch p.stage.skill {
        case .pass: return t16(he)
        case .set: return CrossText.setTip(p.engine, he) ?? t14(he)
        case .smash: return t15(he)
        default: return t14(he)
        }
    }
}
