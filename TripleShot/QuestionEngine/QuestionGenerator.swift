import Foundation

// Port of questionenginelib QuestionGenerator.kt (questionenginelib 578ed22). Spec 04 §3.2.

protocol QuestionGenerator: AnyObject {
    var mode: QuestionMode { get }
    var minLevel: Int { get }
    var maxLevel: Int { get }
    func generate(level: Int) -> Question
}
