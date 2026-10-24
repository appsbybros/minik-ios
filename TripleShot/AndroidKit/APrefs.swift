import Foundation

// AndroidKit: android.content.SharedPreferences (frameworks/base SharedPreferencesImpl) over
// UserDefaults.standard with the key "<prefsName>.<key>" (the ios-qa SplashPrefs convention). One instance per
// file name, like ContextImpl's cache. Edits are applied to memory and storage synchronously by both apply()
// and commit(); clear() runs before the puts/removes of the same editor; putting a null String/Set removes the
// key; a put of a value equal to the stored one changes nothing (Android skips it).
//
// String sets reproduce Android's iteration order exactly: putStringSet stores `new HashSet<>(values)` (the
// copy constructor, libcore main: HashMap.newHashMap(max(size, 12))) and the file keeps that HashSet's
// iteration order; in the same process getStringSet returns that very HashSet; after a restart the set is read
// back into a default `new HashSet()` in file order. The stored [String] is the file order.

let MODE_PRIVATE = 0

/// `context.getSharedPreferences(name, mode)` (the mode is ignored: always app-private).
func getSharedPreferences(_ name: String, _ mode: Int) -> ASharedPreferences {
    return ASharedPreferences.named(name)
}

final class ASharedPreferences {
    let name: String
    /// UserDefaults.standard; an App Store capture's own suite while one runs (TripleShotScreenshot.preferences).
    private let defaults = TripleShotScreenshot.preferences

    /// The HashSet objects of this process (Android's in-memory map), by key, in iteration order.
    private var stringSets: [String: [String]] = [:]

    private static var instances: [String: ASharedPreferences] = [:]

    /// The shared instance of a preferences file.
    static func named(_ name: String) -> ASharedPreferences {
        if let existing = instances[name] { return existing }
        let created = ASharedPreferences(name: name)
        instances[name] = created
        return created
    }

    private init(name: String) {
        self.name = name
    }

    private func storageKey(_ key: String) -> String {
        return name + "." + key
    }

    private func stored(_ key: String) -> Any? {
        return defaults.object(forKey: storageKey(key))
    }

    func getString(_ k: String, _ d: String?) -> String? {
        return (stored(k) as? String) ?? d
    }

    func getInt(_ k: String, _ d: Int) -> Int {
        guard let value = stored(k) else { return d }
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return d
    }

    func getLong(_ k: String, _ d: Int64) -> Int64 {
        guard let value = stored(k) else { return d }
        if let i = value as? Int64 { return i }
        if let n = value as? NSNumber { return n.int64Value }
        return d
    }

    func getFloat(_ k: String, _ d: Float) -> Float {
        guard let value = stored(k) else { return d }
        if let f = value as? Float { return f }
        if let n = value as? NSNumber { return n.floatValue }
        return d
    }

    func getBoolean(_ k: String, _ d: Bool) -> Bool {
        guard let value = stored(k) else { return d }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return d
    }

    /// `getStringSet(key, defValues)`: the elements in java.util.HashSet iteration order (see the file
    /// comment); `d` itself when the key is missing.
    func getStringSet(_ k: String, _ d: [String]?) -> [String]? {
        if let inMemory = stringSets[k] { return inMemory }
        guard let fileOrder = stored(k) as? [String] else { return d }
        // XmlUtils.readThisSetXml: `new HashSet()` filled in file order.
        let order = JavaOrder.hashSetOrder(fileOrder)
        stringSets[k] = order
        return order
    }

    func contains(_ k: String) -> Bool {
        return stored(k) != nil
    }

    /// `getAll()`: every key of this file with its value (string sets in HashSet order).
    func getAll() -> [String: Any] {
        let prefix = name + "."
        var result: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let shortKey = String(key.dropFirst(prefix.count))
            if value is [String] {
                result[shortKey] = getStringSet(shortKey, nil) ?? []
            } else {
                result[shortKey] = value
            }
        }
        return result
    }

    func edit() -> Editor {
        return Editor(self)
    }

    fileprivate enum Change {
        case value(Any)
        case stringSet([String])
        case remove
    }

    fileprivate func apply(clear: Bool, changes: [(String, Change)]) {
        if clear {
            let prefix = name + "."
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
            stringSets.removeAll()
        }
        for (key, change) in changes {
            switch change {
            case .remove:
                defaults.removeObject(forKey: storageKey(key))
                stringSets[key] = nil
            case .value(let value):
                if let existing = stored(key), ASharedPreferences.equal(existing, value) {
                    continue
                }
                defaults.set(value, forKey: storageKey(key))
                stringSets[key] = nil
            case .stringSet(let values):
                // `new HashSet<String>(values)`; an equal set already in memory is kept as it is.
                let copy = JavaOrder.hashSetCopyOrder(values)
                if let existing = getStringSet(key, nil), Set(existing) == Set(copy) {
                    continue
                }
                defaults.set(copy, forKey: storageKey(key))
                stringSets[key] = copy
            }
        }
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as String, y as String): return x == y
        case let (x as Bool, y as Bool): return x == y
        case let (x as NSNumber, y as NSNumber): return x == y
        default: return false
        }
    }

    /// SharedPreferences.Editor: the changes are applied in order when committed (clear() first).
    final class Editor {
        private let prefs: ASharedPreferences
        private var clearRequested = false
        private var changes: [(String, Change)] = []

        fileprivate init(_ prefs: ASharedPreferences) {
            self.prefs = prefs
        }

        private func record(_ key: String, _ change: Change) -> Editor {
            // mModified is a map: a later change of the same key replaces the earlier one.
            changes.removeAll { $0.0 == key }
            changes.append((key, change))
            return self
        }

        @discardableResult
        func putString(_ k: String, _ v: String?) -> Editor {
            guard let v = v else { return record(k, .remove) }
            return record(k, .value(v))
        }

        @discardableResult
        func putInt(_ k: String, _ v: Int) -> Editor { return record(k, .value(v)) }

        @discardableResult
        func putLong(_ k: String, _ v: Int64) -> Editor { return record(k, .value(v)) }

        @discardableResult
        func putFloat(_ k: String, _ v: Float) -> Editor { return record(k, .value(v)) }

        @discardableResult
        func putBoolean(_ k: String, _ v: Bool) -> Editor { return record(k, .value(v)) }

        /// `putStringSet(key, values)`: `values` in the iteration order of the Kotlin set (duplicates ignored).
        @discardableResult
        func putStringSet(_ k: String, _ v: [String]?) -> Editor {
            guard let v = v else { return record(k, .remove) }
            var seen = Set<String>()
            let unique = v.filter { seen.insert($0).inserted }
            return record(k, .stringSet(unique))
        }

        @discardableResult
        func remove(_ k: String) -> Editor { return record(k, .remove) }

        @discardableResult
        func clear() -> Editor {
            clearRequested = true
            return self
        }

        func apply() {
            prefs.apply(clear: clearRequested, changes: changes)
            clearRequested = false
            changes.removeAll()
        }

        @discardableResult
        func commit() -> Bool {
            apply()
            return true
        }
    }
}
