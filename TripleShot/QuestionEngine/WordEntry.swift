import Foundation

// Port of questionenginelib WordEntry.kt (questionenginelib 578ed22). Spec 04 §4.4.
// `values` is the parser's LinkedHashMap (insertion order kept; equality compares it as a map).

struct WordEntry {
    var values: KLinkedMap<String, String>
    var group: String
    var level: Int
    var id: String

    init(values: KLinkedMap<String, String>, group: String, level: Int, id: String) {
        self.values = values
        self.group = group
        self.level = level
        self.id = id
    }

    /// Kotlin's default `id`: `"$group-$level-" + values.entries.sortedBy { it.key }
    /// .joinToString("|") { "${it.key}:${it.value}" }.hashCode()` (WordsXmlParser always passes an id).
    init(values: KLinkedMap<String, String>, group: String, level: Int) {
        let joined = values.entries.kSortedBy { $0.key }.map { "\($0.key):\($0.value)" }.joined(separator: "|")
        self.init(values: values, group: group, level: level, id: "\(group)-\(level)-\(joined.javaHashCode)")
    }

    func value(languageCode: String) -> String? {
        if let v = values[QuestionLocaleContract.normalize(languageCode: languageCode)], !v.kotlinIsBlank { return v }
        if let v = values[languageCode], !v.kotlinIsBlank { return v }
        return nil
    }
}

/// Kotlin data-class `equals` (KLinkedMap `==` is java.util.AbstractMap.equals: order ignored).
extension WordEntry: Equatable {}

extension WordEntry: CustomStringConvertible {
    /// Kotlin data-class `toString` (the map prints `{k=v, ...}` in insertion order).
    var description: String {
        let map = values.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return "WordEntry(values={\(map)}, group=\(group), level=\(level), id=\(id))"
    }
}
