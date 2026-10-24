import SwiftUI
import UIKit

/// Android colour ints (0xAARRGGBB) as UIKit / SwiftUI colours.
enum MPColor {
    static func ui(_ argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255, blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24) / 255)
    }
    static func color(_ argb: UInt32) -> Color { Color(ui(argb)) }
    /// Android `PongRankPresentation.mix`: opaque channel blend with Kotlin's Float math and `toInt()` truncation.
    static func mix(_ a: UInt32, _ b: UInt32, _ f: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Float((a >> shift) & 0xff), y = Float((b >> shift) & 0xff)
            return UInt32(Int(x * (1 - f) + y * f)) & 0xff
        }
        return 0xff00_0000 | channel(16) << 16 | channel(8) << 8 | channel(0)
    }
}

/// Android `PongArena` (a4174b6): the scenery chosen for friendly, tournament and team matches. The empty wire value
/// belongs to older rooms and keeps their original court. Wire key `arena` (rooms, team meta, saved tables).
enum MPArena: String, CaseIterable, Codable {
    case legacy = "", beach = "beach", indoors = "indoors", park = "park", castle = "castle"
    var wire: String { rawValue }
    var english: String {
        switch self { case .legacy: return "Original"; case .beach: return "Beach"; case .indoors: return "Indoors"; case .park: return "Park"; case .castle: return "Ping Pong Castle" }
    }
    var hebrew: String {
        switch self { case .legacy: return "מקורית"; case .beach: return "חוף הים"; case .indoors: return "בבית"; case .park: return "פארק"; case .castle: return "טירת הפינג פונג" }
    }
    /// Android `PongArena.largeTable`: Indoors and Park use the large (daily-table) singles court.
    var largeTable: Bool { self == .indoors || self == .park }
    func title(he: Bool) -> String { he ? hebrew : english }
    static let choices: [MPArena] = [.beach, .indoors, .park, .castle]
    static func read(_ value: String?) -> MPArena { allCases.first { $0.wire == value } ?? .legacy }
    /// Android `ArenaBackdrop`: the scenery file in `Resources/ModernPongArt/arenas` (standalone app only), or nil for
    /// the original `modern_surround` (Legacy and Indoors).
    func backdropFile(wide: Bool) -> String? {
        switch self {
        case .beach: return wide ? "arenas/arena_beach_landscape.webp" : "arenas/arena_beach_portrait.webp"
        case .park: return wide ? "arenas/arena_park_landscape.webp" : "arenas/arena_park_portrait.webp"
        case .castle: return wide ? "arenas/arena_castle_landscape.jpg" : "arenas/arena_castle_portrait.jpg"
        case .legacy, .indoors: return nil
        }
    }
    /// The decoded scenery, nil where the art is not bundled (Math Plus, Minik Plus) or for the original court.
    func backdrop(wide: Bool) -> UIImage? { backdropFile(wide: wide).flatMap(MPArtFiles.image) }
}

/// Android `PongTeamColors`: stable team identity; turn instructions are in the HUD, not name outlines.
enum MPTeamColors {
    private static func mix(_ seed: Int64) -> UInt64 {
        var z = UInt64(bitPattern: seed)
        z = (z ^ (z >> 30)) &* UInt64(bitPattern: -4658895280553007687)
        z = (z ^ (z >> 27)) &* UInt64(bitPattern: -7723592293110705685)
        return z ^ (z >> 31)
    }
    private static let palettes: [[UInt32]] = [[0xff80d7ff, 0xffffafcf], [0xff80d7ff, 0xffffb46a], [0xffffdf75, 0xffffafcf], [0xffffb46a, 0xff80d7ff]]
    /// Team 0 / 1 fill colour (ARGB). `seed` 0 = the default pair (sky blue / pink).
    static func fill(_ team: Int, seed: Int64 = 0) -> UInt32 {
        let mixed = mix(seed)
        // Kotlin Math.floorMod(mixed, 4) of the signed value equals its two lowest bits.
        return palettes[Int(mixed & 3)][min(max(team, 0), 1) ^ Int((mixed >> 2) & 1)]
    }
    static func uiFill(_ team: Int, seed: Int64 = 0) -> UIColor { MPColor.ui(fill(team, seed: seed)) }
    /// Android `PongTeamColors.named`: "first · second" (or stacked) with each name in its team colour.
    static func named(_ first: String, _ second: String, stacked: Bool = false, firstColor: UInt32 = fill(0), secondColor: UInt32 = fill(1)) -> NSAttributedString {
        let text = NSMutableAttributedString(string: first + (stacked ? "\n" : " · ") + second)
        text.addAttribute(.foregroundColor, value: MPColor.ui(firstColor), range: NSRange(location: 0, length: (first as NSString).length))
        let start = (first as NSString).length + (stacked ? 1 : 3)
        text.addAttribute(.foregroundColor, value: MPColor.ui(secondColor), range: NSRange(location: start, length: text.length - start))
        return text
    }
    /// Android `PongTeamColors.score`: "a : b" in the two team colours.
    static func score(_ first: Int, _ second: Int, firstTeam: Int = 0, seed: Int64 = 0) -> NSAttributedString {
        let a = String(first), b = String(second)
        let text = NSMutableAttributedString(string: a + " : " + b)
        text.addAttribute(.foregroundColor, value: MPColor.ui(fill(firstTeam, seed: seed)), range: NSRange(location: 0, length: a.count))
        text.addAttribute(.foregroundColor, value: MPColor.ui(fill(1 - firstTeam, seed: seed)), range: NSRange(location: a.count + 3, length: b.count))
        return text
    }
}

/// A raised Android `FamilySkyDrawable` face: the base colour plus its three-stop face gradient (top, middle, bottom).
struct MPCourtFace: Equatable {
    var base: UInt32; var top: UInt32; var middle: UInt32; var bottom: UInt32
    var stops: [UInt32] { [top, middle, bottom] }
    var colors: [Color] { stops.map(MPColor.color) }
    var uiColors: [UIColor] { stops.map(MPColor.ui) }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom) }
}

/// Android `PongCourtStyle` colours (explicit faces keep their hue instead of passing through the shared pastel map).
/// The landscape layout helper is not ported here.
enum MPCourtStyle {
    static let start: UInt32 = 0xff8bd4ae
    static let saved: UInt32 = 0xffcfaff4
    static let startFace = MPCourtFace(base: start, top: 0xffcef2de, middle: 0xff93d6b1, bottom: 0xff82c99f)
    static let menuFace = MPCourtFace(base: 0xffb8d9ff, top: 0xffe0f3ff, middle: 0xffbde2ff, bottom: 0xffa8d6f4)
    static func teamFace(_ side: Int) -> MPCourtFace {
        side == 0 ? MPCourtFace(base: MPTeamColors.fill(0), top: 0xffc6eeff, middle: MPTeamColors.fill(0), bottom: 0xff64bee7)
            : MPCourtFace(base: MPTeamColors.fill(1), top: 0xffffdfec, middle: MPTeamColors.fill(1), bottom: 0xffed94bc)
    }
    static let savedFace = MPCourtFace(base: saved, top: 0xffe9dafc, middle: 0xffd1b2f1, bottom: 0xffc5a2e8)
    static let savedItemFace = MPCourtFace(base: 0xffffffff, top: 0xffffffff, middle: 0xfffdfdff, bottom: 0xfff5f4fa)
    /// Android default corner radii (dp = points): start 15, menu 20, team 22, saved 18, saved item 15.
    static let startRadius: CGFloat = 15, menuRadius: CGFloat = 20, teamRadius: CGFloat = 22, savedRadius: CGFloat = 18, savedItemRadius: CGFloat = 15
}

/// Android `PongHelpTips` (aca67f4 and later): the "Did you know?" serve tip is shown at most three times
/// (UserDefaults key mirrors Android's `pong_help_tips` / `serve_double_bounce`).
enum MPHelpTips {
    static let countKey = "modern.pong.v2.pong_help_tips.serve_double_bounce"
    /// Android `R.string.serve_double_bounce_tip`.
    static func serveDoubleBounceTip(he: Bool) -> String {
        he ? "בניגוד לדעה רווחת, הגשה שקופצת פעמיים בצד של היריב מזכה את המגיש בנקודה, בתנאי שקפצה קודם פעם אחת בצד שלו. שתי קפיצות בצד של המגיש הן שגיאה בהגשה."
            : "Contrary to a common belief, a serve that bounces twice on your opponent's side wins you the point—as long as it first bounced once on your own side. Two bounces on your own side are a serve fault."
    }
    /// Android `R.string.serve_double_bounce_point`.
    static func serveDoubleBouncePoint(he: Bool) -> String {
        he ? "בניגוד לדעה הרווחת: שתי קפיצות בצד היריב מזכות אתכם בנקודה — גם בהגשה!"
            : "Despite the common myth: two bounces on their side win you the point—even on a serve!"
    }
    /// Android `PongHelpTips.next`: "" when not eligible or already shown three times; otherwise counts this showing and
    /// returns the tip with its two leading line breaks.
    static func next(he: Bool, eligible: Bool = true, defaults: UserDefaults = .standard) -> String {
        if !eligible { return "" }
        let count = defaults.integer(forKey: countKey)
        if count >= 3 { return "" }
        defaults.set(count + 1, forKey: countKey)
        return "\n\n" + (he ? "הידעתם? " : "Did you know? ") + serveDoubleBounceTip(he: he)
    }
    /// Android `PongHelpTips.diagonal`: the team serve fault text.
    static func diagonal(he: Bool, ownPoint: Bool) -> String {
        (he ? "שגיאת הגשה: צריך להגיש באלכסון. " : "Serve fault: serve diagonally. ") +
            (he ? (ownPoint ? "נקודה לקבוצה שלכם" : "נקודה לקבוצה היריבה") : (ownPoint ? "Your team's point" : "Other team's point"))
    }
}

/// Android `PongSessionTips`: three point explanations per process (app run), never three per frame or per new match.
/// `owner` is the game asking (Android passes the game object or "team/<seed>").
enum MPSessionTips {
    private static var used = 0
    private static var seen: [AnyHashable: (point: Int, allowed: Bool)] = [:]
    private static let lock = NSLock()
    static func allow(_ owner: AnyHashable, point: Int, eligible: Bool) -> Bool {
        if !eligible { return false }
        lock.lock(); defer { lock.unlock() }
        if let previous = seen[owner], previous.point == point { return previous.allowed }
        if used >= 3 { return false }
        used += 1; seen[owner] = (point, true); return true
    }
    static func reset() { lock.lock(); used = 0; seen = [:]; lock.unlock() }
}
