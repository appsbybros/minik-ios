import Foundation

enum MPNames {
    /// Android `Nicknames.characterBase` (4bd6758): registered nickname bases stay "Minik" / "Miniko" although the
    /// characters are now shown as Mega Minik and Mega Miniko (the rules' nickname list is unchanged).
    static func characterBase(_ characterId: String, hebrew: Bool) -> String {
        switch characterId {
        case "minik": return hebrew ? "מיניק" : "Minik"
        case "miniko": return hebrew ? "מיניקו" : "Miniko"
        default: return (MPRoster.find(characterId) ?? MPRoster.all[0]).name(hebrew: hebrew)
        }
    }
    static let icons = ["🐱", "🦊", "🐼", "🐸", "🐯", "🐧"]
    static func candidate(_ index: Int, hebrew: Bool, suffix: Int = 0, character: String = "") -> String {
        let i = abs(index % 100), extra = suffix > 0 ? String(suffix) : ""
        if let player = MPRoster.find(character) {
            let en = ["Best", "Happy", "Human", "Summer", "Winter", "Green", "Blue", "Sunny", "Super", "Brave"]
            let he = ["בכתר", "בכיף", "בקצב", "בקיץ", "בחורף", "בירוק", "בכחול", "בשמש", "בזהב", "בנצנוץ"]
            let word = character == "moshiko" && i % 10 == 3 ? "Beach" : character == "moshiko" && i % 10 == 4 ? "Snowy" : en[i % 10]
            return (hebrew ? characterBase(player.id, hebrew: true) + " " + he[i % 10] : word + characterBase(player.id, hebrew: false).replacingOccurrences(of: " ", with: "")) + extra
        }
        let adjectives = ["Green", "Blue", "Pink", "Sunny", "Happy", "Brave", "Sweet", "Lucky", "Playful", "Gentle"]
        let animals = ["Frog", "Panda", "Bunny", "Fox", "Koala", "Otter", "Tiger", "Bear", "Duck", "Owl"]
        let nouns = ["צפרדע", "פנדה", "ארנב", "שועל", "קואלה", "לוטרה", "נמר", "דובון", "ברווז", "ינשוף"]
        let masculine = ["ירוק", "כחול", "ורוד", "זוהר", "שמח", "אמיץ", "מתוק", "זריז", "חייכן", "חמוד"]
        let feminine = ["ירוקה", "כחולה", "ורודה", "זוהרת", "שמחה", "אמיצה", "מתוקה", "זריזה", "חייכנית", "חמודה"]
        return (hebrew ? nouns[i % 10] + " " + ([0, 1, 4, 5].contains(i % 10) ? feminine : masculine)[i / 10] : adjectives[i / 10] + animals[i % 10]) + extra
    }
}
final class MPPreferences {
    let defaults: UserDefaults
    private let prefix = "modern.pong.v2."
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load<T: Decodable>(_ key: String, _ type: T.Type) -> T? { defaults.data(forKey: prefix + key).flatMap { try? JSONDecoder().decode(type, from: $0) } }
    func save<T: Encodable>(_ key: String, _ value: T) { defaults.set(try? JSONEncoder().encode(value), forKey: prefix + key) }
    var identity: MPIdentity? { get { load("identity", MPIdentity.self) } set { save("identity", newValue) } }
    /// Beginner / Standard / Pro. Beginner is the default without a saved choice (Android `controlDifficulty`, default 4);
    /// an earlier saved Standard/Pro choice keeps its meaning.
    var control: MPLevel {
        get {
            if let value = defaults.object(forKey: prefix + "control") as? Int { return MPLevel.control(value) }
            if defaults.object(forKey: prefix + "pro") != nil { return defaults.bool(forKey: prefix + "pro") ? .superHard : .easy }
            return .beginner
        }
        set { defaults.set(MPLevel.control(newValue.rawValue).rawValue, forKey: prefix + "control") }
    }
    var target: Int { get { let value = defaults.integer(forKey: prefix + "target"); return value == 0 ? 7 : value } set { defaults.set(newValue, forKey: prefix + "target") } }
    var skipGuide: Bool { get { defaults.bool(forKey: prefix + "skipGuide") } set { defaults.set(newValue, forKey: prefix + "skipGuide") } }
    var rooms: [MPSession] { get { load("rooms", [MPSession].self) ?? [] } set { save("rooms", newValue) } }
    /// Android PlayActivity `arena_FRIENDLY` / `arena_TOURNAMENT` (a4174b6): the last arena chosen for each kind of room,
    /// Beach for friendly games and Park for tournaments until one is chosen. A replay keeps the friendly arena.
    func arena(_ kind: MPSessionKind) -> MPArena {
        let saved = MPArena.read(defaults.string(forKey: prefix + "arena_" + kind.rawValue))
        return MPArena.choices.contains(saved) ? saved : (kind == .tournament ? .park : .beach)
    }
    func setArena(_ arena: MPArena, for kind: MPSessionKind) { defaults.set(arena.wire, forKey: prefix + "arena_" + kind.rawValue) }
    /// Android PlayActivity `knockoutFormat`: the last chosen tournament format.
    var knockoutFormat: Bool { get { defaults.bool(forKey: prefix + "knockoutFormat") } set { defaults.set(newValue, forKey: prefix + "knockoutFormat") } }
    func sequence(_ id: String) -> Int64 {
        let key = prefix + "sequence." + id, next = Int64(defaults.integer(forKey: key)) + 1
        defaults.set(next, forKey: key); return next
    }
    // Android RoomBook (2026-10): routine "news" notices (inactivity warnings, other players' results,
    // deletions) are retired and not resurfaced; failures use the screen's own error handling.
    // A completed room is never kept in "Your games / tournaments" history.
    private func flags(_ name: String) -> [String] { load(name, [String].self) ?? [] }
    private func flag(_ name: String, _ id: String) {
        var all = flags(name); guard !all.contains(id) else { return }
        all.append(id); save(name, Array(all.suffix(512)))
    }
    /// Android `RoomBook.completionKnown`.
    func completionKnown(_ s: MPSession) -> Bool { flags("completed").contains(s.id) }
    /// Android `RoomBook.remember`: an open room is listed; a completed one is marked and removed from the list.
    func remember(_ s: MPSession) {
        if s.complete { flag("completed", s.id); removed(s); return }
        guard !completionKnown(s) else { return }
        rooms = rooms.filter { $0.id != s.id } + [s]
    }
    /// Android `RoomBook.dismissResult`: "Done" (or Back) on a completed room.
    func dismissResult(_ s: MPSession) { flag("completed", s.id); removed(s) }
    /// Android `RoomBook.firstCelebration`: a completed room celebrates a win once.
    func firstCelebration(_ s: MPSession) -> Bool {
        if flags("celebrated").contains(s.id) { return false }
        flag("celebrated", s.id); return true
    }
    /// Android `RoomBook.forget` / `closed` / `deleted`: no notice is queued.
    func removed(_ s: MPSession) { rooms = rooms.filter { $0.id != s.id } }
}
