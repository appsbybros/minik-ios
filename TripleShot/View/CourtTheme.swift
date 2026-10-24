import Foundation

// Port of view/CourtTheme.kt (TripleShotGame dd722e5). Spec 01 section 7.5.

/**
 * Source-artwork position used when an eliminated Live HORSE player becomes a spectator.
 * Coordinates are in the same 1024x1536 source-image space used by TripleShotCourtView.
 */
struct SpectatorSpot: Hashable {
    var sourceX: Float
    var sourceY: Float
    var scale: Float = 0.82
}

/** A court theme owns the safe places where eliminated players may sit and watch. */
struct SpectatorArea: Hashable {
    var spots: [SpectatorSpot]
}

/**
 * Small theme descriptor kept separate from game/Firebase state.
 * More court-specific values can be added here later without changing game rules.
 */
struct CourtTheme: Hashable {
    var id: String
    var spectatorArea: SpectatorArea
}

enum CourtThemes {

    /**
     * Current forest court.
     * These three positions intentionally reuse the already-proven source coordinates used
     * by TripleShotCourtView for remote-player idle placement, so this addition does not
     * introduce a second untested coordinate system.
     */
    static let ENCHANTED_FOREST = CourtTheme(
        id: "enchanted_forest",
        spectatorArea: SpectatorArea(
            spots: [
                SpectatorSpot(sourceX: 155, sourceY: 1180),
                SpectatorSpot(sourceX: 520, sourceY: 1260),
                SpectatorSpot(sourceX: 805, sourceY: 1115)
            ]
        )
    )
}
