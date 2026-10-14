import SwiftUI

// MARK: Menu sections (Android FamilyMenu)

extension FamilyKit {
    /// Android `FamilyMenu` colours: each home section and its buttons share one colour.
    enum MenuColor {
        static let learn: UInt32 = 0xffb8d9ff
        static let play: UInt32 = 0xffb9f4dc
        static let saved: UInt32 = 0xffe8dcff
        static let advanced: UInt32 = 0xffffe082
        static let link: UInt32 = 0xff2869bd
        static let ink: UInt32 = 0xff282d4e
    }

    /// Android `FamilyMenu.section`: a raised light panel outlined in the section colour, an ink title
    /// and a − / + sign that opens and closes it. The host keeps the open state (Android stores it per
    /// title in "family_menu_sections"; the first two sections start open) and toggles it.
    struct MenuSection<Content: View>: View {
        let title: String
        let color: UInt32
        let open: Bool
        let toggle: () -> Void
        let content: Content

        init(_ title: String, color: UInt32, open: Bool, toggle: @escaping () -> Void, @ViewBuilder content: () -> Content) {
            self.title = title
            self.color = color
            self.open = open
            self.toggle = toggle
            self.content = content()
        }

        var body: some View {
            VStack(spacing: 0) {
                Button(action: toggle) {
                    HStack(spacing: 0) {
                        Text(verbatim: title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(FamilyKit.color(MenuColor.ink))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: open ? "−" : "+")
                            .font(.system(size: 26))
                            .foregroundColor(FamilyKit.color(MenuColor.ink))
                            .frame(width: 42, height: 48)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: title + (open ? ", −" : ", +")))
                if open {
                    VStack(spacing: 0) {
                        content
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(SkySurface(color: color, cornerRadius: 18, panel: true, strokeWidth: 2, strokeColor: color))
            .padding(.bottom, 14)
        }
    }

    /// Android `FamilyMenu.style`: a section button on a raised face in the section colour, ink text,
    /// 15-point corners. The label keeps its own font, padding and height (the apps use 54 or 64).
    struct MenuButtonStyle: ButtonStyle {
        let color: UInt32

        init(color: UInt32) {
            self.color = color
        }

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(FamilyKit.color(MenuColor.ink))
                .background(SkySurface(color: color, cornerRadius: 15, pressed: configuration.isPressed))
                .contentShape(Rectangle())
        }
    }
}


// MARK: "More below" (Android FamilyMoreFrame)

/// Where the menu content and its scroll view are on screen; updating it redraws nothing.
private final class FamilyKitMoreBelowTracker {
    var content = CGRect.zero
    var viewport = CGRect.zero
}

private struct FamilyKitMoreBelowMarker: Hashable {
    let index: Int
}

/// Reports a view's frame in global coordinates when it appears and whenever it moves, as
/// scrolling does.
@MainActor
private struct FamilyKitFrameProbe: View {
    let report: @MainActor (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.frame(in: .global)) }
                .onChange(of: proxy.frame(in: .global)) { _, rect in
                    report(rect)
                }
        }
    }
}

extension FamilyKit {
    /// Android `FamilyMoreFrame`: a vertical scroll view with a reserved 48-point row below it. While
    /// more of the menu lies below, the row shows "More below" and a gently bouncing arrow (still with
    /// Reduce Motion or VoiceOver); tapping it scrolls down by 65% of the view. At the bottom the cue
    /// hides but keeps its row, so it never covers an action. `light` is the dark-ink variant for
    /// light pages (Android "family-menu-light", Squash/Volley); the default suits scenery.
    /// `language` overrides `FamilyMessages`' language for the cue text.
    @MainActor
    struct MoreBelowScroll<Content: View>: View {
        let light: Bool
        let language: String?
        let content: Content
        @State private var tracker = FamilyKitMoreBelowTracker()
        @State private var canScrollDown = false
        @State private var markerCount = 1
        @State private var bouncing = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

        private static var step: CGFloat { return 16 }

        init(light: Bool = false, language: String? = nil, @ViewBuilder content: () -> Content) {
            self.light = light
            self.language = language
            self.content = content()
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        content
                            .background(FamilyKitFrameProbe { rect in
                                tracker.content = rect
                                refresh()
                            })
                            .overlay(alignment: .top) {
                                markers
                            }
                    }
                    .background(FamilyKitFrameProbe { rect in
                        tracker.viewport = rect
                        refresh()
                    })
                    cue(proxy)
                }
            }
        }

        /// Android `canScrollVertically(1)`, and enough scroll targets for the content's height.
        private func refresh() {
            let more = tracker.viewport.height > 0 && tracker.content.maxY > tracker.viewport.maxY + 1
            if more != canScrollDown { canScrollDown = more }
            let count = max(1, Int((tracker.content.height / MoreBelowScroll.step).rounded(.up)) + 1)
            if count != markerCount { markerCount = count }
        }

        /// Invisible scroll targets every 16 points down the content, for `scrollTo`.
        private var markers: some View {
            VStack(spacing: 0) {
                ForEach(0..<markerCount, id: \.self) { index in
                    Color.clear
                        .frame(height: MoreBelowScroll.step)
                        .id(FamilyKitMoreBelowMarker(index: index))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private func text(_ en: String, _ he: String) -> String {
            if let language = language { return FamilyMessages.text(en, he, language: language) }
            return FamilyMessages.shared.text(en, he)
        }

        private func cue(_ proxy: ScrollViewProxy) -> some View {
            let show = canScrollDown
            let animate = show && !voiceOver && !reduceMotion
            return Button {
                // Android `smoothScrollBy(0, height * .65)`.
                let scrolled = max(0, tracker.viewport.minY - tracker.content.minY)
                let index = max(0, Int((scrolled + tracker.viewport.height * 0.65) / MoreBelowScroll.step))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(FamilyKitMoreBelowMarker(index: index), anchor: .top)
                }
            } label: {
                HStack(spacing: 0) {
                    Text(verbatim: text("More below", "עוד למטה"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FamilyKit.color(light ? 0xff183652 : 0xfff7fbff))
                        .shadow(color: FamilyKit.color(light ? 0xfff7fbff : 0xff102039), radius: 1, x: 0, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(FamilyKit.color(light ? 0xff245477 : 0xffffdf77))
                        .shadow(color: .black, radius: 1, x: 0, y: 1)
                        .frame(width: 38, height: 44)
                        .offset(y: bouncing ? 4 : 0)
                        .animation(animate ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default, value: bouncing)
                }
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(show ? 1 : 0)
            .allowsHitTesting(show)
            .accessibilityLabel(Text(verbatim: text("More options below. Tap to scroll", "עוד אפשרויות למטה. הקישו לגלילה")))
            .accessibilityHidden(!show)
            .onChange(of: animate, initial: true) { _, now in
                bouncing = now
            }
        }
    }
}
