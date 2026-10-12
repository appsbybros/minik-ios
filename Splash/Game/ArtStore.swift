import UIKit

/// Port of Android ArtStore.kt: atlases, directional atlases, four-frame locomotion atlases,
/// balloons, tinted splashes, opaque-body anchors, portraits and the timed pose selection. Art is
/// the Android WebP converted losslessly to PNG.
struct SpriteFrame {
    let rect: CGRect
    let handX: CGFloat
    let handY: CGFloat
    let image: UIImage?
}

/// Android `SpriteVisual(bitmap, frame, mirrored, key)`; `atlas` names the bitmap the frame is cut from.
struct SpriteVisual {
    let frame: SpriteFrame
    let mirrored: Bool
    let key: String
    let atlas: String
}

/// Android `ArtStore.frame(actor, time)`: the timed pose index (pure, testable). 100-107 are the
/// locomotion frames (100-103 walking, 104-107 running), driven by the travelled distance.
enum SplashPose {
    static func frame(_ a: SplashActor, _ time: Double) -> Int {
        if time < a.cleanUntil { return 11 }
        if time - a.hitAt < 0.23 { return 10 }
        if a.height > 0.1 { return 8 }
        if time < a.crouchUntil { return 9 }
        if time - a.throwAt < 0.10 { return 6 }
        if time - a.throwAt < 0.30 { return 7 }
        if time - a.pickupAt < 0.18 { return 3 }
        if a.held != nil && time - a.windupAt < 0.25 { return 5 }
        if a.velocity.length() > 0.18 { return 100 + (a.runBlend > 0.45 ? 4 : 0) + KotlinNumber.int(a.gait) % 4 }
        if a.held != nil { return 4 }
        return 0
    }

    /// Android `ArtStore.visual` pose mapping for side/back atlases (after the locomotion fallback).
    static func directionalPose(_ index: Int) -> Int {
        switch index {
        case 3, 9, 10: return 7
        case 4: return 3
        case 5: return 4
        case 6, 7: return 5
        case 8: return 6
        case 12, 13: return 1
        case 14, 15: return 2
        default: return 0
        }
    }

    /// Android: without a locomotion atlas, 100+ falls back to the front walking frames 12-15.
    static func safeIndex(_ index: Int) -> Int {
        return index >= 100 ? 12 + (index - 100) % 4 : index
    }

    /// The facing as seen through a camera turned by `yaw`.
    static func facing(_ facing: V, _ yaw: Double) -> Facing {
        return Facing.of(V(cos(yaw) * facing.x - sin(yaw) * facing.y, sin(yaw) * facing.x + cos(yaw) * facing.y))
    }

    /// Android `anchor` cache key for a visual key: "front", "motion-<row>", "back" or "side".
    static func anchorKey(_ visualKey: String) -> String {
        if visualKey.hasPrefix("front") { return "front" }
        if visualKey.hasPrefix("motion") {
            let parts: [Substring] = visualKey.split(separator: "-", omittingEmptySubsequences: false)
            return "motion-" + (parts.count > 1 ? String(parts[1]) : "0")
        }
        let frame = Int(visualKey.replacingOccurrences(of: "direction-", with: "")) ?? 0
        return frame >= 8 ? "back" : "side"
    }
}

@MainActor
final class ArtStore {
    static let shared = ArtStore()

    static let balloonNames = ["orange", "yellow", "green", "blue", "pink", "cyan"]

    private struct FrameMeta {
        let rect: CGRect
        let hand: CGPoint
    }

    private var frontMeta: [String: [FrameMeta]] = [:]
    private var directionMeta: [String: [FrameMeta]] = [:]
    private var frontFrames: [String: [SpriteFrame]] = [:]
    private var directionFrames: [String: [SpriteFrame]] = [:]
    private var motion: [String: CGImage] = [:]
    private var motionCells: [String: SpriteFrame] = [:]
    private var anchors: [String: SpriteAnchor] = [:]
    private var portraits: [String: UIImage] = [:]
    private var readyCells: [String: UIImage] = [:]
    private var images: [String: UIImage] = [:]
    private var wordBalloons: [Int: UIImage] = [:]
    private var paintedCache: [String: UIImage] = [:]
    private var paintedOrder: [String] = []

    private init() {
        frontMeta = ArtStore.loadMeta("atlas")
        directionMeta = ArtStore.loadMeta("directions")
    }

    private static func loadMeta(_ name: String) -> [String: [FrameMeta]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let characters = root["characters"] as? [String: Any] else { return [:] }
        var result: [String: [FrameMeta]] = [:]
        for (id, value) in characters {
            guard let entry = value as? [String: Any], let frames = entry["frames"] as? [Any] else { continue }
            var list: [FrameMeta] = []
            for item in frames {
                guard let frame = item as? [String: Any] else { continue }
                let r = NodeValue.list(frame["rect"]).map { NodeValue.number($0) ?? 0 }
                let h = NodeValue.list(frame["hand"]).map { NodeValue.number($0) ?? 0 }
                guard r.count == 4, h.count == 2 else { continue }
                list.append(FrameMeta(rect: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]), hand: CGPoint(x: h[0], y: h[1])))
            }
            result[id] = list
        }
        return result
    }

    /// Releases decoded art after a memory warning; everything reloads on demand (the
    /// locomotion atlases of the current roster stay, as Android keeps them until the next battle).
    func purge() {
        frontFrames.removeAll()
        directionFrames.removeAll()
        motionCells.removeAll()
        images.removeAll()
        wordBalloons.removeAll()
        paintedCache.removeAll()
        paintedOrder.removeAll()
    }

    /// Android `close()`: drops every decoded bitmap.
    func close() {
        purge()
        motion.removeAll()
        portraits.removeAll()
        readyCells.removeAll()
        anchors.removeAll()
    }

    func image(_ name: String) -> UIImage? {
        if let cached = images[name] { return cached }
        guard let loaded = UIImage(named: name) else { return nil }
        images[name] = loaded
        return loaded
    }

    /// Decodes an atlas once so per-frame crops share a ready bitmap.
    private func decoded(_ name: String) -> CGImage? {
        guard let source = UIImage(named: name)?.cgImage else { return nil }
        let width = source.width
        let height = source.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? source
    }

    private func cut(_ atlas: CGImage?, _ meta: [FrameMeta]) -> [SpriteFrame] {
        return meta.map { m -> SpriteFrame in
            var cell: UIImage? = nil
            if let atlas = atlas, let cropped = atlas.cropping(to: m.rect) {
                cell = UIImage(cgImage: cropped, scale: 1, orientation: .up)
            }
            return SpriteFrame(rect: m.rect, handX: m.hand.x, handY: m.hand.y, image: cell)
        }
    }

    func frames(_ character: String) -> [SpriteFrame] {
        if let cached = frontFrames[character] { return cached }
        let made = cut(decoded(character), frontMeta[character] ?? [])
        frontFrames[character] = made
        return made
    }

    func directional(_ character: String) -> [SpriteFrame] {
        if let cached = directionFrames[character] { return cached }
        let made = cut(decoded(character + "_directions"), directionMeta[character] ?? [])
        directionFrames[character] = made
        return made
    }

    /// Android `Bitmap.createBitmap(actors[id], 0, 0, 256, 320)`: the raw first cell of the front
    /// atlas, shown on the house-player cards.
    func readyCell(_ character: String) -> UIImage? {
        if let cached = readyCells[character] { return cached }
        guard let atlas = image(character)?.cgImage, let cropped = atlas.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 320)) else { return nil }
        let made = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        readyCells[character] = made
        return made
    }

    /// Android `prepareMotion(ids)`: keeps exactly the locomotion atlases of this roster.
    func prepareMotion(_ ids: [String]) {
        for id in Array(motion.keys) where !ids.contains(id) {
            motion.removeValue(forKey: id)
        }
        motionCells = motionCells.filter { entry in ids.contains(where: { entry.key.hasPrefix($0 + "/") }) }
        var seen = Set<String>()
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            if motion[id] == nil, let atlas = decoded(id + "_locomotion") { motion[id] = atlas }
        }
    }

    private func motionFrame(_ character: String, _ row: Int, _ phase: Int, front: Bool) -> SpriteFrame {
        let key = character + "/\(row)/\(phase)"
        if let cached = motionCells[key] { return cached }
        let rect = CGRect(x: phase * 192, y: row * 240, width: 192, height: 240)
        var cell: UIImage? = nil
        if let atlas = motion[character], let cropped = atlas.cropping(to: rect) {
            cell = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        }
        let made = SpriteFrame(rect: rect, handX: front ? 136 : 168, handY: 174, image: cell)
        motionCells[key] = made
        return made
    }

    /// Android `anchor(id, visual)`: the opaque body bounds of the visual's pose family.
    func anchor(_ character: String, _ visual: SpriteVisual) -> SpriteAnchor {
        let key = SplashPose.anchorKey(visual.key)
        let cacheKey = character + "/" + key
        if let cached = anchors[cacheKey] { return cached }
        let rect: CGRect
        let source: CGImage?
        if key == "front" {
            rect = frontMeta[character]?.first?.rect ?? CGRect(x: 0, y: 0, width: 256, height: 320)
            source = image(character)?.cgImage
        } else if key.hasPrefix("motion") {
            rect = CGRect(x: 0, y: visual.frame.rect.minY, width: visual.frame.rect.width, height: visual.frame.rect.height)
            source = motion[character]
        } else {
            let list = directionMeta[character] ?? []
            let index = key == "back" ? 8 : 0
            rect = index < list.count ? list[index].rect : CGRect(x: 0, y: 0, width: 256, height: 320)
            source = image(character + "_directions")?.cgImage
        }
        guard let atlas = source else {
            return SpriteAnchor(left: 0, top: 0, right: Float(rect.width), bottom: Float(rect.height))
        }
        let made = SpriteSizing.anchor(atlas, rect)
        anchors[cacheKey] = made
        return made
    }

    /// Android `portrait(id)`: the ready pose normalised to its visible body (home, house players,
    /// results and the battle loading screen).
    func portrait(_ character: String) -> UIImage? {
        if let cached = portraits[character] { return cached }
        guard let atlas = image(character)?.cgImage, let rect = frontMeta[character]?.first?.rect else { return nil }
        let anchor = SpriteSizing.anchor(atlas, rect)
        guard let made = SpriteSizing.portrait(atlas, rect, anchor) else { return nil }
        portraits[character] = made
        return made
    }

    func visual(_ a: SplashActor, _ index: Int, _ yaw: Double = 0.0) -> SpriteVisual? {
        let facing = SplashPose.facing(a.facing, yaw)
        let character = a.member.character
        if index >= 100 && motion[character] != nil {
            let row = (facing == .front ? 0 : (facing == .back ? 4 : 2)) + (index >= 104 ? 1 : 0)
            let phase = (index - 100) % 4
            let frame = motionFrame(character, row, phase, front: facing == .front)
            return SpriteVisual(frame: frame, mirrored: facing == .left, key: "motion-\(row)-\(phase)", atlas: character + "_locomotion")
        }
        let safeIndex = SplashPose.safeIndex(index)
        if facing == .front {
            let list = frames(character)
            guard safeIndex >= 0 && safeIndex < list.count else { return nil }
            return SpriteVisual(frame: list[safeIndex], mirrored: false, key: "front-\(safeIndex)", atlas: character)
        }
        let frame = SplashPose.directionalPose(safeIndex) + (facing == .back ? 8 : 0)
        let list = directional(character)
        guard frame < list.count else { return nil }
        return SpriteVisual(frame: list[frame], mirrored: facing == .left, key: "direction-\(frame)", atlas: character + "_directions")
    }

    func scene(_ arena: Arena) -> UIImage? { return image("arena_" + arena.rawValue.lowercased()) }
    var lagoon: UIImage? { return image("lagoon") }
    var logo: UIImage? { return image("splash_icon") }

    func balloon(_ color: Int) -> UIImage? {
        guard color >= 0 && color < ArtStore.balloonNames.count else { return nil }
        return image("balloon_" + ArtStore.balloonNames[color])
    }

    /// Android `wordBalloonSource = Rect(35, 0, 245, 280)`: transparent side padding cropped.
    func wordBalloon(_ color: Int) -> UIImage? {
        if let cached = wordBalloons[color] { return cached }
        guard let source = balloon(color)?.cgImage,
              let cropped = source.cropping(to: CGRect(x: 35, y: 0, width: 210, height: 280)) else { return nil }
        let trimmed = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        wordBalloons[color] = trimmed
        return trimmed
    }

    func splash(_ shape: Int, _ color: Int) -> UIImage? {
        guard shape >= 0 && shape < 6 && color >= 0 && color < 6 else { return nil }
        return image("splash_\(shape)_c\(color)")
    }

    /// Precomposes stable paint/pose combinations once (Android caches 48, oldest first out).
    func painted(_ a: SplashActor, _ index: Int, _ yaw: Double = 0.0) -> UIImage? {
        if a.paint.isEmpty { return nil }
        guard let pose = visual(a, index, yaw), let base = pose.frame.image else { return nil }
        let stains = a.paint.map { "\($0.color),\($0.u),\($0.v)" }.joined(separator: ";")
        let key = a.member.character + ":" + pose.key + ":" + stains
        if let cached = paintedCache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 320), format: format)
        let marks = a.paint
        let composed = renderer.image { _ in
            base.draw(in: CGRect(x: 0, y: 0, width: 256, height: 320))
            for stain in marks {
                let x = 256 * CGFloat(stain.u)
                let y = 320 * CGFloat(stain.v)
                let w: CGFloat = 256 * 0.62
                splash(1, stain.color)?.draw(in: CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w),
                                             blendMode: .sourceAtop, alpha: 250.0 / 255.0)
            }
        }
        if paintedOrder.count >= 48 {
            let first = paintedOrder.removeFirst()
            paintedCache.removeValue(forKey: first)
        }
        paintedCache[key] = composed
        paintedOrder.append(key)
        return composed
    }
}
