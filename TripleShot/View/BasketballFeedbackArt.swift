import Foundation

// Port of view/BasketballFeedbackArt.kt (Android snapshot dd722e5), statement by statement (spec 07 §3.4, §4.1.4-§4.1.6,
// §6.3.3, §6.3.4). The cell tables are transcribed literally (same order, same Float literals). Quirk kept: the
// socket x is 0.7 * w for every cell index with index % 3 == 2 (spec 07 §8.8).

/** Alpha-preserving sprite cuts and pivots: art/basketball-feedback-20261016/manifest.json. */
enum BasketballFeedbackArt {
    private static let kyra_original: [CharacterSpriteFrame] = [
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_00, anchorX01: 0.5, anchorY01: 0.98667, ballSourceX: 104.500, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_01, anchorX01: 0.5, anchorY01: 0.98222, ballSourceX: 104.500, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_02, anchorX01: 0.5, anchorY01: 0.99556, ballSourceX: 146.300, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_03, anchorX01: 0.5, anchorY01: 0.99556, ballSourceX: 104.500, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_04, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.500, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_05, anchorX01: 0.5, anchorY01: 0.99556, ballSourceX: 146.300, ballSourceY: 117.000, targetHeightDp: 209.302),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_06, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.500, ballSourceY: 105.040, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_07, anchorX01: 0.5, anchorY01: 0.99010, ballSourceX: 104.500, ballSourceY: 105.040, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_08, anchorX01: 0.5, anchorY01: 0.99010, ballSourceX: 146.300, ballSourceY: 105.040, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_09, anchorX01: 0.5, anchorY01: 0.96040, ballSourceX: 104.500, ballSourceY: 111.100, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_10, anchorX01: 0.5, anchorY01: 0.97030, ballSourceX: 104.500, ballSourceY: 111.100, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_11, anchorX01: 0.5, anchorY01: 0.99505, ballSourceX: 146.300, ballSourceY: 111.100, targetHeightDp: 187.907),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_12, anchorX01: 0.5, anchorY01: 0.98723, ballSourceX: 104.500, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_13, anchorX01: 0.5, anchorY01: 0.98298, ballSourceX: 104.500, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_14, anchorX01: 0.5, anchorY01: 0.98723, ballSourceX: 146.300, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_15, anchorX01: 0.5, anchorY01: 0.99574, ballSourceX: 104.500, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_16, anchorX01: 0.5, anchorY01: 0.99574, ballSourceX: 104.500, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_17, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 146.300, ballSourceY: 14.100, targetHeightDp: 218.605),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_18, anchorX01: 0.5, anchorY01: 0.89623, ballSourceX: 104.500, ballSourceY: 110.240, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_19, anchorX01: 0.5, anchorY01: 0.90094, ballSourceX: 104.500, ballSourceY: 110.240, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_20, anchorX01: 0.5, anchorY01: 0.91509, ballSourceX: 146.300, ballSourceY: 110.240, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_21, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.500, ballSourceY: 12.720, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_22, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.500, ballSourceY: 12.720, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_23, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 146.300, ballSourceY: 12.720, targetHeightDp: 197.209),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_24, anchorX01: 0.5, anchorY01: 0.97436, ballSourceX: 104.500, ballSourceY: 66.300, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_25, anchorX01: 0.5, anchorY01: 0.97949, ballSourceX: 104.500, ballSourceY: 66.300, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_26, anchorX01: 0.5, anchorY01: 0.98462, ballSourceX: 146.300, ballSourceY: 66.300, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_27, anchorX01: 0.5, anchorY01: 0.92308, ballSourceX: 104.500, ballSourceY: 101.400, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_28, anchorX01: 0.5, anchorY01: 0.96410, ballSourceX: 104.500, ballSourceY: 101.400, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_29, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 146.300, ballSourceY: 101.400, targetHeightDp: 181.395),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_30, anchorX01: 0.5, anchorY01: 0.95676, ballSourceX: 104.500, ballSourceY: 96.200, targetHeightDp: 172.093),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_31, anchorX01: 0.5, anchorY01: 0.97297, ballSourceX: 104.500, ballSourceY: 96.200, targetHeightDp: 172.093),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_32, anchorX01: 0.5, anchorY01: 0.97297, ballSourceX: 146.300, ballSourceY: 96.200, targetHeightDp: 172.093),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_33, anchorX01: 0.5, anchorY01: 0.97838, ballSourceX: 104.500, ballSourceY: 96.200, targetHeightDp: 172.093),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_34, anchorX01: 0.5, anchorY01: 0.98378, ballSourceX: 104.500, ballSourceY: 96.200, targetHeightDp: 172.093),
        CharacterSpriteFrame(resId: R.drawable.basket_kyra_original_35, anchorX01: 0.5, anchorY01: 0.97838, ballSourceX: 146.300, ballSourceY: 96.200, targetHeightDp: 172.093)
    ]
    private static let gaya_ground: [CharacterSpriteFrame] = [
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_00, anchorX01: 0.5, anchorY01: 0.97834, ballSourceX: 128.000, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_01, anchorX01: 0.5, anchorY01: 0.97112, ballSourceX: 128.000, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_02, anchorX01: 0.5, anchorY01: 0.98195, ballSourceX: 179.200, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_03, anchorX01: 0.5, anchorY01: 0.99278, ballSourceX: 128.000, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_04, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 128.000, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_05, anchorX01: 0.5, anchorY01: 0.99639, ballSourceX: 179.200, ballSourceY: 144.040, targetHeightDp: 209.848),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_06, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 128.000, ballSourceY: 130.520, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_07, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 128.000, ballSourceY: 130.520, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_08, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 179.200, ballSourceY: 130.520, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_09, anchorX01: 0.5, anchorY01: 0.97211, ballSourceX: 128.000, ballSourceY: 138.050, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_10, anchorX01: 0.5, anchorY01: 0.93625, ballSourceX: 128.000, ballSourceY: 138.050, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_11, anchorX01: 0.5, anchorY01: 0.97211, ballSourceX: 179.200, ballSourceY: 138.050, targetHeightDp: 190.152),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_12, anchorX01: 0.5, anchorY01: 0.99270, ballSourceX: 128.000, ballSourceY: 93.160, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_13, anchorX01: 0.5, anchorY01: 0.98540, ballSourceX: 128.000, ballSourceY: 93.160, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_14, anchorX01: 0.5, anchorY01: 0.99635, ballSourceX: 179.200, ballSourceY: 93.160, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_15, anchorX01: 0.5, anchorY01: 0.98540, ballSourceX: 128.000, ballSourceY: 16.440, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_16, anchorX01: 0.5, anchorY01: 0.98540, ballSourceX: 128.000, ballSourceY: 16.440, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_17, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 179.200, ballSourceY: 16.440, targetHeightDp: 207.576),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_18, anchorX01: 0.5, anchorY01: 0.93243, ballSourceX: 128.000, ballSourceY: 115.440, targetHeightDp: 168.182),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_19, anchorX01: 0.5, anchorY01: 0.92342, ballSourceX: 128.000, ballSourceY: 115.440, targetHeightDp: 168.182),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_20, anchorX01: 0.5, anchorY01: 0.93694, ballSourceX: 179.200, ballSourceY: 115.440, targetHeightDp: 168.182),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_21, anchorX01: 0.5, anchorY01: 0.93243, ballSourceX: 128.000, ballSourceY: 115.440, targetHeightDp: 168.182),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_22, anchorX01: 0.5, anchorY01: 0.92793, ballSourceX: 128.000, ballSourceY: 115.440, targetHeightDp: 168.182),
        CharacterSpriteFrame(resId: R.drawable.basket_gaya_ground_23, anchorX01: 0.5, anchorY01: 0.95045, ballSourceX: 179.200, ballSourceY: 115.440, targetHeightDp: 168.182)
    ]
    private static let comet_ground: [CharacterSpriteFrame] = [
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_00, anchorX01: 0.5, anchorY01: 0.97297, ballSourceX: 104.000, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_01, anchorX01: 0.5, anchorY01: 0.96697, ballSourceX: 104.000, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_02, anchorX01: 0.5, anchorY01: 0.97297, ballSourceX: 145.600, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_03, anchorX01: 0.5, anchorY01: 0.98198, ballSourceX: 103.500, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_04, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.000, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_05, anchorX01: 0.5, anchorY01: 0.97297, ballSourceX: 145.600, ballSourceY: 173.160, targetHeightDp: 219.079),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_06, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 104.000, ballSourceY: 156.520, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_07, anchorX01: 0.5, anchorY01: 0.98007, ballSourceX: 104.000, ballSourceY: 156.520, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_08, anchorX01: 0.5, anchorY01: 0.98339, ballSourceX: 145.600, ballSourceY: 156.520, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_09, anchorX01: 0.5, anchorY01: 0.95349, ballSourceX: 103.500, ballSourceY: 165.550, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_10, anchorX01: 0.5, anchorY01: 0.95349, ballSourceX: 104.000, ballSourceY: 165.550, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_11, anchorX01: 0.5, anchorY01: 0.98007, ballSourceX: 145.600, ballSourceY: 165.550, targetHeightDp: 198.026),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_12, anchorX01: 0.5, anchorY01: 0.99695, ballSourceX: 104.000, ballSourceY: 111.520, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_13, anchorX01: 0.5, anchorY01: 0.98780, ballSourceX: 104.000, ballSourceY: 111.520, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_14, anchorX01: 0.5, anchorY01: 0.99695, ballSourceX: 145.600, ballSourceY: 111.520, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_15, anchorX01: 0.5, anchorY01: 0.99390, ballSourceX: 103.500, ballSourceY: 19.680, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_16, anchorX01: 0.5, anchorY01: 0.99085, ballSourceX: 104.000, ballSourceY: 19.680, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_17, anchorX01: 0.5, anchorY01: 1.00000, ballSourceX: 145.600, ballSourceY: 19.680, targetHeightDp: 215.789),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_18, anchorX01: 0.5, anchorY01: 0.85284, ballSourceX: 104.000, ballSourceY: 155.480, targetHeightDp: 196.711),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_19, anchorX01: 0.5, anchorY01: 0.85619, ballSourceX: 104.000, ballSourceY: 155.480, targetHeightDp: 196.711),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_20, anchorX01: 0.5, anchorY01: 0.88294, ballSourceX: 145.600, ballSourceY: 155.480, targetHeightDp: 196.711),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_21, anchorX01: 0.5, anchorY01: 0.91639, ballSourceX: 103.500, ballSourceY: 155.480, targetHeightDp: 196.711),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_22, anchorX01: 0.5, anchorY01: 0.93645, ballSourceX: 104.000, ballSourceY: 155.480, targetHeightDp: 196.711),
        CharacterSpriteFrame(resId: R.drawable.basket_comet_ground_23, anchorX01: 0.5, anchorY01: 0.89298, ballSourceX: 145.600, ballSourceY: 155.480, targetHeightDp: 196.711)
    ]

    private static func direction(f: [CharacterSpriteFrame], start: Int) -> CharacterDirectionalActionSprites {
        return CharacterDirectionalActionSprites(back: f[start + 1], side: f[start + 2], front: f[start])
    }

    private static func walks(f: [CharacterSpriteFrame]) -> [CharacterDirectionalActionSprites] {
        return [CharacterDirectionalActionSprites(back: f[5], side: f[7], front: f[3]),
                CharacterDirectionalActionSprites(back: f[6], side: f[8], front: f[4])]
    }

    static let kyra: CharacterSpriteSet = {
        let f = kyra_original
        return CharacterSpriteSet(characterId: "kyra_original", referenceHeightPx: 240, referenceHeightDp: 200, idleBack: f[1], idleFront: f[0],
                                  shotBack: CharacterShotSprites(low: f[10], mid: f[25], set: f[13], release: f[16]),
                                  shotSide: CharacterShotSprites(low: f[11], mid: f[26], set: f[14], release: f[17]),
                                  shotFront: CharacterShotSprites(low: f[9], mid: f[24], set: f[12], release: f[15]),
                                  steal: direction(f: f, start: 18), block: direction(f: f, start: 27),
                                  rebound: direction(f: f, start: 30),
                                  dunks: [CharacterDunkSprite(frame: f[21], facing: TripleShotPlayerRenderer.Facing.FRONT),
                                          CharacterDunkSprite(frame: f[22], facing: TripleShotPlayerRenderer.Facing.BACK),
                                          CharacterDunkSprite(frame: f[23], facing: TripleShotPlayerRenderer.Facing.SIDE)],
                                  winner: f[33], loser: f[34], spectator: f[35], idleSide: f[2], locomotion: walks(f: f))
    }()

    static func folded(old: CharacterSpriteSet) -> CharacterSpriteSet {
        let f: [CharacterSpriteFrame]
        switch old.characterId {
        case "kyra": f = gaya_ground
        case "zephyr": f = comet_ground
        default: return old
        }
        var copy = old
        copy.idleFront = f[0]
        copy.idleBack = f[1]
        copy.idleSide = f[2]
        copy.locomotion = walks(f: f)
        copy.steal = direction(f: f, start: 18)
        copy.shotFront.low = f[9]
        copy.shotFront.mid = f[12]
        copy.shotFront.set = f[15]
        copy.shotBack.low = f[10]
        copy.shotBack.mid = f[13]
        copy.shotBack.set = f[16]
        copy.shotSide.low = f[11]
        copy.shotSide.mid = f[14]
        copy.shotSide.set = f[17]
        return copy
    }

    static func dribble(id: String?, facing: TripleShotPlayerRenderer.Facing) -> CharacterSpriteFrame? {
        let f: [CharacterSpriteFrame]
        switch id {
        case "kyra"?: f = gaya_ground
        case "zephyr"?: f = comet_ground
        default: return nil
        }
        let index: Int
        switch facing {
        case .FRONT: index = 21
        case .BACK: index = 22
        default: index = 23
        }
        return f[index]
    }

    // Kotlin positional call forms.
    static func folded(_ old: CharacterSpriteSet) -> CharacterSpriteSet { return folded(old: old) }
    static func dribble(_ id: String?, _ facing: TripleShotPlayerRenderer.Facing) -> CharacterSpriteFrame? {
        return dribble(id: id, facing: facing)
    }
}
