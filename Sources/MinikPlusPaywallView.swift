import SwiftUI

/// Minik Plus and Minik Plus English: the texts of the free week and the buy wall, in the
/// interface language.
enum MinikPlusPaywallText {
    /// The app's name inside the texts: Minik Plus (מיניק פלוס in Hebrew) or Minik English.
    static func brandName(_ variant: ProductVariant, locale: InterfaceLocaleID) -> String {
        variant == .minikPlusEnglish ? locale.text("Minik English") : locale.text("Minik Plus")
    }

    /// "N days left in your free week", with each language's plural forms.
    static func daysLeft(_ days: Int, locale: InterfaceLocaleID) -> String {
        locale.text("\(days) days left in your free week")
    }

    /// The primary button: the App Store's price, or no price while it is not loaded.
    static func unlockButton(price: String?, locale: InterfaceLocaleID) -> String {
        guard let price else { return locale.text("Unlock everything") }
        return String(format: locale.text("Unlock everything – %@"), price)
    }
}

/// One full-screen view for the welcome before the free week ("Try Minik Plus free for 7 days"),
/// the wall after it ("Your free week is over") and the buy screen a grown-up opens during it.
/// It covers every activity; each store action and link waits for the grown-up check.
@MainActor
struct MinikPlusPaywallView: View {
    @ObservedObject var commerce: MinikCommerceController
    let variant: ProductVariant

    @Environment(\.interfaceLocaleID) private var interfaceLocale
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var textPercent: CGFloat = 100
    @State private var gatedAction: MinikPlusPaywallAction?
    /// Unlocked by the grown-up check; it runs once the check's sheet has gone.
    @State private var pendingAction: MinikPlusPaywallAction?
    @State private var restoreFoundNothing = false
    private let releaseInformation = MinikReleaseInformation.load()

    init(commerce: MinikCommerceController, variant: ProductVariant) {
        self.commerce = commerce
        self.variant = variant
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // An opaque layer that takes every touch: nothing under the wall can be reached.
                MinikPretty.sky
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                MinikSkyBackground()
                ScrollView {
                    content(width: geometry.size.width)
                        .frame(maxWidth: 540)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityAddTraits(.isModal)
        .sheet(item: $gatedAction, onDismiss: runPendingAction) { action in
            ParentalGateView(
                onCancel: { gatedAction = nil },
                onUnlock: {
                    pendingAction = action
                    gatedAction = nil
                }
            )
        }
        // Offline at launch, or the product not available yet: the App Store is asked again while
        // the window is up, and a later answer fills in the price.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if commerce.fullAccessProduct == nil, !commerce.isBusy {
                    await commerce.reloadStore()
                }
            }
        }
    }

    private func content(width: CGFloat) -> some View {
        MinikGlassPanel(padding: 0, cornerRadius: 28) {
            VStack(spacing: 14) {
                if canClose {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            commerce.dismissRequestedPaywall()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(MinikPretty.softInk)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: interfaceLocale.text("Close")))
                    }
                }

                let artWidth = max(1, min(320, width * 0.7))
                MinikArtworkImage(name: MinikPretty.Art.welcome)
                    .frame(width: artWidth, height: artWidth / MinikPretty.Art.welcomeAspect)
                    .accessibilityHidden(true)

                Text(verbatim: interfaceLocale.text("For parents"))
                    .font(MinikPretty.bodyFont(15 * textScale))
                    .foregroundStyle(MinikPretty.purple)

                Text(verbatim: headline)
                    .font(MinikPretty.titleFont(28 * textScale))
                    .foregroundStyle(MinikPretty.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: String(
                    format: interfaceLocale.text("Unlock all of %@ with a one-time purchase. No ads, no subscription."),
                    brandName
                ))
                .font(MinikPretty.bodyFont(18 * textScale))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if commerce.plusAccess == .trialNotStarted {
                    // Before the week starts the app says how long it lasts, that everything is
                    // locked after it, and what unlocking costs.
                    Text(verbatim: freeWeekTerms)
                        .font(MinikPretty.bodyFont(16 * textScale))
                        .foregroundStyle(MinikPretty.softInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionButtons
                    .padding(.top, 4)

                statusMessage

                links
            }
            .padding(.horizontal, 22)
            .padding(.top, canClose ? 6 : 22)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if commerce.plusAccess == .trialNotStarted {
                Button {
                    request(.startFreeWeek)
                } label: {
                    MinikInkCenteredText(interfaceLocale.text("Start free week"), fontSize: 22 * textScale)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPretty.HeroButtonStyle(
                    look: MinikPretty.PillLook.warm,
                    fontSize: 22 * textScale,
                    minHeight: 58
                ))
                .disabled(commerce.isBusy)
                .accessibilityHint(Text(verbatim: interfaceLocale.text("Opens a grown-up check before contacting the App Store")))
            }

            Button {
                request(.unlock)
            } label: {
                HStack(spacing: 10) {
                    MinikInkCenteredText(MinikPlusPaywallText.unlockButton(
                        price: commerce.fullAccessProduct?.displayPrice,
                        locale: interfaceLocale
                    ), fontSize: 22 * textScale)
                    // Only while the App Store is being asked. When it did not answer (or has no
                    // such product yet) the button stays without a price, unavailable, and the
                    // message below offers Try again.
                    if isLoadingPrice {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: commerce.plusAccess == .trialNotStarted ? MinikPretty.PillLook.purple : MinikPretty.PillLook.warm,
                fontSize: 22 * textScale,
                minHeight: 58
            ))
            .disabled(commerce.isBusy || commerce.fullAccessProduct == nil)
            .opacity(isUnlockUnavailable ? 0.55 : 1)
            .accessibilityHint(Text(verbatim: interfaceLocale.text("Opens a grown-up check before contacting the App Store")))

            if canClose {
                // During the free week (the daily window or the chip): back to the app. Leaving
                // the window buys nothing, so it needs no grown-up check, and it works while the
                // App Store is still being asked.
                Button {
                    commerce.dismissRequestedPaywall()
                } label: {
                    MinikInkCenteredText(interfaceLocale.text("Continue"), fontSize: 20 * textScale)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MinikPretty.HeroButtonStyle(
                    look: MinikPretty.PillLook.blue,
                    fontSize: 20 * textScale,
                    minHeight: 54
                ))
            }

            Button {
                request(.restore)
            } label: {
                MinikInkCenteredText(interfaceLocale.text("Restore Purchases"), fontSize: 18 * textScale)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: MinikPretty.PillLook.white,
                fontSize: 18 * textScale,
                minHeight: 50
            ))
            .disabled(commerce.isBusy)
            .accessibilityHint(Text(verbatim: interfaceLocale.text("Opens a grown-up check before restoring App Store purchases")))
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if commerce.isBusy {
            ProgressView {
                Text(verbatim: busyMessage)
                    .font(MinikPretty.bodyFont(15 * textScale))
                    .foregroundStyle(MinikPretty.softInk)
            }
        } else if outcomeMessage != nil || isUnlockUnavailable || commerce.status == .failed {
            VStack(spacing: 8) {
                if let outcome = outcomeMessage {
                    Text(verbatim: outcome)
                        .font(MinikPretty.bodyFont(15 * textScale))
                        .foregroundStyle(MinikPretty.softInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isUnlockUnavailable || commerce.status == .failed {
                    storeUnavailableMessage
                }
            }
        }
    }

    /// The App Store did not answer, or it has no full-access product yet: Unlock everything waits
    /// without a price, and Try again asks once more (the window also asks every 15 s). The message
    /// names the real reason; only a device that is offline is told to check the internet.
    private var storeUnavailableMessage: some View {
        VStack(spacing: 8) {
            Text(verbatim: storeProblemMessage)
                .font(MinikPretty.bodyFont(15 * textScale))
                .foregroundStyle(MinikPretty.color(0xC2416E))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await commerce.reloadStore() }
            } label: {
                Text(verbatim: interfaceLocale.text("Try again"))
                    .font(MinikPretty.titleFont(16 * textScale))
                    .foregroundStyle(MinikPretty.purple)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    /// The App Store is being asked for the price (at launch or Try again).
    private var isLoadingPrice: Bool {
        commerce.fullAccessProduct == nil && commerce.status == .loading
    }

    /// Unlock everything has no product to sell: the App Store did not answer, or has none yet.
    private var isUnlockUnavailable: Bool {
        commerce.fullAccessProduct == nil && commerce.status != .loading
    }

    /// Privacy Policy and Support, small, each behind the grown-up check.
    private var links: some View {
        HStack(spacing: 18) {
            if releaseInformation.url(for: .privacyPolicy) != nil {
                linkButton(interfaceLocale.text("Privacy Policy"), action: .privacyPolicy)
            }
            if releaseInformation.url(for: .support) != nil {
                linkButton(interfaceLocale.text("Support"), action: .support)
            }
        }
        .padding(.top, 2)
    }

    private func linkButton(_ title: String, action: MinikPlusPaywallAction) -> some View {
        Button {
            request(action)
        } label: {
            Text(verbatim: title)
                .font(MinikPretty.bodyFont(14 * textScale))
                .underline()
                .foregroundStyle(MinikPretty.softInk)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: interfaceLocale.text("Opens a grown-up check before leaving the app")))
    }

    // MARK: - Texts

    private var brandName: String {
        MinikPlusPaywallText.brandName(variant, locale: interfaceLocale)
    }

    private var headline: String {
        switch commerce.plusAccess {
        case .trialNotStarted:
            return String(format: interfaceLocale.text("Try %@ free for 7 days"), brandName)
        case .trialEnded:
            return interfaceLocale.text("Your free week is over")
        case .trial(let daysLeft):
            return MinikPlusPaywallText.daysLeft(daysLeft, locale: interfaceLocale)
        case .fullAccess:
            return interfaceLocale.text("Thank you! Everything is unlocked.")
        }
    }

    private var freeWeekTerms: String {
        guard let price = commerce.fullAccessProduct?.displayPrice else {
            return interfaceLocale.text("Your free week lasts 7 days. After that, the whole app is locked until you unlock it with a one-time purchase.")
        }
        return String(
            format: interfaceLocale.text("Your free week lasts 7 days. After that, the whole app is locked until you unlock it with a one-time purchase of %@."),
            price
        )
    }

    private var storeProblemMessage: String {
        switch commerce.storeProblem {
        case .offline:
            return interfaceLocale.text("Can't reach the store right now. Check the internet and try again.")
        case .notAnswering:
            return interfaceLocale.text("The App Store isn't answering right now. Please try again in a little while.")
        case .productUnavailable:
            return interfaceLocale.text("Unlock everything isn't available in the App Store right now. Please try again later.")
        case .purchasesNotAllowed:
            return interfaceLocale.text("Purchases are turned off on this device. A parent can allow them in Settings > Screen Time.")
        }
    }

    private var busyMessage: String {
        switch commerce.status {
        case .purchasing:
            return interfaceLocale.text("Contacting the App Store…")
        case .restoring:
            return interfaceLocale.text("Restoring purchases…")
        default:
            return interfaceLocale.text("Checking purchases…")
        }
    }

    private var outcomeMessage: String? {
        switch commerce.status {
        case .pending:
            return interfaceLocale.text("Purchase approval is pending.")
        case .cancelled:
            return interfaceLocale.text("Purchase cancelled.")
        case .ready where restoreFoundNothing:
            return interfaceLocale.text("No earlier purchase was found.")
        default:
            return nil
        }
    }

    // MARK: - Actions

    /// The wall closes by itself once the app is unlocked; during the free week the buy screen a
    /// grown-up opened can be closed.
    private var canClose: Bool {
        !commerce.plusAccess.isLocked
    }

    private var textScale: CGFloat {
        min(1.3, max(0.9, textPercent / 100))
    }

    private func request(_ action: MinikPlusPaywallAction) {
        restoreFoundNothing = false
        gatedAction = action
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .startFreeWeek:
            Task { await commerce.startFreeWeek() }
        case .unlock:
            Task { await commerce.purchaseFullAccess() }
        case .restore:
            Task {
                await commerce.restorePurchases()
                restoreFoundNothing = commerce.status == .ready && commerce.plusAccess != .fullAccess
            }
        case .privacyPolicy:
            if let url = releaseInformation.url(for: .privacyPolicy) { openURL(url) }
        case .support:
            if let url = releaseInformation.url(for: .support) { openURL(url) }
        }
    }
}

private enum MinikPlusPaywallAction: String, Identifiable {
    case startFreeWeek
    case unlock
    case restore
    case privacyPolicy
    case support

    var id: String { rawValue }
}

/// The note after full access was bought or restored; the wall has closed and the app goes on
/// where it was.
struct MinikPlusUnlockThanks: View {
    @Environment(\.interfaceLocaleID) private var interfaceLocale

    init() {}

    var body: some View {
        Label {
            Text(verbatim: interfaceLocale.text("Thank you! Everything is unlocked."))
        } icon: {
            Image(systemName: "checkmark.seal.fill")
        }
        .font(MinikPretty.titleFont(17))
        .foregroundStyle(MinikPretty.color(0x1F8A5B))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white)
                .shadow(color: MinikPretty.shadowInk.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Minik Plus: the small "N days left in your free week" chip on the main screen. A tap opens the
/// grown-up check, then the buy screen (the intro holds the check's sheet). It shows nothing
/// outside the free week.
struct MinikPlusFreeWeekChip: View {
    @ObservedObject var commerce: MinikCommerceController
    let fontSize: CGFloat
    let onTap: () -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocale

    init(commerce: MinikCommerceController, fontSize: CGFloat, onTap: @escaping () -> Void) {
        self.commerce = commerce
        self.fontSize = fontSize
        self.onTap = onTap
    }

    var body: some View {
        if case .trial(let daysLeft) = commerce.plusAccess {
            Button(action: onTap) {
                Label {
                    Text(verbatim: MinikPlusPaywallText.daysLeft(daysLeft, locale: interfaceLocale))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } icon: {
                    Image(systemName: "gift.fill")
                }
                .font(MinikPretty.bodyFont(fontSize))
                .foregroundStyle(MinikPretty.color(0x6A55D6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background {
                    Capsule(style: .continuous)
                        .fill(MinikPretty.lavender)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(MinikPretty.lavenderRim, lineWidth: 1.5)
                        }
                }
            }
            .buttonStyle(MinikPretty.PressScaleStyle())
            .accessibilityHint(Text(verbatim: interfaceLocale.text("Opens a grown-up check before contacting the App Store")))
        }
    }
}
