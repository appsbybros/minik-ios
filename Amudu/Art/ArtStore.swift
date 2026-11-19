import UIKit

/// One atlas cell: its pixel rectangle and the hand anchor normalized to that cell's size (Android `SpriteFrame`).
struct SpriteFrame {
    let rect: CGRect
    let handX: CGFloat
    let handY: CGFloat
    /// Android `face` (art/face-protection.json): the eyes/mouth oval as fractions of the cell (Kotlin left, top,
    /// right, bottom; stored here as origin and size), kept free of paint.
    var face: CGRect? = nil
}

/// Android `SpriteVisual`: the cropped cell to draw, its frame data, and whether side art is mirrored.
struct SpriteVisual {
    let image: UIImage
    let frame: SpriteFrame
    let mirrored: Bool
    let facing: String
}

private final class ArtBundleToken {}

/// Android `ArtStore`: the approved character atlases (front + directional), arenas and balls, with
/// `atlas.json` / `directions.json` frame crops and hand anchors.
final class ArtStore {
    private(set) var frames: [String: [SpriteFrame]] = [:]
    private(set) var directionalFrames: [String: [SpriteFrame]] = [:]
    private var frameImages: [String: [UIImage]] = [:]
    private var directionalImages: [String: [UIImage]] = [:]
    private var portraits: [String: UIImage] = [:]
    private var anchors: [String: SpriteAnchor] = [:]
    private(set) var scenes: [ArenaScene: UIImage] = [:]
    private(set) var balls: [BallKind: UIImage] = [:]
    /// Android `practiceTree` / `balloonMenu` (`practice_tree.webp`, `paint_balloon_menu.webp`).
    let practiceTree: UIImage
    let balloonMenu: UIImage
    private var paintedBalloons: [UInt32: UIImage] = [:]
    private let placeholderFrame = SpriteFrame(rect: CGRect(x: 0, y: 0, width: 256, height: 320), handX: 0.5, handY: 0.6)

    init() {
        let bundle = Bundle(for: ArtBundleToken.self)
        practiceTree = ArtStore.load("practice_tree", bundle)
        balloonMenu = ArtStore.load("paint_balloon_menu", bundle)
        for arena in ArenaScene.allCases { scenes[arena] = ArtStore.load(arena.artName, bundle) }
        // Android: the paint balloon is drawn procedurally (`PaintEffects.balloon()`), the other balls are artwork.
        for kind in BallKind.allCases { balls[kind] = kind == .paint ? PaintEffects.balloon() : ArtStore.load(kind.artName, bundle) }
        let atlas = ArtStore.characters(ArtStore.json("atlas", bundle))
        let directional = ArtStore.characters(ArtStore.json("directions", bundle))
        let faces = ArtStore.json("face-protection", bundle)
        for c in AmuduCharacters.all {
            let sheet = ArtStore.load(c.id, bundle)
            let side = ArtStore.load(c.id + "_directions", bundle)
            let front = ArtStore.parse(atlas, c.id, faces)
            let directions = ArtStore.parse(directional, c.id, faces, side: true)
            frames[c.id] = front
            directionalFrames[c.id] = directions
            frameImages[c.id] = front.map { ArtStore.crop(sheet, $0.rect) }
            directionalImages[c.id] = directions.map { ArtStore.crop(side, $0.rect) }
        }
    }

    private static func load(_ name: String, _ bundle: Bundle) -> UIImage {
        if let image = UIImage(named: name, in: bundle, compatibleWith: nil) { return image }
        if let image = UIImage(named: name) { return image }
        return UIImage()
    }

    private static func json(_ name: String, _ bundle: Bundle) -> [String: Any] {
        guard let url = bundle.url(forResource: name, withExtension: "json") ?? Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func characters(_ root: [String: Any]) -> [String: Any] {
        return (root["characters"] as? [String: Any]) ?? [:]
    }

    /// Hand anchors are pixels of their cell; Android normalizes them by the cell's width and height (front cells are
    /// 256x320, directional cells 192x240).
    /// The face oval of each cell comes from `face-protection.json` (its `front` or `side` list, by frame index).
    private static func parse(_ table: [String: Any], _ id: String, _ faces: [String: Any], side: Bool = false) -> [SpriteFrame] {
        guard let entry = table[id] as? [String: Any], let list = entry["frames"] as? [Any] else { return [] }
        let faceList = ((faces[id] as? [String: Any])?[side ? "side" : "front"] as? [Any]) ?? []
        var out: [SpriteFrame] = []
        for (i, item) in list.enumerated() {
            guard let f = item as? [String: Any] else { continue }
            let r = (f["rect"] as? [Any])?.compactMap { AmuduCodec.number($0) } ?? []
            let h = (f["hand"] as? [Any])?.compactMap { AmuduCodec.number($0) } ?? []
            guard r.count >= 4, h.count >= 2 else { continue }
            let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            var face: CGRect?
            if i < faceList.count, let values = (faceList[i] as? [Any])?.compactMap({ AmuduCodec.number($0) }), values.count >= 4 {
                face = CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
            }
            out.append(SpriteFrame(rect: rect, handX: CGFloat(h[0] / r[2]), handY: CGFloat(h[1] / r[3]), face: face))
        }
        return out
    }

    private static func crop(_ image: UIImage, _ rect: CGRect) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let scale = image.scale
        let pixels = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale, width: rect.width * scale, height: rect.height * scale)
        guard let part = cg.cropping(to: pixels) else { return UIImage() }
        return UIImage(cgImage: part, scale: 1, orientation: .up)
    }

    func scene(_ scene: ArenaScene) -> UIImage { return scenes[scene] ?? UIImage() }

    func ball(_ kind: BallKind) -> UIImage { return balls[kind] ?? UIImage() }

    /// Android `ballPreview`: menus show the paint balloon artwork, every other ball as itself.
    func ballPreview(_ kind: BallKind) -> UIImage { return kind == .paint ? balloonMenu : ball(kind) }

    /// Android `paintBalloon(color)`: the procedural balloon in the current paint colour (cached per colour).
    func paintBalloon<C: BinaryInteger>(_ color: C) -> UIImage {
        let key = UInt32(truncatingIfNeeded: color)
        if let cached = paintedBalloons[key] { return cached }
        let made = PaintEffects.balloon(key)
        paintedBalloons[key] = made
        return made
    }

    /// Android `ArtStore.portrait`: the front idle cell, sized by its opaque bounds into a 256x320 portrait (cached).
    func portrait(_ id: String) -> UIImage {
        let key = AmuduCharacters.get(id).id
        if let cached = portraits[key] { return cached }
        guard let cell = frameImages[key]?.first else { return UIImage() }
        let made = SpriteSizing.portrait(cell, frontAnchor(key))
        portraits[key] = made
        return made
    }

    private func frontAnchor(_ id: String) -> SpriteAnchor {
        let key = id + "/front"
        if let cached = anchors[key] { return cached }
        let made = SpriteSizing.anchor(cell(frameImages[id], 0))
        anchors[key] = made
        return made
    }

    /// Android `ArtStore.anchor`: the opaque bounds of the idle cell for this facing (front, back or side), cached.
    func anchor(_ character: String, _ visual: SpriteVisual) -> SpriteAnchor {
        let id = AmuduCharacters.get(character).id
        let facing = visual.facing == "front" ? "front" : (visual.facing == "back" ? "back" : "side")
        if facing == "front" { return frontAnchor(id) }
        let key = id + "/" + facing
        if let cached = anchors[key] { return cached }
        let made = SpriteSizing.anchor(cell(directionalImages[id], facing == "back" ? 8 : 0))
        anchors[key] = made
        return made
    }

    /// Android `ArtStore.frame`: which of the 16 front cells an actor shows right now.
    func frame(_ a: GameActor, _ e: AmuduEngine) -> Int {
        if e.time - a.hitAt < 0.32 { return 10 }
        if e.time < a.duckUntil { return 9 }
        if a.jumpHeight > 0.015 { return 8 }
        if e.time - a.throwAt < 0.13 { return 6 }
        if e.time - a.throwAt < 0.42 { return 7 }
        if e.time - a.catchAt < 0.35 { return 4 }
        // Low attacks use the existing hands-down crouch pose.
        if e.time < a.catchUntil { return e.phase == .flight && a.catchHeight < 1.05 ? 9 : 6 }
        if e.ball.holder == a.member.id { return 4 }
        if a.actuallyMoving { return 12 + Kotlin.toInt(a.gait) % 4 }
        return 0
    }

    func visual(_ a: GameActor, _ e: AmuduEngine) -> SpriteVisual {
        let id = AmuduCharacters.get(a.member.character).id
        // An eliminated player walks off the court (presentation only).
        let walking = EliminationExit.walking(a, e.time)
        let direction = walking ? EliminationExit.facing(a) : a.facing
        let index = walking ? 12 + Kotlin.toInt(EliminationExit.gait(a, e.time)) % 4 : frame(a, e)
        let facing: String
        if abs(direction.x) > abs(direction.y) * 0.85 {
            facing = direction.x < 0 ? "left" : "right"
        } else {
            facing = direction.y < 0 ? "back" : "front"
        }
        if facing == "front" {
            return SpriteVisual(image: cell(frameImages[id], index), frame: cellFrame(frames[id], index), mirrored: false, facing: facing)
        }
        let pose: Int
        switch index {
        case 2, 4: pose = 3
        case 5: pose = 4
        case 6, 7: pose = 5
        case 8: pose = 6
        case 9, 10: pose = 7
        case 12, 13: pose = 1
        case 14, 15: pose = 2
        default: pose = 0
        }
        let directional = pose + (facing == "back" ? 8 : 0)
        return SpriteVisual(image: cell(directionalImages[id], directional), frame: cellFrame(directionalFrames[id], directional),
                            mirrored: facing == "left", facing: facing)
    }

    private func cell(_ images: [UIImage]?, _ index: Int) -> UIImage {
        guard let images, index >= 0, index < images.count else { return UIImage() }
        return images[index]
    }

    private func cellFrame(_ list: [SpriteFrame]?, _ index: Int) -> SpriteFrame {
        guard let list, index >= 0, index < list.count else { return placeholderFrame }
        return list[index]
    }
}
