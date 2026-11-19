import SwiftUI

/// Android `FamilyLeague.landing()` / `render()`: the family league page. Its back arrow (Android `screenBack`) hides
/// the league and returns home.
struct FamilyLeagueScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject var league: FamilyLeague

    var body: some View {
        AmuduPage(model.tr("Family league", "ליגה משפחתית"), background: model.art.scene(model.scene), back: {
            league.hide()
            model.home()
        }) {
            switch league.page {
            case .loading:
                EmptyView()
            case .landing:
                landing
            case .league:
                standings
            }
        }
    }

    /// Android: `GameDialogBuilder(a).setTitle(...).setView(input).setPositiveButton(tr("Join",...))` — the shared SPUD
    /// dialog (only the × closes it without joining).
    private func joinDialog() {
        let field = SpudDialogField(placeholder: model.tr("Six-character code", "קוד בן שישה תווים"), capitalization: .never)
        let request = SpudDialogStyle.make(title: model.tr("Join a family league", "הצטרפות לליגה משפחתית"), field: field,
                                           positive: (model.tr("Join", "הצטרפות"), { [model, league] in
                                               league.joinInput = model.dialogInput
                                               league.confirmJoin()
                                           }))
        _ = model.showDialog(request, input: "")
    }

    private func deleteDialog() {
        let request = SpudDialogStyle.make(title: model.tr("Delete league?", "למחוק את הליגה?"),
                                           message: model.tr("This deletes the league roster and standings for everyone.", "הפעולה תמחק את רשימת המשתתפים ואת טבלת הליגה לכולם."),
                                           positive: (model.tr("Delete", "מחיקה"), { [league] in league.delete() }),
                                           negative: (model.tr("Cancel", "ביטול"), {}))
        _ = model.showDialog(request)
    }

    @ViewBuilder private var landing: some View {
        AmuduParagraph(model.tr("Choose your house players once. Friends join with the same code each time. Only players who join a round receive points for it.",
                                "בוחרים שחקני בית פעם אחת. חברים מצטרפים בכל פעם עם אותו קוד. רק מי שמשתתף במשחק מקבל בו נקודות."))
        AmuduButton(model.tr("Create a family league", "יצירת ליגה משפחתית")) {
            league.hide()
            model.leagueSetup(true)
        }
        AmuduButton(model.tr("Join a family league", "הצטרפות לליגה משפחתית"), color: 0xffb7dcff) {
            joinDialog()
        }
    }

    @ViewBuilder private var standings: some View {
        let rows = league.rows
        AmuduLabel(league.code, size: 28)
        AmuduButton(model.tr("Copy code", "העתקת הקוד"), color: 0xffb7dcff) { league.copyCode() }
        AmuduParagraph(model.tr("A win earns 3 points. Ties are ordered by fewer penalty points. Absent players keep their totals.",
                                "ניצחון מזכה ב־3 נקודות. בשוויון, פחות נקודות חובה קובעות. הניקוד של מי שלא משתתף נשאר ללא שינוי."), size: 16)
        ScrollView(.horizontal, showsIndicators: true) {
            table(rows)
        }
        .padding(.bottom, 12)
        let histories = rows.filter { !$0.nicknames.isEmpty }
        if !histories.isEmpty {
            AmuduLabel(model.tr("Nickname history", "היסטוריית כינויים"), size: 20)
            ScrollView {
                AmuduParagraph(histories.map { $0.member.displayName(hebrew: model.hebrew) + ": " + $0.nicknames.joined(separator: " · ") }
                    .joined(separator: "\n\n"), size: 16)
            }
            .frame(height: 150)
        }
        if !league.activeRoom.isEmpty {
            AmuduButton(model.tr("Join this round", "הצטרפות למשחק")) {
                league.hide()
                model.openLeagueRoom(league.activeRoom, league.id, false, nil)
            }
        }
        if league.isHost {
            AmuduButton(model.tr("New league game", "משחק חדש בליגה")) {
                league.hide()
                model.leagueSetup(false)
            }
            AmuduButton(model.tr("Delete league", "מחיקת הליגה"), color: 0xffe91e63, ink: 0xffffffff) {
                deleteDialog()
            }
        }
    }

    /// Android `TableLayout` on a 0xdd163049 panel with 16 dp corners: Player (avatar + name), Points, Wins, Penalties,
    /// Games.
    private func table(_ rows: [LeagueStandings.Row]) -> some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell(model.tr("Player", "שחקן"), 170)
                cell(model.tr("Points", "נקודות"), 78)
                cell(model.tr("Wins", "ניצחונות"), 70)
                cell(model.tr("Penalties", "נקודות חובה"), 95)
                cell(model.tr("Games", "משחקים"), 80)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    HStack(spacing: 0) {
                        Image(uiImage: model.art.portrait(row.member.character))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 52)
                        cell(row.member.displayName(hebrew: model.hebrew), 130)
                            .frame(maxWidth: .infinity)
                        // Equal empty end cell balances the avatar without moving the avatar itself.
                        Color.clear.frame(width: 40, height: 1)
                    }
                    cell(String(row.points), 72)
                    cell(String(row.wins), 72)
                    cell(String(row.penalties), 72)
                    cell(String(row.games), 72)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(argb: 0xdd163049)))
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(minWidth: width)
    }
}
