import UIKit
import XCTest
@testable import MinikTripleShot

/// The app as project.yml builds it (spec 23): the bundle identity, the generated Info.plist (the Android manifest's
/// label, orientations and the family catalogue key), the window-scene manifest, Android's res/ and assets/ as one
/// folder reference, the privacy manifest, the app icon, the family catalogue entry and, once the owner adds it,
/// the Firebase registration. Hosted in the app, so Bundle.main is the app bundle.
final class IntegrationTests: XCTestCase {

    /// The built Info.plist as the bundle stores it (device-specific keys such as "~ipad" kept as written).
    private func rawInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testHostIsTheTripleShotApp() throws {
        let info = try rawInfoPlist()
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.appsbybros.minik.swish")
        // Android's applicationId, which the resource and intent code also uses.
        XCTAssertEqual(Bundle.main.bundleIdentifier, AResources.packageName)
        // PRODUCT_NAME equals the scheme name: the TestFlight workflow archives "$SCHEME.app".
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "MinikTripleShot")
        XCTAssertEqual(Bundle.main.bundleURL.lastPathComponent, "MinikTripleShot.app")
    }

    func testInfoPlistFollowsTheAndroidManifest() throws {
        let info = try rawInfoPlist()
        // android:label="Triple Shot", the same in every language.
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Triple Shot")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, TripleShotApp.label)
        // res/values (the default resources) is Hebrew, res/values-en English.
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "he")
        XCTAssertEqual(info["CFBundleLocalizations"] as? [String], ["he", "en"])
        XCTAssertEqual(info["MinikFamilyCatalogKey"] as? String, "tripleshot")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertNotNil(info["UILaunchScreen"] as? [String: Any])
        // Portrait pages, landscape-capable games: every orientation a screen can ask for, full screen on iPad.
        XCTAssertEqual(info["UIRequiresFullScreen"] as? Bool, true)
        XCTAssertEqual(info["UISupportedInterfaceOrientations"] as? [String],
                       ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft",
                        "UIInterfaceOrientationLandscapeRight"])
        XCTAssertEqual(info["UISupportedInterfaceOrientations~ipad"] as? [String],
                       ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"])
        // The versions come from the build settings (MINIK_MARKETING_VERSION / MINIK_BUILD_NUMBER).
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let value = info[key] as? String ?? ""
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertFalse(value.contains("$("), key)
        }
    }

    @MainActor
    func testOneWindowSceneWithTheTripleShotSceneDelegate() throws {
        let info = try rawInfoPlist()
        let manifest = try XCTUnwrap(info["UIApplicationSceneManifest"] as? [String: Any])
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
        let roles = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
        let configurations = try XCTUnwrap(roles["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
        XCTAssertEqual(configurations.count, 1)
        XCTAssertEqual(configurations.first?["UISceneConfigurationName"] as? String, "Default Configuration")
        let className = try XCTUnwrap(configurations.first?["UISceneDelegateClassName"] as? String)
        XCTAssertEqual(className, "MinikTripleShot.TripleShotSceneDelegate")
        XCTAssertTrue(NSClassFromString(className) == TripleShotSceneDelegate.self)
        XCTAssertTrue(TripleShotApp.usesScenes)
        for scene in UIApplication.shared.connectedScenes {
            XCTAssertTrue(scene.delegate is TripleShotSceneDelegate)
        }
    }

    func testAndroidResourcesAreOneFolderReference() throws {
        let res = Bundle.main.bundleURL.appendingPathComponent("Res", isDirectory: true)
        XCTAssertEqual(AResources.resURL.standardizedFileURL.path, res.standardizedFileURL.path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: res.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        for path in ["strings/he.json", "strings/en.json", "strings/android.json", "drawable-sizes.json",
                     "raw/basket_bounce.wav", "raw/basket_catch.wav", "raw/basket_swish.wav",
                     "assets/question_banks/arithmetic.xml", "assets/question_banks/en/arithmetic.xml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: res.appendingPathComponent(path).path), path)
        }
        // The Hebrew and English banks share file names; a group would have flattened them into one file.
        let hebrew = try Data(contentsOf: res.appendingPathComponent("assets/question_banks/arithmetic.xml"))
        let english = try Data(contentsOf: res.appendingPathComponent("assets/question_banks/en/arithmetic.xml"))
        XCTAssertNotEqual(hebrew, english)
        // Nothing of TripleShot/Res is copied flat into the bundle root.
        XCTAssertNil(Bundle.main.url(forResource: "arithmetic", withExtension: "xml"))
        XCTAssertNil(Bundle.main.url(forResource: "drawable-sizes", withExtension: "json"))
        XCTAssertNil(Bundle.main.url(forResource: "he", withExtension: "json"))
        XCTAssertNil(Bundle.main.url(forResource: "basket_swish", withExtension: "wav"))
        // R.swift is compiled: its ids are the Android names.
        XCTAssertEqual(R.string.app_name, "app_name")
    }

    func testPrivacyManifestIsBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        var reasons: [String: [String]] = [:]
        for entry in manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [] {
            reasons[entry["NSPrivacyAccessedAPIType"] as? String ?? ""] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
        }
        // APrefs (UserDefaults) and the uptime clocks (ASystem.nanoTime, ProcessInfo.systemUptime).
        XCTAssertEqual(reasons, ["NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                                 "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]])
        // Online play: the anonymous uid and the nickname (user ID); rooms, scores, streaks, answers (gameplay).
        let collected = (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
        XCTAssertEqual(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String },
                       ["NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeGameplayContent"])
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }

    func testAppIconIsTheCompiledAppIconSet() throws {
        let info = try rawInfoPlist()
        let icons = try XCTUnwrap(info["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
    }

    func testFamilyCatalogueKnowsThisApp() throws {
        let info = try rawInfoPlist()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "minik-family-catalog", withExtension: "json"))
        let catalogue = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let apps = try XCTUnwrap(catalogue["apps"] as? [String: Any])
        let key = try XCTUnwrap(info["MinikFamilyCatalogKey"] as? String)
        // The "More Minik apps & games" card leaves out the entry of the host app (Android: by package).
        let entry = try XCTUnwrap(apps[key] as? [String: Any])
        XCTAssertEqual(entry["applicationId"] as? String, Bundle.main.bundleIdentifier)
        // Family/FamilyArt.xcassets compiles into the same asset catalogue as TripleShot/Assets.xcassets.
        XCTAssertNotNil(UIImage(named: "family-tripleshot-en"))
        XCTAssertNotNil(UIImage(named: "family-tripleshot-he"))
    }

    func testFirebaseRegistrationIsMissingOrThisApps() throws {
        // Until the owner registers the iOS app in minikswish (spec 23 9.2) there is no plist and play is offline.
        guard let url = Bundle.main.url(forResource: AFirebaseApp.OPTIONS_RESOURCE, withExtension: "plist") else {
            return
        }
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["BUNDLE_ID"] as? String, Bundle.main.bundleIdentifier)
        XCTAssertEqual(plist["PROJECT_ID"] as? String, AFirebaseApp.PROJECT_ID)
        if let databaseURL = plist["DATABASE_URL"] as? String {
            XCTAssertEqual(AFirebaseApp.trimmedURL(databaseURL), AFirebaseApp.DATABASE_URL)
        }
    }
}
