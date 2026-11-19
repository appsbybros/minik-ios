import SwiftUI
import UIKit

/// Android `ui/GameDialogBuilder` + `ui/SpudDialogStyle` (2026-11): every small SPUD dialog shares one presentation —
/// a pale sky panel (0xfff2faff, 24 dp corners, a 1 dp 0xffbcd8e9 outline) at most 460 dp wide, a pink × at the top end
/// when it may be closed, a 23 sp bold blue title in the centre, an 18 sp ink message, white inputs, list rows and
/// 56 dp raised actions with 14 dp corners. A Back/Cancel negative is replaced by the × (unless the dialog keeps its
/// back action, as the pause dialog does); the remaining negative is pink with white text, a positive "Continue" (or a
/// green primary) is mint and every other action is sky blue. Two actions sit side by side (negative first, then
/// positive); three or more stack in portrait with the principal action first.
enum SpudDialogTone {
    case blue
    case green
    case pink

    var fill: UInt32 {
        switch self {
        case .blue: return 0xffa6dcff
        case .green: return 0xffb1eddb
        case .pink: return 0xffe91e63
        }
    }

    var ink: UInt32 { return self == .pink ? 0xffffffff : SpudDialogStyle.ink }
}

struct SpudDialogAction: Identifiable {
    let id = UUID()
    let title: String
    let tone: SpudDialogTone
    /// Android dialog buttons close the dialog before their listener runs.
    let run: @MainActor () -> Void
}

/// An EditText inside a dialog (`setView(input)`).
struct SpudDialogField {
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization? = .sentences
    /// Android `InputFilter.LengthFilter` (UTF-16 units).
    var limit: Int? = nil
    var minLines = 1
}

struct SpudDialogRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String?
    var field: SpudDialogField?
    /// Android `setItems`: tapping a row closes the dialog and runs `onItem`.
    var items: [String] = []
    var onItem: (@MainActor (Int) -> Void)?
    /// Display order (already arranged like `SpudDialogStyle`).
    var actions: [SpudDialogAction] = []
    /// Stack the actions vertically (more than two actions in portrait).
    var stacked = false
    var allowClose = true
    /// The × and a tap outside: Android `cancel.performClick()` or `dialog.cancel()` (its OnCancelListener).
    var onClose: (@MainActor () -> Void)?
}

enum SpudDialogStyle {
    static let ink: UInt32 = 0xff17384d
    static let blue: UInt32 = 0xff1d70b0
    static let panel: UInt32 = 0xfff2faff
    static let outline: UInt32 = 0xffbcd8e9
    static let pink: UInt32 = 0xffe91e63

    private static func isBackText(_ text: String) -> Bool {
        let he = AppText.language == "he"
        return ["Back", "Cancel", "חזרה", "ביטול", GameText.t("Back", "חזרה", hebrew: he), GameText.t("Cancel", "ביטול", hebrew: he)].contains(text)
    }

    private static func isContinue(_ text: String) -> Bool {
        let he = AppText.language == "he"
        return ["Continue", "המשך", GameText.t("Continue", "המשך", hebrew: he)].contains(text)
    }

    /// Android `GameDialogBuilder.show()` → `SpudDialogStyle.apply(dialog, allowClose, keepBack, greenPrimary)`: the
    /// positive (-1), neutral (-3) and negative (-2) buttons as Android collects them, minus a Back/Cancel negative,
    /// which the × replaces. `onCancel` is the dialog's OnCancelListener.
    static func make(title: String, message: String? = nil, field: SpudDialogField? = nil, items: [String] = [],
                     onItem: (@MainActor (Int) -> Void)? = nil,
                     positive: (String, @MainActor () -> Void)? = nil, neutral: (String, @MainActor () -> Void)? = nil,
                     negative: (String, @MainActor () -> Void)? = nil, allowClose: Bool = true, keepBack: Bool = false,
                     greenPrimary: Bool = false, onCancel: (@MainActor () -> Void)? = nil,
                     landscape: Bool = false) -> SpudDialogRequest {
        var cancel: (@MainActor () -> Void)?
        var buttons: [SpudDialogAction] = []
        if let p = positive {
            let green = greenPrimary || isContinue(p.0)
            buttons.append(SpudDialogAction(title: p.0, tone: green ? .green : .blue, run: p.1))
        }
        if let n = neutral {
            buttons.append(SpudDialogAction(title: n.0, tone: .blue, run: n.1))
        }
        if let n = negative {
            if !keepBack && isBackText(n.0) {
                cancel = n.1
            } else {
                buttons.append(SpudDialogAction(title: n.0, tone: .pink, run: n.1))
            }
        }
        let stacked = buttons.count > 2 && !landscape
        // Negative then positive in two-column dialogs; principal action first in a stack.
        let ordered = buttons.count == 2 ? Array(buttons.reversed()) : buttons
        return SpudDialogRequest(title: title, message: message, field: field, items: items, onItem: onItem, actions: ordered,
                                 stacked: stacked, allowClose: allowClose, onClose: cancel ?? onCancel)
    }
}

/// The panel shared by every SPUD dialog: the dimmed backdrop, the pale sky panel, the × and the centred blue title.
struct SpudDialogPanel<Content: View>: View {
    let title: String
    let allowClose: Bool
    var maxWidth: CGFloat = 460
    let onClose: () -> Void
    let content: Content

    init(title: String, allowClose: Bool, maxWidth: CGFloat = 460, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.allowClose = allowClose
        self.maxWidth = maxWidth
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if allowClose { onClose() } }
                VStack(spacing: 0) {
                    if allowClose {
                        HStack {
                            Spacer(minLength: 0)
                            Button(action: onClose) {
                                Text("×")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color(argb: SpudDialogStyle.pink))
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppText.t("Close", "סגירה"))
                        }
                    }
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(Color(argb: SpudDialogStyle.blue))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 16)
                    }
                    content
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(argb: SpudDialogStyle.panel))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(argb: SpudDialogStyle.outline), lineWidth: 1))
                )
                .frame(width: max(0, min(geo.size.width - 32, maxWidth)))
                .frame(maxHeight: max(0, geo.size.height - 24))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.layoutDirection, AppText.rtl ? .rightToLeft : .leftToRight)
    }
}

/// One raised dialog action (Android `FamilySkyDrawable` with 14 dp corners, 17 sp bold, 56 dp high).
struct SpudDialogButton: View {
    let title: String
    let tone: SpudDialogTone
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(argb: tone.ink))
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyButtonStyle(color: tone.fill, radius: 14))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The white input of a dialog (`SpudDialogStyle`: 18 sp, 56 dp minimum, 12 dp padding, ink and grey hint).
struct SpudDialogInput: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization? = .sentences
    var minLines = 1
    var ltr = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(argb: SkyInk.hint)), axis: minLines > 1 ? .vertical : .horizontal)
            .lineLimit(minLines > 1 ? minLines...max(minLines, 8) : 1...1)
            .font(.system(size: 18))
            .foregroundColor(Color(argb: SpudDialogStyle.ink))
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .focused($focused)
            .padding(12)
            .frame(minHeight: 56)
            .background(InputFace(focused: focused))
            .environment(\.layoutDirection, ltr ? .leftToRight : (AppText.rtl ? .rightToLeft : .leftToRight))
    }
}

/// Renders one `SpudDialogRequest`.
struct SpudDialogView: View {
    @ObservedObject var model: AppModel
    let request: SpudDialogRequest

    var body: some View {
        SpudDialogPanel(title: request.title, allowClose: request.allowClose, onClose: { model.closeDialog(request.id, cancel: true) }) {
            VStack(spacing: 0) {
                if !request.items.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(request.items.enumerated()), id: \.offset) { i, item in
                                Button {
                                    model.chooseDialogItem(request.id, i)
                                } label: {
                                    Text(item)
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(argb: SpudDialogStyle.ink))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(request.items.count) * 56, 56 * 7))
                }
                if let message = request.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 18))
                        .foregroundColor(Color(argb: SpudDialogStyle.ink))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, request.field == nil ? 0 : 8)
                }
                if let field = request.field {
                    SpudDialogInput(placeholder: field.placeholder,
                                    text: Binding(get: { model.dialogInput }, set: { model.setDialogInput($0, limit: field.limit) }),
                                    keyboard: field.keyboard, capitalization: field.capitalization, minLines: field.minLines)
                }
                if !request.actions.isEmpty {
                    if request.stacked {
                        VStack(spacing: 12) {
                            ForEach(request.actions) { a in
                                SpudDialogButton(title: a.title, tone: a.tone) { model.runDialogAction(request.id, a) }
                            }
                        }
                        .padding(.top, 20)
                    } else {
                        HStack(spacing: 16) {
                            ForEach(request.actions) { a in
                                SpudDialogButton(title: a.title, tone: a.tone) { model.runDialogAction(request.id, a) }
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
        }
    }
}

/// Android `FamilyAdultGate.open` styled by `SpudDialogStyle.apply(dialog, adult = true)`: the shared localized
/// grown-up step — "For grown-ups", the question read left to right (22 sp), a white answer field with 12 dp corners and
/// a mint Continue across the panel; Cancel became the pink ×. A tap outside does not close it.
struct AdultGateCard: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    private static let titles: [String: String] = ["en": "For grown-ups", "he": "למבוגרים", "es": "Para una persona adulta",
                                                   "ar": "لشخص بالغ", "hi": "किसी बड़े के लिए", "nl": "Voor een volwassene"]

    var body: some View {
        SpudDialogPanel(title: AdultGateCard.titles[AppText.language] ?? "For grown-ups", allowClose: true, maxWidth: 440,
                        onClose: { model.cancelGate() }) {
            VStack(spacing: 0) {
                Text(verbatim: model.gateQuestion)
                    .font(.system(size: 22))
                    .foregroundColor(Color(argb: 0xff17364a))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                TextField("", text: $model.gateInput, prompt: Text(FamilyMessages.text("Answer", "תשובה")).foregroundColor(Color(argb: 0xff52677b)))
                    .keyboardType(.numberPad)
                    .font(.system(size: 20))
                    .foregroundColor(Color(argb: 0xff17364a))
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(argb: 0xff87a8be), lineWidth: 1))
                    )
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(FamilyMessages.text("Answer", "תשובה"))
                if model.gateError {
                    Text(FamilyMessages.text("Try again.", "נסו שוב."))
                        .font(.system(size: 15))
                        .foregroundColor(Color(argb: 0xffb3261e))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                Button {
                    model.confirmGate()
                } label: {
                    Text(FamilyMessages.text("Continue", "המשך"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(argb: 0xff17364a))
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SkyButtonStyle(color: 0xff58bd8c, radius: 14))
                .padding(.top, 24)
            }
        }
        .onAppear { focused = true }
    }
}
