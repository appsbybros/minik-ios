import SwiftUI

/// The intro's child section sizes from dimens_pretty.xml: the phone values, and
/// the sw600dp ones on iPad, grown on the larger iPads as the rest of the intro
/// is. Text follows Dynamic Type through `textScale`, and the touch targets keep
/// Apple's 44-point minimum.
struct ChildProfileSectionMetrics {
    /// layout-sw600dp: the iPad draws the selector as Android's tablet layout does.
    let tablet: Bool
    let labelSize: CGFloat
    let fieldTextSize: CGFloat
    let spinnerMinHeight: CGFloat
    let fieldMinHeight: CGFloat
    let buttonTextSize: CGFloat
    let buttonMinHeight: CGFloat
    let labelToField: CGFloat
    let fieldToButtons: CGFloat
    let buttonGap: CGFloat

    init(tablet: Bool, scale: CGFloat, textScale: CGFloat) {
        self.tablet = tablet
        let size: (CGFloat, CGFloat) -> CGFloat = { phone, pad in
            tablet ? pad * scale : phone
        }
        // pretty_intro_label_text, intro_field_spinner_font_size, pretty_intro_small_button_text.
        let fieldText = size(18, 24) * textScale
        let buttonText = size(16, 22) * textScale
        labelSize = size(17, 26) * textScale
        fieldTextSize = fieldText
        buttonTextSize = buttonText
        // pretty_intro_spinner_min_height inside the 2 dp padding of pretty_intro_field_min_height.
        let spinnerHeight = max(size(40, 54), fieldText * 1.33 + 12)
        spinnerMinHeight = spinnerHeight
        fieldMinHeight = spinnerHeight + 4
        // pretty_intro_small_button_height.
        buttonMinHeight = max(size(44, 54), buttonText * 1.33 + 14)
        labelToField = size(6, 8)
        fieldToButtons = size(10, 14)
        buttonGap = size(14, 18)
    }
}

/// Android IntroScreen's child section (fragment_intro_plus.xml childSection):
/// "Child name:" over the rounded child selector, then Add and Delete as small
/// pastel pills, with Edit between them to rename the child (iOS). With no
/// child yet the caption says the name is optional, only Add shows, and the
/// selector is empty and does nothing, as on Android (setNoUsersExistView and
/// addFakeItemToNameSpinner: one empty item in a disabled spinner).
struct ChildProfileSection: View {
    @ObservedObject var store: ChildProfileStore
    let metrics: ChildProfileSectionMetrics
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let onEdit: (ChildProfile) -> Void
    let onDelete: (ChildProfile) -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID

    init(
        store: ChildProfileStore,
        metrics: ChildProfileSectionMetrics,
        onSelect: @escaping (UUID) -> Void,
        onAdd: @escaping () -> Void,
        onEdit: @escaping (ChildProfile) -> Void,
        onDelete: @escaping (ChildProfile) -> Void
    ) {
        self.store = store
        self.metrics = metrics
        self.onSelect = onSelect
        self.onAdd = onAdd
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: caption)
                .font(MinikPretty.bodyFont(metrics.labelSize))
                .foregroundStyle(MinikPretty.navy)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The selector reads the caption as its own label.
                .accessibilityHidden(true)
            selector
                .padding(.top, metrics.labelToField)
            actions
                .padding(.top, metrics.fieldToButtons)
        }
    }

    /// Android's title_with_colon, or field_label_optional while no child exists.
    private var caption: String {
        if store.children.isEmpty {
            return interfaceLocaleID.text("Child name (optional):")
        }
        return interfaceLocaleID.text("Child name:")
    }

    /// bg_pretty_field around the spinner: the chosen child, and the other
    /// children in a menu. With no child the field stays empty and a tap does
    /// nothing, like Android's disabled spinner.
    @ViewBuilder
    private var selector: some View {
        if store.children.isEmpty {
            field(name: "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: interfaceLocaleID.text("Child name")))
        } else {
            Menu {
                ForEach(store.children) { child in
                    Button {
                        onSelect(child.id)
                    } label: {
                        menuRow(child)
                    }
                }
            } label: {
                field(name: store.selectedChild?.name ?? "")
            }
            .menuOrder(.fixed)
            .accessibilityLabel(Text(verbatim: interfaceLocaleID.text("Child name")))
            .accessibilityValue(Text(verbatim: store.selectedChild?.name ?? ""))
            .accessibilityHint(Text(verbatim: interfaceLocaleID.text("Chooses which child is playing")))
        }
    }

    @ViewBuilder
    private func menuRow(_ child: ChildProfile) -> some View {
        if child.id == store.selectedChildID {
            Label(child.name, systemImage: "checkmark")
        } else {
            Text(verbatim: child.name)
        }
    }

    /// The white field with the lavender rim (bg_pretty_field) around Android's
    /// spinner face.
    private func field(name: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return spinnerFace(name: name)
            .padding(2)
            .frame(maxWidth: .infinity, minHeight: metrics.fieldMinHeight)
            .background(Color.white, in: shape)
            .overlay {
                shape.strokeBorder(MinikPretty.lavenderRim, lineWidth: 2)
            }
            .contentShape(shape)
    }

    /// The spinner's face, with or without a child. Phones: bg_spinner_arrow, a
    /// grey-rimmed white face with the down arrow at the end. iPad: the sw600dp
    /// layout's bg_minik_white_pill, plain white with no arrow (paddingEnd 18dp).
    @ViewBuilder
    private func spinnerFace(name: String) -> some View {
        if metrics.tablet {
            Text(verbatim: name)
                .font(.system(size: metrics.fieldTextSize))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 17)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, minHeight: metrics.spinnerMinHeight)
        } else {
            LanguageParentDropdownLabel(
                title: name,
                fontSize: metrics.fieldTextSize,
                minHeight: metrics.spinnerMinHeight,
                showsArrow: true
            )
        }
    }

    /// addUserButton and deleteUserButton side by side, with Edit between them.
    private var actions: some View {
        HStack(spacing: metrics.buttonGap) {
            if store.canAddChild {
                Button(action: onAdd) {
                    Text(verbatim: interfaceLocaleID.text("Add"))
                }
                .buttonStyle(ChildProfilePillStyle(
                    look: .add,
                    fontSize: metrics.buttonTextSize,
                    minHeight: metrics.buttonMinHeight
                ))
                .accessibilityLabel(Text(verbatim: interfaceLocaleID.text("Add a child")))
            }
            if let child = store.selectedChild {
                Button {
                    onEdit(child)
                } label: {
                    Text(verbatim: interfaceLocaleID.text("Edit"))
                }
                .buttonStyle(ChildProfilePillStyle(
                    look: .edit,
                    fontSize: metrics.buttonTextSize,
                    minHeight: metrics.buttonMinHeight
                ))
                .accessibilityLabel(Text(verbatim: interfaceLocaleID.text("Edit name")))
                Button {
                    onDelete(child)
                } label: {
                    Text(verbatim: interfaceLocaleID.text("Delete"))
                }
                .buttonStyle(ChildProfilePillStyle(
                    look: .delete,
                    fontSize: metrics.buttonTextSize,
                    minHeight: metrics.buttonMinHeight
                ))
            }
        }
    }
}

/// Android's addUserButton and deleteUserButton (unelevated, 22 dp corners and a
/// white 2 dp rim): mint for Add and pink for Delete; Edit takes the design's
/// lavender with pretty_purple_text.
struct ChildProfilePillStyle: ButtonStyle {
    enum Look {
        case add
        case edit
        case delete
    }

    let look: Look
    let fontSize: CGFloat
    let minHeight: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(look: Look, fontSize: CGFloat, minHeight: CGFloat) {
        self.look = look
        self.fontSize = fontSize
        self.minHeight = minHeight
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return configuration.label
            .font(MinikPretty.titleFont(fontSize))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(Color.white, lineWidth: 2)
            }
            .overlay {
                if configuration.isPressed {
                    shape.fill(Color.black.opacity(0.06))
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var fill: Color {
        switch look {
        case .add:
            return MinikPretty.color(0xD4F6E6)
        case .edit:
            return MinikPretty.color(0xECE6FF)
        case .delete:
            return MinikPretty.color(0xFFE0EC)
        }
    }

    private var ink: Color {
        switch look {
        case .add:
            return MinikPretty.color(0x1F8A5B)
        case .edit:
            return MinikPretty.color(0x6A55D6)
        case .delete:
            return MinikPretty.color(0xC2416E)
        }
    }
}

/// What the child section asks the intro to show.
enum ChildProfileDialogRequest: Equatable {
    case add
    case rename(ChildProfile)
    case delete(ChildProfile)
}

/// Android's name entry and its "Are you sure?" AlertDialog as a card over the
/// intro in the rainbow-sky design (bg_pretty_dialog): add or rename a child,
/// or confirm a deletion. A tap outside cancels, as on Android.
struct ChildProfileDialog: View {
    let request: ChildProfileDialogRequest
    let store: ChildProfileStore
    /// Called when the dialog is done; true when another learner now plays.
    let onFinish: (Bool) -> Void
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @ScaledMetric(relativeTo: .body) private var textPercent: CGFloat = 100
    @State private var draft: String
    @State private var problem: ChildProfileNameProblem?
    @FocusState private var nameFocused: Bool

    private static let problemInk = MinikPretty.color(0xC2416E)

    init(
        request: ChildProfileDialogRequest,
        store: ChildProfileStore,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.request = request
        self.store = store
        self.onFinish = onFinish
        switch request {
        case .rename(let child):
            _draft = State(initialValue: child.name)
        case .add, .delete:
            _draft = State(initialValue: "")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let tablet = geometry.size.width >= 600
            ZStack {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: cancel)
                    .accessibilityHidden(true)
                card(sizes: ChildProfileDialogSizes(tablet: tablet, textScale: textScale))
                    .frame(width: max(1, min(geometry.size.width - 32, tablet ? 520 : 380)))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAction(.escape, cancel)
        .onAppear(perform: focusNameIfNeeded)
    }

    private func card(sizes: ChildProfileDialogSizes) -> some View {
        let shape = RoundedRectangle(cornerRadius: LanguageParentDialogBackground.cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            switch request {
            case .add, .rename:
                nameContent(sizes)
            case .delete(let child):
                deleteContent(child, sizes: sizes)
            }
        }
        .padding(.horizontal, sizes.padding)
        .padding(.top, sizes.padding)
        .padding(.bottom, sizes.padding - 2)
        .background {
            LanguageParentDialogBackground()
        }
        .overlay {
            shape
                .strokeBorder(LanguageParentPalette.dialogStroke, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private func nameContent(_ sizes: ChildProfileDialogSizes) -> some View {
        Text(verbatim: heading)
            .font(MinikPretty.titleFont(sizes.title))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
        TextField(interfaceLocaleID.text("Child name"), text: $draft)
            .font(.system(size: sizes.field))
            .foregroundStyle(Color.black)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit(save)
            .onChange(of: draft) { _, newValue in
                if newValue.count > ChildProfileLimits.maximumNameLength {
                    draft = String(newValue.prefix(ChildProfileLimits.maximumNameLength))
                }
                problem = nil
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: sizes.fieldHeight)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(problem == nil ? MinikPretty.lavenderRim : Self.problemInk, lineWidth: 2)
            }
            .padding(.top, sizes.titleGap)
        if let problem {
            Text(verbatim: problemText(problem))
                .font(MinikPretty.bodyFont(sizes.note))
                .foregroundStyle(Self.problemInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        dialogButtons(sizes) {
            Button(action: save) {
                Text(verbatim: interfaceLocaleID.text("Save"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: MinikPretty.PillLook.purple,
                fontSize: sizes.button,
                minHeight: sizes.buttonHeight
            ))
            .disabled(ChildProfileLimits.normalizedName(draft).isEmpty)
        }
    }

    @ViewBuilder
    private func deleteContent(_ child: ChildProfile, sizes: ChildProfileDialogSizes) -> some View {
        Text(verbatim: interfaceLocaleID.text("Delete"))
            .font(MinikPretty.titleFont(sizes.title))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
        Text(verbatim: child.name)
            .font(MinikPretty.titleFont(sizes.title * 0.9))
            .foregroundStyle(MinikPretty.purple)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        Text(verbatim: interfaceLocaleID.text("Are you sure you want to delete?"))
            .font(MinikPretty.bodyFont(sizes.bodyText))
            .foregroundStyle(MinikPretty.navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, sizes.titleGap)
        Text(verbatim: interfaceLocaleID.text("Points and progress saved for this child on this device will be deleted."))
            .font(MinikPretty.bodyFont(sizes.note))
            .foregroundStyle(MinikPretty.softInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        dialogButtons(sizes) {
            Button {
                confirmDeletion(of: child)
            } label: {
                Text(verbatim: interfaceLocaleID.text("Yes, delete"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: MinikPretty.PillLook.warm,
                fontSize: sizes.button,
                minHeight: sizes.buttonHeight
            ))
        }
    }

    /// Cancel and the dialog's main action side by side. The main action is the
    /// trailing button, so it is on the left in Hebrew and Arabic and on the
    /// right in left-to-right languages, as on every two-button row in the app.
    private func dialogButtons<Primary: View>(
        _ sizes: ChildProfileDialogSizes,
        @ViewBuilder primary: () -> Primary
    ) -> some View {
        HStack(spacing: 14) {
            Button(action: cancel) {
                Text(verbatim: interfaceLocaleID.text("Cancel"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MinikPretty.HeroButtonStyle(
                look: MinikPretty.PillLook.white,
                fontSize: sizes.button,
                minHeight: sizes.buttonHeight
            ))
            primary()
        }
        .padding(.top, sizes.buttonsGap)
    }

    private var heading: String {
        switch request {
        case .add:
            return interfaceLocaleID.text("Add a child")
        case .rename:
            return interfaceLocaleID.text("Edit name")
        case .delete:
            return interfaceLocaleID.text("Delete")
        }
    }

    private func problemText(_ problem: ChildProfileNameProblem) -> String {
        switch problem {
        case .empty:
            return interfaceLocaleID.text("Please enter a name.")
        case .duplicate:
            return interfaceLocaleID.text("Another child already has this name.")
        case .limitReached:
            return interfaceLocaleID.text("You can add up to 20 children.")
        }
    }

    private var textScale: CGFloat {
        min(1.4, max(0.9, textPercent / 100))
    }

    private func focusNameIfNeeded() {
        switch request {
        case .add, .rename:
            nameFocused = true
        case .delete:
            break
        }
    }

    private func save() {
        switch request {
        case .add:
            if let refusal = store.addChild(named: draft) {
                problem = refusal
            } else {
                onFinish(true)
            }
        case .rename(let child):
            if let refusal = store.renameChild(child.id, to: draft) {
                problem = refusal
            } else {
                onFinish(false)
            }
        case .delete:
            break
        }
    }

    private func confirmDeletion(of child: ChildProfile) {
        store.deleteChild(child.id)
        onFinish(true)
    }

    private func cancel() {
        onFinish(false)
    }
}

/// The dialog's sizes on phones and on iPad (the Parent Area dialog's sizes).
private struct ChildProfileDialogSizes {
    let title: CGFloat
    let bodyText: CGFloat
    let note: CGFloat
    let field: CGFloat
    let fieldHeight: CGFloat
    let button: CGFloat
    let buttonHeight: CGFloat
    let padding: CGFloat
    let titleGap: CGFloat
    let buttonsGap: CGFloat

    init(tablet: Bool, textScale: CGFloat) {
        let fieldText: CGFloat = (tablet ? 24 : 18) * textScale
        let minimumFieldHeight: CGFloat = tablet ? 56 : 48
        title = (tablet ? 32 : 24) * textScale
        bodyText = (tablet ? 24 : 18) * textScale
        note = (tablet ? 19 : 15) * textScale
        field = fieldText
        fieldHeight = max(minimumFieldHeight, fieldText * 1.33 + 16)
        button = (tablet ? 24 : 18) * textScale
        buttonHeight = tablet ? 60 : 50
        padding = tablet ? 30 : 22
        titleGap = tablet ? 22 : 18
        buttonsGap = tablet ? 28 : 22
    }
}
