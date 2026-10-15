import SwiftUI

// Android MinikCrossPong 1dbfe33: match results over the court (MatchResultDialog) in every app language (MatchResultWords).

/// Android MatchResultWords: result copy for every supported interface language, without guessing a person's gender. A
/// house character's Hebrew and Arabic sentence agrees with the character; a person gets a neutral sentence. Names are
/// isolated (U+2068…U+2069), so a Latin name keeps a Hebrew or Arabic sentence in order.
enum MPResultWords {
    private static let femaleHousePlayers: Set<String> = ["kyra", "gaya", "mia", "amber"]
    private static let maleHousePlayers: Set<String> = ["minik", "flare", "miniko", "moshiko", "coach67"]
    static func winner(_ name: String, houseCharacter: String? = nil, language: String = MPText.language) -> String {
        let isolated = "\u{2068}\(name)\u{2069}"
        let female = houseCharacter.map { femaleHousePlayers.contains($0) } ?? false
        let male = houseCharacter.map { maleHousePlayers.contains($0) } ?? false
        switch language {
        case "he":
            if female { return "\(isolated) ניצחה במשחק הזה!" }
            if male { return "\(isolated) ניצח במשחק הזה!" }
            return "כל הכבוד ל־\(isolated) על הניצחון!"
        case "ar": return female ? "فازت \(isolated) بهذه المباراة!" : "تهانينا لـ\(isolated) على الفوز بهذه المباراة!"
        case "es": return "¡\(isolated) ganó este partido!"
        case "hi": return "\(isolated) ने यह मैच जीत लिया!"
        case "nl": return "\(isolated) heeft deze wedstrijd gewonnen!"
        default: return "\(isolated) won this match!"
        }
    }
    static func scores(_ language: String = MPText.language) -> String {
        switch language {
        case "he": return "תוצאות המשחק"
        case "ar": return "نتائج المباراة"
        case "es": return "Resultados del partido"
        case "hi": return "मैच के नतीजे"
        case "nl": return "Wedstrijdresultaten"
        default: return "Match results"
        }
    }
    static func youWon(_ language: String = MPText.language) -> String {
        switch language {
        case "he": return "ניצחתם במשחק הזה!"
        case "ar": return "لقد فزت بهذه المباراة!"
        case "es": return "¡Ganaste este partido!"
        case "hi": return "आपने यह मैच जीत लिया!"
        case "nl": return "Je hebt deze wedstrijd gewonnen!"
        default: return "You won this match!"
        }
    }
}

/// One player of a result card, in finishing order.
struct MPXResultRow: Equatable {
    var name: String
    var score: Int
    var winner = false
}

/// Android MatchResultDialog: a translucent result card over the real court, on a dimmed screen (Android also blurs it from
/// Android 12; here the court is not blurred, so a live SpriteKit view never renders through a filter). Rank, name and score
/// are separate columns that follow the interface direction. Put it over the whole screen; it takes every touch until one of
/// its buttons closes it.
struct MPXResultCard: View {
    struct Action { let title: String; let close: () -> Void }
    let title: String
    let rows: [MPXResultRow]
    let primary: Action
    var secondary: Action? = nil
    var note = ""
    @State private var closed = false

    private static let gold = FamilyKit.color(0xffffe59d)
    private static let accents: [UInt32] = [0xffffe59d, 0xffa6dcff, 0xffb1eddb, 0xffffb9df]

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.opacity(0.62).ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    panel(wide: wide)
                    ScrollView { panel(wide: wide) }
                }
                .frame(width: max(0, min(geo.size.width - 32, 620)))
                .frame(maxHeight: geo.size.height * 0.84)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        // 0x33 = 20% opacity; the texts and buttons stay fully opaque.
                        .fill(LinearGradient(colors: [FamilyKit.color(0x33315c8c), FamilyKit.color(0x33263167)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(FamilyKit.color(0xb3b9dfff), lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func panel(wide: Bool) -> some View {
        VStack(spacing: 0) {
            line("★  " + MPResultWords.scores(), size: wide ? 14 : 16, color: Self.gold).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            line(title, size: wide ? 22 : 26, color: Self.gold).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, 6).padding(.bottom, wide ? 8 : 16)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let accent = FamilyKit.color(Self.accents[index % Self.accents.count])
                HStack(spacing: 0) {
                    line(Self.number(index + 1), size: 18, color: accent).frame(width: 30)
                    line(row.name, size: wide ? 18 : 21).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                    line(Self.number(row.score), size: wide ? 22 : 25, color: accent).frame(width: 48)
                }
                .padding(.horizontal, 8).padding(.vertical, 5).frame(minHeight: wide ? 38 : 50)
                .background {
                    if row.winner {
                        RoundedRectangle(cornerRadius: 14).fill(FamilyKit.color(0x22ffe59d))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(FamilyKit.color(0x99ffe59d), lineWidth: 1))
                    }
                }
                .padding(.bottom, 4)
            }
            if !note.isEmpty {
                line(note, size: 15, color: FamilyKit.color(0xffd9ecff), bold: false).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10).padding(.bottom, 4)
            }
            HStack(spacing: 12) {
                button(primary, color: 0xffa6dcff)
                if let secondary { button(secondary, color: 0xffffb9cf) }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20).padding(.vertical, wide ? 12 : 22)
    }

    private func line(_ value: String, size: CGFloat, color: Color = .white, bold: Bool = true) -> some View {
        Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: FamilyKit.color(0xaa091c37), radius: 2, x: 0, y: 1)
    }

    private func button(_ action: Action, color: UInt32) -> some View {
        Button {
            guard !closed else { return }
            closed = true
            action.close()
        } label: {
            Text(action.title).font(.system(size: 18, weight: .bold)).foregroundStyle(FamilyKit.color(0xff17384d))
                .multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(FamilyKit.SkyButtonStyle(color: color, cornerRadius: 16))
    }

    /// Android `NumberFormat.getIntegerInstance(language)`: Arabic shows Arabic-Indic digits.
    private static func number(_ value: Int) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: MPText.language)
        format.numberStyle = .decimal
        return format.string(from: NSNumber(value: value)) ?? String(value)
    }
}
