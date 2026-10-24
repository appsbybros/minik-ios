import SwiftUI
import Combine
import UIKit

/// Android `PongOnlineTeamsActivity`: invite-only live doubles. Each friend brings their own nickname and character
/// and is ready as soon as they connect; the host arranges the teams and starts.
@MainActor final class MPOnlineTeamsController: ObservableObject {
    enum Pane { case setup, connecting, error, lobby, bench, game }
    @Published private(set) var pane = Pane.setup
    @Published var mode: MPTeamMode
    @Published var code = ""
    @Published private(set) var errorText = ""
    @Published var toast: String?
    @Published var confirmLeave = false
    @Published var picking: Int?
    @Published var share: MPShareItem?
    @Published private(set) var room: MPTeamRoom?
    @Published private(set) var manuallyPaused = false
    @Published private(set) var resumed = true
    /// Android 22f756e/a4174b6: the room's arena (fixed when it is created) and this player's control difficulty
    /// (ControlChoice 4/1/0/3), sent once per connection as a `control` input.
    @Published var arena: MPArena { didSet { UserDefaults.standard.set(arena.wire, forKey: "modern.pong.teams.arena") } }
    @Published var control: Int { didSet { UserDefaults.standard.set(control, forKey: "modern.pong.teams.control") } }
    private var sentControl = false
    let identity: MPTeamIdentity
    let hebrew: Bool
    var onExit: (() -> Void)?
    private var cancelling = false
    private var watch: AnyCancellable?
    init(mode: MPTeamMode, identity: MPTeamIdentity, hebrew: Bool, arena: MPArena = .beach, control: Int = 0) {
        self.mode = mode; self.identity = identity; self.hebrew = hebrew
        self.arena = MPArena.choices.contains(arena) ? arena : .beach; self.control = MPControlChoice.normalize(control)
    }
    func tr(_ en: String, _ he: String) -> String { hebrew ? he : en }
    var title: String {
        switch pane {
        case .setup: return tr("Online team game", "משחק קבוצתי ברשת")
        case .connecting: return tr("Connecting…", "מתחברים…")
        case .error: return tr("Let’s find your table", "בואו נמצא את השולחן שלכם")
        case .lobby: return tr("Choose your teams", "בחירת הקבוצות")
        case .bench, .game: return tr("Team match", "משחק קבוצתי")
        }
    }
    /// Android `navigateBack`: before a room, leave; in the lobby, cancel the room; at the table, confirm first.
    func back() {
        guard let room else { onExit?(); return }
        if room.phase == "lobby" { cancelRoom() } else { confirmLeave = true }
    }
    func leaveTable() { confirmLeave = false; onExit?() }
    func close() { watch = nil; room?.close(); room = nil }
    func lifecycle(active: Bool) { resumed = active; room?.setActive(active && !manuallyPaused) }
    func togglePause() { manuallyPaused.toggle(); room?.setActive(resumed && !manuallyPaused) }
    func cancelRoom() {
        if cancelling { return }
        guard let room else { onExit?(); return }
        cancelling = true
        room.cancel { [weak self] ok in
            guard let self else { return }
            self.cancelling = false
            if ok { self.watch = nil; self.room = nil; self.onExit?() }
            else { self.toast = self.tr("Could not cancel. Check your connection and try again.", "לא ניתן לבטל. בדקו את החיבור ונסו שוב.") }
        }
    }
    func create() { let arena = self.arena.wire; connect { $0.createFlexible(self.mode, arena: arena) } }
    func join() { let value = code; connect { $0.join(value) } }
    private func connect(_ action: @escaping (MPTeamRoom) -> Void) {
        close(); sentControl = false; pane = .connecting
        let r = MPTeamRoom(identity: identity)
        r.failed = { [weak self] message in
            guard let self else { return }
            if self.pane == .connecting { self.connectionError(message) }
            else { self.toast = self.tr("Connection interrupted. The table waits while you reconnect.", "החיבור נקטע. השולחן ממתין עד שתחזרו להתחבר.") }
        }
        room = r
        watch = r.$revision.sink { [weak self] _ in Task { @MainActor [weak self] in self?.render() } }
        r.connect { action(r) }
    }
    private func connectionError(_ message: String) {
        close(); pane = .error
        switch message {
        case "Check the six-character room code.": errorText = tr("Enter the six characters your friend shared.", "הזינו את ששת התווים שהחבר שיתף.")
        case "Room not found.": errorText = tr("We couldn’t find that room. Check the code with your friend.", "לא מצאנו את החדר. בדקו את הקוד עם החבר.")
        case "This match has already started.": errorText = tr("This match has already started. Ask your friend to create a new table for you.", "המשחק כבר התחיל. בקשו מהחבר ליצור שולחן חדש בשבילכם.")
        case "No invited place is available.": errorText = tr("All friend places are occupied. Ask someone to leave the room before joining.", "כל המקומות לחברים תפוסים. בקשו ממישהו לצאת מהחדר לפני ההצטרפות.")
        case "This room needs a newer app version.": errorText = tr("Update the app to join this table.", "עדכנו את האפליקציה כדי להצטרף לשולחן הזה.")
        default: errorText = tr("Check your connection and try again. Your existing room can be reopened using its code.", "בדקו את החיבור ונסו שוב. אפשר לחזור לחדר הקיים בעזרת הקוד שלו.")
        }
    }
    func setup() { pane = .setup }
    /// Android `render`: the pane follows the room's phase and this player's place.
    private func render() {
        guard let r = room else { return }
        if r.phase == "closed" && !cancelling {
            close(); toast = tr("This room was cancelled", "החדר בוטל"); pane = .setup; return
        }
        guard !r.code.isEmpty, !r.meta.isEmpty, r.members[r.uid] != nil else { return }
        let playing = r.phase == "playing" || r.phase == "finished"
        if playing && r.localSeat < 0 { pane = .bench; return }
        if playing && r.game != nil {
            if pane != .game { pane = .game }
            if !sentControl && !r.waiting && r.supportsSpinControls { r.input("control", MPPoint(0.5, 0.5), control: control); sentControl = true }
            return
        }
        if r.phase == "lobby" && pane != .lobby { pane = .lobby }
    }
    func hud(_ r: MPTeamRoom) -> String {
        guard let g = r.game, g.actors.indices.contains(r.localSeat) else { return "" }
        let own = g.actors[r.localSeat].team
        return "\(g.points[own]) : \(g.points[1 - own])"
    }
    /// Android: the own team's score first, each in its team colour.
    func coloredHud(_ r: MPTeamRoom) -> AttributedString? {
        guard let g = r.game, g.actors.indices.contains(r.localSeat) else { return nil }
        let own = g.actors[r.localSeat].team
        return MPJourneyController.teamScore(g.points[own], g.points[1 - own], firstTeam: own, seed: g.seed)
    }
    /// The control the table reads input with: older hosts only understand taps.
    func tableControl(_ r: MPTeamRoom) -> Int { r.supportsSpinControls ? control : 0 }
    func hintIsTip(_ r: MPTeamRoom) -> Bool { r.game?.notice.hasPrefix("serve-double-bounce-") == true }
    func hint(_ r: MPTeamRoom) -> String {
        guard let g = r.game, g.actors.indices.contains(r.localSeat) else { return "" }
        let own = g.actors[r.localSeat].team
        if g.notice.hasPrefix("diagonal-serve-") { return MPHelpTips.diagonal(he: hebrew, ownPoint: g.notice != "diagonal-serve-\(own)") }
        if g.notice == "serve-double-bounce-\(own)" && g.showServePointTip { return MPHelpTips.serveDoubleBouncePoint(he: hebrew) }
        if let ending = g.ending { return ending.message(hebrew, ownTeam: own) }
        if r.phase == "finished" { return tr("Match complete", "המשחק הסתיים") }
        if r.waiting { return tr("Waiting for every player to return", "ממתינים שכל השחקנים יחזרו") }
        if g.waitingServe && g.nextHitter[g.server] != r.localSeat { return tr("Your tablemate is serving", "שחקן אחר מגיש") }
        if g.waitingServe { return tr("Tap the far side to serve", "הקישו בצד הרחוק כדי להגיש") }
        if g.alternate && g.nextHitter[own] != r.localSeat { return tr("Your teammate's turn. Move aside.", "תור חבר הקבוצה. פנו לו מקום.") }
        if control == 3 && r.supportsSpinControls { return tr("Swipe to aim · arc for topspin · left–right for sidespin", "מחליקים לכיוון · קשת לסיבוב קדמי · שמאלה–ימינה לסיבוב צדי") }
        if control == 0 || control == 1 { return tr("Move into reach · swipe toward your target as the ball arrives", "זזים אל הכדור · מחליקים לכיוון המטרה כשהוא מגיע") }
        return tr("Drag to move · tap the far side to hit", "גררו כדי לזוז · הקישו בצד הרחוק כדי לחבוט")
    }
    func invitation(_ code: String) -> String {
        tr("Join my Minik Ping Pong team table! Open the app, choose Online team game, then enter room code: \(code)", "בואו לשולחן הקבוצתי שלי ב־מיניק פינג פונג! פתחו את האפליקציה, בחרו משחק קבוצתי ברשת והזינו את הקוד: \(code)")
    }
}

struct MPOnlineTeamsScreen: View {
    @ObservedObject var model: MPOnlineTeamsController
    private func t(_ en: String, _ he: String) -> String { model.tr(en, he) }
    private func text(_ value: String, size: CGFloat = 18) -> some View {
        Text(value).font(.system(size: size, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 6).fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        Group {
            switch model.pane {
            case .setup: setup
            case .connecting: MPJourneyPanel { text(t("Finding your table…", "מחפשים את השולחן שלכם…")); ProgressView() }
            case .error: MPJourneyPanel { text(model.errorText); MPJourneyButton(title: t("Back to team rooms", "חזרה לחדרים הקבוצתיים"), accent: true) { model.setup() } }
            case .bench: MPJourneyPanel { text(t("This match has started with the selected players.", "המשחק התחיל עם השחקנים שנבחרו.")); MPJourneyButton(title: t("Back", "חזרה")) { model.leaveTable() } }
            case .lobby: if let room = model.room { MPTeamLobbyView(model: model, room: room) }
            case .game: if let room = model.room { MPTeamTableView(model: model, room: room) }
            }
        }
        .alert(model.toast ?? "", isPresented: Binding(get: { model.toast != nil }, set: { if !$0 { model.toast = nil } })) {
            Button(t("OK", "אישור")) { model.toast = nil }
        }
        .alert(t("Leave the table?", "לצאת מהשולחן?"), isPresented: $model.confirmLeave) {
            Button(t("Leave", "יציאה"), role: .destructive) { model.leaveTable() }
            Button(t("Keep playing", "ממשיכים לשחק"), role: .cancel) { model.confirmLeave = false }
        } message: { Text(t("The match waits for you. Use the room code to return; a bot will not replace you.", "המשחק ממתין לכם. אפשר לחזור עם קוד החדר; שחקן בית לא יחליף אתכם.")) }
        .sheet(item: $model.share) { item in MPShareSheet(text: item.text) }
    }
    private var setup: some View {
        MPJourneyPanel {
            text(t("Team rules", "חוקי הקבוצה"))
            MPChoiceBar(title: t("Team rules", "חוקי הקבוצה"), options: MPTeamMode.allCases.map { (value: $0, label: $0.title(model.hebrew)) }, selection: $model.mode)
            text(t("Control difficulty", "רמת השליטה"))
            MPJourneySelector(title: t("Control difficulty", "רמת השליטה"), options: MPJourneyController.controlLevels.map { (value: $0, label: MPJourneyScreen.controlTitle($0, model.hebrew)) }, selection: $model.control)
            text(model.mode.explanation(model.hebrew), size: 15)
            text(t("Arena", "זירה"))
            MPJourneySelector(title: t("Arena", "זירה"), options: MPArena.choices.map { (value: $0, label: $0.title(he: model.hebrew)) }, selection: $model.arena)
            MPJourneyButton(title: t("Create team room", "יצירת חדר קבוצתי"), accent: true) { model.create() }.padding(.top, 10)
            MPDashedDivider()
            TextField(t("Room code", "קוד החדר"), text: Binding(get: { model.code }, set: { model.code = String($0.uppercased().prefix(6)) }))
                .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.title3.bold()).multilineTextAlignment(.center)
                .foregroundStyle(MPJourneyStyle.ink).padding(12).frame(minHeight: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8)).environment(\.layoutDirection, .leftToRight)
            MPJourneyButton(title: t("Join team room", "הצטרפות לחדר קבוצתי")) { model.join() }.padding(.top, 8)
            MPJourneyButton(title: t("Cancel", "ביטול"), fill: MPStyle.pink, textColor: .white) { model.cancelRoom() }.padding(.top, 24)
        }
    }
}

/// Android `FamilyTournamentUi.divider`: a dashed line with generous space around it between Create and Join.
struct MPDashedDivider: View {
    var body: some View {
        GeometryReader { proxy in
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: proxy.size.width, y: 1)) }
                .stroke(Color(red: 0x78 / 255, green: 0x92 / 255, blue: 0xad / 255), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }.frame(height: 2).padding(.horizontal, 8).padding(.vertical, 24).accessibilityHidden(true)
    }
}

/// Android lobby: the room code, copy and invite, the two team columns and Start (host) or Cancel.
struct MPTeamLobbyView: View {
    @ObservedObject var model: MPOnlineTeamsController
    @ObservedObject var room: MPTeamRoom
    private func t(_ en: String, _ he: String) -> String { model.tr(en, he) }
    var body: some View {
        MPJourneyPanel {
            Text(t("Room code: ", "קוד החדר: ") + room.code).font(.system(size: 22, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                MPJourneyButton(title: t("Copy code", "העתקת הקוד"), accent: true) { UIPasteboard.general.string = room.code; model.toast = t("Room code copied", "קוד החדר הועתק") }
                MPJourneyButton(title: t("Invite a friend", "הזמנת חבר")) { model.share = MPShareItem(text: model.invitation(room.code)) }
            }.padding(.vertical, 8)
            board.padding(.top, 16).padding(.bottom, 8)
            if !room.flexible { Text(t("This older room keeps its original places. Create a new room to arrange the teams.", "בחדר הישן הזה המקומות קבועים. צרו חדר חדש כדי לסדר את הקבוצות.")).font(.system(size: 15, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center) }
            if room.host && room.localSeat < 0 { Text(t("Choose yourself for a place before starting.", "בחרו לעצמכם מקום לפני תחילת המשחק.")).font(.system(size: 16, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center) }
            if room.host {
                MPJourneyButton(title: t("Start match", "מתחילים במשחק"), face: MPCourtStyle.startFace) { room.start() }
                    .disabled(!room.canStart).opacity(room.canStart ? 1 : 0.42).padding(.top, 12)
                    .accessibilityLabel(room.canStart ? t("Start match", "מתחילים במשחק") : t("Choose every player and wait for selected friends to connect", "בחרו שחקן לכל מקום והמתינו לחיבור החברים שבחרתם"))
            }
            MPJourneyButton(title: t("Cancel", "ביטול"), fill: MPStyle.pink, textColor: .white) { model.cancelRoom() }.padding(.top, 20)
        }
        .sheet(isPresented: Binding(get: { model.picking != nil }, set: { if !$0 { model.picking = nil } })) {
            if let seat = model.picking { MPTeamPlayerPicker(model: model, room: room, seat: seat) }
        }
    }
    /// Android `TeamLobbyCards.board`: "Your team" first (left in English, right in Hebrew).
    private var board: some View {
        let groups = room.localSeat >= 2 ? [[2, 3], [0, 1]] : [[0, 1], [2, 3]]
        let editable = room.host && room.flexible
        return HStack(alignment: .top, spacing: 12) {
            ForEach(groups.indices, id: \.self) { index in
                VStack(spacing: 12) {
                    ForEach(groups[index], id: \.self) { seat in tile(seat, editable: editable) }
                    Text(index == 0 ? t("Your team", "הקבוצה שלכם") : t("Other team", "הקבוצה היריבה")).font(.system(size: 18, weight: .bold)).foregroundStyle(MPJourneyStyle.ink)
                    Text(editable ? t("Tap a player to change", "הקישו על שחקן כדי להחליף") : t("The host arranges the teams", "המארח מסדר את הקבוצות")).font(.system(size: 14, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 6).padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(index == 0 ? Color(red: 0xfc / 255, green: 0xe5 / 255, blue: 0xf1 / 255) : Color(red: 0xe3 / 255, green: 0xef / 255, blue: 1), in: RoundedRectangle(cornerRadius: 18))
            }
        }.environment(\.layoutDirection, model.hebrew ? .rightToLeft : .leftToRight)
    }
    private func tile(_ seat: Int, editable: Bool) -> some View {
        let user = room.playerAt(seat), occupied = room.occupied(seat)
        let name = occupied ? room.nameAt(seat, hebrew: model.hebrew) : (room.host ? t("Tap to choose", "הקישו לבחירה") : t("Waiting for the host", "ממתינים לבחירת המארח"))
        let connected = user.map { room.present($0) } ?? true
        return Button { if editable { model.picking = seat } } label: {
            VStack(spacing: 4) {
                if occupied { MPAvatar(character: room.characterAt(seat), icon: 0).frame(height: 112) }
                else { MPEmptyPlayer().frame(height: 112) }
                Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                if !connected { Text(t("Reconnecting…", "מתחבר מחדש…")).font(.system(size: 13, weight: .bold)).foregroundStyle(MPJourneyStyle.ink) }
            }.padding(6).frame(maxWidth: .infinity).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(!editable)
            .accessibilityLabel(name + (editable ? t(". Tap to change player", ". הקישו להחלפת שחקן") : ""))
    }
}

/// Android `TeamLobbyCards.EmptyPlayer`: a grey silhouette with a question mark.
struct MPEmptyPlayer: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 3, size.height / 3), x = size.width / 2
            let grey = Color(red: 0x60 / 255, green: 0x77 / 255, blue: 0x85 / 255).opacity(135.0 / 255)
            context.fill(Path(ellipseIn: CGRect(x: x - unit * 0.42, y: size.height * 0.28 - unit * 0.42, width: unit * 0.84, height: unit * 0.84)), with: .color(grey))
            context.fill(Path(roundedRect: CGRect(x: x - unit * 0.7, y: size.height * 0.47, width: unit * 1.4, height: size.height * 0.46), cornerRadius: unit * 0.25), with: .color(grey))
            context.draw(Text("?").font(.system(size: unit * 0.75, weight: .bold)).foregroundColor(.white), at: CGPoint(x: x, y: size.height * 0.70))
        }.accessibilityHidden(true)
    }
}

/// Android `TeamLobbyCards.picker`: connected friends first (moved, never duplicated), then house players, or empty.
struct MPTeamPlayerPicker: View {
    @ObservedObject var model: MPOnlineTeamsController
    @ObservedObject var room: MPTeamRoom
    let seat: Int
    private func t(_ en: String, _ he: String) -> String { model.tr(en, he) }
    private func choose(_ value: String) { room.chooseSlot(seat, value); model.picking = nil }
    var body: some View {
        let current = (room.lineup?.slots.indices.contains(seat) ?? false) ? room.lineup!.slots[seat] : MPTeamLineup.empty
        let people = room.members.sorted { $0.value < $1.value }.compactMap { entry -> MPConnectedFriend? in
            guard let identity = room.profiles[entry.key], room.present(entry.key), "u:" + entry.key != current else { return nil }
            return MPConnectedFriend(id: entry.key, identity: identity)
        }
        let bots = MPRoster.all.filter { "b:" + $0.id != current }
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !people.isEmpty {
                        Text(t("Connected friends", "חברים מחוברים")).font(.system(size: 19, weight: .bold)).foregroundStyle(MPJourneyStyle.ink)
                        ForEach(people) { person in
                            Button { choose("u:" + person.id) } label: {
                                HStack { MPAvatar(character: person.identity.character, icon: 0).frame(width: 66, height: 76); Text(person.identity.name).font(.system(size: 17, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).frame(maxWidth: .infinity) }
                                    .padding(6).background(Color(red: 0xe4 / 255, green: 0xf0 / 255, blue: 1), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityLabel(person.identity.name)
                        }
                    }
                    Text(t("House players", "שחקני הבית")).font(.system(size: 19, weight: .bold)).foregroundStyle(MPJourneyStyle.ink)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 12) {
                        ForEach(bots) { bot in
                            Button { choose("b:" + bot.id) } label: {
                                VStack(spacing: 2) { MPAvatar(character: bot.id, icon: 0).frame(height: 96); Text(bot.name(hebrew: model.hebrew)).font(.system(size: 14, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).lineLimit(1).minimumScaleFactor(0.7) }
                                    .padding(4).frame(maxWidth: .infinity).background(Color(red: 0xe5 / 255, green: 0xf7 / 255, blue: 0xf1 / 255), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityLabel(bot.name(hebrew: model.hebrew))
                        }
                    }
                    if current != MPTeamLineup.empty {
                        Button { choose(MPTeamLineup.empty) } label: {
                            Text(t("Leave this place empty", "השארת המקום פנוי")).font(.system(size: 17, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(t("Choose a player", "בחירת שחקן")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "ביטול")) { model.picking = nil }.foregroundStyle(MPJourneyStyle.link) } }
        }.environment(\.layoutDirection, model.hebrew ? .rightToLeft : .leftToRight)
        // The sheet is its own presentation: on Dark Mode devices its title would be white on this white page.
        .preferredColorScheme(.light)
    }
}

struct MPConnectedFriend: Identifiable { let id: String; let identity: MPTeamIdentity }

/// Android online team table (29f5dc7): the friend's view of the authority's snapshots; moves, taps and strokes go to
/// the host. The arena's scenery is drawn behind it.
struct MPTeamTableView: View {
    @ObservedObject var model: MPOnlineTeamsController
    @ObservedObject var room: MPTeamRoom
    private func t(_ en: String, _ he: String) -> String { model.tr(en, he) }
    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            if let g = room.game {
                let link = room, control = model.tableControl(room)
                let names = Dictionary(uniqueKeysWithValues: (0..<4).map { ($0, room.nameAt($0, hebrew: model.hebrew)) })
                let court = MPPracticeCourt(game: g, hebrew: model.hebrew, localSeat: max(room.localSeat, 0), simulate: false, running: model.resumed, names: names,
                                            controlOverride: control, soundsEnabled: { MPJourneyController.soundsOn },
                                            onMove: { point in link.input("move", point) }, onTap: { point in link.input("tap", point) },
                                            onStroke: { stroke in link.input("stroke", MPPoint(0.5, 0.5), control: control, stroke: stroke) })
                ZStack {
                    if wide {
                        // Android PongCourtStyle.landscape: tools and coaching in the start gutter, an equal empty gutter.
                        let side = min(max(proxy.size.width * 0.19, 144), 192)
                        HStack(spacing: 0) { sidebar.frame(width: side); court; Color.clear.frame(width: side) }
                    } else { VStack(spacing: 6) { controls; court } }
                    MPOrientationToast(hebrew: model.hebrew)
                }
                .onAppear { MPOrientationHint.shared.observe(wide: wide); MPOrientationHint.shared.schedule(active: { room.game?.ended == false }, wide: { wide }) }
                .onChange(of: wide) { _, value in MPOrientationHint.shared.observe(wide: value) }
            }
        }
        .padding(.horizontal, 6).padding(.bottom, 6)
        .background { MPArenaBackdrop(arena: room.arena) }
    }
    private var score: some View {
        Group {
            if let colored = model.coloredHud(room) { Text(colored) } else { Text(model.hud(room)).foregroundStyle(.white) }
        }
        .font(.system(size: 28, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity).environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(model.hud(room))
    }
    private var hint: some View {
        let tip = model.hintIsTip(room)
        return Text(model.hint(room)).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(tip ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: tip ? .leading : .center).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 14)
    }
    private var pause: some View {
        Button { model.togglePause() } label: {
            Image(systemName: model.manuallyPaused ? "play.fill" : "pause.fill").font(.title3).foregroundStyle(MPJourneyStyle.ink).frame(width: 48, height: 48)
                .background(MPJourneyStyle.cyan, in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityLabel(t("Pause / Continue", "השהיה / המשך"))
    }
    /// Android portrait bar: the score centred in a 56-point row, Pause at the end, the coaching below.
    private var controls: some View {
        VStack(spacing: 0) {
            ZStack { score.padding(.horizontal, 64); HStack { Spacer(); pause.padding(.trailing, 6) } }.frame(height: 56)
            hint
        }.padding(8).background(MPJourneyStyle.hudBar, in: RoundedRectangle(cornerRadius: 18))
    }
    private var sidebar: some View {
        VStack(spacing: 4) {
            pause.frame(height: 48)
            ScrollView {
                VStack(spacing: 14) {
                    score.shadow(color: MPColor.color(0xff071b3b), radius: 1.4)
                    hint.shadow(color: MPColor.color(0xff071b3b), radius: 1.4)
                }
            }
            Color.clear.frame(height: 48)
        }.padding(.horizontal, 8).padding(.vertical, 4)
    }
}
