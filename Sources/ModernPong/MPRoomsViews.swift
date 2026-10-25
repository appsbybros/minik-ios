import SwiftUI

/// Android PlayActivity.standings (36fbbb4, b7b471d): the tournament table with Started / Finished / Remaining and the
/// scored / conceded / difference columns, plus the ranking explanation. Numbers stay left to right.
struct MPRoomsStandings: View {
    let session: MPSession
    let hebrew: Bool
    private func t(_ en: String, _ he: String) -> String { hebrew ? he : en }
    private func cell(_ value: String, _ width: CGFloat, bold: Bool = false) -> some View {
        Text(value).font(.system(size: 14, weight: bold ? .bold : .regular)).foregroundStyle(MPStyle.ink).multilineTextAlignment(.center)
            .lineLimit(2).minimumScaleFactor(0.8).padding(.horizontal, 5).padding(.vertical, 7).frame(width: width)
            .environment(\.layoutDirection, Int(value) != nil ? .leftToRight : (hebrew ? .rightToLeft : .leftToRight))
    }
    var body: some View {
        let s = session
        let headers = [t("Points", "נקודות"), t("Wins", "ניצחונות"), t("Losses", "הפסדים"), t("Started", "התחילו"), t("Finished", "הסתיימו"), t("Remaining", "נותרו"),
                       t("Points scored", "נקודות זכות"), t("Points conceded", "נקודות חובה"), t("Point difference", "הפרש נקודות")]
        let rows = MPRules.standings(s)
        VStack(spacing: 10) {
            Text(t("Tournament table", "טבלת הטורניר")).font(.system(size: 19, weight: .bold)).foregroundStyle(MPStyle.ink).multilineTextAlignment(.center)
            Text(t("Swipe sideways to see every column", "החליקו לצדדים כדי לראות את כל העמודות")).font(.system(size: 13)).foregroundStyle(MPStyle.ink).leadingText()
            Text(t("Ranking: tournament points, wins, point difference, then points scored. A complete tie keeps the same stable order.", "הדירוג נקבע לפי נקודות הטורניר, ניצחונות, הפרש נקודות ואז נקודות זכות. בשוויון מלא נשמר סדר קבוע."))
                .font(.system(size: 14)).foregroundStyle(MPStyle.ink).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        cell(t("Player", "שחקן"), 156, bold: true)
                        ForEach(headers.indices, id: \.self) { index in cell(headers[index], index >= 5 ? 104 : 76, bold: true) }
                    }.frame(height: 52).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 9))
                    ForEach(rows.indices, id: \.self) { i in
                        let r = rows[i]
                        if let p = s.participants[r.id] {
                            let games = s.matches.values.filter { $0.contains(p.id) }
                            let values = [r.points, r.wins, r.losses, games.filter { $0.phase == .playing }.count, r.played, games.filter { !$0.terminal }.count, r.pointsFor, r.pointsAgainst, r.pointsFor - r.pointsAgainst]
                            HStack(spacing: 0) {
                                HStack(spacing: 4) {
                                    MPAvatar(character: p.bot?.characterId ?? p.identity.characterId, icon: p.identity.avatar).frame(width: 48, height: 60)
                                    Text(p.name(hebrew: hebrew) + (s.departed[p.id] == true ? t(" · Left", " · עזב/ה") : "")).font(.system(size: 15, weight: .bold)).foregroundStyle(MPStyle.ink)
                                        .lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(width: 156)
                                ForEach(values.indices, id: \.self) { index in cell(String(values[index]), index >= 5 ? 104 : 76) }
                            }
                            .frame(height: 68)
                            .background(i % 2 == 0 ? Color(red: 231 / 255, green: 251 / 255, blue: 244 / 255) : Color(red: 241 / 255, green: 237 / 255, blue: 1), in: RoundedRectangle(cornerRadius: 9))
                            .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
                        }
                    }
                }
            }
            .defaultScrollAnchor(hebrew ? UnitPoint.trailing : UnitPoint.leading)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Android PlayActivity.completed (78ed219, 36fbbb4): the final podium of a tournament, kept visible until leaving.
struct MPRoomsPodium: View {
    let session: MPSession
    let hebrew: Bool
    private static let colors: [UInt32] = [0xffffdf75, 0xffdce6ee, 0xffe8b185]
    var body: some View {
        VStack(spacing: 10) {
            Text(hebrew ? "מנצחי הטורניר" : "Tournament podium").font(.system(size: 21, weight: .bold)).foregroundStyle(MPStyle.ink).multilineTextAlignment(.center)
            let podium = MPRanking.podium(session)
            ForEach(podium.indices, id: \.self) { index in
                if let p = session.participants[podium[index]] {
                    HStack(spacing: 8) {
                        MPAvatar(character: p.bot?.characterId ?? p.identity.characterId, icon: p.identity.avatar).frame(width: 62, height: 76)
                        Text("\(index + 1). " + p.name(hebrew: hebrew)).font(.system(size: 20, weight: .bold)).foregroundStyle(MPStyle.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(MPColor.color(Self.colors[index]), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

/// Android `LandscapeTipSession` / `PongOrientationHint` (0e65e52): "For a wider view, play in landscape." is offered at
/// most once per app run, 0.9 s into an active match in portrait, and never after the player has used landscape.
struct MPLandscapeTipSession {
    private(set) var playedLandscape = false
    private(set) var shown = false
    mutating func observe(_ landscape: Bool) { if landscape { playedLandscape = true } }
    mutating func claim(_ active: Bool) -> Bool {
        if !active || playedLandscape || shown { return false }
        shown = true; return true
    }
    @MainActor static var shared = MPLandscapeTipSession()
}
