import Foundation

// Port of view/BasketballSpriteCompletion.kt (Android 6c38131), statement by statement (spec 07 §3.2, §4.1.1,
// §4.1.2, §6.3.1). The 24-pose tables are transcribed literally (same order, same Float literals); `frame()` computes
// the socket as `w * x`, `h * y` in Float at run time like Kotlin.

/** Generated bindings; source/crops/pivots are in art/basketball-20261006/manifest.json. */
enum BasketballSpriteCompletion {
    private static func frame(res: ADrawableRes, w: Float, h: Float, x: Float, y: Float, height: Float) -> CharacterSpriteFrame {
        return CharacterSpriteFrame(resId: res, anchorX01: 0.5, anchorY01: 1, ballSourceX: w * x, ballSourceY: h * y,
                                    targetHeightDp: height)
    }

    private static func pack(id: String, f: [CharacterSpriteFrame]) -> CharacterSpriteSet {
        func shot(low: Int, set: Int, release: Int) -> CharacterShotSprites {
            return CharacterShotSprites(low: f[low], mid: f[low], set: f[set], release: f[release])
        }
        let raised = CharacterDirectionalActionSprites(back: f[13], side: f[14], front: f[12])
        return CharacterSpriteSet(characterId: id, referenceHeightPx: 240, referenceHeightDp: 200, idleBack: f[1], idleFront: f[0],
                                  shotBack: shot(low: 10, set: 13, release: 16),
                                  shotSide: shot(low: 11, set: 14, release: 17),
                                  shotFront: shot(low: 9, set: 12, release: 15),
                                  steal: CharacterDirectionalActionSprites(back: f[19], side: f[20], front: f[18]), block: raised, rebound: raised,
                                  dunks: [CharacterDunkSprite(frame: f[21], facing: TripleShotPlayerRenderer.Facing.FRONT),
                                          CharacterDunkSprite(frame: f[22], facing: TripleShotPlayerRenderer.Facing.BACK),
                                          CharacterDunkSprite(frame: f[23], facing: TripleShotPlayerRenderer.Facing.SIDE)],
                                  winner: f[15], loser: f[9], spectator: f[0], idleSide: f[2],
                                  locomotion: [CharacterDirectionalActionSprites(back: f[5], side: f[7], front: f[3]),
                                               CharacterDirectionalActionSprites(back: f[6], side: f[8], front: f[4])])
    }

    /// Kotlin `private val packs: Map<String, CharacterSpriteSet> by lazy { mapOf(...) }` (only looked up).
    private static let packs: [String: CharacterSpriteSet] = {
        var packs: [String: CharacterSpriteSet] = [:]
        packs["buddy_23"] = pack(id: "buddy_23", f: [
            frame(res: R.drawable.basket_buddy_23_00, w: 180, h: 246, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_01, w: 139, h: 247, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_02, w: 180, h: 248, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_03, w: 141, h: 243, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_04, w: 141, h: 246, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_05, w: 138, h: 251, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_06, w: 136, h: 232, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_07, w: 199, h: 224, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_08, w: 197, h: 223, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_buddy_23_09, w: 168, h: 223, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_buddy_23_10, w: 166, h: 226, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_buddy_23_11, w: 146, h: 231, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_buddy_23_12, w: 144, h: 253, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_buddy_23_13, w: 133, h: 253, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_buddy_23_14, w: 161, h: 252, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_buddy_23_15, w: 141, h: 244, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_buddy_23_16, w: 165, h: 244, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_buddy_23_17, w: 159, h: 252, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_buddy_23_18, w: 213, h: 203, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_buddy_23_19, w: 233, h: 201, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_buddy_23_20, w: 244, h: 199, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_buddy_23_21, w: 141, h: 239, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_buddy_23_22, w: 158, h: 233, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_buddy_23_23, w: 171, h: 235, x: 0.68, y: 0.035, height: 215)
        ])
        packs["ace_23"] = pack(id: "ace_23", f: [
            frame(res: R.drawable.basket_ace_23_00, w: 153, h: 259, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_01, w: 140, h: 260, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_02, w: 77, h: 261, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_03, w: 121, h: 263, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_04, w: 119, h: 263, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_05, w: 126, h: 262, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_06, w: 119, h: 236, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_07, w: 170, h: 230, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_08, w: 182, h: 229, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_ace_23_09, w: 171, h: 222, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_ace_23_10, w: 166, h: 223, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_ace_23_11, w: 132, h: 229, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_ace_23_12, w: 153, h: 259, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_ace_23_13, w: 138, h: 258, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_ace_23_14, w: 97, h: 262, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_ace_23_15, w: 128, h: 248, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_ace_23_16, w: 127, h: 253, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_ace_23_17, w: 122, h: 269, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_ace_23_18, w: 198, h: 202, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_ace_23_19, w: 220, h: 202, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_ace_23_20, w: 215, h: 202, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_ace_23_21, w: 160, h: 249, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_ace_23_22, w: 145, h: 256, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_ace_23_23, w: 153, h: 246, x: 0.68, y: 0.035, height: 215)
        ])
        packs["rooza"] = pack(id: "rooza", f: [
            frame(res: R.drawable.basket_rooza_00, w: 129, h: 241, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_01, w: 124, h: 245, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_02, w: 134, h: 247, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_03, w: 116, h: 249, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_04, w: 110, h: 250, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_05, w: 106, h: 248, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_06, w: 109, h: 241, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_07, w: 184, h: 236, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_08, w: 193, h: 236, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_rooza_09, w: 158, h: 228, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_rooza_10, w: 162, h: 224, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_rooza_11, w: 161, h: 234, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_rooza_12, w: 130, h: 249, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_rooza_13, w: 124, h: 249, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_rooza_14, w: 118, h: 250, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_rooza_15, w: 140, h: 247, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_rooza_16, w: 125, h: 244, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_rooza_17, w: 147, h: 240, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_rooza_18, w: 195, h: 205, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_rooza_19, w: 186, h: 207, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_rooza_20, w: 189, h: 212, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_rooza_21, w: 141, h: 236, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_rooza_22, w: 129, h: 248, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_rooza_23, w: 139, h: 234, x: 0.68, y: 0.035, height: 215)
        ])
        packs["unicorn_32"] = pack(id: "unicorn_32", f: [
            frame(res: R.drawable.basket_unicorn_32_00, w: 185, h: 249, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_01, w: 183, h: 249, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_02, w: 140, h: 252, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_03, w: 157, h: 255, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_04, w: 169, h: 251, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_05, w: 165, h: 250, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_06, w: 164, h: 241, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_07, w: 210, h: 227, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_08, w: 198, h: 227, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_unicorn_32_09, w: 197, h: 228, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_unicorn_32_10, w: 209, h: 231, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_unicorn_32_11, w: 185, h: 232, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_unicorn_32_12, w: 171, h: 252, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_unicorn_32_13, w: 159, h: 253, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_unicorn_32_14, w: 129, h: 256, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_unicorn_32_15, w: 158, h: 238, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_unicorn_32_16, w: 156, h: 277, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_unicorn_32_17, w: 152, h: 262, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_unicorn_32_18, w: 229, h: 206, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_unicorn_32_19, w: 232, h: 199, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_unicorn_32_20, w: 227, h: 206, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_unicorn_32_21, w: 167, h: 241, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_unicorn_32_22, w: 172, h: 226, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_unicorn_32_23, w: 153, h: 242, x: 0.68, y: 0.035, height: 215)
        ])
        packs["kyra"] = pack(id: "kyra", f: [
            frame(res: R.drawable.basket_kyra_00, w: 162, h: 254, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_01, w: 159, h: 253, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_02, w: 91, h: 258, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_03, w: 149, h: 256, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_04, w: 151, h: 255, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_05, w: 158, h: 255, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_06, w: 156, h: 240, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_07, w: 186, h: 235, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_08, w: 186, h: 236, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_kyra_09, w: 156, h: 230, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_kyra_10, w: 157, h: 238, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_kyra_11, w: 134, h: 241, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_kyra_12, w: 143, h: 285, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_kyra_13, w: 141, h: 287, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_kyra_14, w: 88, h: 292, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_kyra_15, w: 142, h: 281, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_kyra_16, w: 140, h: 286, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_kyra_17, w: 115, h: 296, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_kyra_18, w: 236, h: 189, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_kyra_19, w: 208, h: 194, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_kyra_20, w: 238, h: 185, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_kyra_21, w: 149, h: 254, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_kyra_22, w: 133, h: 245, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_kyra_23, w: 167, h: 238, x: 0.68, y: 0.035, height: 215)
        ])
        packs["bob"] = pack(id: "bob", f: [
            frame(res: R.drawable.basket_bob_00, w: 105, h: 238, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_01, w: 107, h: 238, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_02, w: 60, h: 239, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_03, w: 103, h: 239, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_04, w: 98, h: 235, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_05, w: 106, h: 239, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_06, w: 108, h: 229, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_07, w: 193, h: 225, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_08, w: 191, h: 220, x: 0.74, y: 0.55, height: 176.0),
            frame(res: R.drawable.basket_bob_09, w: 150, h: 216, x: 0.51, y: 0.58, height: 155.76),
            frame(res: R.drawable.basket_bob_10, w: 146, h: 221, x: 0.51, y: 0.58, height: 155.76),
            frame(res: R.drawable.basket_bob_11, w: 138, h: 218, x: 0.83, y: 0.45, height: 155.76),
            frame(res: R.drawable.basket_bob_12, w: 105, h: 258, x: 0.5, y: 0.055, height: 208.56),
            frame(res: R.drawable.basket_bob_13, w: 107, h: 258, x: 0.5, y: 0.055, height: 208.56),
            frame(res: R.drawable.basket_bob_14, w: 87, h: 260, x: 0.69, y: 0.055, height: 208.56),
            frame(res: R.drawable.basket_bob_15, w: 122, h: 260, x: 0.28, y: 0.035, height: 198.0),
            frame(res: R.drawable.basket_bob_16, w: 129, h: 256, x: 0.68, y: 0.035, height: 198.0),
            frame(res: R.drawable.basket_bob_17, w: 111, h: 254, x: 0.68, y: 0.035, height: 198.0),
            frame(res: R.drawable.basket_bob_18, w: 206, h: 197, x: 0.68, y: 0.035, height: 147.84),
            frame(res: R.drawable.basket_bob_19, w: 196, h: 190, x: 0.68, y: 0.035, height: 147.84),
            frame(res: R.drawable.basket_bob_20, w: 193, h: 192, x: 0.68, y: 0.035, height: 147.84),
            frame(res: R.drawable.basket_bob_21, w: 146, h: 237, x: 0.28, y: 0.035, height: 189.2),
            frame(res: R.drawable.basket_bob_22, w: 129, h: 239, x: 0.68, y: 0.035, height: 189.2),
            frame(res: R.drawable.basket_bob_23, w: 113, h: 244, x: 0.68, y: 0.035, height: 189.2)
        ])
        packs["woman_dark"] = pack(id: "woman_dark", f: [
            frame(res: R.drawable.basket_woman_dark_00, w: 160, h: 271, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_01, w: 142, h: 271, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_02, w: 104, h: 271, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_03, w: 100, h: 269, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_04, w: 102, h: 269, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_05, w: 102, h: 270, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_06, w: 106, h: 243, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_07, w: 178, h: 239, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_08, w: 176, h: 234, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_woman_dark_09, w: 128, h: 222, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_woman_dark_10, w: 133, h: 224, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_woman_dark_11, w: 123, h: 233, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_woman_dark_12, w: 137, h: 276, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_woman_dark_13, w: 132, h: 278, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_woman_dark_14, w: 86, h: 282, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_woman_dark_15, w: 105, h: 280, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_woman_dark_16, w: 112, h: 278, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_woman_dark_17, w: 128, h: 266, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_woman_dark_18, w: 195, h: 206, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_woman_dark_19, w: 197, h: 201, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_woman_dark_20, w: 176, h: 207, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_woman_dark_21, w: 125, h: 242, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_woman_dark_22, w: 128, h: 224, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_woman_dark_23, w: 138, h: 239, x: 0.68, y: 0.035, height: 215)
        ])
        packs["nova"] = pack(id: "nova", f: [
            frame(res: R.drawable.basket_nova_00, w: 104, h: 259, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_01, w: 103, h: 259, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_02, w: 65, h: 261, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_03, w: 91, h: 262, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_04, w: 91, h: 263, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_05, w: 90, h: 262, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_06, w: 100, h: 246, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_07, w: 175, h: 237, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_08, w: 209, h: 241, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_nova_09, w: 174, h: 215, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_nova_10, w: 178, h: 220, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_nova_11, w: 119, h: 225, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_nova_12, w: 111, h: 275, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_nova_13, w: 108, h: 273, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_nova_14, w: 66, h: 275, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_nova_15, w: 112, h: 281, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_nova_16, w: 118, h: 288, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_nova_17, w: 114, h: 283, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_nova_18, w: 221, h: 193, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_nova_19, w: 207, h: 193, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_nova_20, w: 229, h: 197, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_nova_21, w: 126, h: 228, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_nova_22, w: 134, h: 239, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_nova_23, w: 103, h: 248, x: 0.68, y: 0.035, height: 215)
        ])
        packs["coach_67"] = pack(id: "coach_67", f: [
            frame(res: R.drawable.basket_coach_67_00, w: 177, h: 255, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_01, w: 181, h: 254, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_02, w: 92, h: 257, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_03, w: 124, h: 261, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_04, w: 126, h: 261, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_05, w: 132, h: 254, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_06, w: 129, h: 239, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_07, w: 208, h: 233, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_08, w: 205, h: 233, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_coach_67_09, w: 179, h: 218, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_coach_67_10, w: 194, h: 220, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_coach_67_11, w: 140, h: 241, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_coach_67_12, w: 171, h: 267, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_coach_67_13, w: 164, h: 267, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_coach_67_14, w: 90, h: 276, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_coach_67_15, w: 167, h: 239, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_coach_67_16, w: 160, h: 250, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_coach_67_17, w: 137, h: 280, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_coach_67_18, w: 220, h: 207, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_coach_67_19, w: 224, h: 207, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_coach_67_20, w: 215, h: 214, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_coach_67_21, w: 159, h: 265, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_coach_67_22, w: 146, h: 242, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_coach_67_23, w: 142, h: 244, x: 0.68, y: 0.035, height: 215)
        ])
        packs["zephyr"] = pack(id: "zephyr", f: [
            frame(res: R.drawable.basket_zephyr_00, w: 192, h: 243, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_01, w: 193, h: 243, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_02, w: 114, h: 247, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_03, w: 177, h: 247, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_04, w: 178, h: 248, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_05, w: 189, h: 251, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_06, w: 185, h: 238, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_07, w: 216, h: 233, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_08, w: 223, h: 226, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_zephyr_09, w: 184, h: 216, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_zephyr_10, w: 198, h: 217, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_zephyr_11, w: 175, h: 248, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_zephyr_12, w: 176, h: 272, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_zephyr_13, w: 176, h: 271, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_zephyr_14, w: 130, h: 275, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_zephyr_15, w: 166, h: 276, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_zephyr_16, w: 176, h: 283, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_zephyr_17, w: 142, h: 291, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_zephyr_18, w: 213, h: 203, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_zephyr_19, w: 228, h: 198, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_zephyr_20, w: 219, h: 209, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_zephyr_21, w: 183, h: 257, x: 0.28, y: 0.035, height: 215),
            frame(res: R.drawable.basket_zephyr_22, w: 170, h: 250, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_zephyr_23, w: 175, h: 246, x: 0.68, y: 0.035, height: 215)
        ])
        packs["flare"] = pack(id: "flare", f: [
            frame(res: R.drawable.basket_flare_00, w: 162, h: 245, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_01, w: 164, h: 242, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_02, w: 80, h: 246, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_03, w: 129, h: 248, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_04, w: 130, h: 248, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_05, w: 125, h: 245, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_06, w: 127, h: 235, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_07, w: 216, h: 233, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_08, w: 223, h: 228, x: 0.74, y: 0.55, height: 200),
            frame(res: R.drawable.basket_flare_09, w: 189, h: 223, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_flare_10, w: 185, h: 212, x: 0.51, y: 0.58, height: 177),
            frame(res: R.drawable.basket_flare_11, w: 131, h: 230, x: 0.83, y: 0.45, height: 177),
            frame(res: R.drawable.basket_flare_12, w: 154, h: 264, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_flare_13, w: 151, h: 263, x: 0.5, y: 0.055, height: 237),
            frame(res: R.drawable.basket_flare_14, w: 95, h: 268, x: 0.69, y: 0.055, height: 237),
            frame(res: R.drawable.basket_flare_15, w: 163, h: 264, x: 0.28, y: 0.035, height: 225),
            frame(res: R.drawable.basket_flare_16, w: 159, h: 258, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_flare_17, w: 139, h: 251, x: 0.68, y: 0.035, height: 225),
            frame(res: R.drawable.basket_flare_18, w: 234, h: 180, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_flare_19, w: 224, h: 176, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_flare_20, w: 215, h: 173, x: 0.68, y: 0.035, height: 168),
            frame(res: R.drawable.basket_flare_21, w: 135, h: 265, x: 0.77, y: 0.035, height: 215),
            frame(res: R.drawable.basket_flare_22, w: 123, h: 256, x: 0.68, y: 0.035, height: 215),
            frame(res: R.drawable.basket_flare_23, w: 144, h: 252, x: 0.68, y: 0.035, height: 215)
        ])
        return packs
    }()

    /// iOS only: the ids `packs` has a set for (taken from the map itself), so the catalog's one-time composition
    /// covers exactly the ids for which Kotlin's `find` returns a pack. Sorted for a stable order; the composition
    /// does not depend on it.
    static let packIds: [String] = packs.keys.sorted()

    /// Kotlin returns a new copy on every call; with value types the copy is implicit.
    static func find(id: String?) -> CharacterSpriteSet? {
        guard let id = id, let pack = packs[id] else { return nil }
        return BasketballSupplement.enrich(old: pack)
    }

    static func enrich(old: CharacterSpriteSet) -> CharacterSpriteSet {
        guard let fresh = packs[old.characterId] else { return old }
        var copy = old
        copy.idleSide = fresh.idleSide
        copy.locomotion = fresh.locomotion
        copy.idleFront = old.characterId == "zephyr" ? fresh.idleFront : old.idleFront
        copy.shotFront.release = fresh.shotFront.release
        copy.shotSide.release = fresh.shotSide.release
        return copy
    }

    // Kotlin positional call forms.
    static func find(_ id: String?) -> CharacterSpriteSet? { return find(id: id) }
    static func enrich(_ old: CharacterSpriteSet) -> CharacterSpriteSet { return enrich(old: old) }
}
