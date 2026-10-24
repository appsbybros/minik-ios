import Foundation

/// Port of `TripleShotDemoActivity.kt` (Android snapshot dd722e5), statement by statement (spec 18 §3.1, §4.1, §4.12).
///
/// The only launcher activity. Its manifest entry (portrait, `configChanges="orientation|screenSize|
/// smallestScreenSize|screenLayout|keyboardHidden"`, so rotation never recreates it) is registered by
/// `App/TripleShotApp.swift`, which also creates this class as the MAIN/LAUNCHER activity.
/// `AppCompatActivity(R.layout.activity_triple_shot_demo)` is `AActivity(contentLayoutId:)`: the default `onCreate`
/// inflates the layout (one FrameLayout `tripleShotDemoContainer`, match_parent), built in code by
/// `TripleShotDemoLayout` and registered with ALayoutInflater. `onCreate` then installs the two window-wide restylers
/// (`FamilySkyUi.watch`, `TripleShotControls.watch`, family first, like the Android listener order) on the decor view,
/// so every screen hosted here is re-skinned like on Android, and adds the navigator `TripleShotHostFragment`.
///
/// Not ported (DESIGN 3, spec 18 §8.11): the debug-only `qaCapture` / `language` locale override of L11-16
/// (`BuildConfig.DEBUG && intent.getBooleanExtra("qaCapture", false)`). `savedInstanceState` is always null on iOS
/// (an activity is never recreated), so the host fragment is always added.
final class TripleShotDemoActivity: AActivity {

    /// Registers the Swift builder of `R.layout.activity_triple_shot_demo` once (ALayoutInflater).
    private static let layoutRegistration: Void = {
        ALayoutInflater.register(R.layout.activity_triple_shot_demo) { _ in
            TripleShotDemoLayout.build()
        }
    }()

    /// Kotlin `TripleShotDemoActivity : AppCompatActivity(R.layout.activity_triple_shot_demo)` (also what the launcher,
    /// `TripleShotApp.makeLauncherActivity`, and `startActivity` instantiate).
    required convenience init() {
        _ = TripleShotDemoActivity.layoutRegistration
        self.init(contentLayoutId: R.layout.activity_triple_shot_demo)
    }

    override func onCreate(_ savedInstanceState: ABundle?) {
        // L11-16 (debug-only qaCapture locale override): not ported.
        super.onCreate(savedInstanceState)
        // App Store captures only (TripleShotScreenshot; inert for normal launches): stage the capture's settings.
        TripleShotScreenshot.prepare(activity: self)
        FamilySkyUi.watch(root: window.decorView)
        TripleShotControls.watch(root: window.decorView)
        if savedInstanceState == nil {
            supportFragmentManager.beginTransaction()
                .replace(R.id.tripleShotDemoContainer, TripleShotHostFragment())
                .commit()
        }
        // App Store captures only: open the requested scene once Home is showing.
        TripleShotScreenshot.start(activity: self)
    }

    override func onConfigurationChanged(_ newConfig: AConfiguration) {
        super.onConfigurationChanged(newConfig)
        (supportFragmentManager.findFragmentById(R.id.tripleShotDemoContainer) as? TripleShotHostFragment)?
            .onDeviceConfigurationChanged(newConfig: newConfig)
    }
}

/// `res/layout/activity_triple_shot_demo.xml` built in code (same id, attributes and params as the XML).
enum TripleShotDemoLayout {
    static func build() -> AView {
        // <FrameLayout @+id/tripleShotDemoContainer match_parent x match_parent />
        let container = AFrameLayout()
        container.viewId = R.id.tripleShotDemoContainer
        container.layoutParams = AViewGroup.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.MATCH_PARENT
        )
        return container
    }
}
