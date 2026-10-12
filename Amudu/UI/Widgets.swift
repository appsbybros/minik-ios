import SwiftUI
import UIKit

extension Color {
    /// Android ARGB int (0xAARRGGBB).
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xff) / 255,
                  green: Double((argb >> 8) & 0xff) / 255,
                  blue: Double(argb & 0xff) / 255,
                  opacity: Double((argb >> 24) & 0xff) / 255)
    }
}

/// Android `label(s, size, color)`: bold, centered, 9/7 padding.
struct AmuduLabel: View {
    let text: String
    var size: CGFloat = 18
    var color: UInt32 = 0xffffffff

    init(_ text: String, size: CGFloat = 18, color: UInt32 = 0xffffffff) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(Color(argb: color))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
    }
}

/// Android setup `fieldTitle(title)`: a 17 sp label 20 dp below the previous field.
struct FieldTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        AmuduLabel(text, size: 17)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

/// Android `button(s, color)`: 54 dp, 18 dp corners, dark bold text.
struct AmuduButton: View {
    let title: String
    var color: UInt32 = 0xffb8f3dc
    let action: () -> Void

    init(_ title: String, color: UInt32 = 0xffb8f3dc, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: 0xff12324a))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: color)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

/// Android `page(title)`: the arena picture at 40% over navy, a scrolling column and a 28 sp title.
struct AmuduPage<Content: View>: View {
    let title: String
    let background: UIImage
    let content: Content

    init(_ title: String, background: UIImage, @ViewBuilder content: () -> Content) {
        self.title = title
        self.background = background
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color(argb: 0xff0b2036).ignoresSafeArea()
            GeometryReader { geo in
                Image(uiImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.40)
            }
            .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    AmuduLabel(title, size: 28)
                    content
                }
                .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
            }
        }
    }
}

/// Android `FamilyMenu` colours: each home section and its buttons share one colour.
enum MenuColors {
    static let learn: UInt32 = 0xffb8d9ff
    static let play: UInt32 = 0xffb9f4dc
    static let saved: UInt32 = 0xffe8dcff
    static let advanced: UInt32 = 0xffffe082
    static let ink: UInt32 = 0xff282d4e
}

/// Android `FamilyMenu.section`: a bordered home section with a white title and a − / + sign that opens and closes it.
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
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color(argb: 0xff18243a), radius: 1, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(open ? "−" : "+")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .shadow(color: Color(argb: 0xff18243a), radius: 1, x: 0, y: 1)
                        .frame(width: 42, height: 48)
                }
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + (open ? ", −" : ", +"))
            if open {
                VStack(spacing: 0) {
                    content
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(argb: color), lineWidth: 2))
        .padding(.bottom, 14)
    }
}

/// Android `FamilyMenu.style`: a section's button in the section colour with dark ink and 15 dp corners.
struct SectionButton: View {
    let title: String
    let color: UInt32
    let action: () -> Void

    init(_ title: String, color: UInt32, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: MenuColors.ink))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 15).fill(Color(argb: color)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Android `CenteredToggleSpan`: a drawn minus (open) or plus (closed) as wide as 1.5 letters.
private struct ToggleSign: Shape {
    let expanded: Bool
    let textSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.minX + textSize * 0.68
        let cy = rect.midY
        let radius = textSize * 0.48
        p.move(to: CGPoint(x: cx - radius, y: cy))
        p.addLine(to: CGPoint(x: cx + radius, y: cy))
        if !expanded {
            p.move(to: CGPoint(x: cx, y: cy - radius))
            p.addLine(to: CGPoint(x: cx, y: cy + radius))
        }
        return p
    }
}

/// Android setup `group(title)`: a lilac button that opens or closes the rules below it.
struct GroupToggle: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ToggleSign(expanded: expanded, textSize: 16)
                    .stroke(Color(argb: 0xff12324a), style: StrokeStyle(lineWidth: 16 * 0.14, lineCap: .round))
                    .frame(width: 24, height: 24)
                Text("  " + title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: 0xff12324a))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: 0xffdfcfff)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .accessibilityLabel((expanded ? "−  " : "+  ") + title)
    }
}

/// Android `PictureChoices.Option`.
struct PictureOption: Identifiable {
    let id: String
    let name: String
    let image: UIImage
}

/// Android `PictureChoices`: small, visible photo choices, three per row; choosing never rebuilds or scrolls the form.
struct PictureChoices: View {
    let options: [PictureOption]
    let selected: String
    let arena: Bool
    let onSelected: (String) -> Void

    private var rows: [[PictureOption]] {
        return stride(from: 0, to: options.count, by: 3).map { Array(options[$0..<min($0 + 3, options.count)]) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { option in card(option) }
                    ForEach(0..<(3 - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    @ViewBuilder private func picture(_ option: PictureOption) -> some View {
        if arena {
            // Keep the horizon and landmarks visible instead of cropping to the ground.
            Image(uiImage: option.image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .top)
                .clipped()
        } else {
            Image(uiImage: option.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
        }
    }

    private func card(_ option: PictureOption) -> some View {
        let isSelected = option.id == selected
        return Button {
            if option.id != selected { onSelected(option.id) }
        } label: {
            VStack(spacing: 0) {
                picture(option)
                    .accessibilityHidden(true)
                Text(option.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(argb: isSelected ? 0xff12324a : 0xfff4faff))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 2)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, minHeight: 43)
            }
            .padding(EdgeInsets(top: 6, leading: 5, bottom: 5, trailing: 5))
            .background(RoundedRectangle(cornerRadius: 15).fill(Color(argb: isSelected ? 0xffc5ecff : 0xff153c54)))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(argb: isSelected ? 0xff72d4ff : 0xff4e748a), lineWidth: isSelected ? 3 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Android `Switch` on the settings page: white text, the app's cyan accent.
struct SettingSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var minHeight: CGFloat = 56

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
        .tint(Color(argb: 0xff00e5ff))
        .frame(minHeight: minHeight)
    }
}

/// Android `GameDialogBuilder`: a light dialog (#F7FAFC) with dark text, used for dialogs that update while open.
struct DialogCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(argb: 0xff17384d))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                content
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(argb: 0xfff7fafc)))
            .padding(.horizontal, 22)
        }
    }
}

/// Android dialog button (positive or neutral): bold #174963 text at the end of the dialog.
struct DialogTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: action) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(argb: 0xff174963))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Android `Intent.createChooser` for text: the system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Android `JourneyCelebration`: a finite celebration; with Reduce Motion it is the same still badge.
struct JourneyCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var born = Date()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done || reduceMotion)) { timeline in
            Canvas { context, size in
                draw(&context, size, timeline.date.timeIntervalSince(born))
            }
        }
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            done = true
        }
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ elapsed: Double) {
        let motion = !reduceMotion
        let t = motion ? min(elapsed, 1.8) : 1.8
        let cx = size.width / 2
        let cy = size.height / 2
        let r = size.height * 0.29
        let colors: [UInt32] = [0xffffd769, 0xff93f2d2, 0xffc4b2ff, 0xffffb8c9]
        // Android draws the confetti in pixels: 8 x 14 with 2 px corners.
        let px = 1 / max(displayScale, 1)
        for i in 0..<20 {
            let angle = Double(i) * 2 * Double.pi / 20
            let radius = r * (1.5 + CGFloat(min(t, 1)) * 0.85)
            let x = cx + CGFloat(cos(angle)) * radius
            let y = cy + CGFloat(sin(angle)) * radius * 0.63
            var piece = context
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .degrees(Double(i) * 31 + t * 75))
            let alpha: Double = (elapsed < 1.8 && motion) ? 1 : 190.0 / 255.0
            let shape = Path(roundedRect: CGRect(x: -4 * px, y: -7 * px, width: 8 * px, height: 14 * px), cornerRadius: 2 * px)
            piece.fill(shape, with: .color(Color(argb: colors[i % 4]).opacity(alpha)))
        }
        context.fill(Path(ellipseIn: CGRect(x: cx - r * 1.12, y: cy - r * 1.12, width: r * 2.24, height: r * 2.24)), with: .color(Color(argb: 0xff173f55)))
        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(Color(argb: colors[0])))
        var check = Path()
        check.move(to: CGPoint(x: cx - r * 0.43, y: cy))
        check.addLine(to: CGPoint(x: cx - r * 0.08, y: cy + r * 0.29))
        check.addLine(to: CGPoint(x: cx + r * 0.47, y: cy - r * 0.3))
        context.stroke(check, with: .color(Color(argb: 0xff173f55)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
    }
}

private struct StarShape: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let step = rect.width / 5
        let r = min(step * 0.44, rect.height * 0.43)
        let x = step * (CGFloat(index) + 0.5)
        let y = rect.height / 2
        var outline = Path()
        for j in 0..<10 {
            let a = -Double.pi / 2 + Double(j) * Double.pi / 5
            let radius = j % 2 == 0 ? r : r * 0.44
            let point = CGPoint(x: x + CGFloat(cos(a)) * radius, y: y + CGFloat(sin(a)) * radius)
            if j == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
        }
        outline.closeSubpath()
        return outline
    }
}

/// Android `SkillStars`: five stars, filled gold up to the rating, thin grey outlines after it.
struct SkillStars: View {
    let value: Int

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                if i < value {
                    StarShape(index: i).fill(Color(argb: 0xffffdd63))
                } else {
                    StarShape(index: i).stroke(Color(argb: 0xffb7bdc8), lineWidth: 1)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(value) / 5")
    }
}

private struct ChevronShape: Shape {
    let right: Bool

    func path(in rect: CGRect) -> Path {
        let sign: CGFloat = right ? 1 : -1
        let cx = rect.midX
        let cy = rect.midY
        var outline = Path()
        outline.move(to: CGPoint(x: cx - sign * 10, y: cy - 19))
        outline.addLine(to: CGPoint(x: cx + sign * 10, y: cy))
        outline.addLine(to: CGPoint(x: cx - sign * 10, y: cy + 19))
        return outline
    }
}

/// Android `AvatarArrow`: a thick rounded chevron in a 64x72 touch target.
struct AvatarArrow: View {
    let right: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChevronShape(right: right)
                .stroke(Color(argb: 0xffb8f3dc), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: 64, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppText.t(right ? "Next avatar" : "Previous avatar"))
    }
}

/// Android `ic_dropdown` vector (24x24 viewport).
private struct DropdownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var outline = Path()
        outline.move(to: p(5.4, 8.6))
        outline.addLine(to: p(12, 15.2))
        outline.addLine(to: p(18.6, 8.6))
        outline.addLine(to: p(20, 10))
        outline.addLine(to: p(12, 18))
        outline.addLine(to: p(4, 10))
        outline.closeSubpath()
        return outline
    }
}

/// Android setup `choice()`: a field title above a light rounded field with a dropdown chevron.
struct ChoiceMenu: View {
    let title: String
    let items: [String]
    let selected: Int
    let change: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FieldTitle(title)
            Menu {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        if i != selected { change(i) }
                    } label: {
                        if i == selected {
                            Label(items[i], systemImage: "checkmark")
                        } else {
                            Text(items[i])
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selected >= 0 && selected < items.count ? items[selected] : "")
                        .font(.system(size: 16))
                        .foregroundColor(Color(argb: 0xff14324a))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DropdownShape()
                        .fill(Color(argb: 0xff14324a))
                        .frame(width: 28, height: 28)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: items.contains(where: { $0.count > 44 }) ? 82 : 54)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: 0xffe3f4ff)))
                .contentShape(Rectangle())
            }
        }
    }
}

/// Android `CheckBox` row: white 17 sp text, cyan accent, disabled for the player's own avatar.
struct HouseCheck: View {
    let title: String
    let checked: Bool
    let enabled: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        Button {
            toggle(!checked)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(checked ? Color(argb: 0xff00e5ff) : Color.white, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if checked {
                        RoundedRectangle(cornerRadius: 3).fill(Color(argb: 0xff00e5ff)).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(argb: 0xff0b2036))
                    }
                }
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Android `Toast`.
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
    }
}
