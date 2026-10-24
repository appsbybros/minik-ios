import Foundation

// Port of view/BasketballSupplement.kt (Android snapshot dd722e5), statement by statement (spec 07 §3.3, §4.1.3,
// §6.3.2). The 12-frame tables are transcribed literally (pre-multiplied sockets, same Float literals).

enum BasketballSupplement {
    /// Kotlin `private val frames by lazy { mapOf(...) }` (only looked up).
    private static let frames: [String: [CharacterSpriteFrame]] = {
        var frames: [String: [CharacterSpriteFrame]] = [:]
        frames["buddy_23"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 106.500, ballSourceY: 125.600, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 103.500, ballSourceY: 125.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 101.500, ballSourceY: 126.400, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 114.400, ballSourceY: 13.200, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 101.200, ballSourceY: 13.280, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 95.150, ballSourceY: 13.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 102.300, ballSourceY: 13.240, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 108.350, ballSourceY: 13.280, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 101.200, ballSourceY: 13.240, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 114.400, ballSourceY: 12.600, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 112.200, ballSourceY: 12.640, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_buddy_23_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 107.800, ballSourceY: 12.720, targetHeightDp: 200)
        ]
        frames["ace_23"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 114.000, ballSourceY: 135.600, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 115.500, ballSourceY: 135.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 94.000, ballSourceY: 138.400, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 113.850, ballSourceY: 13.600, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 101.750, ballSourceY: 13.840, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 96.250, ballSourceY: 14.040, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 113.300, ballSourceY: 13.600, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 110.000, ballSourceY: 13.600, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 105.050, ballSourceY: 13.960, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 112.750, ballSourceY: 13.520, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 101.200, ballSourceY: 13.360, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_ace_23_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 99.550, ballSourceY: 13.400, targetHeightDp: 200)
        ]
        frames["rooza"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 116.500, ballSourceY: 135.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 112.500, ballSourceY: 133.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 113.500, ballSourceY: 135.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 144.650, ballSourceY: 14.000, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 141.350, ballSourceY: 12.840, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 116.050, ballSourceY: 12.840, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 108.350, ballSourceY: 13.560, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 108.900, ballSourceY: 13.560, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 107.250, ballSourceY: 14.040, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 121.000, ballSourceY: 13.600, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 106.700, ballSourceY: 13.800, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_rooza_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 113.850, ballSourceY: 13.960, targetHeightDp: 200)
        ]
        frames["unicorn_32"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 131.500, ballSourceY: 130.800, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 117.500, ballSourceY: 128.400, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 120.500, ballSourceY: 130.000, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 138.600, ballSourceY: 13.440, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 120.450, ballSourceY: 13.120, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 105.050, ballSourceY: 13.760, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 103.950, ballSourceY: 13.760, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 109.450, ballSourceY: 13.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 121.000, ballSourceY: 14.240, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 132.000, ballSourceY: 13.440, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 125.400, ballSourceY: 13.760, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_unicorn_32_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 127.600, ballSourceY: 13.720, targetHeightDp: 200)
        ]
        frames["kyra"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 111.000, ballSourceY: 140.000, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 107.000, ballSourceY: 140.800, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 90.500, ballSourceY: 143.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 103.400, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 105.050, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 96.250, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 102.850, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 103.400, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 90.200, ballSourceY: 14.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 117.700, ballSourceY: 14.400, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 111.100, ballSourceY: 14.400, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_kyra_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 123.200, ballSourceY: 14.400, targetHeightDp: 200)
        ]
        frames["bob"] = [
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_00, anchorX01: 0.5, anchorY01: 1, ballSourceX: 94.000, ballSourceY: 123.200, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_01, anchorX01: 0.5, anchorY01: 1, ballSourceX: 87.000, ballSourceY: 122.400, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_02, anchorX01: 0.5, anchorY01: 1, ballSourceX: 78.000, ballSourceY: 120.400, targetHeightDp: 205),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_03, anchorX01: 0.5, anchorY01: 1, ballSourceX: 94.600, ballSourceY: 13.400, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_04, anchorX01: 0.5, anchorY01: 1, ballSourceX: 92.400, ballSourceY: 13.280, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_05, anchorX01: 0.5, anchorY01: 1, ballSourceX: 96.250, ballSourceY: 13.200, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_06, anchorX01: 0.5, anchorY01: 1, ballSourceX: 102.850, ballSourceY: 13.440, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_07, anchorX01: 0.5, anchorY01: 1, ballSourceX: 94.600, ballSourceY: 13.360, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_08, anchorX01: 0.5, anchorY01: 1, ballSourceX: 79.200, ballSourceY: 13.080, targetHeightDp: 237),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_09, anchorX01: 0.5, anchorY01: 1, ballSourceX: 99.550, ballSourceY: 12.680, targetHeightDp: 215),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_10, anchorX01: 0.5, anchorY01: 1, ballSourceX: 90.750, ballSourceY: 12.800, targetHeightDp: 200),
            CharacterSpriteFrame(resId: R.drawable.basket_bob_extra_11, anchorX01: 0.5, anchorY01: 1, ballSourceX: 90.750, ballSourceY: 12.760, targetHeightDp: 200)
        ]
        return frames
    }()

    static func enrich(old: CharacterSpriteSet) -> CharacterSpriteSet {
        guard let f = frames[old.characterId] else { return old }
        var copy = old
        copy.shotFront.mid = f[0]
        copy.shotBack.mid = f[1]
        copy.shotSide.mid = f[2]
        copy.block = CharacterDirectionalActionSprites(back: f[4], side: f[5], front: f[3])
        copy.rebound = CharacterDirectionalActionSprites(back: f[7], side: f[8], front: f[6])
        copy.winner = f[9]
        copy.loser = f[10]
        copy.spectator = f[11]
        return copy
    }

    /// Kotlin positional call form.
    static func enrich(_ old: CharacterSpriteSet) -> CharacterSpriteSet { return enrich(old: old) }
}
