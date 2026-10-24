import Foundation

/// Port of `ui/GameplayInsets.kt` (Android snapshot dd722e5), statement by statement.
///
/// Keep legacy gameplay HUDs outside system bars, including Android 15 edge-to-edge.
/// (Kotlin `internal fun applyGameplayInsets(root: View, window: Window)`: white status-bar icons; `root` padded by its
/// original padding plus the system-bar and display-cutout insets on every edge, insets returned unconsumed.)
func applyGameplayInsets(root: AView, window: AWindow) {
    AWindowCompat.getInsetsController(window, root).isAppearanceLightStatusBars = false
    let left = root.paddingLeft
    let top = root.paddingTop
    let right = root.paddingRight
    let bottom = root.paddingBottom
    AViewCompat.setOnApplyWindowInsetsListener(root) { view, insets in
        let safe = insets.getInsets(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout())
        view.setPadding(left + safe.left, top + safe.top, right + safe.right, bottom + safe.bottom)
        return insets
    }
    AViewCompat.requestApplyInsets(root)
}

func applyGameplayInsets(_ root: AView, _ window: AWindow) { applyGameplayInsets(root: root, window: window) }
