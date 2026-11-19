import Foundation

/// Android `core/PracticeGuidance.kt`: the live control hint and the opening brief of a journey challenge or lesson.
enum PracticeGuidance {
    static func live(_ s: SpudStage, _ mode: ThrowMode, _ he: Bool) -> String {
        let target: String
        switch s.skill {
        case .tree, .rebound: target = he ? "העץ" : "the tree"
        case .ring: target = he ? "הטבעת" : "the ring"
        case .ground: target = he ? "האי הזהוב" : "the golden island"
        default: target = he ? "השותף המסומן או תווית השם" : "the marked partner or their name label"
        }
        if mode == .easy {
            return he ? "געו במקום שבו הכדור צריך לפגוע. גובה הנגיעה קובע את גובה הזריקה."
                : "Tap the exact spot to throw. Tap height sets the throw height."
        } else if mode == .target {
            return he ? "געו כשהנקודה הנעה נמצאת במקום שבו רוצים לפגוע." : "Tap when the moving dot is where you want to hit."
        } else if he {
            return "החליקו מהכדור לכיוון \(target). מהירות ההחלקה קובעת עוצמה וגובה."
        } else {
            return "Swipe from your ball toward \(target). Swipe speed sets power and height."
        }
    }

    static func brief(_ s: SpudStage, _ mode: ThrowMode, _ he: Bool) -> String {
        if !s.throwing {
            if s.skill == .catching && s.moving {
                return he ? "הכדור יישלח לסימון בצד. גררו כדי להגיע אליו, וגעו לתפיסה בזמן."
                    : "The ball is sent to a marker beside you. Drag to reach it, then tap to catch as it arrives."
            }
            return s.brief(he)
        }
        if s.skill == .call { return s.brief(he) }
        let goal: String
        switch s.skill {
        case .tag:
            goal = he ? "פגעו בשחקן המסומן. חוק הקרקע מוצג בתחילת השיעור." : "Hit the marked player. The ground rule is shown before this lesson."
        case .tree:
            goal = he ? "פגעו בגזע העץ לפני הנגיעה בקרקע." : "Hit the tree trunk before the ball touches the ground."
        case .rebound:
            goal = he ? "פגעו בגזע ותפסו את הכדור החוזר לפני שינחת." : "Hit the trunk and catch the rebound before it lands."
        case .ring:
            goal = he ? "הכדור צריך לעבור בתוך הטבעת באוויר." : "The ball must pass through the ring in the air."
        case .ground:
            goal = he ? "הנגיעה הראשונה בקרקע צריכה להיות באי הזהוב." : "The first ground contact must be on the golden island."
        default:
            goal = he ? "מסרו לשותף ואז תפסו את המסירה בחזרה." : "Pass to your partner, then catch their return."
        }
        return live(s, mode, he) + "\n" + goal + "\n" + (he ? "אפשר לזוז ולזרוק מכל מקום." : "You can move and throw from anywhere.")
    }
}
