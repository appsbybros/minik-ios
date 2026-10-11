import SwiftUI
import UIKit

// MARK: - Portrait notice (iPad QA ISSUE-004)

extension View {
    /// Asks to turn an iPad held in landscape upright; see PortraitNoticeModifier.
    /// RootView enables it for the portrait-only language products only: Minik Math
    /// and the Ping Pong apps turn with the iPad.
    @MainActor
    func minikPortraitNotice(isEnabled: Bool) -> some View {
        modifier(PortraitNoticeModifier(isEnabled: isEnabled))
    }
}

/// The language apps are portrait-only, as Android's sensorPortrait (project.yml:
/// UISupportedInterfaceOrientations with UIRequiresFullScreen). iPhone, iPadOS 17
/// and iPadOS 18 keep them upright, but iPadOS 26 no longer turns the screen for an
/// app that supports only portrait: on an iPad held in landscape it draws the app's
/// portrait window smaller, between black bars (ISSUE-004), and no API lets an app
/// turn the screen or the device. So while an iPad is physically in landscape, a
/// friendly notice in the rainbow-sky design asks to turn it.
///
/// - It sits in the top safe-area inset: every screen lays out below it, so it never
///   covers an activity's controls, and the sky still runs behind it.
/// - It never blocks play, and its X hides it until the iPad is next upright.
/// - It is gone as soon as the iPad is in portrait, either way up.
/// - Lying flat (face up or down) or unknown keeps the last upright reading, as the
///   system's interface does; an iPad already lying flat at launch shows the notice
///   once it is lifted. With the rotation lock on, iPadOS reports the locked
///   orientation, which is the one the app is drawn in.
/// - iPhone, an iPad app running on a Mac and the App Store screenshot captures
///   never show it.
@MainActor
struct PortraitNoticeModifier: ViewModifier {
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The device itself (not the interface) was last upright in landscape.
    @State private var deviceIsLandscape = false
    /// The X was tapped; cleared when the iPad is next in portrait.
    @State private var isHiddenUntilPortrait = false
    /// Balances UIDevice's begin/end orientation notification calls.
    @State private var isObservingOrientation = false

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && appliesToThisDevice {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if showsNotice {
                            PortraitNoticeBanner(onHide: { isHiddenUntilPortrait = true })
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsNotice)
                }
                .onAppear { startObservingOrientation() }
                .onDisappear { stopObservingOrientation() }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                    record(UIDevice.current.orientation)
                }
                // The iPad may have been turned while another app was in front.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        record(UIDevice.current.orientation)
                    }
                }
        } else {
            content
        }
    }

    /// An iPad, not an iPad app on a Mac, and not an App Store screenshot capture.
    private var appliesToThisDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && !ProcessInfo.processInfo.isiOSAppOnMac
            && StoreScreenshotScene.name == nil
    }

    private var showsNotice: Bool {
        deviceIsLandscape && !isHiddenUntilPortrait
    }

    private func startObservingOrientation() {
        guard !isObservingOrientation else { return }
        isObservingOrientation = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        record(UIDevice.current.orientation)
    }

    private func stopObservingOrientation() {
        guard isObservingOrientation else { return }
        isObservingOrientation = false
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// Landscape shows the notice; portrait (either way up) hides it and forgets the
    /// X. Face up, face down and unknown leave everything as it was.
    private func record(_ orientation: UIDeviceOrientation) {
        if orientation.isLandscape {
            if !deviceIsLandscape {
                deviceIsLandscape = true
            }
        } else if orientation.isPortrait {
            if deviceIsLandscape {
                deviceIsLandscape = false
            }
            if isHiddenUntilPortrait {
                isHiddenUntilPortrait = false
            }
        }
    }
}

/// The notice: a white glass card with a lavender rim on the sky, an iPad turning
/// upright in purple, the message in navy Fredoka and a small X. At most 640 points
/// wide and centred. iPadOS draws the whole portrait window smaller in landscape,
/// so the message is a size larger than the activities' body text.
@MainActor
struct PortraitNoticeBanner: View {
    let onHide: () -> Void

    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .body) private var textPercent: CGFloat = 100

    init(onHide: @escaping () -> Void) {
        self.onHide = onHide
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            pictogram
            Text(interfaceLocaleID.text("This app is designed for portrait. Please turn your iPad for the best experience."))
                .font(MinikPretty.bodyFont(22 * textScale))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            hideButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MinikPretty.panelFill)
                .shadow(color: MinikPretty.shadowInk.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(MinikPretty.lavenderRim, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// An iPad on its side, an arrow and an upright iPad, in the interface's reading
    /// order: Hebrew and Arabic read it from the right.
    private var pictogram: some View {
        let rightToLeft = layoutDirection == .rightToLeft
        return HStack(spacing: 5) {
            Image(systemName: rightToLeft ? "ipad" : "ipad.landscape")
            Image(systemName: rightToLeft ? "arrow.left" : "arrow.right")
                .font(.system(size: 15, weight: .heavy))
            Image(systemName: rightToLeft ? "ipad.landscape" : "ipad")
        }
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(MinikPretty.purple)
        // The order above already follows the reading direction.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MinikPretty.lavender, in: Capsule(style: .continuous))
        .accessibilityHidden(true)
    }

    /// A small X with a 44-point target; it hides the notice until the iPad is upright.
    private var hideButton: some View {
        Button(action: onHide) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MinikPretty.softInk)
                .frame(width: 30, height: 30)
                .background(MinikPretty.lavender, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(MinikPretty.PressScaleStyle())
        .accessibilityLabel(Text(interfaceLocaleID.text("Hide this message")))
    }

    /// Dynamic Type for the message, within what a notice above the screen should take.
    private var textScale: CGFloat {
        min(1.3, max(0.9, textPercent / 100))
    }
}
