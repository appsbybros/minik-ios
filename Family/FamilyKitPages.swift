import SwiftUI

// MARK: Rooms and tournaments (Android FamilyTournamentUi)

private struct FamilyKitDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

extension FamilyKit {
    /// Android `FamilyTournamentUi.divider`: the dashed line that separates "Create room" from joining
    /// (2 points, 7 on / 6 off, #7892AD), with 24 points above and below and 8 at the sides.
    struct TournamentDivider: View {
        init() {}

        var body: some View {
            FamilyKitDashLine()
                .stroke(FamilyKit.color(0xff7892ad), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .frame(height: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
        }
    }

    /// Android `FamilyTournamentUi.confirmSave`: leaving an unfinished tournament asks Save / Don't save
    /// / Cancel. A raised light panel with a centred title and message and three 64-point buttons (Save
    /// blue, Don't save red with white text, Cancel lilac; their lettering centred on the raised face, as
    /// Android binds `FamilyButtonAlignment`). A tap outside does nothing. The host shows
    /// it last in a full-screen `ZStack`, supplies the texts in its own language and hides it in each
    /// callback (Android dismisses the dialog first, then runs Save or Don't save; Cancel only closes).
    struct TournamentExitDialog: View {
        let title: String
        let message: String
        let save: String
        let discard: String
        let cancel: String
        let onSave: () -> Void
        let onDiscard: () -> Void
        let onCancel: () -> Void

        init(title: String, message: String, save: String, discard: String, cancel: String,
             onSave: @escaping () -> Void, onDiscard: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.title = title
            self.message = message
            self.save = save
            self.discard = discard
            self.cancel = cancel
            self.onSave = onSave
            self.onDiscard = onDiscard
            self.onCancel = onCancel
        }

        var body: some View {
            SkyDialog(panelColor: 0xfff6f8ff) {
                ViewThatFits(in: .vertical) {
                    panel
                    ScrollView { panel }
                }
            }
        }

        private var panel: some View {
            VStack(spacing: 0) {
                Text(verbatim: title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(FamilyKit.color(MenuColor.ink))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: message)
                    .font(.system(size: 17))
                    .foregroundColor(FamilyKit.color(MenuColor.ink))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                button(save, fill: 0xffb8d9ff, text: MenuColor.ink, action: onSave)
                button(discard, fill: 0xffe91e63, text: 0xffffffff, action: onDiscard)
                button(cancel, fill: 0xffe8e0ff, text: MenuColor.ink, action: onCancel)
            }
            .padding(24)
        }

        private func button(_ title: String, fill: UInt32, text: UInt32, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(verbatim: title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(FamilyKit.color(text))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            }
            .buttonStyle(SkyButtonStyle(color: fill, cornerRadius: 16))
            .padding(.top, 18)
        }
    }
}

// MARK: Reading width (Android FamilyReadingPanel)

extension FamilyKit {
    /// Android `FamilyReadingPanel.contentWidth`: in portrait the full width; in landscape a centred
    /// column of about half the window, at least 300 and at most 520 points (never wider than
    /// available). Android decides landscape by the screen's width and height.
    static func readingWidth(_ available: CGFloat, landscape: Bool) -> CGFloat {
        if !landscape { return available }
        return min(available, min(520, max(300, available * 0.52)))
    }

    /// Android `FamilyReadingPanel`: lays its content out at `readingWidth` of the width it is offered,
    /// centred at the top, and itself takes the full width. Use it inside a page's scroll view:
    /// `FamilyKit.ReadingColumn(landscape: size.width > size.height) { column }`.
    struct ReadingColumn: Layout {
        let landscape: Bool

        init(landscape: Bool) {
            self.landscape = landscape
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            var natural: CGFloat = 0
            for subview in subviews {
                natural = max(natural, subview.sizeThatFits(.unspecified).width)
            }
            var available = proposal.width ?? natural
            if !available.isFinite { available = natural }
            let width = FamilyKit.readingWidth(available, landscape: landscape)
            var height: CGFloat = 0
            for subview in subviews {
                height = max(height, subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height)
            }
            return CGSize(width: available, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let width = FamilyKit.readingWidth(bounds.width, landscape: landscape)
            for subview in subviews {
                subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                              proposal: ProposedViewSize(width: width, height: bounds.height))
            }
        }
    }
}

// MARK: Landscape reminder (Android FamilyLandscapeHint)

extension FamilyKit {
    /// Android `FamilyLandscapeHint.show`: 0.9 s after a game appears, if its view is taller than wide,
    /// "For a wider view, play in landscape." shows for 3.5 s near the bottom (a Toast). It never
    /// takes touches or moves the HUD, and shows at most once per appearance. Apply it to the game
    /// view: `.modifier(FamilyKit.LandscapeHint())`. `language` overrides `FamilyMessages`' language.
    @MainActor
    struct LandscapeHint: ViewModifier {
        let language: String?
        @State private var checked = false
        @State private var showing = false

        init(language: String? = nil) {
            self.language = language
        }

        func body(content: Content) -> some View {
            content.overlay {
                GeometryReader { geo in
                    let portrait = geo.size.height > geo.size.width
                    ZStack {
                        Color.clear
                        if showing {
                            Toast(text)
                        }
                    }
                    .task(id: portrait) {
                        if checked { return }
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        if Task.isCancelled || checked { return }
                        checked = true
                        if !portrait { return }
                        showing = true
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        showing = false
                    }
                    .onDisappear {
                        // Entering the game again is a new appearance.
                        checked = false
                        showing = false
                    }
                }
                .allowsHitTesting(false)
            }
        }

        private var text: String {
            let en = "For a wider view, play in landscape.", he = "לתצוגה רחבה יותר, שחקו במצב אופקי."
            if let language = language { return FamilyMessages.text(en, he, language: language) }
            return FamilyMessages.shared.text(en, he)
        }
    }
}

// MARK: Form fields (Android FamilyFormStyle)

extension FamilyKit {
    /// Android `FamilyFormStyle` colours.
    enum FormColor {
        static let text: UInt32 = 0xff17384d
        static let hint: UInt32 = 0xff536b7b
        static let border: UInt32 = 0xff879baa
        static let focusedBorder: UInt32 = 0xff2587d6
        static let fill: UInt32 = 0xffffffff
    }

    /// Android `FamilyFormStyle.apply` for a text field: dark text on white with 8-point corners and a
    /// 1-point border (blue while focused), at least 12 x 8 points of padding and 48 points tall. Pass
    /// the field's focus state; use `FormColor.hint` for its prompt. Android also flattens information
    /// labels that sat on raised sky faces: give those a plain 8-point rounded fill instead.
    struct FormField: ViewModifier {
        let focused: Bool
        let minHeight: CGFloat

        init(focused: Bool, minHeight: CGFloat = 48) {
            self.focused = focused
            self.minHeight = minHeight
        }

        func body(content: Content) -> some View {
            content
                .foregroundColor(FamilyKit.color(FormColor.text))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .circular).fill(FamilyKit.color(FormColor.fill)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .circular)
                    .strokeBorder(FamilyKit.color(focused ? FormColor.focusedBorder : FormColor.border), lineWidth: 1))
        }
    }
}
