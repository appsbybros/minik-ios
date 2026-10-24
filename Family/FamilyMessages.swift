import ImageIO
import SwiftUI
import UIKit

/// The host's grown-up gate: it runs the approved action after the adult has passed the gate.
typealias FamilyGate = (@escaping () -> Void) -> Void

/// The promotion card being shown (Android `FamilyMessages.show`).
struct FamilyCard: Identifiable {
    let id = UUID()
    let entry: FamilyCatalog.Entry
    let locale: String
    let gate: FamilyGate?
    let finished: () -> Void
    let adFree: () -> Bool
}

/// Android `FamilyAdultGate`: x in 4...9, y in 3...8.
struct FamilyGateRequest: Identifiable {
    let id = UUID()
    let x: Int
    let y: Int
    let approved: () -> Void
}

/// Port of Android MinikFamilyServices FamilyMessages.java: the shared editorial messages of the
/// Minik apps — the voluntary "More Minik apps & games" card, the promotion that replaces one
/// eligible ad break in 30 (at most once a day) and the remove-ads reminder (after 14 days, then
/// at most every 14 days, with a permanent opt-out). Hosts own their grown-up gate, safe breaks and
/// entitlements, and show `FamilyOverlay` above their root view. On iOS the card never links to
/// Google Play.
@MainActor
final class FamilyMessages: ObservableObject {
    static let shared = FamilyMessages()

    @Published private(set) var card: FamilyCard?
    @Published var image: UIImage?
    @Published var reminderVisible = false
    @Published var gateRequest: FamilyGateRequest?
    @Published var gateAnswer = ""
    @Published var gateError = false
    @Published var toast: String?
    /// The `FamilyOverlay`s on screen, in the order they appeared; only the last one draws.
    @Published private(set) var overlayHosts: [UUID] = []

    /// Android `setLanguage(language)`; otherwise the device language.
    var languageOverride: String?
    /// This app's catalogue key (`MinikFamilyCatalogKey` in Info.plist, e.g. "squash"), so the
    /// catalogue never promotes the app itself.
    private(set) var catalogKey: String
    private var policy: FamilyMessagePolicy
    private var reminderGate: FamilyGate?
    private var reminderPurchase: (() -> Void)?
    private var watchTask: Task<Void, Never>?

    private init() {
        catalogKey = (Bundle.main.object(forInfoDictionaryKey: "MinikFamilyCatalogKey") as? String) ?? ""
        policy = FamilyMessagePolicy.decode(UserDefaults.standard.string(forKey: FamilyCatalog.key("cadence")), now: FamilyMessages.now())
        save()
        FamilyCatalog.refresh()
    }

    var isShowing: Bool { return card != nil || reminderVisible }

    private static func now() -> Int64 { return Int64(Date().timeIntervalSince1970 * 1000) }

    private func save() { UserDefaults.standard.set(policy.encode(), forKey: FamilyCatalog.key("cadence")) }

    /// Android `language(a)`: the host's override, else the device language; "iw" is Hebrew.
    var language: String {
        let l = languageOverride ?? (Locale.preferredLanguages.first ?? "en")
        return l.hasPrefix("iw") ? "he" + l.dropFirst(2) : l
    }

    /// Android `FamilyMessages.text(a, en, he)`.
    func text(_ en: String, _ he: String) -> String { return FamilyMessages.text(en, he, language: language) }

    static func text(_ en: String, _ he: String) -> String { return shared.text(en, he) }

    /// The text in a given language, for host labels that follow the host's own language setting.
    static func text(_ en: String, _ he: String, language: String) -> String {
        let l = String(language.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "en")
        return l == "he" || l == "iw" ? he : FamilyText.get(l, en)
    }

    var rtl: Bool { return language.hasPrefix("he") || language.hasPrefix("ar") }

    // MARK: Entry points (Android public API)

    /// Android `replaceAd`: true only when this has replaced the normal ad (the host then counts it as shown).
    @discardableResult
    func replaceAd(_ completedId: String, ownershipResolved: Bool, adFree: @escaping () -> Bool, gate: FamilyGate?, finished: @escaping () -> Void) -> Bool {
        if isShowing { return false }
        let due = policy.opportunity(completedId, now: FamilyMessages.now(), resolved: ownershipResolved, adFree: adFree())
        save()
        if !due { return false }
        guard let entry = FamilyCatalog.load().choose(catalogKey) else { return false }
        show(entry, gate, finished, adFree)
        policy.promotionShown(FamilyMessages.now())
        save()
        return true
    }

    /// Android `showMoreApps`: the voluntary menu entry stays available to ad-free users.
    @discardableResult
    func showMoreApps(gate: FamilyGate?) -> Bool {
        if isShowing { return false }
        guard let entry = FamilyCatalog.load().choose(catalogKey) else {
            open(gate) { [weak self] in self?.openLink(FamilyCatalog.directory) }
            return true
        }
        show(entry, gate, {}, { false })
        return true
    }

    /// Android `remind`: the host calls it on an idle menu once its own startup messages are done.
    @discardableResult
    func remind(ownershipResolved: Bool, adFree: @escaping () -> Bool, purchaseAvailable: Bool, gate: FamilyGate?, purchase: @escaping () -> Void) -> Bool {
        if isShowing || !policy.reminderDue(FamilyMessages.now(), resolved: ownershipResolved, adFree: adFree(), purchaseAvailable: purchaseAvailable) {
            return false
        }
        reminderGate = gate
        reminderPurchase = purchase
        reminderVisible = true
        watch(adFree)
        policy.reminderShown(FamilyMessages.now())
        save()
        return true
    }

    // MARK: Reminder actions

    func reminderRemoveAds() {
        let purchase = reminderPurchase
        let gate = reminderGate
        closeReminder()
        if let purchase = purchase { open(gate, purchase) }
    }

    func reminderLater() { closeReminder() }

    func reminderNever() {
        policy.stopReminding()
        save()
        closeReminder()
    }

    private func closeReminder() {
        reminderVisible = false
        reminderGate = nil
        reminderPurchase = nil
        if card == nil { stopWatching() }
    }

    // MARK: Card

    private func show(_ entry: FamilyCatalog.Entry, _ gate: FamilyGate?, _ finished: @escaping () -> Void, _ adFree: @escaping () -> Bool) {
        let locale = language
        image = FamilyMessages.bundledImage(entry.asset(locale))
        card = FamilyCard(entry: entry, locale: locale, gate: gate, finished: finished, adFree: adFree)
        if !entry.artUrl.isEmpty, let url = URL(string: entry.artUrl) {
            let shown = card?.id
            FamilyFetch.data(url, maximum: 5_000_000) { data in
                guard let data = data, let picture = FamilyMessages.decode(data) else { return }
                Task { @MainActor in
                    let messages = FamilyMessages.shared
                    if messages.card?.id == shown { messages.image = picture }
                }
            }
        }
        watch(adFree)
    }

    /// "Keep playing" or a dismissal: Android `complete`.
    func dismissCard() {
        guard let current = card else { return }
        card = nil
        image = nil
        if !reminderVisible { stopWatching() }
        current.finished()
    }

    func cardLink(_ url: String) {
        guard let current = card else { return }
        open(current.gate) { [weak self] in self?.openLink(url) }
    }

    /// Android `watchEntitlement`: closes the message as soon as the app becomes ad-free.
    private func watch(_ adFree: @escaping () -> Bool) {
        stopWatching()
        watchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self = self, self.isShowing else { return }
                if adFree() {
                    if self.card != nil { self.dismissCard() }
                    if self.reminderVisible { self.closeReminder() }
                    return
                }
            }
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: Gate and links

    /// The host's gate, else Android's short local grown-up gate.
    private func open(_ gate: FamilyGate?, _ approved: @escaping () -> Void) {
        if let gate = gate {
            gate(approved)
            return
        }
        gateAnswer = ""
        gateError = false
        gateRequest = FamilyGateRequest(x: 4 + Int.random(in: 0..<6), y: 3 + Int.random(in: 0..<6), approved: approved)
    }

    func confirmGate() {
        guard let request = gateRequest else { return }
        if let value = FamilyMessages.answer(gateAnswer), value == request.x * request.y {
            gateRequest = nil
            request.approved()
        } else {
            gateError = true
        }
    }

    func cancelGate() {
        gateRequest = nil
    }

    /// Java `Integer.parseInt(text.trim())`, as Android checks the answer: an optional sign and
    /// Unicode decimal digits, so an answer typed with Arabic-Indic digits ("٥٦") counts too.
    nonisolated static func answer(_ text: String) -> Int? {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
        while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
        var sign = 1
        if let first = scalars.first, first == "-" || first == "+" {
            if first == "-" { sign = -1 }
            scalars.removeFirst()
        }
        if scalars.isEmpty { return nil }
        var value = 0
        for scalar in scalars {
            guard scalar.value <= 0xffff, scalar.properties.generalCategory == .decimalNumber,
                  let digit = scalar.properties.numericValue else { return nil }
            value = value * 10 + Int(digit)
            if value > 2_147_483_648 { return nil }
        }
        value *= sign
        return value <= 2_147_483_647 ? value : nil
    }

    // MARK: Overlays

    func attach(_ host: UUID) {
        overlayHosts.removeAll { $0 == host }
        overlayHosts.append(host)
    }

    func detach(_ host: UUID) {
        overlayHosts.removeAll { $0 == host }
    }

    private func openLink(_ link: String) {
        guard let url = URL(string: link) else { return }
        UIApplication.shared.open(url) { opened in
            if opened { return }
            Task { @MainActor in
                let messages = FamilyMessages.shared
                messages.toast = messages.text("No browser is available.", "אין דפדפן זמין.")
            }
        }
    }

    // MARK: Art

    /// The bundled catalogue art ("minik-family/art/<name>.png" is the image set "family-<name>").
    static func bundledImage(_ asset: String) -> UIImage? {
        guard !asset.isEmpty else { return nil }
        let file = (asset as NSString).lastPathComponent
        let name = (file as NSString).deletingPathExtension
        return UIImage(named: "family-" + name)
    }

    /// Android `decode(bytes)`: bounded size, scaled down to at most 1400 pixels.
    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12000, height <= 12000 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), 1400),
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: Views

/// Shown above a host's root view, and above a sheet that can open the card: the family card, the
/// remove-ads reminder, the grown-up gate and the "No browser" note. Only the overlay that appeared
/// last draws them, so a card opened in a sheet is shown once, above the sheet. As on Android (every
/// family dialog goes through `FamilyDialogStyle.apply`, which defaults to `FamilySkyUi.dialog`), the
/// dialogs are light sky panels with raised buttons.
@MainActor
struct FamilyOverlay: View {
    @ObservedObject private var messages = FamilyMessages.shared
    @State private var host = UUID()

    var body: some View {
        let topmost = messages.overlayHosts.last == host
        ZStack {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if topmost, let card = messages.card {
                FamilyCardView(card: card)
            }
            if topmost && messages.reminderVisible {
                FamilyReminderView()
            }
            if topmost, let request = messages.gateRequest {
                FamilyGateView(request: request)
            }
            if topmost, let toast = messages.toast {
                FamilyKit.Toast(toast)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if messages.toast == toast { messages.toast = nil }
                    }
            }
        }
        .onAppear { messages.attach(host) }
        .onDisappear { messages.detach(host) }
    }
}

private func familyColor(_ argb: UInt32) -> Color {
    return Color(red: Double((argb >> 16) & 0xff) / 255, green: Double((argb >> 8) & 0xff) / 255, blue: Double(argb & 0xff) / 255,
                 opacity: Double((argb >> 24) & 0xff) / 255)
}

private struct FamilyContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Android `show(a, entry, ...)`: eyebrow, artwork, title, body, the directory note, the link buttons
/// and a full-width mint "Keep playing" button at the end, all on the card's lilac box, in a sky dialog
/// at most 650 points wide that wraps its content (scrolling when it is taller). "Keep playing" closes
/// it, as does a tap outside.
@MainActor
private struct FamilyCardView: View {
    let card: FamilyCard
    @ObservedObject private var messages = FamilyMessages.shared
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let e = card.entry
        let locale = card.locale
        GeometryReader { geo in
            FamilyKit.SkyDialog(maxWidth: 650, margin: 12, onBackdropTap: { messages.dismissCard() }) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            label(messages.text("From the Minik family", "ממשפחת מיניק"), 14, 0xff6951a1)
                                .padding(.bottom, 10)
                            if let picture = messages.image {
                                Image(uiImage: picture)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: min(geo.size.width - 60, 614) * 500 / 1024)
                                    .accessibilityLabel(e.title(locale))
                                    .padding(.bottom, 12)
                            }
                            label(e.title(locale), 27, 0xff182844, bold: true)
                            label(e.body(locale), 18, 0xff263d5b)
                            label(messages.text("Discover all our apps and games at miniklearn.com.", "כל האפליקציות והמשחקים שלנו מחכים ב־miniklearn.com."), 15, 0xff455978)
                            if !e.landingUrl.isEmpty { link(messages.text("Meet this app", "להכיר את האפליקציה"), e.landingUrl) }
                            if !e.webUrl.isEmpty { link(messages.text("Play on the website", "משחק באתר"), e.webUrl) }
                            if !e.iosUrl.isEmpty { link(messages.text("Also available for iPhone", "זמין גם ל־iPhone"), e.iosUrl) }
                            link(messages.text("All our apps & games", "כל האפליקציות והמשחקים"), FamilyCatalog.directory)
                            keepPlaying
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        .background(GeometryReader { inner in
                            Color.clear.preference(key: FamilyContentHeight.self, value: inner.size.height)
                        })
                    }
                    // The dialog's 24-point margins take the rest of the height.
                    .frame(height: max(min(contentHeight, geo.size.height - 48), 1))
                    .background(familyColor(0xfff7f5ff))
                    .clipShape(RoundedRectangle(cornerRadius: FamilyKit.Sky.dialogCornerRadius, style: .circular))
                    .onPreferenceChange(FamilyContentHeight.self) { height in
                        MainActor.assumeIsolated { contentHeight = height }
                    }
                }
                .environment(\.layoutDirection, messages.rtl ? .rightToLeft : .leftToRight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func label(_ text: String, _ size: CGFloat, _ color: UInt32, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundColor(familyColor(color))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 7)
    }

    /// A flat pale-blue link button, its text 1.5 points above centre (Android: no font padding,
    /// 3 points of bottom padding), 12 points below the item above.
    private func link(_ title: String, _ url: String) -> some View {
        Button { messages.cardLink(url) } label: {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(familyColor(0xff16395b))
                .multilineTextAlignment(.center)
                .padding(.bottom, 3)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 16).fill(familyColor(0xffdceeff)))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    /// Android's in-card "Keep playing" (no longer a dialog button): flat mint, 52 points tall, full
    /// width, 16 points below the links.
    private var keepPlaying: some View {
        Button { messages.dismissCard() } label: {
            Text(messages.text("Keep playing", "ממשיכים לשחק"))
                .font(.system(size: 16))
                .foregroundColor(familyColor(0xff17334f))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(familyColor(0xffc8f1e6)))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

/// Android `FamilyMessages.remind`: "Ad-free play" with Remove ads (raised blue), Remind me later
/// (pink) and Don't show again (blue, at the start of the row) in a sky dialog. The buttons stack,
/// Remove ads on top, when the row does not fit. A tap outside is "Remind me later".
@MainActor
private struct FamilyReminderView: View {
    @ObservedObject private var messages = FamilyMessages.shared

    var body: some View {
        FamilyKit.SkyDialog(maxWidth: 480, onBackdropTap: { messages.reminderLater() }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(messages.text("Ad-free play", "משחק ללא פרסומות"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(familyColor(0xff17364a))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(messages.text("Would you like to remove the ads? You can keep playing either way.", "רוצים להסיר את הפרסומות? אפשר להמשיך לשחק גם בלי לרכוש."))
                    .font(.system(size: 16))
                    .foregroundColor(familyColor(0xff263d5b))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        never
                        Spacer(minLength: 8)
                        later
                        remove
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        remove
                        later
                        never
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .environment(\.layoutDirection, messages.rtl ? .rightToLeft : .leftToRight)
        }
    }

    private var remove: some View {
        FamilyKit.SkyDialogButton(messages.text("Remove ads", "הסרת פרסומות")) { messages.reminderRemoveAds() }
    }

    private var later: some View {
        FamilyKit.SkyDialogButton(messages.text("Remind me later", "להזכיר לי בהמשך"), role: .negative) { messages.reminderLater() }
    }

    private var never: some View {
        FamilyKit.SkyDialogButton(messages.text("Don't show again", "לא להציג שוב"), role: .neutral) { messages.reminderNever() }
    }
}

/// Android `FamilyAdultGate.open`: "For a grown-up", "x × y = ?" read left to right and a number field
/// (styled by `FamilyFormStyle`), in a sky dialog with raised Cancel (pink) and Continue (blue)
/// buttons. A tap outside cancels.
@MainActor
private struct FamilyGateView: View {
    let request: FamilyGateRequest
    @ObservedObject private var messages = FamilyMessages.shared
    @FocusState private var answerFocused: Bool

    var body: some View {
        FamilyKit.SkyDialog(onBackdropTap: { messages.cancelGate() }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(messages.text("For a grown-up", "למבוגר אחראי"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(familyColor(0xff17364a))
                Text(verbatim: "\u{2066}\(request.x) × \(request.y) = ?\u{2069}")
                    .font(.system(size: 18))
                    .foregroundColor(familyColor(0xff17364a))
                TextField("", text: $messages.gateAnswer)
                    .keyboardType(.asciiCapableNumberPad)
                    .font(.system(size: 18))
                    .focused($answerFocused)
                    .modifier(FamilyKit.FormField(focused: answerFocused, minHeight: 56))
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(messages.text("Answer", "תשובה"))
                if messages.gateError {
                    Text(messages.text("Try again.", "נסו שוב."))
                        .font(.system(size: 15))
                        .foregroundColor(familyColor(0xffb3261e))
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    // The gate's Material buttons keep their capitals.
                    FamilyKit.SkyDialogButton(messages.text("Cancel", "ביטול"), role: .negative, textColor: 0xff245785, uppercase: true) {
                        messages.cancelGate()
                    }
                    FamilyKit.SkyDialogButton(messages.text("Continue", "המשך"), textColor: 0xff245785, uppercase: true) {
                        messages.confirmGate()
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .environment(\.layoutDirection, messages.rtl ? .rightToLeft : .leftToRight)
        }
    }
}
