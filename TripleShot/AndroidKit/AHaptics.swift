import UIKit

// AndroidKit haptics (DESIGN 4.6): android.view.HapticFeedbackConstants and the effect each constant plays.
//
// The constant -> vibration table is HapticFeedbackVibrationProvider.getVibrationForHapticFeedback (android-15
// framework, the owner's Pixel 6): LONG_PRESS is EFFECT_HEAVY_CLICK, CLOCK_TICK is EFFECT_TEXTURE_TICK, and so on.
// Each predefined Android effect maps to the closest iOS feedback generator:
//   EFFECT_HEAVY_CLICK   -> UIImpactFeedbackGenerator(.heavy)
//   EFFECT_CLICK         -> UIImpactFeedbackGenerator(.medium)
//   EFFECT_TICK          -> UIImpactFeedbackGenerator(.light)
//   EFFECT_TEXTURE_TICK  -> UISelectionFeedbackGenerator (the lightest tick iOS has)
//   EFFECT_DOUBLE_CLICK  -> two .medium impacts 130 ms apart (Android's fallback waveform: 30 ms on, 100 ms off, 30 ms on)
//   PRIMITIVE_TICK(s)    -> UIImpactFeedbackGenerator(.light) at intensity s
//   PRIMITIVE_LOW_TICK(s)-> UIImpactFeedbackGenerator(.soft) at intensity s
// iOS applies the user's system haptics setting itself (Android's global "touch feedback" setting).
// The app uses LONG_PRESS (1v1 possession, game screen) and CLOCK_TICK (game screen). The constants themselves
// (AHapticFeedbackConstants) are declared with AView in AView.swift.

/// The vibration of a haptic feedback constant and its iOS playback (used by AView.performHapticFeedback).
enum AHaptics {
    /// android.os.VibrationEffect kinds the haptic feedback table uses.
    enum Effect: Equatable {
        case click
        case heavyClick
        case tick
        case textureTick
        case doubleClick
        /// VibrationEffect.Composition.PRIMITIVE_TICK at the given scale.
        case primitiveTick(Float)
        /// VibrationEffect.Composition.PRIMITIVE_LOW_TICK at the given scale.
        case primitiveLowTick(Float)
    }

    /// config_enableHapticTextHandle (AOSP default false): TEXT_HANDLE_MOVE plays nothing.
    static let hapticTextHandleEnabled = false

    /// HapticFeedbackVibrationProvider.getVibrationForHapticFeedback: nil = no vibration.
    static func effect(_ feedbackConstant: Int) -> Effect? {
        // HapticFeedbackConstants values (android-36); AHapticFeedbackConstants (AView.swift) names most of them.
        switch feedbackConstant {
        case 6, 13, 23, 18, 26:
            // CONTEXT_CLICK, GESTURE_END, GESTURE_THRESHOLD_ACTIVATE, SCROLL_TICK, SEGMENT_TICK
            return .tick
        case 9:
            // TEXT_HANDLE_MOVE (config_enableHapticTextHandle), then as CLOCK_TICK
            return hapticTextHandleEnabled ? .textureTick : nil
        case 4, 27:
            // CLOCK_TICK, SEGMENT_FREQUENT_TICK
            return .textureTick
        case 7:
            // KEYBOARD_RELEASE (keyboard vibration: EFFECT_TICK)
            return .tick
        case 3:
            // KEYBOARD_TAP == KEYBOARD_PRESS (keyboard vibration: EFFECT_CLICK)
            return .click
        case 8, 11:
            // VIRTUAL_KEY_RELEASE, DRAG_CROSSING
            return .tick
        case 1, 15, 5, 16, 12, 19, 20:
            // VIRTUAL_KEY, EDGE_RELEASE, CALENDAR_DATE, CONFIRM, GESTURE_START, SCROLL_ITEM_FOCUS, SCROLL_LIMIT
            return .click
        case 0, 25, 14:
            // LONG_PRESS, DRAG_START, EDGE_SQUEEZE
            return .heavyClick
        case 17:
            // REJECT
            return .doubleClick
        case 24:
            // GESTURE_THRESHOLD_DEACTIVATE
            return .primitiveTick(0.4)
        case 21:
            // TOGGLE_ON
            return .primitiveTick(0.5)
        case 22:
            // TOGGLE_OFF
            return .primitiveLowTick(0.2)
        default:
            // NO_HAPTICS (-1) and unknown constants.
            return nil
        }
    }

    /// Plays the feedback of a constant; false when the constant has no vibration (Android performs nothing then).
    @discardableResult
    static func perform(_ feedbackConstant: Int) -> Bool {
        guard let e = effect(feedbackConstant) else { return false }
        play(e)
        return true
    }

    /// Plays one effect now (main thread).
    static func play(_ effect: Effect) {
        switch effect {
        case .click:
            impact(.medium, 1)
        case .heavyClick:
            impact(.heavy, 1)
        case .tick:
            impact(.light, 1)
        case .textureTick:
            let g = selection
            g.selectionChanged()
            g.prepare()
        case .doubleClick:
            impact(.medium, 1)
            _ = AHandler(ALooper.getMainLooper()).postDelayed({ impact(.medium, 1) }, 130)
        case .primitiveTick(let scale):
            impact(.light, CGFloat(scale))
        case .primitiveLowTick(let scale):
            impact(.soft, CGFloat(scale))
        }
    }

    // MARK: - generators (created once, kept prepared like the Android vibrator service)

    nonisolated(unsafe) private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    nonisolated(unsafe) private static var selectionGenerator: UISelectionFeedbackGenerator?

    private static var selection: UISelectionFeedbackGenerator {
        if let g = selectionGenerator { return g }
        let g = UISelectionFeedbackGenerator()
        selectionGenerator = g
        return g
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat) {
        let g: UIImpactFeedbackGenerator
        if let existing = impactGenerators[style] {
            g = existing
        } else {
            g = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = g
        }
        if intensity >= 1 {
            g.impactOccurred()
        } else {
            g.impactOccurred(intensity: max(0, intensity))
        }
        g.prepare()
    }
}
