import Foundation

// Port of view/TripleShotCharacterVisuals.kt (Android 6c38131), statement by statement (spec 07 §3.1, §4.1).
// Drawable ids are their Android resource names (R.drawable.x is a String). `ballForegroundRect01` stays an
// android.graphics.RectF (ARectF: left, top, right, bottom). The Kotlin data classes become structs; their
// synthesized `==`/hash differ from Kotlin's data-class equality (Float.compare) only for NaN and -0.0, which no
// catalog value holds. Kotlin `copy(x = ...)` is written as a mutation of a `var` copy.
//
// iOS change required by the port brief (spec 07 §8.6): Android's `find()` builds a fresh copy of six of the twelve
// sets on every call (Completion + Supplement + folded); here every set is composed ONCE, with the same Kotlin
// composition, into an immutable dictionary. The results are identical (pure functions of constant tables).

/**
 * One authored sprite frame.
 *
 * Ball anchors are source-image pixels because generated art is not guaranteed to use the same
 * canvas size. targetHeightDp is optional: when absent, the character pack's reference scale is
 * used so older crouch/sit/release art keeps its natural relative height.
 */
struct CharacterSpriteFrame: Hashable {
    var resId: ADrawableRes
    var anchorX01: Float
    var anchorY01: Float
    var ballSourceX: Float?
    var ballSourceY: Float?
    var targetHeightDp: Float?
    /**
     * Optional normalized source rectangle redrawn after the dynamic ball, allowing the near
     * hand/forearm to cover the ball without baking a basketball into the sprite.
     */
    var ballForegroundRect01: ARectF?

    init(resId: ADrawableRes, anchorX01: Float = 0.5, anchorY01: Float = 1, ballSourceX: Float? = nil,
         ballSourceY: Float? = nil, targetHeightDp: Float? = nil, ballForegroundRect01: ARectF? = nil) {
        self.resId = resId
        self.anchorX01 = anchorX01
        self.anchorY01 = anchorY01
        self.ballSourceX = ballSourceX
        self.ballSourceY = ballSourceY
        self.targetHeightDp = targetHeightDp
        self.ballForegroundRect01 = ballForegroundRect01
    }

    /// Kotlin positional constructor form (the generated tables call it positionally).
    init(_ resId: ADrawableRes, _ anchorX01: Float = 0.5, _ anchorY01: Float = 1, _ ballSourceX: Float? = nil,
         _ ballSourceY: Float? = nil, _ targetHeightDp: Float? = nil, _ ballForegroundRect01: ARectF? = nil) {
        self.init(resId: resId, anchorX01: anchorX01, anchorY01: anchorY01, ballSourceX: ballSourceX,
                  ballSourceY: ballSourceY, targetHeightDp: targetHeightDp, ballForegroundRect01: ballForegroundRect01)
    }

    var hasBallAnchor: Bool {
        return ballSourceX != nil && ballSourceY != nil
    }
}

struct CharacterShotSprites: Hashable {
    var low: CharacterSpriteFrame
    var mid: CharacterSpriteFrame
    var set: CharacterSpriteFrame
    var release: CharacterSpriteFrame? = nil
}

extension CharacterShotSprites {
    /// Kotlin positional constructor form `CharacterShotSprites(low, mid, set, release)`.
    init(_ low: CharacterSpriteFrame, _ mid: CharacterSpriteFrame, _ set: CharacterSpriteFrame,
         _ release: CharacterSpriteFrame? = nil) {
        self.init(low: low, mid: mid, set: set, release: release)
    }
}

/** Constructor order is BACK, SIDE, FRONT (the generated tables call it positionally). */
struct CharacterDirectionalActionSprites: Hashable {
    var back: CharacterSpriteFrame
    var side: CharacterSpriteFrame
    var front: CharacterSpriteFrame
}

extension CharacterDirectionalActionSprites {
    /// Kotlin positional constructor form `CharacterDirectionalActionSprites(back, side, front)`.
    init(_ back: CharacterSpriteFrame, _ side: CharacterSpriteFrame, _ front: CharacterSpriteFrame) {
        self.init(back: back, side: side, front: front)
    }
}

/** One selectable dunk pose. CourtView chooses among these from approach angle + live speed. */
struct CharacterDunkSprite: Hashable {
    var frame: CharacterSpriteFrame
    var facing: TripleShotPlayerRenderer.Facing
    /** Speed at which this pose looks most natural. Selection is weighted, never hard-gated. */
    var preferredSpeed01: Float = 0.82
    /** Relative lottery weight after angle/speed scoring. */
    var weight: Float = 1
    /** Small pose-specific contact polish. Positive lift raises Maya/ball above the rim. */
    var contactLiftDp: Float = 0
    /** Moves the contact point away from hoop centre toward the approach side. */
    var contactOutwardDp: Float = 0
    /** Some reverse/side poses are visually on the camera side of the rim/net. */
    var playerInFrontOfHoop: Bool = false
}

extension CharacterDunkSprite {
    /// Kotlin positional constructor form `CharacterDunkSprite(frame, facing)` (default tuning).
    init(_ frame: CharacterSpriteFrame, _ facing: TripleShotPlayerRenderer.Facing) {
        self.init(frame: frame, facing: facing)
    }
}

struct CharacterSpriteSet: Hashable {
    var characterId: String
    /** Source-pixel scale used by older frames that do not provide targetHeightDp. */
    var referenceHeightPx: Float
    var referenceHeightDp: Float
    var idleBack: CharacterSpriteFrame
    var idleFront: CharacterSpriteFrame
    var shotBack: CharacterShotSprites
    var shotSide: CharacterShotSprites
    var shotFront: CharacterShotSprites
    /** Optional 1v1 action art. SIDE is mirrored when the action points left. */
    var steal: CharacterDirectionalActionSprites? = nil
    var block: CharacterDirectionalActionSprites? = nil
    var rebound: CharacterDirectionalActionSprites? = nil
    /** Optional wow-dunk library. Every frame owns a real dynamic-ball socket. */
    var dunks: [CharacterDunkSprite] = []
    var winner: CharacterSpriteFrame
    var loser: CharacterSpriteFrame
    var spectator: CharacterSpriteFrame
    var idleSide: CharacterSpriteFrame? = nil
    var locomotion: [CharacterDirectionalActionSprites] = []
    var playfulHold: CharacterSpriteFrame? = nil
}

/**
 * Android-resource visual registry.
 *
 * The renderer never references woman_dark_* directly anymore. To add another player, register
 * one CharacterSpriteSet here after its FRONT/BACK/SIDE frames have been prepared.
 */
enum TripleShotCharacterVisualCatalog {

    private static let SHOT_LOW_HEIGHT_DP: Float = 181
    private static let SHOT_MID_HEIGHT_DP: Float = 188
    private static let SHOT_SET_HEIGHT_DP: Float = 200

    /*
     * The original non-V17 images looked too small beside the new LOW/MID/SET art.
     * The current court reads Maya a little too small. 188dp is the visual reference for upright
     * Maya frames; crouched steal crops keep pose-specific heights so they do not become giants.
     */
    static let womanDark = CharacterSpriteSet(
        characterId: TripleShotCharacterRoster.ID_WOMAN_DARK,
        referenceHeightPx: 500,
        referenceHeightDp: 200,

        idleBack: CharacterSpriteFrame(
            resId: R.drawable.woman_dark_back_standing,
            anchorX01: 0.50,
            ballSourceX: 214,
            ballSourceY: 278
        ),

        idleFront: CharacterSpriteFrame(
            resId: R.drawable.woman_dark_front_defense,
            anchorX01: 0.50,
            ballSourceX: 238,
            ballSourceY: 247
        ),

        shotBack: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_back_low,
                anchorX01: 0.495,
                ballSourceX: 294,
                ballSourceY: 515,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_back_mid,
                anchorX01: 0.502,
                ballSourceX: 279,
                ballSourceY: 165,
                targetHeightDp: 181
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_back_set,
                anchorX01: 0.500,
                ballSourceX: 242,
                ballSourceY: 62,
                targetHeightDp: SHOT_SET_HEIGHT_DP
            ),
            release: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_back_after_throw,
                anchorX01: 0.50
            )
        ),

        shotSide: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_side_low,
                anchorX01: 0.476,
                ballSourceX: 551,
                ballSourceY: 555,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_side_mid,
                anchorX01: 0.475,
                ballSourceX: 667,
                ballSourceY: 392,
                targetHeightDp: 186,
                ballForegroundRect01: ARectF(0.60, 0.18, 1.00, 0.39)
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_side_set,
                anchorX01: 0.544,
                ballSourceX: 548,
                ballSourceY: 127,
                targetHeightDp: SHOT_SET_HEIGHT_DP,
                ballForegroundRect01: ARectF(0.58, 0.00, 1.00, 0.27)
            ),
            release: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_front_throw,
                anchorX01: 0.50
            )
        ),

        shotFront: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_front_low,
                anchorX01: 0.500,
                ballSourceX: 318,
                ballSourceY: 580,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_front_mid,
                anchorX01: 0.500,
                ballSourceX: 264,
                ballSourceY: 260,
                targetHeightDp: SHOT_MID_HEIGHT_DP
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_shot_front_set,
                anchorX01: 0.510,
                ballSourceX: 238,
                ballSourceY: 68,
                targetHeightDp: SHOT_SET_HEIGHT_DP
            ),
            // A true front follow-through has not been authored yet. The renderer keeps SET
            // briefly during release instead of rotating to the wrong SIDE/BACK family.
            release: nil
        ),

        steal: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_steal_back,
                anchorX01: 0.50,
                targetHeightDp: 178
            ),
            side: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_steal_side,
                anchorX01: 0.50,
                // This crop is much shorter than the standing/block crops because Maya is
                // crouched wide. Scaling it to the same DISPLAY height made her body enormous.
                // Keep the same approximate pixel-to-dp body scale as the correctly-sized block art.
                targetHeightDp: 153
            ),
            front: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_steal_front,
                anchorX01: 0.50,
                // The crouched FRONT reach looked planted too low compared with the standing actor.
                // Keep the approved scale, but lift the whole action about 7dp during the reach.
                anchorY01: 1.11,
                // Same issue as SIDE, even more pronounced: the authored crop is only ~220 px tall.
                targetHeightDp: 110
            )
        ),

        // Action-sheet frames were generated/cropped at different POSE heights. Equal display
        // heights therefore distort Maya's anatomy. These targets keep ~0.50dp per source pixel,
        // so head/shoe/torso scale stays consistent while crouched/tucked poses remain naturally
        // shorter on screen.
        block: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_block_back,
                anchorX01: 0.50,
                targetHeightDp: 203
            ),
            side: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_block_side,
                anchorX01: 0.50,
                targetHeightDp: 208
            ),
            front: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_block_front,
                anchorX01: 0.50,
                targetHeightDp: 170
            )
        ),

        rebound: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_rebound_back,
                anchorX01: 0.50,
                targetHeightDp: 169
            ),
            side: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_rebound_side,
                anchorX01: 0.50,
                targetHeightDp: 206
            ),
            front: CharacterSpriteFrame(
                resId: R.drawable.woman_dark_rebound_front,
                anchorX01: 0.50,
                targetHeightDp: 183
            )
        ),


        dunks: [
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_back_one_hand,
                    anchorX01: 0.50,
                    ballSourceX: 617,
                    ballSourceY: 53,
                    targetHeightDp: 230
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.94,
                weight: 1.20,
                contactLiftDp: 6,
                contactOutwardDp: 0,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_back_two_hand_power,
                    anchorX01: 0.50,
                    ballSourceX: 485,
                    ballSourceY: 43,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.84,
                weight: 1.05,
                contactLiftDp: 18,
                contactOutwardDp: 2,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_back_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 485,
                    ballSourceY: 40,
                    targetHeightDp: 234
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.76,
                weight: 0.92,
                contactLiftDp: 20,
                contactOutwardDp: 4,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_front_two_hand_power,
                    anchorX01: 0.50,
                    ballSourceX: 490,
                    ballSourceY: 45,
                    targetHeightDp: 230
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.84,
                weight: 1.05,
                contactLiftDp: 5,
                contactOutwardDp: 0,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_front_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 455,
                    ballSourceY: 32,
                    targetHeightDp: 234
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.75,
                weight: 0.92,
                contactLiftDp: 14,
                contactOutwardDp: 4,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_front_statue,
                    anchorX01: 0.50,
                    ballSourceX: 640,
                    ballSourceY: 60,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.96,
                weight: 1.18,
                contactLiftDp: 6,
                contactOutwardDp: 2,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_side_two_hand_gather,
                    anchorX01: 0.50,
                    ballSourceX: 560,
                    ballSourceY: 55,
                    targetHeightDp: 226
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.72,
                weight: 0.88,
                contactLiftDp: 18,
                contactOutwardDp: 12,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_side_reverse_gather,
                    anchorX01: 0.50,
                    ballSourceX: 550,
                    ballSourceY: 105,
                    targetHeightDp: 228
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.80,
                weight: 0.90,
                contactLiftDp: 22,
                contactOutwardDp: 15,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_side_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 538,
                    ballSourceY: 45,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.86,
                weight: 1.05,
                contactLiftDp: 19,
                contactOutwardDp: 13,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.woman_dark_dunk_side_statue,
                    anchorX01: 0.50,
                    ballSourceX: 627,
                    ballSourceY: 56,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.98,
                weight: 1.22,
                contactLiftDp: 7,
                contactOutwardDp: 4,
                playerInFrontOfHoop: false
            )
        ],

        winner: CharacterSpriteFrame(
            resId: R.drawable.woman_dark_front_celebrate,
            anchorX01: 0.53
        ),

        loser: CharacterSpriteFrame(
            resId: R.drawable.woman_dark_front_sitting_sad,
            anchorX01: 0.50
        ),

        spectator: CharacterSpriteFrame(
            resId: R.drawable.woman_dark_front_sitting,
            anchorX01: 0.50
        )
    )


    /**
     * Mia Essence Skies. Internal id remains "nova" so existing saved configs keep working.
     * Assets were selected from the Aug-24/25 generated pack, alpha-trimmed and converted to
     * WebP. Ball sockets are transferred from the matching Maya production poses in normalized
     * visible-body space, so the game ball remains dynamic rather than baked into artwork.
     *
     * Known art debt: BACK LOW/MID are usable but too similar to SET; they stay on the explicit
     * replacement list instead of being treated as finished animation.
     */
    static let miaEssenceSkies = CharacterSpriteSet(
        characterId: TripleShotCharacterRoster.ID_NOVA,
        referenceHeightPx: 900,
        referenceHeightDp: 200,
        idleBack: CharacterSpriteFrame(
            resId: R.drawable.nova_idle_back,
            anchorX01: 0.50,
            ballSourceX: 333.5,
            ballSourceY: 496.9
        ),
        idleFront: CharacterSpriteFrame(
            resId: R.drawable.nova_idle_front,
            anchorX01: 0.50,
            ballSourceX: 555.6,
            ballSourceY: 478.5
        ),
        shotBack: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_back_low,
                anchorX01: 0.50,
                ballSourceX: 181.3,
                ballSourceY: 375.3,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_back_mid,
                anchorX01: 0.50,
                ballSourceX: 183.5,
                ballSourceY: 120.4,
                targetHeightDp: SHOT_MID_HEIGHT_DP
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_back_set,
                anchorX01: 0.50,
                ballSourceX: 185.4,
                ballSourceY: 46.5,
                targetHeightDp: SHOT_SET_HEIGHT_DP
            ),
            release: CharacterSpriteFrame(resId: R.drawable.nova_release_back, anchorX01: 0.50)
        ),
        shotSide: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_side_low,
                anchorX01: 0.50,
                ballSourceX: 438.7,
                ballSourceY: 410.5,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_side_mid,
                anchorX01: 0.50,
                ballSourceX: 389.3,
                ballSourceY: 238.5,
                targetHeightDp: SHOT_MID_HEIGHT_DP
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_side_set,
                anchorX01: 0.50,
                ballSourceX: 370.7,
                ballSourceY: 101.3,
                targetHeightDp: SHOT_SET_HEIGHT_DP
            ),
            release: CharacterSpriteFrame(resId: R.drawable.nova_release_side, anchorX01: 0.50)
        ),
        shotFront: CharacterShotSprites(
            low: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_front_low,
                anchorX01: 0.50,
                ballSourceX: 196.8,
                ballSourceY: 425.6,
                targetHeightDp: SHOT_LOW_HEIGHT_DP
            ),
            mid: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_front_mid,
                anchorX01: 0.50,
                ballSourceX: 188.4,
                ballSourceY: 189.2,
                targetHeightDp: SHOT_MID_HEIGHT_DP
            ),
            set: CharacterSpriteFrame(
                resId: R.drawable.nova_shot_front_set,
                anchorX01: 0.50,
                ballSourceX: 187.0,
                ballSourceY: 52.1,
                targetHeightDp: SHOT_SET_HEIGHT_DP
            ),
            release: CharacterSpriteFrame(resId: R.drawable.nova_release_front, anchorX01: 0.50)
        ),
        steal: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.nova_steal_back, anchorX01: 0.50, targetHeightDp: 178),
            side: CharacterSpriteFrame(resId: R.drawable.nova_steal_side, anchorX01: 0.50, targetHeightDp: 153),
            front: CharacterSpriteFrame(resId: R.drawable.nova_steal_front, anchorX01: 0.50, anchorY01: 1.11, targetHeightDp: 110)
        ),
        block: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.nova_block_back, anchorX01: 0.50, targetHeightDp: 203),
            side: CharacterSpriteFrame(resId: R.drawable.nova_block_side, anchorX01: 0.50, targetHeightDp: 208),
            front: CharacterSpriteFrame(resId: R.drawable.nova_block_front, anchorX01: 0.50, targetHeightDp: 170)
        ),
        rebound: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.nova_rebound_back, anchorX01: 0.50, targetHeightDp: 169),
            side: CharacterSpriteFrame(resId: R.drawable.nova_rebound_side, anchorX01: 0.50, targetHeightDp: 206),
            front: CharacterSpriteFrame(resId: R.drawable.nova_rebound_front, anchorX01: 0.50, targetHeightDp: 183)
        ),
        dunks: [
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_back_one_hand,
                    anchorX01: 0.50,
                    ballSourceX: 488.0,
                    ballSourceY: 52.5,
                    targetHeightDp: 230
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.94,
                weight: 1.20,
                contactLiftDp: 6,
                contactOutwardDp: 0,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_back_two_hand_power,
                    anchorX01: 0.50,
                    ballSourceX: 437.6,
                    ballSourceY: 44.5,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.84,
                weight: 1.05,
                contactLiftDp: 18,
                contactOutwardDp: 2,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_back_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 348.1,
                    ballSourceY: 36.2,
                    targetHeightDp: 234
                ),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.76,
                weight: 0.92,
                contactLiftDp: 20,
                contactOutwardDp: 4,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_front_two_hand_power,
                    anchorX01: 0.50,
                    ballSourceX: 325.4,
                    ballSourceY: 41.9,
                    targetHeightDp: 230
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.84,
                weight: 1.05,
                contactLiftDp: 5,
                contactOutwardDp: 0,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_front_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 284.0,
                    ballSourceY: 31.4,
                    targetHeightDp: 234
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.75,
                weight: 0.92,
                contactLiftDp: 14,
                contactOutwardDp: 4,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_front_statue,
                    anchorX01: 0.50,
                    ballSourceX: 606.5,
                    ballSourceY: 57.1,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.96,
                weight: 1.18,
                contactLiftDp: 6,
                contactOutwardDp: 2,
                playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_side_two_hand_gather,
                    anchorX01: 0.50,
                    ballSourceX: 486.7,
                    ballSourceY: 54.6,
                    targetHeightDp: 226
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.72,
                weight: 0.88,
                contactLiftDp: 18,
                contactOutwardDp: 12,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_side_reverse_gather,
                    anchorX01: 0.50,
                    ballSourceX: 448.6,
                    ballSourceY: 105.0,
                    targetHeightDp: 228
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.80,
                weight: 0.90,
                contactLiftDp: 22,
                contactOutwardDp: 15,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_side_two_hand_hang,
                    anchorX01: 0.50,
                    ballSourceX: 404.5,
                    ballSourceY: 35.8,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.86,
                weight: 1.05,
                contactLiftDp: 19,
                contactOutwardDp: 13,
                playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(
                    resId: R.drawable.nova_dunk_side_statue,
                    anchorX01: 0.50,
                    ballSourceX: 463.8,
                    ballSourceY: 58.1,
                    targetHeightDp: 232
                ),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.98,
                weight: 1.22,
                contactLiftDp: 7,
                contactOutwardDp: 4,
                playerInFrontOfHoop: false
            )
        ],
        winner: CharacterSpriteFrame(resId: R.drawable.nova_winner, anchorX01: 0.50, targetHeightDp: 190),
        loser: CharacterSpriteFrame(resId: R.drawable.nova_loser, anchorX01: 0.50, targetHeightDp: 128),
        spectator: CharacterSpriteFrame(resId: R.drawable.nova_spectator, anchorX01: 0.50, targetHeightDp: 128)
    )


    static let coach67 = CharacterSpriteSet(
        characterId: TripleShotCharacterRoster.ID_COACH_67,
        referenceHeightPx: 477,
        referenceHeightDp: 200,
        idleBack: CharacterSpriteFrame(resId: R.drawable.coach_67_back_standing, anchorX01: 0.50, ballSourceX: 221.1, ballSourceY: 263.1),
        idleFront: CharacterSpriteFrame(resId: R.drawable.coach_67_front_defense, anchorX01: 0.50, ballSourceX: 290.2, ballSourceY: 230.4),
        shotBack: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_back_mid, anchorX01: 0.50, ballSourceX: 133, ballSourceY: 62, targetHeightDp: 202, ballForegroundRect01: ARectF(0.24, 0.055, 0.76, 0.18)),
            mid: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_back_mid, anchorX01: 0.50, ballSourceX: 133.0, ballSourceY: 68.6, targetHeightDp: 202, ballForegroundRect01: ARectF(0.24, 0.055, 0.76, 0.18)),
            set: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_back_set, anchorX01: 0.50, ballSourceX: 127.7, ballSourceY: 33.2, targetHeightDp: 222, ballForegroundRect01: ARectF(0.24, 0.01, 0.76, 0.115)),
            release: CharacterSpriteFrame(resId: R.drawable.coach_67_back_after_throw, anchorX01: 0.50)
        ),
        shotSide: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_side_low, anchorX01: 0.50, ballSourceX: 227.2, ballSourceY: 219.8, targetHeightDp: 204),
            mid: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_side_mid, anchorX01: 0.50, ballSourceX: 243.7, ballSourceY: 130.1, targetHeightDp: 210, ballForegroundRect01: ARectF(0.65, 0.18, 0.99, 0.36)),
            set: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_side_set, anchorX01: 0.50, ballSourceX: 227.7, ballSourceY: 56.9, targetHeightDp: 213, ballForegroundRect01: ARectF(0.63, 0.04, 0.99, 0.23)),
            release: CharacterSpriteFrame(resId: R.drawable.coach_67_front_throw, anchorX01: 0.50)
        ),
        shotFront: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_front_low, anchorX01: 0.50, ballSourceX: 163.2, ballSourceY: 200.7, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_front_mid, anchorX01: 0.50, ballSourceX: 131.2, ballSourceY: 107.5, targetHeightDp: 208, ballForegroundRect01: ARectF(0.25, 0.16, 0.75, 0.33)),
            set: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_front_set, anchorX01: 0.50, ballSourceX: 130.0, ballSourceY: 36.5, targetHeightDp: 224, ballForegroundRect01: ARectF(0.25, 0.01, 0.75, 0.13)),
            release: CharacterSpriteFrame(resId: R.drawable.coach_67_front_throw, anchorX01: 0.50)
        ),
        steal: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.coach_67_steal_back, anchorX01: 0.50, targetHeightDp: 198),
            side: CharacterSpriteFrame(resId: R.drawable.coach_67_steal_side, anchorX01: 0.50, targetHeightDp: 157),
            front: CharacterSpriteFrame(resId: R.drawable.coach_67_steal_front, anchorX01: 0.50, anchorY01: 0.98, targetHeightDp: 151)
        ),
        block: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.coach_67_block_back, anchorX01: 0.50, targetHeightDp: 228),
            side: CharacterSpriteFrame(resId: R.drawable.coach_67_block_side, anchorX01: 0.50, targetHeightDp: 228),
            front: CharacterSpriteFrame(resId: R.drawable.coach_67_block_front, anchorX01: 0.50, targetHeightDp: 213)
        ),
        rebound: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.coach_67_rebound_back, anchorX01: 0.50, targetHeightDp: 229),
            side: CharacterSpriteFrame(resId: R.drawable.coach_67_rebound_side, anchorX01: 0.50, targetHeightDp: 228),
            front: CharacterSpriteFrame(resId: R.drawable.coach_67_rebound_front, anchorX01: 0.50, targetHeightDp: 230)
        ),
        dunks: [
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_back_one_hand, anchorX01: 0.50, ballSourceX: 254.6, ballSourceY: 33.5, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.94, weight: 1.20,
                contactLiftDp: 6, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_back_two_hand_power, anchorX01: 0.50, ballSourceX: 189.3, ballSourceY: 28.6, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 18, contactOutwardDp: 2, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_back_two_hand_hang, anchorX01: 0.50, ballSourceX: 224.7, ballSourceY: 21.0, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.76, weight: 0.92,
                contactLiftDp: 20, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_front_two_hand_power, anchorX01: 0.50, ballSourceX: 174.7, ballSourceY: 26.6, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 5, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_front_two_hand_hang, anchorX01: 0.50, ballSourceX: 165.0, ballSourceY: 20.4, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.75, weight: 0.92,
                contactLiftDp: 14, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_front_statue, anchorX01: 0.50, ballSourceX: 277.7, ballSourceY: 38.5, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.96, weight: 1.18,
                contactLiftDp: 6, contactOutwardDp: 2, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_side_two_hand_gather, anchorX01: 0.50, ballSourceX: 244.1, ballSourceY: 34.1, targetHeightDp: 226),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.72, weight: 0.88,
                contactLiftDp: 18, contactOutwardDp: 12, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_side_reverse_gather, anchorX01: 0.50, ballSourceX: 222.4, ballSourceY: 61.9, targetHeightDp: 228),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.80, weight: 0.90,
                contactLiftDp: 22, contactOutwardDp: 15, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_side_two_hand_hang, anchorX01: 0.50, ballSourceX: 230.3, ballSourceY: 26.0, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.86, weight: 1.05,
                contactLiftDp: 19, contactOutwardDp: 13, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.coach_67_dunk_side_statue, anchorX01: 0.50, ballSourceX: 291.7, ballSourceY: 36.8, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.98, weight: 1.22,
                contactLiftDp: 7, contactOutwardDp: 4, playerInFrontOfHoop: false
            )
        ],
        winner: CharacterSpriteFrame(resId: R.drawable.coach_67_front_celebrate, anchorX01: 0.50),
        loser: CharacterSpriteFrame(resId: R.drawable.coach_67_front_sitting_sad, anchorX01: 0.50),
        spectator: CharacterSpriteFrame(resId: R.drawable.coach_67_front_sitting, anchorX01: 0.50),
        // Kotlin passes it first (named): the frame expression has no side effects.
        playfulHold: CharacterSpriteFrame(resId: R.drawable.coach_67_shot_back_low, ballSourceX: 163.8, ballSourceY: 173.4, targetHeightDp: 181)
    )

    static let zephyr = CharacterSpriteSet(
        characterId: TripleShotCharacterRoster.ID_ZEPHYR,
        referenceHeightPx: 322,
        referenceHeightDp: 200,
        idleBack: CharacterSpriteFrame(resId: R.drawable.zephyr_back_standing, anchorX01: 0.50, ballSourceX: 310.5, ballSourceY: 178.8),
        idleFront: CharacterSpriteFrame(resId: R.drawable.zephyr_front_defense, anchorX01: 0.50, ballSourceX: 305.5, ballSourceY: 199.3),
        shotBack: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_back_low, anchorX01: 0.50, ballSourceX: 172.8, ballSourceY: 155.3, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_back_mid, anchorX01: 0.50, ballSourceX: 166.5, ballSourceY: 49.6, targetHeightDp: 181),
            set: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_back_set, anchorX01: 0.50, ballSourceX: 168.3, ballSourceY: 26.2, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.zephyr_back_after_throw, anchorX01: 0.50)
        ),
        shotSide: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_side_low, anchorX01: 0.50, ballSourceX: 254.6, ballSourceY: 155.3, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_side_mid, anchorX01: 0.50, ballSourceX: 233.7, ballSourceY: 97.1, targetHeightDp: 186),
            set: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_side_set, anchorX01: 0.50, ballSourceX: 251.1, ballSourceY: 43.7, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.zephyr_front_throw, anchorX01: 0.50)
        ),
        shotFront: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_front_low, anchorX01: 0.50, ballSourceX: 178.8, ballSourceY: 165.8, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_front_mid, anchorX01: 0.50, ballSourceX: 149.8, ballSourceY: 90.5, targetHeightDp: 188),
            set: CharacterSpriteFrame(resId: R.drawable.zephyr_shot_front_set, anchorX01: 0.50, ballSourceX: 168.5, ballSourceY: 25.6, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.zephyr_front_throw, anchorX01: 0.50)
        ),
        steal: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.zephyr_steal_back, anchorX01: 0.50, targetHeightDp: 178),
            side: CharacterSpriteFrame(resId: R.drawable.zephyr_steal_side, anchorX01: 0.50, targetHeightDp: 153),
            front: CharacterSpriteFrame(resId: R.drawable.zephyr_steal_front, anchorX01: 0.50, anchorY01: 1.11, targetHeightDp: 110)
        ),
        block: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.zephyr_block_back, anchorX01: 0.50, targetHeightDp: 203),
            side: CharacterSpriteFrame(resId: R.drawable.zephyr_block_side, anchorX01: 0.50, targetHeightDp: 208),
            front: CharacterSpriteFrame(resId: R.drawable.zephyr_block_front, anchorX01: 0.50, targetHeightDp: 170)
        ),
        rebound: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.zephyr_rebound_back, anchorX01: 0.50, targetHeightDp: 169),
            side: CharacterSpriteFrame(resId: R.drawable.zephyr_rebound_side, anchorX01: 0.50, targetHeightDp: 206),
            front: CharacterSpriteFrame(resId: R.drawable.zephyr_rebound_front, anchorX01: 0.50, targetHeightDp: 183)
        ),
        dunks: [
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_back_one_hand, anchorX01: 0.50, ballSourceX: 234.8, ballSourceY: 21.8, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.94, weight: 1.20,
                contactLiftDp: 6, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_back_two_hand_power, anchorX01: 0.50, ballSourceX: 239.5, ballSourceY: 21.9, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 18, contactOutwardDp: 2, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_back_two_hand_hang, anchorX01: 0.50, ballSourceX: 250.1, ballSourceY: 18.3, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.76, weight: 0.92,
                contactLiftDp: 20, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_front_two_hand_power, anchorX01: 0.50, ballSourceX: 235.2, ballSourceY: 21.0, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 5, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_front_two_hand_hang, anchorX01: 0.50, ballSourceX: 194.4, ballSourceY: 18.0, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.75, weight: 0.92,
                contactLiftDp: 14, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_front_statue, anchorX01: 0.50, ballSourceX: 311.6, ballSourceY: 25.9, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.96, weight: 1.18,
                contactLiftDp: 6, contactOutwardDp: 2, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_side_two_hand_gather, anchorX01: 0.50, ballSourceX: 252.7, ballSourceY: 25.9, targetHeightDp: 226),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.72, weight: 0.88,
                contactLiftDp: 18, contactOutwardDp: 12, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_side_reverse_gather, anchorX01: 0.50, ballSourceX: 247.8, ballSourceY: 47.1, targetHeightDp: 228),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.80, weight: 0.90,
                contactLiftDp: 22, contactOutwardDp: 15, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_side_two_hand_hang, anchorX01: 0.50, ballSourceX: 194.7, ballSourceY: 20.1, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.86, weight: 1.05,
                contactLiftDp: 19, contactOutwardDp: 13, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.zephyr_dunk_side_statue, anchorX01: 0.50, ballSourceX: 280.9, ballSourceY: 25.1, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.98, weight: 1.22,
                contactLiftDp: 7, contactOutwardDp: 4, playerInFrontOfHoop: false
            )
        ],
        winner: CharacterSpriteFrame(resId: R.drawable.zephyr_front_celebrate, anchorX01: 0.50),
        loser: CharacterSpriteFrame(resId: R.drawable.zephyr_front_sitting_sad, anchorX01: 0.50),
        spectator: CharacterSpriteFrame(resId: R.drawable.zephyr_front_sitting, anchorX01: 0.50)
    )

    static let flare = CharacterSpriteSet(
        characterId: TripleShotCharacterRoster.ID_FLARE,
        referenceHeightPx: 352,
        referenceHeightDp: 200,
        idleBack: CharacterSpriteFrame(resId: R.drawable.flare_back_standing, anchorX01: 0.50, ballSourceX: 194.6, ballSourceY: 204.3),
        idleFront: CharacterSpriteFrame(resId: R.drawable.flare_front_defense, anchorX01: 0.50, ballSourceX: 255.2, ballSourceY: 175.3),
        shotBack: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.flare_shot_back_low, anchorX01: 0.50, ballSourceX: 132.7, ballSourceY: 130.3, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.flare_shot_back_mid, anchorX01: 0.50, ballSourceX: 120.5, ballSourceY: 54.9, targetHeightDp: 181),
            set: CharacterSpriteFrame(resId: R.drawable.flare_shot_back_set, anchorX01: 0.50, ballSourceX: 100.2, ballSourceY: 24.5, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.flare_back_after_throw, anchorX01: 0.50)
        ),
        shotSide: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.flare_shot_side_low, anchorX01: 0.50, ballSourceX: 194.8, ballSourceY: 149.4, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.flare_shot_side_mid, anchorX01: 0.50, ballSourceX: 167.9, ballSourceY: 92.0, targetHeightDp: 186),
            set: CharacterSpriteFrame(resId: R.drawable.flare_shot_side_set, anchorX01: 0.50, ballSourceX: 135.6, ballSourceY: 42.0, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.flare_front_throw, anchorX01: 0.50)
        ),
        shotFront: CharacterShotSprites(
            low: CharacterSpriteFrame(resId: R.drawable.flare_shot_front_low, anchorX01: 0.50, ballSourceX: 137.7, ballSourceY: 148.3, targetHeightDp: 181),
            mid: CharacterSpriteFrame(resId: R.drawable.flare_shot_front_mid, anchorX01: 0.50, ballSourceX: 124.7, ballSourceY: 75.4, targetHeightDp: 188),
            set: CharacterSpriteFrame(resId: R.drawable.flare_shot_front_set, anchorX01: 0.50, ballSourceX: 111.5, ballSourceY: 26.9, targetHeightDp: 200),
            release: CharacterSpriteFrame(resId: R.drawable.flare_front_throw, anchorX01: 0.50)
        ),
        steal: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.flare_steal_back, anchorX01: 0.50, targetHeightDp: 178),
            side: CharacterSpriteFrame(resId: R.drawable.flare_steal_side, anchorX01: 0.50, targetHeightDp: 153),
            front: CharacterSpriteFrame(resId: R.drawable.flare_steal_front, anchorX01: 0.50, anchorY01: 1.11, targetHeightDp: 110)
        ),
        block: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.flare_block_back, anchorX01: 0.50, targetHeightDp: 203),
            side: CharacterSpriteFrame(resId: R.drawable.flare_block_side, anchorX01: 0.50, targetHeightDp: 208),
            front: CharacterSpriteFrame(resId: R.drawable.flare_block_front, anchorX01: 0.50, targetHeightDp: 170)
        ),
        rebound: CharacterDirectionalActionSprites(
            back: CharacterSpriteFrame(resId: R.drawable.flare_rebound_back, anchorX01: 0.50, targetHeightDp: 169),
            side: CharacterSpriteFrame(resId: R.drawable.flare_rebound_side, anchorX01: 0.50, targetHeightDp: 206),
            front: CharacterSpriteFrame(resId: R.drawable.flare_rebound_front, anchorX01: 0.50, targetHeightDp: 183)
        ),
        dunks: [
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_back_one_hand, anchorX01: 0.50, ballSourceX: 307.2, ballSourceY: 27.3, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.94, weight: 1.20,
                contactLiftDp: 6, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_back_two_hand_power, anchorX01: 0.50, ballSourceX: 198.3, ballSourceY: 30.1, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 18, contactOutwardDp: 2, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_back_two_hand_hang, anchorX01: 0.50, ballSourceX: 269.2, ballSourceY: 24.1, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.BACK,
                preferredSpeed01: 0.76, weight: 0.92,
                contactLiftDp: 20, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_front_two_hand_power, anchorX01: 0.50, ballSourceX: 183.0, ballSourceY: 31.3, targetHeightDp: 230),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.84, weight: 1.05,
                contactLiftDp: 5, contactOutwardDp: 0, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_front_two_hand_hang, anchorX01: 0.50, ballSourceX: 162.0, ballSourceY: 24.8, targetHeightDp: 234),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.75, weight: 0.92,
                contactLiftDp: 14, contactOutwardDp: 4, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_front_statue, anchorX01: 0.50, ballSourceX: 334.9, ballSourceY: 33.8, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.FRONT,
                preferredSpeed01: 0.96, weight: 1.18,
                contactLiftDp: 6, contactOutwardDp: 2, playerInFrontOfHoop: false
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_side_two_hand_gather, anchorX01: 0.50, ballSourceX: 329.9, ballSourceY: 45.7, targetHeightDp: 226),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.72, weight: 0.88,
                contactLiftDp: 18, contactOutwardDp: 12, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_side_reverse_gather, anchorX01: 0.50, ballSourceX: 291.3, ballSourceY: 66.8, targetHeightDp: 228),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.80, weight: 0.90,
                contactLiftDp: 22, contactOutwardDp: 15, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_side_two_hand_hang, anchorX01: 0.50, ballSourceX: 256.1, ballSourceY: 34.1, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.86, weight: 1.05,
                contactLiftDp: 19, contactOutwardDp: 13, playerInFrontOfHoop: true
            ),
            CharacterDunkSprite(
                frame: CharacterSpriteFrame(resId: R.drawable.flare_dunk_side_statue, anchorX01: 0.50, ballSourceX: 352.7, ballSourceY: 48.6, targetHeightDp: 232),
                facing: TripleShotPlayerRenderer.Facing.SIDE,
                preferredSpeed01: 0.98, weight: 1.22,
                contactLiftDp: 7, contactOutwardDp: 4, playerInFrontOfHoop: false
            )
        ],
        winner: CharacterSpriteFrame(resId: R.drawable.flare_front_celebrate, anchorX01: 0.50),
        loser: CharacterSpriteFrame(resId: R.drawable.flare_front_sitting_sad, anchorX01: 0.50),
        spectator: CharacterSpriteFrame(resId: R.drawable.flare_front_sitting, anchorX01: 0.50)
    )

    private static let previewDrawables: [String: ADrawableRes] = [
        TripleShotCharacterRoster.ID_BOB: R.drawable.character_preview_bob,
        TripleShotCharacterRoster.ID_WOMAN_DARK: R.drawable.woman_dark_front_defense,
        TripleShotCharacterRoster.ID_ROOZA: R.drawable.character_preview_rooza,
        TripleShotCharacterRoster.ID_NOVA: R.drawable.character_preview_nova,
        TripleShotCharacterRoster.ID_UNICORN_32: R.drawable.character_preview_unicorn_32,
        TripleShotCharacterRoster.ID_COACH_67: R.drawable.character_preview_coach_67,
        TripleShotCharacterRoster.ID_KYRA: R.drawable.character_preview_kyra,
        TripleShotCharacterRoster.ID_ZEPHYR: R.drawable.character_preview_zephyr,
        TripleShotCharacterRoster.ID_FLARE: R.drawable.character_preview_flare,
        TripleShotCharacterRoster.ID_ACE_23: R.drawable.character_preview_ace_23,
        TripleShotCharacterRoster.ID_BUDDY_23: R.drawable.character_preview_buddy_23
    ]

    static func previewResId(characterId: String?) -> ADrawableRes? {
        if let resId = find(characterId: characterId)?.idleFront.resId {
            return resId
        }
        guard let characterId = characterId else { return nil }
        return previewDrawables[characterId]
    }

    /// Kotlin `mapOf(...)`: insertion-ordered (`playableCharacterIds()` lists the keys in this order).
    private static let sets: KLinkedMap<String, CharacterSpriteSet> = KLinkedMap([
        (womanDark.characterId, womanDark),
        (miaEssenceSkies.characterId, miaEssenceSkies),
        (coach67.characterId, coach67),
        (zephyr.characterId, zephyr),
        (flare.characterId, flare)
    ])

    /// Kotlin `by lazy { sets.mapValues { BasketballFeedbackArt.folded(BasketballSpriteCompletion.enrich(it.value)) } }`.
    private static let completedSets: [String: CharacterSpriteSet] = {
        var completed: [String: CharacterSpriteSet] = [:]
        for entry in sets.entries {
            completed[entry.key] = BasketballFeedbackArt.folded(old: BasketballSpriteCompletion.enrich(old: entry.value))
        }
        return completed
    }()

    /// The Kotlin `find` body for one non-null id:
    /// `if (it == "kyra_original") BasketballFeedbackArt.kyra else completedSets[it]
    ///  ?: BasketballSpriteCompletion.find(it)?.let(BasketballFeedbackArt::folded)`.
    private static func compose(_ it: String) -> CharacterSpriteSet? {
        if it == "kyra_original" {
            return BasketballFeedbackArt.kyra
        }
        if let completed = completedSets[it] {
            return completed
        }
        return BasketballSpriteCompletion.find(id: it).map { BasketballFeedbackArt.folded(old: $0) }
    }

    /// Every set the Kotlin `find` can return, composed once. That expression yields a set only for
    /// "kyra_original", the `sets` keys and the BasketballSpriteCompletion pack ids; every other id gives null
    /// there and is absent here.
    private static let resolvedSets: [String: CharacterSpriteSet] = {
        var resolved: [String: CharacterSpriteSet] = [:]
        for id in ["kyra_original"] + sets.keys + BasketballSpriteCompletion.packIds where resolved[id] == nil {
            if let set = compose(id) {
                resolved[id] = set
            }
        }
        return resolved
    }()

    static func find(characterId: String?) -> CharacterSpriteSet? {
        guard let characterId = characterId else { return nil }
        return resolvedSets[characterId]
    }

    static func hasVisuals(characterId: String?) -> Bool {
        return find(characterId: characterId) != nil
    }

    /// Unused in the app (as on Android). Kotlin `sets.keys + setOf(...)` is a LinkedHashSet in this order.
    static func playableCharacterIds() -> KLinkedSet<String> {
        return KLinkedSet(sets.keys + ["kyra_original", "bob", "rooza", "unicorn_32", "kyra", "ace_23", "buddy_23"])
    }

    // Kotlin positional call forms.
    static func previewResId(_ characterId: String?) -> ADrawableRes? { return previewResId(characterId: characterId) }
    static func find(_ characterId: String?) -> CharacterSpriteSet? { return find(characterId: characterId) }
    static func hasVisuals(_ characterId: String?) -> Bool { return hasVisuals(characterId: characterId) }
}
