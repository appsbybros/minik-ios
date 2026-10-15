import SwiftUI
import SpriteKit

/// Room, tournament and cross-table screens of Multi Ping Pong (Android MinikCrossPong 5c1aa4d PlayActivity.renderRoom, friendly,
/// seatLobby, tournament, waitingRoster, matchRow, groupBracket, standings; PrivateMatchActivity cross screen; CrossActivity).
extension ModernPongView {
    // ---- room screen ------------------------------------------------------------------------------------------------------
    var lobby: some View {
        ScrollView {
            if let s = model.session {
                VStack(spacing: gap) {
                    roomIntro(s)
                    if s.kind == .friendly { friendlyRoom(s) } else { tournamentRoom(s) }
                }.frame(maxWidth: 720).padding(20).frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(leaveTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
            if let s = model.session {
                let delete = MPRules.canDelete(s, actor: model.userID)
                Button(delete ? t("Delete", "מחיקה") : t("Leave", "עזיבה"), role: .destructive) { Task { await model.leave(delete: delete) } }
                Button(t("Cancel", "ביטול"), role: .cancel) {}
            }
        } message: { Text(leaveMessage) }
    }
    private var leaveTitle: String {
        guard let s = model.session else { return "" }
        return MPRules.canDelete(s, actor: model.userID) ? t("Delete tournament?", "למחוק את הטורניר?") : t("Leave tournament?", "לעזוב את הטורניר?")
    }
    private var leaveMessage: String {
        guard let s = model.session else { return "" }
        if MPRules.canDelete(s, actor: model.userID) { return t("The tournament and its matches will be deleted for everyone.", "הטורניר והמשחקים שלו יימחקו עבור כולם.") }
        return t("Your completed results stay. Your unfinished matches are cancelled.", "התוצאות שהושלמו נשמרות. המשחקים שלכם שטרם הסתיימו מבוטלים.")
    }
    /// Android renderRoom intro card: the room's title, the code to copy, its control level and game type.
    private func roomIntro(_ s: MPSession) -> some View {
        card(MPStyle.mint) {
            Text(roomTitle(s)).font(.title3.bold()).multilineTextAlignment(.center)
            if model.online && MPRules.acceptsNewPlayer(s) {
                Button { UIPasteboard.general.string = s.code; copied = true } label: {
                    Label(t("Copy code", "העתקת הקוד") + " · " + s.code, systemImage: "doc.on.doc").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }.buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 15)).environment(\.layoutDirection, .leftToRight)
                if copied { Text(t("Code copied", "הקוד הועתק")).font(.callout) }
            }
            Text(t("Controls: ", "רמת השליטה: ") + MPControlChoice.title(s.difficulty, hebrew: he)).font(.callout).multilineTextAlignment(.center)
            if s.tableSize > 2 { Text(gameTypeLine(s)).font(.callout).multilineTextAlignment(.center) }
        }
    }
    private func gameTypeLine(_ s: MPSession) -> String {
        var line = t("Game type: ", "סוג המשחק: ") + s.gameMode.title(he)
        if s.kind == .tournament && s.format == .knockout {
            line += " · " + (s.advance == 1 ? t("the winner of each table goes through", "המקום הראשון בכל שולחן עולה") : t("the top two of each table go through", "שני הראשונים בכל שולחן עולים"))
        }
        return line
    }
    /// Android PlayActivity.completed: the result headline and Done; a completed room is not kept in history.
    private func completedCard(_ s: MPSession) -> some View {
        card(MPStyle.mint) {
            Text(MPCompletionText.headline(s, model.userID, hebrew: he)).font(.title2.bold()).multilineTextAlignment(.center)
            action(t("Done", "סיום"), color: MPStyle.lilac) { model.dismissCompleted() }
        }
    }
    func playerPicture(_ p: MPParticipant) -> some View {
        let character = p.bot?.characterId ?? p.identity.characterId
        return MPAvatar(character: character, icon: p.identity.avatar)
    }
    // ---- friendly -----------------------------------------------------------------------------------------------------------
    @ViewBuilder private func friendlyRoom(_ s: MPSession) -> some View {
        let fixtures = s.matches.values.sorted { $0.id < $1.id }
        if s.complete {
            completedCard(s)
            ForEach(fixtures) { matchRow(s, $0, controls: false, showPair: true) }
        } else if s.tableSize >= 3 && s.matches.isEmpty {
            seatLobby(s)
            friendlyExit(s)
        } else {
            card {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(s.roster, id: \.self) { id in
                        if let p = s.participants[id] {
                            VStack(spacing: 6) {
                                playerPicture(p).frame(width: 74, height: 80)
                                Text(p.name(hebrew: he)).font(.headline).lineLimit(1).minimumScaleFactor(0.55).multilineTextAlignment(.center)
                                if id == model.userID { Text(t("You", "אתם")).font(.caption) }
                                else if p.bot == nil && !s.connected(id) { Text(t("Offline", "לא מחובר")).font(.caption) }
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                let current = fixtures.first(where: { !$0.terminal }) ?? fixtures.last
                if let current {
                    // The finished table stays visible above its final duel.
                    ForEach(fixtures.filter { $0.terminal && $0.id != current.id }) { matchRow(s, $0, controls: false, showPair: true) }
                    matchRow(s, current, controls: true, showPair: current.players.count < s.participants.count)
                } else {
                    Text(t("Share the code with a friend and wait for them to join, or choose a house player below. Once your friend has joined or you have chosen a house player, tap Start.",
                           "שתפו את הקוד עם חבר או חברה והמתינו להצטרפותם, או בחרו שחקן בית למטה. לאחר שהחבר או החברה הצטרפו, או שבחרתם שחקן בית, לחצו על התחלה."))
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if s.host == model.userID && s.participants.count < s.capacity {
                        Text(t("Opponent", "היריב שלכם")).font(.title3.bold())
                        housePicker(excluded: [])
                        action(t("Start", "התחלה"), color: MPStyle.mint) {
                            let chosen = pickedPlayer(excluded: [])
                            Task { await model.addFriendlyHouse(chosen) }
                        }
                    }
                }
            }
            friendlyExit(s)
        }
    }
    /// Android 5c1aa4d: "Save for later" once a match has started; Finish (or Cancel, for a game that never started) removes it.
    @ViewBuilder private func friendlyExit(_ s: MPSession) -> some View {
        let started = s.matches.values.contains { $0.phase == .playing || $0.phase == .finished }
        if started { action(t("Save for later", "שמירה להמשך"), color: MPStyle.mint) { model.saveForLater() } }
        action(started ? t("Finish", "סיום") : t("Cancel", "ביטול"), color: MPStyle.pink) { Task { await model.leave(delete: true) } }
            .foregroundStyle(.white)
    }
    /// Android seatLobby: the seats in table order, free seats, house players and seat changes before the start.
    private func seatLobby(_ s: MPSession) -> some View {
        let seating = s.seating()
        let used = Set(s.participants.values.compactMap { $0.bot?.characterId })
        return card {
            Text(s.tableSize == 4 ? t("Cross table · 4 seats", "שולחן לארבעה · 4 מקומות") : t("Y table · 3 seats", "שולחן Y · 3 מקומות")).font(.title3.bold())
            ForEach(0..<s.tableSize, id: \.self) { seat in seatRow(s, seat: seat, uid: seating.first(where: { $0.value == seat })?.key) }
            if s.host == model.userID && !s.freeSeats().isEmpty {
                Text(t("Fill a free seat with a house player", "מלאו מקום פנוי בשחקן בית")).font(.headline)
                housePicker(excluded: used)
                action(t("Add house player", "הוספת שחקן בית"), color: MPStyle.mint) {
                    let chosen = pickedPlayer(excluded: used)
                    // The free seat is picked inside the transaction (Android), never from this snapshot.
                    Task { await model.addFriendlyHouse(chosen) }
                }
            }
            Text(model.online ? t("Share the code so friends can take free seats, or fill them with house players. The game starts as soon as every seat is taken.", "שתפו את הקוד כדי שחברים יתפסו מקומות פנויים, או מלאו אותם בשחקני בית. המשחק מתחיל כשכל המקומות תפוסים.")
                 : t("Fill the free seats with house players. The game starts as soon as every seat is taken.", "מלאו את המקומות הפנויים בשחקני בית. המשחק מתחיל כשכל המקומות תפוסים."))
                .font(.footnote).multilineTextAlignment(.center)
        }
    }
    private func seatRow(_ s: MPSession, seat: Int, uid: String?) -> some View {
        let fill: Color = uid == nil ? Color(red: 1, green: 250 / 255, blue: 235 / 255) : Color(red: 236 / 255, green: 248 / 255, blue: 1)
        return HStack(spacing: 8) {
            Text("\(seat + 1)").font(.title3.bold()).frame(width: 32)
            if let uid, let p = s.participants[uid] {
                playerPicture(p).frame(width: 56, height: 64)
                Text(p.name(hebrew: he) + seatNote(s, uid, p)).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                if p.bot != nil && s.host == model.userID {
                    Button(t("Remove", "הסרה")) { Task { await model.removeHouse(uid) } }.font(.callout.bold()).padding(10)
                        .background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text(t("Free seat", "מקום פנוי")).foregroundStyle(Color(red: 120 / 255, green: 110 / 255, blue: 90 / 255)).frame(maxWidth: .infinity, alignment: .leading)
                if s.participants[model.userID] != nil {
                    Button(t("Sit here", "לשבת כאן")) { Task { await model.chooseSeat(seat) } }.font(.callout.bold()).padding(10)
                        .background(MPStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 8).frame(minHeight: 76)
        .background(fill, in: RoundedRectangle(cornerRadius: 12))
    }
    private func seatNote(_ s: MPSession, _ uid: String, _ p: MPParticipant) -> String {
        if uid == model.userID { return t(" · you", " · אתם") }
        if p.bot != nil { return t(" · house player", " · שחקן בית") }
        if !s.connected(uid) { return t(" · offline", " · לא מחובר") }
        return ""
    }
    // ---- tournament ---------------------------------------------------------------------------------------------------------
    @ViewBuilder private func tournamentRoom(_ s: MPSession) -> some View {
        if s.complete {
            completedCard(s)
            if s.knockout { bracket(s) } else { standings(s) }
        } else {
            if s.state == "WAITING" {
                waitingRoster(s)
                waitingTools(s)
                tournamentExitButton(s)
            } else {
                tournamentSummary(s)
                tournamentPlay(s)
            }
        }
    }
    /// Android tournamentExitButton: Delete (nobody else connected) or Leave, after a confirmation.
    private func tournamentExitButton(_ s: MPSession) -> some View {
        action(MPRules.canDelete(s, actor: model.userID) ? t("Delete tournament", "מחיקת הטורניר") : t("Leave tournament", "עזיבת הטורניר"), color: MPStyle.pink) { confirmLeave = true }
            .foregroundStyle(.white).padding(.top, 24)
    }
    /// Android waitingRoster (5c1aa4d): the players with their skills out of 10 (people have no invented skills) and, for the
    /// host, a remove control for each house player.
    private func waitingRoster(_ s: MPSession) -> some View {
        let host = s.host == model.userID
        let skills = [t("Speed", "מהירות"), t("Reaction", "תגובה"), t("Accuracy", "דיוק"), t("Power", "עוצמה"), t("Agility", "זריזות"),
                      t("Forehand", "כף יד"), t("Backhand", "גב יד"), t("Serve", "הגשה")]
        let count = MPMatchText.ordered("\(s.participants.count) / \(s.capacity)")
        return card {
            Text(t("Players", "שחקנים")).font(.title3.bold())
            Text(t("\(count) players · Skills out of 10", "\(count) שחקנים · יכולות מתוך 10")).font(.system(size: 15)).multilineTextAlignment(.center)
            Text(t("Swipe sideways to see every skill", "החליקו לצדדים כדי לראות את כל היכולות")).font(.system(size: 13)).multilineTextAlignment(.center)
            ScrollView(.horizontal) {
                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        Text(t("Player", "שחקן")).frame(width: 140)
                        if host { Text(t("Remove", "הסרה")).frame(width: 64) }
                        ForEach(skills, id: \.self) { Text($0).frame(width: 72) }
                    }.font(.system(size: 14, weight: .bold)).frame(height: 56).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 9))
                    ForEach(Array(s.roster.enumerated()), id: \.offset) { item in
                        if let p = s.participants[item.element] { rosterRow(s, p, index: item.offset, host: host) }
                    }
                }
            }
            .defaultScrollAnchor(he ? UnitPoint.trailing : UnitPoint.leading)
        }
    }
    private func rosterRow(_ s: MPSession, _ p: MPParticipant, index: Int, host: Bool) -> some View {
        let values: [Int]? = p.bot.map { [$0.speed, $0.reaction, $0.accuracy, $0.power, $0.agility, $0.forehandSkill, $0.backhandSkill, $0.serveSkill] }
        let fill: Color = index % 2 == 0 ? Color(red: 231 / 255, green: 251 / 255, blue: 244 / 255) : Color(red: 241 / 255, green: 237 / 255, blue: 1)
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                playerPicture(p).frame(width: 48, height: 70)
                Text(p.name(hebrew: he)).font(.system(size: 15, weight: .bold)).lineLimit(3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }.frame(width: 140)
            if host {
                Group {
                    if p.bot != nil {
                        Button { Task { await model.removeHouse(p.id) } } label: {
                            Image("mpx_tournament_remove").resizable().scaledToFit().padding(12).frame(width: 48, height: 48)
                        }.buttonStyle(.plain).accessibilityLabel(t("Remove ", "הסרת ") + p.name(hebrew: he))
                    } else { Text("—").font(.system(size: 16)) }
                }.frame(width: 64)
            }
            ForEach(0..<8, id: \.self) { i in Text(values.map { String($0[i]) } ?? "—").font(.system(size: 14)).frame(width: 72) }
        }
        .frame(height: 78)
        .background(fill, in: RoundedRectangle(cornerRadius: 9))
    }
    private func tournamentSummary(_ s: MPSession) -> some View {
        let finished = s.matches.values.filter { $0.phase == .finished }.count
        let remaining = s.matches.values.filter { !$0.terminal }.count
        let roundLeft = MPKnockout.fixtures(s, MPKnockout.current(s)).filter { !$0.terminal }.count
        return VStack(spacing: gap) {
            card(Color(red: 218 / 255, green: 239 / 255, blue: 1)) {
                if s.knockout {
                    Text(t("Matches remaining this round: \(roundLeft)", "משחקים שנותרו בסיבוב הזה: \(roundLeft)")).font(.headline).multilineTextAlignment(.center)
                    Text(MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
                } else {
                    Text(t("Finished: \(finished)  •  Remaining: \(remaining)", "הסתיימו: \(finished)  •  נותרו: \(remaining)")).font(.headline).multilineTextAlignment(.center)
                }
            }
            if !s.knockout { standings(s) }
        }
    }
    @ViewBuilder private func waitingTools(_ s: MPSession) -> some View {
        if s.host == model.userID {
            let used = Set(s.participants.values.compactMap { $0.bot?.characterId })
            if s.participants.count < s.capacity {
                // Every character may play more than once in a tournament ("Kyra 2"); unused ones come first in the picker.
                let excluded: Set<String> = used.count < MPRoster.all.count ? used : []
                card {
                    housePicker(excluded: excluded)
                    action(t("Add player", "הוספת שחקן"), color: MPStyle.mint) {
                        let chosen = pickedPlayer(excluded: excluded)
                        Task { await model.addHouse(chosen) }
                    }
                    // Bulk filling stays for the larger tournament formats.
                    if s.capacity > 8 {
                        action(t("Fill the empty places with house players", "מילוי המקומות הפנויים בשחקני בית"), color: MPStyle.lilac) { Task { await model.fillWithHouse() } }
                    }
                }
            }
            action(t("Start tournament", "התחלת הטורניר"), color: MPStyle.mint) { Task { await model.startTournament() } }
                .disabled(s.participants.count != s.capacity || model.busy)
                .opacity(s.participants.count == s.capacity ? 1 : 0.55)
        } else {
            card { Text(t("The host will start when everyone has joined.", "המארח יתחיל לאחר שכולם יצטרפו.")).multilineTextAlignment(.center) }
        }
    }
    @ViewBuilder private func tournamentPlay(_ s: MPSession) -> some View {
        let mine = s.matches.values.filter { $0.contains(model.userID) && !$0.terminal }.sorted { $0.id < $1.id }
        card(MPStyle.mint) {
            if s.knockout { Text(MPKnockout.playerStatus(s, model.userID, hebrew: he)).font(.title3.bold()).multilineTextAlignment(.center) }
            else if mine.isEmpty { Text(t("Your matches are complete. Waiting for the other players to finish the tournament.", "המשחקים שלכם הסתיימו. ממתינים לשאר השחקנים לסיום הטורניר.")).multilineTextAlignment(.center) }
            else { Text(t("Next / playable games", "המשחקים הבאים שאפשר לשחק")).font(.title3.bold()).frame(minHeight: 64) }
            ForEach(mine) { matchRow(s, $0, controls: true, showPair: true) }
        }
        tournamentExitButton(s)
        if s.knockout { bracket(s) }
        else {
            expandHeader(t("All matches", "כל המשחקים") + " (\(s.matches.count))", open: expanded.contains("allMatches")) { toggle("allMatches") }
            if expanded.contains("allMatches") {
                card { ForEach(s.matches.values.sorted { $0.id < $1.id }) { matchRow(s, $0, controls: false, showPair: true) } }
            }
        }
    }
    // ---- fixtures -----------------------------------------------------------------------------------------------------------
    /// Android PlayActivity.matchRow: players, what kind of fixture it is, its state, its result or the Ready controls.
    func matchRow(_ s: MPSession, _ m: MPFixture, controls: Bool, showPair: Bool) -> some View {
        let names = m.players.map { s.participants[$0]?.name(hebrew: he) ?? "?" }
        let pair = names.count == 2
        return VStack(spacing: 8) {
            if showPair { Text(pair ? MPMatchText.pair(names[0], names[1]) : MPMatchText.group(names)).font(.headline).multilineTextAlignment(.center) }
            if m.goal == .tiebreak { Text(t("Tie-break · the first point decides", "שובר שוויון · הנקודה הראשונה מכריעה")).font(.callout).multilineTextAlignment(.center) }
            if MPRules.isDuel(m) { Text(t("Final duel · the last two", "קרב גמר · שני האחרונים")).font(.callout).multilineTextAlignment(.center) }
            Text(matchState(m, names: names, houseOnly: houseOnly(s, m))).font(m.phase == .finished ? .title3.bold() : .headline).multilineTextAlignment(.center)
            if m.phase == .finished {
                Text(finishedLine(s, m)).font(.headline).multilineTextAlignment(.center)
            } else if controls && !m.terminal {
                matchControls(s, m, pair: pair)
            }
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(Color(red: 252 / 255, green: 249 / 255, blue: 1), in: RoundedRectangle(cornerRadius: 18))
    }
    /// Android 5c1aa4d: a fixture whose only human is this player (the others are house players).
    private func houseOnly(_ s: MPSession, _ m: MPFixture) -> Bool { m.players.filter { s.human($0) } == [model.userID] }
    private func matchState(_ m: MPFixture, names: [String], houseOnly: Bool) -> String {
        switch m.phase {
        case .cancelled: return t("Cancelled — player left", "בוטל — שחקן עזב")
        case .waiting: return t("Not started", "טרם התחיל")
        case .ready: return houseOnly ? t("Not started", "טרם התחיל") : t("Ready", "מוכן")
        case .playing: return t("In progress", "בתהליך")
        case .finished: return names.count == 2 ? MPMatchText.result(names[0], m.scoreA, m.scoreB, names[1]) : MPMatchText.table(names, m.scores)
        }
    }
    private func finishedLine(_ s: MPSession, _ m: MPFixture) -> String {
        if m.goal == .topTwo { return t("Going through: ", "עולים: ") + m.placement.prefix(2).map { s.participants[$0]?.name(hebrew: he) ?? "?" }.joined(separator: ", ") }
        return t("Winner: ", "המנצח: ") + (s.participants[m.winner]?.name(hebrew: he) ?? "?")
    }
    @ViewBuilder private func matchControls(_ s: MPSession, _ m: MPFixture, pair: Bool) -> some View {
        if !m.contains(model.userID) {
            // Players who are not in this fixture (an eliminated player before the final duel) only watch its result.
            Text(t("You are not playing in this one. The result appears here.", "אתם לא משחקים במשחק הזה. התוצאה תופיע כאן.")).font(.footnote).multilineTextAlignment(.center)
        } else if m.phase == .playing {
            action(t("Resume game", "המשך המשחק"), color: MPStyle.mint) { Task { await model.ready(m) } }
        } else if houseOnly(s, m) {
            let busy = s.matches.values.contains { $0.id != m.id && $0.phase == .playing && $0.contains(model.userID) }
            if busy { Text(t("Finish your current match before starting another.", "סיימו את המשחק הנוכחי לפני התחלת משחק נוסף.")).multilineTextAlignment(.center) }
            action(t("Start", "התחלה"), color: MPStyle.mint) { Task { await model.startHouseMatch(m) } }.disabled(busy).opacity(busy ? 0.55 : 1)
        } else {
            let humans = m.players.filter { s.human($0) }
            if !humans.isEmpty && humans.allSatisfy({ m.ready[$0] == true }) { Text(readyLine(s, m, humans: humans, pair: pair)).multilineTextAlignment(.center) }
            let readyNames = m.players.filter { m.ready[$0] == true }.compactMap { s.participants[$0]?.name(hebrew: he) }.joined(separator: ", ")
            Text(t("Ready: ", "מוכנים: ") + (readyNames.isEmpty ? t("Not yet", "עדיין לא") : readyNames)).multilineTextAlignment(.center)
            let mineReady = m.ready[model.userID] == true
            action(mineReady ? t("Cancel Ready", "ביטול מוכנות") : (s.kind == .friendly ? t("Start", "התחלה") : t("I'm Ready", "אני מוכן")),
                   color: mineReady ? MPStyle.lilac : MPStyle.mint) { Task { await model.ready(m) } }
        }
    }
    private func readyLine(_ s: MPSession, _ m: MPFixture, humans: [String], pair: Bool) -> String {
        let away = humans.filter { !s.connected($0) }
        if !away.isEmpty {
            let names = away.map { s.participants[$0]?.name(hebrew: he) ?? "?" }.joined(separator: ", ")
            return (pair ? t("Both are Ready. Waiting for ", "שניכם מוכנים. ממתינים לחיבור של ") : t("Everyone is Ready. Waiting for ", "כולם מוכנים. ממתינים לחיבור של ")) + names
        }
        if s.matches.values.contains(where: { other in other.id != m.id && other.phase == .playing && humans.contains(where: other.contains) }) {
            return t("A player has another unfinished match. Resume and finish it first.", "לאחד השחקנים יש משחק אחר שטרם הסתיים. יש לחזור אליו ולסיים אותו קודם.")
        }
        return pair ? t("Both are Ready. Starting…", "שניכם מוכנים. מתחילים…") : t("Everyone is Ready. Starting…", "כולם מוכנים. מתחילים…")
    }
    // ---- brackets and standings -----------------------------------------------------------------------------------------
    @ViewBuilder func bracket(_ s: MPSession) -> some View {
        if s.grouped { groupBracket(s) }
        else {
            card {
                Text(s.complete ? t("Tournament bracket", "עץ הטורניר") : MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
                Text(t("Swipe sideways to follow the bracket. Pairs are drawn again each round.", "החליקו לצדדים לצפייה בעץ. הזוגות מוגרלים מחדש בכל סיבוב.")).font(.caption).multilineTextAlignment(.center)
                ScrollView(.horizontal) { MPKnockoutBracketView(session: s, hebrew: he) }
                    .defaultScrollAnchor(he ? UnitPoint.trailing : UnitPoint.leading)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
    /// Android groupBracket: every round's tables in seat order, final scores, who goes through (✓), tie-breaks, final duels,
    /// walkovers and byes.
    private func groupBracket(_ s: MPSession) -> some View {
        card {
            Text(s.complete ? t("Tournament tables", "שולחנות הטורניר") : MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
            Text((MPKnockout.perTable(s) == 1 ? t("The winner of every table goes through.", "המקום הראשון בכל שולחן עולה.") : t("The top two of every table go through.", "שני הראשונים בכל שולחן עולים.")) + t(" ✓ = through.", " ✓ = עלו."))
                .font(.caption).multilineTextAlignment(.center)
            ForEach(s.rounds.keys.sorted(), id: \.self) { round in groupRound(s, round) }
        }
    }
    private func groupRound(_ s: MPSession, _ round: Int) -> some View {
        let drawn = s.rounds[round] ?? MPKnockoutRound(players: [])
        // Marked as soon as their table is decided, before the next round is drawn.
        let through = Set(MPKnockout.advancing(s, round))
        let tables = MPKnockout.matches(s, round)
        return VStack(spacing: 6) {
            Text(MPGroupTournament.stage(drawn.players.count, s.tableSize, hebrew: he, advance: MPKnockout.perTable(s))).font(.headline)
            ForEach(Array(tables.enumerated()), id: \.offset) { item in
                Text(t("Table \(item.offset + 1): ", "שולחן \(item.offset + 1): ") + MPMatchText.ordered(tableLine(s, item.element, through: through)) + phaseNote(item.element))
                    .font(.callout).multilineTextAlignment(.center)
                if let tie = s.matches[MPKnockout.tiebreakId(s.code, round, item.offset)] {
                    Text(t("Tie-break for 2nd place: ", "שובר שוויון על המקום השני: ") + MPMatchText.ordered(tie.players.map { mark($0, through) + name(s, $0) }.joined(separator: "  ·  ")) + phaseNote(tie))
                        .font(.footnote).multilineTextAlignment(.center)
                }
                if let duel = s.matches[MPRules.duelId(item.element.id)] {
                    Text(t("Final duel: ", "קרב גמר: ") + MPMatchText.ordered(tableLine(s, duel, through: through)) + phaseNote(duel)).font(.footnote).multilineTextAlignment(.center)
                }
            }
            ForEach(Array(drawn.walkovers.enumerated()), id: \.offset) { item in
                Text(MPKnockout.walkoverTitle(hebrew: he) + ": " + item.element.map { mark($0, through) + name(s, $0) }.joined(separator: ", ")).font(.footnote).multilineTextAlignment(.center)
            }
            if !drawn.byes.isEmpty {
                Text(t("Bye: ", "עולים ללא משחק: ") + drawn.byes.map { name(s, $0) }.joined(separator: ", ")).font(.footnote).multilineTextAlignment(.center)
            }
        }.padding(.vertical, 6)
    }
    private func name(_ s: MPSession, _ id: String) -> String { s.participants[id]?.name(hebrew: he) ?? "?" }
    private func mark(_ id: String, _ through: Set<String>) -> String { through.contains(id) ? "✓ " : "" }
    private func tableLine(_ s: MPSession, _ m: MPFixture, through: Set<String>) -> String {
        m.players.enumerated().map { item -> String in
            let score = m.phase == .finished ? " \(item.offset < m.scores.count ? m.scores[item.offset] : 0)" : ""
            return mark(item.element, through) + name(s, item.element) + score
        }.joined(separator: "  ·  ")
    }
    private func phaseNote(_ m: MPFixture) -> String {
        switch m.phase {
        case .finished: return ""
        case .playing: return t(" (playing)", " (משחקים)")
        case .cancelled: return t(" (cancelled)", " (בוטל)")
        case .waiting, .ready: return t(" (not started)", " (טרם התחיל)")
        }
    }
    /// Android PlayActivity.standings: placement points (or win points for pairs), wins, losses, started, finished, remaining.
    func standings(_ s: MPSession) -> some View {
        card {
            Text(t("Tournament table", "טבלת הטורניר")).font(.title3.bold())
            Text(t("Swipe sideways to see every column", "החליקו לצדדים כדי לראות את כל העמודות")).font(.caption)
            ScrollView(.horizontal) {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Text(t("Player", "שחקן")).frame(width: 156)
                        ForEach([t("Points", "נקודות"), t("Wins", "ניצחונות"), t("Losses", "הפסדים"), t("Started", "התחילו"), t("Finished", "הסתיימו"), t("Remaining", "נותרו")], id: \.self) { Text($0).frame(width: 76) }
                    }.font(.caption.bold()).frame(height: 52).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 9))
                    ForEach(Array(MPRules.standings(s).enumerated()), id: \.offset) { item in standingRow(s, item.element, index: item.offset) }
                }
            }
        }
    }
    private func standingRow(_ s: MPSession, _ row: MPStanding, index: Int) -> some View {
        let games = s.matches.values.filter { $0.contains(row.id) }
        let values = [row.points, row.wins, row.losses, games.filter { $0.phase == .playing }.count, row.played, games.filter { !$0.terminal }.count]
        let p = s.participants[row.id]
        let fill: Color = index % 2 == 0 ? Color(red: 231 / 255, green: 251 / 255, blue: 244 / 255) : Color(red: 241 / 255, green: 237 / 255, blue: 1)
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let p { playerPicture(p).frame(width: 44, height: 52) }
                Text((p?.name(hebrew: he) ?? "?") + (s.departed[row.id] == true ? t(" · Left", " · עזב/ה") : "")).font(.callout.bold()).lineLimit(2)
            }.frame(width: 156)
            ForEach(values.indices, id: \.self) { i in Text(String(values[i])).frame(width: 76) }
        }
        .frame(height: 68)
        .background(fill, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(row.id == model.userID ? MPStyle.pink : Color.clear, lineWidth: 2))
    }

    // ---- cross table screens --------------------------------------------------------------------------------------------
    private var courtLabel: String {
        t("Three or four player table tennis court. Your arm of the table is at the bottom. Send the ball to any other player.", "מגרש טניס שולחן לשלושה או ארבעה שחקנים. הזרוע שלכם בשולחן נמצאת למטה. שלחו את הכדור לכל שחקן אחר.")
    }
    /// The status of a court screen: white bold text on a dark rounded panel.
    private func courtStatus(_ text: String, wide: Bool) -> some View {
        Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(wide ? 12 : 3)
            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10).padding(.vertical, 4)
            .background(MPXMenu.status, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 4)
            .accessibilityAddTraits(.updatesFrequently)
    }
    /// Android PrivateMatchActivity cross screen (5c1aa4d MatchSceneLayout): Back, the stage and control level, the status line
    /// and the court, in portrait or landscape over the evening terrace.
    var crossMatchScreen: some View {
        MPXMatchLayout(tools: 1) {
            MPXTool(symbol: MPText.rtl ? "arrow.right" : "arrow.left", label: t("Back", "חזרה"), fill: MPStyle.bar) { model.back() }
        } status: { wide in
            VStack(spacing: 4) {
                Text(model.crossHeader).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                courtStatus(model.crossStatus, wide: wide)
            }
        } court: {
            if let court = model.crossScene {
                MPXCourt(scene: court, label: courtLabel)
                    .background(GeometryReader { geo in Color.clear.task(id: ObjectIdentifier(court)) {
                        // FamilyLandscapeHint (Android PrivateMatchActivity 5c1aa4d): a portrait court suggests landscape.
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        if geo.size.height > geo.size.width { model.toast = FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי.") }
                    } })
            }
        }
    }
    /// Android CrossActivity toolbar (5c1aa4d MatchToolbar): Back, pause, the action camera, the guide, a new match, settings.
    private var crossToolbar: some View {
        Group {
            MPXTool(symbol: MPText.rtl ? "arrow.right" : "arrow.left", label: t("Back", "חזרה"), fill: MPStyle.bar) { model.back() }
            MPXTool(symbol: model.crossPaused ? "play.fill" : "pause.fill", label: model.crossPaused ? t("Resume", "המשך") : t("Pause", "השהיה"),
                    fill: model.crossPaused ? Color(red: 22 / 255, green: 163 / 255, blue: 94 / 255) : MPStyle.pink) { model.toggleCrossPause() }
            MPXTool(symbol: "camera.viewfinder", label: t("Action camera / fit all players", "מצלמת פעולה / כל השחקנים במסך"),
                    fill: Color(red: 29 / 255, green: 112 / 255, blue: 176 / 255)) { model.toggleActionCamera() }
            MPXTool(symbol: "questionmark", label: t("How to play", "איך משחקים"), fill: Color(red: 247 / 255, green: 204 / 255, blue: 79 / 255)) { model.startTour() }
            MPXTool(symbol: "arrow.counterclockwise", label: t("New match", "משחק חדש"), fill: Color(red: 48 / 255, green: 72 / 255, blue: 99 / 255)) { model.restartCross() }
            MPXTool(symbol: "gearshape.fill", label: t("Settings", "הגדרות"), fill: Color(red: 48 / 255, green: 72 / 255, blue: 99 / 255)) { openCrossSettings() }
        }
    }
    private func openCrossSettings() {
        crossSettingsWasPaused = model.crossSettingsOpened()
        settingsPlayers = model.preferences.crossPlayers
        settingsTarget = model.preferences.crossTarget
        settingsControl = model.preferences.control
        settingsOpponents = Array(model.preferences.crossOpponents.prefix(3))
        showCrossSettings = true
    }
    /// Android CrossActivity: the local match, its status line, the guide's cards and the result, in the match layout.
    var crossGame: some View {
        MPXMatchLayout(tools: 6) {
            crossToolbar
        } status: { wide in
            courtStatus(model.crossStatus, wide: wide)
        } court: {
            ZStack {
                if let court = model.crossScene {
                    MPXCourt(scene: court, label: courtLabel)
                        .background(GeometryReader { geo in Color.clear.task(id: ObjectIdentifier(court)) {
                            // FamilyLandscapeHint: a portrait court suggests landscape once.
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            if geo.size.height > geo.size.width { model.toast = FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי.") }
                        } })
                }
                if let tourCard = model.tourCard { tourCardView(tourCard) }
            }
        }
        // Android 1dbfe33 MatchResultDialog: the result card over the whole match screen.
        .overlay { if let outcome = model.crossResult { crossResultView(outcome) } }
    }
    private func tourCardView(_ tourCard: CrossTourCard) -> some View {
        VStack(spacing: 10) {
            Text(tourCard.title).font(.title2.bold()).multilineTextAlignment(.center)
            ScrollView { Text(tourCard.message).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }.frame(maxHeight: 300)
            tourActions(tourCard)
        }
        .padding(18).frame(maxWidth: 520)
        .background(.white, in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 10).padding(16)
    }
    @ViewBuilder private func tourActions(_ tourCard: CrossTourCard) -> some View {
        let blue = Color(red: 133 / 255, green: 215 / 255, blue: 1), yellow = Color(red: 1, green: 211 / 255, blue: 90 / 255)
        let mint = Color(red: 122 / 255, green: 231 / 255, blue: 190 / 255), gray = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
        // Android 5c1aa4d: the team and scoring cards lead to the team game first (R.string.guide_team_practice).
        if tourCard.phase == .info && tourCard.teamPractice {
            action(MPText.journey("Learn team play"), color: blue) { model.tourTeamPractice() }
        }
        switch tourCard.phase {
        case .explain:
            action(t("Show me", "הראו לי"), color: blue) { model.tourShow() }
            action(t("Try it yourself", "עכשיו תורכם"), color: yellow) { model.tourTry() }
        case .result:
            action(t("Try again", "ננסה שוב"), color: blue) { model.tourTry() }
        default:
            EmptyView()
        }
        HStack(spacing: 8) {
            if tourCard.canGoBack { action(t("Back", "חזרה"), color: gray) { model.tourBack() } }
            action(t("Next", "הבא"), color: yellow) { model.tourNext() }
        }
        action(t("To the game", "למשחק"), color: mint) { model.endTour() }
    }
    private func crossResultView(_ outcome: CrossLocalResult) -> some View {
        MPXResultCard(title: outcome.title, rows: outcome.rows,
                      primary: .init(title: t("Play again", "לשחק שוב")) { model.closeCrossResult(playAgain: true) },
                      secondary: .init(title: t("Menu", "תפריט")) { model.closeCrossResult(playAgain: false) },
                      note: t("Completed games are not saved.", "משחקים שהסתיימו אינם נשמרים."))
    }
    /// Android CrossActivity.showSettings: players, control level, points to win and the three house players.
    var crossSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Android 5c1aa4d: the reception assistance comes first in the settings.
                    MPXReceptionSettings(preferences: model.preferences, hebrew: he)
                    Text(t("Players at the table", "שחקנים סביב השולחן")).font(.headline)
                    Picker(t("Players at the table", "שחקנים סביב השולחן"), selection: $settingsPlayers) {
                        Text(t("3 players (Y table)", "3 שחקנים (שולחן Y)")).tag(3)
                        Text(t("4 players (cross table)", "4 שחקנים")).tag(4)
                    }.pickerStyle(.segmented)
                    Text(t("Control level", "רמת השליטה")).font(.headline)
                    Picker(t("Control level", "רמת השליטה"), selection: $settingsControl) {
                        Text(t("Beginner", "מתחילים")).tag(MPLevel.beginner)
                        Text(t("Standard", "רגילה")).tag(MPLevel.easy)
                        Text(t("Pro", "מקצועני")).tag(MPLevel.superHard)
                    }.pickerStyle(.segmented)
                    Text(t("Points to win", "נקודות לניצחון")).font(.headline)
                    Picker(t("Points to win", "נקודות לניצחון"), selection: $settingsTarget) { ForEach([3, 5, 7], id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.segmented)
                    Text(t("House players", "שחקני הבית")).font(.headline)
                    ForEach(0..<min(3, settingsOpponents.count), id: \.self) { slot in opponentMenu(slot) }
                    Text(t("Beginner: keep your paddle in the ball's path for an automatic hit; swipe a little left or right before the ball arrives to choose who gets it (the 🎯 shows who). Standard: tap as the ball arrives, drag sideways to aim, a faster drag hits harder. Pro: swipe through the ball toward a player.",
                           "מתחילים: השאירו את המחבט במסלול הכדור לחבטה אוטומטית; החליקו מעט שמאלה או ימינה לפני שהכדור מגיע כדי לבחור למי (ה־🎯 מראה למי). רגילה: הקישו כשהכדור מגיע, גררו הצידה לכיוון, גרירה מהירה חזקה יותר. מקצועני: החליקו דרך הכדור לעבר שחקן."))
                        .font(.footnote).multilineTextAlignment(.center)
                    // Android setPositiveButton(R.string.new_match): a resource string, shorter in Dutch than its catalog row.
                    action(MPText.resource("Apply & start new match", "החלת ההגדרות ומשחק חדש", he), color: MPStyle.mint) {
                        crossSettingsWasPaused = true
                        model.applyCrossSettings(players: settingsPlayers, control: settingsControl, target: settingsTarget, opponents: settingsOpponents)
                        showCrossSettings = false
                    }
                    action(t("Cancel", "ביטול"), color: MPStyle.lilac) { showCrossSettings = false }
                }.padding(24)
            }
            .navigationTitle(t("Settings", "הגדרות")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showCrossSettings = false } } }
        }
    }
    /// One house-player slot; choosing a character used by another slot swaps the two.
    private func opponentMenu(_ slot: Int) -> some View {
        Menu {
            ForEach(MPRoster.all) { player in
                Button(player.name(hebrew: he)) {
                    var chosen = settingsOpponents
                    if let other = chosen.firstIndex(of: player.id), other != slot { chosen[other] = chosen[slot] }
                    chosen[slot] = player.id
                    settingsOpponents = chosen
                }
            }
        } label: {
            let id = settingsOpponents[slot]
            HStack(spacing: 10) {
                MPAvatar(character: id, icon: 0).frame(width: 44, height: 44)
                Text("\(slot + 1). " + (MPRoster.find(id)?.name(hebrew: he) ?? id)).font(.headline)
                Spacer()
                Image(systemName: "chevron.down")
            }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 15))
    }
}
