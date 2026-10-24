import Foundation

// Port of questionenginelib QuestionMode.kt (questionenginelib 578ed22). Spec 04 §3.2.
// Case order is the Kotlin ordinal order; `name` is used in the difficulty preference keys.

enum QuestionMode: String, KotlinEnum {
    case ARITHMETIC
    case ENGLISH
    case GENERAL_KNOWLEDGE
    case SCIENCE
    case ASTRONOMY
    case ARTIFICIAL_INTELLIGENCE
    case HISTORY
    case MATHEMATICS
    case PROGRAMMING
    case BAGRUT_MATHEMATICS
    case PARADOXES
}
