import Foundation
import CoreGraphics
import UIKit

/// Android `ReceptionAssist` (2026-10): one simulation clock for the whole match. Gentle slow motion only for a
/// receiver who chose it; camera preferences never enter physics. Online the authority owns the clock and its
/// state travels in the checkpoint (`reception`), so every phone plays at the same pace.
struct MPReceptionAssist: Equatable {
    /// Production owners enable this after loading preferences; pure physics callers stay unmodified.
    var enabled = false
    var slow: [Int: Bool] = [:]
    private(set) var scale = 1.0
    private(set) var receiver = -1
    private(set) var strength = 0.0

    /// Returns the simulation seconds for `realSeconds` of wall time. A non-authority follows the authority's scale.
    mutating func advance(_ realSeconds: Double, seat: Int?, eta: Double?, authority: Bool = true) -> Double {
        let dt = realSeconds.isNaN ? 0 : realSeconds.mpClamp(0, 1.0 / 30)
        if dt <= 0 { return 0 }
        if !authority { return dt * scale }
        receiver = seat ?? -1
        if enabled, seat != nil, let eta, eta.isFinite, eta >= -0.12, eta <= 1.1 {
            let t = (1 - max(eta, 0) / 1.1).mpClamp(0, 1)
            strength = t * t * (3 - 2 * t)
        } else { strength = 0 }
        var target = 1.0
        if enabled, let seat, slow[seat] == true { target = 1 - 0.55 * strength }
        scale += (target - scale) * (1 - exp(-dt * 5))
        if abs(scale - 1) < 0.00001 { scale = 1 }
        return dt * scale
    }

    /// Android `ReceptionAssist.wire()`; `slow` is keyed by the seat number as text.
    var wire: MPWire {
        var options: MPWire = [:]
        for (seat, value) in slow { options[String(seat)] = value }
        return ["enabled": enabled, "scale": scale, "receiver": receiver, "strength": strength, "slow": options]
    }

    /// Android `ReceptionAssist.restore`: an empty map (an older snapshot) plays at normal speed; an invalid state is rejected.
    init(wire w: MPWire) throws {
        let s = (w["scale"] as? NSNumber)?.doubleValue ?? 1
        let f = (w["strength"] as? NSNumber)?.doubleValue ?? 0
        let r = (w["receiver"] as? NSNumber)?.intValue ?? -1
        guard s.isFinite, s >= 0.45, s <= 1, f.isFinite, f >= 0, f <= 1, r >= -1, r <= 3 else { throw MPError.permission }
        var options: [Int: Bool] = [:]
        for (key, value) in MPCodec.map(w["slow"]) {
            guard let seat = Int(key), (0...3).contains(seat), let flag = MPReceptionAssist.flag(value) else { throw MPError.permission }
            options[seat] = flag
        }
        enabled = MPReceptionAssist.flag(w["enabled"]) == true; scale = s; strength = f; receiver = r; slow = options
    }
    init() {}

    /// Android `ReceptionAssist.reflected`: the other phone's view of the same shared clock (seats 0 and 1 swap).
    static func reflected(_ w: MPWire) -> MPWire {
        if w.isEmpty { return w }
        var next = w
        let receiver = (w["receiver"] as? NSNumber)?.intValue ?? -1
        next["receiver"] = (0...1).contains(receiver) ? 1 - receiver : -1
        var options: MPWire = [:]
        for (key, value) in MPCodec.map(w["slow"]) { if let seat = Int(key) { options[String(1 - seat)] = value } }
        next["slow"] = options
        return next
    }

    /// Android `ReceptionAssist.eta`: seconds until the ball passes `at`, or nil when it passes wide (> 0.35).
    static func eta(_ ball: MPPoint, _ velocity: MPPoint, _ at: MPPoint) -> Double? {
        let speed2 = velocity.x * velocity.x + velocity.y * velocity.y
        if speed2 < 0.000001 { return nil }
        let x = at.x - ball.x, y = at.y - ball.y
        let t = (x * velocity.x + y * velocity.y) / speed2
        return hypot(x - velocity.x * t, y - velocity.y * t) < 0.35 ? t : nil
    }

    /// A JSON/RTDB boolean (or a Swift `Bool` in a locally built wire). Numbers are not accepted as booleans.
    static func flag(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let swift = value as? Bool, type(of: value) == Bool.self { return swift }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

/// The 1v1 checkpoint keeps `reception` inside `engine`. Decoding is lenient: a missing, partial or RTDB-array
/// `slow` map is read as Android's `Wire.wire()` would read it, and an invalid state plays at normal speed.
extension MPReceptionAssist: Codable {
    private enum CodingKeys: String, CodingKey { case enabled, scale, receiver, strength, slow }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var w: MPWire = [:]
        if let value = try? c.decodeIfPresent(Bool.self, forKey: .enabled) { w["enabled"] = value }
        if let value = try? c.decodeIfPresent(Double.self, forKey: .scale) { w["scale"] = value }
        if let value = try? c.decodeIfPresent(Int.self, forKey: .receiver) { w["receiver"] = value }
        if let value = try? c.decodeIfPresent(Double.self, forKey: .strength) { w["strength"] = value }
        if let keyed = try? c.decodeIfPresent([String: Bool].self, forKey: .slow) {
            var options: MPWire = [:]; for (key, value) in keyed { options[key] = value }; w["slow"] = options
        } else if let list = try? c.decodeIfPresent([Bool?].self, forKey: .slow) {
            var options: MPWire = [:]; for (index, value) in list.enumerated() { if let value { options[String(index)] = value } }; w["slow"] = options
        }
        self = (try? MPReceptionAssist(wire: w)) ?? MPReceptionAssist()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled); try c.encode(scale, forKey: .scale)
        try c.encode(receiver, forKey: .receiver); try c.encode(strength, forKey: .strength)
        var options: [String: Bool] = [:]; for (seat, value) in slow { options[String(seat)] = value }
        try c.encode(options, forKey: .slow)
    }
    /// The shared clock seen from the other phone.
    var reflected: MPReceptionAssist {
        (try? MPReceptionAssist(wire: MPReceptionAssist.reflected(wire))) ?? self
    }
}

/// Android `ReceptionSettings` (`reception_assistance` preferences): three choices, all off until the player turns
/// them on. Zoom and follow change only this screen; slow motion is shared with the other players.
enum MPReceptionSettings {
    static let keys = ["zoom", "slow", "follow"]
    private static func key(_ name: String) -> String { "modern.pong.reception." + name }
    static func value(_ name: String) -> Bool { UserDefaults.standard.bool(forKey: key(name)) }
    static func set(_ name: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: key(name)) }
    static var slow: Bool { value("slow") }
    static func title(_ name: String, hebrew: Bool) -> String {
        switch name {
        case "zoom": return hebrew ? "מיקוד המצלמה לקראת החבטה שלי" : "Zoom in for my return"
        case "slow": return hebrew ? "האטה הדרגתית לקראת החבטה שלי" : "Gentle slow motion for my return"
        default: return hebrew ? "מיקוד המצלמה כששחקן אחר מקבל את הכדור" : "Zoom in for another player's return (not bots)"
        }
    }
    static func explanation(_ name: String, hebrew: Bool) -> String {
        switch name {
        case "zoom": return hebrew ? "המצלמה מתקרבת כשהכדור מגיע אליכם, ואז חוזרת למבט על השולחן." : "Bring the camera closer as the ball approaches you, then return to the full table."
        case "slow": return hebrew ? "מאטים לזמן קצר את המשחק לקראת החבטה שלכם. ברשת, כולם משחקים באותה מהירות." : "Slow the whole game briefly for your return. Online, everyone shares the same pace."
        default: return hebrew ? "במשחק מקוון, מתקרבים כששחקן אחר מקבל את הכדור. בתור של שחקן בית המבט נשאר רגיל." : "During online play, zoom in when another player receives the ball. Bot turns keep the normal view."
        }
    }
    static func title(hebrew: Bool) -> String { hebrew ? "עזרה בקבלת הכדור ▾" : "Ball assistance ▾" }
    /// Android ReceptionSettings (29f5dc7): the expandable section's raised toggle reads "+" when closed, "−" when open.
    static func toggle(open: Bool, hebrew: Bool) -> String {
        open ? (hebrew ? "−  עזרה בקבלת הכדור" : "−  Ball assistance") : (hebrew ? "+  עזרה בקבלת הכדור" : "+  Ball assistance")
    }
    static func note(hebrew: Bool) -> String {
        hebrew ? "במשחק ברשת כולם משחקים באותה מהירות. כל שחקן בוחר אם להאט לקראת החבטה שלו. אפשרויות המצלמה משפיעות רק על המסך שלכם; אין התקרבות לקראת חבטות של בוטים."
            : "Online players share the same game speed. Each player chooses slow motion for their own return. Camera choices affect only your screen; bots do not trigger zoom."
    }
}

/// Android `ReceptionCamera`: a reversible screen transform (top-left origin, y down) that eases toward the
/// receiver. It holds still during a touch, and iOS Reduce Motion keeps the full table (Android: animations off).
/// Android 131bd3a / ef28b1c (1.0.15-1.0.16): the zoom and its offset are eased together as one transform
/// (`p * zoom + t`); one reception keeps its first focus and its peak strength until 0.28 s after it ends, so the
/// camera holds still instead of pumping; framing that caps the zoom also caps the pan; and the offset never uncovers
/// the edge of the view.
struct MPReceptionCamera {
    private(set) var amount = 0.0
    private(set) var x: CGFloat = 0, y: CGFloat = 0, tx: CGFloat = 0, ty: CGFloat = 0
    private var framingLimit = CGFloat.infinity
    private var renderedZoom: CGFloat = 1
    private var visibleTop = CGFloat.nan, visibleBottom = CGFloat.nan
    private var actorTop: CGFloat = 0, actorBottom: CGFloat = 0
    private var frame = CGSize.zero
    private var receiving = false, releaseDelay = 0.0, peakStrength = 0.0
    private var receptionFocus = CGPoint.zero
    var zoom: CGFloat { renderedZoom }
    mutating func update(_ dt: Double, assist: MPReceptionAssist, local: Int, focus: CGPoint, size: CGSize, holding: Bool, reduceMotion: Bool) {
        if frame != size {
            if frame.width > 0 { framingLimit = .infinity; visibleTop = .nan; visibleBottom = .nan }
            frame = size
        }
        if holding { return }
        let own = assist.receiver == local
        let allowed = MPReceptionSettings.value(own ? "zoom" : "follow") && assist.receiver >= 0 && !reduceMotion
        let incoming = allowed && assist.strength > 0
        if incoming {
            if !receiving { peakStrength = 0; receptionFocus = focus }
            peakStrength = max(peakStrength, assist.strength)
            releaseDelay = 0.28
        } else { releaseDelay = max(releaseDelay - dt, 0) }
        receiving = incoming || releaseDelay > 0
        let target = receiving ? peakStrength : 0
        let fixedFocus = receiving ? receptionFocus : focus
        let k = 1 - exp(-dt.mpClamp(0, 0.075) * 4)
        amount += (target - amount) * k
        if amount < 0.0001 { amount = 0; x = fixedFocus.x; y = fixedFocus.y }
        else if receiving { x += (fixedFocus.x - x) * CGFloat(k); y += (fixedFocus.y - y) * CGFloat(k) }
        x = min(size.width * 0.88, max(size.width * 0.12, x)); y = min(size.height * 0.88, max(size.height * 0.12, y))
        let targetZoom = min(CGFloat(1 + 0.42 * amount), framingLimit)
        // If framing prevents zoom, it must also prevent reception panning.
        let framedAmount = min(max((targetZoom - 1) / 0.42, 0), 1)
        let targetX = (size.width * 0.5 - x) * framedAmount
        var targetY = (size.height * 0.62 - y) * framedAmount
        if visibleTop.isFinite, targetZoom > 1.0001 {
            let lower = visibleTop - (y + (actorTop - y) * targetZoom), upper = visibleBottom - (y + (actorBottom - y) * targetZoom)
            if lower <= upper { targetY = min(max(targetY, lower), upper) }
        }
        // Resolve framing before easing the final transform, and ease the complete offset (not a moving pivot plus a
        // separate pan). Valid endpoints stay inside the view throughout the interpolation.
        let offsetX = min(max((1 - targetZoom) * x + targetX, size.width * (1 - targetZoom)), 0)
        let offsetY = min(max((1 - targetZoom) * y + targetY, size.height * (1 - targetZoom)), 0)
        renderedZoom += (targetZoom - renderedZoom) * CGFloat(k)
        tx += (offsetX - tx) * CGFloat(k); ty += (offsetY - ty) * CGFloat(k)
    }
    /// Android 579de33 / 131bd3a `keepPlayersVisible`: zoom the singles scene without losing either player's head or
    /// feet beyond `visibleTop...visibleBottom` (court points, y down). The actors' extent only grows during a
    /// reception, so a swing pose cannot pump the camera in and out.
    mutating func keepPlayersVisible(top: CGFloat, bottom: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat) {
        guard bottom > top, visibleBottom > visibleTop else { return }
        self.visibleTop = visibleTop; self.visibleBottom = visibleBottom
        if framingLimit.isInfinite { actorTop = top; actorBottom = bottom }
        else { actorTop = min(actorTop, top); actorBottom = max(actorBottom, bottom) }
        framingLimit = max((visibleBottom - visibleTop) / (actorBottom - actorTop), 1)
    }
    /// Android `begin`: translate, then scale about the view's origin.
    func apply(_ context: CGContext) {
        context.translateBy(x: tx, y: ty); context.scaleBy(x: zoom, y: zoom)
    }
    /// A world point's position on screen.
    func painted(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + tx, y: p.y * zoom + ty) }
    /// Android `ReceptionCamera.scenery`: the same transform for a view whose points are `offset` from the court's
    /// (`translate(offset); begin; translate(-offset)`); `offset` is the court origin in that view.
    func transform(offset: CGPoint) -> CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: offset.x * (1 - zoom) + tx, ty: offset.y * (1 - zoom) + ty)
    }
    /// The world point under a screen point (touch input).
    func base(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - tx) / zoom, y: (p.y - ty) / zoom) }
}
