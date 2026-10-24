import SwiftUI

/// Android `MatchResultDialog` (bcee181 and later): the headline, "<winner> won!", both players' cards (portrait, name,
/// score) in the canonical left-to-right order, and the actions. The local player's card wears their colour rank; the
/// opponent's card wears the challenged colour in a Color Challenge, otherwise a cheerful random colour.
struct MPMatchResult: Equatable {
    struct Player: Equatable { var name: String; var avatar: String; var score: Int }
    var title: String
    var first: Player
    var second: Player
    /// 0 = `first` won, 1 = `second` won.
    var winner: Int
    var action: String
    var localPlayer = 0
    var opponentColorOverride: UInt32? = nil
    var again = false
    /// Android picks the opponent colour with `random()` each time the dialog is shown.
    var opponentColor: UInt32 = ([0xffff5ba6, 0xffffdf75, 0xffffb46a] as [UInt32]).randomElement()!
}

struct MPMatchResultView: View {
    let result: MPMatchResult
    let localRank: MPRank
    let hebrew: Bool
    let again: () -> Void
    let close: () -> Void
    private let ink: UInt32 = 0xff173e56
    private func text(_ value: String, _ size: CGFloat, _ color: UInt32) -> some View {
        Text(value).font(.system(size: size, weight: .bold)).foregroundStyle(MPColor.color(color)).multilineTextAlignment(.center)
            .padding(.horizontal, 4).padding(.vertical, 3).fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            ScrollView {
                VStack(spacing: 0) {
                    text(result.title, wide ? 19 : 23, ink)
                    let victor = result.winner == 0 ? result.first : result.second
                    text(hebrew ? "המנצח במשחק: \u{2068}\(victor.name)\u{2069}" : "\(victor.name) won!", wide ? 19 : 22, 0xff2069a4)
                    HStack(spacing: 0) {
                        card(result.first, index: 0, wide: wide)
                        card(result.second, index: 1, wide: wide)
                    }.environment(\.layoutDirection, .leftToRight)
                    actions(wide: wide).padding(.top, wide ? 8 : 16)
                }
                .padding(.horizontal, 16).padding(.top, wide ? 10 : 20).padding(.bottom, wide ? 12 : 30)
                .background(RoundedRectangle(cornerRadius: 28).fill(MPColor.color(0xf5f2fbff)))
                .frame(maxWidth: min(proxy.size.width - 32, wide ? 580 : 520))
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
    }
    private func card(_ p: MPMatchResult.Player, index: Int, wide: Bool) -> some View {
        let local = index == result.localPlayer
        let overrideRank = result.opponentColorOverride.flatMap { c in MPRanks.all.first { $0.color == c } }
        let color = local ? localRank.color : (result.opponentColorOverride ?? result.opponentColor)
        let cardInk = local ? localRank.ink : MPRanks.ink(color)
        let details = VStack(spacing: 0) {
            text("\u{2068}\(p.name)\u{2069}", wide ? 16 : 18, cardInk).lineLimit(2).minimumScaleFactor(0.7)
            text(String(p.score), wide ? 26 : 30, cardInk).monospacedDigit()
        }
        return Group {
            if wide {
                HStack(spacing: 4) { MPAvatar(character: p.avatar, icon: 0).frame(width: 64, height: 76); details.frame(maxWidth: .infinity) }
            } else {
                VStack(spacing: 4) { MPAvatar(character: p.avatar, icon: 0).frame(maxWidth: .infinity).frame(height: 140); details }
            }
        }
        .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, wide ? 10 : 18)
        .background {
            if local { MPRankPresentation.background(localRank, radius: 20) }
            else if let overrideRank { MPRankPresentation.background(overrideRank, radius: 20) }
            else { RoundedRectangle(cornerRadius: 20).fill(MPColor.color(color)) }
        }
        .overlay { if color == MPRanks.all[0].color { RoundedRectangle(cornerRadius: 20).strokeBorder(MPColor.color(0xff7292af), lineWidth: 1) } }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4).padding(.vertical, wide ? 5 : 12)
        .accessibilityElement(children: .ignore).accessibilityLabel(p.name + " " + String(p.score))
    }
    @ViewBuilder private func actions(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 8)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            if result.again {
                Button(action: again) {
                    Text(hebrew ? "משחק נוסף" : "Play again").font(.system(size: 18, weight: .bold)).foregroundStyle(MPColor.color(ink))
                        .frame(maxWidth: .infinity, minHeight: 54).background(MPFaceBackground(face: MPCourtStyle.startFace, radius: 20))
                }.buttonStyle(.plain)
            }
            Button(action: close) {
                Text(result.action).font(.system(size: 18, weight: .bold)).foregroundStyle(result.again ? Color.white : MPColor.color(ink)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 8)
                    .background {
                        if result.again { RoundedRectangle(cornerRadius: 20).fill(MPStyle.pink) }
                        else { MPFaceBackground(face: MPCourtStyle.menuFace, radius: 20) }
                    }
            }.buttonStyle(.plain)
        }
    }
}
