import Foundation

#if canImport(GoogleMobileAds) && canImport(UIKit)
@preconcurrency import GoogleMobileAds
import UIKit

actor GoogleMobileAdsInterstitialAdService: MinikInterstitialAdService {
    private var driver: GoogleMobileAdsInterstitialDriver?

    func configure(_ configuration: MinikAdProviderConfiguration) async -> Bool {
        let resolvedDriver: GoogleMobileAdsInterstitialDriver
        if let driver {
            resolvedDriver = driver
        } else {
            let created = await MainActor.run { GoogleMobileAdsInterstitialDriver() }
            driver = created
            resolvedDriver = created
        }
        return await resolvedDriver.configure(configuration)
    }

    func presentInterstitial() async -> MinikInterstitialPresentationResult {
        guard let driver else { return .unavailable }
        return await driver.presentInterstitial()
    }

    func waitUntilDismissed() async {
        guard let driver else { return }
        await driver.waitUntilDismissed()
    }
}

@MainActor
private final class GoogleMobileAdsInterstitialDriver: NSObject, FullScreenContentDelegate {
    private var interstitial: InterstitialAd?
    private var interstitialAdUnitIdentifier: String?
    private var presentationContinuation:
        CheckedContinuation<MinikInterstitialPresentationResult, Never>?
    /// An interstitial is on screen; `waitUntilDismissed` callers wait for it to close.
    private var isOnScreen = false
    private var dismissalContinuations: [CheckedContinuation<Void, Never>] = []

    func configure(_ configuration: MinikAdProviderConfiguration) async -> Bool {
        guard configuration.isChildDirected,
              configuration.treatsUserAsUnderAgeOfConsent,
              configuration.maximumContentRating == .general,
              !configuration.allowsPersonalizedAds,
              let bundledApplicationIdentifier = Bundle.main.object(
                  forInfoDictionaryKey: "GADApplicationIdentifier"
              ) as? String,
              bundledApplicationIdentifier == configuration.applicationIdentifier else {
            return false
        }

        let requestConfiguration = MobileAds.shared.requestConfiguration
        requestConfiguration.ageRestrictedTreatment = .child
        requestConfiguration.maxAdContentRating = GADMaxAdContentRating.general
        requestConfiguration.publisherPrivacyPersonalizationState = .disabled

        interstitialAdUnitIdentifier = configuration.interstitialAdUnitIdentifier
        // In Swift, Google Mobile Ads 13 exposes start() only as an async call.
        _ = await MobileAds.shared.start()
        return await loadInterstitial()
    }

    func presentInterstitial() async -> MinikInterstitialPresentationResult {
        guard presentationContinuation == nil else { return .unavailable }
        guard let interstitial else {
            _ = await loadInterstitial()
            return .unavailable
        }

        do {
            try interstitial.canPresent(from: nil)
        } catch {
            self.interstitial = nil
            _ = await loadInterstitial()
            return .failed
        }

        return await withCheckedContinuation { continuation in
            presentationContinuation = continuation
            interstitial.present(from: nil)
        }
    }

    func waitUntilDismissed() async {
        guard isOnScreen else { return }
        await withCheckedContinuation { continuation in
            dismissalContinuations.append(continuation)
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isOnScreen = true
        finishPresentation(with: .presented)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        interstitial = nil
        finishPresentation(with: .failed)
        endDismissalWait()
        Task { _ = await loadInterstitial() }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        endDismissalWait()
        Task { _ = await loadInterstitial() }
    }

    private func loadInterstitial() async -> Bool {
        guard interstitial == nil,
              let interstitialAdUnitIdentifier else {
            return interstitial != nil
        }

        do {
            let loaded = try await InterstitialAd.load(
                with: interstitialAdUnitIdentifier,
                request: Request()
            )
            loaded.fullScreenContentDelegate = self
            interstitial = loaded
            return true
        } catch {
            interstitial = nil
            return false
        }
    }

    private func finishPresentation(with result: MinikInterstitialPresentationResult) {
        presentationContinuation?.resume(returning: result)
        presentationContinuation = nil
    }

    private func endDismissalWait() {
        isOnScreen = false
        let waiting = dismissalContinuations
        dismissalContinuations = []
        waiting.forEach { $0.resume() }
    }
}
#endif

enum ProductionMinikInterstitialAdServiceFactory {
    static func make() -> any MinikInterstitialAdService {
        #if canImport(GoogleMobileAds) && canImport(UIKit)
        return GoogleMobileAdsInterstitialAdService()
        #else
        return UnconfiguredMinikInterstitialAdService()
        #endif
    }
}
