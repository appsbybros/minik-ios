import SwiftUI

/// One place of the team lobby (Android LobbyPlayer).
struct MPXLobbyPlayer: Identifiable {
    var seat: Int
    var token: String
    var name: String
    var character: String?
    var connected = true
    var id: Int { seat }
}

/// Android cross/CrossOnlineTeamsActivity.kt (MinikCrossPong 5c1aa4d): invite-only live doubles. Create or join a room by its
/// six-character code; the host arranges both teams with connected friends and house players; every friend brings their own
/// nickname and character and is ready when connected; the host's phone runs the shared match.
@MainActor final class CrossTeamsModel: ObservableObject {
    enum Page { case setup, connecting, error, lobby, bench, game }
    @Published private(set) var page: Page = .setup
    @Published var mode: String
    @Published var code = ""
    @Published private(set) var explanation = ""
    @Published private(set) var court: CrossScene?
    @Published private(set) var hint = ""
    @Published var notice: String?
    @Published var picker: Int?
    @Published var confirmLeave = false
    @Published var help = false
    @Published var shareText: String?
    @Published private(set) var revision = 0
    @Published var actionCamera: Bool { didSet { preferences.crossActionCamera = actionCamera; court?.fullScreen = actionCamera } }
    private(set) var link: CrossTeamRoom?
    private var cancelling = false, manuallyPaused = false, foreground = true
    let preferences: MPPreferences
    let hebrew: Bool
    private let audio: MPAudio
    private let onClose: () -> Void

    init(players: Int, preferences: MPPreferences, hebrew: Bool, audio: MPAudio, onClose: @escaping () -> Void) {
        mode = players == 3 ? "THREE" : "FOUR"
        self.preferences = preferences; self.hebrew = hebrew; self.audio = audio; self.onClose = onClose
        actionCamera = preferences.crossActionCamera
    }
    /// Android `tr`: English or Hebrew only, as the activity writes them.
    func tr(_ en: String, _ he: String) -> String { hebrew ? he : en }

    // ---- connection ------------------------------------------------------------------------------------------------------------
    func create() { connect { $0.createFlexible(mode: self.mode) } }
    func join() { let value = code; connect { $0.join(value) } }
    private func connect(_ action: @escaping (CrossTeamRoom) -> Void) {
        link?.close(); link = nil
        page = .connecting
        guard let room = CrossTeamRoom.make(preferences: preferences, hebrew: hebrew, changed: { [weak self] in self?.render() },
                                            failed: { [weak self] message in self?.failed(message) }) else { connectionError(""); return }
        link = room
        room.connect { action(room) }
    }
    private func failed(_ message: String) {
        if page == .connecting { connectionError(message) }
        else { notice = tr("Connection interrupted. The table waits while you reconnect.", "החיבור נקטע. השולחן ממתין עד שתחזרו להתחבר.") }
    }
    private func connectionError(_ message: String) {
        link?.close(); link = nil; leaveCourt()
        page = .error
        switch message {
        case CrossTeamRoom.Message.code: explanation = tr("Enter the six characters your friend shared.", "הזינו את ששת התווים שהחבר שיתף.")
        case CrossTeamRoom.Message.notFound: explanation = tr("We couldn’t find that room. Check the code with your friend.", "לא מצאנו את החדר. בדקו את הקוד עם החבר.")
        case CrossTeamRoom.Message.started: explanation = tr("This match has already started. Ask your friend to create a new table for you.", "המשחק כבר התחיל. בקשו מהחבר ליצור שולחן חדש בשבילכם.")
        case CrossTeamRoom.Message.full: explanation = tr("All friend places are occupied. Ask someone to leave the room before joining.", "כל המקומות לחברים תפוסים. בקשו ממישהו לצאת מהחדר לפני ההצטרפות.")
        case CrossTeamRoom.Message.newer: explanation = tr("Update the app to join this table.", "עדכנו את האפליקציה כדי להצטרף לשולחן הזה.")
        default: explanation = tr("Check your connection and try again. Your existing room can be reopened using its code.", "בדקו את החיבור ונסו שוב. אפשר לחזור לחדר הקיים בעזרת הקוד שלו.")
        }
    }
    func setup() { leaveCourt(); page = .setup }

    // ---- what the room shows ---------------------------------------------------------------------------------------------------
    private func render() {
        guard let r = link else { return }
        if r.phase == "closed" && !cancelling {
            r.close(); link = nil; preferences.teamRoom = nil
            notice = tr("This room was cancelled", "החדר בוטל")
            setup(); return
        }
        if r.code.isEmpty || r.meta.isEmpty || r.members[r.uid] == nil { return }
        if (r.phase == "playing" || r.phase == "finished") && r.localSeat < 0 { leaveCourt(); page = .bench; return }
        if (r.phase == "playing" || r.phase == "finished"), let game = r.game {
            if court?.engine !== game { gamePage(r, game) }
            // render() runs at 50 Hz during play: publish only real changes, so the view isn't rebuilt every frame.
            if page != .game { page = .game }
            let next: String
            if let outcome = CrossText.teamOutcome(game, local: r.localSeat, hebrew) { next = outcome }
            else if r.phase == "finished" { next = tr("Match complete", "המשחק הסתיים") }
            else if r.waiting { next = tr("Waiting for every player to return", "ממתינים שכל השחקנים יחזרו") }
            else if game.receivingSet { next = tr("Swipe now to smash!", "החליקו עכשיו להנחתה!") }
            else if game.referee.mayServe(r.localSeat) { next = tr("Tap another court to serve", "הקישו על שולחן אחר להגשה") }
            else { next = CrossText.setTip(game, hebrew) ?? tr("Move your paddle to the ball", "הזיזו את המחבט לכדור") }
            if hint != next { hint = next }
            court?.acceptsInput = !r.waiting && r.phase == "playing"
            return
        }
        if r.phase == "lobby" { leaveCourt(); page = .lobby; revision += 1 }
    }
    private func gamePage(_ r: CrossTeamRoom, _ game: CrossEngine) {
        court?.setActive(false)
        let scene = CrossScene(engine: game)
        scene.preferences = preferences
        scene.playCue = { [weak self] cue in self?.audio.play(cue.sound) }
        // The room's own clock runs the match; the court only draws it and takes input.
        scene.step = { _ in }
        scene.names = game.seats.map { r.nameAt($0.index, hebrew: hebrew) }
        scene.fullScreen = actionCamera
        court = scene
        scene.setActive(foreground)
    }
    private func leaveCourt() { court?.setActive(false); court = nil }
    var room: CrossTeamRoom? { link }
    /// The two team columns, the local player's team first.
    var groups: [[MPXLobbyPlayer]] {
        guard let r = link else { return [] }
        var groups = [[0, 2], [1, 3]].map { $0.filter { $0 < r.capacity } }
        if r.localSeat >= 0 && groups[1].contains(r.localSeat) { groups.reverse() }
        return groups.map { group in
            group.map { seat -> MPXLobbyPlayer in
                let user = r.playerAt(seat)
                let token = user.map { "u:" + $0 } ?? (r.occupied(seat) ? "b:" + r.characterAt(seat) : CrossLineup.empty)
                let name = r.occupied(seat) ? r.nameAt(seat, hebrew: hebrew) : (r.host ? tr("Tap to choose", "הקישו לבחירה") : tr("Waiting for the host", "ממתינים לבחירת המארח"))
                return MPXLobbyPlayer(seat: seat, token: token, name: name, character: r.occupied(seat) ? r.characterAt(seat) : nil,
                                      connected: user.map { r.present($0) } ?? true)
            }
        }
    }
    /// Connected friends who could take a place (the picker's first group), excluding the current occupant.
    func people(for seat: Int) -> [(String, CrossTeamIdentity)] {
        guard let r = link else { return [] }
        let current = r.lineup.map { seat < $0.slots.count ? $0.slots[seat] : "" } ?? ""
        return r.members.sorted { $0.value < $1.value }.compactMap { entry in
            guard let identity = r.profiles[entry.key], r.present(entry.key), "u:" + entry.key != current else { return nil }
            return (entry.key, identity)
        }
    }
    func current(_ seat: Int) -> String { link?.lineup.map { seat < $0.slots.count ? $0.slots[seat] : CrossLineup.empty } ?? CrossLineup.empty }
    func choose(_ seat: Int, _ value: String) { picker = nil; link?.chooseSlot(seat, value) }
    func start() { link?.start() }
    func copyCode() {
        guard let value = link?.code else { return }
        UIPasteboard.general.string = value
        notice = tr("Room code copied", "קוד החדר הועתק")
    }
    func invite() {
        guard let value = link?.code else { return }
        shareText = tr("Join my Multiplayer Ping Pong team table! Open the app, choose Online team game, then enter room code: \(value)",
                       "בואו לשולחן הקבוצתי שלי ב־פינג פונג מרובה משתתפים! פתחו את האפליקציה, בחרו משחק קבוצתי ברשת והזינו את הקוד: \(value)")
    }

    // ---- navigation ---------------------------------------------------------------------------------------------------------------
    /// Android navigateBack: no room closes the screen; a lobby is cancelled; a started match asks first (nobody replaces you).
    func back() {
        guard let r = link else { close(); return }
        if r.phase == "lobby" { cancelRoom() } else { confirmLeave = true }
    }
    func cancelRoom() {
        if cancelling { return }
        guard let r = link else { close(); return }
        cancelling = true
        r.cancel { [weak self] ok in
            guard let self else { return }
            self.cancelling = false
            if ok { self.link = nil; self.close() }
            else { self.notice = self.tr("Could not cancel. Check your connection and try again.", "לא ניתן לבטל. בדקו את החיבור ונסו שוב.") }
        }
    }
    func close() { link?.close(); link = nil; leaveCourt(); onClose() }
    func togglePause() { manuallyPaused.toggle(); link?.setActive(foreground && !manuallyPaused) }
    func openHelp() { manuallyPaused = true; link?.setActive(false); help = true }
    func closeHelp() { help = false; manuallyPaused = false; link?.setActive(foreground) }
    func toggleCamera() {
        actionCamera.toggle()
        notice = hebrew ? (actionCamera ? "מצלמת פעולה" : "כל השחקנים במסך") : (actionCamera ? "Action camera" : "Fit all players")
    }
    func lifecycle(active: Bool) {
        foreground = active
        link?.setActive(active && !manuallyPaused)
        court?.setActive(active)
    }
}

/// The online team screens.
@MainActor struct MPXTeamsView: View {
    @ObservedObject var model: CrossTeamsModel
    @State private var hint: String?
    private func tr(_ en: String, _ he: String) -> String { model.tr(en, he) }
    var body: some View {
        ZStack {
            MPXSunsetBackground().ignoresSafeArea()
            if model.page == .game { game } else { page }
            if let text = model.notice ?? hint {
                VStack { Spacer(); Text(text).font(.callout.bold()).foregroundStyle(.white).multilineTextAlignment(.center).padding(12)
                    .background(Color.black.opacity(0.75), in: Capsule()).padding(.bottom, 36) }
                    .allowsHitTesting(false)
                    .task(id: text) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        if model.notice == text { model.notice = nil }
                        if hint == text { hint = nil }
                    }
            }
        }
        .foregroundStyle(MPXMenu.deepInk)
        .alert(tr("Leave the table?", "לצאת מהשולחן?"), isPresented: $model.confirmLeave) {
            Button(tr("Leave", "יציאה"), role: .destructive) { model.close() }
            Button(tr("Keep playing", "ממשיכים לשחק"), role: .cancel) {}
        } message: { Text(tr("The match waits for you. Use the room code to return; a bot will not replace you.", "המשחק ממתין לכם. אפשר לחזור עם קוד החדר; שחקן בית לא יחליף אתכם.")) }
        .alert(CrossText.setTitle(model.hebrew), isPresented: Binding(get: { model.help }, set: { if !$0 { model.closeHelp() } })) {
            Button(tr("Continue", "המשך")) { model.closeHelp() }
        } message: { Text(CrossText.setHelp(model.hebrew)) }
        .sheet(isPresented: Binding(get: { model.shareText != nil }, set: { if !$0 { model.shareText = nil } })) { MPXShareSheet(text: model.shareText ?? "") }
        .sheet(isPresented: Binding(get: { model.picker != nil }, set: { if !$0 { model.picker = nil } })) { picker }
    }
    private var title: String {
        switch model.page {
        case .setup: return tr("Online team game", "משחק קבוצתי ברשת")
        case .connecting: return tr("Connecting…", "מתחברים…")
        case .error: return tr("Let’s find your table", "בואו נמצא את השולחן שלכם")
        case .lobby: return tr("Choose your teams", "בחירת הקבוצות")
        case .bench, .game: return tr("Team match", "משחק קבוצתי")
        }
    }
    private var page: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 58)
                HStack {
                    Button { model.back() } label: {
                        Image(systemName: MPText.rtl ? "arrow.right" : "arrow.left").font(.system(size: 27, weight: .heavy)).frame(width: 48, height: 48)
                    }.foregroundStyle(MPStyle.pink).accessibilityLabel(tr("Back", "חזרה"))
                    Spacer()
                }
            }.frame(minHeight: 60).padding(.horizontal, 8).background(MPStyle.bar, in: RoundedRectangle(cornerRadius: 15)).padding(.horizontal, 8).padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    switch model.page {
                    case .setup: setup
                    case .connecting: text(tr("Finding your table…", "מחפשים את השולחן שלכם…"))
                    case .error:
                        text(model.explanation)
                        button(tr("Back to team rooms", "חזרה לחדרים הקבוצתיים"), accent: true) { model.setup() }
                    case .lobby: lobby
                    case .bench:
                        text(tr("This match has started with the selected players.", "המשחק התחיל עם השחקנים שנבחרו."))
                        button(tr("Back", "חזרה")) { model.close() }
                    case .game: EmptyView()
                    }
                }
                .padding(20).padding(.bottom, 12)
                .background(Color(red: 0xf4 / 255, green: 0xf5 / 255, blue: 0xfc / 255), in: RoundedRectangle(cornerRadius: 24))
                .frame(maxWidth: 650).padding(12).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
    }
    private func text(_ value: String, _ size: CGFloat = 18) -> some View {
        Text(value).font(.system(size: size, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
    }
    private func button(_ title: String, accent: Bool = false, fill: Color? = nil, ink: Color = MPXMenu.deepInk, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 12)
                .background(fill ?? (accent ? MPXMenu.gold : MPXMenu.cyan), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).padding(.top, 20)
    }
    @ViewBuilder private var setup: some View {
        text(tr("Team size", "גודל הקבוצות"))
        Picker(tr("Team size", "גודל הקבוצות"), selection: $model.mode) {
            Text(tr("Two against two", "שניים מול שניים")).tag("FOUR")
            Text(tr("Two against one", "שניים מול אחד")).tag("THREE")
        }.pickerStyle(.segmented)
        button(tr("Create team room", "יצירת חדר קבוצתי"), accent: true) { model.create() }
        MPXDivider()
        TextField(tr("Room code", "קוד החדר"), text: Binding(get: { model.code }, set: { model.code = String($0.uppercased().prefix(6)) }))
            .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.title3.bold()).multilineTextAlignment(.center)
            .foregroundStyle(MPXMenu.deepInk).padding(12).frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.75)))
            .environment(\.layoutDirection, .leftToRight).padding(.bottom, 12)
        button(tr("Join team room", "הצטרפות לחדר קבוצתי")) { model.join() }
        button(tr("Cancel", "ביטול"), fill: MPXMenu.pink, ink: .white) { model.cancelRoom() }.padding(.top, 12).padding(.bottom, 16)
    }
    @ViewBuilder private var lobby: some View {
        if let r = model.room {
            let _ = model.revision
            text(tr("Room code: ", "קוד החדר: ") + r.code, 22)
            HStack(spacing: 12) {
                button(tr("Copy code", "העתקת הקוד"), accent: true) { model.copyCode() }
                button(tr("Invite a friend", "הזמנת חבר")) { model.invite() }
            }.padding(.bottom, 8)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(model.groups.enumerated()), id: \.offset) { item in
                    teamColumn(item.offset, item.element, editable: r.host && r.flexible)
                }
            }.padding(.top, 24).padding(.bottom, 12)
            if !r.flexible { text(tr("This older room keeps its original places. Create a new room to arrange the teams.", "בחדר הישן הזה המקומות קבועים. צרו חדר חדש כדי לסדר את הקבוצות."), 15) }
            if r.host && r.localSeat < 0 { text(tr("Choose yourself for a place before starting.", "בחרו לעצמכם מקום לפני תחילת המשחק."), 16) }
            if r.host {
                button(tr("Start match", "מתחילים במשחק"), accent: true) { model.start() }
                    .disabled(!r.canStart).opacity(r.canStart ? 1 : 0.42)
                    .accessibilityLabel(r.canStart ? tr("Start match", "מתחילים במשחק") : tr("Choose every player and wait for selected friends to connect", "בחרו שחקן לכל מקום והמתינו לחיבור החברים שבחרתם"))
            }
            button(tr("Cancel", "ביטול"), fill: MPXMenu.pink, ink: .white) { model.cancelRoom() }
        }
    }
    /// Android TeamLobbyCards.board: two clear team columns with whole-body portraits and real people's nicknames.
    private func teamColumn(_ index: Int, _ players: [MPXLobbyPlayer], editable: Bool) -> some View {
        VStack(spacing: 12) {
            ForEach(players) { player in
                Button { if editable { model.picker = player.seat } } label: {
                    VStack(spacing: 4) {
                        if let character = player.character { MPXPortrait(character: character).frame(height: 112) }
                        else { emptyPlayer.frame(height: 112) }
                        Text(player.name).font(.system(size: 16, weight: .bold)).foregroundStyle(MPXMenu.deepInk).multilineTextAlignment(.center)
                        if !player.connected { Text(tr("Reconnecting…", "מתחבר מחדש…")).font(.system(size: 13, weight: .bold)).foregroundStyle(MPXMenu.deepInk) }
                    }.padding(6).frame(maxWidth: .infinity).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(!editable)
                    .accessibilityLabel(player.name + (editable ? tr(". Tap to change player", ". הקישו להחלפת שחקן") : ""))
            }
            Text(index == 0 ? tr("Your team", "הקבוצה שלכם") : tr("Other team", "הקבוצה היריבה")).font(.system(size: 18, weight: .bold)).multilineTextAlignment(.center)
            Text(editable ? tr("Tap a player to change", "הקישו על שחקן כדי להחליף") : tr("The host arranges the teams", "המארח מסדר את הקבוצות"))
                .font(.system(size: 14, weight: .bold)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6).padding(.vertical, 8).frame(maxWidth: .infinity)
        .background(index == 0 ? Color(red: 0xfc / 255, green: 0xe5 / 255, blue: 0xf1 / 255) : Color(red: 0xe3 / 255, green: 0xef / 255, blue: 1), in: RoundedRectangle(cornerRadius: 18))
    }
    private var emptyPlayer: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width / 3, geo.size.height / 3), x = geo.size.width / 2
            ZStack {
                Circle().fill(Color(red: 0x60 / 255, green: 0x77 / 255, blue: 0x85 / 255).opacity(135 / 255)).frame(width: unit * 0.84, height: unit * 0.84)
                    .position(x: x, y: geo.size.height * 0.28)
                RoundedRectangle(cornerRadius: unit * 0.25).fill(Color(red: 0x60 / 255, green: 0x77 / 255, blue: 0x85 / 255).opacity(135 / 255))
                    .frame(width: unit * 1.4, height: geo.size.height * 0.46).position(x: x, y: geo.size.height * 0.70)
                Text("?").font(.system(size: unit * 0.75, weight: .bold)).foregroundStyle(.white).position(x: x, y: geo.size.height * 0.70)
            }
        }.accessibilityHidden(true)
    }
    /// Android TeamLobbyCards.picker: connected friends, then the house players, then "Leave this place empty".
    private var picker: some View {
        let seat = model.picker ?? 0
        let current = model.current(seat)
        return NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    let people = model.people(for: seat)
                    if !people.isEmpty { Text(tr("Connected friends", "חברים מחוברים")).font(.system(size: 19, weight: .bold)) }
                    ForEach(Array(people.enumerated()), id: \.offset) { item in
                        Button { model.choose(seat, "u:" + item.element.0) } label: {
                            HStack { MPXPortrait(character: item.element.1.character).frame(width: 66, height: 76); Text(item.element.1.name).font(.system(size: 17, weight: .bold)).foregroundStyle(MPXMenu.deepInk); Spacer() }
                                .padding(6).background(Color(red: 0xe4 / 255, green: 0xf0 / 255, blue: 1), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    Text(tr("House players", "שחקני הבית")).font(.system(size: 19, weight: .bold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 12) {
                        ForEach(MPRoster.all.filter { "b:" + $0.id != current }) { bot in
                            Button { model.choose(seat, "b:" + bot.id) } label: {
                                VStack { MPXPortrait(character: bot.id).frame(height: 96); Text(bot.name(hebrew: model.hebrew)).font(.system(size: 14, weight: .bold)).foregroundStyle(MPXMenu.deepInk) }
                                    .padding(6).frame(maxWidth: .infinity).background(Color(red: 0xe5 / 255, green: 0xf7 / 255, blue: 0xf1 / 255), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                    if current != CrossLineup.empty {
                        Button { model.choose(seat, CrossLineup.empty) } label: {
                            Text(tr("Leave this place empty", "השארת המקום פנוי")).font(.system(size: 17, weight: .bold)).foregroundStyle(MPXMenu.deepInk).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.plain)
                    }
                }.padding(16).foregroundStyle(MPXMenu.deepInk)
            }
            .background(Color.white)
            .navigationTitle(tr("Choose a player", "בחירת שחקן")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel", "ביטול")) { model.picker = nil } } }
        }
        .environment(\.layoutDirection, model.hebrew ? .rightToLeft : .leftToRight)
    }
    private var game: some View {
        MPXMatchLayout(tools: 4) {
            MPXTool(symbol: MPText.rtl ? "arrow.right" : "arrow.left", label: tr("Back", "חזרה"), fill: MPXMenu.cyan, tint: MPXMenu.deepInk) { model.back() }
            MPXTool(symbol: "playpause.fill", label: tr("Pause / Continue", "השהיה / המשך"), fill: MPXMenu.cyan, tint: MPXMenu.deepInk) { model.togglePause() }
            MPXTool(symbol: "camera.viewfinder", label: tr("Switch camera view", "החלפת תצוגת מצלמה"), fill: MPXMenu.cyan, tint: MPXMenu.deepInk) { model.toggleCamera() }
            MPXTool(symbol: "questionmark", label: tr("Help", "עזרה"), fill: MPXMenu.cyan, tint: MPXMenu.deepInk) { model.openHelp() }
        } status: { wide in
            VStack(spacing: 2) {
                Text(tr("Team match", "משחק קבוצתי")).font(.system(size: 20, weight: .bold)).environment(\.layoutDirection, .leftToRight)
                Text(model.hint).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.center).lineLimit(wide ? 12 : 4)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 6)
            .background(MPXMenu.hud, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 4)
        } court: {
            if let court = model.court {
                MPXCourt(scene: court, label: tr("Team match", "משחק קבוצתי"))
                    .background(GeometryReader { geo in Color.clear.task(id: ObjectIdentifier(court)) {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        if geo.size.height > geo.size.width { hint = FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי.") }
                    } })
            }
        }
    }
}
