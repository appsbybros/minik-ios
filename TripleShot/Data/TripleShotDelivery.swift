import Foundation

// Port of data/TripleShotDelivery.kt (TripleShotGame dd722e5): the members a RELEASE build reads. Spec 04 §2.3.
//
// The release BuildConfig comes from `qeDelivery("production", gradleProperty("qePracticeNodes") ?: "")`
// (app/build.gradle.kts:19-30, 70-73): QE_BUNDLE = false (no signed bundle), QE_EDGE_ORIGIN = "" (origin of
// questionenginelib config/edge/production.json), QE_PRACTICE_NODES = "". So `enabled` is false: the Home
// "Cloud practice" button stays GONE and CloudPracticeActivity can never start.
//
// Not ported (debug/QA only, DESIGN 3): `practiceNodes`, `defaultMode` (questionenginelib delivery DeliveryMode),
// the `io` executor, `get(context, mode)` (whose first statement is `check(enabled)`), `locale(context)` and
// `token(forceRefresh)`; their only caller is CloudPracticeActivity, which is not ported either.

/**
 * Shared QuestionEngine delivery for TripleShot, one client API in three modes:
 *  - BUNDLED: the signed corpus shipped in assets/questionengine; no server at all;
 *  - REMOTE: the edge channel (origin + pinned public keys fixed at build time from
 *    questionenginelib/config/edge/<channel>.json); identity is the app's anonymous Firebase user;
 *  - COMBINED: bundled questions work offline from first launch, more come from the server.
 * The build decides the default (bundle and/or origin present); debug automation may force a mode.
 * Rounds are prepared ahead of play; answering and explanations are local.
 */
enum TripleShotDelivery {
    /// The generated BuildConfig fields of the release build type.
    private enum BuildConfig {
        static let QE_BUNDLE = false
        static let QE_EDGE_ORIGIN = ""
        static let QE_PRACTICE_NODES = ""
    }

    static var hasBundle: Bool { return BuildConfig.QE_BUNDLE }
    static var hasRemote: Bool { return !BuildConfig.QE_EDGE_ORIGIN.isEmpty }
    static var enabled: Bool { return (hasBundle || hasRemote) && !BuildConfig.QE_PRACTICE_NODES.isEmpty }
}
