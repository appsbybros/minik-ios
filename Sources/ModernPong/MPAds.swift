import Foundation
import UIKit
#if canImport(GoogleMobileAds)
@preconcurrency import GoogleMobileAds
#endif

/// Android `AdPolicy`: pure, persisted cadence. No identifiers, network calls or age inference.
struct MPAdPolicy: Codable {
    var total = 0, completed = 0
    var activeMillis: Int64 = 0, lastAd: Int64 = 0, sessionMillis: Int64 = 0, lastActive: Int64 = 0
    var history: [Int64] = [], completedIDs: [String] = []
    var regularLongSession: Bool { history.count >= 5 && history.suffix(5).reduce(0, +) / 5 >= 900_000 }
    mutating func active(_ millis: Int64, now: Int64) {
        guard millis > 0 else { return }
        if lastActive > 0 && now - lastActive >= 1_800_000 && sessionMillis > 0 { history = Array((history + [sessionMillis]).suffix(5)); sessionMillis = 0 }
        let delta = min(millis, 5000); sessionMillis += delta; activeMillis += delta; lastActive = now
    }
    /// Android `AdPolicy.complete`: each real match counts once; malformed identifiers never count.
    mutating func completion(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 200, !id.contains(","), !completedIDs.contains(id) else { return false }
        completedIDs = Array((completedIDs + [id]).suffix(512)); total += 1; completed += 1; return true
    }
    func due(now: Int64) -> Bool {
        guard total > 2, lastAd == 0 || now >= lastAd && now - lastAd >= 120_000 else { return false }
        return regularLongSession ? completed >= 3 && activeMillis >= 300_000 : completed >= 2 || activeMillis >= 210_000
    }
    mutating func shown(now: Int64) { lastAd = now; completed = 0; activeMillis = 0 }
}
/// Completed-match interstitials for the standalone app (`.full`) only. Simple hosts (Math) show their own ads.
/// Production: `MinikAdsConfiguration` for `.minikPingPong` (enabled, policy-approved, real IDs).
/// Debug: Google's published iOS sample IDs when `ModernPongTestAdsEnabled` is set. Otherwise no ads.
/// Requests are child-directed, G-rated and non-personalized.
@MainActor final class MPAds: NSObject {
    var willPresent: (() -> Void)?
    private static let sampleApplication = "ca-app-pub-3940256099942544~1458002511"
    private static let sampleInterstitial = "ca-app-pub-3940256099942544/4411468910"
    private let preferences: MPPreferences
    private let unit: String?
    private var policy: MPAdPolicy
    private var continuation: (() -> Void)?
    private var loading = false, presenting = false, providerStarted = false
    private var eligible = true
    private var loadedAt: Int64 = 0, retryAt: Int64 = 0
    #if canImport(GoogleMobileAds)
    private var interstitial: InterstitialAd?
    #endif
    /// True when this build and experience may request interstitials at all.
    var configured: Bool { unit != nil }
    init(preferences: MPPreferences, experience: ModernPongExperience = .full) {
        self.preferences = preferences; policy = preferences.load("ads", MPAdPolicy.self) ?? .init()
        unit = MPAds.interstitialUnit(experience: experience)
        super.init()
    }
    private static func interstitialUnit(experience: ModernPongExperience) -> String? {
        guard experience == .full, ProductVariant.current == .minikPingPong else { return nil }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        if let production = MinikAdsConfiguration.load(product: .minikPingPong).providerConfiguration,
           production.isChildDirected, production.treatsUserAsUnderAgeOfConsent,
           production.maximumContentRating == .general, !production.allowsPersonalizedAds,
           bundled == production.applicationIdentifier {
            return production.interstitialAdUnitIdentifier
        }
        let value = Bundle.main.object(forInfoDictionaryKey: "ModernPongTestAdsEnabled")
        let testAds = value as? Bool == true || ["YES", "TRUE", "1"].contains((value as? String)?.uppercased() ?? "")
        return testAds && bundled == sampleApplication ? sampleInterstitial : nil
    }
    func start(removeAds: Bool) { eligible = !removeAds; startProvider() }
    func active(_ millis: Int64) { policy.active(millis, now: MPClock.now); preferences.save("ads", policy) }
    func removeAds(_ active: Bool) {
        eligible = !active
        if active {
            #if canImport(GoogleMobileAds)
            interstitial = nil
            #endif
        } else { startProvider() }
    }
    private func startProvider() {
        guard eligible, !providerStarted, unit != nil else { return }
        #if canImport(GoogleMobileAds)
        providerStarted = true
        let config = MobileAds.shared.requestConfiguration
        config.ageRestrictedTreatment = .child; config.maxAdContentRating = GADMaxAdContentRating.general
        config.publisherPrivacyPersonalizationState = .disabled
        Task { _ = await MobileAds.shared.start(); preload() }
        #endif
    }
    /// Call only after the durable, authoritative result; never while Ready or rallying.
    func completed(_ id: String, then: @escaping () -> Void) {
        let fresh = policy.completion(id); preferences.save("ads", policy)
        // Android AdCoordinator also returns while a family message is up, so no ad opens over it.
        guard fresh, eligible, !presenting, !FamilyMessages.shared.isShowing, policy.due(now: MPClock.now),
              UIApplication.shared.applicationState == .active else { then(); return }
        #if canImport(GoogleMobileAds)
        // Android AdCoordinator: an interstitial loaded 55 minutes ago or more is discarded, never shown.
        guard let ad = interstitial, MPClock.now - loadedAt < 3_300_000 else { interstitial = nil; preload(); then(); return }
        do { try ad.canPresent(from: nil) } catch { interstitial = nil; preload(); then(); return }
        // Android AdCoordinator: one eligible ad break in 30 (at most once a day) shows a Minik family
        // app instead; the cadence counts it as the ad.
        if FamilyMessages.shared.replaceAd(id, ownershipResolved: true, adFree: { [weak self] in !(self?.eligible ?? false) }, gate: nil,
                                          finished: { [weak self] in then(); self?.preload() }) {
            policy.shown(now: MPClock.now); preferences.save("ads", policy); return
        }
        presenting = true; continuation = then; ad.present(from: nil)
        #else
        then()
        #endif
    }
    private func preload() {
        #if canImport(GoogleMobileAds)
        guard eligible, providerStarted, !loading, interstitial == nil, let unit, MPClock.now >= retryAt else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let ad = try await InterstitialAd.load(with: unit, request: Request())
                guard eligible else { return }
                ad.fullScreenContentDelegate = self; interstitial = ad; loadedAt = MPClock.now
            } catch {
                // Android AdCoordinator waits a minute before another request after a failed load.
                retryAt = MPClock.now + 60_000
            }
        }
        #endif
    }
    private func finished() { presenting = false; let callback = continuation; continuation = nil; callback?(); preload() }
}
#if canImport(GoogleMobileAds)
extension MPAds: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) { willPresent?(); policy.shown(now: MPClock.now); preferences.save("ads", policy) }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { interstitial = nil; finished() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { interstitial = nil; finished() }
}
#endif
