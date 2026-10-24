import Foundation

// Port of view/TripleShotCourtCatalog.kt (TripleShotGame dd722e5). Spec 01 sections 6.2 and 7.4.

/** Visual-only atmosphere. It must never alter gameplay physics or AI. */
enum TripleShotCourtAtmosphere: String, KotlinEnum {
    case NONE
    case COLORED_LIGHTS
    case LIGHT_SNOW
    case LIGHT_RAIN
}

/**
 * Stable visual court descriptor.
 *
 * Missing future artwork is resolved by name at runtime and safely falls back to the original
 * forest court. This lets the code ship before the final 16:9 artwork exists.
 */
struct TripleShotCourtStyle: Hashable {
    var id: String
    var titleRes: AStringRes
    var subtitleRes: AStringRes
    var landscapeDrawableName: String
    var portraitDrawableName: String?
    var atmosphere: TripleShotCourtAtmosphere = .NONE

    /**
     * `context.resources.getIdentifier(preferred, "drawable", context.packageName)`, falling back to
     * `R.drawable.triple_shot_court_background` when the image is not bundled (Android id 0). Drawable ids are
     * their resource names on iOS (DESIGN 2.7). The context is not needed on iOS; it is accepted (any value,
     * e.g. the activity or a view) so call sites keep the Kotlin shape.
     */
    func resolveBackgroundResId(
        context: Any?,
        orientation: TripleShotGameOrientation
    ) -> ADrawableRes {
        let preferred =
            orientation == TripleShotGameOrientation.LANDSCAPE
                ? landscapeDrawableName
                : (portraitDrawableName ?? landscapeDrawableName)
        let resolved = AResources.getIdentifier(preferred, "drawable")
        return resolved ?? R.drawable.triple_shot_court_background
    }

    /** Positional form (Kotlin `style.resolveBackgroundResId(context, orientation)`). */
    func resolveBackgroundResId(_ context: Any?, _ orientation: TripleShotGameOrientation) -> ADrawableRes {
        return resolveBackgroundResId(context: context, orientation: orientation)
    }

    /** Same as [resolveBackgroundResId] for call sites that have no context to pass. */
    func resolveBackgroundResId(_ orientation: TripleShotGameOrientation) -> ADrawableRes {
        return resolveBackgroundResId(context: nil, orientation: orientation)
    }
}

enum TripleShotCourtCatalog {
    static let DEFAULT_ID = "enchanted_forest"

    static let all: [TripleShotCourtStyle] = [
        TripleShotCourtStyle(
            id: "enchanted_forest",
            titleRes: R.string.minik_swish_court_enchanted_forest,
            subtitleRes: R.string.minik_swish_court_enchanted_forest_desc,
            landscapeDrawableName: "triple_shot_court_enchanted_forest_landscape",
            portraitDrawableName: "triple_shot_court_background"
        ),
        TripleShotCourtStyle(
            id: "sunset_pulse",
            titleRes: R.string.minik_swish_court_sunset_pulse,
            subtitleRes: R.string.minik_swish_court_sunset_pulse_desc,
            landscapeDrawableName: "triple_shot_court_sunset_pulse_landscape",
            portraitDrawableName: "triple_shot_court_sunset_pulse_portrait",
            atmosphere: .COLORED_LIGHTS
        ),
        TripleShotCourtStyle(
            id: "sunset_cove",
            titleRes: R.string.minik_swish_court_sunset_cove,
            subtitleRes: R.string.minik_swish_court_sunset_cove_desc,
            landscapeDrawableName: "triple_shot_court_sunset_cove_landscape",
            portraitDrawableName: nil,
            atmosphere: .COLORED_LIGHTS
        ),
        TripleShotCourtStyle(
            id: "neon_tide",
            titleRes: R.string.minik_swish_court_neon_tide,
            subtitleRes: R.string.minik_swish_court_neon_tide_desc,
            landscapeDrawableName: "triple_shot_court_neon_tide_landscape",
            portraitDrawableName: nil,
            atmosphere: .COLORED_LIGHTS
        ),
        TripleShotCourtStyle(
            id: "neon_falls",
            titleRes: R.string.minik_swish_court_neon_falls,
            subtitleRes: R.string.minik_swish_court_neon_falls_desc,
            landscapeDrawableName: "triple_shot_court_neon_falls_landscape",
            portraitDrawableName: nil,
            atmosphere: .COLORED_LIGHTS
        ),
        TripleShotCourtStyle(
            id: "skyforge_peaks",
            titleRes: R.string.minik_swish_court_skyforge_peaks,
            subtitleRes: R.string.minik_swish_court_skyforge_peaks_desc,
            landscapeDrawableName: "triple_shot_court_skyforge_peaks_landscape",
            portraitDrawableName: "triple_shot_court_skyforge_peaks_portrait"
        ),
        TripleShotCourtStyle(
            id: "frostline",
            titleRes: R.string.minik_swish_court_frostline,
            subtitleRes: R.string.minik_swish_court_frostline_desc,
            landscapeDrawableName: "triple_shot_court_frostline_landscape",
            portraitDrawableName: "triple_shot_court_frostline_portrait",
            atmosphere: .LIGHT_SNOW
        ),
        TripleShotCourtStyle(
            id: "rain_break",
            titleRes: R.string.minik_swish_court_rain_break,
            subtitleRes: R.string.minik_swish_court_rain_break_desc,
            landscapeDrawableName: "triple_shot_court_rain_break_landscape",
            portraitDrawableName: "triple_shot_court_rain_break_portrait",
            atmosphere: .LIGHT_RAIN
        ),
        TripleShotCourtStyle(
            id: "midnight_arena",
            titleRes: R.string.minik_swish_court_midnight_arena,
            subtitleRes: R.string.minik_swish_court_midnight_arena_desc,
            landscapeDrawableName: "triple_shot_court_midnight_arena_landscape",
            portraitDrawableName: "triple_shot_court_midnight_arena_portrait"
        )
    ]

    static func find(id: String?) -> TripleShotCourtStyle {
        return all.first { $0.id == id } ?? all.first { $0.id == DEFAULT_ID }!
    }

    /// Positional form (Kotlin `TripleShotCourtCatalog.find(id)`).
    static func find(_ id: String?) -> TripleShotCourtStyle {
        return find(id: id)
    }
}
