import SwiftUI
import UIKit

/// Android `PongHudText` (6feaac5 and later): a real contour around the text, including individually coloured spans,
/// without a filled panel. `adaptive` inverts each span's luminance for its rim (Android's rank-contrast colour matrix):
/// dark Brown or Blue get a light rim, light Silver or Yellow a dark one. Otherwise the rim is navy 0xff071b3b.
struct MPHudText: View {
    struct Segment { var text: String; var color: UInt32 }
    let segments: [Segment]
    var font: Font = .system(size: 18, weight: .bold)
    var outline: CGFloat = 0
    var adaptive = false
    var alignment: TextAlignment = .center
    init(_ segments: [Segment], font: Font = .system(size: 18, weight: .bold), outline: CGFloat = 0, adaptive: Bool = false, alignment: TextAlignment = .center) {
        self.segments = segments; self.font = font; self.outline = outline; self.adaptive = adaptive; self.alignment = alignment
    }
    init(_ text: String, color: UInt32, font: Font = .system(size: 18, weight: .bold), outline: CGFloat = 0, adaptive: Bool = false, alignment: TextAlignment = .center) {
        self.init([Segment(text: text, color: color)], font: font, outline: outline, adaptive: adaptive, alignment: alignment)
    }
    /// Android `rankContrast`: 510 − (0.897 R + 1.761 G + 0.342 B), clamped, as a grey.
    static func rim(_ argb: UInt32) -> UInt32 {
        let r = Double((argb >> 16) & 0xff), g = Double((argb >> 8) & 0xff), b = Double(argb & 0xff)
        let v = UInt32(max(0, min(255, 510 - (0.897 * r + 1.761 * g + 0.342 * b))))
        return 0xff00_0000 | v << 16 | v << 8 | v
    }
    private func text(_ rim: Bool) -> Text {
        segments.reduce(Text("")) { result, s in
            result + Text(s.text).foregroundColor(MPColor.color(rim ? (adaptive ? Self.rim(s.color) : 0xff071b3b) : s.color))
        }
    }
    var body: some View {
        let main = text(false).font(font).multilineTextAlignment(alignment)
        if outline > 0 {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4
                    text(true).font(font).multilineTextAlignment(alignment)
                        .offset(x: CGFloat(cos(angle)) * outline / 2, y: CGFloat(sin(angle)) * outline / 2)
                }
                main
            }.accessibilityElement(children: .ignore).accessibilityLabel(segments.map(\.text).joined())
        } else { main }
    }
}

/// Android `LocalizedActivity.surface(color, radius).setFaceGradient(...)`: a raised face with its three-stop gradient
/// and an optional 1-point outline.
struct MPFaceBackground: View {
    let face: MPCourtFace
    var radius: CGFloat = 18
    var stroke: UInt32? = nil
    var lineWidth: CGFloat = 1
    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(face.gradient)
            .overlay { if let stroke { RoundedRectangle(cornerRadius: radius).strokeBorder(MPColor.color(stroke), lineWidth: lineWidth) } }
    }
}
extension MPRankPresentation {
    /// Android `PongRankPresentation.surface`: the rank face with its outline.
    static func background(_ rank: MPRank, radius: CGFloat = 20) -> MPFaceBackground {
        MPFaceBackground(face: face(rank), radius: radius, stroke: stroke(rank))
    }
}

/// Android 95ba112 `PongRankPresentation.hero`: the mascot with non-interactive points and current rank beside it;
/// the ordinary "Color ranking" menu button opens the ranks. Separate columns keep long RTL text off the art.
struct MPRankHero: View {
    let ranking: MPRanking
    let hebrew: Bool
    let height: CGFloat
    var body: some View {
        let rank = ranking.rank, name = rank.name(he: hebrew)
        let number = NumberFormatter.localizedString(from: NSNumber(value: ranking.points), number: .decimal)
        let first = hebrew ? "ניקוד מצטבר: \(number)" : "Points: \(number)"
        let prefix = hebrew ? "דירוג נוכחי: " : "Current ranking: "
        GeometryReader { proxy in
            let art = min(height, (proxy.size.width - 12) / 2)
            ZStack {
                Image("mp_app_icon").resizable().scaledToFit().frame(width: art, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    MPHudText(first, color: 0xffffffff, font: .system(size: 17, weight: .bold), outline: 1.4, alignment: .leading)
                    MPHudText([.init(text: prefix, color: 0xffffffff), .init(text: name, color: rank.color)], font: .system(size: 17, weight: .bold), outline: 1.4, adaptive: true, alignment: .leading)
                }
                .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 4)
                .frame(width: max(min(240, proxy.size.width - art - 12), 0), alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityElement(children: .ignore).accessibilityLabel(first + ". " + prefix + name)
            }
        }
        .frame(height: height).padding(.bottom, 18)
    }
}

/// Android `PongRankDialog.show` / `details`: the reward rules, the twelve colours, and one colour's requirements.
struct MPRankSheet: View {
    let ranking: MPRanking
    let hebrew: Bool
    let close: () -> Void
    @State private var detail: Int?
    private let ink = MPColor.color(0xff173e56)
    private func paragraph(_ value: String) -> some View {
        Text(value).font(.system(size: 17)).foregroundStyle(ink).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.vertical, 8)
    }
    var body: some View {
        let he = hebrew
        VStack(spacing: 0) {
            ZStack {
                Text(detail.map { MPRanks.all[$0].name(he: he) } ?? (he ? "דירוג צבעים" : "Color ranking"))
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(ink).multilineTextAlignment(.center).padding(.horizontal, 58).padding(.vertical, 8)
                HStack {
                    Button { if detail != nil { detail = nil } else { close() } } label: {
                        Image(systemName: he ? "arrow.right" : "arrow.left").font(.system(size: 24, weight: .heavy)).frame(width: 52, height: 48)
                    }.foregroundStyle(MPStyle.pink).accessibilityLabel(he ? "חזרה" : "Back")
                    Spacer()
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    if let target = detail { details(target) } else { ladder }
                }.padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 18)
        .background(MPColor.color(0xffeff8ff).ignoresSafeArea())
        .environment(\.layoutDirection, he ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.light)
    }
    @ViewBuilder private var ladder: some View {
        let he = hebrew
        paragraph(he ? "ניצחון ידידות לפי רמת השליטה:\nמתחילים / נינוחה: 1–5 מול בוט, 3–10 ברשת.\nרגילה: 3–7 מול בוט, 5–15 ברשת.\nמקצועני: 5–10 מול בוט, 8–20 ברשת.\nהניקוד תלוי בכישורי הבוט או בצבע שהיריב ברשת הרוויח. כל הנקודות שלמות."
                  : "Friendly wins by control level:\nBeginner / Starter: 1–5 vs bots, 3–10 online.\nStandard: 3–7 vs bots, 5–15 online.\nPro: 5–10 vs bots, 8–20 online.\nPoints depend on the bot’s abilities or your online opponent’s earned color. All points are whole numbers.")
        paragraph(he ? "טורניר: נקודה לכל ניצחון, ועוד 15/10/5 למקומות 1/2/3. באתגרים יומיים חדשים מרוויחים 3, 5, 7, 10, 12 או 15 נקודות לפי השלב. הפסד לא מוריד נקודות. לחצו על צבע כדי לראות איך מרוויחים אותו."
                  : "Tournament: 1 point per match win, plus 15/10/5 for first/second/third. New daily stages award 3, 5, 7, 10, 12 or 15 points as you progress. Losing never removes points. Tap a color to see how to earn it.")
        let level = ranking.state.level
        ForEach(MPRanks.all.indices, id: \.self) { i in
            let rank = MPRanks.all[i]
            Button { detail = i } label: {
                Text(rank.name(he: he) + " · \(rank.threshold)" + (i == level ? (he ? " · הצבע שלכם" : " · your color") : ""))
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(MPColor.color(rank.ink)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(MPColor.color(rank.color))
                        .overlay { if i == 0 { RoundedRectangle(cornerRadius: 14).strokeBorder(MPColor.color(0xff7292af), lineWidth: 1) } })
            }.buttonStyle(.plain).padding(.top, 10)
        }
    }
    @ViewBuilder private func details(_ target: Int) -> some View {
        let he = hebrew, rank = MPRanks.all[target], r = MPRankPromotion.requirement(target)
        // Android 95ba112: White and Yellow say only what they need; the champion is named beside its portrait.
        if target == 0 { paragraph(he ? "לבן הוא דירוג הצבע ההתחלתי שלכם." : "White is your starting color rank.") }
        else if target == 1 { paragraph(he ? "על מנת לקבל את דירוג הצבע הצהוב צריך להשיג 200 נקודות." : "To earn the Yellow color rank, you need 200 points.") }
        else {
            paragraph(he ? "ניקוד מצטבר של \(rank.threshold) נקודות, לאחר השלמת דירוגי הצבע הקודמים." : "Reach \(rank.threshold) points and complete the earlier color ranks.")
            let names = MPRankPromotion.bots(target).map { $0.name(hebrew: he) }.joined(separator: ", ")
            paragraph(he ? "\(r.bots) ניצחונות\(r.streak ? " ברצף" : "") במשחקי אתגר הצבע מול \(names). \(r.streak ? "הפסד מאפס רצף שטרם הושלם." : "אפשר לבחור שוב באותו יריב.")"
                      : "\(r.bots) Color Challenge wins\(r.streak ? " in a row" : "") against \(names). \(r.streak ? "A loss resets an unfinished streak." : "You may repeat an opponent.")")
            let minimum = MPControlChoice.title(MPRankPromotion.minimumControl(target), hebrew: he)
            paragraph(he ? "משחקי ההעפלה הם עד 11 נקודות. רמת השליטה המינימלית: ״\(minimum)״. מתחילים דרך אתגר הצבע לאחר צבירת הנקודות."
                      : "Qualification matches are first to 11. Minimum control level: \(minimum). Start in Color Challenge once you have enough points.")
            if r.champions > 0 {
                let id = MPRankPromotion.championProfile(target).characterId
                let character = MPRoster.find(id) ?? MPRoster.all[0]
                let champion = he ? "\(["june", "mia", "gaya", "kyra"].contains(character.id) ? "אלופת" : "אלוף") הצבע \(rank.he) (\(character.name(hebrew: true)))"
                    : "\(rank.en) Champion, \(character.name(hebrew: false))"
                let count = r.champions == 1 ? "" : he ? " \(r.champions) פעמים" : " \(r.champions) times"
                HStack(spacing: 12) {
                    MPAvatar(character: character.id, icon: 0, championRank: target).frame(width: 64, height: 84)
                    Text(he ? "עבור שלב זה צריך גם לנצח את \(champion)\(count)." : "To complete this stage, also beat the \(champion)\(count).")
                        .font(.system(size: 17)).foregroundStyle(ink).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Android `ColorChallengeActivity.celebrate`: the colour just earned, the player's avatar celebrating, confetti and
/// one rank cue (played by the controller). "Let's go!" closes it; the promotion is acknowledged when it appears.
struct MPRankCelebration: View {
    let level: Int
    let character: String
    let hebrew: Bool
    let close: () -> Void
    var body: some View {
        let rank = MPRanks.all[min(max(level, 0), MPRanks.lastIndex)], name = rank.name(he: hebrew), ink = MPColor.color(rank.ink)
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Text(hebrew ? "כל הכבוד! צבע חדש: \(name)" : "Congratulations! Your new color: \(name)").font(.system(size: 25, weight: .bold)).foregroundStyle(ink).multilineTextAlignment(.center)
                        MPTeamVictory(characters: [character], hebrew: hebrew).frame(height: wide ? 100 : 170)
                        Text(hebrew ? "הצלחתם באתגר. הצבע החדש שלכם בכל משחק יחידים!" : "You earned it. Your new color follows you into every singles match!").font(.system(size: 18)).foregroundStyle(ink).multilineTextAlignment(.center)
                        Button(action: close) {
                            Text(hebrew ? "איזה כיף!" : "Let's go!").font(.system(size: 18, weight: .bold)).foregroundStyle(MPColor.color(0xff123348))
                                .frame(maxWidth: .infinity, minHeight: 56).background(MPFaceBackground(face: MPCourtStyle.startFace, radius: 18))
                        }.buttonStyle(.plain).padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 26).fill(MPColor.color(rank.color))
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(MPColor.color(level == 0 ? 0xff69869e : rank.color), lineWidth: 2)))
                    .frame(maxWidth: min(480, proxy.size.width - 32))
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height - 32)
                }
                MPVictoryConfetti()
            }
        }
        .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
        .accessibilityAddTraits(.isModal)
    }
}
