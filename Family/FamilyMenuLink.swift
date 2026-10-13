import SwiftUI

/// Android `FamilyMenu.link`: the quiet "More Minik apps & games" link, never a regular app button.
/// Bold, underlined, the family link blue on a faint backing, at least 48 points tall.
struct FamilyMenuLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 17, weight: .bold))
                .underline()
                .foregroundColor(Color(red: 0x28 / 255, green: 0x69 / 255, blue: 0xbd / 255))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0xf7 / 255, green: 0xfb / 255, blue: 1, opacity: 0xee / 255)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
