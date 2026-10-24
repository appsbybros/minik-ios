import SwiftUI

/// Android `ColorChallengeActivity` (6feaac5, 29f5dc7): the current and next colour, eligibility, the qualification
/// rules, the controls a challenge allows, progress, and the opponents (the strongest house players and the colour's
/// Champion). A challenge is a local friendly room on the Park arena to 11 points; a paused one can be resumed or
/// forfeited.
struct MPColorChallengeView: View {
    @ObservedObject var model: MPController
    let hebrew: Bool
    @State private var confirmForfeit = false
    private func t(_ en: String, _ he: String) -> String { hebrew ? he : en }
    private func line(_ value: String, size: CGFloat = 18, color: UInt32 = 0xffffffff) -> some View {
        MPHudText(value, color: color, font: .system(size: size, weight: .bold), outline: color == 0xffffffff ? 0 : 1.4, adaptive: true, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.vertical, 7)
    }
    var body: some View {
        let _ = model.rankRevision
        ScrollView {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
                .background(RoundedRectangle(cornerRadius: 22).fill(MPColor.color(0xee142d4a)))
                .frame(maxWidth: 620).padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity)
        }
        .alert(t("Forfeit this match? An unfinished winning streak will reset. Your points and completed wins stay saved.", "לפרוש מהמשחק? רצף ניצחונות שטרם הושלם יתאפס. הנקודות והניצחונות שהושלמו נשמרים."), isPresented: $confirmForfeit) {
            Button(t("Cancel", "ביטול"), role: .cancel) {}
            Button(t("Forfeit", "פרישה"), role: .destructive) { model.forfeitChallenge() }
        }
    }
    @ViewBuilder private var content: some View {
        let ranking = model.ranking, state = ranking.state, current = ranking.rank
        line(t("Current color: \(current.name(he: false)) · \(state.points) points", "הצבע שלכם: \(current.name(he: true)) · \(state.points) נקודות"), size: 21, color: current.color)
        if let next = state.next {
            let target = MPRanks.all[next], name = target.name(he: hebrew)
            line(t("Next color: \(name)", "הצבע הבא: \(name)"), size: 23, color: target.color)
            if !state.eligible {
                line(t("Earn \(target.threshold - state.points) more points to open this challenge.", "עוד \(target.threshold - state.points) נקודות לפתיחת האתגר."))
            } else {
                line(t("You've earned enough points! Now take the challenge and earn your next color.", "השגתם מספיק נקודות! עכשיו הזמן להצליח באתגר ולזכות בצבע הבא."), size: 19)
                if ranking.activeTrialCode != nil { paused } else { challenge(next, target: target, name: name, state: state) }
            }
        } else {
            line(t("Gold achieved! Keep playing for the fun of it.", "הגעתם לזהב! ממשיכים לשחק בשביל הכיף."))
        }
    }
    @ViewBuilder private var paused: some View {
        line(t("Your qualification match is paused. Resume it, or forfeit it to start a new qualification match.", "משחק אתגר הצבע שלכם מושהה. אפשר להמשיך בו, או לפרוש כדי להתחיל משחק העפלה חדש."))
        actionButton(t("Resume match", "המשך המשחק"), MPColor.color(0xff25864d)) { model.resumeChallenge() }
        actionButton(t("Forfeit match", "פרישה מהמשחק"), MPStyle.pink) { confirmForfeit = true }
    }
    private func actionButton(_ title: String, _ color: Color, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18).fill(color))
        }.buttonStyle(.plain).padding(.top, 16).disabled(model.busy)
    }
    @ViewBuilder private func challenge(_ next: Int, target: MPRank, name: String, state: MPRankProgress) -> some View {
        let requirement = state.requirement, rivals = MPRankPromotion.bots(next)
        let rivalNames = rivals.map { $0.name(hebrew: hebrew) }.joined(separator: ", ")
        line(requirement.streak
             ? t("To earn \(name), win \(requirement.bots) games in a row against \(rivals[0].name(hebrew: false)). Each game is played to 11 points.", "כדי לזכות בצבע \(name), נצחו \(requirement.bots) משחקים ברצף מול \(rivals[0].name(hebrew: true)). בכל משחק מנצחים כשמגיעים ל־11 נקודות.")
             : t("To earn \(name), win \(requirement.bots) games against any of the three strongest players: \(rivalNames). Each game is played to 11 points.", "כדי לזכות בצבע \(name), נצחו \(requirement.bots) משחקים מול אחד משלושת השחקנים החזקים ביותר: \(rivalNames). בכל משחק מנצחים כשמגיעים ל־11 נקודות."))
        let choices = [1, 0, 3].filter { MPRankPromotion.allowedControl(next, $0) }
        line(t("Qualification controls", "רמת השליטה באתגר"))
        MPChoiceBar(title: t("Qualification controls", "רמת השליטה באתגר"),
                    options: choices.map { (value: $0, label: MPControlChoice.title($0, hebrew: hebrew)) },
                    selection: Binding(get: { choices.contains(model.challengeControl) ? model.challengeControl : choices[0] }, set: { model.challengeControl = $0 }))
        line(requirement.streak ? t("Best-player streak: \(state.streak)/\(requirement.bots)", "רצף מול השחקן החזק ביותר: \(state.streak)/\(requirement.bots)")
             : t("House-player wins: \(state.botWins)/\(requirement.bots)", "ניצחונות מול שחקני הבית: \(state.botWins)/\(requirement.bots)"), size: 20)
        line(requirement.streak ? t("Rules: A loss resets an unfinished streak. Once the full streak is complete, it stays saved—even during Champion matches.", "הכללים: הפסד מאפס רצף שטרם הושלם. לאחר השלמת הרצף כולו הוא נשמר, גם במשחקים מול אלוף הצבע.")
             : t("Rules: Choose any listed player each time. You can repeat the same opponent. Wins stay saved after a loss.", "הכללים: בכל פעם אפשר לבחור כל שחקן מהרשימה, גם את אותו היריב שוב. הניצחונות נשמרים גם אחרי הפסד."), size: 16)
        if requirement.champions > 0 {
            line(t("\(name) Champion wins: \(state.championWins)/\(requirement.champions)", "ניצחונות מול אלוף הצבע \(name): \(state.championWins)/\(requirement.champions)"), size: 20)
            line(t("Rules: Also beat the \(name) Champion \(requirement.champions) times. These wins stay saved after a loss. Each match is played to 11 points.", "הכללים: צריך גם לנצח את אלוף הצבע \(name) \(requirement.champions) פעמים. הניצחונות האלה נשמרים גם אחרי הפסד. כל משחק הוא עד 11 נקודות."), size: 16)
        }
        line(t("Choose your opponent below", "בחרו יריב בהמשך"), size: 20)
        ForEach(rivals) { opponent($0.profile, next: next, target: target, name: name, champion: false) }
        if requirement.champions > 0 { opponent(MPRankPromotion.championProfile(next), next: next, target: target, name: name, champion: true) }
    }
    private func opponent(_ bot: MPBot, next: Int, target: MPRank, name: String, champion: Bool) -> some View {
        let c = MPRoster.find(bot.characterId) ?? MPRoster.all[0]
        return HStack(spacing: 12) {
            MPAvatar(character: c.id, icon: 0).frame(width: 84, height: 110)
            VStack(spacing: 12) {
                Text(champion ? t("\(name) Champion · \(c.name(hebrew: false))", "אלוף הצבע \(name) · \(c.name(hebrew: true))") : c.name(hebrew: hebrew))
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(MPColor.color(target.ink)).multilineTextAlignment(.center)
                Button { model.startChallenge(bot: bot, target: next, champion: champion) } label: {
                    Text(t("Play", "למשחק")).font(.system(size: 18, weight: .bold)).foregroundStyle(MPColor.color(0xff123348))
                        .frame(maxWidth: .infinity, minHeight: 54).background(MPFaceBackground(face: MPCourtStyle.startFace, radius: 16))
                }.buttonStyle(.plain).disabled(model.busy)
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 16)
        .background(MPRankPresentation.background(target, radius: 20))
        .padding(.top, 16)
    }
}
