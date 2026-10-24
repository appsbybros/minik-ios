import Foundation

// Firebase Realtime Database wire format of the TripleShot models, exactly as Firebase Android
// (firebase-database 22.0.1, CustomClassMapper; verified against its bytecode and run on the JVM) writes and
// reads them. Spec 01 section 4.3, spec 05 section 8, DESIGN section 12 (the "tms" quirk is kept).
//
// Writing: `toFirebaseMap()` is what CustomClassMapper.convertToPlainJavaTypes(object) produces for
// DatabaseReference.setValue / updateChildren / MutableData.setValue(object):
// - one key per public getter: the property names, plus "finished" (from LiveHorseState.isFinished()), and
//   "tms" for ShotReplaySample.tMs (getter getTMs(): the leading upper-case run "TM" is lower-cased);
// - every key is present, including "", 0, false and empty lists/maps (Firebase itself drops empty nodes);
// - Kotlin Int and Long as integers (Int64); Kotlin Float as Float.doubleValue(), except that an integral value
//   within +-2^63 is written as a Long (512f -> 512, -0f -> 0, 0.7f -> 0.699999988079071);
// - lists as arrays, maps as dictionaries.
//
// Reading: `fromFirebaseOrThrow(value)` is CustomClassMapper.convertToCustomClass(value, X::class.java), i.e.
// DataSnapshot.getValue(X::class.java) / MutableData.getValue(X::class.java), on the plain value Firebase
// Android builds from the node (HashMap, ArrayList, String, Long, Double, Boolean; here [String: Any], [Any],
// String, Int64, Double, Bool or the Foundation objects of the iOS SDK):
// - nil / NSNull (no node) -> nil;
// - the entries are visited in java.util.HashMap order (BeanMapper.deserialize iterates the HashMap that
//   ChildrenNode.getValue filled in child-key order), so the first failing key and the warnings are Android's;
// - keys match the property (field) names case-sensitively; any other key is skipped with Android's
//   Log.w("ClassMapper", "No setter/field for <key> found on class <class>[ (fields/setters are case
//   sensitive!)]"), so "tms" is NOT read back into tMs (a "tMs" key would be) and "finished" in a horse node is
//   ignored;
// - missing keys keep the Kotlin defaults;
// - the number coercions of convertInteger / convertLong / convertDouble (truncation toward zero, 32-bit and
//   64-bit range checks, Long -> Double precision check); a Boolean must be a JSON boolean, a String must be a
//   string, a List must be an array and a Map must be an object.
// Where Android throws a DatabaseException, fromFirebaseOrThrow throws ADatabaseException with Android's
// message, and fromFirebase returns nil. (In Android listeners that exception would crash the app; inside
// Transaction.Handler.doTransaction Firebase turns it into an aborted transaction with that error.)
// Only deviation: a JSON null inside an object or list (which Firebase never delivers) is skipped instead of
// being stored as a Kotlin null in a non-null field.

/** The parts of Firebase Android's CustomClassMapper that the TripleShot wire classes go through. */
enum TripleShotModelsFirebaseCodec {

    /** CustomClassMapper's log tag. */
    static let LOG_TAG = "ClassMapper"

    /**
     * Test hook: receives every "No setter/field" warning as Android logs it with Log.w(LOG_TAG, message)
     * (the warning also goes to ALog).
     */
    nonisolated(unsafe) static var warningSink: ((String) -> Void)?

    // MARK: Writing (CustomClassMapper.serialize)

    /** java.lang.Integer / java.lang.Long are written unchanged (JSON integers). */
    static func integer(_ value: Int) -> Any {
        return Int64(value)
    }

    /**
     * java.lang.Float: `d = doubleValue()`; if `d <= 2^63 && d >= -2^63 && Math.floor(d) == d` then
     * `Long.valueOf(longValue())`, else `Double.valueOf(d)`.
     */
    static func float(_ value: Float) -> Any {
        let d = Double(value)
        if d <= 0x1p63 && d >= -0x1p63 && d.rounded(.down) == d {
            return javaLong(d)
        }
        return d
    }

    /** Map<String, Int>: a HashMap of the serialized values (key order is not part of the wire format). */
    static func integerMap(_ map: [String: Int]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in map {
            result[key] = integer(value)
        }
        return result
    }

    // MARK: Reading (CustomClassMapper.deserializeToType)

    /** What Firebase Android hands to the mapper for a JSON number: Long or Double. */
    enum JavaNumber {
        case long(Int64)
        case double(Double)
    }

    static func isNull(_ value: Any?) -> Bool {
        guard let value = value else { return true }
        return value is NSNull
    }

    static func isBoolean(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /** nil for non-numbers and for JSON booleans (a Boolean is not a Number in Java). */
    static func javaNumber(_ value: Any) -> JavaNumber? {
        guard !(value is String), let number = value as? NSNumber, !isBoolean(number) else { return nil }
        if number is NSDecimalNumber {
            // JSONSerialization may return long numbers as NSDecimalNumber; its doubleValue is not always
            // correctly rounded, the decimal text is.
            let text = number.stringValue
            if let exact = Int64(text) { return .long(exact) }
            if let exact = Double(text) { return .double(exact) }
            return .double(number.doubleValue)
        }
        if CFNumberIsFloatType(number as CFNumber) {
            return .double(number.doubleValue)
        }
        return .long(number.int64Value)
    }

    /** Java `(long) d`: truncation toward zero, NaN -> 0, saturating. */
    static func javaLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 0x1p63 { return Int64.max }
        if d <= -0x1p63 { return Int64.min }
        return Int64(d)
    }

    /** CustomClassMapper.convertInteger. */
    static func convertInteger(_ value: Any) throws -> Int {
        guard let number = javaNumber(value) else {
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to int")
        }
        // double value = ((Number) o).doubleValue(); in range -> ((Number) o).intValue()
        let d: Double
        switch number {
        case .long(let l): d = Double(l)
        case .double(let v): d = v
        }
        if d >= -2147483648.0 && d <= 2147483647.0 {
            switch number {
            case .long(let l): return Int(l)
            case .double(let v): return Int(v.rounded(.towardZero))
            }
        }
        throw ADatabaseException(
            "Numeric value out of 32-bit integer range: \(javaString(d)). Did you mean to use a long or double instead of an int?"
        )
    }

    /** CustomClassMapper.convertLong. */
    static func convertLong(_ value: Any) throws -> Int64 {
        switch javaNumber(value) {
        case .long(let l)?:
            return l
        case .double(let d)?:
            if d >= -0x1p63 && d <= 0x1p63 {
                return javaLong(d)
            }
            throw ADatabaseException(
                "Numeric value out of 64-bit long range: \(javaString(d)). Did you mean to use a double instead of a long?"
            )
        case nil:
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to long")
        }
    }

    /** CustomClassMapper.convertDouble. */
    static func convertDouble(_ value: Any) throws -> Double {
        switch javaNumber(value) {
        case .long(let l)?:
            let d = Double(l)
            if javaLong(d) == l {
                return d
            }
            throw ADatabaseException(
                "Loss of precision while converting number to double: \(l). Did you mean to use a 64-bit long instead?"
            )
        case .double(let d)?:
            return d
        case nil:
            throw ADatabaseException("Failed to convert a value of type \(javaClassName(value)) to double")
        }
    }

    /** Float fields: `convertDouble(o).floatValue()`. */
    static func convertFloat(_ value: Any) throws -> Float {
        return Float(try convertDouble(value))
    }

    /** CustomClassMapper.convertBoolean. */
    static func convertBoolean(_ value: Any) throws -> Bool {
        if !(value is String), let number = value as? NSNumber, isBoolean(number) {
            return number.boolValue
        }
        throw ADatabaseException("Failed to convert value of type \(javaClassName(value)) to boolean")
    }

    /** CustomClassMapper.convertString. */
    static func convertString(_ value: Any) throws -> String {
        if let text = value as? String {
            return text
        }
        throw ADatabaseException("Failed to convert value of type \(javaClassName(value)) to String")
    }

    /**
     * CustomClassMapper.convertBean + BeanMapper.deserialize: the node must be an object; its entries in the
     * iteration order of the java.util.HashMap Android deserializes.
     */
    static func bean(_ value: Any, _ className: String) throws -> [(key: String, value: Any)] {
        guard let map = stringKeyedMap(value) else {
            throw ADatabaseException("Can't convert object of type \(javaClassName(value)) to type \(className)")
        }
        return hashMapEntries(map)
    }

    /** BeanMapper.deserialize for a key without a field: Android's warning (never an error for these classes). */
    static func unknownProperty(_ key: String, _ className: String, _ properties: Set<String>) {
        var message = "No setter/field for " + key + " found on class " + className
        // properties is keyed by the lower-cased (Locale.US) serialized names.
        if properties.contains(key.lowercased()) {
            message += " (fields/setters are case sensitive!)"
        }
        ALog.w(LOG_TAG, message)
        warningSink?(message)
    }

    /** The lower-cased serialized property names of a bean (BeanMapper.properties keys). */
    static func properties(_ serialized: [String: Any]) -> Set<String> {
        return Set(serialized.keys.map { $0.lowercased() })
    }

    /** List<T> fields. */
    static func expectList(_ value: Any) throws -> [Any] {
        if !(value is String), let list = value as? [Any] {
            return list
        }
        throw ADatabaseException("Expected a List while deserializing, but got a class \(javaClassName(value))")
    }

    /** Map<String, T> fields (CustomClassMapper.expectMap), entries in HashMap order. */
    static func expectMap(_ value: Any) throws -> [(key: String, value: Any)] {
        if let map = stringKeyedMap(value) {
            return hashMapEntries(map)
        }
        throw ADatabaseException("Expected a Map while deserializing, but got a class \(javaClassName(value))")
    }

    static func convertStringList(_ value: Any) throws -> [String] {
        var result: [String] = []
        for item in try expectList(value) where !isNull(item) {
            result.append(try convertString(item))
        }
        return result
    }

    static func convertIntegerMap(_ value: Any) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, item) in try expectMap(value) where !isNull(item) {
            result[key] = try convertInteger(item)
        }
        return result
    }

    /** A JSON object as [String: Any] (Swift dictionaries and the iOS SDK's NSDictionary). */
    private static func stringKeyedMap(_ value: Any) -> [String: Any]? {
        if value is String { return nil }
        if let map = value as? [String: Any] {
            return map
        }
        if let map = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, item) in map {
                guard let text = key.base as? String else { return nil }
                result[text] = item
            }
            return result
        }
        return nil
    }

    /** The entries as a java.util.HashMap filled in Firebase child-key order iterates them. */
    private static func hashMapEntries(_ map: [String: Any]) -> [(key: String, value: Any)] {
        return JavaOrder.hashMapOrder(Array(map.keys)).map { (key: $0, value: map[$0]!) }
    }

    /** `o.getClass().getName()` of the plain value Android would hold (used in the exception texts). */
    static func javaClassName(_ value: Any) -> String {
        if value is String { return "java.lang.String" }
        if let number = value as? NSNumber {
            if isBoolean(number) { return "java.lang.Boolean" }
            if case .double? = javaNumber(number) { return "java.lang.Double" }
            return "java.lang.Long"
        }
        if value is [Any] { return "java.util.ArrayList" }
        if stringKeyedMap(value) != nil { return "java.util.HashMap" }
        return String(describing: type(of: value))
    }
}

private typealias Codec = TripleShotModelsFirebaseCodec

// MARK: - RoomMeta (rooms/{CODE}/meta; Android writes it by explicit paths and reads it with getValue)

extension RoomMeta {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.RoomMeta"
    private static let firebaseProperties = Codec.properties(RoomMeta().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            "hostUid": hostUid,
            "status": status,
            "seed": seed,
            "createdAt": createdAt,
            "startedAt": startedAt,
            "gameType": gameType,
            "categories": categories,
            "timeLimitSeconds": Codec.integer(timeLimitSeconds),
            "maxPlayers": Codec.integer(maxPlayers)
        ]
    }

    static func fromFirebase(_ value: Any?) -> RoomMeta? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> RoomMeta? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = RoomMeta()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "hostUid": result.hostUid = try Codec.convertString(item)
            case "status": result.status = try Codec.convertString(item)
            case "seed": result.seed = try Codec.convertLong(item)
            case "createdAt": result.createdAt = try Codec.convertLong(item)
            case "startedAt": result.startedAt = try Codec.convertLong(item)
            case "gameType": result.gameType = try Codec.convertString(item)
            case "categories": result.categories = try Codec.convertStringList(item)
            case "timeLimitSeconds": result.timeLimitSeconds = try Codec.convertInteger(item)
            case "maxPlayers": result.maxPlayers = try Codec.convertInteger(item)
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}

// MARK: - LivePlayerState (rooms/{CODE}/players/{uid}; Android writes explicit maps and reads with getValue)

extension LivePlayerState {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.LivePlayerState"
    private static let firebaseProperties = Codec.properties(LivePlayerState().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            "uid": uid,
            "name": name,
            "score": Codec.integer(score),
            "knowledgeStreak": Codec.integer(knowledgeStreak),
            "shootingStreak": Codec.integer(shootingStreak),
            "bestKnowledgeStreak": Codec.integer(bestKnowledgeStreak),
            "bestShootingStreak": Codec.integer(bestShootingStreak),
            "correctAnswers": Codec.integer(correctAnswers),
            "madeShots": Codec.integer(madeShots),
            "shots": Codec.integer(shots),
            "lastEvent": lastEvent,
            "finished": finished,
            "updatedAt": updatedAt
        ]
    }

    static func fromFirebase(_ value: Any?) -> LivePlayerState? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> LivePlayerState? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = LivePlayerState()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "uid": result.uid = try Codec.convertString(item)
            case "name": result.name = try Codec.convertString(item)
            case "score": result.score = try Codec.convertInteger(item)
            case "knowledgeStreak": result.knowledgeStreak = try Codec.convertInteger(item)
            case "shootingStreak": result.shootingStreak = try Codec.convertInteger(item)
            case "bestKnowledgeStreak": result.bestKnowledgeStreak = try Codec.convertInteger(item)
            case "bestShootingStreak": result.bestShootingStreak = try Codec.convertInteger(item)
            case "correctAnswers": result.correctAnswers = try Codec.convertInteger(item)
            case "madeShots": result.madeShots = try Codec.convertInteger(item)
            case "shots": result.shots = try Codec.convertInteger(item)
            case "lastEvent": result.lastEvent = try Codec.convertString(item)
            case "finished": result.finished = try Codec.convertBoolean(item)
            case "updatedAt": result.updatedAt = try Codec.convertLong(item)
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}

// MARK: - LiveHorseState (rooms/{CODE}/horse; written as an object, so "finished" is on the wire)

extension LiveHorseState {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.LiveHorseState"
    private static let firebaseProperties = Codec.properties(LiveHorseState().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            "phase": phase,
            "setterUid": setterUid,
            "currentPlayerUid": currentPlayerUid,
            "challengeEstablished": challengeEstablished,
            "challengeCategory": challengeCategory,
            "challengeSpotId": challengeSpotId,
            "challengeSpotX": Codec.float(challengeSpotX),
            "challengeSpotY": Codec.float(challengeSpotY),
            "playerOrder": playerOrder,
            "attemptedUids": attemptedUids,
            "penalties": Codec.integerMap(penalties),
            "spectatorSlots": Codec.integerMap(spectatorSlots),
            "winnerUid": winnerUid,
            "turnNumber": Codec.integer(turnNumber),
            "updatedAt": updatedAt,
            // Public getter isFinished() -> "finished". Android ignores it when reading.
            "finished": isFinished
        ]
    }

    static func fromFirebase(_ value: Any?) -> LiveHorseState? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> LiveHorseState? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = LiveHorseState()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "phase": result.phase = try Codec.convertString(item)
            case "setterUid": result.setterUid = try Codec.convertString(item)
            case "currentPlayerUid": result.currentPlayerUid = try Codec.convertString(item)
            case "challengeEstablished": result.challengeEstablished = try Codec.convertBoolean(item)
            case "challengeCategory": result.challengeCategory = try Codec.convertString(item)
            case "challengeSpotId": result.challengeSpotId = try Codec.convertString(item)
            case "challengeSpotX": result.challengeSpotX = try Codec.convertFloat(item)
            case "challengeSpotY": result.challengeSpotY = try Codec.convertFloat(item)
            case "playerOrder": result.playerOrder = try Codec.convertStringList(item)
            case "attemptedUids": result.attemptedUids = try Codec.convertStringList(item)
            case "penalties": result.penalties = try Codec.convertIntegerMap(item)
            case "spectatorSlots": result.spectatorSlots = try Codec.convertIntegerMap(item)
            case "winnerUid": result.winnerUid = try Codec.convertString(item)
            case "turnNumber": result.turnNumber = try Codec.convertInteger(item)
            case "updatedAt": result.updatedAt = try Codec.convertLong(item)
            // Includes "finished": no field behind isFinished(), so Android warns and ignores it.
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}

// MARK: - LeaderboardEntry (leaderboard/{uid}; written as an object in a transaction)

extension LeaderboardEntry {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.LeaderboardEntry"
    private static let firebaseProperties = Codec.properties(LeaderboardEntry().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            "uid": uid,
            "name": name,
            "bestScore": Codec.integer(bestScore),
            "bestShootingStreak": Codec.integer(bestShootingStreak),
            "bestKnowledgeStreak": Codec.integer(bestKnowledgeStreak),
            "bestCorrectAnswers": Codec.integer(bestCorrectAnswers),
            "bestRunCorrectAnswers": Codec.integer(bestRunCorrectAnswers),
            "bestRunShots": Codec.integer(bestRunShots),
            "bestRunMadeShots": Codec.integer(bestRunMadeShots),
            "bestRunKnowledgeAccuracyPercent": Codec.integer(bestRunKnowledgeAccuracyPercent),
            "bestRunShootingPercent": Codec.integer(bestRunShootingPercent),
            "bestRunCategories": bestRunCategories,
            "updatedAt": updatedAt
        ]
    }

    static func fromFirebase(_ value: Any?) -> LeaderboardEntry? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> LeaderboardEntry? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = LeaderboardEntry()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "uid": result.uid = try Codec.convertString(item)
            case "name": result.name = try Codec.convertString(item)
            case "bestScore": result.bestScore = try Codec.convertInteger(item)
            case "bestShootingStreak": result.bestShootingStreak = try Codec.convertInteger(item)
            case "bestKnowledgeStreak": result.bestKnowledgeStreak = try Codec.convertInteger(item)
            case "bestCorrectAnswers": result.bestCorrectAnswers = try Codec.convertInteger(item)
            case "bestRunCorrectAnswers": result.bestRunCorrectAnswers = try Codec.convertInteger(item)
            case "bestRunShots": result.bestRunShots = try Codec.convertInteger(item)
            case "bestRunMadeShots": result.bestRunMadeShots = try Codec.convertInteger(item)
            case "bestRunKnowledgeAccuracyPercent": result.bestRunKnowledgeAccuracyPercent = try Codec.convertInteger(item)
            case "bestRunShootingPercent": result.bestRunShootingPercent = try Codec.convertInteger(item)
            case "bestRunCategories": result.bestRunCategories = try Codec.convertStringList(item)
            case "updatedAt": result.updatedAt = try Codec.convertLong(item)
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}

// MARK: - ShotReplaySample (inside LiveShotEvent.samples)

extension ShotReplaySample {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.ShotReplaySample"
    private static let firebaseProperties = Codec.properties(ShotReplaySample().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            // Getter getTMs() -> "tms". Android receivers cannot read it back (they look for "tMs").
            "tms": tMs,
            "x": Codec.float(x),
            "y": Codec.float(y),
            "depth": Codec.float(depth)
        ]
    }

    static func fromFirebase(_ value: Any?) -> ShotReplaySample? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> ShotReplaySample? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = ShotReplaySample()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "tMs": result.tMs = try Codec.convertLong(item)
            case "x": result.x = try Codec.convertFloat(item)
            case "y": result.y = try Codec.convertFloat(item)
            case "depth": result.depth = try Codec.convertFloat(item)
            // Includes "tms": "No setter/field for tms ... (fields/setters are case sensitive!)".
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}

// MARK: - LiveShotEvent (rooms/{CODE}/shots/{pushId}; written as an object)

extension LiveShotEvent {
    static let FIREBASE_CLASS_NAME = "com.appsbybros.minik.swish.model.LiveShotEvent"
    private static let firebaseProperties = Codec.properties(LiveShotEvent().toFirebaseMap())

    func toFirebaseMap() -> [String: Any] {
        return [
            "id": id,
            "playerUid": playerUid,
            "playerName": playerName,
            "shotSpotX": Codec.float(shotSpotX),
            "shotSpotY": Codec.float(shotSpotY),
            "aimError": Codec.float(aimError),
            "powerError": Codec.float(powerError),
            "arcError": Codec.float(arcError),
            "rawPeakGyro": Codec.float(rawPeakGyro),
            "rawReleasePitchDeg": Codec.float(rawReleasePitchDeg),
            "pullBack": Codec.float(pullBack),
            "hotHand": hotHand,
            "releasedAt": releasedAt,
            "made": made,
            "samples": samples.map { $0.toFirebaseMap() }
        ]
    }

    static func fromFirebase(_ value: Any?) -> LiveShotEvent? {
        return try? fromFirebaseOrThrow(value)
    }

    static func fromFirebaseOrThrow(_ value: Any?) throws -> LiveShotEvent? {
        guard let value = value, !Codec.isNull(value) else { return nil }
        var result = LiveShotEvent()
        for (key, item) in try Codec.bean(value, FIREBASE_CLASS_NAME) where !Codec.isNull(item) {
            switch key {
            case "id": result.id = try Codec.convertString(item)
            case "playerUid": result.playerUid = try Codec.convertString(item)
            case "playerName": result.playerName = try Codec.convertString(item)
            case "shotSpotX": result.shotSpotX = try Codec.convertFloat(item)
            case "shotSpotY": result.shotSpotY = try Codec.convertFloat(item)
            case "aimError": result.aimError = try Codec.convertFloat(item)
            case "powerError": result.powerError = try Codec.convertFloat(item)
            case "arcError": result.arcError = try Codec.convertFloat(item)
            case "rawPeakGyro": result.rawPeakGyro = try Codec.convertFloat(item)
            case "rawReleasePitchDeg": result.rawReleasePitchDeg = try Codec.convertFloat(item)
            case "pullBack": result.pullBack = try Codec.convertFloat(item)
            case "hotHand": result.hotHand = try Codec.convertBoolean(item)
            case "releasedAt": result.releasedAt = try Codec.convertLong(item)
            case "made": result.made = try Codec.convertBoolean(item)
            case "samples":
                var samples: [ShotReplaySample] = []
                for element in try Codec.expectList(item) {
                    if let sample = try ShotReplaySample.fromFirebaseOrThrow(element) {
                        samples.append(sample)
                    }
                }
                result.samples = samples
            default: Codec.unknownProperty(key, FIREBASE_CLASS_NAME, firebaseProperties)
            }
        }
        return result
    }
}
