import SwiftUI
import SpriteKit

/// Multi Ping Pong entry point (Android MinikCrossPong 5c1aa4d PlayActivity home, forms and rooms; CrossActivity; the classic and
/// cross match screens; the journey and team screens in MPXJourney.swift / MPXTeams.swift). Ads and purchases are off in this app, so it shows no ad, purchase, restore or code UI. The Simple
/// experience (a host's embedded classic game) keeps its single-player screen. Hosts dismiss their presentation in onClose; a
/// completed Simple match calls it once.
@MainActor struct ModernPongView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject var model: MPController
    /// The host's commerce controller is accepted for source compatibility; Multi Ping Pong sells nothing.
    private let commerce: MinikCommerceController?
    @State var expanded: Set<String> = []
    /// Android home: the profile, friendly and tournament forms open one at a time.
    @State var section: String?
    @State var joinCodes: [String: String] = [:]
    @State var nicknameIndex = 0
    @State var avatarIndex = 0
    @State var avatarCharacter = "miniko"
    @State var profileSaved = false
    @State var friendlyTable = 4
    @State var tournamentTable = 4
    @State var friendlyMode = MPGameMode.winnerTakesAll
    /// Android 5c1aa4d: the friendly form's third game type, "Team play".
    @State var friendlyTeam = false
    /// Android PlayActivity.tournamentOptions: the separate "Create tournament" page.
    @State var creatingTournament = false
    @State var tournamentMode = MPGameMode.winnerTakesAll
    @State var tournamentFormat = MPTournamentFormat.knockout
    @State var capacity = 4
    @State var legs = 1
    @State var winPoints = 3
    @State var knockoutCapacity = 8
    @State var advance = 2
    @State var formTarget = 7
    @State var formsLoaded = false
    @State var carouselDirection = 1
    @State var pickerIndex = 0
    @State var editingHouse = false
    @State var confirmLeave = false
    @State var showHelp = false
    @State var copied = false
    @State var showGameSettings = false
    @State var showCrossSettings = false
    @State var crossSettingsWasPaused = false
    @State var settingsPlayers = 4
    @State var settingsTarget = 5
    @State var settingsControl = MPLevel.beginner
    @State var settingsOpponents: [String] = []
    let gap: CGFloat = 12
    init(experience: ModernPongExperience = .full, commerce: MinikCommerceController? = nil, onClose: @escaping (ModernPongResult?) -> Void = { _ in }) {
        // Android LocalizedActivity: the primary device language, not the host's locale (the shared RootView offers this app only
        // English and Hebrew).
        MPText.configureFromDevice()
        _model = StateObject(wrappedValue: MPController(experience: experience, onClose: onClose))
        self.commerce = commerce
    }
    /// Android `hebrew` (`AppText.language == "he"`): Hebrew texts and names. Layout follows `MPText.rtl` (Hebrew and Arabic).
    var he: Bool { MPText.language == "he" }
    /// Android `tr(en, he)` = `AppText.t(en, he, hebrew)`: Hebrew, or the app language's catalog text, or English.
    func t(_ en: String, _ he: String) -> String { MPText.t(en, he, self.he) }
    func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: MPText.rtl ? "arrow.right" : "arrow.left")
                .font(.system(size: 27, weight: .heavy)).frame(width: 48, height: 48)
        }.foregroundStyle(MPStyle.pink).accessibilityLabel(t("Back", "חזרה"))
    }
    /// Android 5c1aa4d: the cross table's screens and the journey/team screens bring their own bars (MatchSceneLayout).
    private var ownBar: Bool {
        switch model.route {
        case .cross, .journey, .teams: return true
        // Android 1dbfe33: a room match's result shows over its own match screen.
        case .game, .result: return model.crossScene != nil
        default: return false
        }
    }
    var body: some View {
        ZStack {
            if model.experience == .simple { MPIllustratedBackground().ignoresSafeArea() }
            // Android SunsetTerrace: the integrated menu painting on the home, the evening terrace elsewhere.
            else { MPXSunsetBackground(menu: model.route == .menu && !creatingTournament).ignoresSafeArea() }
            VStack(spacing: 0) {
                if !ownBar { header }
                // Android 1dbfe33: a room match's result card shows over its court, which stays the same view.
                if model.route == .game || roomResult != nil { game }
                else {
                    switch model.route {
                    case .menu: if creatingTournament { tournamentOptions } else { menu }
                    case .lobby: lobby
                    case .guide: guide
                    case .game, .result: result
                    case .cross: crossGame
                    case .journey: if let journey = model.journey { MPXJourneyView(model: journey) }
                    case .teams: if let teams = model.teams { MPXTeamsView(model: teams) }
                    }
                }
            }
            if let room = roomResult { roomResultCard(room.0, room.1) }
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).font(.callout.bold()).foregroundStyle(.white).multilineTextAlignment(.center).padding(12)
                    .background(Color.black.opacity(0.75), in: Capsule()).padding(.bottom, 36) }
                    .allowsHitTesting(false)
                    .task(id: toast) { try? await Task.sleep(nanoseconds: 2_200_000_000); if model.toast == toast { model.toast = nil } }
            }
        }
        .overlay {
            // Android VictoryConfetti: brief and noninteractive; a new celebration restarts it.
            if let celebration = model.celebration { MPVictoryConfetti().id(celebration) }
        }
        .confirmationDialog(t("Save this tournament?", "לשמור את הטורניר?"), isPresented: $model.tournamentExitPrompt, titleVisibility: .visible) {
            Button(t("Save", "שמירה")) { model.keepTournament() }
            Button(t("Don't save", "לא לשמור"), role: .destructive) { model.discardTournament() }
            Button(t("Cancel", "ביטול"), role: .cancel) {}
        } message: { Text(tournamentExitMessage) }
        .foregroundStyle(MPStyle.ink).preferredColorScheme(.light)
        .task {
            await model.start(hebrew: he, removeAds: false)
            if model.experience == .full { model.applyStoreScreenshotScene() }
        }
        .onChange(of: phase) { _, value in model.lifecycle(active: value == .active) }
        .onDisappear { model.close() }
        .alert(model.errorTitle ?? t("Please try again", "נסו שוב"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil; model.errorTitle = nil } })) {
            Button(t("OK", "אישור")) { model.error = nil; model.errorTitle = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showHelp) { help }
        .sheet(isPresented: $showGameSettings, onDismiss: { if model.paused { model.togglePause() } }) { gameSettings }
        .sheet(isPresented: $showCrossSettings, onDismiss: { model.crossSettingsCancelled(wasPaused: crossSettingsWasPaused); crossSettingsWasPaused = true }) { crossSettings }
        // Last, so the alert and the sheets read right to left too (Android LocalizedActivity / GuideDialog: `AppText.rtl`).
        .environment(\.layoutDirection, MPText.rtl ? .rightToLeft : .leftToRight)
    }
    private var tournamentExitMessage: String {
        guard let s = model.session else { return "" }
        return MPRules.canDelete(s, actor: model.userID)
            ? t("Save to continue later. Don't save deletes this tournament and its matches.", "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, הטורניר והמשחקים שלו יימחקו.")
            : t("Save to continue later. Don't save leaves the tournament; other players can continue.", "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, תעזבו את הטורניר והשחקנים האחרים יוכלו להמשיך.")
    }
    private var caption: String {
        switch model.route {
        case .menu:
            if model.experience == .simple { return "MINIK Ping Pong" }
            // Android R.string.app_name (5c1aa4d: "Multiplayer Ping Pong").
            return creatingTournament ? t("Create tournament", "יצירת טורניר") : t("Multiplayer Ping Pong", "פינג פונג מרובה משתתפים")
        case .lobby: return model.session?.kind == .tournament ? t("Tournament", "טורניר") : t("Friendly game", "משחק ידידות")
        case .game: return model.session?.kind == .tournament ? t("Tournament match", "משחק בטורניר") : t("Ping Pong", "פינג פונג")
        case .guide: return t("Learn with Minik", "לומדים עם מיניק")
        case .result:
            if model.session != nil { return model.session?.kind == .tournament ? t("Tournament match", "משחק בטורניר") : t("Ping Pong", "פינג פונג") }
            return t("Match result", "תוצאת המשחק")
        case .cross, .journey, .teams: return ""
        }
    }
    private var header: some View {
        // Android PlayActivity.page(mainMenu) (18cd99d, a247226): the home title sits on the painted sky, without a bar, on one
        // line above the illustrated players (24 pt, shrinking to 16 pt on narrow screens), with a navy edge so the sunrise
        // cannot wash it out.
        let home = model.route == .menu && model.experience != .simple && !creatingTournament
        return ZStack {
            Text(caption).font(.system(size: 24, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                .lineLimit(home ? 1 : nil).minimumScaleFactor(home ? 16 / 24 : 1)
                .shadow(color: home ? Color(red: 20 / 255, green: 45 / 255, blue: 92 / 255) : .clear, radius: 2)
                .padding(.horizontal, 58)
            HStack {
                if creatingTournament && model.route == .menu {
                    backButton { creatingTournament = false; section = "tournament" }
                } else if model.route != .menu || model.experience == .simple {
                    backButton { model.back() }
                }
                Spacer()
                if model.route == .menu && model.experience == .simple {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel(t("Help", "עזרה"))
                } else if model.route == .game && model.session == nil {
                    Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.title2).frame(width: 48, height: 48) }
                        .accessibilityLabel(model.paused ? t("Resume", "המשך") : t("Pause", "השהיה"))
                }
            }
        }.frame(minHeight: 60).padding(.horizontal, 8)
        // Android ModernActivity's screen bar: white text on a dark rounded bar, readable over the artwork.
        .foregroundStyle(.white)
        .background(home ? Color.clear : MPStyle.bar, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 8).padding(.top, 4)
    }

    func toggle(_ key: String) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }
    func action(_ title: String, color: Color = MPStyle.blue, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(.headline, design: .rounded, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 8) }
            .buttonStyle(.plain).background(color, in: RoundedRectangle(cornerRadius: 18)).disabled(model.busy)
    }
    func card<Content: View>(_ color: Color = Color.white.opacity(0.82), @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: gap, content: content).padding(16).frame(maxWidth: .infinity).background(color, in: RoundedRectangle(cornerRadius: 18))
    }

    // ---- home -------------------------------------------------------------------------------------------------------------
    private var menu: some View {
        ScrollView {
            VStack(spacing: gap) {
                if model.experience == .simple {
                    Image("mp_app_icon").resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 220).accessibilityHidden(true).padding(.bottom, 16)
                    action(t("Learn how to play with Minik", "למדו לשחק עם מיניק"), color: MPStyle.mint) { model.guide() }
                    controls
                    carousel
                    action(t("Start", "מתחילים"), color: MPStyle.blue) { model.startSingle() }
                } else {
                    Color.clear.frame(height: heroSpace).padding(.bottom, 24).accessibilityHidden(true)
                    // Android 5c1aa4d PlayActivity.home: four FamilyMenu sections.
                    MPXSection(title: t("Start & learn", "מתחילים ולומדים"), color: MPXMenu.learn, preferences: model.preferences, defaultOpen: true) {
                        action(t("Learn how to play with Minik", "לומדים לשחק עם מיניק"), color: MPXMenu.learn) { model.openCross(learn: true) }
                        action(t("Daily skill journey", "אתגר יומי"), color: MPXMenu.learn) { model.openJourney(.brief) }
                        action(t("Nickname & avatar", "כינוי ודמות") + " · " + profileName, color: MPXMenu.learn) {
                            if section != "profile" {
                                avatarIndex = model.identity?.avatar ?? 0; avatarCharacter = model.identity?.characterId ?? "miniko"; profileSaved = false
                            }
                            section = section == "profile" ? nil : "profile"
                        }.accessibilityLabel(t("Choose your nickname and avatar", "בחירת כינוי ודמות"))
                        if section == "profile" { profileEditor }
                    }
                    MPXSection(title: t("Play", "משחקים"), color: MPXMenu.play, preferences: model.preferences, defaultOpen: true) {
                        expandHeader(t("New friendly game", "משחק ידידות חדש"), open: section == "friendly", fill: MPXMenu.play) { section = section == "friendly" ? nil : "friendly" }
                        if section == "friendly" { createForm(.friendly) }
                        expandHeader(t("New tournament", "טורניר חדש"), open: section == "tournament", fill: MPXMenu.play) { section = section == "tournament" ? nil : "tournament" }
                        if section == "tournament" { tournamentEntry }
                    }
                    MPXSection(title: t("Saved games", "משחקים שמורים"), color: MPXMenu.saved, preferences: model.preferences, defaultOpen: false) {
                        roomSection(.friendly)
                        roomSection(.tournament)
                    }
                    MPXSection(title: t("Advanced", "מתקדם"), color: MPXMenu.advanced, preferences: model.preferences, defaultOpen: false) {
                        action(t("Settings · Feedback & sharing", "הגדרות · משוב ושיתוף"), color: MPXMenu.advanced) { model.openJourney(.settings) }
                        // Android PlayActivity (Advanced): "More Minik apps & games" as a link, behind the family grown-up gate.
                        MPXLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { FamilyMessages.shared.showMoreApps(gate: nil) }
                    }
                    if model.online {
                        if model.connecting { ProgressView(t("Connecting…", "מתחברים…")) }
                        else if !model.connected { Button(t("Retry online connection", "נסו להתחבר שוב")) { Task { await model.retryOnline(removeAds: false) } }.font(.headline).padding(12) }
                    }
                }
                if model.busy { ProgressView().accessibilityLabel(t("Loading", "טוען")) }
            }.frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadForms() }
    }
    private func loadForms() {
        guard !formsLoaded else { return }
        formsLoaded = true
        let prefs = model.preferences
        friendlyTable = prefs.tableSize(.friendly); tournamentTable = prefs.tableSize(.tournament)
        friendlyMode = prefs.gameMode(.friendly); tournamentMode = prefs.gameMode(.tournament)
        friendlyTeam = prefs.defaults.bool(forKey: "modern.pong.v2.friendlyTeamPlay")
        tournamentFormat = prefs.knockoutFormat ? .knockout : .roundRobin
        advance = prefs.advance; knockoutCapacity = prefs.knockoutPlayers
        // Android PlayActivity: "Points to win" always opens at 7.
        formTarget = 7
    }
    /// Android PlayActivity.home: the space the integrated menu painting keeps for its hero (27 % of the height, 168–216 pt).
    private var heroSpace: CGFloat { min(216, max(168, UIScreen.main.bounds.height * 0.27)) }
    private var profileName: String { model.identity?.name ?? MPNames.candidate(0, hebrew: he, character: model.identity?.characterId ?? "miniko") }
    func expandHeader(_ title: String, open: Bool, blue: Bool = false, fill: Color? = nil, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if !blue { Text(open ? "−" : "+").font(.system(size: 34, weight: .heavy)).frame(width: 44, height: 48) }
            }.padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.plain).background(fill ?? (blue ? MPStyle.blue : MPStyle.lilac), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityValue(open ? t("Expanded", "מורחב") : t("Collapsed", "מצומצם"))
    }
    var controls: some View {
        VStack(spacing: 14) {
            Text(t("Control difficulty", "רמת השליטה")).font(.headline)
            Picker(t("Control difficulty", "רמת השליטה"), selection: $model.level) {
                Text(t("Beginner", "מתחילים")).tag(MPLevel.beginner)
                Text(t("Standard", "רגילה")).tag(MPLevel.easy)
                Text(t("Pro", "מקצועני")).tag(MPLevel.superHard)
            }.pickerStyle(.segmented).onChange(of: model.level) { _, _ in model.saveControls() }
            Text(controlHint).font(.callout).multilineTextAlignment(.center)
            if model.experience == .simple {
                HStack { Text(t("Points to win", "נקודות לניצחון")).font(.headline); Spacer(); Picker(t("Points", "נקודות"), selection: $model.target) { ForEach(model.level.targets, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu).font(.title3.bold()) }
            }
        }
    }
    private var controlHint: String {
        if model.experience == .simple {
            // Android PlayActivity control description (2026-10), one sentence per selected level.
            if model.level.automaticContact { return t("Beginner: move into place for an automatic hit; a small sideways swipe aims it. Opponent skill comes from your chosen house player.", "מתחילים: מזיזים את המחבט למקום לחבטה אוטומטית; החלקה קטנה הצידה מכוונת אותה. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.") }
            return model.level.pro ? t("Pro: precise timing and power. Opponent skill comes from your chosen house player.", "מקצועני: תזמון ועוצמה מדויקים. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.") : t("Standard: tap or swipe; faster swipes add power. Opponent skill comes from your chosen house player.", "רגילה: מקישים או מחליקים; החלקה מהירה מוסיפה עוצמה. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.")
        }
        // Android 828c6fc createForm: one description of all three levels.
        return t("Beginner: move into place for an automatic hit; swipe a little left or right before the ball arrives to choose who gets it (the 🎯 shows who). Standard: tap or swipe; faster swipes add power. Pro: precise timing and power. Opponent skill comes from your chosen house player.",
                 "מתחילים: מזיזים את המחבט למקום לחבטה אוטומטית; החלקה קטנה שמאלה או ימינה לפני שהכדור מגיע בוחרת למי (ה־🎯 מראה למי). רגילה: מקישים או מחליקים; החלקה מהירה מוסיפה עוצמה. מקצועני: תזמון ועוצמה מדויקים. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.")
    }
    /// Classic Simple carousel over every house player.
    var carousel: some View {
        VStack(spacing: 16) {
            Text(t("Opponent", "יריב")).font(.headline)
            HStack {
                Button { cycle(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.system(size: 34)).frame(width: 48, height: 60) }.accessibilityLabel(t("Previous player", "השחקן הקודם"))
                VStack(spacing: 14) {
                    MPAvatar(character: model.selectedPlayer.id, icon: 0).frame(height: 150)
                    Text(model.selectedPlayer.name(hebrew: he)).font(.title2.bold()).padding(.vertical, 6)
                }.frame(maxWidth: .infinity).id(model.selectedPlayer.id)
                    .transition(.asymmetric(insertion: .move(edge: carouselDirection > 0 ? .trailing : .leading).combined(with: .opacity), removal: .move(edge: carouselDirection > 0 ? .leading : .trailing).combined(with: .opacity)))
                    .gesture(DragGesture(minimumDistance: 30).onEnded { if abs($0.translation.width) > abs($0.translation.height) { cycle($0.translation.width < 0 ? 1 : -1) } })
                Button { cycle(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.system(size: 34)).frame(width: 48, height: 60) }.accessibilityLabel(t("Next player", "השחקן הבא"))
            }.clipped().environment(\.layoutDirection, .leftToRight)
            Text(statsLine(model.selectedPlayer.profile)).font(.caption).multilineTextAlignment(.center)
        }
    }
    /// Android HousePlayerPicker stats. The English text follows the catalog key ("Power {0}  ·  Forehand {1}…"), so the four
    /// other languages show Android's catalog translation.
    func statsLine(_ p: MPBot) -> String {
        t("Power \(p.power)  ·  Forehand \(p.forehandSkill)  ·  Backhand \(p.backhandSkill)  ·  Serve \(p.serveSkill)",
          "עוצמה \(p.power) · כף יד \(p.forehandSkill) · גב יד \(p.backhandSkill) · הגשה \(p.serveSkill)")
    }
    private func cycle(_ offset: Int) { carouselDirection = offset; withAnimation(.easeInOut(duration: 0.22)) { model.playerIndex = (model.playerIndex + offset + MPRoster.all.count) % MPRoster.all.count } }
    /// Android HousePlayerPicker: large arrows, swipes and the selected character, skipping `excluded` characters.
    func housePicker(excluded: Set<String>) -> some View {
        let choices = MPRoster.all.filter { !excluded.contains($0.id) }
        let list = choices.isEmpty ? MPRoster.all : choices
        let player = list[((pickerIndex % list.count) + list.count) % list.count]
        return VStack(spacing: 10) {
            HStack {
                Button { carouselDirection = -1; withAnimation(.easeInOut(duration: 0.22)) { pickerIndex -= 1 } } label: { Image(systemName: "chevron.left.circle.fill").font(.system(size: 34)).frame(width: 54, height: 64) }
                    .foregroundStyle(MPStyle.pink).accessibilityLabel(t("Previous player", "השחקן הקודם"))
                MPAvatar(character: player.id, icon: 0).frame(height: 130).frame(maxWidth: .infinity).id(player.id)
                    .transition(.opacity)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) { withAnimation(.easeInOut(duration: 0.22)) { pickerIndex += value.translation.width < 0 ? 1 : -1 } }
                    })
                Button { carouselDirection = 1; withAnimation(.easeInOut(duration: 0.22)) { pickerIndex += 1 } } label: { Image(systemName: "chevron.right.circle.fill").font(.system(size: 34)).frame(width: 54, height: 64) }
                    .foregroundStyle(MPStyle.pink).accessibilityLabel(t("Next player", "השחקן הבא"))
            }.environment(\.layoutDirection, .leftToRight)
            Text(player.name(hebrew: he)).font(.title2.bold())
            Text(statsLine(player.profile)).font(.caption).multilineTextAlignment(.center)
        }
    }
    func pickedPlayer(excluded: Set<String>) -> MPHousePlayer {
        let choices = MPRoster.all.filter { !excluded.contains($0.id) }
        let list = choices.isEmpty ? MPRoster.all : choices
        return list[((pickerIndex % list.count) + list.count) % list.count]
    }
    private var profileEditor: some View {
        card {
            Text(t("Choose a nickname", "בחרו כינוי")).font(.title3.bold())
            Text(MPNames.candidate(nicknameIndex, hebrew: he, character: avatarCharacter)).font(.title2.bold()).frame(minHeight: 48).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                let count = MPRoster.find(avatarCharacter) == nil ? 100 : 10
                Button { nicknameIndex = (nicknameIndex + count - 1) % count } label: { Text("‹").font(.system(size: 30, weight: .bold)).frame(maxWidth: .infinity, minHeight: 52) }
                    .foregroundStyle(MPStyle.pink).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel(t("Previous nickname", "הכינוי הקודם"))
                Button { nicknameIndex = (nicknameIndex + 1) % count } label: { Text("›").font(.system(size: 30, weight: .bold)).frame(maxWidth: .infinity, minHeight: 52) }
                    .foregroundStyle(MPStyle.pink).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel(t("Next nickname", "הכינוי הבא"))
            }.environment(\.layoutDirection, .leftToRight)
            Text(t("Choose a playful name. Character names match your avatar. A number is added only if the name is already taken.", "בחרו כינוי חמוד. שם הדמות הוא חלק מהכינוי. מספר יתווסף רק אם הכינוי כבר תפוס.")).font(.footnote).multilineTextAlignment(.center)
            Text(t("Choose your avatar", "בחרו את הדמות שלכם")).font(.title3.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(MPRoster.all) { player in
                    Button { avatarCharacter = player.id; profileSaved = false } label: {
                        VStack { MPAvatar(character: player.id, icon: 0).frame(height: 64); Text(player.name(hebrew: he)).font(.caption).lineLimit(1) }
                            .padding(4).background(avatarCharacter == player.id ? MPStyle.mint : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            Text(t("Or choose an icon", "או בחרו סמל")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(0..<MPNames.icons.count, id: \.self) { index in
                    Button { avatarCharacter = ""; avatarIndex = index; profileSaved = false } label: {
                        Text(MPNames.icons[index]).font(.system(size: 32)).frame(maxWidth: .infinity, minHeight: 64)
                            .background(avatarCharacter.isEmpty && avatarIndex == index ? MPStyle.mint : .white, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityLabel(avatarName(index))
                }
            }
            action(t("Save nickname & avatar", "שמירת הכינוי והדמות"), color: MPStyle.mint) {
                Task {
                    await model.profile(index: nicknameIndex, avatar: avatarIndex, character: avatarCharacter)
                    if model.error == nil { profileSaved = true }
                }
            }.disabled(!model.connected)
            if profileSaved { Text(t("Nickname and avatar saved", "הכינוי והדמות נשמרו")).font(.callout.bold()) }
        }
    }
    /// Android PlayActivity.avatarNames: the spoken names of the six icons (`MPNames.icons` order).
    func avatarName(_ index: Int) -> String {
        let englishNames = ["Cat", "Fox", "Panda", "Frog", "Tiger", "Penguin"]
        let hebrewNames = ["חתול", "שועל", "פנדה", "צפרדע", "טיגריס", "פינגווין"]
        let i = min(max(index, 0), englishNames.count - 1)
        return he ? hebrewNames[i] : MPText.t(englishNames[i])
    }
    /// Android 5c1aa4d: a tournament is created on its own page; the home offers "Create room" and joining by code.
    private var tournamentEntry: some View {
        card {
            action(t("Create room", "יצירת חדר"), color: MPStyle.blue) { creatingTournament = true }
            MPXDivider()
            Text(t("Room code", "קוד חדר")).font(.headline)
            TextField(t("6-character code", "קוד בן 6 תווים"), text: joinBinding(.tournament)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.title3.bold()).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight)
            action(t("Join room", "הצטרפות לחדר"), color: MPStyle.blue) { Task { await model.join(.tournament, joinCodes[MPSessionKind.tournament.rawValue] ?? "") } }
        }
    }
    /// Android PlayActivity.tournamentOptions: the tournament settings, "Create room" and Cancel.
    private var tournamentOptions: some View {
        ScrollView {
            VStack(spacing: gap) {
                createForm(.tournament, settingsOnly: true)
                action(t("Cancel", "ביטול"), color: MPStyle.pink) { creatingTournament = false; section = "tournament" }.foregroundStyle(.white)
            }.frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }
    /// Android PlayActivity.createForm (5c1aa4d).
    @ViewBuilder private func createForm(_ kind: MPSessionKind, settingsOnly: Bool = false) -> some View {
        let tournament = kind == .tournament
        let table = tournament ? tournamentTable : friendlyTable
        let team = !tournament && friendlyTeam && table > 2
        card {
            Text(tournament ? t("Invite friends with the code and add house players to the same tournament.", "הזמינו חברים באמצעות הקוד והוסיפו שחקני בית לאותו טורניר.")
                 : t("Create a game, then share its code with a friend or choose a house player.", "צרו משחק, ואז שתפו את הקוד עם חבר או בחרו שחקן בית."))
                .multilineTextAlignment(.center)
            Text(tournament ? t("Players per table", "שחקנים בכל שולחן") : t("Players at the table", "שחקנים סביב השולחן")).font(.headline)
            Picker(tournament ? t("Players per table", "שחקנים בכל שולחן") : t("Players at the table", "שחקנים סביב השולחן"), selection: tableBinding(kind)) {
                if tournament {
                    Text(t("Pairs (classic table)", "זוגות (שולחן קלאסי)")).tag(2)
                    Text(t("Tables of 3 (Y table)", "שולחנות של 3 (Y)")).tag(3)
                    Text(t("Tables of 4 (cross table)", "שולחנות של 4")).tag(4)
                } else {
                    Text(t("2 players · classic table", "2 שחקנים · שולחן קלאסי")).tag(2)
                    Text(t("3 players · Y table", "3 שחקנים · שולחן Y")).tag(3)
                    Text(t("4 players · cross table", "4 שחקנים · שולחן משותף")).tag(4)
                }
            }.pickerStyle(.menu).font(.headline)
            if table > 2 {
                // Game type: tables of 3 or 4 only (a pair always plays the classic game); a friendly game may also be team play.
                Text(t("Game type", "סוג המשחק")).font(.headline)
                if tournament {
                    Picker(t("Game type", "סוג המשחק"), selection: modeBinding(kind)) {
                        ForEach(MPGameMode.allCases, id: \.self) { Text($0.title(he)).tag($0) }
                    }.pickerStyle(.segmented)
                } else {
                    Picker(t("Game type", "סוג המשחק"), selection: friendlyTypeBinding) {
                        ForEach(Array(MPGameMode.allCases.enumerated()), id: \.offset) { Text($0.element.title(he)).tag($0.offset) }
                        Text(t("Team play", "משחק קבוצתי")).tag(MPGameMode.allCases.count)
                    }.pickerStyle(.segmented)
                }
                Text(team ? t("Teammates share a score. There is no individual elimination.", "לחברי הקבוצה יש ניקוד משותף. אין הדחה אישית.")
                     : (tournament ? tournamentMode : friendlyMode).explanation(he)).font(.footnote).multilineTextAlignment(.center)
            }
            if team {
                Text(t("Two against one or two against two. Choose the players and your teammate on the next screen.", "שניים מול אחד או שניים מול שניים. במסך הבא בוחרים שחקנים וחבר קבוצה."))
                    .multilineTextAlignment(.center)
                action(t("Play with house players", "משחק עם שחקני בית"), color: MPStyle.mint) { model.openJourney(.teams, players: table) }
                action(t("Create or join an online team game", "יצירה או הצטרפות למשחק קבוצתי ברשת"), color: MPStyle.mint) { model.openTeams(players: table) }
            } else {
                ordinaryForm(kind, table: table, settingsOnly: settingsOnly)
            }
        }
    }
    /// The form below the game type: everything except team play's two entries.
    @ViewBuilder private func ordinaryForm(_ kind: MPSessionKind, table: Int, settingsOnly: Bool) -> some View {
        let tournament = kind == .tournament
        Group {
            if tournament { tournamentChoices(table) }
            controls
            Text(t("Points to win", "נקודות לניצחון")).font(.headline)
            Picker(t("Points to win", "נקודות לניצחון"), selection: $formTarget) { ForEach([3, 5, 7], id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.segmented)
            if tournament { Text(t("Choose your house players on the next screen.", "במסך הבא בחרו את שחקני הבית.")).multilineTextAlignment(.center) }
            if !model.online {
                Text(t("Online rooms are not set up in this version yet, so this game is created on this phone with house players.", "חדרים מקוונים עדיין לא זמינים בגרסה הזו, לכן המשחק נוצר בטלפון הזה עם שחקני בית."))
                    .font(.footnote).multilineTextAlignment(.center)
            }
            if !model.hasSpace(kind) {
                Text(tournament ? t("You have three open tournaments. Finish or leave one before creating another.", "יש לכם שלושה טורנירים פתוחים. סיימו או עזבו אחד מהם לפני יצירת טורניר נוסף.")
                     : t("You have three open games. Choose Finish in one of Your games to make room for a new one.", "יש לכם שלושה משחקים פתוחים. בחרו סיום באחד מהמשחקים שלכם כדי לפנות מקום למשחק חדש."))
                    .multilineTextAlignment(.center)
            }
            action(tournament ? t("Create room", "יצירת חדר") : t("Create game", "יצירת משחק"), color: MPStyle.blue) { createRoom(kind) }
                .disabled(!model.connected || model.busy)
            if !settingsOnly && !tournament {
                MPXDivider()
                Text(t("Or join with a code", "או הצטרפו באמצעות קוד")).font(.headline)
                HStack {
                    TextField(t("6-character code", "קוד בן 6 תווים"), text: joinBinding(kind)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.title3.bold()).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight)
                    Button(t("Join", "הצטרפות")) { Task { await model.join(kind, joinCodes[kind.rawValue] ?? "") } }
                        .font(.headline).padding(14).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 14)).disabled(model.busy)
                }
            }
        }
    }
    /// The friendly game type as an index: the game modes, then team play.
    private var friendlyTypeBinding: Binding<Int> {
        Binding(get: { friendlyTeam ? MPGameMode.allCases.count : (MPGameMode.allCases.firstIndex(of: friendlyMode) ?? 0) }, set: { value in
            if value >= MPGameMode.allCases.count {
                friendlyTeam = true
            } else {
                friendlyTeam = false
                friendlyMode = MPGameMode.allCases[value]
                model.preferences.setGameMode(.friendly, friendlyMode)
            }
            model.preferences.defaults.set(friendlyTeam, forKey: "modern.pong.v2.friendlyTeamPlay")
        })
    }
    @ViewBuilder private func tournamentChoices(_ table: Int) -> some View {
        Text(t("Tournament format", "שיטת הטורניר")).font(.headline)
        Picker(t("Tournament format", "שיטת הטורניר"), selection: Binding(get: { tournamentFormat }, set: { tournamentFormat = $0; model.preferences.knockoutFormat = $0 == .knockout })) {
            ForEach(MPTournamentFormat.allCases, id: \.self) { Text($0.title(he)).tag($0) }
        }.pickerStyle(.segmented)
        if tournamentFormat == .knockout {
            let limit = table == 2 ? MPKnockout.maxPairPlayers : MPKnockout.maxPlayers
            // Android selector "Players" (catalog key) with its value.
            Stepper(t("Players", "שחקנים") + ": \(min(knockoutCapacity, limit))",
                    value: Binding(get: { min(knockoutCapacity, limit) }, set: { knockoutCapacity = $0; model.preferences.knockoutPlayers = $0 }), in: 2...limit).font(.headline)
            Text(table == 2 ? t("Pairs are drawn each round (a random bye when the number is odd); winners go through.", "בכל סיבוב מוגרלים זוגות (כשהמספר אי־זוגי, מישהו עולה בהגרלה ללא משחק); המנצחים עולים.")
                 : t("Any number of players: every round is split into tables of 4 and 3 (a table of 2 only when there is no other way, like 5 = 3 + 2). The players going through play the next round, until one champion is left.", "כל מספר של שחקנים: כל סיבוב מתחלק לשולחנות של 4 ושל 3 (שולחן של 2 רק כשאין ברירה, כמו 5 = 3 + 2). מי שעולים משחקים בסיבוב הבא, עד שנשאר אלוף אחד."))
                .font(.footnote).multilineTextAlignment(.center)
            if table > 2 {
                Text(t("Going through from each table", "עולים מכל שולחן")).font(.headline)
                Picker(t("Going through from each table", "עולים מכל שולחן"), selection: Binding(get: { advance }, set: { advance = $0; model.preferences.advance = $0 })) {
                    Text(t("1 · the winner", "1 · המקום הראשון")).tag(1)
                    Text(t("2 · the top two", "2 · שני המקומות הראשונים")).tag(2)
                }.pickerStyle(.segmented)
                Text(advanceHelp).font(.footnote).multilineTextAlignment(.center)
            }
        } else {
            Stepper(t("Players", "שחקנים") + ": \(capacity)", value: $capacity, in: 2...8).font(.headline)
            Text(t("Tables of 3 or 4: every two players share at least one table and everyone plays about the same number of tables. Places earn points: 1st 3, 2nd 2, 3rd 1, 4th 0.", "שולחנות של 3 או 4: כל שני שחקנים נפגשים לפחות בשולחן אחד וכולם משחקים כמעט אותו מספר שולחנות. נקודות לפי מקום: ראשון 3, שני 2, שלישי 1, רביעי 0."))
                .font(.footnote).multilineTextAlignment(.center)
            Text(t("Play the whole schedule", "משחקים את כל התוכנית")).font(.headline)
            Picker(t("Play the whole schedule", "משחקים את כל התוכנית"), selection: $legs) { Text(t("Once", "פעם אחת")).tag(1); Text(t("Twice", "פעמיים")).tag(2) }.pickerStyle(.segmented)
            Stepper(t("Standings points per win (pairs)", "נקודות בטבלה לכל ניצחון (זוגות)") + ": \(winPoints)", value: $winPoints, in: 1...5).font(.headline)
        }
    }
    private var advanceHelp: String {
        if advance != 2 { return t("Only the table's winner goes through.", "רק המקום הראשון בכל שולחן עולה.") }
        if tournamentMode == .elimination { return t("The table plays until two players are left; both go through.", "משחקים עד שנשארים שני שחקנים בשולחן, ושניהם עולים.") }
        return t("The winner and the runner-up go through. A tie for second place is settled by a one-point tie-break.", "המקום הראשון והמקום השני עולים. תיקו על המקום השני מוכרע בשובר שוויון של נקודה אחת.")
    }
    private func tableBinding(_ kind: MPSessionKind) -> Binding<Int> {
        Binding(get: { kind == .tournament ? tournamentTable : friendlyTable }, set: { value in
            if kind == .tournament { tournamentTable = value } else { friendlyTable = value }
            model.preferences.setTableSize(kind, value)
        })
    }
    private func modeBinding(_ kind: MPSessionKind) -> Binding<MPGameMode> {
        Binding(get: { kind == .tournament ? tournamentMode : friendlyMode }, set: { value in
            if kind == .tournament { tournamentMode = value } else { friendlyMode = value }
            model.preferences.setGameMode(kind, value)
        })
    }
    private func joinBinding(_ kind: MPSessionKind) -> Binding<String> {
        Binding(get: { joinCodes[kind.rawValue] ?? "" }, set: { joinCodes[kind.rawValue] = String($0.uppercased().prefix(6)) })
    }
    private func createRoom(_ kind: MPSessionKind) {
        let tournament = kind == .tournament
        let table = tournament ? tournamentTable : friendlyTable
        let mode = tournament ? tournamentMode : friendlyMode
        let format: MPTournamentFormat = tournament ? tournamentFormat : .roundRobin
        let limit = table == 2 ? MPKnockout.maxPairPlayers : MPKnockout.maxPlayers
        let players = format == .knockout ? min(knockoutCapacity, limit) : capacity
        let target = formTarget
        Task {
            // Android sends a friendly room legs 1 and win points 3 (its form has no such selectors).
            let roomLegs = kind == .friendly ? 1 : legs
            let roomWin = kind == .friendly ? 3 : winPoints
            await model.create(kind, capacity: players, legs: roomLegs, winPoints: roomWin, target: target, format: format,
                               tableSize: table, gameMode: mode, advance: advance)
            if model.error == nil { section = nil; creatingTournament = false }
        }
    }
    /// Android PlayActivity.history (5c1aa4d): "Saved games (n):" / "Saved tournaments (n):", newest first.
    private func roomSection(_ kind: MPSessionKind) -> some View {
        let key = kind.path, open = expanded.contains(key)
        let entries = model.rooms.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
        let title = (kind == .friendly ? t("Saved games", "משחקים שמורים") : t("Saved tournaments", "טורנירים שמורים")) + " (\(entries.count)):"
        let kindFill: Color = kind == .friendly ? Color(red: 216 / 255, green: 244 / 255, blue: 252 / 255) : Color(red: 241 / 255, green: 224 / 255, blue: 251 / 255)
        let fill: Color = open ? kindFill : Color.clear
        return VStack(spacing: open ? gap : 0) {
            expandHeader(title, open: open, fill: MPXMenu.saved) { toggle(key) }
            if open {
                if entries.isEmpty { Text(t("Nothing here yet. Start one above!", "עוד אין כאן משחקים. אפשר להתחיל למעלה!")).multilineTextAlignment(.center).padding(12) }
                ForEach(entries) { s in
                    Button { section = nil; model.enter(s) } label: {
                        Text(roomTitle(s)).font(.headline).frame(maxWidth: .infinity, minHeight: 64)
                    }.buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
        .padding(open ? 14 : 0)
        .background(fill, in: RoundedRectangle(cornerRadius: 18))
    }
    /// Android RoomBook.title.
    func roomTitle(_ s: MPSession) -> String { (s.kind == .tournament ? t("Tournament", "טורניר") : t("Friendly game", "משחק ידידות")) + " (\(s.code))" }

    // ---- classic match screen ---------------------------------------------------------------------------------------------
    private var game: some View {
        VStack(spacing: 0) {
            if model.crossScene != nil { crossMatchScreen } else { classicMatchScreen }
        }
    }
    private var classicMatchScreen: some View {
        VStack(spacing: 0) {
            HStack { Text(model.identity?.name ?? t("You", "אתם")).lineLimit(1); Spacer(); Text(MPMatchText.score(model.childScore, model.opponentScore)).font(.title.bold()).monospacedDigit(); Spacer(); Text(opponentName).lineLimit(1) }.font(.headline).padding(.horizontal, 18).padding(.vertical, 8)
            if model.session == nil {
                Button { if !model.paused { model.togglePause() }; showGameSettings = true } label: { Label(t("Settings", "הגדרות"), systemImage: "gearshape.fill").font(.headline).padding(10) }
            }
            if let scene = model.scene {
                SpriteView(scene: scene).id(ObjectIdentifier(scene))
                    .accessibilityLabel(t("Table tennis court. Your side is at the bottom. Beginner automatically hits when your paddle is in place. Other levels use taps or swipes.", "מגרש פינג פונג. הצד שלכם בתחתית. במתחילים מציבים את המחבט והוא חובט אוטומטית. ברמות האחרות מקישים או מחליקים כדי לחבוט."))
                    .overlay(alignment: .bottom) { Text(gameStatus).font(.callout.bold()).multilineTextAlignment(.center).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 8).allowsHitTesting(false) }
            }
        }
    }
    private var opponentName: String {
        if let s = model.session, let m = model.fixture { return s.participants[m.a == model.userID ? m.b : m.a]?.name(hebrew: he) ?? "" }; return model.selectedPlayer.name(hebrew: he)
    }
    /// Android PrivateMatchActivity status: a room match is prefixed with the knockout stage and its control level.
    private var gameStatus: String {
        guard let s = model.session, let m = model.fixture else { return gameStatusText }
        let prefix = (s.knockout ? model.matchStage(s, m) + " · " : "") + MPControlChoice.title(s.difficulty, hebrew: he) + " · "
        return prefix + model.classicRoomStatus(opponentName)
    }
    private var gameStatusText: String {
        if model.paused { return t("Paused", "המשחק מושהה") }
        switch model.status {
        case "WAITING": return t("Waiting for the other player to return…", "ממתינים לחזרת השחקן השני…")
        case "TAP_SERVE": return t("Tap a point on the table to aim your serve", "געו בנקודה בשולחן כדי לכוון את ההגשה")
        case "SWIPE_SERVE": return t("Swipe forward through the ball to serve", "החליקו קדימה דרך הכדור כדי להגיש")
        case "RETURN_BALL": return t("Return the ball", "החזירו את הכדור")
        case "AUTO_HINT": return t("Move your paddle to the ball on your side. It hits automatically!", "הזיזו את המחבט אל הכדור בצד שלכם. החבטה אוטומטית!")
        case "NET_FAULT": return t("The ball hit the net", "הכדור פגע ברשת")
        case "OUT_FAULT": return t("The ball landed outside", "הכדור נחת בחוץ")
        case "SECOND_BOUNCE": return t("Two bounces — point", "שתי קפיצות — נקודה")
        case "INVALID_SERVE": return t("The serve must bounce on both sides", "ההגשה חייבת לקפוץ בשני הצדדים")
        default: return t("Tap to return · Swipe diagonally to aim", "נגיעה להחזרה · החלקה באלכסון לכיוון")
        }
    }
    private var gameSettings: some View {
        NavigationStack { ScrollView { VStack(spacing: 18) {
            if model.practice {
                Text(t("Minik level", "הרמה של מיניק")).font(.headline)
                Picker(t("Minik level", "הרמה של מיניק"), selection: $model.practiceLevel) {
                    Text(t("Beginner", "מתחילים")).tag(MPLevel.beginner)
                    Text(t("Easy", "קלה")).tag(MPLevel.easy); Text(t("Medium", "בינונית")).tag(MPLevel.medium)
                    Text(t("Hard", "קשה")).tag(MPLevel.hard); Text(t("Super hard", "סופר קשה")).tag(MPLevel.superHard)
                }.pickerStyle(.menu).font(.title3.bold())
                Text(t("Beginner hits automatically when your paddle is in place. Easy, Medium and Hard use forgiving taps and diagonal swipes. Super hard requires precise swipes.", "במתחילים המחבט חובט אוטומטית כשהוא במקום. קל, בינוני וקשה משתמשים בנגיעות ובהחלקות אלכסוניות סלחניות. סופר קשה דורש החלקות מדויקות.")).multilineTextAlignment(.center)
            } else { controls }
            action(t("Start a new game", "התחלת משחק חדש")) { model.startSingle(practice: model.practice); showGameSettings = false }
            action(t("Continue game", "המשך המשחק"), color: MPStyle.mint) { showGameSettings = false }
        }.padding(24) }.navigationTitle(t("Settings", "הגדרות")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showGameSettings = false } } } }
    }

    // ---- classic guide (Simple experience) ----------------------------------------------------------------------------------
    private var guide: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape { HStack(spacing: 8) { guideCourt; ScrollView { guideControls }.frame(width: min(350, geometry.size.width * 0.46)) } }
                else { VStack(spacing: 8) { if model.scene != nil { guideCourt.frame(maxHeight: geometry.size.height * 0.48) }; ScrollView { guideControls } } }
            }.padding(.horizontal, 12).padding(.bottom, 12)
        }
    }
    @ViewBuilder private var guideCourt: some View {
        if let scene = model.scene { SpriteView(scene: scene).id(ObjectIdentifier(scene)).clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(model.tutorialPhase == .attempt) }
        else { Image("mp_minik_motion_ready").resizable().scaledToFit().frame(maxHeight: 220).accessibilityHidden(true) }
    }
    private var guideControls: some View {
        VStack(spacing: 12) {
            Text("\(model.tutorialStep.rawValue + 1) / \(MPTutorialStep.allCases.count)").font(.caption.bold())
            Text(model.tutorialStep.title(he)).font(.title3.bold()).multilineTextAlignment(.center)
            Text(model.tutorialStep.instruction(he)).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if model.tutorialPhase == .demonstration || model.tutorialPhase == .attempt {
                Text(model.tutorialPhase == .demonstration ? t("Watch how it’s done", "צפו איך עושים את זה") : t("Your turn!", "עכשיו תורכם!"))
                    .font(.headline).foregroundStyle(MPStyle.pink).multilineTextAlignment(.center)
            }
            if model.tutorialPhase == .feedback {
                Label(guideFeedback, systemImage: model.tutorialSuccess ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill").font(.headline).foregroundStyle(model.tutorialSuccess ? Color.green : MPStyle.pink)
            }
            action(t("Show me", "הראו לי"), color: MPStyle.lilac) { model.tutorialStart(demo: true) }
            action(model.tutorialPhase == .feedback ? t("Try again", "נסו שוב") : t("Try it yourself", "נסו בעצמכם"), color: MPStyle.mint) { model.tutorialStart(demo: false) }
            if model.tutorialPhase == .explanation || model.tutorialPhase == .feedback { action(t("Next", "הבא")) { model.tutorialNext() } }
            action(t("To the game", "למשחק")) { model.guideToGame() }
            Toggle(t("Don’t show the guide automatically", "לא להציג את ההדרכה באופן אוטומטי"), isOn: $model.skipGuide).font(.callout).padding(.vertical, 8)
        }.padding(.horizontal, 4).padding(.bottom, 12)
    }
    private var guideFeedback: String {
        if model.tutorialStep == .autoReturn {
            return model.tutorialSuccess ? t("Great positioning! Your paddle hit automatically and returned the ball to Minik.", "מיקום מצוין! המחבט חבט אוטומטית והחזיר את הכדור למיניק.") :
                t("Move your paddle into the incoming ball’s path on your side. You can get there early and lift your finger; no tap timing is needed.", "הזיזו את המחבט למסלול הכדור בצד שלכם. אפשר להגיע מוקדם ולהרים את האצבע — אין צורך לתזמן הקשה.")
        }
        return model.tutorialSuccess ? t("Well done! The ball landed in the right area.", "כל הכבוד! הכדור נחת באזור הנכון.") : t("Try again. Watch the timing and where the ball lands.", "נסו שוב. שימו לב לתזמון ולמקום שבו הכדור נוחת.")
    }
    private var help: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text(t("Serve", "הגשה")).font(.title2.bold())
            Text(t("Tap any point on the table to aim your serve. The first bounce is on your side; the second is on the opponent’s side.", "געו בכל נקודה בשולחן כדי לכוון אליה את ההגשה. הקפיצה הראשונה בצד שלכם והשנייה בצד היריב."))
            Text(t("Return and aim", "החזרה וכיוון")).font(.title2.bold())
            Text(t("Tap when the ball reaches your paddle for a forgiving return that keeps its natural sideways direction. Swipe diagonally forward and left or right to choose the landing side, including a wide cross-table shot.", "געו כשהכדור מגיע למחבט כדי להחזיר בסלחנות ולשמור על כיוון התנועה לצדדים. החליקו באלכסון קדימה ושמאלה או ימינה כדי לבחור את צד הנחיתה, גם לקצה הנגדי של השולחן."))
            Text(t("Beginner, Standard and Pro", "מתחילים, שליטה רגילה ומקצוענים")).font(.title2.bold())
            Text(t("Beginner is the default: move the paddle into the ball’s path and it hits automatically. Standard allows taps and forgiving diagonal swipes. Pro requires precise swipe timing, direction and power. House players have their own power, forehand, backhand and serve skills.", "מתחילים היא ברירת המחדל: מזיזים את המחבט למסלול הכדור והוא חובט אוטומטית. שליטה רגילה מאפשרת נגיעות והחלקות אלכסוניות סלחניות. שליטת מקצוענים דורשת דיוק בתזמון, בכיוון ובעוצמה. לכל שחקן בית כישורים משלו בעוצמה, בכף יד, בגב יד ובהגשה."))
        }.padding(24) }.navigationTitle(t("How to play", "איך משחקים")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showHelp = false } } } }
    }

    // ---- results ----------------------------------------------------------------------------------------------------------
    private var result: some View {
        ScrollView { VStack(spacing: 24) {
            // A room match shows its result card over the court instead (roomResultCard).
            if let result = model.result {
                Image(systemName: result.won ? "trophy.fill" : "hand.thumbsup.fill").font(.system(size: 72)).foregroundStyle(result.won ? .orange : MPStyle.pink).padding(.top, 32)
                Text(result.won ? t("You won!", "ניצחתם!") : t("Good game!", "משחק טוב!")).font(.largeTitle.bold())
                Text("\(result.playerPoints) – \(result.opponentPoints)").font(.system(size: 46, weight: .bold, design: .rounded)).environment(\.layoutDirection, .leftToRight)
                action(t("Back", "חזרה"), color: MPStyle.mint) { model.back() }
            }
        }.frame(maxWidth: 540).padding(24).frame(maxWidth: .infinity) }
    }
    /// A finished room match: its room and fixture while the result shows.
    private var roomResult: (MPSession, MPFixture)? {
        guard model.route == .result, let s = model.session, let m = model.fixture else { return nil }
        return (s, m)
    }
    /// Android PrivateMatchActivity result (1dbfe33 MatchResultDialog) over the court: the headline, every player with their
    /// score in finishing order, the table's final duel, and one action.
    private func roomResultCard(_ s: MPSession, _ fixture: MPFixture) -> some View {
        let m = s.matches[fixture.id] ?? fixture
        func name(_ id: String) -> String { s.participants[id]?.name(hebrew: he) ?? "?" }
        // Android `placement.ifEmpty { players.sortedByDescending(scoreOf) }`: a stable sort, so equal scores keep seat order.
        var order = m.placement
        if order.isEmpty {
            order = m.players.enumerated().sorted { a, b in
                let left = m.scoreOf(a.element), right = m.scoreOf(b.element)
                return left != right ? left > right : a.offset < b.offset
            }.map(\.element)
        }
        var note = ""
        if let duel = s.matches[MPRules.duelId(m.id)] {
            note = t("Final duel: ", "קרב גמר: ") + (duel.phase == .finished ? MPMatchText.result(name(duel.a), duel.scoreA, duel.scoreB, name(duel.b))
                                                                       : MPMatchText.pair(name(duel.a), name(duel.b)))
        }
        let close = s.complete ? (s.knockout ? t("View bracket", "לעץ הטורניר") : t("Done", "סיום")) : t("Continue", "המשך")
        return MPXResultCard(title: MPCompletionText.matchHeadline(s, fixture, model.userID, hebrew: he),
                             rows: order.map { MPXResultRow(name: name($0), score: m.scoreOf($0), winner: $0 == m.winner) },
                             primary: .init(title: close) { model.closeResult() }, note: note)
    }
}

enum MPStyle {
    static let mint = Color(red: 185 / 255, green: 244 / 255, blue: 220 / 255)
    static let blue = Color(red: 184 / 255, green: 217 / 255, blue: 1)
    static let lilac = Color(red: 232 / 255, green: 220 / 255, blue: 1)
    static let ink = Color(red: 40 / 255, green: 45 / 255, blue: 78 / 255)
    static let pink = Color(red: 233 / 255, green: 30 / 255, blue: 99 / 255)
    static let bar = Color(red: 48 / 255, green: 72 / 255, blue: 99 / 255)
    /// Android "Learn how to play" button (255, 224, 130).
    static let yellow = Color(red: 1, green: 224 / 255, blue: 130 / 255)
}
struct MPAvatar: View {
    let character: String; let icon: Int
    var body: some View {
        Group {
            // Android BotPortrait (5c1aa4d): the character's first standing pose.
            if let pose = MPXPortrait.image(character) { Image(uiImage: pose).resizable().scaledToFit() }
            else if character == "minik" { Image("mp_minik_motion_ready").resizable().scaledToFit() }
            else if let image = Self.image(character) { Image(uiImage: image).resizable().scaledToFit() }
            else { Text(MPNames.icons[max(0, icon) % MPNames.icons.count]).font(.system(size: 48)) }
        }.accessibilityHidden(true)
    }
    private static var cache: [String: UIImage] = [:]
    private static func image(_ id: String) -> UIImage? {
        if let value = cache[id] { return value }
        guard !id.isEmpty, MPRoster.find(id) != nil, let cg = UIImage(named: "mp_bot_" + id)?.cgImage,
            let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(cg.width / 4), height: CGFloat(cg.height / 2))) else { return nil }
        let value = UIImage(cgImage: cropped); cache[id] = value; return value
    }
}

/// Android LocalizedActivity.safeContent(illustrated = true): a night-to-sand gradient under modern_surround,
/// filling the whole screen (aspect fill instead of Android's stretch, so the art keeps its proportions).
struct MPIllustratedBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 17 / 255, green: 29 / 255, blue: 57 / 255),
                                        Color(red: 29 / 255, green: 71 / 255, blue: 86 / 255),
                                        Color(red: 218 / 255, green: 182 / 255, blue: 119 / 255)],
                               startPoint: .top, endPoint: .bottom)
                Image("mp_modern_surround").resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }
        .accessibilityHidden(true)
    }
}
