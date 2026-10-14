import Foundation

enum MPNames {
    static let icons = ["🐱", "🦊", "🐼", "🐸", "🐯", "🐧"]
    static func candidate(_ index: Int, hebrew: Bool, suffix: Int = 0, character: String = "") -> String {
        let i = abs(index % 100), extra = suffix > 0 ? String(suffix) : ""
        if let player = MPRoster.find(character) {
            let en = ["Best", "Happy", "Human", "Summer", "Winter", "Green", "Blue", "Sunny", "Super", "Brave"]
            let he = ["בכתר", "בכיף", "בקצב", "בקיץ", "בחורף", "בירוק", "בכחול", "בשמש", "בזהב", "בנצנוץ"]
            let word = character == "moshiko" && i % 10 == 3 ? "Beach" : character == "moshiko" && i % 10 == 4 ? "Snowy" : en[i % 10]
            return (hebrew ? player.hebrew + " " + he[i % 10] : word + player.english.replacingOccurrences(of: " ", with: "")) + extra
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
    /// Android PlayActivity `knockoutFormat`: the last chosen tournament format (Multi Ping Pong defaults to a knockout).
    var knockoutFormat: Bool {
        get { defaults.object(forKey: prefix + "knockoutFormat") == nil ? true : defaults.bool(forKey: prefix + "knockoutFormat") }
        set { defaults.set(newValue, forKey: prefix + "knockoutFormat") }
    }
    // Android PlayActivity (828c6fc) form choices: players per table per room kind (2, 3 or 4; default 4), the game type per
    // room kind, players going through from each knockout table (1 or 2; default 2) and the knockout size (default 8).
    func tableSize(_ kind: MPSessionKind) -> Int {
        let value = defaults.integer(forKey: prefix + "tableSize." + kind.rawValue)
        return (2...4).contains(value) ? value : 4
    }
    func setTableSize(_ kind: MPSessionKind, _ value: Int) { defaults.set(min(4, max(2, value)), forKey: prefix + "tableSize." + kind.rawValue) }
    func gameMode(_ kind: MPSessionKind) -> MPGameMode {
        MPGameMode(rawValue: defaults.string(forKey: prefix + "gameMode." + kind.rawValue) ?? "") ?? .winnerTakesAll
    }
    func setGameMode(_ kind: MPSessionKind, _ value: MPGameMode) { defaults.set(value.rawValue, forKey: prefix + "gameMode." + kind.rawValue) }
    var advance: Int {
        get { let value = defaults.integer(forKey: prefix + "advance"); return value == 1 ? 1 : 2 }
        set { defaults.set(min(2, max(1, newValue)), forKey: prefix + "advance") }
    }
    var knockoutPlayers: Int {
        get { let value = defaults.integer(forKey: prefix + "knockoutPlayers"); return (2...MPKnockout.maxPlayers).contains(value) ? value : 8 }
        set { defaults.set(min(MPKnockout.maxPlayers, max(2, newValue)), forKey: prefix + "knockoutPlayers") }
    }
    // Android CrossActivity `cross_local`: players at the local table (3/4, default 4), points to win (3/5/7, default 5), the
    // three house players, full screen (default on) and whether the cross guide was seen.
    var crossPlayers: Int {
        get { let value = defaults.integer(forKey: prefix + "cross.players"); return value == 3 ? 3 : 4 }
        set { defaults.set(newValue == 3 ? 3 : 4, forKey: prefix + "cross.players") }
    }
    var crossTarget: Int {
        get { let value = defaults.integer(forKey: prefix + "cross.target"); return [3, 5, 7].contains(value) ? value : 5 }
        set { defaults.set([3, 5, 7].contains(newValue) ? newValue : 5, forKey: prefix + "cross.target") }
    }
    var crossOpponents: [String] {
        get {
            let saved = (defaults.string(forKey: prefix + "cross.opponents") ?? "kyra,mia,minik").split(separator: ",").map(String.init)
            var result: [String] = []
            for id in saved where MPRoster.find(id) != nil && !result.contains(id) { result.append(id) }
            for player in MPRoster.all where !result.contains(player.id) { result.append(player.id) }
            return result
        }
        set { defaults.set(newValue.joined(separator: ","), forKey: prefix + "cross.opponents") }
    }
    /// Android `cross_local/full_screen`, now read only by a room fixture's court (PrivateMatchActivity 5c1aa4d), default off.
    var crossFullScreen: Bool {
        get { defaults.object(forKey: prefix + "cross.fullScreen") == nil ? false : defaults.bool(forKey: prefix + "cross.fullScreen") }
        set { defaults.set(newValue, forKey: prefix + "cross.fullScreen") }
    }
    /// Android `cross/action_camera` (5c1aa4d): the landscape action camera of the local, journey and team courts, default on.
    var crossActionCamera: Bool {
        get { defaults.object(forKey: prefix + "cross.actionCamera") == nil ? true : defaults.bool(forKey: prefix + "cross.actionCamera") }
        set { defaults.set(newValue, forKey: prefix + "cross.actionCamera") }
    }
    // Android ReceptionSettings (`reception_assistance`, 5c1aa4d): zoom for my return, gentle slow motion for my return, zoom for
    // another human's return. All off by default.
    var receptionZoom: Bool { get { defaults.bool(forKey: prefix + "reception.zoom") } set { defaults.set(newValue, forKey: prefix + "reception.zoom") } }
    var receptionSlow: Bool { get { defaults.bool(forKey: prefix + "reception.slow") } set { defaults.set(newValue, forKey: prefix + "reception.slow") } }
    var receptionFollow: Bool { get { defaults.bool(forKey: prefix + "reception.follow") } set { defaults.set(newValue, forKey: prefix + "reception.follow") } }
    /// Android `pong_music/enabled`: the quiet menu music, default on.
    var menuMusic: Bool {
        get { defaults.object(forKey: prefix + "menuMusic") == nil ? true : defaults.bool(forKey: prefix + "menuMusic") }
        set { defaults.set(newValue, forKey: prefix + "menuMusic") }
    }
    /// Android `cross_skill_journey/sound`: game sounds of team games and daily practice, default on.
    var journeySound: Bool {
        get { defaults.object(forKey: prefix + "journey.sound") == nil ? true : defaults.bool(forKey: prefix + "journey.sound") }
        set { defaults.set(newValue, forKey: prefix + "journey.sound") }
    }
    // Android `cross_skill_journey`: the next stage (0-based, cycles of 30), practice stars, the day of the last daily bonus, the
    // completed stage receipts ("cycle/stage") and a saved unfinished practice or team match.
    var journeyStep: Int { get { max(0, defaults.integer(forKey: prefix + "journey.step")) } set { defaults.set(max(0, newValue), forKey: prefix + "journey.step") } }
    var journeyStars: Int { get { defaults.integer(forKey: prefix + "journey.stars") } set { defaults.set(newValue, forKey: prefix + "journey.stars") } }
    var journeyDay: String { get { defaults.string(forKey: prefix + "journey.day") ?? "" } set { defaults.set(newValue, forKey: prefix + "journey.day") } }
    var journeyReceipts: [String] { get { defaults.stringArray(forKey: prefix + "journey.receipts") ?? [] } set { defaults.set(newValue, forKey: prefix + "journey.receipts") } }
    var savedPractice: String? { get { defaults.string(forKey: prefix + "journey.savedPractice") } set { defaults.set(newValue, forKey: prefix + "journey.savedPractice") } }
    var savedTeamMatch: String? { get { defaults.string(forKey: prefix + "journey.savedMatch") } set { defaults.set(newValue, forKey: prefix + "journey.savedMatch") } }
    /// Android FamilyMenu (`family_menu_sections`): a home section's remembered open state, by its title.
    func menuSection(_ title: String, default open: Bool) -> Bool {
        defaults.object(forKey: prefix + "menuSection." + title) == nil ? open : defaults.bool(forKey: prefix + "menuSection." + title)
    }
    func setMenuSection(_ title: String, _ open: Bool) { defaults.set(open, forKey: prefix + "menuSection." + title) }
    /// Android `cross_team_rooms`: the online team room to reopen, and the strictly increasing input sequence.
    var teamRoom: String? { get { defaults.string(forKey: prefix + "teamRoom") } set { defaults.set(newValue, forKey: prefix + "teamRoom") } }
    var teamSequence: Int64 {
        get { (defaults.object(forKey: prefix + "teamSequence") as? NSNumber)?.int64Value ?? 0 }
        set { defaults.set(NSNumber(value: newValue), forKey: prefix + "teamSequence") }
    }
    var crossGuideSeen: Bool { get { defaults.bool(forKey: prefix + "cross.guideSeen") } set { defaults.set(newValue, forKey: prefix + "cross.guideSeen") } }
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
    /// Android `RoomBook.forget` / `deleted`: no notice is queued.
    func removed(_ s: MPSession) { rooms = rooms.filter { $0.id != s.id } }
    /// Android `RoomBook.closed` (5c1aa4d): a cancelled, finished or left room is also marked complete, so a late refresh of it
    /// is ignored instead of listing it again.
    func closed(_ s: MPSession) { flag("completed", s.id); removed(s) }
}
