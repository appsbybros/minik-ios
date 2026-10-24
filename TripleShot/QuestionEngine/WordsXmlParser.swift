import Foundation

// Port of questionenginelib WordsXmlParser.kt (questionenginelib 578ed22). Spec 04 §4.4.
// Plain DOM parse (DocumentBuilderFactory defaults, no DOCTYPE guard) through AndroidKit AXmlDocument, Android's
// DocumentBuilderImpl: comments are not elements, so the commented-out words of words.xml are skipped, and
// `attributes` is the NamedNodeMap in source order (ar, en, es, he in words.xml). Nothing catches its errors on
// Android (a crash), hence `try!` and preconditions.

/** Reads the existing words.xml format unchanged. */
enum WordsXmlParser {
    static func parse(input: Data) -> [WordEntry] {
        let doc = try! AXmlDocument.parse(input)
        let arrays = doc.documentElement.getElementsByTagName("string-array")
        var out: [WordEntry] = []
        var ids = Set<String>()
        for i in kuntil(0, arrays.count) {
            let array = arrays[i]
            let name = array.getAttribute("name")
            let suffix = QuestionsKotlin.substringAfterLast(name, "_", "a").lowercased()
            let level: Int
            switch suffix {
            case "a": level = 1
            case "b": level = 2
            case "c": level = 3
            case "d": level = 4
            case "e": level = 5
            default: level = 3
            }
            let words = array.getElementsByTagName("word")
            for j in kuntil(0, words.count) {
                let w = words[j]
                var values = KLinkedMap<String, String>()
                let attrs = w.attributes
                for k in kuntil(0, attrs.count) {
                    let a = attrs[k]
                    let rawKey = a.nodeName.lowercased()
                    let key = rawKey == "iw" ? "he" : rawKey
                    let value = a.nodeValue!.ktrim()
                    if QuestionLocaleContract.contentLocales.contains(key) && !value.kotlinIsBlank { values[key] = value }
                }
                precondition(!values.isEmpty, "word \(name)-\(j) has no translations")
                let id = "\(name)-\(j)"
                precondition(ids.insert(id).inserted, "Duplicate word id: \(id)")
                out.append(WordEntry(values: values, group: name, level: level, id: id))
            }
        }
        return out
    }
}
