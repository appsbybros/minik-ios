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

/// One player of a result card, in finishing order. Android 47ad0c9: a name may show in its seat colour (ARGB).
struct MPXResultRow: Equatable {
    var name: String
    var score: Int
    var winner = false
    var color: UInt32? = nil
}

/// Android MatchResultDialog: a translucent result card over the real court, on a dimmed screen (Android also blurs it from
/// Android 12; here the court is not blurred, so a live SpriteKit view never renders through a filter). Rank, name and score
/// are separate columns that follow the interface direction. Put it over the whole screen; it takes every touch until one of
/// its buttons closes it. Android d376d64 (readability): a 50 % white backing with dark, solid lettering and no shadow; the
/// headline and the names keep their hue but are darkened until they read on the dimmed court (`readable`); 5375378's white
/// outlines were removed again by d376d64.
struct MPXResultCard: View {
    /// Android 47ad0c9 MatchResultDialog.Action: light blue by default; the pink (#E91E63) Menu or "Back to tournament" has
    /// white lettering.
    struct Action {
        let title: String
        let color: UInt32
        let close: () -> Void
        init(title: String, color: UInt32 = 0xffa6dcff, close: @escaping () -> Void) { self.title = title; self.color = color; self.close = close }
    }
    static let pink: UInt32 = 0xffe91e63
    let title: String
    let rows: [MPXResultRow]
    let primary: Action
    var secondary: Action? = nil
    var note = ""
    @State private var closed = false

    /// Android d376d64: the dark gold heading and rank colours, and the default lettering (#142C42).
    static let gold: UInt32 = 0xff5b450d
    static let accents: [UInt32] = [0xff5b450d, 0xff183e62, 0xff104c3b, 0xff632d50]
    static let ink: UInt32 = 0xff142c42

    /// Android d376d64 `readable`: white at 50 % over the dimmed court can be as dark as #808080, so a colour is blended 15 %
    /// toward black (ColorUtils.blendARGB, in Float as on Android) until its contrast with #808080 reaches 4.5, at most 12 times.
    static func readable(_ color: UInt32) -> UInt32 {
        var c = color
        for _ in 0..<12 where contrast(c, 0xff808080) < 4.5 { c = blendBlack(c, 0.15) }
        return c
    }
    /// androidx ColorUtils.calculateContrast of two opaque colours.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a) + 0.05, lb = luminance(b) + 0.05
        return max(la, lb) / min(la, lb)
    }
    /// androidx ColorUtils.calculateLuminance (sRGB, 0.04045 threshold; 0.2126, 0.7152, 0.0722).
    static func luminance(_ c: UInt32) -> Double {
        func linear(_ v: UInt32) -> Double { let x = Double(v) / 255; return x < 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c >> 16 & 0xff) + 0.7152 * linear(c >> 8 & 0xff) + 0.0722 * linear(c & 0xff)
    }
    /// androidx ColorUtils.blendARGB(color, Color.BLACK, ratio): Float channels, truncated.
    static func blendBlack(_ c: UInt32, _ ratio: Float) -> UInt32 {
        let inverse: Float = 1 - ratio
        func channel(_ shift: UInt32, _ other: Float) -> UInt32 { UInt32(Float(c >> shift & 0xff) * inverse + other * ratio) }
        return channel(24, 255) << 24 | channel(16, 0) << 16 | channel(8, 0) << 8 | channel(0, 0)
    }

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
                        // Android d376d64: only the backing is translucent (white at 50 %); the texts and buttons stay opaque.
                        .fill(FamilyKit.color(0x80ffffff))
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
            line("★  " + MPResultWords.scores(), size: wide ? 14 : 16, color: FamilyKit.color(Self.gold)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            // Android 47ad0c9: the headline is pink; d376d64: darkened until it reads on the dimmed court.
            line(title, size: wide ? 22 : 26, color: FamilyKit.color(Self.readable(0xffff5ba6))).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, 6).padding(.bottom, wide ? 8 : 16)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let accent = FamilyKit.color(Self.accents[index % Self.accents.count])
                HStack(spacing: 0) {
                    line(Self.number(index + 1), size: 18, color: accent).frame(width: 30)
                    line(row.name, size: wide ? 18 : 21, color: FamilyKit.color(Self.readable(row.color ?? Self.ink)))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
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
                line(note, size: 15, color: FamilyKit.color(Self.ink), bold: false).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10).padding(.bottom, 4)
            }
            // Android 47ad0c9: the pink secondary action (Menu) comes first, at the reading edge. Android b58f0d5: 16 pt above.
            HStack(spacing: 12) {
                if let secondary { button(secondary, color: MPXResultCard.pink) }
                button(primary, color: primary.color)
            }
            .padding(.top, MPSpacing.actionTop)
        }
        .padding(.horizontal, 20).padding(.vertical, wide ? 12 : 22)
    }

    /// Android d376d64: solid lettering without a shadow.
    private func line(_ value: String, size: CGFloat, color: Color = FamilyKit.color(MPXResultCard.ink), bold: Bool = true) -> some View {
        Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func button(_ action: Action, color: UInt32) -> some View {
        Button {
            guard !closed else { return }
            closed = true
            action.close()
        } label: {
            // Android 6fcb446 PongButton: word labels one size larger (18 → 19).
            Text(action.title).font(.system(size: 19, weight: .bold)).foregroundStyle(color == MPXResultCard.pink ? Color.white : FamilyKit.color(0xff17384d))
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
